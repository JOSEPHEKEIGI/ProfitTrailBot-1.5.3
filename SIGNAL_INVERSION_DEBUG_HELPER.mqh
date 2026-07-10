// ====================================================================
// SIGNAL INVERSION DEBUG QUICK START
// ====================================================================
// 
// Copy this code into your MainLifecycle.mqh OnTick() or main processing loop
// to automatically validate signals for inversion
//
// ====================================================================

/**
 * Quick Start: Add this to MainLifecycle.mqh to auto-validate all signals
 * 
 * Location: In the main signal generation loop, after signal is generated
 * 
 * Example usage:
 *   STradingSignal signal = GenerateICTSignal(symbol);
 *   
 *   // ADD THIS:
 *   if(g_Enable_Signal_Inversion_Debug && signal.valid)
 *   {
 *      ValidateSignalAndLogIssues(signal, symbol, htf_bias);
 *   }
 */

// Add this configuration parameter to your EA inputs:
// input bool g_Enable_Signal_Inversion_Debug = false;  // Enable signal inversion validation

// Helper function to validate and log signal issues
void ValidateSignalAndLogIssues(const STradingSignal &signal, string symbol, int expected_direction)
{
   if(!g_Enable_Signal_Inversion_Debug)
      return;

   // Test 1: Direction alignment
   if(expected_direction != 0 && signal.direction != expected_direction)
   {
      string expected_str = (expected_direction == 1 ? "BUY" : "SELL");
      string actual_str = (signal.direction == 1 ? "BUY" : signal.direction == -1 ? "SELL" : "NEUTRAL");
      
      Print("[INVERSION_WARNING] ", symbol, 
            " Expected=", expected_str, 
            " Actual=", actual_str);
      
      // Log for file
      Log(LOG_ERROR, "SignalInversionDebug",
          StringFormat("%s DIRECTION INVERSION: Expected %s but got %s (HTF Score vs Signal Mismatch)",
                       symbol, expected_str, actual_str));
   }

   // Test 2: Entry/SL/TP alignment
   if(signal.direction == 1)  // BUY
   {
      if(signal.stop_loss >= signal.entry_price)
      {
         Print("[LEVEL_INVERSION] ", symbol, 
               " BUY: SL(", signal.stop_loss, 
               ") should be < Entry(", signal.entry_price, ")");
         
         Log(LOG_ERROR, "SignalInversionDebug",
             StringFormat("%s BUY LEVEL INVERSION: SL=%.5f >= Entry=%.5f (should be <)",
                          symbol, signal.stop_loss, signal.entry_price));
      }
      
      if(signal.take_profit <= signal.entry_price)
      {
         Print("[LEVEL_INVERSION] ", symbol, 
               " BUY: TP(", signal.take_profit, 
               ") should be > Entry(", signal.entry_price, ")");
         
         Log(LOG_ERROR, "SignalInversionDebug",
             StringFormat("%s BUY LEVEL INVERSION: TP=%.5f <= Entry=%.5f (should be >)",
                          symbol, signal.take_profit, signal.entry_price));
      }
   }
   else if(signal.direction == -1)  // SELL
   {
      if(signal.stop_loss <= signal.entry_price)
      {
         Print("[LEVEL_INVERSION] ", symbol, 
               " SELL: SL(", signal.stop_loss, 
               ") should be > Entry(", signal.entry_price, ")");
         
         Log(LOG_ERROR, "SignalInversionDebug",
             StringFormat("%s SELL LEVEL INVERSION: SL=%.5f <= Entry=%.5f (should be >)",
                          symbol, signal.stop_loss, signal.entry_price));
      }
      
      if(signal.take_profit >= signal.entry_price)
      {
         Print("[LEVEL_INVERSION] ", symbol, 
               " SELL: TP(", signal.take_profit, 
               ") should be < Entry(", signal.entry_price, ")");
         
         Log(LOG_ERROR, "SignalInversionDebug",
             StringFormat("%s SELL LEVEL INVERSION: TP=%.5f >= Entry=%.5f (should be <)",
                          symbol, signal.take_profit, signal.entry_price));
      }
   }
}

// ====================================================================
// DIAGNOSTIC PRINT HELPER
// ====================================================================
// Call this to print a visual representation of the signal state
// Useful for quick debugging

void PrintSignalState(string symbol, const STradingSignal &signal, 
                      int htf_bias, ENUM_MARKET_STRUCTURE market_struct)
{
   string dir_str = (signal.direction == 1 ? "BUY " : signal.direction == -1 ? "SELL" : "NONE");
   string bias_str = (htf_bias == 1 ? "BULL" : htf_bias == -1 ? "BEAR" : "NEUT");
   string struct_str = (market_struct == MARKET_BULLISH ? "BULL" : 
                        market_struct == MARKET_BEARISH ? "BEAR" : "RANG");
   
   Print("═══════════════════════════════════════════════════════");
   Print("SIGNAL STATE: ", symbol);
   Print("───────────────────────────────────────────────────────");
   Print("Direction:  ", dir_str, "  | HTF Bias: ", bias_str, "  | Market: ", struct_str);
   Print("Entry:  ", DoubleToString(signal.entry_price, 5));
   Print("S/L:    ", DoubleToString(signal.stop_loss, 5), 
         (signal.direction == 1 ? "  (should be <)" : signal.direction == -1 ? "  (should be >)" : ""));
   Print("T/P:    ", DoubleToString(signal.take_profit, 5), 
         (signal.direction == 1 ? "  (should be >)" : signal.direction == -1 ? "  (should be <)" : ""));
   Print("R/R:    ", DoubleToString(signal.risk_reward_ratio, 2));
   Print("Valid:  ", (signal.valid ? "YES" : "NO"));
   Print("═══════════════════════════════════════════════════════");
}

