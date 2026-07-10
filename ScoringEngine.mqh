#ifndef SCORING_ENGINE_MQH
#define SCORING_ENGINE_MQH

#property copyright "Copyright 2024, ProfitTrailBot Ltd."
#property strict

int GetPooledIndicatorHandle(string symbol, ENUM_TIMEFRAMES tf, int period, string type);
int GetSymbolIndex(string symbol);
int GetHTFBias(string symbol);
int GetHTFBiasScore(string symbol);
int DetectMarketStructure(string symbol, ENUM_TIMEFRAMES tf);
bool IsMarketTrending(string symbol, ENUM_TIMEFRAMES tf);
bool GetMomentumValues(string symbol, ENUM_TIMEFRAMES tf, int symbol_index, double &macd_value, double &stoch_value);
double GetATRValue(string symbol, ENUM_TIMEFRAMES tf, int atr_period = 0);
double GetRSIValue(string symbol, ENUM_TIMEFRAMES tf, int period);
double GetCachedVolatilityFactor(string symbol, int symbol_index);
double GetAverageSpreadPips(string symbol);

int PTBGetCoreTimeframeIndex(ENUM_TIMEFRAMES tf)
{
   if(tf == Signal_TF)
      return 0;
   if(tf == Primary_TF)
      return 1;
   if(tf == Confirm_TF)
      return 2;
   if(tf == Trend_TF)
      return 3;
   return -1;
}

int PTBGetCacheTTLSeconds(ENUM_TIMEFRAMES tf)
{
   int tf_seconds = PeriodSeconds(tf);
   if(tf_seconds <= 0)
      tf_seconds = 60;

   int ttl = tf_seconds + 10;
   if(ttl < 60)
      ttl = 60;
   return ttl;
}

double PTBAverageClose(const MqlRates &rates[], int period)
{
   int available = ArraySize(rates);
   int count = MathMin(period, available);
   if(count <= 0)
      return 0.0;

   double total = 0.0;
   for(int i = 0; i < count; i++)
      total += rates[i].close;
   return total / count;
}

double PTBAverageRange(const MqlRates &rates[], int start, int count)
{
   int available = ArraySize(rates);
   if(available <= 0 || start < 0 || count <= 0 || start >= available)
      return 0.0;

   int end = MathMin(available, start + count);
   double total = 0.0;
   int used = 0;
   for(int i = start; i < end; i++)
   {
      double candle_range = rates[i].high - rates[i].low;
      if(candle_range > 0.0 && MathIsValidNumber(candle_range))
      {
         total += candle_range;
         used++;
      }
   }

   if(used <= 0)
      return 0.0;
   return total / used;
}

bool PTBReadIndicatorValue(string symbol, ENUM_TIMEFRAMES tf, int period, string type,
                           int buffer_index, int shift, double &value)
{
   value = 0.0;
   if(period <= 0 || shift < 0)
      return false;

   int handle = GetPooledIndicatorHandle(symbol, tf, period, type);
   if(handle == INVALID_HANDLE)
      return false;

   double buffer[];
   ArraySetAsSeries(buffer, true);
   if(CopyBuffer(handle, buffer_index, shift, 1, buffer) < 1 || ArraySize(buffer) < 1)
      return false;
   if(!MathIsValidNumber(buffer[0]))
      return false;

   value = buffer[0];
   return true;
}

int PTBResolveStructureCacheSlot(int symbol_index, ENUM_TIMEFRAMES tf)
{
   if(symbol_index < 0 || symbol_index >= MAX_SYMBOLS)
      return -1;

   int core_index = PTBGetCoreTimeframeIndex(tf);
   if(core_index >= 0)
   {
      int mapped_slot = g_structure_slot_map[symbol_index][core_index];
      if(mapped_slot >= 0 && mapped_slot < MAX_TF_CACHE && g_structure_cache[symbol_index][mapped_slot].tf == tf)
         return mapped_slot;

      int preferred_slot = core_index;
      g_structure_slot_map[symbol_index][core_index] = preferred_slot;
      g_structure_cache[symbol_index][preferred_slot].tf = tf;
      return preferred_slot;
   }

   for(int slot = 4; slot < MAX_TF_CACHE; slot++)
   {
      if(g_structure_cache[symbol_index][slot].tf == tf)
         return slot;
   }

   for(int slot = 4; slot < MAX_TF_CACHE; slot++)
   {
      if(g_structure_cache[symbol_index][slot].tf == (ENUM_TIMEFRAMES)-1)
      {
         g_structure_cache[symbol_index][slot].tf = tf;
         return slot;
      }
   }

   int oldest_slot = 4;
   datetime oldest_time = LONG_MAX;
   for(int slot = 4; slot < MAX_TF_CACHE; slot++)
   {
      datetime calc_time = g_structure_calc_time[symbol_index][slot];
      if(calc_time <= 0)
         return slot;
      if(calc_time < oldest_time)
      {
         oldest_time = calc_time;
         oldest_slot = slot;
      }
   }

   g_structure_cache[symbol_index][oldest_slot].tf = tf;
   return oldest_slot;
}

int PTBResolveBiasCacheSlot(int symbol_index)
{
   if(symbol_index < 0 || symbol_index >= MAX_SYMBOLS)
      return -1;

   int trend_core_index = PTBGetCoreTimeframeIndex(Trend_TF);
   if(trend_core_index >= 0)
   {
      int mapped_slot = g_bias_slot_map[symbol_index][trend_core_index];
      if(mapped_slot >= 0 && mapped_slot < MAX_TF_CACHE)
         return mapped_slot;

      int slot = PTBResolveStructureCacheSlot(symbol_index, Trend_TF);
      if(slot >= 0)
         g_bias_slot_map[symbol_index][trend_core_index] = slot;
      return slot;
   }

   return PTBResolveStructureCacheSlot(symbol_index, Trend_TF);
}

