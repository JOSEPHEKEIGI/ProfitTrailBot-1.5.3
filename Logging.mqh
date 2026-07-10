#ifndef LOGGING_MQH
#define LOGGING_MQH

// ===== LOGGING SEVERITY HIERARCHY =====
// CRITICAL: Immediate action required (kill switches, fatal errors)
// ERROR:    Operation failed, execution blocked (trade failures, validation failures)
// WARN:     Unexpected condition, may reduce effectiveness (high spread, low bias score)
// INFO:     Normal operational events (trades, parameter changes, session switches)
// DEBUG:    Detailed trace info for troubleshooting (calculation steps, gate evaluations)
// DETAIL:   Ultra-verbose (hex dumps, array contents, full state snapshots)

// ===== MODULE PREFIXES FOR STRUCTURED LOGGING =====
// [RISK]      - Risk management, kill switches, drawdown tracking
// [SIGNAL]    - Signal generation, gating, score calculations
// [DIRECTOR]  - Director module, regime switching, learning state
// [KIMANIZ]   - KImaniz strategy, setup detection, trade setup
// [REVERSAL]  - Reversal detection, structure analysis
// [AI]        - AI model inference, confidence scores, predictions
// [TRADE]     - Trade execution, order management, position tracking
// [SESSION]   - Session gating, time filters, market hours
// [SPREAD]    - Spread gating, abnormal spread detection
// [EXECUTION] - Execution latency, slippage, order routing
// [CACHE]     - Cache management, symbol state, data updates

void Log(ENUM_LOG_LEVEL level, string function, string message, bool alert = false)
{
   if(level > Log_Level) return;
   
   // Issue 3.9: Validate function name
   if(StringLen(function) == 0)
      function = "Unknown";
   
   string prefix;
   switch(level)
   {
      case LOG_ERROR:   prefix = "[ERROR] "; break;
      case LOG_WARNING: prefix = "[WARN]  "; break;
      case LOG_INFO:    prefix = "[INFO]  "; break;
      case LOG_DEBUG:   prefix = "[DEBUG] "; break;
      case LOG_DETAILED:prefix = "[DETAIL] "; break;
      default:          prefix = ""; break;
   }
   
   string timestamp = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
   string log_message = StringFormat("%s %s %s: %s", timestamp, prefix, function, message);
   Print(log_message);
   
   if(alert && level <= LOG_WARNING)
   {
      SendAlert(ALERT_ERROR, log_message);
   }
}

void SendAlert(ENUM_ALERT_TYPE alert_type, string message)
{
   if(IsStopped()) return;
   
   string alert_prefix;
   switch(alert_type)
   {
      case ALERT_TRADE_OPEN:   alert_prefix = "TRADE OPEN: "; break;
      case ALERT_TRADE_CLOSE:  alert_prefix = "TRADE CLOSE: "; break;
      case ALERT_SIGNAL:       alert_prefix = "SIGNAL: "; break;
      case ALERT_INFO:         alert_prefix = "INFO: "; break;
      case ALERT_ERROR:        alert_prefix = "ERROR: "; break;
      case ALERT_DRAWDOWN:     alert_prefix = "DRAWDOWN: "; break;
      case ALERT_DAILY_LIMIT:  alert_prefix = "DAILY LIMIT: "; break;
      case ALERT_RISK_CONTROL: alert_prefix = "RISK CONTROL: "; break;
      case ALERT_EXECUTION:    alert_prefix = "EXECUTION: "; break;
      default:                 alert_prefix = "ALERT: "; break;
   }
   
   string full_message = alert_prefix + message;
   
   if(Enable_Email_Alerts)
   {
      SendMail("ProfitTrailBot Alert", full_message);
   }
   
   if(Enable_Telegram_Alerts && Telegram_Token != "" && Telegram_Chat_ID != "")
   {
      SendTelegramMessage(Telegram_Token, Telegram_Chat_ID, full_message);
   }
   
   Alert(full_message);
}

void LogSymbolError(string symbol, string operation, int error_code = 0)
{
   string error_msg;
   
   if(error_code == 0)
      error_code = GetLastError();
   
   // Translate error code to meaningful message
   switch(error_code)
   {
      case 4001:
         error_msg = "Terminal stopped (code 4001)";
         break;
      case 4014:
         error_msg = "Symbol not found in Market Watch (code 4014)";
         break;
      case 4107:
         error_msg = "Value required (code 4107)";
         break;
      case 0:
         error_msg = "No error";
         break;
      default:
         error_msg = "Error code: " + IntegerToString(error_code);
   }
   
   Log(LOG_ERROR, operation, "Failed for " + symbol + " - " + error_msg);
}

void LogTradeMessage(ENUM_LOG_LEVEL level, string function, string symbol, string message_type, string details = "")
{
   string formatted_msg = symbol + " - " + message_type;
   if(StringLen(details) > 0)
      formatted_msg += ": " + details;
   
   Log(level, function, formatted_msg);
}

