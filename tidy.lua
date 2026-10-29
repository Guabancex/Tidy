--[[
Tidy - drops unwanted loot from your inventory the moment it lands.
Author: Guabancex

For Ashita v4. You choose the items: each profile is a trash list, and only
items on the active profile's list are ever dropped -- everything else is kept.
Equipped items, bazaar items and gil are never touched.

Hunt mode uses the CatsEyeXI mob drop database (data/mobdb.lua, by monster id):
target a mob and add it, mark the item(s) you want, and everything else that
mob drops is trashed -- except Rare/Ex items and anything worth at least your
Keep value (NPC gil). Auto (on by default) reads the mob you're fighting and
applies the same rules to its drop list -- no setup per mob. Hunt only drops
what you loot: copies you already had are never touched.

Commands (/tidy alone opens the window):
  /tidy on | off                 start / stop dropping
  /tidy add <item name>          put an item on the active trash list
  /tidy remove <item name>       take it off again
  /tidy list                     show the active trash list
  /tidy profile                  list profiles
  /tidy profile <name>           switch profile
  /tidy profile new <name>       new empty profile (and switch to it)
  /tidy hunt                     add your current target to the hunt
  /tidy hunt clear               empty the hunt
  /tidy hunt auto [on|off]       read the mob you're fighting and use its drop list (default on)
  /tidy hunt forget              forget the mobs fought this session
  /tidy hunt value <gil>         keep anything worth at least this (NPC price)
  /tidy want <item name>         keep this item from the hunted mobs (toggle)
  /tidy extra                    list Extra drops (loot that isn't on any drop list)
  /tidy extra add|remove <item>  add / remove an Extra drop
  /tidy extra keep|rules <item>  never drop it / let the keep rules decide
  /tidy extra learn [on|off]     learn Extra drops from treasure pool loot (default on)
  /tidy mini                     fold the window to the green crystal / unfold it
  /tidy lock [on|off]            lock the window and the crystal in place (or use the Lock switch)
  /tidy th [auto | <0-14>]       Treasure Hunter used for drop rates (default auto)
  /tidy pause                    pause / resume dropping (this session only)
  /tidy reload                   reload the addon
  /tidy why                      why each item in your bag is or isn't dropped
  /tidy drop <item name>         drop one stack now (tests that drops work)
  /tidy help
]]--

addon.name    = 'Tidy'
addon.author  = 'Guabancex'
addon.version = '2.1.0'
addon.desc    = 'Drops unwanted loot as soon as it lands in your inventory.'
addon.link    = ''

require('common')
local chat     = require('chat')
local imgui    = require('imgui')
local settings = require('settings')
local logic    = require('lib.logic')

local INVENTORY    = 0      -- loot only ever lands in the main inventory
local SCAN_EVERY   = 0.5    -- seconds between inventory checks
local DROP_GAP     = 0.6    -- seconds between drops (one packet at a time)
local LOG_SIZE     = 50

local PANEL_W, PANEL_H_MIN, PANEL_H_MAX = 470, 220, 360
local START_W            = 660                -- window width when first opened
local MIN_W, MIN_H       = 600, 380           -- smallest you can drag it to
local MAX_W, MAX_H       = 1200, 1100
local GRIP               = 16                 -- the resize corner, in pixels

-- Window size: starts compact (the sidebar plus a page column about PANEL_W
-- wide, up to PANEL_H_MAX tall, less on small screens). Drag the bottom-right
-- corner to resize it; the page fills the column and long pages scroll inside
-- it. PANEL_W follows the window's width while it's drawn.

-- Game resolution from ImGui; 1920x1080 if it can't be read.
local function screen_size()
    local ok, w, h = pcall(function()
        local d = imgui.GetIO().DisplaySize
        return d.x or d[1], d.y or d[2]
    end)
    if ok and type(w) == 'number' and type(h) == 'number' and w > 0 and h > 0 then return w, h end
    return 1920, 1080
end

local defaults = T{
    enabled  = false,       -- off until you turn it on
    active   = 'Default',
    profiles = T{},         -- logic.ensure creates 'Default' on first load
    ui_open  = true,
    ui_mini  = false,       -- window folded down to the green crystal
    ui_size  = T{ -1, -1 }, -- full window size you dragged it to (-1 = starting size)
    opacity  = 82,          -- window opacity, 30-100
    th_override = -1,       -- Treasure Hunter for the drop rates: -1 = work it out
    extra    = T{},         -- Extra drops, shared by every profile (logic.extra_list)
    extra_learn = true,     -- learn Extra drops from treasure pool loot
    locked   = false,       -- lock style: the window and the crystal stay where they are
}

local S = nil
local db = nil              -- data/mobdb.lua, loaded on 'load'
local sent = {}             -- drops sent per slot (see logic.plan)
local baseline = {}         -- Hunt: what you already had of each loot item
local learned = {}          -- Hunt auto: [dropid] = { name, zone, at } for mobs you fought this session
local fighting = nil        -- { id, name, zone, dropid } of the mob you're engaged on, or nil
local targeted = nil        -- same shape: the monster under your cursor while NOT engaged
local fight_note = nil      -- why nothing is shown, e.g. 'X has no drop list' (window + /tidy why)
local last_scan, last_drop = 0, 0
local log = {}              -- recent drops, newest first: { time, name, count, value }
local stats = { stacks = 0, items = 0, value = 0 }   -- this session
local paused = false        -- session-only pause (not saved)

-- Treasure Hunter on the mob you're fighting. The client is never told the
-- mob's TH level, so: a proc message ("... increases to N") is exact; before
-- one, it's estimated from your job, subjob and gear and your party's THF levels.
local th_seen = {}          -- [mob server id] = { level, at }: TH the server announced
local th_recent = nil       -- { name, level, at }: a proc seen before the fight was read
local th_est = { level = 0, why = 'no Treasure Hunter' }
local last_fight_id = nil
local flash = nil           -- { text, at }: the last drop, shown fading in the header

local ui = {
    open      = { true },
    name_buf  = { '' },
    pick      = {},         -- item picker text per picker
    filter    = {},         -- search text per list
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function say(fmt, ...)
    print(chat.header(addon.name):append(chat.message(string.format(fmt, ...))))
end

local function err(fmt, ...)
    print(chat.header(addon.name):append(chat.error(string.format(fmt, ...))))
end

local function save()
    settings.save()
end

-- Lock style: the window and the folded crystal stay put (no dragging) until unlocked.
local function set_locked(on)
    S.locked = on and true or false
    save()
    say('%s', S.locked and 'Locked in place (/tidy lock to unlock).' or 'Unlocked: drag to move.')
end

-- Start over: what you hold right now becomes the baseline Hunt never touches.
local function reset_tracking()
    sent = {}
    baseline = {}
end

local function profile()
    return logic.ensure(S)
end

local extra_command, set_paused, reload     -- defined with the commands

local function item_name(id)
    local ok, res = pcall(function() return AshitaCore:GetResourceManager():GetItemById(id) end)
    if ok and res and res.Name and res.Name[1] and res.Name[1] ~= '' then return res.Name[1] end
    return 'Item #' .. tostring(id)
end

-- Item id by (English) name, any case; nil if unknown.
local function item_id(name)
    name = name and name:match('^%s*(.-)%s*$') or ''
    if name == '' then return nil end
    local rm = AshitaCore:GetResourceManager()
    for _, lang in ipairs({ 2, 0 }) do
        local ok, res = pcall(function() return rm:GetItemByName(name, lang) end)
        if ok and res and res.Id and res.Id ~= 0 then return res.Id, res.Name and res.Name[1] or name end
    end
    return nil
end

-- True once the character is fully in the world (not zoning / loading).
local function in_game()
    local ok, res = pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty()
        local player = AshitaCore:GetMemoryManager():GetPlayer()
        return party:GetMemberZone(0) ~= 0 and player:GetMainJobLevel() > 0
    end)
    return ok and res == true
end

-- The inventory as a list of { bag, index, id, count, flags }.
local function read_inventory()
    local slots = {}
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    local max = inv:GetContainerCountMax(INVENTORY)
    for i = 0, max - 1 do
        local it = inv:GetContainerItem(INVENTORY, i)
        if it and it.Id and it.Id ~= 0 and it.Id ~= 0xFFFF then
            slots[#slots + 1] = { bag = INVENTORY, index = i, id = it.Id, count = it.Count, flags = it.Flags }
        end
    end
    return slots
end

-- ---------------------------------------------------------------------------
-- The cleaner
-- ---------------------------------------------------------------------------

-- The entity under your cursor (or sub-target), or nil.
local function current_target()
    local t = AshitaCore:GetMemoryManager():GetTarget()
    local idx = t:GetIsSubTargetActive() == 0 and t:GetTargetIndex(0) or t:GetTargetIndex(1)
    if not idx or idx == 0 then return nil end
    return GetEntity(idx)
end

-- { id, name, zone, dropid } for a monster entity, or nil if it isn't one.
-- dropid is nil when the database has no drop list for it.
local function mob_from_entity(e)
    if not e or not e.ServerId or e.ServerId < 0x1000000 then return nil end
    if bit.band(e.SpawnFlags or 0, 0x10) == 0 then return nil end
    return { id = e.ServerId, name = e.Name, zone = math.floor(e.ServerId / 4096) % 4096,
             dropid = logic.dropid_for(db, e.ServerId) }
end

-- Treasure Hunter from what Tidy can see: your job/subjob trait plus your
-- equipped TH gear (capped 8 for a THF main, 4 otherwise), and the trait of any
-- Thief in your party (their gear can't be seen). Returns { level, why }.
local function estimate_th()
    local best, why = 0, 'no Treasure Hunter'
    pcall(function()
        local mm = AshitaCore:GetMemoryManager()
        local pl = mm:GetPlayer()
        local mj, ml, sj, sl = pl:GetMainJob(), pl:GetMainJobLevel(), pl:GetSubJob(), pl:GetSubJobLevel()
        local trait = logic.th_trait(mj, ml, sj, sl)
        local gear = 0
        if db and db.th_gear then
            local inv = mm:GetInventory()
            for slot = 0, 15 do
                local okq, eq = pcall(function() return inv:GetEquippedItem(slot) end)
                local packed = okq and eq and eq.Index or 0
                if packed ~= 0 then
                    local item = inv:GetContainerItem(bit.rshift(bit.band(packed, 0xFF00), 8), bit.band(packed, 0xFF))
                    gear = gear + (item and db.th_gear[item.Id] or 0)
                end
            end
        end
        best = logic.th_applied(mj, trait, gear)
        if best > 0 then
            why = string.format('you: trait %d + gear %d', trait, gear)
        end
        local party = mm:GetParty()
        for i = 1, 5 do
            if party:GetMemberIsActive(i) == 1 then
                local pmj = party:GetMemberMainJob(i)
                local t = logic.th_applied(pmj, logic.th_trait(pmj, party:GetMemberMainJobLevel(i),
                    party:GetMemberSubJob(i), party:GetMemberSubJobLevel(i)), 0)
                if t > best then
                    best, why = t, string.format('%s: Thief trait', party:GetMemberName(i) or 'party member')
                end
            end
        end
    end)
    return { level = best, why = why }
end

-- The TH used for drop rates now: { level, how, why }.
local function th_now()
    if (S.th_override or -1) >= 0 then
        return { level = S.th_override, how = 'set', why = 'set by you (/tidy th auto to undo)' }
    end
    local seen = fighting and th_seen[fighting.id] and th_seen[fighting.id].level
    if seen then
        return { level = seen, how = 'seen', why = 'exact: announced by the server' }
    end
    return { level = th_est.level, how = 'est.', why = 'estimated: ' .. th_est.why .. ' (a proc message makes it exact)' }
end

-- Read the mob you're fighting and learn its drop list for Hunt auto. Runs even
-- with Tidy off, so the window can show it. Sources, in order: the monster your
-- character is attacking (what the game says you're engaged on), then your cursor
-- target. Not engaged: the monster under your cursor is shown as "Target".
local last_watch = 0
local function watch_fight(now)
    if now - last_watch < SCAN_EVERY then return end
    last_watch = now
    fighting, targeted, fight_note = nil, nil, nil
    if not db then fight_note = 'Mob database not loaded.' return end
    local ok, e = pcall(function()
        local mm = AshitaCore:GetMemoryManager()
        local me_idx = mm:GetParty():GetMemberTargetIndex(0)
        local me = GetPlayerEntity()
        local engaged = me ~= nil and me.Status == 1                  -- 1 = engaged

        local mob = nil
        if engaged then
            local ok2, idx = pcall(function() return mm:GetEntity():GetTargetedIndex(me_idx) end)
            if ok2 and idx and idx > 0 then mob = mob_from_entity(GetEntity(idx)) end
        end
        if not mob then mob = mob_from_entity(current_target()) end

        if not engaged then
            targeted = mob
            return
        end
        if not mob then
            fight_note = 'Engaged, but Tidy can\'t see your mob -- put your cursor on it.'
        elseif not mob.dropid then
            fight_note = string.format('%s has no drop list in the database.', mob.name or 'This mob')
        else
            fighting = mob
            local l = learned[mob.dropid]
            if type(l) == 'table' then
                l.at = now
                if not l.name or l.name == 'Unknown mob' then l.name = mob.name end
            else
                learned[mob.dropid] = { name = mob.name, zone = mob.zone, at = now }
            end
        end
    end)
    if not ok then fighting, targeted, fight_note = nil, nil, 'Fight read failed: ' .. tostring(e) end

    -- A mob that died or that you left starts at TH 0 next time.
    local id = fighting and fighting.id or nil
    if last_fight_id and last_fight_id ~= id then th_seen[last_fight_id] = nil end
    last_fight_id = id
    if id and th_seen[id] == nil and th_recent and now - th_recent.at < 30
        and th_recent.name == (fighting.name or ''):lower() then
        th_seen[id] = { level = th_recent.level, at = now }
    end
    -- Mobs others fought: forget after 10 minutes (it may have died and respawned at TH 0).
    for mob, t in pairs(th_seen) do
        if mob == id then t.at = now elseif now - t.at > 600 then th_seen[mob] = nil end
    end
    th_est = estimate_th()
end

local function tick()
    if not S then return end
    watch_fight(os.clock())
    if not S.enabled or paused then return end
    local now = os.clock()
    if now - last_drop < DROP_GAP then return end   -- spacing between drops
    if now - last_scan < SCAN_EVERY then return end
    last_scan = now
    if not in_game() then
        sent = {}
        return
    end

    local ok, drops = pcall(function()
        local slots = read_inventory()
        local trash = logic.trash_map(db, profile(), learned, logic.extra_list(S))
        for id in pairs(baseline) do
            if trash[id] ~= 'loot' then baseline[id] = nil end
        end
        logic.update_baseline(baseline, slots, trash)
        return logic.plan(slots, trash, sent, now, baseline)
    end)
    if not ok then
        err('Inventory read failed: %s', tostring(drops))
        return
    end

    local d = drops[1]      -- one drop per pass; the next comes DROP_GAP later
    if not d then return end
    AshitaCore:GetPacketManager():AddOutgoingPacket(0x28, logic.drop_packet(d.bag, d.index, d.count))
    logic.mark_sent(sent, d, now)
    last_drop = now

    local name = item_name(d.id)
    local info = db and db.items[d.id]
    local value = (info and info[1] or 0) * d.count
    table.insert(log, 1, { time = os.date('%H:%M:%S'), name = name, count = d.count, value = value })
    while #log > LOG_SIZE do table.remove(log) end
    stats.stacks, stats.items, stats.value = stats.stacks + 1, stats.items + d.count, stats.value + value
    flash = { text = string.format('%s x%d', name, d.count), at = now }
    say('Dropped %s x%d', name, d.count)
end

-- ---------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------

local function add_by_name(name)
    local id, real = item_id(name)
    if not id then return err('No item named "%s".', tostring(name)) end
    local ok, msg = logic.add_item(profile(), id, real)
    if ok then save() say('%s', msg) else err('%s', msg) end
end

local function remove_by_name(name)
    local id = item_id(name)
    if not id then
        -- Also allow removing by the stored name (e.g. an item the client can't look up).
        for _, it in ipairs(profile().items) do
            if it.name and it.name:lower() == (name or ''):lower() then id = it.id end
        end
    end
    if not id then return err('No item named "%s".', tostring(name)) end
    local ok, msg = logic.remove_item(profile(), id)
    if ok then save() say('%s', msg) else err('%s', msg) end
end

local function zone_name(z)
    return (db and db.zone_names[z]) or ('zone ' .. tostring(z))
end

local function hunt_target()
    if not db then return err('Mob database not loaded (data/mobdb.lua).') end
    -- The monster under your cursor, or else the one you're engaged on.
    local mob = mob_from_entity(current_target()) or fighting
    if not mob then return err('Target a monster (or engage one) first.') end
    if not mob.dropid then return err('%s has no drop list in the database.', tostring(mob.name)) end
    local ok, msg = logic.add_mob(profile(), { id = mob.id, name = mob.name, zone = mob.zone, dropid = mob.dropid })
    if ok then save() say('%s', msg) else err('%s', msg) end
end

local function want_by_name(name)
    local id, real = item_id(name)
    if not id then return err('No item named "%s".', tostring(name)) end
    local on = logic.toggle_want(profile(), id, real)
    save()
    say('%s %s.', real, on and 'marked WANT -- always kept' or 'no longer wanted')
end

-- /tidy why: what Tidy sees right now and, for every item in your inventory that
-- it knows about, whether it will be dropped and why not.
local function why()
    local p = profile()
    local h = logic.hunt(p)
    say('Tidy is %s. Profile: %s. Database: %s.', S.enabled and 'ON' or 'OFF (type /tidy on)',
        S.active, db and 'loaded' or 'MISSING')
    say('In game: %s. Fighting: %s. Mobs learned: %d. Auto: %s, keep value %d, keep Rare/Ex %s.',
        tostring(in_game()), fighting and (fighting.name .. ' (drop list ' .. fighting.dropid .. ')')
            or fight_note or 'none',
        (function() local n = 0 for _ in pairs(learned) do n = n + 1 end return n end)(),
        h.auto and 'on' or 'off', h.keep_value or 0, h.keep_rare and 'yes' or 'no')

    local ok, slots = pcall(read_inventory)
    if not ok then return err('Inventory read failed: %s', tostring(slots)) end
    local extra = logic.extra_list(S)
    local trash = logic.trash_map(db, p, learned, extra)
    local totals = logic.totals(slots)
    local shown, any = {}, false
    for _, s in ipairs(slots) do
        if s.index > 0 and not shown[s.id] then
            shown[s.id] = true
            local kind = trash[s.id]
            local name = item_name(s.id)
            local reason = nil
            if kind == true then
                reason = (s.flags or 0) ~= 0 and 'on trash list, but equipped/bazaar -- never dropped'
                    or 'on trash list -> DROPS'
            elseif kind == 'loot' then
                local have, base = totals[s.id] or 0, baseline[s.id]
                if base == nil then
                    reason = 'mob loot -> starts tracking on the next check'
                elseif have > base then
                    reason = string.format('mob loot, %d new -> DROPS', have - base)
                else
                    reason = string.format('mob loot, but you had %d before -> kept (only NEW loot drops)', base)
                end
            elseif db then
                -- On a drop list Tidy knows, but kept: say which rule kept it.
                local v = logic.verdict(db, h, s.id)
                local known = false
                for d in pairs(learned) do
                    for _, row in ipairs(logic.drop_rows(db, d)) do if row.item == s.id then known = true end end
                end
                for _, m in ipairs(h.mobs) do
                    for _, row in ipairs(logic.drop_rows(db, m.dropid)) do if row.item == s.id then known = true end end
                end
                local x = logic.find_extra(extra, s.id)
                if x and not known then
                    known = true
                    if x.mode == 'keep' then v = 'xkeep' end
                    if v == 'trash' then v = 'xidle' end
                end
                if known then
                    reason = ({ want = 'kept: marked Want', rare = 'kept: Rare/Ex',
                        value = string.format('kept: worth %dg+ (Keep value)', h.keep_value or 0),
                        trash = (h.auto and 'kept' or 'kept: Auto is off'),
                        xkeep = 'kept: Extra drop set to Keep',
                        xidle = 'kept: Extra drop, waiting for a fight (or a pinned mob)' })[v]
                end
            end
            if reason then
                any = true
                say('  %s x%d: %s', name, totals[s.id] or 0, reason)
            end
        end
    end
    if not any then
        say('  Nothing in your inventory is on a trash list or a known mob drop list.')
    end
end

-- /tidy drop <item>: drop one stack of an item right now -- a direct test that the
-- game accepts Tidy's drop packets. Ignores profiles and rules (never gil/equipped).
local function drop_now(name)
    local id, real = item_id(name)
    if not id then return err('No item named "%s".', tostring(name)) end
    local ok, slots = pcall(read_inventory)
    if not ok then return err('Inventory read failed.') end
    for _, s in ipairs(slots) do
        if s.index > 0 and s.id == id and (s.flags or 0) == 0 then
            AshitaCore:GetPacketManager():AddOutgoingPacket(0x28, logic.drop_packet(s.bag, s.index, s.count))
            say('Sent drop for %s x%d (slot %d). If it is still in your bag in a few seconds, the server is refusing the drop packet.',
                real, s.count, s.index)
            return
        end
    end
    err('No droppable %s in your inventory.', real)
end

-- Extra drops by name.
local function extra_by_name(verb, name)
    local list = logic.extra_list(S)
    local id, real = item_id(name)
    if not id then
        for _, x in ipairs(list) do
            if x.name and x.name:lower() == (name or ''):lower() then id, real = x.id, x.name end
        end
    end
    if not id then return err('No item named "%s".', tostring(name)) end
    local ok, msg
    if verb == 'add' then
        ok, msg = logic.add_extra(list, id, real, 'rules')
    elseif verb == 'remove' or verb == 'rm' then
        ok, msg = logic.remove_extra(list, id)
    else
        local x = logic.find_extra(list, id)
        if not x then
            ok, msg = logic.add_extra(list, id, real, verb)
        else
            x.mode, x.learned = verb, false
            ok, msg = true, string.format('%s: %s.', real, verb == 'keep' and 'always kept' or 'keep rules decide')
        end
    end
    if ok then save() say('%s', msg) else err('%s', msg) end
end

extra_command = function(args)
    local verb = args[3] and args[3]:lower() or nil
    local name = table.concat(args, ' ', 4)
    if verb == nil or verb == 'list' then
        local list = logic.extra_list(S)
        say('Extra drops (%d), learning %s:', #list, S.extra_learn ~= false and 'ON' or 'OFF')
        for _, x in ipairs(list) do
            say('  %s: %s%s', x.name or ('#' .. x.id), x.mode == 'keep' and 'Keep' or 'Rules',
                x.from and (' (seen from ' .. x.from .. ')') or '')
        end
    elseif verb == 'learn' then
        if args[4] then S.extra_learn = args[4]:lower() == 'on' else S.extra_learn = S.extra_learn == false end
        save()
        say('Learning Extra drops from loot: %s.', S.extra_learn and 'ON' or 'OFF')
    elseif verb == 'add' or verb == 'remove' or verb == 'rm' or verb == 'keep' or verb == 'rules' then
        extra_by_name(verb, name)
    else
        err('Usage: /tidy extra [add|remove|keep|rules <item> | learn on|off]')
    end
end

set_paused = function(on)
    paused = on
    if not on then sent = {} end
    say('%s', paused and 'Paused -- nothing is dropped until you resume (/tidy pause).' or 'Resumed.')
end

reload = function()
    save()
    local ok = pcall(function() AshitaCore:GetChatManager():QueueCommand(-1, '/addon reload tidy') end)
    if not ok then err('Could not reload -- type /addon reload tidy') end
end

local function help()
    say('Tidy v%s by %s', addon.version, addon.author)
    say('/tidy  open the window')
    say('/tidy on | off  start / stop dropping')
    say('/tidy add <item>  /tidy remove <item>  /tidy list')
    say('/tidy profile [<name> | new <name>]')
    say('/tidy hunt (adds your target) | /tidy hunt clear | /tidy want <item>')
    say('/tidy hunt auto [on|off] | /tidy hunt forget | /tidy hunt value <gil>')
    say('/tidy extra [add|remove|keep|rules <item> | learn on|off]  (drops not on any list)')
    say('/tidy mini (fold/unfold the window) | /tidy lock | /tidy opacity 30-100 | /tidy pause | /tidy reload')
    say('/tidy th [auto | 0-14]  (Treasure Hunter used for drop rates)')
    say('/tidy why  (why each item is or isn\'t dropped) | /tidy drop <item>  (test a drop now)')
end

ashita.events.register('command', 'tidy_command', function(e)
    local args = e.command:args()
    if #args == 0 or args[1]:lower() ~= '/tidy' then return end
    e.blocked = true
    if not S then return end

    local sub = args[2] and args[2]:lower() or nil
    local rest = table.concat(args, ' ', 3)

    if sub == nil then
        ui.open[1] = not ui.open[1]
        S.ui_open = ui.open[1]
        save()
    elseif sub == 'on' or sub == 'off' then
        S.enabled = (sub == 'on')
        reset_tracking()
        save()
        say('Tidy %s (profile: %s, %d items).', S.enabled and 'ON -- dropping trash' or 'OFF',
            S.active, #profile().items)
    elseif sub == 'add' then
        add_by_name(rest)
    elseif sub == 'remove' or sub == 'rm' or sub == 'del' then
        remove_by_name(rest)
    elseif sub == 'list' then
        local items = profile().items
        say('Trash list "%s" (%d):', S.active, #items)
        for _, it in ipairs(items) do say('  %s', it.name or ('#' .. it.id)) end
    elseif sub == 'profile' then
        local a3 = args[3] and args[3]:lower() or nil
        if not a3 then
            say('Profiles: %s (active: %s)', table.concat(logic.profile_names(S), ', '), S.active)
        elseif a3 == 'new' then
            local ok, msg = logic.new_profile(S, table.concat(args, ' ', 4))
            if ok then save() say('%s', msg) else err('%s', msg) end
        else
            local stored = logic.find_profile(S, rest)
            if stored then
                S.active = stored
                reset_tracking()
                save()
                say('Profile: %s (%d items).', stored, #profile().items)
            else
                err('No profile named "%s".', rest)
            end
        end
    elseif sub == 'hunt' then
        local a3 = args[3] and args[3]:lower() or nil
        if a3 == 'clear' then
            logic.hunt(profile()).mobs = {}
            save()
            say('Hunt cleared.')
        elseif a3 == 'auto' or a3 == 'any' then
            local h = logic.hunt(profile())
            if args[4] then h.auto = args[4]:lower() == 'on' else h.auto = not h.auto end
            save()
            say('Auto (mobs you fight): %s.', h.auto and 'ON' or 'OFF')
        elseif a3 == 'forget' then
            learned = {}
            say('Forgot the mobs fought this session.')
        elseif a3 == 'value' and tonumber(args[4]) then
            logic.hunt(profile()).keep_value = math.max(0, math.floor(tonumber(args[4])))
            save()
            say('Keep anything worth %d+ gil (NPC).', logic.hunt(profile()).keep_value)
        else
            hunt_target()
        end
    elseif sub == 'want' then
        want_by_name(rest)
    elseif sub == 'extra' then
        extra_command(args)
    elseif sub == 'th' then
        local a3 = args[3] and args[3]:lower() or nil
        if a3 == 'auto' then
            S.th_override = -1
            save()
        elseif tonumber(a3) then
            S.th_override = math.max(0, math.min(logic.TH_MAX, math.floor(tonumber(a3))))
            save()
        end
        local t = th_now()
        say('Treasure Hunter for drop rates: %d (%s).', t.level, t.why)
    elseif sub == 'lock' or sub == 'unlock' then
        local w = (args[3] or ''):lower()
        if sub == 'unlock' or w == 'off' then set_locked(false)
        elseif w == 'on' then set_locked(true)
        else set_locked(not S.locked) end
    elseif sub == 'opacity' then
        local v = tonumber(args[3] or '')
        if not v or v < 30 or v > 100 then return err('Use /tidy opacity 30-100 (100 = solid).') end
        S.opacity = math.floor(v)
        save()
        say('Window opacity %d (100 = solid).', S.opacity)
    elseif sub == 'mini' then
        ui.open[1] = true
        S.ui_open, S.ui_mini = true, not S.ui_mini
        save()
    elseif sub == 'pause' then
        set_paused(not paused)
    elseif sub == 'reload' then
        reload()
    elseif sub == 'why' then
        why()
    elseif sub == 'drop' then
        drop_now(rest)
    elseif sub == 'help' then
        help()
    else
        err('Unknown command. /tidy help')
    end
end)

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

-- ImGui's Text/TextColored/SetTooltip treat the string as a printf format: a '%'
-- in it (e.g. '24.0% 148g') makes ImGui read arguments that were never passed and
-- can crash the game client. Everything shown goes through these, which strip '%'.
local function clean(s) return (tostring(s or ''):gsub('%%', '')) end
local function text(s) imgui.Text(clean(s)) end
local function ctext(col, s) imgui.TextColored(col, clean(s)) end
local function tip(s) imgui.SetTooltip(clean(s)) end
local function hover(s) if imgui.IsItemHovered() then tip(s) end end

-- Pushes/combos/child panels that must be closed even if the window code errors
-- part way: an unbalanced ImGui stack is another way to crash the client.
local width_depth, combo_open, color_depth, child_open = 0, false, 0, false
local function push_width(w) imgui.PushItemWidth(w) width_depth = width_depth + 1 end
local function pop_width() imgui.PopItemWidth() width_depth = width_depth - 1 end

-- Tidy's look: Final Fantasy XV's menus. Smoked blue-black glass, white type
-- with letter-spaced headings, hairlines that fade out at their ends, a bright
-- light band behind the chosen row with a dark chevron, square key-cap buttons.
-- Pale FFXV blue = on / kept / wanted, a muted red = what gets dropped, soft
-- gold = gil, periwinkle = places and extras. Folded, Tidy is a green crystal.
local function rgb(hex, a)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
             tonumber(hex:sub(5, 6), 16) / 255, a or 1.0 }
end
local INK      = rgb('0b1018', 0.82)    -- blue-black glass (alpha replaced by the opacity setting)
local MINT     = rgb('8fd3ff')          -- FFXV pale blue: on, kept, wanted
local MINT_HI  = rgb('e6f4ff')
local ON_MINT  = rgb('0b1018')
local RED      = rgb('e25c5c')          -- muted red: dropped
local GREEN    = MINT                   -- kept
local GRAY     = rgb('9aa5b1')
local SOOT     = rgb('5f6b78')
local CHALK    = rgb('c9d2dc')
local GOLD     = rgb('d9b36c')          -- soft gold: gil
local SUN      = rgb('3f6f99')          -- deep steel blue (the start of the slider's fill)
local LAV      = rgb('a9b6ff')          -- periwinkle: places, extras
local WHITE    = rgb('f3f6fa')
local RULE     = { 0.86, 0.92, 1.00, 0.25 } -- hairline
local VIOLET   = LAV
local LINE     = rgb('dbe9ff')          -- the hairlines' colour
local DEEP     = rgb('0b1018')          -- dark ink on the light band
local NEON, NEON2 = SUN, MINT
local FRAME    = rgb('17202c')
local FRAME_HI = rgb('223041')
local DARK     = { 0.05, 0.07, 0.10, 1 }
local DARK_HI  = { 0.09, 0.12, 0.17, 1 }
local DARK_ACT = { 0.12, 0.16, 0.22, 1 }

local RADIUS   = 0                      -- square corners (cinematic menu look)
local RALL     = ImDrawFlags_RoundCornersAll or ImDrawCornerFlags_All or 15   -- round all four corners
local SIDE_W   = 136                    -- the sidebar
local SIDE_GAP = 26                     -- between the sidebar and the page
local NAV_H    = 28                     -- one page row in the sidebar

-- Window-wide style, pushed around Begin/End. Each entry is skipped if this
-- Ashita build doesn't define the constant, and the counts pop exactly what was pushed.
local STYLE_COLORS = {
    { 'ImGuiCol_WindowBg',          { INK[1], INK[2], INK[3], 0.92 } },
    { 'ImGuiCol_ChildBg',           { 0, 0, 0, 0 } },
    { 'ImGuiCol_PopupBg',           rgb('0c1119', 0.97) },
    { 'ImGuiCol_Border',            { 1, 1, 1, 0.20 } },        -- hairline frames round buttons and fields
    { 'ImGuiCol_Text',              WHITE },
    { 'ImGuiCol_TextDisabled',      GRAY },
    { 'ImGuiCol_FrameBg',           { 1, 1, 1, 0.035 } },
    { 'ImGuiCol_FrameBgHovered',    { 1, 1, 1, 0.07 } },
    { 'ImGuiCol_FrameBgActive',     rgb('8fd3ff', 0.14) },
    { 'ImGuiCol_Button',            { 1, 1, 1, 0.02 } },
    { 'ImGuiCol_ButtonHovered',     { 1, 1, 1, 0.10 } },
    { 'ImGuiCol_ButtonActive',      rgb('8fd3ff', 0.25) },
    { 'ImGuiCol_Header',            rgb('8fd3ff', 0.14) },
    { 'ImGuiCol_HeaderHovered',     { 1, 1, 1, 0.08 } },
    { 'ImGuiCol_HeaderActive',      rgb('8fd3ff', 0.22) },
    { 'ImGuiCol_Separator',         { 1, 1, 1, 0.07 } },
    { 'ImGuiCol_CheckMark',         MINT },
    { 'ImGuiCol_SliderGrab',        WHITE },
    { 'ImGuiCol_SliderGrabActive',  MINT },
    { 'ImGuiCol_ScrollbarBg',       { 0, 0, 0, 0 } },
    { 'ImGuiCol_ScrollbarGrab',     { 1, 1, 1, 0.22 } },
    { 'ImGuiCol_ScrollbarGrabHovered', { 1, 1, 1, 0.40 } },
    { 'ImGuiCol_ScrollbarGrabActive', MINT },
    { 'ImGuiCol_TextSelectedBg',    rgb('8fd3ff', 0.30) },
}
local STYLE_VARS = {
    { 'ImGuiStyleVar_WindowRounding',   0 },
    { 'ImGuiStyleVar_ChildRounding',    0 },
    { 'ImGuiStyleVar_FrameRounding',    0 },
    { 'ImGuiStyleVar_PopupRounding',    0 },
    { 'ImGuiStyleVar_GrabRounding',     0 },
    { 'ImGuiStyleVar_ScrollbarRounding', 0 },
    { 'ImGuiStyleVar_WindowBorderSize', 0 },
    { 'ImGuiStyleVar_ChildBorderSize',  0 },
    { 'ImGuiStyleVar_FrameBorderSize',  1 },
    { 'ImGuiStyleVar_PopupBorderSize',  1 },
    { 'ImGuiStyleVar_WindowPadding',    { 16, 14 } },
    { 'ImGuiStyleVar_FramePadding',     { 9, 3 } },
    { 'ImGuiStyleVar_ItemSpacing',      { 7, 5 } },
    { 'ImGuiStyleVar_ScrollbarSize',    6 },
}
local function push_style()
    local nc, nv = 0, 0
    -- The panel's see-through-ness comes from the opacity setting (30-100).
    local o = math.max(30, math.min(100, (S and S.opacity) or 82)) / 100
    for _, c in ipairs(STYLE_COLORS) do
        local id = _G[c[1]]
        local col = c[2]
        if c[1] == 'ImGuiCol_WindowBg' then col = { 0, 0, 0, 0 } end   -- the glass is drawn by hand (glass())
        if type(id) == 'number' and pcall(imgui.PushStyleColor, id, col) then nc = nc + 1 end
    end
    for _, v in ipairs(STYLE_VARS) do
        local id = _G[v[1]]
        local val = v[2]
        if v[1] == 'ImGuiStyleVar_WindowPadding' and S and S.ui_mini then val = { 2, 2 } end  -- the folded crystal
        if type(id) == 'number' and pcall(imgui.PushStyleVar, id, val) then nv = nv + 1 end
    end
    return nc, nv
end
local function pop_style(nc, nv)
    if nv > 0 then imgui.PopStyleVar(nv) end
    if nc > 0 then imgui.PopStyleColor(nc) end
end

-- Button colors for one widget (counted, so an error mid-draw still pops them).
local function push_button_colors(bg, hi, fg)
    local n = 0
    for _, c in ipairs({ { 'ImGuiCol_Button', bg }, { 'ImGuiCol_ButtonHovered', hi },
                         { 'ImGuiCol_ButtonActive', bg }, { 'ImGuiCol_Text', fg } }) do
        local id = _G[c[1]]
        if type(id) == 'number' and pcall(imgui.PushStyleColor, id, c[2]) then n = n + 1 end
    end
    color_depth = color_depth + n
    return n
end
local function pop_colors(n)
    if n > 0 then imgui.PopStyleColor(n) end
    color_depth = color_depth - n
end

-- A solid toggle: pale blue pill with ink type when active, quiet when not.
local function pill(label, active)
    local n = active and push_button_colors(MINT, MINT_HI, ON_MINT) or 0
    local clicked = imgui.Button(label)
    pop_colors(n)
    return clicked
end

-- Drawing straight onto the window. All optional: if this Ashita build's draw
-- list differs, the decoration is skipped and the window still works.
local function with_alpha(c, a) return { c[1], c[2], c[3], a } end
local function col32(c) return imgui.GetColorU32(c) end
local function xy(a, b)
    if type(a) == 'table' then return a.x or a[1], a.y or a[2] end
    return a, b
end
local function num(v, d) return type(v) == 'number' and v or d end
local function decorate(fn) pcall(fn, imgui.GetWindowDrawList()) end
local function cursor() local x, y = xy(imgui.GetCursorScreenPos()) return num(x, 0), num(y, 0) end
local function text_w(s) return num((xy(imgui.CalcTextSize(s))), 7 * #s) end
local function line_h() return num(imgui.GetTextLineHeight(), 13) end
local function frame_h() return num(imgui.GetFrameHeight(), line_h() + 6) end
local function mouse() local x, y = xy(imgui.GetMousePos()) return num(x, -1), num(y, -1) end

-- Two colors blended (t = 0..1).
local function mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, (a[4] or 1) + ((b[4] or 1) - (a[4] or 1)) * t }
end
-- A left-to-right gradient bar (one colour if this build can't do gradients).
local function gradient(dl, x1, y1, x2, y2, a, b)
    if not pcall(function() dl:AddRectFilledMultiColor({ x1, y1 }, { x2, y2 }, col32(a), col32(b), col32(b), col32(a)) end) then
        dl:AddRectFilled({ x1, y1 }, { x2, y2 }, col32(a))
    end
end
-- YunaUI's mark: a small diamond outline, filled inside when it's lit.
local function diamond(dl, cx, cy, r, lit, a)
    a = a or 1
    local c = col32(lit and with_alpha(NEON2, a) or { 0.60, 0.64, 0.70, a })
    dl:AddLine({ cx, cy - r }, { cx + r, cy }, c, 1.4)
    dl:AddLine({ cx + r, cy }, { cx, cy + r }, c, 1.4)
    dl:AddLine({ cx, cy + r }, { cx - r, cy }, c, 1.4)
    dl:AddLine({ cx - r, cy }, { cx, cy - r }, c, 1.4)
    local q = r * 0.45
    local f = col32(lit and { 0.90, 0.96, 1, a } or { 0.52, 0.56, 0.62, a * 0.8 })
    pcall(function()
        dl:AddTriangleFilled({ cx, cy - q }, { cx + q, cy }, { cx, cy + q }, f)
        dl:AddTriangleFilled({ cx, cy + q }, { cx - q, cy }, { cx, cy - q }, f)
    end)
end

-- The cinematic look's pieces, in Tidy's colours.
-- A hairline that fades out at both ends.
local function rule(dl, x1, x2, y, c, a)
    local mid = (x1 + x2) / 2
    local c0, c1 = col32(with_alpha(c, 0)), col32(with_alpha(c, a or 0.35))
    if not pcall(function()
        dl:AddRectFilledMultiColor({ x1, y }, { mid, y + 1 }, c0, c1, c1, c0)
        dl:AddRectFilledMultiColor({ mid, y }, { x2, y + 1 }, c1, c0, c0, c1)
    end) then dl:AddLine({ x1, y }, { x2, y }, c1, 1) end
end
-- A light band, bright on the left and fading right (the selected row).
local function band(dl, x1, y1, x2, y2, c, a)
    gradient(dl, x1, y1, x2, y2, with_alpha(c, a or 0.6), with_alpha(c, 0))
end
local function chevron(dl, x, y, s, c)
    dl:AddTriangleFilled({ x, y - s }, { x + s, y }, { x, y + s }, col32(c))
end
-- The glass: blue-black shading to near black, see-through by the opacity
-- setting, with white hairlines along the top and bottom and a cool sheen.
local function glass()
    decorate(function(dl)
        local wx, wy = xy(imgui.GetWindowPos())
        local ww, wh = xy(imgui.GetWindowSize())
        if type(wx) ~= 'number' or type(ww) ~= 'number' then return end
        local o = math.max(30, math.min(100, (S and S.opacity) or 82)) / 100
        local t, b = col32(rgb('121a25', o)), col32(rgb('020306', o))
        if not pcall(function() dl:AddRectFilledMultiColor({ wx, wy }, { wx + ww, wy + wh }, t, t, b, b) end) then
            dl:AddRectFilled({ wx, wy }, { wx + ww, wy + wh }, t)
        end
        band(dl, wx, wy, wx + ww * 0.55, wy + 70, LINE, 0.05)         -- a cool sheen top left
        rule(dl, wx, wx + ww, wy, LINE, 0.80)
        rule(dl, wx, wx + ww, wy + wh - 1, LINE, 0.35)
    end)
end

-- Letter-spaced capitals for small labels.
local function track(t) return (clean(t):upper():gsub('(.)', '%1 '):gsub(' $', '')) end

local ROW_W = 360            -- the page column, set each frame from the window's width

-- Tooltips: a dark glass card, a faint white edge and a pale blue line along the
-- top that fades out; the first line bright, the rest softer.
tip = function(s)
    s = clean(s)
    if imgui.BeginTooltip == nil then return imgui.SetTooltip(s) end
    local nv, nc = 0, 0
    for _, v in ipairs({ { 'ImGuiStyleVar_WindowRounding', 0 }, { 'ImGuiStyleVar_WindowPadding', { 9, 5 } },
                         { 'ImGuiStyleVar_WindowBorderSize', 1 } }) do
        local id = _G[v[1]]
        if type(id) == 'number' and pcall(imgui.PushStyleVar, id, v[2]) then nv = nv + 1 end
    end
    for _, c in ipairs({ { 'ImGuiCol_PopupBg', rgb('0a0e15', 0.97) }, { 'ImGuiCol_Border', { 1, 1, 1, 0.18 } } }) do
        local id = _G[c[1]]
        if type(id) == 'number' and pcall(imgui.PushStyleColor, id, c[2]) then nc = nc + 1 end
    end
    if imgui.BeginTooltip() == false then
        imgui.SetTooltip(s)
    else
        pcall(function()
            local first = true
            for l in (s .. '\n'):gmatch('([^\n]*)\n') do
                if first then imgui.Text(l) else imgui.TextColored(CHALK, l) end
                first = false
            end
            decorate(function(dl)
                local wx, wy = xy(imgui.GetWindowPos())
                local ww = xy(imgui.GetWindowSize())
                gradient(dl, wx + 8, wy + 1, wx + ww - 8, wy + 2, MINT, with_alpha(MINT, 0))
            end)
        end)
        imgui.EndTooltip()
    end
    if nc > 0 then imgui.PopStyleColor(nc) end
    if nv > 0 then imgui.PopStyleVar(nv) end
end

-- Section heading: the name in spaced capitals, a faint line on to the edge.
local function section(label)
    imgui.Dummy({ 1, 6 })
    local head, rest = label:match('^(.-)%s*(%(.*%))$')   -- letter-space the name, not the note
    if not head then head, rest = label:match('^(.-)%s+%-%-%s+(.*)$') end
    local x, y = cursor()
    ctext({ 0.93, 0.96, 1.00, 1 }, track(head or label))
    local ex = x + text_w(track(head or label))
    if rest then
        imgui.SameLine(0, 10)
        ctext(SOOT, rest:lower())
        ex = ex + 10 + text_w(rest)
    end
    decorate(function(dl)
        local cy = y + line_h() / 2
        if ex + 14 < x + ROW_W then rule(dl, ex + 14, x + ROW_W + 40, cy, LINE, 0.3) end
    end)
    imgui.Dummy({ 1, 2 })
end

-- Faint flat band behind every other row of a table.
local function stripe(on)
    if not on then return end
    decorate(function(dl)
        local x, y = cursor()
        dl:AddRectFilled({ x - 4, y - 1 }, { x + ROW_W, y + num(imgui.GetTextLineHeightWithSpacing(), 17) - 1 },
            col32({ 1, 1, 1, 0.025 }))
    end)
end

local function scaled(scale, col, t)
    pcall(imgui.SetWindowFontScale, scale)
    ctext(col, t)
    pcall(imgui.SetWindowFontScale, 1.0)
end

-- A colored tag (DROP / WANT / VALUE / RARE / KEEP); looks like a chip, does nothing.
local function chip(label, col, id)
    local n = push_button_colors(with_alpha(col, 0.18), with_alpha(col, 0.18), col)
    imgui.SmallButton(label .. '##chip_' .. id)
    pop_colors(n)
end

-- An on/off toggle in the cinematic style: ON / OFF in spaced capitals and a
-- square check box at the right; the box fills pale blue when on.
local function switch(id, on)
    local x, y = cursor()
    local w, h = 44, 22
    local clicked = imgui.InvisibleButton(id, { w, h })
    local hov = imgui.IsItemHovered() == true
    decorate(function(dl)
        local bx, by, b = x + w - 15, y + (h - 14) / 2, 14
        dl:AddRect({ bx, by }, { bx + b, by + b }, col32(on and MINT or { 1, 1, 1, hov and 0.85 or 0.5 }), 0, RALL, 1)
        if on then
            dl:AddRectFilled({ bx + 3, by + 3 }, { bx + b - 3, by + b - 3 }, col32(MINT))
            dl:AddRect({ bx - 2, by - 2 }, { bx + b + 2, by + b + 2 }, col32(with_alpha(MINT, 0.25)), 0, RALL, 2)
        end
        local lbl = on and 'O N' or 'O F F'
        dl:AddText({ bx - 6 - text_w(lbl), y + (h - line_h()) / 2 }, col32(on and MINT or (hov and CHALK or SOOT)), lbl)
    end)
    return clicked
end

-- A setting on one line: its name on the left, a switch at the right edge.
local function row_switch(id, label, on, hint)
    imgui.AlignTextToFramePadding()
    ctext(WHITE, label)
    if hint then hover(hint) end
    imgui.SameLine(math.max(num(imgui.GetCursorPosX(), 0) + 10, ROW_W - 44))
    local clicked = switch(id, on)
    if hint then hover(hint) end
    return clicked
end

-- A slider on one line: the name, a hairline track filling pale blue, a white diamond knob, the
-- value at the end. Returns the value and true when you let go of it.
local function row_slider(id, label, value, lo, hi, fmt)
    imgui.AlignTextToFramePadding()
    ctext(WHITE, label)
    local shown = string.format(fmt or '%d', value)
    local tl = math.max(text_w(label) + 22, ROW_W * 0.34)
    local tr = ROW_W - math.max(text_w(shown), 40) - 16
    imgui.SameLine(tl)
    local x, y = cursor()
    local w, h = math.max(40, tr - tl), frame_h()
    imgui.InvisibleButton(id, { w, h })
    local active, hov = imgui.IsItemActive() == true, imgui.IsItemHovered() == true
    if active then
        local mx = mouse()
        local f = math.max(0, math.min(1, (mx - x) / w))
        value = math.floor(lo + f * (hi - lo) + 0.5)
        shown = string.format(fmt or '%d', value)
    end
    local done = imgui.IsItemDeactivated() == true
    decorate(function(dl)
        local f = math.max(0, math.min(1, (value - lo) / math.max(1, hi - lo)))
        local cy = y + h / 2
        dl:AddRectFilled({ x, cy - 1 }, { x + w, cy + 1 }, col32({ 1, 1, 1, 0.14 }))
        gradient(dl, x, cy - 1, x + w * f, cy + 1, NEON, NEON2)
        local kx = x + w * f
        if active or hov then dl:AddRectFilled({ kx - 8, cy - 8 }, { kx + 8, cy + 8 }, col32(with_alpha(NEON2, 0.22))) end
        dl:AddQuadFilled({ kx, cy - 6 }, { kx + 6, cy }, { kx, cy + 6 }, { kx - 6, cy }, col32({ 1, 1, 1, 1 }))
    end)
    imgui.SameLine(ROW_W - text_w(shown))
    ctext(WHITE, shown)
    return value, done
end

-- A key-cap button: its name in spaced capitals inside a square hairline
-- frame, pale blue for the main action, grey for quiet ones; a white light
-- band sweeps in when you hover.
local function neon_button(label, quiet, w)
    local name = track(label:gsub('##.*$', ''))
    local x, y = cursor()
    local bw, bh = w or (text_w(name) + 26), math.floor(frame_h() * 1.12)
    local clicked = imgui.InvisibleButton(label, { bw, bh })
    local hov, act = imgui.IsItemHovered() == true, imgui.IsItemActive() == true
    decorate(function(dl)
        dl:AddRectFilled({ x, y }, { x + bw, y + bh }, col32({ 0, 0, 0, 0.25 }))
        if hov or act then band(dl, x, y, x + bw, y + bh, LINE, act and 0.35 or 0.18) end
        dl:AddRect({ x, y }, { x + bw, y + bh }, col32(quiet and { 1, 1, 1, hov and 0.55 or 0.28 } or with_alpha(NEON2, hov and 1 or 0.8)), 0, RALL, 1)
        dl:AddText({ x + (bw - text_w(name)) / 2, y + (bh - line_h()) / 2 }, col32(WHITE), name)
    end)
    return clicked
end

-- A small round icon button (- and x in the corner).
local function round_button(label, glyph, danger)
    local x, y = cursor()
    local s = 22
    local clicked = imgui.InvisibleButton(label, { s, s })
    local hov = imgui.IsItemHovered() == true
    decorate(function(dl)
        local cx, cy, r = x + s / 2, y + s / 2, s * 0.2
        if hov then
            dl:AddRectFilled({ x, y }, { x + s, y + s }, col32(danger and with_alpha(RED, 0.30) or with_alpha(MINT, 0.16)))
            dl:AddRect({ x, y }, { x + s, y + s }, col32({ 1, 1, 1, 0.45 }), 0, RALL, 1)
        end
        local c = col32(hov and WHITE or with_alpha(CHALK, 0.85))
        r = s * 0.22
        if glyph == 'x' then
            dl:AddLine({ cx - r, cy - r }, { cx + r, cy + r }, c, 1.5)
            dl:AddLine({ cx - r, cy + r }, { cx + r, cy - r }, c, 1.5)
        else
            dl:AddLine({ cx - r, cy }, { cx + r, cy }, c, 1.5)
        end
    end)
    return clicked
end

local draw_window   -- the window body, defined below
local later = {}            -- changes made by buttons, applied after the lists are drawn
local function after(fn) later[#later + 1] = fn end

-- Search box for a list; returns the lowercase query ('' = show all).
local function search_box(key)
    ui.filter[key] = ui.filter[key] or { '' }
    push_width(200)
    imgui.InputText('Search##flt_' .. key, ui.filter[key], 48)
    pop_width()
    return (ui.filter[key][1] or ''):lower():match('^%s*(.-)%s*$')
end

-- Item names from the game client, for the pickers. Built a slice per frame the
-- first time a picker is typed in, so the game never stalls.
local INDEX_MAX, INDEX_STEP = 0x7FFF, 1500
local index = { list = {}, next = 1, done = false }
local function grow_index()
    if index.done then return end
    local rm = AshitaCore:GetResourceManager()
    local stop = math.min(index.next + INDEX_STEP - 1, INDEX_MAX)
    for id = index.next, stop do
        local ok, res = pcall(function() return rm:GetItemById(id) end)
        local nm = ok and res and res.Name and res.Name[1] or nil
        if nm and nm ~= '' and nm ~= '.' then
            index.list[#index.list + 1] = { id = id, name = nm, lname = nm:lower() }
        end
    end
    index.next = stop + 1
    if index.next > INDEX_MAX then
        index.done = true
        table.sort(index.list, function(a, b) return a.lname < b.lname end)
    end
end

-- Up to n items whose name contains q; names that start with q come first.
local function find_items(q, n)
    local first, rest = {}, {}
    for _, it in ipairs(index.list) do
        local at = it.lname:find(q, 1, true)
        if at == 1 then first[#first + 1] = it elseif at then rest[#rest + 1] = it end
        if #first >= n then break end
    end
    for _, it in ipairs(rest) do
        if #first >= n then break end
        first[#first + 1] = it
    end
    return first
end

-- Type-ahead item picker: type part of a name, click a match (or press Enter on
-- an exact name). on_pick(id, name) runs after the frame's lists are drawn.
local function item_picker(key, button, hint, on_pick)
    ui.pick[key] = ui.pick[key] or { '' }
    local buf = ui.pick[key]
    push_width(200)
    local entered = imgui.InputText('##pick_' .. key, buf, 64, ImGuiInputTextFlags_EnterReturnsTrue)
    pop_width()
    hover(hint)
    imgui.SameLine()
    if imgui.Button(button .. '##pickbtn_' .. key) or entered then
        local id, real = item_id(buf[1])
        if id then
            after(function() on_pick(id, real) end)
            buf[1] = ''
        else
            err('No item named "%s". Pick one from the list under the box.', tostring(buf[1]))
        end
        return
    end
    local q = (buf[1] or ''):lower():match('^%s*(.-)%s*$')
    if #q < 2 then return end
    grow_index()
    for _, it in ipairs(find_items(q, 8)) do
        if imgui.Selectable(clean(it.name) .. '##pk_' .. key .. '_' .. it.id, false) then
            local id, name = it.id, it.name
            after(function() on_pick(id, name) end)
            buf[1] = ''
        end
    end
    if not index.done then ctext(GRAY, '  (still loading item names...)') end
end

local function npc_value(id)
    local info = db and db.items[id]
    return info and info[1] or 0
end

local VERDICT_TAG = { want = 'WANT', rare = 'RARE', value = 'VALUE', trash = 'DROP', keep = 'KEEP' }
local VERDICT_COL = { want = MINT, rare = LAV, value = GOLD, trash = RED, keep = MINT }

-- One mob's drop table: verdict chip per item, Want/Unwant buttons.
local function drop_table(key, dropid, p, h)
    local th = th_now().level
    ctext(GRAY, string.format('  %-26s %5s %6s', 'Item', 'TH' .. th, 'NPC'))
    hover('Drops per 100 kills at Treasure Hunter ' .. th .. ' (CatsEyeXI scale). Hover a row for details.')
    local n = 0
    for _, row in ipairs(logic.drop_rows(db, dropid)) do
        n = n + 1
        stripe(n % 2 == 0)
        local v = logic.verdict(db, h, row.item)
        local nm = item_name(row.item)
        local short = #nm > 26 and (nm:sub(1, 25) .. '.') or nm
        local chance = logic.row_chance(row, th) / 100
        ctext(v == 'trash' and WHITE or MINT, string.format('  %-26s %5.1f %5dg', short, chance, npc_value(row.item)))
        if imgui.IsItemHovered() then
            local base = logic.row_chance(row, 0) / 100
            local detail = (row.group or 0) ~= 0
                and string.format('\nGroup %d: the group drops in %.1f of 100 kills, then one of its items by weight (%d of %d).',
                    row.group, logic.th_rate(th, (row.group_rate or 0) * 10) / 100, row.rate or 0, row.group_total or 0)
                or ''
            tip(string.format('%s\nDrops in %.1f of 100 kills with no TH, %.1f at TH%d.%s', nm, base, chance, th, detail))
        end
        imgui.SameLine()
        chip(VERDICT_TAG[v], VERDICT_COL[v], key .. '_' .. row.item)
        imgui.SameLine()
        if imgui.SmallButton((v == 'want' and 'Unwant' or 'Want') .. '##w_' .. key .. '_' .. row.item) then
            local id = row.item
            after(function() logic.toggle_want(p, id, item_name(id)) save() end)
        end
    end
    -- Extra drops ride along with every mob's table.
    for _, x in ipairs(logic.extra_list(S)) do
        n = n + 1
        stripe(n % 2 == 0)
        local v = x.mode == 'keep' and 'keep' or logic.verdict(db, h, x.id)
        local nm = x.name or item_name(x.id)
        local short = #nm > 26 and (nm:sub(1, 25) .. '.') or nm
        ctext(LAV, string.format('  %-26s %5s %5dg', short, 'extra', npc_value(x.id)))
        hover(nm .. ' -- Extra drop (not on the drop list). Change it on the Extra page.')
        imgui.SameLine()
        chip(VERDICT_TAG[v], VERDICT_COL[v], key .. '_x' .. x.id)
    end
end

-- Status mark: a pale blue dot with a slow pulsing halo while dropping, an amber dot
-- when paused, a dim dash when off.
local function status_dot()
    decorate(function(dl)
        local x, y = cursor()
        local cy = y + line_h() / 2 + 1
        if not S.enabled then
            dl:AddRectFilled({ x + 1, cy - 1 }, { x + 10, cy + 1 }, col32(SOOT))
        elseif paused then
            dl:AddCircleFilled({ x + 5, cy }, 4, col32(GOLD), 16)
        else
            local pulse = 0.25 + 0.25 * math.sin(os.clock() * 3)
            dl:AddCircleFilled({ x + 5, cy }, 8, col32(with_alpha(MINT, pulse * 0.6)), 16)
            dl:AddCircleFilled({ x + 5, cy }, 4, col32(MINT), 16)
        end
    end)
    imgui.Dummy({ 12, 1 })
end

-- The title: T I D Y in spaced white capitals after a small pale blue diamond,
-- a hairline under it that fades out at both ends.
local function wordmark(dl, x, y, size)
    local font = imgui.GetFont()
    local base = num(imgui.GetFontSize(), 13)
    local k = size / base
    local cy = y + size / 2
    local m = size * 0.20
    dl:AddQuadFilled({ x + m, cy - m }, { x + 2 * m, cy }, { x + m, cy + m }, { x, cy }, col32(with_alpha(MINT, 0.30)))
    for _, seg in ipairs({ { { x + m, cy - m }, { x + 2 * m, cy } }, { { x + 2 * m, cy }, { x + m, cy + m } },
                           { { x + m, cy + m }, { x, cy } }, { { x, cy }, { x + m, cy - m } } }) do
        dl:AddLine(seg[1], seg[2], col32(MINT), 1)
    end
    local cx = x + 2 * m + 10
    local word = 'TIDY'
    for i = 1, #word do
        local ch = word:sub(i, i)
        dl:AddText(font, size, { cx, y }, col32(WHITE), ch)
        cx = cx + text_w(ch) * k + size * 0.28                       -- wide letter spacing
    end
    local by = y + size + 6
    rule(dl, x - 4, x + SIDE_W + 4, by, LINE, 0.6)
    return by + 1
end

-- Pages, picked in the sidebar.
local PAGES = { 'Fight', 'Trash', 'Want', 'Pinned', 'Extra', 'Bag', 'Log', 'Settings' }

-- The sidebar: the wordmark and version, then one row per page. The open page
-- sits on FFXV's light band (bright on the left, fading right) in dark ink with
-- a chevron; a hovered one gets a faint band.
local function sidebar(x0, y0, counts)
    local bottom = y0 + 64
    decorate(function(dl)
        bottom = wordmark(dl, x0 + 4, y0 + 2, 30)
        dl:AddText({ x0 + 4, bottom + 6 }, col32(SOOT), track('Loot') .. '   v' .. addon.version)
        bottom = bottom + 6 + line_h()
    end)
    local y = bottom + 16
    for _, name in ipairs(PAGES) do
        local label = counts[name] and string.format('%s %d##pg_%s', name, counts[name], name) or (name .. '##pg_' .. name)
        local on = ui.page == name
        pcall(imgui.SetCursorScreenPos, { x0, y })
        if imgui.InvisibleButton(label, { SIDE_W, NAV_H }) then ui.page = name end
        local hov = imgui.IsItemHovered() == true
        decorate(function(dl)
            if on then
                band(dl, x0, y + 1, x0 + SIDE_W, y + NAV_H - 1, WHITE, 0.92)
                chevron(dl, x0 + 6, y + NAV_H / 2, 4, DEEP)
            elseif hov then
                band(dl, x0, y + 1, x0 + SIDE_W, y + NAV_H - 1, WHITE, 0.08)
            end
            local ty = y + (NAV_H - line_h()) / 2
            dl:AddText({ x0 + 18, ty }, col32(on and DEEP or (hov and WHITE or CHALK)), track(name))
            if not on then dl:AddLine({ x0 + 12, y + NAV_H + 1 }, { x0 + SIDE_W, y + NAV_H + 1 }, col32({ 1, 1, 1, 0.05 }), 1) end
            if counts[name] then
                local c = tostring(counts[name])
                dl:AddText({ x0 + SIDE_W - 10 - text_w(c), ty }, col32(on and WHITE or SOOT), c)
            end
        end)
        y = y + NAV_H + 3
    end
    -- Lock style: pins the window and the folded crystal where they are.
    y = y + 8
    pcall(imgui.SetCursorScreenPos, { x0 + 4, y + (22 - line_h()) / 2 })
    ctext(S.locked and MINT or SOOT, track(S.locked and 'Locked' or 'Lock'))
    hover(S.locked and 'Locked in place. Click the switch to move it again.' or 'Lock the window and the crystal in place.')
    pcall(imgui.SetCursorScreenPos, { x0 + SIDE_W - 44, y })
    if switch('##tidy_lock', S.locked) then after(function() set_locked(not S.locked) end) end
    hover(S.locked and 'Locked in place. Click to unlock (/tidy lock).' or 'Lock the window and the crystal in place (/tidy lock).')
    return y + 22
end

-- The line between the sidebar and the page: a faint white line fading at both ends.
local function divider(dl, x, y1, y2)
    local mid = (y1 + y2) / 2
    local c0, c1 = col32(with_alpha(LINE, 0)), col32(with_alpha(LINE, 0.22))
    if not pcall(function()
        dl:AddRectFilledMultiColor({ x - 2, y1 }, { x - 1, mid }, c0, c0, c1, c1)
        dl:AddRectFilledMultiColor({ x - 2, mid }, { x - 1, y2 }, c1, c1, c0, c0)
    end) then dl:AddLine({ x - 2, y1 }, { x - 2, y2 }, c1, 1) end
end

-- Tidy's folded icon: the FFXI home point crystal, in green, drawn with shapes
-- (no image files needed). A tall, slender shard of pale green light -- a
-- long point above, a short one below -- turning slowly and floating over a
-- glowing rune circle, with green flames licking up round its foot and a
-- glint now and then. dim = grey and still (Tidy off or paused).
local function crystal(dl, cx, cy, s, dim)
    local function c(r, g, b, a)
        r, g, b = math.min(1, r), math.min(1, g), math.min(1, b)
        if dim then local v = (r + g + b) / 3 return col32({ v, v, v, a or 1 }) end
        return col32({ r, g, b, a or 1 })
    end
    local t = dim and 0 or os.clock()
    local floor_y = cy + s * 0.86                                    -- the rune circle on the ground
    local fy = dim and 0 or math.sin(t * 1.5) * s * 0.04            -- the crystal floats
    local top, bot = cy - s * 1.00 + fy, cy + s * 0.70 + fy          -- a long point up, a shorter one down
    local gy, rx, rz = cy + s * 0.02 + fy, s * 0.19, s * 0.06        -- its widest ring, a little below the middle
    local turn = t * 0.5
    local breathe = 0.5 + 0.5 * math.sin(t * 1.7)
    -- the cold glow round it
    for i = 6, 1, -1 do
        dl:AddCircleFilled({ cx, cy - s * 0.15 }, s * (0.22 + 0.11 * i), c(0.25, 1.00, 0.50, 0.020 + 0.016 * breathe), 32)
    end
    -- the rune circle: a glowing ring seen from the side, with ticks round it
    local erx, ery = s * 0.62, s * 0.13
    local function ring(scale, col, w)
        local n = 28
        for i = 0, n - 1 do
            local a1, a2 = i * 2 * math.pi / n, (i + 1) * 2 * math.pi / n
            dl:AddLine({ cx + math.cos(a1) * erx * scale, floor_y + math.sin(a1) * ery * scale },
                       { cx + math.cos(a2) * erx * scale, floor_y + math.sin(a2) * ery * scale }, col, w)
        end
    end
    ring(1.00, c(0.45, 1.00, 0.60, 0.45 + 0.25 * breathe), 1.2)
    ring(0.72, c(0.55, 1.00, 0.70, 0.30 + 0.20 * breathe), 1)
    for i = 0, 11 do
        local a = i * math.pi / 6 + t * 0.2
        local x1, y1 = cx + math.cos(a) * erx * 0.74, floor_y + math.sin(a) * ery * 0.74
        local x2, y2 = cx + math.cos(a) * erx * 0.98, floor_y + math.sin(a) * ery * 0.98
        dl:AddLine({ x1, y1 }, { x2, y2 }, c(0.65, 1.00, 0.75, 0.35), 1)
    end
    -- the flames: green tongues round the foot, flickering; the ones
    -- behind the crystal are drawn first, the ones in front last
    local flames = {}
    for k = 0, 10 do
        local a = k * 2 * math.pi / 11 + 0.3
        local fl = dim and 0.5 or (0.5 + 0.5 * math.sin(t * 5.0 + k * 1.9)) * (0.65 + 0.35 * math.sin(t * 2.7 + k))
        flames[#flames + 1] = { z = math.sin(a), x = cx + math.cos(a) * erx * 0.55, y = floor_y + math.sin(a) * ery * 0.55,
                                h = s * (0.55 + 0.50 * fl), w = s * (0.10 + 0.03 * (k % 3)),
                                sway = dim and 0 or math.sin(t * 3.0 + k * 2.3) * s * 0.08 }
    end
    -- one tongue: a soft outer flame and a brighter core, bulging a little low down
    local function flame(f)
        local tip = { f.x + f.sway, f.y - f.h }
        local my = f.y - f.h * 0.35
        dl:AddQuadFilled({ f.x - f.w, f.y }, { f.x - f.w * 1.1 + f.sway * 0.3, my }, tip, { f.x + f.w * 1.1 + f.sway * 0.3, my }, c(0.15, 0.85, 0.40, 0.16))
        dl:AddTriangleFilled({ f.x + f.w * 1.1 + f.sway * 0.3, my }, { f.x + f.w, f.y }, { f.x - f.w, f.y }, c(0.15, 0.85, 0.40, 0.16))
        local w2 = f.w * 0.5
        dl:AddQuadFilled({ f.x - w2, f.y }, { f.x - w2 * 1.2 + f.sway * 0.2, my }, { f.x + f.sway * 0.75, f.y - f.h * 0.72 }, { f.x + w2 * 1.2 + f.sway * 0.2, my }, c(0.45, 1.00, 0.60, 0.30))
        dl:AddTriangleFilled({ f.x + w2 * 1.2 + f.sway * 0.2, my }, { f.x + w2, f.y }, { f.x - w2, f.y }, c(0.45, 1.00, 0.60, 0.30))
    end
    -- the light pooling on the ground under it
    for i = 3, 1, -1 do
        local k = i / 3
        local n = 20
        for j = 0, n - 1 do
            local a1, a2 = j * 2 * math.pi / n, (j + 1) * 2 * math.pi / n
            dl:AddTriangleFilled({ cx, floor_y }, { cx + math.cos(a1) * erx * 0.8 * k, floor_y + math.sin(a1) * ery * 0.8 * k },
                { cx + math.cos(a2) * erx * 0.8 * k, floor_y + math.sin(a2) * ery * 0.8 * k }, c(0.35, 1.00, 0.55, 0.10 + 0.05 * breathe))
        end
    end
    for _, f in ipairs(flames) do if f.z < 0 then flame(f) end end
    -- the girdle's six corners
    local P = {}
    for i = 0, 5 do
        local a = turn + i * math.pi / 3
        P[i] = { cx + math.cos(a) * rx, gy + math.sin(a) * rz }
    end
    local faces = {}
    for i = 0, 5 do
        local j = (i + 1) % 6
        local a = turn + (i + 0.5) * math.pi / 3
        local nx, nz = math.cos(a), math.sin(a)
        local lit = math.max(0, 0.55 * nz - 0.45 * nx + 0.25)
        faces[#faces + 1] = { z = nz, pts = { { cx, top }, P[i], P[j] }, v = 0.40 + 0.70 * lit }
        faces[#faces + 1] = { z = nz, pts = { { cx, bot }, P[i], P[j] }, v = 0.28 + 0.55 * lit }
    end
    table.sort(faces, function(a, b) return a.z < b.z end)
    for _, f in ipairs(faces) do
        local v = f.v * (f.z < 0 and 0.6 or 1)
        local alpha = f.z < 0 and 0.80 or 0.88                      -- see-through, as the crystal is
        dl:AddTriangleFilled(f.pts[1], f.pts[2], f.pts[3], c(0.10 + 0.70 * v * v, 0.60 + 0.40 * v, 0.25 + 0.60 * v * v, alpha))
        if f.z >= 0 then
            dl:AddLine(f.pts[1], f.pts[2], c(0.80, 1.00, 0.85, 0.55), 1)
            dl:AddLine(f.pts[2], f.pts[3], c(0.88, 1.00, 0.90, 0.70), 1)
        end
    end
    -- the light inside it: a pale core down the middle
    dl:AddQuadFilled({ cx, top + s * 0.20 }, { cx + s * 0.06, gy }, { cx, bot - s * 0.12 }, { cx - s * 0.06, gy }, c(0.92, 1.00, 0.94, 0.55 + 0.25 * breathe))
    for _, f in ipairs(flames) do if f.z >= 0 then flame(f) end end
    if dim then return end
    -- a glint at the top point, now and then
    local ph = (t % 3.2) / 3.2
    if ph < 0.22 then
        local q = math.sin(math.pi * ph / 0.22)
        local x, y = cx, top + s * 0.05
        dl:AddQuadFilled({ x - s * 0.36 * q, y }, { x, y - s * 0.04 * q - 0.5 }, { x + s * 0.36 * q, y }, { x, y + s * 0.04 * q + 0.5 }, c(1, 1, 1, 0.95 * q))
        dl:AddQuadFilled({ x, y - s * 0.36 * q }, { x + s * 0.04 * q + 0.5, y }, { x, y + s * 0.36 * q }, { x - s * 0.04 * q - 0.5, y }, c(1, 1, 1, 0.95 * q))
    end
end

-- Folded: just the green crystal. Click it to open the window; drag it to move it.
local ICON = 46
local eye_press = nil
local function eye_icon(dim, tooltip, on_click, on_right)
    local x, y = cursor()
    imgui.Dummy({ ICON, ICON })
    local hov = imgui.IsItemHovered() == true
    decorate(function(dl)
        crystal(dl, x + ICON / 2, y + ICON / 2, ICON * 0.47, dim)
    end)
    local mx, my = mouse()
    if hov and imgui.IsMouseClicked(0) then eye_press = { mx, my } end
    if eye_press and not imgui.IsMouseDown(0) then
        if hov and math.abs(mx - eye_press[1]) < 4 and math.abs(my - eye_press[2]) < 4 then on_click() end
        eye_press = nil
    end
    if hov and on_right and imgui.IsMouseClicked(1) then on_right() end
    if hov and not imgui.IsMouseDown(0) then tip(tooltip) end
end

local function mini_bar()
    local state = not S.enabled and 'OFF' or (paused and 'PAUSED' or 'ON')
    local lines = { 'Tidy ' .. state .. '  --  ' .. stats.items .. ' dropped' }
    local age = flash and (os.clock() - flash.at) or 99
    if age < 4 then lines[#lines + 1] = 'Dropped ' .. flash.text end
    if fighting then lines[#lines + 1] = 'Fighting ' .. (fighting.name or '?') end
    lines[#lines + 1] = 'Click: open  |  Right-click: turn on/off  |  ' .. (S.locked and 'Locked in place' or 'Drag: move')
    eye_icon(not S.enabled or paused, table.concat(lines, '\n'),
        function() after(function() S.ui_mini = false save() end) end,
        function()
            after(function()
                S.enabled = not S.enabled
                reset_tracking()
                save()
                say('Tidy %s.', S.enabled and 'ON -- dropping trash' or 'OFF')
            end)
        end)
end

-- The top of the page column: the on/off switch and state, Pause and Reload,
-- - and x in the corner; a line of big numbers; the last drop; a neon rule.
local function header(cw, right)
    if switch('##tidy_on', S.enabled) then
        after(function()
            S.enabled = not S.enabled
            reset_tracking()
            save()
            say('Tidy %s.', S.enabled and 'ON -- dropping trash' or 'OFF')
        end)
    end
    hover(S.enabled and 'Tidy is dropping. Click to turn it off.' or 'Tidy is off. Click to start dropping.')
    imgui.SameLine(0, 10)
    status_dot()
    imgui.SameLine(0, 4)
    if not S.enabled then
        ctext(GRAY, 'OFF')
    elseif paused then
        ctext(GOLD, 'PAUSED')
    else
        ctext(MINT, 'DROPPING')
    end
    imgui.SameLine(0, 16)
    if neon_button(paused and 'PAUSED##tidy_pause' or 'PAUSE##tidy_pause', not paused) then after(function() set_paused(not paused) end) end
    hover('Stop dropping for now without turning Tidy off (not saved).')
    imgui.SameLine(0, 6)
    if neon_button('RELOAD##tidy_reload', true) then after(reload) end
    hover('Reload Tidy (/addon reload tidy). Settings are kept.')
    imgui.SameLine(right)
    if round_button('-##tidy_fold', '-') then after(function() S.ui_mini = true save() end) end
    hover('Fold Tidy down to the green crystal (/tidy mini)')
    imgui.SameLine(0, 4)
    if round_button('x##tidy_close', 'x', true) then after(function() ui.open[1] = false end) end
    hover('Close (type /tidy to open again)')

    -- Big numbers: what's been dropped and what it was worth.
    imgui.Dummy({ 1, 2 })
    scaled(1.6, GOLD, string.format('%d', stats.items))
    imgui.SameLine(0, 5)
    ctext(GRAY, 'DROPPED')
    imgui.SameLine(0, 14)
    scaled(1.6, CHALK, string.format('%dg', stats.value))
    imgui.SameLine(0, 5)
    ctext(GRAY, 'NPC VALUE')
    imgui.SameLine(0, 16)
    ctext(SOOT, 'PROFILE')
    imgui.SameLine(0, 4)
    ctext(LAV, S.active)
    if fighting then
        ctext(SOOT, 'FIGHTING')
        imgui.SameLine(0, 4)
        ctext(MINT, fighting.name or '?')
    else
        ctext(SOOT, fight_note and 'FIGHT: SEE FIGHT' or 'NOT FIGHTING')
    end
    imgui.SameLine(0, 14)
    -- The last drop, fading out, or the tagline.
    local age = flash and (os.clock() - flash.at) or 99
    if age < 4 then
        ctext(with_alpha(RED, 1 - age / 5), 'DROPPED  ' .. flash.text)
    else
        ctext(GRAY, 'Drops unwanted loot the moment it lands.')
    end
    if not db then ctext(RED, 'data/mobdb.lua missing -- Hunt is off.') end
    decorate(function(dl)
        local x, y = cursor()
        rule(dl, x, x + cw, y + 4, LINE, 0.45)
    end)
    imgui.Dummy({ 1, 10 })
end

local function fight_tab(p, h)
    if not db then return ctext(RED, 'data/mobdb.lua missing -- Hunt is off.') end
    if fighting then
        section('FIGHTING NOW')
        ctext(GREEN, string.format('Fighting now: %s  (%s)', fighting.name or '?', zone_name(fighting.zone)))
        local t = th_now()
        ctext(GRAY, 'Treasure Hunter:')
        imgui.SameLine(0, 4)
        ctext(t.how == 'seen' and MINT or (t.how == 'set' and LAV or GOLD), string.format('%d (%s)', t.level, t.how))
        hover(t.why)
        if h.auto == false then ctext(GRAY, '  Auto is off -- this mob is not being cleaned (Settings page).') end
        drop_table('now', fighting.dropid, p, h)
    elseif fight_note then
        ctext(RED, 'Fighting now: ' .. fight_note)
    elseif targeted then
        -- Not engaged: preview the monster under your cursor (pin it, or engage it).
        if targeted.dropid then
            text(string.format('Target: %s  (%s) -- not engaged', targeted.name or '?', zone_name(targeted.zone)))
            imgui.SameLine()
            if imgui.SmallButton('Pin##pin_target') then after(hunt_target) end
            drop_table('tgt', targeted.dropid, p, h)
        else
            ctext(GRAY, string.format('Target: %s -- no drop list in the database.', targeted.name or '?'))
        end
    else
        ctext(GRAY, 'Fighting now: --  (engage a monster, or target one to preview it)')
    end

    -- Mobs fought this session (their lists stay active while Auto is on).
    local recent = {}
    for dropid, l in pairs(learned) do
        if not fighting or fighting.dropid ~= dropid then
            if type(l) ~= 'table' then l = {} end      -- never index a bad entry
            recent[#recent + 1] = { dropid = dropid, name = l.name, zone = l.zone, at = l.at or 0 }
        end
    end
    table.sort(recent, function(x, y) return x.at > y.at end)
    if #recent > 0 and imgui.CollapsingHeader(string.format('Fought this session (%d)###tidy_recent', #recent)) then
        for i, m in ipairs(recent) do
            text(string.format('  %s  (%s)', m.name or '?', zone_name(m.zone)))
            drop_table('r' .. i, m.dropid, p, h)
        end
        if imgui.SmallButton('Forget these') then after(function() learned = {} end) end
    end
    ctext(GRAY, 'Only new loot is dropped -- items you already had are kept.')
end

local function trash_tab(p)
    section('TRASH LIST -- every copy dropped on sight')
    item_picker('trash', 'Add', 'Type part of a name, then click it in the list (or type it exactly and press Enter).',
        function(id, name)
            local ok, msg = logic.add_item(p, id, name)
            if ok then save() say('%s', msg) else err('%s', msg) end
        end)
    if #p.items == 0 then return ctext(GRAY, '  (empty -- nothing on a trash list is dropped)') end
    local q = search_box('trash')
    for _, it in ipairs(p.items) do
        if logic.matches(q, it.name) then
            ctext(RED, '  ' .. (it.name or ('#' .. it.id)))
            imgui.SameLine()
            if imgui.SmallButton('Keep##rm_' .. it.id) then
                local id = it.id
                after(function() local _, msg = logic.remove_item(p, id) save() say('%s', msg) end)
            end
            hover('Take it off the trash list.')
        end
    end
end

local function want_tab(p, h)
    section('WANT -- always kept, from every mob')
    item_picker('want', 'Want', 'Type part of a name, then click it in the list.',
        function(id, name)
            if not logic.toggle_want(p, id, name) then logic.toggle_want(p, id, name) end   -- add, never toggle off
            save()
            say('%s marked WANT -- always kept.', name)
        end)
    if #h.want == 0 then return ctext(GRAY, '  (nothing yet -- press Want on a drop table row, or add one above)') end
    local q = search_box('want')
    for _, w in ipairs(h.want) do
        if logic.matches(q, w.name) then
            ctext(GREEN, '  ' .. (w.name or ('#' .. w.id)))
            imgui.SameLine()
            if imgui.SmallButton('Unwant##uw_' .. w.id) then
                local id, name = w.id, w.name
                after(function() logic.toggle_want(p, id, name) save() end)
            end
        end
    end
end

local function pinned_tab(p, h)
    if not db then return ctext(RED, 'data/mobdb.lua missing -- Hunt is off.') end
    section('PINNED MOBS -- cleaned even when not fighting')
    if neon_button('Pin my target##pin_btn') then after(hunt_target) end
    imgui.SameLine(0, 6)
    if neon_button('Clear##clear_pins', true) then after(function() h.mobs = {} save() end) end
    if #h.mobs == 0 then return ctext(GRAY, '  (none pinned)') end
    for mi, m in ipairs(h.mobs) do
        local open = imgui.CollapsingHeader(string.format('%s  (%s)###pin_%d', clean(m.name or '?'), clean(zone_name(m.zone)), m.dropid or mi))
        if open then
            if imgui.SmallButton('Unpin##mob_' .. mi) then
                local i = mi
                after(function() table.remove(h.mobs, i) save() end)
            end
            drop_table('p' .. mi, m.dropid, p, h)
        end
    end
end

local function extra_tab(h)
    section('EXTRA DROPS -- loot not on any drop list')
    ctext(GRAY, 'Rules: the keep rules decide (Want, Rare/Ex, Keep value).  Keep: never dropped.')
    if row_switch('##tidy_learn', 'Learn new ones from loot', S.extra_learn ~= false,
        'When the treasure pool gets an item that is not on that mob\'s drop list,\n'
        .. 'add it here as Keep. Nothing is dropped until you set it to Rules.') then
        S.extra_learn = not (S.extra_learn ~= false)
        save()
    end
    item_picker('extra', 'Add', 'Type part of a name, then click it in the list. Added as Rules.',
        function(id, name)
            local ok, msg = logic.add_extra(logic.extra_list(S), id, name, 'rules')
            if ok then save() say('%s', msg) else err('%s', msg) end
        end)
    local list = logic.extra_list(S)
    if #list == 0 then return ctext(GRAY, '  (none yet)') end
    local q = search_box('extra')
    for _, x in ipairs(list) do
        if logic.matches(q, x.name) then
            local v = x.mode == 'keep' and 'keep' or logic.verdict(db, h, x.id)
            local col = v == 'trash' and RED or GREEN
            ctext(col, string.format('  %s  %dg  %s', x.name or ('#' .. x.id), npc_value(x.id),
                v == 'keep' and 'Keep' or VERDICT_TAG[v]))
            if x.from then hover('First seen from ' .. x.from .. (x.learned and ' (learned)' or '')) end
            imgui.SameLine()
            if imgui.SmallButton((x.mode == 'keep' and 'Use rules' or 'Keep') .. '##xm_' .. x.id) then
                local e = x
                after(function() e.mode = (e.mode == 'keep') and 'rules' or 'keep' e.learned = false save() end)
            end
            imgui.SameLine()
            if imgui.SmallButton('Remove##xr_' .. x.id) then
                local id = x.id
                after(function() local _, msg = logic.remove_extra(logic.extra_list(S), id) save() say('%s', msg) end)
            end
        end
    end
end

local function bag_tab(p)
    local seen, rows = {}, {}
    local ok = pcall(function()
        for _, s in ipairs(read_inventory()) do
            if s.index > 0 then
                if not seen[s.id] then
                    seen[s.id] = { id = s.id, count = 0, locked = false }
                    rows[#rows + 1] = seen[s.id]
                end
                seen[s.id].count = seen[s.id].count + (s.count or 0)
                if (s.flags or 0) ~= 0 then seen[s.id].locked = true end
            end
        end
    end)
    if not ok then return ctext(GRAY, '  (inventory not available)') end
    for _, r in ipairs(rows) do r.name = item_name(r.id) end
    table.sort(rows, function(a, b) return a.name:lower() < b.name:lower() end)
    local trash = logic.trash_map(db, p, learned, logic.extra_list(S))
    local q = search_box('bag')
    for _, r in ipairs(rows) do
        if logic.matches(q, r.name) then
            local kind = trash[r.id]
            if kind == true then
                ctext(RED, string.format('  %s x%d  (trash list)', r.name, r.count))
            elseif kind == 'loot' then
                ctext(GOLD, string.format('  %s x%d  (Hunt: new copies drop)', r.name, r.count))
            else
                text(string.format('  %s x%d', r.name, r.count))
            end
            if r.locked then hover('Equipped/bazaar copies are never dropped.') end
            if kind ~= true then
                imgui.SameLine()
                if imgui.SmallButton('Trash##add_' .. r.id) then
                    local id, name = r.id, r.name
                    after(function() local _, msg = logic.add_item(p, id, name) save() say('%s', msg) end)
                end
                hover('Add to the trash list: every copy is dropped.')
            end
            imgui.SameLine()
            if imgui.SmallButton('Want##bw_' .. r.id) then
                local id, name = r.id, r.name
                after(function()
                    local on = logic.toggle_want(p, id, name)
                    save()
                    say('%s %s.', name, on and 'marked WANT -- always kept' or 'no longer wanted')
                end)
            end
        end
    end
end

local function log_tab()
    section('DROP LOG')
    ctext(GOLD, string.format('This session: %d stacks, %d items, %dg NPC value.', stats.stacks, stats.items, stats.value))
    if #log == 0 then return ctext(GRAY, '  (nothing dropped yet)') end
    for _, l in ipairs(log) do
        ctext(GRAY, string.format('  %s  %s x%d  %dg', l.time or '', l.name or '?', l.count or 0, l.value or 0))
    end
    if imgui.SmallButton('Clear log') then after(function() log = {} end) end
end

local function settings_tab(h)
    section('PROFILE')
    push_width(180)
    if imgui.BeginCombo('Profile##tidy_profile', clean(S.active)) then
        combo_open = true
        for _, name in ipairs(logic.profile_names(S)) do
            if imgui.Selectable(clean(name) .. '##tp_' .. name, name == S.active) then
                local n = name
                after(function() S.active = n reset_tracking() save() end)
            end
        end
        imgui.EndCombo()
        combo_open = false
    end
    pop_width()
    push_width(180)
    imgui.InputText('##tidy_newname', ui.name_buf, 48)
    pop_width()
    imgui.SameLine()
    if imgui.Button('New') then
        after(function()
            local ok, msg = logic.new_profile(S, ui.name_buf[1])
            if ok then ui.name_buf[1] = '' save() say('%s', msg) else err('%s', msg) end
        end)
    end
    imgui.SameLine()
    if imgui.Button('Copy') then
        after(function()
            local ok, msg = logic.new_profile(S, ui.name_buf[1], S.active)
            if ok then ui.name_buf[1] = '' save() say('%s', msg) else err('%s', msg) end
        end)
    end
    imgui.SameLine()
    if imgui.Button('Delete') then
        after(function()
            local ok, msg = logic.delete_profile(S, S.active)
            if ok then save() say('%s', msg) else err('%s', msg) end
        end)
    end
    hover('Deletes the selected profile.')

    -- Hunt rules
    section('HUNT RULES (this profile)')
    if row_switch('##tidy_auto', 'Auto: mobs I fight', h.auto ~= false,
        'Reads the mob you are engaged on (and anything that drops you loot)\n'
        .. 'and drops the useless items from its drop list. No setup per mob.') then
        h.auto = not (h.auto ~= false) save()
    end
    if row_switch('##tidy_rare', 'Keep Rare/Ex', h.keep_rare ~= false) then
        h.keep_rare = not (h.keep_rare ~= false) save()
    end
    local kv, kdone = row_slider('##tidy_keepval', 'Keep value', h.keep_value or 500, 0, 20000, '%dg')
    hover('Keep anything that sells to an NPC for at least this much. 0 = off.')
    h.keep_value = kv
    if kdone then save() end

    section('TREASURE HUNTER (drop rates shown)')
    local auto_th = (S.th_override or -1) < 0
    if row_switch('##tidy_th_auto', 'Work it out', auto_th,
        'From your job, subjob and gear, your party\'s Thieves,\nand the game\'s Treasure Hunter proc messages.') then
        S.th_override = auto_th and th_est.level or -1
        save()
    end
    if (S.th_override or -1) >= 0 then
        local tv, tdone = row_slider('##th_set', 'Treasure Hunter', S.th_override, 0, logic.TH_MAX, 'TH%d')
        S.th_override = tv
        if tdone then save() end
    else
        local t = th_now()
        ctext(GRAY, string.format('Now %d (%s)', t.level, t.how))
        hover(t.why)
    end

    section('LOOK')
    local op, odone = row_slider('##tidy_opacity', 'Window opacity', S.opacity or 82, 30, 100, '%d')
    hover('How solid the window is: 100 = solid, lower = see-through (/tidy opacity 30-100).')
    S.opacity = op
    if odone then save() end

    section('TOOLS')
    if neon_button('Explain my bag in chat##why_btn') then after(why) end
    hover('Same as /tidy why: a line per item saying whether it will be dropped and why.')
    imgui.SameLine(0, 6)
    if neon_button('Reload Tidy##reload_btn', true) then after(reload) end
end

draw_window = function()
    later = {}
    local p = profile()
    local h = logic.hunt(p)
    if S.ui_mini then
        mini_bar()
        for _, fn in ipairs(later) do fn() end
        later = {}
        return
    end
    glass()
    local ww = num(imgui.GetWindowWidth(), START_W)
    local _, wh = xy(imgui.GetWindowSize())
    local _, wy = xy(imgui.GetWindowPos())
    local x0, y0 = cursor()
    local cw = math.max(200, ww - 32 - SIDE_W - SIDE_GAP)
    PANEL_W, ROW_W = cw, cw - 14

    local counts = { Trash = #p.items, Want = #h.want, Pinned = #h.mobs, Extra = #logic.extra_list(S) }
    ui.page = ui.page or 'Fight'
    sidebar(x0, y0, counts)
    decorate(function(dl)
        local bottom = (type(wy) == 'number' and type(wh) == 'number') and (wy + wh - 18) or (y0 + 360)
        divider(dl, x0 + SIDE_W + SIDE_GAP / 2, y0, bottom)
    end)

    -- The page column: header, then the page, scrolling, down to the corner.
    pcall(imgui.SetCursorScreenPos, { x0 + SIDE_W + SIDE_GAP, y0 })
    imgui.Indent(SIDE_W + SIDE_GAP)
    header(cw, ww - 16 - 48)
    local ok, shown = pcall(imgui.BeginChild, '##tidy_panel', { 0, -(GRIP - 4) }, false)
    if not ok then ok, shown = pcall(imgui.BeginChild, '##tidy_panel', { 0, -(GRIP - 4) }, 0) end
    child_open = ok
    if not ok or shown then
        local page = ui.page
        if page == 'Fight' then fight_tab(p, h)
        elseif page == 'Trash' then trash_tab(p)
        elseif page == 'Want' then want_tab(p, h)
        elseif page == 'Pinned' then pinned_tab(p, h)
        elseif page == 'Extra' then extra_tab(h)
        elseif page == 'Bag' then bag_tab(p)
        elseif page == 'Log' then log_tab()
        else settings_tab(h) end
    end
    if child_open then imgui.EndChild() child_open = false end
    imgui.Unindent(SIDE_W + SIDE_GAP)

    for _, fn in ipairs(later) do fn() end
    later = {}
end

-- Starting height: the header plus a page panel sized to the screen.
local function start_size()
    local _, sh = screen_size()
    local panel_h = math.floor(math.max(PANEL_H_MIN, math.min(PANEL_H_MAX, sh * 0.38)))
    return START_W, panel_h + 150
end

-- The resize corner: three acid hatch lines at the bottom right. Dragging it
-- resizes the window (done here, so it works even where ImGui's own grip
-- doesn't), and the size is saved when you let go.
local resizing = nil
local restore_size = true
local function resize_corner()
    local wx, wy = xy(imgui.GetWindowPos())
    local ww, wh = xy(imgui.GetWindowSize())
    if not (wx and ww) then return end
    local x0, y0 = wx + ww - GRIP - 1, wy + wh - GRIP - 1
    pcall(imgui.SetCursorScreenPos, { x0, y0 })
    imgui.InvisibleButton('##tidy_resize', { GRIP, GRIP })
    local hot = imgui.IsItemHovered() or resizing ~= nil
    if imgui.IsItemHovered() then tip('Drag to resize') end
    decorate(function(dl)
        local c = col32(hot and MINT or with_alpha(WHITE, 0.35))
        local x1, y1 = wx + ww - 3, wy + wh - 3
        for k = 1, 3 do
            local d = k * 4
            dl:AddLine({ x1 - d, y1 }, { x1, y1 - d }, c, 1.5)
        end
    end)
    local mx, my = xy(imgui.GetMousePos())
    if imgui.IsItemActive() and mx then
        if not resizing then resizing = { mx = mx, my = my, w = ww, h = wh } end
        local nw = math.max(MIN_W, math.min(MAX_W, resizing.w + (mx - resizing.mx)))
        local nh = math.max(MIN_H, math.min(MAX_H, resizing.h + (my - resizing.my)))
        if math.abs(nw - ww) >= 1 or math.abs(nh - wh) >= 1 then imgui.SetWindowSize({ nw, nh }) end
    elseif resizing then
        resizing = nil
        S.ui_size = T{ math.floor(ww), math.floor(wh) }
        save()
    end
end

local last_ui_error = -60
local function render()
    if not ui.open[1] then
        if S.ui_open then S.ui_open = false save() end
        return
    end
    local nc, nv = push_style()
    local flags
    if S.ui_mini then
        -- Folded: the slim bar fits its contents.
        imgui.SetNextWindowSizeConstraints({ 0, 0 }, { START_W, 4000 })
        flags = bit.bor(ImGuiWindowFlags_AlwaysAutoResize or 0, ImGuiWindowFlags_NoTitleBar or 0)
        restore_size = true
    else
        -- Full window: the size you dragged it to (or the starting size).
        local w, h = start_size()
        local saved = S.ui_size
        if saved and (saved[1] or -1) > 0 then w, h = saved[1], saved[2] end
        if restore_size then
            imgui.SetNextWindowSize({ w, h }, ImGuiCond_Always or 0)
            restore_size = false
        end
        imgui.SetNextWindowSizeConstraints({ MIN_W, MIN_H }, { MAX_W, MAX_H })
        flags = bit.bor(ImGuiWindowFlags_NoTitleBar or 0, ImGuiWindowFlags_NoResize or 0,
            ImGuiWindowFlags_NoScrollbar or 0)
    end
    if S.locked then flags = bit.bor(flags, ImGuiWindowFlags_NoMove or 0) end
    if imgui.Begin('Tidy v' .. addon.version .. '##tidy_window', ui.open, flags) then
        width_depth, combo_open, color_depth, child_open = 0, false, 0, false
        local ok, e = pcall(draw_window)
        if not ok then
            -- Close whatever the failed draw left open, so ImGui stays balanced.
            later = {}
            if combo_open then imgui.EndCombo() combo_open = false end
            while width_depth > 0 do pop_width() end
            if color_depth > 0 then pop_colors(color_depth) end
            if child_open then imgui.EndChild() child_open = false end
            local now = os.clock()
            if now - last_ui_error > 30 then
                last_ui_error = now
                err('Window error (Tidy kept running): %s', tostring(e))
            end
            ctext(RED, 'Window error -- see chat. Tidy keeps running.')
        end
        if not S.ui_mini then pcall(resize_corner) end
    end
    imgui.End()
    pop_style(nc, nv)
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

ashita.events.register('load', 'tidy_load', function()
    local ok, data = pcall(require, 'data.mobdb')
    if ok then db = data else err('Could not load data/mobdb.lua -- Hunt mode is off.') end
    S = settings.load(defaults)
    logic.ensure(S)
    ui.open[1] = S.ui_open ~= false
    settings.register('settings', 'tidy_settings_update', function(s)
        if s ~= nil then
            S = s
            logic.ensure(S)
            sent = {}
        end
    end)
    say('v%s loaded. Profile: %s (%d items), %s. /tidy to open, /tidy help for commands.', addon.version,
        S.active, #profile().items, S.enabled and 'ON' or 'OFF')
end)

ashita.events.register('unload', 'tidy_unload', function()
    if S then save() end
end)

ashita.events.register('d3d_present', 'tidy_present', function()
    if not S then return end
    local ok, e = pcall(tick)
    if not ok then
        local now = os.clock()
        if now - last_ui_error > 30 then
            last_ui_error = now
            err('Error (Tidy kept running): %s', tostring(e))
        end
    end
    render()
end)

local function u32(data, offset)   -- offset as in the packet docs (0-based)
    local a, b, c, d = data:byte(offset + 1, offset + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end

-- Treasure Hunter procs: "Additional effect: Treasure Hunter effectiveness
-- against the Colibri increases to 5." -- the mob's exact TH from then on.
ashita.events.register('text_in', 'tidy_text_in', function(e)
    local ok = pcall(function()
        local msg = e.message_modified or e.message
        if type(msg) ~= 'string' or not msg:find('Treasure Hunter', 1, true) then return end
        msg = msg:gsub('[\30\31].', ''):gsub('[%z\1-\31]', '')
        local name, level = msg:match('Treasure Hunter effectiveness against (.-) increases to (%d+)')
        if not name then return end
        name = name:gsub('^[Tt]he ', ''):lower()
        level = tonumber(level)
        if fighting and (fighting.name or ''):lower() == name then
            th_seen[fighting.id] = { level = level, at = os.clock() }
        else
            th_recent = { name = name, level = level, at = os.clock() }
        end
    end)
    if not ok then return end
end)

ashita.events.register('packet_in', 'tidy_packet_in', function(e)
    -- Zoning: slot numbers are re-sent by the server, forget what we sent.
    if e.id == 0x0A then sent = {} return end

    -- Treasure Hunter, live from the game's packets (anyone's proc, whatever
    -- your chat filters show): 0x028 action packets carry the proc as an
    -- additional effect; 0x029 is how a server can announce the starting TH.
    if e.id == 0x028 and e.data then
        local ok, found = pcall(logic.th_from_action, e.data)
        if ok then for mob, level in pairs(found) do th_seen[mob] = { level = level, at = os.clock() } end end
        return
    end
    if e.id == 0x029 and e.data then
        local ok, mob, level = pcall(logic.th_from_message, e.data)
        if ok and mob then th_seen[mob] = { level = level, at = os.clock() } end
        return
    end

    -- 0x0D2 Found Item: loot entered the treasure pool. Dropper (0x08) is the
    -- mob's server id -- learn its drop list for "Any mob I kill".
    if e.id == 0x0D2 and db and e.data and #e.data >= 0x16 then
        if e.data:byte(0x15 + 1) ~= 0 then return end          -- 'Old': not a new drop
        local mob_id = u32(e.data, 0x08)
        local dropid = logic.dropid_for(db, mob_id)
        local idx0 = e.data:byte(0x12 + 1) + e.data:byte(0x13 + 1) * 256
        local ent0 = idx0 > 0 and GetEntity(idx0) or nil
        local is_mob = mob_id >= 0x1000000 and (ent0 == nil or bit.band(ent0.SpawnFlags or 0, 0x10) ~= 0)
        -- Extra drops: loot from a monster that isn't on its drop list (e.g. Ramuite).
        -- Learned as Keep, so nothing new is ever dropped until you choose Rules.
        local item = e.data:byte(0x10 + 1) + e.data:byte(0x11 + 1) * 256
        if S and is_mob and S.extra_learn ~= false and item ~= 0 and item ~= 0xFFFF
            and not (dropid and logic.on_drop_list(db, dropid, item))
            and not logic.find_extra(logic.extra_list(S), item) then
            local from = (ent0 and ent0.Name) or 'a monster'
            local nm = item_name(item)
            if logic.add_extra(logic.extra_list(S), item, nm, 'keep', from) then
                save()
                say('New Extra drop: %s (from %s). Kept -- set it to Rules on the Extra page to let Tidy clean it.', nm, from)
            end
        end
        if dropid then
            -- Always a record, never a bare 'true': the window reads .name/.zone/.at.
            local idx = e.data:byte(0x12 + 1) + e.data:byte(0x13 + 1) * 256     -- Dropper Index
            local ent = idx > 0 and GetEntity(idx) or nil
            local l = learned[dropid]
            if type(l) == 'table' then
                l.at = os.clock()
            else
                learned[dropid] = { name = (ent and ent.Name) or 'Unknown mob',
                    zone = math.floor(mob_id / 4096) % 4096, at = os.clock() }
            end
        end
    end
end)
