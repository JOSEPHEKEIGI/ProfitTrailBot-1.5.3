#ifndef RISK_SESSION_MQH
#define RISK_SESSION_MQH

// Implemented in TradeManagement.mqh (included later in main unit)
ENUM_ORDER_TYPE_FILLING GetSymbolFillingMode(string symbol);
bool ExecuteTrade(string symbol, const STradingSignal &signal, int symbol_index);

int TimeframeToMinutes(ENUM_TIMEFRAMES tf)
{
   // Dynamic conversion supports all broker/platform timeframes (M2, M3, H2, H3, H6, etc.)
   int tf_seconds = PeriodSeconds(tf);
   if(tf_seconds <= 0)
      return 0;
   return tf_seconds / 60;
}

// FIX: Determine market day (Forex: trades Sun 5pm → Fri 4pm UTC)
datetime GetMarketDay(datetime server_time)
{
   MqlDateTime dt;
   TimeToStruct(server_time, dt);
   
   // Before Sunday 5pm = Friday's market
   if(dt.day_of_week == 0 && dt.hour < 17)  // Sunday before 5pm
      return (server_time / 86400 - 2) * 86400;  // Return Friday 0:00 UTC
   
   // Normal market day
   return (server_time / 86400) * 86400;  // Return today 0:00 UTC
}

string GetRiskSessionStateKey(string field)
{
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   return "PTB.RISK." + (string)login + "." + IntegerToString(Magic_Base) + "." + field;
}

double BoolToPersistDouble(bool value)
{
   return (value ? 1.0 : 0.0);
}

bool GetPersistedRiskStateNumber(string field, double &value)
{
   string key = GetRiskSessionStateKey(field);
   if(!GlobalVariableCheck(key))
      return false;

   value = GlobalVariableGet(key);
   return true;
}

void PersistRiskSessionState()
{
   datetime persisted_trade_day = (g_trade_day > 0 ? g_trade_day : GetMarketDay(TimeCurrent()));
   int persisted_trades_today = g_trades_today;
   if(persisted_trades_today < 0)
      persisted_trades_today = 0;

   GlobalVariableSet(GetRiskSessionStateKey("TRADE_DAY"), (double)persisted_trade_day);
   GlobalVariableSet(GetRiskSessionStateKey("TRADES_TODAY"), (double)persisted_trades_today);
   GlobalVariableSet(GetRiskSessionStateKey("EQUITY_DAY_START"), g_equity_day_start);
   GlobalVariableSet(GetRiskSessionStateKey("EQUITY_SESSION_HIGH"), g_equity_all_time_high);
   GlobalVariableSet(GetRiskSessionStateKey("RISK_COOLDOWN_UNTIL"), (double)g_risk_cooldown_until);
   GlobalVariableSet(GetRiskSessionStateKey("DRAWDOWN_PAUSE_UNTIL"), (double)g_drawdown_pause_until);
   GlobalVariableSet(GetRiskSessionStateKey("MARKET_PAUSE_UNTIL"), (double)g_market_pause_until);
   GlobalVariableSet(GetRiskSessionStateKey("KILL_ACTIVE"), BoolToPersistDouble(g_Kill_Switch_Active));
   GlobalVariableSet(GetRiskSessionStateKey("KILL_ACTIVATED_TIME"), (double)g_Kill_Switch_Activated_Time);
   GlobalVariableSet(GetRiskSessionStateKey("KILL_LATCHED"), BoolToPersistDouble(g_Kill_Switch_Daily_Loss_Latched));
   GlobalVariableSet(GetRiskSessionStateKey("KILL_TRIGGER_LOSS_PCT"), g_Kill_Switch_Trigger_Loss_Pct);
   GlobalVariableSet(GetRiskSessionStateKey("KILL_TRIGGER_LIMIT_PCT"), g_Kill_Switch_Trigger_Limit_Pct);
   GlobalVariableSet(GetRiskSessionStateKey("KILL_TRIGGER_DAY_START"), g_Kill_Switch_Trigger_Day_Start_Equity);
}

bool RestorePersistedRiskSessionState()
{
   double stored_trade_day_value = 0.0;
   if(!GetPersistedRiskStateNumber("TRADE_DAY", stored_trade_day_value))
      return false;

   datetime now = TimeCurrent();
   datetime current_market_day = GetMarketDay(now);
   datetime stored_trade_day = (datetime)MathRound(stored_trade_day_value);
   if(stored_trade_day <= 0 || stored_trade_day != current_market_day)
      return false;

   g_trade_day = stored_trade_day;
   bool repaired_persisted_state = false;

   double stored_value = 0.0;
   if(GetPersistedRiskStateNumber("TRADES_TODAY", stored_value))
   {
      int restored_trades_today = (int)MathRound(stored_value);
      if(restored_trades_today < 0)
         restored_trades_today = 0;
      g_trades_today = restored_trades_today;
   }
    if(GetPersistedRiskStateNumber("EQUITY_DAY_START", stored_value) && stored_value > 0.0)
       g_equity_day_start = stored_value;
    if(GetPersistedRiskStateNumber("EQUITY_SESSION_HIGH", stored_value) && stored_value > 0.0)
      g_equity_all_time_high = stored_value;

   if(GetPersistedRiskStateNumber("RISK_COOLDOWN_UNTIL", stored_value))
   {
      datetime restored_until = (datetime)MathRound(stored_value);
      if(restored_until > now)
         g_risk_cooldown_until = restored_until;
   }

   if(GetPersistedRiskStateNumber("DRAWDOWN_PAUSE_UNTIL", stored_value))
   {
      datetime restored_until = (datetime)MathRound(stored_value);
      if(restored_until > now)
         g_drawdown_pause_until = restored_until;
   }

   if(GetPersistedRiskStateNumber("MARKET_PAUSE_UNTIL", stored_value))
   {
      datetime restored_until = (datetime)MathRound(stored_value);
      if(restored_until > now)
         g_market_pause_until = restored_until;
   }

   bool restored_kill_active = false;
   if(GetPersistedRiskStateNumber("KILL_ACTIVE", stored_value))
      restored_kill_active = (stored_value > 0.5);

   bool restored_daily_loss_latch = false;
   if(GetPersistedRiskStateNumber("KILL_LATCHED", stored_value))
      restored_daily_loss_latch = (stored_value > 0.5);

   double stored_trigger_loss_pct = 0.0;
   double stored_trigger_limit_pct = 0.0;
   double stored_trigger_day_start = 0.0;
   if(GetPersistedRiskStateNumber("KILL_TRIGGER_LOSS_PCT", stored_value) && stored_value > 0.0)
      stored_trigger_loss_pct = stored_value;
   if(GetPersistedRiskStateNumber("KILL_TRIGGER_LIMIT_PCT", stored_value) && stored_value > 0.0)
      stored_trigger_limit_pct = stored_value;
   if(GetPersistedRiskStateNumber("KILL_TRIGGER_DAY_START", stored_value) && stored_value > 0.0)
      stored_trigger_day_start = stored_value;

   if(stored_trigger_day_start > 0.0 && stored_trigger_day_start > g_equity_day_start)
      g_equity_day_start = stored_trigger_day_start;

   double equity_now = AccountInfoDouble(ACCOUNT_EQUITY);
   double loss_pct = SafeDiv(MathMax(0.0, g_equity_day_start - equity_now), g_equity_day_start, 0.0) * 100.0;
   double kill_daily_loss_limit_pct = 0.0;
   switch(g_Kill_Switch_Mode)
   {
      case KILL_SWITCH_MODE_CONSERVATIVE:
         kill_daily_loss_limit_pct = 2.0;
         break;
      case KILL_SWITCH_MODE_MODERATE:
         kill_daily_loss_limit_pct = 5.0;
         break;
      case KILL_SWITCH_MODE_AGGRESSIVE:
         kill_daily_loss_limit_pct = 10.0;
         break;
      default:
         kill_daily_loss_limit_pct = 0.0;
         break;
   }
   if(g_Kill_Switch_Max_Daily_Loss_Ccy > 0.0 && g_equity_day_start > 0.0)
      kill_daily_loss_limit_pct = SafeDiv(g_Kill_Switch_Max_Daily_Loss_Ccy, g_equity_day_start, 0.0) * 100.0;

   bool same_day_daily_loss_still_breached =
      (g_Kill_Switch_Mode != KILL_SWITCH_MODE_DISABLED &&
       kill_daily_loss_limit_pct > 0.0 &&
       loss_pct >= kill_daily_loss_limit_pct);

   if(restored_daily_loss_latch || restored_kill_active || same_day_daily_loss_still_breached)
   {
      g_Kill_Switch_Daily_Loss_Latched = (restored_daily_loss_latch || same_day_daily_loss_still_breached);
      g_Kill_Switch_Active = true;

      if(GetPersistedRiskStateNumber("KILL_ACTIVATED_TIME", stored_value))
         g_Kill_Switch_Activated_Time = (datetime)MathRound(stored_value);

      g_Kill_Switch_Trigger_Loss_Pct = stored_trigger_loss_pct;
      g_Kill_Switch_Trigger_Limit_Pct = stored_trigger_limit_pct;
      g_Kill_Switch_Trigger_Day_Start_Equity = stored_trigger_day_start;
      if(g_Kill_Switch_Trigger_Loss_Pct <= 0.0 && same_day_daily_loss_still_breached)
         g_Kill_Switch_Trigger_Loss_Pct = loss_pct;
      if(g_Kill_Switch_Trigger_Limit_Pct <= 0.0 && same_day_daily_loss_still_breached)
         g_Kill_Switch_Trigger_Limit_Pct = kill_daily_loss_limit_pct;
      if(g_Kill_Switch_Trigger_Day_Start_Equity <= 0.0 && same_day_daily_loss_still_breached)
         g_Kill_Switch_Trigger_Day_Start_Equity = g_equity_day_start;

      if(g_Kill_Switch_Activated_Time <= 0)
         g_Kill_Switch_Activated_Time = now;

      if(!restored_daily_loss_latch && same_day_daily_loss_still_breached)
      {
         repaired_persisted_state = true;
         Log(LOG_WARNING, "RestorePersistedRiskSessionState",
             StringFormat("Re-latched same-day kill switch from restored equity: current daily loss %.2f%% >= %.2f%%",
                          loss_pct, kill_daily_loss_limit_pct));
      }

      double restored_daily_dd_limit = (g_Max_Daily_Drawdown_Pct_Effective > 0.0 ?
                                        g_Max_Daily_Drawdown_Pct_Effective :
                                        g_Max_Daily_Drawdown_Pct);
      if(restored_daily_dd_limit > 0.0 &&
         loss_pct >= restored_daily_dd_limit &&
         g_drawdown_pause_until <= now)
      {
         datetime repaired_pause_until = ((now / 3600) + 1) * 3600;
         if(repaired_pause_until <= now)
            repaired_pause_until = now + 3600;

         g_drawdown_pause_until = repaired_pause_until;
         repaired_persisted_state = true;
         Log(LOG_WARNING, "RestorePersistedRiskSessionState",
             StringFormat("Repaired missing same-day drawdown pause: current daily loss %.2f%% >= %.2f%%, pause_until=%s",
                          loss_pct, restored_daily_dd_limit, TimeToString(g_drawdown_pause_until)));
      }

      if(g_Kill_Switch_Trigger_Loss_Pct > 0.0 && g_Kill_Switch_Trigger_Limit_Pct > 0.0)
      {
         g_Kill_Switch_Reason = StringFormat(
            "Restored daily loss kill switch latch: %.2f%% >= %.2f%% (same market day, day-start=$%.2f)",
            g_Kill_Switch_Trigger_Loss_Pct,
            g_Kill_Switch_Trigger_Limit_Pct,
            (g_Kill_Switch_Trigger_Day_Start_Equity > 0.0 ? g_Kill_Switch_Trigger_Day_Start_Equity : g_equity_day_start));
      }
      else if(loss_pct > 0.0)
      {
         g_Kill_Switch_Reason = StringFormat(
            "Restored daily loss kill switch latch: current session loss %.2f%% from $%.2f day-start equity",
            loss_pct, g_equity_day_start);
      }
      else
      {
         g_Kill_Switch_Reason = StringFormat(
            "Restored daily loss kill switch latch from same market day (trigger details unavailable, day-start=$%.2f)",
            g_equity_day_start);
      }
      g_kill_switch_triggers = MathMax(g_kill_switch_triggers, 1);
   }

   if(repaired_persisted_state)
      PersistRiskSessionState();

   Log(LOG_INFO, "RestorePersistedRiskSessionState",
       "Restored same-day risk state: trade_day=" + TimeToString(g_trade_day, TIME_DATE) +
       ", trades_today=" + IntegerToString(g_trades_today) +
       ", equity_day_start=$" + DoubleToString(g_equity_day_start, 2) +
       ", risk_cooldown_until=" + TimeToString(g_risk_cooldown_until) +
       ", drawdown_pause_until=" + TimeToString(g_drawdown_pause_until) +
       ", market_pause_until=" + TimeToString(g_market_pause_until) +
       ", kill_switch=" + (g_Kill_Switch_Active ? "Y" : "N"));
   return true;
}

bool UpdateDailyCounters(bool force_reset = false)
{
   datetime current_time = TimeCurrent();
   datetime market_day = GetMarketDay(current_time);  // FIX: Use market day instead of calendar day
   
   // FIXED: Reset on market day change or force reset
   if(force_reset || market_day != g_trade_day)
   {
      g_trade_day = market_day;  // FIX: Use market day, not calendar day
      g_trades_today = 0;
      g_equity_day_start = AccountInfoDouble(ACCOUNT_EQUITY);
      g_equity_all_time_high = MathMax(g_equity_day_start, AccountInfoDouble(ACCOUNT_BALANCE));
      g_consecutive_losses = 0;
      g_consecutive_wins = 0;
      g_risk_cooldown_until = 0;
       g_Kill_Switch_Active = false;
       g_Kill_Switch_Activated_Time = 0;
       g_Kill_Switch_Reason = "";
       g_Kill_Switch_Daily_Loss_Latched = false;
       g_Kill_Switch_Trigger_Loss_Pct = 0.0;
       g_Kill_Switch_Trigger_Limit_Pct = 0.0;
       g_Kill_Switch_Trigger_Day_Start_Equity = 0.0;
       g_exec_latency_blocks = 0;
       g_exec_slippage_reroutes = 0;
       g_exec_slippage_violations = 0;
      for(int i = 0; i < MAX_SYMBOLS; i++)
      {
         g_symbol_loss_streak[i] = 0;
         g_symbol_last_loss_time[i] = 0;
         g_symbol_loss_cooldown_until[i] = 0;
      }
      PersistRiskSessionState();
      Log(LOG_INFO, "UpdateDailyCounters", "Daily counters reset at " + TimeToString(current_time) + 
          " - Starting equity: $" + DoubleToString(g_equity_day_start, 2));
      return true;
   }
   return false;
}

bool CanExecuteTradeToday()
{
   UpdateDailyCounters();

   // Check critical daily limit gate (always enforced for safety)
   if(!CGateController::CanExecuteTrade(Symbol(), "daily_limit_gate"))
      return false;
   static datetime last_daily_limit_alert_time = 0;
   static datetime last_daily_limit_alert_day = 0;
   
   if(g_trades_today >= g_Max_Trades_Per_Day_Effective)
   {
      datetime now = TimeCurrent();
      if(last_daily_limit_alert_day != g_trade_day)
      {
         last_daily_limit_alert_day = g_trade_day;
         last_daily_limit_alert_time = 0;
      }

      if(last_daily_limit_alert_time == 0 || (now - last_daily_limit_alert_time) >= 60)
      {
         string msg = StringFormat("Max daily trades reached: %d/%d", 
                                   g_trades_today, g_Max_Trades_Per_Day_Effective);
         Log(LOG_WARNING, "CanExecuteTradeToday", msg);
         SendAlert(ALERT_DAILY_LIMIT, msg);
         last_daily_limit_alert_time = now;
      }
      return false;
   }
   
   return true;
}

