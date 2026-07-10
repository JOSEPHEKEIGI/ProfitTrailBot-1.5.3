//+------------------------------------------------------------------+
//|                    TrendAnalysisEnhanced.mqh                      |
//|          Institutional-Grade Trend Determination System            |
//|                   Copyright 2026, ProfitTrailBot Ltd.             |
//|                                                                  |
//| TIER 1-3 ENHANCEMENT: Multi-phase trend detection with strength  |
//| quantification, momentum confirmation, and phase classification   |
//+------------------------------------------------------------------+

#ifndef TREND_ANALYSIS_ENHANCED_MQH
#define TREND_ANALYSIS_ENHANCED_MQH

#property copyright "Copyright 2026, ProfitTrailBot Ltd."
#property strict

// Include ScoringEngine for utility functions
#include "ScoringEngine.mqh"

// Define missing constants required for caching
#ifndef MAX_SYMBOLS
#define MAX_SYMBOLS 10
#endif

#ifndef MAX_TF_CACHE
#define MAX_TF_CACHE 4
#endif

//====================================================================
// ENUM DEFINITIONS
//====================================================================

enum ENUM_TREND_PHASE
{
   TREND_PHASE_NONE = 0,      // No trend or insufficient data
   TREND_PHASE_INITIATION = 1, // Early trend formation (0-25% of move)
   TREND_PHASE_DEVELOPMENT = 2, // Active continuation (25-75% of move)
   TREND_PHASE_EXHAUSTION = 3,  // Late stage, signs of weakening
   TREND_PHASE_REVERSAL = 4     // High probability reversal setup
};

enum ENUM_TREND_DIRECTION
{
   TREND_NEUTRAL = 0,
   TREND_BULLISH = 1,
   TREND_BEARISH = -1
};

//====================================================================
// STRUCTURE DEFINITIONS
//====================================================================

struct STrendStrength
{
   double sma_strength;        // SMA alignment score (0-100)
   double momentum_strength;   // Momentum confirmation (0-100)
   double oscillator_strength; // RSI/Stoch/MACD alignment (0-100)
   double volatility_strength; // Volatility & range coherence (0-100)
   double sustainability;      // Trend likelihood to continue (0-100)
   
   double composite;           // Weighted combination (0-100)
   bool valid;                 // Data sufficient for analysis
};

struct STrendAnalysis
{
   ENUM_TREND_DIRECTION direction;     // Current trend direction
   ENUM_TREND_PHASE phase;             // Current phase
   double strength;                    // 0-100: composite strength
   double sma_score;                   // 0-100: moving average alignment
   double momentum_score;              // 0-100: momentum validation
   double oscillator_score;            // 0-100: overbought/oversold safety
   double volatility_factor;           // 0.5-2.0: volatility adjustment
   double sustainability_score;        // 0-100: trend continuation likelihood
   
   int bars_in_trend;                  // Bars since trend start
   int bars_until_phase_reset;         // Bars until phase likely to change
   
   datetime last_update;               // Timestamp of last calculation
   bool is_fresh;                      // Data is current (< TTL)
   string diagnostic;                  // Debug info
};

struct STrendConfluence
{
   bool sma_aligned;           // SMA structure agrees
   bool momentum_aligned;      // Price momentum agrees
   bool oscillator_aligned;    // RSI/Stoch within acceptable range
   bool volatility_aligned;    // Volatility support trend
   
   int confluence_count;       // Number of aligned factors
   double confluence_score;    // Weighted confluence (0-100)
   bool meets_minimum;         // Meets institutional threshold
};

//====================================================================
// CACHING STRUCTURES FOR PERFORMANCE
//====================================================================

struct STrendCache
{
   datetime last_bar;
   STrendAnalysis analysis;
   int cache_ttl_seconds;
   datetime cache_time;
};

// Global caches
// STrendCache g_trend_cache[MAX_SYMBOLS][MAX_TF_CACHE];  // Disabled to reduce dependencies
int g_trend_cache_count = 0;

//====================================================================
// INSTITUTIONAL TREND ANALYZER CLASS
//====================================================================

