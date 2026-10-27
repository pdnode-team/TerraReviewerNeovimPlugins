vim.api.nvim_create_user_command("TerraSetApiKey", function(opts)
	require("terra-reviewer").set_api_key()
end, { desc = "Set Terra Reviewer API Key" })

vim.api.nvim_create_user_command("TerraClearApiKey", function()
	require("terra-reviewer").clear_api_key()
end, { desc = "Clear Terra Reviewer API Key" })
