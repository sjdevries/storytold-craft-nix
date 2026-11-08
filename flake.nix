{
  description = "Nix packages for the storytold craft apps (CadCraft, GridCraft, WordCraft, PDFCraft)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Provides pkgs.rust-bin (specific pinned rustc versions) via the overlay.
    # Used to pin pdfcraft to rustc 1.95 (see the pdfcraft cfg below).
    rustOverlay.url = "github:oxalica/rust-overlay";
  };

  outputs = { self, nixpkgs, rustOverlay }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f (import nixpkgs {
          inherit system;
          overlays = [ rustOverlay.overlays.default ];
        }));

      # Pinned app sources. We fetch the source directly with builtins.fetchGit,
      # pinned by full commit hash for reproducibility.
      #
      # Packaging note (2026-11-07): effectcraft, designcraft and lightcraft now
      # ship their OWN upstream flake.nix + nix/package.nix. We deliberately do
      # NOT adopt them — user decision 2026-11-07: "keep my own flakes for now".
      # One mkCraft codepath for all 12 apps stays simpler, and our layer carries
      # the startup-update-check patch that upstream does not have.
      #
      # --- bumped 2026-11-07: whole suite to the 2026-11-06 release wave ---
      sources = {
        cadcraft = builtins.fetchGit {
          url = "https://github.com/storytold/cadcraft";
          rev = "32238e83c2c8bf643994132883e94bc96961f649"; # v0.18.0
        };
        gridcraft = builtins.fetchGit {
          url = "https://github.com/storytold/gridcraft";
          rev = "a6a6a49a0415087474251b08e887a3581fab9e14"; # v0.17.0
        };
        wordcraft = builtins.fetchGit {
          url = "https://github.com/storytold/wordcraft";
          rev = "02a802cbafe45b5c8fecc00490c8f6b78c5ba251"; # v0.16.0
        };
        pdfcraft = builtins.fetchGit {
          url = "https://github.com/storytold/pdfcraft";
          rev = "8c572792d6760bdc903d6f9a032e3e38e8f71cb8"; # v0.19.0
        };
        photocraft = builtins.fetchGit {
          url = "https://github.com/storytold/photocraft";
          rev = "efb7ebd0c0dab1fc108ee4642aa47c22694271a8"; # v0.21.0
        };
        vectorcraft = builtins.fetchGit {
          url = "https://github.com/storytold/vectorcraft";
          rev = "654749c16eb20b6d3182a96defb66e11d1a9649a"; # v0.22.0
        };
        filmcraft = builtins.fetchGit {
          url = "https://github.com/storytold/filmcraft";
          rev = "015d5b3ea37e1202a529e6245d3cc021c8c16ffd"; # v0.18.0
        };
        effectcraft = builtins.fetchGit {
          url = "https://github.com/storytold/effectcraft";
          rev = "42e3c6a6c119d973aa59ab0437487ea6cae6a15d"; # v0.22.0
        };
        soundcraft = builtins.fetchGit {
          url = "https://github.com/storytold/soundcraft";
          rev = "5ff012ab88490cdfc635ee304c1019885e1b880d"; # v0.18.0
        };
        deckcraft = builtins.fetchGit {
          url = "https://github.com/storytold/deckcraft";
          rev = "a3e2254d3de32ed1718f156f070b54a34b949b54"; # v0.16.0
        };
        designcraft = builtins.fetchGit {
          url = "https://github.com/storytold/designcraft";
          rev = "58ac6d29b260e033f4291afc4318b507cfd90fd9"; # v0.18.0
        };
        lightcraft = builtins.fetchGit {
          url = "https://github.com/storytold/lightcraft";
          rev = "16636c45a63bff3065a6fd31aecc22a6fc15ca53"; # v0.19.0
        };
      };

      # craft-fonts: PER-APP pins, matching what each app's own release workflow
      # embeds. User decision 2026-11-07: "craft-fonts per app to match upstream"
      # — the old single shared rev (3d9ab3a1, 2026-10-11) no longer matched any
      # upstream consumer.
      #
      # Source of truth, in order:
      #   1. <app>/.github/workflows/release.yml  `craft-fonts-ref:`  (override)
      #   2. else craft-common-actions release.yml `default:`          (suite pin)
      # The release workflow is what produces the official artifacts, so it wins
      # over an app's own flake where the two disagree.
      #
      # Known disagreement: designcraft's flake.nix pins abb83316 (2026-10-06)
      # while its release.yml pins b076417b (2026-10-24). We follow release.yml.
      #
      # Nix dedupes the identical fetches, so the shared b076417b rev costs one
      # download for the ten apps that use it.
      #
      # Re-verify every bump: the suite default and the per-app overrides move
      # independently.
      craftFontsRevs = {
        # b076417b — 2026-10-24, explicit in each app's release.yml
        cadcraft    = "b076417b5880bd4154bd22f00695b1d28c6bea83";
        gridcraft   = "b076417b5880bd4154bd22f00695b1d28c6bea83";
        wordcraft   = "b076417b5880bd4154bd22f00695b1d28c6bea83";
        pdfcraft    = "b076417b5880bd4154bd22f00695b1d28c6bea83";
        photocraft  = "b076417b5880bd4154bd22f00695b1d28c6bea83";
        vectorcraft = "b076417b5880bd4154bd22f00695b1d28c6bea83";
        filmcraft   = "b076417b5880bd4154bd22f00695b1d28c6bea83";
        designcraft = "b076417b5880bd4154bd22f00695b1d28c6bea83";
        lightcraft  = "b076417b5880bd4154bd22f00695b1d28c6bea83";

        # bfcbf714 — 2026-10-20, the craft-common-actions suite default;
        # these two set no per-app override, so they follow the suite pin.
        effectcraft = "bfcbf714e45a3ea8e98f88ab2b7971372a576414";
        soundcraft  = "bfcbf714e45a3ea8e98f88ab2b7971372a576414";

        # 37827adc — 2026-10-25, deckcraft's own release.yml override.
        deckcraft   = "37827adc41fd165f9a9234ac40f94dbad353aa69";
      };

      craftFonts = nixpkgs.lib.mapAttrs
        (_name: rev: builtins.fetchGit {
          url = "https://github.com/storytold/craft-fonts";
          inherit rev;
        })
        craftFontsRevs;

      mkCraft = import ./lib/mkCraft.nix;
    in
    {
      packages = forAllSystems (pkgs:
        let
          craft = mkCraft { inherit pkgs; };

          # Base (fontless) config per app.
          #
          # cargoHash recomputed for all 12 apps on 2026-11-07: every Cargo.lock
          # changed in this bump (40–191 new crates per app, ~1350 new crate
          # instances across the suite). Re-run the wrong-hash extraction on
          # every future bump — a stale cargoHash fails the vendor derivation,
          # it does not silently pass.

          # ---- cargo >= 1.99 required by craft-libs @ 92d392cf --------------
          #
          # Four apps pull craft-libs 92d392cf, whose crates/menu/Cargo.toml
          # declares
          #
          #   craft-keymap = { workspace = true, default-features = false,
          #                  features = [ "egui" ] }
          #
          # over a workspace root that gives `craft-keymap = { path =
          # "crates/keymap" }` with no default-features. Cargo 1.98 rejects
          # that override ("`default-features = false` cannot override
          # workspace's `default-features`"), so `cargo metadata` fails for
          # EVERY crate in that workspace. fetch-cargo-vendor-util then skips
          # them all and dies later with the misleading
          #
          #   Exception: Couldn't find manifest for crate craft-docpath
          #              inside .../git/92d392cf...
          #
          # — craft-docpath exists fine upstream at crates/docpath; it was
          # never indexed because the metadata call that indexes it failed.
          #
          # Cargo 1.99 accepts the manifest, so the affected apps build against
          # rust-bin 1.99. Verified 2026-11-08 by realising just the vendor
          # derivations: they build, and the existing cargoHash is still
          # accepted — the toolchain bump does not change the vendored output,
          # so no hash recompute is needed.
          #
          # NOTE this is a VENDORING floor, not an MSRV issue: the apps'
          # declared rust-version (1.95) was never the problem.
          #
          # ⚠ HOW TO RE-DERIVE THE AFFECTED SET ON A FUTURE BUMP.
          # Do NOT look at one craft-libs rev per app. Each app's Cargo.lock
          # carries SEVERAL craft-libs revs (wordcraft has six), so reading
          # the first match says the wrong thing — that is exactly how
          # wordcraft was missed the first time: its first-listed rev is
          # 762a06a4, but it also pulls 92d392cf transitively.
          #
          # Correct procedure: collect the FULL set of craft-libs revs per
          # app, then mark an app affected if ANY of its revs is 92d392cf
          # (or any other rev whose crates/menu/Cargo.toml overrides
          # default-features over a root that omits it).
          #
          # As of this bump exactly one rev is bad (92d392cf) and it reaches
          # four apps: cadcraft, designcraft, effectcraft, wordcraft. The
          # other eight apps' vendors build fine on 1.98 — confirmed by real
          # builds, not by inspection.
          #
          # Drop all four overrides once craft-nix's own nixpkgs provides
          # cargo >= 1.99 (our current lock, 8edc0c72, gives 1.98.1).
          rust199 = pkgs.makeRustPlatform {
            cargo = pkgs.rust-bin.stable."1.99.0".default;
            rustc = pkgs.rust-bin.stable."1.99.0".default;
          };

          apps = {
            cadcraft = {
              version = "0.18.0";
              src = sources.cadcraft;
              cargoHash = "sha256-WVRERkYps/v1SQTYVBrHrk1rRzBGDBnMPUl6lUjBjOs=";
              extraGuiBuildInputs = [ pkgs.gtk3 pkgs.systemd ]; # rfd + hidapi
              rustPlatform = rust199; # craft-libs 92d392cf needs cargo >= 1.99
              description = "CadCraft — clean-room AutoCAD";
            };
            gridcraft = {
              version = "0.17.0";
              src = sources.gridcraft;
              cargoHash = "sha256-Mb3HBd3fquTqMYkJ6m+j/+V7Yx5zg2a2LU3b98QEab4=";
              extraGuiBuildInputs = [ pkgs.gtk3 ]; # rfd
              description = "GridCraft — clean-room spreadsheet";
            };
            wordcraft = {
              version = "0.16.0";
              src = sources.wordcraft;
              cargoHash = "sha256-LsoTa1dUflP/Q2XKDUsEtk/kRdtgWyO87dXL2rPZEaI=";
              extraGuiBuildInputs = [ pkgs.gtk3 ]; # rfd
              rustPlatform = rust199; # pulls craft-libs 92d392cf transitively
              description = "WordCraft — clean-room word processor";
            };
            pdfcraft = {
              version = "0.19.0";
              src = sources.pdfcraft;
              cargoHash = "sha256-VHPrDEntypGEyeCg1VcIlZ6NRQQw+kXAn+bXJZvnMmI=";
              extraGuiBuildInputs = [ ]; # no rfd
              # WORKAROUND — STILL REQUIRED at 0.19.0 (re-verified 2026-11-07).
              # The OCR stack (ocrs → rten → rten-gemm 0.26.0) fails to codegen
              # under rustc 1.98's LLVM — `llvm.x86.avx512.vpdpbusd.512`
              # signature mismatch. Pin rustc 1.95, which is exactly pdfcraft's
              # own workspace MSRV (Cargo.toml `rust-version = "1.95"`) and still
              # carries the pre-change LLVM.
              #
              # Re-checked at v0.19.0: Cargo.lock still has rten 0.26.0 and
              # rten-gemm 0.26.0, so the drop condition is NOT met.
              # Drop only once upstream bumps rten-gemm off 0.26.0.
              # User decision 2026-11-07: keep the 1.95 pin.
              rustPlatform = pkgs.makeRustPlatform {
                cargo = pkgs.rust-bin.stable."1.95.0".default;
                rustc = pkgs.rust-bin.stable."1.95.0".default;
              };
              description = "PDFCraft — clean-room PDF viewer/editor";
            };
            # --- new apps added 2026-10-14: the rest of the ArtCraft suite ---
            photocraft = {
              version = "0.21.0";
              src = sources.photocraft;
              cargoHash = "sha256-u6hM6QTbRwbiuc24hGiQRv2Wsh70Wg07yZM1IQGVyUs=";
              extraGuiBuildInputs = [ pkgs.gtk3 ]; # rfd
              description = "PhotoCraft — clean-room Photoshop-style image editor";
            };
            vectorcraft = {
              version = "0.22.0";
              src = sources.vectorcraft;
              cargoHash = "sha256-wXaN0TDkhMT6SgOH5HO1NSVsvB3vT1bghEomOF3BYkc=";
              extraGuiBuildInputs = [ pkgs.gtk3 ]; # rfd
              description = "VectorCraft — clean-room Illustrator-style vector editor";
            };
            filmcraft = {
              version = "0.18.0";
              src = sources.filmcraft;
              cargoHash = "sha256-mQqu82vQiXpI0643hF3ZQ9HbZ0qNlDeMN9Q9LG++8lk=";
              extraGuiBuildInputs = [ pkgs.gtk3 pkgs.alsa-lib ]; # rfd
              description = "FilmCraft — clean-room Premiere-style video editor";
            };
            effectcraft = {
              version = "0.22.0";
              src = sources.effectcraft;
              cargoHash = "sha256-y2dt8DhUWQ+l2k8P3V7VZqdCbzY7C5jja5RVBq6oz54=";
              extraGuiBuildInputs = [ pkgs.gtk3 pkgs.alsa-lib ]; # rfd
              rustPlatform = rust199; # craft-libs 92d392cf needs cargo >= 1.99
              description = "EffectCraft — clean-room After Effects-style motion graphics";
            };
            soundcraft = {
              version = "0.18.0";
              src = sources.soundcraft;
              cargoHash = "sha256-ExKqLiUi8EeqJyvftaNwpdx/oYuQ/nnVqefXBC9jVCM=";
              extraGuiBuildInputs = [ pkgs.gtk3 pkgs.alsa-lib ]; # rfd
              description = "SoundCraft — clean-room Pro Tools-style audio workstation";
            };
            deckcraft = {
              version = "0.16.0";
              src = sources.deckcraft;
              cargoHash = "sha256-uoKVa3SVGaWAoJ5o3VL+FI9d843OJyR2x0NnGx9azC0=";
              extraGuiBuildInputs = [ pkgs.gtk3 pkgs.alsa-lib ]; # rfd
              description = "DeckCraft — clean-room PowerPoint-style presentations";
            };
            designcraft = {
              version = "0.18.0";
              src = sources.designcraft;
              cargoHash = "sha256-jLb9jIh3P8u1mcJG8jXJbnbfkGf3B4SctYEXgJqPU/Q=";
              extraGuiBuildInputs = [ pkgs.gtk3 ]; # rfd
              rustPlatform = rust199; # craft-libs 92d392cf needs cargo >= 1.99
              description = "DesignCraft — clean-room InDesign-style page layout";
            };
            lightcraft = {
              version = "0.19.0";
              src = sources.lightcraft;
              cargoHash = "sha256-QRYnnaffvzVa82QH6ucBfTWW9tyc8PBD2cQCaplw0MA=";
              extraGuiBuildInputs = [ pkgs.gtk3 ]; # rfd
              description = "LightCraft — clean-room Lightroom-style photo library";
            };
          };

          # Build both the fontless and the with-fonts variant for each app.
          variants = nixpkgs.lib.mapAttrs (name: cfg: {
            plain = craft (cfg // { inherit name; });
            fonts = craft (cfg // {
              inherit name;
              withFonts = true;
              craftFontsSrc = craftFonts.${name};
            });
          }) apps;

          # Flatten to package names: <app>, <app>-cli, <app>-fonts, <app>-cli-fonts.
          flatten = nixpkgs.lib.foldlAttrs
            (acc: name: v: acc // {
              "${name}" = v.plain.gui;
              "${name}-cli" = v.plain.cli;
              "${name}-fonts" = v.fonts.gui;
              "${name}-cli-fonts" = v.fonts.cli;
            })
            { };
        in
        flatten variants // { default = variants.cadcraft.plain.gui; });
    };
}
