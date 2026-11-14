# Changelog

All notable changes to Tidy. Newest first.
Versions follow `MAJOR.MINOR.PATCH`; the version is also shown in Tidy's window,
its load message, `/tidy help`, and the download file name.

## 2.12.3
- **Lighter on memory.** The folded crystal is drawn every frame and made about 70 KB of throwaway tables doing it
  (every point, colour and its 3D model, fresh each frame). It now reuses them: about 14 KB a frame, drawn
  exactly the same (checked call for call). The window pages also draw a little faster.
- The Stats page works out the week once a second instead of every frame.
- Removed 11 unused values (old colours, a corner radius, an unused opacity read), which also frees room in the
  main file's 200-variable limit.

## 2.12.2
- **Fixed: changing the UI size crashed Tidy.** The slider (and `/tidy scale`) made Tidy reload itself from inside its
  own frame. Now the size applies at once with no reload; the text is scaled until the next load builds the fonts
  sharp at that size.

## 2.12.1
- **Fixed: saving the UI size or the window/crystal spots could fail** ("Could not save the size") when
  `config/addons/tidy/` didn't exist yet. Tidy now makes the folder first.

## 2.12.0
- **UI size slider** in Settings > Look, under Window opacity: **Auto** (follows your resolution: 1080p 1x, 1440p
  1.25x, 4K 2x -- it shows the size Auto picked) or 0.75x to 3x in quarter steps. Let go to apply: Tidy saves it and
  reloads to rebuild the fonts at that size (same as `/tidy scale`). Letting go where it was does nothing.
- Code: the UI-size table is declared with the other state at the top, so the Settings page and `/tidy scale` use it
  directly (the command went through a test-only global before). A test that left a stub behind is fixed.
- 83 tests.

