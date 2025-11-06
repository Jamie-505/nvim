return {
  'nvim-tree/nvim-tree.lua',
  dependencies = {
    'nvim-tree/nvim-web-devicons',
  },
  cmd = { 'NvimTreeToggle', 'NvimTreeFocus' },
  keys = {
    { '<C-n>', '<CMD>NvimTreeToggle<CR>', desc = 'NvimTree Toggle window' },
  },
  opts = {
    filters = {
      dotfiles = false,
    },
    disable_netrw = false,
    hijack_netrw = false,
    hijack_cursor = true,
    hijack_unnamed_buffer_when_opening = false,
    sync_root_with_cwd = true,
    update_focused_file = {
      enable = true,
      update_root = false,
    },
    diagnostics = {
      enable = true,
      show_on_dirs = true,
      show_on_open_dirs = true,
    },
    view = {
      adaptive_size = true,
      side = 'left',
      width = 30,
      preserve_window_proportions = true,
    },
    git = {
      enable = true,
      ignore = false,
    },
    filesystem_watchers = {
      enable = true,
    },
    actions = {
      open_file = {
        resize_window = true,
      },
    },
    renderer = {
      root_folder_label = false,
      highlight_git = true,
      highlight_opened_files = 'name',
      highlight_diagnostics = true,

      indent_markers = {
        enable = true,
      },

      icons = {
        show = {
          file = true,
          folder = true,
          folder_arrow = true,
          git = true,
        },

        glyphs = {
          default = '󰈚',
          symlink = '',
          folder = {
            default = '',
            empty = '',
            empty_open = '',
            open = '',
            symlink = '',
            symlink_open = '',
            arrow_open = '',
            arrow_closed = '',
          },
          git = {
            unstaged = '✗',
            staged = '✓',
            unmerged = '',
            renamed = '➜',
            untracked = '★',
            deleted = '',
            ignored = '◌',
          },
        },
      },
    },
  },
  config = function(_, opts)
    require('nvim-tree').setup(opts)
    require('colors').add_and_set_color_module('nvim-tree', function()
      vim.api.nvim_set_hl(0, 'NvimTreeCursorLine', {
        bg = '#474656',
      })
      if vim.g.transparent_enabled then
        vim.api.nvim_set_hl(0, 'NvimTreeWinSeparator', {
          bg = 'NONE',
        })
        vim.api.nvim_set_hl(0, 'NvimTreeNormal', {
          bg = 'NONE',
        })
      end
    end)
  end,
}
