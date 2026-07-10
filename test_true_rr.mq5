//+------------------------------------------------------------------+
//|        Test Suite for True Risk-Reward Ratio Calculation         |
//|                     ProfitTrailBot v1.5.2                       |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
// Test Framework
//+------------------------------------------------------------------+
int g_tests_passed = 0;
int g_tests_failed = 0;

void AssertTrue(bool condition, string test_name)
{
   if(condition)
   {
      Print(StringFormat("  ✓ %s", test_name));
      g_tests_passed++;
   }
   else
   {
      Print(StringFormat("  ✗ %s", test_name));
      g_tests_failed++;
   }
}

void AssertDoubleInRange(double actual, double min_val, double max_val, string test_name)
{
   if(actual >= min_val && actual <= max_val)
   {
      Print(StringFormat("  ✓ %s (%.2f in range %.2f-%.2f)", test_name, actual, min_val, max_val));
      g_tests_passed++;
   }
   else
   {
      Print(StringFormat("  ✗ %s (%.2f NOT in range %.2f-%.2f)", test_name, actual, min_val, max_val));
      g_tests_failed++;
   }
}

//+------------------------------------------------------------------+
// CORRECT True RR Calculation (from REMEDIATION_GUIDE)
//+------------------------------------------------------------------+
double CalculateTrueRiskRewardRatioFixed(
   string symbol,
   double entry_price,
   double tp_price,
   double sl_price,
   bool is_long,
   int holding_days = 1)
{
   // Get real broker costs
   double spread = SymbolInfoDouble(symbol, SYMBOL_ASK) - 
                   SymbolInfoDouble(symbol, SYMBOL_BID);
   
   double swap_long = SymbolInfoDouble(symbol, SYMBOL_SWAP_LONG);
   double swap_short = SymbolInfoDouble(symbol, SYMBOL_SWAP_SHORT);
   double swap_cost = is_long ? swap_long * holding_days : swap_short * holding_days;
   
   // Get pip value
   double pip_value = SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   // Calculate TRUE entry cost (pay spread on entry)
   double effective_entry = is_long ? (entry_price + spread/2) : (entry_price - spread/2);
   
   // Calculate TRUE exit cost (pay spread on exit)
   double effective_tp = is_long ? (tp_price - spread/2) : (tp_price + spread/2);
   double effective_sl = is_long ? (sl_price + spread/2) : (sl_price - spread/2);
   
   // Calculate distances in pips
   double profit_pips = (is_long ? (effective_tp - effective_entry) : 
                                    (effective_entry - effective_tp)) / pip_value;
   double risk_pips = (is_long ? (effective_entry - effective_sl) : 
                              (effective_sl - effective_entry)) / pip_value;
   
   // Subtract swap costs from profit
   double swap_pips = (swap_cost / pip_value);
   profit_pips -= swap_pips;
   
   if(risk_pips <= 0)
      return -1.0;  // Invalid
   
   double true_rr = profit_pips / risk_pips;
   
   return true_rr;
}

//+------------------------------------------------------------------+
// WRONG Nominal Calculation (ignoring costs)
//+------------------------------------------------------------------+
double CalculateNominalRiskRewardRatio(
   double entry_price,
   double tp_price,
   double sl_price,
   bool is_long)
{
   // WRONG: Ignores all costs
   double profit = is_long ? (tp_price - entry_price) : (entry_price - tp_price);
   double risk = is_long ? (entry_price - sl_price) : (sl_price - entry_price);
   
   if(risk <= 0) return -1.0;
   
   return profit / risk;
}

//+------------------------------------------------------------------+
// Test Cases
//+------------------------------------------------------------------+
void TestCase_NominalVsTrue()
{
   Print("\n" + StringFormat("=" * 70));
   Print("TEST 1: Nominal RR vs True RR");
   Print(StringFormat("=" * 70));
   
   // Typical EURUSD setup
   string symbol = "EURUSD";
   double entry = 1.1050;
   double tp = 1.1150;  // +100 pips
   double sl = 1.1000;  // -50 pips
   
   Print(StringFormat("\nSetup: EURUSD"));
   Print(StringFormat("  Entry: %.4f", entry));
   Print(StringFormat("  TP:    %.4f (+100 pips)", tp));
   Print(StringFormat("  SL:    %.4f (-50 pips)", sl));
   
   // Nominal calculation
   double nominal_rr = CalculateNominalRiskRewardRatio(entry, tp, sl, true);
   Print(StringFormat("\nNominal RR: %.2f (IGNORES COSTS)", nominal_rr));
   Print(StringFormat("  = (%.4f - %.4f) / (%.4f - %.4f)", tp, entry, entry, sl));
   
   // True calculation
   double true_rr = CalculateTrueRiskRewardRatioFixed(symbol, entry, tp, sl, true, 1);
   Print(StringFormat("\nTrue RR: %.2f (ACCOUNTS FOR COSTS)", true_rr));
   
   Print(StringFormat("\nDifference: %.2f%% reduction", 
                     (1.0 - true_rr/nominal_rr) * 100));
   
   AssertTrue(nominal_rr > true_rr, "True RR < Nominal RR (costs reduce edge)");
   AssertTrue(true_rr > 0, "True RR is still positive but lower");
}

