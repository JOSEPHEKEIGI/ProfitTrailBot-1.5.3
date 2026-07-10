#ifndef VALIDATION_MQH
#define VALIDATION_MQH

bool ValidateAllInputs()
{
   bool valid = true;
   
   // DEFENSIVE APPROACH: Constrain rather than reject
   // Log issues but allow EA to continue with constrained values
   
   // Validate Risk
   if(Risk_Percent < 0.01 || Risk_Percent > 5.0)
   {
      Log(LOG_WARNING, "ValidateAllInputs", "Invalid Risk_Percent: " + DoubleToString(Risk_Percent, 2) + 
          ". Must be 0.01-5.0 (Will use constrained value at runtime)");
      valid = false;
   }
   
   // Validate RR - Ensuring Min_RR_Ratio = 1.5 is within valid range
   if(Min_RR_Ratio < 1.0 || Min_RR_Ratio > 10.0)
   {
      Log(LOG_WARNING, "ValidateAllInputs", "Invalid Min_RR_Ratio: " + DoubleToString(Min_RR_Ratio, 2) +
          ". Must be 1.0-10.0 (Will use constrained value at runtime)");
      valid = false;
   }
   
   // Validate FVG Size
   if(Min_FVG_Size_Ratio < 0.01 || Min_FVG_Size_Ratio > 0.5)
   {
      Log(LOG_WARNING, "ValidateAllInputs", "Invalid Min_FVG_Size_Ratio: " + 
          DoubleToString(Min_FVG_Size_Ratio, 3) + ". Must be 0.01-0.5 (Will use constrained value at runtime)");
      valid = false;
   }
   
   // Validate Order Block Size
   if(Min_Order_Block_Size < 0.1 || Min_Order_Block_Size > 5.0)
   {
      Log(LOG_WARNING, "ValidateAllInputs", "Invalid Min_Order_Block_Size: " + 
          DoubleToString(Min_Order_Block_Size, 2) + ". Must be 0.1-5.0 (Will use constrained value at runtime)");
      valid = false;
   }
   
   // Validate Max Trades
   if(Max_Concurrent_Trades < 1 || Max_Concurrent_Trades > 20)
   {
      Log(LOG_WARNING, "ValidateAllInputs", "Invalid Max_Concurrent_Trades: " + 
          IntegerToString(Max_Concurrent_Trades) + ". Must be 1-20 (Will use constrained value at runtime)");
      valid = false;
   }
   
   if(Max_Trades_Per_Day < 1 || Max_Trades_Per_Day > 50)
   {
      Log(LOG_WARNING, "ValidateAllInputs", "Invalid Max_Trades_Per_Day: " + 
          IntegerToString(Max_Trades_Per_Day) + ". Must be 1-50 (Will use constrained value at runtime)");
      valid = false;
   }
   
   // Validate ATR Period
   if(ATR_Period < 5 || ATR_Period > 100)
   {
      Log(LOG_WARNING, "ValidateAllInputs", "Invalid ATR_Period: " + 
          IntegerToString(ATR_Period) + ". Must be 5-100 (Will use constrained value at runtime)");
      valid = false;
   }
   
   // NEW: TIMEFRAME VALIDATION - Add comprehensive timeframe validation
   if(!ValidateTimeframes())
   {
      Log(LOG_WARNING, "ValidateAllInputs", "Timeframe validation detected issues (Will use constrained values at runtime)");
      valid = false;
   }
   
   // Validate Lookback Bars
   if(Trend_Lookback_Bars < 10 || Trend_Lookback_Bars > 500)
   {
      Log(LOG_WARNING, "ValidateAllInputs", "Invalid Trend_Lookback_Bars: " + 
          IntegerToString(Trend_Lookback_Bars) + ". Must be 10-500 (Will use constrained value at runtime)");
      valid = false;
   }
   
   // Validate Drawdown %
   // FIXED: Reset equity all-time high reference for accurate session drawdown tracking
   // This prevents stale high from previous restart from inflating perceived drawdown
   g_equity_all_time_high = AccountInfoDouble(ACCOUNT_EQUITY);
   
   if(Max_Daily_Drawdown_Pct < 1 || Max_Daily_Drawdown_Pct > 50)
   {
      Log(LOG_WARNING, "ValidateAllInputs", "Invalid Max_Daily_Drawdown_Pct: " + 
          DoubleToString(Max_Daily_Drawdown_Pct, 2) + ". Must be 1-50 (Will use constrained value at runtime)");
      valid = false;
   }
   
   if(Max_Account_Drawdown_Pct < 5 || Max_Account_Drawdown_Pct > 100)
   {
      Log(LOG_WARNING, "ValidateAllInputs", "Invalid Max_Account_Drawdown_Pct: " + 
          DoubleToString(Max_Account_Drawdown_Pct, 2) + ". Must be 5-100 (Will use constrained value at runtime)");
      valid = false;
   }

   if(PerTrade_Drawdown_Pct < 0.0 || PerTrade_Drawdown_Pct > 200.0)
   {
      Log(LOG_WARNING, "ValidateAllInputs", "Invalid PerTrade_Drawdown_Pct: " +
          DoubleToString(PerTrade_Drawdown_Pct, 1) + ". Must be 0.0-200.0 (Will use constrained value at runtime)");
      valid = false;
   }

   if(PerTrade_Drawdown_Min_Hold_Seconds < 0 || PerTrade_Drawdown_Min_Hold_Seconds > 86400)
   {
      Log(LOG_WARNING, "ValidateAllInputs", "Invalid PerTrade_Drawdown_Min_Hold_Seconds: " +
          IntegerToString(PerTrade_Drawdown_Min_Hold_Seconds) + ". Must be 0-86400 (Will use constrained value at runtime)");
      valid = false;
   }

   if(PerTrade_Drawdown_Min_Loss_Currency < 0.0 || PerTrade_Drawdown_Min_Loss_Currency > 100000.0)
   {
      Log(LOG_WARNING, "ValidateAllInputs", "Invalid PerTrade_Drawdown_Min_Loss_Currency: " +
          DoubleToString(PerTrade_Drawdown_Min_Loss_Currency, 2) + ". Must be 0.0-100000.0 (Will use constrained value at runtime)");
      valid = false;
   }

   if(MaxAcceptableDrawdown < 0.0 || MaxAcceptableDrawdown > 1000000.0)
   {
      Log(LOG_WARNING, "ValidateAllInputs", "Invalid MaxAcceptableDrawdown: " +
          DoubleToString(MaxAcceptableDrawdown, 2) + ". Must be 0.0-1000000.0 account currency (Will use constrained value at runtime)");
      valid = false;
   }

   if(Peak_Profit_Drawdown_Pct < 0.0 || Peak_Profit_Drawdown_Pct > 100.0)
   {
      Log(LOG_WARNING, "ValidateAllInputs", "Invalid Peak_Profit_Drawdown_Pct: " +
          DoubleToString(Peak_Profit_Drawdown_Pct, 1) + ". Must be 0-100 (Will use constrained value at runtime)");
      valid = false;
   }

   if(Peak_Profit_Min_R < 0.0 || Peak_Profit_Min_R > 50.0)
   {
      Log(LOG_WARNING, "ValidateAllInputs", "Invalid Peak_Profit_Min_R: " +
          DoubleToString(Peak_Profit_Min_R, 2) + ". Must be 0.0-50.0 (Will use constrained value at runtime)");
      valid = false;
   }
   
   // Institutional risk controls validation
   if(Max_Open_Risk_Pct < 0.0 || Max_Open_Risk_Pct > 100.0)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Max_Open_Risk_Pct: " + 
          DoubleToString(Max_Open_Risk_Pct, 2) + ". Must be 0-100 (0=auto)");
      valid = false;
   }
   
   if(Max_Symbol_Risk_Pct < 0.0 || Max_Symbol_Risk_Pct > 100.0)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Max_Symbol_Risk_Pct: " + 
          DoubleToString(Max_Symbol_Risk_Pct, 2) + ". Must be 0-100 (0=auto)");
      valid = false;
   }
   
   if(Max_Open_Risk_Pct > 0.0 && Max_Symbol_Risk_Pct > Max_Open_Risk_Pct)
   {
      Log(LOG_WARNING, "ValidateAllInputs", "Max_Symbol_Risk_Pct exceeds Max_Open_Risk_Pct. Symbol limit will be capped by open risk.");
   }
   
   if(Max_Margin_Usage_Pct < 0.0 || Max_Margin_Usage_Pct > 100.0)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Max_Margin_Usage_Pct: " + 
          DoubleToString(Max_Margin_Usage_Pct, 1) + ". Must be 0-100 (0=disable)");
      valid = false;
   }
   
   if(Min_Margin_Level_Pct < 0.0 || Min_Margin_Level_Pct > 1000.0)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Min_Margin_Level_Pct: " + 
          DoubleToString(Min_Margin_Level_Pct, 1) + ". Must be 0-1000 (0=disable)");
      valid = false;
   }
   
   if(Max_Consecutive_Losses < 0 || Max_Consecutive_Losses > 50)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Max_Consecutive_Losses: " + 
          IntegerToString(Max_Consecutive_Losses) + ". Must be 0-50");
      valid = false;
   }

   // Kill Switch validation: enum mode is auto-validated; currency override checked below
   if(Kill_Switch_Max_Daily_Loss_Ccy < 0.0)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Kill_Switch_Max_Daily_Loss_Ccy: " +
          DoubleToString(Kill_Switch_Max_Daily_Loss_Ccy, 2) + ". Must be >= 0.0");
      valid = false;
   }

   if(Kill_Switch_Max_Daily_Loss_Ccy < 0.0)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Kill_Switch_Max_Daily_Loss_Ccy: " +
          DoubleToString(Kill_Switch_Max_Daily_Loss_Ccy, 2) + ". Must be >= 0");
      valid = false;
   }

   if(Integrity_Min_Aligned_TF < 0 || Integrity_Min_Aligned_TF > 4)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Integrity_Min_Aligned_TF: " +
          IntegerToString(Integrity_Min_Aligned_TF) + ". Must be 0-4");
      valid = false;
   }

   if(Integrity_Min_HTF_Bias_Score < 0 || Integrity_Min_HTF_Bias_Score > 10)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Integrity_Min_HTF_Bias_Score: " +
          IntegerToString(Integrity_Min_HTF_Bias_Score) + ". Must be 0-10");
      valid = false;
   }

   if(Max_Signal_Age_Seconds < 0 || Max_Signal_Age_Seconds > 3600)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Max_Signal_Age_Seconds: " +
          IntegerToString(Max_Signal_Age_Seconds) + ". Must be 0-3600");
      valid = false;
   }

   if(Max_Tick_Age_Seconds < 1 || Max_Tick_Age_Seconds > 60)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Max_Tick_Age_Seconds: " +
          IntegerToString(Max_Tick_Age_Seconds) + ". Must be 1-60");
      valid = false;
   }

   if(Execution_Max_Slippage_Pips < 0.0 || Execution_Max_Slippage_Pips > 50.0)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Execution_Max_Slippage_Pips: " +
          DoubleToString(Execution_Max_Slippage_Pips, 2) + ". Must be 0-50");
      valid = false;
   }
   
   if(Loss_Cooldown_Minutes < 0 || Loss_Cooldown_Minutes > 1440)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Loss_Cooldown_Minutes: " + 
          IntegerToString(Loss_Cooldown_Minutes) + ". Must be 0-1440");
      valid = false;
   }

   if(Enable_Symbol_Loss_Circuit_Breaker)
   {
      if(Symbol_Loss_Streak_Threshold < 1 || Symbol_Loss_Streak_Threshold > 20)
      {
         Log(LOG_ERROR, "ValidateAllInputs", "Invalid Symbol_Loss_Streak_Threshold: " +
             IntegerToString(Symbol_Loss_Streak_Threshold) + ". Must be 1-20");
         valid = false;
      }

      if(Symbol_Loss_Streak_Window_Minutes < 1 || Symbol_Loss_Streak_Window_Minutes > 720)
      {
         Log(LOG_ERROR, "ValidateAllInputs", "Invalid Symbol_Loss_Streak_Window_Minutes: " +
             IntegerToString(Symbol_Loss_Streak_Window_Minutes) + ". Must be 1-720");
         valid = false;
      }

      if(Symbol_Loss_Cooldown_Minutes < 1 || Symbol_Loss_Cooldown_Minutes > 1440)
      {
         Log(LOG_ERROR, "ValidateAllInputs", "Invalid Symbol_Loss_Cooldown_Minutes: " +
             IntegerToString(Symbol_Loss_Cooldown_Minutes) + ". Must be 1-1440");
         valid = false;
      }
   }

   if(Abnormal_Spread_Spike_Threshold < 1 || Abnormal_Spread_Spike_Threshold > 20)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Abnormal_Spread_Spike_Threshold: " +
          IntegerToString(Abnormal_Spread_Spike_Threshold) + ". Must be 1-20");
      valid = false;
   }

   if(Abnormal_Market_Pause_Minutes < 1 || Abnormal_Market_Pause_Minutes > 240)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Abnormal_Market_Pause_Minutes: " +
          IntegerToString(Abnormal_Market_Pause_Minutes) + ". Must be 1-240");
      valid = false;
   }

   // Validate Retry Settings
   if(Max_Retry_Attempts < 1 || Max_Retry_Attempts > 100)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Max_Retry_Attempts: " + 
          IntegerToString(Max_Retry_Attempts) + ". Must be 1-100");
      valid = false;
   }
   
   if(Retry_Interval_Seconds < 1 || Retry_Interval_Seconds > 60)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Retry_Interval_Seconds: " + 
          IntegerToString(Retry_Interval_Seconds) + ". Must be 1-60");
      valid = false;
   }

   if(Max_Queued_Signal_Age_Minutes < 1 || Max_Queued_Signal_Age_Minutes > 1440)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Max_Queued_Signal_Age_Minutes: " +
          IntegerToString(Max_Queued_Signal_Age_Minutes) + ". Must be 1-1440");
      valid = false;
   }

   if(Signal_Check_Seconds < 1 || Signal_Check_Seconds > 3600)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Signal_Check_Seconds: " +
          IntegerToString(Signal_Check_Seconds) + ". Must be 1-3600");
      valid = false;
   }

   if(Housekeeping_Interval_Seconds < 1 || Housekeeping_Interval_Seconds > 3600)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Housekeeping_Interval_Seconds: " +
          IntegerToString(Housekeeping_Interval_Seconds) + ". Must be 1-3600");
      valid = false;
   }

   if(Housekeeping_Bar_Interval < 1 || Housekeeping_Bar_Interval > 1000)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Housekeeping_Bar_Interval: " +
          IntegerToString(Housekeeping_Bar_Interval) + ". Must be 1-1000");
      valid = false;
   }

   if(ATR_Handle_Validate_Bars < 0 || ATR_Handle_Validate_Bars > 10000)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid ATR_Handle_Validate_Bars: " +
          IntegerToString(ATR_Handle_Validate_Bars) + ". Must be 0-10000");
      valid = false;
   }

   if(Signal_Cooldown_Bars < 0 || Signal_Cooldown_Bars > 50)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Signal_Cooldown_Bars: " +
          IntegerToString(Signal_Cooldown_Bars) + ". Must be 0-50");
      valid = false;
   }

   // Auto-regime router and suitability-hunt profile validation
   if(Auto_Regime_Strong_Bias_MinScore < 3 || Auto_Regime_Strong_Bias_MinScore > 7)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Auto_Regime_Strong_Bias_MinScore: " +
          IntegerToString(Auto_Regime_Strong_Bias_MinScore) + ". Must be 3-7");
      valid = false;
   }

   if(Auto_Regime_Intra_HighLow_MaxVolatility < 0.70 || Auto_Regime_Intra_HighLow_MaxVolatility > 1.80)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Auto_Regime_Intra_HighLow_MaxVolatility: " +
          DoubleToString(Auto_Regime_Intra_HighLow_MaxVolatility, 2) + ". Must be 0.70-1.80");
      valid = false;
   }

   if(Suitability_Weak_Bias_MaxScore < 2 || Suitability_Weak_Bias_MaxScore > 6)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Suitability_Weak_Bias_MaxScore: " +
          IntegerToString(Suitability_Weak_Bias_MaxScore) + ". Must be 2-6");
      valid = false;
   }

   if(Suitability_High_Volatility_Factor < 1.05 || Suitability_High_Volatility_Factor > 2.20)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Suitability_High_Volatility_Factor: " +
          DoubleToString(Suitability_High_Volatility_Factor, 2) + ". Must be 1.05-2.20");
      valid = false;
   }

   if(Regime_Risk_Multiplier_Trend < 0.25 || Regime_Risk_Multiplier_Trend > 3.00)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Regime_Risk_Multiplier_Trend: " +
          DoubleToString(Regime_Risk_Multiplier_Trend, 2) + ". Must be 0.25-3.00");
      valid = false;
   }

   if(Regime_Risk_Multiplier_Range < 0.25 || Regime_Risk_Multiplier_Range > 3.00)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Regime_Risk_Multiplier_Range: " +
          DoubleToString(Regime_Risk_Multiplier_Range, 2) + ". Must be 0.25-3.00");
      valid = false;
   }

   if(Regime_Risk_Multiplier_Retracement < 0.25 || Regime_Risk_Multiplier_Retracement > 3.00)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Regime_Risk_Multiplier_Retracement: " +
          DoubleToString(Regime_Risk_Multiplier_Retracement, 2) + ". Must be 0.25-3.00");
      valid = false;
   }

   ENUM_STRATEGY_MIX strategy_mix_effective = NormalizeStrategyMix(Strategy_Mix);
   if(strategy_mix_effective != Strategy_Mix)
   {
      Log(LOG_WARNING, "ValidateAllInputs",
          "Invalid Strategy_Mix value " + IntegerToString((int)Strategy_Mix) +
          " detected; runtime will fall back to legacy mixed routing.");
   }

   bool single_strategy_mix =
      (strategy_mix_effective == STRAT_ICT_ONLY ||
       strategy_mix_effective == STRAT_AI_ONLY ||
       strategy_mix_effective == STRAT_KIM_ONLY);
   if(single_strategy_mix && Suitability_Allow_CrossRole_Fallbacks)
   {
      Log(LOG_WARNING, "ValidateAllInputs",
          "Suitability_Allow_CrossRole_Fallbacks has limited effect in single-strategy Strategy_Mix modes.");
   }

   bool ai_strategy_expected =
      (strategy_mix_effective == STRAT_AI_ONLY ||
       strategy_mix_effective == STRAT_BOTH ||
       strategy_mix_effective == STRAT_AI_KIM ||
       strategy_mix_effective == STRAT_ALL_THREE ||
       strategy_mix_effective == STRAT_EITHER);
   if(!Enable_AI_Trend_Predictor && ai_strategy_expected)
   {
      Log(LOG_WARNING, "ValidateAllInputs",
          "AI-focused Strategy_Mix selected while Enable_AI_Trend_Predictor=false; routing will degrade/fallback.");
   }

   if(Disable_All_Gating_Master_Switch)
   {
      bool detailed_gates_enabled =
         Enable_Confluence_Check || Enable_HTF_Bias_Check ||
         Require_FVG_For_Trade || Require_BOS_Confirmation ||
         Require_First_Retracement_After_BOS || Enable_ICT_Smart_Entry_Validation ||
         Enable_Entry_Distance_Validation || Enable_Max_Risk_Distance_Validation ||
         AI_Require_Agreement || Enable_Spread_Gates || Enable_Session_Gates ||
         Enable_Exposure_Gates || Enable_Abnormal_Market_Pause ||
         Enable_Symbol_Loss_Circuit_Breaker;
      if(detailed_gates_enabled)
      {
         Log(LOG_WARNING, "ValidateAllInputs",
             "Disable_All_Gating_Master_Switch=true makes detailed gate toggles redundant; they are bypassed at runtime.");
      }
   }

   if(!Enable_AI_Trend_Predictor &&
      (AI_Require_Agreement || AI_Use_Enhanced_Targets || AI_Use_Risk_Adjustment))
   {
      Log(LOG_WARNING, "ValidateAllInputs",
          "AI feature toggles are set while Enable_AI_Trend_Predictor=false; agreement/target/risk AI options will remain inactive.");
   }

   if(AI_Trend_Confidence < 0 || AI_Trend_Confidence > 5)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid AI_Trend_Confidence: " +
          IntegerToString(AI_Trend_Confidence) + ". Must be 0-5");
      valid = false;
   }

   if(AI_Buy_Confidence_Threshold < 0.40 || AI_Buy_Confidence_Threshold > 0.95)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid AI_Buy_Confidence_Threshold: " +
          DoubleToString(AI_Buy_Confidence_Threshold, 2) + ". Must be 0.40-0.95");
      valid = false;
   }

   if(AI_Sell_Confidence_Threshold < 0.40 || AI_Sell_Confidence_Threshold > 0.95)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid AI_Sell_Confidence_Threshold: " +
          DoubleToString(AI_Sell_Confidence_Threshold, 2) + ". Must be 0.40-0.95");
      valid = false;
   }

   if(AI_Min_Directional_Edge < 0.0 || AI_Min_Directional_Edge > 0.50)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid AI_Min_Directional_Edge: " +
          DoubleToString(AI_Min_Directional_Edge, 2) + ". Must be 0.00-0.50");
      valid = false;
   }

   if(AI_Min_Expected_Value_R < 0.0 || AI_Min_Expected_Value_R > 2.0)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid AI_Min_Expected_Value_R: " +
          DoubleToString(AI_Min_Expected_Value_R, 2) + ". Must be 0.00-2.00");
      valid = false;
   }

   if(AI_Max_Spread_to_ATR < 0.0 || AI_Max_Spread_to_ATR > 1.0)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid AI_Max_Spread_to_ATR: " +
          DoubleToString(AI_Max_Spread_to_ATR, 2) + ". Must be 0.00-1.00");
      valid = false;
   }

   if(AI_Low_Confidence_Threshold < 0.50 || AI_Low_Confidence_Threshold > 0.90)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid AI_Low_Confidence_Threshold: " +
          DoubleToString(AI_Low_Confidence_Threshold, 2) + ". Must be 0.50-0.90");
      valid = false;
   }

   if(AI_Low_Confidence_Extra_RR < 0.0 || AI_Low_Confidence_Extra_RR > 3.0)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid AI_Low_Confidence_Extra_RR: " +
          DoubleToString(AI_Low_Confidence_Extra_RR, 2) + ". Must be 0.00-3.00");
      valid = false;
   }

   if(AI_Min_Aligned_Structures < 1 || AI_Min_Aligned_Structures > 3)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid AI_Min_Aligned_Structures: " +
          IntegerToString(AI_Min_Aligned_Structures) + ". Must be 1-3");
      valid = false;
   }

   if(AI_Max_Opposing_Structures < 0 || AI_Max_Opposing_Structures > 2)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid AI_Max_Opposing_Structures: " +
          IntegerToString(AI_Max_Opposing_Structures) + ". Must be 0-2");
      valid = false;
   }

   if(AI_Model_HotReload_Check_Seconds < 1 || AI_Model_HotReload_Check_Seconds > 3600)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid AI_Model_HotReload_Check_Seconds: " +
          IntegerToString(AI_Model_HotReload_Check_Seconds) + ". Must be 1-3600");
      valid = false;
   }

   // AI candle quality filter validation
   if(Enable_AI_Candle_Quality_Filter)
   {
      if(AI_Candle_Quality_Lookback_Bars < 2 || AI_Candle_Quality_Lookback_Bars > 5)
      {
         Log(LOG_ERROR, "ValidateAllInputs", "Invalid AI_Candle_Quality_Lookback_Bars: " +
             IntegerToString(AI_Candle_Quality_Lookback_Bars) + ". Must be 2-5");
         valid = false;
      }

      if(AI_Candle_Min_Quality_Score < 0.0 || AI_Candle_Min_Quality_Score > 1.0)
      {
         Log(LOG_ERROR, "ValidateAllInputs", "Invalid AI_Candle_Min_Quality_Score: " +
             DoubleToString(AI_Candle_Min_Quality_Score, 2) + ". Must be 0.00-1.00");
         valid = false;
      }

      if(AI_Candle_Min_Body_Ratio < 0.05 || AI_Candle_Min_Body_Ratio > 0.95)
      {
         Log(LOG_ERROR, "ValidateAllInputs", "Invalid AI_Candle_Min_Body_Ratio: " +
             DoubleToString(AI_Candle_Min_Body_Ratio, 2) + ". Must be 0.05-0.95");
         valid = false;
      }

      if(AI_Candle_Max_Opposite_Wick_Ratio < 0.05 || AI_Candle_Max_Opposite_Wick_Ratio > 0.95)
      {
         Log(LOG_ERROR, "ValidateAllInputs", "Invalid AI_Candle_Max_Opposite_Wick_Ratio: " +
             DoubleToString(AI_Candle_Max_Opposite_Wick_Ratio, 2) + ". Must be 0.05-0.95");
         valid = false;
      }

      if(AI_Candle_ATR_Min_Range_Factor < 0.05 || AI_Candle_ATR_Min_Range_Factor > 5.0)
      {
         Log(LOG_ERROR, "ValidateAllInputs", "Invalid AI_Candle_ATR_Min_Range_Factor: " +
             DoubleToString(AI_Candle_ATR_Min_Range_Factor, 2) + ". Must be 0.05-5.00");
         valid = false;
      }

      if(AI_Candle_ATR_Max_Range_Factor < 0.10 || AI_Candle_ATR_Max_Range_Factor > 8.0)
      {
         Log(LOG_ERROR, "ValidateAllInputs", "Invalid AI_Candle_ATR_Max_Range_Factor: " +
             DoubleToString(AI_Candle_ATR_Max_Range_Factor, 2) + ". Must be 0.10-8.00");
         valid = false;
      }

      if(AI_Candle_ATR_Max_Range_Factor <= AI_Candle_ATR_Min_Range_Factor)
      {
         Log(LOG_ERROR, "ValidateAllInputs", "AI candle ATR range factors invalid: max must be greater than min");
         valid = false;
      }
   }
   
   // NEW: Session time validation
   if(London_Session_Start >= London_Session_End)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid London session times");
      valid = false;
   }
   
   if(NewYork_Session_Start >= NewYork_Session_End)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid NY session times");
      valid = false;
   }
   
   // NEW: Spread validation
   if(Max_Spread_Pips < 1 || Max_Spread_Pips > 999)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Max_Spread_Pips: " + 
          IntegerToString(Max_Spread_Pips) + ". Must be 1-1000");
      valid = false;
   }

   // Symbol spread config validated via struct initialization in SymbolManagement.mqh

   if(Max_Entry_Distance_Pct < 0.1 || Max_Entry_Distance_Pct > 5.0)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Max_Entry_Distance_Pct: " +
          DoubleToString(Max_Entry_Distance_Pct, 2) + ". Must be 0.10-5.00");
      valid = false;
   }

   if(DrawdownLimitToClose > 0.0)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(balance > 0.0 && DrawdownLimitToClose <= balance * 0.005)
      {
         Log(LOG_WARNING, "ValidateAllInputs",
             "DrawdownLimitToClose is very tight relative to balance (" +
             DoubleToString(DrawdownLimitToClose, 2) + " <= 0.5% of $" +
             DoubleToString(balance, 2) +
             "). Consider 0.0 to disable basket close and rely on percentage drawdown guards.");
      }
   }

   if(ProfitTarget_Reenter_Trade && ProfitTarget_Halt_Bot)
   {
      Log(LOG_WARNING, "ValidateAllInputs",
          "ProfitTarget_Reenter_Trade=true and ProfitTarget_Halt_Bot=true: bot halt takes precedence and re-entry will be skipped.");
   }

   // Institutional scoring engine validation
   if(Execution_Score_Threshold < 40.0 || Execution_Score_Threshold > 95.0)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Execution_Score_Threshold: " +
          DoubleToString(Execution_Score_Threshold, 1) + ". Must be 40.0-95.0");
      valid = false;
   }

   if(Scoring_Precheck_Buffer < 0.0 || Scoring_Precheck_Buffer > 20.0)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Scoring_Precheck_Buffer: " +
          DoubleToString(Scoring_Precheck_Buffer, 1) + ". Must be 0.0-20.0");
      valid = false;
   }

   if(Scoring_Target_Weight_Sum < 10.0 || Scoring_Target_Weight_Sum > 1000.0)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Scoring_Target_Weight_Sum: " +
          DoubleToString(Scoring_Target_Weight_Sum, 1) + ". Must be 10.0-1000.0");
      valid = false;
   }

   if(Scoring_Unique_Min_Delta < 0.0 || Scoring_Unique_Min_Delta > 25.0)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Scoring_Unique_Min_Delta: " +
          DoubleToString(Scoring_Unique_Min_Delta, 2) + ". Must be 0.0-25.0");
      valid = false;
   }

   if(Scoring_Adaptive_Threshold_Boost < 0.0 || Scoring_Adaptive_Threshold_Boost > 30.0)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Scoring_Adaptive_Threshold_Boost: " +
          DoubleToString(Scoring_Adaptive_Threshold_Boost, 2) + ". Must be 0.0-30.0");
      valid = false;
   }

   if(Scoring_Adaptive_Risk_Weight_Boost < 0.0 || Scoring_Adaptive_Risk_Weight_Boost > 1.0)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Scoring_Adaptive_Risk_Weight_Boost: " +
          DoubleToString(Scoring_Adaptive_Risk_Weight_Boost, 2) + ". Must be 0.0-1.0");
      valid = false;
   }

   if(Scoring_Adaptive_Opp_Weight_Cut < 0.0 || Scoring_Adaptive_Opp_Weight_Cut > 0.9)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Scoring_Adaptive_Opp_Weight_Cut: " +
          DoubleToString(Scoring_Adaptive_Opp_Weight_Cut, 2) + ". Must be 0.0-0.9");
      valid = false;
   }

   // Phase 3A: Validate weights using global SScoringWeights struct instead of individual inputs
   double scoring_weights_sum = g_scoring_weights.trend + g_scoring_weights.momentum + g_scoring_weights.volatility +
                                g_scoring_weights.structure + g_scoring_weights.alignment +
                                g_scoring_weights.confirmation + g_scoring_weights.risk_reward +
                                g_scoring_weights.entry_quality + g_scoring_weights.spread + g_scoring_weights.regime;
   if(scoring_weights_sum <= 0.0)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "All scoring weights in g_scoring_weights are zero/negative. At least one must be > 0.");
      valid = false;
   }

   if(Scoring_Enforce_Unique_Weights && Scoring_Unique_Min_Delta > 0.0)
   {
      // Phase 3A: Read from global SScoringWeights struct instead of individual inputs
      double sw[10];
      sw[0] = MathMax(0.0, g_scoring_weights.trend);
      sw[1] = MathMax(0.0, g_scoring_weights.momentum);
      sw[2] = MathMax(0.0, g_scoring_weights.volatility);
      sw[3] = MathMax(0.0, g_scoring_weights.structure);
      sw[4] = MathMax(0.0, g_scoring_weights.alignment);
      sw[5] = MathMax(0.0, g_scoring_weights.confirmation);
      sw[6] = MathMax(0.0, g_scoring_weights.risk_reward);
      sw[7] = MathMax(0.0, g_scoring_weights.entry_quality);
      sw[8] = MathMax(0.0, g_scoring_weights.spread);
      sw[9] = MathMax(0.0, g_scoring_weights.regime);

      bool near_duplicates_found = false;
      for(int i = 0; i < 10; i++)
      {
         for(int j = i + 1; j < 10; j++)
         {
            if(MathAbs(sw[i] - sw[j]) < Scoring_Unique_Min_Delta)
            {
               near_duplicates_found = true;
               break;
            }
         }
         if(near_duplicates_found)
            break;
      }

      if(near_duplicates_found)
      {
         Log(LOG_WARNING, "ValidateAllInputs",
             "Scoring weights contain repeated/near-repeated values; runtime harmonization will enforce unique weight buttons.");
      }
   }

   // Soft structural gating validation
   if(Max_Soft_Gate_Failures < 0 || Max_Soft_Gate_Failures > 3)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Max_Soft_Gate_Failures: " +
          IntegerToString(Max_Soft_Gate_Failures) + ". Must be 0-3");
      valid = false;
   }

   if(Soft_Gate_Min_HTF_Bias_Score < 1 || Soft_Gate_Min_HTF_Bias_Score > 10)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Soft_Gate_Min_HTF_Bias_Score: " +
          IntegerToString(Soft_Gate_Min_HTF_Bias_Score) + ". Must be 1-10");
      valid = false;
   }

   if(Soft_Gate_Extra_RR < 0.0 || Soft_Gate_Extra_RR > 2.0)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Soft_Gate_Extra_RR: " +
          DoubleToString(Soft_Gate_Extra_RR, 2) + ". Must be 0.00-2.00");
      valid = false;
   }

   if(Max_Entry_Distance_Relaxed_Cap < Max_Entry_Distance_Pct || Max_Entry_Distance_Relaxed_Cap > 3.0)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Max_Entry_Distance_Relaxed_Cap: " +
          DoubleToString(Max_Entry_Distance_Relaxed_Cap, 2) +
          ". Must be >= Max_Entry_Distance_Pct and <= 3.0");
      valid = false;
   }

   // Reversal module parameter validation
   if(Reversal_Lookback_Bars < 8 || Reversal_Lookback_Bars > 300)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Reversal_Lookback_Bars: " +
          IntegerToString(Reversal_Lookback_Bars) + ". Must be 8-300");
      valid = false;
   }

   if(Reversal_Exhaustion_RSI_Level < 55.0 || Reversal_Exhaustion_RSI_Level > 95.0)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Reversal_Exhaustion_RSI_Level: " +
          DoubleToString(Reversal_Exhaustion_RSI_Level, 1) + ". Must be 55.0-95.0");
      valid = false;
   }

   if(Reversal_Divergence_Threshold < 0.10 || Reversal_Divergence_Threshold > 1.50)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Reversal_Divergence_Threshold: " +
          DoubleToString(Reversal_Divergence_Threshold, 2) + ". Must be 0.10-1.50");
      valid = false;
   }

   if(Reversal_Momentum_Shift_Threshold < 0.05 || Reversal_Momentum_Shift_Threshold > 2.00)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Reversal_Momentum_Shift_Threshold: " +
          DoubleToString(Reversal_Momentum_Shift_Threshold, 2) + ". Must be 0.05-2.00");
      valid = false;
   }

   if(Reversal_Weight_In_Scoring < 0.0 || Reversal_Weight_In_Scoring > 0.50)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "Invalid Reversal_Weight_In_Scoring: " +
          DoubleToString(Reversal_Weight_In_Scoring, 2) + ". Must be 0.00-0.50");
      valid = false;
   }

   bool kim_params_required =
      Enable_KImaniz_Strategy || g_KImaniz_Only_Mode ||
      strategy_mix_effective == STRAT_KIM_ONLY ||
      strategy_mix_effective == STRAT_ICT_KIM ||
      strategy_mix_effective == STRAT_AI_KIM ||
      strategy_mix_effective == STRAT_ALL_THREE;
   if(kim_params_required)
   {
      // KImaniz strategy parameter validation (OTP/Fibonacci integrity)
      if(KImaniz_Swing_Lookback_Bars < 20 || KImaniz_Swing_Lookback_Bars > 1000)
      {
         Log(LOG_ERROR, "ValidateAllInputs", "Invalid KImaniz_Swing_Lookback_Bars: " +
             IntegerToString(KImaniz_Swing_Lookback_Bars) + ". Must be 20-1000");
         valid = false;
      }

      if(KImaniz_Fib_Zone_29_Pct <= 0.0 || KImaniz_Fib_Zone_29_Pct >= 100.0)
      {
         Log(LOG_ERROR, "ValidateAllInputs", "Invalid KImaniz_Fib_Zone_29_Pct: " +
             DoubleToString(KImaniz_Fib_Zone_29_Pct, 2) + ". Must be >0 and <100");
         valid = false;
      }

      if(KImaniz_Fib_Zone_41_Pct <= 0.0 || KImaniz_Fib_Zone_41_Pct >= 100.0)
      {
         Log(LOG_ERROR, "ValidateAllInputs", "Invalid KImaniz_Fib_Zone_41_Pct: " +
             DoubleToString(KImaniz_Fib_Zone_41_Pct, 2) + ". Must be >0 and <100");
         valid = false;
      }

      if(KImaniz_Fib_Zone_29_Pct >= KImaniz_Fib_Zone_41_Pct)
      {
         Log(LOG_ERROR, "ValidateAllInputs", "Invalid KImaniz fib zone ordering: Fib_Zone_29_Pct must be < Fib_Zone_41_Pct");
         valid = false;
      }

      if(KImaniz_OTP_Low_Pct <= 0.0 || KImaniz_OTP_Low_Pct >= 100.0 ||
         KImaniz_OTP_Mid_Pct <= 0.0 || KImaniz_OTP_Mid_Pct >= 100.0 ||
         KImaniz_OTP_High_Pct <= 0.0 || KImaniz_OTP_High_Pct >= 100.0)
      {
         Log(LOG_ERROR, "ValidateAllInputs", "Invalid KImaniz OTP values: OTP_Low/Mid/High must each be >0 and <100");
         valid = false;
      }

      if(!(KImaniz_OTP_Low_Pct < KImaniz_OTP_Mid_Pct && KImaniz_OTP_Mid_Pct < KImaniz_OTP_High_Pct))
      {
         Log(LOG_ERROR, "ValidateAllInputs", "Invalid KImaniz OTP ordering: require OTP_Low < OTP_Mid < OTP_High");
         valid = false;
      }

      // Prevent target/entry zone inversion: TP fib zone must sit ahead of OTP retracement zone.
      if(KImaniz_Fib_Zone_41_Pct >= KImaniz_OTP_Low_Pct)
      {
         Log(LOG_ERROR, "ValidateAllInputs", "Invalid KImaniz zone ordering: require Fib_Zone_41_Pct < OTP_Low_Pct");
         valid = false;
      }

      if(KImaniz_Entry_Zone_Tolerance_Pct < 0.0 || KImaniz_Entry_Zone_Tolerance_Pct > 5.0)
      {
         Log(LOG_ERROR, "ValidateAllInputs", "Invalid KImaniz_Entry_Zone_Tolerance_Pct: " +
             DoubleToString(KImaniz_Entry_Zone_Tolerance_Pct, 2) + ". Must be 0.00-5.00");
         valid = false;
      }
   }
   
   // NEW: ATR multiplier validation - ensuring they work with Min_RR_Ratio = 1.5
   if(ATR_SL_Multiplier <= 0 || ATR_TP_Multiplier <= 0)
   {
      Log(LOG_ERROR, "ValidateAllInputs", "ATR multipliers must be positive");
      valid = false;
   }
   
   // NEW: Validate RR-related parameters consistency
   if(Partial_Close_RR < Min_RR_Ratio)
   {
      Log(LOG_WARNING, "ValidateAllInputs", "Partial_Close_RR (" + DoubleToString(Partial_Close_RR, 1) + 
          ") should be >= Min_RR_Ratio (" + DoubleToString(Min_RR_Ratio, 1) + ") for optimal performance");
   }

   if(Breakeven_RR <= 0)
   {
      Log(LOG_WARNING, "ValidateAllInputs", "Breakeven_RR (" + DoubleToString(Breakeven_RR, 2) + 
          ") should be > 0 for breakeven moves to trigger");
   }
   
   if(Require_BE_Before_Partial && Breakeven_RR > Partial_Close_RR)
   {
      Log(LOG_WARNING, "ValidateAllInputs", "Require_BE_Before_Partial is enabled but Breakeven_RR (" + 
          DoubleToString(Breakeven_RR, 2) + ") is greater than Partial_Close_RR (" + 
          DoubleToString(Partial_Close_RR, 2) + "). Partials may never trigger.");
   }
   
   // NEW: Validate ATR multipliers work well with Min_RR_Ratio = 1.5
   if(ATR_TP_Multiplier / ATR_SL_Multiplier < Min_RR_Ratio)
   {
      Log(LOG_WARNING, "ValidateAllInputs", "ATR TP/SL ratio (" + 
          DoubleToString(ATR_TP_Multiplier / ATR_SL_Multiplier, 2) + 
          ") is less than Min_RR_Ratio (" + DoubleToString(Min_RR_Ratio, 1) + 
          "). Consider adjusting ATR multipliers.");
   }
   
   // NEW: Telegram validation (if enabled)
   if(Enable_Telegram_Alerts)
   {
      if(StringLen(Telegram_Token) < 10 || StringLen(Telegram_Chat_ID) < 5)
      {
         Log(LOG_WARNING, "ValidateAllInputs", 
             "Telegram token/chat ID invalid format - Telegram will fail to send");
      }
   }
   
   if(!valid)
   {
      Log(LOG_WARNING, "ValidateAllInputs",
          "Configuration validation detected issues; runtime constraints/default handling will be applied where possible. Check the preceding validation messages for the exact parameters.");
   }
   
   return valid;
}

