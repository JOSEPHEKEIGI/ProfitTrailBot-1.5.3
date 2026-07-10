#ifndef DIAGNOSTICS_MQH
#define DIAGNOSTICS_MQH

void ResetDebugCounters()
{
   g_debug_counters.signals_generated = 0;
   g_debug_counters.signals_valid = 0;
   g_debug_counters.signals_rejected = 0;
   g_debug_counters.trades_queued = 0;
   g_debug_counters.trades_executed = 0;
   g_debug_counters.trades_failed = 0;
   g_debug_counters.last_reset = TimeCurrent();
}

bool IsNonProductionRuntime()
{
   if((bool)MQLInfoInteger(MQL_OPTIMIZATION))
      return false;
   if((bool)MQLInfoInteger(MQL_TESTER))
      return true;
   return (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO);
}

bool ManualDiagnosticsSurfaceEnabled(bool log_block = false, string context = "Diagnostics")
{
   bool enabled = (Enable_Manual_Test_Hotkeys && IsNonProductionRuntime());
   if(!enabled && log_block)
   {
      static datetime last_manual_surface_log = 0;
      datetime now = TimeCurrent();
      if(last_manual_surface_log == 0 || (now - last_manual_surface_log) >= 30)
      {
         Log(LOG_WARNING, context,
             "Manual diagnostics surface blocked unless Enable_Manual_Test_Hotkeys=true in tester/demo runtime");
         last_manual_surface_log = now;
      }
   }
   return enabled;
}

void PrintDebugReport()
{
   // CRITICAL FIX: Use Log() instead of Print() to prevent debug spam
   datetime now = TimeCurrent();
   int elapsed_minutes = (int)((now - g_debug_counters.last_reset) / 60);
   
   if(!g_Enable_Institutional_Debug)
      return;  // Only print debug report if institutional debug enabled
   
   Log(LOG_INFO, "DebugReport", "=== SIGNAL & TRADE DEBUG REPORT ===");
   Log(LOG_INFO, "DebugReport", "Time Period: " + IntegerToString(elapsed_minutes) + " minutes");
   Log(LOG_INFO, "DebugReport", "Signals Generated: " + IntegerToString(g_debug_counters.signals_generated));
   Log(LOG_INFO, "DebugReport", "Signals Valid: " + IntegerToString(g_debug_counters.signals_valid));
   Log(LOG_INFO, "DebugReport", "Signals Rejected: " + IntegerToString(g_debug_counters.signals_rejected));
   Log(LOG_INFO, "DebugReport", "Trades Queued: " + IntegerToString(g_debug_counters.trades_queued));
   Log(LOG_INFO, "DebugReport", "Trades Executed: " + IntegerToString(g_debug_counters.trades_executed));
   Log(LOG_INFO, "DebugReport", "Trades Failed: " + IntegerToString(g_debug_counters.trades_failed));
   Log(LOG_INFO, "DebugReport", "Reject Stage Mix: " + GetRejectStageSummary());
   Log(LOG_INFO, "DebugReport", "Top Reject Reasons: " + GetTopRejectReasonsSummary(5));
   double success_rate = (g_debug_counters.signals_generated > 0 ? 
         (double)g_debug_counters.signals_valid / g_debug_counters.signals_generated * 100 : 0);
   Log(LOG_INFO, "DebugReport", "Success Rate: " + DoubleToString(success_rate, 2) + "%");
   Log(LOG_INFO, "DebugReport", "===================================");
}

