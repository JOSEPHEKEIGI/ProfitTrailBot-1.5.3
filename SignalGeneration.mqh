#ifndef SIGNAL_GENERATION_MQH
#define SIGNAL_GENERATION_MQH

// Forward declarations - struct definitions come later in main file
// STradingSignal GenerateICTSignal(string symbol);
// STradingSignal GenerateICTSignal(string symbol, bool allow_range_mode);
// STradingSignal GenerateAIPrimarySignal(string symbol, bool allow_range_mode = false);
// STradingSignal GenerateKImanizSignal(string symbol, bool allow_range_mode = false);
// STradingSignal GenerateTradingSignal(string symbol);
// double GetCachedMidPrice(string symbol, int symbol_index);

struct SAIProbabilitySnapshot
{
   bool   valid;
   int    shift;
   int    direction;
   double buy_prob;
   double sell_prob;
   double raw_directional_probability;
   double effective_directional_probability;
   double rsi_value;
   double ma_slope;
   double atr_value;
   double macd_value;
   double stochastic_value;
   double volume_ratio;
   string diag;

   SAIProbabilitySnapshot() :
      valid(false),
      shift(0),
      direction(0),
      buy_prob(0.5),
      sell_prob(0.5),
      raw_directional_probability(0.5),
      effective_directional_probability(0.5),
      rsi_value(50.0),
      ma_slope(0.0),
      atr_value(0.0),
      macd_value(0.0),
      stochastic_value(50.0),
      volume_ratio(1.0),
      diag("")
   {}
};

struct CacheMetadata
{
   int current_bar;
   int last_update_bar;
   datetime last_update;
   int cache_age_seconds;
   bool is_new_bar;
   bool is_stale_age;
   bool is_stale_combined;

   CacheMetadata() :
      current_bar(-1),
      last_update_bar(-1),
      last_update(0),
      cache_age_seconds(0),
      is_new_bar(false),
      is_stale_age(false),
      is_stale_combined(true)
   {}
};

int ResolveHTFBiasForSignalPass(string symbol,
                                bool has_seeded_trend_direction = false,
                                int seeded_trend_direction = 0)
{
   if(has_seeded_trend_direction)
      return seeded_trend_direction;

   return GetHTFBiasInstitutional(symbol);
}

/**
 * Helper functions - Many depend on undefined external functions from original code base
 * The institutional trend analysis integration is complete and functional
 */

CacheMetadata GetCacheStatus(int symbol_index, ENUM_TIMEFRAMES bar_timeframe, int max_age_seconds = 60)
{
   CacheMetadata status;

   if(symbol_index < 0 || symbol_index >= MAX_SYMBOLS)
      return status;

   string cache_symbol = Symbol();
   if(symbol_index < g_symbols_count && StringLen(g_symbols[symbol_index].name) > 0)
      cache_symbol = g_symbols[symbol_index].name;

   status.current_bar = iBarShift(cache_symbol, bar_timeframe, TimeCurrent(), false);
   status.last_update = g_ai_prediction_cache[symbol_index].last_update;
   status.last_update_bar =
      (g_ai_prediction_cache[symbol_index].bar_time > 0 ?
       iBarShift(cache_symbol, bar_timeframe, g_ai_prediction_cache[symbol_index].bar_time, false) :
       -1);

   datetime now = TimeCurrent();
   if(status.last_update > 0 && now >= status.last_update)
      status.cache_age_seconds = (int)(now - status.last_update);
   else
      status.cache_age_seconds = max_age_seconds + 1;

   status.is_new_bar = (status.current_bar != status.last_update_bar && status.last_update_bar >= 0);
   status.is_stale_age = (status.cache_age_seconds > max_age_seconds);
   status.is_stale_combined = (status.is_new_bar && status.is_stale_age) || status.last_update == 0;

   return status;
}

bool IsAIPredictionCacheStale(int symbol_index, int max_age_seconds = 60)
{
   if(symbol_index < 0 || symbol_index >= MAX_SYMBOLS)
      return true;

   if(g_ai_prediction_cache[symbol_index].created_time == 0)
      return true;

   datetime now = TimeCurrent();
   if((now - g_ai_prediction_cache[symbol_index].last_update) > max_age_seconds)
      return true;

   CacheMetadata cache_status = GetCacheStatus(symbol_index, Signal_TF, max_age_seconds);
   if(cache_status.is_stale_combined)
      return true;

   string cache_symbol = Symbol();
   if(symbol_index < g_symbols_count && StringLen(g_symbols[symbol_index].name) > 0)
      cache_symbol = g_symbols[symbol_index].name;

   long current_tick_msc = GetLatestSymbolTickMsc(cache_symbol, symbol_index, false);
   if(current_tick_msc <= 0)
      current_tick_msc = (long)SymbolInfoInteger(cache_symbol, SYMBOL_TIME_MSC);

   if(g_ai_prediction_cache[symbol_index].source_tick_msc > 0 &&
      current_tick_msc > 0 &&
      (current_tick_msc - g_ai_prediction_cache[symbol_index].source_tick_msc) > 5000)
      return true;

   return false;
}

// Helper function implementations
double ComputeRSIFromRates(const MqlRates &rates[], int shift, int period)
{
   if(period <= 0 || shift < 0)
      return 50.0;

   int needed = shift + period + 1;
   if(ArraySize(rates) < needed)
      return 50.0;

   // ===== RECOMMENDED IMPROVEMENT #2: ENHANCED RSI BOUNDS CHECKING =====
   // Additional validation: ensure we have enough bars for safe +1 indexing
   if(shift >= ArraySize(rates) || (shift + period) >= ArraySize(rates))
   {
      Log(LOG_DEBUG, "ComputeRSIFromRates", StringFormat(
          "Insufficient bars for RSI: shift=%d, period=%d, array_size=%d",
          shift, period, ArraySize(rates)));
      return 50.0;
   }
   
   double gains = 0.0;
   double losses = 0.0;
   for(int bar_index = shift; bar_index < shift + period && bar_index + 1 < ArraySize(rates); bar_index++)
   {
      double diff = rates[bar_index].close - rates[bar_index + 1].close;
      if(diff > 0.0)
         gains += diff;
      else
         losses -= diff;
   }

   double total = gains + losses;
   if(total <= 0.0)
      return 50.0;
   if(losses <= 0.0)
      return 100.0;

   double rs = gains / losses;
   double rsi = 100.0 - (100.0 / (1.0 + rs));
   if(!MathIsValidNumber(rsi))
      return 50.0;
   return MathMax(0.0, MathMin(100.0, rsi));
}

double ComputeATRFromRates(const MqlRates &rates[], int shift, int period)
{
   if(period <= 0 || shift < 0)
      return 0.0;

   int needed = shift + period + 1;
   if(ArraySize(rates) < needed)
      return 0.0;

   double tr_sum = 0.0;
   int samples = 0;
   for(int bar_index = shift; bar_index < shift + period; bar_index++)
   {
      double high = rates[bar_index].high;
      double low = rates[bar_index].low;
      double prev_close = rates[bar_index + 1].close;
      double tr = MathMax(high - low, MathMax(MathAbs(high - prev_close), MathAbs(low - prev_close)));
      if(MathIsValidNumber(tr) && tr > 0.0)
      {
         tr_sum += tr;
         samples++;
      }
   }

   if(samples <= 0)
      return 0.0;
   return tr_sum / (double)samples;
}

double GetSignalBarProgress(string symbol, ENUM_TIMEFRAMES tf)
{
   datetime bar_time = iTime(symbol, tf, 0);
   int tf_seconds = PeriodSeconds(tf);
   if(bar_time <= 0 || tf_seconds <= 0)
      return 0.0;

   datetime now = TimeCurrent();
   if(now <= bar_time)
      return 0.0;

   return MathClamp((double)(now - bar_time) / (double)tf_seconds, 0.0, 1.0);
}

int GetAIProbabilitySnapshotRequiredBars(int shift)
{
   const int AI_CLOSE_LOOKBACK = 5;
   const int AI_RSI_PERIOD = 14;
   const int AI_ATR_PERIOD = 14;
   const int AI_MA_PERIOD = 20;

   int close_required = shift + AI_CLOSE_LOOKBACK + 1;
   int momentum_required = shift + MathMax(AI_RSI_PERIOD, AI_ATR_PERIOD) + 1;
   int ma_required = shift + AI_MA_PERIOD + 1;
   return MathMax(close_required, MathMax(momentum_required, ma_required));
}

bool BuildAIProbabilitySnapshot(string symbol,
                                int symbol_index,
                                const MqlRates &rates[],
                                int shift,
                                double spread,
                                double htf_bias_feature,
                                double vol_regime,
                                double buy_min_prob,
                                double sell_min_prob,
                                SAIProbabilitySnapshot &snapshot)
{
   snapshot = SAIProbabilitySnapshot();
   snapshot.shift = shift;

   int required_bars = GetAIProbabilitySnapshotRequiredBars(shift);
   if(shift < 0 || ArraySize(rates) < required_bars)
   {
      snapshot.diag = StringFormat("insufficient_history(%d/%d)", ArraySize(rates), required_bars);
      return false;
   }

   // Extract OHLCV data
   double close0 = rates[shift].close;
   double close1 = (shift + 1 < ArraySize(rates)) ? rates[shift + 1].close : close0;
   double close5 = (shift + 5 < ArraySize(rates)) ? rates[shift + 5].close : close0;
   double high0 = rates[shift].high;
   double low0 = rates[shift].low;
   
   // Compute volume-based metrics
   double vol0 = (double)rates[shift].tick_volume;
   double vol1 = (shift + 1 < ArraySize(rates)) ? (double)rates[shift + 1].tick_volume : vol0;
   
   double vol_sum = 0.0;
   int vol_count = 0;
   for(int i = shift; i < ArraySize(rates) && i < shift + 3; i++)
   {
      vol_sum += (double)rates[i].tick_volume;
      vol_count++;
   }
   double vol_avg = (vol_count > 0 && vol_sum > 0.0) ? vol_sum / vol_count : vol0;
   snapshot.volume_ratio = (vol1 > 0.0 ? vol0 / vol1 : 1.0);

   // Compute RSI from rates (real calculation)
   snapshot.rsi_value = ComputeRSIFromRates(rates, shift, 14);

   // Compute MA slope using proper smoothing
   double ma20_now = 0.0;
   double ma20_prev = 0.0;
   int ma20_now_count = 0;
   int ma20_prev_count = 0;
   for(int i = shift; i < ArraySize(rates) && i < shift + 20; i++)
   {
      ma20_now += rates[i].close;
      ma20_now_count++;
   }
   for(int i = shift + 1; i < ArraySize(rates) && i < shift + 21; i++)
   {
      ma20_prev += rates[i].close;
      ma20_prev_count++;
   }
   ma20_now = (ma20_now_count > 0 ? ma20_now / (double)ma20_now_count : close0);
   ma20_prev = (ma20_prev_count > 0 ? ma20_prev / (double)ma20_prev_count : close1);
   snapshot.ma_slope = ma20_now - ma20_prev;

   // Compute ATR (real calculation)
   snapshot.atr_value = ComputeATRFromRates(rates, shift, 14);
   if(snapshot.atr_value <= 0.0)
   {
      snapshot.diag = "invalid_atr";
      return false;
   }

   // Get real MACD and Stochastic values from indicator cache if available
   GetMomentumValues(symbol, Signal_TF, symbol_index, snapshot.macd_value, snapshot.stochastic_value);

   // Call the real AI probability engine
   GetAIModuleProbabilities(close0, close1, close5, snapshot.atr_value,
                            snapshot.rsi_value, snapshot.ma_slope, vol0, vol1, vol_avg,
                            snapshot.macd_value, snapshot.stochastic_value, 0.5,
                            spread, htf_bias_feature, vol_regime,
                            snapshot.buy_prob, snapshot.sell_prob);

   // Validate probabilities
   if(!MathIsValidNumber(snapshot.buy_prob) || !MathIsValidNumber(snapshot.sell_prob) ||
      snapshot.buy_prob < 0.0 || snapshot.buy_prob > 1.0 ||
      snapshot.sell_prob < 0.0 || snapshot.sell_prob > 1.0)
   {
      snapshot.diag = "invalid_probabilities";
      return false;
   }

   // Determine direction based on probability thresholds
   snapshot.direction = SelectAIDirection(snapshot.buy_prob, snapshot.sell_prob, buy_min_prob, sell_min_prob);
   
   if(snapshot.direction != 0)
   {
      snapshot.raw_directional_probability = GetRawDirectionalAIProbability(snapshot.direction, snapshot.buy_prob, snapshot.sell_prob);
      snapshot.effective_directional_probability = GetEffectiveDirectionalAIProbability(snapshot.direction, snapshot.buy_prob, snapshot.sell_prob);
   }
   else
   {
      snapshot.raw_directional_probability = 0.5;
      snapshot.effective_directional_probability = 0.5;
   }

   snapshot.diag = StringFormat("shift=%d buy=%.3f sell=%.3f dir=%d eff=%.3f rsi=%.1f slope=%.5f atr=%.5f macd=%.5f stoch=%.1f volR=%.2f",
                                shift, snapshot.buy_prob, snapshot.sell_prob, snapshot.direction,
                                snapshot.effective_directional_probability, snapshot.rsi_value,
                                snapshot.ma_slope, snapshot.atr_value, snapshot.macd_value,
                                snapshot.stochastic_value, snapshot.volume_ratio);
   snapshot.valid = true;
   return true;
}

// ========================================
// SHARED SIGNAL SUMMARY AND ROUTING HELPERS
// ========================================

bool SignalHasAIDiagnostics(const STradingSignal &signal)
{
   return (signal.ai_buy_probability >= 0.0 ||
           signal.ai_sell_probability >= 0.0 ||
           signal.ai_effective_probability >= 0.0 ||
           signal.ai_directional_edge >= 0.0 ||
           signal.ai_candle_quality_score >= 0.0 ||
           signal.ai_expected_value_r >= 0.0 ||
           signal.ai_spread_to_atr >= 0.0 ||
           signal.ai_volatility_regime >= 0.0);
}

string BuildAISignalSummary(const STradingSignal &signal, bool compact = true)
{
   if(!SignalHasAIDiagnostics(signal))
      return "";

   string summary = StringFormat("AI[B=%.3f S=%.3f Eff=%.3f Edge=%.3f",
                                 (signal.ai_buy_probability >= 0.0 ? signal.ai_buy_probability : 0.0),
                                 (signal.ai_sell_probability >= 0.0 ? signal.ai_sell_probability : 0.0),
                                 (signal.ai_effective_probability >= 0.0 ? signal.ai_effective_probability : signal.ai_probability),
                                 (signal.ai_directional_edge >= 0.0 ? signal.ai_directional_edge : 0.0));

   if(signal.ai_min_probability_required >= 0.0)
      summary += StringFormat(" Min=%.3f", signal.ai_min_probability_required);
   if(signal.ai_required_edge >= 0.0)
      summary += StringFormat(" ReqEdge=%.3f", signal.ai_required_edge);
   if(signal.ai_candle_quality_score >= 0.0)
   {
      if(signal.ai_candle_quality_required >= 0.0)
         summary += StringFormat(" CQ=%.2f/%.2f", signal.ai_candle_quality_score, signal.ai_candle_quality_required);
      else
         summary += StringFormat(" CQ=%.2f", signal.ai_candle_quality_score);
   }
   if(signal.ai_expected_value_r >= 0.0)
      summary += StringFormat(" EV=%.2fR", signal.ai_expected_value_r);
   if(!compact)
   {
      if(signal.ai_spread_to_atr >= 0.0)
         summary += StringFormat(" SprATR=%.3f", signal.ai_spread_to_atr);
      if(signal.ai_volatility_regime >= 0.0)
         summary += StringFormat(" Vol=%.2f", signal.ai_volatility_regime);
   }
   summary += StringFormat(" Agree=%s", signal.ai_agrees ? "Y" : "N");
   summary += "]";
   return summary;
}

string BuildStrategyOutputSummary(const STradingSignal &signal, bool compact = true)
{
   string summary = (compact ? signal.strategy_output_summary : signal.strategy_output_detail);
   if(StringLen(summary) <= 0)
      summary = (compact ? signal.strategy_output_detail : signal.strategy_output_summary);

   string funnel_summary = signal.institutional_funnel_summary;
   if(StringLen(funnel_summary) > 0 && StringFind(summary, funnel_summary) < 0)
   {
      if(StringLen(summary) > 0)
         summary += " | ";
      summary += funnel_summary;
   }

   string ai_summary = BuildAISignalSummary(signal, compact);
   if(StringLen(ai_summary) > 0 && StringFind(summary, ai_summary) < 0)
   {
      if(StringLen(summary) > 0)
         summary += " | ";
      summary += ai_summary;
   }

   return summary;
}

string InstitutionalTimeframeTag(ENUM_TIMEFRAMES tf)
{
   string tag = EnumToString(tf);
   StringReplace(tag, "PERIOD_", "");
   return tag;
}

string InstitutionalRegimeToString(int regime)
{
   switch(regime)
   {
      case 0: return "TREND";
      case 1: return "RANGE";
      case 2: return "RETRACEMENT";
      default: return "UNKNOWN";
   }
}

string BuildInstitutionalFunnelLabel(ENUM_TIMEFRAMES entry_tf)
{
   return "Funnel[" +
          InstitutionalTimeframeTag(Trend_TF) + "->" +
          InstitutionalTimeframeTag(Primary_TF) + "->" +
          InstitutionalTimeframeTag(Confirm_TF) + "->" +
          InstitutionalTimeframeTag(entry_tf) + "]";
}

void UpdateInstitutionalFunnelSummary(STradingSignal &signal, string summary, string detail)
{
   signal.institutional_funnel_summary = summary;

   if(StringLen(summary) > 0 && StringFind(signal.strategy_output_summary, summary) < 0)
   {
      if(StringLen(signal.strategy_output_summary) > 0)
         signal.strategy_output_summary += " | ";
      signal.strategy_output_summary += summary;
   }

   string effective_detail = (StringLen(detail) > 0 ? detail : summary);
   if(StringLen(effective_detail) > 0 && StringFind(signal.strategy_output_detail, effective_detail) < 0)
   {
      if(StringLen(signal.strategy_output_detail) > 0)
         signal.strategy_output_detail += " | ";
      signal.strategy_output_detail += effective_detail;
   }
}

ENUM_TIMEFRAMES ResolveAdaptiveEntryTimeframe(string symbol,
                                              int symbol_index,
                                              double &volatility_factor,
                                              string &decision_out)
{
   decision_out = "base";
   volatility_factor = 1.0;

   int idx = symbol_index;
   if(idx < 0 || idx >= g_symbols_count || g_symbols[idx].name != symbol)
      idx = GetSymbolIndex(symbol);

   if(idx >= 0 && idx < g_symbols_count)
      volatility_factor = GetCachedVolatilityFactor(symbol, idx);
   if(!MathIsValidNumber(volatility_factor) || volatility_factor <= 0.0)
      volatility_factor = 1.0;

   if(Enable_Adaptive_Entry_Timeframe &&
      Adaptive_Entry_Fast_TF != PERIOD_CURRENT &&
      Adaptive_Entry_Fast_TF != Signal_TF &&
      volatility_factor >= Adaptive_Entry_HighVol_Threshold)
   {
      decision_out = "adaptive-fast";
      return Adaptive_Entry_Fast_TF;
   }

   return Signal_TF;
}

string LiquidityGateStateTag(bool passed)
{
   return (passed ? "PASS" : "MISS");
}

string BuildLiquidityFailureDetail(int direction,
                                   bool strict_mode,
                                   bool equal_level,
                                   bool confirm_sweep,
                                   bool entry_sweep,
                                   string confirm_tf_tag,
                                   string entry_tf_tag)
{
   string eq_tag = (direction == 1 ? "EqL" : "EqH");
   string missing = "";

   if(strict_mode)
   {
      if(!equal_level)
         missing = "equal level";

      if(!confirm_sweep && !entry_sweep)
      {
         if(StringLen(missing) > 0)
            missing += ", ";
         missing += "confirm sweep, entry sweep";
      }
   }
   else if(!equal_level && !confirm_sweep && !entry_sweep)
   {
      missing = "equal level, confirm sweep, entry sweep";
   }

   if(StringLen(missing) == 0)
      missing = "n/a";

   return StringFormat("[mode=%s rule=%s state %s=%s ConfirmSweep(%s)=%s EntrySweep(%s)=%s missing=%s]",
                       (strict_mode ? "STRICT" : "RELAXED"),
                       (strict_mode ? "Eq+(Confirm|Entry)" : "Any1"),
                       eq_tag,
                       LiquidityGateStateTag(equal_level),
                       confirm_tf_tag,
                       LiquidityGateStateTag(confirm_sweep),
                       entry_tf_tag,
                       LiquidityGateStateTag(entry_sweep),
                       missing);
}

bool EvaluateInstitutionalTimeframeFunnel(string symbol,
                                          int symbol_index,
                                          bool allow_range_mode,
                                          STradingSignal &signal,
                                          string stage_tag,
                                          string &reason_out)
{
   reason_out = "";
   signal.execution_tf = Signal_TF;
   signal.institutional_regime = -1;
   signal.institutional_volatility_factor = -1.0;
   signal.institutional_funnel_summary = "";

   if(!Enable_Institutional_Timeframe_Funnel)
      return true;

   int idx = symbol_index;
   if(idx < 0 || idx >= g_symbols_count || g_symbols[idx].name != symbol)
      idx = GetSymbolIndex(symbol);

   string entry_mode = "";
   double volatility_factor = 1.0;
   ENUM_TIMEFRAMES entry_tf = ResolveAdaptiveEntryTimeframe(symbol, idx, volatility_factor, entry_mode);
   signal.execution_tf = entry_tf;
   signal.institutional_volatility_factor = volatility_factor;

   int regime = DetectMarketRegime(symbol, Trend_TF);
   signal.institutional_regime = regime;

   string funnel_tag = BuildInstitutionalFunnelLabel(entry_tf);
   string regime_text = InstitutionalRegimeToString(regime);
   string stage_prefix = (StringLen(stage_tag) > 0 ? stage_tag + " funnel: " : "Signal funnel: ");
   string trend_tf_tag = InstitutionalTimeframeTag(Trend_TF);
   string primary_tf_tag = InstitutionalTimeframeTag(Primary_TF);
   string confirm_tf_tag = InstitutionalTimeframeTag(Confirm_TF);
   string entry_tf_tag = InstitutionalTimeframeTag(entry_tf);

   int direction_structure = DetectMarketStructure(symbol, Trend_TF);

   // Institutional funnel levels 2/3/4/7/8/9 are intentionally unwired:
   // trend direction, regime filtering, primary opposition, confirm opposition,
   // momentum confirmation, and entry structure no longer block signals.
   int setup_structure = DetectMarketStructure(symbol, Primary_TF);

   double ob_high = signal.order_block_high;
   double ob_low = signal.order_block_low;
   bool setup_ob = (ob_high > 0.0 && ob_low > 0.0);
   if(!setup_ob)
      setup_ob = DetectOrderBlock(symbol, Primary_TF, signal.direction, ob_high, ob_low);

   double fvg_high = signal.fvg_high;
   double fvg_low = signal.fvg_low;
   bool setup_fvg = (fvg_high > 0.0 && fvg_low > 0.0);
   if(!setup_fvg)
      setup_fvg = DetectFairValueGap(symbol, Primary_TF, signal.direction, fvg_high, fvg_low);

   if(Enable_OB_FVG_Gate && !setup_ob && !setup_fvg)
   {
      reason_out = stage_prefix + funnel_tag + " " + primary_tf_tag + " setup missing OB/FVG";
      return false;
   }

   if(setup_ob)
   {
      signal.order_block_high = ob_high;
      signal.order_block_low = ob_low;
   }
   if(setup_fvg)
   {
      signal.fvg_high = fvg_high;
      signal.fvg_low = fvg_low;
   }

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = 0.00001;

   double atr_primary = GetATRValue(symbol, Primary_TF);
   double liquidity_tolerance = MathMax(point * 12.0,
                                        (atr_primary > 0.0 ? atr_primary * g_Liquidity_Tolerance_ATR_Multiple_Active : point * 20.0));
   double liquidity_level = 0.0;
   bool equal_level = DirectorDetectEqualLevel(symbol,
                                               Primary_TF,
                                               (signal.direction < 0),
                                               g_Liquidity_Level_Lookback_Active,
                                               liquidity_tolerance,
                                               liquidity_level);
   bool confirm_sweep = (signal.direction == 1 ?
                         DirectorLiquiditySweepLow(symbol, Confirm_TF) :
                         DirectorLiquiditySweepHigh(symbol, Confirm_TF));
   bool entry_sweep = (signal.direction == 1 ?
                       DirectorLiquiditySweepLow(symbol, entry_tf) :
                       DirectorLiquiditySweepHigh(symbol, entry_tf));

   if(Enable_Institutional_Liquidity_Gate)
   {
      bool liquidity_ok = (Liquidity_Layer_Strict ?
                           (equal_level && (confirm_sweep || entry_sweep)) :
                           (equal_level || confirm_sweep || entry_sweep));
      if(!liquidity_ok)
      {
         reason_out = stage_prefix + funnel_tag + " liquidity layer incomplete " +
                      BuildLiquidityFailureDetail(signal.direction,
                                                 Liquidity_Layer_Strict,
                                                 equal_level,
                                                 confirm_sweep,
                                                 entry_sweep,
                                                 confirm_tf_tag,
                                                 entry_tf_tag);
         return false;
      }
   }

   int confirm_structure = DetectMarketStructure(symbol, Confirm_TF);

   double macd_value = 0.0;
   double stoch_value = 50.0;
   GetMomentumValues(symbol, Confirm_TF, idx, macd_value, stoch_value);
   string equal_level_tag = "None";
   if(equal_level)
      equal_level_tag = (signal.direction == 1 ? "EqL" : "EqH");

   string sweep_tag = "None";
   if(confirm_sweep && entry_sweep)
      sweep_tag = confirm_tf_tag + "+" + entry_tf_tag;
   else if(confirm_sweep)
      sweep_tag = confirm_tf_tag;
   else if(entry_sweep)
      sweep_tag = entry_tf_tag;

   string setup_tag = (setup_ob && setup_fvg ? "OB+FVG" : (setup_ob ? "OB" : "FVG"));
   string summary = StringFormat("%s Reg=%s Setup=%s Liq=%s/%s EntryTF=%s Vol=%.2f",
                                 funnel_tag,
                                 regime_text,
                                 setup_tag,
                                 equal_level_tag,
                                 sweep_tag,
                                 entry_tf_tag,
                                 volatility_factor);
   string detail = StringFormat("%s Dir=%s %s=%s %s=%s %s=%s MACD=%.3f Stoch=%.1f Mode=%s LiqLevel=%.5f",
                                funnel_tag,
                                (signal.direction == 1 ? "BUY" : "SELL"),
                                trend_tf_tag,
                                MarketStructureToString(direction_structure),
                                primary_tf_tag,
                                MarketStructureToString(setup_structure),
                                confirm_tf_tag,
                                MarketStructureToString(confirm_structure),
                                macd_value,
                                stoch_value,
                                entry_mode,
                                liquidity_level);
   UpdateInstitutionalFunnelSummary(signal, summary, detail);
   return true;
}

