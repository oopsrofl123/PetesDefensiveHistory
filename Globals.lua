-- get addon namespace
local _, ns = ...

-- Variables that need to be accessed across lua files
ns.INFINITY = 10*24*3600  -- A much longer time than any reasonble value (10 days)
ns.MAX_HISTORY = 4
ns.MAX_CAST_HISTORY = 8  -- must be cycled through on every unit on every cast succeeded. keep low.
ns.SPACING_FROM_FRAMES = 2
ns.DEFAULT_ICON = 134400 -- question mark

-- All recognized slots for history rows and defensives. Integer mappings
-- correspond to CompactPartyFrameMember..i, which are the names of
-- Blizzard's frames. This mapping MUST BE KEPT UP-TO-DATE.
ns.allSlots = { player=1, party1=2, party2=3, party3=4, party4=5 }

ns.trackerUI = {}
ns.activeDefensives = {}    -- One list of currently active aura instance IDs per party member
                         -- This IS NOT the history!
ns.castHistory = {}

ns.groupSolutionUI = nil

-- For each unique (caster, ability), this dict tracks the last time that
-- ability was identified
ns.cdTracker = {}
