-- `:checkhealth kotlin-workflow`: one Kotlin client per buffer, installed vs
-- locked Mason versions, analysis JDK and heap, Spring classpath snapshot,
-- processes this Neovim started, and where the logs are.
local M = {}
local h = vim.health

--- language servers that claim Kotlin semantics; at most one per buffer
local PRIMARY = { kotlin_lsp = true, kotlin_language_server = true, intellij = true, intellij_lsp = true }

local function mason_dir()
  return vim.fn.stdpath('data') .. '/mason'
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

--- installed version as mason-lock records it: the receipt purl's version
local function installed_version(name)
  local receipt = read_json(mason_dir() .. '/packages/' .. name .. '/mason-receipt.json')
  local id = receipt and receipt.source and receipt.source.id
  local version = id and id:match('@(.+)$')
  return version and (version:gsub('%%(%x%x)', function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

local function check_clients()
  h.start('Kotlin clients')
  local any = false
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == 'kotlin' then
      any = true
      local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':~:.')
      local primaries, others = {}, {}
      for _, c in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
        table.insert(PRIMARY[c.name] and primaries or others, c.name)
      end
      if #primaries == 1 then
        h.ok(('%s: %s'):format(name, primaries[1]))
      elseif #primaries == 0 then
        h.info(('%s: no Kotlin client attached (yet)'):format(name))
      else
        h.error(('%s: %d Kotlin clients: %s'):format(name, #primaries, table.concat(primaries, ', ')), {
          'Stop all but kotlin_lsp (`:lsp stop <name>`) and remove the extra server',
        })
      end
      if vim.tbl_contains(others, 'spring-boot') then
        h.warn(name .. ': spring-boot is attached; it should own yaml/properties only')
      end
    end
  end
  if not any then
    h.info('No Kotlin buffer loaded')
  end
  local fwcd = vim.fn.isdirectory(mason_dir() .. '/packages/kotlin-language-server') == 1
  if fwcd then
    h.warn('fwcd kotlin-language-server is installed', { 'Uninstall it: `:MasonUninstall kotlin-language-server`' })
  end
end

local function check_versions()
  h.start('Mason versions')
  local lock_path = vim.fn.stdpath('config') .. '/mason-lock.json'
  local lock = read_json(lock_path)
  if not lock then
    h.error('No readable mason-lock.json', { 'Write one with `:MasonLock` and commit it' })
    return
  end
  local installed = {}
  for name, _ in vim.fs.dir(mason_dir() .. '/packages') do
    installed[name] = installed_version(name) or '?'
  end
  local drift = {}
  for name, version in pairs(lock) do
    if not installed[name] then
      table.insert(drift, ('%s: locked %s, not installed'):format(name, version))
    elseif installed[name] ~= version then
      table.insert(drift, ('%s: locked %s, installed %s'):format(name, version, installed[name]))
    end
  end
  for name, version in pairs(installed) do
    if lock[name] == nil then
      table.insert(drift, ('%s: installed %s, not in the lock'):format(name, version))
    end
  end
  table.sort(drift)
  if #drift == 0 then
    h.ok(('%d packages match mason-lock.json'):format(vim.tbl_count(lock)))
  else
    for _, d in ipairs(drift) do
      h.warn(d)
    end
    h.info('Rollback: restore mason-lock.json from git, then `:MasonLockRestore`; or accept with `:MasonLock`')
  end
  for _, name in ipairs({ 'kotlin-lsp', 'vscode-spring-boot-tools', 'java-debug-adapter' }) do
    h.info(('%s %s'):format(name, installed[name] or 'not installed'))
  end
end

local function check_server()
  h.start('kotlin-lsp')
  local ok, lazy_config = pcall(require, 'lazy.core.config')
  local plugin = ok and lazy_config.plugins['kotlin.nvim']
  if plugin then
    local opts = require('lazy.core.plugin').values(plugin, 'opts', false)
    h.info('Analysis JDK: ' .. tostring(opts.jdk_for_symbol_resolution or '(auto: $JAVA_HOME)'))
    h.info('Configured JVM args: ' .. table.concat(opts.jvm_args or {}, ' '))
  end
  local jvm = require('kotlin-workflow.jvm')
  local clients = vim.lsp.get_clients({ name = 'kotlin_lsp' })
  if #clients == 0 then
    h.info('kotlin-lsp not running')
  end
  for _, c in ipairs(clients) do
    local pid = jvm.client_pid(c)
    local used, max
    if pid then
      used, max = jvm.heap_sync(pid)
    end
    local line = ('pid %s, root %s, heap %s / %s'):format(
      tostring(pid),
      vim.fn.fnamemodify(c.root_dir or '?', ':~'),
      jvm.format(used),
      jvm.format(max)
    )
    if max and max < 7.5 * 1024 ^ 3 then
      h.warn(line, { 'Max heap below 8 GiB: restart the server after changing jvm_args (`:lsp restart kotlin_lsp`)' })
    elseif max then
      h.ok(line)
    else
      h.info(line .. ' (jcmd attach failed)')
    end
    local system_path = require('kotlin.workspace').system_path_for(c)
    if system_path then
      h.info('Server log: ' .. system_path .. '/system/log/intellij-server.log (`<leader>kl`)')
      h.info('Workspace (wipe with `<leader>kw`): ' .. system_path)
    end
  end
end

local function check_optional(module, title)
  local ok, mod = pcall(require, module)
  if ok and type(mod.health) == 'function' then
    h.start(title)
    mod.health(h)
  end
end

local function check_jobs()
  h.start('Processes started from this Neovim')
  local jobs = require('kotlin-workflow.jobs').list()
  if #jobs == 0 then
    h.ok('None running')
    return
  end
  for _, j in ipairs(jobs) do
    h.info(
      ('%s pid %d: %s%s (since %s)'):format(
        j.kind,
        j.pid,
        j.label,
        j.debug_port and (' JDWP ' .. j.debug_port) or '',
        os.date('%H:%M:%S', j.started)
      )
    )
  end
end

function M.check()
  check_clients()
  check_versions()
  check_server()
  check_optional('spring-classpath', 'Spring Boot classpath')
  check_optional('kotlin-quality', 'Quality checks')
  check_jobs()
  h.start('Logs')
  h.info('Neovim LSP log: ' .. vim.lsp.log.get_filename())
end

return M
