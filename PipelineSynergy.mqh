//+------------------------------------------------------------------+
//|                            PipelineSynergy.mqh                   |
//|          Multi-Source Signal Pipeline Integration & Synergies    |
//+------------------------------------------------------------------+

#ifndef PIPELINE_SYNERGY_MQH
#define PIPELINE_SYNERGY_MQH

struct SStrategySynergyScore
{
   bool ict_valid;
   bool ai_valid;
   bool kim_valid;
   bool reversal_valid;

   double directional_agreement;
   double momentum_agreement;
   double structural_agreement;
   double entry_distance_agreement;

   double momentum_synergy;
   double structure_synergy;
   double volatility_regime_synergy;
   double reversal_structural_synergy;

   double total_synergy_factor;
   double execution_tier;
   string synergy_breakdown;

   SStrategySynergyScore() :
      ict_valid(false),
      ai_valid(false),
      kim_valid(false),
      reversal_valid(false),
      directional_agreement(0.0),
      momentum_agreement(0.0),
      structural_agreement(0.0),
      entry_distance_agreement(0.0),
      momentum_synergy(0.0),
      structure_synergy(0.0),
      volatility_regime_synergy(0.0),
      reversal_structural_synergy(0.0),
      total_synergy_factor(1.0),
      execution_tier(3),
      synergy_breakdown("")
   {}
};

struct SMomentumAlignmentState
{
   double signal_tf_macd;
   double primary_tf_macd;
   double confirm_tf_macd;
   double trend_tf_macd;

   double signal_tf_stochastic;
   double primary_tf_stochastic;
   double confirm_tf_stochastic;
   double trend_tf_stochastic;

   int macd_consensus;
   int stochastic_consensus;
   int combined_momentum_direction;

   double macd_alignment_quality;
   double stochastic_alignment_quality;
   double cross_tf_momentum_confidence;

   SMomentumAlignmentState() :
      signal_tf_macd(0.0),
      primary_tf_macd(0.0),
      confirm_tf_macd(0.0),
      trend_tf_macd(0.0),
      signal_tf_stochastic(50.0),
      primary_tf_stochastic(50.0),
      confirm_tf_stochastic(50.0),
      trend_tf_stochastic(50.0),
      macd_consensus(0),
      stochastic_consensus(0),
      combined_momentum_direction(0),
      macd_alignment_quality(0.0),
      stochastic_alignment_quality(0.0),
      cross_tf_momentum_confidence(0.0)
   {}
};

class CPipelineSynergyEngine
{
private:
   string m_last_symbol;
   datetime m_last_calc_time;
   SStrategySynergyScore m_cached_synergy;

public:
   CPipelineSynergyEngine() : m_last_symbol(""), m_last_calc_time(0) {}

