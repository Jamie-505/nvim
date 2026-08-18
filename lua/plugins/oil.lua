-- manipulate files with vim motions
return {
  'stevearc/oil.nvim',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  lazy = false,
  cmd = 'Oil',
  keys = {
    {
      '-',
      function()
        local oil = require('oil')
        local oil_util = require('oil.util')
        oil.open_float()
        oil_util.run_after_load(0, function()
          oil.open_preview()
        end)
      end,
      desc = 'Oil Open parent directory',
    },
  },
  opts = {
    win_options = {
      wrap = true,
      signcolumn = 'yes:2',
    },
    delete_to_trash = true,
    watch_for_changes = true,
    view_options = {
      show_hidden = true,
      is_hidden_file = function(name)
        return vim.startswith(name, '.')
      end,
    },
    float = {
      border = 'rounded',
      win_options = {
        winblend = 0,
        signcolumn = 'yes:2',
      },
      preview_split = 'right',
      override = function(conf)
        local new_conf = vim.tbl_deep_extend(
          'force',
          conf,
          { relative = 'editor', anchor = 'SW', row = 1000, col = 2, width = 200, height = 50 }
        )
        return new_conf
      end,
    },
    confirmation = {
      border = 'rounded',
    },
    preview_win = {
      update_on_cursor_moved = true,
      border = 'rounded',
      win_options = {
        winblend = 0,
      },
    },
    progress = {
      border = 'rounded',
      minimized_border = 'none',
      win_options = {
        winblend = 0,
      },
    },
    ssh = {
      border = 'rounded',
    },
    keymaps_help = {
      border = 'rounded',
    },
  },
}