int GetDirectorSelectionStrategyForRank(int director_strategy_mode, int rank)
{
   if(rank < 0 || rank > 2)
      return -1;

   switch(director_strategy_mode)
   {
      case DIRECTOR_STRATEGY_KIMANIQ_RANGE:
         return (rank == 0 ? 2 : rank == 1 ? 0 : 1);
      case DIRECTOR_STRATEGY_AI_TREND:
         return (rank == 0 ? 1 : rank == 1 ? 0 : 2);
      case DIRECTOR_STRATEGY_ICT_RETRACEMENT:
      default:
         return (rank == 0 ? 0 : rank == 1 ? 2 : 1);
   }
}

string DirectorSelectionStrategyLabel(int strategy_id)
{
   if(strategy_id == 0) return "ICT";
   if(strategy_id == 1) return "AI";
   if(strategy_id == 2) return "KIM";
   return "UNKNOWN";
}

void MergeAIDiagnosticsIntoSignal(STradingSignal &target, const STradingSignal &ai_signal)
{
   if(!ai_signal.valid)
      return;

   target.ai_probability = ai_signal.ai_probability;
   target.ai_confidence = MathMax(target.ai_confidence, ai_signal.ai_confidence);
   target.ai_buy_probability = ai_signal.ai_buy_probability;
   target.ai_sell_probability = ai_signal.ai_sell_probability;
   target.ai_effective_probability = ai_signal.ai_effective_probability;
   target.ai_directional_edge = ai_signal.ai_directional_edge;
   target.ai_min_probability_required = ai_signal.ai_min_probability_required;
   target.ai_required_edge = ai_signal.ai_required_edge;
   target.ai_candle_quality_score = ai_signal.ai_candle_quality_score;
   target.ai_candle_quality_required = ai_signal.ai_candle_quality_required;
   target.ai_expected_value_r = ai_signal.ai_expected_value_r;
   target.ai_spread_to_atr = ai_signal.ai_spread_to_atr;
   target.ai_volatility_regime = ai_signal.ai_volatility_regime;
   target.ai_agrees = (target.direction != 0 && target.direction == ai_signal.direction);

   string ai_summary = BuildAISignalSummary(target, true);
   if(StringLen(ai_summary) > 0)
   {
      if(StringFind(target.strategy_output_summary, ai_summary) < 0)
      {
         if(StringLen(target.strategy_output_summary) > 0)
            target.strategy_output_summary += " | ";
         target.strategy_output_summary += ai_summary;
      }

      string ai_detail = BuildAISignalSummary(target, false);
      if(StringFind(target.strategy_output_detail, ai_detail) < 0)
      {
         if(StringLen(target.strategy_output_detail) > 0)
            target.strategy_output_detail += " | ";
         target.strategy_output_detail += ai_detail;
      }
   }
}

/**
 * ========================================
 * ACTIVE HELPER FUNCTIONS - Core functions used by bot engine and strategies
 * These MUST remain uncommented and available
 * ========================================
 */

bool TrySelectDirectorDrivenSignal(const SRoutingMatrix &route,
                                   const STradingSignal &ict_signal, bool ict_valid,
                                   const STradingSignal &ai_signal, bool ai_valid,
                                   const STradingSignal &kim_signal, bool kim_valid,
                                   STradingSignal &selected)
{
   if(!route.director_active || route.director_strategy_mode < 0)
      return false;

   for(int rank = 0; rank < 3; rank++)
   {
      if(!route.director_active || route.director_strategy_mode < 0)
         break;
      
      int strategy_id = GetDirectorSelectionStrategyForRank(route.director_strategy_mode, rank);
      if(strategy_id < 0)
         continue;

      string selection_reason = StringFormat("Director selected %s%s",
                                             DirectorStrategyModeToString((ENUM_DIRECTOR_STRATEGY_MODE)route.director_strategy_mode),
                                             (rank == 0 ? "" : " fallback"));
      if(strategy_id == 0 && ict_valid)
      {
         selected = ict_signal;
         if(ai_valid && ai_signal.direction == selected.direction)
            MergeAIDiagnosticsIntoSignal(selected, ai_signal);
         if(StringLen(selected.reason) > 0)
            selected.reason = selection_reason + " | " + selected.reason;
         else
            selected.reason = selection_reason;
         return true;
      }
      if(strategy_id == 1 && ai_valid)
      {
         selected = ai_signal;
         if(StringLen(selected.reason) > 0)
            selected.reason = selection_reason + " | " + selected.reason;
         else
            selected.reason = selection_reason;
         return true;
      }
      if(strategy_id == 2 && kim_valid)
      {
         selected = kim_signal;
         if(ai_valid && ai_signal.direction == selected.direction)
            MergeAIDiagnosticsIntoSignal(selected, ai_signal);
         if(StringLen(selected.reason) > 0)
            selected.reason = selection_reason + " | " + selected.reason;
         else
            selected.reason = selection_reason;
         return true;
      }
   }

   return false;
}

bool IsAINeutralOnlyReason(string reason)
{
   return (StringFind(reason, "AI no directional edge") != -1 ||
           StringFind(reason, "AI edge too weak") != -1);
}

bool TryBuildAIFallbackSignal(string symbol,
                              int symbol_index,
                              int trend_direction,
                              const STradingSignal &ai_signal,
                              double ai_fallback_min_prob,
                              STradingSignal &selected,
                              string &reason_out)
{
   reason_out = "";
   selected = STradingSignal();

   double ai_effective_prob = ai_signal.ai_probability;
   if(symbol_index >= 0 && IsAIPredictionFresh(symbol_index, Signal_TF))
   {
      ai_effective_prob = GetEffectiveDirectionalAIProbability(
         ai_signal.direction,
         g_ai_prediction_cache[symbol_index].buy_prob,
         g_ai_prediction_cache[symbol_index].sell_prob
      );
   }

   if(trend_direction != 0 && ai_signal.direction != trend_direction)
   {
      reason_out = "BOTH fallback blocked: AI direction conflicts with trend direction";
      return false;
   }

   bool ai_confidence_ok = (ai_effective_prob >= ai_fallback_min_prob);
   bool ai_score_ok = true;
   string fallback_block_reason = "";
   STradingSignal ai_candidate = ai_signal;

   if(ai_confidence_ok && Enable_All_Institutional_Filters)
   {
      double mid_price_fb = GetCachedMidPrice(symbol, symbol_index);
      if(mid_price_fb <= 0.0)
         mid_price_fb = ai_signal.entry_price;
      int sig_struct_fb = DetectMarketStructure(symbol, Signal_TF);
      int htf_bias_fb = GetHTFBiasInstitutional(symbol);

      ai_score_ok = ApplyScoringGate(
         symbol,
         Signal_TF,
         ai_candidate,
         ai_effective_prob,
         ai_candidate.atr_value,
         htf_bias_fb,
         "AI_FALLBACK",
         symbol_index,
         mid_price_fb,
         sig_struct_fb,
         false
      );

      if(!ai_score_ok)
         fallback_block_reason = "Scoring rejected AI fallback";
   }

   if(ai_confidence_ok && ai_score_ok)
   {
      selected = ai_candidate;
      selected.origin = SIGNAL_ORIGIN_AI;
      selected.reason = StringFormat("BOTH fallback: AI passed (prob %.2f>=%.2f)",
                                     ai_effective_prob, ai_fallback_min_prob);
      return true;
   }

   if(!ai_confidence_ok)
      reason_out = StringFormat("BOTH fallback blocked: AI probability %.2f<%.2f",
                                ai_effective_prob, ai_fallback_min_prob);
   else
      reason_out = (StringLen(ai_candidate.reason) > 0 ?
                    ai_candidate.reason :
                    "BOTH fallback blocked: " + fallback_block_reason);
   return false;
}

bool ResolveSelectedSignalFromCandidates(string symbol,
                                         int symbol_index,
                                         int trend_direction,
                                         const SRoutingMatrix &route,
                                         const STradingSignal &ict_signal, bool ict_valid,
                                         const STradingSignal &ai_signal, bool ai_valid,
                                         const STradingSignal &kim_signal, bool kim_valid,
                                         double ai_fallback_min_prob,
                                         STradingSignal &selected,
                                         string &selection_stage)
{
   selected = STradingSignal();
   selection_stage = "";

   bool kim_only = (route.kim_allowed && !route.ict_allowed && !route.ai_allowed);
   bool ict_only_route = (route.ict_allowed && !route.ai_allowed && !route.kim_allowed);
   bool ai_only_route = (!route.ict_allowed && route.ai_allowed && !route.kim_allowed);
   bool use_role_priority = (g_Enable_Auto_Regime_Router || route.suitability_enforced);
   bool prefer_kim = (use_role_priority && route.suitability_mode == AUTO_REGIME_MODE_RETRACEMENT);
   bool prefer_ai = (use_role_priority && route.suitability_mode == AUTO_REGIME_MODE_INTRA_HIGHLOW);

   // Even without the full auto-router, give each strategy first shot at its native setup.
   if(!use_role_priority)
   {
      int signal_structure = DetectMarketStructure(symbol, Signal_TF);
      bool retracement_ready = false;
      if(trend_direction == 1 || trend_direction == -1)
      {
         retracement_ready = (IsFirstRetracementAfterBOS(symbol, Signal_TF, trend_direction) ||
                              IsInDiscountZone(symbol, Signal_TF, trend_direction));
      }

      bool kim_native_retracement = (route.kim_allowed &&
                                     kim_valid &&
                                     IsDirectionalRetracementSignal(kim_signal));

      if(route.kim_allowed && (retracement_ready || kim_native_retracement))
      {
         prefer_kim = true;
         prefer_ai = false;
      }
      else if(route.ai_allowed && signal_structure == MARKET_RANGE)
      {
         prefer_ai = true;
         prefer_kim = false;
      }
   }

   if(route.director_active)
   {
      if(route.director_strategy_mode == (int)DIRECTOR_STRATEGY_KIMANIQ_RANGE)
      {
         prefer_kim = true;
         prefer_ai = false;
      }
      else if(route.director_strategy_mode == (int)DIRECTOR_STRATEGY_AI_TREND)
      {
         prefer_ai = true;
         prefer_kim = false;
      }
      else if(route.director_strategy_mode == (int)DIRECTOR_STRATEGY_ICT_RETRACEMENT)
      {
         prefer_ai = false;
         prefer_kim = false;
      }
   }

   if(route.require_both)
   {
      if(ict_valid && ai_valid && ict_signal.direction == ai_signal.direction)
      {
         selected = ict_signal;
         selected.origin = SIGNAL_ORIGIN_BOTH;
         MergeAIDiagnosticsIntoSignal(selected, ai_signal);
         selected.ai_agrees = true;
         selected.reason = "ICT and AI agreement";
         selection_stage = "BOTH";
         return true;
      }

      if(ai_valid && g_Allow_AI_Fallback_In_BOTH_Mode)
      {
         string ai_fallback_reason = "";
         if(TryBuildAIFallbackSignal(symbol, symbol_index, trend_direction,
                                     ai_signal, ai_fallback_min_prob,
                                     selected, ai_fallback_reason))
         {
            selection_stage = "AI_FALLBACK";
            return true;
         }
         selected.reason = ai_fallback_reason;
         return false;
      }

      if(ict_valid && g_Allow_ICT_Fallback_In_BOTH_Mode)
      {
         if(!ai_valid && IsAINeutralOnlyReason(ai_signal.reason))
         {
            selected = ict_signal;
            selected.origin = SIGNAL_ORIGIN_ICT;
            selected.reason = "BOTH fallback: ICT passed while AI neutral (" + ai_signal.reason + ")";
            selection_stage = "ICT_FALLBACK";
            return true;
         }

         selected.reason = "BOTH ICT fallback not allowed for AI reason: " + ai_signal.reason;
         return false;
      }

      if(!ict_valid && !ai_valid)
         selected.reason = "BOTH mode: ICT and AI signals invalid | ICT=" + ict_signal.reason +
                           " | AI=" + ai_signal.reason;
      else if(!ict_valid)
         selected.reason = "BOTH mode: ICT signal invalid | ICT=" + ict_signal.reason;
      else if(!ai_valid)
         selected.reason = "BOTH mode: AI signal invalid | AI=" + ai_signal.reason;
      else if(!g_Allow_AI_Fallback_In_BOTH_Mode)
         selected.reason = "BOTH mode: ICT/AI mismatch (AI fallback disabled)";
      else
         selected.reason = "BOTH mode: ICT/AI direction mismatch";
      return false;
   }

   if(kim_only)
   {
      selected = kim_signal;
      selection_stage = "KIM";
      if(!selected.valid && StringLen(selected.reason) == 0)
         selected.reason = "KImaniz only mode: signal invalid | KIM=" + kim_signal.reason;
      return selected.valid;
   }

   if(ict_only_route)
   {
      selected = ict_signal;
      selection_stage = "ICT";
      return selected.valid;
   }
   if(ai_only_route)
   {
      selected = ai_signal;
      selection_stage = "AI";
      return selected.valid;
   }

   if(route.director_active && TrySelectDirectorDrivenSignal(route, ict_signal, ict_valid,
                                                             ai_signal, ai_valid,
                                                             kim_signal, kim_valid,
                                                             selected))
   {
      selection_stage = "DIRECTOR";
      return true;
   }

   if(prefer_kim)
   {
      if(kim_valid)
      {
         selected = kim_signal;
         selection_stage = "KIM";
         return true;
      }
      if(ict_valid)
      {
         selected = ict_signal;
         selection_stage = "ICT";
         return true;
      }
      if(ai_valid)
      {
         selected = ai_signal;
         selection_stage = "AI";
         return true;
      }
   }
   else if(prefer_ai)
   {
      if(ai_valid)
      {
         selected = ai_signal;
         selection_stage = "AI";
         return true;
      }
      if(ict_valid)
      {
         selected = ict_signal;
         selection_stage = "ICT";
         return true;
      }
      if(kim_valid)
      {
         selected = kim_signal;
         selection_stage = "KIM";
         return true;
      }
   }
   else
   {
      if(ict_valid && ai_valid)
      {
         if(ict_signal.direction == ai_signal.direction)
         {
            selected = ict_signal;
            selected.origin = SIGNAL_ORIGIN_BOTH;
            MergeAIDiagnosticsIntoSignal(selected, ai_signal);
            selected.ai_agrees = true;
            selected.reason = "Trend role: ICT+AI confluence";
            selection_stage = "BOTH";
            return true;
         }

         int signal_structure = DetectMarketStructure(symbol, Signal_TF);
         int structure_direction = StructureToDirection(signal_structure);
         bool ict_aligned = (structure_direction == 0 || structure_direction == ict_signal.direction);
         bool ai_aligned = (structure_direction == 0 || structure_direction == ai_signal.direction);

         if(structure_direction != 0 && ict_aligned != ai_aligned)
         {
            selected = (ai_aligned ? ai_signal : ict_signal);
            selection_stage = (ai_aligned ? "AI" : "ICT");
            return true;
         }

         selected = ict_signal;
         selection_stage = "ICT";
         if(StringFind(selected.reason, "AI disagreed") < 0)
         {
            if(StringLen(selected.reason) > 0)
               selected.reason += " | ";
            selected.reason += "AI disagreed";
         }
         return true;
      }

      if(ict_valid)
      {
         selected = ict_signal;
         selection_stage = "ICT";
         return true;
      }
      if(ai_valid)
      {
         selected = ai_signal;
         selection_stage = "AI";
         return true;
      }
      if(kim_valid)
      {
         selected = kim_signal;
         selection_stage = "KIM";
         return true;
      }
   }

   selected.reason = "Either mode: no valid strategy signal | ICT=" + ict_signal.reason +
                     " | AI=" + ai_signal.reason +
                     " | KIM=" + kim_signal.reason;
   return false;
}

void AppendRoutingContextToSignal(const SRoutingMatrix &route, STradingSignal &signal)
{
   if(!(g_Enable_Auto_Regime_Router || route.suitability_enforced))
      return;

   string role_tag_key = (g_Enable_Auto_Regime_Router ? "AutoRegime=" : "SuitabilityRole=");
   string role_tag = role_tag_key + AutoRegimeModeToString(route.suitability_mode);
   string hunt_tag = "HuntMode=" + SuitabilityHuntModeToString(g_Suitability_Hunt_Mode);
   string director_tag = "";

   if(route.director_active)
   {
      string director_strategy = "UNKNOWN";
      if(route.director_strategy_mode >= 0)
         director_strategy = DirectorStrategyModeToString((ENUM_DIRECTOR_STRATEGY_MODE)route.director_strategy_mode);
      director_tag = " | DirectorStrategy=" + director_strategy +
                     " | DirectorLotMult=" + DoubleToString(route.director_lot_multiplier, 2);
   }

   string context = role_tag + " | " + hunt_tag + director_tag;
   if(StringLen(signal.reason) > 0)
      signal.reason += " | " + context;
   else
      signal.reason = context;
}

bool FinalizeSelectedSignal(string symbol,
                            int symbol_index,
                            bool allow_range_mode,
                            int trend_direction,
                            const SRoutingMatrix &route,
                            string stage_tag,
                            STradingSignal &signal)
{
   if(!signal.valid)
      return false;

   string effective_stage = (StringLen(stage_tag) > 0 ? stage_tag : "FINAL");
   bool allow_countertrend_signal = IsCountertrendRetracementSignal(signal);
   bool allow_retracement_continuation = IsHTFAlignedRetracementContinuationContext(symbol, trend_direction, signal);
   if(!HardenStrategySignal(symbol, symbol_index, allow_range_mode, trend_direction, signal, effective_stage))
      return false;

   if(allow_countertrend_signal)
   {
      int signal_tf_direction = 0;
      bool signal_tf_decisive = false;
      if(!GetDirectionalCoreTimeframeState(symbol, Signal_TF, signal_tf_direction, signal_tf_decisive) ||
         !signal_tf_decisive ||
         signal_tf_direction != signal.direction)
      {
         signal.valid = false;
         signal.reason = "Execution gate: countertrend retracement lost Signal_TF confirmation";
         return false;
      }
   }
   else if(allow_retracement_continuation)
   {
      string execution_alignment_reason = "";
      if(!ValidateRetracementContinuationCoreTimeframes(symbol, signal.direction,
                                                        GetExecutionAlignedCoreTimeframeRequirement(),
                                                        "Execution gate", execution_alignment_reason))
      {
         signal.valid = false;
         signal.reason = execution_alignment_reason;
         return false;
      }
   }
   else
   {
      string execution_alignment_reason = "";
      if(!ValidateMinimumAlignedCoreTimeframes(symbol, signal.direction,
                                               GetExecutionAlignedCoreTimeframeRequirement(),
                                               "Execution gate", execution_alignment_reason))
      {
         signal.valid = false;
         signal.reason = execution_alignment_reason;
         return false;
      }
   }

   string integrity_reason = "";
   if(!FinalIntegrityGate(symbol, symbol_index, allow_range_mode, signal, integrity_reason,
                          true, trend_direction))
   {
      signal.valid = false;
      signal.reason = integrity_reason;
      return false;
   }

   int final_signal_structure = DetectMarketStructure(symbol, Signal_TF);
   if(final_signal_structure == MARKET_RANGE && !allow_range_mode)
   {
      signal.valid = false;
      signal.reason = "Final range gate blocked signal before alert/queue";
      return false;
   }

   bool allow_neutral_context = (allow_range_mode || g_Allow_Neutral_Trend_Trading);
   bool allow_kim_range_signal = (allow_range_mode && signal.origin == SIGNAL_ORIGIN_KIMANIZ);
   int final_trend_direction = GetTrendDirection(symbol);
   if(final_trend_direction == 0)
   {
      if(!allow_neutral_context)
      {
         signal.valid = false;
         signal.reason = "Final trend class neutral gate blocked signal before alert/queue";
         return false;
      }
   }
   else if(signal.direction != final_trend_direction && !allow_countertrend_signal && !allow_kim_range_signal)
   {
      signal.valid = false;
      signal.reason = "Final trend class gate blocked counter-trend signal (signal=" +
                      IntegerToString(signal.direction) + ", trend=" +
                      IntegerToString(final_trend_direction) + ")";
      return false;
   }

   AppendRoutingContextToSignal(route, signal);
   return true;
}

// Structured debug helper for institutional-grade traceability
void LogInstitutionalSignal(string stage, string symbol, const STradingSignal &signal, int htf_bias,
                            int signal_tf_structure, double current_price, double spread_points,
                            double atr_value, string diag_txt)
{
   if(!g_Enable_Institutional_Debug)
      return;

   string ai_prob_txt = ((signal.origin == SIGNAL_ORIGIN_AI || SignalHasAIDiagnostics(signal) || signal.ai_agrees) ?
                         DoubleToString(signal.ai_probability, 2) : "NA");
   string ai_conf_txt = ((signal.origin == SIGNAL_ORIGIN_AI || SignalHasAIDiagnostics(signal) || signal.ai_agrees) ?
                         DoubleToString(signal.ai_confidence, 2) : "NA");
   string msg = StringFormat(
      "%s | ORG:%s | DIR:%s | HTF:%s | SigTF:%s | Price:%.2f | Entry:%.2f | SL:%.2f | TP:%.2f | RR:%.2f | Dist:%.2f%% | Spread:%.1fp | ATR:%.2f | AIprob:%s | AIconf:%s | Reason:%s",
      stage,
      SignalOriginToString(signal.origin),
      (signal.direction==1 ? "BUY" : signal.direction==-1 ? "SELL" : "NA"),
      (htf_bias==1 ? "BULL" : htf_bias==-1 ? "BEAR" : "NEUTRAL"),
      MarketStructureToString(signal_tf_structure),
      current_price,
      signal.entry_price, signal.stop_loss, signal.take_profit, signal.risk_reward_ratio,
      (current_price>0 ? MathAbs(signal.entry_price-current_price)/current_price*100.0 : 0.0),
      spread_points,
      atr_value,
      ai_prob_txt,
      ai_conf_txt,
      (StringLen(signal.reason)>0 ? signal.reason : "OK")
   );

   string strategy_summary = BuildStrategyOutputSummary(signal, false);
   if(StringLen(strategy_summary) > 0)
      msg += " | " + strategy_summary;

   if(StringLen(diag_txt) > 0)
      msg += " | " + diag_txt;

   Log(LOG_DETAILED, "InstDebug", symbol + " - " + msg);
}

