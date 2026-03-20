local _, ns = ...

local inferenceRecordList = {}

function ns:getInferenceRecordData()
    return inferenceRecordList
end

-- Aura removal events aren't processed at exactly the moment the buff
-- is removed. E.g., if a buff lasts 12s it is common to see the removal
-- event at 12.05s or 11.95s.
--
-- The tolerance defines the maximum difference between the nominal buff
-- duration and the measured buff duration that counts as match. This can
-- be lax - usually abilities differ by at least 1s in nominal duration if
-- they differ at all. I have seen cases of 0.23s differences. Should be
-- less than DURATION_CONFIDENT_DIFFERENCE
ns.DURATION_TOLERANCE = 0.30

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
ns.CONCURRENT_EVENT_TOLERANCE = 0.100

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


-- Make a permanent record for each inference attempt that can be used immediately
-- for print/logging and later for analysis. At the moment, very reluctant to store
-- a reference to the original event or character since these records are meant to
-- be kept for a long time.
function ns:InferenceRecord(now, trace, event)
    local r = {}
    local inferenceTime = now
    local inferenceTrace = trace                -- code path leading to this inference
    local inferenceAttempt = event:getInference()  -- attempt number
    local eventTime = event:getTime()
    local eventTrace = event:getTrace()         -- code path that created the event
    local eventId = event:getId()
    local eventSource = event:getSource()
    local eventSlot = event:getSlot()
    local batchId = event:getBatchId()
    local logicLayersByAbility = {}
    local confidenceLayers = {}
    local requiredEvidence = {}
    local ability
    local certain = false

    function r:setAbility(ab) ability = ab end

    function r:setCertain(cert) certain = cert end

    function r:setLogicLayersByAbility(logic) logicLayersByAbility = logic end

    function r:setConfidenceLayers(conf) confidenceLayers = conf end

    function r:setRequiredEvidence(reqs) requiredEvidence = reqs end

    function r:toString()
        return string.format(
            "|cffEFD097Infer(tr(infer)=[%s], tr(event)=[%s], source=[%s], eventId=[%s/%d], attempt=[%d])|r",
            inferenceTrace, eventTrace,
            eventSlot, eventId, batchId, inferenceAttempt)
    end

    -- Make a stripped-down table without key names to save space for exporting
    local function stripLogic()
        local logicLayers = {}
        for _, record in pairs(logicLayersByAbility) do
            local thisAbil = {}
            for name, result in pairs(record.logicSummary.logic) do
                thisAbil[ns.logicLayerAliases[name]] = { result.pass, result.final }
            end
            local stripped = { record.caster, record.abilityId, record.logicSummary.pass, thisAbil }
            table.insert(logicLayers, stripped)
        end
        return logicLayers
    end

    local function logicStringForAbility(caster, abilityId, logicSummary, compact)
        -- supposedly building a table -> table.concat is faster than piecewise `..`
        local ability = ns.AbilityIdMap[abilityId]
        local tag = (ability.alias or ability.name)
        -- only show the caster if it isn't the same as the target
        if caster ~= eventSource then
            tag = tag .. "_" .. ns:cosmeticOnlyMapGUIDToSlot(caster)
        end
        local t = { tag .. ":" }
        for name, result in pairs(logicSummary.logic) do
            local s = (result.pass and "|cFFAFD5AB" or "|cFFFA003F") ..
                      (compact and ns.logicLayerAliases[name] or name) .. 
                      (result.final and "" or "*") .. "|r"
            table.insert(t, s)
        end
        result = "[" .. table.concat(t, compact and "" or ",") .. "]"
        return result
    end

    function r:logicString(passing, compact)
        compact = compact or true

        -- supposedly building a table -> table.concat is faster than piecewise `..`
        local t = {}
        for _, record in pairs(logicLayersByAbility) do
            if record.logicSummary.pass == passing then
                local str = logicStringForAbility(
                    record.caster,
                    record.abilityId, 
                    record.logicSummary, compact)
                table.insert(t, str)
            end
        end
        return table.concat(t, " ")
    end

    -- Make a stripped-down table without key names to save space for exporting
    local function stripConfidence()
        local abId = confidenceLayers.ability and confidenceLayers.ability.id or nil
        local certain = confidenceLayers.certain
        local numPossible = confidenceLayers.numPossible
        local layers = {}

        for _, match in pairs(confidenceLayers.layers) do
            local layerName, ability, certain = unpack(match)
            layers[ns.confidenceLayerAliases[layerName]] = { ability and ability.id or nil, certain }
        end

        return { abId, certain, numPossible, layers }
    end

    function r:confidenceString(compact)
        local t = {}
        local ab = confidenceLayers.ability
        local cert = confidenceLayers.certain
        for _, match in pairs(confidenceLayers.layers) do
            local layerName, ability, certain = unpack(match)
            local s = (ability and "|cFFAFD5AB" or "|cFFFA003F") ..
                      (compact and ns.confidenceLayerAliases[layerName] or layerName) ..
                      (certain and "" or "*") .. "|r"
            table.insert(t, s)
        end

        local match = "nil"
        if ab then
            match = (ab.alias or ab.name) .. "," ..
                (compact and ns.confidenceLayerAliases[confidenceLayers.matchLayer] or confidenceLayers.matchLayer) ..
                (cert and "" or "*")
        end
        return string.format("CONF: #S=%d match=[%s], layers=[%s]",
            confidenceLayers.numPossible, match, table.concat(t, ''))
    end

    -- Make a stripped-down table without key names to save space for exporting
    local function stripReqs()
        local reqEvi = {}
        for k, v in pairs(requiredEvidence) do
            reqEvi[ns.logicLayerAliases[k]] = ns:stripKeys(v)
        end
        return reqEvi
    end

    function r:reqString()
        local result = ""
        for reqName, req in pairs(requiredEvidence) do
            if result ~= "" then result = result .. " " end
            result = result .. string.format("[%s%s=%0.3f|r]",
                req.pass and "|cFFAFD5AB" or "|cFFFA003F", reqName, req.timeSince)
        end
        return result
    end

    function r:strip()
        return {
            inferenceTime,
            inferenceTrace,
            inferenceAttempt,
            eventTime,
            eventTrace,
            eventId,
            eventSource,
            eventSlot,
            batchId,
            ability and ability.id or nil,
            certain,
            ability and ability.caster or nil,
            stripLogic(),
            stripConfidence(),
            stripReqs()
        }
    end

    return r
