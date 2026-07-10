#ifndef KIMANIZ_STRATEGY_MQH
#define KIMANIZ_STRATEGY_MQH

struct SKImanizContext
{
   bool   valid;
   int    lookback;
   double swing_high;
   double swing_low;
   double swing_range;
   double otp_low;
   double otp_mid;
   double otp_high;
   double tp_29;
   double tp_41;
   double zone_distance_pct;

   SKImanizContext() :
      valid(false),
      lookback(0),
      swing_high(0.0),
      swing_low(0.0),
      swing_range(0.0),
      otp_low(0.0),
      otp_mid(0.0),
      otp_high(0.0),
      tp_29(0.0),
      tp_41(0.0),
      zone_distance_pct(999.0)
   {}
};

struct SKImanizSwingCache
{
   string   symbol;
   ENUM_TIMEFRAMES tf;
   int      lookback;
   datetime bar_time;
   double   high;
   double   low;
   bool     valid;

   SKImanizSwingCache() : symbol(""), tf(PERIOD_CURRENT), lookback(0), bar_time(0), high(0.0), low(0.0), valid(false) {}
};

bool RepairKImanizTradeLevels(string symbol,
                              int direction,
                              double min_rr,
                              double &entry,
                              double &sl,
                              double &tp,
                              string &repair_summary)
{
   repair_summary = "";
   if(direction != 1 && direction != -1)
      return false;

   STradeLevelContext trade_ctx;
   string trade_ctx_error = "";
   if(!BuildTradeLevelContext(symbol, -1, trade_ctx, trade_ctx_error))
   {
      repair_summary = "ctx_failed[" + trade_ctx_error + "]";
      return false;
   }

   double point = trade_ctx.point;
   double tick_size = trade_ctx.tick_size;

   long stop_level_long = 0;
   long freeze_level_long = 0;
   SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL, stop_level_long);
   SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL, freeze_level_long);

   double min_distance = MathMax((double)stop_level_long, (double)freeze_level_long) * point;
   if(min_distance <= 0.0)
      min_distance = point * 10.0;

   double spread = (double)g_symbols[trade_ctx.symbol_index].cache.spread * point;
   double buffer = MathMax(MathMax(point, tick_size), point * 2.0);
   double required_distance = MathMax(min_distance, spread * 2.0);
   required_distance = MathMax(required_distance + buffer, point * 5.0);
   double rr_cap = MathMax(min_rr + 2.0, 6.0);

   double repaired_risk = MathMax(MathAbs(entry - sl), required_distance);
   double min_reward = MathMax(required_distance, repaired_risk * MathMax(min_rr, 1.0));
   double max_reward = MathMax(min_reward, repaired_risk * rr_cap);
   double desired_reward = MathAbs(tp - entry);
   if(!MathIsValidNumber(desired_reward) || desired_reward <= 0.0)
      desired_reward = min_reward;
   double repaired_reward = MathMin(MathMax(desired_reward, min_reward), max_reward);

   if(direction == 1)
   {
      sl = entry - repaired_risk;
      tp = entry + repaired_reward;
   }
   else
   {
      sl = entry + repaired_risk;
      tp = entry - repaired_reward;
   }

   int repaired_reason = TRADE_LEVELS_OK;
   if(!NormalizeAndValidateTradeLevels(symbol, trade_ctx, entry, sl, tp, repaired_reason))
   {
      repair_summary = "repair_failed[" + TradeLevelsReasonLabel(repaired_reason) + "]";
      return false;
   }

   repair_summary = StringFormat("min=%.5f spread=%.5f risk=%.5f reward=%.5f rrCap=%.2f",
                                 min_distance, spread, MathAbs(entry - sl), MathAbs(tp - entry), rr_cap);
   return true;
}

