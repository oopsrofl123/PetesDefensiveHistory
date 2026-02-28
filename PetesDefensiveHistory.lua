-- get addon namespace
local addonName, ns = ...

-- Other files shouldn't directly access this
local slotToGUID = {}

-- A list of all active auras that we want to infer
ns.buffsForInference = {}

-- A general event tracker: contains the history of recent actions taken
-- by or applied to each character
ns.eventTrackers = {}

-- Retain EVENT_HISTORY_SIZE records of each tracked event type for each
-- character. Must
-- loop over all of these on every buff inference, so don't make it too
-- large, but must be large enough to cover a reasonably large time interval.
local EVENT_HISTORY_SIZE = 8


-- Make an empty event tracker
function ns:makeEventTracker()
    return {
        buff=ns:fixedFIFO(EVENT_HISTORY_SIZE),
        debuff=ns:fixedFIFO(EVENT_HISTORY_SIZE),
        cast=ns:fixedFIFO(EVENT_HISTORY_SIZE),
        shield=ns:fixedFIFO(EVENT_HISTORY_SIZE)
    }
end


-- Is slot tracked? If so, return the stable GUID and character object. The
-- GUID may exist before the Character object, so (non-nil, nil) returns are
-- possible.
--
-- Relies on the updateSlotToGUID maintenance function.
function ns:getTrackedCharacterBySlot(slot)
    if UnitExists(slot) and slotToGUID[slot] then
        local guid = slotToGUID[slot]
        return guid, ns:getTrackedCharacterByGUID(guid)
    end
    return nil
end


local function updateSlotToGUID()
    -- On this pass: make sure all slot->GUID mappings represent current
    -- members of the group/raid/arena/etc. If a slot's GUID changes, that
    -- does not necessarily mean the previous GUID left the group, the
    -- character's position could've shifted.
    for index=1, 5 do
        local slot = ns:indexToSlot(index)
        if UnitExists(slot) then
            local guid = UnitGUID(slot)
            slotToGUID[slot] = guid
            -- Is this the first time we've seen this guid?
            if not ns:getTrackedCharacterByGUID(guid) then
                ns:trackCharacter(slot)
            end
        else
            slotToGUID[slot] = nil
        end
    end

    -- Now compare the GUIDs that existed before the remapping to the ones
    -- that exist after. Any in the first list but not the latter left the
    -- group, so clean up their data.
    for guid, char in pairs(ns:getTrackedCharacters()) do
        if not ns:tablecontains(slotToGUID, guid) then
            ns:untrackCharacter(guid)
        end
    end
end



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



-- Don't hardwire to the global event tracker. Allows swapping out for
-- other event trackers. `event` is a string corresponding to a named
-- component of the table returned by makeEventTracker().
--
-- Multiple inference: to support continuous calls, also check `buff`
-- for previous closest events and, if those are closer, don't overwrite
-- them with whatever is closest in the current event buffer.
local function prepareClosestEvents(buff, eventTrackers, event)
    local closestEvents = {}
    for guid, tracker in pairs(eventTrackers) do
        local prevClosest = 0
        local closest = 0

        -- If there is a previous tracker, get its closest event
        local prevTracker = buff['closest_'..event]
        if prevTracker then
            closest = prevTracker[guid] or closest
        end

        for _, time in pairs(tracker[event]:items()) do
            if math.abs(time - buff.startTime) < math.abs(closest - buff.startTime) then
                closest = time
            end
        end
        closestEvents[guid] = closest
        if prevClosest ~= closest then
            ns:printDebug(string.format("updated closest event type=[%s], actor=[%s], [%0.3f] -> [%0.3f]",
                event, guid, prevClosest, closest))
        end
    end
    return closestEvents
end



