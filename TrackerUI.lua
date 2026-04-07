-- get addon namespace
local addonName, ns = ...
local LibButtonGlow = LibStub("LibButtonGlowcustom")
local GUIDToIndex = {}
local DEFAULT_ICON = 134400    -- Question mark

ns.trackerUI = {}  -- The UI elements next to the frames


-- Try to support Masque
local Masque = LibStub("Masque", true)
local masqueGroup
do
    if Masque then
        masqueGroup = Masque:Group(addonName)
    end
end


-- XXX: TODO: These resetters should revert more of the :Set* calls used in the UI code
local function clearAnchorsResetter(pool, frame)
    frame:ClearAllPoints()
    frame:Hide()
end

local function clearWidgetAnchorsResetter(pool, widget)
    widget:ClearAllPoints()
end
    
-- Make frame pools for the UI elements
-- XXX: TODO: None of these pools properly reset the widgets they receive. So far it
-- doesn't matter because only cooldown trackers release to or acquire from them, but
-- surely one day something will break.
local framePool = CreateFramePool("Frame", UIParent, clearAnchorsResetter)

local cooldownFramePool = CreateFramePool("Cooldown", UIParent, "CooldownFrameTemplate", clearAnchorsResetter)

local gameFontNormalPool =
    CreateObjectPool(function() return UIParent:CreateFontString(nil, 'ARTWORK', 'GameFontNormal') end, clearWidgetAnchorsResetter)