class CTrendAnalysisEnhanced
{
private:
   // Configuration
   static const double SMA_PERIODS[4];      // 10, 20, 50, 200
   static const double MOMENTUM_THRESHOLD;  // 0.35 (35% of ATR)
   static const double PHASE_RESET_ATR;    // 1.5 (reversal threshold)
   static const double MIN_TREND_STRENGTH;  // 45.0 (minimum institutional grade)
   
public:
   // ===== TIER 1: ENHANCED TREND DETECTION =====
   
   // Main entry point: comprehensive trend analysis
   static STrendAnalysis AnalyzeTrendInstitutional(string symbol, ENUM_TIMEFRAMES tf,
                                                   int lookback_bars = 64)
   {
      STrendAnalysis result;
      result.direction = TREND_NEUTRAL;
      result.phase = TREND_PHASE_NONE;
      result.strength = 0.0;
      result.is_fresh = false;
      
      if(StringLen(symbol) <= 0 || lookback_bars < 20)
         return result;
      
      // Check cache first
      int symbol_index = -1; // No caching initially - simplified version
      int tf_index = PTBGetCoreTimeframeIndex(tf);
      // Skip cache check for now to avoid external dependencies
      
      // Fetch data
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(symbol, tf, 0, lookback_bars, rates);
      
      if(copied < 30)
      {
         result.is_fresh = false;
         result.diagnostic = "insufficient_bars";
         return result;
      }
      
      result.is_fresh = true;
      result.last_update = TimeCurrent();
      
      // Core analysis
      STrendStrength strength = CalculateTrendStrength(symbol, tf, rates, copied);
      
      result.sma_score = strength.sma_strength;
      result.momentum_score = strength.momentum_strength;
      result.oscillator_score = strength.oscillator_strength;
      result.volatility_factor = GetVolatilityAdjustment(symbol, tf, rates, copied);
      result.sustainability_score = strength.sustainability;
      
      // Composite strength (weighted)
      result.strength = CompositeStrengthScore(strength, result.volatility_factor);
      
      // Determine direction & phase
      result.direction = DetermineDirection(rates, strength);
      result.phase = DetermineTrendPhase(symbol, tf, rates, copied, strength, result.direction);
      
      // Phase-based bars calculation
      result.bars_in_trend = CalculateBarsInTrend(rates, copied, result.direction);
      result.bars_until_phase_reset = EstimatePhaseTransition(strength, result.phase);
      
      // Build diagnostic string
      result.diagnostic = StringFormat(
         "dir=%d phase=%d str=%.1f sma=%.1f mom=%.1f osc=%.1f sus=%.1f vf=%.2f bars=%d",
         result.direction, result.phase, result.strength,
         result.sma_score, result.momentum_score, result.oscillator_score,
         result.sustainability_score, result.volatility_factor, result.bars_in_trend
      );
      
      // Skip caching to avoid external dependencies
      
      return result;
   }
   
   // ===== TIER 2: TREND STRENGTH COMPONENTS =====
   
   // Calculate strength across all dimensions
   static STrendStrength CalculateTrendStrength(string symbol, ENUM_TIMEFRAMES tf,
                                                const MqlRates &rates[], int count)
   {
      STrendStrength result;
      
      if(count < 20)
      {
         result.composite = 0.0;
         return result;
      }
      
      // Component 1: SMA alignment strength
      result.sma_strength = CalculateSMAStrength(rates, count);
      
      // Component 2: Momentum validation
      result.momentum_strength = CalculateMomentumStrength(symbol, tf, rates, count);
      
      // Component 3: Oscillator confirmation
      result.oscillator_strength = CalculateOscillatorStrength(symbol, tf, rates, count);
      
      // Component 4: Volatility & range coherence
      result.volatility_strength = CalculateVolatilityStrength(rates, count);
      
      // Component 5: Sustainability metric
      result.sustainability = CalculateSustainability(rates, count);
      
      return result;
   }
   