function ns:prepareForInference(buff, eventTrackers)
    -- These fields MUST be named "closest_" .. eventName
    buff.closest_buff = prepareClosestEvents(buff, eventTrackers, 'buff')
    buff.closest_debuff = prepareClosestEvents(buff, eventTrackers, 'debuff')
    buff.closest_cast = prepareClosestEvents(buff, eventTrackers, 'cast')
    buff.closest_shield = prepareClosestEvents(buff, eventTrackers, 'shield')
end



-- Add this aura instance to the tracked list of actives on this player.
local function trackBuff(aura)
    local buff = ns:shallowcopy(aura)
    ns:printDebug(string.format(
        'trackBuff: time=[%0.3f], ID=[%d], target=[%s], flags=(IMP=%d, BIG=%d, EXT=%d, RAID=%d, RIC=%d, HELP=%d, HARM=%d, CANCEL=%d)',
        aura.startTime, aura.auraInstanceId, aura.target,
        aura.IMPORTANT and 1 or 0,
        aura.BIG and 1 or 0, aura.EXTERNAL and 1 or 0,
        aura.RAID and 1 or 0, aura.RAIDINCOMBAT and 1 or 0,
        aura.HELPFUL and 1 or 0, aura.HARMFUL and 1 or 0,
        aura.CANCELABLE and 1 or 0)
    )

    -- Fields relevant to inference
    buff.inference = 0    -- counter tracking how many times this buff has been through inferAbility()
    buff.ability = nil    -- the ability that created this buff
    buff.certain = false  -- is the buff <-> ability assignment certain?
    buff.caster = nil

    ns.buffsForInference[aura.target][aura.auraInstanceId] = buff

    return buff
end



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
local function trackCooldown(buff, ability)
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

    trackCooldown(buff, ability)

    -- XXX: TODO: Awful hack for BoP/Spellward. Using one starts the cooldown for the
    -- other. For the other, the cooldown should start as if this buff were created
    -- by that ability. I'd love to have an elegant solution to this, but I don't
    -- think there is another tracked ability that sets the cooldown of another
    -- tracked ability.
    if ability.id == 1022 or ability.id == 204018 then
        local char = ns:getTrackedCharacterByGUID(ability.caster)
        for _, otherAbility in pairs(char:getAbilities(buff.target)) do
            if (otherAbility.id == 1022 or otherAbility.id == 204018) and
               ability.id ~= otherAbility.id then
                ns:printDebug("applying BoP/spellwarding cooldown hack")
                trackCooldown(buff, otherAbility) -- doesn't alter buff
                -- XXX: TODO: copy/pasted from below
                local cdEndsAt = ns.cdTracker[otherAbility.caster][otherAbility.name]:head()
                ns:queueCooldown(otherAbility, cdEndsAt - ability.cooldown)
            end
        end
    end
end



-- Wrapper for inferAbility that sets up various things and responds uniformly
-- to the result. If this buff is being removed, set isFinalAttempt=true.
-- UPDATE: to match other code, we now assume isFinalAttempt=true if buff.endTime
-- is non-nil.
local function inferAndAct(char, buff, now)
    buffIsExpiring = buff.endTime ~= nil

    if not buff.certain then
        buff.duration = now - buff.startTime
        ns:prepareForInference(buff, ns.eventTrackers)
        local ability, certain = ns:inferAbility(char, buff)
        if certain then
            -- Announce the ability with TTS if it satisfies the users preferences,
            -- as long as this isn't when the buff is removed.
            -- As an extra sanity check, don't announce if the buff was applied more
            -- than 1.5s ago.
            if not buffIsExpiring and
               buff.duration < 1.5 and
               ns:GetOption('enableTTS') and
               (not ns:GetOption('TTSnoUntracked') or ns:GetOption('show_'..ability.id)) and
               (not ns:GetOption('TTSnoSelfCasts') or ability.caster ~= buff.target) then
                C_VoiceChat.SpeakText(
                    C_TTSSettings.GetVoiceOptionID(Enum.TtsVoiceType.Standard),
                    ability.name,
                    C_TTSSettings.GetSpeechRate(),
                    C_TTSSettings.GetSpeechVolume())
            end
            finalizeInference(buff, ability)
        end
        if ability and not buffIsExpiring then
            ns:startGlow(ability)
        end
    end
