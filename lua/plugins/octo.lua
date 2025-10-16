-- github PR tool
return {
  'pwntester/octo.nvim',
  requires = {
    'nvim-lua/plenary.nvim',
    'nvim-telescope/telescope.nvim',
    -- OR 'ibhagwan/fzf-lua',
    -- OR 'folke/snacks.nvim',
    'nvim-tree/nvim-web-devicons',
  },
  cmd = { 'Octo' },
  keys = {
    { '<leader>Oa', '<cmd>Octo actions<CR>', desc = 'Octo Actions' },
    { '<leader>Opl', '<cmd>Octo pr list<CR>', desc = 'Octo PR list' },
    { '<leader>Opc', '<cmd>Octo pr checkout<CR>', desc = 'Octo PR checkout' },
    { '<leader>Opo', '<cmd>Octo pr browse<CR>', desc = 'Octo PR open for current branch' },
    { '<leader>OpO', '<cmd>Octo pr browser<CR>', desc = 'Octo PR open for current branch in browser' },
    { '<leader>Ors', '<cmd>Octo review start<CR>', desc = 'Octo Review start' },
    { '<leader>Orr', '<cmd>Octo review resume<CR>', desc = 'Octo Review resume' },
    { '<leader>Orq', '<cmd>Octo review close<CR>', desc = 'Octo Review quit/close' },
    { '<leader>Orc', '<cmd>Octo review commit<CR>', desc = 'Octo Review commit' },
    { '<leader>Ord', '<cmd>Octo review discard<CR>', desc = 'Octo Review discard' },
  },
  opts = {
    mappings_disable_default = false,
    mappings = {
      review_diff = {
        next_thread = { lhs = ']T', desc = 'Octo Review move to next thread' },
        prev_thread = { lhs = '[T', desc = 'Octo Review move to previous thread' },
      },
    },
  },
}
