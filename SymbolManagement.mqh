#ifndef SYMBOL_MANAGEMENT_MQH
#define SYMBOL_MANAGEMENT_MQH

const double SPREAD_EMA_ALPHA = 0.05; // 5% EMA update for average spread

// ===== SYMBOL-SPECIFIC SPREAD CONFIGURATION STRUCTURE =====
struct SSymbolSpreadConfig {
   string symbol;           // Symbol name (e.g., "XAUUSD")
   int max_spread_pips;     // Maximum allowed spread in pips
   double spread_tighten_factor; // Multiplier for adaptive spread adjustments
   bool use_absolute_limit; // Use net_spread_limit_pips as hard limit?
   double net_spread_limit_pips; // Absolute spread limit (hard cap if enabled)
};

bool IsGoldLikeSpreadSymbol(string symbol)
{
   string symbol_upper = symbol;
   StringToUpper(symbol_upper);
   return (StringFind(symbol_upper, "XAU") >= 0 || StringFind(symbol_upper, "GOLD") >= 0);
}

bool SymbolMatchesSpreadProfile(string target_symbol, string config_symbol)
{
   string target_upper = target_symbol;
   string config_upper = config_symbol;
   StringToUpper(target_upper);
   StringToUpper(config_upper);

   if(target_upper == config_upper)
      return true;

   if(IsGoldLikeSpreadSymbol(target_upper) && IsGoldLikeSpreadSymbol(config_upper))
      return true;

   return (StringFind(target_upper, config_upper) >= 0);
}

// ===== PREDEFINED SYMBOL SPREAD CONFIGURATIONS =====
static SSymbolSpreadConfig g_symbol_spread_config[] = {
   // Symbol         MaxPips  TightenFactor  UseAbsLimit  AbsoluteLimitPips
   {"XAUUSD",       65,      1.00,          true,        55.0},    // Gold: stricter limits
   {"EURUSD",       35,      1.00,          false,       0},       // EUR: standard limits
   {"GBPUSD",       40,      1.00,          false,       0},       // GBP: slightly higher volatility
   {"USDJPY",       30,      1.00,          false,       0},       // JPY: tight spreads
   {"AUDUSD",       45,      1.00,          false,       0},       // AUD: moderate spreads
   {"NZDUSD",       50,      1.00,          false,       0},       // NZD: moderate-high spreads
   // Crypto & Commodity pairs with larger decimal places (need higher pip limits)
   {"BTCUSD",       500,     1.00,          false,       0},       // BTC: high point spread
   {"ETHUSD",       500,     1.00,          false,       0},       // ETH: high point spread
   {"XRPUSD",       500,     1.00,          false,       0},       // XRP: high point spread
   {"LTCUSD",       500,     1.00,          false,       0}        // LTC: high point spread
};

int GetSymbolHashFunc(string symbol)
{
   // Better hash function using Jenkins One At A Time
   uint hash = 0;  // Use unsigned to prevent sign issues
   int len = StringLen(symbol);
   
   for(int i = 0; i < len; i++)
   {
      hash += StringGetCharacter(symbol, i);
      hash += (hash << 10);
      hash ^= (hash >> 6);
   }
   
   hash += (hash << 3);
   hash ^= (hash >> 11);
   hash += (hash << 15);
   
   return (int)(hash & 0x7FFFFFFF);  // Return as positive int
}

void BuildSymbolHashTable()
{
   // Clear hash table
   for(int i = 0; i < 157; i++)
   {
      g_symbol_hash_table[i].symbol_index = -1;
   }
   
   // Insert symbols into hash table
   for(int i = 0; i < g_symbols_count; i++)
   {
      int hash = GetSymbolHashFunc(g_symbols[i].name) % 157;
      
      // Linear probing for collision resolution
      int attempts = 0;
      while(g_symbol_hash_table[hash].symbol_index >= 0 && attempts < 157)
      {
         hash = (hash + 1) % 157;
         attempts++;
      }
      
      if(attempts < 157)
      {
         g_symbol_hash_table[hash].symbol_index = i;
      }
   }
   
   Log(LOG_INFO, "BuildSymbolHashTable", "Hash table built for " + IntegerToString(g_symbols_count) + " symbols");
}

int GetSymbolIndexFast(string symbol)
{
   int hash = GetSymbolHashFunc(symbol) % 157;
   
   for(int attempts = 0; attempts < 157; attempts++)
   {
      int idx = g_symbol_hash_table[hash].symbol_index;
      if(idx >= 0 && idx < g_symbols_count && g_symbols[idx].name == symbol)
         return idx;
      
      if(idx < 0)  // Empty slot = not found
         return -1;
      
      hash = (hash + 1) % 157;
   }
   
   return -1;
}