end



local function traceLogic(event, ability, message, ...)
    ns:printDebug(ns.LOGTYPE.Inference, ns.LOGLEVEL.Verbose,
        string.format(
            "|cFF888888ability=[%s], target=[%s], caster=[%s]: " .. message .. "|r",
            ability.alias or ability.name,
            event:getSlot(),
            ns:cosmeticOnlyMapGUIDToSlot(ability.caster), ...))
end



-- Do Blizzard's aura flags match?
local function logicLayerAuraFlags(event, ability)
    local aura = event:getAura() or
        -- if it's a nonAuraEvent, choose a flag set that should never match with an aura event
        { IMPORTANT=false, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false }

    -- The RAID flag is only set for the caster of the ability. E.g., Blessing of
    -- Freedom is RAID=1 and if you are the paladin casting freedom, the aura will
    -- have RAID=1; however, if the paladin casting freedom is someone else in your
    -- group, their aura will not have RAID=1 (and, consistent with this, their freedom
    -- does not show up on your raid frames). RAIDINCOMBAT doesn't appear to work like
    -- this.
    local requireRaidFlag = ability.caster == ns:myGUID()

    if aura.IMPORTANT ~= ability.IMPORTANT or
       aura.BIG ~= ability.BIG or
       aura.EXTERNAL ~= ability.EXTERNAL or
       (false and requireRaidFlag and aura.RAID ~= ability.RAID) or
       aura.RAIDINCOMBAT ~= ability.RAIDINCOMBAT then
        traceLogic(event, ability,
            "excluded (flags): requireRaidFlag=%d, aura=(%d%d%d%d%d), ability=(%d%d%d%d%d)",
            ns:boolstr(requireRaidFlag),
            ns:boolstr(aura.IMPORTANT), ns:boolstr(aura.BIG), ns:boolstr(aura.EXTERNAL),
            ns:boolstr(aura.RAID), ns:boolstr(aura.RAIDINCOMBAT), ns:boolstr(ability.IMPORTANT),
            ns:boolstr(ability.BIG), ns:boolstr(ability.EXTERNAL), ns:boolstr(ability.RAID),
            ns:boolstr(ability.RAIDINCOMBAT))
        return { pass=false, final=true }
    end
    return { pass=true, final=true }
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
    if not ability.canReset then
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
            return { pass=false, final=true }
        end
    end
    -- XXX: TODO: this isn't implemented yet
    return { pass=true, final=false }
