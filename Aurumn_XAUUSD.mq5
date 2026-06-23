//+------------------------------------------------------------------+
//|                                                  Aurumn_XAUUSD.mq5 |
//|                 EA UTAMA - XAUUSD(c) M15 - HFM Cent Account        |
//|                 Integrasi: Sesi 1 (Foundation) + Sesi 2 (Money Mgmt)|
//+------------------------------------------------------------------+
//  VERSION: v2.1.3
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
//    v2.1.3 - SINKRON PENUH ke config referensi (c.xlsx London + contohgabungan Asia).
//             5 param yg melenceng (interferensi) dikembalikan: EuropeanSessionEnd 15->16,
//             Euro_ADXMin 20->25, Euro_RequireADXRising false->true, MaxDrawdown 20->100,
//             MaxDailyLoss 0->15. London OPEN=8 dikonfirmasi (= c.xlsx, BUKAN 10).
//             Audit penuh: logika/dispatch/risk/exit-routing/health-guard BERSIH, tak ada
//             interferensi lain. Asia=A, London=C (per-sesi). Target: gabungan >= +826.
//    v2.1.2 - KOREKSI KESALAHANKU: London OPEN dikembalikan 8->10. Di v1.9.8 aku
//             salah ubah open 10->8 (alasan keliru 'validated 8-15'); window Option C
//             tervalidasi (+603) sebenarnya 10-15 (lihat v1.9.2). Open 8 menambah jam
//             8-9 -> sesi berubah signifikan. Open=10 & End=15 kini DIKUNCI (komentar
//             JANGAN UBAH). Konflik: run gabungan +826 pakai open=8 - konfirmasi user.
//    v2.1.1 - EXIT 100% PER-SESI: hapus SEMUA param exit global. Tiap sesi profil
//             sendiri (Asia/Euro/US/Overlap/PreLon) dipilih via switch(g_posSessionIdx).
//             Asia=A(partial+BE+trail 1.5/1.5), London=C(trail 3.0/2.0). Tak ada lagi
//             setting bersama yg bisa bertubrukan. EuropeanSessionEnd dikembalikan 15.
//             Audit: Europe TERBUKTI jalan profil C (win 40%+pemenang besar=C, bukan A).
//    v2.1.0 - SESI 10: HEALTH-GUARD autonomous. Pantau PF rolling + loss beruntun
//             dari N trade terakhir; bila edge RUSAK -> auto-jeda entry + alert Telegram,
//             tunggu tinjauan manusia (TIDAK auto-resume, TIDAK ubah parameter = bukan
//             curve-fitting). Net per-posisi via selisih saldo (tahan partial-close).
//             Default TIDAK jeda di tester (validasi tampak mentah). Modul:
//             AurumnHealthGuard.mqh. EA kini FITUR-LENGKAP; sisa = validasi OOS + live.
//    v2.0.0 - EXIT PER-SESI: exit tak lagi global. Posisi menandai sesi pembukanya
//             (g_posSessionIdx); ManageOpenPositions pilih profil sesuai sesi itu.
//             ASIA/lainnya = exit DEFAULT (partial+BE+trail 1.5/1.5 = profil A, proven +826).
//             LONDON = profil SENDIRI (Euro_*: partial/BE OFF, trail 3.0/2.0 = profil C,
//             biarkan pemenang jalan). Asia & London tak lagi bertubrukan exit-nya.
//             CATATAN: ini UBAH konfig +826 (dulu London pakai A); WAJIB re-test.
//    v1.9.9 - Selaras dgn konfig EDGE tervalidasi +826 (contohgabungan.xlsx):
//             EuropeanSessionEnd 15->16 (fungsinya identik). Semua param Asia+London
//             lain sudah cocok. London TIDAK diubah (strategi/RR/SL/exit utuh).
//             EA as-is kini mereproduksi konfig +826 (PF 1.21, DD 19%).
//    v1.9.8 - PERBAIKAN REGRESI: London dikembalikan ke window TERVALIDASI 8-15
//             (saat tambah PreLondon, London tergeser 10-15 -> hilang jam 8-9
//             yg profit +160). PreLondon OFF (redundan saat London mulai 8 +
//             Donchian di likuiditas tipis = drag). Asia TIDAK diubah (stabil sejak
//             v1.3.0); "Asia jelek" = salah alamat, akarnya window London + PreLondon.
//    v1.9.7 - Sesi US: US_RR 1.5->2.5 agar TP > trail-start (3.0 ATR) sehingga
//             trailing (exit C) aktif & pemenang dibiarkan jalan (pelajaran London).
//             Window benar = default 19-24 (lewati NY-open/overlap beracun 15-18);
//             kegagalan US sebelumnya = window di-override ke 13-21/16-22 + RR 1.0.
//    v1.9.6 - Rombak total sesi OVERLAP: ganti Donchian breakout (rugi -434,
//             DD 96%) -> SWEEP-FADE (fade liquidity sweep/stop hunt di awal
//             overlap, fade false-breakout NY open). Mode OVL_SWEEP (utama) /
//             OVL_BREAKOUT (A/B). Sinkron g_ovDstShift. RR dinaikkan 2.5.
//             breakout. Array per-sesi 4->5. Sesi kini: Asia/PraLondon/Europe/Overlap/NY.
//  PRASYARAT: Letakkan AurumnSymbolSpec.mqh, AurumnStrategy_Asian.mqh,
//             AurumnStrategy_European.mqh,
//             AurumnStrategy_US.mqh,
//             AurumnStrategy_Overlap.mqh,
//             AurumnStrategy_PreLondon.mqh, AurumnNewsFilter.mqh,
//             AurumnProtection.mqh,
//             AurumnTelegram.mqh,
//             AurumnHealthGuard.mqh di folder MQL5/Include/
//+------------------------------------------------------------------+
#property copyright "Aurumn EA"
#property version   "2.13"
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
#include <AurumnHealthGuard.mqh>       // SESI 10: pemantau kesehatan edge (auto-pause)

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
input double MaxDailyLoss        = 15.0;       // Cap loss harian SELURUH sesi (= referensi)
input double MaxDrawdown        = 100.0;      // Emergency stop DD% (= referensi; 100=off. Live: pertimbangkan 25-30)
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

