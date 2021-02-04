-- NOTES
-- This printer isn't directly compatible with MQ

--TODO more toggles based on rando settings
local NUM_BIG_POES_REQIURED = 1

--TODO future commandline / button toggles
local PRINT_COMPLETED_CHECKS = false
local PRINT_MISSING_CHECKS = true

-- The offset constants are all from N64 RAM start. Offsets in the check statements are relative.
local save_context_offset = 0x11A5D0

local scene_flags_offset = save_context_offset + 0x00D4 --0x11A6A4
local skulltula_flags_offset = save_context_offset + 0xE9C --0x11B46C
local event_context_offset = save_context_offset + 0xED4 --0x11B4A4
local item_get_inf_offset = save_context_offset + 0xEF0 --0x11B4C0
local inf_table_offset = save_context_offset + 0xEF8 -- 0x11B4C8

local shop_context_offset = save_context_offset + 0x5B4 --0x11AB84
local fishing_context_offset = save_context_offset + 0xEC0 --0x11B490
local big_poe_points_offset =  save_context_offset + 0xEEC -- 0x11B48C

local equipment_offset = save_context_offset + 0x70 -- 0x11A640

--Used to enable debug printing. Usually this should be: false
local DEBUG = false

local debug = function(message)
    if DEBUG then
        print(message)
    end
end

-- Helper method for item check printing
local print_check_category_header = function(category_name)
    local header_length = 70
    local header_divider_character = '#'
    local left_header_string = string.rep(header_divider_character,(header_length-string.len(category_name))/2)
    local right_header_string = string.rep(header_divider_character,(header_length-string.len(category_name))/2)

    --Rounding errors, correct for more spacing to odd length names
    if(string.len(category_name)%2 == 1)then
        right_header_string = right_header_string..header_divider_character
    end

    print('\r\n'..left_header_string..' '..category_name..' '..right_header_string)
end


-- Helper method for item check printing
local print_check_message = function(check_name, check_completed)
    local justify_check_status = 50
    local space_string = ' '
    local spacer = string.rep(space_string,justify_check_status-string.len(check_name))

    if check_completed then
        if PRINT_COMPLETED_CHECKS then
            print(check_name .. ':'..spacer..'Completed')
        end
    else
        if PRINT_MISSING_CHECKS then
            print(check_name .. ':'..spacer..'Missing')
        end
    end
end


-- Offsets for scenes can be found here
-- https://wiki.cloudmodding.com/oot/Scene_Table/NTSC_1.0
-- Each scene is 0x1c bits long, chests at 0x0, switches at 0x4, collectibles at 0xc
local scene_check = function(scene_offset, bit_to_check, scene_data_offset, check_name)
    local local_scene_offset = scene_flags_offset + (0x1c * scene_offset) + scene_data_offset;
    debug('\r\nLocal scene offset: 0x' .. string.format("%x",local_scene_offset))

    local nearby_memory = mainmemory.read_u32_be(local_scene_offset)
    debug('Local memory block 0x' .. string.format("%x", nearby_memory))

    debug('Checking bit #'..bit_to_check)
    local match = bit.check(nearby_memory,bit_to_check)
    print_check_message(check_name, match)
end


local chest_check = function(scene_offset, bit_to_check, check_name)
    scene_check(scene_offset, bit_to_check, 0x0, check_name)
end

local on_the_ground_check = function(scene_offset, bit_to_check,  check_name)
    scene_check(scene_offset, bit_to_check, 0xC, check_name)
end

--NOTE: Scrubs seem to be stored in the "unused" block of scene memory
local scrub_check = function(scene_offset, bit_to_check, check_name)
    scene_check(scene_offset, bit_to_check, 0x10, check_name)
end

local cow_check = function(scene_offset, bit_to_check,  check_name)
    scene_check(scene_offset, bit_to_check, 0xC, check_name)
end

--NOTE: Possibly in a different scene?
local bean_sale_check = function(scene_offset, bit_to_check,  check_name)
    scene_check(scene_offset, bit_to_check, 0x14, check_name)
end

local great_fairy_magic_check = function(scene_offset,bit_to_check,check_name)
    scene_check(scene_offset, bit_to_check, 0x4, check_name)
end

local membership_card_check = function(scene_offset,bit_to_check,check_name)
    scene_check(scene_offset, bit_to_check, 0x4, check_name)
end

--Helper method to resolve skulltula lookup location
local function skulltula_scene_to_array_index(i)
    return  (i + 3) - 2 * (i % 4)
end

--NOTE: The Rando LocationList offsets are bit masks not locations, so 0x1 -> 0 offset, 0x2 -> 1 offset, 0x4 -> 2 offset, 0x8 -> 3 offset, etc.
--NOTE:  8-bit array, scene_offsets are filled on [0x00,0x15] but use a lookup array above
local skulltula_check = function(scene_offset, bit_to_check, check_name)
    debug('\r\nLocal scene offset: ')

    --For some reason the skulltula array isn't a straight mapping from the scene ID
    scene_offset = skulltula_scene_to_array_index(scene_offset)

    local local_skulltula_offset = skulltula_flags_offset + (scene_offset);
    debug('0x' .. string.format("%x",local_skulltula_offset))

    local nearby_memory = mainmemory.read_u8(local_skulltula_offset)
    debug('Local memory block 0x' .. string.format("%x",nearby_memory))

    debug('Checking bit #'..bit_to_check)
    local match = bit.check(nearby_memory,bit_to_check)
    print_check_message(check_name, match)
end

-- Left shelf bit masks are:
-- 0x8    0x2
-- 0x4    0x1
local shop_check = function(shop_offset, item_offset, check_name)
    debug('\r\nLocal shop offset: ')

    local local_shop_offset = shop_context_offset;
    debug('0x' .. string.format("%x",local_shop_offset))

    local nearby_memory = mainmemory.read_u32_be(local_shop_offset)
    debug('Local memory block 0x' .. string.format("%x",nearby_memory))

    local bitToCheck = shop_offset*4 + item_offset

    debug('Checking bit #'..bitToCheck)

    local match = bit.check(nearby_memory,bitToCheck)
    print_check_message(check_name, match)
