#ifndef PROFITTRAILBOT_MQ5
#define PROFITTRAILBOT_MQ5


#property copyright "Copyright 2026, ProfitTrailBot Ltd."
//#property authJoseph Keigi Nganga, Kenya"
// Patent Data: Bot created by Joseph Keigi Nganga, Kenya
#property link      "https://www.mql5.com"
#property version   "5.6"
#property description "ICT Order Block + FVG + Multi-Timeframe Confirmation Bot"
#property description "FIXED: Trade Execution Issues, Entry Price Validation"
#property strict

#import "kernel32.dll"
   int GetTickCount();
#import

#ifndef MAX_SYMBOLS
   #define MAX_SYMBOLS 50
#endif
#ifndef MAX_TF_CACHE
   #define MAX_TF_CACHE 12     // per-symbol structure cache slots (expanded)
#endif

#include <Trade/Trade.mqh>
#include <Trade/AccountInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>
#include <Indicators/Indicators.mqh>
#include <Math/Stat/Math.mqh>
#include <Arrays/ArrayObj.mqh>
#include <Object.mqh>
#include <Files/File.mqh>

// === LOGGING & ALERT TYPES (Required before Logging.mqh) ===
enum ENUM_LOG_LEVEL
{
   LOG_ERROR    = 0,
   LOG_WARNING  = 1,
   LOG_INFO     = 2,
   LOG_DEBUG    = 3,
   LOG_DETAILED = 4
};

enum ENUM_ALERT_TYPE
{
   ALERT_TRADE_OPEN,
   ALERT_TRADE_CLOSE,
   ALERT_SIGNAL,
   ALERT_INFO,
   ALERT_ERROR,
   ALERT_DRAWDOWN,
   ALERT_DAILY_LIMIT,
   ALERT_RISK_CONTROL,
   ALERT_EXECUTION
};

enum ENUM_SIGNAL_ORIGIN
{
   SIGNAL_ORIGIN_UNKNOWN = 0,
   SIGNAL_ORIGIN_ICT = 1,
   SIGNAL_ORIGIN_AI = 2,
   SIGNAL_ORIGIN_BOTH = 3,
   SIGNAL_ORIGIN_KIMANIZ = 4
};

struct STradingSignal
{
   bool      valid;
   int       direction;
   double    entry_price;
   double    stop_loss;
   double    take_profit;
   double    risk_reward_ratio;
   double    atr_value;
   datetime  signal_time;
   string    reason;
   double    order_block_high;
   double    order_block_low;
   double    fvg_high;
   double    fvg_low;
   double    ai_confidence;
   double    ai_probability;
   double    ai_buy_probability;
   double    ai_sell_probability;
   double    ai_effective_probability;
   double    ai_directional_edge;
   double    ai_min_probability_required;
   double    ai_required_edge;
   double    ai_candle_quality_score;
   double    ai_candle_quality_required;
   double    ai_expected_value_r;
   double    ai_spread_to_atr;
   double    ai_volatility_regime;
   bool      ai_agrees;
   string    strategy_output_summary;
   string    strategy_output_detail;
   ENUM_TIMEFRAMES execution_tf;
   int       institutional_regime;
   double    institutional_volatility_factor;
   string    institutional_funnel_summary;
   ENUM_SIGNAL_ORIGIN origin;
   bool      retracement_signal;
   bool      allow_countertrend_execution;
   bool      reversal_detected;
   double    reversal_confidence;
   string    reversal_reason;
   
   STradingSignal() : 
      valid(false),
      direction(0),
      entry_price(0.0),
      stop_loss(0.0),
      take_profit(0.0),
      risk_reward_ratio(0.0),
      atr_value(0.0),
      signal_time(0),
      reason(""),
      order_block_high(0.0),
      order_block_low(0.0),
      fvg_high(0.0),
      fvg_low(0.0),
      ai_confidence(0.5),
      ai_probability(0.5),
      ai_buy_probability(-1.0),
      ai_sell_probability(-1.0),
      ai_effective_probability(-1.0),
      ai_directional_edge(-1.0),
      ai_min_probability_required(-1.0),
      ai_required_edge(-1.0),
      ai_candle_quality_score(-1.0),
      ai_candle_quality_required(-1.0),
      ai_expected_value_r(-1.0),
      ai_spread_to_atr(-1.0),
      ai_volatility_regime(-1.0),
      ai_agrees(false),
      strategy_output_summary(""),
      strategy_output_detail(""),
      execution_tf(PERIOD_CURRENT),
      institutional_regime(-1),
      institutional_volatility_factor(-1.0),
      institutional_funnel_summary(""),
      origin(SIGNAL_ORIGIN_UNKNOWN),
      retracement_signal(false),
      allow_countertrend_execution(false),
      reversal_detected(false),
      reversal_confidence(0.0),
      reversal_reason("")
   {}
};

bool IsDirectionalRetracementSignal(const STradingSignal &signal)
{
   return (signal.retracement_signal &&
           (signal.direction == 1 || signal.direction == -1));
}

bool IsCountertrendRetracementSignal(const STradingSignal &signal)
{
   return (signal.origin == SIGNAL_ORIGIN_KIMANIZ &&
           IsDirectionalRetracementSignal(signal) &&
           signal.allow_countertrend_execution);
}

bool IsHTFAlignedRetracementContinuationSignal(const STradingSignal &signal)
{
   return ((signal.origin == SIGNAL_ORIGIN_ICT || signal.origin == SIGNAL_ORIGIN_BOTH) &&
           IsDirectionalRetracementSignal(signal) &&
           !signal.allow_countertrend_execution);
}

#include "Logging.mqh"
#include "ScoringEngine.mqh"
#include "AIInferenceEngine.mqh"
#include "AIManager.mqh"
#include "ReversalDetectionModule.mqh"
// TIER 1 ENHANCEMENTS
#include "AIEnhancementModule.mqh"
#include "ConfidenceFusionRouter.mqh"  // ENABLED: Temporal decay logic fixed (static arrays removed)
#include "PipelineSynergy.mqh"
// TIER 2 FORWARD INTELLIGENCE
#include "ForwardIntelligence.mqh"
// TIER 3 ADVANCED
#include "DynamicScoringWeights.mqh"
#include "BacktestingFramework.mqh"
#include "NewsIntegration.mqh"
// TIER 4 INSTITUTIONAL TREND SYSTEM
#include "TrendAnalysisEnhanced.mqh"
#include "TrendAnalysisIntegration.mqh"

// FIX #4: Unified Gate Controller (Global synchronization of all execution gates)
#include "UnifiedGateController.mqh"

#define INIT_SUCCEEDED 0
#define INIT_FAILED 1
#define INIT_PARAMETERS_INCORRECT 2

#define ORDER_TYPE_BUY 0
#define ORDER_TYPE_SELL 1
#define STO_LOWHIGH 0

#ifndef TRADE_RETCODE_REQUOTE
#define TRADE_RETCODE_REQUOTE 10004
#endif
#ifndef TRADE_RETCODE_PRICE_OFF
#define TRADE_RETCODE_PRICE_OFF 10015
#endif
#ifndef TRADE_RETCODE_CONNECTION
#define TRADE_RETCODE_CONNECTION 10018
#endif
#ifndef TRADE_RETCODE_TOO_MANY_REQUESTS
#define TRADE_RETCODE_TOO_MANY_REQUESTS 10019
#endif
#ifndef TRADE_RETCODE_LOCKED
#define TRADE_RETCODE_LOCKED 10020
#endif
#ifndef TRADE_RETCODE_TIMEOUT
#define TRADE_RETCODE_TIMEOUT 10021
#endif
#ifndef TRADE_RETCODE_TRADE_DISABLED
#define TRADE_RETCODE_TRADE_DISABLED 10017
#endif
#ifndef TRADE_RETCODE_INVALID_STOPS
#define TRADE_RETCODE_INVALID_STOPS 10016
#endif
#ifndef TRADE_RETCODE_INVALID_VOLUME
#define TRADE_RETCODE_INVALID_VOLUME 10014
#endif
#ifndef TRADE_RETCODE_INVALID_PRICE
#define TRADE_RETCODE_INVALID_PRICE 10015
#endif

#ifndef MAX_SYMBOLS
   #define MAX_SYMBOLS 50
#endif
#define MAX_RETRY_QUEUE 10  // Increased for better retry management
#define MAX_TRADES_PER_SYMBOL 20
#define MAX_ATR_ATTEMPTS 5
#define CACHE_TIMEOUT_SECONDS 5
#ifndef MAX_TF_CACHE
   #define MAX_TF_CACHE 12     // per-symbol structure cache slots (expanded)
#endif
#define MAX_ATR_CACHE 8     // per-symbol ATR cache slots (expanded)
#define STRATEGY_TF_SLOTS 4 // Signal, Primary, Confirm, Trend
#ifndef DEBUG_SIGNAL_INVERSION
   #define DEBUG_SIGNAL_INVERSION 0
#endif
#ifndef DEBUG_SIGNAL_INVERSION_STRICT
   #define DEBUG_SIGNAL_INVERSION_STRICT 0
#endif

// === COMPILE-TIME FILE PATHS (moved from input parameters) ===
#define AI_TRAINING_EXPORT_FILE "ptb_training.db"
#define AI_CONTINUOUS_TRAINING_FILE "ptb_training.db"
#define AUDIT_LOG_FILE "ProfitTrailBot_Audit.csv"
#define AI_SCALER_FILE "ptb_scaler.csv"
#define EXTERNAL_AI_MODEL_PATH "Models\\ptb_model.txt"
#define EXTERNAL_AI_BUY_MODEL "Models\\ptb_buy.txt"
#define EXTERNAL_AI_SELL_MODEL "Models\\ptb_sell.txt"
#define MAX_SIGNAL_COOLDOWN_MINUTES 10

enum ENUM_ICT_SWEEP_PRESET
{
   ICT_PRESET_CUSTOM = 0,
   ICT_PRESET_AGGRESSIVE = 1,
   ICT_PRESET_BALANCED = 2,
   ICT_PRESET_CONSERVATIVE = 3
};

