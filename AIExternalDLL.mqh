#ifndef AI_EXTERNAL_DLL_MQH
#define AI_EXTERNAL_DLL_MQH

#include "Utils.mqh"
#include "AIScaler.mqh"

// Forward declarations for runtime variables (input params are implicitly global)
extern int g_external_ai_mode_runtime;
extern bool g_external_ai_allowed;
extern bool g_external_ai_ready;
extern bool g_Enable_AI_Trend_Predictor_Runtime;

// External ML DLL bindings (LightGBM/XGBoost via local DLL)
#ifdef EXTERNAL_AI_DLL_ENABLED
#import "ProfitTrailAI.dll"
   int    PTB_LoadModelSlot(string model_path, int slot);
   double PTB_PredictSlot(double &features[], int feature_count, int slot);
   int    PTB_PredictMulti(double &features[], int feature_count, double &out_probs[], int out_count, int slot);
   int    PTB_GetFeatureImportance(double &out_values[], int out_count, int slot);
   void   PTB_FreeModelSlot(int slot);
#import
#else
int PTB_LoadModelSlot(string model_path, int slot) { return 0; }
double PTB_PredictSlot(double &features[], int feature_count, int slot) { return 0.5; }
int PTB_PredictMulti(double &features[], int feature_count, double &out_probs[], int out_count, int slot) { return 0; }
int PTB_GetFeatureImportance(double &out_values[], int out_count, int slot) { return 0; }
void PTB_FreeModelSlot(int slot) { }
#endif

string NormalizePathForDLL(string path)
{
   string out = path;
   StringReplace(out, "/", "\\");
   return out;
}

bool IsAbsolutePathForDLL(string path)
{
   string p = NormalizePathForDLL(path);
   if(StringLen(p) >= 2 && StringSubstr(p, 1, 1) == ":") return true; // C:\...
   if(StringLen(p) >= 2 && StringSubstr(p, 0, 2) == "\\\\") return true; // UNC path
   return false;
}

string ResolveFilesPathForDLL(string path_in_files)
{
   string p = NormalizePathForDLL(path_in_files);
   if(IsAbsolutePathForDLL(p))
      return p;

   // Remove leading slashes to keep it relative to MQL5\Files
   while(StringLen(p) > 0)
   {
      int ch = StringGetCharacter(p, 0);
      if(ch != '\\' && ch != '/')
         break;
      p = StringSubstr(p, 1);
   }

   string base = TerminalInfoString(TERMINAL_DATA_PATH);
   base = NormalizePathForDLL(base);
   if(StringLen(base) > 0 && StringSubstr(base, StringLen(base) - 1, 1) != "\\")
      base += "\\";

   return base + "MQL5\\Files\\" + p;
}

bool SanitizeAIFeatureInputs(double &close0, double &close1, double &close5, double &atr,
                             double &rsi, double &ma_slope, double &vol0, double &vol1,
                             double &vol_avg, double &macd, double &stoch, double &sentiment,
                             double &spread, double &htf_bias, double &vol_regime)
{
   // Critical validations
   if(!MathIsValidNumber(close0) || close0 <= 0.0) return false;
   if(!MathIsValidNumber(close1) || close1 <= 0.0) return false;
   if(!MathIsValidNumber(close5) || close5 <= 0.0) return false;
   if(!MathIsValidNumber(atr) || atr <= 0.0 || atr > (close0 * 0.5)) return false;

   // Soft validations with clamping/normalization
   if(!MathIsValidNumber(rsi) || rsi < 0.0 || rsi > 100.0) rsi = 50.0;
   if(!MathIsValidNumber(stoch) || stoch < 0.0 || stoch > 100.0) stoch = 50.0;

   if(!MathIsValidNumber(ma_slope))
      ma_slope = 0.0;
   else if(MathAbs(ma_slope) > close0 * 0.1)
      ma_slope = MathClamp(ma_slope, -close0 * 0.05, close0 * 0.05);

   if(!MathIsValidNumber(macd))
      macd = 0.0;
   else if(MathAbs(macd) > atr * 10.0)
      macd = MathClamp(macd, -atr * 5.0, atr * 5.0);

   if(!MathIsValidNumber(vol0) || vol0 < 0.0) vol0 = 0.0;
   if(!MathIsValidNumber(vol1) || vol1 < 0.0) vol1 = 0.0;
   if(!MathIsValidNumber(vol_avg) || vol_avg <= 0.0) vol_avg = 1.0;

   if(!MathIsValidNumber(sentiment) || sentiment < 0.0 || sentiment > 1.0) sentiment = 0.5;
   if(!MathIsValidNumber(spread) || spread < 0.0) spread = 0.0;
   if(!MathIsValidNumber(htf_bias)) htf_bias = 0.0;
   if(!MathIsValidNumber(vol_regime) || vol_regime <= 0.0) vol_regime = 1.0;

   return true;
}

