# UI layout decisions

1. **Absolute GUI-pixel geometry, not Godot containers.** Every vanilla-style screen places widgets with
   `McW.place(x, y, w, h)` in GUI pixels (× GUI scale) from a `_layout()` run on resize. This mirrors Java's
   `bounds()`/layout arithmetic and keeps one source of truth per screen.
2. **Recraft-only settings live in clearly labelled places.** Video Settings ends with a "Recraft" section (terrain
   renderer, FPS counter, AA, render scale, fog, debug metrics, re-import assets, placeholder assets). Create World's
   World tab has a "Generator" cycle (Java 26.3 / 1.18.2 approximate / hybrid) under the vanilla switch grid.
3. **Unimplemented vanilla options are visible but disabled** with a tooltip giving the reason, never dead buttons
   and never decorative toggles (spec rule 7). Where Recraft has fixed behaviour (e.g. LAN command access) the row
   shows the true fixed value.
4. **Mojang services** (Realms, feedback, bug reports, friends, Xbox settings) are disabled with the reason.
5. **Sub-screens overlay their parent** (parent widgets hidden) instead of being rebuilt, so unsaved state (Create
   World model, options) survives, matching Java returning to the parent screen instance.
6. **Resource packs apply on the next start** (stated on the pack screen); Java reloads immediately.
7. **Title copyright line** is replaced by the "Not an official Minecraft product..." notice; bottom-left shows the
   Recraft build and the installed asset version.
8. **Title icon buttons** open the Language and Accessibility screens directly (as vanilla); Done returns to the title.
