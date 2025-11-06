-- status line
return {
  'nvim-lualine/lualine.nvim',
  dependencies = { 'nvim-tree/nvim-web-devicons', 'xiyaowong/transparent.nvim' },
  event = { 'UIEnter' },
  config = function()
    local function workspace()
      return ' ' .. vim.fn.fnamemodify(vim.fn.getcwd(), ':t')
    end
    local function flutterStatusLine()
      local decorations = vim.g.flutter_tools_decorations
      if not decorations then
        return ''
      end

      local information_table = {}

      -- type: Device
      local device = decorations.device
      if device then
        table.insert(information_table, device.name)
      end

      -- tpye: flutter.ProjectConfig
      local project_config = decorations.project_config
      if project_config and project_config.name then
        table.insert(information_table, project_config.name)
      end

      -- type: string
      local app_version = decorations.app_version
      if app_version then
        local comment_pos, _ = string.find(app_version, '#')
        if comment_pos then
          app_version = string.gsub(string.sub(app_version, 0, comment_pos - 1), '%s+', '')
        end
        table.insert(information_table, app_version)
      end

      return table.concat(information_table, ' - ')
    end
    local function node_package_info()
      local ok, package_info = pcall(require, 'package-info')
      if ok then
        return package_info.get_status()
      end
      return ''
    end
    local function recording()
      local ok, noice = pcall(require, 'noice')
      if ok then
        if noice.api.statusline.mode.has() then
          local status = noice.api.statusline.mode.get()
          return status
        end
        return ''
      end
      return ''
    end
    local function custom_separator()
      return '|'
    end
    local separators = {
      section_separators = { left = '', right = '' },
      component_separators = { left = '|', right = '|' },
    }
    local catppuccin_colors = require('catppuccin.palettes.mocha')
    local sections = {
      lualine_a = {
        { 'mode', separator = { right = separators.section_separators.left } },
        {
          recording,
          color = { bg = catppuccin_colors.red },
          separator = { right = separators.section_separators.left },
        },
      },
      lualine_b = {
        {
          'filename',
          color = { fg = 'lavender' },
          file_status = true,
          newfile_status = true,
          symbols = {
            modified = '[+]',
            readonly = '[-]',
            unnamed = '[No Name]',
            newfile = '[New]',
          },
        },
      },
      lualine_c = { 'branch', 'diff' },
      lualine_x = {
        'searchcount',
        'selectioncount',
        node_package_info,
        flutterStatusLine,
        {
          'lsp_status',
          icon = '',
          symbols = {
            spinner = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' },
            done = '✓',
            separator = ' ',
          },
          ignore_lsp = {},
        },
        {
          'diagnostics',
          sources = { 'nvim_diagnostic', 'nvim_lsp' },
          sections = { 'error', 'warn', 'info', 'hint' },
        },
      },
      lualine_y = {
        {
          'filetype',
          color = { fg = catppuccin_colors.blue },
          separator = { left = separators.section_separators.right, right = '' },
        },
        {
          custom_separator,
          color = { fg = catppuccin_colors.blue },
          separator = { left = '', right = '' },
          padding = 0,
        },
        { workspace, color = { fg = catppuccin_colors.blue }, separator = { left = '', right = '' } },
      },
      lualine_z = {
        {
          'location',
          color = { bg = catppuccin_colors.yellow },
          separator = { left = separators.section_separators.right, right = '' },
          padding = 1,
        },
        {
          custom_separator,
          color = { fg = catppuccin_colors.crust, bg = catppuccin_colors.yellow },
          separator = { left = '', right = '' },
          padding = 0,
        },
        { 'progress', color = { bg = catppuccin_colors.yellow }, separator = { left = '', right = '' }, padding = 1 },
      },
    }
    local opts = {
      options = {
        theme = 'catppuccin',
        section_separators = separators.section_separators,
        component_separators = separators.component_separators,
        globalstatus = true,
        refresh = {
          statusline = 32,
        },
      },
      ignore_focus = {},
      sections = sections,
      inactive_sections = sections,
      extensions = { 'trouble', 'mason', 'lazy' },
    }
    require('lualine').setup(opts)
    local colors = require('colors')
    colors.add_and_set_color_module('lualine', function()
      if vim.g.transparent_enabled then
        vim.api.nvim_set_hl(0, 'lualine_c_normal', {
          bg = 'NONE',
        })
        vim.api.nvim_set_hl(0, 'lualine_c_transparent', {
          bg = 'NONE',
        })
        colors.set_colors('lualine_transparent')
        require('transparent').clear_prefix('lualine_x')
      end
      vim.api.nvim_set_hl(0, 'lualine_c_diff_added_normal', {
        fg = '#a6e3a1',
      })
      vim.api.nvim_set_hl(0, 'lualine_c_diff_modified_normal', {
        fg = '#f9e2af',
      })
      vim.api.nvim_set_hl(0, 'lualine_c_diff_removed_normal', {
        fg = '#f38ba8',
      })
      vim.api.nvim_set_hl(0, 'lualine_c_diff_added_insert', {
        fg = '#a6e3a1',
      })
      vim.api.nvim_set_hl(0, 'lualine_c_diff_modified_insert', {
        fg = '#f9e2af',
      })
      vim.api.nvim_set_hl(0, 'lualine_c_diff_removed_insert', {
        fg = '#f38ba8',
      })
      vim.api.nvim_set_hl(0, 'lualine_c_diff_added_command', {
        fg = '#a6e3a1',
      })
      vim.api.nvim_set_hl(0, 'lualine_c_diff_modified_command', {
        fg = '#f9e2af',
      })
      vim.api.nvim_set_hl(0, 'lualine_c_diff_removed_command', {
        fg = '#f38ba8',
      })
      vim.api.nvim_set_hl(0, 'lualine_c_diff_added_replace', {
        fg = '#a6e3a1',
      })
      vim.api.nvim_set_hl(0, 'lualine_c_diff_modified_replace', {
        fg = '#f9e2af',
      })
      vim.api.nvim_set_hl(0, 'lualine_c_diff_removed_replace', {
        fg = '#f38ba8',
      })
      vim.api.nvim_set_hl(0, 'lualine_c_diff_added_terminal', {
        fg = '#a6e3a1',
      })
      vim.api.nvim_set_hl(0, 'lualine_c_diff_modified_terminal', {
        fg = '#f9e2af',
      })
      vim.api.nvim_set_hl(0, 'lualine_c_diff_removed_terminal', {
        fg = '#f38ba8',
      })
      vim.api.nvim_set_hl(0, 'lualine_c_diff_added_inactive', {
        fg = '#a6e3a1',
      })
      vim.api.nvim_set_hl(0, 'lualine_c_diff_modified_inactive', {
        fg = '#f9e2af',
      })
      vim.api.nvim_set_hl(0, 'lualine_c_diff_removed_inactive', {
        fg = '#f38ba8',
      })
    end)
  end,
}
