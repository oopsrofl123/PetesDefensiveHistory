-- get addon namespace
local addonName, ns = ...

local optionsDefaults = {
    enable = true,
    enableSolo = true,
    enableParty = true,
    enableArena = false,
    enableRaid = false,
    enableBattleground = false,

    iconSize = 32,
    iconSpacing = 3,
    textSize = 15,
    disableInference = false,
    disableCDRTrackers = false,
    disableHistoryTray = false,

    enableTTS = false,
    TTSnoUntracked = false,
    TTSnoSelfCasts = false,

    hideHistoryItemsAtMaxCd = false,
    showTooltips = true,
	debugVisuals = false,
	debugLogging = false,
    dataMiningMode = false,
    muteVerboseLogging = true,
    runGC = false,
}

PetesDefensiveHistoryOptionsDb = PetesDefensiveHistoryOptionsDb or optionsDefaults


-- Universal getter. Use this to access settings, not direct keying
-- into the settings table. No idea why I capitalized this.
function ns:GetOption(opt)
    local val = PetesDefensiveHistoryOptionsDb[opt]
    if val == nil then
        return optionsDefaults[opt]
    end
    return val
end



ns.optionsCategory, layout = Settings.RegisterVerticalLayoutCategory(addonName)

layout:AddInitializer(
    Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", { name='Active inference content' })
)

-- Options that change whether the addon is currently active need to handle data
-- cleanup and UI hiding. Inactive could mean the addon is totally disabled or it
-- is only inactive in this content (e.g., a raid).
--
-- Return a valid setter function.
local function makeActiveSetter(varName, value)
    local function setter(value)
        PetesDefensiveHistoryOptionsDb[varName] = value
        ns:handleAddonActiveStateChange()
    end
    return setter
end

-- Disable the addon entirely
local setting = Settings.RegisterProxySetting(
    ns.optionsCategory,
    "enable",
    Settings.VarType.Boolean,
    "Enable",
    optionsDefaults['enable'],
    function() return ns:GetOption('enable') end,
    makeActiveSetter('enable')
)
toplevel =Settings.CreateCheckbox(ns.optionsCategory, setting,
    "Enable the addon. Disabling the addon prevents all event processing and deletes all collected data, including player info, including talents, tracked cooldowns and event histories.")


local setting = Settings.RegisterProxySetting(
    ns.optionsCategory,
    "enableSolo",
    Settings.VarType.Boolean,
    "Solo",
    optionsDefaults['enableSolo'],
    function() return ns:GetOption('enableSolo') end,
    makeActiveSetter('enableSolo')
)
child = Settings.CreateCheckbox(ns.optionsCategory, setting, "Enable while solo.")
child:SetParentInitializer(toplevel)

local setting = Settings.RegisterProxySetting(
    ns.optionsCategory,
    "enableParty",
    Settings.VarType.Boolean,
    "Party",
    optionsDefaults['enableParty'],
    function() return ns:GetOption('enableParty') end,
    makeActiveSetter('enableParty')
)
child = Settings.CreateCheckbox(ns.optionsCategory, setting, "Enable in non-raid, non-arena group content.")
child:SetParentInitializer(toplevel)

-- XXX: TODO: Arena and raids. not supported yet (needs different frame names)
--local setting = Settings.RegisterProxySetting(
    --ns.optionsCategory,
    --"enableArena",
    --Settings.VarType.Boolean,
    --"Arena",
    --optionsDefaults['enableArena'],
    --function() return ns:GetOption('enableArena') end,
    --makeActiveSetter('enableArena'),
    --function() return false end
--)
--child = Settings.CreateCheckbox(ns.optionsCategory, setting, "Enable in arenas.")
--child:SetParentInitializer(toplevel)
--
--local setting = Settings.RegisterProxySetting(
    --ns.optionsCategory,
    --"enableRaid",
    --Settings.VarType.Boolean,
    --"Raid",
    --optionsDefaults['enableRaid'],
    --function() return ns:GetOption('enableRaid') end,
    --makeActiveSetter('enableRaid')
--)
--child = Settings.CreateCheckbox(ns.optionsCategory, setting, "Enable in raids.")
--child:SetParentInitializer(toplevel)



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
        ns:updateTrackerUI()
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
        ns:updateTrackerUI()
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
        ns:updateTrackerUI()
    end
)
local options = Settings.CreateSliderOptions(0, 10, 1)
options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
Settings.CreateSlider(ns.optionsCategory, setting, options, "Spacing between tracker icons")


