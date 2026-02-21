local _, ns = ...

-- These keys must match the table field names in the abilities database
local cdr = "cdr"
local charges = "charges"
local cooldown = "cooldown"
local duration = "duration"
local duration_variable = "duration_variable"
local hasAbility = "hasAbility"
local requireConcurrentBuff = "requireConcurrentBuff"

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
    },


    -- Druid class tree ------------------------------------------------------------------------
    ["DRUID"] = {
        [327993] = {
            { { id=22812, modifies=duration, amount=4 } },
        },
        [385786] = {  -- adds a shield buff to barkskin. rank 2's shield is bigger but
                      -- that's irrelevant.
            { { id=22812, modifies=requireConcurrentBuff, amount=true } },   -- rank 1
            { { id=22812, modifies=requireConcurrentBuff, amount=true } },   -- rank 2
        }
    },


    -- Evoker class tree ----------------------------------------------------------------------
    ["EVOKER"] = {
    },


    -- Hunter class tree ----------------------------------------------------------------------
    ["HUNTER"] = {
        [264735] = {
            { { id=264735, modifies=hasAbility, amount=true } }
        },
        [459450] = {
            { { id=264735, modifies=charges, amount=1 } }
        },
        [388039] = {
            { { id=264735, modifies=duration, amount=2 } }
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
        }
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
            { { id=255937, modifies=requireConcurrentBuff, amount=true },
              { id=216331, modifies=requireConcurrentBuff, amount=true },
              { id=31884, modifies=requireConcurrentBuff, amount=true },
              { id=389539, modifies=requireConcurrentBuff, amount=true } } 
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
            { { id=642, modifies=cooldown, amount=-30, mult=true },
              { id=31850, modifies=cooldown, amount=-30, mult=true },
              { id=135928, modifies=cooldown, amount=-30, mult=true } }
        },
    },


    -- Priest class tree -----------------------------------------------------------------------
    ["PRIEST"] = {
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
    },
}


ns.SpecTalentModifiers = {
    -- Blood death knight ------------------------------------------------------------------------
    [250] = {
        [55233] = {
            { { id=55233, modifies=hasAbility, amount=true } }
        },
        [317133] = {
            { { id=55233, modifies=duration, amount=2 } }
        },
        [205723] = {
            { { id=55233, modifies=cdr, amount=true } }
        }
    },

    -- Frost death knight ------------------------------------------------------------------------
    [251] = {
        [49143] = {  -- root talent for frost. put frost-specific stuff here
            { { id=48707, modifies=hasAbility, amount=true } },      -- gives AMS since death strike is not *mandatory* for frost
        },
        [51271] = {
            { { id=51271, modifies=hasAbility, amount=true } }
        },
        [456240] = {
            { { id=51271, modifies=duration_variable, amount=ns.DURATION_GTE } }
        }
    },
    -- Unholy death knight ------------------------------------------------------------------------
    [252] = {
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
    },


    -- Arcane mage ----------------------------------------------------------------------------
    [62] = {
        [365350] = {
            { { id=365350, modifies=hasAbility, amount=true } },
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
            { { id=190319, modifies=requireConcurrentBuff, amount=true } },
        },
        [1257443] = {  -- apex talent r4 extends combustion duration
            { { } },    -- rank 1
            { { } },    -- rank 2
            { { } },    -- rank 3
            { { id=190319, modifies=duration_variable, amount=ns.DURATION_GTE } },    -- rank 4
        },
    },
    -- Frost mage -----------------------------------------------------------------------------
    [64] = {
        [235219] = {  -- XXX: TODO: cold snap reset. just model as CDR for now.
            { { id=45438, modifies=cdr, amount=true },
              { id=414659, modifies=cdr, amount=true } },
        },
        [1244110] = {
            { { id=45438, modifies=charges, amount=1 },
              { id=414659, modifies=charges, amount=1 } },
        }
    },


    -- Brewmaster monk ------------------------------------------------------------------------
    [268] = {
    },
    -- Mistweaver monk ------------------------------------------------------------------------
    [270] = {
        [116849] = {
            { { id=116849, modifies=hasAbility, amount=true } },
        },
        [202424] = {
            { { id=116849, modifies=cooldown, amount=-45 } },
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
            { { id=389539, modifies=hasAbility, amount=true } }
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
            -- supposedly does not extend sentinel's duration, should test
            -- rank 2 extends more than rank 1, but all that matters is the duration
            -- is longer than base. we can't know how many extensions will happen
            { { id=31884, modifies=duration_variable, amount=ns.DURATION_GTE } },
            { { id=31884, modifies=duration_variable, amount=ns.DURATION_GTE } }
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
            { { id=31884, modifies=cooldown, amount=-60 },   -- ret gets -60s on wings
              { id=498, modifies=hasAbility, amount=true } }   -- ret gets divine protection
        },
        [1261562] = {
            { { id=498, modifies=requireConcurrentBuff, amount=true } }
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
        }
    },


    -- Assassination rogue ---------------------------------------------------------------------
    [259] = {
    },
    -- Outlaw rogue ---------------------------------------------------------------------
    [260] = {
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
            { { id=185313, modifies=hasAbility, amount=true } },   -- give shadow dance
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
}
