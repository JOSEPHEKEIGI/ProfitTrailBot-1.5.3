#ifndef TRAINING_DATA_EXPORT_MQH
#define TRAINING_DATA_EXPORT_MQH

// Training data export is persisted in a SQLite database.
// This keeps appending reliably across sessions and avoids CSV duplication issues.

// Use COMMON folder optionally (set in main EA)
extern bool g_AI_Use_Common_Files;

#ifndef DATABASE_OPEN_READONLY
   #define DATABASE_OPEN_READONLY 1
#endif
#ifndef DATABASE_OPEN_READWRITE
   #define DATABASE_OPEN_READWRITE 2
#endif
#ifndef DATABASE_OPEN_CREATE
   #define DATABASE_OPEN_CREATE 4
#endif
#ifndef DATABASE_OPEN_MEMORY
   #define DATABASE_OPEN_MEMORY 8
#endif
#ifndef DATABASE_OPEN_COMMON
   #define DATABASE_OPEN_COMMON 16
#endif

int GetMarketStructureAtTime(string symbol, ENUM_TIMEFRAMES tf, datetime bar_time)
{
   int shift = iBarShift(symbol, tf, bar_time, true);
   if(shift < 0)
      return MARKET_RANGE;
   
   int bars_to_analyze = Trend_Lookback_Bars;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, tf, shift, bars_to_analyze, rates);
   if(copied < 20)
      return MARKET_RANGE;
   
   double sma_10 = 0, sma_20 = 0, sma_50 = 0;
   int array_size = ArraySize(rates);
   
   for(int i = 0; i < MathMin(50, array_size); i++)
   {
      if(i < 10) sma_10 += rates[i].close;
      if(i < 20) sma_20 += rates[i].close;
      sma_50 += rates[i].close;
   }
   
   sma_10 /= MathMin(10, array_size);
   sma_20 /= MathMin(20, array_size);
   sma_50 /= MathMin(50, array_size);
   
   double current_price = rates[0].close;
   if(current_price <= 0.0)
      return MARKET_RANGE;
   
   double bullish_strength = 0.0;
   double bearish_strength = 0.0;
   
   if(current_price > sma_10 && sma_10 > sma_20 && sma_20 > sma_50)
      bullish_strength += 3.0;
   else if(current_price > sma_10 && sma_10 > sma_20)
      bullish_strength += 2.0;
   else if(current_price > sma_10)
      bullish_strength += 1.0;
   
   if(current_price < sma_10 && sma_10 < sma_20 && sma_20 < sma_50)
      bearish_strength += 3.0;
   else if(current_price < sma_10 && sma_10 < sma_20)
      bearish_strength += 2.0;
   else if(current_price < sma_10)
      bearish_strength += 1.0;
   
   if(array_size > 4 && rates[4].close > 0.0)
   {
      double price_momentum = (rates[0].close - rates[4].close) / rates[4].close * 100;
      if(price_momentum > 0.1) bullish_strength += 1.0;
      else if(price_momentum < -0.1) bearish_strength += 1.0;
   }
   
   if(bullish_strength >= 2.0 && bullish_strength > bearish_strength + 0.5)
      return MARKET_BULLISH;
   if(bearish_strength >= 2.0 && bearish_strength > bullish_strength + 0.5)
      return MARKET_BEARISH;
   if(bullish_strength >= 1.5 && bullish_strength > bearish_strength + 1.5)
      return MARKET_BULLISH;
   if(bearish_strength >= 1.5 && bearish_strength > bullish_strength + 1.5)
      return MARKET_BEARISH;
   
   return MARKET_RANGE;
}

// --- SQLite training data sink ---
// Columns:
// ts, symbol, tf, close0, close1, close5, atr, rsi, ma_slope, vol0, vol1, vol_avg,
// macd, stoch, sentiment, spread, htf_bias, vol_regime, label_buy, label_sell, label_unified

string NormalizeDBPath(string filename)
{
   string path = filename;
   string lower = path;
   StringToLower(lower);
   // If extension is not .db, default to .db for SQLite.
   if(StringLen(lower) < 3 || StringSubstr(lower, StringLen(lower) - 3) != ".db")
      path = path + ".db";
   return path;
}

string EscapeSQLText(string value)
{
   string out = value;
   StringReplace(out, "'", "''");
   return out;
}

