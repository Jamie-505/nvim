local M = {}
local map = vim.keymap.set
local spinner = require('spinner')
local utils = require('utils')

local function apply_rename(currName, win)
  local newName = vim.trim(vim.fn.getline('.'))
  vim.api.nvim_win_close(win, true)

  if string.len(newName) > 0 and newName ~= currName then
    local params = vim.lsp.util.make_position_params(0, 'utf-8')
    params = vim.tbl_extend('force', params, { newName = newName })

    if spinner.should_show_spinner() then
      local stripped_current_name = string.sub(currName, 1, #currName - 1)
      spinner.show('Renaming ' .. "'" .. stripped_current_name .. "'" .. ' to ' .. "'" .. newName .. "'", 'LSP')
    end
    -- Angular specific check to prevent double renaming
    if
      #vim.lsp.get_clients({ bufnr = 0, name = 'angularls' }) > 0
      and (vim.bo.filetype == 'typescript' or vim.bo.filetype == 'htmlangular' or vim.bo.filetype == 'html')
    then
      vim.lsp.buf.rename(newName, { name = 'angularls' })
    else
      vim.lsp.buf_request(0, 'textDocument/rename', params)
    end
  end
end

local function rename()
  if #vim.lsp.get_clients({ bufnr = 0 }) < 1 then
    Snacks.notify.warn('No LSP attached to this buffer', { title = 'LSP' })
    return
  end

  local currName = vim.fn.expand('<cword>') .. ' '

  local win = require('plenary.popup').create(currName, {
    title = 'Rename',
    style = 'minimal',
    borderchars = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' },
    relative = 'cursor',
    borderhighlight = 'RenamerBorder',
    titlehighlight = 'RenamerTitle',
    focusable = true,
    width = 25,
    height = 1,
    line = 'cursor+2',
    col = 'cursor-1',
  })

  vim.cmd('normal A')
  vim.cmd('startinsert')

  map({ 'n' }, '<Esc>', '<CMD>q<CR>', { buffer = 0 })

  map({ 'i', 'n' }, '<CR>', function()
    apply_rename(currName, win)
    vim.cmd.stopinsert()
  end, { buffer = 0 })
end

-- basic lsp config
vim.api.nvim_create_autocmd({ 'LspAttach' }, {
  callback = function(args)
    -- inlay hints
    vim.lsp.inlay_hint.enable(true, { bufnr = args.buf })
  end,
})

-- hints go stale exactly while you are typing, which is the window where the
-- decoration provider draws them past the end of a line
vim.api.nvim_create_autocmd('InsertEnter', {
  callback = function(args)
    if vim.lsp.inlay_hint.is_enabled({ bufnr = args.buf }) then
      vim.b[args.buf].inlay_hint_restore = true
      vim.lsp.inlay_hint.enable(false, { bufnr = args.buf })
    end
  end,
})
vim.api.nvim_create_autocmd('InsertLeave', {
  callback = function(args)
    if vim.b[args.buf].inlay_hint_restore then
      vim.b[args.buf].inlay_hint_restore = nil
      vim.lsp.inlay_hint.enable(true, { bufnr = args.buf })
    end
  end,
})

-- jdtls answers requests with null until it finished loading the project, so a
-- hover fired right after startup looks like "No information available".
-- `language/status` tells us when it is actually usable, keyed by root_dir.
M.jdtls_ready = {}

-- LspDetach also fires when a single buffer detaches, so confirm the client is
-- really gone (:JdtRestart, crash) before dropping its readiness
vim.api.nvim_create_autocmd('LspDetach', {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if not client or client.name ~= 'jdtls' then
      return
    end
    local root_dir = client.root_dir or ''
    vim.schedule(function()
      if not vim.lsp.get_client_by_id(args.data.client_id) then
        M.jdtls_ready[root_dir] = nil
      end
    end)
  end,
})

local make_capabilities = function()
  local capabilities = vim.lsp.protocol.make_client_capabilities()

  capabilities.textDocument.completion.completionItem = {
    documentationFormat = { 'markdown', 'plaintext' },
    snippetSupport = true,
    preselectSupport = true,
    insertReplaceSupport = true,
    labelDetailsSupport = true,
    deprecatedSupport = true,
    commitCharactersSupport = true,
    tagSupport = { valueSet = { 1 } },
    resolveSupport = {
      properties = {
        'documentation',
        'detail',
        'additionalTextEdits',
      },
    },
  }
  capabilities.textDocument.foldingRange = {
    dynamicRegistration = false,
    lineFoldingOnly = true,
  }
  -- capabilities = require("blink.cmp").get_lsp_capabilities(M.capabilities)
  return capabilities
end

M.capabilities = make_capabilities()
-- servers whose semantic tokens resolve things treesitter cannot (globals vs
-- locals, field vs local, class vs interface, hcl reference targets)
local semantic_tokens_ok = {
  dockerls = true,
  jdtls = true,
  kotlin_language_server = true,
  lua_ls = true,
  -- no qmljs treesitter parser installed, so these tokens are the only
  -- structured highlighting qml gets
  qmlls = true,
  terraformls = true,
  ts_ls = true,
}

M.on_init = function(client, _)
  if semantic_tokens_ok[client.name] then
    return
  end
  if client:supports_method('textDocument/semanticTokens') then
    client.server_capabilities.semanticTokensProvider = nil
  end
end

local function send_lsp_notification(message)
  -- only send notifications, if the folder path includes "projects"
  if spinner.should_show_spinner() then
    local current_word = vim.call('expand', '<cword>')
    spinner.show(message .. current_word, 'LSP')
  end
end

-- Stop spinner, if request is completed or canceled
vim.api.nvim_create_autocmd('LspRequest', {
  callback = function(args)
    local request = args.data.request
    local relevant_methods = {
      'textDocument/declaration',
      'textDocument/definition',
      'textDocument/implementation',
      'callHierarchy/incomingCalls',
      'callHierarchy/outgoingCalls',
      'textDocument/typeDefinition',
      'textDocument/documentSymbol',
      'textDocument/references',
      'workspace/symbol',
      'textDocument/rename',
    }
    local is_relevant = false
    for i = 1, #relevant_methods do
      if relevant_methods[i] == request.method then
        is_relevant = true
        break
      end
    end
    if is_relevant and (request.type == 'cancel' or request.type == 'complete') then
      spinner.hide()
    end
  end,
})
M.setup_keymaps = function()
  local function opts(desc)
    return { desc = desc }
  end

  map('n', '<leader>gD', utils.gotoDefinitionInSplit, { desc = 'Open definition in split' })

  map('n', '<leader>lcr', function()
    M.defaults()
    M.setup_keymaps()
    M.setup_colors()
  end, opts('Lsp Reload Lsp config'))

  map('n', '<leader>lgD', function()
    send_lsp_notification('Go to declaration: ')
    vim.lsp.buf.declaration()
  end, opts('Lsp Go to declaration'))
  map('n', '<leader>lgd', function()
    send_lsp_notification('Go to definition: ')
    require('telescope.builtin').lsp_definitions({
      initial_mode = 'normal',
      layout_config = {
        horizontal = {
          preview_width = 0.55,
        },
      },
    })
  end, opts('Lsp Go to definition'))
  -- vim.lsp.buf.hover waits for every attached client and renders whatever came
  -- back. on java both jdtls and the spring boot server answer, the latter
  -- always with an empty `contents`, so a jdtls that is still resolving the
  -- compilation unit shows up as "Empty hover response". ask the useful client
  -- alone and give it a couple of chances to warm up.
  local hover_client = { java = 'jdtls' }

  local function hover_has_content(result)
    local contents = result and result.contents
    if not contents then
      return false
    end
    if type(contents) == 'string' then
      return #contents > 0
    end
    return not vim.tbl_isempty(contents)
  end

  -- jdtls answers punctuation with an empty payload, so hovering the `@` of an
  -- annotation reports nothing. shift onto the identifier it belongs to.
  local function hover_position_params(client)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()
    local col = cursor[2]
    if not line:sub(col + 1, col + 1):match('[%w_]') and line:sub(col + 2, col + 2):match('[%w_]') then
      col = col + 1
    end
    return {
      textDocument = vim.lsp.util.make_text_document_params(0),
      position = {
        line = cursor[1] - 1,
        character = vim.str_utfindex(line, client.offset_encoding, col, false),
      },
    }
  end

  local function hover_request(client, retries)
    local bufnr = vim.api.nvim_get_current_buf()
    local params = hover_position_params(client)
    client:request('textDocument/hover', params, function(err, result, ctx)
      if not err and not hover_has_content(result) and retries > 0 and vim.api.nvim_get_current_buf() == bufnr then
        vim.defer_fn(function()
          hover_request(client, retries - 1)
        end, 300)
        return
      end
      vim.lsp.handlers['textDocument/hover'](err, result, ctx, { border = 'rounded' })
    end, bufnr)
  end

  local function hover()
    local name = hover_client[vim.bo.filetype]
    if not name then
      vim.lsp.buf.hover({
        border = 'rounded',
      })
      return
    end

    local bufnr = vim.api.nvim_get_current_buf()
    local waited = 0
    local function attempt()
      if vim.api.nvim_get_current_buf() ~= bufnr then
        return
      end
      local client = vim.lsp.get_clients({ bufnr = bufnr, name = name })[1]
      local ready = client and M.jdtls_ready[client.root_dir or ''] or false
      if client and (ready or waited >= 30000) then
        hover_request(client, 2)
        return
      end
      if waited >= 30000 then
        vim.lsp.buf.hover({
          border = 'rounded',
        })
        return
      end
      if waited == 0 then
        vim.notify(name .. ' is still loading the project, hover pending', vim.log.levels.INFO)
      end
      waited = waited + 500
      vim.defer_fn(attempt, 500)
    end
    attempt()
  end

  map('n', '<leader>lh', hover, opts('Lsp hover information'))
  map('n', 'K', hover, opts('Lsp hover information'))
  map('n', '<leader>lgi', function()
    send_lsp_notification('Go to implementation: ')
    require('telescope.builtin').lsp_implementations({
      initial_mode = 'normal',
      layout_config = {
        horizontal = {
          preview_width = 0.55,
        },
      },
    })
  end, opts('Lsp Go to implementation'))
  map('n', '<leader>lgci', function()
    send_lsp_notification('Go to incoming callers: ')
    require('telescope.builtin').lsp_incoming_calls({
      initial_mode = 'normal',
      layout_config = {
        horizontal = {
          preview_width = 0.55,
        },
      },
    })
  end, opts('Lsp Go to incoming calls'))
  map('n', '<leader>lgco', function()
    send_lsp_notification('Go to outgoing callers: ')
    require('telescope.builtin').lsp_outgoing_calls({
      initial_mode = 'normal',
      layout_config = {
        horizontal = {
          preview_width = 0.55,
        },
      },
    })
  end, opts('Lsp Go to outgoing calls'))
  map('n', '<leader>lsh', function()
    require('lsp_signature').toggle_float_win()
  end, opts('Lsp Show signature help'))
  map('n', '<leader>lwa', vim.lsp.buf.add_workspace_folder, opts('Lsp Add workspace folder'))
  map('n', '<leader>lwr', vim.lsp.buf.remove_workspace_folder, opts('Lsp Remove workspace folder'))
  map({ 'n', 'v', 'x' }, '<leader>lca', vim.lsp.buf.code_action, opts('Lsp Code action'))

  map('n', '<leader>lw', function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, opts('Lsp List workspace folders'))

  map('n', '<leader>lD', function()
    send_lsp_notification('Go to type definitions: ')
    require('telescope.builtin').lsp_type_definitions({
      initial_mode = 'normal',
      layout_config = {
        horizontal = {
          preview_width = 0.55,
        },
      },
    })
  end, opts('Lsp Go to type definition'))

  map('n', '<leader>lr', function()
    rename()
  end, opts('Lsp Rename'))

  map('n', '<leader>lgr', function()
    send_lsp_notification('Go to references: ')
    require('telescope.builtin').lsp_references({
      initial_mode = 'normal',
      layout_config = {
        horizontal = {
          preview_width = 0.55,
        },
      },
    })
  end, opts('Lsp Show references'))

  map('n', '<leader>lcl', function()
    vim.lsp.codelens.run()
  end, opts('Lsp Codelens'))

  map('n', '<leader>li', function()
    local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = 0 })
    vim.lsp.inlay_hint.enable(not enabled, { bufnr = 0 })
  end, opts('Lsp Toggle inlay hints'))

  map('n', '<leader>lls', function()
    spinner.hide()
  end, opts('Lsp Hide lsp loading spinner'))
