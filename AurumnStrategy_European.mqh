//+------------------------------------------------------------------+
//|                                                  Aurumn_XAUUSD.mq5 |
//|                 EA UTAMA - XAUUSD(c) M15 - HFM Cent Account        |
//|                 Integrasi: Sesi 1 (Foundation) + Sesi 2 (Money Mgmt)|
//+------------------------------------------------------------------+
//  VERSION: v1.9.2
//    v1.0.0 - Sesi 1: Foundation, time mgmt HFM, trade engine, logging
//    v1.1.0 - Sesi 2: Money management (auto-lot, DD protection,
//             daily-loss limit, consecutive-loss guard, ATR sizing)
//    v1.2.0 - Sesi 3: Strategi Sesi Asia (mean reversion BB+RSI+ADX)
//    v1.2.1 - Fix: validator spek (denominasi USD/USC), entry sesi Asia
//    v1.2.2 - Fix: timezone/DST. Auto-DST kini TERSAMBUNG ke deteksi sesi
//             (sebelumnya dead code) & pakai TimeCurrent (valid di tester)
//    v1.2.3 - Sesi Asia: cooldown setelah loss + konfirmasi RSI turn
//    v1.3.0 - Rombak sesi Asia: tambah strategi BREAKOUT (Donchian+ADX)
//             searah momentum; mean-reversion lama jadi opsi toggle
//    v1.3.1 - Drawdown reset PER-SESI (ganti daily). Tiap sesi punya
//             baseline & halt sendiri; emergency 20% account-level tetap.
//    v1.4.0 - Sesi 4: Strategi Sesi Eropa (trend-following EMA+ADX)
//    v1.5.0 - Sesi 5: Strategi Sesi US (volatility breakout Keltner/ATR)
//    v1.6.0 - Sesi 6: Exit mgmt (breakeven, partial close, trailing - ATR)
//    v1.6.1 - Rombak EU & US ke BREAKOUT Donchian (EMA-cross/Keltner gagal);
//             US sizing 1.5x->1.0x; emergency DD recoverable (cooldown).
//    v1.6.2 - KOREKSI jam sesi ke jam pasar gold riil: London 10-19,
//             NY 15-24 (was 8-16, 13-21). EU/US sebelumnya salah jam.
//    v1.6.3 - FIX timezone: hapus DST-shift sesi (double-count). Jam sesi
//             TETAP sepanjang tahun krn server HFM sudah geser GMT+2->+3.
//    v1.6.4 - Europe: tambah ASIAN-RANGE BREAKOUT (sesuai karakter London;
//             tembus range Asia + filter false-break). Donchian jadi opsi.
//    v1.7.0 - Sesi 7: News filter (CSV utk tester + kalender MT5 live);
//             blokir entry & opsi close-on-news di window high-impact.
//    v1.7.1 - Tambah sesi OVERLAP London-NY (15-19), prioritas tertinggi.
//             Memisah overlap dari US -> ukur bagian US mana yg rugi.
//             Strategi overlap: Donchian breakout. Array per-sesi 3->4.
//    v1.8.0 - Sesi 8: Proteksi lanjutan. Weekend-close (hindari gap Senin),
//             cutoff entry Jumat, delay Senin, filter libur.
//    v1.9.0 - Sesi 9: Telegram (live). Notif buka/tutup/harian/alert,
//             perintah /status /pause /resume /closeall via getUpdates.
//    v1.9.1 - Europe: window breakout awal London (EuroAR_BreakoutWindowEnd).
//             Mulai kampanye optimasi per-sesi: Europe -> Overlap -> NY.
//    v1.9.2 - Europe ROMBAK: London murni 10-15 TERPISAH dari overlap (15-19)
//             & US (19-24), jam server konstan. 2 mode: BREAKOUT + SWEEP.
//  PRASYARAT: Letakkan AurumnSymbolSpec.mqh, AurumnStrategy_Asian.mqh,
//             AurumnStrategy_European.mqh,
//             AurumnStrategy_US.mqh,
//             AurumnStrategy_Overlap.mqh,
//             AurumnNewsFilter.mqh,
//             AurumnProtection.mqh,
//             AurumnTelegram.mqh di folder MQL5/Include/
//+------------------------------------------------------------------+
#property copyright "Aurumn EA"
#property version   "1.92"
#property strict
#property description "Aurumn XAUUSDc M15 - Foundation + Money Mgmt + Sesi Asia (HFM Cent)"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <AurumnSymbolSpec.mqh>        // modul spek terkalibrasi (Sesi spec)
#include <AurumnStrategy_Asian.mqh>    // SESI 3: strategi sesi Asia
#include <AurumnStrategy_European.mqh> // SESI 4: strategi sesi Eropa
#include <AurumnStrategy_US.mqh>       // SESI 5: strategi sesi US
#include <AurumnStrategy_Overlap.mqh>  // SESI OVERLAP London-NY
#include <AurumnNewsFilter.mqh>        // SESI 7: news filter
#include <AurumnProtection.mqh>        // SESI 8: proteksi weekend/holiday
#include <AurumnTelegram.mqh>          // SESI 9: telegram notif + kontrol

