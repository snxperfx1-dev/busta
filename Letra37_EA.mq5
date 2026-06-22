//+------------------------------------------------------------------+
//|                                                   Letra37_EA.mq5  |
//|        Fully-tradeable Expert Advisor built on the Letra 37       |
//|        decision engine (shared Letra37_Engine.mqh).              |
//|                                                                  |
//|  The EA recomputes the full multi-engine pipeline on every new   |
//|  bar of the chart timeframe, reads the V72 / engine decision for |
//|  the last CLOSED bar, and manages live trades:                   |
//|    - risk-based or fixed position sizing                          |
//|    - SL from the Invalidation engine / ATR / fixed                |
//|    - TP from the Target engine (TP1/TP2) / RR / ATR               |
//|    - partial close, break-even, ATR/point trailing                |
//|    - exits on opposite signal / invalidation / phase change       |
//|    - session filter, spread guard, daily-loss & max-trades guard  |
//+------------------------------------------------------------------+
#property copyright "Letra 37 EA (engine port)"
#property version   "1.00"
#property description "Order-placing EA driven by the Letra 37 wave-intelligence / V72 decision engine."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/AccountInfo.mqh>
#include "Letra37_Context.mqh"

//==================================================================
// EA INPUT ENUMS
//==================================================================
enum ENUM_SIG_SOURCE { SIG_ENGINE, SIG_V72, SIG_EITHER, SIG_BOTH };   // arrows / DOE / either(OR) / both(AND)
enum ENUM_LOT_MODE   { LOT_FIXED, LOT_RISK_PCT };
enum ENUM_SL_MODE    { SL_ENGINE, SL_ATR, SL_FIXED };
enum ENUM_TP_MODE    { TP_NETWORK, TP_RR, TP_ATR };   // FU/Invisible-Network attractor / RR / ATR
enum ENUM_TRAIL_MODE { TRAIL_ATR, TRAIL_POINTS };
enum ENUM_MIN_GRADE  { G_APLUS, G_A, G_B, G_C, G_D };

//==================================================================
// EA INPUTS
//==================================================================
input group "Letra37 EA - Execution"
input ENUM_SIG_SOURCE InpSignalSource   = SIG_EITHER;   // Entry source: EITHER=arrow OR DOE (both types), V72=DOE only, ENGINE=arrows only, BOTH=require both
input bool   InpTradeLongs              = true;         // Allow long trades
input bool   InpTradeShorts             = true;         // Allow short trades
input bool   InpReverseOnOpposite       = false;        // Reverse position on opposite signal
input int    InpMaxPositions            = 1;            // Max simultaneous positions (this EA)
input int    InpEngineBars              = 3000;         // Bars recomputed per new bar
input bool   InpUseLimitEntry           = false;        // Use limit at engine entry-mid (else market)
input int    InpPendingExpiryBars       = 6;            // Pending order expiry (bars; 0=GTC)

input group "Letra37 EA - Entry Filters"
input bool          InpRequireErfGate   = true;         // Require ERF entry gate open
input bool          InpRequireHtfAlign  = false;        // Require HTF alignment with trade dir
input double        InpMinConfidence    = 0.0;          // Min DOE confidence % (0=off)

input group "Letra37 EA - Risk / Sizing"
input ENUM_LOT_MODE InpLotMode          = LOT_RISK_PCT; // Position sizing mode
input double        InpFixedLot         = 0.10;         // Fixed lot (LOT_FIXED)
input double        InpRiskPercent      = 1.0;          // Risk % of equity (LOT_RISK_PCT)
input double        InpMaxLot           = 5.0;          // Hard lot cap
input int           InpMaxSpreadPoints  = 0;            // Max spread (points); 0=off (gold spreads are large!)

input group "Letra37 EA - Stop Loss"
input ENUM_SL_MODE  InpSLMode           = SL_ENGINE;    // Stop-loss source
input double        InpSLAtrMult        = 1.5;          // SL = ATR * mult (SL_ATR)
input int           InpSLFixedPoints    = 300;          // SL fixed points (SL_FIXED)
input double        InpSLEngineBufATR   = 0.10;         // Extra ATR buffer beyond engine stop
input double        InpMinSLAtr         = 1.5;          // Minimum SL distance in ATR (stops getting stopped out instantly)
input bool          InpUseKeyLevelStop  = true;         // Anchor SL beyond the recent KEY swing high/low (structure)
input int           InpSwingLookback    = 20;           // Bars scanned for the protective key swing high/low
input double        InpKeyLevelBufATR   = 0.80;         // Buffer beyond the key high/low (xATR) - gold wicks are large
input double        InpMaxSLAtr         = 10.0;         // Safety cap on total SL distance (xATR)

input group "Letra37 EA - Take Profit"
input ENUM_TP_MODE  InpTPMode           = TP_NETWORK;   // Take-profit source (FU / Invisible-Network attractor)
input double        InpTPrr             = 2.0;          // TP = RR * risk (TP_RR)
input double        InpTPAtrMult        = 3.0;          // TP = ATR * mult (TP_ATR)
input bool          InpUsePartial       = true;         // Partial close at first target
input double        InpPartialPct       = 50.0;         // Partial close % at TP1
input bool          InpMoveBEAfterTP1   = false;        // Move SL to BE after partial (off - BE now uses 3R/900 rule)

input group "Letra37 EA - Trade Management"
input bool          InpUseBreakeven     = true;         // Enable break-even
input double        InpBETriggerRR      = 3.0;          // BE trigger in RR (also see ticks below)
input double        InpBETriggerPoints  = 900;         // BE trigger in ticks/points (whichever hits first)
input int           InpBEOffsetPoints   = 20;          // BE offset (points, locked profit)
input bool          InpUseTrailing      = true;         // Enable trailing stop
input ENUM_TRAIL_MODE InpTrailMode      = TRAIL_ATR;    // Trailing mode
input double        InpTrailAtrMult     = 2.0;          // Trail distance = ATR * mult
input int           InpTrailPoints      = 200;          // Trail distance (points)
input int           InpTrailStepPoints  = 20;           // Min step to move trail (points)
input bool          InpExitOnOpposite   = true;         // Close on opposite engine signal
input bool          InpExitOnInvalid    = true;         // Close on engine invalidation
input bool          InpExitOnPhaseFlip  = false;        // Close on Absorption/Retracement phase (off - was cutting too early)
input int           InpMinHoldBars      = 5;            // Min bars to hold before ANY discretionary exit (SL/TP always active)
input bool          InpHoldWithThesis   = true;         // HOLD a bias-aligned trade through opposite signals while the thesis still supports it
input bool          InpExitOnThesisFlip = true;         // CLOSE an open trade when the dominant thesis flips against it (keeps the position matching the panel)

