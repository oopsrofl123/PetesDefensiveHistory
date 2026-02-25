-- get addon namespace
local addonName, ns = ...


-- Updates the global variable allSlots to ensure that slot can be mapped
-- to the correct i such that slot = CompactPartyFrameMember..i
function ns:updateSlotToFrameMapping(slot)
    local frameRoot
    if DandersFrames then
        frameRoot = "DandersPartyHeaderUnitButton"
    else
        frameRoot = "CompactPartyFrameMember"
    end

    for i=1,5 do
        if slot == _G[frameRoot..i].unit then
            if i ~= ns.allSlots[slot] then
                ns:printDebug('updating slot mapping: ' .. slot .. ' -> ' .. i)
                ns.allSlots[slot] = i
                ns.trackerUI[slot].cpfMapping = i
                --ns.historyRows[slot].cpfMappingText:SetText(ns.historyRows[slot].cpfMapping)
                return
            end
        end
    end
end



function ns:slotToIndex(slot)
    return ns.allSlots[slot]
end



-- Map a character name to a slot name. E.g., "Pete" -> "player"
function ns:nameToSlot(n)
    if UnitName("player") == n then
        return "player"
    end
    for i=1,4 do
        if UnitName("party" .. i) == n then
            return "party" .. i
        end
    end
end



-- Blizzard party frames are named CompactPartyFrameMember{1,2,3,4,5}, not the
-- player, party1, party2, ... naming of UnitName(). Map the latter to the former.
function ns:slotToPartyFrameName(slot)
    if DandersFrames then
        return "DandersPartyHeaderUnitButton" .. ns:slotToIndex(slot)
    else
        return "CompactPartyFrameMember" .. ns:slotToIndex(slot)
    end
end



-- Further convenience: return the actual frame
function ns:slotToPartyFrame(slot)
    return _G[ns:slotToPartyFrameName(slot)]
end



-- Initialize a history item with blank values and hide it. Do not perform
-- allocation or do potentially unsafe things like move or reanchor elements.
local function clearHistoryItem(item)
    -- Local data per historyItem
    item.startTime = nil
    item.maxCD = nil
    item.numQueued = 0

    -- Initialize visuals
    item.icon:SetTexture(ns.DEFAULT_ICON)
    ns:showDebugVisual(item.icon)  -- show empty icons in debug mode

    if item.countUp then
        item.timer:SetText("")
        item.timer:Hide()
    else
        item.swipeTexture:Hide()
    end

    ns:showDebugVisual(item)

    return item
end



-- Copy history item in from into to, clobbering the original contents of to.
local function shiftHistoryTrayItem(from, to)
    to.startTime = from.startTime
    to.maxCD = from.maxCD
    to.icon:SetTexture(from.icon:GetTexture())

    -- Preserve visibility of each visual element
    ns:showIfShown(from, to)
    ns:showIfShown(from.timer, to.timer)
    ns:showIfShown(from.icon, to.icon)
end



-- Omit fromIndex to shift the whole history, leaving the "newest" slot open
-- IMPORTANT: the item at fromIndex is hidden since it is cleared. Callers
-- must re-:Show() if they want the item to be seen after this shift.
local function shiftHistoryTrayLeftFrom(items, fromIndex)
    fromIndex = fromIndex or ns.MAX_HISTORY
    for i=1,ns.MAX_HISTORY-1 do
        shiftHistoryItem(items[i+1], items[i])
    end
    clearHistoryItem(items[fromIndex])
end



function ns:addBuffToHistoryTray(slot, buff)
    local row = ns.historyTray[slot]

    -- Don't do anything if the user disabled the history tray
    if ns:GetOption('disableHistoryTray') then return end

    ns:printDebug("aura instance ID " .. buff.auraInstanceId ..
        " added to history tray " .. slot .. " after " .. buff.duration .. "s")

    -- Empty the youngest history slot
    shiftHistoryLeftFrom(row.items)
    
    -- Now that space has been made, add this ability to the tracker
    item = row.items[ns.MAX_HISTORY]
    item.startTime = buff.startTime
    item.maxCD = buff.maxCD
    item.icon:SetTexture(buff.secretTexture)
    item.icon:Show()
    item.timer:Show()
    item:Show()
end



