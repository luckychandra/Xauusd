//+------------------------------------------------------------------+
//|                                                  Aurumn_XAUUSD.mq5 |
//|                 EA UTAMA - XAUUSD(c) M15 - HFM Cent Account        |
//|                 Integrasi: Sesi 1 (Foundation) + Sesi 2 (Money Mgmt)|
//+------------------------------------------------------------------+
//  VERSION: v1.9.5
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
//    v1.9.3 - DST: deteksi dinamis (last Sun Mar/Okt) utk offset. Tambah toggle
//             UseSessionDSTShift (default OFF) utk uji shift sesi vs jam konstan.
//    v1.9.4 - Kompatibilitas sesi: shift DST kini konsisten ke logika internal
//             Europe (range Asia & window) via g_euDstShift. Audit lolos.
//    v1.9.5 - Isi gap pra-London: sesi PRA-LONDON (Frankfurt 08-10), Donchian
//             breakout. Array per-sesi 4->5. Sesi kini: Asia/PraLondon/Europe/Overlap/NY.
//  PRASYARAT: Letakkan AurumnSymbolSpec.mqh, AurumnStrategy_Asian.mqh,
//             AurumnStrategy_European.mqh,
//             AurumnStrategy_US.mqh,
//             AurumnStrategy_Overlap.mqh,
//             AurumnStrategy_PreLondon.mqh, AurumnNewsFilter.mqh,
//             AurumnProtection.mqh,
//             AurumnTelegram.mqh di folder MQL5/Include/
//+------------------------------------------------------------------+
#property copyright "Aurumn EA"
#property version   "1.95"
#property strict
#property description "Aurumn XAUUSDc M15 - Foundation + Money Mgmt + Sesi Asia (HFM Cent)"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <AurumnSymbolSpec.mqh>        // modul spek terkalibrasi (Sesi spec)
#include <AurumnStrategy_Asian.mqh>    // SESI 3: strategi sesi Asia
#include <AurumnStrategy_European.mqh> // SESI 4: strategi sesi Eropa
#include <AurumnStrategy_US.mqh>       // SESI 5: strategi sesi US
#include <AurumnStrategy_Overlap.mqh>  // SESI OVERLAP London-NY
#include <AurumnStrategy_PreLondon.mqh> // SESI PRA-LONDON (Frankfurt 08-10)
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
input bool   TradePreLondonSession = true;
//--- Jam sesi WAKTU SERVER HFM, KONSTAN sepanjang tahun.
//    DST Inggris (BST) & DST server HFM saling meniadakan -> jam server TETAP.
//    (Dibuktikan: shift +1 summer = rugi; jam konstan = profit. v1.6.3)
//    Sesi TERPISAH bersih (non-overlap), tiap jam = satu sesi:
//    Asia 00-08 | Pra-London 08-10 | Europe murni 10-15 | Overlap 15-19 | NY-akhir 19-24.
//    London open=10, NY open=15 (server, konstan). Gap 08-10 kini diisi sesi Pra-London.
input int    AsianSessionStart    = 0;        // Asia mulai (Tokyo)
input int    AsianSessionEnd      = 8;        // Asia selesai
input int    PreLondonSessionStart = 8;       // Pra-London mulai (Frankfurt open)
input int    PreLondonSessionEnd   = 10;      // Pra-London selesai (London open)
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
input int    ServerTimeZoneBase  = 2;          // Offset GMT dasar (winter); offset live dideteksi dinamis
input bool   AutoDetectDST       = true;       // Deteksi DST dinamis (last Sun Mar/Okt) utk offset & log
input bool   UseSessionDSTShift  = false;      // (UJI) geser jam sesi +1 saat summer. Default OFF (jam server konstan = benar)

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
double      g_sessBaseEquity[5] = {0,0,0,0,0};  // equity saat sesi mulai
bool        g_sessHalt[5]       = {false,false,false,false,false}; // halt per sesi (reset saat sesi mulai)
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

   //--- Inisialisasi strategi pra-London (Frankfurt 08-10)
   if(TradePreLondonSession)
   {
      if(!PreLon_Init()) { Log(0, "GAGAL init PreLondon (ADX handle)."); return(INIT_FAILED); }
      Log(2, "Strategi Pra-London (08-10): BREAKOUT (Donchian " + IntegerToString(PreLon_Channel) + " + ADX)");
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
   for(int s = 0; s < 5; s++) { g_sessBaseEquity[s] = eq; g_sessHalt[s] = false; }

   //--- Cek izin trading
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      Log(1, "PERINGATAN: AutoTrading nonaktif.");

   //--- Ringkasan
   Log(2, "===== AURUMN EA v1.9.5 INIT =====");
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
   PreLon_Deinit();
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

   if(entry == DEAL_ENTRY_IN)
      Telegram_Send("BUKA " + dir + " " + DoubleToString(vol, 2) +
                    " lot @ " + DoubleToString(price, _Digits));
   else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
      Telegram_Send((profit >= 0 ? "TUTUP (+) " : "TUTUP (-) ") + DoubleToString(vol, 2) +
                    " lot @ " + DoubleToString(price, _Digits) +
                    " | P/L: " + DoubleToString(profit, 2));
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- State risk diperbarui tiap tick (lacak equity peak & halt)
   UpdateRiskState();

   //--- Kelola posisi terbuka tiap tick (breakeven/partial/trailing - Sesi 6)
   ManageOpenPositions();

   if(!IsNewBar()) return;

   //--- Ringkasan harian Telegram (Sesi 9) saat ganti hari
   if(UseTelegram && Telegram_NotifyDaily)
   {
      MqlDateTime dts; TimeToStruct(TimeCurrent(), dts);
      if(dts.day != g_lastSummaryDay)
      {
         double bal = AccountInfoDouble(ACCOUNT_BALANCE);
         if(g_lastSummaryDay >= 0)
            Telegram_Send("Ringkasan harian\nSaldo: " + DoubleToString(bal, 2) +
                          "\nP/L kemarin: " + DoubleToString(bal - g_daySummaryStartBalance, 2) +
                          "\nDrawdown: " + DoubleToString(CurrentDrawdownPct(), 1) + "%");
         g_lastSummaryDay = dts.day;
         g_daySummaryStartBalance = bal;
      }
   }

   //--- Tentukan sesi dulu (gating risk kini PER-SESI)
   string sesi = ActiveSessionName();
   if(sesi == "NONE") return;

   //--- Pause via Telegram (Sesi 9): jeda entry baru, posisi tetap dikelola
   if(Telegram_IsPaused())
   {
      Log(3, "Trading dijeda via Telegram - skip entry.");
      return;
   }

   //--- Gerbang risk: emergency global (account) + halt khusus sesi ini
   if(!TradingAllowed(sesi))
   {
      Log(3, "Entry sesi " + sesi + " dihentikan oleh proteksi risk.");
      return;
   }

   //--- Filter spread
   if(!SpreadOK())
   {
      Log(3, "Spread " + DoubleToString(CurrentSpreadPips(), 2) + " > limit. Skip.");
      return;
   }

   //--- Proteksi lanjutan (Sesi 8): blokir entry (weekend/cutoff Jumat/Senin/libur)
   if(Protection_BlockNewTrades(TimeCurrent()))
   {
      Log(3, "Proteksi aktif (weekend/libur) - skip entry.");
      return;
   }

   //--- News filter (Sesi 7): blokir entry di window news high-impact
   if(EnableNewsFilter && News_IsBlocked(TimeCurrent()))
   {
      Log(3, "News window aktif - skip entry.");
      return;
   }

   //--- Dapatkan sinyal dari strategi sesi yang aktif
   double atrPips = GetAtrPips();
   int    sig     = 0;
   double slPips  = 0.0;
   double tpPips  = 0.0;
   double sessRiskFactor = 1.0;
   g_euDstShift = SessionDstShift();   // sinkronkan shift DST ke modul Europe

   if(sesi == "ASIA")                          // SESI 3
   {
      sig = Asian_Signal(g_spec, atrPips, slPips, tpPips);
      sessRiskFactor = Asian_RiskFactor;
   }
   else if(sesi == "EUROPE")                   // SESI 4: trend-following
   {
      sig = Euro_Signal(g_spec, atrPips, slPips, tpPips);
      sessRiskFactor = Euro_RiskFactor;
   }
   else if(sesi == "US")                       // SESI 5: volatility breakout
   {
      sig = US_Signal(g_spec, atrPips, slPips, tpPips);
      sessRiskFactor = US_RiskFactor;
   }
   else if(sesi == "OVERLAP")                  // SESI OVERLAP London-NY: breakout
   {
      sig = Overlap_Signal(g_spec, atrPips, slPips, tpPips);
      sessRiskFactor = Overlap_RiskFactor;
   }
   else if(sesi == "PRELONDON")                // SESI PRA-LONDON (Frankfurt): breakout
   {
      sig = PreLon_Signal(g_spec, atrPips, slPips, tpPips);
      sessRiskFactor = PreLon_RiskFactor;
   }

   //--- Fallback uji MM bila tidak ada strategi sesi & TestSignal aktif
   if(sig == 0 && EnableTestSignal && atrPips > 0)
   {
      sig    = TestSignal();
      slPips = atrPips * AtrSLMultiplier;
      tpPips = slPips * RiskRewardRatio;
   }

   //--- Eksekusi bila ada sinyal valid, belum ada posisi, & tidak dalam cooldown
   if(sig != 0 && slPips > 0 && CountOurPositions() == 0 && !InLossCooldown())
   {
      double effRisk   = EffectiveRiskPercent() * sessRiskFactor;
      double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskMoney = balance * effRisk / 100.0;
      double lots      = AutoLotSizing
                         ? AurumnLotsFromRisk(g_spec, riskMoney, slPips)
                         : NormalizeLots(FixedLotSize);

      Log(2, "ENTRY " + (sig > 0 ? "BUY" : "SELL") + " | sesi " + sesi +
             " | effRisk " + DoubleToString(effRisk, 2) + "%" +
             " | SL " + DoubleToString(slPips, 1) + " pips" +
             " | lot " + DoubleToString(lots, 2));

      OpenTradeRiskBased(sig, lots, slPips, tpPips);
   }
   else
   {
      Log(3, "MM watch | sesi " + sesi +
             " | DD " + DoubleToString(CurrentDrawdownPct(), 1) + "%" +
             " | lossStreak " + IntegerToString(CountConsecutiveLosses()));
   }
}

