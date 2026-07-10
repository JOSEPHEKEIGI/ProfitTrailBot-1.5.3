#ifndef STRATEGY_ROUTER_MQH
#define STRATEGY_ROUTER_MQH

#ifndef AUTO_REGIME_MODE_DISABLED
   #define AUTO_REGIME_MODE_DISABLED      0
#endif
#ifndef AUTO_REGIME_MODE_TREND_ALIGNED
   #define AUTO_REGIME_MODE_TREND_ALIGNED 1
#endif
#ifndef AUTO_REGIME_MODE_RETRACEMENT
   #define AUTO_REGIME_MODE_RETRACEMENT   2
#endif
#ifndef AUTO_REGIME_MODE_INTRA_HIGHLOW
   #define AUTO_REGIME_MODE_INTRA_HIGHLOW 3
#endif

struct SRoutingMatrix
{
   bool ict_allowed;
   bool ai_allowed;
   bool kim_allowed;
   bool require_both;
   int suitability_mode;
   bool suitability_enforced;
   bool director_active;
   int director_strategy_mode;
   double director_lot_multiplier;
   string fail_reason;

   SRoutingMatrix() :
      ict_allowed(false),
      ai_allowed(false),
      kim_allowed(false),
      require_both(false),
      suitability_mode(AUTO_REGIME_MODE_DISABLED),
      suitability_enforced(false),
      director_active(false),
      director_strategy_mode(-1),
      director_lot_multiplier(1.0),
      fail_reason("") {}
};

struct SRegimeScoreCard
{
   double trend_score;
   double range_score;
   double retracement_score;
   double trend_confidence;
   double range_confidence;
   double retracement_confidence;
   double adx;
   double atr_ratio;
   double ema_slope_norm;
   double rsi_now;
   double bb_width_now;
   double bb_width_avg;
   double pullback_ratio;
   bool ema200_aligned;
   bool rsi_reversal;
   bool ema_zone_touch;
   bool mtf_trend_aligned;
   bool trend_directional;

   SRegimeScoreCard() :
      trend_score(0.0),
      range_score(0.0),
      retracement_score(0.0),
      trend_confidence(0.0),
      range_confidence(0.0),
      retracement_confidence(0.0),
      adx(0.0),
      atr_ratio(1.0),
      ema_slope_norm(0.0),
      rsi_now(50.0),
      bb_width_now(0.0),
      bb_width_avg(0.0),
      pullback_ratio(0.5),
      ema200_aligned(false),
      rsi_reversal(false),
      ema_zone_touch(false),
      mtf_trend_aligned(false),
      trend_directional(false) {}
};

SRoutingMatrix BuildRoutingMatrix(bool ai_available, bool kim_enabled);
string AutoRegimeModeToString(int mode);
string GetRegimeRiskProfileTag(int mode);
string SuitabilityHuntModeToString(ENUM_SUITABILITY_HUNT_MODE mode);
string StrategyRoutingModeToString(ENUM_STRATEGY_ROUTING_MODE mode);
int CountEnabledStrategies(const SRoutingMatrix &route);
void ApplySuitabilityRoleToRoute(SRoutingMatrix &route, int suitability_mode,
                                 bool force_trend_confluence,
                                 int htf_score, double volatility_factor, bool signal_aligned,
                                 string &suitability_reason);
SRoutingMatrix BuildEffectiveRoutingMatrix(string symbol, int symbol_index, bool ai_available,
                                           int &auto_mode, string &auto_reason,
                                           int &auto_htf_score, double &auto_volatility,
                                           bool &auto_first_retracement, bool &auto_discount_zone);

#include "InstitutionalStrategyDirector.mqh"

double ClampRouter01(double value)
{
   if(value < 0.0)
      return 0.0;
   if(value > 1.0)
      return 1.0;
   return value;
}

double NormalizeRouterFactor(double value, double low, double high)
{
   if(high <= low)
      return 0.0;
   return ClampRouter01((value - low) / (high - low));
}

bool GetEMAValueForRouter(string symbol, ENUM_TIMEFRAMES tf, int period, int shift, double &value)
{
   value = 0.0;
   if(period <= 0 || shift < 0)
      return false;

   int handle = GetPooledIndicatorHandle(symbol, tf, period, "EMA");
   if(handle == INVALID_HANDLE)
      return false;

   double buffer[];
   ArraySetAsSeries(buffer, true);
   bool ok = (CopyBuffer(handle, 0, shift, 1, buffer) >= 1 &&
              ArraySize(buffer) >= 1 &&
              MathIsValidNumber(buffer[0]));
   if(!ok)
      return false;

   value = buffer[0];
   return true;
}

bool GetADXValueForRouter(string symbol, ENUM_TIMEFRAMES tf, int period, int shift, double &value)
{
   value = 0.0;
   if(period <= 0 || shift < 0)
      return false;

   int handle = GetPooledIndicatorHandle(symbol, tf, period, "ADX");
   if(handle == INVALID_HANDLE)
      return false;

   double buffer[];
   ArraySetAsSeries(buffer, true);
   bool ok = (CopyBuffer(handle, 0, shift, 1, buffer) >= 1 &&
              ArraySize(buffer) >= 1 &&
              MathIsValidNumber(buffer[0]));
   if(!ok)
      return false;

   value = buffer[0];
   return true;
}

