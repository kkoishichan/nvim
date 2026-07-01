-- Minimal offline dictionary: query the ECDICT sqlite database directly and show
-- only word + phonetic + Chinese translation in a small float. No animation, no
-- icons, no exam tags -- closes on cursor movement, like other transient floats.

local M = {}

local DB = vim.fn.expand("~/.local/share/trans/ultimate.db")
local ns = vim.api.nvim_create_namespace("user_dict")
local state = { win = nil, autocmd = nil }

local function close()
	if state.autocmd then
		pcall(vim.api.nvim_del_autocmd, state.autocmd)
	end
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		pcall(vim.api.nvim_win_close, state.win, true)
	end
	state.win, state.autocmd = nil, nil
end

-- Returns phonetic, translation (translation may contain embedded newlines).
local function query(word)
	word = vim.trim(word):gsub("'", "''")
	if word == "" then
		return nil
	end
	local sql = ("SELECT phonetic, translation FROM stardict WHERE word = '%s' COLLATE NOCASE LIMIT 1;"):format(word)
	local res = vim.system({ "sqlite3", "-separator", "\t", DB, sql }, { text = true }):wait()
	if res.code ~= 0 then
		return nil
	end
	local out = vim.trim(res.stdout or "")
	if out == "" then
		return nil
	end
	local phonetic, translation = out:match("^([^\t]*)\t(.*)$")
	if not translation then
		phonetic, translation = "", out
	end
	return phonetic, translation
end

-- header may be nil (e.g. sentence translation has no word/phonetic line).
local function open_float(header, body)
	close()

	local lines = {}
	if header and header ~= "" then
		lines[#lines + 1] = header
	end
	local has_header = #lines > 0
	for _, l in ipairs(vim.split(vim.trim(body), "\n", { plain = true })) do
		l = vim.trim(l)
		if l ~= "" then
			lines[#lines + 1] = l
		end
	end
	if #lines == 0 then
		return
	end

	local width = 0
	for _, l in ipairs(lines) do
		width = math.max(width, vim.fn.strdisplaywidth(l))
	end
	width = math.min(math.max(width, 16), 64)
	local height = 0
	for _, l in ipairs(lines) do
		height = height + math.max(1, math.ceil(vim.fn.strdisplaywidth(l) / width))
	end
	height = math.min(height, 16)

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	if has_header then
		vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { end_row = 1, hl_group = "Title" })
	end
	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = "wipe"

	local win = vim.api.nvim_open_win(buf, false, {
		relative = "cursor",
		row = 1,
		col = 0,
		width = width,
		height = height,
		style = "minimal",
		-- Borderless background block on a Pmenu bg, matching the completion docs
		-- and LSP hover. Left/right padding only (no lines), like blink's "padded".
		border = { " ", "", "", " ", "", "", " ", " " },
		focusable = false,
		noautocmd = true,
	})
	vim.wo[win].wrap = true
	vim.wo[win].winhighlight = "NormalFloat:Pmenu,FloatBorder:Pmenu"

	state.win = win
	state.autocmd = vim.api.nvim_create_autocmd(
		{ "CursorMoved", "CursorMovedI", "InsertEnter", "BufLeave", "WinScrolled" },
		{
			once = true,
			callback = close,
		}
	)
end

-- Online machine translation (auto direction -> Chinese) for phrases/sentences.
local function translate_online(text, cb)
	local url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=zh&dt=t"
	vim.system(
		{ "curl", "-sG", "--max-time", "8", "--data-urlencode", "q=" .. text, url },
		{ text = true },
		function(res)
			local out
			if res.code == 0 and res.stdout and res.stdout ~= "" then
				local ok, decoded = pcall(vim.json.decode, res.stdout)
				if ok and type(decoded) == "table" and type(decoded[1]) == "table" then
					local parts = {}
					for _, seg in ipairs(decoded[1]) do
						if type(seg) == "table" and seg[1] then
							parts[#parts + 1] = seg[1]
						end
					end
					out = table.concat(parts)
				end
			end
			vim.schedule(function()
				cb(out)
			end)
		end
	)
end

---Translate text. A single word hits the offline ECDICT dictionary (instant);
---anything with whitespace (phrase/sentence) goes through online translation.
function M.lookup(text)
	text = vim.trim(text or vim.fn.expand("<cword>") or "")
	if text == "" then
		return
	end

	if text:find("%s") then
		open_float(nil, "翻译中…")
		translate_online(text, function(result)
			if result and result ~= "" then
				open_float(nil, result)
			else
				close()
				vim.notify("Translation failed (offline?): " .. text, vim.log.levels.WARN)
			end
		end)
		return
	end

	local phonetic, translation = query(text)
	if not translation then
		vim.notify("No translation: " .. text, vim.log.levels.INFO)
		return
	end
	local header = text
	if phonetic and phonetic ~= "" then
		header = header .. "  /" .. phonetic .. "/"
	end
	open_float(header, translation)
end

---Look up the current visual selection.
function M.lookup_visual()
	local mode = vim.fn.mode()
	local region = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = mode })
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
	M.lookup(table.concat(region, " "))
end

return M
