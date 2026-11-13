-- Pick an IntelliJ run configuration and run it through `gradlew` in a terminal.
--
-- Read from `<root>/.run/*.run.xml`, `<root>/*/.run/*.run.xml`,
-- `<root>/.idea/runConfigurations/*.xml` and the RunManager in `.idea/workspace.xml`.
-- Spring Boot configs map to `bootRun --args=...`, Gradle configs run their tasks
-- and script parameters as-is. Other types (JUnit, Dart, ...) are skipped.
--
-- Spring Boot launches always get `gradle/run.init.gradle` (main class, VM
-- options, the JMX/Actuator settings live data needs); `<leader>Gd` adds
-- `gradle/debug.init.gradle` (JDWP, suspend=y, free loopback port) and attaches
-- through a fresh kotlin-lsp bridge once the JVM listens. Env entries with an
-- empty value aren't passed: the launch inherits Neovim's environment, which is
-- where secrets come from (the picker warns when such a variable is unset).
local M = {}

local CONFIG = vim.fn.stdpath('config')
local RUN_INIT = CONFIG .. '/gradle/run.init.gradle'
local DEBUG_INIT = CONFIG .. '/gradle/debug.init.gradle'

--- IntelliJ VM options → argv (whitespace-separated, double quotes group)
local function split_args(s)
  local out, cur, quoted, any = {}, {}, false, false
  for ch in (s or ''):gmatch('.') do
    if ch == '"' then
      quoted, any = not quoted, true
    elseif ch:match('%s') and not quoted then
      if any then
        table.insert(out, table.concat(cur))
      end
      cur, any = {}, false
    else
      table.insert(cur, ch)
      any = true
    end
  end
  if any then
    table.insert(out, table.concat(cur))
  end
  return out
end

--- env entries with a value; names of empty ones are returned separately
local function split_env(env)
  local set, inherit = {}, {}
  for k, v in pairs(env) do
    if v == '' then
      table.insert(inherit, k)
    else
      set[k] = v
    end
  end
  table.sort(inherit)
  return set, inherit
end

local ENTITIES = { quot = '"', apos = "'", amp = '&', lt = '<', gt = '>' }

local function decode(s)
  return (
    s:gsub('&(#?)(x?)(%w+);', function(hash, hex, name)
      if hash == '' then
        return ENTITIES[name]
      end
      return vim.fn.nr2char(tonumber(name, hex == 'x' and 16 or 10))
    end)
  )
end

