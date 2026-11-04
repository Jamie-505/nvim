-- Guarded Kotlin rename (spec §3.5; port of the trial prototype,
-- .scratch/kotlin-spring-ide/trial/guarded-rename.lua + guard-command.lua).
--
-- kotlin-lsp can answer a rename with edits computed against an older text
-- than the buffer holds (trial: buffer version 5, returned 1), and a plain
-- `vim.lsp.buf.rename()` then applies part of a broken edit. This command:
--   1. offers Save + rename when project buffers are modified (Cancel keeps
--      the unsaved text; nothing is requested)
--   2. snapshots open buffers (text, changedtick, LSP version) and closed
--      project sources (size, mtime) before the request
--   3. validates EVERY target before applying anything: versions, disk and
--      buffer state, ranges, overlaps; a single stale file rejects the whole
--      proposal
--   4. shows the diff and asks before applying; applies to buffers without
--      yielding, rolls back on error; results stay unsaved for review
-- Text edits only: resource operations (file moves) are refused.
local M = {}
local api = vim.api

--- Accept an open target whose returned version differs from the buffer's
--- when the buffer is unmodified and its text equals the file on disk. After
--- edit → save, kotlin-lsp (263.4702.0 and 263.7084.0) labels correct edits
--- with an older version (buffer 5, answer 1); strict checking made same-
--- session save + retry impossible. Decided 2026-11-04 (implementation.md,
--- step 7); the diff preview marks such files.
M.allow_saved_stale = true

local SKIP_DIRS = { build = true, ['.gradle'] = true, ['.git'] = true, ['.idea'] = true, ['.kotlin'] = true, node_modules = true, out = true }
local SOURCE = { kt = true, kts = true, java = true }

local function read(path)
  local file = assert(io.open(path, 'rb'), 'Cannot read ' .. path)
  local text = file:read('*a')
  file:close()
  return text
end

local function inside(root, path)
  return path:sub(1, #root + 1) == root .. '/'
end

local function canonical(root, path)
  local real = assert(vim.uv.fs_realpath(path), 'File does not exist: ' .. path)
  assert(inside(root, real), 'File is outside the project: ' .. path)
  assert(vim.uv.fs_stat(real).type == 'file', 'Not a regular file: ' .. path)
  return real
end

local function stamp(path)
  local st = vim.uv.fs_stat(path)
  return st and (st.size .. ':' .. st.mtime.sec .. '.' .. st.mtime.nsec) or nil
end

--- loaded file buffers inside root, by real path
local function buffers(root)
  local found = {}
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == '' then
      local path = vim.uv.fs_realpath(api.nvim_buf_get_name(buf))
      if path and inside(root, path) then
        assert(not found[path], 'Multiple buffers name the same file: ' .. path)
        found[path] = buf
      end
    end
  end
  return found
end

local function text_of(buf)
  assert(vim.bo[buf].fileformat == 'unix', 'Guarded rename requires LF files: ' .. api.nvim_buf_get_name(buf))
  assert(not vim.bo[buf].bomb, 'Guarded rename does not edit BOM files: ' .. api.nvim_buf_get_name(buf))
  return table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), '\n') .. (vim.bo[buf].endofline and '\n' or '')
end

local function split(text)
  local lines = vim.split(text, '\n', { plain = true })
  if text:sub(-1) == '\n' then
    table.remove(lines)
  end
  if #lines == 0 then
    lines = { '' }
  end
  return lines
end

--- project source files (Kotlin, scripts, Java), skipping build output
local function sources(root)
  local out = {}
  local function walk(dir)
    for name, kind in vim.fs.dir(dir) do
      local path = dir .. '/' .. name
      if kind == 'directory' then
        if not SKIP_DIRS[name] then
          walk(path)
        end
      elseif kind == 'file' and SOURCE[name:match('%.(%w+)$') or ''] then
        table.insert(out, path)
      end
    end
  end
  walk(root)
  return out
