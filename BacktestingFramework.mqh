//+------------------------------------------------------------------+
//|                           BacktestingFramework.mqh               |
//|          Walk-Forward & Out-of-Sample Backtesting Support        |
//|                        Copyright 2026, ProfitTrailBot Ltd.       |
//|                                                                  |
//| TIER 3: Backtesting framework for in-sample/out-of-sample val   |
//+------------------------------------------------------------------+

#ifndef BACKTESTING_FRAMEWORK_MQH
#define BACKTESTING_FRAMEWORK_MQH

#property copyright "Copyright 2026, ProfitTrailBot Ltd."
#property strict

//====================================================================
// BACKTESTING FRAMEWORK
// Tracks win rate, Sharpe ratio, and performance across different
// sample periods (in-sample vs. out-of-sample)
//====================================================================

struct SBacktestPeriod
{
   datetime period_start;
   datetime period_end;
   string period_label;    // "IS_20240101-20240228" or "OOS_20240301-20240331"
   
   int total_trades;
   int winning_trades;
   int losing_trades;
   double total_pnl;
   double max_drawdown;
   double sharpe_ratio;
   
   double win_rate;        // winning_trades / total_trades
   double profit_factor;   // sum(wins) / sum(losses)
   
   // Extended metrics for institutional-grade tracking
   double gross_profit;
   double gross_loss;
   double equity_curve;
   double equity_peak;
   double return_mean;
   double return_m2;
   int    return_count;
   
   SBacktestPeriod() :
      period_start(0),
      period_end(0),
      period_label(""),
      total_trades(0),
      winning_trades(0),
      losing_trades(0),
      total_pnl(0.0),
      max_drawdown(0.0),
      sharpe_ratio(0.0),
      win_rate(0.0),
      profit_factor(0.0),
      gross_profit(0.0),
      gross_loss(0.0),
      equity_curve(0.0),
      equity_peak(0.0),
      return_mean(0.0),
      return_m2(0.0),
      return_count(0) {}
};

struct SWalkForwardSplit
{
   // In-sample period
   int is_bars;            // Number of bars for in-sample
   datetime is_start;
   datetime is_end;
   
   // Out-of-sample period
   int oos_bars;           // Number of bars for out-of-sample
   datetime oos_start;
   datetime oos_end;
   
   // Test results
   SBacktestPeriod is_results;
   SBacktestPeriod oos_results;
   
   // Degradation metrics
   double oos_to_is_win_rate_degradation;  // % change oos vs is
   double oos_to_is_sharpe_degradation;
};

class CBacktestingFramework
{
public:
   // Record a completed trade for backtest metrics
   static void RecordTradeForBacktest(SBacktestPeriod &period,
                                        double profit_loss,
                                        bool is_winning_trade,
                                        double return_value = 0.0)
   {
      period.total_trades++;
      period.total_pnl += profit_loss;
      
      const double NEUTRAL_EPS = 0.01;
      bool neutral_trade = (MathAbs(profit_loss) <= NEUTRAL_EPS);
      if(!neutral_trade)
      {
         if(is_winning_trade)
         {
            period.winning_trades++;
            if(profit_loss > 0.0)
               period.gross_profit += profit_loss;
         }
         else
         {
            period.losing_trades++;
            if(profit_loss < 0.0)
               period.gross_loss += MathAbs(profit_loss);
         }
      }
      
      // Update win rate (exclude neutral exits)
      int effective_trades = period.winning_trades + period.losing_trades;
      if(effective_trades > 0)
         period.win_rate = (double)period.winning_trades / effective_trades;
      else
         period.win_rate = 0.0;
      
      // Update profit factor (avoid divide-by-zero)
      if(period.gross_loss > 0.0)
         period.profit_factor = period.gross_profit / period.gross_loss;
      else if(period.gross_profit > 0.0)
         period.profit_factor = period.gross_profit;
      
      // Update equity curve and drawdown
      period.equity_curve += profit_loss;
      if(period.equity_curve > period.equity_peak)
         period.equity_peak = period.equity_curve;
      double dd = period.equity_peak - period.equity_curve;
      if(dd > period.max_drawdown)
         period.max_drawdown = dd;
      
      // Incremental Sharpe (Welford)
      period.return_count++;
      double delta = return_value - period.return_mean;
      period.return_mean += (period.return_count > 0 ? delta / period.return_count : 0.0);
      double delta2 = return_value - period.return_mean;
      period.return_m2 += delta * delta2;
      if(period.return_count > 1)
      {
         double variance = period.return_m2 / (period.return_count - 1);
         double std_dev = (variance > 0.0 ? MathSqrt(variance) : 0.0);
         period.sharpe_ratio = (std_dev > 0.0 ? period.return_mean / std_dev : 0.0);
      }
      else
      {
         period.sharpe_ratio = 0.0;
      }
   }
   
   // Calculate Sharpe ratio from PnL array
   static double CalculateSharpeRatio(const double &returns[])
   {
      if(ArraySize(returns) < 2)
         return 0.0;
      
      // Calculate mean
      double sum = 0.0;
      for(int i = 0; i < ArraySize(returns); i++)
         sum += returns[i];
      double mean = sum / ArraySize(returns);
      
      // Calculate standard deviation
      double variance = 0.0;
      for(int i = 0; i < ArraySize(returns); i++)
      {
         double diff = returns[i] - mean;
         variance += diff * diff;
      }
      variance /= ArraySize(returns);
      double std_dev = MathSqrt(variance);
      
      if(std_dev <= 0.0)
         return 0.0;
      
      // Sharpe = mean / std_dev (assuming risk-free rate = 0)
      return mean / std_dev;
   }
   
   // Evaluate walk-forward split degradation
   static void EvaluateWalkForwardDegradation(SWalkForwardSplit &split)
   {
      if(split.is_results.win_rate > 0.0)
         split.oos_to_is_win_rate_degradation = 
            ((split.oos_results.win_rate - split.is_results.win_rate) / 
             split.is_results.win_rate) * 100.0;
      
      if(split.is_results.sharpe_ratio > 0.0)
         split.oos_to_is_sharpe_degradation = 
            ((split.oos_results.sharpe_ratio - split.is_results.sharpe_ratio) / 
             split.is_results.sharpe_ratio) * 100.0;
      
      // Log results
      Log(LOG_INFO, "WalkForward", 
          "IS: WR=" + DoubleToString(split.is_results.win_rate * 100, 1) + "% " +
          "Sharpe=" + DoubleToString(split.is_results.sharpe_ratio, 2) + " | " +
          "OOS: WR=" + DoubleToString(split.oos_results.win_rate * 100, 1) + "% " +
          "Sharpe=" + DoubleToString(split.oos_results.sharpe_ratio, 2));
      
      Log(LOG_INFO, "WalkForward",
          "Degradation: WR=" + DoubleToString(split.oos_to_is_win_rate_degradation, 1) + "% " +
          "Sharpe=" + DoubleToString(split.oos_to_is_sharpe_degradation, 1) + "%");
   }
};

#endif // BACKTESTING_FRAMEWORK_MQH
