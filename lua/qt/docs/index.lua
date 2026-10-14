-- Symbol index built from the qdoc *.index files (one per Qt module).
-- Entry fields: k=kind n=name f=fullname m=module h=href b=brief s=signature
local M = {}
local uv = vim.uv or vim.loop
local loaded = {}

local KINDS = { class = true, namespace = true, ["function"] = true, property = true, enum = true }

local function unescape(s)
  if not s then return nil end
  return (s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&#39;", "'"):gsub("&amp;", "&"))
end

local function attr(tag, name)
  return tag:match(" " .. name .. '="([^"]*)"')
end

local function parse_module(path, module, out)
  for line in io.lines(path) do
    local kind = line:match("^%s*<(%a+) ")
    if kind and KINDS[kind] then
      local href = attr(line, "href")
      if href and attr(line, "status") == "active" and attr(line, "access") ~= "private" then
        local name = unescape(attr(line, "name"))
        table.insert(out, {
          k = kind,
          n = name,
          f = unescape(attr(line, "fullname")) or name,
          m = module,
          h = href,
          b = unescape(attr(line, "brief")),
          s = unescape(attr(line, "signature")),
        })
      end
    end
  end
end

local function build(set)
  local entries = {}
  for _, dir in ipairs(vim.fn.readdir(set.root)) do
    local idx = ("%s/%s/%s.index"):format(set.root, dir, dir)
    if uv.fs_stat(idx) then parse_module(idx, dir, entries) end
  end
  return entries
end

local function cache_path(set)
  local tag = vim.fn.sha256(set.root):sub(1, 8)
  return ("%s/qt-docs-%s-%s.json"):format(vim.fn.stdpath("cache"), set.version, tag)
end

local function maps(entries)
  local by_full, by_name = {}, {}
  for _, e in ipairs(entries) do
    by_full[e.f] = by_full[e.f] or {}
    table.insert(by_full[e.f], e)
    by_name[e.n] = by_name[e.n] or {}
    table.insert(by_name[e.n], e)
  end
  return { by_full = by_full, by_name = by_name }
end

--- Loads (or builds, the first time) the index for a doc set.
function M.load(set, force)
  if loaded[set.root] and not force then return loaded[set.root] end
  local path = cache_path(set)
  local entries
  if not force then
    local f = io.open(path, "r")
    if f then
      local ok, data = pcall(vim.json.decode, f:read("*a"))
      f:close()
      if ok and type(data) == "table" then entries = data end
    end
  end
  if not entries then
    vim.notify("Qt docs: indexing Qt " .. set.version .. " (first time only)...", vim.log.levels.INFO)
    vim.cmd.redraw()
    entries = build(set)
    vim.fn.mkdir(vim.fn.stdpath("cache"), "p")
    local f = io.open(path, "w")
    if f then
      f:write(vim.json.encode(entries))
      f:close()
    end
  end
  loaded[set.root] = maps(entries)
  return loaded[set.root]
end

--- query: "QObject::connect", "QObject" or a bare name like "connect".
--- opts.class: class around the cursor, used to rank bare member names.
function M.lookup(set, query, opts)
  opts = opts or {}
  local idx = M.load(set)
  local found = idx.by_full[query]
  if found then return found end
  found = idx.by_name[query]
  if not found then return {} end

  local ranked = {}
  for i, e in ipairs(found) do
    local score = 2
    if opts.class and e.f == opts.class .. "::" .. query then
      score = 0
    elseif e.k == "class" then
      score = 1
    end
    ranked[i] = { e = e, score = score, order = i }
  end
  table.sort(ranked, function(a, b)
    if a.score ~= b.score then return a.score < b.score end
    return a.order < b.order
  end)
  return vim.tbl_map(function(r) return r.e end, ranked)
end

return M
