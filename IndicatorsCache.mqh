#ifndef INDICATORS_CACHE_MQH
#define INDICATORS_CACHE_MQH

void ResetFallbackHandleSlot(int index)
{
   if(index < 0 || index >= 10)
      return;

   g_fallback_handles[index].handle = INVALID_HANDLE;
   g_fallback_handles[index].created_time = 0;
   g_fallback_handles[index].symbol = "";
   g_fallback_handles[index].tf = (ENUM_TIMEFRAMES)-1;
   g_fallback_handles[index].period = 0;
   g_fallback_handles[index].type = "";
}

void NormalizeFallbackHandleCount()
{
   if(g_fallback_count < 0)
      g_fallback_count = 0;
   else if(g_fallback_count > 10)
      g_fallback_count = 10;
}

void ReleaseAllFallbackHandles()
{
   NormalizeFallbackHandleCount();

   int released_handles[10];
   int released_count = 0;

   for(int i = 0; i < 10; i++)
   {
      int handle = g_fallback_handles[i].handle;
      bool already_released = false;
      for(int j = 0; j < released_count; j++)
      {
         if(released_handles[j] == handle)
         {
            already_released = true;
            break;
         }
      }

      if(handle != INVALID_HANDLE && !already_released)
      {
         if(!IndicatorRelease(handle))
         {
            int error = GetLastError();
            Log(LOG_WARNING, "ReleaseAllFallbackHandles", 
                "Failed to release handle " + IntegerToString(handle) + 
                ", error=" + IntegerToString(error));
         }
         else
         {
            released_handles[released_count++] = handle;
         }
      }

      ResetFallbackHandleSlot(i);
   }

   g_fallback_count = 0;
}

int GetTimeframeCacheIndex(ENUM_TIMEFRAMES tf)
{
   return GetStrategyTimeframeSlot(tf);
}

bool InvalidatePooledIndicatorHandle(string symbol, ENUM_TIMEFRAMES tf, int period, string type)
{
   bool invalidated = false;
   for(int i = 0; i < 20; i++)
   {
      if(g_indicator_pool[i].symbol == symbol &&
         g_indicator_pool[i].tf == tf &&
         g_indicator_pool[i].period == period &&
         g_indicator_pool[i].type == type)
      {
         if(g_indicator_pool[i].handle != INVALID_HANDLE)
            IndicatorRelease(g_indicator_pool[i].handle);
         g_indicator_pool[i].handle = INVALID_HANDLE;
         g_indicator_pool[i].symbol = "";
         g_indicator_pool[i].tf = (ENUM_TIMEFRAMES)-1;
         g_indicator_pool[i].period = 0;
         g_indicator_pool[i].type = "";
         g_indicator_pool[i].last_used = 0;
         g_indicator_pool[i].in_use = false;
         invalidated = true;
      }
   }
   
   // FIXED: Sync cache invalidation with pool cleanup
   // If an indicator was released, clear its cached values
   int symbol_index = GetSymbolIndex(symbol);
   if(symbol_index >= 0 && symbol_index < MAX_SYMBOLS && invalidated)
   {
      for(int tf_slot = 0; tf_slot < 4; tf_slot++)
      {
         ENUM_TIMEFRAMES cached_tf = GetStrategyTimeframeBySlot(tf_slot);
         if(cached_tf == tf)
         {
            g_indicator_cache[symbol_index][tf_slot].is_valid = false;
            g_momentum_cache[symbol_index][tf_slot].valid = false;
         }
      }
   }

   NormalizeFallbackHandleCount();
   for(int i = g_fallback_count - 1; i >= 0; i--)
   {
      if(g_fallback_handles[i].symbol == symbol &&
         g_fallback_handles[i].tf == tf &&
         g_fallback_handles[i].period == period &&
         g_fallback_handles[i].type == type)
      {
         if(g_fallback_handles[i].handle != INVALID_HANDLE)
            IndicatorRelease(g_fallback_handles[i].handle);
         for(int j = i; j < g_fallback_count - 1 && j < 9; j++)
            g_fallback_handles[j] = g_fallback_handles[j + 1];
         g_fallback_count--;
         ResetFallbackHandleSlot(g_fallback_count);
         invalidated = true;
      }
   }

   return invalidated;
}

double GetRSIValue(string symbol, ENUM_TIMEFRAMES tf, int period)
{
   // Map timeframe to cache index (Signal=0, Primary=1, Confirm=2, Trend=3)
   int tf_index = GetTimeframeCacheIndex(tf);
   
   int symbol_index = GetSymbolIndex(symbol);
   if(symbol_index < 0)
   {
      Log(LOG_WARNING, "GetRSIValue", "Symbol " + symbol + " not found in cache");
      return 50.0;
   }
   
   // FIXED: Validate cache index bounds before access to prevent out-of-bounds
   if(tf_index < 0 || tf_index >= 4)
   {
      Log(LOG_WARNING, "GetRSIValue", "Invalid timeframe cache index " + IntegerToString(tf_index) + " for " + EnumToString(tf));
      return 50.0;
   }

   datetime bar_time = iTime(symbol, tf, 0);
   if(bar_time <= 0)
      return 50.0;
   
   // FIX 2.1: Return cached RSI if still valid for this bar
   if(tf_index >= 0)
   {
      if(g_indicator_cache[symbol_index][tf_index].is_valid &&
         g_indicator_cache[symbol_index][tf_index].last_bar_time == bar_time)
      {
         return g_indicator_cache[symbol_index][tf_index].rsi_value;
      }
   }
   
   int bars_available = Bars(symbol, tf);
   long series_sync = 0;
   SeriesInfoInteger(symbol, tf, SERIES_SYNCHRONIZED, series_sync);
   int warm_bars_copied = -1;

   // Prime history/series sync before creating/reading indicator buffers.
   if(series_sync == 0 || (bars_available > 0 && bars_available <= period + 2))
   {
      MqlRates warm_rates[];
      ArraySetAsSeries(warm_rates, true);
      warm_bars_copied = CopyRates(symbol, tf, 0, MathMax(period + 50, 120), warm_rates);
      MqlTick sync_tick0;
      SymbolInfoTick(symbol, sync_tick0);
      bars_available = Bars(symbol, tf);
      SeriesInfoInteger(symbol, tf, SERIES_SYNCHRONIZED, series_sync);
   }

   // Use pooled RSI handles per symbol/timeframe to avoid cross-symbol contamination
   int rsi_handle = GetPooledIndicatorHandle(symbol, tf, period, "RSI");
   if(rsi_handle == INVALID_HANDLE)
   {
      if(tf_index >= 0 &&
         g_indicator_cache[symbol_index][tf_index].is_valid &&
         g_indicator_cache[symbol_index][tf_index].last_bar_time > 0)
      {
         int tf_seconds = PeriodSeconds(tf);
         if(tf_seconds <= 0)
            tf_seconds = 60;
         if((bar_time - g_indicator_cache[symbol_index][tf_index].last_bar_time) <= (datetime)(tf_seconds * 2))
            return g_indicator_cache[symbol_index][tf_index].rsi_value;
      }
      Log(LOG_WARNING, "GetRSIValue", "Failed to create RSI handle for " + symbol);
      return 50.0;  // Neutral value if unavailable
   }

   double values[1];
   int copy_result = -1;
   int copy_error = 0;
   int bars_calculated = BarsCalculated(rsi_handle);
   bool rsi_valid = false;

   ResetLastError();
   copy_result = CopyBuffer(rsi_handle, 0, 0, 1, values);
   copy_error = GetLastError();
   if(copy_result != 1 || !MathIsValidNumber(values[0]) || values[0] < 0.0 || values[0] > 100.0)
   {
      ResetLastError();
      copy_result = CopyBuffer(rsi_handle, 0, 1, 1, values);
      copy_error = GetLastError();
   }
   rsi_valid = (copy_result == 1 && MathIsValidNumber(values[0]) && values[0] >= 0.0 && values[0] <= 100.0);

   if(!rsi_valid)
   {
      if(warm_bars_copied < 0)
      {
         MqlRates warm_rates[];
         ArraySetAsSeries(warm_rates, true);
         warm_bars_copied = CopyRates(symbol, tf, 0, MathMax(period + 50, 120), warm_rates);
         MqlTick sync_tick1;
         SymbolInfoTick(symbol, sync_tick1);
         bars_available = Bars(symbol, tf);
         SeriesInfoInteger(symbol, tf, SERIES_SYNCHRONIZED, series_sync);
      }
      bars_calculated = BarsCalculated(rsi_handle);
      ResetLastError();
      copy_result = CopyBuffer(rsi_handle, 0, 0, 1, values);
      copy_error = GetLastError();
      if(copy_result != 1 || !MathIsValidNumber(values[0]) || values[0] < 0.0 || values[0] > 100.0)
      {
         ResetLastError();
         copy_result = CopyBuffer(rsi_handle, 0, 1, 1, values);
         copy_error = GetLastError();
      }
      rsi_valid = (copy_result == 1 && MathIsValidNumber(values[0]) && values[0] >= 0.0 && values[0] <= 100.0);
   }

   if(!rsi_valid)
   {
      InvalidatePooledIndicatorHandle(symbol, tf, period, "RSI");
      rsi_handle = GetPooledIndicatorHandle(symbol, tf, period, "RSI");
      if(rsi_handle != INVALID_HANDLE)
      {
         bars_calculated = BarsCalculated(rsi_handle);
         ResetLastError();
         copy_result = CopyBuffer(rsi_handle, 0, 0, 1, values);
         copy_error = GetLastError();
         if(copy_result != 1 || !MathIsValidNumber(values[0]) || values[0] < 0.0 || values[0] > 100.0)
         {
            ResetLastError();
            copy_result = CopyBuffer(rsi_handle, 0, 1, 1, values);
            copy_error = GetLastError();
         }
         rsi_valid = (copy_result == 1 && MathIsValidNumber(values[0]) && values[0] >= 0.0 && values[0] <= 100.0);

         if(!rsi_valid)
         {
            if(warm_bars_copied < 0)
            {
               MqlRates warm_rates[];
               ArraySetAsSeries(warm_rates, true);
               warm_bars_copied = CopyRates(symbol, tf, 0, MathMax(period + 50, 120), warm_rates);
               MqlTick sync_tick2;
               SymbolInfoTick(symbol, sync_tick2);
               bars_available = Bars(symbol, tf);
               SeriesInfoInteger(symbol, tf, SERIES_SYNCHRONIZED, series_sync);
            }
            bars_calculated = BarsCalculated(rsi_handle);
            ResetLastError();
            copy_result = CopyBuffer(rsi_handle, 0, 0, 1, values);
            copy_error = GetLastError();
            if(copy_result != 1 || !MathIsValidNumber(values[0]) || values[0] < 0.0 || values[0] > 100.0)
            {
               ResetLastError();
               copy_result = CopyBuffer(rsi_handle, 0, 1, 1, values);
               copy_error = GetLastError();
            }
            rsi_valid = (copy_result == 1 && MathIsValidNumber(values[0]) && values[0] >= 0.0 && values[0] <= 100.0);
         }
      }
   }

   if(rsi_valid)
   {
      if(tf_index >= 0)
      {
         g_indicator_cache[symbol_index][tf_index].rsi_value = values[0];
         g_indicator_cache[symbol_index][tf_index].last_bar_time = bar_time;
         g_indicator_cache[symbol_index][tf_index].is_valid = true;
      }
      return values[0];
   }

   static datetime last_rsi_copy_fail_log[MAX_SYMBOLS];
   if(last_rsi_copy_fail_log[symbol_index] == 0 || (TimeCurrent() - last_rsi_copy_fail_log[symbol_index]) >= 60)
   {
      Log(LOG_WARNING, "GetRSIValue",
          "Failed to copy RSI buffer for " + symbol +
          " (tf=" + EnumToString(tf) +
          ", period=" + IntegerToString(period) +
          ", barsAvailable=" + IntegerToString(bars_available) +
          ", seriesSync=" + IntegerToString((int)series_sync) +
          ", barsCalculated=" + IntegerToString(bars_calculated) +
          ", copyResult=" + IntegerToString(copy_result) +
          ", err=" + IntegerToString(copy_error) +
          ", warmBars=" + IntegerToString(warm_bars_copied) + ")");
      last_rsi_copy_fail_log[symbol_index] = TimeCurrent();
   }

   // Transient indicator sync failures can happen; prefer a recent valid RSI over hard-neutral fallback.
   if(tf_index >= 0 &&
      g_indicator_cache[symbol_index][tf_index].is_valid &&
      g_indicator_cache[symbol_index][tf_index].last_bar_time > 0)
   {
      int tf_seconds = PeriodSeconds(tf);
      if(tf_seconds <= 0)
         tf_seconds = 60;
      if((bar_time - g_indicator_cache[symbol_index][tf_index].last_bar_time) <= (datetime)(tf_seconds * 2))
      {
         return g_indicator_cache[symbol_index][tf_index].rsi_value;
      }
   }

   return 50.0;  // Neutral fallback
}