bool GetRSIValuesForRouter(string symbol, ENUM_TIMEFRAMES tf, int period, double &rsi_now, double &rsi_prev)
{
   rsi_now = 50.0;
   rsi_prev = 50.0;
   if(period <= 0)
      return false;

   int handle = GetPooledIndicatorHandle(symbol, tf, period, "RSI");
   if(handle == INVALID_HANDLE)
      return false;

   double buffer[];
   ArraySetAsSeries(buffer, true);
   bool ok = (CopyBuffer(handle, 0, 0, 3, buffer) >= 2 && ArraySize(buffer) >= 2);
   if(!ok)
      return false;

   if(MathIsValidNumber(buffer[1]))
      rsi_now = buffer[1];
   if(ArraySize(buffer) >= 3 && MathIsValidNumber(buffer[2]))
      rsi_prev = buffer[2];
   else if(MathIsValidNumber(buffer[0]))
      rsi_prev = buffer[0];

   return true;
}

bool GetBollingerWidthStatsForRouter(string symbol, ENUM_TIMEFRAMES tf, int period, double deviation,
                                     int lookback, double &width_now, double &width_avg)
{
   width_now = 0.0;
   width_avg = 0.0;
   if(period <= 1 || lookback < 3)
      return false;

   int need = lookback + 4;
   int handle = iBands(symbol, tf, period, 0, deviation, PRICE_CLOSE);
   if(handle == INVALID_HANDLE)
      return false;

   double upper[];
   double lower[];
   ArraySetAsSeries(upper, true);
   ArraySetAsSeries(lower, true);
   bool ok = (CopyBuffer(handle, 1, 0, need, upper) >= 3 &&
              CopyBuffer(handle, 2, 0, need, lower) >= 3 &&
              ArraySize(upper) >= 3 &&
              ArraySize(lower) >= 3);
   IndicatorRelease(handle);
   if(!ok)
      return false;

   double close_prices[];
   ArraySetAsSeries(close_prices, true);
   int copied_close = CopyClose(symbol, tf, 0, need, close_prices);
   if(copied_close < 3 || ArraySize(close_prices) < 3)
      return false;

   double close_1 = close_prices[1];
   if(close_1 <= 0.0)
      return false;

   width_now = MathAbs(upper[1] - lower[1]) / close_1;

   double sum = 0.0;
   int valid = 0;
   int limit = MathMin(lookback + 1, MathMin(ArraySize(upper), ArraySize(close_prices) - 1));
   for(int i = 1; i <= limit; i++)
   {
      double c = close_prices[i];
      if(c <= 0.0)
         continue;
      double w = MathAbs(upper[i] - lower[i]) / c;
      if(!MathIsValidNumber(w))
         continue;
      sum += w;
      valid++;
   }

   if(valid <= 0)
      return false;

   width_avg = sum / (double)valid;
   return (MathIsValidNumber(width_now) && MathIsValidNumber(width_avg));
}

bool GetPullbackRatioForRouter(string symbol, ENUM_TIMEFRAMES tf, int direction, int lookback,
                               double &pullback_ratio, double &range_position)
{
   pullback_ratio = 0.5;
   range_position = 0.5;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int bars_needed = MathMax(lookback, 40);
   if(!GetCachedRates(symbol, tf, rates, bars_needed) || ArraySize(rates) < 10)
      return false;

   int bars = MathMin(ArraySize(rates), bars_needed);
   double highest = rates[1].high;
   double lowest = rates[1].low;
   for(int i = 2; i < bars; i++)
   {
      highest = MathMax(highest, rates[i].high);
      lowest = MathMin(lowest, rates[i].low);
   }

   double range = highest - lowest;
   if(range <= 0.0)
      return false;

   double close_price = rates[1].close;
   range_position = ClampRouter01((close_price - lowest) / range);

   if(direction == 1)
      pullback_ratio = ClampRouter01((highest - close_price) / range);
   else if(direction == -1)
      pullback_ratio = ClampRouter01((close_price - lowest) / range);
   else
      pullback_ratio = MathAbs(0.5 - range_position) * 2.0;

   return true;
}

