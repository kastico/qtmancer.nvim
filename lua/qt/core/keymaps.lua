local M = {}

local function edit_ui(qt, file)
  if file:match("%.ui$") then
    qt.open_designer(file)
  else
    require("qt.designer").select_ui_file_to_open()
  end
end

-- { lhs (after the prefix), action, desc, opts }
--   action: method name on require("qt"), or function(qt, current_file)
--   opts.full  -> only in the "full" preset
--   opts.args  -> arguments for a method-name action
--   opts.ctx   -> buffer-local, only for file names matching one of these patterns
--   opts.where -> label shown in the help for buffer-local maps
local specs = {
  { "a", "show_main_interface", "Main interface" },
  { "h", "show_help", "Help" },
  { "p", "new_project_interactive", "New project" },
  { "P", "new_project_quick", "New project (quick, C++17)", { full = true } },
  { "o", "open_project_interactive", "Open project" },
  { "u", "create_new_ui_interactive", "New UI file" },
  { "e", edit_ui, "Edit current / select UI" },
  { "d", "open_designer", "Qt Designer" },
  { "c", "create_class_interactive", "Create class" },
  { "f", "create_class_from_current_ui", "Create class from current UI" },
  { "b", "build_project", "Build" },
  { "r", "run_project", "Run" },
  { "A", "quick_build_and_run", "Build & run", { full = true } },

  { "Dd", "debug_application", "Debug application" },
  { "Da", "attach_to_process", "Attach to process" },

  { "s11", "build_with_std", "Build with C++11", { full = true, args = { "11" } } },
  { "s14", "build_with_std", "Build with C++14", { full = true, args = { "14" } } },
  { "s17", "build_with_std", "Build with C++17", { full = true, args = { "17" } } },
  { "s20", "build_with_std", "Build with C++20", { full = true, args = { "20" } } },

  { "Cc", "show_current_config", "Show config", { full = true } },
  { "Cs", "select_cxx_standard", "Select C++ standard", { full = true } },
  { "Cr", "reconfigure_project", "Reconfigure project", { full = true } },

  { "k", function() require("qt.docs").open_cursor() end, "Docs: symbol / selection", { modes = { "n", "x" } } },
  { "K", function() require("qt.docs").prompt() end, "Docs: search" },

  -- buffer-local (override the global ones above)
  { "d", function(qt, f) qt.open_designer(f) end, "Open this file in Designer",
    { ctx = { "%.ui$" }, where = ".ui" } },
  { "f", function(qt, f) qt.create_class_from_ui_file(f) end, "Generate class from this UI",
    { ctx = { "%.ui$" }, where = ".ui" } },
  { "U", "find_and_open_ui", "Find & open matching UI",
    { ctx = { "%.h$", "%.cpp$" }, where = ".h/.cpp" } },
}
M.specs = specs

local function options()
  local cfg = require("qt.config").get().keymaps or {}
  return {
    prefix = cfg.prefix or "<leader>Q",
    full = tostring(cfg.preset or "minimal"):lower() == "full",
  }
end

local function runner(qt, spec)
  return function()
    local action, o = spec[2], spec[4] or {}
    if type(action) == "function" then
      return action(qt, vim.api.nvim_buf_get_name(0))
    end
    if not qt[action] then
      return vim.notify("Qt: action not available: " .. action, vim.log.levels.ERROR)
    end
    return qt[action](unpack(o.args or {}))
  end
end

local function matches(spec, name)
  for _, pat in ipairs(spec[4].ctx) do
    if name:match(pat) then return true end
  end
  return false
end

function M.setup(qt)
  qt = qt or require("qt")
  local o = options()
  local buffer_specs = {}

  for _, spec in ipairs(specs) do
    local opts = spec[4] or {}
    if opts.ctx then
      table.insert(buffer_specs, spec)
    elseif o.full or not opts.full then
      vim.keymap.set(opts.modes or "n", o.prefix .. spec[1], runner(qt, spec), { desc = "Qt: " .. spec[3] })
    end
  end

  local group = vim.api.nvim_create_augroup("QtKeymaps", { clear = true })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    pattern = { "*.ui", "*.h", "*.cpp" },
    callback = function(ev)
      local name = vim.api.nvim_buf_get_name(ev.buf)
      for _, spec in ipairs(buffer_specs) do
        if matches(spec, name) then
          vim.keymap.set("n", o.prefix .. spec[1], runner(qt, spec),
            { buffer = ev.buf, desc = "Qt: " .. spec[3] })
        end
      end
    end,
  })

  -- which-key is optional
  local ok, wk = pcall(require, "which-key")
  if ok and wk.add then
    wk.add({
      { o.prefix, group = "qt" },
      { o.prefix .. "D", group = "debug" },
      { o.prefix .. "s", group = "C++ standard" },
      { o.prefix .. "C", group = "config" },
    })
  end
end

-- Lines for :QtHelp, built from the same table so they never go stale
function M.help_lines()
  local o = options()
  local lines = { "Keymaps (prefix " .. o.prefix .. "):" }
  for _, spec in ipairs(specs) do
    local opts = spec[4] or {}
    if o.full or not opts.full then
      local where = opts.where and ("  [" .. opts.where .. " files]") or ""
      table.insert(lines, string.format("  %-14s %s%s", o.prefix .. spec[1], spec[3], where))
    end
  end
  return lines
end

return M
