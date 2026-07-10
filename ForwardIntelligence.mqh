//+------------------------------------------------------------------+
//|                              ForwardIntelligence.mqh             |
//|         Market Regime Prediction & Volatility Forecasting        |
//|                        Copyright 2026, ProfitTrailBot Ltd.       |
//|                                                                  |
//| TIER 2 FORWARD INTELLIGENCE: Predict regime shifts & volatility |
//+------------------------------------------------------------------+

#ifndef FORWARD_INTELLIGENCE_MQH
#define FORWARD_INTELLIGENCE_MQH

#property copyright "Copyright 2026, ProfitTrailBot Ltd."
#property strict

// Forward declarations
double GetATRValue(string symbol, ENUM_TIMEFRAMES tf, int atr_period = 0);
double GetRSIValue(string symbol, ENUM_TIMEFRAMES tf, int period);
int GetPooledIndicatorHandle(string symbol, ENUM_TIMEFRAMES tf, int period, string type);
double SafeDiv(double num, double denom, double fallback = 0.0);

//====================================================================
// MARKET REGIME FORECAST
// Predicts next 5-bar market regime (Trend/Range/Retracement)
// Uses multi-factor analysis with Bollinger Bands, ATR, momentum
//====================================================================

struct SRegimeForecast
{
   double trend_probability;      // P(next 5 bars trending)
   double range_probability;      // P(next 5 bars ranging)
   double retracement_probability;// P(next 5 bars retracing)
   double vol_spike_probability;  // P(volatility spike)
   double breakout_probability;   // P(breakout happening)
   
   // Supporting metrics
   double bb_width_current;       // Current Bollinger Band width
   double bb_width_20bar_avg;     // 20-bar average width
   double bb_squeeze_ratio;       // current / average (< 0.6 = squeeze)
   double atr_current;            // Current ATR
   double atr_5bar_avg;           // 5-bar average ATR
   double atr_expansion_rate;     // Rate of ATR increase
   double rsi_current;            // Current RSI
   double momentum_direction;     // EMA slope indicator
   
   // Predictions
   string predicted_regime;       // "TREND" | "RANGE" | "RETRACEMENT"
   int predicted_direction;       // 1 (up) | -1 (down) | 0 (unknown)
   double confidence;             // 0-1 confidence in prediction
   datetime forecast_time;
   ENUM_TIMEFRAMES timeframe;
   
   SRegimeForecast() :
      trend_probability(0.33),
      range_probability(0.34),
      retracement_probability(0.33),
      vol_spike_probability(0.0),
      breakout_probability(0.0),
      bb_width_current(0.0),
      bb_width_20bar_avg(1.0),
      bb_squeeze_ratio(1.0),
      atr_current(0.0),
      atr_5bar_avg(1.0),
      atr_expansion_rate(0.0),
      rsi_current(50.0),
      momentum_direction(0.0),
      predicted_regime("NEUTRAL"),
      predicted_direction(0),
      confidence(0.0),
      forecast_time(0),
      timeframe(PERIOD_CURRENT) {}
};