input group "Letra37 EA - Session / Guards"
input bool          InpUseSession       = false;        // Restrict trading hours (server time)
input int           InpSessStartHour    = 7;            // Session start hour
input int           InpSessEndHour      = 20;           // Session end hour
input bool          InpSkipFriday       = false;        // No new trades on Friday
input bool          InpCloseAtSessEnd   = false;        // Close all at session end
input double        InpMaxDailyLossPct  = 5.0;          // Halt after daily loss % (0=off)
input int           InpMaxTradesPerDay  = 20;           // Max new trades per day (0=off)

input group "Letra37 EA - Misc"
input ulong         InpMagic            = 370037;       // Magic number
input ulong         InpDeviation        = 20;           // Max slippage (points)
input string        InpComment          = "Letra37";    // Order comment
input bool          InpShowStatus       = true;         // Show status panel (Comment)

input group "Letra37 EA - v60 Context Filters"
input bool   InpUseV60Context   = true;    // Compute v60 context (network / curve-life / TIE / narrative)
input bool   InpReqNetAgree     = true;    // Require Invisible-Network bias to agree (or neutral)
input bool   InpReqStackAgree   = false;   // Require v60 fractal stack to agree
input bool   InpReqCurveAlive   = true;    // Require curve-life not DEAD at entry
input double InpCurveAliveMin   = 33.0;    // Min curve-life to allow entry
input bool   InpReqNarrative    = false;   // Require narrative not WEAKENING
input bool   InpReqTimeAlign    = false;   // Require time-cycle alignment
input double InpMinTimeAlign    = 55.0;    // Min TIE alignment %
input bool   InpBlockV60Terminal= true;    // Block entry when v60 phase is Liquidation/Terminal against dir
input bool   InpTIEBlockOpposed = true;    // TIE: block entry when a strongly-aligned cycle stack opposes
input double InpTIEStrongAlign  = 60.0;    // TIE: "strong" cycle alignment threshold %
input bool   InpAggressiveEntry = false;   // AGGRESSIVE: also enter on v60 confluence (mid-curve) - off so FU extremes lead
input bool   InpAggReqNet       = true;    // Aggressive: require network bias to agree
input bool   InpAggReqTime      = false;   // Aggressive: respect TIE-opposed block
input bool   InpFUExtremeEntry  = true;    // Enter AT the fresh FU node (the indicator's extreme) - stop beyond the wick tip
input bool   InpFURequireBias   = true;    // FU: only take a node that AGREES with the dominant bias (DOE+network+wave) - stops fading reversals
input bool   InpMultiTFEntry    = true;    // MULTI-TF: enter on a fresh Demand/Supply Return on ANY rung (M1/M3/M5/M15/H1/H4)
input int    InpMinEntryRung     = 1;      // Lowest rung allowed for a multi-TF entry (1=M1 ... 6=H4)
input double InpMinDomTransfer   = 45.0;   // Min dominance-transfer % to treat a Return as an ENTRY CYCLE (below = first strike, wait)
input double InpMinEntryProb     = 0.0;    // Optional: min entry-cycle probability % to allow a multi-TF entry (0 = off)
input bool   InpRequireAtFlip    = false;  // Optional: only take multi-TF entries when price is AT the HTF FU flip zone (terminal side)
input int    InpMinTermShifts    = 0;      // Optional: at the flip zone, require N terminal shifts (Wyckoff ~4) before entering (0 = off)
input bool   InpBlockCounterBias = true;   // VETO any entry (incl. arrows/DOE) opposing the dominant thesis (narrative+DOE+network+wave+stack)

input group "Letra37 EA - v60 Curve-Life Management"
input bool   InpUseCurveLifeExit= false;   // Exit when v60 curve-life goes DEAD (OFF - life score dips mid-run and cut winners)
input double InpCurveDeadBelow  = 32.0;    // life <= this => DEAD (close)
input bool   InpUseMigrationTrail= false;  // Keep stop at ownership-migration 0.618 band while force persists
input bool   InpUseNarrativeMgmt= false;   // Manage with narrative lineage / chain vitality (OFF - same decay-close problem)
input double InpChainExitBelow  = 25.0;    // Exit when chain vitality <= this (story decayed across curves)

//==================================================================
// EA GLOBALS
//==================================================================
CTrade        trade;
CPositionInfo posinfo;
CSymbolInfo   sym;
CAccountInfo  gAccount;

datetime gLastBarTime   = 0;
datetime gDayStamp      = 0;
double   gDayStartEquity= 0.0;
int      gTradesToday   = 0;
bool     gHalted        = false;
string   gEntryBlock    = "-";   // live reason the EA is NOT entering (shown in panel)

//--- chart-TF rates for the engine ---
datetime eaT[]; double eaO[],eaH[],eaL[],eaC[],eaVol[];

//--- per-ticket management memory ---
ulong  gMgTicket[]; double gMgInitSL[]; double gMgTP1[]; bool gMgPartialDone[]; bool gMgBEDone[]; int gMgDir[];

//==================================================================
// HELPERS
//==================================================================
int GradeRank(const string g)
{
   if(g=="A+") return(4); if(g=="A") return(3); if(g=="B") return(2); if(g=="C") return(1); return(0);
}
int MinGradeRank(const ENUM_MIN_GRADE g)
{
   switch(g){ case G_APLUS: return(4); case G_A: return(3); case G_B: return(2); case G_C: return(1); }
   return(0);
}
double NormPrice(const double p){ return(NormalizeDouble(p,_Digits)); }
double PointVal(){ return(_Point); }

double MinStopDist()
{
   double sl=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   double fr=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL)*_Point;
   return(MathMax(sl,fr));
}

