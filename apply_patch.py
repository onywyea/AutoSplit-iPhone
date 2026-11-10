from pathlib import Path
import json,shutil,re
root=Path(__file__).resolve().parent
assert (root/'project.yml').exists(), 'Place patch files in the root of AutoSplit-iPhone'
base=root/'AutoSplit'
names=['ScanFlowAmber','ScanFlowViolet','ScanFlowCoral','ScanFlowCyan','ScanFlowPink']
for p in base.glob('*.icon'):
    if p.is_dir(): shutil.rmtree(p)
for p in base.rglob('IconPreview-*'):
    if p.is_file(): p.unlink()
for name in names:
    dest=base/(name+'.icon')
    (dest/'Assets').mkdir(parents=True)
    shutil.copyfile(root/(name+'.png'),dest/'Assets/Artwork.png')
    (dest/'icon.json').write_text(json.dumps({'fill':{'specializations':[{'appearance':'dark','value':'#000000'},{'appearance':'tinted','value':'#000000'}]},'groups':[{'layers':[{'name':'Artwork','image-name':'Artwork.png','glass':False}]}]},indent=2))
    # Previews in asset catalog, not loose PNGs
    folder=base/'Assets.xcassets'/('IconPreview-'+name+'.imageset')
    folder.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(root/(name+'.png'),folder/'Artwork.png')
    (folder/'Contents.json').write_text(json.dumps({'images':[{'filename':'Artwork.png','idiom':'universal'}],'info':{'author':'xcode','version':1}}))
assets=base/'Assets.xcassets'
for p in assets.glob('IconPreview-*.imageset'):
    if p.name not in {'IconPreview-'+n+'.imageset' for n in names}:shutil.rmtree(p)
project=root/'project.yml'
s=project.read_text()
s=re.sub(r'ASSETCATALOG_COMPILER_APPICON_NAME: .*','ASSETCATALOG_COMPILER_APPICON_NAME: ScanFlowAmber',s)
s=re.sub(r'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES: .*','ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES: "ScanFlowViolet ScanFlowCoral ScanFlowCyan ScanFlowPink"',s)
s=re.sub(r"MARKETING_VERSION: '[^']+'","MARKETING_VERSION: '0.4.26'",s)
s=re.sub(r'CURRENT_PROJECT_VERSION: \d+','CURRENT_PROJECT_VERSION: 48',s)
project.write_text(s)
picker=base/'AppIconPicker.swift'
s=picker.read_text()
a=s.index('enum ScanAppIcon:')
b=s.index('\nstruct AppIconPicker:',a)
replacement='''enum ScanAppIcon: String, CaseIterable, Identifiable {
    case amber, violet, coral, cyan, pink
    var id: String { rawValue }
    var name: String? {
        switch self {
        case .amber: return nil
        case .violet: return "ScanFlowViolet"
        case .coral: return "ScanFlowCoral"
        case .cyan: return "ScanFlowCyan"
        case .pink: return "ScanFlowPink"
        }
    }
    var title: String {
        switch self {
        case .amber: return "Бурштиновий документ"
        case .violet: return "Фіолетова стрічка"
        case .coral: return "Кораловий сканер"
        case .cyan: return "Блакитний сканер"
        case .pink: return "Рожева папка"
        }
    }
    static let collections: [(title: String, icons: [Self])] = [
        ("Іконки ScanFlow", [.amber, .violet, .coral, .cyan, .pink])
    ]
    static let previous: [Self] = []
    static var current: Self {
        allCases.first { $0.name == UIApplication.shared.alternateIconName } ?? .amber
    }
}
'''
s=s[:a]+replacement+s[b:]
s=s.replace('30 іконок у трьох колекціях. Оберіть свій варіант.','5 іконок. Оберіть свій варіант.')
s=re.sub(r'\s*DisclosureGroup\("Попередні іконки"\) \{.*?\n\s*\}', '', s, count=1, flags=re.S)
s=s.replace('ScanAppIcon.pearl.name','ScanAppIcon.violet.name').replace('current == .pearl','current == .violet')
s=s.replace('let name = icon.name ?? "ScanFlowIcon"','let name = icon.name ?? "ScanFlowAmber"')
picker.write_text(s)
(base/'IconCollection.json').write_text('[]\n')
check=root/'scripts/check_package.py'
s=check.read_text()
s=s[:s.index('icon=root/')] + '''names=['ScanFlowAmber','ScanFlowViolet','ScanFlowCoral','ScanFlowCyan','ScanFlowPink']
for name in names:
    package=root/'AutoSplit'/(name+'.icon')
    manifest=json.loads((package/'icon.json').read_text())
    for group in manifest['groups']:
        for layer in group['layers']:
            assert (package/'Assets'/layer['image-name']).is_file()
assert len(list((root/'AutoSplit').glob('*.icon')))==5
print('Exactly five icons: OK')
'''
s=s.replace('CURRENT_PROJECT_VERSION: 47','CURRENT_PROJECT_VERSION: 48')
check.write_text(s)
verify=root/'scripts/verify_icon_project.py'
verify.write_text('''from pathlib import Path
import re
p=Path('AutoSplit.xcodeproj/project.pbxproj')
s=p.read_text()
for name in ['ScanFlowAmber','ScanFlowViolet','ScanFlowCoral','ScanFlowCyan','ScanFlowPink']:
    assert name+'.icon in Resources' in s, name
lines=s.splitlines()
for i,line in enumerate(lines):
    if 'isa = PBXFileReference;' in line and '.icon' in line:
        if re.search(r'(?:lastKnownFileType|explicitFileType) = [^;]+;',line):
            line=re.sub(r'(?:lastKnownFileType|explicitFileType) = [^;]+;', 'lastKnownFileType = folder.iconcomposer.icon;',line)
        else:
            line=line.replace('isa = PBXFileReference;', 'isa = PBXFileReference; lastKnownFileType = folder.iconcomposer.icon;')
        lines[i]=line
p.write_text('\n'.join(lines)+'\n')
print('Five icon composer resources verified')
''')
print('ScanFlow 0.4.26 patch applied. Commit/push to build IPA on GitHub Actions.')
