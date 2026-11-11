return {
  'Jamie-505/draven.nvim',
  dir = vim.fn.expand('~/dev/private/github-forks/draven.nvim'),
  dependencies = { 'nvim-telescope/telescope.nvim' },
  cmd = { 'Draven', 'DravenToggle', 'DravenStatus' },
  keys = {
    { '<leader>ar', '<cmd>DravenToggle<cr>', desc = '[A]I [R]eview (toggle)' },
    { '<leader>rf', '<cmd>Telescope draven findings<cr>', desc = '[R]eview [F]indings picker' },
  },
  opts = { export = { submit = true } },
  config = function(_, opts)
    require('draven').setup(opts)
    require('telescope').load_extension('draven')
  end,
}
