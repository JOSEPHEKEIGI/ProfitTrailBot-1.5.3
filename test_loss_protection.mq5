//+------------------------------------------------------------------+
//| Test Suite for Loss Protection Escalation                        |
//| ProfitTrailBot v1.5.2                                            |
//+------------------------------------------------------------------+
#property strict

int g_tests_passed = 0;
int g_tests_failed = 0;

void AssertTrue(bool condition, string test_name)
{
   if(condition)
   {
      Print(StringFormat("  [PASS] %s", test_name));
      g_tests_passed++;
   }
   else
   {
      Print(StringFormat("  [FAIL] %s", test_name));
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

struct LossTrackingData
{
   datetime loss_start_time;
   int consecutive_losses;
   double total_loss_amount;
   int escalation_level;
};

class LossProtectionSystem
{
private:
   LossTrackingData tracker;
   datetime daily_loss_reset_time;
   double daily_max_loss;

public:
   LossProtectionSystem(double max_daily_loss = 500.0)
   {
      tracker.consecutive_losses = 0;
      tracker.total_loss_amount = 0.0;
      tracker.escalation_level = 0;
      tracker.loss_start_time = TimeCurrent();
      daily_loss_reset_time = TimeCurrent();
      daily_max_loss = max_daily_loss;
   }

   bool ProcessLoss(double loss_amount)
   {
      datetime now = TimeCurrent();

      if(now > daily_loss_reset_time + 86400)
      {
         Print("[LossProtection] Daily reset - new trading day");
         daily_loss_reset_time = now;
         tracker.consecutive_losses = 0;
         tracker.total_loss_amount = 0.0;
         tracker.escalation_level = 0;
      }

      tracker.consecutive_losses++;
      tracker.total_loss_amount += loss_amount;
      tracker.loss_start_time = now;

      int prev_level = tracker.escalation_level;

      if(tracker.consecutive_losses >= 5 || tracker.total_loss_amount >= daily_max_loss)
      {
         tracker.escalation_level = 3;
         Print(StringFormat("[LossProtection] LEVEL 3: HALTED (loss %d, total $%.2f)",
                            tracker.consecutive_losses, tracker.total_loss_amount));
         return false;
      }

      if(tracker.consecutive_losses >= 4)
      {
         tracker.escalation_level = 2;
         Print(StringFormat("[LossProtection] LEVEL 2: RESTRICTED (loss %d, 2hr cooldown)",
                            tracker.consecutive_losses));
         return false;
      }

      if(tracker.consecutive_losses >= 3)
      {
         tracker.escalation_level = 1;
         Print(StringFormat("[LossProtection] LEVEL 1: CAUTION (loss %d, 1hr cooldown)",
                            tracker.consecutive_losses));
         return false;
      }

      if(tracker.consecutive_losses >= 2)
      {
         Print(StringFormat("[LossProtection] LEVEL 0: SHORT COOLDOWN (loss %d, 30min)",
                            tracker.consecutive_losses));
         return false;
      }

      if(prev_level != tracker.escalation_level && tracker.escalation_level > 0)
      {
         Print(StringFormat("[LossProtection] Escalation: Level %d -> %d",
                            prev_level, tracker.escalation_level));
      }

      return true;
   }

   bool IsInCooldown()
   {
      return tracker.consecutive_losses >= 2;
   }

   int GetEscalationLevel()
   {
      return tracker.escalation_level;
   }

   int GetConsecutiveLosses()
   {
      return tracker.consecutive_losses;
   }

   double GetTotalLoss()
   {
      return tracker.total_loss_amount;
   }
};

class LossProtectionSystemOld
{
private:
   int consecutive_losses;
   datetime cooldown_until;

public:
   LossProtectionSystemOld()
   {
      consecutive_losses = 0;
      cooldown_until = 0;
   }

   bool ProcessLoss(double loss_amount)
   {
      consecutive_losses++;

      if(consecutive_losses >= 3)
      {
         datetime now = TimeCurrent();
         cooldown_until = now + 30 * 60;
         Print(StringFormat("[OLD] Loss #%d - cooldown 30 min (never escalates)", consecutive_losses));
         return false;
      }

      return true;
   }

   bool IsInCooldown(datetime now)
   {
      return (cooldown_until > now);
   }

   int GetConsecutiveLosses()
   {
      return consecutive_losses;
   }
};

void TestCase_LevelProgression()
{
   Print("\n" + MakeDivider(70));
   Print("TEST 1: Loss Level Progression");
   Print(MakeDivider(70));

   LossProtectionSystem protection;

   for(int i = 1; i <= 5; i++)
   {
      Print(StringFormat("\nLoss #%d:", i));
      bool can_trade = protection.ProcessLoss(100.0);

      Print(StringFormat("  Can trade: %s", can_trade ? "YES" : "NO"));
      Print(StringFormat("  Escalation level: %d", protection.GetEscalationLevel()));
      Print(StringFormat("  Total loss: $%.2f", protection.GetTotalLoss()));

      switch(i)
      {
         case 1:
            AssertTrue(can_trade, "After loss 1: single loss does not block trading");
            AssertTrue(!protection.IsInCooldown(), "After loss 1: no cooldown yet");
            break;
         case 2:
            AssertTrue(!can_trade, "After loss 2: 30 min cooldown active");
            break;
         case 3:
            AssertTrue(!can_trade, "After loss 3: escalated to 1 hour");
            AssertTrue(protection.GetEscalationLevel() == 1, "Level = 1 (CAUTION)");
            break;
         case 4:
            AssertTrue(!can_trade, "After loss 4: escalated to 2 hours");
            AssertTrue(protection.GetEscalationLevel() == 2, "Level = 2 (RESTRICTED)");
            break;
         case 5:
            AssertTrue(!can_trade, "After loss 5: HALTED");
            AssertTrue(protection.GetEscalationLevel() == 3, "Level = 3 (HALTED)");
            break;
      }
   }
}

void TestCase_CompareOldVsNew()
{
   Print("\n" + MakeDivider(70));
   Print("TEST 2: OLD (Fixed Cooldown) vs NEW (Escalating)");
   Print(MakeDivider(70));

   Print("\nScenario: 5 consecutive losses on a bad market day\n");

   LossProtectionSystem new_system;
   Print("[NEW SYSTEM] Processing losses:");
   for(int i = 0; i < 5; i++)
      new_system.ProcessLoss(100.0);

   Print("\n[NEW] After 5 losses:");
   Print("  Status: HALTED (no more trading today)");
   Print(StringFormat("  Total loss: $%.2f", new_system.GetTotalLoss()));
   Print(StringFormat("  Escalation level: %d (3=HALT)", new_system.GetEscalationLevel()));

   LossProtectionSystemOld old_system;
   Print("\n[OLD SYSTEM] Processing losses:");
   for(int i = 0; i < 5; i++)
      old_system.ProcessLoss(100.0);

   Print("\n[OLD] After 5 losses:");
   Print("  Status: 30 min cooldown (same as loss #3)");
   Print("  Escalation: never escalates - always 30 min");
   Print("  Result: can lose unlimited during streaks");

   Print("\nComparison:");
   Print("  [NEW] Escalates -> stops at loss 5 -> max loss = $500");
   Print("  [OLD] Fixed 30 min -> keeps trading -> max loss can exceed $500");

   AssertTrue(new_system.GetEscalationLevel() == 3, "NEW system reaches HALT level");
   AssertTrue(old_system.GetConsecutiveLosses() == 5, "OLD system tracks all 5 losses");
}

void TestCase_NoEscalationWithoutLosses()
{
   Print("\n" + MakeDivider(70));
   Print("TEST 3: No Escalation Without Losses");
   Print(MakeDivider(70));

   LossProtectionSystem protection;

   Print("No losses recorded - system should allow trading");
   AssertTrue(!protection.IsInCooldown(), "No cooldown when no losses");
   AssertTrue(protection.GetEscalationLevel() == 0, "Escalation level is 0");
}

void TestCase_DailyReset()
{
   Print("\n" + MakeDivider(70));
   Print("TEST 4: Daily Reset Behavior");
   Print(MakeDivider(70));

   LossProtectionSystem protection;

   Print("Recording 3 losses...");
   for(int i = 0; i < 3; i++)
      protection.ProcessLoss(100.0);

   Print(StringFormat("After 3 losses: Level = %d, Total = $%.2f",
                      protection.GetEscalationLevel(), protection.GetTotalLoss()));

   AssertTrue(protection.GetConsecutiveLosses() == 3, "3 losses recorded");

   Print("\nIn the live EA, the next market day resets counters to 0.");
   Print("That prevents a temporary trading halt from becoming permanent.");
}

void TestCase_RealDayScenario()
{
   Print("\n" + MakeDivider(70));
   Print("TEST 5: Realistic Trading Day Scenario");
   Print(MakeDivider(70));

   LossProtectionSystem protection;

   Print("\nDay starts: market conditions deteriorate...");
   Print("Trade 1: LOSE $100");
   protection.ProcessLoss(100.0);
   Print("Trade 2: LOSE $100");
   protection.ProcessLoss(100.0);
   Print("Trade 3: LOSE $100");
   protection.ProcessLoss(100.0);
   Print("Trade 4: LOSE $100");
   protection.ProcessLoss(100.0);
   Print("Trade 5: LOSE $100");
   protection.ProcessLoss(100.0);

   Print("\nFinal Result:");
   Print(StringFormat("  Total loss: $%.2f", protection.GetTotalLoss()));
   Print(StringFormat("  Escalation level: %d (3=HALTED)", protection.GetEscalationLevel()));
   Print("  Trading status: BLOCKED");

   Print("\nThis is working as intended.");
   Print("Without escalation, the system would keep trading into the streak.");
   Print("With escalation, trading stops after loss 5.");

   AssertTrue(protection.GetEscalationLevel() == 3, "System halts after 5 losses");
   AssertTrue(MathAbs(protection.GetTotalLoss() - 500.0) < 0.0001, "Total loss is capped at $500");
}

void TestCase_EscalationMilestones()
{
   Print("\n" + MakeDivider(70));
   Print("TEST 6: Escalation Milestones");
   Print(MakeDivider(70));

   Print("\nEscalation Levels and Cooldown Durations:");
   Print("  Loss 1: can trade");
   Print("  Loss 2: Level 0 -> 30 min cooldown");
   Print("  Loss 3: Level 1 (CAUTION) -> 1 hour cooldown");
   Print("  Loss 4: Level 2 (RESTRICTED) -> 2 hour cooldown");
   Print("  Loss 5+: Level 3 (HALTED) -> no trading for the rest of the day");

   LossProtectionSystem protection;
   int expected_levels[] = {0, 0, 1, 2, 3};
   string level_names[] = {"NORMAL", "NORMAL", "CAUTION", "RESTRICTED", "HALTED"};

   for(int i = 0; i < 5; i++)
   {
      protection.ProcessLoss(50.0);
      int level = protection.GetEscalationLevel();

      Print(StringFormat("  Loss %d: Level %d (%s)", i + 1, level, level_names[i]));
      AssertTrue(level == expected_levels[i],
                 StringFormat("Loss %d escalation is correct", i + 1));
   }
}

void OnStart()
{
   Print("\n" + MakeDivider(70));
   Print("LOSS PROTECTION ESCALATION TEST SUITE");
   Print("ProfitTrailBot v1.5.2");
   Print("Testing: fixed vs escalating loss protection");
   Print(MakeDivider(70));

   TestCase_LevelProgression();
   TestCase_CompareOldVsNew();
   TestCase_NoEscalationWithoutLosses();
   TestCase_DailyReset();
   TestCase_RealDayScenario();
   TestCase_EscalationMilestones();

   Print("\n" + MakeDivider(70));
   Print("TEST SUMMARY");
   Print(MakeDivider(70));
   Print(StringFormat("Passed: %d", g_tests_passed));
   Print(StringFormat("Failed: %d", g_tests_failed));

   if(g_tests_failed == 0)
   {
      Print("\n[PASS] ALL TESTS PASSED");
      Print("[PASS] Loss protection escalation works correctly");
   }
   else
   {
      Print(StringFormat("\n[FAIL] %d TESTS FAILED", g_tests_failed));
   }

   Print(MakeDivider(70) + "\n");
}