bool HasDailyTradeBudget()
{
   UpdateDailyCounters();
   // Check critical daily limit gate (always enforced for safety)
   if(!CGateController::CanExecuteTrade(Symbol(), "daily_trade_budget"))
      return false;
   return (g_trades_today < g_Max_Trades_Per_Day_Effective);
}

datetime GetNextDailyResetTime()
{
   UpdateDailyCounters();
   datetime now = TimeCurrent();
   datetime next_reset = g_trade_day + 86400;
   if(next_reset <= now)
      next_reset = now + 60;
   return next_reset;
}

bool IsRecoverableError(int retcode, string retcode_description)
{
   // Temporary/Network errors - worth retrying
   if(retcode == TRADE_RETCODE_REQUOTE ||
      retcode == TRADE_RETCODE_PRICE_OFF ||
      retcode == TRADE_RETCODE_PRICE_CHANGED ||
      retcode == TRADE_RETCODE_CONNECTION ||
      retcode == TRADE_RETCODE_TOO_MANY_REQUESTS ||
      retcode == TRADE_RETCODE_LOCKED ||
      retcode == TRADE_RETCODE_TIMEOUT ||
      retcode == TRADE_RETCODE_FROZEN)
   {
      return true;  // Retry these
   }
   
   // GOLD-specific errors that are recoverable
   if(StringFind(retcode_description, "Off quotes") != -1 ||
      StringFind(retcode_description, "Market is closed") != -1 ||
      StringFind(retcode_description, "No prices") != -1 ||
      StringFind(retcode_description, "Trade is disabled") != -1)
   {
      return true;  // Retry when market reopens or quotes return
   }
   
   // Market closed - will recover when market opens
   if(retcode == TRADE_RETCODE_TRADE_DISABLED ||
      StringFind(retcode_description, "Market closed") != -1)
   {
      return true;  // Retry when market opens
   }
   
   return false;  // All other errors are permanent
}

bool IsPermanentError(int retcode, string retcode_description)
{
   // Symbol not in market watch - won't be fixed by retrying
   if(retcode == 4014 ||
      StringFind(retcode_description, "not in Market Watch") != -1 ||
      StringFind(retcode_description, "Symbol not found") != -1)
   {
      return true;
   }
   
   // Invalid stops - price levels unreachable
   if(retcode == TRADE_RETCODE_INVALID_STOPS)
   {
      return true;
   }
   
   // Invalid volume - lot size not allowed
   if(retcode == TRADE_RETCODE_INVALID_VOLUME ||
      StringFind(retcode_description, "Invalid volume") != -1)
   {
      return true;
   }
   
   // Invalid price
   if(retcode == TRADE_RETCODE_INVALID_PRICE ||
      StringFind(retcode_description, "invalid price") != -1)
   {
      return true;
   }

   // Hard broker rejects that require configuration/capital changes.
   if(retcode == TRADE_RETCODE_NO_MONEY ||
      retcode == TRADE_RETCODE_INVALID_FILL ||
      retcode == TRADE_RETCODE_LIMIT_ORDERS ||
      retcode == TRADE_RETCODE_LIMIT_VOLUME ||
      retcode == TRADE_RETCODE_INVALID_EXPIRATION ||
      StringFind(retcode_description, "No money") != -1 ||
      StringFind(retcode_description, "not enough money") != -1 ||
      StringFind(retcode_description, "Insufficient") != -1)
   {
      return true;
   }
    
   return false;
}

bool IsAmbiguousTradeRetcode(int retcode)
{
   return (retcode == TRADE_RETCODE_CONNECTION ||
           retcode == TRADE_RETCODE_TIMEOUT ||
           retcode == TRADE_RETCODE_LOCKED ||
           retcode == TRADE_RETCODE_TOO_MANY_REQUESTS);
}

void ActivateKillSwitch(string reason)
{
   if(g_Kill_Switch_Mode == KILL_SWITCH_MODE_DISABLED)
      return;

   if(!g_Kill_Switch_Active)
   {
      g_Kill_Switch_Active = true;
      g_Kill_Switch_Activated_Time = TimeCurrent();
      g_Kill_Switch_Reason = reason;
      g_kill_switch_triggers++;
      PersistRiskSessionState();
      Log(LOG_ERROR, "KillSwitch", "TRADING HALTED: " + reason);
      SendAlert(ALERT_RISK_CONTROL, "KILL SWITCH ACTIVATED: " + reason);
      AuditLog("KILL_SWITCH", "", reason);
   }
}

void ResetKillSwitch(string reset_reason = "Manual reset")
{
   if(g_Kill_Switch_Active)
   {
      g_Kill_Switch_Active = false;
      g_Kill_Switch_Activated_Time = 0;
      string old_reason = g_Kill_Switch_Reason;
      g_Kill_Switch_Reason = "";
      g_Kill_Switch_Daily_Loss_Latched = false;
      g_Kill_Switch_Trigger_Loss_Pct = 0.0;
      g_Kill_Switch_Trigger_Limit_Pct = 0.0;
      g_Kill_Switch_Trigger_Day_Start_Equity = 0.0;
      PersistRiskSessionState();
      Log(LOG_INFO, "KillSwitch", "Kill switch reset: " + old_reason + " -> " + reset_reason);
      SendAlert(ALERT_RISK_CONTROL, "KILL SWITCH RESET: " + reset_reason);
      AuditLog("KILL_SWITCH_RESET", old_reason, reset_reason);
   }
}

void EvaluateKillSwitchDailyLoss()
{
   if(g_Kill_Switch_Mode == KILL_SWITCH_MODE_DISABLED)
      return;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0 || g_equity_day_start <= 0.0)
      return;

   double loss_ccy = MathMax(0.0, g_equity_day_start - equity);
   double loss_pct = SafeDiv(loss_ccy, g_equity_day_start, 0.0) * 100.0;

   // Determine loss limits based on enum mode
   double daily_loss_limit_pct = 0.0;
   int consecutive_loss_limit = 0;
   
   switch(g_Kill_Switch_Mode)
   {
      case KILL_SWITCH_MODE_DISABLED:
          return; // Already checked above, but safe guard
          
      case KILL_SWITCH_MODE_CONSERVATIVE:
         daily_loss_limit_pct = 2.0;  // 2% of account
         consecutive_loss_limit = 5;
         break;
          
      case KILL_SWITCH_MODE_MODERATE:
         daily_loss_limit_pct = 5.0;  // 5% of account
         consecutive_loss_limit = 10;
         break;
          
      case KILL_SWITCH_MODE_AGGRESSIVE:
         daily_loss_limit_pct = 10.0; // 10% of account
         consecutive_loss_limit = 20;
         break;
   }

   // Apply currency override if specified (takes precedence over %)
   if(g_Kill_Switch_Max_Daily_Loss_Ccy > 0.0)
   {
      daily_loss_limit_pct = SafeDiv(g_Kill_Switch_Max_Daily_Loss_Ccy, g_equity_day_start, 0.0) * 100.0;
   }

   bool daily_loss_exceeded = (daily_loss_limit_pct > 0.0 && loss_pct >= daily_loss_limit_pct);
   bool streak_exceeded = (consecutive_loss_limit > 0 && g_consecutive_losses >= consecutive_loss_limit);

   // If kill switch is already active, check if loss condition has improved
   if(g_Kill_Switch_Active)
   {
      // Daily-loss trips are latched for the rest of the market day to prevent
      // equity fluctuation from repeatedly re-enabling and re-halting trading.
      if(g_Kill_Switch_Daily_Loss_Latched)
         return;

      // Auto-reset only if no active trigger remains. Daily reset/manual reset still clear state as before.
      if(!daily_loss_exceeded && !streak_exceeded)
      {
         ResetKillSwitch(StringFormat("Loss improved: %.2f%% (limit: %.2f%%), streak=%d/%d",
                                      loss_pct, daily_loss_limit_pct,
                                      g_consecutive_losses, consecutive_loss_limit));
      }
      return;
   }

   // Kill switch not active, check if conditions trigger it
   if(daily_loss_exceeded)
   {
      g_Kill_Switch_Daily_Loss_Latched = true;
      g_Kill_Switch_Trigger_Loss_Pct = loss_pct;
      g_Kill_Switch_Trigger_Limit_Pct = daily_loss_limit_pct;
      g_Kill_Switch_Trigger_Day_Start_Equity = g_equity_day_start;
      ActivateKillSwitch(StringFormat("Daily loss limit hit: %.2f%% >= %.2f%% (%s mode)",
                                      loss_pct, daily_loss_limit_pct,
                                      EnumToString(g_Kill_Switch_Mode)));
      return;
   }

   if(streak_exceeded)
   {
      g_Kill_Switch_Daily_Loss_Latched = false;
      g_Kill_Switch_Trigger_Loss_Pct = 0.0;
      g_Kill_Switch_Trigger_Limit_Pct = 0.0;
      g_Kill_Switch_Trigger_Day_Start_Equity = 0.0;
      ActivateKillSwitch(StringFormat("Consecutive loss limit hit: %d >= %d (%s mode)",
                                      g_consecutive_losses, consecutive_loss_limit,
                                      EnumToString(g_Kill_Switch_Mode)));
      return;
   }
}

bool IsKillSwitchActive()
{
   if(g_Kill_Switch_Mode == KILL_SWITCH_MODE_DISABLED)
      return false;
   return g_Kill_Switch_Active;
}

bool IsSuccessfulCloseRetcode(int retcode)
{
   return (retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL);
}

bool IsSuccessfulOrderCancelRetcode(int retcode)
{
   return (retcode == TRADE_RETCODE_DONE);
}

bool IsMinuteWithinSessionWindow(int current_minutes, int start_minutes, int end_minutes)
{
   if(start_minutes == end_minutes)
      return true;
   if(start_minutes < end_minutes)
      return (current_minutes >= start_minutes && current_minutes < end_minutes);

   // Cross-midnight window
   return (current_minutes >= start_minutes || current_minutes < end_minutes);
}

bool IsWithinTradingSession()
{
   if(!CGateController::IsSessionGateEnabled() || !g_Enable_Session_Gates)
      return true;

   if(!g_Use_Session_Filter)
      return true;

   datetime session_time = GetMarketSessionReferenceTime();
   MqlDateTime dt;
   TimeToStruct(session_time, dt);
   int hour = dt.hour;
   int minute = dt.min;
    
   int current_minutes = hour * 60 + minute;
   int london_start = (int)(g_London_Session_Start * 60);
   int london_end = (int)(g_London_Session_End * 60);
   int ny_start = (int)(g_NewYork_Session_Start * 60);
   int ny_end = (int)(g_NewYork_Session_End * 60);
   
   bool in_london = IsMinuteWithinSessionWindow(current_minutes, london_start, london_end);
   bool in_newyork = IsMinuteWithinSessionWindow(current_minutes, ny_start, ny_end);

   return (in_london || in_newyork);
}

bool IsAbnormalMarketPauseActive(datetime now = 0)
{
   if(now <= 0)
      now = TimeCurrent();

   if(g_Disable_Abnormal_Market_Pause_For_Diagnostics)
      return false;

   if(!g_Enable_Abnormal_Market_Pause)
      return false;

   // Abnormal spread pauses are an optional spread-quality gate.
   // If spread gates are disabled via runtime sync/master bypass, do not block.
   if(!CGateController::IsSpreadGateEnabled())
      return false;

   return (g_market_pause_until > now);
}

bool IsDrawdownPauseActive(datetime now = 0)
{
   if(now <= 0)
      now = TimeCurrent();

   // Drawdown pause is a critical safety stop and remains enforced while active.
   if(!CGateController::IsDrawdownGateEnabled())
      return false;

   return (g_drawdown_pause_until > now);
}

datetime GetExecutionPauseUntil(datetime now = 0)
{
   if(now <= 0)
      now = TimeCurrent();

   datetime pause_until = 0;
   if(IsAbnormalMarketPauseActive(now))
      pause_until = g_market_pause_until;
   if(IsDrawdownPauseActive(now))
      pause_until = MathMax(pause_until, g_drawdown_pause_until);
   return pause_until;
}

datetime GetMarketSessionReferenceTime()
{
   datetime broker_time = TimeTradeServer();
   if(broker_time > 0)
      return broker_time;

   broker_time = TimeCurrent();
   if(broker_time > 0)
      return broker_time;

   return TimeGMT();
}

int GetSecondsOfDay(datetime value)
{
   MqlDateTime dt;
   TimeToStruct(value, dt);
   return dt.hour * 3600 + dt.min * 60 + dt.sec;
}

bool IsWithinBrokerTradeSessionDay(string symbol,
                                   ENUM_DAY_OF_WEEK session_day,
                                   int current_seconds,
                                   bool same_day,
                                   bool &has_sessions)
{
   for(uint session_index = 0; session_index < 16; session_index++)
   {
      datetime from_time = 0;
      datetime to_time = 0;
      if(!SymbolInfoSessionTrade(symbol, session_day, session_index, from_time, to_time))
         break;

      has_sessions = true;
      int from_seconds = GetSecondsOfDay(from_time);
      int to_seconds = GetSecondsOfDay(to_time);

      if(from_seconds == to_seconds)
         return true;

      if(from_seconds < to_seconds)
      {
         if(same_day &&
            current_seconds >= from_seconds &&
            current_seconds < to_seconds)
            return true;
      }
      else
      {
         if(same_day)
         {
            if(current_seconds >= from_seconds)
               return true;
         }
         else
         {
            if(current_seconds < to_seconds)
               return true;
         }
      }
   }

   return false;
}

bool IsWithinBrokerTradeSession(string symbol, datetime check_time, bool &has_sessions)
{
   has_sessions = false;

   MqlDateTime dt;
   TimeToStruct(check_time, dt);
   int current_seconds = dt.hour * 3600 + dt.min * 60 + dt.sec;

   ENUM_DAY_OF_WEEK current_day = (ENUM_DAY_OF_WEEK)dt.day_of_week;
   if(IsWithinBrokerTradeSessionDay(symbol, current_day, current_seconds, true, has_sessions))
      return true;

   ENUM_DAY_OF_WEEK previous_day = (ENUM_DAY_OF_WEEK)((dt.day_of_week + 6) % 7);
   if(IsWithinBrokerTradeSessionDay(symbol, previous_day, current_seconds, false, has_sessions))
      return true;

   return false;
}

