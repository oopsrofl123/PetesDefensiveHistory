-- get addon namespace
local addonName, ns = ...

-- time in seconds to expire a non-buff event since there is no UNIT_AURA(removed)
-- event to naturally time it out
expireNonAuraEventsAfter = 0.5

-- Other files shouldn't directly access this
local slotToGUID = {}
-- Converting GUID -> slot (=player, party1, arena1, etc) is FOR COSMETIC
-- PURPOSES ONLY. DO NOT BASE ANY LOGIC ON UNITS.
local GUIDToSlot = {}

function ns:cosmeticOnlyMapGUIDToSlot(guid)
    return GUIDToSlot[guid] or "unknown"
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
            GUIDToSlot[guid] = slot
            -- Is this the first time we've seen this guid?
            if not ns:getTrackedCharacterByGUID(guid) then
print("updateSlotToGUID -> trackCharacter("..tostring(index)..", "..tostring(slot)..", "..tostring(guid)..", UnitName="..UnitName(slot)..")")
                ns:trackCharacter(slot)
            end
        else
            -- Since the character is no longer in the group (UnitExists=false),
            -- can't map slot-> GUID. So have to reverse-lookup the slot in the
            -- GUIDToSlot table to delete it
            local staleGUID = slotToGUID[slot]
            slotToGUID[slot] = nil
            for k, v in pairs(GUIDToSlot) do
                if v == slot then
                    GUIDToSlot[v] = nil
                end
            end
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


-- Convenience functions: speed up some specific cases that only care about one flag
function ns:isBuff(slot, auraInstanceId)
    return not C_UnitAuras.IsAuraFilteredOutByInstanceID(slot, auraInstanceId, "HELPFUL")
end

function ns:isDebuff(slot, auraInstanceId)
    return not C_UnitAuras.IsAuraFilteredOutByInstanceID(slot, auraInstanceId, "HARMFUL")
end


local function fasterGetFilterFlagsForAuraInstanceId(slot, auraInstanceId)
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
        -- Some auras we track are not cancelable (like GoAK). Unfortunately this filter
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
    }
    -- Precompute the flag string, which is just concatenated 1s and 0s of the flags
    -- we actually match on. Makes comparisons and record keeping easier.
    aura.flags = ns:flagString(aura)

    ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal,
        string.format("auraID=%d: %s %d%d CANCEL: %d NAMEPLATE: %d%d CC: %d%d",
            aura.auraInstanceId, aura.flags,
            ns:boolstr(aura.HELPFUL), ns:boolstr(aura.HARMFUL), ns:boolstr(aura.CANCELABLE),
            ns:boolstr(aura.HELPNAMEPLATE), ns:boolstr(aura.NAMEPLATE),
            ns:boolstr(aura.HARMCC), ns:boolstr(aura.CC)))

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
        ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal,
            "+++ Running special onFinalize("..ability.name..")")
        ev.onFinalize(ev, ability)
    end

    ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal,
        string.format(
            "|cff00CDCDFINALIZED(time=[%0.3f], event=[%s/%d], attempt=[%d]): [%s] cast [%s] at [%0.3f]|r",
            GetTime(), ev:getId(), ev:getBatchId(), ev:getInference(),
            ns:cosmeticOnlyMapGUIDToSlot(ability.caster),
            ability.alias or ability.name, ev:getTime()))

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
                ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal,
                    "applying BoP/spellwarding cooldown hack")
                trackCooldown(ev, otherAbility) -- doesn't alter event
                ns:queueCooldown(otherAbility)
            end
        end
    end
end



-- What to do when the event expires (or is replaced)? If there was a certain inference,
-- track in the static cooldown row, otherwise dump it in the history tray.
-- Since dynamic CDR ability timers are rarely accurate, allow users to
-- send those to the history tray instead. This doesn't prevent them from
-- being glowed while active.
local function eventExpiredOrReplaced(ev)
    local ability, certain = ev:getAbility()
    if ability and certain and not (ability.cdr and ns:GetOption('disableCDRTrackers')) then
        ns:queueCooldown(ability)
    elseif not ev:isNonAuraEvent() then
        -- Can't add these for two reasons: (1) non-aura events don't have a texture to show,
        -- (2) many non-aura events fire that aren't interesting. E.g., every time anyone leaves
        -- combat is a non-aura event. Some of those are vanishes and shadowmelds but most are
        -- nothing.
        ns:addEventToHistoryTray(ev)
    end
