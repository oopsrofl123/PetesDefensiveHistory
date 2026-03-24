-- get addon namespace
local addonName, ns = ...

local welcomeFrame

-- time in seconds to expire a non-buff event since there is no UNIT_AURA(removed)
-- event to naturally time it out
expireNonAuraEventsAfter = 0.5

-- Other files shouldn't directly access this
local slotToGUID = {}
local playerNameToSlot = {}
local slotToFrame = {}

-- Converting GUID -> slot (=player, party1, arena1, etc) is FOR COSMETIC
-- PURPOSES ONLY. DO NOT BASE ANY LOGIC ON UNITS.
local GUIDToSlot = {}

local myGUID

-- Return the player's GUID
function ns:myGUID()
    return myGUID
end

function ns:cosmeticOnlyMapGUIDToSlot(guid)
    return GUIDToSlot[guid]
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



local function findFrameForSlot(slot, slotRoot)
    local framesChecked = 0
    if DandersFrames then
        for _, frame in pairs(DandersFrames_GetAllFrames()) do
            framesChecked = framesChecked + 1
            if frame.unit == slot then
                return frame
            end
        end
    else
        -- Blizzard frames
        local maxN, frameRoot
        if slotRoot == 'party' then
            maxN = 5
            frameRoot = 'CompactPartyFrameMember'
        elseif slotRoot == 'raid' then
            maxN = 40
            frameRoot = 'CompactRaidFrame'
        else
            return nil
        end

        for i=1, maxN do
            framesChecked = framesChecked + 1
            if _G[frameRoot .. i].unit == slot then
                return _G[frameRoot..i]
            end
        end
    end
    ns.printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Error, string.format(
        "Couldn't find unit frame for slot=[%s], slotRoot=[%s] in [%d] frames",
        slot, slotRoot, framesChecked))
    return nil
end



-- Determine the numbers and names of slots. E.g., party1, raid2, etc. Data to keep
-- for each slot:
--      1. slot
--      2. GUID
--      3. playerName (with realm, if applicable)
--      4. unit frame object (_G[CompactPartyMember1], etc.)
local function updateTrackedSlots()
    local contentType, groupSize, slotRoot = ns:getGroupContentInfo()

    myGUID = UnitGUID("player")

    slotToGUID = {}
    slotToFrame = {}
    slotToPlayerName = {}
    GUIDToSlot = {}
    -- getSlotSet returns ['player', 'party1', ...] or ['raid1', 'raid2', ... ] for the
    -- current set of group members. Accounts for addonIsActive() state.
    for _, slot in pairs(ns:getSlotSet()) do
        if UnitExists(slot) then
            -- Unchanging player global ID
            local guid = UnitGUID(slot)

            -- Current user interface element linked to this slot
            local frame = findFrameForSlot(slot, slotRoot)

            -- Player name, hyphenated with realm if appropriate
            local playerName, realm = UnitNameUnmodified(slot)
            if realm then
                playerName = Ambiguate(playerName.."-"..realm, "none")
            end

            slotToGUID[slot] = guid
            slotToFrame[slot] = frame
            playerNameToSlot[playerName] = slot
            GUIDToSlot[guid] = slot
        end
    end
end


function ns:getTrackedSlots()
    return slotToGUID
end


function ns:playerNameToSlot(playerName)
    return playerNameToSlot[playerName]
end


function ns:slotToFrame(slot)
    return slotToFrame[slot]
end


local metadataUpdatesIndex = 0  -- index in updates table
local metadataUpdatesData = {}

function ns:getMetadataUpdatesData()
    return metadataUpdatesData
end

