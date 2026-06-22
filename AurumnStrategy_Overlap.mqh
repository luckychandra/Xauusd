//+------------------------------------------------------------------+
//|                                       AurumnStrategy_Overlap.mqh  |
//|        SESI OVERLAP London-NY (15-19 server) - ROMBAK PENUH     |
//|                                                                  |
//|        Baseline (Donchian breakout) RUGI BERAT (-434, DD 96%):  |
//|        overlap = volatilitas tertinggi = WHIPSAW tertinggi.      |
//|        Breakout kena fakeout di NY open. Strategi diganti.       |
//|                                                                  |
//|        Pola inti (analisa): "liquidity sweep / stop hunt di awal |
//|        overlap menembus high/low sesi London lalu REVERSAL", &   |
//|        "false breakout di NY open". -> Kita FADE sapuan itu.     |
//|                                                                  |
//|        MODE:                                                     |
//|        1) SWEEP (utama) - fade stop hunt: bar menyapu range      |
//|           rolling (~sesi London) lalu close balik -> entry lawan.|
//|        2) BREAKOUT - Donchian lama (alternatif A/B).            |
//|        Fokus jam awal overlap (volatilitas memuncak 2 jam awal). |
//|        News filter global menutup spike rilis data AS.          |
//+------------------------------------------------------------------+
#ifndef AURUMN_STRATEGY_OVERLAP_MQH
#define AURUMN_STRATEGY_OVERLAP_MQH
#include <AurumnSymbolSpec.mqh>

enum OverlapMode
{
   OVL_SWEEP    = 0,   // Fade liquidity sweep / stop hunt (utama)
   OVL_BREAKOUT = 1    // Donchian breakout (alternatif A/B)
};

input group "=== SESI OVERLAP London-NY: MODE ==="
input OverlapMode Overlap_Mode = OVL_SWEEP;   // Strategi overlap aktif

input group "--- Mode SWEEP (fade stop hunt) ---"
input int    Ovl_RangeLookback    = 20;    // Lookback range (bar M15) yg disapu (~sesi London = 5 jam)
input double Ovl_SweepPenetrATR   = 0.10;  // Sapuan min di luar range (x ATR) utk dihitung sweep
input int    Ovl_EntryWindowEnd   = 17;    // Entry hanya SEBELUM jam ini (fokus 2 jam awal overlap)

input group "--- Mode BREAKOUT (alternatif A/B) ---"
input int    Overlap_Channel      = 20;    // Lookback channel
input double Overlap_MinChannelATR = 0.5;  // Tinggi channel min (x ATR)

input group "--- Umum Overlap ---"
input double Overlap_ADXMin       = 20.0;  // ADX minimal (mode breakout)
input bool   Overlap_RequireADXRising = true; // ADX naik (mode breakout)
input int    Overlap_ADXPeriod    = 14;    // Periode ADX
input double Overlap_SLMultiplier = 1.5;   // SL = ATR x mult
input double Overlap_RR           = 2.5;   // Risk:Reward (tinggi: biarkan reversal jalan)
input double Overlap_RiskFactor   = 1.0;   // Sizing sesi

int g_ovADXH = INVALID_HANDLE;
int g_ovDstShift = 0;   // di-set EA tiap tick = SessionDstShift()

bool Overlap_Init()
{
   g_ovADXH = iADX(_Symbol, PERIOD_M15, Overlap_ADXPeriod);
   return(g_ovADXH != INVALID_HANDLE);
}
void Overlap_Deinit()
{
   if(g_ovADXH != INVALID_HANDLE) IndicatorRelease(g_ovADXH);
}

bool Ovl_InEntryWindow()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   return((dt.hour - g_ovDstShift) < Ovl_EntryWindowEnd);
}

bool Ovl_ADXOK()
{
   double adx[];
   ArraySetAsSeries(adx, true);
   if(CopyBuffer(g_ovADXH, 0, 1, 2, adx) < 2) return(false);
   return((adx[0] >= Overlap_ADXMin) && (!Overlap_RequireADXRising || adx[0] > adx[1]));
}

