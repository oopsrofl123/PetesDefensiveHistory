local _, ns = ...


-- Get class specs for each group member so that the defensives that show up on big center debuff are known.
local LibSpecialization = LibStub("LibSpecialization")

local internalPdhGroupSpecs = {}    -- For internal use by LibSpecialization

-- This dict is the set of all possible spells that can target each slot
ns.pdhGroupCDs = {}
-- For each unique (caster, ability), this dict tracks the last time that
-- ability was identified
ns.pdhCDTracker = {}
for slot, _ in pairs(ns.allSlots) do
    ns.pdhGroupCDs[slot] = {
        specId = nil,
        abilities = nil    -- nil for an undetected/unset spec. {} for a spec with no abilities
    }
    ns.pdhCDTracker[slot] = {}
end

-- For each ability, what players can possibly cast the ability? This
-- allows redirecting externals to their casters rather than their targets.
ns.pdhPossibleCasters = {}



-- Aura removal events aren't processed at exactly the moment the buff
-- is removed. E.g., if a buff lasts 12s it is common to see the removal
-- event at 12.05s or 11.95s.
--
-- The tolerance defines the maximum difference between the nominal buff
-- duration and the measured buff duration that counts as match.
ns.DURATION_TOLERANCE = 0.15

-- How much better the best possible solution must be than the second
-- best possible solution.
ns.CONFIDENT_DIFFERENCE = 0.5