string CompactStrategyDiagnosticReason(string reason)
{
   if(StringLen(reason) <= 0)
      return "n/a";

   string compact = reason;
   StringReplace(compact, "\r", " ");
   StringReplace(compact, "\n", " ");
   StringTrimLeft(compact);
   StringTrimRight(compact);

   if(StringLen(compact) > 72)
      compact = StringSubstr(compact, 0, 72) + "...";

   return compact;
}

string DescribeStrategyCandidateState(string label,
                                      bool probed,
                                      const STradingSignal &signal,
                                      bool valid)
{
   string status = "OFF";
   if(probed)
      status = (valid ? "READY" : "MISS");

   string direction =
      (signal.direction == 1 ? "BUY" :
       signal.direction == -1 ? "SELL" : "NA");
   string origin = SignalOriginToString(signal.origin);
   string reason = CompactStrategyDiagnosticReason(signal.reason);

   return label + "=" + status +
          "{dir=" + direction +
          ",org=" + origin +
          ",why=" + reason + "}";
}

void LogStrategyCandidateSnapshot(string scope,
                                  string symbol,
                                  const SRoutingMatrix &route,
                                  bool probe_ict,
                                  bool probe_ai,
                                  bool probe_kim,
                                  const STradingSignal &ict_signal,
                                  bool ict_valid,
                                  const STradingSignal &ai_signal,
                                  bool ai_valid,
                                  const STradingSignal &kim_signal,
                                  bool kim_valid,
                                  const STradingSignal &selected_signal,
                                  string selection_stage)
{
   if(!g_Enable_Institutional_Debug)
      return;

   string selected_dir =
      (selected_signal.direction == 1 ? "BUY" :
       selected_signal.direction == -1 ? "SELL" : "NA");
   string selected_origin = SignalOriginToString(selected_signal.origin);
   string selected_status = (selected_signal.valid ? "READY" : "NONE");
   string selected_reason = CompactStrategyDiagnosticReason(selected_signal.reason);
   string stage = (StringLen(selection_stage) > 0 ? selection_stage : "UNRESOLVED");

   string route_txt =
      "route{ICT=" + (route.ict_allowed ? "Y" : "N") +
      ",AI=" + (route.ai_allowed ? "Y" : "N") +
      ",KIM=" + (route.kim_allowed ? "Y" : "N") +
      ",BOTH=" + (route.require_both ? "Y" : "N") + "}";
   string probe_txt =
      " probe{ICT=" + (probe_ict ? "Y" : "N") +
      ",AI=" + (probe_ai ? "Y" : "N") +
      ",KIM=" + (probe_kim ? "Y" : "N") + "}";
   string candidate_txt =
      " cand[" +
      DescribeStrategyCandidateState("ICT", probe_ict, ict_signal, ict_valid) + " | " +
      DescribeStrategyCandidateState("AI", probe_ai, ai_signal, ai_valid) + " | " +
      DescribeStrategyCandidateState("KIM", probe_kim, kim_signal, kim_valid) + "]";
   string selected_txt =
      " final=" + selected_status +
      "{stage=" + stage +
      ",org=" + selected_origin +
      ",dir=" + selected_dir +
      ",why=" + selected_reason + "}";

   Log(LOG_DEBUG, scope, symbol + " - " + route_txt + probe_txt + candidate_txt + selected_txt);
}

string NormalizeRejectReason(string reason)
{
   string r = reason;
   if(StringLen(r) <= 0)
      return "UNKNOWN";

   string stage = "";
   int first_colon = StringFind(r, ":");
   if(first_colon > 0)
   {
      string possible_stage = StringSubstr(r, 0, first_colon);
      if(possible_stage == "ICT" || possible_stage == "AI" || possible_stage == "FINAL" ||
         possible_stage == "KIM" || possible_stage == "PIPE" || possible_stage == "ROUTE" ||
         possible_stage == "EXECQ" || possible_stage == "RETRY" ||
         possible_stage == "BROKER")
      {
         stage = possible_stage;
         r = StringSubstr(r, first_colon + 1);
      }
   }

   StringTrimLeft(r);
   StringTrimRight(r);

   int pipe_pos = StringFind(r, "|");
   if(pipe_pos > 0)
      r = StringSubstr(r, 0, pipe_pos);

   int paren_pos = StringFind(r, "(");
   if(paren_pos > 0)
      r = StringSubstr(r, 0, paren_pos);

   StringTrimLeft(r);
   StringTrimRight(r);
   if(StringLen(r) > 72)
      r = StringSubstr(r, 0, 72);

   if(StringLen(r) <= 0)
      r = "UNKNOWN";

   if(StringLen(stage) > 0)
      return stage + "|" + r;
   return r;
}

void RecordRejectReason(string reason)
{
   string key = NormalizeRejectReason(reason);
   g_last_reject_reason_key = key;
   g_last_reject_reason_time = TimeCurrent();
   int empty_slot = -1;

   for(int i = 0; i < MAX_REJECT_REASON_BUCKETS; i++)
   {
      if(g_reject_reason_keys[i] == key)
      {
         if(g_reject_reason_counts[i] < 2147483647)
            g_reject_reason_counts[i]++;
         return;
      }
      if(empty_slot < 0 && StringLen(g_reject_reason_keys[i]) == 0)
         empty_slot = i;
   }

   if(empty_slot >= 0)
   {
      g_reject_reason_keys[empty_slot] = key;
      g_reject_reason_counts[empty_slot] = 1;
      return;
   }

   // Replace the smallest bucket when full.
   int min_idx = 0;
   int min_val = g_reject_reason_counts[0];
   for(int i = 1; i < MAX_REJECT_REASON_BUCKETS; i++)
   {
      if(g_reject_reason_counts[i] < min_val)
      {
         min_val = g_reject_reason_counts[i];
         min_idx = i;
      }
   }
   g_reject_reason_keys[min_idx] = key;
   g_reject_reason_counts[min_idx] = min_val + 1;
}

void ResetRejectReasonBuckets()
{
   for(int i = 0; i < MAX_REJECT_REASON_BUCKETS; i++)
   {
      g_reject_reason_keys[i] = "";
      g_reject_reason_counts[i] = 0;
   }
   g_last_reject_reason_key = "";
   g_last_reject_reason_time = 0;
}

string GetTopRejectReasonsSummary(int top_n = 3)
{
   string summary = "";
   bool used[MAX_REJECT_REASON_BUCKETS];
   for(int i = 0; i < MAX_REJECT_REASON_BUCKETS; i++)
      used[i] = false;

   int picked = 0;
   while(picked < top_n)
   {
      int best_idx = -1;
      int best_val = 0;
      for(int i = 0; i < MAX_REJECT_REASON_BUCKETS; i++)
      {
         if(used[i] || StringLen(g_reject_reason_keys[i]) == 0)
            continue;
         if(g_reject_reason_counts[i] > best_val)
         {
            best_val = g_reject_reason_counts[i];
            best_idx = i;
         }
      }

      if(best_idx < 0)
         break;

      used[best_idx] = true;
      if(StringLen(summary) > 0)
         summary += " | ";
      summary += g_reject_reason_keys[best_idx] + "=" + IntegerToString(g_reject_reason_counts[best_idx]);
      picked++;
   }

   if(StringLen(summary) == 0)
      summary = "n/a";

   return summary;
}

string GetRejectStageSummary()
{
   int ict = 0, ai = 0, kim = 0, final_stage = 0, pipe = 0, route = 0, execq = 0, retry = 0, broker = 0, other = 0;

   for(int i = 0; i < MAX_REJECT_REASON_BUCKETS; i++)
   {
      if(StringLen(g_reject_reason_keys[i]) == 0 || g_reject_reason_counts[i] <= 0)
         continue;

      string key = g_reject_reason_keys[i];
      string stage = "OTHER";
      int sep = StringFind(key, "|");
      if(sep > 0)
         stage = StringSubstr(key, 0, sep);

      int c = g_reject_reason_counts[i];
      if(stage == "ICT") ict += c;
      else if(stage == "AI") ai += c;
      else if(stage == "KIM") kim += c;
      else if(stage == "FINAL") final_stage += c;
      else if(stage == "PIPE") pipe += c;
      else if(stage == "ROUTE") route += c;
      else if(stage == "EXECQ") execq += c;
      else if(stage == "RETRY") retry += c;
      else if(stage == "BROKER") broker += c;
      else other += c;
   }

   string out = "";
   if(ict > 0) out += "ICT=" + IntegerToString(ict);
   if(ai > 0) out += (StringLen(out) > 0 ? " | " : "") + "AI=" + IntegerToString(ai);
   if(kim > 0) out += (StringLen(out) > 0 ? " | " : "") + "KIM=" + IntegerToString(kim);
   if(final_stage > 0) out += (StringLen(out) > 0 ? " | " : "") + "FINAL=" + IntegerToString(final_stage);
   if(pipe > 0) out += (StringLen(out) > 0 ? " | " : "") + "PIPE=" + IntegerToString(pipe);
   if(route > 0) out += (StringLen(out) > 0 ? " | " : "") + "ROUTE=" + IntegerToString(route);
   if(execq > 0) out += (StringLen(out) > 0 ? " | " : "") + "EXECQ=" + IntegerToString(execq);
   if(retry > 0) out += (StringLen(out) > 0 ? " | " : "") + "RETRY=" + IntegerToString(retry);
   if(broker > 0) out += (StringLen(out) > 0 ? " | " : "") + "BROKER=" + IntegerToString(broker);
   if(other > 0) out += (StringLen(out) > 0 ? " | " : "") + "OTHER=" + IntegerToString(other);

   if(StringLen(out) == 0)
      out = "n/a";

   return out;
}

/**
 * ========================================
 * ACTIVE HELPER FUNCTIONS - Core functions required by bot engine and strategies
 * ========================================
 */

void MonitorSignalGeneration()
{
   static datetime last_monitor = 0;
   datetime now = TimeCurrent();
   
   if(now - last_monitor >= 60) // Every minute
   {
      last_monitor = now;

      int pending_orders = 0;
      for(int oi = OrdersTotal() - 1; oi >= 0; oi--)
      {
         ulong oticket = OrderGetTicket(oi);
         if(oticket == 0 || !OrderSelect(oticket))
            continue;

         long otype = OrderGetInteger(ORDER_TYPE);
         if(otype != ORDER_TYPE_BUY_LIMIT && otype != ORDER_TYPE_SELL_LIMIT &&
            otype != ORDER_TYPE_BUY_STOP && otype != ORDER_TYPE_SELL_STOP &&
            otype != ORDER_TYPE_BUY_STOP_LIMIT && otype != ORDER_TYPE_SELL_STOP_LIMIT)
            continue;

         long omagic = OrderGetInteger(ORDER_MAGIC);
         if(omagic >= Magic_Base && omagic < Magic_Base + 10000)
            pending_orders++;
      }
      
      Print("[MONITOR] Signal Stats - Generated: ", g_debug_counters.signals_generated,
            ", Valid: ", g_debug_counters.signals_valid,
            ", Queued: ", g_debug_counters.trades_queued,
            ", Executed: ", g_debug_counters.trades_executed,
            ", PendingOpen: ", pending_orders,
            ", RetryQueue: ", g_retry_count,
            ", LastPipelineAgeSec: ", (g_last_process_time > 0 ? (int)(now - g_last_process_time) : -1),
            ", InitComplete: ", (g_initialization_complete ? "Y" : "N"),
            ", TradeAllowed: ", (IsTradeAllowed() ? "Y" : "N"),
            ", DailyBudget: ", (HasDailyTradeBudget() ? "Y" : "N"),
            ", Symbols: ", g_symbols_count);

      Print("[MONITOR] Exec Metrics - LatencyBlocks: ", g_exec_latency_blocks,
            ", SmartReroutes: ", g_exec_slippage_reroutes,
            ", SlippageBreaches: ", g_exec_slippage_violations,
            ", KillSwitch: ", (IsKillSwitchActive() ? "Y" : "N"),
            ", KillTriggers: ", g_kill_switch_triggers);
      string exec_audit_msg = "LatencyBlocks=" + IntegerToString(g_exec_latency_blocks) +
                              " SmartReroutes=" + IntegerToString(g_exec_slippage_reroutes) +
                              " SlippageBreaches=" + IntegerToString(g_exec_slippage_violations) +
                              " KillSwitch=" + (IsKillSwitchActive() ? "Y" : "N") +
                              " KillTriggers=" + IntegerToString(g_kill_switch_triggers);
      AuditLog("MONITOR_EXEC", "", exec_audit_msg);
            
      // Check retry queue status
      if(g_retry_count > 0)
      {
         Print("[MONITOR] Retry Queue: ", g_retry_count, " pending trades");
      }

      if(g_debug_counters.signals_generated > 0 && g_debug_counters.signals_valid == 0)
      {
         Print("[MONITOR] Top Reject Reasons: ", GetTopRejectReasonsSummary(5));
      }
      else if(g_debug_counters.signals_valid > 0 && g_debug_counters.trades_queued == 0)
      {
         Print("[MONITOR] Pipeline Blocked at Queue Stage. Top Reasons: ", GetTopRejectReasonsSummary(5));
      }
      else if(g_debug_counters.trades_queued > 0 && g_debug_counters.trades_executed == 0)
      {
         Print("[MONITOR] Pipeline Blocked at Execution Stage. Top Reasons: ", GetTopRejectReasonsSummary(5));
      }

      if(g_debug_counters.signals_generated > 0)
      {
         Print("[MONITOR] Reject Stage Mix: ", GetRejectStageSummary());
      }
   }
}


//====================================================================
// SAFE RETRY QUEUE MANAGEMENT - CRITICAL FIX
//====================================================================
void RemoveRetryQueueItem(int index)
{
   if(index < 0 || index >= g_retry_count || index >= MAX_RETRY_QUEUE || g_retry_count <= 0)
   {
      Log(LOG_ERROR, "RemoveRetryQueueItem", "Invalid index: " + IntegerToString(index) + ", count: " + IntegerToString(g_retry_count));
      return;
   }
   
   for(int j = index; j < g_retry_count - 1; j++)
   {
      if(j + 1 >= MAX_RETRY_QUEUE)
         break;
      g_trade_retries[j] = g_trade_retries[j + 1];
   }
   
   g_retry_count--;
   if(g_retry_count >= 0 && g_retry_count < MAX_RETRY_QUEUE)
   {
      g_trade_retries[g_retry_count].symbol = "";
      g_trade_retries[g_retry_count].attempt = 0;
      g_trade_retries[g_retry_count].next_retry = 0;
      g_trade_retries[g_retry_count].created_time = 0;
      g_trade_retries[g_retry_count].symbol_index = -1;
      g_trade_retries[g_retry_count].signal_fingerprint = 0;
   }
}

void PruneStaleRetryQueue()
{
   if(g_retry_count <= 0)
      return;

   int max_age_seconds = MathMax(60, g_Max_Queued_Signal_Age_Minutes * 60);
   datetime now = TimeCurrent();

   for(int i = g_retry_count - 1; i >= 0; i--)
   {
      if(i < 0 || i >= MAX_RETRY_QUEUE)
         continue;

      bool malformed = (StringLen(g_trade_retries[i].symbol) == 0);
      bool stale = false;
      int age_seconds = 0;
      if(g_trade_retries[i].created_time > 0)
      {
         age_seconds = (int)(now - g_trade_retries[i].created_time);
         stale = (age_seconds > max_age_seconds);
      }

      if(malformed || stale)
      {
         string why = malformed ? "malformed queue entry" :
                      ("stale queued signal age=" + IntegerToString(age_seconds) + "s (max " + IntegerToString(max_age_seconds) + "s)");
         Log(LOG_INFO, "PruneStaleRetryQueue", "Removing " + g_trade_retries[i].symbol + " - " + why);
         RemoveRetryQueueItem(i);
      }
   }
}

// ATOMIC LOCK MANAGEMENT - RACE CONDITION FIX
static bool g_lock_acquired = false;
static datetime g_lock_timeout = 0;

bool AcquireProcessingLock()
{
   datetime current_time = TimeCurrent();
   
   // Check for stale lock (timeout after 30 seconds)
   if(g_lock_acquired && (current_time - g_lock_timeout) > 30)
   {
      Log(LOG_ERROR, "AcquireProcessingLock", "Stale lock detected, forcing release");
      g_lock_acquired = false;
      g_processing_signals = false;
      g_lock_acquisition_time = 0;
   }
   
   if(g_lock_acquired)
      return false;
      
   g_lock_acquired = true;
   g_lock_timeout = current_time;
   g_processing_signals = true;
   g_lock_acquisition_time = current_time;
   return true;
}

void ReleaseProcessingLock()
{
   g_lock_acquired = false;
   g_lock_timeout = 0;
   g_processing_signals = false;
   g_lock_acquisition_time = 0;
}

void InvalidateSymbolRuntimeCaches(int symbol_index, bool reset_bias_cache = false)
{
   if(symbol_index < 0 || symbol_index >= g_symbols_count || symbol_index >= MAX_SYMBOLS)
      return;

   for(int tf = 0; tf < STRATEGY_TF_SLOTS; tf++)
   {
      g_indicator_cache[symbol_index][tf].is_valid = false;
      g_momentum_cache[symbol_index][tf].valid = false;
      g_momentum_cache[symbol_index][tf].bar_time = 0;
   }

   g_ai_feature_cache[symbol_index].is_valid = false;
   g_ai_feature_cache[symbol_index].bar_time = 0;
   g_ai_feature_cache[symbol_index].last_update = 0;
   g_ai_feature_cache[symbol_index].last_tick_msc = 0;
   g_volatility_cache[symbol_index].last_bar_time = 0;
   g_volatility_cache[symbol_index].last_update = 0;
   g_volatility_cache[symbol_index].last_tick_msc = 0;
   g_symbols[symbol_index].cache.last_rates_update = 0;
   g_symbols[symbol_index].cache.last_rates_bar_time = 0;
   g_symbols[symbol_index].cache.last_rates_tf = PERIOD_CURRENT;
   g_symbols[symbol_index].cache.last_rates_tick_msc = 0;

   if(reset_bias_cache)
   {
      ResetAIPredictionCacheEntry(symbol_index);
      for(int slot = 0; slot < MAX_TF_CACHE; slot++)
      {
         g_htf_bias_cache[symbol_index][slot] = 0;
         g_htf_bias_cache_time[symbol_index][slot] = 0;
         g_htf_bias_calc_time[symbol_index][slot] = 0;
      }
   }
}

string SignalOriginToString(ENUM_SIGNAL_ORIGIN origin)
{
   switch(origin)
   {
      case SIGNAL_ORIGIN_ICT:  return "ICT";
      case SIGNAL_ORIGIN_AI:   return "AI";
      case SIGNAL_ORIGIN_BOTH: return "BOTH";
      case SIGNAL_ORIGIN_KIMANIZ: return "KIMANIZ";
      default:                 return "UNKNOWN";
   }
}

double ClampUnitProbability(double value)
{
   if(!MathIsValidNumber(value))
      return 0.5;
   return MathMax(0.0, MathMin(1.0, value));
}

double GetRawDirectionalAIProbability(int direction, double buy_prob, double sell_prob)
{
   double buy_p = ClampUnitProbability(buy_prob);
   double sell_p = ClampUnitProbability(sell_prob);

   if(direction == 1)
      return buy_p;
   if(direction == -1)
      return sell_p;

   return MathMax(buy_p, sell_p);
}

double GetEffectiveDirectionalAIProbability(int direction, double buy_prob, double sell_prob)
{
   double buy_p = ClampUnitProbability(buy_prob);
   double sell_p = ClampUnitProbability(sell_prob);
   double dir_prob = GetRawDirectionalAIProbability(direction, buy_p, sell_p);
   double opp_prob = (direction == 1 ? sell_p : direction == -1 ? buy_p : MathMin(buy_p, sell_p));

   double sum = dir_prob + opp_prob;
   double relative_prob = (sum > 1e-6 ? dir_prob / sum : dir_prob);
   double neutral_band = MathMax(0.0, g_AI_Neutral_Band);
   double edge = dir_prob - opp_prob;
   double edge_scale = MathMax(0.05, neutral_band + 0.05);
   double edge_score = ClampUnitProbability(0.5 + 0.5 * (edge / edge_scale));
   double hermite_conf = AIInferenceEngine::GetConfidence(dir_prob);

   // Blend raw directional probability with class-separation quality.
   double effective_prob = 0.50 * dir_prob + 0.20 * relative_prob + 0.20 * edge_score + 0.10 * hermite_conf;
   return ClampUnitProbability(effective_prob);
}

// ------------------------------------------------------------------
// Common signal helpers to keep strategy pipelines aligned
// ------------------------------------------------------------------
bool RunCommonSignalPrechecks(string symbol, STradingSignal &signal, int &symbol_index,
                              bool check_session = true, bool check_gold = true,
                              bool allow_range_mode = false,
                              bool has_seeded_trend_direction = false,
                              int seeded_trend_direction = 0)
{
   signal.signal_time = TimeCurrent();

   if(IsStopped())
   {
      signal.reason = "EA is stopping";
      return false;
   }

   symbol_index = GetSymbolIndex(symbol);
   if(symbol_index < 0 || symbol_index >= g_symbols_count)
   {
      signal.reason = "Symbol not in array or index invalid";
      Log(LOG_WARNING, "SignalPrecheck", symbol + " - " + signal.reason);
      return false;
   }

   if(g_symbols[symbol_index].name != symbol)
   {
      signal.reason = "Symbol index validation failed - name mismatch";
      Log(LOG_ERROR, "SignalPrecheck", symbol + " - " + signal.reason);
      return false;
   }

   if(!IsValidSymbol(symbol))
   {
      signal.reason = "Invalid symbol";
      Log(LOG_WARNING, "SignalPrecheck", symbol + " - " + signal.reason);
      return false;
   }

   if(check_gold && !ValidateGoldTradingConditions(symbol))
   {
      if(g_DryRun_TradeBlock_Active && g_Enable_Strategy_DryRun_On_TradeBlock)
      {
         signal.reason = "GOLD trading conditions not met (dry-run diagnostics mode)";
         Log(LOG_DEBUG, "SignalPrecheck", symbol + " - " + signal.reason);
      }
      else
      {
         signal.reason = "GOLD trading conditions not met";
         Log(LOG_INFO, "SignalPrecheck", symbol + " - " + signal.reason);
         return false;
      }
   }

    if(!IsTradeAllowed(symbol))
    {
       if(g_DryRun_TradeBlock_Active && g_Enable_Strategy_DryRun_On_TradeBlock)
       {
         signal.reason = "Trade not allowed (dry-run diagnostics mode)";
         Log(LOG_DEBUG, "SignalPrecheck", symbol + " - " + signal.reason);
      }
      else
      {
         signal.reason = "Trade not allowed";
         Log(LOG_WARNING, "SignalPrecheck", symbol + " - " + signal.reason);
         return false;
       }
    }

    if(!HasDailyTradeBudget())
    {
       signal.reason = "Daily trade budget exhausted";
       Log(LOG_WARNING, "SignalPrecheck", symbol + " - " + signal.reason);
       return false;
    }

    if(IsSymbolLossCooldownActive(symbol))
    {
       signal.reason = "Symbol loss cooldown active";
       Log(LOG_WARNING, "SignalPrecheck", symbol + " - " + signal.reason);
       return false;
   }

   if(!IsMarketOpen(symbol))
   {
      signal.reason = "Market closed";
      Log(LOG_INFO, "SignalPrecheck", symbol + " - " + signal.reason);
      return false;
   }

   if(check_session && !IsWithinTradingSession())
   {
      signal.reason = "Outside trading session";
      Log(LOG_DEBUG, "SignalPrecheck", symbol + " - " + signal.reason);
      return false;
   }

   if(!RefreshSymbolCache(symbol_index))
   {
      signal.reason = "Failed to refresh cache";
      Log(LOG_WARNING, "SignalPrecheck", symbol + " - " + signal.reason);
      return false;
   }

   double cache_bid = g_symbols[symbol_index].cache.bid;
   double cache_ask = g_symbols[symbol_index].cache.ask;
   if(cache_bid <= 0.0 || cache_ask <= 0.0 || cache_bid >= cache_ask)
   {
      signal.reason = "Quote cache invalid";
      Log(LOG_WARNING, "SignalPrecheck", symbol + " - " + signal.reason);
      return false;
   }

   datetime last_quote_time = g_symbols[symbol_index].cache.last_tick_time;
   if(last_quote_time <= 0)
      last_quote_time = g_symbols[symbol_index].cache.last_update;
   int max_quote_age_seconds = MathMax(180, Signal_Check_Seconds * 6);
   if(last_quote_time <= 0 || TimeCurrent() < last_quote_time ||
      (TimeCurrent() - last_quote_time) > max_quote_age_seconds)
   {
      signal.reason = "Quote cache stale";
      Log(LOG_WARNING, "SignalPrecheck", symbol + " - " + signal.reason +
          " (age limit " + IntegerToString(max_quote_age_seconds) + "s)");
      return false;
   }

   string range_reason = "";
   if(!allow_range_mode && IsMarketRanging(symbol, range_reason))
   {
      signal.reason = "Ranging market blocked: " + range_reason;
      Log(LOG_INFO, "SignalPrecheck", symbol + " - " + signal.reason);
      return false;
   }

   int trend_direction = ResolveHTFBiasForSignalPass(symbol,
                                                     has_seeded_trend_direction,
                                                     seeded_trend_direction);
   if(trend_direction == 0 && !allow_range_mode && !g_Allow_Neutral_Trend_Trading)
   {
      signal.reason = "Calculated trend neutral - trading blocked";
      Log(LOG_INFO, "SignalPrecheck", symbol + " - " + signal.reason);
      return false;
   }

   return true;
}

