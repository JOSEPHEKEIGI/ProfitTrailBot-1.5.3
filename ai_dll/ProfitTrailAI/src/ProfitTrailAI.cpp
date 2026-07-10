#include <windows.h>
#include <cstdint>
#include <mutex>
#include <vector>
#include <string>

using BoosterHandle = void*;

static BoosterHandle g_booster[2] = { nullptr, nullptr };
static std::string g_last_error;

static HMODULE g_lightgbm = nullptr;
static std::mutex g_lightgbm_mutex;

using LGBM_BoosterCreateFromModelfile_t = int(__cdecl *)(const char*, int*, BoosterHandle*);
using LGBM_BoosterFree_t = int(__cdecl *)(BoosterHandle);
using LGBM_BoosterPredictForMat_t = int(__cdecl *)(BoosterHandle, const void*, int, int32_t, int32_t, int, int, int, int, const char*, int64_t*, double*);
using LGBM_BoosterFeatureImportance_t = int(__cdecl *)(BoosterHandle, int, int, double*);
using LGBM_BoosterGetNumClasses_t = int(__cdecl *)(BoosterHandle, int*);

static LGBM_BoosterCreateFromModelfile_t pLGBM_BoosterCreateFromModelfile = nullptr;
static LGBM_BoosterFree_t pLGBM_BoosterFree = nullptr;
static LGBM_BoosterPredictForMat_t pLGBM_BoosterPredictForMat = nullptr;
static LGBM_BoosterFeatureImportance_t pLGBM_BoosterFeatureImportance = nullptr;
static LGBM_BoosterGetNumClasses_t pLGBM_BoosterGetNumClasses = nullptr;

static std::wstring GetModuleDir()
{
   HMODULE mod = nullptr;
   if(!GetModuleHandleExW(
      GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
      (LPCWSTR)&GetModuleDir,
      &mod))
   {
      return L"";
   }

   wchar_t path[MAX_PATH] = {0};
   DWORD len = GetModuleFileNameW(mod, path, MAX_PATH);
   if(len == 0 || len >= MAX_PATH)
      return L"";

   std::wstring full(path, len);
   size_t pos = full.find_last_of(L"\\/"); 
   if(pos == std::wstring::npos)
      return L"";

   return full.substr(0, pos + 1);
}

static bool LightGBMLoaded()
{
   return (g_lightgbm != nullptr &&
           pLGBM_BoosterCreateFromModelfile != nullptr &&
           pLGBM_BoosterFree != nullptr &&
           pLGBM_BoosterPredictForMat != nullptr &&
           pLGBM_BoosterFeatureImportance != nullptr &&
           pLGBM_BoosterGetNumClasses != nullptr);
}

static void ResetLightGBM()
{
   if(g_lightgbm != nullptr)
      FreeLibrary(g_lightgbm);
   g_lightgbm = nullptr;
   pLGBM_BoosterCreateFromModelfile = nullptr;
   pLGBM_BoosterFree = nullptr;
   pLGBM_BoosterPredictForMat = nullptr;
   pLGBM_BoosterFeatureImportance = nullptr;
   pLGBM_BoosterGetNumClasses = nullptr;
}

static bool EnsureLightGBMLoaded()
{
   if(LightGBMLoaded())
      return true;

   std::lock_guard<std::mutex> lock(g_lightgbm_mutex);
   if(LightGBMLoaded())
      return true;

   ResetLightGBM();

   std::wstring dll_path = GetModuleDir() + L"lib_lightgbm.dll";
   g_lightgbm = LoadLibraryW(dll_path.c_str());
   if(g_lightgbm == nullptr)
      g_lightgbm = LoadLibraryW(L"lib_lightgbm.dll");

   if(g_lightgbm == nullptr)
   {
      g_last_error = "LoadLibraryW(lib_lightgbm.dll) failed";
      return false;
   }

   pLGBM_BoosterCreateFromModelfile =
      (LGBM_BoosterCreateFromModelfile_t)GetProcAddress(g_lightgbm, "LGBM_BoosterCreateFromModelfile");
   pLGBM_BoosterFree =
      (LGBM_BoosterFree_t)GetProcAddress(g_lightgbm, "LGBM_BoosterFree");
   pLGBM_BoosterPredictForMat =
      (LGBM_BoosterPredictForMat_t)GetProcAddress(g_lightgbm, "LGBM_BoosterPredictForMat");
   pLGBM_BoosterFeatureImportance =
      (LGBM_BoosterFeatureImportance_t)GetProcAddress(g_lightgbm, "LGBM_BoosterFeatureImportance");
   pLGBM_BoosterGetNumClasses =
      (LGBM_BoosterGetNumClasses_t)GetProcAddress(g_lightgbm, "LGBM_BoosterGetNumClasses");

   if(!LightGBMLoaded())
   {
      g_last_error = "GetProcAddress(LightGBM C API) failed";
      ResetLightGBM();
      return false;
   }

   return true;
}