local function recordMetadataUpdate(trace)
    if not ns:GetOption('enableReplays') then return end

    local slotToFrameName = {}
    for slot, frame in pairs(slotToFrame) do
        slotToFrameName[slot] = frame:GetName()
    end
    local now = GetTime()
    local record = {
        time=now,
        trace=trace,
        updateId=metadataUpdatesIndex,
        myGUID=myGUID,
        slotToGUID=slotToGUID,
        playerNameToSlot=playerNameToSlot,
        slotToFrame=slotToFrameName,
        GUIDToSlot=GUIDToSlot,
        PetesDefensiveHistoryOptionsDb=PetesDefensiveHistoryOptionsDb,
    }
    metadataUpdatesData[metadataUpdatesIndex] = record
    ns:playback(now, 'METADATA_DATA_UPDATE', metadataUpdatesIndex, trace)
    metadataUpdatesIndex = metadataUpdatesIndex + 1
end


local function updateCharacterData(trace)
    -- Track newly observed characters
    for slot, guid in pairs(slotToGUID) do
        if not ns:getTrackedCharacterByGUID(guid) then
            ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal, string.format(
                "updateCharacterData(%s) -> trackCharacter(%s, %s, UnitName=%s)",
                trace, slot, guid, tostring(UnitName(slot))))
            ns:trackCharacter(slot)
        end
    end

    -- Delete characters no longer in the track set
    for guid, char in pairs(ns:getTrackedCharacters()) do
        if not GUIDToSlot[guid] then
            char:untrack()
        end
    end

    -- After all new characters are added and old characters are deleted, refresh the list
    -- of abilities targeting each player.
    for _, char in pairs(ns:getTrackedCharacters()) do
        char:setBasicInfo()
        -- XXX: TODO: the above could detect race, but does not add racial abilities.
        -- abilities are only added in response to LibSpec.
        char:cachePossibleAbilities()
    end 

    -- Track for exporting
    recordMetadataUpdate(trace)
    ns:recordCharacterDataUpdate(trace)
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
        -- does not correctly reflect that for GoAK. But maybe it is correct for others?
        -- Arcane surge is also not cancelable but returns true.
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
        inferredSpellId = nil,
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
    local availableAt
    if ability.cdr == false then
        availableAt = math.max(cdfifo:head() + ability.cooldown, event:getTime() + ability.cooldown)
    else
        -- For single charge abilities with dynamic CDR, need to ignore the previous
        -- cooldown in the FIFO. The ability was used, so it was off cooldown even though
        -- the stored end time in the FIFO may disagree (since it cannot account for CDR).
        if ability.charges == 1 then
            availableAt = event:getTime() + ability.cooldown
        else
            -- For a multi-charge CDR ability:
            --    * 1 charge was available at event:getTime() and it was used (causing
            --      this inference).
            --    * It's unknown how much recharge time has gone into the previous charge(s).
            -- XXX: TODO: we can do better than this, but it's a little complicated. Come back
            -- to it later. For now, use the worst-case scenario.
            availableAt = math.max(cdfifo:head() + ability.cooldown, event:getTime() + ability.cooldown)
        end
    end
    cdfifo:push(availableAt)
    event:setAbilityOffCooldown(availableAt)
end



-- Call this function when we are ready to fully accept whatever the best
-- inference was.
function ns:finalizeInference(ev, ability)
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
            "|cff00CDCDFINALIZED(event=[%s/%d], attempt=[%d]): [%s] cast [%s] at [%0.3f]|r",
            ev:getId(), ev:getBatchId(), ev:getInference(),
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



--====================================================================================
-- EVENT HANDLERS
--====================================================================================

local function traceHandler(event, unit, message, ...)
    fmtString = "|cFFFF55FF%s(source=[%s])"
    if message ~= nil then
        fmtString = fmtString..": "..message
    end
    fmtString = fmtString.."|r"

    ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal,
        string.format(fmtString, event, unit, ...))
end

local eventPlaybackList = {}

-- Record WoW API events for export. Very memory intensive, only meant for developers.
function ns:playback(now, event, ...)
    if not ns:GetOption('enableReplays') then return end
    local record = { now, event, ... }
    table.insert(eventPlaybackList, record)
