#ifndef UTILS_MQH
#define UTILS_MQH

#ifndef STRATEGY_TF_SLOTS
#define STRATEGY_TF_SLOTS 4
#endif

double SafeDiv(double numerator, double denominator, double fallback)
{
   // Issue 1.3: FIXED - Check for invalid numbers first
   if(!MathIsValidNumber(numerator))
   {
      Log(LOG_WARNING, "SafeDiv", "Invalid numerator: " + DoubleToString(numerator, 2));
      return fallback;
   }
   
   if(!MathIsValidNumber(denominator))
   {
      Log(LOG_WARNING, "SafeDiv", "Invalid denominator: " + DoubleToString(denominator, 2));
      return fallback;
   }
   
   // CRITICAL FIX: Explicit zero check (handles -0.0, +0.0, and underflow)
   if(denominator == 0.0)
   {
      return fallback;
   }
   
   // Check denominator magnitude for underflow safety
   if(MathAbs(denominator) < 1e-10)
   {
      return fallback;
   }
   
   // Perform division with original denominator
   double result = numerator / denominator;
   
   // Verify result is valid - IMPROVED: Catch NaN more reliably
   if(!MathIsValidNumber(result) || result != result)  // NaN check (NaN != NaN)
   {
      Log(LOG_WARNING, "SafeDiv", "Division resulted in invalid/NaN number");
      return fallback;
   }
   
   // Check for overflow/underflow - IMPROVED: Handle subnormal numbers
   double abs_result = MathAbs(result);
   if(abs_result > 1e308 || (abs_result > 0 && abs_result < 1e-308))
   {
      Log(LOG_WARNING, "SafeDiv", "Division resulted in out-of-range number");
      return fallback;
   }
   
   return result;
}

double MathClamp(double value, double min_val, double max_val)
{
   if(!MathIsValidNumber(value)) return min_val;
   if(value < min_val) return min_val;
   if(value > max_val) return max_val;
   return value;
}

double SafeNormalize(double value, int digits)
{
   if(!MathIsValidNumber(value))
      return 0.0;
   return NormalizeDouble(value, digits);
}

double SafeNormalizeToTick(double value, int digits, double tick_size)
{
   if(!MathIsValidNumber(value) || tick_size <= 0)
      return SafeNormalize(value, digits);
   
   // First normalize to decimal places
   value = NormalizeDouble(value, digits);
   
   // Then round to nearest valid tick
   value = MathRound(value / tick_size) * tick_size;
   
   return NormalizeDouble(value, digits);
}

double GetPipSize(string symbol)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return 0.0;
   
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   int pip_points = (digits == 3 || digits == 5) ? 10 : 1;
   return point * pip_points;
}

int PipsToPoints(string symbol, double pips)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double pip_size = GetPipSize(symbol);
   if(point <= 0.0 || pip_size <= 0.0)
      return (int)MathRound(pips);
   
   return (int)MathRound(pips * (pip_size / point));
}

double PipsToPrice(string symbol, double pips)
{
   double pip_size = GetPipSize(symbol);
   if(pip_size <= 0.0)
      return 0.0;
   return pips * pip_size;
}

double PointsToPips(string symbol, double points)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double pip_size = GetPipSize(symbol);
   if(point <= 0.0 || pip_size <= 0.0)
      return points;
   
   return (points * point) / pip_size;
}

string SafeTruncateComment(string comment)
{
   const int MAX_COMMENT_LENGTH = 240;  // MQL5 limit is ~256, use buffer
   
   if(StringLen(comment) > MAX_COMMENT_LENGTH)
   {
      string truncated = StringSubstr(comment, 0, MAX_COMMENT_LENGTH - 3) + "...";
      Log(LOG_DEBUG, "SafeTruncateComment", 
          "Comment truncated from " + IntegerToString(StringLen(comment)) + 
          " to " + IntegerToString(StringLen(truncated)) + " chars");
      return truncated;
   }
   
   return comment;
}


SNormalizedPrices NormalizeTradePrices(double entry, double sl, double tp, int digits, double tick_size)
{
   SNormalizedPrices prices;
   prices.entry = SafeNormalizeToTick(entry, digits, tick_size);
   prices.stop_loss = SafeNormalizeToTick(sl, digits, tick_size);
   prices.take_profit = SafeNormalizeToTick(tp, digits, tick_size);
   return prices;
}

