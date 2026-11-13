-- kotlin-lsp builds are EAP and stop starting after about a month: the launcher
-- prints "This build of kotlin-server has expired" and exits with code 7.
-- When that happens, show installed vs latest (release dates + changelog of
-- everything in between) and offer a one-key update.
--
-- Mason's registry lags JetBrains' releases by days, so the latest version comes
-- from GitHub; Mason installs it by tag (its download URL is a version template).
-- mason-lock rewrites mason-lock.json on install.

local M = {}

local EXPIRED_EXIT_CODE = 7
local PACKAGE = 'kotlin-lsp'
local RELEASES_API = 'https://api.github.com/repos/Kotlin/kotlin-lsp/releases?per_page=30'
local RELEASES_MD = 'https://raw.githubusercontent.com/Kotlin/kotlin-lsp/main/RELEASES.md'

local opts_for_restart
local showing = false

--- 'kotlin-lsp/v271.2085.0' / 'v271.2085.0' → '271.2085.0'
local function bare(version)
  return version and (version:gsub('^kotlin%-lsp/', ''):gsub('^v', ''))
end

local function fetch(url, cb)
  vim.system({ 'curl', '-fsSL', '--max-time', '20', '-H', 'User-Agent: nvim', url }, { text = true }, function(r)
    vim.schedule(function()
      cb(r.code == 0 and r.stdout or nil, r.code ~= 0 and (r.stderr ~= '' and r.stderr or ('curl exit ' .. r.code)) or nil)
    end)
  end)
end

--- RELEASES.md (newest first) → { [version] = changelog lines }, ordered versions
local function parse_changelogs(md)
  local logs, order, cur, in_log = {}, {}, nil, false
  for line in (md .. '\n'):gmatch('(.-)\r?\n') do
    local v = line:match('^###%s+v(%S+)')
    if v then
      cur, in_log = v, false
      logs[v] = {}
      table.insert(order, v)
    elseif cur and line:match('^#####%s+Changelog') then
      in_log = true
    elseif cur and in_log then
      line = line:gsub('%s*<!%-%-.-%-%->', '')
      table.insert(logs[cur], line)
    end
  end
  for _, v in ipairs(order) do
    local l = logs[v]
    while #l > 0 and l[#l]:match('^%s*$') do
      table.remove(l)
    end
    while #l > 0 and l[1]:match('^%s*$') do
      table.remove(l, 1)
    end
    -- demote headings below the per-version `##`
    for i, s in ipairs(l) do
      l[i] = s:gsub('^(#+)', '%1#')
    end
  end
  return logs, order
end

local function days_ago(iso)
  local y, mo, d = iso:match('^(%d+)-(%d+)-(%d+)')
  if not y then
    return ''
  end
  local n = math.floor((os.time() - os.time({ year = y, month = mo, day = d, hour = 12 })) / 86400 + 0.5)
  return n <= 0 and 'today' or n == 1 and '1 day ago' or (n .. ' days ago')
end

local function install(tag, win)
  local registry = require('mason-registry')
  local pkg = registry.get_package(PACKAGE)
  if pkg:is_installing() then
    return Snacks.notify.warn('kotlin-lsp is already installing')
  end
  if win then
    win:close()
  end
  Snacks.notify.info('Installing ' .. bare(tag) .. '…', { title = 'kotlin-lsp' })
  pkg:install({ version = tag }, function(ok, result)
    vim.schedule(function()
      if not ok then
        return Snacks.notify.error('Install failed: ' .. tostring(result), { title = 'kotlin-lsp' })
      end
      Snacks.notify.info(('Installed %s; restarting the server (mason-lock.json updated, commit it)'):format(bare(tag)), {
        title = 'kotlin-lsp',
      })
      -- kotlin.nvim resolves the versioned server path when it (re)configures,
      -- so reconfigure from a kotlin buffer; enabling starts clients again
      local buf = vim.iter(vim.api.nvim_list_bufs()):find(function(b)
        return vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == 'kotlin'
      end)
      if buf then
        vim.api.nvim_buf_call(buf, function()
          require('kotlin').setup_kotlin_lsp(opts_for_restart)
        end)
      end
    end)
  end)