double NormalizeLot(double lot)
{
   double minlot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxlot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step =SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0) step=0.01;
   lot=MathFloor(lot/step)*step;
   if(lot<minlot) lot=minlot;
   if(lot>maxlot) lot=maxlot;
   if(lot>InpMaxLot) lot=InpMaxLot;
   return(lot);
}

double MoneyPerPointPerLot()
{
   double tickVal=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickSize<=0) tickSize=_Point;
   return(tickVal*(_Point/tickSize));
}

double CalcLot(const double entry,const double sl)
{
   if(InpLotMode==LOT_FIXED) return(NormalizeLot(InpFixedLot));
   double riskMoney=gAccount.Equity()*InpRiskPercent/100.0;
   double slPts=MathAbs(entry-sl)/_Point;
   double mpp=MoneyPerPointPerLot();
   if(slPts<1 || mpp<=0) return(NormalizeLot(InpFixedLot));
   double lot=riskMoney/(slPts*mpp);
   return(NormalizeLot(lot));
}

//--- management memory ---
int MgIndex(const ulong tk){ for(int q=0;q<ArraySize(gMgTicket);q++) if(gMgTicket[q]==tk) return(q); return(-1); }
void MgRegister(const ulong tk,const double initSL,const double tp1,const int dir)
{
   if(MgIndex(tk)>=0) return;
   int s=ArraySize(gMgTicket);
   ArrayResize(gMgTicket,s+1);ArrayResize(gMgInitSL,s+1);ArrayResize(gMgTP1,s+1);ArrayResize(gMgPartialDone,s+1);ArrayResize(gMgBEDone,s+1);ArrayResize(gMgDir,s+1);
   gMgTicket[s]=tk; gMgInitSL[s]=initSL; gMgTP1[s]=tp1; gMgPartialDone[s]=false; gMgBEDone[s]=false; gMgDir[s]=dir;
}
void MgCleanup()
{
   for(int q=ArraySize(gMgTicket)-1;q>=0;q--){
      if(!posinfo.SelectByTicket(gMgTicket[q])){
         ArrayRemove(gMgTicket,q,1);ArrayRemove(gMgInitSL,q,1);ArrayRemove(gMgTP1,q,1);ArrayRemove(gMgPartialDone,q,1);ArrayRemove(gMgBEDone,q,1);ArrayRemove(gMgDir,q,1);
      }
   }
}

int CountOwnPositions()
{
   int n=0;
   for(int q=PositionsTotal()-1;q>=0;q--){
      ulong tk=PositionGetTicket(q);
      if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)==(long)InpMagic && PositionGetString(POSITION_SYMBOL)==_Symbol) n++;
   }
   return(n);
}
int OwnPositionDir()  // returns +1/-1 of first own position, 0 if none
{
   for(int q=PositionsTotal()-1;q>=0;q--){
      ulong tk=PositionGetTicket(q);
      if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)==(long)InpMagic && PositionGetString(POSITION_SYMBOL)==_Symbol)
         return(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1);
   }
   return(0);
}
bool OwnYoungerThan(const int bars)   // true if any own position has been open < bars
{
   int ps=MathMax(PeriodSeconds(_Period),1);
   for(int q=PositionsTotal()-1;q>=0;q--){
      ulong tk=PositionGetTicket(q);
      if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)InpMagic || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      int held=(int)((TimeCurrent()-(datetime)PositionGetInteger(POSITION_TIME))/ps);
      if(held<bars) return(true);
   }
   return(false);
}
void CloseOwnPositions(const int dirFilter=0) // dirFilter 0=all, 1=longs, -1=shorts
{
   for(int q=PositionsTotal()-1;q>=0;q--){
      ulong tk=PositionGetTicket(q);
      if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)InpMagic || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      int d=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      if(dirFilter!=0 && d!=dirFilter) continue;
      trade.PositionClose(tk);
   }
}
void DeletePendingOrders()
{
   for(int q=OrdersTotal()-1;q>=0;q--){
      ulong tk=OrderGetTicket(q);
      if(tk==0) continue;
      if(OrderGetInteger(ORDER_MAGIC)==(long)InpMagic && OrderGetString(ORDER_SYMBOL)==_Symbol)
         trade.OrderDelete(tk);
   }
}

//==================================================================
// OnInit
//==================================================================
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviation);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);
   sym.Name(_Symbol);

   showOriginShort=(originMode==OM_SHORT||originMode==OM_BOTH);
   showOriginLong =(originMode==OM_LONG ||originMode==OM_BOTH);
   ResetState();
   g_lastProcessed=-1;

   gDayStamp=0; gTradesToday=0; gHalted=false;
   gDayStartEquity=gAccount.Equity();
   gLastBarTime=0;
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){ Comment(""); }

//==================================================================
// DAILY GUARD
//==================================================================
void DailyRollover()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   datetime dayKey=(datetime)(dt.year*10000+dt.mon*100+dt.day);
   if(dayKey!=gDayStamp){
      gDayStamp=dayKey; gTradesToday=0; gHalted=false; gDayStartEquity=gAccount.Equity();
   }
   if(InpMaxDailyLossPct>0.0){
      double dd=(gDayStartEquity-gAccount.Equity())/MathMax(gDayStartEquity,1.0)*100.0;
      if(dd>=InpMaxDailyLossPct){ gHalted=true; }
   }
}

bool SessionOK()
{
   if(!InpUseSession) return(true);
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(InpSkipFriday && dt.day_of_week==5) return(false);
   if(InpSessStartHour<=InpSessEndHour)
      return(dt.hour>=InpSessStartHour && dt.hour<InpSessEndHour);
   return(dt.hour>=InpSessStartHour || dt.hour<InpSessEndHour);
}

//==================================================================
// ENGINE COMPUTE (full recompute over window each new bar)
//==================================================================
void ComputeEngine()
{
   int want=InpEngineBars;
   MqlRates r[]; ArraySetAsSeries(r,false);
   int got=CopyRates(_Symbol,_Period,0,want,r);
   if(got<=0) return;
   ArrayResize(eaT,got);ArrayResize(eaO,got);ArrayResize(eaH,got);ArrayResize(eaL,got);ArrayResize(eaC,got);ArrayResize(eaVol,got);
   for(int q=0;q<got;q++){ eaT[q]=r[q].time; eaO[q]=r[q].open; eaH[q]=r[q].high; eaL[q]=r[q].low; eaC[q]=r[q].close; eaVol[q]=(double)r[q].tick_volume; }
   int warmup=MathMax(2*structLen,2*pivotLen)+effLen+10;
   if(got<warmup+5) return;
   ResetState();
   EngineRun(got,eaT,eaO,eaH,eaL,eaC,eaVol,MathMax(warmup,got-InpEngineBars));
   if(InpUseV60Context) ContextRun(InpEngineBars);   // v60 context (does not alter Letra cur_* decision)
}

