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
local function trackActiveBuff(slot, auraInstanceID, iconId, concurrentBuffs, concurrentDebuffs)
    local isImportant, isBigDefensive, isExternal, isRaid, isRaidInCombat =
        getFilterFlagsForAuraInstanceId(slot, auraInstanceID)

    local timeNow = GetTime()

    ns:printDebug(string.format(
        'auraInstanceID=%d (imp=%d, big=%d, ext=%d, raid=%d, ric=%d) added to %s: currently tracking %d other active abilities',
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

    local buff = {
        inference = 0,    -- counter tracking how many times this buff has been through inferAbility()
        ability = nil,    -- the ability that created this buff
        certain = false,  -- is the buff <-> ability assignment certain?
        slot = slot,      -- this is the buff's target (which is the unit frame position it was witnessed on, hence slot)
        auraInstanceID = auraInstanceID,
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
        concurrentBuffs = concurrentBuffs or {},
        concurrentDebuffs = concurrentDebuffs or {},
        closestCasts = closestCasts
    }

    ns.activeDefensives[slot][auraInstanceID] = buff

    return buff
end



-- Call this function when we are ready to fully accept whatever the best
-- inference was.
local function finalizeInference(buff, ability)
    if not buff.certain then
        print(string.format(
            "WARNING: finalizing an uncertain inference (ability=[%s], caster=[%s], target=[%s])!",
            ability.name, ability.caster, buff.slot))
    end

    ns:printDebug(string.format(
        "|cff00CDCDFINAL INFERENCE (attempt=%d, time=%0.3f): [%s] cast [%s] at time [%0.3f]!|r",
            buff.inference, GetTime(), ability.caster, ability.name, buff.startTime))

    ns.cdTracker[ability.caster][ability.name] = buff.startTime
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
        
    ns.castHistory[unitTarget]:push({ time=GetTime() })
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
            -- get all of the buff and debuff auras added in this event
            local buffs = {}
            local debuffs = {}
            for _, x in pairs(aurasAdded) do
                if x.auraInstanceID ~= v.auraInstanceID then
                    if isAuraHarmful(unitTarget, x.auraInstanceID) then
                        table.insert(debuffs, x.auraInstanceID)
                    else
                        table.insert(buffs, x.auraInstanceID)
                    end
                end
            end

            local buff = trackActiveBuff(unitTarget, v.auraInstanceID, v.icon, buffs, debuffs)

            -- attempt instant identification
            ability, certain = ns:inferAbility(unitTarget, buff, false)
            if certain then
                finalizeInference(buff, ability)
            end
            if ability then 
                local cd = ns.staticRows[ability.caster].items[ability.name]
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
            local ability, certain = ns:getAbility(buff)

            -- 1. no matter what happens below, turn off any glow that may have been
            --    enabled on previous inferences.
            if certain or ability then
                local cd = ns.staticRows[ability.caster].items[ability.name]
                LibButtonGlow.HideOverlayGlow(cd)
            end

            -- 2. gather some information and take a final swing at inference
            buff.endTime = GetTime()
            buff.duration = buff.endTime - buff.startTime
            if not ability or not certain then -- [infer=false|uncertain] then
                ability, certain = ns:inferAbility(unitTarget, buff, true)
                if certain then
                    finalizeInference(buff, ability)
                end
            end

            -- 3. The buff is over, so have to make a choice about how to display it.
            --    If there was a certain inference, track in the static cooldown row,
            --    otherwise dump it in the history tray.
            if ability and certain then --if [infer=true] then
                local cd = ns.staticRows[ability.caster].items[ability.name]
                cd.swipeTexture:SetCooldown(buff.startTime, ability.cooldown) --buff.cooldown)
                cd.swipeTexture:Show()
                -- Have to store start/cooldown info because the text on Blizzard's
                -- cooldown swipe can't be controlled (i.e., font size). So we have
                -- to make our own text.
                cd.startTime = buff.startTime
                cd.cooldown = ability.cooldown -- buff.cooldown
            else
                ns:addBuffToHistory(unitTarget, buff)
            end

            actives[auraInstanceID] = nil    -- allow garbage collection
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

        -- Figure out which CompactPartyFrameMemberX corresponds to player, party1, etc.
        ns:updateSlotToFrameMapping(slot)

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