int ParseSymbolList(string &result[])
{
   ArrayFree(result);
   
   g_chart_symbol = Symbol();
   string chart_symbol_name = g_chart_symbol;
   
   if(Trade_Only_Chart_Symbol)
   {
      ArrayResize(result, 1);
      result[0] = chart_symbol_name;
      Log(LOG_INFO, "ParseSymbolList", "Trading only chart symbol: " + result[0]);
      return 1;
   }
   
   if(StringLen(Symbols_List) == 0)
   {
      ArrayResize(result, 1);
      result[0] = chart_symbol_name;
      Log(LOG_INFO, "ParseSymbolList", "No symbol list, using chart symbol: " + result[0]);
      return 1;
   }

   string normalized_list = Symbols_List;
   StringReplace(normalized_list, ";", ",");
   StringTrimLeft(normalized_list);
   StringTrimRight(normalized_list);

   string split_array[];
   int split_count = StringSplit(normalized_list, ',', split_array);
   
   if(split_count > MAX_SYMBOLS)
   {
      Log(LOG_WARNING, "ParseSymbolList", "Too many symbols, limiting to " + IntegerToString(MAX_SYMBOLS));
      split_count = MAX_SYMBOLS;
   }
    
   ArrayResize(result, split_count);
   int valid_count = 0;
   
   for(int i = 0; i < split_count; i++)
   {
      if(i >= ArraySize(split_array))
         break; // Safety check
         
      string symbol_name = split_array[i];
      StringTrimLeft(symbol_name);
      StringTrimRight(symbol_name);
      string symbol_upper = symbol_name;
      StringToUpper(symbol_upper);

      if(StringLen(symbol_name) > 0 && symbol_upper != "0")
      {
         bool duplicate = false;
         
         for(int j = 0; j < valid_count; j++)
         {
            string existing_upper = result[j];
            StringToUpper(existing_upper);
            
            if(existing_upper == symbol_upper)  // Case-insensitive comparison
            {
               duplicate = true;
               Log(LOG_DEBUG, "ParseSymbolList", "Duplicate symbol detected: " + split_array[i]);
               break;
            }
         }
         
         if(!duplicate)
         {
            result[valid_count] = symbol_name;
            valid_count++;
            
            if(valid_count >= MAX_SYMBOLS)
            {
               Log(LOG_WARNING, "ParseSymbolList", "Reached maximum symbols limit: " + IntegerToString(MAX_SYMBOLS));
               break;
            }
         }
      }
   }

   ArrayResize(result, valid_count);

   if(valid_count == 0)
   {
      ArrayResize(result, 1);
      result[0] = chart_symbol_name;
      Log(LOG_WARNING, "ParseSymbolList", "No valid symbols, using chart symbol");
      return 1;
   }

   Log(LOG_INFO, "ParseSymbolList", "Parsed " + IntegerToString(valid_count) + " symbols");
   for(int i = 0; i < MathMin(valid_count, 10); i++)
   {
      Log(LOG_DEBUG, "ParseSymbolList", "Symbol[" + IntegerToString(i) + "] = " + result[i]);
   }
   
   return valid_count;
}

int GetSymbolIndex(string symbol)
{
   int fast_index = GetSymbolIndexFast(symbol);
   if(fast_index >= 0 && fast_index < g_symbols_count)
      return fast_index;

   for(int i = 0; i < g_symbols_count; i++)
   {
      if(g_symbols[i].name == symbol)
         return i;
   }
   return -1;
}

