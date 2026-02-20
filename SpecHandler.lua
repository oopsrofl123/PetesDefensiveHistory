-- Get class specs for each group member

local _, ns = ...

local LibSpecialization = LibStub("LibSpecialization")
local internalGroupSpecs = {}    -- For internal use by LibSpecialization


-- 4 possible mods:
--     1. boolean setter. if the amount is a boolean, then the
--        value is simply set
--     2. non-boolean setter. there is only one special case of a
--        where a setter is not boolean: duration_variable. just
--        handle this.
--     3. numeric change
--         3a. additive change
--         3b. multiplicative change. mult changes apply to the
--             base value. reduce mults to adds this way.
local function applyOneModifier(modifiedAbility, mod)
    ns:printDebug(string.format('got modifier [%d] = (%d, %s, %s, %s)',
        modifiedAbility.id, mod.id, mod.modifies,
        tostring(mod.amount), tostring(mod['mult'] or false)))

    if type(mod.amount) == "boolean" then
        modifiedAbility[mod.modifies] = mod.amount
    elseif mod.modifies == "duration_variable" then
        modifiedAbility[mod.modifies] = mod.amount
    else -- numeric case
        local change = mod.amount
        -- Reduce the multiplicative case to the additive case
        if mod['mult'] then
            change = modifiedAbility[mod.modifies] * mod.amount/100
        end
        modifiedAbility[mod.modifies] = modifiedAbility[mod.modifies] + change
    end
end



-- Returns a modified copy of baseAbility. Do not modify the values in the
-- static database of abilities.
--
-- Numeric modifiers must be applied in a specific order. First, additive
-- modifiers followed by multiplicative. To handle this, every modifier
-- for an ability must be collected before applying any changes.
local function applyTalentModifiers(classFile, specId, baseAbility, talentRanks)
    local modifiedAbility = ns:shallowcopy(baseAbility)
    local allMods = {}
    local classmods = ns.ClassTalentModifiers[classFile]
    local specmods = ns.SpecTalentModifiers[specId]

    -- Collect all modifiers across all talents for this ability
    ns:printDebug("looking for modifiers for baseAbility=["..baseAbility.name.."]")
    for spellId, rank in pairs(talentRanks) do
        -- TalentModifiers only contains the talents relevant to our tracked abilities.
        if rank > 0 then
            -- Spell IDs are unique, so they can only be in one of the two tables
            talents = classmods[spellId] or specmods[spellId]
            if talents then
                mods = talents[rank]
                if not mods then
                    ns:printDebug(string.format(
                        'applyTalentModifiers: talent=[%d]: rank=[%d] does not exist',
                        spellId, rank))
                    return nil
                end
    
                -- Talents can modify multiple spells with multiple modifiers. Get
                -- just the mods that apply to this ability.
                for index, mod in pairs(mods) do
                    if baseAbility.id == mod.id then
                        table.insert(allMods, mod)
                    end
                end
            end
        end
    end

    -- To achieve the sorting below, give an integer value to each talent and
    -- then use a standard < comparator.
    local function toOrd(mod)
        local first = mod.mult and 1 or 0
        local second = mod.modifies == "hasAbility" and mod.amount == false and 100000 or 0
        return first + second
    end
    -- Sort additive effects before multiplicative effects and put talents
    -- that *remove* abilities at the end of the sort. This is a very brittle
    -- way to implement talents that replace other abilities and will probably
    -- break at some point.
    table.sort(allMods, function(a, b) return toOrd(a) < toOrd(b) end)
    for _, mod in pairs(allMods) do
        applyOneModifier(modifiedAbility, mod)
    end

    return modifiedAbility
end



