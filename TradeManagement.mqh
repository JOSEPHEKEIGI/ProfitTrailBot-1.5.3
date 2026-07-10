#ifndef TRADE_MANAGEMENT_MQH
#define TRADE_MANAGEMENT_MQH

// Some builds may not expose SYMBOL_FILLING_RETURN; define if missing
#ifndef SYMBOL_FILLING_RETURN
   #define SYMBOL_FILLING_RETURN 4
#endif

// TradeManagement is included before StrategyRouter in the main compile unit.
// Keep guarded fallback definitions here to avoid include-order dependency.
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

#ifndef SIGNAL_EXEC_PREF_AUTO
   #define SIGNAL_EXEC_PREF_AUTO    0
#endif
#ifndef SIGNAL_EXEC_PREF_MARKET
   #define SIGNAL_EXEC_PREF_MARKET  1
#endif
#ifndef SIGNAL_EXEC_PREF_PENDING
   #define SIGNAL_EXEC_PREF_PENDING 2
#endif

// Minimal extern declarations for variables used in this file
extern bool g_Disable_All_Gates;
extern bool g_Enable_Exposure_Gates;

inline bool ExposureGateOn() { return g_Enable_Exposure_Gates; }

//====================================================================
// Issue 3.12: Trade Execution with Slippage Validation
//====================================================================
ENUM_ORDER_TYPE_FILLING GetSymbolFillingMode(string symbol)
{
   long mode = 0;
   if(!SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE, mode))
      return ORDER_FILLING_RETURN;
   
   // Direct enum match
   if(mode == ORDER_FILLING_FOK || mode == ORDER_FILLING_IOC || mode == ORDER_FILLING_RETURN)
      return (ENUM_ORDER_TYPE_FILLING)mode;
   
   // Bitmask match (ENUM_SYMBOL_FILLING)
   if((mode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;
   if((mode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;
   if((mode & SYMBOL_FILLING_RETURN) == SYMBOL_FILLING_RETURN)
      return ORDER_FILLING_RETURN;
   
   return ORDER_FILLING_RETURN;
}

string FillModeToString(ENUM_ORDER_TYPE_FILLING mode)
{
   switch(mode)
   {
      case ORDER_FILLING_FOK:    return "FOK";
      case ORDER_FILLING_IOC:    return "IOC";
      case ORDER_FILLING_RETURN: return "RETURN";
      default:                   return "UNKNOWN(" + IntegerToString((int)mode) + ")";
   }
}

bool IsFillModeSupportedBySymbol(string symbol, ENUM_ORDER_TYPE_FILLING mode)
{
   long supported = 0;
   if(!SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE, supported))
      return (mode == ORDER_FILLING_RETURN);

   if(supported == mode)
      return true;

   if(mode == ORDER_FILLING_FOK)
      return ((supported & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK);
   if(mode == ORDER_FILLING_IOC)
      return ((supported & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC);
   if(mode == ORDER_FILLING_RETURN)
      return ((supported & SYMBOL_FILLING_RETURN) == SYMBOL_FILLING_RETURN);

   return false;
}

double ComputePendingEntryGuardBuffer(string symbol,
                                      double point,
                                      double tick_size,
                                      double bid,
                                      double ask,
                                      double slippage_pips)
{
   double unit = MathMax(point, tick_size);
   if(unit <= 0.0)
      unit = point;
   if(unit <= 0.0)
      unit = 0.00001;

   double buffer = unit * 3.0;
   double spread = (bid > 0.0 && ask > bid ? ask - bid : 0.0);
   if(spread > 0.0)
      buffer = MathMax(buffer, spread * 0.60);

   double slippage_buffer = PipsToPrice(symbol, MathMax(0.0, slippage_pips));
   if(slippage_buffer > 0.0)
      buffer = MathMax(buffer, slippage_buffer);

   return buffer;
}

string GetSignalOriginTag(ENUM_SIGNAL_ORIGIN origin)
{
   switch(origin)
   {
      case SIGNAL_ORIGIN_ICT:  return "ICT";
      case SIGNAL_ORIGIN_AI:   return "AI";
      case SIGNAL_ORIGIN_BOTH: return "BOTH";
      case SIGNAL_ORIGIN_KIMANIZ: return "KIM";
      default:                 return "UNK";
   }
}

string GetCompactSignalOriginTag(ENUM_SIGNAL_ORIGIN origin)
{
   switch(origin)
   {
      case SIGNAL_ORIGIN_ICT:     return "I";
      case SIGNAL_ORIGIN_AI:      return "A";
      case SIGNAL_ORIGIN_BOTH:    return "B";
      case SIGNAL_ORIGIN_KIMANIZ: return "K";
      default:                    return "U";
   }
}

string GetCompactExecutionBiasTag(const STradingSignal &signal)
{
   if(IsCountertrendRetracementSignal(signal))
      return "C";
   return "";
}

bool CommentHasCountertrendExecutionTag(string comment)
{
   if(StringLen(comment) <= 0)
      return false;
   return (StringFind(comment, "|C|F=") >= 0);
}

double ExtractTaggedNumericValue(string source, string tag, double fallback)
{
   int pos = StringFind(source, tag);
   if(pos < 0)
      return fallback;

   int start = pos + StringLen(tag);
   int len = StringLen(source);
   if(start >= len)
      return fallback;

   int end = start;
   while(end < len)
   {
      int ch = StringGetCharacter(source, end);
      bool is_digit = (ch >= 48 && ch <= 57);
      bool is_numeric_char = (is_digit || ch == 45 || ch == 46);
      if(!is_numeric_char)
         break;
      end++;
   }

   if(end <= start)
   {
      Log(LOG_DEBUG, "ExtractTaggedNumericValue", "Failed to extract " + tag + "; using fallback=" + DoubleToString(fallback, 8));
      return fallback;
   }

   string numeric = StringSubstr(source, start, end - start);
   double value = StringToDouble(numeric);
   if(!MathIsValidNumber(value))
   {
      Log(LOG_WARNING, "ExtractTaggedNumericValue", "Invalid numeric \"" + numeric + "\" for tag " + tag + "; falling back to " + DoubleToString(fallback, 8));
      return fallback;
   }
   
   // MEDIUM FIX: Validate extracted value is within reasonable trading range
   // Most lot multipliers/delays should be in range [0.01, 100] or [-1, large number]
   if(tag == "DirectorLotMult=" && (value < 0.01 || value > 100.0))
   {
      Log(LOG_WARNING, "ExtractTaggedNumericValue", "Lot multiplier " + DoubleToString(value, 2) + " out of range [0.01, 100]; using fallback");
      return fallback;
   }
   if(tag == "NewsMult=" && (value <= 0.0 || value > 5.0))
   {
      Log(LOG_WARNING, "ExtractTaggedNumericValue", "News multiplier " + DoubleToString(value, 2) + " out of range; using fallback");
      return fallback;
   }
   if(tag == "PendingExpiryMin=" && value >= 0 && value > 1440)  // More than 1 day
   {
      Log(LOG_WARNING, "ExtractTaggedNumericValue", "Pending expiry " + DoubleToString(value, 0) + " minutes > 1 day; clamping to 1440");
      return 1440.0;
   }

   return value;
}

// Normalize volume to broker constraints to avoid invalid volume retcodes.
// CRITICAL FIX #1: Use MathRound instead of MathFloor for proper floating-point handling
bool NormalizeLotToBroker(string symbol, double &lot, string &reason)
{
   reason = "";
   double requested_lot = lot;
   double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(min_lot <= 0.0 || max_lot <= 0.0 || lot_step <= 0.0)
   {
      reason = "invalid_volume_params";
      return false;
   }

   if(!MathIsValidNumber(lot) || lot <= 0.0)
   {
      reason = "invalid_lot";
      return false;
   }

   // CRITICAL FIX: Use proper rounding with epsilon tolerance
   const double EPSILON = 1e-10;  // Floating point tolerance
   
   // Round to nearest valid step (not floor)
   double steps = requested_lot / lot_step;
   double rounded_steps = MathRound(steps);  // Round to nearest
   double normalized = rounded_steps * lot_step;
   
   // Clamp to valid range
   if(normalized < min_lot - EPSILON)
   {
      normalized = min_lot;  // Round up to minimum
   }
   if(normalized > max_lot + EPSILON)
   {
      normalized = max_lot;  // Round down to maximum
   }

   if(!MathIsValidNumber(normalized) || normalized <= 0.0)
   {
      reason = "invalid_normalized_lot";
      return false;
   }

   // Check if final lot is too far from requested (> 1 step)
   double difference = MathAbs(requested_lot - normalized);
   if(difference > lot_step + EPSILON)
   {
      reason = StringFormat("Lot adjustment too large: %.2f to %.2f (%.2f step)",
                            lot, normalized, lot_step);
      return false;  // Reject if it changes too much
   }

   lot = normalized;
   
   // Log significant changes. Tiny floating-point step alignment is routine,
   // so keep it out of WARN-level operational logs.
   if(difference > EPSILON)
   {
      ENUM_LOG_LEVEL normalization_level = (difference >= lot_step * 0.1 ? LOG_WARNING : LOG_DEBUG);
      Log(normalization_level, "NormalizeLotToBroker",
          StringFormat("Normalized %.6f -> %.6f (%s, step %.6f)",
                       requested_lot, normalized, symbol, lot_step));
   }

   return true;
}

bool EnforceFinalPerTradeRiskCap(string symbol,
                                 int direction,
                                 double entry_price,
                                 double sl_price,
                                 double &lot,
                                 string context)
{
   double risk_base = GetRiskBaseValue();
   if(risk_base <= 0.0)
   {
      RecordRejectReason("RETRY:FinalRiskCapInvalidBase");
      Log(LOG_WARNING, context, symbol + " - Invalid account base for final per-trade risk cap");
      return false;
   }

   double max_per_trade_pct = g_Final_Per_Trade_Risk_Cap_Pct;
   if(max_per_trade_pct <= 0.0)
      return true;

   max_per_trade_pct = MathMin(max_per_trade_pct, 100.0);
   double max_trade_risk = risk_base * max_per_trade_pct / 100.0;
   double trade_risk = CalculateTradeRiskCurrency(symbol, direction, lot, entry_price, sl_price);
   if(trade_risk <= 0.0 || !MathIsValidNumber(trade_risk))
   {
      RecordRejectReason("RETRY:FinalRiskCapCalcFailed");
      Log(LOG_WARNING, context, symbol + " - Unable to calculate final per-trade risk");
      return false;
   }

   if(trade_risk <= max_trade_risk)
      return true;

   double adjusted_lot = lot * SafeDiv(max_trade_risk, trade_risk, 0.0);
   double requested_adjusted_lot = adjusted_lot;
   string normalize_reason = "";
   if(!NormalizeLotToBroker(symbol, adjusted_lot, normalize_reason))
   {
      RecordRejectReason("RETRY:FinalRiskCapNormalizeFailed_" + normalize_reason);
      Log(LOG_WARNING, context, symbol +
          " - Final per-trade risk cap cannot normalize reduced lot: " + normalize_reason);
      return false;
   }

   double adjusted_risk = CalculateTradeRiskCurrency(symbol, direction, adjusted_lot, entry_price, sl_price);
   if(adjusted_risk > max_trade_risk)
   {
      double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double min_lot_risk_pct = SafeDiv(adjusted_risk, risk_base, 0.0) * 100.0;
      double required_risk_base = SafeDiv(adjusted_risk * 100.0, max_per_trade_pct, 0.0);
      RecordRejectReason("RETRY:FinalRiskCapMinLotOverrisk");
      Log(LOG_WARNING, context,
          StringFormat("%s - Minimum/normalized lot still exceeds final per-trade cap: $%.2f > $%.2f (%.1f%% cap; min-lot risk %.1f%%) | required lot %.4f, normalized %.4f, broker min %.4f, risk base needed $%.2f",
                       symbol, adjusted_risk, max_trade_risk, max_per_trade_pct,
                       min_lot_risk_pct, requested_adjusted_lot, adjusted_lot, min_lot, required_risk_base));
      return false;
   }

   Log(LOG_WARNING, context,
       StringFormat("%s - Final per-trade risk cap reduced lot %.4f -> %.4f ($%.2f -> $%.2f, %.1f%% max)",
                    symbol, lot, adjusted_lot, trade_risk, adjusted_risk, max_per_trade_pct));
   lot = adjusted_lot;
   return true;
}

//====================================================================
// CRITICAL FIX #5: Position Tracker with Dynamic Array Allocation
//====================================================================
class PositionTracker
{
private:
   ulong pos_ids[];
   double pos_pnl[];
   int pos_count;
   int max_capacity;
   static const int INITIAL_CAPACITY;
   static const int GROWTH_FACTOR;  // Double size when needed

public:
   PositionTracker()
   {
      max_capacity = INITIAL_CAPACITY;
      pos_count = 0;
      ArrayResize(pos_ids, max_capacity);
      ArrayResize(pos_pnl, max_capacity);
   }

   ~PositionTracker()
   {
      ArrayFree(pos_ids);
      ArrayFree(pos_pnl);
   }

   // Add a new position
   bool AddPosition(ulong ticket, double pnl)
   {
      // CRITICAL FIX: Auto-grow array if needed
      if(pos_count >= max_capacity)
      {
         int new_capacity = max_capacity * GROWTH_FACTOR;

         if(!ArrayResize(pos_ids, new_capacity))
         {
            Log(LOG_ERROR, "PositionTracker::AddPosition",
                StringFormat("CRITICAL: Failed to grow position array to %d", new_capacity));
            return false;
         }
         if(!ArrayResize(pos_pnl, new_capacity))
         {
            Log(LOG_ERROR, "PositionTracker::AddPosition",
                StringFormat("CRITICAL: Failed to grow PnL array to %d", new_capacity));
            return false;
         }

         max_capacity = new_capacity;
         Log(LOG_WARNING, "PositionTracker::AddPosition",
             StringFormat("Grew position array: %d → %d", max_capacity/GROWTH_FACTOR, max_capacity));
      }

      // Add to end
      pos_ids[pos_count] = ticket;
      pos_pnl[pos_count] = pnl;
      pos_count++;

      return true;
   }

   // Get position by index
   bool GetPosition(int index, ulong &ticket, double &pnl)
   {
      if(index < 0 || index >= pos_count)
         return false;

      ticket = pos_ids[index];
      pnl = pos_pnl[index];
      return true;
   }

   // Remove position by index
   bool RemovePosition(int index)
   {
      if(index < 0 || index >= pos_count)
         return false;

      // Shift all positions after this one back by 1
      for(int i = index; i < pos_count - 1; i++)
      {
         pos_ids[i] = pos_ids[i + 1];
         pos_pnl[i] = pos_pnl[i + 1];
      }

      pos_count--;
      return true;
   }

   // Get total count
   int GetCount() { return pos_count; }

   // Get total PnL
   double GetTotalPnL()
   {
      double total = 0;
      for(int i = 0; i < pos_count; i++)
         total += pos_pnl[i];
      return total;
   }

   // Clear all
   void Clear()
   {
      pos_count = 0;
      // Reset all values
      for(int i = 0; i < max_capacity; i++)
      {
         pos_ids[i] = 0;
         pos_pnl[i] = 0.0;
      }
   }
};

// Static member definitions
const int PositionTracker::INITIAL_CAPACITY = 32;
const int PositionTracker::GROWTH_FACTOR = 2;

// Global instance
static PositionTracker g_position_tracker;

// Check if a position (by identifier) is still open to avoid double-counting partial closes.
bool IsPositionIdentifierOpen(ulong position_id)
{
   if(position_id == 0)
      return false;
   
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(identifier == position_id)
         return true;
   }
   return false;
}

bool BuildAggregatedPositionCloseNet(ulong position_id, double deal_net, double &aggregated_net)
{
   aggregated_net = deal_net;

   static ulong agg_pos_ids[256];
   static double agg_pos_pnl[256];
   static int agg_count = 0;

   if(position_id == 0)
      return true;

   int idx = -1;
   for(int i = 0; i < agg_count; i++)
   {
      if(agg_pos_ids[i] == position_id)
      {
         idx = i;
         break;
      }
   }

   if(idx < 0)
   {
      if(agg_count >= 256)
      {
         idx = 0; // evict oldest to preserve bounded memory
         agg_pos_ids[idx] = position_id;
         agg_pos_pnl[idx] = 0.0;
      }
      else
      {
         idx = agg_count++;
         agg_pos_ids[idx] = position_id;
         agg_pos_pnl[idx] = 0.0;
      }
   }

   agg_pos_pnl[idx] += deal_net;
   aggregated_net = agg_pos_pnl[idx];

   if(IsPositionIdentifierOpen(position_id))
      return false;

   int last = agg_count - 1;
   if(last >= 0 && idx != last)
   {
      agg_pos_ids[idx] = agg_pos_ids[last];
      agg_pos_pnl[idx] = agg_pos_pnl[last];
   }
   if(agg_count > 0)
      agg_count--;

   return true;
}

// Tier 3B: Backtesting metrics update on trade close (aggregates partial closes).
bool UpdateBacktestMetricsOnClose(const string symbol, datetime deal_time, ulong position_id, double deal_net,
                                  double &aggregated_net)
{
   bool final_close = BuildAggregatedPositionCloseNet(position_id, deal_net, aggregated_net);
   if(!Enable_Backtesting_Framework)
      return final_close;
    
   static bool initialized = false;
   static SBacktestPeriod all_period;
   static SWalkForwardSplit split;
   static int oos_trade_count = 0;
   static int stats_interval = 0;
    
   if(stats_interval <= 0)
   {
      stats_interval = Backtest_Min_Trades_For_Stats;
      if(stats_interval < 1)
         stats_interval = 0;
      else if(stats_interval < 5)
         stats_interval = 5;
   }
   
   if(!initialized)
   {
      all_period.period_start = deal_time;
      all_period.period_label = "ALL";
      initialized = true;
      
      if(Backtest_IS_Days > 0 && Backtest_OOS_Days > 0)
      {
         split.is_start = deal_time;
         split.is_end = deal_time + (datetime)(Backtest_IS_Days * 86400);
         split.oos_start = split.is_end;
         split.oos_end = split.oos_start + (datetime)(Backtest_OOS_Days * 86400);
         
         split.is_results.period_start = split.is_start;
         split.is_results.period_end = split.is_end;
         split.is_results.period_label = "IS_" + TimeToString(split.is_start, TIME_DATE) +
                                         "-" + TimeToString(split.is_end, TIME_DATE);
         
         split.oos_results.period_start = split.oos_start;
         split.oos_results.period_end = split.oos_end;
         split.oos_results.period_label = "OOS_" + TimeToString(split.oos_start, TIME_DATE) +
                                          "-" + TimeToString(split.oos_end, TIME_DATE);
      }
   }
    
   if(!final_close)
      return false;
    
   bool is_win = (aggregated_net > 0.0);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double return_value = (balance > 0.0 ? aggregated_net / balance : aggregated_net);
   
   all_period.period_end = deal_time;
   CBacktestingFramework::RecordTradeForBacktest(all_period, aggregated_net, is_win, return_value);
   
   if(stats_interval > 0 && (all_period.total_trades % stats_interval) == 0)
   {
      Log(LOG_INFO, "BacktestMetrics",
          symbol + " - ALL: Trades=" + IntegerToString(all_period.total_trades) +
          " WR=" + DoubleToString(all_period.win_rate * 100, 1) + "%" +
          " PF=" + DoubleToString(all_period.profit_factor, 2) +
          " Sharpe=" + DoubleToString(all_period.sharpe_ratio, 2) +
          " MaxDD=" + DoubleToString(all_period.max_drawdown, 2));
   }
   
   if(split.is_end > 0)
   {
      if(deal_time <= split.is_end)
      {
         split.is_results.period_end = deal_time;
         CBacktestingFramework::RecordTradeForBacktest(split.is_results, aggregated_net, is_win, return_value);
      }
      else
      {
         if(deal_time > split.oos_end)
            split.oos_end = deal_time;
         split.oos_results.period_end = deal_time;
         CBacktestingFramework::RecordTradeForBacktest(split.oos_results, aggregated_net, is_win, return_value);
         oos_trade_count++;
         
         if(stats_interval > 0 &&
            (oos_trade_count % stats_interval) == 0 &&
            split.is_results.total_trades >= stats_interval)
         {
            CBacktestingFramework::EvaluateWalkForwardDegradation(split);
         }
      }
   }

   return true;
}

int ExtractAutoModeFromSignalReason(string reason)
{
   if(StringFind(reason, "AutoRegime=TREND") >= 0 ||
      StringFind(reason, "SuitabilityRole=TREND") >= 0)
      return AUTO_REGIME_MODE_TREND_ALIGNED;

   if(StringFind(reason, "AutoRegime=RANGE") >= 0 ||
      StringFind(reason, "SuitabilityRole=RANGE") >= 0)
      return AUTO_REGIME_MODE_INTRA_HIGHLOW;

   if(StringFind(reason, "AutoRegime=RETRACEMENT") >= 0 ||
      StringFind(reason, "SuitabilityRole=RETRACEMENT") >= 0)
      return AUTO_REGIME_MODE_RETRACEMENT;

   return AUTO_REGIME_MODE_DISABLED;
}

int ExtractExecutionPreferenceFromSignalReason(string reason)
{
   if(StringFind(reason, "ExecPref=MARKET") >= 0)
      return SIGNAL_EXEC_PREF_MARKET;
   if(StringFind(reason, "ExecPref=PENDING") >= 0)
      return SIGNAL_EXEC_PREF_PENDING;
   return SIGNAL_EXEC_PREF_AUTO;
}

int ExtractDirectorStrategyModeFromSignal(const STradingSignal &signal)
{
   if(StringFind(signal.reason, "DirectorStrategy=KIMANIQ_RANGE") >= 0)
      return (int)DIRECTOR_STRATEGY_KIMANIQ_RANGE;
   if(StringFind(signal.reason, "DirectorStrategy=AI_TREND") >= 0)
      return (int)DIRECTOR_STRATEGY_AI_TREND;
   if(StringFind(signal.reason, "DirectorStrategy=ICT_RETRACEMENT") >= 0)
      return (int)DIRECTOR_STRATEGY_ICT_RETRACEMENT;

   if(signal.origin == SIGNAL_ORIGIN_KIMANIZ)
      return (int)DIRECTOR_STRATEGY_KIMANIQ_RANGE;
   if(signal.origin == SIGNAL_ORIGIN_AI)
      return (int)DIRECTOR_STRATEGY_AI_TREND;
   if(signal.origin == SIGNAL_ORIGIN_ICT || signal.origin == SIGNAL_ORIGIN_BOTH)
      return (int)DIRECTOR_STRATEGY_ICT_RETRACEMENT;

   return -1;
}

int PendingOrderDirectionFromType(long order_type)
{
   if(order_type == ORDER_TYPE_BUY_LIMIT || order_type == ORDER_TYPE_BUY_STOP || order_type == ORDER_TYPE_BUY_STOP_LIMIT)
      return 1;
   if(order_type == ORDER_TYPE_SELL_LIMIT || order_type == ORDER_TYPE_SELL_STOP || order_type == ORDER_TYPE_SELL_STOP_LIMIT)
      return -1;
   return 0;
}

bool IsForwardOnlySLTP(ENUM_POSITION_TYPE position_type, double current_sl, double current_tp,
                       double new_sl, double new_tp, double eps)
{
   if(current_sl > 0.0)
   {
      if(new_sl <= 0.0)
         return false; // removing SL is a drawdown move
      if(position_type == POSITION_TYPE_BUY && new_sl < current_sl - eps)
         return false;
      if(position_type == POSITION_TYPE_SELL && new_sl > current_sl + eps)
         return false;
   }

   if(current_tp > 0.0)
   {
      if(new_tp <= 0.0)
         return false; // removing TP is a drawdown move
      if(position_type == POSITION_TYPE_BUY && new_tp < current_tp - eps)
         return false;
      if(position_type == POSITION_TYPE_SELL && new_tp > current_tp + eps)
         return false;
   }

   return true;
}

bool IsSuccessfulTradeRetcode(int retcode, bool is_pending_order);

// Track tickets that have already had a partial close to prevent repeated reductions.
// Position comments are broker-controlled and cannot be relied on for this state.
#define MAX_PARTIAL_CLOSE_TRACK 1024
static ulong g_partial_close_tickets[MAX_PARTIAL_CLOSE_TRACK];
static int g_partial_close_ticket_count = 0;

// Track per-position peak floating profit to enforce drawdown-from-peak exits.
#define MAX_PEAK_PROFIT_TRACK 1024
static ulong g_peak_profit_tickets[MAX_PEAK_PROFIT_TRACK];
static double g_peak_profit_values[MAX_PEAK_PROFIT_TRACK];
static int g_peak_profit_count = 0;

void CompactPeakProfitTracker()
{
   if(g_peak_profit_count <= 0)
      return;

   int write_idx = 0;
   for(int i = 0; i < g_peak_profit_count; i++)
   {
      ulong ticket = g_peak_profit_tickets[i];
      if(ticket == 0)
         continue;
      if(PositionSelectByTicket(ticket))
      {
         g_peak_profit_tickets[write_idx] = ticket;
         g_peak_profit_values[write_idx] = g_peak_profit_values[i];
         write_idx++;
      }
   }

   for(int i = write_idx; i < g_peak_profit_count; i++)
   {
      g_peak_profit_tickets[i] = 0;
      g_peak_profit_values[i] = 0.0;
   }
   g_peak_profit_count = write_idx;
}

int FindPeakProfitIndex(ulong ticket)
{
   if(ticket == 0)
      return -1;
   for(int i = 0; i < g_peak_profit_count; i++)
   {
      if(g_peak_profit_tickets[i] == ticket)
         return i;
   }
   return -1;
}

double UpdateAndGetPeakProfit(ulong ticket, double current_profit)
{
   if(ticket == 0)
      return 0.0;

   int idx = FindPeakProfitIndex(ticket);
   if(current_profit <= 0.0)
      return (idx >= 0 ? g_peak_profit_values[idx] : 0.0);

   if(idx < 0)
   {
      if(g_peak_profit_count >= MAX_PEAK_PROFIT_TRACK)
         CompactPeakProfitTracker();
      if(g_peak_profit_count >= MAX_PEAK_PROFIT_TRACK)
      {
         for(int i = 1; i < MAX_PEAK_PROFIT_TRACK; i++)
         {
            g_peak_profit_tickets[i - 1] = g_peak_profit_tickets[i];
            g_peak_profit_values[i - 1] = g_peak_profit_values[i];
         }
         g_peak_profit_count = MAX_PEAK_PROFIT_TRACK - 1;
      }
      idx = g_peak_profit_count++;
      g_peak_profit_tickets[idx] = ticket;
      g_peak_profit_values[idx] = current_profit;
      return current_profit;
   }

   if(current_profit > g_peak_profit_values[idx])
      g_peak_profit_values[idx] = current_profit;
   return g_peak_profit_values[idx];
}

bool CalculateStopPriceForTargetProfit(string symbol,
                                       ENUM_POSITION_TYPE position_type,
                                       double volume,
                                       double entry_price,
                                       double current_price,
                                       double target_profit,
                                       double &stop_price)
{
   stop_price = 0.0;

   if(symbol == "" || volume <= 0.0 || entry_price <= 0.0 || current_price <= 0.0)
      return false;
   if(!MathIsValidNumber(target_profit))
      return false;

   if(target_profit <= 0.0)
   {
      stop_price = entry_price;
      return true;
   }

   ENUM_ORDER_TYPE calc_type = ORDER_TYPE_BUY;
   if(position_type == POSITION_TYPE_SELL)
      calc_type = ORDER_TYPE_SELL;
   double low = 0.0;
   double high = 0.0;

   if(position_type == POSITION_TYPE_BUY)
   {
      if(current_price <= entry_price)
         return false;
      low = entry_price;
      high = current_price;
   }
   else
   {
      if(current_price >= entry_price)
         return false;
      low = current_price;
      high = entry_price;
   }

   for(int step = 0; step < 40; step++)
   {
      double mid = (low + high) * 0.5;
      double mid_profit = 0.0;
      if(!OrderCalcProfit(calc_type, symbol, volume, entry_price, mid, mid_profit))
         return false;
      if(!MathIsValidNumber(mid_profit))
         return false;

      if(position_type == POSITION_TYPE_BUY)
      {
         if(mid_profit >= target_profit)
            high = mid;
         else
            low = mid;
      }
      else
      {
         if(mid_profit >= target_profit)
            low = mid;
         else
            high = mid;
      }
   }

   stop_price = (position_type == POSITION_TYPE_BUY ? high : low);
   return (stop_price > 0.0 && MathIsValidNumber(stop_price));
}

bool ApplyPeakDrawdownSLProtection(ulong ticket,
                                   string position_symbol,
                                   ENUM_POSITION_TYPE position_type,
                                   double position_volume,
                                   double position_open,
                                   double &position_sl,
                                   double position_tp,
                                   double current_price,
                                   double current_profit,
                                   double peak_profit,
                                   int digits,
                                   double point,
                                   double spread_points,
                                   double min_move_price)
{
   if(g_MaxAcceptableDrawdown <= 0.0 || peak_profit <= 0.0)
      return false;
   if(position_symbol == "" || position_volume <= 0.0 || position_open <= 0.0 ||
      current_price <= 0.0 || point <= 0.0)
      return false;
   if(!MathIsValidNumber(current_profit) || !MathIsValidNumber(peak_profit))
      return false;

   double peak_drawdown = peak_profit - current_profit;
   if(peak_drawdown < g_MaxAcceptableDrawdown)
      return false;

   double protected_profit = MathMax(0.0, peak_profit - g_MaxAcceptableDrawdown);
   double target_lock_profit = MathMax(0.0, MathMin(protected_profit, current_profit));
   double desired_sl = 0.0;

   if(!CalculateStopPriceForTargetProfit(position_symbol, position_type, position_volume,
                                         position_open, current_price, target_lock_profit,
                                         desired_sl))
      return false;

   double sltp_eps = point * 2.0;
   if(g_Peak_Drawdown_SL_Protect_Entry)
   {
      if(position_type == POSITION_TYPE_BUY)
         desired_sl = MathMax(desired_sl, position_open);
      else
         desired_sl = MathMin(desired_sl, position_open);
   }

   long stops_level = SymbolInfoInteger(position_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level = SymbolInfoInteger(position_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double required_gap_points = (double)stops_level;
   if(freeze_level > stops_level)
      required_gap_points = (double)freeze_level;
   if(spread_points > required_gap_points)
      required_gap_points = spread_points;
   double broker_gap = MathMax(required_gap_points * point, point * 2.0);

   if(position_type == POSITION_TYPE_BUY)
   {
      double max_allowed_sl = current_price - broker_gap;
      if(desired_sl > max_allowed_sl)
         desired_sl = max_allowed_sl;

      desired_sl = NormalizeDouble(desired_sl, digits);
      if(g_Peak_Drawdown_SL_Protect_Entry && desired_sl < position_open - sltp_eps)
      {
         Log(LOG_DEBUG, "ApplyPeakDrawdownSLProtection",
             position_symbol + " - Peak drawdown SL lock skipped: broker stop distance would move BUY SL below entry");
         return false;
      }
      if(desired_sl <= 0.0 || desired_sl >= current_price - sltp_eps)
         return false;
      if(position_sl > 0.0 && desired_sl <= position_sl + sltp_eps)
         return false;
   }
   else
   {
      double min_allowed_sl = current_price + broker_gap;
      if(desired_sl < min_allowed_sl)
         desired_sl = min_allowed_sl;

      desired_sl = NormalizeDouble(desired_sl, digits);
      if(g_Peak_Drawdown_SL_Protect_Entry && desired_sl > position_open + sltp_eps)
      {
         Log(LOG_DEBUG, "ApplyPeakDrawdownSLProtection",
             position_symbol + " - Peak drawdown SL lock skipped: broker stop distance would move SELL SL above entry");
         return false;
      }
      if(desired_sl <= current_price + sltp_eps)
         return false;
      if(position_sl > 0.0 && desired_sl >= position_sl - sltp_eps)
         return false;
   }

   if(position_sl > 0.0 && MathAbs(desired_sl - position_sl) <= min_move_price)
      return false;

   if(!IsForwardOnlySLTP(position_type, position_sl, position_tp, desired_sl, position_tp, sltp_eps))
   {
      Log(LOG_WARNING, "ApplyPeakDrawdownSLProtection",
          position_symbol + " - Peak drawdown SL lock blocked (non-forward move)");
      return false;
   }

   bool modify_request_ok = trade.PositionModify(ticket, desired_sl, position_tp);
   int modify_retcode = (int)trade.ResultRetcode();
   bool modify_ok = (modify_request_ok && IsSuccessfulTradeRetcode(modify_retcode, false));
   if(modify_ok)
   {
      string msg = StringFormat("%s - Peak drawdown SL lock: drawdown $%.2f >= $%.2f, peak $%.2f, current $%.2f, protected $%.2f, SL %.5f",
                                position_symbol, peak_drawdown, g_MaxAcceptableDrawdown,
                                peak_profit, current_profit, target_lock_profit, desired_sl);
      Log(LOG_INFO, "ApplyPeakDrawdownSLProtection", msg);
      SendAlert(ALERT_RISK_CONTROL, msg);
      AuditLog("PEAK_DD_SL_LOCK", position_symbol, msg);
      position_sl = desired_sl;
      return true;
   }

   Log(LOG_WARNING, "ApplyPeakDrawdownSLProtection",
       position_symbol + " - Peak drawdown SL lock failed (retcode=" +
       IntegerToString(modify_retcode) + ", " + trade.ResultRetcodeDescription() + ")");
   return false;
}

void ClearPeakProfit(ulong ticket)
{
   int idx = FindPeakProfitIndex(ticket);
   if(idx < 0)
      return;
   g_peak_profit_tickets[idx] = 0;
   g_peak_profit_values[idx] = 0.0;
}

void CompactPartialCloseTracker()
{
   if(g_partial_close_ticket_count <= 0)
      return;

   int write_idx = 0;
   for(int i = 0; i < g_partial_close_ticket_count; i++)
   {
      ulong ticket = g_partial_close_tickets[i];
      if(ticket == 0)
         continue;
      if(PositionSelectByTicket(ticket))
         g_partial_close_tickets[write_idx++] = ticket;
   }

   for(int i = write_idx; i < g_partial_close_ticket_count; i++)
      g_partial_close_tickets[i] = 0;
   g_partial_close_ticket_count = write_idx;
}

bool HasPartialCloseBeenApplied(ulong ticket)
{
   if(ticket == 0)
      return false;

   for(int i = 0; i < g_partial_close_ticket_count; i++)
   {
      if(g_partial_close_tickets[i] == ticket)
         return true;
   }
   return false;
}

void MarkPartialCloseApplied(ulong ticket)
{
   if(ticket == 0 || HasPartialCloseBeenApplied(ticket))
      return;

   if(g_partial_close_ticket_count >= MAX_PARTIAL_CLOSE_TRACK)
      CompactPartialCloseTracker();

   if(g_partial_close_ticket_count >= MAX_PARTIAL_CLOSE_TRACK)
   {
      // Maintain bounded memory by dropping the oldest tracked entry.
      for(int i = 1; i < MAX_PARTIAL_CLOSE_TRACK; i++)
         g_partial_close_tickets[i - 1] = g_partial_close_tickets[i];
      g_partial_close_ticket_count = MAX_PARTIAL_CLOSE_TRACK - 1;
   }

   g_partial_close_tickets[g_partial_close_ticket_count++] = ticket;
}

int FindQueuedTradeByDirection(string symbol, int direction)
{
   datetime now = TimeCurrent();
   int max_age_seconds = MathMax(60, g_Max_Queued_Signal_Age_Minutes * 60);
   int best_index = -1;
   datetime best_time = 0;

   for(int i = 0; i < g_retry_count; i++)
   {
      if(i < 0 || i >= MAX_RETRY_QUEUE)
         break;
      if(g_trade_retries[i].symbol != symbol)
         continue;
      if(direction != 0 && g_trade_retries[i].signal.direction != direction)
         continue;
      if(g_trade_retries[i].created_time > 0 &&
         (now - g_trade_retries[i].created_time) > max_age_seconds)
      {
         continue;
      }

      datetime queued_signal_time = g_trade_retries[i].signal.signal_time;
      if(queued_signal_time <= 0)
         queued_signal_time = g_trade_retries[i].created_time;

      if(best_index < 0 || queued_signal_time >= best_time)
      {
         best_index = i;
         best_time = queued_signal_time;
      }
   }

   return best_index;
}

bool IsSignalTradeShapeValid(const STradingSignal &signal, string &reason)
{
   reason = "";

   if(signal.direction != 1 && signal.direction != -1)
   {
      reason = "invalid_direction";
      return false;
   }

   if(!MathIsValidNumber(signal.entry_price) || !MathIsValidNumber(signal.stop_loss) || !MathIsValidNumber(signal.take_profit))
   {
      reason = "non_numeric_levels";
      return false;
   }

   if(signal.entry_price <= 0.0 || signal.stop_loss <= 0.0 || signal.take_profit <= 0.0)
   {
      reason = "non_positive_levels";
      return false;
   }

   bool buy_layout = (signal.stop_loss < signal.entry_price && signal.take_profit > signal.entry_price);
   bool sell_layout = (signal.stop_loss > signal.entry_price && signal.take_profit < signal.entry_price);
   if(!buy_layout && !sell_layout)
   {
      reason = "invalid_level_layout";
      return false;
   }
   if(signal.direction == 1 && !buy_layout)
   {
      reason = "buy_direction_layout_mismatch";
      return false;
   }
   if(signal.direction == -1 && !sell_layout)
   {
      reason = "sell_direction_layout_mismatch";
      return false;
   }

   return true;
}

bool IsSuccessfulTradeRetcode(int retcode, bool is_pending_order)
{
   // CTrade.* can return true even when the trade server rejects the request.
   // Always gate success on the broker retcode to avoid false "executed" states.
   if(retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL)
      return true;

   // Pending orders are successful when accepted/placed at broker side.
   if(is_pending_order && retcode == TRADE_RETCODE_PLACED)
      return true;

   return false;
}

bool IsManagedExecutionMagic(long magic)
{
   return (magic >= Magic_Base && magic < Magic_Base + 10000);
}

int CountOurPendingOrders(string symbol_filter = "", int direction_filter = 0)
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      long magic = OrderGetInteger(ORDER_MAGIC);
      if(magic < Magic_Base || magic >= Magic_Base + 10000)
         continue;

      ENUM_ORDER_TYPE order_type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      int order_direction = OrderTypeToDirection(order_type);
      if(order_direction == 0)
         continue;

      string order_symbol = OrderGetString(ORDER_SYMBOL);
      if(StringLen(symbol_filter) > 0 && order_symbol != symbol_filter)
         continue;
      if(direction_filter != 0 && order_direction != direction_filter)
         continue;

      count++;
   }
   return count;
}

int CountOurOpenPositions(string symbol_filter = "", int direction_filter = 0)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic < Magic_Base || magic >= Magic_Base + 10000)
         continue;

      string pos_symbol = PositionGetString(POSITION_SYMBOL);
      if(StringLen(symbol_filter) > 0 && pos_symbol != symbol_filter)
         continue;

      if(direction_filter != 0)
      {
         long pos_type_long = PositionGetInteger(POSITION_TYPE);
         int pos_direction = 0;
         if(pos_type_long == POSITION_TYPE_BUY) pos_direction = 1;
         else if(pos_type_long == POSITION_TYPE_SELL) pos_direction = -1;
         if(pos_direction != direction_filter)
            continue;
      }

      count++;
   }
   return count;
}

