-- quick navigation
return {
  enabled = false,
  'folke/flash.nvim',
  event = 'BufReadPost',
  ---@type Flash.Config
  opts = {
    modes = {
      char = {
        enabled = false,
      },
    },
  },
    -- stylua: ignore
    keys = {
      { "S", mode = { "n" }, function() require("flash").jump() end, desc = "Flash" },
      { "n", mode = { "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
      { "N", mode = { "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
      { "r", mode = { "x","o" }, function() require("flash").remote() end, desc = "Flash Remote Flash" },
      { "R", mode = { "x", "o" }, function() require("flash").treesitter_search() end, desc = "Flash Treesitter Search" },
      { "<c-f>", mode = { "c" }, function() require("flash").toggle() end, desc = "Flash Toggle Flash Search" },
    },
}
