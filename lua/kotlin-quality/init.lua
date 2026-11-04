-- On-demand detekt + ktlint through Gradle (ticket 05). Nothing runs on save.
--
-- A run: save modified project buffers → discover tasks (cached) → wipe the
-- latest-run folder (<root build dir>/nvim-quality) → `./gradlew` as an argv
-- with task-level `--rerun` → parse each scope's Checkstyle report → replace
-- covered scopes' findings, keep uncovered ones labelled stale → one summary.
-- A scope is tool × Gradle project × source set; it is covered only when its
-- task ran in this run and its report parsed.
local M = {}

local discovery = require('kotlin-quality.discovery')
local report = require('kotlin-quality.report')

local TOOLS = { detekt = 'detekt', ktlint = 'ktlint-gradle' }
local NS = {
  detekt = vim.api.nvim_create_namespace('detekt'),
  ['ktlint-gradle'] = vim.api.nvim_create_namespace('ktlint-gradle'),
}
local CANCEL_GRACE_MS = 10000

local seq = 0
--- @type table<string, table> root → active run
local active = {}
--- @type table<string, table> root → last run
local last = {}
--- @type table<string, table<string, table>> root → scope key → scope
local store = {}
--- @type table<string, table<integer, true>> namespace name → buffers holding diagnostics
local shown = { detekt = {}, ['ktlint-gradle'] = {} }

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'Quality' })
end

local function safe_name(path)
  return path == ':' and 'root' or path:sub(2):gsub(':', '-')
end

local function write_json(path, data)
  local f = io.open(path, 'w')
  if f then
    f:write(vim.json.encode(data))
    f:close()
  end
end

local function under(root, file)
  return file ~= '' and vim.startswith(vim.fs.normalize(file), root .. '/')
end

--------------------------------------------------------------------------------
-- findings → diagnostics

local function byte_col(file, lnum, column, lines_cache)
  if not column or column < 1 then
    return 0
  end
  local text
  local buf = vim.fn.bufnr(file)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
    text = vim.api.nvim_buf_get_lines(buf, lnum, lnum + 1, false)[1]
  else
    if lines_cache[file] == nil then
      lines_cache[file] = vim.uv.fs_stat(file) and vim.fn.readfile(file) or false
    end
    text = lines_cache[file] and lines_cache[file][lnum + 1]
  end
  if not text then
    return column - 1
  end
  -- the JVM tools count UTF-16 code units
  local ok, b = pcall(vim.str_byteindex, text, 'utf-16', column - 1, false)
  return ok and b or column - 1
end

--- Re-render both namespaces from the store. Exact duplicates (tool, file,
--- line, column, rule, message) collapse; different rules at one spot stay.
local function render()
  local by_tool = { detekt = {}, ['ktlint-gradle'] = {} }
  local seen = {}
  local lines_cache = {}
  for _, scopes in pairs(store) do
    for _, scope in pairs(scopes) do
      for _, f in ipairs(scope.findings) do
        local key = table.concat({ f.tool, f.file, f.line, f.column or '', f.rule_id, f.message }, '\0')
        if not seen[key] then
          seen[key] = true
          local stale = scope.stale or f.stale
          local per_file = by_tool[f.tool]
          per_file[f.file] = per_file[f.file] or {}
          local lnum = math.max(f.line - 1, 0)
          table.insert(per_file[f.file], {
            lnum = lnum,
            col = byte_col(f.file, lnum, f.column, lines_cache),
            severity = vim.diagnostic.severity.WARN,
            source = f.tool,
            code = f.rule_id,
            message = (stale and '[stale] ' or '') .. f.message,
            user_data = { quality = f, stale = stale or false, stale_reason = scope.stale_reason },
          })
        end
      end
    end
  end
  for tool, per_file in pairs(by_tool) do
    local now = {}
    for file, diags in pairs(per_file) do
      local buf = vim.fn.bufadd(file)
      now[buf] = true
      vim.diagnostic.set(NS[tool], buf, diags)
    end
    for buf in pairs(shown[tool]) do
      if not now[buf] and vim.api.nvim_buf_is_valid(buf) then
        vim.diagnostic.reset(NS[tool], buf)
      end
    end
    shown[tool] = now
  end
