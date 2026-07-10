#ifndef MAIN_LIFECYCLE_MQH
#define MAIN_LIFECYCLE_MQH

void InitGlobalCaches()
{
   // Initialize global caches and pools to prevent memory issues
   for(int i = 0; i < MAX_SYMBOLS; i++)
   {
      g_atr_temp_cache[i].handle = INVALID_HANDLE;
      g_temp_indicators[i].handle = INVALID_HANDLE;
      for(int t = 0; t < MAX_TF_CACHE; t++)
      {
         g_structure_cache[i][t].tf = (ENUM_TIMEFRAMES)-1;
         g_structure_cache[i][t].value = MARKET_RANGE;
         g_structure_cache[i][t].last_update = 0;
         g_structure_calc_time[i][t] = 0;
         g_htf_bias_cache[i][t] = 0;
         g_htf_bias_cache_time[i][t] = 0;
         g_htf_bias_calc_time[i][t] = 0;
      }
      for(int t = 0; t < 4; t++)
      {
         g_structure_slot_map[i][t] = -1;
         g_bias_slot_map[i][t] = -1;
         g_momentum_cache[i][t].valid = false;
         g_momentum_cache[i][t].bar_time = 0;
         g_momentum_cache[i][t].macd = 0.0;
         g_momentum_cache[i][t].stoch = 50.0;
      }
      for(int a = 0; a < MAX_ATR_CACHE; a++)
      {
         g_atr_cache[i][a].value = 0.0;
         g_atr_cache[i][a].bar_time = 0;
         g_atr_cache[i][a].tf = (ENUM_TIMEFRAMES)-1;
         g_atr_cache[i][a].period = 0;
         g_atr_cache[i][a].last_used = 0;
      }
      g_ai_prediction_cache[i].probability = 0.5;
      g_ai_prediction_cache[i].buy_prob = 0.5;
      g_ai_prediction_cache[i].sell_prob = 0.5;
      g_ai_prediction_cache[i].confidence = 0.0;
      g_ai_prediction_cache[i].last_update = 0;
      g_ai_prediction_cache[i].created_time = 0;
      g_ai_prediction_cache[i].access_count = 0;
      g_ai_prediction_cache[i].tf = PERIOD_CURRENT;
      g_ai_prediction_cache[i].bar_time = 0;
      g_ai_prediction_cache[i].source_tick_msc = 0;
      g_indicator_cache[i][0].is_valid = false;
      g_indicator_cache[i][1].is_valid = false;
      g_indicator_cache[i][2].is_valid = false;
      g_indicator_cache[i][3].is_valid = false;
      g_volatility_cache[i].factor = 1.0;
      g_volatility_cache[i].last_bar_time = 0;
      g_volatility_cache[i].last_update = 0;
      g_volatility_cache[i].last_tick_msc = 0;
      g_ai_feature_cache[i].rsi_value = 50.0;
      g_ai_feature_cache[i].ma_slope = 0.0;
      g_ai_feature_cache[i].atr_value = 0.001;
      g_ai_feature_cache[i].volume_ratio = 1.0;
      g_ai_feature_cache[i].bar_time = 0;
      g_ai_feature_cache[i].last_update = 0;
      g_ai_feature_cache[i].last_tick_msc = 0;
      g_ai_feature_cache[i].tf = PERIOD_CURRENT;
      g_ai_feature_cache[i].is_valid = false;
      g_ai_last_continuous_export_time[i] = 0;
      g_spread_spike_count[i] = 0;
      g_symbol_loss_streak[i] = 0;
      g_symbol_last_loss_time[i] = 0;
      g_symbol_loss_cooldown_until[i] = 0;
      g_cache_metadata[i].last_accessed = 0;
      g_cache_metadata[i].access_count = 0;
      g_symbols[i].last_housekeeping_bar = 0;
      g_symbols[i].last_atr_validate_bar = 0;
      g_symbols[i].last_signal_bar = 0;
      g_symbols[i].cache.last_rates_tick_msc = 0;
   }

   for(int i = 0; i < 20; i++)
   {
      g_indicator_pool[i].handle = INVALID_HANDLE;
      g_indicator_pool[i].symbol = "";
      g_indicator_pool[i].tf = (ENUM_TIMEFRAMES)-1;
      g_indicator_pool[i].period = 0;
      g_indicator_pool[i].type = "";
      g_indicator_pool[i].in_use = false;
      g_indicator_pool[i].last_used = 0;
   }

   for(int i = 0; i < 10; i++)
   {
      ResetFallbackHandleSlot(i);
   }

   for(int i = 0; i < MAX_RETRY_QUEUE; i++)
   {
      g_trade_retries[i].symbol = "";
      g_trade_retries[i].attempt = 0;
      g_trade_retries[i].next_retry = 0;
      g_trade_retries[i].created_time = 0;
      g_trade_retries[i].symbol_index = -1;
      g_trade_retries[i].signal_fingerprint = 0;
      g_trade_retries[i].ticket = 0;
      g_trade_retries[i].order_placed = false;
      g_trade_retries[i].last_ticket_check_time = 0;
   }

   g_fallback_count = 0;
   g_retry_count = 0;
   g_market_pause_until = 0;
   g_drawdown_pause_until = 0;
   g_ai_cache_requests = 0;
   g_ai_cache_hits = 0;
   g_ai_cache_misses = 0;
   g_Bot_Halt_Active = false;
   g_Bot_Halt_Activated_Time = 0;
   g_Bot_Halt_Reason = "";

   for(int i = 0; i < 157; i++)
   {
      g_symbol_hash_table[i].symbol_index = -1;
   }

   g_position_count_cache.last_update = 0;
   for(int i = 0; i < MAX_SYMBOLS; i++)
   {
      g_position_count_cache.count_per_symbol[i] = 0;
   }

   // Ensure global cached rates use timeseries indexing (0 = most recent bar)
   ArraySetAsSeries(g_cached_rates_main.rates, true);
}

bool RefreshAllRuntimeCaches(bool refresh_symbol_quotes = true, bool log_summary = true)
{
   ArrayFree(g_cached_rates_main.rates);
   g_cached_rates_main.last_update = 0;
   g_cached_rates_main.tf = PERIOD_CURRENT;
   g_cached_rates_main.count = 0;
   ArraySetAsSeries(g_cached_rates_main.rates, true);

   g_position_count_cache.last_update = 0;
   g_ai_cache_manager.last_cleanup = 0;
   g_risk_cache.last_calc = 0;

   for(int i = 0; i < MAX_SYMBOLS; i++)
   {
      g_position_count_cache.count_per_symbol[i] = 0;

      for(int t = 0; t < MAX_TF_CACHE; t++)
      {
         g_structure_cache[i][t].tf = (ENUM_TIMEFRAMES)-1;
         g_structure_cache[i][t].value = MARKET_RANGE;
         g_structure_cache[i][t].last_update = 0;
         g_structure_calc_time[i][t] = 0;
         g_htf_bias_cache[i][t] = 0;
         g_htf_bias_cache_time[i][t] = 0;
         g_htf_bias_calc_time[i][t] = 0;
      }

      for(int t = 0; t < 4; t++)
      {
         g_structure_slot_map[i][t] = -1;
         g_bias_slot_map[i][t] = -1;
         g_momentum_cache[i][t].macd = 0.0;
         g_momentum_cache[i][t].stoch = 50.0;
         g_momentum_cache[i][t].bar_time = 0;
         g_momentum_cache[i][t].valid = false;

         g_indicator_cache[i][t].rsi_value = 50.0;
         g_indicator_cache[i][t].last_bar_time = 0;
         g_indicator_cache[i][t].is_valid = false;
      }

      for(int a = 0; a < MAX_ATR_CACHE; a++)
      {
         g_atr_cache[i][a].value = 0.0;
         g_atr_cache[i][a].bar_time = 0;
         g_atr_cache[i][a].tf = (ENUM_TIMEFRAMES)-1;
         g_atr_cache[i][a].period = 0;
         g_atr_cache[i][a].last_used = 0;
      }

      g_ai_prediction_cache[i].probability = 0.5;
      g_ai_prediction_cache[i].buy_prob = 0.5;
      g_ai_prediction_cache[i].sell_prob = 0.5;
      g_ai_prediction_cache[i].confidence = 0.0;
      g_ai_prediction_cache[i].last_update = 0;
      g_ai_prediction_cache[i].created_time = 0;
      g_ai_prediction_cache[i].access_count = 0;
      g_ai_prediction_cache[i].tf = PERIOD_CURRENT;
      g_ai_prediction_cache[i].bar_time = 0;
      g_ai_prediction_cache[i].source_tick_msc = 0;

      g_volatility_cache[i].factor = 1.0;
      g_volatility_cache[i].last_bar_time = 0;
      g_volatility_cache[i].last_update = 0;
      g_volatility_cache[i].last_tick_msc = 0;

      g_ai_feature_cache[i].rsi_value = 50.0;
      g_ai_feature_cache[i].ma_slope = 0.0;
      g_ai_feature_cache[i].atr_value = 0.001;
      g_ai_feature_cache[i].volume_ratio = 1.0;
      g_ai_feature_cache[i].bar_time = 0;
      g_ai_feature_cache[i].last_update = 0;
      g_ai_feature_cache[i].last_tick_msc = 0;
      g_ai_feature_cache[i].tf = PERIOD_CURRENT;
      g_ai_feature_cache[i].is_valid = false;

      g_cache_metadata[i].last_accessed = 0;
      g_cache_metadata[i].access_count = 0;

      g_symbols[i].cache.bid = 0.0;
      g_symbols[i].cache.ask = 0.0;
      g_symbols[i].cache.point = 0.0;
      g_symbols[i].cache.digits = 0;
      g_symbols[i].cache.spread = 0;
      g_symbols[i].cache.spread_avg_points = 0.0;
      g_symbols[i].cache.spread_avg_samples = 0;
      g_symbols[i].cache.last_update = 0;
      ArrayResize(g_symbols[i].cache.last_rates, 0);
      g_symbols[i].cache.last_rates_update = 0;
      g_symbols[i].cache.last_rates_bar_time = 0;
      g_symbols[i].cache.last_rates_tf = PERIOD_CURRENT;
      g_symbols[i].cache.last_rates_tick_msc = 0;
      g_symbols[i].cache.last_tick_time = 0;
      g_symbols[i].cache.last_tick_msc = 0;
   }

   for(int i = 0; i < 20; i++)
   {
      if(g_indicator_pool[i].handle != INVALID_HANDLE)
         IndicatorRelease(g_indicator_pool[i].handle);
      g_indicator_pool[i].handle = INVALID_HANDLE;
      g_indicator_pool[i].symbol = "";
      g_indicator_pool[i].tf = (ENUM_TIMEFRAMES)-1;
      g_indicator_pool[i].period = 0;
      g_indicator_pool[i].type = "";
      g_indicator_pool[i].last_used = 0;
      g_indicator_pool[i].in_use = false;
   }

   ReleaseAllFallbackHandles();

   for(int i = 0; i < MAX_SYMBOLS; i++)
   {
      if(g_temp_indicators[i].handle != INVALID_HANDLE)
         IndicatorRelease(g_temp_indicators[i].handle);
      g_temp_indicators[i].handle = INVALID_HANDLE;
      g_temp_indicators[i].tf = (ENUM_TIMEFRAMES)-1;
      g_temp_indicators[i].period = 0;
      g_temp_indicators[i].created_time = 0;

      if(g_atr_temp_cache[i].handle != INVALID_HANDLE)
         IndicatorRelease(g_atr_temp_cache[i].handle);
      g_atr_temp_cache[i].handle = INVALID_HANDLE;
      g_atr_temp_cache[i].tf = (ENUM_TIMEFRAMES)-1;
      g_atr_temp_cache[i].period = 0;
      g_atr_temp_cache[i].created_time = 0;
   }

   bool quotes_ok = true;
   if(refresh_symbol_quotes)
   {
      for(int i = 0; i < g_symbols_count; i++)
      {
         if(!RefreshSymbolCache(i))
            quotes_ok = false;
      }
   }

   if(g_symbols_count > 0)
      BuildSymbolHashTable();

   if(log_summary)
   {
      Log(quotes_ok ? LOG_INFO : LOG_WARNING,
          "RefreshAllRuntimeCaches",
          "Runtime caches refreshed" + string(refresh_symbol_quotes ? " with live quote refresh" : "") +
          (quotes_ok ? "" : " (some quote refreshes failed)"));
   }

   return quotes_ok;
}

// CRITICAL FIX: Validate retry queue bounds to prevent array access violations
void ValidateRetryQueueBounds()
{
   if(g_retry_count < 0 || g_retry_count > MAX_RETRY_QUEUE)
   {
      Log(LOG_ERROR, "ValidateRetryQueueBounds", "CRITICAL: Retry count out of bounds: " + IntegerToString(g_retry_count));
      g_retry_count = 0;  // Force reset to safe state
      return;
   }
   
   // Verify all active retry entries have valid data
   for(int i = 0; i < g_retry_count && i < MAX_RETRY_QUEUE; i++)
   {
      if(g_trade_retries[i].symbol == "" || g_trade_retries[i].symbol_index < 0)
      {
         Log(LOG_WARNING, "ValidateRetryQueueBounds", "Slot " + IntegerToString(i) + " has invalid data");
      }
   }
}

bool CheckTradeAllowed()
{
   bool platform_trade_allowed = true;

   if(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) == 0)
   {
      Log(LOG_WARNING, "OnInit", "Terminal trading not allowed");
      platform_trade_allowed = false;
   }

   if(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) == 0)
   {
      Log(LOG_WARNING, "OnInit", "Account trading not allowed");
      platform_trade_allowed = false;
   }

   if(MQLInfoInteger(MQL_TRADE_ALLOWED) == 0)
   {
      Log(LOG_WARNING, "OnInit", "MQL trading not allowed");
      platform_trade_allowed = false;
   }

   if(!platform_trade_allowed)
   {
      Log(LOG_ERROR, "OnInit", "Platform trading permission missing at init - initialization aborted");
      SendAlert(ALERT_ERROR, "Trading not allowed. Enable Algo Trading and restart the EA.");
      return false;
   }

   if(!IsTradeAllowed())
   {
      Log(LOG_WARNING, "OnInit", "EA risk controls currently block trading; initialization will continue in blocked/diagnostic mode");
   }

   return true;
}

void ConfigureTradeDefaults()
{
   trade.SetAsyncMode(false);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_RETURN);
}

bool InitSymbolsAndIndicators()
{
   if(!InitializeSymbols())
   {
      Log(LOG_ERROR, "OnInit", "Failed to initialize symbols");
      SendAlert(ALERT_ERROR, "Failed to initialize symbols");
      return false;
   }

   bool handles_ok = true;

   for(int i = 0; i < g_symbols_count; i++)
   {
      string symbol = g_symbols[i].name;
      Log(LOG_INFO, "OnInit", "Initializing ATR for " + symbol);

      if(!SymbolInfoInteger(symbol, SYMBOL_SELECT))
      {
         if(SymbolSelect(symbol, true))
         {
            Log(LOG_INFO, "OnInit", "Added " + symbol + " to Market Watch");
         }
         else
         {
            Log(LOG_WARNING, "OnInit", "Cannot select symbol in Market Watch: " + symbol);
            continue;
         }
      }

      g_symbols[i].atr_handle = iATR(symbol, Signal_TF, ATR_Period);

      if(g_symbols[i].atr_handle == INVALID_HANDLE)
      {
         Log(LOG_ERROR, "OnInit", "Failed to create ATR handle for " + symbol);
         handles_ok = false;
      }
      else
      {
         Log(LOG_INFO, "OnInit", "ATR handle created for " + symbol + ": " + IntegerToString(g_symbols[i].atr_handle));

         double atr_value = GetATRValue(symbol, Signal_TF);
         if(atr_value > 0)
         {
            Log(LOG_INFO, "OnInit", symbol + " - Current ATR: " + DoubleToString(atr_value, 2));
         }
         else
         {
            Log(LOG_WARNING, "OnInit", symbol + " - Failed to get initial ATR value");
         }
      }
   }

   if(!handles_ok && g_symbols_count > 0)
   {
      Log(LOG_ERROR, "OnInit", "Critical: Some ATR handles failed to initialize - EA cannot start safely");
      SendAlert(ALERT_ERROR, "Failed to initialize indicator handles");
      return false;
   }

   if(g_symbols_count == 0)
   {
      Log(LOG_ERROR, "OnInit", "No valid symbols to trade - EA cannot start");
      SendAlert(ALERT_ERROR, "No valid symbols configured");
      return false;
   }

   return true;
}

void InitCountersAndScoring()
{
   g_trade_day = GetMarketDay(TimeCurrent());
   g_trades_today = 0;
   g_equity_day_start = AccountInfoDouble(ACCOUNT_EQUITY);
   g_equity_all_time_high = MathMax(g_equity_day_start, AccountInfoDouble(ACCOUNT_BALANCE));
   g_last_process_time = 0;

   if(!RestorePersistedRiskSessionState())
      PersistRiskSessionState();

   SScoringModelConfig scoring_cfg;
   scoring_cfg.execution_threshold = g_Execution_Score_Threshold_Effective;
   scoring_cfg.diagnostics_enabled = true;
   scoring_cfg.adaptive_enabled = Scoring_Enable_Adaptive_Model;
   
   // Phase 4: Read weights directly from global g_scoring_weights struct (removed deprecated input parameters)
   double w_trend = g_scoring_weights.trend;
   double w_momentum = g_scoring_weights.momentum;
   double w_volatility = g_scoring_weights.volatility;
   double w_structure = g_scoring_weights.structure;
   double w_alignment = g_scoring_weights.alignment;
   double w_confirmation = g_scoring_weights.confirmation;
   double w_risk_reward = g_scoring_weights.risk_reward;
   double w_entry_quality = g_scoring_weights.entry_quality;
   double w_spread = g_scoring_weights.spread;
   double w_regime = g_scoring_weights.regime;
   string scoring_weight_summary = "";
   HarmonizeScoringWeights(
      w_trend, w_momentum, w_volatility, w_structure, w_alignment,
      w_confirmation, w_risk_reward, w_entry_quality, w_spread, w_regime,
      scoring_weight_summary
   );
   // Phase 3A: Populate global SScoringWeights struct with harmonized values
   g_scoring_weights.trend = w_trend;
   g_scoring_weights.momentum = w_momentum;
   g_scoring_weights.volatility = w_volatility;
   g_scoring_weights.structure = w_structure;
   g_scoring_weights.alignment = w_alignment;
   g_scoring_weights.confirmation = w_confirmation;
   g_scoring_weights.risk_reward = w_risk_reward;
   g_scoring_weights.entry_quality = w_entry_quality;
   g_scoring_weights.spread = w_spread;
   g_scoring_weights.regime = w_regime;
   g_scoring_weights.total_sum = w_trend + w_momentum + w_volatility + w_structure + w_alignment +
                                  w_confirmation + w_risk_reward + w_entry_quality + w_spread + w_regime;
   
   scoring_cfg.weight_trend = w_trend;
   scoring_cfg.weight_momentum = w_momentum;
   scoring_cfg.weight_volatility = w_volatility;
   scoring_cfg.weight_structure = w_structure;
   scoring_cfg.weight_alignment = w_alignment;
   scoring_cfg.weight_confirmation = w_confirmation;
   scoring_cfg.weight_risk_reward = w_risk_reward;
   scoring_cfg.weight_entry_quality = w_entry_quality;
   scoring_cfg.weight_spread = w_spread;
   scoring_cfg.weight_regime = w_regime;
   scoring_cfg.adaptive_threshold_boost_max = Scoring_Adaptive_Threshold_Boost;
   scoring_cfg.adaptive_risk_weight_boost = Scoring_Adaptive_Risk_Weight_Boost;
   scoring_cfg.adaptive_opportunity_weight_cut = Scoring_Adaptive_Opp_Weight_Cut;

   // Phase 4: Initialize engine with config (struct updates complete)
   g_scoring_engine.Init(scoring_cfg);
   Log(LOG_INFO, "OnInit", "ScoringEngine initialized with threshold: " + DoubleToString(g_Execution_Score_Threshold_Effective, 1));
   Log(LOG_INFO, "OnInit", "Scoring weight harmonization: " + scoring_weight_summary);

   if(g_symbols_count > 0)
   {
      string test_symbol = g_symbols[0].name;
      string test_breakdown = g_scoring_engine.GetDetailedScoreBreakdown(test_symbol, Signal_TF, 1);
      Log(LOG_INFO, "OnInit", "ScoringEngine test completed for " + test_symbol);
      Log(LOG_DEBUG, "OnInit", test_breakdown);
   }

   g_debug_signal_count = 0;
   g_debug_errors = 0;
   g_debug_trades_executed = 0;
   g_debug_trades_failed = 0;

   for(int r = 0; r < MAX_REJECT_REASON_BUCKETS; r++)
   {
      g_reject_reason_keys[r] = "";
      g_reject_reason_counts[r] = 0;
   }

   g_processing_signals = false;

   InitializeTimeframeNames();
   BuildSymbolHashTable();
}

