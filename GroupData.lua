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
        shield=ns:fixedFIFO(EVIDENCE_HISTORY_SIZE),
        -- Booleans of the last observed combat status (no time associated)
        combatStatus=ns:fixedFIFO(EVIDENCE_HISTORY_SIZE),
        -- Times when combatStatus changed from true->false
        combatDrop=ns:fixedFIFO(EVIDENCE_HISTORY_SIZE)
    }
end        

function ns:getEvidenceTrackers()
    return evidenceTrackersByGUID
end



-- list of all relevant characters
local trackedCharacters = {}

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
    local classFile = "WARRIOR"
    local englishRaceName = nil  -- unique and locale-independent, valid db key
    local raceId = nil
    local specId = nil
    local specName = nil
    local talentExportString = nil
    local talentRanks = nil
    local abilities = {}
    local possibleAbilities = {}

    -- If this isn't an empty character, start populating it
    if slot then
        GUID = UnitGUID(slot) or
            ns:printDebug("Character("..slot.."): could not get GUID") -- Should error, not recoverable
        name = UnitName(slot)
        className, classFile, _ = UnitClass(slot)
        _, englishRaceName, raceId = UnitRace(slot)
    end

    local evidenceTracker = ns:makeEvidenceTracker()

    ns:printDebug(string.format(
        "Character(%s): new character GUID=[%s], name=[%s], class=[%s]",
        slot, GUID, name, tostring(classFile)))

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

    -- Return the current player/partyX alias assigned to this character. This
    -- is not stable, possibly changing during group roster updates.
    -- This is never set. It is always determined by a lookup table.
    function char:getSlot()
        return "lookup this GUID in slot map"
    end


    -- Settable values ----------------------------------------------------------
    -- Abilities, spec and talents are all downstream of setting spec and talents.
    -- Setting these resolves all of the downstream
    function char:setSpecAndTalents(spec, tstring)
        specId = spec
        _, specName, _, _, _, _, className = GetSpecializationInfoByID(specId)
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

    -- If `target` is nil, return an named list of all abilities castable by
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
            for _, ability in pairs(char:getAbilities(GUID)) do
                table.insert(possibleAbilities, ability)
            end
        end
        ns:printDebug("cached "..#possibleAbilities.." targeting character=["..name.."]")
    end

    function char:getPossibleAbilities() return possibleAbilities end

    -- Stop tracking the character
    function char:untrack()
        ns:printDebug(string.format("DELETING ALL DATA for character name=[%s], GUID=[%s]",
            name, GUID))
        trackedCharacters[GUID] = nil
        -- XXX: TODO: hack until these are formally folded into Character
        ns.eventsForInference[GUID] = nil
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
    function char:trackAuraEvidence(slot, auraInstanceId, now)
        if ns:isBuff(slot, auraInstanceId) then
            char:trackEvidence('buff', now)
        elseif ns:isDebuff(slot, auraInstanceId) then
            char:trackEvidence('debuff', now)
        end
    end

    function char:getEvidence(evidenceType)
        return evidenceTracker[evidenceType]
    end

    function char:getEvidenceTracker()
        return evidenceTracker
    end

    return char
end


-- Do not use the slot->GUID lookup table in the main event code. characters
-- may be created before that table is brought up to date
function ns:trackCharacter(slot)
    local guid = UnitGUID(slot)  -- map the name to a globally unique ID
    if not guid then
        ns:printDebug('trackCharacter(): FATAL: no GUID for slot=['..slot..']')
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

    -- Update the cache of possible abilities targeting this character.
    -- Cannot rely on a GROUP_ROSTER_UPDATE event or libspec callback to
    -- fire after whatever event created this character.
    for _, char in pairs(trackedCharacters) do
        char:cachePossibleAbilities()
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
            ns:printDebug(string.format(
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
local internalGroupSpecs = {}    -- internal use by LibSpecialization
LibSpecialization.RegisterGroup(internalGroupSpecs, 
    function(specId, role, position, playerName, talentExportString)
        local slot = ns:nameToSlot(playerName)
        -- This can happen when libspec fires so early that some party frame
        -- names are still "Unknown"
        if not slot then
            ns:printDebug('trackCharacter(): FATAL: failed to map player name=['..playerName..'] to slot=['..tostring(slot)..']')
            -- The rest of this will throw errors with slot=nil, so don't bother
            return
        end

        local char = ns:trackCharacter(slot)

        -- Use the (possibly new) spec ID and talents to determine which abilities
        -- this character has and what their tracking properties are.
        -- When anything changes the abilities of one character, all must re-cache
        -- the possible spells that can target them.
        char:setSpecAndTalents(specId, talentExportString)
        for _, char in pairs(trackedCharacters) do
            char:cachePossibleAbilities()
        end

        -- XXX: TODO: not correct - needs to live in Character objects.
        ns.cdTracker = ns:initCDTracker()

        -- Solve unique solutions group-wide. This is completely cosmetic: it only
        -- affects the group solution UI.
        ns:zeroKnowledgeSolve()

        -- Update various UI elements:
        ns:updateTrackerUI()
        ns:updateGroupSolutionUI()
    end)
