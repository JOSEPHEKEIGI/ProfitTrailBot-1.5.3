param(
  [Parameter(Mandatory = $true)]
  [string]$InSampleCsv,
  [Parameter(Mandatory = $true)]
  [string]$OosCsv,
  [Parameter(Mandatory = $true)]
  [string]$ForwardCsv,
  [string]$CandidatesCsv = "smoke_test_matrix_v3/matrix_candidates.csv",
  [string]$OutputRoot = "smoke_test_matrix_v3/results",
  [string]$RunLabel = "",
  [double]$ExecutionThreshold = 73.0,
  [double]$IsMinScore = 70.0,
  [double]$OosMinScore = 65.0,
  [double]$ForwardMinScore = 65.0,
  [double]$OosMinProfitFactor = 1.20,
  [double]$ForwardMinProfitFactor = 1.15,
  [double]$MaxDrawdownPct = 12.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture

function Ensure-FileExists([string]$path) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Required file not found: $path"
  }
}

function Clamp([double]$v, [double]$lo, [double]$hi) {
  if ($v -lt $lo) { return $lo }
  if ($v -gt $hi) { return $hi }
  return $v
}

function Parse-DoubleSafe($raw, [double]$default = 0.0) {
  if ($null -eq $raw) { return $default }
  $text = $raw.ToString().Trim()
  if ($text -eq "") { return $default }
  $text = $text.Replace("%", "").Replace(",", "")
  [double]$val = 0.0
  if ([double]::TryParse($text, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$val)) {
    return $val
  }
  return $default
}

function Parse-BoolSafe($raw, [bool]$default = $false) {
  if ($null -eq $raw) { return $default }
  $text = $raw.ToString().Trim().ToLowerInvariant()
  if ($text -in @("true","1","yes","y","on")) { return $true }
  if ($text -in @("false","0","no","n","off")) { return $false }
  return $default
}

function Get-ColText($row, [string[]]$names, [string]$default = "") {
  foreach ($n in $names) {
    if ($row.PSObject.Properties.Name -contains $n) {
      $raw = $row.$n
      if ($null -ne $raw) {
        $txt = $raw.ToString().Trim()
        if ($txt -ne "") { return $txt }
      }
    }
  }
  return $default
}

function Get-ColDouble($row, [string[]]$names, [double]$default = 0.0) {
  foreach ($n in $names) {
    if ($row.PSObject.Properties.Name -contains $n) {
      $raw = $row.$n
      $val = Parse-DoubleSafe $raw $default
      if ($null -ne $raw -and $raw.ToString().Trim() -ne "") {
        return $val
      }
    }
  }
  return $default
}

function Get-ColBool($row, [string[]]$names, [bool]$default = $false) {
  foreach ($n in $names) {
    if ($row.PSObject.Properties.Name -contains $n) {
      return Parse-BoolSafe $row.$n $default
    }
  }
  return $default
}

