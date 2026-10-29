--[[
    Tidy - pure logic (no Ashita calls), so it can be tested offline.
    Author: Guabancex

    A profile is a trash list: { items = { { id = 4357, name = 'Bat Wing' }, ... } }.
    Only items on the active profile's list are ever dropped; everything else is
    kept. Items are matched by id, never by name, so two items that share a name
    can't be confused.
]]--

local logic = {}

-- Inventory slot flags: 0 = free to use. Anything else (equipped, in the bazaar,
-- linkshell equipped, being traded...) is never touched.
logic.FLAG_FREE = 0

-- Seconds before a drop we already sent for a slot may be sent again (the item
-- normally vanishes well before this; a re-send only happens if the server
-- ignored the first one).
logic.RESEND_AFTER = 3.0

-- Byte layout of the outgoing 0x028 Drop Item packet (12 bytes):
--   00-01  id 0x028 | size (3 x 4 bytes) << 9   -> 0x28, 0x06
--   02-03  sync (filled in by the client)
--   04-07  count (uint32, little endian)
--   08     bag
--   09     slot index
--   0A-0B  padding
function logic.drop_packet(bag, slot, count)
    count = math.max(0, math.min(count or 0, 0xFFFFFFFF))
    return {
        0x28, 0x06, 0x00, 0x00,
        count % 256, math.floor(count / 256) % 256,
        math.floor(count / 65536) % 256, math.floor(count / 16777216) % 256,
        bag, slot, 0x00, 0x00,
    }
end

-- Set of item ids on a profile's trash list.
function logic.trash_set(profile)
    local set = {}
    for _, it in ipairs((profile and profile.items) or {}) do
        if it.id then set[it.id] = true end
    end
    return set
end

-- A slot that could be dropped at all: real item, not gil, nothing locking it.
local function droppable(s)
    return s.index > 0 and s.id and s.id ~= 0 and s.id ~= 0xFFFF
        and (s.count or 0) > 0 and (s.flags or 0) == logic.FLAG_FREE
end

-- Forget sent-drops whose slot now holds something else, or that are old enough
-- to send again. Returns the still-pending entry for this slot, or nil.
local function pending_for(s, sent, now)
    local key = s.bag .. ':' .. s.index
    local prior = sent[key]
    if prior and (prior.id ~= s.id or now - prior.at >= logic.RESEND_AFTER) then
        sent[key] = nil
        prior = nil
    end
    return prior
end

-- Total count of each item id across slots.
function logic.totals(slots)
    local t = {}
    for _, s in ipairs(slots) do
        if s.index > 0 and s.id and s.id ~= 0 then t[s.id] = (t[s.id] or 0) + (s.count or 0) end
    end
    return t
end