end

local function count_findings(root)
  local counts = { detekt = { fresh = 0, stale = 0 }, ['ktlint-gradle'] = { fresh = 0, stale = 0 } }
  for _, scope in pairs(store[root] or {}) do
    for _, f in ipairs(scope.findings) do
      local c = counts[f.tool]
      if scope.stale or f.stale then
        c.stale = c.stale + 1
      else
        c.fresh = c.fresh + 1
      end
    end
  end
  return counts
end

local function open_trouble()
  local ok, trouble = pcall(require, 'trouble')
  if not ok then
    return
  end
  trouble.open({
    mode = 'diagnostics',
    focus = false,
    filter = {
      function(item)
        return item.item and (item.item.source == 'detekt' or item.item.source == 'ktlint-gradle')
      end,
    },
  })
end

--------------------------------------------------------------------------------
-- planning

--- @return table[] scopes { key, tool, project, source_set, task, tasks, report, base }
local function plan_check(disc, projects, untyped)
  local scopes, missing = {}, {}
  local run_dir = disc.run_dir
  for _, p in ipairs(projects) do
    local dir = run_dir .. '/reports/' .. safe_name(p.path)
    local detekt_tasks = vim.tbl_filter(function(t)
      return t.kind == (untyped and 'untyped-all' or 'typed')
    end, p.detekt or {})
    if #detekt_tasks == 0 then
      table.insert(missing, p.path .. ' has no ' .. (untyped and 'untyped `detekt`' or 'typed detekt') .. ' task')
    end
    for _, t in ipairs(detekt_tasks) do
      table.insert(scopes, {
        key = (untyped and 'detekt-untyped|' or 'detekt|') .. p.path .. '|' .. t.sourceSet,
        tool = TOOLS.detekt,
        project = p.path,
        source_set = untyped and 'all (untyped)' or t.sourceSet,
        task = t.path,
        tasks = { t.path },
        report = dir .. '/' .. t.name .. '.xml',
        base = t.basePath or disc.rootDir,
      })
    end
    local checks = vim.tbl_filter(function(t)
      return t.kind == 'check'
    end, p.ktlint or {})
    if #checks == 0 and (p.detekt and #p.detekt > 0) then
      table.insert(missing, p.path .. ' has no ktlint check task')
    end
    for _, t in ipairs(checks) do
      table.insert(scopes, {
        key = 'ktlint|' .. p.path .. '|' .. t.sourceSet,
        tool = TOOLS.ktlint,
        project = p.path,
        source_set = t.sourceSet,
        task = t.path,
        worker = t.worker,
        tasks = t.worker and { t.worker, t.path } or { t.path },
        report = dir .. '/' .. t.name .. '.xml',
        base = disc.rootDir,
      })
    end
  end
  return scopes, missing
end

--------------------------------------------------------------------------------
-- run lifecycle

local function save_project_buffers(root)
  local saved = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if
      vim.api.nvim_buf_is_loaded(buf)
      and vim.bo[buf].modified
      and vim.bo[buf].buftype == ''
      and under(root, name)
    then
      local ok, err = pcall(vim.api.nvim_buf_call, buf, function()
        vim.cmd('silent write')
      end)
      if ok then
        table.insert(saved, name)
      else
        notify('Could not save ' .. name .. ': ' .. tostring(err), vim.log.levels.WARN)
      end
    end
  end
  return saved
end

--- changedtick of every loaded project buffer, to tell later edits apart
local function buffer_snapshot(root)
  local ticks = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if vim.api.nvim_buf_is_loaded(buf) and under(root, name) then
      ticks[vim.fs.normalize(name)] = vim.api.nvim_buf_get_changedtick(buf)
    end
  end
  return ticks
end

--- did `file` change after the run's save snapshot?
local function changed_since(run, file)
  local st = vim.uv.fs_stat(file)
  if st and st.mtime.sec > run.started then
    return true
  end
  local buf = vim.fn.bufnr(file)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
    local tick = run.ticks[file]
    if tick == nil then
      return vim.bo[buf].modified
    end
    return vim.api.nvim_buf_get_changedtick(buf) ~= tick
  end
  return false
end