function Compute-Score($row, [double]$executionThreshold) {
  $pf = Get-ColDouble $row @("Profit Factor","ProfitFactor") 0.0
  $rf = Get-ColDouble $row @("Recovery Factor","RecoveryFactor") 0.0
  $ep = Get-ColDouble $row @("Expected Payoff","ExpectedPayoff") 0.0
  $dd = Get-ColDouble $row @("Maximal Drawdown %","Max Drawdown %","Drawdown %","MaxDDPct") 100.0
  $tr = [int](Get-ColDouble $row @("Trades","Total Trades") 0.0)
  $sh = Get-ColDouble $row @("Sharpe Ratio","SharpeRatio") 1.0
  $profit = Get-ColDouble $row @("Profit","Net Profit","NetProfit") 0.0
  $deposit = Get-ColDouble $row @("Initial Deposit","Deposit","InitialBalance") 1000.0
  $rrInput = Get-ColDouble $row @("Min_RR_Ratio","Min RR Ratio","MinRRRatio") 1.8
  $riskPct = Get-ColDouble $row @("Risk_Percent","Risk Percent","RiskPercent") 0.7
  $maxSpread = Get-ColDouble $row @("Max_Spread_Pips","Max Spread Pips","MaxSpreadPips") 45.0
  if ($deposit -le 0.0) { $deposit = 1000.0 }
  $profitPct = 100.0 * $profit / $deposit

  $pass = $true
  if ($pf -lt 1.25) { $pass = $false }
  if ($rf -lt 1.40) { $pass = $false }
  if ($ep -le 0.0) { $pass = $false }
  if ($dd -gt 12.0) { $pass = $false }
  if ($tr -lt 40 -or $tr -gt 600) { $pass = $false }
  if ($riskPct -gt 1.20) { $pass = $false }
  if ($rrInput -lt 1.50) { $pass = $false }

  $n_pf = Clamp (($pf - 1.20) / (2.20 - 1.20)) 0.0 1.0
  $n_dd = Clamp ((12.0 - $dd) / (12.0 - 3.0)) 0.0 1.0
  $n_rf = Clamp (($rf - 1.0) / (5.0 - 1.0)) 0.0 1.0
  $n_profit = Clamp ($profitPct / 30.0) 0.0 1.0
  $n_ep = Clamp ($ep / 10.0) 0.0 1.0
  $n_trades = Clamp (1.0 - ([math]::Abs($tr - 180.0) / 180.0)) 0.0 1.0
  $n_sharpe = Clamp ($sh / 2.0) 0.0 1.0
  $n_rr = Clamp (($rrInput - 1.40) / (2.40 - 1.40)) 0.0 1.0
  $n_risk = Clamp ((1.20 - $riskPct) / (1.20 - 0.30)) 0.0 1.0
  $n_spread = Clamp ((55.0 - $maxSpread) / (55.0 - 20.0)) 0.0 1.0

  $score = 0.0
  if ($pass) {
    $score = 15*$n_pf + 15*$n_dd + 12*$n_rf + 10*$n_profit + 10*$n_ep + 8*$n_trades + 8*$n_sharpe + 8*$n_rr + 8*$n_risk + 6*$n_spread
  }

  $decision = "REJECT"
  if ($pass -and $score -ge $executionThreshold) {
    $decision = "EXECUTE"
  }

  return [PSCustomObject]@{
    FinalScore = [math]::Round($score, 2)
    Pass = $pass
    GateDecision = $decision
    ProfitFactor = $pf
    RecoveryFactor = $rf
    MaxDDPct = $dd
    Trades = $tr
    ProfitPct = [math]::Round($profitPct, 2)
    ExpectedPayoff = $ep
    Sharpe = $sh
    RRInput = $rrInput
    RiskPct = $riskPct
    MaxSpreadPips = $maxSpread
  }
}

function Fingerprint-FromRow($row, [string[]]$fields) {
  $parts = New-Object System.Collections.Generic.List[string]
  foreach ($f in $fields) {
    if (-not ($row.PSObject.Properties.Name -contains $f)) {
      $parts.Add("$f=<missing>")
      continue
    }
    $raw = $row.$f
    if ($null -eq $raw) {
      $parts.Add("$f=<null>")
      continue
    }
    if ($raw -is [bool]) {
      $parts.Add("$f=$([bool]$raw)")
      continue
    }
    $text = $raw.ToString().Trim()
    [double]$num = 0.0
    if ([double]::TryParse($text, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$num)) {
      $parts.Add(("{0}={1}" -f $f, $num.ToString("G17", [System.Globalization.CultureInfo]::InvariantCulture)))
      continue
    }
    $boolCandidate = Parse-BoolSafe $text $false
    if ($text.ToLowerInvariant() -in @("true","false","1","0","yes","no","y","n","on","off")) {
      $parts.Add("$f=$boolCandidate")
      continue
    }
    $parts.Add("$f=$($text.ToLowerInvariant())")
  }
  return ($parts -join "|")
}

function Build-CandidateMaps($candidates, [string[]]$matchFields) {
  $byId = @{}
  $byFingerprint = @{}
  foreach ($c in $candidates) {
    $id = $c.id
    if ($null -eq $id -or $id.ToString().Trim() -eq "") {
      throw "Candidate row missing id."
    }
    $idText = $id.ToString().Trim()
    $byId[$idText] = $c
    $fp = Fingerprint-FromRow $c $matchFields
    if (-not $byFingerprint.ContainsKey($fp)) {
      $byFingerprint[$fp] = New-Object System.Collections.Generic.List[string]
    }
    $byFingerprint[$fp].Add($idText)
  }
  return [PSCustomObject]@{
    ById = $byId
    ByFingerprint = $byFingerprint
  }
}