bool ValidateTimeframes()
{
   bool valid = true;
   
   // Check for logical timeframe hierarchy used throughout the EA:
   // Signal_TF < Confirm_TF <= Primary_TF <= Trend_TF
   // Example default stack: M15 < H1 <= H4 <= D1
   // Convert timeframes to minutes for comparison
   int signal_minutes = TimeframeToMinutes(Signal_TF);
   int primary_minutes = TimeframeToMinutes(Primary_TF);
   int confirm_minutes = TimeframeToMinutes(Confirm_TF);
   
   if(signal_minutes <= 0 || primary_minutes <= 0 || confirm_minutes <= 0)
   {
      Log(LOG_ERROR, "ValidateTimeframes", "Invalid timeframe conversion");
      valid = false;
   }
   
   // Validate hierarchy
   if(signal_minutes >= confirm_minutes)
   {
      Log(LOG_ERROR, "ValidateTimeframes", 
          "Invalid timeframe hierarchy: Signal_TF (" + EnumToString(Signal_TF) + 
          ") must be smaller than Confirm_TF (" + EnumToString(Confirm_TF) + ")");
      valid = false;
   }
   
   if(confirm_minutes > primary_minutes)
   {
      Log(LOG_ERROR, "ValidateTimeframes", 
          "Invalid timeframe hierarchy: Confirm_TF (" + EnumToString(Confirm_TF) + 
          ") must not be larger than Primary_TF (" + EnumToString(Primary_TF) + ")" +
          " | Recommended fix: swap them so Confirm_TF <= Primary_TF");
      valid = false;
   }
   
   // Validate Trend_TF is reasonable (should be >= Primary_TF)
   int trend_minutes = TimeframeToMinutes(Trend_TF);
   if(trend_minutes <= 0)
   {
      Log(LOG_ERROR, "ValidateTimeframes", "Invalid Trend_TF conversion");
      valid = false;
   }
   
   if(primary_minutes > trend_minutes)
   {
      Log(LOG_ERROR, "ValidateTimeframes",
          "Invalid timeframe hierarchy: Primary_TF (" + EnumToString(Primary_TF) +
          ") must not be larger than Trend_TF (" + EnumToString(Trend_TF) + ")");
      valid = false;
   }
   
   // Log validation results
   if(valid)
   {
      Log(LOG_INFO, "ValidateTimeframes", 
          "Timeframe hierarchy validated: " + 
          EnumToString(Signal_TF) + " < " + 
          EnumToString(Confirm_TF) + " <= " +
          EnumToString(Primary_TF) + " <= " +
          EnumToString(Trend_TF));
   }
   
   return valid;
}

