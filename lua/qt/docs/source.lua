-- Finds installed Qt documentation, one entry per Qt version.
local M = {}
local uv = vim.uv or vim.loop
local cached

local function isdir(p)
  local s = uv.fs_stat(p)
  return s ~= nil and s.type == "directory"
end

-- version attribute of the <INDEX ...> tag (not the <?xml version="1.0"?> one)
local function read_version(root)
  local f = io.open(root .. "/qtcore/qtcore.index", "r")
  if not f then return nil end
  local head = f:read(800) or ""
  f:close()
  return head:match('<INDEX[^>]-version="([%d%.]+)"')
end

local function vkey(v)
  local a, b, c = v:match("^(%d+)%.(%d+)%.?(%d*)")
  return { tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0 }
end

local function newer(a, b)
  local x, y = vkey(a.version), vkey(b.version)
  for i = 1, 3 do
    if x[i] ~= y[i] then return x[i] > y[i] end
  end
  return false
end

local function candidates()
  local out = {}
  local home = vim.fn.expand("~")
  -- Qt installer layout: ~/Qt/Docs/Qt-<version>
  for _, base in ipairs({ home .. "/Qt/Docs", "/opt/Qt/Docs" }) do
    if isdir(base) then
      for _, name in ipairs(vim.fn.readdir(base)) do
        if name:match("^Qt%-") then table.insert(out, base .. "/" .. name) end
      end
    end
  end
  -- distro packages
  for _, p in ipairs({ "/usr/share/doc/qt6", "/usr/share/doc/qt5", "/usr/share/doc/qt" }) do
    table.insert(out, p)
  end
  -- user-defined roots (config.docs.paths)
  local ok, cfg = pcall(function() return require("qt.config").get() end)
  for _, p in ipairs((ok and cfg and cfg.docs and cfg.docs.paths) or {}) do
    table.insert(out, vim.fn.expand(p))
  end
  return out
end

--- All installed doc sets, newest first: { { version = "6.10.2", root = "..." }, ... }
function M.list(refresh)
  if cached and not refresh then return cached end
  local seen, out = {}, {}
  for _, root in ipairs(candidates()) do
    if not seen[root] and isdir(root) then
      seen[root] = true
      local v = read_version(root)
      if v then table.insert(out, { version = v, root = root }) end
    end
  end
  table.sort(out, newer)
  cached = out
  return out
end

--- Doc set for a version prefix ("6.5" matches 6.5.10). Without argument:
--- config.docs.version if set, otherwise the newest installed.
function M.get(want)
  local list = M.list()
  if not want then
    local ok, cfg = pcall(function() return require("qt.config").get() end)
    want = ok and cfg and cfg.docs and cfg.docs.version or nil
  end
  if not want then return list[1] end
  for _, k in ipairs(list) do
    if vim.startswith(k.version .. ".", tostring(want) .. ".") then return k end
  end
  return nil
end

--- Online fallback, e.g. online_url("6.10.2", "qobject.html#connect")
function M.online_url(version, page)
  local major = tostring(version):match("^(%d+)") or "6"
  return ("https://doc.qt.io/qt-%s/%s"):format(major, page or "")
end

return M