datetime PTBGetHTFBiasAnchorBar(string symbol)
{
   datetime anchor = 0;
   datetime tf_bar = iTime(symbol, Primary_TF, 0);
   if(tf_bar > anchor)
      anchor = tf_bar;

   tf_bar = iTime(symbol, Confirm_TF, 0);
   if(tf_bar > anchor)
      anchor = tf_bar;

   tf_bar = iTime(symbol, Trend_TF, 0);
   if(tf_bar > anchor)
      anchor = tf_bar;

   return anchor;
}

int DetectMarketStructure(string symbol, ENUM_TIMEFRAMES tf)
{
   if(StringLen(symbol) <= 0)
      return MARKET_RANGE;

   int symbol_index = GetSymbolIndex(symbol);
   if(symbol_index < 0 || symbol_index >= MAX_SYMBOLS)
      return MARKET_RANGE;

   int cache_slot = PTBResolveStructureCacheSlot(symbol_index, tf);
   datetime current_bar = iTime(symbol, tf, 0);
   datetime now = TimeCurrent();
   int cache_ttl = PTBGetCacheTTLSeconds(tf);
   if(cache_slot >= 0 &&
      g_structure_cache[symbol_index][cache_slot].tf == tf &&
      g_structure_cache[symbol_index][cache_slot].last_update == current_bar &&
      g_structure_calc_time[symbol_index][cache_slot] > 0 &&
      now >= g_structure_calc_time[symbol_index][cache_slot] &&
      (now - g_structure_calc_time[symbol_index][cache_slot]) <= cache_ttl)
   {
      return (int)g_structure_cache[symbol_index][cache_slot].value;
   }

   int bars_to_analyze = MathMax(50, MathMin(160, (g_Trend_Lookback_Bars > 0 ? g_Trend_Lookback_Bars : 64)));
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, tf, 0, bars_to_analyze, rates);
   int result = MARKET_RANGE;

   if(copied >= 20)
   {
      double sma10 = PTBAverageClose(rates, 10);
      double sma20 = PTBAverageClose(rates, 20);
      double sma50 = PTBAverageClose(rates, 50);
      double current_price = rates[0].close;

      if(current_price > 0.0 && sma10 > 0.0 && sma20 > 0.0 && sma50 > 0.0)
      {
         double bullish_score = 0.0;
         double bearish_score = 0.0;

         if(current_price > sma10)
            bullish_score += 1.0;
         else if(current_price < sma10)
            bearish_score += 1.0;

         if(current_price > sma20)
            bullish_score += 0.5;
         else if(current_price < sma20)
            bearish_score += 0.5;

         if(sma10 > sma20)
            bullish_score += 1.0;
         else if(sma10 < sma20)
            bearish_score += 1.0;

         if(sma20 > sma50)
            bullish_score += 1.5;
         else if(sma20 < sma50)
            bearish_score += 1.5;

         double atr = GetATRValue(symbol, tf);
         if(atr <= 0.0)
            atr = PTBAverageRange(rates, 0, MathMin(14, copied));
         if(atr <= 0.0)
            atr = current_price * 0.001;

         if(copied > 5)
         {
            double momentum_move = current_price - rates[5].close;
            double momentum_threshold = atr * 0.35;
            if(momentum_move > momentum_threshold)
               bullish_score += 1.5;
            else if(momentum_move < -momentum_threshold)
               bearish_score += 1.5;
         }

         if(copied > 4)
         {
            int rising_closes = 0;
            int falling_closes = 0;
            for(int i = 0; i < 4; i++)
            {
               if(rates[i].close > rates[i + 1].close)
                  rising_closes++;
               else if(rates[i].close < rates[i + 1].close)
                  falling_closes++;
            }
            bullish_score += 0.25 * rising_closes;
            bearish_score += 0.25 * falling_closes;
         }

         if(copied > 6)
         {
            bool higher_highs = (rates[1].high > rates[5].high && rates[1].low > rates[5].low);
            bool lower_lows = (rates[1].high < rates[5].high && rates[1].low < rates[5].low);
            if(higher_highs)
               bullish_score += 1.0;
            else if(lower_lows)
               bearish_score += 1.0;
         }

         double ma_separation = 0.0;
         if(atr > 0.0)
            ma_separation = MathAbs(sma20 - sma50) / atr;
         if(ma_separation < 0.15)
         {
            bullish_score *= 0.85;
            bearish_score *= 0.85;
         }
         else if(ma_separation > 0.50)
         {
            if(bullish_score > bearish_score)
               bullish_score += 0.5;
            else if(bearish_score > bullish_score)
               bearish_score += 0.5;
         }

         double adx_value = 0.0;
         bool adx_valid = (g_Use_ADX_For_Trend && PTBReadIndicatorValue(symbol, tf, 14, "ADX", 0, 1, adx_value));
         double weak_trend_level = MathMax(10.0, g_Weak_Trend_ADX_Level);
         double strong_trend_level = MathMax(weak_trend_level + 2.0, g_Strong_Trend_ADX_Level);
         if(adx_valid)
         {
            if(adx_value >= strong_trend_level)
            {
               if(bullish_score > bearish_score)
                  bullish_score += 1.0;
               else if(bearish_score > bullish_score)
                  bearish_score += 1.0;
            }
            else if(adx_value < weak_trend_level)
            {
               bullish_score *= 0.75;
               bearish_score *= 0.75;
            }
         }

         double lead = bullish_score - bearish_score;
         double min_direction_score = (adx_valid && adx_value >= weak_trend_level ? 2.5 : 3.0);

         if(bullish_score >= min_direction_score && lead >= 1.0)
            result = MARKET_BULLISH;
         else if(bearish_score >= min_direction_score && lead <= -1.0)
            result = MARKET_BEARISH;
         else if(MathAbs(lead) >= 1.5)
            result = (lead > 0.0 ? MARKET_BULLISH : MARKET_BEARISH);
      }
   }

   if(cache_slot >= 0)
   {
      g_structure_cache[symbol_index][cache_slot].tf = tf;
      g_structure_cache[symbol_index][cache_slot].value = (ENUM_MARKET_STRUCTURE)result;
      g_structure_cache[symbol_index][cache_slot].last_update = current_bar;
      g_structure_calc_time[symbol_index][cache_slot] = now;
   }

   return result;
}