end



-- Was the aura's duration consistent with how the ability works?
-- General events: come across a scenario where this applies
local function logicLayerDurationMatches(event, ability)
    local aura = event:getAura()
    if aura then
        if not event:isExpiring() and ability.duration_variable == ns.DURATION_GTE then
            -- There is no invalid duration in this case. Since the event is not yet
            -- expiring, any value <= its nominal duration is accepted. But since the
            -- ability is DURATION_GTE, any value >= its nominal duration is also accepted.
            -- So any number works.
            return { pass=true, final=false }
        end

        -- IMPORTANT! uses event timing, not aura timing
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
            return { pass=false, final=true }
        end
    end
    return { pass=true, final=event:isExpiring() }
end



-- Based off of event data, not aura data.
local function evidenceWitnessed(event, ability, evidenceType, evidenceActor, permissive)
    if evidenceActor == "caster" then
        evidenceActor = ability.caster
    elseif evidenceActor == "target" then
        evidenceActor = event:getTarget()
    else
        print("PROGRAMMER ERROR: bad evidenceActor in evidenceWitnessed")
    end

    local closest, diff = event:timeSinceClosest(evidenceType, evidenceActor)
    -- Have we waited long enough to finalize our decision?
    local final = event:timeSince() > ns.CONCURRENT_EVENT_TOLERANCE

    -- Tolerate at most CONCURRENT_EVENT_TOLERANCE seconds between the event and the
    -- required concurrent evidence. But until that much time passes, it is unknown whether
    -- the required concurrent evidence will pop up. So wait that long before rejecting.
    if diff > ns.CONCURRENT_EVENT_TOLERANCE and not (permissive and not final) then
        traceLogic(event, ability,
            "excluded: actor=[%s], closest [%s]=%0.3f, applied=%0.3f (diff=%0.3f)",
            ns:cosmeticOnlyMapGUIDToSlot(evidenceActor), evidenceType, closest, event:getTime(), diff)
        return { pass=false, final=true }, diff
    end
    return { pass=true, final=final }, diff
end


-- To reduce false positives on combat drops, check how many other characters dropped
-- combat at the same time. If too many drop, then an ability probably was not used.
local function logicLayerNotGroupCombatDrop(event, ability, evidenceActor, permissive)
    -- Returns closest times for all characters if no actor provided
    allDrops = event:timeSinceClosest('combatDrop')
    local numDropsExcludingActor = 0
    for _, drop in pairs(allDrops) do
        closest, diff, actor = unpack(drop)
        if actor ~= evidenceActor and diff <= ns.CONCURRENT_EVENT_TOLERANCE then
            numDropsExcludingActor = numDropsExcludingActor + 1
        end
    end

    -- If 2 or more people drop combat at the same time, combat likely ended. No need
    -- to wait for more evidence.
    if numDropsExcludingActor > 1 then
        return { pass=false, final=true }
    end
        
    local final = event:timeSince() > ns.CONCURRENT_EVENT_TOLERANCE
    -- The final return value (timeSince) doesn't really make sense here
    return { pass=permissive or final, final=final }, event:timeSince()
end


-- If we already identified the aura, does this ability apply that aura?
-- N.B. assumes aura and aura.inferredId are both non-nil
local function logicLayerAppliesInferredAura(aura, ability)
    local pass = aura.inferredId == ability.id or
        (ability.appliesOtherAura ~= nil and aura.inferredId == ability.appliesOtherAura)

    -- The inferred ability ID might not be set at all - so it could change later.
    -- However, if it is set, the applied aura will not change (though the ability.id could)
    -- E.g.: VDH meta on first instance can become apex talent after time
    return { pass=pass, final=pass }
end



