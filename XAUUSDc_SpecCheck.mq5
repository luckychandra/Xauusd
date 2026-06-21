//+------------------------------------------------------------------+
//|                                            XAUUSDc_SpecCheck.mq5  |
//|         SCRIPT DIAGNOSTIK - Baca spesifikasi asli simbol gold     |
//|         Cara pakai: drag script ini ke chart XAUUSDc di HFM.      |
//|         Hasil muncul di tab "Experts" / "Journal".               |
//+------------------------------------------------------------------+
#property copyright "Aurumn EA"
#property version   "1.00"
#property strict
#property script_show_inputs

//--- Bisa diisi manual; default kosong = pakai simbol chart aktif
input string InpSymbol = "";   // Kosongkan untuk pakai simbol chart aktif

//+------------------------------------------------------------------+
void OnStart()
{
   string sym = (InpSymbol == "") ? _Symbol : InpSymbol;

   if(!SymbolSelect(sym, true))
   {
      Print("GAGAL memilih simbol: ", sym, ". Cek nama/suffix di Market Watch.");
      return;
   }

   //--- Ambil properti utama
   int    digits     = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double point      = SymbolInfoDouble(sym, SYMBOL_POINT);
   double tickSize   = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double tickValue  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double contract   = SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE);
   double volMin     = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double volMax     = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double volStep    = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   long   stopsLevel = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
   long   freezeLvl  = SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL);
   double ask        = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid        = SymbolInfoDouble(sym, SYMBOL_BID);
   double spreadRaw  = (ask - bid);
   long   spreadPts  = SymbolInfoInteger(sym, SYMBOL_SPREAD);
   double marginInit = 0.0;
   OrderCalcMargin(ORDER_TYPE_BUY, sym, 1.0, ask, marginInit); // margin per 1.00 lot

   //--- Hitung ukuran pip (gold: 1 pip = 10 point = 0.10)
   double pip = (digits == 3 || digits == 5 || digits == 2) ? point * 10.0 : point;

   //--- Nilai per pip untuk lot minimum (account currency)
   double valuePerPipMinLot = (tickSize > 0)
                              ? (pip / tickSize) * tickValue * volMin : 0.0;

   //--- Info akun
   string accCur   = AccountInfoString(ACCOUNT_CURRENCY);
   long   accLev   = AccountInfoInteger(ACCOUNT_LEVERAGE);
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);

   //--- Deteksi indikasi cent account
   bool likelyCent = (StringFind(accCur, "C") >= 0 || StringFind(sym, "c") == StringLen("XAUUSD"));

   //--- CETAK LAPORAN
   Print("================ SPEK SIMBOL: ", sym, " ================");
   Print("Deskripsi      : ", SymbolInfoString(sym, SYMBOL_DESCRIPTION));
   Print("Digits         : ", digits, "  | Point: ", DoubleToString(point, digits));
   Print("Tick Size      : ", DoubleToString(tickSize, digits));
   Print("Tick Value     : ", DoubleToString(tickValue, 5), " ", accCur, " / tick / 1.0 lot");
   Print("Contract Size  : ", DoubleToString(contract, 2), " (unit per 1.0 lot)");
   Print("1 Pip (harga)  : ", DoubleToString(pip, digits));
   Print("Volume Min     : ", DoubleToString(volMin, 2));
   Print("Volume Max     : ", DoubleToString(volMax, 2));
   Print("Volume Step    : ", DoubleToString(volStep, 2));
   Print("Stops Level    : ", stopsLevel, " points (jarak min SL/TP dari harga)");
   Print("Freeze Level   : ", freezeLvl, " points");
   Print("Spread skrg    : ", spreadPts, " points = ",
         DoubleToString(spreadRaw / pip, 2), " pips (raw: ",
         DoubleToString(spreadRaw, digits), ")");
   Print("Margin/1.0 lot : ", DoubleToString(marginInit, 2), " ", accCur);
   Print("---------------- NILAI RISK ----------------");
   Print("Nilai per 1 pip @ lot min (", DoubleToString(volMin,2), ") : ",
         DoubleToString(valuePerPipMinLot, 5), " ", accCur);
   Print("---------------- AKUN ----------------");
   Print("Currency       : ", accCur, (likelyCent ? "  (INDIKASI CENT ACCOUNT)" : ""));
   Print("Leverage       : 1:", accLev);
   Print("Balance        : ", DoubleToString(balance, 2), " ", accCur);
   Print("=====================================================");
   Print(">> Salin nilai-nilai ini, kita kunci ke konfigurasi Aurumn EA.");
}
//+------------------------------------------------------------------+