bool IsMarketOpen(string symbol)
{
   if(IsStopped()) return false;

   datetime session_time = GetMarketSessionReferenceTime();
   bool has_broker_sessions = false;
   if(IsWithinBrokerTradeSession(symbol, session_time, has_broker_sessions))
      return true;
   if(has_broker_sessions)
      return false;
    
   MqlDateTime dt;
   TimeGMT(dt);
   int day_of_week = dt.day_of_week;
   double current_hour = dt.hour + dt.min / 60.0;
   
   // Crypto is always open
   if(StringFind(symbol, "BTC") != -1 || StringFind(symbol, "ETH") != -1 || 
      StringFind(symbol, "USDT") != -1)
      return true;
   
   // FIX 1.4: Enhanced forex market hours with low-liquidity zone detection
   // Standard forex hours: Sunday 22:00 UTC - Friday 21:00 UTC
   // Friday 21:00-21:30 UTC = low liquidity zone (can trade but reduced quality)
   
   if(day_of_week == 0)  // Sunday
   {
      return current_hour >= 22.0;  // Opens Sunday 22:00 UTC
   }
   
   if(day_of_week >= 1 && day_of_week <= 4)  // Monday-Thursday
   {
      return true;  // Always open
   }
   
   if(day_of_week == 5)  // Friday
   {
      if(current_hour < 21.0) 
         return true;  // Normal hours
      else if(current_hour >= 21.0 && current_hour < 21.5)
      {
         // Low liquidity zone Friday 21:00-21:30 UTC
         Log(LOG_DEBUG, "IsMarketOpen", symbol + 
             " - Trading in LOW LIQUIDITY period (Fri 21:00-21:30 UTC). Expect wider spreads.");
         return true;  // Allow trading but log warning
      }
      else
         return false;  // Closed Friday 21:30+
   }
   
   return false;  // Saturday and other days closed
}

int CancelAllManagedPendingOrders(string reason)
{
   int cancelled_count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      long magic = OrderGetInteger(ORDER_MAGIC);
      if(magic < Magic_Base || magic >= Magic_Base + 10000)
         continue;

      string order_symbol = OrderGetString(ORDER_SYMBOL);
      bool delete_request_ok = trade.OrderDelete(ticket);
      int delete_retcode = (int)trade.ResultRetcode();
      bool delete_ok = (delete_request_ok && IsSuccessfulOrderCancelRetcode(delete_retcode));
      if(delete_ok)
      {
         cancelled_count++;
         Log(LOG_WARNING, "CancelAllManagedPendingOrders",
             "Cancelled pending order #" + (string)ticket + " for " + order_symbol +
             " (" + reason + ")");
      }
      else
      {
         Log(LOG_WARNING, "CancelAllManagedPendingOrders",
             "Failed to cancel pending order #" + (string)ticket + " for " + order_symbol +
             " (retcode=" + IntegerToString(delete_retcode) + ", " +
             trade.ResultRetcodeDescription() + ", reason=" + reason + ")");
      }
   }

   return cancelled_count;
}

void CloseAllPositions(string reason = "risk closeout")
{
   int cancelled_pending = CancelAllManagedPendingOrders(reason);
   if(cancelled_pending > 0)
   {
      Log(LOG_WARNING, "CloseAllPositions",
          "Cancelled " + IntegerToString(cancelled_pending) +
          " managed pending order(s) before closing positions (" + reason + ")");
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(magic >= Magic_Base && magic < Magic_Base + 10000)
         {
            bool close_request_ok = trade.PositionClose(ticket);
            int close_retcode = (int)trade.ResultRetcode();
            bool close_ok = (close_request_ok && IsSuccessfulCloseRetcode(close_retcode));
            if(close_ok)
            {
               Log(LOG_INFO, "CloseAllPositions", "Closed position #" + (string)ticket);
            }
             else
             {
                Log(LOG_WARNING, "CloseAllPositions",
                    "Failed to close position #" + (string)ticket + " (retcode=" +
                    IntegerToString(close_retcode) + ", " + trade.ResultRetcodeDescription() +
                    ", reason=" + reason + ")");
             }
          }
       }
   }
}

void HaltTrading()
{
    string reason = "Trading halt requested";
    if(g_ProfitTarget_Halt_Bot && g_ProfitTargetToClose > 0.0)
       reason = StringFormat("Profit target halt triggered at $%.2f threshold", g_ProfitTargetToClose);

    if(!g_Bot_Halt_Active)
    {
       g_Bot_Halt_Active = true;
       g_Bot_Halt_Activated_Time = TimeCurrent();
       g_Bot_Halt_Reason = reason;
       Log(LOG_ERROR, "HaltTrading", "--- TRADING HALTED (EA remains attached) --- " + reason);
       SendAlert(ALERT_RISK_CONTROL, "BOT HALTED: " + reason + " (EA remains attached)");
       AuditLog("BOT_HALT", "", reason);
    }
}

datetime GetNextHourBoundary(datetime from_time = 0)
{
   datetime t = (from_time > 0 ? from_time : TimeCurrent());
   datetime next_hour = ((t / 3600) + 1) * 3600;
   if(next_hour <= t)
      next_hour = t + 3600;
   return next_hour;
}

void ActivateDrawdownTradingPause(string stage, string reason, bool send_alert = true)
{
   datetime now = TimeCurrent();
   datetime pause_until = GetNextHourBoundary(now);
   bool extended = (pause_until > g_drawdown_pause_until);
   if(extended)
      g_drawdown_pause_until = pause_until;

   if(extended)
      PersistRiskSessionState();

   string msg = reason + " - Trading paused until " + TimeToString(g_drawdown_pause_until);
   static datetime last_pause_log = 0;
   if(extended || last_pause_log == 0 || (now - last_pause_log) >= 30)
   {
      Log(LOG_ERROR, stage, msg);
      AuditLog("DRAWDOWN_PAUSE", "", msg);
      last_pause_log = now;
   }

   if(send_alert && extended)
      SendAlert(ALERT_DRAWDOWN, msg);
}

bool IsDrawdownLimitExceeded()
{
   datetime current_time = TimeCurrent();
   
   // Ensure daily counters are always current before evaluating limits.
   UpdateDailyCounters();
   if(g_drawdown_pause_until > current_time)
      return true;
   
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   // --- 1. Calculate all DD values first ---
   // CRITICAL FIX #3: Only update g_equity_all_time_high at session start, not every tick
   // Problem: Updating on every equity increase made drawdown calculation stale within seconds
   // Solution: Reset at daily boundary, optionally track intra-session high separately if needed
   static datetime last_dd_session = 0;
   if(last_dd_session != g_trade_day)
   {
      // New trading session started
      g_equity_all_time_high = MathMax(equity, balance);
      last_dd_session = g_trade_day;
      if(Log_Level >= LOG_DEBUG)
         Log(LOG_DEBUG, "IsDrawdownLimitExceeded", 
             StringFormat("New session: g_equity_all_time_high reset to $%.2f", g_equity_all_time_high));
   }

   // FIXED: Clearer daily drawdown calculation
   // Positive value = drawdown (loss), negative = gain (should not trigger)
   double daily_dd_pct = SafeDiv(g_equity_day_start - equity, g_equity_day_start, 0.0) * 100.0;
   
   // FIXED: Account equity drawdown - from all-time high
   double equity_dd_pct = SafeDiv(g_equity_all_time_high - equity, g_equity_all_time_high, 0.0) * 100.0;
   
   // DEBUG: Log drawdown status every 60 seconds for monitoring
   static datetime last_debug_log = 0;
   if(current_time - last_debug_log >= 60)
   {
      last_debug_log = current_time;
      string daily_status = (daily_dd_pct > 0) ? "DD" : "GAIN";
      string account_status = (equity_dd_pct > 0) ? "DD" : "GAIN";
      Log(LOG_DEBUG, "IsDrawdownLimitExceeded",
          StringFormat("Daily: %.2f%% (%s, start: $%.2f, current: $%.2f) | "
                      "Account: %.2f%% (%s, high: $%.2f, current: $%.2f)",
                      MathAbs(daily_dd_pct), daily_status, g_equity_day_start, equity,
                      MathAbs(equity_dd_pct), account_status, g_equity_all_time_high, equity));
   }
   
   // --- 2. Check limits in order of severity (most severe action first) ---

   // A. Critical Drawdown (closes all, then pauses trading until next hour)
   if(g_Critical_Drawdown_Pct_Effective > 0 && equity_dd_pct >= g_Critical_Drawdown_Pct_Effective)
   {
      string msg = "CRITICAL DRAWDOWN REACHED: " + DoubleToString(equity_dd_pct, 2) + "% - CLOSING ALL POSITIONS";
      CloseAllPositions("critical drawdown");
      ActivateDrawdownTradingPause("IsDrawdownLimitExceeded", msg, true);
      return true;
   }

   // B. Account Drawdown (closes all, then pauses trading until next hour)
   if(g_Max_Account_Drawdown_Pct_Effective > 0 && equity_dd_pct >= g_Max_Account_Drawdown_Pct_Effective)
   {
      string msg = "Account drawdown limit exceeded: " + DoubleToString(equity_dd_pct, 2) + "% - CLOSING ALL POSITIONS";
      CloseAllPositions("account drawdown");
      ActivateDrawdownTradingPause("IsDrawdownLimitExceeded", msg, Enable_Drawdown_Alerts);
      return true;
   }
   
   // C. Daily Drawdown (pause trading until next hour)
   // Only triggers if drawdown is positive (actual loss, not gain)
   if(g_Max_Daily_Drawdown_Pct_Effective > 0 && daily_dd_pct > 0 && daily_dd_pct >= g_Max_Daily_Drawdown_Pct_Effective)
   {
      string msg = StringFormat("Daily drawdown limit exceeded: %.2f%% (Limit: %.2f%%) - Start: $%.2f, Current: $%.2f",
                                daily_dd_pct, g_Max_Daily_Drawdown_Pct_Effective, g_equity_day_start, equity);
      ActivateDrawdownTradingPause("IsDrawdownLimitExceeded", msg, Enable_Drawdown_Alerts);
      return true;
   }

   return false;
}

bool IsTradeAllowed(string symbol = "")
{
   if(g_Bot_Halt_Active)
   {
      static datetime last_bot_halt_log = 0;
      datetime halt_now = TimeCurrent();
      if(last_bot_halt_log == 0 || (halt_now - last_bot_halt_log) >= 30)
      {
         string halt_reason = (g_Bot_Halt_Reason != "" ? g_Bot_Halt_Reason : "manual halt");
         Log(LOG_ERROR, "IsTradeAllowed", "Bot halt active - trading blocked (" + halt_reason + ")");
         last_bot_halt_log = halt_now;
      }
      return false;
   }

   EvaluateKillSwitchDailyLoss();
   if(IsKillSwitchActive())
   {
      static datetime last_kill_log = 0;
      datetime now = TimeCurrent();
      if(last_kill_log == 0 || (now - last_kill_log) >= 30)
      {
         Log(LOG_ERROR, "IsTradeAllowed", "Kill switch active - trading blocked (" + g_Kill_Switch_Reason + ")");
         last_kill_log = now;
      }
      return false;
   }

   if(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) == 0)
   {
      Log(LOG_WARNING, "IsTradeAllowed", "Terminal trading not allowed");
      return false;
   }

   if(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) == 0)
   {
      Log(LOG_WARNING, "IsTradeAllowed", "Account trading not allowed");
      return false;
   }

   if(MQLInfoInteger(MQL_TRADE_ALLOWED) == 0)
   {
      Log(LOG_WARNING, "IsTradeAllowed", "MQL trading not allowed");
      return false;
   }

   // Defensive runtime override: if diagnostics mode is enabled, clear any stale
   // abnormal-spread pause state even when other runtime sync paths were skipped.
   if(g_Disable_Abnormal_Market_Pause_For_Diagnostics && g_market_pause_until > 0)
   {
      static datetime last_diag_pause_log = 0;
      datetime now = TimeCurrent();
      if(last_diag_pause_log == 0 || (now - last_diag_pause_log) >= 60)
      {
         Log(LOG_INFO, "IsTradeAllowed",
             "Diagnostics override active - abnormal market pause cleared.");
         last_diag_pause_log = now;
      }
      g_market_pause_until = 0;
   }

   datetime now = TimeCurrent();

   if(IsAbnormalMarketPauseActive(now))
   {
      static datetime last_pause_log = 0;
      if(last_pause_log == 0 || (now - last_pause_log) >= 30)
      {
         int remaining_seconds = (int)(g_market_pause_until - now);
         if(remaining_seconds < 0) remaining_seconds = 0;
         Log(LOG_WARNING, "IsTradeAllowed", "Abnormal market pause active (" + IntegerToString(remaining_seconds) + "s remaining). Disable_All_Gating_Master_Switch overrides this gate.");
         last_pause_log = now;
      }
      return false;
   }

   if(IsDrawdownPauseActive(now))
   {
      static datetime last_drawdown_pause_log = 0;
      if(last_drawdown_pause_log == 0 || (now - last_drawdown_pause_log) >= 30)
      {
         int remaining_seconds = (int)(g_drawdown_pause_until - now);
         if(remaining_seconds < 0) remaining_seconds = 0;
         Log(LOG_WARNING, "IsTradeAllowed", "Drawdown pause active (" + IntegerToString(remaining_seconds) +
             "s remaining, until " + TimeToString(g_drawdown_pause_until) + ")");
         last_drawdown_pause_log = now;
      }
      return false;
   }
   // Keep IsTradeAllowed limited to platform/account availability.
   // Policy gates (daily cap, concurrency, exposure) are enforced in
   // ExecuteTrade()/ProcessTradeRetry() where we can apply EA-owned accounting.

   if(symbol != "")
   {
      long select_status = 0;
      bool has_select_info = SymbolInfoInteger(symbol, SYMBOL_SELECT, select_status);
      if((!has_select_info || select_status == 0) && !SymbolSelect(symbol, true))
      {
         Log(LOG_WARNING, "IsTradeAllowed", "Cannot select symbol " + symbol);
         return false;
      }
   }

   return true;
}

// ===== FIX #9: ENTRY PRICE ALIGNMENT VALIDATION =====
// Ensure entry price is within reasonable distance from key support/resistance levels
// Entry too close to these levels = high risk of immediate stop-out
bool ValidateEntryPriceAlignment(string symbol, double entry_price, int direction, string &reason)
{
   reason = "";
   
   if(entry_price <= 0.0 || !MathIsValidNumber(entry_price))
   {
      reason = "Invalid entry price: " + DoubleToString(entry_price, 8);
      return false;
   }
   
   // Get current market prices
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   if(bid <= 0.0 || ask <= 0.0 || point <= 0.0)
   {
      reason = "Cannot validate: invalid market data";
      return true;  // Don't block on data error, allow trade
   }
   
   // Entry must be within 50 pips of current price (prevent stale entry prices)
   double mid = (bid + ask) / 2.0;
   double max_distance_pips = 50.0;
   double max_distance = max_distance_pips * point;
   double entry_distance_pips = MathAbs(entry_price - mid) / point;
   
   if(entry_distance_pips > max_distance_pips)
   {
      reason = StringFormat("Entry %.2f pips away from mid (%.2f), max allowed %.2f pips",
                           entry_distance_pips, mid, max_distance_pips);
      Log(LOG_WARNING, "ValidateEntryPriceAlignment", symbol + " - " + reason);
      return false;
   }
   
   // For LONG trades: entry should be ABOVE bid (we buy at ask or better)
   // For SHORT trades: entry should be BELOW ask (we sell at bid or better)
   bool price_on_correct_side = (direction > 0) ? (entry_price >= bid) : (entry_price <= ask);
   if(!price_on_correct_side)
   {
      reason = StringFormat("%s entry price %.5f is on wrong side (bid=%.5f, ask=%.5f)",
                           (direction > 0 ? "LONG" : "SHORT"), entry_price, bid, ask);
      Log(LOG_WARNING, "ValidateEntryPriceAlignment", symbol + " - " + reason);
      return false;
   }
   
   return true;
}
// ===== END FIX #9 =====


