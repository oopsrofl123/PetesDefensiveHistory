local _, ns = ...

-- Aura removal events aren't processed at exactly the moment the buff
-- is removed. E.g., if a buff lasts 12s it is common to see the removal
-- event at 12.05s or 11.95s.
--
-- The tolerance defines the maximum difference between the nominal buff
-- duration and the measured buff duration that counts as match.
ns.DURATION_TOLERANCE = 0.15

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
CONCURRENT_EVENT_TOLERANCE = 0.050

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


local function traceLogic(event, ability, message, ...)
    if not ns:GetOption('muteVerboseDebugging') then
        ns:printDebug(string.format(
            "ability=[%s], target=[%s], caster=[%s]: " .. message,
            ability.alias or ability.name,
            event:getSlot(),
            ns:cosmeticOnlyMapGUIDToSlot(ability.caster), ...))
    end
end



-- Do Blizzard's aura flags match?
local function logicLayerAuraFlags(event, ability)
    -- if it's a nonAuraEvent, choose a flag set that should never match with an aura event
    local buff = event:getAura() or { IMPORTANT=false, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false }

    if buff.IMPORTANT ~= ability.IMPORTANT or
       buff.BIG ~= ability.BIG or
       buff.EXTERNAL ~= ability.EXTERNAL or
       buff.RAID ~= ability.RAID or
       buff.RAIDINCOMBAT ~= ability.RAIDINCOMBAT then
        traceLogic(event, ability,
            "excluded (flags): buff=(%d,%d,%d,%d,%d), ability=(%d,%d,%d,%d,%d)",
            ns:boolstr(buff.IMPORTANT),
            ns:boolstr(buff.BIG),
            ns:boolstr(buff.EXTERNAL),
            ns:boolstr(buff.RAID),
            ns:boolstr(buff.RAIDINCOMBAT),
            ns:boolstr(ability.IMPORTANT),
            ns:boolstr(ability.BIG),
            ns:boolstr(ability.EXTERNAL),
            ns:boolstr(ability.RAID),
            ns:boolstr(ability.RAIDINCOMBAT))
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
local function logicLayerAbilityOffCooldown(event, ability, cdTracker)
    -- XXX: TODO: better handling for resets. for now, if the ability CAN reset
    -- we give up using its CD information in inference.
    if not ability.reset then
        -- To cast the ability, just need 1 charge to be off cooldown. So check
        -- the oldest charge - if that one isn't available then no younger charge
        -- can't possibly be available.
        local offCDat = cdTracker[ability.caster][ability.name]:tail()
        -- XXX: TODO: If the ability has dynamic CDR, an accurate offCDat isn't
        -- available. However, it is helpful to model these abilities as having
        -- *some* amount of cooldown to remove the ability from the possible list
        -- for at least a little while. A wild guess: even the most potent dynamic
        -- CDR cannot reduce the cooldown of an ability by over 70%, so let's give
        -- CDR abilities a minimum cooldown of 30% of the nominal CD.
        if ability.cdr then
            -- offCDat from the tracker records the full cooldown (i.e., ignores CDR)
            -- (offCDat - ability.cooldown) is the nominal CD length. compress it to
            -- 30%. N.B. this (and everything else) is hopelessly broken for >1charge+CDR
            -- abilities. who cares at this point.
            offCDat = offCDat - 0.7*ability.cooldown
        end

        -- if the buff was applied before the oldest charge came off CD, then this
        -- ability had no charges available to use (was fully on CD).  Allow a small
        -- tolerance.
        if event:getTime() + ns.DURATION_TOLERANCE < offCDat then
            traceLogic(event, ability,
                "excluded (not off cd): recharging until [%0.3fs], event at [%0.3fs]",
                offCDat, event:getTime())
            return false
        end
    end
    return true
end




-- Was the aura's duration consistent with how the ability works?
-- General events: come across a scenario where this applies
local function logicLayerDurationMatches(event, ability)
    local aura = event:getAura()
    if aura then
        local buffDuration = event:timeSince()
        local diff = math.abs(buffDuration - ability.duration)
        local dv = event:isExpiring() and ability.duration_variable or ns.DURATION_LTE
        local tol = ns.DURATION_TOLERANCE

        if (dv == ns.DURATION_FIXED and diff > tol) or
           (dv == ns.DURATION_LTE and diff > tol and buffDuration > ability.duration) or
           (dv == ns.DURATION_GTE and diff > tol and buffDuration < ability.duration) then
            traceLogic(event, ability,
                "excluded (incorrect duration): event=%0.3f, ability=%03f, duration type=%d, diff=%0.3f",
                buffDuration, ability.duration, dv, diff)
            return false
        end
    end
    return true
