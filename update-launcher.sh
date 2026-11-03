#!/usr/bin/env bash
# update-launcher.sh
# Pulls the latest upstream cleanyourtv, rebases your customisations on top,
# builds via GitHub Actions, installs the launcher and any apps in APK_REGISTRY
# on one or more TVs.
#
# Usage (from ~/Projects/cleanyourtv):
#   ./update-launcher.sh                  — all TVs, skip apps already installed
#   ./update-launcher.sh --all            — same
#   ./update-launcher.sh --sony           — Sony only
#   ./update-launcher.sh --tcl            — TCL only
#   ./update-launcher.sh --sony --tcl     — multiple TVs
#   ./update-launcher.sh --update-apps    — re-install apps even if already present
#
# Adding a TV:  add one line to TV_REGISTRY below.
# Adding an app: add one line to APK_REGISTRY below.
#
# Requirements: git, gh (GitHub CLI, logged in), adb, tools/venv set up.
set -euo pipefail
cd "$(dirname "$0")"

# ── TV registry ────────────────────────────────────────────────────────────────
# Format:  "name:ip:theme_path"
# theme_path relative to this repo; leave blank to skip theme push.
TV_REGISTRY=(
    "sony65:10.44.0.96:themes/ruska"
    "tcl:10.44.0.98:examples/tcl-g03-google-tv"
    "sony75:10.44.0.87:themes/ruska"
)

# ── APK registry ───────────────────────────────────────────────────────────────
# Format:  "name:package:source"
#
# source formats:
#   github:owner/repo               — latest GitHub release, first .apk asset
#   github:owner/repo:pattern       — latest release, asset whose name contains pattern
#   url:https://example.com/app.apk — direct download (curl)
#   file:~/path/to/app.apk          — local file (path expanded)
#
# Apps are skipped when already installed unless --update-apps is passed.
APK_REGISTRY=(
    "nuvio:com.nuvio.tv:github:NuvioMedia/NuvioTV"
    "smarttube:org.smarttube.stable:github:yuliskov/SmartTube:universal"
    "janky:com.player.janky:github:jankyapp/jankyapp"
    # "downloader:com.esaba.downloader:file:apps/downloader.apk"
)
# ──────────────────────────────────────────────────────────────────────────────

FORK=tko76/cleanyourtv
BRANCH=sony-vh2-setup
PY=tools/venv/bin/python
UPDATE_APPS=0

# Parse arguments.
declare -A WANTED
WANT_ALL=1
for arg in "$@"; do
    if [ "$arg" = "--update-apps" ]; then
        UPDATE_APPS=1
    else
        WANTED["${arg#--}"]=1
        WANT_ALL=0
    fi
done

# Resolve target TVs.
TARGETS=()
for entry in "${TV_REGISTRY[@]}"; do
    name="${entry%%:*}"; rest="${entry#*:}"; ip="${rest%%:*}"; theme="${rest#*:}"
    if [ "$WANT_ALL" -eq 1 ] || [ "${WANTED[$name]+set}" = set ]; then
        TARGETS+=("$name:$ip:$theme")
    fi
done

