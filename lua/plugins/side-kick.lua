return {
  {
    'NorinB/sidekick.nvim',
    keys = {
      {
        '<leader>ta',
        function()
          require('sidekick.cli').toggle({ filter = { installed = true } })
        end,
        desc = 'Sidekick toggle CLI',
      },
      {
        '<leader>tA',
        function()
          require('sidekick.cli').select({ filter = { installed = true } })
        end,
        desc = 'Sidekick select CLI',
      },
      {
        '<leader>ad',
        function()
          require('sidekick.cli').close()
        end,
        desc = 'Sidekick detach a CLI session',
      },
      {
        '<leader>at',
        function()
          require('sidekick.cli').send({ msg = '{this}' })
        end,
        mode = { 'x', 'n' },
        desc = 'Sidekick send this',
      },
      {
        '<leader>af',
        function()
          require('sidekick.cli').send({ msg = '{file}' })
        end,
        desc = 'Sidekick send file',
      },
      {
        '<leader>av',
        function()
          require('sidekick.cli').send({ msg = '{selection}' })
        end,
        mode = { 'x' },
        desc = 'Sidekick send visual selection',
      },
      {
        '<leader>ap',
        function()
          require('sidekick.cli').prompt()
        end,
        mode = { 'n', 'x' },
        desc = 'Sidekick select prompt',
      },
      {
        '<leader>aa',
        function()
          vim.ui.input({ prompt = 'Sidekick: ' }, function(input)
            if input and input ~= '' then
              require('sidekick.cli').send({ msg = input, submit = true, focus = false })
            end
          end)
        end,
        mode = { 'n', 'x' },
        desc = 'Sidekick input prompt',
      },
      {
        '<leader>aA',
        function()
          local prompts = require('sidekick.config').cli.prompts
          local names = vim.tbl_keys(prompts)
          table.sort(names)
          local function resolve(name)
            local p = prompts[name]
            local value = type(p) == 'table' and p.msg or p
            return type(value) == 'string' and value or ('{' .. name .. '}')
          end
          vim.ui.select(names, {
            prompt = 'Sidekick Prompt',
            format_item = function(name)
              local value = resolve(name)
              local tag = value:find('%s') and 'sentence' or 'context '
              return string.format('%-16s [%s]  %s', name, tag, (value:gsub('\n', '⏎')))
            end,
          }, function(choice)
            if not choice then
              return
            end
            local value = resolve(choice)
            local sep = value:find('%s') and ' ' or ': '
            vim.ui.input({ prompt = 'Message', default = value .. sep }, function(input)
              if not input or input == '' then
                return
              end
              require('sidekick.cli').send({ filter = { installed = true }, msg = input, submit = true })
            end)
          end)
        end,
        mode = { 'n', 'x' },
        desc = 'Sidekick prompt + input',
      },
      {
        '<leader>ac',
        function()
          require('sidekick.cli').toggle({ name = 'claude', focus = true })
        end,
        desc = 'Sidekick toggle claude',
      },
      {
        '<leader>ao',
        function()
          require('sidekick.cli').toggle({ name = 'opencode', focus = true })
        end,
        desc = 'Sidekick toggle openCode',
      },
    },
    ---@type sidekick.Config
    opts = {
      nes = { enabled = false },
      cli = {
        mux = {
          backend = 'tmux',
          enabled = true,
          create = 'split',
          split = {
            size = 0.3,
            before = true,
            close_on_exit = true,
          },
        },
        prompts = {
          visible = '{visible}',
          diagnostics = '{diagnostics}',
          diagnostics_all = '{diagnostics_all}',
          this = '{this}',
          selection = '{position}\n{selection}',
        },
        context = {
          visible = function(ctx)
            local Loc = require('sidekick.cli.context.location')
            local seen, ret = {}, {}
            for _, win in ipairs(vim.api.nvim_list_wins()) do
              local buf = vim.api.nvim_win_get_buf(win)
              if not seen[buf] and Loc.is_file(buf) then
                seen[buf] = true
                local file = Loc.get({ buf = buf, cwd = ctx.cwd }, { kind = 'file' })[1]
                if file then
                  table.insert(file, 1, { '- ', '@markup.list.markdown' })
                  ret[#ret + 1] = file
                end
              end
            end
            return ret
          end,
        },
      },
    },
  },
}
