-- get addon namespace
local _, ns = ...


-- Variables that need to be accessed across lua files

ns.INFINITY = 10*24*3600  -- A much longer time than any reasonble value (10 days)
ns.MAX_HISTORY = 4
ns.MAX_CAST_HISTORY = 60  -- buffs can last a long time. a minute worth of casts for a 1s GCD character
ns.ICON_SIZE = 32
ns.ICON_SPACING = 2
ns.DEFAULT_ICON = 134400 -- question mark
ns.DEBUG_VISUALS = false
ns.DEBUG_MESSAGES = true

-- All recognized slots for history rows and defensives. Integer mappings
-- correspond to CompactPartyFrameMember..i, which are the names of
-- Blizzard's frames. This mapping MUST BE KEPT CORRECT because the
-- CenterDefensiveBuff icons are identified by CompactPartyFrameMember..i.
ns.allSlots = { player=1, party1=2, party2=3, party3=4, party4=5 }


ns.historyRows = {}         -- One row per party member. Each row is a frame. Frames cannot be deleted.
ns.staticRows = {}
ns.activeDefensives = {}    -- One list of currently active aura instance IDs per party member
                         -- This IS NOT the history!
ns.castHistory = {}

ns.groupSolutionUIFrame = nil
ns.groupSolutionUI = {}

for slot, _ in pairs(ns.allSlots) do
    ns.activeDefensives[slot] = {}
    ns.staticRows[slot] = {}
    ns.historyRows[slot] = {}
	ns.groupSolutionUI[slot] = {}
    ns.castHistory[slot] = {}
end


-- Some callbacks (like to LibSpecialization) might occur before the
-- expected data structures are set up.
ns.pdhInitialized = false
