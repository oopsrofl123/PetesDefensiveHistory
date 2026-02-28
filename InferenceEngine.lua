local _, ns = ...

-- Aura removal events aren't processed at exactly the moment the buff
-- is removed. E.g., if a buff lasts 12s it is common to see the removal
-- event at 12.05s or 11.95s.
--
-- The tolerance defines the maximum difference between the nominal buff
-- duration and the measured buff duration that counts as match.
DURATION_TOLERANCE = 0.15

-- Some abilities cause concurrent events. Some apply other buffs or
-- debuffs (e.g., hypothermia/ice block, forbearance/bubble) or fire other
-- events (e.g., AMS applies a shield that causes a UNIT_ABSORB_AMOUNT_CHANGED
-- event). Despite being "concurrent", these actions can occur in different
-- event payloads, meaning we have to wait some amount of time to witness them.
-- Some (like the AMS example) always occur in other payloads because they
-- aren't UNIT_AURA events. So: how long must we wait before we decide that
-- an action *did not* occur?
--
-- Multiple inference is required to make use of this extra information. This
-- parameter both:
--   1. How long must we wait past the buff application to declare that
--      no "concurrent" action occurred.
--   2. Similar to duration tolerance, how far from the buff application
--      counts as "concurrent"?
CONCURRENT_EVENT_TOLERANCE = 0.125

-- How much better the best possible solution must be than the second
-- best possible solution.
DURATION_CONFIDENT_DIFFERENCE = 0.5

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
CASTTIME_CONFIDENT_DIFFERENCE = 0.150


-- Return a 2-tuple:
--     (inferred ability or nil, certain: true|false)
--
-- It is legal to return an ability that is not assigned with certainty, however
-- certain will never be true if ability is nil (no ability was assigned). This
-- allows us to return "working guesses" when it's useful. E.g., multiple abilities
-- can cause the metamorphosis buff and it is useful to know that the meta buff is
-- active until we can determine with certainty which ability applied the meta buff.
function ns:getAbility(buff)
    return buff.ability, buff.certain
end



local function traceLogic(buff, ability, message, ...)
    if not ns:GetOption('muteVerboseDebugging') then
        ns:printDebug(string.format(
            "ability=[%s], target=[%s], caster=[%s]: " .. message,
            ability.name, buff.target, ability.caster, ...))
    end
end



-- Do Blizzard's aura flags match?
local function logicLayerBuffFlags(buff, ability)
    if buff.IMPORTANT ~= ability.IMPORTANT or
       buff.BIG ~= ability.BIG or
       buff.EXTERNAL ~= ability.EXTERNAL or
       buff.RAID ~= ability.RAID or
       buff.RAIDINCOMBAT ~= ability.RAIDINCOMBAT then
        traceLogic(buff, ability,
            "excluded (flags): buff=(%d,%d,%d,%d,%d), ability=(%d,%d,%d,%d,%d)",
            buff.IMPORTANT and 1 or 0,
            buff.BIG and 1 or 0,
            buff.EXTERNAL and 1 or 0,
            buff.RAID and 1 or 0,
            buff.RAIDINCOMBAT and 1 or 0,
            ability.IMPORTANT and 1 or 0,
            ability.BIG and 1 or 0,
            ability.EXTERNAL and 1 or 0,
            ability.RAID and 1 or 0,
            ability.RAIDINCOMBAT and 1 or 0)
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
        -- To cast the ability, just need 1 charge to be off cooldown. So check
        -- the oldest charge - if that one isn't available then no younger charge
        -- can possibly be available.
        local offCDat = cdTracker[ability.caster][ability.name]:tail()

        -- if the buff was applied before the oldest charge came off CD, then this
        -- ability had no charges available to use (was fully on CD).  Allow a small
        -- tolerance.
        if buff.startTime + DURATION_TOLERANCE < offCDat then
            traceLogic(buff, ability,
                "excluded (not off cd): recharging until [%0.3fs], buff applied at [%0.3fs]",
                offCDat, buff.startTime)
            return false
        end
    end
    return true
end



local function getDurationDiff(buff, ability)
    return math.abs(buff.duration - ability.duration)
end



-- Was the buff's duration consistent with how the ability works?
local function logicLayerDurationMatches(buff, ability)
    local buffIsBeingRemoved = buff.endTime ~= nil

    local diff = getDurationDiff(buff, ability)
    local dv = buffIsBeingRemoved and ability.duration_variable or ns.DURATION_LTE
    local tol = DURATION_TOLERANCE

    if (dv == ns.DURATION_FIXED and diff > tol) or
       (dv == ns.DURATION_LTE and diff > tol and buff.duration > ability.duration) or
       (dv == ns.DURATION_GTE and diff > tol and buff.duration < ability.duration) then
        traceLogic(buff, ability,
            "excluded (incorrect duration): buff=%0.3f, ability=%03f, duration type=%d, diff=%0.3f",
            buff.duration, ability.duration, dv, diff)
        return false
    end
    return true
end



