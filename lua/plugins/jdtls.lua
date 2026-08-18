-- java lsp
--
-- eclipse.jdt.ls needs a JDK 21+ to *run*, even when the project targets an older release.
-- $JAVA_HOME points at the active asdf install, so the launcher JDK is resolved separately.
local jdtls_jdk_version = '21'

-- Registered with jdtls so projects can target them (see `:JdtSetRuntime`).
local project_runtimes = {
  { name = 'JavaSE-17', version = '17' },
  { name = 'JavaSE-21', version = '21' },
}

---@param version string
---@return string|nil
local function find_jdk(version)
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

local function runtimes()
  local found = {}
  for _, runtime in pairs(project_runtimes) do
    local path = find_jdk(runtime.version)
    if path then
      table.insert(found, { name = runtime.name, path = path })
    end
  end
  return found
end

-- java-debug-adapter, java-test and the spring-boot jdt extensions, handed to jdtls as bundles
local function bundles()
  local jars = vim.fn.glob('$MASON/share/java-debug-adapter/com.microsoft.java.debug.plugin-*.jar', false, true)

  local excluded = {
    'com.microsoft.java.test.runner-jar-with-dependencies.jar',
    'jacocoagent.jar',
  }
  for _, jar in pairs(vim.fn.glob('$MASON/share/java-test/*.jar', false, true)) do
    if not vim.tbl_contains(excluded, vim.fn.fnamemodify(jar, ':t')) then
      table.insert(jars, jar)
    end
  end

  local ok, spring_boot = pcall(require, 'spring_boot')
  if ok then
    vim.list_extend(jars, spring_boot.java_extensions())
  end

  return jars
end

