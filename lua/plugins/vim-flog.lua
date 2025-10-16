return {
  'rbong/vim-flog',
  cmd = { 'Flog', 'Flogsplit', 'Floggit' },
  keys = {
    { '<leader>Gg', '<CMD>Flog -all -format=%h%d%x20%s<CR>', desc = 'Git graph with Flog' },
  },
  dependencies = {
    {
      'tpope/vim-fugitive',
      keys = {
        { '<leader>Ga', '<CMD>Git add -p<CR>', desc = 'Git add -p' },
        { '<leader>Gc', '<CMD>Git commit<CR>', desc = 'Git commit' },
        {
          '<leader>Gf',
          function()
            vim.cmd('Git fe')
            vim.cmd('echo "Git fetch done!"')
          end,
          desc = 'Git fetch',
        },
      },
    },
  },
}