bool EnsureAIDatabase(int &db_handle, string filename)
{
   string db_path = NormalizeDBPath(filename);
   int flags = DATABASE_OPEN_READWRITE | DATABASE_OPEN_CREATE;
   if(g_AI_Use_Common_Files)
      flags |= DATABASE_OPEN_COMMON;

   db_handle = DatabaseOpen(db_path, flags);
   if(db_handle == INVALID_HANDLE)
   {
      Log(LOG_ERROR, "AITrainingDB", "Failed to open database: " + db_path +
         " (err=" + IntegerToString(GetLastError()) + ")");
      return false;
   }

   string create_sql =
      "CREATE TABLE IF NOT EXISTS ai_training_data ("
      "id INTEGER PRIMARY KEY AUTOINCREMENT,"
      "ts INTEGER NOT NULL,"
      "symbol TEXT NOT NULL,"
      "tf INTEGER NOT NULL,"
      "close0 REAL NOT NULL,"
      "close1 REAL NOT NULL,"
      "close5 REAL NOT NULL,"
      "atr REAL NOT NULL,"
      "rsi REAL NOT NULL,"
      "ma_slope REAL NOT NULL,"
      "vol0 REAL NOT NULL,"
      "vol1 REAL NOT NULL,"
      "vol_avg REAL NOT NULL,"
      "macd REAL NOT NULL,"
      "stoch REAL NOT NULL,"
      "sentiment REAL NOT NULL,"
      "spread REAL NOT NULL,"
      "htf_bias REAL NOT NULL,"
      "vol_regime REAL NOT NULL,"
      "label_buy INTEGER NOT NULL,"
      "label_sell INTEGER NOT NULL,"
      "label_unified INTEGER NOT NULL,"
      "created_at INTEGER NOT NULL,"
      "UNIQUE(ts, symbol, tf)"
      ");";

   if(!DatabaseExecute(db_handle, create_sql))
   {
      Log(LOG_ERROR, "AITrainingDB", "Failed to create training table");
      DatabaseClose(db_handle);
      db_handle = INVALID_HANDLE;
      return false;
   }

   // Indexes for typical queries and ordered reads.
   DatabaseExecute(db_handle, "CREATE INDEX IF NOT EXISTS idx_ai_train_ts ON ai_training_data(ts);");
   DatabaseExecute(db_handle, "CREATE INDEX IF NOT EXISTS idx_ai_train_symbol_tf_ts ON ai_training_data(symbol, tf, ts);");
   return true;
}

