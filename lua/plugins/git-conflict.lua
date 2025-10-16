return {
  'akinsho/git-conflict.nvim',
  version = '*',
  event = 'BufReadPost',
  keys = {
    { '<leader>cn', '<cmd>GitConflictNextConflict<CR>', desc = 'Git Conflict Next' },
    { '<leader>cp', '<cmd>GitConflictPrevConflict<CR>', desc = 'Git Conflict Prev' },
    { '<leader>co', '<cmd>GitConflictChooseOurs<CR>', desc = 'Git Conflict Choose Ours' },
    { '<leader>ct', '<cmd>GitConflictChooseTheirs<CR>', desc = 'Git Conflict Choose Theirs' },
    { '<leader>cb', '<cmd>GitConflictChooseBoth<CR>', desc = 'Git Conflict Choose Both' },
    { '<leader>cl', '<cmd>GitConflictListQf<CR>', desc = 'Git Conflict List' },
  },
  opts = {
    default_mappings = false, -- disable buffer local mapping created by this plugin
    default_commands = true, -- disable commands created by this plugin
    disable_diagnostics = false, -- This will disable the diagnostics in a buffer whilst it is conflicted
    list_opener = 'copen', -- command or function to open the conflicts list
    highlights = { -- They must have background color, otherwise the default color will be used
      incoming = 'DiffAdd',
      current = 'DiffText',
    },
  },
}
