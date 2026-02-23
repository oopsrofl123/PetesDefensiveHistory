-- get addon namespace
local addonName, ns = ...

-- Very different from the MAX_HISTORY size. This must be large enough to show
-- all abilities for a character AND all externals across the group that could
-- be applied to that character.
local UI_MAX_ABILITIES_PER_SLOT = 12

-- eventually make this all settable (via options), but this is not important enough right now
local UI_ICON_SIZE = 48
local UI_ICON_PADDING = 16
local UI_TITLE_PADDING = 15
local UI_ROW_HEIGHT = UI_ICON_SIZE + 36
local UI_CLOSE_BUTTON_HEIGHT = 28
local UI_WIDTH = 200 + (UI_ICON_SIZE+UI_ICON_PADDING) * UI_MAX_ABILITIES_PER_SLOT
-- Can't take length of keyed tables with #. Have to loop through.
local numPlayers = 0
for k, v in pairs(ns.allSlots) do
    numPlayers = numPlayers + 1
end
local UI_HEIGHT = 10 + UI_TITLE_PADDING + 20 + UI_CLOSE_BUTTON_HEIGHT + 20 + UI_ROW_HEIGHT*numPlayers


function ns:updateGroupSolutionRow(row)
    for i=1,UI_MAX_ABILITIES_PER_SLOT do
        local item = row.items[i]
        local ability = ns.groupCDs[row.slot].abilities[i]

        if ability then
            if ability.iconId then
                -- Override the standard spell icon
                item.icon:SetTexture(ability.iconId)
            else
                item.icon:SetTexture(C_Spell.GetSpellInfo(ability.id).iconID)
            end
            item.icon:SetDesaturated(not ability.solved)
            item.icon:Show()

            local cooldown = ability.cooldown .. "s"
            if ability.cdr then
                cooldown = "<" .. cooldown
            end
            item.cooldownLabel:SetText(cooldown)
            item.cooldownLabel:Show()

            local duration = ability.duration .. "s"
            if ability.duration_variable == ns.DURATION_LTE then
                duration = "<" .. duration
            elseif ability.duration_variable == ns.DURATION_GTE then
                duration = ">" .. duration
            end
            item.durationLabel:SetText(duration)
            item.durationLabel:Show()

            -- Only show charges if the ability has charges
            item.chargesLabel:SetText(ability.charges)
            if ability.charges > 1 then
                item.chargesLabel:Show()
            else
                item.chargesLabel:Hide()
            end

            if #ability.conflicts > 0 then
                item.conflictsLabel:SetText(table.concat(ability.conflicts, ' '))
                item.conflictsLabel:SetTextColor(1,0,0)
                item.conflictsLabel:Show()
            end
        else
            item.icon:Hide()
            item.conflictsLabel:Hide()
            item.cooldownLabel:Hide()
            item.durationLabel:Hide()
            item.chargesLabel:Hide()
        end
    end

    -- Update and color class/specialization label if it was detected
    if ns.groupCDs[row.slot].specId then
        row.specLabel:SetText(ns:specIdToString(ns.groupCDs[row.slot].specId))
        _, class = UnitClass(row.slot)
        classColor = RAID_CLASS_COLORS[class]
        row.specLabel:SetTextColor(classColor.r, classColor.g, classColor.b)
        row.specLabel:Show()
    end


    -- Determine the role of the party member and set the appropriate icon
    row.roleIcon:Show()
    local role = UnitGroupRolesAssigned(row.slot)
    if role == "TANK" then
        row.roleIcon:SetTexCoord(0, 0.296875, 0.34375, 0.640625)
    elseif role == "HEALER" then
        row.roleIcon:SetTexCoord(0.3125, 0.609375, 0.015625, 0.3125)
    elseif role == "DAMAGER" then
        row.roleIcon:SetTexCoord(0.3125, 0.609375, 0.34375, 0.640625)
    else
        -- not unusual. happens when not in group
        row.roleIcon:Hide()
    end

    if not UnitExists(row.slot) then
        row:Hide()
    end
end