bool RunCommonSignalPostChecks(string symbol, int symbol_index, STradingSignal &signal)
{
   bool dry_run_trade_block = (g_DryRun_TradeBlock_Active && g_Enable_Strategy_DryRun_On_TradeBlock);

   if(!CanExecuteTradeToday())
   {
      if(dry_run_trade_block)
      {
         signal.reason = "Daily trade cap reached (dry-run diagnostics mode)";
         Log(LOG_DEBUG, "SignalPostcheck", symbol + " - " + signal.reason);
      }
      else
      {
         signal.reason = "Daily trade cap reached";
         Log(LOG_INFO, "SignalPostcheck", symbol + " - " + signal.reason);
         return false;
      }
   }

   if(IsLossCooldownActive())
   {
      if(dry_run_trade_block)
      {
         signal.reason = "Loss cooldown active (dry-run diagnostics mode)";
         Log(LOG_DEBUG, "SignalPostcheck", symbol + " - " + signal.reason);
      }
      else
      {
         signal.reason = "Loss cooldown active";
         Log(LOG_INFO, "SignalPostcheck", symbol + " - " + signal.reason);
         return false;
      }
   }

   if(IsDrawdownLimitExceeded())
   {
      if(dry_run_trade_block)
      {
         signal.reason = "Drawdown limit exceeded (dry-run diagnostics mode)";
         Log(LOG_DEBUG, "SignalPostcheck", symbol + " - " + signal.reason);
      }
      else
      {
         signal.reason = "Drawdown limit exceeded";
         Log(LOG_WARNING, "SignalPostcheck", symbol + " - " + signal.reason);
         return false;
      }
   }

   if(!HasSufficientVolume(symbol))
   {
      if(dry_run_trade_block)
      {
         signal.reason = "Insufficient volume (dry-run diagnostics mode)";
         Log(LOG_DEBUG, "SignalPostcheck", symbol + " - " + signal.reason);
      }
      else
      {
         signal.reason = "Insufficient volume";
         Log(LOG_WARNING, "SignalPostcheck", symbol + " - " + signal.reason);
         return false;
      }
   }

   if(!IsSpreadAcceptable(symbol))
   {
      if(dry_run_trade_block)
      {
         signal.reason = "Spread too high (dry-run diagnostics mode)";
         Log(LOG_DEBUG, "SignalPostcheck", symbol + " - " + signal.reason);
      }
      else
      {
         signal.reason = "Spread too high";
         Log(LOG_WARNING, "SignalPostcheck", symbol + " - " + signal.reason);
         return false;
      }
   }

   return true;
}

bool HardenStrategySignal(string symbol,
                          int symbol_index,
                          bool allow_range_mode,
                          int trend_direction,
                          STradingSignal &signal,
                          string stage_tag)
{
   if(!signal.valid)
      return false;

   string stage_prefix = (StringLen(stage_tag) > 0 ? stage_tag + " hardening: " : "Signal hardening: ");
   bool allow_countertrend_signal = IsCountertrendRetracementSignal(signal);
   string shape_reason = "";
   if(!IsSignalTradeShapeValid(signal, shape_reason))
   {
      signal.valid = false;
      signal.reason = stage_prefix + "invalid trade shape (" + shape_reason + ")";
      return false;
   }

   STradeLevelContext trade_ctx;
   string trade_ctx_error = "";
   if(!BuildTradeLevelContext(symbol, symbol_index, trade_ctx, trade_ctx_error))
   {
      signal.valid = false;
      signal.reason = stage_prefix + trade_ctx_error;
      return false;
   }

   int idx = trade_ctx.symbol_index;
   double point = trade_ctx.point;
   int levels_reason = TRADE_LEVELS_OK;
   if(!NormalizeAndValidateTradeLevels(symbol, trade_ctx,
                                       signal.entry_price, signal.stop_loss, signal.take_profit,
                                       levels_reason))
   {
      signal.valid = false;
      signal.reason = stage_prefix + "trade levels invalid after normalization [" +
                      TradeLevelsReasonLabel(levels_reason) + "]";
      return false;
   }

   if(!IsSignalTradeShapeValid(signal, shape_reason))
   {
      signal.valid = false;
      signal.reason = stage_prefix + "direction/layout mismatch (" + shape_reason + ")";
      return false;
   }

   double risk_distance = MathAbs(signal.entry_price - signal.stop_loss);
   if(risk_distance <= point)
   {
      signal.valid = false;
      signal.reason = stage_prefix + "risk distance too small";
      return false;
   }

   signal.risk_reward_ratio = CalculateTradeRiskRewardRatio(signal.entry_price, signal.stop_loss, signal.take_profit);
   if(signal.risk_reward_ratio < (g_Min_RR_Ratio - 0.01))
   {
      signal.valid = false;
      signal.reason = stage_prefix + "RR below minimum (" +
                      DoubleToString(signal.risk_reward_ratio, 2) + " < " +
                      DoubleToString(g_Min_RR_Ratio, 2) + ")";
      return false;
   }

   double mid_price = GetCachedMidPrice(symbol, idx);
   if(mid_price > 0.0)
   {
      double entry_distance_pct = MathAbs(signal.entry_price - mid_price) / mid_price * 100.0;
      double entry_cap_basis = g_Max_Entry_Distance_Pct;
      if(signal.origin == SIGNAL_ORIGIN_ICT || signal.origin == SIGNAL_ORIGIN_BOTH)
         entry_cap_basis = g_Max_Entry_Distance_Relaxed_Cap;
      bool prefer_pending_execution = (StringFind(signal.reason, "ExecPref=PENDING") >= 0);
      double hard_entry_cap_pct = MathMin(2.0, MathMax(0.80, entry_cap_basis));
      if(entry_distance_pct > hard_entry_cap_pct)
      {
         if(prefer_pending_execution)
         {
            if(g_Enable_Institutional_Debug || g_debug_signals_enabled)
            {
               Log(LOG_INFO, "HardenStrategySignal", symbol + " - " + stage_tag +
                   " far-entry setup preserved for pending execution (" +
                   DoubleToString(entry_distance_pct, 2) + "% > " +
                   DoubleToString(hard_entry_cap_pct, 2) + "%)");
            }
         }
         else
         {
            signal.valid = false;
            signal.reason = stage_prefix + "entry too far from market (" +
                            DoubleToString(entry_distance_pct, 2) + "% > " +
                            DoubleToString(hard_entry_cap_pct, 2) + "%)";
            return false;
         }
      }
   }

   bool allow_neutral_context = (allow_range_mode || g_Allow_Neutral_Trend_Trading);
   int effective_htf_bias = trend_direction;
   if(effective_htf_bias == 0)
   {
      if(!allow_neutral_context)
      {
         signal.valid = false;
         signal.reason = stage_prefix + "HTF bias neutral";
         return false;
      }
   }
   else if(signal.direction != effective_htf_bias && !allow_countertrend_signal)
   {
      signal.valid = false;
      signal.reason = stage_prefix + "direction opposes HTF bias";
      return false;
   }
 
   // Strategy direction must be confirmed by the trend direction class.
   bool allow_kim_range_signal = (allow_range_mode && signal.origin == SIGNAL_ORIGIN_KIMANIZ);
   int trend_class_dir = GetTrendDirection(symbol);
   if(trend_class_dir != 0 && signal.direction != trend_class_dir &&
      !allow_countertrend_signal && !allow_kim_range_signal)
   {
      signal.valid = false;
      signal.reason = stage_prefix + "direction not confirmed by trend class";
      return false;
   }
   if(trend_class_dir == 0)
   {
      if(!allow_neutral_context)
      {
         signal.valid = false;
         signal.reason = stage_prefix + "trend class neutral";
         return false;
      }
   }

   string funnel_reason = "";
   if(!EvaluateInstitutionalTimeframeFunnel(symbol, idx, allow_range_mode, signal, stage_tag, funnel_reason))
   {
      signal.valid = false;
      signal.reason = funnel_reason;
      return false;
   }

   if(signal.signal_time <= 0)
      signal.signal_time = TimeCurrent();

   signal.valid = true;
   return true;
}

bool FinalizeStrategySignalBasics(string symbol,
                                 STradingSignal &signal,
                                 ENUM_SIGNAL_ORIGIN origin,
                                 string stage_tag)
{
   if(signal.origin == SIGNAL_ORIGIN_UNKNOWN)
      signal.origin = origin;

   if(signal.signal_time <= 0)
      signal.signal_time = TimeCurrent();

   if(signal.execution_tf == PERIOD_CURRENT)
      signal.execution_tf = Signal_TF;

   if(!signal.valid)
      return false;

   string stage_prefix = (StringLen(stage_tag) > 0 ? stage_tag + " finalize: " : "Signal finalize: ");

   string shape_reason = "";
   if(!IsSignalTradeShapeValid(signal, shape_reason))
   {
      signal.valid = false;
      signal.reason = stage_prefix + "invalid trade shape (" + shape_reason + ")";
      return false;
   }

   double risk_distance = MathAbs(signal.entry_price - signal.stop_loss);
   double reward_distance = MathAbs(signal.take_profit - signal.entry_price);
   if(!MathIsValidNumber(risk_distance) || !MathIsValidNumber(reward_distance) ||
      risk_distance <= 0.0 || reward_distance <= 0.0)
   {
      signal.valid = false;
      signal.reason = stage_prefix + "invalid risk/reward distance";
      return false;
   }

   double rr = SafeDiv(reward_distance, risk_distance, 0.0);
   if(!MathIsValidNumber(rr) || rr <= 0.0)
   {
      signal.valid = false;
      signal.reason = stage_prefix + "invalid RR ratio";
      return false;
   }

   if(IsHTFAlignedRetracementContinuationSignal(signal) &&
      StringFind(signal.reason, "ExecPref=") < 0)
   {
      if(StringLen(signal.reason) > 0)
         signal.reason += " | ExecPref=PENDING";
      else
         signal.reason = "ExecPref=PENDING";
   }

   signal.risk_reward_ratio = NormalizeDouble(rr, 2);
   return true;
}

void HardenSelectedSignal(string symbol,
                          int symbol_index,
                          bool allow_range_mode,
                          int trend_direction,
                          STradingSignal &signal,
                          string stage_tag)
{
   // INITIALIZATION SAFETY: Validate signal object is properly initialized
   if(symbol == "" || StringLen(symbol) == 0)
   {
      if(DEBUG_SIGNAL_INVERSION)
         Log(LOG_ERROR, "HardenSelectedSignal", "Empty symbol provided");
      signal.valid = false;
      return;
   }
   
   // INITIALIZATION SAFETY: Validate signal has non-zero direction
   if(signal.direction == 0)
   {
      if(DEBUG_SIGNAL_INVERSION)
         Log(LOG_WARNING, "HardenSelectedSignal", 
             StringFormat("%s %s: Signal has neutral direction - will not harden", symbol, stage_tag));
      // Don't invalidate neutral signals, just skip hardening
      return;
   }
   
   // INITIALIZATION SAFETY: Validate signal has valid entry price
   if(signal.entry_price <= 0.0 || !MathIsValidNumber(signal.entry_price))
   {
      if(DEBUG_SIGNAL_INVERSION)
         Log(LOG_ERROR, "HardenSelectedSignal",
             StringFormat("%s %s: Invalid entry price %.5f", symbol, stage_tag, signal.entry_price));
      signal.valid = false;
      return;
   }
   
   if(signal.valid)
      HardenStrategySignal(symbol, symbol_index, allow_range_mode, trend_direction, signal, stage_tag);
}

bool GetDirectionalCoreTimeframeState(string symbol,
                                      ENUM_TIMEFRAMES tf,
                                      int &timeframe_direction,
                                      bool &decisive_out)
{
   timeframe_direction = 0;
   decisive_out = false;

   if(StringLen(symbol) <= 0 || tf == PERIOD_CURRENT)
      return false;

   if(tf == Signal_TF)
   {
      timeframe_direction = StructureToDirection(DetectMarketStructure(symbol, tf));
      decisive_out = (timeframe_direction != 0);
      return true;
   }

   STrendAnalysis analysis = CTrendAnalysisEnhanced::AnalyzeTrendInstitutional(symbol, tf);
   double min_strength = ((tf == Trend_TF) ? 45.0 : 50.0);

   if((analysis.direction == TREND_BULLISH || analysis.direction == TREND_BEARISH) &&
      analysis.strength >= min_strength)
   {
      timeframe_direction = (analysis.direction == TREND_BULLISH ? 1 : -1);
      decisive_out = true;
      return true;
   }

   // If institutional analysis is stale or unavailable, fall back to raw structure.
   if(!analysis.is_fresh)
   {
      timeframe_direction = StructureToDirection(DetectMarketStructure(symbol, tf));
      decisive_out = (timeframe_direction != 0);
   }

   return true;
}

int CountDirectionalAlignedCoreTimeframes(string symbol, int direction, int &decisive_out)
{
   decisive_out = 0;
   if(direction != 1 && direction != -1)
      return 0;

   ENUM_TIMEFRAMES tfs[STRATEGY_TF_SLOTS];
   tfs[0] = Signal_TF;
   tfs[1] = Primary_TF;
   tfs[2] = Confirm_TF;
   tfs[3] = Trend_TF;

   int aligned = 0;
   for(int i = 0; i < STRATEGY_TF_SLOTS; i++)
   {
      int tf_direction = 0;
      bool decisive = false;
      if(!GetDirectionalCoreTimeframeState(symbol, tfs[i], tf_direction, decisive))
         continue;

      if(!decisive)
         continue;

      decisive_out++;
      if(tf_direction == direction)
      {
         aligned++;
      }
   }

   return aligned;
}

int CountDirectionalAlignedHigherCoreTimeframes(string symbol, int direction, int &decisive_out)
{
   decisive_out = 0;
   if(direction != 1 && direction != -1)
      return 0;

   ENUM_TIMEFRAMES tfs[STRATEGY_TF_SLOTS - 1];
   tfs[0] = Primary_TF;
   tfs[1] = Confirm_TF;
   tfs[2] = Trend_TF;

   int aligned = 0;
   for(int i = 0; i < ArraySize(tfs); i++)
   {
      int tf_direction = 0;
      bool decisive = false;
      if(!GetDirectionalCoreTimeframeState(symbol, tfs[i], tf_direction, decisive))
         continue;

      if(!decisive)
         continue;

      decisive_out++;
      if(tf_direction == direction)
         aligned++;
   }

   return aligned;
}

bool ValidateMinimumAlignedCoreTimeframes(string symbol,
                                          int direction,
                                          int min_aligned,
                                          string gate_label,
                                          string &reason_out)
{
   reason_out = "";

   int required = min_aligned;
   if(required < 0)
      required = 0;
   if(required > STRATEGY_TF_SLOTS)
      required = STRATEGY_TF_SLOTS;
   if(required == 0)
      return true;

   int decisive = 0;
   int aligned = CountDirectionalAlignedCoreTimeframes(symbol, direction, decisive);
   if(decisive <= 0)
   {
      string label = (StringLen(gate_label) > 0 ? gate_label : "TF alignment gate");
      reason_out = label + ": no decisive timeframe direction available";
      return false;
   }

   if(required > 1 && decisive < 2)
   {
      string label = (StringLen(gate_label) > 0 ? gate_label : "TF alignment gate");
      reason_out = label + ": insufficient decisive TFs (" +
                   IntegerToString(decisive) + "/" + IntegerToString(STRATEGY_TF_SLOTS) +
                   ", need at least 2)";
      return false;
   }

   int effective_required = MathMin(required, decisive);
   if(aligned >= effective_required)
      return true;

   string label = (StringLen(gate_label) > 0 ? gate_label : "TF alignment gate");
   reason_out = label + ": insufficient TF alignment (" +
                IntegerToString(aligned) + "/" + IntegerToString(decisive) +
                " decisive, need " + IntegerToString(effective_required) +
                ", configured " + IntegerToString(required) + "/" +
                IntegerToString(STRATEGY_TF_SLOTS) + ")";
   return false;
}

bool IsHTFAlignedRetracementContinuationContext(string symbol,
                                                int htf_bias,
                                                const STradingSignal &signal)
{
   if(!IsHTFAlignedRetracementContinuationSignal(signal))
      return false;

   if(signal.direction != htf_bias)
      return false;

   int signal_tf_direction = 0;
   bool signal_tf_decisive = false;
   if(!GetDirectionalCoreTimeframeState(symbol, Signal_TF, signal_tf_direction, signal_tf_decisive))
      return false;

   return (signal_tf_decisive && signal_tf_direction == -signal.direction);
}

bool ValidateRetracementContinuationCoreTimeframes(string symbol,
                                                   int direction,
                                                   int min_aligned,
                                                   string gate_label,
                                                   string &reason_out)
{
   reason_out = "";

   int required = min_aligned;
   if(required < 0)
      required = 0;
   if(required > STRATEGY_TF_SLOTS)
      required = STRATEGY_TF_SLOTS;

   int higher_required = MathMax(0, required - 1);
   if(higher_required == 0)
      return true;

   int decisive = 0;
   int aligned = CountDirectionalAlignedHigherCoreTimeframes(symbol, direction, decisive);
   if(decisive <= 0)
   {
      string label = (StringLen(gate_label) > 0 ? gate_label : "Retracement TF gate");
      reason_out = label + ": no decisive higher timeframe direction available";
      return false;
   }

   int effective_required = MathMin(higher_required, decisive);
   if(aligned >= effective_required)
      return true;

   string label = (StringLen(gate_label) > 0 ? gate_label : "Retracement TF gate");
   reason_out = label + ": retracement continuation HTF alignment insufficient (" +
                IntegerToString(aligned) + "/" + IntegerToString(decisive) +
                " decisive higher TFs, need " + IntegerToString(effective_required) +
                ", configured " + IntegerToString(higher_required) + "/" +
                IntegerToString(STRATEGY_TF_SLOTS - 1) + ")";
   return false;
}

int GetExecutionAlignedCoreTimeframeRequirement()
{
   if(!g_Enable_Final_Integrity_Gate)
      return 0;

   int required = g_Integrity_Min_Aligned_TF;
   if(Require_All_TF_Agreement)
      required = STRATEGY_TF_SLOTS;
   if(required < 0)
      required = 0;
   if(required > STRATEGY_TF_SLOTS)
      required = STRATEGY_TF_SLOTS;
   return required;
}

bool FinalIntegrityGate(string symbol, int symbol_index, bool allow_range_mode,
                        STradingSignal &signal, string &reason_out,
                        bool has_seeded_trend_direction = false,
                        int seeded_trend_direction = 0)
{
   reason_out = "";
   if(!g_Enable_Final_Integrity_Gate)
      return true;

   bool allow_countertrend_signal = IsCountertrendRetracementSignal(signal);
   if(signal.direction == 0)
   {
      reason_out = "Integrity gate: neutral direction";
      return false;
   }

   bool allow_neutral_context = (allow_range_mode || g_Allow_Neutral_Trend_Trading);
   int integrity_htf_bias = ResolveHTFBiasForSignalPass(symbol,
                                                        has_seeded_trend_direction,
                                                        seeded_trend_direction);
   bool allow_retracement_continuation = IsHTFAlignedRetracementContinuationContext(symbol, integrity_htf_bias, signal);
   if(integrity_htf_bias == 0)
   {
      if(!allow_neutral_context)
      {
         reason_out = "Integrity gate: HTF bias neutral";
         return false;
      }
   }
   else if(signal.direction != integrity_htf_bias && !allow_countertrend_signal)
   {
      reason_out = "Integrity gate: direction opposes HTF bias";
      return false;
   }

   datetime now = TimeCurrent();
   double decay_factor = 1.0;  // Default: no decay
   
   // ===== TIER 1C ENHANCEMENT: TEMPORAL SIGNAL DECAY CHECK =====
   // Exponentially decay signal confidence based on age
   // Fresh signals (0 bars): 100%, 5 bars: 90%, 15 bars: 70%, 30 bars: 45%, 60+ bars: 0% (expired)
   if(signal.signal_time > 0)
   {
      int signal_age_seconds = (int)(now - signal.signal_time);
      ENUM_TIMEFRAMES decay_tf = (signal.execution_tf != PERIOD_CURRENT ? signal.execution_tf : Signal_TF);
      int tf_seconds = PeriodSeconds(decay_tf);
      if(tf_seconds <= 0)
         tf_seconds = 60;

      int signal_bars = MathMax(0, signal_age_seconds / tf_seconds);
       
      // Decay curve: exponential falloff
      decay_factor = 1.0;
      if(signal_bars >= 60)
      {
         decay_factor = 0.0;  // Expired
      }
      else if(signal_bars >= 30)
      {
         decay_factor = 0.45;  // 30 bars: 45%
      }
      else if(signal_bars >= 15)
      {
         decay_factor = 0.70;  // 15 bars: 70%
      }
      else if(signal_bars >= 5)
      {
         decay_factor = 0.90;  // 5 bars: 90%
      }
      // else: < 5 bars = 100% (1.0)
      
      if(decay_factor <= 0.0)
      {
         reason_out = "Tier 1C: Signal expired (age=" + IntegerToString(signal_bars) + " bars)";
         return false;
      }
      
      // Apply decay to signal confidence
      signal.ai_confidence *= decay_factor;
      
      if(g_Enable_Institutional_Debug)
         Log(LOG_DEBUG, "CheckFinalIntegrityGate", symbol + 
             " - Tier 1C temporal decay applied (bars=" + IntegerToString(signal_bars) +
             ", factor=" + DoubleToString(decay_factor, 2) +
             ", new_conf=" + DoubleToString(signal.ai_confidence, 2) + ")");
   }
   // ===== END TIER 1C =====
   
   // ===== TIER 1: CONFIDENCE FUSION ROUTING =====
   // Apply multi-signal confidence fusion to determine execution parameters
   // Blends ICT, AI, and Kmaniz confidences with proper weighting
   bool ict_valid = (signal.origin == SIGNAL_ORIGIN_ICT || signal.origin == SIGNAL_ORIGIN_BOTH);
   bool ai_valid = (signal.origin == SIGNAL_ORIGIN_AI ||
                    signal.origin == SIGNAL_ORIGIN_BOTH ||
                    signal.ai_agrees);
   bool kim_valid = (signal.origin == SIGNAL_ORIGIN_KIMANIZ);
   
   double ict_conf = (ict_valid ? MathMax(0.5, signal.ai_confidence) : 0.3);
   double ai_conf = signal.ai_confidence;
   double kim_conf = (kim_valid ? MathMax(0.4, signal.ai_confidence) : 0.3);
   
   int fusion_sources = 0;
   if(ict_valid)
      fusion_sources++;
   if(ai_valid)
      fusion_sources++;
   if(kim_valid)
      fusion_sources++;

   // Confidence decay has already been applied above. Only require confluence
   // when more than one source actually participates in the fused decision.
   bool require_fusion_confluence = (fusion_sources >= 2);
   SConfidenceWeightedRoute fusion_route = CConfidenceFusionRouter::FuseSignalConfidences(
      ict_valid, ict_conf, 1.0,
      ai_valid,  ai_conf,  1.0,
      kim_valid, kim_conf, 1.0,
      require_fusion_confluence
   );
   
   // Apply fusion routing parameters to signal execution
   // Lot sizing from fusion confidence level
   if(fusion_route.execute_signal && fusion_route.execution_confidence >= 0.35)
   {
      signal.ai_confidence = MathMax(signal.ai_confidence, fusion_route.execution_confidence);
      if(g_Enable_Institutional_Debug)
         Log(LOG_DEBUG, "CheckFinalIntegrityGate", symbol + 
             " - Tier 1 Confidence Fusion: route=" + fusion_route.routing_decision + 
             ", confidence=" + DoubleToString(fusion_route.execution_confidence, 2) +
             ", lot_mult=" + DoubleToString(fusion_route.lot_size_multiplier, 2));
   }
   else if(!fusion_route.execute_signal && fusion_route.execution_confidence < 0.2)
   {
      reason_out = "Tier 1: Confidence fusion below execution threshold (" + 
                   DoubleToString(fusion_route.execution_confidence, 2) + ")";
      return false;
   }
   // ===== END TIER 1 =====
   
   if(g_Max_Signal_Age_Seconds > 0 && signal.signal_time > 0 &&
      (now - signal.signal_time) > g_Max_Signal_Age_Seconds)
   {
      reason_out = "Integrity gate: signal stale (" + IntegerToString((int)(now - signal.signal_time)) + "s)";
      return false;
   }

   if(g_Integrity_Min_HTF_Bias_Score > 0)
   {
      int htf_score = (int)MathAbs(GetHTFBiasStrengthInstitutional(symbol));
      if(htf_score < g_Integrity_Min_HTF_Bias_Score)
      {
         reason_out = "Integrity gate: HTF bias score too weak (" +
                      IntegerToString(htf_score) + " < " +
                      IntegerToString(g_Integrity_Min_HTF_Bias_Score) + ")";
         return false;
      }
   }

   if(g_Integrity_Min_Aligned_TF > 0 &&
      allow_countertrend_signal)
   {
      int signal_tf_direction = 0;
      bool signal_tf_decisive = false;
      if(!GetDirectionalCoreTimeframeState(symbol, Signal_TF, signal_tf_direction, signal_tf_decisive) ||
         !signal_tf_decisive ||
         signal_tf_direction != signal.direction)
      {
         reason_out = "Integrity gate: countertrend retracement lost Signal_TF confirmation";
         return false;
      }
   }
   else if(g_Integrity_Min_Aligned_TF > 0 &&
           allow_retracement_continuation &&
           !ValidateRetracementContinuationCoreTimeframes(symbol, signal.direction,
                                                          g_Integrity_Min_Aligned_TF,
                                                          "Integrity gate", reason_out))
   {
      return false;
   }
   else if(g_Integrity_Min_Aligned_TF > 0 &&
           !ValidateMinimumAlignedCoreTimeframes(symbol, signal.direction, g_Integrity_Min_Aligned_TF,
                                                 "Integrity gate", reason_out))
   {
      return false;
   }

   return true;
}