end



-- Main update function for tracked events. Runs inference if appropriate and
-- removes them from tracking when their lifetime is over.
function ns:inferAndAct(inferenceTrace, ev, now)
    if not ev:isCertain() and (ev:isExpiring() or not ev.forceFullDuration) then
        ev:prepareForInference()
        local ability, certain = ns:inferAbility(inferenceTrace, ev, ns.cdTracker)
        if certain then
            finalizeInference(ev, ability)
        elseif ability and not certain then
            ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal,
                string.format(
                    "|cff00CDCDUNCERTAIN(time=[%0.3f], event=[%s/%d], attempt=[%d]): [%s] cast [%s] at time [%0.3f]|r",
                    now, ev:getId(), ev:getBatchId(), ev:getInference(),
                    ns:cosmeticOnlyMapGUIDToSlot(ability.caster),
                    ability.alias or ability.name, ev:getTime()))
        end
        if ability and not ev:isExpiring() then
            ns:startGlow(ev:getAuraAbility())
        end
    end

    -- handle end of life for all events
    if ev:isExpiring() then
        local ability, certain = ev:getAbility()
        if ability then
            ns:stopGlow(ev:getAuraAbility())
        end
        eventExpiredOrReplaced(ev)
        ev:untrack()
    end
end



--====================================================================================
-- EVENT HANDLERS
--====================================================================================

local function traceHandler(event, now, unit, message, ...)
    --fmtString = "|cFFEB4EF7%s(time=[%0.3f], source=[%s])"
    fmtString = "|cFFFF55FF%s(time=[%0.3f], source=[%s])"
    if message ~= nil then
        fmtString = fmtString..": "..message
    end
    fmtString = fmtString.."|r"

    ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal,
        string.format(fmtString, event, now, unit, ...))
end


--------------------------------------------------------------------------------------
-- Track player spell casts
--------------------------------------------------------------------------------------
local castHandler = CreateFrame("Frame", addonName .. "CastHandler")
castHandler:SetScript("OnEvent", function(self, event, caster, castGUID, spellID, castBarID)
    -- Only track casts from tracked characters
    local guid, char = ns:getTrackedCharacterBySlot(caster)
    if not guid then return end
    local now = GetTime()

    traceHandler("SPELLCAST", now, caster, "%s, %s",
        tostring(ns:maskSecret(spellID)), tostring(ns:maskSecret(castBarID)))

    char:trackEvidence('cast', now)

    ns:manageEvents("CAST", guid)
end)


--------------------------------------------------------------------------------------
-- Track when absorb shields are applied
--------------------------------------------------------------------------------------
local absorbHandler = CreateFrame("Frame", addonName .. "AbsorbHandler")
absorbHandler:SetScript("OnEvent", function(self, event, target)
    -- Only track casts from tracked characters
    local guid, char = ns:getTrackedCharacterBySlot(target)
    if not guid then return end
    local now = GetTime()

    traceHandler("ABSORB", now, target)

    char:trackEvidence('shield', now)

    ns:manageEvents("ABSORB", guid)
end)


