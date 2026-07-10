//+------------------------------------------------------------------+
//|                                ConfidenceFusionRouter.mqh        |
//|              Signal Confidence Integration & Temporal Decay      |
//|                        Copyright 2026, ProfitTrailBot Ltd.       |
//|                                                                  |
//| TIER 1: Blend signal confidence into strategy routing & decay   |
//+------------------------------------------------------------------+

#ifndef CONFIDENCE_FUSION_ROUTER_MQH
#define CONFIDENCE_FUSION_ROUTER_MQH

#property copyright "Copyright 2026, ProfitTrailBot Ltd."
#property strict

// Forward declarations
double SafeDiv(double num, double denom, double fallback = 0.0);

//====================================================================
// TEMPORAL CONFIDENCE DECAY SYSTEM
// Signals lose relevance over time. This module applies exponential
// decay to signal confidence based on time since signal generation.
//====================================================================

struct SSignalTimestamp
{
   datetime generation_time;      // When signal was first identified
   datetime confirmation_time;    // When signal was confirmed/validated
   int      timeframe;            // Timeframe of original signal
   int      signal_shift;         // Bar shift at time of generation
   bool     is_valid;             // Flag if signal still applicable
};

struct SSignalDecayMetrics
{
   int bars_since_generation;     // Bars elapsed since signal created
   int bars_since_confirmation;   // Bars elapsed since confirmation
   double decay_factor;           // 1.0 (fresh) to 0.1 (stale)
   double freshness_confidence;   // Multiplication factor for confidence
   bool is_expired;               // True if signal too old to use
   string decay_curve_position;   // Debug: "FRESH"|"RECENT"|"MEDIUM"|"OLD"|"EXPIRED"
   
   SSignalDecayMetrics() :
      bars_since_generation(0),
      bars_since_confirmation(0),
      decay_factor(1.0),
      freshness_confidence(1.0),
      is_expired(false),
      decay_curve_position("") {}
};

class CTemporalSignalDecay
{
private:
   // Decay curve constants (hardcoded to avoid static array initialization issues)
   // 0 bars:   100% retention (factor = 1.0)
   // 5 bars:   90% retention
   // 15 bars:  70% retention
   // 30 bars:  45% retention
   // 60+ bars: 0% retention (expired)
   #define MAX_SIGNAL_AGE_BARS 60
   
public:
   // Calculate temporal decay for a signal
   static SSignalDecayMetrics CalculateDecay(const SSignalTimestamp &sig_time,
                                             datetime current_time,
                                             ENUM_TIMEFRAMES tf)
   {
      SSignalDecayMetrics decay_metrics;
      
      if(!sig_time.is_valid || sig_time.generation_time <= 0)
      {
         decay_metrics.is_expired = true;
         decay_metrics.decay_factor = 0.0;
         decay_metrics.freshness_confidence = 0.1;
         decay_metrics.decay_curve_position = "INVALID";
         return decay_metrics;
      }
      
      // Convert time difference to bars
      int tf_seconds = PeriodSeconds(tf);
      if(tf_seconds <= 0)
         tf_seconds = 300;  // Default to 5M if unknown
      
      int seconds_elapsed = (int)(current_time - sig_time.generation_time);
      if(seconds_elapsed < 0)
      {
         Log(LOG_WARNING, "TemporalDecay", "Signal time in future!");
         decay_metrics.is_expired = true;
         decay_metrics.decay_factor = 0.0;
         return decay_metrics;
      }
      
      decay_metrics.bars_since_generation = seconds_elapsed / tf_seconds;
      
      // Similar calculation for confirmation time
      if(sig_time.confirmation_time > sig_time.generation_time)
      {
         int confirm_seconds = (int)(current_time - sig_time.confirmation_time);
         decay_metrics.bars_since_confirmation = confirm_seconds / tf_seconds;
      }
      else
      {
         decay_metrics.bars_since_confirmation = 
            decay_metrics.bars_since_generation;
      }
      
      // APPLY EXPONENTIAL DECAY CURVE
      // Use interpolation between curve points for smooth decay
      int bars = decay_metrics.bars_since_generation;
      
      if(bars >= MAX_SIGNAL_AGE_BARS)
      {
         decay_metrics.decay_factor = 0.0;
         decay_metrics.is_expired = true;
         decay_metrics.freshness_confidence = 0.0;
         decay_metrics.decay_curve_position = "EXPIRED";
      }
      else if(bars <= 0)
      {
         decay_metrics.decay_factor = 1.0;
         decay_metrics.freshness_confidence = 1.0;
         decay_metrics.decay_curve_position = "FRESH";
      }
      else if(bars <= 5)
      {
         // Linear interpolation between 0-5 bars
         decay_metrics.decay_factor = 1.0 - (bars / 5.0) * (1.0 - 0.90);
         decay_metrics.freshness_confidence = decay_metrics.decay_factor;
         decay_metrics.decay_curve_position = "RECENT";
      }
      else if(bars <= 15)
      {
         // Interpolate between 5-15 bars (0.90 to 0.70)
         double alpha = (bars - 5.0) / 10.0;
         decay_metrics.decay_factor = 0.90 - (alpha * 0.20);
         decay_metrics.freshness_confidence = decay_metrics.decay_factor;
         decay_metrics.decay_curve_position = "MEDIUM";
      }
      else if(bars <= 30)
      {
         // Interpolate between 15-30 bars (0.70 to 0.45)
         double alpha = (bars - 15.0) / 15.0;
         decay_metrics.decay_factor = 0.70 - (alpha * 0.25);
         decay_metrics.freshness_confidence = decay_metrics.decay_factor;
         decay_metrics.decay_curve_position = "OLD";
      }
      else // 30-60 bars (0.45 to 0.0)
      {
         // Interpolate between 30-60 bars
         double alpha = (bars - 30.0) / 30.0;
         decay_metrics.decay_factor = 0.45 - (alpha * 0.45);
         decay_metrics.freshness_confidence = MathMax(0.0, decay_metrics.decay_factor);
         decay_metrics.decay_curve_position = "STALE";
      }
      
      return decay_metrics;
   }
   
