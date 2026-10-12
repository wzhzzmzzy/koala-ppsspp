"""Verify production settings/telemetry in a hidden engine; never activate or fullscreen."""
from pathlib import Path
import argparse, json, os, subprocess, time, uuid
root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--rom', type=Path, required=True, help='Local game image (not included)')
parser.add_argument('--state', type=Path, required=True, help='Matching in-game save state (not included)')
parser.add_argument('--driver', choices=['moltenvk','kosmickrisp'], default='moltenvk')
options = parser.parse_args()
rom = options.rom.expanduser().resolve()
state = options.state.expanduser().resolve()
if not rom.is_file() or not state.is_file():
    parser.error('--rom and --state must refer to existing local files')
build = json.loads((root/'output/build.json').read_text())
app = Path(build['app'])
case = root/'output'/('background-'+build['version']+'-'+options.driver+'-'+time.strftime('%H%M%S'))
case.mkdir()
for name in ['config/ppsspp', 'cache', 'run', 'logs']:
    (case/name).mkdir(parents=True)
prefs = dict(vulkanDriver=options.driver, scale=3, muted=True, volume=37, hud=2, audioBuffer=512,
             vsync=False, textureFilter=3, anisotropy=2, smart2D=True, frameSkip=0, fillAudioGaps=False)
(case/'config/preferences.json').write_text(json.dumps(prefs))
env = dict(os.environ, KOALA_DATA_DIR=str(case), KOALA_CONFIG_DIR=str(case/'config/ppsspp'),
           KOALA_CACHE_DIR=str(case/'cache'), KOALA_LOG_DIR=str(case/'logs'), KOALA_CONTROL_DIR=str(case/'run'),
           KOALA_BACKGROUND_TEST='1')
launch = json.loads(subprocess.check_output([str(app/'Contents/MacOS/KoalaPSP'), '--vulkan-launch-report'], env=env))
env = {k:v for k,v in env.items() if not k.startswith(('VK_', 'MESA_', 'KK_')) and k != 'SDL_VULKAN_LIBRARY'}
env.update(launch['environment'])
(case/'run/launch.ini').write_text(launch['config'])
engine = app/'Contents/Helpers/PPSSPPSDL.app/Contents/MacOS/PPSSPPSDL'
log = (case/'logs/engine.log').open('wb')
args = [str(engine), str(rom),
        '--appendconfig='+str(case/'run/launch.ini'), '--windowed', '--xres', '960', '--yres', '544', '--pause-menu-exit',
        '--state='+str(state)]
child = subprocess.Popen(args, cwd=engine.parent, env=env, stdout=log, stderr=subprocess.STDOUT)
result = dict(appVersion=build['version'], case=str(case), pid=child.pid, fullscreenTested=False, checks=[])
def read_status():
    try: return json.loads((case/'run/status.json').read_text())
    except (FileNotFoundError, json.JSONDecodeError): return {}
def wait_status(predicate, seconds=15):
    until = time.monotonic()+seconds
    while time.monotonic()<until:
        s = read_status()
        if predicate(s): return s
        if child.poll() is not None: raise RuntimeError('Engine exited: '+str(child.returncode))
        time.sleep(.1)
    raise TimeoutError('Status did not reach expected state: '+str(read_status()))
def command(op, ok=True):
    identifier = str(uuid.uuid4()); tmp = case/'run/command.tmp'
    start = time.monotonic(); tmp.write_text(identifier+' '+op+'\n'); tmp.replace(case/'run/command.txt')
    until = time.monotonic()+20
    while time.monotonic()<until:
        try:
            ack = json.loads((case/'run/ack.json').read_text())
            if ack['id'] == identifier:
                assert ack['ok'] is ok, ack
                result['checks'].append(dict(command=op, ack=ack, roundTripMS=(time.monotonic()-start)*1000))
                return ack
        except FileNotFoundError: pass
        time.sleep(.05)
    raise TimeoutError(op)
