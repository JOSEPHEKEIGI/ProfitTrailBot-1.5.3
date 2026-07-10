//+------------------------------------------------------------------+
//|                 TrendAnalysisIntegration.mqh                      |
//|     Adapter Layer to Integrate Enhanced Trend into Existing Code   |
//|                   Copyright 2026, ProfitTrailBot Ltd.             |
//+------------------------------------------------------------------+

#ifndef TREND_ANALYSIS_INTEGRATION_MQH
#define TREND_ANALYSIS_INTEGRATION_MQH

#include "TrendAnalysisEnhanced.mqh"

//====================================================================
// INSTITUTIONAL TREND-AWARE BIAS CALCULATION
//====================================================================

// Enhanced replacement for GetHTFBias() with institutional grading
int GetHTFBiasInstitutional(string symbol)
{
   if(StringLen(symbol) <= 0)
      return 0;
   
   // Get fresh analysis from each timeframe
   STrendAnalysis primary_trend = CTrendAnalysisEnhanced::AnalyzeTrendInstitutional(symbol, Primary_TF);
   STrendAnalysis confirm_trend = CTrendAnalysisEnhanced::AnalyzeTrendInstitutional(symbol, Confirm_TF);
   STrendAnalysis trend_tf_trend = CTrendAnalysisEnhanced::AnalyzeTrendInstitutional(symbol, Trend_TF);
   
   // Confluence-based logic (institutional)
   double bullish_count = 0, bearish_count = 0;
   
   // Weight by strength and phase
   double primary_weight = 2.0 * (primary_trend.strength / 100.0);
   double confirm_weight = 2.0 * (confirm_trend.strength / 100.0);
   double trend_weight = 3.0 * (trend_tf_trend.strength / 100.0);
   
   if(primary_trend.direction == TREND_BULLISH && primary_trend.strength >= 40.0)
      bullish_count += primary_weight;
   else if(primary_trend.direction == TREND_BEARISH && primary_trend.strength >= 40.0)
      bearish_count += primary_weight;
   
   if(confirm_trend.direction == TREND_BULLISH && confirm_trend.strength >= 40.0)
      bullish_count += confirm_weight;
   else if(confirm_trend.direction == TREND_BEARISH && confirm_trend.strength >= 40.0)
      bearish_count += confirm_weight;
   
   if(trend_tf_trend.direction == TREND_BULLISH && trend_tf_trend.strength >= 35.0)
      bullish_count += trend_weight;
   else if(trend_tf_trend.direction == TREND_BEARISH && trend_tf_trend.strength >= 35.0)
      bearish_count += trend_weight;
   
   // Determine bias with consensus check for false weak alignment
   double net = bullish_count - bearish_count;
   
   if(bullish_count > bearish_count && net >= 1.5)
      return 1; // Bullish
   else if(bearish_count > bullish_count && net <= -1.5)
      return -1; // Bearish
   else if(MathAbs(net) >= 1.0)
   {
      // CRITICAL FIX #1: Check for false weak alignment from conflicting strong signals
      // Prevents conflicting strong components (e.g., 60% bullish + 60% bearish) from masquerading as weak alignment
      // C4 FIX: Tighten threshold to 55% to catch softer conflicts (was: >= 60.0)
      int strong_bullish = 0, strong_bearish = 0;
      if(primary_trend.direction == TREND_BULLISH && primary_trend.strength >= 55.0) strong_bullish++;
      if(primary_trend.direction == TREND_BEARISH && primary_trend.strength >= 55.0) strong_bearish++;
      if(confirm_trend.direction == TREND_BULLISH && confirm_trend.strength >= 55.0) strong_bullish++;
      if(confirm_trend.direction == TREND_BEARISH && confirm_trend.strength >= 55.0) strong_bearish++;
      if(trend_tf_trend.direction == TREND_BULLISH && trend_tf_trend.strength >= 55.0) strong_bullish++;
      if(trend_tf_trend.direction == TREND_BEARISH && trend_tf_trend.strength >= 55.0) strong_bearish++;
      
      // If strong signals conflict, return neutral instead of weak alignment
      if(strong_bullish > 0 && strong_bearish > 0)
         return 0;
      
      return (net > 0 ? 1 : -1); // Weak alignment (no conflicting strong signals)
   }
   
   return 0; // Neutral
}

// Get trend strength score (0-100) instead of -7 to +7
double GetHTFBiasStrengthInstitutional(string symbol)
{
   if(StringLen(symbol) <= 0)
      return 0.0;
   
   STrendAnalysis primary_trend = CTrendAnalysisEnhanced::AnalyzeTrendInstitutional(symbol, Primary_TF);
   STrendAnalysis confirm_trend = CTrendAnalysisEnhanced::AnalyzeTrendInstitutional(symbol, Confirm_TF);
   STrendAnalysis trend_tf_trend = CTrendAnalysisEnhanced::AnalyzeTrendInstitutional(symbol, Trend_TF);
   
   // Weighted average strength
   double total_strength = (primary_trend.strength * 2.0 + 
                           confirm_trend.strength * 2.0 + 
                           trend_tf_trend.strength * 3.0) / 7.0;
   
   return total_strength;
}

