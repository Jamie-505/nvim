-- vim: ft=lua tw=80
std = 'luajit'
cache = true

-- Neovim + config globals
read_globals = {
  'vim',
  'Snacks',
}
globals = {
  'vim.g',
  'vim.b',
  'vim.w',
  'vim.o',
  'vim.bo',
  'vim.wo',
  'vim.env',
  'vim.opt',
  'vim.opt_local',
}

ignore = {
  '631', -- line is too long
  '212', -- unused argument
}

exclude_files = {
  'lazy-lock.json',
}
