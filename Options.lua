-- get addon namespace
local addonName, ns = ...

ns.anchorPoints = {
    "TOPLEFT", "TOP", "TOPRIGHT",
    "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT"
}

ns.growthDirections = {
    "LEFT", "RIGHT", "UP", "DOWN"
}

ns.textOutlines = {
    "", "MONOCHROME", "OUTLINE", "THICKOUTLINE", "SLUG"
}

-- opposite direction *AND* in anchor points, not directions
ns.antiDirection = {
    LEFT="RIGHT",
    RIGHT="LEFT",
    UP="BOTTOM",
    DOWN="TOP"
}

local optionsDefaults = {
    enable = true,
    enableSolo = true,
    enableParty = true,
    enableArena = false,
    enableRaid = false,
    enableBattleground = false,

    -- The minimap defaults are ignored for old addon users
    minimap = {
        angle = 225,
        hide = false,
    },
    hidePersonalCDs = false,
    hideInaccurateBadges = false,
    iconSize = 32,
    historyTrayScale = 0.75,
    iconSpacing = 3,
    wrapIcons = 10,
    maxHistoryTrayItems = 4,
    textSize = 15,
    textOutline = 3,
    anchorFrom = 3,         -- TOPRIGHT
    anchorTo = 1,           -- TOPLEFT
    growthDirection = 1,    -- LEFT
    adjustX = -3,
    adjustY = 0,
    showActiveDuration = true,
    disableActiveGlow = false,
    desaturateOnCooldown = false,

    enableMplusXalatathHack = true,
    disableInference = false,
    throttleInference = 0.2,
    disableCDRTrackers = false,
    disableHistoryTray = false,
    hideHistoryItemsAtMaxCd = true,
    showTooltips = true,
    hideWelcomeMessage = false,

    enableTTS = false,
    TTSnoUntracked = false,
    TTSnoSelfCasts = false,

    charSpecificSettings = true,

    inferWithoutTalentData = false,
    enableReplays = false,
	debugVisuals = false,
	debugLogging = false,
    debugLoggingLevelVerbose = false,
    debugLoggingTypeTalents = false,
    debugLoggingTypeInference = false,
    debugLoggingTypeUI = false,
    debugLoggingTypeData = false,
    debugLoggingTypeDataMining = false,
    debugLoggingTypeSimulation = false,
    debugLoggingTypeExport = false,
    runGC = false,

    -- Overrides
    allowBrewmasterStoneform = false,
}

ns.hideWelcomeMessage = nil
ns.optionsProfile = nil
ns.optionsDb = nil
ns.optionsCharKey = nil


local function useProfile()
    -- always use the character-specific settings database for charSpecificSettings
    ns.optionsProfile = PetesDefensiveHistoryOptionsDb.charSpecificSettings and ns.optionsCharKey or 'Shared'
    ns.optionsDb = PetesDefensiveHistoryGlobalOptionsDb.profiles[ns.optionsProfile]
end


-- Called by ADDON_LOADED. Must set up profiles/options so that GetOption() can be called.
function ns:initOptions()
    if not PetesDefensiveHistoryGlobalOptionsDb then
        PetesDefensiveHistoryGlobalOptionsDb = {}
        PetesDefensiveHistoryGlobalOptionsDb.profiles = {}
    end

    if not PetesDefensiveHistoryGlobalOptionsDb.profiles['Shared'] then
        PetesDefensiveHistoryGlobalOptionsDb.profiles['Shared'] = CopyTable(optionsDefaults)
    end

    -- realm=nil until PLAYER_LOGIN. this is why nothing can be done at ADDON_LOADED
    local name, _ = UnitNameUnmodified('player')
    local _, realm = UnitFullName('player')
    ns.optionsCharKey = name .. "-" .. realm
    if not PetesDefensiveHistoryGlobalOptionsDb.profiles[ns.optionsCharKey] then
        PetesDefensiveHistoryGlobalOptionsDb.profiles[ns.optionsCharKey] =
            CopyTable(optionsDefaults)

        -- Check for the legacy pre-global/profiles options database. If this is the first login
        -- of this character using the new profiles system, copy over their old settings.
        if PetesDefensiveHistoryOptionsDb then
            PetesDefensiveHistoryOptionsDb.charSpecificSettings = true
            for k, v in pairs(PetesDefensiveHistoryOptionsDb) do
                PetesDefensiveHistoryGlobalOptionsDb.profiles[ns.optionsCharKey][k] = v
            end
        end
    end

    useProfile()
