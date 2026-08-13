<#
.SYNOPSIS
  Create local development files for Windows.

.DESCRIPTION
  Existing local files are preserved. No secret value is generated or committed.
  Firebase configuration is opt-in because it requires Firebase authentication.
#>
[CmdletBinding()]
param(
  [switch]$ConfigureFirebase,
  [switch]$PrintFingerprints,
  [switch]$DryRun,
  [switch]$SkipPubGet,
  [string]$ApiBaseUrl = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$FirebaseProjectId = if ($env:FIREBASE_PROJECT_ID) { $env:FIREBASE_PROJECT_ID } else { "modi-mara" }
$AndroidPackageName = if ($env:ANDROID_PACKAGE_NAME) { $env:ANDROID_PACKAGE_NAME } else { "com.intpsquad.modi" }
$IosBundleId = if ($env:IOS_BUNDLE_ID) { $env:IOS_BUNDLE_ID } else { "com.intpsquad.modi" }

function Write-SetupLog([string]$Message) {
  Write-Host "[setup] $Message"
}

function Write-SetupWarning([string]$Message) {
  Write-Warning "[setup] $Message"
}

function Copy-IfMissing([string]$Source, [string]$Destination) {
  if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
    throw "Template not found: $Source"
  }
  if (Test-Path -LiteralPath $Destination) {
    Write-SetupLog "keep existing $Destination"
    return
  }
  if ($DryRun) {
    Write-SetupLog "[dry-run] copy $Source -> $Destination"
    return
  }
  $parent = Split-Path -Parent $Destination
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  Copy-Item -LiteralPath $Source -Destination $Destination
  Write-SetupLog "created $Destination"
}

function Copy-DevConfig([string]$Source, [string]$Destination) {
  if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
    throw "Template not found: $Source"
  }
  if (Test-Path -LiteralPath $Destination) {
    Write-SetupLog "keep existing $Destination"
    return
  }
  if ($DryRun) {
    if ($ApiBaseUrl) {
      Write-SetupLog "[dry-run] create $Destination with API_BASE_URL=$ApiBaseUrl"
    } else {
      Write-SetupLog "[dry-run] copy $Source -> $Destination"
    }
    return
  }

  $parent = Split-Path -Parent $Destination
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  if (-not $ApiBaseUrl) {
    Copy-Item -LiteralPath $Source -Destination $Destination
    return
  }

  $config = Get-Content -LiteralPath $Source -Raw | ConvertFrom-Json
  $config.API_BASE_URL = $ApiBaseUrl
  $json = $config | ConvertTo-Json -Depth 4
  $utf8NoBom = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
  [System.IO.File]::WriteAllText($Destination, "$json`n", $utf8NoBom)
  Write-SetupLog "created $Destination"
}

function Resolve-FlutterFire {
  $command = Get-Command flutterfire -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $candidates = @(
    (Join-Path $env:LOCALAPPDATA "Pub\Cache\bin\flutterfire.bat"),
    (Join-Path $env:USERPROFILE ".pub-cache\bin\flutterfire.bat")
  )
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      return $candidate
    }
  }
  return $null
}

