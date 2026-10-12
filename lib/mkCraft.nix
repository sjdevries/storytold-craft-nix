# Shared builder for the storytold craft apps.
#
# Every craft repo shares the same layout:
#   apps/<name>       — desktop GUI (eframe / wgpu / winit)
#   apps/<name>-cli   — headless CLI (no graphics system deps)
#   apps/<name>-web   — wasm target (not built here)
#
# This builds the GUI + CLI from a pinned source. The CLI needs no system
# libraries; the GUI needs the X11/Wayland/Vulkan/font stack, plus per-app
# extras (GTK3 for rfd file dialogs, systemd/libudev for hidapi).
#
# Fonts: pass `withFonts = true` + a `craftFontsSrc` (a storytold/craft-fonts
# checkout) to embed the fonts via CRAFT_FONTS_DIR, exactly like the upstream
# release workflow. Without it the build is "fontless" — everything works but
# some scripts (CJK, etc.) have no glyphs.
#
# To contribute a package upstream to a craft repo, copy the relevant
# `buildRustPackage` into that repo's root flake with `src = ./.` instead
# of a fetchGit source.
{ pkgs }:
{ name
, version
, src
, cargoHash
, extraGuiBuildInputs ? [ ]
, description ? name
, withFonts ? false
, craftFontsSrc ? null
, rustFlags ? null
}:
let
  inherit (pkgs) lib;

  # withFonts requires a source; fail clearly rather than silently building fontless.
  _ = lib.assertMsg (!withFonts || craftFontsSrc != null)
    "mkCraft: withFonts = true requires craftFontsSrc (a storytold/craft-fonts checkout)";

  # Common system libraries for the eframe/wgpu/winit GUI apps.
  guiBuildInputs = [
    pkgs.libx11
    pkgs.libxcursor
    pkgs.libxi
    pkgs.libxrandr
    pkgs.libxinerama
    pkgs.libxkbcommon
    pkgs.wayland
    pkgs.wayland-protocols
    pkgs.vulkan-loader
    pkgs.mesa
    pkgs.fontconfig
    pkgs.freetype
  ] ++ extraGuiBuildInputs;

  # Runtime libraries the wrapped binary must find (Vulkan ICD, GTK, udev, …).
  runtimeLibs = [
    pkgs.vulkan-loader
    pkgs.mesa
    pkgs.libxkbcommon
    pkgs.fontconfig
    pkgs.freetype
  ] ++ extraGuiBuildInputs;

  # Point build.rs at the craft-fonts checkout; fail the build on a malformed
  # font input rather than silently shipping without glyphs (matches upstream).
  fontEnv = lib.optionalAttrs withFonts {
    CRAFT_FONTS_DIR = toString craftFontsSrc;
    CRAFT_FONTS_REQUIRED = "1";
  };

  # Ship the SIL Open Font licences for the embedded fonts alongside the binary.
  fontLicenseInstall = lib.optionalString withFonts ''
    doc=$out/share/doc/${name}
    for lic in ${toString craftFontsSrc}/fonts/*/OFL.txt; do
      [ -f "$lic" ] && install -Dm644 "$lic" "$doc/OFL-$(basename "$(dirname "$lic")").txt"
    done
  '';

  baseMeta = {
    homepage = "https://github.com/storytold/${name}";
    license = with lib.licenses; [ mit asl20 ];
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
in
{
  # Headless CLI — no graphics system dependencies.
  cli = pkgs.rustPlatform.buildRustPackage {
    pname = "${name}-cli";
    inherit version src cargoHash;

    cargoBuildFlags = [ "-p" "${name}-cli" ];
    doCheck = false;

    nativeBuildInputs = [ pkgs.pkg-config ];
    env = fontEnv // lib.optionalAttrs (rustFlags != null) { RUSTFLAGS = rustFlags; };
    postInstall = fontLicenseInstall;

    meta = baseMeta // {
      description = "${description} — headless CLI${if withFonts then " (embedded fonts)" else ""}";
      mainProgram = "${name}-cli";
    };
  };

  # Desktop GUI — eframe/wgpu/winit + file dialogs + accessibility.
  gui = pkgs.rustPlatform.buildRustPackage {
    pname = name;
    inherit version src cargoHash;

    cargoBuildFlags = [ "-p" name ];
    doCheck = false;

    nativeBuildInputs = [ pkgs.pkg-config pkgs.makeWrapper ];
    buildInputs = guiBuildInputs;
    env = fontEnv // lib.optionalAttrs (rustFlags != null) { RUSTFLAGS = rustFlags; };

    # Make the runtime find the Vulkan ICD / GTK / udev regardless of the
    # caller's environment (NixOS provides these too, but be explicit).
    postInstall = ''
      wrapProgram $out/bin/${name} \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}"
    '' + fontLicenseInstall;

    meta = baseMeta // {
      description = "${description} — desktop GUI${if withFonts then " (embedded fonts)" else ""}";
      mainProgram = name;
    };
  };
}
