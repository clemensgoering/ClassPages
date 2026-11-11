-- ClassPages layout preview: writes an HTML page that redraws a simulated frame tree (window, toolbar, popover) from
-- the same rectangles the layout checker computes. The addon's own art (ClassPages/Media) is drawn from its PNG copies
-- (tools/assets/png) as CSS masks tinted with the vertex colour, cropped by the texture coordinates, so 9-slice
-- panels, shadows, gradients and icons look like in the game. Game icons are placeholders. Texts and colours come
-- from the addon. Used by sim.lua when CP_RENDER=<dir> is set.
local Layout -- set by the loader: dofile("render.lua")(Layout)
local Render = {}

local FONT_PX = { small = 10, normal = 12, large = 16 }
local LAYER = { BACKGROUND = 0, BORDER = 1, ARTWORK = 2, OVERLAY = 3, HIGHLIGHT = 4 }

local function esc(s)
  return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- |cffRRGGBB ... |r -> spans; |T...|t -> small icon box
local function richText(text)
  text = esc(text or "")
  text = text:gsub("|T.-|t", '<i class="ic"></i>')
  text = text:gsub("|c%x%x(%x%x%x%x%x%x)(.-)|r", '<span style="color:#%1">%2</span>')
  text = text:gsub("|c%x%x(%x%x%x%x%x%x)", "")
  return text
end

local function rgba(c, alpha)
  if not c then return nil end
  return ("rgba(%d,%d,%d,%.3f)"):format(math.floor((c[1] or 0) * 255 + 0.5), math.floor((c[2] or 0) * 255 + 0.5), math.floor((c[3] or 0) * 255 + 0.5), alpha or c[4] or 1)
end

local function visible(f, root)
  local cur = f
  while cur do
    if not cur._shown then return false end
    if cur == root then return true end
    cur = cur._parent
  end
  return false
end

local function depth(f)
  local d, cur = 0, f
  while cur and cur._parent do d = d + 1; cur = cur._parent end
  return d
end

-- CSS masks must be same-origin: local files are not, so the PNGs are embedded as data URIs (one class per asset).
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64(data)
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1, c2, c3, c4 = math.floor(n / 262144) % 64, math.floor(n / 4096) % 64, math.floor(n / 64) % 64, n % 64
    out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1) .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
  end
  return table.concat(out)
end

local assetCss = {}
local function assetClass(name, pngDir)
  if assetCss[name] == nil then
    local f = io.open(pngDir .. "/" .. name .. ".png", "rb")
    if f then
      assetCss[name] = (".a-%s{-webkit-mask-image:url(data:image/png;base64,%s)}"):format(name, base64(f:read("*a")))
      f:close()
    else
      assetCss[name] = false
    end
  end
  return assetCss[name] and ("a-" .. name) or nil
end

local function assetName(path)
  return type(path) == "string" and path:match("AddOns\\ClassPages\\Media\\([%w_]+)$") or nil
end

function Render.Page(roots, ui, frames, title, pngDir)
  local out = { ('<!doctype html><meta charset="utf-8"><title>%s</title><style>'):format(esc(title)),
    "body{background:#2b3036 radial-gradient(circle at 30% 20%,#3a424a,#1d2125);margin:0;padding:28px;font-family:'Friz Quadrata TT',Georgia,serif}",
    ".root{position:relative;margin-bottom:40px}.r{position:absolute;box-sizing:border-box}",
    ".t{white-space:nowrap;line-height:1.15}.w{white-space:normal}.ic{display:inline-block;width:12px;height:12px;background:#666;vertical-align:middle;border-radius:3px}",
    ".tex{background:#555 linear-gradient(135deg,#8a8173,#4a443c)}.m{-webkit-mask-repeat:no-repeat;mask-repeat:no-repeat}",
    "h2{color:#ddd;font:14px sans-serif;margin:0 0 14px}</style>",
    ("<h2>%s</h2>"):format(esc(title)) }
  for _, root in ipairs(roots) do
    local rr = root and root._shown and Layout.Rect(root, ui)
    if rr then
      out[#out + 1] = ('<div class="root" style="width:%dpx;height:%dpx">'):format(rr.r - rr.l, rr.t - rr.b)
      for _, f in ipairs(frames) do
        if f == root or visible(f, root) then
          local r = Layout.Rect(f, ui)
          if r then
            local w, h = math.max(0, r.r - r.l), math.max(0, r.t - r.b)
            local d = depth(f)
            local pos = ("left:%.1fpx;top:%.1fpx;width:%.1fpx;height:%.1fpx;"):format(r.l - rr.l, rr.t - r.t, w, h)
            if f._kind == "FontString" then
              if f._text and f._text ~= "" then
                local fc = Layout.FontClass(f)
                local color = rgba(f._textColor) or (tostring(f._font):find("Normal") and "#ffd100" or "#ece6da")
                local align = f._justifyH == "RIGHT" and "right" or f._justifyH == "CENTER" and "center" or "left"
                if not f._wSet then align = "left" end
                out[#out + 1] = ('<div class="r t%s" style="%sfont-size:%dpx;color:%s;text-align:%s;z-index:%d">%s</div>'):format(
                  (f._wSet and not f._nowrap) and " w" or "", pos, FONT_PX[fc] or 10, color, align, d * 10 + 6, richText(f._text))
              end
            elseif f._kind == "Texture" and f._layer ~= "HIGHLIGHT" and w > 0 and h > 0 then
              local z = d * 10 + (LAYER[f._layer] or 2)
              local asset = assetName(f._texture)
              if asset then
                local c = f._coords or { 0, 1, 0, 1 }
                local mw, mh = w / math.max(0.0001, c[2] - c[1]), h / math.max(0.0001, c[4] - c[3])
                out[#out + 1] = ('<div class="r m %s" style="%sz-index:%d;background:%s;-webkit-mask-size:%.2fpx %.2fpx;-webkit-mask-position:%.2fpx %.2fpx;%s"></div>'):format(
                  assetClass(asset, pngDir) or "", pos, z, rgba(f._vcolor or { 1, 1, 1, 1 }), mw, mh, -c[1] * mw, -c[3] * mh, f._blend == "ADD" and "mix-blend-mode:screen;" or "")
              elseif f._color then
                out[#out + 1] = ('<div class="r" style="%sz-index:%d;background:%s"></div>'):format(pos, z, rgba(f._color))
              elseif f._texture then
                local radius = f._mask and (assetName(f._mask._texture) == "mask_logo" and "14%" or "8%") or "0"
                out[#out + 1] = ('<div class="r tex" style="%sz-index:%d;border-radius:%s;%s"></div>'):format(pos, z, radius, f._desat and "filter:grayscale(1) brightness(.7);" or "")
              end
            end
          end
        end
      end
      out[#out + 1] = "</div>"
    end
  end
  local css = {}
  for _, rule in pairs(assetCss) do if rule then css[#css + 1] = rule end end
  out[#out + 1] = "<style>" .. table.concat(css, "\n") .. "</style>"
  return table.concat(out, "\n")
end

return function(layout) Layout = layout; return Render end
