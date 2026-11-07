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
assert 'CURRENT_PROJECT_VERSION: 47' in (root/'project.yml').read_text()
print('Package files, asset catalog and upgrade bundle identifier: OK')

icon=root/'AutoSplit/ScanFlowIcon.icon'
manifest=json.loads((icon/'icon.json').read_text())
for group in manifest['groups']:
    for layer in group['layers']:
        assert (icon/'Assets'/layer['image-name']).is_file()
assert len(manifest['groups']) >= 1
assert 'ASSETCATALOG_COMPILER_APPICON_NAME: ScanFlowIcon' in (root/'project.yml').read_text()
print('Icon Composer manifest and selected scanner artwork: OK')

catalog=json.loads((root/"AutoSplit/IconCollection.json").read_text())
assert len(catalog)==30
assert len({i["name"] for i in catalog})==30
assert len({i["case"] for i in catalog})==30
for item in catalog:
    picker=(root/"AutoSplit/AppIconPicker.swift").read_text()
    assert item["name"] in picker and item["title"] in picker
    assert item["name"] in (root/"project.yml").read_text()
for name in ["ScanFlowIcon", "ScanFlowPearl", "ScanFlowGraphite", "ScanFlowClassic"] + [i["name"] for i in catalog]:
    package=root/"AutoSplit"/(name+".icon")
    manifest=json.loads((package/"icon.json").read_text())
    for group in manifest["groups"]:
        for layer in group["layers"]:
            assert (package/"Assets"/layer["image-name"]).is_file()
    if name in {"ScanFlowIcon", "ScanFlowPearl", "ScanFlowGraphite"}:
        assert all(layer.get("glass") for g in manifest["groups"] for layer in g["layers"])
print("All alternate icon packages and native glass layers: OK")

import hashlib, struct
hashes = set()
for item in catalog:
    package = root/'AutoSplit'/(item['name']+'.icon')
    data = (package/'Assets/Artwork.png').read_bytes()
    assert struct.unpack('>II', data[16:24]) == (1024,1024)
    assert data[25] == 2, 'Artwork must be opaque RGB'
    digest = hashlib.sha256(data).hexdigest()
    assert digest == item['artwork_sha256']
    hashes.add(digest)
    manifest = json.loads((package/'icon.json').read_text())
    assert len(manifest['groups']) == 1
    assert manifest['groups'][0]['layers'] == [{'name':'Artwork','image-name':'Artwork.png','glass':False}]
assert len(hashes) == 30
assert [sum(i['collection']==c for i in catalog) for c in [1,2,3]] == [10,10,10]
assert [i['number'] for i in catalog] == list(range(1,31))
print('Thirty distinct opaque approved artworks, picker mappings and compiler names: OK')
