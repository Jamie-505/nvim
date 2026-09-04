return {
  'oclay1st/gradle.nvim',
  cmd = { 'Gradle', 'GradleExec', 'GradleInit', 'GradleFavorites' },
  dependencies = {
    'MunifTanjim/nui.nvim',
  },
  -- the plugin has no wrapper support and defaults to a system `gradle`, which
  -- isn't installed here. every project ships a `gradlew` to pin its own gradle
  -- version, so resolve that instead and fall back to `gradle` when absent.
  opts = function()
    return { gradle_executable = require('utils').gradle_executable() }
  end,
  config = function(_, opts)
    require('gradle').setup(opts)

    -- the console picks `winnr('#')` and force-swaps its buffer in. neotest's
    -- summary sets `winfixbuf`, so whenever it was the previous window the whole
    -- run died with E1513 before gradle was ever spawned (and left a half-built
    -- console buffer behind, which then failed again with E95 on the next try).
    -- make sure the previous window is one that will actually accept a buffer.
    local console = require('gradle.utils.console')
    local execute_command = console.execute_command
    local function accepts_a_buffer(win)
      if win == 0 or not vim.api.nvim_win_is_valid(win) then
        return false
      end
      if vim.api.nvim_win_get_config(win).relative ~= '' then
        return false
      end
      local ok, fixed = pcall(vim.api.nvim_get_option_value, 'winfixbuf', { win = win })
      return not (ok and fixed)
    end
    console.execute_command = function(...)
      local current = vim.api.nvim_get_current_win()
      if not accepts_a_buffer(vim.fn.win_getid(vim.fn.winnr('#'))) then
        local target
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          if win ~= current and accepts_a_buffer(win) then
            target = win
            break
          end
        end
        if not target then
          vim.cmd('botright new')
          target = vim.api.nvim_get_current_win()
        end
        -- visiting it and coming back makes it the previous window
        vim.api.nvim_set_current_win(target)
        if vim.api.nvim_win_is_valid(current) then
          vim.api.nvim_set_current_win(current)
        end
      end
      return execute_command(...)
    end
    -- all call sites read `options.gradle_executable` at call time, so re-point
    -- it when the cwd moves to another project
    vim.api.nvim_create_autocmd('DirChanged', {
      group = vim.api.nvim_create_augroup('GradleWrapper', {}),
      callback = function()
        require('gradle.config').options.gradle_executable = require('utils').gradle_executable()
      end,
    })
  end,
  keys = {
    { '<leader>G', desc = '+Git/Gradle', mode = { 'n', 'x' } },
    { '<leader>Gp', '<cmd>Gradle<cr>', desc = 'Gradle Projects' },
    { '<leader>GF', '<cmd>GradleFavorites<cr>', desc = 'Gradle Favorite Commands' },
  },
}
