if vim.g.loaded_terra_reviewer == 1 then
  return
end
vim.g.loaded_terra_reviewer = 1

vim.api.nvim_create_user_command("TerraSetApiKey", function()
  require("terra-reviewer").set_api_key()
end, { desc = "Save the Terra reviewer API key" })

vim.api.nvim_create_user_command("TerraClearApiKey", function()
  require("terra-reviewer").clear_api_key()
end, { desc = "Delete the saved Terra reviewer API key" })

vim.api.nvim_create_user_command("TerraReview", function()
  require("terra-reviewer").open()
end, { desc = "Open the Terra waiting review queue" })
