-- Add to lazy.setup(), or save as lua/plugins/nvim-rex.lua in LazyVim.
-- Use matching shortcuts in Rex's setup({ mappings = ... }).
local mappings = {
  left = "<M-h>", down = "<M-j>", up = "<M-k>", right = "<M-l>",
}

return {
  {
    "theboxer/nvim-rex",
    main = "rex-splits",
    event = "VeryLazy",
    cond = function()
      return vim.env.REX_SESSION ~= nil and vim.env.REX_SESSION ~= ""
        and vim.env.REX_BLOCK ~= nil and vim.env.REX_BLOCK ~= ""
    end,
    opts = { mappings = mappings },
    keys = function()
      local keys = {}
      for direction, key in pairs(mappings) do
        local target = direction
        keys[#keys + 1] = {
          key,
          function() require("rex-splits").navigate(target) end,
          desc = "Navigate " .. direction .. " (Neovim/Rex)",
        }
      end
      return keys
    end,
  },
}
