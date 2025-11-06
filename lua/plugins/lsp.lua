return {
  {
    'neovim/nvim-lspconfig',
    dependencies = {
      'nvim-lua/plenary.nvim',
    },
    event = 'BufEnter',
    config = function()
      local lspconfig = require('lsp-opts')
      lspconfig.defaults()
      lspconfig.setup_keymaps()
      lspconfig.setup_colors()
    end,
  },
  {
    'antosha417/nvim-lsp-file-operations',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-tree/nvim-tree.lua',
      'stevearc/oil.nvim',
    },
    event = { 'User NvimTreeSetup' },
    ft = { 'oil' },
    config = function()
      require('lsp-file-operations').setup()
    end,
  },
  {
    'nvim-treesitter/nvim-treesitter',
    dependencies = { 'LiadOz/nvim-dap-repl-highlights' },
    lazy = false,
    branch = 'main',
    build = ':TSUpdate',
    config = function()
      local ensure_installed = {
        'angular',
        'bash',
        'c_sharp',
        'css',
        'dart',
        'dap_repl',
        'dockerfile',
        'javascript',
        'html',
        'hyprlang',
        'ini',
        'json',
        'json5',
        'kotlin',
        'latex',
        'lua',
        'luadoc',
        'markdown',
        'markdown_inline',
        'printf',
        'python',
        'regex',
        'rust',
        'ssh_config',
        'swift',
        'terraform',
        'tmux',
        'toml',
        'typescript',
        'vim',
        'vimdoc',
        'yaml',
      }

      local already_installed = require('nvim-treesitter.config').get_installed()
      local parsers_to_install = vim
        .iter(ensure_installed)
        :filter(function(parser)
          return not vim.tbl_contains(already_installed, parser)
        end)
        :totable()
      require('nvim-treesitter').install(parsers_to_install)
      require('nvim-treesitter').update()

      -- Add Custom Filetypes
      local function is_hypr_conf(path)
        return path:match('/hypr/') and path:match('%.conf$')
      end

      local function is_tmux_conf(path)
        return path:match('%tmux.conf$')
      end

      local function check_yaml_file(path)
        if path:match('.*docker.*compose.*$') and (path:match('%.yaml$') or path:match('%.yml$')) then
          return 'yaml.docker-compose'
        end
        return 'yaml'
      end

      vim.filetype.add({
        pattern = {
          -- [".*%.component%.html"] = "htmlangular", -- Sets the filetype to `angular` if it matches the pattern
          ['.*%.yaml'] = function(path, _)
            return check_yaml_file(path)
          end,
          ['.*%.yml'] = function(path, _)
            return check_yaml_file(path)
          end,
          ['.*%.conf'] = function(path, _)
            if is_hypr_conf(path) then
              return 'hyprlang'
            elseif is_tmux_conf(path) then
              return 'tmux'
            else
              return 'dosini'
            end
          end,
        },
      })

      -- Angular
      local function is_angular_template(path)
        return path:match('%.component%.html$')
      end
      vim.api.nvim_create_augroup('AngularTemplates', {})
      vim.api.nvim_create_autocmd({ 'BufRead', 'BufEnter', 'BufNewFile' }, {
        pattern = '*.component.html',
        callback = function()
          -- Set filetype to HTML in order for html related plugins to work
          vim.bo.filetype = 'html'

          -- Set filetype to angular for treesitter specifically
          if is_angular_template(vim.fn.expand('<afile>:p')) then
            vim.cmd('set filetype=htmlangular')
          end
        end,
        group = 'AngularTemplates',
      })

      -- auto-start highlights & indentation
      vim.api.nvim_create_autocmd('FileType', {
        desc = 'User: enable treesitter highlighting',
        callback = function(ctx)
          -- highlights
          local hasStarted = pcall(vim.treesitter.start) -- errors for filetypes with no parser

          -- folds
          local bufnr = ctx.buf
          vim.bo[bufnr].syntax = 'on'
          vim.wo.foldlevel = 99
          vim.wo.foldmethod = 'expr'
          vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'

          -- indent
          local noIndent = {}
          if hasStarted and not vim.list_contains(noIndent, ctx.match) then
            vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })
    end,
  },
  {
    'nvim-treesitter/nvim-treesitter-textobjects',
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    branch = 'main',
    event = { 'BufReadPost', 'BufNewFile' },
    config = function()
      require('nvim-treesitter-textobjects').setup({
        select = {
          enable = true,
          disable = { 'dart' },

          -- Automatically jump forward to textobj, similar to targets.vim
          lookahead = true,

          keymaps = {
            -- You can use the capture groups defined in textobjects.scm
            ['af'] = '@function.outer',
            ['if'] = '@function.inner',
            ['ac'] = '@class.outer',
            -- You can optionally set descriptions to the mappings (used in the desc parameter of
            -- nvim_buf_set_keymap) which plugins like which-key display
            ['ic'] = { query = '@class.inner', desc = 'Select inner part of a class region' },
            -- You can also use captures from other query groups like `locals.scm`
            ['as'] = { query = '@local.scope', query_group = 'locals', desc = 'Select language scope' },
          },
          -- You can choose the select mode (default is charwise 'v')
          --
          -- Can also be a function which gets passed a table with the keys
          -- * query_string: eg '@function.inner'
          -- * method: eg 'v' or 'o'
          -- and should return the mode ('v', 'V', or '<c-v>') or a table
          -- mapping query_strings to modes.
          selection_modes = {
            ['@parameter.outer'] = 'v', -- charwise
            ['@function.outer'] = 'V', -- linewise
            ['@class.outer'] = '<c-v>', -- blockwise
          },
          -- If you set this to `true` (default is `false`) then any textobject is
          -- extended to include preceding or succeeding whitespace. Succeeding
          -- whitespace has priority in order to act similarly to eg the built-in
          -- `ap`.
          --
          -- Can also be a function which gets passed a table with the keys
          -- * query_string: eg '@function.inner'
          -- * selection_mode: eg 'v'
          -- and should return true or false
          include_surrounding_whitespace = true,
        },
        swap = {
          enable = true,
          disable = { 'dart' },
          swap_next = {
            ['<leader>ps'] = '@parameter.inner',
          },
          swap_previous = {
            ['<leader>pS'] = '@parameter.inner',
          },
        },
        move = {
          enable = true,
          disable = { 'dart' },
          set_jumps = true, -- whether to set jumps in the jumplist
          goto_next_start = {
            [']m'] = '@function.outer',
            [']]'] = { query = '@class.outer', desc = 'Next class start' },
            --
            -- You can use regex matching (i.e. lua pattern) and/or pass a list in a "query" key to group multiple queries.
            [']o'] = '@loop.*',
            -- ["]o"] = { query = { "@loop.inner", "@loop.outer" } }
            --
            -- You can pass a query group to use query from `queries/<lang>/<query_group>.scm file in your runtime path.
            -- Below example nvim-treesitter's `locals.scm` and `folds.scm`. They also provide highlights.scm and indent.scm.
            [']s'] = { query = '@local.scope', query_group = 'locals', desc = 'Next scope' },
            [']z'] = { query = '@fold', query_group = 'folds', desc = 'Next fold' },
          },
          goto_next_end = {
            [']M'] = '@function.outer',
            [']['] = '@class.outer',
          },
          goto_previous_start = {
            ['[m'] = '@function.outer',
            ['[['] = '@class.outer',
          },
          goto_previous_end = {
            ['[M'] = '@function.outer',
            ['[]'] = '@class.outer',
          },
          -- Below will go to either the start or the end, whichever is closer.
          -- Use if you want more granular movements
          -- Make it even more gradual by adding multiple queries and regex.
          goto_next = {
            [']d'] = '@conditional.outer',
          },
          goto_previous = {
            ['[d'] = '@conditional.outer',
          },
        },
      })
    end,
  },
  {
    'nvim-treesitter/nvim-treesitter-context',
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    cmd = { 'TSContextEnable', 'TSContextDisable', 'TSContextToggle' },
    event = { 'BufReadPost', 'BufNewFile' },
    keys = {
      {
        '<leader>gC',
        function()
          require('treesitter-context').go_to_context(vim.v.count1)
        end,
        silent = true,
        desc = 'Goto Context',
      },
    },
    opts = {
      enable = true, -- Enable this plugin (Can be enabled/disabled later via commands)
      multiwindow = false, -- Enable multiwindow support.
      max_lines = 4, -- How many lines the window should span. Values <= 0 mean no limit.
      min_window_height = 0, -- Minimum editor window height to enable context. Values <= 0 mean no limit.
      line_numbers = true,
      multiline_threshold = 20, -- Maximum number of lines to show for a single context
      trim_scope = 'outer', -- Which context lines to discard if `max_lines` is exceeded. Choices: 'inner', 'outer'
      mode = 'cursor', -- Line used to calculate context. Choices: 'cursor', 'topline'
      -- Separator between context and content. Should be a single character string, like '-'.
      -- When separator is set, the context will only show up when there are at least 2 lines above cursorline.
      separator = nil,
      zindex = 20, -- The Z-index of the context window
      on_attach = nil, -- (fun(buf: integer): boolean) return false to disable attaching
    },
    config = function(_, opts)
      require('treesitter-context').setup(opts)
      require('colors').add_and_set_color_module('treesitter-context', function()
        vim.api.nvim_set_hl(0, 'TreesitterContext', {
          bg = 'NONE',
        })
        vim.api.nvim_set_hl(0, 'TreesitterContextBottom', {
          sp = '#f9e2af',
          underline = true,
        })
        vim.api.nvim_set_hl(0, 'TreesitterContextLineNumber', {
          bg = 'NONE',
        })
      end)
    end,
  },
  {
    'mason-org/mason.nvim',
    cmd = { 'Mason', 'MasonInstall', 'MasonInstallAll', 'MasonUpdate' },
    keys = {
      { 'M', '<CMD>Mason<CR>', desc = 'Mason Open' },
    },
    opts = function()
      return require('mason-opts')
    end,
    config = function(_, opts)
      require('mason').setup(opts.options)

      vim.api.nvim_create_user_command('MasonInstallAll', function()
        if opts.options.ensure_installed_mason_names and #opts.options.ensure_installed_mason_names > 0 then
          vim.cmd('MasonInstall ' .. table.concat(opts.options.ensure_installed_mason_names, ' '))
        end
      end, {})

      vim.g.mason_binaries_list = opts.options.ensure_installed
    end,
  },
  {
    'dmmulroy/tsc.nvim',
    cmd = { 'TSC' },
    opts = {},
  },
  {
    'folke/trouble.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    cmd = 'Trouble',
    opts = {},
  },
  {
    'rachartier/tiny-inline-diagnostic.nvim',
    -- dependencies = { "https://git.sr.ht/~whynothugo/lsp_lines.nvim" },
    priority = 1000, -- needs to be loaded in first
    event = 'VeryLazy', -- Or `LspAttach`
    keys = function()
      --tiny-inline-diagnostic and lsp_lines toggle through
      -- local show_lsp_lines = vim.diagnostic.config().virtual_text
      local show_diagnostics = true
      return {
        {
          '<leader>ldt',
          function()
            -- if (not show_diagnostics and show_lsp_lines) or show_diagnostics then
            --   show_lsp_lines = require("lsp_lines").toggle()
            -- end
            show_diagnostics = not show_diagnostics
            if show_diagnostics then
              require('tiny-inline-diagnostic').enable()
            else
              require('tiny-inline-diagnostic').disable()
            end
          end,
          desc = 'Diagnostics Toggle virtual text',
        },
        {
          '<leader>ldd',
          function()
            vim.diagnostic.config({ virtual_text = false })
          end,
          desc = 'Diagnostics Force disable virtual text diagnostics',
        },
      }
    end,
    opts = {
      options = {
        use_icons_from_diagnostic = false,
        show_source = true,
        add_messages = true,
        multilines = {
          enabled = true,
          always_show = true,
        },
        show_all_diags_on_cursorline = true,
      },
    },
    config = function(_, opts)
      require('tiny-inline-diagnostic').setup(opts)
      vim.schedule(function()
        vim.diagnostic.config({ virtual_text = false })
      end)
    end,
  },
  {
    'rmagatti/goto-preview',
    keys = {
      {
        '<leader>lpd',
        function()
          require('goto-preview').goto_preview_definition()
        end,
        desc = 'Goto-Preview Go to definition (via popup)',
      },
    },
    opts = {
      width = 120, -- Width of the floating window
      height = 15, -- Height of the floating window
      border = { '↖', '─', '┐', '│', '┘', '─', '└', '│' }, -- Border characters of the floating window
      default_mappings = false, -- Bind default mappings
      debug = false, -- Print debug information
      opacity = nil, -- 0-100 opacity level of the floating window where 100 is fully transparent.
      resizing_mappings = false, -- Binds arrow keys to resizing the floating window.
      post_open_hook = nil, -- A function taking two arguments, a buffer and a window to be ran as a hook.
      post_close_hook = nil, -- A function taking two arguments, a buffer and a window to be ran as a hook.
      references = { -- Configure the telescope UI for slowing the references cycling window.
        telescope = require('telescope.themes').get_dropdown({ hide_preview = false }),
      },
      -- These two configs can also be passed down to the goto-preview definition and implementation calls for one off "peak" functionality.
      focus_on_open = true, -- Focus the floating window when opening it.
      dismiss_on_move = false, -- Dismiss the floating window when moving the cursor.
      force_close = true, -- passed into vim.api.nvim_win_close's second argument. See :h nvim_win_close
      bufhidden = 'wipe', -- the bufhidden option to set on the floating window. See :h bufhidden
      stack_floating_preview_windows = true, -- Whether to nest floating windows
      preview_window_title = { enable = true, position = 'left' }, -- Whether to set the preview window title as the filename
      zindex = 1, -- Starting zindex for the stack of floating windows
    },
  },
  {
    'ray-x/lsp_signature.nvim',
    event = 'LspAttach',
    opts = {
      bind = true,
      handler_opts = {
        border = 'rounded',
      },
      hint_prefix = '',
    },
  },
  {
    'smjonas/inc-rename.nvim',
    cmd = 'IncRename',
    keys = {
      {
        '<leader>lR',
        ':IncRename ',
        desc = 'Lsp IncRename',
      },
    },
    opts = {
      -- the name of the command
      cmd_name = 'IncRename',
      -- the highlight group used for highlighting the identifier's new name
      hl_group = 'Substitute',
      -- whether an empty new name should be previewed; if false the command preview will be cancelled instead
      preview_empty_name = false,
      -- whether to display a `Renamed m instances in n files` message after a rename operation
      show_message = true,
      -- whether to save the "IncRename" command in the commandline history (set to false to prevent issues with
      -- navigating to older entries that may arise due to the behavior of command preview)
      save_in_cmdline_history = false,
      -- the type of the external input buffer to use (currently supports "dressing" or "snacks")
      input_buffer_type = nil,
      -- callback to run after renaming, receives the result table (from LSP handler) as an argument
      post_hook = nil,
    },
  },
  {
    'JezerM/oil-lsp-diagnostics.nvim',
    dependencies = { 'stevearc/oil.nvim' },
    ft = { 'oil' },
    opts = {
      diagnostic_colors = {
        error = 'DiagnosticError',
        warn = 'DiagnosticWarn',
        info = 'DiagnosticInfo',
        hint = 'DiagnosticHint',
      },
      diagnostic_symbols = {
        error = '',
        warn = '',
        info = '',
        hint = '󰌶',
      },
    },
  },
}
