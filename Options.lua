-- get addon namespace
local addonName, ns = ...

PetesDefensiveHistoryOptionsDb = PetesDefensiveHistoryOptionsDb or {
    disableInference = false,
	debugVisuals = false,
	debugLogging = false,
    dataMiningMode = false
}


ns.optionsCategory = Settings.RegisterVerticalLayoutCategory(addonName)

-- Disable all inference. Put everything in the history tray
local disableInference = Settings.RegisterProxySetting(
    optionsCategory,
    "pdh.disableInference",
    Settings.VarType.Boolean,
    "Disable inference",
    false,
    function() return PetesDefensiveHistoryOptionsDb.disableInference or false end,
    function(value) PetesDefensiveHistoryOptionsDb.disableInference = value  end
)

Settings.CreateCheckbox(ns.optionsCategory, disableInference,
    "Disable logic to infer abilities. All abilities will instead be sent to the history tracker for the unit on which they were cast. Each ability will receive a count-up timer that stops at the maximum cooldown length for all abilities that can target that player.")



-- Debug visuals checkbox
local debugVisuals = Settings.RegisterProxySetting(
    optionsCategory,
    "pdh.debugVisuals",
    Settings.VarType.Boolean,
    "Visual debugging",
    false,
    function() return PetesDefensiveHistoryOptionsDb.debugVisuals or false end,
    function(value) PetesDefensiveHistoryOptionsDb.debugVisuals = value  end
)

Settings.CreateCheckbox(ns.optionsCategory, debugVisuals,
    "Add debugging widgets to the tracker icons. This option requires a /reload to take effect.")



-- Debug logging checkbox
local debugLogging = Settings.RegisterProxySetting(
    ns.optionsCategory,
    "pdh.debugLogging",
    Settings.VarType.Boolean,
    "Debugging messages",
    false,
    function() return PetesDefensiveHistoryOptionsDb.debugLogging or false end,
    function(value) PetesDefensiveHistoryOptionsDb.debugLogging = value  end
)

Settings.CreateCheckbox(ns.optionsCategory, debugLogging,
    "Print debug log messages to the chat console. Prints A LOT of text.")



-- Data mining mode checkbox
local dataMiningMode = Settings.RegisterProxySetting(
    ns.optionsCategory,
    "pdh.dataMiningMode",
    Settings.VarType.Boolean,
    "Data mining mode",
    false,
    function() return PetesDefensiveHistoryOptionsDb.dataMiningMode or false end,
    function(value) PetesDefensiveHistoryOptionsDb.dataMiningMode = value  end
)

Settings.CreateCheckbox(ns.optionsCategory, dataMiningMode,
    "Print very verbose aura updates that help build the tracked ability database by hand. Prints secret values, will cause errors in real content. Intended for developers.")

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