//==================================================================
// DECISION + ENTRY
//==================================================================
int DesiredDirection()
{
   bool engLong=cur_longSignal, engShort=cur_shortSignal;
   bool v72Long =(cur_doeAction=="Long"),  v72Short=(cur_doeAction=="Short");
   if(InpSignalSource==SIG_ENGINE) return(engLong?1:engShort?-1:0);
   if(InpSignalSource==SIG_V72)    return(v72Long?1:v72Short?-1:0);
   if(InpSignalSource==SIG_BOTH){ if(engLong&&v72Long) return(1); if(engShort&&v72Short) return(-1); return(0); }
   // SIG_EITHER: the arrow is the faster, precise trigger -> it LEADS; the DOE is the
   // continuously-updating next-entry bias and fills in when no arrow fired.
   // No conflict suppression: a fresh opposite arrow simply flips the trade
   // (handled in TryEnter via exit-on-opposite / reverse).
   if(engLong)  return(1);
   if(engShort) return(-1);
   if(v72Long)  return(1);
   if(v72Short) return(-1);
   return(0);
}

//--- dominant directional consensus.
//--- the DOMINANT thesis direction. The headline command narrative leads (it is what
//--- the panel literally prints, e.g. "Bullish reversal developing"); the DOE decision
//--- confirms; only if BOTH are neutral do we fall back to the structural consensus.
//--- The lagging stack/pressure/wave do NOT get to cancel a clear thesis (they stay
//--- bearish during a developing bullish reversal, which is exactly when we were
//--- wrongly selling). 0 = no clear thesis.
int ConsensusBias()
{
   //--- 1) command narrative = the headline thesis on the panel ---
   if(StringFind(cur_cmdNarrative,"invalidated")<0){
      if(StringFind(cur_cmdNarrative,"Bull")>=0) return(1);
      if(StringFind(cur_cmdNarrative,"Bear")>=0) return(-1);
   }
   //--- 2) DOE decision authority ---
   if(cur_doeAction=="Long")  return(1);
   if(cur_doeAction=="Short") return(-1);
   if(StringFind(cur_doeBias,"Bull")>=0) return(1);
   if(StringFind(cur_doeBias,"Bear")>=0) return(-1);
   //--- 3) fallback: structural consensus (network + wave + stack) ---
   int v=ctx_netBias+ctx_waveDir;
   if(ctx_stackDir>0) v+=1; else if(ctx_stackDir<0) v-=1;
   if(v>0) return(1);
   if(v<0) return(-1);
   return(0);
}

bool PassesFilters(const int dir)
{
   if(dir==1 && !InpTradeLongs){ gEntryBlock="longs off"; return(false); }
   if(dir==-1&& !InpTradeShorts){ gEntryBlock="shorts off"; return(false); }
   if(InpRequireErfGate && !cur_erfEntryGate){ gEntryBlock="ERF gate shut"; return(false); }
   if(InpRequireHtfAlign && !(cur_htfAlign==dir || cur_htfAlign==0)){ gEntryBlock="HTF align"; return(false); }
   if(InpMinConfidence>0.0 && cur_doeConfidence<InpMinConfidence){ gEntryBlock="DOE conf low"; return(false); }
   if(cur_invInvalidated){ gEntryBlock="invalidated"; return(false); }
   //--- v60 context filters (Letra still decides; these only confirm/veto) ---
   if(InpUseV60Context){
      if(InpReqNetAgree   && !(ctx_netBias==dir || ctx_netBias==0)){ gEntryBlock="network disagrees"; return(false); }
      if(InpReqStackAgree && ctx_stackDir!=dir){ gEntryBlock="stack disagrees"; return(false); }
      if(InpReqCurveAlive && ctx_life<InpCurveAliveMin){ gEntryBlock="curve weak"; return(false); }
      if(InpReqNarrative  && ctx_narrState=="WEAKENING"){ gEntryBlock="narrative weak"; return(false); }
      if(InpReqTimeAlign  && ctx_timeAlign<InpMinTimeAlign){ gEntryBlock="time align low"; return(false); }
      if(InpBlockV60Terminal && (ctx_phase=="Liquidation"||ctx_phase=="Terminal Curve") && ctx_waveDir!=0 && ctx_waveDir!=dir){ gEntryBlock="v60 terminal vs dir"; return(false); }
      if(InpTIEBlockOpposed && ctx_timeAlign>=InpTIEStrongAlign && ctx_timeDir!=0 && ctx_timeDir!=dir){ gEntryBlock="TIE opposed"; return(false); }
   }
   return(true);
}

//--- protective stop just beyond the recent KEY swing high/low (real structure).
//--- long  -> below the lowest low of the last InpSwingLookback closed bars
//--- short -> above the highest high of the last InpSwingLookback closed bars
//--- returns 0.0 when disabled or unavailable.
double KeyLevelStop(const int dir,const double entry)
{
   if(!InpUseKeyLevelStop) return(0.0);
   double atr=cur_atr; if(atr<=0) atr=10*_Point;
   int lb=InpSwingLookback; if(lb<2) lb=2;
   double buf=InpKeyLevelBufATR*atr;
   double s=0.0;
   if(dir==1){
      int idx=iLowest(_Symbol,_Period,MODE_LOW,lb,1);     // 1 = skip the still-forming bar
      if(idx>=0){ double lo=iLow(_Symbol,_Period,idx); if(lo>0) s=lo-buf; }
      //--- fold in the engine's structural invalidation (take whichever protects more = lower) ---
      if(!naf(cur_invActiveStop) && cur_invActiveStop<entry){ double e=cur_invActiveStop-buf; if(s==0.0 || e<s) s=e; }
      return( s<entry ? s : 0.0 );                        // must sit below entry to be valid
   } else {
      int idx=iHighest(_Symbol,_Period,MODE_HIGH,lb,1);
      if(idx>=0){ double hi=iHigh(_Symbol,_Period,idx); if(hi>0) s=hi+buf; }
      if(!naf(cur_invActiveStop) && cur_invActiveStop>entry){ double e=cur_invActiveStop+buf; if(s==0.0 || e>s) s=e; }
      return( s>entry ? s : 0.0 );                        // must sit above entry to be valid
   }
}

