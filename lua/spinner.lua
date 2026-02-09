local M = {}
local config = {
  -- Show notification when done.
  -- Set to false to disable.
  show_notification = false,
  -- Name of the plugin. Basically the title of the notification, when the spinner is hidden
  plugin = 'spinner.nvim',
  -- Spinner frames.
  spinner_frames = {
    '⠋',
    '⠙',
    '⠹',
    '⠸',
    '⠼',
    '⠴',
    '⠦',
    '⠧',
    '⠇',
    '⠏',
  },
  show_spinner_regexes = {
    'myBMW',
  },
  notification_id = 'lsp_spinner',
}

local spinner_index = 1
local spinner_timer = nil
local spinner_id = nil

M.should_show_spinner = function()
  for _, pattern in ipairs(config.show_spinner_regexes) do
    local cwd_contains_pattern = string.match(vim.fn.expand('%:p'), pattern) ~= nil
    if cwd_contains_pattern then
      return true
    end
  end
  return false
end

--- Show a spinner at the specified position.
function M.show(msg, title)
  M.hide()
  msg = msg ~= nil and msg or ''

  -- Set up timer and update spinner
  spinner_timer = vim.loop.new_timer()
  spinner_timer:start(
    0,
    100,
    vim.schedule_wrap(function()
      vim.notify((#msg > 0 and ' ' .. msg .. '    ' or '') .. (#msg > 0 and ' ' or ''), vim.log.levels.INFO, {
        id = config.notification_id,
        title = 'LSP',
        timeout = 100,
        opts = function(notification)
          notification.icon = config.spinner_frames[spinner_index]
          spinner_id = notification.id
        end,
      })
      spinner_index = spinner_index % #config.spinner_frames + 1
    end)
  )
end

--- Hide the spinner.
---@param msg? string
function M.hide(msg)
  if spinner_timer then
    spinner_timer:stop()
    spinner_timer:close()
    spinner_timer = nil

    if spinner_id ~= nil then
      Snacks.notifier.hide(config.notification_id)
      spinner_id = nil
    end

    if msg ~= nil then
      vim.notify(msg ~= nil and msg or '', vim.log.levels.INFO, { title = config.plugin })
    end
  end
end

return M