function Map-PhaseRowsToCandidates($phaseName, $rows, $maps, [string[]]$matchFields, [double]$executionThreshold) {
  $bestByCandidate = @{}
  $unmatched = New-Object System.Collections.Generic.List[object]

  foreach ($row in $rows) {
    $candidateIds = New-Object System.Collections.Generic.List[string]
    $idFromRow = Get-ColText $row @("id","ID","candidate_id","CandidateId") ""
    if ($idFromRow -ne "" -and $maps.ById.ContainsKey($idFromRow)) {
      $candidateIds.Add($idFromRow)
    } else {
      $fp = Fingerprint-FromRow $row $matchFields
      if ($maps.ByFingerprint.ContainsKey($fp)) {
        foreach ($mappedId in $maps.ByFingerprint[$fp]) {
          $candidateIds.Add($mappedId)
        }
      }
    }

    if ($candidateIds.Count -eq 0) {
      $unmatched.Add($row)
      continue
    }

    $metrics = Compute-Score $row $executionThreshold
    foreach ($candidateId in $candidateIds) {
      $phaseObj = [PSCustomObject]@{
        CandidateId = $candidateId
        Phase = $phaseName
        FinalScore = $metrics.FinalScore
        Pass = $metrics.Pass
        GateDecision = $metrics.GateDecision
        ProfitFactor = $metrics.ProfitFactor
        RecoveryFactor = $metrics.RecoveryFactor
        MaxDDPct = $metrics.MaxDDPct
        Trades = $metrics.Trades
        ProfitPct = $metrics.ProfitPct
        ExpectedPayoff = $metrics.ExpectedPayoff
        Sharpe = $metrics.Sharpe
        RRInput = $metrics.RRInput
        RiskPct = $metrics.RiskPct
        MaxSpreadPips = $metrics.MaxSpreadPips
        SourceRow = $row
      }

      if (-not $bestByCandidate.ContainsKey($candidateId)) {
        $bestByCandidate[$candidateId] = $phaseObj
        continue
      }

      $old = $bestByCandidate[$candidateId]
      $replace = $false
      if ($phaseObj.FinalScore -gt $old.FinalScore) {
        $replace = $true
      } elseif ($phaseObj.FinalScore -eq $old.FinalScore -and $phaseObj.MaxDDPct -lt $old.MaxDDPct) {
        $replace = $true
      } elseif ($phaseObj.FinalScore -eq $old.FinalScore -and $phaseObj.MaxDDPct -eq $old.MaxDDPct -and $phaseObj.RecoveryFactor -gt $old.RecoveryFactor) {
        $replace = $true
      }

      if ($replace) {
        $bestByCandidate[$candidateId] = $phaseObj
      }
    }
  }

  return [PSCustomObject]@{
    BestByCandidate = $bestByCandidate
    UnmatchedRows = $unmatched
  }
}

function Get-PhaseMetrics($map, [string]$candidateId) {
  if ($map.ContainsKey($candidateId)) {
    return $map[$candidateId]
  }
  return $null
}

function Get-DecisionRank([string]$decision) {
  switch ($decision) {
    "PROMOTE" { return 1 }
    "WATCHLIST" { return 2 }
    "REJECT" { return 3 }
    default { return 4 }
  }
}

Ensure-FileExists $InSampleCsv
Ensure-FileExists $OosCsv
Ensure-FileExists $ForwardCsv
Ensure-FileExists $CandidatesCsv

$candidates = @(Import-Csv -Path $CandidatesCsv)
if (@($candidates).Count -eq 0) {
  throw "No candidates found in $CandidatesCsv"
}

$matchFields = @(
  "Risk_Percent",
  "Min_RR_Ratio",
  "Strategy_Routing_Mode",
  "AI_Signal_Generation_Mode",
  "AI_Trend_Confidence",
  "AI_Buy_Confidence_Threshold",
  "AI_Sell_Confidence_Threshold",
  "AI_Neutral_Band",
  "Require_All_TF_Agreement",
  "Enable_Confluence_Check",
  "Require_FVG_For_Trade",
  "Require_BOS_Confirmation",
  "Require_First_Retracement_After_BOS",
  "Signal_Cooldown_Bars",
  "Max_Spread_Pips",
  "Max_Concurrent_Trades",
  "Max_Trades_Per_Day",
  "Use_Session_Filter",
  "Enable_All_Institutional_Filters_Input"
)

$maps = Build-CandidateMaps $candidates $matchFields

$isRows = Import-Csv -Path $InSampleCsv
$oosRows = Import-Csv -Path $OosCsv
$fwdRows = Import-Csv -Path $ForwardCsv