end

M.setup_colors = function()
  require('colors').add_and_set_color_module('lsp', function()
    vim.api.nvim_set_hl(0, 'FloatBorder', {
      fg = '#f9e2af',
    })
  end)
end

M.defaults = function()
  -- Diagnostic Signs
  local x = vim.diagnostic.severity

  vim.diagnostic.config({
    severity_sort = true,
    virtual_text = { prefix = '' },
    signs = { text = { [x.ERROR] = '󰅙', [x.WARN] = '', [x.INFO] = '󰋼', [x.HINT] = '󰌵' } },
    underline = true,
    float = { border = 'single' },
  })

  -- General LSP config
  vim.lsp.config('*', {
    on_init = M.on_init,
    capabilities = M.capabilities,
  })

  -- LSPs without specific config
  local lsp_servers = {
    'cssls',
    'docker_compose_language_service',
    'jsonls',
    'kotlin_language_server',
    'pyright',
    'qmlls',
    'terraformls',
  }

  -- LSPs with default config
  for _, lsp in ipairs(lsp_servers) do
    vim.lsp.enable(lsp)
  end

  -- LSPs with specific config

  -- Angular
  local angular_json_path = vim.fs.dirname(vim.fs.find({ 'angular.json' }, {
    path = vim.loop.cwd(),
    upward = true,
  })[1])
  if angular_json_path ~= nil then
    local ok, mason_registry = pcall(require, 'mason-registry')
    if not ok then
      vim.notify('mason-registry could not be loaded')
      return
    end

    local angularls_path = vim.fn.expand('$MASON/packages/angular-language-server')
    local handle_angular_exit = function(code, signal, client_id)
      if code > 0 then
        vim.schedule(function()
          -- print "Restarting failed Angular LS.."
          vim.cmd('LspStart angularls')
        end)
      end
    end

    local cmd = {
      'ngserver',
      '--stdio',
      '--tsProbeLocations',
      table.concat({
        angularls_path,
        vim.uv.cwd(),
      }, ','),
      '--ngProbeLocations',
      table.concat({
        angularls_path .. '/node_modules/@angular/language-server',
        vim.uv.cwd(),
      }, ','),
    }

    vim.lsp.config('angularls', {
      cmd = cmd,
      on_exit = handle_angular_exit,
      on_new_config = function(new_config, _)
        new_config.cmd = cmd
      end,
      filetypes = { 'htmlangular', 'typescript', 'html', 'typescriptreact', 'typescript.tsx' },
    })
    vim.lsp.enable('angularls')
  end

  -- Bash
  vim.lsp.config('bashls', {
    filetypes = { 'sh', 'bash' },
  })
  vim.lsp.enable('bashls')

  -- Dockerfile Language Server
  vim.lsp.config('dockerls', {
    settings = {
      docker = {
        languageserver = {
          formatter = {
            ignoreMultilineInstructions = true,
          },
        },
      },
    },
  })
  vim.lsp.enable('dockerls')

  -- Emmet Language Server
  vim.lsp.config('emmet_language_server', {
    filetypes = {
      'htmlangular',
      'htcss',
      'eruby',
      'html',
      'htmldjango',
      'javascriptreact',
      'less',
      'pug',
      'sass',
      'scss',
      'typescriptreactml',
    },
  })
  vim.lsp.enable('emmet_language_server')

  local base_on_attach = vim.lsp.config.eslint.on_attach
  vim.lsp.config('eslint', {
    on_attach = function(client, bufnr)
      if not base_on_attach then
        return
      end

      base_on_attach(client, bufnr)
      vim.api.nvim_create_autocmd('BufWritePre', {
        buffer = bufnr,
        command = 'LspEslintFixAll',
      })
    end,
  })
  vim.lsp.enable('eslint')

  -- HTML
  vim.lsp.config('html', {
    filetypes = {
      'htmlangular',
      'html',
      'templ',
    },
  })
  vim.lsp.enable('html')

  -- lua
  vim.lsp.config('lua_ls', {
    settings = {
      Lua = {
        diagnostics = {
          globals = { 'vim' },
        },
        -- workspace.library is managed by lazydev.nvim
        workspace = {
          checkThirdParty = false,
          maxPreload = 100000,
          preloadFileSize = 10000,
        },
      },
    },
  })
  vim.lsp.enable('lua_ls')

  -- TypeScript
  vim.lsp.config('ts_ls', {
    on_attach = function(client, bufnr)
      vim.api.nvim_buf_create_user_command(bufnr, 'OrganizeImports', function()
        client:exec_cmd({
          command = '_typescript.organizeImports',
          arguments = { vim.api.nvim_buf_get_name(0) },
        })
      end, {})
      vim.api.nvim_buf_set_keymap(
        bufnr,
        'n',
        '<leader>loi',
        '<CMD>OrganizeImports<CR>',
        { desc = 'Lsp organize imports' }
      )
    end,
    init_options = {
      preferences = {
        includeInlayParameterNameHints = 'literal', -- 'none' | 'literals' | 'all'
        includeInlayParameterNameHintsWhenArgumentMatchesName = false,
        includeInlayVariableTypeHints = true,
        includeInlayFunctionParameterTypeHints = true,
        includeInlayVariableTypeHintsWhenTypeMatchesName = true,
        includeInlayPropertyDeclarationTypeHints = true,
        includeInlayFunctionLikeReturnTypeHints = true,
        includeInlayEnumMemberValueHints = true,
        disableSuggestions = true,
        importModuleSpecifierPreference = 'relative',
      },
    },
  })
  vim.lsp.enable('ts_ls')

  vim.lsp.config('yamlls', {
    filetypes = { 'yaml', 'yaml.gitlab' },
  })
  vim.lsp.enable('yamlls')

  -- Latex
  -- vim.lps.config("ltex", {
  --   filetypes = {
  --     "bib",
  --     "gitcommit",
  --     "org",
  --     "plaintex",
  --     "rst",
  --     "rnoweb",
  --     "tex",
  --     "pandoc",
  --     "quarto",
  --     "rmd",
  --     "context",
  --     "mail",
  --     "text",
  --   },
  --   settings = {
  --     ltex = {
  --       language = "de-DE",
  --       checkFrequency = "save",
  --     },
  --   },
  -- })
  -- vim.lsp.enable("ltex")
  -- vim.lsp.config("texlab", {
  --   on_init = M.on_init,
  --   capabilities = M.capabilities,
  -- })
  -- vim.lsp.enable("texlab")
end

return M
