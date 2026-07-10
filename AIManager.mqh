#ifndef AI_MANAGER_MQH
#define AI_MANAGER_MQH

//+------------------------------------------------------------------+
//|                                                   AIManager.mqh |
//|                        Copyright 2024, ProfitTrailBot Ltd.      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, ProfitTrailBot Ltd."
#property strict

// AI Performance Structure
struct AIPerformanceStats
{
   double accuracy_rate;
   int total_predictions;
   int correct_predictions;
   bool needs_retraining;
};

// AI Prediction Cache Structure
struct AIPredictionCache
{
   double probability;   // Bullish probability (for backward compatibility)
   double buy_prob;
   double sell_prob;
   datetime last_update;
   double confidence;
   int access_count;
   datetime created_time;
   ENUM_TIMEFRAMES tf;
   datetime bar_time;
   long source_tick_msc;
};

// AI Manager Class
class AIManager
{
private:
   int training_samples;
   int model_type; // 0 = Logistic, 1 = Neural
   
   // Adaptive learning tracking
   int total_predictions;
   int correct_predictions;
   double current_accuracy;
   double accuracy_moving_avg;
   
public:
   void Init() 
   {
      training_samples = 0;
      model_type = 0;
      
      // Initialize performance tracking
      total_predictions = 0;
      correct_predictions = 0;
      current_accuracy = 0.5;
      accuracy_moving_avg = 0.5;
   }
   
   void Reset() 
   {
      training_samples = 0;
      model_type = 0;
      total_predictions = 0;
      correct_predictions = 0;
      current_accuracy = 0.5;
      accuracy_moving_avg = 0.5;
   }
   
   // Update accuracy tracking with actual trade result
   void UpdateAccuracy(bool prediction_correct)
   {
      total_predictions++;
      if(prediction_correct) 
         correct_predictions++;
      
      // Calculate current accuracy
      if(total_predictions > 0)
         current_accuracy = (double)correct_predictions / total_predictions;
      
      // Exponential moving average: EMA = (new_value * alpha) + (old_value * (1-alpha))
      double alpha = 0.2; // Weight for recent data
      accuracy_moving_avg = (current_accuracy * alpha) + (accuracy_moving_avg * (1.0 - alpha));
   }
   
   // BUG FIX 1.7: Adaptive threshold adjustor with BOUNDED output
   // Original multiplier range: 0.7 to 1.15 - can oscillate and compound unpredictably
   // Fixed range: 0.75 to 1.25 with additional dampening to prevent feedback loop oscillation
   double GetAdaptiveScoreAdjustment()
   {
      // If accuracy < 50%, reduce confidence in predictions
      // If accuracy > 70%, increase confidence
      if(total_predictions < 10) return 1.0; // Not enough data, use default
      
      // Apply conservative scaling to prevent oscillation
      double adjustment = 1.0;
      if(accuracy_moving_avg < 0.45)      adjustment = 0.80;  // -20% max reduction
      else if(accuracy_moving_avg < 0.50) adjustment = 0.90;  // -10% reduction
      else if(accuracy_moving_avg > 0.70) adjustment = 1.15;  // +15% max increase
      else if(accuracy_moving_avg > 0.65) adjustment = 1.07;  // +7% increase
      
      // Final safety clamp: ensure multiplier never exceeds safe bounds [0.75, 1.25]
      return MathMax(0.75, MathMin(1.25, adjustment));
   }
   
   double GetPrediction(double close0, double close1, double close5, double atr, 
                       double rsi, double ma_slope, double vol0, double vol1, 
                       double vol_avg, double macd, double stoch, double sentiment,
                       double htf_bias = 0.0, double vol_regime = 1.0) 
   {
      string dummy = "";
      return GetPredictionWithDiag(close0, close1, close5, atr, rsi, ma_slope,
                                   vol0, vol1, vol_avg, macd, stoch, sentiment,
                                   htf_bias, vol_regime, dummy);
   }

