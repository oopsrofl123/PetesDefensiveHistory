-- get addon namespace
local addonName, ns = ...

PetesDefensiveHistoryOptionsDb = PetesDefensiveHistoryOptionsDb or {
    iconSize = 32,
    iconSpacing = 3,
    textSize = 15,
    disableInference = false,
    disableHistoryTray = false,
	debugVisuals = false,
	debugLogging = false,
    dataMiningMode = false
}


ns.optionsCategory, layout = Settings.RegisterVerticalLayoutCategory(addonName)

layout:AddInitializer(
    Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", { name='Appearance and behavior' })
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
            ns:updateHistoryTrayRow(slot)
        end
    end
)
local options = Settings.CreateSliderOptions(8, 64, 1)
options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right) --, FormatPercentage)
Settings.CreateSlider(ns.optionsCategory, setting, options, "Size of tracker icons")



-- Set cooldown timer text size
local setting = Settings.RegisterProxySetting(
    ns.optionsCategory,
    "textSize",
    Settings.VarType.Number,
    "Timer text size",
    15,
    function() return PetesDefensiveHistoryOptionsDb.textSize or 15 end,
    function(value)
        PetesDefensiveHistoryOptionsDb.textSize = value
        for slot, _ in pairs(ns.allSlots) do
            ns:updateStaticRow(slot)
            ns:updateHistoryTrayRow(slot)
        end
    end
)
local options = Settings.CreateSliderOptions(4, 32, 1)
options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
Settings.CreateSlider(ns.optionsCategory, setting, options, "Text size for cooldown timers")



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
            ns:updateHistoryTrayRow(slot)
        end
    end
)
local options = Settings.CreateSliderOptions(0, 10, 1)
options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
Settings.CreateSlider(ns.optionsCategory, setting, options, "Spacing between tracker icons")


-- Disable all inference. Put everything in the history tray
local disableInference = Settings.RegisterProxySetting(
    optionsCategory,
    "pdh.disableInference",
    Settings.VarType.Boolean,
    "Disable inference",
    false,
    function() return PetesDefensiveHistoryOptionsDb.disableInference or false end,
    function(value)
        PetesDefensiveHistoryOptionsDb.disableInference = value
        for slot, _ in pairs(ns.allSlots) do
            ns:updateStaticRow(slot)
        end
    end
)
Settings.CreateCheckbox(ns.optionsCategory, disableInference,
    "Disable logic to infer abilities and the associated row of icons. All abilities will instead be sent to the history tray for the unit on which they were cast (which may not be the caster!). Items in the history tray receive a count-up timer that stops at the maximum cooldown length for all abilities that can target that unit and the player must know the associated cooldown length.")


local setting = Settings.RegisterProxySetting(
    optionsCategory,
    "pdh.disableHistoryTray",
    Settings.VarType.Boolean,
    "Disable history tray",
    false,
    function() return PetesDefensiveHistoryOptionsDb.disableHistoryTray or false end,
    function(value)
        PetesDefensiveHistoryOptionsDb.disableHistoryTray = value
        for slot, _ in pairs(ns.allSlots) do
            ns:updateHistoryTrayRow(slot)
        end
    end
)
Settings.CreateCheckbox(ns.optionsCategory, setting,
    "Disable the history tray. Do not send abilities that cannot be guessed to the history tray. Instead, quietly ignore them and only show abilities when they are identified. Careful: some abilities can only |cffff0000sometimes|r be guessed! When they are not, they are normally sent to the history tray and appear as available in the cooldown tracker row. If the history tray is hidden, you will not see this and the ability will simply appear to be available.")




layout:AddInitializer(
    Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate",
        { name='Developer options' })
)


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




----------------------------------------------------------------------------------
-- Options subpanel for selecting which spells to track
----------------------------------------------------------------------------------

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


-- These are the locale-independent class names that key into several tables.
-- The display strings are different.
local classes = {
    { "DEATHKNIGHT", { 250, 251, 252 } },
    { "DEMONHUNTER", { 577, 581, 1480 } },
    { "DRUID", { 102, 103, 104, 105 } },
    { "EVOKER", { 1467, 1468, 1473 } },
    { "HUNTER", { 253, 254, 255 } },
    { "MAGE", { 62, 63, 64 } },
    { "MONK", { 268, 269, 270 } },
    { "PALADIN", { 65, 66, 70 } },
    { "PRIEST", { 256, 257, 258 } },
    { "ROGUE", { 259, 260, 261 } },
    { "SHAMAN", { 262, 263, 264 } },
    { "WARLOCK", { 265, 266, 267 } },
    { "WARRIOR", { 71, 72, 73 } }
}

for _, classData in pairs(classes) do
    local classFile = classData[1]
    local specIdList = classData[2]
    local class = LOCALIZED_CLASS_NAMES_MALE[classFile] -- maps "WARRIOR" -> "Warrior" or "Guerrier"

    -- XXX: TODO: not sure how to get the font string object to :SetTextColor()
    --local classColor = RAID_CLASS_COLORS[class]
    layout:AddInitializer(
        Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", { name=class })
    )

    for _, specId in pairs(specIdList) do
        for _, ability in pairs(ns.SpecAbilityDb[specId]) do
            -- icons might not be unique across classes. don't use specId because
            -- we DO want to collapse abilities with icons within specs so there aren't
            -- a zillion options
            if not uniqueAbilities[class .. "_" .. ability.iconId] then
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
                uniqueAbilities[class .. "_" .. ability.iconId] = setting
            end
        end
    end
end

Settings.RegisterAddOnCategory(abilities)
