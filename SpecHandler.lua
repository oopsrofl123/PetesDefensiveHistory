-- Get class specs for each group member

local _, ns = ...

local LibSpecialization = LibStub("LibSpecialization")
local internalGroupSpecs = {}    -- For internal use by LibSpecialization


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
local function updateGroupData(slot, playerName, specId, talents)
    local externals = {}   -- key=caster, value=ability info

    ns:printDebug(string.format("updateGroupData(%s=[%s], spec ID=%d)\nTalent string=[%s]",
        playerName, slot, specId, talents))

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
            abilities = ns.SpecAbilityDb[specId]
            for _, ability in pairs(abilities) do
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
        updateGroupData(slot, playerName, specId, talentExportString)

        -- Decode the talent string. There are talent IDs, but all talents are
        -- related to spell IDs.
        talentRanks = ns:getTalentRanks(specId, talentExportString)

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
