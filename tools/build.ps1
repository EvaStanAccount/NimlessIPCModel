param(
  [ValidateSet('debug','inspect','release')][string]$Mode = 'debug',
  [ValidateSet('all','server','client','tests')][string]$Target = 'all'
)

$Root = Split-Path -Parent $PSScriptRoot
$Out = Join-Path $Root "build\$Mode"
New-Item -ItemType Directory -Force -Path $Out | Out-Null

$Common = @('-d:mingw')
switch ($Mode) {
  'debug' { $Common += @('-d:debug') }
  'inspect' { $Common += @('-d:debug','--lineDir:on') }
  'release' { $Common += @('--t:-s','--l:-Wl,-s') }
}

function Build-One([string]$Name, [string]$Source) {
  $srcPath = Join-Path $Root $Source
  $outPath = Join-Path $Out "$Name.exe"
  & nim c @Common "-o:$outPath" $srcPath
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

switch ($Target) {
  'all' {
    Build-One 'named-pipe-server' 'src\server.nim'
    Build-One 'named-pipe-client' 'src\client.nim'
    Build-One 'protocol-tests' 'tests\protocol_tests.nim'
  }
  'server' { Build-One 'named-pipe-server' 'src\server.nim' }
  'client' { Build-One 'named-pipe-client' 'src\client.nim' }
  'tests' { Build-One 'protocol-tests' 'tests\protocol_tests.nim' }
}

Write-Host "built $Mode $Target in $Out"