string MarketStructureToString(int structure)
{
   switch(structure)
   {
      case MARKET_BULLISH: return "BULLISH";
      case MARKET_BEARISH: return "BEARISH";
      case MARKET_RANGE:   return "RANGE";
      default:             return "RANGE";
   }
}

int StructureToDirection(int structure)
{
   switch(structure)
   {
      case MARKET_BULLISH: return 1;
      case MARKET_BEARISH: return -1;
      default:             return 0;
   }
}

double GetSymbolMidPrice(string symbol, double fallback_price = 0.0)
{
   MqlTick tick;
   if(SymbolInfoTick(symbol, tick))
   {
      if(tick.bid > 0.0 && tick.ask > 0.0)
         return (tick.bid + tick.ask) * 0.5;
      if(tick.last > 0.0)
         return tick.last;
      if(tick.bid > 0.0)
         return tick.bid;
      if(tick.ask > 0.0)
         return tick.ask;
   }
   return fallback_price;
}

double CalculateCloseSMA(const MqlRates &rates[], int shift, int period)
{
   if(period <= 0 || shift < 0)
      return 0.0;

   int needed = shift + period;
   if(ArraySize(rates) < needed)
      return 0.0;

   double close_sum = 0.0;
   for(int i = shift; i < shift + period; i++)
      close_sum += rates[i].close;

   return close_sum / (double)period;
}

bool DetectFairValueGap(string symbol, ENUM_TIMEFRAMES tf, int direction, double &fvg_high, double &fvg_low)
{
   fvg_high = 0.0;
   fvg_low = 0.0;

   if(direction != 1 && direction != -1)
      return false;

   if(!g_Use_FVG_Detection)
      return false;

   int lookback = MathMax(3, g_FVG_Lookback_Bars);
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, tf, 1, lookback + 3, rates);
   if(copied < 3)
      return false;

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = 0.00001;

   double atr_value = GetATRValue(symbol, tf);
   double min_gap = MathMax(point * 2.0,
                            (atr_value > 0.0 ? atr_value * g_Min_FVG_Size_Ratio : point * 10.0));
   int last_index = MathMin(copied - 3, lookback - 1);

   for(int i = 0; i <= last_index; i++)
   {
      MqlRates newest = rates[i];
      MqlRates middle = rates[i + 1];
      MqlRates oldest = rates[i + 2];

      if(direction == 1)
      {
         double gap_low = oldest.high;
         double gap_high = newest.low;
         double gap_size = gap_high - gap_low;
         if(gap_size >= min_gap &&
            newest.low > oldest.high &&
            middle.close >= middle.open)
         {
            fvg_high = gap_high;
            fvg_low = gap_low;
            return true;
         }
      }
      else
      {
         double gap_low = newest.high;
         double gap_high = oldest.low;
         double gap_size = gap_high - gap_low;
         if(gap_size >= min_gap &&
            newest.high < oldest.low &&
            middle.close <= middle.open)
         {
            fvg_high = gap_high;
            fvg_low = gap_low;
            return true;
         }
      }
   }

   return false;
}

