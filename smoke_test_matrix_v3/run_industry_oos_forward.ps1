param(
  [Parameter(Mandatory = $true)]
  [string]$InSampleCsv,
  [Parameter(Mandatory = $true)]
  [string]$OosCsv,
  [Parameter(Mandatory = $true)]
  [string]$ForwardCsv,
  [string]$ConfigPath = "smoke_test_matrix_v3/industry_framework_config.json",
  [string]$CandidatesCsv = "smoke_test_matrix_v3/matrix_candidates.csv",
  [string]$OutputRoot = "smoke_test_matrix_v3/industry_results",
  [string]$RunLabel = ""
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

function Get-Array($value) {
  if ($null -eq $value) { return @() }
  return @($value)
}

function Get-AliasMap($config) {
  $map = @{}
  foreach ($p in $config.column_aliases.PSObject.Properties) {
    $map[$p.Name] = @(Get-Array $p.Value)
  }
  return $map
}

function Get-ColumnHeaders($rows) {
  if (@($rows).Count -eq 0) {
    return @()
  }
  return @($rows[0].PSObject.Properties.Name)
}

function Has-AnyAliasHeader([string[]]$headers, [string[]]$aliases) {
  foreach ($a in @($aliases)) {
    if ($headers -contains $a) {
      return $true
    }
  }
  return $false
}

function Get-ColText($row, [string[]]$aliases, [string]$default = "") {
  foreach ($a in $aliases) {
    if ($row.PSObject.Properties.Name -contains $a) {
      $raw = $row.$a
      if ($null -ne $raw) {
        $txt = $raw.ToString().Trim()
        if ($txt -ne "") { return $txt }
      }
    }
  }
  return $default
}

function Get-ColDouble($row, [string[]]$aliases, [double]$default = 0.0) {
  foreach ($a in $aliases) {
    if ($row.PSObject.Properties.Name -contains $a) {
      $raw = $row.$a
      if ($null -ne $raw -and $raw.ToString().Trim() -ne "") {
        return Parse-DoubleSafe $raw $default
      }
    }
  }
  return $default
}

function Get-Quantile([double[]]$values, [double]$q) {
  $arr = @($values | Where-Object { [double]::IsNaN($_) -eq $false })
  if (@($arr).Count -eq 0) {
    return [double]::NaN
  }
  $sorted = @($arr | Sort-Object)
  if (@($sorted).Count -eq 1) {
    return [double]$sorted[0]
  }
  $qq = Clamp $q 0.0 1.0
  $pos = ($sorted.Count - 1) * $qq
  $lo = [int][math]::Floor($pos)
  $hi = [int][math]::Ceiling($pos)
  if ($lo -eq $hi) {
    return [double]$sorted[$lo]
  }
  $w = $pos - $lo
  return [double]$sorted[$lo] + ([double]$sorted[$hi] - [double]$sorted[$lo]) * $w
}

function Get-Mean([double[]]$values) {
  $arr = @($values)
  if (@($arr).Count -eq 0) { return [double]::NaN }
  $sum = 0.0
  foreach ($v in $arr) { $sum += $v }
  return $sum / $arr.Count
}

function Normalize-Fingerprint($row, [string[]]$fields) {
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
    $txt = $raw.ToString().Trim()
    [double]$num = 0.0
    if ([double]::TryParse($txt, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$num)) {
      $parts.Add(("{0}={1}" -f $f, $num.ToString("G17", [System.Globalization.CultureInfo]::InvariantCulture)))
      continue
    }
    if ($txt.ToLowerInvariant() -in @("true","false","1","0","yes","no","y","n","on","off")) {
      $parts.Add("$f=$(Parse-BoolSafe $txt $false)")
      continue
    }
    $parts.Add("$f=$($txt.ToLowerInvariant())")
  }
  return ($parts -join "|")
}

function Build-CandidateMaps($candidates, [string[]]$matchFields, [string[]]$idAliases) {
  $byId = @{}
  $byFingerprint = @{}
  $fingerprintCollisions = New-Object System.Collections.Generic.List[string]

  foreach ($c in $candidates) {
    $cid = Get-ColText $c $idAliases ""
    if ($cid -eq "") {
      throw "Candidate row missing id column."
    }
    if ($byId.ContainsKey($cid)) {
      throw "Duplicate candidate id detected: $cid"
    }
    $byId[$cid] = $c

    $fp = Normalize-Fingerprint $c $matchFields
    if (-not $byFingerprint.ContainsKey($fp)) {
      $byFingerprint[$fp] = New-Object System.Collections.Generic.List[string]
    } else {
      $fingerprintCollisions.Add("Fingerprint collision for id '$cid' and '$($byFingerprint[$fp] -join ",")'")
    }
    $byFingerprint[$fp].Add($cid)
  }

  return [PSCustomObject]@{
    ById = $byId
    ByFingerprint = $byFingerprint
    FingerprintCollisions = $fingerprintCollisions
  }
}

