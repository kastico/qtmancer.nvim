-- Turns "what the user is pointing at" into index entries.
local M = {}

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Qualified identifier at a 1-based column. Cursor on `connect` in
--- `QObject::connect` gives "QObject::connect"; on `QObject` gives "QObject".
function M.token_at(line, col)
	local init = 1
	while true do
		local s, e = line:find("[%w_:]+", init)
		if not s then
			return nil
		end
		if col >= s and col <= e then
			local run = line:sub(s, e)
			local names, chosen = {}, nil
			for a, name, b in run:gmatch("()([%w_]+)()") do
				table.insert(names, name)
				if col >= s + a - 1 and col <= s + b - 2 then
					chosen = #names
				end
			end
			if #names == 0 then
				return nil
			end
			chosen = chosen or #names
			return table.concat(names, "::", 1, chosen), names[chosen]
		end
		init = e + 1
	end
end

function M.under_cursor()
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2] + 1
	return (M.token_at(line, col))
end

--- Text of the visual selection (while in visual mode, or from the last one
--- when called from an ex command such as :'<,'>QtDocs).
function M.selection()
	local mode = vim.fn.mode()
	local a, b, kind
	if mode:match("^[vV\22]") then
		a, b, kind = vim.fn.getpos("v"), vim.fn.getpos("."), mode
	else
		a, b, kind = vim.fn.getpos("'<"), vim.fn.getpos("'>"), vim.fn.visualmode()
	end
	local ok, lines = pcall(vim.fn.getregion, a, b, { type = kind })
	if not ok or not lines then
		return nil
	end
	return trim(table.concat(lines, " "))
end

--- Class that declares the symbol under the cursor, according to the LSP
--- (clangd hover prints "// In ClassName"). Returns nil if unavailable.
function M.lsp_class()
	local clients = vim.lsp.get_clients({ bufnr = 0 })
	if #clients == 0 then
		return nil
	end
	local enc = clients[1].offset_encoding or "utf-16"
	local params = vim.lsp.util.make_position_params(0, enc)
	local ok, res = pcall(vim.lsp.buf_request_sync, 0, "textDocument/hover", params, 400)
	if not ok or not res then
		return nil
	end
	for _, r in pairs(res) do
		local c = r.result and r.result.contents
		local text
		if type(c) == "string" then
			text = c
		elseif type(c) == "table" then
			text = c.value or (c[1] and (c[1].value or c[1]))
		end
		if type(text) == "string" then
			local cls = text:match("// In ([%w_:]+)")
			if cls then
				return cls
			end
		end
	end
	return nil
end

--- One entry per distinct fullname (overloads share a page, so keep the first).
function M.distinct(entries)
	local seen, out = {}, {}
	for _, e in ipairs(entries) do
		if not seen[e.f] then
			seen[e.f] = true
			table.insert(out, e)
		end
	end
	return out
end

local function qml_type(set, name)
	if not name:match("^%u") then
		return {}
	end
	local by_full = require("qt.docs.index").load(set).by_full
	local suffix = "." .. name
	local out = {}
	for full, list in pairs(by_full) do
		if #full > #suffix and full:sub(-#suffix) == suffix and not full:find("::", 1, true) then
			table.insert(out, list[1])
		end
	end
	table.sort(out, function(a, b)
		if #a.f ~= #b.f then
			return #a.f < #b.f
		end
		return a.f < b.f
	end)
	return out
end

--- Looks the text up in the index. Tries the full name, then the last segment,
--- then shorter prefixes ("Qt::AlignLeft" -> "AlignLeft" -> "Qt").
--- opts.class restricts bare member names to that class when it has a match.
function M.resolve(set, text, opts)
	opts = opts or {}
	local index = require("qt.docs.index")
	local name = (text or ""):match("[%a_][%w_:]*")
	if not name then
		return {}, nil
	end
	name = name:gsub(":+$", "")

	local parts = vim.split(name, "::", { plain = true, trimempty = true })
	local tries = { name }
	if #parts > 1 then
		table.insert(tries, parts[#parts])
		for i = #parts - 1, 1, -1 do
			table.insert(tries, table.concat(parts, "::", 1, i))
		end
	end

	for _, q in ipairs(tries) do
		if vim.bo.filetype == "qml" then
			local qml = qml_type(set, q)
			if #qml > 0 then
				return qml, q
			end
		end
		local found = index.lookup(set, q, opts)
		if #found > 0 then
			if opts.class then
				local own = vim.tbl_filter(function(e)
					return e.f == opts.class .. "::" .. q
				end, found)
				if #own > 0 then
					found = own
				end
			end
			return found, q
		end
	end
	return {}, name
end

--- Fallback: case-insensitive substring search over all fullnames.
function M.search(set, text, limit)
	local needle = (text or ""):lower()
	if needle == "" then
		return {}
	end
	local by_full = require("qt.docs.index").load(set).by_full
	local out = {}
	for full, list in pairs(by_full) do
		if full:lower():find(needle, 1, true) then
			table.insert(out, list[1])
		end
	end
	table.sort(out, function(a, b)
		if (a.k == "class") ~= (b.k == "class") then
			return a.k == "class"
		end
		if #a.f ~= #b.f then
			return #a.f < #b.f
		end
		return a.f < b.f
	end)
	local trimmed = {}
	for i = 1, math.min(#out, limit or 50) do
		trimmed[i] = out[i]
	end
	return trimmed
end

return M