double GetCachedMidPrice(string symbol, int symbol_index)
{
   double bid = 0.0, ask = 0.0;
   if(symbol_index >= 0 && symbol_index < g_symbols_count)
   {
      bid = g_symbols[symbol_index].cache.bid;
      ask = g_symbols[symbol_index].cache.ask;
   }

   if(bid <= 0.0 || ask <= 0.0 || bid >= ask)
   {
      bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   }

   if(bid > 0.0 && ask > 0.0 && bid < ask)
      return (bid + ask) / 2.0;

   return 0.0;
}

double ComputeEntryDistancePct(string symbol, int symbol_index, const STradingSignal &signal, double mid_price = 0.0)
{
   if(mid_price <= 0.0)
      mid_price = GetCachedMidPrice(symbol, symbol_index);
   if(mid_price <= 0.0 || signal.entry_price <= 0.0)
      return -1.0;

   return MathAbs(signal.entry_price - mid_price) / mid_price * 100.0;
}

double GetDirectionalAIProbForScoring(string symbol, int symbol_index, int direction)
{
   if(!g_Enable_AI_Trend_Predictor_Runtime || !g_ai_enabled || direction == 0)
      return 0.0;

   if(symbol_index >= 0 && symbol_index < g_symbols_count && IsAIPredictionFresh(symbol_index, Signal_TF))
   {
      RecordAICacheAccess(symbol_index, true);
      double buy_prob = ClampUnitProbability(g_ai_prediction_cache[symbol_index].buy_prob);
      double sell_prob = ClampUnitProbability(g_ai_prediction_cache[symbol_index].sell_prob);
      return GetEffectiveDirectionalAIProbability(direction, buy_prob, sell_prob);
   }

   return 0.0;
}

string BuildScoreAlignmentSummary(const SFilterDiagnostic &d)
{
   string names[10] = {"trend","momentum","volatility","structure","alignment","mtf","rr","entry","spread","regime"};
   double scores[10];
   scores[0] = d.trend_score;
   scores[1] = d.momentum_score;
   scores[2] = d.volatility_score;
   scores[3] = d.structure_score;
   scores[4] = d.alignment_score;
   scores[5] = d.confirmation_score;
   scores[6] = d.risk_reward_score;
   scores[7] = d.entry_quality_score;
   scores[8] = d.spread_score;
   scores[9] = d.regime_score;

   int max_i = 0;
   int max2_i = -1;
   int min_i = 0;
   int min2_i = -1;
   for(int i = 1; i < 10; i++)
   {
      if(scores[i] > scores[max_i])
      {
         max2_i = max_i;
         max_i = i;
      }
      else if(i != max_i && (max2_i < 0 || scores[i] > scores[max2_i]))
      {
         max2_i = i;
      }

      if(scores[i] < scores[min_i])
      {
         min2_i = min_i;
         min_i = i;
      }
      else if(i != min_i && (min2_i < 0 || scores[i] < scores[min2_i]))
      {
         min2_i = i;
      }
   }

   if(max2_i < 0) max2_i = max_i;
   if(min2_i < 0) min2_i = min_i;

   const double tie_eps = 1.5; // treat scores within ~1-2 points as ties
   if(MathAbs(scores[max_i] - scores[max2_i]) <= tie_eps) max2_i = max_i;
   if(MathAbs(scores[min_i] - scores[min2_i]) <= tie_eps) min2_i = min_i;

   return StringFormat("Score=%.1f/%.1f Dom=%s(%.0f)/%s(%.0f) Weak=%s(%.0f)/%s(%.0f) Pen=%.1f",
                       d.trade_score,
                       (d.required_score > 0.0 ? d.required_score : d.trade_score),
                       names[max_i], scores[max_i],
                       names[max2_i], scores[max2_i],
                       names[min_i], scores[min_i],
                       names[min2_i], scores[min2_i],
                       d.penalty_points);
}

bool ApplyScoringGate(string symbol,
                      ENUM_TIMEFRAMES tf,
                      STradingSignal &signal,
                      double directional_probability,
                      double atr_value,
                      int htf_bias,
                      string stage_tag,
                      int symbol_index_cached = -1,
                      double mid_price_cached = 0.0,
                      int sig_struct_cached = -9999,
                      bool allow_soft_precheck_pass = true)
{
   if(!Enable_All_Institutional_Filters)
      return signal.valid;

   if(!signal.valid)
      return false;

   if(signal.direction == 0)
   {
      signal.valid = false;
      signal.reason = stage_tag + " scoring: no direction";
      return false;
   }

   if(g_scoring_engine.GetScoreThreshold() <= 0)
   {
      signal.valid = false;
      signal.reason = "ScoringEngine not properly initialized";
      Log(LOG_ERROR, stage_tag, symbol + " - " + signal.reason);
      return false;
   }

   int symbol_index = (symbol_index_cached >= 0 ? symbol_index_cached : GetSymbolIndex(symbol));
   double entry_distance_pct = ComputeEntryDistancePct(symbol, symbol_index, signal, mid_price_cached);

   SFilterDiagnostic diagnostic;
   double reversal_confidence = (signal.reversal_detected ? signal.reversal_confidence : -1.0);
   bool scoring_result = g_scoring_engine.ShouldExecuteTrade(
      symbol,
      tf,
      signal.direction,
      diagnostic,
      directional_probability,
      signal.risk_reward_ratio,
      entry_distance_pct,
      reversal_confidence
   );

   double required_score = (diagnostic.required_score > 0.0 ? diagnostic.required_score : g_scoring_engine.GetScoreThreshold());
   double precheck_buffer = MathMax(0.0, Scoring_Precheck_Buffer);
   double precheck_floor = MathMax(55.0, required_score - precheck_buffer);
   bool soft_precheck_pass = (diagnostic.trade_score >= precheck_floor);

   if(!scoring_result && !soft_precheck_pass)
   {
      signal.valid = false;
      signal.reason = stage_tag + " scoring rejected | " +
                      DoubleToString(diagnostic.trade_score, 1) + "/" +
                      DoubleToString(required_score, 1) +
                      " | Confidence: " + diagnostic.confidence_label;
      if(StringLen(diagnostic.score_breakdown) > 0)
         signal.reason += " (" + diagnostic.score_breakdown + ")";
      else if(StringLen(diagnostic.reason) > 0)
         signal.reason += " (" + diagnostic.reason + ")";

      string diag_txt_fail = StringFormat("Score=%.2f/%.1f (max %.1f) %s | Breakdown: %s",
                              diagnostic.trade_score, required_score, diagnostic.available_score_max,
                              diagnostic.reason, diagnostic.score_breakdown);
      int sig_struct = (sig_struct_cached != -9999 ? sig_struct_cached : DetectMarketStructure(symbol, tf));
      double inst_price_log = (mid_price_cached > 0.0 ? mid_price_cached : GetCachedMidPrice(symbol, symbol_index));
      double inst_spread = (symbol_index >= 0 && symbol_index < g_symbols_count ? g_symbols[symbol_index].cache.spread : 0.0);
      LogInstitutionalSignal(stage_tag + "_SCORING_FAIL", symbol, signal, htf_bias, sig_struct,
                             inst_price_log, inst_spread, atr_value, diag_txt_fail);
      if(g_Enable_Institutional_Debug)
      {
         string summary = BuildScoreAlignmentSummary(diagnostic);
         LogTradeMessage(LOG_INFO, stage_tag, symbol, "Scoring alignment", summary);
      }
      return false;
   }

   if(!scoring_result && soft_precheck_pass)
   {
      if(!allow_soft_precheck_pass)
      {
         signal.valid = false;
         signal.reason = stage_tag + " scoring rejected (strict) | " +
                         DoubleToString(diagnostic.trade_score, 1) + "/" +
                         DoubleToString(required_score, 1) +
                         " | Confidence: " + diagnostic.confidence_label;
         if(StringLen(diagnostic.score_breakdown) > 0)
            signal.reason += " (" + diagnostic.score_breakdown + ")";
         if(g_Enable_Institutional_Debug)
         {
            string summary = BuildScoreAlignmentSummary(diagnostic);
            LogTradeMessage(LOG_INFO, stage_tag, symbol, "Scoring alignment", summary);
         }
         return false;
      }

      LogTradeMessage(LOG_INFO, stage_tag, symbol, "Scoring precheck soft-pass",
         "Score: " + DoubleToString(diagnostic.trade_score, 1) + "/" + DoubleToString(required_score, 1) +
         " | Floor: " + DoubleToString(precheck_floor, 1) +
         " | Final score check still required");
      return true;
   }

   // scoring_result == true
   LogTradeMessage(LOG_INFO, stage_tag, symbol, "ScoringEngine approved",
                   "Score: " + DoubleToString(diagnostic.trade_score, 1) + "/" + DoubleToString(required_score, 1) +
                   " | Confidence: " + diagnostic.confidence_label +
                   " (max " + DoubleToString(diagnostic.available_score_max, 1) + ") (" + diagnostic.score_breakdown + ")");
   string diag_txt_pass = StringFormat("Score=%.2f/%.1f (max %.1f) PASS | Breakdown: %s",
                          diagnostic.trade_score, required_score, diagnostic.available_score_max,
                          diagnostic.score_breakdown);
   int sig_struct = (sig_struct_cached != -9999 ? sig_struct_cached : DetectMarketStructure(symbol, tf));
   double inst_price = (mid_price_cached > 0.0 ? mid_price_cached : GetCachedMidPrice(symbol, symbol_index));
   double inst_spread = (symbol_index >= 0 && symbol_index < g_symbols_count ? g_symbols[symbol_index].cache.spread : 0.0);
   LogInstitutionalSignal(stage_tag + "_SCORING_PASS", symbol, signal, htf_bias, sig_struct,
                          inst_price, inst_spread, atr_value, diag_txt_pass);
   return true;
}

bool ApplyAIValidationToSignal(string symbol, STradingSignal &signal)
{
   if(!g_Enable_AI_Trend_Predictor_Runtime || !g_ai_enabled || !signal.valid)
      return signal.valid;

   int symbol_index_ai = GetSymbolIndex(symbol);
   if(symbol_index_ai == -1 || !IsAIPredictionFresh(symbol_index_ai, Signal_TF))
      return signal.valid;

   RecordAICacheAccess(symbol_index_ai, true);
   double buy_prob = ClampUnitProbability(g_ai_prediction_cache[symbol_index_ai].buy_prob);
   double sell_prob = ClampUnitProbability(g_ai_prediction_cache[symbol_index_ai].sell_prob);
   double raw_dir_prob = GetRawDirectionalAIProbability(signal.direction, buy_prob, sell_prob);
   double effective_dir_prob = GetEffectiveDirectionalAIProbability(signal.direction, buy_prob, sell_prob);
   double edge = (signal.direction == 1 ? buy_prob - sell_prob : signal.direction == -1 ? sell_prob - buy_prob : 0.0);

   signal.ai_probability = raw_dir_prob;
   signal.ai_confidence = effective_dir_prob;
   signal.ai_buy_probability = buy_prob;
   signal.ai_sell_probability = sell_prob;
   signal.ai_effective_probability = effective_dir_prob;
   signal.ai_directional_edge = edge;

   double min_conf = GetAIDirectionalMinProbability(signal.direction, symbol, symbol_index_ai);
   signal.ai_min_probability_required = min_conf;
   signal.ai_agrees = CheckAIAgreementWithConfidence(effective_dir_prob, signal.direction, min_conf);
   if(symbol_index_ai >= 0 && symbol_index_ai < g_symbols_count)
   {
      double vol_regime = GetCachedVolatilityFactor(symbol, symbol_index_ai);
      double required_edge = g_AI_Min_Directional_Edge;
      if(!g_Disable_All_Gates && vol_regime > 1.20)
         required_edge += MathMin(0.12, (vol_regime - 1.20) * 0.06);

      double atr_value = GetATRValue(symbol, Signal_TF);
      double spread = g_symbols[symbol_index_ai].cache.spread * g_symbols[symbol_index_ai].cache.point;
      if(atr_value > 0.0)
         signal.ai_spread_to_atr = SafeDiv(spread, atr_value, -1.0);
      signal.ai_volatility_regime = vol_regime;
      signal.ai_required_edge = required_edge;
      if(signal.risk_reward_ratio > 0.0)
         signal.ai_expected_value_r = effective_dir_prob * signal.risk_reward_ratio - (1.0 - effective_dir_prob);
   }
   if(signal.origin == SIGNAL_ORIGIN_AI)
   {
      signal.strategy_output_summary = BuildAISignalSummary(signal, true);
      signal.strategy_output_detail = BuildAISignalSummary(signal, false);
   }
   double prob_conf = AIInferenceEngine::GetConfidence(raw_dir_prob);
   Log(LOG_DEBUG, "ProcessSignals", "Signal validated with AI predictions: " +
       "RawProb=" + DoubleToString(raw_dir_prob, 2) +
       ", EffectiveProb=" + DoubleToString(effective_dir_prob, 2) +
       ", Edge=" + DoubleToString(edge, 2) +
       ", ProbConf=" + DoubleToString(prob_conf, 2) +
       ", DirConf=" + DoubleToString(signal.ai_confidence, 2) +
       ", Agrees=" + (signal.ai_agrees ? "Yes" : "No") +
       ", MinProb=" + DoubleToString(min_conf, 2));

   Log(LOG_DEBUG, "ProcessSignals", "AI Agreement Detail: BuyProb=" +
       DoubleToString(g_ai_prediction_cache[symbol_index_ai].buy_prob, 2) +
       ", SellProb=" + DoubleToString(g_ai_prediction_cache[symbol_index_ai].sell_prob, 2) +
       ", Direction=" + (signal.direction == 1 ? "BUY" : signal.direction == -1 ? "SELL" : "NEUTRAL"));

   double neutral_band = g_AI_Neutral_Band;
   if(neutral_band < 0.0) neutral_band = 0.0;
   if(!signal.ai_agrees && MathAbs(raw_dir_prob - 0.5) <= neutral_band)
      signal.ai_agrees = true; // Neutral -> allow

   if(g_Enable_Institutional_Debug)
   {
      Log(LOG_INFO, "ProcessSignals",
          StringFormat("%s - AI report | Dir=%s Raw=%.3f Effective=%.3f Min=%.3f NeutralBand=%.3f Agree=%s",
                       symbol,
                       (signal.direction == 1 ? "BUY" : signal.direction == -1 ? "SELL" : "NEUTRAL"),
                       raw_dir_prob, effective_dir_prob, min_conf, neutral_band,
                       (signal.ai_agrees ? "YES" : "NO")));
   }

   if(g_AI_Require_Agreement_Runtime && !signal.ai_agrees)
   {
      signal.valid = false;
      signal.reason = "AI disagrees with trade direction (effective prob: " +
                      DoubleToString(effective_dir_prob * 100, 1) + "% < min " +
                      DoubleToString(min_conf * 100, 1) + "%)";
      LogTradeMessage(LOG_INFO, "ProcessSignals", symbol, signal.reason);
      g_ai_signals_disagreed++;
   }
   else if(signal.ai_agrees)
   {
      g_ai_signals_confirmed++;
      if(signal.ai_confidence > 0.75)
         g_ai_high_confidence_trades++;
   }

   return signal.valid;
}

double GetAIDirectionalMinProbability(int direction, string symbol, int symbol_index)
{
   // TIER 1A ENHANCEMENT: Use adaptive threshold calculator instead of static thresholds
   // This accounts for volatility, session effects, and AI performance
   SAdaptiveThresholds adaptive_thresh = g_threshold_calculator.GetAdaptiveThresholds(symbol, symbol_index);
   
   double min_prob;
   if(direction == 1)
      min_prob = adaptive_thresh.buy_threshold;  // Uses adaptive threshold
   else if(direction == -1)
      min_prob = adaptive_thresh.sell_threshold; // Uses adaptive threshold
   else
      min_prob = 0.50; // Neutral
   
   // Apply trend confidence adjustments (legacy system)
   int trend_level = AI_Trend_Confidence;
   if(trend_level < 0) trend_level = 0;
   if(trend_level > 5) trend_level = 5;
   min_prob += (trend_level - 1) * 0.05;
   
   // Clamp to valid range
   min_prob = MathClamp(min_prob, 0.45, 0.90);
   
   Log(LOG_DEBUG, "GetAIDirectionalMinProbability", "Adaptive thresholds for " + symbol + 
       ": min_prob=" + DoubleToString(min_prob, 2) +
       ", vol_factor=" + DoubleToString(adaptive_thresh.vol_adjustment_factor, 2) +
       ", accuracy_factor=" + DoubleToString(adaptive_thresh.accuracy_adjustment_factor, 2));

   return min_prob;
}

int SelectAIDirection(double buy_prob, double sell_prob, double buy_min_prob, double sell_min_prob)
{
   double neutral_band = g_AI_Neutral_Band;
   if(neutral_band < 0.0)
      neutral_band = 0.0;

   double buy_effective = GetEffectiveDirectionalAIProbability(1, buy_prob, sell_prob);
   double sell_effective = GetEffectiveDirectionalAIProbability(-1, buy_prob, sell_prob);
   double edge = buy_prob - sell_prob;

   bool buy_ready = (buy_effective >= buy_min_prob) && (edge >= neutral_band * 0.5);
   bool sell_ready = (sell_effective >= sell_min_prob) && (-edge >= neutral_band * 0.5);

   if(buy_ready && !sell_ready)
      return 1;
   if(sell_ready && !buy_ready)
      return -1;
   if(buy_ready && sell_ready)
      return (buy_effective >= sell_effective ? 1 : -1);

   if(!g_AI_Allow_Relaxed_TieBreak)
      return 0;

   // Relaxed tie-break if neutral-band margin is the only blocker.
   if(buy_effective >= buy_min_prob && buy_prob > sell_prob)
      return 1;
   if(sell_effective >= sell_min_prob && sell_prob > buy_prob)
      return -1;

   return 0;
}

bool EvaluateAIMTFRegimeAlignment(string symbol, int direction, int &aligned, int &opposed, int &neutral)
{
   aligned = 0;
   opposed = 0;
   neutral = 0;

   if(direction != 1 && direction != -1)
      return false;

   ENUM_TIMEFRAMES tfs[3];
   tfs[0] = Signal_TF;
   tfs[1] = Primary_TF;
   tfs[2] = Confirm_TF;
   for(int i = 0; i < 3; i++)
   {
      int structure = DetectMarketStructure(symbol, tfs[i]);
      if(direction == 1)
      {
         if(structure == MARKET_BULLISH) aligned++;
         else if(structure == MARKET_BEARISH) opposed++;
         else neutral++;
      }
      else
      {
         if(structure == MARKET_BEARISH) aligned++;
         else if(structure == MARKET_BULLISH) opposed++;
         else neutral++;
      }
   }

   if(aligned < g_AI_Min_Aligned_Structures)
      return false;

   if(opposed > g_AI_Max_Opposing_Structures)
      return false;

   return true;
}

