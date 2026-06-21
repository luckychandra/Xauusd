//+------------------------------------------------------------------+
//|                                       AurumnStrategy_Overlap.mqh  |
//|        SESI OVERLAP London-New York (15-19 server)              |
//|        Periode paling likuid & bertrend untuk XAUUSD:           |
//|        likuiditas London (LBMA) + NY (COMEX/data US).           |
//|        Strategi: Donchian breakout + ADX (momentum trend).      |
//|        Dipisah dari sesi US agar bisa diukur: apakah overlap    |
//|        (15-19) yg bagus, & NY-akhir (19-24) yg menyeret rugi.   |
//+------------------------------------------------------------------+
#ifndef AURUMN_STRATEGY_OVERLAP_MQH
#define AURUMN_STRATEGY_OVERLAP_MQH
#include <AurumnSymbolSpec.mqh>

input group "=== SESI OVERLAP London-NY (Breakout) ==="
input int    Overlap_Channel         = 20;    // Lookback channel high/low
input double Overlap_MinChannelATR    = 0.5;   // Tinggi channel min (x ATR)
input double Overlap_ADXMin           = 20.0;  // ADX minimal
input bool   Overlap_RequireADXRising = true;  // ADX harus sedang naik
input int    Overlap_ADXPeriod        = 14;    // Periode ADX
input double Overlap_SLMultiplier     = 1.5;   // SL = ATR x mult
input double Overlap_RR               = 1.5;   // Risk:Reward
input double Overlap_RiskFactor       = 1.0;   // Sizing standar (jangan over-size sblm terbukti)

int g_ovADXH = INVALID_HANDLE;

bool Overlap_Init()
{
   g_ovADXH = iADX(_Symbol, PERIOD_M15, Overlap_ADXPeriod);
   return(g_ovADXH != INVALID_HANDLE);
}
void Overlap_Deinit()
{
   if(g_ovADXH != INVALID_HANDLE) IndicatorRelease(g_ovADXH);
}

int Overlap_Signal(const SAurumnSpec &spec, double atrPips, double &slPips, double &tpPips)
{
   slPips = 0.0; tpPips = 0.0;
   if(atrPips <= 0) return(0);

   //--- Filter ADX
   double adx[];
   ArraySetAsSeries(adx, true);
   if(CopyBuffer(g_ovADXH, 0, 1, 2, adx) < 2) return(0);
   if(!((adx[0] >= Overlap_ADXMin) && (!Overlap_RequireADXRising || adx[0] > adx[1])))
      return(0);

   //--- Donchian channel (bar 2..Channel+1, di luar bar berjalan)
   int hiIdx = iHighest(_Symbol, PERIOD_M15, MODE_HIGH, Overlap_Channel, 2);
   int loIdx = iLowest(_Symbol, PERIOD_M15, MODE_LOW,  Overlap_Channel, 2);
   if(hiIdx < 0 || loIdx < 0) return(0);
   double chHigh = iHigh(_Symbol, PERIOD_M15, hiIdx);
   double chLow  = iLow(_Symbol, PERIOD_M15, loIdx);
   if((chHigh - chLow) / spec.pip < Overlap_MinChannelATR * atrPips) return(0);

   //--- Breakout pada close bar terakhir
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   bool buy  = (close1 > chHigh);
   bool sell = (close1 < chLow);
   if(!buy && !sell) return(0);

   slPips = atrPips * Overlap_SLMultiplier;
   tpPips = slPips * Overlap_RR;
   return(buy ? 1 : -1);
}

#endif // AURUMN_STRATEGY_OVERLAP_MQH
