-- window navigation, resizing and buffer swapping
return {
  'smart-splits-nvim/smart-splits.nvim',
  version = '^3.0.0',
  -- must not be lazy: the tmux backend needs to mark the pane as running
  -- Neovim (`@pane-is-vim`) as soon as possible, or tmux swallows <C-hjkl>
  lazy = false,
  dependencies = {
    -- checked first: detects via $TMUX, so it only wins inside a tmux session
    { 'smart-splits-nvim/backend-tmux', main = 'smart-splits-backend-tmux' },
    -- fallback: wins when not inside tmux, e.g. inside herdr directly
    { 'adriankarlen/smart-splits-backend-herdr', main = 'smart-splits-backend-herdr' },
  },
  keys = {
    {
      '<C-h>',
      function()
        require('smart-splits').move_cursor_left()
      end,
      desc = 'SmartSplits move cursor left',
      mode = { 'n', 't' },
    },
    {
      '<C-j>',
      function()
        require('smart-splits').move_cursor_down()
      end,
      mode = { 'n', 't' },
      desc = 'SmartSplits move cursor down',
    },
    {
      '<C-k>',
      function()
        require('smart-splits').move_cursor_up()
      end,
      mode = { 'n', 't' },
      desc = 'SmartSplits move cursor up',
    },
    {
      '<C-l>',
      function()
        require('smart-splits').move_cursor_right()
      end,
      mode = { 'n', 't' },
      desc = 'SmartSplits move cursor right',
    },
    {
      '<Right>',
      function()
        require('smart-splits').resize_right()
      end,
      desc = 'Window Resize right',
    },
    {
      '<Left>',
      function()
        require('smart-splits').resize_left()
      end,
      desc = 'Window Resize left',
    },
    {
      '<Up>',
      function()
        require('smart-splits').resize_up()
      end,
      desc = 'Window Resize up',
    },
    {
      '<Down>',
      function()
        require('smart-splits').resize_down()
      end,
      desc = 'Window Resize down',
    },
    {
      '<M-Right>',
      function()
        require('smart-splits').swap_buf_right()
      end,
      desc = 'Window Swap buffer right',
    },
    {
      '<M-Left>',
      function()
        require('smart-splits').swap_buf_left()
      end,
      desc = 'Window Swap buffer left',
    },
    {
      '<M-Up>',
      function()
        require('smart-splits').swap_buf_up()
      end,
      desc = 'Window Swap buffer up',
    },
    {
      '<M-Down>',
      function()
        require('smart-splits').swap_buf_down()
      end,
      desc = 'Window Swap buffer down',
    },
  },
  ---@type SmartSplitsConfig
  opts = {
    -- Ignored buffer types (fallback for both resize and move, unless overridden below)
    ignored_buftypes = {
      'nofile',
      'quickfix',
      'prompt',
    },
    -- Ignored filetypes (fallback for both resize and move, unless overridden below)
    ignored_filetypes = { 'NvimTree' },
    resize = {
      -- the default number of lines/columns to resize by at a time
      amount = 3,
      -- ignore these autocmd events (via :h eventignore) while processing
      -- smart-splits.nvim computations, which involve visiting different
      -- buffers and windows. These events will be ignored during processing,
      -- and un-ignored on completed. This only applies to resize events,
      -- not cursor movement events.
      ignored_events = {
        'BufEnter',
        'WinEnter',
      },
    },
    move = {
      -- Desired behavior when your cursor is at an edge and you
      -- are moving towards that same edge:
      -- 'wrap' => Wrap to opposite side
      -- 'split' => Create a new split in the desired direction
      -- 'stop' => Do nothing
      -- function => You handle the behavior yourself
      -- NOTE: If using a function, the function will be called with
      -- a context object with the following fields:
      -- {
      --    backend = SmartSplitsBackend|nil, -- the resolved backend, nil if none resolved
      --    direction = 'left'|'right'|'up'|'down',
      --    split(), -- utility function to split current Neovim pane in the current direction
      --    wrap(), -- utility function to wrap to opposite Neovim pane
      -- }
      -- NOTE: `at_edge = 'wrap'` falls back to wrapping within Neovim's own
      -- windows whenever the resolved backend has no pane to wrap to
      at_edge = 'wrap',
      -- when moving cursor between splits left or right,
      -- place the cursor on the same row of the *screen*
      -- regardless of line numbers. False by default.
      -- Can be overridden via function parameter, see Usage.
      same_row = false,
    },
    swap = {
      -- whether the cursor should follow the buffer when swapping
      -- buffers by default; it can also be controlled by passing
      -- `{ move_cursor = true }` or `{ move_cursor = false }`
      -- when calling the Lua function.
      move_cursor = false,
    },
    mux = {
      -- tmux wins when inside a tmux session ($TMUX set); herdr is the
      -- fallback for when herdr is the active multiplexer instead
      backend = { 'smart-splits-backend-tmux', 'smart-splits-backend-herdr' },
      warn_if_unusable = true,
    },
    log = {
      -- default logging level, one of: 'trace'|'debug'|'info'|'warn'|'error'|'fatal'
      level = 'info',
    },
  },
}
