-- return {
--   {
--     'NickvanDyke/opencode.nvim',
--     dependencies = {
--       'folke/snacks.nvim',
--     },
--     keys = {
--       {
--         '<leader>oa',
--         function()
--           require('opencode').ask('@this: ', { submit = true })
--         end,
--         mode = { 'n', 'x' },
--         desc = 'Opencode Ask',
--       },
--       {
--         '<leader>ox',
--         function()
--           require('opencode').select()
--         end,
--         mode = { 'n', 'x' },
--         desc = 'Opencode Execute action',
--       },
--       {
--         '<leader>to',
--         function()
--           require('opencode').toggle()
--         end,
--         mode = { 'n', 't' },
--         desc = 'Toggle Opencode',
--       },
--       {
--         '<leader>or',
--         function()
--           return require('opencode').operator('@this ')
--         end,
--         mode = { 'n', 'x' },
--         desc = 'Opencode Add range',
--         expr = true,
--       },
--       {
--         '<leader>ol',
--         function()
--           return require('opencode').operator('@this ') .. '_'
--         end,
--         desc = 'Opencode Add line',
--         expr = true,
--       },
--       {
--         '<S-C-u>',
--         function()
--           require('opencode').command('session.half.page.up')
--         end,
--         desc = 'Opencode Scroll up',
--       },
--       {
--         '<S-C-d>',
--         function()
--           require('opencode').command('session.half.page.down')
--         end,
--         desc = 'Opencode Scroll down',
--       },
--       {
--         '<leader>fO',
--         function()
--           local pickers = require('telescope.pickers')
--           local finders = require('telescope.finders')
--           local actions = require('telescope.actions')
--           local actions_state = require('telescope.actions.state')
--           local entry_display = require('telescope.pickers.entry_display')
--           local conf = require('telescope.config').values
--
--           local displayer = entry_display.create({
--             separator = '- ',
--             items = {
--               { width = 15 },
--               { remaining = true },
--             },
--           })
--
--           pickers
--             .new({}, {
--               prompt_title = 'Select Context:',
--               finder = finders.new_table({
--                 results = {
--                   { idx = 1, text = '@this', desc = 'current selection' },
--                   { idx = 2, text = '@buffer', desc = 'current buffer' },
--                   { idx = 3, text = '@buffers', desc = 'all open buffers' },
--                   { idx = 4, text = '@visible', desc = 'visible buffers' },
--                   { idx = 5, text = '@diagnostics', desc = 'diagnostics' },
--                   { idx = 6, text = '@quickfix', desc = 'quickfix list' },
--                   { idx = 7, text = '@diff', desc = 'git diff' },
--                   { idx = 8, text = '@marks', desc = 'marks' },
--                   { idx = 9, text = 'no context', desc = 'no specific context' },
--                 },
--                 entry_maker = function(e)
--                   return {
--                     value = e,
--                     display = function()
--                       return displayer({
--                         { e.text, 'TelescopeResultsIdentifier' },
--                         { e.desc, 'TelescopeResultsComment' },
--                       })
--                     end,
--                     ordinal = e.text,
--                   }
--                 end,
--               }),
--               attach_mappings = function(prompt_buffer)
--                 actions.select_default:replace(function()
--                   local selection = actions_state.get_selected_entry()
--                   actions.close(prompt_buffer)
--                   if string.match(selection.value.text, 'no context') ~= nil then
--                     require('opencode').ask('', { submit = true })
--                   else
--                     require('opencode').ask(selection.value.text .. ': ', { submit = true })
--                   end
--                 end)
--                 return true
--               end,
--               sorter = conf.generic_sorter({}),
--               layout_config = { height = 14, width = 50 },
--               get_status_text = function()
--                 return ''
--               end,
--             })
--             :find()
--         end,
--         mode = { 'n', 'x' },
--         desc = 'Opencode pick context',
--       },
--     },
--     config = function()
--       local pane_id
--
--       local function get_pane_id()
--         if not pane_id then
--           return nil
--         end
--
--         local result = vim.fn.system('wezterm cli list --format json 2>&1')
--         if result == nil or result == '' or result:match('error') then
--           pane_id = nil
--           return nil
--         end
--
--         local ok, panes = pcall(vim.json.decode, result)
--         if not ok or type(panes) ~= 'table' then
--           pane_id = nil
--           return nil
--         end
--
--         for _, pane in ipairs(panes) do
--           if tostring(pane.pane_id) == tostring(pane_id) then
--             return pane_id
--           end
--         end
--
--         pane_id = nil
--         return nil
--       end
--
--       local function start_server()
--         if get_pane_id() then
--           return
--         end
--
--         local cmd = {
--           'wezterm',
--           'cli',
--           'split-pane',
--           '--left',
--           '--percent',
--           '25',
--           '--',
--           'opencode --port',
--         }
--
--         local result = vim.fn.system(table.concat(cmd, ' '))
--         vim.fn.system('wezterm cli activate-pane --pane-id ' .. vim.env.WEZTERM_PANE)
--         pane_id = result:match('^%d+')
--       end
--
--       local function stop_server()
--         local id = get_pane_id()
--         if not id then
--           return
--         end
--
--         vim.fn.system('wezterm cli kill-pane --pane-id ' .. id)
--         pane_id = nil
--       end
--
--       local function toggle_server()
--         if get_pane_id() then
--           stop_server()
--         else
--           start_server()
--         end
--       end
--
--       vim.g.opencode_opts = {
--         server = {
--           start = start_server,
--           stop = stop_server,
--           toggle = toggle_server,
--         },
--       }
--       vim.o.autoread = true
--     end,
--   },
-- }
return {
  {
    'NickvanDyke/opencode.nvim',
    dependencies = {
      'folke/snacks.nvim',
    },
    keys = {
      {
        '<leader>oa',
        function()
          require('opencode').ask('@this: ', { submit = true })
        end,
        mode = { 'n', 'x' },
        desc = 'Opencode Ask',
      },
      {
        '<leader>ox',
        function()
          require('opencode').select()
        end,
        mode = { 'n', 'x' },
        desc = 'Opencode Execute action',
      },
      {
        '<leader>to',
        function()
          require('opencode').toggle()
        end,
        mode = 'n',
        desc = 'Toggle Opencode',
      },
      {
        '<leader>or',
        function()
          return require('opencode').operator('@this ')
        end,
        mode = { 'n', 'x' },
        desc = 'Opencode Add range',
        expr = true,
      },
      {
        '<leader>ol',
        function()
          return require('opencode').operator('@this ') .. '_'
        end,
        desc = 'Opencode Add line',
        expr = true,
      },
      {
        '<S-C-u>',
        function()
          require('opencode').command('session.half.page.up')
        end,
        desc = 'Opencode Scroll up',
      },
      {
        '<S-C-d>',
        function()
          require('opencode').command('session.half.page.down')
        end,
        desc = 'Opencode Scroll down',
      },
      {
        '<leader>fO',
        function()
          local pickers = require('telescope.pickers')
          local finders = require('telescope.finders')
          local actions = require('telescope.actions')
          local actions_state = require('telescope.actions.state')
          local entry_display = require('telescope.pickers.entry_display')
          local conf = require('telescope.config').values

          local displayer = entry_display.create({
            separator = '- ',
            items = {
              { width = 15 },
              { remaining = true },
            },
          })

          pickers
            .new({}, {
              prompt_title = 'Select Context:',
              finder = finders.new_table({
                results = {
                  { idx = 1, text = '@this', desc = 'current selection' },
                  { idx = 2, text = '@buffer', desc = 'current buffer' },
                  { idx = 3, text = '@buffers', desc = 'all open buffers' },
                  { idx = 4, text = '@visible', desc = 'visible buffers' },
                  { idx = 5, text = '@diagnostics', desc = 'diagnostics' },
                  { idx = 6, text = '@quickfix', desc = 'quickfix list' },
                  { idx = 7, text = '@diff', desc = 'git diff' },
                  { idx = 8, text = '@marks', desc = 'marks' },
                  { idx = 9, text = 'no context', desc = 'no specific context' },
                },
                entry_maker = function(e)
                  return {
                    value = e,
                    display = function()
                      return displayer({
                        { e.text, 'TelescopeResultsIdentifier' },
                        { e.desc, 'TelescopeResultsComment' },
                      })
                    end,
                    ordinal = e.text,
                  }
                end,
              }),
              attach_mappings = function(prompt_buffer)
                actions.select_default:replace(function()
                  local selection = actions_state.get_selected_entry()
                  actions.close(prompt_buffer)
                  if string.match(selection.value.text, 'no context') ~= nil then
                    require('opencode').ask('', { submit = true })
                  else
                    require('opencode').ask(selection.value.text .. ': ', { submit = true })
                  end
                end)
                return true
              end,
              sorter = conf.generic_sorter({}),
              layout_config = { height = 14, width = 50 },
              get_status_text = function()
                return ''
              end,
            })
            :find()
        end,
        mode = { 'n', 'x' },
        desc = 'Opencode Pick context',
      },
    },
    config = function()
      local tmux_split_opts = { '-h', '-b', '-l', '30%' }

      local function notify(msg, level)
        vim.notify(msg, level or vim.log.levels.INFO, { title = 'opencode.nvim' })
      end

      local function run_tmux(args)
        if not vim.env.TMUX or vim.env.TMUX == '' then
          return nil, 'Not running inside tmux ($TMUX is empty)'
        end

        local cmd = vim.list_extend({ 'tmux' }, args)
        local res = vim.system(cmd, { text = true }):wait()

        if res.code ~= 0 then
          local err = (res.stderr and res.stderr ~= '') and res.stderr or ('tmux exit code ' .. res.code)
          return nil, vim.trim(err)
        end

        return vim.trim(res.stdout or ''), nil
      end

      local function pane_exists(pane_id)
        if not pane_id or pane_id == '' then
          return false
        end
        local out, err = run_tmux({ 'display-message', '-p', '-t', pane_id, '#{pane_id}' })
        return out ~= nil and not err and out == pane_id
      end

      local function current_cwd()
        local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ':p')
        return (cwd:gsub('/$', ''))
      end

      local function start_command_for_cwd(cwd)
        return 'cd ' .. vim.fn.shellescape(cwd) .. ' && opencode --port'
      end

      local function current_pane_id()
        local out = run_tmux({ 'display-message', '-p', '#{pane_id}' })
        return out
      end

      local function pane_window_id(pane_id)
        local out = run_tmux({ 'display-message', '-p', '-t', pane_id, '#{window_id}' })
        return out
      end

      local function reset_window_rename(window_id)
        if not window_id or window_id == '' then
          return
        end

        local _, auto_err = run_tmux({ 'set-window-option', '-t', window_id, 'automatic-rename', 'on' })
        if auto_err then
          notify('Could not re-enable tmux automatic-rename: ' .. auto_err, vim.log.levels.ERROR)
          return
        end

        -- local _, rename_err = run_tmux { "rename-window", "-u", "-t", window_id }
        -- if rename_err then
        --   notify("Could not reset tmux window name: " .. rename_err, vim.log.levels.ERROR)
        --   return
        -- end

        run_tmux({ 'refresh-client', '-S' })
      end

      local function reset_current_window_rename()
        local pane_id = current_pane_id()
        if not pane_id then
          return
        end
        reset_window_rename(pane_window_id(pane_id))
      end

      local function pane_in_current_window(pane_id)
        local current = current_pane_id()
        if not current then
          return false
        end

        local current_win = pane_window_id(current)
        local target_win = pane_window_id(pane_id)
        return current_win ~= nil and current_win == target_win
      end

      local function find_opencode_pane(cwd)
        local out, err = run_tmux({
          'list-panes',
          '-a',
          '-F',
          '#{pane_id}\t#{pane_start_command}',
        })
        if not out then
          return nil, err
        end

        local wanted = start_command_for_cwd(cwd)
        for line in out:gmatch('[^\n]+') do
          local pane_id, start_cmd = line:match('([^\t]+)\t(.*)')
          if pane_id and start_cmd and start_cmd:find(wanted, 1, true) then
            return pane_id, nil
          end
        end

        return nil, nil
      end

      local state = { panes_by_cwd = {} }

      local function pane_for_cwd(cwd)
        local pane_id = state.panes_by_cwd[cwd]
        if pane_exists(pane_id) then
          return pane_id
        end

        pane_id = find_opencode_pane(cwd)
        state.panes_by_cwd[cwd] = pane_id
        return pane_id
      end

      local function start_server()
        local cwd = current_cwd()
        local existing = pane_for_cwd(cwd)
        if existing then
          return
        end

        local args = vim.list_extend({
          'split-window',
          '-d',
          '-P',
          '-F',
          '#{pane_id}',
        }, tmux_split_opts)

        table.insert(args, start_command_for_cwd(cwd))

        local pane_id, err = run_tmux(args)
        if not pane_id then
          notify('Could not start opencode tmux pane: ' .. err, vim.log.levels.ERROR)
          return
        end

        state.panes_by_cwd[cwd] = pane_id
      end

      local function stop_server()
        local cwd = current_cwd()
        local pane_id = pane_for_cwd(cwd)

        if not pane_id then
          state.panes_by_cwd[cwd] = nil
          return
        end

        local _, err = run_tmux({ 'kill-pane', '-t', pane_id })
        if err then
          notify('Could not stop opencode tmux pane: ' .. err, vim.log.levels.ERROR)
          return
        end

        state.panes_by_cwd[cwd] = nil
      end

      local function toggle_server()
        local cwd = current_cwd()
        local pane_id = pane_for_cwd(cwd)

        if not pane_id then
          start_server()
          return
        end

        if pane_in_current_window(pane_id) then
          local current = current_pane_id()
          local current_window = current and pane_window_id(current) or nil
          local _, err = run_tmux({ 'break-pane', '-d', '-s', pane_id, '-n', 'opencode-hidden' })
          if err then
            notify('Could not hide opencode tmux pane: ' .. err, vim.log.levels.ERROR)
            return
          end

          reset_window_rename(current_window)
          return
        end

        local target = current_pane_id()
        if not target then
          notify('Could not determine current tmux pane', vim.log.levels.ERROR)
          return
        end

        local join_opts = {}
        for _, opt in ipairs(tmux_split_opts) do
          table.insert(join_opts, opt)
        end

        local join_args = vim.list_extend({
          'join-pane',
          '-d',
        }, join_opts)

        vim.list_extend(join_args, {
          '-s',
          pane_id,
          '-t',
          target,
        })

        local _, err = run_tmux(join_args)
        if err then
          notify('Could not show opencode tmux pane: ' .. err, vim.log.levels.ERROR)
          return
        end

        reset_current_window_rename()
      end

      vim.g.opencode_opts = {
        server = {
          start = start_server,
          stop = stop_server,
          toggle = toggle_server,
        },
      }

      vim.api.nvim_create_autocmd('VimLeavePre', {
        callback = function()
          reset_current_window_rename()
          for cwd, pane_id in pairs(state.panes_by_cwd) do
            if pane_exists(pane_id) then
              run_tmux({ 'kill-pane', '-t', pane_id })
            end
            state.panes_by_cwd[cwd] = nil
          end
        end,
      })

      vim.o.autoread = true
    end,
  },
}