bool DetectOrderBlock(string symbol, ENUM_TIMEFRAMES tf, int direction, double &ob_high, double &ob_low)
{
   ob_high = 0.0;
   ob_low = 0.0;

   if(direction != 1 && direction != -1)
      return false;

   int lookback = MathMax(10, g_Order_Block_Lookback);
   int confirm_bars = MathMax(1, g_Order_Block_Confirmation);
   int swing_range = MathMax(1, Order_Block_Swing_Range);

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, tf, 1, lookback + confirm_bars + swing_range + 2, rates);
   if(copied <= confirm_bars + 2)
      return false;

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = 0.00001;

   double atr_value = GetATRValue(symbol, tf);
   double min_zone_size = MathMax(point * 8.0,
                                  (atr_value > 0.0 ? atr_value * g_Min_Order_Block_Size : point * 20.0));
   double min_break = MathMax(point * 4.0,
                              (atr_value > 0.0 ? atr_value * 0.05 : point * 10.0));

   int oldest_candidate = copied - swing_range - 1;
   for(int candidate = confirm_bars; candidate < oldest_candidate; candidate++)
   {
      MqlRates block = rates[candidate];
      double zone_size = block.high - block.low;
      if(zone_size < min_zone_size)
         continue;

      bool opposite_candle = (direction == 1 ? block.close < block.open : block.close > block.open);
      if(!opposite_candle)
         continue;

      bool swing_ok = true;
      int left = MathMax(0, candidate - swing_range);
      int right = MathMin(copied - 1, candidate + swing_range);
      for(int k = left; k <= right; k++)
      {
         if(k == candidate)
            continue;

         if(direction == 1 && block.low > rates[k].low)
         {
            swing_ok = false;
            break;
         }
         if(direction == -1 && block.high < rates[k].high)
         {
            swing_ok = false;
            break;
         }
      }
      if(!swing_ok)
         continue;

      double impulse_extreme = (direction == 1 ? -1.0e100 : 1.0e100);
      for(int j = candidate - 1; j >= candidate - confirm_bars; j--)
      {
         if(direction == 1)
            impulse_extreme = MathMax(impulse_extreme, rates[j].high);
         else
            impulse_extreme = MathMin(impulse_extreme, rates[j].low);
      }

      bool confirmed = (direction == 1 ? impulse_extreme > (block.high + min_break)
                                       : impulse_extreme < (block.low - min_break));
      if(!confirmed)
         continue;

      ob_high = block.high;
      ob_low = block.low;
      return true;
   }

   return false;
}

bool IsInDiscountZone(string symbol, ENUM_TIMEFRAMES tf, int direction)
{
   if(direction != 1 && direction != -1)
      return false;

   int lookback = MathMax(12, MathMin(60, g_FVG_Lookback_Bars + 10));
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, tf, 1, lookback, rates);
   if(copied < 5)
      return false;

   double range_high = rates[0].high;
   double range_low = rates[0].low;
   for(int i = 1; i < copied; i++)
   {
      if(rates[i].high > range_high)
         range_high = rates[i].high;
      if(rates[i].low < range_low)
         range_low = rates[i].low;
   }

   if(range_high <= range_low)
      return false;

   double midpoint = (range_high + range_low) * 0.5;
   double fallback_price = rates[0].close;
   double current_price = GetSymbolMidPrice(symbol, fallback_price);

   if(direction == 1)
      return current_price <= midpoint;

   return current_price >= midpoint;
}

bool IsFirstRetracementAfterBOS(string symbol, ENUM_TIMEFRAMES tf, int direction)
{
   if(direction != 1 && direction != -1)
      return false;

   int lookback = MathMax(8, MathMin(40, g_Order_Block_Lookback / 4));
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, tf, 1, lookback + 6, rates);
   if(copied < 6)
      return false;

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = 0.00001;

   double atr_value = GetATRValue(symbol, tf);
   double min_break = MathMax(point * 4.0,
                              (atr_value > 0.0 ? atr_value * 0.08 : point * 12.0));
   double current_price = GetSymbolMidPrice(symbol, rates[0].close);
   if(current_price <= 0.0 || !MathIsValidNumber(current_price))
      current_price = rates[0].close;
   int swing_window = 3;

   for(int bos_index = 1; bos_index < copied - swing_window - 1; bos_index++)
   {
      MqlRates bos_candle = rates[bos_index];
      double prior_extreme = (direction == 1 ? -1.0e100 : 1.0e100);
      for(int k = bos_index + 1; k <= bos_index + swing_window; k++)
      {
         if(direction == 1)
            prior_extreme = MathMax(prior_extreme, rates[k].high);
         else
            prior_extreme = MathMin(prior_extreme, rates[k].low);
      }

      bool displacement = false;
      if(direction == 1)
      {
         displacement = (bos_candle.close > bos_candle.open &&
                         bos_candle.close > prior_extreme + min_break);
      }
      else
      {
         displacement = (bos_candle.close < bos_candle.open &&
                         bos_candle.close < prior_extreme - min_break);
      }
      if(!displacement)
         continue;

      double bos_range = bos_candle.high - bos_candle.low;
      if(bos_range <= point * 4.0)
         continue;

      double retrace_trigger = bos_range * 0.25;
      double recent_retrace = (direction == 1 ? bos_candle.high : bos_candle.low);
      for(int j = 0; j < bos_index; j++)
      {
         if(direction == 1)
            recent_retrace = MathMin(recent_retrace, rates[j].low);
         else
            recent_retrace = MathMax(recent_retrace, rates[j].high);
      }
      if(direction == 1)
         recent_retrace = MathMin(recent_retrace, current_price);
      else
         recent_retrace = MathMax(recent_retrace, current_price);

      if(direction == 1)
      {
         bool pulled_back = recent_retrace <= (bos_candle.high - retrace_trigger);
         bool not_invalidated = recent_retrace >= (bos_candle.low - min_break);
         if(pulled_back && not_invalidated)
            return true;
      }
      else
      {
         bool pulled_back = recent_retrace >= (bos_candle.low + retrace_trigger);
         bool not_invalidated = recent_retrace <= (bos_candle.high + min_break);
         if(pulled_back && not_invalidated)
            return true;
      }
   }

   return false;
}

