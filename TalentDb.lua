local _, ns = ...

-- These keys must match the table field names in the abilities database
local cdr = "cdr"
local charges = "charges"
local cooldown = "cooldown"
local duration = "duration"
local duration_variable = "duration_variable"
local hasAbility = "hasAbility"
local concurrentBuff = "concurrentBuff"

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
            { { id=255937, modifies=concurrentBuff, amount=true },
              { id=216331, modifies=concurrentBuff, amount=true },
              { id=31884, modifies=concurrentBuff, amount=true },
              { id=389539, modifies=concurrentBuff, amount=true } } 
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
    }
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
            { { id=498, modifies=concurrentBuff, amount=true } }
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
    }
}
