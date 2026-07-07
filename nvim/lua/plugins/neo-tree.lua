-- Custom Neo-tree overrides
-- Config documentation: https://github.com/nvim-neo-tree/neo-tree.nvim

-- Windows-only: remap the live `/` filter (fuzzy_finder) to Neo-tree's single-shot
-- `filter_on_submit` (type, then `<Enter>` to search once). Neo-tree cancels the previous
-- in-flight search on every keystroke via `vim.fn.system("taskkill ...")`, and each cancel
-- pays Windows process-spawn cost. (The catastrophic multi-second version of this was the
-- profile-loading `pwsh` shell — fixed by `-NoProfile` in astrocore.lua — but even a plain
-- spawn per keystroke is worth avoiding.) macOS/Linux keep the live fuzzy filter, which isn't
-- affected there. Gated behind `has("win32")`, no-op elsewhere.
local filesystem_opts = {}
if vim.fn.has "win32" == 1 then
  filesystem_opts = {
    filesystem = {
      window = {
        mappings = {
          ["/"] = "filter_on_submit",
        },
      },
    },
  }
end

---@type LazySpec
return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = vim.tbl_deep_extend("force", {
    window = {
      mappings = {
        -- switch between Neo-tree source tabs (Files/Buffers/Git) with Shift+Arrow,
        -- matching the buffer navigation remap in astrocore.lua
        ["<S-Right>"] = "next_source",
        ["<S-Left>"] = "prev_source",
        -- make `z`/`Z` a symmetric pair scoped to the highlighted node: `Z` expands all
        -- subnodes recursively, `z` collapses them (overriding the default `z` =
        -- close_all_nodes, which collapses the entire tree)
        ["Z"] = "expand_all_subnodes",
        ["z"] = "close_all_subnodes",
      },
    },
    -- the Git Status source doesn't follow directory changes (`.` or `:cd`) by default,
    -- unlike the Files/Buffers sources, so it can show stale results after switching dirs
    git_status = {
      bind_to_cwd = true,
    },
  }, filesystem_opts),
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