-- Use various rules about who can cast what ability on whom to narrow down
-- the possible abilities that could be "buff".
--
-- IMPORTANT! buff.cooldown must ALWAYS be set. If the ability can't be
-- uniquely identified, then the worst the timer could be is the longest
-- cooldown among the group's externals and that player's own abilities.
function ns:identifyAbility(slot, buff, useDuration, cdTracker)
    ns:printDebug("STARTING inference for slot=" .. slot)

    if useDuration == nil then
        useDuration = true
    end
    -- allow the caller to override the tracked state of CDs to simulate an
    -- unknown state. useful for determining which abilities are ALWAYS
    -- uniquely identifiable. if the caller doesn't override, use the real
    -- tracker.
    cdTracker = cdTracker or ns.pdhCDTracker
    buff.cooldown = -1

    -- first determine which abilities are possible matches by ensuring
    -- that the duration of the buff is consistent with what is known
    -- about how the buff acts.
    local possibleSolutions = {}
    for _, ability in pairs(ns.pdhGroupCDs[slot].abilities) do
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
            ns:printDebug("target=" .. slot .. ": excluding ability " .. ability.name ..
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
            if #ns.pdhPossibleCasters[ability.name] == 1 then
                local caster = ns.pdhPossibleCasters[ability.name][1]
                local time_since = GetTime() - (cdTracker[caster][ability.name] or 0)
                ns:printDebug("target=" .. slot .. ", caster=" .. caster ..
                    ", ability=" ..  ability.name ..
                    ": last seen " .. time_since ..
                    "s ago, cooldown (=" ..  ability.cooldown .. "s) + duration (=" ..
                    ability.duration .. "s) = " .. ability.cooldown+ability.duration .. "s")

                -- buff.cooldown + buff.duration - since this function operates when the
                -- buff expires, for fixed length buffs, the ability must have been off
                -- coldown CD+DUR seconds ago, not just CD seconds ago.
                -- DURATION_TOLERANCE accounts for times when the event fires slightly
                -- before the buff really falls off.
                if time_since < ability.cooldown + ability.duration - ns.DURATION_TOLERANCE then
                    ns:printDebug("fails cooldown test")
                    isPossible = false
                end
            end
        end

        -- 3. Was the buff's duration consistent with how the ability works?
        local diff = 0  -- Using diff=0 means the duration matched, equivalent to ignoring duration
        if useDuration then
            local isPossibleBefore = isPossible
            diff = math.abs(buff.duration - ability.duration)
            if ability.duration_variable == ns.DURATION_FIXED then
                if diff > ns.DURATION_TOLERANCE then
                    isPossible = false
                end
            elseif ability.duration_variable == ns.DURATION_LTE then
                if not (diff <= ns.DURATION_TOLERANCE or buff.duration <= ability.duration) then
                    isPossible = false
                end
            elseif ability.duration_variable == ns.DURATION_GTE then
                if not (diff <= ns.DURATION_TOLERANCE or buff.duration >= ability.duration) then
                    isPossible = false
                end
            end

            if isPossibleBefore ~= isPossible then
                ns:printDebug("excluding ability " .. ability.name ..
                    ": duration not within tolerance (diff=" .. diff .. ")")
            end
        end

        -- 4. Does the ability trigger a concurrent debuff?
        do
            local isPossibleBefore = isPossible
            if ability.concurrentDebuff then
                if #buff.concurrentDebuffs == 0 then
                    -- not sure if this can cause false negatives. in a tiny bit of testing,
                    -- the concurrentDebuff does always come in the same UNIT_AURA event.
                    isPossible = false
                end
            else
                if #buff.concurrentDebuffs > 0 then
                    -- This can cause false negatives. Just because an ability doesn't *have*
                    -- to come with a debuff doesn't exclude the possibility that another unrelated
                    -- debuff happened at the same moment.
                    isPossible = false
                end
            end
            if isPossibleBefore ~= isPossible then
                ns:printDebug("excluding ability " .. ability.name ..
                    ": must have a concurrent debuff, but " .. #buff.concurrentDebuffs .. " witnessed")
            end
        end

        -- All rules have passed, this ability is a possible match
        if isPossible then
            table.insert(possibleSolutions, { diff=diff, ability=ability })
        end
    end

    table.sort(possibleSolutions, function(a, b) return a.diff <= b.diff end)

    -- consider the two (or more) best possible matches
    local best = possibleSolutions[1] or { diff=ns.INFINITY, ability={ name='INFINITY' } }
    local second = possibleSolutions[2] or { diff=ns.INFINITY, ability={ name='INFINITY' } }

    -- absent any other information, assume the target is also the caster
    local caster = slot

    -- accept this as a confident match
    if second.diff - best.diff >= ns.CONFIDENT_DIFFERENCE then
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
        if #ns.pdhPossibleCasters[best.name] == 1 then
            buff.caster = ns.pdhPossibleCasters[best.name][1]
            cdTracker[ns.pdhPossibleCasters[best.name][1]][best.name] = GetTime() - buff.duration
        end
    else
        ns:printDebug('could not confidently distinguish between ' ..
            best.ability.name .. ' (best), diff=' .. best.diff ..
            ' and ' .. second.ability.name .. ' (second best), diff=' ..
            second.diff)
    end

    if ns:isAbilityIdentified(buff) then
        ns:printDebug("time=" .. GetTime() .. ": " .. buff.caster .. " cast ability " ..
            buff.auraName .. " at time " ..
            cdTracker[buff.caster][buff.auraName])
    else
        ns:printDebug("couldn't identify ability")
    end

    return ns:isAbilityIdentified(buff)
end



-- For each player, collect information across the group to determine
-- which spells can be uniquely identified. Other summary data like the
-- maximum cooldown time across all possible abilities is also collected
-- for cases where abilities cannot be uniquely identified.
--
-- Is called every time LibSpec identifies a spec, so must loop over the
-- whole group each time.
--
-- XXX: TODO: the logic here shouldn't be completely separate (and poorly duplicated)
-- from the identifyAbility() function. the bookkeeping part should be, though.
function ns:updatePdhGroupSolution()
    local externals = {}   -- key=caster, value=ability info

    ns.pdhPossibleCasters = {}  -- rebuild from scratch every time

    -- find all externals (i.e., spells where target might not equal caster) and
    -- build the table of non-externals for each player.
    for slot, _ in pairs(ns.allSlots) do
        specId = ns.pdhGroupCDs[slot].specId
        ns.pdhGroupCDs[slot].abilities = {}
        if specId then
            abilities = ns.SpecDefensiveDb[specId]
            for _, ability in pairs(abilities) do
                -- Record the fact that this slot can cast this ability
                if ns.pdhPossibleCasters[ability.name] then
                    table.insert(ns.pdhPossibleCasters[ability.name], slot)
                else
                    ns.pdhPossibleCasters[ability.name] = { slot }
                end

                if ability.external == ns.NOT_EXTERNAL then
                    table.insert(ns.pdhGroupCDs[slot].abilities, ns:shallowcopy(ability))
                else
                    externals[slot] = ability
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
        for caster, ability in pairs(externals) do
            -- the only rule I know of is no self casting
            if not (caster == slot and ability.external == ns.EXTERNAL_NOT_SELF) then
                ns:printDebug("adding external " .. ability.name .. " to valid list for " .. slot)
                table.insert(ns.pdhGroupCDs[slot].abilities, ns:shallowcopy(ability))
            end
        end
    end

    -- Solve for unique abilities (i.e., figure out which ones can be guessed
    -- based on who they're cast on and how long they last.
    for slot, _ in pairs(ns.allSlots) do
        abilities = ns.pdhGroupCDs[slot].abilities
        for _, ability in pairs(abilities) do
            -- make a "perfect" buff. this data is normally observed by UNIT_AURA and
            -- some of it (like duration) do not match the ideal values.
            -- for abilities with isBuff=false, the buff payload needs to match the
            -- buff the ability applied. E.g., cheat death on prot paladin triggers
            -- GoAK, but we want to track the cheat death cooldown as a separate ability
            local buff = {
                startTime = GetTime(),
                endTime = GetTime() + ability.duration,   -- perfect duration
                duration = ability.duration,
                isImportant = ability.importantFlag,
                isBigDefensive = ability.bigFlag,
                isExternal = ability.externalFlag,
                numUpdates = 0,
                concurrentDebuffs = {}
            }

            -- if the ability is supposed to come with a concurrent debuff, give it a
            -- dummy auraInstanceId=1.
            if ability.concurrentDebuff then
                table.insert(buff.concurrentDebuffs, 1)
            end


            -- make a fake cooldown state where no cooldowns have been seen
            blankCDs = {}
            for slot, _ in pairs(ns.allSlots) do
                blankCDs[slot] = {}
            end
            -- XXX: TODO: make empty fake spell cast histories if those end up being used.
            ns:identifyAbility(slot, buff, false, blankCDs)
            ability.solved = ns:isAbilityIdentified(buff)
            -- would be nice if identifyAbility would return the conflicting spell/caster combos
            ability.conflicts = {}
        end
    end
end


-- This function could run before the data structures are initialized.
LibSpecialization.RegisterGroup(internalPdhGroupSpecs, function(specId, role, position, playerName, talents)
    local slot = ns:nameToSlot(playerName)
    ns:printDebug(string.format("%s (%s): spec ID=%d, a %s %s.\nTalent string=[%s]",
        playerName, slot, specId, position, role, talents))
    ns.pdhGroupCDs[slot].specId = specId

    -- Solving
    ns:updatePdhGroupSolution()

    -- UI elements. N.B. this often happens before frames are allocated
    if ns.pdhInitialized then
        local row = ns.historyRows[slot]
        if row then
            local specstring = ns:specIdToString(specId)
            row.specText:SetText(specstring)
            ns.groupSolutionUI[slot].specLabel:SetText(specstring)
            for slot, _ in pairs(ns.allSlots) do
                ns:showPdhGroupSolutionRow(ns.groupSolutionUI[slot])
            end
        end
    end
end)