   double GetPredictionWithDiag(double close0, double close1, double close5, double atr, 
                                double rsi, double ma_slope, double vol0, double vol1, 
                                double vol_avg, double macd, double stoch, double sentiment,
                                double htf_bias, double vol_regime, string &diag_out)
   {
      training_samples++;
      
      // Input validation - CRITICAL
      if(close0 <= 0 || close1 <= 0 || atr <= 0 || vol_avg <= 0)
      {
         Log(LOG_WARNING, "AIManager::GetPrediction", "Invalid input: close0=" + DoubleToString(close0, 5) + " close1=" + DoubleToString(close1, 5) + " atr=" + DoubleToString(atr, 5) + " vol_avg=" + DoubleToString(vol_avg, 5));
         diag_out = "invalid_inputs";
         return 0.5; // Return neutral
      }
      
      // Validate indicator ranges
      if(rsi < 0 || rsi > 100)
      {
         Log(LOG_WARNING, "AIManager::GetPrediction", "Invalid RSI: " + DoubleToString(rsi, 2));
         rsi = 50; // Neutral fallback
      }
      
      if(stoch < 0 || stoch > 100)
      {
         Log(LOG_WARNING, "AIManager::GetPrediction", "Invalid Stochastic: " + DoubleToString(stoch, 2));
         stoch = 50; // Neutral fallback
      }
      
      // MACD can be any value, but check for extreme outliers
      if(MathAbs(macd) > atr * 10)
      {
         Log(LOG_WARNING, "AIManager::GetPrediction", "MACD outlier detected: " + DoubleToString(macd, 8));
         macd = (macd > 0 ? 1 : macd < 0 ? -1 : 0) * (atr * 5); // Clamp to reasonable range
      }
      
      // MA slope validation
      if(MathAbs(ma_slope) > close0 * 0.1)
      {
         Log(LOG_WARNING, "AIManager::GetPrediction", "MA slope outlier: " + DoubleToString(ma_slope, 8));
         ma_slope = (ma_slope > 0 ? 1 : ma_slope < 0 ? -1 : 0) * (close0 * 0.05); // Clamp to ±5%
      }
      
      // Simple prediction logic based on technical indicators
      double score = 0.5; // Neutral starting point
      double comp_rsi = 0.0, comp_ma = 0.0, comp_macd = 0.0, comp_mom = 0.0, comp_stoch = 0.0, comp_vol = 0.0, comp_htf = 0.0, comp_adapt = 0.0, comp_volreg = 0.0;
      
      // RSI component (overbought/oversold)
      if(rsi > 70) comp_rsi = -0.1;
      else if(rsi < 30) comp_rsi = 0.1;
      score += comp_rsi;
      
      // MA slope component (trend direction)
      if(ma_slope > 0) comp_ma = 0.05;
      else if(ma_slope < 0) comp_ma = -0.05;
      score += comp_ma;
      
      // MACD component (momentum)
      if(macd > 0) comp_macd = 0.05;
      else if(macd < 0) comp_macd = -0.05;
      score += comp_macd;
      
      // Price momentum (clamped to prevent extreme values)
      double momentum = (close0 - close1) / close1;
      momentum = MathMax(-0.05, MathMin(0.05, momentum)); // Clamp to ±5%
      comp_mom = momentum * 0.5; // Reduced scaling from 2.0 to 0.5
      score += comp_mom;
      
      // Stochastic component (overbought/oversold confirmation)
      if(stoch > 80) comp_stoch = -0.05;
      else if(stoch < 20) comp_stoch = 0.05;
      score += comp_stoch;
      
      // Volume component (breakout confirmation)
      if(vol0 > vol_avg * 1.5) comp_vol = 0.02;
      score += comp_vol;
      
      // HTF bias component (aligns with dominant higher timeframe trend)
      comp_htf = htf_bias * 0.10; // ±10% influence when strong bias
      score += comp_htf;

      // Apply adaptive adjustment based on recent performance
      double adaptive_multiplier = GetAdaptiveScoreAdjustment();
      comp_adapt = (score - 0.5) * (adaptive_multiplier - 1.0);
      score = 0.5 + (score - 0.5) * adaptive_multiplier;

      // Volatility regime dampening: high vol shrinks confidence, low vol enhances slightly
      double vr = MathMax(0.5, MathMin(vol_regime, 2.0)); // clamp to reasonable range
      double vol_scale = 1.0 / MathSqrt(vr);              // >1 low vol, <1 high vol
      comp_volreg = (score - 0.5) * (vol_scale - 1.0);
      score = 0.5 + (score - 0.5) * vol_scale;
      
      // BUG FIX 1.1: Clamp score after each adjustment to prevent exceeding [0,1] during calculations
      // This ensures intermediate values (used in diagnostics) are valid and consistent
      score = MathMax(0.0, MathMin(1.0, score));

      // Build diagnostic string (compact for logging)
      diag_out = StringFormat("rsi=%.1f(%.3f)|ma=%.5f(%.3f)|macd=%.5f(%.3f)|mom=%.3f(%.3f)|stoch=%.1f(%.3f)|vol=%.0f/%.0f(%.3f)|htf=%.2f(%.3f)|adapt=%.3f|volReg=%.3f|vr=%.2f|score=%.3f",
                              rsi, comp_rsi,
                              ma_slope, comp_ma,
                              macd, comp_macd,
                              momentum, comp_mom,
                              stoch, comp_stoch,
                              vol0, vol_avg, comp_vol,
                              htf_bias, comp_htf,
                              comp_adapt, comp_volreg, vr, score);
      
      return score;
   }
   
   void GetStats(int &training_count, int &model_type_out) 
   { 
      training_count = training_samples; 
      model_type_out = model_type;
   }
   
   // Get current performance metrics
   void GetPerformanceStats(AIPerformanceStats &stats)
   {
      stats.accuracy_rate = accuracy_moving_avg;
      stats.total_predictions = total_predictions;
      stats.correct_predictions = correct_predictions;
      stats.needs_retraining = (accuracy_moving_avg < 0.50);
   }
};

#endif // AI_MANAGER_MQH
