//+------------------------------------------------------------------+
//|                                      AurumnStrategy_European.mqh  |
//|        SESI 4: STRATEGI SESI EROPA (London)                      |
//|        Dua mode (pilih via Euro_Strategy):                       |
//|        1) ASIAN-RANGE BREAKOUT (default) - tembus range sesi Asia |
//|           di awal London + filter false-break. Sesuai karakter:   |
//|           "breakout dari range Asia, banyak false break di open,  |
//|            tren yg terbentuk cenderung sustain".                  |
//|        2) DONCHIAN BREAKOUT - channel generik (alternatif A/B).   |
//+------------------------------------------------------------------+
#ifndef AURUMN_STRATEGY_EUROPEAN_MQH
#define AURUMN_STRATEGY_EUROPEAN_MQH
#include <AurumnSymbolSpec.mqh>

enum EuroStratType
{
   EURO_DONCHIAN   = 0,   // Donchian channel breakout
   EURO_ASIANRANGE = 1    // Breakout dari range sesi Asia (khas London)
};

input group "=== SESI EROPA (London): PILIHAN STRATEGI ==="
input EuroStratType Euro_Strategy = EURO_ASIANRANGE; // Strategi aktif sesi Eropa

input group "--- Asian-Range Breakout (sesuai karakter London) ---"
input int    EuroAR_AsianStartHour = 0;    // Jam mulai range Asia (samakan AsianSessionStart)
input int    EuroAR_AsianEndHour   = 8;    // Jam selesai range Asia (samakan AsianSessionEnd)
input double EuroAR_BreakBufferATR = 0.15; // Filter false-break: tembus > x ATR di luar range
input int    EuroAR_BreakoutWindowEnd = 15; // Hanya breakout SEBELUM jam ini (awal London)

input group "--- Donchian Breakout (alternatif A/B) ---"
input int    Euro_Channel          = 30;   // Lookback channel high/low
input double Euro_MinChannelATR     = 0.5;  // Tinggi channel min (x ATR)

input group "--- Umum Sesi Eropa ---"
input double Euro_ADXMin            = 20.0; // ADX minimal (pastikan momentum)
input bool   Euro_RequireADXRising  = true; // ADX harus sedang naik
input int    Euro_ADXPeriod         = 14;   // Periode ADX
input double Euro_SLMultiplier      = 2.0;  // SL = ATR x mult (lebar, biar tren bernapas)
input double Euro_RR                = 2.0;  // Risk:Reward
input double Euro_RiskFactor        = 1.0;  // Sizing standar

//--- Handle
int g_euADXH = INVALID_HANDLE;

bool Euro_Init()
{
   g_euADXH = iADX(_Symbol, PERIOD_M15, Euro_ADXPeriod);
   return(g_euADXH != INVALID_HANDLE);
}
void Euro_Deinit()
{
   if(g_euADXH != INVALID_HANDLE) IndicatorRelease(g_euADXH);
}

//--- Filter ADX (kedua mode)
bool Euro_ADXOK()
{
   double adx[];
   ArraySetAsSeries(adx, true);
   if(CopyBuffer(g_euADXH, 0, 1, 2, adx) < 2) return(false);
   return((adx[0] >= Euro_ADXMin) && (!Euro_RequireADXRising || adx[0] > adx[1]));
}

//--- Range sesi Asia hari ini (high/low). Stateless: telusuri bar mundur,
//    kumpulkan bar berjam Asia, berhenti saat keluar dari blok Asia.
bool Euro_GetAsianRange(double &rH, double &rL)
{
   rH = 0; rL = 0;
   double hi = -DBL_MAX, lo = DBL_MAX;
   bool found = false;
   for(int i = 1; i <= 150; i++)
   {
      datetime bt = iTime(_Symbol, PERIOD_M15, i);
      if(bt <= 0) break;
      MqlDateTime dt; TimeToStruct(bt, dt);
      bool inAsia = (dt.hour >= EuroAR_AsianStartHour && dt.hour < EuroAR_AsianEndHour);
      if(inAsia)
      {
         double bh = iHigh(_Symbol, PERIOD_M15, i);
         double bl = iLow(_Symbol, PERIOD_M15, i);
         if(bh > hi) hi = bh;
         if(bl < lo) lo = bl;
         found = true;
      }
      else if(found) break;   // sudah lewat blok Asia hari ini
   }
   if(!found || hi <= lo) return(false);
   rH = hi; rL = lo;
   return(true);
}

