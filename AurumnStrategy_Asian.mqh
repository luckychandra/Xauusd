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
input double Asian_BBDeviation   = 2.0;    // Deviasi BB
input int    Asian_RSIPeriod     = 14;     // Periode RSI
input double Asian_RSIOversold   = 30.0;   // Ambang RSI oversold
input double Asian_RSIOverbought = 70.0;   // Ambang RSI overbought
input bool   Asian_RequireRSITurn = true;  // Wajib RSI berbalik arah
input int    Asian_RangeLookback = 24;     // Bar untuk S/R range
input double Asian_EdgeZone      = 0.33;   // Harga di 33% tepi range
input double Asian_ADXMaxTrend   = 25.0;   // Trade hanya bila ADX < ini (ranging)

input group "--- Umum Sesi Asia ---"
input int    Asian_ADXPeriod     = 14;     // Periode ADX (dipakai kedua mode)
input double Asian_SLMultiplier  = 1.5;    // SL = ATR x mult
input double Asian_RR            = 1.5;    // Risk:Reward
input double Asian_RiskFactor    = 0.5;    // Pengurang sizing sesi Asia

//--- Handle indikator (file-scope)
int g_asBBH  = INVALID_HANDLE;
int g_asRSIH = INVALID_HANDLE;
int g_asADXH = INVALID_HANDLE;

//+------------------------------------------------------------------+
bool Asian_Init()
{
   g_asBBH  = iBands(_Symbol, PERIOD_M15, Asian_BBPeriod, 0, Asian_BBDeviation, PRICE_CLOSE);
   g_asRSIH = iRSI(_Symbol, PERIOD_M15, Asian_RSIPeriod, PRICE_CLOSE);
   g_asADXH = iADX(_Symbol, PERIOD_M15, Asian_ADXPeriod);
   return(g_asBBH != INVALID_HANDLE && g_asRSIH != INVALID_HANDLE && g_asADXH != INVALID_HANDLE);
}

void Asian_Deinit()
{
   if(g_asBBH  != INVALID_HANDLE) IndicatorRelease(g_asBBH);
   if(g_asRSIH != INVALID_HANDLE) IndicatorRelease(g_asRSIH);
   if(g_asADXH != INVALID_HANDLE) IndicatorRelease(g_asADXH);
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

   double up[], lo[];
   ArraySetAsSeries(up, true);
   ArraySetAsSeries(lo, true);
   if(CopyBuffer(g_asBBH, 1, 1, 1, up) < 1) return(0);
   if(CopyBuffer(g_asBBH, 2, 1, 1, lo) < 1) return(0);
   double bbUpper = up[0];
   double bbLower = lo[0];

   double rsi[];
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(g_asRSIH, 0, 1, 2, rsi) < 2) return(0);

   double adx[];
   ArraySetAsSeries(adx, true);
   if(CopyBuffer(g_asADXH, 0, 1, 1, adx) < 1) return(0);
   if(adx[0] >= Asian_ADXMaxTrend) return(0);

   double close1 = iClose(_Symbol, PERIOD_M15, 1);

   int hiIdx = iHighest(_Symbol, PERIOD_M15, MODE_HIGH, Asian_RangeLookback, 1);
   int loIdx = iLowest(_Symbol, PERIOD_M15, MODE_LOW,  Asian_RangeLookback, 1);
   if(hiIdx < 0 || loIdx < 0) return(0);
   double rangeHigh = iHigh(_Symbol, PERIOD_M15, hiIdx);
   double rangeLow  = iLow(_Symbol, PERIOD_M15, loIdx);
   double range = rangeHigh - rangeLow;
   if(range <= 0) return(0);
   double posInRange = (close1 - rangeLow) / range;

   bool rsiTurnUp   = (!Asian_RequireRSITurn) || (rsi[0] > rsi[1]);
   bool rsiTurnDown = (!Asian_RequireRSITurn) || (rsi[0] < rsi[1]);

   bool buy = (close1 < bbLower) && (rsi[0] < Asian_RSIOversold) && rsiTurnUp &&
              (posInRange <= Asian_EdgeZone);
   bool sell = (close1 > bbUpper) && (rsi[0] > Asian_RSIOverbought) && rsiTurnDown &&
               (posInRange >= (1.0 - Asian_EdgeZone));
   if(!buy && !sell) return(0);

   slPips = atrPips * Asian_SLMultiplier;
   tpPips = slPips * Asian_RR;
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