//+------------------------------------------------------------------+
//| ============ MONEY MANAGEMENT (SESI 2) ============              |
//+------------------------------------------------------------------+

//--- Map nama sesi -> index (0=ASIA,1=EUROPE,2=US, -1=NONE)
int SessionIndex(string sess)
{
   if(sess == "ASIA")    return(0);
   if(sess == "EUROPE")  return(1);
   if(sess == "US")      return(2);
   if(sess == "OVERLAP") return(3);
   if(sess == "PRELONDON") return(4);
   return(-1);
}

//--- Perbarui state risk: equity peak, emergency DD (account-level),
//    cap harian opsional, dan loss PER SESI (reset saat tiap sesi mulai).
void UpdateRiskState()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   //--- Equity peak (high water mark) - basis emergency DD
   if(eq > g_equityPeak) g_equityPeak = eq;

   //--- Emergency drawdown ACCOUNT-LEVEL (selalu aktif, backstop semua sesi)
   double dd = CurrentDrawdownPct();
   if(!g_emergencyHalt && dd >= MaxDrawdown)
   {
      g_emergencyHalt = true;
      g_emergencyHaltTime = TimeCurrent();
      Log(1, "EMERGENCY HALT: Drawdown " + DoubleToString(dd, 2) +
             "% >= " + DoubleToString(MaxDrawdown, 2) + "%. SEMUA entry dihentikan" +
             (EmergencyCooldownHours > 0
                ? " (cooldown " + DoubleToString(EmergencyCooldownHours, 0) + " jam)." : " (permanen)."));
   }

   //--- Pemulihan emergency: setelah cooldown, reset & rebaseline peak (mulai segar).
   //    Mencegah EA "mati total" permanen. EmergencyCooldownHours=0 -> permanen.
   if(g_emergencyHalt && EmergencyCooldownHours > 0)
   {
      double hrsElapsed = (double)(TimeCurrent() - g_emergencyHaltTime) / 3600.0;
      if(hrsElapsed >= EmergencyCooldownHours)
      {
         g_emergencyHalt = false;
         g_equityPeak    = eq;   // baseline baru -> DD dihitung ulang dari sini
         Log(1, "EMERGENCY RESET: cooldown selesai. Trading lanjut, baseline equity = " +
                DoubleToString(eq, 2));
      }
   }

   //--- Cap loss harian OPSIONAL (0 = off). Bila aktif, membatasi seluruh sesi.
   if(MaxDailyLoss > 0)
   {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      int dayKey = dt.year * 1000 + dt.day_of_year;
      if(dayKey != g_currentDay)
      {
         g_currentDay     = dayKey;
         g_dayStartEquity = eq;
         g_dailyHalt      = false;
      }
      double dailyLoss = (g_dayStartEquity > 0)
                         ? (g_dayStartEquity - eq) / g_dayStartEquity * 100.0 : 0.0;
      if(!g_dailyHalt && dailyLoss >= MaxDailyLoss)
      {
         g_dailyHalt = true;
         Log(1, "DAILY CAP HALT: Loss harian " + DoubleToString(dailyLoss, 2) +
                "% >= " + DoubleToString(MaxDailyLoss, 2) + "%.");
      }
   }

   //--- Tracking PER SESI: reset baseline & halt saat sesi berganti
   string sess = ActiveSessionName();
   int idx = SessionIndex(sess);
   if(idx >= 0)
   {
      if(sess != g_curSession)   // sesi baru mulai -> reset baseline & halt sesi ini
      {
         g_curSession          = sess;
         g_sessBaseEquity[idx] = eq;
         g_sessHalt[idx]       = false;
         Log(2, "== Sesi mulai: " + sess + " == Equity awal sesi: " + DoubleToString(eq, 2) +
                " | server GMT+" + IntegerToString(CurrentServerGMTOffset()));
      }
      double sessLoss = (g_sessBaseEquity[idx] > 0)
                        ? (g_sessBaseEquity[idx] - eq) / g_sessBaseEquity[idx] * 100.0 : 0.0;
      if(!g_sessHalt[idx] && MaxSessionLoss > 0 && sessLoss >= MaxSessionLoss)
      {
         g_sessHalt[idx] = true;
         Log(1, "SESSION HALT [" + sess + "]: loss sesi " + DoubleToString(sessLoss, 2) +
                "% >= " + DoubleToString(MaxSessionLoss, 2) +
                "%. Sesi ini stop, sesi lain TETAP jalan.");
      }
   }
   else
   {
      g_curSession = "NONE";
   }
}

