-- Get class specs for each group member

local _, ns = ...


-- an evidence tracker for each tracked character. The data is stored in
-- Character()s, this is just a convenience to prevent another loop over all
-- tracked characters for every inference.
local evidenceTrackersByGUID = {}

-- Retain EVIDENCE_HISTORY_SIZE records of each tracked event type for each
-- character. Must
-- loop over all of these on every inference, so don't make it too
-- large, but must be large enough to cover a reasonably large time interval.
--
-- XXX: TODO: Increasing the evidence queue size. Some abilities generate really
-- massive numbers of events (bubble taunt generates a zillion SPELLCASTs).
-- The correct solution is probably to check :head() and refuse to push duplicate
-- time stamps..
local EVIDENCE_HISTORY_SIZE = 12

-- Make an empty event tracker
function ns:makeEvidenceTracker()
    return {
        buff=ns:fixedFIFO(EVIDENCE_HISTORY_SIZE),
        debuff=ns:fixedFIFO(EVIDENCE_HISTORY_SIZE),
        cast=ns:fixedFIFO(EVIDENCE_HISTORY_SIZE),
        castFailedQuiet=ns:fixedFIFO(EVIDENCE_HISTORY_SIZE),
        shield=ns:fixedFIFO(EVIDENCE_HISTORY_SIZE),
        -- Booleans of the last observed combat status (no time associated)
        combatStatus=ns:fixedFIFO(EVIDENCE_HISTORY_SIZE),
        -- Times when combatStatus changed from true->false
        combatDrop=ns:fixedFIFO(EVIDENCE_HISTORY_SIZE),
        unitFlags=ns:fixedFIFO(EVIDENCE_HISTORY_SIZE),
        feignStatus=ns:fixedFIFO(EVIDENCE_HISTORY_SIZE),
        feign=ns:fixedFIFO(EVIDENCE_HISTORY_SIZE),
        maybeFreedom=ns:fixedFIFO(EVIDENCE_HISTORY_SIZE),
        freedom=ns:fixedFIFO(EVIDENCE_HISTORY_SIZE),
        died=ns:fixedFIFO(EVIDENCE_HISTORY_SIZE),
        debuffRemoved=ns:fixedFIFO(EVIDENCE_HISTORY_SIZE),
    }
end        

function ns:getEvidenceTrackers()
    return evidenceTrackersByGUID
end



-- list of all relevant characters
local trackedCharacters = {}

-- save a copy of all character metadata on every event that triggers updates.
-- e.g., GROUP_ROSTER_UPDATE, LibSpec callbacks, etc. Each update requires a fairly
-- large amount of memory, so disable this later.
-- XXX: TODO: disable later via options
local characterUpdatesIndex = 0
local characterUpdatesData = {}


function ns:recordCharacterDataUpdate(trace)
    -- XXX: store this metadata regardless. maybe re-enable in the future
    --if not ns:GetOption('enableReplays') then return end

    local characters = {}
    for _, char in pairs(ns:getTrackedCharacters()) do
        table.insert(characters, char:export())
    end
    local now = GetTime()
    characterUpdatesData[characterUpdatesIndex] = { now, trace, characters }
    ns:playback(now, "CHARACTER_DATA_UPDATE", characterUpdatesIndex, trace)
    characterUpdatesIndex = characterUpdatesIndex + 1
end


function ns:clearCharacterUpdatesData()
    characterUpdatesData = {}
end


function ns:getCharacterUpdatesData()
    return characterUpdatesData
end


function ns:getTrackedCharacterByGUID(guid)
    -- protect the call if guid=nil: return nil
    -- XXX: TODO: it might be more elegant to return an empty character
    return guid and trackedCharacters[guid] or nil
end

function ns:getTrackedCharacters()
    return trackedCharacters
end



