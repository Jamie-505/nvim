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
  keys = function()
    local function kw()
      return require('kotlin-workflow.neotest')
    end
    local function run(target, debug)
      return function()
        local args = type(target) == 'function' and target() or target
        if debug then
          args = type(args) == 'table' and args or { args }
          args.strategy = kw().debug_strategy
        end
        require('neotest').run.run(args)
      end
    end
    local function file()
      return vim.fn.expand('%:p')
    end
    -- the Gradle module of the current file (the dir holding its `src`)
    local function module()
      return require('neotest-gradle.hooks.find_project_directory')(vim.fn.expand('%:p'))
    end
    -- the Gradle build root (settings file), i.e. every module
    local function project()
      return require('neotest-gradle').root(vim.fn.expand('%:p')) or vim.fn.getcwd()
    end
    return {
      { '<leader>Tr', run(nil), desc = 'Test Run nearest' },
      { '<leader>TR', run(file), desc = 'Test Run file' },
      { '<leader>Tm', run(module), desc = 'Test Run module' },
      { '<leader>Ta', run(project), desc = 'Test Run all (project)' },
      { '<leader>Td', run(nil, true), desc = 'Test Debug nearest' },
      { '<leader>TD', run(file, true), desc = 'Test Debug file' },
      { '<leader>TM', run(module, true), desc = 'Test Debug module' },
      { '<leader>TA', run(project, true), desc = 'Test Debug all (project)' },
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
          require('neotest').run.run_last({ strategy = kw().debug_strategy })
        end,
        desc = 'Test Debug last',
      },
      {
        '<leader>Ts',
        function()
          kw().stop()
        end,
        desc = 'Test Stop (SIGINT)',
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
    }
  end,
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
    -- positions, run specs, results and the run/debug strategy for Gradle
    -- projects live in kotlin-workflow.neotest: argv without a shell,
    -- `Outer$Inner` filters, display-name matching, `[n]` parameterized
    -- children, SIGINT on stop and debug through a fresh kotlin-lsp bridge.
    -- the junit4 koans' `@Test(timeout = 1000)` is covered by its query.
    local kw = require('kotlin-workflow.neotest')
    -- kapt writes Java stubs of every test class under build/tmp/kapt3/stubs,
    -- which would register each test twice under the same id
    -- build output holds copies of sources (kapt stubs; Eclipse-model `bin/`)
    local skip = { build = true, bin = true, out = true, ['.gradle'] = true, ['.kotlin'] = true, node_modules = true }
    gradle.filter_dir = function(name)
      return not skip[name]
    end
    gradle.discover_positions = kw.discover_positions
    gradle.build_spec = kw.build_spec
    gradle.results = kw.results

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

    return {
      floating = { border = 'rounded' },
      default_strategy = kw.run_strategy,
      -- koans.nvim's panel, repainted whenever a run finishes. Neotest only
      -- registers consumers here, and koans is `cond`-gated on being inside a
      -- course, so this is the inlined form of `neotest_consumer()` rather than
      -- a call to it. See |koans-neotest|.
      consumers = {
        kotlin_workflow = kw.consumer,
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