bool BuildRegimeScoreCard(string symbol, int symbol_index, int trend_direction,
                          bool first_retracement, bool discount_zone,
                          int htf_score, double volatility_factor,
                          SRegimeScoreCard &card)
{
   card = SRegimeScoreCard();
   card.trend_directional = (trend_direction == 1 || trend_direction == -1);
   ENUM_TIMEFRAMES regime_tf = Confirm_TF; // Use the configured confirmation timeframe as regime anchor

   if((!MathIsValidNumber(volatility_factor) || volatility_factor <= 0.0) &&
      symbol_index >= 0 && symbol_index < g_symbols_count)
      volatility_factor = GetCachedVolatilityFactor(symbol, symbol_index);

   if(!MathIsValidNumber(volatility_factor) || volatility_factor <= 0.0)
      volatility_factor = 1.0;
   card.atr_ratio = volatility_factor;

   int adx_period = 14;
   double adx_value = 0.0;
   if(GetADXValueForRouter(symbol, regime_tf, adx_period, 1, adx_value))
      card.adx = adx_value;

   double ema50_now = 0.0;
   double ema50_prev = 0.0;
   double ema200_now = 0.0;
   double ema20_sig = 0.0;
   double ema50_sig = 0.0;
   bool has_ema50_now = GetEMAValueForRouter(symbol, regime_tf, 50, 1, ema50_now);
   bool has_ema50_prev = GetEMAValueForRouter(symbol, regime_tf, 50, 2, ema50_prev);
   bool has_ema200 = GetEMAValueForRouter(symbol, regime_tf, 200, 1, ema200_now);
   bool has_ema20_sig = GetEMAValueForRouter(symbol, Signal_TF, 20, 1, ema20_sig);
   bool has_ema50_sig = GetEMAValueForRouter(symbol, Signal_TF, 50, 1, ema50_sig);

   double close_trend = iClose(symbol, regime_tf, 1);
   if(close_trend <= 0.0)
      close_trend = iClose(symbol, regime_tf, 0);
   if(close_trend <= 0.0)
      close_trend = SymbolInfoDouble(symbol, SYMBOL_BID);

   double close_signal = iClose(symbol, Signal_TF, 1);
   if(close_signal <= 0.0)
      close_signal = iClose(symbol, Signal_TF, 0);
   if(close_signal <= 0.0)
      close_signal = close_trend;

   double atr_regime = GetATRValue(symbol, regime_tf);
   if(atr_regime <= 0.0)
      atr_regime = GetATRValue(symbol, Signal_TF);
   if(atr_regime <= 0.0)
      atr_regime = MathMax(SymbolInfoDouble(symbol, SYMBOL_POINT) * 10.0, MathAbs(close_trend) * 0.0001);

   if(has_ema50_now && has_ema50_prev && atr_regime > 0.0)
      card.ema_slope_norm = MathAbs(ema50_now - ema50_prev) / atr_regime;

   if(has_ema200 && close_trend > 0.0)
   {
      if(trend_direction == 1)
         card.ema200_aligned = (close_trend >= ema200_now);
      else if(trend_direction == -1)
         card.ema200_aligned = (close_trend <= ema200_now);
      else
      {
         double relative_dist = MathAbs(close_trend - ema200_now) / MathMax(MathAbs(close_trend), 0.0000001);
         card.ema200_aligned = (relative_dist <= 0.0012);
      }
   }

   double rsi_now = 50.0;
   double rsi_prev = 50.0;
   GetRSIValuesForRouter(symbol, Signal_TF, 14, rsi_now, rsi_prev);
   card.rsi_now = rsi_now;

   if(trend_direction == 1)
      card.rsi_reversal = (rsi_prev <= 42.0 && rsi_now > rsi_prev);
   else if(trend_direction == -1)
      card.rsi_reversal = (rsi_prev >= 58.0 && rsi_now < rsi_prev);
   else
      card.rsi_reversal = (MathAbs(rsi_now - 50.0) < MathAbs(rsi_prev - 50.0));

   GetBollingerWidthStatsForRouter(symbol, Signal_TF, 20, 2.0, 20, card.bb_width_now, card.bb_width_avg);

   double pullback_ratio = 0.5;
   double range_position = 0.5;
   int swing_lb = MathMax(40, g_KImaniz_Swing_Lookback_Bars);
   if(GetPullbackRatioForRouter(symbol, regime_tf, trend_direction, swing_lb, pullback_ratio, range_position))
      card.pullback_ratio = pullback_ratio;

   double atr_signal = GetATRValue(symbol, Signal_TF);
   if(atr_signal <= 0.0)
      atr_signal = atr_regime;
   if(atr_signal <= 0.0)
      atr_signal = MathMax(SymbolInfoDouble(symbol, SYMBOL_POINT) * 10.0, MathAbs(close_signal) * 0.0001);

   if(close_signal > 0.0 && atr_signal > 0.0 && (has_ema20_sig || has_ema50_sig))
   {
      double min_dist = 999.0;
      if(has_ema20_sig)
         min_dist = MathMin(min_dist, MathAbs(close_signal - ema20_sig) / atr_signal);
      if(has_ema50_sig)
         min_dist = MathMin(min_dist, MathAbs(close_signal - ema50_sig) / atr_signal);
      card.ema_zone_touch = (min_dist <= 0.35);
   }

   int primary_structure = DetectMarketStructure(symbol, Primary_TF);
   int signal_structure = DetectMarketStructure(symbol, Signal_TF);
   if(trend_direction == 1)
      card.mtf_trend_aligned = (primary_structure == MARKET_BULLISH &&
                                signal_structure == MARKET_BULLISH);
   else if(trend_direction == -1)
      card.mtf_trend_aligned = (primary_structure == MARKET_BEARISH &&
                                signal_structure == MARKET_BEARISH);
   else
      card.mtf_trend_aligned = false;

   double trend_adx_threshold = MathMax(25.0, g_Strong_Trend_ADX_Level - 3.0);
   double range_adx_threshold = MathMin(20.0, g_Weak_Trend_ADX_Level);
   if(range_adx_threshold < 8.0)
      range_adx_threshold = 8.0;
   if(range_adx_threshold >= trend_adx_threshold)
      range_adx_threshold = trend_adx_threshold - 2.0;

   double adx_trend_factor = NormalizeRouterFactor(card.adx, trend_adx_threshold, trend_adx_threshold + 15.0);
   double adx_range_factor = NormalizeRouterFactor(range_adx_threshold - card.adx, 0.0, range_adx_threshold);
   double ema_slope_factor = NormalizeRouterFactor(card.ema_slope_norm, 0.03, 0.35);
   double atr_expand_factor = NormalizeRouterFactor(card.atr_ratio, 1.0, 1.45);
   double htf_strength_factor = NormalizeRouterFactor((double)MathAbs(htf_score),
                                                      (double)g_Suitability_Weak_Bias_MaxScore,
                                                      (double)(g_Auto_Regime_Strong_Bias_MinScore + 2));
   double bb_compress_factor = 0.0;
   if(card.bb_width_avg > 0.0)
   {
      double compression = (card.bb_width_avg - card.bb_width_now) / card.bb_width_avg;
      bb_compress_factor = NormalizeRouterFactor(compression, 0.0, 0.55);
   }

   double rsi_neutral_factor = 1.0 - NormalizeRouterFactor(MathAbs(card.rsi_now - 50.0), 0.0, 15.0);
   if(rsi_neutral_factor < 0.0)
      rsi_neutral_factor = 0.0;

   double oscillation_factor = 1.0 - NormalizeRouterFactor(MathAbs(range_position - 0.5), 0.0, 0.5);
   if(oscillation_factor < 0.0)
      oscillation_factor = 0.0;

   double fib_factor = 0.0;
   if(card.pullback_ratio >= 0.38 && card.pullback_ratio <= 0.62)
      fib_factor = 1.0 - NormalizeRouterFactor(MathAbs(card.pullback_ratio - 0.5), 0.0, 0.12);

   double retracement_context_factor = 0.0;
   if(first_retracement)
      retracement_context_factor += 0.60;
   if(discount_zone)
      retracement_context_factor += 0.40;
   if(retracement_context_factor > 1.0)
      retracement_context_factor = 1.0;

   double mtf_trend_factor = (card.mtf_trend_aligned ? 1.0 : 0.0);
   double low_volatility_factor = NormalizeRouterFactor(
      g_Auto_Regime_Intra_HighLow_MaxVolatility - card.atr_ratio,
      0.0,
      MathMax(0.12, g_Auto_Regime_Intra_HighLow_MaxVolatility - 0.80)
   );
   if(low_volatility_factor < 0.0)
      low_volatility_factor = 0.0;

   double trend_backdrop = 0.5 * adx_trend_factor + 0.5 * (card.ema200_aligned ? 1.0 : 0.0);
   double rsi_reversal_factor = (card.rsi_reversal ? 1.0 : 0.0);
   double ema_touch_factor = (card.ema_zone_touch ? 1.0 : 0.0);

   card.trend_score =
      1.35 * adx_trend_factor +
      1.15 * ema_slope_factor +
      1.00 * atr_expand_factor +
      0.85 * (card.ema200_aligned ? 1.0 : 0.0) +
      0.65 * mtf_trend_factor +
      0.50 * htf_strength_factor;

   card.range_score =
      1.30 * adx_range_factor +
      1.15 * bb_compress_factor +
      1.00 * rsi_neutral_factor +
      0.70 * oscillation_factor +
      0.55 * low_volatility_factor;

   if(signal_structure == MARKET_RANGE)
      card.range_score += 0.35;

   card.retracement_score =
      1.00 * trend_backdrop +
      1.35 * fib_factor +
      1.05 * rsi_reversal_factor +
      0.90 * ema_touch_factor +
      0.70 * retracement_context_factor +
      0.55 * mtf_trend_factor;

   if(!card.trend_directional)
   {
      card.trend_score *= 0.65;
      card.retracement_score *= 0.55;
      card.range_score += 0.30;
   }

   if(card.atr_ratio > g_Auto_Regime_Intra_HighLow_MaxVolatility)
      card.range_score *= 0.85;

   if(card.trend_score < 0.0) card.trend_score = 0.0;
   if(card.range_score < 0.0) card.range_score = 0.0;
   if(card.retracement_score < 0.0) card.retracement_score = 0.0;

   double total = card.trend_score + card.range_score + card.retracement_score;
   if(total > 0.0)
   {
      card.trend_confidence = card.trend_score / total;
      card.range_confidence = card.range_score / total;
      card.retracement_confidence = card.retracement_score / total;
   }

   return true;
}

