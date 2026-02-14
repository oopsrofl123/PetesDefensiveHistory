-- Get class specs for each group member

local _, ns = ...
local LibSpecialization = LibStub("LibSpecialization")
local internalPdhGroupSpecs = {}    -- For internal use by LibSpecialization


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




-- This function could run before the data structures are initialized.
LibSpecialization.RegisterGroup(internalPdhGroupSpecs, function(specId, role, position, playerName, talents)
    local slot = ns:nameToSlot(playerName)
    ns:printDebug(string.format("%s (%s): spec ID=%d, a %s %s.\nTalent string=[%s]",
        playerName, slot, specId, position, role, talents))
    ns.groupCDs[slot].specId = specId

    -- Solving
    updateGroupData()
    ns:zeroKnowledgeSolve()

    -- UI elements. N.B. this often happens before frames are allocated
    if ns.initialized then
        local row = ns.historyRows[slot]
        if row then
            local specstring = ns:specIdToString(specId)
            row.specText:SetText(specstring)
            ns.groupSolutionUI[slot].specLabel:SetText(specstring)
            for slot, _ in pairs(ns.allSlots) do
                ns:showPdhGroupSolutionRow(ns.groupSolutionUI[slot])
            end
        end

        -- Static cooldown row
        ns:updateStaticRows(slot, ns:getCastableAbilities(slot))
    end
end)