end



--------------------------------------------------------------------------------------
-- Track when spell casts occur
--------------------------------------------------------------------------------------
local castHandler = CreateFrame("Frame", addonName .. "CastHandler")
castHandler:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
castHandler:SetScript("OnEvent", function(self, event, caster, castGUID, spellID, castBarID)
    -- Only track casts from tracked characters
    local guid, char = ns:getTrackedCharacterBySlot(caster)
    if not guid then return end
    local now = GetTime()

    -- mask secrets to avoid errors. sets nil if secret
    spellId = ns:maskSecret(spellId)
    castGUID = ns:maskSecret(castGUID)
    castBarID = ns:maskSecret(castBarID)

    ns:printDebug(string.format("SPELLCAST(time=[%0.3f], caster=[%s|%s], %s, %s)",
        now, caster, guid, tostring(spellID), tostring(castBarID)))
        
    ns.eventTrackers[guid].cast:push(GetTime())

print("SPELLCAST inference pass")
    for auraInstanceId, buff in pairs(ns.buffsForInference[guid]) do
        inferAndAct(char, buff, now)
    end
end)


--------------------------------------------------------------------------------------
-- Track when absorb shields are applied
--------------------------------------------------------------------------------------
local absorbHandler = CreateFrame("Frame", addonName .. "AbsorbHandler")
absorbHandler:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
absorbHandler:SetScript("OnEvent", function(self, event, target)
    -- Only track casts from tracked characters
    local guid, char = ns:getTrackedCharacterBySlot(target)
    if not guid then return end
    local now = GetTime()

    ns:printDebug(string.format("ABSORB(time=[%0.3f], target=[%s|%s])",
        now, target, guid))
        
    ns.eventTrackers[guid].shield:push(GetTime())
print("ABSORB inference pass")
    for auraInstanceId, buff in pairs(ns.buffsForInference[guid]) do
        inferAndAct(char, buff, now)
    end
end)