bool ValidateGoldTradingConditions(string symbol)
{
   if(g_Disable_All_Gates)
      return true;

   // Check if this is a GOLD symbol
   if(StringFind(symbol, "XAU") == -1 && StringFind(symbol, "GOLD") == -1)
      return true; // Not gold, use standard validation
   
   // GOLD-specific validations
   MqlTick tick;
   bool has_tick = SymbolInfoTick(symbol, tick); // refresh quotes
   double bid = (has_tick ? tick.bid : SymbolInfoDouble(symbol, SYMBOL_BID));
   double ask = (has_tick ? tick.ask : SymbolInfoDouble(symbol, SYMBOL_ASK));
   
   if(bid <= 0 || ask <= 0)
   {
      Log(LOG_WARNING, "ValidateGoldTradingConditions", 
          symbol + " - Invalid GOLD prices: Bid=" + DoubleToString(bid, 2) + 
          ", Ask=" + DoubleToString(ask, 2));
      return false;
   }
   
   if(g_Enable_Spread_Gates)
   {
      // Check GOLD spread via common spread gate with tighter factor
      if(!IsSpreadAcceptable(symbol))
      {
         // IsSpreadAcceptable logs details; add gold tag for traceability
         Log(LOG_INFO, "ValidateGoldTradingConditions", symbol + " - GOLD spread gate failed");
         return false;
      }
   }

   // Symbol spread validation handled via helper functions in SymbolManagement.mqh
   if(g_Enable_Spread_Gates)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0) point = Point();

      int spread_points = 0;
      if(has_tick && tick.bid > 0.0 && tick.ask > 0.0 && point > 0.0)
         spread_points = (int)MathRound((tick.ask - tick.bid) / point);
      if(spread_points <= 0)
      {
         long spread_raw = 0;
         if(SymbolInfoInteger(symbol, SYMBOL_SPREAD, spread_raw))
            spread_points = (int)spread_raw;
      }

      double spread_pips = PointsToPips(symbol, (double)spread_points);
      // Use symbol-specific spread config via SymbolManagement lookup functions
      double spread_limit_pips = (double)GetSymbolMaxSpreadPips(symbol);
      double net_spread_limit_pips = GetSymbolNetSpreadLimit(symbol);
      if(net_spread_limit_pips > 0.0)
         spread_limit_pips = MathMin(spread_limit_pips, net_spread_limit_pips);
      if(spread_pips > spread_limit_pips)
      {
          Log(LOG_INFO, "ValidateGoldTradingConditions", 
              symbol + " - Spread too high: " + DoubleToString(spread_pips, 1) + 
              " pips > limit " + DoubleToString(spread_limit_pips, 1) + " pips");
          return false;
      }
   }
   
   if(g_Enable_Session_Gates)
   {
      // Check if GOLD market is active (not during low liquidity periods)
      MqlDateTime dt;
      TimeGMT(dt);
      int hour = dt.hour;
      
      // Avoid GOLD trading during Asian session low liquidity (23:00-01:00 GMT)
      if(hour >= 23 || hour <= 1)
      {
         Log(LOG_DEBUG, "ValidateGoldTradingConditions", 
             symbol + " - Avoiding GOLD trading during low liquidity period (" + 
             IntegerToString(hour) + ":00 GMT)");
         return false;
      }
   }
   
   return true;
}

