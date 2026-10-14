local M = {}
local source = require("qt.docs.source")
local index = require("qt.docs.index")
local resolve = require("qt.docs.resolve")
local uv = vim.uv or vim.loop
local term = { win = nil, buf = nil, chan = nil, browser = nil }

local WARN = vim.log.levels.WARN

local function notify(msg, level)
	vim.notify("Qt docs: " .. msg, level or vim.log.levels.INFO)
end

-- Offline file if it exists, otherwise the online page for that Qt version.
local function target(set, e)
	local rel = e.m .. "/" .. e.h
	local file = (rel:gsub("#.*$", ""))
	local anchor = rel:match("#(.+)$")
	local path = set.root .. "/" .. file
	if uv.fs_stat(path) then
		return "file://" .. path .. (anchor and ("#" .. anchor) or "")
	end
	return source.online_url(set.version, e.h)
end

local term = { win = nil }

local BROWSERS = { "w3m", "links", "elinks", "lynx" } -- ordem de preferência

local function installed_browsers()
	return vim.tbl_filter(function(b)
		return vim.fn.executable(b) == 1
	end, BROWSERS)
end

local function viewer_cmd(url)
	local avail = installed_browsers()
	if #avail == 0 then
		return nil
	end
	local pref = vim.g.qt_docs_browser
	local b = (pref and vim.tbl_contains(avail, pref)) and pref or avail[1]

	local args = { b }
	if b == "lynx" then
		vim.list_extend(args, { "-vikeys", "-nonumbers", "-nolist", "-display_charset=utf-8" })
	elseif b == "w3m" then
		vim.list_extend(args, {
			"-o",
			"display_borders=1",
			"-o",
			"color=1",
			"-o",
			"anchor_color=cyan",
			"-o",
			"visited_color=magenta",
			"-o",
			"mark_color=yellow",
			"-o",
			"confirm_qq=0",
		})
	end
	table.insert(args, url)
	return args
end

local function term_alive()
	return term.win
		and vim.api.nvim_win_is_valid(term.win)
		and term.buf
		and vim.api.nvim_buf_is_valid(term.buf)
		and term.chan
		and vim.fn.jobwait({ term.chan }, 0)[1] == -1
end

local function open_terminal(url)
	local cmd = viewer_cmd(url)
	if not cmd then
		return false
	end

	-- Já está aberto: manda o novo URL ao w3m em vez de o relançar.
	if term_alive() and term.browser == "w3m" then
		vim.api.nvim_set_current_win(term.win)
		-- U = abrir URL; Ctrl-u limpa a linha; Enter confirma
		vim.fn.chansend(term.chan, "U\21" .. url .. "\r")
		vim.cmd("startinsert")
		return true
	end

	if term.win and vim.api.nvim_win_is_valid(term.win) then
		vim.api.nvim_set_current_win(term.win)
	else
		vim.cmd("botright vsplit")
		term.win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_width(term.win, math.floor(vim.o.columns * 0.4))
	end

	local buf = vim.api.nvim_create_buf(false, true)
	local old = vim.api.nvim_win_get_buf(term.win)
	vim.api.nvim_win_set_buf(term.win, buf)
	if old ~= buf and vim.bo[old].buftype == "terminal" then
		vim.api.nvim_buf_delete(old, { force = true })
	end

	term.buf = buf
	term.browser = cmd[1]
	term.chan = vim.fn.termopen(cmd, {
		on_exit = function()
			if term.win and vim.api.nvim_win_is_valid(term.win) then
				vim.api.nvim_win_close(term.win, true)
			end
			term.win, term.buf, term.chan, term.browser = nil, nil, nil, nil
		end,
	})
	vim.keymap.set("t", "<A-h>", [[<C-\><C-n><C-w>h]], { buffer = buf })
	vim.cmd("startinsert")
	return true
end

local function open_entry(set, e)
	local url = target(set, e)
	local viewer = vim.g.qt_docs_viewer or "terminal" -- "terminal" | "browser"

	if viewer == "terminal" then
		if open_terminal(url) then
			return notify(("%s (Qt %s)"):format(e.f, set.version))
		end
		notify("no terminal browser found (w3m/lynx/links/elinks), opening the system browser", WARN)
	end

	local obj, err = vim.ui.open(url)
	if not obj then
		return notify("could not open " .. url .. (err and (": " .. err) or ""), vim.log.levels.ERROR)
	end
	notify(("%s (Qt %s)"):format(e.f, set.version))
end

local function choose(set, list)
	vim.ui.select(list, {
		prompt = "Qt " .. set.version .. " docs:",
		format_item = function(e)
			return ("%s  [%s · %s]"):format(e.f, e.k, e.m)
		end,
	}, function(e)
		if e then
			open_entry(set, e)
		end
	end)
end

--- Opens the docs for `text`.
--- opts.version: Qt version prefix ("5.15"), default = config.docs.version or newest
--- opts.use_lsp: ask the LSP which class declares a bare member name
function M.open(text, opts)
	opts = opts or {}
	text = vim.trim(text or "")
	if text == "" then
		return notify("nothing to look up", WARN)
	end

	local set = source.get(opts.version)
	if not set then
		return notify(
			opts.version and ("no docs installed for Qt " .. opts.version)
				or "no Qt documentation found (install the Documentation component or your distro's qt doc package)",
			WARN
		)
	end

	local entries = resolve.resolve(set, text, { class = opts.class })
	local list = resolve.distinct(entries)

	if #list > 1 and opts.use_lsp and not text:find("::", 1, true) then
		local cls = resolve.lsp_class()
		if cls then
			list = resolve.distinct(resolve.resolve(set, text, { class = cls }))
		end
	end

	if #list == 0 then
		local found = resolve.search(set, text, 50)
		if #found == 0 then
			return notify(('no results for "%s" in Qt %s'):format(text, set.version), WARN)
		end
		return choose(set, found)
	end
	if #list == 1 then
		return open_entry(set, list[1])
	end
	choose(set, list)
end

--- Symbol under the cursor, or the selection when called from visual mode / a range.
function M.open_cursor(range)
	if range == nil then
		range = vim.fn.mode():match("^[vV\22]") ~= nil
	end
	local text = range and resolve.selection() or resolve.under_cursor()
	M.open(text, { use_lsp = not range })
end

function M.prompt()
	vim.ui.input({ prompt = "Qt docs: " }, function(q)
		if q and q ~= "" then
			M.open(q)
		end
	end)
end

function M.versions()
	local list = source.list(true)
	if #list == 0 then
		return notify("no Qt documentation found", WARN)
	end
	local lines = { "Qt docs found (newest first):" }
	for _, k in ipairs(list) do
		table.insert(lines, ("  %-8s %s"):format(k.version, k.root))
	end
	vim.notify(table.concat(lines, "\n"))
end

function M.reindex()
	for _, set in ipairs(source.list(true)) do
		index.load(set, true)
	end
	notify("index rebuilt")
end

function M.pick_browser()
	local avail = installed_browsers()
	if #avail == 0 then
		return notify("no terminal browser installed (w3m, links, elinks, lynx)", WARN)
	end
	vim.ui.select(avail, { prompt = "Qt docs browser:" }, function(b)
		if b then
			vim.g.qt_docs_browser = b
			notify("browser: " .. b)
		end
	end)
end

return M