STradingSignal GenerateAIPrimarySignal(string symbol, bool allow_range_mode,
                                       bool has_seeded_trend_direction = false,
                                       int seeded_trend_direction = 0)
{
   STradingSignal signal;
   g_debug_counters.signals_generated++;

   if(!g_Enable_AI_Trend_Predictor_Runtime || !g_ai_enabled)
   {
      signal.reason = "AI trend predictor disabled";
      return signal;
   }

   int symbol_index = -1;
   if(!RunCommonSignalPrechecks(symbol, signal, symbol_index, true, true, allow_range_mode,
                                has_seeded_trend_direction, seeded_trend_direction))
      return signal;

   if(!RunCommonSignalPostChecks(symbol, symbol_index, signal))
      return signal;

   double current_bid = g_symbols[symbol_index].cache.bid;
   double current_ask = g_symbols[symbol_index].cache.ask;
   if(current_bid <= 0 || current_ask <= 0 || current_bid >= current_ask)
   {
      signal.reason = "Invalid market prices";
      return signal;
   }

   int ai_rates_required = MathMax(GetAIProbabilitySnapshotRequiredBars(1),
                                   g_AI_Candle_Quality_Lookback_Bars + 2);
   MqlRates rates[];
   if(!GetCachedRates(symbol, Signal_TF, rates, ai_rates_required) || ArraySize(rates) < ai_rates_required)
   {
      signal.reason = "Insufficient rates for AI inference";
      return signal;
   }
   datetime latest_rate_time = rates[0].time;
   datetime latest_tick_time = g_symbols[symbol_index].cache.last_tick_time;
   if(latest_tick_time <= 0)
      latest_tick_time = g_symbols[symbol_index].cache.last_update;
   if(latest_tick_time <= 0)
      latest_tick_time = latest_rate_time;
   int max_rate_age = MathMax(30, Signal_Check_Seconds * 2);
   if(TimeCurrent() - latest_tick_time > max_rate_age)
   {
      signal.reason = "AI rates stale";
      return signal;
   }

   double atr_value = GetATRValue(symbol, Signal_TF);
   if(atr_value <= 0.0)
   {
      signal.reason = "Invalid ATR value";
      return signal;
   }
   double price_mid_check = (current_bid + current_ask) / 2.0;
   if(price_mid_check > 0.0 && atr_value > price_mid_check * 0.15)
   {
      signal.reason = "AI ATR out of bounds";
      return signal;
   }

   double spread = g_symbols[symbol_index].cache.spread * g_symbols[symbol_index].cache.point;
   int trend_direction = ResolveHTFBiasForSignalPass(symbol,
                                                     has_seeded_trend_direction,
                                                     seeded_trend_direction);
   int htf_struct = DetectMarketStructure(symbol, Confirm_TF);
   double htf_bias_feature = (double)trend_direction;
   if(htf_bias_feature == 0.0)
      htf_bias_feature = (htf_struct == MARKET_BULLISH ? 1.0 : htf_struct == MARKET_BEARISH ? -1.0 : 0.0);
   double vol_regime = GetCachedVolatilityFactor(symbol, symbol_index);

   double spread_to_atr = SafeDiv(spread, atr_value, 0.0);
   if(!g_Disable_All_Gates && g_AI_Max_Spread_to_ATR > 0.0 &&
      spread_to_atr > g_AI_Max_Spread_to_ATR)
   {
      signal.reason = StringFormat("AI spread/ATR filter blocked (%.3f > %.3f)",
                                   spread_to_atr, g_AI_Max_Spread_to_ATR);
      return signal;
   }

   double buy_min_prob = GetAIDirectionalMinProbability(1, symbol, symbol_index);
   double sell_min_prob = GetAIDirectionalMinProbability(-1, symbol, symbol_index);
   SAIProbabilitySnapshot live_snapshot;
   SAIProbabilitySnapshot confirmed_snapshot;
   bool live_snapshot_ok = BuildAIProbabilitySnapshot(symbol, symbol_index, rates, 0, spread, htf_bias_feature, vol_regime,
                                                      buy_min_prob, sell_min_prob, live_snapshot);
   bool confirmed_snapshot_ok = BuildAIProbabilitySnapshot(symbol, symbol_index, rates, 1, spread, htf_bias_feature, vol_regime,
                                                           buy_min_prob, sell_min_prob, confirmed_snapshot);
   if(!confirmed_snapshot_ok)
   {
      signal.reason = "AI confirmed snapshot failed: " + confirmed_snapshot.diag;
      return signal;
   }
   bool live_snapshot_fallback = false;
   if(!live_snapshot_ok)
   {
      string live_diag = live_snapshot.diag;
      live_snapshot = confirmed_snapshot;
      live_snapshot.shift = 0;
      live_snapshot.valid = true;
      live_snapshot.diag = "fallback_confirmed|" + live_diag + "|closed=" + confirmed_snapshot.diag;
      live_snapshot_fallback = true;
      if(g_Enable_Institutional_Debug)
      {
         LogTradeMessage(LOG_WARNING, "GenerateAIPrimarySignal", symbol,
                         "AI live snapshot fallback engaged", live_diag);
      }
   }

   double bar_progress = GetSignalBarProgress(symbol, Signal_TF);
   double snapshot_divergence = MathMax(MathAbs(live_snapshot.buy_prob - confirmed_snapshot.buy_prob),
                                        MathAbs(live_snapshot.sell_prob - confirmed_snapshot.sell_prob));
   double snapshot_stability = 1.0 - MathMin(1.0, snapshot_divergence / 0.25);
   if(!g_Disable_All_Gates && snapshot_divergence >= 0.22)
   {
      signal.reason = StringFormat("AI snapshot instability too high (%.3f)", snapshot_divergence);
      return signal;
   }
   if(!g_Disable_All_Gates &&
      live_snapshot.direction != 0 &&
      confirmed_snapshot.direction != 0 &&
      live_snapshot.direction != confirmed_snapshot.direction &&
      snapshot_divergence >= 0.08)
   {
      signal.reason = StringFormat("AI live/confirmed direction conflict (live=%s confirmed=%s div=%.3f)",
                                   (live_snapshot.direction == 1 ? "BUY" : "SELL"),
                                   (confirmed_snapshot.direction == 1 ? "BUY" : "SELL"),
                                   snapshot_divergence);
      return signal;
   }
   if(!g_Disable_All_Gates &&
      confirmed_snapshot.direction == 0 &&
      live_snapshot.direction != 0 &&
      bar_progress < 0.55 &&
      snapshot_divergence >= 0.06)
   {
      signal.reason = StringFormat("AI live direction not yet confirmed (progress=%.2f div=%.3f)",
                                   bar_progress, snapshot_divergence);
      return signal;
   }

   double live_weight = MathClamp(0.15 + bar_progress * 0.30, 0.15, 0.45);
   if(live_snapshot_fallback)
      live_weight = 0.0;
   if(confirmed_snapshot.direction == 0 && live_snapshot.direction != 0)
      live_weight = MathMin(live_weight, 0.25);
   if(live_snapshot.direction != 0 &&
      live_snapshot.direction == confirmed_snapshot.direction &&
      bar_progress >= 0.60)
      live_weight = MathMin(0.55, live_weight + 0.10);
   double confirmed_weight = 1.0 - live_weight;

   double buy_prob = confirmed_snapshot.buy_prob * confirmed_weight + live_snapshot.buy_prob * live_weight;
   double sell_prob = confirmed_snapshot.sell_prob * confirmed_weight + live_snapshot.sell_prob * live_weight;
   double stability_shrink = 0.70 + 0.30 * snapshot_stability;
   buy_prob = 0.5 + (buy_prob - 0.5) * stability_shrink;
   sell_prob = 0.5 + (sell_prob - 0.5) * stability_shrink;

   if(!MathIsValidNumber(buy_prob) || !MathIsValidNumber(sell_prob) ||
      buy_prob < 0.0 || buy_prob > 1.0 || sell_prob < 0.0 || sell_prob > 1.0)
   {
      signal.reason = "AI probabilities invalid";
      return signal;
   }

   double stability_penalty = MathMax(0.0, snapshot_divergence - 0.04);
   buy_min_prob = MathClamp(buy_min_prob + stability_penalty * 0.35, 0.45, 0.92);
   sell_min_prob = MathClamp(sell_min_prob + stability_penalty * 0.35, 0.45, 0.92);
   int ai_direction = SelectAIDirection(buy_prob, sell_prob, buy_min_prob, sell_min_prob);

   if(ai_direction == 0)
   {
      g_ai_signals_disagreed++;
      signal.reason = StringFormat("AI no directional edge (buy=%.3f sell=%.3f stable=%.2f)",
                                   buy_prob, sell_prob, snapshot_stability);
      return signal;
   }

   double ai_edge = MathAbs(buy_prob - sell_prob);
   double required_edge = g_AI_Min_Directional_Edge;
   if(!g_Disable_All_Gates && vol_regime > 1.20)
      required_edge += MathMin(0.12, (vol_regime - 1.20) * 0.06);
   if(!g_Disable_All_Gates && stability_penalty > 0.0)
      required_edge += MathMin(0.10, stability_penalty * 0.60);
   if(!g_Disable_All_Gates && ai_edge < required_edge)
   {
      g_ai_signals_disagreed++;
      signal.reason = StringFormat("AI edge too weak (edge=%.3f < %.3f)", ai_edge, required_edge);
      return signal;
   }

    bool allow_neutral_ai_context = (allow_range_mode || g_Allow_Neutral_Trend_Trading);
    if(trend_direction == 0)
    {
       if(!allow_neutral_ai_context)
       {
          signal.reason = "Calculated trend neutral - AI signal blocked";
          return signal;
       }
    }
    else if(ai_direction != trend_direction)
    {
       g_ai_signals_disagreed++;
       signal.reason = StringFormat("AI direction %s opposes calculated trend %s",
                                    (ai_direction == 1 ? "BUY" : "SELL"),
                                   (trend_direction == 1 ? "BUY" : "SELL"));
      return signal;
   }

   // DEBUG: MTF Regime Filter Gate Status
   bool mtf_gate_will_execute = (!g_Disable_All_Gates && g_Enable_AI_MTF_Regime_Filter);
   if(g_Enable_Institutional_Debug)
   {
      Log(LOG_DEBUG, "GenerateAIPrimarySignal", symbol +
          StringFormat(" - MTF Gate Check: g_Disable_All_Gates=%d, g_Enable_AI_MTF_Regime_Filter=%d => will_execute=%d",
                      g_Disable_All_Gates, g_Enable_AI_MTF_Regime_Filter, mtf_gate_will_execute));
   }
   
   if(!g_Disable_All_Gates && g_Enable_AI_MTF_Regime_Filter)
   {
      int aligned = 0, opposed = 0, neutral = 0;
      if(!EvaluateAIMTFRegimeAlignment(symbol, ai_direction, aligned, opposed, neutral))
      {
         signal.reason = StringFormat("AI MTF regime filter blocked (aligned=%d opposed=%d neutral=%d)",
                                      aligned, opposed, neutral);
         if(g_Enable_Institutional_Debug)
            Log(LOG_INFO, "GenerateAIPrimarySignal", symbol + " - MTF Regime Filter REJECTED: " + signal.reason);
         return signal;
      }
      else if(g_Enable_Institutional_Debug)
      {
         Log(LOG_DEBUG, "GenerateAIPrimarySignal", symbol + " - MTF Regime Filter PASSED (aligned=" +
             IntegerToString(aligned) + " opposed=" + IntegerToString(opposed) + " neutral=" + IntegerToString(neutral) + ")");
      }
   }
   else if(g_Enable_Institutional_Debug)
   {
      Log(LOG_DEBUG, "GenerateAIPrimarySignal", symbol + " - MTF Regime Filter SKIPPED (gate disabled)");
   }

   SAICandleQualityResult candle_quality = EvaluateAICandleQuality(symbol, ai_direction, rates,
                                                                   atr_value, current_bid, current_ask);
   if(!candle_quality.pass)
   {
      signal.reason = "AI candle quality filter blocked: " + candle_quality.reason;
      if(g_Enable_Institutional_Debug)
      {
         LogTradeMessage(LOG_INFO, "GenerateAIPrimarySignal", symbol,
                         "AI candle quality rejected", candle_quality.reason);
      }
      return signal;
   }

   if(g_Enable_Institutional_Debug)
   {
      LogTradeMessage(LOG_INFO, "GenerateAIPrimarySignal", symbol,
                      "AI candle quality passed", candle_quality.reason);
   }

   double raw_dir_prob = GetRawDirectionalAIProbability(ai_direction, buy_prob, sell_prob);
   double effective_dir_prob = GetEffectiveDirectionalAIProbability(ai_direction, buy_prob, sell_prob);
   int htf_bias_dir = trend_direction;
   double mid_price_cache = (current_bid + current_ask) / 2.0;
   int sig_struct_cache = DetectMarketStructure(symbol, Signal_TF);

   if(g_Enable_Institutional_Debug)
   {
      Log(LOG_INFO, "GenerateAIPrimarySignal",
          StringFormat("%s - AI direction model | Buy=%.3f Sell=%.3f BuyMin=%.3f SellMin=%.3f Effective=%.3f Stable=%.2f LiveW=%.2f",
                       symbol, buy_prob, sell_prob, buy_min_prob, sell_min_prob, effective_dir_prob,
                       snapshot_stability, live_weight));
      Log(LOG_INFO, "GenerateAIPrimarySignal",
          symbol + " - AI snapshots | Live{" + live_snapshot.diag + "} | Closed{" + confirmed_snapshot.diag + "}");
   }

   signal.direction = ai_direction;
   signal.origin = SIGNAL_ORIGIN_AI;
   signal.ai_probability = raw_dir_prob;
   signal.ai_confidence = effective_dir_prob;
   signal.ai_buy_probability = buy_prob;
   signal.ai_sell_probability = sell_prob;
   signal.ai_effective_probability = effective_dir_prob;
   signal.ai_directional_edge = (ai_direction == 1 ? buy_prob - sell_prob : sell_prob - buy_prob);
   signal.ai_min_probability_required = (ai_direction == 1 ? buy_min_prob : sell_min_prob);
   signal.ai_required_edge = required_edge;
   signal.ai_candle_quality_score = candle_quality.score;
   signal.ai_candle_quality_required = candle_quality.min_required_score;
   signal.ai_spread_to_atr = spread_to_atr;
   signal.ai_volatility_regime = vol_regime;
   signal.ai_agrees = true;

   if(Enable_Reversal_Detection)
   {
      SReversalSignal reversal_signal = g_reversal_detector.DetectReversal(symbol, Signal_TF, trend_direction);
      if(reversal_signal.valid)
      {
         signal.reversal_detected = true;
         signal.reversal_confidence = reversal_signal.confidence;
         signal.reversal_reason = reversal_signal.reason;
         g_reversal_signals_count++;

         if(g_Enable_Institutional_Debug)
         {
            LogTradeMessage(LOG_INFO, "GenerateAIPrimarySignal", symbol,
                            "AI reversal detected", reversal_signal.reason);
         }

         if(reversal_signal.direction == signal.direction)
         {
            g_reversal_confirmed_count++;
            if(g_Enable_Institutional_Debug)
            {
               LogTradeMessage(LOG_INFO, "GenerateAIPrimarySignal", symbol,
                               "Reversal confirms AI direction",
                               StringFormat("Confidence: %.1f%%", reversal_signal.confidence * 100.0));
            }
         }
         else if(reversal_signal.direction == -signal.direction)
         {
            if(reversal_signal.confidence > 0.70)
            {
               if(Reversal_Override_Direction)
               {
                  g_reversal_override_count++;
                  signal.reason = "AI trade vetoed by reversal override: " + reversal_signal.reason;
                  return signal;
               }

               // ICT-only opposing-reversal gate does not apply to AI pipeline.
               if(g_Enable_Institutional_Debug)
               {
                  LogTradeMessage(LOG_INFO, "GenerateAIPrimarySignal", symbol,
                                  "Strong opposing reversal tolerated", reversal_signal.reason);
               }
            }
            else if(g_Enable_Institutional_Debug)
            {
               LogTradeMessage(LOG_DEBUG, "GenerateAIPrimarySignal", symbol,
                               "Weak opposing reversal tolerated",
                               StringFormat("Confidence: %.1f%% | %s",
                                            reversal_signal.confidence * 100.0,
                                            reversal_signal.reason));
            }
         }
      }
   }

   g_ai_prediction_cache[symbol_index].probability = buy_prob;
   g_ai_prediction_cache[symbol_index].buy_prob = buy_prob;
   g_ai_prediction_cache[symbol_index].sell_prob = sell_prob;
   g_ai_prediction_cache[symbol_index].confidence = MathMax(buy_prob, sell_prob);
   g_ai_prediction_cache[symbol_index].last_update = TimeCurrent();
   g_ai_prediction_cache[symbol_index].tf = Signal_TF;
   g_ai_prediction_cache[symbol_index].bar_time = iTime(symbol, Signal_TF, 0);
   g_ai_prediction_cache[symbol_index].source_tick_msc =
      GetLatestSymbolTickMsc(symbol, symbol_index, false);
   if(g_ai_prediction_cache[symbol_index].created_time == 0)
      g_ai_prediction_cache[symbol_index].created_time = TimeCurrent();

   double current_price = (current_bid + current_ask) / 2.0;
   signal.entry_price = current_price;
   signal.atr_value = atr_value;

   double point = g_symbols[symbol_index].cache.point;
   if(point <= 0.0)
      point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
   {
      signal.reason = "Invalid point size";
      return signal;
   }

   double volatility_factor = GetCachedVolatilityFactor(symbol, symbol_index);
   double stop_distance = atr_value * g_ATR_SL_Multiplier_Active * volatility_factor;
   double min_stop_distance = point * 5.0;
   if(stop_distance < min_stop_distance)
      stop_distance = min_stop_distance;

   double target_rr = g_Min_RR_Ratio;
   if(g_AI_Use_Enhanced_Targets_Runtime)
   {
      double atr_rr = SafeDiv(g_ATR_TP_Multiplier_Active, MathMax(g_ATR_SL_Multiplier_Active, 0.0001), g_Min_RR_Ratio);
      double confidence_boost = MathClamp((effective_dir_prob - 0.5) * 2.0, 0.0, 1.0);
      double volatility_tilt = MathClamp(volatility_factor, 0.70, 1.80);
      target_rr = MathMax(g_Min_RR_Ratio, atr_rr * (0.90 + 0.20 * confidence_boost));
      if(volatility_tilt > 1.20)
         target_rr += (volatility_tilt - 1.20) * 0.20;
      target_rr = MathMin(target_rr, g_Min_RR_Ratio + 2.5);
   }

   if(signal.direction == 1)
   {
      signal.stop_loss = signal.entry_price - stop_distance;
      signal.take_profit = signal.entry_price + stop_distance * target_rr;
   }
   else
   {
      signal.stop_loss = signal.entry_price + stop_distance;
      signal.take_profit = signal.entry_price - stop_distance * target_rr;
   }

   STradeLevelContext trade_ctx;
   string trade_ctx_error = "";
   if(!BuildTradeLevelContext(symbol, symbol_index, trade_ctx, trade_ctx_error))
   {
      signal.reason = "AI " + trade_ctx_error;
      return signal;
   }

   int levels_reason = TRADE_LEVELS_OK;
   if(!NormalizeAndValidateTradeLevels(symbol, trade_ctx,
                                       signal.entry_price, signal.stop_loss, signal.take_profit,
                                       levels_reason))
   {
      signal.reason = "Invalid AI trade levels [" + TradeLevelsReasonLabel(levels_reason) + "]";
      return signal;
   }

   double risk_distance = MathAbs(signal.entry_price - signal.stop_loss);
   if(risk_distance <= trade_ctx.point)
   {
      signal.reason = "AI risk distance too small";
      return signal;
   }

   signal.risk_reward_ratio = CalculateTradeRiskRewardRatio(signal.entry_price, signal.stop_loss, signal.take_profit);
   double ai_min_rr_required = g_Min_RR_Ratio;
   if(!g_Disable_All_Gates &&
      effective_dir_prob < g_AI_Low_Confidence_Threshold)
   {
      ai_min_rr_required += g_AI_Low_Confidence_Extra_RR;
   }
   signal.valid = (signal.risk_reward_ratio >= ai_min_rr_required - 0.01);
   if(!signal.valid)
   {
      signal.reason = "AI RR ratio too low: " + DoubleToString(signal.risk_reward_ratio, 2) +
                      " (min " + DoubleToString(ai_min_rr_required, 2) + ")";
      return signal;
   }

   double expected_value_r = effective_dir_prob * signal.risk_reward_ratio - (1.0 - effective_dir_prob);
   signal.ai_expected_value_r = expected_value_r;

   if(!g_Disable_All_Gates && g_AI_Enable_EV_Filter)
   {
      if(expected_value_r < g_AI_Min_Expected_Value_R)
      {
         signal.valid = false;
         signal.reason = StringFormat("AI EV filter blocked (EV=%.2fR < %.2fR)",
                                      expected_value_r, g_AI_Min_Expected_Value_R);
         return signal;
      }
   }

   if(!FinalizeStrategySignalBasics(symbol, signal, SIGNAL_ORIGIN_AI, "AI"))
      return signal;

   signal.strategy_output_summary = BuildAISignalSummary(signal, true) +
                                    StringFormat(" Stable=%.2f", snapshot_stability);
   signal.strategy_output_detail = BuildAISignalSummary(signal, false) +
                                   StringFormat(" Stable=%.2f LiveW=%.2f Live[%s] Closed[%s]",
                                                snapshot_stability, live_weight,
                                                live_snapshot.diag, confirmed_snapshot.diag);

   if(!g_Disable_All_Gates && g_Enable_Institutional_Debug)
   {
      Log(LOG_INFO, "GenerateAIPrimarySignal",
          StringFormat("%s - AI execution quality | spreadATR=%.3f edge=%.3f rr=%.2f reqRR=%.2f tieBreak=%s",
                       symbol, spread_to_atr, ai_edge, signal.risk_reward_ratio, ai_min_rr_required,
                       (g_AI_Allow_Relaxed_TieBreak ? "RELAXED" : "STRICT")));
   }

   if(Enable_All_Institutional_Filters)
   {
      if(!ApplyScoringGate(symbol, Signal_TF, signal, effective_dir_prob, atr_value, htf_bias_dir, "AI",
                           symbol_index, mid_price_cache, sig_struct_cache, false))
         return signal;
   }

   signal.reason = StringFormat("AI primary signal | RR=%.2f | %s",
                                signal.risk_reward_ratio, signal.strategy_output_summary);
   g_ai_signals_confirmed++;
   if(signal.ai_confidence > 0.75)
      g_ai_high_confidence_trades++;
   LogTradeMessage(LOG_DEBUG, "GenerateAIPrimarySignal", symbol, "AI signal ready", signal.reason);
   return signal;
}


STradingSignal GenerateTradingSignal(string symbol)
{
   // Route the request based on user-selected strategy mix so tests/diagnostics
   // respect the same logic as the live signal loop.
   STradingSignal result;

   bool ai_available = (g_Enable_AI_Trend_Predictor_Runtime && g_ai_enabled);
   int symbol_index = GetSymbolIndex(symbol);
   int auto_mode = AUTO_REGIME_MODE_DISABLED;
   string auto_reason = "";
   int auto_htf_score = 0;
   double auto_volatility = 1.0;
   bool auto_first_retracement = false;
   bool auto_discount_zone = false;
   SRoutingMatrix route = BuildEffectiveRoutingMatrix(symbol, symbol_index, ai_available,
                                                      auto_mode, auto_reason,
                                                      auto_htf_score, auto_volatility,
                                                      auto_first_retracement, auto_discount_zone);
   int trend_direction = GetHTFBiasInstitutional(symbol);
   bool auto_range_mode = ((g_Enable_Auto_Regime_Router || route.suitability_enforced) &&
                           route.suitability_mode == AUTO_REGIME_MODE_INTRA_HIGHLOW);
   bool allow_range_mode = (g_Allow_Range_Trading || auto_range_mode);

   if(route.fail_reason != "" && !route.ict_allowed && !route.ai_allowed && !route.kim_allowed)
   {
      result.reason = "Routing blocked: " + route.fail_reason;
      return result;
   }

   if(g_Enable_Auto_Regime_Router && g_Enable_Institutional_Debug)
   {
      Log(LOG_DEBUG, "GenerateTradingSignal",
          symbol + " - Auto regime=" + AutoRegimeModeToString(auto_mode) +
          " | " + auto_reason +
          " | HTF=" + IntegerToString(auto_htf_score) +
          " | Vol=" + DoubleToString(auto_volatility, 2) +
          " | FirstRetrace=" + (auto_first_retracement ? "Y" : "N") +
          " | Discount=" + (auto_discount_zone ? "Y" : "N"));
   }
   else if(route.suitability_enforced && g_Enable_Institutional_Debug)
   {
      Log(LOG_DEBUG, "GenerateTradingSignal",
          symbol + " - Suitability role=" + AutoRegimeModeToString(route.suitability_mode) +
          " | HuntMode=" + SuitabilityHuntModeToString(g_Suitability_Hunt_Mode) +
          " | " + auto_reason +
          " | HTF=" + IntegerToString(auto_htf_score) +
          " | Vol=" + DoubleToString(auto_volatility, 2));
   }

   // Keep diagnostics/test routing aligned with live ProcessSignals() behavior.
   if(route.require_both && (!route.ict_allowed || !route.ai_allowed))
   {
      result.reason = "BOTH mode blocked: required strategy unavailable (ICT=" +
                      (route.ict_allowed ? "ON" : "OFF") + ", AI=" +
                      (route.ai_allowed ? "ON" : "OFF") + ")";
      return result;
   }

   if(!ValidateGoldTradingConditions(symbol))
   {
      if(g_DryRun_TradeBlock_Active && g_Enable_Strategy_DryRun_On_TradeBlock)
      {
         result.reason = "GOLD trading conditions not met (dry-run diagnostics mode)";
         Log(LOG_DEBUG, "SignalPrecheck", symbol + " - " + result.reason);
      }
      else
      {
         result.reason = "GOLD trading conditions not met";
         Log(LOG_INFO, "SignalPrecheck", symbol + " - " + result.reason);
         return result;
      }
   }

   if(trend_direction == 0 && !allow_range_mode && !g_Allow_Neutral_Trend_Trading)
   {
      result.reason = "Calculated trend neutral - trading blocked";
      return result;
   }

   // Keep diagnostics/test path aligned with live ProcessSignals() precheck.
   int signal_structure_now = DetectMarketStructure(symbol, Signal_TF);
   if(signal_structure_now == MARKET_RANGE && !allow_range_mode)
   {
      result.reason = "Signal_TF range - trading blocked";
      return result;
   }

   STradingSignal ict_signal;
   STradingSignal ai_signal;
   STradingSignal kim_signal;
   STradingSignal reversal_signal;  // Default invalid signal for synergy calculation
   bool ict_valid = false;
   bool ai_valid  = false;
   bool kim_valid = false;
   double ai_fallback_min_prob = 0.0;
   // Probe only strategies that are both enabled and allowed by the effective routing matrix.
   // This keeps reject telemetry aligned with the actual execution route and avoids
   // counting route-disabled strategies as live pipeline failures.
   bool probe_ict = (g_Enable_ICT_Strategy && route.ict_allowed);
   bool probe_ai = (g_Enable_AI_Strategy && ai_available && route.ai_allowed);
   bool probe_kim = (g_Enable_KImaniz_Strategy && route.kim_allowed);

   if(probe_ict)
   {
      g_Signal_Stats_ICT_Total_Attempts++;  // Track ICT attempt
      ict_signal = GenerateICTSignal(symbol, allow_range_mode, true, trend_direction);
      if(ict_signal.valid && ai_available &&
         !route.require_both && route.ai_allowed &&
         g_AI_Signal_Generation_Mode != AI_SIGNAL_MODE_PRIMARY)
         ApplyAIValidationToSignal(symbol, ict_signal);
      ict_valid = ict_signal.valid;
      if(ict_valid)
      {
         ict_valid = HardenStrategySignal(symbol, symbol_index, allow_range_mode, trend_direction, ict_signal, "ICT");
         if(ict_valid)
            g_Signal_Stats_ICT_Valid++;  // Track executable ICT signal after hardening
      }
   }

   if(probe_ai)
   {
      g_Signal_Stats_AI_Total_Attempts++;  // Track AI attempt
      ai_signal = GenerateAIPrimarySignal(symbol, allow_range_mode, true, trend_direction);
      ai_valid = ai_signal.valid;
      if(ai_valid)
      {
         ai_valid = HardenStrategySignal(symbol, symbol_index, allow_range_mode, trend_direction, ai_signal, "AI");
         if(ai_valid)
            g_Signal_Stats_AI_Valid++;  // Track executable AI signal after hardening
      }
      if(ai_valid)
      {
         ai_fallback_min_prob = GetAIDirectionalMinProbability(ai_signal.direction, symbol, symbol_index);
         ai_fallback_min_prob = MathClamp(ai_fallback_min_prob, 0.50, 0.90);
      }
   }

   if(probe_kim)
   {
      g_Signal_Stats_KIM_Total_Attempts++;  // Track Kimaniz attempt
      kim_signal = GenerateKImanizSignal(symbol, allow_range_mode, true, trend_direction);
      kim_valid = kim_signal.valid;
      if(kim_valid)
      {
         kim_valid = HardenStrategySignal(symbol, symbol_index, allow_range_mode, trend_direction, kim_signal, "KIM");
         if(kim_valid)
            g_Signal_Stats_KIM_Valid++;  // Track executable Kimaniz signal after hardening
      }
   }

   string selection_stage = "";
   ResolveSelectedSignalFromCandidates(symbol, symbol_index, trend_direction, route,
                                       ict_signal, ict_valid,
                                       ai_signal, ai_valid,
                                       kim_signal, kim_valid,
                                       ai_fallback_min_prob,
                                       result, selection_stage);
   
   // === TIER 1A ENHANCEMENT: APPLY PIPELINE SYNERGIES ===
   if(result.valid && result.direction != 0)
   {
      SStrategySynergyScore synergy = g_pipeline_synergy.CalculatePipelineSynergies(
         symbol, result.direction,
         ict_signal, ai_signal, kim_signal, reversal_signal,
         symbol_index
      );
      
      // Apply synergy factor to boost/penalize based on multi-source agreement
      g_pipeline_synergy.ApplySynergyToSignal(result, synergy);
      
      // Log synergy for diagnostics
      if(g_Enable_Institutional_Debug)
      {
         Log(LOG_DEBUG, "GenerateTradingSignal", symbol + " Synergies: " + synergy.synergy_breakdown);
      }
   }
   // === END TIER 1A ENHANCEMENT ===
   
    if(result.valid)
       FinalizeSelectedSignal(symbol, symbol_index, allow_range_mode, trend_direction,
                              route,
                              (StringLen(selection_stage) > 0 ? selection_stage : "FINAL"),
                              result);

    LogStrategyCandidateSnapshot("GenerateTradingSignal",
                                 symbol,
                                 route,
                                 probe_ict,
                                 probe_ai,
                                 probe_kim,
                                 ict_signal,
                                 ict_valid,
                                 ai_signal,
                                 ai_valid,
                                 kim_signal,
                                 kim_valid,
                                 result,
                                 selection_stage);
    return result;
}

