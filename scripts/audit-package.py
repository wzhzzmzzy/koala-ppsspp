"""Audit a standalone .app and exercise its storage path without opening UI."""
from pathlib import Path
import json
import os
import plistlib
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
build = json.loads((root/'output/build.json').read_text())
app = Path(build['app'])
engine = app/'Contents/Helpers/PPSSPPSDL.app'
frameworks = [app/'Contents/Frameworks', engine/'Contents/Frameworks']
magic = {b'\xcf\xfa\xed\xfe',b'\xce\xfa\xed\xfe',b'\xfe\xed\xfa\xcf',b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca'}
records = []
for binary in sorted(app.rglob('*')):
    if not binary.is_file() or binary.is_symlink(): continue
    with binary.open('rb') as f:
        if f.read(4) not in magic: continue
    architectures = subprocess.check_output(['lipo','-archs',str(binary)],text=True).strip().split()
    assert 'arm64' in architectures, binary
    executable = engine/'Contents/MacOS' if binary.is_relative_to(engine) else app/'Contents/MacOS'
    commands = subprocess.check_output(['otool','-arch','arm64','-l',str(binary)],text=True)
    versions = []
    for block in re.split(r'^Load command ',commands,flags=re.M):
        if re.search(r'cmd LC_BUILD_VERSION\b',block):
            versions += re.findall(r'^\s+minos (\d+\.\d+(?:\.\d+)?)$',block,re.M)
        elif re.search(r'cmd LC_VERSION_MIN_MACOSX\b',block):
            versions += re.findall(r'^\s+version (\d+\.\d+(?:\.\d+)?)$',block,re.M)
    assert versions, binary
    assert all(tuple(map(int,v.split('.'))) <= (14,0,0) for v in versions), (binary,versions)
    dependencies = subprocess.check_output(['otool','-arch','arm64','-L',str(binary)],text=True).splitlines()[1:]
    resolved=[]
    for line in dependencies:
        dependency = line.strip().split(' (',1)[0]
        if not dependency or dependency.endswith(':'): continue
        if dependency.startswith(('/System/Library/','/usr/lib/')): continue
        if dependency.startswith('@rpath/'):
            tail = dependency[len('@rpath/'):]
            candidates = [base/tail for base in frameworks] + [binary.parent/tail]
        elif dependency.startswith('@loader_path/'):
            candidates = [binary.parent/dependency[len('@loader_path/'):]]
        elif dependency.startswith('@executable_path/'):
            candidates = [executable/dependency[len('@executable_path/'):]]
        else:
            raise AssertionError(f'External non-system dependency: {binary}: {dependency}')
        candidates = [p.resolve() for p in candidates if p.exists()]
        assert any(p.is_relative_to(app.resolve()) for p in candidates), (binary,dependency)
        resolved.append(dependency)
    records.append({'path':str(binary.relative_to(app)),'architectures':architectures,'minimumOS':versions,'bundledDependencies':resolved})
assert records
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
for bundle in [app,engine]:
    info=plistlib.loads((bundle/'Contents/Info.plist').read_bytes())
    assert info['CFBundleIconFile']=='AppIcon'
    assert (bundle/'Contents/Resources/AppIcon.icns').read_bytes()[:4]==b'icns'
with tempfile.TemporaryDirectory(prefix='koala-portability-') as directory:
    scratch=Path(directory)
    subprocess.run(['ditto','-x','-k',build['archive'],str(scratch/'unpacked')],check=True)
    moved=scratch/'unpacked/Koala PSP.app'
    subprocess.run(['codesign','--verify','--deep','--strict',str(moved)],check=True)
    env=os.environ.copy()
    for key in list(env):
        if key.startswith('KOALA_') or key.startswith('XDG_'): env.pop(key)
    for key,folder in [('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_STATE_HOME','state'),('XDG_CACHE_HOME','cache'),('XDG_RUNTIME_DIR','run')]:
        path=scratch/folder;path.mkdir(mode=0o700);env[key]=str(path)
    executable=moved/'Contents/MacOS/KoalaPSP'
    first=json.loads(subprocess.check_output([str(executable),'--storage-report'],env=env,text=True,cwd=scratch))
    assert first['iconPresent'] and first['games']==0
    (Path(first['config'])/'preferences.json').write_text(json.dumps({'scale':3,'muted':True}))
    second=json.loads(subprocess.check_output([str(executable),'--storage-report'],env=env,text=True,cwd=scratch))
    assert second['scale']==3 and second['muted'] is True
    assert first['data'].startswith(str(scratch)) and first['state'].startswith(str(scratch))
report={'pass':True,'app':str(app),'macho':records,'zip_relocation':'signature and headless native startup passed',
        'preference_reopen':'passed','otherPhysicalMac':'not tested','Gatekeeper':'local ad-hoc signature, not Developer ID notarized',
        'uiOpened':False,'fullscreenTested':False}
(root/'output/package-audit.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
