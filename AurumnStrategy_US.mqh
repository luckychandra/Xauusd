//+------------------------------------------------------------------+
//|                                            AurumnStrategy_US.mqh  |
//|        SESI 5: STRATEGI SESI US - Breakout (Donchian + ADX)      |
//|        ROMBAK v2: Keltner volatility breakout (PF 0.93, rugi)     |
//|        diganti dgn breakout channel yang terbukti edge di gold.   |
//|        Channel lebih pendek (sesi US lebih cepat/volatil).        |
//|        Sizing diturunkan ke 1.0x (agresif 1.5x bikin DD 50%).     |
//|        CATATAN: news filter & pre-news close = Sesi 7 (terpisah). |
//+------------------------------------------------------------------+
#ifndef AURUMN_STRATEGY_US_MQH
#define AURUMN_STRATEGY_US_MQH
#include <AurumnSymbolSpec.mqh>

input group "=== SESI US (Breakout Donchian + ADX) ==="
input int    US_Channel           = 15;    // Lookback channel (lebih pendek utk sesi cepat)
input double US_ADXMin            = 20.0;  // ADX minimal (pastikan ada trend)
input bool   US_RequireADXRising  = true;  // ADX harus sedang naik
input double US_MinChannelATR     = 0.5;   // Tinggi channel min (x ATR)
input int    US_ADXPeriod         = 14;    // Periode ADX
input double US_SLMultiplier      = 1.5;   // SL = ATR x mult
input double US_RR                = 1.5;   // Risk:Reward
input double US_RiskFactor        = 1.0;   // Sizing standar (diturunkan dari 1.5x)

//--- Handle indikator
int g_usADXH = INVALID_HANDLE;

bool US_Init()
{
   g_usADXH = iADX(_Symbol, PERIOD_M15, US_ADXPeriod);
   return(g_usADXH != INVALID_HANDLE);
}

void US_Deinit()
{
   if(g_usADXH != INVALID_HANDLE) IndicatorRelease(g_usADXH);
}

//+------------------------------------------------------------------+
//| Sinyal sesi US (breakout Donchian + ADX, channel pendek)        |
//+------------------------------------------------------------------+
int US_Signal(const SAurumnSpec &spec, double atrPips, double &slPips, double &tpPips)
{
   slPips = 0.0; tpPips = 0.0;
   if(atrPips <= 0) return(0);

   double adx[];
   ArraySetAsSeries(adx, true);
   if(CopyBuffer(g_usADXH, 0, 1, 2, adx) < 2) return(0);
   bool adxOK = (adx[0] >= US_ADXMin) &&
                (!US_RequireADXRising || adx[0] > adx[1]);
   if(!adxOK) return(0);

   int hiIdx = iHighest(_Symbol, PERIOD_M15, MODE_HIGH, US_Channel, 2);
   int loIdx = iLowest(_Symbol, PERIOD_M15, MODE_LOW,  US_Channel, 2);
   if(hiIdx < 0 || loIdx < 0) return(0);
   double chHigh = iHigh(_Symbol, PERIOD_M15, hiIdx);
   double chLow  = iLow(_Symbol, PERIOD_M15, loIdx);

   double chHeightPips = (chHigh - chLow) / spec.pip;
   if(chHeightPips < US_MinChannelATR * atrPips) return(0);

   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   bool buy  = (close1 > chHigh);
   bool sell = (close1 < chLow);
   if(!buy && !sell) return(0);

   slPips = atrPips * US_SLMultiplier;
   tpPips = slPips * US_RR;
   return(buy ? 1 : -1);
}

#endif // AURUMN_STRATEGY_US_MQH