int SelectRegimeModeFromScores(const SRegimeScoreCard &card, bool retracement_ready, bool signal_aligned,
                               int htf_score, double &best_score, double &runner_up_score)
{
   int mode = AUTO_REGIME_MODE_INTRA_HIGHLOW;
   best_score = card.range_score;
   runner_up_score = MathMax(card.trend_score, card.retracement_score);

   if(card.trend_score > best_score)
   {
      runner_up_score = MathMax(best_score, card.retracement_score);
      best_score = card.trend_score;
      mode = AUTO_REGIME_MODE_TREND_ALIGNED;
   }

   if(card.retracement_score > best_score)
   {
      runner_up_score = MathMax(best_score, card.range_score);
      best_score = card.retracement_score;
      mode = AUTO_REGIME_MODE_RETRACEMENT;
   }

   if(retracement_ready && card.retracement_score + 0.10 >= best_score)
      mode = AUTO_REGIME_MODE_RETRACEMENT;

   if(mode == AUTO_REGIME_MODE_TREND_ALIGNED &&
      (!signal_aligned || MathAbs(htf_score) < g_Auto_Regime_Strong_Bias_MinScore))
   {
      if(card.range_score >= card.trend_score - 0.10)
         mode = AUTO_REGIME_MODE_INTRA_HIGHLOW;
   }

   if(mode == AUTO_REGIME_MODE_INTRA_HIGHLOW &&
      signal_aligned &&
      card.trend_score >= card.range_score + 0.30)
   {
      mode = AUTO_REGIME_MODE_TREND_ALIGNED;
   }

   return mode;
}

