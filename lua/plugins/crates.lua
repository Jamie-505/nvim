-- rust dependency manager
return {
  'saecki/crates.nvim',
  event = { 'BufRead Cargo.toml' },
  keys = {
    {
      '<leader>cu',
      function()
        require('crates').upgrade_all_crates()
      end,
      desc = 'Update Crates',
    },
  },
  opts = function()
    return {
      lsp = {
        enabled = true,
        actions = true,
        completion = true,
        hover = true,
      },
    }
  end,
}
