//+------------------------------------------------------------------+
//|                                      AurumnStrategy_European.mqh  |
//|        SESI EROPA (London murni) - ROMBAK PENUH                  |
//|                                                                  |
//|        JAM (server HFM, KONSTAN sepanjang tahun):               |
//|        London open = 10:00 server, NY open = 15:00 server.       |
//|        DST Inggris (BST) & DST server HFM saling meniadakan,     |
//|        jadi jam server TIDAK bergeser winter<->summer.           |
//|        (Dibuktikan proyek: shift +1 summer = rugi -209;          |
//|         jam konstan = +175. Jangan tambah shift.)               |
//|        Europe murni = 10-15 (London open s/d NY open),          |
//|        TERPISAH dari overlap (15-19) & Asia (0-8).              |
//|                                                                  |
//|        DUA MODE (Euro_Mode), sesuai karakter London:            |
//|        1) BREAKOUT - tembus range Asia di awal London.          |
//|        2) SWEEP    - "London Sweep": harga sapu high/low Asia    |
//|           (ambil likuiditas) lalu reversal. Fade sapuan itu.     |
//+------------------------------------------------------------------+
#ifndef AURUMN_STRATEGY_EUROPEAN_MQH
#define AURUMN_STRATEGY_EUROPEAN_MQH
#include <AurumnSymbolSpec.mqh>

enum EuroLondonMode
{
   EURO_BREAKOUT = 0,   // Tembus range Asia (continuation)
   EURO_SWEEP    = 1    // Fade London Sweep (reversal)
};

input group "=== SESI EROPA (London murni): MODE ==="
input EuroLondonMode Euro_Mode = EURO_BREAKOUT; // Strategi London aktif

input group "--- Range Asia (acuan, jam server konstan) ---"
input int    Euro_AsianStart       = 0;     // Mulai range Asia (server)
input int    Euro_AsianEnd         = 8;     // Selesai range Asia (server)
input int    Euro_EntryWindowEnd   = 15;    // Entry hanya SEBELUM jam ini (15=full London murni; persempit utk awal saja)

input group "--- Mode BREAKOUT ---"
input double Euro_BreakBufferATR    = 0.15;  // Filter false-break: tembus > x ATR di luar range

input group "--- Mode SWEEP (London Sweep) ---"
input double Euro_SweepPenetrATR    = 0.10;  // Sapuan min di luar range (x ATR) utk dihitung sweep

input group "--- Umum Sesi Eropa ---"
input double Euro_ADXMin            = 25.0; // ADX minimal (= c.xlsx)
input bool   Euro_RequireADXRising  = true; // ADX harus naik (= c.xlsx)
input int    Euro_ADXPeriod         = 14;   // Periode ADX
input double Euro_SLMultiplier      = 2.0;  // SL = ATR x mult
input double Euro_RR                = 2.0;  // Risk:Reward
input bool   Euro_RunnerMode        = false; // RUNNER London: tanpa TP tetap, biarkan tren jalan (uji pertumbuhan)
input double Euro_Run_TrailStartATR = 1.5;   // RUNNER: mulai trailing lebih dini (lindungi profit tanpa TP)
input double Euro_Run_TrailDistATR  = 2.5;   // RUNNER: jarak trailing (beri ruang tren besar lari)
input double Euro_RiskFactor        = 1.0;  // Faktor sizing sesi

int g_euADXH = INVALID_HANDLE;
int g_euDstShift = 0;   // di-set EA tiap tick = SessionDstShift() (0 bila toggle off)

bool Euro_Init()
{
   g_euADXH = iADX(_Symbol, PERIOD_M15, Euro_ADXPeriod);
   return(g_euADXH != INVALID_HANDLE);
}
void Euro_Deinit()
{
   if(g_euADXH != INVALID_HANDLE) IndicatorRelease(g_euADXH);
}

bool Euro_ADXOK()
{
   double adx[];
   ArraySetAsSeries(adx, true);
   if(CopyBuffer(g_euADXH, 0, 1, 2, adx) < 2) return(false);
   return((adx[0] >= Euro_ADXMin) && (!Euro_RequireADXRising || adx[0] > adx[1]));
}

