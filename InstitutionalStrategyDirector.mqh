#ifndef INSTITUTIONAL_STRATEGY_DIRECTOR_MQH
#define INSTITUTIONAL_STRATEGY_DIRECTOR_MQH

#define DIRECTOR_REGIME_COUNT 4

enum ENUM_DIRECTOR_MARKET_REGIME
{
   DIRECTOR_REGIME_ACCUMULATION = 0,
   DIRECTOR_REGIME_EXPANSION = 1,
   DIRECTOR_REGIME_DISTRIBUTION = 2,
   DIRECTOR_REGIME_VOLATILITY_SHOCK = 3
};

enum ENUM_DIRECTOR_STRATEGY_MODE
{
   DIRECTOR_STRATEGY_KIMANIQ_RANGE = 0,
   DIRECTOR_STRATEGY_AI_TREND = 1,
   DIRECTOR_STRATEGY_ICT_RETRACEMENT = 2
};

double g_director_transition_matrix[MAX_SYMBOLS][DIRECTOR_REGIME_COUNT][DIRECTOR_REGIME_COUNT];
double g_director_transition_prior[DIRECTOR_REGIME_COUNT][DIRECTOR_REGIME_COUNT];
bool g_director_transition_seeded = false;
double g_director_regime_prob[MAX_SYMBOLS][DIRECTOR_REGIME_COUNT];
bool g_director_regime_prob_seeded[MAX_SYMBOLS];
int g_director_transition_counts[MAX_SYMBOLS][DIRECTOR_REGIME_COUNT][DIRECTOR_REGIME_COUNT];
double g_director_transition_reward_sum[MAX_SYMBOLS][DIRECTOR_REGIME_COUNT][DIRECTOR_REGIME_COUNT];
bool g_director_learning_loaded = false;
datetime g_director_last_save_time = 0;

#define DIRECTOR_LEARNING_STATE_FILE "PTB_DirectorMarkovState.bin"
#define DIRECTOR_LEARNING_STATE_VERSION 2
#define MAX_DIRECTOR_ORDER_INTENTS 512
#define MAX_DIRECTOR_OPEN_CONTEXTS 512

ulong g_director_intent_orders[MAX_DIRECTOR_ORDER_INTENTS];
string g_director_intent_symbols[MAX_DIRECTOR_ORDER_INTENTS];
int g_director_intent_modes[MAX_DIRECTOR_ORDER_INTENTS];
int g_director_intent_strategies[MAX_DIRECTOR_ORDER_INTENTS];
datetime g_director_intent_times[MAX_DIRECTOR_ORDER_INTENTS];
bool g_director_intent_used[MAX_DIRECTOR_ORDER_INTENTS];

ulong g_director_open_position_ids[MAX_DIRECTOR_OPEN_CONTEXTS];
string g_director_open_symbols[MAX_DIRECTOR_OPEN_CONTEXTS];
int g_director_open_entry_modes[MAX_DIRECTOR_OPEN_CONTEXTS];
int g_director_open_entry_strategies[MAX_DIRECTOR_OPEN_CONTEXTS];
datetime g_director_open_times[MAX_DIRECTOR_OPEN_CONTEXTS];
bool g_director_open_used[MAX_DIRECTOR_OPEN_CONTEXTS];

struct SDirectorLiquidityMap
{
   bool near_prev_day_high;
   bool near_prev_day_low;
   bool near_equal_highs;
   bool near_equal_lows;
   bool near_order_block;
   bool near_fvg;
   double score;

   SDirectorLiquidityMap() :
      near_prev_day_high(false),
      near_prev_day_low(false),
      near_equal_highs(false),
      near_equal_lows(false),
      near_order_block(false),
      near_fvg(false),
      score(0.0) {}
};

struct SDirectorFeatureState
{
   double volatility_score;
   double micro_score;
   double adx_score;
   double rsi_value;
   double spread_points;
   int trend_signal;
   int trend_primary;
   int trend_confirm;
   int aligned_structures;
   int opposed_structures;
   bool sweep_high;
   bool sweep_low;
   bool first_retracement;
   bool discount_zone;
   SDirectorLiquidityMap liq_map;
   double score_accumulation;
   double score_expansion;
   double score_distribution;
   double score_shock;
   double best_score;
   double runner_score;

   SDirectorFeatureState() :
      volatility_score(1.0),
      micro_score(0.0),
      adx_score(20.0),
      rsi_value(50.0),
      spread_points(0.0),
      trend_signal(0),
      trend_primary(0),
      trend_confirm(0),
      aligned_structures(0),
      opposed_structures(0),
      sweep_high(false),
      sweep_low(false),
      first_retracement(false),
      discount_zone(false),
      score_accumulation(0.0),
      score_expansion(0.0),
      score_distribution(0.0),
      score_shock(0.0),
      best_score(0.0),
      runner_score(0.0) {}
};

double DirectorClamp01(double value)
{
   if(value < 0.0)
      return 0.0;
   if(value > 1.0)
      return 1.0;
   return value;
}

double DirectorNormalize(double value, double low, double high)
{
   if(high <= low)
      return 0.0;
   return DirectorClamp01((value - low) / (high - low));
}

int DirectorRegimeIndexFromAutoMode(int auto_mode)
{
   if(auto_mode == AUTO_REGIME_MODE_INTRA_HIGHLOW)
      return DIRECTOR_REGIME_ACCUMULATION;
   if(auto_mode == AUTO_REGIME_MODE_TREND_ALIGNED)
      return DIRECTOR_REGIME_EXPANSION;
   if(auto_mode == AUTO_REGIME_MODE_RETRACEMENT)
      return DIRECTOR_REGIME_DISTRIBUTION;
   return -1;
}

void DirectorNormalizeTransitionRow(int symbol_index, int row)
{
   if(symbol_index < 0 || symbol_index >= MAX_SYMBOLS)
      return;
   if(row < 0 || row >= DIRECTOR_REGIME_COUNT)
      return;

   double sum = 0.0;
   for(int j = 0; j < DIRECTOR_REGIME_COUNT; j++)
   {
      if(g_director_transition_matrix[symbol_index][row][j] < 0.0001)
         g_director_transition_matrix[symbol_index][row][j] = 0.0001;
      sum += g_director_transition_matrix[symbol_index][row][j];
   }

   if(sum <= 0.0 || !MathIsValidNumber(sum))
   {
      for(int j = 0; j < DIRECTOR_REGIME_COUNT; j++)
         g_director_transition_matrix[symbol_index][row][j] = g_director_transition_prior[row][j];
      return;
   }

   for(int j = 0; j < DIRECTOR_REGIME_COUNT; j++)
      g_director_transition_matrix[symbol_index][row][j] /= sum;
}

void DirectorSaveLearningState(bool force_save = false)
{
   if(!g_director_transition_seeded)
      return;

   datetime now = TimeCurrent();
   if(!force_save && g_director_last_save_time > 0 && (now - g_director_last_save_time) < 60)
      return;

   int handle = FileOpen(DIRECTOR_LEARNING_STATE_FILE, FILE_BIN | FILE_WRITE | FILE_COMMON);
   if(handle == INVALID_HANDLE)
      return;

   FileWriteInteger(handle, DIRECTOR_LEARNING_STATE_VERSION, INT_VALUE);
   for(int s = 0; s < MAX_SYMBOLS; s++)
   {
      for(int i = 0; i < DIRECTOR_REGIME_COUNT; i++)
      {
         for(int j = 0; j < DIRECTOR_REGIME_COUNT; j++)
            FileWriteDouble(handle, g_director_transition_matrix[s][i][j]);
      }
   }
   for(int s = 0; s < MAX_SYMBOLS; s++)
   {
      for(int i = 0; i < DIRECTOR_REGIME_COUNT; i++)
      {
         for(int j = 0; j < DIRECTOR_REGIME_COUNT; j++)
            FileWriteInteger(handle, g_director_transition_counts[s][i][j], INT_VALUE);
      }
   }
   for(int s = 0; s < MAX_SYMBOLS; s++)
   {
      for(int i = 0; i < DIRECTOR_REGIME_COUNT; i++)
      {
         for(int j = 0; j < DIRECTOR_REGIME_COUNT; j++)
            FileWriteDouble(handle, g_director_transition_reward_sum[s][i][j]);
      }
   }

   FileClose(handle);
   g_director_last_save_time = now;
}

