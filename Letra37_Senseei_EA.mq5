//+------------------------------------------------------------------+
//|                                            Letra37_Senseei_EA.mq5 |
//|   Tradeable EA driven by the best-of-v60 "Master Senseei" layer:  |
//|   v60 14-phase structure engine + fractal stack + Invisible       |
//|   Network + Time-Intelligence + Senseei meta-intelligence, with   |
//|   the F72 curve-life score driving hold-vs-flip trade management.  |
//|                                                                  |
//|   Entry  : Senseei ACTION == ATTACK (master direction), gated by  |
//|            confidence / threat / opportunity / network agreement. |
//|   Stop   : v60 canonical wave invalidation (se*_inv) / ATR.       |
//|   Target : network attractor / wave objective / RR.               |
//|   Manage : curve-life — DEAD (life<=flip) closes (and optionally   |
//|            reverses); ALIVE holds; + break-even & ATR trailing.    |
//+------------------------------------------------------------------+
#property copyright "Letra 37 / Master Senseei EA"
#property version   "1.00"
#property description "Order-placing EA driven by the v60 Senseei decision engine + F72 curve-life management."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/AccountInfo.mqh>
#include "Letra37_Senseei.mqh"

//==================================================================
// EA INPUT ENUMS
//==================================================================
enum ENUM_SEN_SL { SLM_INV, SLM_ATR, SLM_FIXED };       // stop-loss source
enum ENUM_SEN_TP { TPM_ATTRACTOR, TPM_WAVEOBJ, TPM_RR, TPM_ATR };
enum ENUM_SEN_TRAIL { TRL_ATR, TRL_POINTS };

//==================================================================
// EA INPUTS
//==================================================================
input group "Senseei EA - Execution"
input bool   InpAttackOnly        = true;    // Only enter on Senseei ACTION = ATTACK (else also PREPARE)
input bool   InpTradeLongs        = true;    // Allow long trades
input bool   InpTradeShorts       = true;    // Allow short trades
input bool   InpRequireNetAgree   = true;    // Require network bias to agree with master
input bool   InpRequireStackAgree = false;   // Require fractal stack to agree with master
input double InpMinConfidence     = 55.0;    // Min Senseei confidence
input double InpMaxThreat         = 45.0;    // Max Senseei threat
input double InpMaxConflict       = 55.0;    // Max Senseei conflict
input int    InpMaxPositions      = 1;       // Max simultaneous positions
input int    InpEngineBars        = 2500;    // Bars recomputed per new bar

input group "Senseei EA - Risk / Sizing"
input bool   InpUseRiskPct        = true;    // Size by % equity risk (else fixed lot)
input double InpRiskPercent       = 1.0;     // Risk % of equity
input double InpFixedLot          = 0.10;    // Fixed lot
input double InpMaxLot            = 5.0;     // Hard lot cap
input int    InpMaxSpreadPoints   = 40;      // Max spread (points); 0=off

input group "Senseei EA - Stop / Target"
input ENUM_SEN_SL InpSLMode       = SLM_INV; // Stop-loss source
input double InpSLAtrMult         = 1.5;     // SL = ATR * mult (SLM_ATR)
input int    InpSLFixedPoints     = 300;     // SL fixed points (SLM_FIXED)
input double InpSLBufferATR       = 0.15;    // Extra ATR buffer beyond invalidation
input ENUM_SEN_TP InpTPMode       = TPM_ATTRACTOR;
input double InpTPrr              = 2.0;     // TP = RR * risk (TPM_RR)
input double InpTPAtrMult         = 3.0;     // TP = ATR * mult (TPM_ATR)

input group "Senseei EA - Curve-Life Management"
input bool   InpUseCurveLife      = true;    // Manage exits with the F72 curve-life score
input double InpLifeDeadBelow     = 32.0;    // life <= this => DEAD (close)
input bool   InpFlipOnDead        = false;   // Reverse to counter side when curve dies
input bool   InpExitOnActionFlip  = true;    // Close when Senseei action turns MANAGE/EXIT
input bool   InpExitOnMasterFlip  = true;    // Close when master direction flips against position

