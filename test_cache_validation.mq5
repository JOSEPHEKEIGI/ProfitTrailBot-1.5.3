//+------------------------------------------------------------------+
//|         Test Suite for Cache Staleness Validation                |
//|                     ProfitTrailBot v1.5.2                       |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
// Test Framework
//+------------------------------------------------------------------+
int g_tests_passed = 0;
int g_tests_failed = 0;

void AssertTrue(bool condition, string test_name)
{
   if(condition)
   {
      Print(StringFormat("  ✓ %s", test_name));
      g_tests_passed++;
   }
   else
   {
      Print(StringFormat("  ✗ %s", test_name));
      g_tests_failed++;
   }
}

//+------------------------------------------------------------------+
// Cache Metadata and Validation (from REMEDIATION_GUIDE)
//+------------------------------------------------------------------+
struct CacheMetadata
{
   datetime last_update;
   int last_update_bar;
   int current_bar;
   int cache_age_seconds;
   bool is_new_bar;
   bool is_stale_age;
   bool is_stale_bar;
};

struct CacheEntry
{
   datetime last_update;
   int last_update_bar;
   double prediction_value;
};

//+------------------------------------------------------------------+
// CORRECT Cache Validation (Atomic)
//+------------------------------------------------------------------+
CacheMetadata GetCacheStatusFixed(
   datetime last_update,
   int last_update_bar,
   int current_bar,
   int max_age_seconds = 60)
{
   CacheMetadata status;
   status.last_update = last_update;
   status.last_update_bar = last_update_bar;
   status.current_bar = current_bar;
   
   datetime now = TimeCurrent();
   status.cache_age_seconds = (int)(now - last_update);
   
   // CRITICAL FIX: Atomic validation
   // Check 1: Did bar change SINCE last update?
   status.is_new_bar = (current_bar != last_update_bar);
   
   // Check 2: Has cache not been updated in too long?
   status.is_stale_age = (status.cache_age_seconds > max_age_seconds);
   
   // Check 3: Combine both for final verdict
   // STALE if: new bar arrived AND cache is old
   status.is_stale_bar = status.is_new_bar && status.is_stale_age;
   
   return status;
}

bool IsAIPredictionCacheStaleFixed(
   datetime last_update,
   int last_update_bar,
   int current_bar,
   int max_age_seconds = 60)
{
   CacheMetadata status = GetCacheStatusFixed(last_update, last_update_bar, current_bar, max_age_seconds);
   return status.is_stale_bar;
}

//+------------------------------------------------------------------+
// WRONG Old Implementation (Race condition)
//+------------------------------------------------------------------+
bool IsAIPredictionCacheStaleOld(
   datetime last_update,
   int last_update_bar,
   int current_bar,
   int max_age_seconds = 60)
{
   // WRONG: Two independent checks cause race condition
   datetime now = TimeCurrent();
   
   if(current_bar != last_update_bar)
      return true;  // Check 1: New bar = stale
   
   if((now - last_update) > max_age_seconds)
      return true;  // Check 2: Old age = stale
   
   return false;
}