end

--NOTE: Getting the bit poe bottle isn't flagged directly, instead only the points on the card are saved
--      and checked on each big poe turn in.
local big_poe_bottle_check = function(check_name)
    debug('\r\nBig poe points offset: 0x' .. string.format("%x",big_poe_points_offset))

    local nearby_memory = mainmemory.read_u32_be(big_poe_points_offset)
    debug('Local memory block 0x' .. string.format("%x", nearby_memory))

    local points_required = 100*NUM_BIG_POES_REQIURED
    debug('Points required: '..points_required)

    local match = (nearby_memory >= points_required)
    print_check_message(check_name, match)
end



-- Offsets can be found at the OOT save context layout here:
-- https://wiki.cloudmodding.com/oot/Save_Format#event_chk_inf
local event_check = function(major_offset,bit_to_check,event_name)
    -- shifting over to the next 4 hex digits
    local event_address = event_context_offset + 0x2 * major_offset;
    debug('0x' .. string.format("%x",event_address))

    local u_16_event_row = mainmemory.read_u16_be(event_address)
    debug('Local memory block 0x' .. string.format("%x",u_16_event_row) .. ' checking bit 0x' .. string.format("%x",bit_to_check));

    local match = bit.check(u_16_event_row,bit_to_check)
    print_check_message(event_name, match)
end

--Used by the game to track some non-quest item event flags
local item_get_info_check = function(check_offset,bit_to_check,check_name)
    debug('\r\nLocal scene offset: ')

    local local_offset = item_get_inf_offset + (check_offset);
    debug('0x' .. string.format("%x",local_offset))

    local nearby_memory = mainmemory.read_u8(local_offset)
    debug('Local memory block 0x' .. string.format("%x",nearby_memory))

    debug('Checking bit #'..bit_to_check)
    local match = bit.check(nearby_memory,bit_to_check)
    print_check_message(check_name, match)
end

--Used by the game to track lots of misc information (Talking to people, getting items, etc.)
local info_table_check = function(check_offset,bit_to_check,check_name)
    debug('\r\nLocal scene offset: ')

    local local_offset = inf_table_offset + (check_offset);
    debug('0x' .. string.format("%x",local_offset))

    local nearby_memory = mainmemory.read_u8(local_offset)
    debug('Local memory block 0x' .. string.format("%x",nearby_memory))

    debug('Checking bit #'..bit_to_check)
    local match = bit.check(nearby_memory,bit_to_check)
    print_check_message(check_name, match)
end

-- The fishing records are intricate and in their own memory area
--NOTE: Fishing in rando is patched and getting the adult reward first doesn't result in the "Golden scale glitch"
local fishing_check = function(isAdult,check_name)
    local bitToCheck = 10 --for child
    if(isAdult) then
        bitToCheck = 11 --for adult
    end

    local nearby_memory = mainmemory.read_u32_be(fishing_context_offset)
    debug('Local memory block 0x' .. string.format("%x",nearby_memory))

    debug('Checking bit #'..bitToCheck)
    local match = bit.check(nearby_memory,bitToCheck)
    print_check_message(check_name, match)
end


local big_gorron_sword_check = function (check_name)
    local nearby_memory = mainmemory.read_u32_be(equipment_offset)
    debug('Local memory block 0x' .. string.format("%x",nearby_memory))

    local bitToCheck = 0x8

    debug('Checking bit #'..bitToCheck)
    local match = bit.check(nearby_memory,bitToCheck)
    print_check_message(check_name, match)
end




local print_kokiri_forest_checks = function()
    print_check_category_header('Kokiri Forest')

    chest_check(0x28, 0x00, 'Midos top left chest')
    chest_check(0x28, 0x01, 'Midos top right chest')
    chest_check(0x28, 0x02, 'Midos bottom left chest')
    chest_check(0x28, 0x03, 'Midos bottom right chest')
    chest_check(0x55, 0x00, 'Kokiri Sword chest')

    cow_check(0x34,0x18,"Cow in house")

    skulltula_check(0x0C,0x0,'Skulltula in soft soil ')
    skulltula_check(0x0C,0x1,'Skulltula on Know-it-All\'s House')
    skulltula_check(0x0C,0x2,'Skulltula on Twin\'s House')

    shop_check(0x6, 0x3, 'Kokiri top-left shop item')
    shop_check(0x6, 0x1, 'Kokiri top-right shop item')
    shop_check(0x6, 0x2, 'Kokiri bottom-left shop item')
    shop_check(0x6, 0x0, 'Kokiri bottom-right shop item')

    chest_check(0x3E, 0x0C, 'Storms grotto chest')
end

local print_lost_woods_checks = function()
    print_check_category_header('Lost Woods')
    event_check(0xC,0x1,'Fairy ocarina check')
    scrub_check(0x5B,0x2,'Right theater scrub')
    scrub_check(0x5B,0x1,'Left theater scrub')
    scrub_check(0x5B,0xA,'Bridge scrub')
    scrub_check(0x1F,0xB,"Grotto by Sacred Forest Meadow left scrub")
    scrub_check(0x1F,0x4,"Grotto Sacred Forest Meadow right scrub")

    item_get_info_check(0x2,0x5,'Slingshot target')
    item_get_info_check(0x3,0x6,'Skull kid check')
    item_get_info_check(0x3,0x7,'Ocarina minigame')
    chest_check(0x3E, 0x14, 'Grotto near goron city shortcut chest')
    item_get_info_check(0x2,0x6,'Deku theater skull mask')
    item_get_info_check(0x2,0x7,'Deku theater mask of truth')
    skulltula_check(0x0D,0x0,'Skulltula soft soil by bridge')
    skulltula_check(0x0D,0x1,'Skulltula soft soil by theater')
    skulltula_check(0x0D,0x2,'Skulltula above theater')