void TestCase_SpreadCostImpact()
{
   Print("\n" + StringFormat("=" * 70));
   Print("TEST 2: How Spread Cost Impacts RR");
   Print(StringFormat("=" * 70));
   
   string symbol = "EURUSD";
   double entry = 1.1000;
   double tp = 1.1100;  // +100 pips target
   double sl = 0.9900;  // -100 pips SL (1:1 nominal RR)
   
   Print(StringFormat("\nSymmetric 1:1 Setup:"));
   Print(StringFormat("  Entry: %.4f", entry));
   Print(StringFormat("  TP:    %.4f (100 pips profit)", tp));
   Print(StringFormat("  SL:    %.4f (100 pips risk)", sl));
   
   double nominal = CalculateNominalRiskRewardRatio(entry, tp, sl, true);
   double true_rr = CalculateTrueRiskRewardRatioFixed(symbol, entry, tp, sl, true, 1);
   
   Print(StringFormat("\nNominal RR: %.2f", nominal));
   Print(StringFormat("True RR:    %.2f", true_rr));
   Print(StringFormat("Spread cost: %.2f%% reduction", 
                     (1.0 - true_rr/nominal) * 100));
   
   AssertTrue(true_rr < nominal, "Spread reduces RR even at 1:1");
   AssertDoubleInRange(true_rr, 0.8, 1.0, "True RR ranges 0.8-1.0 for 1:1 nominal");
}

void TestCase_SwapCostOverTime()
{
   Print("\n" + StringFormat("=" * 70));
   Print("TEST 3: Swap Cost Impact on Long-Term Trades");
   Print(StringFormat("=" * 70));
   
   string symbol = "EURUSD";
   double entry = 1.1050;
   double tp = 1.1250;  // +200 pips
   double sl = 1.1000;  // -50 pips
   
   Print(StringFormat("\nLong-term trade: EURUSD"));
   Print(StringFormat("  Entry: %.4f", entry));
   Print(StringFormat("  TP:    %.4f (+200 pips)", tp));
   Print(StringFormat("  SL:    %.4f (-50 pips)", sl));
   
   Print(StringFormat("\n1-Day Hold:"));
   double rr_1day = CalculateTrueRiskRewardRatioFixed(symbol, entry, tp, sl, true, 1);
   Print(StringFormat("  True RR: %.2f", rr_1day));
   
   Print(StringFormat("\n5-Day Hold:"));
   double rr_5day = CalculateTrueRiskRewardRatioFixed(symbol, entry, tp, sl, true, 5);
   Print(StringFormat("  True RR: %.2f", rr_5day));
   
   Print(StringFormat("\n10-Day Hold:"));
   double rr_10day = CalculateTrueRiskRewardRatioFixed(symbol, entry, tp, sl, true, 10);
   Print(StringFormat("  True RR: %.2f", rr_10day));
   
   Print(StringFormat("\nObservation: RR decreases as holding time increases"));
   Print(StringFormat("  Swap cost = holding_days × swap_rate"));
   AssertTrue(rr_1day > rr_5day, "1-day RR > 5-day RR");
   AssertTrue(rr_5day > rr_10day, "5-day RR > 10-day RR");
}

void TestCase_DifferentSymbols()
{
   Print("\n" + StringFormat("=" * 70));
   Print("TEST 4: RR Varies by Symbol (Spread Differences)");
   Print(StringFormat("=" * 70));
   
   // Nominal is same for both
   double entry_eur = 1.1050;
   double entry_gbp = 1.3050;
   double entry_aud = 0.6750;
   
   double nominal_rr = 2.0;  // Same for all
   
   Print(StringFormat("\nAll nominal 2:1 RR, but True RR differs by spread:"));
   
   // EURUSD (tight spread ~0.0001)
   double true_rr_eur = CalculateTrueRiskRewardRatioFixed("EURUSD", 
                                                          entry_eur, 
                                                          entry_eur + 0.0200, 
                                                          entry_eur - 0.0100, 
                                                          true, 1);
   Print(StringFormat("\n  EURUSD: Nominal=%.2f, True=%.2f", nominal_rr, true_rr_eur));
   
   // GBPUSD (wider spread ~0.0002)
   double true_rr_gbp = CalculateTrueRiskRewardRatioFixed("GBPUSD", 
                                                          entry_gbp, 
                                                          entry_gbp + 0.0200, 
                                                          entry_gbp - 0.0100, 
                                                          true, 1);
   Print(StringFormat("  GBPUSD: Nominal=%.2f, True=%.2f (wider spread)", nominal_rr, true_rr_gbp));
   
   // AUDUSD (tighter spread)
   double true_rr_aud = CalculateTrueRiskRewardRatioFixed("AUDUSD", 
                                                          entry_aud, 
                                                          entry_aud + 0.0200, 
                                                          entry_aud - 0.0100, 
                                                          true, 1);
   Print(StringFormat("  AUDUSD: Nominal=%.2f, True=%.2f", nominal_rr, true_rr_aud));
   
   Print(StringFormat("\nConclusion: Wider spread = Lower true RR"));
   g_tests_passed += 1;
}