void DirectorLoadLearningState()
{
   if(g_director_learning_loaded)
      return;
   g_director_learning_loaded = true;

   int handle = FileOpen(DIRECTOR_LEARNING_STATE_FILE, FILE_BIN | FILE_READ | FILE_COMMON);
   if(handle == INVALID_HANDLE)
      return;

   int version = FileReadInteger(handle, INT_VALUE);
   if(version == 1)
   {
      double legacy_matrix[DIRECTOR_REGIME_COUNT][DIRECTOR_REGIME_COUNT];
      int legacy_counts[DIRECTOR_REGIME_COUNT][DIRECTOR_REGIME_COUNT];
      double legacy_rewards[DIRECTOR_REGIME_COUNT][DIRECTOR_REGIME_COUNT];

      for(int i = 0; i < DIRECTOR_REGIME_COUNT; i++)
      {
         for(int j = 0; j < DIRECTOR_REGIME_COUNT; j++)
         {
            legacy_matrix[i][j] = g_director_transition_prior[i][j];
            legacy_counts[i][j] = 0;
            legacy_rewards[i][j] = 0.0;
         }
      }

      for(int i = 0; i < DIRECTOR_REGIME_COUNT; i++)
      {
         for(int j = 0; j < DIRECTOR_REGIME_COUNT; j++)
         {
            if(FileIsEnding(handle))
            {
               FileClose(handle);
               return;
            }
            double v = FileReadDouble(handle);
            if(MathIsValidNumber(v) && v > 0.0)
               legacy_matrix[i][j] = v;
         }
      }

      for(int i = 0; i < DIRECTOR_REGIME_COUNT; i++)
      {
         for(int j = 0; j < DIRECTOR_REGIME_COUNT; j++)
         {
            if(FileIsEnding(handle))
            {
               FileClose(handle);
               return;
            }
            legacy_counts[i][j] = MathMax(0, FileReadInteger(handle, INT_VALUE));
         }
      }

      for(int i = 0; i < DIRECTOR_REGIME_COUNT; i++)
      {
         for(int j = 0; j < DIRECTOR_REGIME_COUNT; j++)
         {
            if(FileIsEnding(handle))
            {
               FileClose(handle);
               return;
            }
            legacy_rewards[i][j] = FileReadDouble(handle);
         }
      }

      FileClose(handle);

      for(int s = 0; s < MAX_SYMBOLS; s++)
      {
         for(int i = 0; i < DIRECTOR_REGIME_COUNT; i++)
         {
            for(int j = 0; j < DIRECTOR_REGIME_COUNT; j++)
            {
               g_director_transition_matrix[s][i][j] = legacy_matrix[i][j];
               g_director_transition_counts[s][i][j] = legacy_counts[i][j];
               g_director_transition_reward_sum[s][i][j] = legacy_rewards[i][j];
            }
            DirectorNormalizeTransitionRow(s, i);
         }
      }
      return;
   }

   if(version != DIRECTOR_LEARNING_STATE_VERSION)
   {
      FileClose(handle);
      return;
   }

   for(int s = 0; s < MAX_SYMBOLS; s++)
   {
      for(int i = 0; i < DIRECTOR_REGIME_COUNT; i++)
      {
         for(int j = 0; j < DIRECTOR_REGIME_COUNT; j++)
         {
            if(FileIsEnding(handle))
            {
               FileClose(handle);
               return;
            }
            double v = FileReadDouble(handle);
            if(MathIsValidNumber(v) && v > 0.0)
               g_director_transition_matrix[s][i][j] = v;
         }
         DirectorNormalizeTransitionRow(s, i);
      }
   }

   for(int s = 0; s < MAX_SYMBOLS; s++)
   {
      for(int i = 0; i < DIRECTOR_REGIME_COUNT; i++)
      {
         for(int j = 0; j < DIRECTOR_REGIME_COUNT; j++)
         {
            if(FileIsEnding(handle))
            {
               FileClose(handle);
               return;
            }
            g_director_transition_counts[s][i][j] = MathMax(0, FileReadInteger(handle, INT_VALUE));
         }
      }
   }

   for(int s = 0; s < MAX_SYMBOLS; s++)
   {
      for(int i = 0; i < DIRECTOR_REGIME_COUNT; i++)
      {
         for(int j = 0; j < DIRECTOR_REGIME_COUNT; j++)
         {
            if(FileIsEnding(handle))
            {
               FileClose(handle);
               return;
            }
            g_director_transition_reward_sum[s][i][j] = FileReadDouble(handle);
         }
      }
   }

   FileClose(handle);
}

void DirectorFlushLearningState()
{
   DirectorSaveLearningState(true);
}

void DirectorPruneIntentCache(datetime now_time)
{
   for(int i = 0; i < MAX_DIRECTOR_ORDER_INTENTS; i++)
   {
      if(!g_director_intent_used[i])
         continue;
      if((now_time - g_director_intent_times[i]) > 86400)
      {
         g_director_intent_used[i] = false;
         g_director_intent_orders[i] = 0;
         g_director_intent_symbols[i] = "";
         g_director_intent_modes[i] = AUTO_REGIME_MODE_DISABLED;
         g_director_intent_strategies[i] = -1;
         g_director_intent_times[i] = 0;
      }
   }
}

int DirectorFindIntentSlot(ulong order_ticket)
{
   if(order_ticket == 0)
      return -1;
   for(int i = 0; i < MAX_DIRECTOR_ORDER_INTENTS; i++)
   {
      if(g_director_intent_used[i] && g_director_intent_orders[i] == order_ticket)
         return i;
   }
   return -1;
}

int DirectorFindIntentWriteSlot()
{
   for(int i = 0; i < MAX_DIRECTOR_ORDER_INTENTS; i++)
   {
      if(!g_director_intent_used[i])
         return i;
   }

   int oldest = 0;
   datetime oldest_time = g_director_intent_times[0];
   for(int i = 1; i < MAX_DIRECTOR_ORDER_INTENTS; i++)
   {
      if(g_director_intent_times[i] < oldest_time)
      {
         oldest = i;
         oldest_time = g_director_intent_times[i];
      }
   }
   return oldest;
}

void DirectorRegisterOrderIntent(string symbol, ulong order_ticket, int entry_auto_mode,
                                 int strategy_mode, datetime intent_time)
{
   if(order_ticket == 0 || symbol == "")
      return;

   DirectorInitTransitionMatrix();

   if(intent_time <= 0)
      intent_time = TimeCurrent();

   DirectorPruneIntentCache(intent_time);

   int slot = DirectorFindIntentSlot(order_ticket);
   if(slot < 0)
      slot = DirectorFindIntentWriteSlot();
   if(slot < 0)
      return;

   g_director_intent_used[slot] = true;
   g_director_intent_orders[slot] = order_ticket;
   g_director_intent_symbols[slot] = symbol;
   g_director_intent_modes[slot] = entry_auto_mode;
   g_director_intent_strategies[slot] = strategy_mode;
   g_director_intent_times[slot] = intent_time;
}

bool DirectorConsumeOrderIntent(string symbol, ulong order_ticket, int &entry_auto_mode,
                                int &strategy_mode, datetime &intent_time)
{
   entry_auto_mode = AUTO_REGIME_MODE_DISABLED;
   strategy_mode = -1;
   intent_time = 0;
   if(order_ticket == 0)
      return false;

   int slot = DirectorFindIntentSlot(order_ticket);
   if(slot < 0)
      return false;

   if(symbol != "" && g_director_intent_symbols[slot] != "" && g_director_intent_symbols[slot] != symbol)
      return false;

   entry_auto_mode = g_director_intent_modes[slot];
   strategy_mode = g_director_intent_strategies[slot];
   intent_time = g_director_intent_times[slot];

   g_director_intent_used[slot] = false;
   g_director_intent_orders[slot] = 0;
   g_director_intent_symbols[slot] = "";
   g_director_intent_modes[slot] = AUTO_REGIME_MODE_DISABLED;
   g_director_intent_strategies[slot] = -1;
   g_director_intent_times[slot] = 0;
   return true;
}

