-- get addon namespace
local addonName, ns = ...

-- XXX: Below just describes the history tray for non-inferred abilities. Old
-- but still somewhat informative.
--
-- provides
--      1. initialization
--      2. add a buff
--      3. update per row (maybe?)
--      4. update full grid (e.g., on group roster change)
-- for the history tracker and static inferred cooldown rows.
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




-- Copy history item in from into to, clobbering the original contents of to.
local function shiftHistoryItem(from, to)
    to.startTime = from.startTime
    to.maxCD = from.maxCD
    to.icon:SetTexture(from.icon:GetTexture())

    -- Preserve visibility of each visual element
    ns:showIfShown(from, to)
    ns:showIfShown(from.timer, to.timer)
    ns:showIfShown(from.icon, to.icon)
end



-- Initialize a history item with blank values and hide it. Do not perform
-- allocation or do potentially unsafe things like move or reanchor elements.
local function clearHistoryItem(item)
    -- Local data per historyItem
    item.startTime = nil
    item.maxCD = nil

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
    local row = ns.historyRows[slot]

    -- Don't do anything if the user disabled the history tray
    if ns:GetOption('disableHistoryTray') then return end

    ns:printDebug("aura instance ID " .. buff.auraInstanceId ..
        " added to history tray " .. slot .. " after " .. buff.duration .. "s")

    -- Empty the youngest history slot
    shiftHistoryLeftFrom(row.historyItems)
    
    -- Now that space has been made, add this ability to the tracker
    item = row.historyItems[ns.MAX_HISTORY]
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
    local frameName = addonName .. "_" .. slot .. "_" .. index
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
                    self:Hide()  -- hide the whole icon+timer
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

            -- 1. update the cooldown timer text
            if self.numQueued > 0 then
                local untilAvailable = self.startTime + self.cooldown - now
                if untilAvailable > 0 then
                    self.swipeTexture.timer:SetFormattedText("%.0f", untilAvailable)
                else
                    -- 2. monitor for cooldown completions.  This CD is over. Are there more?
                    -- a charge just finished, so this cooldown is available. remove the swipe.
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

        -- Show a spell tooltip on the historyItem
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
function ns:updateStaticRow(slot)
    local row = ns.staticRows[slot]

    local abilities = ns.groupCDs[slot].castableAbilities
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
                -- XXX: TODO: can't figure out how to get cooldown frames to not hide
                -- themselves. oh well. i might need a fully separate frame overlay for
                -- charges if i want them to display when the swipe frame self-hides
                --newItem.swipeTexture:Show()
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
    for name, historyItem in pairs(row.items) do
        if not abilities[name] then
            -- XXX: TODO: WARNING! this leaks frames! need a frame pool at some point
            -- since frames cannot be deallocated.
            row.items[name]:ClearAllPoints()
            row.items[name]:Hide()
        end
    end

    -- Adjust layout based on the icons surviving the previous purge
    local i = 0
    local iconSize = ns:GetOption('iconSize')
    local iconSpacing = ns:GetOption('iconSpacing')
    row:SetSize(row:GetWidth(), iconSize)
    row:SetPoint("TOPRIGHT", ns:slotToPartyFrame(slot), "TOPLEFT", -ns.SPACING_FROM_FRAMES, 0)
    for name, historyItem in pairs(row.items) do
        historyItem:SetPoint("RIGHT", row, "RIGHT", -(iconSize + iconSpacing)*i, 0)
        if historyItem:IsShown() then
            i = i + 1
        end
    end

    if ns:GetOption('disableInference') then
        -- hide the whole row unless visual debugging is turned on
        ns:showDebugVisual(row)
    else
        row:Show()
    end
end



