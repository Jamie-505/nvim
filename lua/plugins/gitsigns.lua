return {
  'lewis6991/gitsigns.nvim',
  event = 'BufReadPost',
  keys = {
    { '<leader>ghr', '<cmd>Gitsigns reset_hunk<CR>', desc = 'Git Reset Hunk' },
    { '<leader>ghp', '<cmd>Gitsigns preview_hunk<CR>', desc = 'Git Preview Hunk' },
    { '<leader>ghn', '<cmd>Gitsigns next_hunk<CR>', desc = 'Git Blame Next Hunk' },
    { '<leader>ghN', '<cmd>Gitsigns prev_hunk<CR>', desc = 'Git Blame Previous Hunk' },
    { '<leader>gbl', '<cmd>Gitsigns blame_line<CR>', desc = 'Git Blame Line' },
    { '<leader>gbc', '<cmd>Gitsigns blame<CR>', desc = 'Git Blame Current Buffer' },
  },
  opts = function()
    local options = {
      signs = {
        add = { text = '│' },
        change = { text = '│' },
        delete = { text = '󰍵' },
        topdelete = { text = '‾' },
        changedelete = { text = '~' },
        untracked = { text = '│' },
      },
      preview_config = {
        style = 'minimal',
        relative = 'cursor',
        border = 'rounded',
      },
    }

    return options
  end,
}
