return {
  'numtostr/Comment.nvim',
  keys = {
    {
      '<leader>/',
      function()
        require('Comment.api').toggle.linewise.current()
      end,
      desc = 'Toggle Comment',
    },
    {
      '<leader>/',
      "<esc><cmd>lua require('Comment.api').toggle.linewise(vim.fn.visualmode())<cr>",
      desc = 'Toggle Comment',
      mode = 'v',
    },
  },
  opts = {},
}
