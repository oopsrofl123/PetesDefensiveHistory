printer = LibPrettyPrint:Printer({
  prefix = "DefensiveHistory",
    formatter = { multiline_tables = true }
})



function specIdToString(specId)
    if specId then
        id, specName, _, _, _, _, className = GetSpecializationInfoByID(specId)
        return specName .. " " .. className -- .. "(" .. specId .. ")"
    else
        return tostring(nil)
    end
end



-- Make a shallow copy of table t and return it
function shallowcopy(t)
    local newt = {}
    for k, v in pairs(t) do
        newt[k] = v
    end
    return newt
end



-- Updates the global variable allSlots to ensure that slot can be mapped
-- to the correct i such that slot = CompactPartyFrameMember..i
function updateSlotToFrameMapping(slot)
	for i=1,5 do
		if slot == _G["CompactPartyFrameMember"..i].unit then
			if i ~= allSlots[slot] then
				printDebug('updating slot mapping: ' .. slot .. ' -> ' .. i)
				allSlots[slot] = i
                historyRows[slot].cpfMapping = i
                historyRows[slot].cpfMappingText:SetText(historyRows[slot].cpfMapping)
				return
			end
		end
	end
end



function slotToIndex(slot)
    return allSlots[slot]
end



-- Map a character name to a slot name. E.g., "Pete" -> "player"
function nameToSlot(n)
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
function slotToPartyFrameName(slot)
    return "CompactPartyFrameMember" .. slotToIndex(slot)
end


-- Further convenience: return the actual frame
function slotToPartyFrame(slot)
    return _G[slotToPartyFrameName(slot)]
end


function showDebugVisual(object)
    if DEBUG_VISUALS then
        object:Show()
    else
        object:Hide()
    end	
end


function printDebug(string)
    if DEBUG_MESSAGES then
        print('|cff00ff00PetesDefensiveHistory:|r ' .. string)
    end
end


-- Show y if x is shown
function showIfShown(x, y)
    if x:IsShown() then y:Show() else y:Hide() end
end