//--- Range sesi Asia hari ini (high/low). Stateless: telusuri bar mundur.
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
      int eh = dt.hour - g_euDstShift;
      bool inAsia = (eh >= Euro_AsianStart && eh < Euro_AsianEnd);
      if(inAsia)
      {
         double bh = iHigh(_Symbol, PERIOD_M15, i);
         double bl = iLow(_Symbol, PERIOD_M15, i);
         if(bh > hi) hi = bh;
         if(bl < lo) lo = bl;
         found = true;
      }
      else if(found) break;
   }
   if(!found || hi <= lo) return(false);
   rH = hi; rL = lo;
   return(true);
}

//--- Masih di window entry awal London?
bool Euro_InEntryWindow()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   return((dt.hour - g_euDstShift) < Euro_EntryWindowEnd);
}

//+------------------------------------------------------------------+
//| MODE BREAKOUT: tembus FRESH di luar range Asia + buffer + ADX   |
//+------------------------------------------------------------------+
int Euro_SignalBreakout(const SAurumnSpec &spec, double atrPips, double &slPips, double &tpPips)
{
   slPips = 0.0; tpPips = 0.0;
   if(!Euro_InEntryWindow()) return(0);
   if(!Euro_ADXOK()) return(0);

   double rH, rL;
   if(!Euro_GetAsianRange(rH, rL)) return(0);

   double atrPrice = atrPips * spec.pip;
   double buffer   = Euro_BreakBufferATR * atrPrice;
   double up = rH + buffer, dn = rL - buffer;

   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double close2 = iClose(_Symbol, PERIOD_M15, 2);
   bool buy  = (close1 > up) && (close2 <= up);   // breakout FRESH ke atas
   bool sell = (close1 < dn) && (close2 >= dn);   // breakout FRESH ke bawah
   if(!buy && !sell) return(0);

   slPips = atrPips * Euro_SLMultiplier;
   tpPips = Euro_RunnerMode ? 0.0 : slPips * Euro_RR;   // RUNNER: 0 = tanpa TP
   return(buy ? 1 : -1);
}

//+------------------------------------------------------------------+
//| MODE SWEEP: bar menyapu di luar range Asia lalu CLOSE balik ke  |
//| dalam (rejection) -> entry arah reversal. Fade London Sweep.    |
//+------------------------------------------------------------------+
int Euro_SignalSweep(const SAurumnSpec &spec, double atrPips, double &slPips, double &tpPips)
{
   slPips = 0.0; tpPips = 0.0;
   if(!Euro_InEntryWindow()) return(0);

   double rH, rL;
   if(!Euro_GetAsianRange(rH, rL)) return(0);

   double atrPrice = atrPips * spec.pip;
   double pen = Euro_SweepPenetrATR * atrPrice;

   double high1  = iHigh(_Symbol, PERIOD_M15, 1);
   double low1   = iLow(_Symbol, PERIOD_M15, 1);
   double close1 = iClose(_Symbol, PERIOD_M15, 1);

   //--- sapu HIGH lalu ditolak (close balik di bawah RH) -> SELL
   bool sweepHigh = (high1 > rH + pen) && (close1 < rH);
   //--- sapu LOW lalu ditolak (close balik di atas RL) -> BUY
   bool sweepLow  = (low1 < rL - pen)  && (close1 > rL);
   if(!sweepHigh && !sweepLow) return(0);

   slPips = atrPips * Euro_SLMultiplier;
   tpPips = Euro_RunnerMode ? 0.0 : slPips * Euro_RR;   // RUNNER: 0 = tanpa TP
   return(sweepHigh ? -1 : 1);
}

//+------------------------------------------------------------------+
//| Dispatcher                                                       |
//+------------------------------------------------------------------+
int Euro_Signal(const SAurumnSpec &spec, double atrPips, double &slPips, double &tpPips)
{
   slPips = 0.0; tpPips = 0.0;
   if(atrPips <= 0) return(0);
   if(Euro_Mode == EURO_SWEEP)
      return(Euro_SignalSweep(spec, atrPips, slPips, tpPips));
   return(Euro_SignalBreakout(spec, atrPips, slPips, tpPips));
}

#endif // AURUMN_STRATEGY_EUROPEAN_MQH
