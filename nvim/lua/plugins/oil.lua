-- Oil stays command-loaded, so Neo-tree still owns directory arguments.

---@type LazySpec
return {
  "stevearc/oil.nvim",
  specs = {
    {
      "AstroNvim/astrocore",
      opts = function(_, opts) opts.mappings.n["-"] = { "<Cmd>Oil<CR>", desc = "Open parent directory in Oil" } end,
    },
  },
}
