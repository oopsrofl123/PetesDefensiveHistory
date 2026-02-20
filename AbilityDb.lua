-- get addon namespace
local _, ns = ...


-- All abilities flagged by Blizzard as IMPORTANT, BIG_DEFENSIVE or EXTERNAL.


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


-- The unique key in this database is spell ID. It is structured by class, not by spec.
-- The class names are the locale-indepedent names that are used to key many internal
-- WoW tables.
ns.AbilityDb = {
	----------------------------------------------------------------------------------------
    ["DEATHKNIGHT"] = {
		{
			name="Anti-Magic Shell",
            buttonPress=true,
            isBuff=true,
			id=48707,
            iconId=136120,
			cooldown=60,
			duration=5,
			duration_variable=ns.DURATION_LTE,
			charges=1,
			cdr=false,
            importantFlag=true, bigFlag=true, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
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
            importantFlag=true, bigFlag=true, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
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
			duration=10,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,   -- talent CDR
            importantFlag=true, bigFlag=true, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            -- adds Coagulating Blood (id=463730), which is not harmful but is
            -- not returned by the aura filter HELPFUL
            concurrentDebuff=true,
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
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
	},

	----------------------------------------------------------------------------------------
    ["DEMONHUNTER"] = {
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
            importantFlag=true, bigFlag=true, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
        -- VDH meta is a different spell from Havoc (191427) and Devourer (void meta - 1217605).
        -- Only the VDH version is flagged IMPORTANT.
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
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
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
			id=209258,
            iconId=1348655,
			cooldown=480,
			duration=20,         -- talent: 15 > 20, req for cheat death talent, so maybe safe to assume
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,           -- true for annihilator
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
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
			id=1270444,
            iconId=7636527,
			cooldown=0,
			duration=10,         -- talent: 15 > 20, req for cheat death talent, so maybe safe to assume
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,           -- true for annihilator
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
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
            importantFlag=false, bigFlag=true, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
	},


	----------------------------------------------------------------------------------------
    ["DRUID"] = {
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
            importantFlag=true, bigFlag=true, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
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
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
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
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
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
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
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
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
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
            -- importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			-- external=ns.NOT_EXTERNAL,
            -- concurrentDebuff=false,
            -- certainOnFirstInference=true
		-- }
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
            importantFlag=false, bigFlag=true, externalFlag=true, raidFlag=true, raidInCombatFlag=true,
			external=ns.EXTERNAL_ANY,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
	},

	----------------------------------------------------------------------------------------
    ["EVOKER"] = {
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
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
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
			charges=2,       -- talent: 2 charges
			cdr=false,
            importantFlag=true, bigFlag=true, externalFlag=false, raidFlag=true, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
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
            importantFlag=false, bigFlag=true, externalFlag=true, raidFlag=true, raidInCombatFlag=true,
			external=ns.EXTERNAL_ANY,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
	},
	
	----------------------------------------------------------------------------------------
    ["HUNTER"] = {
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
            importantFlag=true, bigFlag=true, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
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
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
        -- Although marked IMPORTANT, exhilaration isn't a buff. It causes a short
        -- HoT buff if talented, but that HoT is not important. Haven't figured out
        -- a way to detect when Exhil is cast yet.
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
            -- importantFlag=true, bigFlag=true, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			-- external=ns.NOT_EXTERNAL,
            -- concurrentDebuff=false,
            -- certainOnFirstInference=true
		-- },
	},


	----------------------------------------------------------------------------------------
    ["MAGE"] = {
        -- XXX: TODO: arcane surge always comes with several other buffs. maybe
        -- can use that to identify.
		{
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
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
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
            importantFlag=true, bigFlag=true, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
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
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
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
            externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
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
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
	},


	----------------------------------------------------------------------------------------
    ["MONK"] = {
        -- XXX: TODO: buff in-game is not imp or big flagged, so not observable
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
            -- importantFlag=true, bigFlag=true, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			-- external=ns.NOT_EXTERNAL,
            -- concurrentDebuff=false,
            -- certainOnFirstInference=true
		-- },
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
            importantFlag=false, bigFlag=false, externalFlag=true, raidFlag=true, raidInCombatFlag=true,
			external=ns.EXTERNAL_ANY,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
	},

	----------------------------------------------------------------------------------------
    ["PALADIN"] = {
		{
			name="Blessing of Sacrifice",
            buttonPress=true,
            isBuff=true,
			id=6940,
            iconId=135966,
			cooldown=120,
			duration=12,
			duration_variable=ns.DURATION_LTE,   -- cancels if caster falls < 20% health
			charges=1,
			cdr=false,
            importantFlag=false, bigFlag=true, externalFlag=true, raidFlag=true, raidInCombatFlag=true,
			external=ns.EXTERNAL_NOT_SELF,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
        -- XXX: TODO: for ret, casts concurrent buff shield of vengeance
		{
			name="Divine Protection",
            buttonPress=true,
            isBuff=true,
			id=498,
            iconId=524353,
			cooldown=60,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
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
			cooldown=300,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=true,
            certainOnFirstInference=true
		},
        -- XXX: TODO: forbearance: when applied to someone else, forbearance is applied in
        -- a separate, immediately following UNIT_AURA call. good example of where a delayed
        -- inference could add support through a new confidence layer.
		{
			name="Blessing of Protection",
            buttonPress=true,
            isBuff=true,
			id=1022,
            iconId=135964,
			cooldown=300,
			duration=10,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=false, bigFlag=false, externalFlag=true, raidFlag=true, raidInCombatFlag=true,
			external=ns.EXTERNAL_ANY,
            concurrentDebuff=false,    -- applies forbearance, but the debuff isn't in the same payload
            certainOnFirstInference=true
		},
		{
			name="Blessing of Freedom",
            buttonPress=true,
            isBuff=true,
			id=1044,
            iconId=135968,
			cooldown=25,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=true, raidInCombatFlag=false,
			external=ns.EXTERNAL_ANY,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
        -- Ret talent removes wings and attaches it to wake of ashes. The
        -- buff given is the avenging wrath buff, so copy its flags.
        {
            name='Wake of Ashes',
            buttonPress=true,
            isBuff=true,
			id=255937,
            iconId=1112939,
			cooldown=30,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
        },
        {
            name='Avenging Crusader',
            buttonPress=true,
            isBuff=true,
			id=216331,
            iconId=589117,
			cooldown=60,
			duration=15,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
        },
		{
			name="Avenging Wrath",
            buttonPress=true,
            isBuff=true,
			id=31884,
            iconId=135875,
			cooldown=120,
			duration=20,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
		{
			name="Ardent Defender",
            buttonPress=true,
            isBuff=true,
			id=31850,
            iconId=135870,
			cooldown=90,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true, bigFlag=true, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
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
			charges=1,
			cdr=false,
            importantFlag=false, bigFlag=true, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
		-- GoAK from cheat death talent
		{
			name="Gift of the Golden Valkyr",
            buttonPress=false,    -- does not require the player to press a button, don't check cast history
            isBuff=false,
			id=393108,
            iconId=1349535,   -- blizzard shows the GoAK icon on bigdefensives. show the talent instead
			cooldown=45,
			duration=4,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            -- match GoAK - cheat death procs a shorter GoAK that is not flagged BIG_DEFENSIVE
            importantFlag=false, bigFlag=true, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=true,
            certainOnFirstInference=true
		},
		{
			name="Blessing of Spellwarding",
            buttonPress=true,
            isBuff=true,
			id=204018,
            iconId=135880,
			cooldown=300,
			duration=10,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true, bigFlag=false, externalFlag=true, raidFlag=true, raidInCombatFlag=false,
			external=ns.EXTERNAL_ANY,
            concurrentDebuff=false,  -- applies forbearance, but the debuff isn't in the same payload ON OTHERS
            certainOnFirstInference=true
		},
		{
			name="Sentinel",
            buttonPress=true,
            isBuff=true,
			id=389539,
            iconId=135922,
			cooldown=120,
			duration=16,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
	},


	----------------------------------------------------------------------------------------
    ["PRIEST"] = {
		{
			name="Desperate Prayer",
            buttonPress=true,
            isBuff=true,
			id=19236,
            iconId=237550,
			cooldown=70,   -- talent: 90>70
			duration=10,   -- optional oracle hero talent gives +10s 
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true, bigFlag=true, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
		{
			name="Pain Suppression",
            buttonPress=true,
            isBuff=true,
			id=33206,
            iconId=135936,
			cooldown=180,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=2,    -- talent +1 charge also gives -3s CD per PW:shield cast
			cdr=true,
            importantFlag=false, bigFlag=true, externalFlag=true, raidFlag=true, raidInCombatFlag=true,
			external=ns.EXTERNAL_ANY,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
        -- Divine Hymn creates multiple buffs. The one that is flagged such that UNIT_AURA
        -- would detect it (flag=10000) is the channel, which I think has a 4.5s base
        -- cast time but is affected by haste.
		{
			name="Divine Hymn",
            buttonPress=true,
            isBuff=true,
			id=64843,
            iconId=237540,
			cooldown=120,   -- talent: 180>120
			duration=5,     -- this is the cast (channel) time of divine hymn. cancelled as usual
			duration_variable=ns.DURATION_LTE,
			charges=1,
			cdr=false,
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
		{
			name="Guardian Spirit",
            buttonPress=true,
            isBuff=true,
			id=47788,
            iconId=237542,
			cooldown=180,
			duration=12,    -- 10 base +2s hero (orcale, mandatory) talent
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=true,       -- talent: -60s on CD if the target dies. should rarely trigger
            importantFlag=false, bigFlag=false, externalFlag=true, raidFlag=true, raidInCombatFlag=true,
			external=ns.EXTERNAL_ANY,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
		{
			name="Voidform",
            buttonPress=true,
            isBuff=true,
			id=228260,
            iconId=1386548,
			cooldown=120,
			duration=20,
            -- also a hero talent that adds dynamic duration
			duration_variable=ns.DURATION_GTE,  -- talent: +3s dur dynamic per cast of SW: madness
			charges=1,
			cdr=false,
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		}
	},


	----------------------------------------------------------------------------------------
    ["ROGUE"] = {
		{
			name="Cloak of Shadows",
            buttonPress=true,
            isBuff=true,
			id=31224,
            iconId=136177,
			cooldown=120,   -- talent: 120 > 90
			duration=5,     -- hero talent: 5 > 7
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=false, bigFlag=true, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
		{
			name="Evasion",
            buttonPress=true,
            isBuff=true,
			id=5277,
            iconId=136205,
			cooldown=120,
			duration=10,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
        -- XXX: TODO: adrenaline rush has a weird application where it both adds and updates
        -- itself in the same UNIT_AURA event. should allow instant ID.
        -- also adrenaline rush can be reset with preparation. since there is no CDR for
        -- rush, could infer prep was used if rush is used again before CD is up.
		{
			name="Adrenaline Rush",
            buttonPress=true,
            isBuff=true,
			id=13750,
            iconId=136206,
			cooldown=180,
			duration=19,   -- talent: 15 > 19 (+4s)
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
        -- XXX: TODO: switches to stealth bar, so maybe there's some updated character
        -- state that can be used to guess dance?
        -- also: causes several dance-specific buffs: symbolic victory (457167), danse macabre (393969), 
        -- master of shadows (196980, not dance-specific), fade to nothing (386237, not dance-specific)
        -- could add logic layer that says at least 3 buffs total?
		{
			name="Shadow Dance",
            buttonPress=true,
            isBuff=true,
			id=185313,
            iconId=236279,
			cooldown=20,
			duration=7.2,
			duration_variable=ns.DURATION_FIXED,
			charges=2,
			cdr=false,
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
        -- XXX: TODO: to differentiate from dance, blades doesn't apply any other auras in the same event, 
		{
			name="Shadow Blades",
            buttonPress=true,
            isBuff=true,
			id=121471,
            iconId=376022,
			cooldown=90,
			duration=16,
			duration_variable=ns.DURATION_FIXED,
			charges=2,
			cdr=false,
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
	},


	----------------------------------------------------------------------------------------
    ["SHAMAN"] = {
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
            importantFlag=true, bigFlag=true, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
        -- XXX: TODO: marked as important, but no event fires when it's used
        -- have to choose between healing tide and ascendance
		-- {
			-- name="Healing Tide Totem",
            -- buttonPress=true,
            -- isBuff=true,
			-- id=108280,
            -- iconId=538569,
			-- cooldown=120,   -- talent: 180 > 120
			-- duration=10,
			-- duration_variable=ns.DURATION_FIXED,
			-- charges=1,
			-- cdr=false,
            -- importantFlag=true, bigFlag=true, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			-- external=ns.NOT_EXTERNAL,
            -- concurrentDebuff=false,
            -- certainOnFirstInference=true
		-- },
	},


	----------------------------------------------------------------------------------------
    ["WARLOCK"] = {
		{
			name="Unending Resolve",
            buttonPress=true,
            isBuff=true,
			id=104773,
            iconId=136150,
			cooldown=135,   -- talent: 180 > 135
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true, bigFlag=true, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
        -- marked as IMPORTANT but fires no UNIT_AURA
		-- {
			-- name="Summon Demon Tyrant",
            -- buttonPress=true,
            -- isBuff=true,
			-- id=265187,
            -- iconId=2065628,
			-- cooldown=60,
			-- duration=20,   -- talent: 15>20
			-- duration_variable=ns.DURATION_FIXED,
			-- charges=1,
			-- cdr=false,
            -- importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			-- external=ns.NOT_EXTERNAL,
            -- concurrentDebuff=false,
            -- certainOnFirstInference=true
		-- },
	},


	----------------------------------------------------------------------------------------
    ["WARRIOR"] = {
		{
			name="Die by the Sword",
            buttonPress=true,
            isBuff=true,
			id=118038,
            iconId=132336,
			cooldown=108,   -- talent: 120 > 108
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true, bigFlag=true, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
        -- XXX: TODO: heavily modified by mountain thane hero spec (dur extension, random procs)
        -- proc support needs a separate isBuff=false entry
        -- for mountain thane, also applies thunder blast, could be used to distinguish from
        -- enraged regen
		{
			name="Avatar",
            buttonPress=true,
            isBuff=true,
			id=107574,
            iconId=613534,
			cooldown=90,
			duration=20,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=true,
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
        -- no extra auras with enraged regen
		{
			name="Enraged Regeneration",
            buttonPress=true,
            isBuff=true,
			id=184364,
            iconId=132345,
			cooldown=108,    -- talent: 120>108 (-10%)
			duration=8,      -- talent: +3s 8>11
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            importantFlag=true, bigFlag=false, externalFlag=false, raidFlag=false, raidInCombatFlag=false,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
		},
        -- There are so many talents that affect shield wall
        -- last stand talent adds a concurrent buff to shield wall. could be useful
        {
			name="Shield Wall",
            buttonPress=true,
            isBuff=true,
			id=871,
            iconId=132362,
			cooldown=108,   -- base 180: talent 1: -10%, talent 2: -60s. seems -10% applies after -60s
			duration=8,     -- luckily duration is never affected
			duration_variable=ns.DURATION_FIXED,
			charges=2,      -- +1 charge talent (same as -60s CD talent)
			cdr=true,       -- talent 1: 20 rage=1s, talent 2: shield slam=6s
            importantFlag=true, bigFlag=true, externalFlag=false, raidFlag=false, raidInCombatFlag=true,
			external=ns.NOT_EXTERNAL,
            concurrentDebuff=false,
            certainOnFirstInference=true
        },
        -- XXX: TODO: recklessness is listed as important but generates no UNIT_AURA event
	},
}