end



local function logicLayerRequireEvent(event, ability, evidenceType, eventActor)
    if eventActor == "caster" then
        eventActor = ability.caster
    elseif eventActor == "target" then
        eventActor = event:getTarget()
    else
        print("PROGRAMMER ERROR: bad eventActor in logicLayerRequireEvent")
    end

    local closest, diff = event:timeSinceClosest(evidenceType, eventActor)
    
    -- the "duration" is how long the event has been tracked, not necessarily
    -- the final length of the buff, if there is one. In this usage, we want
    -- to know how long it's been since the event we want to infer happened
    -- to decide whether it's been long enough to definitively state that
    -- the other required concurrent event should have been seen by now.
    if diff > CONCURRENT_EVENT_TOLERANCE or event:timeSince() > CONCURRENT_EVENT_TOLERANCE then
        traceLogic(event, ability,
            "excluded: actor=[%s], closest [%s]=%0.3f, applied=%0.3f (diff=%0.3f)",
            ns:cosmeticOnlyMapGUIDToSlot(actor), evidenceType, closest, event:getTime(), diff)
        return false
    -- Only for very spammy debugging
    --else
        --traceLogic(event, ability,
            --"accepted: closest [%s]=%0.3f, applied=%0.3f (diff=%0.3f)",
            --evidenceType, closest, event:getTime(), diff)
    end
    return true
end



-- logic layers are fundamentally an AND operation: ALL rules must be followed
-- for an ability to have produced a event.
-- based on how each ability works, determine if it could have possibly produced
-- event.
-- which ability is the best match is determined later.
local function getPossibleSolutions(event, cdTracker)
    local char = event:getCharacter() -- Character object, not GUID string
    local maxCD = -1
    local possibleSolutions = {}

    for _, ability in pairs(char:getPossibleAbilities()) do
        maxCD = math.max(maxCD, ability.cooldown)

        -- logical statements in lua short circuit, so additional
        -- logic layers aren't evaluated if they aren't necessary.
        if logicLayerAuraFlags(event, ability) and
           logicLayerAbilityOffCooldown(event, ability, cdTracker) and
           logicLayerDurationMatches(event, ability) and
           (not ability.requireBuff or logicLayerRequireEvent(event, ability, "buff", "target")) and
           (not ability.requireDebuff or logicLayerRequireEvent(event, ability, "debuff", "target")) and
           (not ability.requireShield or logicLayerRequireEvent(event, ability, "shield", "target")) and
           (not ability.requireCombatDrop or logicLayerRequireEvent(event, ability, "combatDrop", "target")) and
           (not ability.requireButtonPress or logicLayerRequireEvent(event, ability, "cast", "caster")) then
            traceLogic(event, ability, "is a possible solution")
            -- All rules have passed, this ability is a possible match
            local x = ns:shallowcopy(ability)
            _, x.castTimeDiff = event:timeSinceClosest("cast", ability.caster)
            -- don't match on duration unless there is an expiring event
            x.durationDiff = event:isExpiring() and math.abs(event:timeSince() - ability.duration) or 0
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
-- return the meta ability so that we can display it now on the frames as active.
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



