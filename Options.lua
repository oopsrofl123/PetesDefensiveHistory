-- get addon namespace
local addonName, ns = ...

PetesDefensiveHistoryOptionsDb = PetesDefensiveHistoryOptionsDb or {
    iconSize = 32,
    iconSpacing = 3,
    disableInference = false,
	debugVisuals = false,
	debugLogging = false,
    dataMiningMode = false
}


ns.optionsCategory, layout = Settings.RegisterVerticalLayoutCategory(addonName)

layout:AddInitializer(
    Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", { name='Appearance' })
)

-- Set tracker icon size
local setting = Settings.RegisterProxySetting(
    ns.optionsCategory,
    "iconSize",
    Settings.VarType.Number,
    "Icon size",
    32,
    function() return PetesDefensiveHistoryOptionsDb.iconSize or 32 end,
    function(value)
        PetesDefensiveHistoryOptionsDb.iconSize = value
        for slot, _ in pairs(ns.allSlots) do
            ns:updateStaticRow(slot)
        end
    end
)
local options = Settings.CreateSliderOptions(8, 64, 1)
options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right) --, FormatPercentage)

Settings.CreateSlider(ns.optionsCategory, setting, options, "Size of tracker icons")


-- Set spacing between tracker items
local setting = Settings.RegisterProxySetting(
    ns.optionsCategory,
    "iconSpacing",
    Settings.VarType.Number,
    "Icon spacing",
    3,
    function() return PetesDefensiveHistoryOptionsDb.iconSpacing or 3 end,
    function(value)
        PetesDefensiveHistoryOptionsDb.iconSpacing = value
        for slot, _ in pairs(ns.allSlots) do
            ns:updateStaticRow(slot)
        end
    end
)
local options = Settings.CreateSliderOptions(0, 10, 1)
options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)

Settings.CreateSlider(ns.optionsCategory, setting, options, "Spacing between tracker icons")





layout:AddInitializer(
    Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", { name='Developer options' })
)

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


local abilities, layout = Settings.RegisterVerticalLayoutSubcategory(ns.optionsCategory, "Tracked abilities")


-- since abilities are replicated for each spec, track unique ones here to prevent
-- adding checkboxes multiple times for the same ability.
local uniqueAbilities = {}

local checkAll = CreateSettingsButtonInitializer(
    "Track all abilities",
    "Check all",
    function()
        for _, setting in pairs(uniqueAbilities) do
            setting:SetValue(true)
        end
    end,
    "Select all checkboxes",
    true, -- addSearchTags
    nil, -- newTagID
    nil -- gameDataFunc
)

layout:AddInitializer(checkAll)


local uncheckAll = CreateSettingsButtonInitializer(
    "Track no abilities",
    "Uncheck all",
    function()
        for _, setting in pairs(uniqueAbilities) do
            setting:SetValue(false)
        end
    end,
    "Unselect all checkboxes",
    true, -- addSearchTags
    nil, -- newTagID
    nil -- gameDataFunc
)

layout:AddInitializer(uncheckAll)


local classes = {
    ["Death Knight"] = { 250, 251, 252 },
    ["Demon Hunter"] = { 577, 581, 1480 },
    ["Druid"] = { 102, 103, 104, 105 },
    ["Evoker"] = { 1467, 1468, 1473 },
    ["Hunter"] = { 253, 254, 255 },
    ["Mage"] = { 62, 63, 64 },
    ["Monk"] = { 268, 269, 270 },
    ["Paladin"] = { 65, 66, 70 },
    ["Priest"] = { 256, 257, 258 },
    ["Rogue"] = { 259, 260, 261 },
    ["Shaman"] = { 262, 263, 264 },
    ["Warlock"] = { 265, 266, 267 },
    ["Warrior"]  = { 71, 72, 73 }
}

for class, specIdList in pairs(classes) do
    layout:AddInitializer(
        Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", { name=class })
    )

    for _, specId in pairs(specIdList) do
        for _, ability in pairs(ns.SpecAbilityDb[specId]) do
            if not uniqueAbilities[ability.iconId] then
                -- set default true values
                PetesDefensiveHistoryOptionsDb["show_" .. ability.iconId] = true
                local setter = function(value)
                    PetesDefensiveHistoryOptionsDb["show_" .. ability.iconId] = value
                    for slot, _ in pairs(ns.allSlots) do
                        ns:updateStaticRow(slot)
                    end
                end
                setting = Settings.RegisterProxySetting(
                    ability,
                    "show_" .. ability.iconId,
                    Settings.VarType.Boolean,
                    ability.name,
                    true,
                    function() return PetesDefensiveHistoryOptionsDb["show_"..ability.iconId] end,
                    setter)
                Settings.CreateCheckbox(abilities, setting)
                --uniqueAbilities[ability.iconId] = setter
                uniqueAbilities[ability.iconId] = setting
            end
        end
    end
end

Settings.RegisterAddOnCategory(abilities)
-------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------
--local frame = CreateFrame("Frame", addonName .. "Reset")
--frame:SetSize(500, 400)

-- Add a button
--local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
--btn:SetSize(120, 24)
--btn:SetPoint("TOPLEFT", 16, -16)
--btn:SetText("Reset")
--btn:SetScript("OnClick", function() ns:reset() end)

--local resetCategory = Settings.RegisterCanvasLayoutSubcategory(ns.optionsCategory, frame, "Reset")
--Settings.RegisterAddOnCategory(resetCategory)
