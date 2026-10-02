---@type LazySpec
return {
  "folke/flash.nvim",
  opts = {
    -- Label matches during / and ? searches as well.
    modes = { search = { enabled = true } },
  },
  keys = {
    { "<C-s>", mode = "c", function() require("flash").toggle() end, desc = "Toggle Flash Search" },
  },
}