--- Just enough XML for IntelliJ's files: elements and attributes, no text nodes.
local function parse_xml(xml)
  xml = xml:gsub('<!%-%-.-%-%->', ''):gsub('<%?.-%?>', '')
  local root = { tag = '#root', attrs = {}, children = {} }
  local stack = { root }
  for close, tag, attrstr, self_close in xml:gmatch('<(/?)([%w_:%.%-]+)(.-)(/?)>') do
    if close == '/' then
      if #stack > 1 then
        table.remove(stack)
      end
    else
      local node = { tag = tag, attrs = {}, children = {} }
      for k, v in attrstr:gmatch('([%w_:%.%-]+)%s*=%s*"(.-)"') do
        node.attrs[k] = decode(v)
      end
      table.insert(stack[#stack].children, node)
      if self_close ~= '/' then
        table.insert(stack, node)
      end
    end
  end
  return root
end

local function children(node, tag)
  return vim.tbl_filter(function(c)
    return c.tag == tag
  end, node and node.children or {})
end

local function child(node, tag, name)
  for _, c in ipairs(node and node.children or {}) do
    if c.tag == tag and (name == nil or c.attrs.name == name) then
      return c
    end
  end
end

local function option(node, name)
  local o = child(node, 'option', name)
  return o and o.attrs.value
end

local function expand(s, project_dir)
  if not s or s == '' then
    return nil
  end
  s = s:gsub('^file://', ''):gsub('%$PROJECT_DIR%$', project_dir):gsub('%$USER_HOME%$', vim.env.HOME)
  return s
end

--- `dmb-in-car-api.main` -> `` (root), `root.sub.main` -> `:sub:`
local function gradle_prefix(module)
  if not module then
    return ''
  end
  local parts = vim.split(module:gsub('%.main$', ''):gsub('%.test$', ''), '.', { plain = true })
  if #parts <= 1 then
    return ''
  end
  return ':' .. table.concat(parts, ':', 2) .. ':'
end

local function quote_arg(a)
  return a:find('[%s\'"]') and ("'" .. a:gsub("'", "\\'") .. "'") or a
end

local function spring_boot(cfg, project_dir, gradlew)
  local args = {}
  local profiles = option(cfg, 'ACTIVE_PROFILES')
  if profiles and profiles ~= '' then
    table.insert(args, '--spring.profiles.active=' .. profiles)
  end
  for _, p in ipairs(children(child(cfg, 'additionalParameters'), 'param')) do
    if option(p, 'enabled') ~= 'false' and option(p, 'name') then
      table.insert(args, quote_arg('--' .. option(p, 'name') .. '=' .. (option(p, 'value') or '')))
    end
  end
  local program_args = option(cfg, 'PROGRAM_PARAMETERS')
  if program_args and program_args ~= '' then
    table.insert(args, program_args)
  end

  local env = {}
  for _, e in ipairs(children(child(cfg, 'envs'), 'env')) do
    env[e.attrs.name] = expand(e.attrs.value, project_dir) or ''
  end

  local module = child(cfg, 'module')
  local cmd = { vim.fn.shellescape(gradlew), gradle_prefix(module and module.attrs.name) .. 'bootRun' }
  if #args > 0 then
    table.insert(cmd, vim.fn.shellescape('--args=' .. table.concat(args, ' ')))
  end

  local set, inherit = split_env(env)
  return {
    kind = 'Spring Boot',
    cmd = table.concat(cmd, ' '),
    cwd = expand(option(cfg, 'WORKING_DIRECTORY'), project_dir) or project_dir,
    env = set,
    inherit_env = inherit,
    main_class = option(cfg, 'SPRING_BOOT_MAIN_CLASS'),
    vm_args = split_args(option(cfg, 'VM_PARAMETERS')),
    inject = true,
    notes = {},
  }
end

local function gradle(cfg, project_dir, gradlew)
  local settings = child(cfg, 'ExternalSystemSettings')
  local cmd = { vim.fn.shellescape(gradlew) }
  local tasks = child(child(settings, 'option', 'taskNames'), 'list')
  for _, t in ipairs(children(tasks, 'option')) do
    table.insert(cmd, t.attrs.value)
  end
  local params = option(settings, 'scriptParameters')
  if params and params ~= '' then
    table.insert(cmd, params)
  end

  local env = {}
  local map = child(child(settings, 'option', 'env'), 'map')
  for _, e in ipairs(children(map, 'entry')) do
    env[e.attrs.key] = expand(e.attrs.value, project_dir) or ''
  end
  local set, inherit = split_env(env)
  return {
    kind = 'Gradle',
    cmd = table.concat(cmd, ' '),
    cwd = expand(option(settings, 'externalProjectPath'), project_dir) or project_dir,
    env = set,
    inherit_env = inherit,
    notes = {},
  }
end

local BUILDERS = {
  SpringBootApplicationConfigurationType = spring_boot,
  GradleRunConfiguration = gradle,
}

local function read(path)
  local f = io.open(path, 'r')
  if not f then
    return nil
  end
  local s = f:read('*a')
  f:close()
  return s
end

--- @return table[] configs
M.collect = function(root)
  local gradlew = root .. '/gradlew'
  if vim.fn.executable(gradlew) ~= 1 then
    gradlew = 'gradle'
  end

  local files = {}
  for _, pattern in ipairs({ '.run/*.run.xml', '*/.run/*.run.xml', '.idea/runConfigurations/*.xml' }) do
    vim.list_extend(files, vim.fn.globpath(root, pattern, true, true))
  end

  local found, seen = {}, {}
  local function add(cfg, source)
    local build = BUILDERS[cfg.attrs.type]
    if cfg.attrs.default == 'true' or not build then
      return
    end
    local entry = build(cfg, root, gradlew)
    entry.name = cfg.attrs.name or '?'
    entry.source = vim.fn.fnamemodify(source, ':.')
    -- the same config can live in both `.run/` and workspace.xml
    local key = entry.name .. '\0' .. entry.cmd .. '\0' .. vim.inspect(entry.env)
    if not seen[key] then
      seen[key] = true
      table.insert(found, entry)
    end
  end

  for _, file in ipairs(files) do
    local xml = read(file)
    if xml then
      for _, comp in ipairs(children(parse_xml(xml), 'component')) do
        for _, cfg in ipairs(children(comp, 'configuration')) do
          add(cfg, file)
        end
      end
    end
  end

  local workspace = root .. '/.idea/workspace.xml'
  local xml = read(workspace)
  if xml then
    for _, comp in ipairs(children(child(parse_xml(xml), 'project'), 'component')) do
      if comp.attrs.name == 'RunManager' then
        for _, cfg in ipairs(children(comp, 'configuration')) do
          add(cfg, workspace)
        end
      end
    end
  end
  return found
end

local function find_root()
  local marker = vim.fs.find({ 'gradlew', '.idea', '.run' }, { path = vim.fn.getcwd(), upward = true })[1]
  return marker and vim.fs.dirname(marker) or vim.fn.getcwd()
end

-- terminal buffers can't have a filetype/syntax, so overlay window matches.
-- spring's ANSI colors cover log lines; these cover what it leaves plain.
local MATCHES = {
  { 'Comment', [[\v^\s+at \S+\(.*\)]] }, -- stack frames
  { 'Comment', [[\v^\s+\.\.\. \d+ (more|common frames omitted)]] },
  { 'DiagnosticError', [[\v^([a-z_][a-z0-9_]*\.)+[A-Z]\w*(Exception|Error)>.*]] },
  { 'DiagnosticError', [[\v^Caused by: .*]] },
  { 'DiagnosticError', [[\v<ERROR>]] },
  { 'DiagnosticWarn', [[\v<WARN>]] },
  { 'ErrorMsg', [[\v^APPLICATION FAILED TO START]] },
  { 'Title', [[\v^(Description|Action):]] },
  { 'ErrorMsg', [[\v^(FAILURE: .*|BUILD FAILED.*|\* What went wrong:)]] },
  { 'DiagnosticOk', [[\v^BUILD SUCCESSFUL.*]] },
}

-- the filtered view is a plain buffer, so spring's ANSI colors are gone there.
-- `filetype=log` gives a base; these restore spring's layout on top of it:
-- <timestamp> <LEVEL> <pid> --- [app] [thread] <logger> : msg
local VIEW_MATCHES = {
  { 'DiagnosticInfo', [[\v<INFO>]] },
  { 'Comment', [[\v<(DEBUG|TRACE)>]] },
  { 'Comment', [[\v^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(\.\d+)?([+-]\d{2}:\d{2}|Z)?]] },
  { 'Number', [[\v<(ERROR|WARN|INFO|DEBUG|TRACE)>\s+\zs\d+\ze\s+---]] },
  { 'Comment', [=[\v\s\zs---\s(\[[^]]*\]\s*)+]=] },
  { 'Identifier', [=[\v---\s(\[[^]]*\]\s*)+\zs\S+\ze\s+:\s]=] },
}

