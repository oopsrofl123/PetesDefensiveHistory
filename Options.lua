-- get addon namespace
local addonName, ns = ...

local optionsDefaults = {
    iconSize = 32,
    iconSpacing = 3,
    textSize = 15,
    disableInference = false,
    disableHistoryTray = false,
    hideHistoryItemsAtMaxCd = false,
    showTooltips = true,
	debugVisuals = false,
	debugLogging = false,
    dataMiningMode = false
}

PetesDefensiveHistoryOptionsDb = PetesDefensiveHistoryOptionsDb or optionsDefaults


-- Universal getter. Use this to access settings, not direct keying
-- into the settings table. No idea why I capitalized this.
function ns:GetOption(opt)
    return PetesDefensiveHistoryOptionsDb[opt] or optionsDefaults[opt]
end



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
    optionsDefaults['iconSize'],
    function() return ns:GetOption('iconSize') end,
    function(value)
        PetesDefensiveHistoryOptionsDb.iconSize = value
        for slot, _ in pairs(ns.allSlots) do
            ns:updateTrackerUI(slot)
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
    optionsDefaults['textSize'],
    function() return ns:GetOption('textSize') end,
    function(value)
        PetesDefensiveHistoryOptionsDb.textSize = value
        for slot, _ in pairs(ns.allSlots) do
            ns:updateTrackerUI(slot)
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
    optionsDefaults['iconSpacing'],
    function() return ns:GetOption('iconSpacing') end,
    function(value)
        PetesDefensiveHistoryOptionsDb.iconSpacing = value
        for slot, _ in pairs(ns.allSlots) do
            ns:updateTrackerUI(slot)
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
    optionsDefaults['disableInference'],
    function() return ns:GetOption('disableInference') end,
    function(value)
        PetesDefensiveHistoryOptionsDb.disableInference = value
        for slot, _ in pairs(ns.allSlots) do
            ns:updateTrackerUI(slot)
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
    optionsDefaults['disableHistoryTray'],
    function() return ns:GetOption('disableHistoryTray') end,
    function(value)
        PetesDefensiveHistoryOptionsDb.disableHistoryTray = value
        for slot, _ in pairs(ns.allSlots) do
            ns:updateTrackerUI(slot)
        end
    end
)
Settings.CreateCheckbox(ns.optionsCategory, setting,
    "Disable the history tray. Do not send abilities that cannot be guessed to the history tray. Instead, quietly ignore them and only show abilities when they are identified. Careful: some abilities can only |cffff0000sometimes|r be guessed! When they are not, they are normally sent to the history tray and appear as available in the cooldown tracker row. If the history tray is hidden, you will not see this and the ability will simply appear to be available.")

local setting = Settings.RegisterProxySetting(
    optionsCategory,
    "pdh.hideHistoryItemsAtMaxCd",
    Settings.VarType.Boolean,
    "Hide old history tray items",
    optionsDefaults['hideHistoryItemsAtMaxCd'],
    function() return ns:GetOption('hideHistoryItemsAtMaxCd') end,
    function(value) PetesDefensiveHistoryOptionsDb.hideHistoryItemsAtMaxCd = value end
)
Settings.CreateCheckbox(ns.optionsCategory, setting,
    "Hide unidentified abilities in the history tray after the maximum possible cooldown is reached.")

local setting = Settings.RegisterProxySetting(
    optionsCategory,
    "pdh.showTooltips",
    Settings.VarType.Boolean,
    "Show spell tooltips",
    optionsDefaults['showTooltips'],
    function() return ns:GetOption('showTooltips') end,
    function(value) PetesDefensiveHistoryOptionsDb.showTooltips = value end
)
Settings.CreateCheckbox(ns.optionsCategory, setting,
    "Show spell tooltips for abilities that can be identified. This does not work for abilities in the history tray, since these abilities are not identified.")



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
    optionsDefaults['debugVisuals'],
    function() return ns:GetOption('debugVisuals') end,
    function(value)
        PetesDefensiveHistoryOptionsDb.debugVisuals = value
        for slot, _ in pairs(ns.allSlots) do
            ns:updateTrackerUI(slot)
        end
    end
)