//+------------------------------------------------------------------+
//| MODE SWEEP: bar menyapu range rolling lalu CLOSE balik ke dalam |
//| (stop hunt + rejection) -> entry arah REVERSAL. Fade sapuan.    |
//+------------------------------------------------------------------+
int Ovl_SignalSweep(const SAurumnSpec &spec, double atrPips, double &slPips, double &tpPips)
{
   slPips = 0.0; tpPips = 0.0;
   if(!Ovl_InEntryWindow()) return(0);

   //--- range yg disapu = high/low bar [2..lookback+1] (kecuali bar sweep di shift 1)
   int hiIdx = iHighest(_Symbol, PERIOD_M15, MODE_HIGH, Ovl_RangeLookback, 2);
   int loIdx = iLowest(_Symbol, PERIOD_M15, MODE_LOW,  Ovl_RangeLookback, 2);
   if(hiIdx < 0 || loIdx < 0) return(0);
   double RH = iHigh(_Symbol, PERIOD_M15, hiIdx);
   double RL = iLow(_Symbol, PERIOD_M15, loIdx);

   double atrPrice = atrPips * spec.pip;
   double pen = Ovl_SweepPenetrATR * atrPrice;

   double high1  = iHigh(_Symbol, PERIOD_M15, 1);
   double low1   = iLow(_Symbol, PERIOD_M15, 1);
   double close1 = iClose(_Symbol, PERIOD_M15, 1);

   //--- sapu HIGH lalu ditolak (close balik di bawah RH) -> SELL
   bool sweepHigh = (high1 > RH + pen) && (close1 < RH);
   //--- sapu LOW lalu ditolak (close balik di atas RL) -> BUY
   bool sweepLow  = (low1 < RL - pen)  && (close1 > RL);
   if(!sweepHigh && !sweepLow) return(0);

   slPips = atrPips * Overlap_SLMultiplier;
   tpPips = slPips * Overlap_RR;
   return(sweepHigh ? -1 : 1);
}

//+------------------------------------------------------------------+
//| MODE BREAKOUT: Donchian (alternatif, untuk A/B)                 |
//+------------------------------------------------------------------+
int Ovl_SignalBreakout(const SAurumnSpec &spec, double atrPips, double &slPips, double &tpPips)
{
   slPips = 0.0; tpPips = 0.0;
   if(!Ovl_InEntryWindow()) return(0);
   if(!Ovl_ADXOK()) return(0);

   int hiIdx = iHighest(_Symbol, PERIOD_M15, MODE_HIGH, Overlap_Channel, 2);
   int loIdx = iLowest(_Symbol, PERIOD_M15, MODE_LOW,  Overlap_Channel, 2);
   if(hiIdx < 0 || loIdx < 0) return(0);
   double chHigh = iHigh(_Symbol, PERIOD_M15, hiIdx);
   double chLow  = iLow(_Symbol, PERIOD_M15, loIdx);
   if((chHigh - chLow) / spec.pip < Overlap_MinChannelATR * atrPips) return(0);

   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   bool buy  = (close1 > chHigh);
   bool sell = (close1 < chLow);
   if(!buy && !sell) return(0);

   slPips = atrPips * Overlap_SLMultiplier;
   tpPips = slPips * Overlap_RR;
   return(buy ? 1 : -1);
}

//+------------------------------------------------------------------+
//| Dispatcher                                                       |
//+------------------------------------------------------------------+
int Overlap_Signal(const SAurumnSpec &spec, double atrPips, double &slPips, double &tpPips)
{
   slPips = 0.0; tpPips = 0.0;
   if(atrPips <= 0) return(0);
   if(Overlap_Mode == OVL_SWEEP)
      return(Ovl_SignalSweep(spec, atrPips, slPips, tpPips));
   return(Ovl_SignalBreakout(spec, atrPips, slPips, tpPips));
}

#endif // AURUMN_STRATEGY_OVERLAP_MQH
