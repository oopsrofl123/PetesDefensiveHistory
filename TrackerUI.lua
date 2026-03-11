-- get addon namespace
local addonName, ns = ...
local LibButtonGlow = LibStub("LibButtonGlowcustom")
local GUIDToIndex = {}
local MAX_HISTORY = 4
local SPACING_FROM_FRAMES = 2
local DEFAULT_ICON = 134400    -- Question mark

ns.trackerUI = {}  -- The UI elements next to the frames


-- Make frame pools for the UI elements
-- XXX: TODO: None of these pools properly reset the widgets they receive. So far it
-- doesn't matter because only cooldown trackers release to or acquire from them, but
-- surely one day something will break.
local framePool = CreateFramePool("Frame", UIParent)

local cooldownFramePool = CreateFramePool("Cooldown", UIParent, "CooldownFrameTemplate")

local gameFontNormalPool =
    CreateObjectPool(function() return UIParent:CreateFontString(nil, 'ARTWORK', 'GameFontNormal') end)

local gameFontNormalSmallPool =
    CreateObjectPool(function() return UIParent:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall') end)

local numberFontNormalSmallPool =
    CreateObjectPool(function() return UIParent:CreateFontString(nil, 'ARTWORK', 'numberFontNormalSmall') end)

local texturePool = CreateTexturePool(UIParent, 'ARTWORK', 0, nil,
    function(pool, frame)
        frame:SetVertexColor(1, 1, 1)
    end)


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


-- Initialize a history item with blank values and hide it. Do not perform
-- allocation or do potentially unsafe things like move or reanchor elements.
local function clearHistoryItem(item)
    -- Local data per historyItem
    item.startTime = nil
    item.maxCD = nil
    item.numQueued = 0

    -- Initialize visuals
    item.icon:SetTexture(DEFAULT_ICON)
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
    fromIndex = fromIndex or MAX_HISTORY
    for i=1, MAX_HISTORY-1 do
        shiftHistoryTrayItem(items[i+1], items[i])
    end
    clearHistoryItem(items[fromIndex])
end



-- Used to have a GUID argument: if the event is going to the tracker, then it
-- wasn't IDed, so it always goes to the target.
function ns:addEventToHistoryTray(event)
    local index = GUIDToIndex[event:getSource()]
    local tray = ns.trackerUI[index].historyTray
    local aura = event:getAura()

    -- Don't do anything if the user disabled the history tray
    if ns:GetOption('disableHistoryTray') then return end

    ns:printDebug(ns.LOGTYPE.UI, ns.LOGLEVEL.Normal,
        "aura instance ID " .. event:getId() ..
        " added to history tray "..index.." after ".. event:timeSince().."s")

    -- Empty the youngest history slot
    shiftHistoryTrayLeftFrom(tray.items)
    
    -- Now that space has been made, add this ability to the tracker
    item = tray.items[MAX_HISTORY]
    item.startTime = event:getTime()
    item.maxCD = event:getMaxCD()
    -- If an aura 
    item.icon:SetTexture(aura and aura.secretTexture or DEFAULT_ICON)
    item.icon:Show()
    item.timer:Show()
    item:Show()
end



-- Glow an item in the static cooldown tracker. Abilities have known casters
function ns:startGlow(ability)
    local index = GUIDToIndex[ability.caster]
    local cd = ns.trackerUI[index].staticRow.items[ability.name]
    -- The cooldown swipe could be active, e.g. for abilities with charges,
    -- CDR abilities, or redirected buffs like VDH meta, which can be applied
    -- by several other abilities.
    cd.swipeTexture:Hide()
    LibButtonGlow.ShowOverlayGlow(cd)
end



-- Stop glowing an item in the static cooldown tracker. Abilities have known casters
function ns:stopGlow(ability)
    local index = GUIDToIndex[ability.caster]
    local cd = ns.trackerUI[index].staticRow.items[ability.name]
    LibButtonGlow.HideOverlayGlow(cd)
    -- The cooldown swipe could be active, e.g. for abilities with charges,
    -- CDR abilities, or redirected buffs like VDH meta, which can be applied
    -- by several other abilities.
    if cd.numQueued > 0 then
        cd.swipeTexture:Show()
    end
end



-- XXX: TODO: this logic shouldn't be here. it should be in Character
-- after folding in cooldown tracking. Only code connecting the tracked
-- cooldown to display should be here.
--
-- Describes why startTime must be computed the way it is. This won't work
-- for abilities with both charges and dynamic CDR. There is no solution in
-- that case.
--
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
function ns:queueCooldown(ability)
    local startTime = ns.cdTracker[ability.caster][ability.name]:head() - ability.cooldown
    local index = GUIDToIndex[ability.caster]
    local cd = ns.trackerUI[index].staticRow.items[ability.name]

    -- cd.startTime is the start time of the recharge, not the start time of the
    -- buff (=when the ability was cast). These can differ for abilities
    -- with charges.
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



-- alloc* functions must not depend on any runtime data
local function allocCountUpTimer(parent)
    local textSize = ns:GetOption('textSize')
    local timer = gameFontNormalPool:Acquire()
    timer:SetParent(parent)
    timer:SetDrawLayer("OVERLAY")

    timer:SetPoint("CENTER", parent, 0, 0)
    timer:SetTextColor(1,1,1)
    timer:SetFont(timer:GetFont(), textSize, "THICKOUTLINE")
    parent:SetScript("OnUpdate", function(self)
        if self.startTime and self.maxCD then
            local elapsed = GetTime() - self.startTime
            if elapsed <= self.maxCD then
                timer:SetFormattedText("%.0f", elapsed)
            else
                timer:SetText("")
                if ns:GetOption('hideHistoryItemsAtMaxCd') then
                    self:Hide()  -- hide the whole icon+timer
                end
            end
        else
            timer:SetText("")
        end
    end)
    return timer
end



-- alloc* functions must not depend on any runtime data
local function allocCountDownTimer(parent, frameName)
    local textSize = ns:GetOption('textSize')
    local swipeTexture = cooldownFramePool:Acquire()

    swipeTexture:SetParent(parent)
    swipeTexture:SetAllPoints()
    -- hide blizzard's countdown text so we can control the size
    swipeTexture:SetHideCountdownNumbers(true)

    swipeTexture.timer = gameFontNormalPool:Acquire()
    swipeTexture.timer:SetParent(swipeTexture)
    swipeTexture.timer:SetDrawLayer('OVERLAY')
    
    swipeTexture.timer:SetTextColor(1,1,1)
    swipeTexture.timer:SetPoint("CENTER", parent, 0, 0)
    swipeTexture.timer:SetFont(swipeTexture.timer:GetFont(), textSize, "THICKOUTLINE")

    swipeTexture.chargeLabel = numberFontNormalSmallPool:Acquire()
    swipeTexture.chargeLabel:SetParent(swipeTexture)
    swipeTexture.chargeLabel:SetDrawLayer('OVERLAY')
    
    swipeTexture.chargeLabel:SetTextColor(1,1,1)
    swipeTexture.chargeLabel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -1, 0)
    swipeTexture.chargeLabel:SetFont(swipeTexture.chargeLabel:GetFont(), textSize, "THICKOUTLINE")

    local warningbg = texturePool:Acquire()
    warningbg:SetParent(parent)
    warningbg:SetDrawLayer('OVERLAY', 0)
    
    warningbg:SetPoint('CENTER', parent.icon, 'TOPLEFT', 4, -1)
    warningbg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    warningbg:SetVertexColor(0,0,0,1)

    local warning = texturePool:Acquire()
    warning:SetParent(parent)
    warning:SetDrawLayer('OVERLAY', 1)
    warning:SetPoint('CENTER', parent.icon, 'TOPLEFT', 4, -1)
    warning:SetAtlas("QuestNormal")
    warning:SetVertexColor(1, 0, 0)

    -- Handle a couple of things:
    --    1. update cooldown timer text
    --    2. handle cooldown charges: monitor the cooldown FIFO to catch
    --       when a cooldown completes. if it does, pop the CD and check
    --       if the FIFO is empty. if it isn't, start a new swipe with the
    --       next CD in the queue.
    parent:SetScript("OnUpdate", function(self)
        local now = GetTime()
        if self.numQueued > 0 then
            local untilAvailable = self.startTime + self.cooldown - now
            if untilAvailable > 0 then
                swipeTexture.timer:SetFormattedText("%.0f", untilAvailable)
            else
                swipeTexture:SetDrawSwipe(false)
                self.numQueued = self.numQueued - 1
                if self.numQueued > 0 then
                    self.startTime = now
                    swipeTexture:SetCooldown(now, self.cooldown)
                end
            end
            swipeTexture.chargeLabel:SetText(self.charges - self.numQueued)
        else
            swipeTexture.timer:SetText("")
        end
    end)

    return swipeTexture, warningbg, warning
