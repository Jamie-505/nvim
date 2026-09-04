return {
  'L3MON4D3/LuaSnip',
  dependencies = 'rafamadriz/friendly-snippets',
  opts = { history = true, updateevents = 'TextChanged,TextChangedI' },
  config = function(_, opts)
    require('luasnip').config.set_config(opts)
    -- vscode format
    require('luasnip.loaders.from_vscode').lazy_load({ exclude = vim.g.vscode_snippets_exclude or {} })
    if vim.g.vscode_snippets_path then
      require('luasnip.loaders.from_vscode').lazy_load({ paths = vim.g.vscode_snippets_path })
    end

    -- snipmate format
    require('luasnip.loaders.from_snipmate').load()
    if vim.g.snipmate_snippets_path then
      require('luasnip.loaders.from_snipmate').lazy_load({ paths = vim.g.snipmate_snippets_path })
    end

    -- lua format
    require('luasnip.loaders.from_lua').load()
    if vim.g.lua_snippets_path then
      require('luasnip.loaders.from_lua').lazy_load({ paths = vim.g.lua_snippets_path })
    end

    vim.api.nvim_create_autocmd('InsertLeave', {
      callback = function()
        if
          require('luasnip').session.current_nodes[vim.api.nvim_get_current_buf()]
          and not require('luasnip').session.jump_active
        then
          require('luasnip').unlink_current()
        end
      end,
    })
  end,
}