double NormalizeMACDValue(string symbol, ENUM_TIMEFRAMES tf, int symbol_index, double macd_value);

bool GetMomentumValues(string symbol, ENUM_TIMEFRAMES tf, int symbol_index, double &macd_value, double &stoch_value)
{
   int tf_index = GetTimeframeCacheIndex(tf);
   datetime bar_time = iTime(symbol, tf, 0);
   macd_value = 0.0;
   stoch_value = 50.0;

   // fast path: cached and fresh
   if(symbol_index >= 0 && tf_index >= 0)
   {
      if(g_momentum_cache[symbol_index][tf_index].valid &&
         g_momentum_cache[symbol_index][tf_index].bar_time == bar_time)
      {
         macd_value = g_momentum_cache[symbol_index][tf_index].macd;
         stoch_value = g_momentum_cache[symbol_index][tf_index].stoch;
         return true;
      }
   }

   // Recompute
   int macd_handle = GetPooledIndicatorHandle(symbol, tf, 12, "MACD");
   if(macd_handle != INVALID_HANDLE)
   {
      double macd_buffer[1];
      if(CopyBuffer(macd_handle, 0, 0, 1, macd_buffer) == 1)
         macd_value = NormalizeMACDValue(symbol, tf, symbol_index, macd_buffer[0]);
   }

   int stoch_handle = GetPooledIndicatorHandle(symbol, tf, 14, "STOCH");
   if(stoch_handle != INVALID_HANDLE)
   {
      double stoch_buffer[1];
      if(CopyBuffer(stoch_handle, 0, 0, 1, stoch_buffer) == 1)
      {
         if(MathIsValidNumber(stoch_buffer[0]))
            stoch_value = MathMax(0.0, MathMin(100.0, stoch_buffer[0]));
      }
   }

   if(symbol_index >= 0 && tf_index >= 0)
   {
      g_momentum_cache[symbol_index][tf_index].macd = macd_value;
      g_momentum_cache[symbol_index][tf_index].stoch = stoch_value;
      g_momentum_cache[symbol_index][tf_index].bar_time = bar_time;
      g_momentum_cache[symbol_index][tf_index].valid = true;
   }

   return true;
}

