local M = {}

M.global_functions = {}

M.add_and_run_global_function = function(name, func)
  M.global_functions[name] = func
  func()
end

M.run_global_function = function(name)
  local func = M.global_functions[name]
  if func ~= nil then
    func()
  end
end

--- Absolute path of the nearest `gradlew` at or above the cwd, else `gradle`.
--- gradle.nvim has no wrapper support and its default assumes a system install.
--- @return string
M.gradle_executable = function()
  local wrapper = vim.fs.find('gradlew', { path = vim.fn.getcwd(), upward = true, type = 'file' })[1]
  if wrapper and vim.fn.executable(wrapper) == 1 then
    return wrapper
  end
  return 'gradle'
end

local function is_terminal_window(win)
  local buf = vim.api.nvim_win_get_buf(win)
  return vim.api.nvim_get_option_value('buftype', { buf = buf }) == 'terminal'
end

local function count_terminal_buffers_in_tabpage(windows)
  local terminal_count = 0

  for _, win in ipairs(windows) do
    if is_terminal_window(win) then
      terminal_count = terminal_count + 1
    end
  end

  return terminal_count
end

M.gotoDefinitionInSplit = function()
  -- Check how many windows are open
  local wins = vim.api.nvim_tabpage_list_wins(0)

  -- NvimTree is not guaranteed to be the first window of the tabpage
  local nvim_tree_win
  for _, win in ipairs(wins) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_get_option_value('filetype', { buf = buf }) == 'NvimTree' then
      nvim_tree_win = win
      break
    end
  end
  local nvim_tree_open = nvim_tree_win ~= nil

  local current_cursor_pos = vim.api.nvim_win_get_cursor(0)

  local current_buf = vim.api.nvim_get_current_buf()
  local current_win = vim.api.nvim_get_current_win()

  local target_win

  local relevant_win_count = #wins - count_terminal_buffers_in_tabpage(wins)

  -- If there are already splits, then take the next one and set buffer to current buffer
  if nvim_tree_open then
    if relevant_win_count == 1 then
      print('Cannot open definition from NvimTree window')
    -- only nvim and one window is open
    elseif relevant_win_count == 2 then
      vim.cmd('vsplit')
      target_win = current_win
    else
      for _, win_num in pairs(wins) do
        if win_num ~= current_win and win_num ~= nvim_tree_win and not is_terminal_window(win_num) then
          target_win = win_num
          break
        end
      end
    end
  else
    if relevant_win_count >= 2 then
      for _, win_num in pairs(wins) do
        if win_num ~= current_win and not is_terminal_window(win_num) then
          target_win = win_num
          break
        end
      end
    else
      vim.cmd('vsplit')
      target_win = current_win
    end
  end

  if target_win == nil then
    return
  end

  -- Set buffer for new window
  vim.api.nvim_win_set_buf(target_win, current_buf)

  -- Copy cursor position to new window for lsp defintion
  vim.api.nvim_win_set_cursor(target_win, current_cursor_pos)

  -- Focus new window
  vim.api.nvim_set_current_win(target_win)

  -- Call lsp
  vim.lsp.buf.definition()
end

return M