local gameFontNormalSmallPool =
    CreateObjectPool(function() return UIParent:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall') end, clearWidgetAnchorsResetter)

local numberFontNormalSmallPool =
    CreateObjectPool(function() return UIParent:CreateFontString(nil, 'ARTWORK', 'numberFontNormalSmall') end, clearWidgetAnchorsResetter)

local texturePool = CreateTexturePool(UIParent, 'ARTWORK', 0, nil,
    function(pool, frame)
        frame:ClearAllPoints()
        frame:SetVertexColor(1, 1, 1)
    end)


-- index i should be 0-based
local function offsets(direction, i, amount)
    local xoffset = 0
    local yoffset = 0
    local wrap = ns:GetOption('wrapIcons')
    if direction == "LEFT" then
        xoffset = -(i % wrap)
        yoffset = -math.floor(i/wrap)
    elseif direction == "RIGHT" then
        xoffset = (i % wrap)
        yoffset = -math.floor(i/wrap)
    elseif direction == "UP" then
        xoffset = math.floor(i/wrap)
        yoffset = (i % wrap)
    else
        xoffset = math.floor(i/wrap)
        yoffset = -(i % wrap)
    end
    return xoffset*amount, yoffset*amount
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
        item.cooldown:Hide()
        item.activeDuration:Hide()
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
    local maxHistory = ns:GetOption("maxHistoryTrayItems")
    fromIndex = fromIndex or maxHistory
    for i=1, maxHistory-1 do
        shiftHistoryTrayItem(items[i+1], items[i])
    end
    clearHistoryItem(items[fromIndex])
end



-- Used to have a GUID argument: if the event is going to the tracker, then it
-- wasn't IDed, so it always goes to the target.
function ns:addEventToHistoryTray(event)
    local slot = ns:cosmeticOnlyMapGUIDToSlot(event:getSource())
    local tray = ns.trackerUI[slot].historyTray
    local aura = event:getAura()

    -- Don't do anything if the user disabled the history tray
    if ns:GetOption('disableHistoryTray') then return end

    ns:printDebug(ns.LOGTYPE.UI, ns.LOGLEVEL.Normal,
        "aura instance ID " .. event:getId() ..
        " added to history tray "..slot.." after ".. event:timeSince().."s")

    -- Empty the youngest history slot
    shiftHistoryTrayLeftFrom(tray.items)
    
    -- Now that space has been made, add this ability to the tracker
    item = tray.items[ns:GetOption('maxHistoryTrayItems')]
    item.startTime = event:getTime()
    item.maxCD = event:getMaxCD()
    -- If an aura 
    item.icon:SetTexture(aura and aura.secretTexture or DEFAULT_ICON)
    item.icon:Show()
    item.timer:Show()
    item:Show()
end



-- Some notes on current usage of these icon functions:
--      1. startGlow in :infer()
--      2. stopGlow -> queueCooldown in :expire()
-- :expire() is only circumvented in the numPossibleSolutions=0 case, in which the
-- event did not interact with a glow/cooldown swipe.
--
-- Glow an item in the static cooldown tracker. Abilities have known casters
function ns:startGlow(ability, duration, initGlow)
    local slot = ns:cosmeticOnlyMapGUIDToSlot(ability.caster)
    local cd = ns.trackerUI[slot].staticRow.items[ability.name]

    -- The cooldown swipe could be active, e.g. for abilities with charges,
    -- CDR abilities, or redirected buffs like VDH meta, which can be applied
    -- by several other abilities.

    -- duration: if the ability creates an aura, duration holds secret data about
    -- how long the aura will last. this can be updated (e.g., fiery
    -- brand's duration is updated each time it spreads to another enemy).
    if duration then
        cd.activeDuration:SetCooldownFromDurationObject(duration)
        cd.activeDuration:Show() 
        if cd.chargeLabel:IsShown() then
            cd.chargeLabel:Hide()
        end
    end

    -- Always hide the cooldown swipe widget when the ability is active.
    cd.cooldown:Hide()

    -- initGlow=false for updates, e.g.
    if initGlow then
        LibButtonGlow.ShowOverlayGlow(cd)
    end
end



-- Stop glowing an item in the static cooldown tracker. Abilities have known casters
function ns:stopGlow(ability)
    local slot = ns:cosmeticOnlyMapGUIDToSlot(ability.caster)
    local cd = ns.trackerUI[slot].staticRow.items[ability.name]

    LibButtonGlow.HideOverlayGlow(cd)
    if cd.charges > 1 then
        cd.chargeLabel:Show()
    end

    -- the active duration cooldown swipe doesn't update if the aura ends early (e.g.,
    -- the user clicks it off). Need to clear to ensure it's gone.
    cd.activeDuration:Clear()

    -- Handle the case where there was a cooldown swipe/timer running before the
    -- ability was activated -- e.g., using the second charge of an ability while its
    -- first charge cooldown was already animating.
    if cd.numQueued > 0 then
        cd.cooldown:Show()
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
function ns:queueCooldown(ability, availableAt)
    local startTime = availableAt - ability.cooldown
    local slot = ns:cosmeticOnlyMapGUIDToSlot(ability.caster)
    local cd = ns.trackerUI[slot].staticRow.items[ability.name]

    -- cd.startTime is the start time of the recharge, not the start time of the
    -- buff (=when the ability was cast). These can differ for abilities
    -- with charges.
    --   * Single charge abilities: cdEndsAt = buff.startTime + ability.cooldown,
    --     even if there is dynamic CDR
    --   * Multi-charge abilities: cdEndsAt accounts for previous recharge completions.
    -- startTime < cd.startTime: there is a rare case where two ability charges are used
    -- very close together and the second is IDed first (GoAK is an example). in this
    -- case, the first event will get the later cooldown charge (and is actually wrong, but
    -- by a small amount). since event batches are processes in order, it will be the first
    -- event to call queueCooldown and set numQueued=1. a correct solution requires reworking
    -- the cdfifo. this hack solution ensures the younger charge controls the swipe.
    if cd.charges == 1 or cd.numQueued == 0 or startTime < cd.startTime then
        cd.startTime = startTime
        cd.cooldown:SetCooldown(startTime, ability.cooldown)
    end

    -- CDR abilities will appear to queue a cooldown when they're used before
    -- their base CD is up.
    cd.numQueued = math.min(cd.numQueued + 1, ability.charges)
    -- If this was the last charge, then draw the dark cooldown swipe.
    -- Otherwise just show the edge.
    cd.cooldown:SetDrawSwipe(cd.numQueued == ability.charges)
    cd.cooldown:Show()
end



local function sizeHistoryItem(item)
    local iconSize = ns:GetOption('iconSize')
    local textSize = ns:GetOption('textSize')
    local textOutline = ns.textOutlines[ns:GetOption("textOutline")]

    if item.countUp then
        local historyTrayScale = ns:GetOption("historyTrayScale")
        iconSize = iconSize * historyTrayScale
        textSize = textSize * historyTrayScale
        item:SetSize(iconSize, iconSize)
        item.timer:SetFont(item.timer:GetFont(), textSize, textOutline)
    else
        item:SetSize(iconSize, iconSize)
        item.cooldown.timer:SetFont(item.cooldown.timer:GetFont(), textSize, textOutline)
        item.chargeLabel:SetFont(item.chargeLabel:GetFont(), textSize, textOutline)
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
local function allocCountDownTimer(parent)
    local textSize = ns:GetOption('textSize')

    local cooldown = cooldownFramePool:Acquire()
    cooldown:SetParent(parent)
    cooldown:SetAllPoints()
    -- hide blizzard's countdown text so we can control the size
    cooldown:SetHideCountdownNumbers(true)

    cooldown.timer = gameFontNormalPool:Acquire()
    cooldown.timer:SetParent(cooldown)
    cooldown.timer:SetDrawLayer('OVERLAY')
    cooldown.timer:SetTextColor(1,1,1)
    cooldown.timer:SetPoint("CENTER", parent, 0, 0)
    cooldown.timer:SetFont(cooldown.timer:GetFont(), textSize, textOutline)

    local activeDuration = cooldownFramePool:Acquire()
    activeDuration:SetParent(parent)
    activeDuration:SetAllPoints()
    activeDuration:SetHideCountdownNumbers(true)  -- no timer text on active aura
    -- active duration is a reverse swipe
    activeDuration:SetReverse(true)
    activeDuration:SetDrawSwipe(true)

    parent.chargeLabel = numberFontNormalSmallPool:Acquire()
    parent.chargeLabel:SetParent(parent)
    parent.chargeLabel:SetDrawLayer('OVERLAY')
    
    parent.chargeLabel:SetTextColor(1,1,1)
    parent.chargeLabel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -1, 0)
    parent.chargeLabel:SetFont(parent.chargeLabel:GetFont(), textSize, textOutline)

    local warningbg = texturePool:Acquire()
    warningbg:SetParent(parent)
    warningbg:SetDrawLayer('OVERLAY', 0)
    
    warningbg:SetPoint('CENTER', parent.icon, 'TOPLEFT', 4, -1)
    warningbg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    warningbg:SetVertexColor(0,0,0,1)

    local warning = texturePool:Acquire()
    warning:SetParent(parent)
    warning:SetDrawLayer('OVERLAY', 1)
    warning:ClearAllPoints()
    warning:SetPoint('CENTER', warningbg) --, 'TOPLEFT', 4, -1)
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
            local untilAvailable = self.startTime + self.cooldownInSeconds - now
            if untilAvailable > 0 then
                cooldown.timer:SetFormattedText("%.0f", untilAvailable)
            else
                cooldown:SetDrawSwipe(false)
                self.numQueued = self.numQueued - 1
                if self.numQueued > 0 then
                    self.startTime = now
                    cooldown:SetCooldown(now, self.cooldownInSeconds)
                end
            end
            self.chargeLabel:SetText(self.charges - self.numQueued)
        else
            cooldown.timer:SetText("")
        end
    end)

    return cooldown, activeDuration, warningbg, warning