-- Disable all inference. Put everything in the history tray
local disableInference = Settings.RegisterProxySetting(
    ns.optionsCategory,
    "disableInference",
    Settings.VarType.Boolean,
    "Disable inference",
    optionsDefaults['disableInference'],
    function() return ns:GetOption('disableInference') end,
    function(value)
        PetesDefensiveHistoryOptionsDb.disableInference = value
        ns:updateTrackerUI()
    end
)
Settings.CreateCheckbox(ns.optionsCategory, disableInference,
    "Disable logic to infer abilities and the associated row of icons. All abilities will instead be sent to the history tray for the unit on which they were cast (which may not be the caster!). Items in the history tray receive a count-up timer that stops at the maximum cooldown length for all abilities that can target that unit and the player must know the associated cooldown length.")

local setting = Settings.RegisterProxySetting(
    ns.optionsCategory,
    "disableCDRTrackers",
    Settings.VarType.Boolean,
    "Disable inaccurate timers",
    optionsDefaults['disableCDRTrackers'],
    function() return ns:GetOption('disableCDRTrackers') end,
    function(value)
        PetesDefensiveHistoryOptionsDb.disableCDRTrackers = value
        ns:updateTrackerUI()
    end
)
Settings.CreateCheckbox(ns.optionsCategory, setting,
    "Dynamic cooldown reduction (e.g., each cast of Power Word: Shield reduces the cooldown of Pain Suppression) cannot be tracked. Normally, these abilities will count down to the MAXIMUM cooldown time. Enabling this option will instead send those abilities to the history tray, declining to show an inaccurate cooldown swipe. NOTE: cooldown timers are especially inaccurate for abilities with BOTH dynamic cooldown reduction and charges (e.g., Shield Wall, Guardian of Ancient Kings, Pain Suppresion, etc.).") 


local setting = Settings.RegisterProxySetting(
    ns.optionsCategory,
    "disableHistoryTray",
    Settings.VarType.Boolean,
    "Disable history tray",
    optionsDefaults['disableHistoryTray'],
    function() return ns:GetOption('disableHistoryTray') end,
    function(value)
        PetesDefensiveHistoryOptionsDb.disableHistoryTray = value
        ns:updateTrackerUI()
    end
)
Settings.CreateCheckbox(ns.optionsCategory, setting,
    "Disable the history tray. Do not send abilities that cannot be guessed to the history tray. Instead, quietly ignore them and only show abilities when they are identified. Careful: some abilities can only |cffff0000sometimes|r be guessed! When they are not, they are normally sent to the history tray and appear as available in the cooldown tracker row. If the history tray is hidden, you will not see this and the ability will simply appear to be available.")

local setting = Settings.RegisterProxySetting(
    ns.optionsCategory,
    "hideHistoryItemsAtMaxCd",
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
    "showTooltips",
    Settings.VarType.Boolean,
    "Show spell tooltips",
    optionsDefaults['showTooltips'],
    function() return ns:GetOption('showTooltips') end,
    function(value) PetesDefensiveHistoryOptionsDb.showTooltips = value end
)
Settings.CreateCheckbox(ns.optionsCategory, setting,
    "Show spell tooltips for abilities that can be identified. This does not work for abilities in the history tray, since these abilities are not identified.")





-- Settings for text to speech --------------------------------------------------
layout:AddInitializer(
    Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", { name='Text to speech' })
)

local setting = Settings.RegisterProxySetting(
    ns.optionsCategory,
    "enableTTS",
    Settings.VarType.Boolean,
    "Enable text to speech",
    optionsDefaults['enableTTS'],
    function() return ns:GetOption('enableTTS') end,
    function(value) PetesDefensiveHistoryOptionsDb.enableTTS = value end
)
toplevel = Settings.CreateCheckbox(ns.optionsCategory, setting,
    "Say the names of abilities when they are used. Only applies to abilities that can be instantly identified.") -- XXX: TODO: Uses the voice, speed and volume settings in Audio Assist > Combat Audio Alerts.")

local setting = Settings.RegisterProxySetting(
    ns.optionsCategory,
    "TTSnoUntracked",
    Settings.VarType.Boolean,
    "Only tracked abilities",
    optionsDefaults['TTSnoUntracked'],
    function() return ns:GetOption('TTSnoUntracked') end,
    function(value) PetesDefensiveHistoryOptionsDb.TTSnoUntracked = value end
)
child = Settings.CreateCheckbox(ns.optionsCategory, setting,
    "Do not announce abilities that are unselected in the Tracked Abilities list.")
child:SetParentInitializer(toplevel)

