-- get addon namespace
local addonName, ns = ...

-- All active auras on everyone in the group, whether they're the ones
-- we track or not.
ns.auras = {}
for slot, _ in pairs(ns.allSlots) do
    ns.auras[slot] = {}
end

ns.slotToGUID = {}


local function fasterGetFilterFlagsForAuraInstanceId(slot, auraInstanceId)
    -- XXX: TODO: weird stuff going on here. an aura filtered by HELPFUL|IMPORTANT
    -- is not filtered by just IMPORTANT but is filtered by just HELPFUL. maybe
    -- this will get fixed. for now, just add the seemingly unnecessary HELPFUL|
    -- in front of every filter.
        --print('----------------',
            --C_Spell.IsSpellImportant(1044),
            --not C_UnitAuras.IsAuraFilteredOutByInstanceID(slot, auraInstanceId, "HELPFUL|IMPORTANT"),
            --not C_UnitAuras.IsAuraFilteredOutByInstanceID(slot, auraInstanceId, "IMPORTANT"),
            ----not C_UnitAuras.IsAuraFilteredOutByInstanceID(slot, auraInstanceId, "HELPFUL")
        --)
    return
        not C_UnitAuras.IsAuraFilteredOutByInstanceID(slot, auraInstanceId, "HELPFUL|IMPORTANT"),
        not C_UnitAuras.IsAuraFilteredOutByInstanceID(slot, auraInstanceId, "HELPFUL|BIG_DEFENSIVE"),
        not C_UnitAuras.IsAuraFilteredOutByInstanceID(slot, auraInstanceId, "HELPFUL|EXTERNAL_DEFENSIVE"),
        not C_UnitAuras.IsAuraFilteredOutByInstanceID(slot, auraInstanceId, "HELPFUL|RAID"),
        not C_UnitAuras.IsAuraFilteredOutByInstanceID(slot, auraInstanceId, "HELPFUL|RAID_IN_COMBAT"),
        not C_UnitAuras.IsAuraFilteredOutByInstanceID(slot, auraInstanceId, "HELPFUL"),
        not C_UnitAuras.IsAuraFilteredOutByInstanceID(slot, auraInstanceId, "HARMFUL"),
        -- Some buffs we track are not cancelable (like GoAK). Unfortunately this filter
        -- isn't correct for GoAK, so it isn't useful in that case. But maybe it is for
        -- some others?
        not C_UnitAuras.IsAuraFilteredOutByInstanceID(slot, auraInstanceId, "HELPFUL|CANCELABLE")
        --not C_UnitAuras.IsAuraFilteredOutByInstanceID(slot, auraInstanceId, "CANCELABLE")
end



-- Add this aura instance to the tracked list of actives on this player.
local function trackBuff(aura, concurrentBuffs, concurrentDebuffs)
    ns:printDebug(string.format(
        'trackBuff: auraInstanceID=[%d], target=[%s], time=[%0.3f], flags=(IMP=%d, BIG=%d, EXT=%d, RAID=%d, RIC=%d, HELP=%d, HARM=%d, CANCELABLE=%d)',
        aura.auraInstanceId, aura.target, aura.startTime,
        aura.IMPORTANT and 1 or 0,
        aura.BIG and 1 or 0, aura.EXTERNAL and 1 or 0,
        aura.RAID and 1 or 0, aura.RAIDINCOMBAT and 1 or 0,
        aura.HELPFUL and 1 or 0, aura.HARMFUL and 1 or 0,
        aura.CANCELABLE and 1 or 0)
    )

    closestCasts = {}
    for guid, hist in pairs(ns.castHistory) do
        closest = ns.INFINITY
        for _, cast in pairs(hist:items()) do
            if math.abs(cast.time - aura.startTime) < math.abs(closest - aura.startTime) then
                closest = cast.time
            end
        end
        closestCasts[guid] = closest
    end

    local buff = ns:shallowcopy(aura)

    -- Add fields relevant to inference
    buff.inference = 0    -- counter tracking how many times this buff has been through inferAbility()
    buff.ability = nil    -- the ability that created this buff
    buff.certain = false  -- is the buff <-> ability assignment certain?
    buff.caster = nil
    buff.concurrentBuffs = concurrentBuffs or {}
    buff.concurrentDebuffs = concurrentDebuffs or {}
    buff.closestCasts = closestCasts

    ns.activeDefensives[aura.target][aura.auraInstanceId] = buff

    return buff