double ComputeSL(const int dir,const double entry)
{
   double atr=cur_atr; if(atr<=0) atr=10*_Point;
   double sl;
   if(InpSLMode==SL_ENGINE && !naf(cur_invActiveStop)){
      sl=cur_invActiveStop + (dir==1? -atr*InpSLEngineBufATR : atr*InpSLEngineBufATR);
   } else if(InpSLMode==SL_FIXED){
      sl=entry + (dir==1? -InpSLFixedPoints*_Point : InpSLFixedPoints*_Point);
   } else {
      sl=entry + (dir==1? -atr*InpSLAtrMult : atr*InpSLAtrMult);
   }
   //--- push the stop BEYOND the recent key swing high/low so structure protects it ---
   double ks=KeyLevelStop(dir,entry);
   if(ks!=0.0){
      if(dir==1)  sl=MathMin(sl,ks);   // long: take the lower (more protective) stop
      else        sl=MathMax(sl,ks);   // short: take the higher (more protective) stop
   }
   //--- enforce correct side + minimum stop distance (broker min AND >= InpMinSLAtr*ATR) ---
   double minD=MathMax(MinStopDist()+_Point, InpMinSLAtr*atr);
   if(dir==1  && sl>entry-minD) sl=entry-minD;
   if(dir==-1 && sl<entry+minD) sl=entry+minD;
   //--- safety cap so a runaway swing can't create an absurd stop ---
   double maxD=InpMaxSLAtr*atr;
   if(dir==1  && sl<entry-maxD) sl=entry-maxD;
   if(dir==-1 && sl>entry+maxD) sl=entry+maxD;
   return(NormPrice(sl));
}

double ComputeTP(const int dir,const double entry,const double sl)
{
   double atr=cur_atr; if(atr<=0) atr=10*_Point;
   double risk=MathAbs(entry-sl);
   double tp=0.0;
   if(InpTPMode==TP_NETWORK){
      // FU pool / Invisible-Network attractor — the magnet price is heading for
      tp = !naf(ctx_netTarget)?ctx_netTarget : !naf(ctx_attractorPx)?ctx_attractorPx : entry+(dir==1? risk*InpTPrr : -risk*InpTPrr);
   } else if(InpTPMode==TP_ATR){
      tp=entry+(dir==1? atr*InpTPAtrMult : -atr*InpTPAtrMult);
   } else {
      tp=entry+(dir==1? risk*InpTPrr : -risk*InpTPrr);
   }
   //--- validate side; fall back to RR if engine target is on the wrong side ---
   if((dir==1 && tp<=entry) || (dir==-1 && tp>=entry))
      tp=entry+(dir==1? risk*InpTPrr : -risk*InpTPrr);
   double minD=MinStopDist()+_Point;
   if(dir==1  && tp<entry+minD) tp=entry+minD;
   if(dir==-1 && tp>entry-minD) tp=entry-minD;
   return(NormPrice(tp));
}

