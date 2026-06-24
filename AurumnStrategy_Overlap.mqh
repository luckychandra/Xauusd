//+------------------------------------------------------------------+
//|                                       AurumnStrategy_Overlap.mqh  |
//|        SESI OVERLAP London-NY (15-19 server) - MTF MOMENTUM-BURST |
//|                                                                  |
//|        Sejarah: Donchian breakout RUGI -434 (DD 96%), sweep-fade |
//|        ~-350. Window ini volatilitas TERTINGGI digerakkan berita |
//|        AS -> spike dua arah. Strategi satu-arah pasti kalah di    |
//|        salah satu rezim (tren KUAT vs reversal).                 |
//|                                                                  |
//|        ROMBAK (analisa): edge sejati = gerakan DIRECTIONAL kuat   |
//|        saat London & NY sepakat tema makro. Maka:                |
//|        - JANGAN tebak arah -> IKUTI tren yang sudah established. |
//|        - HINDARI spike berita (news filter dinamis ±45m).        |
//|                                                                  |
//|        MULTI-TIMEFRAME:                                          |
//|        - BIAS  (M15): EMA50 slope + ADX -> arah (long/short saja).|
//|        - ENTRY (M5) : pullback ke EMA20 + konfirmasi momentum RSI.|
//|        - SL = ATR(M5) ketat. TP = fixed RR (bank burst).         |
//|        Dievaluasi per-bar M5 (entry MTF) - diatur di EA OnTick.   |
//+------------------------------------------------------------------+
#ifndef AURUMN_STRATEGY_OVERLAP_MQH
#define AURUMN_STRATEGY_OVERLAP_MQH
#include <AurumnSymbolSpec.mqh>

input group "=== SESI OVERLAP (NY 15-19): MTF Momentum-Burst ==="
input int    Ovl_BiasEMA          = 50;     // [Bias M15] EMA arah tren
input double Ovl_BiasADXMin        = 22.0;   // [Bias M15] ADX min (tren cukup kuat utk burst)
input int    Ovl_BiasADXPeriod     = 14;     // [Bias M15] periode ADX
input int    Ovl_EntryEMA          = 20;     // [Entry M5] EMA pullback
input double Ovl_PullbackATR        = 0.50;   // [Entry M5] jarak max harga->EMA20 (x ATR M5) = "sudah pullback"
input int    Ovl_RSIPeriod          = 14;     // [Entry M5] periode RSI (momentum)
input double Ovl_RSIMidline         = 50.0;   // [Entry M5] cross garis ini searah bias = momentum lanjut
input int    Ovl_EntryATRPeriod     = 14;     // [Entry M5] periode ATR (basis SL)
input double Ovl_SLMultiplier        = 1.5;    // SL = ATR(M5) x mult (ketat, area swing pullback)
input double Ovl_RR                  = 1.5;    // Risk:Reward (bank burst; pelajaran runner = jangan over-hold)
input int    Ovl_EntryWindowEnd      = 19;     // entry hanya SEBELUM jam ini (server)
input double Overlap_RiskFactor      = 0.5;    // sizing sesi (KONSERVATIF - sesi 2x gagal, belum terbukti)

//--- Handle MTF
int g_ovBiasEMA  = INVALID_HANDLE;   // EMA50 M15 (bias)
int g_ovBiasADX  = INVALID_HANDLE;   // ADX  M15 (kekuatan tren)
int g_ovEntryEMA = INVALID_HANDLE;   // EMA20 M5 (pullback)
int g_ovEntryRSI = INVALID_HANDLE;   // RSI  M5 (momentum)
int g_ovEntryATR = INVALID_HANDLE;   // ATR  M5 (SL)
int g_ovDstShift = 0;                // di-set EA tiap tick = SessionDstShift()