-- Allocate a blank history item and allocate all of its subcomponents. The
-- history item and all subcomponents are :Hide()ed. Callers should :Show()
-- desired elements based on whether the ability represented by this history
-- item is known.
function allocHistoryItem(row, slot, index, countUp)
    local frameName = "item" .. index
    local f = CreateFrame("Frame", frameName, row)
    local textSize = ns:GetOption('textSize')
    f.slot = slot

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()

    -- Is this a count-up history tray item or a count-down cooldown tracker item?
    -- If the cooldown swipe is used, the timer needs to be parented to the 
    -- CooldownFrameTemplate so that the text is layered at the correct level relative
    -- to the swipe texture.
    f.countUp = countUp
    if countUp then
        -- Count-up history mode timer
        f.timer = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.timer:SetPoint("CENTER", f, 0, 0)
        f.timer:SetTextColor(1,1,1)
        f.timer:SetFont(f.timer:GetFont(), textSize, "THICKOUTLINE")
        -- XXX: TODO: is there a better event than OnUpdate? This runs every frame
        f:SetScript("OnUpdate", function(self)
            if self.startTime and self.maxCD then
                local elapsed = GetTime() - self.startTime
                if elapsed <= self.maxCD then
                    self.timer:SetFormattedText("%.0f", elapsed)
                else
                    self.timer:SetText("")
                    if ns:GetOption('hideHistoryItemsAtMaxCd') then
                        self:Hide()  -- hide the whole icon+timer
                    end
                end
            else
                self.timer:SetText("")
            end
        end)
    else
        -- Count-down timer and cooldown swipe. These icons have spellIds, so can
        -- show a tooltip.
        f.swipeTexture = CreateFrame("Cooldown", frameName .. "CDSwipe", f, "CooldownFrameTemplate")

        f.startTime = 0
        f.cooldown = 0
        f.numQueued = 0
        f.charges = 0

        f.swipeTexture:SetAllPoints()
        -- Have to hide blizzard's countdown text so we can control the size
        f.swipeTexture:SetHideCountdownNumbers(true)

        f.swipeTexture.timer = f.swipeTexture:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.swipeTexture.timer:SetTextColor(1,1,1)
        f.swipeTexture.timer:SetPoint("CENTER", f, 0, 0)
        f.swipeTexture.timer:SetFont(f.swipeTexture.timer:GetFont(), textSize, "THICKOUTLINE")

        f.swipeTexture.chargeLabel = f.swipeTexture:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        f.swipeTexture.chargeLabel:SetTextColor(1,1,1)
        f.swipeTexture.chargeLabel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 0)
        f.swipeTexture.chargeLabel:SetFont(f.swipeTexture.chargeLabel:GetFont(), textSize, "THICKOUTLINE")

        -- XXX: TODO: is there a better event than OnUpdate? This runs every frame
        -- Handle a couple of things:
        --    1. update cooldown timer text
        --    2. handle cooldown charges: monitor the cooldown FIFO to catch
        --       when a cooldown completes. if it does, pop the CD and check
        --       if the FIFO is empty. if it isn't, start a new swipe with the
        --       next CD in the queue.
        f:SetScript("OnUpdate", function(self)
            local now = GetTime()
            if self.numQueued > 0 then
                local untilAvailable = self.startTime + self.cooldown - now
                if untilAvailable > 0 then
                    self.swipeTexture.timer:SetFormattedText("%.0f", untilAvailable)
                else
                    self.swipeTexture:SetDrawSwipe(false)
                    self.numQueued = self.numQueued - 1
                    if self.numQueued > 0 then
                        self.startTime = now
                        self.swipeTexture:SetCooldown(now, self.cooldown)
                    end
                end
                self.swipeTexture.chargeLabel:SetText(self.charges - self.numQueued)
            else
                self.swipeTexture.timer:SetText("")
            end
        end)

        -- Show a spell tooltip on the history item
        f:SetScript("OnEnter", function(self)
            if ns:GetOption('showTooltips') then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(self.spellId)
                GameTooltip:Show()
            end
        end)
        f:SetScript("OnLeave", function(self)
            if ns:GetOption('showTooltips') then
                GameTooltip:Hide()
            end
        end)
    end

    return clearHistoryItem(f)
end



local function sizeHistoryItem(item)
    local iconSize = ns:GetOption('iconSize')
    local textSize = ns:GetOption('textSize')
    item:SetSize(iconSize, iconSize)

    if item.countUp then
        item.timer:SetFont(item.timer:GetFont(), textSize, "THICKOUTLINE")
    else
        item.swipeTexture.timer:SetFont(item.swipeTexture.timer:GetFont(), textSize, "THICKOUTLINE")
        item.swipeTexture.chargeLabel:SetFont(item.swipeTexture.chargeLabel:GetFont(), textSize, "THICKOUTLINE")
    end