$isPhase = Map-PhaseRowsToCandidates "IS" $isRows $maps $matchFields $ExecutionThreshold
$oosPhase = Map-PhaseRowsToCandidates "OOS" $oosRows $maps $matchFields $ExecutionThreshold
$fwdPhase = Map-PhaseRowsToCandidates "FORWARD" $fwdRows $maps $matchFields $ExecutionThreshold

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$runToken = if ($RunLabel -ne "") { $RunLabel } else { $timestamp }
$runDir = Join-Path $OutputRoot ("run_" + $runToken)
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$results = New-Object System.Collections.Generic.List[object]

foreach ($c in $candidates) {
  $cid = $c.id.ToString().Trim()
  $is = Get-PhaseMetrics $isPhase.BestByCandidate $cid
  $oos = Get-PhaseMetrics $oosPhase.BestByCandidate $cid
  $fwd = Get-PhaseMetrics $fwdPhase.BestByCandidate $cid

  $hasAll = ($null -ne $is -and $null -ne $oos -and $null -ne $fwd)
  $decision = "MISSING_DATA"
  $reason = "One or more phases missing candidate match"

  $isPass = $false
  $oosPass = $false
  $fwdPass = $false
  $scoreDriftIsOos = 0.0
  $scoreDriftOosFwd = 0.0
  $pfRetentionIsOos = 0.0
  $pfRetentionOosFwd = 0.0

  if ($hasAll) {
    $isPass = ($is.FinalScore -ge $IsMinScore)
    $oosPass = ($oos.FinalScore -ge $OosMinScore -and $oos.ProfitFactor -ge $OosMinProfitFactor -and $oos.MaxDDPct -le $MaxDrawdownPct)
    $fwdPass = ($fwd.FinalScore -ge $ForwardMinScore -and $fwd.ProfitFactor -ge $ForwardMinProfitFactor -and $fwd.MaxDDPct -le $MaxDrawdownPct)

    $scoreDriftIsOos = [math]::Round($is.FinalScore - $oos.FinalScore, 2)
    $scoreDriftOosFwd = [math]::Round($oos.FinalScore - $fwd.FinalScore, 2)
    if ($is.ProfitFactor -gt 0) {
      $pfRetentionIsOos = [math]::Round($oos.ProfitFactor / $is.ProfitFactor, 3)
    }
    if ($oos.ProfitFactor -gt 0) {
      $pfRetentionOosFwd = [math]::Round($fwd.ProfitFactor / $oos.ProfitFactor, 3)
    }

    if ($isPass -and $oosPass -and $fwdPass) {
      $decision = "PROMOTE"
      $reason = "Passed IS/OOS/FORWARD gates"
    } elseif ($isPass -and (($oos.FinalScore -ge ($OosMinScore - 5.0)) -and ($fwd.FinalScore -ge ($ForwardMinScore - 5.0)))) {
      $decision = "WATCHLIST"
      $reason = "Near-threshold OOS/FORWARD performance; monitor stability"
    } else {
      $decision = "REJECT"
      $reason = "Failed OOS/FORWARD promotion gates"
    }
  }

  $results.Add([PSCustomObject]@{
    id = $cid
    profile = $c.profile
    notes = $c.notes
    Decision = $decision
    Reason = $reason
    IsScore = if ($null -ne $is) { $is.FinalScore } else { [double]::NaN }
    OosScore = if ($null -ne $oos) { $oos.FinalScore } else { [double]::NaN }
    ForwardScore = if ($null -ne $fwd) { $fwd.FinalScore } else { [double]::NaN }
    IsProfitFactor = if ($null -ne $is) { $is.ProfitFactor } else { [double]::NaN }
    OosProfitFactor = if ($null -ne $oos) { $oos.ProfitFactor } else { [double]::NaN }
    ForwardProfitFactor = if ($null -ne $fwd) { $fwd.ProfitFactor } else { [double]::NaN }
    IsMaxDDPct = if ($null -ne $is) { $is.MaxDDPct } else { [double]::NaN }
    OosMaxDDPct = if ($null -ne $oos) { $oos.MaxDDPct } else { [double]::NaN }
    ForwardMaxDDPct = if ($null -ne $fwd) { $fwd.MaxDDPct } else { [double]::NaN }
    IsTrades = if ($null -ne $is) { $is.Trades } else { 0 }
    OosTrades = if ($null -ne $oos) { $oos.Trades } else { 0 }
    ForwardTrades = if ($null -ne $fwd) { $fwd.Trades } else { 0 }
    IsPass = $isPass
    OosPass = $oosPass
    ForwardPass = $fwdPass
    ScoreDrift_IS_to_OOS = $scoreDriftIsOos
    ScoreDrift_OOS_to_FORWARD = $scoreDriftOosFwd
    PFRetention_IS_to_OOS = $pfRetentionIsOos
    PFRetention_OOS_to_FORWARD = $pfRetentionOosFwd
  })
}