CTrade        trade;
CPositionInfo posInfo;

//--- Mode operasi: menentukan keagresifan money management
enum AurumnMode
{
   MODE_DEFENSIVE  = 0,   // Bertahan: risk kecil, proteksi kuat
   MODE_BALANCED   = 1,   // Seimbang
   MODE_AGGRESSIVE = 2    // Kejar target: risk besar (cepat tumbuh / cepat habis)
};

//+------------------------------------------------------------------+
//| INPUT                                                            |
//+------------------------------------------------------------------+

//=== UMUM ===
input long   MagicNumber        = 20260620;   // Magic number
input int    Slippage           = 30;         // Slippage (points)
input string TradeComment       = "Aurumn";   // Komentar order

//=== MONEY MANAGEMENT (SESI 2) ===
input AurumnMode InpTradeMode   = MODE_BALANCED; // Mode operasi
input bool   AutoLotSizing      = true;       // Auto lot dari risk %
input double RiskPercentage     = 2.5;        // Risk per trade (%) - basis
input double FixedLotSize       = 0.01;       // Lot tetap (jika auto = false)
input double MaxSessionLoss      = 15.0;       // Loss limit PER SESI (%) - reset tiap sesi mulai
input double MaxDailyLoss        = 0.0;        // Cap loss harian SELURUH sesi (0 = OFF)
input double MaxDrawdown        = 20.0;       // Emergency stop bila DD >= (%)
input double EmergencyCooldownHours = 24.0;   // Jam cooldown emergency lalu lanjut (0=permanen)
input int    AtrPeriod          = 14;         // Periode ATR (M15)
input double AtrSLMultiplier    = 1.5;        // SL = ATR x mult
input double RiskRewardRatio    = 1.5;        // TP = SL x RR
input bool   EnableDrawdownReduce = true;     // Auto-kurangi lot saat DD naik
input double DDReduceStartPct   = 10.0;       // Mulai kurangi risk di DD ini (%)
input double DDReduceFloorMult  = 0.25;       // Risk minimal (x) saat DD parah
input int    ConsecLossTrigger  = 3;          // Kurangi risk setelah N loss beruntun
input double ConsecLossFactor   = 0.5;        // Faktor pengali risk per loss ekstra
input int    EntryCooldownBars  = 8;          // Jeda bar M15 setelah LOSS sebelum entry lagi (0=off)

//=== SESI 6: EXIT MANAGEMENT (berlaku semua sesi, berbasis ATR) ===
input bool   UseBreakeven       = true;       // Pindah SL ke breakeven saat profit
input double BE_TriggerATR      = 1.0;        // Trigger BE saat profit >= x ATR
input double BE_BufferPips      = 2.0;        // Buffer BE di atas/bawah entry (pips)
input bool   UsePartialClose    = true;       // Tutup sebagian saat profit
input double Partial_TriggerATR = 1.0;        // Trigger partial saat profit >= x ATR
input double Partial_Percent    = 50.0;       // % volume yang ditutup
input bool   UseTrailingStop    = true;       // Trailing stop aktif
input double Trail_StartATR     = 1.5;        // Mulai trailing saat profit >= x ATR
input double Trail_DistATR      = 1.5;        // Jarak trailing di belakang harga (x ATR)

//=== TEST SIGNAL (PLACEHOLDER - hanya untuk menguji MM, BUKAN strategi nyata) ===
input bool   EnableTestSignal   = false;      // Aktifkan sinyal uji (EMA cross)
input int    TestEmaFast        = 20;         // EMA cepat (uji)
input int    TestEmaSlow        = 50;         // EMA lambat (uji)

