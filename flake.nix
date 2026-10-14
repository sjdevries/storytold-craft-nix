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

      # Pinned app sources. The upstream craft repos have no flake.nix of their
      # own (a flake PR is open on each), so we fetch the source directly with
      # builtins.fetchGit, pinned by full commit hash for reproducibility.
      sources = {
        cadcraft = builtins.fetchGit {
          url = "https://github.com/storytold/cadcraft";
          rev = "4cb9e8a535b2fc51799dc454099c644c235c3efd";
        };
        gridcraft = builtins.fetchGit {
          url = "https://github.com/storytold/gridcraft";
          rev = "b3acae6b7782ea236d0fb87a0121fd1ba2e14c2b";
        };
        wordcraft = builtins.fetchGit {
          url = "https://github.com/storytold/wordcraft";
          rev = "3ede32e80e6fe496e2d4562094706d06c6b6e2d0";
        };
        pdfcraft = builtins.fetchGit {
          url = "https://github.com/storytold/pdfcraft";
          rev = "87b448b664e1b3c960b479cc0f2c2e7a82c7ac71";
        };
      };

      # Per-app craft-fonts pins (the rev each app's release workflow embeds).
      # Only used when a package is built with withFonts = true.
      craftFonts = {
        cadcraft = builtins.fetchGit {
          url = "https://github.com/storytold/craft-fonts";
          rev = "3d9ab3a132ed0eff457e424226a435a901da30d3";
        };
        gridcraft = builtins.fetchGit {
          url = "https://github.com/storytold/craft-fonts";
          rev = "abb83316d96aa59c1cf64784289e378fe9fa5695";
        };
        wordcraft = builtins.fetchGit {
          url = "https://github.com/storytold/craft-fonts";
          rev = "8dcdacd5153e64560d109541a47d806f26f048c0";
        };
        pdfcraft = builtins.fetchGit {
          url = "https://github.com/storytold/craft-fonts";
          rev = "3d9ab3a132ed0eff457e424226a435a901da30d3";
        };
      };

      mkCraft = import ./lib/mkCraft.nix;
    in
    {
      packages = forAllSystems (pkgs:
        let
          craft = mkCraft { inherit pkgs; };

          # Base (fontless) config per app.
          apps = {
            cadcraft = {
              version = "0.6.1";
              src = sources.cadcraft;
              cargoHash = "sha256-PPoc+p0SfJQYJGvFqJmLaJe4uYdR5Xv7dHg6gxD6Lbc=";
              extraGuiBuildInputs = [ pkgs.gtk3 pkgs.systemd ]; # rfd + hidapi
              description = "CadCraft — clean-room AutoCAD";
            };
            gridcraft = {
              version = "0.6.0";
              src = sources.gridcraft;
              cargoHash = "sha256-P6MZ87aZylYSF1aUNayEiCqVxorb643OLV1ylCxo0K0=";
              extraGuiBuildInputs = [ pkgs.gtk3 ]; # rfd
              description = "GridCraft — clean-room spreadsheet";
            };
            wordcraft = {
              version = "0.6.0";
              src = sources.wordcraft;
              cargoHash = "sha256-slhJhm93xZI4PBxY+tWlwMWzx/JEvyKOg2FKc15kT1w=";
              extraGuiBuildInputs = [ pkgs.gtk3 ]; # rfd
              description = "WordCraft — clean-room word processor";
            };
            pdfcraft = {
              version = "0.7.0";
              src = sources.pdfcraft;
              cargoHash = "sha256-nsOkFjGd5YJk2It0jf1pRd0jPLsm5zrfOVafKnPcG3E=";
              extraGuiBuildInputs = [ ]; # no rfd
              # WORKAROUND (verified 2026-10-12): the OCR stack (ocrs → rten →
              # rten-gemm 0.26.0) fails to codegen under rustc 1.98's LLVM —
              # `llvm.x86.avx512.vpdpbusd.512` signature mismatch (the crate's
              # old <64 x i8> args vs the new <16 x i32> the newer LLVM expects).
              # Pinning rustc 1.95 compiles it cleanly. 1.95 is the floor that
              # satisfies pdfcraft's own crate MSRVs (pdfcraft-* 1.95, rten 1.94,
              # hayro-syntax 1.92) while still carrying the pre-change LLVM.
              # Drop this override once rten-gemm 0.27.0 lands upstream + the
              # Cargo.lock is bumped — then the default 1.98 toolchain works.
              rustPlatform = pkgs.makeRustPlatform {
                cargo = pkgs.rust-bin.stable."1.95.0".default;
                rustc = pkgs.rust-bin.stable."1.95.0".default;
              };
              description = "PDFCraft — clean-room PDF viewer/editor";
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