local function allocSolutionItem(row)
    local item = {}
    item.icon = row:CreateTexture(nil, "OVERLAY")
    item.icon:SetSize(UI_ICON_SIZE, UI_ICON_SIZE)
    item.icon:SetTexture("Interface\\Icons\\Spell_Nature_HealingTouch")
    item.icon:Hide()

    item.cooldownLabel = row:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
    font, height, flags = item.cooldownLabel:GetFont()
    item.cooldownLabel:SetFont(font, height, "THICKOUTLINE")
    item.cooldownLabel:SetTextColor(1,1,1)
    item.cooldownLabel:SetPoint("CENTER", item.icon, "CENTER")
    item.cooldownLabel:Hide()

    item.durationLabel = row:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    item.durationLabel:SetTextColor(1,1,1)
    item.durationLabel:SetPoint("TOP", item.icon, "BOTTOM", 0, -3)
    item.durationLabel:Hide()

    item.chargesLabel = row:CreateFontString(nil, 'OVERLAY', 'NumberFontNormal')
    font, height, flags = item.chargesLabel:GetFont()
    item.chargesLabel:SetFont(font, height, "THICKOUTLINE")
    item.chargesLabel:SetTextColor(1,1,1)
    item.chargesLabel:SetPoint("BOTTOMRIGHT", item.icon, "BOTTOMRIGHT", 0, 2)
    item.chargesLabel:Hide()

    item.conflictsLabel = row:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    item.conflictsLabel:SetPoint("TOP", item.durationLabel, 'BOTTOM', 0, -3)
    item.conflictsLabel:Hide()

    return item
end



local function allocGroupSolutionRow(uiframe, slot, index)
    -- Create the row frame
    local row = CreateFrame("Frame", "Row_"..slot, uiframe)
    row:SetSize(UI_WIDTH, UI_ROW_HEIGHT)
    row:SetPoint("TOP", uiframe.uiTitle, "TOP", 0, -UI_ROW_HEIGHT * (index - 1) - UI_TITLE_PADDING)

    row.slot = slot

    -- Player names
    row.nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    row.nameLabel:SetText(UnitName(slot))
    row.nameLabel:Show()

    -- Player class and specialization
    row.specLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.specLabel:SetText("")
    row.specLabel:Hide() -- only show when spec is detected

    -- tank, healer, dps icon
    row.roleIcon = row:CreateTexture(nil, "OVERLAY")
    row.roleIcon:SetTexture('Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES')
    row.roleIcon:SetSize(20, 20)
    row.roleIcon:SetPoint("LEFT", row, "LEFT", 5+10, 0)  -- inset size matters
    row.specLabel:Hide() -- only show when a role is detected

    row.items = {}
    for i=1,UI_MAX_ABILITIES_PER_SLOT do
        row.items[i] = allocSolutionItem(row)
    end

    -- Anchor the row from right to left so that the grid of icons is left-aligned
    row.items[UI_MAX_ABILITIES_PER_SLOT].icon:SetPoint("RIGHT", row, "RIGHT", -UI_ICON_PADDING, 0)
    for i=UI_MAX_ABILITIES_PER_SLOT-1,1,-1 do
        row.items[i].icon:SetPoint("RIGHT", row.items[i+1].icon, "LEFT", -UI_ICON_PADDING, 0)
    end

    row.nameLabel:SetPoint("TOPRIGHT", row.items[1].icon, "TOPLEFT", -UI_ICON_PADDING, -5)
    row.specLabel:SetPoint("BOTTOMRIGHT", row.items[1].icon, "BOTTOMLEFT", -UI_ICON_PADDING, 5)

    return row
end



local function allocMainUIFrame()
    local f = CreateFrame("Frame", addonName .. "GroupSolutionUI", UIParent, "BackdropTemplate")
    f:SetSize(UI_WIDTH, UI_HEIGHT)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile = "Interface\\TutorialFrame\\TutorialFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileEdge = true,
        tileSize = 16,
        edgeSize = 16,
        insets = {left = 3, right = 5, top = 3, bottom = 5}
    })

    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self, button) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    f.uiTitle = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
    f.uiTitle:SetText("PetesDefensiveHistory")
    f.uiTitle:SetPoint("TOP", f, "TOP", 0, -10)

    local closeButton = CreateFrame("Button", "closeButton", f, 'UIPanelButtonTemplate')
    closeButton:SetSize(UI_WIDTH/2, UI_CLOSE_BUTTON_HEIGHT)
    closeButton:SetPoint("BOTTOM", f, "BOTTOM", 0, 15)
    closeButton:SetText("Close")
    -- not sure why variable scoping binds f in the function call below to this local f, but whatever
    closeButton:SetScript("OnClick", function() f:Hide() end)

    f:Show()
    return f
end



-- IMPORTANT: do not make assumptions about whether group ability solution code
-- has been run when allocating the solution UI. The solutions happen at uncontrollable
-- times during LibSpec callbacks.
function ns:allocGroupSolutionUI()
    local solutionUI = allocMainUIFrame()

    solutionUI.rows = {}
    for slot, index in pairs(ns.allSlots) do
        solutionUI.rows[slot] = allocGroupSolutionRow(solutionUI, slot, index)
    end

    return solutionUI
end
