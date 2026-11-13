# UI parity status (Minecraft Java 26.3)

Source of truth order used: imported 26.3 assets/metadata (sprites, `.png.mcmeta` nine-slice data, `lang/en_us.json`,
`flat_level_generator_preset` data, asset-index panorama/lang files) → known Java screen geometry (1.20–1.21 layouts,
recorded below) → this project's UI spec. No Mojang code is decompiled; geometry comes from documented/observed layouts.

## Foundation (Gate 0)

| Piece | Where | State |
|---|---|---|
| GUI scale rule | `Settings.gui_scale()` | vanilla `max(1, min(w/320, h/240))`, user cap; Auto default |
| Nine-slice sprites | `UiKit.nine()` | border from each sprite's `.mcmeta`, texture pre-scaled by the GUI scale (nearest) so borders/texels are 1 GUI px at any scale; edges + centre tile (`stretch_inner` false) |
| Button text | `McButton` | white / 0xA0A0A0, shadow, Java `renderScrollingString` for overflow |
| Cycle / on-off / edit box | `McW` | `Label: Value`, shift-click reverses; EditBox 0xE0E0E0 text, 4 px inset |
| Slider | `McSlider` | slider / slider_highlighted track, 8×20 handle, centred label |
| Selection list | `McList` | Java AbstractSelectionList: list background, header/footer separators, row outline (white focused / 0x808080), scroller sprites, wheel = item_height/2, drag, keys, 250 ms double click, row-embedded widgets, clipped rows |
| Tabs | `McW.TabButton` | tab sprites, menu background inside the open tab, underline |
| Backgrounds | `UiKit.background` + `PanoramaBg` | title: panorama (2°/s, 10° pitch, FOV 85) + overlay; other out-of-game screens: blurred panorama + `menu_background` tiled 32 px; in-world: blurred world + `inworld_menu_background`; containers: vanilla gradient dim, no blur |
| Text | `UiKit.font()` | installed ascii bitmap provider; Label glyphs sit 1 GUI px low vs `drawString`, compensated at placement |
| Language | `Res.set_language()` | any installed language (asset index), merged over en_us, live |

## Verified by screenshot (2880×1800, GUI scale 3, 2026-11-12)

title.main, world.select, world.edit, world.delete_confirm, world.create.game/world/more, world.superflat_customize,
world.superflat_presets, world.single_biome, world.gamerules_create, game.pause, game.world_options (both tabs),
options.main, options.video, options.keybinds, options.language, options.resourcepacks, container.player,
container.creative, container.crafting + recipe book, container.chest, container.loom, game.death, HUD (survival state), item /
widget tooltips.

Containers: hovered slot uses container/slot_highlight_back + slot_highlight_front (24 x 24); empty armour / offhand /
brewing / enchanting / loom / horse slots show the container/slot/* silhouettes; F3+H toggles advanced tooltips.

## Known deviations

See `UI_REFERENCE_GAPS.md` (missing reference data) and `UI_LAYOUT_DECISIONS.md` (deliberate choices).

## Performance notes

Menus run at 60 fps with vsync (`Settings.set_in_menu`). Lists are virtualised (only visible rows drawn; widgets
for off-screen rows hidden). Sprites and nine-slices are cached per GUI scale; `UiKit.reset_theme()` clears them.
Language names are scanned once on a worker thread and cached in `user://lang_names.json`.
