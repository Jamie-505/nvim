-- better rust lsp setup
return {
  'mrcjkb/rustaceanvim',
  -- version = "^5",
  -- lazy = false,
  event = 'BufEnter *Cargo.toml',
  ft = 'rust',
  config = function()
    local lspconfig = require('lsp-opts')
    vim.g.rustaceanvim = {
      server = {
        autostart = true,
        capabilities = lspconfig.capabilities,
        on_init = lspconfig.on_init,
        default_settings = {
          ['rust-analyzer'] = {
            cargo = {
              features = 'all',
              buildScripts = {
                enable = true,
              },
            },
            procMacro = {
              enable = true,
            },
          },
        },
      },
    }
  end,
}
