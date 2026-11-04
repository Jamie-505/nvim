-- spring boot language server (bean/endpoint navigation, application.properties & yml completion)
return {
  'JavaHello/spring-boot.nvim',
  dependencies = { 'mfussenegger/nvim-jdtls' },
  -- YAML-first: application*.yml / application*.properties start the server
  -- (spring-boot.nvim gates the file names). Kotlin is kotlin-lsp's alone.
  ft = { 'java', 'yaml', 'jproperties' },
  cmd = { 'SpringClasspathRefresh' },
  -- the pickers need no plugin: beans/endpoints are a text search, live data
  -- asks a running spring-boot client (and warns when there is none)
  init = function()
    local function map(lhs, fn, desc)
      vim.keymap.set('n', lhs, function()
        require('spring-pickers')[fn]()
      end, { desc = desc })
    end
    map('<leader>jsb', 'beans', 'Java Spring Find beans')
    map('<leader>jse', 'endpoints', 'Java Spring Find endpoints')
    map('<leader>jsl', 'live', 'Java Spring Live data (running app)')
  end,
  opts = function()
    -- spring boot ls wants a modern jdk, $JAVA_HOME may point at an older asdf install
    local java_home = require('jdk').find('25')
    local server = require('spring-classpath').server_config()
    -- Keep jdtls responsible for Java inlay hints.
    server.handlers['textDocument/inlayHint'] = function() end
    server.filetypes = { 'java', 'yaml', 'jproperties' }
    server.settings = {
      ['boot-java'] = {
        -- live data (<leader>jsl) discovers local JVMs only with this; server default: off
        ['live-information'] = { ['all-local-java-processes'] = true },
      },
    }
    return {
      java_cmd = java_home and java_home .. '/bin/java' or nil,
      log_file = vim.fn.stdpath('state') .. '/spring-boot-ls.log',
      jvm_args = {
        -- type indexing from the Gradle classpath (no jdtls in Kotlin projects)
        '-Dlanguageserver.boot.enable-jandex-index=true',
        -- no embedded web server: it only hosts the MCP server, a localhost
        -- listener nobody uses (what the VS Code extension passes when
        -- boot-java.ai.mcp-server-enabled is off; -Dspring.ai.mcp.server.enabled
        -- alone left the listener up)
        '-Dspring.main.web-application-type=NONE',
      },
      server = server,
    }
  end,
  config = function(_, opts)
    require('spring_boot').setup(opts)
    vim.api.nvim_create_user_command('SpringClasspathRefresh', function()
      require('spring-classpath').refresh()
    end, { desc = 'Re-export the Gradle classpath and send it to the Spring server' })
  end,
}
