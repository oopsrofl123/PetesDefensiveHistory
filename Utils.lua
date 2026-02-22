-- get the addon namespace
local addonName, ns = ...

ns.printer = LibPrettyPrint:Printer({
    prefix = addonName,
    formatter = { multiline_tables = true }
})


-- ring buffer for a fixed size FIFO queue
function ns:fixedFIFO(size)
    local q = {} -- the object returned to the user
    local head = size
    local tail = 1
    local n = 0 -- number of items in queue
    local t = {} -- the internal array

    function q:push(v)
        -- size limit reached, get rid of oldest item
        if n >= size then
            self:pop() 
        end
        head = head % size + 1
        t[head] = v
        n = n + 1
    end

    function q:pop()
        if n == 0 then
            return nil
        end
        local v = t[tail]
        t[tail] = nil -- apparently allows garbage collection
        tail = tail % size + 1
        n = n - 1
        return v
    end

    function q:items()
        return t
    end

    function q:print()
        ns.printer(t)
    end

    -- return the newest item
    function q:head()
        return t[head]
    end

    -- return the oldest item
    function q:tail()
        return t[tail]
    end

    return q
end



function ns:tablecontains(t, value)
    for k, v in pairs(t) do
        if v == value then
            return true
        end
    end
    return false
end



-- Make a shallow copy of table t and return it
function ns:shallowcopy(t)
    local newt = {}
    for k, v in pairs(t) do
        newt[k] = v
    end
    return newt
end



function ns:specIdToString(specId)
    if specId then
        id, specName, _, _, _, _, className = GetSpecializationInfoByID(specId)
        return specName .. " " .. className
    else
        return tostring(nil)
    end
end



-- Updates the global variable allSlots to ensure that slot can be mapped
-- to the correct i such that slot = CompactPartyFrameMember..i
function ns:updateSlotToFrameMapping(slot)
	for i=1,5 do
		if slot == _G["CompactPartyFrameMember"..i].unit then
			if i ~= ns.allSlots[slot] then
				ns:printDebug('updating slot mapping: ' .. slot .. ' -> ' .. i)
				ns.allSlots[slot] = i
                ns.historyRows[slot].cpfMapping = i
                ns.historyRows[slot].cpfMappingText:SetText(ns.historyRows[slot].cpfMapping)
				return
			end
		end
	end
end



function ns:slotToIndex(slot)
    return ns.allSlots[slot]
end



-- Map a character name to a slot name. E.g., "Pete" -> "player"
function ns:nameToSlot(n)
    if UnitName("player") == n then
        return "player"
    end
    for i=1,4 do
        if UnitName("party" .. i) == n then
            return "party" .. i
        end
    end
end



-- Blizzard party frames are named CompactPartyFrameMember{1,2,3,4,5}, not the
-- player, party1, party2, ... naming of UnitName(). Map the latter to the former.
function ns:slotToPartyFrameName(slot)
    return "CompactPartyFrameMember" .. ns:slotToIndex(slot)
end



-- Further convenience: return the actual frame
function ns:slotToPartyFrame(slot)
    return _G[ns:slotToPartyFrameName(slot)]
end



function ns:showDebugVisual(object)
    if PetesDefensiveHistoryOptionsDb.debugVisuals then
        object:Show()
    else
        object:Hide()
    end	
end



function ns:printDebug(string)
    --if ns.DEBUG_MESSAGES then
    if PetesDefensiveHistoryOptionsDb.debugLogging then
        --print('|cff00ff00' .. addonName .. ':|r ' .. string)
        print('|cff00ff00PDH:|r ' .. string)
    end
end



-- Show y if x is shown
function ns:showIfShown(x, y)
    if x:IsShown() then y:Show() else y:Hide() end
end



function ns:maskSecret(value)
    if issecretvalue(value) then
        return nil
    else
        return value
    end
end