class CRegimePredictor
{
public:
   // Main entry: Forecast next market regime
   static SRegimeForecast PredictMarketRegime(string symbol, ENUM_TIMEFRAMES tf)
   {
      SRegimeForecast forecast;
      forecast.timeframe = tf;
      forecast.forecast_time = TimeCurrent();
      
      // FACTOR 1: Bollinger Band Width Analysis
      // Tight BB = Squeeze = Breakout likely
      // Wide BB = Breaking = Trend likely
      AnalyzeBollingerBandWidth(symbol, tf, forecast);
      
      // FACTOR 2: ATR Expansion/Contraction
      // Rising ATR = Volatility increase = Trend starting
      // Falling ATR = Volatility decrease = Range/Consolidation
      AnalyzeATRExpansion(symbol, tf, forecast);
      
      // FACTOR 3: RSI Extremity
      // Extreme RSI (>75 or <25) = Reversal likely
      // Normal RSI (35-65) = Trend continuation likely
      AnalyzeRSIExtremity(symbol, tf, forecast);
      
      // FACTOR 4: Momentum Direction
      // Strong EMA slope = Trend likely
      // Flat EMA slope = Range likely
      AnalyzeMomentumDirection(symbol, tf, forecast);
      
      // NORMALIZE probabilities to sum to 1.0
      double total_prob = forecast.trend_probability + 
                          forecast.range_probability + 
                          forecast.retracement_probability;
      
      if(total_prob > 0.0)
      {
         forecast.trend_probability /= total_prob;
         forecast.range_probability /= total_prob;
         forecast.retracement_probability /= total_prob;
      }
      
      // DETERMINE PRIMARY PREDICTION
      DeterminePrimaryRegime(forecast);
      
      return forecast;
   }
   
private:
   static void AnalyzeBollingerBandWidth(string symbol, ENUM_TIMEFRAMES tf,
                                          SRegimeForecast &forecast)
   {
      // Get Bollinger Bands
      int bb_handle = GetPooledIndicatorHandle(symbol, tf, 20, "BBANDS");
      if(bb_handle == INVALID_HANDLE)
         return;
      
      // Copy upper and lower bands (use 20-bar window + current)
      const int BB_COUNT = 21;
      double bb_upper[], bb_lower[];
      ArraySetAsSeries(bb_upper, true);
      ArraySetAsSeries(bb_lower, true);
      
      int copied_upper = CopyBuffer(bb_handle, 1, 0, BB_COUNT, bb_upper);  // Upper band
      int copied_lower = CopyBuffer(bb_handle, 2, 0, BB_COUNT, bb_lower);  // Lower band
      if(copied_upper != BB_COUNT || copied_lower != BB_COUNT)
         return;
      
      // Current width (current bar)
      if(bb_upper[0] > 0.0 && bb_lower[0] > 0.0)
         forecast.bb_width_current = bb_upper[0] - bb_lower[0];
      
      // 20-bar average width (exclude current bar)
      double sum = 0.0;
      int count = 0;
      for(int i = 1; i < BB_COUNT; i++)
      {
         if(bb_upper[i] > 0.0 && bb_lower[i] > 0.0)
         {
            sum += (bb_upper[i] - bb_lower[i]);
            count++;
         }
      }
      if(count > 0)
         forecast.bb_width_20bar_avg = sum / count;
      else if(forecast.bb_width_current > 0.0)
         forecast.bb_width_20bar_avg = forecast.bb_width_current;
      
      // Calculate squeeze ratio
      forecast.bb_squeeze_ratio = SafeDiv(forecast.bb_width_current,
                                          forecast.bb_width_20bar_avg, 1.0);
      
      // INTERPRETATION
      if(forecast.bb_squeeze_ratio < 0.5) // Very tight squeeze
      {
         forecast.range_probability *= 1.8;  // Strong range signal
         forecast.breakout_probability += 0.4;
         forecast.vol_spike_probability += 0.5;
      }
      else if(forecast.bb_squeeze_ratio < 0.7) // Normal squeeze
      {
         forecast.range_probability *= 1.3;
         forecast.breakout_probability += 0.25;
      }
      else if(forecast.bb_squeeze_ratio > 1.5) // Expansion
      {
         forecast.trend_probability *= 1.4;
         forecast.range_probability *= 0.6;
         forecast.vol_spike_probability += 0.3;
      }
   }
   