-- Currently only applies to auras, but maybe there's a generalization.
-- New events are fired when auras are updated because, in some cases, these updates
-- are new ability uses that must be tracked. However, many auras update themselves
-- without any link to a new ability use.
--
-- XXX: TODO: eventually: also exclude abilities that are known not to update. this
-- requires a new "doesNotUpdate" flag from a comprehensive pass on the ability database,
-- though.
local function logicLayerAuraUpdateAllowed(event, ability)
    if event:isUpdate() and ability.numAuraProviders == 1 then
        return { pass=false, final=true }
    end
    return { pass=true, final=true }
end



-- 1 letter aliases for compact log strings
ns.logicLayerAliases = {
    buff='B',
    cast='P',                -- p for button _p_ress
    combatDrop='C',
    notGroupCombatDrop='g',  -- g for not_G_roupCombatDrop
    cooldown='d',            -- d for cool_d_own
    duration='U',            -- U for d_U_ration
    debuff='D',
    flags='F',
    shield='S',
    appliesInferredAura='A',
    updateAllowed='u'        -- u for _u_pdate
}
    


-- Return all abilities that could have possibly generated the event. When determining
-- possibility, abilities that could become valid based on future information must also
-- be returned. Some information will never change (e.g., aura flags or the time an
-- aura was applied) but some information will (e.g., whether the correct person cast
-- an ability at the right time - this possibility cannot be excluded until waiting a
-- small amount of time from the event).
--
-- logic layers are fundamentally an AND operation: ALL rules must be followed
-- for an ability to have produced a event.
-- based on how each ability works, determine if it could have possibly produced
-- event.  which ability is the best match is determined later.
--
-- IMPORTANT: logic layers must carefully consider whether they use data about the
-- *event* or the (possible) *aura*. evidenceWitnessed, for example, is based off
-- of the *event* time, which can be different than the aura time for auras that
-- update.
local function getPossibleSolutions(event, cdTracker)
    local char = event:getCharacter() -- Character object, not GUID string
    local maxCD = -1
    local possibleSolutions = {}
    local logicLayersByAbility = {}
    -- IMPORTANT: all events in a batch share a reference to the same aura object,
    -- allowing data sharing between events.
    local aura = event:getAura()

    for _, ability in pairs(char:getPossibleAbilities()) do
        maxCD = math.max(maxCD, ability.cooldown)

        local logic = {}

        -- As with confidence and reqs, don't just test these requirements, store them
        -- so a comprehensive record can be kept for logging and analysis later.
        --
        -- XXX: when adding more layers, must add an alias mapping in logicLayerAliases
        logic['flags'] = logicLayerAuraFlags(event, ability)
        logic['cooldown'] = logicLayerAbilityOffCooldown(event, ability, cdTracker)
        logic['duration'] = logicLayerDurationMatches(event, ability)
        if ability.requireBuff then
            logic['buff'] = evidenceWitnessed(event, ability, "buff", "target", true)
        end
        if ability.requireDebuff then
            logic['debuff'] = evidenceWitnessed(event, ability, "debuff", "target", true)
        end
        if ability.requireShield then
            logic['shield'] = evidenceWitnessed(event, ability, "shield", "target", true)
        end
        if ability.requireCombatDrop then
            logic['combatDrop'] = evidenceWitnessed(event, ability, "combatDrop", "target", true)
            logic['notGroupCombatDrop'] = logicLayerNotGroupCombatDrop(event, ability, "target", true)
        end
        if ability.requireButtonPress then
            logic['cast'] = evidenceWitnessed(event, ability, "cast", "caster", true)
        end
        -- Is this event part of a batch where the aura ID has already been inferred?
        if aura and aura.inferredId then
            logic['appliesInferredAura'] = logicLayerAppliesInferredAura(aura, ability)
        end
        if aura then
            logic['updateAllowed'] = logicLayerAuraUpdateAllowed(event, ability)
        end

        local allPass = true
        for _, result in pairs(logic) do allPass = allPass and result.pass end

        -- The numeric ability ID must be recorded. Don't try to key by a string
        -- that incorporates caster ID.
        table.insert(logicLayersByAbility, { caster=ability.caster, abilityId=ability.id, logicSummary={ pass=allPass, logic=logic} })

        if allPass then
            traceLogic(event, ability, "is a possible solution")
            -- All rules have passed, this ability is a possible match
            local x = ns:shallowcopy(ability)
            _, x.castTimeDiff = event:timeSinceClosest("cast", ability.caster)
            -- don't match on duration unless there is an expiring event
            x.durationDiff = event:isExpiring() and math.abs(event:timeSince() - ability.duration) or 0
            table.insert(possibleSolutions, x)
        end
    end

    return possibleSolutions, maxCD, logicLayersByAbility
