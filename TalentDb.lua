local _, ns = ...

-- These keys must match the table field names in the abilities database
local cdr = "cdr"
local charges = "charges"
local cooldown = "cooldown"
local duration = "duration"
local duration_variable = "duration_variable"
local hasAbility = "hasAbility"
local requireBuff = "requireBuff"
local requireShield = "requireShield"
local naturallyUpdates = "naturallyUpdates"
local reset = "canReset"
local targets = "targets"


-- Why have separate class and spec trees? Some talents with equal IDs do different
-- things for different specs. Otherwise it would be sufficient to simply have the
-- talent. That means that the choice of putting a talent in either the class or
-- spec tree only matters *IF* it does something different per spec. For example,
-- all prot war shield wall talents could be put in WARRIOR rather than prot and
-- would work just as well since no other warrior spec has shield wall.
--
-- The Class and Spec tables are *NOT* exactly the same thing as the class and
-- spec talent trees. Some talents that live in the class tree are represented
-- in the spec tree because they do different things for different specs. E.g.,
-- the paladin class talent that reduces blessing of sacrifice's cooldown gives
-- -60s to ret and prot but only -15s to holy. For this reason, that class talent
-- is instead in the spec trees.

-- Per-class table structure:
--      spellId -> { talentrank1 { ... }, ..., talentrankN { ... } }
--      Key: spell ID. Talents also have an ID, but they always act through spells.
--      Value: list of length R, where R is the number of ranks of the talent
--
-- Each talent rank is an unkeyed list of modifiers, all of which are applied if the
-- talent is known. Each modifier is a simple tuple of
--     (spell affected, attribute affected, amount[, mult])
-- if mult is missing or false, then the amount is additive, otherwise it is
-- multiplicative with scaling factor 1+mult/100
--

