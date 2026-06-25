//+------------------------------------------------------------------+
//|                                        AurumnStrategy_Asian.mqh   |
//|        SESI ASIA - 2 mode strategi (pilih via Asian_Strategy):    |
//|        1) BREAKOUT (default) - Donchian channel + ADX trend.      |
//|           Searah momentum; cocok dgn sifat gold yg trending.      |
//|        2) MEAN-REVERSION - BB + RSI (versi lama, untuk A/B test).  |
//+------------------------------------------------------------------+
#ifndef AURUMN_STRATEGY_ASIAN_MQH
#define AURUMN_STRATEGY_ASIAN_MQH
#include <AurumnSymbolSpec.mqh>

enum AsianStratType
{
   STRAT_MEANREV  = 0,   // Mean reversion (BB + RSI)
   STRAT_BREAKOUT = 1    // Breakout (Donchian channel + ADX)
};

input group "=== SESI ASIA: PILIHAN STRATEGI ==="
input AsianStratType Asian_Strategy = STRAT_BREAKOUT; // Strategi aktif sesi Asia

input group "--- Breakout (Donchian + ADX) ---"
input int    AsianBO_Channel          = 20;    // Lookback channel high/low (bar)
input double AsianBO_ADXMin           = 20.0;  // ADX minimal (pastikan ada trend)
input bool   AsianBO_RequireADXRising = true;  // ADX harus sedang naik (momentum)
input double AsianBO_MinChannelATR    = 0.5;   // Tinggi channel min (x ATR) - hindari range sempit

input group "--- Mean Reversion (BB + RSI) ---"
input int    Asian_BBPeriod      = 20;     // Periode Bollinger Bands
input double Asian_BBDeviation   = 1.5;    // Deviasi BB (v2.3.1: 2.0->1.5, lbh byk sentuhan)
input int    Asian_RSIPeriod     = 14;     // Periode RSI
input double Asian_RSIOversold   = 30.0;   // Ambang RSI oversold
input double Asian_RSIOverbought = 70.0;   // Ambang RSI overbought
input bool   Asian_RequireRSITurn = true;  // Wajib RSI berbalik arah
input int    Asian_RangeLookback = 24;     // Bar untuk S/R range
input double Asian_EdgeZone      = 0.33;   // Harga di 33% tepi range (bila edge-zone ON)
input bool   Asian_UseEdgeZone   = false;  // (v2.3.1) Wajib di tepi range? OFF=lbh byk trade (pierce BB sdh=ekstrem)
input double Asian_ADXMaxTrend   = 25.0;   // Trade hanya bila ADX < ini (ranging)

input group "--- Mean Reversion v2: filter struktural (toggle utk uji) ---"
input bool   MR_UseTrendFilter   = true;   // #1 Veto fade LAWAN tren H1 (anti pisau-jatuh)
input int    MR_TrendEMA         = 50;     // EMA H1 penentu arah tren
input double MR_TrendADXMin      = 25.0;   // H1 ADX >= ini = trending -> veto fade lawan arah
input bool   MR_RequireRejection = true;   // #2 Wajib bar tolak band (wick), bukan close menembus
input double MR_RSI_Reject       = 40.0;   // RSI longgar saat rejection (buy<ini, sell>100-ini)
input bool   MR_UseVolContraction= true;   // #3 Hanya trade saat ATR < rata2 (range sejati)
input double MR_VolMaxRatio      = 1.3;    // Skip bila ATR-kini > rasio x ATR-rata2
input int    MR_VolAvgPeriod     = 50;     // Bar utk ATR rata2
input int    MR_TPMode           = 1;      // #4 TP: 0=RR (Asian_RR), 1=target BB-tengah (mean)