int GetHTFBiasScore(string symbol)
{
   // DEPRECATED: Use GetHTFBiasStrengthInstitutional() instead
   // Convert 0-100 institutional strength to -7 to +7 scale
   int institutional_strength = (int)GetHTFBiasStrengthInstitutional(symbol);
   int institutional_direction = GetHTFBiasInstitutional(symbol);
   
   // Convert: 100 strength -> 7 score (if direction is positive), 0 strength -> 0 score
   int score = (int)((institutional_strength / 100.0) * 7.0);
   if(institutional_direction < 0)
      score = -score;
   
   return score;
}

// DEPRECATED: Use GetHTFBiasInstitutional() instead
// This function is wrapped for backward compatibility
int GetHTFBias(string symbol)
{
   // Delegate to institutional version
   return GetHTFBiasInstitutional(symbol);
   
   /* LEGACY IMPLEMENTATION (replaced with institutional system)
   if(StringLen(symbol) <= 0)
      return 0;

   int primary_direction = StructureToDirection(DetectMarketStructure(symbol, Primary_TF));
   int confirm_direction = StructureToDirection(DetectMarketStructure(symbol, Confirm_TF));
   int trend_direction = StructureToDirection(DetectMarketStructure(symbol, Trend_TF));

   if(confirm_direction != 0 && trend_direction != 0)
   {
      if(confirm_direction == trend_direction)
         return confirm_direction;
      return 0;
   }

   if(trend_direction != 0 && (primary_direction == 0 || primary_direction == trend_direction))
      return trend_direction;

   if(confirm_direction != 0 && (primary_direction == 0 || primary_direction == confirm_direction))
      return confirm_direction;

   int score = GetHTFBiasScore(symbol);
   if(score >= 3)
      return 1;
   if(score <= -3)
      return -1;
   return 0;
   */
}

bool IsMarketTrending(string symbol, ENUM_TIMEFRAMES tf)
{
   // DEPRECATED: Use IsTrendInstitutionallyValid() instead
   // Get institutional trend analysis
   STrendAnalysis trend = CTrendAnalysisEnhanced::AnalyzeTrendInstitutional(symbol, tf);
   
   // Market is trending if phase is not reversal and strength is acceptable
   return (trend.phase != TREND_PHASE_REVERSAL && trend.strength >= 45.0);
}

#define STRUCT_BULLISH 0
#define STRUCT_BEARISH 1
#define STRUCT_RANGE   2

struct SFilterDiagnostic
{
   double trade_score;
   double required_score;
   double available_score_max;
   string reason;
   string score_breakdown;

   double trend_score;
   double momentum_score;
   double volatility_score;
   double structure_score;
   double alignment_score;
   double confirmation_score;
   double risk_reward_score;
   double entry_quality_score;
   double spread_score;
   double regime_score;

   double confidence_value;
   string confidence_label;
   string decision;
   double adaptive_threshold;
   double penalty_points;
};

struct SScoringModelConfig
{
   double execution_threshold;
   bool diagnostics_enabled;
   bool adaptive_enabled;

   double weight_trend;
   double weight_momentum;
   double weight_volatility;
   double weight_structure;
   double weight_alignment;
   double weight_confirmation;
   double weight_risk_reward;
   double weight_entry_quality;
   double weight_spread;
   double weight_regime;

   double adaptive_threshold_boost_max;
   double adaptive_risk_weight_boost;
   double adaptive_opportunity_weight_cut;
};

class ScoringEngine
{
private:
   double score_threshold;
   bool diagnostics_enabled;
   bool adaptive_enabled;

   double weight_trend, weight_momentum, weight_volatility, weight_structure, weight_alignment;
   double weight_confirmation, weight_risk_reward, weight_entry_quality, weight_spread, weight_regime;

   double adaptive_threshold_boost_max;
   double adaptive_risk_weight_boost;
   double adaptive_opportunity_weight_cut;

   double Clamp(double v, double lo, double hi)
   {
      if(!MathIsValidNumber(v)) return lo;
      if(v < lo) return lo;
      if(v > hi) return hi;
      return v;
   }
   double Clamp01(double v){ return Clamp(v, 0.0, 1.0); }
   double Clamp100(double v){ return Clamp(v, 0.0, 100.0); }
   double SafeRatio(double n, double d, double fallback)
   {
      if(!MathIsValidNumber(n) || !MathIsValidNumber(d) || d == 0.0 || MathAbs(d) < 1e-10) return fallback;
      double r = n / d;
      if(!MathIsValidNumber(r)) return fallback;
      return r;
   }
   int SignOf(double v){ if(v > 0.0) return 1; if(v < 0.0) return -1; return 0; }