bool ValidateAIFeatureVector(double &features[], int count)
{
   int n = MathMin(count, 15);
   for(int i = 0; i < n; i++)
   {
      if(!MathIsValidNumber(features[i])) return false;
      if(MathAbs(features[i]) > 1e6) return false;
   }
   return true;
}

bool ResolveDualModelConflict(double &buy_prob, double &sell_prob)
{
   if(buy_prob > 0.60 && sell_prob > 0.60)
   {
      buy_prob = 0.5;
      sell_prob = 0.5;
      return true;
   }

   return false;
}

bool IsNearZeroProbabilityPair(double buy_prob, double sell_prob)
{
   // Dual binary models that return both sides this close to zero are not
   // giving a tradable directional opinion. Treat them as no-output.
   return ((buy_prob + sell_prob) <= 1e-4);
}

bool IsConflictingProbabilityPair(double buy_prob, double sell_prob)
{
   return (buy_prob > 0.60 && sell_prob > 0.60);
}

bool NormalizeAndValidateProbabilities(double &buy_prob, double &sell_prob)
{
   bool valid = (MathIsValidNumber(buy_prob) && MathIsValidNumber(sell_prob));
   buy_prob = MathClamp(buy_prob, 0.0, 1.0);
   sell_prob = MathClamp(sell_prob, 0.0, 1.0);
   if(!valid) return false;

   // Binary buy/sell and 3-class hold models can legitimately return near-zero
   // direction probabilities. Interpret that as neutral, not as a reason to
   // override the external model with the internal fallback.
   double total_prob = buy_prob + sell_prob;
   if(total_prob <= 1e-6)
   {
      buy_prob = 0.5;
      sell_prob = 0.5;
      return true;
   }

   ResolveDualModelConflict(buy_prob, sell_prob);
   return true;
}

datetime GetFilesRelativeMTime(string files_relative_path)
{
   // Only works for files under MQL5\Files (relative path like "Models\\ptb_model.txt").
   if(IsAbsolutePathForDLL(files_relative_path))
      return 0;

   long v = FileGetInteger(files_relative_path, FILE_MODIFY_DATE);
   if(v < 0)
      v = FileGetInteger(files_relative_path, FILE_MODIFY_DATE, true); // COMMON fallback
   if(v < 0)
      return 0;
   return (datetime)v;
}

datetime g_external_ai_last_reload_check = 0;
datetime g_external_ai_last_model_mtime_slot0 = 0;
datetime g_external_ai_last_model_mtime_slot1 = 0;
datetime g_external_ai_last_scaler_mtime = 0;
bool g_external_ai_mtime_baseline_set = false;

void CaptureExternalAIMtimeBaseline()
{
   if(g_external_ai_mode_runtime == 0)
   {
      g_external_ai_last_model_mtime_slot0 = GetFilesRelativeMTime(EXTERNAL_AI_BUY_MODEL);
      g_external_ai_last_model_mtime_slot1 = GetFilesRelativeMTime(EXTERNAL_AI_SELL_MODEL);
   }
   else if(g_external_ai_mode_runtime == 1)
   {
      g_external_ai_last_model_mtime_slot0 = GetFilesRelativeMTime(EXTERNAL_AI_MODEL_PATH);
      g_external_ai_last_model_mtime_slot1 = 0;
   }

   if(Enable_AI_Scaler)
      g_external_ai_last_scaler_mtime = GetFilesRelativeMTime(AI_SCALER_FILE);
   else
      g_external_ai_last_scaler_mtime = 0;

   g_external_ai_mtime_baseline_set = true;
}

