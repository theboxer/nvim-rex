-- Tests against locally installed lazy.nvim and LazyVim; downloads nothing.
local root = vim.fn.getcwd()
vim.go.loadplugins = true
local installed = vim.env.REX_SPLITS_LAZY_ROOT or (vim.fn.stdpath("data") .. "/lazy")
vim.env.REX_SESSION, vim.env.REX_BLOCK, vim.env.HERDR_ENV = "session:test", "block:test", "1"
vim.opt.rtp:prepend(installed .. "/lazy.nvim")
local custom = arg[1] == "alt"
local spec = dofile(root .. (custom and "/examples/lazy-custom.lua" or "/examples/lazy.lua"))
spec[1].dir = root
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
require("lazy").setup({
  spec = spec,
  root = temporary .. "/plugins",
  lockfile = temporary .. "/lock.json",
  install = { missing = false },
  checker = { enabled = false },
  change_detection = { enabled = false },
  readme = { enabled = false },
  performance = { cache = { enabled = false }, rtp = { reset = false } },
})
vim.opt.rtp:prepend(installed .. "/LazyVim")
vim.opt.rtp:prepend(installed .. "/snacks.nvim")
require("snacks")
local safe_map = require("lazyvim.util").safe_keymap_set
local function defaults()
  for _, letter in ipairs({ "h", "j", "k", "l" }) do
    safe_map("n", "<C-" .. letter .. ">", "<C-w>" .. letter, { desc = "LazyVim default", remap = true })
  end
end
defaults()
require("lazy").load({ plugins = { "nvim-rex" } })
defaults() -- Also prove loading defaults after our plugin cannot overwrite it.
for _, letter in ipairs({ "h", "j", "k", "l" }) do
  local key = "<" .. (custom and "M" or "C") .. "-" .. letter .. ">"
  local mapping = vim.fn.maparg(key, "n", false, true)
  assert(mapping.callback and mapping.desc:find("Neovim/Rex", 1, true), "LazyVim replaced " .. letter)
  assert(vim.fn.maparg(key, "t"):find("rex-splits", 1, true))
  if custom then
    assert(vim.fn.maparg("<C-" .. letter .. ">", "n", false, true).desc == "LazyVim default")
    assert(vim.fn.maparg("<C-" .. letter .. ">", "t") == "")
  end
end
vim.fn.delete(temporary, "rf")
print("PASS: published lazy.nvim spec loads rex-splits and preserves all four LazyVim mappings")