end



-- Allocate a blank history item and allocate all of its subcomponents. The
-- history item and all subcomponents are :Hide()ed. Callers should :Show()
-- desired elements based on whether the ability represented by this history
-- item is known.
-- alloc* functions must not depend on any runtime data
local function allocHistoryItem(parent, index, countUp)
    local frameName = "item" .. index
    local f = framePool:Acquire()
    f:SetParent(parent)

    f.icon = texturePool:Acquire()
    f.icon:SetParent(f)
    f.icon:SetDrawLayer('ARTWORK', 0)
    f.icon:SetAllPoints()

    -- Is this a count-up history tray item or a count-down cooldown tracker item?
    -- If the cooldown swipe is used, the timer needs to be parented to the 
    -- CooldownFrameTemplate so that the text is layered at the correct level relative
    -- to the swipe texture.
    f.countUp = countUp
    if countUp then
        f.timer = allocCountUpTimer(f)
    else
        f.swipeTexture, f.warningbg, f.warning = allocCountDownTimer(f, frameName)
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


local function releaseHistoryItem(item)
    texturePool:Release(item.icon)
    if item.countUp then
        gameFontNormalPool:Release(item.timer)
    else
        gameFontNormalPool:Release(item.swipeTexture.timer)
        numberFontNormalSmallPool:Release(item.swipeTexture.chargeLabel)
        texturePool:Release(item.warningbg)
        texturePool:Release(item.warning)
        cooldownFramePool:Release(item.swipeTexture)
    end
    framePool:Release(item)