bool FindOpenPositionByMagic(string symbol, int magic_number, ulong &position_ticket)
{
   position_ticket = 0;
   if(StringLen(symbol) == 0)
      return false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;

      long pos_magic = PositionGetInteger(POSITION_MAGIC);
      if(pos_magic != magic_number)
         continue;

      position_ticket = ticket;
      return true;
   }

   return false;
}

#define MAX_EXECUTION_REJECTED_POSITIONS 32
ulong g_execution_rejected_position_ids[MAX_EXECUTION_REJECTED_POSITIONS];
datetime g_execution_rejected_position_times[MAX_EXECUTION_REJECTED_POSITIONS];
int g_execution_rejected_position_cursor = 0;

void RememberExecutionRejectedPosition(ulong position_id)
{
   if(position_id == 0)
      return;

   int slot = g_execution_rejected_position_cursor % MAX_EXECUTION_REJECTED_POSITIONS;
   g_execution_rejected_position_ids[slot] = position_id;
   g_execution_rejected_position_times[slot] = TimeCurrent();
   g_execution_rejected_position_cursor++;
}

bool IsExecutionRejectedPosition(ulong position_id)
{
   if(position_id == 0)
      return false;

   datetime now = TimeCurrent();
   for(int i = 0; i < MAX_EXECUTION_REJECTED_POSITIONS; i++)
   {
      if(g_execution_rejected_position_ids[i] != position_id)
         continue;

      // Execution-rejected fills are normally seen immediately after the forced close.
      // Keep a bounded memory so old position ids cannot suppress future risk accounting.
      if(g_execution_rejected_position_times[i] > 0 &&
         (now - g_execution_rejected_position_times[i]) <= 3600)
         return true;
   }

   return false;
}

bool CloseRejectedMarketFill(string symbol,
                             int magic_number,
                             double actual_slippage_pips,
                             double max_slippage_pips,
                             double expected_price,
                             double fill_price)
{
   ulong position_ticket = 0;
   if(!FindOpenPositionByMagic(symbol, magic_number, position_ticket))
   {
      Log(LOG_WARNING, "ProcessTradeRetry",
          StringFormat("%s - Slippage breach %.2f pips > %.2f pips, but no matching open position was found for immediate close (expected=%.5f, fill=%.5f)",
                       symbol, actual_slippage_pips, max_slippage_pips, expected_price, fill_price));
      return false;
   }

   ulong position_id = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   if(position_id == 0)
      position_id = position_ticket;

   bool close_request_ok = trade.PositionClose(position_ticket);
   int close_retcode = (int)trade.ResultRetcode();
   bool close_ok = (close_request_ok && IsSuccessfulTradeRetcode(close_retcode, false));
   if(close_ok)
   {
      RememberExecutionRejectedPosition(position_id);
      Log(LOG_WARNING, "ProcessTradeRetry",
          StringFormat("%s - Rejected slipped market fill and closed position #%I64u (slippage %.2f pips > %.2f pips, expected=%.5f, fill=%.5f)",
                       symbol, position_ticket, actual_slippage_pips, max_slippage_pips, expected_price, fill_price));
      AuditLog("EXECQ_SLIPPAGE_CLOSE", symbol,
               StringFormat("Ticket=%I64u Slippage=%.2f Max=%.2f Expected=%.5f Fill=%.5f",
                            position_ticket, actual_slippage_pips, max_slippage_pips, expected_price, fill_price));
      return true;
   }

   Log(LOG_WARNING, "ProcessTradeRetry",
       StringFormat("%s - Slippage breach close failed for position #%I64u (retcode=%d, %s)",
                    symbol, position_ticket, close_retcode, trade.ResultRetcodeDescription()));
   return false;
}

string SignalFingerprintTag(ulong signal_fingerprint)
{
   return "F=" + StringFormat("%016I64X", signal_fingerprint);
}

string BuildExecutionComment(const STradingSignal &signal, string symbol, int magic_number, ulong signal_fingerprint)
{
   // Keep broker comment safely below common 31-char limits so the fingerprint survives truncation.
   string bias_tag = GetCompactExecutionBiasTag(signal);
   string comment = StringFormat("PTB|%s%s|%s",
                                 GetCompactSignalOriginTag(signal.origin),
                                 (StringLen(bias_tag) > 0 ? "|" + bias_tag : ""),
                                 SignalFingerprintTag(signal_fingerprint));
   return SafeTruncateComment(comment);
}

bool CommentHasSignalFingerprint(string comment, ulong signal_fingerprint)
{
   if(signal_fingerprint == 0 || StringLen(comment) <= 0)
      return false;
   return (StringFind(comment, SignalFingerprintTag(signal_fingerprint)) >= 0);
}

bool IsExecutionPriceNear(double lhs, double rhs, double tolerance)
{
   if(!MathIsValidNumber(lhs) || !MathIsValidNumber(rhs))
      return false;
   if(lhs <= 0.0 || rhs <= 0.0 || tolerance < 0.0)
      return false;
   return (MathAbs(lhs - rhs) <= tolerance);
}

bool FindRecentMatchingExecutionExposure(string symbol,
                                         int direction,
                                         int magic_number,
                                         ulong signal_fingerprint,
                                         double expected_entry,
                                         double expected_sl,
                                         double expected_tp,
                                         datetime earliest_time,
                                         ulong &matched_ticket,
                                         string &matched_state,
                                         double &matched_price)
{
   matched_ticket = 0;
   matched_state = "";
   matched_price = 0.0;

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = Point();
   if(point <= 0.0)
      point = 0.0001;

   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0)
      tick_size = point;

   double level_tolerance = MathMax(point * 15.0, tick_size * 5.0);
   double entry_tolerance = MathMax(point * 30.0, tick_size * 10.0);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;

      long pos_magic = PositionGetInteger(POSITION_MAGIC);
      if(!IsManagedExecutionMagic(pos_magic))
         continue;

      long pos_type_long = PositionGetInteger(POSITION_TYPE);
      int pos_direction = 0;
      if(pos_type_long == POSITION_TYPE_BUY)
         pos_direction = 1;
      else if(pos_type_long == POSITION_TYPE_SELL)
         pos_direction = -1;
      if(direction != 0 && pos_direction != direction)
         continue;

      datetime pos_time = (datetime)PositionGetInteger(POSITION_TIME);
      if(earliest_time > 0 && pos_time < earliest_time)
         continue;

      double pos_open = PositionGetDouble(POSITION_PRICE_OPEN);
      double pos_sl = PositionGetDouble(POSITION_SL);
      double pos_tp = PositionGetDouble(POSITION_TP);
      string pos_comment = PositionGetString(POSITION_COMMENT);

      bool fingerprint_match = CommentHasSignalFingerprint(pos_comment, signal_fingerprint);
      bool sl_match = (expected_sl <= 0.0 || pos_sl <= 0.0 || IsExecutionPriceNear(pos_sl, expected_sl, level_tolerance));
      bool tp_match = (expected_tp <= 0.0 || pos_tp <= 0.0 || IsExecutionPriceNear(pos_tp, expected_tp, level_tolerance));
      bool entry_match = (expected_entry <= 0.0 || IsExecutionPriceNear(pos_open, expected_entry, entry_tolerance));

      if(fingerprint_match || ((sl_match && tp_match) && entry_match))
      {
         matched_ticket = ticket;
         matched_state = (pos_magic == magic_number ?
                          "open position" :
                          "open position (prior retry magic)");
         matched_price = pos_open;
         return true;
      }
   }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      if(OrderGetString(ORDER_SYMBOL) != symbol)
         continue;

      long order_magic = OrderGetInteger(ORDER_MAGIC);
      if(!IsManagedExecutionMagic(order_magic))
         continue;

      ENUM_ORDER_TYPE order_type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      int order_direction = OrderTypeToDirection(order_type);
      if(order_direction == 0 || (direction != 0 && order_direction != direction))
         continue;

      datetime order_time = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      if(earliest_time > 0 && order_time < earliest_time)
         continue;

      double order_price = OrderGetDouble(ORDER_PRICE_OPEN);
      double order_sl = OrderGetDouble(ORDER_SL);
      double order_tp = OrderGetDouble(ORDER_TP);
      string order_comment = OrderGetString(ORDER_COMMENT);

      bool fingerprint_match = CommentHasSignalFingerprint(order_comment, signal_fingerprint);
      bool entry_match = (expected_entry <= 0.0 || IsExecutionPriceNear(order_price, expected_entry, level_tolerance));
      bool sl_match = (expected_sl <= 0.0 || order_sl <= 0.0 || IsExecutionPriceNear(order_sl, expected_sl, level_tolerance));
      bool tp_match = (expected_tp <= 0.0 || order_tp <= 0.0 || IsExecutionPriceNear(order_tp, expected_tp, level_tolerance));

      if(fingerprint_match || (entry_match && sl_match && tp_match))
      {
         matched_ticket = ticket;
         matched_state = (order_magic == magic_number ?
                          "pending order" :
                          "pending order (prior retry magic)");
         matched_price = order_price;
         return true;
      }
   }

   return false;
}

int ComputeExecutionBackoffSeconds(int base_interval, int attempt)
{
   int backoff = MathMax(1, base_interval);
   int capped_attempt = MathMax(0, MathMin(attempt, 6));
   for(int i = 0; i < capped_attempt; i++)
   {
      if(backoff >= 120)
         return 120;
      backoff *= 2;
   }
   return MathMin(backoff, 120);
}

bool IsSuccessfulPreflightRetcode(int retcode)
{
   return (retcode == 0 ||
           retcode == TRADE_RETCODE_DONE ||
           retcode == TRADE_RETCODE_DONE_PARTIAL ||
           retcode == TRADE_RETCODE_PLACED);
}

bool BuildExecutionPreflightRequest(string symbol,
                                    int magic_number,
                                    ENUM_ORDER_TYPE order_type,
                                    ENUM_ORDER_TYPE_FILLING fill_mode,
                                    double volume,
                                    double price,
                                    double stop_loss,
                                    double take_profit,
                                    ulong deviation_points,
                                    datetime expiration,
                                    string comment,
                                    MqlTradeRequest &request,
                                    string &reason)
{
   ZeroMemory(request);
   reason = "";

   if(StringLen(symbol) <= 0)
   {
      reason = "symbol";
      return false;
   }
   if(!MathIsValidNumber(volume) || volume <= 0.0)
   {
      reason = "volume";
      return false;
   }
   if(!MathIsValidNumber(price) || price <= 0.0)
   {
      reason = "price";
      return false;
   }

   request.action = ((order_type == ORDER_TYPE_BUY || order_type == ORDER_TYPE_SELL) ?
                     TRADE_ACTION_DEAL : TRADE_ACTION_PENDING);
   request.symbol = symbol;
   request.magic = magic_number;
   request.volume = volume;
   request.price = price;
   request.sl = stop_loss;
   request.tp = take_profit;
   request.deviation = deviation_points;
   request.type = order_type;
   request.type_filling = fill_mode;
   request.type_time = ORDER_TIME_GTC;
   request.comment = SafeTruncateComment(comment);

   if(request.action == TRADE_ACTION_PENDING && expiration > 0)
   {
      request.type_time = ORDER_TIME_SPECIFIED;
      request.expiration = expiration;
   }

   return true;
}

bool RunBrokerExecutionPreflight(STradeRetry &retry,
                                 const STradingSignal &signal,
                                 string symbol,
                                 string execution_type,
                                 int magic_number,
                                 ulong signal_fingerprint,
                                 ENUM_ORDER_TYPE order_type,
                                 ENUM_ORDER_TYPE_FILLING fill_mode,
                                 double volume,
                                 double price,
                                 double stop_loss,
                                 double take_profit,
                                 ulong deviation_points,
                                 datetime expiration,
                                 string comment,
                                 int retry_interval,
                                 int digits,
                                 bool &already_live)
{
   already_live = false;

   // FIX #3: Pending order ticket validation - detect already-placed orders
   if(retry.order_placed && retry.ticket > 0)
   {
      if(OrderSelect(retry.ticket))
      {
         ENUM_ORDER_STATE order_state = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
         if(order_state == ORDER_STATE_PLACED || order_state == ORDER_STATE_PARTIAL)
         {
            Log(LOG_INFO, "RunBrokerExecutionPreflight", symbol +
                " - Order ticket " + IntegerToString(retry.ticket) + 
                " still valid on broker; treating as already live");
            already_live = true;
            return true;
         }
         else
         {
            // Order was closed/cancelled; reset for new attempt
            ulong previous_ticket = retry.ticket;
            retry.ticket = 0;
            retry.order_placed = false;
            Log(LOG_INFO, "RunBrokerExecutionPreflight", symbol +
                " - Previous ticket " + IntegerToString(previous_ticket) + 
                " closed; ready for new placement");
         }
      }
      else
      {
         // OrderSelect failed; ticket may be stale
         retry.ticket = 0;
         retry.order_placed = false;
      }
   }

   if(retry.attempt > 0)
   {
      ulong matched_ticket = 0;
      string matched_state = "";
      double matched_price = 0.0;
      datetime reconcile_from = (retry.created_time > 0 ?
                                 retry.created_time - 5 :
                                 TimeCurrent() - MathMax(30, retry_interval * 4));

      if(FindRecentMatchingExecutionExposure(symbol, signal.direction, magic_number,
                                             signal_fingerprint, price, stop_loss, take_profit,
                                             reconcile_from, matched_ticket, matched_state, matched_price))
      {
         string reconcile_msg = symbol + " - Existing " + matched_state +
                                " already matches queued signal; suppressing duplicate resend " +
                                "(ticket=" + (string)matched_ticket +
                                ", price=" + DoubleToString(matched_price, digits) + ")";
         Log(LOG_WARNING, "ProcessTradeRetry", reconcile_msg);
         AuditLogSignal("EXECUTE_RECONCILED", symbol, signal,
                        "State=" + matched_state +
                        " Ticket=" + (string)matched_ticket +
                        " Price=" + DoubleToString(matched_price, digits) +
                        " SigFP=" + StringFormat("%I64u", signal_fingerprint));
         already_live = true;
         return true;
      }
   }

   MqlTradeRequest request;
   MqlTradeCheckResult check;
   string build_reason = "";
   if(!BuildExecutionPreflightRequest(symbol, magic_number, order_type, fill_mode,
                                      volume, price, stop_loss, take_profit,
                                      deviation_points, expiration, comment,
                                      request, build_reason))
   {
      RecordRejectReason("RETRY:PreflightBuildFailed_" + build_reason);
      Log(LOG_ERROR, "ProcessTradeRetry", symbol +
          " - Failed to build broker preflight request (" + build_reason + ")");
      retry.attempt = g_Max_Retry_Attempts;
      return false;
   }

   ZeroMemory(check);
   ResetLastError();
   bool order_check_ok = OrderCheck(request, check);
   int transport_error = GetLastError();
   int check_retcode = (int)check.retcode;
   string check_desc = check.comment;

   if(!order_check_ok)
   {
      check_desc = "OrderCheck failed";
      if(transport_error != 0)
         check_desc += " err=" + IntegerToString(transport_error);
   }
   else if(StringLen(check_desc) <= 0)
   {
      check_desc = "retcode=" + IntegerToString(check_retcode);
   }

   if(!order_check_ok || !IsSuccessfulPreflightRetcode(check_retcode))
   {
      if(check_retcode == TRADE_RETCODE_INVALID_FILL &&
         StringFind(execution_type, "PENDING") < 0)
      {
         ENUM_ORDER_TYPE_FILLING fallback_modes[3] =
            { ORDER_FILLING_FOK, ORDER_FILLING_IOC, ORDER_FILLING_RETURN };

         for(int mode_index = 0; mode_index < 3; mode_index++)
         {
            ENUM_ORDER_TYPE_FILLING fallback_fill = fallback_modes[mode_index];
            if(fallback_fill == fill_mode || !IsFillModeSupportedBySymbol(symbol, fallback_fill))
               continue;

            MqlTradeRequest fallback_request = request;
            fallback_request.type_filling = fallback_fill;

            MqlTradeCheckResult fallback_check;
            ZeroMemory(fallback_check);
            ResetLastError();
            bool fallback_ok = OrderCheck(fallback_request, fallback_check);
            int fallback_transport_error = GetLastError();
            int fallback_retcode = (int)fallback_check.retcode;

            if(fallback_ok && IsSuccessfulPreflightRetcode(fallback_retcode))
            {
               trade.SetTypeFilling(fallback_fill);
               string recovery_msg = symbol + " - Broker rejected fill mode " +
                                     FillModeToString(fill_mode) + " for " + execution_type +
                                     "; retrying with " + FillModeToString(fallback_fill);
               Log(LOG_WARNING, "ProcessTradeRetry", recovery_msg);
               AuditLogSignal("EXECUTE_FILLMODE_RECOVERED", symbol, signal,
                              "Type=" + execution_type +
                              " Fill=" + FillModeToString(fill_mode) + "->" +
                              FillModeToString(fallback_fill) +
                              " SigFP=" + StringFormat("%I64u", signal_fingerprint));
               return true;
            }

            if(g_Enable_Institutional_Debug)
            {
               string fallback_desc = fallback_check.comment;
               if(!fallback_ok)
               {
                  fallback_desc = "OrderCheck failed";
                  if(fallback_transport_error != 0)
                     fallback_desc += " err=" + IntegerToString(fallback_transport_error);
               }
               else if(StringLen(fallback_desc) <= 0)
               {
                  fallback_desc = "retcode=" + IntegerToString(fallback_retcode);
               }

               Log(LOG_DEBUG, "ProcessTradeRetry",
                   symbol + " - Alternate fill mode " + FillModeToString(fallback_fill) +
                   " also rejected for " + execution_type + " (" + fallback_desc + ")");
            }
         }
      }

      string reject_prefix = (StringFind(execution_type, "PENDING") >= 0 ?
                              "RETRY:PendingPreflightFailed_" :
                              "RETRY:MarketPreflightFailed_");
      RecordRejectReason(reject_prefix + IntegerToString(check_retcode));

      string preflight_msg = symbol + " - Broker preflight rejected " + execution_type +
                             " | " + check_desc +
                             " (retcode=" + IntegerToString(check_retcode) +
                             ", margin=" + DoubleToString(check.margin, 2) +
                             ", free=" + DoubleToString(check.margin_free, 2) +
                             ", level=" + DoubleToString(check.margin_level, 1) + ")";
      Log(LOG_WARNING, "ProcessTradeRetry", preflight_msg);
      AuditLogSignal("EXECUTE_PREFLIGHT_FAIL", symbol, signal,
                     "Type=" + execution_type +
                     " Retcode=" + IntegerToString(check_retcode) +
                     " " + check_desc +
                     " SigFP=" + StringFormat("%I64u", signal_fingerprint));

      bool price_issue = (check_retcode == TRADE_RETCODE_INVALID_PRICE ||
                          check_retcode == TRADE_RETCODE_PRICE_OFF ||
                          check_retcode == TRADE_RETCODE_PRICE_CHANGED);
      if(price_issue)
      {
         retry.next_retry = TimeCurrent() + MathMax(1, retry_interval);
         return false;
      }

      if(IsPermanentError(check_retcode, check_desc))
      {
         retry.attempt = g_Max_Retry_Attempts;
         return false;
      }

      retry.next_retry = TimeCurrent() + ComputeExecutionBackoffSeconds(retry_interval, retry.attempt + 1);
      return false;
   }

   if(g_Enable_Institutional_Debug)
   {
      Log(LOG_DEBUG, "ProcessTradeRetry",
          symbol + " - Broker preflight OK for " + execution_type +
          " (margin=" + DoubleToString(check.margin, 2) +
          ", free=" + DoubleToString(check.margin_free, 2) +
          ", level=" + DoubleToString(check.margin_level, 1) + ")");
   }

   return true;
}

bool IsTradeLevelsPermanent(int reason)
{
   switch(reason)
   {
      case TRADE_LEVELS_NON_POSITIVE:
      case TRADE_LEVELS_NON_NUMERIC:
      case TRADE_LEVELS_INVALID_LAYOUT:
      case TRADE_LEVELS_SYMBOL_INDEX:
         return true;
      default:
         return false;
   }
}

// Signal fingerprinting to ensure "single truth" across queue -> execution.
ulong HashFNV1a64Init()
{
   return (ulong)1469598103934665603;
}

ulong HashFNV1a64Mix(ulong hash, ulong value)
{
   hash ^= value;
   hash *= (ulong)1099511628211;
   return hash;
}

ulong HashFNV1a64String(ulong hash, string value)
{
   if(StringLen(value) <= 0)
      return hash;
   uchar bytes[];
   int len = StringToCharArray(value, bytes, 0, -1, CP_UTF8);
   if(len <= 0)
      return hash;
   int n = len;
   if(bytes[len - 1] == 0)
      n = len - 1;
   for(int i = 0; i < n; i++)
   {
      hash ^= (ulong)bytes[i];
      hash *= (ulong)1099511628211;
   }
   return hash;
}

