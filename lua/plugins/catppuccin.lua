return {
  'catppuccin/nvim',
  name = 'catppuccin',
  lazy = false,
  priority = 1000,
  config = function()
    require('catppuccin').setup({
      flavour = 'mocha',
      transparent_background = vim.g.transparent_enabled,
      float = {
        transparent = true,
      },
      custom_highlights = function(colors)
        return {
          Pmenu = { bg = 'NONE' },
          CursorLineNr = { fg = colors.yellow },
          DevIconDart = { fg = '#5fc9f8' },
          gitCommitComment = { fg = '#8886a6' },
          LineNr = { fg = '#8886a6' },
          LspReferenceRead = { bg = '#666666' },
          LspReferenceWrite = { bg = '#666666' },
          LspReferenceText = { bg = '#666666' },
          NoiceCmdlinePopupBorder = { fg = colors.yellow },
          NoiceCmdlinePrompt = { fg = colors.yellow },
          NoiceFormatProgressDone = { fg = '#282737', bg = colors.yellow },
          NoiceVirtualText = { fg = colors.yellow, bg = '#45475a' },
          Record = {
            fg = '#222222',
            bg = '#f38ba8',
            ctermfg = 0,
            ctermbg = 11,
          },
          RecordSepL = {
            fg = '#313244',
            bg = '#f38ba8',
            ctermfg = 0,
            ctermbg = 11,
          },
          RecordSepR = {
            fg = '#f38ba8',
            bg = '#313244',
            ctermfg = 0,
            ctermbg = 11,
          },
          SnacksDashboardHeader = { fg = colors.yellow },
          TabLineFill = { bg = 'NONE' },
        }
      end,
      auto_integrations = true,
      integrations = {
        blink_cmp = {
          style = 'bordered',
        },
        dap = true,
        diffview = true,
        dropbar = {
          enabled = true,
          color_mode = true,
        },
        fidget = true,
        flash = true,
        gitsigns = true,
        grug_far = true,
        indent_blankline = {
          enabled = true,
          scope_color = 'lavender', -- catppuccin color (eg. `lavender`) Default: text
          colored_indent_levels = true,
        },
        lsp_trouble = true,
        mason = true,
        markview = true,
        native_lsp = {
          enabled = true,
          virtual_text = {
            errors = { 'italic' },
            hints = { 'italic' },
            warnings = { 'italic' },
            information = { 'italic' },
            ok = { 'italic' },
          },
          underlines = {
            errors = { 'underline' },
            hints = { 'underline' },
            warnings = { 'underline' },
            information = { 'underline' },
            ok = { 'underline' },
          },
          inlay_hints = {
            background = false,
          },
        },
        neotest = true,
        noice = true,
        nvim_surround = true,
        nvimtree = true,
        octo = true,
        rainbow_delimiters = true,
        snacks = {
          enabled = true,
          indent_scope_color = 'lavender', -- catppuccin color (eg. `lavender`) Default: text
        },
        treesitter = true,
        treesitter_context = true,
        telescope = {
          enabled = true,
          transparent_background = true,
        },
        which_key = true,
      },
    })

    vim.cmd.colorscheme('catppuccin')
  end,
}