local function kotlin_files(root)
  local files = {}
  for name, type in
    vim.fs.dir(root, {
      depth = 20,
      skip = function(dir)
        local base = vim.fs.basename(dir)
        return base ~= 'build' and base ~= 'node_modules' and not vim.startswith(base, '.')
      end,
    })
  do
    if type == 'file' and (name:match('%.kt$') or name:match('%.kts$')) then
      local path = root .. '/' .. name
      local st = vim.uv.fs_stat(path)
      files[path] = st and (st.mtime.sec * 1e9 + st.mtime.nsec) or 0
    end
  end
  return files
end

local function record_line(run, line)
  run.log:write(line, '\n')
  local task, outcome = line:match('^> Task (:%S*)%s*(.-)%s*$')
  if task then
    if not run.outcomes[task] then
      table.insert(run.task_order, task)
    end
    run.outcomes[task] = outcome
  end
end

local function on_output(run, chunk)
  if not chunk or run.status ~= 'running' then
    return
  end
  run.partial = run.partial .. chunk
  while true do
    local nl = run.partial:find('\n', 1, true)
    if not nl then
      break
    end
    record_line(run, run.partial:sub(1, nl - 1))
    run.partial = run.partial:sub(nl + 1)
  end
end

local EXECUTED = { [''] = true, FAILED = true, ['FROM-CACHE'] = true, ['UP-TO-DATE'] = true }

--- coverage for one scope after the run
local function settle(run, scope)
  if run.status == 'cancelled' then
    return 'uncovered', 'run cancelled'
  end
  local worker_outcome = scope.worker and run.outcomes[scope.worker]
  local outcome = run.outcomes[scope.task]
  if worker_outcome == 'NO-SOURCE' or outcome == 'NO-SOURCE' then
    return 'no-source', nil
  end
  if outcome == nil then
    return 'uncovered', 'not run (a dependency failed?)'
  end
  if not EXECUTED[outcome] then
    return 'uncovered', 'task ' .. outcome
  end
  local findings, err = report.parse(scope.report, scope.base)
  if not findings then
    return 'uncovered', 'report ' .. err, nil
  end
  return 'covered', nil, findings
end

local function finish_check(run)
  local root = run.root
  store[root] = store[root] or {}
  local scopes_out = {}
  local uncovered = {}
  local typed_covered = {} -- project → all typed detekt scopes covered?
  for _, scope in ipairs(run.scopes) do
    local coverage, reason, findings = settle(run, scope)
    local entry = {
      key = scope.key,
      tool = scope.tool,
      project = scope.project,
      source_set = scope.source_set,
      task = scope.task,
      outcome = run.outcomes[scope.task],
      report = scope.report,
      coverage = coverage,
      reason = reason,
    }
    if scope.tool == TOOLS.detekt and not run.untyped then
      typed_covered[scope.project] = (typed_covered[scope.project] ~= false) and coverage ~= 'uncovered'
    end
    if coverage == 'covered' or coverage == 'no-source' then
      local records = {}
      for _, f in ipairs(findings or {}) do
        table.insert(records, {
          run_id = run.id,
          tool = scope.tool,
          gradle_project = scope.project,
          task_path = scope.task,
          file = f.file,
          line = f.line,
          column = f.column,
          raw_severity = f.severity,
          rule_id = f.rule,
          message = f.message,
          report_path = scope.report,
          stale = changed_since(run, f.file),
        })
      end
      entry.findings = #records
      store[root][scope.key] = {
        tool = scope.tool,
        project = scope.project,
        source_set = scope.source_set,
        findings = records,
        run_id = run.id,
      }
    else
      table.insert(uncovered, ('%s (%s)'):format(scope.task, reason))
      local prev = store[root][scope.key]
      if prev then
        prev.stale = true
        prev.stale_reason = reason
      end
    end
    table.insert(scopes_out, entry)
  end
  -- a complete typed run supersedes the project's untyped findings
  for project, all in pairs(typed_covered) do
    if all then
      store[root]['detekt-untyped|' .. project .. '|all'] = nil
    end
  end
  render()
  return scopes_out, uncovered
end