local function getCastTimeDiff(buff, ability)
    local closest = buff.closest_cast[ability.caster] or ns.INFINITY
    local buffApplied = buff.startTime
    local diff = math.abs(closest - buffApplied)

    return closest, buffApplied, math.abs(closest - buffApplied)
end



-- Generalized event logic layer
local function getEventTimeDiff(buff, ability, event)
    local closest = buff["closest_"..event][ability.caster] or ns.INFINITY
    return closest, buff.startTime, math.abs(closest - buff.startTime)
end

local function logicLayerRequireConcurrentEvent(buff, ability, event)
    local closest, buffApplied, diff = getEventTimeDiff(buff, ability, event)
    -- buff.duration: hack to avoid zillions of GetTime() calls:
    -- the "duration" is how long the buff has existed so far, not
    -- necessarily the final length of the buff. In this usage, we want
    -- to know how long it's been since the event we want to infer happened
    -- to decide whether it's been long enough to definitively state that
    -- the other required concurrent event should have been seen by now.
    if diff > CONCURRENT_EVENT_TOLERANCE and buff.duration > CONCURRENT_EVENT_TOLERANCE then
        traceLogic(buff, ability,
            "excluded: closest [%s]=%0.3f, applied=%0.3f (diff=%0.3f)",
            event, closest, buffApplied, diff)
        return false
    -- Only for spammy debugging
    --else
        --traceLogic(buff, ability,
            --"accepted: closest [%s]=%0.3f, applied=%0.3f (diff=%0.3f)",
            --event, closest, buffApplied, diff)
    end
    return true
end



-- logic layers are fundamentally an AND operation: ALL rules must be followed
-- for an ability to have produced a buff.
-- based on how each ability works, determine if it could have possibly produced
-- buff.
-- which ability is the best match is determined later.
local function getPossibleSolutions(char, buff, cdTracker)
    local maxCD = -1
    local possibleSolutions = {}

    for _, ability in pairs(char:getPossibleAbilities()) do
        -- it's tempting to only use possible abilities, but the heuristics
        -- below can exclude abilities incorrectly due to the duration
        -- tolerances. so to be sure we have SOME fallback, take the max
        -- among all cds whether possible or not.
        maxCD = math.max(maxCD, ability.cooldown)

        -- important: logical statements in lua short circuit, so additional
        -- logic layers aren't evaluated if they aren't necessary.
        if logicLayerBuffFlags(buff, ability) and
           logicLayerAbilityOffCooldown(buff, ability, cdTracker) and
           logicLayerDurationMatches(buff, ability) and
           (not ability.requireConcurrentBuff or logicLayerRequireConcurrentEvent(buff, ability, "buff")) and
           (not ability.requireConcurrentDebuff or logicLayerRequireConcurrentEvent(buff, ability, "debuff")) and
           (not ability.requireConcurrentShield or logicLayerRequireConcurrentEvent(buff, ability, "shield")) and
           (not ability.requireButtonPress or logicLayerRequireConcurrentEvent(buff, ability, "cast")) then
            traceLogic(buff, ability, "is a possible solution")
            -- All rules have passed, this ability is a possible match
            local x = ns:shallowcopy(ability)
            _, _, x.castTimeDiff = getCastTimeDiff(buff, ability)
            -- if we aren't using duration, set the diff to 0 so no ability is considered
            -- a better match than others.
            x.durationDiff = buff.endTime ~= nil and getDurationDiff(buff, ability) or 0
            table.insert(possibleSolutions, x)
        end
    end

    return possibleSolutions, maxCD
end



local function traceConfidence(layerName, message, ...)
    if not ns:GetOption('muteVerboseDebugging') then
        ns:printDebug(string.format(
            "confidenceLayer(%s): " .. message,
            layerName, ...))
    end
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


----------------------------------------------------------------------------
-- Confidence layers return one of:
--   1. nil
--   2. (ability, certain=true|false)
----------------------------------------------------------------------------

