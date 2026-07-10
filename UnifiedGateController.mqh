#ifndef UNIFIED_GATE_CONTROLLER_MQH
#define UNIFIED_GATE_CONTROLLER_MQH

//+------------------------------------------------------------------+
//| Unified Gate Controller - Synchronizes all execution gates      |
//| FIX #4: Ensures consistent gate state across all modules        |
//+------------------------------------------------------------------+

struct SGateState
{
   bool master_enabled;              // Master kill switch
   bool spread_enabled;              // Spread filter enabled
   bool session_enabled;             // Session time filters enabled
   bool exposure_enabled;            // Position exposure limits enabled
   bool daily_limit_enabled;         // Daily trade count limit enabled
   bool drawdown_enabled;            // Drawdown circuit breakers enabled
   bool structural_gates_enabled;    // ICT structural gates (FVG, BOS, OB)
   
   SGateState() : 
      master_enabled(true),
      spread_enabled(true),
      session_enabled(true),
      exposure_enabled(true),
      daily_limit_enabled(true),
      drawdown_enabled(true),
      structural_gates_enabled(true)
   {}
};

class CGateController
{
public:
   static SGateState current_state;
   
private:
   static datetime last_state_update;
   static int state_change_count;
   
public:
   // Apply runtime-configured optional gate states while keeping critical gate FLAGS enabled.
   // This is the live runtime path. It is distinct from SetMasterGateState(false), which is a
   // test/diagnostic hard stop that blocks execution while preserving critical-gate state for inspection.
   static void ApplyRuntimeGateState(bool spread_enabled,
                                     bool session_enabled,
                                     bool exposure_enabled,
                                     bool structural_enabled,
                                     string context = "")
   {
      bool changed = (!current_state.master_enabled ||
                      current_state.spread_enabled != spread_enabled ||
                      current_state.session_enabled != session_enabled ||
                      current_state.exposure_enabled != exposure_enabled ||
                      current_state.structural_gates_enabled != structural_enabled ||
                      !current_state.daily_limit_enabled ||
                      !current_state.drawdown_enabled);

      current_state.master_enabled = true;
      current_state.spread_enabled = spread_enabled;
      current_state.session_enabled = session_enabled;
      current_state.exposure_enabled = exposure_enabled;
      current_state.structural_gates_enabled = structural_enabled;
      current_state.daily_limit_enabled = true;
      current_state.drawdown_enabled = true;

      if(changed)
      {
         last_state_update = TimeCurrent();
         state_change_count++;

         string reason = (StringLen(context) > 0 ? context : "runtime");
         Log(LOG_INFO, "GateController",
             "Runtime gate sync applied from " + reason + ": " + GetGateStateSummary());
      }
   }

   // Query master gate status
   static bool IsMasterGateEnabled()
   {
      return current_state.master_enabled;
   }
   
   // Query individual gates
   static bool IsSpreadGateEnabled()
   {
      return current_state.master_enabled && current_state.spread_enabled;
   }
   
   static bool IsSessionGateEnabled()
   {
      return current_state.master_enabled && current_state.session_enabled;
   }
   
   static bool IsExposureGateEnabled()
   {
      return current_state.master_enabled && current_state.exposure_enabled;
   }
   
   static bool IsDailyLimitGateEnabled()
   {
      // Controller flag remains ON by design. Live bypass, when configured, is handled via
      // effective runtime limits rather than by disabling this flag.
      return current_state.daily_limit_enabled;
   }
   
   static bool IsDrawdownGateEnabled()
   {
      // Controller flag remains ON by design. Runtime drawdown bypass is handled outside this
      // state flag in diagnostics / master-bypass flows.
      return current_state.drawdown_enabled;
   }
   
   static bool IsStructuralGateEnabled()
   {
      return current_state.master_enabled && current_state.structural_gates_enabled;
   }
   
   // Set master gate state.
   // `false` is a hard stop used by tests/diagnostics: execution is blocked, while critical-gate
   // state remains visible as enabled for assertions and telemetry.
   static void SetMasterGateState(bool enable)
   {
      if(!enable)
      {
         // Hard-stop execution while leaving critical gate flags ON for diagnostics/tests.
         Log(LOG_WARNING, "GateController", 
             "Master gate HARD STOP active - execution blocked, critical gate flags preserved");
         current_state.master_enabled = false;
         current_state.spread_enabled = false;
         current_state.session_enabled = false;
         current_state.exposure_enabled = false;
         current_state.structural_gates_enabled = false;
         // Keep daily_limit_enabled = true for state inspection/assertions.
         // Keep drawdown_enabled = true for state inspection/assertions.
      }
      else
      {
         // When ENABLING: Restore all gates
         Log(LOG_INFO, "GateController", "Master gate ENABLED - All gates restored");
         current_state.master_enabled = true;
         current_state.spread_enabled = true;
         current_state.session_enabled = true;
         current_state.exposure_enabled = true;
         current_state.structural_gates_enabled = true;
         current_state.daily_limit_enabled = true;
         current_state.drawdown_enabled = true;
      }
      last_state_update = TimeCurrent();
      state_change_count++;
   }
   
   // Set all optional gates (respects critical gate enforcement)
   static void SetAllOptionalGates(bool enable)
   {
      if(current_state.master_enabled)
      {
         current_state.spread_enabled = enable;
         current_state.session_enabled = enable;
         current_state.exposure_enabled = enable;
         current_state.structural_gates_enabled = enable;
         
         Log(LOG_INFO, "GateController", 
             StringFormat("All optional gates set to %s (Master=ON)", 
                         enable ? "ENABLED" : "DISABLED"));
         last_state_update = TimeCurrent();
         state_change_count++;
      }
   }
   