// Regime detector for Tier 3A dynamic scoring weights.
// Returns: 0=TREND, 1=RANGE, 2=RETRACEMENT (mapping for DynamicScoringWeights).
int DetectMarketRegime(string symbol, ENUM_TIMEFRAMES tf)
{
   ENUM_TIMEFRAMES regime_signal_tf = (tf == PERIOD_CURRENT ? Signal_TF : tf);
   int symbol_index = GetSymbolIndex(symbol);

   int trend_direction = GetHTFBiasInstitutional(symbol);
   int signal_structure = DetectMarketStructure(symbol, regime_signal_tf);
   bool signal_aligned = ((trend_direction == 1 && signal_structure == MARKET_BULLISH) ||
                          (trend_direction == -1 && signal_structure == MARKET_BEARISH));

   int htf_score = (int)MathAbs(GetHTFBiasStrengthInstitutional(symbol));
   double volatility_factor = 1.0;
   if(symbol_index >= 0 && symbol_index < g_symbols_count)
      volatility_factor = GetCachedVolatilityFactor(symbol, symbol_index);
   if(!MathIsValidNumber(volatility_factor) || volatility_factor <= 0.0)
      volatility_factor = 1.0;

   bool first_retracement = false;
   bool discount_zone = false;
   if(trend_direction == 1 || trend_direction == -1)
   {
      first_retracement = IsFirstRetracementAfterBOS(symbol, regime_signal_tf, trend_direction);
      discount_zone = IsInDiscountZone(symbol, regime_signal_tf, trend_direction);
   }

   bool retracement_ready = (first_retracement || discount_zone);
   bool strong_trend = (htf_score >= g_Auto_Regime_Strong_Bias_MinScore && signal_aligned);

   SRegimeScoreCard scorecard;
   bool scorecard_ready = BuildRegimeScoreCard(symbol, symbol_index, trend_direction,
                                               first_retracement, discount_zone,
                                               htf_score, volatility_factor,
                                               scorecard);

   // Align with Tier 2A predictor adjustments used by the regime engine.
   if(scorecard_ready)
   {
      SRegimeForecast regime_forecast = CRegimePredictor::PredictMarketRegime(symbol, regime_signal_tf);
      if(regime_forecast.predicted_regime == "TREND")
      {
         scorecard.trend_score *= (1.0 + regime_forecast.confidence * 0.15);
      }
      else if(regime_forecast.predicted_regime == "RANGE" && regime_forecast.confidence > 0.65)
      {
         discount_zone = true;
         retracement_ready = true;
      }
   }

   double best_score = 0.0;
   double runner_score = 0.0;
   int scored_mode = AUTO_REGIME_MODE_DISABLED;
   if(scorecard_ready)
   {
      scored_mode = SelectRegimeModeFromScores(scorecard, retracement_ready, signal_aligned,
                                               htf_score, best_score, runner_score);
   }

   if(scored_mode == AUTO_REGIME_MODE_DISABLED)
   {
      if(retracement_ready)
         scored_mode = AUTO_REGIME_MODE_RETRACEMENT;
      else if(strong_trend)
         scored_mode = AUTO_REGIME_MODE_TREND_ALIGNED;
      else
         scored_mode = AUTO_REGIME_MODE_INTRA_HIGHLOW;
   }

   if(scored_mode == AUTO_REGIME_MODE_TREND_ALIGNED)
      return 0;
   if(scored_mode == AUTO_REGIME_MODE_INTRA_HIGHLOW)
      return 1;
   if(scored_mode == AUTO_REGIME_MODE_RETRACEMENT)
      return 2;

   return 1; // Default to RANGE
}

string GetRegimeRiskProfileTag(int mode)
{
   double multiplier = 1.0;
   string tp_style = "Fixed";
   string sl_style = "Tight";
   string regime_name = "MANUAL";

   switch(mode)
   {
      case AUTO_REGIME_MODE_TREND_ALIGNED:
         multiplier = g_Regime_Risk_Multiplier_Trend;
         tp_style = "Trailing";
         sl_style = "ATR";
         regime_name = "TREND";
         break;
      case AUTO_REGIME_MODE_RETRACEMENT:
         multiplier = g_Regime_Risk_Multiplier_Retracement;
         tp_style = "RR2+";
         sl_style = "Structure";
         regime_name = "RETRACEMENT";
         break;
      case AUTO_REGIME_MODE_INTRA_HIGHLOW:
      default:
         multiplier = g_Regime_Risk_Multiplier_Range;
         tp_style = "Fixed";
         sl_style = "Tight";
         regime_name = "RANGE";
         break;
   }

   double effective_risk_pct = MathMax(0.01, g_Risk_Percent_Effective * multiplier);
   
   // I8 PHASE 3 FIX: Enhanced logging for effective risk visibility
   if(g_Enable_Institutional_Debug)
   {
      Log(LOG_DEBUG, "GetRegimeRiskProfileTag", 
          "I8: Regime=" + regime_name + " BaseRisk=" + DoubleToString(g_Risk_Percent_Effective, 2) + 
          "% Multiplier=" + DoubleToString(multiplier, 2) + "x EffectiveRisk=" + 
          DoubleToString(effective_risk_pct, 2) + "% TP=" + tp_style + " SL=" + sl_style);
   }
   
   return "Risk~" + DoubleToString(effective_risk_pct, 2) +
          "%(" + DoubleToString(multiplier, 2) + "x) TP=" + tp_style + " SL=" + sl_style;
}

string AutoRegimeModeToString(int mode)
{
   switch(mode)
   {
      case AUTO_REGIME_MODE_TREND_ALIGNED: return "TREND";
      case AUTO_REGIME_MODE_RETRACEMENT:   return "RETRACEMENT";
      case AUTO_REGIME_MODE_INTRA_HIGHLOW: return "RANGE";
      default:                             return "MANUAL";
   }
}

string SuitabilityHuntModeToString(ENUM_SUITABILITY_HUNT_MODE mode)
{
   switch(mode)
   {
      case SUITABILITY_HUNT_STRICT:     return "STRICT";
      case SUITABILITY_HUNT_AGGRESSIVE: return "AGGRESSIVE";
      case SUITABILITY_HUNT_BALANCED:
      default:                          return "BALANCED";
   }
}