//=== SESSION (jam = waktu server HFM GMT+2/+3) ===
input bool   TradeAsianSession    = true;
input bool   TradeEuropeanSession = true;
input bool   TradeUSSession       = true;
input bool   TradeOverlapSession  = true;
//--- Jam sesi WAKTU SERVER HFM, KONSTAN sepanjang tahun.
//    DST Inggris (BST) & DST server HFM saling meniadakan -> jam server TETAP.
//    (Dibuktikan: shift +1 summer = rugi; jam konstan = profit. v1.6.3)
//    Sesi TERPISAH bersih (non-overlap), tiap jam = satu sesi:
//    Asia 00-08 | Europe murni 10-15 | Overlap 15-19 | NY-akhir 19-24.
//    London open=10, NY open=15 (server, konstan). Lull 08-10 tak ditradingkan.
input int    AsianSessionStart    = 0;        // Asia mulai (Tokyo)
input int    AsianSessionEnd      = 8;        // Asia selesai
input int    EuropeanSessionStart = 10;       // London open (server, konstan)
input int    EuropeanSessionEnd   = 15;       // London murni selesai = NY open (server)
input int    USSessionStart       = 19;       // NY-akhir mulai (setelah overlap)
input int    USSessionEnd         = 24;       // NY selesai (~00:00 server)
input int    OverlapSessionStart  = 15;       // Overlap London-NY mulai (NY open, server)
input int    OverlapSessionEnd    = 19;       // Overlap London-NY selesai (server)

//=== SPREAD ===
input double MaxSpreadPips       = 4.1;        // Spread maksimal (pips)
input bool   CustomSpread        = false;
input double CustomSpreadValue   = 4.1;

//=== TIME / DST ===
input int    ServerTimeZoneBase  = 2;          // Offset GMT dasar (winter)
input bool   AutoDetectDST       = true;       // Auto +1 saat summer

//=== LOGGING ===
input bool   EnableFileLog       = true;
input int    LogLevel            = 2;          // 0=OFF 1=ERR 2=INFO 3=DEBUG

//+------------------------------------------------------------------+
//| GLOBAL                                                           |
//+------------------------------------------------------------------+
SAurumnSpec g_spec;                 // spek simbol aktual
int         g_logHandle  = INVALID_HANDLE;
datetime    g_lastBarTime = 0;
int         g_atrHandle  = INVALID_HANDLE;
int         g_emaFastH   = INVALID_HANDLE;
int         g_emaSlowH   = INVALID_HANDLE;