   // SMA-based trend strength (0-100)
   static double CalculateSMAStrength(const MqlRates &rates[], int count)
   {
      double score = 0.0;
      double current = rates[0].close;
      
      double sma10 = PTBAverageClose(rates, MathMin(10, count));
      double sma20 = PTBAverageClose(rates, MathMin(20, count));
      double sma50 = PTBAverageClose(rates, MathMin(50, count));
      double sma200 = (count >= 200 ? PTBAverageClose(rates, 200) : sma50);
      
      if(sma10 <= 0 || sma20 <= 0 || sma50 <= 0)
         return 0.0;
      
      // Price vs SMAs (0-25 points)
      if(current > sma10 && current > sma20 && current > sma50)
         score += 25.0;
      else if(current < sma10 && current < sma20 && current < sma50)
         score += 25.0;
      else if(current > sma10)
         score += 12.0;
      else if(current < sma10)
         score += 12.0;
      
      // SMA stacking (0-25 points)
      if(sma10 > sma20 && sma20 > sma50 && sma50 > sma200)
         score += 25.0;
      else if(sma10 < sma20 && sma20 < sma50 && sma50 < sma200)
         score += 25.0;
      else if(sma10 > sma20 && sma20 > sma50)
         score += 15.0;
      else if(sma10 < sma20 && sma20 < sma50)
         score += 15.0;
      
      // MA separation (0-20 points)
      double separation = MathAbs(sma20 - sma50) / sma50;
      double sep_score = MathMin(20.0, separation * 40.0);
      score += sep_score;
      
      // SMA angle (0-15 points)
      if(count >= 5)
      {
         double sma20_past = PTBAverageClose(rates, MathMin(20, MathMax(5, count - 5)));
         if(sma20_past > 0)
         {
            double angle = (sma20 - sma20_past) / sma20_past;
            score += MathMin(15.0, MathAbs(angle) * 150.0);
         }
      }
      
      // Range tightening (0-15 points)
      double avg_range_recent = PTBAverageRange(rates, 0, MathMin(5, count));
      double avg_range_past = PTBAverageRange(rates, 5, MathMin(20, count));
      if(avg_range_past > 0)
      {
         if(avg_range_recent > avg_range_past)
            score += 10.0;
      }
      
      return MathMin(100.0, score);
   }
   
   // Momentum validation (0-100)
   static double CalculateMomentumStrength(string symbol, ENUM_TIMEFRAMES tf,
                                          const MqlRates &rates[], int count)
   {
      double score = 0.0;
      
      if(count < 6)
         return 0.0;
      
      double atr = GetATRValue(symbol, tf, 14);
      if(atr <= 0)
         atr = PTBAverageRange(rates, 0, MathMin(14, count));
      if(atr <= 0)
         return 0.0;
      
      double momentum_threshold = atr * 0.35; // MOMENTUM_THRESHOLD
      
      // Recent momentum (0-30 points)
      double momentum_1bar = rates[0].close - rates[1].close;
      double momentum_5bar = rates[0].close - rates[5].close;
      
      if(MathAbs(momentum_5bar) > momentum_threshold)
         score += 30.0;
      else if(MathAbs(momentum_5bar) > momentum_threshold * 0.7)
         score += 20.0;
      
      // Momentum persistence (0-35 points)
      int momentum_bars = 0;
      for(int i = 0; i < MathMin(8, count - 1); i++)
      {
         double delta = rates[i].close - rates[i + 1].close;
         if((momentum_5bar > 0 && delta > 0) || (momentum_5bar < 0 && delta < 0))
            momentum_bars++;
      }
      score += (double)momentum_bars * 4.375; // (35 / 8)
      
      // MACD validation (0-20 points)
      double macd_val = 0.0, macd_signal = 0.0;
      if(GetMomentumValues(symbol, tf, -1, macd_val, macd_signal))
      {
         if((momentum_5bar > 0 && macd_val > 0) || (momentum_5bar < 0 && macd_val < 0))
            score += 20.0;
         else if(MathAbs(macd_val) < MathAbs(macd_signal) * 2)
            score += 10.0;
      }
      
      // Volume confirmation (0-15 points)
      double vol_current = (double)rates[0].tick_volume;
      double vol_avg = 0.0;
      for(int i = 1; i < MathMin(10, count); i++)
         vol_avg += (double)rates[i].tick_volume;
      vol_avg /= MathMin(9, count - 1);
      if(vol_avg > 0 && vol_current > vol_avg * 1.3)
         score += 15.0;
      
      return MathMin(100.0, score);
   }
   
