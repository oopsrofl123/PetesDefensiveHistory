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
    local isUpdate = false
    local trace = newTrace
    local source = newSource
    local char = ns:getTrackedCharacterByGUID(source)
    local inference = 0
    local possibleSolutions = nil
    local certain = false
    local ability = nil
    local time = GetTime()
    local closestEvidence = {}
    local expiration = nil
    local maxCD = ns.INFINITY
    local abilityOffCooldown

    -- Optional fields
    local aura = nil
    local numUpdates = 0
    local debuffInSamePayload = false

    function e:incrementInference() inference = inference + 1 end

    -- Trivial getters
    function e:getExpiration() return expiration end

    function e:isBlocked() return blocked end

    function e:isUpdate() return isUpdate end

    function e:isCertain() return certain end

    function e:getInference() return inference end

    -- numPossibleSolutions is nil before the first :infer()
    function e:hasPossibleSolutions()
        return possibleSolutions == nil or #possibleSolutions > 0
    end

    -- confusing: but this method is different from the InferenceEngine.lua function
    function e:getPossibleSolutions() return possibleSolutions end

    function e:getNumPossibleSolutions() return #possibleSolutions end

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

    function e:getDebuffInSamePayload() return debuffInSamePayload end

    function e:getAbilityOffCooldown(at) return abilityOffCooldown end

    -- Trivial setters
    function e:setDebuffInSamePayload(x) debuffInSamePayload = x end

    function e:setAbility(newAbility) ability = newAbility end

    function e:setAbilityOffCooldown(at) abilityOffCooldown = at end

    function e:setCertain(newCertain) certain = newCertain end

    function e:setBlocked() blocked = true end

    function e:addUpdate() numUpdates = numUpdates + 1 end

    function e:numUpdates() return numUpdates end

    function e:setUpdate() isUpdate = true end

    function e:setPossibleSolutions(s)
        possibleSolutions = s
    end

    function e:setAura(newAura) aura = newAura end

    function e:setMaxCD(newMaxCD) maxCD = newMaxCD end
        
    function e:isExpiring()
        return expiration and GetTime() >= expiration or false
    end

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
        prepareClosestEvents(evidenceTrackers, 'unitFlags')
        prepareClosestEvents(evidenceTrackers, 'feign')
        prepareClosestEvents(evidenceTrackers, 'maybeFreedom')
        prepareClosestEvents(evidenceTrackers, 'freedom')
        prepareClosestEvents(evidenceTrackers, 'died')
    end


    function e:timeSince()
        return GetTime() - time
    end


    -- Extremely important: do not call :timeSince() to measure aura durations. Because
    -- of throttling, event processing may happen far after major event lifecycle stages
    -- like :expire(). Use this function to measure how long an aura has existed so far
    -- or did exist before it expired.
    --
    -- :timeSince() is appropriate for measuring things like evidence finality.
    function e:getDuration()
        if expiration then
            return expiration - time
        else
            return GetTime() - time
        end
    end

    -- If source is nil, return a table of (actor, closest, diff) tuples for all tracked characters
    function e:timeSinceClosest(evidenceType, source)
        if source then
            local closest = closestEvidence[source][evidenceType] or 0
            return closest, math.abs(closest - time)
        else
            local result = {}
            for actor, evidence in pairs(closestEvidence) do
                local closest = evidence[evidenceType] or 0
                table.insert(result, { closest, math.abs(closest - time), actor })
            end
            return result
        end
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
        --maxBatchId = batchId
        for _, ev in pairs(eventList[self:getId()]) do
            if ev:getBatchId() > batchId then
                batchId = ev:getBatchId() + 1
            end
        end
        eventList[self:getId()][batchId] = self

        -- Schedule another inference attempt after waiting the short period of time
        -- that is tolerated for concurrent evidence. Add 10% (*1.1) for good measure.
        -- Removes most of the value a constant poller.
        C_Timer.After(1.1*ns.CONCURRENT_EVENT_TOLERANCE,
            function() ns:manageEvents("E:track", source) end)
    end

    function e:untrack()
        local eventList = ns.eventsForInference[source]
--print('source=', tostring(source), 'getid=', tostring(self:getId()), 'batchid=', tostring(self:getBatchId()), 'list[id]=', tostring(eventList[self:getId()]), 'list[id][batch]=', tostring(eventList[self:getId()][self:getBatchId()]))
        eventList[self:getId()][self:getBatchId()] = nil
        numEvents = 0
        for _, _ in pairs(eventList) do
            numEvents = numEvents + 1
        end
        --if #eventList[self:getId()] == 0 then
        if numEvents == 0 then
            eventList[self:getId()] = nil
        end
    end

    
    -- Main action function for events.
    function e:infer(inferenceTrace)
        if not self:isCertain() then
            self:prepareForInference()
            local prevAbility, prevCertain = self:getAbility()
            local ability, certain = ns:inferAbility(inferenceTrace, self, ns.cdTracker)

            -- Collect evidence for unbound freedom, the bonus freedom buff from a talent
            for _, ability in pairs(self:getPossibleSolutions()) do
                -- N.B. there may be multiple permissible paladin casters
                if ability.id == 1044 and ability.reqsMet then
                    local char = self:getCharacter()
                    char:trackEvidence('maybeFreedom', self:getTime())
                end
            end

            if certain then
                -- UI feedback and data
                ns:finalizeInference(self, ability)
            elseif ability and (not prevAbility or ability.id ~= prevAbility.id) and not certain then
                -- Log an uncertain inference, but only if the ability is different from the last
                ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal,
                    string.format(
                        "|cff00CDCDUNCERTAIN(event=[%s/%d], attempt=[%d]): [%s] cast [%s] at time [%0.3f]|r",
                        self:getId(), self:getBatchId(), self:getInference(),
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
            ns:queueCooldown(ability, abilityOffCooldown)
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


function ns:trackAura(trace, aura, debuffInSamePayload)
    ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal, string.format(
        '+++ trackAura(%s): auraStart=[%0.3f] ID=[%d], target=[%s], flags=[%s %d%d CN: %d NP: %d%d CC: %d%d]',
        trace, aura.startTime % 10000, aura.auraInstanceId, ns:cosmeticOnlyMapGUIDToSlot(aura.target),
        aura.flags,
        ns:boolstr(aura.HELPFUL), ns:boolstr(aura.HARMFUL), ns:boolstr(aura.CANCELABLE),
        ns:boolstr(aura.HELPNAMEPLATE), ns:boolstr(aura.NAMEPLATE),
        ns:boolstr(aura.HARMCC), ns:boolstr(aura.CC)))

    local ev = ns:Event(trace, aura.target)
    ev:setAura(aura)
    ev:setDebuffInSamePayload(debuffInSamePayload)
    ev:track() -- Have to track this after :setAura() because :setAura() determines the tracker ID

    return ev