//--- State risk
double      g_equityPeak   = 0.0;
double      g_dayStartEquity = 0.0;
int         g_currentDay   = -1;
bool        g_emergencyHalt = false;   // dari drawdown maksimal account-level (persist)
datetime    g_emergencyHaltTime = 0;   // waktu emergency fire (untuk cooldown)
bool        g_dailyHalt     = false;   // dari cap harian opsional (reset tiap hari)
//--- State per-sesi: index 0=ASIA, 1=EUROPE, 2=US
double      g_sessBaseEquity[4] = {0,0,0,0};  // equity saat sesi mulai
bool        g_sessHalt[4]       = {false,false,false,false}; // halt per sesi (reset saat sesi mulai)
int         g_lastSummaryDay        = -1;    // hari terakhir kirim ringkasan Telegram
double      g_daySummaryStartBalance = 0;    // saldo awal hari (utk P/L harian)
string      g_curSession        = "NONE";   // sesi aktif terakhir (deteksi pergantian)
ulong       g_partialTickets[];            // tiket yang sudah partial-close (Sesi 6)

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.LogLevel(LOG_LEVEL_ERRORS);

   if(EnableFileLog)
   {
      g_logHandle = FileOpen("Aurumn_" + _Symbol + "_log.txt",
                             FILE_WRITE|FILE_READ|FILE_TXT|FILE_ANSI);
      if(g_logHandle != INVALID_HANDLE) FileSeek(g_logHandle, 0, SEEK_END);
   }

   //--- Muat & validasi spek simbol
   if(!LoadAurumnSpec(_Symbol, g_spec))
   {
      Log(1, "Gagal memuat spek simbol " + _Symbol);
      return(INIT_FAILED);
   }
   string warn;
   if(!AurumnValidateSpec(g_spec, warn))
      Log(1, "PERINGATAN spek: " + warn);

   //--- Handle indikator
   g_atrHandle = iATR(_Symbol, PERIOD_M15, AtrPeriod);
   if(g_atrHandle == INVALID_HANDLE)
   { Log(1, "Gagal membuat handle ATR."); return(INIT_FAILED); }

   if(EnableTestSignal)
   {
      g_emaFastH = iMA(_Symbol, PERIOD_M15, TestEmaFast, 0, MODE_EMA, PRICE_CLOSE);
      g_emaSlowH = iMA(_Symbol, PERIOD_M15, TestEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
      if(g_emaFastH == INVALID_HANDLE || g_emaSlowH == INVALID_HANDLE)
      { Log(1, "Gagal membuat handle EMA uji."); return(INIT_FAILED); }
   }

   //--- Inisialisasi strategi sesi Asia (SESI 3)
   if(!Asian_Init())
   { Log(1, "Gagal inisialisasi strategi sesi Asia."); return(INIT_FAILED); }
   Log(2, "Strategi Asia: " +
          (Asian_Strategy == STRAT_BREAKOUT ? "BREAKOUT (Donchian+ADX)" : "MEAN-REVERSION (BB+RSI)"));

   //--- Inisialisasi strategi sesi Eropa (SESI 4)
   if(!Euro_Init())
   { Log(1, "Gagal inisialisasi strategi sesi Eropa."); return(INIT_FAILED); }
   Log(2, "Strategi Eropa (London murni 10-15): " +
          (Euro_Mode == EURO_SWEEP ? "SWEEP (fade London Sweep)"
                                   : "BREAKOUT (tembus range Asia)") +
          " | range Asia jam " + IntegerToString(Euro_AsianStart) + "-" +
          IntegerToString(Euro_AsianEnd) + " | window<" + IntegerToString(Euro_EntryWindowEnd));

   //--- Inisialisasi strategi sesi US (SESI 5)
   if(!US_Init())
   { Log(1, "Gagal inisialisasi strategi sesi US."); return(INIT_FAILED); }
   Log(2, "Strategi US: BREAKOUT (Donchian " + IntegerToString(US_Channel) + " + ADX)");

   //--- Inisialisasi strategi overlap London-NY
   if(TradeOverlapSession)
   {
      if(!Overlap_Init()) { Log(0, "GAGAL init Overlap (ADX handle)."); return(INIT_FAILED); }
      Log(2, "Strategi Overlap: BREAKOUT (Donchian " + IntegerToString(Overlap_Channel) +
             " + ADX) | jam " + IntegerToString(OverlapSessionStart) + "-" +
             IntegerToString(OverlapSessionEnd));
   }

   //--- Inisialisasi news filter (SESI 7)
   News_Init();
   if(EnableNewsFilter)
      Log(2, "News Filter : ON | " + IntegerToString(News_Count()) + " event | window -" +
             IntegerToString(News_MinutesBefore) + "/+" + IntegerToString(News_MinutesAfter) + " menit" +
             (News_ClosePositions ? " | close-on-news" : ""));
   else
      Log(2, "News Filter : OFF");

   //--- Inisialisasi proteksi lanjutan (SESI 8)
   Protection_Init();
   Log(2, "Proteksi    : " + (UseWeekendClose ? "weekend-close H" + IntegerToString(WeekendCloseDay) +
          " jam" + IntegerToString(WeekendCloseHour) : "weekend OFF") +
          (NoNewTradesFriday ? " | cutoff Jum jam" + IntegerToString(FridayCutoffHour) : "") +
          (UseHolidayFilter ? " | " + IntegerToString(Protection_HolidayCount()) + " libur" : ""));

   //--- Inisialisasi Telegram (SESI 9, live saja)
   Telegram_Init();
   if(UseTelegram)
   {
      Log(2, "Telegram    : ON" + (Telegram_AllowCommands ? " | perintah aktif (poll " +
             IntegerToString(Telegram_PollSeconds) + "s)" : " | notif saja"));
      if(Telegram_AllowCommands && Telegram_PollSeconds > 0)
         EventSetTimer(Telegram_PollSeconds);
   }

   //--- Inisialisasi state risk
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   g_equityPeak     = eq;
   g_dayStartEquity = eq;
   g_currentDay     = -1;
   g_emergencyHalt  = false;
   g_dailyHalt      = false;
   g_curSession     = "NONE";
   for(int s = 0; s < 4; s++) { g_sessBaseEquity[s] = eq; g_sessHalt[s] = false; }

   //--- Cek izin trading
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      Log(1, "PERINGATAN: AutoTrading nonaktif.");

   //--- Ringkasan
   Log(2, "===== AURUMN EA v1.9.2 INIT =====");
   Log(2, "Simbol     : " + _Symbol + " | Cent: " + (g_spec.isCent ? "YA" : "TIDAK") +
          " | Cur: " + g_spec.accCurrency);
   Log(2, "Pip        : " + DoubleToString(g_spec.pip, g_spec.digits) +
          " | PipVal/lot: " + DoubleToString(g_spec.pipValuePerLot, 2) + " " + g_spec.accCurrency);
   Log(2, "MinStop    : " + IntegerToString(g_spec.minStopPoints) + " points");
   Log(2, "Mode       : " + EnumToString(InpTradeMode) +
          " | RiskBasis: " + DoubleToString(RiskPercentage, 2) + "%");
   Log(2, "ServerTime : GMT+" + IntegerToString(CurrentServerGMTOffset()) +
          (IsServerInDST() ? " (summer)" : " (winter)") +
          " | Jam sesi TETAP (London 10:00, NY 15:00)");
   Log(2, "Equity     : " + DoubleToString(eq, 2) + " " + g_spec.accCurrency);
   Log(2, "Proteksi   : SessionLoss " + (MaxSessionLoss > 0 ? DoubleToString(MaxSessionLoss, 1) + "%" : "OFF") +
          " (per-sesi) | DailyCap " + (MaxDailyLoss > 0 ? DoubleToString(MaxDailyLoss, 1) + "%" : "OFF") +
          " | EmergDD " + DoubleToString(MaxDrawdown, 1) + "%/" + DoubleToString(EmergencyCooldownHours,0) + "h (account)");
   Log(2, "Exit Mgmt  : BE " + (UseBreakeven ? "ON" : "off") +
          " | Partial " + (UsePartialClose ? DoubleToString(Partial_Percent, 0) + "%" : "off") +
          " | Trail " + (UseTrailingStop ? "ON" : "off"));
   if(EnableTestSignal)
      Log(2, "CATATAN: TestSignal AKTIF (EMA cross) - ini placeholder uji MM, bukan strategi final.");
   Log(2, "=================================");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_emaFastH  != INVALID_HANDLE) IndicatorRelease(g_emaFastH);
   if(g_emaSlowH  != INVALID_HANDLE) IndicatorRelease(g_emaSlowH);
   Asian_Deinit();
   Euro_Deinit();
   US_Deinit();
   Overlap_Deinit();
   News_Deinit();
   EventKillTimer();
   if(UseTelegram && Telegram_NotifyAlerts)
      Telegram_Send("Aurumn EA dihentikan (reason " + IntegerToString(reason) + ").");
   Log(2, "EA dihentikan. Reason: " + IntegerToString(reason));
   if(g_logHandle != INVALID_HANDLE) { FileClose(g_logHandle); g_logHandle = INVALID_HANDLE; }
}