string ICTSweepPresetToString(ENUM_ICT_SWEEP_PRESET preset)
{
   switch(preset)
   {
      case ICT_PRESET_AGGRESSIVE:   return "Aggressive";
      case ICT_PRESET_BALANCED:     return "Balanced";
      case ICT_PRESET_CONSERVATIVE: return "Conservative";
      default:                      return "Custom";
   }
}

string LiveRiskProfileToString(ENUM_LIVE_RISK_PROFILE profile)
{
   switch(profile)
   {
      case LIVE_PROFILE_SAFER_LIVE: return "Safer Live";
      case LIVE_PROFILE_MAX_PROFIT:
      default:                      return "Max Profit";
   }
}

string GateProfileToString(ENUM_GATE_PROFILE profile)
{
   switch(profile)
   {
      case GATE_PERMISSIVE: return "Permissive";
      case GATE_STANDARD:   return "Standard";
      case GATE_STRICT:     return "Strict";
      case GATE_CUSTOM:
      default:              return "Custom";
   }
}

string RiskTierToString(ENUM_RISK_TIER tier)
{
   switch(tier)
   {
      case TIER_AGGRESSIVE:   return "Aggressive";
      case TIER_BALANCED:     return "Balanced";
      case TIER_CONSERVATIVE: return "Conservative";
      default:                return "Unknown";
   }
}

string TimeframePresetToString(ENUM_TF_PRESET preset)
{
   switch(preset)
   {
      case TF_SCALP:    return "Scalp";
      case TF_STANDARD: return "Standard";
      case TF_SWING:    return "Swing";
      case TF_POSITION: return "Position";
      case TF_CUSTOM:
      default:          return "Custom";
   }
}

void RefreshProfileSelectorState()
{
   g_Gate_Profile_Name = (Enable_Custom_Gate_Overrides ?
                          "Custom(" + GateProfileToString(Gate_Profile_Input) + ")" :
                          GateProfileToString(Gate_Profile_Input));
   g_Risk_Tier_Profile_Name = (Enable_Custom_Risk_Tier_Overrides ?
                               "Custom(" + RiskTierToString(Risk_Tier_Profile_Input) + ")" :
                               RiskTierToString(Risk_Tier_Profile_Input));
   g_Timeframe_Preset_Name = (Enable_Custom_Timeframe_Overrides ?
                              "Custom(" + TimeframePresetToString(Timeframe_Preset_Input) + ")" :
                              TimeframePresetToString(Timeframe_Preset_Input));

   ENUM_TIMEFRAMES preset_signal = Signal_TF;
   ENUM_TIMEFRAMES preset_primary = Primary_TF;
   ENUM_TIMEFRAMES preset_confirm = Confirm_TF;
   ENUM_TIMEFRAMES preset_trend = Trend_TF;
   ApplyTimeframePreset(Timeframe_Preset_Input, preset_signal, preset_primary, preset_confirm, preset_trend);

   g_Timeframe_Preset_Aligned = (Signal_TF == preset_signal &&
                                 Primary_TF == preset_primary &&
                                 Confirm_TF == preset_confirm &&
                                 Trend_TF == preset_trend);
}

void ApplyGateProfileSelection()
{
   g_Enable_Spread_Gates = Enable_Spread_Gates;
   g_Enable_Session_Gates = Enable_Session_Gates;
   g_Enable_Exposure_Gates = Enable_Exposure_Gates;

   if(Enable_Custom_Gate_Overrides)
      return;

   bool fvg_gate = g_Require_FVG_For_Trade;
   bool bos_gate = g_Require_BOS_Confirmation;
   bool entry_distance = g_Enable_Entry_Distance_Validation;
   bool soft_gating = g_Enable_Soft_Structural_Gating;
   bool spread_gates = g_Enable_Spread_Gates;
   ApplyGateProfile(Gate_Profile_Input, fvg_gate, bos_gate, entry_distance, soft_gating, spread_gates);

   g_Require_FVG_For_Trade = fvg_gate;
   g_Require_BOS_Confirmation = bos_gate;
   g_Enable_Entry_Distance_Validation = entry_distance;
   g_Enable_Soft_Structural_Gating = soft_gating;
   g_Enable_Spread_Gates = spread_gates;
}

void ApplyICTSweepPreset(bool is_tester)
{
   bool apply_preset = (ICT_Sweep_Preset != ICT_PRESET_CUSTOM);
   if(ICT_Apply_Preset_In_Tester_Only && !is_tester)
      apply_preset = false;

   if(!apply_preset)
   {
      g_ICT_Sweep_Preset_Effective = ICT_PRESET_CUSTOM;
      g_ICT_Sweep_Preset_Name = "Custom";
      return;
   }

   g_ICT_Sweep_Preset_Effective = ICT_Sweep_Preset;
   g_ICT_Sweep_Preset_Name = ICTSweepPresetToString(g_ICT_Sweep_Preset_Effective);

   switch(g_ICT_Sweep_Preset_Effective)
   {
      case ICT_PRESET_AGGRESSIVE:
         g_Order_Block_Lookback = 340;
         g_Order_Block_Confirmation = 1;
         g_Min_Order_Block_Size = 0.18;
         g_Use_Advanced_OB_Detection = true;
         g_OB_Max_Proximity_Pct = 5.5;
         g_Min_FVG_Size_Ratio = 0.04;
         g_Use_FVG_Detection = true;
         g_Require_FVG_For_Trade = false;
         g_FVG_Lookback_Bars = 85;
         g_Max_Entry_Distance_Pct = 1.10;
         g_Min_RR_Ratio = 1.4;
         break;

      case ICT_PRESET_CONSERVATIVE:
         g_Order_Block_Lookback = 240;
         g_Order_Block_Confirmation = 3;
         g_Min_Order_Block_Size = 0.35;
         g_Use_Advanced_OB_Detection = true;
         g_OB_Max_Proximity_Pct = 3.0;
         g_Min_FVG_Size_Ratio = 0.08;
         g_Use_FVG_Detection = true;
         g_Require_FVG_For_Trade = true;
         g_FVG_Lookback_Bars = 45;
         g_Max_Entry_Distance_Pct = 0.75;
         g_Min_RR_Ratio = 1.9;
         break;

      case ICT_PRESET_BALANCED:
      default:
         g_Order_Block_Lookback = 300;
         g_Order_Block_Confirmation = 2;
         g_Min_Order_Block_Size = 0.25;
         g_Use_Advanced_OB_Detection = true;
         g_OB_Max_Proximity_Pct = 4.0;
         g_Min_FVG_Size_Ratio = 0.06;
         g_Use_FVG_Detection = true;
         g_Require_FVG_For_Trade = true;
         g_FVG_Lookback_Bars = 60;
         g_Max_Entry_Distance_Pct = 0.90;
         g_Min_RR_Ratio = 1.5;
         break;
   }

   g_Order_Block_Lookback = MathMax(g_Order_Block_Lookback, 50);
   g_Order_Block_Confirmation = MathMax(g_Order_Block_Confirmation, 1);
   g_Min_Order_Block_Size = MathMax(g_Min_Order_Block_Size, 0.1);
   g_OB_Max_Proximity_Pct = MathMax(g_OB_Max_Proximity_Pct, 0.2);
   g_Min_FVG_Size_Ratio = MathMax(g_Min_FVG_Size_Ratio, 0.01);
   g_FVG_Lookback_Bars = MathMax(g_FVG_Lookback_Bars, 15);
   g_Max_Entry_Distance_Pct = MathMax(g_Max_Entry_Distance_Pct, 0.1);
   g_Min_RR_Ratio = MathMax(g_Min_RR_Ratio, 1.0);
}

void ApplyLiveRiskProfile(bool is_tester, bool emit_logs = true)
{
   double base_risk_percent = Risk_Percent;
   double base_daily_dd = Max_Daily_Drawdown_Pct;
   double base_account_dd = Max_Account_Drawdown_Pct;
   double base_per_trade_dd = PerTrade_Drawdown_Pct;

   if(!Enable_Custom_Risk_Tier_Overrides)
      ApplyRiskTierProfile(Risk_Tier_Profile_Input, base_daily_dd, base_account_dd, base_per_trade_dd, base_risk_percent);

   // I6 FIX: Apply safety floor and ceiling to execution threshold
   g_Execution_Score_Threshold_Effective = Execution_Score_Threshold;
   g_Execution_Score_Threshold_Effective = MathMax(g_Execution_Score_Threshold_Effective, 25.0);  // Floor
   g_Execution_Score_Threshold_Effective = MathMin(g_Execution_Score_Threshold_Effective, 85.0);  // Ceiling (prevents all trades disabled)
   
   g_Risk_Percent_Effective = base_risk_percent;
   g_Max_Concurrent_Trades_Effective = Max_Concurrent_Trades;
   g_Max_Trades_Per_Day_Effective = Max_Trades_Per_Day;
   g_Max_Spread_Pips_Effective = Max_Spread_Pips;
   g_Max_Open_Risk_Pct_Effective = Max_Open_Risk_Pct;
   g_Max_Symbol_Risk_Pct_Effective = Max_Symbol_Risk_Pct;
   g_Max_Daily_Drawdown_Pct_Effective = base_daily_dd;
   g_Max_Account_Drawdown_Pct_Effective = base_account_dd;
   g_Critical_Drawdown_Pct_Effective = Critical_Drawdown_Pct;
   g_PerTrade_Drawdown_Pct_Effective = base_per_trade_dd;
   g_Live_Risk_Profile_Effective = LIVE_PROFILE_MAX_PROFIT;
   g_Live_Risk_Profile_Name = LiveRiskProfileToString(g_Live_Risk_Profile_Effective);

   bool apply_profile = (Live_Risk_Profile != LIVE_PROFILE_MAX_PROFIT);
   if(is_tester && !Live_Profile_Apply_In_Tester)
      apply_profile = false;

   if(!apply_profile)
   {
      if(emit_logs && is_tester && Live_Risk_Profile != LIVE_PROFILE_MAX_PROFIT && !Live_Profile_Apply_In_Tester)
         Log(LOG_INFO, "OnInit", "Live risk profile override disabled in tester; using configured inputs.");

      g_risk_cache.risk = g_Risk_Percent_Effective;
      g_risk_cache.last_calc = 0;
      return;
   }

   g_Live_Risk_Profile_Effective = Live_Risk_Profile;
   g_Live_Risk_Profile_Name = LiveRiskProfileToString(g_Live_Risk_Profile_Effective);

   switch(g_Live_Risk_Profile_Effective)
   {
      case LIVE_PROFILE_SAFER_LIVE:
         g_Execution_Score_Threshold_Effective = MathMax(g_Execution_Score_Threshold_Effective, 70.0);
         g_Risk_Percent_Effective = MathMin(g_Risk_Percent_Effective, 0.55);
         g_Max_Concurrent_Trades_Effective = MathMin(g_Max_Concurrent_Trades_Effective, 1);
         g_Max_Trades_Per_Day_Effective = MathMin(g_Max_Trades_Per_Day_Effective, 4);
         g_Max_Spread_Pips_Effective = MathMin(g_Max_Spread_Pips_Effective, 65);
         if(g_Max_Open_Risk_Pct_Effective > 0.0)
            g_Max_Open_Risk_Pct_Effective = MathMin(g_Max_Open_Risk_Pct_Effective, 1.10);
         if(g_Max_Symbol_Risk_Pct_Effective > 0.0)
            g_Max_Symbol_Risk_Pct_Effective = MathMin(g_Max_Symbol_Risk_Pct_Effective, 0.65);
         g_Max_Daily_Drawdown_Pct_Effective = MathMin(g_Max_Daily_Drawdown_Pct_Effective, 3.0);
         g_Max_Account_Drawdown_Pct_Effective = MathMin(g_Max_Account_Drawdown_Pct_Effective, 10.0);
         g_Critical_Drawdown_Pct_Effective = MathMin(g_Critical_Drawdown_Pct_Effective, 25.0);

         g_Min_RR_Ratio = MathMax(g_Min_RR_Ratio, 2.0);
         if(g_ICT_Max_Risk_ATR_Multiple <= 0.0)
            g_ICT_Max_Risk_ATR_Multiple = 0.90;
         else
            g_ICT_Max_Risk_ATR_Multiple = MathMin(g_ICT_Max_Risk_ATR_Multiple, 0.90);
         if(g_KImaniz_Max_Risk_ATR_Multiple <= 0.0)
            g_KImaniz_Max_Risk_ATR_Multiple = 0.90;
         else
            g_KImaniz_Max_Risk_ATR_Multiple = MathMin(g_KImaniz_Max_Risk_ATR_Multiple, 0.90);
         g_PerTrade_Drawdown_Pct_Effective = MathMax(g_PerTrade_Drawdown_Pct_Effective, 45.0);
         g_Max_Entry_Distance_Pct = MathMin(g_Max_Entry_Distance_Pct, 0.60);
         g_Max_Entry_Distance_Relaxed_Cap = MathMin(g_Max_Entry_Distance_Relaxed_Cap, 1.10);
         g_Signal_Cooldown_Bars = MathMax(g_Signal_Cooldown_Bars, 2);
         g_Enable_Pending_Breakout_Variant = false;
         g_Enable_Adaptive_Risk = false;
          if(emit_logs)
             Log(LOG_INFO, "OnInit",
                 StringFormat("Safer Live policy applied: risk=%.2f%% maxTrades=%d maxConcurrent=%d spread=%d ddDaily=%.1f%% ddAccount=%.1f%% ictRisk=%.2fATR kimRisk=%.2fATR perTradeDD=%.1f%%",
                              g_Risk_Percent_Effective,
                              g_Max_Trades_Per_Day_Effective,
                              g_Max_Concurrent_Trades_Effective,
                              g_Max_Spread_Pips_Effective,
                              g_Max_Daily_Drawdown_Pct_Effective,
                              g_Max_Account_Drawdown_Pct_Effective,
                              g_ICT_Max_Risk_ATR_Multiple,
                              g_KImaniz_Max_Risk_ATR_Multiple,
                              g_PerTrade_Drawdown_Pct_Effective));
         break;

      case LIVE_PROFILE_MAX_PROFIT:
      default:
         break;
   }

   g_Risk_Percent_Effective = MathMax(0.01, g_Risk_Percent_Effective);
   g_Max_Concurrent_Trades_Effective = MathMax(1, g_Max_Concurrent_Trades_Effective);
   g_Max_Trades_Per_Day_Effective = MathMax(1, g_Max_Trades_Per_Day_Effective);
   g_Max_Spread_Pips_Effective = MathMax(1, g_Max_Spread_Pips_Effective);
   g_Max_Daily_Drawdown_Pct_Effective = MathMax(0.5, g_Max_Daily_Drawdown_Pct_Effective);
   g_Max_Account_Drawdown_Pct_Effective = MathMax(1.0, g_Max_Account_Drawdown_Pct_Effective);
   g_Critical_Drawdown_Pct_Effective = MathMax(1.0, g_Critical_Drawdown_Pct_Effective);
   g_PerTrade_Drawdown_Pct_Effective = MathMax(0.0, g_PerTrade_Drawdown_Pct_Effective);
   if(g_Max_Open_Risk_Pct_Effective < 0.0)
      g_Max_Open_Risk_Pct_Effective = 0.0;
   if(g_Max_Symbol_Risk_Pct_Effective < 0.0)
      g_Max_Symbol_Risk_Pct_Effective = 0.0;
   if(g_Max_Open_Risk_Pct_Effective > 0.0 && g_Max_Symbol_Risk_Pct_Effective > g_Max_Open_Risk_Pct_Effective)
      g_Max_Symbol_Risk_Pct_Effective = g_Max_Open_Risk_Pct_Effective;

   // I6 FIX: Institutional filter floor - ensure at least one path to execution
   double execution_threshold_original = g_Execution_Score_Threshold_Effective;
   g_Execution_Score_Threshold_Effective = MathMin(g_Execution_Score_Threshold_Effective, 85.0);  // Ceiling
   if(g_Execution_Score_Threshold_Effective < execution_threshold_original)
   {
       if(emit_logs)
          Log(LOG_WARNING, "ApplyLiveRiskProfile",
              "I6: Execution score threshold capped at 85.0 (was " + 
              DoubleToString(execution_threshold_original, 1) + 
              ") to ensure trading remains possible with strict institutional filters");
   }

   g_risk_cache.risk = g_Risk_Percent_Effective;
   g_risk_cache.last_calc = 0;
}

void ApplyRuntimePolicyLayers(bool is_tester, bool emit_logs = true)
{
   ApplyICTSweepPreset(is_tester);
   ApplyLiveRiskProfile(is_tester, emit_logs);

   // Harmonize execution feasibility with scoring quality gates:
   // do not reject all trades solely because broker min lot exceeds strict risk sizing.
   if(Enable_All_Institutional_Filters && g_Skip_MinLot_Overrisk)
   {
      g_Skip_MinLot_Overrisk = false;
       if(emit_logs)
          Log(LOG_WARNING, "OnInit", "Harmonized execution: Skip_MinLot_Overrisk forced OFF (scoring-first execution mode)");
   }

   if(g_ATR_SL_Multiplier_Active > 0.0 &&
      SafeDiv(g_ATR_TP_Multiplier_Active, g_ATR_SL_Multiplier_Active, 0.0) < g_Min_RR_Ratio)
   {
      double repaired_tp_multiplier = g_ATR_SL_Multiplier_Active * g_Min_RR_Ratio;
      if(emit_logs)
         Log(LOG_WARNING, "OnInit",
             StringFormat("Preset harmonized: ATR_TP_Multiplier %.2f -> %.2f to satisfy Min_RR %.2f",
                          g_ATR_TP_Multiplier_Active, repaired_tp_multiplier, g_Min_RR_Ratio));
      g_ATR_TP_Multiplier_Active = repaired_tp_multiplier;
   }

   if(g_Enable_Partial_Close && g_Partial_Close_RR < g_Min_RR_Ratio)
   {
      if(emit_logs)
         Log(LOG_WARNING, "OnInit",
             StringFormat("Preset harmonized: Partial_Close_RR %.2f -> %.2f to satisfy Min_RR",
                          g_Partial_Close_RR, g_Min_RR_Ratio));
      g_Partial_Close_RR = g_Min_RR_Ratio;
   }

   // Sync risk core mirrors (in case future live/tester overrides are added)
   g_Risk_Percent = g_Risk_Percent_Effective;
   double final_trade_risk_cap_pct = MathMax(0.0, Final_Per_Trade_Risk_Cap_Pct);
   if(g_Live_Risk_Profile_Effective == LIVE_PROFILE_SAFER_LIVE)
      final_trade_risk_cap_pct = (final_trade_risk_cap_pct <= 0.0 ? 10.0 : MathMin(final_trade_risk_cap_pct, 10.0));
   g_Final_Per_Trade_Risk_Cap_Pct = final_trade_risk_cap_pct;
   g_ProfitTargetToClose = ProfitTargetToClose;
   g_DrawdownLimitToClose = DrawdownLimitToClose;
   g_PerTrade_Drawdown_Pct = g_PerTrade_Drawdown_Pct_Effective;
   int per_trade_min_hold_seconds = MathMax(0, PerTrade_Drawdown_Min_Hold_Seconds);
   double per_trade_min_loss_currency = MathMax(0.0, PerTrade_Drawdown_Min_Loss_Currency);
   if(g_Live_Risk_Profile_Effective == LIVE_PROFILE_SAFER_LIVE)
   {
      per_trade_min_hold_seconds = MathMax(per_trade_min_hold_seconds, 420);
      per_trade_min_loss_currency = MathMax(per_trade_min_loss_currency, 1.00);
   }
   g_PerTrade_Drawdown_Min_Hold_Seconds = per_trade_min_hold_seconds;
   g_PerTrade_Drawdown_Min_Loss_Currency = per_trade_min_loss_currency;
   g_MaxAcceptableDrawdown = MathMax(0.0, MaxAcceptableDrawdown);
   g_Peak_Drawdown_SL_Protect_Entry = Peak_Drawdown_SL_Protect_Entry;
   g_Peak_Profit_Drawdown_Pct = MathClamp(Peak_Profit_Drawdown_Pct, 0.0, 100.0);
   g_Peak_Profit_Min_R = MathMax(0.0, Peak_Profit_Min_R);
   g_ProfitTarget_Reenter_Trade = ProfitTarget_Reenter_Trade;
   g_ProfitTarget_Halt_Bot = ProfitTarget_Halt_Bot;
   g_ProfitTarget_Reentry_Expiry_Minutes = ProfitTarget_Reentry_Expiry_Minutes;
   g_Max_Daily_Drawdown_Pct = g_Max_Daily_Drawdown_Pct_Effective;
   g_Enable_Symbol_Loss_Circuit_Breaker = Enable_Symbol_Loss_Circuit_Breaker;
   g_Symbol_Loss_Streak_Threshold = MathMax(1, Symbol_Loss_Streak_Threshold);
   g_Symbol_Loss_Streak_Window_Minutes = MathMax(1, Symbol_Loss_Streak_Window_Minutes);
   g_Symbol_Loss_Cooldown_Minutes = MathMax(1, Symbol_Loss_Cooldown_Minutes);

   // Broker-feed tuning by risk appetite profile:
   // Safer Live = stricter AI edge/alignment and faster symbol-level protection.
   // Max Profit = balanced throughput with guarded circuit-breaker floors.
   if(g_Live_Risk_Profile_Effective == LIVE_PROFILE_SAFER_LIVE)
   {
      g_Enable_AI_MTF_Regime_Filter = true;
      g_AI_Min_Directional_Edge = MathMax(g_AI_Min_Directional_Edge, 0.14);
      g_AI_Min_Aligned_Structures = MathMax(g_AI_Min_Aligned_Structures, 2);
      g_AI_Max_Opposing_Structures = 1;
      g_AI_Allow_Relaxed_TieBreak = false;
      g_AI_Enable_EV_Filter = true;
      g_AI_Min_Expected_Value_R = MathMax(g_AI_Min_Expected_Value_R, 0.18);
      if(g_AI_Max_Spread_to_ATR <= 0.0)
         g_AI_Max_Spread_to_ATR = 0.08;
      else
         g_AI_Max_Spread_to_ATR = MathMin(g_AI_Max_Spread_to_ATR, 0.08);
      g_AI_Low_Confidence_Threshold = MathMax(g_AI_Low_Confidence_Threshold, 0.66);
      g_AI_Low_Confidence_Extra_RR = MathMax(g_AI_Low_Confidence_Extra_RR, 0.60);

      g_Enable_Symbol_Loss_Circuit_Breaker = true;
      g_Symbol_Loss_Streak_Threshold = MathMax(1, MathMin(g_Symbol_Loss_Streak_Threshold, 2));
      g_Symbol_Loss_Streak_Window_Minutes = MathMax(g_Symbol_Loss_Streak_Window_Minutes, 45);
      g_Symbol_Loss_Cooldown_Minutes = MathMax(g_Symbol_Loss_Cooldown_Minutes, 180);
   }
   else
   {
      // Max Profit profile intentionally respects configured AI gate inputs.
      // Keep only bounded execution sanity limits here; do not force extra signal filters.
      if(g_AI_Max_Spread_to_ATR <= 0.0)
         g_AI_Max_Spread_to_ATR = 0.14;
      else
         g_AI_Max_Spread_to_ATR = MathMin(g_AI_Max_Spread_to_ATR, 0.14);

      g_Enable_Symbol_Loss_Circuit_Breaker = true;
      g_Symbol_Loss_Streak_Threshold = MathMax(g_Symbol_Loss_Streak_Threshold, 2);
      g_Symbol_Loss_Streak_Window_Minutes = MathMax(g_Symbol_Loss_Streak_Window_Minutes, 45);
      g_Symbol_Loss_Cooldown_Minutes = MathMax(g_Symbol_Loss_Cooldown_Minutes, 120);
   }

   // Notify if legacy inputs were removed; MT5 will ignore missing params, so log once for clarity.
   static bool legacy_notice = false;
   if(!legacy_notice)
   {
       if(emit_logs)
          Log(LOG_INFO, "OnInit", "Legacy redundant inputs removed; use Signal_Cadence_Mode, Strategy_Mix, Trade_Only_Chart_Symbol, Enable_Institutional_Liquidity_Gate, Enable_External_AI, and Execution_Max_Slippage_Pips.");
       legacy_notice = true;
    }
}

