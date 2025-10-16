local map = vim.keymap.set

-- Lazy
map("n", "L", "<cmd>Lazy<CR>", { desc = "Lazy Open" })

map("i", "jk", "<ESC>", { desc = "Escape with jk" })

map("n", "<leader><leader>", "<S-v>", { desc = "Enter visual line mode" })
map("n", "<leader>nb", "<C-o>", { desc = "Navigate back" })
map("n", "<leader>nf", "<C-i>", { desc = "Navigate forward" })
map("n", "<leader>q", "<CMD>q<CR>", { desc = "Quit window" })
map("n", "<leader>Q", "<CMD>q!<CR>", { desc = "Force quit window" })
map("n", "<leader>w", "<CMD>w<CR>", { desc = "Save file" })
map("n", "<leader>os", "<CMD>silent !open '%'<CR>", { desc = "open current file with OS handler" })

-- Buffer
map("n", "<leader>bn", "<cmd>enew<CR>", { desc = "Buffer New" })

-- Tabs
map("n", "<C-Tab>", "<cmd>tabnext<CR>", { desc = "Tab Next" })
map("n", "<C-S-Tab>", "<cmd>tabprevious<CR>", { desc = "Tab Previous" })

-- Move lines
map("i", "<M-k>", "<cmd> m-2<CR>", { desc = "Move Move line up" })
map("i", "<M-j>", "<cmd> m+1<CR>", { desc = "Move Move line down" })
map("i", "<M-h>", "<cmd><<CR>", { desc = "Move Move line left" })
map("i", "<M-l>", "<cmd>><CR>", { desc = "Move Move line right" })

-- Highlights
map("n", "<Esc>", "<cmd>noh<CR>", { desc = "General Clear all highlights" })
map("n", "<leader>a", "ggVG<CR>", { desc = "Highlight Highlight all" })

-- Diagnostics
map("n", "<leader>ldf", vim.diagnostic.open_float, { desc = "Diagnostics Floating diagnostics" })
map("n", "<leader>ldp", function()
  vim.diagnostic.jump { count = -1 }
end, { desc = "Diagnostics Prev diagnostic" })
map("n", "<leader>ldn", function()
  vim.diagnostic.jump { count = 1 }
end, { desc = "Diagnostics Next diagnostic" })
map("n", "<leader>ldl", vim.diagnostic.setloclist, { desc = "Diagnostics Diagnostic loclist" })

-- Terminal
map("t", "<C-x>", "<C-\\><C-N>", { desc = "Terminal escape terminal mode" })

-- Transparency
-- map("n", "<leader>tt", function()
--   require("colors").toggle_transparency()
-- end, { desc = "Toggle Transparency" })
