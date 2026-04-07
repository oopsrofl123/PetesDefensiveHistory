# PetesDefensiveHistory

**WHILE MOSTLY FUNCTIONAL, THIS ADDON IS STILL UNDER ACTIVE DEVELOPMENT. EXPECT SOME BUGS, INCONVENIENCES AND /reloads.**


[![Join Discord](https://img.shields.io/badge/Discord-Join%20Server-5865F2?logo=discord&logoColor=white)](https://discord.gg/gVCtQrvpxt) Help by reporting bugs and sharing logic export strings and combat logs!

Tracks cooldowns for Blizzard-approved `IMPORTANT`, `BIG_DEFENSIVE` and `EXTERNAL` buffs.
When identified, active cooldowns are glowed and cooldown timers are shown. Text-To-Speech (TTS) announcements are also supported. Buffs that cannot be identified are instead displayed on a second row similar to a GCD history tracker. These buffs display a "count-up" timer that indicates how much time has passed since that (unidentified) buff was applied.

PetesDefensiveHistory uses a flexible inference engine to identify abilities through several lines of evidence. Many abilities can be detected immediately on cast. In future versions, more abilities will be added.

* Tracks 76 offensive and defensive cooldowns.
* Detects talents and hero specs.
* Text-to-Speech (TTS) ability announcer.
* Supports icon skinning with **Masque**.
* Data exporter and log analyzer to measure inference accuracy using combat logs as a truth source.
* Designed for Mythic+ but future updates will add support for raids and allies in arena.
* Supports the following group frames:
  * Blizzard default frames
  * Cell
  * DandersFrames
  * ElvUI
  * EnhanceQoL
  * Grid2
  * VuhDo

**Would love to integrate the inference engine with a UI-focused addon. Please contact me if interested!**

![](images/PDH1.gif)

# Frequently asked questions
PetesDefensiveHistory might look like OmniCD, but Blizzard's addon restrictions make detecting cooldowns a messy process. There are a few important things to understand about how this AddOn works and its limitations!

# 1. Why do some players have no cooldown trackers?
* This AddOn uses LibSpecialization to retrieve the talents of your teammates. Players without LibSpecialization will not have a cooldown tracker. Talents can change the cooldown timers by several minutes!
* LibSpecialization communicates your talents to your groupmates. Many players have it installed without knowing - for example, BigWigs (and PetesDefensiveHistory!) both bundle it.
* Talents are necessary to know (a) what abilities someone has and (b) what their cooldowns are.
* Players without LibSpecialization *will have no cooldown icons next to their frames*!

![](images/NoLibSpec2.png)
*The mage does not have LibSpecialization*


# 2. What is the second row of icons?
* The second row of icons contains cooldowns **that could not be guessed by the addon**.
* The second row is called the **history tray** and is like a GCD tracker for unidentified cooldowns.
* The history tray **counts up** from the time the buff was applied. If you know the cooldown of the ability, then you can know when it is available even when the AddOn fails.

![](images/HistoryTray.png)
*Freedom could not be guessed on the druid*

* Turn off the history tray with this option:
![](images/DisableHistoryTray.png)

# 3. Why is there a (!) on my cooldown tracker?
* Dynamic cooldown reduction (like *the cooldown of Shield Wall is reduced by 6s when you
  use Shield Slam*) cannot be detected with Blizzard's new restrictions.
* (!) badges mark the cooldown trackers that are affected by dynamic cooldown reduction and
  thus will be inaccurate. Those trackers instead reflect the **longest possible cooldown**.

![](images/CDRBadge.png)
*Guardian of Ancient Kings has dynamic cooldown reduction, and is therefore inaccurate*

* Turn off the badges with this option:
![](images/DisableBadges.png)



# 4. Why do abilities sometimes start glowing long after they're cast?
* Some abilities are hard to distinguish from others. PetesDefensiveHistory continuously collects
  data about each ability and only glows the cooldown when it has enough information to be
  certain that its guess is correct.
* When cooldowns are predicted more than 1.5s from the time they were used, Text-to-speech does
  not announce the cooldown.


# 5. Complicated things happen!
* Players without LibSpecialization can cause unexpected things. For example, if someone without LibSpec uses an external defensive, an icon will be added to the **target's history tray**.

![](images/no_libspec_consequences.png)
*Life Cocoon was cast on the Paladin by a Monk without LibSpec*




# Limitations
* **Tracking is not 100% accurate.** Which cooldown has been used is guessed based on the
  small number of Blizzard marked buffs and some additional logic about who those buffs
  can be cast by and applied to. This addon does not rely on exploits in which secret spell
  IDs are inadvertently leaked.
* **Only abilities flagged by Blizzard can be tracked.** In very rare cases, an ability not
  flagged by Blizzard can be guessed accurately, but we are mostly restricted to just the
  flagged abilities. Blizzard continues to change which abilities are flagged.
* **Tracking only works for players with LibSpecialization.** LibSpecialization is
  included in this addon as well as many common addons such as BigWigs. For players
  without LibSpecialization, all buffs will be sent to the history tracker (i.e., treated
  as unidentified).
* **Dynamic cooldown reduction cannot be tracked.** While static
  cooldown reduction from talents (e.g., cooldown reduced by 60s) is handled, dynamic
  cooldown reduction (CDR)--e.g., the cooldown of Shield Wall is reduced by 6s when you
  use Shield Slam--cannot generally be tracked.  Timers for abilities with both CDR and
  multiple charges are especially inaccurate since the second charge can only begin
  cooling down once the first charge completes. These ability trackers are displayed with
  a (!) badge and can be disabled if desired.
* **Shadowmeld, Vanish and Greater Invis are only detectable when dropping combat!** 
  If used, e.g., when standing in a city, the ability will not be detected.
  * **Combat drops also do not work on target dummies** Dummies prevent combat drops when
    too close (~10 yards).  Walk 20-30yd from the dummy to avoid this.
* **Stoneform is only detectable when it dispels a debuff!** If used only for the physical
  damage reduction, it will **not** be detected.


# Known bugs
There are several known bugs. Unlike *limitations*, which are permanent,
these bugs will be fixed in upcoming releases. Here are a few in no
particular order:
* **Combat drops fail to identify.** Shadowmeld, Feign
  Death, Greater Invis, and Vanish are being missed more often than they should be.
* **Group members without LibSpec can cause wacky results on players with LibSpec!** If a
  group member without LibSpec uses an ability that would be tracked, the addon will still
  try to guess that ability. But because that member didn't have LibSpec, they won't have
  any valid abilities to assign the use to. Instead, the addon will try to assign the use
  to a valid ability it does know about. This will always be an external cooldown on
  another player. Blessing of Freedom is often chosen. This is completely fixable by
  ensuring your entire group has PetesDefensiveHistory or LibSpecialization or any addon
  that embeds LibSpecialization (BigWigs does and WeakAuras used to do this). When you
  can't force your groups to have an addon with LibSpecialization, this will be mostly
  fixed by adding a default ability set for each spec. This will work better for specs
  where the base abilities are near-guaranteed (e.g., Pain Suppression on a disc priest)
  than specs with more optional talents (e.g., Blessing of Protection on a ret paladin).
* Avatar, Guardian of Ancient Kings, and VDH (tank) Metamorphosis inference is currently
  inaccurate, but is solvable.
* Changes to party sort order aren't detected, so trackers will not follow the sorting.
  For example, if you change your party sort order in the default Blizzard frames through
  edit mode the attached trackers will not follow. A `/reload` will fix the issue.
* Cooldown tracker states are lost on `/reload` or if a player leaves the group.
* VDH meta is currently bugged in WoW: the cheat death proc also puts meta on cooldown if
  it is available. This bug will be added to the addon if it continues to exist for much
  longer.
