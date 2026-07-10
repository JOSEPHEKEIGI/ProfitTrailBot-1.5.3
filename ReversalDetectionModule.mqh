//+------------------------------------------------------------------+
//|                                        ReversalDetectionModule.mqh |
//|                        Copyright 2024, ProfitTrailBot Ltd.        |
//|                                   Reversal Detection Enhancement   |
//+------------------------------------------------------------------+

#ifndef REVERSAL_DETECTION_MODULE_MQH
#define REVERSAL_DETECTION_MODULE_MQH

// Cache size constant for reversal detector
#define REVERSAL_MAX_CACHE_SYMBOLS 50

// Safe division function declaration
double SafeDiv(double numerator, double denominator, double fallback = 0.0);
int GetPooledIndicatorHandle(string symbol, ENUM_TIMEFRAMES tf, int period, string type);
void DebugReversalLog(const string msg)
{
   if((bool)MQLInfoInteger(MQL_DEBUG))
      Print(msg);
}

//====================================================================
// REVERSAL DETECTION STRUCTURES
//====================================================================
struct SReversalSignal
{
   bool valid;
   int direction;           // 1 for bullish reversal, -1 for bearish reversal
   double confidence;       // 0.0 to 1.0
   double entry_price;
   double stop_loss;
   double take_profit;
   string reason;
   datetime signal_time;
   
   // Reversal-specific data
   bool divergence_detected;
   bool exhaustion_detected;
   bool structure_break;
   double momentum_shift;
   
   // Trend alignment data
   int trend_direction;     // 1 for uptrend, -1 for downtrend, 0 for neutral
   bool aligns_with_trend;  // True if reversal aligns with higher timeframe trend
   double trend_alignment_bonus; // Confidence bonus from trend alignment
   
   SReversalSignal() : valid(false), direction(0), confidence(0.0), 
                      entry_price(0.0), stop_loss(0.0), take_profit(0.0),
                      reason(""), signal_time(0), divergence_detected(false),
                      exhaustion_detected(false), structure_break(false),
                      momentum_shift(0.0), trend_direction(0), aligns_with_trend(false),
                      trend_alignment_bonus(0.0) {}
};

struct SMomentumData
{
   double rsi_current;
   double rsi_previous;
   double macd_current;
   double macd_signal;
   double macd_histogram;
   double stoch_main;
   double stoch_signal;
   double price_momentum;
   
   SMomentumData() : rsi_current(50.0), rsi_previous(50.0), macd_current(0.0),
                    macd_signal(0.0), macd_histogram(0.0), stoch_main(50.0),
                    stoch_signal(50.0), price_momentum(0.0) {}
};

//====================================================================
// REVERSAL DETECTION CLASS
//====================================================================
class CReversalDetector
{
private:
   // Cache for momentum indicators (fixed size with bounds checking)
   SMomentumData m_momentum_cache[REVERSAL_MAX_CACHE_SYMBOLS];
   datetime m_last_update[REVERSAL_MAX_CACHE_SYMBOLS];
   string m_momentum_cache_symbol[REVERSAL_MAX_CACHE_SYMBOLS];
   ENUM_TIMEFRAMES m_momentum_cache_tf[REVERSAL_MAX_CACHE_SYMBOLS];

   // Per-bar reversal cache to avoid recomputation on every tick.
   SReversalSignal m_signal_cache[REVERSAL_MAX_CACHE_SYMBOLS];
   datetime m_signal_cache_bar_time[REVERSAL_MAX_CACHE_SYMBOLS];
   string m_signal_cache_symbol[REVERSAL_MAX_CACHE_SYMBOLS];
   ENUM_TIMEFRAMES m_signal_cache_tf[REVERSAL_MAX_CACHE_SYMBOLS];
   bool m_signal_cache_trend_aware[REVERSAL_MAX_CACHE_SYMBOLS];
   int m_signal_cache_htf_trend[REVERSAL_MAX_CACHE_SYMBOLS];
   bool m_signal_cache_ready[REVERSAL_MAX_CACHE_SYMBOLS];
   
   // Reversal detection parameters
   double m_divergence_threshold;
   double m_exhaustion_rsi_level;
   double m_momentum_shift_threshold;
   int m_lookback_bars;

   void ApplyRuntimeSettings()
   {
      m_lookback_bars = (int)MathMax(10, MathMin(300, Reversal_Lookback_Bars));
      m_divergence_threshold = MathMax(0.10, MathMin(1.50, Reversal_Divergence_Threshold));
      m_exhaustion_rsi_level = MathMax(55.0, MathMin(95.0, Reversal_Exhaustion_RSI_Level));
      m_momentum_shift_threshold = MathMax(0.05, MathMin(2.0, Reversal_Momentum_Shift_Threshold));
   }
   
public:
   CReversalDetector()
   {
      m_divergence_threshold = 0.7;
      m_exhaustion_rsi_level = 75.0;
      m_momentum_shift_threshold = 0.3;
      m_lookback_bars = 20; // Default value, can be overridden
      
      // Initialize cache
      for(int i = 0; i < REVERSAL_MAX_CACHE_SYMBOLS; i++)
      {
         m_last_update[i] = 0;
         m_momentum_cache_symbol[i] = "";
         m_momentum_cache_tf[i] = (ENUM_TIMEFRAMES)-1;
         m_signal_cache_bar_time[i] = 0;
         m_signal_cache_symbol[i] = "";
         m_signal_cache_tf[i] = (ENUM_TIMEFRAMES)-1;
         m_signal_cache_trend_aware[i] = false;
         m_signal_cache_htf_trend[i] = 0;
         m_signal_cache_ready[i] = false;
      }
   }
   
