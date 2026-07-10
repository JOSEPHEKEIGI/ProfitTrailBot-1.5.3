//+------------------------------------------------------------------+
//| Test Suite for Position Array Dynamic Growth                     |
//| ProfitTrailBot v1.5.2                                            |
//+------------------------------------------------------------------+
#property strict

int g_tests_passed = 0;
int g_tests_failed = 0;

#define POSITION_TRACKER_INITIAL_CAPACITY 32
#define POSITION_TRACKER_GROWTH_FACTOR 2

void AssertTrue(bool condition, string test_name)
{
   if(condition)
   {
      Print(StringFormat("[PASS] %s", test_name));
      g_tests_passed++;
   }
   else
   {
      Print(StringFormat("[FAIL] %s", test_name));
      g_tests_failed++;
   }
}

void AssertEqual(int actual, int expected, string test_name)
{
   if(actual == expected)
   {
      Print(StringFormat("[PASS] %s (%d == %d)", test_name, actual, expected));
      g_tests_passed++;
   }
   else
   {
      Print(StringFormat("[FAIL] %s (got %d, expected %d)", test_name, actual, expected));
      g_tests_failed++;
   }
}

void AssertDoubleEqual(double actual, double expected, double tolerance, string test_name)
{
   if(MathAbs(actual - expected) <= tolerance)
   {
      Print(StringFormat("[PASS] %s (%.2f ~= %.2f)", test_name, actual, expected));
      g_tests_passed++;
   }
   else
   {
      Print(StringFormat("[FAIL] %s (got %.2f, expected %.2f)", test_name, actual, expected));
      g_tests_failed++;
   }
}

string MakeDivider(int length)
{
   string divider = "";
   for(int i = 0; i < length; i++)
      divider += "=";
   return divider;
}

class PositionTracker
{
private:
   ulong pos_ids[];
   double pos_pnl[];
   int pos_count;
   int max_capacity;

public:
   PositionTracker()
   {
      pos_count = 0;
      max_capacity = POSITION_TRACKER_INITIAL_CAPACITY;
      ArrayResize(pos_ids, max_capacity);
      ArrayResize(pos_pnl, max_capacity);
      Print(StringFormat("[PositionTracker] Initialized with capacity %d", max_capacity));
   }

   ~PositionTracker()
   {
      ArrayFree(pos_ids);
      ArrayFree(pos_pnl);
   }

   bool AddPosition(ulong ticket, double pnl)
   {
      if(pos_count >= max_capacity)
      {
         int new_capacity = max_capacity * POSITION_TRACKER_GROWTH_FACTOR;

         if(ArrayResize(pos_ids, new_capacity) != new_capacity)
         {
            Print(StringFormat("[ERROR] Failed to grow ticket array to %d", new_capacity));
            return false;
         }

         if(ArrayResize(pos_pnl, new_capacity) != new_capacity)
         {
            Print(StringFormat("[ERROR] Failed to grow pnl array to %d", new_capacity));
            return false;
         }

         int old_capacity = max_capacity;
         max_capacity = new_capacity;
         Print(StringFormat("[PositionTracker] Grew capacity: %d -> %d", old_capacity, max_capacity));
      }

      pos_ids[pos_count] = ticket;
      pos_pnl[pos_count] = pnl;
      pos_count++;
      return true;
   }

   bool GetPosition(int index, ulong &ticket, double &pnl)
   {
      if(index < 0 || index >= pos_count)
         return false;

      ticket = pos_ids[index];
      pnl = pos_pnl[index];
      return true;
   }

   bool RemovePosition(int index)
   {
      if(index < 0 || index >= pos_count)
         return false;

      for(int i = index; i < pos_count - 1; i++)
      {
         pos_ids[i] = pos_ids[i + 1];
         pos_pnl[i] = pos_pnl[i + 1];
      }

      pos_count--;
      return true;
   }

   int GetCount()
   {
      return pos_count;
   }

   double GetTotalPnL()
   {
      double total = 0.0;
      for(int i = 0; i < pos_count; i++)
         total += pos_pnl[i];
      return total;
   }

   void Clear()
   {
      pos_count = 0;
   }

   int GetCapacity()
   {
      return max_capacity;
   }
};

class PositionTrackerOld
{
private:
   ulong pos_ids[256];
   double pos_pnl[256];
   int pos_count;

public:
   PositionTrackerOld()
   {
      pos_count = 0;
      Print("[PositionTrackerOld] Initialized with fixed capacity 256");
   }

   bool AddPosition(ulong ticket, double pnl)
   {
      if(pos_count >= 256)
      {
         Print("[ERROR-OLD] Position array full at 256");
         return false;
      }

      pos_ids[pos_count] = ticket;
      pos_pnl[pos_count] = pnl;
      pos_count++;
      return true;
   }

   int GetCount()
   {
      return pos_count;
   }
};

void TestCase_AddPositions()
{
   Print("\n" + MakeDivider(60));
   Print("TEST 1: Add 100 Positions");
   Print(MakeDivider(60));

   PositionTracker tracker;
   int growth_events = 0;

   for(int i = 0; i < 100; i++)
   {
      int capacity_before = tracker.GetCapacity();
      bool success = tracker.AddPosition((ulong)(1000000 + i), 10.0 + (i % 5));
      int capacity_after = tracker.GetCapacity();

      if(capacity_after > capacity_before)
         growth_events++;

      if(!success)
      {
         AssertTrue(false, StringFormat("Could not add position %d", i));
         return;
      }
   }

   Print(StringFormat("Array grew %d times during the test", growth_events));
   AssertEqual(tracker.GetCount(), 100, "Position count is 100");
   AssertTrue(tracker.GetCapacity() >= 100, "Capacity grew to fit all positions");
}

