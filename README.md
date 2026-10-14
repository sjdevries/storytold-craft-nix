# storytold-craft-nix

Nix flake for the **storytold craft apps** — [CadCraft](https://github.com/storytold/cadcraft),
[GridCraft](https://github.com/storytold/gridcraft), [WordCraft](https://github.com/storytold/wordcraft),
and [PDFCraft](https://github.com/storytold/pdfcraft) — a family of clean-room, pure-Rust
alternatives to AutoCAD / Excel / Word / Acrobat.

This repo is a **reference / staging flake**: it builds every app in every variant from the
pinned upstream sources, and is structured so the derivations can be contributed either into the
craft repos themselves or into nixpkgs.

## Packages

Each app ships a desktop **GUI** and a headless **CLI**, in a **fontless** and an
**embedded-fonts** build — 16 packages total:

| Package | What |
|---|---|
| `<app>` | desktop GUI, fontless (default) |
| `<app>-cli` | headless CLI, fontless — minimal closure, ideal for scripting / agents |
| `<app>-fonts` | desktop GUI with embedded fonts (CJK, Arabic, Thai, …) |
| `<app>-cli-fonts` | headless CLI with embedded fonts |

…for `cadcraft`, `gridcraft`, `wordcraft`, `pdfcraft`. `default` → `cadcraft` (GUI, fontless).

```sh
nix build .#cadcraft-cli        # headless converter / command runner / MCP server
nix build .#cadcraft-fonts      # GUI with CJK/Arabic/Thai glyphs
nix run   .#gridcraft           # launch the GridCraft GUI
nix run   .#wordcraft-cli -- --help
```

### The `withFonts` option

The shared builder (`lib/mkCraft.nix`) takes `withFonts = true` + a `craftFontsSrc`
(a `storytold/craft-fonts` checkout) and sets `CRAFT_FONTS_DIR` / `CRAFT_FONTS_REQUIRED`,
exactly like the upstream release workflow. Without it the build is "fontless" — everything
works, but some scripts have no glyphs. Each app pins the craft-fonts revision its own release
workflow uses (see `craftFonts` in `flake.nix`).

> Note: upstream's font policy excludes Adobe-licensed faces, so a build may warn
> "not embedding … (no Adobe fonts)". That is expected, not an error.

### Desktop integration

The GUI build installs the desktop files the upstream source already ships under
`packaging/linux/` plus the `assets/app-icon/hicolor/` icon tree, into the standard FHS
layout (matching the upstream `package.sh` staging):

| Installs to | What |
|---|---|
| `share/applications/ai.storyteller.<app>.desktop` | the menu entry (`Exec=<app> %F`) |
| `share/icons/hicolor/<size>/apps/` | the icon, all 8 sizes |
| `share/mime/packages/ai.storyteller.<app>.xml` | DXF/DWG file associations |
| `share/metainfo/ai.storyteller.<app>.metainfo.xml` | AppStream metadata |

The metainfo template's `@VERSION@` / `@DATE@` placeholders are substituted at build time
(`version` from the package, date from the `metaDate` param). The **CLI** variant gets no
desktop entry — it's headless. On NixOS the desktop database and icon cache rebuild on
switch, so the apps appear in the KDE/GNOME menu under their display names
(**CADCraft**, **GridCraft**, **WordCraft**).

> The GUI runtime closure deliberately includes `wayland` even though the binary isn't
> linked against it — winit `dlopen`s `libwayland-client.so` at startup, and without it
> on the path a Wayland session crashes with `NoWaylandLib`. (This bit gridcraft; the
> other two silently fell back to X11/XWayland.)

## Relationship to the upstream flake PRs

Every craft app already has an open, well-structured flake PR — the canonical,
desktop-integrated packaging (root `flake.nix` + `nix/package.nix`, overlays,
`.desktop`/icons/AppStream, portal-aware file dialogs). The bulk are a consistent
series by **@untypequicode** titled *"Add a Nix flake (NixOS, GNOME and Hyprland)"*:

| App | Nix flake PR | Author |
|---|---|---|
| CadCraft | [#794] | @untypequicode |
| GridCraft | [#757] | @untypequicode |
| WordCraft | [#1000] | @untypequicode |
| PDFCraft | [#1511] | @untypequicode |
| DeckCraft | [#261] | @untypequicode |
| DesignCraft | [#611] | @untypequicode |
| EffectCraft | [#1069] | @untypequicode |
| FilmCraft | [#1374] | @untypequicode |
| PhotoCraft | [#4338] | @untypequicode |
| SoundCraft | [#325] | @untypequicode |
| VectorCraft | [#1456] | @untypequicode |
| LightCraft | [#1211] + fix [#1314] | @dev-null-undefined + @untypequicode |

> PhotoCraft also has an earlier, separate flake PR [#621] by @makemake-kbo.

**This repo is complementary, not a replacement.** It fills the gaps those PRs don't expose as
first-class packages:

- a **separate CLI-only package** (`<app>-cli`) with a minimal headless closure — the upstream
  combined package builds the CLI as a second binary inside the GUI's derivation;
- a **named fontless variant** — upstream only offers fontless via a `craft-fonts = null` override.

If those PRs merge, you can consume them directly (`inputs.cadcraft.url = "github:storytold/cadcraft"`)
and this repo stays as the variants reference. If you'd rather have the variants upstream, the
`lib/mkCraft.nix` derivations are written to drop straight into a craft repo's root flake with
`src = ./.`.

## Known issues

### pdfcraft — OCR stack needs a pinned rustc (AVX-512 / LLVM) — RESOLVED via pin

`pdfcraft`'s OCR path (`ocrs → rten → rten-gemm 0.26.0`) fails to codegen under rustc 1.98's
LLVM:

```
error: intrinsic signature mismatch for `llvm.x86.avx512.vpdpbusd.512`:
  expected `<16 x i32> (<16 x i32>, <16 x i32>, <16 x i32>)`,
  found    `<16 x i32> (<16 x i32>, <64 x i8>, <64 x i8>)`
```

The crate uses per-function `#[target_feature(enable = "avx512vnni")]`, so a lower
`target-cpu` does **not** skip the kernel.

**Resolution (this flake):** pdfcraft is built with a **pinned rustc 1.95** (via `rust-bin` /
`oxalica/rust-overlay`), which carries the pre-change LLVM and compiles the crate cleanly — both
the GUI and CLI build and run. The viable window is **1.95 ≤ rustc < 1.98**: 1.95 is the floor
that satisfies pdfcraft's own crate MSRVs (`pdfcraft-*` 1.95, `rten` 1.94, `hayro-syntax` 1.92).
The pin is applied only to the `pdfcraft` config in `flake.nix`; the other three apps use the
default toolchain.

**Clean upstream resolution:** a `Cargo.lock` bump to **rten-gemm 0.27.0** (2026-10-02) in the
pdfcraft repo would let the default 1.98 toolchain work.

**How to drop the pin** (once that bump is in a pdfcraft release):

1. Update the `pdfcraft` source `rev` in `flake.nix` to one that carries `rten-gemm 0.27.0`,
   and refresh its `cargoHash` (run `nix build .#pdfcraft` and let the hash-mismatch error
   report the new `sha256`).
2. Delete the `rustPlatform = pkgs.makeRustPlatform { … }` block from the `pdfcraft` config.
   The app then falls back to the default `pkgs.rustPlatform` (1.98), which now compiles it.
3. If no other app needs it, drop the now-unused `rustOverlay` input and the
   `overlays = [ rustOverlay.overlays.default ]` line in `forAllSystems`, then
   `nix flake update` to prune it from the lock.
4. `nix build .#pdfcraft .#pdfcraft-cli` to confirm the default toolchain builds both targets.

The pin is deliberately isolated to the `pdfcraft` config, so removing it touches nothing else.

### CadCraft — AutoCAD Mechanical Part Tables (BOM) are not extractable

For BOM extraction specifically: CadCraft reads the **old** representation of a parts list
(plain `MTEXT` columns) cleanly — both as text via the CLI and rendered in the GUI. But a
**live AutoCAD Mechanical "Part Table"** (the dynamic BOM object, related to `AM_PAREF` part
references) is a closed proprietary object: neither CadCraft nor LibreDWG decodes its cell data,
and the GUI renders the table area blank. That's a format limitation, not a packaging one — see
the upstream feature request for decoding the ACM Part Table into CadCraft's native `Table` model.

## Structure

```
flake.nix          # pinned sources + the 16 package variants
lib/mkCraft.nix    # shared builder: GUI + CLI, withFonts toggle, per-app system deps
```

Sources are pinned with `builtins.fetchGit` (the upstream repos have no flake of their own yet),
and `cargoHash` pins each app's dependency tree.

## Bumping

- **App version:** update the `rev` in `sources.<app>` + the `version`, then refresh `cargoHash`
  (build with a placeholder hash and read the `got:` value).
- **Fonts:** update the `rev` in `craftFonts.<app>`.

## License

This packaging repo (the Nix expressions and docs) is licensed under the **MIT License** — see
[`LICENSE`](LICENSE).

The craft applications themselves are **MIT OR Apache-2.0** (dual-licensed upstream), so the
built packages carry that dual license plus the embedded fonts' SIL OFL licenses.


[#794]: https://github.com/storytold/cadcraft/pull/794
[#757]: https://github.com/storytold/gridcraft/pull/757
[#1000]: https://github.com/storytold/wordcraft/pull/1000
[#1511]: https://github.com/storytold/pdfcraft/pull/1511
[#261]: https://github.com/storytold/deckcraft/pull/261
[#611]: https://github.com/storytold/designcraft/pull/611
[#1069]: https://github.com/storytold/effectcraft/pull/1069
[#1374]: https://github.com/storytold/filmcraft/pull/1374
[#4338]: https://github.com/storytold/photocraft/pull/4338
[#325]: https://github.com/storytold/soundcraft/pull/325
[#1456]: https://github.com/storytold/vectorcraft/pull/1456
[#1211]: https://github.com/storytold/lightcraft/pull/1211
[#1314]: https://github.com/storytold/lightcraft/pull/1314
[#621]: https://github.com/storytold/photocraft/pull/621
