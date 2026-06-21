//+------------------------------------------------------------------+
//|                                             AurumnTelegram.mqh    |
//|        SESI 9: TELEGRAM (notifikasi + kontrol jarak jauh)        |
//|        LIVE SAJA - WebRequest tidak jalan di Strategy Tester.    |
//|        SETUP WAJIB:                                              |
//|        1) Buat bot via @BotFather -> dapat TOKEN.               |
//|        2) Dapatkan Chat ID (chat dgn bot, buka                  |
//|           https://api.telegram.org/bot<TOKEN>/getUpdates).      |
//|        3) MT5: Tools > Options > Expert Advisors > Allow        |
//|           WebRequest -> tambah  https://api.telegram.org        |
//|        Perintah: /status /pause /resume /closeall /help         |
//+------------------------------------------------------------------+
#ifndef AURUMN_TELEGRAM_MQH
#define AURUMN_TELEGRAM_MQH

input group "=== SESI 9: TELEGRAM (live saja) ==="
input bool   UseTelegram          = false; // Aktifkan Telegram
input string Telegram_Token        = "";    // Bot token dari @BotFather
input string Telegram_ChatID       = "";    // Chat ID tujuan
input bool   Telegram_NotifyTrades = true;  // Notif buka/tutup posisi
input bool   Telegram_NotifyDaily  = true;  // Ringkasan harian
input bool   Telegram_NotifyAlerts = true;  // Notif drawdown/halt/error
input bool   Telegram_AllowCommands = true; // Terima perintah jarak jauh
input int    Telegram_PollSeconds   = 10;   // Interval cek perintah (detik)

//--- State (global, dibaca/diubah EA & modul)
long g_tgOffset            = 0;
bool g_tgPaused            = false;
bool g_tgCloseAllRequested = false;
bool g_tgStatusRequested   = false;

bool Telegram_IsPaused() { return(g_tgPaused); }

//--- URL-encode (percent-encode byte UTF-8)
string Telegram_URLEncode(string s)
{
   string out = "";
   uchar b[];
   int n = StringToCharArray(s, b, 0, WHOLE_ARRAY, CP_UTF8) - 1; // buang null
   for(int i = 0; i < n; i++)
   {
      uchar c = b[i];
      if((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
         (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~')
         out += CharToString(c);
      else
         out += StringFormat("%%%02X", c);
   }
   return(out);
}

//--- Kirim pesan
bool Telegram_Send(string text)
{
   if(!UseTelegram || Telegram_Token == "" || Telegram_ChatID == "") return(false);
   string url    = "https://api.telegram.org/bot" + Telegram_Token + "/sendMessage";
   string params = "chat_id=" + Telegram_ChatID + "&text=" + Telegram_URLEncode(text);
   char data[];
   int len = StringToCharArray(params, data, 0, WHOLE_ARRAY, CP_UTF8) - 1;
   ArrayResize(data, len); // buang terminator agar body bersih
   char result[]; string rh;
   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
   ResetLastError();
   int res = WebRequest("POST", url, headers, 5000, data, result, rh);
   if(res == -1)
   {
      int err = GetLastError();
      if(err == 4014)
         Print("[Telegram] WebRequest tidak diizinkan. Tambah https://api.telegram.org di Options > Expert Advisors.");
      else
         Print("[Telegram] Gagal kirim (error ", err, ").");
      return(false);
   }
   return(res == 200);
}

//--- Tangani satu perintah
void Telegram_HandleCommand(string text)
{
   StringTrimLeft(text); StringTrimRight(text);
   string low = text; StringToLower(low);
   if(StringFind(low, "/pause") == 0)
   { g_tgPaused = true;  Telegram_Send("Trading DIJEDA. Posisi terbuka tetap dikelola."); }
   else if(StringFind(low, "/resume") == 0)
   { g_tgPaused = false; Telegram_Send("Trading DILANJUTKAN."); }
   else if(StringFind(low, "/closeall") == 0)
   { g_tgCloseAllRequested = true; }
   else if(StringFind(low, "/status") == 0)
   { g_tgStatusRequested = true; }
   else if(StringFind(low, "/help") == 0)
   { Telegram_Send("Perintah Aurumn:\n/status - saldo & posisi\n/pause - jeda entry baru\n/resume - lanjut\n/closeall - tutup semua posisi\n/help - bantuan"); }
}

//--- Ambil & proses update (offset agar tak dobel)
void Telegram_Poll(bool handle)
{
   if(!UseTelegram || Telegram_Token == "") return;
   string url = "https://api.telegram.org/bot" + Telegram_Token +
                "/getUpdates?timeout=0&offset=" + IntegerToString(g_tgOffset);
   char data[]; char result[]; string rh;
   ResetLastError();
   int res = WebRequest("GET", url, NULL, NULL, 5000, data, 0, result, rh);
   if(res != 200) return;
   string resp = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);

   int total = StringLen(resp);
   int pos = 0;
   long maxId = g_tgOffset - 1;
   while(true)
   {
      int u = StringFind(resp, "\"update_id\":", pos);
      if(u < 0) break;
      int i = u + 12;
      long id = 0;
      while(i < total)
      {
         ushort ch = StringGetCharacter(resp, i);
         if(ch < '0' || ch > '9') break;
         id = id * 10 + (ch - '0'); i++;
      }
      if(id > maxId) maxId = id;

      //--- ekstrak "text":"..." milik update ini (sebelum update berikutnya)
      int nextU = StringFind(resp, "\"update_id\":", i);
      int bound = (nextU < 0) ? total : nextU;
      int t = StringFind(resp, "\"text\":\"", u);
      if(handle && t >= 0 && t < bound)
      {
         int ts = t + 8;
         string txt = "";
         for(int j = ts; j < total; j++)
         {
            ushort ch = StringGetCharacter(resp, j);
            if(ch == '\\') { j++; continue; }       // lewati karakter ter-escape
            if(ch == '"') break;
            txt += CharToString((uchar)ch);
         }
         if(StringLen(txt) > 0) Telegram_HandleCommand(txt);
      }
      pos = i;
   }
   g_tgOffset = maxId + 1; // update sudah diproses, jangan diambil lagi
}

//--- Inisialisasi: bersihkan backlog (jangan eksekusi perintah lama) + salam
void Telegram_Init()
{
   if(!UseTelegram) return;
   if(Telegram_Token == "" || Telegram_ChatID == "")
   {
      Print("[Telegram] Token/ChatID kosong - Telegram nonaktif.");
      return;
   }
   Telegram_Poll(false); // set offset ke update terbaru tanpa handle
   Telegram_Send("Aurumn EA aktif. Ketik /help untuk perintah.");
}

void Telegram_CheckCommands()
{
   if(!UseTelegram || !Telegram_AllowCommands) return;
   Telegram_Poll(true);
}

#endif // AURUMN_TELEGRAM_MQH