end


-- Universal getter. Use this to access settings, not direct keying
-- into the settings table. No idea why I capitalized this.
function ns:GetOption(opt)
    local val
    -- always use the character-specific settings database for charSpecificSettings
    if opt == 'charSpecificSettings' then
        val = PetesDefensiveHistoryOptionsDb.charSpecificSettings
    else
        val = ns.optionsDb[opt]
    end
    if val == nil then
        return optionsDefaults[opt]
    end
    return val
end


local function makeSectionHeader(layout, text)
    layout:AddInitializer(
        Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", { name=text }))
end


local function makeSetting(category, optName, settingType, label)
    return Settings.RegisterProxySetting(
        category, optName, settingType, label,
        optionsDefaults[optName],
        function() return ns:GetOption(optName) end,
        function(value)
            -- always use the character-specific settings database for charSpecificSettings
            if optName == 'charSpecificSettings' then
                PetesDefensiveHistoryOptionsDb.charSpecificSettings = value
                useProfile()
            else
                ns.optionsDb[optName] = value
            end
            ns:handleAddonActiveStateChange()
            ns:handleReplayStateChange()
            ns:updateTrackerUI()
        end
    )
end


local function makeCheckbox(category, optName, label, tooltip, parentSetting)
    setting = makeSetting(category, optName, Settings.VarType.Boolean, label)
    thisbox = Settings.CreateCheckbox(category, setting, tooltip)
    if parentSetting then
        thisbox:SetParentInitializer(parentSetting)
    end
    return thisbox, setting
end


local function anchorPointOptions()
    local container = Settings.CreateControlTextContainer()
    for i, name in pairs(ns.anchorPoints) do
        container:Add(i, name)
    end
    return container:GetData()
end


local function growthDirectionOptions()
    local container = Settings.CreateControlTextContainer()
    for i, name in pairs(ns.growthDirections) do
        container:Add(i, name)
    end
    return container:GetData()
end


local function textOutlineOptions()
    local container = Settings.CreateControlTextContainer()
    for i, name in pairs(ns.textOutlines) do
        container:Add(i, name)
    end
    return container:GetData()
end



local function buildMainOptions()
    local category, layout = Settings.RegisterVerticalLayoutCategory(addonName)

    makeSectionHeader(layout, 'Active inference content')

    parent = makeCheckbox(category, "enable", "Enable",   -- Disable the addon entirely
        "Enable the addon. Disabling the addon prevents all event processing and deletes all collected data, including player info, including talents, tracked cooldowns and event histories.")
    makeCheckbox(category, "enableSolo", "Solo",
        "Enable while solo.", parent)
    makeCheckbox(category, "enableParty", "Party",
        "Enable in non-raid, non-arena group content.", parent)
    makeCheckbox(category, "enableArena", "Arena",
        "Enable while in arenas. COMPLETELY UNTESTED.", parent)
    --makeCheckbox(category, "enableRaid", "Raid", "Enable in raids.", parent)


    makeSectionHeader(layout, 'Appearance')

    -- Can't use the nice makeCheckbox code because this option is in a subtable
    setting = Settings.RegisterProxySetting(
        category, 'minimap.hide', Settings.VarType.Boolean, "Hide minimap button",
        optionsDefaults.minimap.hide,
        --function() return PetesDefensiveHistoryOptionsDb.minimap.hide end,
        function() return ns.optionsDb.minimap.hide end,
        function(value)
            --PetesDefensiveHistoryOptionsDb.minimap.hide = value
            ns.optionsDb.minimap.hide = value
            if value then
                ns.ldbicon:Hide('PetesDefensiveHistory')
            else
                ns.ldbicon:Show('PetesDefensiveHistory')
            end
        end)
    Settings.CreateCheckbox(category, setting, "Show the minimap button")

    makeCheckbox(category, "hidePersonalCDs", "Hide my cooldowns",
        "Hide the cooldown tracker (both static cooldowns and the history tray) for the player's own frame.")

    makeCheckbox(category, "hideInaccurateBadges", "Hide |cFFFF0000(!)|r badges",
        "When an ability's cooldown timer is very hard to guess, a small |cFFFF0000(!)|r badge is placed on its top left corner. This usually only happens for abilities with dynamic cooldown reduction (e.g., Avatar's cooldown is reduced for every 20 rage spent). Check this option to hide the |cFFFF0000(!)|r badges.")

    -- Set tracker icon size
    setting = makeSetting(category, 'iconSize', Settings.VarType.Number, 'Cooldown icon size')
    local options = Settings.CreateSliderOptions(8, 64, 1)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right) --, FormatPercentage)
    Settings.CreateSlider(category, setting, options, "Size of tracker icons")

    -- Set cooldown timer text size
    setting = makeSetting(category, "textSize", Settings.VarType.Number, "Timer text size")
    local options = Settings.CreateSliderOptions(4, 32, 1)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
    Settings.CreateSlider(category, setting, options, "Text size for cooldown timers")

    -- History tray scale
    setting = makeSetting(category, 'historyTrayScale', Settings.VarType.Number, 'History tray scale')
    local options = Settings.CreateSliderOptions(0, 1, 0.01)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, FormatPercentage)
    Settings.CreateSlider(category, setting, options, "Scale the history tray icons and text")

    -- Timer text outline/shadow
    setting = makeSetting(category, 'textOutline', Settings.VarType.Number,
        'Timer text outline')
    Settings.CreateDropdown(category, setting, textOutlineOptions)

    -- Set spacing between tracker items
    setting = makeSetting(category, "iconSpacing", Settings.VarType.Number, "Icon spacing")
    local options = Settings.CreateSliderOptions(0, 10, 1)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
    Settings.CreateSlider(category, setting, options, "Spacing between tracker icons")

    setting = makeSetting(category, "wrapIcons", Settings.VarType.Number, "Wrap icons at")
    local options = Settings.CreateSliderOptions(1, 15, 1)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
    Settings.CreateSlider(category, setting, options, "Wrap cooldown tracker and history tray icons at this many items. Accounts for growth direction: wrapping create new row for left/right growth and new columns for up/down growth.")

    setting = makeSetting(category, "maxHistoryTrayItems", Settings.VarType.Number,
        "Max items in history tray")
    local options = Settings.CreateSliderOptions(1, 10, 1)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
    Settings.CreateSlider(category, setting, options, "The history tray is like a GCD tracker for cooldowns that can't be identified. Show at most this many unidentified cooldowns in the history tray. To disable the history tray entirely, use Behavior > Disable history tray.")

    -- Anchors
    setting = makeSetting(category, 'anchorFrom', Settings.VarType.Number, 'Anchor tracker from its')
    Settings.CreateDropdown(category, setting, anchorPointOptions)

    setting = makeSetting(category, 'anchorTo', Settings.VarType.Number, 'Anchor tracker to frame\'s')
    Settings.CreateDropdown(category, setting, anchorPointOptions)

    setting = makeSetting(category, 'growthDirection', Settings.VarType.Number, 'Grow icons to the')
    Settings.CreateDropdown(category, setting, growthDirectionOptions)

    setting = makeSetting(category, "adjustX", Settings.VarType.Number,
        "Adjust X position")
    local options = Settings.CreateSliderOptions(-100, 100, 1)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
    Settings.CreateSlider(category, setting, options, "Nudge each cooldown tracker cluster by this many pixels in the X direction")

    setting = makeSetting(category, "adjustY", Settings.VarType.Number,
        "Adjust Y position")
    local options = Settings.CreateSliderOptions(-100, 100, 1)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
    Settings.CreateSlider(category, setting, options, "Nudge each cooldown tracker cluster by this many pixels in the Y direction")

    makeCheckbox(category, "showActiveDuration", "Show active duration swipe",
        "When an ability is active, show a cooldown swipe indicating when the ability will end, similar to what is shown on Blizzard's Center Big Defensives icon.")

    makeCheckbox(category, "disableActiveGlow", "Disable active glow",
        "Do not glow icons when its ability is active.")

    makeCheckbox(category, "desaturateOnCooldown", "Desaturate icons on cooldown",
        "Desaturate cooldown tracker icons while the ability is on cooldown.")

    makeSectionHeader(layout, 'Behavior')

    -- Disable all inference. Put everything in the history tray

    makeCheckbox(category, "disableInference", "Disable inference",
        "Disable logic to infer abilities and the associated row of icons. All abilities will instead be sent to the history tray for the unit on which they were cast (which may not be the caster!). Items in the history tray receive a count-up timer that stops at the maximum cooldown length for all abilities that can target that unit and the player must know the associated cooldown length.")

    setting = makeSetting(category, "throttleInference", Settings.VarType.Number,
        "Throttle inferences by")
    local options = Settings.CreateSliderOptions(0, 1, 0.05)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
    Settings.CreateSlider(category, setting, options, "Wait at least this many fractions of a second between inferences. Does not affect the frequency at which data is collected, which remains real-time.")

    makeCheckbox(category, "disableCDRTrackers", "Disable inaccurate timers",
        "Dynamic cooldown reduction (e.g., each cast of Power Word: Shield reduces the cooldown of Pain Suppression) cannot be tracked. Normally, these abilities will count down to the MAXIMUM cooldown time. Enabling this option will instead send those abilities to the history tray, declining to show an inaccurate cooldown swipe. NOTE: cooldown timers are especially inaccurate for abilities with BOTH dynamic cooldown reduction and charges (e.g., Shield Wall, Guardian of Ancient Kings, Pain Suppresion, etc.).") 

    makeCheckbox(category, "disableHistoryTray", "Disable history tray",
        "Disable the history tray. Do not send abilities that cannot be guessed to the history tray. Instead, quietly ignore them and only show abilities when they are identified. Careful: some abilities can only |cffff0000sometimes|r be guessed! When they are not, they are normally sent to the history tray and appear as available in the cooldown tracker row. If the history tray is hidden, you will not see this and the ability will simply appear to be available.")

    makeCheckbox(category, "hideHistoryItemsAtMaxCd", "Hide old history tray items",
        "Hide unidentified abilities in the history tray after the maximum possible cooldown is reached.")

    makeCheckbox(category, "enableMplusXalatathHack", "Enable M+ Voidbinding hack",
        "The Xal'atath's Bargain affix Voidbinding gives 30% faster cooldown recovery, which confuses internal cooldown logic and sometimes prevents spell identification. This hack helps to continue identifying abilities during Voidbinding weeks and is only active in M+ keys level 11 and lower.")

    makeCheckbox(category, "showTooltips", "Show spell tooltips",
        "Show spell tooltips for abilities that can be identified. This does not work for abilities in the history tray, since these abilities are not identified.")

    -- Make this setting globally available so the dialog window can change it
    _, ns.hideWelcomeMessage = makeCheckbox(
        category, "hideWelcomeMessage", "Hide the welcome message",
        "Don't show the welcome message for first-time users at login.")


    -- Settings for text to speech --------------------------------------------------
    makeSectionHeader(layout, 'Text to speech')

    parent = makeCheckbox(category, "enableTTS", "Enable text to speech",
        "Say the names of abilities when they are used. Only applies to abilities that can be instantly identified.") -- XXX: TODO: Uses the voice, speed and volume settings in Audio Assist > Combat Audio Alerts.")

    makeCheckbox(category, "TTSnoUntracked", "Only tracked abilities",
        "Do not announce abilities that are unselected in the Tracked Abilities list.", parent)

    makeCheckbox(category, "TTSnoSelfCasts", "No self-casts",
        "Do not announce abilities cast by you.", parent)

    return category
