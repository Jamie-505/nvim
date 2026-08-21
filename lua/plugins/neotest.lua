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
  -- commit = '52fca6717ef972113ddd6ca223e30ad0abb2800c',
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
      '<leader>To',
      function()
        require('neotest').output.open({ enter = true, auto_close = true })
      end,
      desc = 'Test Output for nearest',
    },
    {
      '<leader>TO',
      function()
        require('neotest').output_panel.toggle()
      end,
      desc = 'Test Toggle output panel',
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
    -- neotest-gradle only recognises `*Test.kt` / `*Test.java`, while the kotlin
    -- koans name their test files `tests.kt`. it also resolves the gradle project
    -- dir by walking up to `build.gradle`, which in koans is the repo root, so a
    -- run fans out over all ~60 modules. settings.gradle there registers every
    -- folder holding a `src` dir as its own module, so resolve to that instead.
    -- both hooks are plain modules the adapter requires, swap them before load.
    local gradle_root = require('neotest.lib').files.match_root_pattern('build.gradle', 'build.gradle.kts')

    package.loaded['neotest-gradle.hooks.find_project_directory'] = function(path)
      local root = gradle_root(path)
      if not root then
        return nil
      end
      local dir = vim.fn.isdirectory(path) == 1 and path or vim.fs.dirname(path)
      while dir and #dir >= #root do
        if vim.fn.isdirectory(dir .. '/src') == 1 then
          return dir
        end
        if dir == root then
          break
        end
        dir = vim.fs.dirname(dir)
      end
      return root
    end

    package.loaded['neotest-gradle.hooks.is_test_file'] = function(path)
      local name = vim.fs.basename(path)
      if not name:match('%.kt$') and not name:match('%.java$') then
        return false
      end
      return name:match('^[Tt]est') ~= nil
    end

    -- junit4 koans annotate with `@Test(timeout = 1000)`, which parses as
    -- `annotation -> constructor_invocation`. the shipped query only matches a
    -- bare `annotation -> user_type`, so no test positions were discovered.
    package.loaded['neotest-gradle.position_queries.kotlin'] = require('neotest-gradle.position_queries.kotlin')
      .. [[
    (
      (function_declaration
        (modifiers
          (annotation (constructor_invocation (user_type (type_identifier) @test_marker.identifier)))
        )
        (simple_identifier) @test.name
      )
      (#eq? @test_marker.identifier "Test")
    ) @test.definition
  ]]

    -- position ids are built as `<package>.<class>.<test>`, so a file without a
    -- package declaration (every koan) yields a leading dot that never matches
    -- the `classname.name` the junit xml reports back, and lands in the gradle
    -- `--tests` filter as `.TestStart`
    local build_identifier = require('neotest-gradle.hooks.discover_positions.build_position_identifier')
    local function position_id(position, parents)
      return (build_identifier(position, parents):gsub('^%.', ''))
    end

    -- discovery normally runs in neotest's `-u NONE` child process, which never
    -- sees the patches above. passing the hooks as functions instead of the
    -- adapter's `require(...)` strings makes neotest parse in this process.
    local gradle = require('neotest-gradle')
    local position_queries = require('neotest-gradle.position_queries')
    local build_position = require('neotest-gradle.hooks.discover_positions.build_position')

    gradle.discover_positions = function(path)
      local query = position_queries[require('plenary.filetype').detect(path)]
      if not query then
        return nil
      end
      -- `_parse_positions` is the in-process path; the public one would hand the
      -- job to the child, notice the function hooks and fall back with a warning
      return require('neotest.lib').treesitter._parse_positions(path, query, {
        build_position = build_position,
        position_id = position_id,
      })
    end

    -- the adapter concatenates its argv into a single shell string, so a koan
    -- folder like `Default arguments` splits into two shell words and gradle
    -- runs in the wrong dir. re-quote the executable and the project dir.
    local build_spec = gradle.build_spec
    gradle.build_spec = function(args)
      local spec = build_spec(args)
      if spec and spec.command then
        local dir = require('neotest-gradle.hooks.find_project_directory')(args.tree:data().path)
        spec.command = (spec.command:gsub('^(.-)%s+%-%-project%-dir%s+' .. vim.pesc(dir or ''), function(executable)
          return vim.fn.shellescape(executable) .. ' --project-dir ' .. vim.fn.shellescape(dir) .. ' '
        end))
      end
      return spec
    end

    -- when gradle fails before writing any junit report the adapter asserts on
    -- the missing directory and throws a traceback over the run. the output
    -- panel already carries the real error, so just report no results.
    local results = gradle.results
    gradle.results = function(spec, run_result, tree)
      local directory = (spec.context or {}).test_resuls_directory
      if not directory or vim.fn.isdirectory(directory) == 0 then
        return {}
      end
      return results(spec, run_result, tree)
    end

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
          additional_args = { '--no-pub' },
        }),
        gradle,
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
