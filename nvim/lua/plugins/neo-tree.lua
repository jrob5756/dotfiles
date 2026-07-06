-- Custom Neo-tree overrides
-- Config documentation: https://github.com/nvim-neo-tree/neo-tree.nvim

---@type LazySpec
return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = {
    window = {
      mappings = {
        -- switch between Neo-tree source tabs (Files/Buffers/Git) with Shift+Arrow,
        -- matching the buffer navigation remap in astrocore.lua
        ["<S-Right>"] = "next_source",
        ["<S-Left>"] = "prev_source",
      },
    },
    -- the Git Status source doesn't follow directory changes (`.` or `:cd`) by default,
    -- unlike the Files/Buffers sources, so it can show stale results after switching dirs
    git_status = {
      bind_to_cwd = true,
    },
  },
  config = function(_, opts)
    require("neo-tree").setup(opts)

    -- NOTE: `bind_to_cwd = true` above only makes git_status *re-render its existing path*
    -- on DirChanged, it doesn't actually move to the new cwd (that's a Neo-tree quirk —
    -- Files/Buffers sources use a "follow cwd" helper internally that git_status doesn't).
    -- Reuse that same helper directly so git_status behaves consistently with the others.
    vim.api.nvim_create_autocmd("DirChanged", {
      desc = "Point Neo-tree's git_status source at the new working directory",
      callback = function()
        if package.loaded["neo-tree"] then require("neo-tree.sources.manager").dir_changed("git_status") end
      end,
    })
  end,
}
