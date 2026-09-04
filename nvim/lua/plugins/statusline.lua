-- Show the file's total line count in the statusline.
--
-- AstroNvim's built-in `nav` component renders `line:col`, a percentage and a
-- scrollbar, but never the total number of lines, and its ruler format is
-- hardcoded in astroui. So rather than fight that component, this appends an
-- extra one next to it.
--
-- Inserting (rather than replacing an entry by index) keeps this resilient to
-- AstroNvim reordering its default statusline in a future release.

---@type LazySpec
return {
  "rebelot/heirline.nvim",
  opts = function(_, opts)
    local status = require "astroui.status"

    local total_lines = status.component.builder {
      { provider = function() return ("%d lines"):format(vim.fn.line "$") end },
      surround = { separator = "right", color = "nav_bg" },
      hl = status.hl.get_attributes "nav",
      padding = { left = 1, right = 1 },
    }

    -- Position before the trailing mode component so it sits beside `nav`.
    table.insert(opts.statusline, #opts.statusline, total_lines)
    return opts
  end,
}