input group "Senseei EA - Break-even / Trailing"
input bool   InpUseBreakeven      = true;    // Enable break-even
input double InpBETriggerRR       = 1.0;     // BE trigger (RR)
input int    InpBEOffsetPoints    = 20;      // BE locked profit (points)
input bool   InpUseTrailing       = true;    // Enable trailing stop
input ENUM_SEN_TRAIL InpTrailMode = TRL_ATR; // Trailing mode
input double InpTrailAtrMult      = 2.0;     // Trail distance = ATR * mult
input int    InpTrailPoints       = 200;     // Trail distance (points)
input int    InpTrailStepPoints   = 20;      // Min step to move trail (points)

input group "Senseei EA - Session / Guards"
input bool   InpUseSession        = false;   // Restrict trading hours (server time)
input int    InpSessStartHour     = 7;       // Session start hour
input int    InpSessEndHour       = 20;      // Session end hour
input bool   InpSkipFriday        = false;   // No new trades on Friday
input double InpMaxDailyLossPct   = 5.0;     // Halt after daily loss % (0=off)
input int    InpMaxTradesPerDay   = 20;      // Max new trades per day (0=off)

input group "Senseei EA - Misc"
input ulong  InpMagic             = 370060;  // Magic number
input ulong  InpDeviation         = 20;      // Max slippage (points)
input string InpComment           = "Senseei";
input bool   InpShowStatus        = true;    // Show status panel (Comment)

//==================================================================
// EA GLOBALS
//==================================================================
CTrade        trade;
CPositionInfo posinfo;
CSymbolInfo   sym;
CAccountInfo  acc;

datetime gLastBarTime    = 0;
datetime gDayStamp       = 0;
double   gDayStartEquity = 0.0;
int      gTradesToday    = 0;
bool     gHalted         = false;

ulong  gMgTicket[]; double gMgInitSL[]; bool gMgBEDone[]; int gMgDir[];

//==================================================================
// HELPERS
//==================================================================
double NormPrice(const double p){ return(NormalizeDouble(p,_Digits)); }
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
   double step =SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP); if(step<=0) step=0.01;
   lot=MathFloor(lot/step)*step;
   if(lot<minlot) lot=minlot;
   if(lot>maxlot) lot=maxlot;
   if(lot>InpMaxLot) lot=InpMaxLot;
   return(lot);
}
double MoneyPerPointPerLot()
{
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE); if(ts<=0) ts=_Point;
   return(tv*(_Point/ts));
}
double CalcLot(const double entry,const double sl)
{
   if(!InpUseRiskPct) return(NormalizeLot(InpFixedLot));
   double riskMoney=acc.Equity()*InpRiskPercent/100.0;
   double slPts=MathAbs(entry-sl)/_Point;
   double mpp=MoneyPerPointPerLot();
   if(slPts<1 || mpp<=0) return(NormalizeLot(InpFixedLot));
   return(NormalizeLot(riskMoney/(slPts*mpp)));
}
int MgIndex(const ulong tk){ for(int q=0;q<ArraySize(gMgTicket);q++) if(gMgTicket[q]==tk) return(q); return(-1); }
void MgRegister(const ulong tk,const double initSL,const int dir)
{
   if(MgIndex(tk)>=0) return;
   int s=ArraySize(gMgTicket);
   ArrayResize(gMgTicket,s+1);ArrayResize(gMgInitSL,s+1);ArrayResize(gMgBEDone,s+1);ArrayResize(gMgDir,s+1);
   gMgTicket[s]=tk; gMgInitSL[s]=initSL; gMgBEDone[s]=false; gMgDir[s]=dir;
}
void MgCleanup()
{
   for(int q=ArraySize(gMgTicket)-1;q>=0;q--)
      if(!posinfo.SelectByTicket(gMgTicket[q])){ ArrayRemove(gMgTicket,q,1);ArrayRemove(gMgInitSL,q,1);ArrayRemove(gMgBEDone,q,1);ArrayRemove(gMgDir,q,1); }
}
int CountOwn()
{
   int n=0;
   for(int q=PositionsTotal()-1;q>=0;q--){ ulong tk=PositionGetTicket(q); if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)==(long)InpMagic && PositionGetString(POSITION_SYMBOL)==_Symbol) n++; }
   return(n);
}
int OwnDir()
{
   for(int q=PositionsTotal()-1;q>=0;q--){ ulong tk=PositionGetTicket(q); if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)==(long)InpMagic && PositionGetString(POSITION_SYMBOL)==_Symbol)
         return(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1); }
   return(0);
}
void CloseOwn(const int dirFilter=0)
{
   for(int q=PositionsTotal()-1;q>=0;q--){ ulong tk=PositionGetTicket(q); if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)InpMagic || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      int d=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      if(dirFilter!=0 && d!=dirFilter) continue;
      trade.PositionClose(tk); }
}