enum ENUM_AI_SIGNAL_GENERATION_MODE
{
   AI_SIGNAL_MODE_HYBRID = 0, // Use structural signal generation + AI validation (current behavior)
   AI_SIGNAL_MODE_PRIMARY = 1 // Generate signal direction/levels from AI and pass to execution
};

enum ENUM_STRATEGY_ROUTING_MODE
{
   STRATEGY_ROUTING_EITHER = 0,   // Allow either ICT or AI
   STRATEGY_ROUTING_ICT_ONLY = 1, // Exclude AI strategy
   STRATEGY_ROUTING_AI_ONLY = 2,  // Exclude ICT strategy
   STRATEGY_ROUTING_BOTH = 3      // Require both ICT and AI agreement
};

enum ENUM_LIVE_RISK_PROFILE
{
   LIVE_PROFILE_MAX_PROFIT = 0, // Keep configured inputs as-is
   LIVE_PROFILE_SAFER_LIVE = 1  // Enforce lower-risk live caps
};

// === PHASE 2: Profile-Based Parameter Systems ===

enum ENUM_GATE_PROFILE
{
   GATE_PERMISSIVE  = 0,  // Minimal quality gates: distance/soft structural checks off
   GATE_STANDARD    = 1,  // Distance & soft structural checks on; FVG/BOS optional
   GATE_STRICT      = 2,  // All gates enabled
   GATE_CUSTOM      = 3   // Manual override of all gates
};

enum ENUM_RISK_TIER
{
   TIER_AGGRESSIVE  = 0,    // Higher risk: Daily 10%, Account 20%, Per-trade 30%
   TIER_BALANCED    = 1,    // Moderate: Daily 5%, Account 14%, Per-trade 20%
   TIER_CONSERVATIVE = 2    // Lower risk: Daily 3%, Account 8%, Per-trade 15%
};

enum ENUM_TF_PRESET
{
   TF_SCALP      = 0,  // M5/M15/H1/H4
   TF_STANDARD   = 1,  // M15/H4/H1/D1 (default)
   TF_SWING      = 2,  // H1/H4/D1/W1
   TF_POSITION   = 3,  // H4/D1/W1/MN1
   TF_CUSTOM     = 4   // Manual override
};

enum ENUM_STRATEGY_MIX
{
   STRAT_ICT_ONLY   = 0, // ICT only
   STRAT_AI_ONLY    = 1, // AI only
   STRAT_BOTH       = 2, // ICT + AI (require agreement)
   STRAT_EITHER     = 3, // Legacy either-routing (ICT/AI, optional KIM if enabled)
   STRAT_KIM_ONLY   = 4, // KImaniz only
   STRAT_ICT_KIM    = 5, // ICT + KImaniz (either/confluence)
   STRAT_AI_KIM     = 6, // AI + KImaniz (either/confluence)
   STRAT_ALL_THREE  = 7  // ICT + AI + KImaniz (either/confluence)
};

bool IsValidStrategyMixInput(ENUM_STRATEGY_MIX mix)
{
   switch(mix)
   {
      case STRAT_ICT_ONLY:
      case STRAT_AI_ONLY:
      case STRAT_BOTH:
      case STRAT_EITHER:
      case STRAT_KIM_ONLY:
      case STRAT_ICT_KIM:
      case STRAT_AI_KIM:
      case STRAT_ALL_THREE:
         return true;
      default:
         return false;
   }
}

ENUM_STRATEGY_MIX NormalizeStrategyMix(ENUM_STRATEGY_MIX mix)
{
   return (IsValidStrategyMixInput(mix) ? mix : STRAT_EITHER);
}

string StrategyMixToString(ENUM_STRATEGY_MIX mix)
{
   switch(mix)
   {
      case STRAT_ICT_ONLY:  return "ICT_ONLY";
      case STRAT_AI_ONLY:   return "AI_ONLY";
      case STRAT_BOTH:      return "BOTH";
      case STRAT_EITHER:    return "EITHER";
      case STRAT_KIM_ONLY:  return "KIM_ONLY";
      case STRAT_ICT_KIM:   return "ICT_KIM";
      case STRAT_AI_KIM:    return "AI_KIM";
      case STRAT_ALL_THREE: return "ALL_THREE";
      default:
         return "UNKNOWN(" + IntegerToString((int)mix) + ")";
   }
}

// === Profile Application Helper Functions ===

// Apply Gate Profile settings (PHASE 2)
void ApplyGateProfile(ENUM_GATE_PROFILE profile, bool& fvg_gate, bool& bos_gate, 
                     bool& entry_distance, bool& soft_gating, bool& spread_gates)
{
   switch(profile)
   {
      case GATE_PERMISSIVE:
         fvg_gate = false;         // FVG optional
         bos_gate = false;          // BOS optional
         entry_distance = false;    // Distance gate OFF
         soft_gating = false;       // Soft gating OFF
         spread_gates = true;       // Spread filters ON
         break;
      case GATE_STANDARD:           // Default/moderate
         fvg_gate = false;
         bos_gate = false;
         entry_distance = true;
         soft_gating = true;
         spread_gates = true;
         break;
      case GATE_STRICT:             // All gates enabled
         fvg_gate = true;
         bos_gate = true;
         entry_distance = true;
         soft_gating = true;
         spread_gates = true;
         break;
      case GATE_CUSTOM:             // User overrides (no change)
      default:
         break;
   }
}

// Apply Risk Tier Profile settings (PHASE 2)
void ApplyRiskTierProfile(ENUM_RISK_TIER tier, double& daily_dd, double& account_dd, 
                         double& per_trade_dd, double& risk_pct)
{
   switch(tier)
   {
      case TIER_AGGRESSIVE:
         daily_dd = 10.0;     // Daily: 10%
         account_dd = 20.0;   // Account: 20%
         per_trade_dd = 30.0; // Per-trade: 30%
         risk_pct = 1.0;      // 1% risk per trade
         break;
      case TIER_BALANCED:      // Default
         daily_dd = 5.0;      // Daily: 5%
         account_dd = 14.0;   // Account: 14%
         per_trade_dd = 20.0; // Per-trade: 20%
         risk_pct = 0.5;      // 0.5% risk per trade
         break;
      case TIER_CONSERVATIVE:
         daily_dd = 3.0;      // Daily: 3%
         account_dd = 8.0;    // Account: 8%
         per_trade_dd = 15.0; // Per-trade: 15%
         risk_pct = 0.25;     // 0.25% risk per trade
         break;
      default:
         break;
   }
}

// Apply Timeframe Preset settings (PHASE 2)
// Presets must satisfy: Signal_TF < Confirm_TF <= Primary_TF <= Trend_TF
void ApplyTimeframePreset(ENUM_TF_PRESET preset, ENUM_TIMEFRAMES& signal_tf, 
                         ENUM_TIMEFRAMES& primary_tf, ENUM_TIMEFRAMES& confirm_tf, 
                         ENUM_TIMEFRAMES& trend_tf)
{
   switch(preset)
   {
      case TF_SCALP:
         signal_tf = PERIOD_M5;
         primary_tf = PERIOD_H1;
         confirm_tf = PERIOD_M15;
         trend_tf = PERIOD_H4;
         break;
      case TF_STANDARD:         // Default
         signal_tf = PERIOD_M15;
         primary_tf = PERIOD_H4;
         confirm_tf = PERIOD_H1;
         trend_tf = PERIOD_D1;
         break;
      case TF_SWING:
         signal_tf = PERIOD_H1;
         primary_tf = PERIOD_D1;
         confirm_tf = PERIOD_H4;
         trend_tf = PERIOD_W1;
         break;
      case TF_POSITION:
         signal_tf = PERIOD_H4;
         primary_tf = PERIOD_W1;
         confirm_tf = PERIOD_D1;
         trend_tf = PERIOD_MN1;
         break;
      case TF_CUSTOM:           // User overrides (no change)
      default:
         break;
   }
}

enum ENUM_SUITABILITY_HUNT_MODE
{
   SUITABILITY_HUNT_STRICT    = 0, // Preserve strict role isolation
   SUITABILITY_HUNT_BALANCED  = 1, // Institutional balanced hunt mode
   SUITABILITY_HUNT_AGGRESSIVE = 2 // Institutional aggressive hunt mode
};

input group "01 | Universe and Scope"
input string Symbols_List            = "XAUUSD"; // Universe | Symbol list when not chart-only
input bool   Trade_Only_Chart_Symbol = true;     // Universe | Trade only attached chart symbol

input group "02 | Operator Profiles"
input ENUM_GATE_PROFILE Gate_Profile_Input            = GATE_PERMISSIVE; // Profile | Gate preset
input ENUM_RISK_TIER Risk_Tier_Profile_Input          = TIER_AGGRESSIVE; // Profile | Risk tier preset
input ENUM_TF_PRESET Timeframe_Preset_Input           = TF_STANDARD;    // Profile | Timeframe preset
input bool Enable_Custom_Gate_Overrides               = true;           // Profile | Allow manual gate settings
input bool Enable_Custom_Risk_Tier_Overrides          = true;           // Profile | Allow manual risk settings
input bool Enable_Custom_Timeframe_Overrides          = false;          // Profile | Allow manual timeframe settings