input group "--- Umum Sesi Asia ---"
input int    Asian_ADXPeriod     = 14;     // Periode ADX (dipakai kedua mode)
input double Asian_SLMultiplier  = 1.0;    // SL = ATR x mult (NILAI TERVALIDASI +345; bukan 1.5)
input double Asian_RR            = 1.2;    // Risk:Reward (NILAI TERVALIDASI +345; bukan 1.5)
input double Asian_RiskFactor    = 0.5;    // Pengurang sizing sesi Asia

//--- Handle indikator (file-scope)
int g_asBBH  = INVALID_HANDLE;
int g_asRSIH = INVALID_HANDLE;
int g_asADXH = INVALID_HANDLE;
//--- v2 mean-rev: handle filter struktural
int g_mrEmaH1 = INVALID_HANDLE;   // EMA H1 (arah tren)
int g_mrAdxH1 = INVALID_HANDLE;   // ADX H1 (kekuatan tren)
int g_mrAtrH  = INVALID_HANDLE;   // ATR M15 (regime volatilitas)

//+------------------------------------------------------------------+
bool Asian_Init()
{
   g_asBBH  = iBands(_Symbol, PERIOD_M15, Asian_BBPeriod, 0, Asian_BBDeviation, PRICE_CLOSE);
   g_asRSIH = iRSI(_Symbol, PERIOD_M15, Asian_RSIPeriod, PRICE_CLOSE);
   g_asADXH = iADX(_Symbol, PERIOD_M15, Asian_ADXPeriod);
   bool okBase = (g_asBBH != INVALID_HANDLE && g_asRSIH != INVALID_HANDLE && g_asADXH != INVALID_HANDLE);
   //--- v2: handle filter struktural mean-rev (hanya saat mode MEANREV)
   if(Asian_Strategy == STRAT_MEANREV)
   {
      g_mrEmaH1 = iMA(_Symbol, PERIOD_H1, MR_TrendEMA, 0, MODE_EMA, PRICE_CLOSE);
      g_mrAdxH1 = iADX(_Symbol, PERIOD_H1, Asian_ADXPeriod);
      g_mrAtrH  = iATR(_Symbol, PERIOD_M15, 14);   // ATR(14) utk regime volatilitas
      okBase = okBase && (g_mrEmaH1 != INVALID_HANDLE && g_mrAdxH1 != INVALID_HANDLE && g_mrAtrH != INVALID_HANDLE);
   }
   return(okBase);
}

void Asian_Deinit()
{
   if(g_asBBH  != INVALID_HANDLE) IndicatorRelease(g_asBBH);
   if(g_asRSIH != INVALID_HANDLE) IndicatorRelease(g_asRSIH);
   if(g_asADXH != INVALID_HANDLE) IndicatorRelease(g_asADXH);
   if(g_mrEmaH1 != INVALID_HANDLE) IndicatorRelease(g_mrEmaH1);
   if(g_mrAdxH1 != INVALID_HANDLE) IndicatorRelease(g_mrAdxH1);
   if(g_mrAtrH  != INVALID_HANDLE) IndicatorRelease(g_mrAtrH);
}

