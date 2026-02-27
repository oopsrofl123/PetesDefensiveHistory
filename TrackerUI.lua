-- get addon namespace
local addonName, ns = ...
local LibButtonGlow = LibStub("LibButtonGlowcustom")
local GUIDToIndex = {}


function ns:indexToFrame(index)
    if DandersFrames then
        return _G["DandersPartyHeaderUnitButton" .. index]
    else
        return _G["CompactPartyFrameMember" .. index]
    end
end


function ns:indexToSlot(index)
    return ns:indexToFrame(index).unit
end


function ns:nameToSlot(name)
    for index=1, 5 do
        local slot = ns:indexToSlot(index)
        if UnitExists(slot) and UnitName(slot) == name then
            return slot
        end
    end
    return nil
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
        shiftHistoryTrayItem(items[i+1], items[i])
    end
    clearHistoryItem(items[fromIndex])
end



function ns:addBuffToHistoryTray(guid, buff)
    local index = GUIDToIndex[guid]
    local tray = ns.trackerUI[index].historyTray

    -- Don't do anything if the user disabled the history tray
    if ns:GetOption('disableHistoryTray') then return end

    ns:printDebug("aura instance ID " .. buff.auraInstanceId ..
        " added to history tray "..index.." after "..buff.duration.."s")

    -- Empty the youngest history slot
    shiftHistoryTrayLeftFrom(tray.items)
    
    -- Now that space has been made, add this ability to the tracker
    item = tray.items[ns.MAX_HISTORY]
    item.startTime = buff.startTime
    item.maxCD = buff.maxCD
    item.icon:SetTexture(buff.secretTexture)
    item.icon:Show()
    item.timer:Show()
    item:Show()
end



-- Glow an item in the static cooldown tracker. Abilities have known casters
function ns:startGlow(ability)
    local index = GUIDToIndex[ability.caster]
    local cd = ns.trackerUI[index].staticRow.items[ability.name]
    cd.swipeTexture:Hide()
    LibButtonGlow.ShowOverlayGlow(cd)
end



-- Stop glowing an item in the static cooldown tracker. Abilities have known casters
function ns:stopGlow(ability)
    local index = GUIDToIndex[ability.caster]
    local cd = ns.trackerUI[index].staticRow.items[ability.name]
    LibButtonGlow.HideOverlayGlow(cd)
end



-- If startTime is not nil, then also start a new cooldown swipe. If nil, it
-- is assumed that a cooldown swipe is already in progress (e.g., this ability
-- has charges).
--
-- Old important comments from other file describing issues with charge+CDR.
-- Support abilities with charges.
-- 1. If this is not an ability with charges, then start a swipe no
--    matter what. If the ability has CDR, then it could fire before
--    we expect.
-- 2. If the ability has charges, don't start a CD swipe if one is
--    already going. If one is already in
--    progress, then it will propagate itself if there are charges.
--
-- This logic is necessary because of delayed inference. Suppose one
-- charge of an ability is on CD and the second charge is used and
-- the ability can't be inferred until expiry - for a concrete example,
-- say the buff lasts 6s and the cd is 20s. At t=0 and 17 the ability
-- is used. At t=20 the first charge finishes its cd, at t=23 the
-- second charge's buff ends and the ability is identified. Since the
-- cooldown swipe completed at t=20, it did not know that it should
-- start a new swipe for the second charge, and numQueued was dropped
-- to 0. At t=23, we arrive here and it must be recorded that a charge
-- at t=0 prevented CD recovery until t=20. This is exactly what the CD
-- tracker provides.
function ns:queueCooldown(ability, startTime)
    local index = GUIDToIndex[ability.caster]
    local cd = ns.trackerUI[index].staticRow.items[ability.name]

    -- cd.startTime is the start time of the recharge, not the start time of the
    -- buff (=when the ability was cast). These can differ for abilities
    -- with charges. Some notes:
    --   * Single charge abilities: cdEndsAt = buff.startTime + ability.cooldown,
    --     even if there is dynamic CDR
    --   * Multi-charge abilities: cdEndsAt accounts for previous recharge completions.
    if cd.charges == 1 or cd.numQueued == 0 then
        cd.startTime = startTime
        cd.swipeTexture:SetCooldown(startTime, ability.cooldown)
    end
        
    -- CDR abilities will appear to queue a cooldown when they're used before
    -- their base CD is up.
    cd.numQueued = math.min(cd.numQueued + 1, ability.charges)
    -- If this was the last charge, then draw the dark cooldown swipe.
    -- Otherwise just show the edge.
    cd.swipeTexture:SetDrawSwipe(cd.numQueued == ability.charges)
    cd.swipeTexture:Show()
