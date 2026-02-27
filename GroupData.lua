-- Get class specs for each group member

local _, ns = ...


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
    end

    ns:printDebug(string.format(
        "Character(%s): new character GUID=[%s], name=[%s], class=[%s]",
        slot, GUID, name, classFile))

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
        possibleAbilities = {}
        for _, baseAbility in pairs(ns.AbilityDb[classFile]) do
            local ability = ns:applyTalentModifiers(classFile, specId, baseAbility, talentRanks)
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
    end

    -- Update the cache of possible abilities targeting this character.
    -- Cannot rely on a GROUP_ROSTER_UPDATE event or libspec callback to
    -- fire after whatever event created this character.
    for _, char in pairs(trackedCharacters) do
        char:cachePossibleAbilities()
    end
    return char
end


-- Stop tracking the character identified by guid
function ns:untrackCharacter(guid)
    trackedCharacters[guid] = nil
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
        if not slot then
            ns:printDebug('trackCharacter(): FATAL: failed to map player name=['..playerName..'] to slot')
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
        -- 1. Party frames tracker UI
        ns:updateTrackerUI()
        --ns:updateGroupSolutionUI()
    end
)