//+------------------------------------------------------------------+
//| BREAKOUT: Donchian channel + ADX trend (searah momentum)         |
//| BUY  : close[1] tembus di ATAS high channel bar-bar sebelumnya   |
//| SELL : close[1] tembus di BAWAH low channel                      |
//| Filter: ADX cukup tinggi & (opsional) naik; channel tdk sempit.  |
//+------------------------------------------------------------------+
int Asian_SignalBreakout(const SAurumnSpec &spec, double atrPips, double &slPips, double &tpPips)
{
   slPips = 0.0; tpPips = 0.0;

   //--- ADX shift 1 & 2 (untuk cek rising)
   double adx[];
   ArraySetAsSeries(adx, true);
   if(CopyBuffer(g_asADXH, 0, 1, 2, adx) < 2) return(0);
   bool adxOK = (adx[0] >= AsianBO_ADXMin) &&
                (!AsianBO_RequireADXRising || adx[0] > adx[1]);
   if(!adxOK) return(0);

   //--- Channel high/low dari bar SEBELUM bar sinyal (start=2, jadi tdk lookahead)
   int hiIdx = iHighest(_Symbol, PERIOD_M15, MODE_HIGH, AsianBO_Channel, 2);
   int loIdx = iLowest(_Symbol, PERIOD_M15, MODE_LOW,  AsianBO_Channel, 2);
   if(hiIdx < 0 || loIdx < 0) return(0);
   double chHigh = iHigh(_Symbol, PERIOD_M15, hiIdx);
   double chLow  = iLow(_Symbol, PERIOD_M15, loIdx);

   //--- Filter kualitas: channel tidak boleh terlalu sempit (hindari false break)
   double chHeightPips = (chHigh - chLow) / spec.pip;
   if(chHeightPips < AsianBO_MinChannelATR * atrPips) return(0);

   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   bool buy  = (close1 > chHigh);
   bool sell = (close1 < chLow);
   if(!buy && !sell) return(0);

   slPips = atrPips * Asian_SLMultiplier;
   tpPips = slPips * Asian_RR;
   return(buy ? 1 : -1);
}

