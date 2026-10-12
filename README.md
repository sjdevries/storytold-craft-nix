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

## Relationship to the upstream flake PRs

Every craft repo already has an open, well-structured flake PR by **@untypequicode**
(cadcraft [#794], gridcraft [#757], wordcraft [#1000], pdfcraft [#1511]) — those are the
canonical, desktop-integrated packaging (root `flake.nix` + `nix/package.nix`, overlays,
`.desktop`/icons/AppStream, portal-aware file dialogs).

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

### pdfcraft — OCR stack fails to build (AVX-512 / LLVM)

`pdfcraft`'s OCR path (`ocrs → rten → rten-gemm 0.26.0`) fails to codegen under rustc 1.98's
LLVM:

```
error: intrinsic signature mismatch for `llvm.x86.avx512.vpdpbusd.512`:
  expected `<16 x i32> (<16 x i32>, <16 x i32>, <16 x i32>)`,
  found    `<16 x i32> (<16 x i32>, <64 x i8>, <64 x i8>)`
```

The crate uses per-function `#[target_feature(enable = "avx512vnni")]`, so a lower
`target-cpu` does **not** skip the kernel. **rten-gemm 0.27.0** (2026-10-02) likely fixes it;
the clean resolution is a `Cargo.lock` bump upstream. The other three apps build fine.

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

[#794]: https://github.com/storytold/cadcraft/pull/794
[#757]: https://github.com/storytold/gridcraft/pull/757
[#1000]: https://github.com/storytold/wordcraft/pull/1000
[#1511]: https://github.com/storytold/pdfcraft/pull/1511
