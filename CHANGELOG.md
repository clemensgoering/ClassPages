# Changelog

## Unreleased

First public version.

**Class window (`/cp`)**
- One window per class with tabs for overview, talents, trainer, class pages and the HUD editor. Minimap button and an entry in the addon compartment.
- Talent planner for all three trees: several saved plans, export and import as text, comparison with your current talents.
- Level plan: the planned points are ordered, the window shows which talent comes next and a chat line reminds you at level-up.
- Trainer tab: what you can learn now, in the next two levels and later, with costs. Filled after one visit to the trainer.
- Class pages for all nine classes: class quests, items worth getting and useful professions, filtered by level, with a live status. Entries that could not be confirmed are marked with "~".
- Hunter: tameable beasts worth catching per level, and a pet tab with the active pet, the stable and beast training.

**Action bars**
- Any number of bars with free grid, button size, spacing, scale, opacity and position. Spells, items and macros by drag and drop.
- Class presets from the spells you know. Every class also gets a pet bar and a stance bar preset.
- Per bar: cooldown swipe, ready flash, glow for reactive abilities, proc glow, range tint, counters for items, reagents and ammunition with a warning colour.
- Visibility rules: only in combat, only with a target, per stance or form, fade in on mouseover.
- Pet bar with markers for the active action and for autocast; right click toggles autocast.
- Square button tiles with a thin frame that fit the icons at every size.
- Edit mode with snapping, a resize grip and a popover for the values.
- Key bindings by hovering a button and pressing a key, and "Keys 1–0" to give a bar the keys of the main bar in one click.
- "Hide game bars": hides the game's main bar, and its pet and stance bars while your own bars replace them. Vehicles and controlled units get the game's bars and keys back automatically.

**Data and stability**
- Profiles for bars, shared between characters if you want.
- Saved data is never reset. A backup is written before each data migration and before every delete; the migration backup is kept separately.
- Buttons of a type an older version does not know are kept and return after an update.
- Values hidden from addons in combat are passed to the game's widgets and never compared.
- Bursts of pet and talent events are handled once instead of once per event.
- English and German.
