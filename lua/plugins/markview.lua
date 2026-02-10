return {
  'OXY2DEV/markview.nvim',
  ft = 'markdown',
  priority = 49,
  opts = {
    markdown = {
      headings = {
        heading_1 = { icon_hl = '@markup.link', icon = '[%d] ' },
        heading_2 = { icon_hl = '@markup.link', icon = '[%d.%d] ' },
        heading_3 = { icon_hl = '@markup.link', icon = '[%d.%d.%d] ' },
        heading_4 = { icon_hl = '@markup.link', icon = '[%d.%d.%d.%d] ' },
        heading_5 = { icon_hl = '@markup.link', icon = '[%d.%d.%d.%d.%d] ' },
        heading_6 = { icon_hl = '@markup.link', icon = '[%d.%d.%d.%d.%d.%d] ' },
      },
    },
  },
  config = function(_, opts)
    require('markview').setup(opts)
    require('markview.extras.checkboxes').setup({
      --- Default checkbox state(used when adding checkboxes).
      ---@type string
      default = 'X',

      --- Changes how checkboxes are removed.
      ---@type
      ---| "disable" Disables the checkbox.
      ---| "checkbox" Removes the checkbox.
      ---| "list_item" Removes the list item markers too.
      remove_style = 'disable',

      --- Various checkbox states.
      ---
      --- States are in sets to quickly change between them
      --- when there are a lot of states.
      ---@type string[][]
      states = {
        { ' ', '/', 'X' },
        { '<', '>' },
        { '?', '!', '*' },
        { '"' },
        { 'l', 'b', 'i' },
        { 'S', 'I' },
        { 'p', 'c' },
        { 'f', 'k', 'w' },
        { 'u', 'd' },
      },
    })
    require('markview.extras.headings').setup()
    require('markview.extras.editor').setup()
  end,
}
