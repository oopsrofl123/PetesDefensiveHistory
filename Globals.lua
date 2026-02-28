-- get addon namespace
local _, ns = ...

-- Variables that need to be accessed across lua files
ns.INFINITY = 10*24*3600  -- A much longer time than any reasonble value (10 days)

-- For each unique (caster, ability), this dict tracks the last time that
-- ability was identified
ns.cdTracker = {}
