-- get addon namespace
local addonName, ns = ...

ns.PDHOptionsDb = ns.PDHOptionsDb or {
	debugVisuals = false,
	debugLogging = false,
}


ns.optionsCategory = Settings.RegisterVerticalLayoutCategory(addonName)

-- Debug visuals checkbox
local debugVisuals = Settings.RegisterProxySetting(
    optionsCategory,
    "pdh.debugVisuals",
    Settings.VarType.Boolean,
    "Visual debugging",
    false,
    PDHOptionsDb,
    "debugVisuals"
)

Settings.CreateCheckbox(ns.optionsCategory, debugVisuals,
    "Add debugging widgets to the tracker icons")

-- Debug logging checkbox
local debugLogging = Settings.RegisterProxySetting(
    ns.optionsCategory,
    "pdh.debugLogging",
    Settings.VarType.Boolean,
    "Debugging messages",
    false,
    PDHOptionsDb,
    "debugLogging"
)

Settings.CreateCheckbox(ns.optionsCategory, debugLogging,
    "Print debug log messages to the chat console. Prints A LOT of text.")

Settings.RegisterAddOnCategory(ns.optionsCategory)



-------------------------------------------------------------------------------------
-- There is no button for vertical layouts and it is impossible to mix a canvas into
-- the vertical layout. So just create a second page with nothing but a reset button.
-------------------------------------------------------------------------------------

local frame = CreateFrame("Frame", addonName .. "Reset")
frame:SetSize(500, 400)

-- Add a button
local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
btn:SetSize(120, 24)
btn:SetPoint("TOPLEFT", 16, -16)
btn:SetText("Reset")
btn:SetScript("OnClick", function() ns:reset() end)

local resetCategory = Settings.RegisterCanvasLayoutSubcategory(ns.optionsCategory, frame, "Reset")
Settings.RegisterAddOnCategory(resetCategory)