end



-- Settings for development
local function buildDeveloperOptions(topCategory)
    local category, layout =
        Settings.RegisterVerticalLayoutSubcategory(topCategory, "Developer options")

    makeSectionHeader(layout, 'Logic tracing and replays')
    makeCheckbox(category, 'enableReplays', 'Enable logic replays',
        'Did an ability get mis-identified? Logic traces and event replays are the way to debug the complex scenarios this addon must handle. Enabling this option will record all relevant events and metadata to export a replay that can be aligned against a WoW combat log to check for errors. To export a replay, click the addon compartment button (top right of the screen in the default Blizzard UI) and copy the string in the pop-up window. Share your exports and combat logs on our Discord at |cFF00FFFFdiscord.gg/gVCtQrvpxt|r! |cFFFF0000Enabling this option will consume a large amount of memory, possibly ~100 Mb per 30 minute dungeon. Use /reload to clear it.|r')

    makeSectionHeader(layout, 'Debugging')

    makeCheckbox(category, 'inferWithoutTalentData', 'Infer without talent data',
        'Without talent data, it is difficult to know what abilities a player has and what their cooldowns are. When unchecked (the default), do not infer abilities on players without talent data unless it is an external cooldown cast by another player with talent data. By checking this box, the addon will infer all abilities on players without talent data, which can cause many strange false calls and interactions.')

    makeCheckbox(category, 'debugVisuals', 'Visual debugging', 
        "Add debugging widgets to the tracker icons.")

    local parent = makeCheckbox(category, 'debugLogging', "Debugging messages",
        "Print debug log messages to the chat console. Prints A LOT of text.")

    makeCheckbox(category, "debugLoggingLevelVerbose", "Enable verbose logging",
        "Print even more debugging messages.", parent)

    makeCheckbox(category, "debugLoggingTypeTalents", "Talents",
        "Print debugging messages about retrieving, decoding and modifying player talents.",
        parent)

    makeCheckbox(category, "debugLoggingTypeInference", "Inference",
        "Print debugging messages tracing inference calls.", parent)

    makeCheckbox(category, "debugLoggingTypeUI", "User interface",
        "Print debugging messages about the user interface.", parent)

    makeCheckbox(category, "debugLoggingTypeData", "Data collection",
        "Print debugging messages about data collection and tracking.", parent)

    makeCheckbox(category, "debugLoggingTypeDataMining", "Data mining",
        "Print aura data on the player that is not secret out of combat.", parent)

    makeCheckbox(category, "debugLoggingTypeSimulation", "Simulations",
        "Print inference traces during zero knowledge simulations.", parent)

    makeCheckbox(category, "debugLoggingTypeExport", "Export",
        "Print inference traces when converting internal data to export strings.", parent)

    -- Run garbage collection when enabling or disabling the addon
    makeCheckbox(category, "runGC", "Run additional GCs",
        "Run garbage collection when tearing down/setting up the UI. Helps to find memory leaks.")

    -- Allow users to override some decisions made by developers
    makeSectionHeader(layout, 'Overrides')
    makeCheckbox(category, "allowBrewmasterStoneform", "Allow Stoneform on Brewmasters",
        "Stoneform inference is disabled for Brewmasters because of a high number of false positives related to stagger. Check this box to enable Stoneform on Brewmasters.")

    Settings.RegisterAddOnCategory(category)