function Configure-Firebase {
  if ($DryRun) {
    Write-SetupLog "[dry-run] cd app; flutterfire configure --project=$FirebaseProjectId --platforms=android,ios,web --android-package-name=$AndroidPackageName --ios-bundle-id=$IosBundleId --yes"
    return
  }

  if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Flutter is required for Firebase configuration"
  }
  $flutterFire = Resolve-FlutterFire
  if (-not $flutterFire) {
    throw "FlutterFire CLI not found; install flutterfire_cli or add it to PATH"
  }

  Write-SetupLog "run FlutterFire configure for project $FirebaseProjectId"
  Push-Location (Join-Path $RootDir "app")
  try {
    & $flutterFire configure `
      "--project=$FirebaseProjectId" `
      "--platforms=android,ios,web" `
      "--android-package-name=$AndroidPackageName" `
      "--ios-bundle-id=$IosBundleId" `
      "--yes"
    if ($LASTEXITCODE -ne 0) {
      throw "FlutterFire configure failed with exit code $LASTEXITCODE"
    }
  } finally {
    Pop-Location
  }
}

function Print-Fingerprints {
  $gradleWrapper = Join-Path $RootDir "app\android\gradlew.bat"
  if ($DryRun) {
    Write-SetupLog "[dry-run] cd app\android; .\gradlew.bat signingReport"
    return
  }
  if (-not (Test-Path -LiteralPath $gradleWrapper -PathType Leaf)) {
    Write-SetupWarning "Android Gradle wrapper not found: $gradleWrapper"
    return
  }

  Write-SetupLog "print Android debug SHA-1/SHA-256 fingerprints"
  Push-Location (Join-Path $RootDir "app\android")
  try {
    & .\gradlew.bat signingReport
    if ($LASTEXITCODE -ne 0) {
      throw "signingReport failed with exit code $LASTEXITCODE"
    }
  } finally {
    Pop-Location
  }
}

function Test-LocalFiles {
  $paths = @(
    (Join-Path $RootDir "app\env\dev.json"),
    (Join-Path $RootDir "server\.env"),
    (Join-Path $RootDir "ai\.env"),
    (Join-Path $RootDir "app\lib\firebase_options.dart"),
    (Join-Path $RootDir "app\android\app\google-services.json")
  )

  foreach ($path in $paths) {
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      if ($path -like "*google-services.json") {
        $firebaseConfig = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $androidPackages = @($firebaseConfig.client | ForEach-Object { $_.client_info.android_client_info.package_name })
        if ($androidPackages -contains $AndroidPackageName) {
          Write-SetupLog "ready $path ($AndroidPackageName)"
        } else {
          Write-SetupWarning "$path does not contain Android package $AndroidPackageName; run with -ConfigureFirebase"
        }
      } else {
        Write-SetupLog "ready $path"
      }
    } else {
      Write-SetupWarning "missing $path"
    }
  }

  $serviceAccount = Join-Path $RootDir "server\src\main\resources\firebase-service-account.json"
  if (-not (Test-Path -LiteralPath $serviceAccount -PathType Leaf)) {
    Write-SetupWarning "missing $serviceAccount; Firebase-protected API calls will return 401"
  }

  $buildGradle = Join-Path $RootDir "app\android\app\build.gradle.kts"
  $expectedApplicationId = 'applicationId = "' + $AndroidPackageName + '"'
  $packageMatch = Select-String -LiteralPath $buildGradle -Pattern $expectedApplicationId -SimpleMatch
  if (-not $packageMatch) {
    Write-SetupWarning "app/android/app/build.gradle.kts does not use Android package $AndroidPackageName"
  }
}

Write-SetupLog "workspace: $RootDir"
Write-SetupLog "Android package: $AndroidPackageName"
Write-SetupLog "iOS bundle: $IosBundleId"

Copy-IfMissing (Join-Path $RootDir "server\.env.example") (Join-Path $RootDir "server\.env")
Copy-IfMissing (Join-Path $RootDir "ai\.env.example") (Join-Path $RootDir "ai\.env")
Copy-DevConfig (Join-Path $RootDir "app\env\dev.windows.example.json") (Join-Path $RootDir "app\env\dev.json")

if (-not $SkipPubGet) {
  if ($DryRun) {
    Write-SetupLog "[dry-run] cd app; flutter pub get"
  } elseif (Get-Command flutter -ErrorAction SilentlyContinue) {
    Write-SetupLog "run flutter pub get"
    Push-Location (Join-Path $RootDir "app")
    try {
      & flutter pub get
      if ($LASTEXITCODE -ne 0) {
        throw "flutter pub get failed with exit code $LASTEXITCODE"
      }
    } finally {
      Pop-Location
    }
  } else {
    Write-SetupWarning "Flutter not found; skipped flutter pub get"
  }
}

if ($ConfigureFirebase) {
  Configure-Firebase
}

if ($PrintFingerprints) {
  Print-Fingerprints
}

Test-LocalFiles

Write-Host ""
Write-Host "Setup finished. Next steps:"
Write-Host "  1. Fill server\.env and ai\.env with team-provided values."
Write-Host "  2. Add each developer's Android debug SHA-1 in Firebase Console."
Write-Host "  3. Run with -ConfigureFirebase after Firebase fingerprints are updated."
Write-Host "  4. Start dependencies from server/: docker compose up -d"
Write-Host ""
Write-Host "Production deploy/.env is intentionally not created by this developer setup."
