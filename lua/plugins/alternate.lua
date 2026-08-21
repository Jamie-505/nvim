-- Jump between an implementation file and its test, in any project.
--
-- No per-project configuration: the counterpart is derived from the file name
-- (Foo -> FooTest, TestFoo, foo_test, foo.spec, ...) and from the usual
-- directory swaps (test <-> src, test <-> main, test <-> lib, __tests__ -> .).
-- Direct hits are checked first, then a name search under the repo root, and
-- anything still ambiguous goes to vim.ui.select.
--
-- A virtual plugin: nothing to install, loaded on first use.

--- Directory segments that pair up. Applied in both directions.
local DIR_SWAPS = {
  { 'test', 'src' },
  { 'tests', 'src' },
  { 'test', 'main' },
  { 'tests', 'main' },
  { 'test', 'lib' },
  { 'tests', 'lib' },
  { 'spec', 'src' },
  { 'spec', 'lib' },
  { '__tests__', '' },
}

--- Name affixes that mark a test file. Longest first, so that `Tests` wins over
--- `Test` and `.spec` over `Spec` -- otherwise `foo.spec` would strip down to
--- `foo.` rather than `foo`.
local SUFFIXES = {
  '.tests',
  '.test',
  '.spec',
  '_tests',
  '_test',
  '_spec',
  '-tests',
  '-test',
  '-spec',
  'Tests',
  'Test',
  'Spec',
}
local PREFIXES = { 'test_', 'test-', 'Test' }

--- Basenames that name the test of a whole folder rather than of one file.
local GENERIC = { test = true, tests = true, spec = true, specs = true }

--- @param path string
--- @return string|nil
local function repo_root(path)
  local marker = vim.fs.find({ '.git' }, { path = vim.fs.dirname(path), upward = true })[1]
  return marker and vim.fs.dirname(marker) or vim.uv.cwd()
end