int GetAITrainingRowCount(int db_handle, string symbol = "", ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
{
   if(db_handle == INVALID_HANDLE)
      return -1;

   string sql = "SELECT COUNT(*) FROM ai_training_data";
   if(symbol != "")
   {
      sql += " WHERE symbol='" + EscapeSQLText(symbol) + "'";
      if(tf != PERIOD_CURRENT)
         sql += " AND tf=" + IntegerToString((int)tf);
   }

   int stmt = DatabasePrepare(db_handle, sql);
   if(stmt == INVALID_HANDLE)
      return -1;

   int count = -1;
   if(DatabaseRead(stmt))
   {
      int tmp_count = 0;
      if(DatabaseColumnInteger(stmt, 0, tmp_count))
         count = tmp_count;
   }

   DatabaseFinalize(stmt);
   return count;
}

bool InsertAITrainingRow(int db_handle,
   string symbol, ENUM_TIMEFRAMES tf,
   datetime ts,
   double close0, double close1, double close5,
   double atr, double rsi, double ma_slope,
   double vol0, double vol1, double vol_avg,
   double macd, double stoch, double sentiment,
   double spread, double htf_bias, double vol_regime,
   int label_buy, int label_sell, int label_unified)
{
   if(db_handle == INVALID_HANDLE)
      return false;

   string safe_symbol = EscapeSQLText(symbol);
   string sql = StringFormat(
      "INSERT OR IGNORE INTO ai_training_data ("
      "ts, symbol, tf, close0, close1, close5, atr, rsi, ma_slope, vol0, vol1, vol_avg, "
      "macd, stoch, sentiment, spread, htf_bias, vol_regime, label_buy, label_sell, label_unified, created_at"
      ") VALUES ("
      "%d, '%s', %d, %.10f, %.10f, %.10f, %.10f, %.10f, %.10f, %.10f, %.10f, %.10f, "
      "%.10f, %.10f, %.10f, %.10f, %.10f, %.10f, %d, %d, %d, %d"
      ");",
      (int)ts, safe_symbol, (int)tf,
      close0, close1, close5, atr, rsi, ma_slope, vol0, vol1, vol_avg,
      macd, stoch, sentiment, spread, htf_bias, vol_regime,
      label_buy, label_sell, label_unified, (int)TimeCurrent());

   if(!DatabaseExecute(db_handle, sql))
   {
      Log(LOG_ERROR, "AITrainingDB", "Insert failed for " + TimeToString(ts) +
          " (err=" + IntegerToString(GetLastError()) + ")");
      return false;
   }
   return true;
}

bool ExportAITrainingDataCSV(string symbol, ENUM_TIMEFRAMES tf, int bars, string filename)
{
   if(bars < 50)
   {
      Log(LOG_WARNING, "ExportAITrainingDataCSV", "Not enough bars requested");
      return false;
   }
   
   int bars_needed = bars + 10;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, tf, 0, bars_needed, rates);
   if(copied < bars + 6)
   {
      Log(LOG_WARNING, "ExportAITrainingDataCSV", "Insufficient rates copied");
      return false;
   }
   
   int rsi_handle = iRSI(symbol, tf, 14, PRICE_CLOSE);
   int ma_handle = iMA(symbol, tf, 20, 0, MODE_SMA, PRICE_CLOSE);
   int atr_handle = iATR(symbol, tf, 14);
   int atr_long_handle = iATR(symbol, tf, 100);
   int macd_handle = iMACD(symbol, tf, 12, 26, 9, PRICE_CLOSE);
   int stoch_handle = iStochastic(symbol, tf, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
   
   if(rsi_handle == INVALID_HANDLE || ma_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE ||
      atr_long_handle == INVALID_HANDLE || macd_handle == INVALID_HANDLE || stoch_handle == INVALID_HANDLE)
   {
      Log(LOG_ERROR, "ExportAITrainingDataCSV", "Failed to create indicator handles");
      if(rsi_handle != INVALID_HANDLE) IndicatorRelease(rsi_handle);
      if(ma_handle != INVALID_HANDLE) IndicatorRelease(ma_handle);
      if(atr_handle != INVALID_HANDLE) IndicatorRelease(atr_handle);
      if(atr_long_handle != INVALID_HANDLE) IndicatorRelease(atr_long_handle);
      if(macd_handle != INVALID_HANDLE) IndicatorRelease(macd_handle);
      if(stoch_handle != INVALID_HANDLE) IndicatorRelease(stoch_handle);
      return false;
   }
   
   double rsi_buf[], ma_buf[], atr_buf[], atr_long_buf[], macd_buf[], stoch_buf[];
   ArraySetAsSeries(rsi_buf, true);
   ArraySetAsSeries(ma_buf, true);
   ArraySetAsSeries(atr_buf, true);
   ArraySetAsSeries(atr_long_buf, true);
   ArraySetAsSeries(macd_buf, true);
   ArraySetAsSeries(stoch_buf, true);
   
   if(CopyBuffer(rsi_handle, 0, 0, bars_needed, rsi_buf) < bars + 6 ||
      CopyBuffer(ma_handle, 0, 0, bars_needed, ma_buf) < bars + 6 ||
      CopyBuffer(atr_handle, 0, 0, bars_needed, atr_buf) < bars + 6 ||
      CopyBuffer(atr_long_handle, 0, 0, bars_needed, atr_long_buf) < bars + 6 ||
      CopyBuffer(macd_handle, 0, 0, bars_needed, macd_buf) < bars + 6 ||
      CopyBuffer(stoch_handle, 0, 0, bars_needed, stoch_buf) < bars + 6)
   {
      Log(LOG_ERROR, "ExportAITrainingDataCSV", "Failed to copy indicator buffers");
      IndicatorRelease(rsi_handle);
      IndicatorRelease(ma_handle);
      IndicatorRelease(atr_handle);
      IndicatorRelease(atr_long_handle);
      IndicatorRelease(macd_handle);
      IndicatorRelease(stoch_handle);
      return false;
   }
   
   int db = INVALID_HANDLE;
   if(!EnsureAIDatabase(db, filename))
   {
      IndicatorRelease(rsi_handle);
      IndicatorRelease(ma_handle);
      IndicatorRelease(atr_handle);
      IndicatorRelease(atr_long_handle);
      IndicatorRelease(macd_handle);
      IndicatorRelease(stoch_handle);
      return false;
   }

   DatabaseExecute(db, "BEGIN TRANSACTION;");

   int max_i = bars;
   if(max_i > copied - 6)
      max_i = copied - 6;
   
   for(int i = max_i; i >= 6; i--)
   {
      double close0 = rates[i].close;
      double close1 = rates[i + 1].close;
      double close5 = rates[i + 5].close;
      
      double atr = atr_buf[i];
      double rsi = rsi_buf[i];
      double ma_slope = ma_buf[i] - ma_buf[i + 1];
      double vol0 = (double)rates[i].tick_volume;
      double vol1 = (double)rates[i + 1].tick_volume;
      double vol_avg = (vol0 + vol1) > 0 ? (vol0 + vol1) / 2.0 : 1.0;
      double macd = macd_buf[i];
      double stoch = stoch_buf[i];
      double sentiment = 0.5;
      double spread = GetAverageSpreadPrice(symbol); // Approximate typical spread (no time leakage)
      int htf_struct = GetMarketStructureAtTime(symbol, Confirm_TF, rates[i].time);
      double htf_bias_feature = (htf_struct == MARKET_BULLISH ? 1.0 : htf_struct == MARKET_BEARISH ? -1.0 : 0.0);
      double atr_long = atr_long_buf[i];
      double vol_regime = (atr_long > 0.0) ? MathClamp(atr / atr_long, 0.5, Max_Volatility_Adjustment_Factor) : 1.0;
      
      if(!ValidateAITrainingData(close0, close1, close5, atr, rsi, ma_slope, vol0, vol1, vol_avg, macd, stoch, sentiment))
         continue;
      
      // Label generation: TP/SL outcome within 1-bar horizon
      double tp = atr * ATR_TP_Multiplier;
      double sl = atr * ATR_SL_Multiplier;
      
      double next_high = rates[i - 1].high;
      double next_low = rates[i - 1].low;
      
      bool buy_tp_hit = (next_high >= close0 + tp);
      bool buy_sl_hit = (next_low <= close0 - sl);
      bool sell_tp_hit = (next_low <= close0 - tp);
      bool sell_sl_hit = (next_high >= close0 + sl);
      
      int label_buy = (buy_tp_hit && !buy_sl_hit) ? 1 : 0;
      int label_sell = (sell_tp_hit && !sell_sl_hit) ? 1 : 0;
      int label_unified = 0;
      if(label_buy == 1 && label_sell == 0) label_unified = 1;
      else if(label_sell == 1 && label_buy == 0) label_unified = 2;
      
      InsertAITrainingRow(db, symbol, tf, rates[i].time,
         close0, close1, close5,
         atr, rsi, ma_slope,
         vol0, vol1, vol_avg,
         macd, stoch, sentiment,
         spread, htf_bias_feature, vol_regime,
         label_buy, label_sell, label_unified);
   }

   DatabaseExecute(db, "COMMIT;");
   DatabaseClose(db);
   
   IndicatorRelease(rsi_handle);
   IndicatorRelease(ma_handle);
   IndicatorRelease(atr_handle);
   IndicatorRelease(atr_long_handle);
   IndicatorRelease(macd_handle);
   IndicatorRelease(stoch_handle);
   
   Log(LOG_INFO, "ExportAITrainingDataCSV", "Export complete -> database: " + NormalizeDBPath(filename));
   return true;
}

bool AppendAITrainingSampleCSV(string symbol, ENUM_TIMEFRAMES tf, string filename, int sample_shift, datetime &last_written_bar_time)
{
   if(sample_shift < 2)
      sample_shift = 2; // Needs next bar (shift-1) and close5 (shift+5)

   int bars_needed = sample_shift + 6;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, tf, 0, bars_needed, rates);
   if(copied < bars_needed)
      return false;

   datetime sample_time = rates[sample_shift].time;
   if(sample_time <= 0)
      return false;
   if(last_written_bar_time > 0 && sample_time <= last_written_bar_time)
      return false; // Already written (or time went backwards)

   int rsi_handle = GetPooledIndicatorHandle(symbol, tf, 14, "RSI");
   int ma_handle = GetPooledIndicatorHandle(symbol, tf, 20, "MA");
   int atr_handle = GetPooledIndicatorHandle(symbol, tf, 14, "ATR");
   int atr_long_handle = GetPooledIndicatorHandle(symbol, tf, 100, "ATR");
   int macd_handle = GetPooledIndicatorHandle(symbol, tf, 12, "MACD");
   int stoch_handle = GetPooledIndicatorHandle(symbol, tf, 14, "STOCH");

   if(rsi_handle == INVALID_HANDLE || ma_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE ||
      atr_long_handle == INVALID_HANDLE || macd_handle == INVALID_HANDLE || stoch_handle == INVALID_HANDLE)
   {
      return false;
   }

   double rsi_buf[1], atr_buf[1], atr_long_buf[1], macd_buf[1], stoch_buf[1], ma_buf[2];
   if(CopyBuffer(rsi_handle, 0, sample_shift, 1, rsi_buf) != 1 ||
      CopyBuffer(atr_handle, 0, sample_shift, 1, atr_buf) != 1 ||
      CopyBuffer(atr_long_handle, 0, sample_shift, 1, atr_long_buf) != 1 ||
      CopyBuffer(macd_handle, 0, sample_shift, 1, macd_buf) != 1 ||
      CopyBuffer(stoch_handle, 0, sample_shift, 1, stoch_buf) != 1 ||
      CopyBuffer(ma_handle, 0, sample_shift, 2, ma_buf) != 2)
   {
      return false;
   }

   double close0 = rates[sample_shift].close;
   double close1 = rates[sample_shift + 1].close;
   double close5 = rates[sample_shift + 5].close;

   double atr = atr_buf[0];
   double rsi = rsi_buf[0];
   double ma_slope = ma_buf[0] - ma_buf[1];
   double vol0 = (double)rates[sample_shift].tick_volume;
   double vol1 = (double)rates[sample_shift + 1].tick_volume;
   double vol_avg = (vol0 + vol1) > 0 ? (vol0 + vol1) / 2.0 : 1.0;
   double macd = macd_buf[0];
   double stoch = stoch_buf[0];
   double sentiment = 0.5;
   double spread = GetAverageSpreadPrice(symbol); // Approximate typical spread (no time leakage)
   int htf_struct = GetMarketStructureAtTime(symbol, Confirm_TF, sample_time);
   double htf_bias_feature = (htf_struct == MARKET_BULLISH ? 1.0 : htf_struct == MARKET_BEARISH ? -1.0 : 0.0);
   double atr_long = atr_long_buf[0];
   double vol_regime = (atr_long > 0.0) ? MathClamp(atr / atr_long, 0.5, Max_Volatility_Adjustment_Factor) : 1.0;

   if(!ValidateAITrainingData(close0, close1, close5, atr, rsi, ma_slope, vol0, vol1, vol_avg, macd, stoch, sentiment))
      return false;

   // Label generation: TP/SL outcome within 1-bar horizon
   double tp = atr * ATR_TP_Multiplier;
   double sl = atr * ATR_SL_Multiplier;

   double next_high = rates[sample_shift - 1].high;
   double next_low = rates[sample_shift - 1].low;

   bool buy_tp_hit = (next_high >= close0 + tp);
   bool buy_sl_hit = (next_low <= close0 - sl);
   bool sell_tp_hit = (next_low <= close0 - tp);
   bool sell_sl_hit = (next_high >= close0 + sl);

   int label_buy = (buy_tp_hit && !buy_sl_hit) ? 1 : 0;
   int label_sell = (sell_tp_hit && !sell_sl_hit) ? 1 : 0;
   int label_unified = 0;
   if(label_buy == 1 && label_sell == 0) label_unified = 1;
   else if(label_sell == 1 && label_buy == 0) label_unified = 2;

   int db = INVALID_HANDLE;
   if(!EnsureAIDatabase(db, filename))
      return false;

   bool ok = InsertAITrainingRow(db, symbol, tf, sample_time,
      close0, close1, close5,
      atr, rsi, ma_slope,
      vol0, vol1, vol_avg,
      macd, stoch, sentiment,
      spread, htf_bias_feature, vol_regime,
      label_buy, label_sell, label_unified);
   if(!ok)
   {
      DatabaseClose(db);
      return false;
   }

   last_written_bar_time = sample_time;
   g_ai_training_bars++;

   if((g_ai_training_bars <= 5) || (g_ai_training_bars % 50 == 0))
   {
      int total_rows = GetAITrainingRowCount(db, symbol, tf);
      if(total_rows >= 0)
      {
         Log(LOG_INFO, "AITrainingDB",
             StringFormat("%s %s - appended sample at %s (total rows: %d)",
                          symbol, EnumToString(tf), TimeToString(sample_time), total_rows));
      }
   }

   DatabaseClose(db);
   return true;
}

#endif // TRAINING_DATA_EXPORT_MQH