bool GetCachedRates(string symbol, ENUM_TIMEFRAMES tf, MqlRates &rates[], int required_bars)
{
     if(required_bars <= 0)
        return false;

    int symbol_index = GetSymbolIndex(symbol);
    if(symbol_index < 0 || symbol_index >= g_symbols_count)
       return false;

    datetime now = TimeCurrent();

    // Ensure all rates arrays use timeseries indexing (0 = most recent bar)
    ArraySetAsSeries(rates, true);
    ArraySetAsSeries(g_symbols[symbol_index].cache.last_rates, true);

    bool quote_refreshed = RefreshSymbolCache(symbol_index);
    long latest_tick_msc = g_symbols[symbol_index].cache.last_tick_msc;
    if(!quote_refreshed || latest_tick_msc <= 0)
    {
       MqlTick live_tick;
       if(SymbolInfoTick(symbol, live_tick) && (long)live_tick.time_msc > latest_tick_msc)
          latest_tick_msc = (long)live_tick.time_msc;
    }
    bool quote_fresh_known = (quote_refreshed || latest_tick_msc > 0);

    datetime current_bar_time = iTime(symbol, tf, 0);
    bool cache_bar_matches = false;
    bool cache_tick_matches = true;
    if(current_bar_time > 0)
    {
       datetime cached_bar_time = g_symbols[symbol_index].cache.last_rates_bar_time;
       if(ArraySize(g_symbols[symbol_index].cache.last_rates) > 0 &&
          g_symbols[symbol_index].cache.last_rates[0].time > 0)
       {
          cached_bar_time = g_symbols[symbol_index].cache.last_rates[0].time;
       }
       cache_bar_matches = (cached_bar_time == current_bar_time);
    }
    if(latest_tick_msc > 0 && g_symbols[symbol_index].cache.last_rates_tick_msc > 0)
    {
       // If a newer tick has arrived since this rates snapshot, refresh to avoid stale bar data.
       cache_tick_matches = (latest_tick_msc <= g_symbols[symbol_index].cache.last_rates_tick_msc);
    }

    bool cache_age_ok = (g_symbols[symbol_index].cache.last_rates_update > 0 &&
                         now >= g_symbols[symbol_index].cache.last_rates_update &&
                         (now - g_symbols[symbol_index].cache.last_rates_update) < CACHE_TIMEOUT_SECONDS);
    
    // FIXED: Cache tick check - use < not <= to force refresh on NEW ticks
    // Only use cached rates if very recent (age ok) AND bars match AND NO newer ticks
    if(cache_tick_matches && latest_tick_msc > 0 && g_symbols[symbol_index].cache.last_rates_tick_msc > 0)
    {
       cache_tick_matches = (latest_tick_msc < g_symbols[symbol_index].cache.last_rates_tick_msc);
    }
    
    // Check if cached data is still valid.
    // We require a valid current bar timestamp; if iTime is unavailable, force a fresh fetch.
    if(quote_fresh_known &&
       current_bar_time > 0 &&
       g_symbols[symbol_index].cache.last_rates_tf == tf &&
       cache_age_ok &&
       cache_bar_matches &&
       cache_tick_matches &&
       ArraySize(g_symbols[symbol_index].cache.last_rates) >= required_bars)
    {
       ArrayResize(rates, required_bars);
       ArrayCopy(rates, g_symbols[symbol_index].cache.last_rates, 0, 0, required_bars);
       g_cache_metadata[symbol_index].last_accessed = now;
       if(g_cache_metadata[symbol_index].access_count < 2147483647)
          g_cache_metadata[symbol_index].access_count++;
       return true;
    }
   
    // Need to fetch new data.
    int copied = CopyRates(symbol, tf, 0, required_bars, g_symbols[symbol_index].cache.last_rates);
    if(copied < required_bars)
    {
       Log(LOG_WARNING, "GetCachedRates", "Failed to copy rates for " + symbol + ": got " + IntegerToString(copied) + "/" + IntegerToString(required_bars));
       // Mark the rates snapshot invalid so stale data cannot be reused.
       g_symbols[symbol_index].cache.last_rates_update = 0;
       g_symbols[symbol_index].cache.last_rates_bar_time = 0;
       g_symbols[symbol_index].cache.last_rates_tf = PERIOD_CURRENT;
       g_symbols[symbol_index].cache.last_rates_tick_msc = 0;
       return false;
    }
    
    g_symbols[symbol_index].cache.last_rates_tf = tf;
    g_symbols[symbol_index].cache.last_rates_update = now;
    g_symbols[symbol_index].cache.last_rates_tick_msc =
       (latest_tick_msc > 0 ? latest_tick_msc : (long)now * 1000);
    g_symbols[symbol_index].cache.last_rates_bar_time =
       (ArraySize(g_symbols[symbol_index].cache.last_rates) > 0 && g_symbols[symbol_index].cache.last_rates[0].time > 0
        ? g_symbols[symbol_index].cache.last_rates[0].time
        : current_bar_time);
    ArrayResize(rates, required_bars);
    ArrayCopy(rates, g_symbols[symbol_index].cache.last_rates, 0, 0, required_bars);
    g_cache_metadata[symbol_index].last_accessed = now;
    if(g_cache_metadata[symbol_index].access_count < 2147483647)
       g_cache_metadata[symbol_index].access_count++;
    
     return true;
}

// ADDED: Force explicit cache refresh for on-demand refresh scenarios
// This ensures cache is fresh without waiting for timeout or new bar detection
void ForceRefreshSignalCache(int symbol_index)
{
   if(symbol_index < 0 || symbol_index >= g_symbols_count || symbol_index >= MAX_SYMBOLS)
      return;

   datetime now = TimeCurrent();
   
   // Force refresh rates cache by zeroing the last_update time
   g_symbols[symbol_index].cache.last_rates_update = 0;
   g_symbols[symbol_index].cache.last_rates_bar_time = 0;
   g_symbols[symbol_index].cache.last_rates_tick_msc = 0;
   
   // Force refresh all indicator caches for this symbol  
   for(int tf_slot = 0; tf_slot < 4; tf_slot++)
   {
      g_indicator_cache[symbol_index][tf_slot].is_valid = false;
      g_indicator_cache[symbol_index][tf_slot].last_bar_time = 0;
      g_momentum_cache[symbol_index][tf_slot].valid = false;
      g_momentum_cache[symbol_index][tf_slot].bar_time = 0;
   }
   
   // Refresh symbol quote cache
   RefreshSymbolCache(symbol_index);
   
   Log(LOG_DEBUG, "ForceRefreshSignalCache", "Forced cache refresh for " + g_symbols[symbol_index].name);
}

// ADDED: Force refresh for all symbols (bulk refresh on demand)
void ForceRefreshAllSignalCaches()
{
   for(int i = 0; i < g_symbols_count && i < MAX_SYMBOLS; i++)
   {
      ForceRefreshSignalCache(i);
   }
}

long GetLatestSymbolTickMsc(string symbol, int symbol_index, bool refresh_symbol_cache = true)
{
   if(symbol_index < 0 || symbol_index >= g_symbols_count)
      return 0;

   if(refresh_symbol_cache)
      RefreshSymbolCache(symbol_index);

   long latest_tick_msc = g_symbols[symbol_index].cache.last_tick_msc;
   if(latest_tick_msc <= 0 && g_symbols[symbol_index].cache.last_tick_time > 0)
      latest_tick_msc = (long)g_symbols[symbol_index].cache.last_tick_time * 1000;

   MqlTick live_tick;
   if(SymbolInfoTick(symbol, live_tick) && (long)live_tick.time_msc > latest_tick_msc)
      latest_tick_msc = (long)live_tick.time_msc;

   return latest_tick_msc;
}

