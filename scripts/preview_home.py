"""Capture the real native home screen with synthetic documents on a simulator."""
from pathlib import Path
import json
import os
import subprocess
import time


def run(*args):
    return subprocess.check_output(args, text=True).strip()

runtimes = json.loads(run('xcrun', 'simctl', 'list', 'runtimes', '-j'))['runtimes']
ios = [r for r in runtimes if r.get('isAvailable') and 'iOS' in r['name'] and r['version'].startswith('26.')]
assert ios, 'An installed iOS 26 simulator runtime is required'
runtime = sorted(ios, key=lambda r: tuple(map(int, r['version'].split('.'))))[-1]['identifier']
types = json.loads(run('xcrun', 'simctl', 'list', 'devicetypes', '-j'))['devicetypes']
device_type = next(t['identifier'] for t in types if t['name'] == 'iPhone 15 Pro')
device = run('xcrun', 'simctl', 'create', 'ScanFlow design preview', device_type, runtime)
try:
    subprocess.check_call(['xcrun', 'simctl', 'boot', device])
    subprocess.check_call(['xcrun', 'simctl', 'bootstatus', device, '-b'])
    subprocess.check_call(['xcrun', 'simctl', 'status_bar', device, 'override', '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100'])
    app = 'preview-build/Build/Products/Release-iphonesimulator/AutoSplit.app'
    subprocess.check_call(['xcrun', 'simctl', 'install', device, app])
    container = Path(run('xcrun', 'simctl', 'get_app_container', device, 'ua.autosplit.scanner', 'data'))
    root = container / 'Library/Application Support/ScanFlow-v2'
    subprocess.check_call(['swift', 'tests/PreviewFixtures.swift', str(root)])
    # Match the selected amber concept while retaining production color settings.
    preferences = container / 'Library/Preferences/ua.autosplit.scanner.plist'
    subprocess.check_call(['defaults', 'write', str(preferences), 'scanflow.studio.palette', '-string', 'gold'])
    subprocess.check_call(['xcrun', 'simctl', 'launch', device, 'ua.autosplit.scanner'])
    Path('design-preview').mkdir(exist_ok=True)
    def capture_ready(name):
        path = Path('design-preview') / name
        # A simulator cold launch can remain on a blank launch screen for >10s.
        # Synthetic document previews plus the real UI produce a much larger PNG.
        # Still inspect the captured image visually; this only rejects blank frames.
        for attempt in range(36):
            time.sleep(5)
            subprocess.check_call(['xcrun', 'simctl', 'io', device, 'screenshot', str(path)])
            if path.stat().st_size > 100_000:
                print(f'Nonblank capture: {name}, {path.stat().st_size} bytes', flush=True)
                return
            print(f'Waiting for app first frame: {attempt + 1}/36', flush=True)
        raise RuntimeError('The simulator did not render the application; blank screenshot rejected')
    capture_ready('home.png')
    subprocess.check_call(['xcrun', 'simctl', 'ui', device, 'content_size', 'accessibility-large'])
    capture_ready('home-large-text.png')
finally:
    subprocess.run(['xcrun', 'simctl', 'shutdown', device], check=False)
    subprocess.run(['xcrun', 'simctl', 'delete', device], check=False)
