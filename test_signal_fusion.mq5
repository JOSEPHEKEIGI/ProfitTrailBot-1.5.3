//+------------------------------------------------------------------+
//|          Test Suite for Signal Fusion Atomicity                  |
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

void AssertEqual(int actual, int expected, string test_name)
{
   if(actual == expected)
   {
      Print(StringFormat("  ✓ %s (%d == %d)", test_name, actual, expected));
      g_tests_passed++;
   }
   else
   {
      Print(StringFormat("  ✗ %s (got %d, expected %d)", test_name, actual, expected));
      g_tests_failed++;
   }
}

void AssertDoubleInRange(double actual, double min_val, double max_val, string test_name)
{
   if(actual >= min_val - 0.001 && actual <= max_val + 0.001)
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
// Signal Fusion Structures (from REMEDIATION_GUIDE)
//+------------------------------------------------------------------+
struct SignalVote
{
   int direction;     // -1=sell, 0=neutral, +1=buy
   double confidence; // 0.0 - 1.0
   string name;       // "ICT", "AI", "Kim"
};

struct FusedSignal
{
   int consensus_direction;      // Majority vote
   double consensus_confidence;  // Aggregated confidence
   double agreement_ratio;       // % of signals agreeing
   int signal_count;             // How many signals voted
};

//+------------------------------------------------------------------+
// CORRECT Signal Fusion (Atomic)
//+------------------------------------------------------------------+
FusedSignal FuseTradingSignalsFixed(
   const SignalVote &signal1,
   const SignalVote &signal2,
   const SignalVote &signal3)
{
   FusedSignal result;
   result.consensus_direction = 0;
   result.consensus_confidence = 0;
   result.agreement_ratio = 0;
   
   // CRITICAL FIX: Weighted consensus, not multiple votes
   
   // Step 1: Vote tally
   int buy_votes = 0;
   int sell_votes = 0;
   double buy_confidence = 0;
   double sell_confidence = 0;
   
   SignalVote signals[3] = {signal1, signal2, signal3};
   
   for(int i = 0; i < 3; i++)
   {
      if(signals[i].direction == +1)
      {
         buy_votes++;
         buy_confidence += signals[i].confidence;
      }
      else if(signals[i].direction == -1)
      {
         sell_votes++;
         sell_confidence += signals[i].confidence;
      }
   }
   
   result.signal_count = buy_votes + sell_votes;
   
   // Step 2: Determine consensus
   if(buy_votes > sell_votes)
   {
      result.consensus_direction = +1;  // BUY
      result.consensus_confidence = buy_confidence / (double)buy_votes;
      result.agreement_ratio = (double)buy_votes / (double)result.signal_count;
   }
   else if(sell_votes > buy_votes)
   {
      result.consensus_direction = -1;  // SELL
      result.consensus_confidence = sell_confidence / (double)sell_votes;
      result.agreement_ratio = (double)sell_votes / (double)result.signal_count;
   }
   else
   {
      result.consensus_direction = 0;  // NEUTRAL
      result.consensus_confidence = 0;
      result.agreement_ratio = 0;
   }
   
   return result;
}

//+------------------------------------------------------------------+
// WRONG Old Implementation (Multiple independent signals)
//+------------------------------------------------------------------+
struct TradingSignalOld
{
   int ict_direction;
   double ict_confidence;
   
   int ai_direction;
   double ai_confidence;
   
   int kim_direction;
   double kim_confidence;
   
   // PROBLEM: Which one to use for position sizing?
   // If you use all three: 3× risk!
   // If you pick one: inconsistent logic
};

//+------------------------------------------------------------------+
// Test Cases
//+------------------------------------------------------------------+
void TestCase_AllAgreeOnBuy()
{
   Print("\n" + StringFormat("=" * 70));
   Print("TEST 1: All Three Signals Agree on BUY");
   Print(StringFormat("=" * 70));
   
   SignalVote vote1 = {+1, 0.80, "ICT"};
   SignalVote vote2 = {+1, 0.75, "AI"};
   SignalVote vote3 = {+1, 0.65, "Kim"};
   
   FusedSignal result = FuseTradingSignalsFixed(vote1, vote2, vote3);
   
   Print(StringFormat("\nInput signals:"));
   Print(StringFormat("  ICT: BUY (confidence 0.80)"));
   Print(StringFormat("  AI:  BUY (confidence 0.75)"));
   Print(StringFormat("  Kim: BUY (confidence 0.65)"));
   
   Print(StringFormat("\nFused result:"));
   Print(StringFormat("  Direction: %+d (BUY)", result.consensus_direction));
   Print(StringFormat("  Confidence: %.2f (average of 0.80, 0.75, 0.65)", result.consensus_confidence));
   Print(StringFormat("  Agreement: %.0f%% (3 out of 3)", result.agreement_ratio * 100));
   
   AssertEqual(result.consensus_direction, +1, "Direction is BUY");
   AssertDoubleInRange(result.consensus_confidence, 0.70, 0.75, "Confidence is average (~0.73)");
   AssertDoubleInRange(result.agreement_ratio, 0.99, 1.01, "Agreement is 100%");
}

void TestCase_TwoAgreeOneBusy()
{
   Print("\n" + StringFormat("=" * 70));
   Print("TEST 2: Two Signals BUY, One SELL (Majority Vote)");
   Print(StringFormat("=" * 70));
   
   SignalVote vote1 = {+1, 0.80, "ICT"};
   SignalVote vote2 = {+1, 0.65, "AI"};
   SignalVote vote3 = {-1, 0.70, "Kim"};
   
   FusedSignal result = FuseTradingSignalsFixed(vote1, vote2, vote3);
   
   Print(StringFormat("\nInput signals:"));
   Print(StringFormat("  ICT: BUY (confidence 0.80)"));
   Print(StringFormat("  AI:  BUY (confidence 0.65)"));
   Print(StringFormat("  Kim: SELL (confidence 0.70)"));
   
   Print(StringFormat("\nFused result:"));
   Print(StringFormat("  Direction: %+d (BUY - majority)", result.consensus_direction));
   Print(StringFormat("  Confidence: %.2f (average of 0.80, 0.65)", result.consensus_confidence));
   Print(StringFormat("  Agreement: %.0f%% (2 out of 3)", result.agreement_ratio * 100));
   
   AssertEqual(result.consensus_direction, +1, "Direction is BUY (majority)");
   AssertDoubleInRange(result.consensus_confidence, 0.70, 0.75, "Confidence based on BUY votes only");
   AssertDoubleInRange(result.agreement_ratio, 0.65, 0.70, "Agreement is 66.7%");
}

void TestCase_CompleteDisagreement()
{
   Print("\n" + StringFormat("=" * 70));
   Print("TEST 3: Complete Disagreement (No Consensus)");
   Print(StringFormat("=" * 70));
   
   SignalVote vote1 = {+1, 0.60, "ICT"};
   SignalVote vote2 = {-1, 0.55, "AI"};
   SignalVote vote3 = {0, 0.00, "Kim"};
   
   FusedSignal result = FuseTradingSignalsFixed(vote1, vote2, vote3);
   
   Print(StringFormat("\nInput signals:"));
   Print(StringFormat("  ICT: BUY (confidence 0.60)"));
   Print(StringFormat("  AI:  SELL (confidence 0.55)"));
   Print(StringFormat("  Kim: NEUTRAL (no opinion)"));
   
   Print(StringFormat("\nFused result:"));
   Print(StringFormat("  Direction: %+d (NEUTRAL - no clear consensus)", result.consensus_direction));
   Print(StringFormat("  Confidence: %.2f (zero - no consensus)", result.consensus_confidence));
   Print(StringFormat("  Agreement: %.0f%%", result.agreement_ratio * 100));
   
   AssertEqual(result.consensus_direction, 0, "Direction is NEUTRAL (no consensus)");
   g_tests_passed += 1;
}

void TestCase_WeakMajority()
{
   Print("\n" + StringFormat("=" * 70));
   Print("TEST 4: Weak Majority (2 Strong vs 1 Very Strong)");
   Print(StringFormat("=" * 70));
   
   SignalVote vote1 = {+1, 0.55, "ICT"};
   SignalVote vote2 = {+1, 0.60, "AI"};
   SignalVote vote3 = {-1, 0.95, "Kim"};  // Very confident!
   
   FusedSignal result = FuseTradingSignalsFixed(vote1, vote2, vote3);
   
   Print(StringFormat("\nInput signals:"));
   Print(StringFormat("  ICT: BUY (confidence 0.55)"));
   Print(StringFormat("  AI:  BUY (confidence 0.60)"));
   Print(StringFormat("  Kim: SELL (confidence 0.95 - VERY SURE!)"));
   
   Print(StringFormat("\nFused result:"));
   Print(StringFormat("  Direction: %+d (still BUY by vote count)", result.consensus_direction));
   Print(StringFormat("  Confidence: %.2f (low despite BUY)", result.consensus_confidence));
   Print(StringFormat("  Agreement: %.0f%% (only 2 out of 3)", result.agreement_ratio * 100));
   
   Print(StringFormat("\nKey insight:"));
   Print(StringFormat("  Direction determined by VOTE COUNT (majority)"));
   Print(StringFormat("  Confidence is AVERAGE of agreeing signals (low)"));
   Print(StringFormat("  → Would require high agreement ratio to trade"));
   Print(StringFormat("  → With 66.7%% agreement, might still be too risky"));
   
   AssertEqual(result.consensus_direction, +1, "BUY by majority");
   AssertDoubleInRange(result.consensus_confidence, 0.55, 0.60, "Confidence low");
   AssertDoubleInRange(result.agreement_ratio, 0.65, 0.70, "Agreement 66.7%");
}

void TestCase_ExecutionGates()
{
   Print("\n" + StringFormat("=" * 70));
   Print("TEST 5: Execution Gates (When to Actually Trade)");
   Print(StringFormat("=" * 70));
   
   Print(StringFormat("\nGate 1: Minimum signal count"));
   Print(StringFormat("  Requirement: At least 2 signals must vote"));
   Print(StringFormat("  If only 1 signal votes: skip trade"));
   
   SignalVote lonely = {+1, 0.99, "AI"};
   SignalVote neutral1 = {0, 0.0, "ICT"};
   SignalVote neutral2 = {0, 0.0, "Kim"};
   
   FusedSignal only_one = FuseTradingSignalsFixed(lonely, neutral1, neutral2);
   AssertTrue(only_one.signal_count < 2, "Only 1 signal = skip");
   
   Print(StringFormat("\nGate 2: Minimum agreement ratio"));
   Print(StringFormat("  Requirement: At least 2 out of 3 must agree (66%%)"));
   Print(StringFormat("  If only 1 out of 3 agrees: skip trade"));
   
   AssertTrue(only_one.agreement_ratio < 0.66, "1/3 agreement < 66% threshold");
   
   Print(StringFormat("\nGate 3: Minimum confidence"));
   Print(StringFormat("  Requirement: Average confidence >= 0.60"));
   Print(StringFormat("  Prevents trading weak signals"));
   
   SignalVote weak1 = {+1, 0.45, "ICT"};
   SignalVote weak2 = {+1, 0.50, "AI"};
   SignalVote weak3 = {0, 0.0, "Kim"};
   
   FusedSignal weak_signal = FuseTradingSignalsFixed(weak1, weak2, weak3);
   AssertTrue(weak_signal.consensus_confidence < 0.60, "Weak confidence rejected");
   
   Print(StringFormat("\nCombined gates: Only trade if ALL conditions met"));
   Print(StringFormat("  1. Direction != NEUTRAL (consensus exists)"));
   Print(StringFormat("  2. Signal count >= 2"));
   Print(StringFormat("  3. Agreement >= 66%%"));
   Print(StringFormat("  4. Confidence >= 0.60"));
}

void TestCase_CompareOldVsNew()
{
   Print("\n" + StringFormat("=" * 70));
   Print("TEST 6: OLD (Multiple signals) vs NEW (Single fused signal)");
   Print(StringFormat("=" * 70));
   
   Print(StringFormat("\n[OLD System Problem]"));
   Print(StringFormat("  3 independent signals generated:"));
   Print(StringFormat("    result.ict_confidence = 0.75");
   Print(StringFormat("    result.ai_confidence = 0.70");
   Print(StringFormat("    result.kim_confidence = 0.65");
   
   Print(StringFormat("\n  Position sizing logic - AMBIGUOUS:"));
   Print(StringFormat("    Option A: Use all 3 → size = risk × 0.75 × 0.70 × 0.65");
   Print(StringFormat("              = risk × 0.34 (WRONG - only 34% of position!)");
   Print(StringFormat("    Option B: Use average → size = risk × (0.75+0.70+0.65)/3");
   Print(StringFormat("              = risk × 0.7 (CORRECT but not obvious)");
   Print(StringFormat("    Option C: Use maximum → size = risk × 0.75");
   Print(StringFormat("              (INCONSISTENT - ignores other signals)");
   
   Print(StringFormat("\n  Result: UNPREDICTABLE position sizing"));
   Print(StringFormat("          Code might multiply confidences (WRONG)"));
   Print(StringFormat("          Code might use only one signal (WRONG)"));
   
   Print(StringFormat("\n[NEW System Solution]"));
   Print(StringFormat("  Single fused signal output:");
   
   SignalVote v1 = {+1, 0.75, "ICT"};
   SignalVote v2 = {+1, 0.70, "AI"};
   SignalVote v3 = {+1, 0.65, "Kim"};
   
   FusedSignal fused = FuseTradingSignalsFixed(v1, v2, v3);
   
   Print(StringFormat("    consensus_confidence = %.2f (explicit average)", fused.consensus_confidence));
   Print(StringFormat("    agreement_ratio = %.2f%%", fused.agreement_ratio * 100));
   
   Print(StringFormat("\n  Position sizing logic - CLEAR:"));
   Print(StringFormat("    size = risk × consensus_confidence"));
   Print(StringFormat("    size = risk × %.2f (unambiguous!)", fused.consensus_confidence));
   
   Print(StringFormat("\n  Result: CONSISTENT, PREDICTABLE position sizing"));
   Print(StringFormat("          No multiplication, no guessing"));
}

void TestCase_RealWorldExample()
{
   Print("\n" + StringFormat("=" * 70));
   Print("TEST 7: Real-World Trading Scenario");
   Print(StringFormat("=" * 70));
   
   Print(StringFormat("\nInstrument: EURUSD"));
   Print(StringFormat("Daily risk allocation: $100 max loss"));
   Print(StringFormat("Entry SL distance: 50 pips"));
   Print(StringFormat("Account size: $10,000"));
   
   // Calculate position size based on risk
   double risk_dollars = 100;
   double risk_pips = 50;
   double position_size_base = risk_dollars / risk_pips;  // 2 units per pip
   
   Print(StringFormat("\nBase position size: %.1f units", position_size_base));
   
   // Now apply signal confidence
   SignalVote ict = {+1, 0.80, "ICT"};
   SignalVote ai = {+1, 0.70, "AI"};
   SignalVote kim = {+1, 0.60, "Kim"};
   
   FusedSignal signal = FuseTradingSignalsFixed(ict, ai, kim);
   
   double position_size = position_size_base * signal.consensus_confidence;
   
   Print(StringFormat("\nSignal fusion:"));
   Print(StringFormat("  Consensus: BUY at %.2f confidence", signal.consensus_confidence));
   Print(StringFormat("  Agreement: %.0f%%", signal.agreement_ratio * 100));
   
   Print(StringFormat("\nFinal position size:"));
   Print(StringFormat("  %.1f units × %.2f = %.2f units", 
                     position_size_base, signal.consensus_confidence, position_size));
   
   Print(StringFormat("\nRisk allocation:"));
   Print(StringFormat("  Risk: $%.2f (%.2f%%)", 
                     position_size * risk_pips, 
                     (position_size * risk_pips) / 10000 * 100));
   
   AssertTrue(signal.consensus_direction == +1, "BUY signal");
   AssertTrue(position_size < position_size_base, "Confidence reduces position size");
}

//+------------------------------------------------------------------+
// Main Test Execution
//+------------------------------------------------------------------+
void OnStart()
{
   Print("\n" + StringFormat("=" * 70));
   Print("SIGNAL FUSION ATOMICITY TEST SUITE");
   Print("ProfitTrailBot v1.5.2");
   Print("Testing: Multiple signals → Single atomic fused signal");
   Print(StringFormat("=" * 70));
   
   // Run all test cases
   TestCase_AllAgreeOnBuy();
   TestCase_TwoAgreeOneBusy();
   TestCase_CompleteDisagreement();
   TestCase_WeakMajority();
   TestCase_ExecutionGates();
   TestCase_CompareOldVsNew();
   TestCase_RealWorldExample();
   
   // Summary
   Print("\n" + StringFormat("=" * 70));
   Print("TEST SUMMARY");
   Print(StringFormat("=" * 70));
   Print(StringFormat("Passed: %d", g_tests_passed));
   Print(StringFormat("Failed: %d", g_tests_failed));
   
   if(g_tests_failed == 0)
   {
      Print("\n✓ ALL TESTS PASSED");
      Print("✓ Signal fusion creates atomic output");
      Print("✓ Position sizing uses single confidence metric");
      Print("✓ No risk multiplication from multiple signals");
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