enum ETradeLevelsReason
{
   TRADE_LEVELS_OK = 0,
   TRADE_LEVELS_NON_POSITIVE,
   TRADE_LEVELS_NON_NUMERIC,
   TRADE_LEVELS_INVALID_LAYOUT,
   TRADE_LEVELS_SYMBOL_INDEX,
   TRADE_LEVELS_SYMBOL_CACHE,
   TRADE_LEVELS_SL_TOO_CLOSE,
   TRADE_LEVELS_TP_TOO_CLOSE,
   TRADE_LEVELS_SPREAD_TOO_CLOSE
};

struct STradeLevelContext
{
   int    symbol_index;
   double point;
   int    digits;
   double tick_size;
   bool   valid;

   STradeLevelContext() : symbol_index(-1), point(0.0), digits(0), tick_size(0.0), valid(false) {}
};

string TradeLevelsReasonLabel(int reason)
{
   switch(reason)
   {
      case TRADE_LEVELS_NON_POSITIVE:    return "NonPositive";
      case TRADE_LEVELS_NON_NUMERIC:     return "NonNumeric";
      case TRADE_LEVELS_INVALID_LAYOUT:  return "Layout";
      case TRADE_LEVELS_SYMBOL_INDEX:    return "Symbol";
      case TRADE_LEVELS_SYMBOL_CACHE:    return "Cache";
      case TRADE_LEVELS_SL_TOO_CLOSE:    return "SLTooClose";
      case TRADE_LEVELS_TP_TOO_CLOSE:    return "TPTooClose";
      case TRADE_LEVELS_SPREAD_TOO_CLOSE:return "Spread";
      default:                           return "Unknown";
   }
}