string StrategyRoutingModeToString(ENUM_STRATEGY_ROUTING_MODE mode)
{
   switch(mode)
   {
      case STRATEGY_ROUTING_ICT_ONLY: return "ICT_ONLY";
      case STRATEGY_ROUTING_AI_ONLY:  return "AI_ONLY";
      case STRATEGY_ROUTING_BOTH:     return "BOTH";
      case STRATEGY_ROUTING_EITHER:
      default:                        return "MIXED";
   }
}

int CountEnabledStrategies(const SRoutingMatrix &route)
{
   int count = 0;
   if(route.ict_allowed) count++;
   if(route.ai_allowed) count++;
   if(route.kim_allowed) count++;
   return count;
}

void ApplySuitabilityRoleToRoute(SRoutingMatrix &route, int suitability_mode,
                                 bool force_trend_confluence,
                                 int htf_score, double volatility_factor, bool signal_aligned,
                                 string &suitability_reason)
{
   bool can_ict = route.ict_allowed;
   bool can_ai = route.ai_allowed;
   bool can_kim = route.kim_allowed;
   bool allow_cross_role = g_Suitability_Allow_CrossRole_Fallbacks;
   bool strict_hunt = (g_Suitability_Hunt_Mode == SUITABILITY_HUNT_STRICT);
   bool aggressive_hunt = (g_Suitability_Hunt_Mode == SUITABILITY_HUNT_AGGRESSIVE);
   bool weak_bias = (htf_score <= g_Suitability_Weak_Bias_MaxScore);
   bool high_volatility = (volatility_factor >= g_Suitability_High_Volatility_Factor);
   string hunt_mode_label = SuitabilityHuntModeToString(g_Suitability_Hunt_Mode);

   route.ict_allowed = false;
   route.ai_allowed = false;
   route.kim_allowed = false;
   route.require_both = false;
   route.fail_reason = "";
   route.suitability_mode = suitability_mode;
   route.suitability_enforced = true;

   switch(suitability_mode)
   {
      case AUTO_REGIME_MODE_RETRACEMENT:
      {
         if(can_kim)
         {
            route.kim_allowed = true;
            suitability_reason = "Suitability RETRACEMENT: KImaniz primary";
            if(allow_cross_role && !strict_hunt)
            {
               if(can_ict && (aggressive_hunt || htf_score >= g_Auto_Regime_Strong_Bias_MinScore || signal_aligned))
                  route.ict_allowed = true;
               if(can_ai && aggressive_hunt && !weak_bias)
                  route.ai_allowed = true;
            }
         }
         else if(can_ict)
         {
            route.ict_allowed = true;
            suitability_reason = "Suitability RETRACEMENT: ICT fallback (KImaniz unavailable)";
         }
         else if(can_ai)
         {
            route.ai_allowed = true;
            suitability_reason = "Suitability RETRACEMENT: AI fallback (KImaniz/ICT unavailable)";
         }
         else
         {
            route.fail_reason = "SuitabilityRetracementNoStrategyAvailable";
            suitability_reason = "Suitability RETRACEMENT: no strategy available";
         }

         if(route.kim_allowed && route.ict_allowed && route.ai_allowed)
            suitability_reason = "Suitability RETRACEMENT: KImaniz primary + ICT/AI hunt fallback";
         else if(route.kim_allowed && route.ict_allowed)
            suitability_reason = "Suitability RETRACEMENT: KImaniz primary + ICT hunt fallback";
         else if(route.kim_allowed && route.ai_allowed)
            suitability_reason = "Suitability RETRACEMENT: KImaniz primary + AI hunt fallback";
         break;
      }
      case AUTO_REGIME_MODE_TREND_ALIGNED:
      {
         bool require_confluence = force_trend_confluence;
         if(can_ict && can_ai &&
            g_Suitability_Trend_Require_Confluence_On_Weak_Bias &&
            weak_bias)
            require_confluence = true;

         if(can_ict)
            route.ict_allowed = true;

         if(can_ai && (!strict_hunt || !can_ict || force_trend_confluence))
            route.ai_allowed = true;

         if(can_ict && can_ai && require_confluence)
         {
            route.require_both = true;
            suitability_reason = "Suitability TREND: require ICT+AI confluence";
         }
         else if(route.ict_allowed && route.ai_allowed)
         {
            suitability_reason = "Suitability TREND: ICT primary + AI confirmation";
         }
         else if(route.ict_allowed)
         {
            suitability_reason = "Suitability TREND: ICT primary";
         }
         else if(route.ai_allowed)
         {
            suitability_reason = "Suitability TREND: AI fallback (ICT unavailable)";
         }
         else if(can_kim)
         {
            route.kim_allowed = true;
            suitability_reason = "Suitability TREND: KImaniz fallback (ICT/AI unavailable)";
         }
         else
         {
            route.fail_reason = "SuitabilityTrendNoStrategyAvailable";
            suitability_reason = "Suitability TREND: no strategy available";
         }

         if(allow_cross_role && aggressive_hunt && !route.require_both)
         {
            if(!route.ai_allowed && can_ai)
               route.ai_allowed = true;
            if(!route.ict_allowed && can_ict)
               route.ict_allowed = true;
         }
         break;
      }
      case AUTO_REGIME_MODE_INTRA_HIGHLOW:
      default:
      {
         if(can_ai)
         {
            route.ai_allowed = true;
            suitability_reason = "Suitability RANGE: AI primary";
            if(allow_cross_role && !strict_hunt && can_ict &&
               (aggressive_hunt || high_volatility))
               route.ict_allowed = true;
            if(allow_cross_role && aggressive_hunt && can_kim && !high_volatility)
               route.kim_allowed = true;
         }
         else if(can_ict)
         {
            route.ict_allowed = true;
            suitability_reason = "Suitability RANGE: ICT fallback (AI unavailable)";
         }
         else if(can_kim)
         {
            route.kim_allowed = true;
            suitability_reason = "Suitability RANGE: KImaniz fallback (AI/ICT unavailable)";
         }
         else
         {
            route.fail_reason = "SuitabilityIntraNoStrategyAvailable";
            suitability_reason = "Suitability RANGE: no strategy available";
         }

         if(route.ai_allowed && route.ict_allowed && route.kim_allowed)
            suitability_reason = "Suitability RANGE: AI primary + ICT/KImaniz hunt fallback";
         else if(route.ai_allowed && route.ict_allowed)
            suitability_reason = "Suitability RANGE: AI primary + ICT hunt fallback";
         break;
      }
   }

   suitability_reason += " | HuntMode=" + hunt_mode_label +
                         " weakBias=" + (weak_bias ? "Y" : "N") +
                         " highVol=" + (high_volatility ? "Y" : "N");
}