int DirectorFindOpenContextSlot(ulong position_id, string symbol)
{
   if(position_id == 0)
      return -1;
   for(int i = 0; i < MAX_DIRECTOR_OPEN_CONTEXTS; i++)
   {
      if(g_director_open_used[i] &&
         g_director_open_position_ids[i] == position_id &&
         g_director_open_symbols[i] == symbol)
         return i;
   }
   return -1;
}

int DirectorFindOpenContextWriteSlot()
{
   for(int i = 0; i < MAX_DIRECTOR_OPEN_CONTEXTS; i++)
   {
      if(!g_director_open_used[i])
         return i;
   }

   int oldest = 0;
   datetime oldest_time = g_director_open_times[0];
   for(int i = 1; i < MAX_DIRECTOR_OPEN_CONTEXTS; i++)
   {
      if(g_director_open_times[i] < oldest_time)
      {
         oldest = i;
         oldest_time = g_director_open_times[i];
      }
   }
   return oldest;
}

void DirectorPruneOpenContextCache(datetime now_time)
{
   for(int i = 0; i < MAX_DIRECTOR_OPEN_CONTEXTS; i++)
   {
      if(!g_director_open_used[i])
         continue;
      if((now_time - g_director_open_times[i]) > 7 * 86400)
      {
         g_director_open_used[i] = false;
         g_director_open_position_ids[i] = 0;
         g_director_open_symbols[i] = "";
         g_director_open_entry_modes[i] = AUTO_REGIME_MODE_DISABLED;
         g_director_open_entry_strategies[i] = -1;
         g_director_open_times[i] = 0;
      }
   }
}

void DirectorRegisterOpenPositionContext(string symbol, ulong position_id, int entry_auto_mode,
                                         int strategy_mode, datetime open_time)
{
   if(position_id == 0 || symbol == "")
      return;

   DirectorInitTransitionMatrix();

   if(open_time <= 0)
      open_time = TimeCurrent();
   DirectorPruneOpenContextCache(open_time);

   int slot = DirectorFindOpenContextSlot(position_id, symbol);
   if(slot < 0)
      slot = DirectorFindOpenContextWriteSlot();
   if(slot < 0)
      return;

   g_director_open_used[slot] = true;
   g_director_open_position_ids[slot] = position_id;
   g_director_open_symbols[slot] = symbol;
   g_director_open_entry_modes[slot] = entry_auto_mode;
   g_director_open_entry_strategies[slot] = strategy_mode;
   g_director_open_times[slot] = open_time;
}

bool DirectorGetOpenPositionContext(ulong position_id, string symbol, int &entry_auto_mode,
                                    int &strategy_mode, datetime &open_time, bool consume)
{
   entry_auto_mode = AUTO_REGIME_MODE_DISABLED;
   strategy_mode = -1;
   open_time = 0;
   if(position_id == 0)
      return false;

   int slot = DirectorFindOpenContextSlot(position_id, symbol);
   if(slot < 0)
      return false;

   entry_auto_mode = g_director_open_entry_modes[slot];
   strategy_mode = g_director_open_entry_strategies[slot];
   open_time = g_director_open_times[slot];

   if(consume)
   {
      g_director_open_used[slot] = false;
      g_director_open_position_ids[slot] = 0;
      g_director_open_symbols[slot] = "";
      g_director_open_entry_modes[slot] = AUTO_REGIME_MODE_DISABLED;
      g_director_open_entry_strategies[slot] = -1;
      g_director_open_times[slot] = 0;
   }

   return true;
}

bool DirectorIsPositionIdentifierOpen(ulong position_id, string symbol)
{
   if(position_id == 0)
      return false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(symbol != "")
      {
         string pos_symbol = PositionGetString(POSITION_SYMBOL);
         if(pos_symbol != symbol)
            continue;
      }

      long identifier = PositionGetInteger(POSITION_IDENTIFIER);
      if(identifier > 0 && (ulong)identifier == position_id)
         return true;
   }

   return false;
}

string DirectorAutoModeToString(int auto_mode)
{
   switch(auto_mode)
   {
      case AUTO_REGIME_MODE_TREND_ALIGNED: return "TREND";
      case AUTO_REGIME_MODE_RETRACEMENT:   return "RETRACEMENT";
      case AUTO_REGIME_MODE_INTRA_HIGHLOW: return "RANGE";
      default:                             return "DISABLED";
   }
}

string DirectorMarketRegimeToString(ENUM_DIRECTOR_MARKET_REGIME regime)
{
   switch(regime)
   {
      case DIRECTOR_REGIME_ACCUMULATION:    return "ACCUMULATION";
      case DIRECTOR_REGIME_EXPANSION:       return "EXPANSION";
      case DIRECTOR_REGIME_DISTRIBUTION:    return "DISTRIBUTION";
      case DIRECTOR_REGIME_VOLATILITY_SHOCK:return "VOLATILITY_SHOCK";
      default:                              return "UNKNOWN";
   }
}

string DirectorStrategyModeToString(ENUM_DIRECTOR_STRATEGY_MODE mode)
{
   switch(mode)
   {
      case DIRECTOR_STRATEGY_KIMANIQ_RANGE:    return "KIMANIQ_RANGE";
      case DIRECTOR_STRATEGY_AI_TREND:         return "AI_TREND";
      case DIRECTOR_STRATEGY_ICT_RETRACEMENT:  return "ICT_RETRACEMENT";
      default:                                  return "UNKNOWN";
   }
}

double DirectorOutcomeRewardScore(double deal_net)
{
   if(!MathIsValidNumber(deal_net))
      return 0.0;
   if(deal_net > 0.01)
      return 1.0;
   if(deal_net < -0.01)
      return -1.0;
   return 0.0;
}

ENUM_DIRECTOR_MARKET_REGIME DirectorDetectRegimeSnapshot(string symbol)
{
   if(symbol == "")
      return DIRECTOR_REGIME_DISTRIBUTION;

   SDirectorFeatureState state;
   state.volatility_score = DirectorVolatilityScore(symbol, Signal_TF, g_Director_ATR_Period);
   state.micro_score = DirectorMicrostructureSignal(symbol, Signal_TF);
   state.sweep_high = DirectorLiquiditySweepHigh(symbol, Signal_TF);
   state.sweep_low = DirectorLiquiditySweepLow(symbol, Signal_TF);
   state.trend_signal = DirectorTrendDirection(symbol, Signal_TF, g_Director_FastMA, g_Director_SlowMA);
   state.trend_primary = DirectorTrendDirection(symbol, Primary_TF, g_Director_FastMA, g_Director_SlowMA);
   state.trend_confirm = DirectorTrendDirection(symbol, Confirm_TF, g_Director_FastMA, g_Director_SlowMA);
   state.rsi_value = GetRSIValue(symbol, Signal_TF, 14);
   DirectorGetADXValue(symbol, Signal_TF, 14, 1, state.adx_score);

   if(!MathIsValidNumber(state.rsi_value) || state.rsi_value <= 0.0 || state.rsi_value >= 100.0)
      state.rsi_value = 50.0;
   if(!MathIsValidNumber(state.adx_score) || state.adx_score <= 0.0)
      state.adx_score = 20.0;

   long spread_points = 0;
   if(!SymbolInfoInteger(symbol, SYMBOL_SPREAD, spread_points))
      spread_points = 0;
   state.spread_points = (double)MathMax(0, spread_points);

   int trend_direction = GetHTFBiasInstitutional(symbol);
   if(trend_direction == 1 || trend_direction == -1)
   {
      state.first_retracement = IsFirstRetracementAfterBOS(symbol, Signal_TF, trend_direction);
      state.discount_zone = IsInDiscountZone(symbol, Signal_TF, trend_direction);
   }

   int sig_struct = DirectorStructureDirection(DetectMarketStructure(symbol, Signal_TF));
   int pri_struct = DirectorStructureDirection(DetectMarketStructure(symbol, Primary_TF));
   int con_struct = DirectorStructureDirection(DetectMarketStructure(symbol, Confirm_TF));
   int dominant = state.trend_confirm;
   if(dominant == 0) dominant = state.trend_primary;
   if(dominant == 0) dominant = state.trend_signal;
   if(dominant == 0) dominant = con_struct;
   if(dominant == 0) dominant = pri_struct;
   if(dominant == 0) dominant = sig_struct;

   int dirs[3];
   dirs[0] = sig_struct;
   dirs[1] = pri_struct;
   dirs[2] = con_struct;
   state.aligned_structures = 0;
   state.opposed_structures = 0;
   for(int d = 0; d < 3; d++)
   {
      if(dirs[d] == 0 || dominant == 0)
         continue;
      if(dirs[d] == dominant)
         state.aligned_structures++;
      else
         state.opposed_structures++;
   }

   DirectorBuildLiquidityMap(symbol, trend_direction, state.liq_map);
   return DirectorDetectObservedRegimeFromState(state);
}

