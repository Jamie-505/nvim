-- scope highlighting
-- TODO: check old config
return {
  'shellRaining/hlchunk.nvim',
  event = { 'BufReadPre', 'BufNewFile' },
  opts = {
    chunk = {
      enable = true,
      duration = 0,
      delay = 1,
    },
  },
}