local function confidenceLayerOnlyOnePossible(possibleSolutions)
    if #possibleSolutions == 1 then
        traceConfidence('onlyOnePossible', 'success: #possibleSolutions=%d',
            #possibleSolutions)
        return { possibleSolutions[1], true }
    else
        traceConfidence('onlyOnePossible', 'failure: #possibleSolutions=%d',
            #possibleSolutions)
        return nil
    end
end



local function confidenceLayerDuration(possibleSolutions)
    best, second = getTopTwo(possibleSolutions,
        { name='dummy', durationDiff=ns.INFINITY },
        function(a, b) return a.durationDiff <= b.durationDiff end)

    if second.durationDiff - best.durationDiff >= DURATION_CONFIDENT_DIFFERENCE then
        traceConfidence('duration', 'success: best=%0.3f, second=%0.3f, required diff=%0.3f',
            best.durationDiff, second.durationDiff, DURATION_CONFIDENT_DIFFERENCE)
        return { best, true }
    else
        traceConfidence('duration', 'failure: best=%0.3f, second=%0.3f, required diff=%0.3f',
            best.durationDiff, second.durationDiff, DURATION_CONFIDENT_DIFFERENCE)
        return nil
    end
end



-- The best possible solutions can have different cast times if they come
-- from different characters.
local function confidenceLayerCastTime(possibleSolutions)
    best, second = getTopTwo(possibleSolutions,
        { name='dummy', castTimeDiff=ns.INFINITY },
        function(a, b) return a.castTimeDiff <= b.castTimeDiff end)

    if second.castTimeDiff - best.castTimeDiff >= CASTTIME_CONFIDENT_DIFFERENCE then
        return { best, true }
    else
        traceConfidence('castTime', 'failure: best=%0.3f, second=%0.3f, required diff=%0.3f',
            best.castTimeDiff, second.castTimeDiff, CASTTIME_CONFIDENT_DIFFERENCE)
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
            return { (s1.name == "Metamorphosis" and s1 or s2), false }
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
    ns:printDebug("getConfidentMatch("..#possibleSolutions..")")
    match = confidenceLayerOnlyOnePossible(possibleSolutions) or
        confidenceLayerCastTime(possibleSolutions) or
        confidenceLayerDuration(possibleSolutions) or
        confidenceLayerMetamorphosis(possibleSolutions)

    -- for convenience: unpack the 2 tuple
    if match then
        return match[1], match[2]
    else
        return nil
    end
end



-- Use various rules about who can cast what ability on whom to narrow down
-- the possible abilities that could be "buff".
--
-- Will always produce some non-nil value for buff.cooldown - the worst it
-- could be is the maximum across all possible abilities that can target this player.
function ns:inferAbility(char, buff, cdTracker)
    -- track how many times we've tried to infer this ability
    buff.inference = buff.inference + 1

    ns:printDebug(string.format(
        "|cffD8B87CStarting inference(time[%0.3f], target=[%s], attempt=[%d]) ---------------------------------|r",
        GetTime(), char:getID(), buff.inference))

    -- allow the caller to override the tracked state of CDs to simulate an
    -- unknown state. useful for determining which abilities are ALWAYS
    -- uniquely identifiable.
    cdTracker = cdTracker or ns.cdTracker

    -- all logic and ranking is performed in these two lines
    possibleSolutions, maxCD = getPossibleSolutions(char, buff, cdTracker)
    -- maxCD is a property of the observation because it depends on the time of
    -- the final inference. e.g., the CD tracker state could've changed, removing
    -- some CDs from consideration.
    buff.maxCD = maxCD

    -- assignments can be uncertain. e.g., multiple abilities with different CDs
    -- can apply the same buff. it can be useful to know what buff is
    -- present even if it can't be pinned to an ability.
    abilityMatch, certain = getConfidentMatch(possibleSolutions)
    -- Check for disableInference here, not at function start, so that maxCD can
    -- be computed for use by the history tray.
    if abilityMatch and not ns:GetOption('disableInference') then
        buff.ability = abilityMatch
        buff.certain = certain
    else
        ns:printDebug("couldn't infer ability")
    end

    return ns:getAbility(buff)
end



-- Simulate the solving problem by generating buffs that perfectly match
-- all expectations of the ability and then asking the inference engine to
-- infer the ability.
--
-- "zeroKnowledge" - don't use the internal CD tracker, don't use cast time
--      matching. Only infer abilities using the minimum possible info.
function ns:zeroKnowledgeSolve()
    local now = GetTime()

    local idealEventTrackers = {}
    -- give every group member a cast at the perfect time, allowing the ability to
    -- pass the logic layers but never to be identified based on cast time-matching
    -- in the confidence layers.
    for guid, char in pairs(ns:getTrackedCharacters()) do
        local tracker = ns:makeEventTracker()
        tracker.buff:push(now)
        tracker.cast:push(now)
        tracker.shield:push(now)
        tracker.debuff:push(now)
        idealEventTrackers[guid] = tracker
    end

    -- forget everything the internal CD tracker knows about abilities that are
    -- currently on cooldown (from previous successful inferences).
    blankCDs = ns:initCDTracker()

    for guid, char in pairs(ns:getTrackedCharacters()) do
        abilities = char:getPossibleAbilities()
        for _, ability in pairs(abilities) do
            -- make the buff we would expect to see if this ability got used.
            local buff = {
                inference = 0,
                target = guid,
                startTime = now,
                -- XXX: TODO: to match previous behavior (old useDuration=false),
                -- do not set the endTime field. could also re-run inference if the
                -- first fails to simulate whether the buff would be IDed at removal.
                --endTime = now + ability.duration,
                duration = ability.duration,
                IMPORTANT = ability.IMPORTANT,
                BIG = ability.BIG,
                EXTERNAL = ability.EXTERNAL,
                RAID = ability.RAID,
                RAIDINCOMBAT = ability.RAIDINCOMBAT,
                numUpdates = 0,
            }

            ns:prepareForInference(buff, idealEventTrackers)

            ns:printDebug("simulating ability=["..ability.name.."]")
            local _, certain = ns:inferAbility(char, buff, blankCDs)
            ability.solved = certain
            -- would be nice if inferAbility would return the conflicting spell/caster combos
            ability.conflicts = {}
        end
    end
end
