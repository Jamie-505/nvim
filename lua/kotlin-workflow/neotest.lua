-- neotest-gradle for Kotlin/JUnit Platform projects (ticket 06):
--
-- - argv built here, never a shell string: `--tests` filters use `Outer$Inner`
--   (Gradle matches nothing for the dotted form), `--rerun` so a run always
--   executes, and debug runs add `--debug-jvm` on a free loopback port
-- - results only from JUnit XML written by this run, matched by method name or,
--   since Gradle reports `@DisplayName` and parameterized cases by display name
--   only, by display name; a parameterized method's cases become `[n]` children
--   (order = invocation index in the last XML)
-- - one `[n]` case runs in a JUnit Platform launcher JVM with the Test task's
--   exported classpath, JVM args and environment (`selectIteration`)
-- - one strategy for runs and debug: SIGINT on stop (then SIGTERM after 10 s),
--   the run marked cancelled; debug attaches through a fresh kotlin-lsp bridge
--   as soon as the JVM listens
local M = {}

local config_dir = vim.fn.stdpath('config')
M.init_script = config_dir .. '/gradle/test-export.init.gradle'
M.launcher_source = config_dir .. '/java/NvimRunIteration.java'

local PARAMETERIZED = { ParameterizedTest = true, RepeatedTest = true, TestTemplate = true }
local CANCEL_GRACE_MS = 10000

--- vim.fn for the async adapter hooks: neotest runs them in nio tasks, where a
--- plain vim.fn call after a yield raises E5560 (fast event context)
local function nio_fn()
  return require('nio').fn
end

