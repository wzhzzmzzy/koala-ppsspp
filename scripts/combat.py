"""Exercise native PSP inputs during a 30-second first-arena measurement.

Start from the manual state saved immediately after dismissing ATTACKS.
Review the screenshots: core telemetry alone cannot distinguish combat from
an in-game tutorial. This script never automates macOS UI or uploads files.
"""
from pathlib import Path
import argparse
import json
import subprocess
import sys
import time

parser = argparse.ArgumentParser()
parser.add_argument('--session', type=Path, required=True)
parser.add_argument('--label', required=True)
args = parser.parse_args()
root = args.session.resolve()
controller = [sys.executable, str(Path(__file__).with_name('control.py')), '--session', str(root)]
events = []

def command(*parts):
    response = subprocess.check_output(controller + [str(part) for part in parts], text=True)
    events.append({'wall_time': time.time(), 'command': parts, 'ack': json.loads(response)})

command('load', 'manual')
command('resume')
command('analog', 0, 1, 850)
for button in ['square', 'square', 'triangle', 'square', 'square', 'triangle']:
    command('press', button, 80)
    time.sleep(.5)

with (root/f'measure-{args.label}.log').open('w') as output:
    process = subprocess.Popen(controller + ['measure', '30', args.label], stdout=output, stderr=subprocess.STDOUT)
    index = 0
    while process.poll() is None:
        command('press', 'triangle' if index % 3 == 2 else 'square', 80)
        if index in [0, 18, 36]:
            command('shot', f'{args.label}-{index}.png')
        index += 1
        time.sleep(.5)
command('pause')
command('shot', f'{args.label}-end.png')
(root/f'inputs-{args.label}.json').write_text(json.dumps(events, ensure_ascii=False, indent=2)+'\n')
print((root/f'measure-{args.label}.log').read_text())
raise SystemExit(process.returncode)
