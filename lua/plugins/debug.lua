return {
  {
    'mfussenegger/nvim-dap',
    keys = {
      { '<leader>D', '<CMD>DapNew<CR>', desc = 'Debug New' },
      { '<leader>dba', '<CMD>DapClearBreakpoints<CR>', desc = 'Debug Clear Breakpoints' },
      {
        '<leader>dbc',
        function()
          require('dap').set_breakpoint(vim.fn.input('Breakpoint condition'))
        end,
        desc = 'Debug Breakpoint with condition',
      },
      {
        '<leader>dbt',
        '<CMD>DapToggleBreakpoint<CR>',
        desc = 'Toggle Debug Breakpoint',
      },
      {
        '<leader>de',
        function()
          require('dap').set_exception_breakpoints()
        end,
        desc = 'Debug Set exception breakpoints',
      },
      { '<leader>dc', '<CMD>DapContinue<CR>', desc = 'Debug Continue' },
      {
        '<leader>dp',
        function()
          require('dap').pause()
        end,
        desc = 'Debug Pause',
      },
      {
        '<leader>dC',
        function()
          require('dap').run_to_cursor()
        end,
        desc = 'Debug Continue to cursor',
      },
      {
        '<leader>dk',
        function()
          require('dap').up()
        end,
        desc = 'Debug Up',
      },
      {
        '<leader>dj',
        function()
          require('dap').down()
        end,
        desc = 'Debug Down',
      },
      { '<leader>dso', '<CMD>DapStepOver<CR>', desc = 'Debug Step Over' },
      { '<leader>dsO', '<CMD>DapStepOut<CR>', desc = 'Debug Step Out' },
      { '<leader>dsi', '<CMD>DapStepIn<CR>', desc = 'Debug Step In' },
      {
        '<leader>dh',
        function()
          require('dap.ui.widgets').hover()
        end,
        desc = 'Debug Widgets hover',
      },
      { '<leader>dr', '<CMD>DapToggleRepl<CR>', desc = 'Debug Toggle Repl' },
      { '<leader>dd', '<CMD>DapDisconnect<CR>', desc = 'Debug Disconnect' },
      { '<leader>dt', '<CMD>DapTerminate<CR>', desc = 'Debug Terminate' },
      {
        '<leader>dus',
        function()
          local widgets = require('dap.ui.widgets')
          local sidebar = widgets.sidebar(widgets.scopes)
          sidebar.open()
        end,
        desc = 'Debug Open sidebar',
      },
    },
    opts = function()
      local M = {}
      local dap = require('dap')

      -- Adapters
      local dartAdapter = function()
        dap.adapters.dart = {
          type = 'executable',
          command = 'dart', -- if you're using fvm, you'll need to provide the full path to dart (dart.exe for windows users), or you could prepend the fvm command
          args = { 'debug_adapter' },
          -- windows users will need to set 'detached' to false
          options = {
            detached = false,
          },
        }
      end

      local flutterAdapter = function()
        dap.adapters.flutter = {
          type = 'executable',
          command = 'flutter', -- if you're using fvm, you'll need to provide the full path to flutter (flutter.bat for windows users), or you could prepend the fvm command
          args = { 'debug_adapter' },
          -- windows users will need to set 'detached' to false
          options = {
            detached = false,
          },
        }
        require('dap').defaults.flutter.exception_breakpoints = {}
      end

      local javascriptAdapter = function()
        dap.adapters['pwa-node'] = {
          type = 'server',
          host = 'localhost',
          port = '${port}',
          executable = {
            command = 'js-debug-adapter',
            args = {
              '${port}',
            },
          },
          enrich_config = function(config, on_config)
            config.type = 'pwa-node'
            -- TODO: fix for launching vscode launch.js configurations
            -- if config.program ~= nil and string.match(config.program, "%.ts$") then
            --   config.runtimeExecutable = "nodemon"
            --   config.args = { "--watch", "src/**/*.ts", "--exec", "npx", "ts-node", "${file}" }
            -- end
            on_config(config)
          end,
        }

        dap.adapters['node'] = dap.adapters['pwa-node']
      end

      local chromeAdapter = function()
        dap.adapters['pwa-chrome'] = {
          type = 'executable',
          host = 'localhost',
          port = '${port}',
          executable = {
            command = 'js-debug-adapter',
            args = {
              '${port}',
            },
          },
          enrich_config = function(config, on_config)
            config.type = 'pwa-chrome'
            on_config(config)
          end,
        }

        dap.adapters['chrome'] = dap.adapters['pwa-chrome']
      end

      -- Configurations
      local javascriptConfigurations = function()
        dap.configurations.javascript = {
          {
            name = 'Launch file',
            type = 'pwa-node',
            request = 'launch',
            program = '${file}',
            cwd = '${workspaceFolder}',
            console = 'integratedTerminal',
            sourceMaps = true,
          },
          {
            name = 'Attach to Node',
            type = 'pwa-node',
            request = 'attach',
            processId = require('dap.utils').pick_process,
            cwd = '${workspaceFolder}',
            console = 'integratedTerminal',
          },
          {
            type = 'pwa-chrome',
            request = 'launch',
            name = 'Launch & Debug Chrome',
            url = function()
              local co = coroutine.running()
              return coroutine.create(function()
                vim.ui.input({
                  prompt = 'Enter URL: ',
                  default = 'http://localhost:3000',
                }, function(url)
                  if url == nil or url == '' then
                    return
                  else
                    coroutine.resume(co, url)
                  end
                end)
              end)
            end,
            webRoot = vim.fn.getcwd(),
            protocol = 'inspector',
            sourceMaps = true,
            userDataDir = false,
          },
          -- Divider for the launch.json derived configs
          {
            name = '----- ↓ launch.json configs ↓ -----',
            type = '',
            request = 'launch',
          },
        }
      end

      local typescriptConfigurations = function()
        dap.configurations.typescript = {
          {
            name = 'Launch Node',
            type = 'pwa-node',
            request = 'launch',
            runtimeExecutable = 'tsx',
            args = { '--inspect', '${file}' },
            skipFiles = { 'node_modules/**' },
            cwd = '${workspaceFolder}',
            console = 'integratedTerminal',
            sourceMaps = true,
          },
          {
            name = 'Launch Nodemon (npx)',
            type = 'pwa-node',
            request = 'launch',
            runtimeExecutable = 'npx',
            args = { 'nodemon', '--watch', 'src/**/*.ts', '--exec', 'npx', 'ts-node', '${file}' },
            skipFiles = { 'node_modules/**' },
            cwd = '${workspaceFolder}',
            console = 'integratedTerminal',
            sourceMaps = true,
          },
          {
            name = 'Launch Nodemon (npx): src/main.ts',
            type = 'pwa-node',
            request = 'launch',
            runtimeExecutable = 'npx',
            args = {
              'nodemon',
              '--watch',
              'src',
              '--ext',
              'ts',
              '--exec',
              'node',
              '--loader',
              'ts-node/esm',
              '${workspaceFolder}/src/main.ts',
            },
            skipFiles = { 'node_modules/**' },
            cwd = '${workspaceFolder}',
            console = 'repl',
            sourceMaps = true,
          },
          {
            name = 'Launch Nodemon (ESM + ts-node)',
            type = 'pwa-node',
            request = 'launch',
            runtimeExecutable = 'npx',
            args = {
              'nodemon',
              '--watch',
              'src',
              '--ext',
              'ts',
              '--exec',
              'node',
              '--loader',
              'ts-node/esm',
              '--no-warnings',
              '${workspaceFolder}/src/main.ts',
            },
            cwd = '${workspaceFolder}',
            console = 'integratedTerminal',
            sourceMaps = true,
            skipFiles = { 'node_modules/**' },
          },
          {
            name = 'Launch Nodemon (global)',
            type = 'pwa-node',
            request = 'launch',
            runtimeExecutable = 'nodemon',
            args = { '--watch', 'src/**/*.ts', '--exec', 'npx', 'ts-node', '${file}' },
            skipFiles = { 'node_modules/**' },
            cwd = '${workspaceFolder}',
            console = 'integratedTerminal',
            sourceMaps = true,
          },
          {
            name = 'Attach to Node',
            type = 'pwa-node',
            request = 'attach',
            processId = require('dap.utils').pick_process,
            cwd = '${workspaceFolder}',
            console = 'integratedTerminal',
          },
          {
            type = 'pwa-chrome',
            request = 'launch',
            name = 'Launch & Debug Chrome',
            url = function()
              local co = coroutine.running()
              return coroutine.create(function()
                vim.ui.input({
                  prompt = 'Enter URL: ',
                  default = 'http://localhost:3000',
                }, function(url)
                  if url == nil or url == '' then
                    return
                  else
                    coroutine.resume(co, url)
                  end
                end)
              end)
            end,
            webRoot = vim.fn.getcwd(),
            protocol = 'inspector',
            sourceMaps = true,
            userDataDir = false,
          },
          -- Divider for the launch.json derived configs
          {
            name = '----- ↓ launch.json configs ↓ -----',
            type = '',
            request = 'launch',
          },
        }
      end

      M.setup_adapters = function()
        dartAdapter()
        flutterAdapter()
        javascriptAdapter()
        chromeAdapter()
      end

      M.setup_configurations = function()
        javascriptConfigurations()
        typescriptConfigurations()
        -- VSCode configurations
        -- local ok, parser = pcall(require, "json5")
        -- if ok then
        --   local vscode = require "dap.ext.vscode"
        --   vscode.json_decode = function(str)
        --     return parser.parse(str)
        --   end
        --   require("dap.ext.vscode").load_launchjs()
        -- end
        -- require("dap.ext.vscode").load_launchjs()
      end

      M.setup_colors = function()
        require('colors').add_and_set_color_module('debug', function()
          vim.api.nvim_set_hl(0, 'SignColumn', {
            fg = '#bbbbbb',
          })
          vim.api.nvim_set_hl(0, 'DapBreakpoint', {
            fg = '#abe9b3',
          })
          vim.api.nvim_set_hl(0, 'DapLogPoint', {
            fg = '#89dceb',
          })
          vim.api.nvim_set_hl(0, 'DapStopped', {
            fg = '#f38ba8',
          })
          vim.api.nvim_set_hl(0, 'DapBreakpointRejected', {
            fg = '#fdfd96',
          })
        end)
      end

      return M
    end,
    config = function(_, opts)
      vim.fn.sign_define('DapBreakpoint', { text = '󰙧', numhl = 'DapBreakpoint', texthl = 'DapBreakpoint' })
      vim.fn.sign_define('DagLogPoint', { text = '', numhl = 'DapLogPoint', texthl = 'DapLogPoint' })
      vim.fn.sign_define('DapStopped', { text = '', numhl = 'DapStopped', texthl = 'DapStopped' })
      vim.fn.sign_define(
        'DapBreakpointRejected',
        { text = '', numhl = 'DapBreakpointRejected', texthl = 'DapBreakpointRejected' }
      )
      local dap_config = opts
      dap_config.setup_colors()
      dap_config.setup_adapters()
      dap_config.setup_configurations()
    end,
  },
  {
    'theHamsta/nvim-dap-virtual-text',
    dependencies = { 'mfussenegger/nvim-dap', 'nvim-treesitter/nvim-treesitter' },
    event = 'LspAttach',
    config = function()
      require('nvim-dap-virtual-text').setup({
        enabled = true, -- enable this plugin (the default)
        enabled_commands = true, -- create commands DapVirtualTextEnable, DapVirtualTextDisable, DapVirtualTextToggle, (DapVirtualTextForceRefresh for refreshing when debug adapter did not notify its termination)
        highlight_changed_variables = true, -- highlight changed values with NvimDapVirtualTextChanged, else always NvimDapVirtualText
        highlight_new_as_changed = false, -- highlight new variables in the same way as changed variables (if highlight_changed_variables)
        show_stop_reason = true, -- show stop reason when stopped for exceptions
        commented = false, -- prefix virtual text with comment string
        only_first_definition = false, -- only show virtual text at first definition (if there are multiple)
        all_references = false, -- show virtual text on all all references of the variable (not only definitions)
        clear_on_continue = false, -- clear virtual text on "continue" (might cause flickering when stepping)
        --- A callback that determines how a variable is displayed or whether it should be omitted
        --- @param variable Variable https://microsoft.github.io/debug-adapter-protocol/specification#Types_Variable
        --- @param buf number
        --- @param stackframe dap.StackFrame https://microsoft.github.io/debug-adapter-protocol/specification#Types_StackFrame
        --- @param node userdata tree-sitter node identified as variable definition of reference (see `:h tsnode`)
        --- @param options nvim_dap_virtual_text_options Current options for nvim-dap-virtual-text
        --- @return string|nil A text how the virtual text should be displayed or nil, if this variable shouldn't be displayed
        display_callback = function(variable, buf, stackframe, node, options)
          -- by default, strip out new line characters
          if options.virt_text_pos == 'inline' then
            return ' = ' .. variable.value:gsub('%s+', ' ')
          else
            return variable.name .. ' = ' .. variable.value:gsub('%s+', ' ')
          end
        end,
        -- position of virtual text, see `:h nvim_buf_set_extmark()`, default tries to inline the virtual text. Use 'eol' to set to end of line
        virt_text_pos = 'inline',

        -- experimental features:
        all_frames = false, -- show virtual text for all stack frames not only current. Only works for debugpy on my machine.
        virt_lines = false, -- show virtual lines instead of virtual text (will flicker!)
        virt_text_win_col = nil, -- position the virtual text at a fixed window column (starting from the first text column) ,
        -- e.g. 80 to position at column 80, see `:h nvim_buf_set_extmark()`
      })
    end,
  },
  {
    'igorlfs/nvim-dap-view',
    ---@module 'dap-view'
    ---@type dapview.Config
    keys = {
      {
        '<leader>dv',
        '<CMD>DapViewToggle<CR>',
        desc = 'Debug Toggle UI',
      },
    },
    opts = {
      winbar = {
        default_section = 'repl',
      },
    },
  },
  {
    'LiadOz/nvim-dap-repl-highlights',
    event = 'LspAttach',
    config = function()
      require('nvim-dap-repl-highlights').setup()
      vim.api.nvim_create_user_command('DapReplHighlightsSetup', function()
        require('nvim-dap-repl-highlights').setup_highlights()
      end, {})
    end,
  },
}