function Validate-PhaseContract([string]$phaseName, $rows, $aliasMap, [string[]]$requiredMetrics) {
  $issues = New-Object System.Collections.Generic.List[string]
  if (@($rows).Count -eq 0) {
    $issues.Add("${phaseName}: CSV has no rows")
    return $issues
  }

  $headers = Get-ColumnHeaders $rows
  foreach ($metric in $requiredMetrics) {
    if (-not $aliasMap.ContainsKey($metric)) {
      $issues.Add("${phaseName}: missing alias definition for metric '$metric' in config")
      continue
    }
    $aliases = @($aliasMap[$metric])
    $found = $false
    foreach ($a in $aliases) {
      if ($headers -contains $a) {
        $found = $true
        break
      }
    }
    if (-not $found) {
      $issues.Add("${phaseName}: missing required metric '$metric' (aliases: $($aliases -join ', '))")
    }
  }
  return $issues
}

function Compute-RowMetrics($row, $config, $aliasMap) {
  $pf = Get-ColDouble $row $aliasMap["profit_factor"] 0.0
  $rf = Get-ColDouble $row $aliasMap["recovery_factor"] 0.0
  $ep = Get-ColDouble $row $aliasMap["expected_payoff"] 0.0
  $dd = Get-ColDouble $row $aliasMap["max_drawdown_pct"] 100.0
  $tr = [int](Get-ColDouble $row $aliasMap["trades"] 0.0)
  $sh = Get-ColDouble $row $aliasMap["sharpe"] 1.0
  $profit = Get-ColDouble $row $aliasMap["net_profit"] 0.0
  $deposit = Get-ColDouble $row $aliasMap["initial_deposit"] 1000.0
  $rr = Get-ColDouble $row $aliasMap["min_rr_ratio"] 1.8
  $risk = Get-ColDouble $row $aliasMap["risk_percent"] 0.7
  $spread = Get-ColDouble $row $aliasMap["max_spread_pips"] 45.0

  if ($deposit -le 0.0) { $deposit = 1000.0 }
  $profitPct = 100.0 * $profit / $deposit

  $hg = $config.hard_gates
  $hardPass = $true
  if ($pf -lt [double]$hg.profit_factor_min) { $hardPass = $false }
  if ($rf -lt [double]$hg.recovery_factor_min) { $hardPass = $false }
  if ($ep -le [double]$hg.expected_payoff_min) { $hardPass = $false }
  if ($dd -gt [double]$hg.max_drawdown_pct_max) { $hardPass = $false }
  if ($tr -lt [int]$hg.trades_min -or $tr -gt [int]$hg.trades_max) { $hardPass = $false }
  if ($risk -gt [double]$hg.risk_percent_max) { $hardPass = $false }
  if ($rr -lt [double]$hg.min_rr_ratio_min) { $hardPass = $false }

  $nr = $config.score_normalization
  $nw = $config.score_weights
  $n_pf = Clamp (($pf - [double]$nr.profit_factor_min) / ([double]$nr.profit_factor_max - [double]$nr.profit_factor_min)) 0.0 1.0
  $n_dd = Clamp (([double]$nr.drawdown_worst - $dd) / ([double]$nr.drawdown_worst - [double]$nr.drawdown_best)) 0.0 1.0
  $n_rf = Clamp (($rf - [double]$nr.recovery_factor_min) / ([double]$nr.recovery_factor_max - [double]$nr.recovery_factor_min)) 0.0 1.0
  $n_profit = Clamp ($profitPct / [double]$nr.net_profit_pct_target) 0.0 1.0
  $n_ep = Clamp ($ep / [double]$nr.expected_payoff_target) 0.0 1.0
  $n_trades = Clamp (1.0 - ([math]::Abs($tr - [double]$nr.trades_target) / [double]$nr.trades_target)) 0.0 1.0
  $n_sharpe = Clamp ($sh / [double]$nr.sharpe_target) 0.0 1.0
  $n_rr = Clamp (($rr - [double]$nr.rr_min) / ([double]$nr.rr_max - [double]$nr.rr_min)) 0.0 1.0
  $n_risk = Clamp (([double]$nr.risk_worst - $risk) / ([double]$nr.risk_worst - [double]$nr.risk_best)) 0.0 1.0
  $n_spread = Clamp (([double]$nr.spread_worst - $spread) / ([double]$nr.spread_worst - [double]$nr.spread_best)) 0.0 1.0

  $score = 0.0
  if ($hardPass) {
    $score =
      [double]$nw.profit_factor * $n_pf +
      [double]$nw.drawdown * $n_dd +
      [double]$nw.recovery_factor * $n_rf +
      [double]$nw.net_profit_pct * $n_profit +
      [double]$nw.expected_payoff * $n_ep +
      [double]$nw.trades * $n_trades +
      [double]$nw.sharpe * $n_sharpe +
      [double]$nw.rr_input * $n_rr +
      [double]$nw.risk_pct * $n_risk +
      [double]$nw.spread * $n_spread
  }

  return [PSCustomObject]@{
    HardPass = $hardPass
    FinalScore = [math]::Round($score, 2)
    ProfitFactor = $pf
    RecoveryFactor = $rf
    ExpectedPayoff = $ep
    MaxDDPct = $dd
    Trades = $tr
    Sharpe = $sh
    ProfitPct = [math]::Round($profitPct, 2)
    RRInput = $rr
    RiskPct = $risk
    MaxSpreadPips = $spread
  }
}

