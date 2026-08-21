-- `:Koan` helpers for jetbrains academy courses (kotlin koans).
--
-- Every task folder carries a `task-info.yaml` listing the answer placeholders
-- the IntelliJ EduTools plugin blanks out: a byte range into the committed
-- solution plus the text the student is supposed to see. `:Koan stub` applies
-- them, turning a solved task back into the exercise.
--
-- That only works while the solutions are somewhere in git, which they are not
-- on a practice branch. play.kotlinlang.org has the same course as one JSON
-- blob baked into its bundle, holding the exercise text *and* the answer for
-- every blank, so a vendored copy answers both questions without git. It is
-- preferred where it covers a task; git remains the fallback for a course it
-- does not know.
--
-- To refresh it: fetch the `/main.js?<hash>` that https://play.kotlinlang.org/
-- loads, find the sole `JSON.parse('{"summary":"Kotlin Koans...')` in it, and
-- write the parsed object to the path below. The argument is a javascript
-- single-quoted string, so it needs unescaping (`\'`, `\\`, `\/`) before it is
-- valid JSON.
--
-- A virtual plugin: nothing to install, enabled only inside a course checkout
-- and loaded only once :Koan is called.

-- declared up front, the subcommand table below closes over them
local stub, stub_all, solution, task

--- The playground's course, vendored. Keyed `<lesson>/<task>` once loaded.
local CATALOG = vim.fn.stdpath('config') .. '/data/kotlin-koans.json'

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = 'Koan' })
end

--- @param dir string
--- @return string|nil
local function git_root(dir)
  local result = vim.system({ 'git', '-C', dir, 'rev-parse', '--show-toplevel' }):wait()
  if result.code ~= 0 then
    return nil
  end
  return vim.trim(result.stdout)
end

--- The course root is the folder holding `course-info.yaml`, which is also the
--- git root in a checked out course.
--- @param path string
--- @return string|nil
local function course_root(path)
  local marker = vim.fs.find('course-info.yaml', { path = path, upward = true, type = 'file' })[1]
  return marker and vim.fs.dirname(marker) or nil
end

--- @param path string
--- @return string|nil
local function task_dir(path)
  local marker = vim.fs.find('task-info.yaml', { path = path, upward = true, type = 'file' })[1]
  return marker and vim.fs.dirname(marker) or nil
end

--- @param path string
--- @return table|nil
local function read_yaml(path)
  if vim.fn.executable('yq') == 0 then
    notify('yq is required to read course metadata (brew install yq)', vim.log.levels.ERROR)
    return nil
  end
  local result = vim.system({ 'yq', '-o=json', '.', path }):wait()
  if result.code ~= 0 then
    notify('could not parse ' .. path .. ': ' .. (result.stderr or ''), vim.log.levels.ERROR)
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, result.stdout)
  return ok and decoded or nil
end