input group "03 | Strategy Routing"
input ENUM_STRATEGY_MIX Strategy_Mix        = STRAT_ALL_THREE; // Routing | Enabled strategy mix
input bool   Allow_AI_Fallback_In_BOTH_Mode = false; // Routing | Allow AI fallback in BOTH mode
input bool   Allow_ICT_Fallback_In_BOTH_Mode = true; // Routing | Allow ICT fallback in BOTH mode
input bool   Enable_Auto_Regime_Router             = false; // Routing | Auto regime router (live unsupported)
input int    Auto_Regime_Strong_Bias_MinScore      = 6;     // Routing | Strong bias score threshold
input double Auto_Regime_Intra_HighLow_MaxVolatility = 1.10; // Routing | Max volatility for intra high-low
input bool   Use_Institutional_Strategy_Director   = false; // Routing | Director mode (live unsupported)
input double Director_BaseLot                      = 0.01;  // Director | Base lot
input int    Director_ATR_Period                   = 14;    // Director | ATR period
input int    Director_FastMA                       = 20;    // Director | Fast EMA period
input int    Director_SlowMA                       = 50;    // Director | Slow EMA period
input ENUM_SUITABILITY_HUNT_MODE Suitability_Hunt_Mode = SUITABILITY_HUNT_BALANCED; // Suitability | Hunt mode
input bool   Suitability_Allow_CrossRole_Fallbacks = true;  // Suitability | Allow secondary-role fallback
input bool   Suitability_Trend_Require_Confluence_On_Weak_Bias = true; // Suitability | Require confluence on weak trend
input int    Suitability_Weak_Bias_MaxScore        = 4;      // Suitability | Weak trend bias max score
input double Suitability_High_Volatility_Factor    = 1.45;   // Suitability | High-volatility factor
input double Regime_Risk_Multiplier_Trend       = 1.75;  // Regime | Trend risk multiplier
input double Regime_Risk_Multiplier_Range       = 0.75;  // Regime | Range risk multiplier
input double Regime_Risk_Multiplier_Retracement = 1.00;  // Regime | Retracement risk multiplier

input group "04 | Timeframes and Trend Filters"
input ENUM_TIMEFRAMES Signal_TF       = PERIOD_M15; // TF | Entry signal timeframe
input ENUM_TIMEFRAMES Primary_TF      = PERIOD_H4;  // TF | Primary structure timeframe
input ENUM_TIMEFRAMES Confirm_TF      = PERIOD_H1;  // TF | Confirmation timeframe
input ENUM_TIMEFRAMES Trend_TF        = PERIOD_D1;  // TF | Higher-timeframe trend
input bool   Allow_Range_Trading      = true;       // Trend | Allow range-state signals
input bool   Require_All_TF_Agreement = false;      // Trend | Require all timeframes to agree
input bool   Enable_Confluence_Check  = false;      // Trend | Enable confluence gate
input bool   Enable_HTF_Bias_Check    = false;      // Trend | Enable HTF bias gate
input bool   Use_Trend_Filter         = false;      // Trend | Enable trend filter
input bool   Use_ADX_For_Trend        = false;      // Trend | Use ADX trend quality
input int    Trend_Lookback_Bars      = 64;         // Trend | Structure lookback bars
input double Strong_Trend_ADX_Level   = 28.0;       // Trend | Strong ADX threshold
input double Weak_Trend_ADX_Level     = 20.0;       // Trend | Weak ADX threshold

input group "05 | Institutional Funnel"
input bool   Enable_Institutional_Timeframe_Funnel = false;  // Funnel | Enforce Trend-Primary-Confirm-entry
input bool   Enable_Institutional_Liquidity_Gate   = false;  // Funnel | Enable liquidity gate
input bool   Liquidity_Layer_Strict                = false;  // Liquidity | Require sweep confirmation
input int    Liquidity_Level_Lookback              = 50;     // Liquidity | Level lookback bars
input double Liquidity_Tolerance_ATR_Multiple      = 0.12;   // Liquidity | ATR tolerance multiple
input bool   Enable_Adaptive_Entry_Timeframe       = true;   // Entry TF | Adapt during high volatility
input double Adaptive_Entry_HighVol_Threshold      = 1.35;   // Entry TF | High-volatility threshold
input ENUM_TIMEFRAMES Adaptive_Entry_Fast_TF       = PERIOD_M5; // Entry TF | Fast execution timeframe

input group "06 | ICT Structure Model"
input int    Order_Block_Lookback      = 240;   // ICT | Order block lookback bars
input int    Order_Block_Swing_Range   = 5;     // ICT | Order block swing range
input int    Order_Block_Confirmation  = 3;     // ICT | Post-block confirmation bars
input double Min_Order_Block_Size      = 0.35;  // ICT | Minimum order block size
input bool   Use_Advanced_OB_Detection = true;  // ICT | Use advanced OB detection
input double OB_Max_Proximity_Pct      = 3.0;   // ICT | Max OB proximity percent
input bool   Use_FVG_Detection         = true;  // ICT | Enable FVG detection
input double Min_FVG_Size_Ratio        = 0.08;  // ICT | Minimum FVG size ratio
input int    FVG_Lookback_Bars         = 45;    // ICT | FVG lookback bars
input bool   Enable_OB_FVG_Gate        = false; // ICT | Require OB or FVG before signal

input group "07 | KImaniz Retracement Model"
input bool   Enable_KImaniz_Strategy          = true;  // KIM | Enable KImaniz strategy
input int    KImaniz_Swing_Lookback_Bars      = 120;   // KIM | Swing high-low lookback
input double KImaniz_Fib_Zone_29_Pct          = 29.0;  // KIM | Fib zone lower percent
input double KImaniz_Fib_Zone_41_Pct          = 41.0;  // KIM | Fib zone upper percent
input double KImaniz_OTP_Low_Pct              = 70.5;  // KIM | OTP lower percent
input double KImaniz_OTP_Mid_Pct              = 74.0;  // KIM | OTP middle percent
input double KImaniz_OTP_High_Pct             = 79.0;  // KIM | OTP upper percent
input double KImaniz_Entry_Zone_Tolerance_Pct = 0.60;  // KIM | OTP entry tolerance percent
input bool   KImaniz_Allow_Countertrend_With_HTF_Gate = true; // KIM | Allow countertrend with HTF gate

input group "08 | Reversal Model"
input bool   Enable_Reversal_Detection         = false;  // Reversal | Enable module
input double Reversal_Min_Confidence           = 0.68;   // Reversal | Minimum confidence
input bool   Reversal_Require_Divergence       = false;  // Reversal | Require divergence
input bool   Reversal_Use_Structure_Break      = false;  // Reversal | Require structure break
input int    Reversal_Lookback_Bars            = 24;     // Reversal | Lookback bars
input double Reversal_Exhaustion_RSI_Level     = 78.0;   // Reversal | RSI exhaustion level
input double Reversal_Divergence_Threshold     = 0.75;   // Reversal | Divergence threshold
input double Reversal_Momentum_Shift_Threshold = 0.35;   // Reversal | Momentum shift threshold
input bool   Reversal_Override_Direction       = false;  // Reversal | Allow direction override
input double Reversal_Weight_In_Scoring        = 0.15;   // Reversal | Scoring weight

input group "09 | Gate Master Switch"
input bool   Disable_All_Gating_Master_Switch    = true;   // Gates | Bypass optional gates only

// Kill-switch predefined modes with built-in loss limits
enum ENUM_KILL_SWITCH_MODE {
   KILL_SWITCH_MODE_DISABLED      = 0,  // No kill switch active
   KILL_SWITCH_MODE_CONSERVATIVE  = 1,  // Daily loss limit: -2% OR 5 consecutive losses
   KILL_SWITCH_MODE_MODERATE      = 2,  // Daily loss limit: -5% OR 10 consecutive losses
   KILL_SWITCH_MODE_AGGRESSIVE    = 3   // Daily loss limit: -10% OR 20 consecutive losses
};

// ===== CORE RISK MANAGEMENT =====
input group "10 | Kill Switch Governance"
input ENUM_KILL_SWITCH_MODE Kill_Switch_Mode     = KILL_SWITCH_MODE_AGGRESSIVE; // Kill switch | Mode preset
input double Kill_Switch_Max_Daily_Loss_Ccy      = 0.0;   // Kill switch | Max daily loss currency

// ===== STRATEGY ROUTING & SIGNAL GATING =====
input group "11 | ICT Entry Gates"
input bool   Require_FVG_For_Trade               = false; // ICT gate | Require FVG
input bool   Require_BOS_Confirmation            = false; // ICT gate | Require BOS
input bool   Require_First_Retracement_After_BOS = false; // ICT gate | Require first retracement
input bool   ICT_Forward_Trend_Only              = false; // ICT gate | Continuation entries only
input bool   Allow_Opposing_Reversal_Trades      = true;  // ICT gate | Allow opposing reversal
input bool   Enable_ICT_Smart_Entry_Validation   = false; // ICT gate | Smart entry validation
input bool   Enable_Entry_Distance_Validation    = false; // Entry gate | Validate entry distance
input bool   Enable_Max_Risk_Distance_Validation = false; // Entry gate | Validate max SL distance
input double ICT_Max_Risk_ATR_Multiple            = 0.0;   // Entry gate | Max ICT SL ATR multiple
input double KImaniz_Max_Risk_ATR_Multiple        = 0.0;   // Entry gate | Max KIM SL ATR multiple
input bool   Enable_Soft_Structural_Gating       = false; // Entry gate | Enable soft structural gate
input int    Max_Soft_Gate_Failures              = 1;     // Entry gate | Max soft-gate failures
input int    Soft_Gate_Min_HTF_Bias_Score        = 3;     // Entry gate | Min HTF bias score
input double Soft_Gate_Extra_RR                  = 0.15;  // Entry gate | Extra RR per soft failure
input double Max_Entry_Distance_Relaxed_Cap      = 3.00;  // Entry gate | Relaxed distance cap

input group "12 | Final Signal Integrity"
input bool   Enable_Final_Integrity_Gate         = false; // Integrity | Enable final gate
input int    Integrity_Min_Aligned_TF            = 3;     // Integrity | Min aligned timeframes
input int    Integrity_Min_HTF_Bias_Score        = 2;     // Integrity | Min HTF bias score
input int    Max_Signal_Age_Seconds              = 180;   // Integrity | Max signal age seconds

input group "13 | Execution Quality"
input bool   Enable_Execution_Latency_Guard      = true;  // Execution | Block stale quotes
input int    Max_Tick_Age_Seconds                = 30;    // Execution | Max quote age seconds
input bool   Enable_Smart_Order_Routing          = true;  // Execution | Convert to pending on slippage
input double Execution_Max_Slippage_Pips         = 50.0;  // Execution | Max slippage pips

input group "14 | Monitoring and Audit"
input bool   Enable_Audit_Log                    = true;  // Audit | Write structured signal log