   SStrategySynergyScore CalculatePipelineSynergies(
      string symbol,
      int direction,
      const STradingSignal &ict_signal,
      const STradingSignal &ai_signal,
      const STradingSignal &kim_signal,
      const STradingSignal &reversal_signal,
      int symbol_index = -1
   )
   {
      SStrategySynergyScore synergy;

      if(symbol == m_last_symbol && TimeCurrent() - m_last_calc_time < 5)
      {
         synergy = m_cached_synergy;
         synergy.synergy_breakdown += " [CACHED]";
         return synergy;
      }

      synergy.ict_valid = (ict_signal.valid && ict_signal.direction == direction);
      synergy.ai_valid = (ai_signal.valid && ai_signal.direction == direction);
      synergy.kim_valid = (kim_signal.valid && kim_signal.direction == direction);
      synergy.reversal_valid = (reversal_signal.valid && reversal_signal.direction == direction);

      int valid_count = 0;
      if(synergy.ict_valid) valid_count++;
      if(synergy.ai_valid) valid_count++;
      if(synergy.kim_valid) valid_count++;
      if(synergy.reversal_valid) valid_count++;

      if(valid_count == 0)
      {
         synergy.synergy_breakdown = "No valid strategies for directional agreement";
         synergy.total_synergy_factor = 0.80;
         synergy.execution_tier = 3;
         return synergy;
      }

      synergy.directional_agreement = (double)valid_count / 4.0;

      SMomentumAlignmentState momentum = CalculateMomentumAlignment(symbol, direction, symbol_index);
      synergy.momentum_agreement = momentum.cross_tf_momentum_confidence;
      synergy.momentum_synergy = CalculateMomentumSynergy(momentum, direction);

      synergy.structure_synergy = CalculateStructuralAlignment(symbol, ict_signal, ai_signal, kim_signal);
      synergy.structural_agreement = synergy.structure_synergy;

      synergy.entry_distance_agreement = CalculateEntryDistanceAgreement(
         symbol, symbol_index, ict_signal, ai_signal, kim_signal
      );

      if(synergy.reversal_valid && synergy.ict_valid)
         synergy.reversal_structural_synergy = CalculateReversalICTSynergy(reversal_signal, ict_signal);

      double vol_regime = (symbol_index >= 0 ? GetCachedVolatilityFactor(symbol, symbol_index) : 1.0);
      synergy.volatility_regime_synergy = CalculateVolatilityAdaptiveWeighting(vol_regime);

      double synergy_base = 1.0 + (synergy.directional_agreement - 0.25) * 0.15;
      synergy_base += synergy.momentum_synergy * 0.08;
      synergy_base += synergy.structure_synergy * 0.06;
      synergy_base += synergy.reversal_structural_synergy * 0.04;

      synergy.total_synergy_factor = synergy_base * synergy.volatility_regime_synergy;
      synergy.total_synergy_factor = MathMax(0.85, MathMin(1.20, synergy.total_synergy_factor));

      if(synergy.total_synergy_factor >= 1.15 && valid_count >= 3)
         synergy.execution_tier = 1;
      else if(synergy.total_synergy_factor >= 1.05 && valid_count >= 2)
         synergy.execution_tier = 2;
      else
         synergy.execution_tier = 3;

      synergy.synergy_breakdown = StringFormat(
         "Dir=%.0f%% Momentum=%.0f%% Struct=%.0f%% Distance=%.0f%% | Synergy=%.3fx | Tier=%d | Vol=%.2f",
         synergy.directional_agreement * 100.0,
         synergy.momentum_agreement * 100.0,
         synergy.structural_agreement * 100.0,
         synergy.entry_distance_agreement * 100.0,
         synergy.total_synergy_factor,
         synergy.execution_tier,
         vol_regime
      );

      m_last_symbol = symbol;
      m_last_calc_time = TimeCurrent();
      m_cached_synergy = synergy;
      return synergy;
   }

   SMomentumAlignmentState CalculateMomentumAlignment(string symbol, int direction, int symbol_index)
   {
      SMomentumAlignmentState state;

      GetMomentumValues(symbol, Signal_TF, symbol_index, state.signal_tf_macd, state.signal_tf_stochastic);
      GetMomentumValues(symbol, Primary_TF, symbol_index, state.primary_tf_macd, state.primary_tf_stochastic);
      GetMomentumValues(symbol, Confirm_TF, symbol_index, state.confirm_tf_macd, state.confirm_tf_stochastic);
      GetMomentumValues(symbol, Trend_TF, symbol_index, state.trend_tf_macd, state.trend_tf_stochastic);

      int macd_bull_count = 0;
      if(state.signal_tf_macd >= 0.0) macd_bull_count++;
      if(state.primary_tf_macd >= 0.0) macd_bull_count++;
      if(state.confirm_tf_macd >= 0.0) macd_bull_count++;
      if(state.trend_tf_macd >= 0.0) macd_bull_count++;

      state.macd_consensus = (macd_bull_count >= 2 ? 1 : macd_bull_count <= 1 ? -1 : 0);
      state.macd_alignment_quality = MathAbs(macd_bull_count - 2.0) / 4.0;

      int stoch_bull_count = 0;
      if(state.signal_tf_stochastic >= 50.0) stoch_bull_count++;
      if(state.primary_tf_stochastic >= 50.0) stoch_bull_count++;
      if(state.confirm_tf_stochastic >= 50.0) stoch_bull_count++;
      if(state.trend_tf_stochastic >= 50.0) stoch_bull_count++;

      state.stochastic_consensus = (stoch_bull_count >= 2 ? 1 : stoch_bull_count <= 1 ? -1 : 0);
      state.stochastic_alignment_quality = MathAbs(stoch_bull_count - 2.0) / 4.0;
      state.combined_momentum_direction =
         (state.macd_consensus == state.stochastic_consensus ? state.macd_consensus : 0);

      int agreement = 0;
      if(state.macd_consensus == direction) agreement++;
      if(state.stochastic_consensus == direction) agreement++;
      state.cross_tf_momentum_confidence = agreement / 2.0;

      return state;
   }