end


function ns:getPlaybackData()
    return eventPlaybackList
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

    -- the maybe secrets probably aren't useful
    ns:playback(now, "UNIT_SPELLCAST_SUCCEEDED", caster,
        ns:maskSecret(castGUID), ns:maskSecret(spellID), ns:maskSecret(castBarId))

    traceHandler("SPELLCAST", caster, "%s, %s",
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

    ns:playback(now, "UNIT_ABSORB_AMOUNT_CHANGED", target)

    -- XXX: TODO: re-enable this later through some option. it is a uniquely
    -- spammy event.
    --traceHandler("ABSORB", target)

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

    ns:playback(now, "UNIT_FLAGS", target, inCombat)

    traceHandler("FLAGS", target, "inCombat=[%s]", tostring(inCombat))

    -- Check previously witnessed inCombat state. Did target leave combat?
    local lastInCombat = char:getEvidence('combatStatus'):head()
    -- Push the current status whether dropped or not
    char:trackEvidence('combatStatus', inCombat)

    -- FLAGS fires for reasons other than combat - e.g., mounting and dismounting
    local combatChange = tostring(lastInCombat)..">"..tostring(inCombat)
    if lastInCombat == true and inCombat == false then
        char:trackEvidence('combatDrop', now)

        local ev = ns:Event("FLAGS(combatDrop)", guid)
        -- Since this event is not tied to an aura, how long to keep it around?
        ev:setExpiration(now + expireNonAuraEventsAfter)
        ev:track()
        -- XXX: TODO: would be better to fold into Event(), but need some way to show
        -- special data like combat state or aura info in a generic event.
        ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal, string.format(
            "+++ track(FLAGS(combatDrop)): source=[%s], flagChange=[%s], eventId=[%s/%d]",
            ev:getTime(), ns:cosmeticOnlyMapGUIDToSlot(ev:getSource()),
            combatChange, ev:getId(), ev:getBatchId()))
    end
    ns:manageEvents("FLAGS", guid)
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

    traceHandler("AURA", unitTarget, "added=[%d], updated=[%d], removed=[%d]",
        #aurasAdded, #aurasUpdated, #aurasRemoved)

    -- Mode for data collecting, e.g., out of combat. Shows secret values.
    if unitTarget == "player" then
        for _, v in pairs(aurasAdded) do
            ns:printDebug(ns.LOGTYPE.DataMining, ns.LOGLEVEL.Normal,
                "DATA MINING: aura added ID=" .. v.auraInstanceID)
            if not issecretvalue(v.spellId) then
                ns:printDebug(ns.LOGTYPE.DataMining, ns.LOGLEVEL.Verbose,
                    "DATA MINING: " .. ns.compactFormatter(v))
            end
        end
        if #aurasUpdated > 0 then
            ns:printDebug(ns.LOGTYPE.DataMining, ns.LOGLEVEL.Normal,
                "DATA MINING: auraInstanceIDs updated: " .. ns.compactFormatter(aurasUpdated))
        end
        if #aurasRemoved > 0 then
            ns:printDebug(ns.LOGTYPE.DataMining, ns.LOGLEVEL.Normal,
                "DATA MINING: auraInstanceIDs removed: " .. ns.compactFormatter(aurasRemoved))
        end
    end

    local playbackFlags = {}
    -- ensure no secret data is accessed for playback
    local sanitizedAurasAdded = {}
    for _, v in pairs(aurasAdded) do
        local aura = makeAura(now, unitTarget, v.auraInstanceID, v.icon)
        playbackFlags[v.auraInstanceID] = { aura.IMPORTANT, aura.BIG, aura.EXTERNAL,
            aura.RAID, aura.RAIDINCOMBAT, aura.HELPFUL, aura.HARMFUL, aura.CANCELABLE,
            aura.HELPNAMEPLATE, aura.NAMEPLATE, aura.HARMCC, aura.CC }
        table.insert(sanitizedAurasAdded, { auraInstanceID=v.auraInstanceID,
            icon=issecretvalue(v.icon) and 134400 or v.icon })
        if aura.HELPFUL and (aura.IMPORTANT or aura.BIG or aura.EXTERNAL) then
            -- This aura is important, likely from a big cooldown
            ns:trackAura("AURA(add)", aura)
        else
            -- The aura isn't flagged, but it could be concurrent evidence
            char:trackAuraEvidence(unitTarget, v.auraInstanceID, now)
        end
    end
    if #aurasAdded > 0 then
        updateInfo['addedAuras'] = sanitizedAurasAdded
    end
    ns:playback(now, 'UNIT_AURA', unitTarget, updateInfo, playbackFlags)

    for _, auraInstanceId in pairs(aurasUpdated) do
        local ev = ns:getAuraEventByGUID(auraInstanceId, guid)
        if ev then
            if not ev:isBlocked() then
                ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal,
                    "|cff00ff00++++++++++++++ target=" .. unitTarget ..
                    ": updating " .. ev:getId() .. "|r")
                local newEv = ns:trackAura("AURA(update)", ev:getAura()) -- aura is always present
                newEv:setUpdate()  -- this is an update event
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
--local pollrate = 2 --0.25
--poller = C_Timer.NewTicker(pollrate, function()
    --local now = GetTime()
    --for guid, char in pairs(ns:getTrackedCharacters()) do
        --ns:manageEvents("POLL("..pollrate..", "..ns:cosmeticOnlyMapGUIDToSlot(guid)..")", guid)
    --end
--end)