end

local print_sacred_forest_meadow_checks = function()
    print_check_category_header('Sacred Forest Meadow')
    event_check(0x5,0x7,'Saria\'s song check')
    skulltula_check(0x0D,0x3,'Skulltula on wall')
    chest_check(0x3E, 0x11, 'Wolfos Grotto chest')
    scrub_check(0x18,0x8,"Storms grotto left scrub")
    scrub_check(0x18,0x9,"Storms grotto right scrub")

    event_check(0x5,0x0,'Minuet of forest check')
end

local print_deku_tree_checks = function()
    print_check_category_header('Deku Tree')
    chest_check(0x00,0x3,'Map chest')
    chest_check(0x00,0x5,'Slingshot room side chest')
    chest_check(0x00,0x1,'Slingshot chest')
    chest_check(0x00,0x2,'Compass chest')
    chest_check(0x00,0x6,'Compass room side chest')
    chest_check(0x00,0x4,'Basement chest')

    skulltula_check(0x0,0x3,'Skulltula in compass room')
    skulltula_check(0x0,0x2,'Skulltula on basement vines')
    skulltula_check(0x0,0x1,'Skulltula on basement gate')
    skulltula_check(0x0,0x0,'Skulltula in basement bomb wall room')

    on_the_ground_check(0x11,0x1F,'Gohma heart container')
    --Also sets ghoma blue warp (0x0, 0x9)
    event_check(0x0,0x7,'Kokiri Emerald Check')
end

local print_forest_temple_checks = function()
    print_check_category_header('Forest Temple')
    chest_check(0x3,0x3,'Entry room tree chest')
    chest_check(0x3,0x0,'First stalfos chest')
    chest_check(0x3,0x5,'Raised island courtyard chest')
    chest_check(0x3,0x1,'Map chest')
    chest_check(0x3,0x9,'Well chest')
    chest_check(0x3,0x4,'Eye switch chest')
    chest_check(0x3,0xE,'Boss key chest')
    chest_check(0x3,0x2,'Floormaster chest')
    chest_check(0x3,0xD,'Red poe chest')
    chest_check(0x3,0xC,'Bow chest')
    chest_check(0x3,0xF,'Blue poe chest')
    chest_check(0x3,0x7,'Crushing ceiling chest')
    chest_check(0x3,0xB,'Basement chest')

    skulltula_check(0x03,0x1,'Skulltula in the entry room')
    skulltula_check(0x03,0x3,'Skulltula in the lobby')
    skulltula_check(0x03,0x0,'Skulltula in the raised island courtyard')
    skulltula_check(0x03,0x2,'Skulltula in the level island courtyard')
    skulltula_check(0x03,0x4,'Skulltula in the basement')

    on_the_ground_check(0x14,0x1F,'Phantom ganon heart container')
    event_check(0x4,0x8,'Forest medallion check')
end

local print_hyrule_field_checks = function()
    print_check_category_header('Hyrule Field')
    event_check(0x4,0x3,'Ocarina of time check')
    event_check(0xA,0x9,'Song of time check')
    chest_check(0x3E, 0x00, 'Grotto by Market Chest')
    on_the_ground_check(0x3E, 0x01, 'Diving grotto HP')
    chest_check(0x3E, 0x02, 'South-East grotto chest')
    chest_check(0x3E, 0x03, 'Open grotto chest')
    scrub_check(0x10,0x3,"Grotto by Lake Hylia scrub")
    cow_check(0x3E,0x1,"Cow in web grotto")

    skulltula_check(0x0A,0x0,'Skulltula in cow grotto')
    skulltula_check(0x0A,0x1,'Skulltula in grotto near Kakariko')
end

local print_lon_lon_ranch_checks = function()
    print_check_category_header('Lon Lon Ranch')
    event_check(0x5,0x8,'Epona\'s song check')
    item_get_info_check(0x1,0x2,'Talon\'s cucco minigame bottle')
    on_the_ground_check(0x4C, 0x01, 'Block puzzle HP')
    cow_check(0x4C,0x18,"Tower left cow")
    cow_check(0x4C,0x19,"Tower right cow")


    scrub_check(0x26,0x1,"Child grotto left scrub")
    scrub_check(0x26,0x4,"Child grotto middle scrub")
    scrub_check(0x26,0x6,"Child grotto right scrub")

    cow_check(0x36,0x18,"Stables left cow")
    cow_check(0x36,0x19,"Stables right cow")

    skulltula_check(0x0B,0x2,'Skulltula on house window')
    skulltula_check(0x0B,0x3,'Skulltula in tree')
    skulltula_check(0x0B,0x1,'Skulltula on back of corral wall')
    skulltula_check(0x0B,0x0,'Skulltula on outer wall')
end

--NOTE Logic has bombchus from bomchu bowling here, but it's an endless drop so it is not printed
local print_market_checks = function()
    print_check_category_header('Market')
    item_get_info_check(0x0,0x5,'Child shooting gallery')
    item_get_info_check(0x3,0x1,'Bombchu bowling prize #1')
    item_get_info_check(0x3,0x2,'Bombchu bowling prize #2')
    item_get_info_check(0x2,0x3,'Treasure chest minigame')
    info_table_check(0x33,0x1,"Richard the dog HP")
    big_poe_bottle_check('Big poe bottle')
    event_check(0xC,0x4,'Light arrow check')
    event_check(0x5,0x5,'Prelude of light check')

    skulltula_check(0x0E,0x3,'Skulltula in guard house crate')

    shop_check(0x4, 0x3, 'Market Bazaar top-left shop item')
    shop_check(0x4, 0x1, 'Market Bazaar top-right shop item')
    shop_check(0x4, 0x2, 'Market Bazaar bottom-left shop item')
    shop_check(0x4, 0x0, 'Market Bazaar bottom-right shop item')

    shop_check(0x8, 0x3, 'Market Potion top-left shop item')
    shop_check(0x8, 0x1, 'Market Potion top-right shop item')
    shop_check(0x8, 0x2, 'Market Potion bottom-left shop item')
    shop_check(0x8, 0x0, 'Market Potion bottom-right shop item')

    shop_check(0x1, 0x3, 'Market Bombchu top-left shop item')
    shop_check(0x1, 0x1, 'Market Bombchu top-right shop item')
    shop_check(0x1, 0x2, 'Market Bombchu bottom-left shop item')
    shop_check(0x1, 0x0, 'Market Bombchu bottom-right shop item')