end



local function traceConfidence(layerName, message, ...)
    ns:printDebug(ns.LOGTYPE.Inference, ns.LOGLEVEL.Verbose,
        string.format("|cFF888888confidenceLayer(%s): " .. message .. "|r", layerName, ...))
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
--   1. {layerName, nil, false}
--   2. {layerName, ability, certain=true|false}
----------------------------------------------------------------------------

local function confidenceLayerOnlyOnePossible(possibleSolutions)
    if #possibleSolutions == 1 then
        traceConfidence('onlyOnePossible', 'success: #possibleSolutions=%d',
            #possibleSolutions)
        return { "oneSolution", possibleSolutions[1], true }
    else
        traceConfidence('onlyOnePossible', 'failure: #possibleSolutions=%d',
            #possibleSolutions)
        return { "oneSolution", nil, false }
    end
end



local function confidenceLayerDuration(possibleSolutions)
    best, second = getTopTwo(possibleSolutions,
        { name='dummy', durationDiff=ns.INFINITY },
        function(a, b) return a.durationDiff < b.durationDiff end)

    if second.durationDiff - best.durationDiff >= DURATION_CONFIDENT_DIFFERENCE then
        traceConfidence('duration', 'success: best=%0.3f, second=%0.3f, required diff=%0.3f',
            best.durationDiff, second.durationDiff, DURATION_CONFIDENT_DIFFERENCE)
        return { "duration", best, true }
    else
        traceConfidence('duration', 'failure: best=%0.3f, second=%0.3f, required diff=%0.3f',
            best.durationDiff, second.durationDiff, DURATION_CONFIDENT_DIFFERENCE)
        return { "duration", nil, false }
    end
end



-- The best possible solutions can have different cast times if they come
-- from different characters.
local function confidenceLayerCastTime(possibleSolutions)
    best, second = getTopTwo(possibleSolutions,
        { name='dummy', castTimeDiff=ns.INFINITY },
        function(a, b) return a.castTimeDiff < b.castTimeDiff end)

    if second.castTimeDiff - best.castTimeDiff >= CASTTIME_CONFIDENT_DIFFERENCE then
        return { "castTime", best, true }
    else
        traceConfidence('castTime', 'failure: best=%0.3f, second=%0.3f, required diff=%0.3f',
            best.castTimeDiff, second.castTimeDiff, CASTTIME_CONFIDENT_DIFFERENCE)
        return { "castTime", nil, false }
    end
end



-- Attempt uncertain inference. "Uncertain" is a poor term. It really means "we know
-- something useful now, but need more data".
-- There are several cases where multiple abilities apply the same aura:
--    1. VDH meta is also applied by the apex talent and cheat death
--    2. Prot paladin GoAK is also applied by cheat death
--    3. Warrior Avatar is also applied by a hero talent proc
-- If all abilities apply the same buff, instantly ID the buff and glow it while
-- waiting for more data to figure out what cooldown to trigger.
local function confidenceLayerAbilitiesApplySameAura(possibleSolutions)
    local theAbility
    local otherAura

    -- is possibleSolutions a list of abilities that all give the same aura? for this to
    -- be true:
    --      1. exactly one ability does not have an appliesOtherAura field
    --      2. all other abilities have the same appliesOtherAura spell ID
    for _, ability in pairs(possibleSolutions) do
        if ability.appliesOtherAura then
            if not otherAura then
                otherAura = ability.appliesOtherAura
            end

            if otherAura ~= ability.appliesOtherAura then
                traceConfidence('sameAura', 'failure: otherAbility1=%d, otherAbility2=%d',
                    otherAura, ability.appliesOtherAura)
                return { 'uncertainSameAura', nil, false }
            end
        else
            -- if theAbility isn't nil, then another ability without an
            -- appliesOtherAura field is in the list.
            if theAbility then
                traceConfidence('sameAura', 'failure: theAbility1=%s, theAbility2=%s',
                    theAbility.alias or theAbility.name, ability.alias or ability.name)
                return { 'uncertainSameAura', nil, false }
            else
                theAbility = ability
            end
        end
    end
    --      3. the ability exists, is unique and matches the shared appliesOtherAura ID
    if not theAbility then
        traceConfidence('sameAura', 'failure: theAbility1=nil')
        return { 'uncertainSameAura', nil, false }
    end
    if theAbility.id ~= otherAura then
        traceConfidence('sameAura', 'failure: theAbility1=%d, otherAura=%d',
            theAbility.id, otherAura)
        return { 'uncertainSameAura', nil, false }
    end

    return { 'uncertainSameAura', theAbility, false }
end


ns.confidenceLayerAliases = {
    oneSolution='1',
    castTime='P',
    duration='U',
    uncertainSameAura='u'
}

-- Given a list of possible abilities that could have produced event, determine:
--    1. what the best matching solution is
--    2. whether the best matching solution is a *significantly better* match than
--       all other possible solutions.
--
-- Keep in mind that it is VERY common for defensives that there's only one possible
-- matching ability, even without duration knowledge.
--
-- If confidence is attained, return the ability otherwise return nil.
-- Confidence layers are fundamentally an OR operation: if any of the layers can
-- *confidently* (this word is doing a lot of work here) distinguish between abilities,
-- then we have a match.
--
-- XXX: TODO: Would be nice to do a consistency check across confidence layers to
-- make sure the confident ones agree with each other.
local function getConfidentMatch(possibleSolutions)
    local conf= {}
    local ability, certain = nil, false

    conf.numPossible = #possibleSolutions
    conf.layers = {}
    -- order matters, so can't use a named table
    table.insert(conf.layers, confidenceLayerOnlyOnePossible(possibleSolutions))
    table.insert(conf.layers, confidenceLayerCastTime(possibleSolutions))
    table.insert(conf.layers, confidenceLayerDuration(possibleSolutions))
    table.insert(conf.layers, confidenceLayerAbilitiesApplySameAura(possibleSolutions))

    -- XXX: TODO: first match wins. maybe better strategy in the future
    for _, match in pairs(conf.layers) do
        if match[2] then
            conf.matchLayer, ability, certain = unpack(match)
            break
        end
    end

    conf.ability = ability
    conf.certain = certain
    return ability, certain, conf
end


local function makeReq(logicSummary, timeSince)
    return { pass=logicSummary.pass, final=logicSummary.final, timeSince=timeSince }
end


-- Assessment of some requirements changes with time. Buff flags never change,
-- but whether a concurrent debuff or button press occurs does change because
-- these are often not delivered in the same WoW API event. Some time must be
-- given to determine if they will or won't happen. Until that time passes, the
-- logic layer checks are actually "maybe" rather than true. But it is incorrect
-- to exclude abilities that are maybes because that could cause other abilities
-- to be chosen erroneously.
--
-- N.B. unlike in the logic layers, these evidenceWitnessed calls use permissive=false
local function abilityMeetsRequirements(ev, ab)
    local reqs = {}
    local reqsMet = true

    -- Don't just compute, store for logging output/dumping/performance analysis
    if ab.requireBuff then
        reqs['buff'] = makeReq(evidenceWitnessed(ev, ab, "buff", "target", false))
        reqsMet = reqsMet and reqs['buff'].pass
    end
    if ab.requireDebuff then
        reqs['debuff'] = makeReq(evidenceWitnessed(ev, ab, "debuff", "target", false))
        reqsMet = reqsMet and reqs['debuff'].pass
    end
    if ab.requireShield then
        reqs['shield'] = makeReq(evidenceWitnessed(ev, ab, "shield", "target", false))
        reqsMet = reqsMet and reqs['shield'].pass
    end
    if ab.requireCombatDrop then
        reqs['combatDrop'] = makeReq(evidenceWitnessed(ev, ab, "combatDrop", "target", false))
        reqsMet = reqsMet and reqs['combatDrop'].pass
        reqs['notGroupCombatDrop'] = makeReq(logicLayerNotGroupCombatDrop(ev, ab, "target", false))
        reqsMet = reqsMet and reqs['notGroupCombatDrop'].pass
    end
    if ab.requireButtonPress then
        reqs['cast'] = makeReq(evidenceWitnessed(ev, ab, "cast", "caster", false))
        reqsMet = reqsMet and reqs['cast'].pass
    end

    return reqsMet, reqs
end


-- Use various rules about who can cast what ability on whom to narrow down
-- the possible abilities that could be "event". Optional quiet mode suppresses
-- logging in this top-level function, but will not suppress verbose trace logging.
function ns:inferAbility(inferenceTrace, ev, cdTracker, quiet)
    quiet = quiet or false

    local now = GetTime()
    -- track how many times we've tried to infer this ability
    ev:incrementInference()

    -- permanent record of inference for logging/analysis
    local record = ns:InferenceRecord(now, inferenceTrace, ev)

    if not quiet then
        ns:printDebug(ns.LOGTYPE.Inference, ns.LOGLEVEL.Normal, record:toString())
    end

    -- all logic and ranking is performed in these two lines
    possibleSolutions, maxCD, logicLayersByAbility = getPossibleSolutions(ev, cdTracker)
    -- set maxCD at each inference in case one day it uses exclusion information
    ev:setMaxCD(maxCD)
    record:setLogicLayersByAbility(logicLayersByAbility)
    if not quiet then
        ns:printDebug(ns.LOGTYPE.Inference, ns.LOGLEVEL.Normal, "PASS: "..record:logicString(true))
        ns:printDebug(ns.LOGTYPE.Inference, ns.LOGLEVEL.Normal, "FAIL: "..record:logicString(false))
    end

    -- This tracks the case where 0 solutions are returned, essentially killing the event.
    -- getPossibleSolutions() returns the MOST PERMISSIVE
    -- set of possible abilities. I.e., it includes abilities that current evidence
    -- does not support IF they could be supported in the future. If there are 0 possible
    -- abilities at the permissive stage, there will never be a possible ability.
    ev:setNumPossibleSolutions(#possibleSolutions)

    -- the job of the confidence system is to compare multiple solutions and determine
    -- which is best, if that is possible.
    -- assignments can be uncertain. e.g., multiple abilities with different CDs
    -- can cause the same event. if true, it is sometimes useful to report what
    -- *event* occurred.
    abilityMatch, certain, conf = getConfidentMatch(possibleSolutions)
    record:setAbility(abilityMatch)
    record:setCertain(certain)
    record:setConfidenceLayers(conf)
    local nextLogString = record:confidenceString(true)

    -- finally: are the ability requirements actually met? possibleSolutions returns all
    -- abilities that cannot be positively excluded. for example, if an ability requires a
    -- concurrent debuff, we aren't sure that the debuff didn't happen until a short period
    -- after the event occurred. if infer() is called during that short period, the ability
    -- is still *possible*.
    local reqsMet = true   -- uncertain inferences don't need to meet reqs
    if abilityMatch and certain then
        reqsMet, reqs = abilityMeetsRequirements(ev, abilityMatch)
        record:setRequiredEvidence(reqs)
        nextLogString = nextLogString .. ", req evidence: " .. record:reqString()
    end
    if not quiet then
        ns:printDebug(ns.LOGTYPE.Inference, ns.LOGLEVEL.Normal, nextLogString)
    end

    -- Check for disableInference here, not at function start, so that maxCD can
    -- be computed for use by the history tray.
    if abilityMatch and reqsMet and not ns:GetOption('disableInference') then
        ev:setAbility(abilityMatch)
        ev:setCertain(certain)
    end

    -- XXX: TODO: add some option to disable (default:true)
    table.insert(inferenceRecordList, record)

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

            -- make the expected aura
            -- XXX: TODO: must be kept up-to-date with makeAura(). can't use makeAura
            -- directly because it expects an actual aura instance ID to query flags from.
            local aura = {
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
                RAIDINCOMBAT=ability.RAIDINCOMBAT,
            }
            aura.flags = ns:flagString(aura)
            -- and link it to the event
            event:setAura(aura)

            event:prepareForInference(idealEventTrackers)
            local _, certain =
                ns:inferAbility("SIMULATE("..ability.name..")", event, blankCDs,
                    not ns:GetOption('debugLoggingTypeSimulation'))
            ability.solved = certain
            -- XXX: TODO: inferAbility should return the conflicting spell/caster combos
            ability.conflicts = {}
        end
    end
end
