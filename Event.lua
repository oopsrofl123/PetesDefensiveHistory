local addon, ns = ...


local lastNonBuffEventId = 1

-- A list of all active auras that we want to infer
ns.eventsForInference = {}

-- Return nil if either the guid or auraInstanceId is untracked. Auras (keyed by
-- auraInstanceId) can be related to multiple events (e.g., an ability with charges
-- being used multiple times without letting the buff fall). Returns the FIRST
-- event in those cases, which is treated as a special head event.
function ns:getAuraEventByGUID(auraInstanceId, guid)
    evBatch = (ns.eventsForInference[guid] or {})["aura"..auraInstanceId]
    if evBatch then
        return evBatch[1] -- first event
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
    local batchId = 1
    lastNonBuffEventId = lastNonBuffEventId + 1

    local blocked = false
    local trace = newTrace
    local source = newSource
    local char = ns:getTrackedCharacterByGUID(source)
    local inference = 0
    local numPossibleSolutions = nil
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
    function e:isBlocked() return blocked end

    function e:isCertain() return certain end

    function e:getInference() return inference end

    function e:getNumPossibleSolutions() return numPossibleSolutions end

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

    function e:setBlocked() blocked = true end

    function e:setNumPossibleSolutions(n) numPossibleSolutions = n end

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
        local eventList = ns.eventsForInference[source]
        if not eventList[self:getId()] then
            eventList[self:getId()] = {}
        end

        -- weird, but want a short and unique ID for printing
        for _, ev in pairs(eventList[self:getId()]) do
            batchId = ev:getBatchId() + 1
        end
        eventList[self:getId()][batchId] = self

        -- Schedule another inference attempt after waiting the short period of time
        -- that is tolerated for concurrent evidence. Add 10% (*1.1) for good measure.
        -- Removes most of the value a constant poller.
        C_Timer.After(1.1*ns.CONCURRENT_EVENT_TOLERANCE,
            function() ns:manageEvents("Event:track()", source) end)
    end

    function e:untrack()
        local eventList = ns.eventsForInference[source]
        eventList[self:getId()][self:getBatchId()] = nil
        if #eventList[self:getId()] == 0 then
            eventList[self:getId()] = nil
        end
    end

    
    -- Main action function for events.
    function e:infer(inferenceTrace, now)
        if not self:isCertain() then
            self:prepareForInference()
            local prevAbility, prevCertain = self:getAbility()
            local ability, certain = ns:inferAbility(inferenceTrace, self, ns.cdTracker)
            if certain then
                -- UI feedback and data
                ns:finalizeInference(self, ability)
            elseif ability and (not prevAbility or ability.id ~= prevAbility.id) and not certain then
                -- Log an uncertain inference, but only if the ability is different from the last
                ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal,
                    string.format(
                        "|cff00CDCDUNCERTAIN(time=[%0.3f], event=[%s/%d], attempt=[%d]): [%s] cast [%s] at time [%0.3f]|r",
                        now, self:getId(), self:getBatchId(), self:getInference(),
                        ns:cosmeticOnlyMapGUIDToSlot(ability.caster),
                        ability.alias or ability.name, self:getTime()))
            end

            -- UI feedback
            if ability and not self:isExpiring() then
                ns:startGlow(self:getAuraAbility())
            end
        end
    end
    

    -- What to do when the event expires (or is replaced)? If there was a certain inference,
    -- track in the static cooldown row, otherwise dump it in the history tray.
    -- Since dynamic CDR ability timers are rarely accurate, allow users to
    -- send those to the history tray instead. This doesn't prevent them from
    -- being glowed while active.
    function e:expire()
        -- Visual feedback
        local ability, certain = self:getAbility()
        if ability then
            ns:stopGlow(self:getAuraAbility())
        end

        -- More visual feedback
        local ability, certain = self:getAbility()
        if ability and certain and not (ability.cdr and ns:GetOption('disableCDRTrackers')) then
            ns:queueCooldown(ability)
        elseif not self:isNonAuraEvent() then
            -- Can't add non-aura events for two reasons: (1) they don't have a texture to show,
            -- (2) many aren't interesting. E.g., every time anyone leaves combat or dismounts
            -- is a non-aura event. Some of those are vanishes and shadowmelds but most are
            -- nothing.
            ns:addEventToHistoryTray(self)
        end
    
        -- Data handling
        self:untrack()
    end

    return e
end


function ns:trackAura(trace, aura)
    ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal, string.format(
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
        local index = 1
        for _, ev in pairs(evBatch) do
            ev:infer(updateTrace, now)

            -- Propagate batch information through the shared aura.
            -- XXX: TODO: need to share via a non-aura data structure that all events share
            -- reference to. using the aura is convenient now but prevents batch inference
            -- on non-aura events
            local ability = ev:getAbility()
            local aura = ev:getAura()
            if ability and aura and not aura.inferredId then
                -- It doesn't matter which event triggers this or if it's triggered many times
                -- because events in the same batch come from the same aura.
                aura.inferredId = ability.appliesOtherBuff or ability.id
                ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal,
                    string.format("event=[%s/%d], index=%d, setting inferredId=%d",
                        ev:getId(), ev:getBatchId(), index, ability.id))
            end

            -- special handling to reduce spam: for some abilities we know there will be many
            -- updates that do not indicate a new cooldown was used. e.g.: sentinel updates
            -- itself every 1s as it loses stacks, pillar of frost updates every time its
            -- duration is extended.
            --
            -- XXX: TODO: blocks Avatar incorrectly. but while developing an Avatar solution,
            -- it's much better to block() because the inference log spam is so bad debugging
            -- becomes almost impossible.
            if ability and ability.numAuraProviders == 1 and not evBatch[1]:isBlocked() then
                evBatch[1]:setBlocked()
                ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal, string.format(
                    'blocking eventId=[%s/%d]: numProviders=1',
                    ev:getId(), ev:getBatchId()))
            end

            if ev:isExpiring() then
                ev:expire()
            else
                -- numPossibleSolutions is the most permissive set of possible solutions - it includes
                -- abilities that are not yet satisfied by the observed evidence but still *could be*
                -- in future inferences. if there are 0 possibilities, then there will never be a
                -- possible solution.
                -- keep around the first event in the batch so it can be sent to the history tray, but
                -- prune others.
                if index > 1 and ev:getNumPossibleSolutions() == 0 then
                    ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Verbose, string.format(
                        'removing eventId=[%s/%d]: index=%d has 0 possible solutions',
                        ev:getId(), ev:getBatchId(), index))
                    -- :untrack() quietly removes the event with no UI feedback
                    ev:untrack()
                end
            end
            index = index + 1
        end
    end
end