ulong ComputeSignalFingerprint(const STradingSignal &signal, string symbol)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = Point();
   if(point <= 0.0)
      point = 0.0001;

   long entry_ticks = (long)MathRound(signal.entry_price / point);
   long sl_ticks = (long)MathRound(signal.stop_loss / point);
   long tp_ticks = (long)MathRound(signal.take_profit / point);
   long rr_milli = (long)MathRound(signal.risk_reward_ratio * 1000.0);

   ulong hash = HashFNV1a64Init();
   int dir_code = (signal.direction == 1 ? 1 : (signal.direction == -1 ? 2 : 0));
   hash = HashFNV1a64Mix(hash, (ulong)dir_code);
   hash = HashFNV1a64Mix(hash, (ulong)signal.origin);
   hash = HashFNV1a64Mix(hash, (ulong)(signal.retracement_signal ? 1 : 0));
   hash = HashFNV1a64Mix(hash, (ulong)(signal.allow_countertrend_execution ? 1 : 0));
   // ISSUE #6: Do NOT include signal.signal_time - timing shouldn't prevent queue refreshes
   // ISSUE #6: Do NOT include signal.reason - descriptive text changes don't matter for level detection
   hash = HashFNV1a64Mix(hash, (ulong)entry_ticks);
   hash = HashFNV1a64Mix(hash, (ulong)sl_ticks);
   hash = HashFNV1a64Mix(hash, (ulong)tp_ticks);
   hash = HashFNV1a64Mix(hash, (ulong)rr_milli);
   hash = HashFNV1a64String(hash, symbol);
   return hash;
}

// Shared gate checks for ExecuteTrade / ProcessTradeRetry to reduce duplication.
#define GATE_CHECK_TRADE_ALLOWED  0x01
#define GATE_CHECK_DRAWDOWN       0x02
#define GATE_CHECK_GOLD           0x04
#define GATE_CHECK_SPREAD         0x08
#define GATE_CHECK_DAILY_CAP      0x10
#define GATE_CHECK_RANGE          0x20

bool ApplySharedTradeGates(string symbol,
                           bool allow_range,
                           bool is_retry,
                           datetime now,
                           int defer_short,
                           int defer_medium,
                           int gate_mask,
                           datetime &defer_until,
                           string log_context,
                           string reason_prefix)
{
   defer_until = 0;

   if((gate_mask & GATE_CHECK_TRADE_ALLOWED) != 0)
   {
      if(!IsTradeAllowed(symbol))
      {
         string reason = reason_prefix + ":TradeNotAllowed";
         RecordRejectReason(reason);
         if(is_retry)
         {
            datetime defer_to = now + defer_medium;
            datetime pause_until = GetExecutionPauseUntil(now);
            if(pause_until > now)
               defer_to = MathMax(defer_to, pause_until + 5);
            defer_until = defer_to;

            static datetime last_trade_not_allowed_retry_log = 0;
            if(last_trade_not_allowed_retry_log == 0 || (now - last_trade_not_allowed_retry_log) >= 30)
            {
               Log(LOG_INFO, log_context, symbol + " - Trade currently not allowed; retry deferred to " +
                   TimeToString(defer_until));
               last_trade_not_allowed_retry_log = now;
            }
         }
         else
         {
            Log(LOG_WARNING, log_context, symbol + " - Trade not allowed");
         }
         return false;
      }
   }

   if((gate_mask & GATE_CHECK_DRAWDOWN) != 0)
   {
      if(IsDrawdownLimitExceeded())
      {
         string reason = reason_prefix + ":DrawdownLimit";
         RecordRejectReason(reason);
         if(is_retry)
         {
            defer_until = (g_drawdown_pause_until > now ? g_drawdown_pause_until + 5 : now + defer_medium);
            Log(LOG_WARNING, log_context, symbol + " - Drawdown limit exceeded; retry deferred to " +
                TimeToString(defer_until));
         }
         else
         {
            Log(LOG_WARNING, log_context, symbol + " - Drawdown limit exceeded");
         }
         return false;
      }
   }

   bool is_gold_symbol = (StringFind(symbol, "XAU") != -1 || StringFind(symbol, "GOLD") != -1);

   if((gate_mask & GATE_CHECK_GOLD) != 0)
   {
      if(is_gold_symbol && !ValidateGoldTradingConditions(symbol))
      {
         string reason = reason_prefix + ":GoldConditions";
         RecordRejectReason(reason);
         if(is_retry)
         {
            defer_until = now + defer_short;
            Log(LOG_INFO, log_context, symbol + " - GOLD conditions not met, delaying execution");
         }
         else
         {
            Log(LOG_INFO, log_context, symbol + " - GOLD conditions not met");
         }
         return false;
      }
   }

   if((gate_mask & GATE_CHECK_SPREAD) != 0 && !is_gold_symbol)
   {
      if(!IsSpreadAcceptable(symbol))
      {
         string reason = reason_prefix + ":SpreadTooHigh";
         RecordRejectReason(reason);
         if(is_retry)
         {
            defer_until = now + defer_short;
            Log(LOG_INFO, log_context, symbol + " - Spread too high, delaying execution");
         }
         else
         {
            Log(LOG_INFO, log_context, symbol + " - Spread too high");
         }
         return false;
      }
   }

   if((gate_mask & GATE_CHECK_DAILY_CAP) != 0)
   {
      if(!CanExecuteTradeToday())
      {
         string reason = reason_prefix + ":DailyTradeCap";
         RecordRejectReason(reason);
         if(is_retry)
         {
            datetime next_reset = GetNextDailyResetTime();
            defer_until = MathMax(now + 60, next_reset + 5);

            static datetime last_daily_cap_log = 0;
            if(last_daily_cap_log == 0 || (now - last_daily_cap_log) >= 60)
            {
               Log(LOG_INFO, log_context, symbol + " - Daily cap reached; deferring retry until " +
                   TimeToString(defer_until));
               last_daily_cap_log = now;
            }
         }
         else
         {
            Log(LOG_INFO, log_context, symbol + " - Daily trade cap reached, skipping queue");
         }
         return false;
      }
   }

   if((gate_mask & GATE_CHECK_RANGE) != 0)
   {
      string range_reason = "";
      if(!allow_range && IsMarketRanging(symbol, range_reason))
      {
         string reason = reason_prefix + ":RangingMarket";
         RecordRejectReason(reason);
         if(is_retry)
         {
            defer_until = now + defer_medium;
            static datetime last_ranging_retry_log = 0;
            if(last_ranging_retry_log == 0 || (now - last_ranging_retry_log) >= 20)
            {
               Log(LOG_INFO, log_context, symbol + " - Ranging market, retry deferred: " + range_reason);
               last_ranging_retry_log = now;
            }
         }
         else
         {
            Log(LOG_INFO, log_context, symbol + " - Ranging market blocked queueing: " + range_reason);
         }
         return false;
      }
   }

   return true;
}

//====================================================================
// TRADE EXECUTION - COMPLETELY REBUILT
//====================================================================
// Consolidated trade execution function - replaces ExecuteTrade and ExecuteTradeWithErrorHandling
bool FinalizeQueuedTradeAdmission(int queue_index, datetime admission_time)
{
   if(queue_index < 0 || queue_index >= g_retry_count || queue_index >= MAX_RETRY_QUEUE)
   {
      Log(LOG_ERROR, "ExecuteTrade", "Invalid retry queue index after admission: " + IntegerToString(queue_index));
      return false;
   }

   string symbol = g_trade_retries[queue_index].symbol;
   bool trade_executed = ProcessTradeRetry(g_trade_retries[queue_index]);
   if(trade_executed)
   {
      Log(LOG_INFO, "ExecuteTrade", symbol + " - Immediate broker execution completed after queue admission");
      RemoveRetryQueueItem(queue_index);
      return true;
   }

   if(queue_index < 0 || queue_index >= g_retry_count || queue_index >= MAX_RETRY_QUEUE)
      return false;

   if(g_trade_retries[queue_index].attempt >= g_Max_Retry_Attempts)
   {
      Log(LOG_WARNING, "ExecuteTrade", symbol +
          " - Immediate execution failed permanently; removing retry queue entry");
      RemoveRetryQueueItem(queue_index);
      return false;
   }

   if(g_trade_retries[queue_index].next_retry > admission_time)
   {
      if(g_Enable_Institutional_Debug)
      {
         Log(LOG_DEBUG, "ExecuteTrade", symbol +
             " - Immediate execution deferred; queued retry remains active until " +
             TimeToString(g_trade_retries[queue_index].next_retry));
      }
      return true;
   }

   int retry_interval = MathMax(1, g_Retry_Interval_Seconds);
   if(++g_trade_retries[queue_index].attempt >= g_Max_Retry_Attempts)
   {
      RecordRejectReason("RETRY:MaxAttemptsReached");
      Log(LOG_WARNING, "ExecuteTrade", symbol +
          " - Immediate execution exhausted retry budget; removing from queue");
      RemoveRetryQueueItem(queue_index);
      return false;
   }

   g_trade_retries[queue_index].next_retry = TimeCurrent() + retry_interval;
   Log(LOG_INFO, "ExecuteTrade", symbol +
       " - Immediate execution not yet placed; queued retry scheduled at " +
       TimeToString(g_trade_retries[queue_index].next_retry) +
       " (attempt " + IntegerToString(g_trade_retries[queue_index].attempt + 1) +
       "/" + IntegerToString(g_Max_Retry_Attempts) + ")");
   return true;
}

bool ExecuteTrade(string symbol, const STradingSignal &signal, int symbol_index)
{
   // BUG FIX H2: Add initialization cooldown check in ExecuteTrade as double-barrier
   if(!g_initialization_complete)
   {
      datetime current_time = TimeCurrent();
      if(current_time - g_initialization_time < INITIALIZATION_COOLDOWN_SECONDS)
      {
         RecordRejectReason("EXECQ:InitCooldown");
         return false;  // Block queueing during init period
      }
   }

   if(!signal.valid)
   {
      RecordRejectReason("EXECQ:InvalidSignal");
      Log(LOG_WARNING, "ExecuteTrade", "Invalid signal for " + symbol);
      return false;
   }

   string signal_shape_reason = "";
   if(!IsSignalTradeShapeValid(signal, signal_shape_reason))
   {
      RecordRejectReason("EXECQ:MalformedSignal_" + signal_shape_reason);
      Log(LOG_WARNING, "ExecuteTrade", symbol + " - Malformed signal rejected: " + signal_shape_reason);
      return false;
   }

   if(g_Enable_Institutional_Debug && signal.origin == SIGNAL_ORIGIN_ICT && signal.direction == -1)
   {
      Log(LOG_INFO, "ExecuteTrade", symbol + " - DEBUG ICT Launching a SELL trade (queue pipeline)");
   }

   if(g_Enable_Institutional_Debug && StringFind(signal.reason, "PreEntry=") >= 0)
   {
      Log(LOG_INFO, "ExecuteTrade", symbol +
          " - DEBUG pre-entry signal routed into standard queue/retry pipeline");
   }
   
   if(IsLossCooldownActive())
   {
      RecordRejectReason("EXECQ:LossCooldown");
      Log(LOG_WARNING, "ExecuteTrade", symbol + " - Loss cooldown active, skipping trade queue");
      return false;
   }

   if(IsSymbolLossCooldownActive(symbol))
   {
      RecordRejectReason("EXECQ:SymbolLossCooldown");
      Log(LOG_WARNING, "ExecuteTrade", symbol + " - Symbol loss cooldown active, skipping trade queue");
      return false;
   }
   
   if(Enable_Backtest_Mode)
   {
      Log(LOG_INFO, "ExecuteTrade", symbol + " - BACKTEST MODE: Would execute " + 
          (signal.direction == 1 ? "BUY" : "SELL") + " at " + DoubleToString(signal.entry_price, 2));
      return true;
   }

   if(IsStopped())
   {
      RecordRejectReason("EXECQ:EAStopped");
      Log(LOG_WARNING, "ExecuteTrade", symbol + " - EA stopped, skipping trade");
      return false;
   }
   
   if(!IsValidSymbol(symbol))
   {
      RecordRejectReason("EXECQ:InvalidSymbol");
      Log(LOG_WARNING, "ExecuteTrade", symbol + " - Invalid symbol");
      return false;
   }
 
   bool allow_range_execution =
      (g_Allow_Range_Trading ||
       ExtractAutoModeFromSignalReason(signal.reason) == AUTO_REGIME_MODE_INTRA_HIGHLOW);

   datetime now = TimeCurrent();
   datetime shared_defer = 0;
   if(!ApplySharedTradeGates(symbol, allow_range_execution, false, now, 0, 0,
                             GATE_CHECK_TRADE_ALLOWED | GATE_CHECK_DRAWDOWN |
                             GATE_CHECK_GOLD | GATE_CHECK_DAILY_CAP | GATE_CHECK_RANGE,
                             shared_defer, "ExecuteTrade", "EXECQ"))
   {
      return false;
   }
   
   STradingSignal queued_signal = signal;
   double news_size_adjustment = 1.0;

   // ===== TIER 3C ENHANCEMENT: NEWS EVENT INTEGRATION =====
   // Check for high-impact economic news events that should block/reduce position size
   if(Enable_Economic_Calendar_Filter)
   {
      SNewsBuffer news_buffer = CNewsIntegration::CheckNewsBuffer(now, News_Buffer_Before_Minutes,
                                                                  News_Buffer_After_Minutes, symbol);
      
      if(CNewsIntegration::ShouldHaltTradingForNews(news_buffer))
      {
         RecordRejectReason("EXECQ:NewsEventHalt");
         Log(LOG_WARNING, "ExecuteTrade", symbol + 
             " - Trading halted due to high-impact economic news event");
         return false;
      }
      
      // Apply position size adjustment based on news proximity
      news_size_adjustment = CNewsIntegration::GetNewsPositionSizeAdjustment(news_buffer);
      if(news_size_adjustment < 1.0)
      {
         news_size_adjustment = MathMax(0.10, MathMin(1.0, news_size_adjustment));
         if(g_Enable_Institutional_Debug)
            Log(LOG_DEBUG, "ExecuteTrade", symbol + 
                " - Tier 3C: News event position size adjustment applied (" + 
                DoubleToString(news_size_adjustment, 2) + "x)");
         queued_signal.reason = queued_signal.reason + " NewsMult=" + DoubleToString(news_size_adjustment, 2);
      }
   }
   // ===== END TIER 3C =====

   if(signal.signal_time <= 0)
   {
      RecordRejectReason("EXECQ:SignalTimeMissing");
      Log(LOG_WARNING, "ExecuteTrade", symbol + " - Signal time missing; rejecting queue");
      return false;
   }
   if(signal.signal_time > (now + 5))
   {
      RecordRejectReason("EXECQ:SignalTimeFuture");
      Log(LOG_WARNING, "ExecuteTrade", symbol +
          " - Signal time in the future (" + TimeToString(signal.signal_time) + "); rejecting queue");
      return false;
   }
   if(signal.signal_time > 0)
   {
      int max_age_seconds = MathMax(60, g_Max_Queued_Signal_Age_Minutes * 60);
      int signal_age = (int)(now - signal.signal_time);
      if(signal_age > max_age_seconds)
      {
         RecordRejectReason("EXECQ:SignalStale");
         Log(LOG_WARNING, "ExecuteTrade", symbol +
             " - Signal too stale to queue (age=" + IntegerToString(signal_age) +
             "s, max=" + IntegerToString(max_age_seconds) + "s)");
         return false;
      }
   }

   if(g_retry_count < 0)
      g_retry_count = 0;
   if(g_retry_count > MAX_RETRY_QUEUE)
      g_retry_count = MAX_RETRY_QUEUE;

   // Count positions and check limits
   int our_positions = CountOurOpenPositions();
   int symbol_positions = CountOurOpenPositions(symbol);

   int symbol_pending_orders = CountOurPendingOrders(symbol);
   int symbol_total_exposure = symbol_positions + symbol_pending_orders;

   if(ExposureGateOn() && symbol_total_exposure >= MAX_TRADES_PER_SYMBOL)
   {
      RecordRejectReason("EXECQ:SymbolExposureLimit");
      Log(LOG_INFO, "ExecuteTrade", symbol + " - Symbol exposure limit reached (positions=" +
          IntegerToString(symbol_positions) + ", pending=" + IntegerToString(symbol_pending_orders) +
          ", limit=" + IntegerToString(MAX_TRADES_PER_SYMBOL) + ")");
      return false;
   }

   int concurrent_limit = MathMax(1, g_Max_Concurrent_Trades_Effective);
   int our_pending_orders = CountOurPendingOrders();
   int concurrent_slots_used = our_positions + our_pending_orders;
   if(CGateController::IsExposureGateEnabled() && concurrent_slots_used >= concurrent_limit)
   {
      RecordRejectReason("EXECQ:MaxConcurrentTrades");
      Log(LOG_INFO, "ExecuteTrade", symbol + " - Max concurrent trades reached (" +
          IntegerToString(concurrent_slots_used) + "/" + IntegerToString(concurrent_limit) +
          ", open=" + IntegerToString(our_positions) +
          ", pending=" + IntegerToString(our_pending_orders) +
          ", input=" + IntegerToString(Max_Concurrent_Trades) +
          ", profile=" + g_Live_Risk_Profile_Name + ")");
      return false;
   }
   
   // BUG FIX C1: Check bounds BEFORE trying to access any array element.
   // Allow the final valid slot (index MAX_RETRY_QUEUE - 1) to be used.
   if(g_retry_count >= MAX_RETRY_QUEUE)
   {
      RecordRejectReason("EXECQ:RetryQueueFull");
      Log(LOG_WARNING, "ExecuteTrade", "Retry queue full (count=" + IntegerToString(g_retry_count) + "/" + IntegerToString(MAX_RETRY_QUEUE) + ")");
      return false;
   }

   if(!g_Disable_All_Gates)
   {
      int execution_preference = ExtractExecutionPreferenceFromSignalReason(queued_signal.reason);
      bool pending_capable = (g_Use_Pending_Orders ||
                              g_Enable_Smart_Order_Routing ||
                              execution_preference == SIGNAL_EXEC_PREF_PENDING);
      double bid = 0.0, ask = 0.0;
      SymbolInfoDouble(symbol, SYMBOL_BID, bid);
      SymbolInfoDouble(symbol, SYMBOL_ASK, ask);

      if(bid <= 0.0 || ask <= 0.0)
      {
         int sidx = (symbol_index >= 0 ? symbol_index : GetSymbolIndex(symbol));
         if(sidx >= 0 && sidx < g_symbols_count)
         {
            bid = g_symbols[sidx].cache.bid;
            ask = g_symbols[sidx].cache.ask;
         }
      }

      // M2 FIX: Use midpoint for distance calculation (not direction-based price)
      // Calculates distance from CURRENT market (midpoint) to entry price
      double ref_price = 0.0;
      if(bid > 0.0 && ask > 0.0)
         ref_price = (bid + ask) / 2.0;
      
      if(ref_price <= 0.0)
      {
         // Fallback: try to use cached prices if live prices failed
         int sidx = (symbol_index >= 0 ? symbol_index : GetSymbolIndex(symbol));
         if(sidx >= 0 && sidx < g_symbols_count)
         {
            double cached_bid = g_symbols[sidx].cache.bid;
            double cached_ask = g_symbols[sidx].cache.ask;
            if(cached_bid > 0.0 && cached_ask > 0.0)
               ref_price = (cached_bid + cached_ask) / 2.0;
         }
      }

      // BUG FIX 2.7: Entry distance check must not skip - return error if ref_price still invalid
      if(ref_price <= 0.0)
      {
         RecordRejectReason("EXECQ:InvalidRefPriceForDistanceCheck");
         Log(LOG_ERROR, "ExecuteTrade", symbol + 
             " - Cannot validate entry distance: ref_price invalid after all fallbacks (bid=" + 
             DoubleToString(bid, 5) + ", ask=" + DoubleToString(ask, 5) + ")");
         return false;
      }

      double entry_distance_pct = MathAbs(signal.entry_price - ref_price) / ref_price * 100.0;
      double distance_cap_basis = g_Max_Entry_Distance_Pct;
      if(signal.origin == SIGNAL_ORIGIN_ICT || signal.origin == SIGNAL_ORIGIN_BOTH)
         distance_cap_basis = g_Max_Entry_Distance_Relaxed_Cap;
      double distance_cap_pct = MathMin(2.0, MathMax(0.80, distance_cap_basis));
      if(entry_distance_pct > distance_cap_pct)
      {
         if(pending_capable)
         {
            Log(LOG_INFO, "ExecuteTrade", symbol +
                " - Entry far from market (" + DoubleToString(entry_distance_pct, 2) +
                "% > cap " + DoubleToString(distance_cap_pct, 2) +
                "%), preserving signal for pending execution path");
         }
         else
         {
            RecordRejectReason("EXECQ:EntryTooFar");
            Log(LOG_WARNING, "ExecuteTrade", symbol +
                " - Entry too far from market (" + DoubleToString(entry_distance_pct, 2) +
                "% > cap " + DoubleToString(distance_cap_pct, 2) + "%), rejecting signal");
            return false;
         }
      }
   }

   int queue_symbol_index = symbol_index;
   if(queue_symbol_index < 0 || queue_symbol_index >= g_symbols_count ||
      g_symbols[queue_symbol_index].name != symbol)
   {
      queue_symbol_index = GetSymbolIndex(symbol);
   }
   if(queue_symbol_index < 0 || queue_symbol_index >= g_symbols_count)
   {
      RecordRejectReason("EXECQ:SymbolIndexMissing");
      Log(LOG_WARNING, "ExecuteTrade", symbol + " - Symbol index not found; skipping queue");
      return false;
   }

   int queued_direction_index = FindQueuedTradeByDirection(symbol, signal.direction);
   if(queued_direction_index >= 0)
   {
      RecordRejectReason("EXECQ:DuplicateQueuedSignal");
      int queued_attempt = g_trade_retries[queued_direction_index].attempt;
      int queued_age = (g_trade_retries[queued_direction_index].created_time > 0 ?
                        (int)(now - g_trade_retries[queued_direction_index].created_time) : -1);
      datetime queued_next = g_trade_retries[queued_direction_index].next_retry;
      STradingSignal existing_queued_signal = g_trade_retries[queued_direction_index].signal;

      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0)
         point = Point();
      double level_tol = (point > 0.0 ? point * 2.0 : 0.0);
      bool same_levels = false;
      if(level_tol > 0.0)
      {
         same_levels = (MathAbs(existing_queued_signal.entry_price - signal.entry_price) <= level_tol &&
                        MathAbs(existing_queued_signal.stop_loss - signal.stop_loss) <= level_tol &&
                        MathAbs(existing_queued_signal.take_profit - signal.take_profit) <= level_tol);
      }

      if(same_levels)
      {
         Log(LOG_INFO, "ExecuteTrade", symbol + " - Duplicate signal already queued, skipping" +
             " (attempt=" + IntegerToString(queued_attempt) +
             ", age=" + IntegerToString(queued_age) + "s" +
             ", next=" + TimeToString(queued_next) + ")");
         return false;
      }

      if(signal.signal_time > 0 && existing_queued_signal.signal_time > 0 &&
         signal.signal_time <= existing_queued_signal.signal_time)
      {
         Log(LOG_INFO, "ExecuteTrade", symbol +
             " - New signal older/equal to queued signal; keeping existing queue " +
             "(new=" + TimeToString(signal.signal_time) + ", queued=" + TimeToString(existing_queued_signal.signal_time) + ")");
         return false;
      }

      ulong prev_fp = g_trade_retries[queued_direction_index].signal_fingerprint;
      if(prev_fp == 0)
         prev_fp = ComputeSignalFingerprint(existing_queued_signal, symbol);
      ulong new_fp = ComputeSignalFingerprint(queued_signal, symbol);

      // BUG FIX C2: Queue refresh - preserve created_time for signal age calculation
      // Only refresh execution-related fields, NOT timing fields that affect signal age validation
      datetime original_created_time = g_trade_retries[queued_direction_index].created_time;
      
      // Keep exactly one active queued trade per symbol+direction by refreshing it with the latest
      // execution-adjusted signal metadata (for example NewsMult tags).
      g_trade_retries[queued_direction_index].signal = queued_signal;
      g_trade_retries[queued_direction_index].symbol_index = queue_symbol_index;
      g_trade_retries[queued_direction_index].attempt = 0;
      g_trade_retries[queued_direction_index].next_retry = now;
      // DO NOT reset created_time - preserve original for SignalAge calculations
      g_trade_retries[queued_direction_index].created_time = original_created_time;
      g_trade_retries[queued_direction_index].signal_fingerprint = new_fp;
      // FIX #3: Reset ticket fields on queue refresh
      g_trade_retries[queued_direction_index].ticket = 0;
      g_trade_retries[queued_direction_index].order_placed = false;
      g_trade_retries[queued_direction_index].last_ticket_check_time = 0;
      Log(LOG_INFO, "ExecuteTrade", symbol + " - Refreshed queued " +
          (signal.direction == 1 ? "BUY" : "SELL") +
          " signal (replaced older queued levels, previous attempt=" +
          IntegerToString(queued_attempt) + ", age=" + IntegerToString(queued_age) + "s)");
      if(g_Enable_Institutional_Debug && prev_fp != new_fp)
      {
         Log(LOG_DEBUG, "ExecuteTrade", symbol + " - Queue refresh fingerprint " +
              StringFormat("%I64u", prev_fp) + " -> " + StringFormat("%I64u", new_fp));
      }

      bool refresh_admitted = FinalizeQueuedTradeAdmission(queued_direction_index, now);
      if(refresh_admitted)
      {
         g_debug_counters.trades_queued++;
         AuditLogSignal("QUEUE_REFRESH", symbol, queued_signal,
                        "PrevAttempt=" + IntegerToString(queued_attempt) +
                        " AgeSec=" + IntegerToString(queued_age) +
                        " SigFP=" + StringFormat("%I64u", new_fp));
      }
      return refresh_admitted;
   }

   // Recheck symbol exposure just before queuing to catch race conditions.
   int final_position_count = CountOurOpenPositions(symbol);
   int final_pending_count = CountOurPendingOrders(symbol);
   if(ExposureGateOn() && (final_position_count + final_pending_count) >= MAX_TRADES_PER_SYMBOL)
   {
      RecordRejectReason("EXECQ:SymbolExposureLimitAtQueue");
      Log(LOG_WARNING, "ExecuteTrade", symbol + " - Symbol exposure limit reached at queueing (positions=" +
          IntegerToString(final_position_count) + ", pending=" + IntegerToString(final_pending_count) +
          ", limit=" + IntegerToString(MAX_TRADES_PER_SYMBOL) + ")");
      return false;
   }

   // BUG FIX C1: Capture index BEFORE increment to ensure consistent access
   int queue_index = g_retry_count;  // CAPTURE NOW
   
   // Populate array at captured index
   g_trade_retries[queue_index].symbol = symbol;
   g_trade_retries[queue_index].signal = queued_signal;
   g_trade_retries[queue_index].symbol_index = queue_symbol_index;
   g_trade_retries[queue_index].attempt = 0;
   g_trade_retries[queue_index].next_retry = TimeCurrent();
   g_trade_retries[queue_index].created_time = TimeCurrent();
   g_trade_retries[queue_index].signal_fingerprint = ComputeSignalFingerprint(queued_signal, symbol);
   // FIX #3: Initialize ticket fields
   g_trade_retries[queue_index].ticket = 0;
   g_trade_retries[queue_index].order_placed = false;
   g_trade_retries[queue_index].last_ticket_check_time = 0;
   
   // BUG FIX C1: Increment LAST for atomic operation
   g_retry_count++;
   // Sanity check (should not fail now since we pre-checked bounds)
   if(g_retry_count < 1 || g_retry_count > MAX_RETRY_QUEUE)
   {
      Log(LOG_ERROR, "ExecuteTrade", "CRITICAL: Retry count overflow after increment: " + IntegerToString(g_retry_count));
      g_retry_count = MathMax(1, MathMin(g_retry_count, MAX_RETRY_QUEUE));
      return false;
   }
   
   ulong staged_signal_fp = g_trade_retries[queue_index].signal_fingerprint;
   int staged_queue_depth = g_retry_count;
   bool admission_ok = FinalizeQueuedTradeAdmission(queue_index, now);
   if(!admission_ok)
      return false;

   g_debug_counters.trades_queued++;

   // ===== SIGNAL DEPOSIT CONFIRMATION =====
   // Log successful deposit only after the queued signal is accepted by the execution pipeline.
   string deposit_confirmation = StringFormat(
      "%s (%s) | Direction: %s | Entry: %.5f | SL: %.5f | TP: %.5f | RR: %.2f | Queue Depth: %d/%d | Staged Depth: %d/%d",
      symbol,
      SignalOriginToString(queued_signal.origin),
      (queued_signal.direction == 1 ? "BUY" : "SELL"),
      queued_signal.entry_price,
      queued_signal.stop_loss,
      queued_signal.take_profit,
      queued_signal.risk_reward_ratio,
      g_retry_count,
      MAX_RETRY_QUEUE,
      staged_queue_depth,
      MAX_RETRY_QUEUE
   );
     
   Log(LOG_INFO, "SignalDepositQueue", "Confirmed: " + deposit_confirmation);
   AuditLogSignal("QUEUE", symbol, queued_signal,
                  "Queue=" + IntegerToString(g_retry_count) +
                  " StagedQueue=" + IntegerToString(staged_queue_depth) +
                  " SigFP=" + StringFormat("%I64u", staged_signal_fp) +
                  " Origin=" + SignalOriginToString(queued_signal.origin));

   return true;
}


