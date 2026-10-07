<#
.SYNOPSIS
  Builds the Rust core, the Windows app and the interop tests.
.EXAMPLE
  pwsh apps/desktop-windows/build.ps1 -Platform x64
#>
[CmdletBinding()]
param(
    [ValidateSet('x64', 'ARM64')]
    [string]$Platform = 'x64',
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
# @() keeps it an array: an if expression unrolls a one-item array into a string, and
# splatting a string passes cargo one character per argument.
$cargoFlags = @(if ($Configuration -eq 'Release') { '--release' })

function Invoke-Step {
    param([string]$Name, [scriptblock]$Command)
    Write-Host "==> $Name"
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "$Name failed with exit code $LASTEXITCODE" }
}

Push-Location $root
try {
    # The host library feeds the interop tests. The app build below makes its own per-platform copy.
    Invoke-Step 'cargo build (host)' { cargo build @cargoFlags -p storyarc-ffi }

    Invoke-Step "dotnet build $Platform" {
        dotnet build apps/desktop-windows/src/StoryArc.Windows -c $Configuration "-p:Platform=$Platform"
    }

    # ponytail: ARM64 libraries do not load on an x64 host, so the tests run only for the host platform.
    if ($Platform -eq 'x64') {
        Invoke-Step 'dotnet test (interop)' {
            dotnet test apps/desktop-windows/tests/StoryArc.Interop.Tests -c $Configuration
        }
    }
}
finally {
    Pop-Location
}
