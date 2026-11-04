-- Spring pickers (ticket 06):
--   beans()     `<leader>jsb`  text search for @Component/@Service/@Repository/
--                              @Configuration/@*Controller classes and @Bean
--                              functions in Kotlin and Java
--   endpoints() `<leader>jse`  @RestController/@Controller classes and their
--                              @*Mapping handlers, with the class prefix applied
--   live()      `<leader>jsl`  the Spring server's live data (sts/livedata/*)
--                              of a running app: profiles, port, beans,
--                              mappings (jump to the handler), properties
--                              (value + every source that sets it)
-- The first two need no language server: Kotlin bean/endpoint semantics are a
-- known gap of both servers, so ripgrep over the sources is the route.
local M = {}

local GLOBS = { '*.kt', '*.java' }
local STEREOTYPES = {
  Component = true,
  Service = true,
  Repository = true,
  Configuration = true,
  Controller = true,
  RestController = true,
  Bean = true,
}
local MAPPINGS = { GetMapping = 'GET', PostMapping = 'POST', PutMapping = 'PUT', DeleteMapping = 'DELETE', PatchMapping = 'PATCH', RequestMapping = '*' }

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'Spring' })
end

local function root()
  return vim.fs.root(0, { 'settings.gradle.kts', 'settings.gradle', 'gradlew', 'pom.xml', '.git' }) or vim.fn.getcwd()
end

--- files under the root holding any of `words` (ripgrep, ignoring build output)
local function files_with(dir, words)
  local argv = { 'rg', '-l', '--no-messages' }
  -- build output holds copies of sources (kapt stubs; Eclipse-model `bin/`)
  for _, d in ipairs({ 'build', 'bin', 'out', '.gradle', '.kotlin' }) do
    vim.list_extend(argv, { '-g', '!**/' .. d .. '/**' })
  end
  for _, g in ipairs(GLOBS) do
    vim.list_extend(argv, { '-g', g })
  end
  vim.list_extend(argv, { '-e', '@(' .. table.concat(words, '|') .. ')\\b', dir })
  local r = vim.system(argv, { text = true }):wait()
  return vim.split(vim.trim(r.stdout or ''), '\n', { trimempty = true })
end

local function lowerfirst(s)
  return s:sub(1, 1):lower() .. s:sub(2)
end

--- first string literal in an annotation's arguments (`value`/`path` or positional)
local function annotation_path(args)
  if not args then
    return nil
  end
  return args:match('value%s*=%s*%[?%s*"(.-)"') or args:match('path%s*=%s*%[?%s*"(.-)"') or args:match('^%s*%[?%s*"(.-)"')
end

--- Scan one source file: annotations, then the declaration they belong to.
--- @return table[] items { kind, annotation, args, name, class, line, col, file }
local function scan(file)
  local items, pending, class = {}, {}, nil
  local lines = vim.fn.readfile(file)
  for i, line in ipairs(lines) do
    for ann, args in line:gmatch('@(%u[%w]*)%s*(%b())') do
      table.insert(pending, { annotation = ann, args = args:sub(2, -2), line = i })
    end
    for ann in line:gmatch('@(%u[%w]*)%f[^%w(]') do
      if not line:match('@' .. ann .. '%s*%(') then
        table.insert(pending, { annotation = ann, line = i })
      end
    end
    local decl_class = line:match('%f[%w]class%s+(%u[%w_]*)') or line:match('%f[%w]object%s+(%u[%w_]*)')
    local decl_fun = line:match('%f[%w]fun%s+[%w_.<>]-%.?([%a_][%w_]*)%s*%(')
    local java_method = not decl_class and not decl_fun and file:match('%.java$') and line:match('^%s*[%w<>%[%],%s]-%s([%a_][%w_]*)%s*%(') or nil
    local name = decl_class or decl_fun or java_method
    if name and #pending > 0 then
      for _, p in ipairs(pending) do
        p.name = name
        p.kind = decl_class and 'class' or 'function'
        p.class = decl_class or class
        p.decl_line = i
        p.col = (line:find(name, 1, true) or 1) - 1
        p.file = file
        table.insert(items, p)
      end
      pending = {}
    elseif name then
      pending = {}
    end
    if decl_class then
      class = decl_class
    end
  end
  return items