//--- Trading diizinkan untuk sesi tertentu?
//    Emergency DD & cap harian = global; halt sesi = spesifik sesi itu.
bool TradingAllowed(string sess)
{
   if(g_emergencyHalt) return(false);
   if(MaxDailyLoss > 0 && g_dailyHalt) return(false);
   int idx = SessionIndex(sess);
   if(idx >= 0 && g_sessHalt[idx]) return(false);
   return(true);
}

//--- Drawdown saat ini terhadap equity peak (%)
double CurrentDrawdownPct()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_equityPeak <= 0) return(0.0);
   double dd = (g_equityPeak - eq) / g_equityPeak * 100.0;
   return(dd < 0 ? 0 : dd);
}

//--- Risk efektif (%) setelah mode + proteksi drawdown + consecutive loss
double EffectiveRiskPercent()
{
   double r = RiskPercentage * ModeRiskMult() * DDReduceMult() * ConsecLossMult();
   //--- Pagar pengaman: jangan pernah lewat batas wajar per trade
   r = MathMax(0.05, MathMin(r, 25.0));
   return(r);
}

double ModeRiskMult()
{
   switch(InpTradeMode)
   {
      case MODE_DEFENSIVE:  return(0.5);
      case MODE_AGGRESSIVE: return(2.0);
      default:              return(1.0);
   }
}

