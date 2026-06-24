//+------------------------------------------------------------------+
//|                                          AurumnHealthGuard.mqh    |
//|        SESI 10: HEALTH-GUARD (pemantau kesehatan EDGE, live)     |
//|        Memantau performa ROLLING (Profit Factor + loss beruntun)  |
//|        dari N trade terakhir. Bila edge TERDETEKSI RUSAK (PF      |
//|        rolling anjlok / loss beruntun ekstrem) -> auto-JEDA entry  |
//|        baru + alert Telegram, lalu TUNGGU tinjauan manusia.       |
//|                                                                   |
//|        FILOSOFI (penting): ini BUKAN optimizer. TIDAK mengubah    |
//|        parameter apa pun. Tidak ada re-optimasi/curve-fitting     |
//|        live. Ia hanya MENJAGA: kalau strategi berhenti bekerja,   |
//|        ia berhenti trading dan memberi tahu. TIDAK auto-resume    |
//|        (edge rusak butuh investigasi manusia + restart EA).       |
//|                                                                   |
//|        Default TIDAK menjeda di Strategy Tester (HG_PauseInTester  |
//|        =false) supaya validasi/walk-forward menampilkan performa  |
//|        MENTAH; tetap mencatat & meng-log kapan ia AKAN trip.      |
//+------------------------------------------------------------------+
#ifndef AURUMN_HEALTHGUARD_MQH
#define AURUMN_HEALTHGUARD_MQH

input group "=== SESI 10: HEALTH-GUARD (pemantau edge live) ==="
input bool   UseHealthGuard       = true;    // Aktifkan pemantau kesehatan edge
input int    HG_WindowTrades       = 30;      // Evaluasi dari N trade terakhir
input int    HG_MinTradesToEval     = 20;      // Min trade terkumpul sebelum guard menilai
input double HG_MinProfitFactor     = 0.65;    // JEDA bila PF rolling < ini (edge rusak)
input int    HG_MaxConsecLoss       = 12;      // JEDA bila loss beruntun >= ini
input bool   HG_AutoPause           = true;    // Auto-jeda entry saat trip (false = alert saja)
input bool   HG_AlertTelegram       = true;    // Kirim alert Telegram saat trip (live)
input bool   HG_PauseInTester       = false;   // Izinkan jeda di Strategy Tester (default OFF)

//--- State
double g_hgResults[];        // P/L bersih trade terakhir (rolling window)
bool   g_hgTripped = false;  // sudah trip? (persist ke disk; restart TIDAK reset)
string g_hgReason  = "";     // alasan trip
int    g_hgCurStreak = 0;    // FIX#5: streak loss BERJALAN (independen window; tak understated saat trim)

//--- FIX#5: Persistensi state ke disk (LIVE saja; tester selalu fresh agar backtest bersih)
string HG_StateFileName() { return("AurumnHG_" + _Symbol + ".dat"); }

void HealthGuard_SaveState()
{
   if((bool)MQLInfoInteger(MQL_TESTER) || !UseHealthGuard) return;
   int h = FileOpen(HG_StateFileName(), FILE_WRITE|FILE_BIN);
   if(h == INVALID_HANDLE) return;
   FileWriteInteger(h, g_hgTripped ? 1 : 0, INT_VALUE);
   FileWriteInteger(h, g_hgCurStreak, INT_VALUE);   // FIX#5: persist streak berjalan
   int n = ArraySize(g_hgResults);
   FileWriteInteger(h, n, INT_VALUE);
   for(int i = 0; i < n; i++) FileWriteDouble(h, g_hgResults[i]);
   FileClose(h);
}

void HealthGuard_LoadState()
{
   if((bool)MQLInfoInteger(MQL_TESTER) || !UseHealthGuard) return;
   if(!FileIsExist(HG_StateFileName())) return;
   int h = FileOpen(HG_StateFileName(), FILE_READ|FILE_BIN);
   if(h == INVALID_HANDLE) return;
   g_hgTripped = (FileReadInteger(h, INT_VALUE) == 1);
   g_hgCurStreak = FileReadInteger(h, INT_VALUE);   // FIX#5: pulihkan streak berjalan
   int n = FileReadInteger(h, INT_VALUE);
   ArrayResize(g_hgResults, 0);
   for(int i = 0; i < n && !FileIsEnding(h); i++)
   {
      int sz = ArraySize(g_hgResults);
      ArrayResize(g_hgResults, sz + 1);
      g_hgResults[sz] = FileReadDouble(h);
   }
   FileClose(h);
   if(g_hgTripped)
   {
      if(g_hgReason == "") g_hgReason = "(state TRIPPED dipulihkan dari disk)";
      Print("HealthGuard: state TRIPPED dipulihkan - entry TETAP DIJEDA. Hapus MQL5/Files/", HG_StateFileName(), " utk reset stlh investigasi.");
   }
   else
      Print("HealthGuard: riwayat ", ArraySize(g_hgResults), " trade dipulihkan dari disk.");
}

