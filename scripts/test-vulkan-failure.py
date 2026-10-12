"""Verify a broken experimental ICD fails clearly instead of silently using OpenGL."""
from pathlib import Path
import json, os, subprocess, uuid

root=Path(__file__).resolve().parents[1]
build=json.loads((root/'output/build.json').read_text());app=Path(build['app'])
case=root/'output'/('vulkan-failure-'+str(uuid.uuid4())[:8])
for folder in ['config/ppsspp','run','logs']:(case/folder).mkdir(parents=True,exist_ok=True)
(case/'config/preferences.json').write_text(json.dumps({'vulkanDriver':'kosmickrisp'}))
env={k:v for k,v in os.environ.items() if not k.startswith(('VK_','MESA_','KK_','KOALA_','XDG_')) and k!='SDL_VULKAN_LIBRARY'}
env.update(KOALA_DATA_DIR=str(case),KOALA_CONFIG_DIR=str(case/'config/ppsspp'),KOALA_CONTROL_DIR=str(case/'run'),KOALA_LOG_DIR=str(case/'logs'),KOALA_BACKGROUND_TEST='1')
launch=json.loads(subprocess.check_output([str(app/'Contents/MacOS/KoalaPSP'),'--vulkan-launch-report'],env=env))
env.update(launch['environment']);env['VK_DRIVER_FILES']=str(case/'missing-icd.json')
(case/'run/launch.ini').write_text(launch['config'])
engine=app/'Contents/Helpers/PPSSPPSDL.app/Contents/MacOS/PPSSPPSDL'
result=subprocess.run([str(engine),'--appendconfig='+str(case/'run/launch.ini'),'--windowed'],env=env,cwd=engine.parent,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=20)
log=result.stdout.decode(errors='replace');(case/'logs/engine.log').write_text(log)
assert result.returncode==1, (result.returncode,log[-2000:])
assert 'No automatic fallback' in log,log[-2000:]
assert not (case/'logs/vulkan-driver.json').exists()
report={'passed':True,'exitCode':result.returncode,'silentFallback':False,'case':str(case),'fullscreenTested':False}
(case/'result.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