   double CalculateStructuralAlignment(
      string symbol,
      const STradingSignal &ict_sig,
      const STradingSignal &ai_sig,
      const STradingSignal &kim_sig
   )
   {
      double entries[3] = {ict_sig.entry_price, ai_sig.entry_price, kim_sig.entry_price};
      double median_entry = entries[1];
      double max_variation = 0.005;
      int proximity_count = 0;

      for(int i = 0; i < 3; i++)
      {
         if(entries[i] <= 0.0 || median_entry <= 0.0)
            continue;

         double variation = MathAbs(entries[i] - median_entry) / median_entry;
         if(variation <= max_variation)
            proximity_count++;
      }

      double rrs[3] = {ict_sig.risk_reward_ratio, ai_sig.risk_reward_ratio, kim_sig.risk_reward_ratio};
      int rr_consensus_count = 0;
      for(int i = 0; i < 3; i++)
      {
         if(rrs[i] >= 2.0 && rrs[i] <= 4.0)
            rr_consensus_count++;
      }

      int ob_fvg_count = 0;
      if(ict_sig.order_block_high > 0.0 && ict_sig.order_block_low > 0.0)
         ob_fvg_count++;
      if(ict_sig.fvg_high > 0.0 && ict_sig.fvg_low > 0.0)
         ob_fvg_count++;

      return (proximity_count / 3.0) * 0.25 +
             (rr_consensus_count / 3.0) * 0.25 +
             (MathMin(1.0, ob_fvg_count) * 0.5) * 0.25 +
             (MathMin(1.0, proximity_count + rr_consensus_count) / 6.0) * 0.25;
   }

   double CalculateEntryDistanceAgreement(
      string symbol,
      int symbol_index,
      const STradingSignal &ict_sig,
      const STradingSignal &ai_sig,
      const STradingSignal &kim_sig
   )
   {
      double mid_price = GetCachedMidPrice(symbol, symbol_index);
      if(mid_price <= 0.0)
         return 0.5;

      double tolerance = 0.015;
      int agreement_count = 0;
      int valid_count = 0;

      double entries[3] = {ict_sig.entry_price, ai_sig.entry_price, kim_sig.entry_price};
      for(int i = 0; i < 3; i++)
      {
         if(entries[i] <= 0.0)
            continue;

         valid_count++;
         double dist = MathAbs(entries[i] - mid_price) / mid_price;
         if(dist <= tolerance)
            agreement_count++;
      }

      if(valid_count == 0)
         return 0.5;

      return (double)agreement_count / (double)valid_count;
   }

   double CalculateReversalICTSynergy(const STradingSignal &reversal_sig, const STradingSignal &ict_sig)
   {
      if(reversal_sig.entry_price <= 0.0 || ict_sig.entry_price <= 0.0)
         return 0.0;

      double entry_dist = MathAbs(reversal_sig.entry_price - ict_sig.entry_price) /
                          MathMax(0.00001, ict_sig.entry_price);

      if(entry_dist < 0.005)
         return 1.0;
      if(entry_dist < 0.020)
         return 0.6;
      if(entry_dist < 0.050)
         return 0.3;

      return 0.0;
   }

   double CalculateVolatilityAdaptiveWeighting(double vol_factor)
   {
      if(vol_factor < 0.80)
         return 0.95;
      if(vol_factor <= 1.20)
         return 1.0;
      return 1.05;
   }

   double CalculateMomentumSynergy(const SMomentumAlignmentState &momentum, int direction)
   {
      double score = 0.0;
      if(momentum.macd_consensus == direction)
         score += 0.5;
      if(momentum.stochastic_consensus == direction)
         score += 0.5;
      return MathMin(1.0, score);
   }

   void ApplySynergyToSignal(STradingSignal &signal, const SStrategySynergyScore &synergy)
   {
      if(!signal.valid)
         return;

      signal.ai_confidence *= synergy.total_synergy_factor;
      if(StringLen(signal.strategy_output_summary) > 0)
         signal.strategy_output_summary += " | Synergy=" + synergy.synergy_breakdown;
      else
         signal.strategy_output_summary = "Synergy=" + synergy.synergy_breakdown;
   }
};

CPipelineSynergyEngine g_pipeline_synergy;

#endif // PIPELINE_SYNERGY_MQH