function Map-PhaseRows($phaseName, $rows, $maps, [string[]]$matchFields, $aliasMap, $config) {
  $runsByCandidate = @{}
  $unmatchedRows = New-Object System.Collections.Generic.List[object]
  $ambiguousRows = New-Object System.Collections.Generic.List[object]
  $fallbackMatchCount = 0

  foreach ($row in $rows) {
    $candidateIds = New-Object System.Collections.Generic.List[string]
    $idFromRow = Get-ColText $row $aliasMap["id"] ""
    if ($idFromRow -ne "" -and $maps.ById.ContainsKey($idFromRow)) {
      $candidateIds.Add($idFromRow)
    } else {
      $fp = Normalize-Fingerprint $row $matchFields
      if ($maps.ByFingerprint.ContainsKey($fp)) {
        $matchedIds = @($maps.ByFingerprint[$fp])
        if (@($matchedIds).Count -eq 1) {
          $candidateIds.Add($matchedIds[0])
          $fallbackMatchCount++
        } elseif (@($matchedIds).Count -gt 1) {
          $ambiguousRows.Add([PSCustomObject]@{
            phase = $phaseName
            fingerprint = $fp
            candidate_ids = ($matchedIds -join ",")
          })
          $unmatchedRows.Add($row)
          continue
        }
      }
    }

    if ($candidateIds.Count -eq 0) {
      $unmatchedRows.Add($row)
      continue
    }

    $metrics = Compute-RowMetrics $row $config $aliasMap
    foreach ($cid in $candidateIds) {
      if (-not $runsByCandidate.ContainsKey($cid)) {
        $runsByCandidate[$cid] = New-Object System.Collections.Generic.List[object]
      }
      $runsByCandidate[$cid].Add([PSCustomObject]@{
        Phase = $phaseName
        CandidateId = $cid
        Metrics = $metrics
        SourceRow = $row
      })
    }
  }

  return [PSCustomObject]@{
    RunsByCandidate = $runsByCandidate
    UnmatchedRows = $unmatchedRows
    AmbiguousRows = $ambiguousRows
    FallbackMatchCount = $fallbackMatchCount
  }
}

function Aggregate-PhaseRuns($runs, $aggregationCfg) {
  $runArr = @(Get-Array $runs)
  if ($runArr.Count -eq 0) {
    return $null
  }

  [double[]]$scores = @($runArr | ForEach-Object { [double]$_.Metrics.FinalScore })
  [double[]]$pfs = @($runArr | ForEach-Object { [double]$_.Metrics.ProfitFactor })
  [double[]]$dds = @($runArr | ForEach-Object { [double]$_.Metrics.MaxDDPct })
  [double[]]$trades = @($runArr | ForEach-Object { [double]$_.Metrics.Trades })
  [double[]]$pass01 = @($runArr | ForEach-Object { if ($_.Metrics.HardPass) { 1.0 } else { 0.0 } })

  $scoreAgg = Get-Quantile $scores ([double]$aggregationCfg.score_quantile)
  $pfAgg = Get-Quantile $pfs ([double]$aggregationCfg.pf_quantile)
  $ddAgg = Get-Quantile $dds ([double]$aggregationCfg.dd_quantile)
  $tradesAgg = Get-Quantile $trades ([double]$aggregationCfg.trades_quantile)
  $passRate = Get-Mean $pass01

  return [PSCustomObject]@{
    RunCount = $runArr.Count
    ScoreAgg = [math]::Round($scoreAgg, 2)
    ProfitFactorAgg = [math]::Round($pfAgg, 4)
    MaxDDPctAgg = [math]::Round($ddAgg, 4)
    TradesAgg = [int][math]::Round($tradesAgg, 0)
    PassRate = [math]::Round($passRate, 4)
    BestScore = [math]::Round((@($scores | Measure-Object -Maximum).Maximum), 2)
    WorstScore = [math]::Round((@($scores | Measure-Object -Minimum).Minimum), 2)
  }
}