input group "15 | Gate Families"
input bool   Enable_Spread_Gates      = false; // Gate family | Spread and anomaly gates
input bool   Enable_Session_Gates     = false; // Gate family | Session and time gates
input bool   Enable_Exposure_Gates    = true;  // Gate family | Exposure limit gates

input group "16 | Scoring Engine"
input bool   Enable_All_Institutional_Filters_Input = false; // Scoring | Master institutional filters
input bool   Enable_Dashboard                        = true;  // Scoring | Show chart dashboard
input bool   Enable_Adaptive_Risk                    = false; // Scoring | Enable adaptive risk
input double Execution_Score_Threshold          = 40.0;  // Scoring | Execution threshold
input double Scoring_Precheck_Buffer            = 8.0;   // Scoring | Near-threshold precheck buffer
input bool   Scoring_Enable_Adaptive_Model      = true;  // Scoring | Adaptive threshold and weights
input bool   Scoring_Normalize_Weights          = true;  // Scoring | Normalize weights on init
input double Scoring_Target_Weight_Sum          = 100.0; // Scoring | Target weight sum
input bool   Scoring_Enforce_Unique_Weights     = true;  // Scoring | De-duplicate equal weights
input double Scoring_Unique_Min_Delta           = 0.30;  // Scoring | Minimum weight spacing
input double Scoring_Adaptive_Threshold_Boost   = 15.0;  // Scoring | Drawdown threshold boost
input double Scoring_Adaptive_Risk_Weight_Boost = 0.40;  // Scoring | Stress risk-weight boost
input double Scoring_Adaptive_Opp_Weight_Cut    = 0.30;  // Scoring | Stress opportunity cut

input group "17 | AI Signal Model"
input bool   Enable_AI_Trend_Predictor        = true;  // AI | Enable trend predictor
input ENUM_AI_SIGNAL_GENERATION_MODE AI_Signal_Generation_Mode = AI_SIGNAL_MODE_PRIMARY; // AI | Signal generation mode
input int    AI_Trend_Confidence              = 2;     // AI | Trend confidence step
input bool   AI_Use_Enhanced_Targets          = true;  // AI | Use enhanced targets
input bool   AI_Use_Risk_Adjustment           = true;  // AI | Use risk adjustment
input bool   AI_Require_Agreement             = false; // AI | Require directional agreement
input bool   Enable_External_AI               = true;  // AI | Enable external model
input int    External_AI_Mode                 = 0;     // AI | External mode 0 dual, 1 unified
// File paths moved to #define constants for compile-time configuration
input bool   Enable_AI_Scaler                 = true;  // AI | Enable feature scaler
input bool   Enable_AI_Model_HotReload        = true;  // AI | Hot-reload model and scaler
input int    AI_Model_HotReload_Check_Seconds = 30;    // AI | Hot-reload interval seconds
input double AI_Buy_Confidence_Threshold      = 0.50;  // AI | Buy confidence threshold
input double AI_Sell_Confidence_Threshold     = 0.40;  // AI | Sell confidence threshold
input bool   Allow_Neutral_Trend_Trading      = true;  // AI | Allow neutral-trend trading
input double AI_Neutral_Band                  = 0.02;  // AI | Neutral probability band
input bool   AI_Allow_Relaxed_TieBreak        = true;  // AI | Allow relaxed tie-break
input bool   Enable_AI_MTF_Regime_Filter      = false; // AI | Enable MTF regime filter
input int    AI_Min_Aligned_Structures        = 1;     // AI | Min aligned structures
input int    AI_Max_Opposing_Structures       = 2;     // AI | Max opposing structures
input double AI_Min_Directional_Edge           = 0.0;   // AI | Minimum directional edge
input bool   AI_Enable_EV_Filter              = false; // AI | Require positive expected value
input double AI_Min_Expected_Value_R          = 0.0;   // AI | Min expected value in R
input double AI_Max_Spread_to_ATR             = 1.0;   // AI | Max spread-to-ATR ratio
input double AI_Low_Confidence_Threshold      = 0.55;  // AI | Low-confidence threshold
input double AI_Low_Confidence_Extra_RR       = 0.0;   // AI | Extra RR when confidence is low

input group "18 | AI Candle Quality"
input bool   Enable_AI_Candle_Quality_Filter       = false; // AI candle | Enable quality filter
input int    AI_Candle_Quality_Lookback_Bars       = 2;     // AI candle | Lookback bars
input double AI_Candle_Min_Quality_Score           = 0.0;   // AI candle | Min quality score
input double AI_Candle_Min_Body_Ratio              = 0.30;  // AI candle | Min body ratio
input double AI_Candle_Max_Opposite_Wick_Ratio     = 0.55;  // AI candle | Max opposite wick ratio
input double AI_Candle_ATR_Min_Range_Factor        = 0.20;  // AI candle | Min ATR range factor
input double AI_Candle_ATR_Max_Range_Factor        = 2.40;  // AI candle | Max ATR range factor

input group "19 | AI Training Export"
input bool   Enable_AI_Training_Export            = false;               // AI training | Export bootstrap dataset
input int    AI_Training_Export_Bars              = 200000;              // AI training | Bootstrap bars to export
// AI_Training_Export_File moved to #define AI_TRAINING_EXPORT_FILE for compile-time config
input bool   Enable_AI_Continuous_Training_Export = true;                // AI training | Append live labeled samples
// AI_Continuous_Training_File moved to #define AI_CONTINUOUS_TRAINING_FILE for compile-time config
input bool   AI_Use_Common_Files                  = true;                // AI training | Use common Files folder
input bool   AI_Log_Per_Symbol_Training           = false;               // AI training | Log per-symbol samples

input group "20 | Execution Pipeline"
input int    Signal_Check_Seconds               = 1;      // Pipeline | Signal scan interval seconds
// New unified cadence selector: AUTO = new-bar if possible, else cadence; NEW_BAR_ONLY = strict; CONTINUOUS = every cadence
enum ENUM_SIGNAL_CADENCE_MODE { CADENCE_AUTO = 0, CADENCE_NEW_BAR_ONLY = 1, CADENCE_CONTINUOUS = 2 };
input ENUM_SIGNAL_CADENCE_MODE Signal_Cadence_Mode = CADENCE_CONTINUOUS; // Pipeline | Signal scan cadence mode
input bool   Process_Startup_Seed_Bar          = true;   // Pipeline | Process startup seed bar
input int    Signal_Cooldown_Bars              = 0;      // Pipeline | Symbol cooldown bars
input int    Housekeeping_Interval_Seconds     = 1;      // Pipeline | Housekeeping interval seconds
input int    Housekeeping_Bar_Interval         = 1;      // Pipeline | Housekeeping bar interval
input int    ATR_Handle_Validate_Bars          = 10;     // Pipeline | ATR handle validation bars
input long   Magic_Base                        = 910000; // Pipeline | Base magic number
input int    Max_Spread_Pips                   = 65;     // Pipeline | Fallback max spread pips
input bool   Use_Symbol_Specific_Spreads       = true;   // Pipeline | Use symbol spread table
input bool   Enable_Strategy_DryRun_On_TradeBlock = true; // Pipeline | Keep diagnostics on trade block
input int    Max_Retry_Attempts                = 10;      // Pipeline | Max execution retries
input int    Retry_Interval_Seconds            = 1;       // Pipeline | Retry interval seconds
input int    Max_Queued_Signal_Age_Minutes     = 120;     // Pipeline | Max queued signal age minutes

input group "21 | Orders and Trade Management"
input bool   Use_Pending_Orders               = false; // Orders | Use pending orders
input bool   Enable_Pending_Breakout_Variant = true;  // Orders | Add breakout stop orders
input int    Pending_Trend_Grace_Seconds     = 90;    // Orders | Trend grace seconds
input double Max_Entry_Distance_Pct           = 3.00;  // Orders | Base max entry distance
input bool   Enable_Trailing_Stop             = true;  // Position | Enable trailing stop
input bool   Enable_Partial_Close             = true;  // Position | Enable partial close
input bool   Require_BE_Before_Partial        = true;  // Position | Require breakeven before partial
input double Breakeven_RR                     = 0.9;   // Position | Breakeven trigger RR
input double Partial_Close_RR                 = 2.2;   // Position | Partial-close trigger RR

input group "22 | Core Risk Limits"
input double Risk_Percent                        = 1.00;   // Risk | Base risk per trade percent
input double Final_Per_Trade_Risk_Cap_Pct        = 0.0;    // Risk | Final cap after broker min lot
input double Min_RR_Ratio                        = 1.00;   // Risk | Minimum reward-to-risk ratio
input int    Max_Concurrent_Trades               = 20;     // Risk | Max concurrent trades
input int    Max_Trades_Per_Day                  = 50;     // Risk | Max trades per day
input double ProfitTargetToClose                 = 0.0;    // Risk | Basket profit target currency
input double DrawdownLimitToClose                = 0.0;    // Risk | Basket drawdown close percent
input double PerTrade_Drawdown_Pct               = 0.0;    // Risk | Per-trade drawdown percent
input int    PerTrade_Drawdown_Min_Hold_Seconds  = 420;    // Risk | Per-trade minimum hold seconds
input double PerTrade_Drawdown_Min_Loss_Currency = 1.00;   // Risk | Per-trade minimum loss currency
input double MaxAcceptableDrawdown               = 0.0;    // Risk | Peak-profit pullback currency
input bool   Peak_Drawdown_SL_Protect_Entry      = true;   // Risk | Protect SL at entry or better
input double Peak_Profit_Drawdown_Pct            = 0.0;    // Risk | Peak-profit pullback percent
input double Peak_Profit_Min_R                   = 0.0;    // Risk | Min peak profit in R
input bool   ProfitTarget_Reenter_Trade          = true;   // Risk | Re-enter after profit target
input bool   ProfitTarget_Halt_Bot               = false;  // Risk | Halt after profit target
input int    ProfitTarget_Reentry_Expiry_Minutes = 180;    // Risk | Re-entry expiry minutes
input double Max_Daily_Drawdown_Pct              = 10.0;   // Risk | Daily drawdown cap percent
input double Max_Account_Drawdown_Pct            = 30.0;   // Risk | Account drawdown cap percent
input double Critical_Drawdown_Pct               = 50.0;   // Risk | Critical close-all drawdown

