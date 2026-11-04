-- Gradle projects and their quality tasks, as the init script reports them
-- (`-Pnvim.quality.discover`). Cached in stdpath('state') per build root until
-- a build file (or the init script) is newer than the cache.
local M = {}

M.init_script = vim.fn.stdpath('config') .. '/gradle/quality.init.gradle'

local function state_dir(root)
  local dir = vim.fn.stdpath('state')
    .. '/kotlin-quality/'
    .. vim.fs.basename(root)
    .. '-'
    .. vim.fn.sha256(root):sub(1, 8)
  vim.fn.mkdir(dir, 'p')
  return dir
end
M.state_dir = state_dir

local function mtime(path)
  local st = path and vim.uv.fs_stat(path)
  return st and st.mtime.sec or nil
end

local function read_json(path)
  local f = io.open(path, 'r')
  if not f then
    return nil
  end
  local ok, data = pcall(vim.json.decode, f:read('*a'))
  f:close()
  return ok and data or nil
end
M.read_json = read_json

--- files whose change can change the project list or the task set
local function build_files(root, disc)
  local files = {
    M.init_script,
    root .. '/settings.gradle.kts',
    root .. '/settings.gradle',
    root .. '/gradle.properties',
    root .. '/gradle/libs.versions.toml',
  }
  for _, p in ipairs(disc and disc.projects or {}) do
    if p.buildFile then
      table.insert(files, p.buildFile)
    end
  end
  return files
end

--- @return boolean stale, string? newer
local function is_stale(root, disc, cache)
  local cached = mtime(cache)
  if not cached then
    return true
  end
  for _, f in ipairs(build_files(root, disc)) do
    local t = mtime(f)
    if t and t > cached then
      return true, f
    end
  end
  return false
end

--- Nearest Gradle build from the cwd: the directory of the nearest `gradlew`.
--- @return string? root, string? gradlew
function M.root()
  local wrapper = vim.fs.find('gradlew', { path = vim.fn.getcwd(), upward = true, type = 'file' })[1]
  if not wrapper then
    return nil
  end
  return vim.fs.dirname(wrapper), wrapper
end

--- cached discovery, or nil when missing/stale
function M.cached(root)
  local cache = state_dir(root) .. '/discovery.json'
  local disc = read_json(cache)
  if disc and not is_stale(root, disc, cache) then
    return disc
  end
end

--- @param root string
--- @param gradlew string
--- @param cb fun(disc: table?, err: string?)
--- @param force? boolean ignore the cache
--- @return vim.SystemObj? running discovery, when one was started
function M.get(root, gradlew, cb, force)
  local dir = state_dir(root)
  local cache = dir .. '/discovery.json'
  if not force then
    local disc = M.cached(root)
    if disc then
      cb(disc)
      return
    end
  end
  local out = dir .. '/discovery.tmp.json'
  os.remove(out)
  local argv = {
    gradlew,
    '-q',
    'help',
    '-I',
    M.init_script,
    '-Pnvim.quality.discover=' .. out,
    '--no-configuration-cache',
    '--console=plain',
  }
  return vim.system(argv, { cwd = root, text = true }, function(r)
    vim.schedule(function()
      local disc = r.code == 0 and read_json(out)
      if not disc then
        local f = io.open(dir .. '/discovery.log', 'w')
        if f then
          f:write(table.concat(argv, ' '), '\n\n', r.stdout or '', r.stderr or '')
          f:close()
        end
        return cb(nil, ('discovery failed (exit %s), log: %s'):format(tostring(r.code), dir .. '/discovery.log'))
      end
      disc.discovered = os.time()
      local f = assert(io.open(cache, 'w'))
      f:write(vim.json.encode(disc))
      f:close()
      os.remove(out)
      cb(disc)
    end)
  end)
end

return M
