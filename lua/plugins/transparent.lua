return {
  'xiyaowong/transparent.nvim',
  lazy = false,
  opts = {
    extra_groups = {
      'NormalFloat', -- plugins which have float panel such as Lazy, Mason, LspInfo
    },
    exclude_groups = {
      'IndentBlanklineChar',
      'IndentBlanklineContextChar',
      'IndentBlanklineContextStart',
      'IblIndent',
      'IblChar',
      'IblScope',
      'SnacksDashboardHeader',
      'NoiceCmdlinePrompt',
      'NoiceCmdlinePopupBorder',
      'DevIconDart',
      'TelescopeBorder',
      'FloatBorder',
      '@ibl.scope.char.1',
      '@ibl.indent.char.1',
      '@ibl.scope.underline.1',
      '@ibl.whitespace.char.1',
    },
  },
  config = function(_, opts)
    local transparent = require('transparent')
    transparent.setup(opts)
    local toggle_transparency = function()
      transparent.toggle()
      local colors = require('colors')
      colors.set_all_colors()
      require('utils').run_global_function('ibl_setup')
      if vim.g.transparent_enabled then
        transparent.clear_prefix('TabLineFill')
      end
    end
    vim.api.nvim_create_user_command('ToggleTransparency', toggle_transparency, {})
  end,
  keys = {
    { '<leader>tt', '<CMD>ToggleTransparency<CR>', desc = 'toggle transparency' },
  },
}
