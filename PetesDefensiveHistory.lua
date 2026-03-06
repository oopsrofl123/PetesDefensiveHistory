-- get addon namespace
local addonName, ns = ...

-- Other files shouldn't directly access this
local slotToGUID = {}

-- time in seconds to expire a non-buff event since there is no UNIT_AURA(removed)
-- event to naturally time it out
expireNonAuraEventsAfter = 0.5

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
            char:untrack()
        end
    end
end



local function fasterGetFilterFlagsForAuraInstanceId(slot, auraInstanceId)
    -- XXX: TODO: super fun hack to shoe-horn non-buffs into the system. Negative aura IDs
    -- signal to avoid calling C_UnitAuras.IsAuraFilteredOutByInstanceID. Just has to
    -- return a consistent set of flags that we can mimic in AbilityDb (i.e., any ability
    -- we want to ID this way must have this flag set in AbilityDb).
    if auraInstanceId < 0 then
        return false, false, false, false, false, nil, nil, nil, nil, nil, nil, nil
    end
    local function getFlag(filter)
        return not C_UnitAuras.IsAuraFilteredOutByInstanceID(slot, auraInstanceId, filter)
    end
    return
        getFlag("HELPFUL|IMPORTANT"),
        getFlag("HELPFUL|BIG_DEFENSIVE"),
        getFlag("HELPFUL|EXTERNAL_DEFENSIVE"),
        getFlag("HELPFUL|RAID"),
        getFlag("HELPFUL|RAID_IN_COMBAT"),
        getFlag("HELPFUL"),
        getFlag("HARMFUL"),
        -- Some buffs we track are not cancelable (like GoAK). Unfortunately this filter
        -- does not correctly reflect that  for GoAK. But maybe it is correct for others?
        getFlag("HELPFUL|CANCELABLE"),
        getFlag("HELPFUL|INCLUDE_NAME_PLATE_ONLY"),
        getFlag("INCLUDE_NAME_PLATE_ONLY"),
        getFlag("HARMFUL|CROWD_CONTROL"),
        getFlag("CROWD_CONTROL")
end



-- This function needs slot rather than guid to get filter flags from the Blizzard API
local function makeAura(startTime, slot, auraInstanceId, iconId)
    local IMPORTANT, BIG, EXTERNAL, RAID, RAIDINCOMBAT,
        HELPFUL, HARMFUL, CANCELABLE, HELPNAMEPLATE, NAMEPLATE, HARMCC, CC =
        fasterGetFilterFlagsForAuraInstanceId(slot, auraInstanceId)

    aura = {
        target=slotToGUID[slot],
        auraInstanceId=auraInstanceId,
        secretTexture=iconId,
        startTime=startTime,
        IMPORTANT=IMPORTANT,
        BIG=BIG,
        EXTERNAL=EXTERNAL,
        RAID=RAID,
        RAIDINCOMBAT=RAIDINCOMBAT,
        HELPFUL=HELPFUL,
        HARMFUL=HARMFUL,
        CANCELABLE=CANCELABLE,
        HELPNAMEPLATE=HELPNAMEPLATE,
        NAMEPLATE=NAMEPLATE,
        HARMCC=HARMCC,
        CC=CC,
        numUpdates=0
    }

    ns:printDebug(string.format("%d, %s, %s, %s, %s, %s, %s, %s, CANCEL: %s, NAMEPLATE: %s, %s, CC: %s, %s",
        aura.auraInstanceId, tostring(aura.IMPORTANT), tostring(aura.BIG),
        tostring(aura.EXTERNAL), tostring(aura.RAID), tostring(aura.RAIDINCOMBAT),
        tostring(aura.HELPFUL), tostring(aura.HARMFUL), tostring(aura.CANCELABLE),
        tostring(aura.HELPNAMEPLATE), tostring(aura.NAMEPLATE),
        tostring(aura.HARMCC), tostring(aura.CC)))

    return aura
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
local function trackCooldown(event, ability)
    local cdfifo = ns.cdTracker[ability.caster][ability.name]
    if ability.cdr == false then
        cdfifo:push(math.max(cdfifo:head() + ability.cooldown, event:getTime() + ability.cooldown))
    else
        -- For single charge abilities with dynamic CDR, need to ignore the previous
        -- cooldown in the FIFO. The ability was used, so it was off cooldown even though
        -- the stored end time in the FIFO may disagree (since it cannot account for CDR).
        if ability.charges == 1 then
            cdfifo:push(event:getTime() + ability.cooldown)
        else
            -- For a multi-charge CDR ability:
            --    * 1 charge was available at event:getTime() and it was used (causing
            --      this inference).
            --    * It's unknown how much recharge time has gone into the previous charge(s).
            -- XXX: TODO: we can do better than this, but it's a little complicated. Come back
            -- to it later. For now, use the worst-case scenario.
            cdfifo:push(math.max(cdfifo:head() + ability.cooldown, event:getTime() + ability.cooldown))
        end
    end
