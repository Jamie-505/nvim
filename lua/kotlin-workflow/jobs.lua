-- Registry of the processes this Neovim started for the Kotlin workflow: Gradle
-- clients (quality checks, tests, bootRun), the Gradle daemons that served
-- them, and app/test JVMs. Read by `:checkhealth kotlin-workflow` and the
-- lualine memory element; entries whose process is gone drop out on read.
local M = {}

---@class kotlin_workflow.Job
---@field id integer
---@field pid integer
---@field kind 'gradle-client'|'gradle-daemon'|'app'|'test-jvm'
---@field label string
---@field root? string project root
---@field started integer os.time()
---@field debug_port? integer JDWP port, when started for debugging

---@type table<integer, kotlin_workflow.Job>
local entries = {}
local seq = 0

--- @param pid integer?
--- @return boolean
function M.alive(pid)
  return pid ~= nil and pid > 0 and vim.uv.kill(pid, 0) == 0
end

--- @param job table pid, kind, label, root?, debug_port?
--- @return integer id
function M.add(job)
  -- one entry per process: a daemon serves many builds
  for id, e in pairs(entries) do
    if e.pid == job.pid then
      for k, v in pairs(job) do
        e[k] = v
      end
      return id
    end
  end
  seq = seq + 1
  job.id = seq
  job.started = os.time()
  entries[seq] = job
  if job.kind == 'gradle-client' then
    -- find the daemon serving it while the client runs
    require('kotlin-workflow.daemons').watch(job.pid, job.root)
  end
  return seq
end

function M.remove(id)
  entries[id] = nil
end

--- @param kind? string only this kind
--- @return kotlin_workflow.Job[]
function M.list(kind)
  local out = {}
  for id, e in pairs(entries) do
    if not M.alive(e.pid) then
      entries[id] = nil
    elseif kind == nil or e.kind == kind then
      table.insert(out, e)
    end
  end
  table.sort(out, function(a, b)
    return a.id < b.id
  end)
  return out
end

return M
