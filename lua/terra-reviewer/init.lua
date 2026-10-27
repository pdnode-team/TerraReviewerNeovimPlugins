local M = {}

local function api()
  return require("terra-reviewer.api")
end

function M.set_api_key()
  api().set_api_key()
end

function M.clear_api_key()
  api().clear_api_key()
end

function M.open()
  if vim.fn.has("nvim-0.10") ~= 1 then
    vim.notify("terra-reviewer.nvim needs Neovim 0.10 or newer", vim.log.levels.ERROR)
    return
  end
  if vim.fn.executable("curl") ~= 1 then
    vim.notify("curl was not found on PATH", vim.log.levels.ERROR)
    return
  end
  local key = api().get_api_key()
  if not key then
    vim.notify("No Terra API key. Run :TerraSetApiKey", vim.log.levels.WARN)
    return
  end
  require("terra-reviewer.view").open(key)
end

return M