end



-- Allocate a blank history item and allocate all of its subcomponents. The
-- history item and all subcomponents are :Hide()ed. Callers should :Show()
-- desired elements based on whether the ability represented by this history
-- item is known.
function allocHistoryItem(row, index, countUp)
    local frameName = "item" .. index
    local f = CreateFrame("Frame", frameName, row)
    local textSize = ns:GetOption('textSize')

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
        -- Count-down timer and cooldown swipe for identified spells
        f.swipeTexture = CreateFrame("Cooldown", frameName .. "CDSwipe", f, "CooldownFrameTemplate")
        f.swipeTexture:SetAllPoints()
        -- hide blizzard's countdown text so we can control the size
        f.swipeTexture:SetHideCountdownNumbers(true)

        f.swipeTexture.timer = f.swipeTexture:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.swipeTexture.timer:SetTextColor(1,1,1)
        f.swipeTexture.timer:SetPoint("CENTER", f, 0, 0)
        f.swipeTexture.timer:SetFont(f.swipeTexture.timer:GetFont(), textSize, "THICKOUTLINE")

        f.swipeTexture.chargeLabel = f.swipeTexture:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        f.swipeTexture.chargeLabel:SetTextColor(1,1,1)
        f.swipeTexture.chargeLabel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 0)
        f.swipeTexture.chargeLabel:SetFont(f.swipeTexture.chargeLabel:GetFont(), textSize, "THICKOUTLINE")

        f.warningbg = f:CreateTexture(nil, "OVERLAY", nil, 0)
        f.warningbg:SetPoint('CENTER', f.icon, 'TOPLEFT', 4, -1)
        f.warningbg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        --f.warningbg:SetVertexColor(233/255, 214/255, 167/255, 0.9)
        f.warningbg:SetVertexColor(0,0,0,1)

        f.warning = f:CreateTexture(nil, "OVERLAY", nil, 1)
        f.warning:SetPoint('CENTER', f.icon, 'TOPLEFT', 4, -1)
        f.warning:SetAtlas("QuestNormal")
        f.warning:SetVertexColor(1, 0, 0)

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
        item.warningbg:SetSize(iconSize/2, iconSize/2)
        item.warning:SetSize(iconSize/2, iconSize/2)
    end
end



-- XXX: TODO: This function leaks frames, but it happens rarely enough that we
-- can live with it for a while.
local function updateStaticRow(index)
    local tracker = ns.trackerUI[index]
    local row = tracker.staticRow
    local slot = ns:indexToSlot(index)
    local guid = ns.slotToGUID[slot]
    local char = ns:getTrackedCharacterByGUID(guid)
    -- There won't always be a char: before loading and players without libspec
    local abilities = char and char:getAbilities() or {}
    local iconSize = ns:GetOption('iconSize')
    local iconSpacing = ns:GetOption('iconSpacing')

    row:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", 0, 0)

    -- Add a new frame for each tracked cooldown
    for _, ability in pairs(abilities) do
        if not row.items[ability.name] then
            local newItem = allocHistoryItem(row, ability.name, false)
            newItem.spellId = ability.id
            row.items[ability.name] = newItem
            if ability.iconId then
                newItem.icon:SetTexture(ability.iconId)
            end
            newItem.cooldown = ability.cooldown
            newItem.charges = ability.charges
            newItem.numQueued = 0
            if newItem.charges > 1 then
                -- XXX: TODO: doesn't show when not on cooldown
                newItem.swipeTexture.chargeLabel:Show()
                newItem.swipeTexture.chargeLabel:SetText(newItem.charges)
            else
                newItem.swipeTexture.chargeLabel:Hide()
            end

            if ability.cdr then
                newItem.warningbg:Show()
                newItem.warning:Show()
            else
                newItem.warningbg:Hide()
                newItem.warning:Hide()
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
            --row.items[name] = nil  -- XXX: TODO: wait for frame pool implementation
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
local function updateHistoryTray(index)
    local tracker = ns.trackerUI[index]
    local row = tracker.historyTray

    local iconSize = ns:GetOption('iconSize')
    local textSize = ns:GetOption('textSize')
    local iconSpacing = ns:GetOption('iconSpacing')

    row:SetSize(ns.MAX_HISTORY*(iconSize+iconSpacing) - iconSpacing, iconSize+2)
    row:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", 0, -(iconSize + iconSpacing))

    for i=1, ns.MAX_HISTORY do
        local item = row.items[i]
        sizeHistoryItem(item)
        -- items are statically positioned with index 1 being the oldest
        item:SetPoint("LEFT", row, "LEFT", (i-1)*(iconSize + iconSpacing), 0)
        ns:showDebugVisual(item)
        ns:showDebugVisual(item.icon)
    end

    if ns:GetOption('disableHistoryTray') then
        ns:showDebugVisual(row) -- hide the row unless visual debugging is turned on
    else
        row:Show()
    end
