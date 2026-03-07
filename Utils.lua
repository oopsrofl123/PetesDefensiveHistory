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



function ns:printDebug(string)
    if ns:GetOption('debugLogging') then
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


-- Lua-ese for true -> "1", false -> "0"
function ns:boolstr(bool)
    return tostring(bool and 1 or 0)
end
