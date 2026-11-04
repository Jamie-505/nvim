-- Heap readings for running JVMs through `jcmd <pid> GC.heap_info` (~0.05 s per
-- call). The output differs per collector: G1 (Gradle daemons, kotlin-lsp's
-- JBR) reports `total reserved` (the max heap) and `used`; ZGC (the Spring Boot
-- language server) reports `used` and `max capacity`. Anything else falls back
-- to summing `used` figures and reading MaxHeapSize from `VM.flags`.
local M = {}

local jcmd_path
local function jcmd()
  if not jcmd_path then
    local home = require('jdk').find('25') or vim.env.JAVA_HOME
    jcmd_path = home and (home .. '/bin/jcmd') or 'jcmd'
  end
  return jcmd_path
end

local UNIT = { K = 1024, M = 1024 ^ 2, G = 1024 ^ 3 }

local function bytes(n, unit)
  return tonumber(n) * (UNIT[unit] or 1)
end

--- @param text string GC.heap_info output
--- @return number? used bytes, number? max bytes
function M.parse_heap(text)
  local reserved, used = text:match('garbage%-first heap%s+total reserved (%d+)K, committed %d+K, used (%d+)K')
  if reserved then
    return bytes(used, 'K'), bytes(reserved, 'K')
  end
  local zu, zuu, zm, zmu = text:match('ZHeap%s+used (%d+)([KMG]), capacity %d+[KMG], max capacity (%d+)([KMG])')
  if zu then
    return bytes(zu, zuu), bytes(zm, zmu)
  end
  local sum, found = 0, false
  for n, unit in text:gmatch('used (%d+)([KMG])') do
    sum, found = sum + bytes(n, unit), true
  end
  return found and sum or nil, nil
end

local max_flag_cache = {}

--- MaxHeapSize from `jcmd <pid> VM.flags`, cached per pid.
--- @return number? bytes
function M.max_heap_flag(pid)
  if max_flag_cache[pid] == nil then
    local r = vim.system({ jcmd(), tostring(pid), 'VM.flags' }, { text = true, timeout = 5000 }):wait()
    local n = r.code == 0 and (r.stdout or ''):match('MaxHeapSize=(%d+)')
    max_flag_cache[pid] = n and tonumber(n) or false
  end
  return max_flag_cache[pid] or nil
end

local function finish(pid, out, cb)
  local used, max = M.parse_heap(out or '')
  if used and not max then
    max = M.max_heap_flag(pid)
  end
  cb(used, max)
end

--- Asynchronous heap reading; `cb(used, max)` runs on the main loop, with nils
--- when the process is gone or doesn't accept attach.
--- @param pid integer
--- @param cb fun(used: number?, max: number?)
function M.heap(pid, cb)
  vim.system({ jcmd(), tostring(pid), 'GC.heap_info' }, { text = true, timeout = 5000 }, function(r)
    vim.schedule(function()
      if r.code ~= 0 then
        return cb(nil, nil)
      end
      finish(pid, r.stdout, cb)
    end)
  end)
end

--- Blocking variant for `:checkhealth`.
--- @return number? used, number? max
function M.heap_sync(pid)
  local r = vim.system({ jcmd(), tostring(pid), 'GC.heap_info' }, { text = true, timeout = 5000 }):wait()
  if r.code ~= 0 then
    return nil, nil
  end
  local used, max
  finish(pid, r.stdout, function(u, m)
    used, max = u, m
  end)
  return used, max
end

--- `1.2G`, `512M`
function M.format(b)
  if not b then
    return '?'
  end
  if b >= UNIT.G then
    return string.format('%.1fG', b / UNIT.G)
  end
  return string.format('%dM', math.floor(b / UNIT.M + 0.5))
end

--- what identifies each server among this Neovim's child processes
local CLIENT_MARKERS = {
  kotlin_lsp = { 'intellij-server', 'com.intellij.ls.server' },
  ['spring-boot'] = { 'spring-boot-language-server', 'vscode-spring-boot-tools', 'language-server.jar' },
}

local pid_cache = {}

--- @return {pid: integer, command: string}[]
function M.children(parent)
  local r = vim.system({ 'ps', '-A', '-o', 'pid=,ppid=,command=' }, { text = true }):wait()
  local out = {}
  for line in (r.stdout or ''):gmatch('[^\n]+') do
    local pid, ppid, command = line:match('^%s*(%d+)%s+(%d+)%s+(.*)$')
    if pid and tonumber(ppid) == parent then
      table.insert(out, { pid = tonumber(pid), command = command })
    end
  end
  return out
end

--- pid of an LSP client's server process. Neovim 0.12 keeps the process
--- handle private, so match this Neovim's children against the server's
--- command; kotlin-lsp is told apart per project by its `--system-path`.
--- @param client vim.lsp.Client
--- @return integer?
function M.client_pid(client)
  if not client then
    return nil
  end
  local cached = pid_cache[client.id]
  if cached and require('kotlin-workflow.jobs').alive(cached) then
    return cached
  end
  local markers = CLIENT_MARKERS[client.name]
  if not markers then
    local cmd = type(client.config.cmd) == 'table' and client.config.cmd[1]
    markers = cmd and { vim.fs.basename(cmd) } or {}
  end
  local system_path
  if client.name == 'kotlin_lsp' then
    local ok, workspace = pcall(require, 'kotlin.workspace')
    system_path = ok and workspace.system_path_for(client) or nil
  end
  for _, child in ipairs(M.children(vim.fn.getpid())) do
    for _, marker in ipairs(markers) do
      if child.command:find(marker, 1, true) and (not system_path or child.command:find(system_path, 1, true)) then
        pid_cache[client.id] = child.pid
        return child.pid
      end
    end
  end
end

return M