input group "23 | Exposure and Safety Controls"
input bool   Enable_Institutional_Risk = false; // Safety | Enable institutional risk layer
input bool   Risk_Use_Equity            = true; // Safety | Use equity for risk base
input double Max_Open_Risk_Pct          = 100.0; // Exposure | Max open risk percent
input double Max_Symbol_Risk_Pct        = 100.0; // Exposure | Max symbol risk percent
input double Max_Margin_Usage_Pct       = 0.0;   // Exposure | Max margin usage percent
input double Min_Margin_Level_Pct       = 0.0;   // Exposure | Min projected margin level
input int    Max_Consecutive_Losses     = 0;     // Safety | Loss streak before cooldown
input int    Loss_Cooldown_Minutes      = 0;     // Safety | Loss cooldown minutes
input bool   Enable_Symbol_Loss_Circuit_Breaker = false; // Safety | Enable symbol circuit breaker
input int    Symbol_Loss_Streak_Threshold       = 2;    // Safety | Symbol loss streak threshold
input int    Symbol_Loss_Streak_Window_Minutes  = 45;   // Safety | Symbol streak window minutes
input int    Symbol_Loss_Cooldown_Minutes       = 120;  // Safety | Symbol cooldown minutes
input bool   Skip_MinLot_Overrisk       = true;  // Safety | Allow min-lot sizing fallback
input bool   Enable_Abnormal_Market_Pause = false; // Safety | Pause on repeated spread spikes
input int    Abnormal_Spread_Spike_Threshold = 6; // Safety | Spread spike threshold count
input int    Abnormal_Market_Pause_Minutes = 5; // Safety | Abnormal pause minutes
input bool   Disable_Abnormal_Market_Pause_For_Diagnostics = false; // Diagnostics | Disable abnormal pause

input group "24 | Volatility and ATR"
input int    ATR_Period                       = 18;   // ATR | Period
input double ATR_SL_Multiplier                = 2.0;  // ATR | Stop-loss multiplier
input double ATR_TP_Multiplier                = 4.4;  // ATR | Take-profit multiplier
input bool   Enable_Volatility_Adjustment     = true; // Volatility | Enable scaling
input int    Volatility_Lookback_Short        = 8;    // Volatility | Short lookback bars
input int    Volatility_Lookback_Long         = 80;   // Volatility | Long lookback bars
input double Max_Volatility_Adjustment_Factor = 2.4;  // Volatility | Max adjustment factor

input group "25 | Sessions and Activity"
input bool   Use_Session_Filter    = false;  // Session | Enable session filter
input double London_Session_Start  = 7.0;    // Session | London start GMT hour
input double London_Session_End    = 11.8;   // Session | London end GMT hour
input double NewYork_Session_Start = 12.5;   // Session | New York start GMT hour
input double NewYork_Session_End   = 16.8;   // Session | New York end GMT hour
input int    Drought_Alert_Minutes = 45;     // Activity | Drought alert minutes
input int    Drought_Log_Interval  = 10;     // Activity | Drought log interval minutes

input group "26 | Live Profile Overlay"
input ENUM_LIVE_RISK_PROFILE Live_Risk_Profile = LIVE_PROFILE_MAX_PROFIT; // Live | Risk profile overlay
input bool   Live_Profile_Apply_In_Tester = false; // Live | Apply overlay in tester

input group "27 | Strategy Tester"
input ENUM_ICT_SWEEP_PRESET ICT_Sweep_Preset               = ICT_PRESET_CUSTOM; // Tester | ICT sweep preset
input bool                  ICT_Apply_Preset_In_Tester_Only = true;             // Tester | Apply preset only in tester

input group "28 | Alerts and Diagnostics"
input bool   Enable_Backtest_Mode       = false; // Diagnostics | Backtest no-real-trades mode
input bool   Enable_Email_Alerts        = false; // Alerts | Enable email alerts
input bool   Enable_Telegram_Alerts     = false; // Alerts | Enable Telegram alerts
input bool   Enable_Drawdown_Alerts     = true;  // Alerts | Enable drawdown alerts
input string Telegram_Token             = "";    // Alerts | Telegram bot token
input string Telegram_Chat_ID           = "";    // Alerts | Telegram chat ID
input bool   Enable_Institutional_Debug = false; // Diagnostics | Verbose signal logs
input bool   Enable_Manual_Test_Hotkeys = false; // Diagnostics | Manual test hotkeys

input group "29 | Backtest and News"
input bool   Enable_Backtesting_Framework   = true; // Backtest | Enable metrics framework
input int    Backtest_IS_Days               = 30;   // Backtest | In-sample days
input int    Backtest_OOS_Days              = 10;   // Backtest | Out-of-sample days
input int    Backtest_Min_Trades_For_Stats  = 10;   // Backtest | Min trades for stats
input bool   Enable_Economic_Calendar_Filter = false; // News | Enable calendar filter
input int    News_Buffer_Before_Minutes     = 30;   // News | Buffer before minutes
input int    News_Buffer_After_Minutes      = 5;    // News | Buffer after minutes

input group "30 | Logging"
input ENUM_LOG_LEVEL Log_Level = LOG_INFO; // Logging | Verbosity level

enum ENUM_MARKET_STRUCTURE 
{ 
   MARKET_BULLISH, 
   MARKET_BEARISH, 
   MARKET_RANGE 
};

// === PHASE 3: Consolidated Struct Types ===

// Phase 3: Direction weight voting hierarchy (auto-derived from timeframe structure)
struct SDirectionWeights
{
   int trend;
   int confirm;
   int primary;
   int signal;
   
   SDirectionWeights() : trend(3), confirm(2), primary(2), signal(1)
   {
      // Auto-derived from timeframe hierarchy
      // Signal TF (base) = 1, Primary = 2, Confirm = 2, Trend = 3
      // No runtime inputs needed - can be overridden by editing this struct
   }
};

// Phase 3: Consolidated scoring weights with built-in normalization
struct SScoringWeights
{
   double trend;
   double momentum;
   double volatility;
   double structure;
   double alignment;
   double confirmation;
   double risk_reward;
   double entry_quality;
   double spread;
   double regime;
   double total_sum;
   
   SScoringWeights() : 
      trend(20.0),
      momentum(14.0),
      volatility(13.0),
      structure(20.0),
      alignment(7.0),
      confirmation(12.0),
      risk_reward(14.0),
      entry_quality(10.0),
      spread(2.0),
      regime(1.0),
      total_sum(100.0)
   {
      Normalize();
   }
   
   void Normalize()
   {
      double sum = trend + momentum + volatility + structure + 
                   alignment + confirmation + risk_reward + entry_quality + 
                   spread + regime;
      if(sum <= 0) sum = 1.0;
      
      double scale = total_sum / sum;
      trend *= scale;
      momentum *= scale;
      volatility *= scale;
      structure *= scale;
      alignment *= scale;
      confirmation *= scale;
      risk_reward *= scale;
      entry_quality *= scale;
      spread *= scale;
      regime *= scale;
   }
};

// Phase 3: Symbol-specific configuration (extensible for multi-symbol support)
struct SSymbolConfig
{
   string symbol;
   int max_spread_pips;
   double net_spread_limit_pips;
   double spread_tighten_factor;
   
   SSymbolConfig(string sym = "XAUUSD") : symbol(sym), max_spread_pips(73), 
                                          net_spread_limit_pips(100.0), 
                                          spread_tighten_factor(1.00)
   {
      // Symbol-specific defaults (can be extended for additional symbols)
      if(StringFind(symbol, "GOLD") >= 0 || StringFind(symbol, "XAUUSD") >= 0)
      {
         max_spread_pips = 65;
         net_spread_limit_pips = 55.0;
         spread_tighten_factor = 1.00;
      }
   }
};

struct SSymbolCache
{
   double    bid;
   double    ask;
   double    point;
   int       digits;
   long      spread;
   double    spread_avg_points;
   int       spread_avg_samples;
   datetime  last_update;
   MqlRates  last_rates[];
   datetime  last_rates_update;
   datetime  last_rates_bar_time;
   ENUM_TIMEFRAMES last_rates_tf;
   long      last_rates_tick_msc;
   datetime  last_tick_time;
   long      last_tick_msc;
   
   SSymbolCache() : 
      bid(0.0),
      ask(0.0),
      point(0.0),
      digits(0),
      spread(0),
      spread_avg_points(0.0),
      spread_avg_samples(0),
      last_update(0),
      last_rates_update(0),
      last_rates_bar_time(0),
      last_rates_tf(PERIOD_CURRENT),
      last_rates_tick_msc(0),
      last_tick_time(0),
      last_tick_msc(0)
   {}
};

struct SSymbolData
{
   string          name;
   int             atr_handle;
   datetime        last_signal_time;
   datetime        last_signal_bar;
   datetime        last_bar_time;
   datetime        last_processed_time;
   datetime        last_housekeeping_bar;
   datetime        last_atr_validate_bar;
   SSymbolCache    cache;
   bool            copying_atr;
   datetime        last_copy_time;
   int             positions_count;
   datetime        last_position_open;
   
   SSymbolData() :
      atr_handle(INVALID_HANDLE),
      last_signal_time(0),
      last_signal_bar(0),
      last_bar_time(0),
      last_processed_time(0),
      last_housekeeping_bar(0),
      last_atr_validate_bar(0),
      copying_atr(false),
      last_copy_time(0),
      positions_count(0),
      last_position_open(0)
   {}
};

// FIX #1: Quote timestamp validation struct
struct SQuoteSnapshot
{
   double bid;
   double ask;
   int timestamp_ms;     // GetTickCount() milliseconds
   int max_age_ms;       // max acceptable age
   datetime tick_time;    // broker tick timestamp
   
   SQuoteSnapshot() : bid(0), ask(0), timestamp_ms(0), max_age_ms(500), tick_time(0) {}
   
