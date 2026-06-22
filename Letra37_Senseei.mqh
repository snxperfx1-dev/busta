#ifndef __LETRA37_SENSEEI_MQH__
#define __LETRA37_SENSEEI_MQH__
//+------------------------------------------------------------------+
//| Letra37_Senseei.mqh                                              |
//| Best-of-v60 ("F16 Raptor / Master Senseei") decision layer,      |
//| ported on top of the shared Letra37 engine helpers.              |
//|                                                                  |
//| Ports the genuinely decision-improving parts of v60:             |
//|   - Adaptive timeframe ladder (climbs above H1, no collapse)     |
//|   - v60 14-phase structure engine (DIR-FIX + compression /       |
//|     recursive-transition / dominance-transfer)                   |
//|   - Fractal stack alignment                                      |
//|   - Invisible Network node engine (FU pools -> authority /       |
//|     netBias / pressure / primary attractor / FEZ / forward path) |
//|   - Time Intelligence Engine (MN/W/D/H4/H1 cycle stack)          |
//|   - Compact Energy/Resolution/Attractor read                     |
//|   - Senseei meta-intelligence (align/conflict/threat/confidence/ |
//|     intent/timing/opportunity/ACTION)                            |
//|   - F72 curve-life score ("is the trade alive?") for management  |
//+------------------------------------------------------------------+
#include "Letra37_Engine.mqh"

//==================================================================
// SENSEEI INPUTS (distinct names; engine inputs are reused)
//==================================================================
input group "Senseei (v60) - Network"
input double sIn_wickFrac    = 0.30;   // FU spike: min wick / range
input int    sIn_lookback    = 3;      // FU spike: structure lookback
input int    sIn_authMin     = 45;     // Min node authority
input int    sIn_nodeMax     = 250;    // Max remembered nodes
input int    sIn_dormantBars = 120;    // Bars until dormant
input int    sIn_historyBars = 600;    // Bars until historical
input group "Senseei (v60) - Decision"
input int    sIn_minConf     = 55;     // Min confidence to ATTACK
input int    sIn_maxThreat   = 45;     // Max threat to ATTACK

//==================================================================
// ADAPTIVE TIMEFRAME LADDER  (rung 3 = chart timeframe)
//==================================================================
ENUM_TIMEFRAMES SenLadder(const int rung)
{
   int s=PeriodSeconds(_Period);
   if(s<=3600){
      switch(rung){ case 1: return(PERIOD_M1); case 2: return(PERIOD_M3); case 3: return(_Period);
                    case 4: return(PERIOD_M15); case 5: return(PERIOD_H1); case 6: return(PERIOD_H4); }
   } else {
      switch(rung){ case 1: return(PERIOD_H1); case 2: return(PERIOD_H4); case 3: return(_Period);
                    case 4: return(PERIOD_D1); case 5: return(PERIOD_W1); case 6: return(PERIOD_MN1); }
   }
   return(_Period);
}
string SenTfLabel(const ENUM_TIMEFRAMES tf)
{
   switch(tf){ case PERIOD_M1: return("M1"); case PERIOD_M3: return("M3"); case PERIOD_M5: return("M5");
               case PERIOD_M15: return("M15"); case PERIOD_M30: return("M30"); case PERIOD_H1: return("H1");
               case PERIOD_H2: return("H2"); case PERIOD_H4: return("H4"); case PERIOD_H8: return("H8");
               case PERIOD_H12: return("H12"); case PERIOD_D1: return("D"); case PERIOD_W1: return("W");
               case PERIOD_MN1: return("MN"); }
   return(EnumToString(tf));
}

//==================================================================
// V60 STRUCTURE ENGINE — 14-phase, DIR-FIX, compression/recursion
//==================================================================
struct SEV60
{
   datetime t[]; int n;
   double dir[], ph[], sh[], sl[], psh[], psl[], bos[], ch[];
   double p4h[], p4l[], inv[], tgt[], ft[], fb[], fs[], wp[], cm[], mf[];
   double comp[], rec[], dom[];
};

string f_phaseStrV60(const int c)
{
   switch(c){
      case 1:  return("Expansion");
      case 2:  return("Expansion Pre-Convexity");
      case 3:  return("Expansion Induction");
      case 4:  return("Expansion Liquidity");
      case 5:  return("New High");
      case 6:  return("New Low");
      case 7:  return("Transition");
      case 8:  return("Retracement");
      case 9:  return("HTF Flip Zone");
      case 10: return("Induction");
      case 11: return("Liquidation");
      case 12: return("Terminal Curve");
      case 13: return("Demand Return");
      case 14: return("Supply Return");
   }
   return("Point 4 Origin");
}

