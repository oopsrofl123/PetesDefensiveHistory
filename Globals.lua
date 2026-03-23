-- get addon namespace
local _, ns = ...

-- Variables that need to be accessed across lua files
ns.INFINITY = 10*24*3600  -- A much longer time than any reasonble value (10 days)

-- For each unique (caster, ability), this dict tracks the last time that
-- ability was identified
ns.cdTracker = {}

ns.groupSolutionUI = nil

-- These are the locale-independent class names that key into several tables.
-- The display strings are different. The spec IDs are no longer used.
ns.orderedClasses = {
    "DEATHKNIGHT",   -- { 250, 251, 252 } },
    "DEMONHUNTER",   -- { 577, 581, 1480 } },
    "DRUID",         -- { 102, 103, 104, 105 } },
    "EVOKER",        -- { 1467, 1468, 1473 } },
    "HUNTER",        -- { 253, 254, 255 } },
    "MAGE",          -- { 62, 63, 64 } },
    "MONK",          -- { 268, 269, 270 } },
    "PALADIN",       -- { 65, 66, 70 } },
    "PRIEST",        -- { 256, 257, 258 } },
    "ROGUE",         -- { 259, 260, 261 } },
    "SHAMAN",        -- { 262, 263, 264 } },
    "WARLOCK",       -- { 265, 266, 267 } },
    "WARRIOR",       -- { 71, 72, 73 } }
}