end

function M.dirty(root)
  local result = {}
  for path, buf in pairs(buffers(root)) do
    if vim.bo[buf].modified then
      table.insert(result, { path = path, buf = buf })
    end
  end
  table.sort(result, function(a, b)
    return a.path < b.path
  end)
  return result
end

--- Saving is an explicit earlier action: a later refusal never undoes it.
function M.save(root)
  local saved = {}
  for _, entry in ipairs(M.dirty(root)) do
    local ok, err = pcall(api.nvim_buf_call, entry.buf, function()
      vim.cmd.write()
    end)
    if not ok then
      return nil, 'Save failed; no rename requested: ' .. tostring(err), saved
    end
    table.insert(saved, entry.path)
  end
  if #M.dirty(root) > 0 then
    return nil, 'Buffers remain modified after saving', saved
  end
  return saved
end

--- Snapshot BEFORE the rename request: open buffers in full, closed sources
--- by size + mtime.
function M.snapshot(root)
  local open = buffers(root)
  local snapshot = { root = root, open = {}, closed = {} }
  for path, buf in pairs(open) do
    snapshot.open[path] = {
      path = path,
      buf = buf,
      text = text_of(buf),
      raw = read(path),
      tick = api.nvim_buf_get_changedtick(buf),
      version = vim.lsp.util.buf_versions[buf],
      modified = vim.bo[buf].modified,
    }
  end
  for _, path in ipairs(sources(root)) do
    local real = vim.uv.fs_realpath(path)
    if real and not snapshot.open[real] then
      snapshot.closed[real] = stamp(real)
    end
  end
  return snapshot
end

--- the target as it must still be: open (buffer unchanged) or closed (disk unchanged)
local function unchanged(snapshot, file)
  local buf = buffers(snapshot.root)[file.path]
  if file.buf then
    assert(read(file.path) == file.raw, 'File changed on disk: ' .. file.path)
    assert(
      buf == file.buf and api.nvim_buf_get_changedtick(buf) == file.tick,
      'Buffer changed while the rename was pending: ' .. file.path
    )
    assert(vim.lsp.util.buf_versions[buf] == file.version, 'LSP version changed: ' .. file.path)
  else
    assert(stamp(file.path) == file.stamp, 'File changed on disk: ' .. file.path)
    if buf then
      assert(not vim.bo[buf].modified, 'Previously closed target is now modified: ' .. file.path)
    end
  end
  if buf then
    assert(text_of(buf) == file.text, 'Buffer content changed: ' .. file.path)
    assert(vim.bo[buf].modifiable and not vim.bo[buf].readonly, 'Target is not writable: ' .. file.path)
  end
end

local function stage(text, edits, encoding)
  assert(not text:find('\r', 1, true) and not text:find('\0', 1, true), 'Guarded rename requires LF text without NUL')
  local lines, offsets, offset = vim.split(text, '\n', { plain = true }), {}, 0
  for i, line in ipairs(lines) do
    offsets[i] = offset
    offset = offset + #line + 1
  end
  local function position(pos)
    assert(type(pos.line) == 'number' and pos.line >= 0 and pos.line % 1 == 0, 'Invalid line')
    assert(type(pos.character) == 'number' and pos.character >= 0 and pos.character % 1 == 0, 'Invalid column')
    local line = assert(lines[pos.line + 1], 'Edit line outside document')
    local byte = vim.str_byteindex(line, encoding, pos.character, true)
    assert(vim.str_utfindex(line, encoding, byte, true) == pos.character, 'Edit splits a Unicode character')
    return offsets[pos.line + 1] + byte
  end
  local replacements = {}
  for _, edit in ipairs(edits) do
    assert(type(edit.newText) == 'string' and not edit.newText:find('[\r%z]'), 'Invalid replacement text')
    assert(not edit.annotationId, 'Annotated edits need a confirmation route guarded rename does not have')
    local first, last = position(edit.range.start), position(edit.range['end'])
    assert(first <= last, 'Reversed edit range')
    table.insert(replacements, { first = first, last = last, text = edit.newText })
  end
  table.sort(replacements, function(a, b)
    return a.first < b.first
  end)
  for i = 2, #replacements do
    local prev, next = replacements[i - 1], replacements[i]
    assert(prev.last <= next.first and prev.first ~= next.first, 'Overlapping or ambiguous edits')
  end
  for i = #replacements, 1, -1 do
    local edit = replacements[i]
    text = text:sub(1, edit.first) .. edit.text .. text:sub(edit.last + 1)
  end
  return text