SRoutingMatrix BuildEffectiveRoutingMatrix(string symbol, int symbol_index, bool ai_available,
                                           int &auto_mode, string &auto_reason,
                                           int &auto_htf_score, double &auto_volatility,
                                           bool &auto_first_retracement, bool &auto_discount_zone)
{
   SRoutingMatrix route = BuildRoutingMatrix(ai_available, g_Enable_KImaniz_Strategy);

   auto_mode = AUTO_REGIME_MODE_DISABLED;
   auto_reason = "Manual strategy routing";
   auto_htf_score = 0;
   auto_volatility = 1.0;
   auto_first_retracement = false;
   auto_discount_zone = false;

   if(g_Use_Institutional_Strategy_Director)
   {
      SRoutingMatrix director_route;
      if(BuildInstitutionalDirectorRouting(symbol, symbol_index, ai_available,
                                           route, director_route,
                                           auto_mode, auto_reason,
                                           auto_htf_score, auto_volatility,
                                           auto_first_retracement, auto_discount_zone))
      {
         if(StringLen(director_route.fail_reason) == 0)
            auto_reason += " | " + GetRegimeRiskProfileTag(auto_mode);
         return director_route;
      }
   }

   int trend_direction = GetHTFBiasInstitutional(symbol);
   int signal_structure = DetectMarketStructure(symbol, Signal_TF);
   bool signal_aligned = ((trend_direction == 1 && signal_structure == MARKET_BULLISH) ||
                          (trend_direction == -1 && signal_structure == MARKET_BEARISH));

   auto_htf_score = (int)MathAbs(GetHTFBiasStrengthInstitutional(symbol));
   if(symbol_index >= 0 && symbol_index < g_symbols_count)
      auto_volatility = GetCachedVolatilityFactor(symbol, symbol_index);
   if(!MathIsValidNumber(auto_volatility) || auto_volatility <= 0.0)
      auto_volatility = 1.0;

   if(trend_direction == 1 || trend_direction == -1)
   {
      auto_first_retracement = IsFirstRetracementAfterBOS(symbol, Signal_TF, trend_direction);
      auto_discount_zone = IsInDiscountZone(symbol, Signal_TF, trend_direction);
   }

   bool retracement_ready = (auto_first_retracement || auto_discount_zone);
   bool strong_trend = (auto_htf_score >= g_Auto_Regime_Strong_Bias_MinScore && signal_aligned);

   SRegimeScoreCard scorecard;
   bool scorecard_ready = BuildRegimeScoreCard(symbol, symbol_index, trend_direction,
                                               auto_first_retracement, auto_discount_zone,
                                               auto_htf_score, auto_volatility,
                                               scorecard);

   // ===== TIER 2A ENHANCEMENT: REGIME PREDICTOR =====
   // Enhance regime prediction with forward-looking volatility analysis
   // Adjust scorecard based on predicted breakout/consolidation zones
   {
      SRegimeForecast regime_forecast = CRegimePredictor::PredictMarketRegime(symbol, Signal_TF);
      
      // Boost scores if predictor forecasts regime alignment
      if(regime_forecast.predicted_regime == "TREND" && scorecard_ready)
      {
         scorecard.trend_score *= (1.0 + regime_forecast.confidence * 0.15);  // Up to 15% boost
      }
      else if(regime_forecast.predicted_regime == "RANGE" && scorecard_ready)
      {
         // Range prediction: favor intra-high-low mode
         if(regime_forecast.confidence > 0.65)
            auto_discount_zone = true;
         auto_volatility *= (1.0 - regime_forecast.confidence * 0.10);  // Reduce vol for ranges
      }
      
      if(Enable_Institutional_Debug)
         Log(LOG_DEBUG, "BuildEffectiveRoutingMatrix", symbol + 
             " - Tier 2A: Regime forecast=" + regime_forecast.predicted_regime +
             ", conf=" + DoubleToString(regime_forecast.confidence, 2));
   }
   // ===== END TIER 2A =====

   double best_score = 0.0;
   double runner_score = 0.0;
   int scored_mode = AUTO_REGIME_MODE_DISABLED;
   if(scorecard_ready)
   {
      scored_mode = SelectRegimeModeFromScores(scorecard, retracement_ready, signal_aligned,
                                               auto_htf_score, best_score, runner_score);
   }

   if(scored_mode == AUTO_REGIME_MODE_DISABLED)
   {
      if(retracement_ready)
         scored_mode = AUTO_REGIME_MODE_RETRACEMENT;
      else if(strong_trend)
         scored_mode = AUTO_REGIME_MODE_TREND_ALIGNED;
      else
         scored_mode = AUTO_REGIME_MODE_INTRA_HIGHLOW;
   }

   auto_mode = scored_mode;
   route.suitability_mode = auto_mode;

   if(scorecard_ready)
   {
      auto_reason = StringFormat(
         "RegimeEngine score[T=%.2f,R=%.2f,RT=%.2f conf(%.0f/%.0f/%.0f%%)] ADX=%.1f ATRx=%.2f EMA50s=%.2f RSI=%.1f BB=%.4f/%.4f Pull=%.2f",
         scorecard.trend_score,
         scorecard.range_score,
         scorecard.retracement_score,
         scorecard.trend_confidence * 100.0,
         scorecard.range_confidence * 100.0,
         scorecard.retracement_confidence * 100.0,
         scorecard.adx,
         scorecard.atr_ratio,
         scorecard.ema_slope_norm,
         scorecard.rsi_now,
         scorecard.bb_width_now,
         scorecard.bb_width_avg,
         scorecard.pullback_ratio
      );
   }

   if(symbol_index >= 0 && symbol_index < MAX_SYMBOLS)
   {
      static int router_last_mode[MAX_SYMBOLS];
      static bool router_seeded[MAX_SYMBOLS];

      datetime signal_bar = iTime(symbol, Signal_TF, 0);
      if(g_Enable_Auto_Regime_Router && router_seeded[symbol_index] &&
         router_last_mode[symbol_index] != auto_mode)
      {
         double margin = best_score - runner_score;
         if(margin < 0.22)
         {
            int held_mode = router_last_mode[symbol_index];
            auto_reason = "RegimeEngine hysteresis hold " + AutoRegimeModeToString(held_mode) +
                          " (switch margin " + DoubleToString(margin, 2) + ") | " + auto_reason;
            auto_mode = held_mode;
         }
      }

      if(signal_bar > 0)
      {
         router_last_mode[symbol_index] = auto_mode;
         router_seeded[symbol_index] = true;
      }
      else if(!router_seeded[symbol_index])
      {
         router_last_mode[symbol_index] = auto_mode;
         router_seeded[symbol_index] = true;
      }
      else
      {
         router_last_mode[symbol_index] = auto_mode;
      }
   }

   int enabled_strategy_count = CountEnabledStrategies(route);

   // Suitability-driven role routing should only be active when Auto Regime Router is enabled.
   // In manual mode (EITHER/ICT_ONLY/AI_ONLY/BOTH), preserve the operator's explicit routing intent.
   if(g_Enable_Auto_Regime_Router)
   {
      bool force_trend_confluence = true;
      string suitability_reason = auto_reason;
      ApplySuitabilityRoleToRoute(route, auto_mode, force_trend_confluence,
                                  auto_htf_score, auto_volatility, signal_aligned,
                                  suitability_reason);

      auto_reason = suitability_reason +
                    StringFormat(" (first=%s discount=%s htf=%d vol=%.2f)",
                                 (auto_first_retracement ? "Y" : "N"),
                                 (auto_discount_zone ? "Y" : "N"),
                                 auto_htf_score,
                                 auto_volatility);
      auto_reason += " | " + GetRegimeRiskProfileTag(auto_mode);
   }
   else
   {
      route.suitability_enforced = false;
      route.suitability_mode = AUTO_REGIME_MODE_DISABLED;
      if(route.require_both)
      {
         auto_reason = "Manual routing: BOTH mode";
      }
      else if(enabled_strategy_count <= 1)
      {
         auto_reason = "Manual routing: single strategy";
      }
      else
      {
         auto_reason = "Manual strategy routing";
      }
   }

   return route;
}

