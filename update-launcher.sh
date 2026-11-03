#!/usr/bin/env bash
# update-launcher.sh
# Pulls the latest upstream cleanyourtv, rebases your customisations on top,
# builds via GitHub Actions, and installs on one or more TVs.
#
# Usage (from ~/Projects/cleanyourtv):
#   ./update-launcher.sh                 — all TVs
#   ./update-launcher.sh --all           — all TVs (explicit)
#   ./update-launcher.sh --sony          — Sony BRAVIA 4K VH2 only
#   ./update-launcher.sh --tcl           — TCL G03 only
#   ./update-launcher.sh --sony --tcl    — multiple specific TVs
#
# Adding a new TV: add a line to the TV_REGISTRY section below, then use
# its --<name> flag.  The theme path is pushed after install; leave it
# empty ("") to skip the theme step for that TV.
#
# Requirements: git, gh (GitHub CLI, already logged in), adb, tools/venv set up.
set -euo pipefail
cd "$(dirname "$0")"

# ── TV registry ────────────────────────────────────────────────────────────────
# Format: "name:ip:theme_path"
# theme_path is relative to this repo; leave empty to skip theme push.
TV_REGISTRY=(
    "sony65:10.44.0.96:themes/ruska"
    "tcl:10.44.0.98:themes/ruska"
    "sony75:10.44.0.87:themes/ruska"
)
# ──────────────────────────────────────────────────────────────────────────────

FORK=tko76/cleanyourtv
BRANCH=sony-vh2-setup
PY=tools/venv/bin/python

# Parse arguments — collect requested TV names; default to all.
declare -A WANTED
WANT_ALL=1
for arg in "$@"; do
    name="${arg#--}"
    WANTED["$name"]=1
    WANT_ALL=0
done

# Resolve which TVs to install on.
TARGETS=()
for entry in "${TV_REGISTRY[@]}"; do
    name="${entry%%:*}"
    rest="${entry#*:}"
    ip="${rest%%:*}"
    theme="${rest#*:}"
    if [ "$WANT_ALL" -eq 1 ] || [ "${WANTED[$name]+set}" = set ]; then
        TARGETS+=("$name:$ip:$theme")
    fi
done

if [ ${#TARGETS[@]} -eq 0 ]; then
    echo "No matching TVs found. Available: $(printf ' --%s' $(printf '%s\n' "${TV_REGISTRY[@]}" | cut -d: -f1))"
    exit 1
fi

echo "==> TVs to update: $(printf '%s ' "${TARGETS[@]}" | sed 's/:[^:]*:[^ ]*//g')"

# ── Git update ─────────────────────────────────────────────────────────────────
# Commit any local edits (e.g. a new TV added to TV_REGISTRY) before switching branches.
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "==> Committing local changes before rebase..."
    git add -A
    GIT_EDITOR=true git commit -m "Local update ($(date '+%Y-%m-%d'))"
fi

echo "==> Fetching upstream..."
git fetch origin

echo "==> Updating main..."
git checkout main
git merge origin/main --ff-only

echo "==> Rebasing $BRANCH on main..."
git checkout "$BRANCH"
# -Xours keeps our config/theme files on conflict; upstream launcher Java changes
# land cleanly since we carry no custom Java after the Power Center revert.
if ! GIT_EDITOR=true git rebase main -Xours; then
    echo ""
    echo "ERROR: rebase hit a conflict -Xours could not auto-resolve."
    echo "  git status                        — see conflicted files"
    echo "  git add <file> && git rebase --continue"
    echo "  git rebase --abort                — start over"
    exit 1
fi

echo "==> Pushing to fork..."
git push fork "$BRANCH" --force-with-lease

# ── Build ──────────────────────────────────────────────────────────────────────
echo "==> Waiting for GitHub Actions build..."
sleep 8
RUN_ID=$(gh run list --repo "$FORK" --limit 1 --json databaseId -q '.[0].databaseId')
echo "    Run $RUN_ID"
gh run watch --repo "$FORK" "$RUN_ID"
STATUS=$(gh run list --repo "$FORK" --limit 1 --json conclusion -q '.[0].conclusion')
if [ "$STATUS" != "success" ]; then
    echo "Build failed ($STATUS). Check: gh run view --repo $FORK $RUN_ID"
    exit 1
fi

echo "==> Downloading APK..."
TMPDIR=/tmp/launcher-update-$$
mkdir -p "$TMPDIR"
gh run download --repo "$FORK" "$RUN_ID" --name launcher-release --dir "$TMPDIR"

# ── Install ────────────────────────────────────────────────────────────────────
install_tv() {
    local name=$1 ip=$2 theme=$3
    echo ""
    echo "==> [$name] Installing on $ip..."
    adb connect "$ip:5555" 2>/dev/null || true
    "$PY" -I tools/b64push.py "$TMPDIR/app-release.apk" /data/local/tmp/launcher.apk
    if adb -s "$ip:5555" shell pm install -r /data/local/tmp/launcher.apk 2>&1 | grep -q "Success"; then
        echo "    [$name] Updated in-place."
    else
        echo "    [$name] Signature mismatch — uninstalling and reinstalling..."
        adb -s "$ip:5555" shell pm uninstall com.gathin.tvhome
        adb -s "$ip:5555" shell pm install /data/local/tmp/launcher.apk
        adb -s "$ip:5555" shell \
            "settings put secure enabled_accessibility_services com.gathin.tvhome/.HomeKeyService; \
             settings put secure accessibility_enabled 1"
        echo "    [$name] Installed fresh (HomeKeyService re-enabled)."
    fi
    if [ -n "$theme" ]; then
        echo "    [$name] Applying theme: $theme"
        TV_HOST="$ip" tools/theme.sh "$theme"
    fi
}

for target in "${TARGETS[@]}"; do
    name="${target%%:*}"
    rest="${target#*:}"
    ip="${rest%%:*}"
    theme="${rest#*:}"
    install_tv "$name" "$ip" "$theme"
done

rm -rf "$TMPDIR"
echo ""
echo "Done."