double GetATRValue(string symbol, ENUM_TIMEFRAMES tf, int atr_period = 0)
{
   if(atr_period <= 0) atr_period = ATR_Period;

   int symbol_index = GetSymbolIndex(symbol);
   if(symbol_index == -1)
   {
      // Dynamic fallback: handle symbols outside the managed universe (e.g., legacy/open positions).
      long select_status = 0;
      bool has_select_info = SymbolInfoInteger(symbol, SYMBOL_SELECT, select_status);
      if((!has_select_info || select_status == 0) && !SymbolSelect(symbol, true))
      {
         Log(LOG_ERROR, "GetATRValue", "Invalid symbol: " + symbol);
         return 0.0;
      }

      int dyn_handle = GetPooledIndicatorHandle(symbol, tf, atr_period, "ATR");
      if(dyn_handle == INVALID_HANDLE)
      {
         Log(LOG_ERROR, "GetATRValue", "Invalid ATR handle for " + symbol);
         return 0.0;
      }

      double dyn_values[1] = {0.0};
      int dyn_copy = CopyBuffer(dyn_handle, 0, 1, 1, dyn_values);
      if(dyn_copy != 1 || !MathIsValidNumber(dyn_values[0]) || dyn_values[0] <= 0)
         dyn_copy = CopyBuffer(dyn_handle, 0, 0, 1, dyn_values);

      if(dyn_copy == 1 && MathIsValidNumber(dyn_values[0]) && dyn_values[0] > 0)
         return dyn_values[0];

      Log(LOG_WARNING, "GetATRValue", "Failed to copy ATR for " + symbol + " (dynamic fallback)");
      return 0.0;
   }

   datetime bar_time = iTime(symbol, tf, 0);

   // Check ATR cache
   for(int i = 0; i < MAX_ATR_CACHE; i++)
   {
      if(g_atr_cache[symbol_index][i].bar_time == bar_time &&
         g_atr_cache[symbol_index][i].tf == tf &&
         g_atr_cache[symbol_index][i].period == atr_period &&
         g_atr_cache[symbol_index][i].value > 0.0 &&
         MathIsValidNumber(g_atr_cache[symbol_index][i].value))
      {
         g_atr_cache[symbol_index][i].last_used = TimeCurrent();
         return g_atr_cache[symbol_index][i].value;
      }
   }

   int handle = INVALID_HANDLE;
   bool is_temporary = (tf != Signal_TF || atr_period != ATR_Period);
   
   if(is_temporary)
   {
      // Use handle pooling for temporary indicators
      handle = GetPooledIndicatorHandle(symbol, tf, atr_period, "ATR");
   }
    else
     {
        handle = g_symbols[symbol_index].atr_handle;
     }
   
   if(handle == INVALID_HANDLE)
   {
      Log(LOG_ERROR, "GetATRValue", "Invalid ATR handle for " + symbol);
      return 0.0;
   }

   double values[1] = {0.0};
   int copy_result = CopyBuffer(handle, 0, 1, 1, values);
   
   if(!is_temporary && copy_result == 1)
   {
      g_symbols[symbol_index].last_copy_time = TimeCurrent();
   }
   
   if(copy_result == 1 && MathIsValidNumber(values[0]) && values[0] > 0)
   {
      // store in cache (reuse matching tf/period, else first empty, else true LRU)
      int slot = -1;
      int empty_slot = -1;
      datetime oldest = LONG_MAX;
      for(int i = 0; i < MAX_ATR_CACHE; i++)
      {
         if(g_atr_cache[symbol_index][i].tf == tf && g_atr_cache[symbol_index][i].period == atr_period)
         { slot = i; break; }
         if(g_atr_cache[symbol_index][i].bar_time == 0 && empty_slot < 0)
            empty_slot = i;
         if(g_atr_cache[symbol_index][i].last_used < oldest)
         {
            oldest = g_atr_cache[symbol_index][i].last_used;
            slot = i;
         }
      }
      if(slot < 0) slot = (empty_slot >= 0 ? empty_slot : 0);
      g_atr_cache[symbol_index][slot].value = values[0];
      g_atr_cache[symbol_index][slot].bar_time = bar_time;
      g_atr_cache[symbol_index][slot].tf = tf;
      g_atr_cache[symbol_index][slot].period = atr_period;
      g_atr_cache[symbol_index][slot].last_used = TimeCurrent();
      return values[0];
   }
   
   // Revalidate handle once on failure
   if(copy_result != 1 || values[0] <= 0 || !MathIsValidNumber(values[0]))
   {
      if(!is_temporary)
      {
         datetime now = TimeCurrent();
         if(g_symbols[symbol_index].last_copy_time > 0 &&
            (now - g_symbols[symbol_index].last_copy_time) < 5)
         {
            // Cooldown: avoid thrashing ATR handle on transient copy failures.
            double fallback_atr = 0.0;
            datetime best_used = 0;
            for(int i = 0; i < MAX_ATR_CACHE; i++)
            {
               if(g_atr_cache[symbol_index][i].tf == tf &&
                  g_atr_cache[symbol_index][i].period == atr_period &&
                  g_atr_cache[symbol_index][i].value > 0.0 &&
                  MathIsValidNumber(g_atr_cache[symbol_index][i].value))
               {
                  if(g_atr_cache[symbol_index][i].last_used >= best_used)
                  {
                     best_used = g_atr_cache[symbol_index][i].last_used;
                     fallback_atr = g_atr_cache[symbol_index][i].value;
                  }
               }
            }
            if(fallback_atr > 0.0)
               return fallback_atr;
            return 0.0;
         }
      }

      if(is_temporary)
         handle = GetPooledIndicatorHandle(symbol, tf, atr_period, "ATR");
      else
      {
        // Recreate main ATR handle on failed reads to avoid stale-handle loops
        if(g_symbols[symbol_index].atr_handle != INVALID_HANDLE)
           IndicatorRelease(g_symbols[symbol_index].atr_handle);
        g_symbols[symbol_index].atr_handle = iATR(symbol, tf, atr_period);
        handle = g_symbols[symbol_index].atr_handle;
      }
      if(handle != INVALID_HANDLE)
         copy_result = CopyBuffer(handle, 0, 1, 1, values);
      else
         copy_result = -1;
      if(copy_result == 1 && MathIsValidNumber(values[0]) && values[0] > 0)
      {
        int slot = -1;
        int empty_slot = -1;
        datetime oldest = LONG_MAX;
        for(int i = 0; i < MAX_ATR_CACHE; i++)
        {
           if(g_atr_cache[symbol_index][i].tf == tf && g_atr_cache[symbol_index][i].period == atr_period)
           { slot = i; break; }
           if(g_atr_cache[symbol_index][i].bar_time == 0 && empty_slot < 0)
              empty_slot = i;
           if(g_atr_cache[symbol_index][i].last_used < oldest)
           {
              oldest = g_atr_cache[symbol_index][i].last_used;
              slot = i;
           }
        }
        if(slot < 0) slot = (empty_slot >= 0 ? empty_slot : 0);
        g_atr_cache[symbol_index][slot].value = values[0];
        g_atr_cache[symbol_index][slot].bar_time = bar_time;
        g_atr_cache[symbol_index][slot].tf = tf;
        g_atr_cache[symbol_index][slot].period = atr_period;
        g_atr_cache[symbol_index][slot].last_used = TimeCurrent();
        return values[0];
      }
   }

   return 0.0;
}

double GetMACDValue(string symbol, ENUM_TIMEFRAMES tf)
{
   int symbol_index = GetSymbolIndex(symbol);
   if(symbol_index < 0)
      return 0.0;

   int macd_handle = GetPooledIndicatorHandle(symbol, tf, 12, "MACD");
   if(macd_handle == INVALID_HANDLE)
   {
      Log(LOG_WARNING, "GetMACDValue", "Failed to create MACD handle for " + symbol);
      return 0.0;
   }

   double macd_values[1];
   int copy_result = CopyBuffer(macd_handle, 0, 0, 1, macd_values);
   
   if(copy_result == 1 && MathIsValidNumber(macd_values[0]))
   {
      double normalized = NormalizeMACDValue(symbol, tf, symbol_index, macd_values[0]);
      return normalized;
   }

   return 0.0;
}

double GetStochasticValue(string symbol, ENUM_TIMEFRAMES tf)
{
   int stoch_handle = GetPooledIndicatorHandle(symbol, tf, 14, "STOCH");
   if(stoch_handle == INVALID_HANDLE)
   {
      Log(LOG_WARNING, "GetStochasticValue", "Failed to create Stochastic handle for " + symbol);
      return 50.0;  // Neutral midpoint
   }

   double stoch_values[1];
   int copy_result = CopyBuffer(stoch_handle, 0, 0, 1, stoch_values);
   
   if(copy_result == 1 && MathIsValidNumber(stoch_values[0]))
   {
      // Normalize to 0-100 range if needed, clamp to valid bounds
      double stoch_val = MathClamp(stoch_values[0], 0.0, 100.0);
      return stoch_val;
   }

   return 50.0;  // Neutral midpoint on failure
}

int GetPooledIndicatorHandle(string symbol, ENUM_TIMEFRAMES tf, int period, string type)
{
   datetime now = TimeCurrent();
   static datetime last_fallback_cleanup = 0;
   if(last_fallback_cleanup == 0 || now < last_fallback_cleanup || (now - last_fallback_cleanup) >= 30)
   {
      CleanupFallbackHandles();
      last_fallback_cleanup = now;
   }
   
   for(int i = 0; i < 20; i++)
   {
      if(g_indicator_pool[i].symbol == symbol && 
         g_indicator_pool[i].tf == tf && 
         g_indicator_pool[i].period == period && 
         g_indicator_pool[i].type == type &&
         g_indicator_pool[i].handle != INVALID_HANDLE)
      {
         g_indicator_pool[i].last_used = now;
         return g_indicator_pool[i].handle;
      }
   }
   
   for(int i = 0; i < 20; i++)
   {
      if(g_indicator_pool[i].handle == INVALID_HANDLE || 
         (now - g_indicator_pool[i].last_used) > 300)
      {
         if(g_indicator_pool[i].handle != INVALID_HANDLE)
         {
            IndicatorRelease(g_indicator_pool[i].handle);
            g_indicator_pool[i].handle = INVALID_HANDLE;
            g_indicator_pool[i].symbol = "";
            g_indicator_pool[i].tf = (ENUM_TIMEFRAMES)-1;
            g_indicator_pool[i].period = 0;
            g_indicator_pool[i].type = "";
            g_indicator_pool[i].last_used = 0;
         }
            
         int new_handle = INVALID_HANDLE;
         if(type == "ATR")
            new_handle = iATR(symbol, tf, period);
         else if(type == "RSI")
            new_handle = iRSI(symbol, tf, period, PRICE_CLOSE);
         else if(type == "ADX")
            new_handle = iADX(symbol, tf, period);
         else if(type == "MACD")
            new_handle = iMACD(symbol, tf, period, 26, 9, PRICE_CLOSE);
         else if(type == "STOCH")
            new_handle = iStochastic(symbol, tf, period, 3, 3, MODE_SMA, STO_LOWHIGH);
         else if(type == "EMA")
            new_handle = iMA(symbol, tf, period, 0, MODE_EMA, PRICE_CLOSE);
         else if(type == "MA")
            new_handle = iMA(symbol, tf, period, 0, MODE_SMA, PRICE_CLOSE);
            
         if(new_handle != INVALID_HANDLE)
         {
            g_indicator_pool[i].handle = new_handle;
            g_indicator_pool[i].symbol = symbol;
            g_indicator_pool[i].tf = tf;
            g_indicator_pool[i].period = period;
            g_indicator_pool[i].type = type;
            g_indicator_pool[i].last_used = now;
            return new_handle;
         }
      }
   }
   
   int fallback_handle = INVALID_HANDLE;

   NormalizeFallbackHandleCount();
   for(int i = 0; i < g_fallback_count; i++)
   {
      if(g_fallback_handles[i].handle == INVALID_HANDLE)
         continue;
      if(g_fallback_handles[i].symbol == symbol &&
         g_fallback_handles[i].tf == tf &&
         g_fallback_handles[i].period == period &&
         g_fallback_handles[i].type == type)
      {
         g_fallback_handles[i].created_time = now;
         return g_fallback_handles[i].handle;
      }
   }

   if(type == "ATR")
      fallback_handle = iATR(symbol, tf, period);
   else if(type == "RSI")
      fallback_handle = iRSI(symbol, tf, period, PRICE_CLOSE);
   else if(type == "ADX")
      fallback_handle = iADX(symbol, tf, period);
   else if(type == "MACD")
      fallback_handle = iMACD(symbol, tf, period, 26, 9, PRICE_CLOSE);
   else if(type == "STOCH")
      fallback_handle = iStochastic(symbol, tf, period, 3, 3, MODE_SMA, STO_LOWHIGH);
   else if(type == "EMA")
      fallback_handle = iMA(symbol, tf, period, 0, MODE_EMA, PRICE_CLOSE);
   else if(type == "MA")
      fallback_handle = iMA(symbol, tf, period, 0, MODE_SMA, PRICE_CLOSE);
      
   if(fallback_handle != INVALID_HANDLE && g_fallback_count < 10)
   {
      g_fallback_handles[g_fallback_count].handle = fallback_handle;
      g_fallback_handles[g_fallback_count].created_time = now;
      g_fallback_handles[g_fallback_count].symbol = symbol;
      g_fallback_handles[g_fallback_count].tf = tf;
      g_fallback_handles[g_fallback_count].period = period;
      g_fallback_handles[g_fallback_count].type = type;
      g_fallback_count++;
   }
   else if(fallback_handle != INVALID_HANDLE)
   {
      int recycle_index = 0;
      datetime oldest_created = g_fallback_handles[0].created_time;
      for(int i = 1; i < g_fallback_count && i < 10; i++)
      {
         if(g_fallback_handles[i].created_time < oldest_created)
         {
            oldest_created = g_fallback_handles[i].created_time;
            recycle_index = i;
         }
      }

      if(g_fallback_handles[recycle_index].handle != INVALID_HANDLE)
         IndicatorRelease(g_fallback_handles[recycle_index].handle);

      g_fallback_handles[recycle_index].handle = fallback_handle;
      g_fallback_handles[recycle_index].created_time = now;
      g_fallback_handles[recycle_index].symbol = symbol;
      g_fallback_handles[recycle_index].tf = tf;
      g_fallback_handles[recycle_index].period = period;
      g_fallback_handles[recycle_index].type = type;
   }
      
   return fallback_handle;
}