--------------------------------------------------------------------------------------
-- Detect when m+ keys and raid encounters start. Not sure what else triggers this.
-- Does nothing for now.
--------------------------------------------------------------------------------------

-- XXX: Not sure 
--local encounterHandler = CreateFrame("Frame", addonName .. "EncounterLoader")
--encounterHandler:RegisterEvent("ENCOUNTER_START")
--encounterHandler:SetScript("OnEvent", function(self, event, encounterID, encounterName, difficultyID, groupSize)
    --print(event, encounterID, encounterName, difficultyID, groupSize)
--end)


--------------------------------------------------------------------------------------
-- Handle initialization and group roster updates.
--------------------------------------------------------------------------------------
local loader = CreateFrame("Frame", addonName .. "Loader")

local function initAddon()
    -- Prevent this from happening again
    loader:UnregisterEvent("ADDON_LOADED")

    ns:printDebug(ns.LOGTYPE.UI, ns.LOGLEVEL.Normal,
        "Initializing "..addonName..", addonIsActive()=" ..
        tostring(ns:addonIsActive()))

    -- Set to the opposite of the user setting to force a transition into the
    -- desired state.
    lastActiveState = not ns:addonIsActive()
    lastReplayState = ns:GetOption('enableReplays')

    -- Add precomputed flag strings to the abilities in AbilityDb so they don't have to be
    -- recomputed on each inference.
    ns.AbilityIdMap = {}  -- Provide an unnested spell ID -> ability map
    for category, abilities in pairs(ns.AbilityDb) do
        for _, ability in pairs(abilities) do
            ability.flags = ns:flagString(ability)
            ns.AbilityIdMap[ability.id] = ability
        end
    end

    -- Addons are loaded after all blizzard frames, so can allocate everything now.
    ns:allocTrackerUI()
    ns.groupSolutionUI = ns:allocGroupSolutionUI()
    ns.groupSolutionUI:Hide()
end


