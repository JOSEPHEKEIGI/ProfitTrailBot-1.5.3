#ifndef AI_CANDLE_QUALITY_FILTER_MQH
#define AI_CANDLE_QUALITY_FILTER_MQH

struct SAICandleQualityResult
{
   bool   pass;
   double score;
   double min_required_score;
   double body_ratio;
   double opposite_wick_ratio;
   double close_location_score;
   double momentum_score;
   double directional_consistency_score;
   double trend_alignment_score;
   double range_atr_ratio;
   double spread_atr_ratio;
   string reason;

   SAICandleQualityResult() :
      pass(false),
      score(0.0),
      min_required_score(0.0),
      body_ratio(0.0),
      opposite_wick_ratio(1.0),
      close_location_score(0.0),
      momentum_score(0.0),
      directional_consistency_score(0.0),
      trend_alignment_score(0.0),
      range_atr_ratio(0.0),
      spread_atr_ratio(0.0),
      reason("")
   {}
};

double AICQClamp01(double value)
{
   if(!MathIsValidNumber(value))
      return 0.0;
   if(value < 0.0)
      return 0.0;
   if(value > 1.0)
      return 1.0;
   return value;
}

string AICQDirToText(int direction)
{
   if(direction == 1) return "BUY";
   if(direction == -1) return "SELL";
   return "NEUTRAL";
}

double AICQBarRange(const MqlRates &bar)
{
   return (bar.high - bar.low);
}

bool AICQIsDirectionalCandle(const MqlRates &bar, int direction, double &delta)
{
   delta = bar.close - bar.open;
   if(direction == 1)
      return (delta > 0.0);
   if(direction == -1)
      return (delta < 0.0);
   return false;
}

double AICQBodyRatio(const MqlRates &bar)
{
   double range = AICQBarRange(bar);
   if(range <= 0.0)
      return 0.0;
   return AICQClamp01(MathAbs(bar.close - bar.open) / range);
}

double AICQOppositeWickRatio(const MqlRates &bar, int direction)
{
   double range = AICQBarRange(bar);
   if(range <= 0.0)
      return 1.0;

   double upper_wick = bar.high - MathMax(bar.open, bar.close);
   double lower_wick = MathMin(bar.open, bar.close) - bar.low;
   if(upper_wick < 0.0) upper_wick = 0.0;
   if(lower_wick < 0.0) lower_wick = 0.0;

   // Opposite wick: buy -> upper wick, sell -> lower wick.
   double opposite_wick = (direction == 1 ? upper_wick : lower_wick);
   return AICQClamp01(opposite_wick / range);
}

double AICQCloseLocationScore(const MqlRates &bar, int direction)
{
   double range = AICQBarRange(bar);
   if(range <= 0.0)
      return 0.0;

   if(direction == 1)
      return AICQClamp01((bar.close - bar.low) / range);
   if(direction == -1)
      return AICQClamp01((bar.high - bar.close) / range);
   return 0.0;
}

double AICQMomentumScore(const MqlRates &rates[], int direction, int lookback)
{
   int checks = MathMax(1, lookback - 1);
   double hits = 0.0;
   int used = 0;

   for(int i = 1; i <= checks; i++)
   {
      if((i + 1) >= ArraySize(rates))
         break;

      double delta = direction * (rates[i].close - rates[i + 1].close);
      if(delta > 0.0)
         hits += 1.0;
      else if(MathAbs(delta) <= 1e-10)
         hits += 0.5;
      used++;
   }

   if(used <= 0)
      return 0.0;
   return AICQClamp01(SafeDiv(hits, (double)used, 0.0));
}

double AICQDirectionalConsistencyScore(const MqlRates &rates[], int direction, int bars)
{
   int checks = MathMax(2, bars);
   double points = 0.0;
   int used = 0;

   for(int i = 1; i <= checks; i++)
   {
      if(i >= ArraySize(rates))
         break;

      double delta = direction * (rates[i].close - rates[i].open);
      if(delta > 0.0)
         points += 1.0;
      else if(MathAbs(delta) <= 1e-10)
         points += 0.5;
      used++;
   }

   if(used <= 0)
      return 0.0;
   return AICQClamp01(SafeDiv(points, (double)used, 0.0));
}

double AICQRangeScore(double range_atr_ratio, double min_range, double max_range)
{
   if(!MathIsValidNumber(range_atr_ratio) || range_atr_ratio <= 0.0)
      return 0.0;

   if(range_atr_ratio < min_range)
      return AICQClamp01(range_atr_ratio / min_range);
   if(range_atr_ratio > max_range)
      return AICQClamp01(max_range / range_atr_ratio);

   return 1.0;
}

bool AICQStructureAligned(int direction, int structure)
{
   if(direction == 1)
      return (structure == MARKET_BULLISH);
   if(direction == -1)
      return (structure == MARKET_BEARISH);
   return false;
}