void DirectorApplyOnlineTransitionUpdate(int symbol_index, int from_regime, int to_regime, double reward_score)
{
   if(symbol_index < 0 || symbol_index >= MAX_SYMBOLS)
      return;
   if(from_regime < 0 || from_regime >= DIRECTOR_REGIME_COUNT ||
      to_regime < 0 || to_regime >= DIRECTOR_REGIME_COUNT)
      return;

   if(!MathIsValidNumber(reward_score))
      reward_score = 0.0;
   reward_score = MathMax(-1.0, MathMin(1.0, reward_score));

   if(g_director_transition_counts[symbol_index][from_regime][to_regime] < 2000000000)
      g_director_transition_counts[symbol_index][from_regime][to_regime]++;
   g_director_transition_reward_sum[symbol_index][from_regime][to_regime] += reward_score;

   const double prior_weight = 12.0;
   const double reward_scale = 0.70;

   double row_target[DIRECTOR_REGIME_COUNT];
   double row_sum = 0.0;
   double sample_count = 0.0;
   for(int j = 0; j < DIRECTOR_REGIME_COUNT; j++)
   {
      double count = (double)g_director_transition_counts[symbol_index][from_regime][j];
      sample_count += count;
      double avg_reward = 0.0;
      if(count > 0.0)
         avg_reward = g_director_transition_reward_sum[symbol_index][from_regime][j] / count;
      avg_reward = MathMax(-1.0, MathMin(1.0, avg_reward));

      double quality = 1.0 + reward_scale * avg_reward;
      if(quality < 0.10)
         quality = 0.10;

      double posterior = prior_weight * g_director_transition_prior[from_regime][j] + count * quality;
      if(posterior < 0.0001 || !MathIsValidNumber(posterior))
         posterior = 0.0001;
      row_target[j] = posterior;
      row_sum += posterior;
   }

   if(row_sum <= 0.0 || !MathIsValidNumber(row_sum))
      return;

   double eta = 0.10 + 0.30 * DirectorClamp01(sample_count / 200.0);
   for(int j = 0; j < DIRECTOR_REGIME_COUNT; j++)
   {
      double target = row_target[j] / row_sum;
      g_director_transition_matrix[symbol_index][from_regime][j] =
         (1.0 - eta) * g_director_transition_matrix[symbol_index][from_regime][j] + eta * target;
   }

   DirectorNormalizeTransitionRow(symbol_index, from_regime);
   DirectorSaveLearningState(false);
}

bool DirectorLearnFromClose(string symbol, ulong position_id, double deal_net, datetime close_time, string &diagnostic)
{
   diagnostic = "";
   if(symbol == "" || position_id == 0)
      return false;

   DirectorInitTransitionMatrix();

   int entry_auto_mode = AUTO_REGIME_MODE_DISABLED;
   int entry_strategy_mode = -1;
   datetime open_time = 0;
   if(!DirectorGetOpenPositionContext(position_id, symbol, entry_auto_mode, entry_strategy_mode, open_time, false))
      return false;

   if(DirectorIsPositionIdentifierOpen(position_id, symbol))
      return false;

   if(!DirectorGetOpenPositionContext(position_id, symbol, entry_auto_mode, entry_strategy_mode, open_time, true))
      return false;

   int from_regime = DirectorRegimeIndexFromAutoMode(entry_auto_mode);
   if(from_regime < 0)
      return false;

   int symbol_index = GetSymbolIndex(symbol);
   if(symbol_index < 0 || symbol_index >= MAX_SYMBOLS)
      return false;

   ENUM_DIRECTOR_MARKET_REGIME to_regime = DirectorDetectRegimeSnapshot(symbol);
   int to_regime_idx = (int)to_regime;
   double reward = DirectorOutcomeRewardScore(deal_net);
   DirectorApplyOnlineTransitionUpdate(symbol_index, from_regime, to_regime_idx, reward);

   diagnostic = StringFormat(
      "DirectorMarkovLearn %s from=%s to=%s pnl=%.2f reward=%.2f strategy=%d hold=%dmin close=%s",
      symbol,
      DirectorAutoModeToString(entry_auto_mode),
      DirectorMarketRegimeToString(to_regime),
      deal_net,
      reward,
      entry_strategy_mode,
      (open_time > 0 && close_time > open_time ? (int)((close_time - open_time) / 60) : 0),
      TimeToString(close_time)
   );
   return true;
}

void DirectorInitTransitionMatrix()
{
   if(g_director_transition_seeded)
      return;

   g_director_transition_prior[0][0] = 0.60;
   g_director_transition_prior[0][1] = 0.25;
   g_director_transition_prior[0][2] = 0.10;
   g_director_transition_prior[0][3] = 0.05;

   g_director_transition_prior[1][0] = 0.15;
   g_director_transition_prior[1][1] = 0.65;
   g_director_transition_prior[1][2] = 0.15;
   g_director_transition_prior[1][3] = 0.05;

   g_director_transition_prior[2][0] = 0.20;
   g_director_transition_prior[2][1] = 0.20;
   g_director_transition_prior[2][2] = 0.50;
   g_director_transition_prior[2][3] = 0.10;

   g_director_transition_prior[3][0] = 0.30;
   g_director_transition_prior[3][1] = 0.30;
   g_director_transition_prior[3][2] = 0.10;
   g_director_transition_prior[3][3] = 0.30;

   for(int s = 0; s < MAX_SYMBOLS; s++)
   {
      for(int i = 0; i < DIRECTOR_REGIME_COUNT; i++)
      {
         for(int j = 0; j < DIRECTOR_REGIME_COUNT; j++)
         {
            g_director_transition_matrix[s][i][j] = g_director_transition_prior[i][j];
            g_director_transition_counts[s][i][j] = 0;
            g_director_transition_reward_sum[s][i][j] = 0.0;
         }
      }
   }

   for(int i = 0; i < MAX_SYMBOLS; i++)
   {
      g_director_regime_prob_seeded[i] = false;
      for(int j = 0; j < DIRECTOR_REGIME_COUNT; j++)
         g_director_regime_prob[i][j] = 0.25;
   }

   for(int k = 0; k < MAX_DIRECTOR_ORDER_INTENTS; k++)
   {
      g_director_intent_used[k] = false;
      g_director_intent_orders[k] = 0;
      g_director_intent_symbols[k] = "";
      g_director_intent_modes[k] = AUTO_REGIME_MODE_DISABLED;
      g_director_intent_strategies[k] = -1;
      g_director_intent_times[k] = 0;
   }

   for(int k = 0; k < MAX_DIRECTOR_OPEN_CONTEXTS; k++)
   {
      g_director_open_used[k] = false;
      g_director_open_position_ids[k] = 0;
      g_director_open_symbols[k] = "";
      g_director_open_entry_modes[k] = AUTO_REGIME_MODE_DISABLED;
      g_director_open_entry_strategies[k] = -1;
      g_director_open_times[k] = 0;
   }

   g_director_transition_seeded = true;
   g_director_last_save_time = 0;
   DirectorLoadLearningState();
}

void DirectorSeedRegimeProbabilities(int symbol_index, ENUM_DIRECTOR_MARKET_REGIME regime)
{
   if(symbol_index < 0 || symbol_index >= MAX_SYMBOLS)
      return;

   for(int j = 0; j < DIRECTOR_REGIME_COUNT; j++)
      g_director_regime_prob[symbol_index][j] = 0.05;

   g_director_regime_prob[symbol_index][(int)regime] = 0.85;
   g_director_regime_prob_seeded[symbol_index] = true;
}

