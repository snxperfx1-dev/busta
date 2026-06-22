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
#include "Letra37_Engine.mqh"

//==================================================================
// EA INPUT ENUMS
//==================================================================
enum ENUM_SIG_SOURCE { SIG_ENGINE, SIG_V72, SIG_BOTH };   // which decision drives entries
enum ENUM_LOT_MODE   { LOT_FIXED, LOT_RISK_PCT };
enum ENUM_SL_MODE    { SL_ENGINE, SL_ATR, SL_FIXED };
enum ENUM_TP_MODE    { TP_ENGINE_TP1, TP_ENGINE_TP2, TP_RR, TP_ATR };
enum ENUM_TRAIL_MODE { TRAIL_ATR, TRAIL_POINTS };
enum ENUM_MIN_GRADE  { G_APLUS, G_A, G_B, G_C, G_D };

//==================================================================
// EA INPUTS
//==================================================================
input group "Letra37 EA - Execution"
input ENUM_SIG_SOURCE InpSignalSource   = SIG_BOTH;     // Signal source
input bool   InpTradeLongs              = true;         // Allow long trades
input bool   InpTradeShorts             = true;         // Allow short trades
input bool   InpReverseOnOpposite       = false;        // Reverse position on opposite signal
input int    InpMaxPositions            = 1;            // Max simultaneous positions (this EA)
input int    InpEngineBars              = 3000;         // Bars recomputed per new bar
input bool   InpUseLimitEntry           = false;        // Use limit at engine entry-mid (else market)
input int    InpPendingExpiryBars       = 6;            // Pending order expiry (bars; 0=GTC)

input group "Letra37 EA - Entry Filters"
input bool          InpUseGradeFilter   = true;         // Require engine grade >= min
input ENUM_MIN_GRADE InpMinGrade        = G_B;          // Min engine grade
input bool          InpUseTqeFilter     = true;         // Require V72 TQE grade >= min
input ENUM_MIN_GRADE InpMinTqeGrade     = G_B;          // Min TQE grade
input bool          InpRequireErfGate   = true;         // Require ERF entry gate open
input bool          InpRequireHtfAlign  = false;        // Require HTF alignment with trade dir
input bool          InpRequireDoeAction = true;         // Require V72 DOE action = Long/Short (SIG_V72/BOTH)
input double        InpMinConfidence    = 0.0;          // Min DOE confidence % (0=off)

input group "Letra37 EA - Risk / Sizing"
input ENUM_LOT_MODE InpLotMode          = LOT_RISK_PCT; // Position sizing mode
input double        InpFixedLot         = 0.10;         // Fixed lot (LOT_FIXED)
input double        InpRiskPercent      = 1.0;          // Risk % of equity (LOT_RISK_PCT)
input double        InpMaxLot           = 5.0;          // Hard lot cap
input int           InpMaxSpreadPoints  = 40;           // Max spread (points); 0=off

input group "Letra37 EA - Stop Loss"
input ENUM_SL_MODE  InpSLMode           = SL_ENGINE;    // Stop-loss source
input double        InpSLAtrMult        = 1.5;          // SL = ATR * mult (SL_ATR)
input int           InpSLFixedPoints    = 300;          // SL fixed points (SL_FIXED)
input double        InpSLEngineBufATR   = 0.10;         // Extra ATR buffer beyond engine stop

input group "Letra37 EA - Take Profit"
input ENUM_TP_MODE  InpTPMode           = TP_ENGINE_TP1;// Take-profit source
input double        InpTPrr             = 2.0;          // TP = RR * risk (TP_RR)
input double        InpTPAtrMult        = 3.0;          // TP = ATR * mult (TP_ATR)
input bool          InpUsePartial       = true;         // Partial close at first target
input double        InpPartialPct       = 50.0;         // Partial close % at TP1
input bool          InpMoveBEAfterTP1   = true;         // Move SL to BE after partial