   double ComputeAISupport(double directional_prob)
   {
      if(!MathIsValidNumber(directional_prob) || directional_prob <= 0.0 || directional_prob > 1.0)
         return 0.5;

      double p = Clamp(directional_prob, 0.0, 1.0);
      double directional_component = Clamp01((p - 0.5) * 2.0);
      double distance = MathAbs(p - 0.5) * 2.0;
      double curve_component = Clamp01(distance * distance * (3.0 - 2.0 * distance));
      double support = Clamp01(0.55 * directional_component + 0.45 * curve_component);

      // Reliability calibration from live AI performance: shrink AI influence when quality degrades.
      if(g_ai_performance.total_predictions >= 25)
      {
         double acc = Clamp(g_ai_performance.accuracy_rate, 0.35, 0.75);
         double rel = Clamp01((acc - 0.45) / 0.25); // 0 at 45%, 1 at 70%
         double scale = 0.75 + 0.50 * rel;         // 0.75x..1.25x confidence amplitude
         if(g_ai_performance.needs_retraining)
            scale *= 0.85;
         support = Clamp01(0.5 + (support - 0.5) * scale);
      }

      return support;
   }

   double SMA(const MqlRates &rates[], int start, int period)
   {
      int n = ArraySize(rates);
      if(period <= 0 || start < 0 || (start + period) > n) return 0.0;
      double s = 0.0;
      for(int i = start; i < start + period; i++) s += rates[i].close;
      return s / period;
   }

   double StructureDirectionalScore(int structure, int direction)
   {
      if((direction == 1 && structure == STRUCT_BULLISH) || (direction == -1 && structure == STRUCT_BEARISH)) return 100.0;
      if(structure == STRUCT_RANGE) return 45.0;
      return 0.0;
   }

   string ConfidenceLabel(double s)
   {
      if(s <= 40.0) return "LOW";
      if(s <= 60.0) return "WEAK";
      if(s <= 75.0) return "MEDIUM";
      if(s <= 90.0) return "HIGH";
      return "ELITE";
   }

   void ResetDiagnostic(SFilterDiagnostic &d)
   {
      d.trade_score = 0.0; d.required_score = 0.0; d.available_score_max = 100.0;
      d.reason = ""; d.score_breakdown = "";
      d.trend_score = 0.0; d.momentum_score = 0.0; d.volatility_score = 0.0;
      d.structure_score = 0.0; d.alignment_score = 0.0; d.confirmation_score = 0.0;
      d.risk_reward_score = 0.0; d.entry_quality_score = 0.0; d.spread_score = 0.0; d.regime_score = 0.0;
      d.confidence_value = 0.0; d.confidence_label = "LOW"; d.decision = "REJECT";
      d.adaptive_threshold = score_threshold; d.penalty_points = 0.0;
   }

   double ComputeAdaptiveThreshold(double &drawdown_ratio, double &loss_ratio, double &win_ratio)
   {
      drawdown_ratio = 0.0; loss_ratio = 0.0; win_ratio = 0.0;
      if(!adaptive_enabled) return score_threshold;

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(g_equity_all_time_high > 0.0 && equity > 0.0)
      {
         double dd_pct = SafeRatio(g_equity_all_time_high - equity, g_equity_all_time_high, 0.0) * 100.0;
         double dd_limit = (g_Max_Account_Drawdown_Pct_Effective > 0.0 ? g_Max_Account_Drawdown_Pct_Effective : 12.0);
         drawdown_ratio = Clamp01(SafeRatio(dd_pct, dd_limit, 0.0));
      }

      int loss_limit = (Max_Consecutive_Losses > 0 ? Max_Consecutive_Losses : 3);
      loss_ratio = Clamp01(SafeRatio((double)g_consecutive_losses, (double)loss_limit, 0.0));
      win_ratio = Clamp01(SafeRatio((double)g_consecutive_wins, 5.0, 0.0));

      double stress = Clamp01(0.65 * drawdown_ratio + 0.35 * loss_ratio - 0.20 * win_ratio);
      return Clamp(score_threshold + adaptive_threshold_boost_max * stress, score_threshold, 95.0);
   }

   void EffectiveWeights(double drawdown_ratio, double loss_ratio,
                         double &w_trend, double &w_mom, double &w_vol, double &w_struct, double &w_align,
                         double &w_conf, double &w_rr, double &w_entry, double &w_spread, double &w_regime)
   {
      w_trend = weight_trend; w_mom = weight_momentum; w_vol = weight_volatility; w_struct = weight_structure;
      w_align = weight_alignment; w_conf = weight_confirmation; w_rr = weight_risk_reward; w_entry = weight_entry_quality;
      w_spread = weight_spread; w_regime = weight_regime;
      if(!adaptive_enabled) return;

      double stress = Clamp01(0.70 * drawdown_ratio + 0.30 * loss_ratio);
      double risk_mult = 1.0 + adaptive_risk_weight_boost * stress;
      double opp_mult = Clamp(1.0 - adaptive_opportunity_weight_cut * stress, 0.65, 1.05);

      w_trend *= opp_mult; w_mom *= opp_mult; w_struct *= opp_mult; w_align *= opp_mult; w_conf *= opp_mult;
      w_vol *= risk_mult; w_rr *= risk_mult; w_entry *= risk_mult; w_spread *= risk_mult; w_regime *= risk_mult;
   }

public:
   void Init(double threshold, bool enable_diagnostics)
   {
      score_threshold = Clamp(threshold, 1.0, 99.0);
      diagnostics_enabled = enable_diagnostics;
      adaptive_enabled = true;

      // Keep fallback defaults aligned with the institutional input profile (unique, sum=100).
      weight_trend = 18.0; weight_momentum = 13.0; weight_volatility = 11.0; weight_structure = 15.0; weight_alignment = 9.0;
      weight_confirmation = 12.0; weight_risk_reward = 10.0; weight_entry_quality = 7.0; weight_spread = 3.0; weight_regime = 2.0;

      adaptive_threshold_boost_max = 12.0;
      adaptive_risk_weight_boost = 0.35;
      adaptive_opportunity_weight_cut = 0.25;
   }

