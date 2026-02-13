-- Return a tuple of flags for this auraInstanceId:
--   (isImportant, isBigDefensive, isExternalDefensive)
function getFilterFlagsForAuraInstanceId(slot, auraInstanceId)
    return
        tablecontains(C_UnitAuras.GetUnitAuraInstanceIDs(slot, "HELPFUL|IMPORTANT"), auraInstanceId),
        tablecontains(C_UnitAuras.GetUnitAuraInstanceIDs(slot, "HELPFUL|BIG_DEFENSIVE"), auraInstanceId),
        tablecontains(C_UnitAuras.GetUnitAuraInstanceIDs(slot, "HELPFUL|EXTERNAL_DEFENSIVE"), auraInstanceId),
        tablecontains(C_UnitAuras.GetUnitAuraInstanceIDs(slot, "HELPFUL|RAID_IN_COMBAT"), auraInstanceId)
end



-- Add this aura instance to the tracked list of actives on this player.
--
-- IMPORTANT! Save the icon's texture at the instant the aura is applied
-- in case another buff overwrites it later.
function trackActiveDefensive(slot, auraInstanceID, defensiveIcon)
    isImportant, isBigDefensive, isExternal = getFilterFlagsForAuraInstanceId(slot, auraInstanceID)

    printDebug('auraInstanceID=' .. auraInstanceID ..
        ' (important=' .. tostring(isImportant) ..
        ', bigdef=' .. tostring(isBigDefensive) ..
        ', external=' .. tostring(isExternal) ..
        ') added to ' .. slot ..
        ': currently tracking ' .. #activeDefensives[slot] ..
        ' other active defensives')

    defensive = {
        slot = slot,
        auraInstanceID = auraInstanceID,
        secretTexture = defensiveIcon:GetTexture(),
        startTime = GetTime(),
        endTime = GetTime() + INFINITY,
        isImportant = isImportant,
        isBigDefensive = isBigDefensive,
        isExternal = isExternal,
        numUpdates = 0                 -- how many times has this aura been in the aurasUpdated list?
    }

    activeDefensives[slot][auraInstanceID] = defensive

    return defensive
end





-- XXX: DELETEME: TESTING RANDOM STUFF
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetPoint("CENTER")
        f:SetSize(ICON_SIZE, ICON_SIZE)

        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetAllPoints()
        f.icon:SetTexture(DEFAULT_ICON)
        f:Show()
-- XXX: DELETEME: TESTING RANDOM STUFF





--------------------------------------------------------------------------------------
-- This frame is responsible for tracking when party members cast abilities.
--------------------------------------------------------------------------------------
local castHandler = CreateFrame("Frame", "PetesDefensiveHistoryCastHandler")
castHandler:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
castHandler:SetScript("OnEvent", function(self, event, unitTarget, castGUID, spellID, castBarID)
    -- unitTarget is actually the caster of the spell, confusingly
    if not allSlots[unitTarget] then return end

    -- mask secrets to avoid errors. sets nil if secret
    spellId = maskSecret(spellId)
    castGUID = maskSecret(castGUID)
    castBarID = maskSecret(castBarID)

    printDebug("UNIT_SPELLCAST_SUCCEEDED(" .. unitTarget .. ", " ..
        tostring(castGUID) .. ", " .. tostring(spellID) ..
        ", " .. tostring(castBarID) .. ")")
        
    -- loathe to use spellId since it's secret for all party members except the
    -- person who cast it. don't want to get into debugging behavior that changes
    -- between group members.. there is already enough of that in the different
    -- times that the same event is handled on different clients.
    castHistory[unitTarget]:push({ time=GetTime(), spellId=spellId })

    -- Wild spam, should use multiple debug levels but too lazy
    if DEBUG_MESSAGES and unitTarget == "player" then
        castHistory[unitTarget]:print()
    end
end)



--------------------------------------------------------------------------------------
-- This frame is responsible for handling events about auras being applied, updated
-- or removed.
--------------------------------------------------------------------------------------
local auraHandler = CreateFrame("Frame", "PetesDefensiveHistoryAuraHandler")
auraHandler:RegisterEvent("UNIT_AURA")
auraHandler:SetScript("OnEvent", function(self, event, unitTarget, updateInfo)
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
    -- aura instance IDs aren't printed unless we unpack the tables.
    --printDebug('UNIT_AURA: unitTarget=' .. unitTarget ..
        --' #aurasAdded=' .. #aurasAdded ..
        --', #aurasUpdated=' .. #aurasUpdated ..
        --', #aurasRemoved=' .. #aurasRemoved) 

    -- aurasAdded is a list of data structures
    for _, v in pairs(aurasAdded) do
if unitTarget == "player" then
    print(v.auraInstanceID)
--printer(v)

imp, big, ext, ric = getFilterFlagsForAuraInstanceId(unitTarget, v.auraInstanceID)
    -- 389539 sentinel
    --if v.spellId == 389539 then
    if imp then
print(imp, big, ext, ric, 'important')
        f.icon:SetTexture(v.icon)
    end
end
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
        for slot, _ in pairs(allSlots) do
            castHistory[slot] = fixedFIFO(MAX_CAST_HISTORY)
        end
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



-- Open the solution UI
SLASH_PDH1 = "/pdh"
-- Open the config panel
-- SlashCmdList.PDH = function() Settings.OpenToCategory(optionsCategory:GetID()) end
SlashCmdList.PDH = function() groupSolutionUIFrame:Show() end