bool ReloadExternalAIModelsInPlace()
{
   if(!g_external_ai_allowed || !g_external_ai_ready)
      return false;

#ifndef EXTERNAL_AI_DLL_ENABLED
   return false;
#endif

   if(g_external_ai_mode_runtime == 0)
   {
      int buy_ok = PTB_LoadModelSlot(ResolveFilesPathForDLL(EXTERNAL_AI_BUY_MODEL), 0);
      int sell_ok = PTB_LoadModelSlot(ResolveFilesPathForDLL(EXTERNAL_AI_SELL_MODEL), 1);
      return (buy_ok == 1 && sell_ok == 1);
   }
   else if(g_external_ai_mode_runtime == 1)
   {
      int uni_ok = PTB_LoadModelSlot(ResolveFilesPathForDLL(EXTERNAL_AI_MODEL_PATH), 0);
      return (uni_ok == 1);
   }

   return false;
}

void MaybeHotReloadExternalAI()
{
   if(!Enable_AI_Model_HotReload)
      return;
   if(!g_Enable_AI_Trend_Predictor_Runtime || !g_external_ai_allowed || !g_external_ai_ready)
      return;

#ifndef EXTERNAL_AI_DLL_ENABLED
   return;
#endif

   int check_seconds = AI_Model_HotReload_Check_Seconds;
   if(check_seconds < 5) check_seconds = 5;

   datetime now = TimeCurrent();
   if((now - g_external_ai_last_reload_check) < check_seconds)
      return;
   g_external_ai_last_reload_check = now;

   if(!g_external_ai_mtime_baseline_set)
      CaptureExternalAIMtimeBaseline();

   bool scaler_changed = false;
   datetime scaler_mtime = 0;
   if(Enable_AI_Scaler)
   {
      scaler_mtime = GetFilesRelativeMTime(AI_SCALER_FILE);
      scaler_changed = (scaler_mtime > 0 && scaler_mtime != g_external_ai_last_scaler_mtime);
   }

   bool model_changed = false;
   if(g_external_ai_mode_runtime == 0)
   {
      datetime buy_mtime = GetFilesRelativeMTime(EXTERNAL_AI_BUY_MODEL);
      datetime sell_mtime = GetFilesRelativeMTime(EXTERNAL_AI_SELL_MODEL);
      model_changed = ((buy_mtime > 0 && buy_mtime != g_external_ai_last_model_mtime_slot0) ||
                       (sell_mtime > 0 && sell_mtime != g_external_ai_last_model_mtime_slot1));
   }
   else if(g_external_ai_mode_runtime == 1)
   {
      datetime uni_mtime = GetFilesRelativeMTime(EXTERNAL_AI_MODEL_PATH);
      model_changed = (uni_mtime > 0 && uni_mtime != g_external_ai_last_model_mtime_slot0);
   }

   if(!model_changed && !scaler_changed)
      return;

   // Reload scaler first (safe: keeps previous scaler on failure).
   if(scaler_changed)
   {
      if(LoadAIScaler(AI_SCALER_FILE))
      {
         g_ai_scaler_ready = true;
         g_external_ai_last_scaler_mtime = scaler_mtime;
         Log(LOG_INFO, "AIHotReload", "AI scaler reloaded: " + AI_SCALER_FILE);
      }
      else
      {
         Log(LOG_WARNING, "AIHotReload", "AI scaler reload failed (keeping previous scaler): " + AI_SCALER_FILE);
      }
   }

   if(model_changed)
   {
      if(ReloadExternalAIModelsInPlace())
      {
         Log(LOG_INFO, "AIHotReload", "External AI model hot-reloaded");
         CaptureExternalAIMtimeBaseline();
         LogExternalAIFeatureImportance();
      }
      else
      {
         Log(LOG_WARNING, "AIHotReload", "External AI model reload failed (keeping previous model in memory)");
      }
   }
}