// MEDIUM FIX: Validate and cleanup indicator pool to prevent stale handle leaks
void ValidateIndicatorPoolHandles()
{
   datetime now = TimeCurrent();
   int stale_count = 0;
   int invalid_count = 0;
   double tmp_buffer[1];
   
   for(int i = 0; i < 20; i++)
   {
      if(g_indicator_pool[i].handle == INVALID_HANDLE)
         continue;
      
      // Check if handle is stale (not used in 5+ minutes)
      int age_seconds = (int)(now - g_indicator_pool[i].last_used);
      if(age_seconds > 300)
      {
         IndicatorRelease(g_indicator_pool[i].handle);
         g_indicator_pool[i].handle = INVALID_HANDLE;
         g_indicator_pool[i].symbol = "";
         stale_count++;
         Log(LOG_DEBUG, "ValidateIndicatorPoolHandles", "Released stale handle at slot " + IntegerToString(i) + " (age: " + IntegerToString(age_seconds) + "s)");
      }
      // Validate handle is still valid by testing it
      else if(CopyBuffer(g_indicator_pool[i].handle, 0, 0, 1, tmp_buffer) < 1)
      {
         IndicatorRelease(g_indicator_pool[i].handle);
         g_indicator_pool[i].handle = INVALID_HANDLE;
         g_indicator_pool[i].symbol = "";
         invalid_count++;
         Log(LOG_WARNING, "ValidateIndicatorPoolHandles", "Detected invalid handle at slot " + IntegerToString(i) + " (" + g_indicator_pool[i].type + " on " + g_indicator_pool[i].symbol + "); released and reset");
      }
   }
   
   if(stale_count > 0 || invalid_count > 0)
      Log(LOG_INFO, "ValidateIndicatorPoolHandles", "Cleanup complete: " + IntegerToString(stale_count) + " stale, " + IntegerToString(invalid_count) + " invalid");
}

void ValidateATRHandle(string symbol, int symbol_index, ENUM_TIMEFRAMES tf, int period)
{
   if(symbol_index < 0)
      symbol_index = GetSymbolIndex(symbol);
   if(symbol_index < 0)
      return;

   int handle = g_symbols[symbol_index].atr_handle;
   if(handle == INVALID_HANDLE)
   {
      g_symbols[symbol_index].atr_handle = iATR(symbol, tf, period);
      return;
   }

   double tmp[1];
   int copied = CopyBuffer(handle, 0, 1, 1, tmp);
   if(copied != 1 || !MathIsValidNumber(tmp[0]) || tmp[0] <= 0)
      copied = CopyBuffer(handle, 0, 0, 1, tmp);
   if(copied != 1 || !MathIsValidNumber(tmp[0]) || tmp[0] <= 0)
   {
      datetime now = TimeCurrent();
      if(g_symbols[symbol_index].last_copy_time > 0 && (now - g_symbols[symbol_index].last_copy_time) < 5)
         return; // Avoid recreating ATR handle repeatedly on transient copy failures.
      if(g_symbols[symbol_index].atr_handle != INVALID_HANDLE)
         IndicatorRelease(g_symbols[symbol_index].atr_handle);
      g_symbols[symbol_index].atr_handle = iATR(symbol, tf, period);
   }
   else
   {
      g_symbols[symbol_index].last_copy_time = TimeCurrent();
   }
}

void CleanupFallbackHandles()
{
   NormalizeFallbackHandleCount();
   datetime now = TimeCurrent();
   for(int i = g_fallback_count - 1; i >= 0; i--)
   {
      bool invalid_entry = (g_fallback_handles[i].handle == INVALID_HANDLE);
      bool expired_entry = false;
      if(!invalid_entry)
      {
         datetime created_time = g_fallback_handles[i].created_time;
         expired_entry = (created_time <= 0 || now < created_time || (now - created_time) > 600);
      }

      if(invalid_entry || expired_entry)
      {
         if(g_fallback_handles[i].handle != INVALID_HANDLE)
            IndicatorRelease(g_fallback_handles[i].handle);
          
         for(int j = i; j < g_fallback_count - 1 && j < 9; j++)
            g_fallback_handles[j] = g_fallback_handles[j + 1];
         g_fallback_count--;
         ResetFallbackHandleSlot(g_fallback_count);
      }
   }
}

void ResetAIPredictionCacheEntry(int symbol_index)
{
   if(symbol_index < 0 || symbol_index >= MAX_SYMBOLS)
      return;

   g_ai_prediction_cache[symbol_index].probability = 0.5;
   g_ai_prediction_cache[symbol_index].buy_prob = 0.5;
   g_ai_prediction_cache[symbol_index].sell_prob = 0.5;
   g_ai_prediction_cache[symbol_index].last_update = 0;
   g_ai_prediction_cache[symbol_index].confidence = 0.0;
   g_ai_prediction_cache[symbol_index].access_count = 0;
   g_ai_prediction_cache[symbol_index].created_time = 0;
   g_ai_prediction_cache[symbol_index].tf = PERIOD_CURRENT;
   g_ai_prediction_cache[symbol_index].bar_time = 0;
   g_ai_prediction_cache[symbol_index].source_tick_msc = 0;
}

void CleanupAIPredictionCache()
{
   datetime current_time = TimeCurrent();
   int cleanup_interval = MathMax(30, g_ai_cache_manager.cleanup_interval);
   int max_cache_age = MathMax(300, g_ai_cache_manager.max_cache_age);

   if(g_ai_cache_manager.last_cleanup > 0 &&
      current_time >= g_ai_cache_manager.last_cleanup &&
      (current_time - g_ai_cache_manager.last_cleanup) < cleanup_interval)
   {
      return;
   }

   for(int i = 0; i < MAX_SYMBOLS; i++)
   {
      datetime freshness_anchor = g_ai_prediction_cache[i].last_update;
      if(g_ai_prediction_cache[i].created_time > freshness_anchor)
         freshness_anchor = g_ai_prediction_cache[i].created_time;

      if(freshness_anchor > 0 &&
         (current_time < freshness_anchor || (current_time - freshness_anchor) > max_cache_age))
      {
         ResetAIPredictionCacheEntry(i);
      }
   }

   g_ai_cache_manager.last_cleanup = current_time;
}

int GetAIPredictionTTLSeconds(ENUM_TIMEFRAMES tf)
{
   int tf_seconds = PeriodSeconds(tf);
   if(tf_seconds <= 0)
      tf_seconds = 60;
   
   int ttl = tf_seconds + 10; // Allow the full bar plus a small buffer
   if(ttl < 60)
      ttl = 60;
   
   return ttl;
}

