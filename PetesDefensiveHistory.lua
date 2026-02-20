-- get addon namespace
local addonName, ns = ...

local LibButtonGlow = LibStub("LibButtonGlowcustom")

local function isAuraHarmful(slot, auraInstanceId)
    -- could also filter for HARMFUL
    return not ns:tablecontains(C_UnitAuras.GetUnitAuraInstanceIDs(slot, "HELPFUL"), auraInstanceId)
end


-- Return a tuple of flags for this auraInstanceId:
--   (isImportant, isBigDefensive, isExternalDefensive, isRaidInCombat, isRaid)
local function getFilterFlagsForAuraInstanceId(slot, auraInstanceId)
    return
        ns:tablecontains(C_UnitAuras.GetUnitAuraInstanceIDs(slot, "HELPFUL|IMPORTANT"), auraInstanceId),
        ns:tablecontains(C_UnitAuras.GetUnitAuraInstanceIDs(slot, "HELPFUL|BIG_DEFENSIVE"), auraInstanceId),
        ns:tablecontains(C_UnitAuras.GetUnitAuraInstanceIDs(slot, "HELPFUL|EXTERNAL_DEFENSIVE"), auraInstanceId),
        ns:tablecontains(C_UnitAuras.GetUnitAuraInstanceIDs(slot, "HELPFUL|RAID"), auraInstanceId),
        ns:tablecontains(C_UnitAuras.GetUnitAuraInstanceIDs(slot, "HELPFUL|RAID_IN_COMBAT"), auraInstanceId)
end



-- Add this aura instance to the tracked list of actives on this player.
--
-- IMPORTANT! Save the icon's texture at the instant the aura is applied
-- in case another buff overwrites it later.
local function trackActiveBuff(slot, auraInstanceID, iconId, concurrentDebuffs)
    local isImportant, isBigDefensive, isExternal, isRaid, isRaidInCombat =
        getFilterFlagsForAuraInstanceId(slot, auraInstanceID)

    local timeNow = GetTime()

    ns:printDebug(string.format(
        'auraInstanceID=%d (imp=%d, big=%d, ext=%d, raid=%d, ric=%d) added to %s: currently tracking %d other active defensives',
        auraInstanceID, isImportant and 1 or 0,
        isBigDefensive and 1 or 0, isExternal and 1 or 0,
        isRaid and 1 or 0, isRaidInCombat and 1 or 0,
        slot, #ns.activeDefensives[slot])
    )

    ns:printDebug('timeNow='..timeNow..' building list of most recent successful casts for all slots..')
    closestCasts = {}
    for slot, castHistory in pairs(ns.castHistory) do
        closest = ns.INFINITY
        for _, cast in pairs(castHistory:items()) do
            if math.abs(cast.time - timeNow) < math.abs(closest - timeNow) then
                closest = cast.time
            end
        end
        closestCasts[slot] = closest
    end

    local defensive = {
        slot = slot,      -- this is the buff's target (which is the unit frame position it was witnessed on, hence slot
        caster = slot,    -- this is the buff's unknown caster. best guess for now: same as the slot
        auraInstanceID = auraInstanceID,
        --secretTexture = defensiveIcon:GetTexture(),
        secretTexture = iconId,
        startTime = timeNow,
        duration = 0,
        endTime = timeNow + ns.INFINITY,
        isImportant = isImportant,
        isBigDefensive = isBigDefensive,
        isExternal = isExternal,
        isRaid = isRaid,
        isRaidInCombat = isRaidInCombat,
        numUpdates = 0,                 -- how many times has this aura been in the aurasUpdated list?
        concurrentDebuffs = concurrentDebuffs or {},
        closestCasts = closestCasts,
        buffCertainOnFirstInference = false
    }

    ns.activeDefensives[slot][auraInstanceID] = defensive

    return defensive
end



-- Call this function when we are ready to fully accept whatever the best
-- inference was.
local function finalizeInference(buff, attempt)
    ns:printDebug(string.format(
        "|cff00CDCDFINAL INFERENCE (attempt=%d, time=%0.3f): [%s] cast [%s] at time [%0.3f]!|r",
            attempt, GetTime(), buff.caster, buff.name, buff.startTime))

    ns.cdTracker[buff.caster][buff.name] = buff.startTime
end



--------------------------------------------------------------------------------------
-- This frame is responsible for tracking when party members cast abilities.
--------------------------------------------------------------------------------------
local castHandler = CreateFrame("Frame", addonName .. "CastHandler")
castHandler:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
castHandler:SetScript("OnEvent", function(self, event, unitTarget, castGUID, spellID, castBarID)
    -- unitTarget is actually the caster of the spell, confusingly
    if not ns.allSlots[unitTarget] then return end

    -- mask secrets to avoid errors. sets nil if secret
    spellId = ns:maskSecret(spellId)
    castGUID = ns:maskSecret(castGUID)
    castBarID = ns:maskSecret(castBarID)

    ns:printDebug(string.format("UNIT_SPELLCAST_SUCCEEDED(%s, %s, %s, %s, %0.3f)",
        unitTarget, tostring(castGUID), tostring(spellID), tostring(castBarID), GetTime()))
        
    -- loathe to use spellId since it's secret for all party members except the
    -- person who cast it. don't want to get into debugging behavior that changes
    -- between group members.. there is already enough of that in the different
    -- times that the same event is handled on different clients.
    ns.castHistory[unitTarget]:push({ time=GetTime() }) --, spellId=issecretvalue(spellId) and -1 or spellId })