   // Get safe cache index with bounds checking
   int GetSymbolCacheIndex(string symbol);
   
   // Main reversal detection function (without trend)
   SReversalSignal DetectReversal(string symbol, ENUM_TIMEFRAMES tf);
   
   // Trend-aware reversal detection function
   SReversalSignal DetectReversal(string symbol, ENUM_TIMEFRAMES tf, int htf_trend_direction);
   
   // Individual detection methods
   bool DetectMomentumDivergence(string symbol, ENUM_TIMEFRAMES tf, int direction);
   bool DetectExhaustionPattern(string symbol, ENUM_TIMEFRAMES tf, int direction);
   bool DetectStructureBreak(string symbol, ENUM_TIMEFRAMES tf, int direction);
   double CalculateMomentumShift(string symbol, ENUM_TIMEFRAMES tf);
   
   // Trend-aware methods
   double CalculateReversalConfidence(bool divergence, bool exhaustion, bool structure_break, double momentum_shift, int htf_trend = 0);
   bool IsReversalAlignedWithTrend(int reversal_direction, int htf_trend_direction);
   
   // Support methods
   SMomentumData GetMomentumData(string symbol, ENUM_TIMEFRAMES tf);
   void UpdateMomentumCache(string symbol, ENUM_TIMEFRAMES tf, datetime bar_time, const SMomentumData &data);
};

//====================================================================
// MOMENTUM DIVERGENCE DETECTION - FIXED BOUNDS VALIDATION
//====================================================================
bool CReversalDetector::DetectMomentumDivergence(string symbol, ENUM_TIMEFRAMES tf, int direction)
{
   // CRITICAL FIX: Validate parameters first
   if(StringLen(symbol) == 0 || tf <= 0 || (direction != 1 && direction != -1))
   {
      Print("[ERROR] DetectMomentumDivergence: Invalid parameters");
      return false;
   }
   
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int bars_needed = MathMax(m_lookback_bars, 10);
   
   // CRITICAL FIX: Safe CopyRates with error checking
   int copied = CopyRates(symbol, tf, 0, bars_needed, rates);
   if(copied < bars_needed)
   {
      Print("[ERROR] DetectMomentumDivergence: CopyRates failed for " + symbol + 
            " - copied " + IntegerToString(copied) + ", needed " + IntegerToString(bars_needed));
      return false;
   }
   
   int array_size = ArraySize(rates);
   if(array_size < 10) 
   {
      Print("[ERROR] DetectMomentumDivergence: Insufficient array size: " + IntegerToString(array_size));
      return false;
   }

   // Get RSI values for divergence analysis
   int rsi_handle = GetPooledIndicatorHandle(symbol, tf, 14, "RSI");
   if(rsi_handle == INVALID_HANDLE)
   {
      Print("[ERROR] DetectMomentumDivergence: Failed to create RSI handle for " + symbol);
      return false;
   }

   double rsi_values[];
   int rsi_copied = CopyBuffer(rsi_handle, 0, 0, bars_needed, rsi_values);
   if(rsi_copied < bars_needed)
   {
      Print("[ERROR] DetectMomentumDivergence: CopyBuffer failed for RSI - copied " + 
            IntegerToString(rsi_copied) + ", needed " + IntegerToString(bars_needed));
      return false;
   }
   
   // Safe cache index access with bounds checking
   int cache_idx = GetSymbolCacheIndex(symbol);
   if(cache_idx < 0 || cache_idx >= REVERSAL_MAX_CACHE_SYMBOLS)
   {
      Print("[ERROR] DetectMomentumDivergence: Invalid cache index: " + IntegerToString(cache_idx));
      return false;
   }

   // Find recent swing highs/lows in price and RSI
   bool divergence_found = false;
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = 0.0001;
   double min_price_gap = MathMax(point * 8.0, point * (double)m_lookback_bars * 0.35);
   double min_rsi_gap = MathMax(1.5, m_divergence_threshold * 10.0);

   if(direction == -1) // Looking for bearish reversal (bullish divergence)
   {
      // Find two recent swing lows with proper bounds checking
      int swing_low1 = -1, swing_low2 = -1;
      double lowest_price1 = DBL_MAX, lowest_price2 = DBL_MAX;

      // Find first swing low (most recent) - FIXED bounds
      for(int i = 2; i < MathMin(array_size - 2, bars_needed - 2); i++)
      {
         // CRITICAL FIX: Comprehensive bounds checking
         if(i-2 >= 0 && i+2 < array_size && i < array_size && 
            i-1 >= 0 && i+1 < array_size)
         {
            if(rates[i].low < rates[i-1].low && rates[i].low < rates[i-2].low &&
               rates[i].low < rates[i+1].low && rates[i].low < rates[i+2].low)
            {
               if(rates[i].low < lowest_price1)
               {
                  lowest_price1 = rates[i].low;
                  swing_low1 = i;
               }
            }
         }
      }

      // Find second swing low (older) - FIXED bounds
      if(swing_low1 != -1)
      {
         for(int i = swing_low1 + 5; i < MathMin(array_size - 2, bars_needed - 2); i++)
         {
            // CRITICAL FIX: Comprehensive bounds checking
            if(i-2 >= 0 && i+2 < array_size && i < array_size && 
               i-1 >= 0 && i+1 < array_size)
            {
               if(rates[i].low < rates[i-1].low && rates[i].low < rates[i-2].low &&
                  rates[i].low < rates[i+1].low && rates[i].low < rates[i+2].low)
               {
                  if(rates[i].low < lowest_price2)
                  {
                     lowest_price2 = rates[i].low;
                     swing_low2 = i;
                  }
               }
            }
         }
      }

      // Check for bullish divergence (price makes lower low, RSI makes higher low)
      if(swing_low1 != -1 && swing_low2 != -1 && 
         swing_low1 < ArraySize(rsi_values) && swing_low2 < ArraySize(rsi_values) &&
         swing_low1 >= 0 && swing_low2 >= 0)
      {
         double price_gap = MathAbs(rates[swing_low2].low - rates[swing_low1].low);
         double rsi_gap = MathAbs(rsi_values[swing_low1] - rsi_values[swing_low2]);
         if(rates[swing_low1].low < rates[swing_low2].low && // Price lower low
            rsi_values[swing_low1] > rsi_values[swing_low2] && // RSI higher low
            price_gap >= min_price_gap &&
            rsi_gap >= min_rsi_gap)
         {
            divergence_found = true;
            DebugReversalLog("[DEBUG] DetectMomentumDivergence: Bullish divergence found at bars " + 
                  IntegerToString(swing_low1) + " and " + IntegerToString(swing_low2));
         }
      }
   }
   else if(direction == 1) // Looking for bullish reversal (bearish divergence)
   {
      // Find two recent swing highs with proper bounds checking
      int swing_high1 = -1, swing_high2 = -1;
      double highest_price1 = 0, highest_price2 = 0;

      // Find first swing high (most recent) - FIXED bounds
      for(int i = 2; i < MathMin(array_size - 2, bars_needed - 2); i++)
      {
         // CRITICAL FIX: Comprehensive bounds checking
         if(i-2 >= 0 && i+2 < array_size && i < array_size && 
            i-1 >= 0 && i+1 < array_size)
         {
            if(rates[i].high > rates[i-1].high && rates[i].high > rates[i-2].high &&
               rates[i].high > rates[i+1].high && rates[i].high > rates[i+2].high)
            {
               if(rates[i].high > highest_price1)
               {
                  highest_price1 = rates[i].high;
                  swing_high1 = i;
               }
            }
         }
      }

      // Find second swing high (older) - FIXED bounds
      if(swing_high1 != -1)
      {
         for(int i = swing_high1 + 5; i < MathMin(array_size - 2, bars_needed - 2); i++)
         {
            // CRITICAL FIX: Comprehensive bounds checking
            if(i-2 >= 0 && i+2 < array_size && i < array_size && 
               i-1 >= 0 && i+1 < array_size)
            {
               if(rates[i].high > rates[i-1].high && rates[i].high > rates[i-2].high &&
                  rates[i].high > rates[i+1].high && rates[i].high > rates[i+2].high)
               {
                  if(rates[i].high > highest_price2)
                  {
                     highest_price2 = rates[i].high;
                     swing_high2 = i;
                  }
               }
            }
         }
      }

      // Check for bearish divergence (price makes higher high, RSI makes lower high)
      if(swing_high1 != -1 && swing_high2 != -1 &&
         swing_high1 < ArraySize(rsi_values) && swing_high2 < ArraySize(rsi_values) &&
         swing_high1 >= 0 && swing_high2 >= 0)
      {
         double price_gap = MathAbs(rates[swing_high1].high - rates[swing_high2].high);
         double rsi_gap = MathAbs(rsi_values[swing_high1] - rsi_values[swing_high2]);
         if(rates[swing_high1].high > rates[swing_high2].high && // Price higher high
            rsi_values[swing_high1] < rsi_values[swing_high2] &&  // RSI lower high
            price_gap >= min_price_gap &&
            rsi_gap >= min_rsi_gap)
         {
            divergence_found = true;
            DebugReversalLog("[DEBUG] DetectMomentumDivergence: Bearish divergence found at bars " + 
                  IntegerToString(swing_high1) + " and " + IntegerToString(swing_high2));
         }
      }
   }

   return divergence_found;
}

