//+------------------------------------------------------------------+
//|                                            AurumnSymbolSpec.mqh   |
//|     Modul spesifikasi simbol - DIKALIBRASI untuk XAUUSDc (HFM)    |
//|     Nilai dibaca runtime; konstanta di bawah = referensi/validasi |
//|     Sumber: SpecCheck pada akun HFM Cent (USC), 2026.06.20        |
//+------------------------------------------------------------------+
#ifndef AURUMN_SYMBOL_SPEC_MQH
#define AURUMN_SYMBOL_SPEC_MQH

//=== NILAI TERKONFIRMASI XAUUSDc (HFM Cent) - sebagai acuan validasi ===
#define AURUMN_EXP_DIGITS         2
#define AURUMN_EXP_POINT          0.01
#define AURUMN_EXP_TICKSIZE       0.01
#define AURUMN_EXP_TICKVALUE      1.00      // USC per tick per 1.0 lot
#define AURUMN_EXP_CONTRACT       1.00      // 1 oz per lot (cent)
#define AURUMN_EXP_PIP            0.10      // 1 pip = 10 point
#define AURUMN_EXP_VOLMIN         0.01
#define AURUMN_EXP_FREEZE         8         // points

//--- Struktur penampung spek aktual (dibaca dari broker saat runtime)
struct SAurumnSpec
{
   int      digits;
   double   point;
   double   tickSize;
   double   tickValue;       // account currency / tick / 1.0 lot
   double   contract;
   double   pip;             // ukuran 1 pip dalam harga
   double   pipValuePerLot;  // account currency per 1 pip per 1.0 lot
   double   volMin;
   double   volMax;
   double   volStep;
   long     stopsLevel;      // points
   long     freezeLevel;     // points
   long     minStopPoints;   // jarak SL/TP aman yang kita pakai (points)
   bool     isCent;
   string   accCurrency;
   bool     valid;
};

//+------------------------------------------------------------------+
//| Muat spek aktual dari broker untuk simbol tertentu               |
//| minStopBufferPts = buffer ekstra di atas stops/freeze level      |
//+------------------------------------------------------------------+
bool LoadAurumnSpec(const string sym, SAurumnSpec &s, const long minStopBufferPts = 10)
{
   s.valid = false;
   if(!SymbolSelect(sym, true))
      return(false);

   s.digits      = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   s.point       = SymbolInfoDouble(sym, SYMBOL_POINT);
   s.tickSize    = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   s.tickValue   = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   s.contract    = SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE);
   s.volMin      = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   s.volMax      = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   s.volStep     = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   s.stopsLevel  = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
   s.freezeLevel = SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL);

   //--- Ukuran pip (gold 2 digit: pip = 10 point = 0.10)
   if(s.digits == 2 || s.digits == 3 || s.digits == 5)
      s.pip = s.point * 10.0;
   else
      s.pip = s.point;

   //--- Nilai 1 pip per 1.0 lot (account currency)
   s.pipValuePerLot = (s.tickSize > 0)
                      ? (s.pip / s.tickSize) * s.tickValue : 0.0;

   //--- Jarak SL/TP minimum yang aman: max(stops, freeze) + buffer
   //    Karena stopsLevel HFM = 0, freeze = 8, buffer mencegah error reject.
   long base = (s.stopsLevel > s.freezeLevel) ? s.stopsLevel : s.freezeLevel;
   s.minStopPoints = base + minStopBufferPts;

   //--- Deteksi cent account via currency
   s.accCurrency = AccountInfoString(ACCOUNT_CURRENCY);
   s.isCent = (StringFind(s.accCurrency, "USC") >= 0 ||
               StringFind(s.accCurrency, "USc") >= 0 ||
               StringFind(s.accCurrency, "c")   == StringLen(s.accCurrency) - 1);

   s.valid = (s.pip > 0 && s.tickValue > 0 && s.volMin > 0);
   return(s.valid);
}

//+------------------------------------------------------------------+
//| Konversi risk (uang, account currency) -> lot, berdasar SL pips  |
//| Sudah dinormalisasi ke step & clamp min/max broker.              |
//+------------------------------------------------------------------+
double AurumnLotsFromRisk(const SAurumnSpec &s, double riskMoney, double slPips)
{
   if(slPips <= 0 || s.pipValuePerLot <= 0)
      return(s.volMin);

   double lots = riskMoney / (slPips * s.pipValuePerLot);

   //--- Normalisasi ke step
   if(s.volStep > 0)
      lots = MathFloor(lots / s.volStep) * s.volStep;

   //--- Clamp
   lots = MathMax(s.volMin, MathMin(s.volMax, lots));
   return(NormalizeDouble(lots, 2));
}

//+------------------------------------------------------------------+
//| Validasi spek aktual vs nilai XAUUSDc yang diharapkan (warning)  |
//| Mengembalikan true bila cocok; isi 'warn' bila ada selisih.      |
//+------------------------------------------------------------------+
bool AurumnValidateSpec(const SAurumnSpec &s, string &warn)
{
   warn = "";
   bool ok = true;
   //--- Validasi yang TIDAK tergantung denominasi akun:
   if(s.digits != AURUMN_EXP_DIGITS)
   { warn += "Digits beda (" + (string)s.digits + "). "; ok = false; }
   if(MathAbs(s.pip - AURUMN_EXP_PIP) > 1e-8)
   { warn += "Pip beda (" + DoubleToString(s.pip, 5) + "). "; ok = false; }
   if(s.pipValuePerLot <= 0)
   { warn += "PipValue tidak valid. "; ok = false; }
   //--- CATATAN: TickValue & currency tergantung denominasi.
   //    Akun live HFM = USC (cent); Strategy Tester sering = USD.
   //    Keduanya SAH (0.10 USD/pip = 10 USC/pip). Tidak dianggap error.
   return(ok);
}

#endif // AURUMN_SYMBOL_SPEC_MQH
//+------------------------------------------------------------------+