local setting = Settings.RegisterProxySetting(
    ns.optionsCategory,
    "TTSnoSelfCasts",
    Settings.VarType.Boolean,
    "No self-casts",
    optionsDefaults['TTSnoSelfCasts'],
    function() return ns:GetOption('TTSnoSelfCasts') end,
    function(value) PetesDefensiveHistoryOptionsDb.TTSnoSelfCasts = value end
)
child = Settings.CreateCheckbox(ns.optionsCategory, setting,
    "Do not announce abilities cast by you.")
child:SetParentInitializer(toplevel)




-- Settings for development --------------------------------------------------
layout:AddInitializer(
    Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate",
        { name='Developer options' })
)


-- Debug visuals checkbox
local debugVisuals = Settings.RegisterProxySetting(
    ns.optionsCategory,
    "debugVisuals",
    Settings.VarType.Boolean,
    "Visual debugging",
    optionsDefaults['debugVisuals'],
    function() return ns:GetOption('debugVisuals') end,
    function(value)
        PetesDefensiveHistoryOptionsDb.debugVisuals = value
        ns:updateTrackerUI()
    end
)

Settings.CreateCheckbox(ns.optionsCategory, debugVisuals,
    "Add debugging widgets to the tracker icons. This option requires a /reload to take effect.")



-- Debug logging checkbox
local debugLogging = Settings.RegisterProxySetting(
    ns.optionsCategory,
    "debugLogging",
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
    "dataMiningMode",
    Settings.VarType.Boolean,
    "Data mining mode",
    optionsDefaults['dataMiningMode'],
    function() return ns:GetOption('dataMiningMode') end,
    function(value) PetesDefensiveHistoryOptionsDb.dataMiningMode = value  end
)

Settings.CreateCheckbox(ns.optionsCategory, dataMiningMode,
    "Print very verbose aura updates that help build the tracked ability database by hand. Prints secret values, will cause errors in real content. Intended for developers.")


-- Don't log extremely spammy messages like talent ranks and ability inference
-- during the zero knowledge solve.
local setting = Settings.RegisterProxySetting(
    ns.optionsCategory,
    "muteVerboseDebugging",
    Settings.VarType.Boolean,
    "Mute verbose debugging",
    optionsDefaults['muteVerboseDebugging'],
    function() return ns:GetOption('muteVerboseDebugging') end,
    function(value) PetesDefensiveHistoryOptionsDb.muteVerboseDebugging = value  end
)

Settings.CreateCheckbox(ns.optionsCategory, setting,
    "Mute certain extremely verbose debugging messages.")


-- Don't log extremely spammy messages like talent ranks and ability inference
-- during the zero knowledge solve.
local setting = Settings.RegisterProxySetting(
    ns.optionsCategory,
    "runGC",
    Settings.VarType.Boolean,
    "Run additional GCs",
    optionsDefaults['runGC'],
    function() return ns:GetOption('runGC') end,
    function(value) PetesDefensiveHistoryOptionsDb.runGC = value  end
)

Settings.CreateCheckbox(ns.optionsCategory, setting,
    "Run garbage collection when tearing down/setting up the UI. Helps to find memory leaks.")

Settings.RegisterAddOnCategory(ns.optionsCategory, "PetesDefensiveHistoryOptionsDb")




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

local function addOptionForAbility(ability)
    -- set default true values
    optionsDefaults["show_" .. ability.id] = true
    local setter = function(value)
        PetesDefensiveHistoryOptionsDb["show_" .. ability.id] = value
        ns:updateTrackerUI()
    end
    setting = Settings.RegisterProxySetting(
        ns.optionsCategory,
        "show_" .. ability.id,
        Settings.VarType.Boolean,
        ability.name,
        true,
        function() return ns:GetOption("show_"..ability.id) end,
        setter)
    Settings.CreateCheckbox(category, setting)
    table.insert(abilitySetters, setting)
end

-- Racials first
for englishRaceName, raceName in pairs(ns.englishRaceNameToLocalized) do
    local abilities = ns.AbilityDb[englishRaceName]
    if abilities and #abilities > 0 then
        layout:AddInitializer(
            Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", { name=raceName })
        )
        for _, ability in pairs(abilities) do
            addOptionForAbility(ability)
        end
    end
end

-- Class/spec abilities
for _, classFile in pairs(orderedClasses) do
    local abilities = ns.AbilityDb[classFile]
    local class = LOCALIZED_CLASS_NAMES_MALE[classFile] -- maps "WARRIOR" -> "Warrior" or "Guerrier"

    layout:AddInitializer(
        Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", { name=class })
    )

    for _, ability in pairs(abilities) do
        addOptionForAbility(ability)
    end
end


Settings.RegisterAddOnCategory(category)