bool DirectorGetEMAValue(string symbol, ENUM_TIMEFRAMES tf, int period, int shift, double &value)
{
   value = 0.0;
   if(period <= 1 || shift < 0)
      return false;

   int handle = GetPooledIndicatorHandle(symbol, tf, period, "EMA");
   if(handle == INVALID_HANDLE)
      return false;

   double buf[];
   ArraySetAsSeries(buf, true);
   bool ok = (CopyBuffer(handle, 0, shift, 1, buf) >= 1 &&
              ArraySize(buf) >= 1 &&
              MathIsValidNumber(buf[0]));

   if(!ok)
      return false;

   value = buf[0];
   return true;
}

double DirectorVolatilityScore(string symbol, ENUM_TIMEFRAMES tf, int atr_period)
{
   int period = MathMax(2, atr_period);
   int handle = GetPooledIndicatorHandle(symbol, tf, period, "ATR");
   if(handle == INVALID_HANDLE)
      return 1.0;

   double buffer[];
   ArraySetAsSeries(buffer, true);
   bool ok = (CopyBuffer(handle, 0, 1, 7, buffer) >= 6 && ArraySize(buffer) >= 6);
   if(!ok)
      return 1.0;

   double atr_now = buffer[0];
   double atr_prev = buffer[5];
   if(!MathIsValidNumber(atr_now) || !MathIsValidNumber(atr_prev) ||
      atr_now <= 0.0 || atr_prev <= 0.0)
      return 1.0;

   return atr_now / atr_prev;
}

double DirectorMicrostructureSignal(string symbol, ENUM_TIMEFRAMES tf)
{
   long spread_points = 0;
   if(!SymbolInfoInteger(symbol, SYMBOL_SPREAD, spread_points) || spread_points <= 0)
      spread_points = 1;

   long volume = (long)iVolume(symbol, tf, 1);
   if(volume <= 0)
      volume = (long)iVolume(symbol, tf, 0);
   if(volume <= 0)
      volume = 1;

   return (double)volume / (double)spread_points;
}

bool DirectorLiquiditySweepHigh(string symbol, ENUM_TIMEFRAMES tf)
{
   double high0 = iHigh(symbol, tf, 1);
   double high1 = iHigh(symbol, tf, 2);
   double high2 = iHigh(symbol, tf, 3);
   double close0 = iClose(symbol, tf, 1);
   if(high0 <= 0.0 || high1 <= 0.0 || high2 <= 0.0 || close0 <= 0.0)
      return false;

   if(high0 > high1 && high0 > high2 && close0 < high1)
      return true;
   return false;
}

bool DirectorLiquiditySweepLow(string symbol, ENUM_TIMEFRAMES tf)
{
   double low0 = iLow(symbol, tf, 1);
   double low1 = iLow(symbol, tf, 2);
   double low2 = iLow(symbol, tf, 3);
   double close0 = iClose(symbol, tf, 1);
   if(low0 <= 0.0 || low1 <= 0.0 || low2 <= 0.0 || close0 <= 0.0)
      return false;

   if(low0 < low1 && low0 < low2 && close0 > low1)
      return true;
   return false;
}

int DirectorTrendDirection(string symbol, ENUM_TIMEFRAMES tf, int fast_ma, int slow_ma)
{
   int fast_period = MathMax(2, fast_ma);
   int slow_period = MathMax(fast_period + 1, slow_ma);

   double fast = 0.0;
   double slow = 0.0;
   if(!DirectorGetEMAValue(symbol, tf, fast_period, 1, fast) ||
      !DirectorGetEMAValue(symbol, tf, slow_period, 1, slow))
      return 0;

   if(fast > slow)
      return 1;
   if(fast < slow)
      return -1;
   return 0;
}

bool DirectorGetADXValue(string symbol, ENUM_TIMEFRAMES tf, int period, int shift, double &value)
{
   value = 20.0;
   int p = MathMax(2, period);
   if(shift < 0)
      shift = 0;

   int handle = GetPooledIndicatorHandle(symbol, tf, p, "ADX");
   if(handle == INVALID_HANDLE)
      return false;

   double buf[];
   ArraySetAsSeries(buf, true);
   bool ok = (CopyBuffer(handle, 0, shift, 1, buf) >= 1 &&
              ArraySize(buf) >= 1 &&
              MathIsValidNumber(buf[0]));
   if(!ok)
      return false;

   value = buf[0];
   return true;
}

double DirectorMidPrice(string symbol)
{
   MqlTick tick;
   if(SymbolInfoTick(symbol, tick))
   {
      if(tick.bid > 0.0 && tick.ask > 0.0)
         return (tick.bid + tick.ask) * 0.5;
      if(tick.bid > 0.0)
         return tick.bid;
      if(tick.ask > 0.0)
         return tick.ask;
   }

   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   if(bid > 0.0)
      return bid;
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   if(ask > 0.0)
      return ask;

   double close_price = iClose(symbol, Signal_TF, 0);
   if(close_price > 0.0)
      return close_price;
   return 0.0;
}

int DirectorStructureDirection(int structure)
{
   if(structure == MARKET_BULLISH)
      return 1;
   if(structure == MARKET_BEARISH)
      return -1;
   return 0;
}

bool DirectorDetectEqualLevel(string symbol, ENUM_TIMEFRAMES tf, bool highs, int lookback,
                              double tolerance, double &level_out)
{
   level_out = 0.0;
   int lb = MathMax(20, lookback);
   if(tolerance <= 0.0)
      return false;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, tf, 1, lb, rates);
   if(copied < 12 || ArraySize(rates) < 12)
      return false;

   double best_diff = DBL_MAX;
   bool found = false;
   int limit = MathMin(copied, ArraySize(rates));
   for(int i = 2; i < limit - 2; i++)
   {
      double a = (highs ? rates[i].high : rates[i].low);
      if(a <= 0.0)
         continue;

      for(int j = i + 2; j < limit - 1; j++)
      {
         double b = (highs ? rates[j].high : rates[j].low);
         if(b <= 0.0)
            continue;

         double diff = MathAbs(a - b);
         if(diff <= tolerance && diff < best_diff)
         {
            best_diff = diff;
            level_out = (a + b) * 0.5;
            found = true;
         }
      }
   }

   return found;
}