-- Some tracked abilities are given to classes but not as talents (e.g., Shadow Dance).
-- To add these, attach them as hasAbility modifiers to a non-optional root node in
-- the class or spec tree. Spec tree could be cleaner since the non-optional root
-- nodes in the class tree also change per spec.
ns.ClassTalentModifiers = {
    -- Death knight class tree -----------------------------------------------------------------
    ["DEATHKNIGHT"] = {
        [49998] = {  -- death strike required for blood and unholy
              { { id=48707, modifies=hasAbility, amount=true } },      -- gives AMS
        },
        [48792] = {
            { { id=48792, modifies=hasAbility, amount=true } }
        },
        [205727] = {
            { { id=48707, modifies=cooldown, amount=-20 },
              { id=48707, modifies=duration, amount=40, mult=true } }
        },
        [457574] = {  -- increases AMS cooldown in exchange for dispelling harmful events after the fact
            { { id=48707, modifies=cooldown, amount=20 } },
        }
        -- only triggers on killing an enemy that yields exp/honor. not relevant.
        --[434136] = {  -- hero talent
            --{ { id=48792, modifies=cdr, amount=true } }
        --},
    },


    -- Demon hunter class tree -----------------------------------------------------------------
    ["DEMONHUNTER"] = {
        [1266307] = {
            { { id=198589, modifies=charges, amount=1 } },
        },
    },


    -- Druid class tree ------------------------------------------------------------------------
    ["DRUID"] = {
        [327993] = {
            { { id=22812, modifies=duration, amount=4 } },
        },
        [385786] = {  -- adds a shield buff to barkskin. rank 2's shield is bigger but
                      -- that's irrelevant.
            { { id=22812, modifies=requireShield, amount=true } },   -- rank 1
            { { id=22812, modifies=requireShield, amount=true } },   -- rank 2
        }
    },


    -- Evoker class tree ----------------------------------------------------------------------
    ["EVOKER"] = {
        [363916] = {
            { { id=363916, modifies=hasAbility, amount=true } },
        },
        [375406] = {
            { { id=363916, modifies=charges, amount=1 } },
        },
    },


    -- Hunter class tree ----------------------------------------------------------------------
    ["HUNTER"] = {
        [264735] = {   -- all specs have this, can use to give any ability
            { { id=264735, modifies=hasAbility, amount=true },      -- survival of the fittest
              { id=186265, modifies=hasAbility, amount=true },      -- aspect of the turtle
              { id=5384, modifies=hasAbility, amount=true } },      -- feign death
        },
        [459450] = {
            { { id=264735, modifies=charges, amount=1 } }
        },
        [388039] = {
            { { id=264735, modifies=duration, amount=2 } }
        },
        [1258485] = {  -- turtle cooldown reduction
            { { id=186265, modifies=cooldown, amount=-30 } },
        },
        [266921] = {  -- turtle cooldown reduction
            { { id=186265, modifies=cooldown, amount=-15 } },   -- rank 1
            { { id=186265, modifies=cooldown, amount=-30 } },   -- rank 2
        },
    },


    -- Mage class tree -------------------------------------------------------------------------
    ["MAGE"] = {
        [45438] = {   -- ice block
            { { id=45438, modifies=hasAbility, amount=true } },
        },
        [382424] = {
            { { id=45438, modifies=cooldown, amount=-30 },      -- rank 1
              { id=414659, modifies=cooldown, amount=-30 } },   -- rank 1
            { { id=45438, modifies=cooldown, amount=-60 },      -- rank 2
              { id=414659, modifies=cooldown, amount=-60 } },   -- rank 2
        },
        [1265517] = {
            { { id=45438, modifies=cooldown, amount=-30 },
              { id=414659, modifies=cooldown, amount=-30 } },
        },
        [342245] = {   -- alter time
            { { id=342245, modifies=hasAbility, amount=true } },
        },
        [55342] = {   -- mirror image
            { { id=55342, modifies=hasAbility, amount=true } },
        },
        [1244025] = {   -- mirror image
            { { id=55342, modifies=cooldown, amount=-30 } },    -- rank 1
            { { id=55342, modifies=cooldown, amount=-60 } },    -- rank 2
        },
        [414659] = {   -- ice cold
            { { id=414659, modifies=hasAbility, amount=true },
              { id=45438, modifies=hasAbility, amount=false } },
        },
        [1255166] = {
            { { id=342245, modifies=cooldown, amount=-10 } },
        },
        [110959] = {   -- greater invis
            { { id=110959, modifies=hasAbility, amount=true } },
        },
        [382293] = {   -- greater invis speed boost
            { { id=110959, modifies=requireBuff, amount=true } },
        },
        [210476] = {   -- greater invis CD
            { { id=110959, modifies=cooldown, amount=-60 } },
        },
    },


    -- Monk class tree -------------------------------------------------------------------------
    ["MONK"] = {
        [443294] = {  -- hero talent adds CDR
            { { id=116849, modifies=cdr, amount=true } },
        },
    },


    -- Paladin class tree ----------------------------------------------------------------------
    ["PALADIN"] = {
        [385633] = {  -- all specs are given the auras talent
            -- give all paladins bubble
            { { id=642, modifies=hasAbility, amount=true } },
        },
        -- important talent: causes all flavors of wings to add the hammer of
        -- wrath buff concurrently, perhaps helping to distinguish wings from
        -- other (10000)-flagged auras.
        [1241288] = {
            { { id=255937, modifies=requireBuff, amount=true },
              { id=216331, modifies=requireBuff, amount=true },
              { id=31884, modifies=requireBuff, amount=true },
              { id=389539, modifies=requireBuff, amount=true } } 
        },
        [1044] = {
            { { id=1044, modifies=hasAbility, amount=true } }
        },
        [1022] = {
            { { id=1022, modifies=hasAbility, amount=true } }
        },
        [6940] = {
            { { id=6940, modifies=hasAbility, amount=true } }
        },
        [384909] = {
            { { id=1022, modifies=cooldown, amount=-60 },
              { id=204018, modifies=cooldown, amount=-60 } }
        },
        [114154] = {
            { { id=642, modifies=cooldown, amount=-30, mult=true },      -- bubble
              { id=498, modifies=cooldown, amount=-30, mult=true },      -- divine protection
              { id=31850, modifies=cooldown, amount=-30, mult=true },    -- ardent defender
              { id=403876, modifies=cooldown, amount=-30, mult=true } }
              -- { id=135928, modifies=cooldown, amount=-30, mult=true } }  -- what is this?
        },
        [305394] = {
            -- unbound freedom. this talent causes an additional freedom buff for every
            -- freedom cast. it is critical to account for this because the freedom buff
            -- is flagged 10000, meaning it matches many other abilities.
            --
            -- account for it by re-assigning the real freedom to only be permissible on
            -- the caster (in reality there's no distinction between the 2 freedom buffs).
            -- this sets up the unbound freedom cooldown tracker as a sponge for unbound
            -- freedom buffs so they aren't mis-IDed as something else.
            { { id=305394, modifies=hasAbility, amount=true },
            -- assign the real freedom to target only the caster
              { id=1044, modifies=targets, amount=ns.TARGET_SELF }, },
        },
    },


    -- Priest class tree -----------------------------------------------------------------------
    ["PRIEST"] = {
        [19236] = {
            { { id=19236, modifies=hasAbility, amount=true } },
        },
        [238100] = {
            { { id=19236, modifies=cooldown, amount=-20 } },
        },
        [458718] = {
            { { id=19236, modifies=duration, amount=10 } },
        },
        [440738] = {  -- hero talent
            { { id=47788, modifies=duration, amount=2 } },
        },
    },


    -- Rogue class tree -----------------------------------------------------------------------
    ["ROGUE"] = {
        [31224] = {
            { { id=31224, modifies=hasAbility, amount=true } }
        },
        [5277] = {
            { { id=5277, modifies=hasAbility, amount=true } }
        },
        [457022] = {
            { { id=31224, modifies=duration, amount=2 } }
        },
        [382513] = {  -- vanish charges
            { { id=1856, modifies=charges, amount=1 } },
        },
    },


    -- Shaman class tree -----------------------------------------------------------------------
    ["SHAMAN"] = {
        [108271] = {
            { { id=108271, modifies=hasAbility, amount=true } }
        },
        [381647] = {
            { { id=108271, modifies=cooldown, amount=-30 } }
        },
    },


    -- Warlock class tree ----------------------------------------------------------------------
    ["WARLOCK"] = {
        [386659] = {
            { { id=104773, modifies=cooldown, amount=-45 } }
        },
    },


    -- Warrior class tree ----------------------------------------------------------------------
    ["WARRIOR"] = {
        [391271] = {
            { { id=118038, modifies=cooldown, amount=-10, mult=true },
              { id=184364, modifies=cooldown, amount=-10, mult=true },
              { id=871, modifies=cooldown, amount=-10, mult=true } },
        },
        [152278] = {
            { { id=107574, modifies=cdr, amount=true },
              { id=871, modifies=cdr, amount=true } },
        },
    },
}