end




local function handleElvUI(frame)
    -- I think :CreateBackdrop() makes a frame, so don't call this more than once
    if ElvUI and not Masque then  -- Masque overrides ElvUI
        local E, L, V, P, G = unpack(ElvUI)
        if not frame.backdrop then
            -- Only strip once, or else the icon texture will always be stripped
            frame:StripTextures()
            frame:CreateBackdrop()
        end
        frame.backdrop:SetAllPoints()

        frame.icon:SetInside(frame.backdrop)
        frame.icon:SetTexCoord(unpack(E.TexCoords))
    end
end


-- Allocate a blank history item and allocate all of its subcomponents. The
-- history item and all subcomponents are :Hide()ed. Callers should :Show()
-- desired elements based on whether the ability represented by this history
-- item is known.
-- alloc* functions must not depend on any runtime data
local function allocHistoryItem(parent, countUp)
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
        f.cooldown, f.activeDuration, f.warningbg, f.warning = allocCountDownTimer(f)
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

    if Masque and masqueGroup and not f.masqueAdded then
        masqueGroup:AddButton(f, { Icon=f.icon, Cooldown=f.cooldown }, "Aura")
        f.masqueAdded = true
    end

    return clearHistoryItem(f)
end


local function releaseHistoryItem(item)
    if Masque and masqueGroup and f.masqueAdded then
        masqueGroup:RemoveButton(f)
    end
    texturePool:Release(item.icon)
    if item.countUp then
        gameFontNormalPool:Release(item.timer)
    else
        gameFontNormalPool:Release(item.cooldown.timer)
        numberFontNormalSmallPool:Release(item.chargeLabel)
        texturePool:Release(item.warningbg)
        texturePool:Release(item.warning)
        cooldownFramePool:Release(item.cooldown)
        cooldownFramePool:Release(item.activeDuration)
    end
    item:ClearAllPoints()
    item:Hide()
    framePool:Release(item)