function Get-RunsForCandidate([hashtable]$runsByCandidate, [string]$candidateId) {
  if ($null -eq $runsByCandidate -or $candidateId -eq "") {
    return @()
  }
  if (-not $runsByCandidate.ContainsKey($candidateId)) {
    return @()
  }
  $v = $runsByCandidate[$candidateId]
  if ($null -eq $v) {
    return @()
  }
  if ($v -is [System.Collections.Generic.List[object]]) {
    return $v.ToArray()
  }
  if ($v -is [System.Array]) {
    return $v
  }
  if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) {
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($item in $v) { $out.Add($item) }
    return $out.ToArray()
  }
  return ,$v
}

function Evaluate-PhaseGate([string]$phaseName, $agg, $config) {
  if ($null -eq $agg) {
    return [PSCustomObject]@{ Pass = $false; Reason = "$phaseName missing aggregated metrics" }
  }

  $minRuns = [int]$config.aggregation.min_runs_per_phase
  if ($agg.RunCount -lt $minRuns) {
    return [PSCustomObject]@{ Pass = $false; Reason = "$phaseName insufficient runs ($($agg.RunCount)/$minRuns)" }
  }

  $g = $config.promotion_gates
  $phasePass = $true
  $why = New-Object System.Collections.Generic.List[string]

  if ($phaseName -eq "IS") {
    if ($agg.ScoreAgg -lt [double]$g.is_min_score) {
      $phasePass = $false
      $why.Add("score<$($g.is_min_score)")
    }
  } elseif ($phaseName -eq "OOS") {
    if ($agg.ScoreAgg -lt [double]$g.oos_min_score) {
      $phasePass = $false
      $why.Add("score<$($g.oos_min_score)")
    }
    if ($agg.ProfitFactorAgg -lt [double]$g.oos_min_profit_factor) {
      $phasePass = $false
      $why.Add("pf<$($g.oos_min_profit_factor)")
    }
    if ($agg.MaxDDPctAgg -gt [double]$g.oos_max_drawdown_pct) {
      $phasePass = $false
      $why.Add("dd>$($g.oos_max_drawdown_pct)")
    }
  } elseif ($phaseName -eq "FORWARD") {
    if ($agg.ScoreAgg -lt [double]$g.forward_min_score) {
      $phasePass = $false
      $why.Add("score<$($g.forward_min_score)")
    }
    if ($agg.ProfitFactorAgg -lt [double]$g.forward_min_profit_factor) {
      $phasePass = $false
      $why.Add("pf<$($g.forward_min_profit_factor)")
    }
    if ($agg.MaxDDPctAgg -gt [double]$g.forward_max_drawdown_pct) {
      $phasePass = $false
      $why.Add("dd>$($g.forward_max_drawdown_pct)")
    }
  } else {
    $phasePass = $false
    $why.Add("unknown phase")
  }

  if ($agg.PassRate -lt [double]$g.min_phase_pass_rate) {
    $phasePass = $false
    $why.Add("pass_rate<$($g.min_phase_pass_rate)")
  }

  if ($phasePass) {
    return [PSCustomObject]@{ Pass = $true; Reason = "OK" }
  }
  return [PSCustomObject]@{ Pass = $false; Reason = ($why -join "|") }
}

function Get-DecisionRank([string]$decision) {
  switch ($decision) {
    "PROMOTE" { return 1 }
    "WATCHLIST" { return 2 }
    "REJECT" { return 3 }
    "INSUFFICIENT_DATA" { return 4 }
    default { return 5 }
  }
}

Ensure-FileExists $ConfigPath
Ensure-FileExists $CandidatesCsv
Ensure-FileExists $InSampleCsv
Ensure-FileExists $OosCsv
Ensure-FileExists $ForwardCsv