ns.SpecTalentModifiers = {
    -- Blood death knight ------------------------------------------------------------------------
    [250] = {
        [55233] = {
            { { id=55233, modifies=hasAbility, amount=true } }
        },
        [317133] = {
            { { id=55233, modifies=duration, amount=2 } },   -- rank 1
            { { id=55233, modifies=duration, amount=4 } },   -- rank 2
        },
        [205723] = {
            { { id=55233, modifies=cdr, amount=true } }
        }
    },

    -- Frost death knight ------------------------------------------------------------------------
    [251] = {
        [49143] = {  -- root talent for frost. put frost-specific stuff here
            { { id=48707, modifies=hasAbility, amount=true } },      -- gives AMS since death strike is not mandatory for frost
        },
        [51271] = {   -- pillar of frost
            { { id=51271, modifies=hasAbility, amount=true } }
        },
        [456240] = {  -- duration extend on pillar
            { { id=51271, modifies=duration_variable, amount=ns.DURATION_GTE },
              { id=51271, modifies=naturallyUpdates, amount=true } }
        },
        [1265632] = { -- apex talent: r2 and r3 extend pillar duration
            { },                                                                 -- rank 1
            { { id=51271, modifies=duration_variable, amount=ns.DURATION_GTE },  -- rank 2
              { id=51271, modifies=naturallyUpdates, amount=true } },
            { { id=51271, modifies=duration_variable, amount=ns.DURATION_GTE },  -- rank 3
              { id=51271, modifies=naturallyUpdates, amount=true } },
            { { id=51271, modifies=duration_variable, amount=ns.DURATION_GTE },  -- rank 4
              { id=51271, modifies=naturallyUpdates, amount=true } },
        },
    },
    -- Unholy death knight ------------------------------------------------------------------------
    [252] = {
    },


    -- Havoc demon hunter -------------------------------------------------------------------------
    [577] = {
        [198013] = {   -- root havoc talent
            { { id=198589, modifies=hasAbility, amount=true } },
        },
    },
    -- Vengeance demon hunter ---------------------------------------------------------------------
    [581] = {
        [212084] = {    -- root vengeance talent
            { { id=187827, modifies=hasAbility, amount=true } },
        },
        [1256353] = {   -- reduces meta cd by 10s every 3rd voidfall meteor
            { { id=187827, modifies=cdr, amount=true } },
        },
        [209258] = {
            -- cheat death: if a meta buff is already active, this updates
            -- the meta buff, so have to re-infer if the buff is updated.
            { { id=209258, modifies=hasAbility, amount=true } },
        },
        [1265818] = {
            { { id=187827, modifies=duration, amount=5 } },
        },
        [1270444] = {  -- vengeance apex talents
            -- same as cheat death: if a meta buff is already active, using
            -- the apex charge updates the meta buff, so have to re-infer.
            -- Setting duration to DURATION_GTE is a clever hack to get the
            -- inference system to automatically detangle the apex>meta or
            -- meta>apex inference problem. It is wrong, but there is no harm
            -- since no other ability could be conufsed with meta by doing this.
            { { id=1270444, modifies=hasAbility, amount=true },                   -- rank 1
              { id=187827, modifies=duration_variable, amount=ns.DURATION_GTE } },
            { { id=1270444, modifies=hasAbility, amount=true },                   -- rank 2
              { id=187827, modifies=duration_variable, amount=ns.DURATION_GTE } },
            { { id=1270444, modifies=hasAbility, amount=true },                   -- rank 3
              { id=187827, modifies=duration_variable, amount=ns.DURATION_GTE } },
            { { id=1270444, modifies=hasAbility, amount=true },                   -- rank 4
              { id=187827, modifies=duration_variable, amount=ns.DURATION_GTE } },
        },
        [204021] = {
            { { id=204021, modifies=hasAbility, amount=true } },
        },
        [207739] = {   -- burning alive. fiery brand spreads, causing updates and adding dur
            { { id=204021, modifies=duration_variable, amount=ns.DURATION_GTE },
              { id=204021, modifies=naturallyUpdates, amount=true } },
        },
        [336639] = {   -- immo aura ticking extends brand
            { { id=204021, modifies=duration_variable, amount=ns.DURATION_GTE },
              { id=204021, modifies=naturallyUpdates, amount=true } },
            { { id=204021, modifies=duration_variable, amount=ns.DURATION_GTE },
              { id=204021, modifies=naturallyUpdates, amount=true } },
        },
        [389732] = {
            { { id=204021, modifies=cooldown, amount=-12 },
              { id=204021, modifies=charges, amount=1 } },
        },
    },
    -- Devourer demon hunter ----------------------------------------------------------------------
    [1480] = {
        [473728] = {   -- root devourer talent
            { { id=198589, modifies=hasAbility, amount=true } },
        },
    },


    -- Balance druid -------------------------------------------------------------------------
    [102] = {
        [1239669] = {  -- balance druid root talent. give barkskin
            { { id=22812, modifies=hasAbility, amount=true } },
        },
        [194223] = {
            { { id=194223, modifies=hasAbility, amount=true } },
        },
        [468743] = {
            { { id=194223, modifies=cooldown, amount=-60 },
              { id=102560, modifies=cooldown, amount=-60 },
              { id=194223, modifies=charges, amount=1 },
              { id=102560, modifies=charges, amount=1 } },
        },
        [390378] = {
            { { id=194223, modifies=cooldown, amount=-60 },
              { id=102560, modifies=cooldown, amount=-60 } },
        },
        [102560] = {
            { { id=102560, modifies=hasAbility, amount=true },
              { id=194223, modifies=hasAbility, amount=false } }
        },
        [434249] = {  -- hero talent: CDR for all major abilities. maxes at 15s
            { { id=102560, modifies=cdr, amount=true },
              { id=194223, modifies=cdr, amount=true } }
        }
    },
    -- Feral druid ---------------------------------------------------------------------------
    [103] = {
        [5217] = {  -- feral druid root talent. give barkskin
            { { id=22812, modifies=hasAbility, amount=true } },
        },
        [106951] = {
            { { id=106951, modifies=hasAbility, amount=true } },
        },
        [391174] = {
            { { id=106951, modifies=cooldown, amount=-60 },
              { id=102543, modifies=cooldown, amount=-60 } },
        },
        [102543] = {
            { { id=106951, modifies=hasAbility, amount=false },
              { id=102543, modifies=hasAbility, amount=true } },
        },
        [391548] = {
            { { id=102543, modifies=cooldown, amount=-30 } },
        }
    },
    -- Guardian druid ------------------------------------------------------------------------
    [104] = {
        [6807] = {  -- guardian druid root talent. give barkskin
            { { id=22812, modifies=hasAbility, amount=true },
              { id=22812, modifies=cooldown, amount=-15 } },
        },
        [203965] = {
            { { id=22812, modifies=cooldown, amount=-12, mult=true } },
            { { id=22812, modifies=cooldown, amount=-24, mult=true } },
        },
        [1250923] = {
            { { id=22812, modifies=duration, amount=-40, mult=true } },
        },
        [393611] = {
            { { id=22812, modifies=duration, amount=2 } },
        },
        [50334] = {
            { { id=50334, modifies=hasAbility, amount=true } },
        },
        [102558] = {
            { { id=50334, modifies=hasAbility, amount=false },
              { id=102558, modifies=hasAbility, amount=true } },
        },
        [393414] = {
            { { id=102558, modifies=cdr, amount=true } },
        }
    },
    -- Resto druid ---------------------------------------------------------------------------
    [105] = {
        [33763] = {  -- resto druid root talent. give barkskin
            { { id=22812, modifies=hasAbility, amount=true } },
        },
        [102342] = {
            { { id=102342, modifies=hasAbility, amount=true } },
        },
        [382552] = {
            { { id=102342, modifies=cooldown, amount=-20 } },
        },
        [392116] = {
            { { id=102342, modifies=duration, amount=4 } },
        },
    },

    -- Devastation evoker -------------------------------------------------------------------
    [1467] = {
        [375087] = {
            { { id=375087, modifies=hasAbility, amount=true } },
        },
        [375797] = {  -- extends dur by 5s for each emp cast. reduces by 25% each time
            { { id=375087, modifies=duration_variable, amount=ns.DURATION_GTE } },
        },
    },
    -- Preservation evoker ------------------------------------------------------------------
    [1468] = {
        [357170] = {
            { { id=357170, modifies=hasAbility, amount=true } },
        },
        [376204] = {
            { { id=357170, modifies=charges, amount=1 },
              { id=357170, modifies=cooldown, amount=-10 } },
        },
        [376240] = {
            { { id=357170, modifies=duration, amount=15, mult=true } },   -- rank 1
            { { id=357170, modifies=duration, amount=30, mult=true } },   -- rank 2
        },
    },
    -- Augmentation evoker ------------------------------------------------------------------
    [1473] = {
        [395152] = {   -- augmentation root talent
            -- seems aug's obsidian scales are 0.5s longer than others. there must be a
            -- talent somewhere but i can't find it.
            { { id=363916, modifies=duration, amount=0.5 } }
        },
        -- XXX: TODO: this ability does add a buff, but it is not in the same UNIT_AURA event
        --[407243] = {
            --{ { id=363916, modifies=requireBuff, amount=true } },  -- rank 1
            --{ { id=363916, modifies=requireBuff, amount=true } },  -- rank 2
        --},
        [404977] = { -- -20s CDR for ALL spells
            { { id=363916, modifies=cdr, amount=true } }
        },
        [412723] = { -- -30s CDR for ALL spells
            { { id=363916, modifies=cdr, amount=true } }
        },
        [412713] = { -- reduces ALL spell cooldowns permanently
            { { id=363916, modifies=cooldown, amount=-10, mult=true } }
        },
    },


    -- Beast mastery hunter -----------------------------------------------------------------
    [253] = {
    },
    -- Marks hunter -------------------------------------------------------------------------
    [254] = {
        [288613] = {
            { { id=288613, modifies=hasAbility, amount=true } },
        },
        [260404] = {
            { { id=288613, modifies=cooldown, amount=-30 } },
        },
        [1253830] = {
            { { id=288613, modifies=duration, amount=2 } },
        },
    },
    -- Survival hunter ----------------------------------------------------------------------
    [255] = {
        [1250646] = {
            { { id=1250646, modifies=hasAbility, amount=true } },
        },
        [1251790] = {
            { { id=1250646, modifies=cooldown, amount=-15 } },  -- rank 1
            { { id=1250646, modifies=cooldown, amount=-30 } },  -- rank 2
        },
        [1272139] = {
            { { id=1250646, modifies=requireBuff, amount=true } },
        },
        [1264902] = {
            { { id=1250646, modifies=requireBuff, amount=true } },
        },
        [1253830] = {
            { { id=1250646, modifies=duration, amount=2 } },
        },
    },


    -- Arcane mage ----------------------------------------------------------------------------
    [62] = {
        [365350] = {
            { { id=365350, modifies=hasAbility, amount=true } },
        },
        [449412] = {   -- sunfury hero talent extends arcane surge
            { { id=365350, modifies=duration_variable, amount=ns.DURATION_GTE } },
        },
    },
    -- Fire mage ------------------------------------------------------------------------------
    [63] = {
        [190319] = {
            { { id=190319, modifies=hasAbility, amount=true } },
        },
        [1254194] = {
            { { id=190319, modifies=cooldown, amount=-60 } },
        },
        [449412] = {
            { { id=190319, modifies=duration_variable, amount=ns.DURATION_GTE } },
        },
        [383634] = { -- adds a buff (Fiery Rush) to combustion
            { { id=190319, modifies=requireBuff, amount=true } },
        },
        [1257443] = {  -- apex talent r4 extends combustion duration
            { { } },    -- rank 1
            { { } },    -- rank 2
            { { } },    -- rank 3
            { { id=190319, modifies=duration_variable, amount=ns.DURATION_GTE } },    -- rank 4
        },
        -- XXX: TODO: 431131 causes ice cold to update itself a gazillion times
        -- could use this to differentiate from alter time if talented
    },
    -- Frost mage -----------------------------------------------------------------------------
    [64] = {
        [235219] = {  -- XXX: TODO: cold snap reset. just model as CDR for now.
            { { id=45438, modifies=reset, amount=true },
              { id=414659, modifies=reset, amount=true } },
        },
        [1244110] = {
            { { id=45438, modifies=charges, amount=1 },
              { id=414659, modifies=charges, amount=1 } },
        }
    },


    -- Brewmaster monk ------------------------------------------------------------------------
    [268] = {
        [132578] = {
            { { id=132578, modifies=hasAbility, amount=true } },
        },
        [450989] = {
            { { id=132578, modifies=cooldown, amount=-25 } },
        },
    },
    -- Mistweaver monk ------------------------------------------------------------------------
    [270] = {
        [116849] = {
            { { id=116849, modifies=hasAbility, amount=true } },
        },
        [202424] = {
            { { id=116849, modifies=cooldown, amount=-45 } },
        },
        [443294] = {
            { { id=116849, modifies=cdr, amount=true } },
        },
    },
    -- Windwalker monk ------------------------------------------------------------------------
    [269] = {
    },


    -- Holy Paladin ------------------------------------------------------------------------
    [65] = {
        [20473] = { -- required root holy talent. add holy-specific mods here
            { { id=498, modifies=hasAbility, amount=true } }    -- holy gets divine protection
        },
        [384820] = {
            { { id=6940, modifies=cooldown, amount=-15 } }
        },
        [31884] = {
            { { id=31884, modifies=hasAbility, amount=true } }
        },
        -- avenging crusader adds the hammer of wrath buff.
        [216331] = {
            { { id=216331, modifies=hasAbility, amount=true } }
        },
        [1241511] = {
            { { id=31884, modifies=cooldown, amount=-15 },      -- rank 1
              { id=31884, modifies=duration, amount=-4 },
              { id=216331, modifies=cooldown, amount=-7.5 },
              { id=216331, modifies=duration, amount=-2.5 } },
            { { id=31884, modifies=cooldown, amount=-30 },      -- rank 2
              { id=31884, modifies=duration, amount=-8 },
              { id=216331, modifies=cooldown, amount=-15 },
              { id=216331, modifies=duration, amount=-5 } },
        },
        [53376] = {
            { { id=31884, modifies=duration, amount=50, mult=true },
              { id=216331, modifies=duration, amount=50, mult=true } }
        }
    },
    -- Prot Paladin ------------------------------------------------------------------------
    [66] = {
        [384820] = {
            { { id=6940, modifies=cooldown, amount=-60 } }
        },
        [31850] = {
            { { id=31850, modifies=hasAbility, amount=true } }
        },
        [204018] = {
            { { id=204018, modifies=hasAbility, amount=true } }
        },
        [392928] = {
            { { id=135928, modifies=cdr, amount=true } }
        },
        [31884] = {
            { { id=31884, modifies=hasAbility, amount=true } }
        },
        [389539] = {
            { { id=389539, modifies=hasAbility, amount=true },
              { id=389539, modifies=naturallyUpdates, amount=true } },
        },
        [86659] = {
            { { id=86659, modifies=hasAbility, amount=true } }
        },
        [378425] = {
            { { id=642, modifies=cooldown, amount=-15, mult=true },
            { id=1022, modifies=cooldown, amount=-15, mult=true },
            { id=204018, modifies=cooldown, amount=-15, mult=true },
            { id=135928, modifies=cooldown, amount=-15, mult=true } }
        },
        [53376] = {
            { { id=389539, modifies=duration, amount=25, mult=true },
            { id=31884, modifies=duration, amount=25, mult=true } }
        },
        [378279] = {
            { { id=393108, modifies=hasAbility, amount=true },
            { id=86659, modifies=cdr, amount=true } }
        },
        [1246481] = {
            { { id=86659, modifies=charges, amount=1 } }
        },
        [391142] = {
            -- wording doesn't mention sentinel, but does apply to it.
            -- rank 2 extends more than rank 1, but all that matters is the duration
            -- is longer than base.
            { { id=31884, modifies=duration_variable, amount=ns.DURATION_GTE },
              { id=389539, modifies=duration_variable, amount=ns.DURATION_GTE } },
            { { id=31884, modifies=duration_variable, amount=ns.DURATION_GTE },
              { id=389539, modifies=duration_variable, amount=ns.DURATION_GTE } },
        },
        [204074] = {
            { { id=389539, modifies=cooldown, amount=-50, mult=true },
              { id=389539, modifies=duration, amount=-40, mult=true },
              { id=31884, modifies=cooldown, amount=-50, mult=true },
              { id=31884, modifies=duration, amount=-40, mult=true } }
        },
        [432866] = {
            { { id=135928, modifies=cdr, amount=true } }
        }
    },
    -- Ret Paladin ------------------------------------------------------------------------
    [70] = {
        [184575] = { -- 1st spec talent. put ret spec stuff here
            { { id=31884, modifies=cooldown, amount=-60 },    -- ret gets -60s on wings
              { id=498, modifies=hasAbility, amount=true },   -- ret gets divine protection
              { id=498, modifies=cooldown, amount=30 } }      -- but ret DP is a 90s cd
        },
        [1261562] = {
            { { id=498, modifies=requireShield, amount=true },
              { id=498, modifies=requireBuff, amount=true } }
        },
        [384820] = {
            { { id=6940, modifies=cooldown, amount=-60 } }
        },
        [31884] = {
            { { id=31884, modifies=hasAbility, amount=true } }
        },
        --[255937] = {
            --{ { id=255937, modifies=hasAbility, amount=true } }
        --},
        [406872] = {
            { { id=31884, modifies=duration, amount=3 },      -- rank 1
              { id=255937, modifies=duration, amount=3 } },
            { { id=31884, modifies=duration, amount=4 },      -- rank 2
              { id=255937, modifies=duration, amount=4 } },
        },
        [458359] = {
            { { id=255937, modifies=hasAbility, amount=true },
              { id=31884, modifies=hasAbility, amount=false } }
        },
        [431730] = {  -- hero talent: wake of ashes gives a 10% hp shield as a separate buff
                      -- XXX: TODO: buff requirements currently don't add
            { { id=255937, modifies=requireShield, amount=true },
              { id=255937, modifies=requireBuff, amount=true } }
        },
    },


    -- Discipline priest -------------------------------------------------------------------
    [256] = {
        [33206] = {
            { { id=33206, modifies=hasAbility, amount=true } },
        },
        [373035] = {
            { { id=33206, modifies=charges, amount=1 },
              { id=33206, modifies=cdr, amount=true } },
        },
    },
    -- Holy priest -------------------------------------------------------------------------
    [257] = {
        [47788] = {
            { { id=47788, modifies=hasAbility, amount=true } },
        },
        [200209] = {
            -- weird talent: if guardian spirit doesn't trigger the cheat death,
            -- then the cooldown is reduced TO (not by) 60s. if most GS uses don't cheat,
            -- it could be more useful to model this as a 60s cooldown because it's so
            -- far off from the 180s cd.
            -- XXX: TODO: does cheat fire a UNIT_DIED?
            { { id=47788, modifies=cdr, amount=true } },
        },
        [64843] = {
            { { id=64843, modifies=hasAbility, amount=true } },
        },
        [419110] = {
            { { id=64843, modifies=cooldown, amount=-60 } },
        },
    },
    -- Shadow priest -----------------------------------------------------------------------
    [258] = {
        [335467] = {  -- shadow priest root talent, give dispersion
            { { id=47585, modifies=hasAbility, amount=true } },
        },
        [228260] = {
            { { id=228260, modifies=hasAbility, amount=true } },
        },
        [1231346] = { -- extend duration on SW:madness
            { { id=228260, modifies=duration_variable, amount=ns.DURATION_GTE } },
        },
        [454001] = {  -- hero talent that extends duration
            { { id=228260, modifies=duration_variable, amount=ns.DURATION_GTE } },
        },
        [453729] = {  -- hero talent extends dispersion by 2s
            { { id=47585, modifies=duration, amount=2 } },
        },
        [288733] = {  -- dipsersion cd -30s
            { { id=47585, modifies=cooldown, amount=-30 } },
        },
    },


    -- Assassination rogue -----------------------------------------------------------------
    [259] = {
        [2823] = {
            { { id=1856, modifies=hasAbility, amount=true } },   -- give vanish
        },
    },
    -- Outlaw rogue ------------------------------------------------------------------------
    [260] = {
        [279876] = {
            { { id=1856, modifies=hasAbility, amount=true } },   -- give vanish
        },
        [13750] = {
            { { id=13750, modifies=hasAbility, amount=true } },
        },
        [1259465] = {
            { { id=13750, modifies=duration, amount=4 } },
        },
        [1277933] = {
            -- preparation: resets the cd of adrenaline rush. for now, just model
            -- as CDR
            -- XXX: TODO: better handle abilities that reset cooldowns
            { { id=13750, modifies=cdr, amount=true } },
        }
    },
    -- Subtlety rogue ---------------------------------------------------------------------
    [261] = {
        [91023] = {   -- root sub talent
            { { id=185313, modifies=hasAbility, amount=true },   -- give shadow dance
              { id=1856, modifies=hasAbility, amount=true } },   -- give vanish
        },
        [394930] = {
            { { id=185313, modifies=charges, amount=1 } },
        },
        -- two shadow dance duration talents that are hard to deal with
        [382505] = {
            -- give +3s dur to shadow dance if rogue remains out of combat for 6s
            -- let's just model it as DURATION_GTE
            { { id=185313, modifies=duration_variable, amount=ns.DURATION_GTE } },
        },
        [185314] = {
            -- even worse: shadow dance +duration based on haste stat, presumably
            -- meaning haste procs increase duration. again, approximate with DURATION_GTE
            { { id=185313, modifies=duration_variable, amount=ns.DURATION_GTE } },
        },
        [121471] = {
            { { id=121471, modifies=hasAbility, amount=true } }
        },
        [196976] = {  -- gives master of shadows buff on dance
            { { id=185313, modifies=requireBuff, amount=true } },
        },
        [382514] = {  -- gives fade to nothing on dance
            { { id=185313, modifies=requireBuff, amount=true },
              { id=1856, modifies=requireBuff, amount=true } },
        },
        [385722] = {  -- gives silent storm on dance
            { { id=185313, modifies=requireBuff, amount=true },
              { id=1856, modifies=requireBuff, amount=true } },
        },
        [382515] = {  -- vanish gives a shield
            { { id=1856, modifies=requireShield, amount=true } },
        },
    },


    -- Elemental shaman ------------------------------------------------------------------------
    [262] = {
    },
    -- Enhancement shaman ------------------------------------------------------------------------
    [263] = {
    },
    -- Resto shaman ------------------------------------------------------------------------
    [264] = {
    },


    -- Affliction warlock ------------------------------------------------------------------------
    [265] = {
        [980] = {  -- root affliction talent
            { { id=104773, modifies=hasAbility, amount=true } }
        },
    },
    -- Demo warlock ------------------------------------------------------------------------
    [266] = {
        [105174] = {  -- root demo talent
            { { id=104773, modifies=hasAbility, amount=true } }
        },
    },
    -- Destro warlock ------------------------------------------------------------------------
    [267] = {
        [116858] = {  -- root destro talent
            { { id=104773, modifies=hasAbility, amount=true } }
        },
    },


    -- Arms warrior ------------------------------------------------------------------------
    [71] = {
        [118038] = {
            { { id=118038, modifies=hasAbility, amount=true } },
        },
        [107574] = {
            { { id=107574, modifies=hasAbility, amount=true } },
        },
    },
    -- Fury warrior ------------------------------------------------------------------------
    [72] = {
        [184364] = {
            { { id=184364, modifies=hasAbility, amount=true } },
        },
        [107574] = {
            { { id=107574, modifies=hasAbility, amount=true } },
        },
        [383468] = {
            { { id=184364, modifies=duration, amount=8 } },
        },
        [1270724] = {  -- thunder blast extends dur +2. the extension is an aura update
            { { id=107574, modifies=duration_variable, amount=ns.DURATION_GTE },
              { id=107574, modifies=naturallyUpdates, amount=true },
              { id=437134, modifies=duration_variable, amount=ns.DURATION_GTE },
              { id=437134, modifies=naturallyUpdates, amount=true } },
        },
        [437134] = {   -- Avatar of the Storm: hero talent that procs avatar for 4s
            { { id=437134, modifies=hasAbility, amount=true } },
        },
    },
    -- Prot warrior ------------------------------------------------------------------------
    [73] = {
        [107574] = {
            { { id=107574, modifies=hasAbility, amount=true } },
        },
        [1270724] = {  -- thunder blast extends dur +2. the extension is an aura update
            { { id=107574, modifies=duration_variable, amount=ns.DURATION_GTE },
              { id=107574, modifies=naturallyUpdates, amount=true },
              { id=437134, modifies=duration_variable, amount=ns.DURATION_GTE },
              { id=437134, modifies=naturallyUpdates, amount=true } },
        },
        [437134] = {   -- Avatar of the Storm: hero talent that procs avatar for 4s
            { { id=437134, modifies=hasAbility, amount=true } },
        },
        [871] = {
            { { id=871, modifies=hasAbility, amount=true } },
        },
        [1243659] = {  -- last stand adds a buff to shield wall
            { { id=871, modifies=requireBuff, amount=true } },
        },
        [397103] = {
            { { id=871, modifies=cooldown, amount=-60 },
              { id=871, modifies=charges, amount=1 } },
        },
        [384072] = {
            { { id=871, modifies=cdr, amount=true } },
        },
    },
}