-- Unlike the other handler frames, `loader` should never be unregistered. Explanation
-- copied from below.
-- Do not unregister the main `loader` handler's events. It needs to remain registered
-- to detect later changes in group/instance state to auto-en/disable the addon as the
-- user prefers.
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("GROUP_ROSTER_UPDATE")
loader:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
loader:RegisterEvent("ZONE_CHANGED_NEW_AREA")
-- XXX: TODO: haven't ever tested arena, but some functionality could work. main problem
-- is I doubt LibSpecialization would return talent strings for arena enemies, meaning
-- available cooldowns/durations would be unknown.
--loader:RegisterEvent("ARENA_OPPONENT_UPDATE")
--loader:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS")
local loadNum = 1
loader:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        initAddon()
        -- XXX: TODO: useful when debugging options
        -- Can't open the options pane while reading in the addon since saved variables
        -- aren't loaded til ADDON_LOADED.
        --Settings.OpenToCategory(ns.optionsCategory:GetID())
    end

    ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal, event.."("..loadNum..")")
    loadNum = loadNum + 1

    ns:handleAddonActiveStateChange()

    if ns:addonIsActive() then
        -- Get the player that triggered the event
        if event == "PLAYER_SPECIALIZATION_CHANGED" then
            slot = select(1, ...)
            guid = tostring(slotToGUID[slot])  -- might not be populated eyt
            event = string.format("%s(%s,%s)", event, slot, guid)
        end
        ns:respondToRosterUpdate(event)
    end

    if not ns:GetOption('hideWelcomeMessage') then
        welcomeFrame:Show()
    else
        welcomeFrame:Hide()
    end

    ns:playback(GetTime(), event, ...)
end)



function ns:respondToRosterUpdate(trace)
    updateTrackedSlots()
    updateCharacterData(trace)
    ns:updateTrackerUI()         -- Update UI elements
    ns:updateGroupSolutionUI()
end



-- Handle enabling/disabling addon activity. The active state can be changed because
-- the user changed a preference or the character moved from content where the addon
-- is active (e.g., party) into content where it is inactive (e.g., raid).
--
-- Call this function any time the active state *may* have changed. It will determine
-- whether it did and execute accordingly. MUST BE A NO-OP IF NOTHING CHANGED.
function ns:handleAddonActiveStateChange()
    if not lastActiveState and ns:addonIsActive() then
        ns:enableAddon()
    elseif lastActiveState and not ns:addonIsActive() then
        ns:disableAddon()
    end
end



-- When a user enables replays, must fire character and metadata collection updates manually
-- since there is no game event triggered.
function ns:handleReplayStateChange()
    local state = ns:GetOption('enableReplays')
    if not lastReplayState and state then
        recordMetadataUpdate('enableReplays -> true')
        ns:recordCharacterDataUpdate('enableReplays -> true')
    elseif lastReplayState and not state then
        -- nothing for now
    end
    lastReplayState = state
end



function ns:enableAddon()
    loadNum = 1
    ns:printMemUsage("enableAddon: before constructing UI")
    auraHandler:RegisterEvent("UNIT_AURA")
    castHandler:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    absorbHandler:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    flagsHandler:RegisterEvent("UNIT_FLAGS")
    --poller:Invoke()

    ns:respondToRosterUpdate('enableAddon')
    ns:sendLibSpecRequest()
    ns:printMemUsage("enableAddon: after constructing UI")
    if ns:GetOption('runGC') then
        collectgarbage('collect')
        ns:printMemUsage("enableAddon: after constructing UI and running GC")
    end

    lastActiveState = true
end



function ns:disableAddon()
    ns:printMemUsage("disableAddon: before deconstructing UI and deleting data")
    -- Do not unregister the main `loader` handler's events. It needs to remain registered
    -- to detect later changes in group/instance state to auto-en/disable the addon as the
    -- user prefers.
    auraHandler:UnregisterEvent("UNIT_AURA")
    castHandler:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    absorbHandler:UnregisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    flagsHandler:UnregisterEvent("UNIT_FLAGS")
    --poller:Cancel()

    ns:respondToRosterUpdate('disableAddon')
    ns:printMemUsage("disableAddon: after deconstructing UI and deleting data")
    if ns:GetOption('runGC') then
        collectgarbage('collect')
        ns:printMemUsage("disableAddon: after deconstructing UI and deleting data with optional GC")
    end

    lastActiveState = false