   // Oscillator confirmation - RSI/Stoch/MACD alignment (0-100)
   static double CalculateOscillatorStrength(string symbol, ENUM_TIMEFRAMES tf,
                                            const MqlRates &rates[], int count)
   {
      double score = 0.0;
      int indicators_valid = 0;
      double rsi = GetRSIValue(symbol, tf, 14);
      double stoch = 0.0; // Would need stoch indicator integration
      double macd = 0.0;
      
      // RSI validation (0-40 points)
      if(rsi >= 0 && rsi <= 100)
      {
         indicators_valid++;
         
         // Avoid extremes (early reversal detection)
         if(rsi > 70)
            score += 10.0; // Overbought
         else if(rsi < 30)
            score += 10.0; // Oversold
         else if(rsi > 50)
         {
            // Bullish bias: RSI > 50 is healthy
            if(rates[0].close > rates[5].close)
               score += 20.0;
            else
               score += 10.0;
         }
         else if(rsi < 50)
         {
            // Bearish bias: RSI < 50 is healthy
            if(rates[0].close < rates[5].close)
               score += 20.0;
            else
               score += 10.0;
         }
      }
      
      // MACD confirmation (0-30 points)
      double macd_val = 0.0, macd_signal = 0.0;
      if(GetMomentumValues(symbol, tf, -1, macd_val, macd_signal))
      {
         indicators_valid++;
         
         if((macd_val > 0 && macd_val > macd_signal) || (macd_val < 0 && macd_val < macd_signal))
            score += 30.0;
         else if(MathAbs(macd_val - macd_signal) < MathAbs(macd_signal) * 0.2)
            score += 15.0;
      }
      
      // Stoch would go here (0-30 points)
      
      // Normalize by number of valid indicators
      if(indicators_valid > 0)
         score = score / indicators_valid * 50.0; // Weight to 50 max + scale
      
      return MathMin(100.0, score);
   }
   
   // Volatility coherence and range structure (0-100)
   static double CalculateVolatilityStrength(const MqlRates &rates[], int count)
   {
      if(count < 10)
         return 50.0;
      
      double score = 0.0;
      
      // Range expansion/contraction consistency (0-30 points)
      double range_current = rates[0].high - rates[0].low;
      double range_avg = 0.0;
      for(int i = 1; i < MathMin(10, count); i++)
         range_avg += (rates[i].high - rates[i].low);
      range_avg /= MathMin(9, count - 1);
      
      if(range_avg > 0)
      {
         // FIX #10: Use SafeDiv for division operations
         double ratio = SafeDiv(range_current, range_avg, 1.0);
         if(ratio >= 1.2)
            score += 30.0; // Strong directional candle
         else if(ratio >= 0.9)
            score += 20.0;
         else
            score += 10.0;
      }
      
      // True Range consistency (0-20 points)
      double tr_avg = 0.0, tr_dev = 0.0;
      for(int i = 0; i < MathMin(14, count); i++)
      {
         double high = rates[i].high;
         double low = rates[i].low;
         double close_prev = (i > 0 ? rates[i + 1].close : rates[i].close);
         
         double tr = high - low;
         tr = MathMax(tr, high - close_prev);
         tr = MathMax(tr, close_prev - low);
         
         tr_avg += tr;
      }
      tr_avg /= MathMin(14.0, count);
      
      if(tr_avg > 0)
      {
         double volatility_consistency = 1.0 - (tr_dev / tr_avg);
         score += MathMin(20.0, volatility_consistency * 20.0);
      }
      
      // Price within range (0-20 points)
      double avg_close = PTBAverageClose(rates, MathMin(10, count));
      if(avg_close > 0)
      {
         double range = rates[0].high - rates[0].low;
         if(range > 0) // FIX #11: Avoid zero division when candle has no range
         {
            double close_location = (rates[0].close - rates[0].low) / range;
            if(close_location >= 0.3 && close_location <= 0.7)
               score += 20.0;
            else if(close_location >= 0.2 && close_location <= 0.8)
               score += 15.0;
         }
      }
      
      // No wild extremes (0-10 points)
      bool has_extreme = false;
      for(int i = 0; i < MathMin(5, count); i++)
      {
         double range = rates[i].high - rates[i].low;
         if(range > range_avg * 2.5)
         {
            has_extreme = true;
            break;
         }
      }
      if(!has_extreme)
         score += 10.0;
      
      return MathMin(100.0, score);
   }
   