--------------------------------------------------------------------------------------
-- Track when unit flags change
--------------------------------------------------------------------------------------
local flagsHandler = CreateFrame("Frame", addonName .. "UnitFlagsHandler")
flagsHandler:SetScript("OnEvent", function(self, event, target)
    -- Only track casts from tracked characters
    local guid, char = ns:getTrackedCharacterBySlot(target)
    if not guid then return end
    local now = GetTime()

    local inCombat = UnitAffectingCombat(target)
    traceHandler("FLAGS", now, target, "inCombat=[%s]", tostring(inCombat))

    -- Check previously witnessed inCombat state. Did target leave combat?
    local lastInCombat = char:getEvidence('combatStatus'):head()
    -- Push the current status whether dropped or not
    char:trackEvidence('combatStatus', inCombat)

    if lastInCombat == true and inCombat == false then
        char:trackEvidence('combatDrop', now)

        local ev = ns:Event("FLAGS", guid)
        -- Since this event is not tied to an aura, how long to keep it around?
        ev:setExpiration(now + expireNonAuraEventsAfter)
        ev:track()
    end
    ns:manageEvents("FLAGS("..tostring(lastInCombat)..">"..tostring(inCombat)..")", guid)
end)


--------------------------------------------------------------------------------------
-- Track when auras are applied, updated or removed
--------------------------------------------------------------------------------------
local auraHandler = CreateFrame("Frame", addonName .. "AuraHandler")
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

    traceHandler("AURA", now, unitTarget, "added=[%d], updated=[%d], removed=[%d]",
        #aurasAdded, #aurasUpdated, #aurasRemoved)

    -- Mode for data collecting, e.g., out of combat. Shows secret values.
    if unitTarget == "player" then
        for _, v in pairs(aurasAdded) do
            ns:printDebug(ns.LOGTYPE.DataMining, ns.LOGLEVEL.Normal,
                "DATA MINING: aura added ID=" .. v.auraInstanceID)
            if not issecretvalue(v.spellId) then
                ns.compactPrinter(v)
            end
        end
        ns:printDebug(ns.LOGTYPE.DataMining, ns.LOGLEVEL.Normal,
            "DATA MINING: auraInstanceIDs updated: " .. ns.compactFormatter(aurasUpdated))
        ns:printDebug(ns.LOGTYPE.DataMining, ns.LOGLEVEL.Normal,
            "DATA MINING: auraInstanceIDs removed: " .. ns.compactFormatter(aurasRemoved))
    end

    for _, v in pairs(aurasAdded) do
        local aura = makeAura(now, unitTarget, v.auraInstanceID, v.icon)
        if aura.HELPFUL and (aura.IMPORTANT or aura.BIG or aura.EXTERNAL) then
            -- This aura is important, likely from a big cooldown
            ns:trackAura("AURA(add)", aura)
        else
            -- The aura isn't flagged, but it could be concurrent evidence
            char:trackAuraEvidence(unitTarget, v.auraInstanceID, now)
        end
    end

    for _, auraInstanceId in pairs(aurasUpdated) do
        local ev = ns:getAuraEventByGUID(auraInstanceId, guid)
        if ev then
            ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal,
                "|cff00ff00++++++++++++++ target=" .. unitTarget ..
                ": updating " .. ev:getId() .. "|r")

            -- Screen out one very specific case: abilities that are known to naturally
            -- update but have only 1 charge. E.g., Sentinel.
            local ability, certain = ev:getAbility()
            if not ability or not (certain and ability.charges < 2 and ability.naturallyUpdates) then
                -- XXX: TODO: likely violates assumptions about certain inferences.  needs testing.
                -- make an event no matter what. let inferBatch figure out what it all means.
                local aura = ev:getAura()     -- This is an AuraEvent. There is always an aura.
                local newAura = makeAura(now, unitTarget, aura.auraInstanceId, aura.secretTexture)
                ns:trackAura("AURA(update)", newAura)
            end
        else
            -- concurrent buff/debuff evidence can also come from updates.
            -- E.g., warrior thunder blast stacks: these can be farmed outside of Avatar
            -- but are also awarded when pressing avatar.
            char:trackAuraEvidence(unitTarget, auraInstanceId, now)
        end
    end

    -- Aura expiration is when the associated event expires
    for _, auraInstanceId in pairs(aurasRemoved) do
        ns:expireAuraEventByGUID(auraInstanceId, guid, now)
    end

    -- Run inference on all outstanding events for this character
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
local pollrate = 2 --0.25
poller = C_Timer.NewTicker(pollrate, function()
    local now = GetTime()
    for guid, char in pairs(ns:getTrackedCharacters()) do
        ns:manageEvents("POLL("..pollrate..", "..ns:cosmeticOnlyMapGUIDToSlot(guid)..")", guid)
    end
end)


