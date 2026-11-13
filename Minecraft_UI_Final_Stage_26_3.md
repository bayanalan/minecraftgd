# MINECRAFT JAVA 26.3 — COMPLETE USER INTERFACE, SCREEN GEOMETRY & ANY-ASPECT-RATIO IMPLEMENTATION SPECIFICATION

**Standalone DEFERRED FINAL-PHASE execution contract · 10 November 2026 · Target: Godot 4.7.2 stable, typed GDScript · UI parity target: Minecraft Java Edition 26.3 (Wilderness Bound)**

> **DEFERRED FINAL PHASE — READ THIS NOTICE FIRST, CLAUDE CODE:** **Do NOT stop or interrupt ongoing game development to implement this file.** The detailed UI overhaul and any-aspect-ratio scaling implementation described here are the **LAST major workstream**, automatically activated **only after the entire non-UI game is implemented and verified** against the main master prompt. If encountered earlier, register this file as a deferred final-stage task, then **return immediately to the exact gameplay task you were doing**; do not read the rest, rebuild menus, redesign the HUD, or start screenshot-parity work yet. Temporary functional menus/HUD needed to develop and test gameplay are allowed, but they are not this UI overhaul. Once the final-phase gate is genuinely satisfied, read this entire document and implement it in the existing Godot project. At that time, this file takes precedence for every UI, layout, window-responsiveness, asset, accessibility, and UI-test detail. Never mark unverified screens complete.

**Goal:** Reproduce the *appearance, information hierarchy, placement, assets, interaction and transitions* of Minecraft Java 26.3 as closely as the installed owned reference permits, while going beyond vanilla with a **fully resizable application window, no required aspect ratio, no forced letterboxing/pillarboxing and no stretched/squashed controls**. Every playable flow must remain usable at narrow, square, portrait, ultrawide, high-DPI and in-between sizes. The 3D world fills the whole client area; menus adapt their layouts instead of deforming the game.

**Terminology / important distinctions:**
- **Vanilla parity** means the normal-sized UI matches a reference capture from *the exact installed Minecraft Java 26.3 build*, including coordinates in **GUI pixels**, text and sprites. The layouts in this document are **implementation targets and measurement guides**, not a false claim that every screenshot has already been pixel-measured. **Measure unverified values and replace approximations** with actual reference measurements before awarding parity status.
- **Responsive extension** is allowed to differ from vanilla *only when the vanilla geometry would overflow, be unreadable or be poorly arranged in the available shape*. Those differences must be deterministic, documented and tested. Vanilla's own min window is 320×240; our application may support smaller surfaces, subject to physical legibility limits.
- **Hardcore** is a world mode flag, not a fifth underlying numeric game mode; the normal game modes are Survival, Creative, Adventure, and Spectator.
- **Client installation assets** means locally owned Java Edition textures, GUI sprites, fonts, sounds, panorama and language strings. Import/cache privately on the user's computer; do not distribute Mojang assets with project, binaries, or source. Original artwork is allowed only as an explicit fallback when owned assets are absent; never silently represent a generic Godot theme as Minecraft-accurate.
- **If the user's installed reference is not available**, create the implementation with the detailed fallback metrics here, log each unverified location in `docs/UI_REFERENCE_GAPS.md`, and later validate when the reference becomes available. Do not hallucinate a real screenshot, Realms backend, Mojang sign-in, or success state.

---

# 0. ACTIVATION TIMING — POST-GAME UI PASS ONLY (OVERRIDES ALL TIMING LANGUAGE BELOW)

**This is a future work-order/specification, not a request to switch tasks today.** If handed to Claude Code while the main game is being built, the correct action is to **record one pending milestone** in `PROGRESS.md` or `docs/STATUS.md` — `FINAL PHASE: implement minecraft_ui_layout_scaling_26_3.md after full non-UI game completion` — and then resume the interrupted game implementation **unchanged**. Do not spend tokens rereading this lengthy file each session. No separate UI sprint or UI refactor is authorized before the gate below passes.

## 0.1 Absolute prerequisite: full non-UI game completion

The final UI phase may start **only when all gameplay, engine, and service requirements in `minecraft_godot_master_prompt.md` (including its Sections 18–36) have been implemented and objectively verified**. This means *all required non-UI systems*, not just a playable prototype, initial release, P0 gate, or Stage 8 checkpoint. The prerequisite explicitly includes:

- Deterministic terrain/world generation, all target biomes/dimensions/structures, infinite chunk streaming, saving/loading and versioned 1.18.2/26.3 generation modes.
- Every target block, item, crafting/recipe, inventory transaction, workstation **mechanic**, redstone/fluid/lighting system, farming, command, advancement, progression, game rule, and required play style; normal minimal screens may expose these for testing.
- All required mobs, variants, AI, spawning, combat, boss progression, movement/first-person and third-person animations, and player gameplay physics.
- Sound and **music playback** behavior, ambient soundscapes, jukeboxes/note blocks, effects, audio import, and accessibility/event data needed by the final UI.
- Real supported networking/multiplayer/LAN capabilities and external-service integrations **where genuinely implementable**, accurate disabled/error states otherwise, plus graphics/rendering settings backends, high-performance terrain rendering, and benchmarks.
- Successful end-to-end integration, regression/soak tests, profile-guided optimizations and reproducible builds; no unfinished, silently stubbed or falsely reported core feature.

**Evidence requirement:** Write `docs/GAMEPLAY_COMPLETE.md` only when the above *entire non-UI scope* is done, with links to automated test outputs, benchmark measurements, completed feature manifests, remaining blockers and the passing build/commit. **Unimplemented mandatory features, unresolved severe defects, or unverified parity do not satisfy this gate.** If the scope cannot be finished because of a genuine limitation, record that limitation and keep progressing on other game systems; do not invoke this UI phase merely because progress is hard, tokens are low, or a session ends. The user may explicitly change this ordering later, but Claude Code must not silently waive it.

## 0.2 Allowed BEFORE the gate — only functional scaffolding

- Keep the game launchable and testable with **basic functional** title, pause, world creation, settings, HUD, inventory, chat, and workstation interfaces as needed by the master game specification. Working gameplay input and non-UI feature tests must not depend on a finished 26.3 visual skin.
- Preserve resizable-window *capability* and clean scene/UI boundaries from the start so final scaling is possible later. Do not hard-lock the 3D viewport to 16:9, stretch player/world rendering, or entangle game mechanics with a particular display size. These are inexpensive engine safeguards, **not permission to implement the detailed responsive UI system early**.
- Do **not** start the screen-by-screen layout system, HUD pixel matching, texture-backed control redesign, font measurements, elaborate breakpoint testing, screenshot goldens, full UI manifest, or this document's Gates 0–5 before full non-UI completion.
- Do not throw away working placeholder UI or gameplay code until the final pass; replace/refactor deliberately with tests when the gate opens.

## 0.3 What to do AFTER the gate passes

1. Confirm `docs/GAMEPLAY_COMPLETE.md` exists and contains valid, current test/benchmark evidence rather than an unchecked assertion.
2. Make a clean checkpoint of the finished game, keeping gameplay tests green. **Only then** read the rest of this file in full.
3. Execute **Section 24, UI Gates 0 through 5**, in order, with the whole UI/UX/screen inventory and any-aspect-ratio scaling as the last major feature implementation phase. Integrate with live game systems; no disconnected mockup UI.
4. Run all UI layout, input, screenshot, resize and accessibility tests; then rerun the **entire gameplay regression suite** to ensure UI changes did not break the completed game.
5. Record final status honestly, including reference-only/online-service gaps, and ship the unified project. If a required part fails, keep fixing it rather than declaring all-UI completion.

**Precedence rule:** Every imperative elsewhere in this UI document (e.g. “start”, “read”, “implement”, “first”, “immediately”, “Gate 0”) is **conditional upon Section 0.1 passing**. This rule takes precedence over conflicting wording here, the other master prompt, and earlier chat instructions to interrupt current work. The contents specify *what to build later*, not *when to stop building the game*.

---

# 1. EXECUTION RULES: ACCURACY BEFORE VISUAL GUESSWORK

1. **Only after Section 0.1 is satisfied:** read this file fully and inspect the completed Godot project. Do not rewrite functioning gameplay systems. Isolate UI changes behind signals/service interfaces.
2. Create/maintain `docs/UI_SCREEN_MANIFEST.csv`, `docs/UI_REFERENCE_GAPS.md`, `docs/UI_PARITY.md`, `docs/UI_SCREENSHOTS.md`, and `tests/ui/` (or equivalent). Use one **registry entry per screen variant** and one **screenshot golden per breakpoint for representative screens**.
3. Use **locally installed 26.3 game assets as the primary visual source**, with a resource-pack override chain. Inspect 26.3 `assets/minecraft/lang/en_us.json`, `assets/minecraft/textures/gui/**`, GUI sprite metadata (`.png.mcmeta`), fonts and generated atlas metadata. The client JAR is a ZIP; don't execute, decompile, redistribute or transplant Mojang's proprietary game code. Public documentation and legally made visual observations are fair implementation references.
4. If locally feasible, launch the installed official Java 26.3 for **side-by-side manual or automated screenshots** at exactly matching client sizes and GUI scales. Record exact pixel rectangle of every visible widget: `screen_id, width, height, gui_scale, asset_id, rect[x,y,w,h], text, alignment, state`. Do not scrape accounts, passwords, player data or protected Realms endpoints.
5. **Source-of-truth precedence:** exact vanilla 26.3 screenshot & imported asset metadata → official 26.3 release notes / installed translations → 26.3 documentation → measured older Java Edition references → this document's explicit fallback geometry. Write a parity note if sources conflict. Never mix Bedrock's Ore UI with Java's UI.
6. **No generic Godot default controls** visible in final UI. Use themed, data-driven custom Controls that reproduce vanilla shapes and behavior. Custom GUI primitives should be reusable and testable, not one-off drawings of each screen.
7. **Every visible button must perform an action** or accurately display a genuine disabled/unavailable state with reason. Never create dead buttons or fake sign-in/Realms success flows. Backend-deferred features remain labeled as such in status rather than counted complete.
8. **Do not prioritize pretty refactoring over fidelity.** Do not introduce modern rounded corners, neumorphism, gradients, oversized paddings, blur panels or custom fonts in parity mode.
9. Incrementally test UI without requiring world generation, network, music or massive asset imports: create test state providers for each menu that supply realistic inventories, servers, messages and achievements.
10. Keep explanations short and spend execution time implementing, comparing, correcting, verifying. The file is the decision authority; do not ask repetitive design questions.

## 1.1 Mandatory files / interfaces

```text
ui/
  ui_manager.gd                 # Stack, navigation, overlays, pause coordination
  ui_metrics.gd                 # Geometry, GUI scale, DPI, responsive breakpoints
  ui_theme.gd                   # Asset/skin/color/font resolution
  ui_atlas_resolver.gd          # Sprite IDs, nine-slice, tile and animations
  ui_text.gd                    # Localization, font providers, shadow, wrapping
  ui_input_router.gd            # Mouse, keyboard, focus, gamepad, tooltips, drag
  ui_animation.gd               # Splash, widgets, overlays, focus and transitions
  ui_sound.gd                   # Click, hover, typing feedback, music routing
  ui_accessibility.gd           # Narration, font/contrast, subtitles, focus labels
  ui_screen_registry.gd         # Screen ID, parent route, state factory, scene
  ui_reference_capture.gd      # Screenshot/rect dumps for golden testing
  widgets/                      # MCButton, MCTextField, MCTab, MCSlider, MCList,
                                # MCCheckbox, MCSlot, MCPanel, MCTooltip, MCToast,
                                # MCScrollBar, MCIconButton, MCConfirm, MCItemIcon
  screens/                      # One scene + minimal controller per screen family
  containers/                   # Data-driven slot based screens, recipe book etc.
  hud/                          # Player HUD independent of menus
  debug/                        # Debug panels independent of regular GUI scale
  responsive/                   # Tiny / portrait / compact specialized arrangements
  import/                       # Installed Java fonts, GUI sprite metadata, skins

docs/UI_SCREEN_MANIFEST.csv
        UI_PARITY.md
        UI_REFERENCE_GAPS.md
        UI_SCREENSHOTS.md
        UI_LAYOUT_DECISIONS.md

tests/ui/ui_smoke.gd
         ui_all_routes.gd
         ui_hit_tests.gd
         ui_scale_tests.gd
         ui_accessibility_tests.gd
         ui_golden_compare.py   # Offline image analysis allowed; not game runtime
```

Don't build one monolithic `ui.gd` containing hundreds of hard-coded pixel rectangles. Keep engine-native Godot `Control` nodes and reusable widgets, with layout tables and genuine signal connections.

---

# 2. COMPLETE SCALING MODEL — THE MOST IMPORTANT REQUIREMENT

## 2.1 The application must NOT have an enforced aspect ratio

- A new window opens at approximately **1280×720** as a convenient initial size. This is **only a startup preference**, not a base canvas shape that limits later resizing.
- Users may drag any edge/corner continuously. The 3D camera/sky/fog, panorama and UI backgrounds fill the entire drawable client area at each resulting width/height.
- Fullscreen, borderless fullscreen, exclusive fullscreen when platform-capable, maximized, restored, and custom windowed resolutions are first-class modes. Preserve prior windowed size/position; clamp window to current display's work area if a display was unplugged.
- **Never use `keep` aspect mode on a fixed 16:9 viewport** for the game. No bars, image squashing, clipping, or layout anchored to a 1280×720 screenshot. Use actual viewport dimensions for geometry.
- **Never scale X and Y independently** for GUI sprites, fonts, buttons, item icons, inventories, hearts, logos or interactive regions. A square inventory slot must remain square at 5:4, 32:9 and 9:16.
- 3D camera FOV should expand the visible horizontal scene when aspect widens rather than stretching the frame; provide a documented narrow-portrait FOV policy that avoids dramatic fish-eye distortion. First-person viewmodel may need independent safe-area positioning/scale; **do not stretch the held item or arms**.
- A quick resolution change must *not* destroy an open inventory, cursor-carried stack, typed text, slider drag, scroll position or menu history. Re-layout current UI in place, then revalidate pointer capture.
- GUI scaling changes apply to menus, HUD and prompts; debug overlay has its **own scale setting** matching the Java 26.3 separation.

## 2.2 Two precise spaces, never confused

1. **Physical/drawable viewport:** width `P_w`, height `P_h` in the active Godot render/UI coordinate system (not arbitrary OS window-decoration dimensions). At high DPI, understand the conversion between logical window size and drawable framebuffer size; all UI calculations use the same coordinate system as Godot input and Control rendering.
2. **Vanilla GUI logical space:** width `G_w = P_w / S`, height `G_h = P_h / S`, where `S` is the *uniform* GUI pixel scale; text, sprites and slot coordinates are measured here. For stable integer pixel alignment, round widget edges after transforming as required by the chosen pixel-art mode.
3. **Screen-local panel space:** `L_x = (G_w - panel_width)/2`, `L_y = (G_h - panel_height)/2`. Slots and icons are positioned relative to these top-left coordinates; their **intrinsic size does not increase because the window becomes ultrawide**.
4. **Game-space HUD anchors:** hotbar centered at bottom, left-side vitals relative to hotbar, boss bars centered near top, scoreboard right, status effects top right, chat bottom left, debug overlays anchored independently. Use screen edges and safe margins, not a fixed rectangle.
5. **Adaptive spaces** (tiny/portrait): contain panels in available width, reflow menus from 2 columns to 1, use scroll viewports, and optionally choose a uniform fractional scale. The viewport remains full size.

## 2.3 Exact vanilla GUI scaling rule and our extension

Java's documented scale availability at normal sizes is:

```text
max_auto_scale = max(1, min(floor(P_w / 320), floor(P_h / 240)))
S_vanilla = max_auto_scale if user selected Auto
            else clamp(user_integer_gui_scale, 1, max_auto_scale)
G_w = P_w / S_vanilla
G_h = P_h / S_vanilla
```

Integer GUI pixels remain the source of truth for **classic parity mode**. For example, a 1920×1080 framebuffer has maximum Auto `min(6,4)=4` → logical GUI approximately 480×270. A 1280×720 framebuffer has Auto 3 → roughly 426.67×240. At 3440×1440, Auto 6 → about 573.33×240. These are not 16:9 fixed canvases: width varies independently of height. Source: Minecraft Wiki Java Options reference and official Java 26.3 minimum window rule.

**OUR responsive extension (not vanilla):** expose `Auto (Minecraft)`, explicit integer scales that fit, and optional `Adaptive/Fine Scale` (0.5×–6× depending on actual space) with a single uniform scalar. When a narrow viewport cannot fit the content in a 320×240 logical rectangle, prioritize *reflow/scroll* over shrinking text to illegibility. Fractional scaling is allowed only as a controlled last resort or explicit preference; apply nearest-neighbor for retro artwork and use font-rendering fallback tuned for legibility.

### Concrete resolution policy

| Drawable / shape | Vanilla-parity behavior | Responsive behavior if geometry does not fit |
|---|---|---|
| 1920×1080, 2560×1440, 3840×2160 | Auto integer scale; center panels at canonical logical sizes | None needed unless localization/accessibility enlargement |
| 1280×720, 1366×768, 1600×900 | Vanilla GUI scaling; classic layouts | Compact scroll panels only if long lists require |
| 1024×768, 800×600 | Vanilla scale; centered and bottom-aligned anchors | Keep classic two-column unless text overflow |
| 640×480, 640×360, 320×240 | Integer scale normally 1–2; canonical menu geometry | Compress vertical gaps, keep bottom actions accessible |
| 3440×1440, 5120×1440, 32:9, 48:9 | Wider 3D FOV; **menu stays centered**, never expanded full width | Tooltips/chat/right-side overlays may occupy their own edge zones |
| 1080×1920, 720×1280, 9:16 | Full-height 3D frame, landscape-sized central panel if it fits | Center content; long options lists use vertical space |
| 400×900, 320×800, narrow portrait | Uniform scale based on width | Single-column menus, scroll options, responsive title, sticky actions |
| 512×512, 1:1 | Center classic windows | Switch navigation/header density if needed |
| 600×300, 500×200, very short wide | Full-width 3D | Condense top/bottom chrome; internal scroll; compact HUD |
| 280×180, smaller than vanilla min | **Not vanilla parity** | Adaptive compact mode: smallest usable text+icons, scroll and reachable actions |

**Do not pretend that one physical pixel of screen space can display an entire readable UI.** The measurable promise is functional interaction at every physically usable window, graceful degradation at tiny dimensions, and never enforced aspect ratio. At impossible microscopic sizes the UI must not crash or lose state; prioritize recoverable resize / fullscreen controls.