bool InitExternalAI()
{
   if(!g_external_ai_allowed)
      return false;

#ifndef EXTERNAL_AI_DLL_ENABLED
   Log(LOG_WARNING, "InitExternalAI", "External AI DLL disabled at compile time (EXTERNAL_AI_DLL_ENABLED=0)");
   return false;
#endif

   g_external_ai_mode_runtime = External_AI_Mode;

   if(External_AI_Mode == 0)
   {
      int buy_ok = PTB_LoadModelSlot(ResolveFilesPathForDLL(EXTERNAL_AI_BUY_MODEL), 0);
      int sell_ok = PTB_LoadModelSlot(ResolveFilesPathForDLL(EXTERNAL_AI_SELL_MODEL), 1);
      if(buy_ok == 1 && sell_ok == 1)
      {
         Log(LOG_INFO, "InitExternalAI", "External AI dual models loaded");
         g_external_ai_mode_runtime = 0;
         CaptureExternalAIMtimeBaseline();
         return true;
      }
      
      Log(LOG_WARNING, "InitExternalAI", "Dual models unavailable, attempting unified model");
      int uni_ok = PTB_LoadModelSlot(ResolveFilesPathForDLL(EXTERNAL_AI_MODEL_PATH), 0);
      if(uni_ok == 1)
      {
         Log(LOG_INFO, "InitExternalAI", "External AI unified model loaded");
         g_external_ai_mode_runtime = 1;
         CaptureExternalAIMtimeBaseline();
         return true;
      }
      
      Log(LOG_ERROR, "InitExternalAI", "Failed to load any external AI model");
      return false;
   }
   else
   {
      int uni_ok = PTB_LoadModelSlot(ResolveFilesPathForDLL(EXTERNAL_AI_MODEL_PATH), 0);
      if(uni_ok == 1)
      {
         Log(LOG_INFO, "InitExternalAI", "External AI unified model loaded");
         g_external_ai_mode_runtime = 1;
         CaptureExternalAIMtimeBaseline();
         return true;
      }
      
      Log(LOG_WARNING, "InitExternalAI", "Unified model unavailable, attempting dual models");
      int buy_ok = PTB_LoadModelSlot(ResolveFilesPathForDLL(EXTERNAL_AI_BUY_MODEL), 0);
      int sell_ok = PTB_LoadModelSlot(ResolveFilesPathForDLL(EXTERNAL_AI_SELL_MODEL), 1);
      if(buy_ok == 1 && sell_ok == 1)
      {
         Log(LOG_INFO, "InitExternalAI", "External AI dual models loaded");
         g_external_ai_mode_runtime = 0;
         CaptureExternalAIMtimeBaseline();
         return true;
      }
      
      Log(LOG_ERROR, "InitExternalAI", "Failed to load any external AI model");
      return false;
   }
}

void ShutdownExternalAI()
{
   if(!g_external_ai_allowed)
      return;

#ifndef EXTERNAL_AI_DLL_ENABLED
   return;
#endif

   PTB_FreeModelSlot(0);
   PTB_FreeModelSlot(1);
   Log(LOG_INFO, "ShutdownExternalAI", "External AI model released");
}

void BuildAIFeatures(double &features[],
                     double close0, double close1, double close5, double atr,
                     double rsi, double ma_slope, double vol0, double vol1,
                     double vol_avg, double macd, double stoch, double sentiment,
                     double spread, double htf_bias, double vol_regime)
{
   features[0] = close0;
   features[1] = close1;
   features[2] = close5;
   features[3] = atr;
   features[4] = rsi;
   features[5] = ma_slope;
   features[6] = vol0;
   features[7] = vol1;
   features[8] = vol_avg;
   features[9] = macd;
   features[10] = stoch;
   features[11] = sentiment;
   features[12] = spread;
   features[13] = htf_bias;
   features[14] = vol_regime;
}