//--- Reset trip via perintah (Telegram /resume) - tindakan SENGAJA manusia
void HealthGuard_Reset()
{
   bool was = g_hgTripped;
   g_hgTripped = false;
   g_hgReason  = "";
   g_hgCurStreak = 0;
   ArrayResize(g_hgResults, 0);                          // window bersih -> evaluasi ulang dari trade baru
   if(!(bool)MQLInfoInteger(MQL_TESTER) && FileIsExist(HG_StateFileName()))
      FileDelete(HG_StateFileName());                    // hapus state persisten
   if(was) Print("HealthGuard: trip DI-RESET (perintah). Window dikosongkan + file state dihapus.");
}

bool   HealthGuard_IsTripped() { return(g_hgTripped); }
string HealthGuard_Reason()    { return(g_hgReason); }

//--- Apakah harus MENJEDA entry sekarang? (hormati guard tester)
bool HealthGuard_ShouldPauseEntry()
{
   if(!UseHealthGuard || !HG_AutoPause || !g_hgTripped) return(false);
   if((bool)MQLInfoInteger(MQL_TESTER) && !HG_PauseInTester) return(false);
   return(true);
}

//--- Reset (dipanggil OnInit)
void HealthGuard_Init()
{
   ArrayResize(g_hgResults, 0);
   g_hgTripped = false;
   g_hgReason  = "";
   g_hgCurStreak = 0;
   HealthGuard_LoadState();   // FIX#5: pulihkan state live dari disk (tester di-skip)
}

//--- Evaluasi kesehatan dari window saat ini
void HealthGuard_Evaluate()
{
   int n = ArraySize(g_hgResults);
   if(n < HG_MinTradesToEval) return;

   double gp = 0.0, gl = 0.0;
   for(int i = 0; i < n; i++)
   {
      double r = g_hgResults[i];
      if(r >= 0.0) gp += r;
      else         gl += (-r);
   }
   double pf = (gl > 0.0) ? (gp / gl) : (gp > 0.0 ? 999.0 : 0.0);

   string reason = "";
   if(pf < HG_MinProfitFactor)
      reason = "PF rolling " + DoubleToString(pf, 2) + " < " + DoubleToString(HG_MinProfitFactor, 2) +
               " (" + IntegerToString(n) + " trade terakhir)";
   else if(g_hgCurStreak >= HG_MaxConsecLoss)
      reason = "loss beruntun " + IntegerToString(g_hgCurStreak) + " >= " + IntegerToString(HG_MaxConsecLoss);

   if(reason != "" && !g_hgTripped)
   {
      g_hgTripped = true;
      g_hgReason  = reason;
   }
}

//--- Catat hasil 1 trade tutup (P/L bersih = profit+swap+komisi), lalu evaluasi
void HealthGuard_RecordTrade(double netResult)
{
   if(!UseHealthGuard) return;
   //--- FIX#5: streak loss berjalan (dihitung independen dari trim window -> akurat penuh)
   if(netResult < 0.0) g_hgCurStreak++;
   else                g_hgCurStreak = 0;
   int n = ArraySize(g_hgResults);
   ArrayResize(g_hgResults, n + 1);
   g_hgResults[n] = netResult;

   //--- jaga ukuran window: buang yang terlama
   int sz = ArraySize(g_hgResults);
   if(sz > HG_WindowTrades)
   {
      int drop = sz - HG_WindowTrades;
      for(int i = 0; i < HG_WindowTrades; i++) g_hgResults[i] = g_hgResults[i + drop];
      ArrayResize(g_hgResults, HG_WindowTrades);
   }
   HealthGuard_Evaluate();
   HealthGuard_SaveState();   // FIX#5: persist tiap trade -> restart tak hilang state
}

#endif // AURUMN_HEALTHGUARD_MQH