//====================================================================
// EXHAUSTION PATTERN DETECTION - FIXED BOUNDS AND VALIDATION
//====================================================================
bool CReversalDetector::DetectExhaustionPattern(string symbol, ENUM_TIMEFRAMES tf, int direction)
{
   // CRITICAL FIX: Validate parameters first
   if(StringLen(symbol) == 0 || tf <= 0 || (direction != 1 && direction != -1))
   {
      Print("[ERROR] DetectExhaustionPattern: Invalid parameters");
      return false;
   }
   
   SMomentumData momentum = GetMomentumData(symbol, tf);
   
   // CRITICAL FIX: Validate momentum data
   if(!MathIsValidNumber(momentum.rsi_current) || !MathIsValidNumber(momentum.stoch_main))
   {
      Print("[ERROR] DetectExhaustionPattern: Invalid momentum data");
      return false;
   }
   
   bool exhaustion_detected = false;
   
   if(direction == -1) // Looking for bearish reversal
   {
      // Check for overbought conditions
      if(momentum.rsi_current > m_exhaustion_rsi_level && // RSI overbought
         momentum.stoch_main > 80.0 &&                    // Stochastic overbought
         momentum.macd_histogram < momentum.macd_current) // MACD histogram declining
      {
         exhaustion_detected = true;
         DebugReversalLog("[DEBUG] DetectExhaustionPattern: Bearish exhaustion detected - RSI: " + 
               DoubleToString(momentum.rsi_current, 1) + ", Stoch: " + DoubleToString(momentum.stoch_main, 1));
      }
   }
   else if(direction == 1) // Looking for bullish reversal
   {
      // Check for oversold conditions
      if(momentum.rsi_current < (100.0 - m_exhaustion_rsi_level) && // RSI oversold
         momentum.stoch_main < 20.0 &&                              // Stochastic oversold
         momentum.macd_histogram > momentum.macd_current)           // MACD histogram rising
      {
         exhaustion_detected = true;
         DebugReversalLog("[DEBUG] DetectExhaustionPattern: Bullish exhaustion detected - RSI: " + 
               DoubleToString(momentum.rsi_current, 1) + ", Stoch: " + DoubleToString(momentum.stoch_main, 1));
      }
   }
   
   return exhaustion_detected;
}

