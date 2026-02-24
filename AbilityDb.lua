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
ns.TARGET_SELF = 0
ns.TARGET_OTHERS = 1
ns.TARGET_ANY = 2


-- The unique key in this database is spell ID. It is structured by class, not by spec.
-- The class names are the locale-indepedent names that are used to key many internal
-- WoW tables.
ns.AbilityDb = {
	----------------------------------------------------------------------------------------
    ["DEATHKNIGHT"] = {
		{
			name="Anti-Magic Shell",
            buttonPress=true,
			id=48707,
            iconId=136120,
			cooldown=60,
			duration=5,
			duration_variable=ns.DURATION_LTE,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=true, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
		{
			name="Icebound Fortitude",
            buttonPress=true,
			id=48792,
            iconId=237525,
			cooldown=120,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=true, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
		{
			name="Vampiric Blood",
            buttonPress=true,
			id=55233,
            iconId=136168,
			cooldown=90,
			duration=10,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,   -- talent CDR
            IMPORTANT=true, BIG=true, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            -- adds Coagulating Blood (id=463730), which is not harmful but is
            -- not returned by the aura filter HELPFUL
            requireConcurrentBuff=false,
            concurrentDebuff=true,
		},
		{
			name="Pillar of Frost",
            buttonPress=true,
			id=51271,
            iconId=458718,
			cooldown=45,
			duration=12,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
	},

	----------------------------------------------------------------------------------------
    ["DEMONHUNTER"] = {
		{
			name="Blur",
            buttonPress=true,
			id=198589,
            iconId=1305150,
			cooldown=60,
			duration=10,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=true, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
        -- VDH meta is a different spell from Havoc (191427) and Devourer (void meta - 1217605).
        -- Only the VDH version is flagged IMPORTANT.
        -- The apex talent for vengeance makes it impossible to know whether a proc was used
        -- to get a meta buff or if the actual cooldown as used.
		{
			name="Metamorphosis",
            buttonPress=true,
			id=187827,
            iconId=1247263,
			cooldown=120,
			duration=15,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
        -- Cheat death from meta. Gives a full duration meta, so only way to differentiate
        -- is through concurrent debuff (Uncontained Fel, spellID=209261),
		{
			name="Last Resort",
            -- any meta that happens without a button press is cheat death
            buttonPress=false,
			id=209258,
            iconId=1348655,
			cooldown=480,
			duration=15,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=true,
		},
        -- Apex talent: allows meta to be cast but it only lasts 10s. So we can't ever
        -- know which meta is cast (and whether it incurred a cooldown) until after the
        -- buff completes.
		{
			name="Untethered Rage",
            buttonPress=true,
			id=1270444,
            iconId=7636527,
			cooldown=1,
			duration=10,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false
		},
		{
			name="Fiery Brand",
            buttonPress=true,
			id=204021,
            iconId=1344647,
			cooldown=60,
			duration=12,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=false, BIG=true, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
	},


	----------------------------------------------------------------------------------------
    ["DRUID"] = {
		{
			name="Barkskin",
            buttonPress=true,
			id=22812,
            iconId=136097,
			cooldown=60,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=true, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
		{
			name="Celestial Alignment",
            buttonPress=true,
			--id=383410,  -- this is the celestial alignment buff in-game
            id=194223,
            iconId=136060,
			cooldown=180,
			duration=15,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,  -- there is a weird CDR hero talent in hero talents keeper of the grove
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
		{
			name="Incarnation: Chosen of Elune",
            buttonPress=true,
			id=102560,
            --id=390414   -- this is the in-game incarn buff spell ID
            iconId=571586,
			cooldown=180,
			duration=20,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
        -- Feral berserk
		{
			name="Berserk",
            buttonPress=true,
            id=106951,
            iconId=236149,
			cooldown=180,
			duration=15,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
        },
		{
			name="Incarnation: Avatar of Ashamane",
            buttonPress=true,
			id=102543,
            iconId=571586,
			cooldown=180,
			duration=20,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
        -- Guardian berserk
		{
			name="Berserk",
            buttonPress=true,
            id=50334,
            iconId=236149,
			cooldown=180,
			duration=15,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
        },
		{
			name="Incarnation: Guardian of Ursoc",
            buttonPress=true,
			id=102558,
            iconId=571586,
			cooldown=180,
			duration=30,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
        -- there is a spell called Survival Insticts marked as BIG_DEFENSIVE, but it's
        -- the wrong spell ID (=50322), so it is not tracked.
		-- {
			-- name="Survival Instincts",
            -- buttonPress=true,
			-- id=61336,
            -- iconId=236169,
			-- cooldown=180,
			-- duration=6,
			-- duration_variable=ns.DURATION_FIXED,
			-- charges=2,
			-- cdr=false,
            -- IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			-- targets=ns.TARGET_SELF,
            -- concurrentDebuff=false,
		-- }
		{
			name="Ironbark",
            buttonPress=true,
			id=102342,
            iconId=572025,
			cooldown=90,
			duration=12,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=false, BIG=true, EXTERNAL=true, RAID=true, RAIDINCOMBAT=true,
			targets=ns.TARGET_ANY,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
	},

	----------------------------------------------------------------------------------------
    ["EVOKER"] = {
		{
			name="Dragonrage",
            buttonPress=true,
			id=375087,
            iconId=4622452,
			cooldown=120,
			duration=18,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
        -- hero talent: applies to your target or a random nearby injured ally at 50%.
        -- turns scales into an external.
        -- XXX: TODO: however, the external buff is not imp|big|external flagged, so it
        -- doesn't trigger inference.
		{
			name="Obsidian Scales",
            buttonPress=true,
			id=363916,
            iconId=1394891,
			cooldown=90,
			duration=12,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=true, EXTERNAL=false, RAID=true, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
		{
			name="Time Dilation",
            buttonPress=true,
			id=357170,
            iconId=4622478,
			cooldown=60,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=false, BIG=true, EXTERNAL=true, RAID=true, RAIDINCOMBAT=true,
			targets=ns.TARGET_ANY,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
	},
	
	----------------------------------------------------------------------------------------
    ["HUNTER"] = {
		{
			name="Survival of the Fittest",
            buttonPress=true,
			id=264735,
            iconId=136094,
			cooldown=90,
			duration=6,                -- talent: 6 > 8
			duration_variable=ns.DURATION_FIXED,
			charges=1,                 -- talent: 2 charges
			cdr=false,
            IMPORTANT=true, BIG=true, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
		{
			name="Trueshot",
            buttonPress=true,
			id=288613,
            iconId=132329,
			cooldown=120,
			duration=15,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
        -- Although marked IMPORTANT, exhilaration isn't a buff. It causes a short
        -- HoT buff if talented, but that HoT is not important. Haven't figured out
        -- a way to detect when Exhil is cast yet.
		-- {
			-- name="Exhilaration"
            -- buttonPress=true,
			-- id=109304,
            -- iconId=461117,
			-- cooldown=60,   -- talent: 2pts -60s
			-- duration=12,
			-- duration_variable=ns.DURATION_FIXED,
			-- charges=1,
			-- cdr=false,
            -- IMPORTANT=true, BIG=true, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			-- targets=ns.TARGET_SELF,
            -- concurrentDebuff=false,
		-- },
	},


	----------------------------------------------------------------------------------------
    ["MAGE"] = {
        -- XXX: TODO: arcane surge always triggers the arcane missiles buff. this is
        -- slightly different from other cases because you can get the arcane missiles
        -- buff in other ways, so this is an add OR update buff situation.
        -- important to disambiguate this one because it can't be distinguished from
        -- mirror images by duration.
		{
			name="Arcane Surge",
            buttonPress=true,
			id=365350,
            iconId=4667417,
			cooldown=90,
			duration=15,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
        -- XXX: use cancellation to help detect?
		{
			name="Ice Block",
            buttonPress=true,
			id=45438,
            iconId=135841,
			cooldown=240,
			duration=10,
			duration_variable=ns.DURATION_LTE,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=true, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=true,
        },
		-- XXX: any way to use hypothermia as extra info?
		{
			name="Ice Cold",
            buttonPress=true,
			id=414659,
            iconId=135777,
			cooldown=240,
			duration=6,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=true, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=true,
		},
		{
			name="Mirror Image",
            buttonPress=true,
			id=55342,
            iconId=135994,
			cooldown=120,
			duration=15,
			duration_variable=ns.DURATION_LTE,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
		{
			name="Alter Time",
            buttonPress=true,
			id=342245,
            iconId=609811,
			cooldown=50,   -- hero talent -40s 50>40
			duration=10,
			duration_variable=ns.DURATION_LTE,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=true, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
		{
			name="Combustion",
            buttonPress=true,
			id=190319,
            iconId=135824,
			cooldown=120,
			duration=12,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
	},


	----------------------------------------------------------------------------------------
    ["MONK"] = {
        -- XXX: TODO: buff in-game is not imp or big flagged, so not observable
		-- {
	   	    -- name="Fortifying Brew",
            -- buttonPress=true,
			-- id=115203,
            -- iconId=615341,
		    -- cooldown=360   -- talent: 360 > 240 base is really 6min for brew
			-- duration=15,
			-- duration_variable=ns.DURATION_FIXED,
			-- charges=1,
			-- cdr=false,
            -- IMPORTANT=true, BIG=true, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			-- targets=ns.TARGET_SELF,
            -- concurrentDebuff=false,
		-- },
        {
			name="Life Cocoon",
            buttonPress=true,
			id=116849,
            iconId=627485,
			cooldown=120,
			duration=12,
			duration_variable=ns.DURATION_LTE,
			charges=1,
			cdr=false,
            IMPORTANT=false, BIG=false, EXTERNAL=true, RAID=true, RAIDINCOMBAT=true,
			targets=ns.TARGET_ANY,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
	},

	----------------------------------------------------------------------------------------
    ["PALADIN"] = {
		{
			name="Blessing of Sacrifice",
            buttonPress=true,
			id=6940,
            iconId=135966,
			cooldown=120,
			duration=12,
			duration_variable=ns.DURATION_LTE,   -- cancels if caster falls < 20% health
			charges=1,
			cdr=false,
            IMPORTANT=false, BIG=true, EXTERNAL=true, RAID=true, RAIDINCOMBAT=true,
			targets=ns.TARGET_OTHERS,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
		{
			name="Divine Protection",
            buttonPress=true,
			id=498,
            iconId=524353,
			cooldown=60,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
        ---------------------------------------------------------------------------------------
        -- Forbearance spells
        ---------------------------------------------------------------------------------------
        -- The required application of forbearance helps to identify these abilities.
        -- However, whether the UNIT_AURA event contains both the buff and the FB
        -- debuff is complicated. I have observed:
        --      * Bubble self-cast, buff and FB in same event
        --      * Bubble self-cast, buff and FB in different events (2/5+1 casts)
        --          - maybe this is only possible with the cast-bubble-with-FB talent?
        --      * Bubble self-cast, FB already active, buff and FB(udpate) in different events
        --      * Spellwarding self-cast, buff and DB in same event (9+1/9+1 casts)
		{
			name="Divine Shield",
            buttonPress=true,
			id=642,
            iconId=524354,
			cooldown=300,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,  -- Talent allows bubble with FB active, refreshes it to 20s
            concurrentDebuff=true,
		},
		{
			name="Blessing of Protection",
            buttonPress=true,
			id=1022,
            iconId=135964,
			cooldown=300,
			duration=10,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=false, BIG=false, EXTERNAL=true, RAID=true, RAIDINCOMBAT=true,
			targets=ns.TARGET_ANY,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
		{
			name="Blessing of Spellwarding",
            buttonPress=true,
			id=204018,
            iconId=135880,
			cooldown=300,
			duration=10,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=true, RAID=true, RAIDINCOMBAT=false,
			targets=ns.TARGET_ANY,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
        ---------------------------------------------------------------------------------------
        -- END Forbearance spells
        ---------------------------------------------------------------------------------------
		{
			name="Blessing of Freedom",
            buttonPress=true,
			id=1044,
            iconId=135968,
			cooldown=25,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=true, RAIDINCOMBAT=false,
			targets=ns.TARGET_ANY,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
        -- Ret talent removes wings and attaches it to wake of ashes. The
        -- buff given is the avenging wrath buff, so copy its flags.
        {
            name='Wake of Ashes',
            buttonPress=true,
			id=255937,
            iconId=1112939,
			cooldown=30,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
        },
        {
            name='Avenging Crusader',
            buttonPress=true,
			id=216331,
            iconId=589117,
			cooldown=60,
			duration=15,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
        },
		{
			name="Avenging Wrath",
            buttonPress=true,
			id=31884,
            iconId=135875,
			cooldown=120,
			duration=20,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
		{
			name="Ardent Defender",
            buttonPress=true,
			id=31850,
            iconId=135870,
			cooldown=90,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=true, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
		{
			name="Guardian of Ancient Kings",
            buttonPress=true,
			id=86659,
            iconId=135919,
			cooldown=180,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=false, BIG=true, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
		-- GoAK from cheat death talent
		{
			name="Gift of the Golden Valkyr",
            buttonPress=false,    -- does not require the player to press a button, don't check cast history
			id=393108,
            iconId=1349535,   -- blizzard shows the GoAK icon on bigdefensives. show the talent instead
			cooldown=45,
			duration=4,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            -- match GoAK - cheat death procs a shorter GoAK that is not flagged BIG_DEFENSIVE
            IMPORTANT=false, BIG=true, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=true,
		},
		{
			name="Sentinel",
            buttonPress=true,
			id=389539,
            iconId=135922,
			cooldown=120,
			duration=16,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
	},


	----------------------------------------------------------------------------------------
    ["PRIEST"] = {
		{
			name="Desperate Prayer",
            buttonPress=true,
			id=19236,
            iconId=237550,
			cooldown=90,
			duration=10,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=true, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
		{
			name="Pain Suppression",
            buttonPress=true,
			id=33206,
            iconId=135936,
			cooldown=180,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=false, BIG=true, EXTERNAL=true, RAID=true, RAIDINCOMBAT=true,
			targets=ns.TARGET_ANY,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
        -- Divine Hymn creates multiple buffs. The one that is flagged such that UNIT_AURA
        -- would detect it (flag=10000) is the channel, which I think has a 4.5s base
        -- cast time but is affected by haste.
		{
			name="Divine Hymn",
            buttonPress=true,
			id=64843,
            iconId=237540,
			cooldown=180,
			duration=5,    -- the channel time of divine hymn. cancels will be common
			duration_variable=ns.DURATION_LTE,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
		{
			name="Guardian Spirit",
            buttonPress=true,
			id=47788,
            iconId=237542,
			cooldown=180,
			duration=10,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=false, BIG=false, EXTERNAL=true, RAID=true, RAIDINCOMBAT=true,
			targets=ns.TARGET_ANY,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
		{
			name="Voidform",
            buttonPress=true,
			id=228260,
            iconId=1386548,
			cooldown=120,
			duration=20,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		}
	},


	----------------------------------------------------------------------------------------
    ["ROGUE"] = {
		{
			name="Cloak of Shadows",
            buttonPress=true,
			id=31224,
            iconId=136177,
			cooldown=120,
			duration=5,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=false, BIG=true, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
		{
			name="Evasion",
            buttonPress=true,
			id=5277,
            iconId=136205,
			cooldown=120,
			duration=10,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
        -- XXX: TODO: adrenaline rush has a weird application where it both adds and updates
        -- itself in the same UNIT_AURA event. should allow instant ID.
        -- also adrenaline rush can be reset with preparation. since there is no CDR for
        -- rush, could infer prep was used if rush is used again before CD is up.
		{
			name="Adrenaline Rush",
            buttonPress=true,
			id=13750,
            iconId=136206,
			cooldown=180,
			duration=15,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
        -- XXX: TODO: switches to stealth bar, so maybe there's some updated character
        -- state that can be used to guess dance?
        -- also: causes several dance-specific buffs: symbolic victory (457167), danse macabre (393969), 
        -- master of shadows (196980, not dance-specific), fade to nothing (386237, not dance-specific)
        -- could add logic layer that says at least 3 buffs total?
        -- many of those buffs are talents. would need to detect them to count concurrent buffs
		{
			name="Shadow Dance",
            buttonPress=true,
			id=185313,
            iconId=236279,
			cooldown=20,
			duration=6,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=true,
            concurrentDebuff=false,
		},
        -- XXX: TODO: to differentiate from dance, blades doesn't apply any other auras in the same event, 
		{
			name="Shadow Blades",
            buttonPress=true,
			id=121471,
            iconId=376022,
			cooldown=90,
			duration=16,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
	},


	----------------------------------------------------------------------------------------
    ["SHAMAN"] = {
		{
			name="Astral Shift",
            buttonPress=true,
			id=108271,
            iconId=538565,
			cooldown=120,
			duration=12,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=true, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
        -- XXX: TODO: marked as important, but no event fires when it's used
        -- have to choose between healing tide and ascendance
		-- {
			-- name="Healing Tide Totem",
            -- buttonPress=true,
			-- id=108280,
            -- iconId=538569,
			-- cooldown=120,   -- talent: 180 > 120
			-- duration=10,
			-- duration_variable=ns.DURATION_FIXED,
			-- charges=1,
			-- cdr=false,
            -- IMPORTANT=true, BIG=true, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			-- targets=ns.TARGET_SELF,
            -- concurrentDebuff=false,
		-- },
	},


	----------------------------------------------------------------------------------------
    ["WARLOCK"] = {
		{
			name="Unending Resolve",
            buttonPress=true,
			id=104773,
            iconId=136150,
			cooldown=180,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=true, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
        -- marked as IMPORTANT but fires no UNIT_AURA
		-- {
			-- name="Summon Demon Tyrant",
            -- buttonPress=true,
			-- id=265187,
            -- iconId=2065628,
			-- cooldown=60,
			-- duration=20,   -- talent: 15>20
			-- duration_variable=ns.DURATION_FIXED,
			-- charges=1,
			-- cdr=false,
            -- IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			-- targets=ns.TARGET_SELF,
            -- concurrentDebuff=false,
		-- },
        -- XXX: TODO: another IMPORTANT is Summon Darkglare, but as above no UNIT_AURA
	},


	----------------------------------------------------------------------------------------
    ["WARRIOR"] = {
		{
			name="Die by the Sword",
            buttonPress=true,
			id=118038,
            iconId=132336,
			cooldown=120,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=true, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
        -- for mountain thane: applies thunder blast, could be used to distinguish from
        -- enraged regen
		{
			name="Avatar",
            buttonPress=true,
			id=107574,
            iconId=613534,
			cooldown=90,
			duration=20,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
        -- hero talent proc that grants avatar, but does not trigger avatar's CD
        {
			name="Avatar of the Storm",
            buttonPress=true,
			id=437134,
            iconId=432002,
			cooldown=1,
			duration=4,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
        },
		{
			name="Enraged Regeneration",
            buttonPress=true,
			id=184364,
            iconId=132345,
			cooldown=120,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=false, EXTERNAL=false, RAID=false, RAIDINCOMBAT=false,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
		},
        {
			name="Shield Wall",
            buttonPress=true,
			id=871,
            iconId=132362,
			cooldown=180,
			duration=8,
			duration_variable=ns.DURATION_FIXED,
			charges=1,
			cdr=false,
            IMPORTANT=true, BIG=true, EXTERNAL=false, RAID=false, RAIDINCOMBAT=true,
			targets=ns.TARGET_SELF,
            requireConcurrentBuff=false,
            concurrentDebuff=false,
        },
        -- XXX: TODO: recklessness is listed as important but generates no UNIT_AURA event
	},
}
