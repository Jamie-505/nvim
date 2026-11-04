-- Which Gradle daemon serves a build this Neovim started. The Gradle client
-- talks to its daemon over a loopback TCP connection, so the daemon is the
-- process listening on the client's peer port:
--   lsof -a -p <client> -iTCP -sTCP:ESTABLISHED   → 127.0.0.1:x->127.0.0.1:<port>
--   lsof -iTCP:<port> -sTCP:LISTEN                 → daemon pid
-- This works with the configuration cache (an init script writing its pid
-- would not run on a cache hit). A daemon the build reused from a terminal
-- build counts too: it is serving this Neovim's work.
local M = {}

local function lsof(args, cb)
  vim.system(vim.list_extend({ 'lsof', '-nP' }, args), { text = true, timeout = 3000 }, function(r)
    vim.schedule(function()
      cb(r.stdout or '')
    end)
  end)
end

--- Call on the main loop; `cb(pid?, label?)` runs on the main loop too.
--- @param client_pid integer
--- @param cb fun(pid: integer?, label: string?)
function M.resolve(client_pid, cb)
  -- a terminal launch is `shell -c gradlew …`: include the shell's children
  local pids = { tostring(client_pid) }
  local children = vim.system({ 'pgrep', '-P', tostring(client_pid) }, { text = true }):wait().stdout or ''
  for child in children:gmatch('%d+') do
    table.insert(pids, child)
  end
  lsof({ '-a', '-p', table.concat(pids, ','), '-iTCP', '-sTCP:ESTABLISHED', '-Fn' }, function(out)
    local ports = {}
    for peer in out:gmatch('n127%.0%.0%.1:%d+%->127%.0%.0%.1:(%d+)') do
      table.insert(ports, peer)
    end
    local function try(i)
      if i > #ports then
        return cb(nil)
      end
      lsof({ '-iTCP:' .. ports[i], '-sTCP:LISTEN', '-Fp' }, function(listen)
        local pid = tonumber(listen:match('p(%d+)'))
        if not pid or vim.tbl_contains(pids, tostring(pid)) then
          return try(i + 1)
        end
        local ps = vim.system({ 'ps', '-o', 'command=', '-p', tostring(pid) }, { text = true }):wait()
        local version = (ps.stdout or ''):match('GradleDaemon ([%d.]+)')
        if version then
          return cb(pid, 'Gradle daemon ' .. version)
        end
        try(i + 1)
      end)
    end
    try(1)
  end)
end

--- Poll a running Gradle client (every second) until its daemon is known,
--- then register the daemon in the job registry.
--- @param client_pid integer
--- @param root? string
function M.watch(client_pid, root)
  local jobs = require('kotlin-workflow.jobs')
  local timer = assert(vim.uv.new_timer())
  local busy = false
  local function stop()
    if not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end
  timer:start(500, 1000, function()
    if busy then
      return
    end
    if not jobs.alive(client_pid) then
      return vim.schedule(stop)
    end
    busy = true
    vim.schedule(function()
      M.resolve(client_pid, function(pid, label)
        busy = false
        if pid then
          stop()
          jobs.add({ pid = pid, kind = 'gradle-daemon', label = label, root = root, client = client_pid })
        end
      end)
    end)
  end)
end

return M