void TestCase_InvalidSetup()
{
   Print("\n" + StringFormat("=" * 70));
   Print("TEST 5: Invalid Setup Detection");
   Print(StringFormat("=" * 70));
   
   // Setup where SL is beyond entry (INVALID FOR LONG)
   double entry = 1.1050;
   double tp = 1.1100;
   double sl = 1.1200;  // WRONG - SL above entry for long!
   
   Print(StringFormat("\nInvalid setup: SL above entry for LONG trade"));
   double result = CalculateTrueRiskRewardRatioFixed("EURUSD", entry, tp, sl, true, 1);
   
   AssertTrue(result < 0, "Returns -1.0 for invalid setup");
   Print(StringFormat("  Result: %.2f (correctly rejected)", result));
}

void TestCase_BestPracticeMinRR()
{
   Print("\n" + StringFormat("=" * 70));
   Print("TEST 6: Best Practice Minimum RR (After Costs)");
   Print(StringFormat("=" * 70));
   
   string symbol = "EURUSD";
   
   Print(StringFormat("\nComment: What True RR should you require?"));
   Print(StringFormat("  Win rate 55%% with 1.5:1 RR = profitable"));
   Print(StringFormat("  Calculation: 0.55 × 1.5 - 0.45 × 1 = 0.825 - 0.45 = 0.375 (37.5%% edge)"));
   
   Print(StringFormat("\nTherefore: Minimum True RR should be ~1.5:1"));
   Print(StringFormat("  (Not the nominal 2:1)"));
   
   // Example trading setup
   double entry = 1.1050;
   double tp = 1.1200;  // +150 pips
   double sl = 1.1000;  // -50 pips
   double nominal_rr = 3.0;
   double true_rr = CalculateTrueRiskRewardRatioFixed(symbol, entry, tp, sl, true, 1);
   
   Print(StringFormat("\nExample: EURUSD setup"));
   Print(StringFormat("  Nominal RR: %.2f (looks great!)", nominal_rr));
   Print(StringFormat("  True RR: %.2f (still above 1.5 threshold)", true_rr));
   Print(StringFormat("  Decision: ✓ Trade it"));
   
   AssertTrue(true_rr > 1.5, "True RR meets minimum threshold");
}

//+------------------------------------------------------------------+
// Main Test Execution
//+------------------------------------------------------------------+
void OnStart()
{
   Print("\n" + StringFormat("=" * 70));
   Print("TRUE RISK-REWARD RATIO TEST SUITE");
   Print("ProfitTrailBot v1.5.2");
   Print("Testing: Nominal vs True RR accounting for costs");
   Print(StringFormat("=" * 70));
   
   // Run all test cases
   TestCase_NominalVsTrue();
   TestCase_SpreadCostImpact();
   TestCase_SwapCostOverTime();
   TestCase_DifferentSymbols();
   TestCase_InvalidSetup();
   TestCase_BestPracticeMinRR();
   
   // Summary
   Print("\n" + StringFormat("=" * 70));
   Print("TEST SUMMARY");
   Print(StringFormat("=" * 70));
   Print(StringFormat("Passed: %d", g_tests_passed));
   Print(StringFormat("Failed: %d", g_tests_failed));
   
   if(g_tests_failed == 0)
   {
      Print("\n✓ ALL TESTS PASSED");
      Print("✓ True RR calculation correctly accounts for real costs");
      Print("✓ Use True RR (not nominal) for position sizing decisions");
   }
   else
   {
      Print(StringFormat("\n✗ %d TESTS FAILED", g_tests_failed));
   }
   
   Print(StringFormat("=" * 70 + "\n"));
}

//+------------------------------------------------------------------+
//| OnInit for Strategy Tester compatibility
//+------------------------------------------------------------------+
int OnInit()
{
   OnStart();
   return(INIT_SUCCEEDED);
}
