std = "lua51"
max_line_length = 240
self = false
ignore = { "212/_.*", "213", "211/ADDON" }  -- unused args starting with _, unused loop vars, unused ADDON from `local ADDON, ns = ...`

exclude_files = { "tools/tests/**", "ClassPages/Libs/**" }  -- embedded libraries are upstream code

globals = {
  "ClassPages", "ClassPagesDB", "ClassPagesCharDB", "ClassPagesBackupDB",
  "SLASH_CLASSPAGES1", "SLASH_CLASSPAGES2", "SlashCmdList",
}

read_globals = {
  -- Lua / WoW basics
  "DEFAULT_CHAT_FRAME", "CreateFrame", "C_Timer", "C_AddOns", "GetLocale", "GetBuildInfo", "GetTime", "time", "date", "wipe",
  "issecretvalue", "InCombatLockdown", "hooksecurefunc", "UIParent", "GameTooltip", "WOW_PROJECT_ID", "debugstack", "unpack",
  "UnitName", "UnitFullName", "UnitClass", "UnitClassBase", "UnitLevel", "UnitExists", "UnitCreatureFamily", "GetNormalizedRealmName",
  "IsShiftKeyDown", "IsControlKeyDown", "Minimap", "GetCursorPosition", "UISpecialFrames", "LibStub", "Enum", "Constants",
  -- Spells and spellbook
  "C_Spell", "C_SpellBook", "C_Secrets", "C_CurveUtil", "C_SpellActivationOverlay", "ActionButtonSpellAlertManager",
  "IsUsableSpell", "IsPlayerSpell", "IsSpellKnown", "IsPassiveSpell", "GetSpellBookItemInfo", "GetSpellBookItemName",
  "GetNumSpellTabs", "GetSpellTabInfo", "GetProfessions", "GetProfessionInfo",
  -- Secure frames
  "RegisterStateDriver", "UnregisterStateDriver", "SetOverrideBindingClick", "ClearOverrideBindings", "GetInventoryItemID", "C_Item",
  "IsAltKeyDown", "GetShapeshiftFormInfo", "GetNumShapeshiftForms", "GetMoney", "IsTradeskillTrainer",
  "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceLevelReq", "GetTrainerServiceCost",
  -- Talents
  "C_ClassTalents", "C_Traits", "GetSpecializationInfoForClassID", "GetNumTalentTabs", "GetTalentTabInfo", "GetNumTalents",
  "GetTalentInfo", "GetTalentPrereqs",
  -- Pets
  "GetPetActionInfo", "GetPetActionCooldown", "GetPetActionSlotUsable", "GetPetHappiness", "GetPetLoyalty",
  "GetPetTrainingPoints", "GetPetFoodTypes", "GetPetExperience", "C_StableInfo", "GetStablePetInfo",
  "GetNumCrafts", "GetCraftInfo", "C_TradeSkillUI", "C_QuestLog", "GetCraftDisplaySkillLine", "GetCraftName", "GetInventoryItemCount",
}

files["ClassPages/Locales/*.lua"] = { max_line_length = false }  -- one translation per line
files["ClassPages/Classes/Data/*.lua"] = { max_line_length = false }  -- one entry per line
