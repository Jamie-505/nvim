return {
  'vuki656/package-info.nvim',
  dependencies = { 'MunifTanjim/nui.nvim', 'nvim-telescope/telescope.nvim' },
  event = 'BufEnter *package.json',
  keys = {
    {
      '<leader>pi',
      '<CMD>Telescope package_info<CR>',
      desc = 'Telescope NPM Package Info',
      silent = true,
      noremap = true,
    },
  },
  opts = {
    highlights = {
      up_to_date = { -- highlight for up to date dependency virtual text
        fg = '#3C4048',
      },
      outdated = { -- highlight for outdated dependency virtual text
        fg = '#d19a66',
      },
      invalid = { -- highlight for invalid dependency virtual text
        fg = '#ee4b2b',
      },
    },
    icons = {
      enable = true, -- Whether to display icons
      style = {
        up_to_date = '|  ', -- Icon for up to date dependencies
        outdated = '|  ', -- Icon for outdated dependencies
        invalid = '|  ', -- Icon for invalid dependencies
      },
    },
    autostart = true, -- Whether to autostart when `package.json` is opened
    hide_up_to_date = true, -- It hides up to date versions when displaying virtual text
    hide_unstable_versions = false, -- It hides unstable versions from version list e.g next-11.1.3-canary3
    -- Can be `npm`, `yarn`, or `pnpm`. Used for `delete`, `install` etc...
    -- The plugin will try to auto-detect the package manager based on
    -- `yarn.lock` or `package-lock.json`. If none are found it will use the
    -- provided one, if nothing is provided it will use `yarn`
    package_manager = 'npm',
  },
  config = function(_, opts)
    require('package-info').setup(opts)
    require('telescope').load_extension('package_info')
    require('colors').add_and_set_color_module('package-info', function()
      vim.api.nvim_set_hl(0, 'PackageInfoUpToDateVersion', {
        fg = '#abe9b3',
      })
      vim.api.nvim_set_hl(0, 'PackageInfoOutdatedVersion', {
        fg = '#d19a66',
      })
      vim.api.nvim_set_hl(0, 'PackageInfoInvalidVersion', {
        fg = '#ee4b2b',
      })
    end)
  end,
}
