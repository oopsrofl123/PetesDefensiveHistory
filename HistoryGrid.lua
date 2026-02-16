-- get addon namespace
local addonName, ns = ...


-- generally: functions to do with HistoryItems should be local. callers entry
-- points should just be:
--      1. initialization
--      2. add a buff
--      3. update per row (maybe?)
--      4. update full grid (e.g., on group roster change)


-- Functions for building, updating, resetting and interacting with a grid
-- that tracks defensive history.
--
-- Grid architecture: the alternative (cleaner, IMO) architecture is a pool of
-- frames that is built up as needed based on the number of tracked history icons
-- for each player. The problem with the pool architecture is that it involves
-- reanchoring frames during combat, which is very iffy since Blizzard limits
-- some frame interactions in combat. The grid architecture requires more cumbersome
-- update logic (i.e., removing an old history icon involves shifting all icons
-- rather than just excising the old one), but allows a completely static frame
-- layout that can be created out of combat.
--
--
-- Data layout (not necessarily how the data appears on screen)
--
--                                     +---- index MAX_HISTORY is the most recent history item
--                                     |
--                                     V
--        ____________________________________
--         1       2       3       MAX_HISTORY   player  <---- each historyRow frame contains
--        ____________________________________                 data about that party member, like
--         ^       ^       ^                                   name, spec, known cds, etc.
--         |       |       |                     
--         +-------+-------+---- historyItems
--        ____________________________________
--         1       2       3       MAX_HISTORY   party1
--        ____________________________________      ^
--                                                  |
--  history rows keyed by "slot": player/partyX ----+




-- If any historyItem in row matches auraName, return its index. Returns
-- the oldest such index, needs updating to handle abilities with charges.
local function findAuraIndex(row, auraName)
    for i=1,ns.MAX_HISTORY do
        item = row.historyItems[i]
        if item.auraName and item.auraName == auraName then
            return i
        end
    end

    return nil
end



-- Copy history item in from into to, clobbering the original contents of to.
local function shiftHistoryItem(from, to)
    to.startTime = from.startTime
    to.endTime = from.endTime
    to.auraName = from.auraName
    to.duration = from.duration
    to.cooldown = from.cooldown
    to.numUpdates = from.numUpdates
    to.icon:SetTexture(from.icon:GetTexture())

    -- Preserve visibility of each visual element
    ns:showIfShown(from, to)
    ns:showIfShown(from.timer, to.timer)
    ns:showIfShown(from.icon, to.icon)
    -- swipe texture animations have to be restarted in addition to preserving
    -- visibility.
    ns:showIfShown(from.swipeTexture, to.swipeTexture)
    -- if the swipe texture is shown, then all of the relevant data is present
    if from.swipeTexture:IsShown() then
        CooldownFrame_Set(to.swipeTexture, to.startTime, to.cooldown, true)
    end
    to.inferredCD:SetText(to.cooldown)
    ns:showIfShown(from.inferredCD, to.inferredCD)
end



-- Initialize a history item with blank values and hide it. Do not perform
-- allocation or do potentially unsafe things like move or reanchor elements.
local function clearHistoryItem(item)
    -- Local data per historyItem
    item.startTime = nil
    item.endTime = nil
    -- For when auras can be guessed
    item.auraName = nil
    item.duration = nil
    item.cooldown = nil
    item.numUpdates = nil

    -- Initialize visuals
    item.icon:SetTexture(ns.DEFAULT_ICON)
    ns:showDebugVisual(item.icon)  -- show empty icons in debug mode

    item.timer:SetText("")
    item.timer:Hide()

    item.swipeTexture:Hide()

    item.inferredCD:SetText(tostring(item.cooldown))
    ns:showDebugVisual(item.inferredCD)

    ns:showDebugVisual(item)

    return item
end



-- Omit fromIndex to shift the whole history, leaving the "newest" slot open
-- IMPORTANT: the item at fromIndex is hidden since it is cleared. Callers
-- must re-:Show() if they want the item to be seen after this shift.
local function shiftHistoryLeftFrom(historyItems, fromIndex)
    fromIndex = fromIndex or ns.MAX_HISTORY
    for i=1,ns.MAX_HISTORY-1 do
        shiftHistoryItem(historyItems[i+1], historyItems[i])
    end
    clearHistoryItem(historyItems[fromIndex])
end