end



-- Unlike allocRow, do not create any new frames, just set all elements to an
-- empty initial state. Assumes the row has been fully allocated already.
--
-- IMPORTANT: do not do anything that might be combat-unsafe. E.g., changing
-- anchors or positions.
function ns:clearRow(row)
    -- Row-specific data
    row.specId = nil
    row.playerName = nil
	row.cpfMapping = ns.allSlots[row.slot]

    -- Blank state for all visuals
    ns:showDebugVisual(row.bg)

    row.specText:SetText(tostring(row.specId))
    ns:showDebugVisual(row.specText)

	row.cpfMappingText:SetText(tostring(row.cpfMapping))
	ns:showDebugVisual(row.cpfMappingText)

    row:Show()

    for i, item in pairs(row.historyItems) do
        row.historyItems[i] = clearHistoryItem(item)
    end

    return row
end



-- XXX: TODO: This function leaks frames, but it happens rarely enough that we
-- can live with it for a while.
local function updateStaticRow(slot)
    local iconSize = ns:GetOption('iconSize')
    local iconSpacing = ns:GetOption('iconSpacing')
    local tracker = ns.trackerUI[slot]
    local row = tracker.staticRow

    row:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", 0, 0)

    local abilities = ns.groupCDs[slot].castableAbilities or {}
    ns:printDebug("updateStaticRow(" .. slot .. ")")

    -- Add a new frame for each tracked cooldown
    for _, ability in pairs(abilities) do
        if not row.items[ability.name] then
            local newItem = allocHistoryItem(row, slot, ability.name, false)
            newItem.spellId = ability.id
            row.items[ability.name] = newItem
            if ability.iconId then
                newItem.icon:SetTexture(ability.iconId)
            end
            newItem.cooldown = ability.cooldown
            newItem.charges = ability.charges
            if newItem.charges > 1 then
                -- XXX: TODO: doesn't show when not on cooldown
                newItem.swipeTexture.chargeLabel:Show()
                newItem.swipeTexture.chargeLabel:SetText(newItem.charges)
            else
                newItem.swipeTexture.chargeLabel:Hide()
            end
            newItem:Show()
            newItem.icon:Show()
        end

        local item = row.items[ability.name]
        sizeHistoryItem(item)
        -- Did the user opt in to showing this ability?
        if not ns:GetOption("show_"..ability.id) then
            item:Hide()
        else
            item:Show()
        end
    end

    -- If there are any abilities tracked that are no longer trackable (e.g.,
    -- the player changed spec, group changed, new external interferes, etc.)
    for name, _ in pairs(row.items) do
        if not abilities[name] then
            -- XXX: TODO: WARNING! this leaks frames! need a frame pool
            -- since frames cannot be deallocated.
            row.items[name]:ClearAllPoints()
            row.items[name]:Hide()
        end
    end

    -- Adjust layout based on the icons surviving the previous purge
    local i = 0
    for name, item in pairs(row.items) do
        item:SetPoint("RIGHT", row, "RIGHT", -(iconSize + iconSpacing)*i, 0)
        if item:IsShown() then i = i + 1 end
    end

    row:SetSize(i*(iconSize+iconSpacing) - iconSpacing, iconSize+2)

    if ns:GetOption('disableInference') then
        ns:showDebugVisual(row)
    else
        row:Show()
    end
end



-- Update a single row when visual options or party members change.
local function updateHistoryTray(slot)
    local tracker = ns.trackerUI[slot]
    local row = tracker.historyTray
    ns:printDebug("updateHistoryTray(" .. slot .. ")")

    local iconSize = ns:GetOption('iconSize')
    local textSize = ns:GetOption('textSize')
    local iconSpacing = ns:GetOption('iconSpacing')

    row:SetSize(ns.MAX_HISTORY*(iconSize+iconSpacing) - iconSpacing, iconSize+2)
    row:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", 0, -(iconSize + iconSpacing))

    for i=1,ns.MAX_HISTORY do
        local item = row.items[i]
        sizeHistoryItem(item)
        -- items are statically positioned with index 1 being the oldest
        item:SetPoint("LEFT", row, "LEFT", (i-1)*(iconSize + iconSpacing), 0)
        ns:showDebugVisual(item)
        ns:showDebugVisual(item.icon)
    end

    if ns:GetOption('disableHistoryTray') then
        -- hide the whole row unless visual debugging is turned on
        ns:showDebugVisual(row)
    else
        row:Show()
    end