void ComputeSE_V60(const ENUM_TIMEFRAMES tfReq, const int bars,
                   const int pvLen, const int stLen, const int atrL,
                   const double effT, const double dispT, const double convM,
                   const double impM, const double chBuf, const int effL,
                   SEV60 &O)
{
   ENUM_TIMEFRAMES tf=SafeTF(tfReq);
   TFData d; if(!LoadTF(tf,bars,d) || d.n<2*pvLen+5){ O.n=0; return; }
   int n=d.n;
   double diff[]; ArrayResize(diff,n); diff[0]=0; for(int j=1;j<n;j++) diff[j]=d.c[j]-d.c[j-1];
   double vel[]; EMAarr(diff,vel,3);
   double acc[]; ArrayResize(acc,n); acc[0]=0; for(int j=1;j<n;j++) acc[j]=vel[j]-vel[j-1];
   double cvx[]; ArrayResize(cvx,n); cvx[0]=0; for(int j=1;j<n;j++) cvx[j]=acc[j]-acc[j-1];
   double csm[]; EMAarr(cvx,csm,3);
   double atr[]; ATRarr(d.h,d.l,d.c,atr,atrL);
   double phA[]; PivotHigh(d.h,phA,pvLen);
   double plA[]; PivotLow(d.l,plA,pvLen);

   O.n=n; ArrayResize(O.t,n);
   ArrayResize(O.dir,n);ArrayResize(O.ph,n);ArrayResize(O.sh,n);ArrayResize(O.sl,n);ArrayResize(O.psh,n);ArrayResize(O.psl,n);
   ArrayResize(O.bos,n);ArrayResize(O.ch,n);ArrayResize(O.p4h,n);ArrayResize(O.p4l,n);ArrayResize(O.inv,n);ArrayResize(O.tgt,n);
   ArrayResize(O.ft,n);ArrayResize(O.fb,n);ArrayResize(O.fs,n);ArrayResize(O.wp,n);ArrayResize(O.cm,n);ArrayResize(O.mf,n);
   ArrayResize(O.comp,n);ArrayResize(O.rec,n);ArrayResize(O.dom,n);

   double curSH=NA,curSL=NA,prSH=NA,prSL=NA;
   double lastP=NA,prevP=NA; int lastD=0,prevD=0;
   int    dir=0; double ftv=NA,fbv=NA,p4h=NA,p4l=NA,inv=NA,tgt=NA,cycH=NA,cycL=NA;
   bool   bos1=false,bos2=false; double protSw=NA,protSw2=NA,indOrig=NA,indExt=NA; bool indBrk=false;
   int    lastDirSeen=0; int recBrk=0; bool recArm=true; int pst=0;

   for(int j=0;j<n;j++){
      O.t[j]=d.t[j];
      double cl=d.c[j],op=d.o[j],hi=d.h[j],lo=d.l[j],A=atr[j];
      double velP=(j>0)?vel[j-1]:0, accP=(j>0)?acc[j-1]:0;
      double mv=(j>=effL)?MathAbs(cl-d.c[j-effL]):0.0;
      double ps=SumAbsDiff(d.c,j,effL);
      double eff=(ps>0)?mv/ps:0.0;
      double disp=(hi-lo)/fmax2(A,1e-10);
      bool bullImp=eff>effT && vel[j]>velP && acc[j]>0 && cl>op && disp>dispT;
      bool bearImp=eff>effT && vel[j]<velP && acc[j]<0 && cl<op && disp>dispT;
      bool bullDec=MathAbs(acc[j])<MathAbs(accP)*0.8 && vel[j]>0;
      bool bearDec=MathAbs(acc[j])<MathAbs(accP)*0.8 && vel[j]<0;
      double pH=phA[j], pL=plA[j];
      if(!naf(pH)){ prSH=naf(curSH)?pH:curSH; curSH=pH; }
      if(!naf(pL)){ prSL=naf(curSL)?pL:curSL; curSL=pL; }
      double eP=NA; int eD=0;
      if(!naf(pH)){ eP=pH; eD=1; } else if(!naf(pL)){ eP=pL; eD=-1; }
      if(eD!=0){ prevP=lastP; prevD=lastD; lastP=eP; lastD=eD; }
      bool bullBOS=!naf(prSH)&&cl>prSH;
      bool bearBOS=!naf(prSL)&&cl<prSL;
      bool bullCH =!naf(prSH)&&cl>prSH+A*chBuf;
      bool bearCH =!naf(prSL)&&cl<prSL-A*chBuf;
      bool eLong =!naf(pH)&&prevD==-1&&(pH-prevP)>A*impM;
      bool eShort=!naf(pL)&&prevD==1 &&(prevP-pL)>A*impM;
      bool hasCtx=dir!=0&&!naf(ftv);
      bool flipDn=dir==1 && bearCH;
      bool flipUp=dir==-1&& bullCH;
      bool isRev=(eLong&&dir==-1)||(eShort&&dir==1)||flipUp||flipDn;
      bool spawn=(eLong||eShort||flipUp||flipDn)&&(!hasCtx||isRev);
      if(spawn){
         int nd=eLong?1:eShort?-1:flipUp?1:-1;
         double _hi=fmax2(lastP,prevP), _lo=fmin2(lastP,prevP);   // DIR-FIX
         ftv=_hi; fbv=_lo; p4h=_hi; p4l=_lo; cycH=hi; cycL=lo; dir=nd;
         inv = nd==1?_lo:_hi;                                     // protective extreme
         double rng=(!naf(prSH)&&!naf(prSL))?MathAbs(prSH-prSL):A*5.0;
         tgt = nd==1?nz(ftv,cl)+rng:nz(fbv,cl)-rng;
      }
      if(dir==1)  cycH=naf(cycH)?hi:fmax2(cycH,hi);
      if(dir==-1) cycL=naf(cycL)?lo:fmin2(cycL,lo);
      int bosOut=bullBOS?1:bearBOS?-1:0;
      int chOut =bullCH?1:bearCH?-1:0;
      bool reset=(dir!=lastDirSeen); lastDirSeen=dir;
      if(reset){ bos1=false; bos2=false; protSw=NA; protSw2=NA; indOrig=NA; indExt=NA; indBrk=false; }
      if(dir==1 && !naf(pL)){ protSw2=protSw; protSw=pL; }
      if(dir==-1 && !naf(pH)){ protSw2=protSw; protSw=pH; }
      bool oppBOS=(dir==1&&!naf(protSw)&&cl<protSw)||(dir==-1&&!naf(protSw)&&cl>protSw);
      if(!bos1 && oppBOS){ bos1=true; indOrig=dir==1?nz(cycH,hi):nz(cycL,lo); }
      if(bos1 && !bos2 && oppBOS && !naf(protSw2) && (dir==1?cl<protSw2:cl>protSw2)) bos2=true;
      if(bos1 && dir==1)  indExt=naf(indExt)?cl:fmin2(indExt,cl);
      if(bos1 && dir==-1) indExt=naf(indExt)?cl:fmax2(indExt,cl);
      if(bos2 && !naf(indOrig)){ if(dir==1&&cl>indOrig) indBrk=true; if(dir==-1&&cl<indOrig) indBrk=true; }
      double convScore=fmin2(MathAbs(csm[j])/fmax2(A*convM,1e-10)*50.0,100.0);
      double expScore =fmin2(eff/fmax2(effT,1e-10)*50.0+disp/fmax2(dispT,1e-10)*50.0,100.0);
      double absScore =(eff<effT*0.7 && MathAbs(vel[j])<MathAbs(velP)*0.6)?60.0+convScore*0.4:convScore*0.3;
      bool momExpStrong=eff>effT*0.75 && (dir==1?vel[j]>0:vel[j]<0);
      bool momDecaying =dir==1?bullDec:bearDec;
      bool momCounter  =dir==1?bearImp:bullImp;
      bool momExhaust  =eff<effT*0.65 && absScore>40.0;
      bool physConvexDevel=convScore>35.0;
      bool physTransfer   =convScore>48.0 || absScore>40.0;
      bool physCapacityLow=absScore>45.0 || eff<effT*0.6;
      int wdir = !naf(inv)?(cl>inv?1:(cl<inv?-1:dir)):dir;
      bool atFlip=!naf(ftv)&&!naf(fbv)&&cl<=ftv&&cl>=fbv;
      bool expanding=momExpStrong||eLong||eShort||(wdir==1?bullImp:bearImp);
      bool atExtreme=wdir==1?hi>=nz(cycH,hi):(wdir==-1?lo<=nz(cycL,lo):false);
      double extr=wdir==1?nz(cycH,cl):nz(cycL,cl);
      bool extended=!naf(inv)&&MathAbs(extr-inv)>A*1.5;
      double fzMid=(!naf(ftv)&&!naf(fbv))?(ftv+fbv)/2.0:NA;
      double retrFrac=(!naf(fzMid)&&MathAbs(extr-fzMid)>1e-10)?MathAbs(extr-cl)/MathAbs(extr-fzMid):0.0;
      double compIdx=fmin2(100.0,fmax2(0.0,(1.0-fmin2(disp/fmax2(dispT,1e-10),1.0))*60.0+(1.0-fmin2(eff/fmax2(effT,1e-10),1.0))*40.0));
      bool phase2CH=(dir==1&&bearCH)||(dir==-1&&bullCH);
      if(reset||(atExtreme&&extended)){ recBrk=0; recArm=true; }
      if((dir==1&&!naf(pH))||(dir==-1&&!naf(pL))) recArm=true;
      if((phase2CH||oppBOS)&&recArm&&!atExtreme){ recBrk++; recArm=false; }
      double recDom=fmin2(100.0,fmax2(recBrk*(30.0-compIdx*0.15),retrFrac*80.0));
      bool transferDone=recDom>=50.0;
      if(reset) pst=0;
      if(dir!=0 && !reset){
         if(pst==0 && expanding) pst=1;
         if(pst==1 && !atExtreme && momDecaying && physConvexDevel) pst=2;
         if(pst==2 && !atExtreme && momCounter && physTransfer) pst=3;
         if(pst==3 && !atExtreme && (bos1||bos2||indBrk) && physTransfer) pst=4;
         if(pst>=1 && pst<=7 && atExtreme && extended) pst=5;
         if(pst==5 && !atExtreme && (recBrk>=1||momExhaust)) pst=7;
         if(pst==7 && transferDone) pst=8;
         if(pst==8 && atFlip) pst=9;
         if(pst==9 && ((dir==1&&bullImp)||(dir==-1&&bearImp))) pst=10;
         if(pst==10 && (oppBOS||physCapacityLow)) pst=11;
         if(pst==11 && ((dir==1&&lo<fbv)||(dir==-1&&hi>ftv))) pst=12;
         if(pst==12 && ((dir==1&&bullCH)||(dir==-1&&bearCH))) pst=13;
      }
      int phase=pst;
      if(phase==5 && dir==-1) phase=6;
      if(phase==13 && dir==-1) phase=14;
      double wp=pst==0?5.0:pst==1?15.0:pst==2?25.0:pst==3?33.0:pst==4?42.0:pst==5?55.0:pst==7?65.0:pst==8?75.0:pst==9?85.0:pst==10?90.0:pst==11?94.0:pst==12?97.0:100.0;
      double cm=fmin2(convScore,100.0);
      double mf=fmin2(fmax2(expScore,fmax2(absScore,convScore))*0.70+(dir!=0?30.0:0.0),100.0);
      double frzS=fmin2((eLong||eShort?50.0:0.0)+expScore*0.30+convScore*0.20,100.0);
      O.dir[j]=wdir; O.ph[j]=phase; O.sh[j]=curSH; O.sl[j]=curSL; O.psh[j]=prSH; O.psl[j]=prSL;
      O.bos[j]=bosOut; O.ch[j]=chOut; O.p4h[j]=p4h; O.p4l[j]=p4l; O.inv[j]=inv; O.tgt[j]=tgt;
      O.ft[j]=ftv; O.fb[j]=fbv; O.fs[j]=frzS; O.wp[j]=wp; O.cm[j]=cm; O.mf[j]=mf;
      O.comp[j]=compIdx; O.rec[j]=recBrk; O.dom[j]=recDom;
   }
}