end

local function pick(title, entries, opts)
  opts = opts or {}
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  pickers
    .new({}, {
      prompt_title = title,
      finder = finders.new_table({
        results = entries,
        entry_maker = function(e)
          return {
            value = e,
            display = e.display,
            ordinal = e.ordinal or e.display,
            filename = e.file,
            lnum = e.lnum,
            col = e.col and (e.col + 1) or nil,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = opts.previewer or conf.grep_previewer({}),
      attach_mappings = opts.attach_mappings,
    })
    :find()
end

--- @return table[] beans { display, name, kind, file, lnum, col }
function M.collect_beans(dir)
  local out = {}
  for _, file in ipairs(files_with(dir, vim.tbl_keys(STEREOTYPES))) do
    for _, it in ipairs(scan(file)) do
      if STEREOTYPES[it.annotation] then
        local bean = it.kind == 'class' and lowerfirst(it.name) or it.name
        local rel = vim.fn.fnamemodify(file, ':.')
        table.insert(out, {
          name = bean,
          kind = it.annotation,
          display = ('%-15s %-28s %s:%d'):format('@' .. it.annotation, bean, rel, it.decl_line),
          ordinal = bean .. ' ' .. it.annotation .. ' ' .. it.name .. ' ' .. rel,
          file = file,
          lnum = it.decl_line,
          col = it.col,
        })
      end
    end
  end
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

--- @return table[] endpoints { display, method, path, handler, file, lnum, col }
function M.collect_endpoints(dir)
  local out = {}
  local words = { 'RestController', 'Controller' }
  for w in pairs(MAPPINGS) do
    table.insert(words, w)
  end
  for _, file in ipairs(files_with(dir, words)) do
    local items = scan(file)
    local prefix, controllers = {}, {}
    for _, it in ipairs(items) do
      if it.kind == 'class' and it.annotation == 'RequestMapping' then
        prefix[it.name] = annotation_path(it.args) or ''
      end
      if it.kind == 'class' and (it.annotation == 'RestController' or it.annotation == 'Controller') then
        controllers[it.name] = it
      end
    end
    local rel = vim.fn.fnamemodify(file, ':.')
    for name, it in pairs(controllers) do
      table.insert(out, {
        method = '',
        path = prefix[name] or '',
        handler = name,
        display = ('%-7s %-30s %s  %s:%d'):format('@' .. it.annotation:gsub('Controller', 'Ctrl'), (prefix[name] or '') ~= '' and prefix[name] or '/', name, rel, it.decl_line),
        ordinal = name .. ' ' .. (prefix[name] or '') .. ' ' .. rel,
        file = file,
        lnum = it.decl_line,
        col = it.col,
      })
    end
    for _, it in ipairs(items) do
      local method = MAPPINGS[it.annotation]
      if method and it.kind == 'function' then
        if method == '*' then
          method = (it.args or ''):match('RequestMethod%.(%u+)') or 'ANY'
        end
        local path = (prefix[it.class or ''] or '') .. (annotation_path(it.args) or '')
        path = path == '' and '/' or path
        local handler = (it.class or '?') .. '.' .. it.name
        table.insert(out, {
          method = method,
          path = path,
          handler = handler,
          display = ('%-7s %-30s %s  %s:%d'):format(method, path, handler, rel, it.decl_line),
          ordinal = method .. ' ' .. path .. ' ' .. handler .. ' ' .. rel,
          file = file,
          lnum = it.decl_line,
          col = it.col,
        })
      end
    end
  end
  table.sort(out, function(a, b)
    return (a.path .. a.method) < (b.path .. b.method)
  end)
  return out
end

function M.beans()
  local list = M.collect_beans(root())
  if #list == 0 then
    return notify('No Spring stereotypes or @Bean functions under ' .. root(), vim.log.levels.WARN)
  end
  pick('Spring beans (text search)', list)
end

function M.endpoints()
  local list = M.collect_endpoints(root())
  if #list == 0 then
    return notify('No controllers or @*Mapping handlers under ' .. root(), vim.log.levels.WARN)
  end
  pick('Spring endpoints (text search)', list)
end

--------------------------------------------------------------------------------
-- live data

local function spring_client()
  return vim.lsp.get_clients({ name = 'spring-boot', bufnr = 0 })[1] or vim.lsp.get_clients({ name = 'spring-boot' })[1]
end

local function exec(client, command, arg, cb)
  client:request('workspace/executeCommand', { command = command, arguments = arg and { arg } or {} }, function(err, result)
    vim.schedule(function()
      cb(err, result)
    end)
  end)
end

--- `orders.currency`, `ORDERS_CURRENCY` and `orders-currency` are one property
local function relaxed(name)
  return (name or ''):lower():gsub('[^%w]', '')
end

--- @return table[] entries for the live picker
function M.live_entries(data, endpoints)
  local entries = {}
  local function add(e)
    e.ordinal = e.ordinal or e.display
    table.insert(entries, e)
  end
  for _, p in ipairs(type(data.profiles) == 'table' and data.profiles or {}) do
    add({ kind = 'profile', display = 'profile   ' .. p })
  end
  if data.port then
    add({ kind = 'port', display = 'port      ' .. tostring(data.port) })
  end
  if data.contextPath and data.contextPath ~= '' and data.contextPath ~= vim.NIL then
    add({ kind = 'context', display = 'context   ' .. tostring(data.contextPath) })
  end
  local by_route = {}
  for _, ep in ipairs(endpoints or {}) do
    by_route[ep.method .. ' ' .. ep.path] = ep
  end
  for _, m in ipairs(type(data.mappings) == 'table' and data.mappings or {}) do
    local map = m.data and m.data.map or m
    local details = map.details and map.details.map or {}
    local conditions = details.requestMappingConditions and details.requestMappingConditions.map or {}
    local function list(v)
      return v and v.myArrayList or (type(v) == 'table' and v) or {}
    end
    local methods, patterns = list(conditions.methods), list(conditions.patterns)
    if #patterns == 0 then
      -- no conditions: `{GET /orders/{id}}` (strip the outer braces only) or `/webjars/**`
      local inner = (map.predicate or ''):match('^{(.*)}$') or map.predicate or ''
      local method, path = inner:match('^(%u+) ([^,%s]+)')
      if method then
        methods, patterns = { method }, { path }
      elseif inner:match('^/') then
        patterns = { (inner:match('^[^,%s]+')) }
      end
    end
    local handler = details.handlerMethod and details.handlerMethod.map
    local handler_name = handler and handler.className and ((handler.className:match('[^.]+$') or '') .. '.' .. (handler.name or ''))
      or (type(map.handler) == 'string' and map.handler)
      or ''
    for _, path in ipairs(patterns) do
      local method = #methods > 0 and table.concat(methods, '|') or '*'
      local ep = by_route[method .. ' ' .. path]
      add({
        kind = 'mapping',
        display = ('mapping   %-7s %-30s %s'):format(method, path, handler_name),
        file = ep and ep.file,
        lnum = ep and ep.lnum,
        col = ep and ep.col,
      })
    end
  end
  for _, b in ipairs(type(data.beans) == 'table' and data.beans or {}) do
    if type(b) == 'string' and not b:find('.', 1, true) then
      add({ kind = 'bean', display = 'bean      ' .. b, name = b })
    end
  end
  -- properties: the first source holding a (relaxed) name wins
  local groups, order = {}, {}
  for _, source in ipairs(type(data.properties) == 'table' and data.properties.sources or {}) do
    for _, p in ipairs(source.properties or {}) do
      local key = relaxed(p.property)
      if not groups[key] then
        groups[key] = {}
        table.insert(order, key)
      end
      table.insert(groups[key], { source = source.sourceName, property = p.property, value = p.value })
    end
  end
  for _, key in ipairs(order) do
    local g = groups[key]
    local win = g[1]
    -- prefer the dotted spelling for the label
    local label = win.property
    for _, s in ipairs(g) do
      if s.property:find('.', 1, true) then
        label = s.property
        break
      end
    end
    local over = #g > 1 and ('  (over ' .. g[2].source .. ': ' .. tostring(g[2].value) .. ')') or ''
    add({
      kind = 'property',
      display = ('property  %s = %s  [%s]%s'):format(label, tostring(win.value), win.source, over),
      ordinal = 'property ' .. label .. ' ' .. win.property .. ' ' .. tostring(win.value),
      sources = g,
    })
  end
  return entries
end

local function show_live(label, data)
  local endpoints = M.collect_endpoints(root())
  local entries = M.live_entries(data, endpoints)
  local beans = M.collect_beans(root())
  local bean_at = {}
  for _, b in ipairs(beans) do
    bean_at[b.name] = b
  end
  for _, e in ipairs(entries) do
    if e.kind == 'bean' and bean_at[e.name] then
      e.file, e.lnum, e.col = bean_at[e.name].file, bean_at[e.name].lnum, bean_at[e.name].col
    end
  end
  local previewers = require('telescope.previewers')
  local conf = require('telescope.config').values
  local previewer = previewers.new_buffer_previewer({
    title = 'Live data',
    get_buffer_by_name = function(_, entry)
      return entry.value.file or entry.value.display
    end,
    define_preview = function(self, entry)
      local e = entry.value
      if e.file then
        -- source of a mapping's handler / a bean's declaration, at its line
        return conf.buffer_previewer_maker(e.file, self.state.bufnr, {
          bufname = self.state.bufname,
          winid = self.state.winid,
          callback = function()
            if pcall(vim.api.nvim_win_set_cursor, self.state.winid, { e.lnum, 0 }) then
              vim.api.nvim_win_call(self.state.winid, function()
                vim.cmd('normal! zz')
              end)
            end
          end,
        })
      end
      local lines
      if e.sources then
        lines = { e.sources[1].property .. ' = ' .. tostring(e.sources[1].value), '', 'Sources, highest precedence first:' }
        for _, s in ipairs(e.sources) do
          table.insert(lines, ('  %s: %s = %s'):format(s.source, s.property, tostring(s.value)))
        end
      else
        lines = { e.display }
      end
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
    end,
  })
  pick('Spring live data: ' .. label, entries, {
    previewer = previewer,
    attach_mappings = function(bufnr)
      local actions = require('telescope.actions')
      local action_state = require('telescope.actions.state')
      actions.select_default:replace(function()
        local e = action_state.get_selected_entry().value
        actions.close(bufnr)
        if e.file then
          vim.cmd.edit(vim.fn.fnameescape(e.file))
          vim.api.nvim_win_set_cursor(0, { e.lnum, e.col or 0 })
        elseif e.sources then
          notify(table.concat(vim.tbl_map(function(s)
            return ('%s: %s = %s'):format(s.source, s.property, tostring(s.value))
          end, e.sources), '\n'))
        end
      end)
      return true
    end,
  })
end

M.show_live = show_live

local ENDPOINTS = { 'profiles', 'port', 'contextPath', 'beans', 'mappings', 'properties' }

--- Actuator on the module's runtime classpath, from the spring-classpath
--- snapshot: true/false, or nil when the snapshot doesn't know the module
function M.has_actuator(dir, project_name)
  local f = io.open(require('spring-classpath').snapshot_path(dir), 'r')
  if not f then
    return nil
  end
  local ok, snap = pcall(vim.json.decode, f:read('*a'))
  f:close()
  if not ok or type(snap) ~= 'table' then
    return nil
  end
  for _, m in ipairs(snap.modules or {}) do
    if m.name == project_name then
      for _, entry in ipairs(m.runtimeClasspath or {}) do
        if vim.fs.basename(entry):match('^spring%-boot%-actuator%-%d') then
          return true
        end
      end
      return false
    end
  end
  return nil
end

--- fetch everything for one connected process, then `cb(data, err)`
function M.fetch(client, key, cb)
  local data, pending, failed = {}, #ENDPOINTS, {}
  for _, ep in ipairs(ENDPOINTS) do
    exec(client, 'sts/livedata/get', { processKey = key, endpoint = ep }, function(err, result)
      if err or result == nil or result == vim.NIL then
        table.insert(failed, ep)
      else
        data[ep] = result
      end
      pending = pending - 1
      if pending == 0 then
        cb(data, failed)
      end
    end)
  end
end

--- connect and fetch, retrying while the server's JMX connection comes up
function M.load(client, process, cb)
  local key = process.processKey
  exec(client, 'sts/livedata/connect', { processKey = key }, function()
    local tries = 0
    local function attempt()
      tries = tries + 1
      M.fetch(client, key, function(data, failed)
        if data.beans and data.mappings then
          return cb(data)
        end
        if tries < 8 then
          return vim.defer_fn(attempt, 1500)
        end
        cb(nil, failed)
      end)
    end
    attempt()
  end)
end

--- JVMs that are tooling, never an app (the server lists every local JVM)
local TOOLING = {
  'org%.gradle%.',
  'GradleDaemon',
  'GradleWrapperMain',
  'GradleWorkerMain',
  'KotlinCompileDaemon',
  'com%.intellij%.',
  'org%.eclipse%.equinox%.launcher',
  'org%.springframework%.ide%.',
  'spring%-boot%-language%-server',
  'jdk%.jcmd',
  'sun%.tools%.',
}

--- Running apps: processes our launch tagged with a project name, else every
--- listed JVM that isn't tooling. The list is empty for a moment after the
--- server starts, so an empty answer is asked again twice.
function M.apps(client, cb, tries)
  tries = tries or 0
  exec(client, 'sts/livedata/listProcesses', nil, function(err, processes)
    processes = (not err and type(processes) == 'table') and processes or {}
    local tagged, other, seen = {}, {}, {}
    for _, p in ipairs(processes) do
      local label = p.label or ''
      -- a connected process is listed once per action (connect, refresh, disconnect)
      local dup = seen[p.processKey]
      seen[p.processKey] = true
      local tool = false
      for _, pat in ipairs(TOOLING) do
        tool = tool or label:find(pat) ~= nil
      end
      if dup then
        -- already listed
      elseif p.projectName and p.projectName ~= vim.NIL then
        table.insert(tagged, p)
      elseif not tool then
        table.insert(other, p)
      end
    end
    local apps = #tagged > 0 and tagged or other
    if #apps == 0 and tries < 2 then
      return vim.defer_fn(function()
        M.apps(client, cb, tries + 1)
      end, 1000)
    end
    cb(apps)
  end)
end

function M.live(opts)
  opts = opts or {}
  local client = spring_client()
  if not client then
    return notify('Spring server not running: open an application.yml/.properties of the project first', vim.log.levels.WARN)
  end
  M.apps(client, function(processes)
    if #processes == 0 then
      return notify(
        'No running Spring Boot app visible to the Spring server (start one with <leader>Gr; it needs JMX, which <leader>Gr enables)',
        vim.log.levels.WARN
      )
    end
    local function go(process)
      if not process then
        return
      end
      local actuator = M.has_actuator(client.root_dir or root(), process.projectName)
      if actuator == false then
        return notify(
          ('%s has no Actuator (spring-boot-actuator is not on the exported runtime classpath of %s): no live data'):format(
            process.label or process.processKey,
            process.projectName or 'its module'
          ),
          vim.log.levels.WARN
        )
      end
      M.load(client, process, function(data, failed)
        if not data then
          return notify(
            ('%s answers no live data (%s): the app needs Actuator (spring-boot-starter-actuator) for beans, mappings and properties'):format(
              process.label or process.processKey,
              table.concat(failed or {}, ', ')
            ),
            vim.log.levels.WARN
          )
        end
        if opts.on_data then
          return opts.on_data(process, data)
        end
        show_live(process.label or process.processKey, data)
      end)
    end
    if #processes == 1 then
      return go(processes[1])
    end
    vim.ui.select(processes, {
      prompt = 'Spring app',
      format_item = function(p)
        return (p.label or p.processKey) .. (p.projectName and ('  [' .. p.projectName .. ']') or '')
      end,
    }, go)
  end)
end

return M