bool BuildTradeLevelContext(string symbol, int preferred_symbol_index, STradeLevelContext &ctx, string &error_reason)
{
   ctx = STradeLevelContext();
   error_reason = "";

   int index = preferred_symbol_index;
   if(index < 0 || index >= g_symbols_count || g_symbols[index].name != symbol)
      index = GetSymbolIndex(symbol);
   if(index < 0 || index >= g_symbols_count)
   {
      error_reason = "symbol index unavailable";
      return false;
   }

   if(!RefreshSymbolCache(index))
   {
      error_reason = "failed to refresh symbol cache";
      return false;
   }

   double point = g_symbols[index].cache.point;
   if(point <= 0.0)
      point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = Point();
   if(point <= 0.0)
   {
      error_reason = "invalid point size";
      return false;
   }

   int digits = g_symbols[index].cache.digits;
   if(digits <= 0)
      digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(digits < 0)
      digits = 2;

   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0)
      tick_size = point;
   if(tick_size <= 0.0)
   {
      error_reason = "invalid tick size";
      return false;
   }

   ctx.symbol_index = index;
   ctx.point = point;
   ctx.digits = digits;
   ctx.tick_size = tick_size;
   ctx.valid = true;
   return true;
}

bool ValidateTradeLevelsWithReason(string symbol, double entry, double sl, double tp, int &reason)
{
   reason = TRADE_LEVELS_OK;
   if(entry <= 0 || sl <= 0 || tp <= 0)
   {
      Log(LOG_ERROR, "ValidateTradeLevels", "Zero or negative price levels");
      reason = TRADE_LEVELS_NON_POSITIVE;
      return false;
   }
       
   if(!MathIsValidNumber(entry) || !MathIsValidNumber(sl) || !MathIsValidNumber(tp))
   {
      Log(LOG_ERROR, "ValidateTradeLevels", "Invalid number in price levels");
      reason = TRADE_LEVELS_NON_NUMERIC;
      return false;
   }

   // Enforce valid level orientation for either BUY (SL < Entry < TP) or SELL (TP < Entry < SL)
   bool buy_layout = (sl < entry && tp > entry);
   bool sell_layout = (sl > entry && tp < entry);
   if(!buy_layout && !sell_layout)
   {
      Log(LOG_WARNING, "ValidateTradeLevels",
          symbol + " - Invalid SL/TP layout relative to entry (Entry=" + DoubleToString(entry, 5) +
          ", SL=" + DoubleToString(sl, 5) + ", TP=" + DoubleToString(tp, 5) + ")");
      reason = TRADE_LEVELS_INVALID_LAYOUT;
      return false;
   }

   int index = GetSymbolIndex(symbol);
   if(index < 0)
   {
      reason = TRADE_LEVELS_SYMBOL_INDEX;
      return false;
   }
       
   if(!RefreshSymbolCache(index))
   {
      reason = TRADE_LEVELS_SYMBOL_CACHE;
      return false;
   }

   double point = g_symbols[index].cache.point;
    
   long stop_level_long, freeze_level_long;
   SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL, stop_level_long);
   SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL, freeze_level_long);
   
   int stop_level = (int)stop_level_long;
   int freeze_level = (int)freeze_level_long;
   
   double min_distance = MathMax((double)stop_level, (double)freeze_level) * point;
   if(min_distance == 0) min_distance = 10 * point;
   
   double sl_distance = MathAbs(entry - sl);
   if(sl_distance < min_distance)
   {
      double sl_pips = (GetPipSize(symbol) > 0.0 ? sl_distance / GetPipSize(symbol) : sl_distance / point);
      Log(LOG_WARNING, "ValidateTradeLevels", symbol + " - Stop loss too close: " + DoubleToString(sl_pips, 1) + " pips");
      reason = TRADE_LEVELS_SL_TOO_CLOSE;
      return false;
   }

   double tp_distance = MathAbs(tp - entry);
   if(tp_distance < min_distance)
   {
      double tp_pips = (GetPipSize(symbol) > 0.0 ? tp_distance / GetPipSize(symbol) : tp_distance / point);
      Log(LOG_WARNING, "ValidateTradeLevels", symbol + " - Take profit too close: " + DoubleToString(tp_pips, 1) + " pips");
      reason = TRADE_LEVELS_TP_TOO_CLOSE;
      return false;
   }

   long spread_value = g_symbols[index].cache.spread;
   double spread = double(spread_value) * point;
   // Spread check disabled - broker stop/freeze level checks above are sufficient
   // Previous check was too restrictive during normal market conditions

   return true;
}