//====================================================================
// INSTITUTIONAL TREND PHASE INFORMATION
//====================================================================

// Get the dominant trend phase across all timeframes
ENUM_TREND_PHASE GetDominantTrendPhase(string symbol)
{
   STrendAnalysis primary_trend = CTrendAnalysisEnhanced::AnalyzeTrendInstitutional(symbol, Primary_TF);
   STrendAnalysis confirm_trend = CTrendAnalysisEnhanced::AnalyzeTrendInstitutional(symbol, Confirm_TF);
   STrendAnalysis trend_tf_trend = CTrendAnalysisEnhanced::AnalyzeTrendInstitutional(symbol, Trend_TF);
   
   // Weight by timeframe and strength
   double initiation_score = 0.0, development_score = 0.0, exhaustion_score = 0.0, reversal_score = 0.0;
   
   struct SPhaseWeight { ENUM_TREND_PHASE phase; double weight; };
   SPhaseWeight phases[3] = {
      {primary_trend.phase, 2.0 * (primary_trend.strength / 100.0)},
      {confirm_trend.phase, 2.0 * (confirm_trend.strength / 100.0)},
      {trend_tf_trend.phase, 3.0 * (trend_tf_trend.strength / 100.0)}
   };
   
   for(int i = 0; i < 3; i++)
   {
      switch(phases[i].phase)
      {
         case TREND_PHASE_INITIATION:
            initiation_score += phases[i].weight;
            break;
         case TREND_PHASE_DEVELOPMENT:
            development_score += phases[i].weight;
            break;
         case TREND_PHASE_EXHAUSTION:
            exhaustion_score += phases[i].weight;
            break;
         case TREND_PHASE_REVERSAL:
            reversal_score += phases[i].weight;
            break;
      }
   }
   
   // Find highest score
   double max_score = MathMax(initiation_score, 
                             MathMax(development_score, 
                                    MathMax(exhaustion_score, reversal_score)));
   
   if(max_score <= 0.0)
      return TREND_PHASE_NONE;
   else if(initiation_score == max_score)
      return TREND_PHASE_INITIATION;
   else if(development_score == max_score)
      return TREND_PHASE_DEVELOPMENT;
   else if(exhaustion_score == max_score)
      return TREND_PHASE_EXHAUSTION;
   else
      return TREND_PHASE_REVERSAL;
}

// Get trend sustainability score across timeframes (0-100)
double GetTrendSustainabilityInstitutional(string symbol)
{
   STrendAnalysis primary_trend = CTrendAnalysisEnhanced::AnalyzeTrendInstitutional(symbol, Primary_TF);
   STrendAnalysis confirm_trend = CTrendAnalysisEnhanced::AnalyzeTrendInstitutional(symbol, Confirm_TF);
   STrendAnalysis trend_tf_trend = CTrendAnalysisEnhanced::AnalyzeTrendInstitutional(symbol, Trend_TF);
   
   // Weighted sustainability
   double sustainability = (primary_trend.sustainability_score * 2.0 +
                           confirm_trend.sustainability_score * 2.0 +
                           trend_tf_trend.sustainability_score * 3.0) / 7.0;
   
   return sustainability;
}

//====================================================================
// INSTITUTIONAL CONFLUENCE DETECTION
//====================================================================