bool RefreshSymbolCacheBatch(int index)
{
   if(index < 0 || index >= g_symbols_count)
      return false;
   
   string symbol = g_symbols[index].name;
   datetime current_time = TimeCurrent();
   MqlTick latest_tick;
   bool has_tick_info = SymbolInfoTick(symbol, latest_tick);
   long latest_tick_msc = (has_tick_info ? (long)latest_tick.time_msc : 0);
   long tick_time_raw = 0;
   bool has_tick_time = SymbolInfoInteger(symbol, SYMBOL_TIME, tick_time_raw);
   datetime latest_tick_time = (has_tick_time ? (datetime)tick_time_raw : 0);
   if(latest_tick_msc <= 0 && latest_tick_time > 0)
      latest_tick_msc = (long)latest_tick_time * 1000;
   
   // Check cache validity. If a newer tick exists, force a refresh even inside timeout.
   bool cache_age_ok = (g_symbols[index].cache.last_update > 0 &&
                        current_time >= g_symbols[index].cache.last_update &&
                        (current_time - g_symbols[index].cache.last_update) < CACHE_TIMEOUT_SECONDS);
   if(cache_age_ok)
   {
      if((latest_tick_msc > 0 && latest_tick_msc <= g_symbols[index].cache.last_tick_msc) ||
         (latest_tick_msc <= 0 && (!has_tick_time || latest_tick_time <= 0 || latest_tick_time <= g_symbols[index].cache.last_tick_time)))
         return true;
   }
   
   double bid, ask, point;
   long digits_long, spread_long;
   
   // Batch retrieve all properties in a single operation
   if(!SymbolInfoDouble(symbol, SYMBOL_BID, bid) ||
      !SymbolInfoDouble(symbol, SYMBOL_ASK, ask) ||
      !SymbolInfoDouble(symbol, SYMBOL_POINT, point) ||
      !SymbolInfoInteger(symbol, SYMBOL_DIGITS, digits_long) ||
      !SymbolInfoInteger(symbol, SYMBOL_SPREAD, spread_long))
   {
      Log(LOG_WARNING, "RefreshSymbolCacheBatch", "Failed to retrieve symbol info for " + symbol);
      return false;
   }
   
   // Validate data quality (Issue 1.5 also applies here)
   if(bid >= ask || bid <= 0 || ask <= 0 || point <= 0)
   {
      Log(LOG_WARNING, "RefreshSymbolCacheBatch", "Invalid symbol data for " + symbol);
      return false;
   }
   
   // Update cache atomically
   g_symbols[index].cache.bid = bid;
   g_symbols[index].cache.ask = ask;
   g_symbols[index].cache.point = point;
   g_symbols[index].cache.digits = (int)digits_long;
   g_symbols[index].cache.spread = spread_long;
   
   // Update spread EMA (approximate average spread per symbol)
   double spread_points = (double)spread_long;
   if(g_symbols[index].cache.spread_avg_samples <= 0)
   {
      g_symbols[index].cache.spread_avg_points = spread_points;
      g_symbols[index].cache.spread_avg_samples = 1;
   }
   else
   {
      g_symbols[index].cache.spread_avg_points = g_symbols[index].cache.spread_avg_points +
         (SPREAD_EMA_ALPHA * (spread_points - g_symbols[index].cache.spread_avg_points));
      if(g_symbols[index].cache.spread_avg_samples < 1000000)
         g_symbols[index].cache.spread_avg_samples++;
   }
   g_symbols[index].cache.last_update = current_time;
   g_symbols[index].cache.last_tick_time = (latest_tick_time > 0 ? latest_tick_time : current_time);
   g_symbols[index].cache.last_tick_msc = (latest_tick_msc > 0 ? latest_tick_msc : (long)g_symbols[index].cache.last_tick_time * 1000);
   
   // Update metadata for cache maintenance
   g_cache_metadata[index].last_accessed = current_time;
   if(g_cache_metadata[index].access_count < 2147483647)
      g_cache_metadata[index].access_count++;
   
   return true;
}

bool RefreshSymbolCache(int index)
{
   return RefreshSymbolCacheBatch(index);
}

double GetAverageSpreadPoints(string symbol)
{
   int index = GetSymbolIndex(symbol);
   if(index >= 0 && RefreshSymbolCache(index))
   {
      double avg = g_symbols[index].cache.spread_avg_points;
      if(avg > 0.0)
         return avg;
      return (double)g_symbols[index].cache.spread;
   }
   
   long spread;
   if(SymbolInfoInteger(symbol, SYMBOL_SPREAD, spread))
      return (double)spread;
   
   return 0.0;
}

double GetAverageSpreadPrice(string symbol)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return 0.0;
   return GetAverageSpreadPoints(symbol) * point;
}

double GetAverageSpreadPips(string symbol)
{
   return PointsToPips(symbol, GetAverageSpreadPoints(symbol));
}

void InitializeTimeframeNames()
{
   // Issue 2.10: Cache timeframe names to avoid repeated string conversions
   for(int i = 0; i < STRATEGY_TF_SLOTS; i++)
      g_tf_names[i] = EnumToString(GetStrategyTimeframeBySlot(i));
   
   Log(LOG_INFO, "InitializeTimeframeNames", 
       "Cached timeframe names: S=" + g_tf_names[0] + ", P=" + g_tf_names[1] +
       ", C=" + g_tf_names[2] + ", T=" + g_tf_names[3]);
}