$config = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json
$aliasMap = Get-AliasMap $config

$candidates = @(Import-Csv -LiteralPath $CandidatesCsv)
$isRows = @(Import-Csv -LiteralPath $InSampleCsv)
$oosRows = @(Import-Csv -LiteralPath $OosCsv)
$fwdRows = @(Import-Csv -LiteralPath $ForwardCsv)

$isHeaders = Get-ColumnHeaders $isRows
$oosHeaders = Get-ColumnHeaders $oosRows
$fwdHeaders = Get-ColumnHeaders $fwdRows
$idAliases = @($aliasMap["id"])
$isHasIdHeader = Has-AnyAliasHeader $isHeaders $idAliases
$oosHasIdHeader = Has-AnyAliasHeader $oosHeaders $idAliases
$fwdHasIdHeader = Has-AnyAliasHeader $fwdHeaders $idAliases
$allPhasesHaveId = ($isHasIdHeader -and $oosHasIdHeader -and $fwdHasIdHeader)

$requiredMetrics = @(
  "profit_factor",
  "recovery_factor",
  "expected_payoff",
  "max_drawdown_pct",
  "trades",
  "net_profit",
  "initial_deposit",
  "min_rr_ratio",
  "risk_percent",
  "max_spread_pips"
)

$contractIssues = New-Object System.Collections.Generic.List[string]
foreach ($issue in @(Validate-PhaseContract "IS" $isRows $aliasMap $requiredMetrics)) { $contractIssues.Add($issue) }
foreach ($issue in @(Validate-PhaseContract "OOS" $oosRows $aliasMap $requiredMetrics)) { $contractIssues.Add($issue) }
foreach ($issue in @(Validate-PhaseContract "FORWARD" $fwdRows $aliasMap $requiredMetrics)) { $contractIssues.Add($issue) }

if ($contractIssues.Count -gt 0) {
  $msg = "Input contract validation failed:`n - " + ($contractIssues -join "`n - ")
  throw $msg
}

$matchFields = @(Get-Array $config.matching_fields)
$maps = Build-CandidateMaps $candidates $matchFields $aliasMap["id"]

$isPhase = Map-PhaseRows "IS" $isRows $maps $matchFields $aliasMap $config
$oosPhase = Map-PhaseRows "OOS" $oosRows $maps $matchFields $aliasMap $config
$fwdPhase = Map-PhaseRows "FORWARD" $fwdRows $maps $matchFields $aliasMap $config

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$runToken = if ($RunLabel -ne "") { $RunLabel } else { $timestamp }
$runDir = Join-Path $OutputRoot ("run_" + $runToken)
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$decisionBoard = New-Object System.Collections.Generic.List[object]
$phaseCoverage = New-Object System.Collections.Generic.List[object]