end

local print_hyrule_castle_checks = function()
    print_check_category_header('Hyrule Castle')
    event_check(0x5,0x9,'Zelda\'s lullaby check')
    event_check(0x1,0x2,'Strange egg from Malon check')
    event_check(0x4,0x0,'Zelda\'s letter check')
    item_get_info_check(0x2,0x1,'Din\'s fire check')
    skulltula_check(0xE,0x2,'Skulltula in tree')
    skulltula_check(0xE,0x1,'Skulltula in storms grotto')
end

local print_kakariko_village_checks = function()
    print_check_category_header('Kakariko Village')
    event_check(0x5,0xB,'Song of storms check')
    event_check(0x5,0x4,'Nocturne of shadows check')
    item_get_info_check(0x0,0x4,'Cucco collecting bottle')
    item_get_info_check(0x4,0x4,'Talk to cucco lady as adult')
    on_the_ground_check(0x37,0x1,'Impa\'s house HP (Cow jail)')
    cow_check(0x37,0x18,"Impa\'s house cow")

    item_get_info_check(0x3,0x5,'Man on roof HP')
    chest_check(0x3E, 0x08, 'Potion shop grotto chest')
    chest_check(0x3E, 0x0A, 'Redead grotto chest')
    item_get_info_check(0x0,0x6,'Adult shooting gallery')
    event_check(0xD,0xA,'10 gold skulltula check')
    event_check(0xD,0xB,'20 gold skulltula check')
    event_check(0xD,0xC,'30 gold skulltula check')
    event_check(0xD,0xD,'40 gold skulltula check')
    event_check(0xD,0xE,'50 gold skulltula check')

    skulltula_check(0x10,0x5,'Skulltula in tree')
    skulltula_check(0x10,0x1,'Skulltula on guard\'s house')
    skulltula_check(0x10,0x4,'Skulltula on Skulltula house')
    skulltula_check(0x10,0x2,'Skulltula on watchtower')
    skulltula_check(0x10,0x3,'Skulltula on construction site')
    skulltula_check(0x10,0x6,'Skulltula above Impa\'s house')

    --In rando these shops contain different items from market bazaar/potion
    shop_check(0x7, 0x3, 'Kakariko Bazaar top-left shop item')
    shop_check(0x7, 0x1, 'Kakariko Bazaar top-right shop item')
    shop_check(0x7, 0x2, 'Kakariko Bazaar bottom-left shop item')
    shop_check(0x7, 0x0, 'Kakariko Bazaar bottom-right shop item')

    shop_check(0x3, 0x3, 'Kakariko Potion top-left shop item')
    shop_check(0x3, 0x1, 'Kakariko Potion top-right shop item')
    shop_check(0x3, 0x2, 'Kakariko Potion bottom-left shop item')
    shop_check(0x3, 0x0, 'Kakariko Potion bottom-right shop item')
end

local print_graveyard_checks = function()
    print_check_category_header('Graveyard')
    event_check(0x5,0xA,'Sun\'s song check')
    chest_check(0x40, 0x00, 'Shield grave chest')
    chest_check(0x3F, 0x00, 'Sun song grave HP')
    chest_check(0x41, 0x00, 'Composer\'s grave HP chest')
    on_the_ground_check(0x53,0x4,'HP in graveyard crate')
    on_the_ground_check(0x53,0x8,'Dampe\'s gravedigging HP')
    chest_check(0x48, 0x00, 'Hookshot Chest')
    on_the_ground_check(0x48,0x7,'Dampe race in 1 minute HP')
    on_the_ground_check(0x48,0x1,'Windmill HP')

    skulltula_check(0x10,0x0,'Skulltula in soft soil')
    skulltula_check(0x10,0x7,'Skulltula on wall')
end

local print_bottom_of_the_well_checks = function()
    print_check_category_header('Bottom of the Well')
    chest_check(0x08, 0x08, 'Front-left fake wall chest')
    chest_check(0x08, 0x02, 'Front-center bombable chest')
    chest_check(0x08, 0x04, 'Back-left bombable chest')
    chest_check(0x08, 0x09, 'Underwater left chest')
    on_the_ground_check(0x08,0x01,'Coffin key')
    chest_check(0x08, 0x01, 'Compass chest')
    chest_check(0x08, 0x0E, 'Center skulltula chest')
    chest_check(0x08, 0x05, 'Right-bottom fake wall chest')
    chest_check(0x08, 0x0A, 'Fire keese chest')
    chest_check(0x08, 0x0C, 'Like like chest')
    chest_check(0x08, 0x07, 'Map chest')
    chest_check(0x08, 0x10, 'Underwater front chest')
    chest_check(0x08, 0x14, 'Invisible chest')
    chest_check(0x08, 0x03, 'Lens of truth chest')

    skulltula_check(0x08,0x2,'Skulltula in West inner room')
    skulltula_check(0x08,0x1,'Skulltula in East inner room')
    skulltula_check(0x08,0x0,'Skulltula in like like cage')
end

