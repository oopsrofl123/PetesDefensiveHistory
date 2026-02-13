-- Get class specs for each group member so that the defensives that show up on big center debuff are known.
local LibSpecialization = LibStub("LibSpecialization")

local internalPdhGroupSpecs = {}    -- For internal use by LibSpecialization

-- This dict is the set of all possible spells that can target each slot
pdhGroupCDs = {}
-- For each unique (caster, ability), this dict tracks the last time that
-- ability was identified
pdhCDTracker = {}
for slot, _ in pairs(allSlots) do
    pdhGroupCDs[slot] = {
        specId = nil,
        abilities = nil    -- nil for an undetected/unset spec. {} for a spec with no abilities
    }
    pdhCDTracker[slot] = {}
end

-- For each ability, what players can possibly cast the ability? This
-- allows redirecting externals to their casters rather than their targets.
pdhPossibleCasters = {}



-- Aura removal events aren't processed at exactly the moment the buff
-- is removed. E.g., if a buff lasts 12s it is common to see the removal
-- event at 12.05s or 11.95s.
--
-- The tolerance defines the maximum difference between the nominal buff
-- duration and the measured buff duration that counts as match.
DURATION_TOLERANCE = 0.15

-- How much better the best possible solution must be than the second
-- best possible solution.
CONFIDENT_DIFFERENCE = 0.5


-- If the duration of this buff matches (with a small delta) the duration
-- of a solved ability, then this buff is that ability.
--
-- IMPORTANT! buff.cooldown must ALWAYS be set. If the ability can't be
-- uniquely identified, then the worst the timer could be is the longest
-- cooldown among the group's externals and that player's own abilities.
function identifyAbility(slot, buff)
    buff.cooldown = -1

    -- first determine which abilities are possible matches by ensuring
    -- that the duration of the buff is consistent with what is known
    -- about how the buff acts.
    possibleSolutions = {}
    for _, ability in pairs(pdhGroupCDs[slot].abilities) do
        -- it's tempting to only use possible abilities, but the heuristics
        -- below can exclude abilities incorrectly due to the duration
        -- tolerances. so to be sure we have SOME fallback, take the max
        -- among all cds whether possible or not.
        buff.cooldown = math.max(buff.cooldown, ability.cooldown)
        local isPossible = true 

        -- 1. Do Blizzard's aura flags match?
        if buff.isImportant ~= ability.importantFlag then
            isPossible = false
        end
        if buff.isBigDefensive ~= ability.bigFlag then
            isPossible = false
        end
        if buff.isExternal ~= ability.externalFlag then
            isPossible = false
        end
        if not isPossible then
            printDebug("target=" .. slot .. ": excluding ability " .. ability.name ..
                " due to mismatching flags (" ..
                tostring(ability.importantFlag) .. ", " ..
                tostring(ability.bigFlag) .. ", " ..
                tostring(ability.externalFlag) .. ") vs. (" ..
                tostring(buff.isImportant) .. ", " ..
                tostring(buff.isBigDefensive) .. ", " ..
                tostring(buff.isExternal) .. ")")
        end

        -- 2. How much time has passed since we last saw this ability? Was it
        -- long enough that it could be off cooldown? This heuristic only
        -- works for abilities that don't have dynamic cooldown reduction.
        -- ALSO: need to know who cast this ability. For self-cast only
        -- spells slot=caster but externals may not be.
        if isPossible and not ability.cdr then
            -- XXX: make things easier for now. possible to infer for >1 sometimes
            if #pdhPossibleCasters[ability.name] == 1 then
                local caster = pdhPossibleCasters[ability.name][1]
                local time_since = GetTime() - (pdhCDTracker[caster][ability.name] or 0)
                printDebug("target=" .. slot .. ", caster=" .. caster ..
                    ", ability=" ..  ability.name ..
                    ": last seen " .. time_since ..
                    "s ago, cooldown (=" ..  ability.cooldown .. "s) + duration (=" ..
                    ability.duration .. "s) = " .. ability.cooldown+ability.duration .. "s")

                -- buff.cooldown + buff.duration - since this function operates when the
                -- buff expires, for fixed length buffs, the ability must have been off
                -- coldown CD+DUR seconds ago, not just CD seconds ago.
                -- DURATION_TOLERANCE accounts for times when the event fires slightly
                -- before the buff really falls off.
                if time_since < ability.cooldown + ability.duration - DURATION_TOLERANCE then
                    printDebug("fails cooldown test")
                    isPossible = false
                end
            end
        end

        -- 3. Was the buff's duration consistent with how the ability works?
        diff = math.abs(buff.duration - ability.duration)
        if ability.duration_variable == DURATION_FIXED then
            if diff > DURATION_TOLERANCE then
                isPossible = false
            end
        elseif ability.duration_variable == DURATION_LTE then
            if not (diff <= DURATION_TOLERANCE or buff.duration <= ability.duration) then
                isPossible = false
            end
        elseif ability.duration_variable == DURATION_GTE then
            if not (diff <= DURATION_TOLERANCE or buff.duration >= ability.duration) then
                isPossible = false
            end
        end


        if isPossible then
            table.insert(possibleSolutions, { diff=diff, ability=ability })
        end
    end

    table.sort(possibleSolutions, function(a, b) return a.diff <= b.diff end)

    -- consider the two (or more) best possible matches
    local best = possibleSolutions[1] or { diff=INFINITY, ability={ name='INFINITY' } }
    local second = possibleSolutions[2] or { diff=INFINITY, ability={ name='INFINITY' } }

    -- absent any other information, assume the target is also the caster
    local caster = slot

    -- accept this as a confident match
    if second.diff - best.diff >= CONFIDENT_DIFFERENCE then
        best = best.ability -- convenience
        -- XXX: TODO: handle variable duration
        buff.auraName = best.name
        buff.cooldown = best.cooldown
        buff.spellId = best.id
        buff.external = best.external
        buff.iconId = best.iconId     -- usually nil, we use blizzard's texture. only for overriding
        -- track the cooldown of this ability if the caster can be uniquely determined
        -- if only one character in the group could cast this, then that was the caster.
        -- might be different from slot if this was an external.
        if #pdhPossibleCasters[best.name] == 1 then
            caster = pdhPossibleCasters[best.name][1]
            -- XXX: TODO: this is another approximation that could be handled better: for
            -- variable duration buffs, subtracting duration from the current time
            -- might not be when the button was actually pressed.
            pdhCDTracker[pdhPossibleCasters[best.name][1]][best.name] = GetTime() - best.duration
        end
    else
        printDebug('could not confidently distinguish between ' ..
            best.ability.name .. ' (best), diff=' .. best.diff ..
            ' and ' .. second.ability.name .. ' (second best), diff=' ..
            second.diff)
    end

    if isAbilityIdentified(buff) then
        printDebug("time=" .. GetTime() .. ": " .. caster .. " cast ability " ..
            buff.auraName .. " at time " ..
            pdhCDTracker[caster][buff.auraName])
    else
        printDebug("couldn't identify ability")
    end

    return caster