bool GetKImanizSwingRange(string symbol, ENUM_TIMEFRAMES tf, int lookback, double &swing_high, double &swing_low)
{
   swing_high = 0.0;
   swing_low = 0.0;

   datetime bar_time = iTime(symbol, tf, 0);
   if(bar_time <= 0)
      return false;
   static SKImanizSwingCache cache[32];
   for(int ci = 0; ci < 32; ci++)
   {
      if(cache[ci].valid &&
         cache[ci].symbol == symbol &&
         cache[ci].tf == tf &&
         cache[ci].lookback == lookback &&
         cache[ci].bar_time == bar_time)
      {
         // BUG FIX 1.2: Verify cache entry is for CURRENT bar (not stale from previous session)
         // Additional validation: ensure bar_time is still current (on active bar)
         datetime prev_bar_time = iTime(symbol, tf, 1);
         if(prev_bar_time >= bar_time)
         {
            // Bar time went backwards - this shouldn't happen, invalidate cache
            cache[ci].valid = false;
            break;
         }
         
         swing_high = cache[ci].high;
         swing_low = cache[ci].low;
         return true;
      }
   }

   int bars_needed = MathMax(20, lookback);
   MqlRates rates[];
   if(!GetCachedRates(symbol, tf, rates, bars_needed) || ArraySize(rates) < 20)
      return false;
   if(ArraySize(rates) < lookback)
      return false;

   int bars = MathMin(ArraySize(rates), bars_needed);
   swing_high = rates[0].high;
   swing_low = rates[0].low;

   for(int i = 1; i < bars; i++)
   {
      swing_high = MathMax(swing_high, rates[i].high);
      swing_low = MathMin(swing_low, rates[i].low);
   }

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = Point();

   bool ok = ((swing_high - swing_low) > point * 20.0);
   if(ok)
   {
      int target_idx = -1;
      int oldest_idx = 0;
      datetime oldest_time = UINT_MAX;
      
      // Priority 1: Find invalid (empty) slot
      for(int ci = 0; ci < 32; ci++)
      {
         if(!cache[ci].valid)
         {
            target_idx = ci;
            break;
         }
         // Track oldest valid entry for fallback (BUG FIX 1.3)
         if(cache[ci].bar_time < oldest_time)
         {
            oldest_time = cache[ci].bar_time;
            oldest_idx = ci;
         }
      }
      
      // Priority 2: If no empty slot, find matching symbol
      if(target_idx < 0)
      {
         for(int ci = 0; ci < 32; ci++)
         {
            if(cache[ci].symbol == symbol)
            {
               target_idx = ci;
               break;
            }
         }
      }
      
      // Priority 3: Overwrite oldest entry (all slots occupied, no symbol match)
      if(target_idx < 0)
      {
         target_idx = oldest_idx;
      }
      
      cache[target_idx].symbol = symbol;
      cache[target_idx].tf = tf;
      cache[target_idx].lookback = lookback;
      cache[target_idx].bar_time = bar_time;
      cache[target_idx].high = swing_high;
      cache[target_idx].low = swing_low;
      cache[target_idx].valid = true;
   }
   return ok;
}

double KImanizFibLevel(int direction, double swing_high, double swing_low, double fib_pct)
{
   double range = swing_high - swing_low;
   double p = fib_pct / 100.0;
   p = MathMax(0.0, MathMin(1.0, p));

   if(direction == 1)
      return swing_high - (range * p);

   return swing_low + (range * p);
}

double Mid3(double a, double b, double c)
{
   double mn = MathMin(a, MathMin(b, c));
   double mx = MathMax(a, MathMax(b, c));
   return (a + b + c - mn - mx);
}

double DistancePctToZone(double price, double low, double high)
{
   if(price <= 0.0)
      return 999.0;
   if(price < low)
      return ((low - price) / price) * 100.0;
   if(price > high)
      return ((price - high) / price) * 100.0;
   return 0.0;
}

double BuildKImanizRiskFloor(double point,
                             double atr_value,
                             double swing_range,
                             double stop_buffer,
                             double broker_min_distance)
{
   double micro_floor = point * 15.0;
   double atr_floor = MathMax(atr_value * 0.25, micro_floor);
   double swing_floor = MathMax(swing_range * 0.006, micro_floor);
   double structural_floor = MathMax(stop_buffer, MathMin(atr_floor, swing_floor));
   return MathMax(structural_floor, broker_min_distance);
}

double BuildKImanizTargetBuffer(double point,
                                double stop_buffer,
                                double broker_min_distance)
{
   return MathMax(point * 10.0, MathMax(stop_buffer * 0.5, broker_min_distance * 0.5));
}

bool IsKImanizDirectionalTargetValid(int direction,
                                     double entry,
                                     double target,
                                     double target_buffer)
{
   if((direction != 1 && direction != -1) ||
      !MathIsValidNumber(entry) || !MathIsValidNumber(target))
   {
      return false;
   }

   if(direction == 1)
      return (target > entry + target_buffer);

   return (target < entry - target_buffer);
}

double SelectKImanizDirectionalTarget(int direction,
                                      double entry,
                                      double tp_29,
                                      double tp_41,
                                      double target_buffer,
                                      bool &tp29_valid,
                                      bool &tp41_valid,
                                      string &target_basis)
{
   tp29_valid = IsKImanizDirectionalTargetValid(direction, entry, tp_29, target_buffer);
   tp41_valid = IsKImanizDirectionalTargetValid(direction, entry, tp_41, target_buffer);
   target_basis = "RR_FALLBACK";

   if(tp29_valid && tp41_valid)
   {
      if(direction == 1)
      {
         if(tp_29 <= tp_41)
         {
            target_basis = "TP29";
            return tp_29;
         }
         target_basis = "TP41";
         return tp_41;
      }

      if(tp_29 >= tp_41)
      {
         target_basis = "TP29";
         return tp_29;
      }
      target_basis = "TP41";
      return tp_41;
   }

   if(tp29_valid)
   {
      target_basis = "TP29";
      return tp_29;
   }

   if(tp41_valid)
   {
      target_basis = "TP41";
      return tp_41;
   }

   return 0.0;
}