--- The content of a file at a git revision.
--- @param root string
--- @param revision string
--- @param path string absolute
--- @return string|nil
local function at_revision(root, revision, path)
  local relative = path:sub(#root + 2)
  local result = vim.system({ 'git', '-C', root, 'show', revision .. ':' .. relative }):wait()
  if result.code ~= 0 then
    return nil
  end
  return result.stdout
end

--- Blank out a file's answers.
--- @param content string the solution text the offsets index into
--- @param placeholders table[]
--- @return string
local function apply_placeholders(content, placeholders)
  -- back to front, so earlier offsets stay valid
  local ordered = vim.deepcopy(placeholders)
  table.sort(ordered, function(a, b)
    return a.offset > b.offset
  end)
  for _, placeholder in ipairs(ordered) do
    content = content:sub(1, placeholder.offset)
      .. tostring(placeholder.placeholder_text)
      .. content:sub(placeholder.offset + placeholder.length + 1)
  end
  return content
end

--- Whether `content` still holds the answers, rather than being a stub already.
--- Stubbing works back to front, so the lowest-offset placeholder always ends up
--- at exactly its own offset in the result -- finding it there means this text
--- has already been blanked out.
--- @param content string
--- @param placeholders table[]
--- @return boolean
local function holds_answers(content, placeholders)
  local lowest
  for _, placeholder in ipairs(placeholders) do
    if not lowest or placeholder.offset < lowest.offset then
      lowest = placeholder
    end
  end
  if not lowest then
    return true
  end
  if #content < lowest.offset + lowest.length then
    return false
  end
  local text = tostring(lowest.placeholder_text)
  return content:sub(lowest.offset + 1, lowest.offset + #text) ~= text
end

--- Revisions that might hold the solutions, best first.
--- @param root string
--- @return string[]
local function candidate_revisions(root)
  local candidates = { 'refs/koans/solutions' }
  local head = vim.system({ 'git', '-C', root, 'symbolic-ref', '--short', 'refs/remotes/origin/HEAD' }):wait()
  if head.code == 0 then
    table.insert(candidates, vim.trim(head.stdout))
  end
  vim.list_extend(candidates, { 'origin/master', 'origin/main', 'HEAD' })

  local revisions, seen = {}, {}
  for _, candidate in ipairs(candidates) do
    if not seen[candidate] then
      seen[candidate] = true
      if vim.system({ 'git', '-C', root, 'rev-parse', '--verify', '--quiet', candidate }):wait().code == 0 then
        table.insert(revisions, candidate)
      end
    end
  end
  return revisions
end

--- The revision to take solutions from. HEAD is only right while the course is
--- unsolved-side-up: once the stubs are committed (a "remove solutions" commit,
--- a practice branch) HEAD holds stubs, and applying the offsets again would eat
--- into the text. Memoised per course.
--- @type table<string, string>
local resolved = {}

--- @param root string
--- @param dir string a task folder to validate against
--- @param info table that task's task-info.yaml
--- @return string|nil
local function solutions_revision(root, dir, info)
  if resolved[root] then
    return resolved[root]
  end

  local sample, placeholders
  for _, entry in ipairs(info.files or {}) do
    if entry.placeholders and #entry.placeholders > 0 then
      sample, placeholders = dir .. '/' .. entry.name, entry.placeholders
      break
    end
  end
  if not sample then
    return nil
  end

  for _, revision in ipairs(candidate_revisions(root)) do
    local content = at_revision(root, revision, sample)
    if content and holds_answers(content, placeholders) then
      resolved[root] = revision
      return revision
    end
  end

  notify(
    'no solutions found in any of origin/master, origin/main or HEAD; '
      .. 'pin one with :Koan solutions <rev>',
    vim.log.levels.ERROR
  )
  return nil
end

--- Reload any open buffer for `path` so the editor shows what is on disk.
local function reload(path)
  local bufnr = vim.fn.bufnr(path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd('checktime')
    end)
  end
end

--- @param path string
--- @return string|nil
local function read_file(path)
  local file = io.open(path, 'rb')
  if not file then
    return nil
  end
  local content = file:read('*a')
  file:close()
  return content
end

--- @param path string
--- @param content string
local function write_file(path, content)
  local file = assert(io.open(path, 'wb'))
  file:write(content)
  file:close()
  reload(path)
end

--- The vendored course, indexed by `<lesson>/<task>`. `false` once a load has
--- failed, so a missing file is reported once and then quietly falls back.
--- @type table<string, table>|false|nil
local course

--- @return table<string, table>|nil
local function catalog()
  if course ~= nil then
    return course or nil
  end
  course = false

  local content = read_file(CATALOG)
  if not content then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok then
    notify('could not parse ' .. CATALOG, vim.log.levels.WARN)
    return nil
  end

  local index = {}
  for _, lesson in ipairs(decoded.items or {}) do
    for _, entry in ipairs(lesson.task_list or {}) do
      index[lesson.title .. '/' .. entry.name] = entry
    end
  end
  course = index
  return index
end

--- The catalog knows a task by the names its folders still carry.
--- @param dir string task folder
--- @return table|nil
local function catalog_task(dir)
  local index = catalog()
  local lesson = vim.fs.basename(vim.fs.dirname(dir))
  return index and index[lesson .. '/' .. vim.fs.basename(dir)] or nil
end

--- @param entry table|nil a catalog task
--- @param name string a file name or path
--- @return table|nil
local function catalog_file(entry, name)
  local files = entry and entry.task_files
  return files and files[vim.fs.basename(name)] or nil
end

--- Fill a catalog file's blanks back in. The catalog is the mirror image of
--- `task-info.yaml`: it stores the exercise, with each blank's offset pointing
--- at the placeholder and the answer alongside it, where the yaml stores
--- offsets into a solution it does not carry. Filling them reproduces the
--- author's solution byte for byte.
--- @param file table
--- @return string|nil
local function catalog_solution(file)
  local ordered = vim.deepcopy(file.placeholders or {})
  table.sort(ordered, function(a, b)
    return a.offset > b.offset
  end)

  local content = file.text
  for _, placeholder in ipairs(ordered) do
    if not placeholder.possible_answer then
      return nil
    end
    content = content:sub(1, placeholder.offset)
      .. tostring(placeholder.possible_answer)
      .. content:sub(placeholder.offset + placeholder.length + 1)
  end
  return content
end

--- Rewrite a task's files to the exercise state. Files that already are the
--- exercise are left untouched, and so is anything you have since written --
--- only `force` overwrites that.
--- @param dir? string task folder, defaults to the current buffer's task
--- @param force? boolean overwrite work in progress
--- @return table|nil counts { stubbed, already, in_progress }
function stub(dir, force)
  dir = dir or task_dir(vim.api.nvim_buf_get_name(0))
  if not dir then
    notify('not inside a task folder', vim.log.levels.WARN)
    return nil
  end
  local info = read_yaml(dir .. '/task-info.yaml')
  if not info then
    return nil
  end
  local known = catalog_task(dir)

  -- git is only consulted for what the catalog does not cover, and only once
  local root, revision, tried_git
  local function committed(path)
    if not tried_git then
      tried_git = true
      root = git_root(dir)
      if not root then
        notify('not a git checkout, cannot recover the solution text', vim.log.levels.ERROR)
      else
        revision = solutions_revision(root, dir, info)
      end
    end
    return revision and at_revision(root, revision, path) or nil
  end

  local counts = { stubbed = 0, already = 0, in_progress = 0 }
  for _, entry in ipairs(info.files or {}) do
    local placeholders = entry.placeholders or {}
    if #placeholders > 0 then
      local path = dir .. '/' .. entry.name
      local exercise, answers
      local file = catalog_file(known, entry.name)
      if file then
        exercise, answers = file.text, catalog_solution(file)
      else
        -- the yaml offsets index the solution, so always start from that text
        answers = committed(path)
        exercise = answers and apply_placeholders(answers, placeholders)
      end

      if not exercise then
        notify(('no exercise text for %s, skipped'):format(entry.name), vim.log.levels.WARN)
      else
        local current = read_file(path)
        if current == exercise then
          counts.already = counts.already + 1
        elseif current == answers or force then
          write_file(path, exercise)
          counts.stubbed = counts.stubbed + 1
        else
          counts.in_progress = counts.in_progress + 1
        end
      end
    end
  end

  return counts
end

--- The author's answer for the file at `path`, from the catalog if it is
--- covered there and from the committed solution otherwise.
--- @param path string absolute
--- @param dir string its task folder
--- @return string|nil
local function answers_for(path, dir)
  local file = catalog_file(catalog_task(dir), path)
  if file then
    return catalog_solution(file)
  end

  local root = git_root(vim.fs.dirname(path))
  local info = root and read_yaml(dir .. '/task-info.yaml')
  local revision = info and solutions_revision(root, dir, info)
  return revision and at_revision(root, revision, path) or nil
end

--- Open the author's solution for the current task read-only, in a diff split.
function solution()
  local path = vim.api.nvim_buf_get_name(0)
  local dir = task_dir(path)
  if not dir then
    notify('not inside a task folder', vim.log.levels.WARN)
    return
  end
  local content = answers_for(path, dir)
  if not content then
    notify('no solution for ' .. vim.fs.basename(path), vim.log.levels.WARN)
    return
  end

  vim.cmd('diffthis')
  vim.cmd('vnew')
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, '\n'))
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].bufhidden = 'wipe'
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = vim.filetype.match({ filename = path }) or ''
  vim.api.nvim_buf_set_name(bufnr, 'koan://solution/' .. vim.fs.basename(path))
  vim.cmd('diffthis')
