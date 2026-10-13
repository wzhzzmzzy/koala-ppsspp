"""Exercise the bundled MoltenVK runtime in hidden windows and isolated XDG data."""
from pathlib import Path
import argparse, json, os, subprocess, time, uuid

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--rom', required=True, type=Path)
parser.add_argument('--state', type=Path)
parser.add_argument('--app', type=Path)
options = parser.parse_args()
rom = options.rom.expanduser().resolve()
assert rom.is_file(), rom
build = json.loads((root/'output/build.json').read_text())
app = (options.app or Path(build['app'])).resolve()
subprocess.run(['xcrun','swiftc',str(root/'scripts/check-background.swift'),'-o',str(root/'output/check-background'),'-module-cache-path',str(root/'output/swift-module-cache')],check=True)
results = []
for driver in ['moltenvk']:
    case = root/'output'/('vulkan-'+driver+'-'+str(uuid.uuid4())[:8])
    for folder in ['config/ppsspp','run','logs']: (case/folder).mkdir(parents=True,exist_ok=True)
    (case/'config/preferences.json').write_text(json.dumps(dict(scale=3,muted=True,hud=2)))
    env = {k:v for k,v in os.environ.items() if not k.startswith(('VK_','MESA_','KK_','KOALA_','XDG_')) and k!='SDL_VULKAN_LIBRARY'}
    env.update(KOALA_DATA_DIR=str(case), KOALA_CONFIG_DIR=str(case/'config/ppsspp'), KOALA_CONTROL_DIR=str(case/'run'),
               KOALA_LOG_DIR=str(case/'logs'), KOALA_BACKGROUND_TEST='1')
    launch = json.loads(subprocess.check_output([str(app/'Contents/MacOS/KoalaPSP'),'--vulkan-launch-report'],env=env))
    env.update(launch['environment'])
    (case/'run/launch.ini').write_text(launch['config'])
    helper = app/'Contents/Helpers/PPSSPPSDL.app/Contents/MacOS/PPSSPPSDL'
    args = [str(helper),str(rom),'--appendconfig='+str(case/'run/launch.ini'),'--windowed','--xres','960','--yres','544','--pause-menu-exit']
    if options.state: args.append('--state='+str(options.state.expanduser().resolve()))
    result = dict(driver=driver,case=str(case),app=str(app),fullscreenTested=False,foregroundPerformanceMeasured=False,backgroundChecks=0)
    log = (case/'logs/engine.log').open('wb')
    started=time.monotonic()
    child = subprocess.Popen(args,env=env,cwd=helper.parent,stdout=log,stderr=subprocess.STDOUT)
    def background():
        subprocess.run([str(root/'output/check-background'),str(child.pid)],check=True,stdout=subprocess.DEVNULL)
        result['backgroundChecks'] += 1
    def command(op):
        identifier=str(uuid.uuid4());p=case/'run/command.tmp';p.write_text(identifier+' '+op+'\n');p.replace(case/'run/command.txt')
        deadline=time.monotonic()+20
        while time.monotonic()<deadline:
            background()
            try:
                ack=json.loads((case/'run/ack.json').read_text())
                if ack['id']==identifier:
                    assert ack['ok'],ack
                    return ack
            except (FileNotFoundError,json.JSONDecodeError): pass
            if child.poll() is not None: raise RuntimeError('engine exited: '+str(child.returncode))
            time.sleep(.2)
        raise TimeoutError('command: '+op)
    try:
        deadline=time.monotonic()+60
        while time.monotonic()<deadline:
            background()
            if child.poll() is not None: raise RuntimeError('engine exited: '+str(child.returncode))
            try:
                status=json.loads((case/'run/status.json').read_text())
                if status['ready'] and status['playing'] and status.get('frame_samples',0)>=10: break
            except (FileNotFoundError,json.JSONDecodeError): pass
            time.sleep(.3)
        else: raise TimeoutError('engine not ready')
        result['readySeconds']=time.monotonic()-started
        actual=json.loads((case/'logs/vulkan-driver.json').read_text())
        assert actual['requested']==driver and actual['driverName'].lower()==driver and actual['deviceCreated'],actual
        result['actual']=actual
        result['status']=status
        command('ping')
        command('screenshot driver-test.png')
        command('pause'); command('resume')
        command('quit');child.wait(timeout=20)
        assert child.returncode==0,child.returncode
        result['passed']=True
    except Exception as error:
        result['passed']=False;result['error']=repr(error)
    finally:
        if child.poll() is None:
            child.terminate()
            try:child.wait(timeout=5)
            except subprocess.TimeoutExpired:child.kill();child.wait()
        log.close()
        (case/'result.json').write_text(json.dumps(result,indent=2)+'\n')
        results.append(result)
        print(json.dumps({k:v for k,v in result.items() if k!='status'}),flush=True)
(root/'output/vulkan-tests.json').write_text(json.dumps(results,indent=2)+'\n')
raise SystemExit(0 if all(r['passed'] for r in results) else 1)