bool DirectorBuildLiquidityMap(string symbol, int trend_direction, SDirectorLiquidityMap &map)
{
   map = SDirectorLiquidityMap();

   double price = DirectorMidPrice(symbol);
   if(price <= 0.0)
      return false;

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = 0.0001;

   double atr_signal = GetATRValue(symbol, Signal_TF);
   if(atr_signal <= 0.0)
      atr_signal = MathMax(point * 50.0, price * 0.0005);

   double near_limit = MathMax(atr_signal * 0.22, point * 40.0);
   double equal_tol = MathMax(atr_signal * 0.06, point * 18.0);

   double pdh = iHigh(symbol, PERIOD_D1, 1);
   double pdl = iLow(symbol, PERIOD_D1, 1);
   if(pdh > 0.0 && MathAbs(price - pdh) <= near_limit)
   {
      map.near_prev_day_high = true;
      map.score += 0.35;
   }
   if(pdl > 0.0 && MathAbs(price - pdl) <= near_limit)
   {
      map.near_prev_day_low = true;
      map.score += 0.35;
   }

   double equal_high_level = 0.0;
   double equal_low_level = 0.0;
   bool has_equal_highs = DirectorDetectEqualLevel(symbol, Signal_TF, true, 80, equal_tol, equal_high_level);
   bool has_equal_lows = DirectorDetectEqualLevel(symbol, Signal_TF, false, 80, equal_tol, equal_low_level);
   if(has_equal_highs && MathAbs(price - equal_high_level) <= near_limit)
   {
      map.near_equal_highs = true;
      map.score += 0.45;
   }
   if(has_equal_lows && MathAbs(price - equal_low_level) <= near_limit)
   {
      map.near_equal_lows = true;
      map.score += 0.45;
   }

   int probe_direction = trend_direction;
   if(probe_direction == 0)
   {
      int sig_struct = DetectMarketStructure(symbol, Signal_TF);
      probe_direction = DirectorStructureDirection(sig_struct);
      if(probe_direction == 0)
      {
         double ema_fast = 0.0;
         double ema_slow = 0.0;
         if(DirectorGetEMAValue(symbol, Signal_TF, 20, 1, ema_fast) &&
            DirectorGetEMAValue(symbol, Signal_TF, 50, 1, ema_slow))
            probe_direction = (ema_fast >= ema_slow ? 1 : -1);
      }
   }

   double ob_high = 0.0;
   double ob_low = 0.0;
   bool ob_found = false;
   if(probe_direction == 1 || probe_direction == -1)
      ob_found = DetectOrderBlock(symbol, Primary_TF, probe_direction, ob_high, ob_low);
   if(!ob_found && probe_direction != -1)
      ob_found = DetectOrderBlock(symbol, Primary_TF, -1, ob_high, ob_low);
   if(!ob_found && probe_direction != 1)
      ob_found = DetectOrderBlock(symbol, Primary_TF, 1, ob_high, ob_low);

   if(ob_found)
   {
      double ob_mid = (ob_high + ob_low) * 0.5;
      if((price >= ob_low && price <= ob_high) || MathAbs(price - ob_mid) <= near_limit * 1.2)
      {
         map.near_order_block = true;
         map.score += 0.50;
      }
   }

   double fvg_high = 0.0;
   double fvg_low = 0.0;
   bool fvg_found = false;
   if(probe_direction == 1 || probe_direction == -1)
      fvg_found = DetectFairValueGap(symbol, Signal_TF, probe_direction, fvg_high, fvg_low);
   if(!fvg_found && probe_direction != -1)
      fvg_found = DetectFairValueGap(symbol, Signal_TF, -1, fvg_high, fvg_low);
   if(!fvg_found && probe_direction != 1)
      fvg_found = DetectFairValueGap(symbol, Signal_TF, 1, fvg_high, fvg_low);

   if(fvg_found)
   {
      double fvg_mid = (fvg_high + fvg_low) * 0.5;
      if((price >= fvg_low && price <= fvg_high) || MathAbs(price - fvg_mid) <= near_limit * 1.2)
      {
         map.near_fvg = true;
         map.score += 0.50;
      }
   }

   int feature_count = 0;
   if(map.near_prev_day_high) feature_count++;
   if(map.near_prev_day_low) feature_count++;
   if(map.near_equal_highs) feature_count++;
   if(map.near_equal_lows) feature_count++;
   if(map.near_order_block) feature_count++;
   if(map.near_fvg) feature_count++;

   if(feature_count >= 2)
      map.score += 0.35;
   else if(feature_count == 1)
      map.score += 0.10;

   map.score = MathMax(0.0, map.score);
   return true;
}

ENUM_DIRECTOR_MARKET_REGIME DirectorSelectRegimeFromScores(SDirectorFeatureState &state)
{
   double scores[DIRECTOR_REGIME_COUNT];
   scores[DIRECTOR_REGIME_ACCUMULATION] = state.score_accumulation;
   scores[DIRECTOR_REGIME_EXPANSION] = state.score_expansion;
   scores[DIRECTOR_REGIME_DISTRIBUTION] = state.score_distribution;
   scores[DIRECTOR_REGIME_VOLATILITY_SHOCK] = state.score_shock;

   int best_idx = 0;
   int runner_idx = 1;
   if(scores[runner_idx] > scores[best_idx])
   {
      int t = best_idx;
      best_idx = runner_idx;
      runner_idx = t;
   }

   for(int i = 2; i < DIRECTOR_REGIME_COUNT; i++)
   {
      if(scores[i] > scores[best_idx])
      {
         runner_idx = best_idx;
         best_idx = i;
      }
      else if(scores[i] > scores[runner_idx] || runner_idx == best_idx)
      {
         runner_idx = i;
      }
   }

   state.best_score = scores[best_idx];
   state.runner_score = scores[runner_idx];
   return (ENUM_DIRECTOR_MARKET_REGIME)best_idx;
}

ENUM_DIRECTOR_MARKET_REGIME DirectorDetectObservedRegimeFromState(SDirectorFeatureState &state)
{
   double quiet_vol = DirectorNormalize(1.00 - state.volatility_score, 0.0, 0.35);
   double normal_vol = DirectorNormalize(state.volatility_score, 0.85, 1.30);
   double expansion_vol = DirectorNormalize(state.volatility_score, 1.00, 1.55);
   double shock_vol = DirectorNormalize(state.volatility_score, 1.35, 2.40);

   double micro_expansion = DirectorNormalize(state.micro_score, 85.0, 200.0);
   double micro_weak = DirectorNormalize(95.0 - state.micro_score, 0.0, 95.0);

   double adx_trend = DirectorNormalize(state.adx_score, 22.0, 42.0);
   double adx_weak = DirectorNormalize(22.0 - state.adx_score, 0.0, 16.0);
   double adx_exhaust = DirectorNormalize(state.adx_score, 30.0, 55.0);

   double spread_pressure = DirectorNormalize(state.spread_points, 35.0, 130.0);

   double mtf_alignment = DirectorClamp01((double)state.aligned_structures / 3.0);
   double mtf_conflict = DirectorClamp01((double)state.opposed_structures / 3.0);
   double range_bias = DirectorClamp01(1.0 - mtf_alignment);
   if(state.trend_signal == 0 && state.trend_primary == 0 && state.trend_confirm == 0)
      range_bias = MathMin(1.0, range_bias + 0.45);

   double sweep_score = ((state.sweep_high || state.sweep_low) ? 1.0 : 0.0);
   double liq_score = DirectorClamp01(state.liq_map.score / 1.60);
   double retracement_context = (state.first_retracement ? 0.60 : 0.0) +
                                (state.discount_zone ? 0.40 : 0.0);
   if(retracement_context > 1.0)
      retracement_context = 1.0;

   double rsi_exhaustion = 0.0;
   if(state.trend_primary == 1 || state.trend_confirm == 1)
      rsi_exhaustion = DirectorNormalize(state.rsi_value, 62.0, 80.0);
   else if(state.trend_primary == -1 || state.trend_confirm == -1)
      rsi_exhaustion = DirectorNormalize(38.0 - state.rsi_value, 0.0, 18.0);
   else
      rsi_exhaustion = DirectorNormalize(MathAbs(state.rsi_value - 50.0), 8.0, 24.0);

   state.score_accumulation =
      1.30 * quiet_vol +
      0.95 * adx_weak +
      0.90 * range_bias +
      0.60 * micro_weak +
      0.35 * normal_vol;

   state.score_expansion =
      1.20 * expansion_vol +
      1.10 * micro_expansion +
      1.05 * mtf_alignment +
      0.95 * adx_trend +
      0.45 * (state.trend_signal != 0 ? 1.0 : 0.0) -
      0.25 * sweep_score;

   state.score_distribution =
      0.95 * liq_score +
      0.90 * retracement_context +
      0.80 * mtf_conflict +
      0.75 * sweep_score +
      0.65 * rsi_exhaustion +
      0.45 * adx_exhaust;

   state.score_shock =
      1.45 * shock_vol +
      1.00 * sweep_score +
      0.85 * spread_pressure +
      0.70 * liq_score +
      0.55 * mtf_conflict;

   if(state.volatility_score <= 0.80)
      state.score_accumulation += 0.35;
   if(state.volatility_score >= 1.55)
      state.score_shock += 0.45;

   if(state.score_accumulation < 0.0) state.score_accumulation = 0.0;
   if(state.score_expansion < 0.0) state.score_expansion = 0.0;
   if(state.score_distribution < 0.0) state.score_distribution = 0.0;
   if(state.score_shock < 0.0) state.score_shock = 0.0;

   return DirectorSelectRegimeFromScores(state);
}

ENUM_DIRECTOR_MARKET_REGIME DirectorDetectObservedRegime(double volatility_score, double micro_score)
{
   if(volatility_score < 0.80)
      return DIRECTOR_REGIME_ACCUMULATION;

   if(volatility_score > 1.50)
      return DIRECTOR_REGIME_VOLATILITY_SHOCK;

   if(micro_score > 100.0)
      return DIRECTOR_REGIME_EXPANSION;

   return DIRECTOR_REGIME_DISTRIBUTION;
}