bool ProcessTradeRetry(STradeRetry &retry)
{
   string symbol = retry.symbol;
   STradingSignal signal = retry.signal;
   datetime now = TimeCurrent();
   const int KIM_STALE_FAR_ENTRY_SECONDS = 15 * 60;
   int retry_age_seconds = (retry.created_time > 0 ? (int)(now - retry.created_time) : 0);
   bool is_kim_signal = (signal.origin == SIGNAL_ORIGIN_KIMANIZ);
   bool allow_countertrend_retry = IsCountertrendRetracementSignal(signal);
   int symbol_index = retry.symbol_index;
   if(symbol_index < 0 || symbol_index >= g_symbols_count ||
      g_symbols[symbol_index].name != symbol)
   {
      symbol_index = GetSymbolIndex(symbol);
      retry.symbol_index = symbol_index;
   }
   int retry_interval = MathMax(1, g_Retry_Interval_Seconds);
   int defer_short = MathMax(5, retry_interval * 2);
   int defer_medium = MathMax(30, retry_interval * 10);

   if(g_Enable_Institutional_Debug && signal.origin == SIGNAL_ORIGIN_ICT && signal.direction == -1)
   {
      Log(LOG_INFO, "ProcessTradeRetry", symbol + " - DEBUG ICT Launching a SELL trade (execution attempt " +
          IntegerToString(retry.attempt + 1) + ")");
   }

   string shape_reason = "";
   if(!IsSignalTradeShapeValid(signal, shape_reason))
   {
      RecordRejectReason("RETRY:MalformedSignal_" + shape_reason);
      Log(LOG_ERROR, "ProcessTradeRetry", symbol + " - malformed queued signal: " + shape_reason);
      retry.attempt = g_Max_Retry_Attempts;
      return false;
   }

   ulong expected_fp = retry.signal_fingerprint;
   ulong actual_fp = ComputeSignalFingerprint(signal, symbol);
   if(expected_fp == 0)
   {
      // MEDIUM FIX: Stricter fingerprint validation - log backward-compat path
      if(g_debug_signals_enabled)
         Log(LOG_WARNING, "ProcessTradeRetry", symbol + " - No fingerprint in queue; using actual from current signal (signal drift risk)");
      // Backward-compatible: older queued entries may not have fingerprints.
      retry.signal_fingerprint = actual_fp;
      expected_fp = actual_fp;
   }
   if(actual_fp != expected_fp)
   {
      RecordRejectReason("RETRY:SignalMutated");
      Log(LOG_ERROR, "ProcessTradeRetry", symbol +
          " - queued signal fingerprint mismatch; dropping (expected=" +
          StringFormat("%I64u", expected_fp) + ", actual=" +
          StringFormat("%I64u", actual_fp) + ")");
      retry.attempt = g_Max_Retry_Attempts;
      return false;
   }
   ulong signal_fp = expected_fp;

   if(signal.signal_time <= 0)
   {
      RecordRejectReason("RETRY:SignalTimeMissing");
      Log(LOG_ERROR, "ProcessTradeRetry", symbol + " - queued signal missing signal_time; dropping");
      retry.attempt = g_Max_Retry_Attempts;
      return false;
   }
   if(signal.signal_time > (now + 5))
   {
      RecordRejectReason("RETRY:SignalTimeFuture");
      Log(LOG_ERROR, "ProcessTradeRetry", symbol +
          " - queued signal time in the future (" + TimeToString(signal.signal_time) + "); dropping");
      retry.attempt = g_Max_Retry_Attempts;
      return false;
   }
   
   // BUG FIX 1.6: Signal Age Decay Check - reject stale signals with DECREASING tolerance (not increasing!)
   // Original bug: max_allowed_age = max_queue_age_seconds * (1 + MathMin(retry.attempt, 3))
   // This INCREASED tolerance with retry attempts, allowing 20-minute-old signals (attempt 3 = 4x timeout)
   // Fix: Use constant timeout, or DECREASE tolerance with more attempts
   int max_queue_age_seconds = MathMax(60, g_Max_Queued_Signal_Age_Minutes * 60);
   int max_allowed_age = max_queue_age_seconds;  // Fixed timeout, not scaled by attempts
   
   if(retry_age_seconds > max_allowed_age)
   {
      RecordRejectReason("RETRY:SignalTooStaleAtExecution");
      Log(LOG_WARNING, "ProcessTradeRetry", symbol +
          " - Queued signal too stale to execute (age=" + IntegerToString(retry_age_seconds) + 
          "s, max=" + IntegerToString(max_allowed_age) + "s, attempts=" +
          IntegerToString(retry.attempt) + ") → removing from queue");
      retry.attempt = g_Max_Retry_Attempts;
      return false;
   }
   if(retry.created_time > 0 && signal.signal_time > (retry.created_time + 5))
   {
      RecordRejectReason("RETRY:SignalTimeAfterQueue");
      Log(LOG_ERROR, "ProcessTradeRetry", symbol +
          " - queued signal time is after queue creation; dropping");
      retry.attempt = g_Max_Retry_Attempts;
      return false;
   }
   {
      int max_age_seconds = MathMax(60, g_Max_Queued_Signal_Age_Minutes * 60);
      int signal_age = (int)(now - signal.signal_time);
      if(signal_age > max_age_seconds)
      {
         RecordRejectReason("RETRY:SignalStale");
         Log(LOG_WARNING, "ProcessTradeRetry", symbol +
             " - queued signal stale (age=" + IntegerToString(signal_age) +
             "s, max=" + IntegerToString(max_age_seconds) + "s); dropping");
         retry.attempt = g_Max_Retry_Attempts;
         return false;
      }
   }

   if(g_Enable_Institutional_Debug && StringFind(signal.reason, "PreEntry=") >= 0)
   {
      Log(LOG_INFO, "ProcessTradeRetry", symbol +
          " - DEBUG re-testing pre-entry signal through normal execution pipeline");
   }

   // Hard directional revalidation at execution time.
   // Drop normal queued signals immediately if HTF/Trend direction changed or turned neutral.
   // Countertrend retracements may legitimately execute while HTF reads neutral; the
   // Signal_TF confirmation below is the execution-time guard for those setups.
   int trend_direction_now = GetHTFBiasInstitutional(symbol);
   int retry_auto_mode = ExtractAutoModeFromSignalReason(signal.reason);
   bool allow_range_retry =
      (g_Allow_Range_Trading || retry_auto_mode == AUTO_REGIME_MODE_INTRA_HIGHLOW);

   int htf_bias_now = trend_direction_now;

   if(htf_bias_now != 0 && signal.direction != htf_bias_now)
   {
      if(!allow_countertrend_retry)
      {
         RecordRejectReason("RETRY:HTFBiasMismatchNow");
         Log(LOG_INFO, "ProcessTradeRetry", symbol + " - Dropping queued " +
             (signal.direction == 1 ? "BUY" : "SELL") +
             " signal due to HTF bias mismatch (bias now " +
             (htf_bias_now == 1 ? "BUY" : "SELL") + ")");
         retry.attempt = g_Max_Retry_Attempts;
         return false;
      }
   }

   if(!allow_range_retry && trend_direction_now == 0 && !allow_countertrend_retry)
   {
      RecordRejectReason("RETRY:TrendNeutralNow");
      Log(LOG_INFO, "ProcessTradeRetry", symbol + " - Dropping queued " +
          (signal.direction == 1 ? "BUY" : "SELL") +
          " signal: calculated trend became neutral");
      retry.attempt = g_Max_Retry_Attempts;
      return false;
   }
   else if(!allow_range_retry && trend_direction_now == 0 && allow_countertrend_retry && g_Enable_Institutional_Debug)
   {
      Log(LOG_DEBUG, "ProcessTradeRetry", symbol +
          " - Neutral trend tolerated for countertrend retracement; Signal_TF confirmation remains active");
   }
   if(trend_direction_now != 0 && trend_direction_now != signal.direction)
   {
      if(!allow_countertrend_retry)
      {
         RecordRejectReason("RETRY:TrendMismatchNow");
         Log(LOG_INFO, "ProcessTradeRetry", symbol + " - Dropping queued " +
             (signal.direction == 1 ? "BUY" : "SELL") +
             " signal due to Trend_TF mismatch (trend now " +
             (trend_direction_now == 1 ? "BUY" : "SELL") + ")");
         retry.attempt = g_Max_Retry_Attempts;
         return false;
      }
   }

   if(allow_countertrend_retry)
   {
      int signal_tf_direction_now = StructureToDirection(DetectMarketStructure(symbol, Signal_TF));
      if(signal_tf_direction_now != signal.direction)
      {
         RecordRejectReason("RETRY:CountertrendSignalTFLost");
         Log(LOG_INFO, "ProcessTradeRetry", symbol + " - Dropping queued " +
             (signal.direction == 1 ? "BUY" : "SELL") +
             " KImaniz countertrend retracement: Signal_TF no longer confirms direction");
         retry.attempt = g_Max_Retry_Attempts;
         return false;
      }
   }
   
   CSymbolInfo sym;
   if(!sym.Name(symbol))
   {
      RecordRejectReason("RETRY:SymbolInitFailed");
      Log(LOG_ERROR, "ProcessTradeRetry", "Failed to initialize symbol: " + symbol);
      retry.attempt = g_Max_Retry_Attempts;
      return false;
   }
   
   if(!sym.RefreshRates())
   {
      RecordRejectReason("RETRY:RefreshRatesFailed");
      Log(LOG_ERROR, "ProcessTradeRetry", "Failed to refresh rates for " + symbol);
      retry.next_retry = now + defer_short;
      return false;
   }

   if(g_Enable_Execution_Latency_Guard && g_Max_Tick_Age_Seconds > 0)
   {
      MqlTick tick;
      if(!SymbolInfoTick(symbol, tick) || tick.time <= 0)
      {
         RecordRejectReason("EXECQ:TickMissing");
         Log(LOG_WARNING, "ProcessTradeRetry", symbol + " - Unable to retrieve tick for latency guard; deferring execution");
         AuditLog("EXECQ_STALE_TICK", symbol, "Tick unavailable; deferred");
         retry.next_retry = now + defer_short;
         g_exec_latency_blocks++;
         return false;
      }

      int tick_age = (int)(now - tick.time);
      if(tick_age < 0)
         tick_age = 0;
      if(tick_age > g_Max_Tick_Age_Seconds)
      {
         string msg = symbol + " - Stale tick (" + IntegerToString(tick_age) + "s > " +
                      IntegerToString(g_Max_Tick_Age_Seconds) + "s), deferring execution";
         RecordRejectReason("EXECQ:StaleTick");
         Log(LOG_WARNING, "ProcessTradeRetry", msg);
         AuditLog("EXECQ_STALE_TICK", symbol, msg);
         retry.next_retry = now + MathMax(defer_short, g_Max_Tick_Age_Seconds);
         g_exec_latency_blocks++;
         return false;
      }
   }

   datetime shared_defer = 0;
   if(!ApplySharedTradeGates(symbol, allow_range_retry, true, now, defer_short, defer_medium,
                             GATE_CHECK_TRADE_ALLOWED | GATE_CHECK_DRAWDOWN,
                             shared_defer, "ProcessTradeRetry", "RETRY"))
   {
      if(shared_defer > 0)
         retry.next_retry = shared_defer;
      return false;
   }

   double current_bid = sym.Bid();
   double current_ask = sym.Ask();
   if(current_bid <= 0 || current_ask <= 0 || current_bid >= current_ask)
   {
      RecordRejectReason("RETRY:InvalidPrices");
      Log(LOG_ERROR, "ProcessTradeRetry", "Invalid prices for " + symbol + ": Bid=" + DoubleToString(current_bid, 5) + ", Ask=" + DoubleToString(current_ask, 5));
      retry.next_retry = now + defer_short;
      return false;
   }
   
   int digits = (int)sym.Digits();
   double point = sym.Point();
   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0)
      tick_size = point;
   double pip_size = GetPipSize(symbol);
   if(pip_size <= 0.0)
      pip_size = point;
   if(digits <= 0 || point <= 0)
   {
      RecordRejectReason("RETRY:InvalidSymbolProperties");
      Log(LOG_ERROR, "ProcessTradeRetry", "Invalid symbol properties for " + symbol);
      retry.next_retry = now + defer_medium;
      return false;
   }
   
   // ===== FIX 1: ENTRY PRICE STALENESS CHECK =====
   double signal_age_seconds = (int)(now - signal.signal_time);
   if(signal_age_seconds > 15)
   {
      double current_ref_price = (signal.direction == 1 ? current_ask : current_bid);
      if(current_ref_price > 0 && signal.entry_price > 0)
      {
         double entry_drift_pct = MathAbs(signal.entry_price - current_ref_price) / current_ref_price * 100;
         if(entry_drift_pct > 1.0)
         {
            Log(LOG_WARNING, "ProcessTradeRetry", symbol + 
                " - Stale entry price detected: age=" + IntegerToString((int)signal_age_seconds) + 
                "s, entry_drift=" + DoubleToString(entry_drift_pct, 2) + "%, " +
                "signal.entry=" + DoubleToString(signal.entry_price, digits) + 
                ", current_ref=" + DoubleToString(current_ref_price, digits));
            AuditLogSignal("ENTRY_STALE_DETECTED", symbol, signal, 
                          "Drift " + DoubleToString(entry_drift_pct, 2) + "%");
         }
      }
   }
   // ===== END FIX 1 =====
   
   if(IsLossCooldownActive())
   {
      RecordRejectReason("RETRY:LossCooldown");
      Log(LOG_WARNING, "ProcessTradeRetry", symbol + " - Loss cooldown active, skipping execution");
      retry.next_retry = (g_risk_cooldown_until > now ? g_risk_cooldown_until : now + defer_medium);
      return false;
   }

   if(IsSymbolLossCooldownActive(symbol))
   {
      RecordRejectReason("RETRY:SymbolLossCooldown");
      Log(LOG_WARNING, "ProcessTradeRetry", symbol + " - Symbol loss cooldown active, skipping execution");
      int symbol_index_cooldown = GetSymbolIndex(symbol);
      datetime symbol_defer = now + defer_medium;
      if(symbol_index_cooldown >= 0 && symbol_index_cooldown < MAX_SYMBOLS &&
         g_symbol_loss_cooldown_until[symbol_index_cooldown] > now)
      {
         symbol_defer = g_symbol_loss_cooldown_until[symbol_index_cooldown];
      }
      retry.next_retry = symbol_defer;
      return false;
   }
   
   if(!IsMarketOpen(symbol))
   {
      RecordRejectReason("RETRY:MarketClosed");
      Log(LOG_INFO, "ProcessTradeRetry", symbol + " - Market closed, delaying execution");
      retry.next_retry = now + 60;
      return false;
   }
   
   if(!IsWithinTradingSession())
   {
      RecordRejectReason("RETRY:OutsideSession");
      Log(LOG_INFO, "ProcessTradeRetry", symbol + " - Outside trading session, delaying execution");
      retry.next_retry = now + 60;
      return false;
   }

   shared_defer = 0;
   if(!ApplySharedTradeGates(symbol, allow_range_retry, true, now, defer_short, defer_medium,
                             GATE_CHECK_GOLD | GATE_CHECK_SPREAD |
                             GATE_CHECK_DAILY_CAP | GATE_CHECK_RANGE,
                             shared_defer, "ProcessTradeRetry", "RETRY"))
   {
      if(shared_defer > 0)
         retry.next_retry = shared_defer;
      return false;
   }

   int concurrent_limit = MathMax(1, g_Max_Concurrent_Trades_Effective);
   int our_positions_live = CountOurOpenPositions();
   int our_pending_live = CountOurPendingOrders();
   int concurrent_slots_live = our_positions_live + our_pending_live;
   if(CGateController::IsExposureGateEnabled() && concurrent_slots_live >= concurrent_limit)
   {
      RecordRejectReason("RETRY:MaxConcurrentTrades");
      retry.next_retry = now + defer_medium;
      static datetime last_max_concurrent_retry_log = 0;
      if(last_max_concurrent_retry_log == 0 || (now - last_max_concurrent_retry_log) >= 20)
      {
         Log(LOG_INFO, "ProcessTradeRetry", symbol + " - Max concurrent trades gate active, deferring retry (" +
             IntegerToString(concurrent_slots_live) + "/" + IntegerToString(concurrent_limit) +
             ", open=" + IntegerToString(our_positions_live) +
             ", pending=" + IntegerToString(our_pending_live) +
             ", input=" + IntegerToString(Max_Concurrent_Trades) +
             ", profile=" + g_Live_Risk_Profile_Name + ")");
         last_max_concurrent_retry_log = now;
      }
      return false;
   }
   
   // --- FIX START ---
   // Calculate original risk and reward distances from the signal.
   // These distances are the intended risk/reward, which we will apply to the real execution price.
   double stop_loss_distance = MathAbs(signal.entry_price - signal.stop_loss);
   double take_profit_distance = MathAbs(signal.take_profit - signal.entry_price);

   if(stop_loss_distance <= point) // Ensure distance is at least one point
   {
       RecordRejectReason("RETRY:InvalidStopDistance");
       Log(LOG_ERROR, "ProcessTradeRetry", symbol + " - Invalid stop loss distance from signal. Must be > 0.");
       retry.attempt = g_Max_Retry_Attempts; // Permanent signal defect; remove immediately.
       return false; // Fatal error for this signal, cannot proceed.
   }

   if(take_profit_distance <= point)
   {
      RecordRejectReason("RETRY:InvalidTakeProfitDistance");
      Log(LOG_ERROR, "ProcessTradeRetry", symbol + " - Invalid take-profit distance from signal. Must be > 0.");
      retry.attempt = g_Max_Retry_Attempts;
      return false;
   }
   // --- FIX END ---

   // Calculate position size based on the intended risk distance
   double adaptive_risk = GetAdaptiveRiskCached();
   // I5 FIX: Extract regime with validation and logging
   double regime_risk_multiplier = 1.0;
   string detected_regime = "";
   
   if(StringFind(signal.reason, "AutoRegime=TREND") >= 0 ||
      StringFind(signal.reason, "SuitabilityRole=TREND") >= 0)
   {
      regime_risk_multiplier = g_Regime_Risk_Multiplier_Trend;
      detected_regime = "TREND";
   }
   else if(StringFind(signal.reason, "AutoRegime=RANGE") >= 0 ||
           StringFind(signal.reason, "SuitabilityRole=RANGE") >= 0)
   {
      regime_risk_multiplier = g_Regime_Risk_Multiplier_Range;
      detected_regime = "RANGE";
   }
   else if(StringFind(signal.reason, "AutoRegime=RETRACEMENT") >= 0 ||
           StringFind(signal.reason, "SuitabilityRole=RETRACEMENT") >= 0)
   {
      regime_risk_multiplier = g_Regime_Risk_Multiplier_Retracement;
      detected_regime = "RETRACEMENT";
   }
   else
   {
      // Regime not detected in signal reason - use safe default
      Log(LOG_WARNING, "ProcessTradeRetry", symbol + " - Regime not detected in signal reason, using neutral 1.0x");
      detected_regime = "UNDETECTED";
   }
   
   // Validate extracted regime multiplier
   if(!MathIsValidNumber(regime_risk_multiplier))
   {
      Log(LOG_WARNING, "ProcessTradeRetry", symbol + " - Regime multiplier is NaN for " + detected_regime + ", using 1.0x");
      regime_risk_multiplier = 1.0;
   }

   double director_lot_multiplier = ExtractTaggedNumericValue(signal.reason, "DirectorLotMult=", 1.0);
   
   // I4 FIX: Validate director multiplier for NaN/Infinity BEFORE bounding
   if(!MathIsValidNumber(director_lot_multiplier))
   {
      Log(LOG_WARNING, "ProcessTradeRetry", symbol + " - Director lot multiplier is NaN (corrupted signal), using default 1.0");
      director_lot_multiplier = 1.0;
   }
   
   director_lot_multiplier = MathMax(0.25, MathMin(3.00, director_lot_multiplier));
   double total_risk_multiplier = regime_risk_multiplier * director_lot_multiplier;
   
   // I3 FIX: Log compound multiplier effect for visibility
   double pre_adaptive_risk = adaptive_risk;
   adaptive_risk = MathClamp(adaptive_risk * total_risk_multiplier, 0.10, 10.0);
   double post_adaptive_risk = adaptive_risk;
   
   if(g_Enable_Institutional_Debug &&
      (MathAbs(total_risk_multiplier - 1.0) > 0.001 || MathAbs(pre_adaptive_risk - post_adaptive_risk) > 0.001))
   {
      Log(LOG_DEBUG, "ProcessTradeRetry",
          symbol + " - I3: Compound multiplier effect: regime=" + DoubleToString(regime_risk_multiplier, 2) +
          "x director=" + DoubleToString(director_lot_multiplier, 2) +
          "x total=" + DoubleToString(total_risk_multiplier, 2) +
          "x (adaptive risk " + DoubleToString(pre_adaptive_risk, 2) + "% -> " + DoubleToString(post_adaptive_risk, 2) + "%)");
   }
   else if(!g_Enable_Institutional_Debug && total_risk_multiplier != 1.0)
   {
      Log(LOG_DEBUG, "ProcessTradeRetry", symbol + " - Risk multipliers: " + DoubleToString(total_risk_multiplier, 2) + "x");
   }
   
   // ===== FIX #1: PASS ACTUAL PRICES FOR TRUE RR CALCULATION =====
   double base_lot_size = CalculatePositionSize(symbol, stop_loss_distance, adaptive_risk, signal.ai_confidence,
                                                 signal.entry_price, signal.stop_loss, signal.take_profit, signal.direction);
   
   if(base_lot_size <= 0)
   {
      string lot_reason = g_last_position_size_reason;
      if(StringLen(lot_reason) <= 0)
         lot_reason = "unknown";

      RecordRejectReason("RETRY:BaseLotInvalid_" + lot_reason);

      if(lot_reason == "below_min_lot_overrisk" || lot_reason == "margin_reduced_below_min_lot_overrisk")
      {
         Log(LOG_WARNING, "ProcessTradeRetry", symbol +
             " - Base lot invalid (permanent): " + lot_reason +
             " | raw=" + DoubleToString(g_last_position_size_raw_lot, 4) +
             " min=" + DoubleToString(g_last_position_size_min_lot, 2) +
             " | removing from retry queue");
         retry.attempt = g_Max_Retry_Attempts; // Force immediate removal by caller.
      }
      else
      {
         Log(LOG_ERROR, "ProcessTradeRetry", symbol +
             " - Invalid base lot size: " + DoubleToString(base_lot_size, 4) +
             " | reason=" + lot_reason);
         retry.next_retry = now + defer_medium;
      }
      return false;
   }
   
   double lot_size = base_lot_size;
   
   // ===== TIER 1B ENHANCEMENT: CONFIDENCE ROUTING & POSITION SIZING =====
   // Apply confidence-weighted position sizing based on signal quality
   // Strong signals get 1.25x multiplier, weak signals get 0.6x  or skip entirely
   double confidence_multiplier = 1.0;
   {
      // Calculate fused confidence from all signal sources (ICT/AI/KImaniz)
      double ict_confidence = (signal.origin == SIGNAL_ORIGIN_ICT ? 0.75 : 
                               signal.origin == SIGNAL_ORIGIN_BOTH ? 0.85 : 0.50);
      double ai_confidence = signal.ai_confidence;  // Already computed in signal 
      double kim_confidence = (signal.origin == SIGNAL_ORIGIN_KIMANIZ ? 0.70 : 0.50);
      
      // Fuse confidences with weighted averaging (higher if multiple sources agree)
      double fused_confidence;
      if(signal.origin == SIGNAL_ORIGIN_BOTH)
         fused_confidence = 0.5 * ai_confidence + 0.5 * ict_confidence;
      else if(signal.origin == SIGNAL_ORIGIN_ICT)
         fused_confidence = ict_confidence;
      else if(signal.origin == SIGNAL_ORIGIN_AI)
         fused_confidence = ai_confidence;
      else if(signal.origin == SIGNAL_ORIGIN_KIMANIZ)
         fused_confidence = kim_confidence;
      else
         fused_confidence = 0.50;
      
      // Apply confidence-to-multiplier mapping
      if(fused_confidence >= 0.75)
         confidence_multiplier = 1.25;  // High confidence: 25% position boost
      else if(fused_confidence >= 0.55)
         confidence_multiplier = 1.0;   // Normal confidence: standard sizing
      else if(fused_confidence >= 0.35)
         confidence_multiplier = 0.6;   // Low confidence: 40% position reduction
      else
      {
         // Very low confidence is a property of the queued signal, not a transient broker condition.
         // Drop it immediately instead of burning retry slots on a static reject.
         Log(LOG_DEBUG, "ProcessTradeRetry", symbol + 
             " - Dropping queued trade due to very low confidence: " + DoubleToString(fused_confidence, 2));
         RecordRejectReason("RETRY:LowConfidence");
         retry.attempt = g_Max_Retry_Attempts;
         return false;
      }
      
      lot_size = base_lot_size * confidence_multiplier;
      
        if(g_Enable_Institutional_Debug)
          Log(LOG_DEBUG, "ProcessTradeRetry", symbol + 
              " - Tier 1B: Confidence routing applied (fused_conf=" + DoubleToString(fused_confidence, 2) +
              ", multiplier=" + DoubleToString(confidence_multiplier, 2) +
              ", lot=" + DoubleToString(lot_size, 4) + ")");
    }
    // ===== END TIER 1B =====

    // ===== TIER 3C ENHANCEMENT: NEWS SIZE ADJUSTMENT =====
    double news_multiplier = ExtractTaggedNumericValue(signal.reason, "NewsMult=", 1.0);
    if(news_multiplier < 1.0)
    {
       news_multiplier = MathMax(0.10, MathMin(1.0, news_multiplier));
       double pre_news_lot = lot_size;
       lot_size *= news_multiplier;
        if(g_Enable_Institutional_Debug)
          Log(LOG_DEBUG, "ProcessTradeRetry", symbol +
              " - Tier 3C: News multiplier applied (x" + DoubleToString(news_multiplier, 2) +
              ", lot=" + DoubleToString(pre_news_lot, 4) + "->" + DoubleToString(lot_size, 4) + ")");
    }
    // ===== END TIER 3C =====

    // Normalize volume after confidence scaling to avoid invalid volume retcodes.
   double pre_norm_lot = lot_size;
   string lot_norm_reason = "";
   if(!NormalizeLotToBroker(symbol, lot_size, lot_norm_reason))
   {
      RecordRejectReason("RETRY:LotNormalizeFailed_" + lot_norm_reason);
      Log(LOG_ERROR, "ProcessTradeRetry", symbol +
          " - Lot normalization failed. Raw=" + DoubleToString(pre_norm_lot, 4) +
          " Reason=" + lot_norm_reason);
      retry.attempt = g_Max_Retry_Attempts;
      return false;
   }
   if(MathAbs(lot_size - pre_norm_lot) > 1e-8)
   {
      Log(LOG_DEBUG, "ProcessTradeRetry", symbol +
          " - Lot normalized from " + DoubleToString(pre_norm_lot, 4) +
          " to " + DoubleToString(lot_size, 4));
   }

   // Prepare trade
   int magic_number = GetUniqueMagicNumber(symbol, signal.direction);
   trade.SetExpertMagicNumber(magic_number);
   double execution_slippage_pips = g_Execution_Max_Slippage_Pips;
   if(execution_slippage_pips < 0.0)
      execution_slippage_pips = 0.0;
   trade.SetDeviationInPoints(PipsToPoints(symbol, execution_slippage_pips));
   int max_acceptable_slippage_points = (execution_slippage_pips > 0.0 ?
                                         MathMax(1, PipsToPoints(symbol, execution_slippage_pips)) : 0);
   trade.SetTypeFilling(GetSymbolFillingMode(symbol));

   string comment = BuildExecutionComment(signal, symbol, magic_number, signal_fp);

   bool execution_result = false;
   string execution_type = "MARKET";
   double execution_price = 0;
   double expected_market_price = 0.0;
   double secondary_breakout_lot = 0.0;
   // Preserve the primary order request result before any optional secondary requests
   // (e.g., breakout companion pending) mutate CTrade's result buffers.
   bool primary_result_captured = false;
   int primary_result_retcode = 0;
   string primary_result_retcode_desc = "";
   ulong primary_result_order = 0;
   ulong primary_result_deal = 0;
   double primary_result_price = 0.0;
   
   // Validate position size is reasonable
   if(lot_size > SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX))
   {
      RecordRejectReason("RETRY:LotAboveMax");
      Log(LOG_WARNING, "ProcessTradeRetry", symbol + ": Position size exceeds maximum");
      retry.attempt = g_Max_Retry_Attempts; // Permanent sizing failure for this queued signal.
      return false;
   }
   
   // --- RECALCULATE SL/TP FOR MARKET EXECUTION ---
   double adjusted_sl = 0;
   double adjusted_tp = 0;
   
   // Get base SL/TP pips (use original distances)
   double base_sl_pips = stop_loss_distance / point;
   double base_tp_pips = take_profit_distance / point;
   
     // Use base pips for SL/TP calculation
     double adjusted_sl_pips = base_sl_pips;
     double adjusted_tp_pips = base_tp_pips;

     double desired_entry = NormalizeDouble(signal.entry_price, digits);
     int execution_preference = ExtractExecutionPreferenceFromSignalReason(signal.reason);
     bool use_market_execution = !g_Use_Pending_Orders;
     if(execution_preference == SIGNAL_EXEC_PREF_MARKET)
        use_market_execution = true;
     else if(execution_preference == SIGNAL_EXEC_PREF_PENDING)
        use_market_execution = false;
     bool explicit_pending_preference = (execution_preference == SIGNAL_EXEC_PREF_PENDING);

     bool require_pending_for_slippage = false;
     double entry_distance_pips = 0.0;
     if(g_Enable_Smart_Order_Routing && g_Execution_Max_Slippage_Pips > 0.0 &&
        desired_entry > 0.0 && pip_size > 0.0)
     {
        double ref_price = (signal.direction == 1 ? current_ask : current_bid);
        if(ref_price > 0.0)
        {
           entry_distance_pips = MathAbs(desired_entry - ref_price) / pip_size;
           if(entry_distance_pips > g_Execution_Max_Slippage_Pips)
           {
              require_pending_for_slippage = true;
              if(use_market_execution)
              {
                  if(g_Enable_Smart_Order_Routing ||
                     g_Use_Pending_Orders ||
                     execution_preference == SIGNAL_EXEC_PREF_PENDING)
                 {
                    use_market_execution = false;
                    g_exec_slippage_reroutes++;
                    string route_msg = symbol + " - Smart routing to pending: entry distance " +
                                       DoubleToString(entry_distance_pips, 1) + "p > max " +
                                       DoubleToString(g_Execution_Max_Slippage_Pips, 1) + "p";
                    Log(LOG_INFO, "ProcessTradeRetry", route_msg);
                    AuditLogSignal("EXECQ_ROUTE", symbol, signal, route_msg);
                 }
                 else
                 {
                    RecordRejectReason("EXECQ:SlippageRisk");
                    string block_msg = symbol + " - Slippage risk too high for market execution (" +
                                       DoubleToString(entry_distance_pips, 1) + "p > " +
                                       DoubleToString(g_Execution_Max_Slippage_Pips, 1) + "p); pending disabled";
                    Log(LOG_WARNING, "ProcessTradeRetry", block_msg);
                    AuditLogSignal("EXECQ_BLOCK", symbol, signal, block_msg);
                    retry.next_retry = now + defer_short;
                    return false;
                 }
              }
           }
        }
     }

     // ===== FIX 2: VALIDATE MARKET FALLBACK SLIPPAGE =====
      if(use_market_execution && signal.entry_price > 0.0 && max_acceptable_slippage_points > 0)
     {
        double fallback_entry_price = (signal.direction == 1 ? current_ask : current_bid);
        double fallback_slippage_pips = MathAbs(fallback_entry_price - signal.entry_price) / point;
         double max_fallback_slippage = max_acceptable_slippage_points * 1.5;
        
        if(fallback_slippage_pips > max_fallback_slippage)
        {
           RecordRejectReason("RETRY:FallbackSlippageExceeded");
           
           string msg = symbol + " - Market fallback would cause excessive slippage: " +
                       "Intended=" + DoubleToString(signal.entry_price, digits) + 
                       ", Fallback=" + DoubleToString(fallback_entry_price, digits) +
                       ", Slippage=" + DoubleToString(fallback_slippage_pips, 1) + 
                       "p (max " + DoubleToString(max_fallback_slippage, 1) + "p). " +
                       "Deferring execution.";
           
           Log(LOG_WARNING, "ProcessTradeRetry", msg);
           AuditLogSignal("EXECQ_FALLBACK_SLIP", symbol, signal, msg);
           
           retry.next_retry = now + 2;
           return false;
        }
        
         if(fallback_slippage_pips > max_acceptable_slippage_points)
        {
           Log(LOG_INFO, "ProcessTradeRetry", symbol +
               " - Market fallback accepted with elevated slippage: " + 
               DoubleToString(fallback_slippage_pips, 1) + "p (max " +
                DoubleToString(max_acceptable_slippage_points, 1) + "p)");
        }
     }
     // ===== END FIX 2 =====

     if(!use_market_execution)
    {
      // ===== PENDING ORDER EXECUTION =====
      // Use the strategy's computed entry for pending orders (ICT mitigation entries).

       ENUM_ORDER_TYPE_FILLING pending_fill = GetSymbolFillingMode(symbol);
       long fm = 0;
       if(SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE, fm))
       {
          if((fm & SYMBOL_FILLING_RETURN) == SYMBOL_FILLING_RETURN || fm == ORDER_FILLING_RETURN)
             pending_fill = ORDER_FILLING_RETURN;
       }
       trade.SetTypeFilling(pending_fill);

       // Minimum distance required for pending orders (broker constraint)
       int stop_level = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
       int freeze_level = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
       double min_pending_distance = MathMax((double)stop_level, (double)freeze_level) * point;
       if(min_pending_distance < point) min_pending_distance = point * 2;

       // Hard safety backstop: reject stale/invalid pending entries that are too far from market.
       double pending_ref_price = (signal.direction == 1 ? current_ask : current_bid);
       if(pending_ref_price > 0.0)
       {
          double pending_distance_pct = MathAbs(desired_entry - pending_ref_price) / pending_ref_price * 100.0;
           double pending_distance_cap_basis = g_Max_Entry_Distance_Pct;
           if(signal.origin == SIGNAL_ORIGIN_ICT || signal.origin == SIGNAL_ORIGIN_BOTH)
              pending_distance_cap_basis = g_Max_Entry_Distance_Relaxed_Cap;
           double pending_distance_cap_pct = MathMin(2.0, MathMax(0.80, pending_distance_cap_basis));
          if(pending_distance_pct > pending_distance_cap_pct)
          {
             bool trend_aligned_now = (trend_direction_now != 0 && trend_direction_now == signal.direction);

             // KImaniz stale-distance policy:
             // 1) If trend is still aligned, allow a 15-minute grace window.
             // 2) After 15 minutes, execute at market and rebase SL to an acceptable distance.
             if(is_kim_signal && trend_aligned_now)
             {
                if(retry_age_seconds < KIM_STALE_FAR_ENTRY_SECONDS)
                {
                   RecordRejectReason("RETRY:KIMPendingFarAwait15m");
                   retry.next_retry = now + MathMax(30, retry_interval * 2);
                   Log(LOG_INFO, "ProcessTradeRetry", symbol +
                       " - KImaniz trend-aligned far entry awaiting 15m grace window (age=" +
                       IntegerToString(retry_age_seconds) + "s, dist=" +
                       DoubleToString(pending_distance_pct, 2) + "% > cap " +
                       DoubleToString(pending_distance_cap_pct, 2) + "%)");
                   return false;
                }

                // Convert stale far-away KImaniz setup to market execution and normalize SL/TP.
                use_market_execution = true;
                execution_type = "MARKET (KIM STALE FAR ENTRY)";
                execution_price = (signal.direction == 1 ? current_ask : current_bid);

                double atr_now = GetATRValue(symbol, Signal_TF);
                if(atr_now <= 0.0 || !MathIsValidNumber(atr_now))
                   atr_now = MathMax(MathAbs(current_ask - current_bid) * 8.0, pending_ref_price * 0.0015);

                double spread_now = MathMax(point, MathAbs(current_ask - current_bid));
                double broker_min_sl_distance =
                   MathMax(MathMax((double)stop_level, (double)freeze_level) * point,
                           MathMax(point * 8.0, spread_now * 2.5));

                // Keep risk acceptable: cap stale oversized SL while respecting broker minima.
                double acceptable_sl_max = MathMax(broker_min_sl_distance, atr_now * 1.60);
                double rebased_sl_distance = MathMin(stop_loss_distance, acceptable_sl_max);
                if(rebased_sl_distance < broker_min_sl_distance)
                   rebased_sl_distance = broker_min_sl_distance;

                // P5: Validate Min_RR_Ratio before using in TP calculation
                double valid_min_rr = g_Min_RR_Ratio;
                if(!MathIsValidNumber(valid_min_rr) || valid_min_rr < 0.1 || valid_min_rr > 5.0)
                {
                   if(!MathIsValidNumber(valid_min_rr))
                      Log(LOG_WARNING, "ExecuteSignal", "g_Min_RR_Ratio is NaN, using default 1.50");
                   else if(valid_min_rr < 0.1)
                      Log(LOG_WARNING, "ExecuteSignal", "g_Min_RR_Ratio too low: " + DoubleToString(valid_min_rr, 2) + ", using 1.50");
                   else
                      Log(LOG_WARNING, "ExecuteSignal", "g_Min_RR_Ratio too high: " + DoubleToString(valid_min_rr, 2) + ", capping to 5.0");
                   valid_min_rr = MathMin(MathMax(valid_min_rr, 0.1), 5.0);
                   if(!MathIsValidNumber(valid_min_rr))
                      valid_min_rr = 1.50;
                }

                double rebased_tp_distance = MathMax(take_profit_distance, rebased_sl_distance * valid_min_rr);

                adjusted_sl_pips = rebased_sl_distance / point;
                adjusted_tp_pips = rebased_tp_distance / point;

                if(rebased_sl_distance > stop_loss_distance + point)
                {
                   // Recalculate adjusted prices based on rebased distances
                   double adjusted_entry_price = signal.entry_price;
                   double adjusted_sl_price = signal.entry_price + (signal.direction > 0 ? -rebased_sl_distance : rebased_sl_distance);
                   double adjusted_tp_price = signal.entry_price + (signal.direction > 0 ? rebased_tp_distance : -rebased_tp_distance);
                   
                   double resized_lot = CalculatePositionSize(symbol, rebased_sl_distance, adaptive_risk, signal.ai_confidence,
                                                              adjusted_entry_price, adjusted_sl_price, adjusted_tp_price, signal.direction);
                   if(resized_lot > 0.0)
                      lot_size = resized_lot;
                }

                Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                    " - KImaniz stale far-entry converted to market (age=" + IntegerToString(retry_age_seconds) +
                    "s, dist=" + DoubleToString(pending_distance_pct, 2) +
                    "%). SL rebased to acceptable distance=" + DoubleToString(adjusted_sl_pips, 1) + " points");
             }
             else if(explicit_pending_preference)
             {
                RecordRejectReason("RETRY:PendingEntryFarAwait");
                retry.next_retry = now + MathMax(15, retry_interval * 2);
                Log(LOG_INFO, "ProcessTradeRetry", symbol +
                    " - Pending-pref execution remains intentionally far from market; awaiting valid pending zone (age=" +
                    IntegerToString(retry_age_seconds) + "s, dist=" +
                    DoubleToString(pending_distance_pct, 2) + "% > cap " +
                    DoubleToString(pending_distance_cap_pct, 2) + "%)");
                return false;
             }
             else
             {
                RecordRejectReason("RETRY:PendingEntryTooFar");
                Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                    " - Pending entry rejected by hard-safety distance cap. Entry=" + DoubleToString(desired_entry, digits) +
                    ", RefPrice=" + DoubleToString(pending_ref_price, digits) +
                    ", Dist=" + DoubleToString(pending_distance_pct, 2) + "% > Cap=" +
                    DoubleToString(pending_distance_cap_pct, 2) + "%");
                retry.attempt = g_Max_Retry_Attempts; // stale signal; remove from queue immediately
                return false;
             }
          }
       }

       if(!use_market_execution)
       {
          if(signal.direction == 1) // BUY: limit below ask, stop above ask
          {
             if(desired_entry < (current_ask - min_pending_distance))
             {
                execution_type = "PENDING (BUY LIMIT)";
                execution_price = desired_entry;
             }
             else if(desired_entry > (current_ask + min_pending_distance))
             {
                execution_type = "PENDING (BUY STOP)";
                execution_price = desired_entry;
             }
             else
             {
                use_market_execution = true; // Too close to place a valid pending order
             }
          }
          else // SELL: limit above bid, stop below bid
          {
             if(desired_entry > (current_bid + min_pending_distance))
             {
                execution_type = "PENDING (SELL LIMIT)";
                execution_price = desired_entry;
             }
             else if(desired_entry < (current_bid - min_pending_distance))
             {
                execution_type = "PENDING (SELL STOP)";
                execution_price = desired_entry;
             }
             else
             {
                use_market_execution = true; // Too close to place a valid pending order
             }
          }
       }

       if(!use_market_execution)
       {
          // Harmonize risk: recompute SL/TP from intended pip distances using the pending entry
          double entry_price = NormalizeDouble(execution_price, digits);
          if(signal.direction == 1) // BUY
          {
             adjusted_sl = entry_price - (base_sl_pips * point);
             adjusted_tp = entry_price + (base_tp_pips * point);
          }
          else // SELL
          {
             adjusted_sl = entry_price + (base_sl_pips * point);
             adjusted_tp = entry_price - (base_tp_pips * point);
          }
          adjusted_sl = NormalizeDouble(adjusted_sl, digits);
          adjusted_tp = NormalizeDouble(adjusted_tp, digits);

          SNormalizedPrices normalized_pending = NormalizeTradePrices(entry_price, adjusted_sl, adjusted_tp, digits, tick_size);
          entry_price = normalized_pending.entry;
          execution_price = entry_price;
          adjusted_sl = normalized_pending.stop_loss;
          adjusted_tp = normalized_pending.take_profit;

          // Re-validate pending side after normalization; rounding can invalidate order side
          // (e.g., BUY LIMIT normalized above ASK and broker returns invalid price).
          bool is_limit_order = (StringFind(execution_type, "LIMIT") >= 0);
          bool pending_side_valid = false;
          if(signal.direction == 1)
             pending_side_valid = (is_limit_order ?
                                   (execution_price < (current_ask - min_pending_distance)) :
                                   (execution_price > (current_ask + min_pending_distance)));
          else
             pending_side_valid = (is_limit_order ?
                                   (execution_price > (current_bid + min_pending_distance)) :
                                   (execution_price < (current_bid - min_pending_distance)));

          if(!pending_side_valid)
          {
              double price_buffer = ComputePendingEntryGuardBuffer(symbol, point, tick_size,
                                                                   current_bid, current_ask,
                                                                   execution_slippage_pips);
             if(signal.direction == 1)
                entry_price = (is_limit_order ?
                               (current_ask - (min_pending_distance + price_buffer)) :
                               (current_ask + (min_pending_distance + price_buffer)));
             else
                entry_price = (is_limit_order ?
                               (current_bid + (min_pending_distance + price_buffer)) :
                               (current_bid - (min_pending_distance + price_buffer)));

             entry_price = NormalizeDouble(entry_price, digits);
             if(signal.direction == 1)
             {
                adjusted_sl = entry_price - (base_sl_pips * point);
                adjusted_tp = entry_price + (base_tp_pips * point);
             }
             else
             {
                adjusted_sl = entry_price + (base_sl_pips * point);
                adjusted_tp = entry_price - (base_tp_pips * point);
             }
             adjusted_sl = NormalizeDouble(adjusted_sl, digits);
             adjusted_tp = NormalizeDouble(adjusted_tp, digits);

             SNormalizedPrices normalized_adjusted = NormalizeTradePrices(entry_price, adjusted_sl, adjusted_tp, digits, tick_size);
             execution_price = normalized_adjusted.entry;
             adjusted_sl = normalized_adjusted.stop_loss;
             adjusted_tp = normalized_adjusted.take_profit;

             bool pending_side_valid_after_adjust = false;
             if(signal.direction == 1)
                pending_side_valid_after_adjust = (is_limit_order ?
                                                  (execution_price < (current_ask - min_pending_distance)) :
                                                  (execution_price > (current_ask + min_pending_distance)));
             else
                pending_side_valid_after_adjust = (is_limit_order ?
                                                  (execution_price > (current_bid + min_pending_distance)) :
                                                  (execution_price < (current_bid - min_pending_distance)));

             if(!pending_side_valid_after_adjust)
             {
                RecordRejectReason("RETRY:PendingEntryInvalidAfterNormalize");
                Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                    " - Pending entry invalid after normalization/adjustment; deferring retry");
                retry.next_retry = now + defer_short;
                return false;
             }

             Log(LOG_INFO, "ProcessTradeRetry", symbol +
                 " - Pending entry re-anchored after normalization to avoid invalid-price rejection");
          }

          Log(LOG_INFO, "ProcessTradeRetry", symbol + " - " + execution_type + " attempt " + IntegerToString(retry.attempt + 1) +
              ": Entry=" + DoubleToString(execution_price, digits) +
              ", Current Bid=" + DoubleToString(current_bid, digits) +
              ", Current Ask=" + DoubleToString(current_ask, digits) +
              ", SL=" + DoubleToString(adjusted_sl, digits) +
              ", TP=" + DoubleToString(adjusted_tp, digits));
          
          int levels_reason = TRADE_LEVELS_OK;
          if(!ValidateTradeLevelsWithReason(symbol, execution_price, adjusted_sl, adjusted_tp, levels_reason))
          {
             string reason_tag = TradeLevelsReasonLabel(levels_reason);
             RecordRejectReason("RETRY:PendingLevelsInvalid_" + reason_tag);
             if(IsTradeLevelsPermanent(levels_reason))
             {
                Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                    " - Pending trade levels invalid (permanent: " + reason_tag + ")");
                retry.attempt = g_Max_Retry_Attempts;
             }
             else
             {
                Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                    " - Pending trade levels invalid (" + reason_tag + ")");
                retry.next_retry = now + defer_short;
             }
             return false;
          }
          
          if(!EnforceFinalPerTradeRiskCap(symbol, signal.direction, execution_price, adjusted_sl,
                                          lot_size, "ProcessTradeRetry"))
          {
             retry.attempt = g_Max_Retry_Attempts;
             return false;
          }

          if(!CheckInstitutionalRiskLimits(symbol, signal.direction, lot_size, execution_price, adjusted_sl))
          {
             double risk_base = GetRiskBaseValue();
             double trade_risk = CalculateTradeRiskCurrency(symbol, signal.direction, lot_size, execution_price, adjusted_sl);
             double symbol_risk = GetOpenRiskCurrency(symbol);
             double max_symbol_pct = ResolveMaxSymbolRiskPct();
             double max_symbol_risk = (risk_base > 0.0 && max_symbol_pct > 0.0) ? (risk_base * max_symbol_pct / 100.0) : 0.0;
             double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
             bool min_lot_trade = (min_lot > 0.0 && lot_size <= min_lot * 1.01);
             bool symbol_cap_hit = (max_symbol_risk > 0.0 && (symbol_risk + trade_risk) > max_symbol_risk);

             if(min_lot_trade && symbol_cap_hit && symbol_risk <= MathMax(0.01, risk_base * 0.0001))
             {
                RecordRejectReason("RETRY:RiskLimitPendingPermanent");
                retry.attempt = g_Max_Retry_Attempts; // force immediate removal by caller
                Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                    " - Risk limits block pending execution permanently (min-lot floor vs symbol cap) | " +
                    "tradeRisk=$" + DoubleToString(trade_risk, 2) +
                    ", symbolRisk=$" + DoubleToString(symbol_risk, 2) +
                    ", maxSymbolRisk=$" + DoubleToString(max_symbol_risk, 2));
             }
             else
             {
                RecordRejectReason("RETRY:RiskLimitPending");
                retry.next_retry = TimeCurrent() + defer_medium;
                Log(LOG_WARNING, "ProcessTradeRetry", symbol + " - Risk limits block pending execution; deferred retry");
             }
              return false;
           }

           secondary_breakout_lot = 0.0;
           if(g_Enable_Pending_Breakout_Variant)
           {
              double original_pending_lot = lot_size;
              double min_lot_for_split = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
              double candidate_secondary = original_pending_lot / 2.0;
              string split_reason = "";
              if(min_lot_for_split > 0.0 &&
                 candidate_secondary >= min_lot_for_split &&
                 NormalizeLotToBroker(symbol, candidate_secondary, split_reason))
              {
                 double candidate_primary = original_pending_lot - candidate_secondary;
                 string primary_split_reason = "";
                 if(candidate_primary >= min_lot_for_split &&
                    NormalizeLotToBroker(symbol, candidate_primary, primary_split_reason) &&
                    (candidate_primary + candidate_secondary) <= original_pending_lot + 1e-8)
                 {
                    lot_size = candidate_primary;
                    secondary_breakout_lot = candidate_secondary;
                    Log(LOG_INFO, "ProcessTradeRetry",
                        StringFormat("%s - Breakout variant split sizing: primary %.4f, secondary %.4f, original %.4f",
                                     symbol, lot_size, secondary_breakout_lot, original_pending_lot));
                 }
                 else
                 {
                    Log(LOG_INFO, "ProcessTradeRetry", symbol +
                        " - Secondary breakout skipped: lot cannot be split without increasing total exposure");
                 }
              }
              else if(StringLen(split_reason) > 0)
              {
                 Log(LOG_INFO, "ProcessTradeRetry", symbol +
                     " - Secondary breakout skipped: split lot invalid (" + split_reason + ")");
              }
           }

           // CRITICAL FIX: Recheck position count just before execution
           // NOTE: Race condition window exists between this check and OrderSend().
          // Mitigation: Retry queue + min 1-second defer prevents rapid duplicate orders.
          // True atomic execution would require MT5 transaction API (not available).
          int current_positions = CountOurOpenPositions(symbol);
          int current_pending = CountOurPendingOrders(symbol);
          if(ExposureGateOn() && (current_positions + current_pending) >= MAX_TRADES_PER_SYMBOL)
          {
             RecordRejectReason("RETRY:SymbolPositionLimit");
             Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                 ": Symbol exposure increased since signal generation (positions=" +
                 IntegerToString(current_positions) + ", pending=" + IntegerToString(current_pending) +
                 ", limit=" +
                 IntegerToString(MAX_TRADES_PER_SYMBOL) + ") - skipping execution");
             retry.next_retry = now + defer_medium;
             return false;
          }

          int current_global_positions = CountOurOpenPositions();
          int current_global_pending = CountOurPendingOrders();
          int current_global_slots = current_global_positions + current_global_pending;
          if(CGateController::IsExposureGateEnabled() && current_global_slots >= concurrent_limit)
          {
             RecordRejectReason("RETRY:MaxConcurrentTradesAtPending");
             Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                 ": Global concurrent limit reached before pending placement (" +
                 IntegerToString(current_global_slots) + "/" + IntegerToString(concurrent_limit) +
                 ", open=" + IntegerToString(current_global_positions) +
                 ", pending=" + IntegerToString(current_global_pending) + ")");
             retry.next_retry = now + defer_medium;
             return false;
          }

          // Final quote-side validation at send-time for pending orders.
          // Quotes can drift between earlier validation and broker request, causing INVALID_PRICE.
          if(!sym.RefreshRates())
          {
             RecordRejectReason("RETRY:PendingRefreshRatesBeforeSendFailed");
             Log(LOG_WARNING, "ProcessTradeRetry", symbol + " - Failed to refresh quotes before pending placement");
             retry.next_retry = now + defer_short;
             return false;
          }

          // FIX #1: Quote timestamp validation - capture broker tick freshness snapshot
          SQuoteSnapshot quote_snap;
          MqlTick pending_tick;
          if(SymbolInfoTick(symbol, pending_tick))
          {
             quote_snap.bid = pending_tick.bid;
             quote_snap.ask = pending_tick.ask;
             quote_snap.tick_time = pending_tick.time;
          }
          else
          {
             quote_snap.bid = sym.Bid();
             quote_snap.ask = sym.Ask();
          }
          quote_snap.timestamp_ms = (int)GetTickCount();
          quote_snap.max_age_ms = 500;  // 500ms max acceptable age
          
          if(quote_snap.IsStale())
          {
             RecordRejectReason("RETRY:QuoteSnapshotStaleAtCapture");
             Log(LOG_WARNING, "ProcessTradeRetry", symbol + 
                 " - Quote snapshot stale at capture time; re-fetching");
             retry.next_retry = now + 1;
             return false;
          }

          current_bid = quote_snap.bid;
          current_ask = quote_snap.ask;
          if(current_bid <= 0.0 || current_ask <= 0.0 || current_bid >= current_ask)
          {
             RecordRejectReason("RETRY:PendingInvalidQuotesBeforeSend");
             Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                 " - Invalid quotes before pending placement (Bid=" + DoubleToString(current_bid, digits) +
                 ", Ask=" + DoubleToString(current_ask, digits) + ")");
             retry.next_retry = now + defer_short;
             return false;
          }

          int send_stop_level = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
          int send_freeze_level = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
          double send_min_pending_distance = MathMax((double)send_stop_level, (double)send_freeze_level) * point;
          if(send_min_pending_distance < point)
             send_min_pending_distance = point * 2;

          bool send_is_limit_order = (StringFind(execution_type, "LIMIT") >= 0);
          bool send_pending_side_valid = false;
          if(signal.direction == 1)
             send_pending_side_valid = (send_is_limit_order ?
                                       (execution_price < (current_ask - send_min_pending_distance)) :
                                       (execution_price > (current_ask + send_min_pending_distance)));
          else
             send_pending_side_valid = (send_is_limit_order ?
                                       (execution_price > (current_bid + send_min_pending_distance)) :
                                       (execution_price < (current_bid - send_min_pending_distance)));

          if(g_Enable_Institutional_Debug)
          {
             Log(LOG_DEBUG, "ProcessTradeRetry", symbol +
                 " - Pending send snapshot: Type=" + execution_type +
                 ", Entry=" + DoubleToString(execution_price, digits) +
                 ", Bid=" + DoubleToString(current_bid, digits) +
                 ", Ask=" + DoubleToString(current_ask, digits) +
                 ", MinDist=" + DoubleToString(send_min_pending_distance, digits));
          }

          if(!send_pending_side_valid)
          {
              double send_price_buffer = ComputePendingEntryGuardBuffer(symbol, point, tick_size,
                                                                        current_bid, current_ask,
                                                                        execution_slippage_pips);
             if(signal.direction == 1)
                execution_price = (send_is_limit_order ?
                                   (current_ask - (send_min_pending_distance + send_price_buffer)) :
                                   (current_ask + (send_min_pending_distance + send_price_buffer)));
             else
                execution_price = (send_is_limit_order ?
                                   (current_bid + (send_min_pending_distance + send_price_buffer)) :
                                   (current_bid - (send_min_pending_distance + send_price_buffer)));

             execution_price = SafeNormalizeToTick(execution_price, digits, tick_size);
             if(signal.direction == 1)
             {
                adjusted_sl = execution_price - (base_sl_pips * point);
                adjusted_tp = execution_price + (base_tp_pips * point);
             }
             else
             {
                adjusted_sl = execution_price + (base_sl_pips * point);
                adjusted_tp = execution_price - (base_tp_pips * point);
             }

             SNormalizedPrices normalized_send = NormalizeTradePrices(execution_price, adjusted_sl, adjusted_tp, digits, tick_size);
             execution_price = normalized_send.entry;
             adjusted_sl = normalized_send.stop_loss;
             adjusted_tp = normalized_send.take_profit;

             bool send_pending_side_valid_after_adjust = false;
             if(signal.direction == 1)
                send_pending_side_valid_after_adjust = (send_is_limit_order ?
                                                       (execution_price < (current_ask - send_min_pending_distance)) :
                                                       (execution_price > (current_ask + send_min_pending_distance)));
             else
                send_pending_side_valid_after_adjust = (send_is_limit_order ?
                                                       (execution_price > (current_bid + send_min_pending_distance)) :
                                                       (execution_price < (current_bid - send_min_pending_distance)));

             if(!send_pending_side_valid_after_adjust)
             {
                RecordRejectReason("RETRY:PendingEntryInvalidAtSendTime");
                Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                    " - Pending entry invalid at send-time after re-anchoring; deferring retry");
                retry.next_retry = now + defer_short;
                return false;
             }

             Log(LOG_INFO, "ProcessTradeRetry", symbol +
                 " - Pending entry re-anchored at send-time (Entry=" + DoubleToString(execution_price, digits) +
                 ", Bid=" + DoubleToString(current_bid, digits) +
                 ", Ask=" + DoubleToString(current_ask, digits) +
                 ", MinDist=" + DoubleToString(send_min_pending_distance, digits) + ")");
          }

          int send_levels_reason = TRADE_LEVELS_OK;
          if(!ValidateTradeLevelsWithReason(symbol, execution_price, adjusted_sl, adjusted_tp, send_levels_reason))
          {
             string reason_tag = TradeLevelsReasonLabel(send_levels_reason);
             RecordRejectReason("RETRY:PendingLevelsInvalidAtSend_" + reason_tag);
             if(IsTradeLevelsPermanent(send_levels_reason))
             {
                Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                    " - Pending levels invalid at send-time (permanent: " + reason_tag + ")");
                retry.attempt = g_Max_Retry_Attempts;
             }
             else
             {
                Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                    " - Pending levels invalid at send-time (" + reason_tag + ")");
                retry.next_retry = now + defer_short;
             }
             return false;
          }

          int pending_expiry_minutes = (int)MathRound(ExtractTaggedNumericValue(signal.reason, "PendingExpiryMin=", -1.0));
          datetime expiration = TimeCurrent() + 14400;
          if(pending_expiry_minutes > 0)
             expiration = TimeCurrent() + pending_expiry_minutes * 60;

          ENUM_ORDER_TYPE pending_order_type = ORDER_TYPE_BUY_LIMIT;
          if(signal.direction == 1)
             pending_order_type = (StringFind(execution_type, "LIMIT") >= 0 ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_BUY_STOP);
          else
             pending_order_type = (StringFind(execution_type, "LIMIT") >= 0 ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_SELL_STOP);

          bool already_live = false;
          ulong deviation_points = (ulong)MathMax(0, PipsToPoints(symbol, execution_slippage_pips));
          if(!RunBrokerExecutionPreflight(retry, signal, symbol, execution_type, magic_number, signal_fp,
                                          pending_order_type, pending_fill, lot_size, execution_price,
                                          adjusted_sl, adjusted_tp, deviation_points, expiration, comment,
                                          retry_interval, digits, already_live))
          {
             return false;
          }
          if(already_live)
             return true;

          // FIX #2: Atomic position recheck just before OrderSend
          int final_check_positions = CountOurOpenPositions(symbol);
          int final_check_pending = CountOurPendingOrders(symbol);
          
          if(ExposureGateOn() && (final_check_positions + final_check_pending) >= MAX_TRADES_PER_SYMBOL)
          {
             RecordRejectReason("RETRY:SymbolExposureAtPendingSend");
             Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                 " - Symbol exposure limit hit at pending send (pos=" +
                 IntegerToString(final_check_positions) + ", pending=" +
                 IntegerToString(final_check_pending) + ", limit=" +
                 IntegerToString(MAX_TRADES_PER_SYMBOL) + ")");
             retry.next_retry = now + defer_medium;
             return false;
          }

          // Refresh the quote immediately before OrderSend so borderline pending prices
          // do not flip sides between preflight and broker submission.
          if(!sym.RefreshRates())
          {
             RecordRejectReason("RETRY:RefreshRatesFailedAtPendingSend");
             Log(LOG_WARNING, "ProcessTradeRetry", symbol + " - Failed to refresh rates at pending send; deferring");
             retry.next_retry = now + defer_short;
             return false;
          }

          double send_bid = sym.Bid();
          double send_ask = sym.Ask();
          if(send_bid <= 0.0 || send_ask <= 0.0 || send_bid >= send_ask)
          {
             RecordRejectReason("RETRY:InvalidPricesAtPendingSend");
             Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                 " - Invalid prices at pending send: Bid=" + DoubleToString(send_bid, digits) +
                 ", Ask=" + DoubleToString(send_ask, digits));
             retry.next_retry = now + defer_short;
             return false;
          }

          bool rerun_preflight = false;
           double send_price_buffer = ComputePendingEntryGuardBuffer(symbol, point, tick_size,
                                                                     send_bid, send_ask,
                                                                     execution_slippage_pips);
           double send_required_distance = send_min_pending_distance + send_price_buffer;
           bool send_time_is_limit_order = (StringFind(execution_type, "LIMIT") >= 0);
           bool send_side_valid = false;
           if(signal.direction == 1)
              send_side_valid = (send_time_is_limit_order ?
                                 (execution_price < (send_ask - send_required_distance)) :
                                 (execution_price > (send_ask + send_required_distance)));
           else
              send_side_valid = (send_time_is_limit_order ?
                                 (execution_price > (send_bid + send_required_distance)) :
                                 (execution_price < (send_bid - send_required_distance)));

          if(!send_side_valid)
          {
             if(signal.direction == 1)
             {
                if(execution_price <= send_ask)
                {
                   execution_type = "PENDING (BUY LIMIT)";
                   execution_price = send_ask - (send_min_pending_distance + send_price_buffer);
                }
                else
                {
                   execution_type = "PENDING (BUY STOP)";
                   execution_price = send_ask + (send_min_pending_distance + send_price_buffer);
                }
                adjusted_sl = execution_price - (base_sl_pips * point);
                adjusted_tp = execution_price + (base_tp_pips * point);
             }
             else
             {
                if(execution_price >= send_bid)
                {
                   execution_type = "PENDING (SELL LIMIT)";
                   execution_price = send_bid + (send_min_pending_distance + send_price_buffer);
                }
                else
                {
                   execution_type = "PENDING (SELL STOP)";
                   execution_price = send_bid - (send_min_pending_distance + send_price_buffer);
                }
                adjusted_sl = execution_price + (base_sl_pips * point);
                adjusted_tp = execution_price - (base_tp_pips * point);
             }

             execution_price = NormalizeDouble(execution_price, digits);
             adjusted_sl = NormalizeDouble(adjusted_sl, digits);
             adjusted_tp = NormalizeDouble(adjusted_tp, digits);

             SNormalizedPrices send_time_norm = NormalizeTradePrices(execution_price, adjusted_sl, adjusted_tp, digits, tick_size);
             execution_price = send_time_norm.entry;
             adjusted_sl = send_time_norm.stop_loss;
             adjusted_tp = send_time_norm.take_profit;

             if(signal.direction == 1)
                pending_order_type = (StringFind(execution_type, "LIMIT") >= 0 ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_BUY_STOP);
             else
                pending_order_type = (StringFind(execution_type, "LIMIT") >= 0 ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_SELL_STOP);

             Log(LOG_INFO, "ProcessTradeRetry", symbol +
                 " - Pending order re-anchored at send-time to keep broker-side valid: " +
                 execution_type + " | Entry=" + DoubleToString(execution_price, digits) +
                 ", Bid=" + DoubleToString(send_bid, digits) +
                 ", Ask=" + DoubleToString(send_ask, digits));
             rerun_preflight = true;
          }

          current_bid = send_bid;
          current_ask = send_ask;

          if(rerun_preflight)
          {
             bool send_already_live = false;
             if(!RunBrokerExecutionPreflight(retry, signal, symbol, execution_type, magic_number, signal_fp,
                                             pending_order_type, pending_fill, lot_size, execution_price,
                                             adjusted_sl, adjusted_tp, deviation_points, expiration, comment,
                                             retry_interval, digits, send_already_live))
             {
                return false;
             }
             if(send_already_live)
                return true;
          }

          if(signal.direction == 1)
          {
             if(StringFind(execution_type, "LIMIT") >= 0)
            {
                if(IsStopped())
                {
                   RecordRejectReason("RETRY:EAStopping");
                   retry.attempt = g_Max_Retry_Attempts;
                   return false;
                }
                execution_result = trade.BuyLimit(lot_size, execution_price, symbol,
                                                 adjusted_sl, adjusted_tp, ORDER_TIME_SPECIFIED,
                                                 expiration, comment);
            }
            else
            {
                if(IsStopped())
                {
                   RecordRejectReason("RETRY:EAStopping");
                   retry.attempt = g_Max_Retry_Attempts;
                   return false;
                }
                execution_result = trade.BuyStop(lot_size, execution_price, symbol,
                                                adjusted_sl, adjusted_tp, ORDER_TIME_SPECIFIED,
                                                expiration, comment);
            }
         }
         else
         {
            if(StringFind(execution_type, "LIMIT") >= 0)
            {
                if(IsStopped())
                {
                   RecordRejectReason("RETRY:EAStopping");
                   retry.attempt = g_Max_Retry_Attempts;
                   return false;
                }
                execution_result = trade.SellLimit(lot_size, execution_price, symbol,
                                                  adjusted_sl, adjusted_tp, ORDER_TIME_SPECIFIED,
                                                  expiration, comment);
            }
            else
            {
                if(IsStopped())
                {
                   RecordRejectReason("RETRY:EAStopping");
                   retry.attempt = g_Max_Retry_Attempts;
                   return false;
                }
                execution_result = trade.SellStop(lot_size, execution_price, symbol,
                                                 adjusted_sl, adjusted_tp, ORDER_TIME_SPECIFIED,
                                                 expiration, comment);
            }
         }
       }
       else
       {
          if(StringFind(execution_type, "KIM STALE FAR ENTRY") >= 0)
          {
             Log(LOG_INFO, "ProcessTradeRetry", symbol +
                 " - Executing MARKET from KImaniz stale far-entry policy");
          }
          else
          {
             Log(LOG_INFO, "ProcessTradeRetry", symbol +
                 ": Pending entry too close to market (Entry=" + DoubleToString(desired_entry, digits) +
                 ", Bid=" + DoubleToString(current_bid, digits) +
                 ", Ask=" + DoubleToString(current_ask, digits) +
                 ") - executing MARKET instead");
          }
       }

        if(!use_market_execution)
        {
           primary_result_captured = true;
           primary_result_retcode = (int)trade.ResultRetcode();
           primary_result_retcode_desc = trade.ResultRetcodeDescription();
           primary_result_order = trade.ResultOrder();
           primary_result_deal = trade.ResultDeal();
           primary_result_price = trade.ResultPrice();
        }
        
      // Optional: place a breakout-style pending using the pre-split secondary lot.
      if(execution_result && g_Enable_Pending_Breakout_Variant && secondary_breakout_lot > 0.0)
      {
         int global_positions_sb = CountOurOpenPositions();
         int global_pending_sb = CountOurPendingOrders();
         int global_slots_sb = global_positions_sb + global_pending_sb;
         int exposure_positions = CountOurOpenPositions(symbol);
         int exposure_pending = CountOurPendingOrders(symbol);
         if(CGateController::IsExposureGateEnabled() && global_slots_sb >= concurrent_limit)
         {
            Log(LOG_INFO, "ProcessTradeRetry", symbol +
                " - Secondary breakout pending skipped by global concurrent cap (" +
                IntegerToString(global_slots_sb) + "/" + IntegerToString(concurrent_limit) +
                ", open=" + IntegerToString(global_positions_sb) +
                ", pending=" + IntegerToString(global_pending_sb) + ")");
         }
         else if(ExposureGateOn() && (exposure_positions + exposure_pending) >= MAX_TRADES_PER_SYMBOL)
         {
            Log(LOG_INFO, "ProcessTradeRetry", symbol +
                " - Secondary breakout pending skipped due to symbol exposure limit (positions=" +
                IntegerToString(exposure_positions) + ", pending=" + IntegerToString(exposure_pending) +
                ", limit=" + IntegerToString(MAX_TRADES_PER_SYMBOL) + ")");
          }
          else
          {
          double breakout_price = 0.0;
          string breakout_type = "";
          double lot_split = secondary_breakout_lot;
            
          if(signal.direction == 1)
          {
                breakout_price = current_ask + min_pending_distance * 1.1;
                breakout_type = "PENDING (BUY STOP)";
             }
             else
             {
                breakout_price = current_bid - min_pending_distance * 1.1;
                breakout_type = "PENDING (SELL STOP)";
             }

          double breakout_sl, breakout_tp;
          if(signal.direction == 1)
          {
             breakout_sl = breakout_price - (base_sl_pips * point);
             breakout_tp = breakout_price + (base_tp_pips * point);
          }
          else
          {
             breakout_sl = breakout_price + (base_sl_pips * point);
             breakout_tp = breakout_price - (base_tp_pips * point);
          }
          breakout_sl = NormalizeDouble(breakout_sl, digits);
          breakout_tp = NormalizeDouble(breakout_tp, digits);

          SNormalizedPrices breakout_norm = NormalizeTradePrices(breakout_price, breakout_sl, breakout_tp, digits, tick_size);
          breakout_price = breakout_norm.entry;
          breakout_sl = breakout_norm.stop_loss;
          breakout_tp = breakout_norm.take_profit;

          // Combined risk guard for dual pendings
          double worst_entry = (signal.direction == 1 ? MathMax(execution_price, breakout_price) : MathMin(execution_price, breakout_price));
          double worst_sl = (signal.direction == 1 ? worst_entry - (base_sl_pips * point) : worst_entry + (base_sl_pips * point));
             if(!CheckInstitutionalRiskLimits(symbol, signal.direction, lot_size + lot_split, worst_entry, worst_sl))
             {
                Log(LOG_WARNING, "ProcessTradeRetry", symbol + " - Combined risk limit blocks breakout pending; placing only primary pending");
             }
             else if(ValidateTradeLevels(symbol, breakout_price, breakout_sl, breakout_tp) &&
                CheckInstitutionalRiskLimits(symbol, signal.direction, lot_split, breakout_price, breakout_sl))
             {
                datetime expiration = TimeCurrent() + 14400;
                bool breakout_request_ok = false;
                if(signal.direction == 1)
                   breakout_request_ok = trade.BuyStop(lot_split, breakout_price, symbol, breakout_sl, breakout_tp, ORDER_TIME_SPECIFIED, expiration, comment);
                else
                   breakout_request_ok = trade.SellStop(lot_split, breakout_price, symbol, breakout_sl, breakout_tp, ORDER_TIME_SPECIFIED, expiration, comment);

                int breakout_retcode = (int)trade.ResultRetcode();
                bool breakout_ok = (breakout_request_ok && IsSuccessfulTradeRetcode(breakout_retcode, true));

                Log(breakout_ok ? LOG_INFO : LOG_WARNING,
                    "ProcessTradeRetry",
                    symbol + " - Secondary " + breakout_type + " " + (breakout_ok ? "placed" : "failed") +
                    " | Entry=" + DoubleToString(breakout_price, digits) +
                    " | SL=" + DoubleToString(breakout_sl, digits) +
                    " | TP=" + DoubleToString(breakout_tp, digits) +
                    " | Lot=" + DoubleToString(lot_split, 2) +
                    (breakout_ok ? "" : " | Retcode=" + IntegerToString(breakout_retcode)));
             }
             else
             {
                Log(LOG_WARNING, "ProcessTradeRetry", symbol + " - Secondary breakout pending rejected by level/risk checks");
             }
       }
    }
   }

   if(require_pending_for_slippage && use_market_execution)
   {
      RecordRejectReason("EXECQ:SlippageRisk");
      string block_msg = symbol + " - Smart routing required pending due to slippage risk; market execution blocked";
      if(entry_distance_pips > 0.0)
         block_msg += " (distance " + DoubleToString(entry_distance_pips, 1) + "p > " +
                      DoubleToString(g_Execution_Max_Slippage_Pips, 1) + "p)";
      Log(LOG_WARNING, "ProcessTradeRetry", block_msg);
      AuditLogSignal("EXECQ_BLOCK", symbol, signal, block_msg);
      retry.next_retry = now + defer_short;
      return false;
   }

   if(use_market_execution)
   {
      trade.SetTypeFilling(GetSymbolFillingMode(symbol));
      
      // ===== ISSUE #2: SECONDARY ENTRY DISTANCE RE-VALIDATION AT EXECUTION TIME =====
      // Verify that queued signal entry hasn't become too stale due to market movement
      double execution_distance_cap_basis = g_Max_Entry_Distance_Pct;
      if(signal.origin == SIGNAL_ORIGIN_ICT || signal.origin == SIGNAL_ORIGIN_BOTH)
         execution_distance_cap_basis = g_Max_Entry_Distance_Relaxed_Cap;
      double execution_distance_cap_pct = MathMin(2.0, MathMax(0.80, execution_distance_cap_basis));
      
      // Allow 50% margin for volatility gaps between queue insertion and execution
      double stale_entry_threshold_pct = execution_distance_cap_pct * 1.5;
      
      double ref_price_for_stale_check = (signal.direction == 1 ? current_ask : current_bid);
      if(ref_price_for_stale_check > 0.0)
      {
         double execution_distance_pct = MathAbs(signal.entry_price - ref_price_for_stale_check) / ref_price_for_stale_check * 100.0;
         if(execution_distance_pct > stale_entry_threshold_pct)
         {
            // Entry price has become too stale at execution time
            if(g_Use_Pending_Orders && !require_pending_for_slippage)
            {
               // Can convert to pending order as fallback
               use_market_execution = false;
               g_exec_slippage_reroutes++;
               string stale_route_msg = symbol + " - Stale entry at execution time (" +
                                       DoubleToString(execution_distance_pct, 2) + "% > " +
                                       DoubleToString(stale_entry_threshold_pct, 2) +
                                       "%); routing from market to pending order";
               Log(LOG_INFO, "ProcessTradeRetry", stale_route_msg);
               AuditLogSignal("EXECQ_STALE_REROUTE", symbol, signal, stale_route_msg);
            }
            else
            {
               // Cannot proceed with market execution on stale entry
               RecordRejectReason("RETRY:StaleEntryDistance");
               string stale_block_msg = symbol + " - Stale entry prevents market execution (" +
                                       DoubleToString(execution_distance_pct, 2) + "% > " +
                                       DoubleToString(stale_entry_threshold_pct, 2) +
                                       "%); pending orders disabled or not available";
               Log(LOG_WARNING, "ProcessTradeRetry", stale_block_msg);
               AuditLogSignal("EXECQ_STALE_BLOCK", symbol, signal, stale_block_msg);
               retry.next_retry = now + defer_short;
               return false;
            }
         }
      }
      
      // ===== MARKET ORDER EXECUTION =====
      if(signal.direction == 1) // BUY
      {
         // FIXED: Execute immediately at market price - no waiting for "better" prices
         execution_price = current_ask;
         expected_market_price = execution_price;
         adjusted_sl = execution_price - (adjusted_sl_pips * point);
         adjusted_tp = execution_price + (adjusted_tp_pips * point);

         // Normalize the adjusted prices to the symbol's digits
         adjusted_sl = NormalizeDouble(adjusted_sl, digits);
         adjusted_tp = NormalizeDouble(adjusted_tp, digits);

         Log(LOG_INFO, "ProcessTradeRetry", symbol + " - BUY MARKET attempt " + IntegerToString(retry.attempt + 1) +
             ": Current Ask=" + DoubleToString(current_ask, digits) +
             ", SL=" + DoubleToString(adjusted_sl, digits) +
             ", TP=" + DoubleToString(adjusted_tp, digits));
         
          int levels_reason = TRADE_LEVELS_OK;
          if(!ValidateTradeLevelsWithReason(symbol, execution_price, adjusted_sl, adjusted_tp, levels_reason))
          {
             string reason_tag = TradeLevelsReasonLabel(levels_reason);
             RecordRejectReason("RETRY:MarketBuyLevelsInvalid_" + reason_tag);
             if(IsTradeLevelsPermanent(levels_reason))
             {
                Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                    " - Market BUY trade levels invalid (permanent: " + reason_tag + ")");
                retry.attempt = g_Max_Retry_Attempts;
             }
             else
             {
                Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                    " - Market BUY trade levels invalid (" + reason_tag + ")");
                retry.next_retry = now + defer_short;
             }
             return false;
          }
         
         if(!EnforceFinalPerTradeRiskCap(symbol, signal.direction, execution_price, adjusted_sl,
                                         lot_size, "ProcessTradeRetry"))
         {
            retry.attempt = g_Max_Retry_Attempts;
            return false;
         }

         if(!CheckInstitutionalRiskLimits(symbol, signal.direction, lot_size, execution_price, adjusted_sl))
         {
            RecordRejectReason("RETRY:RiskLimitMarketBuy");
            Log(LOG_WARNING, "ProcessTradeRetry", symbol + " - Risk limits block market BUY");
            retry.next_retry = now + defer_medium;
            return false;
         }

         if(IsStopped())
         {
            RecordRejectReason("RETRY:EAStopping");
            retry.attempt = g_Max_Retry_Attempts;
            return false;
         }

         // CRITICAL FIX: Recheck position count just before execution
         // NOTE: Race condition window exists between this check and OrderSend().
         // Mitigation: Retry queue + min 1-second defer prevents rapid duplicate orders.
         // True atomic execution would require MT5 transaction API (not available).
         int current_positions = CountOurOpenPositions(symbol);
         int current_pending = CountOurPendingOrders(symbol);
         if(ExposureGateOn() && (current_positions + current_pending) >= MAX_TRADES_PER_SYMBOL)
         {
            RecordRejectReason("RETRY:SymbolPositionLimit");
            Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                ": Symbol exposure increased since signal generation (positions=" +
                IntegerToString(current_positions) + ", pending=" + IntegerToString(current_pending) +
                ", limit=" +
                IntegerToString(MAX_TRADES_PER_SYMBOL) + ") - skipping execution");
            retry.next_retry = now + defer_medium;
            return false;
         }

         int current_global_positions = CountOurOpenPositions();
         int current_global_pending = CountOurPendingOrders();
         int current_global_slots = current_global_positions + current_global_pending;
         if(CGateController::IsExposureGateEnabled() && current_global_slots >= concurrent_limit)
         {
            RecordRejectReason("RETRY:MaxConcurrentTradesAtExec");
            Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                ": Global concurrent limit reached before market BUY (" +
                IntegerToString(current_global_slots) + "/" + IntegerToString(concurrent_limit) +
                ", open=" + IntegerToString(current_global_positions) +
                ", pending=" + IntegerToString(current_global_pending) + ")");
            retry.next_retry = now + defer_medium;
            return false;
         }

         bool already_live = false;
         ulong deviation_points = (ulong)MathMax(0, PipsToPoints(symbol, execution_slippage_pips));
         
         // FIX #1: Final quote freshness validation before market execution
         if(!sym.RefreshRates())
         {
            RecordRejectReason("RETRY:MarketBuyRefreshFailed");
            Log(LOG_WARNING, "ProcessTradeRetry", symbol + " - Failed to refresh quotes before market BUY");
            retry.next_retry = now + defer_short;
            return false;
         }
         
         double final_bid = sym.Bid();
         double final_ask = sym.Ask();
         double bid_shift = MathAbs(current_bid - final_bid);
         double ask_shift = MathAbs(current_ask - final_ask);
         double bid_shift_pct = (current_bid > 0) ? (bid_shift / current_bid * 100) : 0;
         double ask_shift_pct = (current_ask > 0) ? (ask_shift / current_ask * 100) : 0;
         
         if(bid_shift_pct > 1.0 || ask_shift_pct > 1.0)
         {
            RecordRejectReason("RETRY:QuoteDriftExceededBeforeBuy");
            Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                " - Quote drift > 1% before market BUY (Bid: " + DoubleToString(bid_shift_pct, 2) + 
                "%, Ask: " + DoubleToString(ask_shift_pct, 2) + "%)");
            retry.next_retry = now + 2;
            return false;
         }
         
         current_bid = final_bid;
         current_ask = final_ask;
         execution_price = current_ask;
         
         // ===== FIX 3: DETAILED ENTRY PRICE TRACKING FOR BUY MARKET =====
         double market_buy_entry = current_ask;
         double buy_intended_vs_actual = MathAbs(market_buy_entry - signal.entry_price) / point;
         double buy_intended_vs_actual_pct = (signal.entry_price > 0) ? 
                                             (MathAbs(market_buy_entry - signal.entry_price) / signal.entry_price * 100) : 0;
         
         Log(LOG_INFO, "ProcessTradeRetry", symbol + " - BUY MARKET ENTRY SNAPSHOT: " +
             "Intended=" + DoubleToString(signal.entry_price, digits) + 
             ", Current_Bid=" + DoubleToString(current_bid, digits) +
             ", Current_Ask=" + DoubleToString(current_ask, digits) +
             ", Fallback_Entry=" + DoubleToString(market_buy_entry, digits) +
             ", Deviation=" + DoubleToString(buy_intended_vs_actual, 1) + 
             "p (" + DoubleToString(buy_intended_vs_actual_pct, 2) + "%)");
         // ===== END FIX 3 =====
         
         if(!RunBrokerExecutionPreflight(retry, signal, symbol, execution_type, magic_number, signal_fp,
                                         ORDER_TYPE_BUY, GetSymbolFillingMode(symbol), lot_size, execution_price,
                                         adjusted_sl, adjusted_tp, deviation_points, 0, comment,
                                         retry_interval, digits, already_live))
         {
            return false;
         }
         if(already_live)
            return true;

         execution_result = trade.Buy(lot_size, symbol, 0, // Use 0 for market price
                                     adjusted_sl, adjusted_tp,
                                     comment);
         
         // FIX #4: Post-execution slippage validation for market BUY (ENHANCED)
         if(execution_result)
         {
            double actual_fill = trade.ResultPrice();
            if(actual_fill > 0.0)
            {
               // Compare adverse movement only; a BUY filled below ask is price improvement.
               double market_slippage_points = MathMax(0.0, actual_fill - execution_price) / point;
               double market_slippage_pct = (execution_price > 0) ?
                                            (MathMax(0.0, actual_fill - execution_price) / execution_price * 100) : 0;
               
               // Compare to original intended entry (total entry deviation)
               double entry_deviation_points = MathMax(0.0, actual_fill - signal.entry_price) / point;
               double entry_deviation_pct = (signal.entry_price > 0) ?
                                            (MathMax(0.0, actual_fill - signal.entry_price) / signal.entry_price * 100) : 0;
               
               // Log both metrics
               Log(LOG_INFO, "ProcessTradeRetry", symbol + " - BUY FILL ANALYSIS: " +
                   "SignalEntry=" + DoubleToString(signal.entry_price, digits) +
                   ", MarketOrder=" + DoubleToString(execution_price, digits) +
                   ", ActualFill=" + DoubleToString(actual_fill, digits) +
                   " | MarketSlippage=" + DoubleToString(market_slippage_points, 1) + 
                   "p | TotalDeviation=" + DoubleToString(entry_deviation_points, 1) + "p");
               
                if(max_acceptable_slippage_points > 0 &&
                   market_slippage_points > max_acceptable_slippage_points)
               {
                  Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                      " - MARKET SLIPPAGE WARNING (BUY): Slippage=" + DoubleToString(market_slippage_points, 1) + 
                      "p (" + DoubleToString(market_slippage_pct, 2) + "%)");
               }
               
                if(max_acceptable_slippage_points > 0 &&
                   entry_deviation_points > max_acceptable_slippage_points * 2)
               {
                  Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                      " - ENTRY DEVIATION WARNING (BUY): Total deviation from intended=" + 
                      DoubleToString(entry_deviation_points, 1) + 
                      "p (" + DoubleToString(entry_deviation_pct, 2) + "%)");
               }
               
               AuditLog("BUY_ENTRY_ANALYSIS", symbol,
                       "Signal=" + DoubleToString(signal.entry_price, digits) +
                       ", Filled=" + DoubleToString(actual_fill, digits) +
                       ", Dev=" + DoubleToString(entry_deviation_points, 1) + "p");
            }
         }
      }
      else // SELL
      {
         // FIXED: Execute immediately at market price - no waiting for "better" prices
         execution_price = current_bid;
         expected_market_price = execution_price;
         adjusted_sl = execution_price + (adjusted_sl_pips * point);
         adjusted_tp = execution_price - (adjusted_tp_pips * point);

         // Normalize the adjusted prices
         adjusted_sl = NormalizeDouble(adjusted_sl, digits);
         adjusted_tp = NormalizeDouble(adjusted_tp, digits);

         Log(LOG_INFO, "ProcessTradeRetry", symbol + " - SELL MARKET attempt " + IntegerToString(retry.attempt + 1) +
             ": Current Bid=" + DoubleToString(current_bid, digits) +
             ", SL=" + DoubleToString(adjusted_sl, digits) +
             ", TP=" + DoubleToString(adjusted_tp, digits));
         
          int levels_reason = TRADE_LEVELS_OK;
          if(!ValidateTradeLevelsWithReason(symbol, execution_price, adjusted_sl, adjusted_tp, levels_reason))
          {
             string reason_tag = TradeLevelsReasonLabel(levels_reason);
             RecordRejectReason("RETRY:MarketSellLevelsInvalid_" + reason_tag);
             if(IsTradeLevelsPermanent(levels_reason))
             {
                Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                    " - Market SELL trade levels invalid (permanent: " + reason_tag + ")");
                retry.attempt = g_Max_Retry_Attempts;
             }
             else
             {
                Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                    " - Market SELL trade levels invalid (" + reason_tag + ")");
                retry.next_retry = now + defer_short;
             }
             return false;
          }
         
         if(!EnforceFinalPerTradeRiskCap(symbol, signal.direction, execution_price, adjusted_sl,
                                         lot_size, "ProcessTradeRetry"))
         {
            retry.attempt = g_Max_Retry_Attempts;
            return false;
         }

         if(!CheckInstitutionalRiskLimits(symbol, signal.direction, lot_size, execution_price, adjusted_sl))
         {
            RecordRejectReason("RETRY:RiskLimitMarketSell");
            Log(LOG_WARNING, "ProcessTradeRetry", symbol + " - Risk limits block market SELL");
            retry.next_retry = now + defer_medium;
            return false;
         }

         if(IsStopped())
         {
            RecordRejectReason("RETRY:EAStopping");
            retry.attempt = g_Max_Retry_Attempts;
            return false;
         }

         // CRITICAL FIX: Recheck position count just before execution
         // NOTE: Race condition window exists between this check and OrderSend().
         // Mitigation: Retry queue + min 1-second defer prevents rapid duplicate orders.
         // True atomic execution would require MT5 transaction API (not available).
         int current_positions = CountOurOpenPositions(symbol);
         int current_pending = CountOurPendingOrders(symbol);
         if(ExposureGateOn() && (current_positions + current_pending) >= MAX_TRADES_PER_SYMBOL)
         {
            RecordRejectReason("RETRY:SymbolPositionLimit");
            Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                ": Symbol exposure increased since signal generation (positions=" +
                IntegerToString(current_positions) + ", pending=" + IntegerToString(current_pending) +
                ", limit=" +
                IntegerToString(MAX_TRADES_PER_SYMBOL) + ") - skipping execution");
            retry.next_retry = now + defer_medium;
            return false;
         }

         int current_global_positions = CountOurOpenPositions();
         int current_global_pending = CountOurPendingOrders();
         int current_global_slots = current_global_positions + current_global_pending;
         if(CGateController::IsExposureGateEnabled() && current_global_slots >= concurrent_limit)
         {
            RecordRejectReason("RETRY:MaxConcurrentTradesAtExec");
            Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                ": Global concurrent limit reached before market SELL (" +
                IntegerToString(current_global_slots) + "/" + IntegerToString(concurrent_limit) +
                ", open=" + IntegerToString(current_global_positions) +
                ", pending=" + IntegerToString(current_global_pending) + ")");
            retry.next_retry = now + defer_medium;
            return false;
         }

         bool already_live = false;
         ulong deviation_points = (ulong)MathMax(0, PipsToPoints(symbol, execution_slippage_pips));
         
         // FIX #1: Final quote freshness validation before market execution
         if(!sym.RefreshRates())
         {
            RecordRejectReason("RETRY:MarketSellRefreshFailed");
            Log(LOG_WARNING, "ProcessTradeRetry", symbol + " - Failed to refresh quotes before market SELL");
            retry.next_retry = now + defer_short;
            return false;
         }
         
         double final_bid = sym.Bid();
         double final_ask = sym.Ask();
         double bid_shift = MathAbs(current_bid - final_bid);
         double ask_shift = MathAbs(current_ask - final_ask);
         double bid_shift_pct = (current_bid > 0) ? (bid_shift / current_bid * 100) : 0;
         double ask_shift_pct = (current_ask > 0) ? (ask_shift / current_ask * 100) : 0;
         
         if(bid_shift_pct > 1.0 || ask_shift_pct > 1.0)
         {
            RecordRejectReason("RETRY:QuoteDriftExceededBeforeSell");
            Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                " - Quote drift > 1% before market SELL (Bid: " + DoubleToString(bid_shift_pct, 2) + 
                "%, Ask: " + DoubleToString(ask_shift_pct, 2) + "%)");
            retry.next_retry = now + 2;
            return false;
         }
         
         current_bid = final_bid;
         current_ask = final_ask;
         execution_price = current_bid;
         
         // ===== FIX 3B: DETAILED ENTRY PRICE TRACKING FOR SELL MARKET =====
         double market_sell_entry = current_bid;
         double sell_intended_vs_actual = MathAbs(market_sell_entry - signal.entry_price) / point;
         double sell_intended_vs_actual_pct = (signal.entry_price > 0) ? 
                                              (MathAbs(market_sell_entry - signal.entry_price) / signal.entry_price * 100) : 0;
         
         Log(LOG_INFO, "ProcessTradeRetry", symbol + " - SELL MARKET ENTRY SNAPSHOT: " +
             "Intended=" + DoubleToString(signal.entry_price, digits) + 
             ", Current_Bid=" + DoubleToString(current_bid, digits) +
             ", Current_Ask=" + DoubleToString(current_ask, digits) +
             ", Fallback_Entry=" + DoubleToString(market_sell_entry, digits) +
             ", Deviation=" + DoubleToString(sell_intended_vs_actual, 1) + 
             "p (" + DoubleToString(sell_intended_vs_actual_pct, 2) + "%%)");
         // ===== END FIX 3B =====
         
         if(!RunBrokerExecutionPreflight(retry, signal, symbol, execution_type, magic_number, signal_fp,
                                         ORDER_TYPE_SELL, GetSymbolFillingMode(symbol), lot_size, execution_price,
                                         adjusted_sl, adjusted_tp, deviation_points, 0, comment,
                                         retry_interval, digits, already_live))
         {
            return false;
         }
         if(already_live)
            return true;

         execution_result = trade.Sell(lot_size, symbol, 0, // Use 0 for market price
                                       adjusted_sl, adjusted_tp,
                                       comment);
         
         // FIX #5: Post-execution slippage validation for market SELL (ENHANCED)
         if(execution_result)
         {
            double actual_fill = trade.ResultPrice();
            if(actual_fill > 0.0)
            {
               // Compare adverse movement only; a SELL filled above bid is price improvement.
               double market_slippage_points = MathMax(0.0, execution_price - actual_fill) / point;
               double market_slippage_pct = (execution_price > 0) ?
                                            (MathMax(0.0, execution_price - actual_fill) / execution_price * 100) : 0;
               
               // Compare to original intended entry (total entry deviation)
               double entry_deviation_points = MathMax(0.0, signal.entry_price - actual_fill) / point;
               double entry_deviation_pct = (signal.entry_price > 0) ?
                                            (MathMax(0.0, signal.entry_price - actual_fill) / signal.entry_price * 100) : 0;
               
               // Log both metrics
               Log(LOG_INFO, "ProcessTradeRetry", symbol + " - SELL FILL ANALYSIS: " +
                   "SignalEntry=" + DoubleToString(signal.entry_price, digits) +
                   ", MarketOrder=" + DoubleToString(execution_price, digits) +
                   ", ActualFill=" + DoubleToString(actual_fill, digits) +
                   " | MarketSlippage=" + DoubleToString(market_slippage_points, 1) + 
                   "p | TotalDeviation=" + DoubleToString(entry_deviation_points, 1) + "p");
               
                if(max_acceptable_slippage_points > 0 &&
                   market_slippage_points > max_acceptable_slippage_points)
               {
                  Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                      " - MARKET SLIPPAGE WARNING (SELL): Slippage=" + DoubleToString(market_slippage_points, 1) + 
                      "p (" + DoubleToString(market_slippage_pct, 2) + "%)");
               }
               
                if(max_acceptable_slippage_points > 0 &&
                   entry_deviation_points > max_acceptable_slippage_points * 2)
               {
                  Log(LOG_WARNING, "ProcessTradeRetry", symbol +
                      " - ENTRY DEVIATION WARNING (SELL): Total deviation from intended=" + 
                      DoubleToString(entry_deviation_points, 1) + 
                      "p (" + DoubleToString(entry_deviation_pct, 2) + "%)");
               }
               
               AuditLog("SELL_ENTRY_ANALYSIS", symbol,
                       "Signal=" + DoubleToString(signal.entry_price, digits) +
                       ", Filled=" + DoubleToString(actual_fill, digits) +
                       ", Dev=" + DoubleToString(entry_deviation_points, 1) + "p");
            }
         }
      }

      primary_result_captured = true;
      primary_result_retcode = (int)trade.ResultRetcode();
      primary_result_retcode_desc = trade.ResultRetcodeDescription();
      primary_result_order = trade.ResultOrder();
      primary_result_deal = trade.ResultDeal();
      primary_result_price = trade.ResultPrice();
   }

   bool is_pending_order = (StringFind(execution_type, "PENDING") >= 0);
   int result_retcode = (primary_result_captured ? primary_result_retcode : (int)trade.ResultRetcode());
   string result_retcode_desc = (primary_result_captured ? primary_result_retcode_desc : trade.ResultRetcodeDescription());
   bool broker_execution_ok = (execution_result && IsSuccessfulTradeRetcode(result_retcode, is_pending_order));

   if(broker_execution_ok)
   {
      // Market orders consume daily trade budget on broker acceptance; pending orders consume
      // budget on actual fill (tracked via DEAL_ENTRY_IN in TrackClosedTrades).
      ulong result_order = (primary_result_captured ? primary_result_order : trade.ResultOrder());
      ulong result_deal = (primary_result_captured ? primary_result_deal : trade.ResultDeal());
      int entry_auto_mode = ExtractAutoModeFromSignalReason(signal.reason);
      int entry_strategy_mode = ExtractDirectorStrategyModeFromSignal(signal);
      double logged_price = (primary_result_captured ? primary_result_price : trade.ResultPrice());
      if(is_pending_order)
      {
         logged_price = execution_price;
         if(result_order > 0 && OrderSelect(result_order))
            logged_price = OrderGetDouble(ORDER_PRICE_OPEN);
      }

      if(!is_pending_order && g_Execution_Max_Slippage_Pips > 0.0 &&
         expected_market_price > 0.0 && pip_size > 0.0 && logged_price > 0.0)
      {
         double adverse_slippage_price = 0.0;
         if(signal.direction == 1)
            adverse_slippage_price = MathMax(0.0, logged_price - expected_market_price);
         else if(signal.direction == -1)
            adverse_slippage_price = MathMax(0.0, expected_market_price - logged_price);
         else
            adverse_slippage_price = MathAbs(logged_price - expected_market_price);

         double actual_slippage_pips = adverse_slippage_price / pip_size;
         if(actual_slippage_pips > g_Execution_Max_Slippage_Pips)
         {
            g_exec_slippage_violations++;
            RecordRejectReason("EXECQ:SlippageBreach");
            string slip_msg = StringFormat("%s - Slippage breach %.2f pips > %.2f pips (expected=%.5f, fill=%.5f)",
                                           symbol, actual_slippage_pips, g_Execution_Max_Slippage_Pips,
                                           expected_market_price, logged_price);
            Log(LOG_WARNING, "ProcessTradeRetry", slip_msg);
            AuditLog("EXECQ_SLIPPAGE", symbol, slip_msg);
            AuditLogSignal("EXECUTE_REJECT_SLIPPAGE", symbol, signal,
                           slip_msg + " SigFP=" + StringFormat("%I64u", signal_fp));

            if(CloseRejectedMarketFill(symbol, magic_number, actual_slippage_pips,
                                       g_Execution_Max_Slippage_Pips,
                                       expected_market_price, logged_price))
            {
               retry.attempt = g_Max_Retry_Attempts;
               return false;
            }

            Log(LOG_WARNING, "ProcessTradeRetry",
                symbol + " - Slipped fill remains open because immediate close failed; continuing normal position management");
         }
      }

      if(g_Use_Institutional_Strategy_Director &&
         result_order > 0 &&
         (entry_auto_mode != AUTO_REGIME_MODE_DISABLED || entry_strategy_mode >= 0))
      {
         DirectorRegisterOrderIntent(symbol, result_order, entry_auto_mode, entry_strategy_mode, now);
         if(g_Enable_Institutional_Debug)
         {
            Log(LOG_DEBUG, "ProcessTradeRetry",
                symbol + " - Director intent registered: order=" + (string)result_order +
                " mode=" + IntegerToString(entry_auto_mode) +
                " strategy=" + IntegerToString(entry_strategy_mode));
         }
      }

      bool position_opened = false;

      // For market orders, deal execution is the most reliable fill confirmation.
      if(!is_pending_order)
      {
         if(result_deal > 0)
            position_opened = true;
         else
         {
            ulong pos_ticket = 0;
            if(FindOpenPositionByMagic(symbol, magic_number, pos_ticket))
               position_opened = true;
         }

         // Market execution accepted by broker counts as a daily trade even if fill confirmation
         // is delayed for this tick. Pending orders are counted on DEAL_ENTRY_IN in history tracking.
         g_trades_today++;
         PersistRiskSessionState();
      }
      else
      {
         retry.ticket = result_order;
         retry.order_placed = (result_order > 0);
         if(retry.order_placed)
         {
            Log(LOG_INFO, "ProcessTradeRetry", symbol + " - Pending order accepted by broker, ticket=" +
                IntegerToString(retry.ticket));
         }
      }

      if(position_opened)
      {
         g_position_count_cache.last_update = 0;
         if(symbol_index >= 0 && symbol_index < MAX_SYMBOLS)
         {
            g_symbols[symbol_index].positions_count++;
            g_symbols[symbol_index].last_position_open = TimeCurrent();
            g_symbols[symbol_index].last_signal_time = g_symbols[symbol_index].last_position_open;
         }
         g_debug_trades_executed++;
         // DEBUG: Track successful executions
         g_debug_counters.trades_executed++;
         g_last_trade_time = TimeCurrent();
      }
      else
      {
          if(is_pending_order)
             Log(LOG_DEBUG, "ProcessTradeRetry", symbol + " - Pending order placed; counters update on fill");
          else
             Log(LOG_DEBUG, "ProcessTradeRetry", symbol + " - No immediate fill confirmation; position counters not incremented yet");
      }
      
      string trade_msg = StringFormat("%s - %s ORDER %s: %s | Price: %.5f | SL: %.5f | TP: %.5f | Lot: %.2f | Magic: %d | RR: %.2f",
         symbol,
         execution_type,
         (position_opened ? "EXECUTED" : "PLACED"),
         (signal.direction == 1 ? "BUY" : "SELL"),
         logged_price, // Prefer broker-confirmed price; fallback to requested pending price
         adjusted_sl, // Use adjusted SL
         adjusted_tp, // Use adjusted TP
         lot_size,
         magic_number,
         signal.risk_reward_ratio);
      
      if(g_debug_trades_enabled)
      {
         Print("[DEBUG] TRADE EXECUTED: ", trade_msg);
      }
      
      Log(LOG_INFO, "ProcessTradeRetry", trade_msg);
      SendAlert(ALERT_TRADE_OPEN, trade_msg);
      string audit_exec_msg = StringFormat("Type=%s Retcode=%d Order=%I64u Deal=%I64u Price=%.5f",
                                           execution_type, result_retcode, result_order, result_deal, logged_price);
      AuditLogSignal("EXECUTE_OK", symbol, signal,
                     audit_exec_msg + " SigFP=" + StringFormat("%I64u", signal_fp));
   }
   else
   {
      retry.ticket = 0;
      retry.order_placed = false;
      g_debug_trades_failed++;
      
      // DEBUG: Track failed executions
      g_debug_counters.trades_failed++;
      
      string error_msg = StringFormat("%s - %s ORDER FAILED attempt %d: %s (Retcode: %d)",
         symbol, execution_type, retry.attempt + 1, 
         result_retcode_desc, result_retcode);
      
      if(g_debug_trades_enabled)
      {
         Print("[DEBUG] TRADE FAILED: ", error_msg);
      }
      
      Log(LOG_ERROR, "ProcessTradeRetry", error_msg);
      string audit_fail_msg = StringFormat("Type=%s Retcode=%d %s",
                                           execution_type, result_retcode, result_retcode_desc);
      AuditLogSignal("EXECUTE_FAIL", symbol, signal,
                     audit_fail_msg + " SigFP=" + StringFormat("%I64u", signal_fp));
      
      // ENHANCED: Better error classification and immediate retry for certain errors
      int retcode = result_retcode;
      string retcode_desc = result_retcode_desc;

      if(is_pending_order &&
         (retcode == TRADE_RETCODE_INVALID_PRICE || retcode == TRADE_RETCODE_PRICE_OFF))
      {
         int err_stop_level = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
         int err_freeze_level = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
         Log(LOG_WARNING, "ProcessTradeRetry", symbol +
             " - Pending failure context: Type=" + execution_type +
             ", Entry=" + DoubleToString(execution_price, digits) +
             ", Bid=" + DoubleToString(current_bid, digits) +
             ", Ask=" + DoubleToString(current_ask, digits) +
             ", SL=" + DoubleToString(adjusted_sl, digits) +
             ", TP=" + DoubleToString(adjusted_tp, digits) +
             ", StopsLevel=" + IntegerToString(err_stop_level) +
             ", FreezeLevel=" + IntegerToString(err_freeze_level));
      }
      
      // Immediate retry for price-related errors
      bool pending_invalid_price = (is_pending_order && retcode == TRADE_RETCODE_INVALID_PRICE);
      if(retcode == TRADE_RETCODE_REQUOTE || retcode == TRADE_RETCODE_PRICE_OFF || pending_invalid_price)
      {
         RecordRejectReason(pending_invalid_price ? "BROKER:PendingInvalidPrice" : "BROKER:PriceIssue");
         retry.next_retry = now + MathMax(1, retry_interval);
         Log(LOG_INFO, "ProcessTradeRetry", symbol + 
             " - PRICE ISSUE: " + retcode_desc +
             (pending_invalid_price ? " (pending price will be re-anchored on retry)." : "") +
             " Retrying.");
         return false; // Retry immediately
      }
      
      if(IsPermanentError(retcode, retcode_desc))
      {
         RecordRejectReason("BROKER:PermanentError");
         // Unrecoverable error - don't retry
         Log(LOG_ERROR, "ProcessTradeRetry", symbol + 
             " - PERMANENT ERROR: " + retcode_desc + 
             ". Removing from retry queue (will not retry).");
         retry.attempt = g_Max_Retry_Attempts; // Force removal on return
         return false;  // Signal permanent failure, remove from queue
      }
      else if(IsRecoverableError(retcode, retcode_desc))
      {
         RecordRejectReason("BROKER:RecoverableError");
         // Recoverable error - log and allow retry
         Log(LOG_WARNING, "ProcessTradeRetry", symbol + 
             " - RECOVERABLE ERROR: " + retcode_desc + 
             ". Will retry (attempt " + IntegerToString(retry.attempt + 1) + ").");
         return false;  // Return false to trigger retry logic
      }
      
      // Default: unknown error - log and allow retry
      RecordRejectReason("BROKER:UnknownError");
      Log(LOG_WARNING, "ProcessTradeRetry", symbol + 
          " - Error (" + IntegerToString(retcode) + "): " + retcode_desc + 
          ". Will retry.");
      return false;
   }

   return broker_execution_ok;
}

