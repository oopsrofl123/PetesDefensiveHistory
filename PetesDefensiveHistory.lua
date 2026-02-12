-- Add this aura instance to the tracked list of actives on this player.
--
-- IMPORTANT! Save the icon's texture at the instant the aura is applied
-- in case another buff overwrites it later.
function trackActiveDefensive(slot, auraInstanceID, defensiveIcon)
    printDebug('auraInstanceID=' .. auraInstanceID ..
        ' added to ' .. slot ..
        ': currently tracking ' .. #activeDefensives[slot] ..
        ' other active defensives')

    defensive = {
        slot = slot,
        auraInstanceID = auraInstanceID,
        secretTexture = defensiveIcon:GetTexture(),
        startTime = GetTime(),
        endTime = GetTime() + INFINITY,
        numUpdates = 0                 -- how many times has this aura been in the aurasUpdated list?
    }

    activeDefensives[slot][auraInstanceID] = defensive

    return defensive
end



--------------------------------------------------------------------------------------
-- This frame handles all of the logic that tracks and identifies defensive abilities.
--------------------------------------------------------------------------------------
local handler = CreateFrame("Frame")
handler:RegisterEvent("UNIT_AURA")
handler:SetScript("OnEvent", function(self, event, unitTarget, updateInfo)
    -- Ensure unitTarget is a recognized slot. This event is called for nameplates among other things.
    if not allSlots[unitTarget] then return end

    -- empty table to make #(.) work when no auras are added. same for other tables.
    aurasAdded = updateInfo['addedAuras'] or {}
    aurasRemoved = updateInfo['removedAuraInstanceIDs'] or {}

    -- XXX: Update: might be able to detect VDH fiery brand if it updates on spreading.
    aurasUpdated = updateInfo['updatedAuraInstanceIDs'] or {}

    -- Currently active defensive buffs for this slot
    active = activeDefensives[unitTarget]

    -- Way too verbose even for testing and also not very useful since
    -- aura instance IDs aren't printed.
    --printDebug('UNIT_AURA: unitTarget=' .. unitTarget ..
        --' #aurasAdded=' .. #aurasAdded ..
        --', #aurasUpdated=' .. #aurasUpdated ..
        --', #aurasRemoved=' .. #aurasRemoved) 

    -- aurasAdded is a list of data structures
    for _, v in pairs(aurasAdded) do
        local this_cdb = slotToPartyFrame(unitTarget).CenterDefensiveBuff
        if this_cdb.auraInstanceID == v.auraInstanceID then
            local x = trackActiveDefensive(unitTarget, v.auraInstanceID, this_cdb.icon)
            print(x.secretTexture)
        end
    end          

    -- unlike aurasAdded, this is just a list of updated IDs
    for _, auraInstanceID in pairs(aurasUpdated) do
        defBuff = active[auraInstanceID]
        if defBuff then
            printDebug("slot=" .. unitTarget .. ": updating " .. defBuff.auraInstanceID)
            defBuff.numUpdates = defBuff.numUpdates + 1
        end
    end

    -- unlike aurasAdded, this is just a list of removed IDs
    for _, auraInstanceID in pairs(aurasRemoved) do
        -- if this aura instance ID is being tracked for this player, then it was a defensive
        -- and is now over. Insert it into the history tracker.
        defBuff = active[auraInstanceID]
        if defBuff then
            defBuff.endTime = GetTime()
            defBuff.duration = defBuff.endTime - defBuff.startTime

            addCompletedBuffToHistory(unitTarget, defBuff)

            -- This buff is no longer an active defensive. Clear the memory or else active will
            -- accumulate every defensive buff this unit ever gained.
            active[auraInstanceID] = nil
        end
    end
end)





--------------------------------------------------------------------------------------
-- Just handle initialization and group roster updates.
--------------------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("GROUP_ROSTER_UPDATE")
loader:SetScript("OnEvent", function(self, event)
    printDebug(event)
    -- PLAYER_ENTERING_WORLD fires when loading into an instance
    if not pdhInitialized and event == "PLAYER_ENTERING_WORLD" then
        -- Can't initialize in addon load code due to the need to anchor to party frames
        allocHistoryGrid()
		allocPdhGroupSolutionUI()
    end

    -- GROUP_ROSTER_UPDATE or PLAYER_ENTERING_WORLD
    for slot, _ in pairs(allSlots) do
        if UnitExists(slot) then
            showRow(slot)
		else
			clearRow(historyRows[slot])
        end
    end
end)



SLASH_PDH1 = "/pdh"
-- Open the config panel
-- SlashCmdList.PDH = function() Settings.OpenToCategory(optionsCategory:GetID()) end

-- Open the solution UI
SlashCmdList.PDH = function() groupSolutionUIFrame:Show() end