bool ValidateTradeLevels(string symbol, double entry, double sl, double tp)
{
   int reason = TRADE_LEVELS_OK;
   return ValidateTradeLevelsWithReason(symbol, entry, sl, tp, reason);
}

bool NormalizeAndValidateTradeLevels(string symbol,
                                     const STradeLevelContext &ctx,
                                     double &entry,
                                     double &sl,
                                     double &tp,
                                     int &reason)
{
   reason = TRADE_LEVELS_OK;
   if(!ctx.valid)
   {
      reason = TRADE_LEVELS_SYMBOL_INDEX;
      return false;
   }

   SNormalizedPrices normalized = NormalizeTradePrices(entry, sl, tp, ctx.digits, ctx.tick_size);
   entry = normalized.entry;
   sl = normalized.stop_loss;
   tp = normalized.take_profit;
   return ValidateTradeLevelsWithReason(symbol, entry, sl, tp, reason);
}

double CalculateTradeRiskRewardRatio(double entry, double sl, double tp)
{
   double risk = MathAbs(entry - sl);
   if(risk <= 0.0)
      return 0.0;

   double reward = MathAbs(tp - entry);
   return NormalizeDouble(SafeDiv(reward, risk, 0.0), 2);
}

// CRITICAL FIX #2: True Risk-Reward accounting for real trading costs
double CalculateTrueRiskRewardRatio(
   string symbol,
   double entry_price,
   double tp_price,
   double sl_price,
   bool is_long,
   int holding_days = 1)
{
   // Get real broker costs
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double spread = ask - bid;
   
   double swap_long = SymbolInfoDouble(symbol, SYMBOL_SWAP_LONG);
   double swap_short = SymbolInfoDouble(symbol, SYMBOL_SWAP_SHORT);
   // CRITICAL FIX: SYMBOL_SWAP_LONG/SHORT are already in POINTS (symbol's point unit)
   // They represent swap cost per 1 lot per day in points, not in currency
   // Example: EURUSD swap=10 means 10 points = 0.001 EURUSD per lot per day
   // For RR pips calculation, swap is directly in "pips" (points for this symbol)
   double swap_pips = (is_long ? swap_long : swap_short) * holding_days;
   
   // Point value for this symbol
   double pip_value = SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   // Calculate TRUE entry cost (we pay spread on entry)
   double effective_entry = is_long ? (entry_price + spread/2) : (entry_price - spread/2);
   
   // Calculate TRUE exit cost (we pay FULL spread on exit, not half)
   // FIX #5: Spread handling must be symmetric - all exits pay full spread
   double effective_tp = is_long ? (tp_price - spread) : (tp_price + spread);
   double effective_sl = is_long ? (sl_price + spread) : (sl_price - spread);
   
   // Calculate distances in pips
   double profit_pips = (is_long ? (effective_tp - effective_entry) : 
                                    (effective_entry - effective_tp)) / pip_value;
   double risk_pips = (is_long ? (effective_entry - effective_sl) : 
                              (effective_sl - effective_entry)) / pip_value;
   
   // Subtract swap costs from profit (swap_pips is already in pips from above)
   profit_pips -= swap_pips;
   
   // Ensure risk is positive
   if(risk_pips <= 0.0)
      return -1.0;  // Invalid setup
   
   double true_rr = profit_pips / risk_pips;
   
   #ifdef LOGGING_DEBUG
   Log(LOG_INFO, "TrueRRCalculation",
       StringFormat("%s: Nominal RR=%.2f, Spread=%.1fpips, Swap=%.1fpips, TRUE_RR=%.2f",
                    symbol, 
                    (tp_price - entry_price) / (entry_price - sl_price),
                    spread / pip_value, swap_pips, true_rr));
   #endif
   
   return true_rr;
}