//+------------------------------------------------------------------+
//| OnTimer - polling perintah Telegram (live)                      |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!UseTelegram || !Telegram_AllowCommands) return;
   Telegram_CheckCommands();

   //--- Tangani permintaan yg butuh data EA
   if(g_tgStatusRequested)
   {
      g_tgStatusRequested = false;
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
      Telegram_Send("STATUS Aurumn\nSaldo: " + DoubleToString(bal, 2) +
                    "\nEkuitas: " + DoubleToString(eq, 2) +
                    "\nFloating: " + DoubleToString(eq - bal, 2) +
                    "\nPosisi: " + IntegerToString(CountOurPositions()) +
                    "\nDrawdown: " + DoubleToString(CurrentDrawdownPct(), 1) + "%" +
                    "\nSesi: " + ActiveSessionName() +
                    "\nStatus: " + (Telegram_IsPaused() ? "DIJEDA" : "AKTIF"));
   }
   if(g_tgCloseAllRequested)
   {
      g_tgCloseAllRequested = false;
      int n = CountOurPositions();
      CloseOurPositions("telegram /closeall");
      Telegram_Send("/closeall - " + IntegerToString(n) + " posisi diperintahkan tutup.");
   }
}

//+------------------------------------------------------------------+
//| OnTradeTransaction - notif buka/tutup posisi (live)             |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(!UseTelegram || !Telegram_NotifyTrades) return;
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   ulong deal = trans.deal;
   if(deal == 0 || !HistoryDealSelect(deal)) return;
   if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) return;
   if((long)HistoryDealGetInteger(deal, DEAL_MAGIC) != MagicNumber) return;

   long   entry  = HistoryDealGetInteger(deal, DEAL_ENTRY);
   long   type   = HistoryDealGetInteger(deal, DEAL_TYPE);
   double vol    = HistoryDealGetDouble(deal, DEAL_VOLUME);
   double price  = HistoryDealGetDouble(deal, DEAL_PRICE);
   double profit = HistoryDealGetDouble(deal, DEAL_PROFIT);
   string dir    = (type == DEAL_TYPE_BUY) ? "BUY" : "SELL";

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
