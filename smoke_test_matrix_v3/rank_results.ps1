param(
  [Parameter(Mandatory = $true)]
  [string]$InputCsv,
  [string]$OutputCsv = "smoke_test_matrix_v3/ranked_results.csv",
  [double]$ExecutionThreshold = 73.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Clamp([double]$v, [double]$lo, [double]$hi) {
  if ($v -lt $lo) { return $lo }
  if ($v -gt $hi) { return $hi }
  return $v
}

function Get-ColValue($row, [string[]]$names, [double]$default = 0.0) {
  foreach ($n in $names) {
    if ($row.PSObject.Properties.Name -contains $n) {
      $raw = $row.$n
      if ($null -ne $raw -and "$raw" -ne "") {
        [double]$x = 0.0
        if ([double]::TryParse(($raw.ToString().Replace("%","").Replace(",","")), [ref]$x)) {
          return $x
        }
      }
    }
  }
  return $default
}

$rows = Import-Csv -Path $InputCsv

$ranked = foreach ($r in $rows) {
  $pf = Get-ColValue $r @("Profit Factor","ProfitFactor") 0.0
  $rf = Get-ColValue $r @("Recovery Factor","RecoveryFactor") 0.0
  $ep = Get-ColValue $r @("Expected Payoff","ExpectedPayoff") 0.0
  $dd = Get-ColValue $r @("Maximal Drawdown %","Max Drawdown %","Drawdown %","MaxDDPct") 100.0
  $tr = [int](Get-ColValue $r @("Trades","Total Trades") 0.0)
  $sh = Get-ColValue $r @("Sharpe Ratio","SharpeRatio") 1.0
  $profit = Get-ColValue $r @("Profit","Net Profit","NetProfit") 0.0
  $deposit = Get-ColValue $r @("Initial Deposit","Deposit","InitialBalance") 1000.0
  $rrInput = Get-ColValue $r @("Min_RR_Ratio","Min RR Ratio","MinRRRatio") 1.8
  $riskPct = Get-ColValue $r @("Risk_Percent","Risk Percent","RiskPercent") 0.7
  $maxSpread = Get-ColValue $r @("Max_Spread_Pips","Max Spread Pips","MaxSpreadPips") 45.0
  if ($deposit -le 0) { $deposit = 1000.0 }
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

  $confidence = "LOW"
  if ($score -gt 90) { $confidence = "ELITE" }
  elseif ($score -gt 75) { $confidence = "HIGH" }
  elseif ($score -gt 60) { $confidence = "ACCEPTABLE" }
  elseif ($score -gt 40) { $confidence = "WEAK" }

  $decision = "REJECT"
  if ($pass -and $score -ge $ExecutionThreshold) { $decision = "EXECUTE" }

  [PSCustomObject]@{
    FinalScore = [math]::Round($score, 2)
    Pass       = $pass
    Decision   = $decision
    Confidence = $confidence
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
    CompTrendProxy = [math]::Round(100 * (0.6 * $n_pf + 0.4 * $n_rf), 1)
    CompMomentumProxy = [math]::Round(100 * (0.6 * $n_ep + 0.4 * $n_sharpe), 1)
    CompVolatilityProxy = [math]::Round(100 * (0.6 * $n_dd + 0.4 * $n_trades), 1)
    CompRiskReward = [math]::Round(100 * $n_rr, 1)
    CompSpread = [math]::Round(100 * $n_spread, 1)
    SourceRow = $r
  }
}

$sorted = $ranked | Sort-Object -Property @{Expression="Pass";Descending=$true}, @{Expression="FinalScore";Descending=$true}, @{Expression="MaxDDPct";Descending=$false}, @{Expression="RecoveryFactor";Descending=$true}

# Flatten SourceRow for export
$out = foreach ($s in $sorted) {
  $base = [ordered]@{
    FinalScore = $s.FinalScore
    Pass = $s.Pass
    Decision = $s.Decision
    Confidence = $s.Confidence
    ProfitFactor = $s.ProfitFactor
    RecoveryFactor = $s.RecoveryFactor
    MaxDDPct = $s.MaxDDPct
    Trades = $s.Trades
    ProfitPct = $s.ProfitPct
    ExpectedPayoff = $s.ExpectedPayoff
    Sharpe = $s.Sharpe
    RRInput = $s.RRInput
    RiskPct = $s.RiskPct
    MaxSpreadPips = $s.MaxSpreadPips
    CompTrendProxy = $s.CompTrendProxy
    CompMomentumProxy = $s.CompMomentumProxy
    CompVolatilityProxy = $s.CompVolatilityProxy
    CompRiskReward = $s.CompRiskReward
    CompSpread = $s.CompSpread
  }
  foreach ($p in $s.SourceRow.PSObject.Properties) {
    if (-not $base.Contains($p.Name)) {
      $base[$p.Name] = $p.Value
    }
  }
  [PSCustomObject]$base
}

$out | Export-Csv -Path $OutputCsv -NoTypeInformation
Write-Host "Ranked results written to $OutputCsv"