end



function ns:updateTrackerUI(slot)
    local tracker = ns.trackerUI[slot]
    local iconSize = ns:GetOption('iconSize')
    local iconSpacing = ns:GetOption('iconSpacing')
    local textSize = ns:GetOption('textSize')

    -- Position UI next to frames
    tracker:SetPoint("TOPRIGHT", ns:slotToPartyFrame(slot), "TOPLEFT", -ns.SPACING_FROM_FRAMES, 0)
    tracker:SetSize(300, (iconSize+2)*2)

    tracker.bg:SetAllPoints(tracker)
    tracker.bg:SetColorTexture(0,0,0,0.4)
    ns:showDebugVisual(tracker.bg)

    tracker.specLabel:SetPoint("BOTTOMRIGHT", tracker, "TOPRIGHT", 0, 0)
    tracker.specLabel:SetFont(tracker.specLabel:GetFont(), textSize, "OUTLINE")
    tracker.specLabel:SetText(ns:specIdToString(specId))
    ns:showDebugVisual(tracker.specLabel)

    tracker.cpfMappingLabel:SetPoint("TOPLEFT", tracker, "TOPRIGHT", 3, -3)
    tracker.cpfMappingLabel:SetFont(tracker.cpfMappingLabel:GetFont(), 12, "OUTLINE")
    tracker.cpfMappingLabel:SetText("[" .. tracker.cpfMapping .. "] " .. slot)
    ns:showDebugVisual(tracker.cpfMappingLabel)
    tracker.cpfMappingLabel.bg:SetAllPoints(tracker.cpfMappingLabel)
    ns:showDebugVisual(tracker.cpfMappingLabel.bg)

    updateStaticRow(slot)
    updateHistoryTray(slot)

    tracker:SetWidth(math.max(tracker.staticRow:GetWidth(), tracker.historyTray:GetWidth()))
    tracker:SetHeight(tracker.staticRow:GetHeight() + tracker.historyTray:GetHeight() + iconSpacing)
end



-- specId is optional
function ns:setTrackerUIData(slot, playerName, specId)
    local tracker = ns.trackerUI[slot]
    --local row = ns.historyRows[slot]
    --ns:clearRow(row)
    tracker.cpfMapping = ns.allSlots[slot]
    tracker.specId = specId
    tracker.playerName = playerName
end



local function allocTrackerUIForSlot(slot)
    local tracker = CreateFrame("Frame", addonName .. "TrackerUI" .. slot, UIParent)
    tracker.slot = slot
    tracker.specId = nil
    tracker.playerName = nil
    tracker.cpfMapping = ns.allSlots[slot]

    -- Debug mode transparent background
    tracker.bg = tracker:CreateTexture(nil, "BACKGROUND")

    -- Debug mode text showing the detected class/spec
    tracker.specLabel = tracker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tracker.specLabel:SetTextColor(1,1,1)

    -- Debug mode text showing the CompactPartyFrameMember..i mapping
    tracker.cpfMappingLabel = tracker:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    tracker.cpfMappingLabel:SetTextColor(1,1,1)

    tracker.cpfMappingLabel.bg = tracker:CreateTexture() --nil, "BACKGROUND")
    tracker.cpfMappingLabel.bg:SetAllPoints()
    tracker.cpfMappingLabel.bg:SetColorTexture(1,0,0)


    -- The static cooldown tracker is just an empty list to be filled with icons
    tracker.staticRow = CreateFrame("Frame", "StaticRow", tracker)
    tracker.staticRow.items = {}

    -- The history tray
    tracker.historyTray = CreateFrame("Frame", "HistoryTray", tracker)
    tracker.historyTray.items = {}
    for i=1,ns.MAX_HISTORY do
        tracker.historyTray.items[i] = allocHistoryItem(tracker.historyTray, slot, i, true)
    end

    return tracker
end



-- Frames are allocated only once on load. The only reason to allocate new
-- frames is increasing MAX_HISTORY. Rather than handle that, just force the user
-- to /reload.
function ns:allocHistoryGrid()
    for slot, _ in pairs(ns.allSlots) do
        local tracker = allocTrackerUIForSlot(slot)
        ns.trackerUI[slot] = tracker
        tracker:Show()
        ns:updateTrackerUI(slot)
    end
end