end

--- A plan only when EVERY target passes; otherwise nil + the first reason.
function M.prepare(snapshot, edit, encoding)
  local ok, value = pcall(function()
    assert(type(edit) == 'table', 'No WorkspaceEdit')
    assert(not (edit.changes and edit.documentChanges), 'Ambiguous WorkspaceEdit shapes')
    local documents = vim.deepcopy(edit.documentChanges or {})
    for uri, edits in pairs(edit.changes or {}) do
      table.insert(documents, { textDocument = { uri = uri, version = vim.NIL }, edits = edits })
    end
    local plan = { snapshot = snapshot, files = {}, encoding = encoding }
    local seen = {}
    for _, document in ipairs(documents) do
      assert(not document.kind and document.textDocument, 'Resource operations (file moves) are not supported by guarded rename')
      local td = document.textDocument
      assert(vim.startswith(td.uri, 'file://'), 'Only local file edits are supported')
      local path = canonical(snapshot.root, vim.uri_to_fname(td.uri))
      assert(not seen[path], 'Repeated target document is not supported: ' .. path)
      seen[path] = true
      local file = snapshot.open[path]
      if not file then
        assert(snapshot.closed[path], 'Target was not in the request snapshot: ' .. path)
        local raw = read(path)
        file = { path = path, raw = raw, text = raw, stamp = snapshot.closed[path], modified = false }
      end
      unchanged(snapshot, file)
      local version = td.version
      local saved = not file.modified and file.raw == file.text
      if file.buf and M.allow_saved_stale and saved and type(version) == 'number' and version ~= file.version then
        file.stale_accepted = version
      elseif file.buf then
        assert(
          type(version) == 'number' and version == file.version,
          ('Stale or unverifiable edit for %s: buffer version %s, the server answered for %s'):format(
            vim.fn.fnamemodify(path, ':~:.'),
            tostring(file.version),
            tostring(version)
          )
        )
      else
        assert(version == nil or version == vim.NIL or version == 0, 'Cannot verify closed-file version: ' .. path)
      end
      assert(type(document.edits) == 'table' and #document.edits > 0, 'Empty document edit')
      local after = stage(file.text, document.edits, encoding)
      assert(
        after:sub(-1) == file.text:sub(-1) or (after:sub(-1) ~= '\n' and file.text:sub(-1) ~= '\n'),
        'Guarded rename does not change final-newline state'
      )
      table.insert(plan.files, { before = file, after = after, returned_version = version })
    end
    assert(#plan.files > 0, 'Rename returned no edits')
    table.sort(plan.files, function(a, b)
      return a.before.path < b.before.path
    end)
    return plan
  end)
  if not ok then
    return nil, (tostring(value):gsub('^[^:]+:%d+: ', ''))
  end
  return value
end

function M.preview(plan)
  local parts = {}
  for _, file in ipairs(plan.files) do
    local relative = file.before.path:sub(#plan.snapshot.root + 2)
    local note = file.before.stale_accepted
        and ('# server answered for version %d, buffer is %d: saved and equal to disk\n'):format(file.before.stale_accepted, file.before.version)
      or ''
    table.insert(
      parts,
      note .. '--- ' .. relative .. '\n+++ ' .. relative .. '\n' .. vim.diff(file.before.text, file.after, { result_type = 'unified', ctxlen = 3 })
    )
  end
  return table.concat(parts, '\n')
end

function M.apply(plan)
  local applied = {}
  local ok, err = pcall(function()
    -- load first, then revalidate every target after BufRead hooks and review
    for _, file in ipairs(plan.files) do
      local buf = file.before.buf or vim.fn.bufadd(file.before.path)
      vim.fn.bufload(buf)
      file.buf = buf
    end
    for _, file in ipairs(plan.files) do
      unchanged(plan.snapshot, file.before)
    end
    -- no event-loop yields or filesystem writes inside the commit section
    for _, file in ipairs(plan.files) do
      table.insert(applied, file)
      api.nvim_buf_set_lines(file.buf, 0, -1, false, split(file.after))
    end
  end)
  if ok then
    return true
  end
  local rollback_errors = {}
  for i = #applied, 1, -1 do
    local file = applied[i]
    local restored, why = pcall(function()
      api.nvim_buf_set_lines(file.buf, 0, -1, false, split(file.before.text))
      vim.bo[file.buf].modified = file.before.modified
    end)
    if not restored then
      table.insert(rollback_errors, file.before.path .. ': ' .. tostring(why))
    end
  end
  return nil, tostring(err), rollback_errors
end

--------------------------------------------------------------------------------
-- command

local busy = false

local function message(text, level)
  vim.notify(text, level or vim.log.levels.INFO, { title = 'Guarded rename' })
end

local function primary(buf)
  local clients = vim.lsp.get_clients({ bufnr = buf, name = 'kotlin_lsp' })
  if #clients ~= 1 or not clients[1].initialized then
    return nil, 'Exactly one initialized kotlin-lsp client is required on this buffer'
  end
  return clients[1]
end

local function show_diff(diff)
  vim.cmd('botright new')
  local preview = api.nvim_get_current_buf()
  local win = api.nvim_get_current_win()
  vim.bo[preview].buftype = 'nofile'
  vim.bo[preview].bufhidden = 'wipe'
  vim.bo[preview].swapfile = false
  vim.bo[preview].filetype = 'diff'
  api.nvim_buf_set_name(preview, 'guarded-rename://preview')
  api.nvim_buf_set_lines(preview, 0, -1, false, vim.split(diff, '\n', { plain = true }))
  vim.bo[preview].modifiable = false
  return win
end

--- @param name? string new name; asks when omitted
function M.rename(name)
  if busy then
    return message('Finish or cancel the current rename first', vim.log.levels.WARN)
  end
  local origin = api.nvim_get_current_buf()
  local origin_win = api.nvim_get_current_win()
  local client, why = primary(origin)
  if not client then
    return message(why, vim.log.levels.ERROR)
  end
  local root = vim.uv.fs_realpath(client.root_dir or vim.fn.getcwd())
  busy = true
  local function finish(text, level)
    busy = false
    if text then
      message(text, level)
    end
  end

  local function request(new_name)
    local ok, err = pcall(function()
      assert(api.nvim_buf_is_valid(origin), 'Source buffer is gone')
      assert(#M.dirty(root) == 0, 'Project buffers are still modified; no rename requested')
      local snapshot = M.snapshot(root)
      local params = vim.lsp.util.make_position_params(origin_win, client.offset_encoding)
      params.newName = new_name
      client:request('textDocument/rename', params, function(rerr, result)
        vim.schedule(function()
          if rerr then
            return finish('Server refused the rename: ' .. (rerr.message or vim.inspect(rerr)), vim.log.levels.ERROR)
          end
          local plan, reason = M.prepare(snapshot, result, client.offset_encoding)
          if not plan then
            return finish('Rename refused, nothing applied: ' .. reason, vim.log.levels.ERROR)
          end
          local preview_win = show_diff(M.preview(plan))
          vim.ui.select({ 'Cancel', 'Apply reviewed rename' }, {
            prompt = ('Rename to %s in %d file(s)? Applied edits stay unsaved.'):format(new_name, #plan.files),
          }, function(choice)
            if api.nvim_win_is_valid(preview_win) then
              api.nvim_win_close(preview_win, true)
            end
            if api.nvim_win_is_valid(origin_win) then
              api.nvim_set_current_win(origin_win)
            end
            if choice ~= 'Apply reviewed rename' then
              return finish('Cancelled; no rename edits applied')
            end
            local applied, problem, rollback = M.apply(plan)
            if not applied then
              local details = rollback and #rollback > 0 and ('; rollback failed: ' .. table.concat(rollback, '; ')) or ''
              return finish('Rename refused: ' .. problem .. details, vim.log.levels.ERROR)
            end
            finish(('Renamed in %d buffer(s); review, save, then run the tests'):format(#plan.files))
          end)
        end)
      end, origin)
    end)
    if not ok then
      finish('Rename refused before applying: ' .. tostring(err):gsub('^[^:]+:%d+: ', ''), vim.log.levels.ERROR)
    end
  end

  local function with_name(new_name)
    if not new_name or new_name == '' then
      return finish('Cancelled')
    end
    local changed = M.dirty(root)
    if #changed == 0 then
      return request(new_name)
    end
    local names = vim.tbl_map(function(entry)
      return entry.path:sub(#root + 2)
    end, changed)
    vim.ui.select({ 'Cancel', 'Save project buffers and rename' }, {
      prompt = ('Save %d modified project file(s) first? %s'):format(#changed, table.concat(names, ', ')),
    }, function(choice)
      if choice ~= 'Save project buffers and rename' then
        return finish('Cancelled; unsaved changes kept')
      end
      local saved, failure = M.save(root)
      if not saved then
        return finish(failure, vim.log.levels.ERROR)
      end
      request(new_name)
    end)
  end

  if name and name ~= '' then
    return with_name(name)
  end
  vim.ui.input({ prompt = 'New name: ', default = vim.fn.expand('<cword>') }, with_name)
end

--- buffer-local rename keys for a kotlin-lsp buffer (replaces the plain rename)
function M.attach(buf)
  for _, lhs in ipairs({ 'grn', '<leader>lr', '<leader>lR' }) do
    vim.keymap.set('n', lhs, function()
      M.rename()
    end, { buffer = buf, desc = 'Lsp Rename (guarded)' })
  end
end

function M.setup()
  -- every other plain rename of a Kotlin buffer goes through the guard too,
  -- notably kotlin.nvim's answer to the server's `editor.action.rename` after
  -- Extract variable (spec: inline rename after extract → guarded, save first)
  if not M.plain_rename then
    M.plain_rename = vim.lsp.buf.rename
    vim.lsp.buf.rename = function(new_name, opts)
      opts = opts or {}
      local buf = opts.bufnr or api.nvim_get_current_buf()
      local kotlin = #vim.lsp.get_clients({ bufnr = buf, name = 'kotlin_lsp' }) > 0
      if kotlin and (opts.name == nil or opts.name == 'kotlin_lsp') and opts.filter == nil and buf == api.nvim_get_current_buf() then
        return M.rename(new_name)
      end
      return M.plain_rename(new_name, opts)
    end
  end
  api.nvim_create_user_command('GuardedRename', function(cmd)
    M.rename(cmd.args)
  end, { nargs = '?', desc = 'Kotlin rename: save prompt, whole-edit validation, reviewed diff' })
  api.nvim_create_autocmd('LspAttach', {
    group = api.nvim_create_augroup('guarded-rename', { clear = true }),
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and client.name == 'kotlin_lsp' then
        -- after the generic LSP keymaps of the same event
        vim.schedule(function()
          if api.nvim_buf_is_valid(args.buf) then
            M.attach(args.buf)
          end
        end)
      end
    end,
  })
end

return M
