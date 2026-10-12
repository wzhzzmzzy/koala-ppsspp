"""Build the SwiftUI application and bundle the source-built native engine."""
from pathlib import Path
import hashlib
import json
import os
import plistlib
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
repo = Path(os.environ.get('PPSSPP_SOURCE_DIR', str(root/'vendor/ppsspp'))).expanduser().resolve()
(root/'output').mkdir(exist_ok=True)
if not (repo/'build/PPSSPPSDL.app/Contents/MacOS/PPSSPPSDL').is_file():
    raise SystemExit('Build the PPSSPPSDL target successfully before packaging.')
version = '0.7.0-preview.1'
app = root / f'dist/{version}/Koala PSP.app'
contents = app / 'Contents'
ps3_manifest = json.loads((root/'rpcs3-upstream.json').read_text())
subprocess.run(['python3', str(root/'scripts/prepare-ps3.py')], check=True)
ps2_manifest = json.loads((root/'armsx2-upstream.json').read_text())
subprocess.run(['python3', str(root/'scripts/prepare-ps2.py')], check=True)
subprocess.run(['python3', str(root/'scripts/prepare-vulkan.py')], check=True)
vulkan_manifest = json.loads((root/'vulkan-upstream.json').read_text())
for name in ['MacOS', 'Resources/Licenses', 'Helpers']:
    (contents / name).mkdir(parents=True, exist_ok=True)

subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-O', '-target', 'arm64-apple-macosx14.0',
                *[str(p) for p in sorted((root/'Sources').glob('*.swift'))], '-o', str(contents/'MacOS/KoalaPSP'),
                '-module-cache-path', str(root/'output/swift-module-cache')], check=True)
engine = contents/'Helpers/PPSSPPSDL.app'
if engine.exists():
    shutil.rmtree(engine)
shutil.copytree(repo/'build/PPSSPPSDL.app', engine, symlinks=True)
for asset in ['debugger', 'upload']:
    path = engine/'Contents/Resources/assets'/asset
    if path.exists():
        shutil.rmtree(path)

# Relocate Homebrew dylibs so the application can run without a Homebrew install.
frameworks = engine/'Contents/Frameworks'
frameworks.mkdir(exist_ok=True)
binary = engine/'Contents/MacOS/PPSSPPSDL'
queue = [binary]
seen = set()
copied = []
while queue:
    target = queue.pop(0)
    if target in seen:
        continue
    seen.add(target)
    output = subprocess.check_output(['otool', '-L', str(target)], text=True)
    for line in output.splitlines()[1:]:
        dependency = line.strip().split(' (', 1)[0]
        if not dependency.startswith('/opt/homebrew/'):
            continue
        source = Path(dependency)
        destination = frameworks/source.name
        if not destination.exists():
            shutil.copy2(source.resolve(), destination)
            copied.append({'name': source.name, 'source': dependency,
                           'sha256': hashlib.sha256(destination.read_bytes()).hexdigest()})
            subprocess.run(['install_name_tool', '-id', '@rpath/'+source.name, str(destination)], check=True)
            queue.append(destination)
        relative = ('@executable_path/../Frameworks/' if target == binary else '@loader_path/') + source.name
        subprocess.run(['install_name_tool', '-change', dependency, relative, str(target)], check=True)

# The optional driver is loaded on demand only, so older macOS keeps the default path.
optional = frameworks/'KosmicKrisp'
optional.mkdir(exist_ok=True)
sdk = root/'vendor/vulkan-sdk'/vulkan_manifest['sdkVersion']
for source, name in [('libvulkan.1.4.363.dylib', 'libvulkan.1.dylib'), ('libvulkan_kosmickrisp.dylib', 'libkosmickrisp.dylib')]:
    destination = optional/name
    if source.startswith('libvulkan.1.'):
        subprocess.run(['lipo', str(sdk/'macOS/lib'/source), '-thin', 'arm64', '-output', str(destination)], check=True)
    else:
        shutil.copy2(sdk/'macOS/lib'/source, destination)
    subprocess.run(['install_name_tool', '-id', '@loader_path/'+name, str(destination)], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(destination)], check=True)
(optional/'kosmickrisp_icd.json').write_text(json.dumps({'file_format_version':'1.0.0', 'ICD':{'api_version':'1.4.0', 'library_path':'./libkosmickrisp.dylib'}}, indent=2)+'\n')
shutil.copy2(root/'vulkan-upstream.json', contents/'Resources/vulkan-upstream.json')
for name, expected in vulkan_manifest['notices'].items():
    notice = root/'licenses/vulkan'/name
    assert hashlib.sha256(notice.read_bytes()).hexdigest() == expected, notice
    shutil.copy2(notice, contents/'Resources/Licenses'/notice.name)

ps2_engine = contents/'Helpers/ARMSX2.app'
if ps2_engine.exists():
    shutil.rmtree(ps2_engine)
shutil.copytree(root/'vendor/armsx2'/('verified-' + ps2_manifest['sha256'][:16])/ps2_manifest['bundle'], ps2_engine, symlinks=True)
shutil.copy2(root/'Assets/ARMSX2-defaults.ini', contents/'Resources/ARMSX2-defaults.ini')
shutil.copy2(root/'licenses/ARMSX2-GPLv3.txt', contents/'Resources/Licenses/ARMSX2-GPLv3.txt')
shutil.copy2(root/'armsx2-upstream.json', contents/'Resources/armsx2-upstream.json')
(contents/'Resources/Licenses/ARMSX2-SOURCE.txt').write_text(
    'ARMSX2 official unmodified ARM64 build, GPL-3.0-or-later.\n'
    'Corresponding source: https://github.com/ARMSX2/ARMSX2/tree/' + ps2_manifest['revision'] + '\n'
    'Source archive: https://github.com/ARMSX2/ARMSX2/archive/' + ps2_manifest['revision'] + '.tar.gz\n'
    'Build recipe: .github/workflows/macos_build.yml at the same revision.\n'
    'Qt / SDL and other dependency notices are in the engine Resources directory.\n')
