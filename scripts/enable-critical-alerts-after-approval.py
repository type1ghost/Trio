#!/usr/bin/env python3
"""Use only AFTER Apple approves Critical Alerts for the existing Trio App ID.
Minimal change; preserves Trio dev alert logic and notification permission callbacks.
"""
from pathlib import Path
import plistlib

root = Path(__file__).resolve().parents[1]
ent = root / 'Trio/Resources/Trio.entitlements'
notif = root / 'Trio/Sources/Services/UserNotifications/UserNotificationsManager.swift'
if not ent.exists() or not notif.exists():
    raise SystemExit('Run within a full Trio dev checkout; expected files missing.')
e = plistlib.loads(ent.read_bytes())
k = 'com.apple.developer.usernotifications.critical-alerts'
if e.get(k) is not True:
    e[k] = True
    ent.write_bytes(plistlib.dumps(e, sort_keys=False))
    print('Added entitlement to Trio.entitlements')
else:
    print('Entitlement already present')
source = notif.read_text()
old = 'options: [.badge, .sound, .alert]'
new = 'options: [.badge, .sound, .alert, .criticalAlert]'
if old in source:
    notif.write_text(source.replace(old, new, 1))
    print('Added .criticalAlert to notification authorization options')
elif new in source:
    print('.criticalAlert permission already requested')
else:
    raise SystemExit('Notification authorization call differs from verified upstream dev; inspect manually')
print('NEXT: verify approval and regenerate the affected provisioning profile, then test on device.')