//--- Pengali risk berdasar drawdown (linear turun saat DD melewati ambang)
double DDReduceMult()
{
   if(!EnableDrawdownReduce) return(1.0);
   double dd = CurrentDrawdownPct();
   if(dd <= DDReduceStartPct) return(1.0);
   double span = MathMax(0.001, MaxDrawdown - DDReduceStartPct);
   double t = MathMin(1.0, (dd - DDReduceStartPct) / span);
   return(1.0 - t * (1.0 - DDReduceFloorMult));
}

//--- Pengali risk berdasar loss beruntun
double ConsecLossMult()
{
   int losses = CountConsecutiveLosses();
   if(losses < ConsecLossTrigger) return(1.0);
   int extra = losses - ConsecLossTrigger + 1;
   double m = MathPow(ConsecLossFactor, extra);
   return(MathMax(0.2, m));
}

//--- Hitung loss beruntun dari history (30 hari terakhir)
int CountConsecutiveLosses()
{
   if(!HistorySelect(TimeCurrent() - 30 * 86400, TimeCurrent())) return(0);
   int total = HistoryDealsTotal();
   int losses = 0;
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                    + HistoryDealGetDouble(ticket, DEAL_SWAP)
                    + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      if(profit < 0) losses++;
      else break;
   }
   return(losses);
}

