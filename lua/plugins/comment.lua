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
      "<esc><CMD>lua require('Comment.api').toggle.linewise(vim.fn.visualmode())<CR>",
      desc = 'Toggle Comment',
      mode = 'v',
    },
  },
  opts = {},
}
