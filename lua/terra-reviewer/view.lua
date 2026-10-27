local api = require("terra-reviewer.api")
local format = require("terra-reviewer.format")

local M = {}

local HEADER_LINES = 3
local ns = vim.api.nvim_create_namespace("terra-reviewer")

local COL = {
  flags = 4,
  week = 4,
  time = 8,
  user = 16,
  claim = 14,
  decision = 10,
}

local EMPTY = "None"

local queue_buf
local detail_buf
local queue_win
local detail_win
local prev_win
local items = {}
local loading = false
local request_id = 0
local api_key
local autocmds_ready = false

local function buf_valid(buf)
  return buf ~= nil and vim.api.nvim_buf_is_valid(buf)
end

local function win_valid(win)
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function define_highlights()
  local groups = {
    TerraReviewHeader = "Title",
    TerraReviewMuted = "Comment",
    TerraReviewDanger = "DiagnosticError",
    TerraReviewWarn = "DiagnosticWarn",
    TerraReviewHold = "DiagnosticHint",
  }
  for name, link in pairs(groups) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
end

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function configure_buf(buf, name)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
  vim.bo[buf].filetype = "terra-review"
  vim.bo[buf].modifiable = false
  if vim.api.nvim_buf_get_name(buf) ~= name then
    vim.api.nvim_buf_set_name(buf, name)
  end
end

local function configure_queue_win(win)
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].winblend = 0
  vim.wo[win].winhighlight = "Normal:NormalFloat,EndOfBuffer:NormalFloat"
  pcall(function()
    vim.wo[win].winfixbuf = true
  end)
end