bool Overlap_Init()
{
   g_ovBiasEMA  = iMA(_Symbol,  PERIOD_M15, Ovl_BiasEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_ovBiasADX  = iADX(_Symbol, PERIOD_M15, Ovl_BiasADXPeriod);
   g_ovEntryEMA = iMA(_Symbol,  PERIOD_M5,  Ovl_EntryEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_ovEntryRSI = iRSI(_Symbol, PERIOD_M5,  Ovl_RSIPeriod, PRICE_CLOSE);
   g_ovEntryATR = iATR(_Symbol, PERIOD_M5,  Ovl_EntryATRPeriod);
   return(g_ovBiasEMA  != INVALID_HANDLE && g_ovBiasADX  != INVALID_HANDLE &&
          g_ovEntryEMA != INVALID_HANDLE && g_ovEntryRSI != INVALID_HANDLE &&
          g_ovEntryATR != INVALID_HANDLE);
}
void Overlap_Deinit()
{
   if(g_ovBiasEMA  != INVALID_HANDLE) IndicatorRelease(g_ovBiasEMA);
   if(g_ovBiasADX  != INVALID_HANDLE) IndicatorRelease(g_ovBiasADX);
   if(g_ovEntryEMA != INVALID_HANDLE) IndicatorRelease(g_ovEntryEMA);
   if(g_ovEntryRSI != INVALID_HANDLE) IndicatorRelease(g_ovEntryRSI);
   if(g_ovEntryATR != INVALID_HANDLE) IndicatorRelease(g_ovEntryATR);
}

bool Ovl_InEntryWindow()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   return((dt.hour - g_ovDstShift) < Ovl_EntryWindowEnd);
}

//--- BIAS dari TF tinggi (M15): +1 tren naik, -1 turun, 0 tak jelas
int Ovl_Bias()
{
   double ema[]; ArraySetAsSeries(ema, true);
   if(CopyBuffer(g_ovBiasEMA, 0, 1, 2, ema) < 2) return(0);   // ema[0]=bar tutup terakhir, ema[1]=sebelumnya
   double adx[]; ArraySetAsSeries(adx, true);
   if(CopyBuffer(g_ovBiasADX, 0, 1, 1, adx) < 1) return(0);
   if(adx[0] < Ovl_BiasADXMin) return(0);                     // tren kurang kuat -> no trade
   double c = iClose(_Symbol, PERIOD_M15, 1);
   if(c > ema[0] && ema[0] > ema[1]) return(+1);              // harga>EMA & EMA naik
   if(c < ema[0] && ema[0] < ema[1]) return(-1);              // harga<EMA & EMA turun
   return(0);
}

//+------------------------------------------------------------------+
//| ENTRY (M5): pullback ke EMA20 searah bias + konfirmasi momentum  |
//+------------------------------------------------------------------+
int Overlap_Signal(const SAurumnSpec &spec, double atrPips, double &slPips, double &tpPips)
{
   slPips = 0.0; tpPips = 0.0;
   if(!Ovl_InEntryWindow()) return(0);

   int bias = Ovl_Bias();                 // arah dari M15
   if(bias == 0) return(0);

   double ema5[]; ArraySetAsSeries(ema5, true);
   if(CopyBuffer(g_ovEntryEMA, 0, 1, 1, ema5) < 1) return(0);
   double rsi[];  ArraySetAsSeries(rsi, true);
   if(CopyBuffer(g_ovEntryRSI, 0, 1, 2, rsi) < 2) return(0);   // rsi[0]=tutup terakhir, rsi[1]=sebelumnya
   double atrb[]; ArraySetAsSeries(atrb, true);
   if(CopyBuffer(g_ovEntryATR, 0, 1, 1, atrb) < 1) return(0);
   double atr5 = atrb[0];
   if(atr5 <= 0.0) return(0);

   double c5 = iClose(_Symbol, PERIOD_M5, 1);
   bool nearEMA = (MathAbs(c5 - ema5[0]) <= Ovl_PullbackATR * atr5);   // sudah pullback ke EMA20 M5

   if(bias > 0)
   {
      //--- LONG: pullback ke EMA + momentum NAIK (RSI cross-up midline ATAU candle lanjut di atas EMA)
      bool momUp = (rsi[1] < Ovl_RSIMidline && rsi[0] >= Ovl_RSIMidline) ||
                   (c5 > ema5[0] && rsi[0] > Ovl_RSIMidline);
      if(nearEMA && momUp && c5 >= ema5[0])
      {
         slPips = Ovl_SLMultiplier * atr5 / spec.pip;
         tpPips = slPips * Ovl_RR;
         return(+1);
      }
   }
   else
   {
      //--- SHORT: pullback ke EMA + momentum TURUN
      bool momDn = (rsi[1] > Ovl_RSIMidline && rsi[0] <= Ovl_RSIMidline) ||
                   (c5 < ema5[0] && rsi[0] < Ovl_RSIMidline);
      if(nearEMA && momDn && c5 <= ema5[0])
      {
         slPips = Ovl_SLMultiplier * atr5 / spec.pip;
         tpPips = slPips * Ovl_RR;
         return(-1);
      }
   }
   return(0);
}

#endif // AURUMN_STRATEGY_OVERLAP_MQH
