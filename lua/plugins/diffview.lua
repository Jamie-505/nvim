return {
  'sindrets/diffview.nvim',
  cmd = { 'DiffviewOpen', 'DiffviewFocusFiles', 'DiffviewToggleFiles', 'DiffviewFileHistory' },
  config = function()
    vim.opt.fillchars:append({ diff = '╱' })
    require('diffview').setup({
      view = {
        merge_tool = {
          layout = 'diff4_mixed', -- OURS | BASE | THEIRS on top, LOCAL below
        },
      },
    })
  end,
}
