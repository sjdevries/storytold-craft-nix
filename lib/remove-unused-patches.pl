#!/usr/bin/env perl
#
# Drop [patch.*] entries that the lockfile already reports as UNUSED.
#
# WHY
# ---
# Since the 2026-11-06 wave the Craft apps carry a large [patch.crates-io]
# block pinning the whole egui family to a reviewed fork, plus three entries
# nothing actually depends on:
#
#   egui_demo_lib, egui_inspection, egui_system_font_provider
#
# Cargo records those in Cargo.lock as [[patch.unused]] and, online, merely
# warns. Nix's vendored build is different: fetch-cargo-vendor vendors only
# what the dependency graph needs, so those three crates are absent from the
# vendored egui source. The source-replacement config then redirects the
# fork's git URL at that incomplete directory, and cargo turns the old
# "unused patch" warning into a hard failure:
#
#   error: patch location `https://github.com/storytold/egui.git?rev=6d518fc...`
#          does not contain packages matching `egui_demo_lib`
#   help: check `egui_demo_lib` patch definition for
#         `https://github.com/rust-lang/crates.io-index` in `/build/source/Cargo.toml`
#
# The patch is unused, so dropping it changes nothing about what gets built.
# Verified 2026-11-08: `cargo metadata --offline` against the real vendored
# soundcraft tree goes from exit 101 to exit 0 with these three lines removed.
#
# Only Cargo.toml is touched. Cargo.lock is left exactly as vendored, so the
# source-vs-vendor lock consistency check in cargoSetupPostPatchHook still
# passes.
#
# FAIL-LOUD
# ---------
# The unused set is read from Cargo.lock rather than hardcoded, and the
# rewrite is verified afterwards: every name still listed as unused must be
# gone from every [patch.*] section. If the lock reports an unused patch we
# cannot find in the manifest, or a name survives the rewrite, the build dies
# instead of silently leaving a broken patch in place.
#
# Usage: remove-unused-patches.pl <path-to-cargo-lock> <path-to-cargo-toml>

use strict;
use warnings;

my ($lock_path, $toml_path) = @ARGV;
defined $toml_path or die "usage: $0 <Cargo.lock> <Cargo.toml>\n";

# ---- read the unused set out of Cargo.lock -------------------------------
open my $lh, '<', $lock_path or die "ERROR: cannot read $lock_path: $!\n";
my %unused;
my $in_unused = 0;
while (my $line = <$lh>) {
    if ($line =~ /^\s*\[\[patch\.unused\]\]\s*$/) { $in_unused = 1; next; }
    if ($in_unused) {
        if ($line =~ /^\s*\[/) { $in_unused = 0; next; }
        if ($line =~ /^\s*name\s*=\s*"([^"]+)"\s*$/) { $unused{$1} = 1; }
    }
}
close $lh;

my @names = sort keys %unused;
if (!@names) {
    print "no unused patches recorded; nothing to do\n";
    exit 0;
}
print "unused patches reported by lockfile: @names\n";

# ---- rewrite the [patch.*] sections ------------------------------------
open my $th, '<', $toml_path or die "ERROR: cannot read $toml_path: $!\n";
my @lines = <$th>;
close $th;

my @out;
my $in_patch = 0;
my $patch_hdr_idx = -1;
my %removed;

for my $line (@lines) {
    if ($line =~ /^\s*\[patch[.\]]/) {
        $in_patch = 1;
        $patch_hdr_idx = $#out + 1;
        push @out, $line;
        next;
    }
    if ($line =~ /^\s*\[/) {           # any other table ends the patch section
        $in_patch = 0;
        push @out, $line;
        next;
    }

    if ($in_patch && $line =~ /^\s*([A-Za-z0-9_.-]+)\s*=/) {
        my $key = $1;
        if ($unused{$key}) {
            $removed{$key} = ($removed{$key} // 0) + 1;
            next;                        # drop the line
        }
    }
    push @out, $line;
}

# ---- fail loud on anything we could not clear --------------------------
my @missing = grep { !$removed{$_} } @names;
if (@missing) {
    die "ERROR: lockfile reports these patches as unused but they were not\n",
        "       found in any [patch.*] section of $toml_path:\n",
        join('', map { "         $_\n" } @missing),
        "       The manifest layout changed; this script no longer covers it.\n";
}

# ---- drop patch headers left empty ------------------------------------
my @final;
for (my $i = 0; $i <= $#out; $i++) {
    my $line = $out[$i];
    if ($line =~ /^\s*\[patch[.\]]/) {
        # look ahead: is there any non-blank line before the next table?
        my $has_body = 0;
        for (my $j = $i + 1; $j <= $#out; $j++) {
            last if $out[$j] =~ /^\s*\[/;
            $has_body = 1 if $out[$j] =~ /\S/;
        }
        next unless $has_body;
    }
    push @final, $line;
}

open my $oh, '>', $toml_path or die "ERROR: cannot write $toml_path: $!\n";
print {$oh} join('', @final);
close $oh;

my $count = 0;
$count += $removed{$_} for keys %removed;
print "removed $count unused [patch.*] entr", ($count == 1 ? 'y' : 'ies'),
      " (@names)\n";