void TryEnter()
{
   int dir=DesiredDirection();
   bool aggressive=false, fuEntry=false, mtfEntry=false;
   //--- PRIORITY: enter AT the fresh FU node (the indicator's extreme) ---
   if(dir==0 && InpUseV60Context && InpFUExtremeEntry && ctx_fuFresh && ctx_fuDir!=0){
      int cb=ConsensusBias();
      if(InpFURequireBias && cb!=0 && ctx_fuDir!=cb){
         gEntryBlock="FU "+(ctx_fuDir==1?"buy":"sell")+" node opposes "+(cb==1?"bull":"bear")+" bias";
      } else {
         dir=ctx_fuDir; aggressive=true; fuEntry=true;
      }
   }
   //--- MULTI-TF: a fresh Demand/Supply Return on ANY rung (M1..H4) — the EA sees every timeframe ---
   //  Only a genuine ENTRY CYCLE (dominance transferred to the recursive wave) qualifies;
   //  a first strike (low dominance) is skipped — the curve is still building.
   if(dir==0 && InpMultiTFEntry && cur_mtfEntryFresh && cur_mtfEntryDir!=0 && cur_mtfEntryWt>=InpMinEntryRung){
      if(cur_mtfEntryDom>=InpMinDomTransfer && cur_entryProb>=InpMinEntryProb && (!InpRequireAtFlip || !InpUseV60Context || ctx_atFlip) && (InpMinTermShifts<=0 || !InpUseV60Context || !ctx_atFlip || ctx_termShifts>=InpMinTermShifts)){ dir=cur_mtfEntryDir; aggressive=true; mtfEntry=true; }
      else if(cur_mtfEntryDom<InpMinDomTransfer) gEntryBlock="first strike "+cur_mtfEntryTF+" (dom "+IntegerToString((int)cur_mtfEntryDom)+"% < entry cycle)";
      else if(InpRequireAtFlip && InpUseV60Context && !ctx_atFlip) gEntryBlock="not at flip zone ("+DoubleToString(ctx_distFlipAtr,1)+"ATR away)";
      else if(InpMinTermShifts>0 && InpUseV60Context && ctx_atFlip && ctx_termShifts<InpMinTermShifts) gEntryBlock="terminal building "+IntegerToString(ctx_termShifts)+"/"+IntegerToString(InpMinTermShifts)+" shifts";
      else gEntryBlock="entry prob low "+IntegerToString((int)cur_entryProb)+"%";
   }
   //--- aggressive v60-confluence entry when strict Letra has no signal ---
   if(dir==0 && InpUseV60Context && InpAggressiveEntry){
      int adir=ctx_waveDir;
      bool ok = adir!=0
             && (!InpAggReqNet || ctx_netBias==adir || ctx_netBias==0)
             && ctx_life>=InpCurveAliveMin
             && !((ctx_phase=="Liquidation"||ctx_phase=="Terminal Curve") && ctx_waveDir!=adir)
             && !(InpAggReqTime && InpTIEBlockOpposed && ctx_timeAlign>=InpTIEStrongAlign && ctx_timeDir!=0 && ctx_timeDir!=adir);
      if(ok){ dir=adir; aggressive=true; }
   }
   if(dir==0){ gEntryBlock=(InpUseV60Context&&InpAggressiveEntry)?"no signal / v60 not aligned":"no signal (awaiting Return)"; return; }
   //--- UNIFIED counter-bias veto: never trade against the dominant thesis (covers arrows, DOE, aggressive, FU).
   //--- This is what stops shorts while "Bullish reversal developing" is on the panel. ---
   if(InpBlockCounterBias){
      int cb=ConsensusBias();
      if(cb!=0 && dir!=cb){ gEntryBlock=(dir==1?"long":"short")+" vetoed vs "+(cb==1?"BULL":"BEAR")+" thesis"; return; }
   }
   if(!aggressive){
      if(!PassesFilters(dir)) return;          // strict Letra path keeps full filters
   } else {
      if(dir==1 && !InpTradeLongs){ gEntryBlock="longs off"; return; }     // aggressive path: light gating only
      if(dir==-1&& !InpTradeShorts){ gEntryBlock="shorts off"; return; }
      if(cur_invInvalidated){ gEntryBlock="invalidated"; return; }
   }
   if(!SessionOK()){ gEntryBlock="session closed"; return; }
   if(gHalted){ gEntryBlock="halted (daily loss)"; return; }
   if(InpMaxTradesPerDay>0 && gTradesToday>=InpMaxTradesPerDay){ gEntryBlock="max trades/day"; return; }
   if(InpMaxSpreadPoints>0){ long sp=(long)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD); if(sp>InpMaxSpreadPoints){ gEntryBlock="spread "+IntegerToString((int)sp); return; } }

   int ownDir=OwnPositionDir();
   if(ownDir!=0 && ownDir!=dir){
      if(OwnYoungerThan(InpMinHoldBars)){ gEntryBlock="hold (young pos, no flip)"; return; }   // don't flip a fresh trade
      if(InpReverseOnOpposite){ CloseOwnPositions(0); DeletePendingOrders(); }
      else if(InpExitOnOpposite){ CloseOwnPositions(-dir); }
      else { gEntryBlock="opposite pos open"; return; }
   }
   if(CountOwnPositions()>=InpMaxPositions){ gEntryBlock="max positions"; return; }

   sym.RefreshRates();
   double ask=sym.Ask(), bid=sym.Bid();
   double entry=(dir==1?ask:bid);
   double slBase;
   if(fuEntry && !naf(ctx_fuTip)){
      double a=cur_atr; if(a<=0) a=10*_Point;
      slBase=(dir==1? ctx_fuTip - InpMinSLAtr*a : ctx_fuTip + InpMinSLAtr*a);   // stop BEYOND the FU wick extreme
      //--- and push it beyond the recent key swing high/low (whichever protects more) ---
      double ks=KeyLevelStop(dir,entry);
      if(ks!=0.0){
         if(dir==1)  slBase=MathMin(slBase,ks);
         else        slBase=MathMax(slBase,ks);
      }
      double minD=MathMax(MinStopDist()+_Point, InpMinSLAtr*a);
      if(dir==1 && slBase>entry-minD) slBase=entry-minD;
      if(dir==-1&& slBase<entry+minD) slBase=entry+minD;
      double maxD=InpMaxSLAtr*a;                                                // safety cap
      if(dir==1 && slBase<entry-maxD) slBase=entry-maxD;
      if(dir==-1&& slBase>entry+maxD) slBase=entry+maxD;
      slBase=NormPrice(slBase);
   } else slBase=ComputeSL(dir,entry);
   //--- multi-TF entry: anchor the stop beyond THAT rung's invalidation (+ key swing) ---
   if(mtfEntry && !naf(cur_mtfEntryInv)){
      double a=cur_atr; if(a<=0) a=10*_Point;
      double s2=cur_mtfEntryInv + (dir==1? -InpSLEngineBufATR*a : InpSLEngineBufATR*a);
      double ks=KeyLevelStop(dir,entry);
      if(ks!=0.0){ if(dir==1) s2=MathMin(s2,ks); else s2=MathMax(s2,ks); }
      double minD=MathMax(MinStopDist()+_Point, InpMinSLAtr*a);
      if(dir==1 && s2>entry-minD) s2=entry-minD;
      if(dir==-1&& s2<entry+minD) s2=entry+minD;
      double maxD=InpMaxSLAtr*a;
      if(dir==1 && s2<entry-maxD) s2=entry-maxD;
      if(dir==-1&& s2>entry+maxD) s2=entry+maxD;
      slBase=NormPrice(s2);
   }
   double lot=CalcLot(entry,slBase);
   double tp=ComputeTP(dir,entry,slBase);
   bool _arrow=(dir==1?cur_longSignal:cur_shortSignal);
   bool _doe=(dir==1?(cur_doeAction=="Long"):(cur_doeAction=="Short"));
   string _trig=fuEntry?"FU":mtfEntry?("MTF:"+cur_mtfEntryTF):aggressive?"V60AGG":(_arrow&&_doe)?"ARROW+DOE":_arrow?"ARROW":"DOE";
   string cmt=InpComment+" "+_trig+" "+cur_tqeGrade;

   bool ok=false;
   if(InpUseLimitEntry && !naf(cur_doeEntryMid)){
      double lim=NormPrice(cur_doeEntryMid);
      double slL=ComputeSL(dir,lim);
      double tpL=ComputeTP(dir,lim,slL);
      double lotL=CalcLot(lim,slL);
      datetime exp=(InpPendingExpiryBars>0)?(TimeCurrent()+(datetime)(InpPendingExpiryBars*PeriodSeconds(_Period))):0;
      ENUM_ORDER_TYPE_TIME tt=(exp>0?ORDER_TIME_SPECIFIED:ORDER_TIME_GTC);
      trade.SetTypeFillingBySymbol(_Symbol);
      if(dir==1) ok=trade.BuyLimit(lotL,lim,_Symbol,slL,tpL,tt,exp,cmt);
      else       ok=trade.SellLimit(lotL,lim,_Symbol,slL,tpL,tt,exp,cmt);
   } else {
      if(dir==1) ok=trade.Buy(lot,_Symbol,ask,slBase,tp,cmt);
      else       ok=trade.Sell(lot,_Symbol,bid,slBase,tp,cmt);
   }
   if(ok){
      gTradesToday++;
      gEntryBlock="ENTERED "+_trig;
      ulong tk=trade.ResultOrder();
      // register live position (market entries fill immediately)
      if(posinfo.SelectByTicket(trade.ResultDeal())) {}
      // best-effort: register by scanning newest own position
      for(int q=PositionsTotal()-1;q>=0;q--){
         ulong pt=PositionGetTicket(q);
         if(pt==0) continue;
         if(PositionGetInteger(POSITION_MAGIC)==(long)InpMagic && PositionGetString(POSITION_SYMBOL)==_Symbol){
            double psl=PositionGetDouble(POSITION_SL);
            double _tp1net=!naf(ctx_netTarget)?ctx_netTarget:ctx_attractorPx;   // FU/Network target for partial
            MgRegister(pt,psl,_tp1net,dir);
            break;
         }
      }
   }
}

