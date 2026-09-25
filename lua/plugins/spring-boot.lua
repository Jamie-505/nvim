-- spring boot language server (bean/endpoint navigation, application.properties & yml completion)
return {
  'JavaHello/spring-boot.nvim',
  dependencies = { 'mfussenegger/nvim-jdtls' },
  ft = { 'java', 'kotlin', 'jproperties' },
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
    local java_home = require('jdk').find('25')
    return {
      filetypes = { 'java', 'kotlin', 'yaml', 'jproperties' },
      java_cmd = java_home and java_home .. '/bin/java' or nil,
    }
  end,
  config = function(_, opts)
    vim.lsp.config('spring-boot', {
      handlers = {
        -- Keep jdtls responsible for Java inlay hints.
        ['textDocument/inlayHint'] = function() end,
      },
    })
    require('spring_boot').setup(opts)
  end,
}