## 2.4 Mandatory Godot implementation model

- Set rendering/stretching so the **game scene follows the full root window**, and don't let a fixed-ratio subviewport own the whole game. Recommended: handle UI scaling inside an always-full-size CanvasLayer/Control tree with uniform child scaling, using `Display → Window → Stretch` in a mode that avoids unintentional *second* scaling. Document exact project settings in `docs/UI_LAYOUT_DECISIONS.md`. Godot's `canvas_items` + `expand` can work, but if using manual GUI scale with it, ensure combined transform and pointer calculations are correct; a direct dynamic UI layer without base-size stretching is often simpler for a Minecraft GUI.
- Fullscreen `Control` root per screen. A **screen-local logical content container** is scaled uniformly. Viewport-filling background is separate and **not affected by GUI scale**. Parent retains real viewport dimensions; logical layer receives `G_w,G_h` and only one uniform scale `S`.
- Use `Control` anchors/offsets and layout Containers for flexible screens. Fixed pixel offsets are allowed **inside a centered Minecraft GUI panel** (slots, icon grids); **never** use fixed 1920×1080 screen coordinates.
- Nodes above a world camera: `CanvasLayer` with explicit draw order: world → HUD → dimming → modal menu → tooltip → notifications → accessibility/focus overlay. The UI's mouse capture mode must switch between gameplay and menu; on closing, return focus and recapture mouse appropriately.
- Listen for size/DPI/monitor changes; recompute UI metrics **once per viewport-size change**, not every frame. Cache font glyphs/regions; do not reimport the whole atlas or create dozens of theme resources during a resize.
- For pixel-art native GUI, sample nearest, align clip/slot edges to integer positions where possible, and implement nine-slice/tile sprite metadata precisely. If anti-aliased font is used as fallback, do not blur source art.
- Slot hit testing must be based on the *same inverse transform* as visual layout. Verify drag movement at all scales, including fractional and high-DPI. Use transformed `Control` local coordinates, not raw `InputEventMouseMotion.position` with guessed scale.
- Letterboxing and pillarboxing are unacceptable even on ultrawide or portrait; crop/tile background panoramas using cover-style logic. **World render resolution scaling is independent from GUI resolution scaling**.
- `DisplayServer`/`Window` platform differences: verify supported window modes instead of assuming borderless/exclusive always work on all OSes; provide correct fallback names and persistence.

### Reference GDScript — metric policy (adapt to real project API)

```gdscript
# ui_metrics.gd - uniformly scalable logical GUI rectangle, not a fixed aspect viewport.
class_name UIMetrics
extends RefCounted

static func calculate(drawable_size: Vector2i, selected_scale: int = 0) -> Dictionary:
    var pw: int = maxi(1, drawable_size.x)
    var ph: int = maxi(1, drawable_size.y)
    var vanilla_max: int = maxi(1, mini(floori(float(pw) / 320.0), floori(float(ph) / 240.0)))
    var wanted: int = vanilla_max if selected_scale == 0 else clampi(selected_scale, 1, vanilla_max)
    var s: float = float(wanted)
    var gw: float = float(pw) / s
    var gh: float = float(ph) / s
    var compact: bool = (gw < 320.0 or gh < 240.0)
    var portrait: bool = pw * 4 < ph * 3
    return {
        "physical": Vector2i(pw, ph),
        "gui_scale": s,
        "logical": Vector2(gw, gh),
        "vanilla_max": vanilla_max,
        "compact": compact,
        "portrait": portrait,
        "center": Vector2(gw * 0.5, gh * 0.5),
        "edge_safe": 4.0
    }
```

**Implementation note:** Godot's GDScript integer division behavior and logical-vs-physical window sizing must be verified on the actually installed 4.7.2 binary. In production, use explicit `floori(float(pw) / 320.0)` if necessary to avoid implicit type pitfalls. The snippet is the **policy**, not permission to skip an actual engine parse/run test.

### Responsive layout policy pseudocode

```text
On drawable-size, GUI-scale, locale, accessibility-font or DPI change:
  1. Read actual viewport coordinate dimensions.
  2. Compute vanilla Auto/integer scale; if chosen user scale exceeds fit, clamp.
  3. Compute logical screen dimensions and safe-area boundaries.
  4. Select screen-specific mode (classic / compact / portrait / tiny).
  5. Keep centered panels at intrinsic dimensions where possible.
  6. Move oversized scrolling lists into scroll containers; pin title and action footer.
  7. On narrow screen, turn multi-column forms into a single vertical list.
  8. On too-short screen, condense gaps and allow panel/viewport scrolling.
  9. Clamp tooltips to all four edges; never cover cursor/selection unnecessarily.
  10. Reconstruct visual bounds and hit-test transforms together.
  11. Restore text field focus, selection, scroll, carried inventory item and cursor.
  12. Draw a screenshot and assert layout invariants in automated tests.
```

## 2.5 Spatial design tokens — GUI logical pixels

These are **canonical default dimensions**, not arbitrary modern design sizes. Extract exact 26.3 values from installed GUI assets and validate against screenshots. All distances below are **logical GUI pixels before multiplying by `S`**.

| Token | Default | Rule |
|---|---:|---|
| `button_standard_width` | 200 | Centered single-column Minecraft button |
| `button_standard_height` | 20 | Same for disabled/hover/pressed states |
| `button_narrow_width` | 150 | Standard paired options/configuration buttons |
| `button_half_width` | 98 | Two adjacent buttons inside 200 wide region |
| `button_half_gap` | 4 | Two 98-wide buttons + 4 gap = 200 |
| `button_row_pitch` | 24 | Button height 20 + 4 gap |
| `button_bottom_margin` | 8 | Last 20px button begins at `G_h - 28` |
| `title_baseline_zone` | 14–22 | Most secondary menu title lines near logical top |
| `content_top` | 32–40 | Main menu body starts below title |
| `list_bottom_safe` | 42–58 | Reserve bottom action strip |
| `inventory_slot_pitch` | 18 | Every inventory grid step |
| `inventory_slot_inner` | 16 | Typical item icon pixel size |
| `inventory_skin_width` | 176 | Standard background panel width |
| `inventory_skin_height` | 166 | Common inventory/workstation height |
| `inventory_title_x` | 8 | Panel-relative text padding |
| `inventory_title_y` | 6 | Panel-relative title label top |
| `modal_dim` | measured | Sample from captured vanilla menu frame; no arbitrary blur |
| `tooltip_padding` | measure | Import tooltip theme geometry from source sprites |
| `widget_min_hit_area` | >= sprite visible area | Can add invisible touch target in compact mode without visual change |
| `portrait_outer_margin` | 6–10 | Must remain usable on narrow displays |

### Coordinate grammar (this makes every layout unambiguous)

- `C`: horizontal screen center `G_w/2`, `M`: vertical screen center `G_h/2`.
- `BL(w,h)` means bottom-left anchored rect `(left, G_h - h - bottom_margin)`.
- `TC(w,h,y)` means top-center rect `(C - w/2, y, w, h)`.
- `BC(w,h,bottom)` means bottom-center rect `(C - w/2, G_h - bottom - h, w, h)`.
- `CENTER(w,h)` means `(C-w/2, M-h/2, w, h)`.
- `P(x,y,w,h)` means **panel-relative** position `(L_x+x, L_y+y, w,h)`; use only for inventory containers and panels.
- `ROW2(y)` means left `(C-155,y,150,20)`, right `(C+5,y,150,20)` unless exact reference overrides.
- `ROW1(y)` means `(C-100,y,200,20)`.
- `LIST(top,bottom)` means a centered scroll view **from** `top` **to** `G_h-bottom`, not a fixed number of visible rows.
- `REF` means a location/size to be measured from the installed 26.3 client and recorded in the manifest; **never silently replace with made-up pixel values**.
- All coordinates are in logical GUI units, **not screen physical pixels**. They are recomputed on resize; a centered panel remains centered at any aspect.

## 2.6 Critical geometry/hitbox assertions

For all visible interactive rectangles `R_i`: `R_i.width > 0`, `R_i.height > 0`; the entire actionable area is on-screen or reachable by scrolling; each row's labels fit or wrap/truncate with tooltip; active controls do not overlap unless intentionally layered; popup and tooltip remain inside drawable bounds; focus is visible; the pointer hitbox coincides with visual rect after transforms; no button extends beyond screen safe bounds in compact mode; font baselines do not shift after resize; square icons remain square (`abs(width-height) <= tolerance`). Include automated assertions for these conditions for every screen at the resolution matrix in §23.

---

# 3. VISUAL SOURCE OF TRUTH: EXACT MINECRAFT JAVA, NOT A GENERIC SKIN

## 3.1 Required asset extraction and naming

- GUI sprite source directories: `assets/minecraft/textures/gui/sprites/**`, larger GUI sheets under `assets/minecraft/textures/gui/**`, title/panorama assets under GUI/title directories, associated `.png.mcmeta`; locate actual paths from JAR instead of assuming every texture lives in one atlas or every sheet has the same historical path.
- **Respect GUI sprite metadata**: `stretch`, `tile`, and `nine_slice` policies, border thicknesses, per-sprite canvas dimensions, animation metadata. Render **pixel-nearest**, correctly tiled edges rather than stretching 1px corners across wide buttons. Use a Godot `NinePatchRect` or custom mesh for nine-slice; a custom widget is acceptable when MC's tiling differs from native Godot.
- Fonts: import legitimate local glyph providers and font metadata, Unicode glyph fallback, bold/italic/obfuscated/underline/strikethrough formatting, pixel shadow, alternate fonts, bidi/RTL formatting and glyph coverage. Do not simply replace with Godot's standard UI font. If exact local glyph rendering cannot be reproduced, expose it as a logged visual deviation and use a readable fallback.
- Language strings: `lang/<locale>.json`, preserve translation keys as keys in UI code. Never hardcode English into underlying widget definitions. Respect new 26.3 keys/labels; older screenshots cannot override new text.
- Title-screen panorama is **26.3 Dappled Forest / Abandoned Camp**. Render a properly covering blurred/tinted rotating panorama using local installed assets; logo and splash are anchored over it. Cropping to aspect is allowed; letterboxing/stretching is not.
- Item icons, armor slots, recipe book, toasts, health/status icons, crosshair, chat icons, advancements, music toasts and inventory panels must reuse locally imported assets from their correct 26.3 locations or model-based renders.
- All icon states: idle, hovered/focused, pressed, selected, disabled, unavailable, attention/new, animated or progress; do not fake hover by just tinting a disabled asset.
- Keep project legal: import to `user://...` only on user's system, hash/cache locally, never commit or redistribute extracted proprietary UI sprites/fonts/audio; support private active resource pack selection, with vanilla base below it.

## 3.2 Universal visual language

| Element | Vanilla-style target | Failure to avoid |
|---|---|---|
| Text | Blocky local game font; visual 1px shadow; correct truncation and line wrap | Smooth rounded 14pt generic OS font |
| Buttons | Pixel-edged grey Minecraft widgets; state-specific sprites | Blue rounded Godot buttons / gradients |
| Inputs | Dark inset fill, light stroke, pixel cursor and selection | Modern floating label text fields |
| Menus | In-game vignette/dim behind; full-screen appropriate menu background | Frosted glass / translucent acrylic cards |
| Panels | Imported container skins, slots and borders | Resized 176×166 screenshot that distorts slots |
| Lists | Dark scroll region, Minecraft entry selection & scrollbar | Native OS scrollbars |
| Tooltip | Dark nearly opaque Minecraft box with border and shadow | White tooltips with rounded corners |
| Inventory | 18 logical pixel slot pitch, 16 logical pixel item artwork | 32/48px modern grid |
| Icons | Sprite/model-based with pixel ratio preserved | Generic emoji/fontawesome replacements |
| Focus | Vanilla keyboard hover/highlight and optional focus affordance | Invisible keyboard focus |
| Loading | Exact style progress and percentage/status | Endless spinner with no real work |
| Transitions | Only actual vanilla fades/splash motions | Invented flashy screen animations |

## 3.3 Text handling cases

Support full-width localized labels, CJK/Arabic rendering, variable names/server MOTDs, tooltip 1–30 lines, color codes and click/hover text components, custom item names, book pages, sign text, chat signatures/status, scientific numbers, negative coordinates, right-to-left content, long paths, invalid format recovery. Text measurement must occur **before layout**, not after applying a `clip_contents` mask. For names: choose ellipsis only when original Java does; wrap where Java wraps; preserve full text in hover. Color formatting and obfuscation must not cause jitter in nearby controls. Screen reader text should be the semantic description, not OCR of a bitmap.

---
# 4. SCREEN ROUTER, SHARED MENU SHELLS AND GEOMETRY

## 4.1 Screen routing requirements

The UI is a stateful navigation graph, not dozens of unrelated popups. For each route define: unique ID, title/translation key, parent screen, entry parameters, data provider, pause behavior, cursor capture state, saved focus target, confirm/cancel behavior, background style, option persistence, scroll restore, and responsive modes. All screens support `open(id, payload)`, `back()`, `replace(id)`, and safe closure when the world disconnects. Dialogs stack above parent without rebuilding it. ESC should first close a popup, then a text edit, then an overlay, then the menu (unless the source UI specifically differs). Fatal errors should never land the user in an invisible UI stack.

**Core layers (ascending z order):** 3D game / title panorama → regular HUD → in-game dim overlay → modal inventory/menu backdrop → main screen controls → context menu/select dropdown → tooltip / carried item preview → toast / warning → focus indicator / narrator overlay. Dragged item preview is above slots but below tooltip if the exact vanilla order requires; verify screenshot. Screen transitions consume pointer events while switching. World load/unload operations are coordinated with real state, not time-based illusions.

## 4.2 Four reusable screen shells

| Shell | Composition | Geometry and use |
|---|---|---|
| `TitleBackgroundShell` | 26.3 panorama, large logo, splash, centered control stack, bottom corners | Title, start-of-game server/world menus, options with title panorama or textured dirt backdrop as observed |
| `MenuFormShell` | Header title, centered `ROW1/ROW2` button/input region, fixed Done/Back bottom | Options, video, controls, language, audio, accessibility, world creation submenus |
| `ScrollableListShell` | Title, optional filter bar, full-height list region, sticky actions footer | World selection, server list, resource packs, data packs, keybinds, statistics, credits |
| `GameOverlayShell` | Dimmed live game behind, centered control stack or container sprite | Pause menu, inventories, world options, death, chat, books and other interaction menus |

**Do not use a menu form for an inventory.** Inventories have exact slot geometry tied to clicked slots; form Containers are allowed only in surrounding panels.

## 4.3 Canonical single-column and two-column layouts

```text
Logical view width G_w, height G_h, center C=G_w/2.

SINGLE-ROW button n:
    x = C - 100
    y = y_start + n*24
    w=200, h=20

PAIRED-ROW buttons n:
    left  = (C-155, y_start+n*24, 150,20)
    right = (C+5,   y_start+n*24, 150,20)

TWO BUTTONS FITTING SINGLE-ROW WIDTH:
    left  = (C-100, y, 98,20)
    right = (C+2,   y, 98,20)

BOTTOM DONE:
    button (C-100, G_h-28, 200,20)

BOTTOM FULL PAIR:
    left  = (C-204, G_h-28, 200,20)
    right = (C+4,   G_h-28, 200,20)
    (only use where screenshot confirms 2×200 rather than paired 98×20)
```

**Measurement condition:** many Java menus use center-based widgets of these sizes, but precise row start, number of columns and footer widths **vary per screen/version**. See per-screen prescriptions; when marked `REF`, screenshot measurement decides. Do not blindly apply one template to every submenu.

## 4.4 Universal header/footer behavior

- Header title text: horizontally centered, pixel-aligned, no invented eyebrow text. For compact screens keep the title and back action visible; scroll content beneath it.
- Footer controls: anchored to actual logical `G_h`, not at 720p-relative y. If the normal bottom row conflicts with the list, shrink viewport before moving buttons; never allow an invisible `Done`.
- Information/error/help labels: preserve vanilla order and colors; measure text bounds. Show versions and copyright/license text at title bottom corners, not inside the 200px button column.
- Scrollbar: fixed logical width matching installed UI sprites; thumb size based on visible/content ratio; wheel, drag, keyboard and touch support; no accidental overscroll of a parent container when child consumes input.
- Tooltips: appear near hovered control with vanilla margin, clamped to window; if right side overflows, flip to left, then up; if long, max width is available width minus 8, wrap and scroll only when necessary.
- Modal confirmations: exactly two clear actions, genuine cancel state, no destructive default on Enter; source screenshot decides labels/spacing.
- Screen readers and keyboard focus must follow semantic reading order even when visual layout reflows.

---

# 5. FIRST BOOT, TITLE SCREEN AND GLOBAL MAIN MENU FAMILY

## 5.1 First-boot sequence: locally installed game assets

Route IDs: `boot.splash`, `boot.resource_scan`, `boot.source_selection`, `boot.import_progress`, `boot.import_error`, `boot.missing_assets`, `boot.cache_repair`, `boot.completed`.

**Mandatory behaviors and layout:**
- Boot splash: full-window dark/color field with correctly sized centered logo; no bars. Only show a percentage when genuine measurable import/initialize work exists.
- Asset source detection: `Title` centered `TC(300,20,16)`; below it one or more source cards, each with installation label, detected version, validated path, check/selection state. Primary action centered above bottom margin: `Import & Continue`. Secondary row: `Browse...`, `Retry Scan`, `Use Fallback`, `Exit`; arrange into at most 2 columns in classic mode and a vertical list in narrow mode. Explicitly explain that imported copyrighted files remain local.
- Import progress: actual files and bytes processed, currently indexed asset class, estimated remaining when measurable, cancel (safe atomic rollback), and detailed error output behind disclosure; keep 60fps UI even when import is asynchronous.
- No source: explain how to install a legitimate Java Edition through official launcher or select folder; **never fake successful import or download copyrighted assets from unapproved mirrors**.
- Completed: transition to title automatically or with Continue if narration is active. In subsequent boots, cached version/hash validation happens without interrupting title unless input changed.
- Source cards must preserve long paths via ellipsis/tooltip and remain usable at minimum sizes. Private filesystem paths never leak into logs shipped to external services.

## 5.2 Main title screen — `title.main`

This is the most visible scene and **must be screenshot-verified before other screens are polished**. Java 26.3 officially uses Dappled Forest/Abandoned Camp panorama.

**Classic-mode coordinate target** (logical GUI coordinates, refine with 26.3 reference capture):

