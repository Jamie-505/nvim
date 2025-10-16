-- scope highlighting
return {
  'arnamak/stay-centered.nvim',
  keys = function()
    local enabled = false
    return {
      {
        '<leader>tc',
        function()
          enabled = not enabled
          require('stay-centered').toggle()
          Snacks.notify(enabled and 'Enabled' or 'Disabled', { title = 'Stay Centered' })
        end,
        mode = { 'n', 'v' },
        desc = 'Toggle stay-centered.nvim',
      },
    }
  end,
  opts = {
    -- The filetype is determined by the vim filetype, not the file extension. In order to get the filetype, open a file and run the command:
    -- :lua print(vim.bo.filetype)
    skip_filetypes = {},
    -- Set to false to disable by default
    enabled = false,
    -- allows scrolling to move the cursor without centering, default recommended
    allow_scroll_move = true,
    -- temporarily disables plugin on left-mouse down, allows natural mouse selection
    -- try disabling if plugin causes lag, function uses vim.on_key
    disable_on_mouse = true,
  },
}
