local M = {}

M.filetype_lsp_map = function()
  local filetype_table = {
    angularls = 'htmlangular',
    bashls = 'sh',
    cssls = 'css',
    docker_compose_language_service = 'yaml.docker-compose',
    dockerls = 'docker',
    emmet_language_server = {
      'htmlangular',
      'htcss',
      'eruby',
      'html',
      'htmldjango',
      'javascriptreact',
      'less',
      'pug',
      'sass',
      'scss',
      'typescriptreactml',
    },
    eslint = {
      'javascript',
      'typescript',
    },
    jsonls = 'json',
    pyright = 'python',
    qmlls = 'qml',
    rust_analyzer = 'rust',
    terraformls = 'tf',
    ts_ls = 'typescript',
    yamlls = 'yaml',
  }
  if vim.fn.executable('go') == 1 then
    filetype_table.hyprls = 'hyprlang'
  end
  return filetype_table
end

M.filetype_linter_map = function()
  return {
    lua = 'luacheck',
    markdown = 'markdownlint',
    sh = 'shellcheck',
    dart = 'trivy',
  }
end

M.get_language_server_names = function()
  local names = {}
  for lsp, _ in pairs(M.filetype_lsp_map()) do
    table.insert(names, lsp)
  end
  return names
end

M.get_linter_names = function()
  local names = {}
  for _, entry in pairs(M.filetype_linter_map()) do
    if type(entry) == 'table' then
      for _, linter_name in pairs(entry) do
        table.insert(names, linter_name)
      end
    else
      table.insert(names, entry)
    end
  end
  return names
end

M.get_all_ensure_installed = function()
  local all = M.get_language_server_names()
  for _, linter in pairs(M.get_linter_names()) do
    table.insert(all, linter)
  end
  return all
end

M.get_lsp_filetypes = function()
  local filetypes = {}
  for _, entry in pairs(M.filetype_lsp_map()) do
    if type(entry) == 'table' then
      for _, filetype in pairs(entry) do
        table.insert(filetypes, filetype)
      end
    else
      table.insert(filetypes, entry)
    end
  end
  return filetypes
end

M.get_linter_filetypes = function()
  local filetypes = {}
  for filetype, _ in pairs(M.filetype_linter_map()) do
    table.insert(filetypes, filetype)
  end
  return filetypes
end

M.get_filetype_linter_nvim_lint_map = function()
  local result = {}
  for filetype, linter_name_or_table in pairs(M.filetype_linter_map()) do
    if type(linter_name_or_table) == 'table' then
      local linters = {}
      for _, linter in pairs(linter_name_or_table) do
        table.insert(linters, linter)
      end
      result[filetype] = linters
    else
      result[filetype] = { linter_name_or_table }
    end
  end
  return result
end

M.get_all_ensure_installed_mason_names = function()
  local name_table = {
    'angular-language-server',
    'bash-language-server',
    'css-lsp',
    'dart-debug-adapter',
    'docker-compose-language-service',
    'dockerfile-language-server',
    'emmet-language-server',
    'eslint-lsp',
    'js-debug-adapter',
    'json-lsp',
    -- "latexindent",
    -- "ltex-ls",
    'lua-language-server',
    'luacheck',
    'markdownlint',
    'prettier',
    'pyright',
    'qmlls',
    'roslyn',
    'rust-analyzer',
    'shellcheck',
    'shfmt',
    'sonarlint-language-server',
    'stylua',
    -- "texlab",
    'terraform-ls',
    'trivy',
    'typescript-language-server',
    'yaml-language-server',
    'yamlfmt',
  }
  if vim.fn.executable('go') == 1 then
    table.insert(name_table, 'hyprls')
  end
  return name_table
end

M.options = {
  ensure_installed_mason_names = M.get_all_ensure_installed_mason_names(),

  PATH = 'skip',

  ui = {
    icons = {
      package_pending = ' ',
      package_installed = '󰄳 ',
      package_uninstalled = ' 󰚌',
    },

    keymaps = {
      toggle_server_expand = '<CR>',
      install_server = 'i',
      update_server = 'u',
      check_server_version = 'c',
      update_all_servers = 'U',
      check_outdated_servers = 'C',
      uninstall_server = 'X',
      cancel_installation = '<C-c>',
    },
  },

  max_concurrent_installers = 10,
  registries = {
    'github:mason-org/mason-registry',
    'github:Crashdummyy/mason-registry',
  },
}

return M
