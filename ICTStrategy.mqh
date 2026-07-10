#ifndef ICT_STRATEGY_MQH
#define ICT_STRATEGY_MQH

STradingSignal GenerateICTSignal(string symbol, bool allow_range_mode,
                                 bool has_seeded_trend_direction = false,
                                 int seeded_trend_direction = 0)
{
   STradingSignal signal;
   signal.origin = SIGNAL_ORIGIN_ICT;
   g_debug_counters.signals_generated++;

   if(g_debug_signals_enabled)
      Log(LOG_DEBUG, "GenerateICTSignal", "Generating signal for " + symbol + " (Total: " + IntegerToString(g_debug_counters.signals_generated) + ")");

   int symbol_index = -1;
   if(!RunCommonSignalPrechecks(symbol, signal, symbol_index, true, true, allow_range_mode,
                                has_seeded_trend_direction, seeded_trend_direction))
      return signal;
   
   // Use centralized logging
   LogTradeMessage(LOG_INFO, "GenerateTradingSignal", symbol, "Starting signal generation");
   
   // Direction is seeded from HTF bias here, then finalized by the shared Trend_TF->Primary_TF->Confirm_TF->entry funnel.
   int htf_bias = ResolveHTFBiasForSignalPass(symbol,
                                              has_seeded_trend_direction,
                                              seeded_trend_direction);
   int htf_bias_score = (int)GetHTFBiasStrengthInstitutional(symbol);
   int signal_tf_structure = DetectMarketStructure(symbol, Signal_TF);
   int primary_tf_structure = DetectMarketStructure(symbol, Primary_TF);
   int resolved_direction = htf_bias;
   string direction_note = "";
   
   // DEBUG: Log HTF bias analysis
   if(g_debug_signals_enabled)
   {
      int confirm_structure = DetectMarketStructure(symbol, Confirm_TF);
      int trend_structure = DetectMarketStructure(symbol, Trend_TF);
      string htf_bias_text = (htf_bias == 1 ? "BULLISH" : htf_bias == -1 ? "BEARISH" : "NEUTRAL");
      Print("[DEBUG] HTF STRUCTURE SNAPSHOT for ", symbol,
            " - Primary(", EnumToString(Primary_TF), "):", MarketStructureToString(primary_tf_structure),
            " | Confirm(", EnumToString(Confirm_TF), "):", MarketStructureToString(confirm_structure),
            " | Trend(", EnumToString(Trend_TF), "):", MarketStructureToString(trend_structure),
            " | InstitutionalBias:", htf_bias_text);
   }
   
   if(htf_bias == 0)
   {
      bool allow_neutral_ict = (g_Disable_All_Gates || allow_range_mode || g_Allow_Neutral_Trend_Trading);
      int fallback_direction = StructureToDirection(signal_tf_structure);
      if(fallback_direction == 0)
         fallback_direction = StructureToDirection(primary_tf_structure);
      if(fallback_direction == 0 && has_seeded_trend_direction)
         fallback_direction = seeded_trend_direction;

      if(!allow_neutral_ict || fallback_direction == 0)
      {
         signal.reason = (allow_neutral_ict ?
                          "Calculated trend neutral and no lower-timeframe directional fallback" :
                          "Calculated trend neutral - trading blocked");
         LogTradeMessage(LOG_INFO, "GenerateTradingSignal", symbol, signal.reason);
         return signal;
      }

      htf_bias = fallback_direction;
      resolved_direction = fallback_direction;
      direction_note = "Neutral HTF fallback via " +
                       (StructureToDirection(signal_tf_structure) != 0 ? "Signal_TF" :
                        StructureToDirection(primary_tf_structure) != 0 ? "Primary_TF" : "seeded trend");
      Log(LOG_INFO, "GenerateTradingSignal",
          symbol + " - Neutral HTF bias allowed; using " +
          (fallback_direction == 1 ? "BUY" : "SELL") + " fallback direction");
   }
   
   // Confluence check with optional strict forward-continuation enforcement.
   if(g_Enable_Confluence_Check)
   {
      bool forward_signal_aligned =
         ((htf_bias == 1 && signal_tf_structure == MARKET_BULLISH) ||
          (htf_bias == -1 && signal_tf_structure == MARKET_BEARISH));
      bool forward_signal_opposes =
         ((htf_bias == 1 && signal_tf_structure == MARKET_BEARISH) ||
          (htf_bias == -1 && signal_tf_structure == MARKET_BULLISH));

      // Forward-only should block explicit counter-trend structure; neutral/ranging signal TF is allowed.
      if(g_ICT_Forward_Trend_Only && forward_signal_opposes)
      {
         signal.reason = "Forward-only gate: Signal_TF not aligned with calculated trend direction";
         LogTradeMessage(LOG_INFO, "GenerateTradingSignal", symbol, signal.reason);
         return signal;
      }

      if(g_ICT_Forward_Trend_Only && !forward_signal_aligned && !forward_signal_opposes)
      {
         Log(LOG_DEBUG, "GenerateTradingSignal",
             symbol + " - Forward-only soft pass: Signal_TF is " + MarketStructureToString(signal_tf_structure) +
             " while calculated bias is " + (htf_bias == 1 ? "BULLISH" : "BEARISH"));
      }
      
      // Only block trades if there's strong opposing confluence across multiple timeframes
      bool strong_opposing_confluence = false;
      int confluence_enforce_threshold = (g_Enable_Soft_Structural_Gating ? 6 : 5);
      bool enforce_confluence = (MathAbs(htf_bias_score) >= confluence_enforce_threshold);
      
      if(enforce_confluence && htf_bias == 1) // HTF Bullish
      {
         // Only block if both Signal TF AND Primary TF are strongly bearish
         if(signal_tf_structure == MARKET_BEARISH && primary_tf_structure == MARKET_BEARISH)
         {
            strong_opposing_confluence = true;
            signal.reason = "Strong bearish confluence on lower TFs against bullish HTF - too risky";
         }
      }
      else if(enforce_confluence && htf_bias == -1) // HTF Bearish
      {
         // Only block if both Signal TF AND Primary TF are strongly bullish
         if(signal_tf_structure == MARKET_BULLISH && primary_tf_structure == MARKET_BULLISH)
         {
            strong_opposing_confluence = true;
            signal.reason = "Strong bullish confluence on lower TFs against bearish HTF - too risky";
         }
      }
      
      if(strong_opposing_confluence)
      {
         LogTradeMessage(LOG_INFO, "GenerateTradingSignal", symbol, signal.reason);
         return signal;
      }
      
      // Log confluence status for debugging
      string htf_bias_text = (htf_bias == 1 ? "BULLISH" : htf_bias == -1 ? "BEARISH" : "NEUTRAL");
      Log(LOG_DEBUG, "GenerateTradingSignal", symbol + " - Confluence Check: HTF=" + htf_bias_text + 
          ", Signal TF=" + MarketStructureToString(signal_tf_structure) + 
          ", Primary TF=" + MarketStructureToString(primary_tf_structure) + 
          ", HTF Score=" + IntegerToString(htf_bias_score) + " - " + (enforce_confluence ? "ENFORCED" : "SKIPPED"));
   }
   else
   {
      Log(LOG_DEBUG, "GenerateTradingSignal", symbol + " - Confluence check disabled - proceeding with HTF bias: " + IntegerToString(htf_bias));
   }
   
   // Pre-compute ATR once per signal for reuse (scoring logs, AI features, SL/TP)
   double atr_value = GetATRValue(symbol, Signal_TF);
   double ai_prob_for_scoring = 0.0;
   double mid_price = GetCachedMidPrice(symbol, symbol_index);
   int sig_struct_cache = signal_tf_structure;

   // Use ScoringEngine instead of simple filter
   if(Enable_All_Institutional_Filters)
   {
      // Verify ScoringEngine is properly initialized
      if(g_scoring_engine.GetScoreThreshold() <= 0)
      {
         signal.reason = "ScoringEngine not properly initialized";
         LogTradeMessage(LOG_ERROR, "GenerateTradingSignal", symbol, signal.reason);
         return signal;
      }
      
       // FIX 1: Calculate AI confidence for ScoringEngine integration
       double ai_confidence = 0.0;
       if(g_Enable_AI_Trend_Predictor_Runtime && g_ai_enabled)
       {
          // Get cached AI prediction if fresh for the signal timeframe
          if(IsAIPredictionFresh(symbol_index, Signal_TF))
          {
             // Enhancement: Additional freshness check to prevent stale predictions
             if(IsAIPredictionCacheStale(symbol_index, 60))
             {
                RecordAICacheAccess(symbol_index, false);
                // Cache is stale, fall through to live calculation
             }
             else
             {
                RecordAICacheAccess(symbol_index, true);
                double cached_buy_prob = ClampUnitProbability(g_ai_prediction_cache[symbol_index].buy_prob);
                double cached_sell_prob = ClampUnitProbability(g_ai_prediction_cache[symbol_index].sell_prob);
                ai_prob_for_scoring = GetEffectiveDirectionalAIProbability(resolved_direction, cached_buy_prob, cached_sell_prob);
                ai_confidence = ai_prob_for_scoring;
                signal.ai_probability = GetRawDirectionalAIProbability(resolved_direction, cached_buy_prob, cached_sell_prob);
                signal.ai_confidence = ai_confidence;
             }
          }
          else
          {
             RecordAICacheAccess(symbol_index, false);
            // ATR already precomputed above; reuse for AI features
            
            // Use cached AI features for efficiency
            double rsi_val = 50, ma_slope_val = 0, atr_val = atr_value, vol_ratio = 1.0;
            bool cached_ok = GetCachedAIFeatures(symbol, rsi_val, ma_slope_val, atr_val, vol_ratio, Signal_TF);
            
            // Get rates for close prices
            double close0 = SymbolInfoDouble(symbol, SYMBOL_BID);
            double close1 = 0, close5 = 0;
            double vol0 = 0, vol1 = 0;
            MqlRates rates[];
            
            if(GetCachedRates(symbol, Signal_TF, rates, 5) && ArraySize(rates) >= 5)
            {
               close1 = rates[1].close;
               close5 = rates[4].close;
               vol0 = (double)rates[0].tick_volume;
               vol1 = (double)rates[1].tick_volume;
            }
            
            // FIXED: Validate that we have valid prices before AI processing
            if(close0 <= 0 || close1 <= 0)
            {
               Log(LOG_WARNING, "GenerateTradingSignal", symbol + " - Invalid prices for AI: close0=" + 
                   DoubleToString(close0, 5) + ", close1=" + DoubleToString(close1, 5));
               ai_confidence = 0.0;
               signal.ai_probability = 0.5;
               signal.ai_confidence = 0.0;
               signal.ai_agrees = false;
            }
            else
            {
               double vol_avg = (vol0 + vol1 > 0) ? (vol0 + vol1) / 2.0 : 1.0;
               
               double macd_value = 0.0;
               double stoch_value = 50.0;
               GetMomentumValues(symbol, Signal_TF, symbol_index, macd_value, stoch_value);
               
               // Get prediction with all required inputs
               double spread = g_symbols[symbol_index].cache.spread * g_symbols[symbol_index].cache.point;
               int htf_struct = DetectMarketStructure(symbol, Confirm_TF);
               double htf_bias_feature = (htf_struct == MARKET_BULLISH ? 1.0 : htf_struct == MARKET_BEARISH ? -1.0 : 0.0);
               double vol_regime = GetCachedVolatilityFactor(symbol, symbol_index);
               
               double buy_prob = 0.5;
               double sell_prob = 0.5;
                GetAIModuleProbabilities(close0, close1, close5, atr_value, 
                                         rsi_val, ma_slope_val, vol0, vol1, vol_avg, 
                                         macd_value, stoch_value, 0.5,
                                         spread, htf_bias_feature, vol_regime,
                                         buy_prob, sell_prob);
                
                double cache_confidence = MathMax(buy_prob, sell_prob);
                ai_prob_for_scoring = GetEffectiveDirectionalAIProbability(resolved_direction, buy_prob, sell_prob);
                ai_confidence = ai_prob_for_scoring;
                signal.ai_probability = GetRawDirectionalAIProbability(resolved_direction, buy_prob, sell_prob);
                signal.ai_confidence = ai_confidence;
               
               // FIXED: Update prediction cache for subsequent checks
               g_ai_prediction_cache[symbol_index].probability = buy_prob;
               g_ai_prediction_cache[symbol_index].buy_prob = buy_prob;
               g_ai_prediction_cache[symbol_index].sell_prob = sell_prob;
                g_ai_prediction_cache[symbol_index].confidence = cache_confidence;
               g_ai_prediction_cache[symbol_index].last_update = TimeCurrent();
               g_ai_prediction_cache[symbol_index].created_time = TimeCurrent();
               g_ai_prediction_cache[symbol_index].tf = Signal_TF;
               g_ai_prediction_cache[symbol_index].bar_time = iTime(symbol, Signal_TF, 0);
               g_ai_prediction_cache[symbol_index].source_tick_msc =
                  GetLatestSymbolTickMsc(symbol, symbol_index, false);
                
                if(g_debug_signals_enabled)
                {
                  Log(LOG_DEBUG, "GenerateTradingSignal", symbol + " - AI Prediction: " + 
                      "Buy=" + DoubleToString(buy_prob, 4) + " Sell=" + DoubleToString(sell_prob, 4) + " | DirProb: " + 
                      DoubleToString(ai_confidence, 4) + " | Direction: " + 
                      (buy_prob > 0.6 ? "BULLISH" : sell_prob > 0.6 ? "BEARISH" : "NEUTRAL"));
               }
            }
         }
      }

      // Pre-score uses resolved direction before entry/SL/TP are fully built.
      // Probe with a directional candidate instead of the still-empty signal shell.
      STradingSignal scoring_probe = signal;
      scoring_probe.valid = true;
      scoring_probe.direction = resolved_direction;
      scoring_probe.origin = SIGNAL_ORIGIN_ICT;

      if(!ApplyScoringGate(symbol, Signal_TF, scoring_probe, ai_prob_for_scoring, atr_value, htf_bias, "ICT",
                           symbol_index, mid_price, sig_struct_cache))
      {
         signal.reason = scoring_probe.reason;
         return signal;
      }
   }
   else
   {
      // Simple filter when ScoringEngine disabled - just check if market is trending
      if(g_Use_Trend_Filter && GetHTFBiasStrengthInstitutional(symbol) < 50.0)
      {
         signal.reason = "Market not trending (trend filter enabled)";
         LogTradeMessage(LOG_INFO, "GenerateTradingSignal", symbol, signal.reason);
         return signal;
      }
      
      Log(LOG_DEBUG, "GenerateTradingSignal", symbol + " - ScoringEngine disabled, using basic trend check - PASSED");
   }
      
   if(!RunCommonSignalPostChecks(symbol, symbol_index, signal))
      return signal;

   datetime current_time = TimeCurrent();
   
   // Minimal per-symbol cooldown to prevent bursts when the configured cooldown is disabled.
   const int MIN_COOLDOWN_SECONDS = 30;
   if(!g_Force_Signal_Cadence_Gate_Off &&
      MAX_SIGNAL_COOLDOWN_MINUTES <= 0 && g_symbols[symbol_index].last_signal_time > 0 &&
      (current_time - g_symbols[symbol_index].last_signal_time) < MIN_COOLDOWN_SECONDS)
   {
      signal.reason = StringFormat("Signal cooldown active (fast 30s guard) %d/%d",
                                   (int)(current_time - g_symbols[symbol_index].last_signal_time),
                                   MIN_COOLDOWN_SECONDS);
      Log(LOG_DEBUG, "GenerateTradingSignal", symbol + " - " + signal.reason);
      return signal;
   }

   // FIX 3: Improved signal cooldown - check for existing positions, not just time
   // Use a fresh broker-state count here so cooldown/exposure gates do not lag behind a recent fill.
   int current_positions = GetSymbolPositionCountLive(symbol);
   if(!g_Force_Signal_Cadence_Gate_Off)
   {
      if(current_positions > 0)
      {
         // Position exists, enforce full cooldown
         datetime last_ref_time = g_symbols[symbol_index].last_position_open;
         if(last_ref_time <= 0)
            last_ref_time = g_symbols[symbol_index].last_signal_time;

         if(last_ref_time > 0 &&
            (current_time - last_ref_time) < (MAX_SIGNAL_COOLDOWN_MINUTES * 60))
         {
            signal.reason = "Signal cooldown active (position open)";
            Log(LOG_DEBUG, "GenerateTradingSignal", symbol + " - " + signal.reason);
            return signal;
         }
      }
      else
      {
         // No position, lighter cooldown for sequence trading
         int seconds_since_signal = (int)(current_time - g_symbols[symbol_index].last_signal_time);
         int cooldown_seconds = (MAX_SIGNAL_COOLDOWN_MINUTES * 60) / 2;
         if(g_symbols[symbol_index].last_signal_time > 0 && seconds_since_signal < cooldown_seconds)
         {
            signal.reason = StringFormat("Signal cooldown active (%d/%d seconds)", seconds_since_signal, cooldown_seconds);
            Log(LOG_DEBUG, "GenerateTradingSignal", symbol + " - " + signal.reason);
            return signal;
         }
      }
   }
   
   if(CGateController::IsExposureGateEnabled() && current_positions >= MAX_TRADES_PER_SYMBOL)
   {
      signal.reason = "Max positions per symbol reached: " + IntegerToString(current_positions) + "/" + IntegerToString(MAX_TRADES_PER_SYMBOL);
      Log(LOG_INFO, "GenerateTradingSignal", symbol + " - " + signal.reason);
      return signal;
   }

   if(!RefreshSymbolCache(symbol_index))
   {
      signal.reason = "Failed to refresh cache";
      Log(LOG_WARNING, "GenerateTradingSignal", symbol + " - " + signal.reason);
      return signal;
   }
   
   double current_bid = g_symbols[symbol_index].cache.bid;
   double current_ask = g_symbols[symbol_index].cache.ask;
   if(current_bid <= 0.0 || current_ask <= 0.0 || current_bid >= current_ask)
   {
      current_bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      current_ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   }
   if(current_bid <= 0.0 || current_ask <= 0.0 || current_bid >= current_ask)
   {
      signal.reason = "Invalid market prices";
      Log(LOG_WARNING, "GenerateTradingSignal", symbol + " - " + signal.reason);
      return signal;
   }
   double current_price = (current_bid + current_ask) / 2.0;
   
   int trade_direction = resolved_direction;
   
   // Get ATR value early - needed for reversal detection and other calculations
   atr_value = GetATRValue(symbol, Signal_TF);
   if(atr_value <= 0.0)
   {
      signal.reason = "Invalid ATR value";
      Log(LOG_WARNING, "GenerateTradingSignal", symbol + " - " + signal.reason);
      return signal;
   }

   // Order block detection
   double order_block_high = 0.0, order_block_low = 0.0;
   bool order_block_found = DetectOrderBlock(symbol, Primary_TF, trade_direction, 
                                           order_block_high, order_block_low);
   
   if(!order_block_found)
   {
      // Always continue to structural gating so NoOB can still qualify through strict confluence
      // (e.g., strong HTF context + FVG + BOS) instead of hard-stopping early.
      Log(LOG_INFO, "GenerateTradingSignal", symbol + " - No order block found; deferring to structural fallback path" +
          (g_Disable_All_Gates ? " (master bypass)" : ""));
   }
   else
   {
      signal.order_block_high = order_block_high;
      signal.order_block_low = order_block_low;
   }
   signal.atr_value = atr_value;

   // FVG detection
   double fvg_high = 0.0, fvg_low = 0.0;
   bool fvg_found = DetectFairValueGap(symbol, Signal_TF, trade_direction, fvg_high, fvg_low);
   
   if(fvg_found)
   {
      signal.fvg_high = fvg_high;
      signal.fvg_low = fvg_low;
   }

   // Reversal detection - ENHANCED INTEGRATION
   if(Enable_Reversal_Detection)
   {
      SReversalSignal reversal_signal = g_reversal_detector.DetectReversal(symbol, Signal_TF);
      
      if(reversal_signal.valid)
      {
         signal.reversal_detected = true;
         signal.reversal_confidence = reversal_signal.confidence;
         signal.reversal_reason = reversal_signal.reason;
         
         // Track reversal statistics
         g_reversal_signals_count++;
         
         Log(LOG_INFO, "GenerateTradingSignal", symbol + " - Reversal detected: " + reversal_signal.reason + 
             " (Confidence: " + DoubleToString(reversal_signal.confidence * 100, 1) + "%)");
         
         // Check if reversal direction aligns with or overrides trade direction
         if(reversal_signal.direction == trade_direction)
         {
            // Reversal confirms our trade direction - boost confidence
            g_reversal_confirmed_count++;
            Log(LOG_INFO, "GenerateTradingSignal", symbol + " - Reversal CONFIRMS trade direction");
            
            // Use reversal entry levels if they're better positioned
            if(reversal_signal.entry_price > 0)
            {
               double current_price = (g_symbols[symbol_index].cache.bid + g_symbols[symbol_index].cache.ask) / 2;
               double reversal_distance = MathAbs(reversal_signal.entry_price - current_price);
               double ob_distance = (order_block_found) ? MathAbs(current_price - (order_block_high + order_block_low)/2) : 1e308;
               
               // Use reversal entry if it's closer to current price and reasonable
               if(reversal_distance < ob_distance && reversal_distance < atr_value * 2.0)
               {
                  signal.entry_price = reversal_signal.entry_price;
                  Log(LOG_DEBUG, "GenerateTradingSignal", symbol + " - Using reversal entry price: " + DoubleToString(reversal_signal.entry_price, 2));
               }
            }
            
            // Use reversal SL/TP if they provide better risk/reward
            if(reversal_signal.stop_loss > 0 && reversal_signal.take_profit > 0)
            {
               double reversal_risk = MathAbs(reversal_signal.entry_price - reversal_signal.stop_loss);
               double reversal_reward = MathAbs(reversal_signal.take_profit - reversal_signal.entry_price);
               double reversal_rr = SafeDiv(reversal_reward, reversal_risk, 0.0);
               
               if(reversal_rr >= g_Min_RR_Ratio)
               {
                  signal.stop_loss = reversal_signal.stop_loss;
                  signal.take_profit = reversal_signal.take_profit;
                  Log(LOG_DEBUG, "GenerateTradingSignal", symbol + " - Using reversal SL/TP (RR: " + DoubleToString(reversal_rr, 2) + ")");
               }
            }
         }
         else if(reversal_signal.direction == -trade_direction)
         {
            // Reversal opposes our trade direction
            if(reversal_signal.confidence > 0.7)
            {
               if(Reversal_Override_Direction)
               {
                  // Calculated-direction lock: never allow reversal logic to flip direction counter-trend.
                  signal.reason = "Counter-trend reversal blocked by calculated-direction lock: " + reversal_signal.reason;
                  Log(LOG_INFO, "GenerateTradingSignal", symbol + " - " + signal.reason);
                  return signal;
               }

               if(!g_Allow_Opposing_Reversal_Trades)
               {
                  // Strong opposing reversal - skip trade
                  signal.reason = "Strong reversal signal opposes trade direction: " + reversal_signal.reason +
                                 " (Confidence: " + DoubleToString(reversal_signal.confidence * 100, 1) + "%)";
                  Log(LOG_INFO, "GenerateTradingSignal", symbol + " - " + signal.reason);
                  return signal; // Return invalid signal
               }

               Log(LOG_INFO, "GenerateTradingSignal", symbol + " - Strong opposing reversal tolerated by tuning");
            }
            else
            {
               // Weak opposing reversal - proceed with caution
               Log(LOG_DEBUG, "GenerateTradingSignal", symbol + " - Weak opposing reversal detected (" +
                   DoubleToString(reversal_signal.confidence * 100, 1) + "%), proceeding with original direction");
            }
         }
      }
      else
      {
         Log(LOG_DEBUG, "GenerateTradingSignal", symbol + " - No reversal pattern detected");
      }
   }

   int structural_gate_failures = 0;
   string structural_gate_notes = "";
   bool soft_gate_applied = false;

   if(!order_block_found)
   {
      structural_gate_failures++;
      structural_gate_notes += "NoOB";
   }

   if(g_Require_FVG_For_Trade && !fvg_found)
   {
      if(StringLen(structural_gate_notes) > 0) structural_gate_notes += ";";
      structural_gate_failures++;
      structural_gate_notes += "NoFVG";
   }

   // BOS confirmation can be relaxed for tester calibration runs.
   bool bos_confirmed = DetectStructureBreak(symbol, Signal_TF, trade_direction);
   if(g_Require_BOS_Confirmation && !bos_confirmed)
   {
      if(StringLen(structural_gate_notes) > 0) structural_gate_notes += ";";
      structural_gate_failures++;
      structural_gate_notes += "NoBOS";
   }

   bool actual_first_retracement = false;
   bool discount_zone = false;
   if(trade_direction == 1 || trade_direction == -1)
   {
      actual_first_retracement = IsFirstRetracementAfterBOS(symbol, Signal_TF, trade_direction);
      discount_zone = IsInDiscountZone(symbol, Signal_TF, trade_direction);
   }

   // First-retracement gate is optional and can be force-disabled by forward-only mode.
   bool first_retracement = (g_Require_First_Retracement_After_BOS ? actual_first_retracement : true);

   if(g_Require_First_Retracement_After_BOS && !first_retracement)
   {
      if(StringLen(structural_gate_notes) > 0) structural_gate_notes += ";";
      structural_gate_failures++;
      structural_gate_notes += "NotFirstRetracement";
   }

   // If both OB and FVG exist, prefer overlap and reject conflicting zones in confluence mode.
   bool has_zone_overlap = false;
   if(fvg_found && order_block_found)
   {
      double overlap_low = MathMax(order_block_low, fvg_low);
      double overlap_high = MathMin(order_block_high, fvg_high);
      if(overlap_high > overlap_low)
      {
         has_zone_overlap = true;
      }
      else if(g_Enable_Confluence_Check)
      {
         if(StringLen(structural_gate_notes) > 0) structural_gate_notes += ";";
         structural_gate_failures++;
         structural_gate_notes += "NoOBFVGOverlap";
      }
   }

   // Hard structural confluence fallback:
   // If OB is missing but FVG + BOS are both present under strong HTF context,
   // allow continuation without requiring soft-gate toggles.
   bool strong_context_for_noob = (MathAbs(htf_bias_score) >= MathMax(2, g_Soft_Gate_Min_HTF_Bias_Score));
   bool noob_confluence_fallback = (!order_block_found && fvg_found && bos_confirmed && strong_context_for_noob);
   if(structural_gate_failures == 1 && noob_confluence_fallback)
   {
      Log(LOG_INFO, "GenerateTradingSignal", symbol +
          " - NoOB confluence fallback accepted: FVG+BOS present | HTF score=" +
          IntegerToString(htf_bias_score));
      structural_gate_failures = 0;
      structural_gate_notes = "";
   }

   // FVG-only structural fallback:
   // If HTF bias agrees and is strong, allow FVG-only setups to proceed even when OB/BOS
   // (and first-retracement) gates are the only blockers.
   bool htf_bias_agrees = (htf_bias != 0 && trade_direction == htf_bias);
   bool strong_context_for_fvg_only = (MathAbs(htf_bias_score) >= g_Soft_Gate_Min_HTF_Bias_Score);
   int fvg_only_failures = 0;
   if(!order_block_found)
      fvg_only_failures++;
   if(g_Require_BOS_Confirmation && !bos_confirmed)
      fvg_only_failures++;
   if(g_Require_First_Retracement_After_BOS && !first_retracement)
      fvg_only_failures++;

   bool fvg_only_fallback = (fvg_found &&
                             htf_bias_agrees &&
                             strong_context_for_fvg_only &&
                             fvg_only_failures > 0 &&
                             structural_gate_failures == fvg_only_failures);
   if(structural_gate_failures > 0 && fvg_only_fallback)
   {
      // CRITICAL FIX #3: Add reversal safeguard to FVG-only fallback
      // Prevents triggering counter-reversal trades when FVG lacks OB/BOS structural protection
      bool reversal_blocks_fvg_only = false;
      if(Enable_Reversal_Detection && signal.reversal_detected &&
         signal.reversal_confidence > 0.65 && signal.reversal_confidence > -1.0)
      {
         // Check if reversal opposes trade direction (note: signal.reversal_confidence stores direction-aware confidence)
         // Reversal detector returns positive confidence for direction agreement, need to check reversal_reason
         // Strong opposing reversal should block FVG-only since FVG alone lacks structural invalidation boundary
         reversal_blocks_fvg_only = true;
         Log(LOG_INFO, "GenerateTradingSignal", symbol +
             " - FVG-only BLOCKED: Strong reversal signal (conf=%" +
             DoubleToString(signal.reversal_confidence * 100, 1) + ") detected: " + signal.reversal_reason);
      }
      
      if(!reversal_blocks_fvg_only)
      {
         Log(LOG_INFO, "GenerateTradingSignal", symbol +
             " - FVG-only fallback accepted: " + structural_gate_notes +
             " | HTF score=" + IntegerToString(htf_bias_score));
         structural_gate_failures = 0;
         structural_gate_notes = "";
      }
      else
      {
         // Reversal blocked fallback; keep failures for regular soft gating to apply RR penalties
         Log(LOG_INFO, "GenerateTradingSignal", symbol + 
             " - FVG-only fallback blocked by reversal gate, deferring to soft structural gating");
      }
   }

   if(structural_gate_failures > 0)
   {
      if(!CGateController::IsStructuralGateEnabled())
      {
         Log(LOG_INFO, "GenerateTradingSignal", symbol + " - Structural gating bypassed by gate controller: " + structural_gate_notes);
         structural_gate_failures = 0;
         structural_gate_notes = "";
      }

      if(structural_gate_failures > 0)
      {
         bool strong_context = (MathAbs(htf_bias_score) >= g_Soft_Gate_Min_HTF_Bias_Score);
         bool soft_gate_allowed = (g_Enable_Soft_Structural_Gating &&
                                   strong_context &&
                                   structural_gate_failures <= g_Max_Soft_Gate_Failures);

         if(!soft_gate_allowed)
         {
            signal.reason = "Structural gating blocked: " + structural_gate_notes;
            Log(LOG_INFO, "GenerateTradingSignal", symbol + " - " + signal.reason);
            return signal;
         }

         soft_gate_applied = true;
         Log(LOG_INFO, "GenerateTradingSignal", symbol + " - Soft structural gating applied: " +
             structural_gate_notes + " | HTF score=" + IntegerToString(htf_bias_score) +
             " | failures=" + IntegerToString(structural_gate_failures));
      }
   }

   double volatility_factor = GetCachedVolatilityFactor(symbol, symbol_index);

   // FIXED: Log direction decision for debugging
   string htf_bias_text = (htf_bias == 1 ? "BULLISH" : htf_bias == -1 ? "BEARISH" : "NEUTRAL");
   string direction_suffix = (StringLen(direction_note) > 0 ? " | " + direction_note : "");
   Log(LOG_INFO, "GenerateTradingSignal", symbol + " - Direction: " + 
       (trade_direction == 1 ? "BUY" : "SELL") + 
       " (HTF: " + htf_bias_text + 
       ", Signal TF: " + MarketStructureToString(signal_tf_structure) + ")" + direction_suffix);
   
   signal.direction = trade_direction;

   bool signal_tf_retracing =
      ((trade_direction == 1 && signal_tf_structure == MARKET_BEARISH) ||
       (trade_direction == -1 && signal_tf_structure == MARKET_BULLISH));
   bool retracement_continuation = (htf_bias == trade_direction && signal_tf_retracing);
   if(retracement_continuation)
   {
      signal.retracement_signal = true;
      if(g_Enable_Institutional_Debug || g_debug_signals_enabled)
      {
         Log(LOG_DEBUG, "GenerateTradingSignal", symbol +
             " - ICT retracement continuation armed (FirstRetrace=" +
             (actual_first_retracement ? "Y" : "N") +
             ", Discount=" + (discount_zone ? "Y" : "N") + ")");
      }
   }
    
   // FIX 4: Clarify entry price assignment with explicit precedence
   // Priority 1: Reversal detection entry (if already set above)
   if(signal.entry_price <= 0)
   {
      // Priority 2: OB + FVG overlap entry (highest ICT quality)
      if(order_block_found && fvg_found &&
         order_block_high > 0 && order_block_low > 0 &&
         fvg_high > 0 && fvg_low > 0)
      {
         double overlap_low = MathMax(order_block_low, fvg_low);
         double overlap_high = MathMin(order_block_high, fvg_high);
         if(overlap_high > overlap_low)
         {
            signal.entry_price = overlap_low + (overlap_high - overlap_low) * 0.5;
            Log(LOG_DEBUG, "GenerateTradingSignal", symbol + " - Using OB/FVG overlap entry: " + DoubleToString(signal.entry_price, 2));
         }
      }

      // Priority 3: FVG-based entry (midpoint to avoid chasing edge taps)
      if(signal.entry_price <= 0 && fvg_found && fvg_high > 0 && fvg_low > 0)
      {
         signal.entry_price = fvg_low + (fvg_high - fvg_low) * 0.5;
         Log(LOG_DEBUG, "GenerateTradingSignal", symbol + " - Using FVG midpoint entry: " + DoubleToString(signal.entry_price, 2));
      }

      // Priority 4: Order block-based entry (discount/premium bias)
      if(signal.entry_price <= 0 && order_block_found && order_block_high > 0 && order_block_low > 0)
      {
         double ob_range = order_block_high - order_block_low;
         if(ob_range <= 0)
         {
            // Fallback to mid if OB range is invalid
            signal.entry_price = (order_block_high + order_block_low) / 2.0;
         }
         else
         {
            if(trade_direction == 1)
               // Buy: deeper discount inside OB for fewer false positives
               signal.entry_price = order_block_low + ob_range * 0.2;
            else
               // Sell: deeper premium inside OB
               signal.entry_price = order_block_high - ob_range * 0.2;
         }
          Log(LOG_DEBUG, "GenerateTradingSignal", symbol + " - Using OB-based entry: " + DoubleToString(signal.entry_price, 2));
      }
   }
   
   // Ensure entry price is always set
   if(signal.entry_price <= 0)
   {
      double fallback_entry = (trade_direction == 1 ? current_ask : current_bid);
      if(fallback_entry <= 0.0)
         fallback_entry = current_price;

      bool allow_market_anchor_fallback = (g_Disable_All_Gates || soft_gate_applied);
      if(allow_market_anchor_fallback && fallback_entry > 0.0)
      {
         signal.entry_price = fallback_entry;
         Log(LOG_WARNING, "GenerateTradingSignal",
             symbol + " - Structure entry unavailable; using market-anchor fallback " +
             DoubleToString(signal.entry_price, 2) +
             " | OB=" + (order_block_found ? "Y" : "N") +
             " FVG=" + (fvg_found ? "Y" : "N") +
             " SoftGate=" + (soft_gate_applied ? "Y" : "N") +
             " MasterBypass=" + (g_Disable_All_Gates ? "Y" : "N") +
             (StringLen(structural_gate_notes) > 0 ? " Notes=" + structural_gate_notes : ""));
      }
      else
      {
         signal.reason = "Failed to calculate entry price | OB=" + (order_block_found ? "Y" : "N") +
                         " FVG=" + (fvg_found ? "Y" : "N") +
                         " SoftGate=" + (soft_gate_applied ? "Y" : "N") +
                         " MasterBypass=" + (g_Disable_All_Gates ? "Y" : "N") +
                         (StringLen(structural_gate_notes) > 0 ? " Notes=" + structural_gate_notes : "");
         Log(LOG_ERROR, "GenerateTradingSignal", symbol + " - " + signal.reason);
         return signal;
      }
   }

   if(g_ICT_Forward_Trend_Only)
   {
      double forward_anchor = (trade_direction == 1 ? current_ask : current_bid);
      if(forward_anchor <= 0.0)
         forward_anchor = current_price;

      if(forward_anchor <= 0.0)
      {
         signal.reason = "Invalid forward anchor price";
         Log(LOG_WARNING, "GenerateTradingSignal", symbol + " - " + signal.reason);
         return signal;
      }

      if(trade_direction == 1 && signal.entry_price < forward_anchor)
      {
         Log(LOG_DEBUG, "GenerateTradingSignal", symbol + " - Forward-only entry clamp (BUY): " +
             DoubleToString(signal.entry_price, 2) + " -> " + DoubleToString(forward_anchor, 2));
         signal.entry_price = forward_anchor;
      }
      else if(trade_direction == -1 && signal.entry_price > forward_anchor)
      {
         Log(LOG_DEBUG, "GenerateTradingSignal", symbol + " - Forward-only entry clamp (SELL): " +
             DoubleToString(signal.entry_price, 2) + " -> " + DoubleToString(forward_anchor, 2));
         signal.entry_price = forward_anchor;
      }
   }

   if(g_Enable_ICT_Smart_Entry_Validation && !g_ICT_Forward_Trend_Only && order_block_found &&
       !ValidateSmartEntry(symbol, Signal_TF, trade_direction, signal.entry_price, order_block_low, order_block_high))
   {
       signal.reason = "Entry failed ICT smart-entry validation";
       Log(LOG_INFO, "GenerateTradingSignal", symbol + " - " + signal.reason);
       return signal;
   }
   else if(g_Enable_ICT_Smart_Entry_Validation && g_ICT_Forward_Trend_Only && Log_Level >= LOG_DEBUG)
   {
      Log(LOG_DEBUG, "GenerateTradingSignal", symbol + " - Smart-entry validation skipped (forward-only mode)");
   }
   else if(g_Enable_ICT_Smart_Entry_Validation && !order_block_found && Log_Level >= LOG_DEBUG)
   {
       Log(LOG_DEBUG, "GenerateTradingSignal", symbol + " - Smart-entry validation skipped (no order block available)");
   }

   if(Log_Level >= LOG_DEBUG)
   {
      Log(LOG_DEBUG, "GenerateTradingSignal", symbol + " - Levels: OB[" +
          DoubleToString(order_block_low, 2) + "," + DoubleToString(order_block_high, 2) +
          "] FVG[" + DoubleToString(fvg_low, 2) + "," + DoubleToString(fvg_high, 2) +
          "] Entry=" + DoubleToString(signal.entry_price, 2));
   }

   // Reject entries that are too far from current price (prevents chasing)
   // CRITICAL FIX #2: Distance-aware structure bonuses - good structures only help at tight distances
   if(g_Enable_Entry_Distance_Validation && current_price > 0)
   {
      double entry_distance_pct = MathAbs(signal.entry_price - current_price) / current_price * 100.0;
      double allowed_distance_pct = g_Max_Entry_Distance_Pct;
      
      // Apply distance-aware bonuses: structure quality only helps when entry is tight
      if(entry_distance_pct < 0.5)
      {
         // Entry is tight to market - structure quality helps confidence
         if(fvg_found)
            allowed_distance_pct += 0.35;    // Strong FVG bonus at tight distances
         else if(order_block_found)
            allowed_distance_pct += 0.20;    // OB bonus at tight distances
      }
      else if(entry_distance_pct < 1.0)
      {
         // Entry is moderate distance - slight structure help only
         if(fvg_found)
            allowed_distance_pct += 0.15;    // Reduced FVG bonus at moderate distances
         else if(order_block_found)
            allowed_distance_pct += 0.10;    // Reduced OB bonus at moderate distances
      }
      // else: entry is far from market (>1.0%) - no structure bonus compensates
      
      // Cap total allowed distance to avoid excessive chasing
      double entry_distance_cap = (soft_gate_applied ? g_Max_Entry_Distance_Relaxed_Cap : 1.10);
      allowed_distance_pct = MathMin(allowed_distance_pct, entry_distance_cap);

      if(entry_distance_pct > allowed_distance_pct)
      {
         signal.reason = "Entry too far from current price (" + DoubleToString(entry_distance_pct, 2) + "% > " +
                         DoubleToString(allowed_distance_pct, 2) + "%)";
         Log(LOG_INFO, "GenerateTradingSignal", symbol + " - " + signal.reason);
         return signal;
      }
   }

   // Hard execution safety: never allow entries excessively far from market.
   // This remains active even when soft gating/validation toggles are disabled.
   if(current_price > 0.0)
   {
      double hard_entry_distance_pct = MathAbs(signal.entry_price - current_price) / current_price * 100.0;
      double hard_entry_cap_pct = MathMin(2.0, MathMax(0.80, g_Max_Entry_Distance_Relaxed_Cap));
      if(hard_entry_distance_pct > hard_entry_cap_pct)
      {
         signal.reason = "Entry hard-safety blocked (" + DoubleToString(hard_entry_distance_pct, 2) + "% > " +
                         DoubleToString(hard_entry_cap_pct, 2) + "%)";
         Log(LOG_WARNING, "GenerateTradingSignal", symbol + " - " + signal.reason);
         return signal;
      }
   }

   bool use_reversal_levels = false;
   if(signal.stop_loss > 0.0 && signal.take_profit > 0.0)
   {
      bool reversal_layout_ok =
         ((trade_direction == 1 && signal.stop_loss < signal.entry_price && signal.take_profit > signal.entry_price) ||
          (trade_direction == -1 && signal.stop_loss > signal.entry_price && signal.take_profit < signal.entry_price));
      if(reversal_layout_ok)
         use_reversal_levels = true;
      else
      {
         signal.stop_loss = 0.0;
         signal.take_profit = 0.0;
      }
   }

   // Calculate stop loss and take profit
   double atr_stop_distance = atr_value * ATR_SL_Multiplier * volatility_factor;

   if(!use_reversal_levels)
   {
      if(trade_direction == 1)
         signal.stop_loss = signal.entry_price - atr_stop_distance;
      else
         signal.stop_loss = signal.entry_price + atr_stop_distance;
   }

   // ICT structural invalidation: keep SL beyond OB/FVG boundaries where available.
   if(order_block_found)
   {
      if(trade_direction == 1)
         signal.stop_loss = MathMin(signal.stop_loss, order_block_low - atr_value * 0.15);
      else
         signal.stop_loss = MathMax(signal.stop_loss, order_block_high + atr_value * 0.15);
   }
   if(fvg_found)
   {
      if(trade_direction == 1)
         signal.stop_loss = MathMin(signal.stop_loss, fvg_low - atr_value * 0.10);
      else
         signal.stop_loss = MathMax(signal.stop_loss, fvg_high + atr_value * 0.10);
   }

   double risk_distance = MathAbs(signal.entry_price - signal.stop_loss);
   double spread_price = g_symbols[symbol_index].cache.spread * g_symbols[symbol_index].cache.point;
   double min_risk_distance = MathMax(spread_price * 2.5, atr_value * 0.20);
    double max_risk_distance = atr_value * MathMax(0.0, g_ICT_Max_Risk_ATR_Multiple);
   double risk_base = GetRiskBaseValue();
   double final_risk_cap = (risk_base > 0.0 && g_Final_Per_Trade_Risk_Cap_Pct > 0.0 ?
                            risk_base * g_Final_Per_Trade_Risk_Cap_Pct / 100.0 : 0.0);
   double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   if(final_risk_cap > 0.0 && min_lot > 0.0 && signal.entry_price > 0.0)
   {
      double cap_distance = (max_risk_distance > 0.0 ? max_risk_distance : atr_value);
      double cap_sl = signal.entry_price - trade_direction * cap_distance;
      double minlot_risk_at_cap = CalculateTradeRiskCurrency(symbol, trade_direction, min_lot,
                                                              signal.entry_price, cap_sl);
      if(minlot_risk_at_cap > final_risk_cap && minlot_risk_at_cap > 0.0)
      {
         double affordability_distance = cap_distance * SafeDiv(final_risk_cap, minlot_risk_at_cap, 0.0);
         if(affordability_distance > 0.0)
         {
            if(max_risk_distance <= 0.0)
               max_risk_distance = affordability_distance;
            else
               max_risk_distance = MathMin(max_risk_distance, affordability_distance);
         }
      }
   }
   if(risk_distance < min_risk_distance)
   {
      signal.reason = "Risk distance too small vs spread/ATR";
      Log(LOG_INFO, "GenerateTradingSignal", symbol + " - " + signal.reason);
      return signal;
   }
    if(g_Enable_Max_Risk_Distance_Validation && max_risk_distance > 0.0 && risk_distance > max_risk_distance)
   {
      signal.reason = "Risk distance too wide after ICT structural stop";
      Log(LOG_INFO, "GenerateTradingSignal", symbol + " - " + signal.reason);
      return signal;
   }

   double required_rr = g_Min_RR_Ratio;
   if(!has_zone_overlap)
      required_rr = MathMax(required_rr, soft_gate_applied ? 1.6 : 1.8);  // softened when structural gates are explicitly relaxed
   if(soft_gate_applied)
   {
      // CRITICAL FIX #4: Use exponential RR scaling instead of linear
      // Rationale: Each additional structural failure compounds risk more than the previous one
      // Example scaling (with default g_Soft_Gate_Extra_RR = 0.15):
      //   1 failure: 1.15x multiplier on Min_RR (15% increase)
      //   2 failures: 1.32x multiplier on Min_RR (32% increase)
      //   3 failures: 1.50x multiplier on Min_RR (50% increase)
      // vs old linear: 0.15, 0.30, 0.45 additive
      double penalty_factor = 1.0 + (g_Soft_Gate_Extra_RR * MathPow((double)structural_gate_failures, 1.3));
      required_rr = g_Min_RR_Ratio * penalty_factor;
      if(Log_Level >= LOG_DEBUG)
         Log(LOG_DEBUG, "GenerateTradingSignal", symbol + " - Soft gate RR scaling: " +
             IntegerToString(structural_gate_failures) + " failures -> penalty_factor=" +
             DoubleToString(penalty_factor, 3) + " -> required_rr=" + DoubleToString(required_rr, 2));
   }

   double tp_distance = risk_distance * required_rr;
   if(!use_reversal_levels || signal.take_profit <= 0.0)
      signal.take_profit = signal.entry_price + trade_direction * tp_distance;

   STradeLevelContext trade_ctx;
   string trade_ctx_error = "";
   if(!BuildTradeLevelContext(symbol, symbol_index, trade_ctx, trade_ctx_error))
   {
      signal.reason = trade_ctx_error;
      Log(LOG_WARNING, "GenerateTradingSignal", symbol + " - " + signal.reason);
      return signal;
   }

   int levels_reason = TRADE_LEVELS_OK;
   if(!NormalizeAndValidateTradeLevels(symbol, trade_ctx,
                                       signal.entry_price, signal.stop_loss, signal.take_profit,
                                       levels_reason))
   {
      signal.reason = "Invalid trade levels [" + TradeLevelsReasonLabel(levels_reason) + "]";
      Log(LOG_WARNING, "GenerateTradingSignal", symbol + " - " + signal.reason);
      return signal;
   }

   double final_risk_distance = MathAbs(signal.entry_price - signal.stop_loss);
   if(final_risk_distance <= trade_ctx.point)
   {
      signal.reason = "Risk distance too small after normalization";
      Log(LOG_WARNING, "GenerateTradingSignal", symbol + " - " + signal.reason);
      return signal;
   }

   signal.risk_reward_ratio = CalculateTradeRiskRewardRatio(signal.entry_price, signal.stop_loss, signal.take_profit);

   double final_entry_distance_pct = (current_price > 0.0 ?
      MathAbs(signal.entry_price - current_price) / current_price * 100.0 : 0.0);
   string structural_notes = (StringLen(structural_gate_notes) > 0 ? structural_gate_notes : "None");
   signal.strategy_output_summary = StringFormat(
      "ICT[HTF=%d Sig=%s RT=%s OB=%s FVG=%s BOS=%s 1R=%s Disc=%s Ovl=%s Soft=%s RRreq=%.2f RR=%.2f]",
      htf_bias_score,
      MarketStructureToString(signal_tf_structure),
      (retracement_continuation ? "Y" : "N"),
      (order_block_found ? "Y" : "N"),
      (fvg_found ? "Y" : "N"),
      (bos_confirmed ? "Y" : "N"),
      (actual_first_retracement ? "Y" : "N"),
      (discount_zone ? "Y" : "N"),
      (has_zone_overlap ? "Y" : "N"),
      (soft_gate_applied ? "Y" : "N"),
      required_rr,
      signal.risk_reward_ratio
   );
   signal.strategy_output_detail = StringFormat(
      "ICT[Dir=%s HTF=%d Sig=%s RT=%s OB=%s FVG=%s BOS=%s 1R=%s Disc=%s Ovl=%s Soft=%s Fail=%d Notes=%s EntryDist=%.2f%% RRreq=%.2f RR=%.2f]",
      (trade_direction == 1 ? "BUY" : "SELL"),
      htf_bias_score,
      MarketStructureToString(signal_tf_structure),
      (retracement_continuation ? "Y" : "N"),
      (order_block_found ? "Y" : "N"),
      (fvg_found ? "Y" : "N"),
      (bos_confirmed ? "Y" : "N"),
      (actual_first_retracement ? "Y" : "N"),
      (discount_zone ? "Y" : "N"),
      (has_zone_overlap ? "Y" : "N"),
      (soft_gate_applied ? "Y" : "N"),
      structural_gate_failures,
      structural_notes,
      final_entry_distance_pct,
      required_rr,
      signal.risk_reward_ratio
   );

   // Final institutional score pass with realized RR and entry quality.
   if(Enable_All_Institutional_Filters)
   {
      double ai_prob_final = ai_prob_for_scoring;
      if(g_Enable_AI_Trend_Predictor_Runtime && g_ai_enabled && IsAIPredictionFresh(symbol_index, Signal_TF))
      {
         ai_prob_final = GetEffectiveDirectionalAIProbability(
            trade_direction,
            g_ai_prediction_cache[symbol_index].buy_prob,
            g_ai_prediction_cache[symbol_index].sell_prob
         );
      }

      double final_entry_distance_pct = -1.0;
      if(current_price > 0.0)
         final_entry_distance_pct = MathAbs(signal.entry_price - current_price) / current_price * 100.0;

      SFilterDiagnostic final_diagnostic;
      bool final_score_ok = g_scoring_engine.ShouldExecuteTrade(
         symbol,
         Signal_TF,
         trade_direction,
         final_diagnostic,
         ai_prob_final,
         signal.risk_reward_ratio,
         final_entry_distance_pct,
         (signal.reversal_detected ? signal.reversal_confidence : -1.0)
      );

      if(!final_score_ok)
      {
         double required_score_final = (final_diagnostic.required_score > 0.0 ? final_diagnostic.required_score : g_scoring_engine.GetScoreThreshold());
         signal.reason = "Final score rejected | " + DoubleToString(final_diagnostic.trade_score, 1) + "/" +
                         DoubleToString(required_score_final, 1) + " | Confidence: " + final_diagnostic.confidence_label;
         if(StringLen(final_diagnostic.score_breakdown) > 0)
            signal.reason += " (" + final_diagnostic.score_breakdown + ")";
         LogTradeMessage(LOG_INFO, "GenerateTradingSignal", symbol, signal.reason);
         return signal;
      }
      else
      {
         LogTradeMessage(LOG_INFO, "GenerateTradingSignal", symbol, "Final score approved",
            "Score: " + DoubleToString(final_diagnostic.trade_score, 1) + "/" + DoubleToString(final_diagnostic.required_score, 1) +
            " | Confidence: " + final_diagnostic.confidence_label +
            " | Components: " + final_diagnostic.score_breakdown);
      }
   }

   if(signal.risk_reward_ratio > required_rr - 0.01)  // Add small tolerance for floating point precision
   {
      // ===== INVERSION VALIDATION BLOCK (DEBUG MODE) =====
      if(DEBUG_SIGNAL_INVERSION)
      {
         // Get market structure for this signal's timeframe
         int signal_structure = DetectMarketStructure(symbol, Signal_TF);
         int signal_struct_direction = StructureToDirection(signal_structure);
         
         // **VECTOR 4 FIX**: Check for post-construction direction changes
         if(trade_direction != signal.direction)
         {
            Log(LOG_WARNING, "DirectionChange",
                StringFormat("%s: Direction changed from %d (calc) to %d (final signal)",
                             symbol, trade_direction, signal.direction));
         }
         
         // Validate direction consistency
         bool direction_ok = ValidateSignalDirectionAlignment(signal, signal_struct_direction);
         
         // Validate entry/SL/TP level alignment with direction
         bool level_ok = ValidateSignalLevelAlignment(signal);
         if(!level_ok)
         {
            if(DEBUG_SIGNAL_INVERSION_STRICT)
               Log(LOG_WARNING, "LevelMismatch", 
                   StringFormat("%s LEVEL INVERSION: Dir=%d but SL/TP positioning wrong", 
                                symbol, signal.direction));
         }
         
         if(DEBUG_SIGNAL_INVERSION_STRICT)
         {
            if(!direction_ok)
            {
               signal.reason = "Signal inversion: direction misaligned with structure";
               Log(LOG_WARNING, "SignalInversionBlock", symbol + " - " + signal.reason);
               return signal;
            }
            if(!level_ok)
            {
               signal.reason = "Signal inversion: entry/SL/TP misaligned";
               Log(LOG_WARNING, "SignalInversionBlock", symbol + " - " + signal.reason);
               return signal;
            }
         }
         
         // Log comprehensive diagnostic if strict mode
         if(DEBUG_SIGNAL_INVERSION_STRICT)
         {
            LogSignalInversionDiagnostic(symbol, signal, htf_bias, signal_structure);
         }
      }
      // ===== END INVERSION VALIDATION BLOCK =====
      
      signal.valid = true;
      signal.origin = SIGNAL_ORIGIN_ICT;
      signal.reason = "ICT signal ready | " + signal.strategy_output_summary;
      if(!FinalizeStrategySignalBasics(symbol, signal, SIGNAL_ORIGIN_ICT, "ICT"))
         return signal;
      
      string signal_msg = StringFormat("%s - %s | Entry: %.2f | SL: %.2f | TP: %.2f | RR: %.2f",
         symbol,
         (trade_direction == 1 ? "BUY" : "SELL"),
         signal.entry_price,
         signal.stop_loss,
         signal.take_profit,
         signal.risk_reward_ratio);
      
      // Add reversal information if detected
      if(signal.reversal_detected)
      {
         signal_msg += StringFormat(" | Reversal: %.1f%%", signal.reversal_confidence * 100);
      }
      string strategy_output = BuildStrategyOutputSummary(signal, true);
      if(StringLen(strategy_output) > 0)
         signal_msg += " | " + strategy_output;
      
      if(g_debug_signals_enabled)
      {
         Print("[DEBUG] ICT CANDIDATE SIGNAL: ", signal_msg);
      }
      
      // Candidate signal only; final validation (AI/filters) happens later in ProcessSignals()
      LogTradeMessage(LOG_DEBUG, "GenerateTradingSignal", symbol, "Candidate signal", signal_msg);
   }
   else
   {
      signal.reason = "RR ratio too low: " + DoubleToString(signal.risk_reward_ratio, 2) +
                     " (Min required: " + DoubleToString(required_rr, 1) + ")";
      
      // DEBUG: Track rejected signals
      g_debug_counters.signals_rejected++;
      
      if(g_debug_signals_enabled)
      {
         Print("[DEBUG] ICT REJECTED CANDIDATE: ", symbol, " - ", signal.reason);
      }
      
      LogTradeMessage(LOG_INFO, "GenerateTradingSignal", symbol, signal.reason);
   }

   return signal;
}

STradingSignal GenerateICTSignal(string symbol)
{
   return GenerateICTSignal(symbol, g_Allow_Range_Trading);
}

#endif // ICT_STRATEGY_MQH
