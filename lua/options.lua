local opt = vim.opt
local o = vim.o
local g = vim.g

-------------------------------------- globals -----------------------------------------
g.mapleader = ' '
g.maplocalleader = ' '

-------------------------------------- options ------------------------------------------
o.laststatus = 3
o.showmode = false
o.confirm = true

vim.schedule(function()
  o.clipboard = 'unnamedplus'
end)
o.cursorline = true
o.cursorlineopt = 'number'
o.relativenumber = true
o.wrap = false
o.scrolloff = 5

o.textwidth = 0

opt.spell = false

-- Indenting
o.expandtab = true
o.shiftwidth = 2
o.smartindent = true
o.tabstop = 2
o.softtabstop = 2

opt.fillchars = { eob = ' ' }
o.ignorecase = true
o.smartcase = true
o.mouse = 'a'

-- Numbers
o.number = true
o.numberwidth = 2
o.ruler = false

-- disable nvim intro
opt.shortmess:append('sI')

o.signcolumn = 'auto'
o.splitbelow = true
o.splitright = true
o.inccommand = 'split'
o.timeoutlen = 400
o.undofile = true

-- interval for writing swap file to disk, also used by gitsigns
o.updatetime = 250

o.sessionoptions = 'blank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions'

-- go to previous/next line with h,l,left arrow and right arrow
-- when cursor reaches end/beginning of line
opt.whichwrap:append('<>[]hl')

-- disable some default providers
g['loaded_node_provider'] = 0
g['loaded_python3_provider'] = 0
g['loaded_perl_provider'] = 0
g['loaded_ruby_provider'] = 0

-- add binaries installed by mason.nvim to path
local is_windows = vim.fn.has('win32') ~= 0
local sep = is_windows and '\\' or '/'
local delim = is_windows and ';' or ':'
vim.env.PATH = table.concat({ vim.fn.stdpath('data'), 'mason', 'bin' }, sep) .. delim .. vim.env.PATH

-- vim window options
-- vim.opt.colorcolumn = "160"