static int GetNumClasses(BoosterHandle booster)
{
   if(booster == nullptr)
      return 1;
   if(!EnsureLightGBMLoaded() || pLGBM_BoosterGetNumClasses == nullptr)
      return 1;

   int out = 1;
   int status = pLGBM_BoosterGetNumClasses(booster, &out);
   if(status != 0 || out <= 0)
      return 1;
   return out;
}

static bool WideToUtf8(const wchar_t* w, std::string &out)
{
   if(w == nullptr)
      return false;

   int len = WideCharToMultiByte(CP_UTF8, 0, w, -1, nullptr, 0, nullptr, nullptr);
   if(len <= 0)
      return false;

   out.resize((size_t)len);
   WideCharToMultiByte(CP_UTF8, 0, w, -1, &out[0], len, nullptr, nullptr);
   return true;
}

static constexpr int C_API_DTYPE_FLOAT64 = 1;
static constexpr int C_API_PREDICT_NORMAL = 0;

extern "C" __declspec(dllexport) int PTB_LoadModelSlot(const wchar_t* model_path, int slot)
{
   if(model_path == nullptr)
      return 0;
   if(slot < 0 || slot > 1)
      return 0;
   if(!EnsureLightGBMLoaded())
      return 0;

   std::string utf8_path;
   if(!WideToUtf8(model_path, utf8_path))
      return 0;

   int num_iterations = 0;
   BoosterHandle new_booster = nullptr;
   int status = pLGBM_BoosterCreateFromModelfile(utf8_path.c_str(), &num_iterations, &new_booster);
   if(status != 0 || new_booster == nullptr)
   {
      g_last_error = "LGBM_BoosterCreateFromModelfile failed";
      if(new_booster != nullptr)
         pLGBM_BoosterFree(new_booster);
      return 0;
   }

   if(g_booster[slot] != nullptr)
      pLGBM_BoosterFree(g_booster[slot]);
   g_booster[slot] = new_booster;
   g_last_error.clear();
   return 1;
}

extern "C" __declspec(dllexport) double PTB_PredictSlot(const double* features, int feature_count, int slot)
{
   if(slot < 0 || slot > 1)
      return 0.5;
   if(g_booster[slot] == nullptr || features == nullptr || feature_count <= 0)
      return 0.5;
   if(!EnsureLightGBMLoaded())
      return 0.5;

   int num_classes = GetNumClasses(g_booster[slot]);
   if(num_classes != 1)
      return 0.5;

   double out_result = 0.5;
   int64_t out_len = 0;

   int status = pLGBM_BoosterPredictForMat(
      g_booster[slot],
      features,
      C_API_DTYPE_FLOAT64,
      1,
      feature_count,
      1,
      C_API_PREDICT_NORMAL,
      0,
      -1,
      "",
      &out_len,
      &out_result
   );

   if(status != 0 || out_len <= 0)
      return 0.5;

   if(out_result < 0.0) return 0.0;
   if(out_result > 1.0) return 1.0;
   return out_result;
}

extern "C" __declspec(dllexport) int PTB_PredictMulti(const double* features, int feature_count, double* out_probs, int out_count, int slot)
{
   if(slot < 0 || slot > 1)
      return 0;
   if(g_booster[slot] == nullptr || features == nullptr || out_probs == nullptr || out_count <= 0 || feature_count <= 0)
      return 0;
   if(!EnsureLightGBMLoaded())
      return 0;

   int num_classes = GetNumClasses(g_booster[slot]);
   if(num_classes <= 1)
      return 0;

   std::vector<double> tmp((size_t)num_classes);
   int64_t out_len = 0;
   int status = pLGBM_BoosterPredictForMat(
      g_booster[slot],
      features,
      C_API_DTYPE_FLOAT64,
      1,
      feature_count,
      1,
      C_API_PREDICT_NORMAL,
      0,
      -1,
      "",
      &out_len,
      tmp.data()
   );

   if(status != 0 || out_len <= 0 || out_len < out_count)
      return 0;

   for(int i = 0; i < out_count; i++)
      out_probs[i] = tmp[(size_t)i];

   return 1;
}

extern "C" __declspec(dllexport) int PTB_GetFeatureImportance(double* out_values, int out_count, int slot)
{
   if(slot < 0 || slot > 1)
      return 0;
   if(g_booster[slot] == nullptr || out_values == nullptr || out_count <= 0)
      return 0;
   if(!EnsureLightGBMLoaded())
      return 0;

   int status = pLGBM_BoosterFeatureImportance(
      g_booster[slot],
      -1,
      1,
      out_values
   );

   if(status != 0)
      return 0;
   return 1;
}

extern "C" __declspec(dllexport) void PTB_FreeModelSlot(int slot)
{
   if(slot < 0 || slot > 1)
      return;
   if(g_booster[slot] != nullptr)
   {
      if(EnsureLightGBMLoaded() && pLGBM_BoosterFree != nullptr)
         pLGBM_BoosterFree(g_booster[slot]);
      g_booster[slot] = nullptr;
   }
}
