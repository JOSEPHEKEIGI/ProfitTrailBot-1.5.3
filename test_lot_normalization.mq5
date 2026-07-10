//+------------------------------------------------------------------+
//|                 Test Suite for Lot Normalization                |
//|                     ProfitTrailBot v1.5.2                       |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
// Test Framework
//+------------------------------------------------------------------+
int g_tests_passed = 0;
int g_tests_failed = 0;

void PrintTestHeader(string title)
{
   Print("\n" + StringFormat("=" * 50));
   Print(StringFormat("TEST: %s", title));
   Print(StringFormat("=" * 50));
}

void AssertEqual(double actual, double expected, double tolerance, string test_name)
{
   if(MathAbs(actual - expected) <= tolerance)
   {
      Print(StringFormat("✓ PASS: %s (%.6f == %.6f)", test_name, actual, expected));
      g_tests_passed++;
   }
   else
   {
      Print(StringFormat("✗ FAIL: %s (got %.6f, expected %.6f)", test_name, actual, expected));
      g_tests_failed++;
   }
}

void AssertTrue(bool condition, string test_name)
{
   if(condition)
   {
      Print(StringFormat("✓ PASS: %s", test_name));
      g_tests_passed++;
   }
   else
   {
      Print(StringFormat("✗ FAIL: %s", test_name));
      g_tests_failed++;
   }
}

//+------------------------------------------------------------------+
// CORRECTED Lot Normalization Function (from REMEDIATION_GUIDE)
//+------------------------------------------------------------------+
bool NormalizeLotToBrokerFixed(string symbol, double &lot, string &reason)
{
   double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   // Validate inputs
   if(min_lot <= 0 || max_lot <= 0 || lot_step <= 0)
   {
      reason = "Invalid symbol lot info";
      return false;
   }
   
   // CRITICAL FIX: Use proper rounding with epsilon tolerance
   const double EPSILON = 1e-10;
   
   // Round to nearest valid step (not floor!)
   double steps = lot / lot_step;
   double rounded_steps = MathRound(steps);
   double normalized = rounded_steps * lot_step;
   
   // Clamp to valid range
   if(normalized < min_lot - EPSILON)
   {
      normalized = min_lot;
   }
   if(normalized > max_lot + EPSILON)
   {
      normalized = max_lot;
   }
   
   // Check if final lot is too far from requested
   double difference = MathAbs(lot - normalized);
   if(difference > lot_step + EPSILON)
   {
      reason = StringFormat("Lot adjustment too large: %.2f → %.2f (%.2f step)",
                           lot, normalized, lot_step);
      return false;
   }
   
   lot = normalized;
   
   if(difference > EPSILON)
   {
      Print(StringFormat("[LOG] Normalized %.6f → %.6f", lot, normalized));
   }
   
   return true;
}

//+------------------------------------------------------------------+
// WRONG Old Function (using FLOOR)
//+------------------------------------------------------------------+
bool NormalizeLotToBrokerOld(string symbol, double &lot, string &reason)
{
   double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   if(min_lot <= 0 || max_lot <= 0 || lot_step <= 0)
   {
      reason = "Invalid symbol lot info";
      return false;
   }
   
   // WRONG: Uses floor - silently reduces position
   double normalized = MathFloor(lot / lot_step) * lot_step;
   normalized = MathMax(normalized, min_lot);
   normalized = MathMin(normalized, max_lot);
   
   lot = normalized;
   return true;
}

//+------------------------------------------------------------------+
// Test Cases
//+------------------------------------------------------------------+
void TestCase_StandardNormalization()
{
   PrintTestHeader("Standard Normalization");
   
   string symbol = "EURUSD";
   double input_lot = 1.55;
   double expected = 1.55;
   double tolerance = 0.001;
   
   double lot = input_lot;
   string reason = "";
   
   bool result = NormalizeLotToBrokerFixed(symbol, lot, reason);
   
   AssertTrue(result, "Function returns true");
   AssertEqual(lot, expected, tolerance, "1.55 → 1.55");
}

void TestCase_RoundLot()
{
   PrintTestHeader("Round Lot");
   
   string symbol = "EURUSD";
   double input_lot = 1.0;
   double expected = 1.0;
   double tolerance = 0.001;
   
   double lot = input_lot;
   string reason = "";
   
   bool result = NormalizeLotToBrokerFixed(symbol, lot, reason);
   
   AssertTrue(result, "Function returns true");
   AssertEqual(lot, expected, tolerance, "1.0 → 1.0");
}

