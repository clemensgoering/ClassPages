-- ClassPages session simulator (Lua 5.1 / LuaJIT). Usage: luajit tools/tests/sim.lua <repo root>
--
-- Loads EVERY file of ClassPages.toc into a simulated client and plays whole sessions: login -> preset bars ->
-- every window tab -> talent planning -> HUD editing (unlock, wheel, drag) -> drag & drop onto buttons -> combat with
-- SECRET values (cooldowns, usability, procs) -> deferred secure changes -> pets, stable, beast training -> every slash
-- command -> debug report -> second login with the saved data (no reseed, damaged bar repaired) -> another class.
-- Secrets are a sentinel table: any comparison or arithmetic on them raises like in the client. Secure frames raise
-- when changed in combat. The embedded LibActionButton is replaced by a small fake with the same public surface
-- (the real library is syntax-checked and covered by the live test, /cp debug).
-- Each scenario runs "modern" (all optional APIs) and "minimal" (classic talent API, no alpha-from-boolean, no
-- alert manager, no pet happiness API) so every fallback path runs.
local root = arg[1] or "."
local FAILURES, NOTES = {}, {}
local function fail(msg) FAILURES[#FAILURES + 1] = msg end
local function note(msg) NOTES[#NOTES + 1] = msg end

local Layout = dofile(root .. "/tools/tests/layout.lua")
local Render = dofile(root .. "/tools/tests/render.lua")(Layout)
local RENDER_DIR = os.getenv("CP_RENDER")
local function renderPage(env, name, title, roots)
  if not RENDER_DIR then return end
  local f = io.open(RENDER_DIR .. "/" .. name .. ".html", "w")
  if not f then return end
  f:write(Render.Page(roots, env.UIParent, env._frames, title, root .. "/tools/assets/png"))
  f:close()
end
local LAYOUT_SEEN = {}
local function checkLayout(env, frame, label, where)
  if not frame then return end
  for _, p in ipairs(Layout.Check(frame, env.UIParent, env._frames)) do
    local key = where .. ": " .. p
    if not LAYOUT_SEEN[key] then LAYOUT_SEEN[key] = true; fail(("%s: layout %s"):format(label, key)) end
  end
end

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

---------------------------------------------------------------------------------------------------
-- Simulated client
---------------------------------------------------------------------------------------------------
local function newClient(opts)
  local env = setmetatable({}, { __index = _G })
  env._G = env
  local clock, timers, frames, unknown = 1000, {}, {}, {}
  env._frames, env._unknown, env._chat = frames, unknown, {}
  env._combat = false

  env.C_Timer = { After = function(d, fn) timers[#timers + 1] = { at = clock + (d or 0), fn = fn } end }
  local function advance(seconds)
    local target = clock + seconds
    while true do
      local idx, best
      for i, t in ipairs(timers) do if t.at <= target and (not best or t.at < best.at) then idx, best = i, t end end
      if not idx then break end
      table.remove(timers, idx)
      clock = math.max(clock, best.at)
      local ok, err = pcall(best.fn)
      if not ok then fail("uncaught error in timer: " .. tostring(err)) end
    end
    clock = target
  end
  env._advance = advance
  env.GetTime = function() return clock end
  env.time = function(t) if t then return os.time(t) end return 1794200000 + math.floor(clock) end
  env.date = os.date
  env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

  -- frames ------------------------------------------------------------------------------------
  local Methods, noop = {}, function() end
  local mt = { __index = function(_, k)
    local m = Methods[k]
    if m then return m end
    if type(k) == "string" and k:match("^[A-Z]") then unknown[k] = (unknown[k] or 0) + 1 end
    return nil
  end }
  local function newObject(kind, parent, name)
    local o = setmetatable({ _kind = kind, _shown = true, _scripts = {}, _events = {}, _attrs = {}, _text = "", _w = 100, _h = 20,
      _alpha = 1, _scale = 1, _parent = parent, _name = name, _enabled = true }, mt)
    frames[#frames + 1] = o
    return o
  end
  local function m(name, fn) Methods[name] = fn end
  local function protected(name, fn)
    Methods[name] = function(self, ...)
      if self._secure and env._combat then fail(("protected call %s on %s in combat"):format(name, tostring(self._name))) end
      return fn(self, ...)
    end
  end
  for _, n in ipairs({ "EnableMouse", "EnableMouseWheel", "RegisterForDrag", "RegisterForClicks", "StopMovingOrSizing",
    "SetClampedToScreen", "SetFrameLevel", "SetToplevel", "SetTexCoord", "SetVertexColor", "SetJustifyH", "SetJustifyV", "SetWordWrap",
    "SetMinMaxValues", "SetStatusBarTexture", "SetStatusBarColor", "SetMultiLine", "SetAutoFocus", "SetFocus",
    "ClearFocus", "HighlightText", "SetScrollChild", "SetDrawLayer",  "SetParent", "SetBlendMode",
    "SetDesaturated", "SetOrientation", "SetValueStep", "SetObeyStepOnDrag", "SetTextInsets", "SetThumbTexture", "SetDrawSwipe",
    "SetHideCountdownNumbers", "Clear", "SetMovable", "SetCooldown" }) do m(n, noop) end
  -- anchors are kept per point (layout checker); SetPoint forms: (p) (p, x, y) (p, rel) (p, rel, rp) (p, rel, x, y) (p, rel, rp, x, y)
  protected("SetPoint", function(self, point, a, b, c, d)
    local rel, rp, x, y
    if type(a) == "number" then x, y = a, b
    elseif type(a) == "table" then
      rel = a
      if type(b) == "string" then rp, x, y = b, c, d elseif type(b) == "number" then x, y = b, c end
    end
    self._point = { point, rel, rp, x, y }
    self._points = self._points or {}
    self._points[point] = { rel = rel, relPoint = rp, x = x or 0, y = y or 0 }
  end)
  protected("ClearAllPoints", function(self) self._points = {} end)
  Methods.SetAllPoints = function(self, rel)
    self._points = { TOPLEFT = { rel = rel, relPoint = "TOPLEFT", x = 0, y = 0 }, BOTTOMRIGHT = { rel = rel, relPoint = "BOTTOMRIGHT", x = 0, y = 0 } }
  end
  protected("SetSize", function(self, w, h) self._w, self._h, self._wSet, self._hSet = w, h, true, true end)
  protected("SetScale", function(self, s) self._scale = s end)
  protected("Show", function(self) self._shown = true; if self._scripts.OnShow then self._scripts.OnShow(self) end end)
  protected("Hide", function(self) self._shown = false; if self._scripts.OnHide then self._scripts.OnHide(self) end end)
  protected("SetAttribute", function(self, k, v) self._attrs[k] = v end)
  m("SetWidth", function(self, w) self._w, self._wSet = w, true end)
  m("SetHeight", function(self, h) self._h, self._hSet = h, true end)
  m("SetWordWrap", function(self, v) self._nowrap = not v end)
  m("SetFontObject", function(self, f) self._font = f end)
  m("GetWidth", function(self) return self._w end)
  m("GetHeight", function(self) return self._h end)
  m("GetPoint", function(self) local p = self._point or {} return p[1] or "CENTER", nil, p[3] or "CENTER", p[4] or 0, p[5] or 0 end)
  m("GetCenter", function() return 963, 541 end)
  m("GetRight", function() return 1000 end)
  m("IsMouseOver", function(self) return self._mouseOver or false end)
  m("EnableKeyboard", noop)
  m("SetPropagateKeyboardInput", noop)
  m("GetScale", function(self) return self._scale end)
  m("StartMoving", function(self) if self._secure and env._combat then fail("moving secure frame in combat") end end)
  m("IsShown", function(self) return self._shown end)
  m("IsVisible", function(self) return self._shown end)
  m("SetShown", function(self, s) if s then self:Show() else self:Hide() end end)
  m("SetScript", function(self, k, fn) self._scripts[k] = fn end)
  m("GetScript", function(self, k) return self._scripts[k] end)
  m("HookScript", function(self, k, fn) local old = self._scripts[k]; self._scripts[k] = function(...) if old then old(...) end fn(...) end end)
  m("RegisterEvent", function(self, e)
    if opts.unknownEvents and opts.unknownEvents[e] then error("Attempt to register unknown event \"" .. e .. "\"") end
    self._events[e] = true
  end)
  m("UnregisterEvent", function(self, e) self._events[e] = nil end)
  m("CreateTexture", function(self, _, layer)
    local t = newObject("Texture", self)
    t._layer, t._w, t._h = layer, 0, 0
    if not opts.minimal then t.SetAlphaFromBoolean = function(tex, v, a, b) if v == SECRET then tex._alpha = a else tex._alpha = v and a or b end end end
    return t
  end)
  m("CreateFontString", function(self, _, _, font) local fs = newObject("FontString", self); fs._font = font; fs._w, fs._h = 0, 0 return fs end)
  m("SetText", function(self, t) self._text = t and tostring(t) or "" end)
  m("GetText", function(self) return self._text end)
  m("GetStringWidth", function(self) return Layout.TextWidth(self) end)  -- same estimate as the layout checker
  m("SetTexture", function(self, t) self._texture = t end)
  m("SetTexCoord", function(self, l, r, t, b) self._coords = { l, r, t, b } end)
  m("SetVertexColor", function(self, r, g, b, a) self._vcolor = { r, g, b, a or 1 } end)
  m("SetBlendMode", function(self, mode) self._blend = mode end)
  m("SetDesaturated", function(self, on) self._desat = on end)
  m("CreateMaskTexture", function(self) return newObject("Mask", self) end)
  m("AddMaskTexture", function(self, mask) self._mask = mask end)
  m("SetColorTexture", function(self, r, g, b, a) self._color = { r, g, b, a or 1 } end)
  m("SetTextColor", function(self, r, g, b, a) self._textColor = { r, g, b, a or 1 } end)
  m("SetJustifyH", function(self, j) self._justifyH = j end)
  m("SetAlpha", function(self, a) if a == SECRET then fail("SetAlpha with a secret") end self._alpha = a end)
  m("GetAlpha", function(self) return self._alpha end)
  m("GetAttribute", function(self, k) return self._attrs[k] end)
  m("SetFrameStrata", function(self, s) self._strata = s end)
  m("SetValue", function(self, v) self._value = v; if self._scripts.OnValueChanged then self._scripts.OnValueChanged(self, v) end end)
  m("SetChecked", function(self, v) self._checked = v end)
  m("SetEnabled", function(self, v) self._enabled = v and true or false end)
  m("Click", function(self, button) if self._scripts.OnClick then self._scripts.OnClick(self, button or "LeftButton") end end)
  m("GetName", function(self) return self._name end)
  m("GetParent", function(self) return self._parent end)
  m("SetOwner", noop)
  m("AddLine", function(self, text) self._lines = self._lines or {}; self._lines[#self._lines + 1] = text end)
  m("SetSpellByID", noop)
  m("SetPetAction", noop)
  m("CreateAnimationGroup", function()
    local ag = { playing = false }
    function ag:CreateAnimation() return setmetatable({}, { __index = function() return noop end }) end
    function ag:Play() self.playing = true; env._flashes = (env._flashes or 0) + 1 end
    function ag:Stop() self.playing = false end
    ag.SetLooping = noop
    return ag
  end)

  local TEMPLATES = { SecureHandlerStateTemplate = true, SecureActionButtonTemplate = true, UIPanelScrollFrameTemplate = true,
    UIPanelCloseButton = true, CooldownFrameTemplate = true, ActionButtonTemplate = not opts.minimal }
  env.CreateFrame = function(ftype, name, parent, template)
    if template then
      for t in tostring(template):gmatch("[^,%s]+") do if not TEMPLATES[t] then error("unknown template " .. t) end end
    end
    local f = newObject(ftype or "Frame", parent, name)
    f._template = template
    f._secure = template and template:find("Secure") and true or false
    if template and template:find("ActionButtonTemplate") then
      f.icon = newObject("Texture", f); f.cooldown = newObject("Cooldown", f)
    end
    if name then env[name] = f end
    return f
  end

  env.UIParent = newObject("Frame", nil, "UIParent")
  env.UIParent._w, env.UIParent._h = 1920, 1080
  env.Minimap = newObject("Frame", env.UIParent, "Minimap")
  env.GetCursorPosition = function() return 900, 600 end
  m("GetEffectiveScale", function() return 1 end)
  m("SetHighlightTexture", noop)
  env.GameTooltip = newObject("GameTooltip", env.UIParent, "GameTooltip")
  env.UISpecialFrames = {}
  env.unpack = unpack
  env.securecallfunction = function(fn, ...) return fn(...) end
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) env._chat[#env._chat + 1] = msg end }
  env.SlashCmdList = {}
  env.issecretvalue = function(v) return v == SECRET end
  env.InCombatLockdown = function() return env._combat end
  env.IsShiftKeyDown = function() return env._shift or false end
  env.IsControlKeyDown = function() return false end
  env.GetLocale = function() return opts.clientLocale or "deDE" end
  env.GetBuildInfo = function() return "1.60.1", "70862", "Nov 6 2026", opts.interface or 16001 end
  env.WOW_PROJECT_ID = 18
  env.RegisterStateDriver = function(f, attr, cond)
    if env._combat then fail("RegisterStateDriver in combat") end
    f._driver = cond
    if attr == "visibility" then f._shown = cond ~= "hide" end
  end
  env.UnregisterStateDriver = function(f) f._driver = nil end
  env._bindings = {}
  env.SetOverrideBindingClick = function(owner, _, key, buttonName)
    if env._combat then fail("SetOverrideBindingClick in combat") end
    env._bindings[key] = { owner = owner, button = buttonName }
  end
  env.ClearOverrideBindings = function(owner)
    if env._combat then fail("ClearOverrideBindings in combat") end
    for key, b in pairs(env._bindings) do if b.owner == owner then env._bindings[key] = nil end end
  end
  env.IsAltKeyDown = function() return false end
  env.GetMoney = function() return 5000 end
  env.GetNumShapeshiftForms = function() return opts.char.class == "WARRIOR" and 3 or 0 end
  env.GetShapeshiftFormInfo = function(i) return 132000 + i, false, true, 2457 + i end
  -- class trainer window
  local TRAINER = { { "Jäger", nil, "header" }, { "Arkaner Schuss", "Rang 3", "available", 20, 1800 }, { "Schlangenbiss", "Rang 2", "used", 10, 200 },
    { "Mehrfachschuss", "Rang 5", "unavailable", 62, 40000 }, { "Salve", "Rang 1", "unavailable", 61, 22000 } }
  env.IsTradeskillTrainer = function() return false end
  env.GetNumTrainerServices = function() return #TRAINER end
  env.GetTrainerServiceInfo = function(i) return TRAINER[i][1], TRAINER[i][2], TRAINER[i][3] end
  env.GetTrainerServiceLevelReq = function(i) return TRAINER[i][4] or 0 end
  env.GetTrainerServiceCost = function(i) return TRAINER[i][5] or 0 end
  if not opts.minimal then env.ActionButtonSpellAlertManager = { ShowAlert = function(_, b) b._alert = true end, HideAlert = function(_, b) b._alert = false end } end
  env.Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 }, SpellBookItemType = { Spell = 1, PetAction = 4 } }
  env.C_AddOns = { GetAddOnMetadata = function() return "@project-version@" end }

  -- character -------------------------------------------------------------------------------
  local char = opts.char
  env.UnitFullName = function() return char.name, "" end
  env.GetNormalizedRealmName = function() return "CAMWOWEU4" end
  env.UnitClassBase = function() return char.class, char.classID end
  env.UnitClass = function() return char.localized, char.class, char.classID end
  env.UnitLevel = function(unit) if unit == "pet" then return 55 end return char.level end
  env.UnitExists = function(unit) return unit == "pet" and char.class == "HUNTER" end
  env.UnitName = function(unit) if unit == "pet" then return "Fang" end return char.name end
  env.UnitCreatureFamily = function() return "Wolf" end
  env.GetInventoryItemCount = function() return 150 end
  env.GetInventoryItemID = function() return 2512 end
  env.C_Item = { GetItemCount = function() return 3 end, GetItemNameByID = function() return nil end, GetItemIconByID = function() return nil end }

  -- spells and spellbook ------------------------------------------------------------------
  local spells = char.spells
  local names = {}
  for _, s in ipairs(spells) do names[s[1]] = s[2] end
  for base, name in pairs(char.baseNames or {}) do names[base] = names[base] or name end
  env._cooldowns, env._usable = {}, {}
  env.C_Spell = {
    GetSpellName = function(id) return names[id] end,
    GetSpellTexture = function(id) return 130000 + (id % 1000) end,
    GetSpellCooldown = function(id)
      if env._combat then return { isActive = SECRET, startTime = SECRET, duration = SECRET, isEnabled = true, modRate = 1 } end
      local c = env._cooldowns[id]
      return { isActive = c and true or false, startTime = c and c.start or 0, duration = c and c.duration or 0, isEnabled = true, modRate = 1 }
    end,
    IsSpellUsable = function(id) if env._combat then return SECRET, SECRET end return env._usable[id] ~= false, false end,
  }
  env.C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { name = "Hunter", itemIndexOffset = 0, numSpellBookItems = #spells } end,
    GetSpellBookItemInfo = function(slot, bank)
      if bank == 1 then
        local p = ({ { 17253, "Bite", "Rank 6" }, { 2649, "Growl", "Rank 5" }, { 16827, "Claw", "Rank 7" } })[slot]
        return p and { itemType = 4, spellID = p[1], name = p[2], subName = p[3], isPassive = false }
      end
      local s = spells[slot]
      return s and { itemType = 1, spellID = s[1], name = s[2], subName = s[3], isPassive = s[4] or false }
    end,
    HasPetSpells = function() return char.class == "HUNTER" and 3 or 0 end,
    IsSpellKnown = function(id) for _, s in ipairs(spells) do if s[1] == id then return true end end return false end,
  }
  env.GetProfessions = function() return 1, nil, nil, nil, 2 end
  env.GetProfessionInfo = function(i)
    if i == 1 then return "Lederverarbeitung", 133611, 120, 150, 1, #spells + 1 end
    return "Kochkunst", 133971, 40, 75, 0, 0
  end

  -- talents -----------------------------------------------------------------------------------
  local NODES = {}
  for t = 0, 2 do
    for r = 0, 6 do
      for c = 0, 3 do
        if (r + c + t) % 3 ~= 1 then
          local id = 1000 + t * 100 + r * 10 + c
          NODES[id] = { ID = id, posX = t * 4200 + c * 600, posY = r * 600, maxRanks = (r == 6) and 1 or 5, entryIDs = { id * 10 },
            visibleEdges = (r < 6 and (r + c + t + 1) % 3 ~= 1) and { { targetNode = id + 10 } } or {}, ranksPurchased = (t == 1 and r == 0) and 2 or 0, isVisible = true }
        end
      end
    end
  end
  if not opts.minimal then
    env.Constants = { TraitConsts = { VIEW_TRAIT_CONFIG_ID = -3 } }
    env.C_ClassTalents = { GetActiveConfigID = function() return 77 end, InitializeViewLoadout = noop, ViewLoadout = noop }
    env.C_Traits = {
      GetConfigInfo = function() return { treeIDs = { 9 } } end,
      GetTreeNodes = function() local ids = {} for id in pairs(NODES) do ids[#ids + 1] = id end table.sort(ids) return ids end,
      GetNodeInfo = function(_, id) return NODES[id] end,
      GetEntryInfo = function(_, entryID) return { definitionID = entryID } end,
      GetDefinitionInfo = function(def) return { spellID = def } end,
    }
  end
  env.GetSpecializationInfoForClassID = function(_, i) return 250 + i, ({ "Tierherrschaft", "Treffsicherheit", "Überleben" })[i], "", 132000 + i end
  env.GetNumTalentTabs = function() return 3 end
  env.GetTalentTabInfo = function(t) return ({ "Tierherrschaft", "Treffsicherheit", "Überleben" })[t], 132000 + t, 0 end
  env.GetNumTalents = function() return 6 end
  env.GetTalentInfo = function(t, i)
    local tier, col = math.floor((i - 1) / 2) + 1, (i - 1) % 2 + 1
    return "Talent " .. t .. "." .. i, 135000 + i, tier, col, (t == 2 and i == 1) and 3 or 0, 5
  end
  env.GetTalentPrereqs = function(_, i) if i == 3 then return 1, 1 end end

  -- pets ----------------------------------------------------------------------------------------
  env.GetPetActionInfo = function(i)
    if i > 7 then return nil end
    return "Pet " .. i, i <= 3 and "PET_ATTACK_TEXTURE" or 132000 + i, i <= 3, i == 1, i >= 4, i == 4, 17000 + i
  end
  env.PET_ATTACK_TEXTURE = 132152
  env.GetPetActionCooldown = function() if env._combat then return SECRET, SECRET, 1 end return 0, 0, 1 end
  env.GetPetActionSlotUsable = function() if env._combat then return SECRET end return true end
  if not opts.minimal then
    env.GetPetHappiness = function() return 3, 125, 1 end
    env.GetPetLoyalty = function() return "Treuestufe 4" end
  end
  env.GetPetTrainingPoints = function() return 140, 95 end
  env.GetPetFoodTypes = function() return "Fleisch", "Fisch" end
  env.GetPetExperience = function() return 1200, 4000 end
  env.GetStablePetInfo = function(i) if i <= 1 then return 132000, i == 0 and "Fang" or "Krallo", 55 - i, "Wolf", "Treue" end end
  env.GetCraftDisplaySkillLine = function() return "Wildtierausbildung" end
  names[5149] = "Wildtierausbildung"
  env.GetNumCrafts = function() return 4 end
  env.GetCraftInfo = function(i)
    return ({ { "Biss", "", "header" }, { "Biss", "Rang 7", "available", 0, 0, 20, 56 }, { "Klaue", "Rang 7", "used", 0, 0, 0, 50 }, { "Knurren", "Rang 6", "unavailable", 0, 0, 15, 60 } })[i][1],
      ({ "", "Rang 7", "Rang 7", "Rang 6" })[i], ({ "header", "available", "used", "unavailable" })[i], 0, 0, ({ 0, 20, 0, 15 })[i], ({ 0, 56, 50, 60 })[i]
  end

  env._fire = function(event, ...)
    for _, f in ipairs(frames) do
      if f._events[event] and f._scripts.OnEvent then
        local ok, err = pcall(f._scripts.OnEvent, f, event, ...)
        if not ok then fail(("uncaught error in %s: %s"):format(event, tostring(err))) end
      end
    end
  end
  return env
end

---------------------------------------------------------------------------------------------------
-- Fake LibActionButton (same public surface the addon uses)
---------------------------------------------------------------------------------------------------
local FAKE_LAB = [[
local lib = LibStub:NewLibrary("LibActionButton-1.0", 999)
lib.callbacks = LibStub("CallbackHandler-1.0"):New(lib)
lib.buttons = {}
function lib:CreateButton(id, name, header, config)
  local b = CreateFrame("CheckButton", name, header, "SecureActionButtonTemplate")
  b.cooldown = CreateFrame("Cooldown", nil, b)
  b.state_types, b.state_actions = {}, {}
  function b:SetState(state, kind, action)
    if InCombatLockdown() then error("LAB SetState in combat") end
    self.state_types[tostring(state)] = kind
    self.state_actions[tostring(state)] = action
  end
  function b:GetAction(state) state = tostring(state or 0) return self.state_types[state] or "empty", self.state_actions[state] end
  function b:UpdateConfig(c) assert(type(c) == "table", "config") self.config = c end
  function b:GetSpellId() local k, v = self:GetAction() if k == "spell" then return v end end
  function b:AddToMasque() end
  b.id = id
  lib.buttons[#lib.buttons + 1] = b
  return b
end
function lib._drop(button, kind, value)
  button.state_types["0"], button.state_actions["0"] = kind, value
  lib.callbacks:Fire("OnButtonContentsChanged", button, "0", kind, value)
end
]]

local function tocFiles()
  local files = {}
  local f = assert(io.open(root .. "/ClassPages/ClassPages.toc", "r"))
  for line in f:lines() do
    line = line:gsub("\r", "")
    if line ~= "" and not line:match("^#") then files[#files + 1] = (line:gsub("\\", "/")) end
  end
  f:close()
  return files
end

local function loadAddon(env)
  local ns = {}
  for _, rel in ipairs(tocFiles()) do
    local chunk, err
    if rel:match("LibActionButton") then chunk, err = loadstring(FAKE_LAB, "FakeLAB")
    else chunk, err = loadfile(root .. "/ClassPages/" .. rel) end
    if not chunk then fail("load " .. rel .. ": " .. tostring(err)) else
      setfenv(chunk, env)
      local ok, runErr = pcall(chunk, "ClassPages", ns)
      if not ok then fail("run " .. rel .. ": " .. tostring(runErr)) end
    end
  end
  return ns
end

local function step(name, fn)
  local ok, err = pcall(fn)
  if not ok then fail(name .. ": " .. tostring(err)) end
end

local function findButton(env, text)
  for i = #env._frames, 1, -1 do
    local f = env._frames[i]
    if f.label and f.label._text and f.label._text:find(text, 1, true) and f._scripts.OnClick then return f end
  end
  return nil
end

local HUNTER_SPELLS = {
  { 75, "Automatischer Schuss" }, { 1130, "Mal des Jägers", "Rang 1" }, { 3044, "Arkaner Schuss", "Rang 1" }, { 14281, "Arkaner Schuss", "Rang 2" },
  { 1978, "Schlangenbiss", "Rang 1" }, { 2973, "Raptorstoß", "Rang 1" }, { 19306, "Konterattacke", "Rang 1" }, { 1499, "Eiskältefalle", "Rang 1" },
  { 13165, "Aspekt des Falken", "Rang 1" }, { 883, "Tier rufen" }, { 5149, "Wildtierausbildung" }, { 99999, "Passiv", nil, true },
  { 2108, "Lederverarbeitung" },
}
local HUNTER = { name = "Hunterine", class = "HUNTER", classID = 3, localized = "Jäger", level = 60, spells = HUNTER_SPELLS,
  baseNames = { [5116] = "Erschütternder Schuss" } }
local WARRIOR = { name = "Kruul", class = "WARRIOR", classID = 1, localized = "Krieger", level = 30,
  spells = { { 78, "Heldenhafter Stoß", "Rang 1" }, { 6673, "Schlachtruf", "Rang 1" }, { 100, "Sturmangriff", "Rang 1" } } }

local function session(label, opts, savedDB)
  local env = newClient(opts)
  env.ClassPagesDB, env.ClassPagesCharDB, env.ClassPagesBackupDB = savedDB, nil, nil
  local ns = loadAddon(env)
  if not ns.Events then fail(label .. ": addon did not load"); return end
  local LAB = env.LibStub("LibActionButton-1.0")
  local count = 0
  local function s(name, fn) count = count + 1; step(label .. " / " .. name, fn) end
  local hunter = opts.char.class == "HUNTER"

  s("ADDON_LOADED + PLAYER_LOGIN", function()
    env._fire("ADDON_LOADED", "ClassPages")
    env._fire("PLAYER_LOGIN")
    env._advance(1)
  end)
  local bars = ns.HUD.Bars()
  s("preset bars", function()
    if #bars < 2 then fail(label .. ": only " .. #bars .. " bars") end
    local shots = bars[1]
    local f = select(2, ns.HUD.Frames(shots.id))
    local first = f and f[1]
    if not first then fail(label .. ": first bar has no buttons") return end
    local kind, value = first:GetAction()
    if hunter and not savedDB and (kind ~= "spell" or value ~= 75) then fail(label .. ": first button " .. tostring(kind) .. " " .. tostring(value)) end
    if hunter then
      for _, b in pairs(f) do
        local k, v = b:GetAction()
        if k == "spell" and v == 3044 then fail(label .. ": Arcane Shot not resolved to highest rank") end
      end
    end
  end)
  s("every window tab", function()
    for _, key in ipairs(ns.UI.order) do
      ns.UI.Open(key); env._advance(0.1)
      if ns.UI.Current() == key then
        checkLayout(env, env.ClassPagesWindow, label, "tab " .. key)
        if label:find("fresh install") and label:find("modern") or label:find("warrior") and label:find("modern") then
          renderPage(env, (label:find("warrior") and "warrior-" or "hunter-") .. key, label .. " · " .. key, { env.ClassPagesWindow })
        end
      end
    end
    ns.UI.Toggle(); ns.UI.Toggle("hud"); ns.UI.Refresh()
    if hunter ~= (ns.UI.tabs.pets.button ~= nil) then fail(label .. ": pets tab visibility wrong") end
  end)
  s("talent planner", function()
    local model, byID = ns.Talents.Tree()
    if not model then fail(label .. ": talents not read: " .. tostring(ns.Talents.LastError())) return end
    if #model.trees ~= 3 then fail(label .. ": " .. #model.trees .. " talent trees") end
    local first = model.trees[1].talents[1]
    local plan = ns.Talents.Plan()
    for _ = 1, 5 do ns.Talents.Planner.Add(plan, model, byID, first.id, 60) end
    local text = ns.Talents.Planner.Export(plan, model)
    if not ns.Talents.Planner.Import(text, model) then fail(label .. ": export/import failed: " .. text) end
    if ns.Util.Count(ns.Talents.Current()) == 0 then fail(label .. ": live talent ranks missing") end
    ns.UI.Open("talents")
    local nextTalent, nextLevel = ns.Talents.Next()
    if not nextTalent or type(nextLevel) ~= "number" then fail(label .. ": no next talent point from the plan") end
    local b = findButton(env, ns.L["Compare"]); if b then b:Click() end
    b = findButton(env, ns.L["Export"]); if b then b:Click() end
    b = findButton(env, ns.L["Copy live talents"]); if b then b:Click() end
  end)
  s("HUD tab: add, delete (confirmed), presets", function()
    ns.UI.Open("hud")
    checkLayout(env, env.ClassPagesWindow, label, "tab hud (bar selected)")
    local nb = findButton(env, ns.L["+ New bar"])
    if not nb then fail(label .. ": no New bar button") return end
    local before = #ns.HUD.Bars()
    nb:Click()
    if #ns.HUD.Bars() ~= before + 1 then fail(label .. ": bar not added") end
    local del = findButton(env, ns.L["Delete bar"])
    if del then del:Click() end
    if #ns.HUD.Bars() ~= before + 1 then fail(label .. ": delete without confirmation") end
    if del then del:Click() end
    if #ns.HUD.Bars() ~= before then fail(label .. ": new bar not deleted after confirmation") end
    for _, k in ipairs({ "Move in game", "Refill from preset", "Undo", "Clear buttons" }) do
      local b = findButton(env, ns.L[k]); if b then b:Click() end
    end
    ns.HUD.SetEditing(false)
  end)
  s("regression: delete every bar, add a new one -> it is visible", function()
    for _, b in ipairs(ns.HUD.Bars()) do ns.HUD.DeleteBar(b.id) end
    if #ns.HUD.Bars() ~= 0 then fail(label .. ": bars left") end
    local bar = ns.HUD.AddBar({ name = "New", kind = "free" })
    local header, used = ns.HUD.Frames(bar.id)
    if not header or header._driver == "hide" or not header._shown then fail(label .. ": new empty bar hidden") end
    if not (used[1] and used[1].config and used[1].config.showGrid) then fail(label .. ": empty bar does not show its slots") end
    local hint
    for _, f in ipairs(env._frames) do if f._parent == header and f._kind == "FontString" then hint = f end end
    if not (hint and hint._shown) then fail(label .. ": empty bar hint missing") end
    LAB._drop(used[1], "spell", 75)
    if used[1].config.showGrid then fail(label .. ": grid still forced after the first button") end
    -- presets come back with one click
    local presets = ns.HUD.Presets()
    if #presets == 0 then fail(label .. ": no presets offered") return end
    for _, p in ipairs(presets) do if p.barID then fail(label .. ": deleted preset still marked as used") end end
    local restored = ns.HUD.AddPreset(presets[1].key)
    if not restored or ns.Util.Count(restored.buttons) == 0 then fail(label .. ": preset bar restored without buttons") end
    for i = 2, #presets do ns.HUD.AddPreset(presets[i].key) end
    ns.HUD.DeleteBar(bar.id)
  end)
  s("edit mode: toolbar, select, popover, steppers, grip, snap", function()
    ns.HUD.SetEditing(true)
    if not (env.ClassPagesEditToolbar and env.ClassPagesEditToolbar._shown) then fail(label .. ": no edit toolbar") end
    local id = ns.HUD.Bars()[1].id
    local mover = ns.HUD.Mover.frames[id]
    if not mover then fail(label .. ": no overlay in edit mode") return end
    local bar = ns.profile.hud.bars[id]
    local cols = bar.cols
    mover._scripts.OnMouseWheel(mover, 1)
    if bar.cols ~= math.min(24, cols + 1) then fail(label .. ": wheel did not add a column") end
    mover._scripts.OnMouseUp(mover, "LeftButton")
    if ns.HUD.Selected() ~= id then fail(label .. ": click did not select") end
    local pop = env.ClassPagesEditPopover
    if not (pop and pop._shown) then fail(label .. ": popover not shown") return end
    checkLayout(env, pop, label, "edit popover")
    if label:find("modern") and label:find("fresh") then renderPage(env, "hunter-editmode", label .. " · edit mode", { env.ClassPagesEditToolbar, pop }) end
    checkLayout(env, env.ClassPagesEditToolbar, label, "edit toolbar")
    local stepper = pop.steppers and pop.steppers.cols and pop.steppers.cols.plus
    local before = bar.cols + bar.rows + bar.size + bar.spacing
    if stepper then stepper:Click() end
    if not stepper or bar.cols + bar.rows + bar.size + bar.spacing == before then fail(label .. ": popover stepper changed nothing") end
    mover._scripts.OnDragStart(mover); mover._scripts.OnDragStop(mover); env._advance(0.1)
    if bar.point[1] ~= "CENTER" or bar.point[2] % 8 ~= 0 then fail(label .. ": drag did not save a snapped position") end
    local grip = mover.grip
    grip._scripts.OnMouseDown(grip)
    env.GetCursorPosition = function() return 1100, 600 end
    if grip._scripts.OnUpdate then grip._scripts.OnUpdate(grip) end
    grip._scripts.OnMouseUp(grip)
    env.GetCursorPosition = function() return 900, 600 end
    local hide = findButton(env, ns.L["Hide"]); if hide then hide:Click() end
    if bar.enabled then fail(label .. ": popover hide did not hide") end
    ns.HUD.SetEnabled(id, true)
    local more = findButton(env, ns.L["More settings..."]); if more then more:Click() end
    if ns.UI.Current() ~= "hud" then fail(label .. ": more settings did not open the HUD tab") end
    local done = findButton(env, ns.L["Done"]); if done then done:Click() end
    if ns.HUD.IsEditing() then fail(label .. ": Done did not leave edit mode") end
  end)
  s("visibility rules and mouseover fade", function()
    local bar = ns.HUD.Bars()[1]
    local header, used = ns.HUD.Frames(bar.id)
    bar.show.target = true
    ns.HUD.ApplyBar(bar.id)
    if not tostring(header._driver):find("exists", 1, true) then fail(label .. ": target rule not in the visibility driver: " .. tostring(header._driver)) end
    bar.show.target = nil
    bar.show.mouseover = true
    ns.HUD.ApplyBar(bar.id)
    if header._alpha ~= 0 then fail(label .. ": mouseover bar not faded out") end
    used[1]._scripts.OnEnter(used[1])
    if header._alpha ~= bar.alpha then fail(label .. ": mouseover bar not faded in on enter") end
    used[1]._scripts.OnLeave(used[1])
    if header._alpha ~= 0 then fail(label .. ": mouseover bar not faded out on leave") end
    bar.show.mouseover = nil
    ns.HUD.ApplyBar(bar.id)
    if header._alpha ~= bar.alpha then fail(label .. ": alpha not restored") end
    ns.UI.Open("hud")
    -- dropdown menu: open the content kind menu, check it, pick the second entry, pick the first again
    local dd
    for _, f in ipairs(env._frames) do if f.Pick and f.chevron and f._shown and f._parent and f._parent ~= env.ClassPagesWindow then dd = dd or f end end
    if not dd then fail(label .. ": no dropdown in the HUD tab") else
      dd:Click()
      local menu = env.ClassPagesMenu
      if not (menu and menu._shown) then fail(label .. ": dropdown menu did not open") else
        checkLayout(env, menu, label, "dropdown menu")
        menu.rows[2]:Click()
        if menu._shown then fail(label .. ": menu stayed open after picking") end
      end
      dd:Pick(1)
    end
    for _, k in ipairs({ "Visibility", "Timers", "Layout" }) do
      local seg = findButton(env, ns.L[k])
      if not seg then fail(label .. ": no section button " .. k) else
        seg:Click()
        checkLayout(env, env.ClassPagesWindow, label, "tab hud section " .. k)
        if label:find("modern") and label:find("fresh") then renderPage(env, "hunter-hud-" .. k:lower(), label .. " · hud " .. k, { env.ClassPagesWindow }) end
      end
    end
  end)
  s("key binding mode", function()
    local B = ns.HUD.Binder
    local bar = ns.HUD.Bars()[1]
    local _, used = ns.HUD.Frames(bar.id)
    if not B.SetActive(true) then fail(label .. ": key mode did not start") return end
    checkLayout(env, env.ClassPagesBindPanel, label, "bind panel")
    env._shift = true
    B.Hover(bar.id, 1); B.Press("1")
    env._shift = false
    if bar.keys[1] ~= "SHIFT-1" then fail(label .. ": key not saved: " .. tostring(bar.keys[1])) end
    local bound = env._bindings["SHIFT-1"]
    if not (bound and bound.button == used[1]:GetName()) then fail(label .. ": override binding not set") end
    if not (used[1].cpKey and used[1].cpKey._text == "S-1") then fail(label .. ": key label missing") end
    B.Hover(bar.id, 2); env._shift = true; B.Press("1"); env._shift = false
    if bar.keys[1] ~= nil or bar.keys[2] ~= "SHIFT-1" then fail(label .. ": key not moved to the second button") end
    B.Press("LSHIFT")
    B.Press("DELETE")
    if bar.keys[2] ~= nil or env._bindings["SHIFT-1"] then fail(label .. ": delete did not clear the binding") end
    B.Press("F"); B.Press("ESCAPE")
    if B.IsActive() then fail(label .. ": escape did not end key mode") end
    if bar.keys[2] ~= "F" or not env._bindings.F then fail(label .. ": plain key not bound") end
    ns.HUD.SetEnabled(bar.id, false)
    if env._bindings.F then fail(label .. ": hidden bar keeps its binding") end
    ns.HUD.SetEnabled(bar.id, true)
    if not env._bindings.F then fail(label .. ": binding not restored when shown") end
  end)
  s("counters", function()
    if not hunter then return end
    local found
    for _, bar in ipairs(ns.HUD.Bars()) do
      local _, used = ns.HUD.Frames(bar.id)
      for _, b in pairs(used or {}) do
        local k, v = b.GetAction and b:GetAction()
        if k == "spell" and v == 75 then found = b end
      end
    end
    if not found then return end
    ns.HUD.UpdateCounts()
    if not (found.cpCount and found.cpCount._text == "150") then fail(label .. ": ammunition count not on Auto Shot") end
    local c = found.cpCount._textColor
    if not (c and c[2] < 1) then fail(label .. ": low ammunition not coloured") end
  end)
  s("trainer book and level up", function()
    env._fire("TRAINER_SHOW")
    local store = ns.Trainer.Store()
    if ns.Util.Count(store.list) ~= 4 then fail(label .. ": trainer services not stored: " .. ns.Util.Count(store.list)) end
    ns.UI.Open("trainer")
    checkLayout(env, env.ClassPagesWindow, label, "tab trainer (filled)")
    if label:find("modern") and label:find("fresh") then renderPage(env, "hunter-trainer", label .. " · trainer", { env.ClassPagesWindow }) end
    local before = #env._chat
    env._fire("PLAYER_LEVEL_UP", opts.char.level)
    if #env._chat == before then fail(label .. ": no level-up hint") end
  end)
  s("drag and drop saves", function()
    local bar = ns.HUD.Bars()[1]
    local _, used = ns.HUD.Frames(bar.id)
    LAB._drop(used[3], "item", "item:6948")
    if not (bar.buttons[3] and bar.buttons[3].type == "item" and bar.buttons[3].id == 6948) then fail(label .. ": drop not saved") end
    LAB._drop(used[3], "empty", nil)
    if bar.buttons[3] then fail(label .. ": cleared slot not saved") end
  end)
  s("ready flash and reactive glow out of combat", function()
    if not hunter then return end
    local flashes = env._flashes or 0
    env._cooldowns[14281] = { start = 1000, duration = 6 }
    env._fire("SPELL_UPDATE_COOLDOWN")
    env._advance(6)
    env._cooldowns[14281] = nil
    env._fire("SPELL_UPDATE_COOLDOWN")
    if ns.HUD.stats.ready < 1 or (env._flashes or 0) <= flashes then fail(label .. ": no ready flash after cooldown") end
    env._usable[19306] = true
    env._fire("SPELL_UPDATE_USABLE")
    local glowing = false
    for _, f in ipairs(env._frames) do if f.cpGlow and f.cpGlow._shown then glowing = true end end
    if not glowing then fail(label .. ": counterattack not highlighted") end
    env._fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 3044)
  end)
  s("combat with secret values", function()
    env._combat = true
    env._fire("PLAYER_REGEN_DISABLED")
    env._fire("SPELL_UPDATE_COOLDOWN")
    env._fire("SPELL_UPDATE_USABLE")
    env._fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", SECRET)
    env._fire("PET_BAR_UPDATE_COOLDOWN")
    env._fire("UNIT_PET", SECRET)
    ns.HUD.ApplyBar(ns.HUD.Bars()[1].id)
    ns.HUD.SetEditing(true)
    if ns.Combat.Pending() == 0 then fail(label .. ": bar change not deferred in combat") end
    env.SlashCmdList.CLASSPAGES("probe")
    env._combat = false
    env._fire("PLAYER_REGEN_ENABLED")
    if ns.Combat.Pending() ~= 0 then fail(label .. ": deferred changes not applied after combat") end
  end)
  s("pets, stable, beast training", function()
    env._fire("UNIT_PET", "player")
    env._fire("PET_STABLE_SHOW")
    env._fire("CRAFT_SHOW")
    if not hunter then return end
    local cur = ns.HunterPets.Current()
    if cur.name ~= "Fang" then fail(label .. ": pet not read") end
    if not opts.minimal and cur.happiness ~= 3 then fail(label .. ": happiness not read") end
    if #(ns.HunterPets.Stable().pets or {}) ~= 2 then fail(label .. ": stable not read") end
    if #(ns.HunterPets.Training().list or {}) ~= 3 then fail(label .. ": beast training not read") end
    if not ns.db.families.Wolf then fail(label .. ": family observation missing") end
    ns.UI.Open("pets")
    checkLayout(env, env.ClassPagesWindow, label, "tab pets (with data)")
  end)
  s("minimap button and compartment", function()
    local b = env.ClassPagesMinimapButton
    if not b then fail(label .. ": no minimap button") return end
    if ns.UI.IsOpen() then ns.UI.Toggle() end
    b:Click("LeftButton")
    if not ns.UI.IsOpen() then fail(label .. ": minimap click did not open the window") end
    b:Click("RightButton"); b:Click("RightButton")
    b._scripts.OnDragStart(b); b._scripts.OnUpdate(b); b._scripts.OnDragStop(b)
    b._scripts.OnEnter(b)
    env.ClassPages.Compartment(nil, "LeftButton"); env.ClassPages.CompartmentEnter(nil, b); env.ClassPages.CompartmentLeave()
    env.SlashCmdList.CLASSPAGES("minimap hide"); env.SlashCmdList.CLASSPAGES("minimap show")
  end)
  s("slash commands", function()
    for _, cmd in ipairs({ "", "", "help", "unlock", "lock", "talents", "talents dump", "talents reload", "probe", "feature", "feature hudReady off",
      "feature hudReady on", "profile", "profile copy nonexistent", "keys", "keys", "backup", "restore", "debug on", "debug off", "unknowncmd" }) do
      env.SlashCmdList.CLASSPAGES(cmd)
    end
  end)
  s("debug report", function()
    env.SlashCmdList.CLASSPAGES("debug")
    local report = ns.db.debug.report or ""
    if #report < 500 then fail(label .. ": report too short") end
    for line in report:gmatch("[^\n]+") do
      if line:find("^%[FAIL%]") or line:find("^%[ERR%]") then fail(label .. ": self test: " .. line) end
    end
  end)

  for _, e in ipairs(ns.Health.errors) do
    local expected = opts.unknownEvents and e.where:find("^RegisterEvent")
    if not expected then fail(("%s: addon recorded error at %s: %s"):format(label, e.where, e.err)) end
  end
  local EXPECTED = { SetAlphaFromBoolean = true, SetCooldownFromDurationObject = true }
  for k, n in pairs(env._unknown) do if not EXPECTED[k] then note(("%s: frame method %s (%dx) not in the simulator"):format(label, k, n)) end end
  print(("%-42s %2d steps · %d bars · %d chat lines"):format(label, count, #ns.HUD.Bars(), #env._chat))
  return env.ClassPagesDB, ns
end

local function deepCopy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = deepCopy(v) end return o end

for _, mode in ipairs({ { name = "modern", minimal = false }, { name = "minimal", minimal = true } }) do
  local db = session(mode.name .. " · hunter, fresh install", { minimal = mode.minimal, char = HUNTER }, nil)
  if db then
    local before = 0
    for _, p in pairs(db.profiles) do before = before + #(function() local l = {} for k in pairs(p.hud.bars) do l[#l + 1] = k end return l end)() end
    local saved = deepCopy(db)
    -- damage one saved bar the way a hand edit or a crash could
    for _, p in pairs(saved.profiles) do for _, bar in pairs(p.hud.bars) do bar.cols = "x"; bar.point = "nowhere"; break end end
    local db2, ns2 = session(mode.name .. " · hunter, second login", { minimal = mode.minimal, char = HUNTER }, saved)
    if ns2 then
      local after = #ns2.HUD.Bars()
      if after ~= before then fail(mode.name .. ": second login changed bar count " .. before .. " -> " .. after) end
    end
    session(mode.name .. " · warrior on the same account", { minimal = mode.minimal, char = WARRIOR }, deepCopy(db2))
  end
end
session("modern · hunter, English client", { char = HUNTER, clientLocale = "enUS" }, nil)
session("modern · hunter, newer client interface", { char = HUNTER, interface = 16002, unknownEvents = { PET_UI_UPDATE = true } }, nil)

for _, n in ipairs(NOTES) do print("note: " .. n) end
if #FAILURES > 0 then
  for _, f in ipairs(FAILURES) do print("FAIL " .. f) end
  print(("simulation: %d failure(s)"):format(#FAILURES))
  os.exit(1)
end
print("simulation: OK")
os.exit(0)
