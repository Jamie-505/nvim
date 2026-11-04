-- Lualine memory element (spec §3.6): heap used/max of the JVMs serving this
-- Neovim — kotlin-lsp, the Spring Boot language server, Gradle daemons that
-- ran this Neovim's builds, and the app started from a run config.
--   kls 1.2/8.0G  spring 210M/1.0G  gradle 640M/2.0G  app 180M/4.0G
-- Shown in kotlin/yaml/properties buffers with an attached server. Readings
-- come from `jcmd <pid> GC.heap_info` every 5 s, asynchronously, and only while
-- the element is being drawn and Neovim has focus. A process above 75% of its
-- max turns the element to the warning colour.
local M = {}

local jvm = require('kotlin-workflow.jvm')
local jobs = require('kotlin-workflow.jobs')

M.INTERVAL_MS = 5000
M.WARN = 0.75
local FILETYPES = { kotlin = true, yaml = true, jproperties = true }

--- pid → { used, max, at }
local readings = {}
local pending = {}
local timer
local last_drawn = 0
local focused = true

--- the processes to read: { key, label, pid }
function M.targets()
  local out = {}
  for _, c in ipairs(vim.lsp.get_clients({ name = 'kotlin_lsp' })) do
    local pid = jvm.client_pid(c)
    if pid then
      table.insert(out, { label = 'kls', pid = pid })
    end
  end
  for _, c in ipairs(vim.lsp.get_clients({ name = 'spring-boot' })) do
    local pid = jvm.client_pid(c)
    if pid then
      table.insert(out, { label = 'spring', pid = pid })
    end
  end
  for _, j in ipairs(jobs.list('gradle-daemon')) do
    table.insert(out, { label = 'gradle', pid = j.pid })
  end
  for _, j in ipairs(jobs.list('app')) do
    table.insert(out, { label = 'app', pid = j.pid })
  end
  return out
end

--- targets as of the last tick (statusline redraws never run `ps`)
local current = {}

local function refresh()
  if not focused or vim.uv.now() - last_drawn > 2 * M.INTERVAL_MS then
    return -- not visible: no jcmd
  end
  local live = {}
  current = M.targets()
  for _, t in ipairs(current) do
    live[t.pid] = true
    if not pending[t.pid] then
      pending[t.pid] = true
      jvm.heap(t.pid, function(used, max)
        pending[t.pid] = nil
        readings[t.pid] = used and { used = used, max = max, at = os.time() } or nil
      end)
    end
  end
  for pid in pairs(readings) do
    if not live[pid] then
      readings[pid] = nil
    end
  end
end

local function ensure_timer()
  if timer then
    return
  end
  timer = assert(vim.uv.new_timer())
  timer:start(0, M.INTERVAL_MS, vim.schedule_wrap(refresh))
  vim.api.nvim_create_autocmd({ 'FocusGained', 'FocusLost' }, {
    group = vim.api.nvim_create_augroup('jvm-mem', { clear = true }),
    callback = function(ev)
      focused = ev.event == 'FocusGained'
      if focused then
        refresh()
      end
    end,
  })
end

local function short(b, max)
  -- `1.2/8.0G`, `210M/1.0G`
  local used = jvm.format(b)
  local cap = jvm.format(max)
  if used:sub(-1) == cap:sub(-1) and used:sub(-1) == 'G' then
    used = used:sub(1, -2)
  end
  return used .. '/' .. cap
end

--- per process: { label, text, ratio }
function M.items()
  local out = {}
  for _, t in ipairs(current) do
    local r = readings[t.pid]
    if r then
      table.insert(out, { label = t.label, text = short(r.used, r.max), ratio = r.max and r.used / r.max or 0 })
    end
  end
  return out
end

function M.cond()
  if not FILETYPES[vim.bo.filetype] then
    return false
  end
  return #vim.lsp.get_clients({ bufnr = 0 }) > 0
end

--- lualine component function
function M.status()
  if not M.cond() then
    return ''
  end
  last_drawn = vim.uv.now()
  ensure_timer()
  local parts = {}
  for _, it in ipairs(M.items()) do
    table.insert(parts, it.label .. ' ' .. it.text .. (it.ratio > M.WARN and '!' or ''))
  end
  return #parts > 0 and ('󰍛 ' .. table.concat(parts, '  ')) or ''
end

--- true when any process is above the warning ratio
function M.warning()
  for _, it in ipairs(M.items()) do
    if it.ratio > M.WARN then
      return true
    end
  end
  return false
end

return M