if [ ${#TARGETS[@]} -eq 0 ]; then
    echo "No matching TVs. Available:$(printf ' --%s' $(printf '%s\n' "${TV_REGISTRY[@]}" | cut -d: -f1))"
    exit 1
fi
echo "==> TVs: $(printf '%s ' "${TARGETS[@]}" | sed 's/:[^:]*:[^ ]*//g')"

# ── Git update ─────────────────────────────────────────────────────────────────
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "==> Committing local changes..."
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
if ! GIT_EDITOR=true git rebase main -Xours; then
    echo "ERROR: rebase conflict. Run: git status"
    echo "Fix, then: git add <file> && git rebase --continue"
    echo "Or abort:  git rebase --abort"
    exit 1
fi

echo "==> Pushing to fork..."
git push fork "$BRANCH" --force-with-lease

# ── Build launcher ─────────────────────────────────────────────────────────────
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

TMPDIR=/tmp/launcher-update-$$
mkdir -p "$TMPDIR/launcher"
gh run download --repo "$FORK" "$RUN_ID" --name launcher-release --dir "$TMPDIR/launcher"

# ── Resolve APK sources ────────────────────────────────────────────────────────
# Downloads each APK once to TMPDIR; records the local path per registry name.
declare -A APK_PATHS   # name → local apk path
declare -A APK_PKGS    # name → package id

for entry in "${APK_REGISTRY[@]}"; do
    [[ "$entry" =~ ^[[:space:]]*# ]] && continue   # skip commented lines
    apk_name="${entry%%:*}"
    rest="${entry#*:}"
    apk_pkg="${rest%%:*}"
    apk_src="${rest#*:}"
    APK_PKGS["$apk_name"]="$apk_pkg"

    src_type="${apk_src%%:*}"
    src_val="${apk_src#*:}"

    dest="$TMPDIR/apps/${apk_name}.apk"
    mkdir -p "$TMPDIR/apps"

    case "$src_type" in
        github)
            owner_repo="${src_val%%:*}"
            pattern="${src_val#*:}"
            [ "$pattern" = "$src_val" ] && pattern=".apk"   # no pattern given
            echo "==> [app:$apk_name] Fetching latest release from github:$owner_repo (pattern: $pattern)..."
            dl_url=$(gh api "repos/$owner_repo/releases/latest" \
                --jq ".assets[] | select(.name | test(\"$(printf '%s' "$pattern" | sed 's/\./\\./g')\")) | .browser_download_url" \
                2>/dev/null | head -1 || true)
            if [ -z "$dl_url" ]; then
                echo "    WARNING: no matching asset found for $apk_name — skipping."
                continue
            fi
            curl -fsSL "$dl_url" -o "$dest"
            ;;
        url)
            echo "==> [app:$apk_name] Downloading from $src_val..."
            curl -fsSL "$src_val" -o "$dest"
            ;;
        file)
            # Relative paths resolve from repo root (the script cd's there at startup).
            local_path="${src_val/#\~/$HOME}"
            [[ "$local_path" != /* ]] && local_path="$(pwd)/$local_path"
            if [ ! -f "$local_path" ]; then
                echo "    WARNING: local file not found: $local_path — skipping $apk_name."
                continue
            fi
            cp "$local_path" "$dest"
            ;;
        *)
            echo "    WARNING: unknown source type '$src_type' for $apk_name — skipping."
            continue
            ;;
    esac
    APK_PATHS["$apk_name"]="$dest"
    echo "    [app:$apk_name] Ready."
done

# ── Install function ───────────────────────────────────────────────────────────
install_tv() {
    local name=$1 ip=$2 theme=$3

    echo ""
    echo "==> [$name] Connecting to $ip..."
    adb connect "$ip:5555" 2>/dev/null || true

    # Launcher
    echo "    [$name] Installing launcher..."
    if adb -s "$ip:5555" shell pm install -r /data/local/tmp/launcher.apk 2>&1 | grep -q "Success"; then
        echo "    [$name] Launcher updated in-place."
    else
        "$PY" -I tools/b64push.py "$TMPDIR/launcher/app-release.apk" /data/local/tmp/launcher.apk
        adb -s "$ip:5555" shell pm uninstall com.gathin.tvhome 2>/dev/null || true
        adb -s "$ip:5555" shell pm install /data/local/tmp/launcher.apk
        adb -s "$ip:5555" shell \
            "settings put secure enabled_accessibility_services com.gathin.tvhome/.HomeKeyService; \
             settings put secure accessibility_enabled 1"
        echo "    [$name] Launcher installed fresh."
    fi

    # Theme
    if [ -n "$theme" ]; then
        echo "    [$name] Applying theme: $theme"
        TV_HOST="$ip" tools/theme.sh "$theme"
    fi

    # Apps
    for apk_name in "${!APK_PATHS[@]}"; do
        local_apk="${APK_PATHS[$apk_name]}"
        pkg="${APK_PKGS[$apk_name]}"

        already=$(adb -s "$ip:5555" shell pm list packages "$pkg" 2>/dev/null | grep -c "^package:$pkg$" || true)
        if [ "$already" -gt 0 ] && [ "$UPDATE_APPS" -eq 0 ]; then
            echo "    [$name] $apk_name already installed — skipping (use --update-apps to reinstall)."
            continue
        fi

        echo "    [$name] Installing $apk_name ($pkg)..."
        "$PY" -I tools/b64push.py "$local_apk" "/data/local/tmp/${apk_name}.apk"
        adb -s "$ip:5555" shell pm install -r "/data/local/tmp/${apk_name}.apk" && \
            echo "    [$name] $apk_name installed." || \
            echo "    [$name] WARNING: $apk_name install failed."
    done
}

# Push launcher APK to all TVs first (one upload per TV happens inside install_tv)
for target in "${TARGETS[@]}"; do
    name="${target%%:*}"; rest="${target#*:}"; ip="${rest%%:*}"; theme="${rest#*:}"
    # Pre-push launcher so it's ready before install_tv tries pm install -r
    adb connect "$ip:5555" 2>/dev/null || true
    "$PY" -I tools/b64push.py "$TMPDIR/launcher/app-release.apk" /data/local/tmp/launcher.apk 2>/dev/null || true
done

for target in "${TARGETS[@]}"; do
    name="${target%%:*}"; rest="${target#*:}"; ip="${rest%%:*}"; theme="${rest#*:}"
    install_tv "$name" "$ip" "$theme"
done

rm -rf "$TMPDIR"
echo ""
echo "Done."