end



local function allocWelcomeFrame()
    local f = CreateFrame("Frame", "PetesDefensiveHistoryWelcome", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(700, 350)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    -- Bring to front when clicked
    f:SetScript("OnMouseDown", function(self) self:Raise() end)

    f.TitleText:SetText(addonName)

    -- no need to use pools here, this is once only
    local welcomeText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    welcomeText:SetPoint("TOPLEFT", f.InsetBg, "TOPLEFT", 10, -10)
    welcomeText:SetPoint("TOPRIGHT", f.InsetBg, "TOPRIGHT", -10, -10)
    welcomeText:SetJustifyH("CENTER")
    welcomeText:SetSpacing(4)
    welcomeText:SetText("Welcome to |cFF00FF00"..addonName.."|r, an addon for tracking group cooldowns!")

    
    local discordText = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    discordText:SetPoint("TOP", welcomeText, "BOTTOM", 0, -30)
    discordText:SetPoint("LEFT", f.InsetBg, "LEFT", 10, 0)
    discordText:SetPoint("RIGHT", f.InsetBg, "RIGHT", -10, 0)
    discordText:SetJustifyH("LEFT")
    discordText:SetSpacing(4)
    discordText:SetText("Join the Discord and help improve " ..
        "cooldown guessing accuracy by reporting bugs and inaccurate timers!")

    local link = "|cFF00FFFFhttps://discord.gg/gVCtQrvpxt|r"
    local urlBox = CreateFrame("EditBox", nil, f)
    urlBox:SetPoint("TOP", discordText, "BOTTOM", 0, -10)
    urlBox:SetSize(300, 20)
    urlBox:SetText(link)
    urlBox:SetFontObject("GameFontNormalLarge")
    urlBox:SetJustifyH("CENTER")
    urlBox:SetAutoFocus(true)
    urlBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    urlBox:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
    urlBox:SetScript("OnChar", function(self)
 print('onchar')
        self:SetText(link)
        self:HighlightText()
    end)

    local tracerText = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    tracerText:SetPoint("TOP", urlBox, "BOTTOM", 0, -25)
    tracerText:SetPoint("LEFT", f.InsetBg, "LEFT", 10, 0)
    tracerText:SetPoint("RIGHT", f.InsetBg, "RIGHT", -10, 0)
    tracerText:SetJustifyH("LEFT")
    tracerText:SetSpacing(4)
    tracerText:SetText("|cFFFFFFFFEnable logic tracing and replays|r " ..
        "(AddOn Options > Developer options > Enable logic replays) for serious bug " ..
        "tracking power. To share your replay, click the addon compartment button (top " ..
        "right, near the minimap) and copy the export string.\n" ..
        "|cFFFF0000WARNING: currently a memory hog, you will want to /reload " ..
        "between keys!")

    local checkbox = CreateFrame("CheckButton", "Checkbox", f, "UICheckButtonTemplate")
    checkbox:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
    checkbox.text:SetText("Don't show this message again")
    checkbox.text:SetFontObject("GameFontNormal")
    checkbox:SetChecked(ns:GetOption('hideWelcomeMessage'))
    checkbox:SetScript("OnClick", function(self)
        ns.hideWelcomeMessage:SetValue(self:GetChecked())
    end)

    f:Hide()

    return f
end



do
    welcomeFrame = allocWelcomeFrame()

    -- Open the solution UI
    SLASH_PDH1 = "/pdh"
    -- Open the config panel
    -- SlashCmdList.PDH = function() Settings.OpenToCategory(ns.optionsCategory:GetID()) end
    SlashCmdList.PDH = function() ns.groupSolutionUI:Show() end
end