bool IsAIPredictionFresh(int symbol_index, ENUM_TIMEFRAMES tf)
{
   if(symbol_index < 0 || symbol_index >= g_symbols_count || symbol_index >= MAX_SYMBOLS)
      return false;

   datetime last_update = g_ai_prediction_cache[symbol_index].last_update;
   if(last_update <= 0)
      return false;

   if(!MathIsValidNumber(g_ai_prediction_cache[symbol_index].buy_prob) ||
      !MathIsValidNumber(g_ai_prediction_cache[symbol_index].sell_prob) ||
      !MathIsValidNumber(g_ai_prediction_cache[symbol_index].confidence))
   {
      return false;
   }
   
   datetime now = TimeCurrent();
   if(now < last_update)
      return false;

   if(g_ai_prediction_cache[symbol_index].tf != tf)
      return false;

   string symbol = g_symbols[symbol_index].name;
   if(StringLen(symbol) <= 0)
      return false;

   datetime current_bar_time = iTime(symbol, tf, 0);
   if(current_bar_time <= 0 || g_ai_prediction_cache[symbol_index].bar_time != current_bar_time)
      return false;

   long latest_tick_msc = GetLatestSymbolTickMsc(symbol, symbol_index);
   if(latest_tick_msc > 0 &&
      g_ai_prediction_cache[symbol_index].source_tick_msc > 0 &&
      latest_tick_msc > g_ai_prediction_cache[symbol_index].source_tick_msc)
   {
      return false;
   }

   int ttl = GetAIPredictionTTLSeconds(tf);
   int max_cache_age = MathMax(300, g_ai_cache_manager.max_cache_age);
   int effective_ttl = MathMin(ttl, max_cache_age);
   if(effective_ttl <= 0)
      effective_ttl = 60;

   return (now - last_update) <= effective_ttl;
}

void RecordAICacheAccess(int symbol_index, bool hit)
{
   if(symbol_index < 0 || symbol_index >= MAX_SYMBOLS)
      return;
   
   g_ai_cache_requests++;
   if(hit)
   {
      g_ai_cache_hits++;
      if(g_ai_prediction_cache[symbol_index].access_count < 2147483647)
         g_ai_prediction_cache[symbol_index].access_count++;
   }
   else
   {
      g_ai_cache_misses++;
   }
}

int GetRuntimeCacheTTLSeconds(ENUM_TIMEFRAMES tf)
{
   int tf_seconds = PeriodSeconds(tf);
   if(tf_seconds <= 0)
      tf_seconds = 60;

   int ttl = tf_seconds * 3 + MathMax(10, Signal_Check_Seconds);
   ttl = MathMax(120, MathMin(ttl, 21600));
   return ttl;
}

bool ValidateAITrainingDataDetailed(double close0, double close1, double close5,
                                    double atr_value, double rsi_value, double ma_slope,
                                    double volume0, double volume1, double volume_avg,
                                    double macd_value, double stochastic_value, double sentiment_score,
                                    string &reject_reason)
{
   reject_reason = "";

   if(!MathIsValidNumber(close0) || !MathIsValidNumber(close1) || !MathIsValidNumber(close5))
   {
      reject_reason = "invalid_close_values";
      return false;
   }
   if(close0 <= 0 || close1 <= 0 || close5 <= 0)
   {
      reject_reason = "non_positive_close";
      return false;
   }

   double price_change = MathAbs((close0 - close1) / close1);
   if(!MathIsValidNumber(price_change) || price_change > 0.1)
   {
      reject_reason = "price_jump_gt_10pct";
      return false;
   }

   if(!MathIsValidNumber(atr_value) || atr_value <= 0 || atr_value > (close0 * 0.5))
   {
      reject_reason = "invalid_atr";
      return false;
   }

   if(!MathIsValidNumber(rsi_value) || rsi_value < 0 || rsi_value > 100)
   {
      reject_reason = "invalid_rsi";
      return false;
   }

   if(!MathIsValidNumber(stochastic_value) || stochastic_value < 0 || stochastic_value > 100)
   {
      reject_reason = "invalid_stochastic";
      return false;
   }

   if(!MathIsValidNumber(ma_slope) || MathAbs(ma_slope) > close0 * 0.1)
   {
      reject_reason = "ma_slope_outlier";
      return false;
   }

   if(!MathIsValidNumber(macd_value))
   {
      reject_reason = "invalid_macd";
      return false;
   }

   // Use a floor-based cap so temporary ATR underflow/defaults do not invalidate
   // otherwise valid bars.
   double atr_for_limits = MathMax(atr_value, close0 * 0.0001);
   double macd_cap = MathMax(atr_for_limits * 20.0, close0 * 0.02);
   if(MathAbs(macd_value) > macd_cap)
   {
      reject_reason = "macd_outlier";
      return false;
   }

   if(!MathIsValidNumber(volume0) || !MathIsValidNumber(volume1) || !MathIsValidNumber(volume_avg))
   {
      reject_reason = "invalid_volume";
      return false;
   }
   if(volume0 < 0 || volume1 < 0 || volume_avg < 0)
   {
      reject_reason = "negative_volume";
      return false;
   }
   if(volume0 <= 0 && volume1 <= 0 && volume_avg <= 0)
   {
      reject_reason = "zero_volume_bar";
      return false;
   }

   double safe_volume_avg = MathMax(volume_avg, 1.0);
   if(volume0 > safe_volume_avg * 200.0 || volume1 > safe_volume_avg * 200.0)
   {
      reject_reason = "volume_spike_outlier";
      return false;
   }

   if(!MathIsValidNumber(sentiment_score) || sentiment_score < 0 || sentiment_score > 1)
   {
      reject_reason = "invalid_sentiment";
      return false;
   }

   return true;
}

double NormalizeMACDValue(string symbol, ENUM_TIMEFRAMES tf, int symbol_index, double macd_value)
{
   if(!MathIsValidNumber(macd_value))
      return 0.0;

   double anchor_price = 0.0;
   if(symbol_index >= 0 && symbol_index < g_symbols_count)
   {
      double bid = g_symbols[symbol_index].cache.bid;
      double ask = g_symbols[symbol_index].cache.ask;
      if(bid > 0.0 && ask > 0.0 && bid < ask)
         anchor_price = (bid + ask) / 2.0;
   }

   if(anchor_price <= 0.0)
      anchor_price = iClose(symbol, tf, 0);

   if(anchor_price <= 0.0)
      return macd_value;

   if(MathAbs(macd_value) > anchor_price * 0.20)
   {
      // Some feeds can surface price-anchored MACD values; convert to a bounded momentum feature.
      double anchored_delta = macd_value - anchor_price;
      if(MathAbs(anchored_delta) <= anchor_price * 0.20)
         return anchored_delta;

      return macd_value / anchor_price;
   }

   return macd_value;
}

bool ValidateAITrainingData(double close0, double close1, double close5, 
                           double atr_value, double rsi_value, double ma_slope,
                           double volume0, double volume1, double volume_avg,
                           double macd_value, double stochastic_value, double sentiment_score)
{
   string reject_reason = "";
   return ValidateAITrainingDataDetailed(close0, close1, close5,
                                         atr_value, rsi_value, ma_slope,
                                         volume0, volume1, volume_avg,
                                         macd_value, stochastic_value, sentiment_score,
                                         reject_reason);
}

