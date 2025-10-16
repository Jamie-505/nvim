return {
  'HiPhish/rainbow-delimiters.nvim',
  event = { 'BufEnter', 'BufNew' },
  submodules = false,
  keys = {
    {
      '<leader>tr',
      function()
        require('rainbow-delimiters').toggle()
      end,
      desc = 'Toggle Rainbow delimiters',
    },
  },
  config = function()
    require('rainbow-delimiters.setup').setup({
      strategy = {
        -- ...
      },
      query = {
        -- ...
      },
      highlight = {
        'RainbowDelimiterRed',
        'RainbowDelimiterOrange',
        'RainbowDelimiterYellow',
        'RainbowDelimiterGreen',
        'RainbowDelimiterBlue',
        'RainbowDelimiterCyan',
        'RainbowDelimiterViolet',
      },
    })
    require('colors').add_and_set_color_module('rainbow-delimiters', function()
      vim.api.nvim_set_hl(0, 'RainbowDelimiterRed', {
        fg = '#f38ba8',
      })
      vim.api.nvim_set_hl(0, 'RainbowDelimiterYellow', {
        fg = '#fdfd96',
      })
      vim.api.nvim_set_hl(0, 'RainbowDelimiterViolet', {
        fg = '#b4befe',
      })
      vim.api.nvim_set_hl(0, 'RainbowDelimiterBlue', {
        fg = '#89b4fa',
      })
      vim.api.nvim_set_hl(0, 'RainbowDelimiterGreen', {
        fg = '#a6e3a1',
      })
      vim.api.nvim_set_hl(0, 'RainbowDelimiterOrange', {
        fg = '#fab387',
      })
      vim.api.nvim_set_hl(0, 'RainbowDelimiterCyan', {
        fg = '#94e2d5',
      })
    end)
  end,
}
