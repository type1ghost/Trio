#!/usr/bin/env python3
"""Fail closed if a signed Trio IPA lacks Apple's Critical Alerts entitlement."""
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import zipfile

KEY = 'com.apple.developer.usernotifications.critical-alerts'

def cmd(*args):
    return subprocess.check_output(args, stderr=subprocess.DEVNULL)

def main(ipa_file):
    ipa = Path(ipa_file)
    if not ipa.is_file() or ipa.stat().st_size == 0:
        raise RuntimeError(f'IPA is missing or empty: {ipa}')
    with tempfile.TemporaryDirectory(prefix='trio-entitlement-') as tmp:
        with zipfile.ZipFile(ipa) as zipf:
            zipf.extractall(tmp)
        app = Path(tmp) / 'Payload' / 'Trio.app'
        if not app.exists():
            raise RuntimeError('Trio.app not found in IPA')
        subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
        signed = plistlib.loads(cmd('codesign', '-d', '--entitlements', ':-', str(app)))
        profile_file = app / 'embedded.mobileprovision'
        if not profile_file.exists():
            raise RuntimeError('embedded.mobileprovision not found')
        profile = plistlib.loads(cmd('security', 'cms', '-D', '-i', str(profile_file)))
        if signed.get(KEY) is not True:
            raise RuntimeError('Signed Trio.app lacks approved Critical Alerts entitlement')
        if profile.get('Entitlements', {}).get(KEY) is not True:
            raise RuntimeError('Provisioning profile lacks Apple Critical Alerts entitlement')
        print('PASS: Critical Alerts entitlement is present in both app signature and profile')
if __name__ == '__main__':
    try:
        main(sys.argv[1] if len(sys.argv) > 1 else 'Trio.ipa')
    except Exception as exc:
        print(f'FAIL: {exc}', file=sys.stderr)
        sys.exit(1)