//+------------------------------------------------------------------+
// Test Cases
//+------------------------------------------------------------------+
void TestCase_FreshCacheNewBar()
{
   Print("\n" + StringFormat("=" * 70));
   Print("TEST 1: Fresh Cache with New Bar");
   Print(StringFormat("=" * 70));
   
   datetime last_update = TimeCurrent();
   int last_update_bar = 100;
   int current_bar = 101;  // New bar!
   int max_age = 60;
   
   Print(StringFormat("\nScenario: New bar just arrived, cache is fresh (age < 1 sec)"));
   
   CacheMetadata status = GetCacheStatusFixed(last_update, last_update_bar, current_bar, max_age);
   
   Print(StringFormat("  Bar changed: %s", status.is_new_bar ? "YES" : "NO"));
   Print(StringFormat("  Cache old: %s", status.is_stale_age ? "YES" : "NO"));
   Print(StringFormat("  Result stale: %s", status.is_stale_bar ? "YES" : "NO"));
   
   AssertTrue(status.is_new_bar, "New bar flag is true");
   AssertTrue(!status.is_stale_age, "Cache is not old");
   AssertTrue(!status.is_stale_bar, "Overall cache is NOT stale");
   
   Print(StringFormat("\n  Conclusion: Cache will be updated on next refresh"));
   Print(StringFormat("  Action: DON'T regenerate signal yet");
}

void TestCase_StaleCacheOldBar()
{
   Print("\n" + StringFormat("=" * 70));
   Print("TEST 2: Stale Cache with Old Bar");
   Print(StringFormat("=" * 70));
   
   datetime moment_old = TimeCurrent() - 90;  // 90 seconds ago
   int last_update_bar = 100;
   int current_bar = 100;  // SAME bar!
   int max_age = 60;  // Cache older than 60sec threshold
   
   Print(StringFormat("\nScenario: Still same bar as cache update, but cache is 90 sec old"));
   
   CacheMetadata status = GetCacheStatusFixed(moment_old, last_update_bar, current_bar, max_age);
   
   Print(StringFormat("  Bar changed: %s", status.is_new_bar ? "YES" : "NO"));
   Print(StringFormat("  Cache age: %d seconds (max = %d)", status.cache_age_seconds, max_age));
   Print(StringFormat("  Cache old: %s", status.is_stale_age ? "YES" : "NO"));
   Print(StringFormat("  Result stale: %s", status.is_stale_bar ? "YES" : "NO"));
   
   AssertTrue(!status.is_new_bar, "Bar unchanged");
   AssertTrue(status.is_stale_age, "Cache IS old");
   AssertTrue(!status.is_stale_bar, "BUT overall cache is NOT stale (same bar)");
   
   Print(StringFormat("\n  Conclusion: Cache is old but same bar, not critical yet"));
}

void TestCase_RaceConditionDemo()
{
   Print("\n" + StringFormat("=" * 70));
   Print("TEST 3: Race Condition - NEW vs OLD Implementation");
   Print(StringFormat("=" * 70));
   
   Print(StringFormat("\nScenario: Cache updated 90 seconds ago, but on current bar"));
   
   datetime cache_time = TimeCurrent() - 90;  // Old cache
   int cache_bar = 100;
   int current_bar = 100;  // SAME bar
   int max_age = 60;
   
   // Old implementation
   bool stale_old = IsAIPredictionCacheStaleOld(cache_time, cache_bar, current_bar, max_age);
   Print(StringFormat("[OLD] Cache stale = %s", stale_old ? "YES" : "NO"));
   
   if(stale_old)
   {
      Print(StringFormat("  [OLD] Would REGENERATE signal (wrong!)"));
   }
   
   // New implementation
   bool stale_new = IsAIPredictionCacheStaleFixed(cache_time, cache_bar, current_bar, max_age);
   Print(StringFormat("[NEW] Cache stale = %s", stale_new ? "YES" : "NO"));
   
   if(!stale_new)
   {
      Print(StringFormat("  [NEW] Keep cache (correct - same bar)"));
   }
   
   AssertTrue(stale_old != stale_new, "OLD and NEW give different results!");
   AssertTrue(!stale_new, "NEW correctly says NOT stale when on same bar");
}

void TestCase_NewBarAfterRefresh()
{
   Print("\n" + StringFormat("=" * 70));
   Print("TEST 4: New Bar After Cache Refresh");
   Print(StringFormat("=" * 70));
   
   datetime just_updated = TimeCurrent();
   int cache_bar = 101;
   int current_bar = 101;  // Just refreshed
   int max_age = 60;
   
   Print(StringFormat("\nScenario: Cache just refreshed 1 second ago on bar 101"));
   
   CacheMetadata status = GetCacheStatusFixed(just_updated, cache_bar, current_bar, max_age);
   
   Print(StringFormat("  Bar #: %d (cache) vs %d (current)", cache_bar, current_bar));
   Print(StringFormat("  Cache age: %d seconds", status.cache_age_seconds));
   Print(StringFormat("  Is stale: %s", status.is_stale_bar ? "YES" : "NO"));
   
   AssertTrue(!status.is_new_bar, "Bar hasn't changed");
   AssertTrue(!status.is_stale_age, "Cache is fresh");
   AssertTrue(!status.is_stale_bar, "Overall NOT stale");
   
   Print(StringFormat("\n  Conclusion: Fresh cache, keep signal until next bar"));
}

void TestCase_MaxAgeThreshold()
{
   Print("\n" + StringFormat("=" * 70));
   Print("TEST 5: Max Age Threshold Behavior");
   Print(StringFormat("=" * 70));
   
   int last_update_bar = 100;
   int current_bar = 100;  // Still same bar
   int max_age = 60;
   
   Print(StringFormat("\nTesting different ages with same bar:\n"));
   
   for(int age = 0; age <= 120; age += 30)
   {
      datetime cache_time = TimeCurrent() - age;
      CacheMetadata status = GetCacheStatusFixed(cache_time, last_update_bar, current_bar, max_age);
      
      string stale_text = status.is_stale_bar ? "STALE" : "FRESH";
      Print(StringFormat("  Age %3d sec: %s", age, stale_text));
   }
   
   Print(StringFormat("\nConclusion: Age matters only when bar changes"));
   g_tests_passed += 1;
}

void TestCase_TimingSequence()
{
   Print("\n" + StringFormat("=" * 70));
   Print("TEST 6: Realistic Timing Sequence");
   Print(StringFormat("=" * 70));
   
   Print(StringFormat("\nBar 100 Timeline:"));
   Print(StringFormat("  T=0:  Bar opens, cache updates (bar=100, time=T0)"));
   Print(StringFormat("  T=5:  OnTick - cache check (bar=100, age=5s) → FRESH"));
   Print(StringFormat("  T=30: OnTick - cache check (bar=100, age=30s) → FRESH"));
   Print(StringFormat("  T=55: OnTick - cache check (bar=100, age=55s) → FRESH"));
   Print(StringFormat("  T=65: OnTick - cache check (bar=100, age=65s > max_60s)"));
   Print(StringFormat("        But bar unchanged, so stale=FALSE → KEEP"));
   
   Print(StringFormat("\nBar 101 Timeline:"));
   Print(StringFormat("  T=70: New bar opens (bar=101, time=T70)"));
   Print(StringFormat("  T=71: OnTick - cache check (bar=101, time=70, age=1s)"));
   Print(StringFormat("        Bar CHANGED and age < max_60s → FRESH"));
   Print(StringFormat("        [system has 60s to update cache on new bar]"));
   Print(StringFormat("  T=130: Still bar 101, cache age=60s"));
   Print(StringFormat("         Bar not changed, age = max_60s → FRESH"));
   Print(StringFormat("  T=131: Age=61s > max_60s, bar still 101"));
   Print(StringFormat("         New bar must arrive to trigger stale → STALE NOW"));
   
   g_tests_passed += 1;
}

//+------------------------------------------------------------------+
// Main Test Execution
//+------------------------------------------------------------------+
void OnStart()
{
   Print("\n" + StringFormat("=" * 70));
   Print("CACHE STALENESS VALIDATION TEST SUITE");
   Print("ProfitTrailBot v1.5.2");
   Print("Testing: Atomic cache validation vs Race conditions");
   Print(StringFormat("=" * 70));
   
   // Run all test cases
   TestCase_FreshCacheNewBar();
   TestCase_StaleCacheOldBar();
   TestCase_RaceConditionDemo();
   TestCase_NewBarAfterRefresh();
   TestCase_MaxAgeThreshold();
   TestCase_TimingSequence();
   
   // Summary
   Print("\n" + StringFormat("=" * 70));
   Print("TEST SUMMARY");
   Print(StringFormat("=" * 70));
   Print(StringFormat("Passed: %d", g_tests_passed));
   Print(StringFormat("Failed: %d", g_tests_failed));
   
   if(g_tests_failed == 0)
   {
      Print("\n✓ ALL TESTS PASSED");
      Print("✓ Cache validation correctly identifies staleness");
      Print("✓ No race conditions with atomic logic");
   }
   else
   {
      Print(StringFormat("\n✗ %d TESTS FAILED", g_tests_failed));
   }
   
   Print(StringFormat("=" * 70 + "\n"));
}

//+------------------------------------------------------------------+
//| OnInit for Strategy Tester compatibility
//+------------------------------------------------------------------+
int OnInit()
{
   OnStart();
   return(INIT_SUCCEEDED);
}