   bool IsStale() const {
      if(tick_time > 0)
      {
         int server_age = (int)(TimeCurrent() - tick_time);
         int max_age_seconds = MathMax(1, (max_age_ms + 999) / 1000);
         if(server_age > max_age_seconds)
            return true;
      }
      int age = (int)(GetTickCount() - timestamp_ms);
      return (age > max_age_ms);
   }
};

struct STradeRetry
{
   string          symbol;
   STradingSignal  signal;
   int             attempt;
   datetime        next_retry;
   datetime        created_time;
   int             symbol_index;
   ulong           signal_fingerprint;
   // FIX #3: Pending order ticket tracking
   ulong           ticket;
   bool            order_placed;
   datetime        last_ticket_check_time;
    
   STradeRetry() :
      attempt(0),
      symbol_index(-1),
      next_retry(0),
      created_time(0),
      signal_fingerprint(0),
      ticket(0),
      order_placed(false),
      last_ticket_check_time(0)
   {}
};

struct SIndicatorCache
{
   int handle;
   ENUM_TIMEFRAMES tf;
   int period;
   datetime created_time;
};

struct SAdaptiveRiskCache
{
   double risk;
   datetime last_calc;
   int wins;
   int losses;
};

struct SSymbolHashIndex
{
   int symbol_index;
};

struct SSymbolCacheMetadata
{
   datetime last_accessed;
   int access_count;
};

struct STemporaryIndicatorCache
{
   int handle;
   ENUM_TIMEFRAMES tf;
   int period;
   datetime created_time;
};

struct SLogBuffer
{
   string messages[1000];
   int count;
};
SLogBuffer g_log_buffer;



bool Enable_All_Institutional_Filters = Enable_All_Institutional_Filters_Input;
bool g_Disable_All_Gates = Disable_All_Gating_Master_Switch;
bool g_Enable_Spread_Gates = Enable_Spread_Gates;
bool g_Enable_Session_Gates = Enable_Session_Gates;
bool g_Enable_Exposure_Gates = Enable_Exposure_Gates;
ENUM_KILL_SWITCH_MODE g_Kill_Switch_Mode = Kill_Switch_Mode;
double g_Kill_Switch_Max_Daily_Loss_Ccy = Kill_Switch_Max_Daily_Loss_Ccy;
bool g_Use_Symbol_Specific_Spreads = Use_Symbol_Specific_Spreads;
bool g_Enable_Final_Integrity_Gate = Enable_Final_Integrity_Gate;
int g_Integrity_Min_Aligned_TF = Integrity_Min_Aligned_TF;
int g_Integrity_Min_HTF_Bias_Score = Integrity_Min_HTF_Bias_Score;
int g_Max_Signal_Age_Seconds = Max_Signal_Age_Seconds;
bool g_Enable_Execution_Latency_Guard = Enable_Execution_Latency_Guard;
int g_Max_Tick_Age_Seconds = Max_Tick_Age_Seconds;
bool g_Enable_Smart_Order_Routing = Enable_Smart_Order_Routing;
double g_Execution_Max_Slippage_Pips = Execution_Max_Slippage_Pips;
bool g_Enable_Audit_Log = Enable_Audit_Log;
// Canonical runtime flags to consolidate overlapping/deprecated parameter paths.
bool g_Enable_Confluence_Check = Enable_Confluence_Check;
bool g_Enable_HTF_Bias_Check = Enable_HTF_Bias_Check;
bool g_Enable_AI_Trend_Predictor_Runtime = Enable_AI_Trend_Predictor;
bool g_AI_Require_Agreement_Runtime = AI_Require_Agreement;
bool g_AI_Use_Enhanced_Targets_Runtime = AI_Use_Enhanced_Targets;
bool g_AI_Use_Risk_Adjustment_Runtime = AI_Use_Risk_Adjustment;
bool g_Enable_ICT_Strategy = (Strategy_Mix != STRAT_AI_ONLY &&
                              Strategy_Mix != STRAT_KIM_ONLY &&
                              Strategy_Mix != STRAT_AI_KIM);
bool g_Enable_AI_Strategy = (Strategy_Mix != STRAT_ICT_ONLY &&
                             Strategy_Mix != STRAT_KIM_ONLY &&
                             Strategy_Mix != STRAT_ICT_KIM);
bool g_Enable_Institutional_Risk = (Enable_All_Institutional_Filters && Enable_Institutional_Risk);

bool g_Use_Session_Filter = Use_Session_Filter;
double g_London_Session_Start = London_Session_Start;
double g_London_Session_End = London_Session_End;
double g_NewYork_Session_Start = NewYork_Session_Start;
double g_NewYork_Session_End = NewYork_Session_End;
bool g_Use_Trend_Filter = Use_Trend_Filter;
bool g_Allow_Range_Trading = Allow_Range_Trading;
bool g_Allow_Neutral_Trend_Trading = Allow_Neutral_Trend_Trading;
bool g_Use_ADX_For_Trend = Use_ADX_For_Trend;
double g_Strong_Trend_ADX_Level = Strong_Trend_ADX_Level;
double g_Weak_Trend_ADX_Level = Weak_Trend_ADX_Level;
int g_Trend_Lookback_Bars = Trend_Lookback_Bars;
int g_Order_Block_Lookback = Order_Block_Lookback;
int g_Order_Block_Confirmation = Order_Block_Confirmation;
double g_Min_Order_Block_Size = Min_Order_Block_Size;
bool g_Use_Advanced_OB_Detection = Use_Advanced_OB_Detection;
double g_OB_Max_Proximity_Pct = OB_Max_Proximity_Pct;
double g_Min_FVG_Size_Ratio = Min_FVG_Size_Ratio;
bool g_Use_FVG_Detection = Use_FVG_Detection;
bool g_Require_FVG_For_Trade = Require_FVG_For_Trade;
bool g_Require_BOS_Confirmation = Require_BOS_Confirmation;
bool g_Require_First_Retracement_After_BOS = Require_First_Retracement_After_BOS;
bool g_ICT_Forward_Trend_Only = ICT_Forward_Trend_Only;
bool g_Allow_Opposing_Reversal_Trades = Allow_Opposing_Reversal_Trades;
bool g_Enable_Soft_Structural_Gating = Enable_Soft_Structural_Gating;
bool g_Enable_ICT_Smart_Entry_Validation = Enable_ICT_Smart_Entry_Validation;
bool g_Enable_Entry_Distance_Validation = Enable_Entry_Distance_Validation;
bool g_Enable_Max_Risk_Distance_Validation = Enable_Max_Risk_Distance_Validation;
double g_ICT_Max_Risk_ATR_Multiple = ICT_Max_Risk_ATR_Multiple;
double g_KImaniz_Max_Risk_ATR_Multiple = KImaniz_Max_Risk_ATR_Multiple;
int g_Max_Soft_Gate_Failures = Max_Soft_Gate_Failures;
int g_Soft_Gate_Min_HTF_Bias_Score = Soft_Gate_Min_HTF_Bias_Score;
double g_Soft_Gate_Extra_RR = Soft_Gate_Extra_RR;
double g_Max_Entry_Distance_Relaxed_Cap = Max_Entry_Distance_Relaxed_Cap;
int g_FVG_Lookback_Bars = FVG_Lookback_Bars;
double g_Min_RR_Ratio = Min_RR_Ratio;
bool g_Enable_Volatility_Adjustment = Enable_Volatility_Adjustment;
int g_Volatility_Lookback_Short = Volatility_Lookback_Short;
int g_Volatility_Lookback_Long = Volatility_Lookback_Long;
double g_Max_Volatility_Adjustment_Factor = Max_Volatility_Adjustment_Factor;
bool g_Enable_Trailing_Stop = Enable_Trailing_Stop;
bool g_Enable_Partial_Close = Enable_Partial_Close;
double g_Partial_Close_RR = Partial_Close_RR;
bool g_Require_BE_Before_Partial = Require_BE_Before_Partial;
double g_Breakeven_RR = Breakeven_RR;
bool g_Use_Pending_Orders = Use_Pending_Orders;
bool g_Skip_MinLot_Overrisk = Skip_MinLot_Overrisk;
double g_Max_Entry_Distance_Pct = Max_Entry_Distance_Pct;
bool g_Signal_On_New_Bar_Only = (Signal_Cadence_Mode == CADENCE_NEW_BAR_ONLY);
bool g_Force_Signal_Cadence_Gate_Off = (Signal_Cadence_Mode == CADENCE_CONTINUOUS);
bool g_Process_Startup_Seed_Bar = Process_Startup_Seed_Bar;
int g_Signal_Cooldown_Bars = Signal_Cooldown_Bars;
bool g_Enable_Adaptive_Risk = (Enable_All_Institutional_Filters && Enable_Adaptive_Risk);
bool g_Enable_Dashboard = (Enable_All_Institutional_Filters && Enable_Dashboard);
bool g_AI_Use_Common_Files = AI_Use_Common_Files;
double g_AI_Neutral_Band = AI_Neutral_Band;
double g_AI_Buy_Confidence_Threshold = AI_Buy_Confidence_Threshold;
double g_AI_Sell_Confidence_Threshold = AI_Sell_Confidence_Threshold;
bool g_AI_Allow_Relaxed_TieBreak = AI_Allow_Relaxed_TieBreak;
bool g_Enable_AI_MTF_Regime_Filter = Enable_AI_MTF_Regime_Filter;
int g_AI_Min_Aligned_Structures = AI_Min_Aligned_Structures;
int g_AI_Max_Opposing_Structures = AI_Max_Opposing_Structures;
double g_AI_Min_Directional_Edge = AI_Min_Directional_Edge;
bool g_AI_Enable_EV_Filter = AI_Enable_EV_Filter;
double g_AI_Min_Expected_Value_R = AI_Min_Expected_Value_R;
double g_AI_Max_Spread_to_ATR = AI_Max_Spread_to_ATR;
double g_AI_Low_Confidence_Threshold = AI_Low_Confidence_Threshold;
double g_AI_Low_Confidence_Extra_RR = AI_Low_Confidence_Extra_RR;
bool g_Enable_AI_Candle_Quality_Filter = Enable_AI_Candle_Quality_Filter;
int g_AI_Candle_Quality_Lookback_Bars = AI_Candle_Quality_Lookback_Bars;
double g_AI_Candle_Min_Quality_Score = AI_Candle_Min_Quality_Score;
double g_AI_Candle_Min_Body_Ratio = AI_Candle_Min_Body_Ratio;
double g_AI_Candle_Max_Opposite_Wick_Ratio = AI_Candle_Max_Opposite_Wick_Ratio;
double g_AI_Candle_ATR_Min_Range_Factor = AI_Candle_ATR_Min_Range_Factor;
double g_AI_Candle_ATR_Max_Range_Factor = AI_Candle_ATR_Max_Range_Factor;
ENUM_AI_SIGNAL_GENERATION_MODE g_AI_Signal_Generation_Mode = AI_Signal_Generation_Mode;
ENUM_STRATEGY_ROUTING_MODE g_Strategy_Routing_Mode =
   (Strategy_Mix == STRAT_ICT_ONLY ? STRATEGY_ROUTING_ICT_ONLY :
    Strategy_Mix == STRAT_AI_ONLY ? STRATEGY_ROUTING_AI_ONLY :
    Strategy_Mix == STRAT_BOTH ? STRATEGY_ROUTING_BOTH :
    STRATEGY_ROUTING_EITHER);