Settings.CreateCheckbox(ns.optionsCategory, debugVisuals,
    "Add debugging widgets to the tracker icons. This option requires a /reload to take effect.")



-- Debug logging checkbox
local debugLogging = Settings.RegisterProxySetting(
    ns.optionsCategory,
    "pdh.debugLogging",
    Settings.VarType.Boolean,
    "Debugging messages",
    optionsDefaults['debugLogging'],
    function() return ns:GetOption('debugLogging') end,
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
    optionsDefaults['dataMiningMode'],
    function() return ns:GetOption('dataMiningMode') end,
    function(value) PetesDefensiveHistoryOptionsDb.dataMiningMode = value  end
)

Settings.CreateCheckbox(ns.optionsCategory, dataMiningMode,
    "Print very verbose aura updates that help build the tracked ability database by hand. Prints secret values, will cause errors in real content. Intended for developers.")

Settings.RegisterAddOnCategory(ns.optionsCategory)




----------------------------------------------------------------------------------
-- Options subpanel for selecting which spells to track
----------------------------------------------------------------------------------

local category, layout = Settings.RegisterVerticalLayoutSubcategory(ns.optionsCategory, "Tracked abilities")


-- since abilities are replicated for each spec, track unique ones here to prevent
-- adding checkboxes multiple times for the same ability.
local abilitySetters = {}

local checkAll = CreateSettingsButtonInitializer(
    "Track all abilities",
    "Check all",
    function()
        for _, setting in pairs(abilitySetters) do
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
        for _, setting in pairs(abilitySetters) do
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
-- The display strings are different. The spec IDs are no longer used.
local orderedClasses = {
    "DEATHKNIGHT",   -- { 250, 251, 252 } },
    "DEMONHUNTER",   -- { 577, 581, 1480 } },
    "DRUID",         -- { 102, 103, 104, 105 } },
    "EVOKER",        -- { 1467, 1468, 1473 } },
    "HUNTER",        -- { 253, 254, 255 } },
    "MAGE",          -- { 62, 63, 64 } },
    "MONK",          -- { 268, 269, 270 } },
    "PALADIN",       -- { 65, 66, 70 } },
    "PRIEST",        -- { 256, 257, 258 } },
    "ROGUE",         -- { 259, 260, 261 } },
    "SHAMAN",        -- { 262, 263, 264 } },
    "WARLOCK",       -- { 265, 266, 267 } },
    "WARRIOR",       -- { 71, 72, 73 } }
}

for _, classFile in pairs(orderedClasses) do
    local abilities = ns.AbilityDb[classFile]
    local class = LOCALIZED_CLASS_NAMES_MALE[classFile] -- maps "WARRIOR" -> "Warrior" or "Guerrier"

    -- XXX: TODO: not sure how to get the font string object to :SetTextColor()
    --local classColor = RAID_CLASS_COLORS[class]
    layout:AddInitializer(
        Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", { name=class })
    )

    for _, ability in pairs(abilities) do
        -- set default true values
        PetesDefensiveHistoryOptionsDb["show_" .. ability.id] = true
        local setter = function(value)
            PetesDefensiveHistoryOptionsDb["show_" .. ability.id] = value
            for slot, _ in pairs(ns.allSlots) do
                ns:updateTrackerUI(slot)
            end
        end
        setting = Settings.RegisterProxySetting(
            ability,
            "show_" .. ability.id,
            Settings.VarType.Boolean,
            ability.name,
            true,
            function() return PetesDefensiveHistoryOptionsDb["show_"..ability.id] end,
            setter)
        Settings.CreateCheckbox(category, setting)
        abilitySetters[class .. "_" .. ability.id] = setting
    end
end

Settings.RegisterAddOnCategory(category)
