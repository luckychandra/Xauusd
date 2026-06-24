//+------------------------------------------------------------------+
//|                                          AurumnNewsFilter.mqh     |
//|        SESI 7: NEWS FILTER                                       |
//|        Sumber data via News_Source (dinamis live + CSV backtest):|
//|        AUTO - live=kalender MT5 dinamis, tester=CSV (rekomendasi)|
//|        CSV_ONLY - paksa CSV (reproducible; backtest/no-calendar) |
//|        CALENDAR_ONLY - paksa kalender MT5 (LIVE saja)            |
//|                                                                  |
//|        FORMAT CSV (taruh di folder MQL5/Files/):                |
//|          YYYY.MM.DD,HH:MM,CCY[,IMPACT]                           |
//|          contoh: 2026.01.10,15:30,USD,HIGH                       |
//|        Baris diawali '#' diabaikan (komentar).                  |
//|        PENTING: waktu CSV harus WAKTU SERVER (sama dgn chart),   |
//|        atau set News_CSVOffsetHours utk konversi.               |
//+------------------------------------------------------------------+
#ifndef AURUMN_NEWS_FILTER_MQH
#define AURUMN_NEWS_FILTER_MQH

//--- Sumber data news: dinamis (live) + CSV (backtest), keduanya berfungsi
enum ENewsSource
{
   NEWS_AUTO          = 0,   // OTOMATIS: live=kalender MT5, tester=CSV (rekomendasi)
   NEWS_CSV_ONLY      = 1,   // PAKSA CSV (reproducible; backtest atau jika kalender tak ada)
   NEWS_CALENDAR_ONLY = 2    // PAKSA kalender MT5 (LIVE saja; di tester akan kosong)
};

input group "=== SESI 7: NEWS FILTER ==="
input bool   EnableNewsFilter    = true;             // Aktifkan news filter
input int    News_MinutesBefore  = 30;               // Pause sebelum news (menit)
input int    News_MinutesAfter   = 30;               // Pause sesudah news (menit)
input bool   News_ClosePositions = false;            // Tutup posisi saat masuk window news
input ENewsSource News_Source    = NEWS_AUTO;         // SUMBER news (AUTO=live kalender + tester CSV)
input string News_CSVFile        = "AurumnNews.csv"; // Nama file CSV
input bool   News_CSVCommonFolder = true;            // File di folder Common (andal utk tester)
input int    News_CSVOffsetHours = 0;                // Jam konversi waktu CSV -> server (0=sudah server)
input bool   News_FilterUSD      = true;             // Blokir saat news USD
input bool   News_FilterEUR      = false;            // Blokir saat news EUR juga

//--- Penyimpanan event
struct SNewsEvent { datetime time; string ccy; };
SNewsEvent g_news[];
datetime   g_newsLastRefresh = 0;   // waktu muat terakhir (refresh live harian)

//--- Apakah currency event ini difilter?
bool News_CcyIncluded(const string ccy)
{
   if(!News_FilterUSD && !News_FilterEUR) return(true); // tak ada filter -> semua
   if(ccy == "USD" && News_FilterUSD) return(true);
   if(ccy == "EUR" && News_FilterEUR) return(true);
   return(false);
}

//--- Muat dari file CSV
void News_LoadCSV()
{
   int flags = FILE_READ|FILE_TXT|FILE_ANSI;
   if(News_CSVCommonFolder) flags |= FILE_COMMON;
   int h = FileOpen(News_CSVFile, flags);
   if(h == INVALID_HANDLE)
   {
      Print("[News] CSV tidak ditemukan: ", News_CSVFile,
            (News_CSVCommonFolder ? " (folder Common\\Files)" : " (MQL5\\Files)"),
            " - news filter via CSV nonaktif");
      return;
   }
   int added = 0;
   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      StringTrimLeft(line); StringTrimRight(line);
      if(StringLen(line) < 8) continue;
      if(StringGetCharacter(line, 0) == '#') continue;   // komentar

      string parts[];
      int k = StringSplit(line, ',', parts);
      if(k < 3) continue;
      string sdate = parts[0]; StringTrimLeft(sdate); StringTrimRight(sdate);
      string stime = parts[1]; StringTrimLeft(stime); StringTrimRight(stime);
      string ccy   = parts[2]; StringTrimLeft(ccy);   StringTrimRight(ccy);

      if(!News_CcyIncluded(ccy)) continue;

      datetime t = StringToTime(sdate + " " + stime);
      if(t <= 0) continue;
      t += (datetime)News_CSVOffsetHours * 3600;

      int n = ArraySize(g_news);
      ArrayResize(g_news, n + 1);
      g_news[n].time = t;
      g_news[n].ccy  = ccy;
      added++;
   }
   FileClose(h);
   Print("[News] ", added, " event dimuat dari CSV ", News_CSVFile);
}