//--- Cooldown: blokir entry bila trade terakhir LOSS & belum lewat N bar.
//    Mengatasi pola "re-entry lawan arah" yang terlihat di backtest.
bool InLossCooldown()
{
   if(EntryCooldownBars <= 0) return(false);
   if(!HistorySelect(TimeCurrent() - 30 * 86400, TimeCurrent())) return(false);
   int total = HistoryDealsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                    + HistoryDealGetDouble(ticket, DEAL_SWAP)
                    + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      if(profit >= 0) return(false);   // trade terakhir menang -> tak ada cooldown

      datetime closeT = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      long elapsed = (long)(TimeCurrent() - closeT);
      long window  = (long)EntryCooldownBars * PeriodSeconds(PERIOD_M15);
      return(elapsed < window);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| ============ INDIKATOR & SINYAL UJI ============                 |
//+------------------------------------------------------------------+

//--- ATR dalam satuan pips (bar terakhir yang sudah close)
double GetAtrPips()
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_atrHandle, 0, 1, 1, buf) < 1) return(0.0);
   if(g_spec.pip <= 0) return(0.0);
   return(buf[0] / g_spec.pip);
}

//--- PLACEHOLDER: sinyal EMA cross HANYA untuk menguji MM (+1 buy, -1 sell, 0)
int TestSignal()
{
   double f[], s[];
   ArraySetAsSeries(f, true);
   ArraySetAsSeries(s, true);
   if(CopyBuffer(g_emaFastH, 0, 1, 2, f) < 2) return(0);
   if(CopyBuffer(g_emaSlowH, 0, 1, 2, s) < 2) return(0);
   bool crossUp = (f[1] <= s[1] && f[0] >  s[0]);
   bool crossDn = (f[1] >= s[1] && f[0] <  s[0]);
   if(crossUp) return(1);
   if(crossDn) return(-1);
   return(0);
}

//+------------------------------------------------------------------+
//| ============ TRADE ENGINE ============                           |
//+------------------------------------------------------------------+

//--- Buka trade berbasis risk: konversi SL/TP pips -> harga, jaga minStop
void OpenTradeRiskBased(int dir, double lots, double slPips, double tpPips)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minDist = g_spec.minStopPoints * g_spec.point;

   double slDist = MathMax(slPips * g_spec.pip, minDist);
   double tpDist = MathMax(tpPips * g_spec.pip, minDist);

   if(dir > 0)
   {
      double sl = NormalizeDouble(ask - slDist, g_spec.digits);
      double tp = NormalizeDouble(ask + tpDist, g_spec.digits);
      OpenBuy(lots, sl, tp, TradeComment);
   }
   else
   {
      double sl = NormalizeDouble(bid + slDist, g_spec.digits);
      double tp = NormalizeDouble(bid - tpDist, g_spec.digits);
      OpenSell(lots, sl, tp, TradeComment);
   }
}

bool OpenBuy(double lots, double sl, double tp, string comment)
{ return(ExecuteOrder(ORDER_TYPE_BUY, lots, sl, tp, comment)); }

