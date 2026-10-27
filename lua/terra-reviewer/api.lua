local M = {}

M.URL = "https://api.terra.hackclub.com/review/queue?queue=review&filter=waiting"

local function key_path()
	local dir = vim.fn.stdpath("data") .. "/terra-reviewer"
	vim.fn.mkdir(dir, "p")
	return dir .. "/api_key"
end

function M.get_api_key()
	local path = key_path()
	if vim.fn.filereadable(path) ~= 1 then
		return nil
	end
	local lines = vim.fn.readfile(path)
	local key = lines[1]
	if not key then
		return nil
	end
	key = key:gsub("%s+$", "")
	if key == "" then
		return nil
	end
	return key
end

local function lock_key_file(path)
	if vim.fn.has("unix") == 1 then
		vim.system({ "chmod", "600", path }):wait()
		return
	end
	if vim.fn.executable("icacls") == 1 and vim.env.USERNAME and vim.env.USERNAME ~= "" then
		vim.system({ "icacls", path, "/inheritance:r", "/grant:r", vim.env.USERNAME .. ":F" }):wait()
	end
end

function M.set_api_key()
	local input = vim.fn.inputsecret("Terra API key: ")
	if not input or input == "" then
		vim.notify("Terra API key was not changed", vim.log.levels.WARN)
		return
	end
	input = input:gsub("^%s+", ""):gsub("%s+$", "")
	if input:find('[\r\n"]') then
		vim.notify("Terra API key contains a character this plugin will not store", vim.log.levels.ERROR)
		return
	end

	local path = key_path()
	if vim.fn.writefile({ input }, path) ~= 0 then
		vim.notify("Failed to save the Terra API key", vim.log.levels.ERROR)
		return
	end
	lock_key_file(path)
	vim.notify("Terra API key saved", vim.log.levels.INFO)
end

function M.clear_api_key()
	local path = key_path()
	if vim.fn.filereadable(path) ~= 1 then
		vim.notify("No Terra API key is saved", vim.log.levels.WARN)
		return
	end
	local removed, err = os.remove(path)
	if not removed then
		vim.notify("Failed to delete the Terra API key: " .. tostring(err), vim.log.levels.ERROR)
		return
	end
	vim.notify("Terra API key cleared", vim.log.levels.INFO)
end

function M.parse_response(stdout)
	local text = (stdout or ""):gsub("\r\n", "\n")
	local payload, status_text = text:match("^(.*)\n(%d%d%d)%s*$")
	if not status_text then
		return nil, "curl returned no HTTP status"
	end

	local status = tonumber(status_text)
	if status ~= 200 then
		local snippet = (payload or ""):gsub("%s+", " "):gsub("^%s+", ""):sub(1, 180)
		if snippet ~= "" then
			return nil, string.format("Terra API returned %d: %s", status, snippet)
		end
		return nil, string.format("Terra API returned %d", status)
	end

	local ok, data = pcall(vim.json.decode, payload)
	if not ok or type(data) ~= "table" or type(data.items) ~= "table" then
		return nil, "Terra API returned JSON without an items array"
	end
	return data, nil
end

function M.fetch(api_key, callback)
	local config = table.concat({
		'header = "Authorization: Bearer ' .. api_key .. '"',
		'header = "Accept: application/json"',
		'header = "User-Agent: terra-reviewer.nvim"',
	}, "\n") .. "\n"

	vim.system({
		"curl",
		"--config",
		"-",
		"-sS",
		"--max-time",
		"30",
		"-w",
		"\n%{http_code}",
		"--url",
		M.URL,
	}, { text = true, stdin = config }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				local err = (result.stderr or result.stdout or ""):gsub("%s+$", "")
				if err == "" then
					err = "curl exited " .. tostring(result.code)
				end
				callback(nil, err)
				return
			end
			local data, err = M.parse_response(result.stdout)
			callback(data, err)
		end)
	end)
end

return M
