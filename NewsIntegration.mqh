//+------------------------------------------------------------------+
//|                           NewsIntegration.mqh                    |
//|          Economic Calendar Event Integration & Handling           |
//|                        Copyright 2026, ProfitTrailBot Ltd.       |
//|                                                                  |
//| TIER 3: Reduce/pause trading around high-impact news events      |
//+------------------------------------------------------------------+

#ifndef NEWS_INTEGRATION_MQH
#define NEWS_INTEGRATION_MQH

#property copyright "Copyright 2026, ProfitTrailBot Ltd."
#property strict

//====================================================================
// NEWS EVENT IMPACT LEVELS
//====================================================================

enum ENUM_NEWS_IMPACT
{
   NEWS_IMPACT_LOW = 0,      // Minor impact
   NEWS_IMPACT_MEDIUM = 1,   // Moderate impact
   NEWS_IMPACT_HIGH = 2      // Major impact event
};

enum ENUM_ECON_EVENT
{
   EVENT_NFP = 0,                    // Non-Farm Payroll
   EVENT_FOMC_DECISION = 1,          // FOMC interest rate decision
   EVENT_CPI_RELEASE = 2,            // Inflation data
   EVENT_RETAIL_SALES = 3,           // Retail sales
   EVENT_JOBLESS_CLAIMS = 4,         // Weekly jobless claims
   EVENT_GDPDATA = 5,                // GDP figures
   EVENT_BCE_DECISION = 6,           // European Central Bank
   EVENT_BOE_DECISION = 7,           // Bank of England
   EVENT_UNKNOWN = 8
};

struct SNewsEvent
{
   datetime event_time;              // When the event occurs
   string event_name;                // Event description
   ENUM_ECON_EVENT event_type;
   ENUM_NEWS_IMPACT impact_level;
   string affected_currency;         // USD, EUR, GBP, JPY, CAD
   bool is_consensus_beat_expected;  // True if potential major move
   
   SNewsEvent() :
      event_time(0),
      event_name(""),
      event_type(EVENT_UNKNOWN),
      impact_level(NEWS_IMPACT_LOW),
      affected_currency(""),
      is_consensus_beat_expected(false) {}
};

struct SNewsBuffer
{
   // High-impact event upcoming within this buffer
   int minutes_to_event;    // Minutes until next major news
   bool event_within_buffer;
   SNewsEvent upcoming_event;
   
   // Recently passed event
   int minutes_since_event;  // Minutes since last major news
   bool recent_event_passed;
   SNewsEvent recent_event;
   
   SNewsBuffer() :
      minutes_to_event(-1),
      event_within_buffer(false),
      minutes_since_event(-1),
      recent_event_passed(false) {}
};

//====================================================================
// ECONOMIC CALENDAR CACHE
//====================================================================

#define NEWS_CACHE_MAX 128
#define NEWS_CACHE_REFRESH_SECONDS 60

//====================================================================
// NEWS INTEGRATION MODULE
// Provides functions to check for upcoming/recent news events
// and recommend position sizing adjustments
//====================================================================

class CNewsIntegration
{
private:
   // Cached economic calendar events (filtered per-symbol)
   static datetime last_refresh;
   static datetime cache_from;
   static datetime cache_to;
   static string cache_symbol;
   static int cached_count;
   static SNewsEvent cached_events[NEWS_CACHE_MAX];
   static int last_error;
   static datetime last_error_log;
   
   static string NormalizeCurrency(string code)
   {
      string out = code;
      StringToUpper(out);
      if(StringLen(out) > 3)
         out = StringSubstr(out, 0, 3);
      return out;
   }
   