local function add_matches(win, extra)
  if not (win and vim.api.nvim_win_is_valid(win)) or vim.w[win].run_config_matches then
    return
  end
  vim.w[win].run_config_matches = true
  for _, m in ipairs(vim.list_extend(vim.list_extend({}, MATCHES), extra or {})) do
    vim.fn.matchadd(m[1], m[2], 10, -1, { window = win })
  end
  -- spring boot 3.2+ with micrometer tracing pads an empty trace/span id to a
  -- ~50 column `[   ]` block when no span is active; hide it
  vim.fn.matchadd('Conceal', [[\v\[\s{10,}\]\s?]], 11, -1, { window = win, conceal = '' })
  vim.wo[win].conceallevel = 2
  vim.wo[win].concealcursor = 'nvic'
end

--- Keep windows of `buf` scrolled to the bottom as output arrives: unfocused
--- ones always, the focused one only while its cursor is on the last line (so
--- scrolling back through a log works and `G` resumes following). a terminal
--- does the latter natively, the filtered view needs it done for it.
local function follow(buf)
  local pending = false
  local prev_count = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      if pending then
        return
      end
      pending = true
      -- on_lines runs under textlock, so move cursors afterwards (and batch bursts)
      vim.defer_fn(function()
        pending = false
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        local last = vim.api.nvim_buf_line_count(buf)
        local current = vim.api.nvim_get_current_win()
        for _, win in ipairs(vim.fn.win_findbuf(buf)) do
          if win ~= current or vim.api.nvim_win_get_cursor(win)[1] >= prev_count then
            vim.api.nvim_win_set_cursor(win, { last, 0 })
          end
        end
        prev_count = last
      end, 50)
    end,
  })
