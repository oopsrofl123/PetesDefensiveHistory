local UI_ICON_SIZE = 48
local UI_ICON_PADDING = 16
local UI_TITLE_PADDING = 15

-- Very different from the MAX_HISTORY size. This must be large enough to show
-- all abilities for a character AND all externals across the group that could
-- be applied to that character.
local UI_MAX_ABILITIES_PER_SLOT = 6

local UI_ROW_HEIGHT = UI_ICON_SIZE + 36

local UI_CLOSE_BUTTON_HEIGHT = 28

local UI_WIDTH = 200 + (UI_ICON_SIZE+UI_ICON_PADDING) * UI_MAX_ABILITIES_PER_SLOT
local UI_HEIGHT = 10 + UI_TITLE_PADDING + 20 + UI_CLOSE_BUTTON_HEIGHT + 20 + UI_ROW_HEIGHT * 5   -- #allSlots this is 0 and i'm not sure why



function showPdhGroupSolutionRow(row)
    index = slotToIndex(row.slot)

    row:SetSize(UI_WIDTH, UI_ROW_HEIGHT)
    row:SetPoint("TOP", groupSolutionUIFrame.uiTitle, "TOP", 0, -UI_ROW_HEIGHT * (index - 1) - UI_TITLE_PADDING)

    -- Anchor the row from right to left so that the grid of icons is aligned
    for i=UI_MAX_ABILITIES_PER_SLOT,1,-1 do
        icon = row.abilityIcons[i]
        icon:SetSize(UI_ICON_SIZE, UI_ICON_SIZE)
        if i == UI_MAX_ABILITIES_PER_SLOT then
            icon:SetPoint("RIGHT", row, "RIGHT", -UI_ICON_PADDING, 0)
        else
            icon:SetPoint("RIGHT", row.abilityIcons[i+1], "LEFT", -UI_ICON_PADDING, 0)
        end
        icon:SetTexture("Interface\\Icons\\Spell_Nature_HealingTouch")
        icon:Show()


        cooldownLabel = row.abilityCooldownLabel[i]
        cooldownLabel:SetPoint("CENTER", icon, "CENTER")
        durationLabel = row.abilityDurationLabel[i]
        durationLabel:SetPoint("TOP", icon, "BOTTOM", 0, -3)

        conflictsLabel = row.abilityConflictsLabel[i]
        conflictsLabel:SetPoint("TOP", durationLabel, 'BOTTOM', 0, -3)
    end
    -- Fill in icons from left to right..obviously
    for i=1,UI_MAX_ABILITIES_PER_SLOT do
        icon = row.abilityIcons[i]
        ability = pdhGroupCDs[row.slot].abilities[i]
        conflictsLabel = row.abilityConflictsLabel[i]
        cooldownLabel = row.abilityCooldownLabel[i]
        durationLabel = row.abilityDurationLabel[i]
        if ability then
            if ability.iconId then
                -- Override the standard spell icon
                icon:SetTexture(ability.iconId)
            else
                icon:SetTexture(C_Spell.GetSpellInfo(ability.id).iconID)
            end
            cooldownLabel:SetText(ability.cooldown .. "s")
            durationLabel:SetText(ability.duration .. "s")
            if not ability.solved then icon:SetDesaturated(true) end
            if #ability.conflicts > 0 then
                conflictsLabel:SetText(table.concat(ability.conflicts, ' '))
                conflictsLabel:SetTextColor(1,0,0)
                conflictsLabel:Show()
            end
            icon:Show()
        else
            conflictsLabel:Hide()
            cooldownLabel:Hide()
            durationLabel:Hide()
            icon:Hide()
        end
    end

    row.nameLabel:SetPoint("TOPRIGHT", row.abilityIcons[1], "TOPLEFT", -UI_ICON_PADDING, -5)
    row.nameLabel:SetText(UnitName(row.slot))
    row.nameLabel:Show()

    row.specLabel:SetPoint("BOTTOMRIGHT", row.abilityIcons[1], "BOTTOMLEFT", -UI_ICON_PADDING, 5)
    if historyRows[row.slot] then
        if pdhGroupCDs[row.slot].specId then
            row.specLabel:SetText(specIdToString(pdhGroupCDs[row.slot].specId))
            _, class = UnitClass(row.slot)
            classColor = RAID_CLASS_COLORS[class]
            row.specLabel:SetTextColor(classColor.r, classColor.g, classColor.b)
        end
    end
    row.specLabel:Show()

    row.roleIcon:SetSize(20, 20)
    row.roleIcon:SetPoint("LEFT", row, "LEFT", 5+10, 0)  -- inset size matters
    row.roleIcon:Show()
    -- Determine the role of the party member and set the appropriate icon
    local role = UnitGroupRolesAssigned(row.slot)
    if role == "TANK" then
        row.roleIcon:SetTexCoord(0, 0.296875, 0.34375, 0.640625)
    elseif role == "HEALER" then
        row.roleIcon:SetTexCoord(0.3125, 0.609375, 0.015625, 0.3125)
    elseif role == "DAMAGER" then
        row.roleIcon:SetTexCoord(0.3125, 0.609375, 0.34375, 0.640625)
    else
        printDebug("unrecognized role " .. role .. " for slot " .. row.slot)
    end

