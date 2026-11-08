#!/usr/bin/env perl
#
# Neutralise a Craft app's desktop STARTUP update check.
#
# WHY
# ---
# Since ~v0.16 every Craft app links `craft-update` (a git dep on
# storytold/craft-libs) and, on desktop start, spawns an "update-check"
# thread that GETs api.github.com and raises an "Update and Restart" prompt.
# Accepting that prompt replaces the binary OUTSIDE the Nix store: an
# unmanaged, unreviewed binary wearing a Nix path, which is exactly the
# runtime drift our pinning policy exists to prevent.
#
# Upstream offers no env-var off-switch. The only one, CRAFT_VERSIONS_FILE,
# belongs to the ArtCraft launcher we do not run. So the call is removed at
# the app's own call site.
#
# User decision 2026-11-07: "patch the startup check off in mkCraft".
#
# FAIL-LOUD BY DESIGN
# -------------------
# The setter name differs per app and has already drifted across releases
# (enable_update_check / enable_update_checks / set_startup_update_check /
# start_update_check / a `check_updates: Some(..)` service field). A patch
# that silently matched nothing would quietly re-enable the beacon on the
# next bump -- the worst possible failure mode for a security control. So:
#
#   * 0 matches found  -> die. The upstream call site moved or was renamed.
#   * still enabled    -> die. Some enabled form survived the rewrite.
#
# Either way the build breaks visibly instead of shipping a phone-home app.
#
# Comment lines are skipped for both detection and rewriting, so doc comments
# that merely mention these names neither trigger a false positive nor get
# corrupted.
#
# Usage: disable-startup-update-check.pl <app-name>
#   e.g. disable-startup-update-check.pl cadcraft

use strict;
use warnings;
use File::Find qw(find);

my ($app) = @ARGV;
defined $app and length $app
    or die "usage: $0 <app-name>\n";

my $root = "apps/$app/src";
-d $root or die "ERROR: craft '$app': source dir '$root' not found\n";

my @files;
find(sub { push @files, $File::Find::name if -f && /\.rs$/ }, $root);
@files or die "ERROR: craft '$app': no .rs files under $root\n";

# Void-style startup checks: `recv.enable_update_check();` and friends.
# Handled by deleting the whole statement, so no dangling receiver is left.
my $VOID_METHOD = qr/(?:enable_update_checks?|start_update_check)/;

# Forms that mean "this app checks for updates at startup". Used for both
# detection and the residual check. The negative lookahead keeps an
# already-disabled `set_startup_update_check(false)` from counting as a match.
my @enabled = (
    qr/\.set_startup_update_check\s*\(\s*(?!false\b)/,
    qr/\.\s*$VOID_METHOD\s*\(\s*\)/,
    qr/check_updates\s*:\s*Some\s*\(/,
);

# A line is a comment if, ignoring leading whitespace, it opens with a line
# comment, a block-comment opener, or a block-comment continuation bar.
sub is_comment {
    my ($line) = @_;
    return $line =~ m{^\s*(?://|/\*|\*)};
}

# A void-style call we may delete only when it is the WHOLE statement. If it
# is chained (`a.b().enable_update_check();`) we must not guess -- leave it
# and let the residual check fail the build loudly.
sub whole_line_void {
    my ($line) = @_;
    return $line =~ m{^\s*[\w.:]+\s*\.\s*$VOID_METHOD\s*\(\s*\)\s*;\s*$};
}

my $neutralised = 0;
my @touched;

for my $file (@files) {
    open my $in, '<', $file or die "ERROR: craft '$app': cannot read $file: $!\n";
    my @lines = <$in>;
    close $in;

    my @out;
    my $file_changed = 0;

    for my $line (@lines) {
        if (!is_comment($line)) {
            my $was_enabled = 0;
            for my $re (@enabled) {
                if ($line =~ $re) { $was_enabled = 1; last; }
            }

            if ($was_enabled) {
                my $before = $line;

                if (whole_line_void($line)) {
                    # Drop the entire statement.
                    $neutralised++;
                    $file_changed = 1;
                    next;
                }

                # Replace the argument with a literal false rather than
                # deleting the call, so the setter contract is unchanged and
                # no surrounding expression is left dangling. Handles both
                # `set_startup_update_check(true)` and the nested effectcraft
                # form `set_startup_update_check(startup_update_check(port))`.
                $line =~ s{\.set_startup_update_check\s*\(\s*[^()]*(?:\([^()]*\)[^()]*)*\)}
                          {.set_startup_update_check(false)};

                # photocraft wires the check as a service field: Some(..) -> None.
                $line =~ s/check_updates\s*:\s*Some\s*\(\s*crate::updates::service\s*\(\s*\)\s*\)/check_updates: None/g;

                # Residual check, same pass: if an enabled form is still on
                # this line, the rewrite did not cover it.
                for my $re (@enabled) {
                    if ($line =~ $re) {
                        die "ERROR: craft '$app': a startup update-check call SURVIVED the patch\n",
                            "  $file:\n",
                            "    before: $before",
                            "    after:  $line",
                            "  The rewrite does not cover this form. Extend this\n",
                            "  script before building -- this app would still\n",
                            "  phone home at startup.\n";
                    }
                }

                $neutralised++ if $line ne $before;
                $file_changed = 1 if $line ne $before;
            }
        }

        push @out, $line;
    }

    if ($file_changed) {
        open my $o, '>', $file or die "ERROR: craft '$app': cannot write $file: $!\n";
        print {$o} @out;
        close $o;
        push @touched, $file;
    }
}

if ($neutralised == 0) {
    die "ERROR: craft '$app': found NO startup update-check call under $root.\n",
        "       The upstream call site has moved or been renamed, so this\n",
        "       disable patch did NOTHING and the app may still phone home at\n",
        "       startup. Locate the new call site and extend this script.\n",
        "       (Known forms: set_startup_update_check / enable_update_check(s) /\n",
        "        start_update_check / check_updates: Some(...))\n";
}

print "craft '$app': startup update check DISABLED ",
      "($neutralised call(s) neutralised in ", scalar(@touched), " file(s))\n";