void TestCase_GetPositions()
{
   Print("\n" + MakeDivider(60));
   Print("TEST 2: Add and Retrieve Positions");
   Print(MakeDivider(60));

   PositionTracker tracker;
   for(int i = 0; i < 50; i++)
      tracker.AddPosition((ulong)(2000000 + i), 25.5 + i);

   bool all_verified = true;
   for(int i = 0; i < 50; i++)
   {
      ulong ticket = 0;
      double pnl = 0.0;

      if(!tracker.GetPosition(i, ticket, pnl))
      {
         all_verified = false;
         break;
      }

      if(ticket != (ulong)(2000000 + i) || MathAbs(pnl - (25.5 + i)) > 0.0001)
      {
         all_verified = false;
         break;
      }
   }

   AssertTrue(all_verified, "All 50 positions retrieved correctly");
}

void TestCase_TotalPnL()
{
   Print("\n" + MakeDivider(60));
   Print("TEST 3: Calculate Total PnL");
   Print(MakeDivider(60));

   PositionTracker tracker;
   double expected_total = 0.0;

   for(int i = 0; i < 10; i++)
   {
      double pnl = 10.0 * (i + 1);
      tracker.AddPosition((ulong)(3000000 + i), pnl);
      expected_total += pnl;
   }

   double actual_total = tracker.GetTotalPnL();
   AssertDoubleEqual(actual_total, expected_total, 0.01, "Total PnL is correct");
}

void TestCase_RemovePositions()
{
   Print("\n" + MakeDivider(60));
   Print("TEST 4: Remove Positions");
   Print(MakeDivider(60));

   PositionTracker tracker;
   for(int i = 0; i < 10; i++)
      tracker.AddPosition((ulong)(4000000 + i), 5.0);

   bool removed = tracker.RemovePosition(5);
   AssertTrue(removed, "Position removal succeeded");
   AssertEqual(tracker.GetCount(), 9, "Count is now 9");

   ulong ticket = 0;
   double pnl = 0.0;
   bool shifted = tracker.GetPosition(5, ticket, pnl) && ticket == (ulong)4000006;
   AssertTrue(shifted, "Positions shift down after removal");
}

void TestCase_CompareOldVsNew()
{
   Print("\n" + MakeDivider(60));
   Print("TEST 5: Compare OLD (Fixed 256) vs NEW (Dynamic)");
   Print(MakeDivider(60));

   PositionTracker tracker_new;
   int success_new = 0;
   for(int i = 0; i < 300; i++)
   {
      if(tracker_new.AddPosition((ulong)(5000000 + i), 1.0))
         success_new++;
   }

   PositionTrackerOld tracker_old;
   int success_old = 0;
   for(int i = 0; i < 300; i++)
   {
      if(tracker_old.AddPosition((ulong)(5000000 + i), 1.0))
         success_old++;
   }

   Print(StringFormat("NEW tracker stored %d/300 positions", success_new));
   Print(StringFormat("OLD tracker stored %d/300 positions", success_old));

   AssertTrue(tracker_new.GetCount() == 300, "NEW tracker stores all 300 positions");
   AssertTrue(tracker_old.GetCount() == 256, "OLD tracker stops at 256 positions");
}

void TestCase_OverflowRisk()
{
   Print("\n" + MakeDivider(60));
   Print("TEST 6: Overflow Safety");
   Print(MakeDivider(60));

   PositionTracker tracker;
   bool all_added = true;

   for(int i = 0; i < 500; i++)
   {
      if(!tracker.AddPosition((ulong)(6000000 + i), 1.0))
      {
         all_added = false;
         break;
      }
   }

   AssertTrue(all_added, "Dynamic tracker stores 500 positions without overflow");
   AssertEqual(tracker.GetCount(), 500, "All 500 positions are tracked");
   AssertTrue(tracker.GetCapacity() >= 500, "Capacity expanded to fit 500 positions");
}

void OnStart()
{
   Print("\n" + MakeDivider(70));
   Print("POSITION ARRAY DYNAMIC GROWTH TEST SUITE");
   Print("ProfitTrailBot v1.5.2");
   Print("Testing: fixed 256-element array vs dynamic growth");
   Print(MakeDivider(70));

   TestCase_AddPositions();
   TestCase_GetPositions();
   TestCase_TotalPnL();
   TestCase_RemovePositions();
   TestCase_CompareOldVsNew();
   TestCase_OverflowRisk();

   Print("\n" + MakeDivider(70));
   Print("TEST SUMMARY");
   Print(MakeDivider(70));
   Print(StringFormat("Passed: %d", g_tests_passed));
   Print(StringFormat("Failed: %d", g_tests_failed));

   if(g_tests_failed == 0)
   {
      Print("\n[PASS] ALL TESTS PASSED");
      Print("[PASS] Dynamic position tracking is working");
   }
   else
   {
      Print(StringFormat("\n[FAIL] %d TESTS FAILED", g_tests_failed));
   }

   Print(MakeDivider(70) + "\n");
}
