-- get the addon namespace
local addonName, ns = ...

ns.printer = LibPrettyPrint:Printer({
    prefix = addonName,
    formatter = { multiline_tables = true }
})

ns.compactPrinter = LibPrettyPrint:Printer({
    prefix = addonName,
})

ns.compactFormatter = LibPrettyPrint:Formatter({
    prefix = addonName,
}):Compact()


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



function ns:showDebugVisual(object)
    if ns:GetOption('debugVisuals') then
        object:Show()
    else
        object:Hide()
    end	
end



ns.LOGTYPE = {
    None='None',
    Talents='Talents',
    Inference='Inference',
    UI='UI',
    Data='Data',
    DataMining='DataMining',
}
ns.LOGLEVEL = {
    Error='Error',
    Normal='Normal',
    Verbose='Verbose',
}
function ns:printDebug(logtype, loglevel, string)
    if ns:GetOption('debugLogging') then
        local logTypeEnabled =
            (logtype == ns.LOGTYPE.None) or ns:GetOption('debugLoggingType'..logtype)
        local logLevelEnabled =
            (loglevel == ns.LOGLEVEL.Error) or 
            (loglevel == ns.LOGLEVEL.Normal) or 
            (loglevel == ns.LOGLEVEL.Verbose and ns:GetOption('debugLoggingLevelVerbose'))

        if logTypeEnabled and logLevelEnabled then
            local timeString = ''
            if loglevel == ns.LOGLEVEL.Normal or loglevel == ns.LOGLEVEL.Error then
                timeString = string.format("[%0.3f]", GetTime() % 10000)
            end
            print('|cff00ff00PDH'..timeString..':|r ' .. string)
        end
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


-- Lua-ese for true -> "1", false -> "0"
function ns:boolstr(bool)
    return tostring(bool and 1 or 0)
end


-- x is an event or ability
function ns:flagString(x)
    return ns:boolstr(x.IMPORTANT)..ns:boolstr(x.BIG)..ns:boolstr(x.EXTERNAL)..ns:boolstr(x.RAID)..
ns:boolstr(x.RAIDINCOMBAT)
end


function ns:addonIsActive()
    local contentType, groupSize = ns:getGroupContentInfo()
    return ns:GetOption('enable') and (
        (contentType == 'solo' and ns:GetOption('enableSolo')) or
        (contentType == 'party' and ns:GetOption('enableParty')) or
        (contentType == 'arena' and ns:GetOption('enableArena')) or
        (contentType == 'raid' and ns:GetOption('enableRaid')) or
        (contentType == 'battleground' and ns:GetOption('enableBattleground'))
    )
end


function ns:getGroupContentInfo()
    local inGroup = IsInGroup()        -- true if in party or raid
    local inRaid = IsInRaid()          -- true if in a raid
    local inInstance, instanceType = IsInInstance()
    local contentType, groupSize, slotRoot

    if inInstance and instanceType == "arena" then
        contentType = "arena"
    elseif inInstance and instanceType == "pvp" then
        contentType = "battleground"
    elseif inInstance and instanceType == "party" then
        contentType = "party"
    elseif inRaid then
        contentType = "raid"
    elseif inGroup then
        contentType = "party"
    else
        contentType = "solo"
    end

    if contentType == "raid" or contentType == "battleground" then
        groupSize = GetNumGroupMembers()
        slotRoot = "raid"
    else
        -- GetNumSubgroupMembers excludes the player
        groupSize = GetNumSubgroupMembers() + 1
        slotRoot = "party"
    end

    return contentType, groupSize, slotRoot
end


function ns:getSlotSet()
    if not ns:addonIsActive() then
        return {}
    end

    local contentType, groupSize, slotRoot = ns:getGroupContentInfo()
    local slots = {}

    -- Use the 'player' unit token only out of raid
    if slotRoot == "party" then
        groupSize = groupSize - 1
        table.insert(slots, 'player')
    end
    for i=1, groupSize do
        table.insert(slots, slotRoot..i)
    end

    return slots
end


function ns:printMemUsage(trace)
    UpdateAddOnMemoryUsage()
    ns:printDebug(ns.LOGTYPE.None, ns.LOGLEVEL.Normal,
        trace .. ': mem usage is ' .. GetAddOnMemoryUsage('PetesDefensiveHistory') .. 'k')
end
