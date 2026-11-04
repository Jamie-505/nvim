-- Attach nvim-dap to a JVM listening for JDWP, through a fresh kotlin-lsp DAP
-- bridge (`workspace/executeCommand start_debug_server`) per session.
local M = {}

M.ADAPTER = 'kotlin_workflow_bridge'

--- a free loopback TCP port
function M.free_port()
  local socket = assert(vim.uv.new_tcp())
  assert(socket:bind('127.0.0.1', 0))
  local port = socket:getsockname().port
  socket:close()
  return port
end

local function client()
  return vim.lsp.get_clients({ name = 'kotlin_lsp', bufnr = 0 })[1] or vim.lsp.get_clients({ name = 'kotlin_lsp' })[1]
end

local function ensure_adapter(dap)
  if dap.adapters[M.ADAPTER] then
    return
  end
  -- a function adapter: nvim-dap calls it per session, so every session gets
  -- its own bridge
  dap.adapters[M.ADAPTER] = function(cb, config)
    local c = client()
    if not c then
      vim.notify('kotlin-lsp is not running; open a Kotlin file of the project first', vim.log.levels.ERROR)
      return
    end
    local root = c.root_dir or vim.fn.getcwd()
    c:request('workspace/executeCommand', {
      command = 'start_debug_server',
      arguments = { vim.uri_from_fname(root) },
    }, function(err, result)
      vim.schedule(function()
        local port = tonumber(result)
        if err or not port then
          vim.notify('kotlin-lsp start_debug_server failed: ' .. vim.inspect(err or result), vim.log.levels.ERROR)
          return
        end
        cb({ type = 'server', host = '127.0.0.1', port = port, id = 'intellij_jvm' })
      end)
    end)
  end
end

--- @param jdwp_port integer
--- @param name string session name
--- @param extra? table merged into the attach configuration
function M.attach(jdwp_port, name, extra)
  local dap = require('dap')
  ensure_adapter(dap)
  dap.run(vim.tbl_extend('force', {
    type = M.ADAPTER,
    request = 'attach',
    name = name,
    hostName = '127.0.0.1',
    port = jdwp_port,
  }, extra or {}))
end

--- the port in a JDWP agent's "Listening for transport dt_socket at address: N"
function M.listening_port(text)
  local port = text:match('Listening for transport dt_socket at address: [^%d]-(%d+)')
  return port and tonumber(port)
end

return M