end



-- XXX: TODO: This function leaks frames, but it happens rarely enough that we
-- can live with it for a while.
local function updateStaticRow(index)
    local tracker = ns.trackerUI[index]
    local row = tracker.staticRow
    local slot = ns:indexToSlot(index)
    local guid, char = ns:getTrackedCharacterBySlot(slot)
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
    for name, item in pairs(row.items) do
        if not abilities[name] then
            -- XXX: TODO: WARNING! this leaks frames! need a frame pool
            -- since frames cannot be deallocated.
            item:ClearAllPoints()
            item:Hide()
            releaseHistoryItem(item)
            row.items[name] = nil
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

    row:SetSize(MAX_HISTORY*(iconSize+iconSpacing) - iconSpacing, iconSize+2)
    row:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", 0, -(iconSize + iconSpacing))

    for i=1, MAX_HISTORY do
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
    ns:printDebug(ns.LOGTYPE.UI, ns.LOGLEVEL.Normal, "Updating TrackerUI")
    for index=1, 5 do
        local slot = ns:indexToSlot(index)
        local guid, char = ns:getTrackedCharacterBySlot(slot)
        if guid then
            -- Keep the guid -> index map updated
            GUIDToIndex[guid] = index
        end
        ns:updateTrackerUIByIndex(index)

        -- XXX: TODO: hack to clear history tray while history items/cooldowns are being
        -- folded into Character(). updateHistoryTray() should ask Character() what
        -- historyItems it should show in updateTrackerUIByIndex()
        for _, item in pairs(ns.trackerUI[index].historyTray.items) do
            clearHistoryItem(item)
        end
    end
end



function ns:updateTrackerUIByIndex(index)
    ns:printDebug(ns.LOGTYPE.UI, ns.LOGLEVEL.Normal,
        "Updating TrackerUI for index="..tostring(index))
    local tracker = ns.trackerUI[index]
    local slot = ns:indexToSlot(index)
    local guid, char = ns:getTrackedCharacterBySlot(slot)
    local iconSize = ns:GetOption('iconSize')
    local iconSpacing = ns:GetOption('iconSpacing')
    local textSize = ns:GetOption('textSize')

    -- Position UI next to frames
    tracker:SetPoint("TOPRIGHT", ns:indexToFrame(index), "TOPLEFT", -SPACING_FROM_FRAMES, 0)

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
    ns:printDebug(ns.LOGTYPE.UI, ns.LOGLEVEL.Normal,
        "Allocating TrackerUI for index="..tostring(index))
    local tracker = framePool:Acquire()
    tracker:SetParent(UIParent)
    tracker.index = index

    -- Debug mode transparent background
    tracker.bg = texturePool:Acquire()
    tracker.bg:SetParent(tracker)
    tracker.bg:SetDrawLayer('BACKGROUND', 0)

    -- Debug mode text showing the detected class/spec
    tracker.specLabel = gameFontNormalSmallPool:Acquire()
    tracker.specLabel:SetParent(tracker)
    tracker.specLabel:SetDrawLayer('OVERLAY')
    tracker.specLabel:SetTextColor(1,1,1)

    -- Debug mode text showing the CompactPartyFrameMember..i mapping
    tracker.indexLabel = numberFontNormalSmallPool:Acquire()
    tracker.indexLabel:SetParent(tracker)
    tracker.indexLabel:SetDrawLayer('OVERLAY')
    tracker.indexLabel:SetTextColor(1,1,1)

    tracker.indexLabel.bg = texturePool:Acquire()
    tracker.indexLabel.bg:SetParent(tracker)
    tracker.indexLabel.bg:SetDrawLayer('ARTWORK', 0)
    tracker.indexLabel.bg:SetAllPoints()
    tracker.indexLabel.bg:SetColorTexture(1,0,0)

    -- The static cooldown tracker is just an empty list to be filled with icons
    tracker.staticRow = framePool:Acquire()
    tracker.staticRow:SetParent(tracker)
    tracker.staticRow.items = {}

    -- The history tray
    tracker.historyTray = framePool:Acquire()
    tracker.historyTray:SetParent(tracker)
    tracker.historyTray.items = {}
    for i=1, MAX_HISTORY do
        tracker.historyTray.items[i] = allocHistoryItem(tracker.historyTray, index, i, true)
    end

    return tracker
end



function ns:allocTrackerUI()
    ns:printDebug(ns.LOGTYPE.UI, ns.LOGLEVEL.Normal, "Allocating TrackerUI")
    for index=1, 5 do
        local tracker = allocTrackerUIForSlot(index)
        ns.trackerUI[index] = tracker
    end
end