return {
  'mfussenegger/nvim-jdtls',
  dependencies = {
    'mason-org/mason.nvim',
    'JavaHello/spring-boot.nvim',
  },
  ft = 'java',
  keys = {
    { '<leader>joi', '<CMD>lua require("jdtls").organize_imports()<CR>', desc = 'Java Organize imports' },
    { '<leader>jev', '<CMD>lua require("jdtls").extract_variable_all()<CR>', desc = 'Java Extract variable' },
    { '<leader>jec', '<CMD>lua require("jdtls").extract_constant()<CR>', desc = 'Java Extract constant' },
    {
      '<leader>jev',
      '<ESC><CMD>lua require("jdtls").extract_variable_all(true)<CR>',
      mode = 'v',
      desc = 'Java Extract variable',
    },
    {
      '<leader>jec',
      '<ESC><CMD>lua require("jdtls").extract_constant(true)<CR>',
      mode = 'v',
      desc = 'Java Extract constant',
    },
    {
      '<leader>jem',
      '<ESC><CMD>lua require("jdtls").extract_method(true)<CR>',
      mode = 'v',
      desc = 'Java Extract method',
    },
    { '<leader>jgs', '<CMD>lua require("jdtls").super_implementation()<CR>', desc = 'Java Go to super implementation' },
    { '<leader>jtc', '<CMD>lua require("jdtls.dap").test_class()<CR>', desc = 'Java Debug test class' },
    { '<leader>jtn', '<CMD>lua require("jdtls.dap").test_nearest_method()<CR>', desc = 'Java Debug nearest test' },
    { '<leader>jtp', '<CMD>lua require("jdtls.dap").pick_test()<CR>', desc = 'Java Debug pick test' },
    { '<leader>jb', '<CMD>JdtBytecode<CR>', desc = 'Java Show bytecode' },
    { '<leader>jl', '<CMD>JdtShowLogs<CR>', desc = 'Java Show logs' },
    { '<leader>jr', '<CMD>JdtRestart<CR>', desc = 'Java Restart language server' },
    { '<leader>ju', '<CMD>JdtUpdateConfig<CR>', desc = 'Java Update project config' },
    { '<leader>jw', '<CMD>JdtWipeDataAndRestart<CR>', desc = 'Java Wipe workspace and restart' },
  },
  opts = function()
    -- mason is lazy loaded on cmd/keys, force it so $MASON is set
    pcall(require, 'mason-registry')

    local cmd = { vim.fn.expand('$MASON/bin/jdtls') }

    local launcher_jdk = find_jdk(jdtls_jdk_version)
    if launcher_jdk then
      table.insert(cmd, '--java-executable=' .. launcher_jdk .. '/bin/java')
    end

    vim.list_extend(cmd, {
      -- lombok is used by nearly every spring boot project, jdtls needs it as an agent
      '--jvm-arg=-javaagent:' .. vim.fn.expand('$MASON/share/jdtls/lombok.jar'),
      '--jvm-arg=-XX:+UseParallelGC',
      '--jvm-arg=-XX:GCTimeRatio=4',
      '--jvm-arg=-XX:AdaptiveSizePolicyWeight=90',
      '--jvm-arg=-Dsun.zip.disableMemoryMapping=true',
      '--jvm-arg=-Xms128m',
      '--jvm-arg=-Xmx4g',
    })

    return {
      cmd = cmd,

      root_markers = {
        'settings.gradle',
        'settings.gradle.kts',
        'pom.xml',
        'build.gradle',
        'build.gradle.kts',
        'mvnw',
        'gradlew',
        '.git',
      },

      dap = { hotcodereplace = 'auto', config_overrides = {} },
      -- scanning for main classes is slow on large multi module projects, set to false to skip
      dap_main = {},

      settings = {
        java = {
          eclipse = { downloadSources = true },
          maven = { downloadSources = true },
          gradle = { enabled = true },
          configuration = {
            runtimes = runtimes(),
            updateBuildConfiguration = 'interactive',
          },
          implementationsCodeLens = { enabled = true },
          referencesCodeLens = { enabled = true },
          references = { includeDecompiledSources = true },
          contentProvider = { preferred = 'fernflower' },
          signatureHelp = { enabled = true },
          inlayHints = { parameterNames = { enabled = 'all' } },
          format = { enabled = true },
          sources = {
            organizeImports = { starThreshold = 9999, staticStarThreshold = 9999 },
          },
          completion = {
            importOrder = { 'java', 'javax', 'jakarta', 'org', 'com' },
            favoriteStaticMembers = {
              'org.assertj.core.api.Assertions.*',
              'org.junit.jupiter.api.Assertions.*',
              'org.junit.jupiter.api.Assumptions.*',
              'org.mockito.ArgumentMatchers.*',
              'org.mockito.Mockito.*',
              'org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*',
              'org.springframework.test.web.servlet.result.MockMvcResultHandlers.*',
              'org.springframework.test.web.servlet.result.MockMvcResultMatchers.*',
              'java.util.Objects.requireNonNull',
              'java.util.Objects.requireNonNullElse',
            },
          },
          codeGeneration = {
            toString = {
              template = '${object.className}{${member.name()}=${member.value}, ${otherMembers}}',
            },
            useBlocks = true,
            hashCodeEquals = { useJava7Objects = true },
          },
        },
      },
    }
  end,
  config = function(_, opts)
    local lspconfig = require('lsp-opts')
    local jdtls = require('jdtls')

    local function attach_jdtls()
      local buffer_path = vim.api.nvim_buf_get_name(0)
      local root_dir = vim.fs.root(buffer_path ~= '' and buffer_path or 0, opts.root_markers)
      local project_name = root_dir and vim.fs.basename(root_dir) or 'default'
      local project_cache = vim.fn.stdpath('cache') .. '/jdtls/' .. project_name

      local cmd = vim.deepcopy(opts.cmd)
      vim.list_extend(cmd, {
        '-configuration',
        project_cache .. '/config',
        '-data',
        project_cache .. '/workspace',
      })

      local extended_capabilities = jdtls.extendedClientCapabilities
      extended_capabilities.resolveAdditionalTextEditsSupport = true

      jdtls.start_or_attach({
        name = 'jdtls',
        cmd = cmd,
        root_dir = root_dir,
        settings = opts.settings,
        handlers = {
          -- jdtls serves requests off a resolved compilation unit and answers
          -- null until the project is loaded. record readiness so hover can wait
          -- for it. the echo mirrors nvim-jdtls' own status handler, which this
          -- one replaces.
          ['language/status'] = function(_, result)
            if not result then
              return
            end
            if result.type == 'ServiceReady' then
              lspconfig.jdtls_ready[root_dir or ''] = true
            end
            if result.message then
              vim.api.nvim_echo({ { result.message:sub(1, vim.v.echospace), 'Function' } }, false, {})
            end
          end,
        },
        capabilities = lspconfig.capabilities,
        on_init = lspconfig.on_init,
        init_options = {
          bundles = bundles(),
          extendedClientCapabilities = extended_capabilities,
        },
      })
    end

    vim.api.nvim_create_augroup('Jdtls', { clear = true })
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'java',
      group = 'Jdtls',
      callback = attach_jdtls,
    })

    vim.api.nvim_create_autocmd('LspAttach', {
      group = 'Jdtls',
      callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if not client or client.name ~= 'jdtls' then
          return
        end
        jdtls.setup_dap(opts.dap)
        if opts.dap_main then
          require('jdtls.dap').setup_dap_main_class_configs(opts.dap_main)
        end
      end,
    })

    -- the FileType autocmd above does not fire for the buffer that lazy loaded this plugin
    attach_jdtls()
  end,
}
