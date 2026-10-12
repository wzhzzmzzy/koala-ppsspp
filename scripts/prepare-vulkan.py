"""Fetch pinned SDK into vendor only; no system installation or graphical installer."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import urllib.request

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root/'vulkan-upstream.json').read_text())
directory = root/'vendor/vulkan-sdk'
directory.mkdir(parents=True, exist_ok=True)
sdk = directory/manifest['sdkVersion']

def digest(path):
    with path.open('rb') as file:
        result = hashlib.sha256()
        for chunk in iter(lambda: file.read(1024*1024), b''): result.update(chunk)
        return result.hexdigest()

if not (sdk/'macOS/lib/libvulkan_kosmickrisp.dylib').is_file():
    archive = directory/manifest['asset']
    if not archive.is_file():
        temporary = archive.with_suffix('.download')
        try:
            urllib.request.urlretrieve(manifest['url'], temporary)
            if digest(temporary) != manifest['sha256']: raise SystemExit('Vulkan SDK download checksum mismatch.')
            temporary.rename(archive)
        finally: temporary.unlink(missing_ok=True)
    if digest(archive) != manifest['sha256']: raise SystemExit('Vulkan SDK archive checksum mismatch.')
    extracted = directory/'installer'
    subprocess.run(['ditto', '-x', '-k', str(archive), str(extracted)], check=True)
    name = 'vulkansdk-macOS-' + manifest['sdkVersion']
    installer = extracted/(name+'.app')/'Contents/MacOS'/name
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_MAC_DISABLE_FOREGROUND_APPLICATION_TRANSFORM='1')
    subprocess.run([str(installer), '--cache-path', str(directory/'installer-cache'), '--root', str(sdk),
                    '--accept-licenses', '--default-answer', '--confirm-command', 'install', 'copy_only=1'], env=env, check=True)
for name, expected in manifest['files'].items():
    path = sdk/name
    if not path.is_file() or digest(path) != expected:
        raise SystemExit('Vulkan SDK installed file checksum mismatch: '+name)
print(sdk)
