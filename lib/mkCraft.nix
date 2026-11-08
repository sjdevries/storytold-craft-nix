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
, metaDate ? "2026-10-12"
, rustPlatform ? pkgs.rustPlatform
, disableUpdateCheck ? true
}:
let
  inherit (pkgs) lib;

  # ---- Startup update check: DISABLED --------------------------------------
  #
  # Every Craft app since ~v0.16 links `craft-update` and, on desktop start,
  # spawns an "update-check" thread that GETs api.github.com and raises an
  # "Update and Restart" prompt. Accepting it replaces the binary OUTSIDE the
  # Nix store — an unmanaged, unreviewed binary wearing a Nix path, which is
  # exactly the runtime drift our pinning policy exists to prevent. Upstream
  # offers no env-var off-switch (the only one, CRAFT_VERSIONS_FILE, belongs
  # to the ArtCraft launcher we do not run), so the call is removed at the
  # app's own call site.
  #
  # User decision 2026-11-07: "patch the startup check off in mkCraft".
  #
  # The patch is FAIL-LOUD: it aborts the build if it finds nothing to patch,
  # or if an enabled form survives. A future bump that renames or adds a
  # startup call therefore breaks visibly instead of quietly re-enabling the
  # beacon. See lib/disable-startup-update-check.pl for the full rationale.
  #
  # Set `disableUpdateCheck = false` on an app ONLY if upstream genuinely
  # removes the startup check and you have confirmed that by reading the
  # source — never just to silence the error.
  updateCheckPatch = lib.optionalString disableUpdateCheck ''
    perl ${./disable-startup-update-check.pl} ${name}
  '';

  # ---- Unused [patch.*] entries: REMOVED ----------------------------------
  #
  # Since the 2026-11-06 wave the apps pin the whole egui family to a
  # reviewed fork via [patch.crates-io], and that block includes three
  # crates nothing actually depends on: egui_demo_lib, egui_inspection and
  # egui_system_font_provider. Cargo records them in Cargo.lock as
  # [[patch.unused]] and, online, merely warns.
  #
  # A vendored Nix build is not online. fetch-cargo-vendor vendors only what
  # the dependency graph needs, so those three crates are absent from the
  # vendored egui source; the source-replacement config then redirects the
  # fork's git URL at that incomplete directory and cargo turns the old
  # warning into a hard failure at build time:
  #
  #   error: patch location `https://github.com/storytold/egui.git?rev=6d518fc...`
  #          does not contain packages matching `egui_demo_lib`
  #   help: check `egui_demo_lib` patch definition for
  #         `https://github.com/rust-lang/crates.io-index` in `/build/source/Cargo.toml`
  #
  # The patch is unused, so dropping it changes nothing about what gets
  # built. Verified 2026-11-08: `cargo metadata --offline` against the real
  # vendored soundcraft tree goes exit 101 -> exit 0 with the three lines
  # removed. Only Cargo.toml is edited; Cargo.lock is left exactly as
  # vendored so the source-vs-vendor lock check still passes.
  #
  # The unused set is read from Cargo.lock rather than hardcoded, and the
  # rewrite is verified afterwards, so a manifest that drifts breaks the
  # build instead of leaving a broken patch in place.
  #
  # Runs unconditionally: unlike the update-check patch this is not a
  # policy switch, it is what makes a vendored build of these manifests
  # possible at all.
  unusedPatchPatch = ''
    perl ${./remove-unused-patches.pl} Cargo.lock Cargo.toml
  '';

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
  # `wayland` is required here even though the binary isn't linked against it:
  # winit dlopens libwayland-client.so at runtime, and without it on the path
  # a Wayland session fails with `NoWaylandLib` (seen on gridcraft).
  runtimeLibs = [
    pkgs.wayland
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

  # Desktop integration: install the source's own packaging/linux/ files + the
  # hicolor icon tree, matching the upstream package.sh FHS staging. This is
  # what makes the app appear in the KDE/GNOME application menu with its icon
  # and DXF/DWG file associations. (The CLI gets no desktop entry.)
  # The source ships these under the reverse-DNS id ai.storyteller.<app>.
  appId = "ai.storyteller.${name}";
  desktopIntegration = ''
    install -Dm644 ${src}/packaging/linux/${appId}.desktop \
      $out/share/applications/${appId}.desktop
    install -Dm644 ${src}/packaging/linux/${appId}.mime.xml \
      $out/share/mime/packages/${appId}.xml
    install -Dm644 ${src}/packaging/linux/${appId}.metainfo.xml.in \
      $out/share/metainfo/${appId}.metainfo.xml
    substituteInPlace $out/share/metainfo/${appId}.metainfo.xml \
      --replace '@VERSION@' '${version}' \
      --replace '@DATE@' '${metaDate}'
    mkdir -p $out/share/icons
    cp -R ${src}/assets/app-icon/hicolor $out/share/icons/
  '';

  baseMeta = {
    homepage = "https://github.com/storytold/${name}";
    license = with lib.licenses; [ mit asl20 ];
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
in
{
  # Headless CLI — no graphics system dependencies.
  cli = rustPlatform.buildRustPackage {
    pname = "${name}-cli";
    inherit version src cargoHash;

    cargoBuildFlags = [ "-p" "${name}-cli" ];
    doCheck = false;

    nativeBuildInputs = [ pkgs.pkg-config pkgs.perl ];
    env = fontEnv // lib.optionalAttrs (rustFlags != null) { RUSTFLAGS = rustFlags; };
    postPatch = updateCheckPatch + unusedPatchPatch;
    postInstall = fontLicenseInstall;

    meta = baseMeta // {
      description = "${description} — headless CLI${if withFonts then " (embedded fonts)" else ""}";
      mainProgram = "${name}-cli";
    };
  };

  # Desktop GUI — eframe/wgpu/winit + file dialogs + accessibility.
  gui = rustPlatform.buildRustPackage {
    pname = name;
    inherit version src cargoHash;

    cargoBuildFlags = [ "-p" name ];
    doCheck = false;

    nativeBuildInputs = [ pkgs.pkg-config pkgs.makeWrapper pkgs.perl ];
    buildInputs = guiBuildInputs;
    env = fontEnv // lib.optionalAttrs (rustFlags != null) { RUSTFLAGS = rustFlags; };

    # Neutralise the upstream startup update check, then drop the unused
    # [patch.*] entries, before the build sees either.
    postPatch = updateCheckPatch + unusedPatchPatch;

    # Make the runtime find the Vulkan ICD / GTK / udev regardless of the
    # caller's environment (NixOS provides these too, but be explicit).
    postInstall = ''
      wrapProgram $out/bin/${name} \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}"
    '' + desktopIntegration + fontLicenseInstall;

    meta = baseMeta // {
      description = "${description} — desktop GUI${if withFonts then " (embedded fonts)" else ""}";
      mainProgram = name;
    };
  };
}