bool GetCachedAIFeatures(string symbol, double &rsi_value, double &ma_slope, 
                        double &atr_value, double &volume_ratio, ENUM_TIMEFRAMES tf)
{
   int symbol_index = GetSymbolIndex(symbol);
   if(symbol_index < 0 || symbol_index >= g_symbols_count || symbol_index >= MAX_SYMBOLS)
      return false;
   
   // Check if we have cached features for current bar
   datetime current_bar_time = iTime(symbol, tf, 0);
   if(current_bar_time <= 0)
      return false;
   datetime now = TimeCurrent();
   long latest_tick_msc = GetLatestSymbolTickMsc(symbol, symbol_index);
   int feature_ttl = GetRuntimeCacheTTLSeconds(tf);
   if(g_ai_feature_cache[symbol_index].bar_time == current_bar_time &&
      g_ai_feature_cache[symbol_index].tf == tf &&
      g_ai_feature_cache[symbol_index].last_update > 0 &&
      now >= g_ai_feature_cache[symbol_index].last_update &&
      (now - g_ai_feature_cache[symbol_index].last_update) <= feature_ttl &&
      (latest_tick_msc <= 0 ||
       g_ai_feature_cache[symbol_index].last_tick_msc <= 0 ||
       latest_tick_msc <= g_ai_feature_cache[symbol_index].last_tick_msc) &&
      g_ai_feature_cache[symbol_index].is_valid)
   {
      // FIXED: Return cached values (avoid recalculation)
      rsi_value = g_ai_feature_cache[symbol_index].rsi_value;
      ma_slope = g_ai_feature_cache[symbol_index].ma_slope;
      atr_value = g_ai_feature_cache[symbol_index].atr_value;
      volume_ratio = g_ai_feature_cache[symbol_index].volume_ratio;
      return true;
   }
    
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   bool have_rates = GetCachedRates(symbol, tf, rates, 22);
   double current_price = 0.0;
   double fallback_ma_slope = 0.0;
   bool fallback_ma_valid = false;
   double fallback_atr = 0.0;
   bool fallback_atr_valid = false;

   if(have_rates && ArraySize(rates) >= 22)
   {
      current_price = rates[0].close;

      double ma_now = 0.0;
      double ma_prev = 0.0;
      for(int i = 0; i < 20; i++)
      {
         ma_now += rates[i].close;
         ma_prev += rates[i + 1].close;
      }
      fallback_ma_slope = (ma_now / 20.0) - (ma_prev / 20.0);
      fallback_ma_valid = MathIsValidNumber(fallback_ma_slope);

      double tr_sum = 0.0;
      int tr_samples = 0;
      for(int bar_index = 0; bar_index < 14 && bar_index + 1 < ArraySize(rates); bar_index++)
      {
         double high = rates[bar_index].high;
         double low = rates[bar_index].low;
         double prev_close = rates[bar_index + 1].close;
         double tr = MathMax(high - low, MathMax(MathAbs(high - prev_close), MathAbs(low - prev_close)));
         if(MathIsValidNumber(tr) && tr > 0.0)
         {
            tr_sum += tr;
            tr_samples++;
         }
      }
      if(tr_samples > 0)
      {
         fallback_atr = tr_sum / (double)tr_samples;
         fallback_atr_valid = (MathIsValidNumber(fallback_atr) && fallback_atr > 0.0);
      }
   }
   else if(have_rates && ArraySize(rates) > 0)
   {
      current_price = rates[0].close;
   }

   if(!MathIsValidNumber(current_price) || current_price <= 0.0)
      current_price = SymbolInfoDouble(symbol, SYMBOL_BID);

   // Calculate fresh features using hardened readers and rates-based fallbacks.
   rsi_value = GetRSIValue(symbol, tf, 14);

   int ma_handle = GetPooledIndicatorHandle(symbol, tf, 20, "MA");
   ma_slope = 0.0;
   if(ma_handle != INVALID_HANDLE)
   {
      double ma_buffer[2];
      // Use closed bars to avoid transient values from the still-forming candle.
      if(CopyBuffer(ma_handle, 0, 1, 2, ma_buffer) == 2 &&
         MathIsValidNumber(ma_buffer[0]) && MathIsValidNumber(ma_buffer[1]))
      {
         ma_slope = ma_buffer[0] - ma_buffer[1];
      }
   }
   if((!MathIsValidNumber(ma_slope) || ma_slope == 0.0) && fallback_ma_valid)
      ma_slope = fallback_ma_slope;

   atr_value = GetATRValue(symbol, tf, 14);
   bool atr_valid = (MathIsValidNumber(atr_value) && atr_value > 0.0);
   if(atr_valid &&
      MathIsValidNumber(current_price) && current_price > 0.0 &&
      atr_value > (current_price * 0.5))
   {
      atr_valid = false;
   }
   if(!atr_valid && fallback_atr_valid)
   {
      atr_value = fallback_atr;
      atr_valid = true;
      if(MathIsValidNumber(current_price) && current_price > 0.0 &&
         atr_value > (current_price * 0.5))
      {
         atr_valid = false;
      }
   }

   if(!atr_valid)
      return false;

   if(have_rates && ArraySize(rates) >= 3)
   {
      double avg_volume = (rates[0].tick_volume + rates[1].tick_volume + rates[2].tick_volume) / 3.0;
      volume_ratio = (avg_volume > 0) ? rates[0].tick_volume / avg_volume : 1.0;
   }
   else
      volume_ratio = 1.0;
   
   // FIXED: Cache the calculated features for current bar
   g_ai_feature_cache[symbol_index].rsi_value = rsi_value;
   g_ai_feature_cache[symbol_index].ma_slope = ma_slope;
   g_ai_feature_cache[symbol_index].atr_value = atr_value;
   g_ai_feature_cache[symbol_index].volume_ratio = volume_ratio;
   g_ai_feature_cache[symbol_index].bar_time = current_bar_time;
   g_ai_feature_cache[symbol_index].last_update = now;
   g_ai_feature_cache[symbol_index].last_tick_msc =
      (latest_tick_msc > 0 ? latest_tick_msc : (long)now * 1000);
   g_ai_feature_cache[symbol_index].tf = tf;
   g_ai_feature_cache[symbol_index].is_valid =
      MathIsValidNumber(rsi_value) &&
      MathIsValidNumber(ma_slope) &&
      MathIsValidNumber(atr_value) &&
      atr_value > 0.0 &&
      (!(MathIsValidNumber(current_price) && current_price > 0.0) || atr_value <= (current_price * 0.5));
   
   return g_ai_feature_cache[symbol_index].is_valid;
}

int SelectAIDirection(double buy_prob, double sell_prob, double buy_min_prob, double sell_min_prob);
double GetAIDirectionalMinProbability(int direction, string symbol, int symbol_index);

void UpdateAIPerformanceStats(double buy_prob, double sell_prob, int actual_direction, int symbol_index)
{
   if(actual_direction != 1 && actual_direction != -1)
      return;

   if(!MathIsValidNumber(buy_prob) || !MathIsValidNumber(sell_prob))
      return;

   buy_prob = MathMax(0.0, MathMin(1.0, buy_prob));
   sell_prob = MathMax(0.0, MathMin(1.0, sell_prob));

   double buy_min_prob = g_AI_Buy_Confidence_Threshold;
   double sell_min_prob = g_AI_Sell_Confidence_Threshold;
   int trend_level = AI_Trend_Confidence;
   if(trend_level < 0) trend_level = 0;
   if(trend_level > 5) trend_level = 5;
   buy_min_prob += (trend_level - 1) * 0.05;
   sell_min_prob += (trend_level - 1) * 0.05;
   buy_min_prob = MathClamp(buy_min_prob, 0.45, 0.90);
   sell_min_prob = MathClamp(sell_min_prob, 0.45, 0.90);

   if(symbol_index >= 0 && symbol_index < g_symbols_count)
   {
      string symbol = g_symbols[symbol_index].name;
      if(StringLen(symbol) > 0)
      {
         buy_min_prob = GetAIDirectionalMinProbability(1, symbol, symbol_index);
         sell_min_prob = GetAIDirectionalMinProbability(-1, symbol, symbol_index);
      }
   }

   int predicted_direction = SelectAIDirection(buy_prob, sell_prob, buy_min_prob, sell_min_prob);
   if(predicted_direction == 0)
      return;

   g_ai_performance.total_predictions++;
   if(predicted_direction == actual_direction)
      g_ai_performance.correct_predictions++;

   g_ai_performance.accuracy_rate = (g_ai_performance.total_predictions > 0 ?
      (double)g_ai_performance.correct_predictions / g_ai_performance.total_predictions : 0.0);

   if(g_ai_performance.total_predictions >= 50 && g_ai_performance.accuracy_rate < 0.45)
      g_ai_performance.needs_retraining = true;

   if(symbol_index >= 0 && symbol_index < g_symbols_count && symbol_index < MAX_SYMBOLS)
   {
      g_ai_performance_by_symbol[symbol_index].total_predictions++;
      if(predicted_direction == actual_direction)
         g_ai_performance_by_symbol[symbol_index].correct_predictions++;

      g_ai_performance_by_symbol[symbol_index].accuracy_rate =
         (g_ai_performance_by_symbol[symbol_index].total_predictions > 0 ?
            (double)g_ai_performance_by_symbol[symbol_index].correct_predictions /
            g_ai_performance_by_symbol[symbol_index].total_predictions : 0.0);

      if(g_ai_performance_by_symbol[symbol_index].total_predictions >= 50 &&
         g_ai_performance_by_symbol[symbol_index].accuracy_rate < 0.45)
         g_ai_performance_by_symbol[symbol_index].needs_retraining = true;
   }
}

bool CheckAIAgreementWithConfidence(double dir_probability, int signal_direction, double min_probability = 0.6)
{
   if(!g_ai_enabled || dir_probability < 0 || dir_probability > 1)
      return true; // Default to agreement if AI disabled or invalid

   if(signal_direction == 0)
      return false;

   // dir_probability is already directional (buy_prob for BUY, sell_prob for SELL)
   return (dir_probability >= min_probability);
}

