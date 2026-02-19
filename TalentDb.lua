local _, ns = ...

-- These keys must match the table field names in the abilities database
local cdr = "cdr"
local charges = "charges"
local cooldown = "cooldown"
local duration = "duration"
local duration_variable = "duration_variable"
local hasAbility = "hasAbility"


--
-- Table structure: spellId -> { talentrank1 { ... }, ..., talentrankN { ... } }
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
ns.TalentModifiers = {
    -- Paladin class tree --------------------------------------------------------------------------------
    [385633] = {  -- all specs are given the auras talent
        -- give all paladins bubble
        { { id=524354, modifies=hasAbility, amount=true } },
    },
    [1044] = {
        { { id=135968, modifies=hasAbility, amount=true } }
    },
    [1022] = {
        { { id=135964, modifies=hasAbility, amount=true } }
    },
    [6940] = {
        { { id=135966, modifies=hasAbility, amount=true } }
    },
    [384820] = {
        { { id=135966, modifies=cooldown, amount=-60 } }
    },
    [384909] = {
        { { id=135964, modifies=cooldown, amount=-60 },
          { id=135880, modifies=cooldown, amount=-60 } }
    },
    [114154] = {
        { { id=524354, modifies=cooldown, amount=-30, mult=true },
          { id=135870, modifies=cooldown, amount=-30, mult=true },
          { id=135928, modifies=cooldown, amount=-30, mult=true } }
    },

    -- Prot Paladin --------------------------------------------------------------------------------
    [31850] = {
        { { id=135870, modifies=hasAbility, amount=true } }
    },
    [204018] = {
        { { id=135880, modifies=hasAbility, amount=true } }
    },
    [392928] = {
        { { id=135928, modifies=cdr, amount=true } }
    },
    [31884] = {
        { { id=135875, modifies=hasAbility, amount=true } }
    },
    [389539] = {
        { { id=135922, modifies=hasAbility, amount=true } }
    },
    [86659] = {
        { { id=135919, modifies=hasAbility, amount=true } }
    },
    [378425] = {
        { { id=524354, modifies=cooldown, amount=-15, mult=true },
          { id=135964, modifies=cooldown, amount=-15, mult=true },
          { id=135880, modifies=cooldown, amount=-15, mult=true },
          { id=135928, modifies=cooldown, amount=-15, mult=true } }
    },
    [53376] = {
        { { id=135922, modifies=duration, amount=25, mult=true },
          { id=135875, modifies=duration, amount=25, mult=true } }
    },
    [378279] = {
        { { id=1349535, modifies=hasAbility, amount=true },
          { id=135919, modifies=cdr, amount=true } }
    },
    [1246481] = {
        { { id=135919, modifies=charges, amount=1 } }
    },
    [391142] = {
        -- supposedly does not extend sentinel's duration, should test
        -- rank 2 extends more than rank 1, but all that matters is the duration
        -- is longer than base. we can't know how many extensions will happen
        { { id=135875, modifies=duration_variable, amount=ns.DURATION_GTE } },
        { { id=135875, modifies=duration_variable, amount=ns.DURATION_GTE } }
    },
    [204074] = {
        { { id=135922, modifies=cooldown, amount=-50, mult=true },
          { id=135922, modifies=duration, amount=-40, mult=true },
          { id=135875, modifies=cooldown, amount=-50, mult=true },
          { id=135875, modifies=duration, amount=-40, mult=true } }
    },
    [432866] = {
        { { id=135928, modifies=cdr, amount=true } }
    }
}
