# UI reference gaps

Things implemented without an exact 26.3 reference (no side-by-side capture of the official client was possible in
this environment; the official client is not launched by the agent). Each is a candidate for correction once a
reference screenshot exists.

| Area | What is uncertain | Current choice |
|---|---|---|
| Select World | 26.x uses HeaderAndFooterLayout; exact header/footer heights | 1.20 absolute geometry: search y22, list 48..h-64, buttons h-52 / h-28 |
| World Options (26.3) | No layout reference at all; only lang keys | Tab bar General / Multiplayer + 2-column 150-px grid at 1/6 of the tab area, Done 200 |
| Restrictions / Lock World | No 26.3 lang keys for a Restrictions screen | Not built (manifest: reference_unknown) |
| Video Settings | Exact row order inside each 26.x section | Grouped under the three 26.x section headers by topic |
| Options root | Second header button in-world (Difficulty moved to World Options in 26.3?) | FOV slider + Online... in both contexts |
| Creative tabs | Tab membership/order of items | Heuristic category() + sort (creative_screen.gd) |
| Key Binds | Category membership of Recraft-only actions (hide HUD, debug, pause) | Miscellaneous |
| Pack screen | 26.x search box / layout | 1.20 PackSelectionScreen geometry |
| Language list | Vanilla sort key | Sorted by display name |
| Title | Fade-in of panorama/logo on first show | Not implemented |
| Trees (world, not UI) | Poplar foliage approximate | see PROGRESS.md |
| Enchanting table | Animated 3D book on the left of the GUI | Not drawn |
| Smithing table | Armor-stand preview and cycling empty-slot icons | Not drawn / static |
| Recipe book | Ghost recipe for uncraftable entries; recipe collections (groups) | Click does nothing on red entries; one button per recipe |
| Item tooltips | Attribute modifier lines, rarity colours, enchantment lines | Name only (+ F3+H durability / id) |
| Advancements | title_box hover widget | Tooltip renderer |
| Statistics | 26.x tabbed layout | 1.20 button layout |