bool ForceSignalGeneration(string symbol, int direction = 0)
{
   if(!ManualDiagnosticsSurfaceEnabled(true, "ForceSignalGeneration"))
      return false;

   Print("[TEST] Forcing signal generation for ", symbol, " direction: ", direction);
   
   if(!IsValidSymbol(symbol))
   {
      Print("[TEST ERROR] Invalid symbol: ", symbol);
      return false;
   }
   
   STradingSignal test_signal = GenerateTradingSignal(symbol);
   
   if(direction != 0)
   {
      int forced_direction = (direction > 0 ? 1 : -1);
      int forced_symbol_index = GetSymbolIndex(symbol);
      if(forced_symbol_index < 0)
      {
         Print("[TEST ERROR] Cannot force signal: symbol index not found for ", symbol);
         return false;
      }

      if(!RefreshSymbolCache(forced_symbol_index))
      {
         Print("[TEST ERROR] Cannot force signal: cache refresh failed for ", symbol);
         return false;
      }

      double bid = g_symbols[forced_symbol_index].cache.bid;
      double ask = g_symbols[forced_symbol_index].cache.ask;
      if(bid <= 0.0 || ask <= 0.0 || bid >= ask)
      {
         bid = SymbolInfoDouble(symbol, SYMBOL_BID);
         ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      }

      double point = g_symbols[forced_symbol_index].cache.point;
      if(point <= 0.0)
         point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0)
         point = Point();

      int digits = g_symbols[forced_symbol_index].cache.digits;
      if(digits <= 0)
         digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

      double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tick_size <= 0.0)
         tick_size = point;

      double mid = (bid > 0.0 && ask > 0.0 ? (bid + ask) / 2.0 : 0.0);
      if(mid <= 0.0)
      {
         Print("[TEST ERROR] Cannot force signal: invalid prices for ", symbol);
         return false;
      }

      double atr_value = GetATRValue(symbol, Signal_TF);
      if(atr_value <= 0.0 || !MathIsValidNumber(atr_value))
         atr_value = mid * 0.0020;

      double stop_distance = MathMax(point * 10.0, atr_value * MathMax(0.5, ATR_SL_Multiplier));
      double target_rr = MathMax(1.2, g_Min_RR_Ratio);

      double entry_price = (forced_direction == 1 ? ask : bid);
      if(entry_price <= 0.0)
         entry_price = mid;

      double stop_loss = (forced_direction == 1 ? entry_price - stop_distance : entry_price + stop_distance);
      double take_profit = (forced_direction == 1 ? entry_price + stop_distance * target_rr : entry_price - stop_distance * target_rr);

      STradeLevelContext trade_ctx;
      string trade_ctx_error = "";
      if(!BuildTradeLevelContext(symbol, -1, trade_ctx, trade_ctx_error))
      {
         Print("[TEST ERROR] Cannot force signal: ", trade_ctx_error);
         return false;
      }

      int forced_levels_reason = TRADE_LEVELS_OK;
      if(!NormalizeAndValidateTradeLevels(symbol, trade_ctx, entry_price, stop_loss, take_profit, forced_levels_reason))
      {
         Print("[TEST ERROR] Cannot force signal: generated levels are invalid for ", symbol,
               " [", TradeLevelsReasonLabel(forced_levels_reason), "]");
         return false;
      }

      test_signal.valid = true;
      test_signal.direction = forced_direction;
      test_signal.origin = SIGNAL_ORIGIN_ICT;
      test_signal.entry_price = entry_price;
      test_signal.stop_loss = stop_loss;
      test_signal.take_profit = take_profit;
      test_signal.atr_value = atr_value;
      test_signal.risk_reward_ratio = CalculateTradeRiskRewardRatio(entry_price, stop_loss, take_profit);
      test_signal.reason = "FORCED TEST SIGNAL";
   }
   
   Print("[TEST] Signal result - Valid: ", test_signal.valid, ", Direction: ", test_signal.direction, ", Reason: ", test_signal.reason);
   
   if(test_signal.valid)
   {
      int symbol_index = GetSymbolIndex(symbol);
      if(symbol_index >= 0)
      {
         bool executed = ExecuteTrade(symbol, test_signal, symbol_index);
         Print("[TEST] Trade execution result: ", executed);
         return executed;
      }
   }
   
   return false;
}