//====================================================================
// STRUCTURE BREAK DETECTION FOR REVERSALS - FIXED BOUNDS
//====================================================================
bool CReversalDetector::DetectStructureBreak(string symbol, ENUM_TIMEFRAMES tf, int direction)
{
   // CRITICAL FIX: Validate parameters first
   if(StringLen(symbol) == 0 || tf <= 0 || (direction != 1 && direction != -1))
   {
      Print("[ERROR] DetectStructureBreak: Invalid parameters");
      return false;
   }
   
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int bars_needed = 10;
   
   // CRITICAL FIX: Safe CopyRates with error checking
   int copied = CopyRates(symbol, tf, 0, bars_needed, rates);
   if(copied < bars_needed)
   {
      Print("[ERROR] DetectStructureBreak: CopyRates failed for " + symbol + 
            " - copied " + IntegerToString(copied) + ", needed " + IntegerToString(bars_needed));
      return false;
   }

   int array_size = ArraySize(rates);
   if(array_size < 6) 
   {
      Print("[ERROR] DetectStructureBreak: Insufficient array size: " + IntegerToString(array_size));
      return false;
   }

   bool structure_break = false;

   if(direction == -1) // Looking for bearish reversal
   {
      // Check if price broke below recent support
      double recent_low = rates[1].low;
      for(int i = 2; i < MathMin(6, array_size); i++)
      {
         // CRITICAL FIX: Bounds checking
         if(i >= 0 && i < array_size)
         {
            recent_low = MathMin(recent_low, rates[i].low);
         }
      }

      if(rates[0].close < recent_low)
      {
         structure_break = true;
         DebugReversalLog("[DEBUG] DetectStructureBreak: Bearish structure break detected - price: " + 
               DoubleToString(rates[0].close, 5) + ", support: " + DoubleToString(recent_low, 5));
      }
   }
   else if(direction == 1) // Looking for bullish reversal
   {
      // Check if price broke above recent resistance
      double recent_high = rates[1].high;
      for(int i = 2; i < MathMin(6, array_size); i++)
      {
         // CRITICAL FIX: Bounds checking
         if(i >= 0 && i < array_size)
         {
            recent_high = MathMax(recent_high, rates[i].high);
         }
      }

      if(rates[0].close > recent_high)
      {
         structure_break = true;
         DebugReversalLog("[DEBUG] DetectStructureBreak: Bullish structure break detected - price: " + 
               DoubleToString(rates[0].close, 5) + ", resistance: " + DoubleToString(recent_high, 5));
      }
   }

   return structure_break;
}

bool DetectStructureBreak(string symbol, ENUM_TIMEFRAMES tf, int direction)
{
   static CReversalDetector structure_detector;
   return structure_detector.DetectStructureBreak(symbol, tf, direction);
}

//====================================================================
// MOMENTUM SHIFT CALCULATION - FIXED DIVISION BY ZERO
//====================================================================
double CReversalDetector::CalculateMomentumShift(string symbol, ENUM_TIMEFRAMES tf)
{
   // CRITICAL FIX: Validate parameters first
   if(StringLen(symbol) == 0 || tf <= 0)
   {
      Print("[ERROR] CalculateMomentumShift: Invalid parameters");
      return 0.0;
   }
   
   SMomentumData momentum = GetMomentumData(symbol, tf);
   
   // CRITICAL FIX: Validate momentum data
   if(!MathIsValidNumber(momentum.rsi_current) || !MathIsValidNumber(momentum.rsi_previous))
   {
      Print("[ERROR] CalculateMomentumShift: Invalid momentum data");
      return 0.0;
   }
   
   // Calculate momentum shift based on multiple indicators
   double rsi_shift = SafeDiv(momentum.rsi_current - momentum.rsi_previous, 100.0, 0.0);
   
   // CRITICAL FIX: Safe division for MACD
   double macd_shift = 0.0;
   double macd_denominator = MathAbs(momentum.macd_current) + 0.0001;
   if(macd_denominator > 0)
   {
      macd_shift = SafeDiv(momentum.macd_histogram, macd_denominator, 0.0);
   }
   
   double stoch_shift = SafeDiv(momentum.stoch_main - momentum.stoch_signal, 100.0, 0.0);
   
   // Weighted average of momentum shifts
   double momentum_shift = (rsi_shift * 0.4 + macd_shift * 0.4 + stoch_shift * 0.2);
   
   // CRITICAL FIX: Validate result
   if(!MathIsValidNumber(momentum_shift))
   {
      Print("[ERROR] CalculateMomentumShift: Invalid momentum shift calculation");
      return 0.0;
   }
   
   return momentum_shift;
}

