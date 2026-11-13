# UI screenshots

Captured from the exported ARM64 build at 2880×1800, GUI scale 3. Reproduce with:

- Out-of-game screens: `Recraft2.exe -- --ui=<route>` → `user://autoplay/ui_<route>.png`
  Routes: `title`, `world_list`, `edit_world`, `delete_world`, `create_world`, `create_world_world`,
  `create_world_more`, `game_rules`, `flat`, `presets`, `single_biome`, `options`, `options_video`,
  `options_sounds`, `options_controls`, `options_keybinds`, `options_language`, `options_packs`, `options_access`,
  `options_online`.
- In-world screens: `Recraft2.exe -- --autoplay --gen=java_26_3 --fresh --seed=12345 --screen=<name> [--gm=survival|creative]`
  → `user://autoplay/screen_<name>.png`. Names: `pause`, `inventory`, `crafting`, `options`, `world_options`,
  `world_options_mp`.

Screenshots are not committed (they contain Mojang assets rendered from the user's install); regenerate locally.

| Route | Last capture | Result |
|---|---|---|
| title | 2026-11-12 | panorama, logo + edition, splash, button rows match TitleScreen |
| world_list | 2026-11-12 | list band, separators, outline, scroller, footer rows |
| create_world (3 tabs) | 2026-11-12 | tab sprites, header separator, footer separator |
| game_rules / flat / presets / single_biome | 2026-11-12 | lists + footers |
| edit_world / delete_world | 2026-11-12 | centred layout / ConfirmScreen |
| pause / world_options | 2026-11-12 | blurred world + in-world background |
| options / video / keybinds / language / packs | 2026-11-12 | list shells, sliders, scrolling labels |
| inventory (survival, creative) | 2026-11-11 | vanilla container textures |
