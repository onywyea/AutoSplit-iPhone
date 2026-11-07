"""Bake selection thumbnails with Apple's compiler from the actual .icon layers.

Alternate Icon Composer icons may live only in Assets.car, so UIImage(named:)
cannot load their Home Screen fallbacks. Compile each as primary in a temporary
output directory, and copy its PNG fallback under a separate preview filename.
This leaves the app's generated CFBundleIcons metadata untouched.
"""
from pathlib import Path
import argparse
import subprocess
import tempfile
import shutil
import json
from concurrent.futures import ThreadPoolExecutor

parser = argparse.ArgumentParser()
parser.add_argument('--platform', choices=['iphoneos', 'iphonesimulator'], required=True)
parser.add_argument('--app', type=Path, required=True)
args = parser.parse_args()
assert args.app.is_dir(), args.app
names = ['ScanFlowIcon', 'ScanFlowPearl', 'ScanFlowGraphite', 'ScanFlowClassic'] + [i['name'] for i in json.loads(Path('AutoSplit/IconCollection.json').read_text())]
def render(name):
    artwork = Path('AutoSplit') / (name + '.icon') / 'Assets/Artwork.png'
    if artwork.is_file():
        destination = args.app / ('IconPreview-' + name + '.png')
        subprocess.run(['sips', '-z', '180', '180', str(artwork), '--out', str(destination)], check=True, stdout=subprocess.DEVNULL)
        assert destination.stat().st_size > 1000
        print(f'{name}: exact artwork preview', flush=True)
        return
    with tempfile.TemporaryDirectory(prefix='scanflow-icon-') as folder:
        out = Path(folder)
        command = ['xcrun', '--sdk', args.platform, 'actool',
                   str(Path('AutoSplit') / (name + '.icon')),
                   '--compile', str(out), '--app-icon', name,
                   '--platform', args.platform, '--target-device', 'iphone',
                   '--minimum-deployment-target', '17.0',
                   '--output-partial-info-plist', str(out / 'partial.plist'),
                   '--output-format', 'human-readable-text', '--compress-pngs']
        result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if result.returncode:
            print(result.stdout)
            raise SystemExit(result.returncode)
        candidates = sorted(out.glob(name + '*60x60*.png'))
        assert candidates, f'{name}: actool did not produce a PNG fallback: {list(out.iterdir())}'
        destination = args.app / ('IconPreview-' + name + '.png')
        shutil.copyfile(candidates[-1], destination)
        assert destination.stat().st_size > 1000, destination
        print(f'{name}: native preview, {destination.stat().st_size} bytes', flush=True)

with ThreadPoolExecutor(max_workers=2) as workers:
    list(workers.map(render, names))
