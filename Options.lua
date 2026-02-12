PDHOptionsDb = PDHOptionsDb or {
	debugVisuals = false,
	debugLogging = false,
}


optionsCategory = Settings.RegisterVerticalLayoutCategory("PetesDefensiveHistory")

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

Settings.CreateCheckbox(optionsCategory, debugVisuals, "Add debugging widgets to the tracker icons")

-- Debug logging checkbox
local debugLogging = Settings.RegisterProxySetting(
    optionsCategory,
    "pdh.debugLogging",
    Settings.VarType.Boolean,
    "Debugging messages",
    false,
    PDHOptionsDb,
    "debugLogging"
)

Settings.CreateCheckbox(optionsCategory, debugLogging, "Print debug log messages to the chat console. Prints A LOT of text.")

Settings.RegisterAddOnCategory(optionsCategory)



-------------------------------------------------------------------------------------
-- There is no button for vertical layouts and it is impossible to mix a canvas into
-- the vertical layout. So just create a second page with nothing but a reset button.
-------------------------------------------------------------------------------------

local frame = CreateFrame("Frame", "PetesDefensiveHistoryReset")
frame:SetSize(500, 400)

-- Add a button
local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
btn:SetSize(120, 24)
btn:SetPoint("TOPLEFT", 16, -16)
btn:SetText("Reset")
btn:SetScript("OnClick", function() pdhReset() end)

local resetCategory = Settings.RegisterCanvasLayoutSubcategory(optionsCategory, frame, "Reset")
Settings.RegisterAddOnCategory(resetCategory)