//==================================================================
// POSITION MANAGEMENT (every tick)
//==================================================================
void ManagePositions()
{
   double atr=cur_atr; if(atr<=0) atr=10*_Point;
   for(int q=PositionsTotal()-1;q>=0;q--){
      ulong tk=PositionGetTicket(q);
      if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)InpMagic || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      int    dir   =PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      double openP =PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL =PositionGetDouble(POSITION_SL);
      double curTP =PositionGetDouble(POSITION_TP);
      double vol   =PositionGetDouble(POSITION_VOLUME);
      sym.RefreshRates();
      double mkt   =(dir==1?sym.Bid():sym.Ask());
      int    mi    =MgIndex(tk);
      double initSL=(mi>=0?gMgInitSL[mi]:curSL);
      double risk  =MathAbs(openP-initSL); if(risk<=0) risk=atr;
      double rMult =(dir==1?(mkt-openP):(openP-mkt))/risk;

      //--- bars this position has been open (gate discretionary exits) ---
      int heldBars=(int)((TimeCurrent()-(datetime)PositionGetInteger(POSITION_TIME))/MathMax(PeriodSeconds(_Period),1));
      bool canSoftExit=(heldBars>=InpMinHoldBars);
      //--- always-on protective exits (broker SL/TP also always active) ---
      if(InpCloseAtSessEnd && !SessionOK()){ trade.PositionClose(tk); continue; }
      //--- discretionary exits: only after the minimum hold (stops cutting straight away) ---
      //--- while the dominant thesis still backs this trade, HOLD through opposite blips ---
      int  cbHold=ConsensusBias();
      bool thesisSupports=(InpHoldWithThesis && cbHold!=0 && cbHold==dir);
      //--- THESIS FLIP: the panel's bias has turned against this open trade -> close it
      //--- (this is what removes a lingering short while the panel now reads "Bullish ...", and vice versa) ---
      if(canSoftExit && InpExitOnThesisFlip && cbHold!=0 && cbHold!=dir){ trade.PositionClose(tk); continue; }
      if(canSoftExit && !thesisSupports){
         if(InpExitOnInvalid && cur_invInvalidated){ trade.PositionClose(tk); continue; }
         if(InpExitOnPhaseFlip && (cur_ie1aPhase=="Absorption"||cur_ie1aPhase=="Retracement")){ trade.PositionClose(tk); continue; }
         if(InpExitOnOpposite && ((dir==1&&cur_shortSignal)||(dir==-1&&cur_longSignal))){ trade.PositionClose(tk); continue; }
      }
      if(canSoftExit){
         //--- v60 curve-life exit: close when the curve in our direction goes DEAD ---
         if(InpUseV60Context && InpUseCurveLifeExit && ctx_life<=InpCurveDeadBelow && dir==ctx_waveDir){ trade.PositionClose(tk); continue; }
         //--- v60 narrative management: decayed chain -> exit; fading story -> lock to break-even ---
         if(InpUseV60Context && InpUseNarrativeMgmt && dir==ctx_waveDir){
            if(ctx_chainVitality<=InpChainExitBelow){ trade.PositionClose(tk); continue; }
            if(ctx_narrState=="WEAKENING" && !ctx_converging){
               double be=openP+(dir==1?InpBEOffsetPoints*_Point:-InpBEOffsetPoints*_Point); be=NormPrice(be);
               bool improve=(dir==1?(be>curSL):(curSL==0||be<curSL));
               if(improve && trade.PositionModify(tk,be,curTP)){ if(mi>=0) gMgBEDone[mi]=true; curSL=be; }
            }
         }
      }

      //--- partial close at TP1 ---
      if(InpUsePartial && mi>=0 && !gMgPartialDone[mi] && !naf(gMgTP1[mi])){
         bool hit=(dir==1? mkt>=gMgTP1[mi] : mkt<=gMgTP1[mi]);
         if(hit){
            double closeVol=NormalizeLot(vol*InpPartialPct/100.0);
            if(closeVol>0 && closeVol<vol){
               if(trade.PositionClosePartial(tk,closeVol)){ gMgPartialDone[mi]=true;
                  if(InpMoveBEAfterTP1){ double be=openP+(dir==1?InpBEOffsetPoints*_Point:-InpBEOffsetPoints*_Point); be=NormPrice(be);
                     if((dir==1&&be>curSL)||(dir==-1&&(curSL==0||be<curSL))) trade.PositionModify(tk,be,curTP); gMgBEDone[mi]=true; }
               }
            }
         }
      }

      //--- profit zone gate: BE + trailing only kick in after 3R OR 900 ticks (whichever first) ---
      double profitPts =(dir==1?(mkt-openP):(openP-mkt))/_Point;
      bool   inProfitZone=(rMult>=InpBETriggerRR || profitPts>=InpBETriggerPoints);

      //--- break-even ---
      if(InpUseBreakeven && inProfitZone && (mi<0||!gMgBEDone[mi])){
         double be=openP+(dir==1?InpBEOffsetPoints*_Point:-InpBEOffsetPoints*_Point); be=NormPrice(be);
         bool improve=(dir==1?(be>curSL):(curSL==0||be<curSL));
         if(improve && trade.PositionModify(tk,be,curTP)){ if(mi>=0) gMgBEDone[mi]=true; curSL=be; }
      }

      //--- trailing (only once we're in the profit zone, so we never trail a fresh trade out) ---
      if(InpUseTrailing && inProfitZone){
         double dist=(InpTrailMode==TRAIL_ATR?atr*InpTrailAtrMult:InpTrailPoints*_Point);
         double minD=MinStopDist()+_Point; if(dist<minD) dist=minD;
         double newSL=(dir==1? mkt-dist : mkt+dist);
         if(InpUseV60Context && InpUseMigrationTrail && ctx_cpState=="PERSISTING" && dir==ctx_waveDir && !naf(ctx_mig618)){
            double m=ctx_mig618;
            if((dir==1 && m<mkt) || (dir==-1 && m>mkt)) newSL=m;   // defend the migrated 0.618 band
         }
         newSL=NormPrice(newSL);
         double step=InpTrailStepPoints*_Point;
         bool improve=(dir==1?(newSL>curSL+step):(curSL==0||newSL<curSL-step));
         // never trail to the losing side of entry before BE
         if(dir==1 && newSL<openP && !(mi>=0&&gMgBEDone[mi])) improve=improve&&false;
         if(dir==-1&& newSL>openP && !(mi>=0&&gMgBEDone[mi])) improve=improve&&false;
         if(improve) trade.PositionModify(tk,newSL,curTP);
      }
   }
}

