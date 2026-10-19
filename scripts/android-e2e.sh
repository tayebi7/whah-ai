#!/usr/bin/env bash
set -u
node scripts/mock-provider.mjs > /tmp/mock.log 2>&1 &
adb install -r waha-ai.apk
adb shell am start -n ai.waha.app/.MainActivity
sleep 12
node scripts/android-e2e.mjs
code=$?
echo "--- mock provider saw ---"; tail -20 /tmp/mock.log
exit $code