//==================================================================
// SENSEEI GLOBAL STATE + OUTPUTS
//==================================================================
SEV60     v1,v2,v3,v4,v5,v6;          // ladder rungs 1..6 (rung3 = chart = canonical)
FUPoolOut sfpMN,sfpW,sfpD,sfpH4,sfpH1,sfpM15,sfpM5;

//--- node registry ---
double sn_px[],sn_mid[],sn_sc[]; int sn_dir[],sn_wt[],sn_state[],sn_bar[],sn_rev[];
double sn_pv[7];                       // last pushed tip per TF (MN,W,D,H4,H1,M15,M5)

//--- Senseei decision outputs (last closed bar) ---
int    sen_master=0, sen_waveDir=0, sen_stackDir=0, sen_netBias=0, sen_pdir=0, sen_timeDir=0;
double sen_stackPct=0, sen_alignment=0, sen_conflict=0, sen_threat=0, sen_confidence=0, sen_oppScore=0;
double sen_pressure=0, sen_residual=0, sen_attractorScore=0, sen_timeAlign=0, sen_timeConflict=0;
int    sen_resCode=0, sen_eligN=0;
string sen_action="WAIT", sen_intent="BALANCE", sen_timing="—", sen_opportunity="NONE", sen_phase="Point 4 Origin";
double sen_entry=NA, sen_stop=NA, sen_t1=NA, sen_t2=NA, sen_t3=NA, sen_attractorPx=NA, sen_netTarget=NA, sen_fezHi=NA, sen_fezLo=NA;
//--- curve life (management) ---
double sen_life=50.0, sen_cpForce=0; string sen_cpState="NEUTRAL", sen_alive="◐ WEAKENING";
//--- TIE detail ---
string sen_h1Timing="—"; double sen_wp=0, sen_atr=0;