--- @param name string basename without extension
--- @return string|nil base the name with its test affix removed
local function strip_affix(name)
  for _, suffix in ipairs(SUFFIXES) do
    if #name > #suffix and name:sub(-#suffix):lower() == suffix:lower() then
      -- drop a separator the affix left behind (Foo.Spec -> Foo. -> Foo)
      return (name:sub(1, #name - #suffix):gsub('[%.%-_]$', ''))
    end
  end
  for _, prefix in ipairs(PREFIXES) do
    if #name > #prefix and name:sub(1, #prefix):lower() == prefix:lower() then
      return name:sub(#prefix + 1)
    end
  end
  return nil
end

--- @param path string
--- @return boolean
local function is_test(path)
  local name = vim.fn.fnamemodify(path, ':t:r')
  if GENERIC[name:lower()] or strip_affix(name) then
    return true
  end
  for segment in vim.fs.dirname(path):gmatch('[^/]+') do
    local lower = segment:lower()
    if lower == 'test' or lower == 'tests' or lower == 'spec' or lower == '__tests__' then
      return true
    end
  end
  return false
end

--- Names the counterpart could have, without extension. The affixed names are
--- specific enough to search the whole repo for; the bare and generic ones only
--- mean anything inside a paired folder, where `Foo.kt` in `test/` is the test
--- of `Foo.kt` in `src/`.
--- @param name string
--- @param test boolean whether the *current* file is the test
--- @return string[] affixed, string[] paired
local function candidate_names(name, test)
  if test then
    local base = strip_affix(name)
    return base and { base } or {}, { name }
  end

  local affixed = {}
  for _, suffix in ipairs(SUFFIXES) do
    table.insert(affixed, name .. suffix)
  end
  for _, prefix in ipairs(PREFIXES) do
    table.insert(affixed, prefix .. name)
  end
  return affixed, { name, 'tests', 'test', 'spec' }
end

--- Directories the counterpart could live in.
--- @param dir string
--- @return string[]
local function candidate_dirs(dir)
  local dirs = { dir }
  local seen = { [dir] = true }

  for _, pair in ipairs(DIR_SWAPS) do
    for _, direction in ipairs({ { pair[1], pair[2] }, { pair[2], pair[1] } }) do
      local from, to = direction[1], direction[2]
      if from ~= '' then
        local segments = vim.split(dir, '/')
        local changed = false
        local swapped = {}
        for _, segment in ipairs(segments) do
          if segment:lower() == from then
            changed = true
            if to ~= '' then
              table.insert(swapped, to)
            end
          else
            table.insert(swapped, segment)
          end
        end
        local candidate = table.concat(swapped, '/')
        if changed and not seen[candidate] then
          seen[candidate] = true
          table.insert(dirs, candidate)
        end
      end
    end
  end

  return dirs
end

--- How many leading path segments two paths share; the counterpart sitting in
--- the same module beats one with the same name across the repo.
--- @return integer
local function proximity(a, b)
  local left, right = vim.split(a, '/'), vim.split(b, '/')
  local shared = 0
  for i = 1, math.min(#left, #right) do
    if left[i] ~= right[i] then
      break
    end
    shared = i
  end
  return shared
end

--- Every file under `root` whose basename is one of `names` (any extension).
--- @param root string
--- @param names string[]
--- @return string[]
local function search(root, names)
  if vim.fn.executable('fd') == 0 or #names == 0 then
    return {}
  end
  local escaped = vim.tbl_map(function(name)
    return vim.pesc(name):gsub('%%', '\\')
  end, names)
  local pattern = '^(' .. table.concat(escaped, '|') .. ')\\.[^.]+$'
  local result = vim
    .system({ 'fd', '--type', 'f', '--hidden', '--absolute-path', '--exclude', '.git', pattern, root })
    :wait()
  if result.code ~= 0 then
    return {}
  end
  return vim.split(vim.trim(result.stdout or ''), '\n', { trimempty = true })
end

--- @param path string
--- @return string[]
local function counterparts(path)
  local dir = vim.fs.dirname(path)
  local name = vim.fn.fnamemodify(path, ':t:r')
  local extension = vim.fn.fnamemodify(path, ':e')
  local test = is_test(path)
  local dirs = candidate_dirs(dir)

  local found, seen = {}, { [path] = true }
  local function add(candidate)
    if not seen[candidate] and vim.fn.filereadable(candidate) == 1 then
      seen[candidate] = true
      table.insert(found, candidate)
    end
  end

  local affixed, paired = candidate_names(name, test)

  -- a name that spells out the pairing (FooTest) is the strongest signal
  for _, candidate_dir in ipairs(dirs) do
    for _, candidate in ipairs(affixed) do
      add(candidate_dir .. '/' .. candidate .. '.' .. extension)
    end
  end

  -- otherwise the same or a folder-wide name (tests.kt), across a folder pair
  if #found == 0 then
    for _, candidate_dir in ipairs(dirs) do
      if candidate_dir ~= dir then
        for _, candidate in ipairs(paired) do
          add(candidate_dir .. '/' .. candidate .. '.' .. extension)
        end
      end
    end
  end

  -- a test named after its folder has no name to work from, so offer what lives
  -- in the paired folder, minus the files that have a test of their own
  if #found == 0 and test and GENERIC[name:lower()] then
    for _, candidate_dir in ipairs(dirs) do
      if candidate_dir ~= dir then
        for _, entry in ipairs(vim.fn.glob(candidate_dir .. '/*.' .. extension, false, true)) do
          local claimed = false
          for _, candidate in ipairs(({ candidate_names(vim.fn.fnamemodify(entry, ':t:r'), false) })[1]) do
            if vim.fn.filereadable(dir .. '/' .. candidate .. '.' .. extension) == 1 then
              claimed = true
              break
            end
          end
          if not claimed then
            add(entry)
          end
        end
      end
    end
  end

  if #found == 0 then
    for _, candidate in ipairs(search(repo_root(path), affixed)) do
      add(candidate)
    end
  end

  -- prefer a counterpart of the same kind, nearest in the tree
  table.sort(found, function(a, b)
    local a_matches = (vim.fn.fnamemodify(a, ':e') == extension) and 1 or 0
    local b_matches = (vim.fn.fnamemodify(b, ':e') == extension) and 1 or 0
    if a_matches ~= b_matches then
      return a_matches > b_matches
    end
    local a_near, b_near = proximity(path, a), proximity(path, b)
    if a_near ~= b_near then
      return a_near > b_near
    end
    return #a < #b
  end)

  return found
end

--- @param command string
local function alternate(command)
  local path = vim.api.nvim_buf_get_name(0)
  if path == '' then
    vim.notify('no file in this buffer', vim.log.levels.WARN, { title = 'Alternate' })
    return
  end

  local found = counterparts(path)
  local function open(target)
    vim.cmd(command .. ' ' .. vim.fn.fnameescape(target))
  end

  if #found == 0 then
    vim.notify(
      ('no counterpart for %s'):format(vim.fn.fnamemodify(path, ':t')),
      vim.log.levels.WARN,
      { title = 'Alternate' }
    )
  elseif #found == 1 then
    open(found[1])
  else
    local root = repo_root(path)
    vim.ui.select(found, {
      prompt = is_test(path) and 'Implementation file' or 'Test file',
      format_item = function(item)
        return item:sub(#root + 2)
      end,
    }, function(choice)
      if choice then
        open(choice)
      end
    end)
  end
end

return {
  'alternate',
  virtual = true,
  cmd = { 'A', 'AV', 'AS' },
  keys = {
    {
      '<leader>a',
      function()
        alternate('edit')
      end,
      desc = 'Alternate file (source <-> test)',
    },
  },
  config = function()
    local commands = { A = 'edit', AV = 'vsplit', AS = 'split' }
    for name, command in pairs(commands) do
      vim.api.nvim_create_user_command(name, function()
        alternate(command)
      end, { desc = 'Jump to the source/test counterpart (' .. command .. ')' })
    end
  end,
}