foreach ($candidate in $candidates) {
  [string]$cid = [string](Get-ColText $candidate $aliasMap["id"] "")
  $profile = Get-ColText $candidate @("profile") ""
  $notes = Get-ColText $candidate @("notes") ""

  $isRuns = Get-RunsForCandidate $isPhase.RunsByCandidate $cid
  $oosRuns = Get-RunsForCandidate $oosPhase.RunsByCandidate $cid
  $fwdRuns = Get-RunsForCandidate $fwdPhase.RunsByCandidate $cid

  $isAgg = Aggregate-PhaseRuns $isRuns $config.aggregation
  $oosAgg = Aggregate-PhaseRuns $oosRuns $config.aggregation
  $fwdAgg = Aggregate-PhaseRuns $fwdRuns $config.aggregation

  $phaseCoverage.Add([PSCustomObject]@{
    id = $cid; phase = "IS"; run_count = if ($null -ne $isAgg) { $isAgg.RunCount } else { 0 }
    score_agg = if ($null -ne $isAgg) { $isAgg.ScoreAgg } else { [double]::NaN }
    pf_agg = if ($null -ne $isAgg) { $isAgg.ProfitFactorAgg } else { [double]::NaN }
    dd_agg = if ($null -ne $isAgg) { $isAgg.MaxDDPctAgg } else { [double]::NaN }
    pass_rate = if ($null -ne $isAgg) { $isAgg.PassRate } else { [double]::NaN }
  })
  $phaseCoverage.Add([PSCustomObject]@{
    id = $cid; phase = "OOS"; run_count = if ($null -ne $oosAgg) { $oosAgg.RunCount } else { 0 }
    score_agg = if ($null -ne $oosAgg) { $oosAgg.ScoreAgg } else { [double]::NaN }
    pf_agg = if ($null -ne $oosAgg) { $oosAgg.ProfitFactorAgg } else { [double]::NaN }
    dd_agg = if ($null -ne $oosAgg) { $oosAgg.MaxDDPctAgg } else { [double]::NaN }
    pass_rate = if ($null -ne $oosAgg) { $oosAgg.PassRate } else { [double]::NaN }
  })
  $phaseCoverage.Add([PSCustomObject]@{
    id = $cid; phase = "FORWARD"; run_count = if ($null -ne $fwdAgg) { $fwdAgg.RunCount } else { 0 }
    score_agg = if ($null -ne $fwdAgg) { $fwdAgg.ScoreAgg } else { [double]::NaN }
    pf_agg = if ($null -ne $fwdAgg) { $fwdAgg.ProfitFactorAgg } else { [double]::NaN }
    dd_agg = if ($null -ne $fwdAgg) { $fwdAgg.MaxDDPctAgg } else { [double]::NaN }
    pass_rate = if ($null -ne $fwdAgg) { $fwdAgg.PassRate } else { [double]::NaN }
  })

  $decision = "INSUFFICIENT_DATA"
  $reason = "Missing one or more phases"

  $isGate = Evaluate-PhaseGate "IS" $isAgg $config
  $oosGate = Evaluate-PhaseGate "OOS" $oosAgg $config
  $fwdGate = Evaluate-PhaseGate "FORWARD" $fwdAgg $config

  $hasAllPhases = ($null -ne $isAgg -and $null -ne $oosAgg -and $null -ne $fwdAgg)

  $pfRetIsOos = [double]::NaN
  $pfRetOosFwd = [double]::NaN
  $scoreDriftIsOos = [double]::NaN
  $scoreDriftOosFwd = [double]::NaN
  $retentionPass = $false

  if ($hasAllPhases) {
    if ($isAgg.ProfitFactorAgg -gt 0.0) {
      $pfRetIsOos = [math]::Round($oosAgg.ProfitFactorAgg / $isAgg.ProfitFactorAgg, 4)
    }
    if ($oosAgg.ProfitFactorAgg -gt 0.0) {
      $pfRetOosFwd = [math]::Round($fwdAgg.ProfitFactorAgg / $oosAgg.ProfitFactorAgg, 4)
    }
    $scoreDriftIsOos = [math]::Round($isAgg.ScoreAgg - $oosAgg.ScoreAgg, 2)
    $scoreDriftOosFwd = [math]::Round($oosAgg.ScoreAgg - $fwdAgg.ScoreAgg, 2)

    $g = $config.promotion_gates
    $retentionPass = $true
    if (-not [double]::IsNaN($pfRetIsOos) -and $pfRetIsOos -lt [double]$g.min_pf_retention_is_to_oos) { $retentionPass = $false }
    if (-not [double]::IsNaN($pfRetOosFwd) -and $pfRetOosFwd -lt [double]$g.min_pf_retention_oos_to_forward) { $retentionPass = $false }
    if ($scoreDriftIsOos -gt [double]$g.max_score_drift_is_to_oos) { $retentionPass = $false }
    if ($scoreDriftOosFwd -gt [double]$g.max_score_drift_oos_to_forward) { $retentionPass = $false }

    if ($isGate.Pass -and $oosGate.Pass -and $fwdGate.Pass -and $retentionPass) {
      $decision = "PROMOTE"
      $reason = "Passed IS/OOS/FORWARD + retention/drift gates"
    } else {
      $wm = $config.watchlist_margin
      $gg = $config.promotion_gates

      $nearScore =
        $isAgg.ScoreAgg -ge ([double]$gg.is_min_score - [double]$wm.score) -and
        $oosAgg.ScoreAgg -ge ([double]$gg.oos_min_score - [double]$wm.score) -and
        $fwdAgg.ScoreAgg -ge ([double]$gg.forward_min_score - [double]$wm.score)

      $nearPf =
        $oosAgg.ProfitFactorAgg -ge ([double]$gg.oos_min_profit_factor - [double]$wm.profit_factor) -and
        $fwdAgg.ProfitFactorAgg -ge ([double]$gg.forward_min_profit_factor - [double]$wm.profit_factor)

      $nearDd =
        $oosAgg.MaxDDPctAgg -le ([double]$gg.oos_max_drawdown_pct + [double]$wm.drawdown_pct) -and
        $fwdAgg.MaxDDPctAgg -le ([double]$gg.forward_max_drawdown_pct + [double]$wm.drawdown_pct)

      if ($nearScore -and $nearPf -and $nearDd) {
        $decision = "WATCHLIST"
        $reason = "Near promotion thresholds; monitor additional forward samples"
      } else {
        $decision = "REJECT"
        $reason = "Failed strict promotion gates"
      }
    }
  }

  $decisionBoard.Add([PSCustomObject]@{
    id = $cid
    profile = $profile
    notes = $notes
    decision = $decision
    reason = $reason
    is_runs = if ($null -ne $isAgg) { $isAgg.RunCount } else { 0 }
    oos_runs = if ($null -ne $oosAgg) { $oosAgg.RunCount } else { 0 }
    forward_runs = if ($null -ne $fwdAgg) { $fwdAgg.RunCount } else { 0 }
    is_score = if ($null -ne $isAgg) { $isAgg.ScoreAgg } else { [double]::NaN }
    oos_score = if ($null -ne $oosAgg) { $oosAgg.ScoreAgg } else { [double]::NaN }
    forward_score = if ($null -ne $fwdAgg) { $fwdAgg.ScoreAgg } else { [double]::NaN }
    is_pf = if ($null -ne $isAgg) { $isAgg.ProfitFactorAgg } else { [double]::NaN }
    oos_pf = if ($null -ne $oosAgg) { $oosAgg.ProfitFactorAgg } else { [double]::NaN }
    forward_pf = if ($null -ne $fwdAgg) { $fwdAgg.ProfitFactorAgg } else { [double]::NaN }
    is_dd = if ($null -ne $isAgg) { $isAgg.MaxDDPctAgg } else { [double]::NaN }
    oos_dd = if ($null -ne $oosAgg) { $oosAgg.MaxDDPctAgg } else { [double]::NaN }
    forward_dd = if ($null -ne $fwdAgg) { $fwdAgg.MaxDDPctAgg } else { [double]::NaN }
    is_pass = $isGate.Pass
    oos_pass = $oosGate.Pass
    forward_pass = $fwdGate.Pass
    is_gate_reason = $isGate.Reason
    oos_gate_reason = $oosGate.Reason
    forward_gate_reason = $fwdGate.Reason
    pf_retention_is_to_oos = $pfRetIsOos
    pf_retention_oos_to_forward = $pfRetOosFwd
    score_drift_is_to_oos = $scoreDriftIsOos
    score_drift_oos_to_forward = $scoreDriftOosFwd
    retention_drift_pass = $retentionPass
  })
}

