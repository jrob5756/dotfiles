-- Customize ToggleTerm mappings
--
-- Windows-only: add explicit terminal pickers for PowerShell 5 (`powershell.exe`),
-- PowerShell 7+ (`pwsh.exe`), and cmd.exe (`cmd.exe`). Without these, `vim.o.shell`
-- on Windows defaults to `cmd.exe`, so `<F7>`/`ToggleTerm` only ever opens cmd.
-- Guarded behind `has("win32")` so this file is a no-op on macOS/Linux, since this
-- config is shared across all three platforms.

---@type LazySpec
return {
  "akinsho/toggleterm.nvim",
  specs = {
    {
      "AstroNvim/astrocore",
      opts = function(_, opts)
        if vim.fn.has "win32" ~= 1 then return end
        local astro = require "astrocore"
        local maps = opts.mappings

        maps.n["<Leader>tc"] =
          { function() astro.toggle_term_cmd { cmd = "cmd.exe", direction = "float" } end, desc = "ToggleTerm cmd" }

        if vim.fn.executable "powershell" == 1 then
          maps.n["<Leader>t5"] = {
            function() astro.toggle_term_cmd { cmd = "powershell.exe", direction = "float" } end,
            desc = "ToggleTerm PowerShell 5",
          }
        end

        if vim.fn.executable "pwsh" == 1 then
          maps.n["<Leader>t7"] = {
            function() astro.toggle_term_cmd { cmd = "pwsh.exe", direction = "float" } end,
            desc = "ToggleTerm PowerShell 7",
          }
        end
      end,
    },
  },
}