double AICQTrendAlignmentScore(string symbol, int direction,
                               int &sig_structure, int &primary_structure,
                               int &confirm_structure, int &trend_structure)
{
   sig_structure = DetectMarketStructure(symbol, Signal_TF);
   primary_structure = DetectMarketStructure(symbol, Primary_TF);
   confirm_structure = DetectMarketStructure(symbol, Confirm_TF);
   trend_structure = DetectMarketStructure(symbol, Trend_TF);

   int structures[4] = {sig_structure, primary_structure, confirm_structure, trend_structure};
   double weights[4] = {1.0, 2.0, 2.0, 3.0};

   double score = 0.0;
   double total = 0.0;
   for(int i = 0; i < 4; i++)
   {
      total += weights[i];
      if(AICQStructureAligned(direction, structures[i]))
         score += weights[i];
      else if(structures[i] == MARKET_RANGE)
         score += weights[i] * 0.5;
   }

   return AICQClamp01(SafeDiv(score, total, 0.0));
}

double AICQAdaptiveMinQuality(double base_min_quality, double spread_atr_ratio,
                              double trend_alignment_score, double consistency_score)
{
   double required = AICQClamp01(base_min_quality);

   // Penalize expensive execution conditions.
   if(spread_atr_ratio > 0.08)
      required += MathMin(0.10, (spread_atr_ratio - 0.08) * 0.90);

   // Penalize weak directional persistence.
   if(consistency_score < 0.70)
      required += MathMin(0.08, (0.70 - consistency_score) * 0.25);

   // Penalize weak trend consensus.
   if(trend_alignment_score < 0.75)
      required += MathMin(0.07, (0.75 - trend_alignment_score) * 0.20);

   return MathMin(0.95, AICQClamp01(required));
}

