#ifndef DASHBOARD_MQH
#define DASHBOARD_MQH

#define PTB_DASHBOARD_NAME "PTB_DASHBOARD"
#define PTB_DASHBOARD_UPDATE_SECONDS 2

string FormatPercentSigned(double value)
{
   string sign = (value >= 0.0 ? "+" : "-");
   return sign + DoubleToString(MathAbs(value), 2) + "%";
}

string GetDashboardStatus(double daily_dd_pct, double equity_dd_pct)
{
   datetime now = TimeCurrent();
   
   if(IsStopped())
      return "STOPPED";

   if(g_Bot_Halt_Active)
      return "BOT HALTED";
    
   if(g_initialization_time > 0 && (now - g_initialization_time) < INITIALIZATION_COOLDOWN_SECONDS)
      return "INIT COOLDOWN";

   if(g_drawdown_pause_until > now)
   {
      int remaining = (int)((g_drawdown_pause_until - now) / 60);
      if(remaining < 0) remaining = 0;
      return "DD PAUSE (" + IntegerToString(remaining) + "m)";
   }
    
   if(IsLossCooldownActive())
   {
      int remaining = (int)((g_risk_cooldown_until - now) / 60);
      if(remaining < 0) remaining = 0;
      return "LOSS COOLDOWN (" + IntegerToString(remaining) + "m)";
   }
   
   if(g_Critical_Drawdown_Pct_Effective > 0 && equity_dd_pct >= g_Critical_Drawdown_Pct_Effective)
      return "CRITICAL DD";
   
   if(g_Max_Account_Drawdown_Pct_Effective > 0 && equity_dd_pct >= g_Max_Account_Drawdown_Pct_Effective)
      return "ACCOUNT DD";
   
   if(g_Max_Daily_Drawdown_Pct_Effective > 0 && daily_dd_pct > 0 && daily_dd_pct >= g_Max_Daily_Drawdown_Pct_Effective)
      return "DAILY DD";
   
   return "ACTIVE";
}

void CreateDashboardIfMissing()
{
   if(ObjectFind(0, PTB_DASHBOARD_NAME) >= 0)
      return;
   
   ObjectCreate(0, PTB_DASHBOARD_NAME, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, PTB_DASHBOARD_NAME, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, PTB_DASHBOARD_NAME, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, PTB_DASHBOARD_NAME, OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, PTB_DASHBOARD_NAME, OBJPROP_XSIZE, 420);
   ObjectSetInteger(0, PTB_DASHBOARD_NAME, OBJPROP_YSIZE, 190);
   ObjectSetInteger(0, PTB_DASHBOARD_NAME, OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(0, PTB_DASHBOARD_NAME, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, PTB_DASHBOARD_NAME, OBJPROP_BORDER_COLOR, clrGray);
   ObjectSetInteger(0, PTB_DASHBOARD_NAME, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, PTB_DASHBOARD_NAME, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, PTB_DASHBOARD_NAME, OBJPROP_HIDDEN, true);
   ObjectSetString(0, PTB_DASHBOARD_NAME, OBJPROP_FONT, "Consolas");
}

void DestroyDashboard()
{
   if(ObjectFind(0, PTB_DASHBOARD_NAME) >= 0)
      ObjectDelete(0, PTB_DASHBOARD_NAME);
}

void UpdateDashboard()
{
   static datetime last_update = 0;
   datetime now = TimeCurrent();
   
   if(!g_Enable_Dashboard)
   {
      DestroyDashboard();
      return;
   }
   
   if(now - last_update < PTB_DASHBOARD_UPDATE_SECONDS)
      return;
   last_update = now;
   
   CreateDashboardIfMissing();
   UpdateDailyCounters();
   
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   double daily_dd_pct = SafeDiv(g_equity_day_start - equity, g_equity_day_start, 0.0) * 100.0;
   double equity_ref = (g_equity_all_time_high > 0.0 ? g_equity_all_time_high : equity);
   double equity_dd_pct = SafeDiv(equity_ref - equity, equity_ref, 0.0) * 100.0;
   
   string status = GetDashboardStatus(daily_dd_pct, equity_dd_pct);
   
   double risk_base = GetRiskBaseValue();
   double open_risk = GetOpenRiskCurrency();
   double open_risk_pct = (risk_base > 0.0 ? (open_risk / risk_base * 100.0) : 0.0);
   double max_open_pct = ResolveMaxOpenRiskPct();
   double max_open_risk = (risk_base > 0.0 ? risk_base * max_open_pct / 100.0 : 0.0);
   
   string symbol = Symbol();
   double symbol_risk = GetOpenRiskCurrency(symbol);
   double symbol_risk_pct = (risk_base > 0.0 ? (symbol_risk / risk_base * 100.0) : 0.0);
   double max_symbol_pct = ResolveMaxSymbolRiskPct();
   double max_symbol_risk = (risk_base > 0.0 ? risk_base * max_symbol_pct / 100.0 : 0.0);
   
   long spread_points = 0;
   double spread_pips = 0.0;
   if(SymbolInfoInteger(symbol, SYMBOL_SPREAD, spread_points))
      spread_pips = PointsToPips(symbol, (double)spread_points);
   
    string text = "PTB Dashboard v5.6\n";
    text += "Status: " + status + " | Adaptive Risk: " + (g_Enable_Adaptive_Risk ? "ON" : "OFF") + "\n";
    if(g_Bot_Halt_Active && g_Bot_Halt_Reason != "")
       text += "Halt Reason: " + g_Bot_Halt_Reason + "\n";
    text += "Symbol: " + symbol + " (" + EnumToString(Signal_TF) + ") | Trades: " +
            IntegerToString(g_trades_today) + "/" + IntegerToString(g_Max_Trades_Per_Day_Effective) + "\n";
   text += "Equity: $" + DoubleToString(equity, 2) + " | Balance: $" + DoubleToString(balance, 2) + "\n";
   text += "Daily DD: " + FormatPercentSigned(daily_dd_pct) + " (Limit " + DoubleToString(g_Max_Daily_Drawdown_Pct_Effective, 2) + "%)\n";
   text += "Account DD: " + FormatPercentSigned(equity_dd_pct) + " (Limit " + DoubleToString(g_Max_Account_Drawdown_Pct_Effective, 2) + "%)\n";
   text += "Open Risk: $" + DoubleToString(open_risk, 2) + " (" + DoubleToString(open_risk_pct, 2) + "%) / $" +
           DoubleToString(max_open_risk, 2) + " (" + DoubleToString(max_open_pct, 2) + "%)\n";
   text += "Symbol Risk: $" + DoubleToString(symbol_risk, 2) + " (" + DoubleToString(symbol_risk_pct, 2) + "%) / $" +
           DoubleToString(max_symbol_risk, 2) + " (" + DoubleToString(max_symbol_pct, 2) + "%)\n";
   text += "Spread: " + DoubleToString(spread_pips, 1) + " pips | Inst Risk: " + (g_Enable_Institutional_Risk ? "ON" : "OFF");
   
   ObjectSetString(0, PTB_DASHBOARD_NAME, OBJPROP_TEXT, text);
   ChartRedraw(0);
}

#endif // DASHBOARD_MQH