## 2.11.3
- **Fixed: the Bag page didn't list your items (2.11.2).** The new Trade button's code sat above two UI helpers it
  uses, so they didn't exist yet there; the Bag page hit an error on its first item and drew nothing after it
  (the trade list's rows too). Moved below them. New test: the Bag page draws every item with its Trade button.
- 82 tests.

## 2.11.2
- **Trade buttons beside items.** Every item on the Bag page and on the trade list has a **Trade** button: it trades
  just that item -- every copy, or its trade-list count -- to the open player trade, or to the NPC you target
  (within 6 yalms). Asks first. The item doesn't have to be on the trade list.
- 81 tests.

## 2.11.1
- **Trade how many.** Each trade-list item has a count: the - / + box beside it on the Want page (Ctrl-click
  steps by 12) and an **All** button, or `/tidy trade add 12 Fire Crystal` / `/tidy trade count 12 Fire Crystal` /
  `/tidy trade count all Fire Crystal`. A count can take part of a stack (15 = a stack of 12 and 3 of the next).
  `/tidy trade list` shows each count. Shared lines carry it (`x=4096x12`).
- 80 tests.

## 2.11.0
- **New: trading.** A trade list per profile (Want page, or `/tidy trade add <item>`): those items are never dropped
  or sold, and are handed over when you trade.
  - **Player:** when a trade window opens, Tidy asks "Put N stacks in the trade with <name>?" and fills it, trade
    slots 1-8 (slot 0 is gil), one stack every 0.3 s. You still check the window and press Trade yourself.
  - **NPC:** target it within 6 yalms, then **Trade to my target** or `/tidy trade`: after a Yes, up to 8 stacks go
    in one trade (0x036), the same packet the game's trade window sends.
  - Equipped, bazaar and locked copies are never traded. Packet layouts checked against LandSandBoat's handlers.
- Shared profile lines carry the trade list too (`;x=...`; older lines still import).
- 78 tests.

## 2.10.0
- **New: farm goals.** On the Want page (or `/tidy goal 12 Bone Chip`): the item is kept until you hold that many,
  even when it's on your trash list or a mob's junk. A progress bar shows how close you are; Tidy says once when
  you reach it. After that only new copies go, by your normal rules (dropped, or kept for the shop in Sell mode),
  so the goal's stack stays. `/tidy why` names the goal.
- **New: Stats page.** The last 7 days for this character: gil from sales, items dropped, gil per day, top sellers
  and most-dropped items. Saved with your character (at most every 30 seconds, and on unload); older days are
  dropped on their own. `/tidy stats` opens it.
- **New: share a profile.** Settings > Share > Copy this profile (or `/tidy export`) copies one line --
  `TIDY1;name;t=...;w=...;g=...;v=...;r=...` -- with the trash list, want list, goals and keep rules. Import
  (paste the line, or `/tidy import` reads the clipboard) asks first, then adds it as a new profile and switches to
  it; your own profiles are never changed. Only item ids travel, checked against your game data; anything else is
  left out.
- The window's smallest height is 410 so all nine pages and the lock fit.
- 72 tests.

## 2.9.1
- **Sell mode: every shop is offered.** The game sends nothing when you close a shop, so Tidy treated the first
  shop as open until you zoned: the next shop in the same zone got no "Sell these?" offer, the header kept saying
  AT SHOP, and Sell buttons queued sales with no shop open. A shop menu keeps you still, so Tidy now counts the
  shop as closed as soon as you move away from where you opened it.
- **Faster in big fights:** the Treasure Hunter reader parses action packets a byte at a time instead of bit by
  bit (about 2.4x faster on every action packet).
- **Less repeated work:** each mob's drop rows are built once per session, not every half second and every
  frame, and item names are looked up once.
- Code clean-up: removed three unused drawing helpers, a dead "Sold" branch in the drop loop, and a duplicate
  entity lookup in the loot handler. New test: walking away from a shop lets the next one offer again (66 tests).

## 2.9.0
- **Auction house mode removed** (2.8.0-2.8.2): no AH prices, List / AH buttons, LIST ON AH or `/tidy ah`. Tidy sells
  to NPC shops only, exactly as in 2.7.2. Any saved AH prices are simply ignored.
- New README, banner and screenshot.

## 2.8.2
- **AH buttons**: **List Xg** next to a priced item on the Bag page (lists that item), **AH** next to an unpriced
  one (adds it to AUCTION HOUSE PRICES), and **LIST ON AH** on the Settings page / `/tidy ah now` (lists everything
  you priced). They work with AH mode off too; each asks first and needs the auction house open.

## 2.8.1
- **AH prices are yours**: no database export -- set each item's Single / Stack price on the Rules page (AUCTION
  HOUSE PRICES) or with `/tidy ah price <single> [stack] <item>`. With AH mode on, every copy of a priced item is
  kept and listed at that price when you open the auction house. `tools/ah_export.py` is gone.

## 2.8.0
- **Auction house mode** (`/tidy ah on`, or **Sell on the auction house** on the Hunt rules page): trash worth more on
  the AH than to an NPC is kept; when you open the AH, Tidy asks (Yes / No) and lists it -- full stacks as stacks,
  the rest one at a time -- with the same two packets the client sends (0x04E AskCommit, then LotIn). It checks the
  bag after each listing and stops after two refusals in a row (listings full or not enough gil for the fee).
- Prices: `data/ah_prices.lua`, exported from the server's database by the new `tools/ah_export.py` (lowest current
  listing, else median of the last 10 sales). Items AH mode keeps are left out of NPC selling.

## 2.7.2
- **Selling fixed (again)**: the server only accepts the sale (0x085) when the packet right before it is the
  appraisal (0x084). Tidy waited for the price before selling, and in that gap the game sent its own packets
  (position updates), so every sale was refused. Tidy now sends the two together, the way the client does.
- Tidy checks the bag after each sale: gone = sold (logged, gil counted); still there = it says the shop didn't take
  it and moves on.
- Only the main inventory is sold from (shops buy nothing from a satchel or sack).

## 2.7.1
- The folded crystal comes back exactly where you last left (or locked) it, after a restart too, and the full
  window where you left that -- each kept separately in its own file (`config/addons/tidy/window_pos.txt`), which
  is there at game start, before your character's settings arrive.
- Tidy's window keeps its place across versions (its ImGui id no longer includes the version number).

## 2.7.0
- **Selling fixed**, checked against the server's own source: the shop answers the price request (0x084 -> 0x03D)
  but answers the sale (0x085) with a chat message and an inventory update, not a second 0x03D. Tidy was waiting for
  that, gave up after 3 seconds and closed the shop. It now sells straight after the price, one stack every 0.6s.
