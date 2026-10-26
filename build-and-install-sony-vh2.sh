#!/usr/bin/env bash
# Build the launcher APK via GitHub Actions (because this machine is ARM64
# and the Android SDK's aapt2 is x86-64 only) and install it on the TV.
# Run from ~/Projects/cleanyourtv/
set -euo pipefail

TV_HOST="${TV_HOST:-10.44.0.96}"
FORK_REPO="tko76/cleanyourtv"
BRANCH="sony-vh2-setup"

echo "==> Committing config changes..."
cd "$(dirname "$0")"
git add launcher/app/src/main/res/values/config.xml
if ! git diff --cached --quiet; then
    git commit -m "Update launcher config"
    git push fork "$BRANCH"
else
    echo "No config changes to commit."
fi

echo "==> Triggering GitHub Actions build..."
RUN_ID=$(gh run list --repo "$FORK_REPO" --branch "$BRANCH" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || echo "")
# Wait for a fresh run (push triggers it automatically)
sleep 5
NEW_RUN_ID=$(gh run list --repo "$FORK_REPO" --branch "$BRANCH" --limit 1 --json databaseId -q '.[0].databaseId')
echo "Waiting for run $NEW_RUN_ID..."
gh run watch --repo "$FORK_REPO" "$NEW_RUN_ID"

echo "==> Downloading APK..."
mkdir -p /tmp/launcher-apk
gh run download --repo "$FORK_REPO" "$NEW_RUN_ID" --name launcher-release --dir /tmp/launcher-apk

echo "==> Pushing to TV..."
TV_HOST="$TV_HOST" .venv/bin/python tools/b64push.py /tmp/launcher-apk/app-release.apk /data/local/tmp/launcher.apk

echo "==> Installing..."
adb -s "$TV_HOST:5555" shell pm install -r /data/local/tmp/launcher.apk

echo "==> Done. APK installed."