bool IsValidSymbol(string symbol, bool select_if_missing = true)
{
   if(StringLen(symbol) < 1 || symbol == "0" || symbol == "NULL")
   {
      Log(LOG_WARNING, "IsValidSymbol", "Empty or invalid symbol name");
      return false;
   }
   
   long select_status = 0;
   bool has_select_info = SymbolInfoInteger(symbol, SYMBOL_SELECT, select_status);
   if((!has_select_info || select_status == 0) && select_if_missing)
   {
      if(!SymbolSelect(symbol, true))
      {
         Log(LOG_WARNING, "IsValidSymbol", "Cannot select symbol: " + symbol);
         return false;
      }
      // Refresh selection state after SymbolSelect
      has_select_info = SymbolInfoInteger(symbol, SYMBOL_SELECT, select_status);
   }
   
   if(!has_select_info || select_status == 0)
   {
      Log(LOG_WARNING, "IsValidSymbol", "Symbol not in Market Watch: " + symbol);
      return false;
   }
   
   long trade_mode;
   if(!SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE, trade_mode))
   {
      Log(LOG_WARNING, "IsValidSymbol", "Cannot get trade mode for: " + symbol);
      return false;
   }
   
   if(trade_mode != SYMBOL_TRADE_MODE_FULL)
   {
      Log(LOG_WARNING, "IsValidSymbol", "Symbol " + symbol + " not in full trade mode");
      return false;
   }
   
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   if(bid <= 0 || ask <= 0 || point <= 0 || bid >= ask)
   {
      Log(LOG_WARNING, "IsValidSymbol", "Invalid prices for " + symbol + ": Bid=" + DoubleToString(bid, 5) + ", Ask=" + DoubleToString(ask, 5));
      return false;
   }
   
   return true;
}

bool HasSufficientVolume(string symbol)
{
   double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   if(min_lot <= 0 || lot_step <= 0)
   {
      Log(LOG_WARNING, "HasSufficientVolume", "Invalid lot parameters for " + symbol);
      return false;
   }
   
   return true;
}

bool IsSpreadAcceptable(string symbol)
{
   if(g_Disable_All_Gates || !CGateController::IsSpreadGateEnabled() || !g_Enable_Spread_Gates)
      return true;

   // Secondary quality gate: avoid entering during transient spread spikes
   // even when absolute spread limit is permissive.
   const int SPREAD_REGIME_MIN_SAMPLES = 25;
   const double SPREAD_REGIME_MAX_MULTIPLIER = 2.2;

   int index = GetSymbolIndex(symbol);
   MqlTick tick;
   bool has_tick = SymbolInfoTick(symbol, tick); // refresh quotes

   // Determine spread limit: check symbol-specific config first, then global default
   double max_spread_pips = (double)g_Max_Spread_Pips_Effective;
   
   if(g_Use_Symbol_Specific_Spreads && index >= 0)
   {
      SSymbolSpreadConfig symbol_config = GetSymbolSpreadConfig(symbol);
      if(symbol_config.max_spread_pips > 0)
         max_spread_pips = (double)symbol_config.max_spread_pips;

      if(symbol_config.use_absolute_limit && symbol_config.net_spread_limit_pips > 0.0)
         max_spread_pips = MathMin(max_spread_pips, symbol_config.net_spread_limit_pips);
   }

   int max_spread_points = PipsToPoints(symbol, max_spread_pips);
   if(max_spread_points <= 0)
      max_spread_points = (int)MathRound(max_spread_pips);
   if(index >= 0)
   {
      if(!RefreshSymbolCache(index))
         return false;
      
      double point = g_symbols[index].cache.point;
      int spread_points = 0;
      if(has_tick && tick.bid > 0 && tick.ask > 0 && point > 0)
         spread_points = (int)MathRound((tick.ask - tick.bid) / point);
      else
         spread_points = (int)g_symbols[index].cache.spread;
      bool acceptable = (spread_points <= max_spread_points);
      
      if(!acceptable)
      {
         double spread_pips = PointsToPips(symbol, (double)spread_points);
         Log(LOG_INFO, "IsSpreadAcceptable", "Spread too high: " + DoubleToString(spread_pips, 1) + 
             " pips (limit " + DoubleToString(max_spread_pips, 1) + ")");
      }
      else if(g_symbols[index].cache.spread_avg_samples >= SPREAD_REGIME_MIN_SAMPLES &&
              g_symbols[index].cache.spread_avg_points > 0.0)
      {
         double regime_limit = g_symbols[index].cache.spread_avg_points * SPREAD_REGIME_MAX_MULTIPLIER;
         if((double)spread_points > regime_limit)
         {
            double spread_pips = PointsToPips(symbol, (double)spread_points);
            double regime_limit_pips = PointsToPips(symbol, regime_limit);
            Log(LOG_INFO, "IsSpreadAcceptable",
                symbol + " - Spread regime spike: " + DoubleToString(spread_pips, 1) +
                " pips > dynamic limit " + DoubleToString(regime_limit_pips, 1) + " pips");
            acceptable = false;
         }
      }

      if(!g_Disable_Abnormal_Market_Pause_For_Diagnostics &&
         g_Enable_Abnormal_Market_Pause && !g_Disable_All_Gates && index >= 0 && index < MAX_SYMBOLS)
      {
         if(acceptable)
         {
            if(g_spread_spike_count[index] > 0)
               g_spread_spike_count[index]--;
         }
         else
         {
            g_spread_spike_count[index]++;
            if(g_Abnormal_Spread_Spike_Threshold > 0 &&
               g_spread_spike_count[index] >= g_Abnormal_Spread_Spike_Threshold)
            {
               int pause_seconds = MathMax(60, g_Abnormal_Market_Pause_Minutes * 60);
               datetime now = TimeCurrent();
               datetime pause_until = now + pause_seconds;
               if(pause_until > g_market_pause_until)
                  g_market_pause_until = pause_until;

               g_spread_spike_count[index] = 0;
               Log(LOG_WARNING, "IsSpreadAcceptable",
                   symbol + " - Abnormal spread regime detected repeatedly; trading paused until " +
                   TimeToString(g_market_pause_until));
            }
         }
      }
      else if(g_Disable_Abnormal_Market_Pause_For_Diagnostics && index >= 0 && index < MAX_SYMBOLS)
      {
         // Keep diagnostics runs deterministic: no carry-over spike counts.
         g_spread_spike_count[index] = 0;
      }
       
      return acceptable;
   }
   
   long spread;
   if(!SymbolInfoInteger(symbol, SYMBOL_SPREAD, spread))
      return false;
   
   return ((int)spread <= max_spread_points);
}

double GetRiskBaseValue()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   // Respect user control explicitly: equity-vs-balance base should not be forced by feature toggles.
   bool use_equity = Risk_Use_Equity;
   
   if(use_equity)
      return (equity > 0.0 ? equity : balance);
   
   return (balance > 0.0 ? balance : equity);
}

double ResolveMaxOpenRiskPct()
{
   double pct = g_Max_Open_Risk_Pct_Effective;
   if(pct <= 0.0)
      pct = g_Risk_Percent_Effective * MathMax(1, g_Max_Concurrent_Trades_Effective);

   // Harmonize execution with scoring: risk caps should not be tighter than per-trade risk.
   if(Enable_All_Institutional_Filters)
      pct = MathMax(pct, g_Risk_Percent_Effective);

   return pct;
}

double ResolveMaxSymbolRiskPct()
{
   double pct = g_Max_Symbol_Risk_Pct_Effective;
   if(pct <= 0.0)
      pct = g_Risk_Percent_Effective;

   // Harmonize execution with scoring: symbol cap should not undercut configured per-trade risk.
   if(Enable_All_Institutional_Filters)
      pct = MathMax(pct, g_Risk_Percent_Effective);

   double open_pct = ResolveMaxOpenRiskPct();
   if(open_pct > 0.0 && pct > open_pct)
      pct = open_pct;

   return pct;
}

int OrderTypeToDirection(ENUM_ORDER_TYPE type)
{
   if(type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_STOP_LIMIT)
      return 1;
   if(type == ORDER_TYPE_SELL || type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_SELL_STOP || type == ORDER_TYPE_SELL_STOP_LIMIT)
      return -1;
   return 0;
}

double CalculateTradeRiskCurrency(string symbol, int direction, double volume, double entry_price, double sl_price)
{
   if(volume <= 0.0 || entry_price <= 0.0 || sl_price <= 0.0 || direction == 0)
      return 0.0;
   
   ENUM_ORDER_TYPE order_type = (ENUM_ORDER_TYPE)(direction == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double profit = 0.0;
   if(OrderCalcProfit(order_type, symbol, volume, entry_price, sl_price, profit))
      return MathAbs(profit);
   
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0)
      tick_size = point;
   double tick_value_loss = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   double tick_value = (tick_value_loss > 0.0 ? tick_value_loss : SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE));
   
   if(point <= 0.0 || tick_size <= 0.0 || tick_value <= 0.0)
      return 0.0;
   
   return MathAbs(entry_price - sl_price) / tick_size * tick_value * volume;
}

// ===== FIX #3 HELPER: Get total open risk across all positions =====
double GetTotalOpenRisk()
{
   return GetOpenRiskCurrency("", 0);  // Call existing function with no filters
}
// ===== END FIX #3 HELPER =====

double GetOpenRiskCurrency(string symbol_filter = "", int direction_filter = 0)
{
   double total_risk = 0.0;
   double risk_base = GetRiskBaseValue();
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic < Magic_Base || magic >= Magic_Base + 10000)
         continue;
      
      string symbol = PositionGetString(POSITION_SYMBOL);
      if(symbol_filter != "" && symbol != symbol_filter)
         continue;
      
      long type_long = PositionGetInteger(POSITION_TYPE);
      int direction = (type_long == POSITION_TYPE_BUY) ? 1 : (type_long == POSITION_TYPE_SELL ? -1 : 0);
      if(direction == 0)
         continue;
      if(direction_filter != 0 && direction != direction_filter)
         continue;
      
      double sl = PositionGetDouble(POSITION_SL);
      if(sl <= 0.0)
      {
         if(risk_base > 0.0)
            total_risk += risk_base;  // Treat missing SL as full-account risk
         continue;
      }
      
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double volume = PositionGetDouble(POSITION_VOLUME);
      total_risk += CalculateTradeRiskCurrency(symbol, direction, volume, entry, sl);
   }
   
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      
      long magic = OrderGetInteger(ORDER_MAGIC);
      if(magic < Magic_Base || magic >= Magic_Base + 10000)
         continue;
      
      ENUM_ORDER_TYPE order_type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      int direction = OrderTypeToDirection(order_type);
      if(direction == 0)
         continue;
      if(direction_filter != 0 && direction != direction_filter)
         continue;
      
      string symbol = OrderGetString(ORDER_SYMBOL);
      if(symbol_filter != "" && symbol != symbol_filter)
         continue;
      
      double sl = OrderGetDouble(ORDER_SL);
      if(sl <= 0.0)
      {
         if(risk_base > 0.0)
            total_risk += risk_base;
         continue;
      }
      
      double entry = OrderGetDouble(ORDER_PRICE_OPEN);
      double volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
      total_risk += CalculateTradeRiskCurrency(symbol, direction, volume, entry, sl);
   }
   
   return total_risk;
}

bool IsLossCooldownActive()
{
   if(!g_Enable_Institutional_Risk)
      return false;
   if(Max_Consecutive_Losses <= 0 || Loss_Cooldown_Minutes <= 0)
      return false;
   
   datetime now = TimeCurrent();
   if(g_risk_cooldown_until > now)
   {
      static datetime last_log = 0;
      if(now - last_log > 30)
      {
         last_log = now;
         int remaining = (int)((g_risk_cooldown_until - now) / 60);
         Log(LOG_WARNING, "IsLossCooldownActive", "Loss cooldown active (" + IntegerToString(remaining) + " min remaining)");
      }
      return true;
   }
   return false;
}

// CRITICAL FIX #3: Loss Protection with Exponential Escalation + Position Closure
void ProcessLossProtectionEscalation(string symbol, double loss_amount)
{
   if(symbol == "")
      return;

   datetime now = TimeCurrent();
   int sym_idx = GetSymbolIndex(symbol);
   
   if(sym_idx < 0 || sym_idx >= MAX_SYMBOLS)
      return;

   // Increment consecutive loss counter
   g_symbol_loss_streak[sym_idx]++;
   g_symbol_last_loss_time[sym_idx] = now;

   // CRITICAL: Exponential escalation system
   datetime escalated_cooldown_until = now;
   
   if(g_symbol_loss_streak[sym_idx] >= 5)
   {
      // Level 3: STOP TRADING THIS SYMBOL FOR REST OF DAY + FORCE CLOSE POSITIONS
      // CRITICAL FIX #2: Close all positions immediately to prevent additional losses during ban
      CloseAllSymbolPositions(symbol);
      escalated_cooldown_until = now + 86400;  // 24 hours / rest of day
      Log(LOG_ERROR, "ProcessLossProtectionEscalation",
          StringFormat("%s HALTED: 5 consecutive losses detected. All positions FORCE CLOSED. No more trades for 24 hours.", symbol));
      SendAlert(ALERT_RISK_CONTROL, symbol + " trading HALTED: 5 losses - positions force closed");
   }
   else if(g_symbol_loss_streak[sym_idx] >= 4)
   {
      // Level 2: RESTRICTED - 120 minute cooldown (consider closing losing positions)
      escalated_cooldown_until = now + 120 * 60;  // 2 hours
      Log(LOG_WARNING, "ProcessLossProtectionEscalation",
          StringFormat("%s: 4 consecutive losses - RESTRICTED MODE, 2-hour cooldown", symbol));
      SendAlert(ALERT_RISK_CONTROL, symbol + " in RESTRICTED mode: 4 losses");
   }
   else if(g_symbol_loss_streak[sym_idx] >= 3)
   {
      // Level 1: CAUTION - 60 minute cooldown
      escalated_cooldown_until = now + 60 * 60;  // 1 hour
      Log(LOG_WARNING, "ProcessLossProtectionEscalation",
          StringFormat("%s: 3 consecutive losses - CAUTION MODE, 1-hour cooldown", symbol));
   }
   else if(g_symbol_loss_streak[sym_idx] >= 2)
   {
      // Level 0 (escalating): 30 minute cooldown
      escalated_cooldown_until = now + 30 * 60;  // 30 minutes
      Log(LOG_WARNING, "ProcessLossProtectionEscalation",
          StringFormat("%s: 2 consecutive losses - 30-minute cooldown", symbol));
   }
   else
   {
      // Single loss: no cooldown
      return;
   }

   g_symbol_loss_cooldown_until[sym_idx] = escalated_cooldown_until;
}

// CRITICAL FIX #2 HELPER: Close all open positions for a specific symbol
void CloseAllSymbolPositions(string symbol)
{
   int closed_count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         string pos_symbol = PositionGetString(POSITION_SYMBOL);
         if(pos_symbol == symbol)
         {
            long magic = PositionGetInteger(POSITION_MAGIC);
            if(magic >= Magic_Base && magic < Magic_Base + 10000)
            {
               bool close_ok = trade.PositionClose(ticket);
               if(close_ok)
               {
                  closed_count++;
                  Log(LOG_INFO, "CloseAllSymbolPositions", symbol + " - Closed position #" + (string)ticket);
               }
               else
               {
                  Log(LOG_WARNING, "CloseAllSymbolPositions", symbol + " - Failed to close position #" + (string)ticket);
               }
            }
         }
      }
   }
   if(closed_count > 0)
   {
      Log(LOG_ERROR, "CloseAllSymbolPositions", 
          StringFormat("%s - Force closed %d positions due to loss escalation", symbol, closed_count));
   }
}