// ====================================================================
// BATCH VALIDATION REPORT
// ====================================================================
// Call this after running multiple signals to get a summary report

struct SSignalValidationBatch
{
   int total_signals;
   int inverted_directions;
   int inverted_levels;
   int correct_signals;
   string first_error;
};

SSignalValidationBatch g_validation_batch;

void InitializeValidationBatch()
{
   g_validation_batch.total_signals = 0;
   g_validation_batch.inverted_directions = 0;
   g_validation_batch.inverted_levels = 0;
   g_validation_batch.correct_signals = 0;
   g_validation_batch.first_error = "";
}

void ValidateSignalBatch(const STradingSignal &signal, string symbol, int expected_direction)
{
   g_validation_batch.total_signals++;

   bool direction_ok = (expected_direction == 0 || signal.direction == expected_direction);
   bool levels_ok = false;
   
   if(signal.direction == 1)
      levels_ok = (signal.stop_loss < signal.entry_price && signal.take_profit > signal.entry_price);
   else if(signal.direction == -1)
      levels_ok = (signal.stop_loss > signal.entry_price && signal.take_profit < signal.entry_price);
   else
      levels_ok = true;  // Neutral is always valid

   if(!direction_ok)
   {
      g_validation_batch.inverted_directions++;
      if(StringLen(g_validation_batch.first_error) == 0)
         g_validation_batch.first_error = symbol + ": direction mismatch";
   }

   if(!levels_ok)
   {
      g_validation_batch.inverted_levels++;
      if(StringLen(g_validation_batch.first_error) == 0)
         g_validation_batch.first_error = symbol + ": inverted levels";
   }

   if(direction_ok && levels_ok)
      g_validation_batch.correct_signals++;
}

void PrintValidationBatchReport()
{
   double inversion_rate = 0;
   double level_inversion_rate = 0;
   if(g_validation_batch.total_signals > 0)
   {
      inversion_rate = (double)g_validation_batch.inverted_directions / g_validation_batch.total_signals * 100.0;
      level_inversion_rate = (double)g_validation_batch.inverted_levels / g_validation_batch.total_signals * 100.0;
   }

   Print("\n═══════════════════════════════════════════════════════");
   Print("VALIDATION BATCH REPORT");
   Print("───────────────────────────────────────────────────────");
   Print("Total Signals Analyzed: ", g_validation_batch.total_signals);
   Print("Correct Signals:        ", g_validation_batch.correct_signals, 
         " (", DoubleToString(100 - inversion_rate - level_inversion_rate, 1), "%)");
   Print("Direction Inversions:   ", g_validation_batch.inverted_directions, 
         " (", DoubleToString(inversion_rate, 1), "%)");
   Print("Level Inversions:       ", g_validation_batch.inverted_levels, 
         " (", DoubleToString(level_inversion_rate, 1), "%)");
   
   if(StringLen(g_validation_batch.first_error) > 0)
      Print("First Error:            ", g_validation_batch.first_error);
   
   if(inversion_rate > 25.0)
      Print("⚠️  WARNING: High inversion rate detected!");
   
   Print("═══════════════════════════════════════════════════════\n");

   // Also log to file
   Log(LOG_INFO, "ValidationBatch",
       StringFormat("Total=%d Correct=%d Inverted_Dir=%d(%.1f%%) Inverted_Levels=%d(%.1f%%)",
                    g_validation_batch.total_signals,
                    g_validation_batch.correct_signals,
                    g_validation_batch.inverted_directions, inversion_rate,
                    g_validation_batch.inverted_levels, level_inversion_rate));
}

// ====================================================================
// USAGE TEMPLATE
// ====================================================================
/*

// 1. In your EA inputs section, add:
input bool g_Enable_Signal_Inversion_Debug = false;  // CRITICAL FIX: Disabled by default to prevent performance degradation

// 2. In OnInit(), add:
InitializeValidationBatch();

// 3. In your main signal processing loop, add:
void ProcessSignalsWithValidation(string &symbols[], int symbol_count)
{
   for(int i = 0; i < symbol_count; i++)
   {
      int htf_bias = GetHTFBias(symbols[i]);
      STradingSignal signal = GenerateICTSignal(symbols[i]);
      
      // Validate
      ValidateSignalAndLogIssues(signal, symbols[i], htf_bias);
      ValidateSignalBatch(signal, symbols[i], htf_bias);
      
      // Optional: print state for first signal
      if(i == 0 && g_debug_signals_enabled)
      {
         ENUM_MARKET_STRUCTURE struct_tf = (ENUM_MARKET_STRUCTURE)DetectMarketStructure(symbols[i], Signal_TF);
         PrintSignalState(symbols[i], signal, htf_bias, struct_tf);
      }
      
      // Process signal normally...
   }
}

// 4. At the end of day/session, print report:
void OnDeinit(const int reason)
{
   if(g_Enable_Signal_Inversion_Debug)
   {
      PrintValidationBatchReport();
   }
   // ... rest of cleanup
}

*/

// END OF SIGNAL INVERSION DEBUG QUICK START