input group "Letra37 EA - Trade Management"
input bool          InpUseBreakeven     = true;         // Enable break-even
input double        InpBETriggerRR      = 1.0;          // BE trigger (in RR)
input int           InpBEOffsetPoints   = 20;           // BE offset (points, locked profit)
input bool          InpUseTrailing      = true;         // Enable trailing stop
input ENUM_TRAIL_MODE InpTrailMode      = TRAIL_ATR;    // Trailing mode
input double        InpTrailAtrMult     = 2.0;          // Trail distance = ATR * mult
input int           InpTrailPoints      = 200;          // Trail distance (points)
input int           InpTrailStepPoints  = 20;           // Min step to move trail (points)
input bool          InpExitOnOpposite   = true;         // Close on opposite engine signal
input bool          InpExitOnInvalid    = true;         // Close on engine invalidation
input bool          InpExitOnPhaseFlip  = true;         // Close on Absorption/Retracement phase

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

//==================================================================
// EA GLOBALS
//==================================================================
CTrade        trade;
CPositionInfo posinfo;
CSymbolInfo   sym;
CAccountInfo  acc;

datetime gLastBarTime   = 0;
datetime gDayStamp      = 0;
double   gDayStartEquity= 0.0;
int      gTradesToday   = 0;
bool     gHalted        = false;

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
   double riskMoney=acc.Equity()*InpRiskPercent/100.0;
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
   gDayStartEquity=acc.Equity();
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
      gDayStamp=dayKey; gTradesToday=0; gHalted=false; gDayStartEquity=acc.Equity();
   }
   if(InpMaxDailyLossPct>0.0){
      double dd=(gDayStartEquity-acc.Equity())/MathMax(gDayStartEquity,1.0)*100.0;
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
}

//==================================================================
// DECISION + ENTRY
//==================================================================
int DesiredDirection()
{
   bool engLong=cur_longSignal, engShort=cur_shortSignal;
   bool v72Long =(cur_doeAction=="Long"),  v72Short=(cur_doeAction=="Short");
   bool wantLong=false, wantShort=false;
   if(InpSignalSource==SIG_ENGINE){ wantLong=engLong; wantShort=engShort; }
   else if(InpSignalSource==SIG_V72){ wantLong=v72Long; wantShort=v72Short; }
   else { wantLong=engLong||v72Long; wantShort=engShort||v72Short; }
   if(InpRequireDoeAction && InpSignalSource!=SIG_ENGINE){ wantLong=wantLong&&v72Long; wantShort=wantShort&&v72Short; }
   if(wantLong && !wantShort) return(1);
   if(wantShort && !wantLong) return(-1);
   return(0);
}

bool PassesFilters(const int dir)
{
   if(dir==1 && !InpTradeLongs) return(false);
   if(dir==-1&& !InpTradeShorts) return(false);
   if(InpUseGradeFilter && GradeRank(cur_grade)<MinGradeRank(InpMinGrade)) return(false);
   if(InpUseTqeFilter   && GradeRank(cur_tqeGrade)<MinGradeRank(InpMinTqeGrade)) return(false);
   if(InpRequireErfGate && !cur_erfEntryGate) return(false);
   if(InpRequireHtfAlign && !(cur_htfAlign==dir || cur_htfAlign==0)) return(false);
   if(InpMinConfidence>0.0 && cur_doeConfidence<InpMinConfidence) return(false);
   if(cur_invInvalidated) return(false);
   return(true);
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
   //--- enforce correct side + min stop distance ---
   double minD=MinStopDist()+_Point;
   if(dir==1  && sl>entry-minD) sl=entry-minD;
   if(dir==-1 && sl<entry+minD) sl=entry+minD;
   return(NormPrice(sl));
}