bool g_Use_Institutional_Strategy_Director = Use_Institutional_Strategy_Director;
bool g_AI_Log_Per_Symbol_Training = AI_Log_Per_Symbol_Training;
string g_Audit_Log_File = AUDIT_LOG_FILE;
double g_Director_BaseLot = Director_BaseLot;
int g_Director_ATR_Period = Director_ATR_Period;
int g_Director_FastMA = Director_FastMA;
int g_Director_SlowMA = Director_SlowMA;
bool g_Enable_Auto_Regime_Router = Enable_Auto_Regime_Router;
int g_Auto_Regime_Strong_Bias_MinScore = Auto_Regime_Strong_Bias_MinScore;
double g_Auto_Regime_Intra_HighLow_MaxVolatility = Auto_Regime_Intra_HighLow_MaxVolatility;
ENUM_SUITABILITY_HUNT_MODE g_Suitability_Hunt_Mode = Suitability_Hunt_Mode;
bool g_Suitability_Allow_CrossRole_Fallbacks = Suitability_Allow_CrossRole_Fallbacks;
bool g_Suitability_Trend_Require_Confluence_On_Weak_Bias = Suitability_Trend_Require_Confluence_On_Weak_Bias;
int g_Suitability_Weak_Bias_MaxScore = Suitability_Weak_Bias_MaxScore;
double g_Suitability_High_Volatility_Factor = Suitability_High_Volatility_Factor;
double g_Regime_Risk_Multiplier_Trend = Regime_Risk_Multiplier_Trend;
double g_Regime_Risk_Multiplier_Range = Regime_Risk_Multiplier_Range;
double g_Regime_Risk_Multiplier_Retracement = Regime_Risk_Multiplier_Retracement;
ENUM_STRATEGY_MIX g_Strategy_Mix_Effective = Strategy_Mix;
bool g_Allow_AI_Fallback_In_BOTH_Mode = Allow_AI_Fallback_In_BOTH_Mode;
bool g_Allow_ICT_Fallback_In_BOTH_Mode = Allow_ICT_Fallback_In_BOTH_Mode;
bool g_Enable_KImaniz_Strategy = Enable_KImaniz_Strategy;
bool g_KImaniz_Only_Mode = (Strategy_Mix == STRAT_KIM_ONLY);
bool g_KImaniz_Allow_Countertrend_With_HTF_Gate = KImaniz_Allow_Countertrend_With_HTF_Gate;
int g_KImaniz_Swing_Lookback_Bars = KImaniz_Swing_Lookback_Bars;
double g_KImaniz_Fib_Zone_29_Pct = KImaniz_Fib_Zone_29_Pct;
double g_KImaniz_Fib_Zone_41_Pct = KImaniz_Fib_Zone_41_Pct;
double g_KImaniz_OTP_Low_Pct = KImaniz_OTP_Low_Pct;
double g_KImaniz_OTP_Mid_Pct = KImaniz_OTP_Mid_Pct;
double g_KImaniz_OTP_High_Pct = KImaniz_OTP_High_Pct;
double g_KImaniz_Entry_Zone_Tolerance_Pct = KImaniz_Entry_Zone_Tolerance_Pct;
bool g_Enable_Pending_Breakout_Variant = Enable_Pending_Breakout_Variant;
int g_Pending_Trend_Grace_Seconds = Pending_Trend_Grace_Seconds;
bool g_Enable_Institutional_Debug = Enable_Institutional_Debug;
bool g_Enable_Abnormal_Market_Pause = Enable_Abnormal_Market_Pause;
int g_Abnormal_Spread_Spike_Threshold = Abnormal_Spread_Spike_Threshold;
int g_Abnormal_Market_Pause_Minutes = Abnormal_Market_Pause_Minutes;
bool g_Enable_Strategy_DryRun_On_TradeBlock = Enable_Strategy_DryRun_On_TradeBlock;
bool g_Disable_Abnormal_Market_Pause_For_Diagnostics = Disable_Abnormal_Market_Pause_For_Diagnostics;
bool g_DryRun_TradeBlock_Active = false;
bool g_Kill_Switch_Active = false;
datetime g_Kill_Switch_Activated_Time = 0;
string g_Kill_Switch_Reason = "";
bool g_Kill_Switch_Daily_Loss_Latched = false;
double g_Kill_Switch_Trigger_Loss_Pct = 0.0;
double g_Kill_Switch_Trigger_Limit_Pct = 0.0;
double g_Kill_Switch_Trigger_Day_Start_Equity = 0.0;
int g_kill_switch_triggers = 0;
bool g_Bot_Halt_Active = false;
datetime g_Bot_Halt_Activated_Time = 0;
string g_Bot_Halt_Reason = "";

// Risk core runtime mirrors
double g_Risk_Percent = Risk_Percent;
double g_Final_Per_Trade_Risk_Cap_Pct = Final_Per_Trade_Risk_Cap_Pct;
double g_ProfitTargetToClose = ProfitTargetToClose;
double g_DrawdownLimitToClose = DrawdownLimitToClose;
double g_PerTrade_Drawdown_Pct = PerTrade_Drawdown_Pct;
int    g_PerTrade_Drawdown_Min_Hold_Seconds = PerTrade_Drawdown_Min_Hold_Seconds;
double g_PerTrade_Drawdown_Min_Loss_Currency = PerTrade_Drawdown_Min_Loss_Currency;
double g_MaxAcceptableDrawdown = MaxAcceptableDrawdown;
bool   g_Peak_Drawdown_SL_Protect_Entry = Peak_Drawdown_SL_Protect_Entry;
double g_Peak_Profit_Drawdown_Pct = Peak_Profit_Drawdown_Pct;
double g_Peak_Profit_Min_R = Peak_Profit_Min_R;
bool   g_ProfitTarget_Reenter_Trade = ProfitTarget_Reenter_Trade;
bool   g_ProfitTarget_Halt_Bot = ProfitTarget_Halt_Bot;
int    g_ProfitTarget_Reentry_Expiry_Minutes = ProfitTarget_Reentry_Expiry_Minutes;
double g_Max_Daily_Drawdown_Pct = Max_Daily_Drawdown_Pct;
bool   g_Enable_Symbol_Loss_Circuit_Breaker = Enable_Symbol_Loss_Circuit_Breaker;
int    g_Symbol_Loss_Streak_Threshold = Symbol_Loss_Streak_Threshold;
int    g_Symbol_Loss_Streak_Window_Minutes = Symbol_Loss_Streak_Window_Minutes;
int    g_Symbol_Loss_Cooldown_Minutes = Symbol_Loss_Cooldown_Minutes;
ENUM_ICT_SWEEP_PRESET g_ICT_Sweep_Preset_Effective = ICT_PRESET_CUSTOM;
string g_ICT_Sweep_Preset_Name = "Custom";
double g_Execution_Score_Threshold_Effective = Execution_Score_Threshold;
double g_Risk_Percent_Effective = Risk_Percent;
int g_Max_Concurrent_Trades_Effective = Max_Concurrent_Trades;
int g_Max_Trades_Per_Day_Effective = Max_Trades_Per_Day;
int g_Max_Spread_Pips_Effective = Max_Spread_Pips;
int g_ATR_Period_Active = ATR_Period;
double g_ATR_SL_Multiplier_Active = ATR_SL_Multiplier;
double g_ATR_TP_Multiplier_Active = ATR_TP_Multiplier;
int g_Max_Queued_Signal_Age_Minutes = Max_Queued_Signal_Age_Minutes;
int g_Max_Retry_Attempts = Max_Retry_Attempts;
int g_Retry_Interval_Seconds = Retry_Interval_Seconds;
int g_Liquidity_Level_Lookback_Active = Liquidity_Level_Lookback;
double g_Liquidity_Tolerance_ATR_Multiple_Active = Liquidity_Tolerance_ATR_Multiple;
double g_Max_Open_Risk_Pct_Effective = Max_Open_Risk_Pct;
double g_Max_Symbol_Risk_Pct_Effective = Max_Symbol_Risk_Pct;
double g_Max_Daily_Drawdown_Pct_Effective = Max_Daily_Drawdown_Pct;
double g_Max_Account_Drawdown_Pct_Effective = Max_Account_Drawdown_Pct;
double g_Critical_Drawdown_Pct_Effective = Critical_Drawdown_Pct;
double g_PerTrade_Drawdown_Pct_Effective = PerTrade_Drawdown_Pct;
ENUM_LIVE_RISK_PROFILE g_Live_Risk_Profile_Effective = LIVE_PROFILE_MAX_PROFIT;
string g_Live_Risk_Profile_Name = "Max Profit";
string g_Gate_Profile_Name = "Standard";
string g_Risk_Tier_Profile_Name = "Balanced";
string g_Timeframe_Preset_Name = "Standard";
bool g_Timeframe_Preset_Aligned = true;

