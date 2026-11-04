return {
  'Jamie-505/draven.nvim',
  dir = vim.fn.expand('~/dev/private/github-forks/draven.nvim'),
  cmd = { 'Draven', 'DravenToggle', 'DravenStatus' },
  keys = {
    { '<leader>ar', '<cmd>DravenToggle<cr>', desc = '[A]I [R]eview (toggle)' },
  },
  opts = {},
}