local print_shadow_temple_checks = function()
    print_check_category_header('Shadow Temple')
    chest_check(0x07, 0x01, 'Map chest')
    chest_check(0x07, 0x07, 'Hover boots chest')
    chest_check(0x07, 0x03, 'Compass chest')
    chest_check(0x07, 0x02, 'Early silver rupee chest')
    chest_check(0x07, 0x0C, 'Invisible blades visible chest')
    chest_check(0x07, 0x16, 'Invisible blades invisible chest')
    chest_check(0x07, 0x05, 'Falling spikes lower chest')
    chest_check(0x07, 0x06, 'Falling spikes upper chest')
    chest_check(0x07, 0x04, 'Falling spikes switch chest')
    chest_check(0x07, 0x09, 'Invisible spikes chest')
    --NOTE: AKA "Free-standing key"
    on_the_ground_check(0x07,0x01,'Key in single skull pot')
    chest_check(0x07, 0x15, 'Wind hint chest')
    chest_check(0x07, 0x08, 'After wind enemy chest')
    chest_check(0x07, 0x14, 'After wind hidden chest')
    chest_check(0x07, 0x0A, 'Spike walls left chest')
    chest_check(0x07, 0x0B, 'Boss key chest')
    chest_check(0x07, 0x0D, 'Invisible floormaster chest')

    --NOTE: AKA "Skulltula in like like room"
    skulltula_check(0x07,0x3,'Skulltula in invisible scythe room')
    skulltula_check(0x07,0x1,'Skulltula in falling spikes room')
    skulltula_check(0x07,0x0,'Skulltula in single giant pot')
    skulltula_check(0x07,0x4,'Skulltula near ship')
    skulltula_check(0x07,0x2,'Skulltula in triple giant pot')

    on_the_ground_check(0x18,0x1F,'Bongo Bongo heart container')
    --NOTE: During the test playthrough there were no event bits or scene bits were set for shadow medallion being collected, only the Quest Status items were updated.
    --      As such, the Bongo Bongo heart container is used as an approximation of the Shadow Medallion check
    on_the_ground_check(0x18,0x1F,'Shadow medallion')
end

local print_death_mountain_trail_checks = function()
    print_check_category_header('Death Mountain Trail')
    on_the_ground_check(0x60,0x1E,'HP above Dodongo\'s Cavern')
    chest_check(0x60, 0x01, 'Chest by Goron City')
    chest_check(0x3E, 0x17, 'Storms grotto chest')
    great_fairy_magic_check(0x3B, 0x18, 'Death Mountain Trail great fairy')
    big_gorron_sword_check('Biggoron sword check')
    cow_check(0x3E,0x18,'Death Mountain cow in grotto')

    skulltula_check(0x0F,0x2,'Skulltula in bombable wall by Kakariko')
    skulltula_check(0x0F,0x1,'Skulltula in soft soil')
    skulltula_check(0x0F,0x3,'Skulltula on ledge above Dodongo\'s Cavern')
    skulltula_check(0x0F,0x4,'Skulltula on falling rocks path')
end

local print_goron_city_checks = function()
    print_check_category_header('Goron City')
    event_check(0x5,0x7,'Darunia\'s joy')
    on_the_ground_check(0x62,0x1F,'Spinning Pot HP')
    info_table_check(0x22,0x6,"Stop rolling goron as child")
    info_table_check(0x20,0x1,"Stop rolling goron as adult")
    --TODO Verify in a playthough
    on_the_ground_check(0x62,0x1,'Medigoron giant\'s knife check')
    chest_check(0x62, 0x00, 'Rock Maze Left Chest')
    chest_check(0x62, 0x01, 'Rock Maze Right Chest')
    chest_check(0x62, 0x02, 'Rock Maze Center Chest')
    scrub_check(0x25,0x1,"Lava grotto left scrub")
    scrub_check(0x25,0x4,"Lava grotto middle scrub")
    scrub_check(0x25,0x6,"Lava grotto right scrub")
    skulltula_check(0x0F,0x5,'Skulltula on center platform')
    skulltula_check(0x0F,0x6,'Skulltula in rock maze crate')

    shop_check(0x5, 0x3, 'Goron City top-left shop item')
    shop_check(0x5, 0x1, 'Goron City top-right shop item')
    shop_check(0x5, 0x2, 'Goron City bottom-left shop item')
    shop_check(0x5, 0x0, 'Goron City bottom-right shop item')
end

local print_death_mountain_crater_checks = function()
    print_check_category_header('Death Mountain Crater')
    event_check(0x5,0x1,'Bolero of fire check')
    on_the_ground_check(0x61,0x08,'Volcano HP')
    on_the_ground_check(0x61,0x02,'Climb wall HP')
    chest_check(0x3E, 0x1A, 'Upper grotto chest')
    --TODO Correct bit mask or determine if this is located elsewhere
    -- great_fairy_magic_check(0x3B, 0x0, 'Double magic great fairy')

    scrub_check(0x61,0x6,'Ladder scrub (child only)')
    scrub_check(0x23,0x1,"Hammer grotto left scrub")
    scrub_check(0x23,0x4,"Hammer grotto middle scrub")
    scrub_check(0x23,0x6,"Hammer grotto right scrub")

    skulltula_check(0x0F,0x7,'Skulltula in entrance crate')
    skulltula_check(0x0F,0x0,'Skulltula in soft soil')
end

local print_dodongos_cavern_checks = function()
    print_check_category_header('Dodongo\'s Cavern')
    chest_check(0x01, 0x8, 'Map chest')
    chest_check(0x01, 0x5, 'Compass chest')
    chest_check(0x01, 0x6, 'Bomb flower platform chest')
    chest_check(0x01, 0x4, 'Bomb bag chest')
    chest_check(0x01, 0xA, 'End of bridge chest')
    chest_check(0x12, 0x0, 'Boss room chest')

    scrub_check(0x1,0x5,'Scrub in main room')
    scrub_check(0x1,0x2,'Scrub by dodongo room')
    scrub_check(0x1,0x1,'Left scrub by bomb bag')
    scrub_check(0x1,0x4,'Right scrub by bomb bag')

    skulltula_check(0x01,0x4,'Skulltula in side room by lower lizalfos')
    skulltula_check(0x01,0x1,'Skulltula in scarecrow hallway')
    skulltula_check(0x01,0x2,'Skulltula in alcove above falling stairs')
    skulltula_check(0x01,0x0,'Skulltula on vines in falling stairs room')
    skulltula_check(0x01,0x3,'Skulltula in back room')

    on_the_ground_check(0x12,0x1F,'King Dodongo heart container')
    event_check(0x2,0x5,'Goron\'s Ruby check')
