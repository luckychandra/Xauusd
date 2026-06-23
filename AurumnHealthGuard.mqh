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
bool   g_hgTripped = false;  // sudah trip? (tetap true sampai restart EA)
string g_hgReason  = "";     // alasan trip

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
}

//--- Evaluasi kesehatan dari window saat ini
void HealthGuard_Evaluate()
{
   int n = ArraySize(g_hgResults);
   if(n < HG_MinTradesToEval) return;

   double gp = 0.0, gl = 0.0;
   int    consec = 0, maxConsec = 0;
   for(int i = 0; i < n; i++)
   {
      double r = g_hgResults[i];
      if(r >= 0.0) { gp += r; consec = 0; }
      else         { gl += (-r); consec++; if(consec > maxConsec) maxConsec = consec; }
   }
   double pf = (gl > 0.0) ? (gp / gl) : (gp > 0.0 ? 999.0 : 0.0);

   string reason = "";
   if(pf < HG_MinProfitFactor)
      reason = "PF rolling " + DoubleToString(pf, 2) + " < " + DoubleToString(HG_MinProfitFactor, 2) +
               " (" + IntegerToString(n) + " trade terakhir)";
   else if(maxConsec >= HG_MaxConsecLoss)
      reason = "loss beruntun " + IntegerToString(maxConsec) + " >= " + IntegerToString(HG_MaxConsecLoss);

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
}

#endif // AURUMN_HEALTHGUARD_MQH