//==================================================================
// OnInit / OnDeinit
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
   gDayStamp=0; gTradesToday=0; gHalted=false; gDayStartEquity=acc.Equity(); gLastBarTime=0;
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason){ Comment(""); }

//==================================================================
// GUARDS
//==================================================================
void DailyRollover()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   datetime dayKey=(datetime)(dt.year*10000+dt.mon*100+dt.day);
   if(dayKey!=gDayStamp){ gDayStamp=dayKey; gTradesToday=0; gHalted=false; gDayStartEquity=acc.Equity(); }
   if(InpMaxDailyLossPct>0.0){
      double dd=(gDayStartEquity-acc.Equity())/MathMax(gDayStartEquity,1.0)*100.0;
      if(dd>=InpMaxDailyLossPct) gHalted=true;
   }
}
bool SessionOK()
{
   if(!InpUseSession) return(true);
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(InpSkipFriday && dt.day_of_week==5) return(false);
   if(InpSessStartHour<=InpSessEndHour) return(dt.hour>=InpSessStartHour && dt.hour<InpSessEndHour);
   return(dt.hour>=InpSessStartHour || dt.hour<InpSessEndHour);
}

//==================================================================
// STOP / TARGET from Senseei outputs
//==================================================================
double ComputeSL(const int dir,const double entry)
{
   double a=SenAtr(); if(a<=0) a=10*_Point;
   double sl;
   if(InpSLMode==SLM_INV && !naf(sen_stop)) sl=sen_stop+(dir==1?-a*InpSLBufferATR:a*InpSLBufferATR);
   else if(InpSLMode==SLM_FIXED) sl=entry+(dir==1?-InpSLFixedPoints*_Point:InpSLFixedPoints*_Point);
   else sl=entry+(dir==1?-a*InpSLAtrMult:a*InpSLAtrMult);
   double minD=MinStopDist()+_Point;
   if(dir==1  && sl>entry-minD) sl=entry-minD;
   if(dir==-1 && sl<entry+minD) sl=entry+minD;
   return(NormPrice(sl));
}
double ComputeTP(const int dir,const double entry,const double sl)
{
   double a=SenAtr(); if(a<=0) a=10*_Point;
   double risk=MathAbs(entry-sl);
   double tp=0;
   if(InpTPMode==TPM_ATTRACTOR && !naf(sen_attractorPx)) tp=sen_attractorPx;
   else if(InpTPMode==TPM_WAVEOBJ && !naf(sen_t1)) tp=sen_t1;
   else if(InpTPMode==TPM_ATR) tp=entry+(dir==1?a*InpTPAtrMult:-a*InpTPAtrMult);
   else tp=entry+(dir==1?risk*InpTPrr:-risk*InpTPrr);
   if((dir==1&&tp<=entry)||(dir==-1&&tp>=entry)) tp=entry+(dir==1?risk*InpTPrr:-risk*InpTPrr);
   double minD=MinStopDist()+_Point;
   if(dir==1  && tp<entry+minD) tp=entry+minD;
   if(dir==-1 && tp>entry-minD) tp=entry-minD;
   return(NormPrice(tp));
}