// Phase 3 Global Struct Instances - Consolidated Configuration
SDirectionWeights g_direction_weights;            // Auto-derived voting hierarchy
SScoringWeights g_scoring_weights;                // Consolidated scoring weights with normalization
SSymbolConfig g_symbol_config;                    // Symbol-specific configuration

ScoringEngine g_scoring_engine;

CReversalDetector g_reversal_detector;

CTrade trade;
CAccountInfo account_info;
CPositionInfo position_info;
COrderInfo order_info;

SIndicatorCache g_atr_temp_cache[MAX_SYMBOLS];
SAdaptiveRiskCache g_risk_cache = {Risk_Percent, 0, 0, 0};
SSymbolHashIndex g_symbol_hash_table[157];  // Prime number for hash table
STemporaryIndicatorCache g_temp_indicators[MAX_SYMBOLS];
SSymbolCacheMetadata g_cache_metadata[MAX_SYMBOLS];
bool g_timer_active = false;

int g_rsi_handle = INVALID_HANDLE;


struct SCachedRatesData
{
   MqlRates rates[];
   datetime last_update;
   ENUM_TIMEFRAMES tf;
   int count;
} g_cached_rates_main;





struct SCachedStructure
{
   ENUM_MARKET_STRUCTURE value;
   datetime last_update;
   ENUM_TIMEFRAMES tf;
} g_structure_cache[MAX_SYMBOLS][MAX_TF_CACHE];
datetime g_structure_calc_time[MAX_SYMBOLS][MAX_TF_CACHE];
int g_structure_slot_map[MAX_SYMBOLS][4]; // maps core TF index -> slot in g_structure_cache
int g_bias_slot_map[MAX_SYMBOLS][4];      // maps core TF index -> slot for bias cache

// Helper RAII lock for ProcessSignals
struct auto_release_lock
{
   bool held;
   auto_release_lock(bool h): held(h) {}
   ~auto_release_lock(){ if(held) ReleaseProcessingLock(); }
};

struct SPositionCountCache
{
   int count;
   datetime last_bar;
} g_position_cache[MAX_SYMBOLS];

struct SGlobalPositionCountCache
{
   int count_per_symbol[MAX_SYMBOLS];
   datetime last_update;
} g_position_count_cache;

struct SVolatilityCacheEntry
{
   double factor;
   datetime last_bar_time;
   datetime last_update;
   long last_tick_msc;
} g_volatility_cache[MAX_SYMBOLS];

AIPredictionCache g_ai_prediction_cache[MAX_SYMBOLS];

struct SAICacheManager
{
   datetime last_cleanup;
   int max_cache_age;
   int cleanup_interval;
};
SAICacheManager g_ai_cache_manager = {0, 3600, 300}; // 1 hour max age, 5 min cleanup

struct SIndicatorCacheEntry
{
   double rsi_value;
   datetime last_bar_time;
   bool is_valid;
} g_indicator_cache[MAX_SYMBOLS][4]; // 4 timeframes: Signal(0), Primary(1), Confirm(2), Trend(3)

struct SMomentumCache
{
   double macd;
   double stoch;
   datetime bar_time;
   bool valid;
} g_momentum_cache[MAX_SYMBOLS][4]; // per-symbol, per-core-TF momentum cache

datetime g_startup_time = 0;  // NEW: Track bot startup time for orphan detection
datetime g_trade_day = 0;
int g_trades_today = 0;
double g_equity_day_start = 0.0;
double g_equity_all_time_high = 0.0;
int g_consecutive_losses = 0;
int g_consecutive_wins = 0;
datetime g_risk_cooldown_until = 0;
datetime g_market_pause_until = 0;
datetime g_drawdown_pause_until = 0;
int g_spread_spike_count[MAX_SYMBOLS];
int g_symbol_loss_streak[MAX_SYMBOLS];
datetime g_symbol_last_loss_time[MAX_SYMBOLS];
datetime g_symbol_loss_cooldown_until[MAX_SYMBOLS];

SSymbolData g_symbols[MAX_SYMBOLS];
STradeRetry g_trade_retries[MAX_RETRY_QUEUE];
int g_symbols_count = 0;
int g_retry_count = 0;

datetime g_last_process_time = 0;
string g_chart_symbol = "";

bool g_initialization_complete = false;
datetime g_initialization_time = 0;
const int INITIALIZATION_COOLDOWN_SECONDS = 30; // 30 second cooldown after init

AIManager g_ai_manager;
bool g_ai_enabled = true;
bool g_external_ai_ready = false;
int g_external_ai_mode_runtime = 0;
bool g_external_ai_allowed = false;
int g_ai_training_bars = 0;
int g_ai_signals_confirmed = 0;      // Track AI confirmed signals
int g_ai_signals_disagreed = 0;      // Track AI disagreements
int g_ai_high_confidence_trades = 0; // Trades with >75% AI confidence
datetime g_ai_last_continuous_export_time[MAX_SYMBOLS];

AIPerformanceStats g_ai_performance = {0.0, 0, 0, false};
AIPerformanceStats g_ai_performance_by_symbol[MAX_SYMBOLS];
int g_ai_cache_requests = 0;
int g_ai_cache_hits = 0;
int g_ai_cache_misses = 0;

struct SAIFeatureCache
{
   double rsi_value;
   double ma_slope;
   double atr_value;
   double volume_ratio;
   datetime bar_time;
   datetime last_update;
   long last_tick_msc;
   ENUM_TIMEFRAMES tf;
   bool is_valid;
};
SAIFeatureCache g_ai_feature_cache[MAX_SYMBOLS];



int g_debug_signal_count = 0;
int g_debug_errors = 0;
int g_debug_trades_executed = 0;
int g_debug_trades_failed = 0;
int g_exec_latency_blocks = 0;
int g_exec_slippage_reroutes = 0;
int g_exec_slippage_violations = 0;
string g_last_position_size_reason = "";
double g_last_position_size_raw_lot = 0.0;
double g_last_position_size_min_lot = 0.0;

bool g_processing_signals = false;
static datetime g_lock_acquisition_time = 0;  // Track when lock was acquired (Issue 1.1)

string g_tf_names[STRATEGY_TF_SLOTS];



bool g_debug_signals_enabled = false;
bool g_debug_trades_enabled = false;

struct SDebugCounters
{
   int signals_generated;
   int signals_valid;
   int signals_rejected;
   int trades_queued;
   int trades_executed;
   int trades_failed;
   datetime last_reset;
};
SDebugCounters g_debug_counters = {0, 0, 0, 0, 0, 0, 0};

#define MAX_REJECT_REASON_BUCKETS 64
string g_reject_reason_keys[MAX_REJECT_REASON_BUCKETS];
int g_reject_reason_counts[MAX_REJECT_REASON_BUCKETS];
string g_last_reject_reason_key = "";
datetime g_last_reject_reason_time = 0;

int g_htf_bias_cache[MAX_SYMBOLS][MAX_TF_CACHE];
datetime g_htf_bias_cache_time[MAX_SYMBOLS][MAX_TF_CACHE];
datetime g_htf_bias_calc_time[MAX_SYMBOLS][MAX_TF_CACHE];

struct SATRCacheEntry
{
   double value;
   datetime bar_time;
   ENUM_TIMEFRAMES tf;
   int period;
   datetime last_used;
} g_atr_cache[MAX_SYMBOLS][MAX_ATR_CACHE];

datetime g_last_valid_signal_time = 0;
datetime g_last_trade_time = 0;
datetime g_last_drought_alert = 0;


const double EPSILON_SMALL = 1e-10;      // For denominator checks
const double EPSILON_SUBNORMAL = 1e-308; // Subnormal number threshold
const double EPSILON_LARGE = 1e308;      // Large number threshold


struct SIndicatorPool
{
   int handle;
   string symbol;
   ENUM_TIMEFRAMES tf;
   int period;
   string type;
   datetime last_used;
   bool in_use;
};
SIndicatorPool g_indicator_pool[20]; // Pool of 20 handles

struct SFallbackHandle
{
   int handle;
   datetime created_time;
   string symbol;
   ENUM_TIMEFRAMES tf;
   int period;
   string type;
};
SFallbackHandle g_fallback_handles[10]; // Track up to 10 fallback handles
int g_fallback_count = 0;

struct SNormalizedPrices
{
   double entry;
   double stop_loss;
   double take_profit;
};


int g_buy_signals_count = 0;
int g_sell_signals_count = 0;
int g_reversal_signals_count = 0;
int g_reversal_confirmed_count = 0;
int g_reversal_override_count = 0;
int g_Signal_Stats_ICT_Total_Attempts = 0;
int g_Signal_Stats_ICT_Valid = 0;
int g_Signal_Stats_AI_Total_Attempts = 0;
int g_Signal_Stats_AI_Valid = 0;
int g_Signal_Stats_KIM_Total_Attempts = 0;
int g_Signal_Stats_KIM_Valid = 0;

// Forward declarations for cross-module reject telemetry.
void RecordRejectReason(string reason);
string GetTopRejectReasonsSummary(int top_n);

#include "Utils.mqh"
#ifndef EXTERNAL_AI_DLL_ENABLED
   #define EXTERNAL_AI_DLL_ENABLED
#endif
#include "AIExternalDLL.mqh"
#include "AIScaler.mqh"
#include "SymbolManagement.mqh"
#include "Validation.mqh"
#include "IndicatorsCache.mqh"
#include "TrainingDataExport.mqh"
#include "MarketAnalysis.mqh"
#include "AICandleQualityFilter.mqh"
#include "RiskSession.mqh"
#include "Dashboard.mqh"
#include "TradeManagement.mqh"
#include "StrategyRouter.mqh"
#include "InstitutionalStrategyDirector.mqh"
#include "SignalGeneration.mqh"
#include "ICTStrategy.mqh"
#include "KImanizStrategy.mqh"
#include "Diagnostics.mqh"
#include "MainLifecycle.mqh"

#endif // PROFITTRAILBOT_MQ5
