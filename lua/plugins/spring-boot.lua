-- spring boot language server (bean/endpoint navigation, application.properties & yml completion)
return {
  'JavaHello/spring-boot.nvim',
  dependencies = { 'mfussenegger/nvim-jdtls' },
  ft = { 'java', 'yaml', 'jproperties' },
  keys = {
    {
      '<leader>jsb',
      function()
        require('telescope.builtin').lsp_dynamic_workspace_symbols({
          initial_mode = 'insert',
          default_text = '@+ ',
        })
      end,
      desc = 'Java Spring Find beans',
    },
    {
      '<leader>jse',
      function()
        require('telescope.builtin').lsp_dynamic_workspace_symbols({
          initial_mode = 'insert',
          default_text = '@/ ',
        })
      end,
      desc = 'Java Spring Find endpoints',
    },
  },
  opts = function()
    -- spring boot ls wants a modern jdk, $JAVA_HOME may point at an older asdf install
    local java_home = vim.fn.executable('/usr/libexec/java_home') == 1
        and vim.trim(vim.fn.system({ '/usr/libexec/java_home', '-v', '21' }))
      or nil
    return {
      java_cmd = (java_home and vim.v.shell_error == 0) and java_home .. '/bin/java' or nil,
    }
  end,
}
