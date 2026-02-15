-- Get class specs for each group member

local _, ns = ...

local LibSpecialization = LibStub("LibSpecialization")
local internalGroupSpecs = {}    -- For internal use by LibSpecialization


-- For each player, collect information across the group to determine
-- which spells can be uniquely identified. Other summary data like the
-- maximum cooldown time across all possible abilities is also collected
-- for cases where abilities cannot be uniquely identified.
--
-- Is called every time LibSpec identifies a spec, so must loop over the
-- whole group each time.
local function updateGroupData()
    local externals = {}   -- key=caster, value=ability info

    ns.possibleCasters = {}  -- rebuild from scratch every time

    -- find all externals (i.e., spells where target might not equal caster) and
    -- build the table of non-externals for each player.
    for slot, _ in pairs(ns.allSlots) do
        externals[slot] = {}
        specId = ns.groupCDs[slot].specId
        ns.groupCDs[slot].abilities = {}
        if specId then
            abilities = ns.SpecDefensiveDb[specId]
            for _, ability in pairs(abilities) do
                ability.caster = slot
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



local function getCastableAbilities(slot)
    castable = {}
    -- the groupCDs table stores what abilities can be cast ON slot, not BY slot.
    -- so have to loop over the whole group to find externals like blessing of sac
    -- that cannot be self cast.
    for target, _ in pairs(ns.allSlots) do
        for _, ability in pairs(ns.groupCDs[target].abilities) do
            if ns:tablecontains(ns.possibleCasters[ability.name], slot) then
                castable[ability.name] = ability
            end
        end
    end
    return castable
end



LibSpecialization.RegisterGroup(internalGroupSpecs, function(specId, role, position, playerName, talents)
    local slot = ns:nameToSlot(playerName)
    ns:printDebug(string.format("%s (%s): spec ID=%d, a %s %s.\nTalent string=[%s]",
        playerName, slot, specId, position, role, talents))
    ns.groupCDs[slot].specId = specId

    -- Solving
    updateGroupData()
    ns:zeroKnowledgeSolve()

    -- Update various UI elements:
    -- 1. Party frames static cooldown row
    -- XXX: TODO: not at all what we want. only show inferrable abilities
    ns:updateStaticRows(slot, getCastableAbilities(slot))

    -- 2. Party frames fallback history tray
    ns:updateRow(ns.historyRows[slot], specId, playerName)

    -- 3. the solutions UI. have to do all rows because each group member affects
    --    other group members unique solves.
    for slot, _ in pairs(ns.allSlots) do
        ns:updateGroupSolutionRow(ns.groupSolutionUI.rows[slot])
    end
end)