bool ValidateSmartEntry(string symbol, ENUM_TIMEFRAMES tf, int direction, 
                        double entry_price, double order_block_low, double order_block_high)
{
   if(direction != 1 && direction != -1)
      return false;
   if(entry_price <= 0.0 || order_block_high <= order_block_low)
      return false;

   // SMART: Validate entry is inside an actionable mitigation zone
   MqlRates rates[];
   if(!GetCachedRates(symbol, tf, rates, 8) || ArraySize(rates) < 4)
      return false;

   double current_price = rates[0].close;
   double atr = GetATRValue(symbol, tf);
   if(atr <= 0.0)
      atr = rates[1].high - rates[1].low;
   if(atr <= 0.0)
      atr = SymbolInfoDouble(symbol, SYMBOL_POINT) * 10.0;

   double ob_range = order_block_high - order_block_low;
   if(ob_range <= 0.0)
      return false;

   double zone_mid = (order_block_low + order_block_high) * 0.5;
   double zone_buffer = MathMin(ob_range * 0.15, atr * 0.10);
   bool inside_zone = (entry_price >= order_block_low - zone_buffer &&
                       entry_price <= order_block_high + zone_buffer);
   if(!inside_zone)
      return false;

   double distance_from_current = MathAbs(entry_price - current_price);
   if(distance_from_current > atr * 1.2)
      return false;

   bool mitigation_touch = false;
   for(int i = 1; i <= 2 && i < ArraySize(rates); i++)
   {
      if(direction == 1)
      {
         if(rates[i].low <= order_block_high + atr * 0.05 &&
            rates[i].close > order_block_low - atr * 0.05)
         {
            mitigation_touch = true;
            break;
         }
      }
      else
      {
         if(rates[i].high >= order_block_low - atr * 0.05 &&
            rates[i].close < order_block_high + atr * 0.05)
         {
            mitigation_touch = true;
            break;
         }
      }
   }
   if(!mitigation_touch)
      return false;

   if(direction == 1)  // BUY: avoid premium buy entries inside OB
   {
      if(entry_price > zone_mid + ob_range * 0.10)
         return false;
      if(entry_price > current_price + atr * 0.10)
         return false;
   }
   else  // SELL: avoid discount sell entries inside OB
   {
      if(entry_price < zone_mid - ob_range * 0.10)
         return false;
      if(entry_price < current_price - atr * 0.10)
         return false;
   }

   return true;
}

// ====================================================================
// SIGNAL INVERSION DEBUG FUNCTIONS
// ====================================================================

