param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,

    [ValidateSet("patch", "minor", "major")]
    [string]$Bump = "patch",

    [string]$Remote = "origin",
    [string]$Branch = "main",
    [switch]$SkipPush,
    [switch]$AllowDirty
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

function Get-VersionFromTag($tagName) {
    if ($tagName -match '^v?(\d+)\.(\d+)\.(\d+)$') {
        return [version]"$($matches[1]).$($matches[2]).$($matches[3])"
    }
    return $null
}

function Get-NextVersion([string]$bump) {
    $versions = New-Object System.Collections.Generic.List[version]

    git tag --list "v*" | ForEach-Object {
        $parsed = Get-VersionFromTag $_
        if ($parsed) {
            $versions.Add($parsed)
        }
    }

    git ls-remote --tags $Remote "refs/tags/v*" | ForEach-Object {
        $parts = $_ -split "\s+"
        if ($parts.Count -ge 2) {
            $name = ($parts[1] -replace '^refs/tags/', '') -replace '\^\{\}$', ''
            $parsed = Get-VersionFromTag $name
            if ($parsed) {
                $versions.Add($parsed)
            }
        }
    }

    if ($versions.Count -eq 0) {
        return "0.1.0"
    }

    $latest = $versions | Sort-Object -Descending | Select-Object -First 1
    switch ($bump) {
        "major" { return "$($latest.Major + 1).0.0" }
        "minor" { return "$($latest.Major).$($latest.Minor + 1).0" }
        default { return "$($latest.Major).$($latest.Minor).$($latest.Build + 1)" }
    }
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Get-NextVersion $Bump
    Write-Host "Auto version: $Version ($Bump bump)" -ForegroundColor Green
} else {
    Write-Host "Manual version: $Version" -ForegroundColor Green
}

$tag = "v$Version"
$groupId = "com.github.wukuiqing49"
$artifactId = "AndroidCoreNetwork"
$dependencyWithTag = "$groupId`:$artifactId`:$tag"
$dependencyWithoutTag = "$groupId`:$artifactId`:$Version"

function Run($command) {
    Write-Host ">> $command" -ForegroundColor Cyan
    Invoke-Expression $command
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $command"
    }
}

function Replace-InFile($path, [scriptblock]$replace) {
    if (-not (Test-Path $path)) {
        return
    }
    $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $updated = & $replace $content
    if ($updated -ne $content) {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText((Resolve-Path $path), $updated, $utf8NoBom)
        Write-Host "updated $path"
    }
}

$existingTag = git tag --list $tag
if ($existingTag) {
    throw "Tag $tag already exists locally. Choose a new version or delete the tag intentionally."
}

$remoteTag = git ls-remote --tags $Remote "refs/tags/$tag"
if ($remoteTag) {
    throw "Tag $tag already exists on $Remote. Choose a new version."
}

$statusBefore = git status --porcelain
if ($statusBefore -and -not $AllowDirty) {
    Write-Host "Working tree has uncommitted changes:" -ForegroundColor Yellow
    git status --short
    throw "Re-run with -AllowDirty to include current changes in the release commit."
}

Replace-InFile "README.md" {
    param($content)
    $content `
        -replace 'com\.github\.wukuiqing49:AndroidCoreNetwork:v\d+\.\d+\.\d+', $dependencyWithTag `
        -replace 'com\.github\.wukuiqing49:AndroidCoreNetwork:\d+\.\d+\.\d+', $dependencyWithoutTag `
        -replace 'com\.github\.wukuiqing49\.AndroidCoreNetwork:core_network:v\d+\.\d+\.\d+', $dependencyWithTag `
        -replace 'com\.github\.wukuiqing49\.AndroidCoreNetwork:core_network:\d+\.\d+\.\d+', $dependencyWithoutTag `
        -replace 'v\d+\.\d+\.\d+', $tag `
        -replace 'POM_VERSION=\d+\.\d+\.\d+', "POM_VERSION=$Version"
}

Replace-InFile "core_network/docs/core_network_publish.md" {
    param($content)
    $content `
        -replace 'com\.github\.wukuiqing49:AndroidCoreNetwork:v\d+\.\d+\.\d+', $dependencyWithTag `
        -replace 'com\.github\.wukuiqing49:AndroidCoreNetwork:\d+\.\d+\.\d+', $dependencyWithoutTag `
        -replace 'com\.github\.wukuiqing49\.AndroidCoreNetwork:core_network:v\d+\.\d+\.\d+', $dependencyWithTag `
        -replace 'com\.github\.wukuiqing49\.AndroidCoreNetwork:core_network:\d+\.\d+\.\d+', $dependencyWithoutTag `
        -replace 'v\d+\.\d+\.\d+', $tag `
        -replace 'POM_VERSION=\d+\.\d+\.\d+', "POM_VERSION=$Version" `
        -replace 'release core_network \d+\.\d+\.\d+', "release core_network $Version"
}

Replace-InFile "app/build.gradle" {
    param($content)
    $content `
        -replace 'com\.github\.wukuiqing49:AndroidCoreNetwork:v\d+\.\d+\.\d+', $dependencyWithTag `
        -replace 'com\.github\.wukuiqing49\.AndroidCoreNetwork:core_network:v\d+\.\d+\.\d+', $dependencyWithTag
}

Run ".\gradlew.bat :core_network:compileDebugKotlin"
Run ".\gradlew.bat :app:assembleDebug -PUSE_LOCAL_CORE_NETWORK=true"
Run ".\gradlew.bat :core_network:publishReleasePublicationToMavenLocal `"-PPOM_GROUP_ID=$groupId`" `"-PPOM_VERSION=$Version`""

$statusAfter = git status --porcelain
if (-not $statusAfter) {
    throw "No changes to release."
}

Run "git add README.md app/build.gradle settings.gradle core_network/build.gradle core_network/docs/core_network_publish.md jitpack.yml scripts/release-core-network.ps1"
Run "git commit -m `"release core_network $Version`""
Run "git tag $tag"

if (-not $SkipPush) {
    Run "git push $Remote $Branch"
    Run "git push $Remote $tag"
}

Write-Host ""
Write-Host "Release prepared: $tag" -ForegroundColor Green
Write-Host "JitPack: https://jitpack.io/#wukuiqing49/AndroidCoreNetwork/$tag"
Write-Host "Dependency: implementation `"$dependencyWithTag`""