-- Create a character object for the group/raid member in `slot`.
-- `slot` - "player", "party1", etc. Don't save the slot used on
-- creation, it's only guaranteed to be relevant at that time.
-- If slot is nil, make an empty character
function ns:Character(slot)
    local char = {}   -- the character object
    local GUID = "empty"
    local name = "empty"
    local className = "empty"
    local classFile = nil
    local englishRaceName = nil  -- unique and locale-independent, valid db key
    local raceId = nil
    local specId = nil
    local specName = nil
    local talentExportString = nil
    local talentRanks = nil
    local abilities = {}
    local possibleAbilities = {}
    local evidenceTracker = ns:makeEvidenceTracker()
    local hasLibSpec = false
    local activeAuras = {}


    -- Unlike inference records/events, the amount of character data stored doesn't grow
    -- over time. There's no need to strip keys out of tables to save space. Here, just
    -- choose what data to export. Main exclusions are runtime data like cooldown trackers
    -- and evidence trackers - these contain data for very short windows and so aren't
    -- useful.
    function char:export()
        return {
            GUID=GUID,
            playerName=name,
            classFile=classFile,
            raceName=englishRaceName,
            raceId=raceId,
            specId=specId,
            specName=specName,
            talentExportString=talentExportString,
            hasLibSpec=hasLibSpec,
            talentRanks=talentRanks,
            abilities=abilities,
            possibleAbilities=possibleAbilities,
        }
    end

    -- Unsettable values --------------------------------------------------------
    -- Return the stable ID that is unique across factions and servers. This is
    -- safe to record because it will never change. Also, since it is stable, it
    -- is a valid key into the global table of characters, allowing string->Character
    -- fetching.
    function char:getID() return GUID end

    -- Return the player's name
    function char:getName() return name end

    -- Return the locale-independent class name, suitable as a key for tables
    function char:getClassFile() return classFile end

    function char:getRaceId() return raceId end

    -- Return the class color for this character as a triplet (r,g,b)
    -- Suitable as direct input in: SetColor(getClassColor())
    function char:getClassColor()
        if classFile then
            -- RAID_CLASS_COLORS returns a table with lots of other info in it. Have to
            -- pare down to just r, g, b.
            local coldata = RAID_CLASS_COLORS[classFile]
            return coldata.r, coldata.g, coldata.b
        else
            return 1, 1, 1
        end
    end

    function char:hasLibSpec() return hasLibSpec end

    -- For testing: ignore real evidence and always assign this character perfect
    -- evidence.
    function char:hasPerfectEvidence() return perfectEvidence end

    function char:setPerfectEvidence() perfectEvidence = true end

    function char:setBasicInfo(slot)
        slot = slot or ns:cosmeticOnlyMapGUIDToSlot(GUID)
        name = UnitName(slot)
        className, classFile, _ = UnitClass(slot)
        _, englishRaceName, raceId = UnitRace(slot)
        ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal, string.format(
            "Character(%s,%s): name=[%s], class=[%s], raceName=[%s]",
            slot, GUID, name, tostring(classFile), tostring(raceId), tostring(englishRaceName)))
    end


    -- Settable values ----------------------------------------------------------
    -- Abilities, spec and talents are all downstream of setting spec and talents.
    -- Setting these resolves all of the downstream
    function char:setSpecAndTalents(spec, tstring)
        specId = spec
        hasLibSpec = tstring ~= nil

        -- Try this again. Often fails when zoning into LFG.
        -- XXX: TODO: i think this needs to return nil, signaling a need to try again later
        -- if classFile or englishRaceName are- still nil.
        self:setBasicInfo()

        -- This can disagree with UnitClass() because specId is derived from a LibSpec
        -- callback. The LibSpec callback is more reliable than UnitClass, so prefer it.
        _, specName, _, _, _, classFile, className = GetSpecializationInfoByID(specId)

        talentExportString = tstring

        talentRanks = ns:getTalentRanks(specId, talentExportString)

        -- clear these out. this could be a spec change
        abilities = {}
        possibleAbilities = {} -- not computed here, just cleared
        for _, baseAbility in pairs(ns.AbilityDb[classFile]) do
            local ability = ns:applyTalentModifiers(classFile, specId, baseAbility, talentRanks)
            if ability.hasAbility then
                ability.caster = GUID
                table.insert(abilities, ability)
            end
        end

        -- Add racials
        for _, baseAbility in pairs(ns.AbilityDb[englishRaceName] or {}) do
            local ability = ns:shallowcopy(baseAbility) -- no talents
            ability.hasAbility = true  -- XXX: TODO: this won't be true for evoker CC racials
            if ability.hasAbility then
                ability.caster = GUID
                table.insert(abilities, ability)
            end
        end

        -- Sort the externals to the end. Just for nicer visualization, no functional effect.
        table.sort(abilities,
            function(a, b) return (a.EXTERNAL and 1 or 0) < (b.EXTERNAL and 1 or 0) end)
    end

    function char:getSpec() return specId end

    function char:getSpecString() return tostring(specName).." "..tostring(className) end

    function char:getTalents() return talentRanks end

    function char:hasTalentData() return talentRanks ~= nil end

    -- If `target` is nil, return a named list of all abilities castable by
    -- this character. Otherwise, return all abilities this character can cast
    -- on `target`.
    function char:getAbilities(target)
        local results = {}
        for _, ability in pairs(abilities) do
            if target == nil or
               (ability.targets == ns.TARGET_ANY) or
               (ability.targets == ns.TARGET_SELF and target == GUID) or
               (ability.targets == ns.TARGET_OTHERS and target ~= GUID) then
                results[ability.name] = ability
            end
        end
        return results
    end

    -- Build a list of every ability that could be cast on this character from any
    -- tracked character (i.e., just party members for now). Since this depends on
    -- OTHER characters, it needs to be called every time any tracked character changes.
    function char:cachePossibleAbilities()
        possibleAbilities = {}
        for _, char in pairs(trackedCharacters) do
            local numAuraProviders = {} 
            for _, ability in pairs(char:getAbilities(GUID)) do
                local appliedId = ability.appliesOtherAura or ability.id
                numAuraProviders[appliedId] = (numAuraProviders[appliedId] or 0) + ability.charges 
                table.insert(possibleAbilities, ability)
            end
            -- pass 2: cache the number of abilities providing this aura
            for _, ability in pairs(char:getAbilities(GUID)) do
                local appliedId = ability.appliesOtherAura or ability.id
                ability.numAuraProviders = numAuraProviders[appliedId]
            end
        end
        ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Verbose,
            "cached "..#possibleAbilities.." targeting character=["..name.."]")
    end

    function char:getPossibleAbilities() return possibleAbilities end

    -- Stop tracking the character
    function char:untrack()
        ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal,
            string.format("DELETING ALL DATA for character name=[%s], GUID=[%s]",
            name, GUID))
        trackedCharacters[GUID] = nil
        -- XXX: TODO: hack until these are formally folded into Character
        ns.eventsForInference[GUID] = nil
        ns.cdTracker[GUID] = nil
        evidenceTrackersByGUID[GUID] = nil
    end


    function char:trackEvidence(evidenceType, value)
        evidenceTracker[evidenceType]:push(value)
    end

    -- IMPORTANT!! some auras are returned by neither the helpful nor harmful
    -- filters. This does not necessarily agree with isHelpful or isHarmful
    -- annotations in this payload (which are secret anyway).
    -- If you think an aura should be present in the trackers but isn't, it likely
    -- is neither HELPFUL nor HARMFUL. Example: coagulating blood (id=463730)
    function char:trackAuraEvidence(slot, auraInstanceId, now, helpful, harmful, spellId)
        if helpful then
            char:trackEvidence('buff', now)
        elseif harmful then
            char:trackEvidence('debuff', now)
        end
        activeAuras[auraInstanceId] = { helpful, harmful, spellId }  -- likely secret
    end

    -- important auras are not aura evidence, so activesAuras[ID] will return nil
    -- returns nil, nil in that case
    function char:queryAuraEvidence(auraInstanceId)
        local helpful, harmful, spellId = unpack(activeAuras[auraInstanceId] or {})
        return helpful, harmful, spellId
    end

    -- important auras are not aura evidence, so activesAuras[ID] will return nil
    -- returns nil, nil in that case
    function char:untrackAuraEvidence(auraInstanceId)
        local helpful, harmful, spellId = unpack(activeAuras[auraInstanceId] or {})
        activeAuras[auraInstanceId] = nil
        return helpful, harmful, spellId
    end

    function char:getEvidence(evidenceType)
        return evidenceTracker[evidenceType]
    end

    function char:getEvidenceTracker()
        return evidenceTracker
    end


    -- If this isn't an empty character, start populating it
    if slot and UnitExists(slot) then
        GUID = UnitGUID(slot) or
            ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Error,
                "Character("..slot.."): could not get GUID") -- Should error, not recoverable

        ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal, string.format(
            "Character(%s): new character with GUID=[%s]", slot, GUID))

        char:setBasicInfo(slot)
    else
        if not slot then
            ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Error, "Character(nil) called")
        elseif not UnitExists(slot) then
            ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal, string.format(
                "Character(%s): tried to create new character with UnitExists(%s)=%s!",
                slot, slot, UnitExists(slot)))
        end
        return nil
    end

    return char