-- This function needs slot to get filter flags
local function makeAura(startTime, slot, auraInstanceID, iconId)
    local IMPORTANT, BIG, EXTERNAL, RAID, RAIDINCOMBAT, HELPFUL, HARMFUL, CANCELABLE =
        fasterGetFilterFlagsForAuraInstanceId(slot, auraInstanceID)
    return {
        target=slotToGUID[slot],
        auraInstanceId=auraInstanceID,
        secretTexture=iconId,
        startTime=startTime,
        duration=0,
        -- do not specify an end time. a missing endTime field indicates
        -- the buff is not being removed.
        --endTime=startTime + ns.INFINITY,
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
    local guid, char = ns:getTrackedCharacterBySlot(unitTarget)
    if not guid then return end

    -- empty tables to make #(.) work when no auras are in the list
    local aurasAdded = updateInfo['addedAuras'] or {}
    local aurasRemoved = updateInfo['removedAuraInstanceIDs'] or {}
    local aurasUpdated = updateInfo['updatedAuraInstanceIDs'] or {}
    local now = GetTime()
    local actives = ns.buffsForInference[guid]  -- Currently active defensive buffs for this slot

    ns:printDebug(string.format('AURA(time=%0.3f, target=[%s|%s], #added=[%d], #updated=[%d], #removed=[%d])',
        now, unitTarget, guid, #aurasAdded, #aurasUpdated, #aurasRemoved))

    -- Convenience mode for collecting data about buff rules. Shows all buffs and debuffs added,
    -- including secret data that would not normally be available.
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

        -- Is this aura a buff we want to infer?
        if aura.HELPFUL and (aura.IMPORTANT or aura.BIG or aura.EXTERNAL) then
            local buff = trackBuff(aura)
            -- attempt instant identification
            inferAndAct(char, buff, now)
        else
            -- This is not an aura we want to track, so it counts as a concurrent event
            if aura.HARMFUL then
                ns.eventTrackers[guid].debuff:push(now)
            elseif aura.HELPFUL then
                ns.eventTrackers[guid].buff:push(now)
            end
        end
    end

    -- unlike aurasAdded, this is just a list of updated IDs
    for _, auraInstanceID in pairs(aurasUpdated) do
        buff = actives[auraInstanceID]
        if buff then
            ns:printDebug("target=" .. unitTarget .. ": updating " .. buff.auraInstanceId)
            buff.numUpdates = buff.numUpdates + 1
            -- XXX: TODO: inferAndAct(char, buff, now) here
        end
    end

    -- Aura removal is a unique life stage event. Unlike other inference times,
    -- the buff is being removed, so this is the final attempt at inference.
    -- If the buff can't be IDed, then give up and send it to the history tray.
    -- Otherwise, start a cooldown swipe. Since the buff is going away, it is
    -- also time to end active glows.
    for _, auraInstanceID in pairs(aurasRemoved) do
        -- if this aura instance ID is being tracked for this player, then it was a defensive
        -- and is now over. Insert it into the history tracker.
        buff = actives[auraInstanceID]
        if buff then
            -- 1. turn off any glow that may have been enabled on previous inferences.
            local ability, certain = ns:getAbility(buff)
            if ability then
                ns:stopGlow(ability)
            end

            -- 2. gather some information and take a final swing at inference
            buff.endTime = now   -- if endTime is not nil, the buff is being removed
            inferAndAct(char, buff, now, true)
            ability, certain = ns:getAbility(buff)

            -- 3. The buff is over, so have to make a choice about how to display it.
            --    If there was a certain inference, track in the static cooldown row,
            --    otherwise dump it in the history tray.
            -- Since dynamic CDR ability timers are rarely accurate, allow users to
            -- send those to the history tray instead. This doesn't prevent them from
            -- being glowed, if possible.
            if ability and certain and not (ability.cdr and ns:GetOption('disableCDRTrackers')) then
                local cdEndsAt = ns.cdTracker[ability.caster][ability.name]:head()
                ns:queueCooldown(ability, cdEndsAt - ability.cooldown)
            else
                ns:addBuffToHistoryTray(guid, buff)
            end

            actives[auraInstanceID] = nil
        end
    end

    -- Final step: loop through all buffs on this character that are still not IDed.
    -- Important note: getting here means the buff has not been removed yet, so
    -- that resolution still must wait for a later UNIT_AURA event.
    for auraInstanceId, buff in pairs(actives) do
        inferAndAct(char, buff, now)
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

    -- Maintain the slot -> GUID map
    updateSlotToGUID()

    -- Update UI elements
    ns:updateTrackerUI()
    ns:updateGroupSolutionUI()
end)



--------------------------------------------------------------------------------------
-- A totally unnecessary poller to force more inference attempts when nothing is
-- happening (e.g., standing in town).
--------------------------------------------------------------------------------------
poller = C_Timer.NewTicker(0.25, function()
    local now = GetTime()
    for guid, char in pairs(ns:getTrackedCharacters()) do
        for auraInstanceId, buff in pairs(ns.buffsForInference[guid]) do
            inferAndAct(char, buff, now)
        end
    end
end)


do
    updateSlotToGUID()

    -- Addons are loaded after all blizzard frames, so can allocate everything now.
    ns:allocHistoryGrid()
    ns.groupSolutionUI = ns:allocGroupSolutionUI()

    -- Open the solution UI
    SLASH_PDH1 = "/pdh"
    -- Open the config panel
    -- SlashCmdList.PDH = function() Settings.OpenToCategory(ns.optionsCategory:GetID()) end
    SlashCmdList.PDH = function() ns.groupSolutionUI:Show() end
end