local function finish_format(run)
  local after = kotlin_files(run.root)
  local changed = {}
  for path, t in pairs(after) do
    if run.files_before[path] ~= t then
      table.insert(changed, path)
    end
  end
  table.sort(changed)
  local conflicts = {}
  for _, path in ipairs(changed) do
    local buf = vim.fn.bufnr(path)
    if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
      if vim.bo[buf].modified then
        table.insert(conflicts, path)
      else
        vim.api.nvim_buf_call(buf, function()
          vim.cmd('silent! edit')
        end)
      end
    end
  end
  -- ktlint findings of formatted projects no longer describe the files
  local projects = {}
  for _, p in ipairs(run.projects) do
    projects[p.path] = true
  end
  for _, scope in pairs(store[run.root] or {}) do
    if scope.tool == TOOLS.ktlint and projects[scope.project] then
      scope.stale = true
      scope.stale_reason = 'formatted after the check'
    end
  end
  render()
  return changed, conflicts
end

local function rel(root, path)
  return vim.startswith(path, root .. '/') and path:sub(#root + 2) or path
end

local function summarize(run, scopes_out, uncovered, missing, changed, conflicts)
  local lines = {}
  local status = run.status
  if status == 'failed' then
    local failed_quality, other = 0, 0
    for task, outcome in pairs(run.outcomes) do
      if outcome == 'FAILED' then
        if run.quality_tasks[task] then
          failed_quality = failed_quality + 1
        else
          other = other + 1
        end
      end
    end
    status = other == 0 and failed_quality > 0 and 'failed (findings)' or 'failed (errors)'
  end
  table.insert(lines, ('%s run %d %s%s'):format(run.kind, run.id, status, run.signal and (' by ' .. run.signal) or ''))
  if run.kind ~= 'format' then
    local counts = count_findings(run.root)
    local parts = {}
    for _, tool in ipairs({ 'detekt', 'ktlint-gradle' }) do
      local c = counts[tool]
      table.insert(parts, ('%s %d%s'):format(tool, c.fresh, c.stale > 0 and (' + ' .. c.stale .. ' stale') or ''))
    end
    table.insert(lines, table.concat(parts, ' · ') .. (run.untyped and ' (detekt untyped)' or ''))
  end
  if run.status == 'cancelled' and uncovered and #uncovered > 0 then
    table.insert(lines, ('Uncovered: all %d scopes (run cancelled); earlier findings kept as stale'):format(#uncovered))
  else
    for _, u in ipairs(uncovered or {}) do
      table.insert(lines, 'Uncovered: ' .. u)
    end
  end
  for _, m in ipairs(missing or {}) do
    table.insert(lines, 'Missing: ' .. m)
  end
  if changed then
    table.insert(lines, #changed == 0 and 'No files changed' or ('Changed %d file(s):'):format(#changed))
    for _, c in ipairs(changed) do
      table.insert(lines, '  ' .. rel(run.root, c))
    end
  end
  for _, c in ipairs(conflicts or {}) do
    table.insert(lines, 'Not reloaded (edited during the run): ' .. rel(run.root, c))
  end
  table.insert(lines, 'Log: ' .. run.log_path .. ' (<leader>kr)')
  -- a project without detekt (often the root) is listed, but isn't a warning
  local level = vim.log.levels.INFO
  local c = count_findings(run.root)
  local findings = c.detekt.fresh + c['ktlint-gradle'].fresh
  if run.status == 'cancelled' or (uncovered and #uncovered > 0) or (run.kind ~= 'format' and findings > 0) then
    level = vim.log.levels.WARN
  end
  if status == 'failed (errors)' then
    level = vim.log.levels.ERROR
  end
  notify(table.concat(lines, '\n'), level)
  return lines
end

local function write_index(run)
  local path = discovery.state_dir(run.root) .. '/runs.json'
  local runs = discovery.read_json(path) or {}
  table.insert(runs, 1, {
    id = run.id,
    kind = run.kind,
    status = run.status,
    started = run.started,
    ended = run.ended,
    log = run.log_path,
    manifest = run.run_dir .. '/manifest.json',
  })
  while #runs > 20 do
    table.remove(runs)
  end
  write_json(path, runs)
end

local function on_exit(run, r)
  if active[run.root] ~= run then
    return -- a callback from an older run
  end
  active[run.root] = nil
  if run.partial ~= '' and run.status == 'running' then
    record_line(run, run.partial)
  end
  run.ended = os.time()
  run.exit_code = r.code
  run.signal = r.signal ~= 0 and (run.signal or ('signal ' .. r.signal)) or run.signal
  if run.cancel_timer then
    run.cancel_timer:stop()
    run.cancel_timer:close()
  end
  if run.status == 'running' then
    run.status = r.code == 0 and 'succeeded' or 'failed'
  end
  if run.status == 'cancelled' then
    run.log:write('\n[nvim] run cancelled; ', run.signal or 'no signal needed', '\n')
  end
  run.log:close()
  require('kotlin-workflow.jobs').remove(run.job_id)

  local scopes_out, uncovered, changed, conflicts
  if run.kind == 'format' then
    if run.status ~= 'cancelled' then
      changed, conflicts = finish_format(run)
    end
  else
    scopes_out, uncovered = finish_check(run)
  end
  local summary = summarize(run, scopes_out, uncovered, run.missing, changed, conflicts)
  local tasks = {}
  for _, t in ipairs(run.task_order) do
    table.insert(tasks, { task = t, outcome = run.outcomes[t] == '' and 'EXECUTED' or run.outcomes[t] })
  end
  write_json(run.run_dir .. '/manifest.json', {
    run_id = run.id,
    kind = run.kind,
    untyped = run.untyped or false,
    root = run.root,
    argv = run.argv,
    cwd = run.root,
    started = os.date('!%Y-%m-%dT%H:%M:%SZ', run.started),
    ended = os.date('!%Y-%m-%dT%H:%M:%SZ', run.ended),
    status = run.status,
    exit_code = run.exit_code,
    signal = run.signal,
    run_dir_wiped = true,
    selected_projects = vim.tbl_map(function(p)
      return p.path
    end, run.projects),
    saved_files = run.saved,
    tasks = tasks,
    scopes = scopes_out,
    missing_tasks = run.missing,
    changed_files = changed,
    summary = summary,
  })
  write_index(run)
  last[run.root] = run
  if run.kind ~= 'format' then
    local c = count_findings(run.root)
    if c.detekt.fresh + c.detekt.stale + c['ktlint-gradle'].fresh + c['ktlint-gradle'].stale > 0 then
      open_trouble()
    end
  end
  vim.cmd.redrawstatus()
end

local function start(run, disc)
  local root_project = disc.projects[1]
  for _, p in ipairs(disc.projects) do
    if p.path == ':' then
      root_project = p
    end
  end
  run.run_dir = (root_project and root_project.buildDir or (run.root .. '/build')) .. '/nvim-quality'
  disc.run_dir = run.run_dir
  local tasks = {}
  run.quality_tasks = {}
  if run.kind == 'format' then
    for _, p in ipairs(run.projects) do
      if p.ktlintFormat then
        table.insert(tasks, p.ktlintFormat)
        run.quality_tasks[p.ktlintFormat] = true
      else
        table.insert(run.missing, p.path .. ' has no ktlintFormat task')
      end
    end
    run.files_before = kotlin_files(run.root)
  else
    local scopes, missing = plan_check(disc, run.projects, run.untyped)
    run.scopes = scopes
    vim.list_extend(run.missing, missing)
    for _, s in ipairs(scopes) do
      for _, t in ipairs(s.tasks) do
        if not run.quality_tasks[t] then
          run.quality_tasks[t] = true
          vim.list_extend(tasks, { t, '--rerun' })
        end
      end
    end
  end
  if #tasks == 0 then
    active[run.root] = nil
    notify('Nothing to run: ' .. table.concat(run.missing, '; '), vim.log.levels.WARN)
    return
  end

  vim.fn.delete(run.run_dir, 'rf')
  vim.fn.mkdir(run.run_dir .. '/reports', 'p')
  run.log_path = run.run_dir .. '/gradle.log'
  run.log = assert(io.open(run.log_path, 'w'))
  run.argv = vim.list_extend({
    run.gradlew,
    '-I',
    discovery.init_script,
    '-Pnvim.quality.runDir=' .. run.run_dir,
    '--continue',
    '--console=plain',
  }, tasks)
  run.log:write('[nvim] ', vim.json.encode(run.argv), '\n[nvim] cwd ', run.root, '\n\n')
  run.started = os.time()
  run.ticks = buffer_snapshot(run.root)
  run.status = 'running'
  local function output(_, chunk)
    vim.schedule(function()
      if active[run.root] == run then
        on_output(run, chunk)
      end
    end)
  end
  local ok, obj = pcall(vim.system, run.argv, { cwd = run.root, text = true, stdout = output, stderr = output }, function(r)
    vim.schedule(function()
      on_exit(run, r)
    end)
  end)
  if not ok then
    active[run.root] = nil
    run.log:close()
    notify('Could not start Gradle: ' .. tostring(obj), vim.log.levels.ERROR)
    return
  end
  run.proc = obj
  run.job_id = require('kotlin-workflow.jobs').add({
    pid = obj.pid,
    kind = 'gradle-client',
    label = 'quality ' .. run.kind,
    root = run.root,
  })
  vim.cmd.redrawstatus()
end

--- @param kind 'check'|'untyped'|'format'
--- @param select boolean pick modules first
local function begin(kind, select)
  local root, gradlew = discovery.root()
  if not root then
    return notify('No gradlew above ' .. vim.fn.getcwd(), vim.log.levels.ERROR)
  end
  local current = active[root]
  if current then
    return notify(('A quality %s (run %d) is already running; cancel it with <leader>kx'):format(current.kind, current.id))
  end
  seq = seq + 1
  local run = {
    id = seq,
    kind = kind == 'untyped' and 'check' or kind,
    untyped = kind == 'untyped',
    root = root,
    gradlew = gradlew,
    status = 'discovering',
    outcomes = {},
    task_order = {},
    missing = {},
    partial = '',
    created = os.time(),
  }
  active[root] = run
  run.saved = save_project_buffers(root)
  vim.cmd.redrawstatus()
  local proc = discovery.get(root, gradlew, function(disc, err)
    if active[root] ~= run then
      return
    end
    if run.discovery_job then
      require('kotlin-workflow.jobs').remove(run.discovery_job)
    end
    if not disc then
      active[root] = nil
      vim.cmd.redrawstatus()
      return notify(err, vim.log.levels.ERROR)
    end
    local function go(projects)
      if active[root] ~= run then
        return
      end
      run.projects = projects
      start(run, disc)
    end
    if not select then
      return go(disc.projects)
    end
    M.pick_projects(disc.projects, function(picked)
      if not picked or #picked == 0 then
        active[root] = nil
        vim.cmd.redrawstatus()
        return
      end
      go(picked)
    end)
  end)
  if proc then
    run.discovery = proc
    run.discovery_job = require('kotlin-workflow.jobs').add({
      pid = proc.pid,
      kind = 'gradle-client',
      label = 'quality discovery',
      root = root,
    })
    notify('Discovering Gradle quality tasks…')
  end
end

--- multi-select over Gradle projects (<Tab> marks; <CR> takes the marks or the current entry)
function M.pick_projects(projects, cb)
  local ok = pcall(require, 'telescope')
  if not ok then
    return vim.ui.select(projects, {
      prompt = 'Quality: module',
      format_item = function(p)
        return p.path
      end,
    }, function(p)
      cb(p and { p })
    end)
  end
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local done = false
  pickers
    .new({}, {
      prompt_title = 'Quality: modules (<Tab> marks)',
      finder = finders.new_table({
        results = projects,
        entry_maker = function(p)
          local typed = #vim.tbl_filter(function(t)
            return t.kind == 'typed'
          end, p.detekt or {})
          local label = ('%s  [detekt %d, ktlint %d]'):format(
            p.path,
            typed,
            #vim.tbl_filter(function(t)
              return t.kind == 'check'
            end, p.ktlint or {})
          )
          return { value = p, display = label, ordinal = p.path }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(bufnr)
        actions.select_default:replace(function()
          local picker = action_state.get_current_picker(bufnr)
          local marked = picker:get_multi_selection()
          if #marked == 0 then
            marked = { action_state.get_selected_entry() }
          end
          done = true
          actions.close(bufnr)
          cb(vim.tbl_map(function(e)
            return e.value
          end, marked))
        end)
        actions.close:enhance({
          post = function()
            if not done then
              done = true
              cb(nil)
            end
          end,
        })
        return true
      end,
    })
    :find()
end

--------------------------------------------------------------------------------
-- public

function M.check()
  begin('check', false)
end
function M.check_modules()
  begin('check', true)
end
function M.check_untyped()
  begin('untyped', false)
end
function M.format()
  begin('format', false)
end
function M.format_modules()
  begin('format', true)
end

--- SIGINT to the owned gradlew client (Gradle cancels the build in the
--- daemon), SIGTERM after 10 s if it is still alive.
function M.cancel()
  local root = discovery.root()
  local run = root and active[root]
  if not run then
    return notify('No quality run is active')
  end
  if run.status == 'discovering' then
    if run.discovery then
      run.discovery:kill('sigint')
    end
    active[root] = nil
    vim.cmd.redrawstatus()
    return notify(('Quality %s (run %d) cancelled during discovery'):format(run.kind, run.id))
  end
  if run.status ~= 'running' then
    return
  end
  run.status = 'cancelled'
  run.signal = 'SIGINT'
  run.proc:kill('sigint')
  run.cancel_timer = vim.uv.new_timer()
  run.cancel_timer:start(CANCEL_GRACE_MS, 0, function()
    vim.schedule(function()
      if active[root] == run and not run.proc:is_closing() then
        run.signal = 'SIGINT, then SIGTERM after 10 s'
        run.proc:kill('sigterm')
      end
    end)
  end)
  vim.cmd.redrawstatus()
end

--- the last run's log in a scratch buffer
function M.open_log()
  local root = discovery.root()
  if not root then
    return notify('No gradlew above ' .. vim.fn.getcwd(), vim.log.levels.ERROR)
  end
  local run = active[root] or last[root]
  local path = run and run.log_path
  if not path then
    local runs = discovery.read_json(discovery.state_dir(root) .. '/runs.json')
    path = runs and runs[1] and runs[1].log
  end
  if not path or not vim.uv.fs_stat(path) then
    return notify('No quality run log (a `gradle clean` removes it)', vim.log.levels.WARN)
  end
  vim.cmd('botright new')
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.readfile(path))
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_set_name(buf, 'quality-log://' .. path)
  vim.keymap.set('n', 'q', '<CMD>close<CR>', { buffer = buf })
end

--- lualine: shown while a run is active
function M.status()
  if next(active) == nil then
    return ''
  end
  local root = discovery.root()
  local run = root and active[root]
  if not run then
    return ''
  end
  local what = run.untyped and 'untyped check' or run.kind
  local since = os.time() - (run.started or run.created)
  if run.status == 'discovering' then
    return ('󰔟 quality %s: discovering'):format(what)
  end
  return ('󰔟 quality %s %ds%s'):format(what, since, run.status == 'cancelled' and ' (cancelling)' or '')
end

--- findings for inspection (tests, :lua)
function M.findings(root)
  return store[root or discovery.root()] or {}
end

function M.health(h)
  h.info('Init script: ' .. discovery.init_script)
  local root = discovery.root()
  if not root then
    h.info('No gradlew above the cwd')
    return
  end
  local disc = discovery.cached(root)
  if disc then
    local typed, ktlint = 0, 0
    for _, p in ipairs(disc.projects) do
      for _, t in ipairs(p.detekt or {}) do
        typed = typed + (t.kind == 'typed' and 1 or 0)
      end
      for _, t in ipairs(p.ktlint or {}) do
        ktlint = ktlint + (t.kind == 'check' and 1 or 0)
      end
    end
    h.ok(
      ('Discovery cached: %d Gradle projects, %d typed detekt tasks, %d ktlint checks (Gradle %s)'):format(
        #disc.projects,
        typed,
        ktlint,
        disc.gradleVersion or '?'
      )
    )
  else
    h.info('No current discovery cache (the next check discovers)')
  end
  local runs = discovery.read_json(discovery.state_dir(root) .. '/runs.json')
  if runs and runs[1] then
    h.info(('Last run %d: %s %s, log %s'):format(runs[1].id, runs[1].kind, runs[1].status, runs[1].log))
  end
  if active[root] then
    h.info('Active: ' .. M.status())
  end
end

return M