void MaintainRateCache()
{
   datetime now = TimeCurrent();
   double total_memory = 0;
   int total_cached = 0;
   int stale_seconds = MathMax(120, CACHE_TIMEOUT_SECONDS * 4);
   
   // Calculate total cache memory
   for(int i = 0; i < g_symbols_count; i++)
   {
      if(g_symbols[i].cache.last_rates_update > 0 &&
         now >= g_symbols[i].cache.last_rates_update &&
         (now - g_symbols[i].cache.last_rates_update) > stale_seconds)
      {
         ArrayFree(g_symbols[i].cache.last_rates);
         g_symbols[i].cache.last_rates_update = 0;
         g_symbols[i].cache.last_rates_bar_time = 0;
         g_symbols[i].cache.last_rates_tf = PERIOD_CURRENT;
         g_symbols[i].cache.last_rates_tick_msc = 0;
         g_cache_metadata[i].last_accessed = 0;
         g_cache_metadata[i].access_count = 0;
         continue;
      }

      int cache_size = ArraySize(g_symbols[i].cache.last_rates);
      total_memory += cache_size * sizeof(MqlRates);
      total_cached += cache_size;
   }
   
   // If cache grows too large, evict least recently used
   const double MAX_CACHE_MB = 50.0; // 50MB limit
   if(total_memory > MAX_CACHE_MB * 1024 * 1024)
   {
      Log(LOG_WARNING, "MaintainRateCache", "Cache size " + DoubleToString(total_memory / 1024 / 1024, 1) + 
          "MB exceeds limit, evicting old data");
      
      // Find least recently used symbol
      int lru_index = 0;
      datetime oldest_access = g_cache_metadata[0].last_accessed;
      
      for(int i = 1; i < g_symbols_count; i++)
      {
         if(g_cache_metadata[i].last_accessed < oldest_access)
         {
            oldest_access = g_cache_metadata[i].last_accessed;
            lru_index = i;
         }
      }
      
      // Clear LRU cache
      ArrayFree(g_symbols[lru_index].cache.last_rates);
      g_symbols[lru_index].cache.last_rates_update = 0;
      g_symbols[lru_index].cache.last_rates_bar_time = 0;
      g_symbols[lru_index].cache.last_rates_tf = PERIOD_CURRENT;
      g_symbols[lru_index].cache.last_rates_tick_msc = 0;
      g_cache_metadata[lru_index].last_accessed = 0;
      g_cache_metadata[lru_index].access_count = 0;
      
      Log(LOG_DEBUG, "MaintainRateCache", "Evicted cache for " + g_symbols[lru_index].name);
   }
}

void PurgeStaleDerivedCaches()
{
   datetime now = TimeCurrent();
   int signal_ttl = GetRuntimeCacheTTLSeconds(Signal_TF);

   for(int i = 0; i < g_symbols_count && i < MAX_SYMBOLS; i++)
   {
      for(int tf_slot = 0; tf_slot < STRATEGY_TF_SLOTS; tf_slot++)
      {
         ENUM_TIMEFRAMES tf = GetStrategyTimeframeBySlot(tf_slot);
         int ttl = GetRuntimeCacheTTLSeconds(tf);

         if(g_indicator_cache[i][tf_slot].is_valid)
         {
            datetime t = g_indicator_cache[i][tf_slot].last_bar_time;
            if(t <= 0 || now < t || (now - t) > ttl)
            {
               g_indicator_cache[i][tf_slot].is_valid = false;
               g_indicator_cache[i][tf_slot].last_bar_time = 0;
               g_indicator_cache[i][tf_slot].rsi_value = 50.0;
            }
         }

         if(g_momentum_cache[i][tf_slot].valid)
         {
            datetime t = g_momentum_cache[i][tf_slot].bar_time;
            if(t <= 0 || now < t || (now - t) > ttl)
            {
               g_momentum_cache[i][tf_slot].valid = false;
               g_momentum_cache[i][tf_slot].bar_time = 0;
               g_momentum_cache[i][tf_slot].macd = 0.0;
               g_momentum_cache[i][tf_slot].stoch = 50.0;
            }
         }
      }

      if(g_ai_feature_cache[i].is_valid)
      {
         int feature_ttl = GetRuntimeCacheTTLSeconds(g_ai_feature_cache[i].tf);
         datetime t = g_ai_feature_cache[i].last_update;
         if(t <= 0)
            t = g_ai_feature_cache[i].bar_time;
         if(t <= 0 || now < t || (now - t) > feature_ttl)
         {
            g_ai_feature_cache[i].is_valid = false;
            g_ai_feature_cache[i].bar_time = 0;
            g_ai_feature_cache[i].last_update = 0;
            g_ai_feature_cache[i].last_tick_msc = 0;
         }
      }

      datetime volatility_anchor = g_volatility_cache[i].last_update;
      if(volatility_anchor <= 0)
         volatility_anchor = g_volatility_cache[i].last_bar_time;
      if(volatility_anchor > 0 &&
         now >= volatility_anchor &&
         (now - volatility_anchor) > signal_ttl)
      {
         g_volatility_cache[i].last_bar_time = 0;
         g_volatility_cache[i].last_update = 0;
         g_volatility_cache[i].last_tick_msc = 0;
      }

      int atr_ttl = MathMax(900, signal_ttl * 2);
      for(int a = 0; a < MAX_ATR_CACHE; a++)
      {
         datetime atr_last_used = g_atr_cache[i][a].last_used;
         if(atr_last_used > 0 &&
            now >= atr_last_used &&
            (now - atr_last_used) > atr_ttl)
         {
            g_atr_cache[i][a].value = 0.0;
            g_atr_cache[i][a].bar_time = 0;
            g_atr_cache[i][a].tf = (ENUM_TIMEFRAMES)-1;
            g_atr_cache[i][a].period = 0;
            g_atr_cache[i][a].last_used = 0;
         }
      }

      for(int slot = 0; slot < MAX_TF_CACHE; slot++)
      {
         ENUM_TIMEFRAMES tf = g_structure_cache[i][slot].tf;
         if(tf == (ENUM_TIMEFRAMES)-1)
            continue;

         int ttl = GetRuntimeCacheTTLSeconds(tf);
         if(g_structure_cache[i][slot].last_update > 0 &&
            now >= g_structure_cache[i][slot].last_update &&
            (now - g_structure_cache[i][slot].last_update) > ttl)
         {
            g_structure_cache[i][slot].last_update = 0;
         }

         if(g_htf_bias_calc_time[i][slot] > 0 &&
            now >= g_htf_bias_calc_time[i][slot] &&
            (now - g_htf_bias_calc_time[i][slot]) > ttl)
         {
            g_htf_bias_cache_time[i][slot] = 0;
            g_htf_bias_calc_time[i][slot] = 0;
         }
      }
   }
}

double GetCachedVolatilityFactor(string symbol, int symbol_index)
{
   if(symbol_index < 0 || symbol_index >= g_symbols_count || symbol_index >= MAX_SYMBOLS)
      return 1.0;
    
   datetime now = TimeCurrent();
   datetime current_bar = iTime(symbol, Signal_TF, 0);
   long latest_tick_msc = GetLatestSymbolTickMsc(symbol, symbol_index);
   int cache_ttl = GetRuntimeCacheTTLSeconds(Signal_TF);

   if(g_volatility_cache[symbol_index].last_bar_time == current_bar &&
      g_volatility_cache[symbol_index].last_update > 0 &&
      now >= g_volatility_cache[symbol_index].last_update &&
      (now - g_volatility_cache[symbol_index].last_update) <= cache_ttl &&
      (latest_tick_msc <= 0 ||
       g_volatility_cache[symbol_index].last_tick_msc <= 0 ||
       latest_tick_msc <= g_volatility_cache[symbol_index].last_tick_msc))
   {
      return g_volatility_cache[symbol_index].factor;  // Cache hit
   }
    
   // Cache miss: recalculate volatility
   double volatility_factor = 1.0;
   
   if(g_Enable_Volatility_Adjustment)
   {
      double atr_short = GetATRValue(symbol, Signal_TF, g_Volatility_Lookback_Short);
      double atr_long = GetATRValue(symbol, Signal_TF, g_Volatility_Lookback_Long);
      
      if(atr_short > 0 && atr_long > 0)
      {
         volatility_factor = SafeDiv(atr_short, atr_long, 1.0);
         volatility_factor = MathClamp(volatility_factor, 0.5, g_Max_Volatility_Adjustment_Factor);
      }
   }
   
    // Update cache
   g_volatility_cache[symbol_index].factor = volatility_factor;
   g_volatility_cache[symbol_index].last_bar_time = current_bar;
   g_volatility_cache[symbol_index].last_update = now;
   g_volatility_cache[symbol_index].last_tick_msc =
      (latest_tick_msc > 0 ? latest_tick_msc : (long)now * 1000);
    
   return volatility_factor;
}

#endif // INDICATORS_CACHE_MQH