end



-- For each player, collect information across the group to determine
-- which spells can be uniquely identified. Other summary data like the
-- maximum cooldown time across all possible abilities is also collected
-- for cases where abilities cannot be uniquely identified.
--
-- Is called every time LibSpec identifies a spec, so must loop over the
-- whole group each time.
local function updatePdhGroupSolution()
    externals = {}   -- key=caster, value=ability info

    pdhPossibleCasters = {}  -- rebuild from scratch every time

    -- find all externals (i.e., spells where target might not equal caster) and
    -- build the table of non-externals for each player.
    for slot, _ in pairs(allSlots) do
        specId = pdhGroupCDs[slot].specId
        pdhGroupCDs[slot].abilities = {}
        if specId then
            abilities = SpecDefensiveDb[specId]
            for _, t in pairs(abilities) do
                -- Record the fact that this slot can cast this ability
                if pdhPossibleCasters[t.name] then
                    table.insert(pdhPossibleCasters[t.name], slot)
                else
                    pdhPossibleCasters[t.name] = { slot }
                end

                if t.external == NOT_EXTERNAL then
                    table.insert(pdhGroupCDs[slot].abilities, shallowcopy(t))
                else
                    externals[slot] = t
                end
            end
        end
    end

    -- add externals to the full ability list for each player
    -- for each target, the possible set of abilities are:
    --   1. the target's own (cast on self) abilities
    --   2. another caster's external, assuming there are no rules preventing this
    --      (e.g., blessing of sac can't be cast on self).
    for slot, _ in pairs(allSlots) do
        for caster, ability in pairs(externals) do
            -- the only rule I know of is no self casting
            if caster ~= slot or ability.external ~= EXTERNAL_NOT_SELF then
                printDebug("adding external " .. ability.name .. " to valid list for " .. slot)
                table.insert(pdhGroupCDs[slot].abilities, shallowcopy(ability))
            end
        end
    end

    -- Solve for unique abilities (i.e., figure out which ones can be guessed
    -- based on who they're cast on and how long they last.
    for slot, _ in pairs(allSlots) do
        abilities = pdhGroupCDs[slot].abilities
        for _, ability in pairs(abilities) do
            ability.solved = true
            ability.conflicts = {}

            -- loop through other abilities for this player
            for _, ability2 in pairs(abilities) do
                if ability.name ~= ability2.name then
                    -- simple check: does 'ability' have a unique duration among *other* abilities?
                    -- if true, then we can guess that ability by how long it lasted.
                    if ability.duration == ability2.duration then
                        table.insert(ability.conflicts, ability2.name)
                        ability.solved = false
                    end
                end
            end
        end
    end
end


-- This function could run before the data structures are initialized.
LibSpecialization.RegisterGroup(internalPdhGroupSpecs, function(specId, role, position, playerName, talents)
    local slot = nameToSlot(playerName)
    printDebug(string.format("%s (%s): spec ID=%d, a %s %s.\nTalent string=[%s]",
        playerName, slot, specId, position, role, talents))
    pdhGroupCDs[slot].specId = specId

    -- Solving
    updatePdhGroupSolution()

    -- UI elements. N.B. this often happens before frames are allocated
    if pdhInitialized then
        local row = historyRows[slot]
        if row then
            specstring = specIdToString(specId)
            row.specText:SetText(specstring)
            groupSolutionUI[slot].specLabel:SetText(specstring)
            for slot, _ in pairs(allSlots) do
                showPdhGroupSolutionRow(groupSolutionUI[slot])
            end
        end
    end
end)
