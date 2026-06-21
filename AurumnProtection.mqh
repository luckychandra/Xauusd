//+------------------------------------------------------------------+
//|                                            AurumnProtection.mqh   |
//|        SESI 8: PROTEKSI LANJUTAN (Weekend & Holiday)            |
//|        Menutup celah risiko yg belum ditangani:                 |
//|        - Weekend close: tutup posisi sebelum pasar tutup Jumat   |
//|          (hindari gap pembukaan Senin yg bisa lompati SL).      |
//|        - Cutoff Jumat: stop entry baru sore Jumat.              |
//|        - Delay Senin: hindari whipsaw/gap awal pekan (opsional). |
//|        - Filter libur: skip trading saat likuiditas tipis.      |
//|        Catatan: korelasi N/A (single-symbol). Recovery sudah     |
//|        ditangani emergency-DD recoverable + risk-scaling DD.     |
//+------------------------------------------------------------------+
#ifndef AURUMN_PROTECTION_MQH
#define AURUMN_PROTECTION_MQH

input group "=== SESI 8: PROTEKSI LANJUTAN (Weekend & Holiday) ==="
input bool   UseWeekendClose      = true;  // Tutup semua posisi sebelum weekend
input int    WeekendCloseDay       = 5;     // Hari tutup (0=Min,1=Sen..5=Jum,6=Sab)
input int    WeekendCloseHour       = 22;   // Jam tutup posisi (server)
input bool   NoNewTradesFriday     = true;  // Stop entry baru Jumat sore
input int    FridayCutoffHour       = 20;   // Jam stop entry Jumat (server)
input bool   UseMondayDelay        = false; // Tunda trading awal Senin (hindari gap)
input int    MondayDelayUntilHour   = 2;    // Trading baru mulai jam ini di Senin (server)
input bool   UseHolidayFilter      = false; // Skip trading di tanggal libur
input string HolidayDates           = "";   // Tanggal libur "YYYY.MM.DD", pisah koma

datetime g_holidays[];

//--- Parse daftar tanggal libur
void Protection_Init()
{
   ArrayResize(g_holidays, 0);
   if(!UseHolidayFilter || StringLen(HolidayDates) < 8) return;
   string parts[];
   int k = StringSplit(HolidayDates, ',', parts);
   for(int i = 0; i < k; i++)
   {
      string d = parts[i]; StringTrimLeft(d); StringTrimRight(d);
      if(StringLen(d) < 8) continue;
      datetime t = StringToTime(d);
      if(t <= 0) continue;
      int n = ArraySize(g_holidays);
      ArrayResize(g_holidays, n + 1);
      g_holidays[n] = t;
   }
   Print("[Proteksi] ", ArraySize(g_holidays), " tanggal libur dimuat.");
}

int Protection_HolidayCount() { return(ArraySize(g_holidays)); }

bool Protection_IsHoliday(datetime now)
{
   if(!UseHolidayFilter) return(false);
   MqlDateTime dt; TimeToStruct(now, dt);
   for(int i = 0; i < ArraySize(g_holidays); i++)
   {
      MqlDateTime hd; TimeToStruct(g_holidays[i], hd);
      if(hd.year == dt.year && hd.mon == dt.mon && hd.day == dt.day) return(true);
   }
   return(false);
}

//--- Saatnya tutup posisi untuk weekend?
bool Protection_ShouldCloseForWeekend(datetime now)
{
   if(!UseWeekendClose) return(false);
   MqlDateTime dt; TimeToStruct(now, dt);
   return(dt.day_of_week == WeekendCloseDay && dt.hour >= WeekendCloseHour);
}

//--- Blokir entry baru? (weekend, cutoff Jumat, delay Senin, libur)
bool Protection_BlockNewTrades(datetime now)
{
   MqlDateTime dt; TimeToStruct(now, dt);
   //--- window weekend-close -> juga blokir entry
   if(UseWeekendClose && dt.day_of_week == WeekendCloseDay && dt.hour >= WeekendCloseHour)
      return(true);
   //--- cutoff Jumat (5)
   if(NoNewTradesFriday && dt.day_of_week == 5 && dt.hour >= FridayCutoffHour)
      return(true);
   //--- delay Senin (1)
   if(UseMondayDelay && dt.day_of_week == 1 && dt.hour < MondayDelayUntilHour)
      return(true);
   //--- libur
   if(Protection_IsHoliday(now))
      return(true);
   return(false);
}

#endif // AURUMN_PROTECTION_MQH