bool IsMarketRanging(string symbol, string &reason)
{
   reason = "";

   int signal_structure = DetectMarketStructure(symbol, Signal_TF);
   int primary_structure = DetectMarketStructure(symbol, Primary_TF);
   int confirm_structure = DetectMarketStructure(symbol, Confirm_TF);
   int signal_direction = StructureToDirection(signal_structure);
   int primary_direction = StructureToDirection(primary_structure);
   int confirm_direction = StructureToDirection(confirm_structure);
   int htf_bias = GetHTFBias(symbol);

   if(signal_structure == MARKET_RANGE)
   {
      reason = "SignalTFRange";
      return true;
   }

   if(signal_direction == 0 && primary_direction == 0)
   {
      reason = "SignalPrimaryNeutral";
      return true;
   }

   bool lower_tf_conflict = (signal_direction != 0 && primary_direction != 0 && signal_direction != primary_direction);
   bool higher_tf_conflict = (signal_direction != 0 && confirm_direction != 0 && signal_direction != confirm_direction);
   bool weak_bias = (htf_bias == 0);
   // Treat sub-50 institutional strength as weak/non-trending context.
   bool weak_trend_context = (GetHTFBiasStrengthInstitutional(symbol) < 50.0);

   if(weak_trend_context && (weak_bias || lower_tf_conflict))
   {
      reason = (weak_bias ? "WeakHTFBias" : (lower_tf_conflict ? "SignalPrimaryConflict" : "SignalConfirmConflict"));
      return true;
   }

   return false;
}

int GetTrendDirection(string symbol)
{
   int htf_bias = GetHTFBias(symbol);
   if(htf_bias != 0)
      return htf_bias;

   int confirm_direction = StructureToDirection(DetectMarketStructure(symbol, Confirm_TF));
   int trend_direction = StructureToDirection(DetectMarketStructure(symbol, Trend_TF));

   if(confirm_direction != 0 && trend_direction != 0)
      return (confirm_direction == trend_direction ? confirm_direction : 0);

   if(confirm_direction != 0)
      return confirm_direction;

   return trend_direction;
}

void PrefillHTFBiasCaches(string symbol)
{
   if(StringLen(symbol) == 0)
      return;

   DetectMarketStructure(symbol, Signal_TF);
   DetectMarketStructure(symbol, Primary_TF);
   DetectMarketStructure(symbol, Confirm_TF);
   DetectMarketStructure(symbol, Trend_TF);
   GetHTFBias(symbol);
   GetHTFBiasScore(symbol);
}

ENUM_TIMEFRAMES GetStrategyTimeframeBySlot(const int slot)
{
   switch(slot)
   {
      case 0: return Signal_TF;
      case 1: return Primary_TF;
      case 2: return Confirm_TF;
      case 3: return Trend_TF;
      default: return PERIOD_CURRENT;
   }
}

int GetStrategyTimeframeSlot(const ENUM_TIMEFRAMES tf)
{
   for(int i = 0; i < STRATEGY_TF_SLOTS; i++)
   {
      if(GetStrategyTimeframeBySlot(i) == tf)
         return i;
   }
   return -1;
}

#endif // UTILS_MQH