--------------------------------------------------------------------------------------
-- Handle initialization and group roster updates.
--------------------------------------------------------------------------------------
local loader = CreateFrame("Frame", addonName .. "Loader")
local loadNum
loader:SetScript("OnEvent", function(self, event)
    ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal, event.."("..loadNum..")")
    loadNum = loadNum + 1
    ns:respondToRosterUpdate()
    ns:handleAddonActiveStateChange()
end)


function ns:respondToRosterUpdate()
    updateSlotToGUID()           -- Maintain the slot -> GUID map
    ns:updateTrackerUI()         -- Update UI elements
    ns:updateGroupSolutionUI()

    for index=1, 5 do
        ns.trackerUI[index]:Show()
    end
end



-- Handle enabling/disabling addon activity. The active state can be changed because
-- the user changed a preference or the character moved from content where the addon
-- is active (e.g., party) into content where it is inactive (e.g., raid).
--
-- Call this function any time the active state *may* have changed. It will determine
-- whether it did and execute accordingly
function ns:handleAddonActiveStateChange()
    if not lastActiveState and ns:addonIsActive() then
        ns:enableAddon()
    elseif lastActiveState and not ns:addonIsActive() then
        ns:disableAddon()
    end
end



function ns:enableAddon()
    loadNum = 1
    ns:printMemUsage("enableAddon: before constructing UI")
    loader:RegisterEvent("PLAYER_ENTERING_WORLD")
    loader:RegisterEvent("GROUP_ROSTER_UPDATE")
    loader:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    auraHandler:RegisterEvent("UNIT_AURA")
    castHandler:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    absorbHandler:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    flagsHandler:RegisterEvent("UNIT_FLAGS")
    poller:Invoke()

    ns:respondToRosterUpdate()
    ns:sendLibSpecRequest()
    ns:printMemUsage("enableAddon: after constructing UI")
    if ns:GetOption('runGC') then
        ns:printMemUsage("enableAddon: after constructing UI and running GC")
        collectgarbage('collect')
    end

    lastActiveState = true
end



function ns:disableAddon()
    loader:UnregisterEvent("PLAYER_ENTERING_WORLD")
    loader:UnregisterEvent("GROUP_ROSTER_UPDATE")
    auraHandler:UnregisterEvent("UNIT_AURA")
    castHandler:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    absorbHandler:UnregisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    flagsHandler:UnregisterEvent("UNIT_FLAGS")
    poller:Cancel()

    for index=1, 5 do
        ns.trackerUI[index]:Hide()
        local slot = ns:indexToSlot(index)
        if slot then
            slotToGUID[slot] = nil
            local guid, char = ns:getTrackedCharacterBySlot(slot)
            if guid then
                char:untrack()
            end
        end
    end

    lastActiveState = false
end


do
    -- Add precomputed flag strings to the abilities in AbilityDb so they don't have to be
    -- recomputed on each inference.
    for category, abilities in pairs(ns.AbilityDb) do
        for _, ability in pairs(abilities) do
            ability.flags = ns:flagString(ability)
        end
    end

    -- Addons are loaded after all blizzard frames, so can allocate everything now.
    ns:allocHistoryGrid()
    ns.groupSolutionUI = ns:allocGroupSolutionUI()

    -- Open the solution UI
    SLASH_PDH1 = "/pdh"
    -- Open the config panel
    -- SlashCmdList.PDH = function() Settings.OpenToCategory(ns.optionsCategory:GetID()) end
    SlashCmdList.PDH = function() ns.groupSolutionUI:Show() end

    -- Set up by default. Options aren't loaded yet, so can't check the user's preference.
    ns:enableAddon()
    Settings.OpenToCategory(ns.optionsCategory:GetID())
end