//====================================================================
// GET MOMENTUM DATA - FIXED MEMORY LEAKS AND BOUNDS
//====================================================================
SMomentumData CReversalDetector::GetMomentumData(string symbol, ENUM_TIMEFRAMES tf)
{
   SMomentumData momentum;
   
   // CRITICAL FIX: Validate parameters first
   if(StringLen(symbol) == 0 || tf <= 0)
   {
      Print("[ERROR] GetMomentumData: Invalid parameters");
      return momentum;
   }

   int index = GetSymbolCacheIndex(symbol);
   datetime bar_time = iTime(symbol, tf, 0);
   if(index >= 0 && index < REVERSAL_MAX_CACHE_SYMBOLS &&
      bar_time > 0 &&
      m_last_update[index] == bar_time &&
      m_momentum_cache_symbol[index] == symbol &&
      m_momentum_cache_tf[index] == tf)
   {
      return m_momentum_cache[index];
   }
   
   // RSI
   int rsi_handle = GetPooledIndicatorHandle(symbol, tf, 14, "RSI");
   if(rsi_handle != INVALID_HANDLE)
   {
      double rsi_buffer[2];
      int rsi_copied = CopyBuffer(rsi_handle, 0, 0, 2, rsi_buffer);
      if(rsi_copied == 2)
      {
         momentum.rsi_current = rsi_buffer[0];
         momentum.rsi_previous = rsi_buffer[1];
      }
   }
   
   // MACD
   int macd_handle = GetPooledIndicatorHandle(symbol, tf, 12, "MACD");
   if(macd_handle != INVALID_HANDLE)
   {
      double macd_main[1], macd_signal[1];
      int macd_main_copied = CopyBuffer(macd_handle, 0, 0, 1, macd_main);
      int macd_signal_copied = CopyBuffer(macd_handle, 1, 0, 1, macd_signal);
      
      if(macd_main_copied == 1 && macd_signal_copied == 1)
      {
         momentum.macd_current = macd_main[0];
         momentum.macd_signal = macd_signal[0];
         momentum.macd_histogram = macd_main[0] - macd_signal[0];
      }
   }
   
   // Stochastic
   int stoch_handle = GetPooledIndicatorHandle(symbol, tf, 14, "STOCH");
   if(stoch_handle != INVALID_HANDLE)
   {
      double stoch_main[1], stoch_signal[1];
      int stoch_main_copied = CopyBuffer(stoch_handle, 0, 0, 1, stoch_main);
      int stoch_signal_copied = CopyBuffer(stoch_handle, 1, 0, 1, stoch_signal);
      
      if(stoch_main_copied == 1 && stoch_signal_copied == 1)
      {
         momentum.stoch_main = stoch_main[0];
         momentum.stoch_signal = stoch_signal[0];
      }
   }
   
   // Price momentum
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int rates_copied = CopyRates(symbol, tf, 0, 5, rates);
   if(rates_copied == 5)
   {
      // CRITICAL FIX: Safe division with validation
      if(rates[4].close != 0 && MathIsValidNumber(rates[4].close))
      {
         momentum.price_momentum = SafeDiv(rates[0].close - rates[4].close, rates[4].close, 0.0);
      }
   }

   UpdateMomentumCache(symbol, tf, bar_time, momentum);
   
   return momentum;
}

//====================================================================
// CALCULATE REVERSAL CONFIDENCE - FIXED BOUNDS AND VALIDATION
//====================================================================
double CReversalDetector::CalculateReversalConfidence(bool divergence, bool exhaustion, 
                                                     bool structure_break, double momentum_shift, int htf_trend)
{
   // CRITICAL FIX: Validate momentum_shift
   if(!MathIsValidNumber(momentum_shift))
   {
      Print("[ERROR] CalculateReversalConfidence: Invalid momentum_shift");
      momentum_shift = 0.0;
   }
   
   double confidence = 0.0;
   
   // Base confidence from individual signals
   if(divergence) confidence += 0.4;
   if(exhaustion) confidence += 0.3;
   if(structure_break) confidence += 0.2;
   
   // Momentum shift contribution normalized by user threshold.
   double threshold = MathMax(m_momentum_shift_threshold, 0.05);
   double momentum_abs = MathAbs(momentum_shift);
   double momentum_score = MathMin(1.0, SafeDiv(momentum_abs, threshold, 0.0));
   confidence += momentum_score * 0.1;
   if(momentum_abs < threshold * 0.5)
      confidence *= 0.92;
   
   // Trend alignment bonus: If reversal aligns with HTF trend (pullback/retracement)
   // Reduce confidence if reversal opposes HTF trend (trend reversal trade)
   if(htf_trend != 0)
   {
      // We'll calculate alignment based on signal direction in the calling function
      // For now, just note that trend info is available
   }
   
   // CRITICAL FIX: Ensure confidence is between 0 and 1 with validation
   confidence = MathMin(confidence, 1.0);
   confidence = MathMax(confidence, 0.0);
   
   // CRITICAL FIX: Final validation
   if(!MathIsValidNumber(confidence))
   {
      Print("[ERROR] CalculateReversalConfidence: Invalid confidence calculation");
      return 0.0;
   }
   
   return confidence;
}

//====================================================================
// TREND ALIGNMENT CHECK - Returns true if reversal aligns with HTF trend
//====================================================================
bool CReversalDetector::IsReversalAlignedWithTrend(int reversal_direction, int htf_trend_direction)
{
   // Reversal aligned means: in uptrend, we get pullback (reversal = -1), in downtrend we get bounce (reversal = 1)
   if(htf_trend_direction == 0) return true; // Neutral trend, no alignment requirement
   
   // Bullish pullback in uptrend: HTF = 1, Reversal = -1 (local down move)
   if(htf_trend_direction == 1 && reversal_direction == -1) return true;
   
   // Bearish bounce in downtrend: HTF = -1, Reversal = 1 (local up move)
   if(htf_trend_direction == -1 && reversal_direction == 1) return true;
   
   // Reversal opposes HTF trend (potential full reversal)
   return false;
}

