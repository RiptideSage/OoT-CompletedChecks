# OoT-CompletedChecks
This script reads the save file RAM directly from BizHawk to see what checks have been completed in an Ocarina of Time randomizer run.

# How to Run
- Open the Lua Console in the BizHawk emulator
- Open the script
- Double click the script to run

All remaining checks will print in the console output. 
This will freeze the game while printing (~1 second)

# Runs On
- OoT Rando V6.0
- BizHawk V2.3, V2.9

# Currently Supports
- Shop-sanity
- Key-sanity
- Skull-sanity
- Scrub-sanity
- Cow-sanity
- Song-sanity
- Shuffle in checks for: Magic beans, giant's knife, and carpet salesman

# Quirks
- Some flags in the save file are not updated as they happen in the game. Changing scenes or saving the game finalizes all check updates.
- Randomizer logic may expect players to get items from the "common" shop slots that sell deku sticks, tunics, etc. or from the bombchu bowling alley's bomchu drops. Since these items set no flags they are not listed in this checker.
- During the test playthrough no unique flag could be found for the Shadow Medallion cutscene. Currently the Bongo-Bongo heart container check is used as an approximation.
- If "Shuffle Songs" is set to "Song Locations" Sun's Song check doesn't set a flag and instead checks the quest status for the song it drops. Currently the checker does not support the Sun's Song check for "Song Locations".