void TestOrderBlockDetection(string symbol)
{
   Print("[TEST] Testing Order Block Detection for ", symbol);
   
   double ob_high, ob_low;
   bool bullish_ob = DetectOrderBlock(symbol, Primary_TF, 1, ob_high, ob_low);
   bool bearish_ob = DetectOrderBlock(symbol, Primary_TF, -1, ob_high, ob_low);
   
   Print("[TEST] Bullish OB: ", bullish_ob, ", Bearish OB: ", bearish_ob);
   if(bullish_ob || bearish_ob)
   {
      Print("[TEST] OB Levels - High: ", ob_high, ", Low: ", ob_low);
   }
}

void TestFVGDetection(string symbol)
{
   Print("[TEST] Testing FVG Detection for ", symbol);
   
   double fvg_high, fvg_low;
   bool bullish_fvg = DetectFairValueGap(symbol, Signal_TF, 1, fvg_high, fvg_low);
   bool bearish_fvg = DetectFairValueGap(symbol, Signal_TF, -1, fvg_high, fvg_low);
   
   Print("[TEST] Bullish FVG: ", bullish_fvg, ", Bearish FVG: ", bearish_fvg);
   if(bullish_fvg || bearish_fvg)
   {
      Print("[TEST] FVG Levels - High: ", fvg_high, ", Low: ", fvg_low);
   }
}

void TestScoringEngine(string symbol)
{
   Print("[TEST] Testing ScoringEngine for ", symbol);
   
   SFilterDiagnostic diag_buy, diag_sell;
   bool buy_result = g_scoring_engine.ShouldExecuteTrade(symbol, Signal_TF, 1, diag_buy);
   bool sell_result = g_scoring_engine.ShouldExecuteTrade(symbol, Signal_TF, -1, diag_sell);
   
   Print("[TEST] BUY - Result: ", buy_result, ", Score: ", diag_buy.trade_score, ", Reason: ", diag_buy.reason);
   Print("[TEST] SELL - Result: ", sell_result, ", Score: ", diag_sell.trade_score, ", Reason: ", diag_sell.reason);
}

void TestReversalDetection(string symbol)
{
   Print("[TEST] Testing Reversal Detection for ", symbol);
   
   if(!Enable_Reversal_Detection)
   {
      Print("[TEST] Reversal detection is disabled");
      return;
   }
   
   SReversalSignal reversal_signal = g_reversal_detector.DetectReversal(symbol, Signal_TF);
   
   Print("[TEST] Reversal Signal - Valid: ", reversal_signal.valid);
   if(reversal_signal.valid)
   {
      Print("[TEST] Direction: ", reversal_signal.direction == 1 ? "BULLISH" : "BEARISH");
      Print("[TEST] Confidence: ", DoubleToString(reversal_signal.confidence * 100, 1), "%");
      Print("[TEST] Reason: ", reversal_signal.reason);
      Print("[TEST] Divergence: ", reversal_signal.divergence_detected ? "Yes" : "No");
      Print("[TEST] Exhaustion: ", reversal_signal.exhaustion_detected ? "Yes" : "No");
      Print("[TEST] Structure Break: ", reversal_signal.structure_break ? "Yes" : "No");
      Print("[TEST] Entry Price: ", DoubleToString(reversal_signal.entry_price, 2));
      Print("[TEST] Stop Loss: ", DoubleToString(reversal_signal.stop_loss, 2));
      Print("[TEST] Take Profit: ", DoubleToString(reversal_signal.take_profit, 2));
   }
}

void TestATRCalculation(string symbol)
{
   Print("[TEST] Testing ATR Calculation for ", symbol);
   
   double atr_value = GetATRValue(symbol, Signal_TF);
   Print("[TEST] ATR Value: ", atr_value);
   
   if(atr_value <= 0)
   {
      Print("[TEST ERROR] Invalid ATR value");
   }
}

void TestPositionSizing(string symbol)
{
   Print("[TEST] Testing Position Sizing for ", symbol);
   
   double atr = GetATRValue(symbol, Signal_TF);
   if(atr > 0)
   {
      double stop_distance = atr * ATR_SL_Multiplier;
      double lot_size = CalculatePositionSize(symbol, stop_distance);
      
      Print("[TEST] ATR: ", atr, ", Stop Distance: ", stop_distance, ", Lot Size: ", lot_size);
   }
}

