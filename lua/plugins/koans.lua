-- `:Koan` helpers for jetbrains academy courses (kotlin koans).
--
-- Enabled only inside a course checkout, but loaded eagerly there: the lualine
-- component reads `koans.progress`, which needs the plugin on the runtimepath.
-- All it costs at startup is a command definition and a few `hi default link`s.

return {
  'koans.nvim',
  dir = vim.fn.expand('~/dev/playground/koans.nvim'),
  lazy = false,
  cond = function()
    return vim.fs.find('course-info.yaml', {
      path = vim.uv.cwd(),
      upward = true,
      type = 'file',
    })[1] ~= nil
  end,
  opts = {},
}