int GetSymbolPositionCountLive(string symbol)
{
   if(StringLen(symbol) <= 0)
      return 0;

   // FIX #15: Add retry logic for thread-safe position counting
   // Handle race condition where positions close between iteration and select
   int count = 0;
   int attempts = 0;
   const int MAX_ATTEMPTS = 3;
   
   while(attempts < MAX_ATTEMPTS)
   {
      count = 0;
      bool success = true;
      int total = PositionsTotal();
      
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         
         // Retry select operation if position was just closed
         if(!PositionSelectByTicket(ticket))
         {
            success = false;
            break;  // Position list changed, restart loop
         }

         if(PositionGetString(POSITION_SYMBOL) != symbol)
            continue;

         long pos_magic = PositionGetInteger(POSITION_MAGIC);
         if(pos_magic >= Magic_Base && pos_magic < Magic_Base + 10000)
            count++;
      }
      
      if(success)
         break;  // Successfully iterated without race condition
      
      attempts++;
   }

   return count;
}

int GetSymbolPositionCountCached(string symbol)
{
   int symbol_index = GetSymbolIndex(symbol);
   if(symbol_index < 0 || symbol_index >= MAX_SYMBOLS)
      return 0;
   
   datetime now = TimeCurrent();
   const int POSITION_COUNT_CACHE_SECONDS = 1;
   
   // FIX 2.5: Time-based cache to avoid chart-symbol bar dependency
   if(g_position_count_cache.last_update > 0 &&
      (now - g_position_count_cache.last_update) < POSITION_COUNT_CACHE_SECONDS)
   {
      return g_position_count_cache.count_per_symbol[symbol_index];  // Cache hit - instant return
   }
   
   // Cache miss: recalculate all position counts for this bar
   for(int s = 0; s < MAX_SYMBOLS; s++)
      g_position_count_cache.count_per_symbol[s] = 0;  // Reset counts
   
   int total_positions = PositionsTotal();
   
   // Single pass through all positions - accumulate counts for all symbols
   for(int i = 0; i < total_positions; i++)
   {
      if(IsStopped()) break;
      
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      if(PositionSelectByTicket(ticket))
      {
         string pos_symbol = PositionGetString(POSITION_SYMBOL);
         long pos_magic = PositionGetInteger(POSITION_MAGIC);
         
         if(pos_magic >= Magic_Base && pos_magic < Magic_Base + 10000)
         {
            int pos_symbol_index = GetSymbolIndex(pos_symbol);
            if(pos_symbol_index >= 0 && pos_symbol_index < MAX_SYMBOLS)
               g_position_count_cache.count_per_symbol[pos_symbol_index]++;
         }
      }
   }
   
   // Update cache timestamp
   g_position_count_cache.last_update = now;
   
   // Return cached count for requested symbol
   return g_position_count_cache.count_per_symbol[symbol_index];
}

int GetSymbolPositionCount(string symbol)
{
   return GetSymbolPositionCountCached(symbol);
}

bool InitializeSymbols()
{
   // Release existing handles
   for(int i = 0; i < g_symbols_count; i++)
   {
      if(g_symbols[i].atr_handle != INVALID_HANDLE)
      {
         IndicatorRelease(g_symbols[i].atr_handle);
         g_symbols[i].atr_handle = INVALID_HANDLE;
      }
   }
   
   g_symbols_count = 0;
   g_retry_count = 0;

   string symbols_list[];
   int symbols_count = ParseSymbolList(symbols_list);
   if(symbols_count == 0)
   {
      Log(LOG_ERROR, "InitializeSymbols", "No symbols to initialize");
      return false;
   }

   g_symbols_count = MathMin(symbols_count, MAX_SYMBOLS);

   for(int i = 0; i < g_symbols_count; i++)
   {
      g_symbols[i].name = symbols_list[i];
      g_symbols[i].last_signal_time = 0;
      g_symbols[i].last_bar_time = 0;
      g_symbols[i].last_processed_time = 0;
      g_symbols[i].atr_handle = INVALID_HANDLE;
      g_symbols[i].copying_atr = false;
      g_symbols[i].last_copy_time = 0;
      g_symbols[i].positions_count = 0;
      g_symbols[i].last_position_open = 0;
      
      // Initialize cache
      ArrayResize(g_symbols[i].cache.last_rates, 0);
      g_symbols[i].cache.last_rates_update = 0;
      g_symbols[i].cache.last_rates_bar_time = 0;
      g_symbols[i].cache.last_rates_tf = PERIOD_CURRENT;
      g_symbols[i].cache.last_rates_tick_msc = 0;
      g_symbols[i].cache.last_tick_time = 0;
      g_symbols[i].cache.last_tick_msc = 0;
      g_symbols[i].cache.spread_avg_points = 0.0;
      g_symbols[i].cache.spread_avg_samples = 0;
   }

   return true;
}