end



----------------------------------------------------------------------------------
-- Options subpanel for selecting which spells to track
----------------------------------------------------------------------------------

local function buildTrackedSpells(topCategory)
    local category, layout =
        Settings.RegisterVerticalLayoutSubcategory(topCategory, "Tracked abilities")

    -- track setter checkboxes so we can iterate over them
    local abilitySettings = {}

    local function setAll(v)
        local function f()
            for _, data in pairs(abilitySettings) do
                -- Don't set developerDisable spells
                if not data.disable then data.setting:SetValue(v) end
            end
        end
        return f
    end

    layout:AddInitializer(CreateSettingsButtonInitializer(
        "Track all abilities", "Check all", setAll(true),
        "Select all checkboxes", true, nil, nil))

    layout:AddInitializer(CreateSettingsButtonInitializer(
        "Track no abilities", "Uncheck all", setAll(false),
        "Unselect all checkboxes", true, nil, nil))

    local disabledWarning = "Disabled by addon developer. This ability will be enabled in future updates, but has interactions that need more testing. Enable at your own risk."

    local function addOptionForAbility(ability)
        -- set default enabled values
        optionsDefaults["show_" .. ability.id] = not ability.developerDisable
    
        checkbox, setting = makeCheckbox(category,
            "show_" .. ability.id,
            (not ability.developerDisable and "" or "|cFFFF0000") .. ability.name .. "|r",
            not ability.developerDisable and ability.name or disabledWarning)

        table.insert(abilitySettings, { setting=setting, disable=ability.developerDisable ~= nil })
    end

    -- Racials first
    for englishRaceName, raceName in pairs(ns.englishRaceNameToLocalized) do
        local abilities = ns.AbilityDb[englishRaceName]
        if abilities and #abilities > 0 then
            makeSectionHeader(layout, raceName)
            for _, ability in pairs(abilities) do
                addOptionForAbility(ability)
            end
        end
    end

    -- Class/spec abilities
    for _, classFile in pairs(ns.orderedClasses) do
        local abilities = ns.AbilityDb[classFile]
        makeSectionHeader(layout, LOCALIZED_CLASS_NAMES_MALE[classFile])
        for _, ability in pairs(abilities) do
            addOptionForAbility(ability)
        end
    end

    Settings.RegisterAddOnCategory(category)
