-- Variables that need to be accessed across lua files

INFINITY = 10*24*3600  -- A much longer time than any reasonble value (10 days)
MAX_HISTORY = 4
ICON_SIZE = 36
ICON_SPACING = 2
DEFAULT_ICON = 134400 -- question mark
DEBUG_VISUALS = false
DEBUG_MESSAGES = true

-- All recognized slots for history rows and defensives. Integer mappings
-- correspond to CompactPartyFrameMember..i, which are the names of
-- Blizzard's frames. This mapping MUST BE KEPT CORRECT because the
-- CenterDefensiveBuff icons are identified by CompactPartyFrameMember..i.
allSlots = { player=1, party1=2, party2=3, party3=4, party4=5 }


historyRows = {}         -- One row per party member. Each row is a frame. Frames cannot be deleted.
activeDefensives = {}    -- One list of currently active aura instance IDs per party member
                         -- This IS NOT the history!
groupSolutionUIFrame = nil
groupSolutionUI = {}

for slot, _ in pairs(allSlots) do
    activeDefensives[slot] = {}
    historyRows[slot] = {}
	groupSolutionUI = {}
end


-- Some callbacks (like to LibSpecialization) might occur before the
-- expected data structures are set up.
pdhInitialized = false
