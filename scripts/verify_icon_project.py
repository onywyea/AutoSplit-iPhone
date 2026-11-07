"""Keep native Icon Composer type explicit across XcodeGen/Xcode versions."""
from pathlib import Path
import re
p=Path('AutoSplit.xcodeproj/project.pbxproj')
project=p.read_text()
lines=project.splitlines()
found=False
for i,line in enumerate(lines):
    if 'isa = PBXFileReference;' in line and '.icon' in line:
        if re.search(r'(?:lastKnownFileType|explicitFileType) = [^;]+;',line):
            line=re.sub(r'(?:lastKnownFileType|explicitFileType) = [^;]+;','lastKnownFileType = folder.iconcomposer.icon;',line)
        else:
            line=line.replace('isa = PBXFileReference;','isa = PBXFileReference; lastKnownFileType = folder.iconcomposer.icon;')
        lines[i]=line;found=True
for name in ['ScanFlowIcon','ScanFlowPearl','ScanFlowGraphite','ScanFlowClassic']:
    assert name+'.icon in Resources' in project, name+' is missing from Resources'
assert found, 'Icon Composer package is missing as a file reference'
project='\n'.join(lines)+'\n'
assert 'ScanFlowIcon.icon in Resources' in project, 'Icon Composer package is missing from Resources'
p.write_text(project)
print('Native Liquid Glass icon resource: included with Icon Composer type')