end



local function allocPdhGroupSolutionRow(slot, index)
    -- Create the row frame
    local row = CreateFrame("Frame", nil, groupSolutionUIFrame)

    row.slot = slot
    row.nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    row.specLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.roleIcon = row:CreateTexture(nil, "OVERLAY")
    row.roleIcon:SetTexture('Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES')
    row.abilityIcons = {}
    row.abilityConflictsLabel = {}
    row.abilityCooldownLabel = {}
    row.abilityDurationLabel = {}

    for i=1,UI_MAX_ABILITIES_PER_SLOT do
        row.abilityIcons[i] = row:CreateTexture(nil, "OVERLAY")
        row.abilityConflictsLabel[i] = row:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')

        row.abilityCooldownLabel[i] = row:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
        font, height, flags = row.abilityCooldownLabel[i]:GetFont()
        row.abilityCooldownLabel[i]:SetFont(font, height, "THICKOUTLINE")
        row.abilityCooldownLabel[i]:SetTextColor(1,1,1)

        row.abilityDurationLabel[i] = row:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
        row.abilityDurationLabel[i]:SetTextColor(1,1,1)
    end

    groupSolutionUI[slot] = row

    return row
end



function showPdhGroupSolutionUI()
    groupSolutionUIFrame:SetSize(UI_WIDTH, UI_HEIGHT)
    groupSolutionUIFrame:SetPoint("CENTER")
    groupSolutionUIFrame:SetBackdrop({
        bgFile = "Interface\\TutorialFrame\\TutorialFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileEdge = true,
        tileSize = 16,
        edgeSize = 16,
        insets = {left = 3, right = 5, top = 3, bottom = 5}
    })

    groupSolutionUIFrame:SetMovable(true)
    groupSolutionUIFrame:EnableMouse(true)
    groupSolutionUIFrame:RegisterForDrag("LeftButton")
    groupSolutionUIFrame:SetScript("OnDragStart", function(self, button) self:StartMoving() end)
    groupSolutionUIFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    groupSolutionUIFrame:Show()
end


function allocPdhGroupSolutionUI()
    groupSolutionUIFrame = CreateFrame("Frame", "PetesDefensiveHistoryGroupSolutionUI", UIParent, "BackdropTemplate")
    showPdhGroupSolutionUI()

    groupSolutionUIFrame.uiTitle = groupSolutionUIFrame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
    groupSolutionUIFrame.uiTitle:SetText("PetesDefensiveHistory")
    groupSolutionUIFrame.uiTitle:SetPoint("TOP", groupSolutionUIFrame, "TOP", 0, -10)

    for slot, index in pairs(allSlots) do
        row = allocPdhGroupSolutionRow(slot, index)
        showPdhGroupSolutionRow(row)
    end

    closeButton = CreateFrame("Button", nil, groupSolutionUIFrame, 'UIPanelButtonTemplate')
    closeButton:SetSize(UI_WIDTH/2, UI_CLOSE_BUTTON_HEIGHT)
    closeButton:SetPoint("BOTTOM", groupSolutionUIFrame, "BOTTOM", 0, 15)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function() groupSolutionUIFrame:Hide() end)
end