end

local print_fire_temple_checks = function()
    print_check_category_header('Fire Temple')
    chest_check(0x04, 0x01, 'Chest near boss room')
    chest_check(0x04, 0x00, 'Flare dancer chest')
    chest_check(0x04, 0x0C, 'Boss key chest')
    chest_check(0x04, 0x04, 'Big lava room North hallway chest')
    chest_check(0x04, 0x02, 'Big lava room South hallway chest')
    chest_check(0x04, 0x03, 'Boulder maze lower chest')
    chest_check(0x04, 0x08, 'Boulder maze side room chest')
    chest_check(0x04, 0x0A, 'Map chest')
    chest_check(0x04, 0x0B, 'Boulder maze shortcut chest')
    chest_check(0x04, 0x06, 'Boulder maze upper chest')
    chest_check(0x04, 0x0D, 'Scarecrow chest')
    chest_check(0x04, 0x07, 'Compass chest')
    chest_check(0x04, 0x05, 'Megaton hammer chest')
    chest_check(0x04, 0x09, 'Highest goron chest')

    skulltula_check(0x04,0x1,'Skulltula in boss key loop')
    skulltula_check(0x04,0x0,'Skulltula in song of time room')
    skulltula_check(0x04,0x2,'Skulltula in boulder maze room')
    skulltula_check(0x04,0x4,'Skulltula at scarecrow climb')
    skulltula_check(0x04,0x3,'Skulltula at scarecrow top')

    on_the_ground_check(0x15,0x1F,'Volvagia heart container')
    event_check(0x4,0x9,'Fire medallion check')
end

local print_zoras_river_checks = function()
    print_check_category_header('Zora\'s River')
    bean_sale_check(0x54,0x18,'Bean salesman check')
    chest_check(0x3E, 0x09, 'Open grotto on ledge chest')
    event_check(0xD,0x6,'Song of storms for frogs')
    event_check(0xD,0x0,'5 songs + frog song minigame')
    on_the_ground_check(0x54,0x04,'Pillar in river HP')
    on_the_ground_check(0x54,0x0B,'Waterfall ledge HP')
    scrub_check(0x15,0x8,"Storms grotto left scrub")
    scrub_check(0x15,0x9,"Storms grotto right scrub")

    skulltula_check(0x11,0x1,'Skulltula in tree')
    --NOTE: There is no GS in the soft soil. It's the only one that doesn't have one.
    skulltula_check(0x11,0x0,'Skulltula on ladder')
    skulltula_check(0x11,0x4,'Skulltula on wall by upper grottos')
    skulltula_check(0x11,0x3,'Skulltula on wall above bridge')
end

local print_zoras_domain_checks = function()
    print_check_category_header('Zora\'s Domain')
    event_check(0x3,0x8,'Diving minigame')
    chest_check(0x58, 0x00, 'Torches Chest')
    info_table_check(0x26,0x1,"Thawed King Zora")
    skulltula_check(0x11,0x6,'Skulltula by frozen waterfall')

    shop_check(0x2, 0x3, 'Zora\'s Domain top-left shop item')
    shop_check(0x2, 0x1, 'Zora\'s Domain top-right shop item')
    shop_check(0x2, 0x2, 'Zora\'s Domain bottom-left shop item')
    shop_check(0x2, 0x0, 'Zora\'s Domain bottom-right shop item')
end

local print_zoras_fountain_checks = function()
    print_check_category_header('Zora\'s Fountain')
    item_get_info_check(0x2,0x0,'Farore\'s wind check')
    on_the_ground_check(0x59,0x01,'Iceberg HP')
    on_the_ground_check(0x59,0x14,'Bottom of lake HP')
    skulltula_check(0x11,0x2,'Skulltula above log')
    skulltula_check(0x11,0x7,'Skulltula in tree')
    skulltula_check(0x11,0x5,'Skulltula in hidden cave')
end

local print_jabu_checks = function()
    print_check_category_header('Jabu Jabu\'s Belly')
    chest_check(0x02, 0x01, 'Boomerang chest')
    chest_check(0x02, 0x02, 'Map chest')
    chest_check(0x02, 0x04, 'Compass chest')
    scrub_check(0x02,0x1,"Scrub at bottom of Jabu")
    skulltula_check(0x02,0x3,'Skulltula in water switch room')
    skulltula_check(0x02,0x0,'Skulltula in lobby basement (lower skulltula)')
    skulltula_check(0x02,0x1,'Skulltula in lobby basement (upper skulltula)')
    skulltula_check(0x02,0x2,'Skulltula near boss room')

    on_the_ground_check(0x13,0x1F,'Barinade heart container')
    event_check(0x3,0x7,'Zora\'s sapphire check')
end

local print_ice_cavern_checks = function()
    print_check_category_header('Ice Cavern')
    event_check(0x5,0x2,'Serenade of water')
    chest_check(0x09, 0x00, 'Map chest')
    chest_check(0x09, 0x01, 'Compass chest')
    on_the_ground_check(0x09,0x01,'HP in red ice')
    chest_check(0x09, 0x02, 'Iron boots chest')
    skulltula_check(0x09,0x1,'Skulltula in spinning scythe room')
    skulltula_check(0x09,0x2,'Skulltula in iced HP room')
    skulltula_check(0x09,0x0,'Skulltula in push block room')
end

