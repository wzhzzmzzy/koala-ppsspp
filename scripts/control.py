"""Native file IPC for repeatable controls, screenshots and timed measurements."""
from pathlib import Path
import argparse
import json
import statistics
import time
import uuid

parser = argparse.ArgumentParser()
parser.add_argument('--session', type=Path, required=True)
parser.add_argument('--wait', type=float, default=0)
parser.add_argument('command', choices=['status','press','analog','save','load','pause','resume','mute','fullscreen','quit','shot','measure'])
parser.add_argument('arguments', nargs='*')
args = parser.parse_args()
root = args.session.resolve()

def status():
    return json.loads((root/'status.json').read_text())

def send(operation):
    identifier = str(uuid.uuid4())
    temporary = root/'command.tmp'
    temporary.write_text(f'{identifier} {operation}\n')
    temporary.replace(root/'command.txt')
    until = time.monotonic() + 20
    while time.monotonic() < until:
        try:
            ack = json.loads((root/'ack.json').read_text())
            if ack['id'] == identifier:
                if not ack['ok']:
                    raise RuntimeError(ack['message'])
                return ack
        except FileNotFoundError:
            pass
        time.sleep(.05)
    raise TimeoutError(f'Native command timed out: {operation}')

if args.command == 'status':
    result = status()
elif args.command == 'measure':
    duration = float(args.arguments[0]) if args.arguments else 30
    label = args.arguments[1] if len(args.arguments) > 1 else 'sample'
    samples = []
    first = status()
    start = time.monotonic()
    while time.monotonic() - start < duration:
        sample = status()
        if not samples or sample['time'] != samples[-1]['time']:
            if not sample['playing']:
                raise RuntimeError('Benchmark interrupted: emulator is paused or in a native menu')
            samples.append(sample)
        time.sleep(.2)
    final = status()
    def distribution(key):
        values = sorted(sample[key] for sample in samples)
        return {'mean':statistics.mean(values),'min':min(values),'max':max(values),'p05':values[int((len(values)-1)*.05)]}
    result = {'label':label,'duration_seconds':time.monotonic()-start,'sample_count':len(samples),
              'game_fps':distribution('game_fps'),'vps':distribution('vps'),
              'speed_percent':distribution('speed_percent'),'rss_bytes':distribution('rss_bytes'),
              'vblank_rate':(final['vblanks']-first['vblanks'])/(final['time']-first['time']),
              'render_scale':final['render_scale'],'gpu_backend':final['gpu_backend'],
              'jit_active':all(sample['jit_active'] for sample in samples),'frameskip':final['frameskip'],
              'muted':final['muted'],'pass':statistics.mean(s['speed_percent'] for s in samples)>=95,
              'samples':samples}
    (root/f'benchmark-{label}.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    result = {key:value for key,value in result.items() if key!='samples'}
else:
    buttons = {'select':1,'start':8,'up':16,'right':32,'down':64,'left':128,
               'l':256,'r':512,'triangle':4096,'circle':8192,'cross':16384,'square':32768}
    if args.command == 'press':
        button = buttons[args.arguments[0]]
        hold = args.arguments[1] if len(args.arguments)>1 else '100'
        operation = f'press {button} {hold}'
    elif args.command in ['save','load']:
        slot = 0 if args.arguments and args.arguments[0]=='auto' else 1
        operation = f'{args.command} {slot}'
    elif args.command == 'shot':
        operation = 'screenshot '+args.arguments[0]
    else:
        operation = ' '.join([args.command]+args.arguments)
    result = send(operation)
if args.wait:
    time.sleep(args.wait)
print(json.dumps(result,ensure_ascii=False))
if result.get('pass') is False:
    raise SystemExit(1)