double f_authSen(const int i){ return(sn_sc[i]+sn_wt[i]*4.0+sn_rev[i]*3.0); }
void SnPush(const double px,const double mid,const int dir,const double sc,const int wt,const int barI)
{
   int s=ArraySize(sn_px);
   ArrayResize(sn_px,s+1);ArrayResize(sn_mid,s+1);ArrayResize(sn_sc,s+1);ArrayResize(sn_dir,s+1);
   ArrayResize(sn_wt,s+1);ArrayResize(sn_state,s+1);ArrayResize(sn_bar,s+1);ArrayResize(sn_rev,s+1);
   sn_px[s]=px; sn_mid[s]=mid; sn_dir[s]=dir; sn_sc[s]=sc; sn_wt[s]=wt; sn_state[s]=0; sn_bar[s]=barI; sn_rev[s]=0;
   if(ArraySize(sn_px)>sIn_nodeMax){ ArrayRemove(sn_px,0,1);ArrayRemove(sn_mid,0,1);ArrayRemove(sn_sc,0,1);ArrayRemove(sn_dir,0,1);ArrayRemove(sn_wt,0,1);ArrayRemove(sn_state,0,1);ArrayRemove(sn_bar,0,1);ArrayRemove(sn_rev,0,1); }
}

//--- read the current (forming) cycle bar + prior extremes for the TIE ---
void CycleRead(const ENUM_TIMEFRAMES tf,double &o,double &h,double &l,double &ph,double &pl)
{
   o=NA;h=NA;l=NA;ph=NA;pl=NA;
   MqlRates r[]; ArraySetAsSeries(r,false);
   int got=CopyRates(_Symbol,tf,0,4,r); if(got<2) return;
   int cur=got-1, prv=got-2;
   o=r[cur].open; h=r[cur].high; l=r[cur].low; ph=r[prv].high; pl=r[prv].low;
}