| Element | Position / dimensions | Visual and behavior |
|---|---|---|
| Panorama | `(0,0,G_w,G_h)` full client | Slowly rotating 26.3 panorama, cover-crop, source tint/vignette; never stretch x/y |
| Minecraft title logo | centered; bounding width **measured from locally imported logo source and screenshot**; approximately upper quarter | Preserve source aspect; same top offset/animation as vanilla |
| Yellow splash phrase | rotated/angled near right of logo (REF) | Imported text, randomized deterministic seed/animation; no arbitrary different font |
| Singleplayer | `ROW1(y0)` | `y0 = G_h/4 + 48` **classic fallback**, screenshot verify |
| Multiplayer | `ROW1(y0+24)` | Opens server browser/warning as applicable |
| Minecraft Realms | `ROW1(y0+48)` | 26.3 Realms icon/notification state from installed sprite |
| Quick icon row | centered near `y0+72` (REF) | Language, accessibility, social/friends or other actual 26.3 buttons; discover actual order/size |
| Options / Quit Game | two 98px buttons at `y0+96` (fallback; REF) | Options left, Quit Game right; adapt 26.3 screenshots |
| Version/build | bottom-left, about 2px edge margin | Actual app version and Java asset compatibility; don't misrepresent clone as official Minecraft |
| Copyright/company info | bottom-right, about 2px margin | Accurately distinguish original Minecraft trademark/copyright credits from clone authorship |
| Mod/resource notices | lower corner region if applicable | Only genuine current state, no fabricated vanilla status |

**Screenshot verification targets:** 320×240 GUI scale 1; 1280×720 Auto; 1920×1080 scale 2/3/4; ultrawide and portrait. Pixel compare logo bounding rect, buttons' centers, splash angle, version alignment, hover sprites. For extreme short height, title logo shrinks uniformly and menu becomes scrollable; retain access to Quit/Options.

**Interaction:** Mouse hover, keyboard navigation, enter/space, ESC from submenus, active selection highlight, Minecraft click sound, language and accessibility icons with accurate tooltips. Quit confirms only if source does; otherwise exit normally. If game is loaded behind title (after save), ensure it is unloaded cleanly.

## 5.3 Main menu-adjacent views

- `title.language`: list of available installed languages, search only if 26.3 includes it; language names in native scripts, centered list, select/Done, narrator and font changes in place. Prevent locale switch from resetting world or UI scale.
- `title.accessibility`: same detailed accessibility screen as in Options; accessible before boot world.
- `title.friends`: 26.3 Friends List presentation if feature reachable from title; filter, search, incoming requests and player actions depend on actual account/network; no simulation of public social services. Graceful unavailable prompt if not connected.
- `title.credits` / links: only routes genuinely offered by 26.3 main screen; don't invent first-party marketplace or Java Edition Bedrock-style dressing room.

---

# 6. SINGLEPLAYER WORLD MANAGEMENT: ALL SCREENS AND EXACT RESPONSIBILITIES

## 6.1 Select World — `world.select`

**Classic layout:** title `TC(..., 16)`; optional world-search field near top occupying centered list width; list begins below search and ends above footer. Rows are **Minecraft-style entries**, not big card tiles. Each has a square world icon on the left (commonly 32×32 in GUI logical units, verify 26.3), world name first line, metadata underneath (date, modes/commands/version), compatibility warnings, hover action icons. Row height typically around 36 logical units; **measure reference**. Clicking row selects, double click loads. Keyboard arrows move, Enter opens, mouse wheel scrolls, scroll state preserved after Edit/Re-Create.

**Footer target:** first row `Play Selected World` and `Create New World`, second row `Edit`, `Delete`, `Re-Create`, `Back` (arrangement REF; adjust widths/spacing to exact screenshot). Disabled when no selection, except Create/Back. List must virtualize 10,000 saves and lazily decode thumbnails; no repeated parsing of world save files during scroll. Use save metadata and icon resources rather than launching worlds to produce list item previews.

**Variants:** no worlds (empty state); 1 world; duplicate names; incompatible version; experimental world; damaged/missing level.dat; old world upgrade/backup; hosted/dependent world; long name with Unicode and ampersands; large save. Preserve warning icons/colors, tooltips, backup confirmations.

## 6.2 Edit World — `world.edit`

- World name field; `Reset Icon` (if present in 26.3), `Open World Folder`, `Make Backup`, `Open Backups Folder`, `Optimize World`, `Export World Generation Settings` or data pack/recreate options **only where vanilla reference presents them**; discover exact set from version. Do not show buttons from Bedrock's Edit World screen.
- Standard `MenuFormShell` center-aligned two-column controls; selected world name and info at top; bottom Done/Cancel. Text changes apply only after confirm. Path/open-folder actions use supported OS APIs with existence checks.
- Show irreversible and backup warnings before disk changes. If restoring backup, ensure world not open and preserve original until verified.

## 6.3 Delete World — `world.delete_confirm`

Centered warning title and explanatory text; world name emphasized; confirm and cancel buttons at bottom of centered modal. Never make destructive option keyboard default; use vanilla labels/hover appearance. If confirmation fails, remain in dialog and report reason. Screen remains responsive while filesystem delete work runs.

## 6.4 Re-Create / Clone World — `world.recreate`

Reuse creation flow prefilled from selected world's seed/settings; **no direct world overwrite**. Re-create creates new unique folder after conflict resolution. Preserve compatible generator selection and world rules. Show version mismatch where 1.18.2 generation is being used in modern 26.3 game content. For a copied world, don't imply identical built structures unless copied save data supports it.

## 6.5 World select warning and maintenance views

`world.backup_confirm`, `world.backup_progress`, `world.upgrade_confirm`, `world.upgrade_progress`, `world.optimize`, `world.optimize_progress`, `world.corrupt`, `world.restore_backup`, `world.copy_error`, `world.delete_error`, `world.unsupported_version`, `world.experimental_warning`, `world.datapack_load_failed`, `world.safe_mode`, `world.resource_reload`, `world.join_progress`. Each has a true progress state / confirm-cancel semantics. Use centered Minecraft dialog and bottom buttons; a message is not a substitute for an underlying operation.

---

# 7. CREATE WORLD: GAME / WORLD / MORE — EVERY FIELD AND SUBMENU

## 7.1 Shared Create New World shell — `world.create`

Minecraft Java uses **three header tabs**: `Game`, `World`, `More`. At normal widths, tabs span or fit the main centered content area as measured; selected state is an actual tab sprite/state, not a modern pill. The title `Create New World` is in the upper title region. A scrollable central form region starts under tabs. At bottom, `Create New World` and `Cancel` (centered paired buttons; exact widths measured) remain reachable during scrolling. **Changing tabs preserves unsaved values.** All fields must be bound to one validated world-creation model and must not reset each other when swapping tabs.

Typical classic fallback grid:

```text
Header title: centered, y about 10–20 (REF)
Tabs: row across top; tab band near y=0–32 (REF)
Content max width: 310 logical px in classic mode, centered
Wide form control: x = C-155, w=310 or inner single 200; reference decides
Primary action footer: bottom x=C-204/w200 and x=C+4/w200 only where it fits
When footer paired controls exceed G_w: use compact 98px pair or stacked layout
```

### Game tab (`world.create.game`)

| Field | Required semantics | Position relative to form |
|---|---|---|
| World Name | Text field defaults to `New World`; sanitize filename without changing visible name improperly; show chosen save folder if needed | Top label + full-width inset text field |
| Game Mode | Cycle **Survival → Hardcore → Creative** (only those available here, not Adventure/Spectator as selectable creation modes unless installed vanilla says otherwise) | Single wide button, 20 high, after name |
| Difficulty | Peaceful / Easy / Normal / Hard; constrain for Hardcore | Next 20px button separated by 4–12 |
| Allow Commands | On/Off; rules for Creative/Hardcore and cheats | Next button, adjacent tooltip |
| Info/help | Short descriptions and optional tooltip associated with each control | Under text or hover; do not consume unrelated space |

### World tab (`world.create.world`)

| Field | Required semantics | Layout |
|---|---|---|
| World Type | Default, Superflat, Large Biomes, Amplified, Single Biome; Debug Mode only through vanilla-specific modifier sequence | Wide selector or two-column selector + Customize |
| Customize | Enabled for Superflat/Single Biome; opens the correct child screen | Alongside world-type selector if vanilla does |
| Seed | Blank=random, accepts signed numbers and arbitrary text hashed using vanilla rules | Label + full-width inset text entry |
| Generate Structures | On/Off | Single wide toggle button |
| Bonus Chest | On/Off, disabled in invalid modes | Single wide toggle button |
| Generator compatibility | Modern vs dedicated 1.18.2 mode if the game exposes it; clearly **clone-specific** | Place in a clearly separated optional 'Advanced compatibility' section, not masquerading as vanilla |

### More tab (`world.create.more`)

Centered stacked launch buttons for `Game Rules`, `Experiments`, and `Data Packs`, with the current selected statuses. If a button's underlying functionality is not implemented, do not claim creation is feature complete; show explicit incomplete status in parity tracker, not an inactive visually normal button.

## 7.2 Customize Superflat — `world.superflat_customize`

- Current layers ordered from top to bottom with the correct block icon/name and layer height; surface at top. Layer selection highlight and scrollbar; ability to select/remove layer, add/edit allowed layers, choose preset.
- Buttons `Presets`, `Remove Layer`, `Done`, `Cancel` (and any actual 26.3 additions). Exact positions match reference. Preset selection preserves edits until explicitly accepted; cancellation restores the original.
- Each 18px block icon remains crisp; selected row must not cover label. Scroll large 1–100 layer recipes without clipping. Validate total thickness and block IDs in editor, not only on world launch.

## 7.3 Superflat Presets — `world.superflat_presets`

- Preset list and icons; editable superflat preset string if present; copy/paste; `Use Preset`, `Cancel`. Include actual vanilla preset definitions, e.g. Classic Flat, Tunnelers' Dream, Water World, Overworld, Snowy Kingdom, Bottomless Pit, Desert, Redstone Ready, The Void, only where 26.3 reference confirms each.
- List starts below title; edit field is lower/upper according to vanilla screen measurement. Keyboard arrows/selection and scroll. Present clear validation for invalid block string; do not crash if user enters huge input.

## 7.4 Single Biome selector — `world.single_biome`

- Scrollable vanilla-style biome list, searchable if actual 26.3 provides it; selected item highlight; every biome from versioned registry including 26.3 Dappled Forest where supported; do not invent missing biome strings. Select/Done/Cancel; preserve selection across resize and locale changes.
- World configuration must use valid version-specific worldgen settings, not just tint all grass to chosen biome.

## 7.5 Game Rules — `world.gamerules_create`, `world.gamerules_runtime`

- Scrollable, searchable categorized list generated from **actual 26.3 game rules registry**. Categories are headings with readable narrator focus; boolean rules use toggles and numerical rules use validated fields. Search filters by translated name/description and ID, does not mutate values. Tooltip/description below or on hover as per source.
- Runtime rules may have permission/read-only states; world creation allows editing even with commands disabled. 26.3 explicitly supports focusable category headings for narration. Show disabled state and reason for missing permissions.
- Footer Done/Cancel, Restore Defaults if present in source. No invented rule names/count. Preserve scroll while toggling. Compare exact strings with installed translations.

## 7.6 Experiments — `world.experiments`

- Version-specific experiments registry (not assumed nonempty in 26.3 stable). Toggle each available experimental data pack with description/compatibility warnings. Confirm changes and warning; if experimental toggles absent in stable, show the reference state rather than inventing a list.
- Warning screen when enabling experiments that affect world stability; allow user to cancel without losing other creation settings.

## 7.7 Data Packs — `world.datapacks`

- Resource/data pack selector model: two scrollable lists `Available` and `Selected` (or precise 26.3 tabs), pack icons, name, version/compatibility, description, visual ordering, move arrows, drag/reorder, open folder, search field (present in modern Java 1.21.11+), Done/Cancel.
- At narrow widths switch lists to stacked panels or tab toggle; **retain actual ordering semantics**, validation and selection when changing layout. This is a *responsive extension*; in classic mode screenshot-match source.
- Pack enable/disable can require reload; show real progress. Core vanilla pack cannot be removed improperly. Warn and handle invalid pack or dependency.

## 7.8 Create world progress — `world.create_progress`

Show generating/preparing/loading progress with actual stage, percentage only if measured, responsive background, cancel only if operation safely supports it. Display world creation errors via a recoverable Java-like dialog. When ready, transition into world and set correct HUD/mouse state. Do not use timer-based fake progress.

---

# 8. PAUSE / IN-GAME MENU AND 26.3 WORLD OPTIONS

## 8.1 Game Menu (Esc) — `game.pause`

The world stops for local singleplayer when source semantics permit; it does not arbitrarily freeze a multiplayer server or LAN clients. Background is the current 3D view dimmed according to vanilla (no Gaussian blur unless exact source UI uses it). Title `Game Menu` near top. Buttons align to center with standard 200px width for full rows, 98px width for pairs. **Verify the exact 26.3 button order**:

- `Back to Game` top single-row button.
- `Advancements` and `Statistics` side-by-side in one 200px row.
- `Give Feedback` and `Report Bugs` may be paired external-link actions (actual location based on reference).
- `Options...` and `World Options...` in their reference positions. **26.3 moved World Options to the location previously occupied by Open to LAN. Do NOT put a separate old Open to LAN on pause screen.**
- `Friends List`, `Social Interactions`, `Server Links...` shown only when valid in current context/26.3 installed reference.
- `Save and Quit to Title` / `Disconnect` last full-width action, with actual save and network cleanup.

**Classic fallback:** centered button stack starting around `G_h/4 + 8`; each full row 20px high, 4px gap; pairs form a 200px-wide group. Real source may have mixed vertical spacing. At very short heights, use a scrollable control column with sticky `Back to Game` and `Save & Quit` actions; default pause state must never trap player.

## 8.2 World Options — `game.world_options`

**Critical 26.3-specific UI.** This is the current-world settings screen, reachable from Pause. Two category tabs/sections: **General** and **Multiplayer** (actual visual implementation measured from installed 26.3 client).

**General fields (all):**

1. `Default Game Mode` — options & permission constraints, changes world's default mode.
2. `Personal Game Mode` — current player's active mode; read-only when not authorized.
3. `Allow Commands` — affects authority; don't fake security state.
4. `Difficulty` — Peaceful/Easy/Normal/Hard; in Hardcore enforce lock.
5. `Edit Game Rules` — opens categorized rules editor; permission-dependent.
6. `Restrictions` — opens screen explaining what cannot be changed; `Lock World` or related confirmation where 26.3 offers it.

**Multiplayer fields (all):**

1. `LAN` — real scope state/on-off; enables network serving only if supported.
2. `Port` — valid TCP port validation; disabled until relevant state.
3. `Command Access` — permission model for joiners.
4. `Force Game Mode` — enforce or not default mode for connecting players.

Do not copy older 1.21 world options or display old separate Open to LAN screen as though it were still primary. **The Online Options button remains in the main Options menu**, regardless of whether multiplayer is currently active, as specified by the 26.3 release notes. Use layout of left/right paired controls or vertical categories exactly as observed; start with labeled centered rows and a bottom Done. If screen's available height is less than content height, scroll middle content while pinning sections' selector and Done. All controls need correct active/disabled states and tooltips.

## 8.3 Restrictions / Lock World — `game.restrictions`, `game.lock_world`

- Show permissions and world constraints in readable panel; use translated exact 26.3 strings.
- If lock is available, use a confirmation showing irreversibility/ownership; valid only when permitted. Highlight permanently disabled controls; don't silently toggle them.
- Hardcore locks difficulty/mode as vanilla requires; no impossible toggle back to Survival.

## 8.4 Multiplayer scope / LAN detail — `game.lan` (legacy-only if present)

Treat legacy `Open to LAN` screen as a compatibility or direct transition route only if discoverable in 26.3, **not a pause-menu replacement**. World Options Multiplayer handles 26.3 settings. If a separate dialog is shown by 26.3 for LAN confirmation, implement that dialog with ports/permissions and robust validation. For a clone without a network service, a purely decorative toggle **is not implemented**; keep status truthful.

---

# 9. COMPLETE OPTIONS / SETTINGS NAVIGATION

## 9.1 Root Options — `options.main`

Classic `MenuFormShell`, medium width centered. Fields should be data-driven from actual `options.txt`/translations; UI includes sliders along with child-screen launch buttons. Confirm actual rows with 26.3 screenshot. At minimum routes:

- FOV (slider) with numeric/current label and instantaneous camera preview where appropriate.
- Online Options (always present in 26.3).
- Skin Customization.
- Music & Sounds.
- Video Settings.
- Controls.
- Language.
- Chat Settings.
- Resource Packs.
- Accessibility Settings.
- Telemetry Data / data collection information where vanilla 26.3 provides it.
- Done/Back.

**Do not assume all appear simultaneously or in a specific row order from an old Minecraft screenshot.** Generate screen inventory and measure exact row layout. Every slider button has mouse wheel/drag/keyboard behavior and a formatted display label. Settings persist safely to local profile, apply live where feasible and restore correctly after restart. Entering Options from title versus pause must route Done back to the correct parent.

## 9.2 Video Settings — `options.video`

In modern Java these controls are organized into categories including **Display**, **Quality & Performance**, **Preferences** (the earlier Interface section was renamed Preferences). Render category separators/headings with exact indent and vertical spacing; long list scrolls. Include every current setting actually supported by 26.3/available hardware; model follows option registry rather than static count.

**Display:**
- GUI Scale (`Auto`, 1–max; Ctrl + mouse-wheel adjustment in video settings if matching Java behavior).
- Fullscreen / Borderless Fullscreen default, Exclusive Fullscreen Mode where platform supports; runtime switch without restart per 26.3.
- VSync, frame-rate limit, refresh behavior/monitor when exposed.
- Brightness, field-of-view-related display settings if located in corresponding root/child screen.
- Graphics API selection (Java 26.2 introduced OpenGL/Vulkan selection; Godot renderer choices must be described truthfully and may require restart). Never claim Godot's renderer is Minecraft's actual graphics backend.
- macOS-only Menu/Dock Visibility, if appropriate and implementable.

**Quality & Performance:**
- Graphics Preset: Fast, Fancy, Fabulous!, Custom (modern preset system rather than a single old graphics toggle).
- Render Distance, Simulation Distance, Biome Blend.
- Clouds, Cloud Distance when applicable, Weather effects, Leaves, Entity Shadows, Entity Distance.
- Particles, Mipmap Levels, Texture Filtering, Anisotropic Filtering.
- Ambient Occlusion/Smooth Lighting options as exposed, Vignette, transparency/cutout behavior, Chunk Fade, Prioritize Chunk Updates.
- Visual effects and performance-related individual toggles; correct show/hide by GPU backend or preset.

