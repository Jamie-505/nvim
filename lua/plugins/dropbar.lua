-- breadcrumbs
return {
  'Bekaboo/dropbar.nvim',
  event = { 'BufReadPost', 'BufNewFile' },
  keys = {
    {
      '<leader>;',
      function()
        require('dropbar.api').pick()
      end,
      desc = 'Pick Symbol from top bar',
    },
    {
      '<leader>td',
      function()
        if vim.o.winbar == '' then
          vim.o.winbar = '%{%v:lua.dropbar()%}'
        else
          vim.o.winbar = ''
        end
      end,
      desc = 'Toggle Dropbar (breadcrumbs)',
    },
  },
  opts = {},
}