void TestAIPipeline(string symbol)
{
   Print("[TEST] Testing AI Pipeline for ", symbol);
   
   int symbol_index = GetSymbolIndex(symbol);
   if(symbol_index < 0)
   {
      Print("[TEST ERROR] Symbol not found: ", symbol);
      return;
   }
   
   if(!RefreshSymbolCache(symbol_index))
   {
      Print("[TEST ERROR] Failed to refresh cache for ", symbol);
      return;
   }
   
   double rsi_value = 50.0, ma_slope = 0.0, atr_value = 0.0, volume_ratio = 1.0;
   bool features_ok = GetCachedAIFeatures(symbol, rsi_value, ma_slope, atr_value, volume_ratio, Signal_TF);
   Print("[TEST] Cached AI features: OK=", features_ok, ", RSI=", DoubleToString(rsi_value, 2),
         ", MA Slope=", DoubleToString(ma_slope, 6), ", ATR=", DoubleToString(atr_value, 5),
         ", VolRatio=", DoubleToString(volume_ratio, 3));
   
   MqlRates rates[];
   if(!GetCachedRates(symbol, Signal_TF, rates, 6) || ArraySize(rates) < 6)
   {
      Print("[TEST ERROR] Failed to get rates for AI pipeline");
      return;
   }
   
   double close0 = rates[0].close;
   double close1 = rates[1].close;
   double close5 = rates[5].close;
   double vol0 = (double)rates[0].tick_volume;
   double vol1 = (double)rates[1].tick_volume;
   double vol_avg = (vol0 + vol1 > 0.0) ? (vol0 + vol1) / 2.0 : 1.0;
   
   double macd_value = 0.0;
   double stoch_value = 50.0;
   GetMomentumValues(symbol, Signal_TF, symbol_index, macd_value, stoch_value);
   
   double spread = g_symbols[symbol_index].cache.spread * g_symbols[symbol_index].cache.point;
   int htf_struct = DetectMarketStructure(symbol, Confirm_TF);
   double htf_bias_feature = (htf_struct == MARKET_BULLISH ? 1.0 : htf_struct == MARKET_BEARISH ? -1.0 : 0.0);
   double vol_regime = GetCachedVolatilityFactor(symbol, symbol_index);
   
   double buy_prob = 0.5;
   double sell_prob = 0.5;
   GetAIModuleProbabilities(close0, close1, close5, atr_value, rsi_value, ma_slope,
                            vol0, vol1, vol_avg, macd_value, stoch_value, 0.5,
                            spread, htf_bias_feature, vol_regime,
                            buy_prob, sell_prob);
   
   bool buy_valid = MathIsValidNumber(buy_prob) && buy_prob >= 0.0 && buy_prob <= 1.0;
   bool sell_valid = MathIsValidNumber(sell_prob) && sell_prob >= 0.0 && sell_prob <= 1.0;
   Print("[TEST] AI Probabilities: Buy=", DoubleToString(buy_prob, 4),
         ", Sell=", DoubleToString(sell_prob, 4),
         ", Valid=", (buy_valid && sell_valid));
   Print("[TEST] AI Confidence (max): ", DoubleToString(MathMax(buy_prob, sell_prob), 4));

   STradingSignal ai_signal = GenerateAIPrimarySignal(symbol, g_Allow_Range_Trading);
   Print("[TEST] AI Signal Valid: ", ai_signal.valid);
   Print("[TEST] AI Signal Reason: ", ai_signal.reason);
   if(StringLen(BuildStrategyOutputSummary(ai_signal, false)) > 0)
      Print("[TEST] Strategy Output: ", BuildStrategyOutputSummary(ai_signal, false));
   if(SignalHasAIDiagnostics(ai_signal))
      Print("[TEST] AI Output: ", BuildAISignalSummary(ai_signal, false));
   if(ai_signal.reversal_detected)
      Print("[TEST] AI Reversal: ", ai_signal.reversal_reason);
}

