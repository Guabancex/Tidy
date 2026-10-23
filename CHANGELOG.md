# Changelog

All notable changes to Tidy. Newest first.
Versions follow `MAJOR.MINOR.PATCH`; the version is also shown in Tidy's window,
its load message, `/tidy help`, and the download file name.

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
