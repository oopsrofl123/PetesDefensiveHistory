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
	},
	-- Frost
	[251] = {
		{
			name="Anti-Magic Shell",
            isBuff=true,
			id=48707,
			cooldown=40, -- talent: 60 > 40
			duration=7,  -- talent: 5 > 7 (+40%)
			duration_variable=ns.DURATION_LTE,  -- ends when shield broken
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		},
		{
			name="Icebound Fortitude",
            isBuff=true,
			id=48792,
			cooldown=120,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		}
	},
	-- Unholy
	[252] = {
		{
			name="Anti-Magic Shell",
            isBuff=true,
			id=48707,
			cooldown=40, -- talent: 60 > 40
			duration=7,  -- talent: 5 > 7 (+40%)
			duration_variable=ns.DURATION_LTE,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		},
		{
			name="Icebound Fortitude",
            isBuff=true,
			id=48792,
			cooldown=120,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		}
	},


	---------------------------------------------
	-- Demon hunter
	---------------------------------------------
	-- Havoc
	[577] = {
		{
			name="Blur",
            isBuff=true,
			id=212800,
			cooldown=60,
			duration=10,
			duration_variable=ns.DURATION_FIXED,
			charges=1,      -- talent 2 charges
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		}
	},
	-- Vengeance
	[581] = {
		{
			-- lot of talents affect this
			name="Fiery Brand",
            isBuff=true,
			id=207771,
			cooldown=60,             -- talent: 60 > 48
			duration=12,
			duration_variable=ns.DURATION_GTE, -- talent: spreading in multi-target and +0.25s duration on immo ticks
			charges=1,               -- talent: +1 charge
			cdr=false,
            importantFlag=false,
            bigFlag=true,
            externalFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		}
	},
	-- Devourer
	[1480] = {
		{
			name="Blur",
            isBuff=true,
			id=212800,
			cooldown=60,
			duration=10,
			duration_variable=ns.DURATION_FIXED,
			charges=1,      -- talent 2 charges
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		}
	},


	---------------------------------------------
	-- Druid
	---------------------------------------------
	-- Balance
	[102] = {
		{
			name="Barkskin",
            isBuff=true,
			id=22812,
			cooldown=60,
			duration=12,    -- talent: 8 > 12
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		}
	},
	-- Feral
	[103] = {
		{
			name="Barkskin",
            isBuff=true,
			id=22812,
			cooldown=60,
			duration=12,    -- talent: 8 > 12
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		}
	},
	-- Guardian
	[104] = {
        -- Survival instincts actually isn't tracked. wild.
		{
			name="Barkskin",
            isBuff=true,
			id=22812,
			cooldown=34.2,    -- talent: 45 > 34.2 (-12% per point, 2pts, 10.8s)
			duration=12,    -- base 8. talent: imp bark: +4, ursoc's endurance +2
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		}
	},
	-- Resto druid
	[105] = {
		{
			name="Barkskin",
            isBuff=true,
			id=22812,
			cooldown=60,
			duration=12,    -- talent: 8 > 12
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		},
		{
			name="Ironbark",
            isBuff=true,
			id=102342,
			cooldown=70,    -- talent: 90 > 70
			duration=12,    -- talent: 12 > 16 but maybe wont be taken
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=false,
            bigFlag=true,
            externalFlag=true,
			external=ns.EXTERNAL_ANY,
            concurrentDebuff=false
		}
	},


	---------------------------------------------
	-- Evoker
	---------------------------------------------
	-- Devastation
	[1467] = {
	},
	-- Preservation
	[1468] = {
	},
	-- Augmentation
	[1465] = {
	},
	

	---------------------------------------------
	-- Hunter
	---------------------------------------------
	-- Beast Mastery
	[253] = {
		{
			name="Survival of the Fittest",
            isBuff=true,
			id=264735,
			cooldown=90,
			duration=8,                -- talent: 6 > 8
			duration_variable=ns.DURATION_FIXED,
			charges=2,                 -- talent: 2 charges
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		},
	},
	-- Marks
	[254] = {
		{
			name="Survival of the Fittest",
            isBuff=true,
			id=264735,
			cooldown=90,
			duration=8,                -- talent: 6 > 8
			duration_variable=ns.DURATION_FIXED,
			charges=2,                 -- talent: 2 charges
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		},
    },
	-- Survival
	[255] = {
		{
			name="Survival of the Fittest",
            isBuff=true,
			id=264735,
			cooldown=90,
			duration=8,                -- talent: 6 > 8
			duration_variable=ns.DURATION_FIXED,
			charges=2,                 -- talent: 2 charges
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		},
	},


	---------------------------------------------
	-- Mage
	---------------------------------------------
	-- Ice block does appear as a big defensive even though it's an immunity
	-- all talents that affect ice cold equally affect ice block
	-- Arcane
	[62] = {
		-- XXX: any way to use hypothermia as extra info?
		{
			name="Ice Cold",
            isBuff=true,
			id=414658,
			cooldown=240,   -- base: 240 3 talents each give -30s
			duration=6,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		}
	},
	-- Fire
	[63] = {
		-- XXX: any way to use hypothermia as extra info?
		{
			name="Ice Cold",
            isBuff=true,
			id=414658,
			cooldown=240,   -- base: 240 3 talents each give -30s
			duration=6,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		}
	},
	-- Frost
	[64] = {
		-- Will be hard to track this properly: cold snap resets cooldown
		-- and other choice node talent gives a second charge.
		-- XXX: any way to use hypothermia as extra info?
		{
			name="Ice Cold",
            isBuff=true,
			id=414658,
			cooldown=240,   -- base: 240 3 talents each give -30s
			duration=6,
			duration_variable=ns.DURATION_FIXED,
			charges=1,      -- only frost has talent +1 charge
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		}
	},


	---------------------------------------------
	-- Monk
	---------------------------------------------
	-- Brewmaster
	[268] = {
		-- Yep, fort brew ignored by Blizzard
		-- fort brew: 120s cd > 90s cd with talent
		--{
		--	name="Fortifying Brew",
        --  isBuff=true,
		--	-- this ID might be diff for brew id=115203,
		--	cooldown=360   -- talent: 360 > 240 base is really 6min for brew
		--	duration=15,
		--	duration_variable=ns.DURATION_FIXED,
		--	charges=1,      -- only frost has talent +1 charge
		--	cdr=false,
		--	external=ns.NOT_EXTERNAL,
        --  concurrentDebuff=false
		--}
	},
	-- Mistweaver
	[270] = {
		-- life cocoon not tracked
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
            isBuff=true,
			id=6940,
			cooldown=105,   -- talent: -15s 120s > 105s  -- yes, holy's sac is worse than other specs
			duration=12,
			duration_variable=ns.DURATION_LTE,   -- cancels if caster falls < 20% health
			charges=1,
			cdr=false,
            importantFlag=false,
            bigFlag=true,
            externalFlag=true,
			external=ns.EXTERNAL_NOT_SELF,
            concurrentDebuff=false
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
            isBuff=true,
			id=31850,
			cooldown=63,  -- talent 90 > 63 (-30%)
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		},
        -- can't do this until move away from the CenterDefensiveBuff frame since it doesn't show there
        -- also it probably isn't
		-- {
			-- name="Divine Shield",
            -- isBuff=true,
			-- id=642,
			-- cooldown=175,  -- talent1: 300 > 210 (-30%), talent2: -15% 210 > 175
			-- duration=8,
			-- duration_variable=ns.DURATION_FIXED,
			-- charges=1,
			-- cdr=false,
            -- importantFlag=true,
            -- bigFlag=false,
            -- externalFlag=false,
			-- external=ns.NOT_EXTERNAL,
            -- concurrentDebuff=true
		-- },
		{
			name="Guardian of Ancient Kings",
            isBuff=true,
			id=86659,
			cooldown=180,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=2,      -- talent 2 charges
			cdr=true,
            importantFlag=false,
            bigFlag=true,
            externalFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		},
		{
			-- GoAK from cheat death talent
			name="Gift of the Golden Valkyr",
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
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=true
		},
		{
			name="Blessing of Sacrifice",
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
			external=ns.EXTERNAL_NOT_SELF,
            concurrentDebuff=false
		}
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
			external=ns.EXTERNAL_NOT_SELF,
            concurrentDebuff=false
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
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		}
	},
	-- Outlaw
	[260] = {
		{
			name="Cloak of Shadows",
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
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		}
	},
	-- Subtlety
	[261] = {
		{
			name="Cloak of Shadows",
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
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		}
	},


	---------------------------------------------
	-- Shaman
	---------------------------------------------
	-- Elemental
	[262] = {
		{
			name="Astral Shift",
            isBuff=true,
			id=108271,
			cooldown=90,   -- talent: 120 > 90
			duration=12,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		}
	},
	-- Enhancement
	[263] = {
		{
			name="Astral Shift",
            isBuff=true,
			id=108271,
			cooldown=90,   -- talent: 120 > 90
			duration=12,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		}
	},
	-- Resto
	[264] = {
		{
			name="Astral Shift",
            isBuff=true,
			id=108271,
			cooldown=90,   -- talent: 120 > 90
			duration=12,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true,
            bigFlag=true,
            externalFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		}
	},


	---------------------------------------------
	-- Warlock
	---------------------------------------------
	-- Affliction
	[265] = {
		{
			name="Unending Resolve",
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
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		}
	},
	-- Demo
	[266] = {
		{
			name="Unending Resolve",
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
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
		}
	},
	-- Destro
	[267] = {
		{
			name="Unending Resolve",
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
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
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
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false
        },
	},
}