// Helper to reset loss escalation when profit is achieved
void ResetLossEscalation(string symbol)
{
   if(symbol == "")
      return;

   int sym_idx = GetSymbolIndex(symbol);
   if(sym_idx < 0 || sym_idx >= MAX_SYMBOLS)
      return;

   if(g_symbol_loss_streak[sym_idx] > 0)
   {
      int prev_streak = g_symbol_loss_streak[sym_idx];
      g_symbol_loss_streak[sym_idx] = 0;
      g_symbol_loss_cooldown_until[sym_idx] = 0;
      Log(LOG_INFO, "ResetLossEscalation",
          StringFormat("%s: Loss streak broken after %d losses. Ready to trade.", symbol, prev_streak));
   }
}

bool IsSymbolLossCooldownActive(string symbol)
{
   if(!g_Enable_Institutional_Risk || !g_Enable_Symbol_Loss_Circuit_Breaker)
      return false;

   if(symbol == "")
      return false;

   int symbol_index = GetSymbolIndex(symbol);
   if(symbol_index < 0 || symbol_index >= g_symbols_count || symbol_index >= MAX_SYMBOLS)
      return false;

   datetime now = TimeCurrent();
   if(g_symbol_loss_cooldown_until[symbol_index] > now)
   {
      static datetime last_symbol_log[MAX_SYMBOLS];
      if(last_symbol_log[symbol_index] == 0 || (now - last_symbol_log[symbol_index]) >= 30)
      {
         int remaining = (int)((g_symbol_loss_cooldown_until[symbol_index] - now) / 60);
         if(remaining < 0) remaining = 0;
         Log(LOG_WARNING, "IsSymbolLossCooldownActive",
             symbol + " - Symbol loss cooldown active (" + IntegerToString(remaining) +
             " min remaining)");
         last_symbol_log[symbol_index] = now;
      }
      return true;
   }

   return false;
}

bool CheckInstitutionalRiskLimits(string symbol, int direction, double volume, double entry_price, double sl_price)
{
   if(!g_Enable_Institutional_Risk)
      return true;
   
   if(volume <= 0.0 || entry_price <= 0.0 || sl_price <= 0.0 || direction == 0)
   {
      Log(LOG_WARNING, "CheckInstitutionalRiskLimits", symbol + " - Invalid trade inputs for risk checks");
      return false;
   }
   
   if(IsLossCooldownActive())
      return false;

   if(IsSymbolLossCooldownActive(symbol))
      return false;
   
   double risk_base = GetRiskBaseValue();
   if(risk_base <= 0.0)
   {
      Log(LOG_WARNING, "CheckInstitutionalRiskLimits", symbol + " - Invalid account base for risk");
      return false;
   }
   
   double trade_risk = CalculateTradeRiskCurrency(symbol, direction, volume, entry_price, sl_price);
   if(trade_risk <= 0.0 || !MathIsValidNumber(trade_risk))
   {
      Log(LOG_WARNING, "CheckInstitutionalRiskLimits", symbol + " - Unable to calculate trade risk");
      return false;
   }

   double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   bool min_lot_trade = (min_lot > 0.0 && volume <= min_lot * 1.01);
   double min_lot_relief_pct = 0.0;
   if(Enable_All_Institutional_Filters && !g_Skip_MinLot_Overrisk && min_lot_trade)
   {
      // Controlled relief so broker min-lot floor does not fully deadlock scoring-approved signals.
      // Still bounded to keep risk discipline.
      min_lot_relief_pct = MathMin(8.0, MathMax(g_Risk_Percent_Effective * 6.0, 2.5));
   }
   
   double max_open_pct = ResolveMaxOpenRiskPct();
   if(min_lot_relief_pct > 0.0)
      max_open_pct = MathMax(max_open_pct, min_lot_relief_pct);
   if(max_open_pct > 0.0)
   {
      double open_risk = GetOpenRiskCurrency();
      double max_open_risk = risk_base * max_open_pct / 100.0;
      if((open_risk + trade_risk) > max_open_risk)
      {
         Log(LOG_WARNING, "CheckInstitutionalRiskLimits",
             StringFormat("%s - Open risk limit exceeded: $%.2f + $%.2f > $%.2f (%.2f%%)",
                          symbol, open_risk, trade_risk, max_open_risk, max_open_pct));
         return false;
      }
   }
   
   double max_symbol_pct = ResolveMaxSymbolRiskPct();
   if(min_lot_relief_pct > 0.0)
      max_symbol_pct = MathMax(max_symbol_pct, min_lot_relief_pct);
   if(max_symbol_pct > 0.0)
   {
      double symbol_risk = GetOpenRiskCurrency(symbol);
      double max_symbol_risk = risk_base * max_symbol_pct / 100.0;
      if((symbol_risk + trade_risk) > max_symbol_risk)
      {
         Log(LOG_WARNING, "CheckInstitutionalRiskLimits",
             StringFormat("%s - Symbol risk limit exceeded: $%.2f + $%.2f > $%.2f (%.2f%%)",
                          symbol, symbol_risk, trade_risk, max_symbol_risk, max_symbol_pct));
         return false;
      }
   }
   
   if(Max_Margin_Usage_Pct > 0.0 || Min_Margin_Level_Pct > 0.0)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double margin = AccountInfoDouble(ACCOUNT_MARGIN);
      if(equity > 0.0)
      {
         ENUM_ORDER_TYPE order_type = (ENUM_ORDER_TYPE)(direction == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
         double new_margin = 0.0;
         if(OrderCalcMargin(order_type, symbol, volume, entry_price, new_margin))
         {
            double usage_pct = SafeDiv(margin + new_margin, equity, 0.0) * 100.0;
            if(Max_Margin_Usage_Pct > 0.0 && usage_pct > Max_Margin_Usage_Pct)
            {
               Log(LOG_WARNING, "CheckInstitutionalRiskLimits",
                   StringFormat("%s - Margin usage %.1f%% exceeds limit %.1f%%",
                                symbol, usage_pct, Max_Margin_Usage_Pct));
               return false;
            }
            
            double projected_margin_level = (margin + new_margin) > 0.0 ? (equity / (margin + new_margin) * 100.0) : 100000.0;
            if(Min_Margin_Level_Pct > 0.0 && projected_margin_level < Min_Margin_Level_Pct)
            {
               Log(LOG_WARNING, "CheckInstitutionalRiskLimits",
                   StringFormat("%s - Projected margin level %.1f%% below limit %.1f%%",
                                symbol, projected_margin_level, Min_Margin_Level_Pct));
               return false;
            }
         }
      }
   }
   
   return true;
}

