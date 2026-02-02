return {
  'nvim-neotest/neotest',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-neotest/nvim-nio',
    'antoinemadec/FixCursorHold.nvim',
    'nvim-treesitter/nvim-treesitter',
    -- Language specifics
    'NorinB/neotest-dart',
    'nvim-neotest/neotest-jest',
    'weilbith/neotest-gradle',
  },
  commit = '52fca6717ef972113ddd6ca223e30ad0abb2800c',
  cmd = 'Neotest summary',
  event = { 'BufEnter *spec*', 'BufEnter *test*' },
  keys = {
    {
      '<leader>Td',
      function()
        require('neotest').run.run({ strategy = 'dap' })
      end,
      desc = 'Test Debug nearest',
    },
    {
      '<leader>TD',
      function()
        require('neotest').run.run({ vim.fn.expand('%'), strategy = 'dap' })
      end,
      desc = 'Test Debug file',
    },
    {
      '<leader>Tr',
      function()
        require('neotest').run.run()
      end,
      desc = 'Test Run nearest',
    },
    {
      '<leader>TR',
      function()
        require('neotest').run.run(vim.fn.expand('%'))
      end,
      desc = 'Test Run file',
    },
    {
      '<leader>TS',
      function()
        require('neotest').summary.toggle()
      end,
      desc = 'Test Toggle summary',
    },
    {
      '<leader>Tl',
      function()
        require('neotest').run.run_last()
      end,
      desc = 'Test Run last',
    },
    {
      '<leader>TL',
      function()
        require('neotest').run.run_last({ strategy = 'dap' })
      end,
      desc = 'Test Debug last',
    },
    {
      '<leader>Ts',
      function()
        require('neotest').run.stop()
      end,
      desc = 'Test Stop',
    },
  },
  opts = function()
    return {
      adapters = {
        require('neotest-dart')({
          -- change it to `dart` for Dart only tests
          -- Command being used to run tests. Defaults to `flutter`
          command = 'flutter',
          -- When set Flutter outline information is used when constructing test name.
          use_lsp = true,
          -- Useful when using custom test names with @isTest annotation
          custom_test_method_names = { 'blocTest' },
          -- don't fetch packages
          additional_args = { "--no-pub" },
        }),
        require('neotest-gradle'),
        require('neotest-jest')({
          jestCommand = 'npm test --',
          jestConfigFile = function(file)
            if string.find(file, '/packages/') then
              return string.match(file, '(.-/[^/]+/)src') .. 'jest.config.ts'
            end

            if string.find(file, 'e2e-spec', 1, true) then
              local fs = vim.fs
              local path = fs.dirname(fs.find({ 'jest-e2e.json' }, {
                path = file,
                upward = true,
              })[1]) .. '/jest-e2e.json'
              return path
            end

            return vim.fn.getcwd() .. '/jest.config.ts'
          end,
          env = { CI = true },
          cwd = function(path)
            return vim.fn.getcwd()
          end,
        }),
      },
    }
  end,
}