//====================================================================
// MAIN REVERSAL DETECTION FUNCTION - ENHANCED WITH CACHING AND DEBUG
//====================================================================
SReversalSignal CReversalDetector::DetectReversal(string symbol, ENUM_TIMEFRAMES tf)
{
   SReversalSignal signal;
   signal.signal_time = TimeCurrent();

   // CRITICAL FIX: Validate parameters first
   if(StringLen(symbol) == 0 || tf <= 0)
   {
      Print("[ERROR] DetectReversal: Invalid parameters");
      return signal; // Return invalid signal
   }

   // Apply user settings
   if(!Enable_Reversal_Detection)
   {
      DebugReversalLog("[DEBUG] DetectReversal: Reversal detection disabled");
      return signal; // Return invalid signal
   }

   ApplyRuntimeSettings();

   int cache_index = GetSymbolCacheIndex(symbol);
   datetime bar_time = iTime(symbol, tf, 0);
   if(cache_index >= 0 && cache_index < REVERSAL_MAX_CACHE_SYMBOLS &&
      bar_time > 0 &&
      m_signal_cache_ready[cache_index] &&
      !m_signal_cache_trend_aware[cache_index] &&
      m_signal_cache_bar_time[cache_index] == bar_time &&
      m_signal_cache_tf[cache_index] == tf &&
      m_signal_cache_symbol[cache_index] == symbol)
   {
      SReversalSignal cached_signal = m_signal_cache[cache_index];
      cached_signal.signal_time = TimeCurrent();
      return cached_signal;
   }

   DebugReversalLog("[DEBUG] DetectReversal: Starting reversal detection for " + symbol + " on " + EnumToString(tf));

   // Try both directions
   for(int dir = -1; dir <= 1; dir += 2)
   {
      bool divergence = false;
      bool exhaustion = false;
      bool structure_break = false;
      
      // Apply user filters
      if(!g_Disable_All_Gates && Reversal_Require_Divergence)
      {
         divergence = DetectMomentumDivergence(symbol, tf, dir);
         if(!divergence) 
         {
            DebugReversalLog("[DEBUG] DetectReversal: Divergence required but not found for direction " + IntegerToString(dir));
            continue; // Skip if divergence required but not found
         }
      }
      else
      {
         divergence = DetectMomentumDivergence(symbol, tf, dir);
      }
      
      exhaustion = DetectExhaustionPattern(symbol, tf, dir);
      
      if(Reversal_Use_Structure_Break)
      {
         structure_break = DetectStructureBreak(symbol, tf, dir);
      }
      
      double momentum_shift = CalculateMomentumShift(symbol, tf);

      double confidence = CalculateReversalConfidence(divergence, exhaustion, structure_break, momentum_shift);

      // Check minimum confidence requirement
      if(confidence >= Reversal_Min_Confidence)
      {
         signal.valid = true;
         signal.direction = dir;
         signal.confidence = confidence;
         signal.divergence_detected = divergence;
         signal.exhaustion_detected = exhaustion;
         signal.structure_break = structure_break;
         signal.momentum_shift = momentum_shift;

         // Build reason string
         signal.reason = "Reversal detected: ";
         if(divergence) signal.reason += "Divergence ";
         if(exhaustion) signal.reason += "Exhaustion ";
         if(structure_break) signal.reason += "Structure-Break ";
         signal.reason += StringFormat("(Confidence: %.1f%%)", confidence * 100);

         DebugReversalLog("[DEBUG] DetectReversal: Valid reversal signal found - Direction: " + IntegerToString(dir) + 
               ", Confidence: " + DoubleToString(confidence * 100, 1) + "%, Reason: " + signal.reason);

         // Calculate entry, SL, and TP
         MqlRates rates[];
         ArraySetAsSeries(rates, true);
         int rates_copied = CopyRates(symbol, tf, 0, 3, rates);
         if(rates_copied == 3)
         {
            double atr = 0.001; // Default ATR
            int atr_handle = GetPooledIndicatorHandle(symbol, tf, 14, "ATR");
            if(atr_handle != INVALID_HANDLE)
            {
               double atr_buffer[1];
               int atr_copied = CopyBuffer(atr_handle, 0, 0, 1, atr_buffer);
               if(atr_copied == 1 && MathIsValidNumber(atr_buffer[0]))
               {
                  atr = atr_buffer[0];
               }
            }

            if(dir == 1) // Bullish reversal
            {
               signal.entry_price = rates[0].close;
               signal.stop_loss = rates[0].close - (atr * 2.0);
               signal.take_profit = rates[0].close + (atr * 3.0);
            }
            else // Bearish reversal
            {
               signal.entry_price = rates[0].close;
               signal.stop_loss = rates[0].close + (atr * 2.0);
               signal.take_profit = rates[0].close - (atr * 3.0);
            }
            
            DebugReversalLog("[DEBUG] DetectReversal: Entry: " + DoubleToString(signal.entry_price, 5) + 
                  ", SL: " + DoubleToString(signal.stop_loss, 5) + 
                  ", TP: " + DoubleToString(signal.take_profit, 5));
         }
         else
         {
            Print("[ERROR] DetectReversal: Failed to copy rates for entry calculation");
         }

         break; // Take the first valid signal
      }
      else
      {
         DebugReversalLog("[DEBUG] DetectReversal: Confidence too low for direction " + IntegerToString(dir) + 
               " - Got: " + DoubleToString(confidence * 100, 1) + "%, Required: " + 
               DoubleToString(Reversal_Min_Confidence * 100, 1) + "%");
      }
   }

   if(!signal.valid)
   {
      DebugReversalLog("[DEBUG] DetectReversal: No valid reversal signal found for " + symbol);
   }

   if(cache_index >= 0 && cache_index < REVERSAL_MAX_CACHE_SYMBOLS && bar_time > 0)
   {
      m_signal_cache[cache_index] = signal;
      m_signal_cache_bar_time[cache_index] = bar_time;
      m_signal_cache_symbol[cache_index] = symbol;
      m_signal_cache_tf[cache_index] = tf;
      m_signal_cache_trend_aware[cache_index] = false;
      m_signal_cache_htf_trend[cache_index] = 0;
      m_signal_cache_ready[cache_index] = true;
   }

   return signal;
}