bool BuildKImanizContext(string symbol, int direction, int lookback, double current_price, SKImanizContext &ctx)
{
   ctx = SKImanizContext();
   ctx.lookback = lookback;

   double swing_high = 0.0, swing_low = 0.0;
   if(!GetKImanizSwingRange(symbol, Primary_TF, lookback, swing_high, swing_low))
      return false;

   double range = swing_high - swing_low;
   if(range <= 0.0 || !MathIsValidNumber(range))
      return false;

   double otp_70 = KImanizFibLevel(direction, swing_high, swing_low, g_KImaniz_OTP_Low_Pct);
   double otp_74 = KImanizFibLevel(direction, swing_high, swing_low, g_KImaniz_OTP_Mid_Pct);
   double otp_79 = KImanizFibLevel(direction, swing_high, swing_low, g_KImaniz_OTP_High_Pct);
   double otp_low = MathMin(otp_70, MathMin(otp_74, otp_79));
   double otp_high = MathMax(otp_70, MathMax(otp_74, otp_79));
   double otp_mid = Mid3(otp_70, otp_74, otp_79);

   ctx.valid = true;
   ctx.swing_high = swing_high;
   ctx.swing_low = swing_low;
   ctx.swing_range = range;
   ctx.otp_low = otp_low;
   ctx.otp_mid = otp_mid;
   ctx.otp_high = otp_high;
   ctx.tp_29 = KImanizFibLevel(direction, swing_high, swing_low, g_KImaniz_Fib_Zone_29_Pct);
   ctx.tp_41 = KImanizFibLevel(direction, swing_high, swing_low, g_KImaniz_Fib_Zone_41_Pct);
   ctx.zone_distance_pct = DistancePctToZone(current_price, otp_low, otp_high);
   return true;
}

bool ResolveBestKImanizContextForDirection(string symbol,
                                           int direction,
                                           int &lookbacks[],
                                           int lookback_count,
                                           double current_price,
                                           SKImanizContext &best_ctx)
{
   best_ctx = SKImanizContext();
   if(direction != 1 && direction != -1)
      return false;

   for(int li = 0; li < lookback_count; li++)
   {
      int lb = lookbacks[li];
      bool duplicate = false;
      for(int lj = 0; lj < li; lj++)
      {
         if(lookbacks[lj] == lb)
         {
            duplicate = true;
            break;
         }
      }
      if(duplicate)
         continue;

      SKImanizContext ctx;
      if(!BuildKImanizContext(symbol, direction, lb, current_price, ctx))
         continue;

      if(!best_ctx.valid || ctx.zone_distance_pct < best_ctx.zone_distance_pct)
         best_ctx = ctx;
   }

   return best_ctx.valid;
}