   static bool ExtractSymbolCurrencies(string symbol, string &base, string &quote)
   {
      base = "";
      quote = "";
      
      if(SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE, base))
         base = NormalizeCurrency(base);
      if(SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT, quote))
         quote = NormalizeCurrency(quote);
      
      if(StringLen(base) < 3 || StringLen(quote) < 3)
      {
         if(StringLen(symbol) >= 6)
         {
            base = NormalizeCurrency(StringSubstr(symbol, 0, 3));
            quote = NormalizeCurrency(StringSubstr(symbol, 3, 3));
         }
      }
      
      return (StringLen(base) >= 3 && StringLen(quote) >= 3);
   }
   
   static bool IsCurrencyRelevant(string event_currency, string base, string quote)
   {
      string cur = NormalizeCurrency(event_currency);
      if(StringLen(cur) == 0)
         return false;
      return (cur == base || cur == quote);
   }
   
   static ENUM_NEWS_IMPACT MapCalendarImportance(int importance)
   {
      if(importance >= 2)
         return NEWS_IMPACT_HIGH;
      if(importance == 1)
         return NEWS_IMPACT_MEDIUM;
      return NEWS_IMPACT_LOW;
   }
   
   static ENUM_ECON_EVENT DetectEventType(string name)
   {
      string up = name;
      StringToUpper(up);
      if(StringFind(up, "NON-FARM") >= 0 || StringFind(up, "NONFARM") >= 0 || StringFind(up, "NFP") >= 0)
         return EVENT_NFP;
      if(StringFind(up, "FOMC") >= 0 || StringFind(up, "FED") >= 0 || StringFind(up, "FEDERAL") >= 0)
         return EVENT_FOMC_DECISION;
      if(StringFind(up, "CPI") >= 0 || StringFind(up, "INFLATION") >= 0)
         return EVENT_CPI_RELEASE;
      if(StringFind(up, "RETAIL") >= 0)
         return EVENT_RETAIL_SALES;
      if(StringFind(up, "JOBLESS") >= 0 || StringFind(up, "CLAIMS") >= 0)
         return EVENT_JOBLESS_CLAIMS;
      if(StringFind(up, "GDP") >= 0)
         return EVENT_GDPDATA;
      if(StringFind(up, "ECB") >= 0 || StringFind(up, "BCE") >= 0)
         return EVENT_BCE_DECISION;
      if(StringFind(up, "BOE") >= 0 || StringFind(up, "BANK OF ENGLAND") >= 0)
         return EVENT_BOE_DECISION;
      return EVENT_UNKNOWN;
   }
   
   static bool RefreshCache(datetime now, int buffer_before_minutes, int buffer_after_minutes, string symbol)
   {
      cached_count = 0;
      cache_symbol = symbol;
      
      int before = (buffer_before_minutes > 0 ? buffer_before_minutes : 0);
      int after = (buffer_after_minutes > 0 ? buffer_after_minutes : 0);
      cache_from = now - (datetime)(before * 60);
      cache_to = now + (datetime)(after * 60);
      if(cache_to <= cache_from)
         cache_to = cache_from + 60;
      
      MqlCalendarValue values[];
      ResetLastError();
      int total = CalendarValueHistory(values, cache_from, cache_to);
      int err = GetLastError();
      last_error = err;
      last_refresh = now;
      
      if(total <= 0)
      {
         if(err != 0 && (last_error_log == 0 || (now - last_error_log) >= 300))
         {
            Log(LOG_WARNING, "NewsIntegration",
                "Economic calendar unavailable (err=" + IntegerToString(err) +
                "). Tier 3C will be bypassed until data is available.");
            last_error_log = now;
         }
         return false;
      }
      
      string base = "", quote = "";
      bool filter_by_symbol = (StringLen(symbol) > 0 && ExtractSymbolCurrencies(symbol, base, quote));
      
      for(int i = 0; i < total && cached_count < NEWS_CACHE_MAX; i++)
      {
         MqlCalendarEvent ev;
         ResetLastError();
         CalendarEventById(values[i].event_id, ev);
         if(GetLastError() != 0)
            continue;
         
         string name_upper = ev.name;
         StringToUpper(name_upper);
         ENUM_ECON_EVENT event_type = DetectEventType(ev.name);
         bool relevant = true;
         if(filter_by_symbol)
         {
            relevant = false;
            if(StringFind(name_upper, base) >= 0 || StringFind(name_upper, quote) >= 0)
               relevant = true;
            
            if(!relevant)
            {
               if(event_type == EVENT_FOMC_DECISION || event_type == EVENT_NFP ||
                  event_type == EVENT_CPI_RELEASE || event_type == EVENT_RETAIL_SALES ||
                  event_type == EVENT_JOBLESS_CLAIMS || event_type == EVENT_GDPDATA)
               {
                  relevant = (base == "USD" || quote == "USD");
               }
               else if(event_type == EVENT_BCE_DECISION)
               {
                  relevant = (base == "EUR" || quote == "EUR");
               }
               else if(event_type == EVENT_BOE_DECISION)
               {
                  relevant = (base == "GBP" || quote == "GBP");
               }
            }
         }
         if(!relevant)
            continue;
         
         ENUM_NEWS_IMPACT impact = MapCalendarImportance((int)ev.importance);
         if(impact == NEWS_IMPACT_LOW)
            continue;
         
         SNewsEvent news;
         news.event_time = values[i].time;
         news.event_name = ev.name;
         news.event_type = event_type;
         news.impact_level = impact;
         news.affected_currency = "";
         news.is_consensus_beat_expected = false;
         
         cached_events[cached_count++] = news;
      }
      
      return (cached_count > 0);
   }
    