//+------------------------------------------------------------------+
//| MODE 1: Asian-Range Breakout (khas London)                      |
//| Entry FRESH saat close menembus di luar range Asia + buffer.    |
//| Buffer = filter false-break. Tren dibiarkan jalan via trailing. |
//+------------------------------------------------------------------+
int Euro_SignalAsianRange(const SAurumnSpec &spec, double atrPips, double &slPips, double &tpPips)
{
   slPips = 0.0; tpPips = 0.0;

   //--- Hanya ambil breakout di AWAL London (range Asia ditembus di jam-jam pertama).
   //    Setelah window ini, pergerakan harian sudah matang -> tidak entry breakout baru.
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour >= EuroAR_BreakoutWindowEnd) return(0);

   if(!Euro_ADXOK()) return(0);

   double rH, rL;
   if(!Euro_GetAsianRange(rH, rL)) return(0);

   double atrPrice = atrPips * spec.pip;
   double buffer   = EuroAR_BreakBufferATR * atrPrice;
   double up = rH + buffer;
   double dn = rL - buffer;

   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double close2 = iClose(_Symbol, PERIOD_M15, 2);

   //--- FRESH breakout: bar sebelumnya masih di dalam, bar ini menembus
   bool buy  = (close1 > up) && (close2 <= up);
   bool sell = (close1 < dn) && (close2 >= dn);
   if(!buy && !sell) return(0);

   slPips = atrPips * Euro_SLMultiplier;
   tpPips = slPips * Euro_RR;
   return(buy ? 1 : -1);
}

//+------------------------------------------------------------------+
//| MODE 2: Donchian Breakout (alternatif)                          |
//+------------------------------------------------------------------+
int Euro_SignalDonchian(const SAurumnSpec &spec, double atrPips, double &slPips, double &tpPips)
{
   slPips = 0.0; tpPips = 0.0;
   if(!Euro_ADXOK()) return(0);

   int hiIdx = iHighest(_Symbol, PERIOD_M15, MODE_HIGH, Euro_Channel, 2);
   int loIdx = iLowest(_Symbol, PERIOD_M15, MODE_LOW,  Euro_Channel, 2);
   if(hiIdx < 0 || loIdx < 0) return(0);
   double chHigh = iHigh(_Symbol, PERIOD_M15, hiIdx);
   double chLow  = iLow(_Symbol, PERIOD_M15, loIdx);
   if((chHigh - chLow) / spec.pip < Euro_MinChannelATR * atrPips) return(0);

   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   bool buy  = (close1 > chHigh);
   bool sell = (close1 < chLow);
   if(!buy && !sell) return(0);

   slPips = atrPips * Euro_SLMultiplier;
   tpPips = slPips * Euro_RR;
   return(buy ? 1 : -1);
}

//+------------------------------------------------------------------+
//| Dispatcher                                                       |
//+------------------------------------------------------------------+
int Euro_Signal(const SAurumnSpec &spec, double atrPips, double &slPips, double &tpPips)
{
   slPips = 0.0; tpPips = 0.0;
   if(atrPips <= 0) return(0);
   if(Euro_Strategy == EURO_ASIANRANGE)
      return(Euro_SignalAsianRange(spec, atrPips, slPips, tpPips));
   return(Euro_SignalDonchian(spec, atrPips, slPips, tpPips));
}

#endif // AURUMN_STRATEGY_EUROPEAN_MQH
