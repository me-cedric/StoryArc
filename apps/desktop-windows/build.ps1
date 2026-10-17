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
    [string]$Configuration = 'Release',
    # Also make the unsigned MSIX into .build/msix/<Platform> (task 6.7). Off by default: it needs the MSIX tooling of the runner.
    [switch]$Package
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

    if ($Package) {
        # The Store signs the package after submission, so it is built unsigned. Forward slashes with a trailing one:
        # a trailing backslash before a closing quote breaks the native command line.
        $packageDir = "$($root.Path -replace '\\', '/')/.build/msix/$Platform/"
        Invoke-Step "msix $Platform" {
            dotnet build apps/desktop-windows/src/StoryArc.Windows -c $Configuration "-p:Platform=$Platform" -p:GenerateAppxPackageOnBuild=true -p:AppxPackageSigningEnabled=false -p:AppxBundle=Never "-p:AppxPackageDir=$packageDir"
        }
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
