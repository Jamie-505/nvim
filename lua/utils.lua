local M = {}
local api = vim.api
local cur_buf = api.nvim_get_current_buf

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

local function buf_index(bufnr)
  for i, value in ipairs(vim.t.bufs) do
    if value == bufnr then
      return i
    end
  end
end

M.close_buffer = function(bufnr)
  bufnr = bufnr or cur_buf()

  if vim.bo[bufnr].buftype == 'terminal' then
    vim.cmd(vim.bo.buflisted and 'set nobl | enew' or 'hide')
  else
    local curBufIndex = buf_index(bufnr)
    local bufhidden = vim.bo.bufhidden

    -- force close floating wins or nonbuflisted
    if api.nvim_win_get_config(0).zindex then
      vim.cmd('bw')
      return

      -- handle listed bufs
    elseif curBufIndex and #vim.t.bufs > 1 then
      local newBufIndex = curBufIndex == #vim.t.bufs and -1 or 1
      vim.cmd('b' .. vim.t.bufs[curBufIndex + newBufIndex])

      -- handle unlisted
    elseif not vim.bo.buflisted then
      local tmpbufnr = vim.t.bufs[1]
      api.nvim_set_current_win(vim.fn.bufwinid(bufnr))
      api.nvim_set_current_buf(tmpbufnr)
      vim.cmd('bw' .. bufnr)
      return
    else
      vim.cmd('enew')
    end

    if not (bufhidden == 'delete') then
      vim.cmd('confirm bd' .. bufnr)
    end
  end

  vim.cmd('redrawtabline')
end

M.closeAllBufs = function(include_cur_buf)
  local bufs = vim.t.bufs

  if include_cur_buf ~= nil and not include_cur_buf then
    table.remove(bufs, buf_index(cur_buf()))
  end

  for _, buf in ipairs(bufs) do
    M.close_buffer(buf)
  end
end

M.statusline_separators = {
  default = { left = '', right = '' },
  round = { left = '', right = '' },
  block = { left = '█', right = '█' },
  arrow = { left = '', right = '' },
}

M.indexOf = function(table, value)
  for i, v in ipairs(table) do
    if v == value then
      return i
    end
  end
  return nil
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
  local first_buffer = vim.api.nvim_win_get_buf(wins[1])

  local nvim_tree_open = vim.api.nvim_get_option_value('filetype', { buf = first_buffer }) == 'NvimTree'

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
        if win_num ~= current_win and win_num ~= wins[1] and not is_terminal_window(win_num) then
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