**Preferences:**
- GUI/HUD-affecting options such as screen effects, Music Toast, view bobbing, attack indicator, auto-save indicator or other actually present 26.3 items. Some options may belong in Accessibility rather than Video; record exact source placement and obey it.

**Critical 26.3 deltas:** no `Raw Input` in Mouse Settings; 26.3 introduced new transparency handling and F3+X shortcut, default borderless fullscreen, immediate fullscreen switching. **Do not introduce later 26.4-only settings**. A setting present in Minecraft but not technically available in Godot needs either a real equivalent implementation or an honest disabled entry, never a fake performance promise.

**Exact layout:** typical two-column settings buttons `ROW2(y)`, category heading lines; setting lists can be longer than view height, so a centrally constrained scroll panel with consistent row pitch is mandatory. Retain category heading and slider positions at 1920×1080 comparison. At 320×240, preserve focus and footer and allow scrolling without overlap. Buttons/labels must show numeric current values without truncating longer translated settings names, with tooltip when truncated.

## 9.3 Music & Sounds — `options.audio`

Every actual vanilla category and control to be represented and functional:
- Master Volume; Music; Jukebox/Note Blocks; Weather; Blocks; Hostile Creatures; Friendly Creatures; Players; Ambient/Environment; Voice/Speech (if present); UI; sound output device (if available); subtitles toggle; directional audio / output sound implementation states.
- Categories and preview playback follow 26.3 behavior. Percentage sliders display exact current percentage; muting sets 0%, keyboard adjusts discrete increments correctly. Updating Music volume affects existing playing stream; no duplicate soundtrack starts on opening/closing this menu.
- Subtitles have real directional arrows/compass hints including **26.3 change: point to the most recent sound in range**; do not overlay fixed arrows that ignore listener rotation.
- A UI sound is sent to its appropriate category. Main-menu click sounds should be controlled by valid mixing logic and Master Volume.
- Preserve any unique new 26.2/26.3 audio settings through registry import if present.

## 9.4 Controls — `options.controls`

- Entry buttons `Mouse Settings...`, `Key Binds...`.
- Hold/Toggle controls for Sneak, Sprint, Attack/Destroy, Use Item/Place Block as offered.
- Auto-Jump, sprint timing/window options, and **26.3 Quit Shortcuts** (on by default according to 26.3 release notes; not all sources agree on earlier snapshot default, so release wins).
- macOS `Right Click Emulation` conditional option.
- Tabs/category rows as per 26.3. The active key-binding UI uses **physical keys**, not localized character-based key code matching, to reproduce 26.3 input behavior.

### Key Binds — `options.keybinds`

- Scrollable grouped key list with action name left and **current bound key** right, `Reset` on changed rows (where applicable), title and `Reset Keys`/Done bottom controls.
- Categories include Movement, Gameplay, Inventory, Creative, Multiplayer, Miscellaneous, Spectator, Debug and all live registered actions. Generate from action registry so plugin/action additions don't disappear.
- On click, row enters listening state with visual prompt. Capture keyboard/mouse/wheel combos as exact 26.3 allows; Escape cancels/clears according to source behavior. Warn or color duplicate bindings. Reset single/all routes have correct confirmation and undo possibility.
- UI display must correctly represent physical key names on Windows and macOS. Modifier keys should not permanently latch after rebinding. Controls must remain navigable by keyboard when a key bind is currently being captured.

### Mouse Settings — `options.mouse`

- Mouse sensitivity, scroll sensitivity, invert Y, discrete scrolling, raw mouse mode **omitted** in 26.3, and relevant input options from 26.3 registry. Slider labels must reflect values precisely; honor different input devices, and avoid cursor warp while menu open.

## 9.5 Chat Settings — `options.chat`

Include the version-correct controls for: chat visibility (Shown/Commands Only/Hidden), colors, web links and link prompts, text opacity, chat text scale, chat width, chat height focused/unfocused, delay, line spacing, background opacity, narrator setting, reduced debug info / only where appropriate. Preserve current chat history/typing while applying changes. Show chat mock preview only if vanilla does; do not add random design adornments.

## 9.6 Accessibility — `options.accessibility`

Support: narrator/off and available modes, subtitles, accessibility text background opacity, high contrast resource pack toggle where installed, text-to-speech support status, keyboard navigation, screen effects intensity, damage tilt, FOV effect scaling, darkness pulsing, glint speed/strength, hide lightning flashes, contrast/color settings where vanilla 26.3 offers them, directional subtitles, screen reader labels, focus narration, language-font behavior. **Exact settings list must be derived from 26.3 reference**; some settings change between releases. Non-functional controls are not acceptable as complete.

Use two-column settings/scroll category layout in classic; single-column at narrow width. Screen reader should narrate menu title, focused control, selected option and tooltip; no endless repeat on resize. Ensure the very first asset-import flow is accessible, including when no Minecraft font is available.

## 9.7 Skin Customization — `options.skin`

- Toggle hat, jacket, sleeves, pants legs, cape display; left/right variants separately. Layout is a two-column grid of pixel buttons, with Done at bottom; show precise imported preview or avatar model if reference screen includes it.
- Changing a toggle affects live 3D player model and third-person view. No false promises of account-wide online skin changes if the system is offline.

## 9.8 Language — `options.language`

- Large centered scrollable language list, native names, select highlight and Done; optional Force Unicode Font toggle if exact version has it. The chosen locale applies to all screens and game text components. Preserve cursor/click target transforms when font metrics change.
- Render right-to-left language strings properly; UI reading order may differ but game-space anchors must remain stable, and inventory grid must preserve vanilla ordering if source does not mirror it.

## 9.9 Resource Packs — `options.resourcepacks`

- Two lists with icons, names, metadata; active pack ordering; search box as in modern Java, open pack folder action, choose/unchoose/move order, incompatible pack warnings, `Done`.
- Resource reload progress and failure-recovery UI; preserve current world and menus where safe. Asset changes can affect font and sprite sizes: recompute menu layout after reload without resetting user input.
- In compact mode convert dual lists to switchable tabs, with explicit arrows/order controls. In classic use 26.3 screenshot geometry.

## 9.10 Online Options — `options.online`

**Always reachable from Options in 26.3.** Controls include friend-list availability, in-game notifications, allow requests, presence/activity visibility, Xbox privacy settings external link and other current options. Disable online-only controls if logged out; never invent a connected profile. Category layout updated in 26.2; inspect 26.3 rather than older screenshot.

## 9.11 Telemetry / Privacy / Feedback / External links — `options.telemetry`

Where 26.3 shows Telemetry or privacy information, provide exact visible descriptive layout, scrolling text, opt-out/required data distinctions if applicable, accurate external links; the clone should collect **no telemetry by default** unless separately authorized. Do not impersonate Microsoft's data usage. If a vanilla external link is irrelevant to a clone, label it a reference/outbound link and do not falsely represent official account integration.

---
# 10. MULTIPLAYER: EVERY SERVER/FRIEND/CONNECTION MENU

## 10.1 Java Multiplayer screen — `network.multiplayer`

**Classic structure:** `ScrollableListShell` with centered title top, server rows occupying scroll body and a two-row footer. The server list is not a web-app table. Each row has a square server icon left, server name, MOTD lines, player count, signal/latency/status indicator on right, version/mismatch badge, hover/select border and up/down controls if vanilla shows them. Place LAN-discovered servers in proper list region with distinct style/status. Asynchronous server pings are throttled; do not freeze UI while refreshing dozens of entries.

Buttons/flows: `Join Server`, `Direct Connection`, `Add Server`, `Edit`, `Delete`, `Refresh`, `Cancel`/`Back`; order/sizes per actual 26.3 reference. Disable Join/Edit/Delete without a selection. Double-click or Enter selected server; scroll wheel and keyboard navigation. Represent unknown ping as unknown, not fake 0 ms. Render formatting codes for MOTDs safely; never execute text events from untrusted server descriptions without user action.

**Security/consent:** Java Edition online accounts and server authentication are not available simply because Minecraft assets were imported. The UI can reproduce menus; functional server join requires implementing the protocol/auth properly and permission. Do not claim general vanilla multiplayer parity before such implementation.

## 10.2 Multiplayer warning — `network.multiplayer_warning`

If vanilla presents a safety warning before multiplayer, use a warning text block and paired Proceed/Cancel; remember user choice only if version/reference says so. Longer translated disclaimer must scroll. Link to safety information only through explicit user click.

## 10.3 Add Server — `network.add_server`

Centered form: `Server Name` and `Server Address` labels + input fields; `Server Resource Packs` option (Prompt/Enabled/Disabled) where source has it; Done/Cancel bottom. Validate address as host, optional port, IPv6 bracket form, domain/IDN, whitespace, colon usage; error text without crash. Do not save password. Persist server icon/ping cache separately from user-entered address.

## 10.4 Edit Server — `network.edit_server`

Same geometry as Add Server prefilled, maintain selection, cancel reverts, Done saves and reorders only if reference behavior requires. Server list must retain scroll position on return.

## 10.5 Direct Connection — `network.direct_connect`

Single address field at center, `Join Server`, `Cancel` below; clipboard Paste usable; DNS/port errors shown in interface. Distinguish local direct IP from address saved to list.

## 10.6 Delete Server — `network.delete_server_confirm`

Title/warning and hostname, confirm/cancel, return to selected-row state. No silent destructive action. Persist only on confirm.

## 10.7 Joining / downloading packs / disconnect — connection screens

Route IDs: `network.resolving`, `network.connecting`, `network.authenticating`, `network.encrypting`, `network.login`, `network.configuration`, `network.pack_prompt`, `network.pack_download`, `network.pack_reload`, `network.joining_world`, `network.disconnected`, `network.kicked`, `network.failed`, `network.timeout`, `network.incompatible_protocol`, `network.banned`, `network.missing_mods`. Each has authentic explanatory text and error detail when known, a reachable Cancel/Back and no false success. Don't show a fake spinner forever. Progress indicators reflect actual network phase; `Disconnect` returns to exact previous screen (server list vs direct connect vs Realms).

## 10.8 Social Interactions — `network.social_interactions`

In multiplayer: player list with exact tab labels/controls from installed 26.3, user avatars/heads, search/filter, hide/show chat per player, report actions when real and appropriate, current player self state. No invented official moderation pipeline; if reporting cannot be submitted, label unavailable and explain. Game handles chat-hidden state properly, across new messages and disconnections.

## 10.9 Report Player — `network.report_player`

Multi-step report reason choice, offending message selection/context where legally/technically available, freeform description, evidence preview, confirmation/cancel and successful receipt only upon actual success; never fabricated. This is a fidelity target only if an authorized reporting backend actually exists. A clone running offline must not pretend to file reports with Mojang.

## 10.10 Server Links — `network.server_links`

If connected server advertises links, show a list with link titles/types and icons, explicit click opens through OS confirmation as vanilla does, link sanitization and no auto-open. Empty list has accurate state. Server-provided labels may be long and include formatting; safely render.

## 10.11 Player list overlay (Tab) — `hud.player_list`

Overlay top center spanning **only needed width** based on number of players and name lengths; Minecraft head icons, names, score/objectives, connection indicators and optional header/footer. Multiple columns at high player count, responsive scroll/condense at narrow width. It should not be an opaque full-screen dialog, should not steal gameplay mouse unless source does. Tab press/release behavior matches binding. Show selected scoreboard objective on right side, not overlapping the player list on narrow screens.

---

# 11. REALMS & FRIENDS — 26.3-SPECIFIC COMPLETE UI COVERAGE

**Important scope warning:** A visual clone of Realms interfaces does not constitute a Realms client. Actual Realms service/API, Microsoft identity, subscriptions and payments require authorized integration. Implement menus and non-network test paths fully; keep online operations clearly unavailable if backend is not present. Do not circumvent account systems. Treat official 26.3 assets/labels as layout references only.

## 11.1 Main Realms view — `realms.list`

- 26.3 Realms list of owned/member Realms, active/inactive status, icon, description, slots/player count, ping/region where visible. Screen header and available tabs from actual screenshot.
- `Play`, `Configure`, `Leave`, `Renew`, `Add Realm` actions conditionally visible; invitation indicators and a `Join Realm` route for invite codes (new in 26.3).
- List rows retain selections on reload. Network error/loading/offline/expired/trial states are distinct screens. The UI should never show a player subscribed when not authenticated.

## 11.2 Realms introduction — `realms.intro`

New 26.3 onboarding/introduction screen with feature presentation, trial information when valid, forward/back controls, optional promotional art from local 26.3 resources. Must work in narrow view without giant artwork obstructing primary actions. Do not invent real payment links or start a subscription automatically.

## 11.3 Join Realm by code — `realms.join_by_code`

Text field + validation, enter/confirm/cancel, expired/invalid/already-member/unauthorized states. 26.3 newly supports joining via invite codes. Never display accepted membership until backend confirms it.

## 11.4 Create/manage invite codes — `realms.invite_codes`

List up to **five invite codes per realm** per 26.3 notes, active/inactive status, expiration choices, copy/share controls, revoke/disable and confirmations. Only show real codes sourced from authorized service. Copy feedback accessible to narration, but do not display hidden/private token to external logs.

## 11.5 Configure Realm — `realms.configure`

- Tabs/sections as actual reference: World Slots, Players, Settings, Subscription, Backups, Minigames or related options. Source 26.3 has a tab-based configuration layout.
- World slot selection and activation, upload/replace slot, downloaded worlds, create/recreate world using regular world creation screen, resource packs, backups, region preference (Auto and available regions), **render distance and simulation distance sliders newly added in 26.3**.
- World slot thumbnails remain square and preserve scene crops. Distinguish active from selected.
- Player invitations, roles/permissions, remove/kick, blocked list, open/close realm, subscription info. Correct confirmation for irreversible actions.
- Cloud operation views: creating, downloading, uploading, backup restore, world switching, connection, failure; show genuine progress and retry.

## 11.6 Realms auxiliary screen registry

`realms.pending_invites`, `realms.invited_players`, `realms.player_permissions`, `realms.world_slots`, `realms.world_options`, `realms.world_backup_list`, `realms.backup_detail`, `realms.backup_restore_confirm`, `realms.download_world`, `realms.upload_world`, `realms.create_world`, `realms.recreate_world`, `realms.minigames`, `realms.subscription`, `realms.trial`, `realms.expired`, `realms.close_confirm`, `realms.open_confirm`, `realms.region`, `realms.resource_pack`, `realms.invite_player`, `realms.remove_player_confirm`, `realms.error`, `realms.loading`, `realms.news`, `realms.notifications`, `realms.join_by_code`, `realms.intro`, `realms.invite_codes`.

Each discovered 26.3 screen gets a manifest row and responsive layout. If impossible to implement without official backend, still reproduce the **locally testable visual state** but classify network operations as **blocked**, not complete.

---

# 12. IN-GAME HUD: EXACT EDGE ANCHORS AND EVERY OVERLAY

Minecraft's HUD is *not* a single centered canvas. Each section uses screen-center, bottom, top-left, top-right, edge-of-screen or player-view anchors. **When resizing, HUD elements retain the correct anchors and increase/decrease available empty space rather than stretching across the whole screen.**

## 12.1 HUD layers and ordering

1. 3D world rendered full viewport (no bars), independent dynamic resolution.
2. World overlays: portal/nausea/spying scope/pumpkin/carved helmet; underwater/mob status view transforms; dark vignette; powder-snow freeze border; world border damage; first-person hand/held item in 3D viewmodel space.
3. Crosshair centered in actual drawable viewport; source 16×16 sprite/model size or imported sprite dimensions, show/hide based on camera/game mode.
4. Bottom-centered hotbar + offhand icon + experience and status icons.
5. Chat, action bar, title/subtitle announcements, toasts, boss bars, scoreboard, status effects, tab list, narrator/subtitles.
6. Debug F3 overlays and hitbox/debug charts, with independently configurable scale.
7. Screen menus, inventory and tooltips in front of HUD.

## 12.2 Hotbar, inventory-held item, selected slot

**Classic vanilla geometry (logical GUI units, verify actual 26.3 sprite atlas):**

| Part | Geometry | Rule |
|---|---|---|
| Hotbar background | **182×22**, horizontally centered, bottom margin approximately **0** GUI px (sprite may include borders) | `x=C-91`, `y=G_h-22` |
| Nine item slot centers | `x=C-80+20*i`, `y=G_h-11`, `i=0..8` | Slot pitch **20** logical px in HUD (not 18 inventory grid) |
| Selected slot frame | commonly **24×24**, positioned over chosen slot, using imported sprite | x aligns selected slot; frame may protrude 1px beyond hotbar, screenshot verify |
| Offhand preview slot | left or right of hotbar according to primary-hand setting; size from local HUD sprite | Should not cover hotbar on short/narrow windows |
| Item icons | usually **16×16** nominal before transforms | Render 3D items as 3D icon when applicable, 2D sprite items as flat |
| Stack quantity | lower-right within its slot, source font + drop shadow | Show only if >1 or vanilla says so; don't clip long numbers |
| Durability bar | thin colored bottom-of-icon meter at reference position | Animated/colored by real durability; don't use percent text |
| Cooldown overlay | translucent wedge/rectangle over slot | Draw independent from item count and selection frame |
| Attack indicator | hotbar or crosshair position based on setting | Scale and timing follow combat state |
| Held item tooltip | centered above hotbar temporarily | E.g. item name, enchant color; don't overlap HP icons |

`hotbar y` remains bottom-anchored on ultrawide, portrait and during resize. In compact portrait widths < hotbar width, **uniformly reduce HUD component scale** until full hotbar fits; if below readable threshold offer a compact scrollable overlay but retain 9 slot access through wheel/number keys. Do not cut off slots 1 or 9.

## 12.3 Health, armor, hunger, air, absorption, mount health

Relative to centered hotbar, classic survival places hearts/armor in columns on left and hunger/air on right; XP bar between them above hotbar. Precise pixel location depends on current effects/rows; use the following **anchored design constraints**, then measure the exact offsets from official capture:

- Bottom vitals region spans about the hotbar's **182 logical px** width; heart row left 10 hearts, hunger row right 10 drumsticks, each icon **9×9** logical (verify actual source). Health rows can increase above base row when player max health exceeds 20; absorption hearts and blinking damage heal states add overlays/rows.
- Armor row above health on left if armor rating >0. Render half/full/empty states.
- Air/bubbles appear above hunger or in reference-defined slot when underwater. Fade after leaving water according to vanilla.
- Hunger/exhaustion states and low-hunger warning use correct sprites/animation; saturation is not normally shown unless debug settings.
- Mount/jump bar and mount health may replace/overlay XP/hunger regions according to ridden entity. Ensure horse jump charge bar isn't accidentally displayed while walking.
- Experience progress bar centered horizontally just above hotbar, typically **182px×5px** visible strip (source asset verify); level number centered over bar at proper baseline; only in eligible game modes.
- Creative/Spectator special HUD: Survival hearts/hunger disappear; Creative hotbar remains; Spectator hotbar/navigation behaves differently; Hardcore hearts have appropriate icon variant.
- Effects (Poison, Wither, Regeneration, Freeze, Weakness, Nausea, Absorption), hardcore face hearts, breath and armor animations must use correct local 26.3 sprite variant rather than recoloring the same icon.