double CalculatePositionSize(string symbol, double stop_loss_distance, double adaptive_risk_pct = -1.0, double ai_confidence = 0.5,
                             double entry_price = 0.0, double stop_loss_price = 0.0, double take_profit_price = 0.0, int direction = 1)
{
   g_last_position_size_reason = "";
   g_last_position_size_raw_lot = 0.0;
   g_last_position_size_min_lot = 0.0;

   if(stop_loss_distance <= 0)
   {
      g_last_position_size_reason = "invalid_stop_distance";
      Log(LOG_ERROR, "CalculatePositionSize", "Invalid stop loss distance");
      return 0.0;
   }
   
   // ===== FIX #1: TRUE RISK/REWARD CALCULATION =====
   // If we have actual prices, calculate the EFFECTIVE stop loss distance accounting for spread & swap costs
   double effective_sl_distance = stop_loss_distance;  // Default: use nominal distance
   
   if(entry_price > 0.0 && stop_loss_price > 0.0 && take_profit_price > 0.0)
   {
      // Calculate true RR using actual prices (accounts for spread + swap costs)
      bool is_long = (direction > 0);
      double true_rr = CalculateTrueRiskRewardRatio(symbol, entry_price, take_profit_price, stop_loss_price, is_long, 1);
      double nominal_rr = (take_profit_price > entry_price) ? 
                         (take_profit_price - entry_price) / MathAbs(stop_loss_price - entry_price) :
                         (entry_price - take_profit_price) / MathAbs(stop_loss_price - entry_price);
      
      // CRITICAL: If true RR is significantly worse than nominal, adjust position size down
      if(true_rr > 0.0 && nominal_rr > 0.0 && true_rr < nominal_rr)
      {
         // Effective risk is HIGHER when accounting for spread/swap
         // Example: nominal RR=1.0, true RR=0.8 means real risk is 25% higher (1/0.8=1.25)
         // So we must reduce position size by the same ratio
         double rr_adjustment_factor = true_rr / nominal_rr;  // Will be < 1.0
         effective_sl_distance = stop_loss_distance / rr_adjustment_factor;  // Increase effective distance
         
         Log(LOG_DEBUG, "CalculatePositionSize", 
             StringFormat("%s - TRUE RR ADJUSTMENT: nominal_rr=%.2f, true_rr=%.2f, adjustment_factor=%.2f, effective_sl_distance=%.2f->%.2f pips",
                         symbol, nominal_rr, true_rr, rr_adjustment_factor, stop_loss_distance, effective_sl_distance));
      }
      else if(true_rr <= 0.0)
      {
         // Trade has negative expected value (real risk > real reward), REJECT it
         Log(LOG_WARNING, "CalculatePositionSize",
             StringFormat("%s - TRADE REJECTED: true_rr=%.2f (negative EV). Entry=%.5f, SL=%.5f, TP=%.5f",
                         symbol, true_rr, entry_price, stop_loss_price, take_profit_price));
         g_last_position_size_reason = "negative_true_rr";
         return 0.0;
      }
   }
   // ===== END FIX #1 =====
   
   double account_base = GetRiskBaseValue();
   if(account_base <= 0)
   {
      g_last_position_size_reason = "invalid_account_base";
      Log(LOG_ERROR, "CalculatePositionSize", "Invalid account base for risk sizing");
      return 0.0;
   }
   
   // I1 FIX: Separate base risk validation from adaptive (post-multiplied) risk
   // Validate BASE risk ONLY (when adaptive_risk_pct not provided)
   // Adaptive risk already clamped [0.10, 10.0] at source, so accept higher values
   double risk_pct = (adaptive_risk_pct > 0) ? adaptive_risk_pct : g_Risk_Percent_Effective;
   
   // P4: Validate ONLY base risk percent bounds [0.01, 2.0] to prevent over-leverage
   // Note: if adaptive_risk_pct > 0, it's post-multiplied and already bounded at source (TradeManagement line 2369)
   if(adaptive_risk_pct <= 0)
   {
      // This is BASE risk from g_Risk_Percent_Effective - strict validation
      if(!MathIsValidNumber(risk_pct) || risk_pct < 0.01 || risk_pct > 2.0)
      {
         if(!MathIsValidNumber(risk_pct))
            Log(LOG_WARNING, "CalculatePositionSize", "Base risk_pct is NaN, resetting to 0.50");
         else if(risk_pct < 0.01)
            Log(LOG_WARNING, "CalculatePositionSize", "Base risk_pct too low: " + DoubleToString(risk_pct, 2) + "%, resetting to 0.50");
         else
            Log(LOG_WARNING, "CalculatePositionSize", "Base risk_pct too high: " + DoubleToString(risk_pct, 2) + "%, resetting to 0.50 (max 2.0%)");
         risk_pct = 0.50;  // Reset to safe default
      }
   }
   else
   {
      // This is ADAPTIVE risk (post-multiplier) - light validation only for NaN/Infinity
      if(!MathIsValidNumber(risk_pct))
      {
         Log(LOG_WARNING, "CalculatePositionSize", "Adaptive risk_pct is NaN (post-multipliers), using 1.00");
         risk_pct = 1.00;  // Neutral position sizing multiplier
      }
      // Note: value might be 0.10-10.0 (from TradeManagement clamp), that's expected
   }
   
   // AI risk adjustment is optional and never upscales above baseline risk.
   double ai_risk_multiplier = 1.0;  // Default: full risk
   if(g_ai_enabled && g_AI_Use_Risk_Adjustment_Runtime && ai_confidence > 0.0)
   {
      // Use AIInferenceEngine for enhanced decision making
      string signal_strength = AIInferenceEngine::GetSignalStrength(ai_confidence);
      
      // Deterministic down-scaling only: low AI confidence reduces risk,
      // high confidence keeps baseline configured risk.
      if(ai_confidence < 0.4)
      {
         ai_risk_multiplier = 0.5 + (ai_confidence / 0.4) * 0.3; // 0.5x to 0.8x
      }
      else if(ai_confidence < 0.6)
      {
         ai_risk_multiplier = 0.8 + ((ai_confidence - 0.4) / 0.2) * 0.2; // 0.8x to 1.0x
      }
      else
      {
         ai_risk_multiplier = 1.0; // Do not exceed configured base risk
      }
      
      ai_risk_multiplier = MathMin(ai_risk_multiplier, 1.0);  // Never upscale risk
      ai_risk_multiplier = MathMax(ai_risk_multiplier, 0.5);  // Floor at 0.5x
      
      Log(LOG_DEBUG, "CalculatePositionSize", 
         StringFormat("AI Risk Multiplier: %.2fx (confidence: %.1f%%, strength: %s)", 
            ai_risk_multiplier, ai_confidence * 100, signal_strength));
   }
   
   // ===== TIER 2B ENHANCEMENT: VOLATILITY FORECASTER =====
   // Adjust position sizing based on predicted volatility spikes
   double vol_adjustment = 1.0;
   {
      // Get volatility forecast for the signal timeframe
      int symbol_index = GetSymbolIndex(symbol);
      if(symbol_index >= 0)
      {
         SVolatilityForecast vol_forecast = CVolatilityForecaster::PredictVolatility(symbol, Signal_TF);
         
         // Adjust position size based on predicted volatility environment
         // High volatility spike: reduce position to 0.65x
         // Normal volatility: keep standard sizing (1.0x)
         // Low volatility: maintain standard (meanders increase risk)
         vol_adjustment = vol_forecast.position_size_adjustment;
         
         if(g_Enable_Institutional_Debug)
            Log(LOG_DEBUG, "CalculatePositionSize", symbol + 
                " - Tier 2B: Vol forecast=" + DoubleToString(vol_forecast.predicted_volatility, 2) +
                ", spike_likelihood=" + DoubleToString(vol_forecast.vol_spike_likelihood, 2) +
                ", adjust=" + DoubleToString(vol_adjustment, 2));
      }
   }
   // ===== END TIER 2B =====
   
   double risk_amount = account_base * risk_pct / 100.0 * ai_risk_multiplier * vol_adjustment;

   // ===== NEW: ENFORCE SYMBOL RISK CAP =====
   // Position sizing must respect both per-trade risk AND per-symbol risk limits.
   // If symbol cap is stricter than per-trade risk, scale down the risk amount.
   double max_symbol_pct = ResolveMaxSymbolRiskPct();
   double max_symbol_risk = account_base * max_symbol_pct / 100.0;
   double current_symbol_risk = GetOpenRiskCurrency(symbol);
   
   if(max_symbol_risk > 0.0 && (current_symbol_risk + risk_amount) > max_symbol_risk)
   {
      double available_symbol_risk = MathMax(0.0, max_symbol_risk - current_symbol_risk);
      if(available_symbol_risk > 0.0)
      {
         Log(LOG_WARNING, "CalculatePositionSize", 
            StringFormat("%s - Position risk scaled down due to symbol cap: %.2f%% [%.2f] -> %.2f%% [%.2f] " +
                        "(current: %.2f, limit: %.2f)",
                        symbol, risk_pct, risk_amount, max_symbol_pct, available_symbol_risk,
                        current_symbol_risk, max_symbol_risk));
         risk_amount = available_symbol_risk;
      }
      else if(available_symbol_risk <= 0.0)
      {
         // Symbol cap is full but allow trade to proceed with minimal risk
         double account_equity = AccountInfoDouble(ACCOUNT_EQUITY);
         double equity_pct = (account_equity > 0.0) ? (max_symbol_risk / account_equity * 100.0) : 0.0;
         Log(LOG_WARNING, "CalculatePositionSize", 
            StringFormat("%s - Symbol risk cap full: %.2f (limit: %.2f@%.2f%% equity). Using minimum allowable position.",
                        symbol, current_symbol_risk, max_symbol_risk, equity_pct));
         // Allow trade to proceed; position sizing will use minimum lot.
      }
   }
   // ===== END SYMBOL RISK CAP =====

   CSymbolInfo sym_info;
   if(!sym_info.Name(symbol))
   {
      g_last_position_size_reason = "symbol_init_failed";
      Log(LOG_ERROR, "CalculatePositionSize", "Failed to set symbol: " + symbol);
      return 0.0;
   }
   
   // CRITICAL FIX: Enhanced validation for all division operations
   if(!sym_info.RefreshRates())
   {
      g_last_position_size_reason = "refresh_rates_failed";
      Log(LOG_ERROR, "CalculatePositionSize", "Failed to refresh rates for " + symbol);
      return 0.0;
   }

   double tick_value = sym_info.TickValue();
   double tick_size = sym_info.TickSize();
   double point = sym_info.Point();

   if(tick_size <= 0.0 || !MathIsValidNumber(tick_size))
      tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0 || !MathIsValidNumber(tick_size))
      tick_size = point;

   if(tick_value <= 0.0 || !MathIsValidNumber(tick_value))
      tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tick_value <= 0.0 || !MathIsValidNumber(tick_value))
      tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);

   // CRITICAL: Validate all values before any calculations
   if(tick_size <= 0.0 || !MathIsValidNumber(tick_size))
   {
      g_last_position_size_reason = "invalid_tick_size";
      Log(LOG_ERROR, "CalculatePositionSize", "Invalid tick_size: " + DoubleToString(tick_size, 8));
      return 0.0;
   }
   
   if(tick_value <= 0.0 || !MathIsValidNumber(tick_value))
   {
      // Final fallback via broker-side P/L calc for 1 lot across stop distance.
      double px = sym_info.Bid();
      if(px <= 0.0 || !MathIsValidNumber(px))
         px = sym_info.Ask();
      if(px > 0.0 && MathIsValidNumber(px))
      {
         double profit_probe = 0.0;
         if(OrderCalcProfit(ORDER_TYPE_BUY, symbol, 1.0, px, px - effective_sl_distance, profit_probe))
         {
            double loss_probe = MathAbs(profit_probe);
            if(loss_probe > 0.0 && MathIsValidNumber(loss_probe))
            {
               tick_value = loss_probe;
               tick_size = effective_sl_distance;
            }
         }
      }

      if(tick_value <= 0.0 || !MathIsValidNumber(tick_value))
      {
         g_last_position_size_reason = "invalid_tick_value";
         Log(LOG_ERROR, "CalculatePositionSize", "Invalid tick_value: " + DoubleToString(tick_value, 8));
         return 0.0;
      }
   }

   // SAFE division with validation
   double loss_in_currency = SafeDiv(effective_sl_distance, tick_size, 0.0) * tick_value;
   if(loss_in_currency <= 0.0 || !MathIsValidNumber(loss_in_currency))
   {
      g_last_position_size_reason = "invalid_loss_calc";
      Log(LOG_ERROR, "CalculatePositionSize", "Invalid loss calculation: " + DoubleToString(loss_in_currency, 2));
      return 0.0;
   }

   double raw_lot_size = SafeDiv(risk_amount, loss_in_currency, 0.0);
   g_last_position_size_raw_lot = raw_lot_size;
   if(raw_lot_size <= 0.0 || !MathIsValidNumber(raw_lot_size))
   {
      g_last_position_size_reason = "invalid_raw_lot";
      Log(LOG_ERROR, "CalculatePositionSize", "Invalid raw lot size: " + DoubleToString(raw_lot_size, 4));
      return 0.0;
   }

   double min_lot = sym_info.LotsMin();
   g_last_position_size_min_lot = min_lot;
   double max_lot = sym_info.LotsMax();
   double lot_step = sym_info.LotsStep();
   
   // ===== FIX #2: ENFORCE PER-TRADE POSITION SIZE CAP =====
   // Never allow a single trade to use more than configurable % of account.
   // Use the same effective stop-loss cost model as the base lot calculation so
   // caps stay consistent when tick_size != point or true-RR widened effective SL.
   double max_per_trade_pct = 10.0;  // Hard cap: max 10% of account per trade
   double account_balance = GetRiskBaseValue();
   double max_per_trade_risk = account_balance * max_per_trade_pct / 100.0;
   double per_lot_loss_in_currency = loss_in_currency;
   double trade_risk = raw_lot_size * per_lot_loss_in_currency;
   
   if(trade_risk > max_per_trade_risk)
   {
      // Scale down lot size to respect per-trade cap
      double allowed_ratio = max_per_trade_risk / trade_risk;
      double capped_lot_size = raw_lot_size * allowed_ratio;
      
      Log(LOG_WARNING, "CalculatePositionSize",
          StringFormat("%s - FIX #2: Per-trade risk cap imposed: %.2f lots -> %.2f lots (%.1f%% of account max)",
                       symbol, raw_lot_size, capped_lot_size, max_per_trade_pct));
      
      raw_lot_size = capped_lot_size;
      trade_risk = raw_lot_size * per_lot_loss_in_currency;
   }
   
   // ===== FIX #3: ENFORCE RISK DISTRIBUTION ACROSS TRADES =====
   // No single trade should represent more than 30% of total open risk
   double total_open_risk = GetTotalOpenRisk();
   max_per_trade_pct = 30.0;
   double max_risk_distribution = total_open_risk * max_per_trade_pct / 100.0;
   
   if(trade_risk > max_risk_distribution && total_open_risk > 0.0)
   {
      double dist_ratio = max_risk_distribution / trade_risk;
      double dist_capped_lot = raw_lot_size * dist_ratio;
      
      Log(LOG_WARNING, "CalculatePositionSize",
          StringFormat("%s - FIX #3: Risk distribution cap: %.2f lots -> %.2f lots (max %.0f%% of total risk=%.2f)",
                       symbol, raw_lot_size, dist_capped_lot, max_per_trade_pct, total_open_risk));
      
      raw_lot_size = MathMin(raw_lot_size, dist_capped_lot);
      trade_risk = raw_lot_size * per_lot_loss_in_currency;
   }
   // ===== END FIX #3 =====
   
   if(g_Enable_Institutional_Risk && g_Skip_MinLot_Overrisk && raw_lot_size < min_lot)
   {
      g_last_position_size_reason = "below_min_lot_overrisk";
      Log(LOG_WARNING, "CalculatePositionSize", symbol + " - Raw lot " + DoubleToString(raw_lot_size, 4) +
          " below min lot " + DoubleToString(min_lot, 2) + " (would over-risk). Skipping.");
      return 0.0;
   }
   
   double lot_size = raw_lot_size;

   if(lot_step > 0)
      lot_size = MathFloor(lot_size / lot_step) * lot_step;

   lot_size = MathMax(lot_size, min_lot);
   lot_size = MathMin(lot_size, max_lot);

   // Use broker-side margin calculation for accurate symbol/account margin rules.
   double required_margin = 0.0;
   double margin_price = sym_info.Ask();
   if(margin_price <= 0.0)
      margin_price = sym_info.Bid();
   if(margin_price <= 0.0)
      margin_price = SymbolInfoDouble(symbol, SYMBOL_ASK);

   if(margin_price > 0.0)
   {
      if(!OrderCalcMargin(ORDER_TYPE_BUY, symbol, lot_size, margin_price, required_margin))
         required_margin = 0.0;
   }

   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   
   if(free_margin > 0.0 && required_margin > 0.0 && free_margin < required_margin * 1.1) // Require 10% buffer
   {
      Log(LOG_WARNING, "CalculatePositionSize", symbol + " - Insufficient margin. Required: " + 
          DoubleToString(required_margin, 2) + ", Free: " + DoubleToString(free_margin, 2));
      
      // SAFE reduction with validation
      if(required_margin > 0.0)
      {
         double margin_ratio = SafeDiv(free_margin, required_margin, 0.0);
         double reduced_lot = lot_size * margin_ratio * 0.9; // 90% of available
         if(lot_step > 0.0)
            reduced_lot = MathFloor(reduced_lot / lot_step) * lot_step;
         if(g_Enable_Institutional_Risk && g_Skip_MinLot_Overrisk && reduced_lot < min_lot)
         {
            g_last_position_size_reason = "margin_reduced_below_min_lot_overrisk";
            Log(LOG_WARNING, "CalculatePositionSize", symbol + " - Margin-reduced lot " +
                DoubleToString(reduced_lot, 4) + " below min lot " + DoubleToString(min_lot, 2) +
                " (would over-risk). Skipping.");
            return 0.0;
         }
         
         lot_size = reduced_lot;
         lot_size = MathMax(lot_size, min_lot);
         lot_size = MathMin(lot_size, max_lot);
      }
   }

   if(lot_size <= 0 || !MathIsValidNumber(lot_size))
   {
      g_last_position_size_reason = "invalid_final_lot";
      Log(LOG_ERROR, "CalculatePositionSize", "Invalid lot size: " + DoubleToString(lot_size, 2));
      return 0.0;
   }

   g_last_position_size_reason = "ok";

   Log(LOG_DEBUG, "CalculatePositionSize", symbol + " - Lot: " + DoubleToString(lot_size, 2) + 
       ", Risk: $" + DoubleToString(risk_amount, 2) + ", SL Distance: " + DoubleToString(stop_loss_distance, 2));
       
   return lot_size;
}

