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
  cmd = 'Neotest',
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

    -- upstream only matches the `FooTest.kt` suffix convention, which the koans
    -- (`tests.kt`) never hit. match both rather than replacing one with the other.
    package.loaded['neotest-gradle.hooks.is_test_file'] = function(path)
      local name = vim.fs.basename(path)
      if not name:match('%.kt$') and not name:match('%.java$') then
        return false
      end
      return name:match('^[Tt]est') ~= nil or name:match('Test%.kt$') ~= nil or name:match('Test%.java$') ~= nil
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

    -- neotest keys adapters as `<name>:<root>`, so `root` has to answer the same
    -- for the cwd and for any file under it. `find_project_directory` above is
    -- deliberately per-module (it is what `--project-dir` wants), so using it as
    -- `root` registered a second adapter instance and every test showed twice.
    -- the reactor root is the stable answer; fall back for single-module repos.
    local reactor_root = require('neotest.lib').files.match_root_pattern('settings.gradle', 'settings.gradle.kts')
    gradle.root = function(path)
      return reactor_root(path) or gradle_root(path)
    end
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

    local ui = require('neotest.lib.ui')
    local open_buf = ui.open_buf
    ui.open_buf = function(bufnr, line, column)
      local has_editable_window = false
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_config(win).relative == '' and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == '' then
          has_editable_window = true
          break
        end
      end
      -- every window is a sidebar/summary/console, so make somewhere to land.
      -- `vnew`, not `vsplit`: a split would just clone the special buffer.
      if not has_editable_window then
        vim.cmd('topleft vnew')
      end
      return open_buf(bufnr, line, column)
    end

    -- the adapter concatenates its argv into a single shell string, so a koan
    -- folder like `Default arguments` splits into two shell words and gradle
    -- runs in the wrong dir. re-quote the executable and the project dir.
    -- the adapter hardcodes the `test` task, so a custom source set never runs:
    -- its classes aren't on `test`'s testClassesDirs, the `--tests` filter matches
    -- nothing, and the reports land under a different directory. gradle names the
    -- Test task after the source set, which is the path segment after `src/`.
    local function gradle_test_task(path)
      return path:match('/src/([^/]+)/') or 'test'
    end

    local build_spec = gradle.build_spec
    gradle.build_spec = function(args)
      local spec = build_spec(args)
      local path = args.tree:data().path
      local dir = require('neotest-gradle.hooks.find_project_directory')(path)
      local task = gradle_test_task(path)
      if spec and spec.command and dir then
        spec.command = (
          spec.command:gsub('^(.-)%s+%-%-project%-dir%s+' .. vim.pesc(dir) .. '%s+test', function(executable)
            return vim.fn.shellescape(executable) .. ' --project-dir ' .. vim.fn.shellescape(dir) .. ' ' .. task
          end)
        )
      end
      -- gradle 9 dropped the `testResultsDir` project property, so the adapter's
      -- `properties --property testResultsDir` prints "null" and it builds the
      -- path "null/test". resolve the task's real report directory instead.
      if spec and dir then
        spec.context = spec.context or {}
        local expected = vim.fs.joinpath(dir, 'build', 'test-results', task)
        local reported = spec.context.test_resuls_directory
        if vim.fn.isdirectory(expected) == 1 or not reported or reported == '' or vim.fn.isdirectory(reported) == 0 then
          spec.context.test_resuls_directory = expected
        end
      end
      return spec
    end

    -- when gradle fails before writing any junit report the adapter asserts on
    -- the missing directory and throws a traceback over the run. the output
    -- panel already carries the real error, so just report no results.
    local collect_results = gradle.results
    gradle.results = function(spec, run_result, tree)
      local directory = (spec.context or {}).test_resuls_directory
      if not directory or vim.fn.isdirectory(directory) == 0 then
        -- returning `{}` would leave the positions in `running` forever, so the
        -- summary just spins. mark them failed and point at the output panel.
        local failed = {}
        for _, position in tree:iter() do
          if position.type == 'test' or position.type == 'namespace' then
            failed[position.id] = {
              status = 'failed',
              short = 'no junit reports at ' .. tostring(directory) .. ' - see the output panel',
            }
          end
        end
        return failed
      end
      return collect_results(spec, run_result, tree)
    end

    return {
      floating = { border = 'rounded' },
      -- koans.nvim's panel, repainted whenever a run finishes. Neotest only
      -- registers consumers here, and koans is `cond`-gated on being inside a
      -- course, so this is the inlined form of `neotest_consumer()` rather than
      -- a call to it. See |koans-neotest|.
      consumers = {
        koan = function(client)
          client.listeners.results = function()
            -- the listener runs inside an nio task
            vim.schedule(function()
              local ok, progress = pcall(require, 'koans.progress')
              if ok then
                progress.invalidate()
              end
            end)
          end
        end,
      },
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
            local default = vim.fn.getcwd() .. '/jest.config.ts'

            if string.find(file, '/packages/') then
              local pkg_root = string.match(file, '(.-/[^/]+/)src')
              return pkg_root and pkg_root .. 'jest.config.ts' or default
            end

            if string.find(file, 'e2e-spec', 1, true) then
              local found = vim.fs.find({ 'jest-e2e.json' }, {
                path = file,
                upward = true,
              })[1]
              if found then
                return found
              end
            end

            return default
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