bool OpenSell(double lots, double sl, double tp, string comment)
{ return(ExecuteOrder(ORDER_TYPE_SELL, lots, sl, tp, comment)); }

bool ExecuteOrder(ENUM_ORDER_TYPE type, double lots, double sl, double tp, string comment)
{
   lots = NormalizeLots(lots);
   if(lots <= 0) { Log(1, "Lot tidak valid, order dibatalkan."); return(false); }

   for(int attempt = 1; attempt <= 3; attempt++)
   {
      bool ok = (type == ORDER_TYPE_BUY)
                ? trade.Buy(lots, _Symbol, 0.0, sl, tp, comment)
                : trade.Sell(lots, _Symbol, 0.0, sl, tp, comment);
      uint rc = trade.ResultRetcode();

      if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED))
      {
         Log(2, "Order " + EnumToString(type) + " OK lot=" + DoubleToString(lots, 2) +
                " SL=" + DoubleToString(sl, g_spec.digits) +
                " TP=" + DoubleToString(tp, g_spec.digits));
         return(true);
      }
      if(rc == TRADE_RETCODE_REQUOTE || rc == TRADE_RETCODE_PRICE_OFF ||
         rc == TRADE_RETCODE_PRICE_CHANGED || rc == TRADE_RETCODE_TOO_MANY_REQUESTS)
      { Sleep(300); continue; }

      Log(1, "Order GAGAL rc=" + IntegerToString(rc) + " (" +
             trade.ResultRetcodeDescription() + ")");
      return(false);
   }
   Log(1, "Order gagal setelah 3x percobaan.");
   return(false);
}

double NormalizeLots(double lots)
{
   double step = g_spec.volStep > 0 ? g_spec.volStep : 0.01;
   lots = MathFloor(lots / step) * step;
   lots = MathMax(g_spec.volMin, MathMin(g_spec.volMax, lots));
   return(NormalizeDouble(lots, 2));
}

int CountOurPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == MagicNumber)
            count++;
   return(count);
}

//--- Tutup semua posisi milik EA ini (dipakai close-on-news, dll)
void CloseOurPositions(string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != MagicNumber) continue;
      ulong ticket = posInfo.Ticket();
      if(trade.PositionClose(ticket))
         Log(2, "Tutup posisi (" + reason + ") ticket=" + IntegerToString((long)ticket));
   }
}

//+------------------------------------------------------------------+
//| ============ SESI 6: EXIT MANAGEMENT ============                |
//| Dipanggil tiap tick. Breakeven + partial close + trailing,       |
//| semua berbasis ATR. Berlaku untuk posisi dari sesi mana pun.     |
//+------------------------------------------------------------------+

//--- Apakah tiket sudah pernah partial-close?
bool IsPartialDone(ulong ticket)
{
   for(int i = 0; i < ArraySize(g_partialTickets); i++)
      if(g_partialTickets[i] == ticket) return(true);
   return(false);
}

//--- Tandai tiket sudah partial-close
void MarkPartialDone(ulong ticket)
{
   int n = ArraySize(g_partialTickets);
   ArrayResize(g_partialTickets, n + 1);
   g_partialTickets[n] = ticket;
}

//--- Buang tiket yang posisinya sudah tertutup (jaga array tetap kecil)
void PrunePartialTickets()
{
   ulong keep[];
   int k = 0;
   for(int i = 0; i < ArraySize(g_partialTickets); i++)
   {
      if(PositionSelectByTicket(g_partialTickets[i]))
      { ArrayResize(keep, k + 1); keep[k] = g_partialTickets[i]; k++; }
   }
   ArrayResize(g_partialTickets, k);
   for(int i = 0; i < k; i++) g_partialTickets[i] = keep[i];
}

//--- SL "lebih baik" untuk arah posisi (buy: lebih tinggi; sell: lebih rendah).
//    SL = 0 dianggap belum ada (kandidat selalu menang).
double BetterSL(double curr, double cand, long type)
{
   if(type == POSITION_TYPE_BUY)
      return((curr == 0) ? cand : MathMax(curr, cand));
   else
      return((curr == 0) ? cand : MathMin(curr, cand));
}