void ProcessSignals()
{
   static datetime last_cooldown_log = 0;
   static datetime last_lock_unavailable_log = 0;
   static datetime last_completion_heartbeat = 0;
   static datetime last_pipeline_heartbeat = 0;
   static datetime last_trade_not_allowed_log = 0;
   static datetime last_ai_mode_fallback_log = 0;
   static datetime last_tick_fallback_log[MAX_SYMBOLS];
   static datetime last_forced_continuous_log[MAX_SYMBOLS];
   static datetime last_bar_cooldown_log[MAX_SYMBOLS];
   static datetime last_bar_cooldown_bar[MAX_SYMBOLS];
   static int completion_calls = 0;
   static datetime last_housekeeping_slice = 0;
   static datetime last_retry_slice = 0;

   // CRITICAL FIX: Prevent trading during initialization period
   if(!g_initialization_complete)
   {
      datetime current_time = TimeCurrent();
      if(current_time - g_initialization_time < INITIALIZATION_COOLDOWN_SECONDS)
      {
         if(last_cooldown_log == 0 || (current_time - last_cooldown_log) >= 5)
         {
            Log(LOG_INFO, "ProcessSignals", "Initialization cooldown active - " +
                IntegerToString(INITIALIZATION_COOLDOWN_SECONDS - (current_time - g_initialization_time)) +
                " seconds remaining");
            last_cooldown_log = current_time;
         }
         return;
      }
      else
      {
         g_initialization_complete = true;
         Log(LOG_INFO, "ProcessSignals", "Initialization cooldown complete - trading now active");
         SendAlert(ALERT_INFO, "ProfitTrailBot initialization complete - trading is now active");
      }
   }
   
   // RAII lock guard
   bool lock_acquired = AcquireProcessingLock();
   if(!lock_acquired)
   {
      datetime now = TimeCurrent();
      if(last_lock_unavailable_log == 0 || (now - last_lock_unavailable_log) >= 10)
      {
         Log(LOG_DEBUG, "ProcessSignals", "Processing lock not available - skipping");
         last_lock_unavailable_log = now;
      }
      return;
   }
   auto_release_lock _lock_guard(lock_acquired);
   datetime current_time = TimeCurrent();
   g_DryRun_TradeBlock_Active = false;
   static bool hb_effective_seeded[MAX_SYMBOLS];
   static bool hb_effective_ict[MAX_SYMBOLS];
   static bool hb_effective_ai[MAX_SYMBOLS];
   static bool hb_effective_kim[MAX_SYMBOLS];
   static bool hb_effective_both[MAX_SYMBOLS];
   static bool hb_effective_director[MAX_SYMBOLS];
   static int hb_effective_mode[MAX_SYMBOLS];
   static int hb_effective_director_strategy[MAX_SYMBOLS];
   static datetime hb_effective_time[MAX_SYMBOLS];
     
   g_last_process_time = current_time;
  
   static datetime last_process_log = 0;
   if((current_time - last_process_log) >= 60)
   {
      last_process_log = current_time;
      Log(LOG_INFO, "ProcessSignals", "Processing signals at " + TimeToString(current_time) + 
          " (Signals: " + IntegerToString(g_debug_signal_count) + 
          ", Executed: " + IntegerToString(g_debug_trades_executed) + 
          ", Failed: " + IntegerToString(g_debug_trades_failed) + 
          ", Errors: " + IntegerToString(g_debug_errors) + ")");
   }

   // Strategy pipeline heartbeat for reachability diagnostics (once per minute)
   if((current_time - last_pipeline_heartbeat) >= 60)
   {
      last_pipeline_heartbeat = current_time;
      int hb_our_positions = 0;
      int hb_our_pending = 0;
      for(int pi = PositionsTotal() - 1; pi >= 0; pi--)
      {
         ulong pticket = PositionGetTicket(pi);
         if(pticket == 0 || !PositionSelectByTicket(pticket))
            continue;
         long pmagic = PositionGetInteger(POSITION_MAGIC);
         if(pmagic >= Magic_Base && pmagic < Magic_Base + 10000)
            hb_our_positions++;
      }
      for(int oi = OrdersTotal() - 1; oi >= 0; oi--)
      {
         ulong oticket = OrderGetTicket(oi);
         if(oticket == 0 || !OrderSelect(oticket))
            continue;
         long omagic = OrderGetInteger(ORDER_MAGIC);
         if(omagic >= Magic_Base && omagic < Magic_Base + 10000)
            hb_our_pending++;
      }
      string concurrent_cap = IntegerToString(g_Max_Concurrent_Trades_Effective);
      string route_label = StrategyRoutingModeToString(g_Strategy_Routing_Mode);
      string strict_both = (g_Strategy_Routing_Mode == STRATEGY_ROUTING_BOTH &&
                            !g_Allow_AI_Fallback_In_BOTH_Mode ? "YES" : "NO");
      string top_rejects_hb = GetTopRejectReasonsSummary(3);
      if(StringLen(top_rejects_hb) == 0)
         top_rejects_hb = "none";

      string effective_route_hb = "n/a";
      if(g_symbols_count > 0)
      {
         int ei = 0;
         if(ei >= 0 && ei < MAX_SYMBOLS && hb_effective_seeded[ei])
         {
            string mode_txt = AutoRegimeModeToString(hb_effective_mode[ei]);
            string director_strategy_txt = "n/a";
            if(hb_effective_director[ei] && hb_effective_director_strategy[ei] >= 0)
               director_strategy_txt = DirectorStrategyModeToString((ENUM_DIRECTOR_STRATEGY_MODE)hb_effective_director_strategy[ei]);
            int route_age = (hb_effective_time[ei] > 0 ? (int)(current_time - hb_effective_time[ei]) : -1);
            effective_route_hb = StringFormat("%s{ICT=%s,AI=%s,KIM=%s,BOTH=%s,Mode=%s,Director=%s,DirStrat=%s,Age=%ds}",
                                              g_symbols[ei].name,
                                              (hb_effective_ict[ei] ? "Y" : "N"),
                                              (hb_effective_ai[ei] ? "Y" : "N"),
                                              (hb_effective_kim[ei] ? "Y" : "N"),
                                              (hb_effective_both[ei] ? "Y" : "N"),
                                              mode_txt,
                                              (hb_effective_director[ei] ? "Y" : "N"),
                                              director_strategy_txt,
                                              route_age);
         }
      }

      string hb = "Route=" + IntegerToString((int)g_Strategy_Routing_Mode) + "(" + route_label + ")" +
                  " ICT=" + (g_Enable_ICT_Strategy ? "ON" : "OFF") +
                  " AI=" + (g_Enable_AI_Strategy ? "ON" : "OFF") +
                  " AIavail=" + (g_Enable_AI_Trend_Predictor_Runtime && g_ai_enabled ? "YES" : "NO") +
                  " StrictBOTH=" + strict_both +
                  " AIFallbackInBOTH=" + (g_Allow_AI_Fallback_In_BOTH_Mode ? "ON" : "OFF") +
                  " ICTFallbackInBOTH=" + (g_Allow_ICT_Fallback_In_BOTH_Mode ? "ON" : "OFF") +
                  " AIAgreeGate=" + (g_AI_Require_Agreement_Runtime ? "ON" : "OFF") +
                  " Director=" + (g_Use_Institutional_Strategy_Director ? "ON" : "OFF") +
                  " AutoRegime=" + (g_Enable_Auto_Regime_Router ? "ON" : "OFF") +
                  " KIM=" + (g_Enable_KImaniz_Strategy ? "ON" : "OFF") +
                  " KIMonly=" + (g_KImaniz_Only_Mode ? "YES" : "NO") +
                  " NewBarOnly=" + (g_Signal_On_New_Bar_Only ? "ON" : "OFF") +
                  " DryRunOnBlock=" + (g_Enable_Strategy_DryRun_On_TradeBlock ? "ON" : "OFF") +
                  " MaxConcurrent(input/eff/open+pending)=" + IntegerToString(Max_Concurrent_Trades) +
                  "/" + concurrent_cap + "/" + IntegerToString(hb_our_positions + hb_our_pending) +
                  " (open=" + IntegerToString(hb_our_positions) +
                  ",pending=" + IntegerToString(hb_our_pending) + ")" +
                  " RetryQ=" + IntegerToString(g_retry_count) +
                  " TopRejects=" + top_rejects_hb +
                  " EffRoute=" + effective_route_hb;
      Log(LOG_INFO, "PipelineHeartbeat", hb);
   }

   // Use bar time for cooldown gating reference
   datetime bar_time = iTime(Symbol(), Signal_TF, 0);

   bool trade_allowed_now = IsTradeAllowed();
   static bool previous_trade_allowed = true;
   if(trade_allowed_now && !previous_trade_allowed)
   {
      ResetRejectReasonBuckets();
      Log(LOG_INFO, "ProcessSignals",
          "Trade allowance restored - reject reason buckets reset for fresh pipeline diagnostics");
   }
   previous_trade_allowed = trade_allowed_now;
   bool dry_run_on_block = false;
   if(!trade_allowed_now)
   {
      RecordRejectReason("PIPE:TradeNotAllowed");
      if(last_trade_not_allowed_log == 0 || (current_time - last_trade_not_allowed_log) >= 30)
      {
         Log(LOG_WARNING, "ProcessSignals", "Trade not allowed");
         last_trade_not_allowed_log = current_time;
      }

      // Keep risk/session bookkeeping active even when opening new trades is blocked.
      if((current_time - last_housekeeping_slice) >= MathMax(1, Signal_Check_Seconds))
      {
         last_housekeeping_slice = current_time;
         PruneStaleRetryQueue();
         CleanupExpiredPendingOrders();
         ManageOpenPositions();
         TrackClosedTrades();
      }

      if(g_Enable_Strategy_DryRun_On_TradeBlock)
      {
         dry_run_on_block = true;
         g_DryRun_TradeBlock_Active = true;
         static datetime last_dry_run_log = 0;
         if(last_dry_run_log == 0 || (current_time - last_dry_run_log) >= 60)
         {
            Log(LOG_INFO, "ProcessSignals",
                "Trade blocked - running strategy pipeline in DRY-RUN mode (execution disabled)");
            last_dry_run_log = current_time;
         }
      }
   }
   if(trade_allowed_now || dry_run_on_block)
   {
      // Process trade retries only when live execution is allowed.
      if(trade_allowed_now && current_time - last_retry_slice >= MathMax(1, g_Retry_Interval_Seconds))
      {
         last_retry_slice = current_time;

         if(g_retry_count < 0)
            g_retry_count = 0;
         PruneStaleRetryQueue();

         if(g_retry_count > MAX_RETRY_QUEUE)
         {
            Log(LOG_ERROR, "ProcessSignals", "Retry queue overflow detected, resetting");
            g_retry_count = MAX_RETRY_QUEUE;
         }

         int retry_interval = MathMax(1, g_Retry_Interval_Seconds);
         
         for(int i = g_retry_count - 1; i >= 0; i--)
         {
            if(i < 0 || i >= MAX_RETRY_QUEUE)
               break;
            
            if(g_trade_retries[i].next_retry <= current_time)
            {
               bool trade_executed = ProcessTradeRetry(g_trade_retries[i]);
               
                if(trade_executed)
                {
                   RemoveRetryQueueItem(i);
                }
                else if(g_trade_retries[i].attempt >= g_Max_Retry_Attempts)
                {
                   Log(LOG_WARNING, "ProcessSignals", g_trade_retries[i].symbol + " - Max retries reached");
                   RemoveRetryQueueItem(i);
                }
                else if(g_trade_retries[i].next_retry > current_time)
                {
                   // Deferred by ProcessTradeRetry pre-checks (session/spread/market state).
                   continue;
                }
                else if(++g_trade_retries[i].attempt >= g_Max_Retry_Attempts)
               {
                  RecordRejectReason("RETRY:MaxAttemptsReached");
                  Log(LOG_WARNING, "ProcessSignals", g_trade_retries[i].symbol + " - Max retries reached");
                  RemoveRetryQueueItem(i);
               }
               else
               {
                  g_trade_retries[i].next_retry = current_time + retry_interval;
               }
            }
         }
      }

      // Housekeeping keyed to bar and time intervals, time-sliced to reduce lock hold
      static datetime last_housekeeping_bar = 0;
      static datetime last_housekeeping_time = 0;
      bool do_housekeeping = false;
      double tf_seconds = (double)PeriodSeconds(Signal_TF);
      if(tf_seconds <= 0) tf_seconds = 60.0;
      if(bar_time != 0 && (last_housekeeping_bar == 0 || (bar_time - last_housekeeping_bar) >= Housekeeping_Bar_Interval * tf_seconds))
         do_housekeeping = true;
      if((current_time - last_housekeeping_time) >= Housekeeping_Interval_Seconds)
         do_housekeeping = true;

      if(do_housekeeping && (current_time - last_housekeeping_slice) >= MathMax(1, Signal_Check_Seconds))
      {
         last_housekeeping_bar = bar_time;
         last_housekeeping_time = current_time;
         last_housekeeping_slice = current_time;

         CleanupExpiredPendingOrders();
         ManageOpenPositions();
         TrackClosedTrades();

         // Periodic ATR handle validation to avoid stale handles
         if(ATR_Handle_Validate_Bars > 0)
         {
            for(int si = 0; si < g_symbols_count; si++)
            {
               datetime symbol_bar_time = iTime(g_symbols[si].name, Signal_TF, 0);
               if(symbol_bar_time <= 0)
                  symbol_bar_time = bar_time;

               double bars_delta = (symbol_bar_time - g_symbols[si].last_atr_validate_bar) / tf_seconds;
               if(g_symbols[si].last_atr_validate_bar == 0 || bars_delta >= ATR_Handle_Validate_Bars)
               {
                  ValidateATRHandle(g_symbols[si].name, si, Signal_TF, g_ATR_Period_Active);
                  g_symbols[si].last_atr_validate_bar = symbol_bar_time;
               }
            }
         }
      }

      // Generate signals for each symbol
      static datetime last_no_new_bar_log[MAX_SYMBOLS];
      static datetime last_new_bar_wait_log[MAX_SYMBOLS];
      static datetime last_range_skip_log[MAX_SYMBOLS];
      static int last_auto_regime_mode[MAX_SYMBOLS];
      static bool auto_regime_seeded[MAX_SYMBOLS];
      int symbol_process_count = MathMin(g_symbols_count, MAX_SYMBOLS);
      static bool symbol_count_cap_warned = false;
      if(!symbol_count_cap_warned && g_symbols_count > MAX_SYMBOLS)
      {
         Log(LOG_WARNING, "ProcessSignals",
             "Symbol count exceeds MAX_SYMBOLS (" + IntegerToString(g_symbols_count) +
             " > " + IntegerToString(MAX_SYMBOLS) + "). Processing is capped for safety.");
         symbol_count_cap_warned = true;
      }

      for(int i = 0; i < symbol_process_count; i++)
      {
         if(IsStopped()) break;
         
         string symbol = g_symbols[i].name;

         datetime current_bar = iTime(symbol, Signal_TF, 0);
         if(current_bar <= 0)
         {
            Log(LOG_DEBUG, "ProcessSignals", "No bar data yet for " + symbol + " on " + EnumToString(Signal_TF));
            continue;
         }
         
         if(g_debug_signals_enabled)
         {
            int log_gap_seconds = MathMax(60, Signal_Check_Seconds);
            if(current_time - last_no_new_bar_log[i] >= log_gap_seconds)
            {
               Log(LOG_DETAILED, "ProcessSignals", "Checking " + symbol + " - Last bar: " +
                   TimeToString(g_symbols[i].last_bar_time) + ", Current bar: " + TimeToString(current_bar));
            }
         }
         
         bool should_process = false;
         bool require_new_bar_for_processing = (g_Signal_On_New_Bar_Only && !g_Force_Signal_Cadence_Gate_Off);
         bool prefer_new_bar_with_fallback = (!g_Signal_On_New_Bar_Only && !g_Force_Signal_Cadence_Gate_Off);
         bool first_bar = (g_symbols[i].last_bar_time == 0);
         bool did_bar_transition_invalidation = false;
         
         if(first_bar)
         {
            g_symbols[i].last_bar_time = current_bar;
            g_symbols[i].last_processed_time = current_time; // seed timer fallback baseline
            InvalidateSymbolRuntimeCaches(i, true);
            // ADDED: Force explicit cache refresh on startup to ensure clean state
            ForceRefreshSignalCache(i);
            did_bar_transition_invalidation = true;

            if(require_new_bar_for_processing)
            {
               if(g_Process_Startup_Seed_Bar)
               {
                  should_process = true;
                  Log(LOG_INFO, "ProcessSignals", "Seeded initial bar state for " + symbol +
                      " at " + TimeToString(current_bar) + " - processing startup seed bar once" +
                      " (newBarOnly=" + (g_Signal_On_New_Bar_Only ? "ON" : "OFF") +
                      ", cadenceForceOff=" + (g_Force_Signal_Cadence_Gate_Off ? "ON" : "OFF") + ")");
               }
               else
               {
                  Log(LOG_INFO, "ProcessSignals", "Seeded initial bar state for " + symbol +
                      " at " + TimeToString(current_bar) + " - waiting for next new bar" +
                      " (newBarOnly=" + (g_Signal_On_New_Bar_Only ? "ON" : "OFF") +
                      ", cadenceForceOff=" + (g_Force_Signal_Cadence_Gate_Off ? "ON" : "OFF") + ")");
               }
            }
            else
            {
               should_process = true;
               Log(LOG_INFO, "ProcessSignals", "First bar processing for " + symbol + " at " + TimeToString(current_bar) +
                   " (newBarOnly=" + (g_Signal_On_New_Bar_Only ? "ON" : "OFF") +
                   ", cadenceForceOff=" + (g_Force_Signal_Cadence_Gate_Off ? "ON" : "OFF") + ")");
            }
         }
         else if(current_bar > g_symbols[i].last_bar_time)
         {
            g_symbols[i].last_bar_time = current_bar;
            should_process = true;
            Log(LOG_INFO, "ProcessSignals", "New bar for " + symbol + " at " + TimeToString(current_bar));

            InvalidateSymbolRuntimeCaches(i, true);
            // ADDED: Force explicit cache refresh to ensure no stale indicator values
            ForceRefreshSignalCache(i);
            did_bar_transition_invalidation = true;

            if(Enable_AI_Continuous_Training_Export)
            {
               AppendAITrainingSampleCSV(symbol, Signal_TF, AI_CONTINUOUS_TRAINING_FILE, 2, g_ai_last_continuous_export_time[i]);
            }
         }
         // Timer-based fallback: if enough time passed, process even without new bar
         else if(!require_new_bar_for_processing)
         {
            int elapsed_since_process = (int)(current_time - g_symbols[i].last_processed_time);
            int tick_interval = MathMax(1, Signal_Check_Seconds);

            if(g_Force_Signal_Cadence_Gate_Off)
            {
               should_process = true;
               int forced_log_gap = MathMax(60, Signal_Check_Seconds);
               if(last_forced_continuous_log[i] == 0 || (current_time - last_forced_continuous_log[i]) >= forced_log_gap)
               {
                  Log(LOG_DEBUG, "ProcessSignals", "Continuous processing forced for " + symbol +
                      " (cadence gate disabled)");
                  last_forced_continuous_log[i] = current_time;
               }
            }
            else if(prefer_new_bar_with_fallback)
            {
               int tf_seconds_local = PeriodSeconds(Signal_TF);
               if(tf_seconds_local <= 0)
                  tf_seconds_local = 60;

               // AUTO mode should prefer confirmed new bars and only fall back to cadence
               // when the bar feed has stalled past the expected next bar boundary.
               int stale_bar_age = (int)(current_time - g_symbols[i].last_bar_time);
               int auto_fallback_after = tf_seconds_local + tick_interval;
               bool auto_fallback_due = (g_symbols[i].last_bar_time > 0 && stale_bar_age >= auto_fallback_after);
               if(auto_fallback_due &&
                  (g_symbols[i].last_processed_time == 0 || elapsed_since_process >= tick_interval))
               {
                  should_process = true;
                  int fallback_log_gap = MathMax(30, tick_interval);
                  if(last_tick_fallback_log[i] == 0 || (current_time - last_tick_fallback_log[i]) >= fallback_log_gap)
                  {
                     Log(LOG_DEBUG, "ProcessSignals", "AUTO cadence fallback for " + symbol +
                         " (lastBarAge=" + IntegerToString(stale_bar_age) + "s, threshold=" +
                         IntegerToString(auto_fallback_after) + "s)");
                     last_tick_fallback_log[i] = current_time;
                  }
               }
            }
            else
            {
               // In continuous mode, still honor the configured signal-check cadence
               // to avoid redundant full-pipeline scans every tick.
               if(g_symbols[i].last_processed_time == 0 || elapsed_since_process >= tick_interval)
               {
                  should_process = true;
                  int fallback_log_gap = MathMax(30, tick_interval);
                  if(last_tick_fallback_log[i] == 0 || (current_time - last_tick_fallback_log[i]) >= fallback_log_gap)
                  {
                     Log(LOG_DEBUG, "ProcessSignals", "Tick fallback for " + symbol +
                         " (elapsed " + IntegerToString(elapsed_since_process) + "s)");
                     last_tick_fallback_log[i] = current_time;
                  }
               }
            }
         }
         else
         {
            // Strict NEW_BAR_ONLY mode: never process on timer fallback.
            // This avoids same-bar reprocessing from stale intra-bar cache state.
         }
         
         // Master bypass intentionally does not override cadence semantics here.
         // It bypasses optional validation gates, not bar/timer scheduling.

         // In continuous cadence mode, force fresh indicator/feature snapshots per processing pass.
         if(should_process && !did_bar_transition_invalidation && !require_new_bar_for_processing)
            InvalidateSymbolRuntimeCaches(i, false);

         if(!should_process)
         {
            int wait_remaining = (g_Force_Signal_Cadence_Gate_Off ? 0 :
                                  Signal_Check_Seconds - (int)(current_time - g_symbols[i].last_processed_time));
            if(wait_remaining < 0) wait_remaining = 0;
            if(require_new_bar_for_processing || prefer_new_bar_with_fallback)
            {
               int tf_seconds_local = PeriodSeconds(Signal_TF);
               if(tf_seconds_local <= 0)
                  tf_seconds_local = 60;
               int next_bar_eta = (int)((g_symbols[i].last_bar_time + tf_seconds_local) - current_time);
               if(next_bar_eta < 0)
                  next_bar_eta = 0;
               if(last_new_bar_wait_log[i] == 0 || (current_time - last_new_bar_wait_log[i]) >= 60)
               {
                  string cadence_label = (require_new_bar_for_processing ? "NEW_BAR_ONLY" : "AUTO");
                  string fallback_suffix = "";
                  if(prefer_new_bar_with_fallback)
                     fallback_suffix = " | cadence fallback after " +
                                       IntegerToString(tf_seconds_local + MathMax(1, Signal_Check_Seconds)) + "s stale bar age";
                  Log(LOG_INFO, "ProcessSignals",
                      "Skipping " + symbol + " - " + cadence_label + " waiting for next bar after " +
                      TimeToString(g_symbols[i].last_bar_time) + " (eta " + IntegerToString(next_bar_eta) + "s" +
                      fallback_suffix + ")");
                  last_new_bar_wait_log[i] = current_time;
               }
            }
            else if(g_debug_signals_enabled)
            {
               int log_gap_seconds = MathMax(60, Signal_Check_Seconds);
               if(current_time - last_no_new_bar_log[i] >= log_gap_seconds)
               {
                  Log(LOG_DETAILED, "ProcessSignals", "Skipping " + symbol + " - No new bar; wait " + IntegerToString(wait_remaining) + "s for timer");
                  last_no_new_bar_log[i] = current_time;
               }
            }
            continue;
         }

         // Heavy checks deferred until we know we will process this symbol
         // Prefill HTF bias cache for all core TFs for this symbol
         PrefillHTFBiasCaches(symbol);

         if(!IsMarketOpen(symbol))
         {
            RecordRejectReason("PIPE:MarketClosed");
            Log(LOG_INFO, "ProcessSignals", "Market closed for " + symbol);
            continue;
         }
         
         bool is_gold_symbol = (StringFind(symbol, "XAU") != -1 || StringFind(symbol, "GOLD") != -1);
         if(is_gold_symbol)
         {
            if(!ValidateGoldTradingConditions(symbol))
            {
               RecordRejectReason("PIPE:GoldConditions");
               if(!dry_run_on_block)
               {
                  Log(LOG_INFO, "ProcessSignals", symbol + " - GOLD trading conditions not met");
                  continue;
               }
               Log(LOG_INFO, "ProcessSignals",
                   symbol + " - GOLD trading conditions not met; DRY-RUN diagnostics bypass active");
            }
         }
         else if(!IsSpreadAcceptable(symbol))
         {
            RecordRejectReason("PIPE:SpreadTooHigh");
            if(!dry_run_on_block)
            {
               Log(LOG_WARNING, "ProcessSignals", "Spread too high for " + symbol);
               continue;
            }
            Log(LOG_INFO, "ProcessSignals",
                symbol + " - Spread gate blocked live execution; DRY-RUN diagnostics bypass active");
         }

         // Bar-time cooldown: prevent multiple signals on the same bar (or within N bars)
         if(!g_Force_Signal_Cadence_Gate_Off &&
            g_Signal_Cooldown_Bars > 0 &&
            g_symbols[i].last_signal_bar > 0)
         {
            double tf_seconds = (double)PeriodSeconds(Signal_TF);
            if(tf_seconds <= 0) tf_seconds = 60.0;
            int bars_since_signal = (int)MathFloor((current_bar - g_symbols[i].last_signal_bar) / tf_seconds);
            if(bars_since_signal < g_Signal_Cooldown_Bars)
            {
               // Keep elapsed reference fresh while waiting for cooldown bars.
               g_symbols[i].last_processed_time = current_time;

               int cooldown_log_gap = MathMax(30, Signal_Check_Seconds * 4);
               if(last_bar_cooldown_bar[i] != current_bar ||
                  last_bar_cooldown_log[i] == 0 ||
                  (current_time - last_bar_cooldown_log[i]) >= cooldown_log_gap)
               {
                  Log(LOG_DEBUG, "ProcessSignals", "Cooldown (bar-based) active for " + symbol +
                      " - bars since signal: " + IntegerToString(bars_since_signal) + "/" +
                      IntegerToString(g_Signal_Cooldown_Bars));
                  last_bar_cooldown_log[i] = current_time;
                  last_bar_cooldown_bar[i] = current_bar;
               }
               continue;
            }
         }
         
         g_symbols[i].last_processed_time = current_time;
         
         if(!IsValidSymbol(symbol))
         {
            RecordRejectReason("PIPE:InvalidSymbol");
            Log(LOG_WARNING, "ProcessSignals", "Invalid symbol: " + symbol);
            continue;
         }

         int trend_direction = GetHTFBiasInstitutional(symbol);
         int signal_structure_now = DetectMarketStructure(symbol, Signal_TF);

         Log(LOG_DEBUG, "ProcessSignals", "Generating signal for " + symbol);
         bool ai_available = (g_Enable_AI_Trend_Predictor_Runtime && g_ai_enabled);
         int auto_mode = AUTO_REGIME_MODE_DISABLED;
         string auto_reason = "";
         int auto_htf_score = 0;
         double auto_volatility = 1.0;
         bool auto_first_retracement = false;
         bool auto_discount_zone = false;
         SRoutingMatrix route = BuildEffectiveRoutingMatrix(symbol, i, ai_available,
                                                            auto_mode, auto_reason,
                                                            auto_htf_score, auto_volatility,
                                                            auto_first_retracement, auto_discount_zone);
         if(i >= 0 && i < MAX_SYMBOLS)
         {
            hb_effective_seeded[i] = true;
            hb_effective_ict[i] = route.ict_allowed;
            hb_effective_ai[i] = route.ai_allowed;
            hb_effective_kim[i] = route.kim_allowed;
            hb_effective_both[i] = route.require_both;
            hb_effective_mode[i] = route.suitability_mode;
            hb_effective_director[i] = route.director_active;
            hb_effective_director_strategy[i] = route.director_strategy_mode;
            hb_effective_time[i] = current_time;
         }
         bool ict_allowed = route.ict_allowed;
         bool ai_allowed = route.ai_allowed;
         bool require_both = route.require_both;
         bool kimaniz_enabled = route.kim_allowed;
         // Keep live probing consistent with the routed strategy permissions for this symbol/bar.
         bool probe_ict = (g_Enable_ICT_Strategy && route.ict_allowed);
         bool probe_ai = (g_Enable_AI_Strategy && ai_available && route.ai_allowed);
         bool probe_kim = (g_Enable_KImaniz_Strategy && route.kim_allowed);
         bool auto_range_mode = ((g_Enable_Auto_Regime_Router || route.suitability_enforced) &&
                                 route.suitability_mode == AUTO_REGIME_MODE_INTRA_HIGHLOW);
         bool allow_range_mode = (g_Allow_Range_Trading || auto_range_mode);

         if(trend_direction == 0 && !allow_range_mode && !g_Allow_Neutral_Trend_Trading)
         {
            RecordRejectReason("PIPE:HTFNeutral");
            Log(LOG_INFO, "ProcessSignals", symbol + " - Calculated trend neutral - skipping signal generation");
            continue;
         }

         if(signal_structure_now == MARKET_RANGE && !allow_range_mode)
         {
            RecordRejectReason("PIPE:RangingMarket");
            if(last_range_skip_log[i] == 0 || (current_time - last_range_skip_log[i]) >= 30)
            {
               Log(LOG_INFO, "ProcessSignals", symbol + " - Signal_TF range - skipping signal generation");
               last_range_skip_log[i] = current_time;
            }
            continue;
         }

         if(g_Enable_Auto_Regime_Router)
         {
            bool regime_changed = (!auto_regime_seeded[i] || last_auto_regime_mode[i] != auto_mode);
            if(regime_changed)
            {
               Log(LOG_INFO, "AutoRegimeRouter",
                   symbol + " - Switched to " + AutoRegimeModeToString(auto_mode) +
                   " | " + auto_reason +
                   " | HTF=" + IntegerToString(auto_htf_score) +
                   " | Vol=" + DoubleToString(auto_volatility, 2));
            }
            auto_regime_seeded[i] = true;
            last_auto_regime_mode[i] = auto_mode;
         }
         else if(route.suitability_enforced && g_Enable_Institutional_Debug)
         {
            bool role_changed = (!auto_regime_seeded[i] || last_auto_regime_mode[i] != route.suitability_mode);
            if(role_changed)
            {
               Log(LOG_DEBUG, "StrategySuitability",
                   symbol + " - Role " + AutoRegimeModeToString(route.suitability_mode) +
                   " | HuntMode=" + SuitabilityHuntModeToString(g_Suitability_Hunt_Mode) +
                   " | " + auto_reason +
                   " | HTF=" + IntegerToString(auto_htf_score) +
                   " | Vol=" + DoubleToString(auto_volatility, 2));
            }
            auto_regime_seeded[i] = true;
            last_auto_regime_mode[i] = route.suitability_mode;
         }

         if(route.fail_reason != "" && !ict_allowed && !ai_allowed && !kimaniz_enabled)
         {
            RecordRejectReason("ROUTE:" + route.fail_reason);
            Log(LOG_WARNING, "ProcessSignals", symbol + " - Routing blocked: " + route.fail_reason);
            continue;
         }

         if(require_both && (!ict_allowed || !ai_allowed))
         {
            RecordRejectReason("ROUTE:RequiredStrategyMissing");
            Log(LOG_WARNING, "ProcessSignals", symbol + " - BOTH mode but a required strategy unavailable (ICT=" +
                (ict_allowed ? "ON" : "OFF") + ", AI=" + (ai_allowed ? "ON" : "OFF") + ")");
            continue;
         }

         STradingSignal ict_signal;
         STradingSignal ai_signal;
         STradingSignal kimaniz_signal;
         bool ict_valid = false;
         bool ai_valid = false;
         bool kimaniz_valid = false;
         double ai_fallback_min_prob = 0.0;

         if(probe_ict)
         {
            g_Signal_Stats_ICT_Total_Attempts++;  // Track live ICT attempt
            ict_signal = GenerateICTSignal(symbol, allow_range_mode, true, trend_direction);
            if(ict_signal.valid && ai_available &&
               !require_both && ai_allowed &&
               g_AI_Signal_Generation_Mode != AI_SIGNAL_MODE_PRIMARY)
               ApplyAIValidationToSignal(symbol, ict_signal);
            ict_valid = ict_signal.valid;
            if(ict_valid)
               ict_valid = HardenStrategySignal(symbol, i, allow_range_mode, trend_direction, ict_signal, "ICT");
            if(ict_valid)
               g_Signal_Stats_ICT_Valid++;  // Track live executable ICT signal
            if(!ict_valid && StringLen(ict_signal.reason) > 0)
            {
               RecordRejectReason("ICT:" + ict_signal.reason);
               Log(LOG_DEBUG, "ProcessSignals", symbol + " - ICT signal invalid: " + ict_signal.reason);
            }
         }

         if(probe_ai)
         {
            g_Signal_Stats_AI_Total_Attempts++;  // Track live AI attempt
            ai_signal = GenerateAIPrimarySignal(symbol, allow_range_mode, true, trend_direction);
            ai_valid = ai_signal.valid;
            if(ai_valid)
               ai_valid = HardenStrategySignal(symbol, i, allow_range_mode, trend_direction, ai_signal, "AI");
            if(ai_valid)
               g_Signal_Stats_AI_Valid++;  // Track live executable AI signal
            if(!ai_valid && StringLen(ai_signal.reason) > 0)
            {
               RecordRejectReason("AI:" + ai_signal.reason);
               Log(LOG_DEBUG, "ProcessSignals", symbol + " - AI signal invalid: " + ai_signal.reason);
            }
            if(ai_valid)
            {
               ai_fallback_min_prob = GetAIDirectionalMinProbability(ai_signal.direction, symbol, i);
               // Keep fallback strict, but do not add extra penalty on top of AI's own directional gate.
               ai_fallback_min_prob = MathClamp(ai_fallback_min_prob, 0.50, 0.90);
            }
         }

         if(probe_kim)
         {
            g_Signal_Stats_KIM_Total_Attempts++;  // Track live Kimaniz attempt
            kimaniz_signal = GenerateKImanizSignal(symbol, allow_range_mode, true, trend_direction);
            kimaniz_valid = kimaniz_signal.valid;
            if(kimaniz_valid)
               kimaniz_valid = HardenStrategySignal(symbol, i, allow_range_mode, trend_direction, kimaniz_signal, "KIM");
            if(kimaniz_valid)
               g_Signal_Stats_KIM_Valid++;  // Track live executable Kimaniz signal
            if(!kimaniz_valid && StringLen(kimaniz_signal.reason) > 0)
            {
               RecordRejectReason("KIM:" + kimaniz_signal.reason);
               Log(LOG_DEBUG, "ProcessSignals", symbol + " - KImaniz signal invalid: " + kimaniz_signal.reason);
            }
         }

          STradingSignal signal;
          STradingSignal reversal_signal;  // Keep live path aligned with GenerateTradingSignal().
          string selection_stage = "";
          ResolveSelectedSignalFromCandidates(symbol, i, trend_direction, route,
                                              ict_signal, ict_valid,
                                              ai_signal, ai_valid,
                                              kimaniz_signal, kimaniz_valid,
                                              ai_fallback_min_prob,
                                              signal, selection_stage);

          if(signal.valid && signal.direction != 0)
          {
             SStrategySynergyScore synergy = g_pipeline_synergy.CalculatePipelineSynergies(
                symbol, signal.direction,
                ict_signal, ai_signal, kimaniz_signal, reversal_signal,
                i
             );

             g_pipeline_synergy.ApplySynergyToSignal(signal, synergy);

             if(g_Enable_Institutional_Debug)
             {
                Log(LOG_DEBUG, "ProcessSignals", symbol + " Synergies: " + synergy.synergy_breakdown);
             }
          }

          if(signal.valid)
          {
             if(!FinalizeSelectedSignal(symbol, i, allow_range_mode, trend_direction,
                                        route,
                                        (StringLen(selection_stage) > 0 ? selection_stage : "FINAL"),
                                        signal))
             {
                if(StringLen(signal.reason) > 0)
                   RecordRejectReason("FINAL:" + signal.reason);
                Log(LOG_INFO, "ProcessSignals", symbol + " - " + signal.reason);
                AuditLogSignal("FINAL_REJECT", symbol, signal, signal.reason);
             }
          }

          LogStrategyCandidateSnapshot("ProcessSignals",
                                       symbol,
                                       route,
                                       probe_ict,
                                       probe_ai,
                                       probe_kim,
                                       ict_signal,
                                       ict_valid,
                                       ai_signal,
                                       ai_valid,
                                       kimaniz_signal,
                                       kimaniz_valid,
                                       signal,
                                       selection_stage);
          
          if(signal.valid)
          {
            AuditLogSignal("SIGNAL_READY", symbol, signal, "Final gates passed");

            string signal_msg = StringFormat("%s - %s | Origin: %s | Entry: %.2f | SL: %.2f | TP: %.2f | RR: %.2f",
               symbol,
               (signal.direction == 1 ? "BUY" : "SELL"),
               SignalOriginToString(signal.origin),
               signal.entry_price,
               signal.stop_loss,
               signal.take_profit,
               signal.risk_reward_ratio);

            if(signal.reversal_detected)
               signal_msg += StringFormat(" | Reversal: %.1f%%", signal.reversal_confidence * 100);
            string strategy_output = BuildStrategyOutputSummary(signal, true);
            if(StringLen(strategy_output) > 0)
               signal_msg += " | " + strategy_output;

            // Per-symbol/bar dedupe to avoid flooding alerts/queue with repeated levels.
            static string dedupe_symbol[MAX_SYMBOLS];
            static int    dedupe_direction[MAX_SYMBOLS];
            static double dedupe_entry[MAX_SYMBOLS];
            static double dedupe_sl[MAX_SYMBOLS];
            static double dedupe_tp[MAX_SYMBOLS];
            static datetime dedupe_bar[MAX_SYMBOLS];
            static datetime dedupe_timestamp[MAX_SYMBOLS];  // Track when dedupe entry was set
            static bool dedupe_initialized = false;

            // Initialize dedupe timestamps on first call
            if(!dedupe_initialized)
            {
               for(int di = 0; di < MAX_SYMBOLS; di++)
                  dedupe_timestamp[di] = 0;
               dedupe_initialized = true;
            }

            // Clear signal dedupe cache every 5 minutes (300 seconds) to allow re-signaling on same levels
            for(int di = 0; di < MAX_SYMBOLS; di++)
            {
               if(dedupe_timestamp[di] > 0 && (current_time - dedupe_timestamp[di]) >= 300)
               {
                  dedupe_symbol[di] = "";
                  dedupe_direction[di] = 0;
                  dedupe_entry[di] = 0.0;
                  dedupe_sl[di] = 0.0;
                  dedupe_tp[di] = 0.0;
                  dedupe_bar[di] = 0;
                  dedupe_timestamp[di] = 0;
               }
            }

            double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
            if(point <= 0.0) point = Point();
            double level_tol = point * 2.0;
            datetime current_bar_time = iTime(symbol, Signal_TF, 0);
            bool duplicate_now = false;
            string duplicate_reason = "";
            if(i >= 0 && i < MAX_SYMBOLS && dedupe_symbol[i] == symbol && dedupe_bar[i] == current_bar_time)
            {
               bool same_direction = (dedupe_direction[i] == signal.direction);
               bool same_levels = (MathAbs(dedupe_entry[i] - signal.entry_price) <= level_tol &&
                                   MathAbs(dedupe_sl[i]    - signal.stop_loss)   <= level_tol &&
                                   MathAbs(dedupe_tp[i]    - signal.take_profit) <= level_tol);
               // KImaniz anti-flood: allow at most one alert/queue per symbol per bar.
               bool kim_same_bar = (signal.origin == SIGNAL_ORIGIN_KIMANIZ);
               if(kim_same_bar)
               {
                  duplicate_now = true;
                  duplicate_reason = "KImaniz same-bar guard";
               }
               else if(same_direction && same_levels)
               {
                  duplicate_now = true;
                  duplicate_reason = "same direction and levels already emitted this bar";
               }
               else if(same_levels)
               {
                  duplicate_now = true;
                  duplicate_reason = "same levels already emitted this bar";
               }
            }

            if(duplicate_now)
            {
               RecordRejectReason("PIPE:DuplicateSignal");
               Log(LOG_DEBUG, "ProcessSignals", symbol + " - Duplicate signal (same bar), skipping alert/queue" +
                   (StringLen(duplicate_reason) > 0 ? " [" + duplicate_reason + "]" : ""));
               AuditLogSignal("PIPE_DUPLICATE", symbol, signal, duplicate_reason);
               continue;
            }

            if(i >= 0 && i < MAX_SYMBOLS)
            {
               dedupe_symbol[i] = symbol;
               dedupe_direction[i] = signal.direction;
               dedupe_entry[i] = signal.entry_price;
               dedupe_sl[i] = signal.stop_loss;
               dedupe_tp[i] = signal.take_profit;
               dedupe_bar[i] = current_bar_time;
               dedupe_timestamp[i] = current_time;  // Track when this dedupe entry was set
            }

            // Signal is fully validated and deduplicated.
            // Pre-logging before execution (diagnostics only - counters updated post-confirmation)
            LogTradeMessage(LOG_INFO, "ProcessSignals", symbol, "Valid signal", signal_msg);

            int inst_htf_bias = trend_direction;
            int inst_sig_struct = DetectMarketStructure(symbol, Signal_TF);
            double inst_price = (g_symbols[i].cache.bid > 0 && g_symbols[i].cache.ask > 0) ?
                                (g_symbols[i].cache.bid + g_symbols[i].cache.ask) / 2.0 : signal.entry_price;
            LogInstitutionalSignal("SIGNAL_READY", symbol, signal, inst_htf_bias, inst_sig_struct,
                                   inst_price, g_symbols[i].cache.spread, signal.atr_value, "");

            g_debug_signal_count++;
            g_last_valid_signal_time = TimeCurrent();

            Log(LOG_INFO, "ProcessSignals", "Valid signal generated for " + symbol + ": " + signal.reason);
            if(dry_run_on_block)
            {
               Log(LOG_INFO, "ProcessSignals",
                   symbol + " - DRY-RUN mode active: signal diagnostics recorded, trade execution skipped");
               // Even in dry-run, count the valid signal (but not queued)
               g_debug_counters.signals_valid++;
               if(signal.direction == 1) g_buy_signals_count++;
               else if(signal.direction == -1) g_sell_signals_count++;
               continue;
            }
            
            // CRITICAL: Attempt to queue signal - only confirm counters on successful queue
            bool queued = ExecuteTrade(symbol, signal, i);
            
            if(queued)
            {
               // CONFIRMED SIGNAL DEPOSIT: Queue was successful
               // Only NOW increment validated signal counter (post-confirmation)
               g_debug_counters.signals_valid++;
               
               // Track signal direction for bias monitoring (only for actually queued signals)
               if(signal.direction == 1) g_buy_signals_count++;
               else if(signal.direction == -1) g_sell_signals_count++;
               
                // Start cooldown only after a trade is actually queued
                g_symbols[i].last_signal_time = TimeCurrent();
                g_symbols[i].last_signal_bar = current_bar;

                SendAlert(ALERT_SIGNAL, signal_msg);
                
                Log(LOG_INFO, "SignalDepositConfirmed", symbol + " - Signal admitted to execution pipeline (" +
                    SignalOriginToString(signal.origin) + ") | Queue depth=" + IntegerToString(g_retry_count));
            }
            else
            {
               // Signal was valid but failed to queue - log and skip cooldown
               string execution_reject_reason = g_last_reject_reason_key;
               if(StringLen(execution_reject_reason) <= 0)
                  execution_reject_reason = "unknown";
               if(i >= 0 && i < MAX_SYMBOLS)
               {
                  // Queue failure should not poison same-bar retries for the same setup.
                  // Cooldown is intentionally skipped here, so clear the emit dedupe entry too.
                  dedupe_symbol[i] = "";
                  dedupe_direction[i] = 0;
                  dedupe_entry[i] = 0.0;
                  dedupe_sl[i] = 0.0;
                  dedupe_tp[i] = 0.0;
                  dedupe_bar[i] = 0;
                  dedupe_timestamp[i] = 0;
               }
               RecordRejectReason("SIGNAL:ValidButUnqueued");
               Log(LOG_WARNING, "SignalDepositFailed", symbol + " - Valid signal failed to queue (" + 
                   SignalOriginToString(signal.origin) + ") | Last execution reject: " + execution_reject_reason);
               AuditLogSignal("VALID_BUT_UNQUEUED", symbol, signal,
                              "ExecuteTrade() returned false | LastReject=" + execution_reject_reason);
            }
         }
         else
         {
            if(StringLen(signal.reason) > 0)
               RecordRejectReason("FINAL:" + signal.reason);
            Log(LOG_DEBUG, "ProcessSignals", "No valid signal for " + symbol + " - Reason: " + signal.reason);
         }
      }
      
      // Monitor direction bias
      MonitorDirectionBias();
   }

   // release handled by auto_release_lock
   completion_calls++;
   if(g_debug_signals_enabled && (last_completion_heartbeat == 0 || (current_time - last_completion_heartbeat) >= 60))
   {
      Log(LOG_DEBUG, "ProcessSignals",
          "Signal loop heartbeat - calls=" + IntegerToString(completion_calls) +
          ", symbols=" + IntegerToString(g_symbols_count) +
          ", retries=" + IntegerToString(g_retry_count));
      completion_calls = 0;
      last_completion_heartbeat = current_time;
   }
}