void RunComprehensiveTest(string symbol = "")
{
   if(symbol == "")
      symbol = Symbol();
      
   Print("\n=== COMPREHENSIVE TEST SUITE ===");
   Print("Testing Symbol: ", symbol);
   Print("Current Time: ", TimeToString(TimeCurrent()));
   
   // Test individual components
   TestATRCalculation(symbol);
   TestOrderBlockDetection(symbol);
   TestFVGDetection(symbol);
   TestScoringEngine(symbol);
   TestPositionSizing(symbol);
   TestReversalDetection(symbol);
   TestAIPipeline(symbol);
   
   // Test signal generation
   Print("\n[TEST] Testing Signal Generation...");
   STradingSignal test_signal = GenerateTradingSignal(symbol);
   Print("[TEST] Signal Valid: ", test_signal.valid);
   Print("[TEST] Signal Direction: ", test_signal.direction);
   Print("[TEST] Signal Reason: ", test_signal.reason);
   if(StringLen(BuildStrategyOutputSummary(test_signal, false)) > 0)
      Print("[TEST] Strategy Output: ", BuildStrategyOutputSummary(test_signal, false));
   Print("[TEST] Entry Price: ", test_signal.entry_price);
   Print("[TEST] Stop Loss: ", test_signal.stop_loss);
   Print("[TEST] Take Profit: ", test_signal.take_profit);
   Print("[TEST] Risk/Reward: ", test_signal.risk_reward_ratio);
   if(SignalHasAIDiagnostics(test_signal))
      Print("[TEST] AI Output: ", BuildAISignalSummary(test_signal, false));
   
   // Test reversal integration
   if(test_signal.reversal_detected)
   {
      Print("[TEST] Reversal Detected: ", test_signal.reversal_detected);
      Print("[TEST] Reversal Confidence: ", DoubleToString(test_signal.reversal_confidence * 100, 1), "%");
      Print("[TEST] Reversal Reason: ", test_signal.reversal_reason);
   }
   
   Print("\n=== TEST COMPLETE ===");
}

void TestBothDirections(string symbol)
{
   Log(LOG_INFO, "TestBothDirections", "=== TESTING BOTH DIRECTIONS FOR " + symbol + " ===");
   
   // Test market structure for all timeframes
   int signal_structure = DetectMarketStructure(symbol, Signal_TF);
   int primary_structure = DetectMarketStructure(symbol, Primary_TF);
   int confirm_structure = DetectMarketStructure(symbol, Confirm_TF);
   
   Log(LOG_INFO, "TestBothDirections", "Market Structure - Signal: " + MarketStructureToString(signal_structure) +
       ", Primary: " + MarketStructureToString(primary_structure) + 
       ", Confirm: " + MarketStructureToString(confirm_structure));
   
   // Test HTF bias
   int htf_bias = GetHTFBiasInstitutional(symbol);
   string htf_bias_text = (htf_bias == 1 ? "BULLISH" : htf_bias == -1 ? "BEARISH" : "NEUTRAL");
   Log(LOG_INFO, "TestBothDirections", "HTF Bias: " + htf_bias_text);
   
   // Test order blocks for both directions
   double ob_high_buy, ob_low_buy, ob_high_sell, ob_low_sell;
   bool buy_ob = DetectOrderBlock(symbol, Primary_TF, 1, ob_high_buy, ob_low_buy);
   bool sell_ob = DetectOrderBlock(symbol, Primary_TF, -1, ob_high_sell, ob_low_sell);
   
   Log(LOG_INFO, "TestBothDirections", "Order Blocks - BUY: " + (buy_ob ? "Found" : "None") +
       ", SELL: " + (sell_ob ? "Found" : "None"));
   
   Log(LOG_INFO, "TestBothDirections", "=== TEST COMPLETE ===");
}

#endif // DIAGNOSTICS_MQH
