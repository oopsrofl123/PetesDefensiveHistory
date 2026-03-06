local addon, ns = ...


local lastNonBuffEventId = 1

-- A list of all active auras that we want to infer
ns.eventsForInference = {}

-- Return nil if either the guid or auraInstanceId is untracked
function ns:getAuraEventByGUID(auraInstanceId, guid)
    return (ns.eventsForInference[guid] or {})["aura"..auraInstanceId]
end


-- "trace" is just a string describing what generated this event
-- "source" is the unitTarget of the event that generated this event
function ns:Event(newTrace, newSource)
    local e = {}
    local id = lastNonBuffEventId
    lastNonBuffEventId = lastNonBuffEventId + 1

    local trace = newTrace
    local source = newSource
    local char = ns:getTrackedCharacterByGUID(source)
    local inference = 0
    local certain = false
    local ability = nil
    local time = GetTime()
    local closestEvidence = {}
    local expiration = nil
    local maxCD = ns.INFINITY

    -- Optional fields
    local aura

    function e:incrementInference()
        inference = inference + 1
    end

    -- Trivial getters
    function e:isCertain() return certain end

    function e:getInference() return inference end

    function e:getTrace() return trace end

    -- The event's "source" is the target for auras. Allow both terms for ease of understanding
    function e:getSource() return source end

    function e:getSlot() return ns:cosmeticOnlyMapGUIDToSlot(source) end

    function e:getCharacter() return char end

    function e:getMaxCD() return maxCD end

    function e:getTarget() return source end

    function e:getAura() return aura end

    function e:getTime() return time end

    -- event IDs don't account for the source because event trackers are already
    -- keyed by source. maybe they shouldn't be?
    function e:getId()
        if aura then
            return "aura" .. tostring(aura.auraInstanceId)
        else
            return "nonAuraEvent" .. tostring(id)
        end
    end

    -- Return a 2-tuple:
    --     (inferred ability or nil, certain: true|false)
    --          
    -- It is legal to return an ability that is not assigned with certainty, however
    -- certain will never be true if ability is nil (no ability was assigned). This
    -- allows us to return "working guesses" when it's useful. E.g., multiple abilities
    -- can cause the metamorphosis buff and it is useful to know that the meta buff is
    -- active until we can determine with certainty which ability applied the meta buff.
    function e:getAbility() return ability, certain end

    -- Trivial setters
    function e:setAbility(newAbility) ability = newAbility end

    function e:setCertain(newCertain) certain = newCertain end

    function e:setAura(newAura) aura = newAura end

    function e:setMaxCD(newMaxCD) maxCD = newMaxCD end
        
    function e:isExpiring() return expiration and GetTime() >= expiration or false end

    function e:setExpiration(newExpiration) expiration = newExpiration end

    function e:isNonAuraEvent() return aura == nil end

    -- Don't hardwire to the global evidence tracker. Allows swapping out for
    -- other event trackers. `evidenceType` is a string corresponding to a named
    -- component of the table returned by makeEvidenceTracker().
    --
    -- Multiple inference: to support continuous calls, also check `buff`
    -- for previous closest events and, if those are closer, don't overwrite
    -- them with whatever is closest in the current event buffer.
    local function prepareClosestEvents(evidenceTrackers, evidenceType)
        for guid, tracker in pairs(evidenceTrackers) do
            if not closestEvidence[guid] then
                closestEvidence[guid] = {}
            end
            if not closestEvidence[guid][evidenceType] then
                closestEvidence[guid][evidenceType] = 0
            end

            local closest = closestEvidence[guid][evidenceType]
            local prevClosest = closest  -- just for debugging. serves no purpose
    
            for _, evtime in pairs(tracker[evidenceType]:items()) do
                if math.abs(evtime - time) < math.abs(closest - time) then
                    closest = evtime
                end
            end
            closestEvidence[guid][evidenceType] = closest
            if prevClosest ~= closest and prevClosest ~= 0 then
                ns:printDebug(string.format("updated closest evidenceType=[%s], actor=[%s], [%0.3f] -> [%0.3f]",
                    evidenceType, ns:cosmeticOnlyMapGUIDToSlot(source), prevClosest, closest))
            end
        end
    end


    function e:prepareForInference(evidenceTrackers)
        evidenceTrackers = evidenceTrackers or ns:getEvidenceTrackers()
        prepareClosestEvents(evidenceTrackers, 'buff')
        prepareClosestEvents(evidenceTrackers, 'debuff')
        prepareClosestEvents(evidenceTrackers, 'cast')
        prepareClosestEvents(evidenceTrackers, 'shield')
        prepareClosestEvents(evidenceTrackers, 'combatDrop')
    end


    function e:timeSince()
        return GetTime() - time
    end

    function e:timeSinceClosest(evidenceType, source)
        local closest = closestEvidence[source][evidenceType] or 0
        return closest, math.abs(closest - time)
    end

    -- Can't do this in constructor because the common use case of :setAura()
    -- changes getId().
    function e:track()
        ns.eventsForInference[self:getSource()][self:getId()] = self
    end

    function e:untrack()
        ns.eventsForInference[self:getSource()][self:getId()] = nil
    end

    return e
end


function ns:trackAura(trace, aura)
    ns:printDebug(string.format(
        'trackAura(%s): time=[%0.3f], ID=[%d], target=[%s], flags=(IMP=%d, BIG=%d, EXT=%d, RAID=%d, RIC=%d, HELP=%d, HARM=%d, CANCEL=%d, HELPNAMEPLATE=%d, NAMEPLATE=%d, HARMCC=%d, CC=%d)',
        trace, aura.startTime, aura.auraInstanceId, ns:cosmeticOnlyMapGUIDToSlot(aura.target),
        aura.IMPORTANT and 1 or 0,
        aura.BIG and 1 or 0, aura.EXTERNAL and 1 or 0,
        aura.RAID and 1 or 0, aura.RAIDINCOMBAT and 1 or 0,
        aura.HELPFUL and 1 or 0, aura.HARMFUL and 1 or 0,
        aura.CANCELABLE and 1 or 0,
        aura.HELPNAMEPLATE and 1 or 0, aura.NAMEPLATE and 1 or 0,
        aura.HARMCC and 1 or 0, aura.CC and 1 or 0)
    )       

    local ev = ns:Event(trace, aura.target)
    ev:setAura(aura)
    ev:track() -- Have to track this after :setAura() because :setAura() determines the tracker ID

    return ev
end


-- Loop through all events for the tracked character 'guid'. Try to infer them
-- if they still aren't guessed and execute life cycle functions.
function ns:manageEvents(updateTrace, guid)
    local now = GetTime()
    local char = ns:getTrackedCharacterByGUID(guid)

    for _, ev in pairs(ns.eventsForInference[guid]) do
        ns:inferAndAct(updateTrace, ev, now)
    end
end
