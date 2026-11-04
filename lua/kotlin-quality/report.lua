-- Checkstyle XML reports from detekt and ktlint-gradle, parsed structurally:
-- tags are scanned with quotes respected, entities decoded, and a report that
-- doesn't open with <checkstyle> and close with </checkstyle> is invalid (a
-- truncated file never reads as "no findings").
local M = {}

local ENTITIES = { lt = '<', gt = '>', amp = '&', quot = '"', apos = "'" }

function M.decode(s)
  return (
    s:gsub('&(#?)([xX]?)(%w+);', function(hash, hex, body)
      if hash == '' then
        return ENTITIES[body] or ('&' .. body .. ';')
      end
      local n = tonumber(body, hex ~= '' and 16 or 10)
      return n and vim.fn.nr2char(n) or ('&#' .. hex .. body .. ';')
    end)
  )
end

--- @return {name: string, attrs: table<string,string>, closing: boolean}[]?, string? err
local function scan(text)
  local tags, i = {}, 1
  while true do
    local s = text:find('<', i, true)
    if not s then
      return tags
    end
    if text:sub(s, s + 3) == '<!--' then
      local e = text:find('-->', s + 4, true)
      if not e then
        return nil, 'unterminated comment'
      end
      i = e + 3
    elseif text:sub(s + 1, s + 1) == '?' then
      local e = text:find('?>', s + 2, true)
      if not e then
        return nil, 'unterminated declaration'
      end
      i = e + 2
    else
      local j, quote = s + 1, nil
      while true do
        j = text:find(quote or '[\'">]', j)
        if not j then
          return nil, 'truncated tag'
        end
        local c = text:sub(j, j)
        if quote then
          quote = nil
        elseif c == '>' then
          break
        else
          quote = c
        end
        j = j + 1
      end
      local body = text:sub(s + 1, j - 1)
      local attrs = {}
      for k, _, v in body:gmatch('([%w:_%.%-]+)%s*=%s*(["\'])(.-)%2') do
        attrs[k] = M.decode(v)
      end
      table.insert(tags, { name = body:match('^/?%s*([%w:_%.%-]+)'), attrs = attrs, closing = body:sub(1, 1) == '/' })
      i = j + 1
    end
  end
end

--- @param path string report file
--- @param base string directory relative file names resolve against
--- @return {file: string, line: integer, column?: integer, severity: string, message: string, rule: string}[]?, string? err
function M.parse(path, base)
  local f = io.open(path, 'r')
  if not f then
    return nil, 'missing'
  end
  local text = f:read('*a')
  f:close()
  local tags, err = scan(text)
  if not tags then
    return nil, 'invalid (' .. err .. ')'
  end
  if #tags == 0 or tags[1].name ~= 'checkstyle' or tags[1].closing then
    return nil, 'invalid (no <checkstyle> root)'
  end
  local last = tags[#tags]
  if not (last.name == 'checkstyle' and last.closing) then
    return nil, 'invalid (no closing </checkstyle>)'
  end
  local out, file = {}, nil
  for _, t in ipairs(tags) do
    if t.name == 'file' and not t.closing then
      file = t.attrs.name
      if file and not vim.startswith(file, '/') then
        file = vim.fs.joinpath(base, file)
      end
      file = file and vim.fs.normalize(file)
    elseif t.name == 'file' and t.closing then
      file = nil
    elseif t.name == 'error' and file then
      table.insert(out, {
        file = file,
        line = tonumber(t.attrs.line) or 1,
        column = tonumber(t.attrs.column),
        severity = t.attrs.severity or '',
        message = t.attrs.message or '',
        rule = t.attrs.source or '',
      })
    end
  end
  return out
end

return M
