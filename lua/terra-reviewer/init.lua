local M = {}

local function get_api_key_path()
	local data_dir = vim.fn.stdpath("data") .. "/terra-reviewer"
	vim.fn.mkdir(data_dir, "p")
	return data_dir .. "/api_key"
end

function M.set_api_key()
	vim.ui.input({
		prompt = "Enter Terra Reviewer API Key: ",
	}, function(input)
		if not input or input == "" then
			vim.notify("Cancelled", vim.log.levels.WARN)
			return
		end

		local path = get_api_key_path()
		local file = io.open(path, "w")

		if not file then
			vim.notify("Failed to save API KEY", vim.log.levels.ERROR)
			return
		end

		file:write(input)
		file:close()

		if vim.fn.has("unix") == 1 then
			vim.fn.system("chmod 600" .. vim.fn.shellescape(path))
		else
			pcall(function()
				vim.fn.system('icacls "' .. path .. '" /inheritance:r /grant:r "%USERNAME%":F')
			end)
		end
		vim.notify("API Key saved successfully", vim.log.levels.INFO)
	end)
end

function M.get_api_key()
	local path = get_api_key_path()
	if vim.fn.filereadable(path) ~= 1 then
		return nil
	end

	local lines = vim.fn.readfile(path)
	if not lines or #lines == 0 then
		return nil
	end

	-- readfile 返回的是行数组，我们只存了一行
	local key = lines[1]
	if not key then
		return nil
	end

	-- 去掉末尾空白
	return (key:gsub("%s+$", ""))
end

function M.clear_api_key()
	local path = get_api_key_path()
	if vim.fn.filereadable(path) == 1 then
		os.remove(path)
		vim.notify("API Key cleared", vim.log.levels.INFO)
	else
		vim.notify("No API Key found", vim.log.levels.WARN)
	end
end

-- local function fetch_queue()
--   local api_key = M.get_api_key()
--   if not  api_key then
--     vim.notify("Please set API Key first!", vim.log.levels.WARN)
--     return nil
--   end
--
--   local url = "https://api.terra.hackclub.com/review?filter=waiting"
--   local cmd = string.format(
--     'curl -s -H "Authorization: Bearer %s" -H "Accept: application/json" "%s"',
--     api_key, url
--   )
--
--   local result = vim.fn.system(cmd)
--   local ok, data = pcall(vim.json.decode, result)
--   if not ok or not data or not data.items then
--     vim.notify("Cannot get ", level, opts)
-- end

return M
