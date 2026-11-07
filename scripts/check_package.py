"""Package checks only; iOS build is performed separately on the macOS runner."""
from pathlib import Path
import json
root=Path(__file__).resolve().parents[1]
required=['App','Models','Store','Scanner','Rules','Imaging','Pipeline','CropEditor','Camera','Handoff','PaperEdges','LiveText','CleanupEditor','PageBrowser','DocumentPager','ImageLoading','PDFExport','OriginalsExport','Design','DocumentWorkspace','LibraryComponents','Theme','AppearanceControls','GalleryImport','ScanAccent','CameraFocusControls','RimSeal','Orientation']
for name in required:
    assert (root/'AutoSplit'/f'{name}.swift').is_file(),name
asset=root/'AutoSplit/Assets.xcassets/AppIcon.appiconset'
assert (asset/'AppIcon.png').is_file()
assert json.loads((asset/'Contents.json').read_text())['images'][0]['filename']=='AppIcon.png'
assert (root/'.github/workflows/build.yml').is_file()
assert 'ua.autosplit.scanner' in (root/'project.yml').read_text()
assert 'CURRENT_PROJECT_VERSION: 39' in (root/'project.yml').read_text()
print('Package files, asset catalog and upgrade bundle identifier: OK')

icon=root/'AutoSplit/ScanFlowIcon.icon'
manifest=json.loads((icon/'icon.json').read_text())
for group in manifest['groups']:
    for layer in group['layers']:
        assert (icon/'Assets'/layer['image-name']).is_file()
assert len(manifest['groups'])==4
assert 'ASSETCATALOG_COMPILER_APPICON_NAME: ScanFlowIcon' in (root/'project.yml').read_text()
print('Native layered Liquid Glass icon manifest and artwork: OK')
