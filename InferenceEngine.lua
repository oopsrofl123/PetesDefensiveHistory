local _, ns = ...


-- This dict is the set of all possible spells that can target each slot
ns.groupCDs = {}
-- For each unique (caster, ability), this dict tracks the last time that
-- ability was identified
ns.cdTracker = {}
for slot, _ in pairs(ns.allSlots) do
    ns.groupCDs[slot] = {
        specId = nil,
        abilities = nil    -- nil for an undetected/unset spec. {} for a spec with no abilities
    }
    ns.cdTracker[slot] = {}
end

-- For each ability, what players can possibly cast the ability? This
-- allows redirecting externals to their casters rather than their targets.
ns.possibleCasters = {}



-- Aura removal events aren't processed at exactly the moment the buff
-- is removed. E.g., if a buff lasts 12s it is common to see the removal
-- event at 12.05s or 11.95s.
--
-- The tolerance defines the maximum difference between the nominal buff
-- duration and the measured buff duration that counts as match.
ns.DURATION_TOLERANCE = 0.15

-- How much better the best possible solution must be than the second
-- best possible solution.
ns.DURATION_CONFIDENT_DIFFERENCE = 0.5

-- How close must the buff's start time be to the caster's cast time for us
-- to confidently claim this spell was cast?
-- Confusing point: this variable is applied to cast time DIFFERENCES --
-- i.e., for each potential caster, first compute how far the cast time was
-- from the buff application.  then compare those differences.  The
-- further away the second caster was from the best caster, the higher the
-- likelihood that the best caster really cast the spell.
--
-- IMPORTANT: A reasonble model is that every group
-- member will be pressing abilities every GCD, meaning cast times can be modelled
-- as a uniform on [0, GCD length]. For a slow GCD of 1.5, setting this parameter
-- to 0.01 would have a false positive rate of 1/150 (0.6%) and for a fast GCD of 1.0 a
-- FP rate of 1/100 (=1%).
ns.CASTTIME_CONFIDENT_DIFFERENCE = 0.150



function ns:isAbilityInferred(buff)
    return buff.name ~= nil
end


local function traceLogic(buff, ability, message, ...)
    ns:printDebug(string.format(
        "ability=[%s], target=[%s], caster=[%s]: " .. message,
        ability.name, buff.slot, ability.caster, ...))
end



-- Do Blizzard's aura flags match?
local function logicLayerBuffFlags(buff, ability)
    if buff.isImportant ~= ability.importantFlag or
       buff.isBigDefensive ~= ability.bigFlag or
       buff.isExternal ~= ability.externalFlag or
       buff.isRaid ~= ability.raidFlag or
       buff.isRaidInCombat ~= ability.raidInCombatFlag then
        traceLogic(buff, ability, "excluding due to flag mismatch buff=(%d,%d,%d,%d,%d), ability=(%d,%d,%d,%d,%d)",
            buff.isImportant and 1 or 0,
            buff.isBigDefensive and 1 or 0,
            buff.isExternal and 1 or 0,
            buff.isRaid and 1 or 0,
            buff.isRaidInCombat and 1 or 0,
            ability.importantFlag and 1 or 0,
            ability.bigFlag and 1 or 0,
            ability.externalFlag and 1 or 0,
            ability.isRaidFlag and 1 or 0,
            ability.isRaidInCombatFlag and 1 or 0)
        return false
    end
    return true
end



-- How much time has passed since we last saw this ability? Was it
-- long enough that it could be off cooldown? This heuristic only
-- works for abilities that don't have dynamic cooldown reduction.
-- IMPORTANT: there is an ability in the list for each caster of each ability
-- that can target the person. e.g., if two there are 2 paladins with sac
-- in the group, then there will be 2 entries of sac in this list.
-- we want to know if THIS caster has the ability off cooldown.
local function logicLayerAbilityOffCooldown(buff, ability, cdTracker)
    if not ability.cdr then
        local caster = ability.caster
        local time_since = GetTime() - (cdTracker[caster][ability.name] or 0)

        -- ability.cooldown + buff.duration - sometimes abilities are identified
        -- when the buff expires. for fixed duration buffs, the ability must have been off
        -- coldown CD+DUR seconds ago, not just CD seconds ago.
        if time_since < ability.cooldown + buff.duration - ns.DURATION_TOLERANCE then
            traceLogic(buff, ability,
                "excluding (not off cd): last seen %0.3fs ago, cd=%ds, duration=%0.3fs, reject interval < %0.3fs",
                time_since, ability.cooldown, buff.duration,
                ability.cooldown + buff.duration - ns.DURATION_TOLERANCE)
            return false
        end
    end
    return true