-- For deleting specific history items (e.g., when an ability can be identified and
-- we want to delete any previous instances of that ability.
-- fromIndex is not optional since there is no "natural" choice that corresponds to
-- reasonable behavior.
local function shiftHistoryRightFrom(historyItems, fromIndex)
    for i=fromIndex,2,-1 do
        shiftHistoryItem(historyItems[i-1], historyItems[i])
    end
    clearHistoryItem(historyItems[1]) 
end



function ns:addBuffToHistory(slot, buff)
    ns:printDebug("aura instance ID " .. buff.auraInstanceID ..
        " added to history tray " .. slot .. " after " .. buff.duration .. "s")

    if ns:isAbilityInferred(buff) then
        ns:printDebug("ERROR: adding inferred ability to history tray, should go to static tracker")
    end

    slot = buff.caster  -- for externals, might be updated by identify
    local row = ns.historyRows[slot]

    -- Empty the youngest history slot
    shiftHistoryLeftFrom(row.historyItems)
    
    -- Now that space has been made, add this ability to the tracker
    item = row.historyItems[ns.MAX_HISTORY]
    item.startTime = buff.startTime
    item.endTime = buff.endTime
    item.auraName = buff.auraName
    item.duration = buff.duration
    item.cooldown = buff.cooldown
    item.numUpdates = buff.numUpdates
    item.icon:SetTexture(buff.secretTexture)
    item.icon:Show()
    item.timer:Show()
    item:Show()
end



-- showRow() is called when a player in position `slot` exists in the party
function ns:showRow(row)
    local slot = row.slot

    ns:updateSlotToFrameMapping(slot)
	row:SetPoint("BOTTOMRIGHT", ns:slotToPartyFrame(slot), "BOTTOMLEFT", -2, 0)

    for key, item in pairs(row.historyItems) do
        item:Show()
    end
    row:Show()
end



-- Allocate a blank history item and allocate all of its subcomponents. The
-- history item and all subcomponents are :Hide()ed. Callers should :Show()
-- desired elements based on whether the ability represented by this history
-- item is known.
function allocHistoryItem(row, slot, index)
    local frameName = addonName .. "_" .. slot .. "_" .. index
    local f = CreateFrame("Frame", frameName, row)
    f.slot = slot

    f:SetSize(ns.ICON_SIZE, ns.ICON_SIZE)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()

    -- Count-up history mode timer
    f.timer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.timer:SetPoint("CENTER", f, 0, 0)
    f.timer:SetFont(f.timer:GetFont(), 15, "THICKOUTLINE")

    -- Single ability cooldown swipe
    f.swipeTexture = CreateFrame("Cooldown", frameName .. "_cooldownSwipe", f, "CooldownFrameTemplate")
    f.swipeTexture:SetAllPoints()

    -- For debugging
    f.inferredCD = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.inferredCD:SetPoint("TOP", f, "BOTTOM", 0, 0)
    f.inferredCD:SetFont(f.inferredCD:GetFont(), 15, "OUTLINE")

    -- Count-up timer script
    -- XXX: TODO: is there a better event than OnUpdate? This runs every frame
    f:SetScript("OnUpdate", function(self)
        if self.startTime and self.cooldown then
            local elapsed = GetTime()-self.startTime
            if elapsed <= self.cooldown then
                self.timer:SetFormattedText("%.0f", elapsed)
            else
                self.timer:SetText("")
            end
        else
            self.timer:SetText("")
        end
    end)

    return clearHistoryItem(f)
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

    --ns:showDebugVisual(row)
    row:Show()

    for i, item in pairs(row.historyItems) do
        row.historyItems[i] = clearHistoryItem(item)
    end

    return row
end



-- Create a row for a specific slot. Anchor the row to the relevant party frame
-- and allocate a blank set of history items.
local function allocRow(slot)
    local row = CreateFrame("Frame", addonName .. "Row" .. slot, UIParent)
    row.slot = slot

    -- Position next to Blizzard frames
    row:SetSize(ns.MAX_HISTORY*ns.ICON_SIZE + (ns.MAX_HISTORY-1)*ns.ICON_SPACING, ns.ICON_SIZE)
    row:SetPoint("BOTTOMRIGHT", ns:slotToPartyFrame(slot), "BOTTOMLEFT", -ns.SPACING_FROM_FRAMES, 0)

    -- Debug mode transparent background
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    -- Debug mode text showing the detected class/spec
    row.specText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.specText:SetPoint("BOTTOMRIGHT", row, "TOPRIGHT", 0, 0)
    row.specText:SetFont(row.specText:GetFont(), 15, "OUTLINE")

    -- Debug mode text showing the CompactPartyFrameMember..i mapping
    row.cpfMappingText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.cpfMappingText:SetPoint("RIGHT", row, "LEFT", 0, 0)
    row.cpfMappingText:SetFont(row.cpfMappingText:GetFont(), 15, "OUTLINE")

    -- Create all historyItems for this row
    -- Do not do this in clearRow() since historyItems contain frames. These will
    -- be allocated here and the top-level data will be immutable.
    row.historyItems = {}
    for i=1,ns.MAX_HISTORY do
        historyItem = allocHistoryItem(row, slot, i)
        -- historyItems are statically positioned with index 1 being the oldest
        -- historyItem and MAX_HISTORY being the newest added item. Different
        -- party frame layouts (e.g. anchored-on-right) can be accommodated
        -- without changing any logic - only updating this layout.
        historyItem:SetPoint("LEFT", row, "LEFT", (i-1)*(ns.ICON_SIZE+ns.ICON_SPACING), 0)
        row.historyItems[i] = historyItem
    end

    return ns:clearRow(row)
end



-- XXX: TODO: This function leaks frames, but it happens rarely enough that we
-- can live with it for a while.
function ns:updateStaticRows(slot, abilities)
    local row = ns.staticRows[slot]
    ns:printDebug("updateStaticRows(" .. slot .. ")")

    -- Add a new frame for each tracked cooldown
    for _, ability in pairs(abilities) do
        if not row.items[ability.name] then
            local newItem = allocHistoryItem(row, slot, ability.name)
            row.items[ability.name] = newItem
            if ability.iconId then
                newItem.icon:SetTexture(ability.iconId)
            end
            newItem:Show()
            newItem.icon:Show()
        end
    end

    -- If there are any abilities tracked that are no longer trackable (e.g.,
    -- the player changed spec, group changed, new external interferes, etc.)
    for name, historyItem in pairs(row.items) do
        if not abilities[name] then
            -- XXX: TODO: WARNING! this leaks frames! need a frame pool at some point
            -- since frames cannot be deallocated.
            row.items[name]:ClearAllPoints()
            row.items[name]:Hide()
            --row.items[name] = nil
        end
    end

    -- Adjust layout based on the icons surviving the previous purge
    local i = 0
    for name, historyItem in pairs(row.items) do
        historyItem:SetPoint("RIGHT", row, "RIGHT", -(ns.ICON_SIZE + ns.ICON_SPACING)*i, 0)
        if historyItem:IsShown() then
            i = i + 1
        end
    end

    row:Show()
end



-- Update a single row, e.g. when party members change. SOLVING a row (i.e.,
-- figuring out what cooldowns can and can't be guessed) shouldn't be done here
-- as it requires knowledge of all group cds (specifically external defensives).
function ns:updateRow(row, specId, playerName)
    ns:clearRow(row)
    row.specId = specId
    row.specText:SetText(ns:specIdToString(specId))
    ns:showDebugVisual(row.specText)
    row.playerName = playerName
end



local function allocStaticRow(slot)
    local row = CreateFrame("Frame", addonName .. "StaticRow" .. slot, UIParent)
    row:SetSize(200, ns.ICON_SIZE+2)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0,0,0,0.4)
    ns:showDebugVisual(row.bg)

    row:SetPoint("TOPRIGHT", ns:slotToPartyFrame(slot), "TOPLEFT", -ns.SPACING_FROM_FRAMES, 0)
    row:Show()

    row.items = {}

    return row
end



-- Frames are allocated only once - on creation. The only reason to allocate new
-- frames is increasing MAX_HISTORY. Rather than handle that, just force the user
-- to /reload.
function ns:allocHistoryGrid()
    for slot, _ in pairs(ns.allSlots) do
        -- Fallback mode: history tray
        ns.historyRows[slot] = allocRow(slot)

        -- Inferred abilities: omniCD-like cooldown tracking
        ns.staticRows[slot] = allocStaticRow(slot)
    end
end



-- XXX: TODO: This was meant to reset tracking data. Haven't used it in forever,
-- probably very broken.
function ns:reset()
    ns:printDebug("resetting")
    for slot, row in pairs(ns.historyRows) do
        ns:clearRow(row)
        if UnitExists(slot) then
            ns:printDebug("showing row for slot " .. slot)
            ns:showRow(row)
        else
            ns:printDebug("hiding row for slot " .. slot)
        end
    end
    ns:printDebug("done resetting")
end