public:
   // Check if trading should be cautious due to upcoming news
   static SNewsBuffer CheckNewsBuffer(datetime current_time, 
                                      int buffer_before_minutes = 30,
                                      int buffer_after_minutes = 5,
                                      string symbol = "")
   {
      SNewsBuffer buffer;
      
      if(buffer_before_minutes < 0)
         buffer_before_minutes = 0;
      if(buffer_after_minutes < 0)
         buffer_after_minutes = 0;
      
      bool need_refresh = false;
      if(last_refresh == 0)
         need_refresh = true;
      else if((current_time - last_refresh) >= NEWS_CACHE_REFRESH_SECONDS)
         need_refresh = true;
      else if(current_time < cache_from || current_time > cache_to)
         need_refresh = true;
      else if(symbol != cache_symbol)
         need_refresh = true;
      
      if(need_refresh)
         RefreshCache(current_time, buffer_before_minutes, buffer_after_minutes, symbol);
      
      if(cached_count <= 0)
         return buffer;
      
      // Scan cached events
      for(int i = 0; i < cached_count; i++)
      {
         if(cached_events[i].event_time <= 0)
            continue;
         
         int minutes_diff = (int)((cached_events[i].event_time - current_time) / 60);
         
         // Check if event is within pre-event buffer
         if(minutes_diff > 0 && minutes_diff <= buffer_before_minutes)
         {
            if(!buffer.event_within_buffer ||
               minutes_diff < buffer.minutes_to_event ||
               (minutes_diff == buffer.minutes_to_event &&
                cached_events[i].impact_level > buffer.upcoming_event.impact_level))
            {
               buffer.minutes_to_event = minutes_diff;
               buffer.event_within_buffer = true;
               buffer.upcoming_event = cached_events[i];
            }
         }
         
         // Check if event recently passed
         if(minutes_diff < 0 && minutes_diff >= -buffer_after_minutes)
         {
            int minutes_since = -minutes_diff;
            if(!buffer.recent_event_passed ||
               minutes_since < buffer.minutes_since_event ||
               (minutes_since == buffer.minutes_since_event &&
                cached_events[i].impact_level > buffer.recent_event.impact_level))
            {
               buffer.minutes_since_event = minutes_since;
               buffer.recent_event_passed = true;
               buffer.recent_event = cached_events[i];
            }
         }
      }
      
      return buffer;
   }
   
   // Get position size adjustment based on news proximity
   static double GetNewsPositionSizeAdjustment(const SNewsBuffer &buffer)
   {
      // If high-impact event imminent: reduce size significantly
      if(buffer.event_within_buffer && 
         buffer.upcoming_event.impact_level == NEWS_IMPACT_HIGH)
      {
         if(buffer.minutes_to_event <= 5)
            return 0.3;    // 70% reduction (3 mins before)
         else if(buffer.minutes_to_event <= 15)
            return 0.6;    // 40% reduction
         else if(buffer.minutes_to_event <= 30)
            return 0.8;    // 20% reduction
      }
      else if(buffer.event_within_buffer && 
              buffer.upcoming_event.impact_level == NEWS_IMPACT_MEDIUM)
      {
         return 0.85;      // 15% reduction for medium impact
      }
      
      // Just passed high-impact event: still cautious for 5 mins
      if(buffer.recent_event_passed && 
         buffer.recent_event.impact_level == NEWS_IMPACT_HIGH &&
         buffer.minutes_since_event <= 5)
      {
         return 0.5;       // 50% reduction
      }
      
      return 1.0;         // Normal sizing
   }
   
   // Recommend halt/pause trading completely
   static bool ShouldHaltTradingForNews(const SNewsBuffer &buffer)
   {
      // Halt 10 minutes before NFP or FOMC
      if(buffer.event_within_buffer && buffer.minutes_to_event <= 10)
      {
         if(buffer.upcoming_event.event_type == EVENT_NFP ||
            buffer.upcoming_event.event_type == EVENT_FOMC_DECISION)
            return true;
      }
      
      // Halt 3 minutes after NFP/FOMC
      if(buffer.recent_event_passed && buffer.minutes_since_event <= 3)
      {
         if(buffer.recent_event.event_type == EVENT_NFP ||
            buffer.recent_event.event_type == EVENT_FOMC_DECISION)
            return true;
      }
      
      return false;
   }

};

// Static member initialization
datetime CNewsIntegration::last_refresh = 0;
datetime CNewsIntegration::cache_from = 0;
datetime CNewsIntegration::cache_to = 0;
string CNewsIntegration::cache_symbol = "";
int CNewsIntegration::cached_count = 0;
SNewsEvent CNewsIntegration::cached_events[NEWS_CACHE_MAX];
int CNewsIntegration::last_error = 0;
datetime CNewsIntegration::last_error_log = 0;

#endif // NEWS_INTEGRATION_MQH