$sorted = @($decisionBoard | Sort-Object `
  @{Expression={ Get-DecisionRank $_.decision }; Descending=$false}, `
  @{Expression="oos_score"; Descending=$true}, `
  @{Expression="forward_score"; Descending=$true}, `
  @{Expression="oos_dd"; Descending=$false})

$decisionPath = Join-Path $runDir "decision_board.csv"
$phaseCoveragePath = Join-Path $runDir "phase_coverage.csv"
$issuesPath = Join-Path $runDir "issues.md"
$promotionPacketPath = Join-Path $runDir "promotion_packet.json"
$lockPath = Join-Path $runDir "reproducibility.lock.json"
$summaryPath = Join-Path $runDir "summary.md"

$sorted | Export-Csv -Path $decisionPath -NoTypeInformation
$phaseCoverage | Export-Csv -Path $phaseCoveragePath -NoTypeInformation

$promoted = @($sorted | Where-Object { $_.decision -eq "PROMOTE" })
$watchlist = @($sorted | Where-Object { $_.decision -eq "WATCHLIST" })
$reject = @($sorted | Where-Object { $_.decision -eq "REJECT" })
$insufficient = @($sorted | Where-Object { $_.decision -eq "INSUFFICIENT_DATA" })

$issues = New-Object System.Collections.Generic.List[string]
if ($maps.FingerprintCollisions.Count -gt 0 -and -not $allPhasesHaveId) {
  $issues.Add("Fingerprint collisions:")
  foreach ($x in $maps.FingerprintCollisions) { $issues.Add("- $x") }
}
$issues.Add("Row matching diagnostics:")
$issues.Add("- IS: id_header=$isHasIdHeader fallback_matches=$($isPhase.FallbackMatchCount) ambiguous_fingerprint_rows=$($isPhase.AmbiguousRows.Count)")
$issues.Add("- OOS: id_header=$oosHasIdHeader fallback_matches=$($oosPhase.FallbackMatchCount) ambiguous_fingerprint_rows=$($oosPhase.AmbiguousRows.Count)")
$issues.Add("- FORWARD: id_header=$fwdHasIdHeader fallback_matches=$($fwdPhase.FallbackMatchCount) ambiguous_fingerprint_rows=$($fwdPhase.AmbiguousRows.Count)")
if ($isPhase.AmbiguousRows.Count -gt 0 -or $oosPhase.AmbiguousRows.Count -gt 0 -or $fwdPhase.AmbiguousRows.Count -gt 0) {
  $issues.Add("Ambiguous fingerprint matches were skipped to prevent cross-candidate contamination.")
}
$issues.Add("Unmatched rows:")
$issues.Add("- IS: $($isPhase.UnmatchedRows.Count)")
$issues.Add("- OOS: $($oosPhase.UnmatchedRows.Count)")
$issues.Add("- FORWARD: $($fwdPhase.UnmatchedRows.Count)")