-- Given a list of possible abilities that could have produced event, determine:
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
-- both the DH and paladin cast something near the time the event was observed.
--
-- If confidence is attained, return the ability otherwise return nil.
-- Confidence layers are fundamentally an OR operation: if any of the layers can
-- *confidently* (this word is doing a lot of work here) distinguish between abilities,
-- then we have a match.
--
-- XXX: TODO: Would be nice to do a consistency check across confidence layers to
-- make sure the confident ones agree with each other.
local function getConfidentMatch(possibleSolutions)
    local match = false

    -- This if statement is only to prevent printing the confidence traces when there
    -- are 0 possible solutions. Otherwise the code below handles the 0 solution
    -- situation perfectly well.
    if #possibleSolutions > 0 then
        ns:printDebug("getConfidentMatch("..#possibleSolutions..")")
        match = confidenceLayerOnlyOnePossible(possibleSolutions) or
            confidenceLayerCastTime(possibleSolutions) or
            confidenceLayerDuration(possibleSolutions) or
            confidenceLayerMetamorphosis(possibleSolutions)
    else
        ns:printDebug("getConfidentMatch("..#possibleSolutions..").. skipping")
    end

    -- for convenience: unpack the 2 tuple
    if match then
        return match[1], match[2]
    else
        return nil
    end
end



-- Use various rules about who can cast what ability on whom to narrow down
-- the possible abilities that could be "event".
function ns:inferAbility(inferenceTrace, ev, cdTracker)
    -- track how many times we've tried to infer this ability
    ev:incrementInference()

    ns:printDebug(string.format(
        "|cffD8B87CInfer(time=[%0.3f], tr(poll)=[%s], tr(event)=[%s], target=[%s], eventId=[%s], attempt=[%d])|r",
        GetTime(), inferenceTrace, ev:getTrace(),
        ev:getSlot(), ev:getId(), ev:getInference()))

    -- allow the caller to override the tracked state of CDs to simulate an
    -- unknown state. useful for determining which abilities are ALWAYS
    -- uniquely identifiable.
    cdTracker = cdTracker or ns.cdTracker

    -- all logic and ranking is performed in these two lines
    possibleSolutions, maxCD = getPossibleSolutions(ev, cdTracker)
    -- set maxCD at each inference in case one day it uses exclusion information
    ev:setMaxCD(maxCD)

    -- assignments can be uncertain. e.g., multiple abilities with different CDs
    -- can cause the same event. if true, it is sometimes useful to report what
    -- *event* occurred.
    abilityMatch, certain = getConfidentMatch(possibleSolutions)
    -- Check for disableInference here, not at function start, so that maxCD can
    -- be computed for use by the history tray.
    if abilityMatch and not ns:GetOption('disableInference') then
        ev:setAbility(abilityMatch)
        ev:setCertain(certain)
    else
        ns:printDebug("couldn't infer ability")
    end

    return ev:getAbility()
end



-- Simulate the solving problem by generating events that perfectly match
-- all expectations of the ability and then asking the inference engine to
-- infer the ability.
--
-- "zeroKnowledge" - don't use the internal CD tracker, don't use cast time
--      matching. Only infer abilities using the minimum possible info.
function ns:zeroKnowledgeSolve()
    local now = GetTime()

    -- XXX: TODO: need to build an appropriate ideal event tracker for each ability
    local idealEventTrackers = {}
    -- give every group member a cast at the perfect time, allowing the ability to
    -- pass the logic layers but never to be identified based on cast time-matching
    -- in the confidence layers.
    for guid, char in pairs(ns:getTrackedCharacters()) do
        local tracker = ns:makeEvidenceTracker()
        tracker.buff:push(now)
        tracker.cast:push(now)
        tracker.shield:push(now)
        tracker.debuff:push(now)
        tracker.combatDrop:push(now)
        idealEventTrackers[guid] = tracker
    end

    -- forget everything the internal CD tracker knows about abilities that are
    -- currently on cooldown (from previous successful inferences).
    blankCDs = ns:initCDTracker()

    for guid, char in pairs(ns:getTrackedCharacters()) do
        abilities = char:getPossibleAbilities()
        for _, ability in pairs(abilities) do
            -- make the event we would expect to see if this ability got used.
            local event = ns:Event("SIMULATE("..ability.name..")", guid)

            -- make the expected buff and link it to the event
            event:setAura({
                auraInstanceId=-1,
                target=guid,
                -- XXX: TODO: to match previous behavior (old useDuration=false),
                -- do not set the endTime field. could also re-run inference if the
                -- first fails to simulate whether the event would be IDed at removal.
                --aura.endTime = now + ability.duration,
                IMPORTANT=ability.IMPORTANT,
                BIG=ability.BIG,
                EXTERNAL=ability.EXTERNAL,
                RAID=ability.RAID,
                RAIDINCOMBAT=ability.RAIDINCOMBAT
            })

            event:prepareForInference(idealEventTrackers)
            local _, certain = ns:inferAbility("SIMULATE("..ability.name..")", event, blankCDs)
            ability.solved = certain
            -- XXX: TODO: inferAbility should return the conflicting spell/caster combos
            ability.conflicts = {}
        end
    end
end
