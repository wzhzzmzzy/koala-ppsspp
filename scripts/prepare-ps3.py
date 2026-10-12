"""Fetch and verify the pinned official RPCS3 native macOS engine."""
from pathlib import Path
import hashlib
import json
import subprocess
import urllib.request

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root/'rpcs3-upstream.json').read_text())
directory = root/'vendor/rpcs3'
directory.mkdir(parents=True, exist_ok=True)
archive = directory/manifest['asset']
if not archive.is_file():
    temporary = archive.with_suffix('.download')
    try:
        urllib.request.urlretrieve(manifest['url'], temporary)
        if hashlib.sha256(temporary.read_bytes()).hexdigest() != manifest['sha256']:
            raise SystemExit('RPCS3 download checksum mismatch; refusing to extract.')
        temporary.rename(archive)
    finally:
        temporary.unlink(missing_ok=True)
if hashlib.sha256(archive.read_bytes()).hexdigest() != manifest['sha256']:
    raise SystemExit('RPCS3 archive checksum mismatch; refusing to package.')
# Only extract an authenticated, fixed upstream artifact. Never unpack BIOS/ROM archives here.
extracted = directory/('verified-' + manifest['sha256'][:16])
engine = extracted/manifest['bundle']/manifest['executable']
if not engine.is_file():
    extracted.mkdir(exist_ok=True)
    subprocess.run(['7zz', 'x', '-y', '-o' + str(extracted), str(archive)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(extracted/manifest['bundle'])], check=True)
assert engine.is_file(), engine
architectures = subprocess.check_output(['lipo', '-archs', str(engine)], text=True).strip()
assert architectures == 'arm64', architectures
print(engine)
