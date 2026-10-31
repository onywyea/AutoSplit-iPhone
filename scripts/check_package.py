"""Package sanity check. This does not compile Swift or prove iPhone behavior."""
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
required = ['project.yml', '.github/workflows/build.yml', 'README_RU.md',
            'AutoSplit/App.swift', 'AutoSplit/Models.swift', 'AutoSplit/Store.swift',
            'AutoSplit/Imaging.swift', 'AutoSplit/Rules.swift', 'AutoSplit/Scanner.swift',
            'tests/main.swift', 'tests/cases.json']
for name in required:
    assert (root / name).is_file(), name
    assert (root / name).stat().st_size, name
cases = json.loads((root / 'tests/cases.json').read_text())
assert len(cases) >= 12
assert len(list((root / 'AutoSplit').glob('*.swift'))) == 6
assert 'CODE_SIGNING_ALLOWED: NO' in (root / 'project.yml').read_text()
assert 'workflow_dispatch:' in (root / '.github/workflows/build.yml').read_text()
try:
    import yaml
except ImportError:
    print('PyYAML unavailable: YAML parsing skipped')
else:
    project = yaml.safe_load((root / 'project.yml').read_text())
    assert project['targets']['AutoSplit']['platform'] == 'iOS'
    workflow = yaml.safe_load((root / '.github/workflows/build.yml').read_text())
    assert workflow['jobs']['build']['runs-on'].startswith('macos-')
print('Package structure and fixtures: OK. Swift/iOS compilation NOT run locally.')