SRoutingMatrix BuildRoutingMatrix(bool ai_available, bool kim_enabled)
{
   SRoutingMatrix m;
   bool kim_only = (kim_enabled && g_KImaniz_Only_Mode);

   if(kim_only)
   {
      m.kim_allowed = true;
      return m;
   }

   switch(g_Strategy_Routing_Mode)
   {
      case STRATEGY_ROUTING_ICT_ONLY:
         m.ict_allowed = g_Enable_ICT_Strategy;
         if(!m.ict_allowed) m.fail_reason = "ICTDisabled";
         break;

      case STRATEGY_ROUTING_AI_ONLY:
         m.ai_allowed = (g_Enable_AI_Strategy && ai_available);
         if(!g_Enable_AI_Strategy) m.fail_reason = "AIDisabled";
         else if(!ai_available)     m.fail_reason = "AIUnavailable";
         break;

      case STRATEGY_ROUTING_BOTH:
         m.require_both = true;
         m.ict_allowed = g_Enable_ICT_Strategy;
         m.ai_allowed = (g_Enable_AI_Strategy && ai_available);
         if(!m.ict_allowed || !m.ai_allowed)
         {
            if(!m.ict_allowed)
               m.fail_reason = "ICTDisabled";
            else if(!g_Enable_AI_Strategy)
               m.fail_reason = "AIDisabled";
            else
               m.fail_reason = "AIUnavailable";
         }
         break;

      case STRATEGY_ROUTING_EITHER:
      default:
         m.ict_allowed = g_Enable_ICT_Strategy;
         m.ai_allowed = (g_Enable_AI_Strategy && ai_available);
         m.kim_allowed = kim_enabled;
         if(!m.ict_allowed && !m.ai_allowed && !m.kim_allowed)
            m.fail_reason = "AllStrategiesDisabled";
         break;
   }

   return m;
}

#endif // STRATEGY_ROUTER_MQH
