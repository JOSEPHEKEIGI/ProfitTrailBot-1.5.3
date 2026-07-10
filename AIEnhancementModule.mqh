//+------------------------------------------------------------------+
//|                                    AIEnhancementModule.mqh       |
//|                      Adaptive AI Decision & Confidence Fusion     |
//|                        Copyright 2026, ProfitTrailBot Ltd.       |
//|                                                                  |
//| TIER 1 ENHANCEMENTS: Adaptive thresholds + Confidence routing   |
//+------------------------------------------------------------------+

#ifndef AI_ENHANCEMENT_MODULE_MQH
#define AI_ENHANCEMENT_MODULE_MQH

#property copyright "Copyright 2026, ProfitTrailBot Ltd."
#property strict

// Define maximum symbols for caching (align with global MAX_SYMBOLS when available)
#ifndef MAX_SYMBOLS
   #define MAX_SYMBOLS 50
#endif

// Forward declarations
int GetTimeframeCacheIndex(ENUM_TIMEFRAMES tf);
double GetATRValue(string symbol, ENUM_TIMEFRAMES tf, int atr_period = 0);
double SafeDiv(double numerator, double denominator, double fallback = 0.0);
extern bool g_ai_enabled;
extern AIManager g_ai_manager;

double GetAdaptiveATRForConfiguredTimeframes(string symbol, int atr_period)
{
   ENUM_TIMEFRAMES tf_candidates[4];
   tf_candidates[0] = Signal_TF;
   tf_candidates[1] = Primary_TF;
   tf_candidates[2] = Confirm_TF;
   tf_candidates[3] = Trend_TF;

   for(int i = 0; i < 4; i++)
   {
      ENUM_TIMEFRAMES tf = tf_candidates[i];
      if(tf == PERIOD_CURRENT)
         continue;

      bool duplicate = false;
      for(int j = 0; j < i; j++)
      {
         if(tf_candidates[j] == tf)
         {
            duplicate = true;
            break;
         }
      }

      if(duplicate)
         continue;

      double atr_value = GetATRValue(symbol, tf, atr_period);
      if(atr_value > 0.0)
         return atr_value;
   }

   return 0.0;
}

//====================================================================
// ADAPTIVE THRESHOLD CALCULATOR
// Adjusts AI decision thresholds based on:
//  - Symbol volatility (vol_ratio)
//  - AI performance (accuracy feedback)
//  - Time-of-day bias (session effects)
//====================================================================

struct SAdaptiveThresholds
{
   double buy_threshold;       // Adjusted from base 0.60
   double sell_threshold;      // Adjusted from base 0.40
   double neutral_band;        // sell_threshold to buy_threshold
   double vol_adjustment_factor;
   double accuracy_adjustment_factor;
   double session_adjustment_factor;
   
   string reasoning;           // Debug explanation
   
   SAdaptiveThresholds() :
      buy_threshold(0.60),
      sell_threshold(0.40),
      neutral_band(0.20),
      vol_adjustment_factor(1.0),
      accuracy_adjustment_factor(1.0),
      session_adjustment_factor(1.0),
      reasoning("") {}
};

class CAdaptiveThresholdCalculator
{
private:
   // Cache thresholds per symbol to avoid recalculation every tick
   SAdaptiveThresholds cached_thresholds[MAX_SYMBOLS];
   datetime cached_threshold_time[MAX_SYMBOLS];
   
   double BASE_BUY_THRESHOLD;
   double BASE_SELL_THRESHOLD;
   int CACHE_REFRESH_SECONDS;
   
public:
   CAdaptiveThresholdCalculator()
   {
      // Initialize from globals: allows runtime parameter changes to affect adaptive thresholds
      BASE_BUY_THRESHOLD = g_AI_Buy_Confidence_Threshold;    // Should be 0.60 (clamped [0.50-0.90])
      BASE_SELL_THRESHOLD = g_AI_Sell_Confidence_Threshold;  // Should be 0.45 (clamped [0.10-0.50])
      CACHE_REFRESH_SECONDS = 60;
      for(int i = 0; i < MAX_SYMBOLS; i++)
         cached_threshold_time[i] = 0;
   }
   