//====================================================================
// TREND-AWARE REVERSAL DETECTION - Factors in HTF trend direction
//====================================================================
SReversalSignal CReversalDetector::DetectReversal(string symbol, ENUM_TIMEFRAMES tf, int htf_trend_direction)
{
   SReversalSignal signal;
   signal.signal_time = TimeCurrent();
   signal.trend_direction = htf_trend_direction;

   // CRITICAL FIX: Validate parameters first
   if(StringLen(symbol) == 0 || tf <= 0)
   {
      Print("[ERROR] DetectReversal (trend-aware): Invalid parameters");
      return signal; // Return invalid signal
   }

   // Apply user settings
   if(!Enable_Reversal_Detection)
   {
      DebugReversalLog("[DEBUG] DetectReversal (trend-aware): Reversal detection disabled");
      return signal; // Return invalid signal
   }

   ApplyRuntimeSettings();

   int cache_index = GetSymbolCacheIndex(symbol);
   datetime bar_time = iTime(symbol, tf, 0);
   if(cache_index >= 0 && cache_index < REVERSAL_MAX_CACHE_SYMBOLS &&
      bar_time > 0 &&
      m_signal_cache_ready[cache_index] &&
      m_signal_cache_trend_aware[cache_index] &&
      m_signal_cache_bar_time[cache_index] == bar_time &&
      m_signal_cache_tf[cache_index] == tf &&
      m_signal_cache_symbol[cache_index] == symbol &&
      m_signal_cache_htf_trend[cache_index] == htf_trend_direction)
   {
      SReversalSignal cached_signal = m_signal_cache[cache_index];
      cached_signal.signal_time = TimeCurrent();
      return cached_signal;
   }

   DebugReversalLog("[DEBUG] DetectReversal (trend-aware): Starting reversal detection for " + symbol + 
         " on " + EnumToString(tf) + " with HTF trend: " + IntegerToString(htf_trend_direction));

   // Try both directions
   for(int dir = -1; dir <= 1; dir += 2)
   {
      bool divergence = false;
      bool exhaustion = false;
      bool structure_break = false;
      
      // Apply user filters
      if(!g_Disable_All_Gates && Reversal_Require_Divergence)
      {
         divergence = DetectMomentumDivergence(symbol, tf, dir);
         if(!divergence) 
         {
            DebugReversalLog("[DEBUG] DetectReversal (trend-aware): Divergence required but not found for direction " + IntegerToString(dir));
            continue;
         }
      }
      else
      {
         divergence = DetectMomentumDivergence(symbol, tf, dir);
      }
      
      exhaustion = DetectExhaustionPattern(symbol, tf, dir);
      
      if(Reversal_Use_Structure_Break)
      {
         structure_break = DetectStructureBreak(symbol, tf, dir);
      }
      
      double momentum_shift = CalculateMomentumShift(symbol, tf);

      // Calculate confidence with trend awareness
      double confidence = CalculateReversalConfidence(divergence, exhaustion, structure_break, momentum_shift, htf_trend_direction);
      
      // Check trend alignment and apply adjustments
      bool aligns_with_trend = IsReversalAlignedWithTrend(dir, htf_trend_direction);
      double trend_bonus = 0.0;
      
      if(aligns_with_trend && htf_trend_direction != 0)
      {
         // Reversal aligns with HTF trend (pullback/bounce) - add confidence bonus
         trend_bonus = 0.15; // 15% confidence boost for trend-aligned reversals
         confidence = MathMin(1.0, confidence + trend_bonus);
         
         DebugReversalLog("[DEBUG] DetectReversal (trend-aware): Reversal aligns with HTF trend - bonus applied");
      }
      else if(!aligns_with_trend && htf_trend_direction != 0)
      {
         // Reversal opposes HTF trend (potential full reversal) - reduce confidence
         double trend_penalty = 0.1; // 10% confidence reduction for trend-opposing reversals
         confidence = MathMax(0.0, confidence - trend_penalty);
         
         DebugReversalLog("[DEBUG] DetectReversal (trend-aware): Reversal opposes HTF trend - penalty applied");
      }

      // Check minimum confidence requirement
      if(confidence >= Reversal_Min_Confidence)
      {
         signal.valid = true;
         signal.direction = dir;
         signal.confidence = confidence;
         signal.divergence_detected = divergence;
         signal.exhaustion_detected = exhaustion;
         signal.structure_break = structure_break;
         signal.momentum_shift = momentum_shift;
         signal.aligns_with_trend = aligns_with_trend;
         signal.trend_alignment_bonus = trend_bonus;

         // Build reason string with trend alignment info
         signal.reason = "Reversal detected: ";
         if(divergence) signal.reason += "Divergence ";
         if(exhaustion) signal.reason += "Exhaustion ";
         if(structure_break) signal.reason += "Structure-Break ";
         if(aligns_with_trend) signal.reason += "[Trend-Aligned] ";
         else if(htf_trend_direction != 0) signal.reason += "[Trend-Opposing] ";
         signal.reason += StringFormat("(Confidence: %.1f%%)", confidence * 100);

         DebugReversalLog("[DEBUG] DetectReversal (trend-aware): Valid reversal signal found - Direction: " + IntegerToString(dir) + 
               ", Confidence: " + DoubleToString(confidence * 100, 1) + "%, Trend-Aligned: " + 
               (aligns_with_trend ? "YES" : "NO") + ", Reason: " + signal.reason);

         // Calculate entry, SL, and TP
         MqlRates rates[];
         ArraySetAsSeries(rates, true);
         int rates_copied = CopyRates(symbol, tf, 0, 3, rates);
         if(rates_copied == 3)
         {
            double atr = 0.001; // Default ATR
            int atr_handle = GetPooledIndicatorHandle(symbol, tf, 14, "ATR");
            if(atr_handle != INVALID_HANDLE)
            {
               double atr_buffer[1];
               int atr_copied = CopyBuffer(atr_handle, 0, 0, 1, atr_buffer);
               if(atr_copied == 1 && MathIsValidNumber(atr_buffer[0]))
               {
                  atr = atr_buffer[0];
               }
            }

            if(dir == 1) // Bullish reversal
            {
               signal.entry_price = rates[0].close;
               signal.stop_loss = rates[0].close - (atr * 2.0);
               signal.take_profit = rates[0].close + (atr * 3.0);
            }
            else // Bearish reversal
            {
               signal.entry_price = rates[0].close;
               signal.stop_loss = rates[0].close + (atr * 2.0);
               signal.take_profit = rates[0].close - (atr * 3.0);
            }
            
            DebugReversalLog("[DEBUG] DetectReversal (trend-aware): Entry: " + DoubleToString(signal.entry_price, 5) + 
                  ", SL: " + DoubleToString(signal.stop_loss, 5) + 
                  ", TP: " + DoubleToString(signal.take_profit, 5));
         }
         else
         {
            Print("[ERROR] DetectReversal (trend-aware): Failed to copy rates for entry calculation");
         }

         break; // Take the first valid signal
      }
      else
      {
         DebugReversalLog("[DEBUG] DetectReversal (trend-aware): Confidence too low for direction " + IntegerToString(dir) + 
               " - Got: " + DoubleToString(confidence * 100, 1) + "%, Required: " + 
               DoubleToString(Reversal_Min_Confidence * 100, 1) + "%");
      }
   }

   if(!signal.valid)
   {
      DebugReversalLog("[DEBUG] DetectReversal (trend-aware): No valid reversal signal found for " + symbol);
   }

   if(cache_index >= 0 && cache_index < REVERSAL_MAX_CACHE_SYMBOLS && bar_time > 0)
   {
      m_signal_cache[cache_index] = signal;
      m_signal_cache_bar_time[cache_index] = bar_time;
      m_signal_cache_symbol[cache_index] = symbol;
      m_signal_cache_tf[cache_index] = tf;
      m_signal_cache_trend_aware[cache_index] = true;
      m_signal_cache_htf_trend[cache_index] = htf_trend_direction;
      m_signal_cache_ready[cache_index] = true;
   }

   return signal;
}