SAICandleQualityResult EvaluateAICandleQuality(string symbol, int direction, const MqlRates &rates[],
                                               double atr_value, double current_bid, double current_ask)
{
   SAICandleQualityResult out;

   if(!CGateController::IsStructuralGateEnabled() || !g_Enable_AI_Candle_Quality_Filter)
   {
      out.pass = true;
      out.score = 1.0;
      out.min_required_score = 0.0;
      out.reason = "disabled";
      return out;
   }

   if(direction != 1 && direction != -1)
   {
      out.reason = "invalid direction";
      return out;
   }

   int lookback = MathMax(2, MathMin(5, g_AI_Candle_Quality_Lookback_Bars));
   if(ArraySize(rates) < (lookback + 3))
   {
      out.reason = "insufficient candle history";
      return out;
   }

   if(atr_value <= 0.0 || !MathIsValidNumber(atr_value))
   {
      out.reason = "invalid ATR";
      return out;
   }

   const MqlRates trigger = rates[1]; // last closed candle
   double range = AICQBarRange(trigger);
   if(range <= 0.0 || !MathIsValidNumber(range))
   {
      out.reason = "invalid trigger candle";
      return out;
   }

   double trigger_delta = 0.0;
   bool trigger_direction_ok = AICQIsDirectionalCandle(trigger, direction, trigger_delta);
   bool trigger_soft_override = false;
   double trigger_body_ratio = AICQBodyRatio(trigger);

   int sig_structure = MARKET_RANGE;
   int primary_structure = MARKET_RANGE;
   int confirm_structure = MARKET_RANGE;
   int trend_structure = MARKET_RANGE;
   out.trend_alignment_score = AICQTrendAlignmentScore(symbol, direction, sig_structure, primary_structure,
                                                       confirm_structure, trend_structure);
   int htf_bias = GetHTFBiasInstitutional(symbol);
   bool htf_aligned = (htf_bias == direction);

   // Allow a narrow soft-override when last closed candle is a weak counter candle
   // but multi-timeframe trend context is still strongly aligned.
   if(!trigger_direction_ok)
   {
      bool weak_counter_candle = (trigger_body_ratio <= 0.22);
      bool strong_context = (out.trend_alignment_score >= 0.82 && htf_aligned);
      if(weak_counter_candle && strong_context)
      {
         trigger_soft_override = true;
      }
      else
      {
         out.reason = StringFormat(
            "trigger candle direction mismatch (dir=%s open=%.5f close=%.5f body=%.2f trend=%.2f htf=%d)",
            AICQDirToText(direction), trigger.open, trigger.close, trigger_body_ratio,
            out.trend_alignment_score, htf_bias
         );
         return out;
      }
   }

   if(out.trend_alignment_score < 0.65 || !htf_aligned)
   {
      out.reason = StringFormat("trend not confirmed (dir=%s align=%.2f sig=%d pri=%d conf=%d trend=%d htf=%d)",
                                AICQDirToText(direction), out.trend_alignment_score,
                                sig_structure, primary_structure, confirm_structure, trend_structure, htf_bias);
      return out;
   }

   out.body_ratio = trigger_body_ratio;
   out.opposite_wick_ratio = AICQOppositeWickRatio(trigger, direction);
   out.close_location_score = AICQCloseLocationScore(trigger, direction);
   out.momentum_score = AICQMomentumScore(rates, direction, lookback);
   out.directional_consistency_score = AICQDirectionalConsistencyScore(rates, direction, lookback);
   // FIX #10: Use SafeDiv for division operations
   out.range_atr_ratio = SafeDiv(range, atr_value, 1.0);

   if(current_ask > current_bid)
      out.spread_atr_ratio = SafeDiv(current_ask - current_bid, atr_value, 0.0);
   else
      out.spread_atr_ratio = 0.0;

   double min_quality = MathMax(0.0, MathMin(1.0, g_AI_Candle_Min_Quality_Score));
   double min_body = MathMax(0.05, MathMin(0.95, g_AI_Candle_Min_Body_Ratio));
   double max_opp_wick = MathMax(0.05, MathMin(0.95, g_AI_Candle_Max_Opposite_Wick_Ratio));
   double min_range = MathMax(0.05, g_AI_Candle_ATR_Min_Range_Factor);
   double max_range = MathMax(min_range + 0.05, g_AI_Candle_ATR_Max_Range_Factor);

   // Hard sanity guards for execution quality.
   if(out.body_ratio < min_body * 0.55)
   {
      out.reason = StringFormat("body too weak (%.2f < hard %.2f)", out.body_ratio, min_body * 0.55);
      return out;
   }
   if(out.opposite_wick_ratio > MathMin(0.98, max_opp_wick * 1.35))
   {
      out.reason = StringFormat("opposite wick too large (%.2f > hard %.2f)",
                                out.opposite_wick_ratio, MathMin(0.98, max_opp_wick * 1.35));
      return out;
   }
   if(out.directional_consistency_score < 0.30)
   {
      out.reason = StringFormat("directional consistency too low (%.2f)", out.directional_consistency_score);
      return out;
   }
   if(out.spread_atr_ratio > 0.24)
   {
      out.reason = StringFormat("spread too expensive vs ATR (%.3f)", out.spread_atr_ratio);
      return out;
   }

   double body_score = AICQClamp01((out.body_ratio - min_body) / (1.0 - min_body));
   double wick_score = AICQClamp01((max_opp_wick - out.opposite_wick_ratio) / max_opp_wick);
   double range_score = AICQRangeScore(out.range_atr_ratio, min_range, max_range);
   double spread_score = AICQClamp01(1.0 - out.spread_atr_ratio / 0.18);

   // Institutional blend: directional intent + trend confirmation + execution quality.
   out.score = 0.18 * body_score +
               0.14 * wick_score +
               0.14 * out.close_location_score +
               0.16 * out.momentum_score +
               0.12 * out.directional_consistency_score +
               0.14 * out.trend_alignment_score +
               0.08 * range_score +
               0.04 * spread_score;

   out.min_required_score = AICQAdaptiveMinQuality(min_quality, out.spread_atr_ratio,
                                                   out.trend_alignment_score, out.directional_consistency_score);

   if(trigger_soft_override)
   {
      // Keep this path conservative: allow continuation pullback candles,
      // but require higher quality score and apply a score haircut.
      out.score *= 0.90;
      out.min_required_score = MathMin(0.95, out.min_required_score + 0.05);
   }

   out.pass = (out.score >= out.min_required_score);
   out.reason = StringFormat(
      "Q=%.2f/%.2f body=%.2f wick=%.2f close=%.2f mom=%.2f cons=%.2f trend=%.2f r/atr=%.2f spr/atr=%.3f",
      out.score, out.min_required_score, out.body_ratio, out.opposite_wick_ratio, out.close_location_score,
      out.momentum_score, out.directional_consistency_score, out.trend_alignment_score,
      out.range_atr_ratio, out.spread_atr_ratio
   );

   if(trigger_soft_override)
      out.reason += " | soft_trigger_override";

   if(!out.pass)
   {
      string flags = "";
      if(body_score < 0.35) flags += " weak_body";
      if(wick_score < 0.35) flags += " large_opp_wick";
      if(out.close_location_score < 0.40) flags += " weak_close";
      if(out.momentum_score < 0.45) flags += " weak_momentum";
      if(out.directional_consistency_score < 0.50) flags += " choppy";
      if(out.trend_alignment_score < 0.70) flags += " weak_trend";
      if(range_score < 0.35) flags += " poor_range";
      if(spread_score < 0.35) flags += " expensive_spread";
      if(StringLen(flags) > 0)
         out.reason += " |" + flags;
   }

   return out;
}

#endif // AI_CANDLE_QUALITY_FILTER_MQH