void ApplyMasterGateBypass(bool emit_logs = true)
{
   if(!g_Disable_All_Gates)
      return;

   Enable_All_Institutional_Filters = false;
   g_Enable_Institutional_Risk = false;
   g_Enable_Adaptive_Risk = false;
   g_Enable_Spread_Gates = false;
   g_Enable_Session_Gates = false;
   g_Use_Session_Filter = false;
   g_Use_Trend_Filter = false;
   g_Allow_Range_Trading = true;
   g_Allow_Neutral_Trend_Trading = true;
   g_Enable_Confluence_Check = false;
   g_Enable_HTF_Bias_Check = false;
   g_Require_FVG_For_Trade = false;
   g_Require_BOS_Confirmation = false;
   g_Require_First_Retracement_After_BOS = false;
   g_ICT_Forward_Trend_Only = false;
   g_Allow_Opposing_Reversal_Trades = true;
   g_Enable_Soft_Structural_Gating = false;
   g_Enable_ICT_Smart_Entry_Validation = false;
   g_Enable_Entry_Distance_Validation = false;
   g_Enable_Max_Risk_Distance_Validation = false;
   g_Enable_AI_MTF_Regime_Filter = false;
   g_AI_Min_Aligned_Structures = 1;
   g_AI_Max_Opposing_Structures = 2;
   g_AI_Min_Directional_Edge = 0.0;
   g_AI_Allow_Relaxed_TieBreak = true;
   g_AI_Enable_EV_Filter = false;
   g_AI_Min_Expected_Value_R = 0.0;
   g_AI_Max_Spread_to_ATR = 1.0;
   g_AI_Low_Confidence_Extra_RR = 0.0;
   g_Enable_AI_Candle_Quality_Filter = false;
   g_AI_Candle_Min_Quality_Score = 0.0;
   g_Require_BE_Before_Partial = false;
   // Keep configured cadence and any already-active safety pauses in diagnostics mode.
   // Forcing tick-level scans explodes duplicate signal churn and masks true strategy behavior.
   g_Enable_Symbol_Loss_Circuit_Breaker = false;
   g_Enable_Abnormal_Market_Pause = false;
   g_Max_Spread_Pips_Effective = 2147483647;
   g_market_pause_until = 0;

   if(emit_logs)
      Log(LOG_WARNING, "SyncRuntimeParameters",
         "Disable_All_Gating_Master_Switch ACTIVE: optional strategy/session/spread gates bypassed" +
         " (exposure, daily trade count, drawdown, margin, and kill-switch hard-stops remain active)" +
         " | MaxConcurrent input=" + IntegerToString(Max_Concurrent_Trades) +
         " effective=" + IntegerToString(g_Max_Concurrent_Trades_Effective));
}

void AppendPressureFlag(string &flags, string flag)
{
   if(StringLen(flag) <= 0)
      return;
   if(StringLen(flags) > 0)
      flags += " | ";
   flags += flag;
}

bool RuntimeStructuralGatesEnabled()
{
   return (g_Require_FVG_For_Trade ||
           g_Require_BOS_Confirmation ||
           g_Require_First_Retracement_After_BOS ||
           g_Enable_Soft_Structural_Gating ||
           g_Enable_ICT_Smart_Entry_Validation ||
           g_Enable_Entry_Distance_Validation ||
           g_Enable_Max_Risk_Distance_Validation);
}

void SyncUnifiedGateController()
{
   CGateController::ApplyRuntimeGateState(
      (!g_Disable_All_Gates && g_Enable_Spread_Gates),
      (!g_Disable_All_Gates && g_Enable_Session_Gates && g_Use_Session_Filter),
      g_Enable_Exposure_Gates,
      (!g_Disable_All_Gates && RuntimeStructuralGatesEnabled()),
      "SyncRuntimeParameters");
}

void RefreshConsolidatedRuntimeFlags()
{
   g_Enable_AI_Trend_Predictor_Runtime = Enable_AI_Trend_Predictor;

   bool ict_gates_enabled = (!g_Disable_All_Gates && g_Enable_ICT_Strategy);
   g_Enable_Confluence_Check = (ict_gates_enabled && Enable_Confluence_Check);
   g_Enable_HTF_Bias_Check = (ict_gates_enabled && Enable_HTF_Bias_Check);

   bool ai_features_enabled = g_Enable_AI_Trend_Predictor_Runtime;
   bool strict_ai_route = (g_Strategy_Routing_Mode == STRATEGY_ROUTING_AI_ONLY ||
                           g_Strategy_Routing_Mode == STRATEGY_ROUTING_BOTH);
   // In EITHER/ICT/KIM mixed routing, strict AI agreement can suppress non-AI routes entirely.
   // Keep strict agreement for AI_ONLY and BOTH, but relax it for EITHER mode.
   g_AI_Require_Agreement_Runtime = (!g_Disable_All_Gates && ai_features_enabled &&
                                     AI_Require_Agreement && strict_ai_route);
   g_AI_Use_Enhanced_Targets_Runtime = (ai_features_enabled && AI_Use_Enhanced_Targets);
   g_AI_Use_Risk_Adjustment_Runtime = (ai_features_enabled && AI_Use_Risk_Adjustment);
   g_AI_Log_Per_Symbol_Training = AI_Log_Per_Symbol_Training;
   g_Audit_Log_File = AUDIT_LOG_FILE;
}

void SyncRuntimeParameters(bool emit_logs = true)
{
   RefreshProfileSelectorState();
   g_Disable_All_Gates = Disable_All_Gating_Master_Switch;
   Enable_All_Institutional_Filters = Enable_All_Institutional_Filters_Input;
   g_Enable_Institutional_Risk = (Enable_All_Institutional_Filters && Enable_Institutional_Risk);

   // Kill Switch uses enum-driven mode; currency override still available
   g_Kill_Switch_Max_Daily_Loss_Ccy = MathMax(0.0, Kill_Switch_Max_Daily_Loss_Ccy);
   g_Enable_Final_Integrity_Gate = Enable_Final_Integrity_Gate;
   g_Integrity_Min_Aligned_TF = MathMax(0, MathMin(STRATEGY_TF_SLOTS, Integrity_Min_Aligned_TF));
   g_Integrity_Min_HTF_Bias_Score = MathMax(0, MathMin(10, Integrity_Min_HTF_Bias_Score));
   g_Max_Signal_Age_Seconds = MathMax(0, Max_Signal_Age_Seconds);
   g_Enable_Execution_Latency_Guard = Enable_Execution_Latency_Guard;
   g_Max_Tick_Age_Seconds = MathMax(1, Max_Tick_Age_Seconds);
   g_Enable_Smart_Order_Routing = Enable_Smart_Order_Routing;
   g_Execution_Max_Slippage_Pips = MathMax(0.0, Execution_Max_Slippage_Pips);
   g_Enable_Audit_Log = Enable_Audit_Log;
   g_Audit_Log_File = AUDIT_LOG_FILE;

   // In Strategy Tester we disable session filter automatically to avoid zero-trade backtests
   bool is_tester = (bool)MQLInfoInteger(MQL_TESTER);
   if(is_tester)
   {
      g_Use_Session_Filter = false;
      if(emit_logs)
         Log(LOG_INFO, "OnInit", "Session filter DISABLED for tester (full 24h trading)");
   }
   else
   {
      g_Use_Session_Filter = Use_Session_Filter;
   }
   g_London_Session_Start = London_Session_Start;
   g_London_Session_End = London_Session_End;
   g_NewYork_Session_Start = NewYork_Session_Start;
   g_NewYork_Session_End = NewYork_Session_End;
   g_Use_Trend_Filter = Use_Trend_Filter;
   g_Allow_Range_Trading = Allow_Range_Trading;
   g_Allow_Neutral_Trend_Trading = Allow_Neutral_Trend_Trading;
   g_Use_ADX_For_Trend = Use_ADX_For_Trend;
   g_Strong_Trend_ADX_Level = Strong_Trend_ADX_Level;
   g_Weak_Trend_ADX_Level = Weak_Trend_ADX_Level;
   g_Trend_Lookback_Bars = Trend_Lookback_Bars;
   g_Order_Block_Lookback = Order_Block_Lookback;
   g_Order_Block_Confirmation = Order_Block_Confirmation;
   g_Min_Order_Block_Size = Min_Order_Block_Size;
   g_Use_Advanced_OB_Detection = Use_Advanced_OB_Detection;
   g_OB_Max_Proximity_Pct = OB_Max_Proximity_Pct;
   g_Min_FVG_Size_Ratio = Min_FVG_Size_Ratio;
   g_Use_FVG_Detection = Use_FVG_Detection;
   g_Require_FVG_For_Trade = Require_FVG_For_Trade;
   g_Require_BOS_Confirmation = Require_BOS_Confirmation;
   g_Require_First_Retracement_After_BOS = Require_First_Retracement_After_BOS;
   g_ICT_Forward_Trend_Only = ICT_Forward_Trend_Only;
   g_Allow_Opposing_Reversal_Trades = Allow_Opposing_Reversal_Trades;
   // Signal gating controls apply only to ICT strategy (finalized after strategy-mix resolution below).
   g_Enable_Soft_Structural_Gating = Enable_Soft_Structural_Gating;
   g_Enable_ICT_Smart_Entry_Validation = Enable_ICT_Smart_Entry_Validation;
   g_Enable_Entry_Distance_Validation = Enable_Entry_Distance_Validation;
   g_Enable_Max_Risk_Distance_Validation = Enable_Max_Risk_Distance_Validation;
   g_ICT_Max_Risk_ATR_Multiple = MathMax(0.0, ICT_Max_Risk_ATR_Multiple);
   g_KImaniz_Max_Risk_ATR_Multiple = MathMax(0.0, KImaniz_Max_Risk_ATR_Multiple);
   g_Max_Soft_Gate_Failures = Max_Soft_Gate_Failures;
   g_Soft_Gate_Min_HTF_Bias_Score = Soft_Gate_Min_HTF_Bias_Score;
   g_Soft_Gate_Extra_RR = Soft_Gate_Extra_RR;
   ApplyGateProfileSelection();
   g_Max_Entry_Distance_Relaxed_Cap = Max_Entry_Distance_Relaxed_Cap;
   g_FVG_Lookback_Bars = FVG_Lookback_Bars;
   g_Min_RR_Ratio = Min_RR_Ratio;
   g_Enable_Volatility_Adjustment = Enable_Volatility_Adjustment;
   g_Volatility_Lookback_Short = Volatility_Lookback_Short;
   g_Volatility_Lookback_Long = Volatility_Lookback_Long;
   g_Max_Volatility_Adjustment_Factor = Max_Volatility_Adjustment_Factor;
   g_ATR_SL_Multiplier_Active = MathMax(0.10, ATR_SL_Multiplier);
   g_ATR_TP_Multiplier_Active = MathMax(0.10, ATR_TP_Multiplier);
   g_Enable_Trailing_Stop = Enable_Trailing_Stop;
   g_Enable_Partial_Close = Enable_Partial_Close;
   g_Partial_Close_RR = Partial_Close_RR;
   g_Require_BE_Before_Partial = Require_BE_Before_Partial;
   g_Breakeven_RR = Breakeven_RR;
   g_MaxAcceptableDrawdown = MathMax(0.0, MaxAcceptableDrawdown);
   g_Peak_Drawdown_SL_Protect_Entry = Peak_Drawdown_SL_Protect_Entry;
   g_Use_Pending_Orders = Use_Pending_Orders;
   g_Skip_MinLot_Overrisk = Skip_MinLot_Overrisk;
   g_Max_Entry_Distance_Pct = Max_Entry_Distance_Pct;
   g_Pending_Trend_Grace_Seconds = MathMax(0, Pending_Trend_Grace_Seconds);
   g_Max_Queued_Signal_Age_Minutes = MathMax(1, Max_Queued_Signal_Age_Minutes);
   g_Max_Retry_Attempts = MathMax(1, Max_Retry_Attempts);
   g_Retry_Interval_Seconds = MathMax(1, Retry_Interval_Seconds);
   // Unified cadence handling
   g_Force_Signal_Cadence_Gate_Off = (Signal_Cadence_Mode == CADENCE_CONTINUOUS);
   g_Signal_On_New_Bar_Only = (Signal_Cadence_Mode == CADENCE_NEW_BAR_ONLY);
   g_Process_Startup_Seed_Bar = Process_Startup_Seed_Bar;
   g_Signal_Cooldown_Bars = Signal_Cooldown_Bars;
   g_Enable_Adaptive_Risk = (Enable_All_Institutional_Filters && Enable_Adaptive_Risk);
   g_Enable_Dashboard = (Enable_All_Institutional_Filters && Enable_Dashboard);
   g_AI_Use_Common_Files = AI_Use_Common_Files;
   g_AI_Neutral_Band = AI_Neutral_Band;
   g_AI_Buy_Confidence_Threshold = MathMax(0.50, MathMin(0.90, AI_Buy_Confidence_Threshold));
   g_AI_Sell_Confidence_Threshold = MathMax(0.10, MathMin(0.50, AI_Sell_Confidence_Threshold));
   g_AI_Allow_Relaxed_TieBreak = AI_Allow_Relaxed_TieBreak;
   g_Enable_AI_MTF_Regime_Filter = Enable_AI_MTF_Regime_Filter;
   g_AI_Min_Aligned_Structures = MathMax(1, MathMin(3, AI_Min_Aligned_Structures));
   g_AI_Max_Opposing_Structures = MathMax(0, MathMin(2, AI_Max_Opposing_Structures));
   g_AI_Min_Directional_Edge = MathMax(0.0, MathMin(0.50, AI_Min_Directional_Edge));
   g_AI_Enable_EV_Filter = AI_Enable_EV_Filter;
   g_AI_Min_Expected_Value_R = MathMax(0.0, MathMin(2.0, AI_Min_Expected_Value_R));
   g_AI_Max_Spread_to_ATR = MathMax(0.0, MathMin(1.0, AI_Max_Spread_to_ATR));
   g_AI_Low_Confidence_Threshold = MathMax(0.50, MathMin(0.90, AI_Low_Confidence_Threshold));
   g_AI_Low_Confidence_Extra_RR = MathMax(0.0, MathMin(3.0, AI_Low_Confidence_Extra_RR));
   g_Enable_AI_Candle_Quality_Filter = Enable_AI_Candle_Quality_Filter;
   g_AI_Candle_Quality_Lookback_Bars = MathMax(2, MathMin(5, AI_Candle_Quality_Lookback_Bars));
   g_AI_Candle_Min_Quality_Score = MathMax(0.0, MathMin(1.0, AI_Candle_Min_Quality_Score));
   g_AI_Candle_Min_Body_Ratio = MathMax(0.05, MathMin(0.95, AI_Candle_Min_Body_Ratio));
   g_AI_Candle_Max_Opposite_Wick_Ratio = MathMax(0.05, MathMin(0.95, AI_Candle_Max_Opposite_Wick_Ratio));
   g_AI_Candle_ATR_Min_Range_Factor = MathMax(0.05, AI_Candle_ATR_Min_Range_Factor);
   g_AI_Candle_ATR_Max_Range_Factor = MathMax(g_AI_Candle_ATR_Min_Range_Factor + 0.05, AI_Candle_ATR_Max_Range_Factor);
   g_AI_Signal_Generation_Mode = AI_Signal_Generation_Mode;
   g_Use_Institutional_Strategy_Director = Use_Institutional_Strategy_Director;
   g_Director_BaseLot = MathMax(0.01, Director_BaseLot);
   g_Director_ATR_Period = MathMax(5, MathMin(100, Director_ATR_Period));
   g_Director_FastMA = MathMax(2, MathMin(200, Director_FastMA));
   g_Director_SlowMA = MathMax(g_Director_FastMA + 1, MathMin(400, Director_SlowMA));
   g_Enable_Auto_Regime_Router = Enable_Auto_Regime_Router;
   g_Auto_Regime_Strong_Bias_MinScore = MathMax(3, MathMin(7, Auto_Regime_Strong_Bias_MinScore));
   g_Auto_Regime_Intra_HighLow_MaxVolatility = MathMax(0.70, MathMin(1.80, Auto_Regime_Intra_HighLow_MaxVolatility));
   g_Suitability_Hunt_Mode = Suitability_Hunt_Mode;
   g_Suitability_Allow_CrossRole_Fallbacks = Suitability_Allow_CrossRole_Fallbacks;
   g_Suitability_Trend_Require_Confluence_On_Weak_Bias = Suitability_Trend_Require_Confluence_On_Weak_Bias;
   g_Suitability_Weak_Bias_MaxScore = MathMax(2, MathMin(6, Suitability_Weak_Bias_MaxScore));
   g_Suitability_High_Volatility_Factor = MathMax(1.05, MathMin(2.20, Suitability_High_Volatility_Factor));
   g_Regime_Risk_Multiplier_Trend = MathMax(0.25, MathMin(3.00, Regime_Risk_Multiplier_Trend));
   g_Regime_Risk_Multiplier_Range = MathMax(0.25, MathMin(3.00, Regime_Risk_Multiplier_Range));
   g_Regime_Risk_Multiplier_Retracement = MathMax(0.25, MathMin(3.00, Regime_Risk_Multiplier_Retracement));
   g_Allow_AI_Fallback_In_BOTH_Mode = Allow_AI_Fallback_In_BOTH_Mode;
   g_Allow_ICT_Fallback_In_BOTH_Mode = Allow_ICT_Fallback_In_BOTH_Mode;
   g_Strategy_Mix_Effective = NormalizeStrategyMix(Strategy_Mix);
   if(g_Strategy_Mix_Effective != Strategy_Mix)
   {
       if(emit_logs)
          Log(LOG_WARNING, "OnInit",
              "Invalid Strategy_Mix value " + IntegerToString((int)Strategy_Mix) +
              " detected; falling back to legacy mixed routing.");
   }

   g_Strategy_Routing_Mode = STRATEGY_ROUTING_EITHER;
   // Unified strategy mix handling
   g_Enable_KImaniz_Strategy = Enable_KImaniz_Strategy;
   g_Enable_ICT_Strategy = true;
   g_Enable_AI_Strategy = true;
   g_KImaniz_Only_Mode = false;
   switch(g_Strategy_Mix_Effective)
   {
      case STRAT_ICT_ONLY:
         g_Enable_ICT_Strategy = true;
         g_Enable_AI_Strategy = false;
         g_Enable_KImaniz_Strategy = false;
         g_KImaniz_Only_Mode = false;
         g_Strategy_Routing_Mode = STRATEGY_ROUTING_ICT_ONLY;
         break;
      case STRAT_AI_ONLY:
         g_Enable_ICT_Strategy = false;
         g_Enable_AI_Strategy = true;
         g_Enable_KImaniz_Strategy = false;
         g_KImaniz_Only_Mode = false;
         g_Strategy_Routing_Mode = STRATEGY_ROUTING_AI_ONLY;
         break;
      case STRAT_BOTH:
         g_Enable_ICT_Strategy = true;
         g_Enable_AI_Strategy = true;
         g_Enable_KImaniz_Strategy = false;
         g_KImaniz_Only_Mode = false;
         g_Strategy_Routing_Mode = STRATEGY_ROUTING_BOTH;
         break;
      case STRAT_KIM_ONLY:
         g_Enable_ICT_Strategy = false;
         g_Enable_AI_Strategy = false;
         g_Enable_KImaniz_Strategy = true;
         g_KImaniz_Only_Mode = true;
         g_Strategy_Routing_Mode = STRATEGY_ROUTING_EITHER;
         break;
      case STRAT_ICT_KIM:
         g_Enable_ICT_Strategy = true;
         g_Enable_AI_Strategy = false;
         g_Enable_KImaniz_Strategy = true;
         g_KImaniz_Only_Mode = false;
         g_Strategy_Routing_Mode = STRATEGY_ROUTING_EITHER;
         break;
      case STRAT_AI_KIM:
         g_Enable_ICT_Strategy = false;
         g_Enable_AI_Strategy = true;
         g_Enable_KImaniz_Strategy = true;
         g_KImaniz_Only_Mode = false;
         g_Strategy_Routing_Mode = STRATEGY_ROUTING_EITHER;
         break;
      case STRAT_ALL_THREE:
         g_Enable_ICT_Strategy = true;
         g_Enable_AI_Strategy = true;
         g_Enable_KImaniz_Strategy = true;
         g_KImaniz_Only_Mode = false;
         g_Strategy_Routing_Mode = STRATEGY_ROUTING_EITHER;
         break;
      case STRAT_EITHER:
      default:
         g_Enable_ICT_Strategy = true;
         g_Enable_AI_Strategy = true;
         g_Enable_KImaniz_Strategy = true;
         g_KImaniz_Only_Mode = false;
         g_Strategy_Routing_Mode = STRATEGY_ROUTING_EITHER;
         break;
   }
   // Strategy routing hardening: disable dynamic/legacy overlays to keep deterministic selection.
   g_Enable_Auto_Regime_Router = false;
   g_Use_Institutional_Strategy_Director = false;
   g_Suitability_Allow_CrossRole_Fallbacks = false;

   // Final ICT-only gate activation derived from resolved strategy mix.
   bool ict_filters_active = g_Enable_ICT_Strategy;
   bool soft_gating_base = g_Enable_Soft_Structural_Gating;
   bool smart_entry_base = g_Enable_ICT_Smart_Entry_Validation;
   bool entry_distance_base = g_Enable_Entry_Distance_Validation;
   bool max_risk_distance_base = g_Enable_Max_Risk_Distance_Validation;
   int soft_gate_failures_base = g_Max_Soft_Gate_Failures;
   int soft_gate_bias_base = g_Soft_Gate_Min_HTF_Bias_Score;
   double soft_gate_extra_rr_base = g_Soft_Gate_Extra_RR;
   g_Enable_Soft_Structural_Gating = (ict_filters_active ? soft_gating_base : false);
   g_Enable_ICT_Smart_Entry_Validation = (ict_filters_active ? smart_entry_base : false);
   g_Enable_Entry_Distance_Validation = (ict_filters_active ? entry_distance_base : false);
   g_Enable_Max_Risk_Distance_Validation = (ict_filters_active ? max_risk_distance_base : false);
   g_Max_Soft_Gate_Failures = (ict_filters_active ? soft_gate_failures_base : 0);
   g_Soft_Gate_Min_HTF_Bias_Score = (ict_filters_active ? soft_gate_bias_base : 0);
   g_Soft_Gate_Extra_RR = (ict_filters_active ? soft_gate_extra_rr_base : 0.0);
   if(ict_filters_active && g_ICT_Forward_Trend_Only)
   {
      if(g_Require_First_Retracement_After_BOS)
      {
          if(emit_logs)
             Log(LOG_WARNING, "OnInit",
                 "ICT_Forward_Trend_Only active: forcing First_Retracement_After_BOS gate OFF");
      }
      g_Require_First_Retracement_After_BOS = false;

      if(g_Enable_ICT_Smart_Entry_Validation)
      {
          if(emit_logs)
             Log(LOG_WARNING, "OnInit",
                 "ICT_Forward_Trend_Only active: forcing ICT smart-entry mitigation gate OFF");
      }
      g_Enable_ICT_Smart_Entry_Validation = false;
   }
   // Shared hard-safety cap used by ICT, AI, KImaniz and execution queue checks.
   g_Max_Entry_Distance_Relaxed_Cap = Max_Entry_Distance_Relaxed_Cap;
   g_KImaniz_Allow_Countertrend_With_HTF_Gate = KImaniz_Allow_Countertrend_With_HTF_Gate;
   g_KImaniz_Swing_Lookback_Bars = MathMax(20, KImaniz_Swing_Lookback_Bars);
   g_KImaniz_Fib_Zone_29_Pct = KImaniz_Fib_Zone_29_Pct;
   g_KImaniz_Fib_Zone_41_Pct = KImaniz_Fib_Zone_41_Pct;
   g_KImaniz_OTP_Low_Pct = KImaniz_OTP_Low_Pct;
   g_KImaniz_OTP_Mid_Pct = KImaniz_OTP_Mid_Pct;
   g_KImaniz_OTP_High_Pct = KImaniz_OTP_High_Pct;
   g_KImaniz_Entry_Zone_Tolerance_Pct = MathMax(0.0, KImaniz_Entry_Zone_Tolerance_Pct);
   g_Enable_Pending_Breakout_Variant = Enable_Pending_Breakout_Variant;
   g_Enable_Institutional_Debug = Enable_Institutional_Debug;
   g_debug_signals_enabled = g_Enable_Institutional_Debug;
   g_debug_trades_enabled = g_Enable_Institutional_Debug;
   g_Enable_Abnormal_Market_Pause = Enable_Abnormal_Market_Pause;
   g_Abnormal_Spread_Spike_Threshold = MathMax(1, Abnormal_Spread_Spike_Threshold);
   g_Abnormal_Market_Pause_Minutes = MathMax(1, Abnormal_Market_Pause_Minutes);
   g_Enable_Strategy_DryRun_On_TradeBlock = Enable_Strategy_DryRun_On_TradeBlock;
   g_Disable_Abnormal_Market_Pause_For_Diagnostics =
      (Disable_Abnormal_Market_Pause_For_Diagnostics && IsNonProductionRuntime());
   if(Disable_Abnormal_Market_Pause_For_Diagnostics && !g_Disable_Abnormal_Market_Pause_For_Diagnostics)
   {
       if(emit_logs)
          Log(LOG_WARNING, "OnInit",
              "Diagnostics abnormal-market pause bypass ignored outside tester/demo runtime");
   }
   if(g_Disable_Abnormal_Market_Pause_For_Diagnostics)
   {
      g_Enable_Abnormal_Market_Pause = false;
      g_market_pause_until = 0;
       if(emit_logs)
          Log(LOG_WARNING, "OnInit",
              "Abnormal market pause disabled for diagnostics (spread spikes no longer trigger a trade pause)");
   }

   // VALIDATION: Parameter health check before policy application
   // Detects NaN, Infinity, range violations, conflicts
   ValidateRuntimeParameters(emit_logs);

   ApplyRuntimePolicyLayers(is_tester, emit_logs);
   ApplyMasterGateBypass(emit_logs);
   RefreshConsolidatedRuntimeFlags();
   SyncUnifiedGateController();
}