double GetAdaptiveRiskCached(int cache_seconds = 300)
{
   datetime now = TimeCurrent();
   double current_drawdown = 0.0;

   // Return cached value if recent
   if(g_risk_cache.last_calc > 0 && (now - g_risk_cache.last_calc) < cache_seconds)
   {
      Log(LOG_DETAILED, "GetAdaptiveRiskCached", "Using cached risk: " + DoubleToString(g_risk_cache.risk, 2) + "%");
      return g_risk_cache.risk;
   }

   // DISABLED AS PER GUIDE: Never increase risk during drawdown
   if(!g_Enable_Adaptive_Risk)
   {
      g_risk_cache.risk = g_Risk_Percent_Effective;
      g_risk_cache.last_calc = now;
      return g_Risk_Percent_Effective;
   }

   int wins = 0, losses = 0;

   // Select history for last 5 days
   if(!HistorySelect(now - 86400 * 5, now))
   {
      Log(LOG_WARNING, "GetAdaptiveRiskCached", "HistorySelect failed - using base risk");
      return g_Risk_Percent_Effective;
   }

   int deal_count = HistoryDealsTotal();
   if(deal_count == 0)
   {
      Log(LOG_DEBUG, "GetAdaptiveRiskCached", "No history available");
      g_risk_cache.risk = g_Risk_Percent_Effective;
      g_risk_cache.last_calc = now;
      return g_Risk_Percent_Effective;
   }

   // Issue 2.8 FIX: Limit iteration to most recent 500 deals (more recent = more relevant)
   int deals_to_process = MathMin(deal_count, 500);
   int start_index = deal_count - deals_to_process;

   ulong close_keys[];
   ulong close_position_ids[];
   double close_nets[];
   datetime close_times[];

   for(int i = start_index; i < deal_count; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;

      long deal_type = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(deal_type != DEAL_TYPE_BUY && deal_type != DEAL_TYPE_SELL)
         continue;

      ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(deal_entry != DEAL_ENTRY_OUT && deal_entry != DEAL_ENTRY_OUT_BY && deal_entry != DEAL_ENTRY_INOUT)
         continue;

      ulong position_id = (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      ulong deal_order = (ulong)HistoryDealGetInteger(ticket, DEAL_ORDER);
      ulong close_key = (position_id > 0 ? position_id : (deal_order > 0 ? deal_order : ticket));

      int close_index = -1;
      for(int ci = 0; ci < ArraySize(close_keys); ci++)
      {
         if(close_keys[ci] == close_key)
         {
            close_index = ci;
            break;
         }
      }

      if(close_index < 0)
      {
         int new_size = ArraySize(close_keys) + 1;
         ArrayResize(close_keys, new_size);
         ArrayResize(close_position_ids, new_size);
         ArrayResize(close_nets, new_size);
         ArrayResize(close_times, new_size);
         close_index = new_size - 1;
         close_keys[close_index] = close_key;
         close_position_ids[close_index] = position_id;
         close_nets[close_index] = 0.0;
         close_times[close_index] = 0;
      }

      double net_profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                          HistoryDealGetDouble(ticket, DEAL_SWAP) +
                          HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      datetime deal_time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      close_nets[close_index] += net_profit;
      if(deal_time >= close_times[close_index])
         close_times[close_index] = deal_time;
   }

   int close_count = ArraySize(close_keys);
   for(int i = 0; i < close_count - 1; i++)
   {
      for(int j = i + 1; j < close_count; j++)
      {
         if(close_times[j] < close_times[i])
            continue;

         ulong swap_key = close_keys[i];
         close_keys[i] = close_keys[j];
         close_keys[j] = swap_key;

         ulong swap_position_id = close_position_ids[i];
         close_position_ids[i] = close_position_ids[j];
         close_position_ids[j] = swap_position_id;

         double swap_net = close_nets[i];
         close_nets[i] = close_nets[j];
         close_nets[j] = swap_net;

         datetime swap_time = close_times[i];
         close_times[i] = close_times[j];
         close_times[j] = swap_time;
      }
   }

   for(int ci = 0; ci < close_count; ci++)
   {
      ulong position_id = close_position_ids[ci];
      if(position_id > 0 && IsPositionIdentifierOpen(position_id))
         continue;

      if(close_nets[ci] > 0.01)
         wins++;
      else if(close_nets[ci] < -0.01)
         losses++;
   }

   int consecutive_wins = 0;
   for(int ci = 0; ci < close_count; ci++)
   {
      ulong position_id = close_position_ids[ci];
      if(position_id > 0 && IsPositionIdentifierOpen(position_id))
         continue;

      if(close_nets[ci] > 0.01)
      {
         consecutive_wins++;
      }
      else if(close_nets[ci] < -0.01)
      {
         break;
      }
      else
      {
         break;
      }
   }

   // REFACTORED AS PER GUIDE: Simplified adaptive risk logic
   double adaptive_risk = g_Risk_Percent_Effective;
   int total_trades = wins + losses;

   if(total_trades > 0)
   {
      // GUIDE RULE: Never increase risk during drawdown
      // Check current drawdown
      if(g_equity_all_time_high > 0)
      {
         current_drawdown = (g_equity_all_time_high - AccountInfoDouble(ACCOUNT_EQUITY)) / g_equity_all_time_high * 100.0;
      }

      // GUIDE RULE: Never increase risk when drawdown >= 3%
      if(current_drawdown >= 3.0)
      {
         adaptive_risk = g_Risk_Percent_Effective * 0.7;  // Reduce risk during drawdown
         Log(LOG_INFO, "GetAdaptiveRiskCached", "Drawdown >= 3% detected (" +
             DoubleToString(current_drawdown, 1) + "%), reducing risk to " +
             DoubleToString(adaptive_risk, 2) + "%");
      }
      else if(consecutive_wins >= 3)
      {
         // GUIDE RULE: Only increase risk on winning streak (3+ wins)
         adaptive_risk = g_Risk_Percent_Effective * 1.2;
         Log(LOG_INFO, "GetAdaptiveRiskCached", "Winning streak >= 3 detected (" +
             IntegerToString(consecutive_wins) + " wins), increasing risk to " +
             DoubleToString(adaptive_risk, 2) + "%");
      }
      // GUIDE RULE: Never increase risk when volatility is expanding rapidly
      else
      {
         // Check for rapid volatility expansion
         double current_atr = GetATRValue(Symbol(), Signal_TF);
         double avg_atr = GetATRValue(Symbol(), Signal_TF, 50); // Longer period ATR

         if(avg_atr > 0 && (current_atr / avg_atr) > 1.5)
         {
            adaptive_risk = g_Risk_Percent_Effective * 0.8; // Reduce risk during high volatility
            Log(LOG_INFO, "GetAdaptiveRiskCached", "High volatility detected (ATR ratio: " +
                DoubleToString(current_atr / avg_atr, 2) + "), reducing risk to " +
                DoubleToString(adaptive_risk, 2) + "%");
         }
      }
   }

   // Clamp to reasonable bounds (never exceed 1.5x or go below 0.5x)
   adaptive_risk = MathClamp(adaptive_risk, g_Risk_Percent_Effective * 0.5, g_Risk_Percent_Effective * 1.5);

   // Cache result
   g_risk_cache.risk = adaptive_risk;
   g_risk_cache.wins = wins;
   g_risk_cache.losses = losses;
   g_risk_cache.last_calc = now;

   Log(LOG_DEBUG, "GetAdaptiveRiskCached",
       "Processed " + IntegerToString(deals_to_process) + " history deals, counted " +
       IntegerToString(total_trades) + " finalized closed trades: " +
       "Wins=" + IntegerToString(wins) +
        ", Losses=" + IntegerToString(losses) +
       ", ConsecutiveWins=" + IntegerToString(consecutive_wins) +
       ", Current Drawdown=" + DoubleToString(current_drawdown, 1) + "%" +
       ", Risk=" + DoubleToString(adaptive_risk, 2) + "%");

   return adaptive_risk;
}

bool LaunchProfitTargetReentry(string symbol,
                               ENUM_POSITION_TYPE position_type,
                               double target_entry_price,
                               double stop_loss_distance,
                               double take_profit_distance,
                               bool force_market_order = false)
{
   if(!g_ProfitTarget_Reenter_Trade)
      return false;

   if(symbol == "" || stop_loss_distance <= 0.0 || take_profit_distance <= 0.0)
   {
      Log(LOG_WARNING, "LaunchProfitTargetReentry", "Invalid re-entry inputs");
      return false;
   }

   if(!IsTradeAllowed(symbol))
   {
      Log(LOG_WARNING, "LaunchProfitTargetReentry", symbol + " - Trading not allowed");
      return false;
   }

   if(!IsMarketOpen(symbol) || !IsSpreadAcceptable(symbol))
   {
      Log(LOG_INFO, "LaunchProfitTargetReentry", symbol + " - Market/spread condition blocks re-entry");
      return false;
   }

   if(!CanExecuteTradeToday())
      return false;

   if(CGateController::IsStructuralGateEnabled())
   {
      string range_reason = "";
      if(IsMarketRanging(symbol, range_reason))
      {
         Log(LOG_INFO, "LaunchProfitTargetReentry", symbol + " - Ranging market blocks re-entry: " + range_reason);
         return false;
      }
   }

    int symbol_positions = GetSymbolPositionCountLive(symbol);
    int symbol_pending_orders = 0;

   int our_positions = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         long pos_magic = PositionGetInteger(POSITION_MAGIC);
         if(pos_magic >= Magic_Base && pos_magic < Magic_Base + 10000)
            our_positions++;
      }
   }

   int our_pending_orders = 0;
   for(int oi = OrdersTotal() - 1; oi >= 0; oi--)
   {
      ulong oticket = OrderGetTicket(oi);
      if(oticket == 0 || !OrderSelect(oticket))
         continue;
      long omagic = OrderGetInteger(ORDER_MAGIC);
      if(omagic < Magic_Base || omagic >= Magic_Base + 10000)
         continue;
      ENUM_ORDER_TYPE otype = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
       if(otype == ORDER_TYPE_BUY_LIMIT || otype == ORDER_TYPE_SELL_LIMIT ||
          otype == ORDER_TYPE_BUY_STOP || otype == ORDER_TYPE_SELL_STOP ||
          otype == ORDER_TYPE_BUY_STOP_LIMIT || otype == ORDER_TYPE_SELL_STOP_LIMIT)
       {
          our_pending_orders++;
          if(OrderGetString(ORDER_SYMBOL) == symbol)
             symbol_pending_orders++;
       }
    }

    int symbol_exposure = symbol_positions + symbol_pending_orders;
    if(CGateController::IsExposureGateEnabled() && symbol_exposure >= MAX_TRADES_PER_SYMBOL)
    {
       Log(LOG_WARNING, "LaunchProfitTargetReentry", symbol +
           " - Symbol exposure limit reached (positions=" + IntegerToString(symbol_positions) +
           ", pending=" + IntegerToString(symbol_pending_orders) +
           ", limit=" + IntegerToString(MAX_TRADES_PER_SYMBOL) + ")");
       return false;
    }

   int concurrent_limit = MathMax(1, g_Max_Concurrent_Trades_Effective);
   int concurrent_slots = our_positions + our_pending_orders;
   if(!g_Disable_All_Gates && concurrent_slots >= concurrent_limit)
   {
      Log(LOG_WARNING, "LaunchProfitTargetReentry",
          "Max concurrent trades reached (" + IntegerToString(concurrent_slots) + "/" +
          IntegerToString(concurrent_limit) +
          ", open=" + IntegerToString(our_positions) +
          ", pending=" + IntegerToString(our_pending_orders) +
          ", input=" + IntegerToString(Max_Concurrent_Trades) +
          ", profile=" + g_Live_Risk_Profile_Name + ")");
      return false;
   }

   CSymbolInfo sym;
   if(!sym.Name(symbol) || !sym.RefreshRates())
   {
      Log(LOG_WARNING, "LaunchProfitTargetReentry", "Failed to refresh symbol data for " + symbol);
      return false;
   }

   double point = sym.Point();
   int digits = (int)sym.Digits();
   double current_bid = sym.Bid();
   double current_ask = sym.Ask();
   if(point <= 0.0 || digits <= 0 || current_bid <= 0.0 || current_ask <= 0.0 || current_bid >= current_ask)
   {
      Log(LOG_WARNING, "LaunchProfitTargetReentry", symbol + " - Invalid quote data");
      return false;
   }

   int direction = (position_type == POSITION_TYPE_BUY) ? 1 : -1;
   double entry_price = NormalizeDouble(target_entry_price, digits);
   if(entry_price <= 0.0)
      entry_price = NormalizeDouble((direction == 1 ? current_ask : current_bid), digits);

   double entry_sl = (direction == 1) ?
      NormalizeDouble(entry_price - stop_loss_distance, digits) :
      NormalizeDouble(entry_price + stop_loss_distance, digits);
   double entry_tp = (direction == 1) ?
      NormalizeDouble(entry_price + take_profit_distance, digits) :
      NormalizeDouble(entry_price - take_profit_distance, digits);

   int stop_level = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freeze_level = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double min_pending_distance = MathMax((double)stop_level, (double)freeze_level) * point;
   if(min_pending_distance < point)
      min_pending_distance = point * 2.0;

   bool use_market = force_market_order;
   bool is_limit = false;
   if(!use_market && direction == 1)
   {
      if(entry_price < (current_ask - min_pending_distance))
         is_limit = true;
      else if(entry_price > (current_ask + min_pending_distance))
         is_limit = false;
      else
         use_market = true;
   }
   else if(!use_market)
   {
      if(entry_price > (current_bid + min_pending_distance))
         is_limit = true;
      else if(entry_price < (current_bid - min_pending_distance))
         is_limit = false;
      else
         use_market = true;
   }

   string mode = "MARKET";
   double queue_entry = entry_price;
   double queue_sl = entry_sl;
   double queue_tp = entry_tp;
   if(use_market)
   {
      queue_entry = (direction == 1) ? current_ask : current_bid;
      queue_sl = (direction == 1) ?
         NormalizeDouble(queue_entry - stop_loss_distance, digits) :
         NormalizeDouble(queue_entry + stop_loss_distance, digits);
      queue_tp = (direction == 1) ?
         NormalizeDouble(queue_entry + take_profit_distance, digits) :
         NormalizeDouble(queue_entry - take_profit_distance, digits);
      mode = (direction == 1 ? "BUY MARKET" : "SELL MARKET");
   }
   else if(direction == 1)
   {
      mode = (is_limit ? "BUY LIMIT" : "BUY STOP");
   }
   else
   {
      mode = (is_limit ? "SELL LIMIT" : "SELL STOP");
   }

   STradeLevelContext trade_ctx;
   string trade_ctx_error = "";
   if(!BuildTradeLevelContext(symbol, -1, trade_ctx, trade_ctx_error))
   {
      Log(LOG_WARNING, "LaunchProfitTargetReentry",
          symbol + " - Re-entry context unavailable before queueing (" + mode + "): " + trade_ctx_error);
      return false;
   }

   int reentry_levels_reason = TRADE_LEVELS_OK;
   if(!NormalizeAndValidateTradeLevels(symbol, trade_ctx, queue_entry, queue_sl, queue_tp, reentry_levels_reason))
   {
      Log(LOG_WARNING, "LaunchProfitTargetReentry",
          symbol + " - Re-entry levels invalid before queueing (" + mode + "): " +
          TradeLevelsReasonLabel(reentry_levels_reason));
      return false;
   }

   STradingSignal reentry_signal;
   reentry_signal.valid = true;
   reentry_signal.direction = direction;
   reentry_signal.entry_price = queue_entry;
   reentry_signal.stop_loss = queue_sl;
   reentry_signal.take_profit = queue_tp;
   reentry_signal.signal_time = TimeCurrent();
   reentry_signal.origin = SIGNAL_ORIGIN_UNKNOWN;
   reentry_signal.atr_value = GetATRValue(symbol, Signal_TF);
   reentry_signal.risk_reward_ratio = CalculateTradeRiskRewardRatio(queue_entry, queue_sl, queue_tp);
   string execution_pref_tag = (use_market ? "MARKET" : "PENDING");
   reentry_signal.reason = "PreEntry=ProfitTargetReentry | ExecPref=" + execution_pref_tag;
   reentry_signal.reason += " | ReentryMode=" + mode;
   reentry_signal.reason += " | TargetEntry=" + DoubleToString(target_entry_price, digits);
   if(force_market_order)
      reentry_signal.reason += " | ForceMarket=ON";
   if(!use_market && g_ProfitTarget_Reentry_Expiry_Minutes > 0)
      reentry_signal.reason += " | PendingExpiryMin=" + IntegerToString(g_ProfitTarget_Reentry_Expiry_Minutes);

   int symbol_index = GetSymbolIndex(symbol);
   bool queued = ExecuteTrade(symbol, reentry_signal, symbol_index);
   if(queued)
   {
      Log(LOG_INFO, "LaunchProfitTargetReentry",
          symbol + " - Re-entry queued through standard execution pipeline (" + mode +
          ", entry=" + DoubleToString(queue_entry, digits) +
          ", sl=" + DoubleToString(queue_sl, digits) +
          ", tp=" + DoubleToString(queue_tp, digits) + ")");
      return true;
   }

   Log(LOG_WARNING, "LaunchProfitTargetReentry",
       symbol + " - Re-entry rejected before queueing by standard execution pipeline (" + mode + ")");
   return false;
}

// ===== FIX #7: HISTORICAL EXTREME EVENT DETECTION =====
// Check for rare low-probability events that may cause extreme losses
double CheckHistoricalExtremeEvents(string symbol, double entry_price, double stop_loss_price)
{
   // Scan last 100 1-minute candles for extreme moves
   const int CANDLE_LOOKBACK = 100;
   const double EXTREME_MOVE_THRESHOLD = 3.0;  // 3x average volatility = extreme
   
   double current_atr = iATR(symbol, PERIOD_M1, 14);
   if(current_atr <= 0.0 || !MathIsValidNumber(current_atr))
      return 0.0;  // Cannot detect extremes without valid ATR
   
   int extreme_candles = 0;
   int total_candles = 0;
   
   // Check last N minutes for extreme range candles
   for(int i = 0; i < CANDLE_LOOKBACK; i++)
   {
      double high = iHigh(symbol, PERIOD_M1, i);
      double low = iLow(symbol, PERIOD_M1, i);
      double candle_range = (high - low);
      
      if(MathIsValidNumber(high) && MathIsValidNumber(low) && high > low)
      {
         total_candles++;
         double range_ratio = candle_range / current_atr;
         
         // If this candle is 3x+ more volatile than recent ATR, it's extreme
         if(range_ratio > EXTREME_MOVE_THRESHOLD)
            extreme_candles++;
      }
   }
   
   // Calculate probability: if >= 2 extreme candles in last 100,
   // there's elevated risk of another extreme event
   if(total_candles > 10)
   {
      double extreme_frequency = (double)extreme_candles / (double)total_candles;
      
      // If >2% of recent candles are extreme, mark higher probability
      if(extreme_frequency > 0.02)
      {
         Log(LOG_DEBUG, "CheckHistoricalExtremeEvents",
             StringFormat("%s - Extreme activity detected: %d/%d candles (%.1f%% extreme)",
                         symbol, extreme_candles, total_candles, extreme_frequency * 100.0));
         return MathMin(extreme_frequency * 5.0, 0.75);  // Cap at 75% probability
      }
   }
   
   return 0.0;
}
// ===== END FIX #7 =====