//+------------------------------------------------------------------+
//| MEAN-REVERSION: BB + RSI (versi lama, untuk A/B)                 |
//+------------------------------------------------------------------+
int Asian_SignalMeanRev(const SAurumnSpec &spec, double atrPips, double &slPips, double &tpPips)
{
   slPips = 0.0; tpPips = 0.0;

   //--- BB shift 1 (0=tengah, 1=atas, 2=bawah)
   double mid[], up[], lo[];
   ArraySetAsSeries(mid, true); ArraySetAsSeries(up, true); ArraySetAsSeries(lo, true);
   if(CopyBuffer(g_asBBH, 0, 1, 1, mid) < 1) return(0);
   if(CopyBuffer(g_asBBH, 1, 1, 1, up)  < 1) return(0);
   if(CopyBuffer(g_asBBH, 2, 1, 1, lo)  < 1) return(0);
   double bbMid = mid[0], bbUpper = up[0], bbLower = lo[0];

   //--- RSI shift 1 & 2
   double rsi[];
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(g_asRSIH, 0, 1, 2, rsi) < 2) return(0);

   //--- ADX M15 shift 1: filter ranging dasar (tetap)
   double adx[];
   ArraySetAsSeries(adx, true);
   if(CopyBuffer(g_asADXH, 0, 1, 1, adx) < 1) return(0);
   if(adx[0] >= Asian_ADXMaxTrend) return(0);

   //--- v2 FILTER #3: KONTRAKSI VOLATILITAS - hanya range sejati, bukan ekspansi.
   //    Menyerang kegagalan lama (SL 71-222 pips dari ATR besar/directional).
   if(MR_UseVolContraction)
   {
      int need = (int)MathMax(2, MR_VolAvgPeriod);
      double atrBuf[];
      ArraySetAsSeries(atrBuf, true);
      if(CopyBuffer(g_mrAtrH, 0, 1, need, atrBuf) < need) return(0);
      double sum = 0.0;
      for(int i = 0; i < need; i++) sum += atrBuf[i];
      double atrAvg = sum / need;
      if(atrAvg > 0.0 && atrBuf[0] > MR_VolMaxRatio * atrAvg) return(0);
   }

   //--- Harga & range bar sinyal (shift 1)
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double high1  = iHigh(_Symbol, PERIOD_M15, 1);
   double low1   = iLow(_Symbol, PERIOD_M15, 1);

   int hiIdx = iHighest(_Symbol, PERIOD_M15, MODE_HIGH, Asian_RangeLookback, 1);
   int loIdx = iLowest(_Symbol, PERIOD_M15, MODE_LOW, Asian_RangeLookback, 1);
   if(hiIdx < 0 || loIdx < 0) return(0);
   double rangeHigh = iHigh(_Symbol, PERIOD_M15, hiIdx);
   double rangeLow  = iLow(_Symbol, PERIOD_M15, loIdx);
   double range = rangeHigh - rangeLow;
   if(range <= 0) return(0);
   double posInRange = (close1 - rangeLow) / range;

   //--- (v2.3.1) edge-zone kini OPSIONAL (default OFF): pierce BB sudah = ekstrem
   bool edgeBuyOK  = (!Asian_UseEdgeZone) || (posInRange <= Asian_EdgeZone);
   bool edgeSellOK = (!Asian_UseEdgeZone) || (posInRange >= (1.0 - Asian_EdgeZone));

   bool rsiTurnUp   = (!Asian_RequireRSITurn) || (rsi[0] > rsi[1]);
   bool rsiTurnDown = (!Asian_RequireRSITurn) || (rsi[0] < rsi[1]);

   //--- ENTRY: v2 FILTER #2 = wajib bar TOLAK band (wick), bukan nge-fade momentum.
   bool buy = false, sell = false;
   if(MR_RequireRejection)
   {
      double rsiHi = 100.0 - MR_RSI_Reject;
      buy  = (low1  < bbLower) && (close1 > bbLower) && (rsi[0] < MR_RSI_Reject) && rsiTurnUp   && edgeBuyOK;
      sell = (high1 > bbUpper) && (close1 < bbUpper) && (rsi[0] > rsiHi)         && rsiTurnDown && edgeSellOK;
   }
   else
   {
      buy  = (close1 < bbLower) && (rsi[0] < Asian_RSIOversold)   && rsiTurnUp   && edgeBuyOK;
      sell = (close1 > bbUpper) && (rsi[0] > Asian_RSIOverbought) && rsiTurnDown && edgeSellOK;
   }
   if(!buy && !sell) return(0);

   //--- v2 FILTER #1: VETO fade LAWAN tren H1 (anti pisau-jatuh - kegagalan utama 9 Mar).
   if(MR_UseTrendFilter)
   {
      double emaH1[], adxH1[];
      ArraySetAsSeries(emaH1, true); ArraySetAsSeries(adxH1, true);
      if(CopyBuffer(g_mrEmaH1, 0, 1, 3, emaH1) < 3) return(0);
      if(CopyBuffer(g_mrAdxH1, 0, 1, 1, adxH1) < 1) return(0);
      bool h1Trending = (adxH1[0] >= MR_TrendADXMin);
      bool h1Up   = (emaH1[0] > emaH1[2]);
      bool h1Down = (emaH1[0] < emaH1[2]);
      if(h1Trending && h1Down && buy)  return(0);   // jangan BUY-fade saat H1 turun kuat
      if(h1Trending && h1Up   && sell) return(0);   // jangan SELL-fade saat H1 naik kuat
   }

   //--- SL ATR; TP: v2 FILTER #4 = target BB-tengah (mean) bila MR_TPMode=1.
   slPips = atrPips * Asian_SLMultiplier;
   if(MR_TPMode == 1)
   {
      double tpDistPips = (buy ? (bbMid - close1) : (close1 - bbMid)) / spec.pip;
      tpPips = (tpDistPips > slPips * 0.5) ? tpDistPips : slPips * Asian_RR;
   }
   else
   {
      tpPips = slPips * Asian_RR;
   }
   return(buy ? 1 : -1);
}

//+------------------------------------------------------------------+
//| Dispatcher sinyal sesi Asia                                      |
//+------------------------------------------------------------------+
int Asian_Signal(const SAurumnSpec &spec, double atrPips, double &slPips, double &tpPips)
{
   slPips = 0.0; tpPips = 0.0;
   if(atrPips <= 0) return(0);
   if(Asian_Strategy == STRAT_BREAKOUT)
      return(Asian_SignalBreakout(spec, atrPips, slPips, tpPips));
   return(Asian_SignalMeanRev(spec, atrPips, slPips, tpPips));
}

#endif // AURUMN_STRATEGY_ASIAN_MQH