ps3_engine = contents/'Helpers/RPCS3.app'
if ps3_engine.exists():
    shutil.rmtree(ps3_engine)
shutil.copytree(root/'vendor/rpcs3'/('verified-' + ps3_manifest['sha256'][:16])/ps3_manifest['bundle'], ps3_engine, symlinks=True)
shutil.copy2(root/'licenses/RPCS3-LICENSE.txt', contents/'Resources/Licenses/RPCS3-LICENSE.txt')
shutil.copy2(root/'rpcs3-upstream.json', contents/'Resources/rpcs3-upstream.json')
(contents/'Resources/Licenses/RPCS3-SOURCE.txt').write_text(
    'RPCS3 official unmodified macOS ARM64 binary, GPL-2.0-only (see LICENSE for exceptions).\n'
    'Corresponding source: https://github.com/RPCS3/rpcs3/tree/' + ps3_manifest['revision'] + '\n'
    'Source archive: ' + ps3_manifest['sourceArchive'] + '\n'
    'Build recipes: .ci/build-mac.sh and .ci/deploy-mac.sh at the same revision.\n'
    'All official bundled frameworks, notices and resources are retained.\n')
shutil.copy2(repo/'LICENSE.TXT' , contents/'Resources/Licenses/PPSSPP-GPL.txt')
subprocess.run(['xcrun','swiftc','-target','arm64-apple-macosx14.0',str(root/'scripts/make-icon.swift'),
                '-o',str(root/'output/make-icon'),'-module-cache-path',str(root/'output/swift-module-cache')], check=True)
subprocess.run([str(root/'output/make-icon'), str(root/'Assets/AppIconParts')], check=True)
iconset = root/'output/AppIcon.iconset'
iconset.mkdir(exist_ok=True)
for size in [16,32,128,256,512]:
    for retina in [1,2]:
        name = f'icon_{size}x{size}'+('@2x' if retina == 2 else '')+'.png'
        shutil.copy2(root/f'Assets/AppIconParts/icon-{size*retina}.png',iconset/name)
icon = root/'Assets/AppIcon.icns'
subprocess.run(['iconutil','-c','icns',str(iconset),'-o',str(icon)],check=True)
for resources in [contents/'Resources',engine/'Contents/Resources']:
    shutil.copy2(icon,resources/'AppIcon.icns')
shutil.copy2(root/'Assets/AppIconParts/icon-1024.png',contents/'Resources/KoalaIcon.png')
shutil.copy2(root/'Assets/AppIconParts/icon-256.png',engine/'Contents/Resources/assets/ui_images/icon.png')
plist = {
    'CFBundleExecutable': 'KoalaPSP', 'CFBundleIdentifier': 'local.koala.psp.native',
    'CFBundleName': 'Koala PSP', 'CFBundleDisplayName': 'Koala PSP', 'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': '0.7.0', 'CFBundleVersion': '10', 'KoalaReleaseVersion': version, 'LSMinimumSystemVersion': '14.0',
    'CFBundleIconFile': 'AppIcon',
    'NSHighResolutionCapable': True,
    'NSHumanReadableCopyright': 'Koala native launcher; PPSSPP GPL-2.0-or-later; ARMSX2 GPL-3.0-or-later; RPCS3 GPL-2.0-only',
}
(contents/'Info.plist').write_bytes(plistlib.dumps(plist))
engine_plist = engine/'Contents/Info.plist'
value = plistlib.loads(engine_plist.read_bytes())
value.update(CFBundleIdentifier='local.koala.psp.native.engine', CFBundleName='Koala PSP Player',
             CFBundleShortVersionString='1.20.4', CFBundleVersion='1.20.4', CFBundleIconFile='AppIcon', LSMinimumSystemVersion='14.0')
engine_plist.write_bytes(plistlib.dumps(value))
subprocess.run(['codesign', '--force', '--deep', '--sign', '-', '--entitlements', str(repo/'macOS/Entitlements.plist'), str(engine)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(ps2_engine)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(ps3_engine)], check=True)
subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
record = {
    'app': str(app), 'version':version, 'architecture': 'arm64', 'launcher': 'SwiftUI/AppKit',
    'engine': 'PPSSPP v1.20.4', 'revision': subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip(),
    'graphics': 'MoltenVK default; optional KosmicKrisp via Vulkan Loader (macOS 26+)', 'vulkan': vulkan_manifest, 'relocatedLibraries': copied,
    'codeSigning': 'local ad-hoc; not notarized',
    'webRuntime': False, 'ps2': ps2_manifest, 'ps3': ps3_manifest,
    'minimumMacOS':'14.0', 'icon':str(icon),
}
archive = root/f'dist/Koala-PSP-{version}-macOS-arm64.zip'
if archive.exists(): archive.unlink()
subprocess.run(['ditto','-c','-k','--sequesterRsrc','--keepParent',str(app),str(archive)],check=True)
record['archive'] = str(archive)
record['archiveSHA256'] = hashlib.sha256(archive.read_bytes()).hexdigest()
(root/'output/build.json').write_text(json.dumps(record, ensure_ascii=False, indent=2)+'\n')
print(app)
