---@type LazySpec
return {
  "sindrets/diffview.nvim",
  cmd = { "DiffviewClose", "DiffviewFileHistory" },
  specs = {
    {
      "AstroNvim/astrocore",
      opts = function(_, opts)
        local maps = opts.mappings
        maps.n["<Leader>gv"] = {
          function()
            if require("diffview.lib").get_current_view() then
              vim.cmd "DiffviewClose"
            else
              vim.cmd "DiffviewOpen"
            end
          end,
          desc = "Toggle Diffview (working tree)",
        }
        maps.n["<Leader>gh"] = { "<Cmd>DiffviewFileHistory %<CR>", desc = "Git history (current file)" }
      end,
    },
  },
}