void ManageOpenPositions()
{
   //--- Weekend close (Sesi 8): tutup semua posisi sebelum weekend (hindari gap Senin)
   if(Protection_ShouldCloseForWeekend(TimeCurrent()) && CountOurPositions() > 0)
   {
      CloseOurPositions("weekend");
      return;
   }

   //--- Pre-news close (Sesi 7): tutup posisi saat masuk window news high-impact
   if(EnableNewsFilter && News_ClosePositions && CountOurPositions() > 0 &&
      News_IsBlocked(TimeCurrent()))
   {
      CloseOurPositions("pre-news");
      return;
   }

   if(!UseBreakeven && !UsePartialClose && !UseTrailingStop) return;
   if(CountOurPositions() == 0) return;

   double atrPips = GetAtrPips();
   if(atrPips <= 0) return;
   double atrPrice = atrPips * g_spec.pip;
   double minDist  = g_spec.minStopPoints * g_spec.point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != MagicNumber) continue;

      ulong  ticket = posInfo.Ticket();
      long   type   = posInfo.PositionType();
      double entry  = posInfo.PriceOpen();
      double vol    = posInfo.Volume();
      double sl     = posInfo.StopLoss();
      double tp     = posInfo.TakeProfit();

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      //--- Seberapa jauh harga bergerak menguntungkan (price terms)
      double favor    = (type == POSITION_TYPE_BUY) ? (bid - entry) : (entry - ask);
      double curClose = (type == POSITION_TYPE_BUY) ? bid : ask;
      if(favor <= 0) continue;   // belum profit -> tak ada manajemen profit-based

      //--- Partial close (sekali per tiket; sisa harus >= volume min)
      if(UsePartialClose && Partial_Percent > 0 && !IsPartialDone(ticket) &&
         favor >= Partial_TriggerATR * atrPrice)
      {
         double closeVol = NormalizeLots(vol * Partial_Percent / 100.0);
         double remain   = vol - closeVol;
         if(closeVol >= g_spec.volMin && remain >= g_spec.volMin)
         {
            if(trade.PositionClosePartial(ticket, closeVol))
            {
               MarkPartialDone(ticket);
               Log(2, "Partial close " + DoubleToString(closeVol, 2) + " lot @ " +
                      DoubleToString(curClose, g_spec.digits) + " (sisa " +
                      DoubleToString(remain, 2) + ")");
            }
         }
      }

      //--- Hitung SL target gabungan (breakeven + trailing), modifikasi sekali
      double desiredSL = sl;

      if(UseBreakeven && favor >= BE_TriggerATR * atrPrice)
      {
         double be = (type == POSITION_TYPE_BUY) ? entry + BE_BufferPips * g_spec.pip
                                                 : entry - BE_BufferPips * g_spec.pip;
         desiredSL = BetterSL(desiredSL, be, type);
      }

      if(UseTrailingStop && favor >= Trail_StartATR * atrPrice)
      {
         double tr = (type == POSITION_TYPE_BUY) ? curClose - Trail_DistATR * atrPrice
                                                 : curClose + Trail_DistATR * atrPrice;
         desiredSL = BetterSL(desiredSL, tr, type);
      }

      //--- Terapkan hanya bila berubah, lebih baik, & jarak valid dari harga
      if(desiredSL != sl)
      {
         bool better = (type == POSITION_TYPE_BUY) ? (desiredSL > sl || sl == 0)
                                                   : (desiredSL < sl || sl == 0);
         bool farEnough = (type == POSITION_TYPE_BUY) ? (bid - desiredSL >= minDist)
                                                      : (desiredSL - ask >= minDist);
         if(better && farEnough)
            trade.PositionModify(ticket, NormalizeDouble(desiredSL, g_spec.digits), tp);
      }
   }

   PrunePartialTickets();
}

//+------------------------------------------------------------------+
//| ============ TIME / SESSION / SPREAD ============                |
//+------------------------------------------------------------------+
//--- Apakah server sedang DST (summer)? Pakai TimeCurrent() agar VALID di
//    Strategy Tester maupun live (TimeGMT tidak reliabel di tester).
bool IsServerInDST()
{
   datetime gmtApprox = TimeCurrent() - (datetime)ServerTimeZoneBase * 3600;
   return(IsEUSummerTime(gmtApprox));
}