void AuditLog(string stage, string symbol, string message)
{
   if(!g_Enable_Audit_Log)
      return;

   const int audit_flags = FILE_READ | FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE;
   const string audit_fallback_file = "ProfitTrailBot_Audit.csv";
   string audit_file = g_Audit_Log_File;
   ResetLastError();
   int handle = FileOpen(audit_file, audit_flags);
   int open_error = GetLastError();
   if(handle == INVALID_HANDLE && audit_file != audit_fallback_file)
   {
      ResetLastError();
      handle = FileOpen(audit_fallback_file, audit_flags);
      open_error = GetLastError();
      if(handle != INVALID_HANDLE)
      {
         static datetime last_audit_fallback = 0;
         datetime now = TimeCurrent();
         if(last_audit_fallback == 0 || (now - last_audit_fallback) >= 300)
         {
            Log(LOG_WARNING, "AuditLog",
                "Configured audit log file unavailable (" + audit_file +
                "); falling back to " + audit_fallback_file);
            last_audit_fallback = now;
         }
         audit_file = audit_fallback_file;
      }
   }

   if(handle == INVALID_HANDLE)
   {
      static datetime last_audit_fail = 0;
      datetime now = TimeCurrent();
      if(last_audit_fail == 0 || (now - last_audit_fail) >= 60)
      {
         Log(LOG_WARNING, "AuditLog", "Unable to open audit log file: " + audit_file +
             " (err=" + IntegerToString(open_error) + ")");
         last_audit_fail = now;
      }
      return;
   }

   bool write_header = (FileSize(handle) == 0);
   FileSeek(handle, 0, SEEK_END);
   if(write_header)
      FileWrite(handle, "Time", "Stage", "Symbol", "Message");
   string ts = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
   FileWrite(handle, ts, stage, symbol, message);
   FileClose(handle);
}

void AuditLogSignal(string stage, string symbol, const STradingSignal &signal, string message = "")
{
   if(!g_Enable_Audit_Log)
      return;

   string dir_txt = (signal.direction == 1 ? "BUY" : signal.direction == -1 ? "SELL" : "NA");
   string origin_txt = SignalOriginToString(signal.origin);
   string reason_txt = (StringLen(signal.reason) > 0 ? signal.reason : "OK");
   string msg = StringFormat("ORG=%s DIR=%s Entry=%.2f SL=%.2f TP=%.2f RR=%.2f Reason=%s%s",
                             origin_txt, dir_txt,
                             signal.entry_price, signal.stop_loss, signal.take_profit,
                             signal.risk_reward_ratio,
                             reason_txt,
                             (StringLen(message) > 0 ? " | " + message : ""));
   AuditLog(stage, symbol, msg);
}


bool SendTelegramMessage(string token, string chat_id, string message)
{
   // CRITICAL FIX: Enhanced validation and memory management
   int token_len = StringLen(token);
   int chat_id_len = StringLen(chat_id);
   if(token_len == 0 || chat_id_len == 0 || token_len > 1000 || chat_id_len > 100)
   {
      Log(LOG_WARNING, "SendTelegramMessage", "Invalid Telegram credentials");
      return false;
   }
   
   int msg_len = StringLen(message);
   if(msg_len > 4000)
      message = StringSubstr(message, 0, 4000) + "...";
   
   string url = "https://api.telegram.org/bot" + token + "/sendMessage";
   string params = "chat_id=" + chat_id + "&text=" + message + 
                  "&parse_mode=HTML&disable_web_page_preview=true";
   
   char data[], result[];
   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
   
   // CRITICAL FIX: Safe array operations with validation
   int params_len = StringLen(params);
   if(params_len <= 0 || params_len > 10000)
   {
      Log(LOG_ERROR, "SendTelegramMessage", "Invalid params length: " + IntegerToString(params_len));
      return false;
   }
   
   int data_len = params_len + 10; // Extra buffer
   if(!ArrayResize(data, data_len))
   {
      Log(LOG_ERROR, "SendTelegramMessage", "Failed to resize data array");
      return false;
   }
   
   // SAFE string conversion with error handling
   int converted = StringToCharArray(params, data, 0, params_len, CP_UTF8);
   if(converted <= 0 || converted > data_len)
   {
      Log(LOG_ERROR, "SendTelegramMessage", "String conversion failed or buffer overflow");
      ArrayFree(data);
      return false;
   }
   
   // SAFE WebRequest with timeout and validation
   int res = WebRequest("POST", url, headers, 10000, data, result, headers); // Increased timeout
   
   // CRITICAL: Always clean up memory
   ArrayFree(data);
   
   if(res == -1)
   {
      ArrayFree(result);
      if(!TerminalInfoInteger(TERMINAL_DLLS_ALLOWED))
      {
         Log(LOG_ERROR, "SendTelegramMessage", 
             "WebRequest not allowed. Add 'https://api.telegram.org' to allowed URLs");
      }
      else
      {
         Log(LOG_ERROR, "SendTelegramMessage", 
             "WebRequest failed with error: " + IntegerToString(GetLastError()));
      }
      return false;
   }
   
   // Clean up result array
   ArrayFree(result);
   
   if(res != 200)
   {
      Log(LOG_WARNING, "SendTelegramMessage", "Failed to send Telegram message. HTTP Code: " + IntegerToString(res));
      return false;
   }
   
   Log(LOG_DEBUG, "SendTelegramMessage", "Telegram message sent successfully");
   return true;
}

#endif // LOGGING_MQH
