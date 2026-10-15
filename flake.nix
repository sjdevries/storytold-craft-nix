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
        # --- updated 2026-10-14: all four bumped a version ---
        cadcraft = builtins.fetchGit {
          url = "https://github.com/storytold/cadcraft";
          rev = "fc4e98315a8d771b5ab832f0ade0b5e7b106df7f";
        };
        gridcraft = builtins.fetchGit {
          url = "https://github.com/storytold/gridcraft";
          rev = "e6b6b349708ab4978cb3f061f6bd6ecbc25667cb";
        };
        wordcraft = builtins.fetchGit {
          url = "https://github.com/storytold/wordcraft";
          rev = "fd0bb2fb1ec081e3eddc4d01917637fef0cafdfe";
        };
        pdfcraft = builtins.fetchGit {
          url = "https://github.com/storytold/pdfcraft";
          rev = "afa8e1843cfed613f3d403119f6c2649bce824c9";
        };
        # --- new apps added 2026-10-14: the rest of the ArtCraft suite ---
        photocraft = builtins.fetchGit {
          url = "https://github.com/storytold/photocraft";
          rev = "df055f3dcb0bb0312af97548ee6c6f9628f21dd7";
        };
        vectorcraft = builtins.fetchGit {
          url = "https://github.com/storytold/vectorcraft";
          rev = "b12a52f7249e0aa73f030587e05ed9ce0c73ab67";
        };
        filmcraft = builtins.fetchGit {
          url = "https://github.com/storytold/filmcraft";
          rev = "8309f21a6c3f34ddf190af7fd9bfd913053a1fd5";
        };
        effectcraft = builtins.fetchGit {
          url = "https://github.com/storytold/effectcraft";
          rev = "0311bdc34d0dc10c2d18ff7875b4f52d483e5e27";
        };
        soundcraft = builtins.fetchGit {
          url = "https://github.com/storytold/soundcraft";
          rev = "3a28a657692c1b98b28c276d8f61df9471074f0f";
        };
        deckcraft = builtins.fetchGit {
          url = "https://github.com/storytold/deckcraft";
          rev = "9859da39255c0262cd592bb57101d7f2fa961f72";
        };
        designcraft = builtins.fetchGit {
          url = "https://github.com/storytold/designcraft";
          rev = "a930276fd7462f3d9abd2fbb38544c94c0c911c8";
        };
        lightcraft = builtins.fetchGit {
          url = "https://github.com/storytold/lightcraft";
          rev = "0da998f24dfc03069d49867f8877af2bf7c51f94";
        };
      };

      # craft-fonts is a single shared repo (one fonts/ tree: Noto CJK/Arabic/Thai,
      # BizUD, Shippori). The rev each app's release workflow embeds; latest is
      # 3d9ab3a1. We use one shared pin for every app (Nix dedupes the fetch).
      # Only used when a package is built with withFonts = true.
      craftFontsRev = "3d9ab3a132ed0eff457e424226a435a901da30d3";
      craftFonts = nixpkgs.lib.genAttrs
        [ "cadcraft" "gridcraft" "wordcraft" "pdfcraft"
          "photocraft" "vectorcraft" "filmcraft" "effectcraft"
          "soundcraft" "deckcraft" "designcraft" "lightcraft" ]
        (_: builtins.fetchGit {
          url = "https://github.com/storytold/craft-fonts";
          rev = craftFontsRev;
        });

      mkCraft = import ./lib/mkCraft.nix;
    in
    {
      packages = forAllSystems (pkgs:
        let
          craft = mkCraft { inherit pkgs; };

          # Base (fontless) config per app.
          apps = {
            # --- updated 2026-10-14: all four bumped a version ---
            cadcraft = {
              version = "0.7.0";
              src = sources.cadcraft;
              cargoHash = "sha256-7/TxuM5jh6fncL0+pAT147GJuri/sD0xnN6lRxueD0E=";
              extraGuiBuildInputs = [ pkgs.gtk3 pkgs.systemd ]; # rfd + hidapi
              description = "CadCraft — clean-room AutoCAD";
            };
            gridcraft = {
              version = "0.7.0";
              src = sources.gridcraft;
              cargoHash = "sha256-9PJmE7dLeDIEsnczga1WfWaad1e0YLLh04rJcSyzGwE=";
              extraGuiBuildInputs = [ pkgs.gtk3 ]; # rfd
              description = "GridCraft — clean-room spreadsheet";
            };
            wordcraft = {
              version = "0.7.0";
              src = sources.wordcraft;
              cargoHash = "sha256-Hc/+C2hh4vuBxPr2a8b5R94Fwy3Md5asmIDaG4pcHTc=";
              extraGuiBuildInputs = [ pkgs.gtk3 ]; # rfd
              description = "WordCraft — clean-room word processor";
            };
            pdfcraft = {
              version = "0.8.0";
              src = sources.pdfcraft;
              cargoHash = "sha256-PoXZ0+0Dlf3YBeDTuGsqla9w15I2ToJw1PyxIluu81s=";
              extraGuiBuildInputs = [ ]; # no rfd
              # WORKAROUND (still required for 0.8.0, re-verified 2026-10-14):
              # the OCR stack (ocrs → rten → rten-gemm 0.26.0) fails to codegen
              # under rustc 1.98's LLVM — `llvm.x86.avx512.vpdpbusd.512`
              # signature mismatch. Pin rustc 1.95, which is exactly pdfcraft
              # 0.8.0's own workspace MSRV and still carries the pre-change LLVM.
              # Drop once rten-gemm 0.27.0 lands upstream + Cargo.lock bumps.
              rustPlatform = pkgs.makeRustPlatform {
                cargo = pkgs.rust-bin.stable."1.95.0".default;
                rustc = pkgs.rust-bin.stable."1.95.0".default;
              };
              description = "PDFCraft — clean-room PDF viewer/editor";
            };
            # --- new apps added 2026-10-14: the rest of the ArtCraft suite ---
            photocraft = {
              version = "0.9.0";
              src = sources.photocraft;
              cargoHash = "sha256-w+u3fMZoZj4tiLZee9R0ZOG9cEv+7vV2GpDj6gZ96T4=";
              extraGuiBuildInputs = [ pkgs.gtk3 ]; # rfd
              description = "PhotoCraft — clean-room Photoshop-style image editor";
            };
            vectorcraft = {
              version = "0.11.0";
              src = sources.vectorcraft;
              cargoHash = "sha256-uJukhS4PxMGHgwpDK4pVWc45qvpMuBPFbANi7UrOAKo=";
              extraGuiBuildInputs = [ pkgs.gtk3 ]; # rfd
              description = "VectorCraft — clean-room Illustrator-style vector editor";
            };
            filmcraft = {
              version = "0.8.0";
              src = sources.filmcraft;
              cargoHash = "sha256-xjyTr6HPvaO6tndE+1Icgs6HCx96I5a2zQfAYpqPE7U=";
              extraGuiBuildInputs = [ pkgs.gtk3 pkgs.alsa-lib ]; # rfd
              description = "FilmCraft — clean-room Premiere-style video editor";
            };
            effectcraft = {
              version = "0.10.0";
              src = sources.effectcraft;
              cargoHash = "sha256-Ag4H+W8IPcgTXi/GAYpeDV2qGBYr7sth2uD+QwckTek=";
              extraGuiBuildInputs = [ pkgs.gtk3 pkgs.alsa-lib ]; # rfd
              description = "EffectCraft — clean-room After Effects-style motion graphics";
            };
            soundcraft = {
              version = "0.7.0";
              src = sources.soundcraft;
              cargoHash = "sha256-E6TBJJMjLX2D5DvzSdy5HPxhSq2IG+rz2VtD2wkN+dQ=";
              extraGuiBuildInputs = [ pkgs.gtk3 pkgs.alsa-lib ]; # rfd
              description = "SoundCraft — clean-room Pro Tools-style audio workstation";
            };
            deckcraft = {
              version = "0.7.0";
              src = sources.deckcraft;
              cargoHash = "sha256-Ba2jD5qyRZKHz8Lf9LMstNg5iGeumytchZBPycVVwv0=";
              extraGuiBuildInputs = [ pkgs.gtk3 pkgs.alsa-lib ]; # rfd
              description = "DeckCraft — clean-room PowerPoint-style presentations";
            };
            designcraft = {
              version = "0.8.0";
              src = sources.designcraft;
              cargoHash = "sha256-8OMM2snZMshErMH8zvix3mEYnBe+qTAQ1O+pCVANnDw=";
              extraGuiBuildInputs = [ pkgs.gtk3 ]; # rfd
              description = "DesignCraft — clean-room InDesign-style page layout";
            };
            lightcraft = {
              version = "0.8.0";
              src = sources.lightcraft;
              cargoHash = "sha256-HVnm2Ziy2WB8y3eLWEU/oXS36bvWI6zuDlTJ0BPfOtE=";
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