//--- Offset GMT server saat ini (base + 1 bila DST aktif)
int CurrentServerGMTOffset()
{
   int off = ServerTimeZoneBase;
   if(AutoDetectDST && IsServerInDST()) off += 1;
   return(off);
}

//--- Pergeseran jam sesi saat DST (OPSIONAL, untuk uji empiris).
//    Default OFF: jam server HFM KONSTAN sepanjang tahun karena server (EU DST)
//    & London (UK DST) bergeser di tanggal sama -> selisih tetap +2 jam.
//    Bukti proyek: shift ON di summer = rugi (-209); OFF (konstan) = +175.
//    Toggle ON hanya bila ingin membandingkan sendiri lewat backtest.
int SessionDstShift()
{
   if(UseSessionDSTShift && IsServerInDST()) return(1);
   return(0);
}

bool IsEUSummerTime(datetime gmt)
{
   MqlDateTime dt; TimeToStruct(gmt, dt);
   datetime start = LastSundayOfMonth(dt.year, 3) + 3600;   // Minggu terakhir Mar 01:00 GMT
   datetime end   = LastSundayOfMonth(dt.year, 10) + 3600;  // Minggu terakhir Okt 01:00 GMT
   return(gmt >= start && gmt < end);
}

datetime LastSundayOfMonth(int year, int month)
{
   int nm = (month == 12) ? 1 : month + 1;
   int ny = (month == 12) ? year + 1 : year;
   MqlDateTime dt; dt.year = ny; dt.mon = nm; dt.day = 1;
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime firstNext = StructToTime(dt);
   datetime lastDay = firstNext - 86400;
   MqlDateTime ld; TimeToStruct(lastDay, ld);
   return(lastDay - ld.day_of_week * 86400);
}

string ActiveSessionName()
{
   //--- Jam server HFM KONSTAN sepanjang tahun (server selalu +2 dari London;
   //    keduanya geser di tanggal DST sama). Default tanpa shift.
   //    Bila UseSessionDSTShift=ON, jam efektif digeser -1 di summer (window +1).
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour - SessionDstShift();
   //--- Prioritas: OVERLAP > US > EUROPE > ASIA.
   if(TradeOverlapSession  && h >= OverlapSessionStart  && h < OverlapSessionEnd)  return("OVERLAP");
   if(TradeUSSession       && h >= USSessionStart       && h < USSessionEnd)       return("US");
   if(TradeEuropeanSession && h >= EuropeanSessionStart && h < EuropeanSessionEnd) return("EUROPE");
   if(TradePreLondonSession && h >= PreLondonSessionStart && h < PreLondonSessionEnd) return("PRELONDON");
   if(TradeAsianSession    && h >= AsianSessionStart    && h < AsianSessionEnd)     return("ASIA");
   return("NONE");
}

bool IsNewBar()
{
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t != g_lastBarTime) { g_lastBarTime = t; return(true); }
   return(false);
}

double CurrentSpreadPips()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(g_spec.pip <= 0) return(0);
   return((ask - bid) / g_spec.pip);
}

double EffectiveMaxSpread() { return(CustomSpread ? CustomSpreadValue : MaxSpreadPips); }
bool   SpreadOK()           { return(CurrentSpreadPips() <= EffectiveMaxSpread()); }

//+------------------------------------------------------------------+
//| ============ LOGGING ============                                |
//+------------------------------------------------------------------+
void Log(int level, string msg)
{
   if(LogLevel == 0 || level > LogLevel) return;
   string tag = (level == 1) ? "[ERROR]" : (level == 2 ? "[INFO]" : "[DEBUG]");
   string line = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + " " + tag + " " + msg;
   Print(line);
   if(EnableFileLog && g_logHandle != INVALID_HANDLE)
   { FileWrite(g_logHandle, line); FileFlush(g_logHandle); }
}
//+------------------------------------------------------------------+
//| AKHIR v1.2.0                                                     |
//| Berikutnya (Sesi 4): Strategi Sesi Eropa - trend-following       |
//| EMA crossover, breakout confirmation, momentum entry.            |
//+------------------------------------------------------------------+
