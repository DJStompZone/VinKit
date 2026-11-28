<#
.SYNOPSIS
    Bumps the Flutter app version, builds an obfuscated release AAB, and uploads Dart debug symbols to Firebase Crashlytics.

.DESCRIPTION
    Resolves the project root relative to this script's location, updates the version line in
    pubspec.yaml (defaulting to a patch + build bump), clears stale symbols from
    build/app/outputs/symbols, runs a release appbundle build with obfuscation and split debug
    info, and uploads the resulting symbols to the VinKit Firebase Android app.

.PARAMETER Bump
    Version component to increment in pubspec.yaml: 'patch' (default), 'minor', 'major', 'build', or 'none'.
    All options except 'none' increment the trailing build number (+N).

.PARAMETER SkipUpload
    Builds the release AAB without uploading symbols to Crashlytics.
#>
[CmdletBinding()]
param(
    [ValidateSet('patch', 'minor', 'major', 'build', 'none')]
    [string]$Bump = 'patch',

    [switch]$SkipUpload
)

$ErrorActionPreference = 'Stop'

function Update-PubspecVersion {
    <#
    .SYNOPSIS
        Increments the semantic version and build number in pubspec.yaml in place.

    .DESCRIPTION
        Reads pubspec.yaml using UTF-8 without BOM, locates the top-level version field
        matching X.Y.Z+B, computes the next version for the requested bump type, writes
        the updated file while preserving existing line endings, and returns the new version.

    .PARAMETER Path
        Path to pubspec.yaml.

    .PARAMETER BumpType
        One of 'patch', 'minor', 'major', or 'build'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateSet('patch', 'minor', 'major', 'build')]
        [string]$BumpType
    )

    $resolvedPath = (Resolve-Path -Path $Path).Path
    $content = [System.IO.File]::ReadAllText($resolvedPath)
    $pattern = '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)(?=\r?$)'
    $match = [regex]::Match($content, $pattern)

    if (-not $match.Success) {
        throw "Could not find a 'version: X.Y.Z+B' line in $resolvedPath"
    }

    $major = [int]$match.Groups[1].Value
    $minor = [int]$match.Groups[2].Value
    $patch = [int]$match.Groups[3].Value
    $build = [int]$match.Groups[4].Value
    $oldVersion = "$major.$minor.$patch+$build"

    switch ($BumpType) {
        'major' {
            $major++
            $minor = 0
            $patch = 0
            $build++
        }
        'minor' {
            $minor++
            $patch = 0
            $build++
        }
        'patch' {
            $patch++
            $build++
        }
        'build' {
            $build++
        }
    }

    $newVersion = "$major.$minor.$patch+$build"
    $updatedContent = [regex]::Replace($content, $pattern, "version: $newVersion", 1)
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($resolvedPath, $updatedContent, $utf8NoBom)

    Write-Host "Bumped pubspec.yaml: $oldVersion -> $newVersion"
    return $newVersion
}

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$FirebaseAppId = '1:542221948774:android:5c4d3a2b96b77f745e1aa7'
$SymbolsDir = Join-Path $ProjectRoot 'build/app/outputs/symbols'
$PubspecPath = Join-Path $ProjectRoot 'pubspec.yaml'

Push-Location $ProjectRoot
try {
    if ($Bump -ne 'none') {
        Update-PubspecVersion -Path $PubspecPath -BumpType $Bump | Out-Null
    }

    if (Test-Path $SymbolsDir) {
        Remove-Item -Recurse -Force $SymbolsDir
    }

    flutter build appbundle --release --obfuscate --split-debug-info=$SymbolsDir
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build appbundle failed with exit code $LASTEXITCODE"
    }

    if (-not $SkipUpload) {
        firebase crashlytics:symbols:upload --app=$FirebaseAppId $SymbolsDir
        if ($LASTEXITCODE -ne 0) {
            throw "Crashlytics symbol upload failed with exit code $LASTEXITCODE"
        }
    }
}
finally {
    Pop-Location
}