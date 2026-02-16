-- get addon namespace
local _, ns = ...


-- Eventually populate this with all abilities that are displayed by Blizzard's
-- center big defensive buffs option.
--
-- Why?
-- 
-- 1. If a class only has one defensive, then we can guess that when a defensive
--    icon is shown, it is either that spell or an external.
-- 2. If a class has more than one defensive, then the maximum cooldown across
--    all defensives is the maximum possible cooldown timer, so all cooldowns can
--    be reset when that number is reached.
--
-- Issue with externals: externals (like ironbark) show up as big defensive buffs,
-- meaning we can't correctly guess what ability is shown even for classes with only
-- a single defensive. However, we also don't aim to track externals since they don't
-- follow the basic logic of this addon.
--
-- TODO: deal with talents later


-- Is the duration static, possibly less than the stated amount (e.g., AMS?) or more than
-- the stated amount (e.g., Fiery Brand with spreading)?
ns.DURATION_FIXED = 0
ns.DURATION_LTE = 1    -- less than or equal to
ns.DURATION_GTE = 2    -- greaer than or equal to

-- Necessary because of blessing of sacrifice, which is the only defensive so
-- far that cannot be cast on self.
ns.NOT_EXTERNAL = 0
ns.EXTERNAL_ANY = 1
ns.EXTERNAL_NOT_SELF = 2