end



-- Call this function when we are ready to fully accept whatever the best
-- inference was.
local function finalizeInference(ev, ability)
    if not ev:isCertain() then
        print(string.format(
            "WARNING: finalizing an uncertain inference (ability=[%s], caster=[%s], target=[%s])!",
            ability.name, ability.caster, ev:getSource()))
    end

    -- XXX: TODO: undo
    local buff = ev:getAura()

    -- Optionally announce the ability with TTS, but only if it isn't expiring
    -- and was IDed quickly enough (1.5s since it was used).
    if not ev:isExpiring() and ev:timeSince() < 1.5 and ns:GetOption('enableTTS') and
       (not ns:GetOption('TTSnoUntracked') or ns:GetOption('show_'..ability.id)) and
       (not ns:GetOption('TTSnoSelfCasts') or ability.caster ~= ev:getTarget()) then
        C_VoiceChat.SpeakText(
            C_TTSSettings.GetVoiceOptionID(Enum.TtsVoiceType.Standard),
            ability.name,
            C_TTSSettings.GetSpeechRate(),
            C_TTSSettings.GetSpeechVolume())
    end

    -- Run an optional callback to make last minute changes before finalizing
    if ev.onFinalize then
        ns:printDebug("+++ Running special onFinalize("..ability.name..")")
        ev.onFinalize(ev, ability)
    end

    ns:printDebug(string.format(
        "|cff00CDCDFINALIZED(time=[%0.3f], attempt=[%d]): [%s] cast [%s] at time [%0.3f]|r",
            GetTime(), ev:getInference(), ability.caster, ability.name, ev:getTime()))

    trackCooldown(ev, ability)

    -- XXX: TODO: Awful hack for BoP/Spellward. Using one starts the cooldown for the
    -- other. For the other, the cooldown should start as if this buff were created
    -- by that ability. I'd love to have an elegant solution to this, but I don't
    -- think there is another tracked ability that sets the cooldown of another
    -- tracked ability.
    if ability.id == 1022 or ability.id == 204018 then
        local char = ns:getTrackedCharacterByGUID(ability.caster)
        for _, otherAbility in pairs(char:getAbilities(ev:getTarget())) do
            if (otherAbility.id == 1022 or otherAbility.id == 204018) and
               ability.id ~= otherAbility.id then
                ns:printDebug("applying BoP/spellwarding cooldown hack")
                trackCooldown(ev, otherAbility) -- doesn't alter event
                ns:queueCooldown(otherAbility)
            end
        end
    end
end



-- What to do when the buff expires (or is replaced)? If there was a certain inference,
-- track in the static cooldown row, otherwise dump it in the history tray.
-- Since dynamic CDR ability timers are rarely accurate, allow users to
-- send those to the history tray instead. This doesn't prevent them from
-- being glowed while active.
local function eventExpiredOrReplaced(ev)
    local ability, certain = ev:getAbility()
    if ability and certain and not (ability.cdr and ns:GetOption('disableCDRTrackers')) then
        ns:queueCooldown(ability)
    elseif not ev:isNonAuraEvent() then
        ns:addAuraToHistoryTray(ev:getAura())
    end