int SeedTodayPendingEntryOrders(datetime day_start, datetime now, ulong &order_ids[])
{
   ArrayInitialize(order_ids, 0);
   if(!HistorySelect(day_start, now))
      return 0;

   int seeded_count = 0;
   int deals_total = HistoryDealsTotal();
   int max_orders = ArraySize(order_ids);
   for(int i = 0; i < deals_total && seeded_count < max_orders; i++)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket == 0)
         continue;

      long deal_magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
      if(deal_magic < Magic_Base || deal_magic >= Magic_Base + 10000)
         continue;

      ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
      ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal_ticket, DEAL_TYPE);
      if(deal_entry != DEAL_ENTRY_IN || (deal_type != DEAL_TYPE_BUY && deal_type != DEAL_TYPE_SELL))
         continue;

      ulong deal_order = (ulong)HistoryDealGetInteger(deal_ticket, DEAL_ORDER);
      if(deal_order == 0 || !HistoryOrderSelect(deal_order))
         continue;
      if(PendingOrderDirectionFromType(HistoryOrderGetInteger(deal_order, ORDER_TYPE)) == 0)
         continue;

      bool seen_order = false;
      for(int oi = 0; oi < seeded_count; oi++)
      {
         if(order_ids[oi] == deal_order)
         {
            seen_order = true;
            break;
         }
      }

      if(!seen_order)
         order_ids[seeded_count++] = deal_order;
   }

   return seeded_count;
}