//--- ATR for the chart TF (published by the Senseei engine) ---
double SenAtr(){ return(sen_atr>0?sen_atr:0.0); }

//==================================================================
// ENTRY
//==================================================================
bool PassesFilters(const int dir)
{
   if(dir==1 && !InpTradeLongs) return(false);
   if(dir==-1&& !InpTradeShorts) return(false);
   if(sen_action=="WAIT") return(false);
   if(InpAttackOnly && sen_action!="ATTACK") return(false);
   if(!InpAttackOnly && sen_action!="ATTACK" && sen_action!="PREPARE") return(false);
   if(sen_confidence<InpMinConfidence) return(false);
   if(sen_threat>InpMaxThreat) return(false);
   if(sen_conflict>InpMaxConflict) return(false);
   if(InpRequireNetAgree && !(sen_netBias==dir || sen_netBias==0)) return(false);
   if(InpRequireStackAgree && sen_stackDir!=dir) return(false);
   if(sen_resCode==2) return(false);   // already resolved -> manage, don't enter
   return(true);
}
void TryEnter()
{
   if(sen_master==0) return;
   int dir=sen_master;
   if(!PassesFilters(dir)) return;
   if(!SessionOK() || gHalted) return;
   if(InpMaxTradesPerDay>0 && gTradesToday>=InpMaxTradesPerDay) return;
   if(InpMaxSpreadPoints>0){ long sp=(long)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD); if(sp>InpMaxSpreadPoints) return; }

   int ownDir=OwnDir();
   if(ownDir!=0 && ownDir!=dir){
      if(InpExitOnMasterFlip) CloseOwn(-dir); else return;
   }
   if(CountOwn()>=InpMaxPositions) return;

   sym.RefreshRates();
   double ask=sym.Ask(), bid=sym.Bid();
   double entry=(dir==1?ask:bid);
   double sl=ComputeSL(dir,entry);
   double lot=CalcLot(entry,sl);
   double tp=ComputeTP(dir,entry,sl);
   string cmt=InpComment+" "+sen_action+" "+sen_opportunity;
   bool ok=(dir==1)?trade.Buy(lot,_Symbol,ask,sl,tp,cmt):trade.Sell(lot,_Symbol,bid,sl,tp,cmt);
   if(ok){
      gTradesToday++;
      for(int q=PositionsTotal()-1;q>=0;q--){ ulong pt=PositionGetTicket(q); if(pt==0) continue;
         if(PositionGetInteger(POSITION_MAGIC)==(long)InpMagic && PositionGetString(POSITION_SYMBOL)==_Symbol){
            MgRegister(pt,PositionGetDouble(POSITION_SL),dir); break; } }
   }
}

