-- kotlin lsp (JetBrains kotlin-lsp via bin/intellij-server, which ships its own JBR)
return {
  'AlexandrosAlexiou/kotlin.nvim',
  dependencies = {
    'mason-org/mason.nvim',
    'stevearc/oil.nvim',
    'folke/trouble.nvim',
  },
  ft = 'kotlin',
  keys = {
    { '<leader>koi', '<CMD>KotlinOrganizeImports<CR>', desc = 'Kotlin Organize imports' },
    { '<leader>kgt', '<CMD>KotlinTypeDefinition<CR>', desc = 'Kotlin Go to type definition' },
    { '<leader>kgi', '<CMD>KotlinImplementation<CR>', desc = 'Kotlin Go to implementation' },
    { '<leader>kci', '<CMD>KotlinIncomingCalls<CR>', desc = 'Kotlin Incoming calls' },
    { '<leader>kco', '<CMD>KotlinOutgoingCalls<CR>', desc = 'Kotlin Outgoing calls' },
    { '<leader>ks', '<CMD>KotlinSymbols<CR>', desc = 'Kotlin Document symbols' },
    { '<leader>kS', '<CMD>KotlinWorkspaceSymbols<CR>', desc = 'Kotlin Workspace symbols' },
    { '<leader>kn', '<CMD>KotlinNewFromTemplate<CR>', desc = 'Kotlin New file from template' },
    { '<leader>kh', '<CMD>KotlinInlayHintsToggle<CR>', desc = 'Kotlin Toggle inlay hints' },
    { '<leader>kd', '<CMD>KotlinDebug<CR>', desc = 'Kotlin Attach debugger' },
    { '<leader>kl', '<CMD>KotlinShowLogs<CR>', desc = 'Kotlin Show logs' },
    { '<leader>kw', '<CMD>KotlinCleanWorkspace<CR>', desc = 'Kotlin Wipe workspace' },
  },
  opts = function()
    return {
      -- the server bundles its own JBR to *run*; this is the JDK it analyzes
      -- against, and auto-detection reads $JAVA_HOME, which points at the
      -- active asdf install
      jdk_for_symbol_resolution = require('jdk').find('25'),
      jvm_args = { '-Xmx4g' },
    }
  end,
  config = function(_, opts)
    require('kotlin').setup(opts)

    -- setup() wires a `FileType kotlin` autocmd, but `ft = 'kotlin'` means this
    -- plugin loads *on* the first kotlin buffer, whose FileType has already
    -- fired. Attach it explicitly, mirroring the jdtls workaround.
    require('kotlin').setup_kotlin_lsp(opts)
  end,
}