// Build confluence matrix for trading decisions
STrendConfluence GetTrendConfluenceInstitutional(string symbol, int direction)
{
   STrendConfluence result;
   result.confluence_count = 0;
   result.confluence_score = 0.0;
   result.meets_minimum = false;
   
   STrendAnalysis signal_trend = CTrendAnalysisEnhanced::AnalyzeTrendInstitutional(symbol, Signal_TF);
   STrendAnalysis primary_trend = CTrendAnalysisEnhanced::AnalyzeTrendInstitutional(symbol, Primary_TF);
   STrendAnalysis confirm_trend = CTrendAnalysisEnhanced::AnalyzeTrendInstitutional(symbol, Confirm_TF);
   STrendAnalysis trend_tf_trend = CTrendAnalysisEnhanced::AnalyzeTrendInstitutional(symbol, Trend_TF);
   
   // Check each component
   // 1. SMA alignment across the board
   double avg_sma_strength = (signal_trend.sma_score + primary_trend.sma_score + 
                             confirm_trend.sma_score + trend_tf_trend.sma_score) / 4.0;
   result.sma_aligned = (avg_sma_strength >= 55.0);
   if(result.sma_aligned) result.confluence_count++;
   
   // 2. Momentum alignment
   double avg_momentum = (signal_trend.momentum_score + primary_trend.momentum_score + 
                         confirm_trend.momentum_score + trend_tf_trend.momentum_score) / 4.0;
   result.momentum_aligned = (avg_momentum >= 50.0 && MathAbs(signal_trend.momentum_score - primary_trend.momentum_score) < 20.0);
   if(result.momentum_aligned) result.confluence_count++;
   
   // 3. Oscillator alignment
   double avg_osc = (signal_trend.oscillator_score + primary_trend.oscillator_score + 
                    confirm_trend.oscillator_score + trend_tf_trend.oscillator_score) / 4.0;
   result.oscillator_aligned = (avg_osc >= 50.0);
   if(result.oscillator_aligned) result.confluence_count++;
   
   // 4. Volatility support
   double avg_vol_factor = (signal_trend.volatility_factor + primary_trend.volatility_factor + 
                           confirm_trend.volatility_factor + trend_tf_trend.volatility_factor) / 4.0;
   result.volatility_aligned = (avg_vol_factor >= 0.8 && avg_vol_factor <= 1.5);
   if(result.volatility_aligned) result.confluence_count++;
   
   // Calculate confluence score
   result.confluence_score = (result.confluence_count / 4.0) * 100.0;
   
   // Institutional minimum: 3+ factors aligned with 70+ score
   result.meets_minimum = (result.confluence_count >= 3 && result.confluence_score >= 70.0);
   
   return result;
}

//====================================================================
// COMPATIBILITY ADAPTERS (Backward Compatibility)
//====================================================================

// Adapter to use enhanced trend in scoring engine
// Call this in ScoringEngine calculations
double GetHTFTrendStrengthScore(string symbol)
{
   // Returns -100 to +100 scale for compatibility
   double strength = GetHTFBiasStrengthInstitutional(symbol);
   int bias = GetHTFBiasInstitutional(symbol);
   
   if(bias == 0)
      return 0.0;
   
   return (double)bias * strength;
}

// Enhanced trend validation for signal generation
bool IsTrendInstitutionallyValid(string symbol, int direction)
{
   STrendConfluence confluence = GetTrendConfluenceInstitutional(symbol, direction);
   
   if(!confluence.meets_minimum)
      return false;
   
   ENUM_TREND_PHASE phase = GetDominantTrendPhase(symbol);
   
   // Reject reversal phase unless explicitly configured
   if(phase == TREND_PHASE_REVERSAL)
      return false;
   
   return confluence.meets_minimum;
}

//====================================================================
// LOGGING & DIAGNOSTICS
//====================================================================

void LogTrendAnalysis(string symbol, ENUM_TIMEFRAMES tf, const STrendAnalysis &analysis)
{
   if(!Enable_Institutional_Debug)
      return;
   
   string phase_str = "";
   switch(analysis.phase)
   {
      case TREND_PHASE_INITIATION: phase_str = "INIT"; break;
      case TREND_PHASE_DEVELOPMENT: phase_str = "DEV"; break;
      case TREND_PHASE_EXHAUSTION: phase_str = "EXH"; break;
      case TREND_PHASE_REVERSAL: phase_str = "REV"; break;
      default: phase_str = "NONE";
   }
   
   string direction_str = (analysis.direction == TREND_BULLISH ? "BULL" : 
                          analysis.direction == TREND_BEARISH ? "BEAR" : "NEUT");
   
   Log(LOG_DEBUG, "TrendAnalysisEnhanced", 
       StringFormat("%s,%s: dir=%s phase=%s str=%.1f sma=%.1f mom=%.1f osc=%.1f sus=%.1f vf=%.2f bars=%d",
                   symbol, EnumToString(tf), direction_str, phase_str,
                   analysis.strength, analysis.sma_score, analysis.momentum_score,
                   analysis.oscillator_score, analysis.sustainability_score,
                   analysis.volatility_factor, analysis.bars_in_trend));
}

void LogTrendConfluence(string symbol, int direction, const STrendConfluence &confluence)
{
   if(!Enable_Institutional_Debug)
      return;
   
   Log(LOG_DEBUG, "TrendConfluence",
       StringFormat("%s (dir=%d): sma=%s mom=%s osc=%s vol=%s | count=%d score=%.1f valid=%s",
                   symbol, direction,
                   (confluence.sma_aligned ? "Y" : "N"),
                   (confluence.momentum_aligned ? "Y" : "N"),
                   (confluence.oscillator_aligned ? "Y" : "N"),
                   (confluence.volatility_aligned ? "Y" : "N"),
                   confluence.confluence_count, confluence.confluence_score,
                   (confluence.meets_minimum ? "YES" : "NO")));
}

#endif // TREND_ANALYSIS_INTEGRATION_MQH