**HUD collision manager:** determine bounding rectangles of left vitals, right vitals, chat, titles, boss bars, toasts, scoreboard, status effects, subtitles. In tiny screens, deprioritize debug/scoreboard before essential vitals; stack temporary subtitles above instead of on top of hotbar. Never hide essential inventory/crosshair due to a random toast.

## 12.4 Crosshair, targeting and block overlay

- Crosshair centered exactly `(P_w/2,P_h/2)` in physical UI coordinates and then drawn with correct uniform scaling. Does not shift for ultrawide.
- Targeted block selection outline is **3D world-space**, not a HUD rectangle; voxel face highlight and breaking damage cracks aligned to block coordinates. Don't let GUI scaling change block outline thickness incorrectly.
- Damage vignette, low-health effects, underwater overlay, portal texture and spyglass mask cover or appropriately crop full viewport; no fake 16:9 mask with black edges. Spyglass circle keeps a **true circle** (uniform radius), with surrounding dark mask filling other space.
- First-person hand/arm and item use animations maintain aspect and source scale as FOV/viewport changes. Debug hitboxes must align with real 3D entities.

## 12.5 Chat overlay — `hud.chat`, `hud.chat_input`

- Anchor **bottom-left**, just above the vitals/hotbar area, with vanilla margins and computed width/height based on player settings. Not fixed 1920px coordinates.
- Unfocused chat lines age/fade; focused/chat-open history scroll, scroll bar, click/hover components, input background, command suggestions, commands beginning `/`, history Up/Down, Tab completion, error/warning and multiline when appropriate.
- Open input with `T`; `/` prefills slash; keyboard focus moves from gameplay to chat. On Enter submit validated message/command, on Escape cancel, on mouse click handle clickable texts only after source policy. Cursor and chat text selection must respect imported pixel font.
- Negative X position? Never. On portrait, chat width clamps to available width minus margins; no line runs behind scoreboard. On short screens, chat height adapts and can scroll. Keep visible text readable and preserve message timestamps/state through resize.

## 12.6 Action bar, titles, subtitles, boss bars, objectives

- **Action bar:** horizontal center, usually above hotbar; time-based fade, formatting support, priority over low-priority tooltip.
- **Title / subtitle:** centered screen, large Minecraft font scale and stacked hierarchy; timing (fade-in, stay, fade-out) comes from game events; no aspect distortion.
- **Boss bar:** centered near top with correct width (commonly around 182 logical px), texture and fill; stack multiple bars with consistent vertical pitch. Large numbers of bars scroll/clamp in compact mode.
- **Scoreboard sidebar:** right edge aligned with safe padding and rows, automatic width based on measured text; no clipping or overlay over chat/center. Team/objective color formatting preserved.
- **Advancement toast:** top-right source sprite/card; item icon left, title and description, slide-in/out motion, queue successive events rather than overlapping them; track actual notification queue state.
- **Tutorial toasts:** top-right with progress when applicable; independent from achievements, stack properly.
- **Recipe unlocked toast:** top-right with item and true progress; avoid impossible recipes shown when unlocked registry empty.
- **Now Playing / Music Toast:** implement **26.3 current display behavior** and Music Toast preference (always/pause-only/off if present). Display actual track title/attribution from locally imported music and metadata; don't hardcode fake song names.
- **Direction subtitles:** bottom-right/right edge, source font, sound descriptor, direction arrows pointing to **latest** audible event; fade/timeouts and max visible rows. At small aspect, move above other right-edge overlays.
- **Status effects:** top-right, one icon per potion/status effect, blinking near expiry, separate from subtitles and toasts; accurate stacking order.
- **Player notifications:** lower center/edge based on reference, time fade and correct icon.

## 12.7 F3 debug and related views

- `hud.debug`: coordinate data, facing, FPS, frame time, biome, light, chunk, entity counts, server/local state, selected block/fluid, targeted block, memory, display refresh rate and **26.3 player speed (blocks/tick)**; only display measurements that are real.
- `hud.debug_pie`: profiler visual when enabled; overlays without destroying HUD alignment.
- `hud.debug_graph`: frame-time graphs and other charts, anchored to correct edges.
- `hud.debug_f6_options`: current Java 26.3 Debug Options, allows separate scale: `Auto`, `Unchanged`, explicit scales. New display settings affect debug layer only.
- `hud.debug_gamemode_switcher`: F3+F4 radial/linear selector as version reference, current icon for Adventure is **Buried Treasure Map** in 26.3. Cycling modes and commit logic require valid permissions. Don't implement fake mode switch outside game state.
- `hud.debug_f3x`: F3+X toggles Improved Transparency in reference version; in clone perform actual equivalent or disabled-with-reason with truthful status.
- Hitbox toggle, chunk border display, advanced tooltips, reload resources, chunk debugging, profiler toggles, freeze effects, debug clipboard shortcuts and key-combination help overlay must be represented if supported by 26.3. Debug should not accidentally consume normal text entry key combos.
- Debug overlay uses independent uniform scale and safe-edge placement; at 320×240 it can scroll/fold rather than cover the entire player view. `F1` HUD hide mode hides appropriate HUD/UI but doesn't corrupt screen state.

## 12.8 Special spectator/creative/gameplay overlays

`hud.spectator_hotbar`, `hud.spectator_menu`, `hud.spectator_teleport`, `hud.spectator_team`, `hud.creative_hotbar_saved`, `hud.raid_bar`, `hud.sleeping`, `hud.trading_xp`, `hud.mount_jump`, `hud.swim_air`, `hud.fishing_indicator`, `hud.map_held`, `hud.spyglass`, `hud.portal`, `hud.freeze`, `hud.powder_snow`, `hud.totem_animation`, `hud.damage`, `hud.hurt_vignette`, `hud.cinematic`, `hud.underwater`, `hud.camera_viewmodel`, `hud.leash_indicator`, `hud.crosshair_attack_indicator`, `hud.riding`. Each effect with unique input/visibility/animation is part of the UI inventory, not a placeholder list.

---

# 13. INVENTORY GEOMETRY: SLOT-PRECISE, PIXEL-PRECISE, FUNCTIONAL

## 13.1 Universal slot rules

**Every container uses the exact original source GUI PNG dimensions and immutable slot coordinates from its UI schema. Do NOT uniformly resize source inventory artwork to match the screen.** Instead, center the background and uniformly scale the **whole container** when required. Use the common `176×166` panel where applicable, and larger/smaller actual source sizes elsewhere. The slot coordinate system is local to upper-left of panel, `P(x,y,18,18)`. Item artwork typically 16×16 px inside slot with 1px inset. Hotbar slot pitch is 20px; inventory slot pitch is 18px—do not mix them.

Shared player backpack (typical 176×166 container):

```text
PANEL L=(G_w-176)/2, T=(G_h-166)/2
Player main inventory slots, rows r=0..2, cols c=0..8:
  slot top-left = (L+8 + 18*c, T+84 + 18*r)
Player hotbar inventory row, cols c=0..8:
  slot top-left = (L+8 + 18*c, T+142)

Each 18x18 slot is 1px border/inset + 16x16 item + 1px border/inset.
Hover selection outline and item icon must use same local transform and z order.
```

These values are common vanilla Java container coordinates; **verify 26.3 exact panel sprites and each screen**, as creative inventory, expanded containers and special screens differ. Use `docs/UI_PARITY.md` to distinguish confirmed vs provisional figures.

**Slot interactions (must actually work):** left/right click pickup/drop half, click swap, shift-click quick move, hotbar number key swap, offhand F swap, Q drop/CTRL+Q stack drop, creative pick-block middle click, drag distributing items evenly (left) / one each (right), double-click collect matching items, carried stack and count, recipe ghost items, item tooltips with rich text, locking invalid slot types, spectating restrictions, inventory sync, transaction rollback, container closure persistence. Slot quantity overlays draw over item icon at exact baseline; use resource pack-compatible fonts. Captured drag item follows cursor through resize/DPI changes with no offset jump.

## 13.2 Player Inventory / Crafting — `container.player`

**Panel:** common **176×166** PNG and center formula, if reference matches. **Required layout:**

| Region | Approx. panel-relative logical coordinates | Exact intended contents |
|---|---|---|
| Player avatar preview | x≈26–78, y≈8–79 | Live 3D model, draggable rotation, armor/skin layers; correct aspect |
| Armor: head/chest/legs/feet | x=8, y≈8,26,44,62 | Four armor-only slots and actual slot icon overlays |
| Crafting 2×2 | x≈98 and 116, y≈18 and 36 | Four ingredient slots |
| Craft result | x≈154, y≈28 | One output slot; recipe dependency and result preview |
| Offhand | x≈77,y≈62 | Genuine shield/torch/offhand icon slot |
| Main 27 | x=8+18c, y=84+18r | Player backpack |
| Hotbar 9 | x=8+18c, y=142 | Inventory hotbar row |
| Recipe book tab | protruding left of panel, REF | Toggles recipe book; panel may shift horizontally in wide screens |
| Item hover tooltip | cursor-relative, screen-clamped | Full item name/lore/enchantments/stats/NBT flags if eligible |

Recipe-book side panel may shift main panel laterally in classic mode; exact changed coordinates measured by screenshot, not guessed. At narrow width, recipe book opens a **tab/overlay** in the same usable window (responsive extension) instead of going offscreen. Escape first closes recipe book if vanilla does.

## 13.3 Crafting Table — `container.crafting`

**Background:** common 176×166; output arrow belongs to imported sprite. Main 27 + hotbar positions same common panel. Craft input **3×3**, approximate starts `x=30,y=17`, pitch 18; output `x≈124,y≈35`. Render recipe output as computed from actual ingredients. Recipe-book button near left; match vanilla panel shift and input grid. Crafting sound, item consumption, achievements and invalid placement states must connect to real gameplay.

## 13.4 Chest and containers — `container.chest_1..6`, `container.chest_double`

- Single chest (3 rows) often uses `176×166`, internal chest slots `x=8+18c,y=18+18r` for r=0..2. Player inventory `x=8+18c,y=84+18r`, hotbar `y=142`.
- Double chest (6 rows) often uses `176×222`; chest slots `x=8+18c, y=18+18r`, r=0..5; player inventory x=8+18c, y≈140+18r, hotbar y≈198. Verify actual source geometry.
- Generic chest-like container with N rows derives panel height and player inventory offset from N; panel centered, not cropped. Label displays correct custom name; long names truncate according to vanilla rules.
- Ender Chest is chest UI with its own inventory and localized label; trapped chest same visual grid but game side effect differs. Shulker Box is 27 slots with own label and interaction restrictions. Barrels use correct grid and sound but similar UI.
- Hopper GUI commonly **176×133** with one row of 5 slots, player inventory shifted relative to shorter panel. Verify slot coordinates from 26.3 sprite; do not substitute chest texture.
- Dropper/Dispenser commonly 3×3 storage grids (9 slots); title distinguishes item behavior, GUI slots must map correctly.
- Crafter block has 3×3 grid with toggleable disabled slots, redstone preview/result and correct crafting indicator; any introduced post-1.21 textures must be imported rather than approximated.
- Bundle item uses tooltip/hover contents and compact contents view; visual uses inventory overlay rather than full-screen menu; any newer 26.3 bundle behavior must be version-checked.

## 13.5 Creative Inventory — `container.creative`

- Different panel/sprites from standard player inventory, multiple creative category tabs along top/sides; every Java 26.3 tab must be present and correctly ordered. Use version registry for all item contents. Common categories: Building Blocks, Colored Blocks, Natural Blocks, Functional Blocks, Redstone Blocks, Tools & Utilities, Combat, Food & Drinks, Ingredients, Spawn Eggs, Operator Utilities when permitted, Saved Hotbars, Search, Inventory; verify exact tab ordering/icons from 26.3.
- Search field in Search tab and live filtering across item registry. Scrollbar position, result grid, selected tab protruding edge geometry and background texture must match current assets. Tabs with hover tooltip, click action, active state and page navigation.
- Saved Hotbars have numbered saved/load presets with keyboard shortcuts where vanilla supports them; not just a disabled tab.
- Creative item cursor left-click stack, right-click one, middle pick, drag quick placement behavior. Item group ordering must reflect **26.3 changed mineral order and Natural Blocks Overworld→Nether→End progression**.
- Operator items appear only with permission option; don't leak items hidden by source rules.
- Responsive: the pane remains centered; if tabs no longer fit horizontally they can paginate or use secondary category selector. **Never shrink 16px items into illegible 4px icons** just to preserve original number of columns.

## 13.6 Container screen geometry data contract

Use one schema per workstation, not hundreds of hand-coded absolute UI positions:

```yaml
screen_id: container.crafting
reference_version: java_26.3
background_sprite: minecraft:gui/container/crafting_table
background_px: [176, 166]          # must be verified against installed file
centered: true
slots:
  crafting_input:
    shape: grid
    origin_gui: [30, 17]           # verify against exact 26.3 sprite
    columns: 3
    rows: 3
    pitch_gui: [18, 18]
  crafting_result:
    shape: single
    origin_gui: [124, 35]          # verify against exact 26.3 sprite
  player_main:
    shape: grid
    origin_gui: [8, 84]
    columns: 9
    rows: 3
    pitch_gui: [18, 18]
  player_hotbar:
    shape: grid
    origin_gui: [8, 142]
    columns: 9
    rows: 1
    pitch_gui: [18, 18]
responsive:
  classic: centered_at_intrinsic_size
  narrow: uniformly_fit_or_scroll_with_recipe_book_overlay
  short: hold_footer_and_scroll_large_auxiliary_panes
```

Generated runtime schema should be JSON or Godot resources as project prefers. The YAML above is conceptual. **Never assume the source sprite ID shown is an actual direct image path**; resolve through asset index/GUI registry.

---

# 14. EVERY CRAFTING/WORKSTATION/VILLAGER INVENTORY SCREEN

For each listed workstation, implement background sprite, dimensions, all individual slot coordinates, player inventory slots where present, active progress bars and icons, audio feedback, tooltip, keyboard flow, unique button behavior, state changes and resizing. **Do not claim complete for just drawing an imported PNG.** Layout uses `P(x,y,...)` anchored from *actual* screen panel; fill in unverified locations from local 26.3 screenshot and sprite geometry before visual signoff.

| Screen ID | Required unique panel elements | Layout contract (relative to centered native sprite) |
|---|---|---|
| `container.furnace` | Input, fuel, output; burning flame, smelt arrow progress, recipe book | Native 176×166-style furnace panel; input approx `(56,17)`, fuel `(56,53)`, output `(116,35)`, flame/arrow between; REF exact |
| `container.blast_furnace` | Faster cook speed; same inventory pattern with distinct title | Use furnace-type inherited slot schema, own recipe set/sounds |
| `container.smoker` | Food cooking progress | Furnace variant, distinct title/icons/sounds |
| `container.brewing_stand` | Reagent, blaze-powder fuel, three bottle slots; brew timer and fuel meter | Native brewing sprite 176×166 family; reagent approx `(79,17)`, bottles ~`(56,51),(79,58),(102,51)`, fuel at left; REF exact |
| `container.enchanting` | Item/lapis slots, animated book, 3 enchantment offers, rune text, XP/lapis costs | Source custom panel & Enchanting Standard Galactic text; book animation isn't static image; proper selection highlight and disabled cost |
| `container.anvil` | Input 1, input 2, output, rename textbox, XP cost line, red error color | Native anvil panel; slots around `(27,47)`,`(76,47)`,`(134,47)` REF exact; rename field above |
| `container.grindstone` | Two input slots, one output, XP indicator (if UI has it) | Custom grindstone skin/slot geometry from asset; no anvil rename field |
| `container.smithing_table` | Template, base, addition, result; upgrade diagram; tooltip for missing pattern | Four relevant slots, clear schema; netherite upgrade and armor trims with 3D previews as vanilla |
| `container.stonecutter` | One input slot; recipe grid scroll/list; output slot; selected recipe highlight | Compact output recipe array with scrollbar; dynamic recipe count, not fake fixed rows |
| `container.loom` | Banner, dye, optional pattern, pattern choices, output/banner preview | Pattern scrollable grid, banner texture preview with colors, ingredient-specific validation |
| `container.cartography_table` | Two inputs (map plus paper/map/glass), output, output map preview | Native cartography panel; 26.3 Explorer Maps' extendable-map rules reflected in enabled buttons/output |
| `container.lectern` | Book page spread, next/previous arrows, page number, Done | May be book-reading GUI instead of slot grid; book texture native |
| `container.merchant` | Trade list left, current trade details, two payment slots, result, villager level/XP bar, arrows | Wide trading panel, *not* a 176px crafting table; scrolling trades, selected row and discounts, locked/out-of-stock states |
| `container.horse` | Horse equipment (saddle/armor), horse preview, player slots | Own width/height, horse model preview; show equipment slots as valid for horse type |
| `container.donkey` | Saddle + storage rows when chested, animal preview | Correct inventory row count tied to entity state |
| `container.mule` | Similar to donkey but variant equipment availability | Distinguish entity, no impossible armor slot |
| `container.llama` | Decor/carpet slot and size-dependent storage rows, model preview | Source layout for 3/6/9/12/15 storage slots |
| `container.chest_boat` | Boat inventory storage, title, item behavior | Chest-like 27 slots if vanilla, verify source |
| `container.chest_minecart` | Storage slots, title | Chest-like layout and live inventory |
| `container.hopper_minecart` | Hopper slots | Hopper-like layout |
| `container.beacon` | Beacon power choices, secondary power option, payment slot, confirmation and powered states | Custom panel width/height; selected effect icons, disabled effect eligibility, level gating |
| `container.crafter` | Disabled slot states, 3×3 ingredients, output preview | Per-slot disable interactions and indicator |
| `container.trial_vault` | If interaction opens a distinct UI in 26.3, implement exact state; if direct world-use, DO NOT invent a menu | Verify from Java 26.3 behavior |
| `container.hopper` | 5 slots, correctly shifted player inventory | Native shorter skin, not crop of chest |
| `container.dispenser` | 3×3, player inventory | Native dispenser skin |
| `container.dropper` | 3×3, player inventory | Native dispenser/dropper family skin |
| `container.shulker_box` | 27 storage slots, item restrictions, custom name | Native shulker-style 3-row container |
| `container.ender_chest` | 27 personal storage, ender chest title | Chest-family background |
| `container.barrel` | 27 storage, barrel title | Chest-family background |
| `container.fletching_table` | **No vanilla working crafting GUI if 26.3 still has none** | Do not fabricate a fletching menu; gameplay block interaction according to reference |
| `container.smithing_legacy` | Only for older compatibility save UI if source needs | Isolate version switch; default uses modern smithing UI |
| `container.repair` | Only if exposed by game state / mod, not a universal vanilla menu | Do not count imaginary screens |

