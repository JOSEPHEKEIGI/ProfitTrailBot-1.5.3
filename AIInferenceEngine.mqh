#ifndef AI_INFERENCE_ENGINE_MQH
#define AI_INFERENCE_ENGINE_MQH

//+------------------------------------------------------------------+
//|                                          AIInferenceEngine.mqh |
//|                        Copyright 2024, ProfitTrailBot Ltd.      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, ProfitTrailBot Ltd."
#property strict

// AI Inference Engine Class
class AIInferenceEngine
{
private:
   static double buy_threshold;
   static double sell_threshold;
   
public:
   static void SetThresholds(double buy_thresh = 0.6, double sell_thresh = 0.4)
   {
      buy_threshold = buy_thresh;
      sell_threshold = sell_thresh;
   }
   
   static int Decide(double probability)
   {
      if(probability > buy_threshold) return 1;   // BUY
      if(probability < sell_threshold) return -1; // SELL
      return 0; // Neutral
   }
   
   static double GetConfidence(double probability)
   {
      // FIX #11: Validate input is finite before processing
      if(!MathIsValidNumber(probability))
         return 0.0;
      
      // Clamp probability to valid range [0, 1]
      probability = MathMax(0.0, MathMin(1.0, probability));
      
      // Distance from neutral (0.5), normalized to [0, 1]
      double distance = MathAbs(probability - 0.5) * 2.0;
      
      // Apply smooth Hermite interpolation curve for confidence
      // Formula: distance^2 * (3 - 2*distance)
      // This ensures: confidence(0.5)=0, confidence(0/1)=1, with smooth S-curve
      double confidence = distance * distance * (3.0 - 2.0 * distance);
      
      return MathMin(1.0, confidence); // Clamp to [0, 1] (defensive)
   }
   
   // Enhanced AI Decision Making with consistent thresholds
   static int MakeEnhancedDecision(double probability, double confidence_threshold = 0.3)
   {
      double confidence = GetConfidence(probability);
      
      if(confidence < confidence_threshold)
         return 0; // Not confident enough
         
      // Use same thresholds as Decide() for consistency
      return Decide(probability);
   }
   
   // AI Signal Validation
   static bool ValidateAISignal(double probability, double min_confidence = 0.2)
   {
      double confidence = GetConfidence(probability);
      return confidence >= min_confidence;
   }
   
   // Get AI Signal Strength
   static string GetSignalStrength(double probability)
   {
      double confidence = GetConfidence(probability);
      
      if(confidence >= 0.8) return "VERY_HIGH";
      if(confidence >= 0.6) return "HIGH";
      if(confidence >= 0.4) return "MEDIUM";
      if(confidence >= 0.2) return "LOW";
      return "VERY_LOW";
   }
};

// Static variable definitions
double AIInferenceEngine::buy_threshold = 0.6;
double AIInferenceEngine::sell_threshold = 0.4;

#endif // AI_INFERENCE_ENGINE_MQH