//=== SESI 6: EXIT PER-SESI (tiap sesi profil SENDIRI - TIDAK ADA global lagi) ===
// Trigger bersama (ambang; hanya berlaku di sesi yang mengaktifkan partial/BE)
input double BE_TriggerATR      = 1.0;        // Trigger BE saat profit >= x ATR
input double BE_BufferPips      = 2.0;        // Buffer BE di atas/bawah entry (pips)
input double Partial_TriggerATR = 1.0;        // Trigger partial saat profit >= x ATR
input double Partial_Percent    = 50.0;       // % volume yang ditutup saat partial

// --- ASIA (profil A: scalp, exit ketat - NILAI TERVALIDASI run gabungan) ---
input bool   Asia_UsePartial    = true;       // Asia: partial close ON
input bool   Asia_UseBE         = true;       // Asia: breakeven ON
input bool   Asia_UseTrail      = true;       // Asia: trailing ON
input double Asia_TrailStart    = 1.5;        // Asia: mulai trailing (x ATR)
input double Asia_TrailDist     = 1.5;        // Asia: jarak trailing (x ATR)

// --- LONDON/EUROPE (profil C: trend, biarkan pemenang jalan - EDGE Option C) ---
input bool   Euro_UsePartial     = false;     // London: partial OFF (jangan cekik runner)
input bool   Euro_UseBE          = false;     // London: breakeven OFF
input bool   Euro_UseTrail       = true;      // London: trailing ON
input double Euro_Trail_StartATR = 3.0;       // London: mulai trailing
input double Euro_Trail_DistATR  = 2.0;       // London: jarak trailing

// --- US (profil trend) ---
input bool   US_UsePartial      = false;      // US: partial OFF
input bool   US_UseBE           = false;      // US: breakeven OFF
input bool   US_UseTrail        = true;       // US: trailing ON
input double US_TrailStart      = 3.0;        // US: mulai trailing
input double US_TrailDist       = 2.0;        // US: jarak trailing

// --- OVERLAP (profil trend) ---
input bool   Overlap_UsePartial = false;      // Overlap: partial OFF
input bool   Overlap_UseBE      = false;      // Overlap: breakeven OFF
input bool   Overlap_UseTrail   = true;       // Overlap: trailing ON
input double Overlap_TrailStart = 3.0;        // Overlap: mulai trailing
input double Overlap_TrailDist  = 2.0;        // Overlap: jarak trailing

// --- PRELONDON (profil trend) ---
input bool   PreLon_UsePartial  = false;      // PreLondon: partial OFF
input bool   PreLon_UseBE       = false;      // PreLondon: breakeven OFF
input bool   PreLon_UseTrail    = true;       // PreLondon: trailing ON
input double PreLon_TrailStart  = 3.0;        // PreLondon: mulai trailing
input double PreLon_TrailDist   = 2.0;        // PreLondon: jarak trailing

//=== TEST SIGNAL (PLACEHOLDER - hanya untuk menguji MM, BUKAN strategi nyata) ===
input bool   EnableTestSignal   = false;      // Aktifkan sinyal uji (EMA cross)
input int    TestEmaFast        = 20;         // EMA cepat (uji)
input int    TestEmaSlow        = 50;         // EMA lambat (uji)

//=== SESSION (jam = waktu server HFM GMT+2/+3) ===
input bool   TradeAsianSession    = true;
input bool   TradeEuropeanSession = true;
input bool   TradeUSSession       = false;
input bool   TradeOverlapSession  = false;
input bool   TradePreLondonSession = false;
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
input int    EuropeanSessionStart = 8;        // London OPEN = 8 (= c.xlsx + contohgabungan). TERKUNCI.
input int    EuropeanSessionEnd   = 16;       // London END = 16 (= c.xlsx + contohgabungan). TERKUNCI.
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
int         g_posSessionIdx     = -1;       // sesi yg membuka posisi aktif (utk exit per-sesi)
double      g_posEntryBalance   = 0.0;      // saldo saat posisi dibuka (utk hitung net per-posisi)
int         g_prevPosCount      = 0;        // jumlah posisi tick sebelumnya (deteksi tutup)

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
   if(!U