//==================================================================
// MANAGEMENT (curve-life + BE + trailing)
//==================================================================
void ManagePositions()
{
   double a=SenAtr(); if(a<=0) a=10*_Point;
   for(int q=PositionsTotal()-1;q>=0;q--){
      ulong tk=PositionGetTicket(q); if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)InpMagic || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      int    dir   =PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      double openP =PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL =PositionGetDouble(POSITION_SL);
      double curTP =PositionGetDouble(POSITION_TP);
      sym.RefreshRates();
      double mkt   =(dir==1?sym.Bid():sym.Ask());
      int    mi    =MgIndex(tk);
      double initSL=(mi>=0?gMgInitSL[mi]:curSL);
      double risk  =MathAbs(openP-initSL); if(risk<=0) risk=a;
      double rMult =(dir==1?(mkt-openP):(openP-mkt))/risk;

      //--- curve-life: DEAD => close (and optionally flip) ---
      if(InpUseCurveLife && sen_life<=InpLifeDeadBelow && dir==sen_waveDir){
         trade.PositionClose(tk);
         if(InpFlipOnDead && sen_master==-dir){ /* reversal handled by next TryEnter */ }
         continue;
      }
      //--- Senseei action turned to MANAGE/EXIT ---
      if(InpExitOnActionFlip && (sen_action=="MANAGE / EXIT")){ trade.PositionClose(tk); continue; }
      //--- master flipped against the position ---
      if(InpExitOnMasterFlip && sen_master!=0 && sen_master!=dir){ trade.PositionClose(tk); continue; }

      //--- break-even ---
      if(InpUseBreakeven && rMult>=InpBETriggerRR && (mi<0||!gMgBEDone[mi])){
         double be=openP+(dir==1?InpBEOffsetPoints*_Point:-InpBEOffsetPoints*_Point); be=NormPrice(be);
         bool improve=(dir==1?(be>curSL):(curSL==0||be<curSL));
         if(improve && trade.PositionModify(tk,be,curTP)){ if(mi>=0) gMgBEDone[mi]=true; curSL=be; }
      }
      //--- trailing ---
      if(InpUseTrailing){
         double dist=(InpTrailMode==TRL_ATR?a*InpTrailAtrMult:InpTrailPoints*_Point);
         double minD=MinStopDist()+_Point; if(dist<minD) dist=minD;
         double newSL=(dir==1?mkt-dist:mkt+dist); newSL=NormPrice(newSL);
         double step=InpTrailStepPoints*_Point;
         bool improve=(dir==1?(newSL>curSL+step):(curSL==0||newSL<curSL-step));
         if(dir==1 && newSL<openP && !(mi>=0&&gMgBEDone[mi])) improve=false;
         if(dir==-1&& newSL>openP && !(mi>=0&&gMgBEDone[mi])) improve=false;
         if(improve) trade.PositionModify(tk,newSL,curTP);
      }
   }
}

//==================================================================
// STATUS
//==================================================================
void ShowStatus()
{
   if(!InpShowStatus) return;
   string s="MASTER SENSEEI EA  ["+_Symbol+","+EnumToString(_Period)+"]\n";
   s+="Phase  : "+sen_phase+"  ("+f_waveDirLabel(sen_waveDir)+")  wp "+R0(sen_wp)+"%\n";
   s+="ACTION : "+sen_action+"   master "+(sen_master==1?"LONG":sen_master==-1?"SHORT":"-")+"\n";
   s+="Conf   : "+R0(sen_confidence)+"%   Threat "+R0(sen_threat)+"%   Conflict "+R0(sen_conflict)+"%\n";
   s+="Opp    : "+sen_opportunity+"   intent "+sen_intent+"   timing "+sen_timing+"\n";
   s+="Stack  : "+(sen_stackDir==1?"BULL":sen_stackDir==-1?"BEAR":"-")+" "+R0(sen_stackPct)+"%   Net "+(sen_netBias==1?"BULL":sen_netBias==-1?"BEAR":"-")+"  press "+R0(sen_pressure)+"\n";
   s+="Time   : "+(sen_timeDir==1?"CLIMB":sen_timeDir==-1?"DIVE":"LEVEL")+"  align "+R0(sen_timeAlign)+"%  H1 "+sen_h1Timing+"\n";
   s+="Curve  : "+sen_alive+"  life "+R0(sen_life)+"  force "+sen_cpState+"\n";
   s+="Levels : entry "+PXs(sen_entry)+"  stop "+PXs(sen_stop)+"  attr "+PXs(sen_attractorPx)+"  T1 "+PXs(sen_t1)+"\n";
   s+="Pos    : "+IntegerToString(CountOwn())+"   TradesToday "+IntegerToString(gTradesToday)+(gHalted?"  [HALTED]":"");
   Comment(s);
}

//==================================================================
// OnTick
//==================================================================
void OnTick()
{
   MgCleanup();
   DailyRollover();
   if(g_lastProcessed>=-1 && sen_master!=0) ManagePositions();   // manage with last engine state each tick

   datetime bt=iTime(_Symbol,_Period,0);
   if(bt!=gLastBarTime){
      gLastBarTime=bt;
      SenseeiRun(InpEngineBars);          // full recompute -> sets sen_* for last closed bar
      g_lastProcessed=0;                  // mark engine has produced output
      ManagePositions();
      TryEnter();
      ShowStatus();
   }
}
//+------------------------------------------------------------------+