end

--- Show the answer to one blank, rather than the whole file `solution` gives.
--- Which blank is asked for when the file has more than one.
local function hint()
  local path = vim.api.nvim_buf_get_name(0)
  local dir = task_dir(path)
  local file = dir and catalog_file(catalog_task(dir), path)
  if not file then
    notify('no hints for ' .. (dir and vim.fs.basename(path) or 'this file'), vim.log.levels.WARN)
    return
  end

  local blanks = vim.tbl_filter(function(placeholder)
    return placeholder.possible_answer ~= nil
  end, file.placeholders or {})
  if #blanks == 0 then
    notify('nothing to fill in here', vim.log.levels.WARN)
    return
  end

  local function show(placeholder)
    local lines = vim.split(tostring(placeholder.possible_answer), '\n')
    local language = vim.filetype.match({ filename = path }) or ''
    table.insert(lines, 1, '```' .. language)
    table.insert(lines, '```')
    vim.lsp.util.open_floating_preview(lines, 'markdown', { border = 'rounded', focus = false })
  end

  if #blanks == 1 then
    show(blanks[1])
    return
  end
  vim.ui.select(blanks, {
    prompt = 'Which blank?',
    format_item = function(placeholder)
      -- the blank as it reads in the exercise, enough to tell them apart
      return vim.split(tostring(placeholder.placeholder_text), '\n')[1]
    end,
  }, function(choice)
    if choice then
      show(choice)
    end
  end)
