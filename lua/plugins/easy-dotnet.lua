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
        dotnet.run_profile()
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
      ---@type easy-dotnet.TestRunner.Options
      test_runner = {
        ---@type "split" | "vsplit" | "float" | "buf"
        viewmode = 'float',
        ---@type number|nil
        vsplit_width = nil,
        ---@type string|nil
        vsplit_pos = nil,
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
          debug_test = { lhs = '<leader>d', desc = 'debug test' },
          go_to_file = { lhs = 'g', desc = 'go to file' },
          run_all = { lhs = '<leader>R', desc = 'run all tests' },
          run = { lhs = '<leader>r', desc = 'run test' },
          peek_stacktrace = { lhs = '<leader>p', desc = 'peek stacktrace of failed test' },
          expand = { lhs = 'o', desc = 'expand' },
          expand_node = { lhs = 'E', desc = 'expand node' },
          collapse_all = { lhs = 'W', desc = 'collapse all' },
          close = { lhs = 'q', desc = 'close testrunner' },
          refresh_testrunner = { lhs = '<C-r>', desc = 'refresh testrunner' },
        },
      },
      new = {
        project = {
          prefix = 'sln',
        },
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
      notifications = {
        handler = function(start_event)
          local spinner = require('easy-dotnet.ui-modules.spinner').new()
          spinner:start_spinner(function()
            return start_event.job.name
          end)
          ---@param finished_event easy-dotnet.Job.Event
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