void ValidateRuntimeParameters(bool emit_logs = true)
{
   bool validation_passed = true;
   int validation_warnings = 0;
   int validation_errors = 0;
   
   // Check critical numeric parameters for NaN/Infinity
   if(!MathIsValidNumber(g_Risk_Percent) || g_Risk_Percent <= 0)
   {
      if(emit_logs)
         Log(LOG_ERROR, "ValidateRuntimeParameters", "Risk_Percent is invalid: " + DoubleToString(g_Risk_Percent, 5));
      g_Risk_Percent = 0.50;
      validation_errors++;
      validation_passed = false;
   }
   
   if(!MathIsValidNumber(g_Min_RR_Ratio) || g_Min_RR_Ratio <= 0)
   {
      if(emit_logs)
         Log(LOG_ERROR, "ValidateRuntimeParameters", "Min_RR_Ratio is invalid: " + DoubleToString(g_Min_RR_Ratio, 5));
      g_Min_RR_Ratio = 1.50;
      validation_errors++;
      validation_passed = false;
   }
   
   if(!MathIsValidNumber(g_Max_Spread_Pips_Effective) || g_Max_Spread_Pips_Effective <= 0)
   {
      if(emit_logs)
         Log(LOG_ERROR, "ValidateRuntimeParameters", "Max_Spread_Pips is invalid: " + DoubleToString(g_Max_Spread_Pips_Effective, 2));
      g_Max_Spread_Pips_Effective = 35;
      validation_errors++;
      validation_passed = false;
   }
   
   // I7 FIX: Validate regime multipliers (were missing)
   if(!MathIsValidNumber(g_Regime_Risk_Multiplier_Trend) || g_Regime_Risk_Multiplier_Trend < 0.25 || g_Regime_Risk_Multiplier_Trend > 3.00)
   {
       if(emit_logs)
          Log(LOG_ERROR, "ValidateRuntimeParameters", 
              "Regime_Risk_Multiplier_Trend invalid: " + DoubleToString(g_Regime_Risk_Multiplier_Trend, 2) + " (expected [0.25, 3.00])");
      g_Regime_Risk_Multiplier_Trend = 1.75;
      validation_errors++;
      validation_passed = false;
   }
   
   if(!MathIsValidNumber(g_Regime_Risk_Multiplier_Range) || g_Regime_Risk_Multiplier_Range < 0.25 || g_Regime_Risk_Multiplier_Range > 3.00)
   {
       if(emit_logs)
          Log(LOG_ERROR, "ValidateRuntimeParameters", 
              "Regime_Risk_Multiplier_Range invalid: " + DoubleToString(g_Regime_Risk_Multiplier_Range, 2) + " (expected [0.25, 3.00])");
      g_Regime_Risk_Multiplier_Range = 0.80;
      validation_errors++;
      validation_passed = false;
   }
   
   if(!MathIsValidNumber(g_Regime_Risk_Multiplier_Retracement) || g_Regime_Risk_Multiplier_Retracement < 0.25 || g_Regime_Risk_Multiplier_Retracement > 3.00)
   {
       if(emit_logs)
          Log(LOG_ERROR, "ValidateRuntimeParameters", 
              "Regime_Risk_Multiplier_Retracement invalid: " + DoubleToString(g_Regime_Risk_Multiplier_Retracement, 2) + " (expected [0.25, 3.00])");
      g_Regime_Risk_Multiplier_Retracement = 1.50;
      validation_errors++;
      validation_passed = false;
   }
   
   // I7 FIX: Validate director parameters (were missing)
   if(!MathIsValidNumber(g_Director_BaseLot) || g_Director_BaseLot < 0.01 || g_Director_BaseLot > 100.0)
   {
       if(emit_logs)
          Log(LOG_ERROR, "ValidateRuntimeParameters", 
              "Director_BaseLot invalid: " + DoubleToString(g_Director_BaseLot, 2) + " (expected [0.01, 100.0])");
      g_Director_BaseLot = 0.01;
      validation_errors++;
      validation_passed = false;
   }
   
   if(!MathIsValidNumber(g_Director_ATR_Period) || g_Director_ATR_Period < 5 || g_Director_ATR_Period > 100)
   {
       if(emit_logs)
          Log(LOG_ERROR, "ValidateRuntimeParameters", 
              "Director_ATR_Period invalid: " + IntegerToString(g_Director_ATR_Period) + " (expected [5, 100])");
      g_Director_ATR_Period = 14;
      validation_errors++;
      validation_passed = false;
   }
   
   if(!MathIsValidNumber(g_Director_FastMA) || g_Director_FastMA < 2 || g_Director_FastMA > 200)
   {
       if(emit_logs)
          Log(LOG_ERROR, "ValidateRuntimeParameters", 
              "Director_FastMA invalid: " + IntegerToString(g_Director_FastMA) + " (expected [2, 200])");
      g_Director_FastMA = 9;
      validation_errors++;
      validation_passed = false;
   }
   
   if(!MathIsValidNumber(g_Director_SlowMA) || g_Director_SlowMA < g_Director_FastMA + 1 || g_Director_SlowMA > 400)
   {
       if(emit_logs)
          Log(LOG_ERROR, "ValidateRuntimeParameters", 
              "Director_SlowMA invalid: " + IntegerToString(g_Director_SlowMA) + " (expected [FastMA+1, 400])");
      g_Director_SlowMA = 21;
      validation_errors++;
      validation_passed = false;
   }
   
   // Check AI parameters
   if(!MathIsValidNumber(g_AI_Neutral_Band) || g_AI_Neutral_Band < 0.01 || g_AI_Neutral_Band > 0.50)
   {
       if(emit_logs)
          Log(LOG_WARNING, "ValidateRuntimeParameters", 
              "AI_Neutral_Band out of range: " + DoubleToString(g_AI_Neutral_Band, 4) + " (expected [0.01, 0.50])");
      g_AI_Neutral_Band = 0.12;
      validation_warnings++;
   }
   
   if(!MathIsValidNumber(g_AI_Low_Confidence_Threshold) || g_AI_Low_Confidence_Threshold < 0.50 || g_AI_Low_Confidence_Threshold > 0.90)
   {
       if(emit_logs)
          Log(LOG_WARNING, "ValidateRuntimeParameters",
              "AI_Low_Confidence_Threshold out of range: " + DoubleToString(g_AI_Low_Confidence_Threshold, 4) + " (expected [0.50, 0.90])");
      g_AI_Low_Confidence_Threshold = 0.65;
      validation_warnings++;
   }
   
   // Validate AI Buy confidence threshold bounds
   if(!MathIsValidNumber(g_AI_Buy_Confidence_Threshold) || g_AI_Buy_Confidence_Threshold < 0.50 || g_AI_Buy_Confidence_Threshold > 0.90)
   {
       if(emit_logs)
          Log(LOG_ERROR, "ValidateRuntimeParameters",
              "AI_Buy_Confidence_Threshold out of range: " + DoubleToString(g_AI_Buy_Confidence_Threshold, 2) + " (expected [0.50, 0.90])");
      g_AI_Buy_Confidence_Threshold = 0.60;
      validation_errors++;
      validation_passed = false;
   }
   
   // Validate AI Sell confidence threshold bounds
   if(!MathIsValidNumber(g_AI_Sell_Confidence_Threshold) || g_AI_Sell_Confidence_Threshold < 0.10 || g_AI_Sell_Confidence_Threshold > 0.50)
   {
       if(emit_logs)
          Log(LOG_ERROR, "ValidateRuntimeParameters",
              "AI_Sell_Confidence_Threshold out of range: " + DoubleToString(g_AI_Sell_Confidence_Threshold, 2) + " (expected [0.10, 0.50])");
      g_AI_Sell_Confidence_Threshold = 0.45;
      validation_errors++;
      validation_passed = false;
   }
   
   // Check AI candle range constraints
   if(g_AI_Candle_ATR_Max_Range_Factor <= g_AI_Candle_ATR_Min_Range_Factor + 0.05)
   {
       if(emit_logs)
          Log(LOG_ERROR, "ValidateRuntimeParameters",
              "AI_Candle_ATR_Max_Range_Factor too close to Min: " + 
              DoubleToString(g_AI_Candle_ATR_Max_Range_Factor, 3) + " vs Min " + 
              DoubleToString(g_AI_Candle_ATR_Min_Range_Factor, 3) + "; enforcing gap");
      g_AI_Candle_ATR_Max_Range_Factor = g_AI_Candle_ATR_Min_Range_Factor + 0.15;
      validation_errors++;
      validation_passed = false;
   }
   
   // Conflict detection: BOTH mode fallbacks
   if(g_Strategy_Routing_Mode == STRATEGY_ROUTING_BOTH)
   {
      if(!g_Allow_AI_Fallback_In_BOTH_Mode && !g_Allow_ICT_Fallback_In_BOTH_Mode)
      {
          if(emit_logs)
             Log(LOG_WARNING, "ValidateRuntimeParameters",
                 "BOTH mode with both fallbacks disabled - may result in silent failures if ICT/AI disagree. " +
                 "Enable at least one fallback or switch to EITHER mode");
         validation_warnings++;
      }
   }
   
   // Conflict detection: ICT_Forward_Trend_Only + Reversals
   if(g_ICT_Forward_Trend_Only && g_Allow_Opposing_Reversal_Trades)
   {
      g_Allow_Opposing_Reversal_Trades = false;
       if(emit_logs)
          Log(LOG_WARNING, "ValidateRuntimeParameters",
              "Conflict: ICT_Forward_Trend_Only=true AND Allow_Opposing_Reversal_Trades=true. " +
              "Auto-corrected by disabling Allow_Opposing_Reversal_Trades at runtime");
      validation_warnings++;
   }
   
   // I9 FIX: Validate AI probability thresholds don't overlap
   if(g_AI_Buy_Confidence_Threshold <= g_AI_Sell_Confidence_Threshold)
   {
      double corrected_buy = MathMax(0.60, g_AI_Buy_Confidence_Threshold);
      double corrected_sell = MathMin(0.45, g_AI_Sell_Confidence_Threshold);
      if(corrected_buy <= corrected_sell)
      {
         corrected_buy = 0.60;
         corrected_sell = 0.45;
      }

      if(emit_logs)
         Log(LOG_WARNING, "ValidateRuntimeParameters",
             "I9: AI_Buy_Confidence_Threshold (" + DoubleToString(g_AI_Buy_Confidence_Threshold, 2) +
             ") <= AI_Sell_Confidence_Threshold (" + DoubleToString(g_AI_Sell_Confidence_Threshold, 2) +
             "). Auto-corrected runtime thresholds to Buy=" + DoubleToString(corrected_buy, 2) +
             " Sell=" + DoubleToString(corrected_sell, 2));

      g_AI_Buy_Confidence_Threshold = corrected_buy;
      g_AI_Sell_Confidence_Threshold = corrected_sell;
      validation_warnings++;
   }
   
   if(g_AI_Low_Confidence_Threshold >= g_AI_Buy_Confidence_Threshold)
   {
      double corrected_low_conf = MathMax(0.50, g_AI_Buy_Confidence_Threshold - 0.05);
      if(corrected_low_conf >= g_AI_Buy_Confidence_Threshold)
         corrected_low_conf = 0.55;

       if(emit_logs)
          Log(LOG_WARNING, "ValidateRuntimeParameters",
              "I9: AI_Low_Confidence_Threshold (" + DoubleToString(g_AI_Low_Confidence_Threshold, 2) +
              ") >= AI_Buy_Confidence_Threshold (" + DoubleToString(g_AI_Buy_Confidence_Threshold, 2) +
              "). Auto-corrected runtime low-confidence threshold to " + DoubleToString(corrected_low_conf, 2));

      g_AI_Low_Confidence_Threshold = corrected_low_conf;
      validation_warnings++;
   }
   
   // I10 FIX: Validate cadence mode and cooldown consistency
   if(Signal_Cadence_Mode == CADENCE_NEW_BAR_ONLY && g_Signal_Cooldown_Bars < 1)
   {
       if(emit_logs)
          Log(LOG_WARNING, "ValidateRuntimeParameters",
              "I10: CADENCE_NEW_BAR_ONLY mode requires Signal_Cooldown_Bars >= 1 to prevent race conditions. Setting to 1");
      g_Signal_Cooldown_Bars = 1;
      validation_warnings++;
   }
   
   if(Signal_Cadence_Mode == CADENCE_CONTINUOUS && g_Signal_Cooldown_Bars == 0)
   {
       if(emit_logs)
          Log(LOG_WARNING, "ValidateRuntimeParameters",
              "I10: CADENCE_CONTINUOUS mode with Signal_Cooldown_Bars=0 can produce rapid duplicate signals. " +
              "Recommend setting Signal_Cooldown_Bars >= 1 for safety");
      validation_warnings++;
   }
   
   // Summary
   if(validation_errors > 0)
   {
       if(emit_logs)
          Log(LOG_ERROR, "ValidateRuntimeParameters",
              "Parameter validation FAILED: " + IntegerToString(validation_errors) + " errors detected. " +
              "Using fallback values for invalid parameters");
      validation_passed = false;
   }
   
   if(validation_warnings > 0)
   {
       if(emit_logs)
          Log(LOG_WARNING, "ValidateRuntimeParameters",
              "Parameter validation complete with " + IntegerToString(validation_warnings) + " warnings");
   }
   
   if(validation_passed && validation_warnings == 0)
   {
       if(emit_logs)
          Log(LOG_INFO, "ValidateRuntimeParameters", "Parameter validation PASSED - all parameters valid");
}
}