local function allocStaticRow(slot)
    local row = CreateFrame("Frame", addonName .. "StaticRow" .. slot, UIParent)
    row:SetSize(200, ns:GetOption('iconSize')+2)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0,0,0,0.4)
    ns:showDebugVisual(row.bg)

    row:SetPoint("TOPRIGHT", ns:slotToPartyFrame(slot), "TOPLEFT", -ns.SPACING_FROM_FRAMES, 0)
    row:Show()

    row.items = {}

    return row
end



function ns:setDataHistoryTrayRow(slot, specId, playerName)
    local row = ns.historyRows[slot]
    ns:clearRow(row)
    row.specId = specId
    row.specText:SetText(ns:specIdToString(specId))
    ns:showDebugVisual(row.specText)
    row.playerName = playerName
end



-- Update a single row when visual options or party members change.
function ns:updateHistoryTrayRow(slot, specId, playerName)
    local row = ns.historyRows[slot]
    ns:printDebug("updateHistoryTrayRow(" .. slot .. ")")

    local iconSize = ns:GetOption('iconSize')
    local textSize = ns:GetOption('textSize')
    local iconSpacing = ns:GetOption('iconSpacing')

    -- Position row next to Blizzard frames
    row:SetSize(ns.MAX_HISTORY*iconSize + (ns.MAX_HISTORY-1)*iconSpacing, iconSize)
    row:SetPoint("BOTTOMRIGHT", ns:slotToPartyFrame(slot), "BOTTOMLEFT", -ns.SPACING_FROM_FRAMES, 0)

    row.specText:SetPoint("BOTTOMRIGHT", row, "TOPRIGHT", 0, 0)
    row.specText:SetFont(row.specText:GetFont(), textSize, "OUTLINE")
    row.cpfMappingText:SetPoint("RIGHT", row, "LEFT", 0, 0)
    row.cpfMappingText:SetFont(row.cpfMappingText:GetFont(), textSize, "OUTLINE")

    for i=1,ns.MAX_HISTORY do
        local historyItem = row.historyItems[i]
        sizeHistoryItem(historyItem)
        -- historyItems are statically positioned with index 1 being the oldest
        -- historyItem and MAX_HISTORY being the newest added item. Different
        -- party frame layouts (e.g. anchored-on-right) can be accommodated
        -- without changing any logic - only updating this layout.
        historyItem:SetPoint("LEFT", row, "LEFT", (i-1)*(iconSize + iconSpacing), 0)
    end

    if ns:GetOption('disableHistoryTray') then
        -- hide the whole row unless visual debugging is turned on
        ns:showDebugVisual(row)
    else
        row:Show()
    end
end



-- Create a row for a specific slot. Anchor the row to the relevant party frame
-- and allocate a blank set of history items.
local function allocHistoryTrayRow(slot)
    local row = CreateFrame("Frame", addonName .. "Row" .. slot, UIParent)
    row.slot = slot

    -- Debug mode transparent background
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    -- Debug mode text showing the detected class/spec
    row.specText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.specText:SetTextColor(1,1,1)

    -- Debug mode text showing the CompactPartyFrameMember..i mapping
    row.cpfMappingText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.cpfMappingText:SetTextColor(1,1,1)

    -- Create all historyItems for this row
    -- Do not do this in clearRow() since historyItems contain frames. These will
    -- be allocated here and the top-level data will be immutable.
    row.historyItems = {}
    for i=1,ns.MAX_HISTORY do
        row.historyItems[i] = allocHistoryItem(row, slot, i, true)
    end

    return ns:clearRow(row)
end



-- Frames are allocated only once - on creation. The only reason to allocate new
-- frames is increasing MAX_HISTORY. Rather than handle that, just force the user
-- to /reload.
function ns:allocHistoryGrid()
    for slot, _ in pairs(ns.allSlots) do
        -- Fallback mode: history tray
        ns.historyRows[slot] = allocHistoryTrayRow(slot)
        ns:updateHistoryTrayRow(slot)

        -- Inferred abilities: omniCD-like cooldown tracking
        ns.staticRows[slot] = allocStaticRow(slot)
    end
end
