local api = vim.api

local M = {}

local state = {
  pattern = nil,
  invert = false,
  bufnr = nil,
  attached_to = nil,
  scheduled = false,
}

local function repl_bufnr()
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if
      api.nvim_buf_is_valid(buf)
      and vim.bo[buf].buftype == 'prompt'
      and api.nvim_buf_get_name(buf):match('%[dap%-repl%-%d+%]$')
    then
      return buf
    end
  end
end

local function matcher()
  if not state.pattern or state.pattern == '' then
    return nil
  end
  local ok, re = pcall(vim.regex, state.pattern)
  if not ok then
    vim.notify('Invalid pattern: ' .. state.pattern, vim.log.levels.ERROR)
    return nil
  end
  return re
end

local function copy_extmarks(src, dst, src_row, dst_row)
  local marks = api.nvim_buf_get_extmarks(src, -1, { src_row, 0 }, { src_row, -1 }, { details = true })
  for _, mark in ipairs(marks) do
    local col, details = mark[3], mark[4]
    if details.ns_id then
      local end_row = details.end_row == src_row and dst_row or nil
      pcall(api.nvim_buf_set_extmark, dst, details.ns_id, dst_row, col, {
        end_row = end_row,
        end_col = end_row and details.end_col or nil,
        hl_group = details.hl_group,
        priority = details.priority,
      })
    end
  end
end

function M.render()
  local dst = state.bufnr
  if not dst or not api.nvim_buf_is_valid(dst) then
    return
  end

  local src = repl_bufnr()
  local lines, kept = {}, {}

  if src then
    local re = matcher()
    for row, line in ipairs(api.nvim_buf_get_lines(src, 0, -1, false)) do
      local hit = re == nil or re:match_str(line) ~= nil
      if re and state.invert then
        hit = not hit
      end
      if hit then
        lines[#lines + 1] = line
        kept[#kept + 1] = row - 1
      end
    end
  else
    lines = { '-- no dap-repl buffer --' }
  end

  vim.bo[dst].modifiable = true
  api.nvim_buf_set_lines(dst, 0, -1, false, lines)
  vim.bo[dst].modifiable = false

  api.nvim_buf_clear_namespace(dst, -1, 0, -1)
  if src then
    for i, src_row in ipairs(kept) do
      copy_extmarks(src, dst, src_row, i - 1)
    end
  end

  for _, win in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_buf(win) == dst then
      api.nvim_win_set_cursor(win, { math.max(#lines, 1), 0 })
    end
  end
end

local function schedule_render()
  if state.scheduled then
    return
  end
  state.scheduled = true
  vim.defer_fn(function()
    state.scheduled = false
    M.render()
  end, 50)
end

local function attach()
  local src = repl_bufnr()
  if not src or state.attached_to == src then
    return
  end
  state.attached_to = src
  api.nvim_buf_attach(src, false, {
    on_lines = function()
      if not state.bufnr or not api.nvim_buf_is_valid(state.bufnr) then
        state.attached_to = nil
        return true
      end
      schedule_render()
    end,
    on_detach = function()
      state.attached_to = nil
    end,
  })
end

function M.set_pattern(pattern)
  state.pattern = pattern
  attach()
  M.render()
end

function M.prompt()
  vim.ui.input({ prompt = 'REPL filter: ', default = state.pattern or '' }, function(input)
    if input == nil then
      return
    end
    M.set_pattern(input)
  end)
end

function M.clear()
  M.set_pattern(nil)
end

function M.toggle_invert()
  state.invert = not state.invert
  M.render()
end

function M.label()
  if not state.pattern or state.pattern == '' then
    return 'Filter'
  end
  return (state.invert and 'Filter !' or 'Filter ') .. state.pattern
end

function M.buffer()
  if state.bufnr and api.nvim_buf_is_valid(state.bufnr) then
    return state.bufnr
  end

  local buf = api.nvim_create_buf(false, true)
  state.bufnr = buf
  api.nvim_buf_set_name(buf, '[dap-repl-filter]')
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = 'dap-repl'

  vim.keymap.set('n', 's', M.prompt, { buffer = buf, desc = 'Set REPL filter' })
  vim.keymap.set('n', 'x', M.clear, { buffer = buf, desc = 'Clear REPL filter' })
  vim.keymap.set('n', 'v', M.toggle_invert, { buffer = buf, desc = 'Invert REPL filter' })

  return buf
end

function M.show()
  attach()
  if not state.pattern or state.pattern == '' then
    M.prompt()
  else
    M.render()
  end
end

function M.open()
  local dapview = require('dap-view')
  dapview.open()
  local had_pattern = state.pattern and state.pattern ~= ''
  dapview.show_view('filter')
  if had_pattern then
    M.prompt()
  end
end

return M