void SyncOpenPositionsState()
{
   if(g_symbols_count <= 0)
      return;
   
   // Reset counts and last open times
   for(int i = 0; i < g_symbols_count; i++)
   {
      g_symbols[i].positions_count = 0;
      g_symbols[i].last_position_open = 0;
   }
   
   int total_positions = PositionsTotal();
   int synced = 0;
   
   for(int i = total_positions - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      
      if(!PositionSelectByTicket(ticket))
         continue;
      
      long pos_magic = PositionGetInteger(POSITION_MAGIC);
      if(pos_magic < Magic_Base || pos_magic >= Magic_Base + 10000)
         continue;
      
      string pos_symbol = PositionGetString(POSITION_SYMBOL);
      int symbol_index = GetSymbolIndex(pos_symbol);
      if(symbol_index < 0)
         continue;
      
      g_symbols[symbol_index].positions_count++;
      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
      if(open_time > g_symbols[symbol_index].last_position_open)
         g_symbols[symbol_index].last_position_open = open_time;
      
      synced++;
   }
   
   // Align last_signal_time with last_position_open to enforce cooldown after restart
   for(int i = 0; i < g_symbols_count; i++)
   {
      if(g_symbols[i].last_position_open > g_symbols[i].last_signal_time)
         g_symbols[i].last_signal_time = g_symbols[i].last_position_open;
   }
   
   if(synced > 0)
   {
      Log(LOG_INFO, "SyncOpenPositionsState", 
          "Synced " + IntegerToString(synced) + " open positions to symbol state");
   }
}

// ===== SYMBOL SPREAD CONFIGURATION LOOKUP FUNCTIONS =====

/**
 * Get spread configuration for a specific symbol
 * Falls back to default if symbol not found in config array
 */
SSymbolSpreadConfig GetSymbolSpreadConfig(const string symbol = NULL) {
   string target_symbol = (symbol == NULL || symbol == "") ? Symbol() : symbol;
   
   if(!g_Use_Symbol_Specific_Spreads) {
      // Return generic config when feature disabled
      SSymbolSpreadConfig generic;
      generic.symbol = target_symbol;
      generic.max_spread_pips = g_Max_Spread_Pips_Effective;
      generic.spread_tighten_factor = 1.00;
      generic.use_absolute_limit = false;
      generic.net_spread_limit_pips = 0;
      return generic;
   }
   
   // Search config array for matching symbol
   for(int i = 0; i < ArraySize(g_symbol_spread_config); i++) {
      if(SymbolMatchesSpreadProfile(target_symbol, g_symbol_spread_config[i].symbol)) {
          return g_symbol_spread_config[i];
      }
   }
   
   // Not found in config - return default
   SSymbolSpreadConfig default_config;
   default_config.symbol = target_symbol;
   default_config.max_spread_pips = g_Max_Spread_Pips_Effective;
   default_config.spread_tighten_factor = 1.00;
   default_config.use_absolute_limit = false;
   default_config.net_spread_limit_pips = 0;
   return default_config;
}

/**
 * Get maximum spread in pips for a symbol
 */
int GetSymbolMaxSpreadPips(const string symbol = NULL) {
   SSymbolSpreadConfig config = GetSymbolSpreadConfig(symbol);
   return config.max_spread_pips;
}

/**
 * Get absolute spread limit for a symbol (0 = no limit)
 */
double GetSymbolNetSpreadLimit(const string symbol = NULL) {
   SSymbolSpreadConfig config = GetSymbolSpreadConfig(symbol);
   return config.use_absolute_limit ? config.net_spread_limit_pips : 0;
}

/**
 * Get spread tighten factor for a symbol
 */
double GetSymbolSpreadTightenFactor(const string symbol = NULL) {
   SSymbolSpreadConfig config = GetSymbolSpreadConfig(symbol);
   return config.spread_tighten_factor;
}

#endif // SYMBOL_MANAGEMENT_MQH