end



-- XXX: TODO: This function leaks frames, but it happens rarely enough that we
-- can live with it for a while.
local function updateStaticRow(slot)
    local tracker = ns.trackerUI[slot]
    local row = tracker.staticRow
    local guid, char = ns:getTrackedCharacterBySlot(slot)
    -- There won't always be a char: before loading and players without libspec
    local abilities = char and char:getAbilities() or {}
    local iconSize = ns:GetOption('iconSize')
    local iconSpacing = ns:GetOption('iconSpacing')
    local dir = ns.growthDirections[ns:GetOption('growthDirection')]
    local antidir = ns.antiDirection[dir]

    -- Add a new frame for each tracked cooldown
    for _, ability in pairs(abilities) do
        if not row.items[ability.name] then
            row.items[ability.name] = allocHistoryItem(row, false)
            -- XXX: TODO: active state data should be maintained elsewhere. the static ability
            -- data is fine.
            -- Don't set this below or it'll clobber the active state of the cooldown queue
            row.items[ability.name].numQueued = 0
        end

        local item = row.items[ability.name]
        
        -- Always update static ability data. spec could have changed
        item.spellId = ability.id
        if ability.iconId then
            item.icon:SetTexture(ability.iconId)
            handleElvUI(item)
        end
        item.cooldownInSeconds = ability.cooldown
        item.charges = ability.charges
        if item.charges > 1 then
            item.chargeLabel:Show()
            item.chargeLabel:SetText(item.charges)
        else
            item.chargeLabel:Hide()
        end

        if ability.cdr and not ns:GetOption("hideInaccurateBadges") then
            item.warningbg:Show()
            item.warning:Show()
        else
            item.warningbg:Hide()
            item.warning:Hide()
        end
        item.icon:Show()

        sizeHistoryItem(item)
        -- Did the user opt in to showing this ability?
        if not ns:GetOption("show_"..ability.id) or
           ability.hideAbility or
           (ability.name == 'Stoneform' and char:getSpec() == 268 and not ns:GetOption('allowBrewmasterStoneform')) then
            item:Hide()
        else
            item:Show()
        end
    end

    -- If there are any abilities tracked that are no longer trackable (e.g.,
    -- the player changed spec, group changed, new external interferes, etc.)
    for name, item in pairs(row.items) do
        if not abilities[name] then
            releaseHistoryItem(item)
            row.items[name] = nil
        end
    end

    -- Adjust layout based on the icons surviving the previous purge
    local i = 0
    local wrap = ns:GetOption('wrapIcons')
    for name, item in pairs(row.items) do
        local xoff, yoff = offsets(dir, i, (iconSize + iconSpacing))
        item:ClearAllPoints()
        if dir == 'LEFT' or dir == 'RIGHT' then
            item:SetPoint('TOP'..antidir, row, 'TOP'..antidir, xoff, yoff)
        elseif dir == 'UP' or dir == 'DOWN' then
            item:SetPoint(antidir..'LEFT', row, antidir..'LEFT', xoff, yoff)
        end
        if item:IsShown() then i = i + 1 end
    end

    if dir == "LEFT" or dir == "RIGHT" then
        row:SetSize(math.min(i, wrap)*(iconSize+iconSpacing) - iconSpacing,
            (math.floor((i-1)/wrap)+1) * (iconSize + iconSpacing))
    else
        row:SetSize((math.floor((i-1)/wrap)+1) * (iconSize + iconSpacing),
            math.min(i, wrap)*(iconSize+iconSpacing) - iconSpacing)
    end

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
    local historyTrayScale = ns:GetOption('historyTrayScale')
    local iconSize = ns:GetOption('iconSize')*historyTrayScale
    local textSize = ns:GetOption('textSize')*historyTrayScale
    local iconSpacing = ns:GetOption('iconSpacing')
    local dir = ns.growthDirections[ns:GetOption('growthDirection')]
    local antidir = ns.antiDirection[dir]

    local maxHistory = ns:GetOption('maxHistoryTrayItems')
    local wrap = ns:GetOption('wrapIcons')
    for i=1, math.max(maxHistory, #row.items) do
        local item = row.items[i]
        if i > maxHistory then   -- maxHistory was reduced by user options
            releaseHistoryItem(item)
            row.items[i] = nil
        else
            if not item then   -- maxHistory was increased by the user (or is first call)
                row.items[i] = allocHistoryItem(tracker.historyTray, true)
                item = row.items[i]
            end
            sizeHistoryItem(item)
            handleElvUI(item)
            -- item at index 1 is the oldest
            local xoff, yoff = offsets(dir, (maxHistory - i), (iconSize + iconSpacing))
            item:ClearAllPoints()
            if dir == 'LEFT' or dir == 'RIGHT' then
                item:SetPoint('TOP'..antidir, row, 'TOP'..antidir, xoff, yoff)
            elseif dir == 'UP' or dir == 'DOWN' then
                item:SetPoint(antidir..'LEFT', row, antidir..'LEFT', xoff, yoff)
            end
            --item:SetPoint(antidir, row, antidir, xoff, yoff)
            ns:showDebugVisual(item)
            ns:showDebugVisual(item.icon)
        end
    end

    if dir == "LEFT" or dir == "RIGHT" then
        row:SetSize(math.min(maxHistory, wrap)*(iconSize+iconSpacing) - iconSpacing,
            (math.floor((maxHistory-1)/wrap) + 1) * (iconSize+iconSpacing))
    else
        row:SetSize((math.floor((maxHistory-1)/wrap) + 1) * (iconSize+iconSpacing),
            math.min(maxHistory, wrap)*(iconSize+iconSpacing) - iconSpacing)
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
    local trackedSlots = ns:getTrackedSlots()

    for slot, _ in pairs(trackedSlots) do
        if not ns.trackerUI[slot] then
            ns.trackerUI[slot] = ns:allocTrackerUIForSlot(slot)
        end
        local ui = ns.trackerUI[slot]

        ns:updateTrackerUIBySlot(slot)

        -- XXX: TODO: hack to clear history tray while history items/cooldowns are being
        -- folded into Character(). updateHistoryTray() should ask Character() what
        -- historyItems it should show in updateTrackerUIByIndex()
        for _, item in pairs(ui.historyTray.items) do
            clearHistoryItem(item)
        end

        local frame = ns:slotToFrame(slot)
        if ns:addonIsActive() and
           frame and frame:IsVisible() and
           (slot ~= 'player' or not ns:GetOption('hidePersonalCDs')) then
            ui:Show()
        else
            ui:Hide()
        end
    end

    -- Get rid of any UIs no longer tracked
    for slot, ui in pairs(ns.trackerUI) do
        if not trackedSlots[slot] then
            -- XXX: TODO: Should do some more teardown/releasing here
            ui:Hide()
        end
    end
end



function ns:updateTrackerUIBySlot(slot)
    ns:printDebug(ns.LOGTYPE.UI, ns.LOGLEVEL.Normal,
        "Updating TrackerUI for slot="..tostring(slot))
    local tracker = ns.trackerUI[slot]
    local guid, char = ns:getTrackedCharacterBySlot(slot)
    local iconSize = ns:GetOption('iconSize')
    local iconSpacing = ns:GetOption('iconSpacing')
    local textSize = ns:GetOption('textSize')
    local dir = ns.growthDirections[ns:GetOption('growthDirection')]

    -- Position UI next to frames
    local frame = ns:slotToFrame(slot)
    if frame then
        local xspacing, yspacing = ns:GetOption("adjustX"), ns:GetOption("adjustY")
        tracker:ClearAllPoints()
        tracker:SetPoint(ns.anchorPoints[ns:GetOption('anchorFrom')],
            frame, ns.anchorPoints[ns:GetOption('anchorTo')],
            xspacing, yspacing)
    end

    tracker.bg:SetAllPoints(tracker)
    tracker.bg:SetColorTexture(0,0,0,0.4)
    ns:showDebugVisual(tracker.bg)

    tracker.specLabel:SetPoint("BOTTOMRIGHT", tracker, "TOPRIGHT", 0, 0)
    tracker.specLabel:SetFont(tracker.specLabel:GetFont(), textSize, "OUTLINE")
    local spec = char and char:getSpecString() or nil
    tracker.specLabel:SetText(spec)
    ns:showDebugVisual(tracker.specLabel)

    tracker.slotLabel:SetPoint("TOPLEFT", tracker, "TOPRIGHT", 3, -3)
    tracker.slotLabel:SetFont(tracker.slotLabel:GetFont(), 12, "OUTLINE")
    local frameUnit = frame and (frame.unit or frame.raidid or "nil")
    tracker.slotLabel:SetText("["..slot.."] "..tostring(frameUnit))
    ns:showDebugVisual(tracker.slotLabel)
    tracker.slotLabel.bg:SetAllPoints(tracker.slotLabel)
    ns:showDebugVisual(tracker.slotLabel.bg)

    updateStaticRow(slot)
    updateHistoryTray(slot)

    -- Resize the whole tracker UI to fit the two new elements
    if dir == "LEFT" or dir == "RIGHT" then
        tracker:SetWidth(math.max(tracker.staticRow:GetWidth(), tracker.historyTray:GetWidth()) + iconSpacing)
        tracker:SetHeight(tracker.staticRow:GetHeight() + tracker.historyTray:GetHeight() + iconSpacing)
    else
        tracker:SetWidth(tracker.staticRow:GetWidth() + tracker.historyTray:GetWidth() + iconSpacing)
        tracker:SetHeight(math.max(tracker.staticRow:GetHeight(), tracker.historyTray:GetHeight()) + iconSpacing)

    end

    -- Position the history tray relative to the static row
    local dir = ns.growthDirections[ns:GetOption('growthDirection')]
    local antidir = ns.antiDirection[dir]
    local historyTrayScale = ns:GetOption('historyTrayScale')
    tracker.staticRow:ClearAllPoints()
    tracker.historyTray:ClearAllPoints()
    if dir == "LEFT" then
        tracker.staticRow:SetPoint('TOP'..antidir, tracker)
        tracker.historyTray:SetPoint('TOPRIGHT', tracker.staticRow, 'BOTTOMRIGHT',
            0, -iconSpacing*historyTrayScale)
    elseif dir == "RIGHT" then
        tracker.staticRow:SetPoint('TOP'..antidir, tracker)
        tracker.historyTray:SetPoint('TOPLEFT', tracker.staticRow,
            'BOTTOMLEFT', 0, -iconSpacing*historyTrayScale)
    elseif dir == "UP" then
        tracker.staticRow:SetPoint(antidir..'LEFT', tracker)
        tracker.historyTray:SetPoint('BOTTOMLEFT', tracker.staticRow, 'BOTTOMRIGHT',
            iconSpacing*historyTrayScale, 0)
    elseif dir == "DOWN" then
        tracker.staticRow:SetPoint(antidir..'LEFT', tracker)
        tracker.historyTray:SetPoint('TOPLEFT', tracker.staticRow, 'TOPRIGHT',
            iconSpacing*historyTrayScale, 0)
    end

    if Masque and masqueGroup then
        masqueGroup:ReSkin(true)
    end
end



function ns:allocTrackerUIForSlot(slot)
    ns:printDebug(ns.LOGTYPE.UI, ns.LOGLEVEL.Normal,
        "Allocating TrackerUI for slot="..tostring(slot))
    local tracker = framePool:Acquire()
    tracker:SetParent(UIParent)
    tracker.slot = slot

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
    tracker.slotLabel = numberFontNormalSmallPool:Acquire()
    tracker.slotLabel:SetParent(tracker)
    tracker.slotLabel:SetDrawLayer('OVERLAY')
    tracker.slotLabel:SetTextColor(1,1,1)

    tracker.slotLabel.bg = texturePool:Acquire()
    tracker.slotLabel.bg:SetParent(tracker)
    tracker.slotLabel.bg:SetDrawLayer('ARTWORK', 0)
    tracker.slotLabel.bg:SetAllPoints()
    tracker.slotLabel.bg:SetColorTexture(1,0,0)

    -- The static cooldown tracker is just an empty list to be filled with icons
    tracker.staticRow = framePool:Acquire()
    tracker.staticRow:SetParent(tracker)
    tracker.staticRow.items = {}

    -- The history tray
    tracker.historyTray = framePool:Acquire()
    tracker.historyTray:SetParent(tracker)
    tracker.historyTray.items = {}

    return tracker
end



function ns:allocTrackerUI()
    ns:printDebug(ns.LOGTYPE.UI, ns.LOGLEVEL.Normal, "Allocating TrackerUI")
    for slot, _ in pairs(ns:getTrackedSlots()) do
        local tracker = allocTrackerUIForSlot(slot)
        ns.trackerUI[slot] = tracker
    end
end
