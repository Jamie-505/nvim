local autocmd = vim.api.nvim_create_autocmd
local augroup = vim.api.nvim_create_augroup -- Create/get autocommand group

local numberToggleGroup = augroup('numberToggles', {})

autocmd({ 'WinLeave', 'FocusLost' }, {
  callback = function()
    if vim.wo.number == true then
      vim.wo.relativenumber = false
    end
  end,
  group = numberToggleGroup,
  pattern = '*',
})

autocmd({ 'WinEnter', 'FocusGained' }, {
  callback = function()
    if vim.wo.number == true then
      vim.wo.relativenumber = true
    end
  end,
  group = numberToggleGroup,
  pattern = '*',
})

-- Spellcheck for specific files
local spell_types = { 'text', 'plaintex', 'plaintext', 'typst', 'gitcommit', 'markdown' }

-- Create an augroup for spellcheck to group related autocommands
vim.api.nvim_create_augroup('Spellcheck', { clear = true })

vim.api.nvim_create_autocmd({ 'FileType' }, {
  group = 'Spellcheck',
  pattern = spell_types,
  callback = function()
    vim.opt_local.spell = true
  end,
  desc = 'Enable spellcheck for defined filetypes',
})