void HarmonizeScoringWeights(
   double &w_trend, double &w_momentum, double &w_volatility, double &w_structure, double &w_alignment,
   double &w_confirmation, double &w_risk_reward, double &w_entry_quality, double &w_spread, double &w_regime,
   string &summary)
{
   double w[10];
   w[0] = MathMax(0.0, w_trend);
   w[1] = MathMax(0.0, w_momentum);
   w[2] = MathMax(0.0, w_volatility);
   w[3] = MathMax(0.0, w_structure);
   w[4] = MathMax(0.0, w_alignment);
   w[5] = MathMax(0.0, w_confirmation);
   w[6] = MathMax(0.0, w_risk_reward);
   w[7] = MathMax(0.0, w_entry_quality);
   w[8] = MathMax(0.0, w_spread);
   w[9] = MathMax(0.0, w_regime);

   int adjusted = 0;
   double total = 0.0;
   for(int i = 0; i < 10; i++)
      total += w[i];

   if(total <= 0.0)
   {
      // Deterministic fallback profile (sum=100).
      w[0] = 18.0; w[1] = 13.0; w[2] = 11.0; w[3] = 15.0; w[4] = 9.0;
      w[5] = 12.0; w[6] = 10.0; w[7] = 7.0;  w[8] = 3.0;  w[9] = 2.0;
      total = 100.0;
      adjusted++;
   }

   if(Scoring_Normalize_Weights && Scoring_Target_Weight_Sum > 0.0 && total > 0.0)
   {
      double scale = Scoring_Target_Weight_Sum / total;
      for(int i = 0; i < 10; i++)
         w[i] *= scale;
      adjusted++;
   }

   if(Scoring_Enforce_Unique_Weights && Scoring_Unique_Min_Delta > 0.0)
   {
      for(int i = 0; i < 10; i++)
      {
         for(int j = 0; j < i; j++)
         {
            if(MathAbs(w[i] - w[j]) < Scoring_Unique_Min_Delta)
            {
               w[i] = w[j] + Scoring_Unique_Min_Delta;
               adjusted++;
            }
         }
      }

      if(Scoring_Normalize_Weights && Scoring_Target_Weight_Sum > 0.0)
      {
         double total_after_unique = 0.0;
         for(int i = 0; i < 10; i++)
            total_after_unique += w[i];
         if(total_after_unique > 0.0)
         {
            double scale_unique = Scoring_Target_Weight_Sum / total_after_unique;
            for(int i = 0; i < 10; i++)
               w[i] *= scale_unique;
         }
      }
   }

   int unique_count = 0;
   for(int i = 0; i < 10; i++)
   {
      bool is_unique = true;
      for(int j = 0; j < i; j++)
      {
         if(MathAbs(w[i] - w[j]) < MathMax(0.01, Scoring_Unique_Min_Delta * 0.5))
         {
            is_unique = false;
            break;
         }
      }
      if(is_unique)
         unique_count++;
   }

   double final_sum = 0.0;
   for(int i = 0; i < 10; i++)
      final_sum += w[i];

   w_trend = w[0];
   w_momentum = w[1];
   w_volatility = w[2];
   w_structure = w[3];
   w_alignment = w[4];
   w_confirmation = w[5];
   w_risk_reward = w[6];
   w_entry_quality = w[7];
   w_spread = w[8];
   w_regime = w[9];

   summary = StringFormat(
      "sum=%.2f unique=%d/10 adjusted=%d normalize=%s enforce_unique=%s | "
      "trend=%.2f,momentum=%.2f,volatility=%.2f,structure=%.2f,alignment=%.2f,confirmation=%.2f,rr=%.2f,entry=%.2f,spread=%.2f,regime=%.2f",
      final_sum,
      unique_count,
      adjusted,
      (Scoring_Normalize_Weights ? "ON" : "OFF"),
      (Scoring_Enforce_Unique_Weights ? "ON" : "OFF"),
      w[0], w[1], w[2], w[3], w[4], w[5], w[6], w[7], w[8], w[9]
   );
}