void RestoreIntradayExecutionStateFromHistory(datetime now)
{
   datetime day_start = (g_trade_day > 0 ? g_trade_day : (now / 86400) * 86400);
   if(day_start <= 0)
      day_start = now - 86400;

   // Preserve same-day hard risk latches restored during init. History bootstrap should
   // rebuild intraday counters, but it must never silently clear an active kill switch.
   bool preserved_kill_switch_active = g_Kill_Switch_Active;
   datetime preserved_kill_switch_activated_time = g_Kill_Switch_Activated_Time;
   string preserved_kill_switch_reason = g_Kill_Switch_Reason;
   bool preserved_daily_loss_latched = g_Kill_Switch_Daily_Loss_Latched;
   double preserved_trigger_loss_pct = g_Kill_Switch_Trigger_Loss_Pct;
   double preserved_trigger_limit_pct = g_Kill_Switch_Trigger_Limit_Pct;
   double preserved_trigger_day_start_equity = g_Kill_Switch_Trigger_Day_Start_Equity;
   int preserved_kill_switch_triggers = g_kill_switch_triggers;

   if(!HistorySelect(day_start, now))
   {
      Log(LOG_WARNING, "RestoreIntradayExecutionStateFromHistory", "HistorySelect failed");
      return;
   }

   g_trades_today = 0;
   g_consecutive_losses = 0;
   g_consecutive_wins = 0;
   g_risk_cooldown_until = 0;
   for(int si = 0; si < MAX_SYMBOLS; si++)
   {
      g_symbol_loss_streak[si] = 0;
      g_symbol_last_loss_time[si] = 0;
      g_symbol_loss_cooldown_until[si] = 0;
   }

   ulong entry_keys[];
   ulong closed_position_keys[];
   double closed_position_net[];
   datetime closed_position_time[];
   string closed_position_symbol[];

   int deals_total = HistoryDealsTotal();
   const double DEAL_NEUTRAL_EPS = 0.01;
   for(int i = 0; i < deals_total; i++)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket == 0)
         continue;

      long deal_magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
      if(deal_magic < Magic_Base || deal_magic >= Magic_Base + 10000)
         continue;

      ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
      ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal_ticket, DEAL_TYPE);
      if(deal_type != DEAL_TYPE_BUY && deal_type != DEAL_TYPE_SELL)
         continue;

      ulong position_id = (ulong)HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID);
      ulong deal_order = (ulong)HistoryDealGetInteger(deal_ticket, DEAL_ORDER);
      ulong entry_key = (position_id > 0 ? position_id : (deal_order > 0 ? deal_order : deal_ticket));

      if(deal_entry == DEAL_ENTRY_IN)
      {
         bool seen_entry = false;
         for(int ei = 0; ei < ArraySize(entry_keys); ei++)
         {
            if(entry_keys[ei] == entry_key)
            {
               seen_entry = true;
               break;
            }
         }

         if(!seen_entry)
         {
            int new_size = ArraySize(entry_keys) + 1;
            ArrayResize(entry_keys, new_size);
            entry_keys[new_size - 1] = entry_key;
         }
         continue;
      }

      if(deal_entry != DEAL_ENTRY_OUT && deal_entry != DEAL_ENTRY_OUT_BY && deal_entry != DEAL_ENTRY_INOUT)
         continue;

      int close_index = -1;
      for(int ci = 0; ci < ArraySize(closed_position_keys); ci++)
      {
         if(closed_position_keys[ci] == entry_key)
         {
            close_index = ci;
            break;
         }
      }

      if(close_index < 0)
      {
         int new_size = ArraySize(closed_position_keys) + 1;
         ArrayResize(closed_position_keys, new_size);
         ArrayResize(closed_position_net, new_size);
         ArrayResize(closed_position_time, new_size);
         ArrayResize(closed_position_symbol, new_size);
         close_index = new_size - 1;
         closed_position_keys[close_index] = entry_key;
         closed_position_net[close_index] = 0.0;
         closed_position_time[close_index] = 0;
         closed_position_symbol[close_index] = "";
      }

      double deal_net = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT) +
                        HistoryDealGetDouble(deal_ticket, DEAL_SWAP) +
                        HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
      datetime deal_time = (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME);
      string deal_symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);

      closed_position_net[close_index] += deal_net;
      if(deal_time >= closed_position_time[close_index])
      {
         closed_position_time[close_index] = deal_time;
         closed_position_symbol[close_index] = deal_symbol;
      }
   }

   g_trades_today = ArraySize(entry_keys);

   int close_count = ArraySize(closed_position_keys);
   for(int i = 0; i < close_count - 1; i++)
   {
      for(int j = i + 1; j < close_count; j++)
      {
         if(closed_position_time[j] < closed_position_time[i])
         {
            ulong swap_key = closed_position_keys[i];
            closed_position_keys[i] = closed_position_keys[j];
            closed_position_keys[j] = swap_key;

            double swap_net = closed_position_net[i];
            closed_position_net[i] = closed_position_net[j];
            closed_position_net[j] = swap_net;

            datetime swap_time = closed_position_time[i];
            closed_position_time[i] = closed_position_time[j];
            closed_position_time[j] = swap_time;

            string swap_symbol = closed_position_symbol[i];
            closed_position_symbol[i] = closed_position_symbol[j];
            closed_position_symbol[j] = swap_symbol;
         }
      }
   }

   int symbol_window_seconds = (int)MathMax(60, g_Symbol_Loss_Streak_Window_Minutes * 60);
   for(int i = 0; i < close_count; i++)
   {
      bool trade_profitable = (closed_position_net[i] > DEAL_NEUTRAL_EPS);
      bool trade_losing = (closed_position_net[i] < -DEAL_NEUTRAL_EPS);
      bool trade_neutral = (!trade_profitable && !trade_losing);
      bool execution_rejected_position = IsExecutionRejectedPosition(closed_position_keys[i]);

      if(g_Enable_Institutional_Risk && !execution_rejected_position)
      {
         if(trade_profitable)
         {
            g_consecutive_wins++;
            g_consecutive_losses = 0;
         }
         else if(trade_losing)
         {
            g_consecutive_losses++;
            g_consecutive_wins = 0;

            if(Max_Consecutive_Losses > 0 && Loss_Cooldown_Minutes > 0 &&
               g_consecutive_losses >= Max_Consecutive_Losses)
            {
               datetime cooldown_until = closed_position_time[i] + (Loss_Cooldown_Minutes * 60);
               if(cooldown_until > g_risk_cooldown_until)
                  g_risk_cooldown_until = cooldown_until;
            }
         }
      }

      if(g_Enable_Institutional_Risk &&
         g_Enable_Symbol_Loss_Circuit_Breaker &&
         g_Symbol_Loss_Streak_Threshold > 0 &&
         !execution_rejected_position)
      {
         int symbol_index = GetSymbolIndex(closed_position_symbol[i]);
         if(symbol_index >= 0 && symbol_index < MAX_SYMBOLS)
         {
            if(trade_profitable || trade_neutral)
            {
               g_symbol_loss_streak[symbol_index] = 0;
               if(trade_profitable)
                  g_symbol_last_loss_time[symbol_index] = 0;
            }
            else if(trade_losing)
            {
               if(g_symbol_last_loss_time[symbol_index] > 0 &&
                  (closed_position_time[i] - g_symbol_last_loss_time[symbol_index]) <= symbol_window_seconds)
               {
                  g_symbol_loss_streak[symbol_index]++;
               }
               else
               {
                  g_symbol_loss_streak[symbol_index] = 1;
               }

               g_symbol_last_loss_time[symbol_index] = closed_position_time[i];

               if(g_symbol_loss_streak[symbol_index] >= g_Symbol_Loss_Streak_Threshold)
               {
                  datetime symbol_cooldown_until = closed_position_time[i] +
                                                   (datetime)(MathMax(1, g_Symbol_Loss_Cooldown_Minutes) * 60);
                  if(symbol_cooldown_until > g_symbol_loss_cooldown_until[symbol_index])
                     g_symbol_loss_cooldown_until[symbol_index] = symbol_cooldown_until;

                  g_symbol_loss_streak[symbol_index] = 0;
               }
            }
         }
      }
   }

   Log(LOG_INFO, "RestoreIntradayExecutionStateFromHistory",
       "Restored intraday state: trades_today=" + IntegerToString(g_trades_today) +
       ", wins=" + IntegerToString(g_consecutive_wins) +
       ", losses=" + IntegerToString(g_consecutive_losses) +
       ", risk_cooldown_until=" + TimeToString(g_risk_cooldown_until));

   g_Kill_Switch_Active = preserved_kill_switch_active;
   g_Kill_Switch_Activated_Time = preserved_kill_switch_activated_time;
   g_Kill_Switch_Reason = preserved_kill_switch_reason;
   g_Kill_Switch_Daily_Loss_Latched = preserved_daily_loss_latched;
   g_Kill_Switch_Trigger_Loss_Pct = preserved_trigger_loss_pct;
   g_Kill_Switch_Trigger_Limit_Pct = preserved_trigger_limit_pct;
   g_Kill_Switch_Trigger_Day_Start_Equity = preserved_trigger_day_start_equity;
   g_kill_switch_triggers = preserved_kill_switch_triggers;

   PersistRiskSessionState();
}

