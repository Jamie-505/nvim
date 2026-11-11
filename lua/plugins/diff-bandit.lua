return {
  'Jamie-505/diffbandit.nvim',
  dir = vim.fn.expand('~/dev/private/github-forks/diffbandit.nvim'),
  cmd = {
    'DiffBandit',
    'DiffBanditBuffers',
    'DiffBanditFolderDiff',
    'DiffBanditGit',
    'DiffBanditGitCurrent',
    'DiffBanditCommitPanel',
    'DiffBanditGitMenu',
    'DiffBanditGitLog',
    'DiffBanditGitCommit',
    'DiffBanditGitCompare',
    'DiffBanditGitCheckout',
    'DiffBanditMerge',
  },
  opts = function()
    -- Transparent Normal has no bg; diffbandit falls back to black (#000000)
    -- for its "pane background" groups. Clear those so the backdrop shows.
    local function fg(name)
      return vim.api.nvim_get_hl(0, { name = name, link = false }).fg
    end
    local comment = fg('Comment')
    local p = require('catppuccin.palettes').get_palette('mocha')
    local blend = require('catppuccin.utils.colors').blend
    return {
      git = {
        panel = { view = 'tree' },
      },
      ui = {
        theme = {
          -- tweak the alphas (0-1) to make a band stronger/weaker
          colors = {
            add = blend(p.green, p.base, 0.4),
            delete = blend(p.red, p.base, 0.4),
            change = blend(p.mauve, p.base, 0.33),
            change_emphasis = blend(p.mauve, p.base, 0.66),
          },
          highlights = {
            DiffBanditContext = { bg = 'NONE' },
            DiffBanditSignColumn = { bg = 'NONE' },
            DiffBanditGap = { fg = comment, bg = 'NONE' },
            DiffBanditPlaceholder = { fg = comment, bg = 'NONE' },
            DiffBanditEmptyNotice = { fg = comment, bg = 'NONE', italic = true },
            DiffBanditConnectorContext = { fg = comment, bg = 'NONE' },
            DiffBanditOverviewContext = { bg = 'NONE' },
            DiffBanditSplit = { fg = fg('WinSeparator'), bg = 'NONE' },
            -- commit panel + pane headers
            DiffBanditStatus = { fg = fg('Normal'), bg = 'NONE' },
            DiffBanditStatusLine = { fg = comment, bg = 'NONE' },
            DiffBanditStatusMuted = { fg = comment, bg = 'NONE' },
            DiffBanditStatusAccent = { fg = fg('Identifier'), bg = 'NONE', bold = true },
          },
        },
      },
    }
  end,
  config = function(_, opts)
    require('diffbandit').setup(opts)

    -- Groups whose fg is computed (so can't be static overrides) but whose bg
    -- falls back to black when Normal is transparent: strip the black bg.
    local function strip_black()
      if vim.api.nvim_get_hl(0, { name = 'Normal', link = false }).bg then
        return
      end
      for _, name in ipairs(vim.fn.getcompletion('DiffBandit', 'highlight')) do
        local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
        if hl.bg == 0 then
          hl.bg = nil
          if hl.fg == 0 then
            hl.fg = vim.api.nvim_get_hl(0, { name = 'LineNr', link = false }).fg
          end
          vim.api.nvim_set_hl(0, name, hl)
        end
      end
    end
    strip_black()
    -- deferred so it runs after diffbandit's refresh and transparent.nvim
    vim.api.nvim_create_autocmd('ColorScheme', { callback = vim.schedule_wrap(strip_black) })
  end,
}
