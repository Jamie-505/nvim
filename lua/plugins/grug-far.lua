-- fancy search and replace
return {
  'MagicDuck/grug-far.nvim',
  cmd = 'GrugFar',
  keys = {
    {
      '<leader>S',
      '<CMD>GrugFar<CR>',
      desc = 'Search Open',
    },
    {
      '<leader>S',
      "<CMD>'<,'>GrugFar<CR>",
      mode = { 'v' },
      desc = 'Search Selection',
    },
  },
  opts = {
    keymaps = {
      close = { n = 'q' },
    },
  },
}