   // Trend sustainability: likelihood of continuation (0-100)
   static double CalculateSustainability(const MqlRates &rates[], int count)
   {
      if(count < 20)
         return 50.0;
      
      double score = 0.0;
      
      // HH/LL pattern (0-40 points)
      int hh_count = 0, ll_count = 0;
      for(int i = 0; i < MathMin(10, count - 1); i++)
      {
         if(rates[i].high > rates[i + 1].high)
            hh_count++;
         if(rates[i].low > rates[i + 1].low)
            ll_count++;
      }
      
      if(hh_count >= 6 || ll_count >= 6)
         score += 40.0;
      else if(hh_count >= 4 || ll_count >= 4)
         score += 25.0;
      else
         score += 10.0;
      
      // Trend continuation strength (0-30 points)
      double trend_strength_test = 0.0;
      for(int i = 0; i < MathMin(5, count - 1); i++)
      {
         if(rates[i].close > rates[i + 1].close)
            trend_strength_test += 1.0;
         else
            trend_strength_test -= 1.0;
      }
      
      if(MathAbs(trend_strength_test) >= 4.0)
         score += 30.0;
      else if(MathAbs(trend_strength_test) >= 2.0)
         score += 20.0;
      
      // Volatility regime (0-20 points)
      double avg_range_recent = PTBAverageRange(rates, 0, MathMin(5, count));
      double avg_range_historical = PTBAverageRange(rates, 5, MathMin(20, count));
      if(avg_range_historical > 0 && avg_range_recent > avg_range_historical * 0.85)
         score += 20.0;
      else if(avg_range_recent > avg_range_historical * 0.6)
         score += 10.0;
      
      // Support/Resistance holds (0-10 points)
      double min_recent = rates[0].low;
      for(int i = 0; i < MathMin(3, count); i++)
         min_recent = MathMin(min_recent, rates[i].low);
      
      double max_recent = rates[0].high;
      for(int i = 0; i < MathMin(3, count); i++)
         max_recent = MathMax(max_recent, rates[i].high);
      
      if(rates[0].close < max_recent && rates[0].close > min_recent)
         score += 10.0;
      
      return MathMin(100.0, score);
   }
   
   // Volatility adjustment factor (0.5-2.0)
   static double GetVolatilityAdjustment(string symbol, ENUM_TIMEFRAMES tf,
                                        const MqlRates &rates[], int count)
   {
      double atr = GetATRValue(symbol, tf, 14);
      if(atr <= 0)
         return 1.0;
      
      double avg_range = PTBAverageRange(rates, 0, MathMin(30, count));
      if(avg_range <= 0)
         return 1.0;
      
      // FIX #10: Use SafeDiv for division operations
      double vol_ratio = SafeDiv(atr, avg_range, 1.0);
      
      // High volatility dampens confidence
      if(vol_ratio > 1.5)
         return 0.65;
      else if(vol_ratio > 1.2)
         return 0.8;
      else if(vol_ratio < 0.6)
         return 1.3; // Low vol, tighter bands accepted
      else if(vol_ratio < 0.8)
         return 1.1;
      
      return 1.0;
   }
   
   // ===== TIER 3: COMPOSITE & CLASSIFICATION =====
   
   // Composite strength score (0-100) with weighting
   static double CompositeStrengthScore(const STrendStrength &strength, double vol_factor)
   {
      double weights[5] = {0.25, 0.25, 0.20, 0.15, 0.15};
      double components[5] = {
         strength.sma_strength,
         strength.momentum_strength,
         strength.oscillator_strength,
         strength.volatility_strength,
         strength.sustainability
      };
      
      double weighted = 0.0;
      for(int i = 0; i < 5; i++)
         weighted += components[i] * weights[i];
      
      // Apply volatility adjuster
      if(vol_factor < 1.0)
         weighted = weighted * vol_factor;
      else if(vol_factor > 1.0)
         weighted = weighted / vol_factor;
      
      return MathMin(100.0, MathMax(0.0, weighted));
   }
   