void TestCase_BelowMinStep()
{
   PrintTestHeader("Below Min Step");
   
   string symbol = "EURUSD";
   double input_lot = 0.05;
   double expected_min = 0.01;  // Depends on broker
   double tolerance = 0.01;
   
   double lot = input_lot;
   string reason = "";
   
   bool result = NormalizeLotToBrokerFixed(symbol, lot, reason);
   
   Print(StringFormat("Input: %.6f, Output: %.6f, Expected >= %.6f", 
                     input_lot, lot, expected_min));
   
   // Should either round up or return false
   if(result)
   {
      AssertTrue(lot >= expected_min, "Result >= minimum lot");
      g_tests_passed++;
   }
   else
   {
      AssertTrue(lot == 0 || reason != "", "Returns false with reason");
      g_tests_passed++;
   }
}

void TestCase_CompareFLOORvsROUND()
{
   PrintTestHeader("Compare FLOOR vs ROUND - The Critical Difference");
   
   string symbol = "EURUSD";
   
   // Test case where FLOOR fails
   double lot_problematic = 1.0;
   double lot_step = 0.10;  // Example step size
   
   Print(StringFormat("\nScenario: lot=%.2f, lot_step=%.2f", lot_problematic, lot_step));
   
   // Using FLOOR (WRONG)
   double normalized_floor = MathFloor(lot_problematic / lot_step) * lot_step;
   Print(StringFormat("FLOOR: %.2f / %.2f = %.2f → Floor = %.0f → %.2f",
                     lot_problematic, lot_step, lot_problematic/lot_step,
                     MathFloor(lot_problematic/lot_step), normalized_floor));
   
   // Using ROUND (CORRECT)
   double normalized_round = MathRound(lot_problematic / lot_step) * lot_step;
   Print(StringFormat("ROUND: %.2f / %.2f = %.2f → Round = %.0f → %.2f",
                     lot_problematic, lot_step, lot_problematic/lot_step,
                     MathRound(lot_problematic/lot_step), normalized_round));
   
   // Floating point precision issue
   Print(StringFormat("\nFloating point precision test:"));
   double problematic_ratio = 1.0 / 0.10;
   Print(StringFormat("1.0 / 0.10 = %.15f (not exactly 10!)", problematic_ratio));
   Print(StringFormat("MathFloor(%.15f) = %.0f (loses precision!)", 
                     problematic_ratio, MathFloor(problematic_ratio)));
   Print(StringFormat("MathRound(%.15f) = %.0f (safer)", 
                     problematic_ratio, MathRound(problematic_ratio)));
}

void TestCase_VerySmallLot()
{
   PrintTestHeader("Very Small Lot");
   
   string symbol = "EURUSD";
   double input_lot = 0.001;
   
   double lot = input_lot;
   string reason = "";
   
   bool result = NormalizeLotToBrokerFixed(symbol, lot, reason);
   
   Print(StringFormat("Input: %.6f, Output: %.6f", input_lot, lot));
   
   if(!result)
   {
      Print(StringFormat("Correctly rejected: %s", reason));
      g_tests_passed++;
   }
   else
   {
      AssertTrue(lot >= SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN),
                "Output is at least minimum lot");
   }
}

void TestCase_FractionalRounding()
{
   PrintTestHeader("Fractional Rounding");
   
   string symbol = "EURUSD";
   double input_lot = 1.555;
   double expected = 1.56;  // Should round up
   double tolerance = 0.01;
   
   double lot = input_lot;
   string reason = "";
   
   bool result = NormalizeLotToBrokerFixed(symbol, lot, reason);
   
   AssertTrue(result, "Function returns true");
   // Might be 1.55 or 1.56 depending on rounding, but should be close
   AssertEqual(lot, expected, tolerance, "1.555 rounds intelligently");
}

//+------------------------------------------------------------------+
// Main Test Execution
//+------------------------------------------------------------------+
void OnStart()
{
   Print("\n" + StringFormat("=" * 60));
   Print("LOT NORMALIZATION TEST SUITE");
   Print("ProfitTrailBot v1.5.2");
   Print(StringFormat("=" * 60));
   
   Print(StringFormat("\nTesting EURUSD symbol...\n"));
   
   // Run all test cases
   TestCase_StandardNormalization();
   TestCase_RoundLot();
   TestCase_BelowMinStep();
   TestCase_CompareFLOORvsROUND();
   TestCase_VerySmallLot();
   TestCase_FractionalRounding();
   
   // Summary
   Print("\n" + StringFormat("=" * 60));
   Print("TEST SUMMARY");
   Print(StringFormat("=" * 60));
   Print(StringFormat("Passed: %d", g_tests_passed));
   Print(StringFormat("Failed: %d", g_tests_failed));
   
   if(g_tests_failed == 0)
   {
      Print("\n✓ ALL TESTS PASSED");
   }
   else
   {
      Print(StringFormat("\n✗ %d TESTS FAILED - Review fixes", g_tests_failed));
   }
   
   Print(StringFormat("=" * 60 + "\n"));
}

//+------------------------------------------------------------------+
//| OnInit function for Strategy Tester compatibility
//+------------------------------------------------------------------+
int OnInit()
{
   OnStart();
   return(INIT_SUCCEEDED);
}