//--- Muat dari kalender MT5 (LIVE saja; di tester fungsi ini kosong)
void News_LoadCalendar()
{
   if(MQLInfoInteger(MQL_TESTER)) return;   // kalender tak tersedia di tester

   datetime from = TimeCurrent() - 2 * 86400;
   datetime to   = TimeCurrent() + 14 * 86400;
   string ccys[]; int nc = 0;
   if(News_FilterUSD) { ArrayResize(ccys, nc + 1); ccys[nc++] = "USD"; }
   if(News_FilterEUR) { ArrayResize(ccys, nc + 1); ccys[nc++] = "EUR"; }

   int added = 0;
   for(int c = 0; c < nc; c++)
   {
      MqlCalendarValue values[];
      int n = CalendarValueHistory(values, from, to, NULL, ccys[c]);
      for(int i = 0; i < n; i++)
      {
         MqlCalendarEvent evt;
         if(!CalendarEventById(values[i].event_id, evt)) continue;
         if(evt.importance != CALENDAR_IMPORTANCE_HIGH) continue;
         int idx = ArraySize(g_news);
         ArrayResize(g_news, idx + 1);
         g_news[idx].time = values[i].time;
         g_news[idx].ccy  = ccys[c];
         added++;
      }
   }
   Print("[News] ", added, " event high-impact dimuat dari kalender MT5 (live).");
}

//--- Pilih & muat sumber aktif (dipakai Init + refresh)
void News_LoadActive()
{
   ArrayResize(g_news, 0);
   bool tester = (bool)MQLInfoInteger(MQL_TESTER);
   if(News_Source == NEWS_CSV_ONLY)      { News_LoadCSV(); return; }
   if(News_Source == NEWS_CALENDAR_ONLY) { News_LoadCalendar(); return; }
   //--- NEWS_AUTO: live=kalender dinamis (fallback CSV bila kosong), tester=CSV
   if(tester) News_LoadCSV();
   else
   {
      News_LoadCalendar();
      if(ArraySize(g_news) == 0)
      {
         Print("[News] Kalender live kosong -> fallback ke CSV.");
         News_LoadCSV();
      }
   }
}

//--- Inisialisasi
bool News_Init()
{
   ArrayResize(g_news, 0);
   g_newsLastRefresh = 0;
   if(!EnableNewsFilter) return(true);
   News_LoadActive();
   g_newsLastRefresh = TimeCurrent();
   Print("[News] sumber=", EnumToString(News_Source), " | ", ArraySize(g_news), " event aktif");
   return(true);
}

//--- Refresh berkala (LIVE saja, harian) agar event baru/berubah terbaca
void News_MaybeRefresh()
{
   if(!EnableNewsFilter) return;
   if((bool)MQLInfoInteger(MQL_TESTER)) return;             // tester: tak perlu refresh
   if(TimeCurrent() - g_newsLastRefresh < 86400) return;    // sekali sehari
   News_LoadActive();
   g_newsLastRefresh = TimeCurrent();
   Print("[News] refresh harian: ", ArraySize(g_news), " event aktif");
}

void News_Deinit() { ArrayFree(g_news); }

int News_Count() { return(ArraySize(g_news)); }

//--- Apakah waktu 'now' dalam window blackout news?
bool News_IsBlocked(datetime now)
{
   if(!EnableNewsFilter) return(false);
   long before = (long)News_MinutesBefore * 60;
   long after  = (long)News_MinutesAfter * 60;
   for(int i = 0; i < ArraySize(g_news); i++)
   {
      if(now >= g_news[i].time - before && now <= g_news[i].time + after)
         return(true);
   }
   return(false);
}

#endif // AURUMN_NEWS_FILTER_MQH
