-- ClassPages layout checker for the session simulator. Computes the screen rectangle of every visible region below a
-- root frame (window, edit toolbar, popover) from its anchors, sizes and an estimate of text widths, then reports:
--   * regions sticking out of the root,
--   * overlapping siblings (text, buttons, edit boxes, skinned frames),
--   * button labels wider than their button.
-- Text widths are estimates per font (average glyph width of the WoW fonts); a small tolerance avoids noise.
-- Usage: local Layout = dofile(".../layout.lua"); local problems = Layout.Check(rootFrame, uiParent)
local Layout = {}

local GLYPH = { small = 5.6, normal = 6.6, large = 8.8 }
local LINE = { small = 12, normal = 14, large = 18 }
local TOL = 1.5
local MIN_GAP, MIN_PAD = 3, 3

local function fontClass(f)
  local font = tostring(f._font or "GameFontHighlightSmall")
  if font:find("Large") then return "large" end
  if font:find("Small") then return "small" end
  return "normal"
end

Layout.FontClass = fontClass

local function plain(text)
  text = tostring(text or "")
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "MMM")
  local n = 0
  for _ in text:gmatch("[^\128-\191]") do n = n + 1 end
  return n
end

function Layout.TextWidth(f)
  return plain(f._text) * GLYPH[fontClass(f)]
end

local function anchorXY(rect, point)
  local x = point:find("LEFT") and rect.l or point:find("RIGHT") and rect.r or (rect.l + rect.r) / 2
  local y = point:find("TOP") and rect.t or point:find("BOTTOM") and rect.b or (rect.b + rect.t) / 2
  return x, y
end

local function size(f)
  if f._kind == "FontString" then
    local tw = Layout.TextWidth(f)
    local w = f._wSet and f._w or tw
    local lines = 1
    if f._wSet and not f._nowrap and f._w > 0 then lines = math.max(1, math.ceil(tw / f._w)) end
    local h = f._hSet and f._h or lines * LINE[fontClass(f)]
    return w, h
  end
  return f._w or 0, f._h or 0
end

-- rect = { l, r, b, t } in UIParent coordinates (y up); nil when the region has no anchors
local function rect(f, cache, ui)
  if f == ui then return { l = 0, r = ui._w, b = 0, t = ui._h } end
  if cache[f] ~= nil then return cache[f] or nil end
  cache[f] = false
  local pts = f._points
  if not pts or not next(pts) then return nil end
  local w, h = size(f)
  local l, r, b, t, cx, cy
  for point, a in pairs(pts) do
    local rel = a.rel or f._parent or ui
    local rr = rect(rel, cache, ui)
    if not rr then return nil end
    local ax, ay = anchorXY(rr, a.relPoint or point)
    ax, ay = ax + (a.x or 0), ay + (a.y or 0)
    if point:find("LEFT") then l = ax elseif point:find("RIGHT") then r = ax else cx = ax end
    if point:find("TOP") then t = ay elseif point:find("BOTTOM") then b = ay else cy = ay end
  end
  if l and not r then r = l + w elseif r and not l then l = r - w elseif not l then l, r = (cx or 0) - w / 2, (cx or 0) + w / 2 end
  if t and not b then b = t - h elseif b and not t then t = b + h elseif not t then b, t = (cy or 0) - h / 2, (cy or 0) + h / 2 end
  local out = { l = l, r = r, b = b, t = t }
  cache[f] = out
  return out
end
Layout.Rect = function(f, ui) return rect(f, {}, ui) end

local function visible(f, root)
  local cur = f
  while cur do
    if not cur._shown then return false end
    if cur == root then return true end
    cur = cur._parent
  end
  return false
end

local function under(f, root)
  local cur = f._parent
  while cur do
    if cur == root then return true end
    cur = cur._parent
  end
  return false
end

local function name(f)
  local text = f._kind == "FontString" and f._text or (f.label and f.label._text) or f._name
  return ("%s%s"):format(f._kind, text and text ~= "" and (" '" .. tostring(text):sub(1, 40) .. "'") or "")
end

local function content(f)
  if f._kind == "FontString" then return f._text ~= nil and f._text ~= "" end
  if f._kind == "Texture" then return false end
  return f._kind == "Button" or f._kind == "EditBox" or f._kind == "CheckButton" or f._kind == "StatusBar" or f._kind == "Slider" or f.cpSkin ~= nil
end

function Layout.Check(root, ui, frames)
  local problems, cache = {}, {}
  local rr = rect(root, cache, ui)
  if not rr or not root._shown then return problems end
  local byParent = {}
  for _, f in ipairs(frames) do
    if f ~= root and under(f, root) and visible(f, root) and content(f) then
      local fr = rect(f, cache, ui)
      if fr then
        if fr.l < rr.l - TOL or fr.r > rr.r + TOL or fr.b < rr.b - TOL or fr.t > rr.t + TOL then
          problems[#problems + 1] = ("sticks out of %s: %s"):format(tostring(root._name), name(f))
        end
        -- content must also stay inside its own card / row / button (skinned parent)
        local p = f._parent
        local pr = p and p ~= root and p.cpSkin and rect(p, cache, ui)
        -- text keeps MIN_PAD px to the top and bottom edge of its card / row / button
        if pr and f._kind == "FontString" and not tostring(f._font):find("^NumberFont") and (pr.t - fr.t < MIN_PAD or fr.b - pr.b < MIN_PAD) and fr.t <= pr.t + TOL and fr.b >= pr.b - TOL then
          problems[#problems + 1] = ("no vertical padding in its %s: %s"):format(name(p), name(f))
        end
        if pr and (fr.l < pr.l - TOL or fr.r > pr.r + TOL or fr.b < pr.b - TOL or fr.t > pr.t + TOL) then
          problems[#problems + 1] = ("sticks out of its %s: %s"):format(name(p), name(f))
        end
        byParent[f._parent] = byParent[f._parent] or {}
        table.insert(byParent[f._parent], { f = f, r = fr })
        if f.label and f.label._text and f.label._text ~= "" and f._kind == "Button" then
          local tw = Layout.TextWidth(f.label)
          if tw > (f._w or 0) - 6 then problems[#problems + 1] = ("label wider than button (%d > %d): %s"):format(tw, (f._w or 0) - 6, name(f)) end
        end
      end
    end
  end
  for _, list in pairs(byParent) do
    for i = 1, #list do
      for j = i + 1, #list do
        local a, b = list[i].r, list[j].r
        local ox = math.min(a.r, b.r) - math.max(a.l, b.l)
        local oy = math.min(a.t, b.t) - math.max(a.b, b.b)
        if ox > 2 and oy > 2 then
          problems[#problems + 1] = ("overlap: %s <> %s"):format(name(list[i].f), name(list[j].f))
        elseif ox > 2 and oy > -MIN_GAP and list[i].f._kind == "FontString" and list[j].f._kind == "FontString" then
          -- stacked texts closer than MIN_GAP px read as one block
          problems[#problems + 1] = ("too close (%.0f px): %s <> %s"):format(-oy, name(list[i].f), name(list[j].f))
        end
      end
    end
  end
  table.sort(problems)
  return problems
end

return Layout