### Villager trading specifics

The trading UI must show villager profession/title, level badge and progress bar, a scrollable left trade-selection list with costs and resulting item icons, right exchange slots and arrow, green/red trade availability feedback, temporary discounts, hovering item details, shift-click multiple trades, evolving trade offers on XP leveling. **26.3 allows newly unlocked villager trades to update while the player is still trading**; update list live without closing screen. Preserve selection/scroll if the corresponding trade remains valid. When `container.merchant` open at a very narrow width, put trade list into a left tab or top section while keeping the currently selected trade/result always visible.

### Smithing/Enchantment details

- Smithing result preview must use the actual armor trim texture/color and 3D model preview when relevant. Template/base/addition slots must show placeholders and accept valid registry item types only.
- Enchantment table animates the book independently of frame rate. Exactly three offers with numeric level costs, lapis requirement and runic/cipher text derived from actual seed/offer; don't show all options enabled when insufficient lapis/levels.
- Grinder should show valid output and XP effects; anvil should show `Too Expensive!` where vanilla and cost color red/green; char limits/rename validation.
- Stonecutter and loom use source recipe/pattern icons, scroll through all matches, and highlight selected result correctly; output item counts must match.

---
# 15. ALL TEXT-EDITING, BOOK, SIGN, MAP, AND SPECIAL-PURPOSE GAMEPLAY SCREENS

These screens are easy to miss because they are not part of the main menu. **All are required if corresponding gameplay mechanics exist**. If no separate UI exists in vanilla 26.3, the manifest must say `in_world_interaction`, not invent a popup.

## 15.1 Sign and Hanging Sign editors — `edit.sign`, `edit.hanging_sign`

- **World remains visible behind editor**, with the actual placed sign at its in-world position and text layout mapped onto the sign's 3D face as vanilla does; don't use a generic browser-style input form.
- Multi-line sign text editing (regular/hanging as actual vanilla supports), line-by-line cursor, up/down line navigation, Unicode, formatting permissions, color/dye and glow ink visual effects represented on sign texture. Confirm/Done centered lower section; Escape/cancel behavior follows reference. Validate length restrictions by glyph width and version rules, not arbitrary 64 characters.
- Front/back sign surface support from modern Minecraft; editor respects selected side, and waxed signs cannot be edited. Preserve text entry when the window is resized mid-edit.
- At narrow width the sign model remains a true rectangle with uniform scale, text clipped only to the actual in-world board; external controls reflow underneath.

## 15.2 Writable Book editor — `edit.book_and_quill`

- Book page background imported from 26.3; page text region and inner margins derived from sprite, not guessed generic text box.
- Editable multiline page with maximum character/page size and width/line constraints, page-turn corner controls, page count, `Sign` and `Done`; preserve cursor, selection and per-page contents while navigating and resizing.
- Signing book opens `edit.book_sign` overlay with editable title and sign/cancel actions. Signing is intentional and irreversible per game rules; don't auto-sign on Escape.
- Page rendering should match pixel-font line height and source word wrapping, including right-to-left and formatting codes where supported. Use clipping inside book page, not across the entire screen.

## 15.3 Written Book reader — `view.written_book`

- Same book page frame with read-only content; previous/next arrows, page count, clickable text components if actual content supports, hyperlinks and hover tooltips. Modal pinned to screen center; no unnecessary whole-screen text zoom.
- `Lectern` book reader uses correct page layout and may emit comparator updates when turning pages. A bound lectern in world can show page count and Done in source layout. Multiple readers may see synchronized page if game network logic exists.

## 15.4 Command Block GUI — `edit.command_block`

- Command text field (multiline or single-line with scroll per version), output display/toggle, block type (Impulse/Chain/Repeat), condition (Conditional/Unconditional), redstone mode (Needs Redstone/Always Active), Done/Cancel, previous output text and hover explanation. Correct labels/color and disabled states when player lacks permission.
- Command editing must never assume pasted user text is safe to execute instantly; save or commit per Minecraft action semantics. No invisible command field or overlapping footer on portrait.

## 15.5 Structure Block UI — `edit.structure_block`

- Modes Save, Load, Corner, Data, with name, relative position XYZ, size XYZ, mirror, rotation, integrity, seed, show bounding box, include entities, detect/save/load commands as appropriate to version. Mode-specific field visibility and positive/negative integer validation.
- Pixel form can be dense; at compact dimensions use center scroll body and pinned Done/Cancel, with visual grouping by mode. Normal-size screenshots must match exactly.
- Structure bounding preview uses real world overlay lines; a menu checkbox can't substitute for preview behavior.

## 15.6 Jigsaw Block UI — `edit.jigsaw_block`

- Target pool/template pool, name, target, final state, joint type (if exposed), selection priority/placement priority if current version supports, generation depth/levels, Keep Jigsaws toggle, Generate button and Done/Cancel. Version-driven data keys and field labels, no old 1.16-only assumptions.
- Tooltips explain syntax; validation does not prevent canceling and returning to world. Sizing follows `MenuFormShell`, compact scrolling.

## 15.7 Creative command / NPC special / debug menu rules

- A vanilla Java player should **not** get Bedrock's NPC dialogue/agent UI unless a real Java content source provides it.
- Debug stick, barrier and light block are interacted with in world; no invented dedicated menus.
- Block entity overlays beyond command/structure/jigsaw are included only if Java 26.3 actually presents separate screen.

## 15.8 Maps and cartography

- Held filled map is an in-world HUD render in hands with preserved aspect, not a full-screen game menu. Map icons and player marker orientation follow 26.3 current rules. Right-click/use on map behavior should reflect game state.
- Cartography table is a container (`container.cartography_table`), with input/output slots and map preview. Distinguish normal maps from **26.3 Explorer Maps**, whose individual item IDs and extension restrictions changed.

## 15.9 Recipe Book — `overlay.recipe_book`

- Work with crafting table, personal crafting, furnace/blast furnace/smoker/other relevant recipes. Recipes are categorized tabs with page arrows/scroll, search, available-only toggle, ingredient ghost overlays and click-to-fill.
- Left-of-inventory protruding panel in normal-width layout, which pushes main inventory to the right where vanilla does. Exact open/closed transitions, tab positions, recipe icons and filter state from source.
- On narrow screens use a source-art-preserving **switchable full-width recipe panel** over the inventory with a persistent Close/Back action. Preserve held item state and active recipe. Selecting a recipe updates actual crafting matrix or ghost overlay; never do nothing.

## 15.10 Item components, nested UI and hover-only interfaces

- Bundle preview, shulker contents preview where supported, written book hover pages, suspicious stew effect tooltips, potion effect descriptions, banner patterns, map ID/level, item lore, enchantments, attribute modifier lists, armor trim components, coordinates, food components and rarity colors all use precise Minecraft tooltip rendering with rich text.
- When `F3+H` advanced tooltips are enabled, show item registry name/durability/components actually available. Tooltip is repositioned/clamped intelligently at every window size.
- Modded extra tooltip components are not part of vanilla baseline; allow extension only after core is accurate.

---

# 16. DEATH, SLEEP, END, ACHIEVEMENTS, STATISTICS, CREDITS AND PROGRESSION

## 16.1 Death screens — `game.death`, `game.hardcore_death`

- Full-screen translucent red/dark overlay over *actual world* and centered death title, cause of death text, score where applicable. Vanilla button(s) `Respawn` and `Title Screen` / equivalents with 26.3 wording. **Hardcore:** no ordinary respawn; `Spectate World` and title/return path according to reference. Do not show a functioning Respawn button in Hardcore.
- Cause can include clickable/hover death message components and player names; layout handles long messages by wrap/clamp, with original colors and shadow. Resizing during death screen must not restart death animation or toggle eligibility.
- Confirm quit if the world will be deleted/irreversible action only where vanilla prompts; don't fabricate a forced delete. On respawn restore HUD/player control after world/position is actually ready.

## 16.2 Bed/sleep UI — `game.sleep`

- Sleeping-in-bed view usually remains mostly in-world with button `Leave Bed`, chat may open, time/night skip logic. Correct darkening, text if multiplayer waiting, visible button center/bottom based on reference. Straw beds introduced in 26.3 behave like beds but with correct item/block icon and statistic `Times Slept in a Straw Bed`.
- Sleep UI must work at any shape and must not center the sleep button over an obscured hotbar on tiny viewports.

## 16.3 Advancements — `game.advancements`

- Scrollable **advancement tree** with imported tab sprites, background tile patterns, nodes (completed/uncompleted progress states), connecting lines, hover detail tooltip with title, description and item icon, progress percentage when applicable. Correct tabs for Minecraft, Adventure, Nether, End, Husbandry and other **26.3 installed advancement registry groups**. Nested hidden advancements and criteria must not appear prematurely.
- The tree is pannable and zooms/pans with clamp, with screen header and Done/Back. It is **not** a flat checklist. Root/no advancements case, multiple background textures and tab-overflow arrows must be implemented.
- On wide screens center tree/panel; on portrait preserve central content but allow extra vertical tree viewport; UI tabs remain reachable.

## 16.4 Statistics — `game.statistics`

- Categories: General, Items, Mobs and actual category breakdown. Vanilla sortable tables/lists with icons and numeric values; columns and headers, scrolling, sorted state. 26.3 adds Times Slept in a Straw Bed. Populated from real game stat registry and saved player data; don't hardcode fixed 20 rows.
- Zero-stat rows may be hidden according to source logic. Use summary labels and `Done`, mobile-width responsive list columns (only extension if source would overflow). Numeric formatting/localization stable.

## 16.5 End poem and credits — `game.end_poem`, `game.credits`

- Full-screen dark background, scrolling stylized poem/credits text with original timing/speed, optionally skip with keyboard according to reference; loading proper locally installed resources and localization. The original content may be proprietary: extract only from locally installed game for private playback, do not bundle text in the clone's repository.
- Important interactive conditions: entering End portal after Dragon defeat, continue to respawn/title after credits, pause/skip state, resizing without restarting scroll. Long languages and CJK use correct wrapping. Never show empty fake credits page.

## 16.6 Toast/notice history and progress screens

`game.advancement_toast`, `game.recipe_toast`, `game.tutorial_toast`, `game.death_notice`, `game.world_save_progress`, `game.autosave_indicator`, `game.resource_reload`, `game.spawn_chunks_progress`, `game.terrain_loading`, `game.connecting_portal`, `game.dimension_transition`, `game.credits`, `game.end_poem`, `game.hardcore_death`, `game.sleep`.

A notification is **not necessarily its own full-screen scene**: overlays are entries in a single notification queue with content, timeout, animation and anchor. List them in the manifest as overlays, not menu screens, to avoid needless scene switching.

---

# 17. MODAL POPUPS, CONFIRMATIONS, ERROR STATES, HELP AND DISCOVERY

The client needs a comprehensive modal system for real operations. Screen-specific exceptions should not be replaced with the same anonymous alert. Each modal uses the correct Java-style background, title, explanatory text, button order, disabled state, and keyboard routing.

| Dialog or modal | Trigger | Required controls/behavior |
|---|---|---|
| Connection failed | DNS/auth/timeout/protocol | Detailed reason, Back/Retry if source supports it |
| Resource pack offer | Joining server or changing packs | Accept/Decline or Prompt; show pack details and size when available |
| Incompatible packs | Old/new pack format | Warning, choose/cancel, order preservation |
| Confirm world delete | World list | Dangerous action clearly distinct, Cancel remains available |
| Create same-name world | World create | Display resolved save folder, never overwrite |
| World conversion/upgrade | Older save load | Recommend backup; show version and recovery path |
| Experimental world warning | Create/load | Scope and acknowledgement per source |
| Multiplayer security | First launch of online play | Source text and Proceed/Cancel |
| Confirm external URL | Chat/server link | Show sanitized destination, Yes/No, never auto-open |
| Confirm command/game mode change | Restrictions/permission | State changes only upon genuine confirmation |
| Quit/disconnect | Pause/esc where applicable | Save/cleanup, route return |
| Reconfigure renderer | Graphics API switch | Warning/restart only where real renderer requires it |
| Asset import missing | First boot | Browse/Retry/Fallback/Exit with explicit missing list |
| Asset import corruption | Cache hash mismatch | Repair/rebuild without deleting users' game installation |
| Out of disk space | Import/save/download | Recoverable dialog and Retry/Back |
| World save failed | Autosave/manual save | Warn user, preserve in-memory state when possible |
| Cloud auth unavailable | Realms/friends | Truthful unavailable state, don't fake account success |
| Player report | Actual authorized reporting | Reason, evidence, submit, confirmation/failed |
| World lock/restrictions | World Options | Permission and irreversible change confirmation |
| Dangerous link/file | Resource pack and open folder | Explicit intent, path sanitization |

**UI consistency:** Standard modal width is `min(310, G_w-16)` logical pixels unless screenshot measures another width. Explanatory text centered with source-appropriate alignment and wrapped between top title and bottom paired buttons. At tiny widths switch to one-column buttons and scroll inner text, not stretch dialog to 1× viewport height and lose cancel.

---

# 18. INPUT, FOCUS, TOOLTIP, POINTER AND ACCESSIBILITY CONTRACT

## 18.1 Three input contexts

1. **Gameplay**: mouse captured, cursor hidden; pointer drives camera; hotkeys operate game.
2. **Menu**: mouse free/confined appropriately; pixel pointer visible; UI controls receive clicks; movement keys do not trigger actions unless vanilla allows.
3. **Text/drag**: user types into a field or drags a slot stack; some keyboard actions are consumed; global shortcuts still respect Esc/back; resize does not drop drag.

Switch contexts atomically. Closing the last menu restores gameplay capture only after appropriate state check. Do not unconditionally recapture when a world is loading/disconnected. On alt-tab focus loss, pause/uncapture as vanilla options specify; no stuck mouse button or locked key.

## 18.2 Exact input semantics

- Mouse: left/right/middle click, double click, hover, scroll wheel horizontal/vertical, drag, press outside modal, cursor tooltips, mouse capture, on-screen virtual cursor if gamepad activated.
- Keyboard: Tab focus navigation with logical order, Shift+Tab reverse, arrows for lists/sliders, Enter/Space activate, Esc close/back, Home/End and Page Up/Down for lists, Ctrl+A/C/V/X for editable text, arrow selection and IME composition. Do not interpret all Ctrl combos as world actions when text field owns focus.
- Key remapping: physical key scancodes in Java 26.3 style, repeat behavior, conflict warnings, modifier key releases, cursor mode, no permanent stuck shift/ctrl/alt.
- Gamepad (bonus but required for polished controller readiness): mapped D-pad navigation, A/Confirm, B/Back, shoulders for tabs, stick list scrolling, virtual cursor for complex grids. This is an **extension** rather than fake claim that Java keyboard/mouse UI has native identical gamepad behavior. Focus rectangle and help prompts remain Minecraft-style.
- Touch: optional fallback gestures/click targets, no pinch-induced nonuniform scaling of GUI, long press item tooltip, screen reader target, virtual keyboard. Not a replacement for desktop parity.
- Scroll routing: wheel over a list scrolls that list, not underlying gameplay hotbar; wheel over a slider only adjusts where 26.3 allows; wheel over recipe book scrolls recipes.
- Resize while mouse down: preserve whichever element owns pointer capture and its drag data; after reflow, convert pointer to new local rect and continue without item duplication.
- Focus when opening a screen: first meaningful button or text input, matching source. Back restores parent focus and scroll position. Disabled controls cannot accept focus unless accessibility narration specifically describes them.

## 18.3 Tooltip engine

- Tooltip state includes source item, rich component list, mouse anchor, text measurement, black/dark pixel border sprite, per-line color, optional item preview, min/max width, animation delay, modality.
- Placement algorithm: try right-and-below mouse → left → above → centered within safe rect. Prevent overlap with bottom hotbar/drag item if possible. For larger than viewport height, allow independent scroll and keep title visible.
- Never render source tooltip text into one giant bitmap that becomes blurry at higher scales. Cache glyph layouts; format after localization.

## 18.4 Text input / IME / localization

- Use correct active composition handling on Windows/macOS/Linux; newer macOS 26.3 supports native accent candidate popup during hold. Godot text controls may have platform-specific IME behavior; test real devices instead of assuming.
- Caret, selection, horizontal scroll, blink phase, max input bytes/chars/glyph lengths per field; no code execution from chat text or sign content.
- RTL/bidi screen readers, keyboard shortcuts, CJK font fallback and tooltip wrapping. Long German/Russian labels must not overlap paired buttons; if they do, reflow labels or use tooltip in compact mode.

## 18.5 Accessibility criteria

- Every interactive widget has visible and spoken name, state (checked/selected/disabled), description, keyboard action and focus order; describe icons not just tooltip strings.
- Color conveys state but isn't the only cue; focus border/underline or named state; ensure errors not red-only.
- Master text / GUI size control is operable even when current screen is clipped. The `Options → Video → GUI Scale` path must always be reachable, including via keyboard.
- Narration doesn't repeat every frame or resize; speech queued/debounced appropriately. All critical UI sounds have readable text equivalent (subtitles where gameplay sound).
- At huge UI scale, content scrolls while controls remain available, rather than silently failing.

---

# 19. RESPONSIVE RULES FOR EVERY UI FAMILY — NO ASPECT-RATIO FIXES

These layout modes are **intentional extensions**, while Classic reproduces Java 26.3. Enter the smallest mode necessary to avoid unusable content; hysteresis prevents mode jitter while resizing around a breakpoint.

## 19.1 Breakpoints in logical GUI width/height, not CSS pixels