STradingSignal GenerateKImanizSignal(string symbol, bool allow_range_mode = false,
                                     bool has_seeded_trend_direction = false,
                                     int seeded_trend_direction = 0)
{
   STradingSignal signal;
   signal.origin = SIGNAL_ORIGIN_KIMANIZ;

   if(!g_Enable_KImaniz_Strategy)
   {
      signal.reason = "KImaniz strategy disabled";
      return signal;
   }

   int symbol_index = -1;
   if(!RunCommonSignalPrechecks(symbol, signal, symbol_index, true, true, allow_range_mode,
                                has_seeded_trend_direction, seeded_trend_direction))
      return signal;

   double bid = g_symbols[symbol_index].cache.bid;
   double ask = g_symbols[symbol_index].cache.ask;
   double current_price = (bid > 0.0 && ask > 0.0 ? (bid + ask) / 2.0 : 0.0);
   if(current_price <= 0.0 || !MathIsValidNumber(current_price))
   {
      signal.reason = "Invalid current price";
      return signal;
   }

   if(!RunCommonSignalPostChecks(symbol, symbol_index, signal))
      return signal;

   double atr_value = GetATRValue(symbol, Signal_TF);
   if(atr_value <= 0.0 || !MathIsValidNumber(atr_value))
      atr_value = current_price * 0.0020;

   // Adaptive OTP tolerance improves hit-rate in volatile sessions.
   double base_zone_tol_pct = MathMax(0.0, g_KImaniz_Entry_Zone_Tolerance_Pct);
   double atr_zone_tol_pct = (current_price > 0.0 ? (atr_value / current_price) * 100.0 * 0.35 : 0.0);
   double otp_zone_tol_pct = MathMin(1.20, MathMax(base_zone_tol_pct, atr_zone_tol_pct));
   double relaxed_zone_pct = MathMin(5.00, otp_zone_tol_pct * 3.0 + 0.25); // wider tolerance to avoid "too far" rejects
   double hunt_extra_pct = 0.0;
   if(g_Suitability_Hunt_Mode == SUITABILITY_HUNT_BALANCED)
      hunt_extra_pct = 0.35;
   else if(g_Suitability_Hunt_Mode == SUITABILITY_HUNT_AGGRESSIVE)
      hunt_extra_pct = 0.70;

   int base_lb = MathMax(20, g_KImaniz_Swing_Lookback_Bars);
   int lookbacks[4];
   lookbacks[0] = base_lb;
   lookbacks[1] = MathMax(20, (base_lb * 3) / 4);
   lookbacks[2] = MathMax(20, base_lb / 2);
   lookbacks[3] = MathMax(20, (base_lb * 5) / 4);

   SKImanizContext best_ctx;
   bool best_ctx_resolved = false;
   int direction = ResolveHTFBiasForSignalPass(symbol,
                                               has_seeded_trend_direction,
                                               seeded_trend_direction);
   int htf_bias = direction;
   int signal_structure_dir = StructureToDirection(DetectMarketStructure(symbol, Signal_TF));
   bool first_retracement = false;
   bool discount_zone = false;
   bool retracement_context = false;
   if(htf_bias == 1 || htf_bias == -1)
   {
      first_retracement = IsFirstRetracementAfterBOS(symbol, Signal_TF, htf_bias);
      discount_zone = IsInDiscountZone(symbol, Signal_TF, htf_bias);
      retracement_context = (first_retracement || discount_zone);
      if(retracement_context)
         signal.retracement_signal = true;
   }

   if(direction == 0)
   {
      if(!allow_range_mode)
      {
         signal.reason = "Calculated trend neutral - trading blocked";
         return signal;
      }

      SKImanizContext best_buy_ctx;
      SKImanizContext best_sell_ctx;
      ResolveBestKImanizContextForDirection(symbol, 1, lookbacks, ArraySize(lookbacks), current_price, best_buy_ctx);
      ResolveBestKImanizContextForDirection(symbol, -1, lookbacks, ArraySize(lookbacks), current_price, best_sell_ctx);

      if(!best_buy_ctx.valid && !best_sell_ctx.valid)
      {
         signal.reason = "No valid swing context for KImaniz";
         return signal;
      }

      if(best_buy_ctx.valid && !best_sell_ctx.valid)
      {
         direction = 1;
         best_ctx = best_buy_ctx;
      }
      else if(best_sell_ctx.valid && !best_buy_ctx.valid)
      {
         direction = -1;
         best_ctx = best_sell_ctx;
      }
      else
      {
         double buy_dist = best_buy_ctx.zone_distance_pct;
         double sell_dist = best_sell_ctx.zone_distance_pct;
         int structure_hint = StructureToDirection(DetectMarketStructure(symbol, Signal_TF));
         if(buy_dist + 0.01 < sell_dist)
         {
            direction = 1;
            best_ctx = best_buy_ctx;
         }
         else if(sell_dist + 0.01 < buy_dist)
         {
            direction = -1;
            best_ctx = best_sell_ctx;
         }
         else if(structure_hint == 1)
         {
            direction = 1;
            best_ctx = best_buy_ctx;
         }
         else if(structure_hint == -1)
         {
            direction = -1;
            best_ctx = best_sell_ctx;
         }
         else
         {
            double swing_mid = (best_buy_ctx.swing_high + best_buy_ctx.swing_low) * 0.5;
            direction = (current_price <= swing_mid ? 1 : -1);
            best_ctx = (direction == 1 ? best_buy_ctx : best_sell_ctx);
         }
      }

      best_ctx_resolved = true;
      Log(LOG_INFO, "GenerateKImanizSignal",
          symbol + " - Neutral HTF bias in range mode: using " +
          (direction == 1 ? "BUY" : "SELL") + " KImaniz context (buyDist=" +
          DoubleToString(best_buy_ctx.zone_distance_pct, 2) + "%, sellDist=" +
          DoubleToString(best_sell_ctx.zone_distance_pct, 2) + "%)");
   }

   bool countertrend_candidate =
      (g_KImaniz_Allow_Countertrend_With_HTF_Gate &&
       htf_bias != 0 &&
       retracement_context &&
       signal_structure_dir == -htf_bias);

   if(!best_ctx_resolved && countertrend_candidate)
   {
      int countertrend_htf_score = (int)MathAbs(GetHTFBiasStrengthInstitutional(symbol));
      int min_countertrend_htf_score = MathMax(1, g_Integrity_Min_HTF_Bias_Score);
      if(countertrend_htf_score < min_countertrend_htf_score)
      {
         Log(LOG_DEBUG, "GenerateKImanizSignal",
             symbol + " - KImaniz countertrend blocked by HTF gate (score=" +
             IntegerToString(countertrend_htf_score) + " < " +
             IntegerToString(min_countertrend_htf_score) + ")");
      }
      else
      {
         SKImanizContext countertrend_ctx;
         if(ResolveBestKImanizContextForDirection(symbol, -htf_bias, lookbacks, ArraySize(lookbacks), current_price, countertrend_ctx))
         {
            direction = -htf_bias;
            best_ctx = countertrend_ctx;
            best_ctx_resolved = true;
            signal.allow_countertrend_execution = true;
            string signal_tf_label = (signal_structure_dir == 1 ? "BUY" :
                                     (signal_structure_dir == -1 ? "SELL" : "NEUTRAL"));
            Log(LOG_INFO, "GenerateKImanizSignal",
                symbol + " - Countertrend KImaniz retracement armed with HTF gate (HTF=" +
                (htf_bias == 1 ? "BUY" : "SELL") +
                ", SignalTF=" + signal_tf_label +
                ", HTFScore=" + IntegerToString(countertrend_htf_score) +
                ", FirstRetrace=" + (first_retracement ? "Y" : "N") +
                ", Discount=" + (discount_zone ? "Y" : "N") + ")");
         }
         else
         {
            Log(LOG_DEBUG, "GenerateKImanizSignal",
                symbol + " - Retracement context detected but no countertrend KImaniz context resolved; checking HTF-aligned fallback");
         }
      }
   }

   if(!best_ctx_resolved &&
      htf_bias != 0 &&
      retracement_context)
   {
      SKImanizContext retracement_ctx;
      if(ResolveBestKImanizContextForDirection(symbol, htf_bias, lookbacks, ArraySize(lookbacks), current_price, retracement_ctx))
      {
         direction = htf_bias;
         best_ctx = retracement_ctx;
         best_ctx_resolved = true;
         signal.allow_countertrend_execution = false;

         string signal_tf_label = (signal_structure_dir == 1 ? "BUY" :
                                  (signal_structure_dir == -1 ? "SELL" : "NEUTRAL"));
         Log(LOG_INFO, "GenerateKImanizSignal",
             symbol + " - HTF-aligned KImaniz retracement armed (HTF=" +
             (htf_bias == 1 ? "BUY" : "SELL") +
             ", SignalTF=" + signal_tf_label +
             ", FirstRetrace=" + (first_retracement ? "Y" : "N") +
             ", Discount=" + (discount_zone ? "Y" : "N") + ")");
      }
      else
      {
         Log(LOG_DEBUG, "GenerateKImanizSignal",
             symbol + " - Retracement context detected but no HTF-aligned KImaniz context resolved");
      }
   }

   if(direction != 1 && direction != -1)
   {
      signal.reason = "No directional bias for KImaniz";
      return signal;
   }

   // Final same-bar anti-flooding for KImaniz is enforced in ProcessSignals() after
   // routing/final gates. Do not lock here, otherwise an unselected or unqueued
   // candidate can suppress later same-bar KImaniz opportunities.

   if(!best_ctx_resolved)
   {
      ResolveBestKImanizContextForDirection(symbol, direction, lookbacks, ArraySize(lookbacks), current_price, best_ctx);
   }

   if(!best_ctx.valid)
   {
      signal.reason = "No valid swing context for KImaniz";
      return signal;
   }

   double bias_boost = 0.0;
   int htf_score = MathAbs(GetHTFBiasScore(symbol));
   if(htf_score >= 7)
      bias_boost = 0.5; // allow a bit more distance when bias is strong

   double allowed_zone_pct = relaxed_zone_pct + bias_boost + hunt_extra_pct;
   if(best_ctx.zone_distance_pct > allowed_zone_pct)
   {
      if(!CGateController::IsStructuralGateEnabled())
      {
         Log(LOG_INFO, "GenerateKImanizSignal", symbol +
             " - OTP distance gate bypassed by gate controller ("+
             DoubleToString(best_ctx.zone_distance_pct, 2) + "% > " +
             DoubleToString(allowed_zone_pct, 2) + "%)");
      }
      else
      {
         signal.reason = "Price too far from KImaniz OTP (" + DoubleToString(best_ctx.zone_distance_pct, 2) +
                        "% > " + DoubleToString(allowed_zone_pct, 2) + "%)";
         return signal;
      }
   }

   bool in_strict_otp_zone = (best_ctx.zone_distance_pct <= otp_zone_tol_pct);

   double fvg_high = 0.0, fvg_low = 0.0;
   bool fvg_found = DetectFairValueGap(symbol, Signal_TF, direction, fvg_high, fvg_low);
   string fvg_tf_tag = "SignalTF";
   if(!fvg_found)
   {
      fvg_found = DetectFairValueGap(symbol, Primary_TF, direction, fvg_high, fvg_low);
      if(fvg_found) fvg_tf_tag = "PrimaryTF";
   }

   bool allow_no_fvg = false;
   if(!fvg_found)
   {
      int htf_score = (int)MathAbs(GetHTFBiasStrengthInstitutional(symbol));
      // Permit no-FVG trades only when bias is strong OR we are inside the strict OTP zone.
      // Using relaxed_zone here makes this gate effectively always pass after the prior distance filter.
      allow_no_fvg = (htf_score >= 5 || in_strict_otp_zone);
      if(!allow_no_fvg)
      {
         signal.reason = "No FVG confluence for KImaniz";
         return signal;
      }
      fvg_tf_tag = (htf_score >= 5 ? "None(StrongBias)" : "None(StrictOTP)");
   }

   int digits = g_symbols[symbol_index].cache.digits;
   signal.direction = direction;

   // Keep market-intended entries on the executable quote side so later
   // slippage/closeness checks do not treat midpoint entries as artificially far.
   double market_entry = (direction == 1 ? ask : bid);
   if(market_entry <= 0.0 || !MathIsValidNumber(market_entry))
      market_entry = current_price;
   bool force_pending_preference = (!in_strict_otp_zone &&
                                    (signal.retracement_signal || signal.allow_countertrend_execution));
   bool use_pending_entry = (!in_strict_otp_zone && (g_Use_Pending_Orders || force_pending_preference));
   double desired_entry = (use_pending_entry ? best_ctx.otp_mid : market_entry);

   // Keep entry realistic vs current market to avoid stale far-away placements.
   double desired_entry_dist_pct = (current_price > 0.0 ? MathAbs(desired_entry - current_price) / current_price * 100.0 : 0.0);
   double entry_hard_cap_pct = MathMin(1.8, MathMax(0.60, g_Max_Entry_Distance_Pct));
   if(use_pending_entry && desired_entry_dist_pct > entry_hard_cap_pct)
   {
      Log(LOG_DEBUG, "GenerateKImanizSignal", symbol +
          " - OTP midpoint entry too far from market (" +
          DoubleToString(desired_entry_dist_pct, 2) + "% > " +
          DoubleToString(entry_hard_cap_pct, 2) + "%); using market-side entry");
      use_pending_entry = false;
      desired_entry = market_entry;
   }

   // Alignment guard: keep KImaniz pending entries as pullbacks, not breakout stops.
   if(use_pending_entry)
   {
      if(direction == 1 && desired_entry > current_price)
      {
         Log(LOG_DEBUG, "GenerateKImanizSignal", symbol +
             " - Pending BUY entry crossed above current price; using market-side entry");
         use_pending_entry = false;
         desired_entry = market_entry;
      }
      else if(direction == -1 && desired_entry < current_price)
      {
         Log(LOG_DEBUG, "GenerateKImanizSignal", symbol +
             " - Pending SELL entry crossed below current price; using market-side entry");
         use_pending_entry = false;
         desired_entry = market_entry;
      }
   }

   signal.entry_price = NormalizeDouble(desired_entry, digits);
   signal.fvg_high = fvg_high;
   signal.fvg_low = fvg_low;
   signal.atr_value = atr_value;

   STradeLevelContext trade_ctx;
   string trade_ctx_error = "";
   if(!BuildTradeLevelContext(symbol, symbol_index, trade_ctx, trade_ctx_error))
   {
      signal.reason = "KImaniz " + trade_ctx_error;
      return signal;
   }

   double point = trade_ctx.point;
   double stop_buffer = MathMax(atr_value * 0.20, point * 10.0);
   long stop_level_long = 0;
   long freeze_level_long = 0;
   SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL, stop_level_long);
   SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL, freeze_level_long);

   double spread_distance = (double)g_symbols[trade_ctx.symbol_index].cache.spread * point;
   double broker_min_distance = MathMax((double)stop_level_long, (double)freeze_level_long) * point;
   broker_min_distance = MathMax(broker_min_distance, spread_distance * 2.0);
   broker_min_distance = MathMax(broker_min_distance, MathMax(point * 5.0, trade_ctx.tick_size * 2.0));
   double structural_risk_floor = BuildKImanizRiskFloor(point, atr_value, best_ctx.swing_range, stop_buffer, broker_min_distance);
   double target_buffer = BuildKImanizTargetBuffer(point, stop_buffer, broker_min_distance);
   double kim_rr_cap = MathMax(g_Min_RR_Ratio + 2.0, 6.0);
   string stop_basis = "";
   string target_basis = "";
   bool tp29_valid = false;
   bool tp41_valid = false;
   bool target_capped = false;

   // Use tighter structure anchor when FVG exists, else fall back to swing invalidation.
   if(direction == 1)
   {
      double swing_sl = best_ctx.swing_low - stop_buffer;
      double fvg_sl = (fvg_found ? (fvg_low - stop_buffer * 0.40) : swing_sl);
      signal.stop_loss = swing_sl;
      stop_basis = "SWING";
      if(fvg_found && fvg_sl > signal.stop_loss)
      {
         signal.stop_loss = fvg_sl;
         stop_basis = "FVG";
      }

      double floor_stop = signal.entry_price - structural_risk_floor;
      if(signal.stop_loss > floor_stop)
      {
         signal.stop_loss = floor_stop;
         stop_basis += "+FLOOR";
      }

      if(signal.stop_loss >= signal.entry_price - point * 5.0)
      {
         signal.stop_loss = signal.entry_price - structural_risk_floor;
         stop_basis = "ENTRY_FLOOR";
      }
   }
   else
   {
      double swing_sl = best_ctx.swing_high + stop_buffer;
      double fvg_sl = (fvg_found ? (fvg_high + stop_buffer * 0.40) : swing_sl);
      signal.stop_loss = swing_sl;
      stop_basis = "SWING";
      if(fvg_found && fvg_sl < signal.stop_loss)
      {
         signal.stop_loss = fvg_sl;
         stop_basis = "FVG";
      }

      double floor_stop = signal.entry_price + structural_risk_floor;
      if(signal.stop_loss < floor_stop)
      {
         signal.stop_loss = floor_stop;
         stop_basis += "+FLOOR";
      }

      if(signal.stop_loss <= signal.entry_price + point * 5.0)
      {
         signal.stop_loss = signal.entry_price + structural_risk_floor;
         stop_basis = "ENTRY_FLOOR";
      }
   }

   // Inversion guard: force SL/TP to remain on the correct side of entry for direction.
   bool buy_stop_layout = (signal.stop_loss < signal.entry_price);
   bool sell_stop_layout = (signal.stop_loss > signal.entry_price);
   if(direction == 1 && !buy_stop_layout)
   {
      signal.stop_loss = signal.entry_price - structural_risk_floor;
      stop_basis = "ENTRY_FLOOR";
   }
   else if(direction == -1 && !sell_stop_layout)
   {
      signal.stop_loss = signal.entry_price + structural_risk_floor;
      stop_basis = "ENTRY_FLOOR";
   }

   double risk = MathAbs(signal.entry_price - signal.stop_loss);
   if(risk <= point)
   {
      signal.reason = "Invalid KImaniz risk distance";
      return signal;
   }

   if(!g_Disable_All_Gates && Enable_Max_Risk_Distance_Validation &&
      g_KImaniz_Max_Risk_ATR_Multiple > 0.0 && atr_value > 0.0)
   {
      double max_kim_risk = MathMax(structural_risk_floor, atr_value * g_KImaniz_Max_Risk_ATR_Multiple);
      double risk_base = GetRiskBaseValue();
      double final_risk_cap = (risk_base > 0.0 && g_Final_Per_Trade_Risk_Cap_Pct > 0.0 ?
                               risk_base * g_Final_Per_Trade_Risk_Cap_Pct / 100.0 : 0.0);
      double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      if(final_risk_cap > 0.0 && min_lot > 0.0)
      {
         double cap_sl = signal.entry_price - direction * max_kim_risk;
         double minlot_risk_at_cap = CalculateTradeRiskCurrency(symbol, direction, min_lot,
                                                                 signal.entry_price, cap_sl);
         if(minlot_risk_at_cap > final_risk_cap && minlot_risk_at_cap > 0.0)
         {
            double affordability_risk = max_kim_risk * SafeDiv(final_risk_cap, minlot_risk_at_cap, 0.0);
            if(affordability_risk > point)
            {
               double adjusted_max_kim_risk = MathMax(structural_risk_floor, affordability_risk);
               if(adjusted_max_kim_risk < max_kim_risk)
               {
                  Log(LOG_INFO, "GenerateKImanizSignal", symbol +
                      " - KImaniz final-cap risk fit: max risk " +
                      DoubleToString(max_kim_risk, digits) + " -> " +
                      DoubleToString(adjusted_max_kim_risk, digits) +
                      " (min-lot risk $" + DoubleToString(minlot_risk_at_cap, 2) +
                      " > cap $" + DoubleToString(final_risk_cap, 2) + ")");
                  max_kim_risk = adjusted_max_kim_risk;
               }
            }
         }
      }
      if(risk > max_kim_risk)
      {
         double capped_sl = signal.entry_price - direction * max_kim_risk;
         if(direction == 1)
            signal.stop_loss = MathMin(capped_sl, signal.entry_price - structural_risk_floor);
         else
            signal.stop_loss = MathMax(capped_sl, signal.entry_price + structural_risk_floor);

         risk = MathAbs(signal.entry_price - signal.stop_loss);
         stop_basis += "+RISKCAP";
         Log(LOG_INFO, "GenerateKImanizSignal", symbol +
             " - KImaniz risk capped to " + DoubleToString(risk, digits) +
             " (" + DoubleToString(g_KImaniz_Max_Risk_ATR_Multiple, 2) + " ATR max)");
      }
   }

   double fallback_reward = MathMax(risk * g_Min_RR_Ratio, target_buffer * 2.0);
   double selected_target = SelectKImanizDirectionalTarget(direction, signal.entry_price,
                                                           best_ctx.tp_29, best_ctx.tp_41, target_buffer,
                                                           tp29_valid, tp41_valid, target_basis);
   if(target_basis == "RR_FALLBACK")
      signal.take_profit = signal.entry_price + direction * fallback_reward;
   else
      signal.take_profit = selected_target;

   bool buy_layout = (signal.stop_loss < signal.entry_price && signal.take_profit > signal.entry_price);
   bool sell_layout = (signal.stop_loss > signal.entry_price && signal.take_profit < signal.entry_price);
   if(direction == 1 && !buy_layout)
   {
      signal.take_profit = signal.entry_price + fallback_reward;
      target_basis = "RR_FALLBACK+LAYOUT";
   }
   else if(direction == -1 && !sell_layout)
   {
      signal.take_profit = signal.entry_price - fallback_reward;
      target_basis = "RR_FALLBACK+LAYOUT";
   }

   double reward = MathAbs(signal.take_profit - signal.entry_price);
   double rr = SafeDiv(reward, risk, 0.0);
   if(rr < g_Min_RR_Ratio)
   {
      // Enforce minimum RR when concentration target is too conservative.
      signal.take_profit = signal.entry_price + direction * (risk * g_Min_RR_Ratio);
      target_basis += "+MINRR";
      rr = g_Min_RR_Ratio;
   }
   else if(rr > kim_rr_cap)
   {
      signal.take_profit = signal.entry_price + direction * (risk * kim_rr_cap);
      target_basis += "+CAP";
      target_capped = true;
   }

   int levels_reason = TRADE_LEVELS_OK;
   if(!NormalizeAndValidateTradeLevels(symbol, trade_ctx,
                                       signal.entry_price, signal.stop_loss, signal.take_profit,
                                       levels_reason))
   {
      bool repairable_levels = (levels_reason != TRADE_LEVELS_NON_POSITIVE &&
                                levels_reason != TRADE_LEVELS_NON_NUMERIC &&
                                levels_reason != TRADE_LEVELS_SYMBOL_INDEX &&
                                levels_reason != TRADE_LEVELS_SYMBOL_CACHE);
      string repair_summary = "";
      bool repaired = false;
      if(repairable_levels)
      {
         repaired = RepairKImanizTradeLevels(symbol, direction, g_Min_RR_Ratio,
                                             signal.entry_price, signal.stop_loss, signal.take_profit, repair_summary);
      }

      if(!repaired)
      {
         signal.reason = "KImaniz levels invalid after normalization [" + TradeLevelsReasonLabel(levels_reason) + "]";
         return signal;
      }

      Log(LOG_INFO, "GenerateKImanizSignal", symbol +
          " - KImaniz levels repaired after normalization (" + repair_summary + ")");
   }

   bool final_buy_layout = (signal.stop_loss < signal.entry_price && signal.take_profit > signal.entry_price);
   bool final_sell_layout = (signal.stop_loss > signal.entry_price && signal.take_profit < signal.entry_price);
   if((direction == 1 && !final_buy_layout) || (direction == -1 && !final_sell_layout))
   {
      signal.reason = "KImaniz inversion guard: direction/layout mismatch";
      return signal;
   }

   double final_risk = MathAbs(signal.entry_price - signal.stop_loss);
   if(final_risk <= point)
   {
      signal.reason = "KImaniz risk invalid after normalization";
      return signal;
   }

   signal.risk_reward_ratio = CalculateTradeRiskRewardRatio(signal.entry_price, signal.stop_loss, signal.take_profit);
   if(signal.risk_reward_ratio < (g_Min_RR_Ratio - 0.01))
   {
      signal.reason = "KImaniz RR below minimum";
      return signal;
   }

   string mode_label = (signal.allow_countertrend_execution ? "CT" :
                        (signal.retracement_signal ? "RT" : "TA"));
   string zone_mode = (in_strict_otp_zone ? "STRICT" : (use_pending_entry ? "OTP" : "MARKET"));
   string exec_pref_tag = (use_pending_entry ? "PENDING" : "MARKET");
   signal.strategy_output_summary = StringFormat(
      "KIM[Mode=%s LB=%d Dist=%.2f%% Zone=%s FVG=%s RR=%.2f OTP=%.2f]",
      mode_label,
      best_ctx.lookback,
      best_ctx.zone_distance_pct,
      zone_mode,
      fvg_tf_tag,
      signal.risk_reward_ratio,
      best_ctx.otp_mid
   );
   signal.strategy_output_detail = StringFormat(
      "KIM[Mode=%s Dir=%s LB=%d Swing=%.2f OTP[%.2f,%.2f,%.2f] TP29=%.2f TP41=%.2f TP29v=%s TP41v=%s Stop=%s RiskFloor=%.2f TPBasis=%s RRCap=%.2f Cap=%s Dist=%.2f%% Zone=%s FVG=%s ATR=%.2f RR=%.2f]",
      mode_label,
      (direction == 1 ? "BUY" : "SELL"),
      best_ctx.lookback,
      best_ctx.swing_range,
      best_ctx.otp_low,
      best_ctx.otp_mid,
      best_ctx.otp_high,
      best_ctx.tp_29,
      best_ctx.tp_41,
      (tp29_valid ? "Y" : "N"),
      (tp41_valid ? "Y" : "N"),
      stop_basis,
      structural_risk_floor,
      target_basis,
      kim_rr_cap,
      (target_capped ? "Y" : "N"),
      best_ctx.zone_distance_pct,
      zone_mode,
      fvg_tf_tag,
      atr_value,
      signal.risk_reward_ratio
   );

   signal.valid = true;

   // Institutional scoring for KImaniz (directional probability from AI cache when available)
   if(Enable_All_Institutional_Filters)
   {
      double kim_ai_prob = GetDirectionalAIProbForScoring(symbol, symbol_index, signal.direction);
      int sig_struct_cache = DetectMarketStructure(symbol, Signal_TF);
      double mid_price_cache = current_price;
      int htf_bias_cache = ResolveHTFBiasForSignalPass(symbol,
                                                       has_seeded_trend_direction,
                                                       seeded_trend_direction);
      bool allow_kim_soft_precheck = (IsDirectionalRetracementSignal(signal) &&
                                      signal.allow_countertrend_execution);
      if(!ApplyScoringGate(symbol, Signal_TF, signal, kim_ai_prob, atr_value, htf_bias_cache, "KIM",
                           symbol_index, mid_price_cache, sig_struct_cache, allow_kim_soft_precheck))
         return signal;
   }

   if(!FinalizeStrategySignalBasics(symbol, signal, SIGNAL_ORIGIN_KIMANIZ, "KIM"))
      return signal;

   signal.reason = "KImaniz signal ready | " + signal.strategy_output_summary +
                   " | ExecPref=" + exec_pref_tag;
   LogTradeMessage(LOG_DEBUG, "GenerateKImanizSignal", symbol, "Candidate signal", BuildStrategyOutputSummary(signal, true));
   return signal;
}

#endif // KIMANIZ_STRATEGY_MQH