end

------------------------------------------------------------------------------
-- log-level filter
--
-- terminal buffers can't hide lines, so filtering shows a separate read-only
-- buffer that mirrors the terminal live, in the terminal's place.
------------------------------------------------------------------------------

local LEVELS = { 'ERROR', 'WARN', 'INFO', 'DEBUG', 'TRACE' }
local ALL = 'All (raw terminal)'

--- per terminal buffer: { term, name, view, view_buf, levels?, eff, cur, shown, dirty }
local states = {}

--- `eff`: level for log lines and their continuations, 'other' for lines that are
--- always shown (gradle output, banner, spring's failure report), 'blank' to drop.
local function classify(line, current)
  if line:match('^%s*$') then
    return 'blank', current
  end
  if line:match('^%d%d%d%d%-%d%d%-%d%d') or line:match('^%d%d:%d%d:%d%d') then
    local head, best, at = line:sub(1, 80), nil, math.huge
    for _, level in ipairs(LEVELS) do
      local s = head:find('%f[%w]' .. level .. '%f[%W]')
      if s and s < at then
        best, at = level, s
      end
    end
    if best then
      return best, best
    end
  end
  if current then
    -- stack traces stay with the log line that printed them
    local name = line:match('^([%w_%.%$]+)')
    if
      line:match('^%s+%S')
      or line:match('^Caused by:')
      or (name and name:find('%.') and (name:match('Exception$') or name:match('Error$')))
    then
      return current, current
    end
  end
  return 'other', current
end

local function refresh(state)
  local term_buf, view_buf = state.term.buf, state.view_buf
  if not (state.levels and vim.api.nvim_buf_is_valid(term_buf) and vim.api.nvim_buf_is_valid(view_buf)) then
    return
  end
  -- reclassify from the first changed line down
  local all = vim.api.nvim_buf_get_lines(term_buf, 0, -1, false)
  local from = math.min(state.dirty or #state.eff, #state.eff)
  for i = #state.eff, from + 1, -1 do
    state.eff[i], state.cur[i] = nil, nil
  end
  -- the pty hard-wraps long lines into several buffer lines; a line following a
  -- full-width one is the rest of it. width is that of the last window shown in.
  local term_win = state.term.win
  if term_win and vim.api.nvim_win_is_valid(term_win) then
    local info = vim.fn.getwininfo(term_win)[1]
    state.cols = info.width - info.textoff
  end
  local cols = state.cols or vim.o.columns
  local current = from > 0 and state.cur[from] or nil
  for i = from + 1, #all do
    if i > 1 and state.eff[i - 1] and vim.fn.strdisplaywidth(all[i - 1]) >= cols then
      state.eff[i] = state.eff[i - 1]
    else
      state.eff[i], current = classify(all[i], current)
    end
    state.cur[i] = current
  end
  state.dirty = nil

  local shown = {}
  for i, eff in ipairs(state.eff) do
    if eff == 'other' or state.levels[eff] then
      table.insert(shown, all[i])
    end
  end
  -- only rewrite from the first difference so the reader's cursor isn't disturbed
  local old = state.shown
  local k = 1
  while k <= #old and k <= #shown and old[k] == shown[k] do
    k = k + 1
  end
  if k > #old and k > #shown then
    return
  end
  vim.bo[view_buf].modifiable = true
  vim.api.nvim_buf_set_lines(view_buf, k - 1, -1, false, vim.list_slice(shown, k))
  vim.bo[view_buf].modifiable = false
  state.shown = shown
end

local function ensure_view(state)
  if state.view_buf and vim.api.nvim_buf_is_valid(state.view_buf) then
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].filetype = 'log'
  state.view_buf, state.shown, state.eff, state.cur, state.dirty = buf, {}, {}, {}, 0
  follow(buf)

  local pending = false
  vim.api.nvim_buf_attach(state.term.buf, false, {
    on_lines = function(_, _, _, first)
      if not vim.api.nvim_buf_is_valid(buf) then
        return true -- view is gone, detach
      end
      state.dirty = math.min(state.dirty or first, first)
      if pending then
        return
      end
      pending = true
      vim.defer_fn(function()
        pending = false
        refresh(state)
      end, 100)
    end,
  })

  state.view = Snacks.win({
    buf = buf,
    show = false,
    position = 'bottom',
    height = 0.35,
    enter = false,
    keys = { q = 'hide' },
    wo = { wrap = false },
  })
  state.view:on('BufWinEnter', function(self)
    vim.schedule(function()
      add_matches(self.win, VIEW_MATCHES)
    end)
  end, { buf = true })
  vim.keymap.set('n', 'f', M.filter, { buffer = buf, desc = 'Filter log levels' })
  vim.keymap.set('n', '<C-c>', function() M.stop() end, { buffer = buf, desc = 'Stop run config' })
  vim.keymap.set('n', '<C-r>', function() M.restart() end, { buffer = buf, desc = 'Restart run config' })
end

--- @param levels string[]|nil nil/empty or containing ALL = raw terminal
local function apply(state, levels)
  local term = state.term
  local focused = vim.api.nvim_get_current_win()
  local was_focused = focused == term.win or (state.view and focused == state.view.win)

  local set = nil
  for _, l in ipairs(levels or {}) do
    if l == ALL then
      set = nil
      break
    end
    set = set or {}
    set[l] = true
  end
  state.levels = set

  if not set then
    if state.view and state.view:valid() then
      state.view:hide()
    end
    term:show()
    if was_focused then
      term:focus()
    end
    return
  end

  ensure_view(state)
  state.dirty = 0 -- level set changed: rebuild the view from scratch
  refresh(state)
  local label = table.concat(
    vim.tbl_filter(function(l)
      return set[l]
    end, LEVELS),
    ','
  )
  -- pcall: another run with the same name and filter would already own this name
  pcall(vim.api.nvim_buf_set_name, state.view_buf, string.format('run-config://%s [%s]', state.name, label))
  if term:valid() then
    term:hide()
  end
  state.view:show()
  vim.wo[state.view.win].winbar = (' %s  [%s]'):format(state.name, label):gsub('%%', '%%%%')
  local last = vim.api.nvim_buf_line_count(state.view_buf)
  vim.api.nvim_win_set_cursor(state.view.win, { last, 0 })
  if was_focused then
    state.view:focus()
  end
end

local function current_state()
  local term = M.last_term
  if not (term and term:buf_valid()) then
    Snacks.notify.warn('No run config terminal yet, start one with <leader>Gr')
    return nil
  end
  return states[term.buf]
end

--- Show the run's active window: the filtered view if a filter is set, else the terminal.
local function show_active(state, focus)
  local win = state.levels and state.view or state.term
  win:show()
  if focus then
    win:focus()
  end
end

M.filter = function()
  local state = current_state()
  if not state then
    return
  end
  local current = state.levels
      and table.concat(
        vim.tbl_filter(function(l)
          return state.levels[l]
        end, LEVELS),
        ','
      )
    or 'all'

  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  require('telescope.pickers')
    .new(require('telescope.themes').get_dropdown({}), {
      prompt_title = 'Log levels: <Tab> mark, <CR> apply (now: ' .. current .. ')',
      finder = require('telescope.finders').new_table({ results = vim.list_extend(vim.list_extend({}, LEVELS), { ALL }) }),
      sorter = require('telescope.config').values.generic_sorter({}),
      attach_mappings = function(prompt_buf)
        actions.select_default:replace(function()
          local picker = action_state.get_current_picker(prompt_buf)
          local picked = vim.tbl_map(function(e)
            return e.value
          end, picker:get_multi_selection())
          if #picked == 0 then
            local entry = action_state.get_selected_entry()
            picked = entry and { entry.value } or {}
          end
          actions.close(prompt_buf)
          if #picked > 0 then
            apply(state, picked)
          end
        end)
        return true
      end,
    })
    :find()
end

local function drop_state(buf)
  local state = states[buf]
  states[buf] = nil
  if state and state.view then
    state.view:close()
    if state.view_buf and vim.api.nvim_buf_is_valid(state.view_buf) then
      vim.api.nvim_buf_delete(state.view_buf, { force = true })
    end
  end
end

--- the shell command for a launch: the config's own plus the injected init scripts
local function launch_cmd(entry, debug_port)
  if not entry.inject then
    return entry.cmd
  end
  -- bootRun never finishes while the app runs, so the rich console's progress
  -- bar would sit at "93% EXECUTING" forever
  local extra = { '--console=plain', '-I', RUN_INIT }
  if entry.main_class and entry.main_class ~= '' then
    table.insert(extra, '-PrunMainClass=' .. entry.main_class)
  end
  if entry.vm_args and #entry.vm_args > 0 then
    local dir = vim.fn.stdpath('state') .. '/run-configs'
    vim.fn.mkdir(dir, 'p')
    local file = dir .. '/' .. entry.name:gsub('[^%w%-_.]', '_') .. '.jvmargs'
    vim.fn.writefile(entry.vm_args, file)
    table.insert(extra, '-Pnvim.run.jvmArgsFile=' .. file)
  end
  if debug_port then
    vim.list_extend(extra, { '-I', DEBUG_INIT, '-Pnvim.debugPort=' .. debug_port })
  end
  return entry.cmd .. ' ' .. table.concat(vim.tbl_map(vim.fn.shellescape, extra), ' ')
end

--- run name → terminal of a launch that may still be running
local by_name = {}

local function job_running(term)
  local job = term and term:buf_valid() and vim.b[term.buf].terminal_job_id
  return job and vim.fn.jobwait({ job }, 0)[1] == -1, job
end

--- Watch a launch's output: register the app JVM (Spring Boot logs its PID),
--- report when it's ready (or failed), and, for a debug launch, attach once
--- JDWP listens. "Started X in N seconds" is logged on ApplicationReadyEvent,
--- the same signal IntelliJ reads over JMX (SpringApplicationAdminMXBean.ready).
local function watch(term, entry, debug_port)
  local jobs = require('kotlin-workflow.jobs')
  local job = vim.b[term.buf].terminal_job_id
  local ok, client_pid = pcall(vim.fn.jobpid, job)
  if ok and client_pid then
    jobs.add({ pid = client_pid, kind = 'gradle-client', label = 'bootRun ' .. entry.name, root = entry.cwd })
  end
  local attached, app, done = debug_port == nil, false, not entry.inject
  vim.api.nvim_buf_attach(term.buf, false, {
    on_lines = function(_, buf, _, first, _, last)
      if attached and app and done then
        return true -- detach
      end
      -- the terminal wraps long lines at its width (two run terminals side by
      -- side are half width), so also match the lines joined back together
      local lines = vim.api.nvim_buf_get_lines(buf, math.max(first - 2, 0), last, false)
      local text = table.concat(lines, '\n') .. '\n' .. table.concat(lines, '')
      if not attached and require('kotlin-workflow.debug').listening_port(text) == debug_port then
        attached = true
        vim.schedule(function()
          require('kotlin-workflow.debug').attach(debug_port, entry.name, { kotlin_workflow_job = job })
        end)
      end
      local pid = not app and table.concat(lines, ''):match('with PID (%d+)')
      if pid then
        app = true
        vim.schedule(function()
          jobs.add({ pid = tonumber(pid), kind = 'app', label = entry.name, root = entry.cwd, debug_port = debug_port })
        end)
      end
      if not done then
        local joined = table.concat(lines, '')
        local secs = joined:match('Started %S+ in ([%d%.]+) seconds')
        if secs then
          done = true
          vim.schedule(function()
            Snacks.notify.info(('Started in %ss'):format(secs), { title = entry.name })
          end)
        elseif joined:find('APPLICATION FAILED TO START', 1, true) or joined:find('BUILD FAILED', 1, true) then
          done = true
          vim.schedule(function()
            Snacks.notify.error('Failed to start', { title = entry.name })
          end)
        end
      end
    end,
  })
end

--- @param entry table a collected config
--- @param opts? { debug?: boolean }
M.run = function(entry, opts)
  opts = opts or {}
  local previous = by_name[entry.name]
  if job_running(previous) then
    M.last_term = previous
    show_active(states[previous.buf] or { term = previous }, true)
    Snacks.notify.warn('Already running; stop it first (<C-c> in its terminal, or <leader>dt when debugging)', { title = entry.name })
    return
  end
  if opts.debug and not entry.inject then
    Snacks.notify.warn('Debug launches need a Spring Boot run config (bootRun)', { title = entry.name })
    return
  end
  local debug_port = opts.debug and require('kotlin-workflow.debug').free_port() or nil
  local cmd = launch_cmd(entry, debug_port)
  -- terminal buffers only show the program's own ANSI colors. under gradle the
  -- app has no System.console(), so spring boot's `detect` turns colored logs off.
  local env = vim.tbl_extend('keep', entry.env, { SPRING_OUTPUT_ANSI_ENABLED = 'always' })
  local term_opts = {
    cwd = entry.cwd,
    env = env,
    count = 1, -- part of the terminal id; keep it stable regardless of v:count
    -- non-interactive: snacks would otherwise `startinsert` on every BufEnter, and
    -- after the app exits any key in terminal mode wipes the buffer (nvim
    -- builtin), so a crash log vanished on the first scroll. entering the
    -- buffer stays in normal mode; `i` switches to terminal mode.
    interactive = false,
    auto_close = false,
    -- open beside the code without stealing focus; follow() keeps it tailing
    win = { position = 'bottom', height = 0.35, enter = false },
  }
  local term = Snacks.terminal.get(cmd, vim.tbl_extend('force', term_opts, { create = false }))
  if term then
    local job = vim.b[term.buf].terminal_job_id
    if job and vim.fn.jobwait({ job }, 0)[1] == -1 then
      -- still running: just bring it back (filtered, if a filter is set)
      M.last_term = term
      show_active(states[term.buf] or { term = term }, true)
      return
    end
    -- finished: wipe it (and its filtered view) so a fresh run starts unfiltered
    local buf = term.buf
    drop_state(buf)
    term:close()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
  term = Snacks.terminal.get(cmd, term_opts)
  M.last_term = term
  by_name[entry.name] = term
  watch(term, entry, debug_port)
  states[term.buf] = { term = term, name = entry.name, entry = entry, opts = opts }
  follow(term.buf)
  vim.keymap.set('n', 'f', M.filter, { buffer = term.buf, desc = 'Filter log levels' })
  vim.keymap.set('n', '<C-c>', function() M.stop() end, { buffer = term.buf, desc = 'Stop run config' })
  vim.keymap.set('n', '<C-r>', function() M.restart() end, { buffer = term.buf, desc = 'Restart run config' })
  local term_buf = term.buf
  term:on('BufWipeout', function()
    drop_state(term_buf)
  end, { buf = true })
  -- matches are window-local and snacks makes a new window on every show
  add_matches(term.win)
  term:on('BufWinEnter', function(self)
    -- fires inside nvim_open_win, before snacks has stored the new win id
    vim.schedule(function()
      add_matches(self.win)
    end)
  end, { buf = true })
  for _, note in ipairs(entry.notes) do
    Snacks.notify.warn(note, { title = entry.name })
  end
end

--- run state of a terminal buffer or of its filtered view
local function state_for(buf)
  if states[buf] then
    return states[buf]
  end
  for _, s in pairs(states) do
    if s.view_buf == buf then
      return s
    end
  end
end

--- Interrupt the run shown in the current buffer, as <C-c> in terminal mode
--- would: gradle passes the SIGINT on and the app shuts down gracefully.
M.stop = function()
  local state = state_for(vim.api.nvim_get_current_buf())
  if not state then
    return
  end
  local running, job = job_running(state.term)
  if not running then
    return Snacks.notify.info('Not running', { title = state.name })
  end
  vim.fn.chansend(job, '\3')
end

--- Stop the run shown in the current buffer (if running) and launch it again
--- with the same config, debug mode and log filter.
M.restart = function()
  local state = state_for(vim.api.nvim_get_current_buf())
  if not (state and state.entry) then
    return
  end
  local entry, opts, levels = state.entry, state.opts, state.levels
  local function relaunch()
    M.run(entry, opts)
    local new = M.last_term and states[M.last_term.buf]
    if levels and new then
      apply(new, vim.tbl_keys(levels))
    end
  end
  local running, job = job_running(state.term)
  if not running then
    return relaunch()
  end
  vim.api.nvim_create_autocmd('TermClose', {
    buffer = state.term.buf,
    once = true,
    callback = function()
      vim.schedule(relaunch)
    end,
  })
  Snacks.notify.info('Restarting…', { title = entry.name })
  vim.fn.chansend(job, '\3')
  -- graceful shutdown hung: kill it (TermClose still relaunches)
  vim.defer_fn(function()
    if job_running(state.term) then
      vim.fn.jobstop(job)
    end
  end, 15000)
end

--- Show/hide the most recently started (or resumed) run config's log: the
--- filtered view when a filter is set, else the terminal.
M.toggle = function()
  local state = current_state()
  if not state then
    return
  end
  local active = state.levels and state.view or state.term
  local other = state.levels and state.term or state.view
  if active:valid() then
    active:hide()
  else
    if other and other:valid() then
      other:hide()
    end
    show_active(state, false)
  end
end

--- @param opts? { debug?: boolean }
M.pick = function(opts)
  opts = opts or {}
  local root = find_root()
  local configs = M.collect(root)
  if #configs == 0 then
    Snacks.notify.warn('No Spring Boot / Gradle run configs under ' .. root)
    return
  end
  vim.ui.select(configs, {
    prompt = opts.debug and 'Debug IntelliJ run config' or 'IntelliJ run configs',
    format_item = function(e)
      return string.format('%s  [%s]  %s', e.name, e.kind, e.cmd:gsub('^%S+/gradlew', './gradlew'))
    end,
  }, function(entry)
    if not entry then
      return
    end
    local unset = vim.tbl_filter(function(name)
      return vim.env[name] == nil
    end, entry.inherit_env or {})
    if #unset > 0 then
      Snacks.notify.warn(
        ('Empty in the run config and unset in this Neovim: %s. Export them before starting Neovim (secrets stay out of run configs).'):format(
          table.concat(unset, ', ')
        ),
        { title = entry.name }
      )
    end
    M.run(entry, opts)
  end)
end

return M