//====================================================================
// UTILITY FUNCTIONS - FIXED BOUNDS AND VALIDATION
//====================================================================
int CReversalDetector::GetSymbolCacheIndex(string symbol)
{
   // CRITICAL FIX: Validate symbol first
   if(StringLen(symbol) == 0)
   {
      Print("[ERROR] GetSymbolCacheIndex: Empty symbol");
      return 0;
   }
   
   // Simple hash function for symbol indexing
   int hash = 0;
   for(int i = 0; i < StringLen(symbol); i++)
   {
      hash += StringGetCharacter(symbol, i);
   }
   
   // CRITICAL FIX: Ensure hash is within bounds
   int index = MathAbs(hash) % 50;
   if(index < 0 || index >= REVERSAL_MAX_CACHE_SYMBOLS)
   {
      Print("[ERROR] GetSymbolCacheIndex: Index out of bounds: " + IntegerToString(index));
      return 0;
   }
   
   return index;
}

void CReversalDetector::UpdateMomentumCache(string symbol, ENUM_TIMEFRAMES tf, datetime bar_time, const SMomentumData &data)
{
   // CRITICAL FIX: Validate symbol first
   if(StringLen(symbol) == 0)
   {
      Print("[ERROR] UpdateMomentumCache: Empty symbol");
      return;
   }
   
   int index = GetSymbolCacheIndex(symbol);
   if(index >= 0 && index < REVERSAL_MAX_CACHE_SYMBOLS)
   {
      m_momentum_cache[index] = data;
      m_last_update[index] = bar_time;
      m_momentum_cache_symbol[index] = symbol;
      m_momentum_cache_tf[index] = tf;
      DebugReversalLog("[DEBUG] UpdateMomentumCache: Updated cache for " + symbol + " at index " + IntegerToString(index));
   }
   else
   {
      Print("[ERROR] UpdateMomentumCache: Invalid cache index: " + IntegerToString(index));
   }
}

#endif // REVERSAL_DETECTION_MODULE_MQH