   static void AnalyzeATRExpansion(string symbol, ENUM_TIMEFRAMES tf,
                                    SRegimeForecast &forecast)
   {
      // Get current and recent ATR values
      int atr_handle = GetPooledIndicatorHandle(symbol, tf, 14, "ATR");
      if(atr_handle == INVALID_HANDLE)
         return;
      
      const int ATR_COUNT = 6; // current + 5 bars
      double atr_vals[];
      ArraySetAsSeries(atr_vals, true);
      if(CopyBuffer(atr_handle, 0, 0, ATR_COUNT, atr_vals) != ATR_COUNT)
         return;
      
      if(!MathIsValidNumber(atr_vals[0]) || atr_vals[0] <= 0.0)
         return;
      
      forecast.atr_current = atr_vals[0];
      
      // Calculate recent average ATR (last 5 bars, exclude current)
      double atr_sum = 0.0;
      int count = 0;
      for(int i = 1; i < ATR_COUNT; i++)
      {
         if(MathIsValidNumber(atr_vals[i]) && atr_vals[i] > 0.0)
         {
            atr_sum += atr_vals[i];
            count++;
         }
      }
      if(count > 0)
         forecast.atr_5bar_avg = atr_sum / count;
      else
         forecast.atr_5bar_avg = forecast.atr_current;
      
      // ATR expansion rate
      forecast.atr_expansion_rate = SafeDiv(forecast.atr_current,
                                            forecast.atr_5bar_avg, 1.0);
      
      // INTERPRETATION
      if(forecast.atr_expansion_rate > 1.2) // ATR rising 20%+
      {
         forecast.trend_probability += 0.3;   // Trend setup
         forecast.vol_spike_probability += 0.3;
         forecast.range_probability *= 0.7;
      }
      else if(forecast.atr_expansion_rate < 0.8) // ATR falling
      {
         forecast.range_probability += 0.2;
         forecast.trend_probability *= 0.8;
      }
   }
   
   static void AnalyzeRSIExtremity(string symbol, ENUM_TIMEFRAMES tf,
                                    SRegimeForecast &forecast)
   {
      forecast.rsi_current = GetRSIValue(symbol, tf, 14);
      
      if(forecast.rsi_current > 75.0) // Overbought
      {
         forecast.retracement_probability += 0.35;  // Pullback likely
         forecast.trend_probability *= 0.8;
         forecast.predicted_direction = -1;  // Lean bearish
      }
      else if(forecast.rsi_current < 25.0) // Oversold
      {
         forecast.retracement_probability += 0.35;  // Bounce likely
         forecast.trend_probability *= 0.8;
         forecast.predicted_direction = 1;  // Lean bullish
      }
      else if(forecast.rsi_current < 35.0 || forecast.rsi_current > 65.0)
      {
         // Near extremes but not extreme - continuation likely
         forecast.trend_probability += 0.15;
      }
   }
   
   static void AnalyzeMomentumDirection(string symbol, ENUM_TIMEFRAMES tf,
                                        SRegimeForecast &forecast)
   {
      // Get EMA to measure momentum
      int ema_handle = GetPooledIndicatorHandle(symbol, tf, 20, "EMA");
      if(ema_handle == INVALID_HANDLE)
         return;
      
      const int EMA_COUNT = 6; // current + 5 bars
      double ema_values[];
      ArraySetAsSeries(ema_values, true);
      
      if(CopyBuffer(ema_handle, 0, 0, EMA_COUNT, ema_values) != EMA_COUNT)
         return;
      
      // Calculate EMA slope (normalized)
      double ema_current = ema_values[0];
      double ema_5bars_ago = ema_values[5];
      double slope_raw = (ema_current - ema_5bars_ago);
      double atr = GetATRValue(symbol, tf, 14);
      if(atr <= 0.0 || !MathIsValidNumber(atr))
         atr = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double slope_norm = SafeDiv(slope_raw, atr, slope_raw);
      
      forecast.momentum_direction = slope_norm;
      
      // Price vs EMA
      double close_current = iClose(symbol, tf, 0);
      
      if(close_current > ema_current && forecast.momentum_direction > 0.15)
      {
         // Bullish: price above EMA and EMA rising
         forecast.trend_probability += 0.25;
         forecast.predicted_direction = 1;
      }
      else if(close_current < ema_current && forecast.momentum_direction < -0.15)
      {
         // Bearish: price below EMA and EMA falling
         forecast.trend_probability += 0.25;
         forecast.predicted_direction = -1;
      }
      else if(MathAbs(forecast.momentum_direction) < 0.03)
      {
         // Flat EMA = Range environment
         forecast.range_probability += 0.2;
      }
   }
   