   // Unified permission check for trade execution
   static bool CanExecuteTrade(string symbol, string context = "")
   {
      // Check 1: Master hard-stop
      if(!current_state.master_enabled)
      {
         Log(LOG_WARNING, "GateController", 
             "Trade blocked - master hard stop active for " + symbol);
         return false;
      }
      
      // Check 2: Daily limit (ALWAYS enforced)
      if(!current_state.daily_limit_enabled || 
         g_trades_today >= g_Max_Trades_Per_Day_Effective)
      {
         return false;  // Daily limit logic handles its own alert
      }
      
      // Check 3: Drawdown circuit breakers (ALWAYS enforced)
      if(!current_state.drawdown_enabled)
      {
         Log(LOG_WARNING, "GateController", 
             "Trade blocked - Drawdown circuit breaker triggered");
         return false;
      }
      
      // If context provided, log approval
      if(context != "")
      {
         Log(LOG_DEBUG, "GateController", 
             StringFormat("Trade APPROVED for %s: %s", symbol, context));
      }
      
      return true;
   }
   
   // Get current gate-state summary. Daily/DD entries reflect controller state flags,
   // not the full set of effective runtime limits after diagnostics/master-bypass policy.
   static string GetGateStateSummary()
   {
      return StringFormat(
         "GateState[Master=%s Spread=%s Session=%s Exposure=%s Daily=%s(FLAG) DD=%s(FLAG) Struct=%s]",
         current_state.master_enabled ? "ON" : "OFF",
         current_state.spread_enabled ? "ON" : "OFF",
         current_state.session_enabled ? "ON" : "OFF",
         current_state.exposure_enabled ? "ON" : "OFF",
         current_state.daily_limit_enabled ? "ON" : "OFF",
         current_state.drawdown_enabled ? "ON" : "OFF",
         current_state.structural_gates_enabled ? "ON" : "OFF"
      );
   }
   
   // Reset to default state
   static void ResetToDefaults()
   {
      current_state = SGateState();
      last_state_update = TimeCurrent();
      state_change_count = 0;
      Log(LOG_INFO, "GateController", "Gate state reset to defaults");
   }
   
   // Diagnostic info
   static int GetStateChangeCount()
   {
      return state_change_count;
   }
   
   static datetime GetLastStateUpdate()
   {
      return last_state_update;
   }
};

//+------------------------------------------------------------------+
//| Test Gate Manager - Enables per-test gate configuration          |
//| Saves/restores gate state for isolated test execution            |
//+------------------------------------------------------------------+

class CGateTestManager
{
private:
   static SGateState saved_state;
   static bool state_saved;
   
public:
   // Save current gate configuration for later restoration
   static void SaveGateState()
   {
      saved_state = CGateController::current_state;
      state_saved = true;
      Log(LOG_DEBUG, "GateTestManager", "Gate state saved: " + CGateController::GetGateStateSummary());
   }
   
   // Restore previously saved gate configuration
   static void RestoreGateState()
   {
      if(!state_saved)
      {
         Log(LOG_WARNING, "GateTestManager", "Attempted to restore without prior save");
         return;
      }
      CGateController::current_state = saved_state;
      state_saved = false;
      Log(LOG_DEBUG, "GateTestManager", "Gate state restored: " + CGateController::GetGateStateSummary());
   }
   
   // Run test segment with all gates enabled
   static void TestSegmentWithGatesEnabled(string segment_name)
   {
      Log(LOG_INFO, "GateTestManager", 
          StringFormat("TEST SEGMENT START (Gates ENABLED): %s", segment_name));
      CGateController::ResetToDefaults();
      CGateController::SetAllOptionalGates(true);
   }
   
   // Run test segment with all optional gates disabled (but critical gates still enforced)
   static void TestSegmentWithOptionalGatesDisabled(string segment_name)
   {
      Log(LOG_INFO, "GateTestManager", 
          StringFormat("TEST SEGMENT START (Optional Gates DISABLED): %s", segment_name));
      CGateController::ResetToDefaults();
      CGateController::SetAllOptionalGates(false);
   }
   
    // Run test segment with master gate disabled.
    // Execution is blocked, but critical-gate flags remain enabled for state assertions.
    static void TestSegmentWithMasterGateDisabled(string segment_name)
    {
       Log(LOG_INFO, "GateTestManager", 
           StringFormat("TEST SEGMENT START (Master Gate HARD STOP): %s", segment_name));
       CGateController::SetMasterGateState(false);
    }
   
   // Run test segment with full gate restoration (production mode)
   static void TestSegmentWithFullGateRestoration(string segment_name)
   {
      Log(LOG_INFO, "GateTestManager", 
          StringFormat("TEST SEGMENT START (Full Gates ENABLED): %s", segment_name));
      RestoreGateState();
   }
   
   // Check if gates are currently enabled
   static string GetCurrentGateConfiguration()
   {
      return CGateController::GetGateStateSummary();
   }
};

// Static member initialization for CGateTestManager
SGateState CGateTestManager::saved_state;
bool CGateTestManager::state_saved = false;

// Static member initialization
SGateState CGateController::current_state;
datetime CGateController::last_state_update = 0;
int CGateController::state_change_count = 0;

#endif
