#ifndef AI_SCALER_MQH
#define AI_SCALER_MQH

double g_ai_scaler_mean[15];
double g_ai_scaler_std[15];
bool g_ai_scaler_ready = false;
const double AI_SCALER_MIN_STD = 1e-8;

bool LoadAIScaler(string filename)
{
   int base_flags = FILE_READ | FILE_CSV | FILE_ANSI;
   short csv_delimiter = ',';
   int handle = FileOpen(filename, base_flags, csv_delimiter);
   bool used_common = false;
   if(handle == INVALID_HANDLE)
   {
      handle = FileOpen(filename, base_flags | FILE_COMMON, csv_delimiter);
      if(handle != INVALID_HANDLE)
         used_common = true;
   }
   if(handle == INVALID_HANDLE)
   {
      Log(LOG_WARNING, "LoadAIScaler", "Scaler file not found: " + filename);
      return false;
   }
   
   double tmp_mean[15];
   double tmp_std[15];
   int idx = 0;
   uint start_time = GetTickCount();
   const uint FILE_TIMEOUT_MS = 5000;  // 5 second timeout for file reading
   
   while(!FileIsEnding(handle) && idx < 15)
   {
      // FIX #12: Add timeout protection for corrupted/slow files
      if((GetTickCount() - start_time) > FILE_TIMEOUT_MS)
      {
         FileClose(handle);
         Log(LOG_ERROR, "LoadAIScaler", "Scaler file read TIMEOUT after " + IntegerToString(idx) + " rows");
         return false;
      }
      
      string mean_str = FileReadString(handle);
      string std_str = FileReadString(handle);
      if(StringLen(mean_str) == 0 || StringLen(std_str) == 0)
         break;

      double mean_v = StringToDouble(mean_str);
      double std_v = StringToDouble(std_str);
      if(!MathIsValidNumber(mean_v) || !MathIsValidNumber(std_v))
      {
         FileClose(handle);
         Log(LOG_WARNING, "LoadAIScaler", "Scaler contains invalid numeric values");
         return false;
      }

      tmp_mean[idx] = mean_v;
      tmp_std[idx] = std_v;
      if(tmp_std[idx] <= AI_SCALER_MIN_STD)
         tmp_std[idx] = 1.0;
      
      idx++;
   }
   
   FileClose(handle);
   
   if(idx < 15)
   {
      Log(LOG_WARNING, "LoadAIScaler", "Scaler file incomplete, loaded " + IntegerToString(idx) + " rows");
      return false;
   }
   
   for(int i = 0; i < 15; i++)
   {
      g_ai_scaler_mean[i] = tmp_mean[i];
      g_ai_scaler_std[i] = tmp_std[i];
   }

   Log(LOG_INFO, "LoadAIScaler", "Scaler loaded: " + filename + (used_common ? " (COMMON)" : ""));
   return true;
}

void ApplyAIScaler(double &features[], int count)
{
   if(!Enable_AI_Scaler || !g_ai_scaler_ready)
      return;
   
   int n = MathMin(count, 15);
   for(int i = 0; i < n; i++)
   {
      double stdv = g_ai_scaler_std[i];
      if(stdv <= AI_SCALER_MIN_STD) stdv = 1.0;
      features[i] = (features[i] - g_ai_scaler_mean[i]) / stdv;
   }
}

#endif // AI_SCALER_MQH