end


local lastManageEvents = {}

ns.numThrottled = 0

-- Loop through all events for the tracked character 'guid'. Try to infer them
-- if they still aren't guessed and execute life cycle functions.
function ns:manageEvents(updateTrace, guid, now)
    -- This is where all the heavy lifting and calculations occur. Throttle how often
    -- this function can run. Don't throttle scheduled callbacks though.
    local last = lastManageEvents[guid] or 0
    now = now or GetTime()
    -- XXX: TODO: make an enum later, check for scheduled callbacks by trace name
    if now - last < ns:GetOption('throttleInference') and
       updateTrace ~= "E:track" and updateTrace ~= "E:orphan" then
        ns.numThrottled = ns.numThrottled + 1
        ns:printDebug(ns.LOGTYPE.Data, ns.LOGTYPE.Verbose, string.format(
            'Throttling manageEvents, last event was %0.3fs ago', now - last))
        return
    end

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
            -- Prevent tons of log spam and unnecessary :infer()s on unsolvable events
            if ev:hasPossibleSolutions() then
                -- a manageEvents() call only counts against the inference throttle if
                -- it actually tries to infer something.
                lastManageEvents[guid] = now
                ev:infer(updateTrace)
            end

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

            -- special handling to reduce spam: for abilities with only one possible provider,
            -- aura updates cannot mean a new ability was used. so block new events from
            -- being registered.
            -- this used to wait until an inference was made, but now checks whether none of
            -- the remaining possible abilities have >1 aura providers and blocks as soon as
            -- that occurs.
            --
            -- XXX: below should no longer be true since expiry is handled in a separate loop
            -- N.B. do not :block() if the event batch is expiring, evBatch[1] may already
            -- be nil.
            --
            -- XXX: TODO: blocks Avatar incorrectly
            if not evBatch[1]:isBlocked() then
                shouldBlock = true
                for _, ability in pairs(ev:getPossibleSolutions()) do
                    shouldBlock = shouldBlock and (ability.numAuraProviders == 1)
                end
                if shouldBlock then
                    evBatch[1]:setBlocked()
                    ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal, string.format(
                        'blocking eventId=[%s/%d]: max(numAuraProviders)=1',
                        ev:getId(), ev:getBatchId()))
                end
            end

            if not ev:isExpiring() then
                -- if numPossibleSolutions=0, then there will never be a possible solution.
                -- keep the first event in the batch so it can be sent to the history tray, on
                -- :expire(), but silently drop others.
                -- Do not immediately expire it; other updates would then go to history tray.
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

        -- Separate the expire loop so that events don't go missing during batch processing
        for _, ev in pairs(evBatch) do
            if ev:isExpiring() then
                ev:expire()
            end

            -- Catch orphaned aura events: expirations aren't set on auras when created -
            -- instead they expire on UNIT_AURA(remove). In some rare cases, that event can
            -- be lost (for example, if the aura expires during a loading screen), creating
            -- an orphan event that will never expire. Catch these cases by ensuring that
            -- the aura with this event's auraInstanceId is still present.
            --
            -- THIS MUST BE DONE LAST! C_UnitAuras.GetAuraDataByAuraInstanceID sometimes
            -- returns false when multiple events happen in the same frame. For example, if an
            -- AMS expires with a shield, there will be an ABSORB event and a UNIT_AURA event
            -- in the same frame to remove the shield and the aura. If the shield fires first,
            -- it can expire the event here as an orphan.
            local aura = ev:getAura()
            if aura and not ev:isExpiring() then
                if not C_UnitAuras.GetAuraDataByAuraInstanceID(ev:getSlot(), aura.auraInstanceId) then
                    ns:playback(now, 'EXPIRE_ORPHANED_AURA',
                        updateTrace, ev:getSlot(), ev:getId(), ev:getBatchId())
                    ns:printDebug(ns.LOGTYPE.Data, ns.LOGLEVEL.Normal, string.format(
                        'EXPIRING (maybe) ORPHANED AURA: trace=[%s], slot=[%s] event=[%s/%d]',
                        updateTrace, ev:getSlot(), ev:getId(), ev:getBatchId()))
                    ev:setExpiration(now)
                    C_Timer.After(1.1*ns.CONCURRENT_EVENT_TOLERANCE,
                        function() ns:manageEvents("E:orphan", ev:getSource()) end)
                end
            end
        end
    end
end
