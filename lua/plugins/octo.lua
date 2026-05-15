-- github PR tool
return {
  'pwntester/octo.nvim',
  -- commit = 'c14f5b6ee92f0b2717efd525211bcb6cebf03fa6',
  requires = {
    'nvim-lua/plenary.nvim',
    -- 'nvim-telescope/telescope.nvim',
    -- OR 'ibhagwan/fzf-lua',
    'folke/snacks.nvim',
    'nvim-tree/nvim-web-devicons',
  },
  cmd = { 'Octo' },
  keys = {
    { '<leader>Oa', '<CMD>Octo actions<CR>', desc = 'Octo Actions' },
    { '<leader>Opl', '<CMD>Octo pr list<CR>', desc = 'Octo PR list' },
    { '<leader>Opc', '<CMD>Octo pr checkout<CR>', desc = 'Octo PR checkout' },
    { '<leader>OpC', '<CMD>Octo pr create<CR>', desc = 'Octo PR create' },
    { '<leader>Opo', '<CMD>Octo pr browse<CR>', desc = 'Octo PR open for current branch' },
    { '<leader>OpO', '<CMD>Octo pr browser<CR>', desc = 'Octo PR open for current branch in browser' },
    { '<leader>OpU', '<CMD>Octo pr url<CR>', desc = 'Octo PR URL' },
    { '<leader>Ors', '<CMD>Octo review start<CR>', desc = 'Octo Review start' },
    { '<leader>Orr', '<CMD>Octo review resume<CR>', desc = 'Octo Review resume' },
    { '<leader>Orq', '<CMD>Octo review close<CR>', desc = 'Octo Review quit/close' },
    { '<leader>Orc', '<CMD>Octo review commit<CR>', desc = 'Octo Review commit' },
    { '<leader>Ord', '<CMD>Octo review discard<CR>', desc = 'Octo Review discard' },
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
