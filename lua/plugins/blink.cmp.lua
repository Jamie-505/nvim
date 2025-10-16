return {
  {
    'saghen/blink.cmp',
    dependencies = { 'L3MON4D3/LuaSnip' },
    lazy = false,
    version = '1.*',
    ---@module 'blink.cmp'
    ---@type blink.cmp.Config
    opts = {
      keymap = {
        preset = 'none',
        ['<M-space>'] = { 'show', 'show_documentation', 'hide_documentation', 'fallback' },
        ['<Tab>'] = { 'select_next', 'fallback' },
        ['<S-Tab>'] = { 'select_prev', 'fallback' },
        ['<CR>'] = { 'select_and_accept', 'fallback' },
        ['<C-e>'] = { 'hide', 'fallback' },
        ['<C-b>'] = { 'scroll_documentation_up', 'fallback' },
        ['<C-f>'] = { 'scroll_documentation_down', 'fallback' },
        ['<Esc>'] = {
          function(cmp)
            if cmp.is_visible() then
              cmp.cancel({
                callback = function()
                  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'i', true)
                end,
              })
            else
              vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'n', true)
            end
          end,
        },
      },
      appearance = {
        nerd_font_variant = 'mono',
      },
      completion = {
        accept = { auto_brackets = { enabled = false } },
        documentation = { auto_show = true },
        list = { selection = { preselect = false, auto_insert = true } },
      },
      fuzzy = { implementation = 'prefer_rust_with_warning' },
      snippets = {
        preset = 'luasnip',
      },
      sources = {
        default = { 'lsp', 'path', 'snippets', 'buffer' },
      },
    },
    opts_extend = { 'sources.default' },
  },
}