void GetAIModuleProbabilities(double close0, double close1, double close5, double atr,
                              double rsi, double ma_slope, double vol0, double vol1,
                              double vol_avg, double macd, double stoch, double sentiment,
                              double spread, double htf_bias, double vol_regime,
                              double &buy_prob, double &sell_prob)
{
   if(!SanitizeAIFeatureInputs(close0, close1, close5, atr, rsi, ma_slope, vol0, vol1,
                               vol_avg, macd, stoch, sentiment, spread, htf_bias, vol_regime))
   {
      Log(LOG_WARNING, "GetAIModuleProbabilities", "Invalid AI inputs - returning neutral probabilities");
      buy_prob = 0.5;
      sell_prob = 0.5;
      return;
   }

   double features[15];
   BuildAIFeatures(features, close0, close1, close5, atr, rsi, ma_slope, vol0, vol1,
                   vol_avg, macd, stoch, sentiment, spread, htf_bias, vol_regime);
   
   ApplyAIScaler(features, 15);
   if(Enable_AI_Scaler && g_ai_scaler_ready)
   {
      if(!ValidateAIFeatureVector(features, 15))
      {
         Log(LOG_WARNING, "GetAIModuleProbabilities", "Scaled AI features invalid - returning neutral probabilities");
         buy_prob = 0.5;
         sell_prob = 0.5;
         return;
      }
   }

   if(g_external_ai_allowed && g_external_ai_ready)
   {
      if(g_external_ai_mode_runtime == 0)
      {
         double buy_p = PTB_PredictSlot(features, 15, 0);
         double sell_p = PTB_PredictSlot(features, 15, 1);
         double raw_buy_p = buy_p;
         double raw_sell_p = sell_p;
         buy_prob = buy_p;
         sell_prob = sell_p;
         bool dual_near_zero_fallback = false;
         if(NormalizeAndValidateProbabilities(buy_prob, sell_prob))
         {
            if(IsNearZeroProbabilityPair(raw_buy_p, raw_sell_p))
            {
               dual_near_zero_fallback = true;
               static datetime last_dual_near_zero_fallback_log = 0;
               datetime now_ts = TimeCurrent();
               if(g_debug_signals_enabled &&
                 (last_dual_near_zero_fallback_log == 0 || (now_ts - last_dual_near_zero_fallback_log) >= 300))
              {
                 Log(LOG_WARNING, "GetAIModuleProbabilities",
                     StringFormat("External AI dual model returned near-zero buy/sell probabilities | raw_buy=%.8f raw_sell=%.8f - using internal AI fallback",
                                  raw_buy_p, raw_sell_p));
                 last_dual_near_zero_fallback_log = now_ts;
               }
            }
            else
           {
              if(g_debug_signals_enabled && IsConflictingProbabilityPair(raw_buy_p, raw_sell_p))
              {
                 Log(LOG_DEBUG, "GetAIModuleProbabilities",
                     StringFormat("External AI dual model returned conflicting probabilities | raw_buy=%.8f raw_sell=%.8f",
                                  raw_buy_p, raw_sell_p));
              }
               return;
            }
         }

         if(!dual_near_zero_fallback)
         {
            Log(LOG_WARNING, "GetAIModuleProbabilities",
                StringFormat("External AI dual model returned invalid probabilities | raw_buy=%.8f raw_sell=%.8f - falling back",
                             raw_buy_p, raw_sell_p));
         }
      }
      else
      {
         double out_probs[3];
         int ok = PTB_PredictMulti(features, 15, out_probs, 3, 0);
         if(ok == 1)
         {
            double hold_p = out_probs[0];
            double raw_buy_p = out_probs[1];
            double raw_sell_p = out_probs[2];
            buy_prob = out_probs[1];
            sell_prob = out_probs[2];
            if(NormalizeAndValidateProbabilities(buy_prob, sell_prob))
            {
               if(g_debug_signals_enabled && IsNearZeroProbabilityPair(raw_buy_p, raw_sell_p))
               {
                  Log(LOG_DEBUG, "GetAIModuleProbabilities",
                      StringFormat("External AI unified model returned hold/no-direction probabilities | hold=%.8f raw_buy=%.8f raw_sell=%.8f",
                                   hold_p, raw_buy_p, raw_sell_p));
               }
               else if(g_debug_signals_enabled && IsConflictingProbabilityPair(raw_buy_p, raw_sell_p))
               {
                  Log(LOG_DEBUG, "GetAIModuleProbabilities",
                      StringFormat("External AI unified model returned conflicting directional probabilities | hold=%.8f raw_buy=%.8f raw_sell=%.8f",
                                   hold_p, raw_buy_p, raw_sell_p));
               }
               return;
            }
             
            Log(LOG_WARNING, "GetAIModuleProbabilities",
                StringFormat("External AI unified model returned invalid probabilities | hold=%.8f raw_buy=%.8f raw_sell=%.8f - falling back",
                             hold_p, raw_buy_p, raw_sell_p));
         }
      }
   }

   double prob;
   string ai_diag = "";
   if(g_debug_signals_enabled)
   {
      prob = g_ai_manager.GetPredictionWithDiag(close0, close1, close5, atr, rsi, ma_slope,
                                                vol0, vol1, vol_avg, macd, stoch, sentiment,
                                                htf_bias, vol_regime, ai_diag);
      if(StringLen(ai_diag) > 0)
      {
         Log(LOG_DEBUG, "AIInternalDiag", StringFormat("Prob=%.3f | %s", prob, ai_diag));
      }
   }
   else
   {
      prob = g_ai_manager.GetPrediction(close0, close1, close5, atr, rsi, ma_slope,
                                        vol0, vol1, vol_avg, macd, stoch, sentiment,
                                        htf_bias, vol_regime);
   }
   if(!MathIsValidNumber(prob) || prob < 0.0 || prob > 1.0)
   {
      Log(LOG_WARNING, "GetAIModuleProbabilities", "Invalid prediction, defaulting to 0.5");
      prob = 0.5;
   }
   buy_prob = prob;
   sell_prob = 1.0 - prob;
}