   void Init(const SScoringModelConfig &cfg)
   {
      score_threshold = Clamp(cfg.execution_threshold, 1.0, 99.0);
      diagnostics_enabled = cfg.diagnostics_enabled;
      adaptive_enabled = cfg.adaptive_enabled;

      weight_trend = MathMax(0.0, cfg.weight_trend);
      weight_momentum = MathMax(0.0, cfg.weight_momentum);
      weight_volatility = MathMax(0.0, cfg.weight_volatility);
      weight_structure = MathMax(0.0, cfg.weight_structure);
      weight_alignment = MathMax(0.0, cfg.weight_alignment);
      weight_confirmation = MathMax(0.0, cfg.weight_confirmation);
      weight_risk_reward = MathMax(0.0, cfg.weight_risk_reward);
      weight_entry_quality = MathMax(0.0, cfg.weight_entry_quality);
      weight_spread = MathMax(0.0, cfg.weight_spread);
      weight_regime = MathMax(0.0, cfg.weight_regime);

      adaptive_threshold_boost_max = Clamp(cfg.adaptive_threshold_boost_max, 0.0, 30.0);
      adaptive_risk_weight_boost = Clamp(cfg.adaptive_risk_weight_boost, 0.0, 1.0);
      adaptive_opportunity_weight_cut = Clamp(cfg.adaptive_opportunity_weight_cut, 0.0, 0.9);

      double ws = weight_trend + weight_momentum + weight_volatility + weight_structure + weight_alignment +
                  weight_confirmation + weight_risk_reward + weight_entry_quality + weight_spread + weight_regime;
      if(ws <= 0.0) Init(score_threshold, diagnostics_enabled);
   }

   double GetScoreThreshold(){ return score_threshold; }