   // Apply decay to signal confidence
   static double ApplyDecayToConfidence(double original_confidence,
                                        const SSignalDecayMetrics &decay_metrics)
   {
      if(decay_metrics.is_expired)
         return original_confidence * 0.1;  // Drastically reduce expired signals
      
      return original_confidence * decay_metrics.decay_factor;
   }
};

//====================================================================
// CONFIDENCE-WEIGHTED ROUTING
// Routes trade signals to more/less aggressive execution based on
// combined confidence from multiple strategy sources.
//====================================================================

struct SConfidenceWeightedRoute
{
   bool execute_signal;           // Execute trade?
   double execution_confidence;   // 0-1 composite confidence
   double lot_size_multiplier;    // 0.5 (weak) to 1.5 (strong)
   double stop_loss_distance_multiplier;  // 0.8 (tight) to 1.5 (wide)
   string confidence_source;      // Which signal had highest confidence
   string routing_decision;       // Debug explanation
   
   SConfidenceWeightedRoute() :
      execute_signal(false),
      execution_confidence(0.0),
      lot_size_multiplier(1.0),
      stop_loss_distance_multiplier(1.0),
      confidence_source(""),
      routing_decision("") {}
};

class CConfidenceFusionRouter
{
public:
   // Main entry: Fuse all signal confidences and make routing decision
   static SConfidenceWeightedRoute FuseSignalConfidences(
      bool ict_valid,              // ICT signal available?
      double ict_confidence,       // ICT signal confidence (0-1)
      double ict_temporal_decay,   // Temporal freshness (0-1)
      
      bool ai_valid,               // AI signal available?
      double ai_confidence,        // AI prediction confidence (0-1)
      double ai_temporal_decay,    // Temporal freshness (0-1)
      
      bool kim_valid,              // Kmaniz signal available?
      double kim_confidence,       // Kmaniz confidence (0-1)
      double kim_temporal_decay,   // Temporal freshness (0-1)
      
      bool require_confluence      // Need agreement between strategies?
   )
   {
      SConfidenceWeightedRoute route;

      // Clamp inputs to valid ranges
      ict_confidence = MathMax(0.0, MathMin(1.0, ict_confidence));
      ai_confidence = MathMax(0.0, MathMin(1.0, ai_confidence));
      kim_confidence = MathMax(0.0, MathMin(1.0, kim_confidence));
      ict_temporal_decay = MathMax(0.0, MathMin(1.0, ict_temporal_decay));
      ai_temporal_decay = MathMax(0.0, MathMin(1.0, ai_temporal_decay));
      kim_temporal_decay = MathMax(0.0, MathMin(1.0, kim_temporal_decay));
      
      // FUSION STRATEGY: Weighted average of available signals
      // Weights: ICT=40%, AI=35%, Kmaniz=25%
      
      double weighted_confidence = 0.0;
      double total_weight = 0.0;
      int signals_active = 0;
      
      // ICT component
      if(ict_valid && ict_confidence >= 0.2)
      {
         double ict_fused = ict_confidence * ict_temporal_decay;  // Apply decay
         weighted_confidence += ict_fused * 0.40;
         total_weight += 0.40;
         signals_active++;
      }
      
      // AI component
      if(ai_valid && ai_confidence >= 0.2)
      {
         double ai_fused = ai_confidence * ai_temporal_decay;     // Apply decay
         weighted_confidence += ai_fused * 0.35;
         total_weight += 0.35;
         signals_active++;
      }
      
      // Kmaniz component
      if(kim_valid && kim_confidence >= 0.2)
      {
         double kim_fused = kim_confidence * kim_temporal_decay;  // Apply decay
         weighted_confidence += kim_fused * 0.25;
         total_weight += 0.25;
         signals_active++;
      }
      
      // CONFLUENCE CHECK: If requiring agreement, penalize lonely signals
      if(require_confluence && signals_active < 2)
      {
         weighted_confidence *= 0.5;  // Penalize single-strategy signals
      }
      else if(signals_active >= 2)
      {
         weighted_confidence *= 1.05; // Bonus for multi-signal agreement
      }
      
      // Normalize to 0-1
      if(total_weight > 0.0)
      {
         route.execution_confidence = SafeDiv(weighted_confidence, total_weight, 0.0);
      }
      else
      {
         route.execution_confidence = 0.0;
      }
      
      // Clamp to valid range
      route.execution_confidence = MathMax(0.0, MathMin(1.0, route.execution_confidence));
      
      // DECISION THRESHOLDS
      // Confidence 0.75+:  Execute, normal sizing
      // Confidence 0.55-0.75: Execute, reduced sizing
      // Confidence 0.35-0.55: Execute, minimal sizing (cautious)
      // Confidence <0.35:  Do not execute
      
      if(route.execution_confidence >= 0.75)
      {
         route.execute_signal = true;
         route.lot_size_multiplier = 1.25;      // 25% larger
         route.stop_loss_distance_multiplier = 0.9;  // Tight stop
         route.routing_decision = "HIGH_CONFIDENCE_EXECUTE";
      }
      else if(route.execution_confidence >= 0.55)
      {
         route.execute_signal = true;
         route.lot_size_multiplier = 1.0;       // Normal size
         route.stop_loss_distance_multiplier = 1.0;  // Normal stop
         route.routing_decision = "NORMAL_EXECUTE";
      }
      else if(route.execution_confidence >= 0.35)
      {
         route.execute_signal = true;
         route.lot_size_multiplier = 0.6;       // 40% smaller
         route.stop_loss_distance_multiplier = 1.3;  // Wider stop
         route.routing_decision = "CAUTIOUS_EXECUTE";
      }
      else if(route.execution_confidence >= 0.2)
      {
         route.execute_signal = false;
         route.routing_decision = "BELOW_THRESHOLD_SKIP";
      }
      else
      {
         route.execute_signal = false;
         route.routing_decision = "INSUFFICIENT_SIGNAL";
      }
      
      // Identify which signal had highest confidence
      if(ict_valid && ict_confidence * ict_temporal_decay >= 
         ai_confidence * ai_temporal_decay &&
         ict_confidence * ict_temporal_decay >= kim_confidence * kim_temporal_decay)
         route.confidence_source = "ICT";
      else if(ai_valid && ai_confidence * ai_temporal_decay >= 
         kim_confidence * kim_temporal_decay)
         route.confidence_source = "AI";
      else if(kim_valid)
         route.confidence_source = "KMANIZ";
      else
         route.confidence_source = "NONE";
      
      return route;
   }
};

#endif // CONFIDENCE_FUSION_ROUTER_MQH