M.kotlin_query = [[
  ((class_declaration (type_identifier) @namespace.name)) @namespace.definition
  (
    (function_declaration
      (modifiers (annotation (user_type (type_identifier) @test_marker.identifier)))
      (simple_identifier) @test.name)
    (#any-of? @test_marker.identifier "Test" "ParameterizedTest" "RepeatedTest" "TestTemplate")
  ) @test.definition
  (
    (function_declaration
      (modifiers (annotation (constructor_invocation (user_type (type_identifier) @test_marker.identifier))))
      (simple_identifier) @test.name)
    (#any-of? @test_marker.identifier "Test" "ParameterizedTest" "RepeatedTest" "TestTemplate")
  ) @test.definition
]]

local function clean(name)
  return ((name or ''):gsub('`', ''))
end

--------------------------------------------------------------------------------
-- positions

local package_cache = {}
local function package_of(path)
  local ok, st = pcall(vim.uv.fs_stat, path)
  local key = path .. ':' .. (ok and st and st.mtime.sec or 0)
  if package_cache[key] == nil then
    package_cache[key] = require('neotest-gradle.hooks.shared_utilities').get_package_name(path)
  end
  return package_cache[key]
end

--- `pkg.Outer$Inner` for a namespace node (or the namespace above a test)
local function jvm_class(node)
  local names = {}
  local n = node
  while n do
    local d = n:data()
    if d.type == 'namespace' then
      table.insert(names, 1, clean(d.handle_name or d.name))
    elseif d.type == 'file' then
      break
    end
    n = n:parent()
  end
  if #names == 0 then
    return nil
  end
  local pkg = package_of(node:data().path)
  return (pkg ~= '' and (pkg .. '.') or '') .. table.concat(names, '$')
end
M.jvm_class = jvm_class

--- the Gradle `--tests` filters for a position
local function filters(node)
  local pos = node:data()
  if pos.invocation then
    node = node:parent()
    pos = node:data()
  end
  if pos.type == 'test' then
    local cls = jvm_class(node:parent())
    return cls and { cls .. '.' .. clean(pos.handle_name) } or {}
  elseif pos.type == 'namespace' then
    return { jvm_class(node) }
  elseif pos.type == 'file' then
    local out = {}
    for _, child in ipairs(node:children()) do
      if child:data().type == 'namespace' then
        table.insert(out, jvm_class(child))
      end
    end
    return out
  end
  return {}
end
M.filters = filters

local function position_id(position, parents)
  local build_identifier = require('neotest-gradle.hooks.discover_positions.build_position_identifier')
  return (build_identifier(position, parents):gsub('^%.', ''))
end

local function build_position(file_path, source, captured)
  local pos = require('neotest-gradle.hooks.discover_positions.build_position')(file_path, source, captured)
  if pos.type ~= 'test' then
    return pos
  end
  local marker = captured['test_marker.identifier']
  pos.marker = marker and vim.treesitter.get_node_text(marker, source) or nil
  pos.parameterized = PARAMETERIZED[pos.marker or ''] or nil
  local text = vim.treesitter.get_node_text(captured['test.definition'], source)
  local header = text:sub(1, (text:find('%f[%w]fun%f[%W]') or #text))
  local display = header:match('@DisplayName%s*%(%s*"(.-)"%s*%)')
  if display then
    pos.display_name = display
    pos.name = display
  end
  pos.invocation_pattern = header:match('@ParameterizedTest%s*%(.-name%s*=%s*"(.-)"')
    or header:match('@RepeatedTest%s*%(.-name%s*=%s*"(.-)"')
  return pos
end

--- Gradle names the Test task after the source set: the segment after `src/`
local function test_task(path)
  return path:match('/src/([^/]+)/') or 'test'
end

local function module_dir(path)
  return require('neotest-gradle.hooks.find_project_directory')(path)
end

local function gradle_root(dir)
  local wrapper = vim.fs.find('gradlew', { path = dir, upward = true, type = 'file' })[1]
  return wrapper and vim.fs.dirname(wrapper), wrapper or 'gradle'
end

local function as_list(v)
  if v == nil then
    return {}
  end
  return (type(v) == 'table' and v[1] ~= nil) and v or { v }
end

local function read_xml(path)
  local text = require('neotest.lib').files.read(path)
  local ok, data = pcall(require('neotest.lib.xml').parse, text)
  return ok and data or nil
end

local function testcases_of(xml)
  local out = {}
  for _, suite in ipairs(as_list(xml and xml.testsuite)) do
    for _, case in ipairs(as_list(suite.testcase)) do
      table.insert(out, case)
    end
  end
  return out
end

local function name_pattern(p)
  return '^' .. vim.pesc(p):gsub('{[^}]*}', '.-') .. '$'
end

--- Assign a class's XML testcases to its test positions.
--- @param cases table[] testcase nodes of one class, in report order
--- @param tests table[] test positions directly in that class
--- @return {pos: table, invocation?: integer, case: table}[]
local function match_cases(cases, tests)
  local by_method, by_display, param = {}, {}, {}
  for _, t in ipairs(tests) do
    by_method[clean(t.handle_name)] = t
    if t.display_name then
      by_display[t.display_name] = t
    end
    if t.parameterized then
      table.insert(param, t)
    end
  end
  local out, counters = {}, {}
  for _, case in ipairs(cases) do
    local name = case._attr and case._attr.name or ''
    local method = name:match('^(.-)%(.*%)$')
    local t = (method and by_method[method]) or by_display[name]
    if t and not t.parameterized then
      table.insert(out, { pos = t, case = case })
    else
      local owner
      if t and t.parameterized then
        owner = t
      elseif #param == 1 then
        owner = param[1]
      else
        for _, p in ipairs(param) do
          if p.invocation_pattern and name:match(name_pattern(p.invocation_pattern)) then
            owner = p
            break
          end
        end
      end
      if owner then
        counters[owner.id] = (counters[owner.id] or 0) + 1
        table.insert(out, { pos = owner, invocation = counters[owner.id], case = case })
      end
    end
  end
  return out
end

--- direct test positions of every class in `tree`, keyed by JVM class name
local function tests_by_class(tree)
  local classes = {}
  for _, node in tree:iter_nodes() do
    local pos = node:data()
    if pos.type == 'test' and not pos.invocation then
      local cls = jvm_class(node:parent())
      if cls then
        classes[cls] = classes[cls] or {}
        table.insert(classes[cls], pos)
      end
    end
  end
  return classes
end

--- add `[n]` children under parameterized methods from the class's last XML
local function add_invocations(tree)
  local any = false
  for _, pos in tree:iter() do
    if pos.parameterized then
      any = true
      break
    end
  end
  if not any then
    return tree
  end
  local list = tree:to_list()
  local nodes_by_data = {}
  local function index(l)
    nodes_by_data[l[1]] = l
    for i = 2, #l do
      index(l[i])
    end
  end
  index(list)
  local results_dir = nil
  for cls, tests in pairs(tests_by_class(tree)) do
    local has_param = false
    for _, t in ipairs(tests) do
      has_param = has_param or t.parameterized
    end
    if has_param then
      local path = tests[1].path
      results_dir = results_dir or (module_dir(path) .. '/build/test-results/' .. test_task(path))
      local xml_path = results_dir .. '/TEST-' .. cls .. '.xml'
      if vim.uv.fs_stat(xml_path) then
        for _, m in ipairs(match_cases(testcases_of(read_xml(xml_path)), tests)) do
          if m.invocation then
            local parent = nodes_by_data[m.pos]
            table.insert(parent, {
              {
                type = 'test',
                id = m.pos.id .. '[' .. m.invocation .. ']',
                name = '[' .. m.invocation .. '] ' .. (m.case._attr.name or ''),
                path = m.pos.path,
                handle_name = m.pos.handle_name,
                invocation = m.invocation,
                method_id = m.pos.id,
              },
            })
          end
        end
      end
    end
  end
  return require('neotest.types').Tree.from_list(list, function(pos)
    return pos.id
  end)
end

function M.discover_positions(path)
  local ft = require('plenary.filetype').detect(path)
  local query = ft == 'kotlin' and M.kotlin_query or require('neotest-gradle.position_queries')[ft]
  if not query then
    return nil
  end
  local tree = require('neotest.lib').treesitter._parse_positions(path, query, {
    build_position = build_position,
    position_id = position_id,
  })
  return tree and add_invocations(tree)
end

--------------------------------------------------------------------------------
-- run specs

local function is_debug(strategy)
  return strategy == M.debug_strategy or strategy == 'dap'
end

local function error_spec(message, context)
  local file = nio_fn().tempname()
  nio_fn().writefile(vim.split(message, '\n'), file)
  context.error = message
  return { command = { 'cat', file }, context = context }
end

local function launcher_classes(export)
  local launcher_jar
  for _, entry in ipairs(export.classpath) do
    if vim.fs.basename(entry):match('^junit%-platform%-launcher') then
      launcher_jar = entry
    end
  end
  if not launcher_jar then
    return nil, 'junit-platform-launcher is not on the test runtime classpath'
  end
  local st = vim.uv.fs_stat(M.launcher_source)
  local dir = nio_fn().stdpath('cache')
    .. '/kotlin-workflow/launcher/'
    .. nio_fn().sha256(launcher_jar .. ':' .. (st and st.mtime.sec or 0)):sub(1, 12)
  if vim.uv.fs_stat(dir .. '/NvimRunIteration.class') then
    return dir
  end
  nio_fn().mkdir(dir, 'p')
  local javac = vim.fs.dirname(export.java) .. '/javac'
  local code, out = require('neotest.lib').process.run({
    javac,
    '-nowarn',
    '-d',
    dir,
    '-cp',
    table.concat(export.classpath, ':'),
    M.launcher_source,
  }, { stdout = true, stderr = true })
  if code ~= 0 then
    nio_fn().delete(dir, 'rf')
    return nil, 'compiling the launcher failed (needs JUnit Platform 1.13+ for selectIteration):\n' .. (out.stderr or '')
  end
  return dir
end

local function invocation_spec(node, debug)
  local pos = node:data()
  local method_node = node:parent()
  local cls = jvm_class(method_node:parent())
  local method = clean(method_node:data().handle_name)
  local dir = module_dir(pos.path)
  local root, gradlew = gradle_root(dir)
  local task = test_task(pos.path)
  local context = {
    kotlin_workflow = true,
    invocation = pos.invocation,
    position_id = pos.id,
    method_id = pos.method_id,
    started = os.time(),
  }
  local state = nio_fn().stdpath('state') .. '/kotlin-workflow'
  nio_fn().mkdir(state, 'p')
  local export_path = state .. '/test-export-' .. nio_fn().sha256(dir .. ':' .. task):sub(1, 12) .. '.json'
  os.remove(export_path)
  local code, out = require('neotest.lib').process.run({
    gradlew,
    '-q',
    '-p',
    root,
    '-I',
    M.init_script,
    '-Pnvim.test.export=' .. export_path,
    '-Pnvim.test.dir=' .. dir,
    '-Pnvim.test.task=' .. task,
    '--no-configuration-cache',
    '--console=plain',
    'nvimTestExport',
  }, { stdout = true, stderr = true })
  local f = code == 0 and io.open(export_path, 'r')
  if not f then
    return error_spec('Test classpath export failed:\n' .. (out.stdout or '') .. (out.stderr or ''), context)
  end
  local export = vim.json.decode(f:read('*a'))
  f:close()
  local classes, err = launcher_classes(export)
  if not classes then
    return error_spec(err, context)
  end
  local argv = { export.java }
  vim.list_extend(argv, export.jvmArgs or {})
  if debug then
    local port = require('kotlin-workflow.debug').free_port()
    table.insert(argv, '-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=127.0.0.1:' .. port)
    context.debug = { name = method .. ' ' .. pos.name }
  end
  vim.list_extend(argv, {
    '-cp',
    classes .. ':' .. table.concat(export.classpath, ':'),
    'NvimRunIteration',
    cls,
    method,
    tostring(pos.invocation - 1),
  })
  return {
    command = argv,
    cwd = export.workingDir,
    env = next(export.environment or {}) and export.environment or nil,
    context = context,
  }
end

--- results directories a run of `pos` writes JUnit XML into
local function results_dirs(pos, dir, task)
  if pos.type ~= 'dir' then
    return { dir .. '/build/test-results/' .. task }
  end
  local out = {}
  for _, found in
    ipairs(vim.fs.find(function(name, parent)
      return name == 'test-results' and vim.fs.basename(parent) == 'build'
    end, { path = dir, type = 'directory', limit = math.huge }))
  do
    table.insert(out, found .. '/' .. task)
  end
  return out
end

function M.build_spec(args)
  local node = args.tree
  local pos = node:data()
  local debug = is_debug(args.strategy)
  if pos.invocation then
    return invocation_spec(node, debug)
  end
  local dir = pos.type == 'dir' and pos.path or module_dir(pos.path)
  if not dir then
    return nil
  end
  local _, gradlew = gradle_root(dir)
  local task = pos.type == 'dir' and 'test' or test_task(pos.path)
  local argv = { gradlew, '--project-dir', dir, '-I', M.init_script, '--console=plain', task, '--rerun' }
  for _, filter in ipairs(filters(node)) do
    vim.list_extend(argv, { '--tests', filter })
  end
  local context = {
    kotlin_workflow = true,
    started = os.time(),
    results_dirs = results_dirs(pos, dir, task),
    task = task,
  }
  if debug then
    local port = require('kotlin-workflow.debug').free_port()
    vim.list_extend(argv, { '--debug-jvm', '-Pnvim.test.debugPort=' .. port })
    context.debug = { name = 'Test ' .. pos.name }
  end
  return { command = argv, cwd = dir, context = context }
end

--------------------------------------------------------------------------------
-- results

local function failure_of(case, path)
  local node = case.failure or case.error
  if not node then
    return nil
  end
  local attr = node._attr or {}
  local trace = type(node[1]) == 'string' and node[1] or ''
  local line
  local base = vim.fs.basename(path)
  for file, n in trace:gmatch('%(([^%(%):]+):(%d+)%)') do
    if file == base then
      line = tonumber(n) - 1
      break
    end
  end
  local message = attr.message or attr.type or 'failed'
  return { message = message, line = line }
end

local function status_of(case)
  if case.failure or case.error then
    return 'failed'
  end
  if case.skipped ~= nil then
    return 'skipped'
  end
  return 'passed'
end

local function invocation_results(spec, result, tree)
  local ctx = spec.context
  local text = table.concat(nio_fn().readfile(result.output), '\n')
  local status, display
  for s, _, name in text:gmatch('NVIM_RESULT (%u+)\t([^\t]*)\t([^\r\n]*)') do
    status = s == 'SUCCESSFUL' and 'passed' or (s == 'ABORTED' and 'skipped' or 'failed')
    display = name
  end
  local errors = {}
  local pos = tree:data()
  for block in text:gmatch('NVIM_FAILURE\r?\n(.-)NVIM_FAILURE_END') do
    local line
    for file, n in block:gmatch('%(([^%(%):]+):(%d+)%)') do
      if file == vim.fs.basename(pos.path) then
        line = tonumber(n) - 1
        break
      end
    end
    table.insert(errors, { message = block:match('^[^\r\n]*'), line = line })
  end
  if not status then
    return {
      [ctx.position_id] = {
        status = 'failed',
        short = ctx.error or 'the launcher ran no test (exit ' .. tostring(result.code) .. ') - see the output',
        output = result.output,
      },
    }
  end
  return {
    [ctx.position_id] = {
      status = status,
      short = display,
      errors = errors,
      output = result.output,
    },
  }
end

function M.results(spec, result, tree)
  local ctx = spec.context or {}
  if not ctx.kotlin_workflow then
    return require('neotest-gradle.hooks.collect_results')(spec, result, tree)
  end
  local out = {}
  if ctx.cancelled then
    for _, pos in tree:iter() do
      if pos.type == 'test' then
        out[pos.id] = { status = 'skipped', short = 'cancelled (<leader>Ts)', output = result.output }
      end
    end
    return out
  end
  if ctx.invocation then
    return invocation_results(spec, result, tree)
  end
  local files = {}
  for _, dir in ipairs(ctx.results_dirs or {}) do
    for name, type in vim.fs.dir(dir) do
      if type == 'file' and name:match('^TEST%-.*%.xml$') then
        local path = dir .. '/' .. name
        local st = vim.uv.fs_stat(path)
        if st and st.mtime.sec >= ctx.started then
          table.insert(files, path)
        end
      end
    end
  end
  if #files == 0 then
    for _, pos in tree:iter() do
      if pos.type == 'test' then
        out[pos.id] = {
          status = 'failed',
          short = 'no JUnit XML from this run - see the output panel',
          output = result.output,
        }
      end
    end
    return out
  end
  local classes = tests_by_class(tree)
  local cases_by_class = {}
  for _, file in ipairs(files) do
    for _, case in ipairs(testcases_of(read_xml(file))) do
      local cls = case._attr and case._attr.classname
      if cls then
        cases_by_class[cls] = cases_by_class[cls] or {}
        table.insert(cases_by_class[cls], case)
      end
    end
  end
  local owners = {}
  for cls, cases in pairs(cases_by_class) do
    for _, m in ipairs(match_cases(cases, classes[cls] or {})) do
      local status = status_of(m.case)
      local err = failure_of(m.case, m.pos.path)
      local r = {
        status = status,
        short = err and err.message or nil,
        errors = err and { err } or nil,
        output = result.output,
      }
      if m.invocation then
        r.short = (m.case._attr.name or '') .. (err and (': ' .. err.message) or '')
        out[m.pos.id .. '[' .. m.invocation .. ']'] = r
        local o = owners[m.pos.id] or { passed = 0, failed = 0, skipped = 0, errors = {} }
        o[status] = o[status] + 1
        if err then
          table.insert(o.errors, err)
        end
        owners[m.pos.id] = o
      else
        out[m.pos.id] = r
      end
    end
  end
  for id, o in pairs(owners) do
    local status = o.failed > 0 and 'failed' or (o.passed > 0 and 'passed' or 'skipped')
    out[id] = {
      status = status,
      short = ('%d passed, %d failed, %d skipped'):format(o.passed, o.failed, o.skipped),
      errors = o.errors,
      output = result.output,
    }
  end
  if next(out) == nil then
    -- Nothing matched: the run started before neotest had discovered the file's
    -- tests (the file node comes first). Without this the file shows "skipped"
    -- even when every case passed; give the run's root the XML's verdict.
    local n = { passed = 0, failed = 0, skipped = 0 }
    for _, cases in pairs(cases_by_class) do
      for _, case in ipairs(cases) do
        local s = status_of(case)
        n[s] = (n[s] or 0) + 1
      end
    end
    if n.passed + n.failed + n.skipped > 0 then
      out[tree:data().id] = {
        status = n.failed > 0 and 'failed' or (n.passed > 0 and 'passed' or 'skipped'),
        short = ('%d passed, %d failed, %d skipped (tests not discovered yet: rerun to mark each)'):format(n.passed, n.failed, n.skipped),
        output = result.output,
      }
    end
  end
  return out
end

--------------------------------------------------------------------------------
-- strategy

local running = {}

local function process(spec)
  local nio = require('nio')
  local ctx = spec.context
  local output_path = nio.fn.tempname()
  local fd = assert(io.open(output_path, 'w'))
  local finish = nio.control.future()
  local code
  local subscribers = {}
  local tail, attached = '', false
  local job = nio.fn.jobstart(spec.command, {
    cwd = spec.cwd,
    env = spec.env,
    pty = true,
    height = 40,
    width = 200,
    on_stdout = function(_, data)
      local chunk = table.concat(data, '\n')
      if chunk == '' or code ~= nil then
        return
      end
      fd:write(chunk)
      for _, q in ipairs(subscribers) do
        q.put_nowait(chunk)
      end
      if ctx.debug and not attached then
        tail = (tail .. chunk):sub(-1000)
        local port = require('kotlin-workflow.debug').listening_port(tail)
        if port then
          attached = true
          vim.schedule(function()
            require('kotlin-workflow.debug').attach(port, ctx.debug.name)
          end)
        end
      end
    end,
    on_exit = function(_, c)
      code = c
      fd:close()
      finish.set()
    end,
  })
  if job <= 0 then
    fd:write('could not start: ' .. vim.inspect(spec.command))
    fd:close()
    code = 1
    finish.set()
  end
  local pid = job > 0 and nio.fn.jobpid(job) or nil
  if pid and vim.fs.basename(spec.command[1]) == 'gradlew' then
    -- the registry drops it once the process is gone
    require('kotlin-workflow.jobs').add({ pid = pid, kind = 'gradle-client', label = 'test ' .. (ctx.task or ''), root = spec.cwd })
  end
  local instance
  instance = {
    is_complete = function()
      return code ~= nil
    end,
    output = function()
      return output_path
    end,
    stop = function()
      if code ~= nil or not pid then
        return
      end
      ctx.cancelled = true
      vim.uv.kill(pid, 'sigint')
      vim.defer_fn(function()
        if code == nil then
          vim.uv.kill(pid, 'sigterm')
        end
      end, CANCEL_GRACE_MS)
    end,
    output_stream = function()
      local queue = nio.control.queue()
      table.insert(subscribers, queue)
      return function()
        local data = nio.first({ queue.get, finish.wait })
        if data then
          return data
        end
        if queue.size() ~= 0 then
          return queue.get()
        end
      end
    end,
    attach = function()
      vim.schedule(function()
        vim.cmd('botright split ' .. vim.fn.fnameescape(output_path))
      end)
    end,
    result = function()
      if code == nil then
        finish.wait()
      end
      running[instance] = nil
      return code
    end,
  }
  running[instance] = true
  return instance
end

--- default strategy: ours for Gradle/launcher specs, neotest's otherwise
function M.run_strategy(spec, context)
  if spec.context and spec.context.kotlin_workflow then
    return process(spec)
  end
  return require('neotest.client.strategies.integrated')(spec, context)
end

--- debug strategy: build_spec has added JDWP; attach once the JVM listens
function M.debug_strategy(spec, context)
  if spec.context and spec.context.kotlin_workflow then
    return process(spec)
  end
  return require('neotest.client.strategies.dap')(spec, context)
end

--- number of Kotlin test runs in progress
function M.active_count()
  local n = 0
  for _ in pairs(running) do
    n = n + 1
  end
  return n
end

--- stop every Kotlin test run (SIGINT, SIGTERM after 10 s); else neotest's stop
function M.stop()
  local any = false
  for instance in pairs(running) do
    any = true
    instance.stop()
  end
  if not any then
    require('neotest').run.stop()
  end
end

--- neotest consumer: rediscover a file after a run so new `[n]` children
--- appear (the XML they come from didn't exist when the file was parsed)
function M.consumer(client)
  M.client = client
  client.listeners.results = function(adapter_id, results, partial)
    if partial or not vim.startswith(adapter_id, 'gradle-test:') then
      return
    end
    local files = {}
    for id in pairs(results) do
      local node = client:get_position(id, { adapter = adapter_id })
      local pos = node and node:data()
      if pos and pos.parameterized then
        files[pos.path] = true
      end
    end
    for file in pairs(files) do
      client:_update_positions(file, { adapter = adapter_id })
    end
  end
  return {}
end

return M