   bool ShouldExecuteTrade(string symbol, ENUM_TIMEFRAMES tf, int direction, SFilterDiagnostic &d,
                           double ai_confidence = 0.0, double rr_hint = 0.0,
                           double entry_distance_pct = -1.0, double reversal_confidence = -1.0)
   {
      ResetDiagnostic(d);
      if(direction != 1 && direction != -1){ d.reason = "Invalid trade direction"; return false; }
      int symbol_index = GetSymbolIndex(symbol);
      if(symbol_index < 0){ d.reason = "Symbol not tracked"; return false; }

      MqlRates rates[]; ArraySetAsSeries(rates, true);
      if(CopyRates(symbol, tf, 0, 80, rates) < 80){ d.reason = "Insufficient data"; return false; }

      double price = rates[0].close;
      if(price <= 0.0){ d.reason = "Invalid price data"; return false; }

      double ma5 = SMA(rates, 0, 5), ma20 = SMA(rates, 0, 20), ma50 = SMA(rates, 0, 50), ma20_prev = SMA(rates, 5, 20);
      if(ma5 <= 0.0 || ma20 <= 0.0 || ma50 <= 0.0 || ma20_prev <= 0.0){ d.reason = "MA calculation failed"; return false; }

      double atr = GetATRValue(symbol, tf);
      if(atr <= 0.0){ atr = MathAbs(rates[1].high - rates[1].low); if(atr <= 0.0) atr = price * 0.001; }

      int htf_bias_dir = GetHTFBias(symbol);
      int htf_bias_score = GetHTFBiasScore(symbol);
      int htf_dir_from_score = SignOf((double)htf_bias_score);
      int htf_dir = (htf_bias_dir != 0 ? htf_bias_dir : htf_dir_from_score);
      double htf_strength = Clamp01(MathAbs((double)htf_bias_score) / 7.0);

      int st_sig = DetectMarketStructure(symbol, tf);
      int st_pri = DetectMarketStructure(symbol, Primary_TF);
      int st_con = DetectMarketStructure(symbol, Confirm_TF);
      int st_trd = DetectMarketStructure(symbol, Trend_TF);

      double slope = SafeRatio(ma20 - ma20_prev, atr, 0.0);
      double slope_score = Clamp01(0.5 + 0.5 * Clamp((double)direction * slope * 4.0, -1.0, 1.0));
      double dir_support = (htf_dir == direction ? 1.0 : (htf_dir == 0 ? 0.45 : 0.0));
      d.trend_score = Clamp100(100.0 * (0.45 * htf_strength + 0.35 * dir_support + 0.20 * slope_score));
      if((direction == 1 && ma20 > ma50) || (direction == -1 && ma20 < ma50)) d.trend_score = Clamp100(d.trend_score + 8.0);

      double macd = 0.0, stoch = 50.0;
      GetMomentumValues(symbol, tf, symbol_index, macd, stoch);
      double rsi = GetRSIValue(symbol, tf, 14);
      double macd_dir_score = (direction == 1 ? (macd > 0.0 ? 1.0 : 0.0) : (macd < 0.0 ? 1.0 : 0.0));
      double macd_mag_score = Clamp01(SafeRatio(MathAbs(macd), atr * 0.25, 0.0));
      double stoch_score = 0.45;
      if(direction == 1){ if(stoch >= 45 && stoch <= 75) stoch_score = 1.0; else if(stoch > 88) stoch_score = 0.25; else if(stoch >= 30) stoch_score = 0.65; }
      else { if(stoch >= 25 && stoch <= 55) stoch_score = 1.0; else if(stoch < 12) stoch_score = 0.25; else if(stoch <= 70) stoch_score = 0.65; }
      double rsi_score = 0.45;
      if(direction == 1){ if(rsi >= 50 && rsi <= 68) rsi_score = 1.0; else if(rsi > 78) rsi_score = 0.30; else if(rsi >= 44) rsi_score = 0.60; }
      else { if(rsi >= 32 && rsi <= 50) rsi_score = 1.0; else if(rsi < 22) rsi_score = 0.30; else if(rsi <= 56) rsi_score = 0.60; }
      d.momentum_score = Clamp100(100.0 * (0.40 * (0.60 * macd_dir_score + 0.40 * macd_mag_score) + 0.35 * stoch_score + 0.25 * rsi_score));

      double vol_factor = GetCachedVolatilityFactor(symbol, symbol_index); if(vol_factor <= 0.0) vol_factor = 1.0;
      double vol_dev = MathAbs(vol_factor - 1.0);
      d.volatility_score = Clamp100((1.0 - Clamp01(vol_dev / 0.85)) * 100.0);
      if(vol_factor < 0.65) d.volatility_score *= 0.65; else if(vol_factor > 1.75) d.volatility_score *= 0.55;

      double ss = StructureDirectionalScore(st_sig, direction), sp = StructureDirectionalScore(st_pri, direction);
      double sc = StructureDirectionalScore(st_con, direction), st = StructureDirectionalScore(st_trd, direction);
      int aligned = 0;
      if((direction == 1 && st_sig == STRUCT_BULLISH) || (direction == -1 && st_sig == STRUCT_BEARISH)) aligned++;
      if((direction == 1 && st_pri == STRUCT_BULLISH) || (direction == -1 && st_pri == STRUCT_BEARISH)) aligned++;
      if((direction == 1 && st_con == STRUCT_BULLISH) || (direction == -1 && st_con == STRUCT_BEARISH)) aligned++;
      if((direction == 1 && st_trd == STRUCT_BULLISH) || (direction == -1 && st_trd == STRUCT_BEARISH)) aligned++;
      d.structure_score = Clamp100(0.20 * ss + 0.25 * sp + 0.25 * sc + 0.30 * st + (aligned >= 3 ? 8.0 : 0.0));

      d.alignment_score = 0.0;
      if(direction == 1){ if(price > ma5) d.alignment_score += 30; if(ma5 > ma20) d.alignment_score += 25; if(ma20 > ma50) d.alignment_score += 25; if(rsi >= 50) d.alignment_score += 20; }
      else { if(price < ma5) d.alignment_score += 30; if(ma5 < ma20) d.alignment_score += 25; if(ma20 < ma50) d.alignment_score += 25; if(rsi <= 50) d.alignment_score += 20; }
      d.alignment_score = Clamp100(d.alignment_score);

      bool ai_known = (ai_confidence > 0.0 && ai_confidence <= 1.0);
      double ai_support = (ai_known ? ComputeAISupport(ai_confidence) : 0.5);
      double mtf_aligned = Clamp01((double)(aligned > 0 ? aligned - 1 : 0) / 3.0);
      d.confirmation_score = Clamp100(100.0 * (0.40 * htf_strength + 0.30 * mtf_aligned + 0.30 * ai_support));
      if(Require_All_TF_Agreement && aligned < 4) d.confirmation_score *= 0.70;
      if(htf_dir != 0 && htf_dir != direction) d.confirmation_score *= 0.25;
      if(ai_known && ai_support > 0.85)
         d.confirmation_score = Clamp100(d.confirmation_score + 4.0);
      if(reversal_confidence >= 0.0)
      {
         double reversal_weight = Clamp(Reversal_Weight_In_Scoring, 0.0, 0.50);
         if(reversal_weight > 0.0)
         {
            double reversal_score = Clamp100(Clamp01(reversal_confidence) * 100.0);
            d.confirmation_score = Clamp100((1.0 - reversal_weight) * d.confirmation_score +
                                            reversal_weight * reversal_score);
            if(reversal_confidence >= Reversal_Min_Confidence)
               d.confirmation_score = Clamp100(d.confirmation_score + 4.0 * reversal_weight);
         }
      }

      bool rr_known = (rr_hint > 0.0);
      double rr = rr_hint;
      if(!rr_known)
      {
         // Pre-entry scoring stage: RR not fully known yet, use neutral prior.
         rr = 0.0;
         d.risk_reward_score = 62.0;
      }
      else
      {
         d.risk_reward_score = Clamp100(Clamp01((rr - 1.0) / 2.5) * 100.0);
         if(rr < g_Min_RR_Ratio) d.risk_reward_score *= 0.35;
         else if(rr >= g_Min_RR_Ratio + 0.5) d.risk_reward_score = Clamp100(d.risk_reward_score + 10.0);
      }

      if(entry_distance_pct >= 0.0)
      {
         double max_ed = MathMax(0.10, g_Max_Entry_Distance_Pct);
         d.entry_quality_score = Clamp100((1.0 - Clamp01(SafeRatio(entry_distance_pct, max_ed, 1.0))) * 100.0);
      }
      else
      {
         d.entry_quality_score = Clamp100((1.0 - Clamp01(SafeRatio(MathAbs(price - ma5), atr, 0.0))) * 100.0);
      }

      long spread_points = 0; SymbolInfoInteger(symbol, SYMBOL_SPREAD, spread_points);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      int pip_points = ((digits == 3 || digits == 5) ? 10 : 1);
      double spread_pips = SafeRatio((double)spread_points, (double)pip_points, 0.0);
      double max_spread = MathMax(1.0, (double)g_Max_Spread_Pips_Effective);
      d.spread_score = Clamp100((1.0 - Clamp01(SafeRatio(spread_pips, max_spread, 1.0))) * 100.0);
      double avg_spread = GetAverageSpreadPips(symbol);
      if(avg_spread > 0.0)
      {
         double reg_mult = SafeRatio(spread_pips, avg_spread, 1.0);
         if(reg_mult > 1.6) d.spread_score *= 0.60; else if(reg_mult > 1.3) d.spread_score *= 0.80;
      }
      if(spread_pips > max_spread) d.spread_score = 0.0;

      bool trending = IsMarketTrending(symbol, tf);
      double avg_range = 0.0; int rc = 0;
      for(int i = 2; i < 16; i++){ double rg = rates[i].high - rates[i].low; if(rg > 0){ avg_range += rg; rc++; } }
      if(rc > 0) avg_range /= rc; else avg_range = atr;
      double last_range = rates[1].high - rates[1].low;
      bool breakout = (avg_range > 0.0 && last_range > avg_range * 1.6 && vol_factor > 1.15);
      d.regime_score = 45.0;
      if(trending && htf_strength >= 0.50) d.regime_score = 85.0;
      else if(trending) d.regime_score = 70.0;
      else if(breakout)
      {
         bool breakout_support = ((direction == 1 && rates[1].close > rates[1].open) || (direction == -1 && rates[1].close < rates[1].open));
         d.regime_score = (breakout_support ? 75.0 : 40.0);
      }
      d.regime_score = Clamp100(d.regime_score);

      double dd_ratio = 0.0, loss_ratio = 0.0, win_ratio = 0.0;
      d.adaptive_threshold = ComputeAdaptiveThreshold(dd_ratio, loss_ratio, win_ratio);

      // ===== TIER 3A ENHANCEMENT: DYNAMIC SCORING WEIGHTS =====
      // Apply regime-aware weight adjustments based on detected market structure
      // TREND mode: emphasize momentum, trend, alignment
      // RANGE mode: emphasize structure, confirmation, reversal factors
      // RETRACEMENT mode: balanced approach across all factors
      SDynamicWeights dyn_weights = CDynamicWeightAdjuster::GetAdjustedWeights(symbol, tf, Primary_TF, Confirm_TF);
      
      // Apply dynamic weights to override static weights
      weight_trend = dyn_weights.weight_trend;
      weight_momentum = dyn_weights.weight_momentum;
      weight_volatility = dyn_weights.weight_volatility;
      weight_structure = dyn_weights.weight_structure;
      weight_alignment = dyn_weights.weight_alignment;
      weight_confirmation = dyn_weights.weight_confirmation;
      weight_risk_reward = dyn_weights.weight_risk_reward;
      weight_entry_quality = dyn_weights.weight_entry_quality;
      weight_spread = dyn_weights.weight_spread;
      weight_regime = dyn_weights.weight_regime;
      
      if(Enable_Institutional_Debug)
         Log(LOG_DEBUG, "ShouldExecuteTrade", symbol + 
             " - Tier 3A: Dynamic weights applied (regime=" + 
             IntegerToString(dyn_weights.detected_regime) + 
             ", trend=" + DoubleToString(weight_trend, 1) + 
             ", structure=" + DoubleToString(weight_structure, 1) + ")");
      // ===== END TIER 3A =====

      double w_trend, w_mom, w_vol, w_struct, w_align, w_conf, w_rr, w_entry, w_spread, w_regime;
      EffectiveWeights(dd_ratio, loss_ratio, w_trend, w_mom, w_vol, w_struct, w_align, w_conf, w_rr, w_entry, w_spread, w_regime);

      double w_sum = w_trend + w_mom + w_vol + w_struct + w_align + w_conf + w_rr + w_entry + w_spread + w_regime;
      if(w_sum <= 0.0) w_sum = 1.0;
      double weighted = (w_trend * d.trend_score + w_mom * d.momentum_score + w_vol * d.volatility_score +
                         w_struct * d.structure_score + w_align * d.alignment_score + w_conf * d.confirmation_score +
                         w_rr * d.risk_reward_score + w_entry * d.entry_quality_score + w_spread * d.spread_score +
                         w_regime * d.regime_score) / w_sum;

      int conflict = 0;
      if(d.trend_score < 35.0) conflict++;
      if(d.momentum_score < 35.0) conflict++;
      if(d.structure_score < 35.0) conflict++;
      if(d.alignment_score < 35.0) conflict++;
      if(d.confirmation_score < 35.0) conflict++;

      d.penalty_points = 0.0;
      if(d.spread_score < 30.0) d.penalty_points += 8.0;
      if(d.volatility_score < 30.0) d.penalty_points += 6.0;
      if(rr_known && d.risk_reward_score < 40.0) d.penalty_points += 10.0;
      if(d.entry_quality_score < 35.0) d.penalty_points += 6.0;
      if(ai_known && g_AI_Require_Agreement_Runtime)
      {
         if(ai_support < 0.35) d.penalty_points += 8.0;
         else if(ai_support < 0.50) d.penalty_points += 4.0;
      }
      if(conflict >= 3) d.penalty_points += 6.0 + (conflict - 3) * 2.0;
      if(htf_dir != 0 && htf_dir != direction) d.penalty_points += 8.0;

      d.trade_score = Clamp100(weighted - d.penalty_points);
      d.available_score_max = Clamp100(100.0 - d.penalty_points);
      d.required_score = d.adaptive_threshold;
      d.confidence_value = d.trade_score;
      d.confidence_label = ConfidenceLabel(d.trade_score);
      d.decision = (d.trade_score >= d.required_score ? "EXECUTE" : "REJECT");

      string base_breakdown = StringFormat(
         "trend=%.1f,momentum=%.1f,volatility=%.1f,structure=%.1f,alignment=%.1f,mtf=%.1f,rr=%.1f,entry=%.1f,spread=%.1f,regime=%.1f,penalty=%.1f",
         d.trend_score, d.momentum_score, d.volatility_score, d.structure_score, d.alignment_score,
         d.confirmation_score, d.risk_reward_score, d.entry_quality_score, d.spread_score, d.regime_score, d.penalty_points
      );

      if(diagnostics_enabled && g_Enable_Institutional_Debug)
      {
         double wn_trend = SafeRatio(w_trend, w_sum, 0.0);
         double wn_mom = SafeRatio(w_mom, w_sum, 0.0);
         double wn_vol = SafeRatio(w_vol, w_sum, 0.0);
         double wn_struct = SafeRatio(w_struct, w_sum, 0.0);
         double wn_align = SafeRatio(w_align, w_sum, 0.0);
         double wn_conf = SafeRatio(w_conf, w_sum, 0.0);
         double wn_rr = SafeRatio(w_rr, w_sum, 0.0);
         double wn_entry = SafeRatio(w_entry, w_sum, 0.0);
         double wn_spread = SafeRatio(w_spread, w_sum, 0.0);
         double wn_regime = SafeRatio(w_regime, w_sum, 0.0);

         double c_trend = wn_trend * d.trend_score;
         double c_mom = wn_mom * d.momentum_score;
         double c_vol = wn_vol * d.volatility_score;
         double c_struct = wn_struct * d.structure_score;
         double c_align = wn_align * d.alignment_score;
         double c_conf = wn_conf * d.confirmation_score;
         double c_rr = wn_rr * d.risk_reward_score;
         double c_entry = wn_entry * d.entry_quality_score;
         double c_spread = wn_spread * d.spread_score;
         double c_regime = wn_regime * d.regime_score;

         d.score_breakdown = StringFormat(
            "%s | wsum=%.1f raw=%.1f | w%%[T=%.2f M=%.2f V=%.2f S=%.2f A=%.2f C=%.2f R=%.2f E=%.2f Sp=%.2f G=%.2f] | c[T=%.1f M=%.1f V=%.1f S=%.1f A=%.1f C=%.1f R=%.1f E=%.1f Sp=%.1f G=%.1f]",
            base_breakdown,
            w_sum,
            weighted,
            wn_trend, wn_mom, wn_vol, wn_struct, wn_align, wn_conf, wn_rr, wn_entry, wn_spread, wn_regime,
            c_trend, c_mom, c_vol, c_struct, c_align, c_conf, c_rr, c_entry, c_spread, c_regime
         );

         if(htf_bias_dir != 0 && htf_dir_from_score != 0 && htf_bias_dir != htf_dir_from_score)
         {
            Log(LOG_WARNING, "ScoringEngine",
                StringFormat("%s %s %s: HTF direction mismatch (bias=%d score=%d dir=%d)",
                             symbol, EnumToString(tf), (direction == 1 ? "BUY" : "SELL"),
                             htf_bias_dir, htf_bias_score, htf_dir_from_score));
         }
      }
      else
      {
         d.score_breakdown = base_breakdown;
      }

      d.reason = StringFormat("Decision=%s | Score=%.1f/100 | Threshold=%.1f | Confidence=%s", d.decision, d.trade_score, d.required_score, d.confidence_label);
      return (d.trade_score >= d.required_score);
   }

   string GetDetailedScoreBreakdown(string symbol, ENUM_TIMEFRAMES tf, int direction,
                                    double ai_confidence = 0.0, double rr_hint = 0.0,
                                    double entry_distance_pct = -1.0, double reversal_confidence = -1.0)
   {
      SFilterDiagnostic d;
      bool ok = ShouldExecuteTrade(symbol, tf, direction, d, ai_confidence, rr_hint,
                                   entry_distance_pct, reversal_confidence);
      return StringFormat("%s %s %s: Score %.1f/%.1f (%s) | Decision=%s | Confidence=%s | Components[%s]",
                          symbol, EnumToString(tf), (direction == 1 ? "BUY" : "SELL"),
                          d.trade_score, d.required_score, (ok ? "PASS" : "FAIL"), d.decision, d.confidence_label, d.score_breakdown);
   }
};

#endif // SCORING_ENGINE_MQH
