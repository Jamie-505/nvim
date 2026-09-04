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
  ---@type CommentConfig
  -- gc/gcc are owned by undo-glow.nvim; Comment.nvim's defaults would override
  -- them once it loads via <leader>/
  opts = { mappings = false },
}
