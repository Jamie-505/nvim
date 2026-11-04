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
    { '<leader>k', desc = '+Kotlin', mode = { 'n', 'x' } },
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
  init = function()
    -- quality checks run through Gradle only, so these work without the
    -- server (and without loading this plugin)
    local function q(fn)
      return function()
        require('kotlin-quality')[fn]()
      end
    end
    local map = function(lhs, fn, desc)
      vim.keymap.set('n', lhs, q(fn), { desc = desc })
    end
    map('<leader>kq', 'check', 'Kotlin Quality check project')
    map('<leader>kQ', 'check_modules', 'Kotlin Quality check modules')
    map('<leader>ku', 'check_untyped', 'Kotlin Quality fast untyped detekt')
    map('<leader>kf', 'format', 'Kotlin Format project (ktlintFormat)')
    map('<leader>kF', 'format_modules', 'Kotlin Format modules (ktlintFormat)')
    map('<leader>kx', 'cancel', 'Kotlin Quality cancel run')
    map('<leader>kr', 'open_log', 'Kotlin Quality last run log')
    -- grn / <leader>lr / <leader>lR on kotlin-lsp buffers: guarded rename
    require('guarded-rename').setup()
  end,
  opts = function()
    return {
      -- the server bundles its own JBR to *run*; this is the JDK it analyzes
      -- against, and auto-detection reads $JAVA_HOME, which points at the
      -- active asdf install
      jdk_for_symbol_resolution = require('jdk').find('25'),
      -- a fresh index of the trial sample peaked at ~6 GiB RSS with -Xmx4g;
      -- warm sessions sit around 1.2 GiB. the heap may grow to 8 GiB, no -Xms.
      jvm_args = { '-Xmx8g' },
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
