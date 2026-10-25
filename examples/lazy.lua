-- Add to lazy.setup(), or save as lua/plugins/nvim-rex.lua in LazyVim.
return {
  {
    "theboxer/nvim-rex",
    main = "rex-splits",
    event = "VeryLazy",
    cond = function()
      return vim.env.REX_SESSION ~= nil and vim.env.REX_SESSION ~= ""
        and vim.env.REX_BLOCK ~= nil and vim.env.REX_BLOCK ~= ""
    end,
    opts = {},
    -- Reserve the keys so LazyVim's default mappings cannot replace them.
    keys = {
      { "<C-h>", function() require("rex-splits").navigate("h") end, desc = "Navigate left (Neovim/Rex)" },
      { "<C-j>", function() require("rex-splits").navigate("j") end, desc = "Navigate down (Neovim/Rex)" },
      { "<C-k>", function() require("rex-splits").navigate("k") end, desc = "Navigate up (Neovim/Rex)" },
      { "<C-l>", function() require("rex-splits").navigate("l") end, desc = "Navigate right (Neovim/Rex)" },
    },
  },
}