/**
 * Validates signal direction against expected market bias
 * @param signal Trading signal to validate
 * @param expected_direction Expected direction (1=BUY, -1=SELL, 0=NEUTRAL)
 * @return true if direction matches expected, false otherwise
 */
bool ValidateSignalDirectionAlignment(const STradingSignal &signal, int expected_direction)
{
   if(expected_direction == 0)
      return true;  // Neutral is always valid

   if(expected_direction != signal.direction)
   {
      Log(LOG_ERROR, "SignalDirectionValidation",
          StringFormat("DIRECTION MISMATCH: Expected=%d (%s), Actual=%d (%s)",
                       expected_direction,
                       (expected_direction == 1 ? "BUY" : expected_direction == -1 ? "SELL" : "NEUTRAL"),
                       signal.direction,
                       (signal.direction == 1 ? "BUY" : signal.direction == -1 ? "SELL" : "NEUTRAL")));
      return false;
   }
   return true;
}

/**
 * Validates that Entry/SL/TP are correctly positioned relative to direction
 * @param signal Trading signal to validate
 * @return true if levels are aligned with direction, false if inverted
 */
bool ValidateSignalLevelAlignment(const STradingSignal &signal)
{
   if(signal.direction == 0)
      return true;  // Neutral signals don't need level validation

   // EDGE CASE FIX: Add tolerance for floating point precision when comparing prices
   // Use a small epsilon to avoid false positives from floating point rounding
   const double PRICE_TOLERANCE = 1e-6;  // 0.000001 in decimal terms
   
   if(signal.direction == 1)  // BUY
   {
      // For BUY: SL should be BELOW entry, TP should be ABOVE
      // EDGE CASE: Use tolerance to handle floating point precision
      bool sl_ok = (signal.stop_loss < signal.entry_price - PRICE_TOLERANCE);
      bool tp_ok = (signal.take_profit > signal.entry_price + PRICE_TOLERANCE);
      
      // EDGE CASE FIX: Validate that neither SL nor TP equals entry price exactly
      if(MathAbs(signal.stop_loss - signal.entry_price) < PRICE_TOLERANCE)
         sl_ok = false;
      if(MathAbs(signal.take_profit - signal.entry_price) < PRICE_TOLERANCE)
         tp_ok = false;

      if(!sl_ok || !tp_ok)
      {
         Log(LOG_ERROR, "SignalLevelAlignment",
             StringFormat("BUY SIGNAL INVERTED LEVELS: Entry=%.5f, SL=%.5f (expected <%.5f), TP=%.5f (expected >%.5f) | SL_OK=%s TP_OK=%s",
                          signal.entry_price, signal.stop_loss, signal.entry_price,
                          signal.take_profit, signal.entry_price,
                          (sl_ok ? "Y" : "N"), (tp_ok ? "Y" : "N")));
         return false;
      }
   }
   else if(signal.direction == -1)  // SELL
   {
      // For SELL: SL should be ABOVE entry, TP should be BELOW
      // EDGE CASE: Use tolerance to handle floating point precision
      bool sl_ok = (signal.stop_loss > signal.entry_price + PRICE_TOLERANCE);
      bool tp_ok = (signal.take_profit < signal.entry_price - PRICE_TOLERANCE);
      
      // EDGE CASE FIX: Validate that neither SL nor TP equals entry price exactly
      if(MathAbs(signal.stop_loss - signal.entry_price) < PRICE_TOLERANCE)
         sl_ok = false;
      if(MathAbs(signal.take_profit - signal.entry_price) < PRICE_TOLERANCE)
         tp_ok = false;

      if(!sl_ok || !tp_ok)
      {
         Log(LOG_ERROR, "SignalLevelAlignment",
             StringFormat("SELL SIGNAL INVERTED LEVELS: Entry=%.5f, SL=%.5f (expected >%.5f), TP=%.5f (expected <%.5f) | SL_OK=%s TP_OK=%s",
                          signal.entry_price, signal.stop_loss, signal.entry_price,
                          signal.take_profit, signal.entry_price,
                          (sl_ok ? "Y" : "N"), (tp_ok ? "Y" : "N")));
         return false;
      }
   }

   return true;
}

/**
 * Validates that market structure direction matches signal direction
 * @param symbol Symbol to check
 * @param signal_direction Direction from signal
 * @param tf Timeframe where direction should be detected
 * @return true if structure matches direction, false if presumably inverted
 */
bool ValidateMarketStructureDirectionAlignment(string symbol, int signal_direction, ENUM_TIMEFRAMES tf)
{
   if(signal_direction == 0)
      return true;  // Neutral is always valid

   int structure = DetectMarketStructure(symbol, tf);
   int structure_direction = StructureToDirection(structure);

   if(structure_direction == 0)
      return true;  // Ranging market is neutral, don't fail on direction mismatch

   if(structure_direction != signal_direction)
   {
      string struct_str = (structure == MARKET_BULLISH ? "BULLISH" :
                           structure == MARKET_BEARISH ? "BEARISH" : "NEUTRAL");
      string signal_str = (signal_direction == 1 ? "BUY" :
                           signal_direction == -1 ? "SELL" : "NEUTRAL");

      Log(LOG_WARNING, "StructureDirectionMismatch",
          StringFormat("%s %s: Market Structure=%s (dir=%d) vs Signal=%s (dir=%d) - POSSIBLE INVERSION",
                       symbol, EnumToString(tf), struct_str, structure_direction, signal_str, signal_direction));
      return false;
   }

   return true;
}

/**
 * Comprehensive signal inversion diagnostic
 * Logs detailed debug information about signal generation
 * @param symbol Symbol being analyzed
 * @param signal Generated trading signal
 * @param htf_bias HTF bias score for direction
 * @param market_structure Market structure at signal timeframe
 */
void LogSignalInversionDiagnostic(string symbol, const STradingSignal &signal, 
                                  int htf_bias, int market_structure)
{
   if(!g_Enable_Institutional_Debug && !g_debug_signals_enabled)
      return;

   string struct_str = (market_structure == MARKET_BULLISH ? "BULLISH" :
                        market_structure == MARKET_BEARISH ? "BEARISH" : "NEUTRAL");
   string bias_str = (htf_bias == 1 ? "BULLISH" : htf_bias == -1 ? "BEARISH" : "NEUTRAL");
   string dir_str = (signal.direction == 1 ? "BUY" : signal.direction == -1 ? "SELL" : "NEUTRAL");

   string status = "OK";
   if(market_structure != 0 && StructureToDirection(market_structure) != signal.direction)
      status = "MISMATCH";
   if(htf_bias != signal.direction && htf_bias != 0 && signal.direction != 0)
      status = "BIAS_MISMATCH";

   string levels_status = "OK";
   if(!ValidateSignalLevelAlignment(signal))
      levels_status = "INVERTED";

   Log(LOG_DETAILED, "SignalInversionDiag",
       StringFormat("%s | Dir=%s (HTF=%s Struct=%s) | Entry=%.5f SL=%.5f TP=%.5f | LevelStatus=%s DirectionStatus=%s",
                    symbol, dir_str, bias_str, struct_str,
                    signal.entry_price, signal.stop_loss, signal.take_profit,
                    levels_status, status));
}

/**
 * Run complete signal inversion validation suite
 * @param signal Signal to validate
 * @param symbol Symbol being traded
 * @param expected_direction Expected direction from HTF bias
 * @return true if all validations pass, false if any indicate inversion
 */
bool ValidateSignalForInversion(const STradingSignal &signal, string symbol, int expected_direction)
{
   bool overall_valid = true;

   // Test 1: Direction alignment
   if(!ValidateSignalDirectionAlignment(signal, expected_direction))
   {
      Log(LOG_ERROR, "SignalInversionValidation", symbol + " - FAILED: Direction alignment");
      overall_valid = false;
   }

   // Test 2: Level alignment
   if(!ValidateSignalLevelAlignment(signal))
   {
      Log(LOG_ERROR, "SignalInversionValidation", symbol + " - FAILED: Entry/SL/TP alignment");
      overall_valid = false;
   }

   // Test 3: Market structure alignment
   if(!ValidateMarketStructureDirectionAlignment(symbol, signal.direction, Signal_TF))
   {
      Log(LOG_WARNING, "SignalInversionValidation", symbol + " - WARNING: Structure alignment");
      // Don't fail overall on this, just warn
   }

   if(overall_valid)
   {
      Log(LOG_DEBUG, "SignalInversionValidation", symbol + " - PASSED: All inversion checks");
   }

   return overall_valid;
}

#endif // VALIDATION_MQH
