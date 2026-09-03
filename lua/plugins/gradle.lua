return {
  'oclay1st/gradle.nvim',
  cmd = { 'Gradle', 'GradleExec', 'GradleInit', 'GradleFavorites' },
  dependencies = {
    'MunifTanjim/nui.nvim',
  },
  opts = {}, -- options, see default configuration
  keys = {
    { '<leader>G', desc = '+Gradle', mode = { 'n', 'x' } },
    { '<leader>Gp', '<cmd>Gradle<cr>', desc = 'Gradle Projects' },
    { '<leader>GF', '<cmd>GradleFavorites<cr>', desc = 'Gradle Favorite Commands' },
  },
}
