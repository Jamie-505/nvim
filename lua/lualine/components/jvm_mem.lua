-- lualine component `jvm_mem` (data from lua/jvm-mem): each process in its own
-- colour, so a Gradle daemon at 90% of its 512M turns only `gradle` red.
--   { 'jvm_mem', ok = '#7f849c', warn = '#f38ba8' }
local Component = require('lualine.component'):extend()

function Component:init(options)
  Component.super.init(self, options)
  self.hl_ok = self:create_hl({ fg = options.ok }, 'ok')
  self.hl_warn = self:create_hl({ fg = options.warn }, 'warn')
end

function Component:update_status()
  local mem = require('jvm-mem')
  if not mem.cond() then
    return ''
  end
  mem.status() -- marks the element as drawn (keeps the 5 s refresh running)
  local parts = {}
  for _, it in ipairs(mem.items()) do
    local warn = it.ratio > mem.WARN
    table.insert(parts, self:format_hl(warn and self.hl_warn or self.hl_ok) .. it.label .. ' ' .. it.text .. (warn and '!' or ''))
  end
  if #parts == 0 then
    return ''
  end
  return self:format_hl(self.hl_ok) .. '󰍛 ' .. table.concat(parts, '  ') .. self:get_default_hl()
end

return Component
