# PetesDefensiveHistory

**WHILE MOSTLY FUNCTIONAL, THIS ADDON IS STILL UNDER ACTIVE DEVELOPMENT. EXPECT SOME BUGS AND INCONVENIENCES.**

Tracks cooldowns for Blizzard-approved `IMPORTANT`, `BIG_DEFENSIVE` and `EXTERNAL` buffs.
When identified, active cooldowns are glowed and cooldown timers are shown. Text-To-Speech (TTS) announcements are also supported. Buffs that cannot be identified are instead displayed on a second row similar to a GCD history tracker. These buffs display a "count-up" timer that indicates how much time has passed since that (unidentified) buff was applied.

PetesDefensiveHistory uses a flexible inference engine to identify abilities through several lines of evidence. Many abilities can be detected immediately on cast. In future versions, more abilities will be added.

* Tracks 61 offensive and defensive cooldowns.
* Detects talents and hero specs.
* Text-to-Speech (TTS) ability announcer.
* Supports DandersFrames and Blizzard default frames.
* Data exporter and log analyzer to measure inference accuracy using combat logs as a truth source.
* Designed for Mythic+ but can work for allies in arena and in raids. Support may come in a future update.
* 

Layout options are currently limited, mimicking OmniCD layouts with cooldowns to the left of party frames. **Would love to integrate the inference engine with a UI-focused addon. Please contact me if interested!**

# Limitations
* **Tracking is not 100% accurate.** Which cooldown has been used is guessed based on the small number of Blizzard marked buffs and some additional logic about who those buffs can be cast by and applied to. This addon does not rely on exploits in which secret spell IDs are inadvertently leaked.
* **Tracking only works for players with LibSpecialization.** LibSpecialization is included in this addon as well as many common addons such as BigWigs. For players without LibSpecialization, all buffs will be sent to the history tracker (i.e., treated as unidentified).
* **Dynamic cooldown reduction cannot be tracked.** While static cooldown reduction from talents (e.g., cooldown reduced by 60s) is handled, dynamic cooldown reduction (CDR)--e.g., the cooldown of Shield Wall is reduced by 6s when you use Shield Slam--cannot generally be tracked. Timers for abilities with both CDR and multiple charges are especially inaccurate since the second charge can only begin cooling down once the first charge completes. These ability trackers are displayed with a (!) badge and can be disabled if desired.

# Known bugs
There are several known bugs. Here are a few in no particular order:
* Avatar, Guardian of Ancient Kings, and VDH (tank) Metamorphosis inference is currently inaccurate, but is solvable.
* Changes to party sort order aren't detected, so trackers will not follow the sorting. A `/reload` will fix the issue.
* Cooldown tracker states are lost on `/reload` or if a player leaves the group.
* VDH meta is currently bugged in WoW: the cheat death proc also puts meta on cooldown if it is available. This bug will be added to the addon if it continues to exist for much longer.


### History tray fallback mode when cooldown is ambiguous
The default mode: when a big cooldown is used, keep the icon around (without knowing what it is) and attach a timer that counts up. Similar to a GCD tracker - is useful if the player knows the cooldown of the ability.

To reduce clutter, the count-up timer is removed when the longest possible cooldown across all abilities that could be present on that player is reached.

![](images/fallback_behavior.png)


### Cooldown tracking when ability can be guessed
In some cases, the ability used can be guessed. For example, if the group has no external defensives and a spec has only one ability X that is classified as a BIG_DEFENSIVE, then any time a big defensive buff is shown it must be ability X.

![](images/cooldowns_tracked.png)

### Group-wide solving which abilities can always be uniquely identified
Use `/pdh` to show which group members are valid targets for each ability in the group. Abilities that can always be guessed are colored, greyed out abilities can only sometimes be guessed.

![](images/group_solutions_UI.png)