local print_lake_hylia_checks = function()
    print_check_category_header('Lake Hylia')
    event_check(0x3,0x1,'Ruto\'s letter check')
    fishing_check(false,"Child fishing reward")
    fishing_check(true,"Adult fishing reward")
    item_get_info_check(0x3,0x0,'Lake Hylia Lab diving HP')
    on_the_ground_check(0x57,0x1E,'HP on lab')
    --It's not actually a chest, but it is marked in the chest section
    chest_check(0x57,0x0,'Fire arrows check')
    scrub_check(0x19,0x1,"Grave grotto left scrub")
    scrub_check(0x19,0x4,"Grave grotto middle scrub")
    scrub_check(0x19,0x6,"Grave grotto right scrub")

    skulltula_check(0x12,0x2,'Skulltula on lab wall')
    skulltula_check(0x12,0x0,'Skulltula in soft soil')
    skulltula_check(0x12,0x1,'Skulltula on fire arrow island')
    skulltula_check(0x12,0x3,'Skulltula in lab crate')
    skulltula_check(0x12,0x4,'Skulltula in big tree')
end

local print_water_temple_checks = function()
    print_check_category_header('Water Temple')
    chest_check(0x05, 0x09, 'Compass chest')
    chest_check(0x05, 0x02, 'Map chest')
    chest_check(0x05, 0x00, 'Cracked wall chest')
    chest_check(0x05, 0x01, 'Torches chest')
    chest_check(0x05, 0x05, 'Boss key chest')
    chest_check(0x05, 0x06, 'Central pillar chest')
    chest_check(0x05, 0x08, 'Central bow target chest')
    chest_check(0x05, 0x07, 'Longshot chest')
    chest_check(0x05, 0x03, 'River chest')
    chest_check(0x05, 0x0A, 'Dragon chest')

    skulltula_check(0x05,0x0,'Skulltula behind gate')
    skulltula_check(0x05,0x3,'Skulltula near boss key room')
    skulltula_check(0x05,0x2,'Skulltula in central pillar room')
    skulltula_check(0x05,0x1,'Skulltula in falling platforms room')
    skulltula_check(0x05,0x4,'Skulltula in river room')

    on_the_ground_check(0x16,0x1F,'Morpha heart container')
    event_check(0x4,0xA,'Water medallion check')
end

local print_gerudo_valley_checks = function()
    print_check_category_header('Gerudo Valley')
    on_the_ground_check(0x5A,0x2,'Crate on ledge HP')
    on_the_ground_check(0x5A,0x1,'Waterfall HP')
    chest_check(0x5A, 0x00, 'Hammer rock chest')
    scrub_check(0x1A,0x8,"Storms grotto left scrub")
    scrub_check(0x1A,0x9,"Storms grotto right scrub")
    cow_check(0x5A,0x18,"Cow at bottom of Gerudo Valley")

    skulltula_check(0x13,0x1,'Skulltula by entry bridge')
    skulltula_check(0x13,0x0,'Skulltula in soft soil')
    skulltula_check(0x13,0x3,'Skulltula behind tent')
    skulltula_check(0x13,0x2,'Skulltula on pillar')
end

local print_gerudo_fortress_checks = function()
    print_check_category_header('Gerudo Fortress')
    on_the_ground_check(0xC,0xC,'North F1 Carpenter')
    on_the_ground_check(0xC,0xA,'North F2 Carpenter')
    on_the_ground_check(0xC,0xE,'South F1 Carpenter')
    on_the_ground_check(0xC,0xF,'South F2 Carpenter')
    chest_check(0x5D, 0x00, 'Top of fortress chest')
    membership_card_check(0xC, 0x2, 'Membership card check')
    info_table_check(0x33,0x0,"Horseback archery 1000pts")
    item_get_info_check(0x0,0x7,'Horseback archery 1500pts')
    skulltula_check(0x14,0x1,'Skulltula at top of fortress')
    skulltula_check(0x14,0x0,'Skulltula on far archery target')
end

local print_gerudo_training_ground_checks = function()
    print_check_category_header('Gerudo Training Ground')
    chest_check(0x0B, 0x13, 'Lobby left chest')
    chest_check(0x0B, 0x07, 'Lobby right chest')
    chest_check(0x0B, 0x00, 'Stalfos chest')
    chest_check(0x0B, 0x11, 'Before heavy block chest')
    chest_check(0x0B, 0x0F, 'Heavy block 1st chest')
    chest_check(0x0B, 0x0E, 'Heavy block 2nd chest')
    chest_check(0x0B, 0x14, 'Heavy block 3rd chest')
    chest_check(0x0B, 0x02, 'Heavy block 4th chest')
    chest_check(0x0B, 0x03, 'Eye statue chest')
    chest_check(0x0B, 0x04, 'Near scarecrow chest')
    chest_check(0x0B, 0x12, 'Hammer room enemy clear chest')
    chest_check(0x0B, 0x10, 'Hammer room switch chest')
    on_the_ground_check(0x0B,0x1,'Key on stairs')
    chest_check(0x0B, 0x05, 'Maze right-central chest')
    chest_check(0x0B, 0x08, 'Maze right-side chest')
    chest_check(0x0B, 0x0D, 'Underwater silver rupee chest')
    chest_check(0x0B, 0x01, 'Beamos chest')
    chest_check(0x0B, 0x0B, 'Hidden ceiling chest')
    chest_check(0x0B, 0x06, 'Maze path 1st chest')
    chest_check(0x0B, 0x0A, 'Maze path 2nd chest')
    chest_check(0x0B, 0x09, 'Maze path 3rd chest')
    chest_check(0x0B, 0x0C, 'Maze path final chest')
end

local print_haunted_wasteland_checks = function()
    print_check_category_header('Haunted Wasteland')
    --TODO Verify in a playthough
    on_the_ground_check(0x5E,0x01,'Carpet salesman check')
    chest_check(0x5E, 0x00, 'Wasteland chest')
    skulltula_check(0x15,0x1,'Skulltula in shelter')
end