try:
    first = wait_status(lambda s:s.get('ready') and s.get('playing') and s.get('frame_samples',0)>=10, 50)
    assert {k:first[k] for k in ['render_scale','volume','hud','audio_buffer','vsync','texture_filter','anisotropy','muted']} == dict(render_scale=3,volume=37,hud=2,audio_buffer=512,vsync=False,texture_filter=3,anisotropy=2,muted=True), first
    assert first['frame_ms_mean']>0 and first['frame_ms_p95']>0
    result['driver'] = json.loads((case/'logs/vulkan-driver.json').read_text())
    assert result['driver']['requested'] == options.driver
    assert result['driver']['driverName'].lower() == options.driver
    assert result['driver']['deviceCreated']
    result['initialStatus'] = first
    result['backgroundCheck'] = json.loads(subprocess.check_output([str(root/'output/check-background'),str(child.pid)]))
    menus = json.loads((case/'logs/native-menus.json').read_text())
    assert len(menus)==4 and sum(len(g[1]) for g in menus)==10
    result['nativeMenus'] = menus
    command('ping')
    command('bind-shoulders')
    controls = (case/'config/ppsspp/controls.ini').read_text(encoding='utf-8-sig')
    assert 'L = 1-45,10-194,10-193' in controls and 'R = 1-51,10-195,10-192' in controls
    command('bind-shoulders')
    assert (case/'config/ppsspp/controls.ini').read_text(encoding='utf-8-sig') == controls
    result['shoulderAliases'] = 'additive and idempotent; keyboard and old mappings retained'
    command('screenshot hud-detail.png')
    for volume,hud in [(0,0),(82,1),(37,2)]:
        command(f'settings 1 {volume} {hud}')
        wait_status(lambda s:s.get('volume')==volume and s.get('hud')==hud and s.get('muted'))
    command('settings 0 200 2', ok=False)
    assert read_status()['volume']==37 and read_status()['muted']
    command('pause'); wait_status(lambda s:not s.get('playing',True))
    command('resume'); wait_status(lambda s:s.get('playing',False))
    # Read through the same PlayerModel/MappingSnapshot used by the diagrams.
    def mapping_snapshot():
        try: return json.loads((case/'run/mappings.json').read_text())
        except (FileNotFoundError,json.JSONDecodeError): return {}
    def wait_mapping(name, expected):
        deadline = time.monotonic()+8
        while time.monotonic()<deadline:
            s = mapping_snapshot()
            action = next((a for a in s.get('actions',[]) if a['name']==name), None)
            if action is not None and action['bindings']==expected: return s
            time.sleep(.1)
        raise AssertionError('Live mapping did not update: '+name)
    def diagram():
        return json.loads(subprocess.check_output([str(app/'Contents/MacOS/KoalaPSP'),'--mapping-report',str(case/'run/mappings.json')],env=env))
    live = []
    wait_mapping('Cross', [[dict(device=1,code=54)],[dict(device=10,code=189)]])
    before = diagram(); assert before['a']=='× 叉' and '实时配置' in before['_source']
    command('pause')
    command('test-binding Cross 10-190')
    wait_mapping('Cross', [[dict(device=10,code=190)]])
    moved = diagram(); assert moved['a']=='未绑定' and '× 叉' in moved['b'] and '○ 圆' in moved['b']
    assert (case/'config/ppsspp/controls.ini').read_text(encoding='utf-8-sig') == controls
    live.append(dict(change='unsaved cross moved from A to B while paused', diagram=moved))
    command('test-binding Square 10-193:10-189')
    wait_mapping('Square', [[dict(device=10,code=193),dict(device=10,code=189)]])
    chord = diagram(); assert chord['a']=='□ 方块（组合）' and '组合' in chord['lb']
    live.append(dict(change='LB + A chord',diagram=chord))
    command('test-binding Cross clear'); wait_mapping('Cross',[])
    cleared = diagram(); assert cleared['b']=='○ 圆'
    live.append(dict(change='clear cross',diagram=cleared))
    command('test-binding Triangle 11-189'); wait_mapping('Triangle',[[dict(device=11,code=189)]])
    assert diagram()['y']=='未绑定'
    result['liveMappings'] = live
    (case/'logs/mappings-final.json').write_text(json.dumps(mapping_snapshot(),ensure_ascii=False,indent=2))
    command('resume')
    command('quit'); child.wait(timeout=20); assert child.returncode==0
    result['pass'] = True
except Exception as e:
    result['pass'] = False; result['error'] = repr(e)
    if child.poll() is None:
        child.terminate()
        try: child.wait(timeout=5)
        except subprocess.TimeoutExpired: child.kill(); child.wait()
finally:
    log.close()
    (case/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    (root/'output/background-test.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k not in ['initialStatus','nativeMenus','checks']},ensure_ascii=False))
raise SystemExit(0 if result['pass'] else 1)
