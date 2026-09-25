-- github PR tool

local function jump_global_review_thread(direction)
  local reviews = require('octo.reviews')
  local utils = require('octo.utils')
  local review = reviews.get_current_review()

  if not review or not review.layout then
    return
  end

  local _, current_path = utils.get_split_and_path(vim.api.nvim_get_current_buf())
  if not current_path then
    return
  end

  local file_order = {}
  for index, file in ipairs(review.layout.files) do
    file_order[file.path] = index
  end

  local current_file_index = file_order[current_path]
  if not current_file_index then
    return
  end

  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local commit_review = review:get_level() == 'COMMIT'
  local candidates = {}

  local function thread_line(thread)
    local lines = commit_review and { thread.originalStartLine, thread.originalLine }
      or { thread.startLine, thread.line, thread.originalStartLine, thread.originalLine }

    for _, line in ipairs(lines) do
      if type(line) == 'number' then
        return line
      end
    end
  end

  for _, thread in pairs(review.threads) do
    local file_index = file_order[thread.path]
    local line = thread_line(thread)

    if file_index and line and not thread.isOutdated then
      candidates[#candidates + 1] = {
        thread = thread,
        file_index = file_index,
        line = line,
      }
    end
  end

  table.sort(candidates, function(a, b)
    if a.file_index ~= b.file_index then
      return a.file_index < b.file_index
    end
    return a.line < b.line
  end)

  local target

  if direction > 0 then
    for _, candidate in ipairs(candidates) do
      if
        candidate.file_index > current_file_index
        or (candidate.file_index == current_file_index and candidate.line > current_line)
      then
        target = candidate.thread
        break
      end
    end

    target = target or (candidates[1] and candidates[1].thread)
  else
    for index = #candidates, 1, -1 do
      local candidate = candidates[index]
      if
        candidate.file_index < current_file_index
        or (candidate.file_index == current_file_index and candidate.line < current_line)
      then
        target = candidate.thread
        break
      end
    end

    target = target or (candidates[#candidates] and candidates[#candidates].thread)
  end

  if target then
    reviews.jump_to_pending_review_thread(target)
    require('octo.reviews.thread-panel').show_review_threads(false)
  end
end

return {
  'pwntester/octo.nvim',
  -- commit = 'c14f5b6ee92f0b2717efd525211bcb6cebf03fa6',
  dependencies = {
    'nvim-lua/plenary.nvim',
    {
      'Jamie-505/telescope-octo-review.nvim',
      dir = vim.fn.expand('~/dev/private/telescope-octo-review.nvim'),
      dependencies = { 'nvim-telescope/telescope.nvim' },
      config = function()
        require('telescope').load_extension('octo_review')
      end,
    },
    -- OR 'ibhagwan/fzf-lua',
    'folke/snacks.nvim',
    'nvim-tree/nvim-web-devicons',
  },
  cmd = { 'Octo' },
  keys = {
    {
      ']T',
      function()
        jump_global_review_thread(1)
      end,
      desc = 'Octo: next review thread globally',
    },
    {
      '[T',
      function()
        jump_global_review_thread(-1)
      end,
      desc = 'Octo: previous review thread globally',
    },
    { '<leader>Oa', '<CMD>Octo actions<CR>', desc = 'Octo Actions' },
    { '<leader>Opl', '<CMD>Octo pr list<CR>', desc = 'Octo PR list' },
    { '<leader>Opc', '<CMD>Octo pr checkout<CR>', desc = 'Octo PR checkout' },
    { '<leader>OpC', '<CMD>Octo pr create<CR>', desc = 'Octo PR create' },
    { '<leader>Opo', '<CMD>Octo pr browse<CR>', desc = 'Octo PR open for current branch' },
    { '<leader>OpO', '<CMD>Octo pr browser<CR>', desc = 'Octo PR open for current branch in browser' },
    { '<leader>OpU', '<CMD>Octo pr url<CR>', desc = 'Octo PR URL' },
    { '<leader>Ors', '<CMD>Octo review start<CR>', desc = 'Octo Review start' },
    { '<leader>Orr', '<CMD>Octo review resume<CR>', desc = 'Octo Review resume' },
    {
      '<leader>Ofc',
      function()
        require('telescope').extensions.octo_review.comments()
      end,
      desc = 'Octo Review find comment',
    },
    {
      '<leader>Oft',
      function()
        require('telescope').extensions.octo_review.threads()
      end,
      desc = 'Octo Review find thread',
    },
    { '<leader>Orq', '<CMD>Octo review close<CR>', desc = 'Octo Review quit/close' },
    { '<leader>Orc', '<CMD>Octo review commit<CR>', desc = 'Octo Review commit' },
    { '<leader>Ord', '<CMD>Octo review discard<CR>', desc = 'Octo Review discard' },
  },
  ---@type OctoConfig
  opts = {
    -- maps ~/.ssh/config Host aliases to the real API host
    ssh_aliases = {
      ['github-work'] = 'github.com',
      ['github-personal'] = 'github.com',
    },
    mappings_disable_default = false,
  },
}
