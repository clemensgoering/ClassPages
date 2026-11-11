-- ClassPages: "Trainer" tab for every class. Shows the trainer book (Classes/Trainer.lua) in the shared list view:
-- learnable now (with the total cost), the next two levels, and with "All levels" everything later.
local ADDON, ns = ...
local UI = ns.UI

UI.RegisterTab("trainer", "Trainer", UI.GuideView({
  key = "trainer",
  intro = "What your trainer teaches now and soon, with costs.",
  empty = "Visit your class trainer once to fill this list.",
  dynamic = function(level, mode)
    local store = ns.Trainer.Store()
    if not store then return {} end
    local money = GetMoney and GetMoney()
    if ns.Secret.IsSecret(money) then money = nil end
    return (ns.Trainer.Rows(store, level, mode, money))
  end,
}), { icon = "Interface\\Icons\\INV_Misc_Book_09", order = 25 })