   // Main entry point: Get contextual thresholds for a symbol
   SAdaptiveThresholds GetAdaptiveThresholds(string symbol, int symbol_index)
   {
      // Check cache validity
      datetime now = TimeCurrent();
      bool use_cache = (symbol_index >= 0 && symbol_index < MAX_SYMBOLS);
      if(use_cache && cached_threshold_time[symbol_index] > 0 && 
         (now - cached_threshold_time[symbol_index]) < CACHE_REFRESH_SECONDS)
      {
         return cached_thresholds[symbol_index];
      }
      
      SAdaptiveThresholds thresholds;
      thresholds.buy_threshold = BASE_BUY_THRESHOLD;
      thresholds.sell_threshold = BASE_SELL_THRESHOLD;
      
      // FACTOR 1: VOLATILITY SENSITIVITY
      // High volatility symbols need stronger signal confirmation to avoid whipsaws
      // Low volatility symbols need lower thresholds to catch regime changes
      double vol_adjustment = AdjustForVolatility(symbol, thresholds);
      thresholds.vol_adjustment_factor = vol_adjustment;
      
      // FACTOR 2: AI ACCURACY FEEDBACK
      // If AI is underperforming, raise thresholds (be more selective)
      // If AI is performing well, keep thresholds or lower slightly
      if(CheckAIManagerExists())
      {
         double accuracy_adjustment = AdjustForAIAccuracy(thresholds);
         thresholds.accuracy_adjustment_factor = accuracy_adjustment;
      }
      
      // FACTOR 3: TIME-OF-DAY SESSION EFFECTS
      // Different sessions have different volatility patterns
      double session_adjustment = AdjustForSession(thresholds);
      thresholds.session_adjustment_factor = session_adjustment;
      
      // APPLY ALL ADJUSTMENTS
      thresholds.buy_threshold = MathMax(0.55, 
                                         MathMin(0.75,
                                                 thresholds.buy_threshold));
      thresholds.sell_threshold = MathMax(0.25,
                                          MathMin(0.45,
                                                  thresholds.sell_threshold));
      
      thresholds.neutral_band = thresholds.buy_threshold - thresholds.sell_threshold;
      
      // Cache result (when index is valid)
      if(use_cache)
      {
         cached_thresholds[symbol_index] = thresholds;
         cached_threshold_time[symbol_index] = now;
      }
      else
      {
         thresholds.reasoning += "NO_CACHE|";
      }
      
      if((bool)MQLInfoInteger(MQL_DEBUG))
         Log(LOG_DEBUG, "AdaptiveThresholds", 
            symbol + " " + thresholds.reasoning);
      
      return thresholds;
   }

private:
   double AdjustForVolatility(string symbol, SAdaptiveThresholds &thresholds)
   {
      // Use the configured timeframe hierarchy first, then fall back across the remaining
      // configured frames so volatility logic stays aligned with the active setup.
      double atr_fast = GetAdaptiveATRForConfiguredTimeframes(symbol, 14);
      double atr_slow = GetAdaptiveATRForConfiguredTimeframes(symbol, 100);
       
      if(atr_fast <= 0.0 || atr_slow <= 0.0)
         return 1.0;  // No adjustment if data unavailable
      
      double vol_ratio = SafeDiv(atr_fast, atr_slow, 1.0);
      
      if(vol_ratio > 1.35) // ELEVATED VOLATILITY (35%+ above trend)
      {
         // Require stronger signal conviction
         thresholds.buy_threshold += 0.08;
         thresholds.sell_threshold -= 0.08;
         thresholds.reasoning += "HIGH_VOL|";
         return 1.1;  // Confidence multiplier
      }
      else if(vol_ratio > 1.15) // NORMAL - HIGH VOLATILITY
      {
         thresholds.buy_threshold += 0.03;
         thresholds.sell_threshold -= 0.03;
         thresholds.reasoning += "NORM_HIGH_VOL|";
         return 1.05;
      }
      else if(vol_ratio < 0.70) // LOW VOLATILITY (SQUEEZE/RANGE MODE)
      {
         // Market is calm - lower threshold to catch early breakout entries
         thresholds.buy_threshold -= 0.05;
         thresholds.sell_threshold += 0.05;  // Tighter neutral band
         thresholds.reasoning += "LOW_VOL|";
         return 0.95;  // Slight confidence reduction (harder to predict)
      }
      else // 0.7-1.1 = NORMAL VOLATILITY
      {
         thresholds.reasoning += "NORMAL_VOL|";
         return 1.0;
      }
   }
   
