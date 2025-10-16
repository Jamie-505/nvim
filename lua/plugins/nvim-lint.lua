return {
  'mfussenegger/nvim-lint',
  dependencies = {
    'rachartier/tiny-inline-diagnostic.nvim',
  },
  ft = function()
    return require('mason-opts').get_linter_filetypes()
  end,
  config = function()
    local lint = require('lint')
    local mason_config = require('mason-opts')
    lint.linters_by_ft = mason_config.get_filetype_linter_nvim_lint_map()

    vim.schedule(function()
      vim.diagnostic.config({ virtual_text = false })
    end)

    vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
      callback = function()
        if vim.opt_local.modifiable:get() then
          lint.try_lint()
        end
      end,
    })
  end,
}