end



-- Main update function for tracked events. Runs inference if appropriate and
-- removes them from tracking when their lifetime is over.
function ns:inferAndAct(inferenceTrace, char, ev, now)
    if not ev:isCertain() and (ev:isExpiring() or not ev.forceFullDuration) then
        ev:prepareForInference()
        local ability, certain = ns:inferAbility(inferenceTrace, char, ev)
        if certain then
            finalizeInference(ev, ability)
        end
        if ability and not ev:isExpiring() then
            ns:startGlow(ability)
        end
    end

    -- handle end of life for all events
    if ev:isExpiring() then
        local ability, certain = ev:getAbility()
        if ability then
            ns:stopGlow(ability)
        end
        eventExpiredOrReplaced(ev)
        ev:untrack()
    end
end



--====================================================================================
-- EVENT HANDLERS
--====================================================================================

--------------------------------------------------------------------------------------
-- Track player spell casts
--------------------------------------------------------------------------------------
local castHandler = CreateFrame("Frame", addonName .. "CastHandler")
castHandler:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
castHandler:SetScript("OnEvent", function(self, event, caster, castGUID, spellID, castBarID)
    -- Only track casts from tracked characters
    local guid, char = ns:getTrackedCharacterBySlot(caster)
    if not guid then return end
    local now = GetTime()

    ns:printDebug(string.format("SPELLCAST(time=[%0.3f], caster=[%s|%s], %s, %s)",
        now, caster, guid,
        tostring(ns:maskSecret(spellID)), tostring(ns:maskSecret(castBarID))))
        
    char:trackEvidence('cast', now)

    ns:manageEvents("CAST", guid)
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
        
    char:trackEvidence('shield', now)

    ns:manageEvents("ABSORB", guid)
end)


--------------------------------------------------------------------------------------
-- Track when unit flags change
--------------------------------------------------------------------------------------
local flagsHandler = CreateFrame("Frame", addonName .. "UnitFlagsHandler")
flagsHandler:RegisterEvent("UNIT_FLAGS")
flagsHandler:SetScript("OnEvent", function(self, event, target)
    -- Only track casts from tracked characters
    local guid, char = ns:getTrackedCharacterBySlot(target)
    if not guid then return end
    local now = GetTime()

    local inCombat = UnitAffectingCombat(target)
    ns:printDebug(string.format("UNIT_FLAGS(time=[%0.3f], target=[%s|%s], inCombat=[%s])",
        now, target, guid, tostring(inCombat)))

    -- Check previously witnessed inCombat state. Did target leave combat?
    local lastInCombat = char:getEvidence('combatStatus'):head()
    -- Push the current status whether dropped or not
    char:trackEvidence('combatStatus', inCombat)

    if lastInCombat == true and inCombat == false then
        char:trackEvidence('combatDrop', now)

        local ev = ns:Event("FLAGS", guid)
        -- Since this event is not tied to a buff, how long to keep it around?
        ev:setExpiration(now + expireNonAuraEventsAfter)
        ev:track()
    end
    ns:manageEvents("FLAGS("..tostring(lastInCombat)..">"..tostring(inCombat)..")", guid)
end)