end


-- Do not use the slot->GUID lookup table in the main event code. characters
-- may be created before that table is brought up to date
function ns:trackCharacter(slot)
    ns:playback(GetTime(), 'TRACK_CHARACTER', tostring(slot))
    -- XXX: try pcall() to figure out 
    --local guid = UnitGUID(slot)  -- map the name to a globally unique ID
    local retOK, guid = pcall(UnitGUID, slot)  -- map the name to a globally unique ID
    if not retOK then
        ns:playback(GetTime(), 'TRACK_CHARACTER_FAILED', tostring(slot))
        return
    end
    if not guid then
        ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Error,
            'trackCharacter(): FATAL: no GUID for slot=['..slot..']')
        return
    end

    -- If this character is tracked already, return it, else create a new one
    local char = trackedCharacters[guid]
    if not char then
        char = ns:Character(slot)
        trackedCharacters[guid] = char
        -- XXX: TODO: hack until these are formally folded into Character
        ns.eventsForInference[guid] = {}
        evidenceTrackersByGUID[guid] = char:getEvidenceTracker()
    end

    return char
end



-- XXX: TODO: fold this into Character()
function ns:initCDTracker()
    local cdTracker = {}

    -- Now that all abilities are determined, initialize this slot's cooldown tracker
    -- with the correct charge count for each ability. Fill with dummy 0 values that
    -- mean the last time the CD was used was infinitely long ago.
    for guid, char in pairs(trackedCharacters) do
        cdTracker[guid] = {}
        for _, ability in pairs(char:getAbilities()) do
            ns:printDebug(string.format(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal,
                "initCDTracker: slot=[%s], ability=[%s], charges=[%d]",
                guid, ability.name, ability.charges))
            local fifo = ns:fixedFIFO(ability.charges)
            for i=1, ability.charges do
                fifo:push(0)
            end
            cdTracker[guid][ability.name] = fifo
        end
    end

    return cdTracker
