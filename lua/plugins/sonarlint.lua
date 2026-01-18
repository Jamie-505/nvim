return {
  enabled = false,
  name = 'sonarlint',
  url = 'https://gitlab.com/schrieveslaach/sonarlint.nvim',
  ft = {
    'javascript',
    'typescript',
  },
  opts = {
    server = {
      cmd = {
        'sonarlint-language-server',
        -- Ensure that sonarlint-language-server uses stdio channel
        '-stdio',
        '-analyzers',
        vim.fn.expand('$MASON/share/sonarlint-analyzers/sonarjs.jar'),
      },
    },
    filetypes = {
      -- Tested and working
      'typescript',
      'javascript',
    },
  },
}
