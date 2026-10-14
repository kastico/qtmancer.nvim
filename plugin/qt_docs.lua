if vim.g.loaded_qt_docs then
	return
end
vim.g.loaded_qt_docs = true

vim.api.nvim_create_user_command("QtDocs", function(o)
	local docs = require("qt.docs")
	if o.args ~= "" then
		return docs.open(o.args)
	end
	docs.open_cursor(o.range > 0)
end, { nargs = "?", range = true, desc = "Qt docs: symbol under cursor, selection or query" })

vim.api.nvim_create_user_command("QtDocsVersions", function()
	require("qt.docs").versions()
end, { desc = "List installed Qt documentation sets" })

vim.api.nvim_create_user_command("QtDocsReindex", function()
	require("qt.docs").reindex()
end, { desc = "Rebuild the Qt docs symbol index" })

vim.api.nvim_create_user_command("QtDocsBrowser", function()
	require("qt.docs").pick_browser()
end, { desc = "Choose the terminal browser for Qt docs" })