local print_desert_colossus_checks = function()
    print_check_category_header('Desert Colossus')
    event_check(0xA,0xC,'Requiem of spirit check')
    item_get_info_check(0x2,0x2,'Naryu\'s love check')
    on_the_ground_check(0x5C,0xD,'HP on arch')
    scrub_check(0x27,0x8,"Silver boulder grotto left scrub")
    scrub_check(0x27,0x9,"Silver boulder grotto right scrub")

    skulltula_check(0x15,0x2,'Skulltula on hill')
    skulltula_check(0x15,0x3,'Skulltula on tree')
    skulltula_check(0x15,0x0,'Skulltula in soft soil')
end

local print_spirit_temple_checks = function()
    print_check_category_header('Spirit Temple')
    chest_check(0x06, 0x08, 'Child bridge chest')
    chest_check(0x06, 0x00, 'Child early torches chest')
    chest_check(0x06, 0x06, 'Child climb North chest')
    chest_check(0x06, 0x0C, 'Child climb East chest')
    chest_check(0x06, 0x03, 'Map chest')
    chest_check(0x06, 0x01, 'Sun block room chest')
    chest_check(0x5C, 0x0B, 'Silver gauntlets chest')

    chest_check(0x06, 0x04, 'Compass chest')
    chest_check(0x06, 0x07, 'Early adult right chest')
    chest_check(0x06, 0x0D, 'First mirror left chest')
    chest_check(0x06, 0x0E, 'First mirror right chest')
    chest_check(0x06, 0x0F, 'Statue room Northeast chest')
    chest_check(0x06, 0x02, 'Statue room hand chest')
    chest_check(0x06, 0x05, 'Near four armos chest')
    chest_check(0x06, 0x14, 'Hallway right invisible chest')
    chest_check(0x06, 0x15, 'Hallway left invisible chest')
    chest_check(0x5C, 0x09, 'Mirror shield chest')

    chest_check(0x06, 0x0A, 'Boss key chest')
    chest_check(0x06, 0x12, 'Top-most chest')

    skulltula_check(0x06,0x4,'Skulltula on metal fence')
    skulltula_check(0x06,0x3,'Skulltula on sun room floor')
    skulltula_check(0x06,0x0,'Skulltula in hall after sun block room')
    skulltula_check(0x06,0x2,'Skulltula lobby')
    skulltula_check(0x06,0x1,'Skulltula boulder room')

    on_the_ground_check(0x17,0x1F,'Twinrova heart container')
    event_check(0xC,0x8,'Spirit medallion check')
end

local print_ganons_castle_checks = function()
    print_check_category_header('Ganon\'s Castle')
    great_fairy_magic_check(0x3B, 0x8, 'Ganon\'s Castle great fairy')
    skulltula_check(0x0E,0x0,'Skulltula outside on pillar')


    chest_check(0x0D, 0x09, 'Forest trial chest')
    chest_check(0x0D, 0x07, 'Water trial left chest')
    chest_check(0x0D, 0x06, 'Water trial right chest')
    chest_check(0x0D, 0x08, 'Shadow trial front chest')
    chest_check(0x0D, 0x05, 'Shadow trial gold gauntlets chest')
    chest_check(0x0D, 0x0C, 'Light trial 1st left chest')
    chest_check(0x0D, 0x0B, 'Light trial 2nd left chest')
    chest_check(0x0D, 0x0D, 'Light trial 3rd left chest')
    chest_check(0x0D, 0x0E, 'Light trial 1st right chest')
    chest_check(0x0D, 0x0A, 'Light trial 2nd right chest')
    chest_check(0x0D, 0x0F, 'Light trial 3rd right chest')
    chest_check(0x0D, 0x10, 'Light trial invisible enemies chest')
    chest_check(0x0D, 0x11, 'Light trial lullaby chest')
    chest_check(0x0D, 0x12, 'Spirit trial crystal switch chest')
    chest_check(0x0D, 0x14, 'Spirit trial invisible chest')

    scrub_check(0xD,0x8,"Lobby left scrub")
    scrub_check(0xD,0x6,"Lobby center-left scrub")
    scrub_check(0xD,0x4,"Lobby center-right scrub")
    scrub_check(0xD,0x9,"Lobby right scrub")

    chest_check(0x0A, 0x0B, 'Ganon\'s Tower boss key chest')

end

-- NOTES: Rando has the lists of checks here https://github.com/Roman971/OoT-Randomizer/tree/Dev-R/data/World
-- NOTES: Since BizHawk doesn't modify the ROM, but instead interacts with the RAM directly this checker category_name
--        use the solo-player Rando memory addresses.
function print_item_check_statuses()
    print('---------------------START Checks Summary---------------------')
    print_kokiri_forest_checks()
    print_lost_woods_checks()
    print_sacred_forest_meadow_checks()
    print_deku_tree_checks()
    print_forest_temple_checks()
    print_hyrule_field_checks()
    print_lon_lon_ranch_checks()
    print_market_checks()
    print_hyrule_castle_checks()
    print_kakariko_village_checks()
    print_graveyard_checks()
    print_bottom_of_the_well_checks()
    print_shadow_temple_checks()
    print_death_mountain_trail_checks()
    print_goron_city_checks()
    print_death_mountain_crater_checks()
    print_dodongos_cavern_checks()
    print_fire_temple_checks()
    print_zoras_river_checks()
    print_zoras_domain_checks()
    print_zoras_fountain_checks()
    print_jabu_checks()
    print_ice_cavern_checks()
    print_lake_hylia_checks()
    print_water_temple_checks()
    print_gerudo_valley_checks()
    print_gerudo_fortress_checks()
    print_gerudo_training_ground_checks()
    print_haunted_wasteland_checks()
    print_desert_colossus_checks()
    print_spirit_temple_checks()
    print_ganons_castle_checks()
    print('----------------------END Checks Summary----------------------\r\n\r\n\r\n')
end


---------- Main Method -----------------
--TODO make this pull an Object and then write it
--TODO add item counts (5/10) to zones / main header

--TODO compress completed zones into a short line
--TODO make this an asynch call
print_item_check_statuses()