ns.SpecDefensiveDb = {
	---------------------------------------------
	-- Death knight
	---------------------------------------------
	-- Blood
	[250] = {
		{
			name="Anti-Magic Shell",
            buttonPress=true,
            isBuff=true,
			id=48707,
            iconId=136120,
			cooldown=40, -- talent: 60 > 40
			duration=7,  -- talent: 5 > 7 (+40%)
			duration_variable=ns.DURATION_LTE,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
		{
			name="Icebound Fortitude",
            buttonPress=true,
            isBuff=true,
			id=48792,
            iconId=237525,
			cooldown=120,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
		{
			name="Vampiric Blood",
            buttonPress=true,
            isBuff=true,
			id=55233,
            iconId=136168,
			cooldown=90,
			duration=10,  -- talent +2: 10 > 12
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=true,   -- talent CDR
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            -- adds Coagulating Blood (id=463730), which is not harmful but is
            -- not returned by the aura filter HELPFUL
            concurrentDebuff=true,
            certainOnFirstInference=true
		},
        
	},
	-- Frost
	[251] = {
		{
			name="Anti-Magic Shell",
            buttonPress=true,
            isBuff=true,
			id=48707,
            iconId=136120,
			cooldown=40, -- talent: 60 > 40
			duration=7,  -- talent: 5 > 7 (+40%)
			duration_variable=ns.DURATION_LTE,  -- ends when shield broken
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
		{
			name="Icebound Fortitude",
            buttonPress=true,
            isBuff=true,
			id=48792,
            iconId=237525,
			cooldown=120,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
		{
			name="Pillar of Frost",
            buttonPress=true,
            isBuff=true,
			id=51271,
            iconId=458718,
			cooldown=45,
			duration=12,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=false,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		}
	},
	-- Unholy
	[252] = {
		{
			name="Anti-Magic Shell",
            buttonPress=true,
            isBuff=true,
			id=48707,
            iconId=136120,
			cooldown=40, -- talent: 60 > 40
			duration=7,  -- talent: 5 > 7 (+40%)
			duration_variable=ns.DURATION_LTE,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
		{
			name="Icebound Fortitude",
            buttonPress=true,
            isBuff=true,
			id=48792,
            iconId=237525,
			cooldown=120,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		}
	},


	---------------------------------------------
	-- Demon hunter
	---------------------------------------------
	-- Havoc
	[577] = {
		{
			name="Blur",
            buttonPress=true,
            isBuff=true,
			id=198589,
            iconId=1305150,
			cooldown=60,
			duration=10,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		}
	},
	-- Vengeance
	[581] = {
		{
			name="Metamorphosis",
            buttonPress=true,
            isBuff=true,
			id=187827,
            iconId=1247263,
			cooldown=120,
			duration=20,         -- talent: 15 > 20, req for cheat death talent, so maybe safe to assume
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,           -- true for annihilator
            importantFlag=true,
            bigFlag=false,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=false -- can't track Meta because of the apex talent. however, if meta and the apex talent are the only things that could have happened, we do know what buff as applied (meta) but not which coodown to track (meta or apex)
		},
        -- Cheat death from meta. Gives a full duration meta, so only way to differentiate
        -- is through concurrent debuff (Uncontained Fel, spellID=209261),
		{
			name="Last Resort",
            buttonPress=false,   -- fires on its own, without the player pressing a button, so do not check the cast history
            isBuff=false,
			id=187827,
            iconId=1348655,
			cooldown=480,
			duration=20,         -- talent: 15 > 20, req for cheat death talent, so maybe safe to assume
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,           -- true for annihilator
            importantFlag=true,
            bigFlag=false,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=true,
            certainOnFirstInference=true
		},
        -- Apex talent: allows meta to be cast but it only lasts 10s. So we can't ever
        -- know which meta is cast (and whether it incurred a cooldown) until after the
        -- buff completes.
		{
			name="Untethered Rage",
            buttonPress=true,
            isBuff=false,
			id=187827,
            iconId=7636527,
			cooldown=0,
			duration=10,         -- talent: 15 > 20, req for cheat death talent, so maybe safe to assume
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,           -- true for annihilator
            importantFlag=true,
            bigFlag=false,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            -- confusingly, although this ability is why meta can't be inferred instantly,
            -- this flag should be false here.
            certainOnFirstInference=true,
            -- Only for active buff tracking
            activeBuff="Metamorphosis"
		},
		-- lot of talents affect brand
		{
			name="Fiery Brand",
            buttonPress=true,
            isBuff=true,
			id=207771,
            iconId=1344647,
			cooldown=60,             -- talent: 60 > 48
			duration=12,
			duration_variable=ns.DURATION_GTE, -- talent: spreading in multi-target and +0.25s duration on immo ticks
			charges=1,               -- talent: +1 charge, same talent that affects cd
			cdr=false,
            importantFlag=false,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		}
	},
	-- Devourer
	[1480] = {
		{
			name="Blur",
            buttonPress=true,
            isBuff=true,
			id=198589,
			cooldown=60,
			duration=10,
			duration_variable=ns.DURATION_FIXED,
			charges=1,      -- talent 2 charges
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		}
	},


	---------------------------------------------
	-- Druid
	---------------------------------------------
	-- Balance
	[102] = {
		{
			name="Barkskin",
            buttonPress=true,
            isBuff=true,
			id=22812,
            iconId=136097,
			cooldown=60,
			duration=12,    -- talent: 8 > 12
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
        -- Can only have one of celestial alignment or incarn
		{
			name="Celestial Alignment",
            buttonPress=true,
            isBuff=true,
			id=383410,
            iconId=136060,
			cooldown=120,   -- talent: 180 > 120
			duration=15,    -- talent: 8 > 12
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,  -- there is a weird CDR hero talent in hero talents keeper of the grove
            importantFlag=true,
            bigFlag=false,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
		{
			name="Incarnation: Chosen of Elune",
            buttonPress=true,
            isBuff=true,
			id=102560,
            iconId=571586,
			cooldown=120,   -- talent: 180 > 120
			duration=20,    -- talent: 8 > 12
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=false,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
	},
	-- Feral
	[103] = {
		{
			name="Barkskin",
            buttonPress=true,
            isBuff=true,
			id=22812,
            iconId=136097,
			cooldown=60,
			duration=12,    -- talent: 8 > 12
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
        -- Either incarn or berserk+convoke
		{
			name="Incarnation: Avatar of Ashamane",
            buttonPress=true,
            isBuff=true,
			id=102543,
            iconId=571586,
			cooldown=120,    -- base: 3min, talent1: -60, talent2: -30
			duration=20,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=false,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		}
	},
	-- Guardian
	[104] = {
		{
			name="Barkskin",
            buttonPress=true,
            isBuff=true,
			id=22812,
            iconId=136097,
			cooldown=34.2,    -- talent: 45 > 34.2 (-12% per point, 2pts, 10.8s)
			duration=12,    -- base 8. talent: imp bark: +4, ursoc's endurance +2
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
		{
			name="Incarnation: Guardian of Ursoc",
            buttonPress=true,
            isBuff=true,
			id=102558,
            iconId=571586,
			cooldown=180,
			duration=30,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=true,
            importantFlag=true,
            bigFlag=false,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		}
        -- there is a spell called Survival Insticts marked as BIG_DEFENSIVE, but it's
        -- the wrong spell ID (=50322), so it is not tracked.
		-- {
			-- name="Survival Instincts",
            -- buttonPress=true,
            -- isBuff=true,
			-- id=61336,
            -- iconId=236169,
			-- cooldown=180,
			-- duration=6,
			-- duration_variable=ns.DURATION_FIXED,
			-- charges=2,
			-- cdr=false,
            -- importantFlag=true,
            -- bigFlag=false,
            -- externalFlag=false,
            -- raidFlag=false,
            -- raidInCombatFlag=false,
			-- external=ns.NOT_EXTERNAL,
            -- concurrentDebuff=false,
            -- certainOnFirstInference=true
		-- }
	},
	-- Resto druid
	[105] = {
		{
			name="Barkskin",
            buttonPress=true,
            isBuff=true,
			id=22812,
            iconId=136097,
			cooldown=60,
			duration=12,    -- talent: 8 > 12
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
		{
			name="Ironbark",
            buttonPress=true,
            isBuff=true,
			id=102342,
            iconId=572025,
			cooldown=70,    -- talent: 90 > 70
			duration=12,    -- talent: 12 > 16 but maybe wont be taken
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=false,
            bigFlag=true,
            externalFlag=true,
            raidFlag=true,
            raidInCombatFlag=true,
			external=ns.EXTERNAL_ANY,
            concurrentDebuff=false,
            certainOnFirstInference=true
		}
	},


	---------------------------------------------
	-- Evoker
	---------------------------------------------
	-- Devastation
	[1467] = {
		{
			name="Dragonrage",
            buttonPress=true,
            isBuff=true,
			id=375087,
            iconId=4622452,
			cooldown=120,
			duration=18,
			duration_variable=ns.DURATION_GTE,  -- talent: +5s per empowered spell
			charges=2,
			cdr=false,
            importantFlag=true,
            bigFlag=false,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
        -- hero talent: applies to your target or a random nearby injured ally at 50%.
        -- turns scales into an external.
        -- XXX: TODO: however, the external buff is not imp|big|external flagged, so it
        -- doesn't trigger inference.
		{
			name="Obsidian Scales",
            buttonPress=true,
            isBuff=true,
			id=363916,
            iconId=1394891,
			cooldown=90,
			duration=12,
			duration_variable=ns.DURATION_FIXED,
			charges=2,                 -- talent: 2 charges
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=true,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
	},
	-- Preservation
	[1468] = {
		{
			name="Time Dilation",
            buttonPress=true,
            isBuff=true,
			id=357170,
            iconId=4622478,
			cooldown=60,               -- talent: -10s 60>50
			duration=8,                -- talent: +15% 8>9.2
			duration_variable=ns.DURATION_FIXED,
			charges=2,                 -- talent: +1 charge
			cdr=false,
            importantFlag=false,
            bigFlag=true,
            externalFlag=true,
            raidFlag=true,
            raidInCombatFlag=true,
			external=ns.EXTERNAL_ANY,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
        -- hero talent: applies to your target or a random nearby injured ally at 50%.
        -- turns scales into an external.
        -- XXX: TODO: however, the external buff is not imp|big|external flagged, so it
        -- doesn't trigger inference.
		{
			name="Obsidian Scales",
            buttonPress=true,
            isBuff=true,
			id=363916,
            iconId=1394891,
			cooldown=90,
			duration=12,
			duration_variable=ns.DURATION_FIXED,
			charges=2,                 -- talent: 2 charges
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=true,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
	},
	-- Augmentation
	[1473] = {
		{
			name="Obsidian Scales",
            buttonPress=true,
            isBuff=true,
			id=363916,
            iconId=1394891,
			cooldown=81,      -- looks like aug gets baseline -10% (-9s, 90>81)
			duration=12.5,
			duration_variable=ns.DURATION_FIXED,
			charges=2,                 -- talent: 2 charges
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=true,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
	},
	

	---------------------------------------------
	-- Hunter
	---------------------------------------------
	-- Beast Mastery
	[253] = {
		{
			name="Survival of the Fittest",
            buttonPress=true,
            isBuff=true,
			id=264735,
            iconId=136094,
			cooldown=90,
			duration=8,                -- talent: 6 > 8
			duration_variable=ns.DURATION_FIXED,
			charges=2,                 -- talent: 2 charges
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
	},
	-- Marks
	[254] = {
		{
			name="Survival of the Fittest",
            buttonPress=true,
            isBuff=true,
			id=264735,
            iconId=136094,
			cooldown=90,
			duration=8,                -- talent: 6 > 8
			duration_variable=ns.DURATION_FIXED,
			charges=2,                 -- talent: 2 charges
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
		{
			name="Trueshot",
            buttonPress=true,
            isBuff=true,
			id=288613,
            iconId=132329,
			cooldown=90,    -- talent -30s
			duration=15,                -- hero talent: +4
			duration_variable=ns.DURATION_FIXED,
			charges=2,
			cdr=false,
            importantFlag=true,
            bigFlag=false,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
    },
	-- Survival
	[255] = {
		{
			name="Survival of the Fittest",
            buttonPress=true,
            isBuff=true,
			id=264735,
            iconId=136094,
			cooldown=90,
			duration=8,                -- talent: 6 > 8
			duration_variable=ns.DURATION_FIXED,
			charges=2,                 -- talent: 2 charges
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
        -- Although marked IMPORTANT, exhilaration isn't a buff. It causes a short
        -- HoT buff if talented, but that HoT is not important, so wouldn't be detected.
		-- {
			-- name="Exhilaration"
            -- buttonPress=true,
            -- isBuff=true,
			-- id=109304,
            -- iconId=461117,
			-- cooldown=60,   -- talent: 2pts -60s
			-- duration=12,
			-- duration_variable=ns.DURATION_FIXED,
			-- charges=1,
			-- cdr=false,
            -- importantFlag=true,
            -- bigFlag=true,
            -- externalFlag=false,
            -- raidFlag=false,
            -- raidInCombatFlag=false,
			-- external=ns.NOT_EXTERNAL,
            -- concurrentDebuff=false,
            -- certainOnFirstInference=true
		-- },
	},


	---------------------------------------------
	-- Mage
	---------------------------------------------
	-- XXX: TODO: handle ice block for all specs. does anyone take ice block in m+?
	-- all talents that affect ice cold equally affect ice block
	-- Arcane
	[62] = {
		{
            -- XXX: TODO: arcane surge always comes with several other buffs. maybe
            -- can use that to identify.
			name="Arcane Surge",
            buttonPress=true,
            isBuff=true,
			id=365350,
            iconId=4667417,
			cooldown=90,
			duration=15,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=false,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
		{
			name="Ice Cold",
            buttonPress=true,
            isBuff=true,
			id=414658,
            iconId=135777,
			cooldown=240,   -- base: 240 3 talents each give -30s
			duration=6,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=true,
            certainOnFirstInference=true
		},
		{
			name="Mirror Image",
            buttonPress=true,
            isBuff=true,
			id=55342,
            iconId=135994,
			cooldown=120,   -- base 120, talent -30
			duration=15,
			duration_variable=ns.DURATION_LTE,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=false,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
		{
			name="Alter Time",
            buttonPress=true,
            isBuff=true,
			id=342245,
            iconId=609811,
			cooldown=50,   -- hero talent -40s 50>40
			duration=10,
			duration_variable=ns.DURATION_LTE,
			charges=1,
			cdr=false,
            -- this disagrees with C_Spell.IsSpellImportant and C_UnitAuras.AuraIsBigDefensive
            -- but this is what happens in game. There are other Alter Time spell IDs, but this
            -- spell ID is the one shown by idTip in game.
            importantFlag=true,   -- false
            bigFlag=false,        -- true
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		}
	},
	-- Fire
	[63] = {
		{
			name="Combustion",
            buttonPress=true,
            isBuff=true,
			id=190319,
            iconId=135824,
			cooldown=60,   -- several talents
			duration=12,
			duration_variable=ns.DURATION_GTE,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=false,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
		-- XXX: any way to use hypothermia as extra info?
		{
			name="Ice Cold",
            buttonPress=true,
            isBuff=true,
			id=414658,
            iconId=135777,
			cooldown=240,   -- base: 240 3 talents each give -30s
			duration=6,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=true,
            certainOnFirstInference=true
		},
		{
			name="Mirror Image",
            buttonPress=true,
            isBuff=true,
			id=55342,
            iconId=135994,
			cooldown=120,   -- base 120, talent -30
			duration=15,
			duration_variable=ns.DURATION_LTE,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=false,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
		{
			name="Alter Time",
            buttonPress=true,
            isBuff=true,
			id=342245,
            iconId=609811,
			cooldown=50,     -- hero talent 50>40 (-10s)
			duration=10,
			duration_variable=ns.DURATION_LTE,
			charges=1,
			cdr=false,
            -- this disagrees with C_Spell.IsSpellImportant and C_UnitAuras.AuraIsBigDefensive
            -- but this is what happens in game. There are other Alter Time spell IDs, but this
            -- spell ID is the one shown by idTip in game.
            importantFlag=true,   -- false
            bigFlag=false,        -- true
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		}
	},
	-- Frost
	[64] = {
		-- Will be hard to track this properly: cold snap resets cooldown
		-- and other choice node talent gives a second charge.
		{
			name="Ice Cold",
            buttonPress=true,
            isBuff=true,
			id=414658,
            iconId=135777,
			cooldown=240,   -- base: 240 3 talents each give -30s
			duration=6,
			duration_variable=ns.DURATION_FIXED,
			charges=1,      -- only frost has talent +1 charge
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=true,
            certainOnFirstInference=true
		},
		{
			name="Mirror Image",
            buttonPress=true,
            isBuff=true,
			id=55342,
            iconId=135994,
			cooldown=120,   -- base 120, talent -30
			duration=15,
			duration_variable=ns.DURATION_LTE,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=false,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
		{
			name="Alter Time",
            buttonPress=true,
            isBuff=true,
			id=342245,
            iconId=609811,
			cooldown=50,
			duration=10,
			duration_variable=ns.DURATION_LTE,
			charges=1,
			cdr=false,
            -- this disagrees with C_Spell.IsSpellImportant and C_UnitAuras.AuraIsBigDefensive
            -- but this is what happens in game. There are other Alter Time spell IDs, but this
            -- spell ID is the one shown by idTip in game.
            importantFlag=true,   -- false
            bigFlag=false,        -- true
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		}
	},


	---------------------------------------------
	-- Monk
	---------------------------------------------
	-- Brewmaster
	[268] = {
        -- XXX: TODO: actual in-game buff is not imp or big flagged, so not observable
		-- {
	   	    -- name="Fortifying Brew",
            -- buttonPress=true,
            -- isBuff=true,
			-- id=115203,
            -- iconId=615341,
		    --	cooldown=360   -- talent: 360 > 240 base is really 6min for brew
			-- duration=15,
			-- duration_variable=ns.DURATION_FIXED,
			-- charges=1,
			-- cdr=false,
            -- importantFlag=true,
            -- bigFlag=true,
            -- externalFlag=false,
            -- raidFlag=false,
            -- raidInCombatFlag=false,
			-- external=ns.NOT_EXTERNAL,
            -- concurrentDebuff=false,
            -- certainOnFirstInference=true
		-- },
	},
	-- Mistweaver
	[270] = {
        -- actual in-game buff is not imp or big flagged, so not observable
		-- {
	   	    -- name="Fortifying Brew",
            -- buttonPress=true,
            -- isBuff=true,
			-- id=115203,
            -- iconId=615341,
			-- cooldown=120,   -- base 120, talent -30
			-- duration=15,
			-- duration_variable=ns.DURATION_FIXED,
			-- charges=1,
			-- cdr=false,
            -- importantFlag=true,
            -- bigFlag=true,
            -- externalFlag=false,
            -- raidFlag=false,
            -- raidInCombatFlag=false,
			-- external=ns.NOT_EXTERNAL,
            -- concurrentDebuff=false,
            -- certainOnFirstInference=true
		-- },
		-- life cocoon not tracked
        -- XXX: TODO: need to test this when cast on someone else
        {
			name="Life Cocoon",
            buttonPress=true,
            isBuff=true,
			id=116849,
            iconId=627485,
			cooldown=75,   -- base 120, talent -45
			duration=12,
			duration_variable=ns.DURATION_LTE,
			charges=1,
			cdr=true,
            importantFlag=false,
            bigFlag=false,
            externalFlag=true,
            raidFlag=true,
            raidInCombatFlag=true,
			external=ns.EXTERNAL_ANY,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
	},
	-- Windwalker
	[269] = {
		-- touch of karma also ignored
		-- Yep, fort brew ignored by Blizzard
		-- fort brew: 120s cd > 90s cd with talent
		--{
		--	name="Fortifying Brew",
        --  isBuff=true,
		--	id=115203,
		--	cooldown=120,   -- talent: 120 > 90
		--	duration=15,
		--	duration_variable=ns.DURATION_FIXED,
		--	charges=1,      -- only frost has talent +1 charge
		--	cdr=false,
		--	external=ns.NOT_EXTERNAL,
        --  concurrentDebuff=false
		--}
	},


	---------------------------------------------
	-- Paladin
	---------------------------------------------
	-- Holy
	[65] = {
		{
			name="Blessing of Sacrifice",
            buttonPress=true,
            isBuff=true,
			id=6940,
            iconId=135966,
			cooldown=105,   -- talent: -15s 120s > 105s  -- yes, holy's sac is worse than other specs
			duration=12,
			duration_variable=ns.DURATION_LTE,   -- cancels if caster falls < 20% health
			charges=1,
			cdr=false,
            importantFlag=false,
            bigFlag=true,
            externalFlag=true,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.EXTERNAL_NOT_SELF,
            concurrentDebuff=false,
            certainOnFirstInference=true
		}
		-- Divine Protection is not tracked
		--{
		--	name="Divine Protection",
        --  isBuff=true,
		--	id=403876,
		--	cooldown=60,   -- talent: -30%: 60s > 48s  -- base is diff from ret
		--	duration=8,
		--	duration_variable=ns.DURATION_FIXED,
		--	charges=1,
		--	cdr=false,
		--	external=ns.NOT_EXTERNAL,
        --  concurrentDebuff=false
		--},
	},
	-- Protection
	[66] = {
		{
			name="Ardent Defender",
            buttonPress=true,
            isBuff=true,
			id=31850,
            iconId=135870,
			cooldown=63,  -- talent 90 > 63 (-30%)
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
		{
			name="Divine Shield",
            buttonPress=true,
            isBuff=true,
			id=642,
            iconId=524354,
			cooldown=175,  -- talent1: 300 > 210 (-30%), talent2: -15% 210 > 175
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=false,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=true,
            certainOnFirstInference=true
		},
		{
			name="Guardian of Ancient Kings",
            buttonPress=true,
            isBuff=true,
			id=86659,
            iconId=135919,
			cooldown=180,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=2,      -- talent 2 charges
			cdr=true,
            importantFlag=false,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
		{
			-- GoAK from cheat death talent
			name="Gift of the Golden Valkyr",
            buttonPress=false,    -- does not require the player to press a button, don't check cast history
            isBuff=false,
			id=393108,
            iconId=1349535,   -- blizzard shows the GoAK icon. show the talent instead
			cooldown=45,
			duration=4,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            -- match GoAK - cheat death procs a shorter GoAK that is not flagged BIG_DEFENSIVE
            importantFlag=false,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=true,
            certainOnFirstInference=true
		},
		{
			name="Blessing of Sacrifice",
            buttonPress=true,
            isBuff=true,
			id=6940,
            iconId=135966,
			cooldown=60,   -- talent 2min > 1min
			duration=12,
			duration_variable=ns.DURATION_LTE,   -- cancels if caster falls < 20% health
			charges=1,
			cdr=false,
            importantFlag=false,
            bigFlag=true,
            externalFlag=true,
            raidFlag=true,
            raidInCombatFlag=true,
			external=ns.EXTERNAL_NOT_SELF,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
        -- XXX: TODO: BoP isn't flagged as important
		{
			name="Blessing of Protection",
            buttonPress=true,
            isBuff=true,
			id=1022,
            iconId=135964,
			--cooldown=195,   -- base: 300, talent1: -60s, talent2: -15% (=45s)
            -- in game testing shows 205s cd, not the above expected
			cooldown=205,   -- base: 300, talent1: -60s, talent2: -15% (=45s)
			duration=10,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=false,
            bigFlag=false,
            externalFlag=true,
            raidFlag=true,
            raidInCombatFlag=true,
			external=ns.EXTERNAL_ANY,
            concurrentDebuff=false,    -- applies forbearance, but the debuff isn't in the same payload
            certainOnFirstInference=true
		},
		{
			name="Blessing of Spellwarding",
            buttonPress=true,
            isBuff=true,
			id=6940,
            iconId=135880,
			--cooldown=195,   -- base: 300, talent1: -60s, talent2: -15% (=45s)
            -- in game testing shows 205s cd, not the above expected
			cooldown=205,   -- base: 300, talent1: -60s, talent2: -15% (=45s)
			duration=10,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=false,
            externalFlag=true,
            raidFlag=true,
            raidInCombatFlag=false,
			external=ns.EXTERNAL_ANY,
            concurrentDebuff=false,  -- applies forbearance, but the debuff isn't in the same payload
            certainOnFirstInference=true
		},
		{
			name="Blessing of Freedom",
            buttonPress=true,
            isBuff=true,
			id=1044,
            iconId=135968,
			cooldown=25,   -- WRONG
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=false,
            externalFlag=false,
            raidFlag=true,
            raidInCombatFlag=false,
			external=ns.EXTERNAL_ANY,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
		{
			name="Avenging Wrath",
            buttonPress=true,
            isBuff=true,
			id=31884,
            iconId=135875,
			cooldown=120,   -- WRONG
			duration=18,
			duration_variable=ns.DURATION_GTE,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=false,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
	},
	-- Retribution
	[70] = {
		-- Divine Protection is not tracked
		--{
		--	name="Divine Protection",
        --  isBuff=true,
		--	id=403876,
		--	cooldown=60,   -- talent: -30%: 90s > 63s
		--	duration=8,
		--	duration_variable=ns.DURATION_FIXED,
		--	charges=1,
		--	cdr=false,
		--	external=ns.NOT_EXTERNAL,
        --  concurrentDebuff=false
		--},
		{
			name="Blessing of Sacrifice",
            buttonPress=true,
            isBuff=true,
			id=6940,
			cooldown=60,   -- talent 2min > 1min
			duration=12,
			duration_variable=ns.DURATION_LTE,   -- cancels if caster falls < 20% health
			charges=1,
			cdr=false,
            importantFlag=false,
            bigFlag=true,
            externalFlag=true,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.EXTERNAL_NOT_SELF,
            concurrentDebuff=false,
            certainOnFirstInference=true
		}
	},


	---------------------------------------------
	-- Priest
	---------------------------------------------
	-- Discipline
	[256] = {
	},
	-- Holy
	[257] = {
	},
	-- Shadow
	[258] = {
	},


	---------------------------------------------
	-- Rogue
	---------------------------------------------
	-- Assassination
	[259] = {
		{
			name="Cloak of Shadows",
            buttonPress=true,
            isBuff=true,
			id=31224,
			cooldown=120,   -- talent: 120 > 90
			duration=5,     -- hero talent: 5 > 7
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=false,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		}
	},
	-- Outlaw
	[260] = {
		{
			name="Cloak of Shadows",
            buttonPress=true,
            isBuff=true,
			id=31224,
			cooldown=120,   -- talent: 120 > 90
			duration=5,     -- hero talent: 5 > 7
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=false,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		}
	},
	-- Subtlety
	[261] = {
		{
			name="Cloak of Shadows",
            buttonPress=true,
            isBuff=true,
			id=31224,
			cooldown=120,   -- talent: 120 > 90
			duration=5,     -- hero talent: 5 > 7
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=false,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		}
	},


	---------------------------------------------
	-- Shaman
	---------------------------------------------
	-- Elemental
	[262] = {
		{
			name="Astral Shift",
            buttonPress=true,
            isBuff=true,
			id=108271,
            iconId=538565,
			cooldown=90,   -- talent: 120 > 90
			duration=12,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		}
	},
	-- Enhancement
	[263] = {
		{
			name="Astral Shift",
            buttonPress=true,
            isBuff=true,
			id=108271,
            iconId=538565,
			cooldown=90,   -- talent: 120 > 90
			duration=12,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		}
	},
	-- Resto
	[264] = {
		{
			name="Astral Shift",
            buttonPress=true,
            isBuff=true,
			id=108271,
            iconId=538565,
			cooldown=90,   -- talent: 120 > 90
			duration=12,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		}
	},


	---------------------------------------------
	-- Warlock
	---------------------------------------------
	-- Affliction
	[265] = {
		{
			name="Unending Resolve",
            buttonPress=true,
            isBuff=true,
			id=104773,
			cooldown=135,   -- talent: 180 > 135
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		}
	},
	-- Demo
	[266] = {
		{
			name="Unending Resolve",
            buttonPress=true,
            isBuff=true,
			id=104773,
			cooldown=135,   -- talent: 180 > 135
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		}
	},
	-- Destro
	[267] = {
		{
			name="Unending Resolve",
            buttonPress=true,
            isBuff=true,
			id=104773,
			cooldown=135,   -- talent: 180 > 135
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		}
	},


	---------------------------------------------
	-- Warrior
	---------------------------------------------
	-- Arms
	[71] = {
	},
	-- Fury
	[72] = {
	},
	-- Protection
	[73] = {
        -- There are so many talents that affect shield wall
        {
			name="Shield Wall",
            buttonPress=true,
            isBuff=true,
			id=871,
			cooldown=120,   -- talent 1: -10%, talent 2: -60s
			duration=8,     -- luckily duration is never affected
			duration_variable=ns.DURATION_FIXED,
			charges=2,
			cdr=true,       -- talent 1: 20 rage=1s, talent 2: shield slam=6s
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
            raidFlag=false,
            raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
        }
	},
}
