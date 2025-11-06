return {
  'GustavEikaas/easy-dotnet.nvim',
  dependencies = { 'nvim-lua/plenary.nvim', 'nvim-telescope/telescope.nvim' },
  ft = 'cs',
  keys = {
    {
      '<leader>Dr',
      function()
        local dotnet = require('easy-dotnet')
        dotnet.run()
      end,
      desc = 'Dotnet Run',
    },
    {
      '<leader>DR',
      function()
        local dotnet = require('easy-dotnet')
        dotnet.run_with_profile()
      end,
      desc = 'Dotnet Run with profile',
    },
    {
      '<leader>Dw',
      function()
        local dotnet = require('easy-dotnet')
        dotnet.watch()
      end,
      desc = 'Dotnet Watch',
    },
  },
  config = function()
    local function get_secret_path(secret_guid)
      local path = ''
      local home_dir = vim.fn.expand('~')
      if require('easy-dotnet.extensions').isWindows() then
        local secret_path = home_dir
          .. '\\AppData\\Roaming\\Microsoft\\UserSecrets\\'
          .. secret_guid
          .. '\\secrets.json'
        path = secret_path
      else
        local secret_path = home_dir .. '/.microsoft/usersecrets/' .. secret_guid .. '/secrets.json'
        path = secret_path
      end
      return path
    end

    local dotnet = require('easy-dotnet')
    dotnet.setup({
      lsp = {
        enabled = true,
        roslynator_enabled = true,
        analyzer_assemblies = {},
        config = {},
      },
      debugger = {
        bin_path = 'netcoredbg',
        auto_register_dap = true,
        mappings = {
          open_variable_viewer = { lhs = 'T', desc = 'open variable viewer' },
        },
      },
      ---@type TestRunnerOptions
      test_runner = {
        ---@type "split" | "vsplit" | "float" | "buf"
        viewmode = 'float',
        ---@type number|nil
        vsplit_width = nil,
        ---@type string|nil
        vsplit_pos = nil,
        enable_buffer_test_execution = true,
        noBuild = true,
        icons = {
          passed = '',
          skipped = '',
          failed = '',
          success = '',
          reload = '',
          test = '',
          sln = '󰘐',
          project = '󰘐',
          dir = '',
          package = '',
        },
        mappings = {
          run_test_from_buffer = { lhs = '<leader>r', desc = 'run test from buffer' },
          peek_stack_trace_from_buffer = { lhs = '<leader>p', desc = 'peek stack trace from buffer' },
          filter_failed_tests = { lhs = '<leader>fe', desc = 'filter failed tests' },
          debug_test = { lhs = '<leader>d', desc = 'debug test' },
          go_to_file = { lhs = 'g', desc = 'go to file' },
          run_all = { lhs = '<leader>R', desc = 'run all tests' },
          run = { lhs = '<leader>r', desc = 'run test' },
          peek_stacktrace = { lhs = '<leader>p', desc = 'peek stacktrace of failed test' },
          expand = { lhs = 'o', desc = 'expand' },
          expand_node = { lhs = 'E', desc = 'expand node' },
          expand_all = { lhs = '-', desc = 'expand all' },
          collapse_all = { lhs = 'W', desc = 'collapse all' },
          close = { lhs = 'q', desc = 'close testrunner' },
          refresh_testrunner = { lhs = '<C-r>', desc = 'refresh testrunner' },
        },
        additional_args = {},
      },
      new = {
        project = {
          prefix = 'sln',
        },
      },
      ---@param action "test" | "restore" | "build" | "run"
      terminal = function(path, action, args)
        args = args or ''
        local commands = {
          run = function()
            return string.format('dotnet run --project %s %s', path, args)
          end,
          test = function()
            return string.format('dotnet test %s %s', path, args)
          end,
          restore = function()
            return string.format('dotnet restore %s %s', path, args)
          end,
          build = function()
            return string.format('dotnet build %s %s', path, args)
          end,
          watch = function()
            return string.format('dotnet watch --project %s %s', path, args)
          end,
        }
        local command = commands[action]()
        if require('easy-dotnet.extensions').isWindows() == true then
          command = command .. '\r'
        end
        vim.cmd('vsplit')
        vim.cmd('term ' .. command)
      end,
      secrets = {
        path = get_secret_path,
      },
      csproj_mappings = true,
      fsproj_mappings = true,
      auto_bootstrap_namespace = {
        type = 'block_scoped',
        enabled = true,
        use_clipboard_json = {
          behavior = 'prompt',
          register = '+',
        },
      },
      server = {
        ---@type nil | "Off" | "Critical" | "Error" | "Warning" | "Information" | "Verbose" | "All"
        log_level = nil,
      },
      picker = 'telescope',
      background_scanning = true,
      notifications = {
        handler = function(start_event)
          local spinner = require('easy-dotnet.ui-modules.spinner').new()
          spinner:start_spinner(start_event.job.name)
          ---@param finished_event JobEvent
          return function(finished_event)
            spinner:stop_spinner(finished_event.result.msg, finished_event.result.level)
          end
        end,
      },
      diagnostics = {
        default_severity = 'error',
        setqflist = false,
      },
    })
    vim.api.nvim_create_user_command('DotnetSecrets', function()
      dotnet.secrets()
    end, {})
  end,
}
