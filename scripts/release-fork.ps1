param(
   [string]$GameDir = 'D:\SteamLibrary\steamapps\common\ProjectZomboid',
   [Parameter(Mandatory = $true)][string]$JdkBin
)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$out = Join-Path $PWD 'build\fork-release'
New-Item -ItemType Directory -Force $out | Out-Null
$baseline = Join-Path $out 'pzopt-3d39148846-classes.zip'
if (-not (Test-Path -LiteralPath $baseline)) {
   & gh release download b42.22.2-20261111-2036-fad57862 -R xD3I/PZ_Optimization -p pzopt-3d39148846-classes.zip -D $out
   if ($LASTEXITCODE -ne 0) { throw 'Could not download the upstream baseline' }
}
if ((Get-FileHash $baseline -Algorithm SHA256).Hash.ToLower() -ne 'ba125a3f05cc04617c3f49217e1f07e99efe3dfa0ddaa4f34beb5020f35973c4') { throw 'Upstream ZIP hash mismatch' }
$jar = Join-Path $GameDir 'projectzomboid.jar'
if ((Get-FileHash $jar -Algorithm SHA256).Hash.ToLower() -ne '3c4a7c5f149d784758c6fb5f8fa85f3a21d572e38bc081400e89035f8120d287') { throw 'Requires the reviewed Build 42.22.2 game JAR' }
$base = Join-Path $out 'baseline'
Expand-Archive -LiteralPath $baseline -DestinationPath $base -Force
$patch = Join-Path $out 'patch'
New-Item -ItemType Directory -Force $patch | Out-Null
# Reuse the verified upstream payload; compile only the modified source files.
& (Join-Path $JdkBin 'javac.exe') --release 25 -implicit:none -sourcepath (Join-Path $out 'empty') -cp "$base;$base\pzopt\overrides;$jar" -d $patch src/pzopt/pzopt/Darkness.java src/pzopt/pzopt/Updater.java src/pzopt/pzopt/UpscalerDeps.java
if ($LASTEXITCODE -ne 0) { throw 'Patch compilation failed' }
@'
import hashlib, pathlib, re, subprocess, time, zipfile
root = pathlib.Path('build/fork-release')
base = root / 'pzopt-3d39148846-classes.zip'
with zipfile.ZipFile(base) as z:
    files = {n: z.read(n) for n in z.namelist() if not n.endswith('/')}
for p in (root / 'patch').rglob('*.class'):
    files[p.relative_to(root / 'patch').as_posix()] = p.read_bytes()
commit = subprocess.check_output(['git', 'rev-parse', '--short', 'HEAD'], text=True).strip()
info = files['pzopt/build-info.properties'].decode()
info = re.sub(r'^commit=.*$', 'commit=' + commit, info, flags=re.M)
info = re.sub(r'^built=.*$', 'built=' + str(int(time.time())), info, flags=re.M)
files['pzopt/build-info.properties'] = info.encode()
files['pzopt-files.txt'] = ('\n'.join(sorted(files)) + '\n').encode()
out = root / 'release' / base.name
out.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for name, data in sorted(files.items()):
        z.writestr(name, data)
print(out, 'entries=' + str(len(files)), 'sha256=' + hashlib.sha256(out.read_bytes()).hexdigest())
'@ | python
if ($LASTEXITCODE -ne 0) { throw 'Release packaging failed' }
foreach ($name in @('install.ps1', 'install.sh', 'uninstall.ps1', 'uninstall.sh')) {
   Copy-Item -LiteralPath $name -Destination (Join-Path $out "release\$name")
}