   static void DeterminePrimaryRegime(SRegimeForecast &forecast)
   {
      if(forecast.trend_probability >= 0.40)
      {
         forecast.predicted_regime = "TREND";
         forecast.confidence = forecast.trend_probability;
      }
      else if(forecast.range_probability >= 0.40)
      {
         forecast.predicted_regime = "RANGE";
         forecast.confidence = forecast.range_probability;
      }
      else if(forecast.retracement_probability >= 0.35)
      {
         forecast.predicted_regime = "RETRACEMENT";
         forecast.confidence = forecast.retracement_probability;
      }
      else
      {
         forecast.predicted_regime = "NEUTRAL";
         forecast.confidence = 0.33;
      }
   }
};

//====================================================================
// VOLATILITY FORECAST
// Predicts volatility expansion/contraction over next 5 bars
// Uses ATR clustering and historical volatility patterns
//====================================================================

struct SVolatilityForecast
{
   double current_volatility;     // Current ATR-derived volatility
   double predicted_volatility;   // Predicted volatility 5 bars ahead
   double volatility_change_ratio;// predicted / current
   double vol_spike_likelihood;   // 0-1 probability of vol spike
   
   // Session expectations
   double session_expected_vol;   // Typical vol for current session
   double vol_surprise_factor;    // current vs expected
   
   // Clustering signals
   bool is_clustering;            // Recent bars show clustering
   double clustering_strength;    // Intensity of clustering (1.0-3.0+)
   
   // Recommendation
   string vol_recommendation;     // "CALM|NORMAL|ELEVATED|SPIKE"
   double position_size_adjustment;  // 0.5 (calm) to 1.5 (spike warning)
   
   SVolatilityForecast() :
      current_volatility(0.0),
      predicted_volatility(0.0),
      volatility_change_ratio(1.0),
      vol_spike_likelihood(0.0),
      session_expected_vol(0.0),
      vol_surprise_factor(1.0),
      is_clustering(false),
      clustering_strength(1.0),
      vol_recommendation("NORMAL"),
      position_size_adjustment(1.0) {}
};

class CVolatilityForecaster
{
public:
   static SVolatilityForecast PredictVolatility(string symbol, ENUM_TIMEFRAMES tf)
   {
      SVolatilityForecast forecast;
      
      // Get current ATR
      forecast.current_volatility = GetATRValue(symbol, tf, 14);
      if(forecast.current_volatility <= 0.0)
         return forecast;
      
      // FACTOR 1: Volatility Clustering Detection
      DetectVolatilityClustering(symbol, tf, forecast);
      
      // FACTOR 2: Historical Session Expectations
      GetSessionVolatilityExpectations(forecast);
      
      // FACTOR 3: Mean Reversion Prediction
      PredictMeanReversion(forecast);
      
      // DETERMINE RECOMMENDATION
      DetermineVolatilityRecommendation(forecast);
      
      return forecast;
   }
   
private:
   static void DetectVolatilityClustering(string symbol, ENUM_TIMEFRAMES tf,
                                          SVolatilityForecast &forecast)
   {
      int atr_handle = GetPooledIndicatorHandle(symbol, tf, 14, "ATR");
      if(atr_handle == INVALID_HANDLE)
         return;
      
      const int ATR_COUNT = 21; // current + 20 bars
      double atr_vals[];
      ArraySetAsSeries(atr_vals, true);
      if(CopyBuffer(atr_handle, 0, 0, ATR_COUNT, atr_vals) != ATR_COUNT)
         return;
      
      if(!MathIsValidNumber(atr_vals[0]) || atr_vals[0] <= 0.0)
         return;
      
      forecast.current_volatility = atr_vals[0];
      
      // Average of recent 3 bars (including current)
      double atr_recent_sum = 0.0;
      int recent_count = 0;
      for(int i = 0; i < 3; i++)
      {
         if(MathIsValidNumber(atr_vals[i]) && atr_vals[i] > 0.0)
         {
            atr_recent_sum += atr_vals[i];
            recent_count++;
         }
      }
      double atr_recent_avg = (recent_count > 0 ? (atr_recent_sum / recent_count) : forecast.current_volatility);
      
      // Long-term average (exclude current bar)
      double atr_long_sum = 0.0;
      int long_count = 0;
      for(int i = 1; i < ATR_COUNT; i++)
      {
         if(MathIsValidNumber(atr_vals[i]) && atr_vals[i] > 0.0)
         {
            atr_long_sum += atr_vals[i];
            long_count++;
         }
      }
      double atr_long_avg = (long_count > 0 ? (atr_long_sum / long_count) : forecast.current_volatility);
      
      // Clustering strength
      forecast.clustering_strength = SafeDiv(atr_recent_avg, atr_long_avg, 1.0);
      
      // Is volatility clustering?
      forecast.is_clustering = (forecast.clustering_strength > 1.25);
      
      // If clustering: expect decay (mean reversion)
      // If calm: expect potential spike
      if(forecast.is_clustering)
      {
         forecast.predicted_volatility = atr_recent_avg * 0.92;  // Decay
         forecast.volatility_change_ratio = SafeDiv(forecast.predicted_volatility, forecast.current_volatility, 1.0);
         forecast.vol_spike_likelihood = 0.2;
      }
      else
      {
         forecast.predicted_volatility = atr_long_avg * 1.08;  // Slight increase
         forecast.volatility_change_ratio = SafeDiv(forecast.predicted_volatility, forecast.current_volatility, 1.0);
         forecast.vol_spike_likelihood = 0.4;
      }
   }
   
