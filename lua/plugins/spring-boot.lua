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
      -- the built-in autocmd resolves root_dir once and reuses it forever, so a
      -- buffer from a second project attaches to the first project's server.
      -- driven per buffer in `config` instead.
      autocmd = false,
    }
  end,
  config = function(_, opts)
    -- returns the resolved opts (ls_path filled in from mason or vscode), or nil
    -- when the language server could not be found
    local resolved = require('spring_boot').setup(opts)
    if not resolved then
      return
    end

    local launch = require('spring_boot.launch')
    local function start()
      -- rebuild per buffer, update_ls_config derives root_dir from the current one
      launch.start(launch.update_ls_config(resolved))
    end

    vim.api.nvim_create_autocmd('FileType', {
      group = vim.api.nvim_create_augroup('SpringBoot', { clear = true }),
      pattern = { 'java', 'yaml', 'jproperties' },
      callback = start,
    })

    start()
  end,
}