void CheckProfitTargetAndDrawdown()
{
    // FIXED: Add throttle to prevent redundant close attempts
    static datetime last_check = 0;
    static int last_positions_count = 0;
    datetime current_time = TimeCurrent();
    int current_positions = PositionsTotal();
    
    // Skip if: no changes AND enough time hasn't passed
    // (Prevents checking 50x per second, but allows immediate re-check if new position added)
    if((current_time - last_check < 1) && (current_positions == last_positions_count))
        return;
    
    last_check = current_time;
    last_positions_count = current_positions;
    
    if (g_ProfitTargetToClose <= 0 && g_DrawdownLimitToClose <= 0 && g_PerTrade_Drawdown_Pct <= 0.0) return;

    double total_profit = 0.0;
    double total_loss = 0.0;
    int profit_target_hits = 0;
    double qualifying_profit_sum = 0.0;
    int positions_total = PositionsTotal();
    
    // Calculate total P&L from all EA positions in one pass
    for (int i = 0; i < positions_total; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket > 0 && PositionSelectByTicket(ticket))
        {
            long magic = PositionGetInteger(POSITION_MAGIC);
            if (magic >= Magic_Base && magic < Magic_Base + 10000)
            {
                double profit = PositionGetDouble(POSITION_PROFIT);
                if (profit > 0)
                {
                    total_profit += profit;
                    if(g_ProfitTargetToClose > 0.0 && profit >= g_ProfitTargetToClose)
                    {
                       profit_target_hits++;
                       qualifying_profit_sum += profit;
                    }
                }
                else if (profit < 0)
                    total_loss += MathAbs(profit);
            }
        }
    }

    // Check profit target first
    if (g_ProfitTargetToClose > 0 && profit_target_hits > 0)
    {
        Log(LOG_INFO, "CheckProfitTargetAndDrawdown",
            "PROFIT TARGET HIT on " + IntegerToString(profit_target_hits) + " position(s) " +
            "(threshold $" + DoubleToString(g_ProfitTargetToClose, 2) +
            ", qualifying P&L $" + DoubleToString(qualifying_profit_sum, 2) +
            ", total floating profit $" + DoubleToString(total_profit, 2) + ")");
        SendAlert(ALERT_INFO,
                  "PROFIT TARGET HIT: closing only trades with P&L >= $" +
                  DoubleToString(g_ProfitTargetToClose, 2));
        
        // Select a stable re-entry candidate first among target-hit trades (highest profit).
        int closed_count = 0;
        ulong reentry_candidate_ticket = 0;
        bool reentry_candidate_closed = false;
        string reentry_symbol = "";
        ENUM_POSITION_TYPE reentry_type = POSITION_TYPE_BUY;
        double reentry_price = 0.0;
        double reentry_sl_distance = 0.0;
        double reentry_tp_distance = 0.0;
        double best_profit = -1.0e100;
        bool fallback_closed_with_levels = false;
        string fallback_symbol = "";
        ENUM_POSITION_TYPE fallback_type = POSITION_TYPE_BUY;
        double fallback_sl_distance = 0.0;
        double fallback_tp_distance = 0.0;

        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
           ulong ticket = PositionGetTicket(i);
           if(ticket == 0 || !PositionSelectByTicket(ticket))
              continue;

           long magic = PositionGetInteger(POSITION_MAGIC);
           if(magic < Magic_Base || magic >= Magic_Base + 10000)
              continue;

           long pos_type_long = PositionGetInteger(POSITION_TYPE);
           if(pos_type_long != POSITION_TYPE_BUY && pos_type_long != POSITION_TYPE_SELL)
              continue;

           double profit = PositionGetDouble(POSITION_PROFIT);
           double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
           double pos_sl = PositionGetDouble(POSITION_SL);
           double pos_tp = PositionGetDouble(POSITION_TP);
           if(profit < g_ProfitTargetToClose || open_price <= 0.0 || pos_sl <= 0.0 || pos_tp <= 0.0)
              continue;

           if(profit > best_profit)
           {
              best_profit = profit;
              reentry_candidate_ticket = ticket;
              reentry_symbol = PositionGetString(POSITION_SYMBOL);
              reentry_type = (ENUM_POSITION_TYPE)pos_type_long;
              reentry_sl_distance = MathAbs(open_price - pos_sl);
              reentry_tp_distance = MathAbs(pos_tp - open_price);
           }
        }

        for (int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if (ticket > 0 && PositionSelectByTicket(ticket))
            {
                long magic = PositionGetInteger(POSITION_MAGIC);
                if (magic >= Magic_Base && magic < Magic_Base + 10000)
                {
                    long pos_type_long = PositionGetInteger(POSITION_TYPE);
                    if(pos_type_long != POSITION_TYPE_BUY && pos_type_long != POSITION_TYPE_SELL)
                       continue;
                    double profit = PositionGetDouble(POSITION_PROFIT);
                    if(profit < g_ProfitTargetToClose)
                       continue; // Close only positions that individually hit profit target.

                    string pos_symbol = PositionGetString(POSITION_SYMBOL);
                    double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
                    double pos_sl = PositionGetDouble(POSITION_SL);
                    double pos_tp = PositionGetDouble(POSITION_TP);
                    double sl_distance = (open_price > 0.0 && pos_sl > 0.0) ? MathAbs(open_price - pos_sl) : 0.0;
                    double tp_distance = (open_price > 0.0 && pos_tp > 0.0) ? MathAbs(pos_tp - open_price) : 0.0;
                    bool close_request_ok = trade.PositionClose(ticket);
                    int close_retcode = (int)trade.ResultRetcode();
                    bool close_ok = (close_request_ok && IsSuccessfulCloseRetcode(close_retcode));
                    if(close_ok)
                    {
                        closed_count++;
                        Log(LOG_INFO, "CheckProfitTargetAndDrawdown", "Closed position #" + (string)ticket + " P&L: $" + DoubleToString(profit, 2));

                        if(!fallback_closed_with_levels && sl_distance > 0.0 && tp_distance > 0.0)
                        {
                           fallback_symbol = pos_symbol;
                           fallback_type = (ENUM_POSITION_TYPE)pos_type_long;
                           fallback_sl_distance = sl_distance;
                           fallback_tp_distance = tp_distance;
                           fallback_closed_with_levels = true;
                        }

                        if(ticket == reentry_candidate_ticket)
                        {
                            reentry_price = trade.ResultPrice();
                            reentry_candidate_closed = true;
                        }
                     }
                     else
                     {
                        Log(LOG_WARNING, "CheckProfitTargetAndDrawdown",
                            "Failed to close position #" + (string)ticket + " (retcode=" +
                            IntegerToString(close_retcode) + ", " + trade.ResultRetcodeDescription() + ")");
                     }
                  }
              }
         }

         if(reentry_candidate_closed && reentry_price <= 0.0)
         {
            reentry_price = (reentry_type == POSITION_TYPE_BUY ?
               SymbolInfoDouble(reentry_symbol, SYMBOL_ASK) :
               SymbolInfoDouble(reentry_symbol, SYMBOL_BID));
         }

        if(!reentry_candidate_closed && fallback_closed_with_levels)
        {
           reentry_symbol = fallback_symbol;
            reentry_type = fallback_type;
            reentry_sl_distance = fallback_sl_distance;
            reentry_tp_distance = fallback_tp_distance;
            reentry_candidate_closed = true;
            reentry_price = (reentry_type == POSITION_TYPE_BUY ?
               SymbolInfoDouble(reentry_symbol, SYMBOL_ASK) :
               SymbolInfoDouble(reentry_symbol, SYMBOL_BID));
            Log(LOG_INFO, "CheckProfitTargetAndDrawdown",
                "Re-entry switched to fallback closed position candidate.");
         }

        if(closed_count <= 0)
        {
           Log(LOG_WARNING, "CheckProfitTargetAndDrawdown",
               "Profit target was detected but no qualifying position could be closed. Bot remains active.");
           return;
        }

        bool has_reentry_candidate = (reentry_candidate_closed &&
                                      reentry_symbol != "" &&
                                      reentry_sl_distance > 0.0 &&
                                      reentry_tp_distance > 0.0);

        bool reentered = false;
        if(closed_count > 0 && g_ProfitTarget_Reenter_Trade && !g_ProfitTarget_Halt_Bot && has_reentry_candidate)
        {
            reentered = LaunchProfitTargetReentry(reentry_symbol,
                                                  reentry_type,
                                                  reentry_price,
                                                  reentry_sl_distance,
                                                  reentry_tp_distance,
                                                  false);
            Log(reentered ? LOG_INFO : LOG_WARNING,
                "CheckProfitTargetAndDrawdown",
                reentry_symbol + (reentered ?
                   " - Profit-target re-entry queued after close" :
                   " - Profit-target re-entry requested but not queued"));
         }

         if(g_ProfitTarget_Halt_Bot)
         {
            HaltTrading();
            return;
         }
}

    // Per-trade drawdown limit (individual trade risk cut vs SL risk amount).
     if(g_PerTrade_Drawdown_Pct > 0.0)
     {
          int closed_per_trade = 0;
          for(int i = PositionsTotal() - 1; i >= 0; i--)
          {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket))
               continue;

            long magic = PositionGetInteger(POSITION_MAGIC);
            if(magic < Magic_Base || magic >= Magic_Base + 10000)
               continue;

             double profit = PositionGetDouble(POSITION_PROFIT);
             if(profit >= 0.0)
                continue;

             double floating_loss = MathAbs(profit);
             if(g_PerTrade_Drawdown_Min_Loss_Currency > 0.0 &&
                floating_loss < g_PerTrade_Drawdown_Min_Loss_Currency)
                continue;

             if(g_PerTrade_Drawdown_Min_Hold_Seconds > 0)
             {
                datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
                if(open_time > 0 && (current_time - open_time) < g_PerTrade_Drawdown_Min_Hold_Seconds)
                   continue;
             }

             string symbol = PositionGetString(POSITION_SYMBOL);
             double volume = PositionGetDouble(POSITION_VOLUME);
             double entry = PositionGetDouble(POSITION_PRICE_OPEN);
             double sl = PositionGetDouble(POSITION_SL);
             long type_long = PositionGetInteger(POSITION_TYPE);
             int direction = (type_long == POSITION_TYPE_BUY) ? 1 : (type_long == POSITION_TYPE_SELL ? -1 : 0);
             if(symbol == "" || volume <= 0.0 || entry <= 0.0 || sl <= 0.0 || direction == 0)
                continue;

             double sl_risk_amount = CalculateTradeRiskCurrency(symbol, direction, volume, entry, sl);
             if(sl_risk_amount <= 0.0)
                continue;

             double trade_drawdown_pct = SafeDiv(MathAbs(profit), sl_risk_amount, 0.0) * 100.0;
             if(trade_drawdown_pct < g_PerTrade_Drawdown_Pct)
                continue;

             bool close_request_ok = trade.PositionClose(ticket);
             int close_retcode = (int)trade.ResultRetcode();
             bool close_ok = (close_request_ok && IsSuccessfulCloseRetcode(close_retcode));
             if(close_ok)
             {
                closed_per_trade++;
                Log(LOG_WARNING, "CheckProfitTargetAndDrawdown",
                    "Closed position #" + (string)ticket + " - per-trade drawdown hit: -" +
                    DoubleToString(trade_drawdown_pct, 1) + "% (limit -" +
                    DoubleToString(g_PerTrade_Drawdown_Pct, 1) + "% of SL risk, P&L $" +
                    DoubleToString(profit, 2) + ", SL risk $" + DoubleToString(sl_risk_amount, 2) +
                    ", minHold=" + IntegerToString(g_PerTrade_Drawdown_Min_Hold_Seconds) +
                    "s, minLoss=$" + DoubleToString(g_PerTrade_Drawdown_Min_Loss_Currency, 2) + ")");
             }
            else
            {
               Log(LOG_WARNING, "CheckProfitTargetAndDrawdown",
                   "Failed to close drawdown position #" + (string)ticket + " (retcode=" +
                   IntegerToString(close_retcode) + ", " + trade.ResultRetcodeDescription() + ")");
            }
         }

         if(closed_per_trade > 0)
         {
            SendAlert(ALERT_RISK_CONTROL, "Per-trade drawdown limit triggered. Closed " +
                      IntegerToString(closed_per_trade) + " trade(s).");
            return;
         }
     }

     // Basket drawdown limit
     if (g_DrawdownLimitToClose > 0 && total_loss >= g_DrawdownLimitToClose)
      {
           Log(LOG_ERROR, "CheckProfitTargetAndDrawdown", "DRAWDOWN LIMIT REACHED: $" + DoubleToString(total_loss, 2) + " >= $" + DoubleToString(g_DrawdownLimitToClose, 2));
           int cancelled_pending = CancelAllManagedPendingOrders("basket drawdown");
           if(cancelled_pending > 0)
           {
              Log(LOG_WARNING, "CheckProfitTargetAndDrawdown",
                  "Cancelled " + IntegerToString(cancelled_pending) +
                  " managed pending order(s) before basket drawdown closeout");
           }
            
           // Close ALL positions managed by this EA
           int closed_count = 0;
          bool deferred_for_market_closed = false;
          for (int i = PositionsTotal() - 1; i >= 0; i--)
          {
              ulong ticket = PositionGetTicket(i);
              if (ticket > 0 && PositionSelectByTicket(ticket))
              {
                  long magic = PositionGetInteger(POSITION_MAGIC);
                   if (magic >= Magic_Base && magic < Magic_Base + 10000)
                   {
                      string position_symbol = PositionGetString(POSITION_SYMBOL);
                      if(!IsMarketOpen(position_symbol))
                      {
                         deferred_for_market_closed = true;
                         continue;
                      }

                       double profit = PositionGetDouble(POSITION_PROFIT);
                       bool close_request_ok = trade.PositionClose(ticket);
                       int close_retcode = (int)trade.ResultRetcode();
                       bool close_ok = (close_request_ok && IsSuccessfulCloseRetcode(close_retcode));
                       if(close_ok)
                      {
                          closed_count++;
                          Log(LOG_INFO, "CheckProfitTargetAndDrawdown", "Closed position #" + (string)ticket + " P&L: $" + DoubleToString(profit, 2));
                      }
                      else
                     {
                        Log(LOG_WARNING, "CheckProfitTargetAndDrawdown",
                            "Failed to close position #" + (string)ticket + " (retcode=" +
                            IntegerToString(close_retcode) + ", " + trade.ResultRetcodeDescription() + ")");
                     }
                  }
               }
           }
          if(closed_count <= 0 && deferred_for_market_closed)
          {
             string dd_msg = "DRAWDOWN LIMIT REACHED: $" + DoubleToString(total_loss, 2) +
                             " >= $" + DoubleToString(g_DrawdownLimitToClose, 2) +
                             ". Close-out deferred while market is closed.";
             ActivateDrawdownTradingPause("CheckProfitTargetAndDrawdown", dd_msg, true);
             return;
          }
          string dd_msg = "DRAWDOWN LIMIT REACHED: $" + DoubleToString(total_loss, 2) +
                          " >= $" + DoubleToString(g_DrawdownLimitToClose, 2) +
                          ". Closed " + IntegerToString(closed_count) + " positions.";
          ActivateDrawdownTradingPause("CheckProfitTargetAndDrawdown", dd_msg, true);
          return;
     }
}

//====================================================================
// NEW: Position Orphan Detection & Cleanup (Fix for GOLD Risk Cap Issue)
//====================================================================

bool IsPositionOrphaned(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   // Managed broker positions remain valid across EA restarts. Their age relative to the
   // current EA instance is not sufficient evidence that they are "orphaned", and force-
   // closing them on startup can liquidate legitimate live trades after a restart/recompile.
   return false;
}

void CleanupOrphanedPositions()
{
   if(g_Disable_All_Gates)
      return;  // Skip startup audit in test/dry-run mode
    
   Log(LOG_INFO, "CleanupOrphanedPositions", "=== SCANNING FOR PRE-EXISTING MANAGED POSITIONS ===");
    
   int preserved_count = 0;
   int positions_checked = 0;
    
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(IsStopped())
         break;
      
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      
      positions_checked++;
       
       long magic = PositionGetInteger(POSITION_MAGIC);
       
       // Only inspect positions with our magic number range
       if(magic < Magic_Base || magic >= Magic_Base + 10000)
          continue;

       datetime position_open_time = (datetime)PositionGetInteger(POSITION_TIME);
       bool preexisting_position = (g_startup_time > 0 &&
                                    position_open_time > 0 &&
                                    position_open_time < g_startup_time);
       if(preexisting_position)
       {
          string symbol = PositionGetString(POSITION_SYMBOL);
          double volume = PositionGetDouble(POSITION_VOLUME);
          double entry = PositionGetDouble(POSITION_PRICE_OPEN);
          ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

          preserved_count++;
          Log(LOG_INFO, "CleanupOrphanedPositions",
              StringFormat("Preserving pre-existing managed position #%llu | %s | %.2f lots | %s @ %.2f | opened %s before current startup %s",
                           ticket, symbol, volume, (type == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                           entry, TimeToString(position_open_time), TimeToString(g_startup_time)));
       }
    }
    
    Log(LOG_INFO, "CleanupOrphanedPositions", 
        StringFormat("Startup position scan complete: %d positions checked, %d pre-existing managed positions preserved",
                     positions_checked, preserved_count));
    
    if(preserved_count > 0)
    {
       Log(LOG_INFO, "CleanupOrphanedPositions",
           StringFormat("Preserved %d managed positions from earlier sessions; state will be synchronized instead of force-closed",
                        preserved_count));
    }
}

#endif // RISK_SESSION_MQH
