return {
  'sindrets/diffview.nvim',
  cmd = { 'DiffviewOpen', 'DiffviewFocusFiles', 'DiffviewToggleFiles', 'DiffviewFileHistory' },
  config = function()
    vim.opt.fillchars:append({ diff = '╱' })
  end,
}