--------------------------------------------------------------------------------------
-- Track when auras are applied, updated or removed
--------------------------------------------------------------------------------------
local auraHandler = CreateFrame("Frame", addonName .. "AuraHandler")
auraHandler:RegisterEvent("UNIT_AURA")
auraHandler:SetScript("OnEvent", function(self, event, unitTarget, updateInfo)
    -- Ensure unitTarget is a recognized slot. This event is called for nameplates and others
    local guid, char = ns:getTrackedCharacterBySlot(unitTarget)
    if not guid then return end
    -- XXX: TODO: later release to track CCs
    --if guid == nil and unitTarget:sub(1,9) == 'nameplate' then guid = UnitGUID(unitTarget) end

    -- empty tables to make #(.) work when no auras are in the list
    local aurasAdded = updateInfo['addedAuras'] or {}
    local aurasRemoved = updateInfo['removedAuraInstanceIDs'] or {}
    local aurasUpdated = updateInfo['updatedAuraInstanceIDs'] or {}
    local now = GetTime()

    ns:printDebug(string.format('AURA(time=[%0.3f], target=[%s|%s], added=[%d], updated=[%d], removed=[%d])',
        now, unitTarget, guid, #aurasAdded, #aurasUpdated, #aurasRemoved))

    -- Convenience mode for collecting data about buff rules. Shows all buffs and debuffs added,
    -- including secret data that would not normally be available.
    if ns:GetOption('dataMiningMode') and unitTarget == "player" then
        for _, v in pairs(aurasAdded) do
            ns:printDebug("DATA MINING: aura added ID=" .. v.auraInstanceID)
            if not issecretvalue(v.spellId) then
                ns.compactPrinter(v)
            end
        end
        ns:printDebug("DATA MINING: aura instance IDs updated: " .. ns.compactFormatter(aurasUpdated))
        ns:printDebug("DATA MINING: aura instance IDs removed: " .. ns.compactFormatter(aurasRemoved))
    end

    for _, v in pairs(aurasAdded) do
        local aura = makeAura(now, unitTarget, v.auraInstanceID, v.icon)

        -- Is this aura a buff we want to infer?
        if aura.HELPFUL and (aura.IMPORTANT or aura.BIG or aura.EXTERNAL) then
            local ev = ns:trackAura("AURA(add)", aura)
        else
            -- This is not an aura we want to track, so it counts as a concurrent event
            -- IMPORTANT!! some auras are returned by neither the helpful nor harmful
            -- filters. This does not necessarily agree with isHelpful or isHarmful
            -- annotations in this payload (which are secret anyway).
            -- If you think a buff should be present in the trackers but isn't, it likely
            -- falls is neither HELPFUL nor HARMFUL. Example: coagulating blood (id=463730)
            if aura.HARMFUL then
                char:trackEvidence('debuff', now)
            elseif aura.HELPFUL then
                char:trackEvidence('buff', now)
            end
        end
    end

    for _, auraInstanceId in pairs(aurasUpdated) do
        local ev = ns:getAuraEventByGUID(auraInstanceId, guid)
        local buff = ev and ev:getAura() or nil
        -- needs to become an event
        if buff then
            ns:printDebug("|cff00ff00++++++++++++++ target=" .. unitTarget ..
                ": updating " .. ev:getId() .. "|r")
            buff.numUpdates = buff.numUpdates + 1
            local ability, certain = ev:getAbility()
            -- LIMITATION: when inference fails (or more likely, is turned off) we can't
            -- do anything because the ability could naturally update. an example of this
            -- is when a charge>1 ability is pressed a second time while it's already
            -- running. if it wasn't inferred (or the user disabled inference), then we
            -- can't send the first charge to the history tray because it would need to
            -- happen now and we don't know if this is a natural update. in the end, only
            -- the second use will be sent to the history tray (on expiry).
            --
            -- XXX: TODO: this is the crux of the fiery brand 2-charge problem. It
            -- naturally self-updates and has 2 charges. The only way to distinguish
            -- a charge use is to detect a very close button press (and even this is
            -- not 100% accurate), but the machinery to do that is in inferAbility. We
            -- can't call inferAbility here without causing side effects.
            --
            -- It looks like a no-side-effects version of inferAbility is needed so this
            -- rule and others can be tested without committing to previous results.
            if certain and not ability.naturallyUpdates and ability.charges > 1 then
                -- The easy case: the first use of the ability with IDed with certainty and
                -- the cooldown has already been tracked. If this buff does NOT naturally
                -- update and it has >1 charges, then maybe it was pressed a second time,
                -- expending a second charge. Try to infer again.
                -- ability.charges > 1 is not a check that there is a charge available for
                -- use, the inference engine does that.
                --
                -- Whether the upcoming inference succeeds or not, the previous certain
                -- inference is being voided and replaced.
                eventExpiredOrReplaced(ev)
                buff.startTime = now   -- must reset or inference machinery will skip
                buff.certain = false   -- must reset or inference machinery will skip
                ns:inferAndAct("AURA(update)", char, ev, now)
            elseif ability and not certain and not ability.naturallyUpdates then
                -- Harder case. An uncertain inference and the inferred ability does not
                -- update. There might not be a general way to resolve this. Currently the
                -- only non-certain inference is VDH meta, maybe a special rule for each
                -- corner case is practical.
                if ability.name == 'Metamorphosis' then
                    local updateTime = now
                    local metaDuration = char:getAbilities()['Metamorphosis'].duration
                    local apexDuration = char:getAbilities()['Untethered Rage'].duration
                    ev.forceFullDuration = true
                    ev.onFinalize = function(event, ability)
                        -- When did meta start its cooldown?
                        -- The current buff is meta, but it has been applied at two
                        -- time points by either meta or the apex talent. We need to know
                        -- which one was the real meta to know when to start the cooldown.
                        -- Remember that this is the certain=false case, which means that
                        -- the buff has been running for <10s (or else we would know it is
                        -- not the apex talent which only lasts 10s).
                        -- Case 1: apex > meta:
                        --     meta overwrites apex, so the total duration of the buff is:
                        --          duration = (apex dur before update) + 20s < 30s
                        --     The duration is <30s because the apex has been running for
                        --     less than 10s or 
                        -- Case 2: meta > apex: in this case, do nothing
                        --     apex extends meta, so the total duration is:
                        --          duration = 20s + 10s = 30s
                        if event:timeSince() < metaDuration + apexDuration - ns.DURATION_TOLERANCE then
                            -- XXX: TODO: BROKEN! THIS DOES NOT WORK AND NEVER DID!
                            event.startTime = updateTime -- Case 1
                        end
                    end
                end
            end
        else
            -- buff not in the tracked list, could they be concurrently applied buffs?
            -- E.g., warrior thunder blast stacks: these can be farmed outside of Avatar
            -- but are also awarded when pressing avatar.
            -- There are auras that are neither HELPFUL or HARMFUL
            local _, _, _, _, _, HELPFUL, HARMFUL, _, _, _ =
                fasterGetFilterFlagsForAuraInstanceId(unitTarget, auraInstanceId)
            if HARMFUL then
                char:trackEvidence('debuff', now)
            elseif HELPFUL then
                char:trackEvidence('buff', now)
            end
        end
    end

    -- Flag events tracking expiring buffs for expiration
    for _, auraInstanceId in pairs(aurasRemoved) do
        local ev = ns:getAuraEventByGUID(auraInstanceId, guid)
        if ev then
            ev:setExpiration(now)
        end
    end

    -- Final step: loop through all buffs on this character that are still not IDed.
    -- Important note: getting here means the buff has not been removed yet, so
    -- that resolution still must wait for a later UNIT_AURA event.
    ns:manageEvents("AURA", guid)
end)


--------------------------------------------------------------------------------------
-- A totally unnecessary poller to force more inference attempts. In real content,
-- there will be many inferences per second, but when nothing is happening (e.g.,
-- standing in town) some multiple-inference machinery doesn't fire.
--
-- Unlike other events, the poller isn't fired for any specific player, so manage
-- events for every tracked character.
--------------------------------------------------------------------------------------
local pollrate = 0.25
poller = C_Timer.NewTicker(pollrate, function()
    local now = GetTime()
    for guid, char in pairs(ns:getTrackedCharacters()) do
        ns:manageEvents("POLL("..pollrate..", "..guid..")", guid)
    end
end)


--------------------------------------------------------------------------------------
-- Handle initialization and group roster updates.
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