void TrackClosedTrades(bool force_scan = false)
{
   static datetime last_check = 0;
   static datetime last_processed_time = 0;
   static ulong last_processed_ticket = 0;
   static int last_deals_total = -1;
   static bool history_bootstrapped = false;
   static ulong counted_pending_entry_orders[256];
   static int counted_pending_entry_count = 0;
   datetime now = TimeCurrent();
   
   // Check every 10 seconds unless a broker event explicitly forces a sync.
   if(!force_scan && now - last_check < 10) return;
   last_check = now;

   // Keep day-scoped counters and cooldown state aligned even when no new trade attempts occur.
   if(UpdateDailyCounters())
      counted_pending_entry_count = 0;
   datetime active_trade_day = (g_trade_day > 0 ? g_trade_day : GetMarketDay(now));
   
   // Narrow history window to reduce load; keep small overlap for safety
   datetime select_from = (last_processed_time > 0 ? last_processed_time - 60 : now - 86400);
   if(select_from < 0) select_from = 0;
   
   if(!HistorySelect(select_from, now))
   {
      Log(LOG_WARNING, "TrackClosedTrades", "HistorySelect failed");
      return;
   }
   
   int deals_total = HistoryDealsTotal();
   if(!history_bootstrapped)
   {
      history_bootstrapped = true;
      counted_pending_entry_count = SeedTodayPendingEntryOrders(active_trade_day, now, counted_pending_entry_orders);
      RestoreIntradayExecutionStateFromHistory(now);
      if(!HistorySelect(select_from, now))
      {
         Log(LOG_WARNING, "TrackClosedTrades", "HistorySelect failed after bootstrap restore");
         return;
      }
      deals_total = HistoryDealsTotal();
      if(deals_total > 0)
      {
         ulong bootstrap_ticket = HistoryDealGetTicket(deals_total - 1);
         if(bootstrap_ticket > 0)
         {
            last_processed_time = (datetime)HistoryDealGetInteger(bootstrap_ticket, DEAL_TIME);
            last_processed_ticket = bootstrap_ticket;
            last_deals_total = deals_total;
            Log(LOG_INFO, "TrackClosedTrades", "History baseline set at latest deal #" +
                (string)bootstrap_ticket + " to avoid replaying stale streak events");
            return;
         }
      }
      else
      {
         // No history yet: anchor cursor at "now" so later activity doesn't replay stale windows.
         last_processed_time = now;
      }
   }

   if(deals_total > 0)
   {
      ulong latest_ticket = HistoryDealGetTicket(deals_total - 1);
      datetime latest_time = (datetime)HistoryDealGetInteger(latest_ticket, DEAL_TIME);
      if(latest_time == last_processed_time && latest_ticket == last_processed_ticket)
      {
         return; // Latest deal already processed
      }
   }
    else if(last_deals_total == 0 && last_processed_time > 0)
   {
      return;
   }
   last_deals_total = deals_total;

   int new_deal_indices[];
   ArrayResize(new_deal_indices, deals_total);
   int new_deal_count = 0;
   for(int i = deals_total - 1; i >= 0; i--)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket == 0)
         continue;

      datetime deal_time = (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME);
      if(deal_time < last_processed_time)
         break;
      if(deal_time == last_processed_time && deal_ticket <= last_processed_ticket)
         break;

      new_deal_indices[new_deal_count++] = i;
   }

   for(int ni = new_deal_count - 1; ni >= 0; ni--)
   {
      int i = new_deal_indices[ni];
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket == 0) continue;
      
      datetime deal_time = (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME);
      if(deal_time < last_processed_time) continue;
      if(deal_time == last_processed_time && deal_ticket <= last_processed_ticket) continue;

      // Advance cursor for every unseen deal (including non-EA/mismatched ones) to avoid rescanning.
      if(deal_time > last_processed_time || (deal_time == last_processed_time && deal_ticket > last_processed_ticket))
      {
         last_processed_time = deal_time;
         last_processed_ticket = deal_ticket;
      }
      
      ENUM_DEAL_REASON deal_reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(deal_ticket, DEAL_REASON);
      ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
      ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal_ticket, DEAL_TYPE);
      ulong deal_order = (ulong)HistoryDealGetInteger(deal_ticket, DEAL_ORDER);
      long deal_magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
      
      // Only track our EA's completed deals
      if(deal_magic < Magic_Base || deal_magic >= Magic_Base + 10000) continue;
      if(deal_type != DEAL_TYPE_BUY && deal_type != DEAL_TYPE_SELL) continue;

      // Pending fill accounting: ensure daily trade cap also applies to pending-order executions.
      if(deal_entry == DEAL_ENTRY_IN)
      {
         string entry_symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
         ulong position_id = (ulong)HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID);
         int entry_auto_mode = AUTO_REGIME_MODE_DISABLED;
         int entry_strategy_mode = -1;
         datetime entry_intent_time = 0;
         if(g_Use_Institutional_Strategy_Director &&
            deal_order > 0 &&
            DirectorConsumeOrderIntent(entry_symbol, deal_order, entry_auto_mode,
                                       entry_strategy_mode, entry_intent_time))
         {
            DirectorRegisterOpenPositionContext(entry_symbol, position_id,
                                                entry_auto_mode, entry_strategy_mode, deal_time);
            if(g_Enable_Institutional_Debug)
            {
               Log(LOG_DEBUG, "TrackClosedTrades",
                   entry_symbol + " - Director open context linked: position=" + (string)position_id +
                   " order=" + (string)deal_order +
                   " mode=" + IntegerToString(entry_auto_mode) +
                   " strategy=" + IntegerToString(entry_strategy_mode));
            }
         }

         bool from_pending = false;
         if(deal_order > 0 && HistoryOrderSelect(deal_order))
         {
            long order_type = HistoryOrderGetInteger(deal_order, ORDER_TYPE);
            from_pending = (order_type == ORDER_TYPE_BUY_LIMIT ||
                            order_type == ORDER_TYPE_SELL_LIMIT ||
                            order_type == ORDER_TYPE_BUY_STOP ||
                            order_type == ORDER_TYPE_SELL_STOP ||
                            order_type == ORDER_TYPE_BUY_STOP_LIMIT ||
                            order_type == ORDER_TYPE_SELL_STOP_LIMIT);
         }

         if(from_pending && deal_order > 0)
         {
            bool seen_order = false;
            for(int oi = 0; oi < counted_pending_entry_count; oi++)
            {
               if(counted_pending_entry_orders[oi] == deal_order)
               {
                  seen_order = true;
                  break;
               }
            }

            if(!seen_order)
            {
               bool counts_toward_today = (deal_time >= active_trade_day);
               g_position_count_cache.last_update = 0;
               if(counted_pending_entry_count >= 256)
               {
                  for(int sh = 1; sh < 256; sh++)
                     counted_pending_entry_orders[sh - 1] = counted_pending_entry_orders[sh];
                  counted_pending_entry_count = 255;
               }
               counted_pending_entry_orders[counted_pending_entry_count++] = deal_order;

               int entry_symbol_index = GetSymbolIndex(entry_symbol);
               if(entry_symbol_index >= 0 && entry_symbol_index < g_symbols_count)
               {
                  g_symbols[entry_symbol_index].positions_count = CountOurOpenPositions(entry_symbol);
                  if(deal_time > g_symbols[entry_symbol_index].last_position_open)
                     g_symbols[entry_symbol_index].last_position_open = deal_time;
                  if(g_symbols[entry_symbol_index].last_position_open > g_symbols[entry_symbol_index].last_signal_time)
                     g_symbols[entry_symbol_index].last_signal_time = g_symbols[entry_symbol_index].last_position_open;
               }

               if(counts_toward_today)
               {
                  g_trades_today++;
                  PersistRiskSessionState();
                  g_debug_trades_executed++;
                  g_debug_counters.trades_executed++;

                  Log(LOG_INFO, "TrackClosedTrades", entry_symbol +
                      " - Pending fill counted toward daily cap via order #" + (string)deal_order +
                      " (trades today: " + IntegerToString(g_trades_today) + "/" +
                      IntegerToString(g_Max_Trades_Per_Day_Effective) + ")");
                  AuditLog("EXECUTE_FILL", entry_symbol,
                           "Pending fill via order #" + (string)deal_order +
                           " (trades today: " + IntegerToString(g_trades_today) + "/" +
                           IntegerToString(g_Max_Trades_Per_Day_Effective) + ")");
               }
               else
               {
                  Log(LOG_INFO, "TrackClosedTrades", entry_symbol +
                      " - Historical pending fill via order #" + (string)deal_order +
                      " predates current market day; syncing state without consuming today's trade cap");
               }

               if(deal_time > g_last_trade_time)
                  g_last_trade_time = deal_time;
            }
         }
         continue;
      }

      if(deal_entry != DEAL_ENTRY_OUT && deal_entry != DEAL_ENTRY_OUT_BY && deal_entry != DEAL_ENTRY_INOUT) continue;
      
      double deal_profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
      double deal_swap = HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
      double deal_commission = HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
      double deal_net = deal_profit + deal_swap + deal_commission;
      string deal_symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
      ulong deal_position_id = (ulong)HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID);
      int symbol_index = GetSymbolIndex(deal_symbol);

      double trade_net = deal_net;
      bool final_trade_close = UpdateBacktestMetricsOnClose(deal_symbol, deal_time, deal_position_id, deal_net, trade_net);
      bool execution_rejected_position = IsExecutionRejectedPosition(deal_position_id);

      if(final_trade_close && g_Use_Institutional_Strategy_Director && deal_position_id > 0)
      {
         string learning_msg = "";
         if(DirectorLearnFromClose(deal_symbol, deal_position_id, trade_net, deal_time, learning_msg))
            Log(LOG_INFO, "TrackClosedTrades", learning_msg);
      }

      // Use full realized trade PnL on final close and ignore near-zero exits to avoid false streak signals.
      const double DEAL_NEUTRAL_EPS = 0.01;
      bool trade_profitable = (trade_net > DEAL_NEUTRAL_EPS);
      bool trade_losing = (trade_net < -DEAL_NEUTRAL_EPS);
      bool trade_neutral = (!trade_profitable && !trade_losing);
      if(final_trade_close && !trade_neutral && !execution_rejected_position)
         g_ai_manager.UpdateAccuracy(trade_profitable);

      if(final_trade_close && execution_rejected_position)
      {
         Log(LOG_INFO, "TrackClosedTrades", deal_symbol +
             " - Execution-rejected fill close excluded from strategy loss cooldown accounting");
      }
       
      if(final_trade_close && g_Enable_Institutional_Risk && !execution_rejected_position)
      {
         if(trade_profitable)
         {
            g_consecutive_wins++;
            g_consecutive_losses = 0;
         }
         else if(trade_losing)
         {
            g_consecutive_losses++;
            g_consecutive_wins = 0;
            // Kill Switch consecutive loss check handled in EvaluateKillSwitchDailyLoss()
            // via enum-driven mode selection
             
            if(Max_Consecutive_Losses > 0 && Loss_Cooldown_Minutes > 0 &&
               g_consecutive_losses >= Max_Consecutive_Losses)
            {
               datetime cooldown_until = now + (Loss_Cooldown_Minutes * 60);
               if(cooldown_until > g_risk_cooldown_until)
                  g_risk_cooldown_until = cooldown_until;

               double equity_now = AccountInfoDouble(ACCOUNT_EQUITY);
               double daily_dd_pct = SafeDiv(g_equity_day_start - equity_now, g_equity_day_start, 0.0) * 100.0;
               double equity_ref = (g_equity_all_time_high > 0.0 ? g_equity_all_time_high : equity_now);
               double account_dd_pct = SafeDiv(equity_ref - equity_now, equity_ref, 0.0) * 100.0;
               
               string msg = StringFormat("Loss streak limit reached (%d/%d). Risk cooldown active until %s (Daily DD: %.2f%%, Account DD: %.2f%%)",
                                         g_consecutive_losses, Max_Consecutive_Losses,
                                         TimeToString(g_risk_cooldown_until),
                                         daily_dd_pct, account_dd_pct);
               Log(LOG_WARNING, "TrackClosedTrades", msg);
               if(Enable_Drawdown_Alerts)
                  // Loss-streak cooldown is a risk-control event, not an equity drawdown breach.
                  SendAlert(ALERT_RISK_CONTROL, msg);
            }
         }

         if(g_Enable_Symbol_Loss_Circuit_Breaker &&
            symbol_index >= 0 && symbol_index < MAX_SYMBOLS)
         {
            if(trade_profitable || trade_neutral)
            {
               g_symbol_loss_streak[symbol_index] = 0;
               if(trade_profitable)
                  g_symbol_last_loss_time[symbol_index] = 0;
            }
            else if(trade_losing)
            {
               int window_seconds = (int)MathMax(60, g_Symbol_Loss_Streak_Window_Minutes * 60);
               if(g_symbol_last_loss_time[symbol_index] > 0 &&
                  (deal_time - g_symbol_last_loss_time[symbol_index]) <= window_seconds)
               {
                  g_symbol_loss_streak[symbol_index]++;
               }
               else
               {
                  g_symbol_loss_streak[symbol_index] = 1;
               }
               g_symbol_last_loss_time[symbol_index] = deal_time;

               if(g_symbol_loss_streak[symbol_index] >= g_Symbol_Loss_Streak_Threshold)
               {
                  datetime symbol_cooldown_until = deal_time + (datetime)(MathMax(1, g_Symbol_Loss_Cooldown_Minutes) * 60);
                  if(symbol_cooldown_until > g_symbol_loss_cooldown_until[symbol_index])
                     g_symbol_loss_cooldown_until[symbol_index] = symbol_cooldown_until;

                  string symbol_msg = StringFormat("%s - Symbol loss circuit breaker triggered (%d losses within %d min). Cooldown until %s",
                                                   deal_symbol,
                                                   g_symbol_loss_streak[symbol_index],
                                                   g_Symbol_Loss_Streak_Window_Minutes,
                                                   TimeToString(g_symbol_loss_cooldown_until[symbol_index]));
                  Log(LOG_WARNING, "TrackClosedTrades", symbol_msg);
                  if(Enable_Drawdown_Alerts)
                     SendAlert(ALERT_RISK_CONTROL, symbol_msg);

                  g_symbol_loss_streak[symbol_index] = 0;
               }
            }
         }
      }
      
      // Get position details for better accuracy tracking
      string close_type = (deal_reason == DEAL_REASON_TP) ? "TP" :
                         (deal_reason == DEAL_REASON_SL) ? "SL" :
                         (deal_reason == DEAL_REASON_EXPERT) ? "EXPERT" :
                         (deal_reason == DEAL_REASON_CLIENT) ? "MANUAL" : "OTHER";
      
      Log(LOG_DEBUG, "TrackClosedTrades", 
          deal_symbol + " - Deal #" + IntegerToString(deal_ticket) + 
          " [" + close_type + "] " + (final_trade_close ? "FINAL " : "PARTIAL ") +
          (trade_profitable ? "WIN" : (trade_losing ? "LOSS" : "NEUTRAL")) + 
          " - Net P&L: $" + DoubleToString(deal_net, 2) +
          (final_trade_close && MathAbs(trade_net - deal_net) > DEAL_NEUTRAL_EPS ?
             " | TradeNet: $" + DoubleToString(trade_net, 2) : "") +
          " (profit=" + DoubleToString(deal_profit, 2) +
          ", swap=" + DoubleToString(deal_swap, 2) +
          ", commission=" + DoubleToString(deal_commission, 2) + ")");
      
      // Log AI assessment
      if(g_Enable_AI_Trend_Predictor_Runtime && symbol_index >= 0)
      {
         if((TimeCurrent() - g_ai_prediction_cache[symbol_index].last_update) < 300)
         {
            double ai_conf = g_ai_prediction_cache[symbol_index].confidence;
            Log(LOG_DEBUG, "TrackClosedTrades", 
                deal_symbol + " - AI Confidence at close: " + DoubleToString(ai_conf, 4));
         }
      }
   }
}