-- Update the group CD databases with the new information that player in
-- `slot` is class/specialization `specId`.
--
-- For each player, collect information across the group to determine
-- which spells can be uniquely identified. Other summary data like the
-- maximum cooldown time across all possible abilities is also collected
-- for cases where abilities cannot be uniquely identified.
--
-- Is called every time LibSpec identifies a spec, so must loop over the
-- whole group each time.
local function updateGroupData(slot, playerName, specId, classFile, talentExportString)
    local externals = {}   -- key=caster, value=ability info

    ns:printDebug(string.format("updateGroupData(%s=[%s], spec ID=%d)\nTalent string=[%s]",
        playerName, slot, specId, talentExportString))

    -- Decode the talent string. There are talent IDs, but all talents are
    -- related to spell IDs.
    talentRanks = ns:getTalentRanks(specId, talentExportString)

    ns.groupCDs[slot].playerName = playerName
    ns.groupCDs[slot].specId = specId

    ns.possibleCasters = {}  -- rebuild from scratch every time

    -- find all externals (i.e., spells where target might not equal caster) and
    -- build the table of non-externals for each player.
    for slot, _ in pairs(ns.allSlots) do
        externals[slot] = {}
        local specId = ns.groupCDs[slot].specId
        ns.groupCDs[slot].abilities = {}          -- things that can be CAST ON this slot
        ns.groupCDs[slot].castableAbilities = {}  -- things that can be CAST by this slot
        if specId then
            baseAbilities = ns.AbilityDb[classFile]
            for _, baseAbility in pairs(baseAbilities) do
                local ability = applyTalentModifiers(classFile, specId, baseAbility, talentRanks)
                if ability.hasAbility then
                    ability.caster = slot
                    ns.groupCDs[slot].castableAbilities[ability.name] = ability
                    -- Record the fact that this slot can cast this ability
                    if ns.possibleCasters[ability.name] then
                        table.insert(ns.possibleCasters[ability.name], slot)
                    else
                        ns.possibleCasters[ability.name] = { slot }
                    end

                    if ability.external == ns.NOT_EXTERNAL then
                        table.insert(ns.groupCDs[slot].abilities, ns:shallowcopy(ability))
                    else
                        table.insert(externals[slot], ns:shallowcopy(ability))
                    end
                end
            end
        end
    end

    -- XXX: TODO: a separate loop for this no longer seems necessary..
    -- add externals to the full ability list for each player
    -- for each target, the possible set of abilities are:
    --   1. the target's own (cast on self) abilities
    --   2. another caster's external, assuming there are no rules preventing this
    --      (e.g., blessing of sac can't be cast on self).
    for slot, _ in pairs(ns.allSlots) do
        for caster, abilities in pairs(externals) do
            for _, ability in pairs(abilities) do
                -- the only rule I know of is no self casting
                if not (caster == slot and ability.external == ns.EXTERNAL_NOT_SELF) then
                    table.insert(ns.groupCDs[slot].abilities, ns:shallowcopy(ability))
                end
            end
        end
    end
end



LibSpecialization.RegisterGroup(internalGroupSpecs, 
    function(specId, role, position, playerName, talentExportString)
        local slot = ns:nameToSlot(playerName)
        -- classFile is the locale-independent class name like "WARRIOR" or "PRIEST"
        local _, _, _, _, _, classFile, _ = GetSpecializationInfoByID(specId)
        updateGroupData(slot, playerName, specId, classFile, talentExportString)

        -- Solve unique solutions group-wide
        ns:zeroKnowledgeSolve()

        -- Update various UI elements:
        -- 1. Party frames static cooldown row
        -- XXX: TODO: shows abilities that aren't always inferrable. this could be what we want
        -- since in some scenarios they could be inferrable.  have to think about this.
        ns:updateStaticRow(slot)

        -- 2. Party frames fallback history tray
        ns:setDataHistoryTrayRow(slot, specId, UnitName(slot))
        ns:updateHistoryTrayRow(slot)

        -- 3. the solutions UI. have to do all rows because each group member affects
        --    other group members unique solves.
        for slot, _ in pairs(ns.allSlots) do
            ns:updateGroupSolutionRow(ns.groupSolutionUI.rows[slot])
        end
    end
)