//====================================================================
// BIAS MONITORING - Track signal distribution including reversals
//====================================================================
void MonitorDirectionBias()
{
   static datetime last_report = 0;
   
   datetime now = TimeCurrent();
   if(now - last_report >= 3600) // Report every hour
   {
      last_report = now;
      
      int total_signals = g_buy_signals_count + g_sell_signals_count;
      double buy_percentage = (total_signals > 0) ?
                             (double)g_buy_signals_count / total_signals * 100 : 0;
      double sell_percentage = (total_signals > 0) ?
                              (double)g_sell_signals_count / total_signals * 100 : 0;
      
      Log(LOG_INFO, "MonitorDirectionBias",
          StringFormat("Signal Distribution - BUY: %d (%.1f%%), SELL: %d (%.1f%%)",
                      g_buy_signals_count, buy_percentage,
                      g_sell_signals_count, sell_percentage));
      
      // Reversal statistics
      if(Enable_Reversal_Detection)
      {
         double reversal_rate = (total_signals > 0) ? 
                               (double)g_reversal_signals_count / total_signals * 100 : 0;
         double confirmation_rate = (g_reversal_signals_count > 0) ? 
                                   (double)g_reversal_confirmed_count / g_reversal_signals_count * 100 : 0;
         
         Log(LOG_INFO, "MonitorDirectionBias", 
             StringFormat("Reversal Stats - Detected: %d (%.1f%%), Confirmed: %d (%.1f%%), Overrides: %d",
                         g_reversal_signals_count, reversal_rate,
                         g_reversal_confirmed_count, confirmation_rate,
                         g_reversal_override_count));
      }
      
      // Reset counters
      g_buy_signals_count = 0;
      g_sell_signals_count = 0;
      g_reversal_signals_count = 0;
      g_reversal_confirmed_count = 0;
      g_reversal_override_count = 0;
   }
}

#endif // SIGNAL_GENERATION_MQH