   // Determine trend direction
   static ENUM_TREND_DIRECTION DetermineDirection(const MqlRates &rates[], const STrendStrength &strength)
   {
      if(strength.sma_strength + strength.momentum_strength + strength.oscillator_strength < 60.0)
         return TREND_NEUTRAL;
      
      double bullish = 0.0, bearish = 0.0;
      
      if(rates[0].close > rates[0].open)
         bullish += 1.5;
      else
         bearish += 1.5;
      
      if(strength.sma_strength > 50.0)
      {
         // Determine from SMA: price vs SMAs
         double sma10 = 0.0;
         for(int i = 0; i < MathMin(10, ArraySize(rates)); i++)
            sma10 += rates[i].close;
         sma10 /= MathMin(10.0, ArraySize(rates));
         
         if(rates[0].close > sma10)
            bullish += 2.0;
         else
            bearish += 2.0;
      }
      
      if(strength.momentum_strength > 50.0)
      {
         if(rates[0].close > rates[5].close)
            bullish += 1.5;
         else
            bearish += 1.5;
      }
      
      if(bullish > bearish)
         return TREND_BULLISH;
      else if(bearish > bullish)
         return TREND_BEARISH;
      else
         return TREND_NEUTRAL;
   }
   
   // Classify trend into phase
   static ENUM_TREND_PHASE DetermineTrendPhase(string symbol, ENUM_TIMEFRAMES tf,
                                              const MqlRates &rates[], int count,
                                              const STrendStrength &strength,
                                              ENUM_TREND_DIRECTION direction)
   {
      if(direction == TREND_NEUTRAL || strength.composite < 35.0)
         return TREND_PHASE_NONE;
      
      // Phase detection based on strength indicators
      double sma_strength = strength.sma_strength;
      double momentum_strength = strength.momentum_strength;
      double sustainability = strength.sustainability;
      
      // Exhaustion phase: Strong trend weakening indicators
      if(sma_strength >= 70.0 && momentum_strength < 40.0)
         return TREND_PHASE_EXHAUSTION;
      
      // Reversal phase: Clear reversal signals
      if(momentum_strength < 25.0 && sustainability < 40.0)
         return TREND_PHASE_REVERSAL;
      
      // Development phase: Established trend with momentum
      if(sma_strength >= 60.0 && momentum_strength >= 50.0 && sustainability >= 55.0)
         return TREND_PHASE_DEVELOPMENT;
      
      // Initiation phase: Trend forming
      if(sma_strength >= 45.0 && momentum_strength >= 35.0)
         return TREND_PHASE_INITIATION;
      
      return TREND_PHASE_NONE;
   }
   
   // ===== TIER 4: HELPER FUNCTIONS =====
   
   static int CalculateBarsInTrend(const MqlRates &rates[], int count, ENUM_TREND_DIRECTION direction)
   {
      if(direction == TREND_NEUTRAL || count < 5)
         return 0;
      
      int bars = 0;
      for(int i = 0; i < MathMin(count - 1, 50); i++)
      {
         bool higher = (rates[i].close > rates[i + 1].close && rates[i].low >= rates[i + 1].low);
         bool lower = (rates[i].close < rates[i + 1].close && rates[i].high <= rates[i + 1].high);
         
         if((direction == TREND_BULLISH && higher) || (direction == TREND_BEARISH && lower))
            bars++;
         else if(bars > 0)
            break;
      }
      
      return bars;
   }
   
   static int EstimatePhaseTransition(const STrendStrength &strength, ENUM_TREND_PHASE phase)
   {
      if(phase == TREND_PHASE_NONE)
         return 0;
      
      // Based on sustainability score, estimate bars until phase change
      double sustainability_gap = 100.0 - strength.sustainability;
      int estimated_bars = (int)(sustainability_gap / 5.0);
      
      return MathMax(1, MathMin(50, estimated_bars));
   }
   
   // ===== CACHING & LIFECYCLE =====
   
   static bool IsTrendCacheFresh(int symbol_index, int tf_index)
   {
      // Caching disabled to reduce dependencies
      return false;
   }
   
   static void CacheTrendAnalysis(int symbol_index, int tf_index, const STrendAnalysis &analysis)
   {
      // Caching disabled to reduce dependencies
   }
};

// Initialize static const arrays
const double CTrendAnalysisEnhanced::SMA_PERIODS[4] = {10, 20, 50, 200};
const double CTrendAnalysisEnhanced::MOMENTUM_THRESHOLD = 0.35;
const double CTrendAnalysisEnhanced::PHASE_RESET_ATR = 1.5;
const double CTrendAnalysisEnhanced::MIN_TREND_STRENGTH = 45.0;

#endif // TREND_ANALYSIS_ENHANCED_MQH