ENUM_DIRECTOR_MARKET_REGIME DirectorInferRegime(
   int symbol_index,
   ENUM_DIRECTOR_MARKET_REGIME observed_regime,
   double volatility_score,
   double micro_score,
   double &confidence)
{
   confidence = 1.0;
   if(symbol_index < 0 || symbol_index >= MAX_SYMBOLS)
      return observed_regime;

   DirectorInitTransitionMatrix();

   if(!g_director_regime_prob_seeded[symbol_index])
      DirectorSeedRegimeProbabilities(symbol_index, observed_regime);

   double predicted[DIRECTOR_REGIME_COUNT];
   for(int j = 0; j < DIRECTOR_REGIME_COUNT; j++)
   {
      predicted[j] = 0.0;
      for(int i = 0; i < DIRECTOR_REGIME_COUNT; i++)
         predicted[j] += g_director_regime_prob[symbol_index][i] * g_director_transition_matrix[symbol_index][i][j];
   }

   double emission[DIRECTOR_REGIME_COUNT];
   for(int j = 0; j < DIRECTOR_REGIME_COUNT; j++)
      emission[j] = 0.10;

   int observed_idx = (int)observed_regime;
   emission[observed_idx] = 0.70;
   if(observed_regime == DIRECTOR_REGIME_VOLATILITY_SHOCK && volatility_score >= 1.70)
      emission[observed_idx] = 0.80;
   if(observed_regime == DIRECTOR_REGIME_EXPANSION && micro_score >= 140.0)
      emission[observed_idx] = MathMax(emission[observed_idx], 0.76);

   double tail = (1.0 - emission[observed_idx]) / (double)(DIRECTOR_REGIME_COUNT - 1);
   for(int j = 0; j < DIRECTOR_REGIME_COUNT; j++)
   {
      if(j != observed_idx)
         emission[j] = tail;
   }

   double sum = 0.0;
   for(int j = 0; j < DIRECTOR_REGIME_COUNT; j++)
   {
      g_director_regime_prob[symbol_index][j] = predicted[j] * emission[j];
      sum += g_director_regime_prob[symbol_index][j];
   }

   if(sum <= 0.0 || !MathIsValidNumber(sum))
   {
      DirectorSeedRegimeProbabilities(symbol_index, observed_regime);
      confidence = g_director_regime_prob[symbol_index][observed_idx];
      return observed_regime;
   }

   int best_index = 0;
   double best_prob = 0.0;
   for(int j = 0; j < DIRECTOR_REGIME_COUNT; j++)
   {
      g_director_regime_prob[symbol_index][j] /= sum;
      if(g_director_regime_prob[symbol_index][j] > best_prob)
      {
         best_prob = g_director_regime_prob[symbol_index][j];
         best_index = j;
      }
   }

   confidence = best_prob;
   return (ENUM_DIRECTOR_MARKET_REGIME)best_index;
}

int DirectorRegimeToAutoMode(ENUM_DIRECTOR_MARKET_REGIME regime)
{
   switch(regime)
   {
      case DIRECTOR_REGIME_ACCUMULATION:    return AUTO_REGIME_MODE_INTRA_HIGHLOW;
      case DIRECTOR_REGIME_EXPANSION:       return AUTO_REGIME_MODE_TREND_ALIGNED;
      case DIRECTOR_REGIME_DISTRIBUTION:    return AUTO_REGIME_MODE_RETRACEMENT;
      case DIRECTOR_REGIME_VOLATILITY_SHOCK:return AUTO_REGIME_MODE_RETRACEMENT;
      default:                              return AUTO_REGIME_MODE_DISABLED;
   }
}

ENUM_DIRECTOR_STRATEGY_MODE DirectorAllocateStrategy(ENUM_DIRECTOR_MARKET_REGIME regime)
{
   switch(regime)
   {
      case DIRECTOR_REGIME_ACCUMULATION:    return DIRECTOR_STRATEGY_KIMANIQ_RANGE;
      case DIRECTOR_REGIME_EXPANSION:       return DIRECTOR_STRATEGY_AI_TREND;
      case DIRECTOR_REGIME_DISTRIBUTION:    return DIRECTOR_STRATEGY_ICT_RETRACEMENT;
      case DIRECTOR_REGIME_VOLATILITY_SHOCK:return DIRECTOR_STRATEGY_ICT_RETRACEMENT;
      default:                              return DIRECTOR_STRATEGY_ICT_RETRACEMENT;
   }
}

double DirectorStrategyLotMultiplier(ENUM_DIRECTOR_STRATEGY_MODE mode)
{
   switch(mode)
   {
      case DIRECTOR_STRATEGY_KIMANIQ_RANGE:   return 0.80;
      case DIRECTOR_STRATEGY_AI_TREND:        return 1.20;
      case DIRECTOR_STRATEGY_ICT_RETRACEMENT:
      default:                                return 1.00;
   }
}

double DirectorStrategyLot(ENUM_DIRECTOR_STRATEGY_MODE mode)
{
   double base_lot = MathMax(0.01, g_Director_BaseLot);
   return base_lot * DirectorStrategyLotMultiplier(mode);
}

void DirectorResetRoute(SRoutingMatrix &route, int auto_mode)
{
   route.ict_allowed = false;
   route.ai_allowed = false;
   route.kim_allowed = false;
   route.require_both = false;
   route.suitability_mode = auto_mode;
   route.suitability_enforced = true;
   route.director_active = true;
   route.director_strategy_mode = -1;
   route.director_lot_multiplier = 1.0;
   route.fail_reason = "";
}

bool DirectorEnablePreferredStrategy(
   ENUM_DIRECTOR_STRATEGY_MODE preferred,
   bool can_ict,
   bool can_ai,
   bool can_kim,
   SRoutingMatrix &route,
   ENUM_DIRECTOR_STRATEGY_MODE &selected,
   string &fallback_note)
{
   selected = preferred;
   fallback_note = "";

   switch(preferred)
   {
      case DIRECTOR_STRATEGY_KIMANIQ_RANGE:
      {
         if(can_kim)
         {
            route.kim_allowed = true;
            return true;
         }
         if(can_ict)
         {
            route.ict_allowed = true;
            selected = DIRECTOR_STRATEGY_ICT_RETRACEMENT;
            fallback_note = "fallback=ICT";
            return true;
         }
         if(can_ai)
         {
            route.ai_allowed = true;
            selected = DIRECTOR_STRATEGY_AI_TREND;
            fallback_note = "fallback=AI";
            return true;
         }
         return false;
      }
      case DIRECTOR_STRATEGY_AI_TREND:
      {
         if(can_ai)
         {
            route.ai_allowed = true;
            return true;
         }
         if(can_ict)
         {
            route.ict_allowed = true;
            selected = DIRECTOR_STRATEGY_ICT_RETRACEMENT;
            fallback_note = "fallback=ICT";
            return true;
         }
         if(can_kim)
         {
            route.kim_allowed = true;
            selected = DIRECTOR_STRATEGY_KIMANIQ_RANGE;
            fallback_note = "fallback=KIM";
            return true;
         }
         return false;
      }
      case DIRECTOR_STRATEGY_ICT_RETRACEMENT:
      default:
      {
         if(can_ict)
         {
            route.ict_allowed = true;
            return true;
         }
         if(can_kim)
         {
            route.kim_allowed = true;
            selected = DIRECTOR_STRATEGY_KIMANIQ_RANGE;
            fallback_note = "fallback=KIM";
            return true;
         }
         if(can_ai)
         {
            route.ai_allowed = true;
            selected = DIRECTOR_STRATEGY_AI_TREND;
            fallback_note = "fallback=AI";
            return true;
         }
         return false;
      }
   }
}