void ManageOpenPositions()
{
   // Throttle to avoid redundant work on every tick
   static uint last_manage_ms = 0;
   uint now_ms = GetTickCount();
   if(last_manage_ms != 0 && (now_ms - last_manage_ms) < 500)
      return;
   last_manage_ms = now_ms;

   if(IsStopped()) return;
   
   // Check profit target and drawdown limits first
   CheckProfitTargetAndDrawdown();

   static datetime last_partial_tracker_cleanup = 0;
   datetime now = TimeCurrent();
   if(last_partial_tracker_cleanup == 0 || (now - last_partial_tracker_cleanup) >= 60)
   {
      CompactPartialCloseTracker();
      CompactPeakProfitTracker();
      last_partial_tracker_cleanup = now;
   }

   int total_positions = PositionsTotal();
   if(total_positions == 0)
   {
      for(int i = 0; i < g_symbols_count; i++)
         g_symbols[i].positions_count = 0;
      return;
   }

   for(int i = total_positions - 1; i >= 0; i--)
   {
      if(IsStopped()) break;
      
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      string position_symbol = PositionGetString(POSITION_SYMBOL);
      long position_magic = PositionGetInteger(POSITION_MAGIC);
      
      if(position_magic < Magic_Base || position_magic >= Magic_Base + 10000)
         continue;

      // CRITICAL FIX: Safe enum validation and casting
      long position_type_long = PositionGetInteger(POSITION_TYPE);
      
      // Validate enum value before casting
      if(position_type_long < 0 || position_type_long > 1)
      {
         Log(LOG_WARNING, "ManageOpenPositions", "Invalid position type value: " + IntegerToString(position_type_long) + " for ticket " + IntegerToString(ticket));
         continue;
      }
      
      // Additional broker-specific validation
      if(position_type_long != POSITION_TYPE_BUY && position_type_long != POSITION_TYPE_SELL)
      {
         Log(LOG_WARNING, "ManageOpenPositions", "Unexpected position type from broker: " + IntegerToString(position_type_long));
         continue;
      }
      
      ENUM_POSITION_TYPE position_type = (ENUM_POSITION_TYPE)position_type_long;
      double position_open = PositionGetDouble(POSITION_PRICE_OPEN);
      double position_sl = PositionGetDouble(POSITION_SL);
      double position_tp = PositionGetDouble(POSITION_TP);
      double position_volume = PositionGetDouble(POSITION_VOLUME);

      // Issue 3.8: CSymbolInfo validation with proper error checking
      CSymbolInfo sym;
      if(!sym.Name(position_symbol))
      {
         Log(LOG_WARNING, "ManageOpenPositions", "Failed to set symbol " + position_symbol);
         continue;
      }
      
      if(!sym.RefreshRates())
      {
         Log(LOG_WARNING, "ManageOpenPositions", "Failed to refresh " + position_symbol);
         continue;
      }
      
      // Validate symbol prices are valid
      if(sym.Bid() <= 0 || sym.Ask() <= 0 || sym.Point() <= 0)
      {
         Log(LOG_WARNING, "ManageOpenPositions", "Invalid symbol prices for " + position_symbol);
         continue;
      }

      double spread_points = sym.Spread();
      double min_move_price = spread_points * sym.Point();
      double current_price = (position_type == POSITION_TYPE_BUY) ? sym.Bid() : sym.Ask();
      double current_rr = SafeDiv(MathAbs(current_price - position_open), 
                                  MathAbs(position_open - position_sl), 0.0);
      double current_profit = PositionGetDouble(POSITION_PROFIT);
      if(!MathIsValidNumber(current_profit))
         current_profit = 0.0;
      double peak_profit = UpdateAndGetPeakProfit(ticket, current_profit);
      int pos_direction = (position_type == POSITION_TYPE_BUY ? 1 : -1);
      double risk_ccy = 0.0;
      if(position_open > 0.0 && position_sl > 0.0 && position_volume > 0.0)
         risk_ccy = CalculateTradeRiskCurrency(position_symbol, pos_direction, position_volume, position_open, position_sl);
      double peak_profit_r = (risk_ccy > 0.0 ? (peak_profit / risk_ccy) : 0.0);
      double current_profit_r = (risk_ccy > 0.0 ? (current_profit / risk_ccy) : 0.0);

      ApplyPeakDrawdownSLProtection(ticket, position_symbol, position_type, position_volume,
                                    position_open, position_sl, position_tp, current_price,
                                    current_profit, peak_profit, (int)sym.Digits(), sym.Point(),
                                    spread_points, min_move_price);

      if(g_Peak_Profit_Drawdown_Pct > 0.0 && peak_profit > 0.0 && risk_ccy > 0.0)
      {
         double min_peak_r = (g_Peak_Profit_Min_R > 0.0 ? g_Peak_Profit_Min_R : 0.0);
         if(peak_profit_r >= min_peak_r)
         {
            double retain_ratio = 1.0 - (g_Peak_Profit_Drawdown_Pct / 100.0);
            if(retain_ratio < 0.0) retain_ratio = 0.0;
            double threshold_profit = peak_profit * retain_ratio;
            if(current_profit <= threshold_profit)
            {
               double dd_pct = (peak_profit > 0.0 ? (MathMax(0.0, peak_profit - current_profit) / peak_profit * 100.0) : 0.0);
               string dd_msg = StringFormat("%s - Peak profit drawdown %.1f%% (peak=%.2f/%.2fR, current=%.2f/%.2fR, threshold=%.2f). Closing position #%I64u",
                                            position_symbol, dd_pct, peak_profit, peak_profit_r,
                                            current_profit, current_profit_r, threshold_profit, ticket);
               bool close_request_ok = trade.PositionClose(ticket);
               int close_retcode = (int)trade.ResultRetcode();
               bool close_ok = (close_request_ok && IsSuccessfulTradeRetcode(close_retcode, false));
               if(close_ok)
               {
                  Log(LOG_WARNING, "ManageOpenPositions", dd_msg);
                  SendAlert(ALERT_TRADE_CLOSE, dd_msg);
                  AuditLog("PEAK_DD_CLOSE", position_symbol, dd_msg);
                  ClearPeakProfit(ticket);
                  
                   // Tier 3B metrics are recorded on deal close in TrackClosedTrades
                   // to avoid double-counting manual close events.
               }
               else
               {
                  Log(LOG_WARNING, "ManageOpenPositions", position_symbol +
                      " - Peak profit drawdown close failed (retcode=" + IntegerToString(close_retcode) +
                      ", " + trade.ResultRetcodeDescription() + ")");
               }
               continue;
            }
         }
      }

      // Move SL to breakeven once RR threshold is reached
      if(g_Breakeven_RR > 0 && current_rr >= g_Breakeven_RR)
      {
         double be_tolerance = sym.Point() * 2;
         double sltp_eps = sym.Point() * 2;
         double desired_sl = position_open;
         bool should_move_be = false;

         if(position_type == POSITION_TYPE_BUY)
         {
            if(position_sl == 0 || position_sl < desired_sl - be_tolerance)
               should_move_be = true;
         }
         else
         {
            if(position_sl == 0 || position_sl > desired_sl + be_tolerance)
               should_move_be = true;
         }

         if(should_move_be)
         {
            // Avoid micro-adjustments: require move greater than one spread
            if(MathAbs(desired_sl - position_sl) > min_move_price)
            {
               if(!IsForwardOnlySLTP(position_type, position_sl, position_tp, desired_sl, position_tp, sltp_eps))
               {
                  Log(LOG_WARNING, "ManageOpenPositions", position_symbol + " - SL/TP change blocked (non-forward move)");
               }
               else
               {
                  bool modify_request_ok = trade.PositionModify(ticket, desired_sl, position_tp);
                  int modify_retcode = (int)trade.ResultRetcode();
                  bool modify_ok = (modify_request_ok && IsSuccessfulTradeRetcode(modify_retcode, false));
                  if(modify_ok)
                  {
                     Log(LOG_INFO, "ManageOpenPositions", position_symbol + " - Moved SL to breakeven");
                     position_sl = desired_sl;
                  }
                  else
                  {
                     Log(LOG_WARNING, "ManageOpenPositions", position_symbol +
                         " - Breakeven SL update failed (retcode=" + IntegerToString(modify_retcode) +
                         ", " + trade.ResultRetcodeDescription() + ")");
                  }
               }
            }
         }
      }

      // Breakeven check: ensure SL has moved to (or beyond) entry before partials
      bool is_breakeven = false;
      if(position_sl > 0)
      {
         double be_tolerance = sym.Point() * 2;
         if(position_type == POSITION_TYPE_BUY)
            is_breakeven = (position_sl >= position_open - be_tolerance);
         else
            is_breakeven = (position_sl <= position_open + be_tolerance);
      }

      // Partial close - Using Min_RR_Ratio = 1.5 as reference for partial close RR
      bool allow_partial = !g_Require_BE_Before_Partial || is_breakeven;
      if(g_Enable_Partial_Close && current_rr >= g_Partial_Close_RR &&
         allow_partial && !HasPartialCloseBeenApplied(ticket))
      {
            double min_lot = sym.LotsMin();
            double lot_step = sym.LotsStep();
            if(position_volume > min_lot * 1.5)
         {
            double close_volume = position_volume * 0.5;
            close_volume = MathMax(close_volume, min_lot);
            if(lot_step > 0.0)
               close_volume = MathFloor(close_volume / lot_step) * lot_step;
            int lot_digits = 2;
            if(lot_step > 0.0)
            {
               lot_digits = (int)MathRound(-MathLog10(lot_step));
               if(lot_digits < 0) lot_digits = 0;
               if(lot_digits > 8) lot_digits = 8;
            }
            close_volume = NormalizeDouble(close_volume, lot_digits);
            if(close_volume < min_lot || close_volume >= position_volume)
               close_volume = 0.0;
             
            if(close_volume > 0.0)
            {
               bool partial_request_ok = trade.PositionClosePartial(ticket, close_volume);
               int partial_retcode = (int)trade.ResultRetcode();
               bool partial_ok = (partial_request_ok && IsSuccessfulTradeRetcode(partial_retcode, false));
               if(partial_ok)
               {
                  MarkPartialCloseApplied(ticket);
                  string msg = StringFormat("%s - Partial close: %.2f lots at RR: %.2f",
                     position_symbol, close_volume, current_rr);
                  Log(LOG_INFO, "ManageOpenPositions", msg);
                  SendAlert(ALERT_TRADE_CLOSE, msg);
               }
               else
               {
                  Log(LOG_WARNING, "ManageOpenPositions", position_symbol +
                      " - Partial close failed (retcode=" + IntegerToString(partial_retcode) +
                      ", " + trade.ResultRetcodeDescription() + ")");
               }
            }
         }
      }
      // Trailing stop
         if(g_Enable_Trailing_Stop)
         {
            // Use primary timeframe ATR for smoother trailing on higher‑TF trades
            double current_atr = GetATRValue(position_symbol, Primary_TF);
            if(current_atr > 0)
            {
               double trail_distance = current_atr * ATR_SL_Multiplier;
               
               // CAP TRAILING DISTANCE: Prevent SL from drifting too far from entry
               // This limits risk accumulation when positions are held long
               double initial_sl_distance = MathAbs(position_open - position_sl);
               if(initial_sl_distance > 0.0)
               {
                  // Maximum allowed SL distance = 1.5x initial SL or ATR distance, whichever is larger
                  double max_trailing_distance = MathMax(initial_sl_distance * 1.5, current_atr);
                  if(trail_distance > max_trailing_distance)
                  {
                     trail_distance = max_trailing_distance;
                  }
               }
               
            double new_stop_loss = 0.0;
            double sltp_eps = sym.Point() * 2;

            if(position_type == POSITION_TYPE_BUY)
            {
               new_stop_loss = current_price - trail_distance;
               new_stop_loss = NormalizeDouble(new_stop_loss, (int)sym.Digits());
               if(new_stop_loss > position_sl && 
                  new_stop_loss < current_price - sym.Spread() * sym.Point())
               {
                  if(MathAbs(new_stop_loss - position_sl) > min_move_price)
                  {
                     if(!IsForwardOnlySLTP(position_type, position_sl, position_tp, new_stop_loss, position_tp, sltp_eps))
                     {
                        Log(LOG_WARNING, "ManageOpenPositions", position_symbol + " - SL/TP change blocked (non-forward move)");
                     }
                     else
                     {
                        bool modify_request_ok = trade.PositionModify(ticket, new_stop_loss, position_tp);
                        int modify_retcode = (int)trade.ResultRetcode();
                        bool modify_ok = (modify_request_ok && IsSuccessfulTradeRetcode(modify_retcode, false));
                        if(modify_ok)
                        {
                           Log(LOG_INFO, "ManageOpenPositions", position_symbol + " - BUY Trail SL to: " + DoubleToString(new_stop_loss, 2));
                        }
                        else
                        {
                           Log(LOG_WARNING, "ManageOpenPositions", position_symbol +
                               " - BUY trail SL update failed (retcode=" + IntegerToString(modify_retcode) +
                               ", " + trade.ResultRetcodeDescription() + ")");
                        }
                     }
                  }
               }
            }
            else
            {
               new_stop_loss = current_price + trail_distance;
               new_stop_loss = NormalizeDouble(new_stop_loss, (int)sym.Digits());
               if((position_sl == 0 || new_stop_loss < position_sl) && 
                  new_stop_loss > current_price + sym.Spread() * sym.Point())
               {
                  if(MathAbs(new_stop_loss - position_sl) > min_move_price)
                  {
                     if(!IsForwardOnlySLTP(position_type, position_sl, position_tp, new_stop_loss, position_tp, sltp_eps))
                     {
                        Log(LOG_WARNING, "ManageOpenPositions", position_symbol + " - SL/TP change blocked (non-forward move)");
                     }
                     else
                     {
                        bool modify_request_ok = trade.PositionModify(ticket, new_stop_loss, position_tp);
                        int modify_retcode = (int)trade.ResultRetcode();
                        bool modify_ok = (modify_request_ok && IsSuccessfulTradeRetcode(modify_retcode, false));
                        if(modify_ok)
                        {
                           Log(LOG_INFO, "ManageOpenPositions", position_symbol + " - SELL Trail SL to: " + DoubleToString(new_stop_loss, 2));
                        }
                        else
                        {
                           Log(LOG_WARNING, "ManageOpenPositions", position_symbol +
                               " - SELL trail SL update failed (retcode=" + IntegerToString(modify_retcode) +
                               ", " + trade.ResultRetcodeDescription() + ")");
                        }
                     }
                  }
               }
            }
         }
      }
   }
   
   // Issue 2.1 FIX: FIRST reset position counts
   for(int i = 0; i < g_symbols_count; i++)
   {
      g_symbols[i].positions_count = 0;
      g_symbols[i].last_position_open = 0;
   }
   
   // SECOND: Recount positions in single pass (positions already managed above)
   total_positions = PositionsTotal();
   for(int i = total_positions - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
      {
         // Position closed - re-snapshot total
         total_positions = PositionsTotal();
         if(i >= total_positions)
            continue;  // Skip if position closed
         
         // Retry this position
         ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
      }
      
      if(!PositionSelectByTicket(ticket))
         continue;
      
      string position_symbol = PositionGetString(POSITION_SYMBOL);
      long position_magic = PositionGetInteger(POSITION_MAGIC);
      
      if(position_magic >= Magic_Base && position_magic < Magic_Base + 10000)
      {
         int symbol_index = GetSymbolIndex(position_symbol);
         if(symbol_index >= 0)
         {
            g_symbols[symbol_index].positions_count++;
            datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
            if(open_time > g_symbols[symbol_index].last_position_open)
               g_symbols[symbol_index].last_position_open = open_time;
            if(g_symbols[symbol_index].last_position_open > g_symbols[symbol_index].last_signal_time)
               g_symbols[symbol_index].last_signal_time = g_symbols[symbol_index].last_position_open;
         }
      }
   }
}



int GetUniqueMagicNumber(string symbol, int direction)
{
   int base_offset = GetSymbolHashFunc(symbol) % 10000;
   
   // Generate a unique component within [0..9999] so it stays in Magic_Base range
   int time_component = (int)(TimeCurrent() % 10000);
   int unique_component = (base_offset * 17 + direction * 13 + time_component) % 10000;
   if(unique_component < 0) unique_component += 10000;
   
   int unique_magic = (int)(Magic_Base + unique_component);
   
   Log(LOG_DEBUG, "GetUniqueMagicNumber", symbol + " - Magic: " + IntegerToString(unique_magic));
       
   return unique_magic;
}

void CleanupExpiredPendingOrders()
{
   static datetime last_cleanup = 0;
   static datetime last_market_closed_skip_log = 0;
   static datetime last_grace_skip_log = 0;
   datetime current_time = TimeCurrent();
   
   // Run at most once per second so trend-mismatched pendings are removed quickly.
   if(current_time - last_cleanup < 1) return;
   last_cleanup = current_time;
   
   int total_orders = OrdersTotal();
   if(total_orders == 0) return;
   
   int cleaned_count = 0;
   
   for(int i = total_orders - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      
      long order_magic = OrderGetInteger(ORDER_MAGIC);
      if(order_magic < Magic_Base || order_magic >= Magic_Base + 10000) continue; // Not our order
      
      datetime order_time = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      datetime order_expiration = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
      string order_symbol = OrderGetString(ORDER_SYMBOL);
      long order_type = OrderGetInteger(ORDER_TYPE);
      string order_comment = OrderGetString(ORDER_COMMENT);
      int order_direction = PendingOrderDirectionFromType(order_type);
      bool allow_countertrend_pending = CommentHasCountertrendExecutionTag(order_comment);
      datetime effective_expiration = order_expiration;
      if(effective_expiration <= 0 && order_time > 0)
         effective_expiration = order_time + 14400; // Align fallback with the default 4h pending expiry used at placement.
      int order_age_seconds = g_Pending_Trend_Grace_Seconds;
      if(order_time > 0)
         order_age_seconds = (int)MathMax(0, current_time - order_time);

      bool expired = (effective_expiration > 0 && current_time >= effective_expiration);
      bool trend_mismatch = false;
      bool neutral_trend_mismatch = false;
      string trend_reason = "";
      int trend_direction_now = 0;
      if(order_direction != 0)
      {
         trend_direction_now = GetHTFBiasInstitutional(order_symbol);
         if(trend_direction_now == 0)
         {
            trend_mismatch = true;
            neutral_trend_mismatch = true;
            trend_reason = "Calculated trend neutral";
         }
         else if(trend_direction_now != order_direction && !allow_countertrend_pending)
         {
            trend_mismatch = true;
            trend_reason = "CalcTrend=" + (trend_direction_now == 1 ? "BUY" : "SELL") +
                           " vs Pending=" + (order_direction == 1 ? "BUY" : "SELL");
         }
      }

      bool defer_neutral_trend_cleanup =
         (neutral_trend_mismatch &&
          g_Pending_Trend_Grace_Seconds > 0 &&
          order_age_seconds < g_Pending_Trend_Grace_Seconds);
      if(defer_neutral_trend_cleanup)
      {
         if(last_grace_skip_log == 0 || (current_time - last_grace_skip_log) >= 60)
         {
            Log(LOG_DEBUG, "CleanupExpiredPendingOrders",
                "Holding pending order #" + IntegerToString(ticket) +
                " for " + order_symbol + " during neutral-trend grace (" +
                IntegerToString(order_age_seconds) + "s/" +
                IntegerToString(g_Pending_Trend_Grace_Seconds) + "s)");
            last_grace_skip_log = current_time;
         }
         continue;
      }

      // Remove orders that are stale by age or no longer trend-aligned.
      if(expired || trend_mismatch)
      {
         if(!IsMarketOpen(order_symbol))
         {
            if(last_market_closed_skip_log == 0 || (current_time - last_market_closed_skip_log) >= 300)
            {
               Log(LOG_INFO, "CleanupExpiredPendingOrders",
                   "Deferring pending-order cleanup while market is closed for " + order_symbol);
               last_market_closed_skip_log = current_time;
            }
            continue;
         }

         bool delete_request_ok = trade.OrderDelete(ticket);
         int delete_retcode = (int)trade.ResultRetcode();
         bool delete_ok = (delete_request_ok && IsSuccessfulTradeRetcode(delete_retcode, false));
         if(delete_ok)
         {
            cleaned_count++;
            if(trend_mismatch)
            {
               Log(LOG_INFO, "CleanupExpiredPendingOrders",
                   "Removed pending order #" + IntegerToString(ticket) +
                   " for " + order_symbol + " due to trend mismatch (" + trend_reason +
                   ", age=" + IntegerToString(order_age_seconds) + "s)");
            }
            else
            {
               Log(LOG_INFO, "CleanupExpiredPendingOrders",
                    "Removed expired pending order #" + IntegerToString(ticket) +
                    " for " + order_symbol + " (age: " +
                    IntegerToString((current_time - order_time) / 60) + " minutes" +
                    (effective_expiration > 0 ? ", expiry=" + TimeToString(effective_expiration) : "") + ")");
            }
         }
         else
         {
            Log(LOG_WARNING, "CleanupExpiredPendingOrders",
                "Failed to remove pending order #" + IntegerToString(ticket) +
                " for " + order_symbol + " (retcode=" + IntegerToString(delete_retcode) +
                ", " + trade.ResultRetcodeDescription() + ")");
         }
       }
    }
   
   if(cleaned_count > 0)
   {
      Log(LOG_INFO, "CleanupExpiredPendingOrders", 
          "Cleaned up " + IntegerToString(cleaned_count) + " pending orders");
   }
}

#endif // TRADE_MANAGEMENT_MQH
