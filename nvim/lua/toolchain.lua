local M = {}

M.nix = vim.env.DOTFILES_NIX == "1"

local sdk_available

--- Returns whether the current PATH provides a working .NET SDK.
function M.have_dotnet_sdk()
  if sdk_available == nil then
    sdk_available = false
    if vim.fn.executable "dotnet" == 1 then
      local output = vim.fn.system { "dotnet", "--list-sdks" }
      sdk_available = vim.v.shell_error == 0 and output:match "%S" ~= nil
    end
  end
  return sdk_available
end

--- Returns an active-environment or PATH Python interpreter, or nil.
function M.python()
  -- The Nix wrapper pins tools on PATH, but project environments still own Python analysis.
  for _, variable in ipairs { "VIRTUAL_ENV", "CONDA_PREFIX" } do
    local root = vim.env[variable]
    if root and root ~= "" then
      local suffixes = vim.fn.has "win32" == 1 and { "/Scripts/python.exe", "/python.exe" }
        or { "/bin/python", "/bin/python3" }
      for _, suffix in ipairs(suffixes) do
        local interpreter = root .. suffix
        if vim.fn.executable(interpreter) == 1 then return interpreter end
      end
    end
  end
  for _, name in ipairs { "python", "python3" } do
    local path = vim.fn.exepath(name)
    if path ~= "" then return path end
  end
end

--- Returns a directly executable debugpy adapter on PATH, or nil.
function M.debugpy_adapter()
  local path = vim.fn.exepath "debugpy-adapter"
  -- DAP spawns without a shell, so Windows batch shims need the Python fallback.
  if path ~= "" and not path:lower():match "%.cmd$" and not path:lower():match "%.bat$" then return path end
end

--- Returns a PATH interpreter that can import debugpy, or nil.
function M.debugpy_python()
  for _, name in ipairs { "python", "python3" } do
    local path = vim.fn.exepath(name)
    if path ~= "" then
      vim.fn.system { path, "-c", "import debugpy" }
      if vim.v.shell_error == 0 then return path end
    end
  end
end

return M
