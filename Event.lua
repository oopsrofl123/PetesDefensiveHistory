local addon, ns = ...


local lastNonBuffEventId = 1

-- A list of all active auras that we want to infer
ns.eventsForInference = {}

-- Return nil if either the guid or auraInstanceId is untracked. Auras (keyed by
-- auraInstanceId) can be related to multiple events (e.g., an ability with charges
-- being used multiple times without letting the buff fall). Returns the MOST RECENT
-- event in those cases.
function ns:getAuraEventByGUID(auraInstanceId, guid)
    evBatch = (ns.eventsForInference[guid] or {})["aura"..auraInstanceId]
    if evBatch then
        return evBatch[#evBatch] -- last event
    end
    return nil
end


-- Handle event batches
function ns:expireAuraEventByGUID(auraInstanceId, guid, when)
    evBatch = (ns.eventsForInference[guid] or {})["aura"..auraInstanceId]
    if evBatch then
        if #evBatch>1 then
            ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal,
                "expiring batch size="..#evBatch.." for id=aura"..auraInstanceId)
        end
        for _, event in pairs(evBatch) do
            event:setExpiration(when)
        end
    end
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
    local aura = nil

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

    function e:getBatchId() return batchId end

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

    -- Some abilities apply auras from different abilities. E.g., Avatar of the Storm is
    -- a proc that applies the Avatar buff. Those abilities often glow the icon of the
    -- buff, not the ability that caused it.
    function e:getAuraAbility()
        if ability and ability.appliesOtherAura then
            local char = ns:getTrackedCharacterByGUID(ability.caster)
            for _, otherAbility in pairs(char:getAbilities()) do
                if otherAbility.id == ability.appliesOtherAura then
                    return otherAbility
                end
            end
        end
        return ability
    end

    -- Trivial setters
    function e:setAbility(newAbility) ability = newAbility end

    function e:setCertain(newCertain) certain = newCertain end

    function e:setAura(newAura) aura = newAura end

    function e:setMaxCD(newMaxCD) maxCD = newMaxCD end
        
    function e:isExpiring() return expiration and GetTime() >= expiration or false end

    function e:setExpiration(when) expiration = when end

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
                ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal,
                    string.format("updated closest evidenceType=[%s], actor=[%s], [%0.3f]->[%0.3f]",
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

    -- Can't do this in constructor because the common use case of :setAura() changes getId().
    -- Some events are related and are thus batched under the same ID. A good example is a
    -- buff from an ability with charges. The first charge use creates the buff (and a matching
    -- event) and if the ability is used again while the first buff still exists, the buff is
    -- updated (not added) and a second matching event is created for the update. These two
    -- events originate from the same auraInstanceId and will thus be tracked together as a
    -- batch.
    --
    -- Batches assist in complicated inference that requires data sharing across events. E.g.,
    -- VDH meta with the apex talent and cheat death. All 3 can occur during the same buff
    -- lifecycle, making it difficult to determine the timing of each ability use (and thus
    -- the cooldown).
    function e:track()
        if not ns.eventsForInference[self:getSource()][self:getId()] then
            ns.eventsForInference[self:getSource()][self:getId()] = {}
        end
        table.insert(ns.eventsForInference[self:getSource()][self:getId()], self)
        batchId = #(ns.eventsForInference[self:getSource()][self:getId()])
    end

    function e:untrack()
        ns.eventsForInference[self:getSource()][self:getId()] = nil
    end

    return e
end


function ns:trackAura(trace, aura)
    ns:printDebug(string.format(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal,
        'trackAura(%s): time=[%0.3f], ID=[%d], target=[%s], flags=[%s %d%d CANCEL: %d NAMEPLATE: %d%d CC: %d%d]',
        trace, aura.startTime, aura.auraInstanceId, ns:cosmeticOnlyMapGUIDToSlot(aura.target),
        aura.flags,
        ns:boolstr(aura.HELPFUL), ns:boolstr(aura.HARMFUL), ns:boolstr(aura.CANCELABLE),
        ns:boolstr(aura.HELPNAMEPLATE), ns:boolstr(aura.NAMEPLATE),
        ns:boolstr(aura.HARMCC), ns:boolstr(aura.CC)))

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

    -- Tracking structure: each character has a list of events keyed by either
    -- an associated aura (via auraInstanceId) or an internally assigned numeric ID.
    -- An aura instance ID can map to multiple events that sometimes have data that
    -- can be shared between events to aid inference. E.g.: VDH metamorphosis will
    -- generate one auraInstanceId for: regular meta button press, apex talent meta
    -- button press, cheat death. Each will generate an event. By processing 3 events
    -- together it is possible to figure out which ability generated which event.
    for evId, evBatch in pairs(ns.eventsForInference[guid]) do
        -- XXX: TODO: some debugging while this is a new feature
        for _, ev in pairs(evBatch) do
            ns:inferAndAct(updateTrace, ev, now)
        end
    end
end