end



local function getDurationDiff(buff, ability)
    return math.abs(buff.duration - ability.duration)
end



-- Was the buff's duration consistent with how the ability works?
local function logicLayerDurationMatches(buff, ability, useDuration)
    if useDuration then
        -- shorter variables for readability
        local diff = getDurationDiff(buff, ability)
        local dv = ability.duration_variable
        local tol = ns.DURATION_TOLERANCE

        if (dv == ns.DURATION_FIXED and diff > tol) or
           (dv == ns.DURATION_LTE and diff > tol and buff.duration > ability.duration) or
           (dv == ns.DURATION_GTE and diff > tol and buff.duration < ability.duration) then
            traceLogic(buff, ability, "excluding: duration not within tolerance (buff=%0.3f, ability=%03f, duration type=%d, diff=%0.3f)", buff.duration, ability.duration, dv, diff)
            return false
        end
    end
    return true
end



-- Does the ability trigger a concurrent debuff and if so, was there one?
-- This checks both for (1) if a debuff is required, there must be one and (2) if a
-- debuff is not required, there must not be one. These could definitely generate
-- false negatives (especially case 2), so need testing to see how reliable this is.
-- Maybe should remove case 2.
--   1. requires debuff: maybe UNIT_AURA can be called separately for the buff and debuff portions
--   2. does not require debuff: maybe another unrelated debuff was applied in the same event
local function logicLayerCheckConcurrentDebuffs(buff, ability)
    if ability.concurrentDebuff then
        if #buff.concurrentDebuffs == 0 then
            traceLogic(buff, ability,
                "excluding: requires concurrent debuff but %d debuffs observed",
                #buff.concurrentDebuffs)
            return false
        end
    else
        if #buff.concurrentDebuffs > 0 then
            traceLogic(buff, ability,
                "excluding: does not create concurrent debuff but %d debuffs observed",
                #buff.concurrentDebuffs)
            return false
        end
    end
    return true
end



local function getCastTimeDiff(buff, ability)
    local closest = buff.closestCasts[ability.caster] or ns.INFINITY
    local buffApplied = buff.startTime
    local diff = math.abs(closest - buffApplied)

    return closest, buffApplied, math.abs(closest - buffApplied)
end



-- Ensure the person who can cast this ability did cast something around the correct time
local function logicLayerCasterDidCast(buff, ability)
    local closest, buffApplied, diff = getCastTimeDiff(buff, ability)
    -- buttonPress - does the ability require the player to press a button? cheat death
    -- mechanics like last resort and golden valkyr proc without an action
    if ability.buttonPress and diff > ns.DURATION_TOLERANCE then
        traceLogic(buff, ability,
            "excluding: caster's closest cast=%0.3f, buff applied=%0.3f (diff=%0.3f)",
            closest, buffApplied, diff)
        return false
    end
    return true
end



-- logic layers are fundamentally an AND operation: ALL rules must be followed
-- for an ability to have produced a buff.
-- based on how each ability works, determine if it could have possibly produced
-- buff.
-- which ability is the best match is determined later.
local function getPossibleSolutions(buff, slot, useDuration, cdTracker)
    local maxCD = -1
    local possibleSolutions = {}

    for _, ability in pairs(ns.groupCDs[slot].abilities) do
        -- it's tempting to only use possible abilities, but the heuristics
        -- below can exclude abilities incorrectly due to the duration
        -- tolerances. so to be sure we have SOME fallback, take the max
        -- among all cds whether possible or not.
        maxCD = math.max(maxCD, ability.cooldown)

        -- important: logical statements in lua short circuit, so additional
        -- logic layers aren't evaluated if they aren't necessary.
        if logicLayerBuffFlags(buff, ability) and
           logicLayerAbilityOffCooldown(buff, ability, cdTracker) and
           logicLayerDurationMatches(buff, ability, useDuration) and
           logicLayerCheckConcurrentDebuffs(buff, ability) and
           logicLayerCasterDidCast(buff, ability) then
            traceLogic(buff, ability, "is a possible solution")
            -- All rules have passed, this ability is a possible match
            local x = ns:shallowcopy(ability)
            _, _, x.castTimeDiff = getCastTimeDiff(buff, ability)
            -- if we aren't using duration, set the diff to 0 so no ability is considered
            -- a better match than others.
            x.durationDiff = useDuration and getDurationDiff(buff, ability) or 0
            table.insert(possibleSolutions, x)
        end
    end

    return possibleSolutions, maxCD
end



local function traceConfidence(layerName, message, ...)
    ns:printDebug(string.format(
        "confidenceLayer(%s): " .. message,
        layerName, ...))
end



-- To be confident that one ability is the correct match, only need to look at the 2
-- best matches. If the second best match is significantly worse than the best match,
-- then so are all the other possible abilities and we can be confident. If it isn't,
-- the we can't be confident anyway.
local function getTopTwo(list, dummy, comparator)
    table.sort(list, comparator)

    local best = list[1] or dummy
    local second = list[2] or dummy

    return best, second
end



local function confidenceLayerOnlyOnePossible(possibleSolutions)
    return #possibleSolutions == 1 and possibleSolutions[1] or nil
end



local function confidenceLayerDuration(possibleSolutions)
    best, second = getTopTwo(possibleSolutions,
        { name='dummy', durationDiff=ns.INFINITY },
        function(a, b) return a.durationDiff <= b.durationDiff end)

    if second.durationDiff - best.durationDiff >= ns.DURATION_CONFIDENT_DIFFERENCE then
        traceConfidence('duration', 'success: best=%0.3f, second=%0.3f, required diff=%0.3f',
            best.durationDiff, second.durationDiff, ns.DURATION_CONFIDENT_DIFFERENCE)
        return best
    else
        traceConfidence('duration', 'failure: best=%0.3f, second=%0.3f, required diff=%0.3f',
            best.durationDiff, second.durationDiff, ns.DURATION_CONFIDENT_DIFFERENCE)
        return nil
    end
end



local function confidenceLayerCastTime(possibleSolutions)
    best, second = getTopTwo(possibleSolutions,
        { name='dummy', castTimeDiff=ns.INFINITY },
        function(a, b) return a.castTimeDiff <= b.castTimeDiff end)

    if second.castTimeDiff - best.castTimeDiff >= ns.CASTTIME_CONFIDENT_DIFFERENCE then
        return best
    else
        traceConfidence('castTime', 'failure: best=%0.3f, second=%0.3f, required diff=%0.3f',
            best.castTimeDiff, second.castTimeDiff, ns.CASTTIME_CONFIDENT_DIFFERENCE)
        return nil
    end
end



-- Special handling for DH's meta due to the apex talent. If the only 2
-- valid abilities are meta and the apex talent, then we don't know which
-- cooldown to initiate, but we do know that the buff attained is meta. So
-- return the buff so that we can display it now on the frames as active.
--
-- This can only happen at initial inference since the buffs have different
-- duration.
local function confidenceLayerMetamorphosis(possibleSolutions)
    if #possibleSolutions == 2 then
        local s1 = possibleSolutions[1]
        local s2 = possibleSolutions[2]
        if (s1.name == "Metamorphosis" and s2.name == "Untethered Rage") or
           (s2.name == "Metamorphosis" and s1.name == "Untethered Rage") then
            return s1.name == "Metamorphosis" and s1 or s2
        end
        traceConfidence('Metamorphosis', 'failure: not the two correct possible solutions s1=[%s], s2=[%s]',
            s1.name, s2.name)
        return nil
    else
        traceConfidence('Metamorphosis', 'failure: #possibleSolutions=%d (not 2)',
            #possibleSolutions)
        return nil
    end
end



-- Given a list of possible abilities that could have produced buff, determine:
--    1. what the best matching solution is
--    2. whether the best matching solution is a *significantly better* match than
--       all other possible solutions.
--
-- Keep in mind that it is VERY common for defensives that there's only one possible
-- matching ability, even without duration knowledge.
--
-- When there are multiple possible abilities, the instant identification rate will
-- be low.
-- A good illustration is blessing of freedom: it is NOT flagged as an external, can
-- be cast on anyone, and has a (1,0,0) flag set, which is a common flag set for
-- important personals like DH metamorphosis. Freedom can be easily
-- distinguished from meta after it completes via duration, but instant IDing is hard.
-- Everyone is likely casting something every GCD, so there is a high chance that
-- both the DH and paladin cast something near the time the buff was observed.
--
-- If confidence is attained, return the ability otherwise return nil.
-- Confidence layers are fundamentally an OR operation: if any of the layers can
-- *confidently* (this word is doing a lot of work here) distinguish between abilities,
-- then we have a match.
--
-- XXX: TODO: Would be nice to do a consistency check across confidence layers to
-- make sure the confident ones agree with each other.
local function getConfidentMatch(possibleSolutions)
    match = confidenceLayerOnlyOnePossible(possibleSolutions) or
        confidenceLayerCastTime(possibleSolutions) or
        confidenceLayerDuration(possibleSolutions) or
        confidenceLayerMetamorphosis(possibleSolutions)

    return match
end



-- Use various rules about who can cast what ability on whom to narrow down
-- the possible abilities that could be "buff".
--
-- Will always produce some non-nil value for buff.cooldown - the worst it
-- could be is the maximum across all possible abilities that can target this player.
function ns:inferAbility(slot, buff, useDuration, cdTracker)
    ns:printDebug(string.format(
        "|cffD8B87CStarting inference(slot=[%s], time=%0.3f) ------------------------------|r",
        slot, GetTime()))
    if useDuration == nil then useDuration = true end

    -- allow the caller to override the tracked state of CDs to simulate an
    -- unknown state. useful for determining which abilities are ALWAYS
    -- uniquely identifiable.
    cdTracker = cdTracker or ns.cdTracker

    -- all logic and ranking is performed in these two lines
    possibleSolutions, maxCD = getPossibleSolutions(buff, slot, useDuration, cdTracker)

    abilityMatch = getConfidentMatch(possibleSolutions)
    if abilityMatch and not PetesDefensiveHistoryOptionsDb.disableInference then
        buff.name = abilityMatch.name
        buff.cooldown = abilityMatch.cooldown
        buff.spellId = abilityMatch.id
        -- XXX: TODO: fairly sure this is dead, remove later
        --buff.external = abilityMatch.external
        buff.iconId = abilityMatch.iconId
        buff.caster = abilityMatch.caster
        buff.certainOnFirstInference = abilityMatch.certainOnFirstInference
        buff.activeBuff = abilityMatch.activeBuff
    else
        buff.cooldown = maxCD
        ns:printDebug("couldn't infer ability")
    end

    return ns:isAbilityInferred(buff)
end



-- Simulate the solving problem by generating buffs that perfectly match
-- all expectations of the ability and then asking the inference engine to
-- infer the ability.
--
-- "zeroKnowledge" - don't use the internal CD tracker, don't use cast time
--      matching. Only infer abilities using the minimum possible info.
function ns:zeroKnowledgeSolve()
    for slot, _ in pairs(ns.allSlots) do
        abilities = ns.groupCDs[slot].abilities
        for _, ability in pairs(abilities) do
            -- make the buff we would expect to see if this ability got used.
            -- for abilities with isBuff=false, the buff payload needs to match the
            -- buff the ability applied. E.g., cheat death on prot paladin triggers
            -- GoAK, but we want to track the cheat death cooldown as a separate ability
            local buff = {
                slot = slot,
                startTime = GetTime(),
                endTime = GetTime() + ability.duration,
                duration = ability.duration,
                isImportant = ability.importantFlag,
                isBigDefensive = ability.bigFlag,
                isExternal = ability.externalFlag,
                isRaid = ability.raidFlag,
                isRaidInCombat = ability.raidInCombatFlag,
                numUpdates = 0,
                concurrentDebuffs = {},
                closestCasts = {}
            }

            -- if the ability is supposed to come with a concurrent debuff, give it a
            -- dummy aura. It doesn't matter what the auraInstanceId is.
            if ability.concurrentDebuff then
                table.insert(buff.concurrentDebuffs, 1)
            end

            -- give every group member a cast at the perfect time, allowing the ability to
            -- pass the logic layers but never to be identified based on cast time-matching
            -- in the confidence layers.
            for slot, _ in pairs(ns.allSlots) do
                buff.closestCasts[slot] = GetTime()  
            end

            -- forget everything the internal CD tracker knows about abilities that are
            -- currently on cooldown (from previous successful inferences).
            blankCDs = {}
            for slot, _ in pairs(ns.allSlots) do
                blankCDs[slot] = {}
            end

            ns:inferAbility(slot, buff, false, blankCDs)
            ability.solved = ns:isAbilityInferred(buff)
            -- would be nice if inferAbility would return the conflicting spell/caster combos
            ability.conflicts = {}
        end
    end
end
