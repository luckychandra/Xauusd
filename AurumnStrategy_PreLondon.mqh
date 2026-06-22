//+------------------------------------------------------------------+
//|                                     AurumnStrategy_PreLondon.mqh  |
//|        SESI PRA-LONDON (Frankfurt open, 08-10 server)           |
//|        Transisi Asia->London: likuiditas mulai naik (Frankfurt)  |
//|        tapi sebelum London open (10:00). Sering momentum awal     |
//|        ATAU sweep/fakeout. Strategi: Donchian breakout (momentum  |
//|        dini), DIBEDAKAN dari Europe (Asian-range) agar uji beda.  |
//|        PERINGATAN: periode transisi/likuiditas tipis - uji        |
//|        isolasi dulu; bisa jadi gap lebih baik dibiarkan kosong.   |
//+------------------------------------------------------------------+
#ifndef AURUMN_STRATEGY_PRELONDON_MQH
#define AURUMN_STRATEGY_PRELONDON_MQH
#include <AurumnSymbolSpec.mqh>

input group "=== SESI PRA-LONDON (Frankfurt 08-10): Breakout ==="
input int    PreLon_Channel         = 15;    // Lookback channel high/low
input double PreLon_MinChannelATR    = 0.5;   // Tinggi channel min (x ATR)
input double PreLon_ADXMin           = 20.0;  // ADX minimal
input bool   PreLon_RequireADXRising = true;  // ADX harus sedang naik
input int    PreLon_ADXPeriod        = 14;    // Periode ADX
input double PreLon_SLMultiplier     = 1.5;   // SL = ATR x mult
input double PreLon_RR               = 1.5;   // Risk:Reward
input double PreLon_RiskFactor       = 1.0;   // Sizing (jangan over-size periode belum terbukti)

int g_plADXH = INVALID_HANDLE;

bool PreLon_Init()
{
   g_plADXH = iADX(_Symbol, PERIOD_M15, PreLon_ADXPeriod);
   return(g_plADXH != INVALID_HANDLE);
}
void PreLon_Deinit()
{
   if(g_plADXH != INVALID_HANDLE) IndicatorRelease(g_plADXH);
}

int PreLon_Signal(const SAurumnSpec &spec, double atrPips, double &slPips, double &tpPips)
{
   slPips = 0.0; tpPips = 0.0;
   if(atrPips <= 0) return(0);

   //--- Filter ADX
   double adx[];
   ArraySetAsSeries(adx, true);
   if(CopyBuffer(g_plADXH, 0, 1, 2, adx) < 2) return(0);
   if(!((adx[0] >= PreLon_ADXMin) && (!PreLon_RequireADXRising || adx[0] > adx[1])))
      return(0);

   //--- Donchian channel (bar 2..Channel+1)
   int hiIdx = iHighest(_Symbol, PERIOD_M15, MODE_HIGH, PreLon_Channel, 2);
   int loIdx = iLowest(_Symbol, PERIOD_M15, MODE_LOW,  PreLon_Channel, 2);
   if(hiIdx < 0 || loIdx < 0) return(0);
   double chHigh = iHigh(_Symbol, PERIOD_M15, hiIdx);
   double chLow  = iLow(_Symbol, PERIOD_M15, loIdx);
   if((chHigh - chLow) / spec.pip < PreLon_MinChannelATR * atrPips) return(0);

   //--- Breakout pada close bar terakhir
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   bool buy  = (close1 > chHigh);
   bool sell = (close1 < chLow);
   if(!buy && !sell) return(0);

   slPips = atrPips * PreLon_SLMultiplier;
   tpPips = slPips * PreLon_RR;
   return(buy ? 1 : -1);
}

#endif // AURUMN_STRATEGY_PRELONDON_MQH
