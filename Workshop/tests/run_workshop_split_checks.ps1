$ErrorActionPreference = 'Stop'
$splitRuntime = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies'
& (Join-Path $splitRuntime 'node\bin\node.exe') (Join-Path $PSScriptRoot 'check_workshop_split.cjs')
if ($LASTEXITCODE) { throw 'Workshop split LSL analysis failed' }
& (Join-Path $splitRuntime 'python\python.exe') (Join-Path $PSScriptRoot 'test_workshop_split.py')
if ($LASTEXITCODE) { throw 'Workshop split behavior checks failed' }
& (Join-Path $splitRuntime 'python\python.exe') (Join-Path $PSScriptRoot 'test_idle_session.py')
if ($LASTEXITCODE) { throw 'Workshop idle session checks failed' }
