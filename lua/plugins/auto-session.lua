return {
  'rmagatti/auto-session',
  lazy = false,
  keys = {
    { '<leader>sl', '<cmd>AutoSession restore<CR>', desc = 'Session Restore last in cwd' },
    { '<leader>fse', '<cmd>AutoSession search<CR>', desc = 'Telescope Sessions' },
    { '<leader>sd', '<cmd>AutoSession delete<CR>', desc = 'Session Delete current session' },
  },
  ---enables autocomplete for opts
  ---@module "auto-session"
  ---@type AutoSession.Config
  opts = {
    suppressed_dirs = { '~/', '~/Downloads', '/' },
    cwd_change_handling = true,
    auto_restore_last_session = false,
    auto_restore = false,
    session_lens = {
      picker = 'telescope',
      mappings = {
        delete_session = { { 'n', 'i' }, '<C-d>' },
        alternate_session = { { 'n', 'i' }, '<C-s>' },
        copy_session = { { 'n', 'i' }, '<C-y>' },
      },
      load_on_setup = false,
    },
    pre_save_cmds = {
      -- "bw __FLUTTER_DEV_LOG__",
    },
  },
}