void SortFeatureImportance(string &names[], double &vals[], int count)
{
   for(int i = 0; i < count - 1; i++)
   {
      int best = i;
      for(int j = i + 1; j < count; j++)
      {
         if(vals[j] > vals[best])
            best = j;
      }
      if(best != i)
      {
         double tmp = vals[i];
         vals[i] = vals[best];
         vals[best] = tmp;
         
         string name_tmp = names[i];
         names[i] = names[best];
         names[best] = name_tmp;
      }
   }
}

void LogExternalAIFeatureImportance()
{
   if(!g_external_ai_allowed || !g_external_ai_ready)
      return;
   
   string feature_names[15] = {
      "close0","close1","close5","atr","rsi","ma_slope",
      "vol0","vol1","vol_avg","macd","stoch","sentiment",
      "spread","htf_bias","vol_regime"
   };
   
   double importances[15];
   int slot = (g_external_ai_mode_runtime == 0 ? 0 : 0);
   int ok = PTB_GetFeatureImportance(importances, 15, slot);
   if(ok != 1)
   {
      Log(LOG_WARNING, "AIImportance", "Failed to read feature importance");
      return;
   }
   
   SortFeatureImportance(feature_names, importances, 15);
   
   Log(LOG_INFO, "AIImportance", "Top features (model slot " + IntegerToString(slot) + "):");
   for(int k = 0; k < 5; k++)
   {
      Log(LOG_INFO, "AIImportance", feature_names[k] + ": " + DoubleToString(importances[k], 2));
   }
   
   if(g_external_ai_mode_runtime == 0)
   {
      string feature_names_sell[15] = {
         "close0","close1","close5","atr","rsi","ma_slope",
         "vol0","vol1","vol_avg","macd","stoch","sentiment",
         "spread","htf_bias","vol_regime"
      };
      double importances_sell[15];
      int ok2 = PTB_GetFeatureImportance(importances_sell, 15, 1);
      if(ok2 == 1)
      {
         SortFeatureImportance(feature_names_sell, importances_sell, 15);
         Log(LOG_INFO, "AIImportance", "Top features (sell model slot 1):");
         for(int k = 0; k < 5; k++)
         {
            Log(LOG_INFO, "AIImportance", feature_names_sell[k] + ": " + DoubleToString(importances_sell[k], 2));
         }
      }
   }
}

#endif // AI_EXTERNAL_DLL_MQH