- **Kept loot is counted**: Sell mode now remembers how much new loot it kept (saved), so it's still sold after you
  zone into town. Before, zoning made the kept loot read as "copies you already had", and nothing was offered.
- **Are you sure?** A Yes / No prompt before selling to a shop (it names the items and the gil), before a Sell button
  sells, before a Trash button adds to the trash list, and before `/tidy drop`. Switch: **Ask before selling or
  trashing** (Hunt rules page) or `/tidy confirm on|off`.
- An item the shop won't price is skipped instead of stopping the selling.
- `/tidy scale` works again (it errored).

## 2.6.0
- Selling no longer uses `/sellit` (that command doesn't exist in game). Tidy now sells at NPC shops itself:
  with Sell mode on, trash an NPC buys is kept, and when you open a vendor's Sell list Tidy sells it all and
  reports the gil in chat.
- The **Sell** buttons on the Bag page and Trash list sell that item while a shop is open.
- `/tidy sellcmd` removed.

## 2.5.0
- Sell mode has a button now: **SELL ON / SELL OFF** in the header, next to PAUSE (the status reads SELLING when on).
  The switch on the Hunt rules page and `/tidy sell` still work.
- A **Sell** button next to every item an NPC buys -- on the Bag page (with what the stack sells for) and on the
  Trash list for items you're carrying. It sends `/sellit <item name>` right away.
- Every sell now says in chat exactly what it sent (`Sell: /sellit Bat Wing`), so you can see it go through.
- Sell mode waits 15 seconds (was 8) for an item to sell before dropping it instead.

## 2.4.2
- The folded crystal is green again (Tidy's colour), on FFXI Questlog's crystal model.

## 2.4.1
- First launch opens the window at 600, 400 for setup (until you move it -- after that it reopens where you left it).

## 2.4.0
- UI size for 1440p / 4K: text, sidebar, pages, spacing, the resize corner and the folded crystal all scale
  together. **Auto** by default from your game resolution (1080p 1x, 1440p 1.25x, 4K 2x). `/tidy scale 0.75-3`
  to set it yourself, `/tidy scale auto` to go back (reloads Tidy to rebuild the text sharp). Kept in
  `config/addons/tidy/ui_scale.txt`, so it applies from game start.

## 2.3.0
- **Sell mode.** Trash an NPC would buy goes through `/sellit` instead of being dropped; trash no NPC buys is
  still dropped. Turn it on with the **Sell instead of drop** switch (Hunt rules) or `/tidy sell on`. If a sell
  doesn't go through within a few seconds the item is dropped instead, so the bag never clogs. `/tidy sellcmd`
  changes the command (`{name}`, `{count}`, `{id}` are filled in; default `/sellit {name}`). The drop log marks
  each line SOLD or drop.
- The folded crystal is now FFXI Questlog's crystal exactly -- same model and colours.

## 2.2.0
- The folded green crystal is now a real 3D model: a six-sided shard turning on its axis (one full turn every 6 seconds), tipped toward you and lit from the upper left, so each facet brightens and darkens as it comes around.
- Aether look: a flat ink panel with the top-left corner cut off, a faint edge all round, and the cut lit in Tidy's pale blue. Tidy's own colours are unchanged.
- Barlow Semi Condensed type (fonts/, SIL Open Font License); falls back to the default font if missing.

## [2.1.0] - 2026-10-29

### Changed
- Folded, Tidy is now FFXI's home point crystal in green (the same design as
  FFXI Questlog's, which is blue): a tall shard turning slowly over a glowing
  rune circle, with green flames flickering round its foot and a glint at its
  tip now and then. Grey and still while Tidy is off or paused.

## [2.0.0] - 2026-10-29

### Changed
- Designed after Final Fantasy XV's menus: smoked blue-black glass shading to
  near black (still set by the opacity setting) with white hairlines along the
  top and bottom and a cool sheen; T I D Y in spaced white capitals after a
  pale blue diamond; the open page on a bright light band, fading to the right,
  in dark type with a chevron; pale blue for on / kept / wanted, a muted red for
  drops, soft gold for gil, periwinkle for places and extras; white hairlines,
  light-band hovers and pale blue frames on buttons, sliders and tooltips.
- The pink glowing border and its racing lights are gone: FFXV's menus are quiet.
- Folded, Tidy is now a green FFXI crystal: a long double point with a
  six-sided girdle, turning slowly and floating in a soft green glow, its
  facets catching the light, with a glint now and then. Grey and still while
  Tidy is off or paused. Click, right-click and drag work as before.

## [1.8.0] - 2026-10-24

### Changed
- New look, matching Wayfinder's cinematic menu style while keeping Tidy's
  1980s colours: square corners; a dark midnight-violet glass that shades to
  near black (still set by the opacity setting) with pink hairlines along the
  top and bottom; the TIDY title letter-spaced after a hollow diamond, with a
  fading pink rule under it; pages in the sidebar in spaced capitals, the
  open one lit by a pink light band with a chevron; section rules that fade
  out; key-cap buttons with hairline frames (cyan for the main action);
  ON / OFF toggles with a square check box; hairline sliders with a diamond
  knob; square tooltips. The pink border glow and the pear-cut gem stay.

## [1.7.2] - 2026-10-23

### Fixed
- The gem's facet colours are capped at full brightness when the glint
  passes over them.

## [1.7.1] - 2026-10-23

### Changed
- The folded gem is now pear cut: a green teardrop, point up, with a flat
  table facet and a ring of angled facets that light up as a glint sweeps
  round the stone. The breathing glow, shine and twinkles stay; grey and still
  while Tidy is off or paused.

## [1.7.0] - 2026-10-23

### Changed
- Folded, Tidy is now a twinkling green gem like the one in the CatsEyeXI art
  instead of the blinking eye: a glossy green cabochon with a soft breathing
  glow, a shine, a band of light that drifts across it like a cat's-eye
  stone, and star twinkles flashing in turn. Grey and still while Tidy is off
  or paused. Click, right-click, drag and Lock work as before.

## [1.6.0] - 2026-10-23

### Added
- Lock switch at the bottom of the sidebar: pins the window and the folded
  green eye in place so they can't be dragged. Turn it off, or type
  `/tidy lock`, to move them again. Saved with your settings.

## [1.5.0] - 2026-10-23

### Changed
- Tidy's window is designed like YunaUI (Ashita build 4), in the same 1980s
  palette: a rounded midnight-violet panel with a thin pink edge, YunaUI's
  switches (dark pills, tinted when on, white knob), sliders (sunset-to-cyan
  track, white knob with a halo), rounded buttons with a cyan edge, spaced
  section names, diamond marks in the sidebar, and the TIDY letters flowing
  pink to violet like YunaUI's title.
- Replaces the flat look from 1.4.5. The pink border glow and the blinking
  green eye when folded stay.

## [1.4.9] - 2026-10-23

### Changed
- Each blink of the folded eye swaps it between its calm green look and an
  "awake" look: a molten gold iris with light rippling out from a wide diamond
  pupil.

## [1.4.8] - 2026-10-23

### Changed
- Folded, it's just the eye now: no tile, no border and no glow round it.

## [1.4.7] - 2026-10-23

### Changed
- The folded green eye blinks now: every few seconds the lids sweep shut and
  open again (every third time, a quick double blink), out of step with FFXI
  Questlog's pink eye.

## [1.4.6] - 2026-10-23

### Changed
- Folded, Tidy is now just the CatsEyeXI green cat's eye in a small tile with
  the pink neon glow. Click it to open the window, right-click to turn Tidy on
  or off, drag it to move it. Hover it for the state, drop count and current
  fight. The eye goes grey while Tidy is off or paused.

## [1.4.5] - 2026-10-23

### Changed
- Flat look, open and folded: square corners everywhere, solid colors instead
  of gradients, no drop shadows or inner glow.
- The border glow is solid hot pink now (no color cycling); it still pulses and
  the two comets still race round the edge.

## [1.4.4] - 2026-10-23

### Changed
- The border glow is animated now: the neon round the window's edge shifts
  slowly through hot pink, sunset orange and electric cyan and pulses, and two
  bright comets race round the border trailing light. Works on the folded bar too.

## [1.4.3] - 2026-10-23

### Changed
- The glow now goes round the window's borders: a soft hot pink neon glow
  spreads outward from the whole edge of the window (and the folded bar) and
  breathes slowly. The wordmark is back to plain drifting colors.

## [1.4.2] - 2026-10-23

### Changed
- A glow instead of sparkles: a soft neon halo breathes slowly behind the TIDY
  wordmark (drifting from pink to cyan), the letters bloom a little with it,
  and the window's neon edge breathes in time.

## [1.4.1] - 2026-10-23

### Added
- Sparkles: small four-point stars twinkle in turn around the TIDY wordmark,
  and one glides slowly round the window's neon edge.

## [1.4.0] - 2026-10-22

### Changed
- New window, laid out like YunaUI's settings panel and kept in the 80s Miami
  colors:
  - A rounded, see-through midnight-violet panel with a glowing hot pink neon
    edge.
  - A sidebar on the left: the big TIDY wordmark (its letters drift from hot
    pink through sunset orange to electric cyan) over sunset stripes, the
    version, and one row per page with its count. The open page glows pink with
    a cyan line under it. A slanted divider, lit pink at the top, separates it
    from the page.
  - Round on/off switches instead of check boxes, and pink-to-cyan sliders with
    a white knob.
  - Section names in spaced capitals with a faint line to the edge; rounded
    buttons with a pink neon edge; round - and x buttons in the corner.
  - Tooltips are dark violet cards with a pink-to-cyan line along the top.
- The main ON / OFF button is now a switch at the top of the page column.
- The window starts at about 660 pixels wide and can be resized from 600 x 380
  up to 1200 x 1100.

## [1.3.1] - 2026-10-20

### Added
- Resize corner: drag the three short lines at the bottom right of the window
  (they light up acid green) to make Tidy bigger or smaller, from 440 x 300 up
  to 1200 x 1100. The page panel fills the window. Tidy remembers the size,
  also after folding to the slim bar and back.

## [1.3.0] - 2026-10-20

### Changed
- New look: an editorial, avant-garde design, in the same family as FFXI
  Questlog.
  - Ink-black panel, bone-white type, square corners and thin rules; no
    gradients or round shapes.
  - Masthead: a vermilion block, a large TIDY wordmark, letter-spaced
    INVENTORY CLEANER, and a heavy rule.
  - What's been dropped and its NPC value in big numbers.
  - The page buttons are now one row of text tabs; the open page is underlined
    in acid green.
  - Section headings get a vermilion tick and letter-spaced capitals.
  - Colors: acid green for on / kept / wanted, vermilion for dropped, ochre for
    gil, lilac for places and extra drops.
  - The status dot is now a square: pulsing acid while dropping, ochre when
    paused, a dash when off.
  - The folded slim bar matches.
- Same window size as before.

## [1.2.1] - 2026-10-18

### Changed
- Treasure Hunter is read live from the game's own packets: the proc arrives
  inside the attack's action packet (0x028) with the mob's new level, so Tidy
  sees every proc on your mob, from anyone in the party, whatever your chat
  filters show. The chat line is still used as a backup.
- A server-sent message 603 (0x029) is read too, so a server that announces a
  mob's starting TH gives Tidy the exact level from the first hit.
- A remembered TH level for a mob you stopped fighting is forgotten after 10
  minutes, since it may have died and respawned at TH 0.
- No web or outside connection: everything comes from packets the game client
  already receives.

## [1.2.0] - 2026-10-18

### Added
- Drop tables show each item's chance per 100 kills at the mob's Treasure
  Hunter level, using CatsEyeXI's Treasure Hunter table. Hover a row for the
  chance with no TH.
- Treasure Hunter level on the Fight page:
  - **seen**: exact, read from the game's "Treasure Hunter effectiveness ...
    increases to N" message;
  - **est.**: before a proc, from your Thief trait (main or subjob), your
    equipped TH gear, and any Thief in your party, with the server's caps
    (8 for a Thief main, 4 otherwise);
  - **set**: chosen by you on the Settings page or with `/tidy th <0-14>`;
    `/tidy th auto` goes back to working it out.
- The drop database includes Treasure Hunter gear (from `item_mods.sql`) and
  drop groups.

### Fixed
- Grouped drops showed the item's weight inside its group as if it were the
  drop rate (for example 14.2% instead of 3.4%). They now show the real chance:
  the group's chance times the item's share of the group.

## [1.1.1] - 2026-10-17

### Changed
- Window is a little bigger: about 540 px wide (was 450), and the page panel
  can be up to 360 px tall (was 280).
- Drop tables show item names up to 26 characters (was 22) before shortening.

## [1.1.0] - 2026-10-17

### Added
- The window folds down to a slim bar with the **-** button or `/tidy mini`.
  The bar shows Tidy's state, what it has dropped and the mob you're fighting;
  click the state to turn Tidy on or off, **+** to open the full window again.
  Tidy remembers whether it was folded.
- Status dot beside ON/OFF: pulses mint while dropping, gold when paused, gray
  when off.
- The last dropped item flashes under the title, then fades.

### Changed
- Fading mint accent lines, section headings on every page, striped drop
  tables, and colored chips for each item's rule: DROP, WANT, VALUE, RARE, KEEP.

## [1.0.9] - 2026-10-17

### Changed
- Compact window: narrower, shorter page panel, tighter spacing, page buttons
  in two rows. Long lines are clipped instead of widening the window.

## [1.0.8] - 2026-10-17

### Changed
- New look: dark panel with mint accents (coral = dropped, mint = kept,
  gold = gil, lavender = places and extras).
- Custom header with the version and a close button.
- Pill buttons for ON/OFF, Pause and the pages; pages replace the tabs.
- Pages sit in a framed panel that scrolls, so the window keeps one size.
- If drawing the window fails, the window says so and the error goes to chat.

## [1.0.7] - 2026-10-17

### Added
- **Extra drops**: loot that isn't on any drop list (such as Ramuite). Learned
  automatically from the treasure pool as **Keep**; set one to **Use rules**
  to let Hunt's keep rules decide. `/tidy extra` commands.
- Type-ahead item picker on the Trash, Want and Extra pages: type part of a
  name and click it, even for items you don't have.
- Search box on every list.
- Status bar with on/off, **Pause** (this session only), **Reload**, and
  session totals. `/tidy pause` and `/tidy reload`.
- Drop log with times and NPC value.

### Changed
- The window is split into tabs: Fight, Trash, Want, Pinned, Extra, Bag, Log,
  Settings.
- The drop database also stores the sell price and Rare/Ex flags of every item
  that has them, so Extra drops get the same keep rules.

## [1.0.6] - 2026-10-17

### Changed
- The window sizes itself to its contents, between a readable minimum and a
  share of the screen.

## [1.0.5] - 2026-10-16

### Fixed
- An error ("boolean ... name") when loot arrived from a mob Tidy hadn't seen
  you fight.

## [1.0.4] - 2026-10-16

### Changed
- Hunt reads the mob you're actually attacking, not only your cursor target.
- When Tidy can't see your mob, it says why (window and `/tidy why`).
- Not engaged, the window previews the monster under your cursor so you can
  pin it.

### Fixed
- Pinned mobs no longer appear to vanish when the list changes.

## [1.0.3] - 2026-10-16

### Changed
- Window opens at double size; full item names in drop tables.

## [1.0.2] - 2026-10-16

### Added
- Version shown in the window title, the load message and `/tidy help`.

## [1.0.1] - 2026-10-16

### Fixed
- A game crash while drop tables were on screen.
- Window drawing is guarded, so an error can't take the game down.

### Added
- `/tidy why` explains why each item is or isn't dropped.
- `/tidy drop <item>` drops one stack immediately to test that drops work.

## [1.0.0] - 2026-10-16

### Added
- First release.
- Trash lists: items on the active profile's list are dropped on sight.
- Profiles with separate lists and settings.
- Hunt mode with the CatsEyeXI drop database: drops the useless items from the
  mob you're fighting (Auto) or from pinned mobs, keeping items marked Want,
  Rare/Ex items, and anything worth at least the Keep value. Only new loot is
  dropped.
- Never drops gil, equipped items or bazaar items. Off until you turn it on.