end

local function show(installed, releases, logs)
  local latest = releases[1]
  local by_version = {}
  for _, r in ipairs(releases) do
    by_version[bare(r.tag_name)] = r
  end
  local cur = by_version[installed]
  local lines = {
    '# kotlin-lsp build expired',
    '',
    ('- Installed: `%s`%s'):format(
      installed,
      cur and (' (released %s, %s)'):format(cur.published_at:sub(1, 10), days_ago(cur.published_at)) or ''
    ),
    ('- Latest:    `%s` (released %s, %s)'):format(
      bare(latest.tag_name),
      latest.published_at:sub(1, 10),
      days_ago(latest.published_at)
    ),
    '',
  }
  local newer = bare(latest.tag_name) ~= installed
  if newer then
    table.insert(lines, '`u` update + restart server · `q` close')
    for _, r in ipairs(releases) do
      local v = bare(r.tag_name)
      if v == installed then
        break
      end
      vim.list_extend(lines, { '', ('## %s (%s)'):format(v, r.published_at:sub(1, 10)), '' })
      local log = logs[v]
      vim.list_extend(lines, log and #log > 0 and log or { '_No changelog in RELEASES.md._' })
    end
  else
    vim.list_extend(lines, { 'No newer release yet. Watch https://github.com/Kotlin/kotlin-lsp/releases', '', '`q` close' })
  end

  showing = true
  local win = Snacks.win({
    text = lines,
    ft = 'markdown',
    width = 0.7,
    height = 0.8,
    border = 'rounded',
    title = ' kotlin-lsp ',
    wo = { wrap = true, linebreak = true, conceallevel = 2 },
    keys = { q = 'close' },
    on_close = function()
      showing = false
    end,
  })
  if newer then
    vim.keymap.set('n', 'u', function()
      install(latest.tag_name, win)
    end, { buffer = win.buf, desc = 'Update kotlin-lsp' })
  end
end

--- Look up installed vs latest and open the update window.
function M.prompt()
  if showing then
    return
  end
  local ok, pkg = pcall(function()
    return require('mason-registry').get_package(PACKAGE)
  end)
  local installed = ok and bare(pkg:get_installed_version()) or '?'
  fetch(RELEASES_API, function(json, err)
    if not json then
      return Snacks.notify.error('Could not fetch releases: ' .. err, { title = 'kotlin-lsp expired' })
    end
    local releases = vim.tbl_filter(function(r)
      return not r.draft and not r.prerelease and r.tag_name:match('^kotlin%-lsp/v')
    end, vim.json.decode(json))
    if #releases == 0 then
      return Snacks.notify.error('No releases found on GitHub', { title = 'kotlin-lsp expired' })
    end
    fetch(RELEASES_MD, function(md)
      local logs = md and parse_changelogs(md) or {}
      show(installed, releases, logs)
    end)
  end)
end

--- Catch the expiry exit on every kotlin_lsp start, including `:lsp restart`.
--- kotlin.nvim reassigns its config on each kotlin buffer, so the hook goes on
--- vim.lsp.start rather than the config.
function M.setup(opts)
  opts_for_restart = opts
  if M._hooked then
    return
  end
  M._hooked = true
  local start = vim.lsp.start
  vim.lsp.start = function(config, ...)
    if config and config.name == 'kotlin_lsp' and not config._expiry_hooked then
      local orig = config.on_exit
      config._expiry_hooked = true
      config.on_exit = function(code, signal, id)
        if code == EXPIRED_EXIT_CODE then
          vim.schedule(M.prompt)
          return
        end
        for _, cb in ipairs(vim._ensure_list(orig)) do
          cb(code, signal, id)
        end
      end
    end
    return start(config, ...)
  end
end

return M
