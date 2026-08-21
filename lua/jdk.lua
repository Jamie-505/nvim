-- shared JDK resolution.
--
-- $JAVA_HOME points at the active asdf install, which may be older than a given
-- tool needs (eclipse.jdt.ls and kotlin-lsp both want 21+ to run, even when the
-- project targets an older release). Resolve a specific version separately.
local M = {}

---@param version string
---@return string|nil
function M.find(version)
  if vim.fn.executable('/usr/libexec/java_home') == 1 then
    local home = vim.fn.system({ '/usr/libexec/java_home', '-v', version })
    if vim.v.shell_error == 0 then
      return vim.trim(home)
    end
  end

  for _, path in ipairs({
    '/Library/Java/JavaVirtualMachines/openjdk-' .. version .. '/Contents/Home',
    vim.fn.expand('~/.asdf/installs/java/openjdk-' .. version),
    '/usr/lib/jvm/java-' .. version .. '-openjdk',
  }) do
    if vim.fn.isdirectory(path) == 1 then
      return path
    end
  end
end

return M