| Mode | Trigger (after current GUI scale) | General layout policy |
|---|---|---|
| `CLASSIC` | width ≥ 410 AND height ≥ 230 and screen's own minimum fits | Pixel-comparable vanilla layout |
| `COMPACT` | width 320–409 OR height 180–229, or local overflow | Narrower margins, reduced nonessential vertical gaps, scroll content |
| `PORTRAIT` | aspect < 0.80, or width too narrow for 2-column controls | Single vertical column; large vertical scroll area; skinny panels centered |
| `TINY` | width < 320 OR height < 180 | Minimal reachable actions, scroll/collapse, uniform scale only, no clipping |
| `ULTRAWIDE` | aspect > 2.5 with sufficient width | Central classic-sized menu; edge overlays anchored; **no stretched menu** |
| `HIGH_DPI` | detected high pixel density / user accessibility scale | Same layout rules in logical units; render crisp pixels and readable text |

Triggers are initial safe values and should be tuned against actual screenshots/tests. Classic should be favored whenever the reference can fit. Different screen families have differing intrinsic minimum widths; e.g. a 176-wide inventory can still be Classic inside narrow portrait while a wide 350px server-list dialog cannot. The state decision should be based on `screen_min_width`, `screen_min_height`, and actual content bounds, not only the global thresholds above.

## 19.2 Per-family compact/portrait transformation table

| Family | Classic | Narrow/portrait | Very short/tiny |
|---|---|---|---|
| Title | Centered 200px column and logo | Uniformly sized logo, 1-column stack | Scrollable menu; quit/settings always reachable |
| World list | Wide center list and 2-row footer | List full usable width, buttons regroup | Sticky Play/Back, overflow menu for less-frequent actions |
| Create world | 3 tabs across top and center controls | Tabs may scroll or fit compressed, fields in one column | Sticky Create/Cancel + scroll form |
| Options | Paired 150px columns | One vertical column of same controls | Scroll list + fixed Done |
| Video/audio | Category rows, paired sliders | One-column categories | Collapse categories into expandable sections if needed |
| Keybinds | Action name/key/reset row | Wrap name, keep key visible on second line | Scroll list, dedicated bind dialog |
| Server list | Wide rows with icons and descriptions | Icons + two-line metadata; hide nonessential ping details into tooltip | Sticky Join/Back, action overflow |
| Realms | Tabs and realm cards/list | Tabs scroll, compact realm rows | Actions in accessible overflow drawer |
| Pause | Normal Minecraft centered button group | One-column same order | Scroll, pin Resume and Save/Quit |
| World Options | Two categories and many fields | Single-column settings, tabs | Scroll with persistent Done |
| Inventory 176×166 | Panel at intrinsic size + GUI scale | Center and uniform fit if needed | Scale down to fit or scroll outer panel with accessible slots |
| Creative inventory | Multiple protruding category tabs | Paginated tabs or category switcher | Keep slot area readable; scroll item results |
| Recipe Book | Beside inventory | Overlay/tab above inventory | Switchable overlay with search/close |
| Trading | Trade list left + exchange right | Trade list tab or top; selected trade lower | One trade visible plus scroll choices |
| Advancements | Tree panel with protruding tabs | Pan/scroll tree, tabs above | Zoom controls and scroll, no glyph squashing |
| Statistics | Multi-column data table | Wrap row content; column label-value | Scroll rows, keep category tabs pinned |
| Chat | Bottom left wide overlay | Width clamp, fewer lines | Narrow single column above essential controls |
| HUD | Center hotbar, left/right vitals | Uniform HUD scale down only enough to fit | Preserve minimal hotbar/crosshair; nonessential overlays queue |
| Book | Center page with arrows | Uniform page fit | Page scrolling with accessible arrows |
| Sign | In-world board centered | Board scales uniformly, text width maintained | Board-centered area with external Done below |
| Debug | Corner text panels | Independent scale with fold or scroll | Debug may cover scene but must stay navigable |
| Loading/error | Centered multiline card | Wrap paragraphs | Scroll text + pinned Back |

**Hard rule:** Reflow only *layout relationships*. **Do not alter Minecraft slot order, number of slots, widget state, world FOV base or text semantics** to fit a window. Do not stretch a 176px inventory sprite to 320px by changing only width; either uniform zoom, tiling as documented by metadata, or scrolling.

## 19.3 Dynamic responsive algorithm — detailed

1. Measure each text string and icon after font/language choice.
2. Determine intrinsic panel preferred width/height for active screen from asset dimensions + children.
3. Compute usable rectangle subtracting small fixed margins (min ~4 logical pixels) and any platform safe insets.
4. If preferred panel fits, use exact classic reference rect; align to GUI pixel grid.
5. If it doesn't fit because of **width**, attempt alternate vertical arrangement for menus, not inventories; if inventories use uniform fit in available width.
6. If it doesn't fit because of **height**, keep title and critical footer controls visible; put body in a scroll viewport or zoom uniformly if the screen is a fixed-intrinsic inventory sprite. For a fixed 176×166 inventory at tiny heights, a scrollable container is allowed as accessibility fallback, but click/drag behavior across scroll must be tested.
7. If both fail, use TINY mode. Prefer one 200px-equivalent control at a time and vertical scroll to presenting 40px unreadable text.
8. Set focus neighbors after actual layout, not based on original row indices; handle disabled controls.
9. After layout, collect all visible children and perform intersection/overflow assertions. If any fail, mark screen in parity report; do **not** quietly clip it.
10. Keep animation phase and user-edited state while layout changes.

## 19.4 Panorama/scene resizing

- Title panorama: use aspect-cover method, not `TextureRect` stretch scaling with unequal axes. For cubemap-based panorama, 3D sky camera itself adapts to viewport; overlay/title remains same anchor geometry. At very wide ratios panorama shows more of scene or cropped vertically depending on projection; no empty bands.
- Pause and inventory: live 3D world continues to fill viewport; dim overlay is a single fullscreen `ColorRect` or shader with actual viewport dimensions, independent of UI scale. 176×166 inventory remains centered on top.
- Beds/portals/death: their screen overlays cover exact viewport; circular/rectangular masks remain geometrically correct.
- Black bars are only acceptable if an **in-world cinematic cutscene explicitly uses artistic bars**, not as a side effect of game window size.

## 19.5 Specific coordinate example at three ratios

For a common 176×166 inventory panel at GUI scale `S`, panel top-left in *logical units* is always:

```text
L = (G_w - 176)/2; T = (G_h - 166)/2
```

- `1920×1080` Auto `S=4`: `G=480×270` ⇒ `(L,T)=(152,52)`, physical top-left `(608,208)`, physical panel `(704×664)`. The world remains 1920×1080.
- `1280×720` Auto `S=3`: `G≈426.67×240` ⇒ `(L,T)≈(125.33,37)`, physical top-left `(376,111)`, physical panel `(528×498)`.
- `3440×1440` Auto `S=6`: `G≈573.33×240` ⇒ `(L,T)≈(198.67,37)`, physical top-left `(1192,222)`, physical panel `(1056×996)`.
- `720×1280` Auto `S=2`: `G=360×640` ⇒ `(L,T)=(92,237)`, physical top-left `(184,474)`, physical panel `(352×332)`. No cropped panel and no black bars; dramatically taller world view is still rendered.

Note these are **computed examples**, not screenshot measurements; a specific inventory with recipe book open or a different imported background size has different panel origins. Fractional logical coordinates should be snapped to pixel grid consistently after physical transform so the sprites stay crisp.

---
# 20. REQUIRED SCREEN MANIFEST — DO NOT OMIT ANY ROUTE FAMILY

This is a **minimum discovered baseline**, not proof it exhausts all 26.3 internal screens. Before completion, cross-check the installed 26.3 reference UI and relevant registries/screenshot navigation, add newly discovered flows, and mark any incorrect historical routes `not_in_26_3` rather than silently pretending they exist. One listed row may comprise several state variants; create unique variants in the implementation manifest. Every screen entry must include `layout_ref`, `responsive_mode`, `controller`, `state_provider`, `implemented`, `interactive_test`, `visual_golden`, and `verification`.

| Family | Mandatory routes / variants | Notes |
|---|---|---|
| Boot / asset import | `boot.splash`, `boot.resource_scan`, `boot.source_selection`, `boot.import_progress`, `boot.import_error`, `boot.missing_assets`, `boot.cache_repair`, `boot.completed` | Clone-first-boot extension, not claim of vanilla launcher UI |
| Main/title | `title.main`, `title.language`, `title.accessibility`, `title.friends` | Java 26.3 local asset panorama and title layout |
| World list | `world.select`, `world.edit`, `world.delete_confirm`, `world.recreate` | List, editing, delete, recreate |
| World maintenance | `world.backup_confirm`, `world.backup_progress`, `world.upgrade_confirm`, `world.upgrade_progress`, `world.optimize`, `world.optimize_progress`, `world.corrupt`, `world.restore_backup`, `world.copy_error`, `world.delete_error`, `world.unsupported_version`, `world.experimental_warning`, `world.datapack_load_failed`, `world.safe_mode` | Each real operation has real state/progress |
| Creation | `world.create.game`, `world.create.world`, `world.create.more`, `world.superflat_customize`, `world.superflat_presets`, `world.single_biome`, `world.gamerules_create`, `world.experiments`, `world.datapacks`, `world.create_progress` | Three tabs + submenus |
| Pause / game | `game.pause`, `game.world_options.general`, `game.world_options.multiplayer`, `game.restrictions`, `game.lock_world`, `game.sleep`, `game.death`, `game.hardcore_death` | World Options replaces old Open-to-LAN pause entry |
| Options root | `options.main`, `options.video`, `options.audio`, `options.controls`, `options.keybinds`, `options.mouse`, `options.chat`, `options.accessibility`, `options.skin`, `options.language`, `options.resourcepacks`, `options.online`, `options.telemetry` | All option categories + platform variants |
| Multiplayer basic | `network.multiplayer_warning`, `network.multiplayer`, `network.add_server`, `network.edit_server`, `network.direct_connect`, `network.delete_server_confirm` | Authentic server-list list geometry |
| Multiplayer states | `network.resolving`, `network.connecting`, `network.authenticating`, `network.encrypting`, `network.login`, `network.configuration`, `network.pack_prompt`, `network.pack_download`, `network.pack_reload`, `network.joining_world`, `network.disconnected`, `network.kicked`, `network.failed`, `network.timeout`, `network.incompatible_protocol`, `network.banned`, `network.missing_mods` | Status tied to real network operations |
| Multiplayer social | `network.social_interactions`, `network.report_player`, `network.server_links`, `hud.player_list` | Permission/auth constraints truthful |
| Realms main | `realms.list`, `realms.intro`, `realms.join_by_code`, `realms.invite_codes`, `realms.configure`, `realms.loading`, `realms.error` | Includes new 26.3 features |
| Realms administration | `realms.pending_invites`, `realms.invited_players`, `realms.player_permissions`, `realms.world_slots`, `realms.world_options`, `realms.world_backup_list`, `realms.backup_detail`, `realms.backup_restore_confirm`, `realms.download_world`, `realms.upload_world`, `realms.create_world`, `realms.recreate_world`, `realms.minigames`, `realms.subscription`, `realms.trial`, `realms.expired`, `realms.close_confirm`, `realms.open_confirm`, `realms.region`, `realms.resource_pack`, `realms.invite_player`, `realms.remove_player_confirm`, `realms.news`, `realms.notifications` | Service-dependent actions may be blocked honestly |
| Inventory basic | `container.player`, `container.crafting`, `container.creative`, `container.chest_1`…`container.chest_6`, `container.ender_chest`, `container.shulker_box`, `container.barrel`, `container.hopper`, `container.dropper`, `container.dispenser`, `container.crafter` | Each has exact slot schema |
| Workstations | `container.furnace`, `container.blast_furnace`, `container.smoker`, `container.brewing_stand`, `container.enchanting`, `container.anvil`, `container.grindstone`, `container.smithing_table`, `container.stonecutter`, `container.loom`, `container.cartography_table`, `container.beacon`, `container.lectern` | Every progress/special widget |
| Mobile inventory entities | `container.merchant`, `container.horse`, `container.donkey`, `container.mule`, `container.llama`, `container.chest_boat`, `container.chest_minecart`, `container.hopper_minecart` | Live entity state needed |
| Recipe and effects | `overlay.recipe_book`, `overlay.item_tooltip`, `overlay.bundle_preview`, `overlay.item_hover` | Overlays, not necessarily full menu scene |
| Text editors | `edit.sign`, `edit.hanging_sign`, `edit.book_and_quill`, `edit.book_sign`, `view.written_book`, `edit.command_block`, `edit.structure_block`, `edit.jigsaw_block` | In-world or specialized UI |
| Progression | `game.advancements`, `game.statistics`, `game.end_poem`, `game.credits` | Panning trees, sorted stats, credits |
| HUD core | `hud.hotbar`, `hud.crosshair`, `hud.health`, `hud.armor`, `hud.hunger`, `hud.air`, `hud.experience`, `hud.offhand`, `hud.attack_indicator`, `hud.status_effects`, `hud.held_item_name` | Anchors not fixed aspect |
| HUD communication | `hud.chat`, `hud.chat_input`, `hud.actionbar`, `hud.title`, `hud.subtitle`, `hud.bossbar`, `hud.scoreboard`, `hud.subtitles`, `hud.music_toast`, `hud.advancement_toast`, `hud.recipe_toast`, `hud.tutorial_toast` | Overlay priority / edge collision |
| HUD game states | `hud.spectator_hotbar`, `hud.spectator_menu`, `hud.spectator_teleport`, `hud.spectator_team`, `hud.creative_hotbar_saved`, `hud.raid_bar`, `hud.sleeping`, `hud.mount_jump`, `hud.swim_air`, `hud.map_held`, `hud.spyglass`, `hud.portal`, `hud.freeze`, `hud.powder_snow`, `hud.totem_animation`, `hud.damage`, `hud.underwater`, `hud.camera_viewmodel`, `hud.riding` | Actual gameplay state |
| HUD debug | `hud.debug`, `hud.debug_pie`, `hud.debug_graph`, `hud.debug_f6_options`, `hud.debug_gamemode_switcher`, `hud.debug_f3x`, `hud.debug_chunk_borders`, `hud.debug_hitboxes` | Separate scale in 26.3 |
| Generic modals | `dialog.confirm`, `dialog.warning`, `dialog.error`, `dialog.external_link`, `dialog.progress`, `dialog.choice`, `dialog.permission_denied`, `dialog.unsupported`, `dialog.save_failed`, `dialog.video_restart`, `dialog.quit` | Use variants with exact labels/geometry |

**Coverage rules:**
- The single `options.video` route may have category tabs/scroll and many option rows. It is only complete once every verified 26.3 visible option is represented, correctly placed and functional. Route-count alone is insufficient.
- Likewise `container.creative` covers many category tabs and `container.merchant` many trade configurations. Each requires tests across variations.
- Some listed routes are **clone support screens**, or **conditional states not separate vanilla screens**. The manifest must tag `vanilla_26_3`, `conditional`, `overlay`, `clone_extension`, `service_blocked`, `not_in_version` or `reference_unknown`. Do not imply all share one-to-one class mapping with Mojang's client.
- Add a route whenever automated screenshots/reference exploration finds something unrepresented. The closing requirement is zero untriaged discovered screens, not just the rows above.

---

# 21. UI PERFORMANCE ENGINEERING AND RENDERING CORRECTNESS

1. **No per-frame menu relayout.** Update on viewport resize, font/language change, asset reload, list data change or dynamic widget state that actually affects size. Avoid a resize/layout loop caused by changing minimum size inside `resized` signal.
2. Cache imported sprite textures and styleboxes; never allocate a new texture for every hover or every drawn inventory item. All GUI repeated assets share resources.
3. Use virtualized rows for world/server lists, item-search results, trade lists, statistics and keybinding tables; do not create 20,000 Control nodes to show the first 15.
4. Batch inventory item/icon drawing where feasible without defeating hit testing. Small slot counts may use lightweight Controls; avoid one audio player or shader resource per slot.
5. Responsive calculations are pure/repeatable functions; test them in isolation. No random padding/position choices based on frame time.
6. Preserve 3D render budget: on options/inventory screen, don't trigger full chunk remesh or asset reimport just because UI moves. Menus should not cause frame spikes.
7. Pixel-art sprite reconstruction: imported `.mcmeta` animation frames and nine-slice metadata; correct texture sampling, no unintentional blurred inventory slots.
8. Keep UI 60 Hz or display refresh smooth even if world generation is asynchronous. Main-thread blocking asset imports must be broken into idle stages/worker operations; Godot scene changes and GPU resource creation must follow engine thread-safety rules.
9. Reuse one tooltip layer and one notification queue, not dozens of always-running hidden popups.
10. Font glyph/layout cache keyed by language/font/scale/text content; invalidate on resource pack change. Avoid full text reparse on each animation tick.
11. Profile CPU allocations, GPU draw calls and input latency at 320×240, 1080p, ultrawide, 4K. Place results in `docs/UI_PARITY.md` or benchmark log; no unverified claim of "zero impact".
12. UI frame pacing remains stable when resizing rapidly (e.g. dragging window from 2560×1440 down to 600×300), including input capture and drag interactions.
13. Disable/ignore off-screen UI content for input/hit testing; clipping only affects rendering, not parent event ownership unless explicitly configured.
14. Every GUI element should have exactly one source of layout truth: sprites provide intrinsic size; screen schema provides position; state provides visibility; localization provides measured label size.
15. Avoid rebuilding all UI scenes after changing one slider value. Bound controls update their own state and flush settings to disk with a safe debounce/commit strategy.

---

# 22. VISUAL PARITY VERIFICATION: INSTRUMENTED SCREENSHOTS OR IT IS NOT DONE

## 22.1 Capture pipeline

**Goal:** compare a deterministic reference screenshot from Minecraft Java 26.3 with an equally deterministic clone capture, in exactly the same drawable size, GUI scale, language, screen and state. The world/panorama portion may differ; mask dynamic background regions to compare GUI layer and geometry separately.

Create an automated UI test harness with commands similar to:

```text
godot --headless --path . --script tests/ui/ui_smoke.gd

godot --path . -- --ui-test-screen=title.main --ui-test-size=1280x720 \
  --ui-test-scale=3 --ui-test-language=en_us --ui-test-state=default \
  --ui-capture=out/title_1280x720.png
```

**These are example invocation contracts to implement, not existing Godot CLI built-ins.** A `--ui-test-size=` argument must be parsed by the project's test bootstrap and applied via supported Godot APIs before screenshot capture; headless mode may not support true GPU screenshot rendering on all platforms. Use a graphical test runner or offscreen supported renderer for reference goldens when needed, and use headless tests for structural/geometry assertions. Never report screenshot tests passed when no screenshot was captured.

### Source-reference capture checklist

At each actual native Java screenshot record:

```text
reference_version: 26.3
screen_id: options.video
display_pixels: 1920x1080
gui_scale: 4
locale: en_us
state: defaults
source: locally_captured_official_jar
rects:
  - id: title
    x: <MEASURE>
    y: <MEASURE>
    width: <MEASURE>
    height: <MEASURE>
  - id: button_1
    x: <MEASURE>
    y: <MEASURE>
    width: <MEASURE>
    height: <MEASURE>
  - id: button_2
    x: <MEASURE>
    y: <MEASURE>
    width: <MEASURE>
    height: <MEASURE>
background_mask: dynamic_world_or_panorama
notes: hover / keyboard focus / scrollbar position / tooltip / language
```

The `<MEASURE>` placeholders are **deliberate measurement fields**, not permission to skip measuring. A cloned screenshot that happens to look similar at 1920×1080 but has every button 10px too far right is not accepted.

## 22.2 Mandatory states to capture for each unique widget

- Idle, hovered, clicked/pressed, focused by keyboard, disabled, selected/toggled, tooltip visible, narrated/accessible focus as supported.
- For list item: empty, selected first, selected last, scroll middle, long label, incompatible/deleted entry.
- For text input: empty, typed, selected text, composition/IME, invalid input, too-long text and localized.
- For inventory slot: empty, hover, item with stack count, selected drag, ghost recipe, durability bar, enchant glint, tooltip.
- For slider: min, max, intermediate, keyboard step, width change during mouse drag.
- For network: loading, unavailable, failed and success only if genuinely connected.
- For world: creation with each tab, selected mode, warning, progress and real completed world.
- For modal: cancellation returns to same parent screen and scroll/focus.

## 22.3 Visual comparison scoring

- **Geometric parity at classic dimensions:** rect position/size difference target ≤1 logical GUI pixel for static widgets after reference measurement; capture rounding rules documented. Clipped or missing controls = automatic failure.
- **Artwork parity:** sprite hash/ID should match local imported asset ID; output texture color matches after deterministic UI compositing. Differences in dynamic panorama frames are masked. No smoothing/distortion: sampled corner pixel sizes consistent.
- **Text parity:** translation key/string, font, baseline, wrapping/truncation, drop shadow, colors and cursor blink state. Long strings verified separately.
- **Behavior parity:** each click/keyboard action routes to correct destination and updates actual state; no dead controls. Most important flows: Start World, Pause, Save, Options, Inventory, Crafting, Chat, World Options, Exit.
- **Responsive integrity:** at every test size, 0 off-screen non-scrollable essential controls, 0 accidental overlapping hitboxes, 0 non-square square-sprite distortions, 0 stalled hover/focus after resize, 0 mouse coordinate mismatches.
- **Performance:** no routine per-frame layout allocations when size/states unchanged, and no full-project hangs during resize, search/scroll or menu transitions. Profile and report measured timings.

## 22.4 Golden reference categories

A. **Title family** at three GUI scales and portrait/ultrawide.
B. **World selection / Create World** 3 tabs, each world type and customization child.
C. **Options** root, Video categories, Audio, Controls, Keybinds, Chat, Language, Accessibility, Online.
D. **Pause / World Options** General/Multiplayer, Restrictions, Game Rules and confirmation.
E. **Inventory family** each unique source background, with/without items, recipe book open, creative tabs.
F. **HUD** survival full vitals, Creative, Spectator, Hardcore, weather/underwater, effects, toasts, debug.
G. **Multiplayer / Realms** offline and signed-in reference when legally available, list and dialogs.
H. **Edit overlays** sign, book, command/structure/jigsaw blocks, stats, advancements, death, sleep, credits.

Reference parity does not require identical world landscape in the background; only GUI position/assets are evaluated against masked background. Keep screenshots and diff visualizations in a **local test-only directory**, never commit proprietary reference captures unless distribution rights are clear.

---

# 23. TEST MATRIX: SIZES, RATIOS, DPI, STATE AND INPUT

## 23.1 Required physical window sizes

**Run every core screen, every unique workstation skin and every overlay against these sizes.** Do not only run one happy-path at 1920×1080.

| Size | Ratio | Purpose |
|---|---|---|
| 320×240 | 4:3 | Java 26.3 documented minimum, scale1 |
| 640×360 | 16:9 | Short low-resolution, scale1 |
| 640×480 | 4:3 | Scale2 |
| 800×600 | 4:3 | Traditional small desktop |
| 1024×768 | 4:3 | GUI scale3 candidate |
| 1280×720 | 16:9 | Startup default |
| 1366×768 | ~16:9 | Common laptop odd pixel sizes |
| 1600×900 | 16:9 | Desktop mid-resolution |
| 1920×1080 | 16:9 | Main golden comparison |
| 2560×1440 | 16:9 | High DPI/scale |
| 3840×2160 | 16:9 | 4K raster and scale |
| 3440×1440 | ~21:9 | Ultrawide |
| 5120×1440 | 32:9 | Super ultrawide |
| 600×600 | 1:1 | Square |
| 720×1280 | 9:16 | Portrait landscape inversion |
| 1080×1920 | 9:16 | Tall portrait |
| 400×900 | ~4:9 | Narrow portrait |
| 600×300 | 2:1 | Very short game window |
| 500×200 | 2.5:1 | Very short under vanilla min-height |
| 280×180 | ~1.56:1 | Smaller than Java min; compact extension |
| 220×420 | ~1:1.91 | Extremely narrow compact extension |

Test at Auto and **minimum/maximum integer GUI scale** where meaningful, optional fractional UI scaling where supported, Windows 125/150/200% OS display scaling, and external monitor switch when practicable. Test long localized labels in German, French, Spanish, Arabic and at least one CJK locale; locale asset availability must be verified. At all sizes the *world occupies the entire client area*.

## 23.2 Dynamic resize torture tests

1. Open inventory with a carried stack of 64 blocks; resize through 1920×1080→3440×1440→400×900→1280×720 while continuing mouse drag; verify original stack count and hitbox.
2. Open Create World, type a long seed and world name; resize continuously; switch tabs and return; values persist.
3. Open Video Settings, drag GUI Scale or Render Distance while resizing; pointer remains on slider thumb and effect applies correctly.
4. Open chat with 10,000 historical messages, type partial command and IME text; resize, scroll, select text; no lost characters or duplicates.
5. Open creative search with 10,000+ items (registry test data), filter and drag an icon; resize and switch categories; scroll doesn't reset unexpectedly.
6. World list with 10,000 save metadata fixtures; scroll at 60fps and select row; resize; no click hits row that is visually elsewhere.
7. Multiplayer server browser with 500 entries and changing ping data; resizing shouldn't re-query network or create endless scene loads.
8. Realms list offline/expired, then unauthorized auth failure; no fake success UI.
9. Open book editor on page 43 with cursor in middle of an RTL line; resize; text and position retained.
10. Turn on narrator, change language, resize, use only keyboard to quit/reopen Settings; every action remains reachable.
11. F3 overlay with separate debug scale; change normal GUI scale and verify debug remains independent.
12. Hardcore death screen at 280×180; no Respawn action, title/leave still accessible.
13. Alt-tab while windowed exclusive/borderless modes are toggled; no mouse lock or stuck keys.
14. Repeated fullscreen↔windowed changes while resource pack reload is in progress; no black bars, crash or persistent clipped UI.
15. Change from 16:9 to 9:16 while 3D player holds a map or spyglass; model/mask remains undistorted.

## 23.3 Hit-testing automation

For every visible button `b`, compute the center of its transformed rectangle in UI input space; synthesize a click; assert the expected route/state change. For 9 hotbar slots, 36 inventory slots, every creative tab, trade rows and empty vs filled slots, synthesize click at center and along edges. Assert **visual→hitbox error <=1 logical GUI pixel** in classic mode. For scrollable controls, position pointer on first/last visible row and verify the correct indexed item receives action. Tooltips must never steal click events for controls underneath unless deliberately interactive.

## 23.4 State persistence tests

Settings persist through quit/relaunch, including GUI scale, volume sliders, fullscreen mode, accessibility settings, keybinds, active pack ordering and chat options. World creation state survives navigation until explicitly canceled. Screen stack survives temporary child dialogs. No setting changes game state merely because options were opened or resize occurred. Ensure no save file corruption after a window resize during autosave.

---

# 24. FINAL-PHASE-ONLY UI IMPLEMENTATION ORDER AND FEATURE-COMPLETION GATES

**DO NOT execute any of the following gates until Section 0.1 has passed and `docs/GAMEPLAY_COMPLETE.md` is validated.** These are **sub-stages of the final UI phase after the entire non-UI game is finished**, not concurrent milestones. Then use short, tested work slices and preserve the completed game.

### Gate 0 — UI foundation

- Build UI metrics, screen stack, theme, asset resolver, font text engine, base widget classes and test harness.
- One uniform GUI scale and responsive policy across all screens; root viewport always fills available window.
- Demonstrate title with imported owned sprite, correct hover/click, at 1920×1080, 3440×1440, 720×1280 and 320×240.
- Automated parse/smoke tests pass. **Cannot progress to visual polish without working input and responsive hitboxes**.

### Gate 1 — essential functional flows

- Title → Singleplayer → Create World → Start → HUD → Inventory → Crafting → Pause → Options → Save & Quit → World list.
- All buttons functional, world state persists, GUI scale live setting works. Resize torture tests pass in these views.
- Compare core screenshots to 26.3 local reference; log unmeasured values explicitly.

### Gate 2 — player UI and workstation parity

- Complete survival, creative, adventure, spectator HUD states; player inventory, all chest sizes, furnace and primary workstations, recipe book, crafting item transactions, chat, status effects, toasts, map/spyglass screen overlays.
- Input matrix passes; every inventory slot action validated; all imported panels match pixel rects where reference exists.

### Gate 3 — settings/world/network UI completeness

- Every 26.3 Options control implemented/functionally bound; Create World tabs, game rules/data packs/experiments; World Options General/Multiplayer; server list/add/edit/connect/error states; Realms/screens with backend blockers clearly tracked.
- Capture each menu at 16:9, ultrawide and portrait. No dead controls, no fake online success.

### Gate 4 — specialist and accessibility

- Books, signs, commands/structure/jigsaw editors, statistics, advancement tree, death/sleep/credits, debug overlays, full focus/narrator/locale support.
- Screen manifest complete (including discovered variants), responsive tests clean, parity goldens reviewed. No untriaged clipping or focus blockers.

### Gate 5 — final coverage audit

- Execute exhaustive screen route crawls and screenshot diff suite. Fix largest geometry deviations first. Verify all translation keys and live widgets against local Java 26.3, not screenshots from older editions.
- Produce an honest summary of **visual-verified**, **functional-verified**, **reference-unknown**, **service-blocked**, **not-in-version** for every row. Continue working through remaining features; do not declare final completion if any required behavior remains unimplemented or blocked without disclosure.

**Progress protocol, every implementation slice:** `inspect one relevant source → implement → run Godot parse/test → test at 4 sizes → capture PNG → compare geometry → update manifest/status → continue`. Avoid spending tokens narrating what a screenshot might look like; use measurements and actual UI code.

---

# 25. NON-NEGOTIABLE ACCEPTANCE CHECKLIST

Use checkboxes in `docs/UI_PARITY.md`. A checked item must have a test or screenshot ID.

- [ ] The game/window fills its client area with **no aspect-ratio lock** at every tested size.
- [ ] No letterboxing, pillarboxing or nonuniform scaling on any HUD or menu.
- [ ] A circle remains circular; square inventory slots and item icons remain square.
- [ ] No critical interactive element is offscreen and unreachable at portrait or tiny sizes.
- [ ] All essential GUI elements maintain correct screen or panel anchoring during resize.
- [ ] Visual click/hover/focus regions stay aligned after scale, DPI and window changes.
- [ ] User can modify GUI Scale using visible UI and keyboard without being trapped.
- [ ] Every native-size screen has measured/validated 26.3 widget positions, or explicit unverified gap.
- [ ] Main title logo, splash, panorama, buttons, footer and icons match installed 26.3 reference.
- [ ] Every options screen/setting (including 26.3 World Options and Online) is represented accurately.
- [ ] No 26.4-only UI controls are accidentally included as if part of 26.3.
- [ ] The world creation Game/World/More tabs and all their nested views function.
- [ ] Singleplayer list, edit, backup, delete, recreate and failure/upgrade flows function.
- [ ] HUD hotbar, experience, status, chat, bossbars, toasts and debug use correct anchors.
- [ ] All unique inventory panels use **correct native panel size and local slot geometry**.
- [ ] All 36 regular player inventory slots, hotbar, crafting, armor and offhand behave correctly.
- [ ] Creative categories/search/tabs/saved hotbars are complete for 26.3 registry.
- [ ] All workstation GUIs and villagers' live trade updates behave correctly.
- [ ] Recipe book displays actual available recipes, filters and ghost/auto-fill behavior.
- [ ] Books, signs, command/structure/jigsaw editors and interactive text are usable.
- [ ] Stats/advancement tree/credits/end poem/death/hardcore/sleep are implemented.
- [ ] Full multiplayer menu hierarchy and error states are present, with honest backend limitations.
- [ ] 26.3 Realms introduction, join codes, invite management, region and distance sliders appear in appropriate contexts.
- [ ] Mouse, keyboard, physical key binds, tab navigation, IME, subtitles and narration work.
- [ ] Localized long labels and RTL/CJK text remain functional; no silent text clipping.
- [ ] GUI artwork/fonts originate from private locally imported assets or explicitly labeled fallback.
- [ ] Screenshot goldens, geometry assertions, route crawl and resize stress suites pass.
- [ ] UI performance is benchmarked rather than asserted; no repeated layout work while idle.
- [ ] Final `UI_SCREEN_MANIFEST` has no unknown discovered screens and no falsely marked completed screens.

---

# 26. SOURCE LINKS, VERSION GUARDRAILS, AND REFERENCE MEASUREMENT NOTES

These are **reading/reference sources** for the agent, not embedded art. Sources may be updated; pin all implementation decisions to the user's exact installed 26.3 reference. This specification combines directly confirmed 26.3 UI changes with known Java layout conventions and explicitly labeled unmeasured numerical targets.

1. **Mojang official Java 26.3 release, 15 September 2026** — [minecraft.net/en-us/article/minecraft-java-edition-26-3](https://www.minecraft.net/en-us/article/minecraft-java-edition-26-3): exact UI changes, min window 320×240, borderless default, World Options sections and new fields, current panorama, music/notifications, debug overlay scale, accessibility subtitles and Realms changes.
2. **Minecraft Wiki: Java Options** — [minecraft.wiki/w/Options](https://minecraft.wiki/w/Options): GUI scale formula, current setting families and video/controls history; cross-check against installed current release.
3. **Minecraft Wiki: Title Screen** — [minecraft.wiki/w/Title_Screen](https://minecraft.wiki/w/Title_Screen): Java title layout and button families.
4. **Minecraft Wiki: Create New World** — [minecraft.wiki/w/Create_New_World](https://minecraft.wiki/w/Create_New_World): Game/World/More, presets, single-biome, world-generation selection.
5. **Minecraft Wiki: Game Menu / World Options** — [minecraft.wiki/w/Game_Menu](https://minecraft.wiki/w/Game_Menu), [minecraft.wiki/w/World_Options](https://minecraft.wiki/w/World_Options): pause hierarchy and 26.3 World Options changes.
6. **Minecraft Wiki: Resource Pack sprites** — [minecraft.wiki/w/Resource_Pack](https://minecraft.wiki/w/Resource_Pack): GUI sprite atlas, `stretch`, `tile`, `nine_slice` metadata and recent changes.
7. **Minecraft Wiki: Java Realms** — [minecraft.wiki/w/Java_Realms](https://minecraft.wiki/w/Java_Realms): 26.3 invitation codes, introduction and world distance sliders, configuration UI.
8. **Godot stable: Multiple resolutions** — [docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html): `canvas_items`, `viewport`, stretch modes, expand, scaling, high-DPI, 3D vs UI independent rendering and pitfalls. **Do not select Stretch Aspect Keep for the entire game.**
9. **Godot stable: Control** — [docs.godotengine.org/en/stable/classes/class_control.html](https://docs.godotengine.org/en/stable/classes/class_control.html): anchors, offsets, layout, mouse input filters, focus and theme overrides.
10. **Godot stable: UI system** — [docs.godotengine.org/en/stable/tutorials/ui/index.html](https://docs.godotengine.org/en/stable/tutorials/ui/index.html): Container nodes, Theme resources, keyboard/controller focus.
11. **Mojang GUI sprite changes (1.20.2)** — [feedback.minecraft.net/hc/en-us/articles/19703470383757-Minecraft-Java-Edition-1-20-2](https://feedback.minecraft.net/hc/en-us/articles/19703470383757-Minecraft-Java-Edition-1-20-2): sprites split from large sheets, GUI atlas, metadata scaling.

**Unverified-data policy:** Exact numeric title/button placements for every 26.3 screen are not all published in official release notes or available without running the exact client. The panel slot dimensions and menu geometry here are **well-established Java-style starting coordinates** and are explicitly subject to reference capture. Claiming every single button is already measured would be misleading. The task for Claude Code is to **perform those measurements**, track the `REF` values and iterate until layouts meet parity. That is how to get exact positions instead of a convincing-but-wrong imitation.

---

# 27. FINAL CLAUDE CODE DIRECTIVE

**THIS DIRECTIVE IS DEFERRED UNTIL THE WHOLE NON-UI GAME IS FINISHED AND VERIFIED.** If the main game is still under construction, **do not interrupt it, do not begin UI implementation, and do not reread this document**. Record it as the last workstream and resume the current game task. Only after Section 0.1's completion gate is satisfied, implement everything in this document as a fully working, tested UI subsystem integrated into the completed Godot game. Start the **final UI phase** with its foundation (Section 24 Gate 0), then finish all menus, screen geometry, styling, responsive scaling, and any-aspect-ratio support. Consult imported local Minecraft Java 26.3 assets and references. Do not substitute generic Godot buttons, fixed-resolution screenshots or Bedrock UI. Connect to real already-finished gameplay, preserve data on resize, generate screenshot/geometry tests, and fix discrepancies.

At every size and aspect ratio, the 3D game fills the whole window and the UI is uniformly scaled or responsively reflowed. **An inventory slot never becomes a rectangle simply because the window is very wide.** At normal desktop sizes, preserve exact pixel-measured Java 26.3 geometry. At unusual sizes, preserve usability without distorting the design. Continue through every screen entry and state; maintain `UI_SCREEN_MANIFEST.csv` and `UI_PARITY.md` so a future session can resume from the precise next unverified task without wasting tokens rereading the full document. Only report features finished when they have live behavior and passing layout/input tests. Never state that internet-dependent services, every menu or perfect 1:1 parity is complete without the necessary implementation and verification.
