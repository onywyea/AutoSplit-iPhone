"""Capture the actual icon gallery without loading document/OCR fixture frameworks."""
from pathlib import Path
import subprocess,json,time

def run(*args): return subprocess.check_output(args,text=True).strip()
runtimes=json.loads(run('xcrun','simctl','list','runtimes','-j'))['runtimes']
ios=[r for r in runtimes if r.get('isAvailable') and 'iOS' in r['name'] and r['version'].startswith('26.')]
assert ios
runtime=sorted(ios,key=lambda r:tuple(map(int,r['version'].split('.'))))[-1]['identifier']
types=json.loads(run('xcrun','simctl','list','devicetypes','-j'))['devicetypes']
kind=next(t['identifier'] for t in types if t['name']=='iPhone 15 Pro')
device=run('xcrun','simctl','create','ScanFlow icon gallery',kind,runtime)
app='preview-build/Build/Products/Debug-iphonesimulator/AutoSplit.app'
out=Path('design-preview');out.mkdir(exist_ok=True)
try:
 subprocess.check_call(['xcrun','simctl','boot',device])
 subprocess.run(['xcrun','simctl','bootstatus',device,'-b'],check=True,timeout=240)
 subprocess.check_call(['xcrun','simctl','status_bar',device,'override','--time','9:41','--batteryState','charged','--batteryLevel','100'])
 subprocess.check_call(['xcrun','simctl','install',device,app])
 for size,start in [(size, start) for size in ['large'] for start in ['prism','portal','archive','art201','art205','art209','art301','art305','art309']] + [('accessibility-large','art309')]:
  subprocess.run(['xcrun','simctl','terminate',device,'ua.autosplit.scanner'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  subprocess.check_call(['xcrun','simctl','ui',device,'content_size',size])
  subprocess.check_call(['xcrun','simctl','launch',device,'ua.autosplit.scanner','--preview-icons','--preview-icon-scroll',start])
  target=out/(f'icons-{start}-{size}.png')
  for attempt in range(30):
   time.sleep(3)
   subprocess.check_call(['xcrun','simctl','io',device,'screenshot',str(target)])
   if target.stat().st_size>100000: break
  else: raise RuntimeError('Blank gallery frame: '+str(target))
  print('Captured',target,flush=True)
finally:
 try:
  subprocess.run(['xcrun','simctl','shutdown',device],check=False,timeout=15)
 except subprocess.TimeoutExpired:
  print('Simulator shutdown timed out after captures; runner cleanup will stop it',flush=True)
