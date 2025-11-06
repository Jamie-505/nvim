return {
  'folke/noice.nvim',
  dependencies = {
    'nvim-telescope/telescope.nvim',
    'MunifTanjim/nui.nvim',
    {
      'rcarriga/nvim-notify',
      opts = {
        fps = 60,
        background_colour = '#FDFD9A',
      },
    },
  },
  event = 'VeryLazy',
  keys = {
    { '<leader>fn', '<CMD>Noice telescope<CR>', desc = 'Notifications Show history' },
    -- { "<leader>dm", "<CMD>Noice dismiss<CR>", desc = "Noice Dismiss messages" },
  },
  opts = {
    presets = {
      inc_rename = {
        cmdline = {
          format = {
            IncRename = {
              pattern = '^:%s*IncRename%s+',
              icon = ' ',
              conceal = true,
              opts = {
                relative = 'cursor',
                size = { min_width = 20 },
                position = { row = -3, col = 0 },
              },
            },
          },
        },
      },
    },
    cmdline = {
      format = {
        input = { view = 'cmdline' },
      },
    },
    notify = {
      enabled = true,
    },
    popupmenu = {
      enabled = true,
      backend = 'cmp',
    },
    lsp = {
      hover = {
        enabled = false,
      },
      signature = {
        enabled = false,
      },
    },
    commands = {
      history = {
        filter = {},
      },
    },
    routes = {
      {
        filter = {
          event = 'msg_show',
          kind = '',
          find = 'Code actions:',
        },
        opts = { replace = false },
      },
      {
        filter = {
          warning = true,
          find = 'angularls',
        },
        opts = { skip = true },
      },
    },
  },
}