end)



--------------------------------------------------------------------------------------
-- This frame is responsible for handling events about auras being applied, updated
-- or removed.
--------------------------------------------------------------------------------------
local auraHandler = CreateFrame("Frame", addonName .. "AuraHandler")
auraHandler:RegisterEvent("UNIT_AURA")
auraHandler:SetScript("OnEvent", function(self, event, unitTarget, updateInfo)
    -- Ensure unitTarget is a recognized slot. This event is called for nameplates and others
    if not ns.allSlots[unitTarget] then return end

    -- empty table to make #(.) work when no auras are added. same for other tables.
    local aurasAdded = updateInfo['addedAuras'] or {}
    local aurasRemoved = updateInfo['removedAuraInstanceIDs'] or {}
    local aurasUpdated = updateInfo['updatedAuraInstanceIDs'] or {}

    -- Currently active defensive buffs for this slot
    local actives = ns.activeDefensives[unitTarget]

    -- Way too verbose even for testing and also not very useful since
    -- aura instance IDs aren't printed unless we unpack the tables.
    ns:printDebug(string.format('UNIT_AURA(time=%0.3f, slot=[%s], #aurasAdded=[%d], #aurasUpdated=[%d], #aurasRemoved=[%d])',
        GetTime(), unitTarget, #aurasAdded, #aurasUpdated, #aurasRemoved))

    -- Convenience mode for collecting data about buff rules. Show all buffs and
    -- debuffs added, including secret data that would not be available in
    -- real content
    if PetesDefensiveHistoryOptionsDb.dataMiningMode and unitTarget == "player" then
        print(string.format("DATA MINING: %d added, %d updated, %d removed",
            #aurasAdded, #aurasUpdated, #aurasRemoved))
        for _, v in pairs(aurasAdded) do
            print("DATA MINING: aura added ID=" .. v.auraInstanceID)
            if not issecretvalue(v.spellId) then
                ns.printer(v)
            end
        end
        print("DATA MINING: auras updated:")
        ns.printer(aurasUpdated)
        print("DATA MINING: auras removed:")
        ns.printer(aurasRemoved)
    end

    -- aurasAdded is a list of data structures unlike the other aura sets
    for _, v in pairs(aurasAdded) do
        local imp, big, ext, raid, ric = getFilterFlagsForAuraInstanceId(unitTarget, v.auraInstanceID)
        local harm = isAuraHarmful(unitTarget, v.auraInstanceID)

        ns:printDebug("ADDED BUFF (not filtered imp|big|ext): " ..
            v.auraInstanceID, imp, big, ext, raid, ric, harm)
        -- the abilities we handle are helpfuls that are either important, big or externals
        if not harm and (imp or big or ext) then
            -- get all of the debuff auras added in this event
            local debuffs = {}
            for _, v in pairs(aurasAdded) do
                if isAuraHarmful(unitTarget, v.auraInstanceID) then
                    table.insert(debuffs, v.auraInstanceID)
                end
            end

            local buff = trackActiveBuff(unitTarget, v.auraInstanceID, v.icon, debuffs)
            -- attempt instant identification
            if ns:inferAbility(unitTarget, buff, false) then
                if buff.certainOnFirstInference then
                    finalizeInference(buff, 1)
                end
                -- IDable abilities go to the static tracker
                local cd = ns.staticRows[buff.caster].items[buff.name]
                cd.swipeTexture:Hide()
                LibButtonGlow.ShowOverlayGlow(cd)
            end
        end
    end

    -- unlike aurasAdded, this is just a list of updated IDs
    for _, auraInstanceID in pairs(aurasUpdated) do
        buff = actives[auraInstanceID]
        if buff then
            ns:printDebug("slot=" .. unitTarget .. ": updating " .. buff.auraInstanceID)
            buff.numUpdates = buff.numUpdates + 1
        end
    end

    -- unlike aurasAdded, this is just a list of removed IDs
    for _, auraInstanceID in pairs(aurasRemoved) do
        -- if this aura instance ID is being tracked for this player, then it was a defensive
        -- and is now over. Insert it into the history tracker.
        buff = actives[auraInstanceID]
        if buff then
            buff.endTime = GetTime()
            buff.duration = buff.endTime - buff.startTime

            -- Try inference at expiration if it failed before or if the ability is
            -- flagged as uncertain on the first inference. The latter allows some
            -- interesting logic/confidence layers.
            if not ns:isAbilityInferred(buff) or not buff.certainOnFirstInference then
                if ns:inferAbility(unitTarget, buff, true) then
                    finalizeInference(buff, 2)
                end
            end

            if ns:isAbilityInferred(buff) then
                -- IDable abilities go to the static tracker
                local cd = ns.staticRows[buff.caster].items[buff.name]
                cd.swipeTexture:SetCooldown(buff.startTime, buff.cooldown)
                cd.swipeTexture:Show()
                cd.startTime = buff.startTime
                cd.cooldown = buff.cooldown
                -- Support the activated buff being different from the cooldown tracker
                cd = ns.staticRows[buff.caster].items[buff.activeBuff or buff.name]
                LibButtonGlow.HideOverlayGlow(cd)
            else
                -- This was the last chance at IDing. So if it's still non-IDable,
                -- go to the fallback history tray
                ns:addBuffToHistory(unitTarget, buff)
            end

            -- allow garbage collection
            actives[auraInstanceID] = nil
        end
    end
end)



--------------------------------------------------------------------------------------
-- Just handle initialization and group roster updates.
--------------------------------------------------------------------------------------
local loader = CreateFrame("Frame", addonName .. "Loader")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("GROUP_ROSTER_UPDATE")
loader:SetScript("OnEvent", function(self, event)
    ns:printDebug(event)

    -- PLAYER_ENTERING_WORLD fires when loading into an instance
    if event == "PLAYER_ENTERING_WORLD" then
        -- now frame allocation and data structure setup is durig addon readin
    end

    -- GROUP_ROSTER_UPDATE or PLAYER_ENTERING_WORLD
    -- Only handle the fallback history tray here. The static cooldown row is
    -- handled by the LibSpec callback when spec is detected.
    for slot, _ in pairs(ns.allSlots) do
        local row = ns.historyRows[slot]

        -- account for the fact that LibSpec also fires on GROUP_ROSTER_UPDATE
        -- and can either come before or after this event.
        if UnitExists(slot) then
            if UnitName(slot) ~= row.playerName then
                -- this handler was called before LibSpec
                ns:setDataHistoryTrayRow(slot, nil, UnitName(slot))
                ns:updateHistoryTrayRow(slot)
            else
                -- this handler was called after LibSpec. nothing to do
            end
        else
            ns:clearRow(row)
            ns:showDebugVisual(row)
        end
    end
end)


-- Addons should be loaded after all blizzard frames, so can allocate everything now.
ns:allocHistoryGrid()
for slot, _ in pairs(ns.allSlots) do
    ns.castHistory[slot] = ns:fixedFIFO(ns.MAX_CAST_HISTORY)
end
ns.groupSolutionUI = ns:allocGroupSolutionUI()

-- Open the solution UI
SLASH_PDH1 = "/pdh"
-- Open the config panel
-- SlashCmdList.PDH = function() Settings.OpenToCategory(ns.optionsCategory:GetID()) end
SlashCmdList.PDH = function() ns.groupSolutionUI:Show() end