$issuesMd = @(
  "# Industry OOS + Forward Issues",
  "",
  "Run: $runToken",
  ""
) + $issues
$issuesMd -join "`r`n" | Out-File -FilePath $issuesPath -Encoding utf8

$packet = [PSCustomObject]@{
  run_label = $runToken
  framework_version = $config.framework_version
  symbol = $config.symbol
  timeframe = $config.timeframe
  windows = $config.windows
  thresholds = $config.promotion_gates
  decision_counts = [PSCustomObject]@{
    promote = $promoted.Count
    watchlist = $watchlist.Count
    reject = $reject.Count
    insufficient_data = $insufficient.Count
  }
  promoted_candidates = $promoted
  watchlist_candidates = $watchlist
  top_ranked = @($sorted | Select-Object -First 10)
}
$packet | ConvertTo-Json -Depth 10 | Out-File -FilePath $promotionPacketPath -Encoding utf8

$lock = [PSCustomObject]@{
  generated_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  run_label = $runToken
  framework_script = [PSCustomObject]@{
    path = "smoke_test_matrix_v3/run_industry_oos_forward.ps1"
    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath "smoke_test_matrix_v3/run_industry_oos_forward.ps1").Hash
  }
  config = [PSCustomObject]@{
    path = $ConfigPath
    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $ConfigPath).Hash
  }
  inputs = @(
    [PSCustomObject]@{ path = $CandidatesCsv; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $CandidatesCsv).Hash },
    [PSCustomObject]@{ path = $InSampleCsv; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $InSampleCsv).Hash },
    [PSCustomObject]@{ path = $OosCsv; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $OosCsv).Hash },
    [PSCustomObject]@{ path = $ForwardCsv; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $ForwardCsv).Hash }
  )
  environment = [PSCustomObject]@{
    powershell = $PSVersionTable.PSVersion.ToString()
    edition = $PSVersionTable.PSEdition
    os = [System.Environment]::OSVersion.VersionString
    machine = $env:COMPUTERNAME
  }
  outputs = @(
    "decision_board.csv",
    "phase_coverage.csv",
    "issues.md",
    "promotion_packet.json",
    "reproducibility.lock.json",
    "summary.md"
  )
}
$lock | ConvertTo-Json -Depth 12 | Out-File -FilePath $lockPath -Encoding utf8

$topLines = New-Object System.Collections.Generic.List[string]
foreach ($row in @($sorted | Select-Object -First 10)) {
  $topLines.Add("- $($row.id) ($($row.profile)) | decision=$($row.decision) | IS/OOS/FWD score=$($row.is_score)/$($row.oos_score)/$($row.forward_score) | OOS/FWD PF=$($row.oos_pf)/$($row.forward_pf) | OOS/FWD DD=$($row.oos_dd)/$($row.forward_dd)")
}

$summary = @(
  "# Industry OOS + Forward Summary",
  "",
  "Run: $runToken",
  "",
  "## Decision Counts",
  "",
  "- PROMOTE: $($promoted.Count)",
  "- WATCHLIST: $($watchlist.Count)",
  "- REJECT: $($reject.Count)",
  "- INSUFFICIENT_DATA: $($insufficient.Count)",
  "",
  "## Top Candidates",
  ""
) + $topLines + @(
  "",
  "## Artifacts",
  "",
  "- decision_board.csv",
  "- phase_coverage.csv",
  "- issues.md",
  "- promotion_packet.json",
  "- reproducibility.lock.json"
)
$summary -join "`r`n" | Out-File -FilePath $summaryPath -Encoding utf8

Write-Host "Industry OOS+Forward framework run completed."
Write-Host "Run folder: $runDir"
Write-Host "Decision board: $decisionPath"
Write-Host "Promotion packet: $promotionPacketPath"
