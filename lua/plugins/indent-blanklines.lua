return {
  'lukas-reineke/indent-blankline.nvim',
  event = 'BufReadPost',
  keys = {
    {
      '<leader>gc',
      function()
        local config = { scope = {} }
        config.scope.exclude = { language = {}, node_type = {} }
        config.scope.include = { node_type = {} }
        local node = require('ibl.scope').get(vim.api.nvim_get_current_buf(), config)

        if node then
          local start_row, _, end_row, _ = node:range()
          if start_row ~= end_row then
            vim.api.nvim_win_set_cursor(vim.api.nvim_get_current_win(), { start_row + 1, 0 })
            vim.api.nvim_feedkeys('_', 'n', true)
          end
        end
      end,
      desc = 'Goto Inner Context',
    },
    {
      '<leader>ti',
      '<cmd>IBLToggle<CR>',
      desc = 'Toggle Indentation lines',
    },
  },
  opts = {
    indent = { char = '│', highlight = 'IblChar' },
    scope = { enabled = false, char = '│', highlight = 'IblScopeChar' },
  },
  config = function(_, opts)
    require('colors').add_and_set_color_module('ibl', function()
      vim.api.nvim_set_hl(0, 'IblScopeChar', {
        fg = '#fdfd96',
      })
      vim.api.nvim_set_hl(0, 'IblScope', {
        fg = '#fdfd96',
      })
      vim.api.nvim_set_hl(0, 'IblChar', {
        fg = '#383747',
      })
    end)

    require('utils').add_and_run_global_function('ibl_setup', function()
      require('ibl').setup(opts)
      local hooks = require('ibl.hooks')
      hooks.register(hooks.type.WHITESPACE, hooks.builtin.hide_first_space_indent_level)
      require('ibl').refresh()
    end)
  end,
}
