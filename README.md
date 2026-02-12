# PetesDefensiveHistory

Tracks cooldowns for Blizzard's "Center Big Defensive Buffs".

Which cooldown has been used is guessed based on the small number of buffs that Blizzard marks BIG_DEFENSIVE and additional logic about how those buffs work. Since no unsecreting explots are used, tracking cannot be 100% accurate and depends on the group composition. External defensives like Ironbark and Blessing of Sacrifice make the cooldown inference problem depend on the group composition. There are many limitations to the accuracy of the cooldown identification logic and there are still more ways to improve guessing.

STILL A WORK IN PROGRESS. Most notably, support to automatically identify talents that change cooldown length, buff duration or number of charges.

### Fallback mode when cooldown is ambiguous
The default mode: when a big cooldown is used, keep the icon around (without knowing what it is) and attach a timer that counts up. Requires the player to know the cooldown of the ability (e.g., when the Barkskin timer hits 60, the ability is off cooldown).

To reduce clutter, the timer is removed when the longest possible cooldown across all abilities that could be present on that player is reached.

![](fallback_behavior.png)


### OmniCD-like tracking when cooldown can be accurately guessed
In some cases, the ability used can be guessed. For example, if the group has no external defensives and a spec has only one ability X that is classified as a BIG_DEFENSIVE, then any time a big defensive buff is shown it must be ability X.

![](cooldowns_tracked.png)

### Group-wide solving which abilities can always be uniquely identified
Use `/pdh` to get a panel showing all of the BIG_DEFENSIVEs in the group and which characters are valid targets. Greyed out icons are abilities that cannot *always* be accurately inferred.

![](group_solutions_UI.png)