   static void GetSessionVolatilityExpectations(SVolatilityForecast &forecast)
   {
      // Extract hour from current timestamp (Unix time: seconds / 3600, modulo 24)
      int hour = (int)((TimeCurrent() / 3600) % 24);
      
      // Historical volatility patterns (empirical averages)
      if(hour >= 0 && hour < 8) // Asian
      {
         forecast.session_expected_vol = forecast.current_volatility * 0.80;
      }
      else if(hour >= 8 && hour < 14) // European
      {
         forecast.session_expected_vol = forecast.current_volatility * 1.20;
      }
      else if(hour >= 14 && hour < 20) // US
      {
         forecast.session_expected_vol = forecast.current_volatility * 1.40;
      }
      else // Off-hours
      {
         forecast.session_expected_vol = forecast.current_volatility * 0.60;
      }
      
      forecast.vol_surprise_factor = SafeDiv(forecast.current_volatility,
                                             forecast.session_expected_vol, 1.0);
   }
   
   static void PredictMeanReversion(SVolatilityForecast &forecast)
   {
      // If current vol > expected, expect reversion down
      if(forecast.vol_surprise_factor > 1.25)
      {
         forecast.predicted_volatility *= 0.90;  // Revert downward
         forecast.vol_spike_likelihood += 0.15;
      }
      else if(forecast.vol_surprise_factor < 0.75)
      {
         forecast.predicted_volatility *= 1.15;  // Revert upward
         forecast.vol_spike_likelihood += 0.25;
      }
   }
   
   static void DetermineVolatilityRecommendation(SVolatilityForecast &forecast)
   {
      if(forecast.vol_spike_likelihood > 0.65)
      {
         forecast.vol_recommendation = "SPIKE_WARNING";
         forecast.position_size_adjustment = 0.65;  // Reduce size 35%
      }
      else if(forecast.vol_spike_likelihood > 0.50)
      {
         forecast.vol_recommendation = "ELEVATED";
         forecast.position_size_adjustment = 0.80;  // Reduce size 20%
      }
      else if(forecast.current_volatility < forecast.session_expected_vol * 0.75)
      {
         forecast.vol_recommendation = "CALM";
         forecast.position_size_adjustment = 1.15; // Increase size 15%
      }
      else
      {
         forecast.vol_recommendation = "NORMAL";
         forecast.position_size_adjustment = 1.0;
      }
   }
};

#endif // FORWARD_INTELLIGENCE_MQH