//==================================================================
// SENSEEI DRIVER — full recompute -> sets sen_* for last closed bar
//==================================================================
void SenseeiRun(const int bars)
{
   TFData d; if(!LoadTF(_Period,bars,d)) return;
   int N=d.n; int warmup=MathMax(2*structLen,2*pivotLen)+effLen+10;
   if(N<warmup+5) return;
   int last=N-2;

   //--- chart ATR + EMA50 ---
   double atrC[]; ATRarr(d.h,d.l,d.c,atrC,atrLen);
   double emaC[]; EMAarr(d.c,emaC,50);

   //--- ladder structure engines (rung3 = chart = canonical) ---
   ComputeSE_V60(SenLadder(1),bars,pivotLen,structLen,atrLen,effThresh,dispThresh,convMult,impulseAtrMult,chochBufferATR,effLen,v1);
   ComputeSE_V60(SenLadder(2),bars,pivotLen,structLen,atrLen,effThresh,dispThresh,convMult,impulseAtrMult,chochBufferATR,effLen,v2);
   ComputeSE_V60(SenLadder(3),bars,pivotLen,structLen,atrLen,effThresh,dispThresh,convMult,impulseAtrMult,chochBufferATR,effLen,v3);
   ComputeSE_V60(SenLadder(4),bars,pivotLen,structLen,atrLen,effThresh,dispThresh,convMult,impulseAtrMult,chochBufferATR,effLen,v4);
   ComputeSE_V60(SenLadder(5),bars,pivotLen,structLen,atrLen,effThresh,dispThresh,convMult,impulseAtrMult,chochBufferATR,effLen,v5);
   ComputeSE_V60(SenLadder(6),bars,pivotLen,structLen,atrLen,effThresh,dispThresh,convMult,impulseAtrMult,chochBufferATR,effLen,v6);

   //--- FU pools for the fixed node ladder ---
   ComputeFUPool(PERIOD_MN1,bars,sIn_wickFrac,sfpMN);
   ComputeFUPool(PERIOD_W1, bars,sIn_wickFrac,sfpW);
   ComputeFUPool(PERIOD_D1, bars,sIn_wickFrac,sfpD);
   ComputeFUPool(PERIOD_H4, bars,sIn_wickFrac,sfpH4);
   ComputeFUPool(PERIOD_H1, bars,sIn_wickFrac,sfpH1);
   ComputeFUPool(PERIOD_M15,bars,sIn_wickFrac,sfpM15);
   ComputeFUPool(PERIOD_M5, bars,sIn_wickFrac,sfpM5);

   //--- rebuild node registry over the window ---
   ArrayResize(sn_px,0);ArrayResize(sn_mid,0);ArrayResize(sn_sc,0);ArrayResize(sn_dir,0);
   ArrayResize(sn_wt,0);ArrayResize(sn_state,0);ArrayResize(sn_bar,0);ArrayResize(sn_rev,0);
   for(int k=0;k<7;k++) sn_pv[k]=NA;
   int wts[7]={9,8,7,6,5,4,3};
   for(int j=warmup;j<=last;j++){
      datetime ct=d.t[j]; double clj=d.c[j];
      for(int k=0;k<7;k++){
         int vld=0; double tip=NA,mid=NA; int dr=0; double sc=0;
         if(k==0){ vld=MapValI(sfpMN.t,sfpMN.valid,sfpMN.n,ct); tip=MapVal(sfpMN.t,sfpMN.tip,sfpMN.n,ct); mid=MapVal(sfpMN.t,sfpMN.mid,sfpMN.n,ct); dr=MapValI(sfpMN.t,sfpMN.dir,sfpMN.n,ct); sc=MapVal(sfpMN.t,sfpMN.score,sfpMN.n,ct); }
         else if(k==1){ vld=MapValI(sfpW.t,sfpW.valid,sfpW.n,ct); tip=MapVal(sfpW.t,sfpW.tip,sfpW.n,ct); mid=MapVal(sfpW.t,sfpW.mid,sfpW.n,ct); dr=MapValI(sfpW.t,sfpW.dir,sfpW.n,ct); sc=MapVal(sfpW.t,sfpW.score,sfpW.n,ct); }
         else if(k==2){ vld=MapValI(sfpD.t,sfpD.valid,sfpD.n,ct); tip=MapVal(sfpD.t,sfpD.tip,sfpD.n,ct); mid=MapVal(sfpD.t,sfpD.mid,sfpD.n,ct); dr=MapValI(sfpD.t,sfpD.dir,sfpD.n,ct); sc=MapVal(sfpD.t,sfpD.score,sfpD.n,ct); }
         else if(k==3){ vld=MapValI(sfpH4.t,sfpH4.valid,sfpH4.n,ct); tip=MapVal(sfpH4.t,sfpH4.tip,sfpH4.n,ct); mid=MapVal(sfpH4.t,sfpH4.mid,sfpH4.n,ct); dr=MapValI(sfpH4.t,sfpH4.dir,sfpH4.n,ct); sc=MapVal(sfpH4.t,sfpH4.score,sfpH4.n,ct); }
         else if(k==4){ vld=MapValI(sfpH1.t,sfpH1.valid,sfpH1.n,ct); tip=MapVal(sfpH1.t,sfpH1.tip,sfpH1.n,ct); mid=MapVal(sfpH1.t,sfpH1.mid,sfpH1.n,ct); dr=MapValI(sfpH1.t,sfpH1.dir,sfpH1.n,ct); sc=MapVal(sfpH1.t,sfpH1.score,sfpH1.n,ct); }
         else if(k==5){ vld=MapValI(sfpM15.t,sfpM15.valid,sfpM15.n,ct); tip=MapVal(sfpM15.t,sfpM15.tip,sfpM15.n,ct); mid=MapVal(sfpM15.t,sfpM15.mid,sfpM15.n,ct); dr=MapValI(sfpM15.t,sfpM15.dir,sfpM15.n,ct); sc=MapVal(sfpM15.t,sfpM15.score,sfpM15.n,ct); }
         else { vld=MapValI(sfpM5.t,sfpM5.valid,sfpM5.n,ct); tip=MapVal(sfpM5.t,sfpM5.tip,sfpM5.n,ct); mid=MapVal(sfpM5.t,sfpM5.mid,sfpM5.n,ct); dr=MapValI(sfpM5.t,sfpM5.dir,sfpM5.n,ct); sc=MapVal(sfpM5.t,sfpM5.score,sfpM5.n,ct); }
         if(vld==1 && !naf(tip) && (naf(sn_pv[k])||tip!=sn_pv[k])){ SnPush(tip,mid,dr,sc,wts[k],j); sn_pv[k]=tip; }
      }
      //--- update node states with this bar ---
      double atrj=atrC[j];
      for(int i=0;i<ArraySize(sn_px);i++){
         if(sn_state[i]==2) continue;
         double np=sn_px[i]; int nd=sn_dir[i]; int age=j-sn_bar[i];
         if(nd==-1?clj>np:clj<np) sn_state[i]=2;
         else {
            if(MathAbs(clj-np)<atrj*0.25) sn_rev[i]++;
            sn_state[i]= age>sIn_historyBars*sn_wt[i]?3: age>sIn_dormantBars*sn_wt[i]?1:0;
         }
      }
   }

   //--- network aggregates at last bar ---
   double clL=d.c[last], atrL=atrC[last];
   int eligN=0; double bullAuth=0,bearAuth=0; int domIdx=-1; double domAuth=0;
   //--- netBias: highest-weight valid TF dir, else EMA50 ---
   datetime ctL=d.t[last];
   int netBias=0;
   for(int k=0;k<7;k++){
      int vld=0,dr=0;
      if(k==0){ vld=MapValI(sfpMN.t,sfpMN.valid,sfpMN.n,ctL); dr=MapValI(sfpMN.t,sfpMN.dir,sfpMN.n,ctL); }
      else if(k==1){ vld=MapValI(sfpW.t,sfpW.valid,sfpW.n,ctL); dr=MapValI(sfpW.t,sfpW.dir,sfpW.n,ctL); }
      else if(k==2){ vld=MapValI(sfpD.t,sfpD.valid,sfpD.n,ctL); dr=MapValI(sfpD.t,sfpD.dir,sfpD.n,ctL); }
      else if(k==3){ vld=MapValI(sfpH4.t,sfpH4.valid,sfpH4.n,ctL); dr=MapValI(sfpH4.t,sfpH4.dir,sfpH4.n,ctL); }
      else if(k==4){ vld=MapValI(sfpH1.t,sfpH1.valid,sfpH1.n,ctL); dr=MapValI(sfpH1.t,sfpH1.dir,sfpH1.n,ctL); }
      else if(k==5){ vld=MapValI(sfpM15.t,sfpM15.valid,sfpM15.n,ctL); dr=MapValI(sfpM15.t,sfpM15.dir,sfpM15.n,ctL); }
      else { vld=MapValI(sfpM5.t,sfpM5.valid,sfpM5.n,ctL); dr=MapValI(sfpM5.t,sfpM5.dir,sfpM5.n,ctL); }
      if(vld==1 && dr!=0){ netBias=dr; break; }
   }
   if(netBias==0) netBias=clL>emaC[last]?1:clL<emaC[last]?-1:0;

   int attrIdx=-1; double attrRank=-1; double fezHi=NA,fezLo=NA,fezHiA=0,fezLoA=0;
   for(int i=0;i<ArraySize(sn_px);i++){
      int st=sn_state[i]; double a=f_authSen(i);
      if(st!=2 && a>=sIn_authMin){
         double np=sn_px[i]; int nd=sn_dir[i]; int wt=sn_wt[i];
         eligN++;
         if(nd==1) bullAuth+=a; else if(nd==-1) bearAuth+=a;
         if(a>domAuth){ domAuth=a; domIdx=i; }
         bool onBias=netBias==-1?np<clL:np>clL;
         if(onBias){ double rk=wt*1000.0+a; if(rk>attrRank){ attrRank=rk; attrIdx=i; } }
         if(np>clL && a>fezHiA){ fezHi=np; fezHiA=a; }
         if(np<clL && a>fezLoA){ fezLo=np; fezLoA=a; }
      }
   }
   double pressure=(bullAuth+bearAuth)>0?(bullAuth-bearAuth)/(bullAuth+bearAuth)*100.0:0.0;
   int pdir=pressure>12?1:pressure<-12?-1:0;
   double netTarget=attrIdx>=0?sn_px[attrIdx]:NA;

   //--- map canonical (rung3) + ladder rung dirs at last bar ---
   int  c_ph=(int)nz(MapVal(v3.t,v3.ph,v3.n,ctL));
   double c_inv=MapVal(v3.t,v3.inv,v3.n,ctL), c_tgt=MapVal(v3.t,v3.tgt,v3.n,ctL);
   double c_ft=MapVal(v3.t,v3.ft,v3.n,ctL), c_fb=MapVal(v3.t,v3.fb,v3.n,ctL);
   double c_p4h=MapVal(v3.t,v3.p4h,v3.n,ctL), c_p4l=MapVal(v3.t,v3.p4l,v3.n,ctL);
   double c_wp=nz(MapVal(v3.t,v3.wp,v3.n,ctL)), c_comp=nz(MapVal(v3.t,v3.comp,v3.n,ctL)), c_rec=nz(MapVal(v3.t,v3.rec,v3.n,ctL));
   double c_mf=nz(MapVal(v3.t,v3.mf,v3.n,ctL));
   int waveDir=f_waveDirByOrigin(c_inv,clL,(int)nz(MapVal(v3.t,v3.dir,v3.n,ctL)));
   string phaseStr=f_phaseStrV60(c_ph);

   int d1=f_waveDirByOrigin(MapVal(v1.t,v1.inv,v1.n,ctL),clL,(int)nz(MapVal(v1.t,v1.dir,v1.n,ctL)));
   int d2=f_waveDirByOrigin(MapVal(v2.t,v2.inv,v2.n,ctL),clL,(int)nz(MapVal(v2.t,v2.dir,v2.n,ctL)));
   int d4=f_waveDirByOrigin(MapVal(v4.t,v4.inv,v4.n,ctL),clL,(int)nz(MapVal(v4.t,v4.dir,v4.n,ctL)));
   int d5=f_waveDirByOrigin(MapVal(v5.t,v5.inv,v5.n,ctL),clL,(int)nz(MapVal(v5.t,v5.dir,v5.n,ctL)));
   int d6=f_waveDirByOrigin(MapVal(v6.t,v6.inv,v6.n,ctL),clL,(int)nz(MapVal(v6.t,v6.dir,v6.n,ctL)));
   int sb=(d1==1?1:0)+(d2==1?1:0)+(waveDir==1?1:0)+(d4==1?1:0)+(d5==1?1:0)+(d6==1?1:0);
   int sbe=(d1==-1?1:0)+(d2==-1?1:0)+(waveDir==-1?1:0)+(d4==-1?1:0)+(d5==-1?1:0)+(d6==-1?1:0);
   int stackDir=sb>sbe?1:sbe>sb?-1:0;
   double stackPct=(double)MathMax(sb,sbe)/6.0*100.0;
   double t2=MapVal(v4.t,v4.tgt,v4.n,ctL), t3=MapVal(v5.t,v5.tgt,v5.n,ctL);

   //--- TIE (cycle stack MN/W/D/H4/H1) ---
   double mo,mh,ml,mph,mpl; CycleRead(PERIOD_MN1,mo,mh,ml,mph,mpl);
   double wo,wh,wl,wph,wpl; CycleRead(PERIOD_W1, wo,wh,wl,wph,wpl);
   double do_,dh,dl,dph,dpl; CycleRead(PERIOD_D1, do_,dh,dl,dph,dpl);
   double ho,hh,hl,hph,hpl; CycleRead(PERIOD_H4, ho,hh,hl,hph,hpl);
   double o1,h1,l1,ph1,pl1; CycleRead(PERIOD_H1, o1,h1,l1,ph1,pl1);
   int tBull=(!naf(mo)&&clL>mo?1:0)+(!naf(wo)&&clL>wo?1:0)+(!naf(do_)&&clL>do_?1:0)+(!naf(ho)&&clL>ho?1:0)+(!naf(o1)&&clL>o1?1:0);
   int tBear=(!naf(mo)&&clL<mo?1:0)+(!naf(wo)&&clL<wo?1:0)+(!naf(do_)&&clL<do_?1:0)+(!naf(ho)&&clL<ho?1:0)+(!naf(o1)&&clL<o1?1:0);
   int timeDir=tBull>tBear?1:tBear>tBull?-1:0;
   double timeAlign=(tBull+tBear)>0?(double)MathMax(tBull,tBear)/(tBull+tBear)*100.0:50.0;
   double timeConflict=100.0-timeAlign;
   bool h1Ht=!naf(h1)&&!naf(ph1)&&h1>ph1, h1Lt=!naf(l1)&&!naf(pl1)&&l1<pl1;
   double h1pos=(!naf(h1)&&!naf(l1)&&h1>l1)?(clL-l1)/fmax2(h1-l1,_Point):0.5;
   double h1LowProb=(h1Lt&&!h1Ht)?30.0:(h1Ht&&!h1Lt)?70.0:MathRound(h1pos*100.0);
   string h1Timing=(h1Ht&&h1Lt)?"COMPLETION":h1LowProb>=55?"LOW FIRST":h1LowProb<=45?"HIGH FIRST":"BALANCED";

   //--- EDE / RE / EAE (compact, from canonical phase) ---
   int ede_state=(phaseStr=="Point 4 Origin"||phaseStr=="Expansion")?1:phaseStr=="Expansion Pre-Convexity"?2:phaseStr=="Expansion Induction"?3:phaseStr=="Expansion Liquidity"?4:(phaseStr=="New High"||phaseStr=="New Low")?5:6;
   double dissProg=fmin2((ede_state>=2?25.0:0.0)+(ede_state>=3?25.0:0.0)+(ede_state>=4?25.0:0.0)+(ede_state>=5?25.0:0.0),100.0);
   double residual=clamp(100.0-c_wp,0.0,100.0);
   int resCode=(phaseStr=="Demand Return"||phaseStr=="Supply Return")?2:(phaseStr=="New High"||phaseStr=="New Low"||phaseStr=="Terminal Curve"||phaseStr=="Liquidation")?1:0;
   double attractorPx=resCode==0?(waveDir==1?nz(c_fb,clL-atrL*2.0):nz(c_ft,clL+atrL*2.0)):(waveDir==1?nz(c_p4l,clL-atrL):nz(c_p4h,clL+atrL));
   if(naf(attractorPx)) attractorPx=netTarget;
   double attractorScore=fmin2(residual*0.40+(resCode==0?30.0:resCode==1?20.0:5.0)+(!naf(attractorPx)?fmax2(0.0,30.0-MathAbs(clL-attractorPx)/fmax2(atrL,1e-10)*5.0):0.0),100.0);

   //--- Senseei meta-intelligence ---
   int vt1=waveDir, vt2=stackDir, vt3=netBias, vt4=pdir;
   int sum=vt1+vt2+vt3+vt4;
   int master=sum>0?1:sum<0?-1:0;
   int cast=(vt1!=0?1:0)+(vt2!=0?1:0)+(vt3!=0?1:0)+(vt4!=0?1:0);
   int forV=(vt1==master&&vt1!=0?1:0)+(vt2==master&&vt2!=0?1:0)+(vt3==master&&vt3!=0?1:0)+(vt4==master&&vt4!=0?1:0);
   double alignment=cast>0?(double)forV/cast*100.0:50.0;
   double conflict=cast>0?(double)(cast-forV)/cast*100.0:0.0;
   double threat=clamp(conflict*0.40+residual*0.28+timeConflict*0.12+(pdir!=0&&pdir!=master?18.0:0.0)+(resCode==1?10.0:0.0),0.0,100.0);
   double confidence=clamp(alignment*0.40+timeAlign*0.12+stackPct*0.18+attractorScore*0.15+fmin2(15.0,eligN*1.2)-threat*0.20,0.0,100.0);
   string timing=(resCode==2)?"RESOLVED":c_wp<15?"VERY EARLY":c_wp<35?"EARLY":c_wp<55?"DEVELOPING":c_wp<80?"MID CYCLE":c_wp<96?"LATE":"TERMINAL";
   string intent=conflict>55?"ABSORPTION":(phaseStr=="Expansion"||phaseStr=="New High"||phaseStr=="New Low")?"EXPANSION":phaseStr=="Expansion Pre-Convexity"?"CONTINUATION":(phaseStr=="Expansion Induction"||phaseStr=="Induction")?"RESOLUTION":(phaseStr=="Expansion Liquidity"||phaseStr=="Liquidation"||phaseStr=="Terminal Curve")?"DELIVERY":master==0?"BALANCE":"CONTINUATION";
   double oppScore=clamp(alignment*0.40+attractorScore*0.30+stackPct*0.30-threat*0.35,0.0,100.0);
   string opportunity=master==0?"NONE":conflict>60?"DEVELOPING":oppScore<20?"NONE":oppScore<40?"DEVELOPING":oppScore<62?"GOOD":oppScore<82?"STRONG":"EXCEPTIONAL";
   string action=master==0?"WAIT":conflict>60?"WAIT":resCode==2?"MANAGE / EXIT":((opportunity=="STRONG"||opportunity=="EXCEPTIONAL")&&confidence>=sIn_minConf&&threat<sIn_maxThreat)?"ATTACK":(opportunity=="GOOD"||opportunity=="STRONG")?"PREPARE":"WAIT";

   //--- attack levels ---
   double entry=(!naf(c_ft)&&!naf(c_fb))?(c_ft+c_fb)/2.0:NA;

   //--- F72 curve life ("is the trade alive?") ---
   double cExtreme=waveDir==1?MapVal(v3.t,v3.sh,v3.n,ctL):waveDir==-1?MapVal(v3.t,v3.sl,v3.n,ctL):NA;
   double retrX=(naf(cExtreme)||naf(c_inv)||cExtreme==c_inv)?50.0:fmin2(100.0,MathAbs(cExtreme-clL)/MathAbs(cExtreme-c_inv)*100.0);
   bool attacking=waveDir==1?(!naf(cExtreme)&&d.h[last]>=cExtreme):waveDir==-1?(!naf(cExtreme)&&d.l[last]<=cExtreme):false;
   bool progressing=attacking;
   int budgetDepth=MathMax(1,MathMin(4,1+(int)MathRound(c_comp/33.0)));
   bool recursionComplete=budgetDepth>0 && (int)c_rec>=budgetDepth;
   double cpForce=clamp(c_comp*0.50+residual*0.20-(int)c_rec*12.0+8.0,0.0,100.0);
   string cpState=cpForce>=60.0?"PERSISTING":cpForce<=35.0?"LEAKING":"NEUTRAL";
   double life=clamp(cpForce*0.45+residual*0.30-(recursionComplete&&!progressing?25.0:0.0)-(cpState=="LEAKING"&&!progressing?20.0:0.0)+(progressing?28.0:0.0)+(retrX<25.0?16.0:retrX<45.0?6.0:retrX>75.0?-12.0:0.0)+10.0,0.0,100.0);
   string aliveTx=(progressing&&life>=45.0)?"▲ ALIVE · ATTACKING":life>=60.0?"● ALIVE · HOLD":life<=32.0?"✕ DEAD · FLIP":"◐ WEAKENING · MANAGE";

   //--- publish ---
   sen_master=master; sen_waveDir=waveDir; sen_stackDir=stackDir; sen_netBias=netBias; sen_pdir=pdir; sen_timeDir=timeDir;
   sen_stackPct=stackPct; sen_alignment=alignment; sen_conflict=conflict; sen_threat=threat; sen_confidence=confidence; sen_oppScore=oppScore;
   sen_pressure=pressure; sen_residual=residual; sen_attractorScore=attractorScore; sen_timeAlign=timeAlign; sen_timeConflict=timeConflict;
   sen_resCode=resCode; sen_eligN=eligN; sen_action=action; sen_intent=intent; sen_timing=timing; sen_opportunity=opportunity; sen_phase=phaseStr;
   sen_entry=entry; sen_stop=c_inv; sen_t1=nz(c_tgt,attractorPx); sen_t2=t2; sen_t3=t3; sen_attractorPx=attractorPx; sen_netTarget=netTarget; sen_fezHi=fezHi; sen_fezLo=fezLo;
   sen_life=life; sen_cpForce=cpForce; sen_cpState=cpState; sen_alive=aliveTx; sen_h1Timing=h1Timing; sen_wp=c_wp; sen_atr=atrL;
}

#endif // __LETRA37_SENSEEI_MQH__