bool BuildInstitutionalDirectorRouting(
   string symbol,
   int symbol_index,
   bool ai_available,
   const SRoutingMatrix &base_route,
   SRoutingMatrix &route,
   int &auto_mode,
   string &auto_reason,
   int &auto_htf_score,
   double &auto_volatility,
   bool &auto_first_retracement,
   bool &auto_discount_zone)
{
   if(!g_Use_Institutional_Strategy_Director)
      return false;

   DirectorInitTransitionMatrix();

   auto_htf_score = (int)MathAbs(GetHTFBiasStrengthInstitutional(symbol));
   if(symbol_index >= 0 && symbol_index < g_symbols_count)
      auto_volatility = GetCachedVolatilityFactor(symbol, symbol_index);
   if(!MathIsValidNumber(auto_volatility) || auto_volatility <= 0.0)
      auto_volatility = 1.0;

   int trend_direction = GetHTFBiasInstitutional(symbol);
   auto_first_retracement = false;
   auto_discount_zone = false;
   if(trend_direction == 1 || trend_direction == -1)
   {
      auto_first_retracement = IsFirstRetracementAfterBOS(symbol, Signal_TF, trend_direction);
      auto_discount_zone = IsInDiscountZone(symbol, Signal_TF, trend_direction);
   }

   SDirectorFeatureState state;
   state.volatility_score = DirectorVolatilityScore(symbol, Signal_TF, g_Director_ATR_Period);
   state.micro_score = DirectorMicrostructureSignal(symbol, Signal_TF);
   state.sweep_high = DirectorLiquiditySweepHigh(symbol, Signal_TF);
   state.sweep_low = DirectorLiquiditySweepLow(symbol, Signal_TF);
   state.first_retracement = auto_first_retracement;
   state.discount_zone = auto_discount_zone;
   state.trend_signal = DirectorTrendDirection(symbol, Signal_TF, g_Director_FastMA, g_Director_SlowMA);
   state.trend_primary = DirectorTrendDirection(symbol, Primary_TF, g_Director_FastMA, g_Director_SlowMA);
   state.trend_confirm = DirectorTrendDirection(symbol, Confirm_TF, g_Director_FastMA, g_Director_SlowMA);
   state.rsi_value = GetRSIValue(symbol, Signal_TF, 14);
   DirectorGetADXValue(symbol, Signal_TF, 14, 1, state.adx_score);

   long spread_points = 0;
   if(!SymbolInfoInteger(symbol, SYMBOL_SPREAD, spread_points))
      spread_points = 0;
   state.spread_points = (double)MathMax(0, spread_points);

   int sig_struct = DirectorStructureDirection(DetectMarketStructure(symbol, Signal_TF));
   int pri_struct = DirectorStructureDirection(DetectMarketStructure(symbol, Primary_TF));
   int con_struct = DirectorStructureDirection(DetectMarketStructure(symbol, Confirm_TF));
   int dominant = state.trend_confirm;
   if(dominant == 0) dominant = state.trend_primary;
   if(dominant == 0) dominant = state.trend_signal;
   if(dominant == 0) dominant = con_struct;
   if(dominant == 0) dominant = pri_struct;
   if(dominant == 0) dominant = sig_struct;

   int dirs[3];
   dirs[0] = sig_struct;
   dirs[1] = pri_struct;
   dirs[2] = con_struct;
   state.aligned_structures = 0;
   state.opposed_structures = 0;
   for(int d = 0; d < 3; d++)
   {
      if(dirs[d] == 0 || dominant == 0)
         continue;
      if(dirs[d] == dominant)
         state.aligned_structures++;
      else
         state.opposed_structures++;
   }

   DirectorBuildLiquidityMap(symbol, trend_direction, state.liq_map);

   ENUM_DIRECTOR_MARKET_REGIME observed_regime = DirectorDetectObservedRegimeFromState(state);
   double regime_confidence = 1.0;
   ENUM_DIRECTOR_MARKET_REGIME regime = DirectorInferRegime(symbol_index, observed_regime,
                                                            state.volatility_score, state.micro_score,
                                                            regime_confidence);
   bool hysteresis_hold = false;
   if(symbol_index >= 0 && symbol_index < MAX_SYMBOLS)
   {
      static int last_regime[MAX_SYMBOLS];
      static bool seeded[MAX_SYMBOLS];
      if(seeded[symbol_index] && last_regime[symbol_index] != (int)regime)
      {
         double switch_margin = state.best_score - state.runner_score;
         if(switch_margin < 0.20 && regime_confidence < 0.60)
         {
            regime = (ENUM_DIRECTOR_MARKET_REGIME)last_regime[symbol_index];
            hysteresis_hold = true;
         }
      }
      last_regime[symbol_index] = (int)regime;
      seeded[symbol_index] = true;
   }

   auto_mode = DirectorRegimeToAutoMode(regime);
   route = base_route;
   DirectorResetRoute(route, auto_mode);

   bool can_ict = base_route.ict_allowed;
   bool can_ai = (base_route.ai_allowed && ai_available);
   bool can_kim = base_route.kim_allowed;

   ENUM_DIRECTOR_STRATEGY_MODE preferred_mode = DirectorAllocateStrategy(regime);
   ENUM_DIRECTOR_STRATEGY_MODE selected_mode = preferred_mode;
   string fallback_note = "";
   bool has_strategy = DirectorEnablePreferredStrategy(preferred_mode, can_ict, can_ai, can_kim,
                                                       route, selected_mode, fallback_note);

   if(!has_strategy)
      route.fail_reason = "DirectorNoStrategyAvailable";

   double strategy_lot = DirectorStrategyLot(selected_mode);
   double lot_multiplier = DirectorStrategyLotMultiplier(selected_mode);
   route.director_strategy_mode = (int)selected_mode;
   route.director_lot_multiplier = lot_multiplier;

   string prob_text = "";
   if(symbol_index >= 0 && symbol_index < MAX_SYMBOLS && g_director_regime_prob_seeded[symbol_index])
   {
      prob_text = StringFormat(
         " probs[A=%.0f,E=%.0f,D=%.0f,V=%.0f%%]",
         g_director_regime_prob[symbol_index][0] * 100.0,
         g_director_regime_prob[symbol_index][1] * 100.0,
         g_director_regime_prob[symbol_index][2] * 100.0,
         g_director_regime_prob[symbol_index][3] * 100.0
      );
   }

   auto_reason = StringFormat(
      "InstitutionalDirector regime=%s obs=%s conf=%.0f%% score[A=%.2f,E=%.2f,D=%.2f,S=%.2f] vol=%.2f micro=%.1f adx=%.1f rsi=%.1f spread=%.1f trend[S/P/C=%d/%d/%d] mtf[a=%d,o=%d] liq=%.2f[PdH=%s,PdL=%s,EqH=%s,EqL=%s,OB=%s,FVG=%s] strategy=%s lot=%.2f(x%.2f) sweepH=%s sweepL=%s%s",
      DirectorMarketRegimeToString(regime),
      DirectorMarketRegimeToString(observed_regime),
      regime_confidence * 100.0,
      state.score_accumulation,
      state.score_expansion,
      state.score_distribution,
      state.score_shock,
      state.volatility_score,
      state.micro_score,
      state.adx_score,
      state.rsi_value,
      state.spread_points,
      state.trend_signal,
      state.trend_primary,
      state.trend_confirm,
      state.aligned_structures,
      state.opposed_structures,
      state.liq_map.score,
      (state.liq_map.near_prev_day_high ? "Y" : "N"),
      (state.liq_map.near_prev_day_low ? "Y" : "N"),
      (state.liq_map.near_equal_highs ? "Y" : "N"),
      (state.liq_map.near_equal_lows ? "Y" : "N"),
      (state.liq_map.near_order_block ? "Y" : "N"),
      (state.liq_map.near_fvg ? "Y" : "N"),
      DirectorStrategyModeToString(selected_mode),
      strategy_lot,
      lot_multiplier,
      (state.sweep_high ? "Y" : "N"),
      (state.sweep_low ? "Y" : "N"),
      (StringLen(fallback_note) > 0 ? " " + fallback_note : "")
   );

   if(hysteresis_hold)
      auto_reason += " hysteresis=HOLD";

   if(StringLen(prob_text) > 0)
      auto_reason += prob_text;

   auto_reason += StringFormat(" first=%s discount=%s htf=%d volCache=%.2f",
                               (auto_first_retracement ? "Y" : "N"),
                               (auto_discount_zone ? "Y" : "N"),
                               auto_htf_score,
                               auto_volatility);

   return true;
}

#endif // INSTITUTIONAL_STRATEGY_DIRECTOR_MQH