   double AdjustForAIAccuracy(SAdaptiveThresholds &thresholds)
   {
      // This function assumes AIManager exists and is tracking accuracy
      // Returns multiplier to apply to thresholds
      // Note: AIManager.GetAdaptiveScoreAdjustment() returns 0.7 to 1.15
      
      // Use AIManager performance feedback when available
      double ai_adjustment = 1.0;
      AIPerformanceStats stats;
      g_ai_manager.GetPerformanceStats(stats);
      if(stats.total_predictions < 20)
      {
         thresholds.reasoning += "AI_WARMUP|";
         return 1.0;
      }
      ai_adjustment = g_ai_manager.GetAdaptiveScoreAdjustment();
      
      // If accuracy is declining, we raise sell_threshold and lower buy_threshold
      // This makes us MORE conservative (fewer trades, higher conviction)
      if(ai_adjustment < 0.85 || stats.accuracy_rate < 0.45) // Poor accuracy
      {
         thresholds.buy_threshold += 0.04;
         thresholds.sell_threshold -= 0.04;
         thresholds.reasoning += "LOW_ACCURACY|";
      }
      else if(ai_adjustment > 1.10 || stats.accuracy_rate > 0.70) // Good accuracy
      {
         thresholds.buy_threshold -= 0.02;
         thresholds.sell_threshold += 0.02;
         thresholds.reasoning += "HIGH_ACCURACY|";
      }
      
      return ai_adjustment;
   }
   
   double AdjustForSession(SAdaptiveThresholds &thresholds)
   {
      // Market sessions have different characteristics
      // Asian: Lower volatility, tighter ranges
      // European: Increased volatility, breakouts
      // US: Highest volatility, trending
      
      // Extract hour from current timestamp (Unix time: seconds / 3600, modulo 24)
      int hour = (int)((TimeCurrent() / 3600) % 24);
      
      double buy_delta = 0.0;
      double sell_delta = 0.0;
      double session_factor = 1.0;
      
      if(hour >= 0 && hour < 8) // ASIAN SESSION (Low accuracy historically)
      {
         buy_delta += 0.02;   // Higher bar
         sell_delta -= 0.02;
         thresholds.reasoning += "ASIAN_SESSION|";
         session_factor = 0.95;  // Lower confidence
      }
      else if(hour >= 8 && hour < 14) // EUROPEAN (Normal)
      {
         thresholds.reasoning += "EUROPEAN_SESSION|";
         session_factor = 1.0;
      }
      else if(hour >= 14 && hour < 20) // US OVERLAP (Highest activity)
      {
         buy_delta -= 0.02;   // Lower bar, more opportunities
         sell_delta += 0.02;
         thresholds.reasoning += "US_SESSION|";
         session_factor = 1.05;  // Higher confidence
      }
      else // US CLOSE / OFF HOURS
      {
         buy_delta += 0.02;
         sell_delta -= 0.02;
         thresholds.reasoning += "OFF_HOURS|";
         session_factor = 0.90;
      }
      
      thresholds.buy_threshold += buy_delta;
      thresholds.sell_threshold += sell_delta;
      return session_factor;
   }
   
   bool CheckAIManagerExists()
   {
      return g_ai_enabled;
   }
};

// Global instance
CAdaptiveThresholdCalculator g_threshold_calculator;

//====================================================================
// ENHANCED AI DECISION MAKING WITH CONTEXT
//====================================================================

class CEnhancedAIDecision
{
public:
   // Make decision using adaptive thresholds
   static int MakeContextualDecision(string symbol, int symbol_index,
                                     double probability)
   {
      SAdaptiveThresholds thresholds = 
         g_threshold_calculator.GetAdaptiveThresholds(symbol, symbol_index);
      
      // Clamp probability to valid range
      probability = MathMax(0.0, MathMin(1.0, probability));
      
      // Decision logic with adaptive thresholds
      if(probability > thresholds.buy_threshold)
         return 1;    // BUY signal
      else if(probability < thresholds.sell_threshold)
         return -1;   // SELL signal
      else
         return 0;    // NEUTRAL (in dead band)
   }
   
   // Get confidence score adjusted for thresholds
   static double GetContextualConfidence(string symbol, int symbol_index,
                                         double probability)
   {
      SAdaptiveThresholds thresholds = 
         g_threshold_calculator.GetAdaptiveThresholds(symbol, symbol_index);
      
      probability = MathMax(0.0, MathMin(1.0, probability));
      
      // Distance from threshold (not from 0.5)
      double distance_from_threshold;
      
      if(probability > thresholds.buy_threshold)
         distance_from_threshold = (probability - thresholds.buy_threshold) / 
                                   (1.0 - thresholds.buy_threshold);
      else if(probability < thresholds.sell_threshold)
         distance_from_threshold = (thresholds.sell_threshold - probability) / 
                                   thresholds.sell_threshold;
      else
         distance_from_threshold = 0.0;  // In neutral band
      
      // Apply S-curve for smooth confidence
      distance_from_threshold = MathMax(0.0, MathMin(1.0, distance_from_threshold));
      double confidence = distance_from_threshold * distance_from_threshold * 
                         (3.0 - 2.0 * distance_from_threshold);
      
      return confidence;
   }
};

#endif // AI_ENHANCEMENT_MODULE_MQH