//==================================================================
// STATUS PANEL
//==================================================================
void ShowStatus()
{
   if(!InpShowStatus) return;
   string s="";
   s+="LETRA 37 EA  ["+_Symbol+","+EnumToString(_Period)+"]\n";
   s+="Phase  : "+cur_currentDisplayPhase+"  (M5 "+f_waveDirLabel(cur_dirM5)+")\n";
   s+="DOE    : "+cur_doeAction+"  conf "+R0(cur_doeConfidence)+"%  bias "+cur_doeBias+"\n";
   s+="Grade  : eng "+cur_grade+"  TQE "+cur_tqeGrade+"  risk "+cur_tqeRisk+"\n";
   s+="Opp    : "+cur_oppState+" "+R0(cur_oppProgress)+"%   ERF gate "+(cur_erfEntryGate?"OPEN":"SHUT")+"\n";
   s+="Stop   : "+PXs(cur_invActiveStop)+(cur_invInvalidated?" [INVALID]":"")+"   Target "+PXs(!naf(ctx_netTarget)?ctx_netTarget:ctx_attractorPx)+"\n";
   s+="Dest   : "+cur_tplWinnerClass+" "+PXs(cur_tplMainTarget)+" ("+cur_tplSource+")\n";
   s+="Pos    : "+IntegerToString(CountOwnPositions())+"   TradesToday "+IntegerToString(gTradesToday)+(gHalted?"  [HALTED]":"")+"\n";
   s+="Gate   : "+gEntryBlock+"\n";
   s+="Curve  : own "+cur_curveOwner+" "+f_waveDirLabel(cur_ownerDir)+"  "+cur_transState+"  ["+cur_entryReady+"]\n";
   s+="Recur  : dom "+R0(cur_domTransfer)+"%  comp "+cur_compRegime+"  depth "+IntegerToString(cur_recDepth)+"/"+IntegerToString(cur_expRecDepth)+(cur_mtfEntryFresh?("  | RET "+cur_mtfEntryTF+" "+(cur_mtfEntryDir==1?"L":"S")+" dom "+R0(cur_mtfEntryDom)+"%"):"")+"\n";
   s+="Cap    : budget "+R0(cur_curveBudget)+"%  toFlip "+DoubleToString(cur_distFlipAtr,1)+"ATR  entryP "+R0(cur_entryProb)+"%\n";
   if(InpUseV60Context) s+="Camp   : "+ctx_campaign+"  toFlip "+DoubleToString(ctx_distFlipAtr,1)+"ATR"+(ctx_atFlip?("  shifts "+IntegerToString(ctx_termShifts)+"/"+IntegerToString(ctx_termExpected)+(ctx_termComplete?" DONE":"")):"")+(ctx_fuMerged?"  [FU merged->parent]":"")+"\n";
   s+="Narr   : "+cur_cmdNarrative;
   if(InpUseV60Context){
      s+="\n--- v60 context ---";
      s+="\nNet "+(ctx_netBias==1?"BULL":ctx_netBias==-1?"BEAR":"-")+"  Stack "+(ctx_stackDir==1?"BULL":ctx_stackDir==-1?"BEAR":"-")+" "+R0(ctx_stackPct)+"%  press "+R0(ctx_pressure);
      s+="\nCurve "+ctx_alive+"  life "+R0(ctx_life)+"  force "+ctx_cpState;
      s+="\nv60Phase "+ctx_phase+"  Narr "+ctx_narrState+" "+R0(ctx_narrative)+(ctx_converging?" (converging)":"");
      s+="\nTime "+(ctx_timeDir==1?"CLIMB":ctx_timeDir==-1?"DIVE":"LEVEL")+" "+R0(ctx_timeAlign)+"%  H1 "+ctx_h1Timing+"  attr "+PXs(ctx_attractorPx);
      s+="\nFU node "+(ctx_fuFresh?((ctx_fuDir==1?"BULL @ ":"BEAR @ ")+PXs(ctx_fuTip)):"- (none fresh)");
   }
   Comment(s);
}

//==================================================================
// OnTick
//==================================================================
void OnTick()
{
   MgCleanup();
   DailyRollover();

   // manage open trades every tick (uses last computed cur_* engine state)
   if(g_lastProcessed>=0) ManagePositions();

   datetime bt=iTime(_Symbol,_Period,0);
   bool newBar=(bt!=gLastBarTime);
   if(newBar){
      gLastBarTime=bt;
      ComputeEngine();          // full recompute -> sets cur_* for last closed bar
      if(g_lastProcessed>=0){
         TryEnter();             // evaluate entry on the just-closed bar
         ManagePositions();      // re-manage with fresh engine state
         ShowStatus();
      }
   }
}
//+------------------------------------------------------------------+