end


local function restoreLegacyOptions()
    -- Check for some arbitrary element of the older options database
    if PetesDefensiveHistoryOptionsDb and PetesDefensiveHistoryOptionsDb.enable then
        ns:printDebug(ns.LOGTYPE.None, ns.LOGLEVEL.Normal,
            "Restoring legacy settings for "..ns.optionsCharKey)
        PetesDefensiveHistoryOptionsDb.charSpecificSettings = true
        for k, v in pairs(PetesDefensiveHistoryOptionsDb) do
            PetesDefensiveHistoryGlobalOptionsDb.profiles[ns.optionsCharKey][k] = v
        end
        -- Ideally we would :SetValue() all of the settings we just restored, but I'm not sure
        -- where the list of all settings can be obtained (and we don't maintain such a list).
        -- Instead, just reproduce the SetValue() downstream responses since this function will
        -- be deleted in the near future anyway.
        ns:handleAddonActiveStateChange()
        ns:handleReplayStateChange()
        ns:updateTrackerUI()
    else
        ns:printDebug(ns.LOGTYPE.None, ns.LOGTYPE.Error,
            "Could not find legacy settings for "..ns.optionsCharKey..". Nothing to restore!")
    end
end


StaticPopupDialogs['PDH_CONFIRM_LEGACY_RESTORE_DIALOG'] = {
    text="This will overwrite (delete) your current "..addonName.." settings with your older settings. Are you sure?",
    button1="Delete",
    button2="Cancel",
    timeout=0,
    whileDead=true,
    hideOnEscape=true,
    preferredIndex=3,
    OnAccept=function(self) restoreLegacyOptions() end,
}


StaticPopupDialogs["PDH_CONFIRM_IMPORT_SETTINGS"] = {
    text="Are you sure you want to overwrite your settings for "..addonName.."? This will permanently delete your current layout.",
    button1="Delete",
    button2="Cancel",
    timeout=0,
    whileDead=true,
    hideOnEscape=true,
    preferredIndex=3,
    OnAccept=function(self)  end, -- XXX: do something
}

local function allocSettingsExportPopup()
    local f = CreateFrame("Frame", addonName .. "SettingsExportPopup", UIParent, "BackdropTemplate")

    f:SetPoint("CENTER")
    f:SetSize(600, 250)
    f:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    f:SetBackdropColor(0, 0, 0, 0.9)
    f:SetFrameStrata('TOOLTIP')

    f.uiTitle = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
    f.uiTitle:SetText("Settings export string")
    f.uiTitle:SetPoint("TOP", f, "TOP", 0, -10)

    f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", 8, -34)
    f.scroll:SetPoint("BOTTOMRIGHT", -30, 36)

    f.edit = CreateFrame("EditBox", nil, f.scroll)
    f.edit:SetMultiLine(true)
    f.edit:SetFontObject('GameFontWhiteSmall')
    f.edit:SetWidth(540)
    f.edit:SetAutoFocus(true)
    f.edit:EnableMouse(true)

    f.scroll:SetScrollChild(f.edit)
    f.edit:SetScript("OnEscapePressed", function() f:Hide() end)

    -- Make a close button since some won't figure out the escape button
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(120, 25)
    b:SetPoint("BOTTOM", f, 'BOTTOM', 0, 8)
    b:SetText("Close")
    b:SetScript("OnClick", function(self, button, down) f:Hide() end)

    -- Don't show until the user clicks the compartment button
    f:Hide()

    return f
end

local settingsExportPopup = allocSettingsExportPopup()

local function buildProfiles(topCategory)
    local category, layout =
        Settings.RegisterVerticalLayoutSubcategory(topCategory, "Profiles")

    makeCheckbox(category, "charSpecificSettings", "Character-specific settings",
        "Only apply settings to this character")

    layout:AddInitializer(CreateSettingsButtonInitializer(
        "Share settings", "Export settings",
        function()
            local data = { C_AddOns.GetAddOnMetadata(addonName, 'Version'), ns.optionsDb }
            local serializedData = C_EncodingUtil.SerializeCBOR(data)
            local compressedString = C_EncodingUtil.CompressString(serializedData)
            local finalString = C_EncodingUtil.EncodeBase64(compressedString)
            settingsExportPopup.edit:SetText(finalString)
            settingsExportPopup:Show()
        end,
        "Create a string containing your current settings that can be input to the |cFFFFFFImport settings|r button.", true, nil, nil))

    layout:AddInitializer(CreateSettingsButtonInitializer(
        "Use settings |cFFFF0000NOT IMPLEMENTED|r", "Import settings",
        function() end,
        "Paste a settings string here to quickly set up your UI. |cFFFF0000This will overwrite (delete) all of your current settings!|r", true, nil, nil))

    layout:AddInitializer(CreateSettingsButtonInitializer(
        "Restore legacy settings", "Restore pre-12.0.5 settings",
        function()
            StaticPopup_Show('PDH_CONFIRM_LEGACY_RESTORE_DIALOG')
        end,
        "Did the 12.0.5 settings change delete your old settings? No problem, click this button and your old settings will be restored. |cFFFF0000Be careful! This will overwrite (delete) the current (supposedly wrong) settings!|r", true, nil, nil))
end


do
    ns.optionsCategory = buildMainOptions()
    buildTrackedSpells(ns.optionsCategory)
    buildProfiles(ns.optionsCategory)
    buildDeveloperOptions(ns.optionsCategory)

    Settings.RegisterAddOnCategory(ns.optionsCategory)
end