end

--- Open the task description: the checked out `task.md`, or the catalog's copy
--- of it for a course that ships without one.
function task()
  local dir = task_dir(vim.api.nvim_buf_get_name(0))
  if not dir then
    notify('not inside a task folder', vim.log.levels.WARN)
    return
  end

  if vim.fn.filereadable(dir .. '/task.md') == 1 then
    vim.cmd('vsplit ' .. vim.fn.fnameescape(dir .. '/task.md'))
    return
  end

  local known = catalog_task(dir)
  if not known or not known.description_text then
    notify('no description for this task', vim.log.levels.WARN)
    return
  end

  vim.cmd('vnew')
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(known.description_text, '\n'))
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].bufhidden = 'wipe'
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = 'markdown'
  vim.api.nvim_buf_set_name(bufnr, 'koan://task/' .. vim.fs.basename(dir))
end

--- Every task folder in course order.
--- @param root string
--- @return string[]
local function ordered_tasks(root)
  local course = read_yaml(root .. '/course-info.yaml')
  if not course then
    return {}
  end
  local tasks = {}
  for _, lesson in ipairs(course.content or {}) do
    local lesson_dir = root .. '/' .. lesson
    local lesson_info = read_yaml(lesson_dir .. '/lesson-info.yaml')
    for _, task in ipairs(lesson_info and lesson_info.content or {}) do
      local dir = lesson_dir .. '/' .. task
      -- a renamed folder simply drops out of the ordering
      if vim.fn.isdirectory(dir) == 1 then
        table.insert(tasks, dir)
      end
    end
  end
  return tasks
end

--- Point an open task description at the task just moved to, so `next` carries
--- the whole reading setup along rather than leaving a stale description behind.
--- @param target string task folder
local function follow_task_split(target)
  local description = target .. '/task.md'
  if vim.fn.filereadable(description) == 0 then
    return
  end
  local moved_in = vim.api.nvim_get_current_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
    if win ~= moved_in and name:match('/task%.md$') and name ~= description then
      vim.api.nvim_win_call(win, function()
        vim.cmd('edit ' .. vim.fn.fnameescape(description))
      end)
    end
  end