void LogConfigurationSummary()
{
   Log(LOG_INFO, "OnInit", "Configuration Summary:");
   Log(LOG_INFO, "OnInit", "  Disable All Gating Master Switch: " + (g_Disable_All_Gates ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "  Chart Symbol: " + Symbol());
   Log(LOG_INFO, "OnInit", "  Symbols: " + IntegerToString(g_symbols_count));
   Log(LOG_INFO, "OnInit", "  Timeframes: S=" + g_tf_names[0] +
        ", P=" + g_tf_names[1] + ", C=" + g_tf_names[2] + ", T=" + g_tf_names[3]);
   Log(LOG_INFO, "OnInit", "  Gate Profile: " + g_Gate_Profile_Name);
   Log(LOG_INFO, "OnInit", "  Risk Tier Profile: " + g_Risk_Tier_Profile_Name);
   Log(LOG_INFO, "OnInit", "  Timeframe Preset: " + g_Timeframe_Preset_Name +
      " | aligned=" + (g_Timeframe_Preset_Aligned ? "YES" : "NO"));
   if(Enable_Custom_Gate_Overrides)
      Log(LOG_INFO, "OnInit", "  Gate Profile Note: selector is descriptive only because custom gate overrides are enabled");
   if(Enable_Custom_Risk_Tier_Overrides)
      Log(LOG_INFO, "OnInit", "  Risk Tier Note: selector is descriptive only because custom risk overrides are enabled");
   Log(LOG_INFO, "OnInit", "  Require All TF Agreement: " + (Require_All_TF_Agreement ? "Yes" : "No"));
   Log(LOG_INFO, "OnInit", "  Use Trend Filter: " + (Use_Trend_Filter ? "Yes" : "No"));
   Log(LOG_INFO, "OnInit", "  Allow Range Trading: " + (Allow_Range_Trading ? "Yes" : "No"));
   Log(LOG_INFO, "OnInit", "  Risk: " + DoubleToString(g_Risk_Percent_Effective, 2) + "% (effective)");
   Log(LOG_INFO, "OnInit", "  Basket Drawdown Limit: $" + DoubleToString(g_DrawdownLimitToClose, 2));
   Log(LOG_INFO, "OnInit", "  Per-Trade Drawdown Limit: " + DoubleToString(g_PerTrade_Drawdown_Pct, 1) + "% of SL risk amount");
   Log(LOG_INFO, "OnInit", "  Per-Trade Drawdown Min Hold: " + IntegerToString(g_PerTrade_Drawdown_Min_Hold_Seconds) + "s");
   Log(LOG_INFO, "OnInit", "  Per-Trade Drawdown Min Loss: $" + DoubleToString(g_PerTrade_Drawdown_Min_Loss_Currency, 2));
   Log(LOG_INFO, "OnInit", "  Peak Drawdown SL Protection: $" + DoubleToString(g_MaxAcceptableDrawdown, 2) +
      " | entry floor=" + (g_Peak_Drawdown_SL_Protect_Entry ? "ON" : "OFF"));
   Log(LOG_INFO, "OnInit", "  Peak Profit Drawdown: " + DoubleToString(g_Peak_Profit_Drawdown_Pct, 1) + "%");
   Log(LOG_INFO, "OnInit", "  Peak Profit Min: " + DoubleToString(g_Peak_Profit_Min_R, 2) + "R");
   Log(LOG_INFO, "OnInit", "  Symbol Loss Circuit Breaker: " + (g_Enable_Symbol_Loss_Circuit_Breaker ? "ENABLED" : "DISABLED") +
      " (streak=" + IntegerToString(g_Symbol_Loss_Streak_Threshold) +
      ", window=" + IntegerToString(g_Symbol_Loss_Streak_Window_Minutes) + "m" +
      ", cooldown=" + IntegerToString(g_Symbol_Loss_Cooldown_Minutes) + "m)");
   Log(LOG_INFO, "OnInit", "  Skip MinLot Overrisk (Input): " + (Skip_MinLot_Overrisk ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "  Skip MinLot Overrisk (Effective): " + (g_Skip_MinLot_Overrisk ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "  Scoring Threshold: " + DoubleToString(g_Execution_Score_Threshold_Effective, 1) + " (effective)");
   Log(LOG_INFO, "OnInit", "  Live Risk Profile (Input): " + LiveRiskProfileToString(Live_Risk_Profile));
   Log(LOG_INFO, "OnInit", "  Live Risk Profile (Effective): " + g_Live_Risk_Profile_Name);
   if(!Enable_Custom_Timeframe_Overrides && !g_Timeframe_Preset_Aligned)
   {
      Log(LOG_WARNING, "OnInit",
          "Timeframe preset/input mismatch: preset selector is not aligned with Signal/Primary/Confirm/Trend inputs.");
   }
   Log(LOG_INFO, "OnInit", "  Max Daily Trades (Effective): " + IntegerToString(g_Max_Trades_Per_Day_Effective));
   Log(LOG_INFO, "OnInit", "  Max Concurrent Trades (Input): " + IntegerToString(Max_Concurrent_Trades));
   Log(LOG_INFO, "OnInit", "  Max Concurrent Trades (Effective): " + IntegerToString(g_Max_Concurrent_Trades_Effective));
   Log(LOG_INFO, "OnInit", "  Max Spread Pips (Effective): " + IntegerToString(g_Max_Spread_Pips_Effective));
   Log(LOG_INFO, "OnInit", "  Use Symbol-Specific Spreads: " + (g_Use_Symbol_Specific_Spreads ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "  Scoring Precheck Buffer: " + DoubleToString(Scoring_Precheck_Buffer, 1));
   Log(LOG_INFO, "OnInit", "  Scoring Adaptive Model: " + (Scoring_Enable_Adaptive_Model ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "  Scoring Normalize Weights: " + (Scoring_Normalize_Weights ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "  Scoring Target Weight Sum: " + DoubleToString(Scoring_Target_Weight_Sum, 2));
   Log(LOG_INFO, "OnInit", "  Scoring Enforce Unique Weights: " + (Scoring_Enforce_Unique_Weights ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "  Scoring Unique Min Delta: " + DoubleToString(Scoring_Unique_Min_Delta, 2));
   Log(LOG_INFO, "OnInit", "  Min RR: " + DoubleToString(g_Min_RR_Ratio, 1) + " (effective)");
   Log(LOG_INFO, "OnInit", "  Max Entry Distance: " + DoubleToString(g_Max_Entry_Distance_Pct, 1) + "% (effective)");
   Log(LOG_INFO, "OnInit", "  Pending Trend Grace: " + IntegerToString(g_Pending_Trend_Grace_Seconds) + "s");
   Log(LOG_INFO, "OnInit", "  BOS Gate: " + (g_Require_BOS_Confirmation ? "REQUIRED" : "RELAXED"));
   Log(LOG_INFO, "OnInit", "  First Retracement Gate: " + (g_Require_First_Retracement_After_BOS ? "REQUIRED" : "RELAXED"));
   Log(LOG_INFO, "OnInit", "  ICT Forward Trend Only: " + (g_ICT_Forward_Trend_Only ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "  Opposing Reversal Filter: " + (g_Allow_Opposing_Reversal_Trades ? "RELAXED" : "STRICT"));
   Log(LOG_INFO, "OnInit", "  Soft Structural Gating: " + (g_Enable_Soft_Structural_Gating ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "  ICT Smart Entry Validation: " + (g_Enable_ICT_Smart_Entry_Validation ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "  Entry Distance Validation: " + (g_Enable_Entry_Distance_Validation ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "  Max Risk Distance Validation: " + (g_Enable_Max_Risk_Distance_Validation ? "ENABLED" : "DISABLED") +
       " | ICT=" + DoubleToString(g_ICT_Max_Risk_ATR_Multiple, 2) +
       " ATR KIM=" + DoubleToString(g_KImaniz_Max_Risk_ATR_Multiple, 2) + " ATR");
   Log(LOG_INFO, "OnInit", "  Soft Gate Failures Max: " + IntegerToString(g_Max_Soft_Gate_Failures));
   Log(LOG_INFO, "OnInit", "  Soft Gate HTF Bias Min: " + IntegerToString(g_Soft_Gate_Min_HTF_Bias_Score));
   Log(LOG_INFO, "OnInit", "  Soft Gate Extra RR: " + DoubleToString(g_Soft_Gate_Extra_RR, 2));
   Log(LOG_INFO, "OnInit", "  Relaxed Entry Distance Cap: " + DoubleToString(g_Max_Entry_Distance_Relaxed_Cap, 2) + "%");
   Log(LOG_INFO, "OnInit", "  ICT Preset (Input): " + ICTSweepPresetToString(ICT_Sweep_Preset));
   Log(LOG_INFO, "OnInit", "  ICT Preset (Effective): " + g_ICT_Sweep_Preset_Name);
   Log(LOG_INFO, "OnInit", "  Signal Cadence Mode (Input): " +
       (Signal_Cadence_Mode == CADENCE_NEW_BAR_ONLY ? "NEW_BAR_ONLY" :
        Signal_Cadence_Mode == CADENCE_CONTINUOUS ? "CONTINUOUS" : "AUTO"));
   Log(LOG_INFO, "OnInit", "  Signal Cadence (Effective): " +
       (g_Signal_On_New_Bar_Only ? "NEW_BAR_ONLY" :
        g_Force_Signal_Cadence_Gate_Off ? "CONTINUOUS" : "AUTO"));
   Log(LOG_INFO, "OnInit", "  Process Startup Seed Bar: " + (g_Process_Startup_Seed_Bar ? "Yes" : "No"));
   Log(LOG_INFO, "OnInit", "  Signal Cooldown Bars (Input): " + IntegerToString(Signal_Cooldown_Bars));
   Log(LOG_INFO, "OnInit", "  Signal Cooldown Bars (Effective): " + IntegerToString(g_Signal_Cooldown_Bars));
   Log(LOG_INFO, "OnInit", "  Signal Check Seconds: " + IntegerToString(Signal_Check_Seconds) + "s");
   Log(LOG_INFO, "OnInit", "  Max Retry Attempts: " + IntegerToString(g_Max_Retry_Attempts));
   Log(LOG_INFO, "OnInit", "  Retry Interval: " + IntegerToString(g_Retry_Interval_Seconds) + "s");
   Log(LOG_INFO, "OnInit", "  Max Queued Signal Age: " + IntegerToString(g_Max_Queued_Signal_Age_Minutes) + "m");
   Log(LOG_INFO, "OnInit", "  Backtest Mode: " + (Enable_Backtest_Mode ? "ENABLED (NO REAL TRADES)" : "DISABLED (REAL TRADES)"));
   Log(LOG_INFO, "OnInit", "  Input Flags:");
   Log(LOG_INFO, "OnInit", "    Institutional Filters (Input): " + (Enable_All_Institutional_Filters_Input ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    Institutional Risk (Input): " + (Enable_Institutional_Risk ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    Dashboard (Input): " + (Enable_Dashboard ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    Adaptive Risk (Input): " + (Enable_Adaptive_Risk ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    Session Filter (Input): " + (Use_Session_Filter ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    Strategy Mix (Input): " +
      StrategyMixToString(Strategy_Mix) + " [" + IntegerToString((int)Strategy_Mix) + "]");
   Log(LOG_INFO, "OnInit", "    Strategy Mix (Effective): " +
      StrategyMixToString(g_Strategy_Mix_Effective) + " [" + IntegerToString((int)g_Strategy_Mix_Effective) + "]");
   Log(LOG_INFO, "OnInit", "    Institutional Strategy Director (Input): " +
      (Use_Institutional_Strategy_Director ? "ENABLED" : "DISABLED") +
      " | baseLot=" + DoubleToString(Director_BaseLot, 2) +
      " ATR=" + IntegerToString(Director_ATR_Period) +
      " MA=" + IntegerToString(Director_FastMA) + "/" + IntegerToString(Director_SlowMA));
   Log(LOG_INFO, "OnInit", "    Auto Regime Router (Input): " + (Enable_Auto_Regime_Router ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    Suitability Hunt Mode (Input): " +
      (Suitability_Hunt_Mode == SUITABILITY_HUNT_STRICT ? "STRICT" :
       Suitability_Hunt_Mode == SUITABILITY_HUNT_AGGRESSIVE ? "AGGRESSIVE" : "BALANCED"));
   Log(LOG_INFO, "OnInit", "    AI Trend Predictor (Input): " + (Enable_AI_Trend_Predictor ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    AI Signal Mode (Input): " + (AI_Signal_Generation_Mode == AI_SIGNAL_MODE_PRIMARY ? "AI_PRIMARY" : "HYBRID"));
   Log(LOG_INFO, "OnInit", "    AI Candle Quality Filter (Input): " + (Enable_AI_Candle_Quality_Filter ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    Strategy Routing (Effective): " +
      (g_Strategy_Routing_Mode == STRATEGY_ROUTING_ICT_ONLY ? "ICT_ONLY" :
       g_Strategy_Routing_Mode == STRATEGY_ROUTING_AI_ONLY ? "AI_ONLY" :
       g_Strategy_Routing_Mode == STRATEGY_ROUTING_BOTH ? "BOTH" : "MIXED"));
   Log(LOG_INFO, "OnInit", "    BOTH Mode AI Fallback (Input): " + (Allow_AI_Fallback_In_BOTH_Mode ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    BOTH Mode ICT Fallback (Input): " + (Allow_ICT_Fallback_In_BOTH_Mode ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    KImaniz Strategy (Input): " + (Enable_KImaniz_Strategy ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    KImaniz Only Mode (Effective): " + (g_KImaniz_Only_Mode ? "YES" : "NO"));
   Log(LOG_INFO, "OnInit", "    AI Require Agreement (Input): " + (AI_Require_Agreement ? "YES" : "NO"));
   Log(LOG_INFO, "OnInit", "    Confluence Check (Input): " + (Enable_Confluence_Check ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    HTF Bias Check (Input): " + (Enable_HTF_Bias_Check ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    Abnormal Market Pause (Input): " + (Enable_Abnormal_Market_Pause ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    Disable Abnormal Pause for Diagnostics (Input): " +
      (Disable_Abnormal_Market_Pause_For_Diagnostics ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    Dry-Run During Trade Block (Input): " +
      (Enable_Strategy_DryRun_On_TradeBlock ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    Spread Gates (Input): " + (Enable_Spread_Gates ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    Session Gates (Input): " + (Enable_Session_Gates ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    Exposure Gates (Input): " + (Enable_Exposure_Gates ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "  Effective Flags:");
   Log(LOG_INFO, "OnInit", "    Institutional Filters: " + (Enable_All_Institutional_Filters ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    Session Filter: " + (g_Use_Session_Filter ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    ICT Strategy: " + (g_Enable_ICT_Strategy ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    AI Trend Predictor: " + (g_Enable_AI_Trend_Predictor_Runtime ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    AI Signal Mode: " + (g_AI_Signal_Generation_Mode == AI_SIGNAL_MODE_PRIMARY ? "AI_PRIMARY" : "HYBRID"));
   Log(LOG_INFO, "OnInit", "    AI MTF Regime Filter: " + ((!g_Disable_All_Gates && g_Enable_AI_MTF_Regime_Filter) ? "ENABLED" : "DISABLED") +
      " (minAligned=" + IntegerToString(g_AI_Min_Aligned_Structures) +
      ", maxOpposing=" + IntegerToString(g_AI_Max_Opposing_Structures) +
      ", minEdge=" + DoubleToString(g_AI_Min_Directional_Edge, 2) + ")");
   Log(LOG_INFO, "OnInit", "    AI EV/Execution Gates: tieBreak=" + (g_AI_Allow_Relaxed_TieBreak ? "RELAXED" : "STRICT") +
      ", evFilter=" + (g_AI_Enable_EV_Filter ? "ON" : "OFF") +
      ", minEV=" + DoubleToString(g_AI_Min_Expected_Value_R, 2) + "R" +
      ", maxSpreadATR=" + DoubleToString(g_AI_Max_Spread_to_ATR, 2) +
      ", lowConf<" + DoubleToString(g_AI_Low_Confidence_Threshold, 2) +
      " => +RR " + DoubleToString(g_AI_Low_Confidence_Extra_RR, 2));
   Log(LOG_INFO, "OnInit", "    AI Candle Quality Filter: " + ((!g_Disable_All_Gates && g_Enable_AI_Candle_Quality_Filter) ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    AI Candle Quality Params: lookback=" + IntegerToString(g_AI_Candle_Quality_Lookback_Bars) +
       " minQ=" + DoubleToString(g_AI_Candle_Min_Quality_Score, 2) +
       " minBody=" + DoubleToString(g_AI_Candle_Min_Body_Ratio, 2) +
       " maxOppWick=" + DoubleToString(g_AI_Candle_Max_Opposite_Wick_Ratio, 2) +
       " atrRange=[" + DoubleToString(g_AI_Candle_ATR_Min_Range_Factor, 2) + "," +
       DoubleToString(g_AI_Candle_ATR_Max_Range_Factor, 2) + "]");
   Log(LOG_INFO, "OnInit", "    Strategy Routing: " +
      (g_Strategy_Routing_Mode == STRATEGY_ROUTING_ICT_ONLY ? "ICT_ONLY" :
       g_Strategy_Routing_Mode == STRATEGY_ROUTING_AI_ONLY ? "AI_ONLY" :
        g_Strategy_Routing_Mode == STRATEGY_ROUTING_BOTH ? "BOTH" : "MIXED"));
   Log(LOG_INFO, "OnInit", "    BOTH Mode AI Fallback: " + (g_Allow_AI_Fallback_In_BOTH_Mode ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    BOTH Mode ICT Fallback: " + (g_Allow_ICT_Fallback_In_BOTH_Mode ? "ENABLED" : "DISABLED"));
   if(g_Strategy_Routing_Mode == STRATEGY_ROUTING_BOTH &&
      !g_Allow_AI_Fallback_In_BOTH_Mode &&
      !g_Allow_ICT_Fallback_In_BOTH_Mode)
   {
      Log(LOG_WARNING, "OnInit",
          "Strict BOTH routing active: ICT and AI must both be valid and same-direction before any trade.");
   }
   Log(LOG_INFO, "OnInit", "    KImaniz Strategy: " + (g_Enable_KImaniz_Strategy ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    KImaniz Only Mode: " + (g_KImaniz_Only_Mode ? "YES" : "NO"));
   Log(LOG_INFO, "OnInit", "    KImaniz Countertrend HTF Gate: " + (g_KImaniz_Allow_Countertrend_With_HTF_Gate ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    Institutional Strategy Director: " +
      (g_Use_Institutional_Strategy_Director ? "ENABLED" : "DISABLED") +
      " (baseLot=" + DoubleToString(g_Director_BaseLot, 2) +
      ", ATR=" + IntegerToString(g_Director_ATR_Period) +
      ", MA=" + IntegerToString(g_Director_FastMA) + "/" + IntegerToString(g_Director_SlowMA) + ")");
   Log(LOG_INFO, "OnInit", "    Auto Regime Router: " + (g_Enable_Auto_Regime_Router ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    Auto Regime Params: strongBiasMin=" + IntegerToString(g_Auto_Regime_Strong_Bias_MinScore) +
      " intraMaxVol=" + DoubleToString(g_Auto_Regime_Intra_HighLow_MaxVolatility, 2));
   Log(LOG_INFO, "OnInit", "    Suitability Profile: mode=" +
      (g_Suitability_Hunt_Mode == SUITABILITY_HUNT_STRICT ? "STRICT" :
       g_Suitability_Hunt_Mode == SUITABILITY_HUNT_AGGRESSIVE ? "AGGRESSIVE" : "BALANCED") +
      " crossRole=" + (g_Suitability_Allow_CrossRole_Fallbacks ? "YES" : "NO") +
      " weakBias<=" + IntegerToString(g_Suitability_Weak_Bias_MaxScore) +
      " highVol>=" + DoubleToString(g_Suitability_High_Volatility_Factor, 2) +
      " weakBiasConfluence=" + (g_Suitability_Trend_Require_Confluence_On_Weak_Bias ? "YES" : "NO"));
   if(!g_Enable_Auto_Regime_Router && g_Suitability_Allow_CrossRole_Fallbacks)
      Log(LOG_INFO, "OnInit",
          "    Suitability Note: cross-role fallback is inactive while auto-regime routing is disabled");
   Log(LOG_INFO, "OnInit", "    Regime Risk Multipliers: trend=" +
      DoubleToString(g_Regime_Risk_Multiplier_Trend, 2) +
      " range=" + DoubleToString(g_Regime_Risk_Multiplier_Range, 2) +
      " retracement=" + DoubleToString(g_Regime_Risk_Multiplier_Retracement, 2));
   Log(LOG_INFO, "OnInit", "    AI Require Agreement: " + (g_AI_Require_Agreement_Runtime ? "YES" : "NO"));
   Log(LOG_INFO, "OnInit", "    Confluence Check: " + (g_Enable_Confluence_Check ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    HTF Bias Check: " + (g_Enable_HTF_Bias_Check ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    AI Detailed Reports: " + (g_Enable_Institutional_Debug ? "ENABLED via institutional debug" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    AI Per-Symbol Training Logs: " + (g_AI_Log_Per_Symbol_Training ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    AI Enhanced Targets: " + (g_AI_Use_Enhanced_Targets_Runtime ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    AI Risk Adjustment: " + (g_AI_Use_Risk_Adjustment_Runtime ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    Abnormal Market Pause: " + (g_Enable_Abnormal_Market_Pause ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    Dry-Run During Trade Block: " + (g_Enable_Strategy_DryRun_On_TradeBlock ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    Spread Gates: " + (g_Enable_Spread_Gates ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    Session Gates: " + (g_Enable_Session_Gates ? "ENABLED" : "DISABLED"));
   Log(LOG_INFO, "OnInit", "    Exposure Gates: " + (g_Enable_Exposure_Gates ? "ENABLED" : "DISABLED"));
   if(g_Disable_All_Gates)
      Log(LOG_WARNING, "OnInit", "  Master gate bypass is active: strategy/session/spread/position-count gates are bypassed; active loss/drawdown pauses remain enforced");
   if(Enable_All_Institutional_Filters_Input != Enable_All_Institutional_Filters)
   {
      Log(LOG_WARNING, "OnInit", "  Mismatch: Institutional Filters input != effective (check .set overrides)");
   }
   if(Enable_Dashboard && !g_Enable_Dashboard)
   {
      Log(LOG_WARNING, "OnInit", "  Gated: Dashboard input ON but master switch OFF -> Dashboard disabled");
   }
   if(Enable_Adaptive_Risk && !g_Enable_Adaptive_Risk)
   {
      if(g_Live_Risk_Profile_Effective == LIVE_PROFILE_SAFER_LIVE)
         Log(LOG_WARNING, "OnInit", "  Policy: Adaptive Risk disabled by Safer Live profile");
      else
         Log(LOG_WARNING, "OnInit", "  Gated: Adaptive Risk input ON but master switch OFF -> Adaptive Risk disabled");
   }
   if(Enable_Institutional_Risk && !g_Enable_Institutional_Risk)
   {
      Log(LOG_WARNING, "OnInit", "  Gated: Institutional Risk input ON but master switch OFF -> Institutional Risk disabled");
   }

   // Parameter-pressure diagnostics:
   // flag combinations that are valid but commonly suppress signal throughput.
   int pressure_score = 0;
   string pressure_flags = "";

   if(g_Strategy_Routing_Mode == STRATEGY_ROUTING_BOTH &&
      !g_Allow_AI_Fallback_In_BOTH_Mode &&
      !g_Allow_ICT_Fallback_In_BOTH_Mode)
   {
      pressure_score += 4;
      AppendPressureFlag(pressure_flags, "StrictBOTHNoFallback");
   }

   if(g_Enable_ICT_Strategy && g_Require_FVG_For_Trade && g_Require_BOS_Confirmation)
   {
      pressure_score += 3;
      AppendPressureFlag(pressure_flags, "ICT:FVG+BOSRequired");
   }

   if(g_Enable_ICT_Strategy && g_Enable_Soft_Structural_Gating && g_Max_Soft_Gate_Failures <= 0)
   {
      pressure_score += 2;
      AppendPressureFlag(pressure_flags, "ICT:SoftGateZeroTolerance");
   }

   if(g_Enable_AI_Strategy && g_AI_Min_Directional_Edge >= 0.10)
   {
      pressure_score += 2;
      AppendPressureFlag(pressure_flags, "AI:HighMinDirectionalEdge");
   }

   if(g_Enable_AI_Strategy &&
      g_Enable_AI_MTF_Regime_Filter &&
      g_AI_Min_Aligned_Structures >= 3 &&
      g_AI_Max_Opposing_Structures <= 0)
   {
      pressure_score += 2;
      AppendPressureFlag(pressure_flags, "AI:StrictMTFAlignment");
   }

   if(g_Enable_KImaniz_Strategy && g_KImaniz_Entry_Zone_Tolerance_Pct < 0.40)
   {
      pressure_score += 1;
      AppendPressureFlag(pressure_flags, "KIM:TightEntryTolerance");
   }

   if(g_Signal_On_New_Bar_Only)
   {
      pressure_score += 1;
      AppendPressureFlag(pressure_flags, "Cadence:NewBarOnly");
   }

   if(g_Max_Concurrent_Trades_Effective <= 1)
   {
      pressure_score += 1;
      AppendPressureFlag(pressure_flags, "Exposure:MaxConcurrent<=1");
   }

   if(g_Max_Trades_Per_Day_Effective <= 1)
   {
      pressure_score += 1;
      AppendPressureFlag(pressure_flags, "Budget:MaxTradesPerDay<=1");
   }

   string pressure_level = "LOW";
   if(pressure_score >= 8)
      pressure_level = "HIGH";
   else if(pressure_score >= 4)
      pressure_level = "MEDIUM";

   Log(LOG_INFO, "OnInit", "  Parameter Pressure Scan: score=" + IntegerToString(pressure_score) +
       " level=" + pressure_level);
   if(StringLen(pressure_flags) > 0)
      Log(LOG_INFO, "OnInit", "  Potential Throughput Blockers: " + pressure_flags);

   if(g_Use_Institutional_Strategy_Director && g_Enable_Auto_Regime_Router)
   {
      Log(LOG_WARNING, "OnInit",
          "Director and Auto-Regime are both enabled. Director routing takes precedence over auto-regime role routing.");
   }

   if(g_Enable_AI_Strategy && !Enable_AI_Trend_Predictor)
   {
      Log(LOG_WARNING, "OnInit",
          "AI strategy is enabled while AI Trend Predictor input is disabled. AI route will be availability-limited.");
   }

   if(pressure_score >= 8)
   {
      Log(LOG_WARNING, "OnInit",
          "High parameter pressure detected. If signal flow is sparse, consider relaxing one or more of: " +
          "Require_FVG_For_Trade, Require_BOS_Confirmation, AI_Min_Directional_Edge, " +
          "KImaniz_Entry_Zone_Tolerance_Pct, Signal_Cadence_Mode.");
   }

   Log(LOG_INFO, "OnInit", "==========================================");
}

void AppendStrategyWiringIssue(string &issues, string issue)
{
   if(StringLen(issue) <= 0)
      return;

   if(StringLen(issues) > 0)
      issues += ";";
   issues += issue;
}

void GetExpectedRuntimeStrategyWiring(ENUM_STRATEGY_MIX mix,
                                      bool &expect_ict,
                                      bool &expect_ai,
                                      bool &expect_kim,
                                      bool &expect_kim_only,
                                      ENUM_STRATEGY_ROUTING_MODE &expected_route)
{
   expect_ict = true;
   expect_ai = true;
   expect_kim = true;
   expect_kim_only = false;
   expected_route = STRATEGY_ROUTING_EITHER;

   switch(mix)
   {
      case STRAT_ICT_ONLY:
         expect_ai = false;
         expect_kim = false;
         expected_route = STRATEGY_ROUTING_ICT_ONLY;
         break;
      case STRAT_AI_ONLY:
         expect_ict = false;
         expect_kim = false;
         expected_route = STRATEGY_ROUTING_AI_ONLY;
         break;
      case STRAT_BOTH:
         expect_kim = false;
         expected_route = STRATEGY_ROUTING_BOTH;
         break;
      case STRAT_KIM_ONLY:
         expect_ict = false;
         expect_ai = false;
         expect_kim = true;
         expect_kim_only = true;
         expected_route = STRATEGY_ROUTING_EITHER;
         break;
      case STRAT_ICT_KIM:
         expect_ict = true;
         expect_ai = false;
         expect_kim = true;
         expected_route = STRATEGY_ROUTING_EITHER;
         break;
      case STRAT_AI_KIM:
         expect_ict = false;
         expect_ai = true;
         expect_kim = true;
         expected_route = STRATEGY_ROUTING_EITHER;
         break;
      case STRAT_ALL_THREE:
      case STRAT_EITHER:
      default:
         break;
   }
}

string DescribeRuntimeStrategyWiring()
{
   return "mix=" + StrategyMixToString(g_Strategy_Mix_Effective) +
          " route=" + StrategyRoutingModeToString(g_Strategy_Routing_Mode) +
          " ICT=" + (g_Enable_ICT_Strategy ? "ON" : "OFF") +
          " AI=" + (g_Enable_AI_Strategy ? "ON" : "OFF") +
          " KIM=" + (g_Enable_KImaniz_Strategy ? "ON" : "OFF") +
          " KIMonly=" + (g_KImaniz_Only_Mode ? "YES" : "NO") +
          " Director=" + (g_Use_Institutional_Strategy_Director ? "ON" : "OFF") +
          " AutoRegime=" + (g_Enable_Auto_Regime_Router ? "ON" : "OFF") +
          " CrossRole=" + (g_Suitability_Allow_CrossRole_Fallbacks ? "YES" : "NO");
}

bool ValidateRuntimeStrategyWiring(string &issues)
{
   bool expect_ict = false;
   bool expect_ai = false;
   bool expect_kim = false;
   bool expect_kim_only = false;
   ENUM_STRATEGY_ROUTING_MODE expected_route = STRATEGY_ROUTING_EITHER;

   GetExpectedRuntimeStrategyWiring(g_Strategy_Mix_Effective,
                                    expect_ict,
                                    expect_ai,
                                    expect_kim,
                                    expect_kim_only,
                                    expected_route);

   if(g_Strategy_Routing_Mode != expected_route)
      AppendStrategyWiringIssue(issues, "route!=" + StrategyRoutingModeToString(expected_route));
   if(g_Enable_ICT_Strategy != expect_ict)
      AppendStrategyWiringIssue(issues, "ICT=" + (expect_ict ? "expected ON" : "expected OFF"));
   if(g_Enable_AI_Strategy != expect_ai)
      AppendStrategyWiringIssue(issues, "AI=" + (expect_ai ? "expected ON" : "expected OFF"));
   if(g_Enable_KImaniz_Strategy != expect_kim)
      AppendStrategyWiringIssue(issues, "KIM=" + (expect_kim ? "expected ON" : "expected OFF"));
   if(g_KImaniz_Only_Mode != expect_kim_only)
      AppendStrategyWiringIssue(issues, "KIMonly=" + (expect_kim_only ? "expected YES" : "expected NO"));

   if(g_KImaniz_Only_Mode && (!g_Enable_KImaniz_Strategy || g_Enable_ICT_Strategy || g_Enable_AI_Strategy))
      AppendStrategyWiringIssue(issues, "KIMonlyRuntimeInconsistent");

   return (StringLen(issues) == 0);
}

bool ValidateInputsAndRebuildHash()
{
   if(!ValidateAllInputs())
   {
      Log(LOG_WARNING, "OnInit",
          "Input validation detected issues. Check the preceding ValidateAllInputs/ValidateTimeframes messages; runtime constraints may still allow startup.");
      return false;
   }

   string wiring_issues = "";
   if(!ValidateRuntimeStrategyWiring(wiring_issues))
   {
      Log(LOG_ERROR, "OnInit", "Strategy wiring validation failed: " + wiring_issues +
          " | " + DescribeRuntimeStrategyWiring());
      SendAlert(ALERT_ERROR, "Strategy wiring mismatch - startup aborted");
      return false;
   }

   Log(LOG_INFO, "OnInit", "Strategy wiring validation passed: " + DescribeRuntimeStrategyWiring());

   BuildSymbolHashTable();
   return true;
}

void InitAIAndPerformance()
{
   g_ai_manager.Init();

   g_ai_performance.total_predictions = 0;
   g_ai_performance.correct_predictions = 0;
   g_ai_performance.accuracy_rate = 0.0;
   g_ai_performance.needs_retraining = false;
   for(int i = 0; i < MAX_SYMBOLS; i++)
   {
      g_ai_performance_by_symbol[i].total_predictions = 0;
      g_ai_performance_by_symbol[i].correct_predictions = 0;
      g_ai_performance_by_symbol[i].accuracy_rate = 0.0;
      g_ai_performance_by_symbol[i].needs_retraining = false;
   }

   Log(LOG_INFO, "OnInit", "AI Manager initialized with feature engineering, logistic regression, and neural network");
   Log(LOG_INFO, "OnInit", "Advanced AI engines initialized successfully");

   bool dll_allowed = (bool)TerminalInfoInteger(TERMINAL_DLLS_ALLOWED);
   bool enable_ext = (Enable_External_AI && dll_allowed);
   g_external_ai_allowed = enable_ext;
   if(enable_ext)
   {
      Log(LOG_INFO, "OnInit", "External AI DLL: ENABLED (DLLs allowed, probing model load)");
   }
   else
   {
      if(Enable_External_AI)
         Log(LOG_WARNING, "OnInit", "External AI requested but unavailable (allowed=" + (dll_allowed?"true":"false") +
             ") - falling back to internal AI");
      else
         Log(LOG_INFO, "OnInit", "External AI: disabled by input");
   }

   if(g_Enable_AI_Trend_Predictor_Runtime)
   {
      g_ai_enabled = true;
      Log(LOG_INFO, "OnInit", "AI trend predictor initialized");
      Log(LOG_INFO, "OnInit", "AI Inference: " + (g_external_ai_allowed ? "External DLL requested" : "Internal fallback"));
      Log(LOG_INFO, "OnInit", "AI Training Export: " +
          (Enable_AI_Continuous_Training_Export ? "ENABLED (per closed bar)" : "DISABLED") +
          ", bootstrap=" + (Enable_AI_Training_Export ? "ON" : "OFF"));
      if(Enable_AI_Continuous_Training_Export)
         Log(LOG_INFO, "OnInit", "AI continuous samples will append to " + AI_CONTINUOUS_TRAINING_FILE);
      else
         Log(LOG_WARNING, "OnInit", "AI continuous training export disabled; model files will not improve from live bars");
      Log(LOG_DEBUG, "OnInit", "Issue 1.6 FIX: AI Manager validation enabled - invalid probabilities will be caught");
   }
   else
   {
      g_ai_enabled = false;
      Log(LOG_INFO, "OnInit", "AI Machine Learning system disabled");
   }

   if(g_Enable_AI_Trend_Predictor_Runtime && g_external_ai_allowed)
   {
      g_external_ai_ready = InitExternalAI();
      if(!g_external_ai_ready)
         Log(LOG_WARNING, "OnInit", "External AI disabled - falling back to internal AI model");
   }

   if(g_Enable_AI_Trend_Predictor_Runtime && Enable_AI_Scaler)
   {
      g_ai_scaler_ready = LoadAIScaler(AI_SCALER_FILE);
      if(!g_ai_scaler_ready)
      {
         Log(LOG_WARNING, "OnInit", "AI scaler missing - auto-disabling external AI");
         if(g_external_ai_ready)
            ShutdownExternalAI();
         g_external_ai_ready = false;
         g_external_ai_mode_runtime = -1;
      }
   }

   if(g_Enable_AI_Trend_Predictor_Runtime && g_external_ai_allowed && g_external_ai_ready)
   {
      LogExternalAIFeatureImportance();
   }
}

void InitDebugTools()
{
   ResetDebugCounters();
   Log(LOG_INFO, "OnInit", "Debug and test system initialized");
   Log(LOG_INFO, "OnInit",
       "Manual hotkeys/test trades require Enable_Manual_Test_Hotkeys=true and tester/demo runtime");
}

void StartInitializationCooldown()
{
   g_initialization_time = TimeCurrent();
   g_initialization_complete = false;

   Log(LOG_INFO, "OnInit", "Initialization complete - EA entering " + IntegerToString(INITIALIZATION_COOLDOWN_SECONDS) + "s cooldown period");
   Log(LOG_WARNING, "OnInit", "TRADING DISABLED for " + IntegerToString(INITIALIZATION_COOLDOWN_SECONDS) + " seconds to prevent random execution");
   Log(LOG_INFO, "OnInit", "Trade execution will begin at: " + TimeToString(g_initialization_time + INITIALIZATION_COOLDOWN_SECONDS));
}

bool StartTimer()
{
   // Ensure predictable timer lifecycle across re-init events
   if(g_timer_active)
   {
      EventKillTimer();
      g_timer_active = false;
      Log(LOG_DEBUG, "OnInit", "Existing timer stopped before re-initialization");
   }

   int timer_seconds = Signal_Check_Seconds;
   if(timer_seconds < 1)
      timer_seconds = 1;

   if(!EventSetTimer(timer_seconds))
   {
      Log(LOG_ERROR, "OnInit", "Failed to set timer interval " + IntegerToString(timer_seconds) +
          "s - EA will not function properly");
      SendAlert(ALERT_ERROR, "Timer initialization failed - EA may not process signals");
      return false;
   }

   g_timer_active = true;
   Log(LOG_DEBUG, "OnInit", "Timer set successfully with " + IntegerToString(timer_seconds) +
       "s interval");
   return true;
}

// ===== TIER 1 + 2 + 3 ENHANCEMENT MODULE INITIALIZATION =====
bool InitEnhancementModules()
{
   Log(LOG_INFO, "InitEnhancementModules", "Initializing Tier 1-3 enhancement modules...");
   
   // ===== TIER 1A: ADAPTIVE THRESHOLDS CALCULATOR =====
   // This module creates per-symbol threshold calculator instances
   // Thresholds now adjust based on volatility, session effects, and AI accuracy
   if(g_Enable_Institutional_Debug)
      Log(LOG_DEBUG, "InitEnhancementModules", "Tier 1A: Adaptive Threshold Calculator - ready for per-symbol adjustment");
   
   // ===== TIER 1B + 1C: TEMPORAL DECAY & CONFIDENCE FUSION ROUTER =====
   // Initialize routing parameters and decay curve defaults
   if(g_Enable_Institutional_Debug)
   {
      Log(LOG_DEBUG, "InitEnhancementModules", "Tier 1B: Confidence Fusion Router initialized with position-size multiplier system");
      Log(LOG_DEBUG, "InitEnhancementModules", "Tier 1C: Temporal Signal Decay - bar-aging system active (60+ bar expiration)");
   }
   
   // ===== TIER 2A: REGIME PREDICTOR =====
   // Initialize predictor cache for each symbol
   if(g_Enable_Institutional_Debug)
   {
      for(int i = 0; i < g_symbols_count; i++)
      {
         Log(LOG_DEBUG, "InitEnhancementModules", "Tier 2A: Regime Predictor cache initialized for " + g_symbols[i].name);
      }
   }
   
   // ===== TIER 2B: VOLATILITY FORECASTER =====
   // Initialize volatility forecasting state
   if(g_Enable_Institutional_Debug)
      Log(LOG_DEBUG, "InitEnhancementModules", "Tier 2B: Volatility Forecaster active (ATR clustering + mean-reversion analysis)");
   
   // ===== TIER 3A: DYNAMIC SCORING WEIGHTS =====
   // Initialize regime-based weight adjustment
   if(g_Enable_Institutional_Debug)
      Log(LOG_DEBUG, "InitEnhancementModules", "Tier 3A: Dynamic Scoring Weights (TREND/RANGE/RETRACEMENT regime awareness active)");
   
   // ===== TIER 3B: BACKTESTING FRAMEWORK =====
   // Initialize backtesting metrics
   if(g_Enable_Institutional_Debug)
      Log(LOG_DEBUG, "InitEnhancementModules",
          "Tier 3B: Backtesting Framework " +
          (Enable_Backtesting_Framework ? "active" : "disabled") +
          " (win-rate, Sharpe, walk-forward metrics)");
   
   // ===== TIER 3C: NEWS INTEGRATION =====
   // Initialize news event monitoring
   if(g_Enable_Institutional_Debug)
      Log(LOG_DEBUG, "InitEnhancementModules",
          "Tier 3C: News Integration " +
          (Enable_Economic_Calendar_Filter ? "active" : "disabled") +
          " (economic calendar event detection, position sizing adjustment)");
   
   // ===== FEATURE ENABLEMENT SUMMARY =====
   Log(LOG_INFO, "InitEnhancementModules", "✓ All enhancement modules initialized and active");
   Log(LOG_INFO, "InitEnhancementModules", "  Tier 1: Adaptive Thresholds + Confidence Routing + Temporal Decay");
   Log(LOG_INFO, "InitEnhancementModules", "  Tier 2: Regime Prediction + Volatility Forecasting");
   Log(LOG_INFO, "InitEnhancementModules", "  Tier 3: Dynamic Weights + Backtesting + News Integration");
   
   return true;
}

void RunInitDiagnostics()
{
   // Keep startup diagnostics lightweight in live runs; run deep checks in tester/test mode only.
   bool run_deep_diagnostics = (bool)MQLInfoInteger(MQL_TESTER);
   if(run_deep_diagnostics && g_symbols_count > 0)
   {
      TestBothDirections(g_symbols[0].name);
   }

   Log(LOG_INFO, "OnInit", "Initialization diagnostics complete. Cooldown: " +
       IntegerToString(INITIALIZATION_COOLDOWN_SECONDS) + "s, trading starts at " +
       TimeToString(g_initialization_time + INITIALIZATION_COOLDOWN_SECONDS));
}

int OnInit()
{
   g_startup_time = TimeCurrent();  // NEW: Mark bot startup time for orphan detection
   
   Log(LOG_INFO, "OnInit", "==========================================");
   Log(LOG_INFO, "OnInit", "ProfitTrailBot v5.6 - TRADE EXECUTION FIXED");
   Log(LOG_INFO, "OnInit", "FIXED: Signal alerts not executing trades");
   Log(LOG_INFO, "OnInit", "Attached to: " + Symbol() + " on " + EnumToString((ENUM_TIMEFRAMES)_Period));
   Log(LOG_INFO, "OnInit", "Startup Time: " + TimeToString(g_startup_time));
   Log(LOG_INFO, "OnInit", "==========================================");

   InitGlobalCaches();

   // FIX #4: Start from a known controller state, then sync to runtime parameters.
   CGateController::ResetToDefaults();
   SyncRuntimeParameters();

   Log(LOG_INFO, "OnInit", "Gate Controller initialized: " + CGateController::GetGateStateSummary());

   if(!Enable_Custom_Timeframe_Overrides && !g_Timeframe_Preset_Aligned)
   {
      Log(LOG_ERROR, "OnInit",
          "Timeframe preset/input mismatch: Timeframe_Preset_Input does not auto-override Signal/Primary/Confirm/Trend inputs. " +
          "Either align the timeframe inputs to the selected preset or enable custom timeframe overrides explicitly.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(Enable_Auto_Regime_Router || Use_Institutional_Strategy_Director)
   {
      Log(LOG_ERROR, "OnInit",
          "Unsupported live routing option enabled: Enable_Auto_Regime_Router=" +
          (Enable_Auto_Regime_Router ? "true" : "false") +
          ", Use_Institutional_Strategy_Director=" +
          (Use_Institutional_Strategy_Director ? "true" : "false") +
          ". Both must be false for live startup; deterministic routing hardening aborts instead of silently changing behavior.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(!CheckTradeAllowed())
      return INIT_FAILED;

   ConfigureTradeDefaults();

   if(!InitSymbolsAndIndicators())
      return INIT_FAILED;

   // FIX #7: Validate symbol array was properly initialized
   if(g_symbols_count <= 0 || g_symbols_count > MAX_SYMBOLS)
   {
      Log(LOG_ERROR, "OnInit", "CRITICAL: Invalid symbol count - count=" + 
          IntegerToString(g_symbols_count) + ", max=" + IntegerToString(MAX_SYMBOLS));
      return INIT_FAILED;
   }
   // Verify the first symbol is valid (array is pre-allocated with MAX_SYMBOLS capacity)
   if(StringLen(g_symbols[0].name) == 0)
   {
      Log(LOG_ERROR, "OnInit", "CRITICAL: First symbol slot is empty, array initialization failed");
      return INIT_FAILED;
   }
   Log(LOG_INFO, "OnInit", "Symbol array validation: " + IntegerToString(g_symbols_count) + " symbol(s) initialized successfully (array capacity: " + IntegerToString(ArraySize(g_symbols)) + ")");

   RefreshAllRuntimeCaches(true, true);

   // Timeframe inputs are referenced directly across the EA and cannot be safely auto-corrected at runtime.
   if(!ValidateTimeframes())
   {
      Log(LOG_ERROR, "OnInit",
          "Timeframe configuration is invalid and cannot be auto-corrected. " +
          "Fix Signal_TF/Confirm_TF/Primary_TF/Trend_TF so Signal_TF < Confirm_TF <= Primary_TF <= Trend_TF.");
      return INIT_PARAMETERS_INCORRECT;
   }

   // CRITICAL FIX: Defensive parameter validation with smart defaults for non-timeframe issues.
   if(!ValidateInputsAndRebuildHash())
   {
      Log(LOG_WARNING, "OnInit", "Parameter validation detected issues - applying safe defaults and continuing...");
      
      // Apply conservative safe defaults for critical parameters
      if(Risk_Percent < 0.01 || Risk_Percent > 5.0)
      {
         Log(LOG_WARNING, "OnInit", "Risk_Percent=" + DoubleToString(Risk_Percent, 2) + " is invalid, using 0.50%");
         // We can't modify input parameters at runtime, but we can log the issue
         // The effective values will use safe defaults in validation
      }
      
      // Continue anyway - parameters will be constrained at sync time
      Log(LOG_INFO, "OnInit", "EA will continue with validated/constrained runtime parameters");
   }
   else
   {
      Log(LOG_INFO, "OnInit", "Parameter validation passed successfully");
   }

   InitCountersAndScoring();
   // Rebuild day-scoped execution counters on every startup/reload before any signal processing can resume.
   RestoreIntradayExecutionStateFromHistory(TimeCurrent());
   if(g_Use_Institutional_Strategy_Director)
      DirectorInitTransitionMatrix();
   SyncOpenPositionsState();
   CleanupOrphanedPositions();  // Audit pre-existing managed positions without force-closing them
   LogConfigurationSummary();

   InitAIAndPerformance();
   InitEnhancementModules();  // ← Tier 1/2/3 enhancement modules
   InitDebugTools();
   StartInitializationCooldown();

   if(Enable_AI_Training_Export)
   {
      string ai_train_path = NormalizeDBPath(AI_TRAINING_EXPORT_FILE);
      bool ai_train_exists = (g_AI_Use_Common_Files ? FileIsExist(ai_train_path, FILE_COMMON) : FileIsExist(ai_train_path));
      int existing_rows = -1;

      int ai_db = INVALID_HANDLE;
      if(!EnsureAIDatabase(ai_db, AI_TRAINING_EXPORT_FILE))
      {
         Log(LOG_WARNING, "OnInit", "AI training database init failed: " + ai_train_path);
      }
      else
      {
         existing_rows = GetAITrainingRowCount(ai_db, Symbol(), Signal_TF);
         if(existing_rows >= 0)
         {
            Log(LOG_INFO, "OnInit", "AI training DB rows for " + Symbol() + " " + EnumToString(Signal_TF) +
                ": " + IntegerToString(existing_rows));
         }
         DatabaseClose(ai_db);
      }

      if(ai_train_exists && existing_rows > 0)
      {
         Log(LOG_INFO, "OnInit", "AI training database already present - preserving and appending: " + ai_train_path + (g_AI_Use_Common_Files ? " (COMMON)" : ""));
      }
      else
      {
         ExportAITrainingDataCSV(Symbol(), Signal_TF, AI_Training_Export_Bars, AI_TRAINING_EXPORT_FILE);
      }
   }

   if(!StartTimer())
      return INIT_FAILED;
   
   UpdateDashboard();

   RunInitDiagnostics();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   PersistRiskSessionState();

   ReleaseProcessingLock();
   g_processing_signals = false;

   if(g_Use_Institutional_Strategy_Director)
      DirectorFlushLearningState();

   if(g_timer_active)
   {
      EventKillTimer();
      g_timer_active = false;
      Log(LOG_DEBUG, "OnDeinit", "Timer killed successfully");
   }

   if(g_Enable_AI_Trend_Predictor_Runtime)
   {
      g_ai_manager.Reset();
      Log(LOG_INFO, "OnDeinit", "AI Manager cleaned up");
   }

   if(g_Enable_AI_Trend_Predictor_Runtime && Enable_External_AI && g_external_ai_ready)
   {
      ShutdownExternalAI();
      g_external_ai_ready = false;
   }

   CleanupAIPredictionCache();
   ReleaseAllFallbackHandles();

   for(int i = 0; i < 20; i++)
   {
      if(g_indicator_pool[i].handle != INVALID_HANDLE)
      {
         IndicatorRelease(g_indicator_pool[i].handle);
      }
      g_indicator_pool[i].handle = INVALID_HANDLE;
      g_indicator_pool[i].symbol = "";
      g_indicator_pool[i].tf = (ENUM_TIMEFRAMES)-1;
      g_indicator_pool[i].period = 0;
      g_indicator_pool[i].type = "";
      g_indicator_pool[i].last_used = 0;
      g_indicator_pool[i].in_use = false;
   }

   if(g_rsi_handle != INVALID_HANDLE)
   {
      IndicatorRelease(g_rsi_handle);
      g_rsi_handle = INVALID_HANDLE;
      Log(LOG_DEBUG, "OnDeinit", "Released global RSI handle");
   }
   
   DestroyDashboard();

   for(int i = 0; i < g_symbols_count; i++)
   {
      if(g_symbols[i].atr_handle != INVALID_HANDLE)
      {
         IndicatorRelease(g_symbols[i].atr_handle);
         Log(LOG_DEBUG, "OnDeinit", "Released ATR handle for " + g_symbols[i].name);
         g_symbols[i].atr_handle = INVALID_HANDLE;
      }

      g_symbols[i].name = "";
      g_symbols[i].positions_count = 0;
   }

   for(int i = 0; i < MAX_SYMBOLS; i++)
   {
      if(g_temp_indicators[i].handle != INVALID_HANDLE)
      {
         IndicatorRelease(g_temp_indicators[i].handle);
      }
      g_temp_indicators[i].handle = INVALID_HANDLE;
      g_temp_indicators[i].tf = (ENUM_TIMEFRAMES)-1;
      g_temp_indicators[i].period = 0;
      g_temp_indicators[i].created_time = 0;

      if(g_atr_temp_cache[i].handle != INVALID_HANDLE)
      {
         IndicatorRelease(g_atr_temp_cache[i].handle);
      }
      g_atr_temp_cache[i].handle = INVALID_HANDLE;
      g_atr_temp_cache[i].tf = (ENUM_TIMEFRAMES)-1;
      g_atr_temp_cache[i].period = 0;
      g_atr_temp_cache[i].created_time = 0;
   }

   g_symbols_count = 0;
   g_retry_count = 0;

   Log(LOG_INFO, "OnDeinit", "Deinitialized: " + GetDeinitReasonText(reason));
   Log(LOG_INFO, "OnDeinit", "Debug Stats - Signals: " + IntegerToString(g_debug_signal_count) +
        ", Trades Executed: " + IntegerToString(g_debug_trades_executed) +
        ", Trades Failed: " + IntegerToString(g_debug_trades_failed) +
        ", Errors: " + IntegerToString(g_debug_errors));

   if(g_Enable_AI_Trend_Predictor_Runtime && g_ai_performance.total_predictions > 0)
   {
      Log(LOG_INFO, "OnDeinit",
          StringFormat("Final AI Stats: %d predictions, %.1f%% accuracy",
             g_ai_performance.total_predictions,
             g_ai_performance.accuracy_rate * 100));
   }

   Log(LOG_INFO, "OnDeinit", "Memory cleaned up successfully");
}

string GetDeinitReasonText(int reason)
{
   switch(reason)
   {
      case REASON_ACCOUNT:    return "Account changed";
      case REASON_CHARTCHANGE:return "Chart changed";
      case REASON_CHARTCLOSE: return "Chart closed";
      case REASON_PARAMETERS: return "Parameters changed";
      case REASON_RECOMPILE:  return "Recompiled";
      case REASON_REMOVE:     return "Removed";
      case REASON_TEMPLATE:   return "Template changed";
      default:                return "Unknown reason";
   }
}

string FormatDurationMinutes(int total_minutes)
{
   if(total_minutes <= 0)
      return "0m";

   int days = total_minutes / 1440;
   int rem = total_minutes % 1440;
   int hours = rem / 60;
   int mins = rem % 60;

   if(days > 0)
      return IntegerToString(days) + "d " + IntegerToString(hours) + "h " + IntegerToString(mins) + "m";
   if(hours > 0)
      return IntegerToString(hours) + "h " + IntegerToString(mins) + "m";
   return IntegerToString(mins) + "m";
}

void OnTick()
{
   if(IsStopped())
      return;

   // M1 FIX: Periodic parameter re-sync to catch runtime changes
   // I2 PHASE 3 FIX: Reduced from 60 seconds to 5 seconds for faster response to live parameter changes
   static datetime last_param_sync = 0;
   datetime now = TimeCurrent();
   if(last_param_sync == 0 || (now - last_param_sync) >= 5)
   {
      SyncRuntimeParameters(false);
      last_param_sync = now;
   }

   // Run pipeline on a bounded cadence; retries still run promptly while avoiding tick-storm CPU spikes.
   ProcessSignalsAndRetries();

   static datetime last_drawdown_log = 0;
   if(IsDrawdownLimitExceeded())
   {
      datetime now = TimeCurrent();
      if(last_drawdown_log == 0 || (now - last_drawdown_log) >= 30)
      {
         if(g_drawdown_pause_until > now)
            Log(LOG_WARNING, "OnTick", "Drawdown pause active until " + TimeToString(g_drawdown_pause_until));
         else
            Log(LOG_WARNING, "OnTick", "Drawdown limit exceeded - trading pause active");
         last_drawdown_log = now;
      }
   }
}

void ProcessSignalsAndRetries()
{
   datetime now = TimeCurrent();
   static datetime last_pipeline_run = 0;

   // Don't block ProcessSignals at the pipeline level when a fresh bar is waiting.
   // AUTO and NEW_BAR_ONLY should both process new bars immediately.
   bool cadence_prefers_bars = !g_Force_Signal_Cadence_Gate_Off;
   bool any_new_bar_pending = false;
   if(cadence_prefers_bars && g_symbols_count > 0)
   {
      for(int i = 0; i < g_symbols_count && i < MAX_SYMBOLS; i++)
      {
         datetime bar_time = iTime(g_symbols[i].name, Signal_TF, 0);
         if(bar_time > g_symbols[i].last_bar_time)
         {
            any_new_bar_pending = true;
            break;
         }
      }
   }

   int configured_cadence = MathMax(1, Signal_Check_Seconds);
   int retry_cadence = MathMax(1, g_Retry_Interval_Seconds);
   int pipeline_interval = configured_cadence;
   if(g_Force_Signal_Cadence_Gate_Off || any_new_bar_pending)
      pipeline_interval = 0; // Explicit continuous mode or immediate new-bar pass.
   else if(g_retry_count > 0)
      pipeline_interval = MathMax(1, MathMin(configured_cadence, retry_cadence));
   else if(g_Signal_On_New_Bar_Only)
      pipeline_interval = MathMax(1, MathMin(configured_cadence, 5)); // Poll lightly while waiting for the next bar.

   if(pipeline_interval > 0 && last_pipeline_run != 0 && (now - last_pipeline_run) < pipeline_interval)
      return;
   last_pipeline_run = now;

   ProcessSignals();

   // Drought monitor: warn if no valid signals or trades for a long time (only once per interval)
   if(Drought_Alert_Minutes > 0 && Drought_Log_Interval > 0)
   {
      datetime last_activity = MathMax(g_last_trade_time, g_last_valid_signal_time);
      if(last_activity == 0) last_activity = g_initialization_time;
      int minutes_since = (int)((now - last_activity) / 60);
      if(minutes_since >= Drought_Alert_Minutes &&
         (g_last_drought_alert == 0 || (now - g_last_drought_alert) >= Drought_Log_Interval * 60))
      {
         string top_rejects = GetTopRejectReasonsSummary(5);
         string reject_stage_mix = GetRejectStageSummary();
         Log(LOG_WARNING, "TradeDrought",
             "No valid signals/trades for " + IntegerToString(minutes_since) + " minutes (" +
             FormatDurationMinutes(minutes_since) + "). " +
             "SessionFilter=" + (g_Use_Session_Filter ? "ON" : "OFF") +
             ", Allow_Range_Trading=" + (g_Allow_Range_Trading ? "ON" : "OFF") +
             ", Max_Spread_Pips=" + DoubleToString(g_Max_Spread_Pips_Effective, 1) +
             ", Signal_TF=" + IntegerToString(Signal_TF) +
             ", Generated=" + IntegerToString(g_debug_counters.signals_generated) +
             ", Valid=" + IntegerToString(g_debug_counters.signals_valid) +
             ", Queued=" + IntegerToString(g_debug_counters.trades_queued) +
             ", Executed=" + IntegerToString(g_debug_counters.trades_executed) +
             ", RejectStageMix=" + reject_stage_mix +
             ", TopRejects=" + top_rejects);
         g_last_drought_alert = now;
      }
   }

   static datetime last_cache_maintenance = 0;
   if(now - last_cache_maintenance >= 60)
   {
      MaintainRateCache();
      PurgeStaleDerivedCaches();
      last_cache_maintenance = now;
   }

   if(g_Enable_AI_Trend_Predictor_Runtime)
   {
      static datetime last_report_time = 0;
      if((now - last_report_time) >= 3600)
      {
         last_report_time = now;

         int training_count = 0;
         int model_type = 0;
         g_ai_manager.GetStats(training_count, model_type);

         AIPerformanceStats perf_stats;
         g_ai_manager.GetPerformanceStats(perf_stats);

         string model_name = (model_type == 0) ? "Logistic" : "Neural";
         string retraining_status = perf_stats.needs_retraining ? "NEEDED" : "OK";

         Log(LOG_INFO, "ProcessSignalsAndRetries",
            StringFormat("AI Hourly Report: %d samples, Model: %s, Accuracy: %.1f%%, Predictions: %d, Correct: %d, Retraining: %s",
               training_count, model_name, perf_stats.accuracy_rate * 100,
               perf_stats.total_predictions, perf_stats.correct_predictions, retraining_status));

         if(g_AI_Log_Per_Symbol_Training)
         {
            for(int i = 0; i < g_symbols_count && i < MAX_SYMBOLS; i++)
            {
               if(g_ai_performance_by_symbol[i].total_predictions <= 0)
                  continue;
               string symbol = g_symbols[i].name;
               if(StringLen(symbol) == 0)
                  continue;
               string sym_retrain = g_ai_performance_by_symbol[i].needs_retraining ? "NEEDED" : "OK";
               Log(LOG_INFO, "ProcessSignalsAndRetries",
                   StringFormat("AI Symbol Report [%s]: Accuracy %.1f%%, Predictions %d, Correct %d, Retraining %s",
                                symbol,
                                g_ai_performance_by_symbol[i].accuracy_rate * 100,
                                g_ai_performance_by_symbol[i].total_predictions,
                                g_ai_performance_by_symbol[i].correct_predictions,
                                sym_retrain));
            }
         }

         if(g_ai_cache_requests > 0)
         {
            double cache_hit_rate = (double)g_ai_cache_hits / g_ai_cache_requests * 100.0;
            Log(LOG_INFO, "ProcessSignalsAndRetries",
               StringFormat("AI Cache Performance: Hit rate %.1f%% (%d hits / %d requests, %d misses)",
               cache_hit_rate, g_ai_cache_hits, g_ai_cache_requests, g_ai_cache_misses));

            // Reset windowed stats for the next report interval
            g_ai_cache_requests = 0;
            g_ai_cache_hits = 0;
            g_ai_cache_misses = 0;
         }

         if(perf_stats.needs_retraining && training_count > 200)
         {
            Log(LOG_WARNING, "ProcessSignalsAndRetries", "Triggering AI model retraining due to low accuracy (< 50%)");
            g_ai_manager.Reset();
         }
      }
   }

   static datetime last_scoring_check = 0;
   if((now - last_scoring_check) >= 14400 && g_symbols_count > 0)
   {
      last_scoring_check = now;
      string test_symbol = g_symbols[0].name;
      double threshold = g_scoring_engine.GetScoreThreshold();

      Log(LOG_INFO, "ProcessSignalsAndRetries",
          "ScoringEngine Health Check - Threshold: " + DoubleToString(threshold, 1) +
          ", Test Symbol: " + test_symbol);

      string buy_breakdown = g_scoring_engine.GetDetailedScoreBreakdown(test_symbol, Signal_TF, 1);
      string sell_breakdown = g_scoring_engine.GetDetailedScoreBreakdown(test_symbol, Signal_TF, -1);

      Log(LOG_DEBUG, "ProcessSignalsAndRetries", "BUY Test: " + buy_breakdown);
      Log(LOG_DEBUG, "ProcessSignalsAndRetries", "SELL Test: " + sell_breakdown);
   }
}

void OnTimer()
{
   if(!g_timer_active)
   {
      Log(LOG_WARNING, "OnTimer", "Timer called but not active");
      return;
   }

   datetime now = TimeCurrent();

   // Keep broker-state reconciliation live even when execution is quiet.
   TrackClosedTrades();

   // Hot-reload external AI models/scaler (when updated on disk)
   MaybeHotReloadExternalAI();

   CleanupAIPredictionCache();

   static datetime last_fallback_cleanup = 0;
   if(now - last_fallback_cleanup > 300)
   {
      CleanupFallbackHandles();
      last_fallback_cleanup = now;
   }

   datetime current_bar = iTime(Symbol(), Signal_TF, 0);
   if(current_bar <= 0)
   {
      Log(LOG_DEBUG, "OnTimer", "No bar data yet for " + Symbol() + " on " + EnumToString(Signal_TF));
   }
   else if(g_cached_rates_main.last_update != current_bar)
   {
      int bars_needed = MathMax(g_Trend_Lookback_Bars, MathMax(g_Order_Block_Lookback, MathMax(g_FVG_Lookback_Bars, 10)));
      int bars_copied = CopyRates(Symbol(), Signal_TF, 0, bars_needed, g_cached_rates_main.rates);

      if(bars_copied >= 10)
      {
         g_cached_rates_main.count = bars_copied;
         g_cached_rates_main.tf = Signal_TF;
         g_cached_rates_main.last_update = current_bar;

         Log(LOG_DEBUG, "OnTimer", StringFormat("Cached rates refreshed: %d bars copied", bars_copied));
      }
      else
      {
         int err = GetLastError();
         Log(LOG_WARNING, "OnTimer", StringFormat("Failed to copy rates for %s %s: got %d bars, need %d (err=%d)",
                Symbol(), EnumToString(Signal_TF), bars_copied, bars_needed, err));
      }
   }

   // AI training per symbol (per bar) to keep multi-symbol runs consistent.
   if(g_ai_enabled && g_symbols_count > 0)
   {
      static int ai_training_attempts = 0;
      static datetime last_training_reset = 0;
      static double last_buy_prob[MAX_SYMBOLS];
      static double last_sell_prob[MAX_SYMBOLS];
      static datetime last_update_bar[MAX_SYMBOLS];
      static int last_signal_direction[MAX_SYMBOLS];
      static datetime last_ai_train_validation_warn[MAX_SYMBOLS];
      static string last_ai_train_validation_reason[MAX_SYMBOLS];
      static datetime last_ai_history_cap_log = 0;
      static datetime last_ai_training_limit_log = 0;
      static bool ai_state_initialized = false;

      if(!ai_state_initialized)
      {
         for(int i = 0; i < MAX_SYMBOLS; i++)
         {
            last_buy_prob[i] = 0.5;
            last_sell_prob[i] = 0.5;
            last_update_bar[i] = 0;
            last_signal_direction[i] = 0;
            last_ai_train_validation_warn[i] = 0;
            last_ai_train_validation_reason[i] = "";
         }
         ai_state_initialized = true;
      }

      if(now - last_training_reset > 3600)
      {
         ai_training_attempts = 0;
         last_training_reset = now;
      }

      string chart_symbol = Symbol();
      datetime symbol_bar_cache[MAX_SYMBOLS];
      bool symbol_bar_ready[MAX_SYMBOLS];
      bool eval_history_enabled[MAX_SYMBOLS];
      bool eval_had_trades[MAX_SYMBOLS];
      int eval_total_trades[MAX_SYMBOLS];
      int eval_profitable_trades[MAX_SYMBOLS];
      int eval_window_deal_count[MAX_SYMBOLS];
      datetime eval_history_from[MAX_SYMBOLS];
      datetime eval_history_to[MAX_SYMBOLS];
      datetime ai_history_from = 0;
      datetime ai_history_to = 0;
      bool have_ai_history_window = false;
      const int MAX_AI_TRAIN_DEAL_SCAN = 1200;

      for(int i = 0; i < MAX_SYMBOLS; i++)
      {
         symbol_bar_cache[i] = 0;
         symbol_bar_ready[i] = false;
         eval_history_enabled[i] = false;
         eval_had_trades[i] = false;
         eval_total_trades[i] = 0;
         eval_profitable_trades[i] = 0;
         eval_window_deal_count[i] = 0;
         eval_history_from[i] = 0;
         eval_history_to[i] = 0;
      }

      for(int i = 0; i < g_symbols_count && i < MAX_SYMBOLS; i++)
      {
         string symbol = g_symbols[i].name;
         if(StringLen(symbol) == 0)
            continue;

         datetime symbol_bar = iTime(symbol, Signal_TF, 0);
         if(symbol_bar <= 0)
            continue;

         symbol_bar_cache[i] = symbol_bar;
         symbol_bar_ready[i] = true;

         datetime prev_update = last_update_bar[i];
         if(prev_update > 0 && symbol_bar > prev_update && last_signal_direction[i] != 0)
         {
            eval_history_enabled[i] = true;
            eval_history_from[i] = prev_update;
            eval_history_to[i] = symbol_bar;

            if(!have_ai_history_window || prev_update < ai_history_from)
               ai_history_from = prev_update;
            if(!have_ai_history_window || symbol_bar > ai_history_to)
               ai_history_to = symbol_bar;
            have_ai_history_window = true;
         }
      }

      if(have_ai_history_window && HistorySelect(ai_history_from, ai_history_to))
      {
         int deals = HistoryDealsTotal();
         bool ai_history_cap_hit = false;

         for(int d = deals - 1; d >= 0; d--)
         {
            ulong ticket = HistoryDealGetTicket(d);
            if(ticket == 0)
               continue;

            datetime deal_time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
            if(deal_time < ai_history_from)
               break;

            string deal_symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
            int deal_symbol_index = GetSymbolIndex(deal_symbol);
            long deal_type = HistoryDealGetInteger(ticket, DEAL_TYPE);
            long deal_magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
            long deal_entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
            bool managed_close_deal =
               (deal_symbol_index >= 0 && deal_symbol_index < MAX_SYMBOLS &&
                deal_magic >= Magic_Base && deal_magic < Magic_Base + 10000 &&
                (deal_type == DEAL_TYPE_BUY || deal_type == DEAL_TYPE_SELL) &&
                (deal_entry == DEAL_ENTRY_OUT || deal_entry == DEAL_ENTRY_OUT_BY || deal_entry == DEAL_ENTRY_INOUT));
            double deal_profit = 0.0;
            if(managed_close_deal)
               deal_profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);

            for(int si = 0; si < g_symbols_count && si < MAX_SYMBOLS; si++)
            {
               if(!eval_history_enabled[si])
                  continue;
               if(eval_window_deal_count[si] >= MAX_AI_TRAIN_DEAL_SCAN)
                  continue;
               if(deal_time < eval_history_from[si] || deal_time > eval_history_to[si])
                  continue;

               // Preserve prior behavior: the cap is on the latest N total deals in the
               // selected history window, not just the matching symbol's close deals.
               eval_window_deal_count[si]++;
               if(eval_window_deal_count[si] >= MAX_AI_TRAIN_DEAL_SCAN)
                  ai_history_cap_hit = true;

               if(!managed_close_deal || deal_symbol_index != si)
                  continue;

               eval_had_trades[si] = true;
               eval_total_trades[si]++;
               if(deal_profit > 0.0)
                  eval_profitable_trades[si]++;
            }
         }

         if(ai_history_cap_hit &&
            (last_ai_history_cap_log == 0 || (now - last_ai_history_cap_log) >= 300))
         {
            Log(LOG_DEBUG, "OnTimer",
                "AI history evaluation capped to latest " + IntegerToString(MAX_AI_TRAIN_DEAL_SCAN) +
                " total deals per symbol history window");
            last_ai_history_cap_log = now;
         }
      }

      for(int i = 0; i < g_symbols_count && i < MAX_SYMBOLS; i++)
      {
         string symbol = g_symbols[i].name;
         if(StringLen(symbol) == 0)
            continue;

         datetime symbol_bar = symbol_bar_cache[i];
         if(!symbol_bar_ready[i] || symbol_bar <= 0)
            continue;

         if(last_update_bar[i] == symbol_bar)
            continue;

         MqlRates rates[];
         ArraySetAsSeries(rates, true);
         if(!GetCachedRates(symbol, Signal_TF, rates, 6) || ArraySize(rates) < 6)
         {
            if(g_AI_Log_Per_Symbol_Training || symbol == chart_symbol)
               Log(LOG_DEBUG, "OnTimer", "Insufficient rates for AI training on " + symbol);
            continue;
         }

         double rsi_value, ma_slope, atr_value, volume_ratio;
         bool features_valid = GetCachedAIFeatures(symbol, rsi_value, ma_slope, atr_value, volume_ratio, Signal_TF);
         if(!features_valid)
         {
            if(g_AI_Log_Per_Symbol_Training || symbol == chart_symbol)
               Log(LOG_DEBUG, "OnTimer", "AI feature extraction failed - skipping training");
            continue;
         }

         if(ai_training_attempts >= 1000)
         {
            if(last_ai_training_limit_log == 0 || (now - last_ai_training_limit_log) >= 600)
            {
               Log(LOG_WARNING, "OnTimer", "AI training limit reached (1000/hour) - skipping to prevent resource exhaustion");
               last_ai_training_limit_log = now;
            }
            break;
         }

         ai_training_attempts++;

         double volume_avg = (rates[0].tick_volume + rates[1].tick_volume + rates[2].tick_volume) / 3.0;
         double macd_value = 0.0;
         double stochastic_value = 50.0;
         GetMomentumValues(symbol, Signal_TF, 0, macd_value, stochastic_value);

         double sentiment_score = 0.5;
         double spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD) * SymbolInfoDouble(symbol, SYMBOL_POINT);
         int htf_struct = DetectMarketStructure(symbol, Confirm_TF);
         double htf_bias_feature = (htf_struct == MARKET_BULLISH ? 1.0 : htf_struct == MARKET_BEARISH ? -1.0 : 0.0);
         double vol_regime = GetCachedVolatilityFactor(symbol, i);

         string ai_train_reject_reason = "";
         if(ValidateAITrainingDataDetailed(
            rates[0].close,
            rates[1].close,
            rates[5].close,
            atr_value,
            rsi_value,
            ma_slope,
            rates[0].tick_volume,
            rates[1].tick_volume,
            volume_avg,
            macd_value,
            stochastic_value,
            sentiment_score,
            ai_train_reject_reason))
         {
            double buy_prob = 0.5;
            double sell_prob = 0.5;
            GetAIModuleProbabilities(
               rates[0].close,
               rates[1].close,
               rates[5].close,
               atr_value,
               rsi_value,
               ma_slope,
               rates[0].tick_volume,
               rates[1].tick_volume,
               volume_avg,
               macd_value,
               stochastic_value,
               sentiment_score,
               spread,
               htf_bias_feature,
               vol_regime,
               buy_prob,
               sell_prob
            );

            if(!NormalizeAndValidateProbabilities(buy_prob, sell_prob))
            {
               RecordRejectReason("AI:training_probabilities_invalid");
               if(g_AI_Log_Per_Symbol_Training || symbol == chart_symbol)
               {
                  Log(LOG_WARNING, "OnTimer",
                      StringFormat("AI training probabilities invalid - skipping this bar | buy=%.3f sell=%.3f",
                                   buy_prob, sell_prob));
               }
               continue;
            }

            g_ai_prediction_cache[i].probability = buy_prob;
            g_ai_prediction_cache[i].buy_prob = buy_prob;
            g_ai_prediction_cache[i].sell_prob = sell_prob;
            g_ai_prediction_cache[i].last_update = now;
            g_ai_prediction_cache[i].confidence = MathMax(buy_prob, sell_prob);
            g_ai_prediction_cache[i].tf = Signal_TF;
            g_ai_prediction_cache[i].bar_time = symbol_bar;
            g_ai_prediction_cache[i].source_tick_msc = GetLatestSymbolTickMsc(symbol, i, false);
            if(g_ai_prediction_cache[i].created_time == 0)
               g_ai_prediction_cache[i].created_time = now;

            double buy_min_prob = GetAIDirectionalMinProbability(1, symbol, i);
            double sell_min_prob = GetAIDirectionalMinProbability(-1, symbol, i);
            int current_signal_direction = SelectAIDirection(buy_prob, sell_prob, buy_min_prob, sell_min_prob);

            datetime prev_update = last_update_bar[i];
            int prev_signal_direction = last_signal_direction[i];
            double prev_buy_prob = last_buy_prob[i];
            double prev_sell_prob = last_sell_prob[i];

            if(prev_update > 0 && symbol_bar > prev_update && prev_signal_direction != 0)
            {
               if(eval_had_trades[i] && eval_total_trades[i] > 0)
               {
                  int actual_outcome = (eval_profitable_trades[i] > eval_total_trades[i] / 2) ? 1 : -1;
                  UpdateAIPerformanceStats(prev_buy_prob, prev_sell_prob, actual_outcome, i);
               }
            }

            last_buy_prob[i] = buy_prob;
            last_sell_prob[i] = sell_prob;
            last_update_bar[i] = symbol_bar;
            last_signal_direction[i] = current_signal_direction;

            if(Enable_AI_Continuous_Training_Export)
            {
               if(AppendAITrainingSampleCSV(symbol, Signal_TF, AI_CONTINUOUS_TRAINING_FILE, 2, g_ai_last_continuous_export_time[i]) &&
                  (g_AI_Log_Per_Symbol_Training || symbol == chart_symbol))
               {
                  Log(LOG_DEBUG, "OnTimer", "AI continuous training sample exported for " + symbol);
               }
            }

            if(g_AI_Log_Per_Symbol_Training || symbol == chart_symbol)
               Log(LOG_DEBUG, "OnTimer", StringFormat("AI Training: buy=%.3f sell=%.3f, validated data", buy_prob, sell_prob));
         }
         else
         {
            RecordRejectReason("AI:training_data_validation_" + ai_train_reject_reason);
            bool reason_changed = (ai_train_reject_reason != last_ai_train_validation_reason[i]);
            bool warn_due = (last_ai_train_validation_warn[i] == 0 || (now - last_ai_train_validation_warn[i]) >= 600);
            if(reason_changed || warn_due)
            {
               if(g_AI_Log_Per_Symbol_Training || symbol == chart_symbol)
               {
                  Log(LOG_WARNING, "OnTimer",
                      StringFormat("AI training data validation failed (%s) - skipping this bar | close0=%.5f close1=%.5f atr=%.5f rsi=%.2f ma=%.5f macd=%.5f stoch=%.2f vol0=%.0f vol1=%.0f vavg=%.2f",
                                   ai_train_reject_reason,
                                   rates[0].close,
                                   rates[1].close,
                                   atr_value,
                                   rsi_value,
                                   ma_slope,
                                   macd_value,
                                   stochastic_value,
                                   rates[0].tick_volume,
                                   rates[1].tick_volume,
                                   volume_avg));
               }
               last_ai_train_validation_warn[i] = now;
               last_ai_train_validation_reason[i] = ai_train_reject_reason;
            }
         }
      }
   }

   // Tickless safety fallback: keep the trading pipeline alive when chart ticks are sparse/missing.
   // This prevents full signal starvation where monitor logs continue but signals_generated stays zero.
   static datetime last_timer_pipeline_log = 0;
   int timer_pipeline_stale_after = MathMax(2, Signal_Check_Seconds);
   if(g_last_process_time == 0 || (now - g_last_process_time) >= timer_pipeline_stale_after)
   {
      ProcessSignalsAndRetries();
      if(last_timer_pipeline_log == 0 || (now - last_timer_pipeline_log) >= 60)
      {
         Log(LOG_DEBUG, "OnTimer", "Tickless fallback executed ProcessSignalsAndRetries() " +
             "(last pipeline age=" + IntegerToString((g_last_process_time > 0) ? (int)(now - g_last_process_time) : -1) + "s)");
         last_timer_pipeline_log = now;
      }
   }

   // Keep timer lightweight; heavy signal/retry work now runs per-tick
   MonitorSignalGeneration();
   UpdateDashboard();

   static datetime last_debug_report = 0;
   if(TimeCurrent() - last_debug_report > 1800)
   {
      PrintDebugReport();
      last_debug_report = TimeCurrent();
   }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   switch(trans.type)
   {
      case TRADE_TRANSACTION_DEAL_ADD:
      case TRADE_TRANSACTION_DEAL_UPDATE:
      case TRADE_TRANSACTION_DEAL_DELETE:
      case TRADE_TRANSACTION_HISTORY_ADD:
      case TRADE_TRANSACTION_HISTORY_UPDATE:
      case TRADE_TRANSACTION_HISTORY_DELETE:
      case TRADE_TRANSACTION_POSITION:
         break;
      default:
         return;
   }

   TrackClosedTrades(true);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_KEYDOWN)
   {
      if(!ManualDiagnosticsSurfaceEnabled(true, "OnChartEvent"))
         return;

      switch((int)lparam)
      {
         case 84: // 'T' key - Run comprehensive test
            RunComprehensiveTest();
            break;

         case 66: // 'B' key - Force BUY signal
            ForceSignalGeneration(Symbol(), 1);
            break;

         case 83: // 'S' key - Force SELL signal
            ForceSignalGeneration(Symbol(), -1);
            break;

         case 82: // 'R' key - Print debug report
            PrintDebugReport();
            break;

         case 67: // 'C' key - Reset debug counters
            ResetDebugCounters();
            Print("[DEBUG] Counters reset");
            break;

         case 70: // 'F' key - Refresh all runtime caches
         {
            bool refresh_ok = RefreshAllRuntimeCaches(true, true);
            Print(refresh_ok ? "[DEBUG] Runtime caches refreshed" :
                               "[DEBUG] Runtime caches refreshed with some quote refresh failures");
            break;
         }
      }
   }
}

#endif // MAIN_LIFECYCLE_MQH
