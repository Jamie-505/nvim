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
    -- lsp actions live under the generic <leader>l prefix: go-to / calls / type
    -- hierarchy / symbols / inlay hints come from lsp-opts (kotlin.nvim's
    -- commands for those are thin wrappers); the kotlin implementations of
    -- the rest are set per buffer on attach (see config). these are extras.
    { '<leader>kn', '<CMD>KotlinNewFromTemplate<CR>', desc = 'Kotlin New file from template' },
    { '<leader>kd', '<CMD>KotlinDebug<CR>', desc = 'Kotlin Attach debugger' },
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
    -- expired EAP build (exit 7) → show changelog + one-key update
    require('kotlin-workflow.update').setup(opts)

    -- generic <leader>l keys, kotlin implementation (jdtls.lua has its own)
    vim.api.nvim_create_autocmd('LspAttach', {
      group = vim.api.nvim_create_augroup('KotlinLspKeys', { clear = true }),
      callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if not client or client.name ~= 'kotlin_lsp' then
          return
        end
        local function map(lhs, rhs, desc)
          vim.keymap.set('n', lhs, rhs, { buffer = args.buf, desc = desc })
        end
        map('<leader>loi', '<CMD>KotlinOrganizeImports<CR>', 'Lsp Organize imports (kotlin)')
        map('<leader>lL', '<CMD>KotlinShowLogs<CR>', 'Lsp Show server logs (kotlin)')
        map('<leader>lsr', '<CMD>lsp restart kotlin_lsp<CR>', 'Lsp Restart server (kotlin)')
        map('<leader>lW', '<CMD>KotlinCleanWorkspace<CR>', 'Lsp Wipe workspace (kotlin)')
      end,
    })

    require('kotlin').setup(opts)

    -- setup() wires a `FileType kotlin` autocmd, but `ft = 'kotlin'` means this
    -- plugin loads *on* the first kotlin buffer, whose FileType has already
    -- fired. Attach it explicitly, mirroring the jdtls workaround.
    require('kotlin').setup_kotlin_lsp(opts)
  end,
}