end

--- @param offset integer
local function move(offset)
  local path = vim.api.nvim_buf_get_name(0)
  local root = course_root(path ~= '' and path or vim.uv.cwd())
  if not root then
    notify('not inside a course', vim.log.levels.WARN)
    return
  end
  local tasks = ordered_tasks(root)
  local current = task_dir(path)
  local index = 0
  for i, dir in ipairs(tasks) do
    if dir == current then
      index = i
      break
    end
  end
  local target = tasks[index + offset] or (offset > 0 and tasks[1] or tasks[#tasks])
  if not target then
    notify('no tasks found', vim.log.levels.WARN)
    return
  end
  local sources = vim.fn.glob(target .. '/src/*', false, true)
  if #sources == 0 then
    notify('no source file in ' .. target, vim.log.levels.WARN)
    return
  end
  vim.cmd('edit ' .. vim.fn.fnameescape(sources[1]))
  follow_task_split(target)
  notify(vim.fs.basename(vim.fs.dirname(target)) .. ' / ' .. vim.fs.basename(target))
end

--- @param counts table
--- @return string
local function summarise(counts)
  return ('stubbed %d · already %d · in progress %d')
    :format(counts.stubbed, counts.already, counts.in_progress)
end

--- Put every task in the course into its exercise state, leaving alone the ones
--- that are there already and the ones you have started.
function stub_all()
  local path = vim.api.nvim_buf_get_name(0)
  local root = course_root(path ~= '' and path or vim.uv.cwd())
  if not root then
    notify('not inside a course', vim.log.levels.WARN)
    return
  end

  local total = { stubbed = 0, already = 0, in_progress = 0 }
  for _, dir in ipairs(ordered_tasks(root)) do
    local counts = stub(dir)
    if not counts then
      return
    end
    for key, value in pairs(counts) do
      total[key] = total[key] + value
    end
  end
  notify(summarise(total))
end

--- Force the current task back to its exercise state, work in progress and all.
local function reset()
  local dir = task_dir(vim.api.nvim_buf_get_name(0))
  if not dir then
    notify('not inside a task folder', vim.log.levels.WARN)
    return
  end
  local prompt = ('Discard your work in %s and restore the exercise?'):format(vim.fs.basename(dir))
  if vim.fn.confirm(prompt, '&Yes\n&No', 2) ~= 1 then
    return
  end
  local counts = stub(dir, true)
  if counts then
    notify(('%s: %s'):format(vim.fs.basename(dir), summarise(counts)))
  end
end

--- Markers of a file that actually declares tests. Hidden files also hold plain
--- fixtures (koans ship a `TestShop.kt` of sample data), and handing one of
--- those to neotest just reports "No tests found".
local TEST_MARKERS = { '@Test', '@ParameterizedTest', '@RepeatedTest', '@TestFactory', 'def test', 'func Test' }

--- @param path string
--- @return boolean
local function declares_tests(path)
  local content = read_file(path)
  if not content then
    return false
  end
  for _, marker in ipairs(TEST_MARKERS) do
    if content:find(marker, 1, true) then
      return true
    end
  end
  return false
end

--- The task's test files. `task-info.yaml` marks them as hidden from the
--- student, which beats guessing from the folder layout.
--- @param dir string task folder
--- @return string[]
local function test_files(dir)
  local files = {}
  local info = read_yaml(dir .. '/task-info.yaml')
  for _, entry in ipairs(info and info.files or {}) do
    if entry.visible == false then
      table.insert(files, dir .. '/' .. entry.name)
    end
  end
  if #files == 0 then
    files = vim.fn.glob(dir .. '/test/*', false, true)
  end

  local readable = vim.tbl_filter(function(path)
    return vim.fn.filereadable(path) == 1
  end, files)
  local with_tests = vim.tbl_filter(declares_tests, readable)
  -- an unrecognised test framework should still get a run attempt
  return #with_tests > 0 and with_tests or readable
end

--- Run the task's tests, from anywhere inside the task -- `src/Task.kt` and
--- `test/tests.kt` both check the same thing.
local function check()
  local dir = task_dir(vim.api.nvim_buf_get_name(0))
  if not dir then
    notify('not inside a task folder', vim.log.levels.WARN)
    return
  end
  local ok, neotest = pcall(require, 'neotest')
  if not ok then
    notify('neotest is not available', vim.log.levels.ERROR)
    return
  end

  local files = test_files(dir)
  if #files == 0 then
    notify('no test files in ' .. vim.fs.basename(dir), vim.log.levels.WARN)
    return
  end

  -- the run itself is silent unless something is watching it, so put the output
  -- panel up first and hand focus straight back
  local from = vim.api.nvim_get_current_win()
  neotest.output_panel.open()
  pcall(vim.api.nvim_set_current_win, from)

  notify(('running %s (%d test file(s))'):format(vim.fs.basename(dir), #files))
  for _, path in ipairs(files) do
    neotest.run.run(path)
  end
end

--- Report where solutions are read from, or pin a git revision to read them
--- from. Pinning only matters for a task the catalog does not cover.
--- @param revision? string
local function solutions(revision)
  local path = vim.api.nvim_buf_get_name(0)
  local root = git_root(path ~= '' and vim.fs.dirname(path) or vim.uv.cwd())
  if not root then
    notify('not a git checkout', vim.log.levels.ERROR)
    return
  end

  local here = task_dir(path)
  if (not revision or revision == '') and here and catalog_file(catalog_task(here), path) then
    notify('solutions read from ' .. vim.fn.fnamemodify(CATALOG, ':~'))
    return
  end

  if revision and revision ~= '' then
    local result = vim.system({ 'git', '-C', root, 'update-ref', 'refs/koans/solutions', revision }):wait()
    if result.code ~= 0 then
      notify(('could not pin %s: %s'):format(revision, vim.trim(result.stderr or '')), vim.log.levels.ERROR)
      return
    end
    resolved[root] = nil
    notify('solutions pinned to ' .. revision)
    return
  end

  local dir = task_dir(path) or ordered_tasks(course_root(root) or root)[1]
  local info = dir and read_yaml(dir .. '/task-info.yaml')
  local current = info and solutions_revision(root, dir, info)
  if current then
    notify('solutions read from ' .. current)
  end
end

local subcommands = {
  check = check,
  stub = function()
    local counts = stub()
    if counts then
      notify(summarise(counts))
    end
  end,
  ['stub-all'] = stub_all,
  reset = reset,
  hint = hint,
  solution = solution,
  solutions = solutions,
  task = task,
  next = function()
    move(1)
  end,
  prev = function()
    move(-1)
  end,
}

return {
  'koans',
  virtual = true,
  cmd = 'Koan',
  cond = function()
    return vim.fs.find('course-info.yaml', {
      path = vim.uv.cwd(),
      upward = true,
      type = 'file',
    })[1] ~= nil
  end,
  config = function()
    vim.api.nvim_create_user_command('Koan', function(opts)
      -- `solutions` takes an optional revision, the rest take nothing
      local name = opts.fargs[1]
      local run = name and subcommands[name]
      if not run then
        notify('usage: :Koan ' .. table.concat(vim.tbl_keys(subcommands), '|'), vim.log.levels.WARN)
        return
      end
      run(unpack(opts.fargs, 2))
    end, {
      nargs = '+',
      desc = 'JetBrains Academy course helpers',
      complete = function(lead, line)
        if line:match('^%s*Koan%s+%S+%s') then
          return {}
        end
        return vim.tbl_filter(function(name)
          return name:find(lead, 1, true) == 1
        end, vim.tbl_keys(subcommands))
      end,
    })
  end,
}
