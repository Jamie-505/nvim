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
        mode = { 'n', 't' },
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
        desc = 'Opencode pick context',
      },
    },
    config = function()
      local pane_id

      local function get_pane_id()
        if not pane_id then
          return nil
        end

        local result = vim.fn.system('wezterm cli list --format json 2>&1')
        if result == nil or result == '' or result:match('error') then
          pane_id = nil
          return nil
        end

        local ok, panes = pcall(vim.json.decode, result)
        if not ok or type(panes) ~= 'table' then
          pane_id = nil
          return nil
        end

        for _, pane in ipairs(panes) do
          if tostring(pane.pane_id) == tostring(pane_id) then
            return pane_id
          end
        end

        pane_id = nil
        return nil
      end

      local function start_server()
        if get_pane_id() then
          return
        end

        local cmd = {
          'wezterm',
          'cli',
          'split-pane',
          '--left',
          '--percent',
          '25',
          '--',
          'opencode',
        }

        local result = vim.fn.system(table.concat(cmd, ' '))
        vim.fn.system('wezterm cli activate-pane --pane-id ' .. vim.env.WEZTERM_PANE)
        pane_id = result:match('^%d+')
      end

      local function stop_server()
        local id = get_pane_id()
        if not id then
          return
        end

        vim.fn.system('wezterm cli kill-pane --pane-id ' .. id)
        pane_id = nil
      end

      local function toggle_server()
        if get_pane_id() then
          stop_server()
        else
          start_server()
        end
      end

      vim.g.opencode_opts = {
        server = {
          start = start_server,
          stop = stop_server,
          toggle = toggle_server,
        },
      }
      vim.o.autoread = true
    end,
  },
}