end



-- It is the UI's job to be able to map GUIDs -> indexes
function ns:updateTrackerUI()
    for index=1, 5 do
        local slot = ns:indexToSlot(index)
        if UnitExists(slot) then
            -- Keep the guid -> index map updated
            GUIDToIndex[ns.slotToGUID[slot]] = index
        end
        ns:updateTrackerUIByIndex(index)

        -- XXX: TODO: hack to clear history tray while history items/cooldowns are
        -- folded into Character(). updateHistoryTray() should ask Character() what
        -- historyItems it should show in updateTrackerUIByIndex()
        for _, item in pairs(ns.trackerUI[index].historyTray.items) do
            clearHistoryItem(item)
        end
    end
end



function ns:updateTrackerUIByIndex(index)
    local tracker = ns.trackerUI[index]
    local slot = ns:indexToSlot(index)
    local guid = ns.slotToGUID[slot]
    local char = ns:getTrackedCharacterByGUID(guid)
    local iconSize = ns:GetOption('iconSize')
    local iconSpacing = ns:GetOption('iconSpacing')
    local textSize = ns:GetOption('textSize')

    -- Position UI next to frames
    tracker:SetPoint("TOPRIGHT", ns:indexToFrame(index), "TOPLEFT", -ns.SPACING_FROM_FRAMES, 0)

    tracker.bg:SetAllPoints(tracker)
    tracker.bg:SetColorTexture(0,0,0,0.4)
    ns:showDebugVisual(tracker.bg)

    tracker.specLabel:SetPoint("BOTTOMRIGHT", tracker, "TOPRIGHT", 0, 0)
    tracker.specLabel:SetFont(tracker.specLabel:GetFont(), textSize, "OUTLINE")
    local spec = char and char:getSpecString() or nil
    tracker.specLabel:SetText(spec)
    ns:showDebugVisual(tracker.specLabel)

    tracker.indexLabel:SetPoint("TOPLEFT", tracker, "TOPRIGHT", 3, -3)
    tracker.indexLabel:SetFont(tracker.indexLabel:GetFont(), 12, "OUTLINE")
    tracker.indexLabel:SetText("["..index.."] "..ns:indexToFrame(index).unit)
    ns:showDebugVisual(tracker.indexLabel)
    tracker.indexLabel.bg:SetAllPoints(tracker.indexLabel)
    ns:showDebugVisual(tracker.indexLabel.bg)

    updateStaticRow(index)
    updateHistoryTray(index)

    tracker:SetWidth(math.max(tracker.staticRow:GetWidth(), tracker.historyTray:GetWidth()))
    tracker:SetHeight(tracker.staticRow:GetHeight() + tracker.historyTray:GetHeight() + iconSpacing)
end



local function allocTrackerUIForSlot(index)
    local tracker = CreateFrame("Frame", addonName .. "TrackerUI" .. index, UIParent)
    tracker.index = index

    -- Debug mode transparent background
    tracker.bg = tracker:CreateTexture(nil, "BACKGROUND")

    -- Debug mode text showing the detected class/spec
    tracker.specLabel = tracker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tracker.specLabel:SetTextColor(1,1,1)

    -- Debug mode text showing the CompactPartyFrameMember..i mapping
    tracker.indexLabel = tracker:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    tracker.indexLabel:SetTextColor(1,1,1)

    tracker.indexLabel.bg = tracker:CreateTexture()
    tracker.indexLabel.bg:SetAllPoints()
    tracker.indexLabel.bg:SetColorTexture(1,0,0)

    -- The static cooldown tracker is just an empty list to be filled with icons
    tracker.staticRow = CreateFrame("Frame", "StaticRow", tracker)
    tracker.staticRow.items = {}

    -- The history tray
    tracker.historyTray = CreateFrame("Frame", "HistoryTray", tracker)
    tracker.historyTray.items = {}
    for i=1, ns.MAX_HISTORY do
        tracker.historyTray.items[i] = allocHistoryItem(tracker.historyTray, index, i, true)
    end

    return tracker
end



-- Frames are allocated only once on load. The only reason to allocate new
-- frames is increasing MAX_HISTORY. Rather than handle that, just force the user
-- to /reload.
function ns:allocHistoryGrid()
    for index=1, 5 do
        local tracker = allocTrackerUIForSlot(index)
        ns.trackerUI[index] = tracker
        tracker:Show()
    end
    ns:updateTrackerUI()
end
