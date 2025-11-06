return {
  'akinsho/git-conflict.nvim',
  version = '*',
  event = 'BufReadPost',
  keys = {
    { '<leader>cn', '<CMD>GitConflictNextConflict<CR>', desc = 'Git Conflict Next' },
    { '<leader>cp', '<CMD>GitConflictPrevConflict<CR>', desc = 'Git Conflict Prev' },
    { '<leader>co', '<CMD>GitConflictChooseOurs<CR>', desc = 'Git Conflict Choose Ours' },
    { '<leader>ct', '<CMD>GitConflictChooseTheirs<CR>', desc = 'Git Conflict Choose Theirs' },
    { '<leader>cb', '<CMD>GitConflictChooseBoth<CR>', desc = 'Git Conflict Choose Both' },
    { '<leader>cl', '<CMD>GitConflictListQf<CR>', desc = 'Git Conflict List' },
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