end



-------------------------------------------------------------------------------
-- All LibSpecialization code below
-------------------------------------------------------------------------------

local LibSpecialization = LibStub("LibSpecialization")

--function ns:sendLibSpecRequest()
    --LibSpecialization.RequestGroupSpecialization()
--end


local function doLibSpecUpdate(specId, playerName, talentExportString, slot)
    slot = slot or ns:playerNameToSlot(playerName)
    if not slot then
        ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Error,
            'trackCharacter(): FATAL: failed to map player name=[' ..
            playerName .. '] to a slot. proceeding without spec info')
    end

    -- Fire a separate playback event here since this function can be delayed from the
    -- LIB_SPEC_RESPONSE playback event.
    ns:playback(GetTime(), "LIB_SPEC_UPDATE", playerName, specId, talentExportString, tostring(slot))
    local char = ns:trackCharacter(slot)
    char:setSpecAndTalents(specId, talentExportString)
    ns:respondToRosterUpdate('doLibSpecUpdate('..playerName..')')

    -- Solve unique solutions group-wide. This is completely cosmetic: it only
    -- affects the group solution UI.
    ns:zeroKnowledgeSolve()
end


-- For /run pdhInject(...) to force talents onto, e.g., followers
function pdhInject(slot, specId, tstring)
    doLibSpecUpdate(specId, 'injectDummy', tstring, slot)
end


function pdhPerfectEvidence(slot)
    local guid, char = ns:getTrackedCharacterBySlot(slot)
    char:setPerfectEvidence()
end


local function handleLibSpecCallback(specId, role, position, playerName, talentExportString)
    -- LibSpec fires for the player on ADDON_LOAD and PLAYER_LOGIN. Since the
    -- LibSpec dev removed the API to manually query later, we have to keep re-calling
    -- this function until the UI is initially loaded.
    --
    -- This ONLY happens on initial login/reload
    if not ns.addonInitialized then
print('deferring libspec callback, received before addon initialized')
        C_Timer.After(0.5, function()
            handleLibSpecCallback(specId, role, position, playerName, talentExportString)
        end)
    else
        if not ns:addonIsActive() then
            ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal,
                "Ignoring LibSpecialization callback, addon is disabled")
            return
        end

        local slot = ns:playerNameToSlot(playerName)
        ns:playback(GetTime(), "LIB_SPEC_RESPONSE", playerName, slot)
        ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal, string.format(
            "Receiving LibSpecialization response for player=[%s], slot=[%s]",
            playerName, tostring(slot)))

        -- LibSpec returns name in a specific format. If we fail to match it to a
        -- valid frame, just have to proceed without spec data.
        if not slot then
            ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal,
                "No slot for playerName=["..playerName.."], queueing update")
            C_Timer.After(1, function() doLibSpecUpdate(specId, playerName, talentExportString) end)
        else
            doLibSpecUpdate(specId, playerName, talentExportString, slot)
        end
    end
end


local internalGroupSpecs = {}    -- internal use by LibSpecialization
LibSpecialization.RegisterGroup(internalGroupSpecs, handleLibSpecCallback)
