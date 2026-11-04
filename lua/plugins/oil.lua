-- manipulate files with vim motions
return {
  'stevearc/oil.nvim',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  lazy = false,
  init = function()
    -- A move whose willRenameFiles edits touch the moved file itself (kotlin-lsp
    -- rewrites its `package` line at the old path) leaves the old-path buffer
    -- modified. Oil then copies that text into the destination buffer and
    -- deletes the old buffer without force; with 'confirm' on that asks "Save
    -- changes to <old path>?", and Yes (or a later :wall, after Cancel) writes the
    -- old file back, so the class exists twice. OilActionsPost runs before oil's
    -- scheduled copy and delete: carry the text over here and drop the old buffer.
    local function by_name(name)
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.fs.normalize(vim.api.nvim_buf_get_name(b)) == name then
          return b
        end
      end
    end
    local function carry(buf, dest)
      vim.api.nvim_buf_set_lines(dest, 0, -1, false, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == buf then
          local cursor = vim.api.nvim_win_get_cursor(win)
          vim.api.nvim_win_set_buf(win, dest)
          pcall(vim.api.nvim_win_set_cursor, win, cursor)
        end
      end
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    vim.api.nvim_create_autocmd('User', {
      pattern = 'OilActionsPost',
      group = vim.api.nvim_create_augroup('oil-lsp-moves', { clear = true }),
      callback = function(ev)
        if ev.data.err then
          return
        end
        local util = require('oil.util')
        local moves = {}
        for _, a in ipairs(ev.data.actions or {}) do
          if a.type == 'move' then
            local _, src = util.parse_url(a.src_url)
            local _, dest = util.parse_url(a.dest_url)
            if src and dest then
              table.insert(moves, { src = vim.fs.normalize(src), dest = vim.fs.normalize(dest), dir = a.entry_type == 'directory' })
            end
          end
        end
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          local name = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
          for _, m in ipairs(moves) do
            local target
            if name == m.src then
              target = m.dest
            elseif m.dir and vim.startswith(name, m.src .. '/') then
              target = m.dest .. name:sub(#m.src + 1)
            end
            local dest = target and by_name(target)
            if
              dest
              and dest ~= buf
              and vim.api.nvim_buf_is_loaded(buf)
              and vim.api.nvim_buf_is_loaded(dest)
              and vim.bo[buf].modified
              and not vim.bo[dest].modified
              and not vim.uv.fs_stat(name)
            then
              carry(buf, dest)
              break
            end
          end
        end
      end,
    })
  end,
  keys = {
    {
      '-',
      function()
        local oil = require('oil')
        local oil_util = require('oil.util')
        oil.open_float()
        oil_util.run_after_load(0, function()
          oil.open_preview()
        end)
      end,
      desc = 'Oil Open parent directory',
    },
  },
  ---@type oil.SetupOpts
  opts = {
    win_options = {
      wrap = true,
      signcolumn = 'yes:2',
    },
    delete_to_trash = true,
    watch_for_changes = true,
    lsp_file_methods = {
      -- kotlin-lsp answers willRenameFiles in ~1.4 s on a cold index; at the
      -- 1000 ms default oil skips the edits and still moves the file
      timeout_ms = 10000,
    },
    view_options = {
      show_hidden = true,
      is_hidden_file = function(name)
        return vim.startswith(name, '.')
      end,
    },
    float = {
      border = 'rounded',
      win_options = {
        winblend = 0,
        signcolumn = 'yes:2',
      },
      preview_split = 'right',
      override = function(conf)
        local new_conf = vim.tbl_deep_extend(
          'force',
          conf,
          { relative = 'editor', anchor = 'SW', row = 1000, col = 2, width = 200, height = 50 }
        )
        return new_conf
      end,
    },
    confirmation = {
      border = 'rounded',
    },
    preview_win = {
      update_on_cursor_moved = true,
      border = 'rounded',
      win_options = {
        winblend = 0,
      },
    },
    progress = {
      border = 'rounded',
      minimized_border = 'none',
      win_options = {
        winblend = 0,
      },
    },
    ssh = {
      border = 'rounded',
    },
    keymaps_help = {
      border = 'rounded',
    },
  },
}