double ComputeTP(const int dir,const double entry,const double sl)
{
   double atr=cur_atr; if(atr<=0) atr=10*_Point;
   double risk=MathAbs(entry-sl);
   double tp=0.0;
   if(InpTPMode==TP_ENGINE_TP1 && !naf(cur_teTp1)) tp=cur_teTp1;
   else if(InpTPMode==TP_ENGINE_TP2 && !naf(cur_teTp2)) tp=cur_teTp2;
   else if(InpTPMode==TP_ATR) tp=entry+(dir==1? atr*InpTPAtrMult : -atr*InpTPAtrMult);
   else tp=entry+(dir==1? risk*InpTPrr : -risk*InpTPrr);
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
   if(dir==0) return;
   if(!PassesFilters(dir)) return;
   if(!SessionOK()) return;
   if(gHalted) return;
   if(InpMaxTradesPerDay>0 && gTradesToday>=InpMaxTradesPerDay) return;
   if(InpMaxSpreadPoints>0){ long sp=(long)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD); if(sp>InpMaxSpreadPoints) return; }

   int ownDir=OwnPositionDir();
   if(ownDir!=0 && ownDir!=dir){
      if(InpReverseOnOpposite){ CloseOwnPositions(0); DeletePendingOrders(); }
      else if(InpExitOnOpposite){ CloseOwnPositions(-dir); }
      else return;
   }
   if(CountOwnPositions()>=InpMaxPositions) return;

   sym.RefreshRates();
   double ask=sym.Ask(), bid=sym.Bid();
   double entry=(dir==1?ask:bid);
   double slBase=ComputeSL(dir,entry);
   double lot=CalcLot(entry,slBase);
   double tp=ComputeTP(dir,entry,slBase);
   string cmt=InpComment+" "+cur_tqeGrade+" "+cur_doeAction;

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
      ulong tk=trade.ResultOrder();
      // register live position (market entries fill immediately)
      if(posinfo.SelectByTicket(trade.ResultDeal())) {}
      // best-effort: register by scanning newest own position
      for(int q=PositionsTotal()-1;q>=0;q--){
         ulong pt=PositionGetTicket(q);
         if(pt==0) continue;
         if(PositionGetInteger(POSITION_MAGIC)==(long)InpMagic && PositionGetString(POSITION_SYMBOL)==_Symbol){
            double psl=PositionGetDouble(POSITION_SL);
            MgRegister(pt,psl,(InpTPMode==TP_ENGINE_TP2&&!naf(cur_teTp2))?cur_teTp2:cur_teTp1,dir);
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

      //--- engine-driven exits ---
      if(InpExitOnInvalid && cur_invInvalidated){ trade.PositionClose(tk); continue; }
      if(InpExitOnPhaseFlip && (cur_ie1aPhase=="Absorption"||cur_ie1aPhase=="Retracement")){ trade.PositionClose(tk); continue; }
      if(InpExitOnOpposite && ((dir==1&&cur_shortSignal)||(dir==-1&&cur_longSignal))){ trade.PositionClose(tk); continue; }
      if(InpCloseAtSessEnd && !SessionOK()){ trade.PositionClose(tk); continue; }

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

      //--- break-even ---
      if(InpUseBreakeven && rMult>=InpBETriggerRR && (mi<0||!gMgBEDone[mi])){
         double be=openP+(dir==1?InpBEOffsetPoints*_Point:-InpBEOffsetPoints*_Point); be=NormPrice(be);
         bool improve=(dir==1?(be>curSL):(curSL==0||be<curSL));
         if(improve && trade.PositionModify(tk,be,curTP)){ if(mi>=0) gMgBEDone[mi]=true; curSL=be; }
      }

      //--- trailing ---
      if(InpUseTrailing){
         double dist=(InpTrailMode==TRAIL_ATR?atr*InpTrailAtrMult:InpTrailPoints*_Point);
         double minD=MinStopDist()+_Point; if(dist<minD) dist=minD;
         double newSL=(dir==1? mkt-dist : mkt+dist); newSL=NormPrice(newSL);
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
   s+="Stop   : "+PXs(cur_invActiveStop)+(cur_invInvalidated?" [INVALID]":"")+"   TP1 "+PXs(cur_teTp1)+"  TP2 "+PXs(cur_teTp2)+"\n";
   s+="Target : "+cur_tplWinnerClass+" "+PXs(cur_tplMainTarget)+" ("+cur_tplSource+")\n";
   s+="Pos    : "+IntegerToString(CountOwnPositions())+"   TradesToday "+IntegerToString(gTradesToday)+(gHalted?"  [HALTED]":"")+"\n";
   s+="Narr   : "+cur_cmdNarrative;
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
