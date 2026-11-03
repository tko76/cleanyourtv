#!/usr/bin/env bash
# update-launcher.sh
# Pulls the latest upstream cleanyourtv, rebases your Sony VH2 customisations on top,
# builds via GitHub Actions, and installs on the Sony (10.44.0.96) and optionally the TCL (10.44.0.98).
#
# Usage (from ~/Projects/cleanyourtv):
#   ./update-launcher.sh            — Sony only
#   ./update-launcher.sh --both     — Sony + TCL
#   ./update-launcher.sh --sony     — Sony only (explicit)
#
# Requirements: git, gh (GitHub CLI, already logged in), adb, tools/venv active.
set -euo pipefail
cd "$(dirname "$0")"

SONY=10.44.0.96
TCL=10.44.0.98
FORK=tko76/cleanyourtv
BRANCH=sony-vh2-setup
PY=tools/venv/bin/python

INSTALL_TCL=0
for arg in "$@"; do
    [ "$arg" = --both ] && INSTALL_TCL=1
done

echo "==> Fetching upstream..."
git fetch origin

echo "==> Updating main..."
git checkout main
git merge origin/main --ff-only

echo "==> Rebasing $BRANCH on main..."
git checkout "$BRANCH"
# -Xours: on conflict keep our version (dock config, theme files).
# Upstream launcher Java changes land cleanly; only config files might conflict.
if ! git rebase main -Xours; then
    echo ""
    echo "ERROR: rebase hit a conflict that -Xours couldn't auto-resolve."
    echo "Run: git status   to see which files need attention."
    echo "Fix them, then: git add <file> && git rebase --continue"
    echo "Or to start over: git rebase --abort"
    exit 1
fi

echo "==> Pushing to fork..."
git push fork "$BRANCH" --force-with-lease

echo "==> Waiting for GitHub Actions build..."
sleep 8
RUN_ID=$(gh run list --repo "$FORK" --limit 1 --json databaseId -q '.[0].databaseId')
echo "    Run $RUN_ID"
gh run watch --repo "$FORK" "$RUN_ID"
STATUS=$(gh run list --repo "$FORK" --limit 1 --json conclusion -q '.[0].conclusion')
if [ "$STATUS" != "success" ]; then
    echo "Build failed (status: $STATUS). Check: gh run view --repo $FORK $RUN_ID"
    exit 1
fi

echo "==> Downloading APK..."
mkdir -p /tmp/launcher-update-$$
gh run download --repo "$FORK" "$RUN_ID" --name launcher-release --dir /tmp/launcher-update-$$

install_tv() {
    local IP=$1
    echo "==> Installing on $IP..."
    adb connect "$IP:5555" 2>/dev/null || true
    "$PY" -I tools/b64push.py /tmp/launcher-update-$$/app-release.apk /data/local/tmp/launcher.apk
    if adb -s "$IP:5555" shell pm install -r /data/local/tmp/launcher.apk 2>&1 | grep -q "Success"; then
        echo "    Updated in-place."
    else
        echo "    Signature mismatch — uninstalling and reinstalling..."
        adb -s "$IP:5555" shell pm uninstall com.gathin.tvhome
        adb -s "$IP:5555" shell pm install /data/local/tmp/launcher.apk
        # Re-enable HomeKeyService after fresh install
        adb -s "$IP:5555" shell \
            "settings put secure enabled_accessibility_services com.gathin.tvhome/.HomeKeyService; \
             settings put secure accessibility_enabled 1"
        echo "    Installed fresh."
    fi
}

install_tv "$SONY"
[ "$INSTALL_TCL" -eq 1 ] && install_tv "$TCL"

rm -rf /tmp/launcher-update-$$
echo ""
echo "Done. Launcher updated."
echo "Re-apply your theme if needed:"
echo "  Sony: TV_HOST=$SONY tools/theme.sh themes/ruska"
[ "$INSTALL_TCL" -eq 1 ] && echo "  TCL:  TV_HOST=$TCL  tools/theme.sh examples/tcl-g03-google-tv"