end



-- Call this function when we are ready to fully accept whatever the best
-- inference was.
local function finalizeInference(buff, ability)
    if not buff.certain then
        print(string.format(
            "WARNING: finalizing an uncertain inference (ability=[%s], caster=[%s], target=[%s])!",
            ability.name, ability.caster, buff.target))
    end

    ns:printDebug(string.format(
        "|cff00CDCDFINAL INFERENCE (attempt=%d, time=%0.3f): [%s] cast [%s] at time [%0.3f]!|r",
            buff.inference, GetTime(), ability.caster, ability.name, buff.startTime))

    
    -- Determine when an ability began recharging. For #charges=1 abilities, this
    -- is just the cast time. For N>1 charges, the recharge for charge k depends
    -- on when charge k-1 finished
    --     end{k} = max(end{k-1}+cd, cast{k}+cd),   end{0}=-Inf
    -- where end{.} is the time when charge {.} finishes recharging.
    --
    -- To see how this differs from the simple charge=1 case where the recharge
    -- finishes at time=cast+cd, consider an ability that has N=10 charges and a
    -- cooldown of cd=10. Use all 10 charges 1s apart, so at times=0, 1, 2, 3, ... 9.
    -- Charge 1 (t=0) comes off of cooldown at t=10, the same as cast+cd:
    --      end{1} = max(-Inf+10, 0+10) = 10
    -- Charge 2 was used at t=1, but it comes off cd at t=20:
    --      end{2} = max(end{1}+10, cast{2}+10) = max(20, 11) = 20
    -- Charge 3:
    --      end{3} = max({end{2}+10, cast{3}+10) = max(30, 12) = 30
    -- ...
    local cdfifo = ns.cdTracker[ability.caster][ability.name]
    if ability.cdr == false then
        cdfifo:push(math.max(cdfifo:head() + ability.cooldown, buff.startTime + ability.cooldown))
    else
        -- For single charge abilities with dynamic CDR, need to ignore the previous
        -- cooldown in the FIFO. The ability was used, so it was off cooldown even though
        -- the stored end time in the FIFO may disagree (since it cannot account for CDR).
        if ability.charges == 1 then
            cdfifo:push(buff.startTime + ability.cooldown)
        else
            -- For a multi-charge CDR ability:
            --    * 1 charge was available at buff.startTime and it was used (causing
            --      this inference).
            --    * It's unknown how much recharge time has gone into the previous charge(s).
            -- XXX: TODO: we can do better than this, but it's a little complicated. Come back
            -- to it later. For now, use the worst-case scenario.
            cdfifo:push(math.max(cdfifo:head() + ability.cooldown, buff.startTime + ability.cooldown))
        end
    end
end



--------------------------------------------------------------------------------------
-- This frame is responsible for tracking when party members cast abilities.
--------------------------------------------------------------------------------------
local castHandler = CreateFrame("Frame", addonName .. "CastHandler")
castHandler:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
castHandler:SetScript("OnEvent", function(self, event, caster, castGUID, spellID, castBarID)
    if not ns.allSlots[caster] then return end

    -- mask secrets to avoid errors. sets nil if secret
    spellId = ns:maskSecret(spellId)
    castGUID = ns:maskSecret(castGUID)
    castBarID = ns:maskSecret(castBarID)

    ns:printDebug(string.format("UNIT_SPELLCAST_SUCCEEDED(%s, %s, %s, %s, %0.3f)",
        caster, tostring(castGUID), tostring(spellID), tostring(castBarID), GetTime()))
        
    ns.castHistory[ns.slotToGUID[caster]]:push({ time=GetTime() })
end)



-- This function needs slot to get filter flags
local function makeAura(startTime, slot, auraInstanceID, iconId)
    local IMPORTANT, BIG, EXTERNAL, RAID, RAIDINCOMBAT, HELPFUL, HARMFUL, CANCELABLE =
        fasterGetFilterFlagsForAuraInstanceId(slot, auraInstanceID)
    return {
        target=ns.slotToGUID[slot],
        auraInstanceId=auraInstanceID,
        secretTexture=iconId,
        startTime=startTime,
        duration=0,
        endTime=startTime + ns.INFINITY,
        IMPORTANT=IMPORTANT,
        BIG=BIG,
        EXTERNAL=EXTERNAL,
        RAID=RAID,
        RAIDINCOMBAT=RAIDINCOMBAT,
        HELPFUL=HELPFUL,
        HARMFUL=HARMFUL,
        CANCELABLE=CANCELABLE,
        numUpdates=0
    }
end



--------------------------------------------------------------------------------------
-- This frame is responsible for handling events about auras being applied, updated
-- or removed.
--------------------------------------------------------------------------------------
local auraHandler = CreateFrame("Frame", addonName .. "AuraHandler")
auraHandler:RegisterEvent("UNIT_AURA")
auraHandler:SetScript("OnEvent", function(self, event, unitTarget, updateInfo)
    -- Ensure unitTarget is a recognized slot. This event is called for nameplates and others
    if not ns.allSlots[unitTarget] then return end

    local guid = ns.slotToGUID[unitTarget]
    local char = ns:getTrackedCharacterByGUID(guid)

    -- empty table to make #(.) work when no auras are added. same for other tables.
    local aurasAdded = updateInfo['addedAuras'] or {}
    local aurasRemoved = updateInfo['removedAuraInstanceIDs'] or {}
    local aurasUpdated = updateInfo['updatedAuraInstanceIDs'] or {}

    local now = GetTime()

    -- Currently active defensive buffs for this slot
    if not ns.activeDefensives[guid] then
        ns.activeDefensives[guid] = {}
    end
    local actives = ns.activeDefensives[guid]

    ns:printDebug(string.format('UNIT_AURA(time=%0.3f, target=[%s/GUID=%s], #added=[%d], #updated=[%d], #removed=[%d])',
        now, unitTarget, guid, #aurasAdded, #aurasUpdated, #aurasRemoved))

    -- Convenience mode for collecting data about buff rules. Show all buffs and
    -- debuffs added, including secret data that would not be available in
    -- real content
    if ns:GetOption('dataMiningMode') and unitTarget == "player" then
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
        local aura = makeAura(now, unitTarget, v.auraInstanceID, v.icon)
        print(aura.auraInstanceId, aura.IMPORTANT, aura.BIG, aura.EXTERNAL,
            aura.RAID, aura.RAIDINCOMBAT, aura.HELPFUL, aura.HARMFUL, aura.CANCELABLE)

        -- Is this aura a buff we want to track?
        if aura.HELPFUL and (aura.IMPORTANT or aura.BIG or aura.EXTERNAL) then
            -- get all of the other buff and debuff auras added in this event
            local buffs = {}
            local debuffs = {}
            for _, x in pairs(aurasAdded) do
                if x.auraInstanceID ~= v.auraInstanceID then
                    if harm then
                        table.insert(debuffs, x.auraInstanceID)
                    else
                        table.insert(buffs, x.auraInstanceID)
                    end
                end
            end

            local buff = trackBuff(aura, buffs, debuffs)

            -- attempt instant identification
            ability, certain = ns:inferAbility(ns:getTrackedCharacterByGUID(guid), buff, false)
            if certain then
                finalizeInference(buff, ability)
            end
            if ability then 
                ns:startGlow(ability)
            end
        end
    end

    -- unlike aurasAdded, this is just a list of updated IDs
    for _, auraInstanceID in pairs(aurasUpdated) do
        buff = actives[auraInstanceID]
        if buff then
            ns:printDebug("target=" .. unitTarget .. ": updating " .. buff.auraInstanceId)
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
                ns:stopGlow(ability)
            end

            -- 2. gather some information and take a final swing at inference
            buff.endTime = GetTime()
            buff.duration = buff.endTime - buff.startTime
            if not ability or not certain then
                ability, certain = ns:inferAbility(char, buff, true)
                if certain then
                    finalizeInference(buff, ability)
                end
            end

            -- 3. The buff is over, so have to make a choice about how to display it.
            --    If there was a certain inference, track in the static cooldown row,
            --    otherwise dump it in the history tray.
            if ability and certain then
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
                local cdEndsAt = ns.cdTracker[ability.caster][ability.name]:head()
                    -- cd.startTime is the start time of the recharge, not the start time of the
                    -- buff (=when the ability was cast). These can differ for abilities
                    -- with charges. Some notes:
                    --   * Single charge abilities: cdEndsAt = buff.startTime + ability.cooldown,
                    --     even if there is dynamic CDR
                    --   * Multi-charge abilities: cdEndsAt accounts for previous recharge completions.

                ns:queueCooldown(ability, cdEndsAt - ability.cooldown)

                -- CDR abilities will appear to queue a cooldown when they're used before
                -- their base CD is up.
                --cd.numQueued = math.min(cd.numQueued + 1, ability.charges)
                -- If this was the last charge, then draw the dark cooldown swipe.
                -- Otherwise just show the edge.
                --cd.swipeTexture:SetDrawSwipe(cd.numQueued == ability.charges)
                --cd.swipeTexture:Show()
            else
                ns:addBuffToHistoryTray(guid, buff)
            end

            actives[auraInstanceID] = nil    -- allow garbage collection
        end
    end
end)



local function updateSlotToGUID()
    for index=1, 5 do
        local slot = ns:indexToSlot(index)
        if UnitExists(slot) then
            local char = ns:trackCharacter(slot)
            local guid = char:getID() -- UnitGUID(slot)
            ns.slotToGUID[slot] = guid
            ns.castHistory[guid] = ns.castHistory[guid] or ns:fixedFIFO(ns.MAX_CAST_HISTORY)
        end
    end

    -- XXX: TODO: prune GUIDs that are no longer tracked
end



--------------------------------------------------------------------------------------
-- Just handle initialization and group roster updates.
--------------------------------------------------------------------------------------
local loader = CreateFrame("Frame", addonName .. "Loader")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("GROUP_ROSTER_UPDATE")
loader:SetScript("OnEvent", function(self, event)
    ns:printDebug(event)

    -- Maintain the slot -> GUID map
    updateSlotToGUID()

    -- Update UI elements
    ns:updateTrackerUI(slot)

    --for slot, _ in pairs(ns.allSlots) do
        --local tracker = ns.trackerUI[slot]

        -- Which X: CompactPartyFrameMemberX maps to player, party1, etc.?
        --ns:updateSlotToFrameMapping(slot)
        --ns:updateTrackerUI(slot)

        -- account for the fact that LibSpec also fires on GROUP_ROSTER_UPDATE
        -- and can either come before or after this event.
        --if UnitExists(slot) then
            --if UnitName(slot) ~= tracker.playerName then
                ---- this handler was called before LibSpec
                --ns:setTrackerUIData(slot, nil, UnitName(slot))
                --ns:updateTrackerUI(slot)
            --else
                -- this handler was called after LibSpec. nothing to do
            --end
        --else
            --ns:clearRow(row)
            --ns:showDebugVisual(tracker)
        --end
    --end
end)


updateSlotToGUID()

-- Addons should be loaded after all blizzard frames, so can allocate everything now.
ns:allocHistoryGrid()
--ns.groupSolutionUI = ns:allocGroupSolutionUI()

-- Open the solution UI
SLASH_PDH1 = "/pdh"
-- Open the config panel
-- SlashCmdList.PDH = function() Settings.OpenToCategory(ns.optionsCategory:GetID()) end
SlashCmdList.PDH = function() ns.groupSolutionUI:Show() end
