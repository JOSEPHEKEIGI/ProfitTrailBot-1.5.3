//+------------------------------------------------------------------+
//|                            DynamicScoringWeights.mqh             |
//|         Dynamic Weight Adjustment by Market Regime                |
//|                        Copyright 2026, ProfitTrailBot Ltd.       |
//|                                                                  |
//| TIER 3: Dynamically reweight scoring factors based on regime     |
//+------------------------------------------------------------------+

#ifndef DYNAMIC_SCORING_WEIGHTS_MQH
#define DYNAMIC_SCORING_WEIGHTS_MQH

#property copyright "Copyright 2026, ProfitTrailBot Ltd."
#property strict

// Forward declarations
string AutoRegimeModeToString(int mode);
int DetectMarketRegime(string symbol, ENUM_TIMEFRAMES tf);
double GetATRValue(string symbol, ENUM_TIMEFRAMES tf, int atr_period = 0);
double GetRSIValue(string symbol, ENUM_TIMEFRAMES tf, int period);

//====================================================================
// DYNAMIC REGIME-BASED WEIGHT ADJUSTMENT
// Reweights scoring factors based on detected market regime:
// TREND: Emphasize momentum + trend alignment
// RANGE: Emphasize structure + reversal + divergence
// RETRACEMENT: Emphasize structure breaks + exhaustion
//====================================================================

struct SDynamicWeights
{
   // Original weights
   double weight_trend;
   double weight_momentum;
   double weight_volatility;
   double weight_structure;
   double weight_alignment;
   double weight_confirmation;
   double weight_risk_reward;
   double weight_entry_quality;
   double weight_spread;
   double weight_regime;
   
   // Context
   int detected_regime;      // TREND / RANGE / RETRACEMENT
   double confidence_regime; // How confident in regime (0-1)
   
   // Adjustments applied
   bool weights_adjusted;
   string adjustment_reason;
   
   SDynamicWeights() :
      weight_trend(0.15),
      weight_momentum(0.12),
      weight_volatility(0.10),
      weight_structure(0.18),
      weight_alignment(0.10),
      weight_confirmation(0.08),
      weight_risk_reward(0.12),
      weight_entry_quality(0.08),
      weight_spread(0.05),
      weight_regime(0.02),
      detected_regime(2),      // Default: RANGE
      confidence_regime(0.0),
      weights_adjusted(false),
      adjustment_reason("") {}
};

class CDynamicWeightAdjuster
{
public:
   // Main entry: Get regime-adjusted weights
   static SDynamicWeights GetAdjustedWeights(string symbol, ENUM_TIMEFRAMES tf_signal,
                                            ENUM_TIMEFRAMES tf_primary, ENUM_TIMEFRAMES tf_confirm)
   {
      SDynamicWeights weights;
      
      // Detect current regime (use primary TF for regime detection)
      weights.detected_regime = DetectMarketRegime(symbol, tf_primary);
      
      // Start with baseline weights
      weights.weight_trend = 0.15;
      weights.weight_momentum = 0.12;
      weights.weight_volatility = 0.10;
      weights.weight_structure = 0.18;
      weights.weight_alignment = 0.10;
      weights.weight_confirmation = 0.08;
      weights.weight_risk_reward = 0.12;
      weights.weight_entry_quality = 0.08;
      weights.weight_spread = 0.05;
      weights.weight_regime = 0.02;
      
      // APPLY REGIME-SPECIFIC ADJUSTMENTS
      if(weights.detected_regime == 0) // TREND mode
      {
         // In trend: prioritize momentum continuation
         weights.weight_trend = 0.22;        // +7% (trend is happening)
         weights.weight_momentum = 0.18;     // +6% (momentum confirms trend)
         weights.weight_alignment = 0.14;    // +4% (HTF alignment matters)
         weights.weight_structure = 0.12;    // -6% (less critical in trend)
         weights.weight_volatility = 0.08;   // -2% (managed by trend)
         weights.weight_confirmation = 0.05; // -3%
         
         weights.confidence_regime = 0.75;
         weights.adjustment_reason = "TREND: Emphasize momentum & continuation";
         weights.weights_adjusted = true;
      }
      else if(weights.detected_regime == 1) // RANGE mode
      {
         // In range: prioritize structure reversals
         weights.weight_structure = 0.28;    // +10% (range boundaries critical)
         weights.weight_momentum = 0.08;     // -4% (momentum less reliable)
         weights.weight_trend = 0.08;        // -7% (no trend)
         weights.weight_confirmation = 0.12; // +4% (need confirmation in range)
         weights.weight_risk_reward = 0.10;  // -2%
         weights.weight_volatility = 0.12;   // +2% (watch for squeeze breaks)
         
         weights.confidence_regime = 0.70;
         weights.adjustment_reason = "RANGE: Emphasize structure & confirmation";
         weights.weights_adjusted = true;
      }
      else if(weights.detected_regime == 2) // RETRACEMENT mode
      {
         // In retracement: balance structure + momentum
         weights.weight_structure = 0.20;    // +2%
         weights.weight_momentum = 0.16;     // +4% (retracement is momentum reversal)
         weights.weight_alignment = 0.12;    // +2% (HTF direction matters)
         weights.weight_confirmation = 0.10; // +2%
         weights.weight_volatility = 0.12;   // +2%
         weights.weight_trend = 0.12;        // -3%
         
         weights.confidence_regime = 0.65;
         weights.adjustment_reason = "RETRACEMENT: Balance structure & momentum";
         weights.weights_adjusted = true;
      }
      
      // NORMALIZE weights to sum to 1.0
      double sum = weights.weight_trend + weights.weight_momentum + 
                   weights.weight_volatility + weights.weight_structure + 
                   weights.weight_alignment + weights.weight_confirmation + 
                   weights.weight_risk_reward + weights.weight_entry_quality + 
                   weights.weight_spread + weights.weight_regime;
      
      if(sum > 0.0)
      {
         weights.weight_trend /= sum;
         weights.weight_momentum /= sum;
         weights.weight_volatility /= sum;
         weights.weight_structure /= sum;
         weights.weight_alignment /= sum;
         weights.weight_confirmation /= sum;
         weights.weight_risk_reward /= sum;
         weights.weight_entry_quality /= sum;
         weights.weight_spread /= sum;
         weights.weight_regime /= sum;
      }
      
      return weights;
   }
};

#endif // DYNAMIC_SCORING_WEIGHTS_MQH