$sorted = $results | Sort-Object `
  @{Expression={ Get-DecisionRank $_.Decision }; Descending=$false}, `
  @{Expression="OosScore"; Descending=$true}, `
  @{Expression="ForwardScore"; Descending=$true}, `
  @{Expression="OosMaxDDPct"; Descending=$false}

$rankedPath = Join-Path $runDir "oos_forward_ranked.csv"
$promotedPath = Join-Path $runDir "oos_forward_promoted.csv"
$summaryPath = Join-Path $runDir "summary.md"
$manifestPath = Join-Path $runDir "manifest.json"

$sorted | Export-Csv -Path $rankedPath -NoTypeInformation
($sorted | Where-Object { $_.Decision -eq "PROMOTE" }) | Export-Csv -Path $promotedPath -NoTypeInformation

$counts = @{
  Promote = @($sorted | Where-Object { $_.Decision -eq "PROMOTE" }).Count
  Watchlist = @($sorted | Where-Object { $_.Decision -eq "WATCHLIST" }).Count
  Reject = @($sorted | Where-Object { $_.Decision -eq "REJECT" }).Count
  Missing = @($sorted | Where-Object { $_.Decision -eq "MISSING_DATA" }).Count
}

$top = $sorted | Select-Object -First 10
$topLines = @()
foreach ($t in $top) {
  $topLines += ("- {0} ({1}) | decision={2} | IS={3} OOS={4} FWD={5} | PF(OOS/FWD)={6}/{7} | DD(OOS/FWD)={8}/{9}" -f `
    $t.id, $t.profile, $t.Decision, $t.IsScore, $t.OosScore, $t.ForwardScore, `
    $t.OosProfitFactor, $t.ForwardProfitFactor, $t.OosMaxDDPct, $t.ForwardMaxDDPct)
}

$summary = @(
  "# OOS + Forward Performance Summary",
  "",
  "Run: $runToken",
  "",
  "## Decision Counts",
  "",
  "- PROMOTE: $($counts.Promote)",
  "- WATCHLIST: $($counts.Watchlist)",
  "- REJECT: $($counts.Reject)",
  "- MISSING_DATA: $($counts.Missing)",
  "",
  "## Top Candidates",
  ""
) + $topLines + @(
  "",
  "## Artifacts",
  "",
  "- Ranked: oos_forward_ranked.csv",
  "- Promoted: oos_forward_promoted.csv",
  "- Manifest: manifest.json"
)
$summary -join "`r`n" | Out-File -FilePath $summaryPath -Encoding utf8

$manifest = [PSCustomObject]@{
  generated_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  run_label = $runToken
  thresholds = [PSCustomObject]@{
    execution_threshold = $ExecutionThreshold
    is_min_score = $IsMinScore
    oos_min_score = $OosMinScore
    forward_min_score = $ForwardMinScore
    oos_min_profit_factor = $OosMinProfitFactor
    forward_min_profit_factor = $ForwardMinProfitFactor
    max_drawdown_pct = $MaxDrawdownPct
  }
  match_fields = $matchFields
  input_files = @(
    [PSCustomObject]@{ path = $InSampleCsv; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $InSampleCsv).Hash },
    [PSCustomObject]@{ path = $OosCsv; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $OosCsv).Hash },
    [PSCustomObject]@{ path = $ForwardCsv; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $ForwardCsv).Hash },
    [PSCustomObject]@{ path = $CandidatesCsv; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $CandidatesCsv).Hash }
  )
  unmatched_rows = [PSCustomObject]@{
    in_sample = $isPhase.UnmatchedRows.Count
    oos = $oosPhase.UnmatchedRows.Count
    forward = $fwdPhase.UnmatchedRows.Count
  }
  output_files = @(
    "oos_forward_ranked.csv",
    "oos_forward_promoted.csv",
    "summary.md",
    "manifest.json"
  )
}

$manifest | ConvertTo-Json -Depth 8 | Out-File -FilePath $manifestPath -Encoding utf8

Write-Host "OOS+Forward evaluation completed."
Write-Host "Run folder: $runDir"
Write-Host "Ranked output: $rankedPath"
Write-Host "Promoted output: $promotedPath"
