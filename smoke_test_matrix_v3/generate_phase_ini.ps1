param(
  [string]$BaseIni = "smoke_test_matrix_v3/optimization_matrix_best.ini",
  [string]$ConfigPath = "smoke_test_matrix_v3/industry_framework_config.json",
  [string]$OutputDir = "smoke_test_matrix_v3/generated_ini",
  [string]$ReportPrefix = "ptb_industry"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-FileExists([string]$path) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Required file not found: $path"
  }
}

function Set-OrAddIniKV([string[]]$lines, [string]$section, [string]$key, [string]$value) {
  $out = New-Object System.Collections.Generic.List[string]
  $inSection = $false
  $updated = $false
  $sectionFound = $false

  foreach ($line in $lines) {
    $trim = $line.Trim()
    if ($trim -match '^\[(.+)\]$') {
      if ($inSection -and -not $updated) {
        $out.Add("$key=$value")
        $updated = $true
      }
      $curr = $matches[1]
      $inSection = ($curr -eq $section)
      if ($inSection) { $sectionFound = $true }
      $out.Add($line)
      continue
    }

    if ($inSection -and $trim -match ('^{0}\s*=' -f [regex]::Escape($key))) {
      $out.Add("$key=$value")
      $updated = $true
      continue
    }

    $out.Add($line)
  }

  if (-not $sectionFound) {
    $out.Add("")
    $out.Add("[$section]")
    $out.Add("$key=$value")
    return @($out)
  }

  if (-not $updated) {
    $out.Add("$key=$value")
  }

  return @($out)
}

function To-MT5Date([string]$isoDate) {
  try {
    $d = [datetime]::ParseExact($isoDate, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
    return $d.ToString("yyyy.MM.dd")
  } catch {
    throw "Invalid date format '$isoDate'. Expected yyyy-MM-dd."
  }
}

Ensure-FileExists $BaseIni
Ensure-FileExists $ConfigPath
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$config = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json
$baseLines = Get-Content -LiteralPath $BaseIni

$phaseMap = [ordered]@{
  "is" = $config.windows.in_sample
  "oos" = $config.windows.oos
  "forward" = $config.windows.forward
}

foreach ($phase in $phaseMap.Keys) {
  $window = $phaseMap[$phase]
  $fromDate = To-MT5Date $window.from
  $toDate = To-MT5Date $window.to

  $lines = @($baseLines)
  $lines = Set-OrAddIniKV $lines "Tester" "FromDate" $fromDate
  $lines = Set-OrAddIniKV $lines "Tester" "ToDate" $toDate
  $lines = Set-OrAddIniKV $lines "Tester" "ForwardMode" "0"
  $lines = Set-OrAddIniKV $lines "Tester" "Report" ("{0}_{1}" -f $ReportPrefix, $phase)

  $outPath = Join-Path $OutputDir ("optimization_{0}.ini" -f $phase)
  $lines | Out-File -FilePath $outPath -Encoding ascii
}

Write-Host "Phase INI files generated in: $OutputDir"