--[[
    Which slots to drop now.
      slots    = list of { bag, index, id, count, flags } for the watched bags
      trash    = { [id] = true } drop every copy (your own trash list), or
                 { [id] = 'loot' } drop only what's above baseline[id] (Hunt mode:
                 copies you already had are never touched)
      sent     = { ["bag:index"] = { id, at } } drops already sent (updated here)
      now      = clock seconds
      baseline = { [id] = count you had before } for 'loot' ids
    Returns a list of { bag, index, id, count } -- count may be part of a stack.
    Index 0 of the inventory is gil and is never returned.
]]--
function logic.plan(slots, trash, sent, now, baseline)
    baseline = baseline or {}
    local out = {}

    -- Whole-stack drops (your trash list), in inventory order.
    for _, s in ipairs(slots) do
        local prior = pending_for(s, sent, now)
        if droppable(s) and trash[s.id] == true and not prior then
            out[#out + 1] = { bag = s.bag, index = s.index, id = s.id, count = s.count }
        end
    end

    -- Loot drops (Hunt): only the excess over what you had, newest slots first.
    local totals = logic.totals(slots)
    local excess = {}
    for id, kind in pairs(trash) do
        if kind == 'loot' then
            local e = (totals[id] or 0) - (baseline[id] or 0)
            if e > 0 then excess[id] = e end
        end
    end
    for i = #slots, 1, -1 do
        local s = slots[i]
        local e = excess[s.id]
        if e and e > 0 and droppable(s) then
            local prior = pending_for(s, sent, now)
            if prior then
                excess[s.id] = math.max(0, e - (prior.count or s.count))
            else
                local n = math.min(e, s.count)
                out[#out + 1] = { bag = s.bag, index = s.index, id = s.id, count = n }
                excess[s.id] = e - n
            end
        end
    end
    return out
end

-- Keep baselines honest: an item you used, sold or traded away lowers its
-- baseline, so the next one you loot counts as new. New 'loot' ids start at
-- whatever you hold now.
function logic.update_baseline(baseline, slots, trash)
    local totals = logic.totals(slots)
    for id, kind in pairs(trash) do
        if kind == 'loot' then
            local have = totals[id] or 0
            if baseline[id] == nil or have < baseline[id] then baseline[id] = have end
        end
    end
end

-- Mark a slot's drop as sent.
function logic.mark_sent(sent, drop, now)
    sent[drop.bag .. ':' .. drop.index] = { id = drop.id, at = now, count = drop.count }
end

-- ---------------------------------------------------------------------------
-- Hunt mode: trash a mob's drop list except what you want and what's valuable.
-- db = data/mobdb.lua. profile.hunt = { mobs = { {id, name, zone, dropid} },
-- want = { {id, name} }, keep_rare, keep_value, auto }.
-- auto: also use the drop list of every mob you fight / that drops you loot.
-- ---------------------------------------------------------------------------

function logic.hunt(profile)
    profile.hunt = profile.hunt or {}
    local h = profile.hunt
    h.mobs = h.mobs or {}
    h.want = h.want or {}
    if h.keep_rare == nil then h.keep_rare = true end
    if h.keep_value == nil then h.keep_value = 500 end
    if h.auto == nil then h.auto = true end   -- read the mob you're fighting
    h.any_mob = nil                            -- (old name, replaced by auto)
    return h
end

-- Drop list id for a mob server id (0x1000000 + zone<<12 + index), or nil.
function logic.dropid_for(db, mobid)
    if not db or not mobid or mobid < 0x1000000 then return nil end
    local zone, index = math.floor(mobid / 4096) % 4096, mobid % 4096
    local z = db.zones[zone]
    return z and z[index] or nil
end

-- Drop rows for a drop list: { { item, rate, group, group_rate, group_total }, ... }.
-- rate is per mille. For a grouped row (group > 0) the server first rolls the
-- group's rate, then picks ONE item of the group by weight: rate is the item's
-- weight, group_total the sum of the group's weights.
function logic.drop_rows(db, dropid)
    local out, lst = {}, db and db.drops[dropid]
    if not lst then return out end
    local groups = db.dgroup and db.dgroup[dropid]
    local grates = db.grate and db.grate[dropid] or {}
    local totals = {}
    for i = 1, #lst, 2 do
        local g = groups and groups[(i + 1) / 2] or 0
        out[#out + 1] = { item = lst[i], rate = lst[i + 1], group = g, group_rate = grates[g] }
        if g ~= 0 then totals[g] = (totals[g] or 0) + lst[i + 1] end
    end
    for _, row in ipairs(out) do
        if row.group ~= 0 then row.group_total = totals[row.group] end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Treasure Hunter, on the CatsEyeXI scale (scripts/globals/combat/
-- treasure_hunter.lua): TH doesn't multiply a rate, it moves the rate's bracket
-- to a fixed value for that TH level. Values are out of 10000.
-- ---------------------------------------------------------------------------

logic.TH_MAX = 14
logic.TH_TABLE = {
--  TH lvl    VC    C     UC    R     VR    SR   UR
    [ 0] = { 2400, 1500, 1000,  500,  100,  50,  10 },
    [ 1] = { 4800, 3000, 1200,  600,  150,  75,  20 },
    [ 2] = { 5600, 4000, 1500,  700,  200, 100,  30 },
    [ 3] = { 6000, 4250, 1650,  750,  225, 120,  35 },
    [ 4] = { 6400, 4500, 1800,  800,  250, 140,  40 },
    [ 5] = { 6666, 4750, 1900,  850,  300, 160,  45 },
    [ 6] = { 6800, 5000, 2000,  900,  350, 180,  50 },
    [ 7] = { 6900, 5250, 2100,  950,  400, 200,  60 },
    [ 8] = { 7050, 5500, 2250, 1050,  475, 230,  70 },
    [ 9] = { 7200, 5750, 2400, 1150,  550, 260,  80 },
    [10] = { 7350, 6000, 2650, 1250,  650, 300,  90 },
    [11] = { 7400, 6250, 2800, 1350,  750, 350, 100 },
    [12] = { 7600, 6500, 2950, 1550,  825, 400, 115 },
    [13] = { 7800, 6750, 3100, 1750,  900, 450, 130 },
    [14] = { 8000, 7000, 3250, 2000, 1000, 500, 150 },
}
logic.TH_BRACKETS = { 2400, 1500, 1000, 500, 100, 50, 0 }

-- A drop rate (out of 10000) at a Treasure Hunter level, as the server computes it.
function logic.th_rate(th, rate)
    th = math.max(0, math.min(logic.TH_MAX, math.floor(th or 0)))
    rate = math.max(0, math.min(10000, rate or 0))
    if rate == 10000 or rate == 0 then return rate end
    for i, floor in ipairs(logic.TH_BRACKETS) do
        if rate >= floor then return logic.TH_TABLE[th][i] end
    end
    return 0
end

-- Chance (out of 10000) that one kill drops this row's item, at TH level th.
function logic.row_chance(row, th)
    if (row.group or 0) == 0 then
        return logic.th_rate(th, (row.rate or 0) * 10)
    end
    local total = row.group_total or 0
    if total <= 0 then return 0 end
    return logic.th_rate(th, (row.group_rate or 0) * 10) * (row.rate or 0) / total
end

-- Treasure Hunter from job traits (CatsEyeXI traits.sql: THF 15 = TH1, 45 = TH2;
-- TH3 is Abyssea-only). Subjob THF counts too.
function logic.th_trait(main_job, main_level, sub_job, sub_level)
    local THF = 6
    local function at(level)
        if (level or 0) >= 45 then return 2 elseif (level or 0) >= 15 then return 1 end
        return 0
    end
    local th = 0
    if main_job == THF then th = at(main_level) end
    if sub_job == THF then th = math.max(th, at(sub_level)) end
    return th
end

-- The TH a player puts on a mob when they hit it: trait + gear, capped at 8 for
-- a THF main and 4 for anyone else (enmity_container.cpp).
function logic.th_applied(main_job, trait, gear)
    local th = (trait or 0) + (gear or 0)
    return math.min(main_job == 6 and 8 or 4, th)
end

-- 'want' | 'rare' | 'value' | 'trash' for one item in Hunt mode.
function logic.verdict(db, h, item)
    for _, w in ipairs(h.want or {}) do
        if w.id == item then return 'want' end
    end
    local info = db and db.items[item]
    local sell, flags = info and info[1] or 0, info and info[2] or 0
    if h.keep_rare and flags ~= 0 then return 'rare' end
    if (h.keep_value or 0) > 0 and sell >= h.keep_value then return 'value' end
    return 'trash'
end

-- The full trash map for a profile: your own list (whole stacks) plus Hunt loot
-- ('loot': only what you didn't already have). Wanted items are never in it.
-- extra_dropids = drop lists of mobs you fought / that dropped you loot (auto).
-- extra = Extra drops (logic.extra_list): loot the server adds outside the drop
-- lists (e.g. Ramuite). Entries set to 'rules' are judged like any drop-list item
-- whenever Hunt is in use -- Auto on and a mob fought this session, or a pinned mob.
function logic.trash_map(db, profile, extra_dropids, extra)
    local map = logic.trash_set(profile)
    local h = logic.hunt(profile)
    local lists = {}
    for _, m in ipairs(h.mobs) do if m.dropid then lists[m.dropid] = true end end
    if h.auto then
        for d in pairs(extra_dropids or {}) do lists[d] = true end
    end
    for dropid in pairs(lists) do
        for _, row in ipairs(logic.drop_rows(db, dropid)) do
            if map[row.item] == nil and logic.verdict(db, h, row.item) == 'trash' then
                map[row.item] = 'loot'
            end
        end
    end
    local hunting = #h.mobs > 0 or (h.auto and next(extra_dropids or {}) ~= nil)
    if hunting then
        for _, x in ipairs(extra or {}) do
            if x.mode == 'rules' and x.id and map[x.id] == nil and logic.verdict(db, h, x.id) == 'trash' then
                map[x.id] = 'loot'
            end
        end
    end
    for _, w in ipairs(h.want) do map[w.id] = nil end   -- wanted always wins
    return map
end

-- True if item is on drop list dropid.
function logic.on_drop_list(db, dropid, item)
    for _, row in ipairs(logic.drop_rows(db, dropid)) do
        if row.item == item then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Extra drops: items mobs drop that aren't on any drop list in the database
-- (server-wide drops such as Ramuite). settings.extra = { { id, name, mode,
-- learned, from } }, shared by every profile. mode 'rules' = Hunt's keep rules
-- decide; 'keep' = never dropped (what auto-learned items start as).
-- ---------------------------------------------------------------------------

function logic.extra_list(settings)
    settings.extra = settings.extra or {}
    return settings.extra
end

function logic.find_extra(list, id)
    for i, x in ipairs(list or {}) do
        if x.id == id then return x, i end
    end
    return nil
end

-- Returns ok, message.
function logic.add_extra(list, id, name, mode, from)
    if not id or id == 0 or id == 0xFFFF then return false, 'Unknown item.' end
    local x = logic.find_extra(list, id)
    if x then return false, (name or x.name) .. ' is already an extra drop.' end
    list[#list + 1] = { id = id, name = name, mode = mode or 'rules', learned = from ~= nil, from = from }
    table.sort(list, function(a, b) return (a.name or ''):lower() < (b.name or ''):lower() end)
    return true, name .. ' added to Extra drops.'
end

function logic.remove_extra(list, id)
    local x, i = logic.find_extra(list, id)
    if not x then return false, 'That item is not an extra drop.' end
    table.remove(list, i)
    return true, (x.name or 'Item') .. ' removed from Extra drops.'
end

-- Case-insensitive substring search; an empty query matches everything.
function logic.matches(query, name)
    if not query or query == '' then return true end
    return tostring(name or ''):lower():find(query, 1, true) ~= nil
end

function logic.toggle_want(profile, id, name)
    local h = logic.hunt(profile)
    for i, w in ipairs(h.want) do
        if w.id == id then
            table.remove(h.want, i)
            return false
        end
    end
    h.want[#h.want + 1] = { id = id, name = name }
    return true
end

function logic.add_mob(profile, mob)
    local h = logic.hunt(profile)
    for _, m in ipairs(h.mobs) do
        if m.dropid == mob.dropid then return false, mob.name .. ' (same drop list) is already on the hunt.' end
    end
    h.mobs[#h.mobs + 1] = mob
    return true, mob.name .. ' added to the hunt.'
end

-- ---------------------------------------------------------------------------
-- Profiles. settings.profiles = { [name] = { items = {...} } }, settings.active.
-- ---------------------------------------------------------------------------

function logic.ensure(settings)
    settings.profiles = settings.profiles or {}
    if next(settings.profiles) == nil then
        settings.profiles['Default'] = { items = {} }
    end
    if not settings.active or not settings.profiles[settings.active] then
        local names = logic.profile_names(settings)
        settings.active = names[1]
    end
    return settings.profiles[settings.active]
end

function logic.profile_names(settings)
    local names = {}
    for name in pairs(settings.profiles or {}) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

-- Case-insensitive lookup; returns the stored name or nil.
function logic.find_profile(settings, name)
    if not name then return nil end
    for stored in pairs(settings.profiles or {}) do
        if stored:lower() == name:lower() then return stored end
    end
    return nil
end

-- Returns ok, message.
function logic.new_profile(settings, name, copy_from)
    name = name and name:match('^%s*(.-)%s*$') or ''
    if name == '' then return false, 'Give the profile a name.' end
    if logic.find_profile(settings, name) then return false, 'A profile named "' .. name .. '" already exists.' end
    local items = {}
    if copy_from and settings.profiles[copy_from] then
        for _, it in ipairs(settings.profiles[copy_from].items or {}) do
            items[#items + 1] = { id = it.id, name = it.name }
        end
    end
    settings.profiles[name] = { items = items }
    settings.active = name
    return true, 'Profile "' .. name .. '" created.'
end

function logic.delete_profile(settings, name)
    local stored = logic.find_profile(settings, name)
    if not stored then return false, 'No profile named "' .. tostring(name) .. '".' end
    if #logic.profile_names(settings) <= 1 then return false, 'Can\'t delete the only profile.' end
    settings.profiles[stored] = nil
    if settings.active == stored then settings.active = logic.profile_names(settings)[1] end
    return true, 'Profile "' .. stored .. '" deleted.'
end

function logic.has_item(profile, id)
    for _, it in ipairs(profile.items or {}) do
        if it.id == id then return true end
    end
    return false
end

function logic.add_item(profile, id, name)
    if not id or id == 0 then return false, 'Unknown item.' end
    if logic.has_item(profile, id) then return false, name .. ' is already on the trash list.' end
    profile.items = profile.items or {}
    profile.items[#profile.items + 1] = { id = id, name = name }
    table.sort(profile.items, function(a, b) return (a.name or ''):lower() < (b.name or ''):lower() end)
    return true, name .. ' added to the trash list.'
end

function logic.remove_item(profile, id)
    for i, it in ipairs(profile.items or {}) do
        if it.id == id then
            table.remove(profile.items, i)
            return true, (it.name or 'Item') .. ' removed from the trash list.'
        end
    end
    return false, 'That item is not on the trash list.'
end

-- ---------------------------------------------------------------------------
-- Packets. Read straight from the game's own packets; nothing leaves the client.
-- ---------------------------------------------------------------------------

logic.MSG_TH_PROC = 603     -- "Treasure Hunter effectiveness against <target> increases to <param>"

-- Bit reader over a packet string. FFXI packs these fields least-significant
-- bit first; bit 0 is the low bit of byte 0 (the packet header included).
local function bit_reader(data, start)
    local pos = start
    local total = #data * 8
    return function(len)
        if pos + len > total then error('short packet', 0) end
        local v, mul = 0, 1
        for i = 0, len - 1 do
            local b = pos + i
            local byte = data:byte(math.floor(b / 8) + 1)
            if math.floor(byte / 2 ^ (b % 8)) % 2 == 1 then v = v + mul end
            mul = mul * 2
        end
        pos = pos + len
        return v
    end
end

-- 0x028 Action: { actor, category, targets = { { id, actions = { { message,
-- param, add_message, add_param } } } } }, or nil if the packet is cut short.
function logic.parse_action(data)
    local ok, res = pcall(function()
        local bits = bit_reader(data, 40)
        local a = { actor = bits(32) }
        local count = bits(6)
        bits(4)
        a.category = bits(4)
        a.param = bits(32)
        a.recast = bits(32)
        a.targets = {}
        for _ = 1, count do
            local t = { id = bits(32), actions = {} }
            local n = bits(4)
            for _ = 1, n do
                local act = {}
                act.reaction, act.animation, act.effect, act.knockback = bits(5), bits(12), bits(7), bits(3)
                act.param, act.message, act.flags = bits(17), bits(10), bits(31)
                if bits(1) == 1 then
                    bits(10)
                    act.add_param, act.add_message = bits(17), bits(10)
                end
                if bits(1) == 1 then
                    bits(10)
                    act.spike_param, act.spike_message = bits(14), bits(10)
                end
                t.actions[#t.actions + 1] = act
            end
            a.targets[#a.targets + 1] = t
        end
        return a
    end)
    return ok and res or nil
end

-- Treasure Hunter levels announced in an 0x028 action packet: { [mob id] = level }.
function logic.th_from_action(data)
    local a = logic.parse_action(data)
    local out = {}
    if not a then return out end
    for _, t in ipairs(a.targets) do
        for _, act in ipairs(t.actions) do
            if act.add_message == logic.MSG_TH_PROC and act.add_param then out[t.id] = act.add_param end
        end
    end
    return out
end

-- 0x029 Message Basic carrying message 603 (what a server-side "starting TH"
-- announcement would send): mob id, level -- or nil.
function logic.th_from_message(data)
    if #data < 0x1A then return nil end
    local function u32(o) local a, b, c, d = data:byte(o + 1, o + 4) return a + b * 256 + c * 65536 + d * 16777216 end
    local msg = (data:byte(0x18 + 1) + data:byte(0x19 + 1) * 256) % 0x8000
    if msg ~= logic.MSG_TH_PROC then return nil end
    return u32(0x08), u32(0x0C)
end

return logic
