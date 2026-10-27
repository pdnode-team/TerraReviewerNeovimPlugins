local M = {}

function M.duration(seconds)
  local total = tonumber(seconds) or 0
  if total < 0 then
    total = 0
  end
  total = math.floor(total)
  local hours = math.floor(total / 3600)
  local minutes = math.floor((total % 3600) / 60)
  if hours > 0 then
    return string.format("%dh %dm", hours, minutes)
  end
  return string.format("%dm", minutes)
end

function M.flags(item)
  local parts = {}
  if (tonumber(item.danger) or 0) > 0 then
    parts[#parts + 1] = "D"
  end
  if (tonumber(item.warn) or 0) > 0 then
    parts[#parts + 1] = "W"
  end
  if item.hold ~= nil and item.hold ~= "" then
    parts[#parts + 1] = "H"
  end
  return table.concat(parts)
end

-- Queue timestamps are ISO-8601 UTC. decidedAt is "YYYY-MM-DD HH:MM:SS" with no zone.
function M.parse_time(value)
  if type(value) ~= "string" then
    return nil
  end
  local year, month, day, hour, min, sec = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)[T ](%d%d):(%d%d):(%d%d)")
  if not year then
    return nil
  end
  return {
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = tonumber(hour),
    min = tonumber(min),
    sec = tonumber(sec),
    utc = value:find("Z", 1, true) ~= nil,
  }
end

function M.stamp(value)
  local parsed = M.parse_time(value)
  if not parsed then
    return "-"
  end
  return string.format("%02d-%02d %02d:%02d", parsed.month, parsed.day, parsed.hour, parsed.min)
end

local function civil_to_epoch(year, month, day, hour, min, sec)
  local shifted = year - (month <= 2 and 1 or 0)
  local era = math.floor((shifted >= 0 and shifted or shifted - 399) / 400)
  local year_of_era = shifted - era * 400
  local day_of_year = math.floor((153 * (month + (month > 2 and -3 or 9)) + 2) / 5) + day - 1
  local day_of_era = year_of_era * 365 + math.floor(year_of_era / 4) - math.floor(year_of_era / 100) + day_of_year
  local days = era * 146097 + day_of_era - 719468
  return days * 86400 + hour * 3600 + min * 60 + sec
end

function M.ago(value, now)
  local parsed = M.parse_time(value)
  if not parsed or not parsed.utc then
    return nil
  end
  local diff = (now or os.time()) - civil_to_epoch(parsed.year, parsed.month, parsed.day, parsed.hour, parsed.min, parsed.sec)
  if diff < 0 then
    return nil
  end
  if diff < 3600 then
    return string.format("%dm ago", math.floor(diff / 60))
  end
  if diff < 86400 then
    return string.format("%dh ago", math.floor(diff / 3600))
  end
  return string.format("%dd ago", math.floor(diff / 86400))
end

function M.when(value, now)
  local stamp = M.stamp(value)
  local ago = M.ago(value, now)
  if ago then
    return stamp .. "  " .. ago
  end
  return stamp
end

function M.pad(value, width)
  local text = tostring(value or "")
  local display = vim.fn.strdisplaywidth(text)
  if display == width then
    return text
  end
  if display < width then
    return text .. string.rep(" ", width - display)
  end
  if width <= 1 then
    return vim.fn.strcharpart(text, 0, 1)
  end

  local ellipsis = "…"
  local budget = width - vim.fn.strdisplaywidth(ellipsis)
  local kept = {}
  local used = 0
  for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    local char_width = vim.fn.strdisplaywidth(char)
    if used + char_width > budget then
      break
    end
    kept[#kept + 1] = char
    used = used + char_width
  end
  local trimmed = table.concat(kept) .. ellipsis
  local gap = width - vim.fn.strdisplaywidth(trimmed)
  if gap > 0 then
    trimmed = trimmed .. string.rep(" ", gap)
  end
  return trimmed
end

function M.text(value)
  if value == nil or value == "" then
    return "-"
  end
  return tostring(value)
end

return M