local function configure_detail_win(win)
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].cursorline = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].winblend = 15
  vim.wo[win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder,FloatTitle:Title,FloatFooter:Comment,EndOfBuffer:NormalFloat"
  pcall(function()
    vim.wo[win].winfixbuf = true
  end)
end

local function grid()
  local height = vim.o.lines - vim.o.cmdheight
  if height < 1 then
    height = vim.o.lines
  end
  local width = vim.o.columns
  if width < 1 then
    width = 1
  end
  return width, height
end

local function fullscreen_config()
  local width, height = grid()
  return {
    relative = "editor",
    row = 0,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    border = "none",
    focusable = true,
    zindex = 50,
  }
end

local function detail_config(lines)
  local width, height = grid()
  local text_width = 36
  for _, line in ipairs(lines or {}) do
    local display = vim.fn.strdisplaywidth(line)
    if display > text_width then
      text_width = display
    end
  end

  local max_width = math.max(1, math.min(62, width - 4))
  local max_height = math.max(1, math.min(math.floor(height * 0.62), height - 4))
  local box_width = math.min(text_width, max_width)
  local box_height = math.min(math.max(#(lines or {}), 1), max_height)
  if box_width < 1 then
    box_width = 1
  end

  local row = math.floor((height - box_height) / 2)
  local col = math.floor((width - box_width) / 2)
  if row < 1 then
    row = 1
  end
  if col < 1 then
    col = 1
  end
  if row + box_height > height - 1 then
    box_height = math.max(1, height - 1 - row)
  end
  if col + box_width > width - 1 then
    box_width = math.max(1, width - 1 - col)
  end

  return {
    relative = "editor",
    row = row,
    col = col,
    width = box_width,
    height = box_height,
    style = "minimal",
    border = "rounded",
    title = " Review ",
    title_pos = "center",
    footer = " q close ",
    footer_pos = "center",
    focusable = true,
    zindex = 70,
  }
end

local function fit(win, config, setup)
  if not win_valid(win) then
    return
  end
  vim.api.nvim_win_set_config(win, config)
  setup(win)
end

local function close_float(win)
  if win_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

local function close_detail()
  close_float(detail_win)
  if win_valid(queue_win) then
    vim.api.nvim_set_current_win(queue_win)
  end
end

local function close_all()
  close_float(detail_win)
  close_float(queue_win)
  if prev_win and vim.api.nvim_win_is_valid(prev_win) then
    vim.api.nvim_set_current_win(prev_win)
  end
end

local function item_at(row)
  local index = row - HEADER_LINES
  local item = items[index]
  if type(item) == "table" then
    return item
  end
  return nil
end

local function current_item()
  if not win_valid(queue_win) then
    return nil
  end
  return item_at(vim.api.nvim_win_get_cursor(queue_win)[1])
end

local function selected_item()
  local current = current_item()
  if current then
    return current
  end
  return items[1]
end

local function column_header()
  return table.concat({
    format.pad("", COL.flags),
    format.pad("WK", COL.week),
    format.pad("TIME", COL.time),
    format.pad("USER", COL.user),
    format.pad("CLAIM", COL.claim),
    format.pad("DECISION", COL.decision),
    "TITLE",
  }, " ")
end

local function cell(value)
  if value == nil or value == "" then
    return EMPTY
  end
  return tostring(value)
end

local function claim_label(item)
  if item.claimedByMe then
    return "you"
  end
  return cell(item.claimedBy)
end

local function item_line(item)
  return table.concat({
    format.pad(cell(format.flags(item)), COL.flags),
    format.pad(cell(item.weekNumber), COL.week),
    format.pad(format.duration(item.seconds), COL.time),
    format.pad(cell(item.username), COL.user),
    format.pad(claim_label(item), COL.claim),
    format.pad(cell(item.decision), COL.decision),
    cell(item.title),
  }, " ")
end

local function paint_queue(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { end_row = 2, hl_group = "TerraReviewMuted", hl_eol = true })
  for index, item in ipairs(items) do
    if type(item) == "table" then
      local row = HEADER_LINES + index - 1
      local flags = format.flags(item)
      local group
      if flags:find("D", 1, true) then
        group = "TerraReviewDanger"
      elseif flags:find("W", 1, true) then
        group = "TerraReviewWarn"
      elseif flags:find("H", 1, true) then
        group = "TerraReviewHold"
      end
      if group then
        vim.api.nvim_buf_set_extmark(buf, ns, row, 0, { end_col = #flags, hl_group = group })
      end
    end
  end
end

local function render_queue()
  if not buf_valid(queue_buf) then
    return
  end

  local count = #items
  local title
  if loading and count == 0 then
    title = "Terra  review / waiting  loading"
  elseif loading then
    title = string.format("Terra  review / waiting  %d  refreshing", count)
  else
    title = string.format("Terra  review / waiting  %d", count)
  end

  local lines = {
    title,
    "<CR> detail    r refresh    y yank id    q quit",
    column_header(),
  }
  for _, item in ipairs(items) do
    if type(item) == "table" then
      lines[#lines + 1] = item_line(item)
    end
  end
  if not loading and count == 0 then
    lines[#lines + 1] = "Queue is empty."
  end

  local cursor
  if win_valid(queue_win) then
    cursor = vim.api.nvim_win_get_cursor(queue_win)
  end
  set_lines(queue_buf, lines)
  paint_queue(queue_buf)
  if cursor and win_valid(queue_win) then
    local max_row = math.max(vim.api.nvim_buf_line_count(queue_buf), 1)
    cursor[1] = math.min(cursor[1], max_row)
    vim.api.nvim_win_set_cursor(queue_win, cursor)
  end
end

local function field(label, value)
  return string.format("%-12s%s", label, value)
end

local function detail_lines(item)
  if not item then
    return { "No review item selected." }
  end

  local lines = {
    format.text(item.title),
    format.text(item.projectTitle),
  }
  if item.chainTitle and item.chainTitle ~= "" and item.chainTitle ~= item.projectTitle then
    lines[#lines + 1] = field("chain", item.chainTitle)
  end

  local kind = item.isUpdate and "update" or "new"
  local platform_text = "-"
  if type(item.platforms) == "table" and #item.platforms > 0 then
    platform_text = table.concat(item.platforms, ", ")
  elseif type(item.platforms) == "string" and item.platforms ~= "" then
    platform_text = item.platforms
  end
  local evidence = string.format(
    "%s  v%s  built %s",
    format.text(item.evidenceStatus),
    format.text(item.evidenceVersion),
    format.when(item.evidenceBuiltAt)
  )
  local claim = claim_label(item)
  if claim == "-" then
    claim = "unclaimed"
  end

  local more = {
    "",
    field("user", format.text(item.username)),
    field("week", format.text(item.weekNumber)),
    field("logged", format.duration(item.seconds)),
    field("platform", platform_text),
    field("kind", kind),
    field("status", format.text(item.status)),
    field("stage", format.text(item.stage)),
    "",
    field("evidence", evidence),
    field("danger", format.text(item.danger)),
    field("warn", format.text(item.warn)),
    "",
    field("claim", claim),
    field("decision", format.text(item.decision)),
    field("decided by", format.text(item.decidedBy)),
    field("decided at", format.when(item.decidedAt)),
    field("hold", format.text(item.hold)),
    field("hold note", format.text(item.holdNote)),
    field("hold at", format.when(item.holdAt)),
    "",
    field("queued", format.when(item.queuedAt)),
    field("submitted", format.when(item.submittedAt)),
    "",
    field("triage", format.text(item.triageTier)),
    field("triaged by", format.text(item.triagedBy)),
    field("id", format.text(item.id)),
    field("project id", format.text(item.projectId)),
    field("chain id", format.text(item.chainId)),
  }
  for _, line in ipairs(more) do
    lines[#lines + 1] = line
  end
  return lines
end

local function render_detail()
  if not buf_valid(detail_buf) then
    return nil
  end
  local lines = detail_lines(selected_item())
  set_lines(detail_buf, lines)
  if win_valid(detail_win) then
    fit(detail_win, detail_config(lines), configure_detail_win)
  end
  return lines
end

local function place_cursor_on_first_item()
  if not win_valid(queue_win) or #items == 0 then
    return
  end
  vim.api.nvim_win_set_cursor(queue_win, { HEADER_LINES + 1, 0 })
end

function M.refresh()
  if not api_key or not buf_valid(queue_buf) then
    return
  end
  request_id = request_id + 1
  local token = request_id
  loading = true
  render_queue()

  api.fetch(api_key, function(data, err)
    if token ~= request_id or not buf_valid(queue_buf) then
      return
    end
    loading = false
    if err then
      vim.notify(err, vim.log.levels.ERROR)
      render_queue()
      return
    end
    items = data.items
    render_queue()
    if win_valid(queue_win) and current_item() == nil then
      place_cursor_on_first_item()
    end
    if win_valid(detail_win) then
      render_detail()
    end
  end)
end

local function yank_id()
  local item = current_item()
  if not item or not item.id then
    vim.notify("No review item on this line", vim.log.levels.WARN)
    return
  end
  vim.fn.setreg('"', item.id)
  pcall(vim.fn.setreg, "+", item.id)
  vim.notify("Yanked " .. item.id, vim.log.levels.INFO)
end

local function open_detail()
  if #items == 0 then
    return
  end
  if not buf_valid(detail_buf) then
    detail_buf = vim.api.nvim_create_buf(false, true)
    configure_buf(detail_buf, "terra://review-item")
    local function map_detail(lhs)
      vim.keymap.set("n", lhs, close_detail, {
        buffer = detail_buf,
        nowait = true,
        silent = true,
        desc = "Close Terra review detail",
      })
    end
    map_detail("q")
    map_detail("<Esc>")
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = detail_buf,
      callback = function()
        detail_buf = nil
      end,
    })
  end

  local lines = render_detail()
  if not win_valid(detail_win) then
    detail_win = vim.api.nvim_open_win(detail_buf, true, detail_config(lines))
    configure_detail_win(detail_win)
  else
    fit(detail_win, detail_config(lines), configure_detail_win)
    vim.api.nvim_set_current_win(detail_win)
  end
end

local function ensure_autocmds()
  if autocmds_ready then
    return
  end
  autocmds_ready = true
  local group = vim.api.nvim_create_augroup("terra-reviewer", { clear = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(event)
      local closed = tonumber(event.match)
      if closed == queue_win then
        queue_win = nil
      end
      if closed == detail_win then
        detail_win = nil
      end
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = define_highlights,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      fit(queue_win, fullscreen_config(), configure_queue_win)
      if win_valid(detail_win) and buf_valid(detail_buf) then
        local lines = vim.api.nvim_buf_get_lines(detail_buf, 0, -1, false)
        fit(detail_win, detail_config(lines), configure_detail_win)
      end
    end,
  })
end

local function map_queue(buf)
  local function map(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  map("<CR>", open_detail, "Open Terra review detail")
  map("r", M.refresh, "Refresh Terra review queue")
  map("y", yank_id, "Yank Terra review id")
  map("q", close_all, "Close Terra review")
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    callback = function()
      if win_valid(detail_win) then
        render_detail()
      end
    end,
  })
end

function M.open(key)
  api_key = key
  define_highlights()
  ensure_autocmds()

  if not buf_valid(queue_buf) then
    queue_buf = vim.api.nvim_create_buf(false, true)
    configure_buf(queue_buf, "terra://review")
    map_queue(queue_buf)
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = queue_buf,
      callback = function()
        queue_buf = nil
        items = {}
      end,
    })
  end

  local current = vim.api.nvim_get_current_win()
  if current ~= queue_win and current ~= detail_win then
    prev_win = current
  end

  if not win_valid(queue_win) then
    queue_win = vim.api.nvim_open_win(queue_buf, true, fullscreen_config())
    configure_queue_win(queue_win)
  else
    fit(queue_win, fullscreen_config(), configure_queue_win)
    vim.api.nvim_set_current_win(queue_win)
  end

  M.refresh()
end

return M
