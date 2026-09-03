local function prompt_with_context(context)
  local _, ctx = require('sidekick.cli').render(context)
  vim.ui.input({ prompt = 'Sidekick: ' }, function(input)
    if not input or input == '' then
      return
    end

    local text = ctx and vim.deepcopy(ctx) or {}
    if #text > 0 then
      text[#text + 1] = {}
    end
    text[#text + 1] = { { input } }

    require('sidekick.cli').send({
      filter = { installed = true },
      text = text,
      submit = true,
      focus = false,
    })
  end)
end

local function prompt_with_message(value)
  local sep = value:find('%s') and ' ' or ': '
  vim.ui.input({ prompt = 'Message', default = value .. sep }, function(input)
    if not input or input == '' then
      return
    end
    require('sidekick.cli').send({ filter = { installed = true }, msg = input, submit = true })
  end)
end

local function select_prompt()
  local prompts = require('sidekick.config').cli.prompts
  local names = vim.tbl_keys(prompts)
  table.sort(names)

  local function resolve(name)
    local prompt = prompts[name]
    local value = type(prompt) == 'table' and prompt.msg or prompt
    return type(value) == 'string' and value or ('{' .. name .. '}')
  end

  vim.ui.select(names, {
    prompt = 'Sidekick Prompt',
    format_item = function(name)
      local value = resolve(name)
      local tag = value:find('%s') and 'sentence' or 'context'
      local label = ('[%s]'):format(tag)
      return string.format('%-16s %-10s  %s', name, label, (value:gsub('\n', '⏎')))
    end,
  }, function(choice)
    if choice then
      prompt_with_message(resolve(choice))
    end
  end)
end

return {
  {
    'NorinB/sidekick.nvim',
    keys = {
      { '<leader>a', desc = '+AI', mode = { 'n', 'x' } },
      {
        '<leader>aa',
        function()
          prompt_with_context('{this}')
        end,
        mode = 'n',
        desc = 'Sidekick input prompt',
      },
      {
        '<leader>aa',
        function()
          prompt_with_context('{position}\n{selection}')
        end,
        mode = 'x',
        desc = 'Sidekick input prompt with selection',
      },
      {
        '<leader>aA',
        function()
          vim.ui.input({ prompt = 'Sidekick: ' }, function(input)
            if not input or input == '' then
              return
            end
            require('sidekick.cli').send({
              filter = { installed = true },
              msg = input,
              submit = true,
            })
          end)
        end,
        mode = { 'n', 'x' },
        desc = 'Sidekick input prompt without context',
      },
      {
        '<leader>ac',
        function()
          require('sidekick.cli').toggle({ name = 'claude', focus = true })
        end,
        desc = 'Sidekick toggle claude',
      },
      {
        '<leader>aC',
        function()
          require('sidekick.cli').toggle({ name = 'codex', focus = true })
        end,
        desc = 'Sidekick toggle codex',
      },
      {
        '<leader>ad',
        function()
          require('sidekick.cli').close()
        end,
        desc = 'Sidekick detach a CLI session',
      },
      {
        '<leader>af',
        function()
          require('sidekick.cli').send({ msg = '{file}' })
        end,
        desc = 'Sidekick send file',
      },
      {
        '<leader>ao',
        function()
          require('sidekick.cli').toggle({ name = 'opencode', focus = true })
        end,
        desc = 'Sidekick toggle openCode',
      },
      {
        '<leader>ap',
        select_prompt,
        mode = { 'n', 'x' },
        desc = 'Sidekick prompt + input',
      },
      {
        '<leader>aP',
        function()
          require('sidekick.cli').prompt()
        end,
        mode = { 'n', 'x' },
        desc = 'Sidekick select prompt',
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
        '<leader>av',
        function()
          require('sidekick.cli').send({ msg = '{selection}' })
        end,
        mode = { 'x' },
        desc = 'Sidekick send visual selection',
      },
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
