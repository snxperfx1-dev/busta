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

//================================================================================
//  ENGINE (inlined from Letra37_Engine.mqh)
//================================================================================
//+------------------------------------------------------------------+
//| Letra37_Engine.mqh                                               |
//| Shared analytical engine for the Letra 37 port.                  |
//| Included by both Letra37.mq5 (indicator) and Letra37_EA.mq5 (EA).|
//| Contains: all inputs, the multi-timeframe structure/physics/     |
//| belief/FU engines, the full chart-TF intelligence pipeline,      |
//| ERF, FRZ, and the V72 decision architecture.                     |
//+------------------------------------------------------------------+
//==================================================================
// ENUMS (replicating Pine string-option inputs)
//==================================================================
enum ENUM_DISPLAY_MODE { DM_EXECUTION, DM_CONTEXT, DM_RESEARCH };
enum ENUM_ORIGIN_MODE  { OM_NONE, OM_SHORT, OM_LONG, OM_BOTH };
enum ENUM_TXT_SIZE     { TS_TINY, TS_SMALL, TS_NORMAL };
enum ENUM_PANEL_POS    { PP_TOP, PP_MIDDLE, PP_BOTTOM };

//==================================================================
// SECTION 1 — INPUTS (ported 1:1 from the Pine source)
//==================================================================

//--- Dashboard panel toggles -------------------------------------
input group "Dashboard A - Command Center"
input bool showDA_Header      = true;
input bool showDA_Directive   = true;
input bool showDA_WaveCtx     = true;
input bool showDA_MarketState = true;
input bool showDA_HTFStack    = true;
input bool showDA_Physics     = true;

input group "Dashboard B - Belief Distributions"
input bool showDB_Header   = true;
input bool showDB_Beliefs  = true;
input bool showDB_Proximity= true;
input bool showDB_ConvEvid = true;
input bool showDB_PhysObs  = true;
input bool showDB_Geometry = true;

input group "Dashboard C - Intelligence Engine"
input bool showDC_Header     = true;
input bool showDC_Hypothesis = true;
input bool showDC_Prediction = true;
input bool showDC_Validation = true;
input bool showDC_AdapConf   = true;
input bool showDC_M1Warn     = true;
input bool showDC_Quality    = true;
input bool showDC_DirProb    = true;
input bool showDC_LiveOpp    = true;
input bool showDC_Execution  = true;

input group "Dashboard P3 - Recursive Wave Intel"
input bool showDP3_Header       = true;
input bool showDP3_Narrative    = true;
input bool showDP3_Nested       = true;
input bool showDP3_Dominance    = true;
input bool showDP3_Fusion       = true;
input bool showDP3_Agreement    = true;
input bool showDP3_FractalConf  = true;
input bool showDP3_Cycles       = true;
input bool showDP3_GeoCap       = true;
input bool showDP3_ExecProb     = true;
input bool showDP3_WaveProgress = true;

input group "Dashboard FU - FU Order Blocks"
input bool showDFU_Panel    = true;
input bool showDFU_Header   = true;
input bool showDFU_Stats    = true;
input bool showDFU_LastBlock= true;

//--- Section 9 entry-cycle visibility ----------------------------
input group "Entry Cycle Visibility (Section 9)"
input bool ecvSupply         = true;
input bool ecvDemand         = true;
input bool ecvHighs          = true;
input bool ecvLows           = true;
input bool ecvExpansion      = true;
input bool ecvPreConvexity   = true;
input bool ecvConvexity      = true;
input bool ecvAbsorption     = true;
input bool ecvRetracement    = true;
input bool ecvInduction      = true;
input bool ecvLiquidation    = true;
input bool ecvFUCandle       = true;
input bool ecvImbalance      = true;
input bool ecvFUImbalance    = true;
input bool ecvOrigin         = true;
input bool ecvWaveCompletion = true;
input bool ecvAllLocations   = false;

//--- Core --------------------------------------------------------
input group "Core Settings"
input int   pivotLen  = 5;
input int   atrLen    = 14;
input int   effLen    = 10;
input int   resetBars = 20;

//--- Filters -----------------------------------------------------
input group "Displacement & Filters"
input double impulseAtrMult = 1.5;
input double retrMin        = 0.3;
input double retrMax        = 0.8;
input double effThresh      = 0.65;
input double dispThresh     = 1.5;
input double convMult       = 0.01;
input int    acceptBars     = 2;
input int    obLookback     = 8;
input int    obMaxBars      = 50;

//--- Structure ---------------------------------------------------
input group "Market Structure"
input bool   useStrictStructure = true;
input int    structLen          = 10;
input bool   showStruct         = true;
input bool   requireStruct      = true;
input double chochBufferATR     = 0.75;

//--- Inducement --------------------------------------------------
input group "Inducement Engine"
input int    inducLookback    = 80;
input double inducZoneWidth   = 0.25;
input bool   requirePreConv   = true;
input bool   requireInduction = true;
input bool   showInducZone    = true;
input bool   showInducLabels  = true;

//--- Liquidity ---------------------------------------------------
input group "Liquidity Engine"
input double liqRadius        = 0.25;
input double liqAgDecay       = 0.95;
input bool   showLiq          = true;
input bool   requireLiqSweep  = true;
input int    liqSweepLookback = 10;

//--- MTF ---------------------------------------------------------
input group "Multi-Timeframe"
input ENUM_TIMEFRAMES tf1 = PERIOD_M15;   // Timeframe 1 (HTF Bias)
input ENUM_TIMEFRAMES tf2 = PERIOD_H1;    // Timeframe 2 (HTF Bias)

//--- Execution ---------------------------------------------------
input group "Execution Controls"
input int    baseLockBars    = 10;
input bool   requireHTFAlign = false;
input double execThreshold   = 5.0;

//--- Visuals -----------------------------------------------------
input group "Visuals"
input bool             showFlipzone     = true;
input bool             showLabels       = true;
input bool             showSignals      = true;
input bool             showTable        = true;
input bool             showSDZones      = true;
input bool             showP4Box        = true;
input bool             showCycleHistory = true;
input ENUM_ORIGIN_MODE originMode       = OM_NONE;
input ENUM_TXT_SIZE    dashTextSize     = TS_SMALL;
input bool             zoneFillOn       = false;

//--- Intelligence engine -----------------------------------------
input group "Intelligence Engine"
input int    beliefSmooth      = 3;
input double confDecayRate     = 0.02;
input double devReinterpThresh = 30.0;

//--- FU order block inputs ---------------------------------------
input group "FU Order Blocks"
input bool   showFUBlocks    = true;
input bool   showFULabels    = true;
input int    fuLookback      = 3;
input double fuMinBodyRatio  = 0.6;
input double fuMinWickRatio  = 0.25;
input int    fuMaxBarsActive = 75;
input bool   fuRequireInZone = true;
input bool   fuBoostBelief   = true;
input bool   fuAlertOn       = true;
input bool   showFUWick      = true;
input int    fuwLookback     = 5;
input double fuwMinWickFrac  = 0.5;
input int    fuAuthMin       = 40;

//--- Display intelligence engine ---------------------------------
input group "Display Intelligence Engine"
input ENUM_DISPLAY_MODE displayMode      = DM_EXECUTION;
input bool   showFUConflLabel = true;
input bool   showFULifecycle  = true;
input bool   enableClustering = true;
input int    clusterWindow    = 8;
input bool   showNarrative    = true;
input bool   showDIE_Dashboard= true;

//--- Future return zones -----------------------------------------
input group "Future Return Zones (Section 17/18)"
input bool   showFRZ           = true;
input bool   showFRZ_Labels    = true;
input bool   showFRZ_Dashboard = true;
input int    frz_minScore      = 26;
input int    frz_maxBarsActive = 100;

//--- Energy resolution framework ---------------------------------
input group "Energy Resolution Framework (ERF)"
input bool   showERF_Dashboard = true;
input double erfReadyResW      = 0.25;
input double erfReadyResidW    = 0.20;
input double erfReadyConfW     = 0.15;
input double erfEntryThreshold = 45.0;
input bool   erfGateEnabled    = true;
input bool   showEntryZone     = true;
input double entryZoneWidthA   = 0.15;

//--- V72 decision dashboard --------------------------------------
input group "V72 - Decision Dashboard"
input bool            in_dashAdvancedMode = false;
input bool            in_showV72Command   = true;
input ENUM_PANEL_POS  commandPanelYOffset = PP_BOTTOM;
input bool            showV72Destination  = true;
input bool            showV72RevDest      = false;

input group "V72 - Trade Qualification (TQE)"
input double in_frzProximityATR   = 2.0;
input double in_frzConvergenceATR = 0.5;
input double in_tqeW_ie1a = 0.25;
input double in_tqeW_erf  = 0.15;
input double in_tqeW_frz  = 0.15;
input double in_tqeW_mce  = 0.20;
input double in_tqeW_re   = 0.10;
input double in_tqeW_liq  = 0.15;
input double in_tqeGradeA1= 85.0;
input double in_tqeGradeA = 72.0;
input double in_tqeGradeB = 58.0;
input double in_tqeGradeC = 42.0;

input group "V72 - Rotation Intelligence (RIE)"
input double in_rieW_decay   = 0.35;
input double in_rieW_absorb  = 0.30;
input double in_rieW_convex  = 0.20;
input double in_rieW_stabExp = 0.40;
input double in_rieW_press   = 0.50;
input double in_rieW_stabInv = 0.30;

input group "V72 - Multi-TF Consensus (MCE)"
input ENUM_TIMEFRAMES mce_tf3 = PERIOD_H4;  // MCE TF3 (HTF)
input ENUM_TIMEFRAMES mce_tf4 = PERIOD_D1;  // MCE TF4 (HTF)

input group "V72 - Target / Invalidation"
input double in_invOriginBuffer = 0.25;
input double in_invZoneBuffer   = 0.10;
input double in_teTertiaryATR   = 2.0;
input double in_rrMinimum       = 1.5;
input bool   in_teTertiaryOn    = false;

input group "V72 - Decision Output (DOE)"
input int    in_doeCapBase = 88;
input int    in_doeCapConv = 95;

//--- Derived origin flags ----------------------------------------
bool showOriginShort;   // set in OnInit
bool showOriginLong;


//==================================================================
// NA SENTINEL + MATH HELPERS (replicating Pine na / ta.* on series)
//==================================================================
#define NA  DBL_MAX

bool   naf(const double x){ return(x==DBL_MAX || x!=x); }
double nz(const double x, const double rep=0.0){ return(naf(x)? rep : x); }
double fmin2(const double a,const double b){ return(a<b?a:b); }
double fmax2(const double a,const double b){ return(a>b?a:b); }
double clamp(const double v,const double lo,const double hi){ return(v<lo?lo:(v>hi?hi:v)); }
int    iclamp(const int v,const int lo,const int hi){ return(v<lo?lo:(v>hi?hi:v)); }

//--- EMA over an oldest->newest array ----------------------------
void EMAarr(const double &src[], double &dst[], const int period)
{
   int n=ArraySize(src); ArrayResize(dst,n);
   if(n==0) return;
   double a=2.0/(period+1.0);
   dst[0]=src[0];
   for(int j=1;j<n;j++) dst[j]=dst[j-1]+a*(src[j]-dst[j-1]);
}

//--- SMA -----------------------------------------------------------
void SMAarr(const double &src[], double &dst[], const int period)
{
   int n=ArraySize(src); ArrayResize(dst,n);
   double run=0;
   for(int j=0;j<n;j++){
      run+=src[j];
      if(j>=period) run-=src[j-period];
      int cnt=(j+1<period)?(j+1):period;
      dst[j]=run/cnt;
   }
}

//--- ATR (Wilder RMA of true range) -------------------------------
void ATRarr(const double &h[], const double &l[], const double &c[], double &dst[], const int period)
{
   int n=ArraySize(c); ArrayResize(dst,n);
   if(n==0) return;
   double tr;
   double prevRMA=0; double seedSum=0;
   for(int j=0;j<n;j++){
      if(j==0) tr=h[0]-l[0];
      else tr=fmax2(h[j]-l[j], fmax2(MathAbs(h[j]-c[j-1]), MathAbs(l[j]-c[j-1])));
      if(j<period){ seedSum+=tr; dst[j]=seedSum/(j+1); prevRMA=dst[j]; }
      else { prevRMA=(prevRMA*(period-1)+tr)/period; dst[j]=prevRMA; }
   }
}

//--- pivot high/low: value emitted at bar (center+len), else NA ----
void PivotHigh(const double &h[], double &dst[], const int len)
{
   int n=ArraySize(h); ArrayResize(dst,n); ArrayInitialize(dst,NA);
   for(int j=2*len;j<n;j++){
      int ctr=j-len; double v=h[ctr]; bool piv=true;
      for(int k=ctr-len;k<=ctr+len && piv;k++){ if(k==ctr) continue; if(h[k]>=v) piv=false; }
      if(piv) dst[j]=v;
   }
}
void PivotLow(const double &l[], double &dst[], const int len)
{
   int n=ArraySize(l); ArrayResize(dst,n); ArrayInitialize(dst,NA);
   for(int j=2*len;j<n;j++){
      int ctr=j-len; double v=l[ctr]; bool piv=true;
      for(int k=ctr-len;k<=ctr+len && piv;k++){ if(k==ctr) continue; if(l[k]<=v) piv=false; }
      if(piv) dst[j]=v;
   }
}

//--- helpers used inside engines ----------------------------------
double SumAbsDiff(const double &c[], const int j, const int len)
{
   double s=0; for(int k=0;k<len;k++){ int a=j-k, b=j-k-1; if(b<0) break; s+=MathAbs(c[a]-c[b]); } return(s);
}
double HighestPrior(const double &h[], const int j, const int len)
{ // max over [j-len .. j-1]   == ta.highest(h,len)[1]
   double m=-DBL_MAX; for(int k=1;k<=len;k++){ int idx=j-k; if(idx<0) break; if(h[idx]>m) m=h[idx]; } return(m==-DBL_MAX?NA:m);
}
double LowestPrior(const double &l[], const int j, const int len)
{
   double m=DBL_MAX; for(int k=1;k<=len;k++){ int idx=j-k; if(idx<0) break; if(l[idx]<m) m=l[idx]; } return(m==DBL_MAX?NA:m);
}
double HighestN(const double &h[], const int j, const int len)
{
   double m=-DBL_MAX; for(int k=0;k<len;k++){ int idx=j-k; if(idx<0) break; if(h[idx]>m) m=h[idx]; } return(m==-DBL_MAX?NA:m);
}
double LowestN(const double &l[], const int j, const int len)
{
   double m=DBL_MAX; for(int k=0;k<len;k++){ int idx=j-k; if(idx<0) break; if(l[idx]<m) m=l[idx]; } return(m==DBL_MAX?NA:m);
}

//==================================================================
// PER-TIMEFRAME RATES CONTAINER + LOADER
//==================================================================
struct TFData
{
   datetime t[];
   double   o[], h[], l[], c[];
   double   vol[];
   int      n;
};

bool LoadTF(const ENUM_TIMEFRAMES tf, const int bars, TFData &d)
{
   MqlRates r[];
   ArraySetAsSeries(r,false);
   int got=CopyRates(_Symbol, tf, 0, bars, r);
   if(got<=0){ d.n=0; return(false); }
   d.n=got;
   ArrayResize(d.t,got); ArrayResize(d.o,got); ArrayResize(d.h,got);
   ArrayResize(d.l,got); ArrayResize(d.c,got); ArrayResize(d.vol,got);
   for(int i=0;i<got;i++){
      d.t[i]=r[i].time; d.o[i]=r[i].open; d.h[i]=r[i].high;
      d.l[i]=r[i].low;  d.c[i]=r[i].close; d.vol[i]=(double)r[i].tick_volume;
   }
   return(true);
}

//--- f_safeTF: clamp a requested TF up to chart TF when chart>H1 ---
ENUM_TIMEFRAMES SafeTF(const ENUM_TIMEFRAMES req)
{
   int chartSec=PeriodSeconds(_Period);
   if(chartSec>3600 && PeriodSeconds(req)<chartSec) return(_Period);
   return(req);
}

//==================================================================
// STRUCTURE ENGINE  (f_se) — full 18-output state machine per TF
//==================================================================
struct SEOut
{
   datetime t[];
   int    n;
   double dir[], ph[], sh[], sl[], psh[], psl[], bos[], ch[];
   double p4h[], p4l[], inv[], tgt[], ft[], fb[], fs[], wp[], cm[], mf[];
};

void ComputeSE(const ENUM_TIMEFRAMES tfReq, const int bars,
               const int pvLen, const int stLen, const int atrL,
               const double effT, const double dispT, const double convM,
               const double impM, const double chBuf, const int effL,
               SEOut &O)
{
   ENUM_TIMEFRAMES tf=SafeTF(tfReq);
   TFData d; if(!LoadTF(tf,bars,d) || d.n<2*pvLen+5){ O.n=0; return; }
   int n=d.n;

   //--- precompute series ---
   double diff[]; ArrayResize(diff,n); diff[0]=0; for(int j=1;j<n;j++) diff[j]=d.c[j]-d.c[j-1];
   double vel[]; EMAarr(diff,vel,3);
   double acc[]; ArrayResize(acc,n); acc[0]=0; for(int j=1;j<n;j++) acc[j]=vel[j]-vel[j-1];
   double cvx[]; ArrayResize(cvx,n); cvx[0]=0; for(int j=1;j<n;j++) cvx[j]=acc[j]-acc[j-1];
   double csm[]; EMAarr(cvx,csm,3);
   double atr[]; ATRarr(d.h,d.l,d.c,atr,atrL);
   double phA[]; PivotHigh(d.h,phA,pvLen);
   double plA[]; PivotLow(d.l,plA,pvLen);

   //--- outputs ---
   O.n=n; ArrayResize(O.t,n);
   ArrayResize(O.dir,n); ArrayResize(O.ph,n); ArrayResize(O.sh,n); ArrayResize(O.sl,n);
   ArrayResize(O.psh,n); ArrayResize(O.psl,n); ArrayResize(O.bos,n); ArrayResize(O.ch,n);
   ArrayResize(O.p4h,n); ArrayResize(O.p4l,n); ArrayResize(O.inv,n); ArrayResize(O.tgt,n);
   ArrayResize(O.ft,n);  ArrayResize(O.fb,n);  ArrayResize(O.fs,n);  ArrayResize(O.wp,n);
   ArrayResize(O.cm,n);  ArrayResize(O.mf,n);

   //--- state (var) ---
   double curSH=NA,curSL=NA,prSH=NA,prSL=NA;
   double lastP=NA,prevP=NA; int lastD=0,prevD=0;
   int    dir=0; double ftv=NA,fbv=NA,p4h=NA,p4l=NA,inv=NA,tgt=NA,cycH=NA,cycL=NA;
   bool   bos1=false,bos2=false; double protSw=NA,protSw2=NA,indOrig=NA,indExt=NA; bool indBrk=false;
   int    lastDirSeen=0; int phaseState=0; int recBrk=0; bool recArm=true;

   for(int j=0;j<n;j++){
      O.t[j]=d.t[j];
      double cl=d.c[j], op=d.o[j], hi=d.h[j], lo=d.l[j];
      double A=atr[j];
      double mv=(j>=effL)?MathAbs(cl-d.c[j-effL]):0.0;
      double ps=SumAbsDiff(d.c,j,effL);
      double eff=(ps>0)?mv/ps:0.0;
      double disp=(hi-lo)/fmax2(A,1e-10);
      double velP=(j>0)?vel[j-1]:0, accP=(j>0)?acc[j-1]:0, accP2=accP;
      bool bullImp=eff>effT && vel[j]>velP && acc[j]>0 && cl>op && disp>dispT;
      bool bearImp=eff>effT && vel[j]<velP && acc[j]<0 && cl<op && disp>dispT;
      bool bullDec=MathAbs(acc[j])<MathAbs(accP)*0.8 && vel[j]>0;
      bool bearDec=MathAbs(acc[j])<MathAbs(accP)*0.8 && vel[j]<0;

      double pH=phA[j], pL=plA[j];
      //--- swings ---
      if(!naf(pH)){ prSH = naf(curSH)?pH:curSH; curSH=pH; }
      if(!naf(pL)){ prSL = naf(curSL)?pL:curSL; curSL=pL; }
      //--- pivot memory ---
      double eP=NA; int eD=0;
      if(!naf(pH)){ eP=pH; eD=1; } else if(!naf(pL)){ eP=pL; eD=-1; }
      if(eD!=0){ prevP=lastP; prevD=lastD; lastP=eP; lastD=eD; }
      //--- BOS/CHoCH ---
      bool bullBOS=!naf(prSH) && cl>prSH;
      bool bearBOS=!naf(prSL) && cl<prSL;
      bool bullCH =!naf(prSH) && cl>prSH+A*chBuf;
      bool bearCH =!naf(prSL) && cl<prSL-A*chBuf;
      //--- impulse ---
      bool eLong =!naf(pH) && prevD==-1 && (pH-prevP)>A*impM;
      bool eShort=!naf(pL) && prevD==1  && (prevP-pL)>A*impM;
      //--- direction / point4 / invalidation / target ---
      bool hasCtx=dir!=0 && !naf(ftv);
      bool flipDn=dir==1  && bearCH;
      bool flipUp=dir==-1 && bullCH;
      bool isRev=(eLong && dir==-1)||(eShort && dir==1)||flipUp||flipDn;
      bool spawn=(eLong||eShort||flipUp||flipDn) && (!hasCtx||isRev);
      if(spawn){
         int nd = eLong?1: eShort?-1: flipUp?1:-1;
         double _hi=fmax2(lastP,prevP), _lo=fmin2(lastP,prevP);  // v60 DIR-FIX: order OB by price, not pivot recency
         double obT=_hi, obB=_lo;
         dir=nd; ftv=obT; fbv=obB; p4h=obT; p4l=obB; cycH=hi; cycL=lo;
         inv = nd==1?_lo:_hi;                                     // invalidation pinned to the protective extreme
         double rng=(!naf(prSH)&&!naf(prSL))?MathAbs(prSH-prSL):A*5.0;
         tgt = nd==1? nz(obT,cl)+rng : nz(obB,cl)-rng;
      }
      if(dir==1)  cycH=naf(cycH)?hi:fmax2(cycH,hi);
      if(dir==-1) cycL=naf(cycL)?lo:fmin2(cycL,lo);

      int bosOut=bullBOS?1:(bearBOS?-1:0);
      int chOut =bullCH?1:(bearCH?-1:0);

      //--- lifecycle ---
      bool reset=(dir!=lastDirSeen); lastDirSeen=dir;
      if(reset){ bos1=false; bos2=false; protSw=NA; protSw2=NA; indOrig=NA; indExt=NA; indBrk=false; }
      if(dir==1 && !naf(pL)){ protSw2=protSw; protSw=pL; }
      if(dir==-1 && !naf(pH)){ protSw2=protSw; protSw=pH; }
      bool oppBOS=(dir==1 && !naf(protSw) && cl<protSw)||(dir==-1 && !naf(protSw) && cl>protSw);
      if(!bos1 && oppBOS){ bos1=true; indOrig = dir==1?nz(cycH,hi):nz(cycL,lo); }
      if(bos1 && !bos2 && oppBOS && !naf(protSw2) && (dir==1? cl<protSw2 : cl>protSw2)) bos2=true;
      if(bos1 && dir==1)  indExt=naf(indExt)?cl:fmin2(indExt,cl);
      if(bos1 && dir==-1) indExt=naf(indExt)?cl:fmax2(indExt,cl);
      if(bos2 && !naf(indOrig)){
         if(dir==1 && cl>indOrig) indBrk=true;
         if(dir==-1 && cl<indOrig) indBrk=true;
      }

      double convScore=fmin2(MathAbs(csm[j])/fmax2(A*convM,1e-10)*50.0,100.0);
      double expScore =fmin2(eff/fmax2(effT,1e-10)*50.0 + disp/fmax2(dispT,1e-10)*50.0,100.0);
      double absScore =(eff<effT*0.7 && MathAbs(vel[j])<MathAbs(velP)*0.6)?60.0+convScore*0.4:convScore*0.3;
      bool momExpStrong=eff>effT*0.75 && (dir==1?vel[j]>0:vel[j]<0);
      bool momDecaying =dir==1?bullDec:bearDec;
      bool momCounter  =dir==1?bearImp:bullImp;
      bool momExhaust  =eff<effT*0.65 && absScore>40.0;
      bool physConvexDevel=convScore>35.0;
      bool physTransfer   =convScore>48.0 || absScore>40.0;
      bool physCapacityLow=absScore>45.0 || eff<effT*0.6;

      //--- v60 wave geometry + compression / recursion / dominance ---
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
      //--- v60 single-latch 14-phase state machine ---
      if(reset) phaseState=0;
      if(dir!=0 && !reset){
         if(phaseState==0 && expanding) phaseState=1;
         if(phaseState==1 && !atExtreme && momDecaying && physConvexDevel) phaseState=2;
         if(phaseState==2 && !atExtreme && momCounter && physTransfer) phaseState=3;
         if(phaseState==3 && !atExtreme && (bos1||bos2||indBrk) && physTransfer) phaseState=4;
         if(phaseState>=1 && phaseState<=7 && atExtreme && extended) phaseState=5;
         if(phaseState==5 && !atExtreme && (recBrk>=1||momExhaust)) phaseState=7;
         if(phaseState==7 && transferDone) phaseState=8;
         if(phaseState==8 && atFlip) phaseState=9;
         if(phaseState==9 && ((dir==1&&bullImp)||(dir==-1&&bearImp))) phaseState=10;
         if(phaseState==10 && (oppBOS||physCapacityLow)) phaseState=11;
         if(phaseState==11 && ((dir==1&&lo<fbv)||(dir==-1&&hi>ftv))) phaseState=12;
         if(phaseState==12 && ((dir==1&&bullCH)||(dir==-1&&bearCH))) phaseState=13;
      }
      //--- map v60 code -> Letra canonical code so Letra's combiner is unchanged ---
      //  v60: 7 Transition->Absorption, 9 HTF Flip->Retr Pre-Cvx, 10 Induction->Retr Induction,
      //       11 Liquidation/12 Terminal->Retr Liquidity, 13/14 Return->Demand/Supply Return.
      int v60c=phaseState;
      if(v60c==5 && dir==-1) v60c=6;
      if(v60c==13 && dir==-1) v60c=14;
      int phase = (v60c>=1&&v60c<=6)?v60c : v60c==7?7 : v60c==8?8 : v60c==9?9 : v60c==10?10 : (v60c==11||v60c==12)?11 : v60c==13?12 : v60c==14?13 : 0;
      double wp = phaseState==0?5.0:phaseState==1?15.0:phaseState==2?25.0:phaseState==3?33.0:phaseState==4?42.0:phaseState==5?55.0:phaseState==7?65.0:phaseState==8?75.0:phaseState==9?85.0:phaseState==10?90.0:phaseState==11?94.0:phaseState==12?97.0:100.0;
      double cm = fmin2(convScore,100.0);
      double mf = fmin2(fmax2(expScore,fmax2(absScore,convScore))*0.70 + (dir!=0?30.0:0.0),100.0);
      double frzS=fmin2((eLong||eShort?50.0:0.0)+expScore*0.30+convScore*0.20,100.0);
      int dirLabel = !naf(inv)?(cl>inv?1:(cl<inv?-1:dir)):dir;

      O.dir[j]=dirLabel; O.ph[j]=phase; O.sh[j]=curSH; O.sl[j]=curSL;
      O.psh[j]=prSH; O.psl[j]=prSL; O.bos[j]=bosOut; O.ch[j]=chOut;
      O.p4h[j]=p4h; O.p4l[j]=p4l; O.inv[j]=inv; O.tgt[j]=tgt;
      O.ft[j]=ftv; O.fb[j]=fbv; O.fs[j]=frzS; O.wp[j]=wp; O.cm[j]=cm; O.mf[j]=mf;
   }
}


//==================================================================
// TIME MAPPING — project an HTF series onto a chart-bar time
// Returns index of the latest HTF bar with open-time <= ct.
//==================================================================
int MapIdx(const datetime &times[], const int n, const datetime ct)
{
   if(n<=0) return(-1);
   if(times[0]>ct) return(-1);
   int lo=0, hi=n-1, res=0;
   while(lo<=hi){ int mid=(lo+hi)>>1; if(times[mid]<=ct){ res=mid; lo=mid+1; } else hi=mid-1; }
   return(res);
}
double MapVal(const datetime &times[], const double &vals[], const int n, const datetime ct)
{
   int k=MapIdx(times,n,ct); return(k<0?NA:vals[k]);
}

//==================================================================
// PHYSICS ENGINE (f_phys) — fixed M5
//==================================================================
struct PhysOut
{
   datetime t[]; int n;
   double atr[],vel[],acc[],cvx[],csm[],eff[],disp[];
   int bCS[],rCS[],bImp[],rImp[],bDec[],rDec[],bMic[],rMic[];
   int vd70[],vd50[],vd85[],vd553[]; double mom[]; int accDec[];
};

void ComputePhys(const ENUM_TIMEFRAMES tfReq, const int bars,
                 const int atrL, const int effL, const double effT,
                 const double dispT, const double convM, PhysOut &P)
{
   ENUM_TIMEFRAMES tf=SafeTF(tfReq);
   TFData d; if(!LoadTF(tf,bars,d) || d.n<effL+5){ P.n=0; return; }
   int n=d.n; P.n=n;
   double diff[]; ArrayResize(diff,n); diff[0]=0; for(int j=1;j<n;j++) diff[j]=d.c[j]-d.c[j-1];
   double vel[]; EMAarr(diff,vel,3);
   double acc[]; ArrayResize(acc,n); acc[0]=0; for(int j=1;j<n;j++) acc[j]=vel[j]-vel[j-1];
   double cvx[]; ArrayResize(cvx,n); cvx[0]=0; for(int j=1;j<n;j++) cvx[j]=acc[j]-acc[j-1];
   double csm[]; EMAarr(cvx,csm,3);
   double atr[]; ATRarr(d.h,d.l,d.c,atr,atrL);

   ArrayResize(P.t,n);
   ArrayResize(P.atr,n);ArrayResize(P.vel,n);ArrayResize(P.acc,n);ArrayResize(P.cvx,n);
   ArrayResize(P.csm,n);ArrayResize(P.eff,n);ArrayResize(P.disp,n);ArrayResize(P.mom,n);
   ArrayResize(P.bCS,n);ArrayResize(P.rCS,n);ArrayResize(P.bImp,n);ArrayResize(P.rImp,n);
   ArrayResize(P.bDec,n);ArrayResize(P.rDec,n);ArrayResize(P.bMic,n);ArrayResize(P.rMic,n);
   ArrayResize(P.vd70,n);ArrayResize(P.vd50,n);ArrayResize(P.vd85,n);ArrayResize(P.vd553,n);ArrayResize(P.accDec,n);

   for(int j=0;j<n;j++){
      double cl=d.c[j],op=d.o[j],hi=d.h[j],lo=d.l[j],A=atr[j];
      double velP=(j>0)?vel[j-1]:0, accP=(j>0)?acc[j-1]:0;
      double csmP=(j>0)?csm[j-1]:0, vel3=(j>2)?vel[j-3]:0;
      double mv=(j>=effL)?MathAbs(cl-d.c[j-effL]):0.0;
      double ps=SumAbsDiff(d.c,j,effL);
      double eff=(ps>0)?mv/ps:0.0;
      double disp=(hi-lo)/fmax2(A,1e-10);
      double cth=A*convM;
      P.t[j]=d.t[j]; P.atr[j]=A; P.vel[j]=vel[j]; P.acc[j]=acc[j]; P.cvx[j]=cvx[j];
      P.csm[j]=csm[j]; P.eff[j]=eff; P.disp[j]=disp; P.mom[j]=vel[j]-velP;
      P.bCS[j]=(csm[j]>cth && csmP<=cth)?1:0;
      P.rCS[j]=(csm[j]<-cth && csmP>=-cth)?1:0;
      P.bImp[j]=(eff>effT && vel[j]>velP && acc[j]>0 && cl>op && disp>dispT)?1:0;
      P.rImp[j]=(eff>effT && vel[j]<velP && acc[j]<0 && cl<op && disp>dispT)?1:0;
      P.bDec[j]=(MathAbs(acc[j])<MathAbs(accP)*0.8 && vel[j]>0)?1:0;
      P.rDec[j]=(MathAbs(acc[j])<MathAbs(accP)*0.8 && vel[j]<0)?1:0;
      P.bMic[j]=(eff>effT*0.80 && vel[j]>velP && acc[j]>0 && cl>op && disp>dispT*0.50)?1:0;
      P.rMic[j]=(eff>effT*0.80 && vel[j]<velP && acc[j]<0 && cl<op && disp>dispT*0.50)?1:0;
      P.vd70[j]=(MathAbs(vel[j])<MathAbs(velP)*0.7)?1:0;
      P.vd50[j]=(MathAbs(vel[j])<MathAbs(velP)*0.5)?1:0;
      P.vd85[j]=(MathAbs(vel[j])<MathAbs(velP)*0.85)?1:0;
      P.vd553[j]=(MathAbs(vel[j])<MathAbs(vel3)*0.55)?1:0;
      P.accDec[j]=(MathAbs(acc[j])<MathAbs(accP))?1:0;
   }
}

//==================================================================
// HTF BELIEF ENGINE (f_htfBeliefs)
//==================================================================
struct BeliefOut { datetime t[]; int n; int dir[]; double exp[],dec[],curv[],ab[],liq[]; };

void ComputeBelief(const ENUM_TIMEFRAMES tfReq, const int bars, const int atrL,
                   const double effT, const double dispT, const double convM,
                   const int obLook, BeliefOut &B)
{
   ENUM_TIMEFRAMES tf=SafeTF(tfReq);
   TFData d; if(!LoadTF(tf,bars,d) || d.n<obLook+5){ B.n=0; return; }
   int n=d.n; B.n=n;
   double diff[]; ArrayResize(diff,n); diff[0]=0; for(int j=1;j<n;j++) diff[j]=d.c[j]-d.c[j-1];
   double vel[]; EMAarr(diff,vel,3);
   double acc[]; ArrayResize(acc,n); acc[0]=0; for(int j=1;j<n;j++) acc[j]=vel[j]-vel[j-1];
   double cnv[]; ArrayResize(cnv,n); cnv[0]=0; for(int j=1;j<n;j++) cnv[j]=acc[j]-acc[j-1];
   double csm[]; EMAarr(cnv,csm,3);
   double atr[]; ATRarr(d.h,d.l,d.c,atr,atrL);
   ArrayResize(B.t,n);ArrayResize(B.dir,n);ArrayResize(B.exp,n);ArrayResize(B.dec,n);
   ArrayResize(B.curv,n);ArrayResize(B.ab,n);ArrayResize(B.liq,n);
   for(int j=0;j<n;j++){
      double cl=d.c[j],op=d.o[j],hi=d.h[j],lo=d.l[j],A=atr[j];
      double velP=(j>0)?vel[j-1]:0, accP=(j>0)?acc[j-1]:0;
      double convTh=A*convM;
      double move=(j>=obLook)?MathAbs(cl-d.c[j-obLook]):0.0;
      double pathSum=SumAbsDiff(d.c,j,obLook);
      double eff=(pathSum>0)?move/pathSum:0.0;
      double disp=(hi-lo)/fmax2(A,1e-10);
      double expScore=fmin2(eff/fmax2(effT,1e-10)*50.0+disp/fmax2(dispT,1e-10)*50.0,100.0);
      double decayScr=(MathAbs(acc[j])<MathAbs(accP)*0.8)?fmin2(MathAbs(cnv[j])/fmax2(convTh,1e-10)*50.0,100.0):0.0;
      double curvScr=fmin2(MathAbs(csm[j])/fmax2(convTh,1e-10)*50.0,100.0);
      double abScr=(eff<effT*0.7 && MathAbs(vel[j])<MathAbs(velP)*0.6)?60.0+curvScr*0.4:curvScr*0.3;
      double liqScr=(MathAbs(csm[j])>convTh*1.5 && disp>dispT)?fmin2(curvScr*1.2,100.0):curvScr*0.5;
      bool bullImp=eff>effT && vel[j]>velP && acc[j]>0 && cl>op && disp>dispT;
      bool bearImp=eff>effT && vel[j]<velP && acc[j]<0 && cl<op && disp>dispT;
      B.t[j]=d.t[j]; B.dir[j]=bullImp?1:(bearImp?-1:0);
      B.exp[j]=expScore; B.dec[j]=decayScr; B.curv[j]=curvScr; B.ab[j]=abScr; B.liq[j]=liqScr;
   }
}

//==================================================================
// M1 PHYSICS ENGINE (f_m1Physics) — fixed "1"
//==================================================================
struct M1Out { datetime t[]; int n; int expWeak[],convEmer[],indEmer[],liqEmer[],absEmer[]; };

void ComputeM1(const int bars, const int atrL, const int effL, const double effT,
               const double dispT, const double convM, M1Out &M)
{
   ENUM_TIMEFRAMES tf=SafeTF(PERIOD_M1);
   TFData d; if(!LoadTF(tf,bars,d) || d.n<effL+5){ M.n=0; return; }
   int n=d.n; M.n=n;
   double diff[]; ArrayResize(diff,n); diff[0]=0; for(int j=1;j<n;j++) diff[j]=d.c[j]-d.c[j-1];
   double v[]; EMAarr(diff,v,3);
   double a[]; ArrayResize(a,n); a[0]=0; for(int j=1;j<n;j++) a[j]=v[j]-v[j-1];
   double cv[]; ArrayResize(cv,n); cv[0]=0; for(int j=1;j<n;j++) cv[j]=a[j]-a[j-1];
   double atr[]; ATRarr(d.h,d.l,d.c,atr,atrL);
   ArrayResize(M.t,n);ArrayResize(M.expWeak,n);ArrayResize(M.convEmer,n);
   ArrayResize(M.indEmer,n);ArrayResize(M.liqEmer,n);ArrayResize(M.absEmer,n);
   for(int j=0;j<n;j++){
      double cl=d.c[j],hi=d.h[j],lo=d.l[j],A=atr[j];
      double aP=(j>0)?a[j-1]:0;
      double m=(j>=effL)?MathAbs(cl-d.c[j-effL]):0.0;
      double ps=SumAbsDiff(d.c,j,effL);
      double e=(ps>0)?m/ps:0.0;
      double dd=(hi-lo)/fmax2(A,1e-10);
      bool mD=MathAbs(a[j])<MathAbs(aP)*0.8;
      M.t[j]=d.t[j];
      M.expWeak[j]=(e<effT*0.7 && mD)?1:0;
      M.convEmer[j]=(MathAbs(cv[j])>A*convM*1.5 && mD)?1:0;
      M.indEmer[j]=(e>effT && a[j]<0 && v[j]>0)?1:0;
      M.liqEmer[j]=(dd>dispT*1.2 && mD)?1:0;
      M.absEmer[j]=(e<effT*0.5 && dd<dispT*0.6)?1:0;
   }
}

//==================================================================
// FU POOL ENGINE (f_fuPool) — multi-TF recursive FU left-pool magnets
//==================================================================
struct FUPoolOut { datetime t[]; int n; double pool[],mid[],bandHi[],bandLo[],tip[],score[]; int dir[],valid[]; };

void ComputeFUPool(const ENUM_TIMEFRAMES tfReq, const int bars, const double wickFrac, FUPoolOut &F)
{
   ENUM_TIMEFRAMES tf=SafeTF(tfReq);
   TFData d; if(!LoadTF(tf,bars,d) || d.n<6){ F.n=0; return; }
   int n=d.n; F.n=n;
   double atr14[]; ATRarr(d.h,d.l,d.c,atr14,14);
   ArrayResize(F.t,n);ArrayResize(F.pool,n);ArrayResize(F.mid,n);ArrayResize(F.bandHi,n);
   ArrayResize(F.bandLo,n);ArrayResize(F.tip,n);ArrayResize(F.score,n);ArrayResize(F.dir,n);ArrayResize(F.valid,n);
   //--- state ---
   double tip=NA,bH=NA,bL=NA,pool=NA; int dir=0; bool valid=false,conf=false;
   for(int j=0;j<n;j++){
      double cl=d.c[j],op=d.o[j],hi=d.h[j],lo=d.l[j];
      double rng=fmax2(hi-lo,1e-10);
      double priorHi=HighestPrior(d.h,j,3);
      double priorLo=LowestPrior(d.l,j,3);
      bool bear=!naf(priorHi) && hi>priorHi && cl<priorHi && (hi-fmax2(op,cl))/rng>=wickFrac;
      bool bull=!naf(priorLo) && lo<priorLo && cl>priorLo && (fmin2(op,cl)-lo)/rng>=wickFrac;
      if(bear){ dir=-1; tip=hi; bH=fmax2(op,cl); bL=fmin2(op,cl); pool=priorHi; valid=true; conf=false; }
      else if(bull){ dir=1; tip=lo; bH=fmax2(op,cl); bL=fmin2(op,cl); pool=priorLo; valid=true; conf=false; }
      if(valid && dir==-1 && !conf && cl<bL) conf=true;
      if(valid && dir==1  && !conf && cl>bH) conf=true;
      double mid=NA,bHi=NA,bLo=NA;
      if(dir==-1 && !naf(tip)){ mid=bH+(tip-bH)*0.50; bHi=bH+(tip-bH)*0.62; bLo=bH+(tip-bH)*0.38; }
      else if(dir==1 && !naf(tip)){ mid=tip+(bL-tip)*0.50; bHi=tip+(bL-tip)*0.62; bLo=tip+(bL-tip)*0.38; }
      double wkAtr=(dir==-1 && !naf(tip))?(tip-bH)/fmax2(atr14[j],1e-10):((dir==1 && !naf(tip))?(bL-tip)/fmax2(atr14[j],1e-10):0.0);
      double score=(conf?30.0:0.0)+fmin2(25.0,wkAtr*15.0)+20.0+(wkAtr>1.0?15.0:0.0)+(wkAtr>1.5?10.0:0.0);
      F.t[j]=d.t[j];
      F.pool[j]=valid?pool:NA; F.mid[j]=mid; F.bandHi[j]=bHi; F.bandLo[j]=bLo;
      F.dir[j]=dir; F.valid[j]=valid?1:0; F.tip[j]=tip; F.score[j]=score;
   }
}

//==================================================================
// HTF DIR (f_htfDir) — V72 MCE single-direction read
//==================================================================
struct DirOut { datetime t[]; int n; int dir[]; };

void ComputeHtfDir(const ENUM_TIMEFRAMES tfReq, const int bars, const int atrL,
                   const double effT, const double dispT, const int obLook, DirOut &R)
{
   ENUM_TIMEFRAMES tf=SafeTF(tfReq);
   TFData d; if(!LoadTF(tf,bars,d) || d.n<obLook+5){ R.n=0; return; }
   int n=d.n; R.n=n;
   double diff[]; ArrayResize(diff,n); diff[0]=0; for(int j=1;j<n;j++) diff[j]=d.c[j]-d.c[j-1];
   double vel[]; EMAarr(diff,vel,3);
   double acc[]; ArrayResize(acc,n); acc[0]=0; for(int j=1;j<n;j++) acc[j]=vel[j]-vel[j-1];
   double atr[]; ATRarr(d.h,d.l,d.c,atr,atrL);
   ArrayResize(R.t,n);ArrayResize(R.dir,n);
   for(int j=0;j<n;j++){
      double cl=d.c[j],op=d.o[j],hi=d.h[j],lo=d.l[j],A=atr[j];
      double velP=(j>0)?vel[j-1]:0;
      double move=(j>=obLook)?MathAbs(cl-d.c[j-obLook]):0.0;
      double pathSum=SumAbsDiff(d.c,j,obLook);
      double eff=(pathSum>0)?move/pathSum:0.0;
      double disp=(hi-lo)/fmax2(A,1e-10);
      bool bullImp=eff>effT && vel[j]>velP && acc[j]>0 && cl>op && disp>dispT;
      bool bearImp=eff>effT && vel[j]<velP && acc[j]<0 && cl<op && disp>dispT;
      R.t[j]=d.t[j]; R.dir[j]=bullImp?1:(bearImp?-1:0);
   }
}


//==================================================================
// PHASE-STRING HELPERS (shared canonical vocabulary)
//==================================================================
string f_phaseStr(const int c)
{
   switch(c){
      case 1:  return("Expansion");
      case 2:  return("Expansion Pre-Convexity");
      case 3:  return("Expansion Induction");
      case 4:  return("Expansion Liquidity");
      case 5:  return("New High");
      case 6:  return("New Low");
      case 7:  return("Absorption");
      case 8:  return("Retracement");
      case 9:  return("Retracement Pre-Convexity");
      case 10: return("Retracement Induction");
      case 11: return("Retracement Liquidity");
      case 12: return("Demand Return");
      case 13: return("Supply Return");
   }
   return("Point 4 Origin");
}
string f_hypFam(const string ph)
{
   if(ph=="Expansion")                 return("EXPANSION");
   if(ph=="Expansion Pre-Convexity")   return("CONVEXITY FORMING");
   if(ph=="Expansion Induction")       return("CONVEXITY FORMING");
   if(ph=="Expansion Liquidity")       return("CONVEXITY FORMING");
   if(ph=="New High")                  return("CREATION FORMING");
   if(ph=="New Low")                   return("CREATION FORMING");
   if(ph=="Absorption")                return("ABSORPTION");
   if(ph=="Demand Return")             return("DEMAND/SUPPLY RETURN");
   if(ph=="Supply Return")             return("DEMAND/SUPPLY RETURN");
   return("RETRACEMENT");
}
string f_famSimple(const int f)
{
   if(f==1) return("Expansion");
   if(f==2) return("Pre-Convexity");
   if(f==4) return("Absorption");
   if(f==5) return("Liquidity");
   if(f==6) return("Absorption");
   return("Expansion");
}
string f_famMicro(const int f)
{
   if(f==2) return("M1 Convexity");
   if(f==4) return("M1 Absorption");
   if(f==5) return("M1 Liquidity");
   return("M1 Expansion");
}
int f_phaseFamilyCode(const int c)
{
   if(c==1) return(1);
   if(c==2 || c==3 || c==4) return(2);
   if(c==5 || c==6) return(3);
   if(c==7) return(4);
   if(c==8 || c==9 || c==10 || c==11) return(5);
   if(c==12 || c==13) return(6);
   return(0);
}
string f_waveDirLabel(const int d){ return(d==1?"Bullish Wave":(d==-1?"Bearish Wave":"Neutral")); }
int f_waveDirByOrigin(const double origin,const double cl,const int fb)
{ return(!naf(origin)?(cl>origin?1:(cl<origin?-1:fb)):fb); }

//==================================================================
// GLOBAL ENGINE INSTANCES (recomputed on each new chart bar)
//==================================================================
SEOut     se1,se3,se5,se15,se60,se240;
PhysOut   phys5;
BeliefOut bel1,bel2;
M1Out     m1o;
FUPoolOut fpW,fpD,fpH4,fpH1,fpM15,fpM5;
DirOut    mdir3,mdir4;

int HTF_BARS = 4000;   // bars to pull per HTF engine (set in OnInit)

//==================================================================
// PER-BAR SIGNAL OUTPUTS (consumed by indicator buffers / EA logic)
//==================================================================
bool   gBarLong=false; bool gBarShort=false; double gBarLongPx=0; double gBarShortPx=0;

//==================================================================
// PERSISTENT CHART-LEVEL STATE  (Pine 'var')
//==================================================================
//--- Sec4 structure ---
double g_lastPivHigh=NA,g_prevPivHigh=NA,g_lastPivLow=NA,g_prevPivLow=NA;
int    g_structBias=0;
double g_prevSwingHigh=NA,g_prevSwingLow=NA,g_currSwingHigh=NA,g_currSwingLow=NA;
//--- Sec5 pivot memory ---
double g_lastPivotPrice=NA,g_prevPivotPrice=NA;
int    g_lastPivotBar=-1,g_prevPivotBar=-1,g_lastPivotDir=0,g_prevPivotDir=0;
//--- Sec8 wave context ---
int    g_direction=0; double g_flipTop=NA,g_flipBot=NA;
int    g_obBirthBar=-1,g_barsInZone=0,g_contBar=-1;
double g_point4OriginHigh=NA,g_point4OriginLow=NA; int g_point4OriginBar=-1;
double g_flipzoneInducPrice=NA,g_flipzoneInducLow=NA,g_flipzoneInducHigh=NA;
double g_inducExpOriginHigh=NA,g_inducExpExtremeLow=NA,g_inducExpOriginLow=NA,g_inducExpExtremeHigh=NA;
double g_inducRetrOriginHigh=NA,g_inducRetrExtremeLow=NA,g_inducRetrOriginLow=NA,g_inducRetrExtremeHigh=NA;
double g_inducZoneLow=NA,g_inducZoneHigh=NA,g_cycleHigh=NA,g_cycleLow=NA;
int    g_waveGeneration=0,g_entryCycle=0; bool g_isRecursiveWave=false; int g_waveDepth=0,g_lastSpawnDir=0; bool g_recursiveComplete=false;
//--- cycle history store ---
double g_cycObTop[4],g_cycObBot[4],g_cycFlipTop[4],g_cycFlipBot[4],g_cycP4High[4],g_cycP4Low[4];
int    g_cycStartBar[4],g_cycDir[4];
//--- Sec9/12 forward-declared smoothed states ---
double g_liqHeat=0.0; bool g_nearFlipzone=false; double g_convexityMaturity=0.0;
double g_waveProgress=30.0,g_waveModelFit=50.0;
double g_expansionBelief=0,g_convexityBelief=0,g_creationBelief=0,g_absorptionBelief=0,g_retracementBelief=0,g_demandReturnBelief=0;
double g_modelConfidence=50.0;
bool   g_inductionEvidence=false,g_preConvEvidence=false,g_closeInside=false;
bool   g_m1AbsorptionEmer=false,g_m1ConvexityEmer=false,g_m1LiquidityEmer=false;
//--- validation ring ---
int    g_predOutcomes[100]; int g_predTotalIdx=0;
string g_lastExpectedPhase="Point 4 Origin",g_lastIE1APhase="Point 4 Origin";
//--- liqg overlay ---
bool   g_liqg_active=false,g_liqg_isRetr=false; int g_liqg_dir=0;
double g_liqg_target=NA,g_liqg_initDist=NA; bool g_liqg_absorbUnlocked=false;
//--- recursive ---
bool   g_recursiveJustFired=false; int g_recursiveFiredBar=-1;
//--- liquidity heatmap arrays ---
double g_liqLevels[],g_liqWeights[]; int g_liqAges[],g_liqTypes[];
//--- exec lock ---
int    g_lastSignalBar=-1,g_lastLongBar=-1,g_lastShortBar=-1; bool g_engineArmed=true;
//--- trade state ---
int    g_tradeDir=0,g_exitFiredBar=-1;
//--- previous-bar series memory ---
double g_prevEnergy=0.0; int g_prevDirection=0,g_prevEntryCycle=0,g_prev_ede_state=0; bool g_prev_LBD=false;
//--- FU blocks ---
double g_fu_top[],g_fu_bot[]; int g_fu_birthBar[],g_fu_dir[]; string g_fu_state[];
//--- FU wick authority ---
double g_fuw_tip=NA,g_fuw_bodyHigh=NA,g_fuw_bodyLow=NA,g_fuw_mid=NA,g_fuw_mid38=NA,g_fuw_mid62=NA;
int    g_fuw_dir=0; double g_fuw_leftPool=NA; int g_fuw_bar=-1; bool g_fuw_valid=false; double g_fuw_strength=NA;
//--- AFE ---
int    g_afe_step=0; double g_afe_origin=NA; int g_afe_originDir=0;
double g_afe_upperFlip=NA,g_afe_lowerFlip=NA; string g_afe_upperFlipRole="-";
double g_afe_activeDest=NA,g_afe_target=NA; bool g_afe_selfReturnDone=false,g_afe_continuation=false;
//--- FRZ arrays ---
double g_frz_top[],g_frz_bot[]; int g_frz_bar[],g_frz_dir[],g_frz_score[];
string g_frz_class[],g_frz_tier[],g_frz_tierF[],g_frz_comp[],g_frz_owner[],g_frz_status[];
int    g_frz_idx[]; int g_frz_totalSpawned=0;
//--- DIE clustering / density ---
int    g_die_clusterCount=0,g_die_clusterStartBar=-1; double g_die_clusterBestScore=0; bool g_die_inCluster=false;
bool   g_die_objMade=false,g_die_absUnlocked=false;
//--- dashboard EMA confidences ---
double g_l1_confidence=50.0,g_l2_confidence=50.0;
//--- wave / delivery registries (V72) ---
int    g_wr_id[],g_wr_parent[],g_wr_root[],g_wr_birth[],g_wr_death[],g_wr_depth[];
string g_wr_spawnPh[],g_wr_deathPh[]; double g_wr_peak[],g_wr_resScore[];
int    g_wr_nextId=1,g_wr_activeId=0,g_wr_activeParent=0,g_wr_activeRoot=0;
int    g_dwr_id[],g_dwr_root[],g_dwr_start[],g_dwr_end[],g_dwr_cycle[]; double g_dwr_energy[]; string g_dwr_res[];
int    g_dwr_nextId=1,g_dwr_activeId=0;

//--- last fully-processed chart bar index (for incremental state) ---
int    g_lastProcessed=-1;
datetime g_lastHTFbuild=0;


//==================================================================
// DISPLAY STATE (written every processed bar; last bar drives render)
//==================================================================
//--- phase / direction ---
string cur_ie1aPhase, cur_currentDisplayPhase, cur_hypFamily;
int    cur_dirM1,cur_dirM3,cur_dirM5,cur_dirM15,cur_dirH1,cur_dirH4;
string cur_l0phase,cur_l1phase,cur_l2phase,cur_l3phase,cur_l4phase;
double cur_phaseConfidence,cur_phaseIntegrity,cur_phaseProgress,cur_ie1aPhaseConf;
double cur_fractalStackScore,cur_fractalCtxScore; int cur_fractalStackDir;
int    cur_liveWaveDir,cur_liveHtfAlign;
//--- liqg ---
bool   cur_liqgActive; string cur_liqgTitle,cur_liqgSub,cur_liqgReadout,cur_liqgArr;
double cur_liqgTarget,cur_liqgDistPct;
//--- physics ---
double cur_atr,cur_velocity,cur_acceleration,cur_efficiency,cur_displacement;
double cur_convSmooth,cur_velocityScore,cur_accelScore,cur_convexityScore,cur_expansionScore;
double cur_obsExp,cur_obsDecay,cur_obsCurv,cur_obsAbs,cur_obsLiq,cur_physicsConsensus,cur_physicsMax,cur_physicsDiff;
string cur_volRegime; double cur_volRatio;
//--- beliefs / proximity / hyp / pred ---
double cur_bExp,cur_bConv,cur_bCreat,cur_bAbs,cur_bRetr,cur_bDR;
double cur_pxExp,cur_pxConv,cur_pxCreat,cur_pxAbs,cur_pxRetr,cur_pxDR;
string cur_primaryHyp; double cur_primaryHypConf;
double cur_hypLE,cur_hypEC,cur_hypCF,cur_hypAA,cur_hypRA,cur_hypDR2;
string cur_expectedNextPhase; double cur_expectedNextProb,cur_predReliability,cur_predAcc10,cur_predAcc25;
double cur_modelConfidence,cur_waveDeviation; bool cur_deviationAlert;
int    cur_m1WarningScore; string cur_m1Warning;
double cur_htfExpBelief,cur_htfConvBelief,cur_htfAbsBelief,cur_htfLiqBelief;
//--- market state / scoring ---
double cur_contProb,cur_finalProb; string cur_grade; color cur_gradeCol;
int    cur_structBias,cur_htfAlign,cur_resonance;
//--- liquidity ---
double cur_liqHeat; string cur_liqZone; bool cur_liqVacuum;
//--- geometry ---
string cur_cycleCapacity,cur_geoCapNarr; double cur_geoCapScore,cur_availableSpace,cur_zonePrecision;
//--- ERF ---
int    cur_edeState; string cur_edeCleaning; double cur_edeDissProg,cur_edeExpEnergy;
string cur_reResolution; double cur_reRecursiveCompletion,cur_reResidual,cur_reRevisit;
string cur_eaeEnergyState,cur_eaePrimaryLabel; double cur_eaePrimaryPrice,cur_eaePrimaryScore,cur_eaeSecondaryPrice;
double cur_erfTradeReadiness,cur_erfConfidence; bool cur_erfEntryGate,cur_erfSuppressRotation;
//--- probability panels ---
double cur_expansionProbability,cur_reversalProbability,cur_tradeReadiness;
//--- directive / edge ---
string cur_directiveStr; color cur_directiveCol; string cur_liveDirective;
double cur_buyProb,cur_sellProb,cur_netEdgeAdjusted,cur_buyScore,cur_sellScore;
//--- live opp / exec ---
double cur_dieEntryScore; string cur_dieFuContrib; bool cur_longSignal,cur_shortSignal; int cur_tradeDir;
//--- cycles ---
int    cur_entryCycle,cur_waveDepth; bool cur_recursiveComplete;
double cur_cyc1,cur_cyc2,cur_cyc3,cur_cyc4; string cur_activeCyclePhase;
//--- dominance / fusion ---
string cur_l0domPhase,cur_l1domPhase,cur_l2domPhase,cur_l3domPhase;
double cur_l0conf,cur_l1conf,cur_l2conf,cur_l3conf;
double cur_l0dom,cur_l1dom,cur_l2dom,cur_l3dom;
string cur_dominantWaveLevel,cur_fusionInterp; double cur_fusionConfidence;
string cur_parentChildRel,cur_childGrandRel;
//--- FRZ display ---
int    cur_frzActive,cur_frzBull,cur_frzBear,cur_frzBest,cur_frzL0,cur_frzL1,cur_frzL2,cur_frzL3;
string cur_frzBestClass,cur_frzBestTier,cur_frzBestComp,cur_frzBestOwner,cur_frzBestStatus;
double cur_frzBestTop,cur_frzBestBot,cur_frzBestMid; int cur_frzBestDir;
//--- FU display ---
bool   cur_anyBullFU,cur_anyBearFU; double cur_fuWinTarget,cur_fuWinBand,cur_fuRecursiveAlign; string cur_fuWinSrc;
double cur_convSeekPx,cur_convSeekSc,cur_convConfidence; string cur_convSeekTf;
//--- V72 ---
string cur_rotState; double cur_rotTransfer,cur_rotControl;
double cur_mceAlign,cur_mceHtfAlign,cur_mceExecAlign; string cur_mceHtfSummary,cur_mceExecSummary; int cur_mceLifecycle;
string cur_neNarrative; double cur_neStrength;
double cur_invActiveStop,cur_invRisk; bool cur_invInvalidated;
double cur_teTp1,cur_teTp2,cur_teTp3,cur_teRR; string cur_teExpectedPath;
string cur_tqeGrade,cur_tqeRisk; double cur_tqeRaw;
string cur_doeBias,cur_doeAction,cur_doeTradeType,cur_doeTrigger; double cur_doeConfidence,cur_doeEntryMid,cur_doeEntryHigh,cur_doeEntryLow;
double cur_oppProgress; string cur_oppState,cur_cmdNarrative;
double cur_tplMainTarget,cur_tplConfidence; string cur_tplSource,cur_tplWinnerClass;
string cur_trcDecision,cur_trcConf,cur_trcWaveChain;
//--- chart-bar rolling helpers ---
double g_atrChart[]; double g_volChart[]; double g_velHist[];


//==================================================================
// FORMAT + CHART-PIVOT HELPERS
//==================================================================
string PXs(const double v){ return(naf(v)?"-":DoubleToString(v,_Digits)); }
string PCTs(const double v){ return(naf(v)?"-":IntegerToString((int)MathRound(v))+"%"); }
string R0(const double v){ return(IntegerToString((int)MathRound(v))); }
int MapValI(const datetime &times[], const int &vals[], const int n, const datetime ct){ int k=MapIdx(times,n,ct); return(k<0?0:vals[k]); }

double ChartPivotHigh(const double &h[], const int i, const int len)
{
   int ctr=i-len; if(ctr-len<0) return(NA);
   double v=h[ctr];
   for(int k=ctr-len;k<=ctr+len;k++){ if(k==ctr) continue; if(h[k]>=v) return(NA); }
   return(v);
}
double ChartPivotLow(const double &l[], const int i, const int len)
{
   int ctr=i-len; if(ctr-len<0) return(NA);
   double v=l[ctr];
   for(int k=ctr-len;k<=ctr+len;k++){ if(k==ctr) continue; if(l[k]<=v) return(NA); }
   return(v);
}
double SMAlastN(const double &arr[], const int n)
{
   int sz=ArraySize(arr); if(sz==0) return(0); int cnt=(sz<n)?sz:n; double s=0;
   for(int k=sz-cnt;k<sz;k++) s+=arr[k]; return(s/cnt);
}

//--- htf bias persistent (Sec3) ---
int g_htfBias1=0,g_htfBias2=0;

//==================================================================
// PROCESS A SINGLE CHART BAR — full faithful pipeline
//==================================================================
void ProcessBar(const int i,const double &o[],const double &h[],const double &l[],
                const double &c[],const datetime &tm[],const double &vol[],
                const int total,const bool isLast)
{
   datetime ct=tm[i];
   double cl=c[i], op=o[i], hi=h[i], lo=l[i];

   //==============================================================
   // MAP HTF STRUCTURE ENGINES (lookahead-off -> last closed bar)
   //==============================================================
   double se1_ph =MapVal(se1.t,se1.ph,se1.n,ct),   se1_inv=MapVal(se1.t,se1.inv,se1.n,ct),   se1_dir=MapVal(se1.t,se1.dir,se1.n,ct),   se1_bos=MapVal(se1.t,se1.bos,se1.n,ct),   se1_ch=MapVal(se1.t,se1.ch,se1.n,ct);
   double se3_ph =MapVal(se3.t,se3.ph,se3.n,ct),   se3_inv=MapVal(se3.t,se3.inv,se3.n,ct),   se3_dir=MapVal(se3.t,se3.dir,se3.n,ct),   se3_bos=MapVal(se3.t,se3.bos,se3.n,ct),   se3_ch=MapVal(se3.t,se3.ch,se3.n,ct),  se3_mf=MapVal(se3.t,se3.mf,se3.n,ct),  se3_wp=MapVal(se3.t,se3.wp,se3.n,ct),  se3_cm=MapVal(se3.t,se3.cm,se3.n,ct);
   double se5_ph =MapVal(se5.t,se5.ph,se5.n,ct),   se5_inv=MapVal(se5.t,se5.inv,se5.n,ct),   se5_dir=MapVal(se5.t,se5.dir,se5.n,ct),   se5_bos=MapVal(se5.t,se5.bos,se5.n,ct),   se5_ch=MapVal(se5.t,se5.ch,se5.n,ct);
   double se5_tgt=MapVal(se5.t,se5.tgt,se5.n,ct),  se5_p4h=MapVal(se5.t,se5.p4h,se5.n,ct),   se5_p4l=MapVal(se5.t,se5.p4l,se5.n,ct),   se5_wp=MapVal(se5.t,se5.wp,se5.n,ct),     se5_cm=MapVal(se5.t,se5.cm,se5.n,ct),  se5_mf=MapVal(se5.t,se5.mf,se5.n,ct);
   double se15_ph=MapVal(se15.t,se15.ph,se15.n,ct),se15_inv=MapVal(se15.t,se15.inv,se15.n,ct),se15_dir=MapVal(se15.t,se15.dir,se15.n,ct),se15_mf=MapVal(se15.t,se15.mf,se15.n,ct),se15_wp=MapVal(se15.t,se15.wp,se15.n,ct);
   double se60_ph=MapVal(se60.t,se60.ph,se60.n,ct),se60_inv=MapVal(se60.t,se60.inv,se60.n,ct),se60_dir=MapVal(se60.t,se60.dir,se60.n,ct),se60_mf=MapVal(se60.t,se60.mf,se60.n,ct),se60_wp=MapVal(se60.t,se60.wp,se60.n,ct);
   double se240_ph=MapVal(se240.t,se240.ph,se240.n,ct),se240_inv=MapVal(se240.t,se240.inv,se240.n,ct),se240_dir=MapVal(se240.t,se240.dir,se240.n,ct);

   string m1_phaseCanon=f_phaseStr((int)nz(se1_ph));
   string l3_phaseCanon=f_phaseStr((int)nz(se3_ph));
   string l0_phaseCanon=f_phaseStr((int)nz(se5_ph));
   string l1_phaseCanon=f_phaseStr((int)nz(se15_ph));
   string l2_phaseCanon=f_phaseStr((int)nz(se60_ph));
   string l4_phaseCanon=f_phaseStr((int)nz(se240_ph));

   int m1_dir=f_waveDirByOrigin(se1_inv,cl,(int)nz(se1_dir));
   int l3_dir=f_waveDirByOrigin(se3_inv,cl,(int)nz(se3_dir));
   int l0_dir=f_waveDirByOrigin(se5_inv,cl,(int)nz(se5_dir));
   int l1_dir=f_waveDirByOrigin(se15_inv,cl,(int)nz(se15_dir));
   int l2_dir=f_waveDirByOrigin(se60_inv,cl,(int)nz(se60_dir));
   int l4_dir=f_waveDirByOrigin(se240_inv,cl,(int)nz(se240_dir));

   int stackBull=(m1_dir==1?1:0)+(l3_dir==1?1:0)+(l0_dir==1?1:0)+(l1_dir==1?1:0)+(l2_dir==1?1:0)+(l4_dir==1?1:0);
   int stackBear=(m1_dir==-1?1:0)+(l3_dir==-1?1:0)+(l0_dir==-1?1:0)+(l1_dir==-1?1:0)+(l2_dir==-1?1:0)+(l4_dir==-1?1:0);
   int fractalStackDir=stackBull>stackBear?1:(stackBear>stackBull?-1:0);
   double fractalStackScore=(double)MathMax(stackBull,stackBear)/6.0*100.0;
   int liveWaveDir=l0_dir;
   int liveHtfAlign=(l2_dir!=0 && l2_dir==l4_dir)?l2_dir:0;
   double fractalCtxScore=fmin2(
        (l4_dir==fractalStackDir&&fractalStackDir!=0?30.0:0.0)+
        (l2_dir==fractalStackDir&&fractalStackDir!=0?26.0:0.0)+
        (l1_dir==fractalStackDir&&fractalStackDir!=0?20.0:0.0)+
        (l0_dir==fractalStackDir&&fractalStackDir!=0?14.0:0.0)+
        (l3_dir==fractalStackDir&&fractalStackDir!=0?6.0:0.0)+
        (m1_dir==fractalStackDir&&fractalStackDir!=0?4.0:0.0),100.0);
   int displayWaveDir_M5=l0_dir;

   //==============================================================
   // PHYSICS (mapped M5) + chart aliases
   //==============================================================
   double atr        =nz(MapVal(phys5.t,phys5.atr,phys5.n,ct),1e-10);
   double velocity   =MapVal(phys5.t,phys5.vel,phys5.n,ct);
   double acceleration=MapVal(phys5.t,phys5.acc,phys5.n,ct);
   double convexity  =MapVal(phys5.t,phys5.cvx,phys5.n,ct);
   double convSmooth =MapVal(phys5.t,phys5.csm,phys5.n,ct);
   double efficiency =MapVal(phys5.t,phys5.eff,phys5.n,ct);
   double displacement=MapVal(phys5.t,phys5.disp,phys5.n,ct);
   bool bullConvShift=MapValI(phys5.t,phys5.bCS,phys5.n,ct)!=0;
   bool bearConvShift=MapValI(phys5.t,phys5.rCS,phys5.n,ct)!=0;
   bool bullImpulse  =MapValI(phys5.t,phys5.bImp,phys5.n,ct)!=0;
   bool bearImpulse  =MapValI(phys5.t,phys5.rImp,phys5.n,ct)!=0;
   bool bullMomDecay =MapValI(phys5.t,phys5.bDec,phys5.n,ct)!=0;
   bool bearMomDecay =MapValI(phys5.t,phys5.rDec,phys5.n,ct)!=0;
   bool bullMicroImpulse=MapValI(phys5.t,phys5.bMic,phys5.n,ct)!=0;
   bool bearMicroImpulse=MapValI(phys5.t,phys5.rMic,phys5.n,ct)!=0;
   bool phys_vd70=MapValI(phys5.t,phys5.vd70,phys5.n,ct)!=0;
   bool phys_vd50=MapValI(phys5.t,phys5.vd50,phys5.n,ct)!=0;
   double phys_mom=MapVal(phys5.t,phys5.mom,phys5.n,ct);
   double convThreshold=atr*convMult;

   //--- vol regime (SMA20 of mapped atr over chart bars) ---
   ArrayResize(g_atrChart,ArraySize(g_atrChart)+1); g_atrChart[ArraySize(g_atrChart)-1]=atr;
   double atrSma=SMAlastN(g_atrChart,20);
   double volRatio=atr/fmax2(atrSma,1e-10);
   string volRegime=volRatio>1.5?"HIGH":(volRatio<0.7?"LOW":"NORMAL");
   double volMult=fmax2(0.5,fmin2(volRatio,2.5));

   //==============================================================
   // HTF BELIEFS (tf1/tf2)  + Sec3 bias
   //==============================================================
   int dir_tf1=MapValI(bel1.t,bel1.dir,bel1.n,ct), dir_tf2=MapValI(bel2.t,bel2.dir,bel2.n,ct);
   double expScr_tf1=nz(MapVal(bel1.t,bel1.exp,bel1.n,ct)), expScr_tf2=nz(MapVal(bel2.t,bel2.exp,bel2.n,ct));
   double decScr_tf1=nz(MapVal(bel1.t,bel1.dec,bel1.n,ct)), decScr_tf2=nz(MapVal(bel2.t,bel2.dec,bel2.n,ct));
   double curvScr_tf1=nz(MapVal(bel1.t,bel1.curv,bel1.n,ct)),curvScr_tf2=nz(MapVal(bel2.t,bel2.curv,bel2.n,ct));
   double abScr_tf1=nz(MapVal(bel1.t,bel1.ab,bel1.n,ct)),    abScr_tf2=nz(MapVal(bel2.t,bel2.ab,bel2.n,ct));
   double liqScr_tf1=nz(MapVal(bel1.t,bel1.liq,bel1.n,ct)),  liqScr_tf2=nz(MapVal(bel2.t,bel2.liq,bel2.n,ct));
   if(expScr_tf1>60 && dir_tf1!=0) g_htfBias1=dir_tf1;
   if(expScr_tf2>60 && dir_tf2!=0) g_htfBias2=dir_tf2;
   if(decScr_tf1>70 && dir_tf1==g_htfBias1) g_htfBias1=0;
   if(decScr_tf2>70 && dir_tf2==g_htfBias2) g_htfBias2=0;
   int htfAlign=(g_htfBias1==1 && g_htfBias2==1)?1:((g_htfBias1==-1 && g_htfBias2==-1)?-1:0);

   //--- m1 physics map ---
   bool m1ExpansionWeak=MapValI(m1o.t,m1o.expWeak,m1o.n,ct)!=0;
   g_m1ConvexityEmer  =MapValI(m1o.t,m1o.convEmer,m1o.n,ct)!=0;
   bool m1InductionEmer=MapValI(m1o.t,m1o.indEmer,m1o.n,ct)!=0;
   g_m1LiquidityEmer  =MapValI(m1o.t,m1o.liqEmer,m1o.n,ct)!=0;
   g_m1AbsorptionEmer =MapValI(m1o.t,m1o.absEmer,m1o.n,ct)!=0;

   //==============================================================
   // SECTION 4 — MARKET STRUCTURE (chart TF)
   //==============================================================
   double structPivH=ChartPivotHigh(h,i,structLen);
   double structPivL=ChartPivotLow (l,i,structLen);
   if(!naf(structPivH)){ g_prevPivHigh=g_lastPivHigh; g_lastPivHigh=structPivH; }
   if(!naf(structPivL)){ g_prevPivLow =g_lastPivLow;  g_lastPivLow =structPivL; }
   bool isHH=!naf(g_lastPivHigh)&&!naf(g_prevPivHigh)&&g_lastPivHigh>g_prevPivHigh;
   bool isLH=!naf(g_lastPivHigh)&&!naf(g_prevPivHigh)&&g_lastPivHigh<g_prevPivHigh;
   bool isHL=!naf(g_lastPivLow )&&!naf(g_prevPivLow )&&g_lastPivLow >g_prevPivLow;
   bool isLL=!naf(g_lastPivLow )&&!naf(g_prevPivLow )&&g_lastPivLow <g_prevPivLow;
   double swPivH=ChartPivotHigh(h,i,pivotLen);
   double swPivL=ChartPivotLow (l,i,pivotLen);
   if(!naf(swPivH)){ g_prevSwingHigh=naf(g_currSwingHigh)?swPivH:g_currSwingHigh; g_currSwingHigh=swPivH; }
   if(!naf(swPivL)){ g_prevSwingLow =naf(g_currSwingLow )?swPivL:g_currSwingLow;  g_currSwingLow =swPivL; }
   bool bullBOS=!naf(g_prevSwingHigh)&&cl>g_prevSwingHigh;
   bool bearBOS=!naf(g_prevSwingLow )&&cl<g_prevSwingLow;
   bool bullCHoCH=!naf(g_prevSwingHigh)&&cl>g_prevSwingHigh+atr*chochBufferATR;
   bool bearCHoCH=!naf(g_prevSwingLow )&&cl<g_prevSwingLow -atr*chochBufferATR;
   if(useStrictStructure){
      if(isHH&&isHL) g_structBias=1;
      if(isLH&&isLL) g_structBias=-1;
   } else {
      if(bullBOS) g_structBias=1;
      if(bearBOS) g_structBias=-1;
   }
   int structBias=g_structBias;
   bool structLongOK =(!requireStruct)||(useStrictStructure&&structBias==1&&isHH)||(!useStrictStructure&&structBias==1);
   bool structShortOK=(!requireStruct)||(useStrictStructure&&structBias==-1&&isLL)||(!useStrictStructure&&structBias==-1);

   //==============================================================
   // SECTION 5 — PIVOT MEMORY (chart, pivotLen)
   //==============================================================
   double pivH=swPivH, pivL=swPivL;
   double pivotEventPrice=NA; int pivotEventBar=-1,pivotEventDir=0;
   if(!naf(pivH)){ pivotEventPrice=pivH; pivotEventBar=i-pivotLen; pivotEventDir=1; }
   else if(!naf(pivL)){ pivotEventPrice=pivL; pivotEventBar=i-pivotLen; pivotEventDir=-1; }
   if(pivotEventDir!=0){
      g_prevPivotPrice=g_lastPivotPrice; g_prevPivotBar=g_lastPivotBar; g_prevPivotDir=g_lastPivotDir;
      g_lastPivotPrice=pivotEventPrice; g_lastPivotBar=pivotEventBar; g_lastPivotDir=pivotEventDir;
   }

   //==============================================================
   // SECTION 6 — IMPULSE
   //==============================================================
   bool eliteShortImpulse=!naf(pivL)&&g_prevPivotDir==1 &&(g_prevPivotPrice-pivL)>atr*impulseAtrMult;
   bool eliteLongImpulse =!naf(pivH)&&g_prevPivotDir==-1&&(pivH-g_prevPivotPrice)>atr*impulseAtrMult;

   //==============================================================
   // PHYSICS OBSERVATION LAYER (Sec9 block)
   //==============================================================
   double velocityScore    =fmin2(MathAbs(velocity)    /fmax2(atr*0.1,1e-10)*50.0,100.0);
   double accelerationScore =fmin2(MathAbs(acceleration)/fmax2(atr*0.05,1e-10)*50.0,100.0);
   double convexityScore   =fmin2(MathAbs(convSmooth)  /fmax2(atr*convMult,1e-10)*25.0,100.0);
   double expansionScore   =fmin2(displacement/fmax2(dispThresh,1e-10)*50.0,100.0);
   double obs_ExpansionScore=fmin2(
        (efficiency>effThresh?efficiency*60.0:efficiency*30.0)+
        (displacement>dispThresh?(displacement/fmax2(dispThresh,1e-10)-1.0)*20.0:0.0)+
        ((velocity>0&&acceleration>0)||(velocity<0&&acceleration<0)?velocityScore*0.2:0.0),100.0);
   double obs_DecayScore=fmin2((bullMomDecay||bearMomDecay?40.0:0.0)+(convexityScore>30?convexityScore*0.5:0.0)+(phys_vd70?30.0:0.0),100.0);
   double obs_CurvatureScore=convexityScore;
   double obs_AbsorptionScore=fmin2(
        (efficiency<effThresh*0.7?(1.0-efficiency/fmax2(effThresh,1e-10))*50.0:0.0)+
        (phys_vd50?30.0:0.0)+(displacement<dispThresh*0.5?20.0:0.0),100.0);
   double obs_LiquidityScore=fmin2(obs_DecayScore*0.4+obs_CurvatureScore*0.4+
        (displacement>dispThresh*1.2&&(bullMomDecay||bearMomDecay)?20.0:0.0),100.0);
   double physicsMax =fmax2(obs_ExpansionScore,fmax2(obs_DecayScore,fmax2(obs_AbsorptionScore,obs_LiquidityScore)));
   double physicsMin =fmin2(obs_ExpansionScore,fmin2(obs_DecayScore,fmin2(obs_AbsorptionScore,obs_LiquidityScore)));
   double physicsDiff=physicsMax-physicsMin;
   double physicsConsensus=fmax2(0.0,100.0-physicsDiff);

   //==============================================================
   // ENGINE 1A  (lifecycle sourced from M5 fixed engine)
   //==============================================================
   string ie1a_currentPhase=l0_phaseCanon;
   double ie1a_phaseConfidence=fmax2(20.0,fmin2(100.0,fractalCtxScore*0.50+nz(se5_mf)*0.30+nz(se5_wp)*0.20));
   string ie1a_hypFamily=f_hypFam(ie1a_currentPhase);
   bool ie1a_isExpSide=(ie1a_currentPhase=="Expansion"||ie1a_currentPhase=="Expansion Pre-Convexity"||
        ie1a_currentPhase=="Expansion Induction"||ie1a_currentPhase=="Expansion Liquidity"||
        ie1a_currentPhase=="New High"||ie1a_currentPhase=="New Low");

   //==============================================================
   // ENERGY RESOLUTION FRAMEWORK (uses PREVIOUS-bar wave state)
   //==============================================================
   int direction=g_direction; // previous-bar direction (spawn runs later)
   int ede_state=(l0_phaseCanon=="Point 4 Origin"||l0_phaseCanon=="Expansion")?1:
        (l0_phaseCanon=="Expansion Pre-Convexity")?2:(l0_phaseCanon=="Expansion Induction")?3:
        (l0_phaseCanon=="Expansion Liquidity")?4:(l0_phaseCanon=="New High"||l0_phaseCanon=="New Low")?5:6;
   string ede_cleaningState=(ede_state==1)?"Accumulating":(ede_state==2)?"Cleaning - Initial Release":
        (ede_state==3)?"Cleaning - Secondary Release":(ede_state==4)?"Cleaning - Purge":(ede_state==5)?"Delivering":"Resolving";
   double ede_expansionEnergy=fmin2(obs_ExpansionScore*0.50+(bullImpulse||bearImpulse?30.0:0.0)+(efficiency*20.0),100.0);
   double ede_dissipatedEnergy=fmin2((ede_state>=2?obs_DecayScore*0.40:0.0)+(ede_state>=3?obs_CurvatureScore*0.30:0.0)+(ede_state>=4?obs_LiquidityScore*0.30:0.0),100.0);
   double ede_dissipationProgress=fmin2((ede_state>=2?25.0:0.0)+(ede_state>=3?25.0:0.0)+(ede_state>=4?25.0:0.0)+(ede_state>=5?25.0:0.0),100.0);
   bool ede_liquidationBecomingDirectional=(ede_state==4&&(bullImpulse||bearImpulse)&&efficiency>effThresh*0.8);
   double ede_deliverySpaceScore=fmin2(fmax2(0.0,100.0-g_convexityMaturity),100.0);
   bool ede_messyPriceIsDissipation=(ede_state>=2&&ede_state<=4)&&obs_DecayScore>30.0&&efficiency<effThresh*0.9&&!(bullImpulse||bearImpulse);
   int re_expectedCycles=MathMax(1,MathMin(g_waveDepth+2,4));
   int re_completedCycles=MathMax(0,MathMin(g_entryCycle,re_expectedCycles));
   double re_recursiveCompletionScore=re_expectedCycles>0?fmin2((double)re_completedCycles/(double)re_expectedCycles*100.0,100.0):0.0;
   double re_residualEnergy=fmax2(0.0,ede_expansionEnergy-ede_dissipatedEnergy);
   bool re_objectiveReached=ede_state>=5;
   bool re_fullDissipation=ede_dissipationProgress>=75.0;
   double re_dissipationProgress=ede_dissipationProgress;
   bool re_absorbedAndReturned=(ie1a_currentPhase=="Demand Return"||ie1a_currentPhase=="Supply Return")&&g_recursiveComplete;
   string re_resolutionState=(re_absorbedAndReturned&&re_fullDissipation&&re_recursiveCompletionScore>=75.0)?"RESOLVED":
        (re_objectiveReached&&re_dissipationProgress>=50.0)?"PARTIALLY RESOLVED":"UNRESOLVED";
   double re_residualEnergyScore=fmin2(re_residualEnergy,100.0);
   bool re_nodeOpen=re_resolutionState=="UNRESOLVED"||re_resolutionState=="PARTIALLY RESOLVED";
   double re_revisitProbability=re_resolutionState=="UNRESOLVED"?fmin2(re_residualEnergyScore*0.90,95.0):
        re_resolutionState=="PARTIALLY RESOLVED"?fmin2(re_residualEnergyScore*0.60,75.0):fmin2(re_residualEnergyScore*0.20,25.0);
   double eae_primaryAttractorPrice=direction==0?NA:
        re_resolutionState=="UNRESOLVED"?(direction==1?nz(g_flipBot,cl-atr*2.0):nz(g_flipTop,cl+atr*2.0)):
        re_resolutionState=="PARTIALLY RESOLVED"?(direction==1?nz(g_point4OriginLow,cl-atr):nz(g_point4OriginHigh,cl+atr)):NA;
   double eae_secondaryAttractorPrice=(direction!=0&&re_resolutionState=="UNRESOLVED"&&!naf(g_inducZoneLow)&&!naf(g_inducZoneHigh))?
        (direction==1?g_inducZoneLow:g_inducZoneHigh):NA;
   double eae_primaryAttractorScore=fmin2(re_residualEnergyScore*0.40+
        (re_resolutionState=="UNRESOLVED"?30.0:re_resolutionState=="PARTIALLY RESOLVED"?20.0:5.0)+
        (!naf(eae_primaryAttractorPrice)?fmax2(0.0,30.0-MathAbs(cl-eae_primaryAttractorPrice)/fmax2(atr,1e-10)*5.0):0.0),100.0);
   double eae_secondaryAttractorScore=fmin2(re_residualEnergyScore*0.25+
        (re_resolutionState=="PARTIALLY RESOLVED"?20.0:10.0)+
        (!naf(eae_secondaryAttractorPrice)?fmax2(0.0,20.0-MathAbs(cl-eae_secondaryAttractorPrice)/fmax2(atr,1e-10)*4.0):0.0),100.0);
   string eae_primaryAttractorLabel=re_resolutionState=="UNRESOLVED"?"Flip Zone (High Residual)":
        re_resolutionState=="PARTIALLY RESOLVED"?"Origin Zone (Partial)":"No Active Attractor";
   string eae_energyState=(ede_state==1)?"Accumulating":(ede_state>=2&&ede_state<=4)?"Cleaning":
        (ede_state==5)?"Delivering":(re_resolutionState=="RESOLVED")?"Exhausted":"Resolving";
   bool erf_activeDissipation=ede_messyPriceIsDissipation;
   bool erf_suppressRotation=erf_activeDissipation&&ede_state>=2&&ede_state<=4;
   double erf_confidence=fmin2((eae_energyState!="Accumulating"?ie1a_phaseConfidence*0.40:20.0)+
        (re_resolutionState=="RESOLVED"?30.0:re_resolutionState=="PARTIALLY RESOLVED"?20.0:10.0)+(eae_primaryAttractorScore*0.30),100.0);
   double erf_dissipationConfidence=fmin2((ede_messyPriceIsDissipation?50.0:0.0)+(ede_dissipationProgress*0.50),100.0);
   double erf_tradeReadiness=fmin2((re_resolutionState=="RESOLVED"?40.0:re_resolutionState=="PARTIALLY RESOLVED"?25.0:10.0)+
        re_recursiveCompletionScore*erfReadyResW+(100.0-re_residualEnergyScore)*erfReadyResidW+erf_confidence*erfReadyConfW,100.0);
   bool erf_entryGate=(!erfGateEnabled)||erf_tradeReadiness>=erfEntryThreshold;


   //==============================================================
   // SECTION 10 — LIQUIDITY HEATMAP
   //==============================================================
   double _swH=nz(HighestN(h,i,liqSweepLookback),hi);
   double _swL=nz(LowestN (l,i,liqSweepLookback),lo);
   bool liqSweepBull=!naf(g_flipTop)&&_swH>g_flipTop;
   bool liqSweepBear=!naf(g_flipBot)&&_swL<g_flipBot;
   ArrayResize(g_volChart,ArraySize(g_volChart)+1); g_volChart[ArraySize(g_volChart)-1]=vol[i];
   double volAvg=SMAlastN(g_volChart,20);
   double normVol=(volAvg>0 && i-pivotLen>=0)?vol[i-pivotLen]/volAvg:1.0;
   if(!naf(pivH)||!naf(pivL)){
      double lvl=!naf(pivH)?pivH:pivL; int lType=!naf(pivH)?1:-1;
      double swRng=(i-pivotLen>=0)?(h[i-pivotLen]-l[i-pivotLen])/fmax2(atr,1e-10):0.0;
      double wt=normVol*swRng;
      int s=ArraySize(g_liqLevels);
      ArrayResize(g_liqLevels,s+1); ArrayResize(g_liqWeights,s+1); ArrayResize(g_liqAges,s+1); ArrayResize(g_liqTypes,s+1);
      g_liqLevels[s]=lvl; g_liqWeights[s]=wt; g_liqAges[s]=i-pivotLen; g_liqTypes[s]=lType;
   }
   if(ArraySize(g_liqLevels)>150){ ArrayRemove(g_liqLevels,0,1); ArrayRemove(g_liqWeights,0,1); ArrayRemove(g_liqAges,0,1); ArrayRemove(g_liqTypes,0,1); }
   double wDensity=0,wDensityAbove=0,wDensityBelow=0;
   double liqRadiusP=atr*liqRadius, liqRadiusWide=atr*liqRadius*3.0;
   int lsz=ArraySize(g_liqLevels);
   for(int q=0;q<lsz;q++){
      double lvl=g_liqLevels[q], wt=g_liqWeights[q]; int age=i-g_liqAges[q];
      double dcy=MathPow(liqAgDecay,age); double dist=MathAbs(cl-lvl);
      if(dist<liqRadiusP) wDensity+=wt*dcy;
      if(dist<liqRadiusWide){ if(lvl>cl) wDensityAbove+=wt*dcy*(1.0-dist/liqRadiusWide); else wDensityBelow+=wt*dcy*(1.0-dist/liqRadiusWide); }
   }
   double liqHeatRaw=fmin2((wDensityAbove+wDensityBelow)/2.0,5.0)/5.0*100.0;
   g_liqHeat=clamp(liqHeatRaw,0.0,100.0);
   double liqHeat=g_liqHeat;
   string liqZone=liqHeat<30?"Open space":liqHeat<70?"Active":"Congested";
   bool liqVacuum=wDensity<0.5;
   bool liqSweepOK=(!requireLiqSweep)||(direction==1&&(liqSweepBull||liqVacuum))||(direction==-1&&(liqSweepBear||liqVacuum));

   //==============================================================
   // SECTION 11 — GEOMETRY
   //==============================================================
   int obAge=(g_obBirthBar>=0)?i-g_obBirthBar:0;
   bool obFresh=obAge<=obMaxBars;
   double obFreshness=(g_obBirthBar>=0)?fmax2(0.0,1.0-(double)obAge/(double)obMaxBars):0.0;
   double originToExtreme=NA;
   if(!naf(g_point4OriginHigh)&&!naf(g_point4OriginLow)){
      double orig=direction==1?g_point4OriginLow:g_point4OriginHigh;
      double extr=direction==1?nz(g_cycleHigh,orig):nz(g_cycleLow,orig);
      originToExtreme=MathAbs(extr-orig);
   }
   double flipzoneWidth=(!naf(g_flipTop)&&!naf(g_flipBot))?g_flipTop-g_flipBot:NA;
   double remainingRoom=NA;
   if(!naf(g_flipTop)&&!naf(g_flipBot)){ double fzMid=(g_flipTop+g_flipBot)/2.0; remainingRoom=fmin2(MathAbs(cl-fzMid)/fmax2(atr*4.0,1e-10)*100.0,100.0); }
   double availableSpace=remainingRoom;
   string cycleCapacity=naf(availableSpace)?"-":availableSpace>=60?"ROOM: HIGH":availableSpace>=30?"ROOM: MID":"ROOM: LOW";
   bool geoFullConvexityPossible=!naf(originToExtreme)&&!naf(flipzoneWidth)&&originToExtreme>atr*6.0&&flipzoneWidth<atr*3.0;
   bool geoPartialConvexityPossible=!naf(originToExtreme)&&originToExtreme>atr*3.0&&originToExtreme<=atr*6.0;
   bool geoAbsorptionOnly=!naf(originToExtreme)&&originToExtreme<=atr*3.0;
   double zonePrecision=!naf(flipzoneWidth)?fmax2(100.0-fmin2((flipzoneWidth/fmax2(atr*0.5,1e-10))*50.0,100.0),0.0):0.0;

   //==============================================================
   // SECTION 12 — WAVE INTELLIGENCE
   //==============================================================
   double ref_effNorm =fmin2(efficiency,1.0);
   double ref_dispNorm=fmin2(displacement/fmax2(dispThresh*2.0,1e-10),1.0);
   double ref_velNorm =fmin2(MathAbs(velocity)/fmax2(atr*0.15,1e-10),1.0);
   double ref_curvNorm=fmin2(MathAbs(convSmooth)/fmax2(atr*convMult*2.0,1e-10),1.0);
   double sim_Expansion   =f_idealSim(ref_effNorm,ref_dispNorm,ref_velNorm,ref_curvNorm,0.85,0.80,0.80,0.10);
   double sim_PreConv     =f_idealSim(ref_effNorm,ref_dispNorm,ref_velNorm,ref_curvNorm,0.60,0.55,0.40,0.50);
   double sim_Induction   =f_idealSim(ref_effNorm,ref_dispNorm,ref_velNorm,ref_curvNorm,0.65,0.60,0.30,0.60);
   double sim_Liquidity   =f_idealSim(ref_effNorm,ref_dispNorm,ref_velNorm,ref_curvNorm,0.45,0.85,0.15,0.80);
   double sim_Creation    =f_idealSim(ref_effNorm,ref_dispNorm,ref_velNorm,ref_curvNorm,0.30,0.70,0.05,0.90);
   double sim_Absorption  =f_idealSim(ref_effNorm,ref_dispNorm,ref_velNorm,ref_curvNorm,0.20,0.25,0.10,0.40);
   double sim_Retracement =f_idealSim(ref_effNorm,ref_dispNorm,ref_velNorm,ref_curvNorm,0.70,0.65,0.65,0.25);
   double sim_DemandReturn=f_idealSim(ref_effNorm,ref_dispNorm,ref_velNorm,ref_curvNorm,0.50,0.40,0.35,0.20);

   double waveTotalRange=!naf(originToExtreme)?originToExtreme:atr*5.0;
   double currentToFlipMid=(!naf(g_flipTop)&&!naf(g_flipBot))?MathAbs(cl-(g_flipTop+g_flipBot)/2.0):atr*4.0;
   double currentToExtreme=direction==1?MathAbs(nz(g_cycleHigh,cl+atr)-cl):MathAbs(cl-nz(g_cycleLow,cl-atr));
   double _posNormDen=fmax2(waveTotalRange,atr*0.5);
   double posDistToCreation   =fmin2(currentToExtreme/_posNormDen*100.0,100.0);
   double posDistToDemand     =fmin2(currentToFlipMid/_posNormDen*100.0,100.0);

   //--- velocity history for vel[2] ---
   ArrayResize(g_velHist,ArraySize(g_velHist)+1); g_velHist[ArraySize(g_velHist)-1]=velocity;
   double vel2=(ArraySize(g_velHist)>=3)?g_velHist[ArraySize(g_velHist)-3]:velocity;

   double expWeaknessScore=fmin2(((efficiency<effThresh?(1.0-efficiency/fmax2(effThresh,1e-10))*40.0:0.0)+
        (obs_DecayScore*0.30)+(MathAbs(velocity)<MathAbs(vel2)*0.6?20.0:0.0))*(100.0/90.0),100.0);
   double inductionMatScore=fmin2((g_inductionEvidence?35.0:0.0)+(obs_CurvatureScore*0.35)+(g_preConvEvidence?20.0:0.0)+
        (displacement>dispThresh*1.2&&(bullMomDecay||bearMomDecay)?10.0:0.0),100.0);
   double liqMatScore=fmin2((obs_LiquidityScore*0.50)+(liqSweepBull||liqSweepBear?30.0:0.0)+(liqHeat>60?20.0:liqHeat>30?10.0:0.0),100.0);
   double rawConvexityMaturity=fmin2(expWeaknessScore*0.35+inductionMatScore*0.35+liqMatScore*0.30,100.0);
   g_convexityMaturity=g_convexityMaturity+(2.0/(beliefSmooth+1))*(rawConvexityMaturity-g_convexityMaturity);
   double convexityMaturity=g_convexityMaturity;

   //==============================================================
   // ENGINE 1A — DISPLAY-PHASE AUTHORITY (liqg overlay)
   //==============================================================
   bool _liqgRetr=ie1a_currentPhase=="Retracement Induction";
   bool _liqgArm =ie1a_currentPhase=="Expansion Induction"||_liqgRetr;
   double _liqgObj=se5_tgt;
   if(_liqgArm && !g_liqg_active && !naf(_liqgObj)){
      g_liqg_active=true; g_liqg_isRetr=_liqgRetr; g_liqg_target=_liqgObj;
      g_liqg_dir=_liqgObj>cl?1:-1; g_liqg_initDist=fmax2(MathAbs(_liqgObj-cl),atr*0.5);
   }
   if(g_liqg_active && !naf(_liqgObj)) g_liqg_target=_liqgObj;
   double _liqgRemain=(g_liqg_active&&!naf(g_liqg_target))?MathAbs(g_liqg_target-cl):NA;
   double liqg_distPct=(g_liqg_active&&!naf(_liqgRemain))?fmin2(100.0,_liqgRemain/fmax2(g_liqg_initDist,1e-10)*100.0):NA;
   bool _liqgCapExh=ede_dissipationProgress>60||convexityMaturity>60;
   bool _liqgResolved=re_resolutionState=="RESOLVED";
   bool _liqgEnergyLo=efficiency<effThresh*0.7;
   bool _liqgMagnet=g_liqg_active&&!naf(liqg_distPct)&&liqg_distPct<20;
   bool _liqgArrStruct=g_liqg_active&&!naf(g_liqg_target)&&(g_liqg_dir==1?cl>=g_liqg_target:cl<=g_liqg_target);
   bool _liqgArrPhys=_liqgCapExh&&(_liqgResolved||_liqgMagnet);
   bool liqg_objArrival=_liqgArrStruct&&_liqgEnergyLo&&_liqgArrPhys;
   bool _liqgCounterBOS=g_liqg_dir==1?bearBOS:bullBOS;
   bool liqg_trueCHoCH=liqg_objArrival&&_liqgCounterBOS&&_liqgEnergyLo&&_liqgResolved;
   string liqg_subPhase=!g_liqg_active?"":liqg_objArrival?"Objective Arrival":
        (_liqgMagnet&&_liqgEnergyLo)?"Terminal Liquidation":
        (convexityMaturity>40||ede_dissipationProgress>40)?"Induction":
        (!naf(liqg_distPct)&&liqg_distPct<70)?"Displacement":
        (!naf(liqg_distPct)&&liqg_distPct<95)?"Push":"Initialization";
   string liqg_title=!g_liqg_active?"":
        (g_liqg_isRetr&&displayWaveDir_M5==-1)?"Pre-Supply Return Liquidation Wave":
        g_liqg_isRetr?"Pre-Demand Return Liquidation Wave":
        displayWaveDir_M5==-1?"Pre-New Low Liquidation Wave":"Pre-New High Liquidation Wave";
   bool _liqgInWindow=ie1a_currentPhase=="Expansion Induction"||ie1a_currentPhase=="Expansion Liquidity"||ie1a_currentPhase=="Retracement Induction"||ie1a_currentPhase=="Retracement Liquidity";
   if(g_liqg_active && (!_liqgInWindow||(liqg_objArrival&&liqg_trueCHoCH))) g_liqg_active=false;
   if(liqg_objArrival&&liqg_trueCHoCH) g_liqg_absorbUnlocked=true;
   if(ie1a_currentPhase=="Point 4 Origin") g_liqg_absorbUnlocked=false;
   string currentDisplayPhase=g_liqg_active?(liqg_title+(liqg_subPhase!=""?" - "+liqg_subPhase:"")):ie1a_currentPhase;
   bool _cdpSAgree=displayWaveDir_M5!=0&&(displayWaveDir_M5==1?cl>se5_inv:cl<se5_inv);
   bool _cdpMAgree=displayWaveDir_M5!=0&&(displayWaveDir_M5==1?velocity>0:velocity<0);
   bool _cdpPAgree=re_resolutionState!="RESOLVED"&&ede_dissipationProgress<80;
   double phaseConfidence=(_cdpSAgree?34.0:0.0)+(_cdpMAgree?33.0:0.0)+(_cdpPAgree?33.0:0.0);
   double phaseIntegrity=fmax2(0.0,fmin2(100.0,phaseConfidence*0.6+(100.0-fmin2(ede_dissipationProgress,100.0))*0.4));
   double _ppDistConsumed=(!naf(se5_tgt)&&!naf(se5_inv))?fmin2(100.0,MathAbs(cl-se5_inv)/fmax2(MathAbs(se5_tgt-se5_inv),1e-10)*100.0):NA;
   double phaseProgress=(g_liqg_active&&!naf(liqg_distPct))?(100.0-liqg_distPct):
        naf(_ppDistConsumed)?fmin2(100.0,ede_dissipationProgress*0.5+convexityMaturity*0.5):
        fmin2(100.0,_ppDistConsumed*0.5+convexityMaturity*0.3+ede_dissipationProgress*0.2);
   string liqg_arrTx=liqg_objArrival?"Yes":(!naf(liqg_distPct)&&liqg_distPct<12)?"Imminent":"No";

   //==============================================================
   // 12-WP / 12-FIT
   //==============================================================
   double _progressFromGeom=NA;
   if(!naf(g_point4OriginHigh)&&!naf(g_flipTop)&&!naf(g_flipBot)){
      double _origin=direction==1?g_point4OriginLow:g_point4OriginHigh;
      double _extreme=direction==1?nz(g_cycleHigh,cl+atr):nz(g_cycleLow,cl-atr);
      double _fzMid=(g_flipTop+g_flipBot)/2.0;
      double _totalMove=MathAbs(_extreme-_origin);
      double _toFzMid=MathAbs(_extreme-_fzMid);
      double _traveled=MathAbs(cl-_origin);
      double _expProg=_totalMove>1e-10?fmin2(_traveled/_totalMove*60.0,60.0):30.0;
      double _retrMove=MathAbs(cl-_extreme);
      double _retrProg=_toFzMid>1e-10?fmin2(_retrMove/fmax2(_toFzMid,1e-10)*40.0,40.0):0.0;
      double _retrWeight=fmin2(obs_AbsorptionScore/40.0,1.0);
      _progressFromGeom=_expProg+_retrProg*_retrWeight;
   }
   double _geomProgress=nz(_progressFromGeom,30.0);
   double _simAnchor=
        (sim_DemandReturn>=sim_Retracement&&sim_DemandReturn>=sim_Absorption&&sim_DemandReturn>=sim_Creation&&sim_DemandReturn>=sim_Expansion)?95.0:
        (sim_Retracement>=sim_Absorption&&sim_Retracement>=sim_Creation&&sim_Retracement>=sim_Expansion)?87.0:
        (sim_Absorption>=sim_Creation&&sim_Absorption>=sim_Expansion)?75.0:
        (sim_Creation>=sim_Liquidity&&sim_Creation>=sim_Expansion)?62.0:
        (sim_Liquidity>=sim_Induction&&sim_Liquidity>=sim_Expansion)?52.0:
        (sim_Induction>=sim_PreConv&&sim_Induction>=sim_Expansion)?43.0:
        (sim_PreConv>=sim_Expansion)?33.0:22.0;
   double _convWeight=fmax2(0.0,1.0-MathAbs(_simAnchor-47.5)/14.5);
   double _convAdjust=(convexityMaturity/100.0)*(_simAnchor-33.0)*0.50*_convWeight;
   double _physProgress=_simAnchor+_convAdjust;
   double rawWaveProgress=_geomProgress*0.60+_physProgress*0.40;
   g_waveProgress=g_waveProgress+(2.0/(beliefSmooth+1))*(rawWaveProgress-g_waveProgress);
   g_waveProgress=clamp(g_waveProgress,0.0,100.0);
   double waveProgress=g_waveProgress;
   double _bestSim=fmax2(sim_Expansion,fmax2(sim_PreConv,fmax2(sim_Induction,fmax2(sim_Liquidity,fmax2(sim_Creation,fmax2(sim_Absorption,fmax2(sim_Retracement,sim_DemandReturn)))))));
   double _geomConsistency=fmin2((!naf(originToExtreme)&&originToExtreme>atr*2.0?30.0:0.0)+
        (!naf(flipzoneWidth)&&flipzoneWidth<atr*4.0?25.0:0.0)+
        ((!naf(g_cycleHigh)||!naf(g_cycleLow))?20.0:0.0)+(direction!=0?25.0:0.0),100.0);
   double rawWaveModelFit=_bestSim*0.55+_geomConsistency*0.45;
   g_waveModelFit=g_waveModelFit+(2.0/(beliefSmooth+1))*(rawWaveModelFit-g_waveModelFit);
   g_waveModelFit=clamp(g_waveModelFit,0.0,100.0);
   double waveModelFit=g_waveModelFit;

   //==============================================================
   // 12A — BELIEF ENGINE
   //==============================================================
   g_preConvEvidence=bullMomDecay||bearMomDecay;
   g_inductionEvidence=(direction==1&&bearImpulse&&structBias==1)||(direction==-1&&bullImpulse&&structBias==-1);
   bool liquidityEvidence=obs_LiquidityScore>50.0&&obs_DecayScore>40.0;
   double _expPosMult=waveProgress<40.0?1.20:waveProgress<60.0?0.80:0.50;
   double rawExpansionBelief=fmin2((obs_ExpansionScore*0.45+(bullImpulse||bearImpulse?30.0:0.0)+(efficiency>effThresh*1.1?15.0:0.0)+sim_Expansion*0.10)*_expPosMult,100.0);
   double _convPosMult=(waveProgress>=30.0&&waveProgress<=65.0)?1.30:0.70;
   double rawConvexityBelief=fmin2((obs_DecayScore*0.30+obs_CurvatureScore*0.25+(g_preConvEvidence?15.0:0.0)+(g_inductionEvidence?10.0:0.0)+(liquidityEvidence?5.0:0.0)+convexityMaturity*0.08)*_convPosMult,100.0);
   double _creatPosMult=(waveProgress>=45.0&&waveProgress<=68.0)?1.40:0.60;
   double rawCreationBelief=fmin2(((convexityMaturity>50?convexityMaturity*0.12:0.0)+(obs_DecayScore>60?obs_DecayScore*0.20:0.0)+(obs_LiquidityScore>50?obs_LiquidityScore*0.20:0.0)+(obs_AbsorptionScore>20?obs_AbsorptionScore*0.15:0.0)+((!naf(g_cycleHigh)&&!naf(g_cycleLow)&&((direction==1&&hi>=nz(g_cycleHigh,hi)*0.998)||(direction==-1&&lo<=nz(g_cycleLow,lo)*1.002)))?20.0:0.0)+sim_Creation*0.10+(posDistToCreation<15.0?(15.0-posDistToCreation)*1.0:0.0))*_creatPosMult,100.0);
   double rawAbsorptionBelief=fmin2(obs_AbsorptionScore*0.50+(efficiency<effThresh*0.6?25.0:0.0)+(displacement<dispThresh*0.5?15.0:0.0)+sim_Absorption*0.10,100.0);
   double rawRetracementBelief=fmin2(((direction==1&&bearImpulse)||(direction==-1&&bullImpulse)?45.0:0.0)+(rawAbsorptionBelief>50?rawAbsorptionBelief*0.30:0.0)+(obs_CurvatureScore>40?15.0:0.0)+sim_Retracement*0.10,100.0);
   double rawDemandReturnBelief=fmin2(((!naf(g_flipTop)&&!naf(g_flipBot)&&cl<=g_flipTop&&cl>=g_flipBot)?35.0:0.0)+(rawRetracementBelief>60?rawRetracementBelief*0.30:0.0)+(liqHeat>50?liqHeat*0.15:0.0)+(liqSweepBull||liqSweepBear?20.0:0.0)+sim_DemandReturn*0.10,100.0);
   double bSmAlpha=2.0/(beliefSmooth+1);
   g_expansionBelief   +=bSmAlpha*(nz(rawExpansionBelief)   -g_expansionBelief);
   g_convexityBelief   +=bSmAlpha*(nz(rawConvexityBelief)   -g_convexityBelief);
   g_creationBelief    +=bSmAlpha*(nz(rawCreationBelief)    -g_creationBelief);
   g_absorptionBelief  +=bSmAlpha*(nz(rawAbsorptionBelief)  -g_absorptionBelief);
   g_retracementBelief +=bSmAlpha*(nz(rawRetracementBelief) -g_retracementBelief);
   g_demandReturnBelief+=bSmAlpha*(nz(rawDemandReturnBelief)-g_demandReturnBelief);
   double d_expansionBelief   =clamp(g_expansionBelief,0,100);
   double d_convexityBelief   =clamp(g_convexityBelief,0,100);
   double d_creationBelief    =clamp(g_creationBelief,0,100);
   double d_absorptionBelief  =clamp(g_absorptionBelief,0,100);
   double d_retracementBelief =clamp(g_retracementBelief,0,100);
   double d_demandReturnBelief=clamp(g_demandReturnBelief,0,100);
   double expansionBelief=g_expansionBelief, convexityBelief=g_convexityBelief, creationBelief=g_creationBelief;
   double absorptionBelief=g_absorptionBelief, retracementBelief=g_retracementBelief, demandReturnBelief=g_demandReturnBelief;

   //==============================================================
   // 12B — PROXIMITY
   //==============================================================
   double expansionProximity=fmin2(sim_Expansion*0.50+(bullImpulse||bearImpulse?25.0:0.0)+(waveProgress<35.0?(35.0-waveProgress)*0.50:0.0)+(obs_ExpansionScore*0.25),100.0);
   double convexityProximity=fmin2(sim_PreConv*0.25+sim_Induction*0.25+sim_Liquidity*0.20+(g_preConvEvidence?15.0:0.0)+(waveProgress>=30.0&&waveProgress<=65.0?15.0:0.0),100.0);
   double creationProximity=fmin2(sim_Creation*0.50+(!naf(g_cycleHigh)&&direction==1&&hi>=nz(g_cycleHigh,hi)*0.995?25.0:0.0)+(!naf(g_cycleLow)&&direction==-1&&lo<=nz(g_cycleLow,lo)*1.005?25.0:0.0)+(convexityMaturity>60?convexityMaturity*0.25:0.0),100.0);
   double absorptionProximity=fmin2(sim_Absorption*0.50+(obs_AbsorptionScore*0.35)+(waveProgress>=68.0&&waveProgress<=80.0?15.0:0.0),100.0);
   double retracementProximity=fmin2(sim_Retracement*0.50+((direction==1&&bearImpulse)||(direction==-1&&bullImpulse)?30.0:0.0)+(waveProgress>=78.0&&waveProgress<=93.0?20.0:0.0),100.0);
   double demandReturnProximity=fmin2(sim_DemandReturn*0.50+(!naf(g_flipTop)&&!naf(g_flipBot)&&cl<=g_flipTop&&cl>=g_flipBot?30.0:0.0)+(waveProgress>=90.0?20.0:0.0),100.0);

   //==============================================================
   // 12D — HYPOTHESIS
   //==============================================================
   double _fitMult=fmax2(0.60,waveModelFit/100.0);
   double hyp_LateExpansion=(expansionBelief*0.35+(waveProgress<38.0?(38.0-waveProgress)*0.80:0.0)+(convexityMaturity<30?(30.0-convexityMaturity)*0.30:0.0)+sim_Expansion*0.20+(expansionBelief>55&&convexityBelief>30?10.0:0.0))*_fitMult;
   double hyp_TerminalConvexity=(convexityBelief*0.30+(convexityMaturity>50?convexityMaturity*0.25:0.0)+(waveProgress>=38.0&&waveProgress<=62.0?20.0:0.0)+(sim_Induction+sim_Liquidity)*0.10+(posDistToCreation<25.0?(25.0-posDistToCreation)*0.50:0.0))*_fitMult;
   double hyp_CreationForming=(creationBelief*0.40+(convexityMaturity>65?(convexityMaturity-65.0)*0.40:0.0)+(posDistToCreation<15.0?(15.0-posDistToCreation)*1.50:0.0)+sim_Creation*0.20)*_fitMult;
   double hyp_AbsorptionActive=(absorptionBelief*0.45+(waveProgress>=68.0&&waveProgress<=80.0?20.0:0.0)+sim_Absorption*0.25+(g_m1AbsorptionEmer?10.0:0.0))*_fitMult;
   double hyp_RetracementActive=(retracementBelief*0.45+(waveProgress>=78.0&&waveProgress<=92.0?20.0:0.0)+sim_Retracement*0.25+((direction==1&&bearImpulse)||(direction==-1&&bullImpulse)?10.0:0.0))*_fitMult;
   double hyp_DemandReturn=(demandReturnBelief*0.45+(waveProgress>=88.0?(waveProgress-88.0)*1.20:0.0)+sim_DemandReturn*0.25+(g_closeInside?15.0:0.0))*_fitMult;
   double hyp_LateExpansion_N    =clamp(hyp_LateExpansion/105.0*100.0,0,100);
   double hyp_EarlyConvexity_N   =clamp(hyp_TerminalConvexity/108.0*100.0,0,100);
   double hyp_CreationForming_N  =clamp(hyp_CreationForming/97.0*100.0,0,100);
   double hyp_AbsorptionActive_N =clamp(hyp_AbsorptionActive/100.0*100.0,0,100);
   double hyp_RetracementActive_N=clamp(hyp_RetracementActive/100.0*100.0,0,100);
   double hyp_DemandReturn_N     =clamp(hyp_DemandReturn/100.0*100.0,0,100);
   string primaryHypothesis=ie1a_hypFamily;
   double primaryHypothesisConf=primaryHypothesis=="EXPANSION"?hyp_LateExpansion_N:
        primaryHypothesis=="CONVEXITY FORMING"?hyp_EarlyConvexity_N:
        primaryHypothesis=="CREATION FORMING"?hyp_CreationForming_N:
        primaryHypothesis=="ABSORPTION"?hyp_AbsorptionActive_N:
        primaryHypothesis=="RETRACEMENT"?hyp_RetracementActive_N:hyp_DemandReturn_N;

   //==============================================================
   // 12E — PREDICTION
   //==============================================================
   double predScore_Expansion=(waveProgress<35.0?(35.0-waveProgress)*1.00:0.0)+(expansionBelief>55?expansionBelief*0.30:0.0)+(convexityMaturity<25?20.0:0.0)+(posDistToCreation>30?15.0:0.0)+(htfAlign==direction&&direction!=0?15.0:0.0);
   double predScore_Convexity=(waveProgress>=25.0&&waveProgress<=60.0?30.0:0.0)+(convexityMaturity>20?convexityMaturity*0.30:0.0)+(obs_DecayScore>40?20.0:0.0)+(g_m1ConvexityEmer?15.0:0.0)+(g_preConvEvidence?15.0:0.0);
   double predScore_Creation=(convexityMaturity>55?(convexityMaturity-55.0)*1.20:0.0)+(posDistToCreation<20.0?(20.0-posDistToCreation)*2.00:0.0)+(obs_LiquidityScore>55?20.0:0.0)+(liqSweepBull||liqSweepBear?15.0:0.0)+(g_m1LiquidityEmer?10.0:0.0);
   double predScore_Absorption=(predScore_Creation>50?predScore_Creation*0.40:0.0)+(obs_AbsorptionScore>35?obs_AbsorptionScore*0.30:0.0)+(g_m1AbsorptionEmer?20.0:0.0)+(waveProgress>=60.0&&waveProgress<=78.0?15.0:0.0);
   double predScore_Retracement=(absorptionBelief>45?absorptionBelief*0.35:0.0)+((direction==1&&bearMicroImpulse)||(direction==-1&&bullMicroImpulse)?25.0:0.0)+(waveProgress>=72.0&&waveProgress<=90.0?20.0:0.0)+(physicsConsensus<40?10.0:0.0);
   double predScore_DemandReturn=(retracementBelief>45?retracementBelief*0.35:0.0)+(posDistToDemand<20.0?(20.0-posDistToDemand)*1.50:0.0)+(liqSweepBull||liqSweepBear?20.0:0.0)+(waveProgress>=88.0?(waveProgress-88.0)*1.20:0.0);
   double _maxPredScore=fmax2(predScore_Expansion,fmax2(predScore_Convexity,fmax2(predScore_Creation,fmax2(predScore_Absorption,fmax2(predScore_Retracement,predScore_DemandReturn)))));
   string expectedNextPhase=
        (predScore_DemandReturn>=predScore_Retracement&&predScore_DemandReturn>=predScore_Absorption&&predScore_DemandReturn>=predScore_Creation&&predScore_DemandReturn>=predScore_Convexity&&predScore_DemandReturn>=predScore_Expansion)?(direction==-1?"Supply Return":"Demand Return"):
        (predScore_Retracement>=predScore_Absorption&&predScore_Retracement>=predScore_Creation&&predScore_Retracement>=predScore_Convexity&&predScore_Retracement>=predScore_Expansion)?"Retracement":
        (predScore_Absorption>=predScore_Creation&&predScore_Absorption>=predScore_Convexity&&predScore_Absorption>=predScore_Expansion)?"Absorption":
        (predScore_Creation>=predScore_Convexity&&predScore_Creation>=predScore_Expansion)?(direction==-1?"New Low":"New High"):
        (predScore_Convexity>=predScore_Expansion)?"Expansion Pre-Convexity":"Expansion";
   double expectedNextProb=_maxPredScore>0?fmin2(_maxPredScore/fmax2(_maxPredScore+30.0,1.0)*100.0,95.0):50.0;

   //==============================================================
   // 12F — VALIDATION + 12G CONFIDENCE
   //==============================================================
   bool predTransition=ie1a_currentPhase!=g_lastIE1APhase;
   bool predSucceeded=predTransition&&ie1a_currentPhase==g_lastExpectedPhase;
   if(predTransition){ g_predOutcomes[g_predTotalIdx%100]=predSucceeded?1:0; g_predTotalIdx++; }
   g_lastExpectedPhase=expectedNextPhase; g_lastIE1APhase=ie1a_currentPhase;
   double predAcc10=PredAcc(10),predAcc25=PredAcc(25),predAcc50=PredAcc(50),predAcc100=PredAcc(100);
   double predReliability=predAcc10*0.4+predAcc25*0.3+predAcc50*0.2+predAcc100*0.1;
   double confIncrease=(predSucceeded?3.0:0.0)+(physicsConsensus>70?2.0:0.0)+(htfAlign==direction&&direction!=0?1.5:0.0)+(dir_tf1==dir_tf2&&dir_tf1!=0?1.0:0.0);
   double confDecrease=(predTransition&&!predSucceeded?2.0:0.0)+(physicsDiff>60?2.0:0.0)+(htfAlign!=direction&&direction!=0?1.5:0.0)+(dir_tf1!=dir_tf2&&dir_tf1!=0&&dir_tf2!=0?1.0:0.0);
   g_modelConfidence=fmax2(10.0,fmin2(100.0,g_modelConfidence+confIncrease-confDecrease-confDecayRate*(g_modelConfidence-50.0)));
   double modelConfidence=g_modelConfidence;
   double idealExpansionSig=efficiency, idealConvSig=obs_DecayScore/100.0, idealAbsSig=obs_AbsorptionScore/100.0;
   double waveDeviationRaw=MathAbs(idealExpansionSig-(ie1a_hypFamily=="EXPANSION"?0.85:0.30))*40.0+MathAbs(idealConvSig-(ie1a_hypFamily=="CONVEXITY FORMING"?0.70:0.20))*30.0+MathAbs(idealAbsSig-(ie1a_hypFamily=="ABSORPTION"?0.70:0.15))*30.0;
   double waveDeviation=fmin2(waveDeviationRaw*100.0,100.0);
   bool deviationAlert=waveDeviation>devReinterpThresh;
   int m1WarningScore=(m1ExpansionWeak?1:0)+(g_m1ConvexityEmer?1:0)+(m1InductionEmer?1:0)+(g_m1LiquidityEmer?1:0)+(g_m1AbsorptionEmer?1:0);
   string m1Warning=m1WarningScore>=4?"CRITICAL":m1WarningScore>=3?"HIGH":m1WarningScore>=2?"MODERATE":m1WarningScore>=1?"LOW":"CLEAR";
   double htf_ExpBelief =fmin2(expScr_tf2*0.5+expScr_tf1*0.5,100.0);
   double htf_ConvBelief=fmin2(decScr_tf2*0.4+curvScr_tf2*0.3+decScr_tf1*0.3,100.0);
   double htf_AbsBelief =fmin2(abScr_tf2*0.5+abScr_tf1*0.5,100.0);
   double htf_LiqBelief =fmin2(liqScr_tf2*0.5+liqScr_tf1*0.5,100.0);


   //==============================================================
   // SECTION 13 — WAVE SPAWN ENGINE
   //==============================================================
   g_recursiveJustFired=false;
   bool _allowSpawn=l0_dir!=0 && l0_dir!=g_direction;
   if(_allowSpawn){
      int nd=l0_dir;
      double obTop=nd==1?g_lastPivotPrice:g_prevPivotPrice;
      double obBot=nd==1?g_prevPivotPrice:g_lastPivotPrice;
      int anchBar=g_prevPivotBar;
      double fzIP=FindInducPrice(h,l,i,anchBar,obTop,obBot,inducLookback);
      obTop=nz(se5_p4h,obTop); obBot=nz(se5_p4l,obBot);
      g_lastSpawnDir=nd; g_direction=nd; g_flipTop=obTop; g_flipBot=obBot;
      g_barsInZone=0; g_obBirthBar=i; g_contBar=-1;
      g_point4OriginHigh=obTop; g_point4OriginLow=obBot; g_point4OriginBar=i;
      g_flipzoneInducPrice=fzIP; g_flipzoneInducLow=naf(fzIP)?NA:fzIP-atr*inducZoneWidth; g_flipzoneInducHigh=naf(fzIP)?NA:fzIP+atr*inducZoneWidth;
      g_inducExpOriginHigh=NA; g_inducExpExtremeLow=NA; g_inducExpOriginLow=NA; g_inducExpExtremeHigh=NA;
      g_inducRetrOriginHigh=NA; g_inducRetrExtremeLow=NA; g_inducRetrOriginLow=NA; g_inducRetrExtremeHigh=NA;
      g_inducZoneLow=NA; g_inducZoneHigh=NA; g_cycleHigh=hi; g_cycleLow=lo;
      g_isRecursiveWave=false; g_entryCycle=0; g_waveDepth=0;
   }
   if(g_direction==1 && hi>nz(g_cycleHigh,hi)) g_cycleHigh=hi;
   if(g_direction==-1 && lo<nz(g_cycleLow,lo)) g_cycleLow=lo;

   bool expInducBuyEv =g_direction==1 && bearImpulse && structBias==1;
   bool expInducSellEv=g_direction==-1&& bullImpulse && structBias==-1;
   if(expInducBuyEv && naf(g_inducExpOriginHigh)){ g_inducExpOriginHigh=nz(g_point4OriginHigh,nz(g_cycleHigh,hi)); g_inducExpExtremeLow=lo; g_inducZoneLow=nz(g_point4OriginHigh,lo)-atr*inducZoneWidth; g_inducZoneHigh=nz(g_point4OriginHigh,lo)+atr*inducZoneWidth; }
   if(expInducSellEv && naf(g_inducExpOriginLow)){ g_inducExpOriginLow=nz(g_point4OriginLow,nz(g_cycleLow,lo)); g_inducExpExtremeHigh=hi; g_inducZoneLow=nz(g_point4OriginLow,hi)-atr*inducZoneWidth; g_inducZoneHigh=nz(g_point4OriginLow,hi)+atr*inducZoneWidth; }
   if(!naf(g_inducExpExtremeLow)&&g_direction==1&&lo<g_inducExpExtremeLow){ g_inducExpExtremeLow=lo; g_inducZoneLow=lo-atr*inducZoneWidth; g_inducZoneHigh=lo+atr*inducZoneWidth; }
   if(!naf(g_inducExpExtremeHigh)&&g_direction==-1&&hi>g_inducExpExtremeHigh){ g_inducExpExtremeHigh=hi; g_inducZoneLow=hi-atr*inducZoneWidth; g_inducZoneHigh=hi+atr*inducZoneWidth; }
   g_nearFlipzone=!naf(g_flipTop)&&!naf(g_flipBot)&&cl<=g_flipTop*1.02&&cl>=g_flipBot*0.98;
   bool nearFlipzone=g_nearFlipzone;
   bool retrInducBuyEv =g_direction==1 && bullImpulse && structBias==-1 && nearFlipzone;
   bool retrInducSellEv=g_direction==-1&& bearImpulse && structBias==1  && nearFlipzone;
   if(retrInducBuyEv && naf(g_inducRetrOriginLow)){ g_inducRetrOriginLow=nz(g_cycleLow,lo); g_inducRetrExtremeHigh=hi; g_inducZoneLow=hi-atr*inducZoneWidth; g_inducZoneHigh=hi+atr*inducZoneWidth; }
   if(retrInducSellEv && naf(g_inducRetrOriginHigh)){ g_inducRetrOriginHigh=nz(g_cycleHigh,hi); g_inducRetrExtremeLow=lo; g_inducZoneLow=lo-atr*inducZoneWidth; g_inducZoneHigh=lo+atr*inducZoneWidth; }
   if(!naf(g_inducRetrExtremeHigh)&&g_direction==1&&hi>g_inducRetrExtremeHigh){ g_inducRetrExtremeHigh=hi; g_inducZoneLow=hi-atr*inducZoneWidth; g_inducZoneHigh=hi+atr*inducZoneWidth; }
   if(!naf(g_inducRetrExtremeLow)&&g_direction==-1&&lo<g_inducRetrExtremeLow){ g_inducRetrExtremeLow=lo; g_inducZoneLow=lo-atr*inducZoneWidth; g_inducZoneHigh=lo+atr*inducZoneWidth; }
   g_closeInside=!naf(g_flipTop)&&cl<=g_flipTop&&cl>=g_flipBot;
   bool priceInDemand=!naf(g_flipBot)&&lo<g_flipBot&&(!naf(g_point4OriginHigh)&&lo<=g_point4OriginHigh);
   bool priceInSupply=!naf(g_flipTop)&&hi>g_flipTop&&(!naf(g_point4OriginLow)&&hi>=g_point4OriginLow);
   bool trueCHoCH_bull=g_direction==1&&priceInDemand&&bullImpulse&&liqSweepOK;
   bool trueCHoCH_bear=g_direction==-1&&priceInSupply&&bearImpulse&&liqSweepOK;
   bool structFlipBull=g_direction==1&&bullConvShift&&structBias==-1;
   bool structFlipBear=g_direction==-1&&bearConvShift&&structBias==1;
   bool recursiveTrigger=(trueCHoCH_bull||trueCHoCH_bear||structFlipBull||structFlipBear)&&(ie1a_currentPhase=="Demand Return"||ie1a_currentPhase=="Supply Return")&&g_demandReturnBelief>40&&g_direction!=0&&!naf(g_flipTop);
   if(recursiveTrigger&&(g_recursiveFiredBar<0||(i-g_recursiveFiredBar)>resetBars)){
      g_recursiveJustFired=true; g_recursiveFiredBar=i; g_recursiveComplete=true;
      int idx=MathMin(MathMax(g_entryCycle,1)-1,3);
      g_cycObTop[idx]=g_flipTop; g_cycObBot[idx]=g_flipBot; g_cycFlipTop[idx]=g_flipTop; g_cycFlipBot[idx]=g_flipBot;
      g_cycP4High[idx]=g_point4OriginHigh; g_cycP4Low[idx]=g_point4OriginLow; g_cycStartBar[idx]=g_point4OriginBar; g_cycDir[idx]=g_direction;
      g_waveGeneration++; g_entryCycle=MathMin(g_entryCycle+1,4); g_isRecursiveWave=true; g_waveDepth=g_entryCycle;
      int nd2=l0_dir!=0?l0_dir:((bullImpulse||bullConvShift)?1:-1);
      double obT2=nd2==1?g_lastPivotPrice:g_prevPivotPrice;
      double obB2=nd2==1?g_prevPivotPrice:g_lastPivotPrice;
      int anchBar2=g_prevPivotBar;
      double fzIP2=FindInducPrice(h,l,i,anchBar2,obT2,obB2,inducLookback);
      g_lastSpawnDir=nd2; g_direction=l0_dir!=0?l0_dir:nd2; g_flipTop=obT2; g_flipBot=obB2; g_barsInZone=0; g_obBirthBar=i;
      g_point4OriginHigh=obT2; g_point4OriginLow=obB2; g_point4OriginBar=i;
      g_flipzoneInducPrice=fzIP2; g_flipzoneInducLow=naf(fzIP2)?NA:fzIP2-atr*inducZoneWidth; g_flipzoneInducHigh=naf(fzIP2)?NA:fzIP2+atr*inducZoneWidth;
      g_inducExpOriginHigh=NA; g_inducExpExtremeLow=NA; g_inducExpOriginLow=NA; g_inducExpExtremeHigh=NA;
      g_inducRetrOriginHigh=NA; g_inducRetrExtremeLow=NA; g_inducRetrOriginLow=NA; g_inducRetrExtremeHigh=NA;
      g_inducZoneLow=NA; g_inducZoneHigh=NA; g_cycleHigh=hi; g_cycleLow=lo; g_contBar=i;
   }
   if(ie1a_currentPhase=="Demand Return"||ie1a_currentPhase=="Supply Return"){ g_barsInZone=g_closeInside?g_barsInZone+1:0; }
   int barsSinceCont=(g_contBar>=0)?i-g_contBar:((g_obBirthBar>=0)?i-g_obBirthBar:0);
   bool bullInvalid=g_direction==1&&cl<g_flipBot-atr*0.5;
   bool bearInvalid=g_direction==-1&&cl>g_flipTop+atr*0.5;
   bool opposingMove=(g_direction==1&&bearImpulse)||(g_direction==-1&&bullImpulse);
   bool hardInvalid=bullInvalid||bearInvalid;
   bool softReset=barsSinceCont>resetBars&&opposingMove&&(ie1a_currentPhase!="Demand Return"&&ie1a_currentPhase!="Supply Return")&&g_demandReturnBelief<30&&g_expansionBelief<30&&!erf_suppressRotation;
   bool safeToReset=hardInvalid||softReset;
   if(g_direction!=l0_dir&&safeToReset){
      g_direction=0; g_lastSpawnDir=0; g_flipTop=NA; g_flipBot=NA; g_contBar=-1; g_obBirthBar=-1; g_barsInZone=0;
      g_isRecursiveWave=false; g_entryCycle=0; g_waveDepth=0; g_recursiveComplete=false;
   }
   direction=g_direction;
   bool recursiveComplete=g_recursiveComplete;
   double flipTop=g_flipTop, flipBot=g_flipBot, point4OriginHigh=g_point4OriginHigh, point4OriginLow=g_point4OriginLow;
   bool closeInside=g_closeInside;

   //==============================================================
   // SECTION 14 — INDUCTION ZONE CLASSIFICATION
   //==============================================================
   bool inRetracementInducZone=!naf(pivL)&&!naf(g_inducZoneLow)&&!naf(g_inducZoneHigh)&&direction==1&&pivL>=g_inducZoneLow&&pivL<=g_inducZoneHigh&&retrInducBuyEv;
   bool inShortRetrInducZone=!naf(pivH)&&!naf(g_inducZoneLow)&&!naf(g_inducZoneHigh)&&direction==-1&&pivH>=g_inducZoneLow&&pivH<=g_inducZoneHigh&&retrInducSellEv;
   double inducConfidence=0.0;
   if(direction==1&&inRetracementInducZone) inducConfidence=1.0;
   else if(direction==1&&!naf(pivL)&&!naf(flipTop)&&!naf(flipBot)&&pivL<flipTop&&pivL>flipBot&&!inRetracementInducZone) inducConfidence=-0.5;
   else if(direction==-1&&inShortRetrInducZone) inducConfidence=1.0;
   else if(direction==-1&&!naf(pivH)&&!naf(flipTop)&&!naf(flipBot)&&pivH>flipBot&&pivH<flipTop&&!inShortRetrInducZone) inducConfidence=-0.5;
   bool retracementPreConvSeen=nearFlipzone&&(bullMomDecay||bearMomDecay);
   bool retracementInductionConf=inRetracementInducZone||inShortRetrInducZone;
   bool convexityComplete=g_creationBelief>50||g_absorptionBelief>40;
   int flipzoneStagesComplete=g_demandReturnBelief>75&&recursiveComplete?5:g_demandReturnBelief>60?4:g_retracementBelief>55?3:retracementInductionConf?2:retracementPreConvSeen?1:0;
   double flipzoneScore=flipzoneStagesComplete/5.0*100.0;

   //==============================================================
   // SECTION 15 — SCORING
   //==============================================================
   double poiMid=(!naf(flipTop)&&!naf(flipBot))?(flipTop+flipBot)/2.0:NA;
   double energy=!naf(poiMid)?MathAbs(cl-poiMid)/fmax2(atr,1e-10):0.0;
   double sStruct=flipzoneScore*0.30;
   double sConv=fmin2(MathAbs(convSmooth)/fmax2(atr*convMult,1e-10)*25.0,25.0);
   double sEnergy=fmin2(energy*10.0,20.0);
   double sEff=efficiency*15.0;
   double sVol=fmin2((atr/fmax2(cl,1e-10))*1000.0,10.0);
   double contProb=fmin2(sStruct+sConv+sEnergy+sEff+sVol,100.0);
   string grade=contProb>90?"A+":contProb>80?"A":contProb>70?"B":contProb>60?"C":"D";
   color gradeCol=grade=="A+"?(color)0x88FF00:grade=="A"?clrLime:grade=="B"?clrYellow:grade=="C"?clrOrange:clrRed;

   //==============================================================
   // SECTION 16 — BAYESIAN
   //==============================================================
   double bayesStruct=structBias==liveWaveDir?0.90:structBias==0?0.50:0.15;
   double bayesMomentum=(liveWaveDir==1&&velocity>0&&acceleration>0)?0.85:(liveWaveDir==-1&&velocity<0&&acceleration<0)?0.85:((liveWaveDir==1&&velocity>0)||(liveWaveDir==-1&&velocity<0))?0.60:0.30;
   double bayesLiq=liqHeat>70?0.80:liqHeat>30?0.55:0.35;
   double bayesHTF=liveHtfAlign==liveWaveDir&&liveHtfAlign!=0?0.90:liveHtfAlign==0?0.55:0.20;
   double bayesDisp=displacement>dispThresh*1.5?0.85:displacement>dispThresh?0.65:0.35;
   double bayesOB=obFreshness>0.7?0.80:obFreshness>0.4?0.60:0.35;
   double bayesInduc=inducConfidence>0?0.90:inducConfidence<0?0.20:0.50;
   double bayesFlipzone=flipzoneStagesComplete>=4?0.92:flipzoneStagesComplete>=3?0.75:flipzoneStagesComplete>=2?0.58:flipzoneStagesComplete>=1?0.42:0.25;
   double logOdds=0.15*MathLog(fmax2(bayesStruct,1e-10)/fmax2(1.0-bayesStruct,1e-10))+0.14*MathLog(fmax2(bayesMomentum,1e-10)/fmax2(1.0-bayesMomentum,1e-10))+0.10*MathLog(fmax2(bayesLiq,1e-10)/fmax2(1.0-bayesLiq,1e-10))+0.14*MathLog(fmax2(bayesHTF,1e-10)/fmax2(1.0-bayesHTF,1e-10))+0.11*MathLog(fmax2(bayesDisp,1e-10)/fmax2(1.0-bayesDisp,1e-10))+0.07*MathLog(fmax2(bayesOB,1e-10)/fmax2(1.0-bayesOB,1e-10))+0.12*MathLog(fmax2(bayesInduc,1e-10)/fmax2(1.0-bayesInduc,1e-10))+0.17*MathLog(fmax2(bayesFlipzone,1e-10)/fmax2(1.0-bayesFlipzone,1e-10));
   double finalProb=1.0/(1.0+MathExp(-logOdds))*100.0;

   //==============================================================
   // SECTION 17 — PROBABILITY PANELS
   //==============================================================
   double velDecay=phys_vd70?1.0:0.0;
   double expansionProbability=fmin2((!bullInvalid&&!bearInvalid?20.0:0.0)+(convexityComplete?20.0:convexityScore*0.4)+(recursiveComplete?15.0:flipzoneStagesComplete*3.0)+(liveHtfAlign==liveWaveDir&&liveHtfAlign!=0?25.0:liveHtfAlign==0?12.5:0.0)+(liqHeat>50?20.0:liqHeat*0.4),100.0);
   double reversalProbability=fmin2((convexityScore>70?25.0:convexityScore*0.35)+(retracementInductionConf?20.0:0.0)+(liqHeat>70?20.0:0.0)+(velDecay*20.0)+(liveHtfAlign!=liveWaveDir&&liveHtfAlign!=0?15.0:0.0),100.0);
   double tradeReadiness=fmin2((liveWaveDir!=0?10.0:0.0)+(flipzoneStagesComplete>=3?15.0:flipzoneStagesComplete*5.0)+(velocityScore*0.10)+(expansionScore*0.10)+(liqHeat<50?10.0:liqHeat>70?-5.0:0.0)+(liveHtfAlign==liveWaveDir&&liveHtfAlign!=0?15.0:0.0)+(expansionProbability*0.20)+(bayesFlipzone*3.0),100.0);

   //==============================================================
   // SECTION 18 — SLIPPAGE & TRADE OPPORTUNITY
   //==============================================================
   double spreadEstimate=atr*0.05;
   double volatilityFactor=volRatio*0.10;
   double slippageCost=atr*volatilityFactor+spreadEstimate;
   double liqDepthPenalty=liqHeat>70?atr*0.05:0.0;
   double totalSlippage=slippageCost+liqDepthPenalty;
   double baseTrend=efficiency*30;
   double impulseScore=displacement>dispThresh?20:0;
   double momentumScore=phys_mom>0?10:-10;
   double accelScore=acceleration>0?10:-10;
   double structScoreV=structBias==1?20:structBias==-1?-20:0;
   double htfScoreV=htfAlign==1?20:htfAlign==-1?-20:0;
   double liqScoreV=wDensity<0.5?10:-5;
   double zoneScore=closeInside?15:0;
   double inducScore=inducConfidence>0?10:inducConfidence<0?-10:0;
   double fzStageScore=flipzoneStagesComplete*6.0;
   double beliefBonus=(direction==1&&g_demandReturnBelief>60)?g_demandReturnBelief*0.10:(direction==-1&&g_demandReturnBelief>60)?g_demandReturnBelief*0.10:0.0;
   double confMult=fmax2(0.7,fmin2(modelConfidence/100.0*1.3,1.3));
   double buyScore=(baseTrend+impulseScore+fmax2(momentumScore,0)+fmax2(accelScore,0)+fmax2(structScoreV,0)+fmax2(htfScoreV,0)+liqScoreV+zoneScore+fmax2(inducScore,0)+fzStageScore+beliefBonus+(fractalStackDir==1?fractalCtxScore*0.30:0.0))*confMult;
   double sellScore=(baseTrend+impulseScore+fmax2(-momentumScore,0)+fmax2(-accelScore,0)+fmax2(-structScoreV,0)+fmax2(-htfScoreV,0)+liqScoreV+zoneScore+fmax2(-inducScore,0)+fzStageScore+beliefBonus+(fractalStackDir==-1?fractalCtxScore*0.30:0.0))*confMult;
   double netEdge=buyScore-sellScore;
   double netEdgeAdjusted=netEdge-(totalSlippage/fmax2(atr,1e-10)*10.0);
   bool edgePassesFilter=MathAbs(netEdgeAdjusted)>execThreshold;
   double buyProb=clamp(buyScore/279.5*100.0,0,100);
   double sellProb=clamp(sellScore/279.5*100.0,0,100);
   string liveDirective=netEdgeAdjusted>25?"BUY PRESSURE":netEdgeAdjusted>10?"BULLISH BIAS":netEdgeAdjusted<-25?"SELL PRESSURE":netEdgeAdjusted<-10?"BEARISH BIAS":"NEUTRAL / WAIT";

   //==============================================================
   // SECTION 19 — HTF ALIGNMENT GATE / SECTION 20 — EXEC LOCK
   //==============================================================
   bool htfAligned=direction!=0&&(htfAlign==direction||htfAlign==0);
   int resonance=htfAligned?2:1;
   int dynamicLockBars=(int)MathRound(baseLockBars*volMult);
   bool inducRearmLong=direction==1&&inRetracementInducZone;
   bool inducRearmShort=direction==-1&&inShortRetrInducZone;
   if(g_recursiveJustFired) g_engineArmed=true;
   if(inducRearmLong||inducRearmShort) g_engineArmed=true;
   bool withinGlobalLock=g_lastSignalBar>=0&&(i-g_lastSignalBar)<dynamicLockBars;
   bool withinLongLock=g_lastLongBar>=0&&(i-g_lastLongBar)<dynamicLockBars;
   bool withinShortLock=g_lastShortBar>=0&&(i-g_lastShortBar)<dynamicLockBars;
   bool signalLocked=withinGlobalLock&&!g_engineArmed;
   bool htfLongOK=(!requireHTFAlign)||(g_htfBias1>=0&&g_htfBias2>=0);
   bool htfShortOK=(!requireHTFAlign)||(g_htfBias1<=0&&g_htfBias2<=0);
   bool preConvOK_long=(!requirePreConv)||retracementPreConvSeen;
   bool preConvOK_short=(!requirePreConv)||retracementPreConvSeen;
   bool inducOK_long=(!requireInduction)||retracementInductionConf;
   bool inducOK_short=(!requireInduction)||retracementInductionConf;

   //==============================================================
   // SECTION 21 — ENTRY SIGNALS
   //==============================================================
   // (grade is no longer an entry gate - removed per design; FU + Invisible Network drive targets)
   bool beliefEntryLong=direction==1&&ie1a_currentPhase=="Demand Return"&&g_demandReturnBelief>50&&g_expansionBelief<60&&g_absorptionBelief>25;
   bool beliefEntryShort=direction==-1&&ie1a_currentPhase=="Supply Return"&&g_demandReturnBelief>50&&g_expansionBelief<60&&g_absorptionBelief>25;
   bool longSignal=showSignals&&beliefEntryLong&&htfAligned&&!signalLocked&&!withinLongLock&&edgePassesFilter&&preConvOK_long&&inducOK_long&&structLongOK&&liqSweepOK&&obFresh&&htfLongOK&&erf_entryGate;
   bool shortSignal=showSignals&&beliefEntryShort&&htfAligned&&!signalLocked&&!withinShortLock&&edgePassesFilter&&preConvOK_short&&inducOK_short&&structShortOK&&liqSweepOK&&obFresh&&htfShortOK&&erf_entryGate;
   if(longSignal){ g_lastSignalBar=i; g_lastLongBar=i; g_engineArmed=false; }
   if(shortSignal){ g_lastSignalBar=i; g_lastShortBar=i; g_engineArmed=false; }
   gBarLong=longSignal; gBarShort=shortSignal; gBarLongPx=lo-atr*0.7; gBarShortPx=hi+atr*0.7;

   //==============================================================
   // SECTION 24 — TRADE STATE
   //==============================================================
   bool exitCondition=(g_tradeDir==1&&bearBOS)||(g_tradeDir==-1&&bullBOS)||(g_tradeDir==1&&bearConvShift&&energy<g_prevEnergy)||(g_tradeDir==-1&&bullConvShift&&energy<g_prevEnergy)||(g_tradeDir==1&&htfAlign==-1)||(g_tradeDir==-1&&htfAlign==1)||(g_tradeDir!=0&&!obFresh)||(g_tradeDir!=0&&safeToReset)||(g_tradeDir==1&&bullInvalid)||(g_tradeDir==-1&&bearInvalid)||(g_tradeDir!=0&&(ie1a_currentPhase=="Absorption"||ie1a_currentPhase=="Retracement"));
   if(longSignal){ g_tradeDir=1; g_exitFiredBar=-1; }
   else if(shortSignal){ g_tradeDir=-1; g_exitFiredBar=-1; }
   else if(exitCondition&&g_tradeDir!=0){ g_exitFiredBar=i; g_tradeDir=0; }
   bool exitLatchActive=g_exitFiredBar>=0&&(i-g_exitFiredBar)<3;
   string directiveStr=longSignal?"BUY (ENTER LONG)":shortSignal?"SELL (ENTER SHORT)":exitLatchActive?"EXIT NOW":g_tradeDir==1?"HOLD LONG":g_tradeDir==-1?"HOLD SHORT":"NO TRADE / STAND DOWN";
   color directiveCol=longSignal?(color)0x88FF00:shortSignal?(color)0x4417FF:exitLatchActive?clrOrange:g_tradeDir==1?clrLime:g_tradeDir==-1?clrRed:clrGray;
   g_prevEnergy=energy;


   //==============================================================
   // DIE-2 — FU ORDER BLOCK DETECTION + LIFECYCLE
   //==============================================================
   double fuRange=hi-lo, fuBody=MathAbs(cl-op), fuUpperWick=hi-fmax2(op,cl), fuLowerWick=fmin2(op,cl)-lo;
   double pO=(i>0)?o[i-1]:op, pH1=(i>0)?h[i-1]:hi, pL1=(i>0)?l[i-1]:lo, pC=(i>0)?c[i-1]:cl;
   double prevRange=pH1-pL1, prevBody=MathAbs(pC-pO), prevUpperWick=pH1-fmax2(pO,pC), prevLowerWick=fmin2(pO,pC)-pL1;
   double prevBodyRatio=prevRange>1e-10?prevBody/prevRange:0.0;
   double prevUpperWickRatio=prevRange>1e-10?prevUpperWick/prevRange:0.0;
   double prevLowerWickRatio=prevRange>1e-10?prevLowerWick/prevRange:0.0;
   bool bearGapLeave=op<pC-atr*0.05, bullGapLeave=op>pC+atr*0.05;
   bool liqLeftBear=!naf(pivH)||(pH1>nz(g_currSwingHigh,pH1)*0.998);
   bool liqLeftBull=!naf(pivL)||(pL1<nz(g_currSwingLow,pL1)*1.002);
   bool isBearFU_prev=prevRange>atr*0.5&&prevBodyRatio>=fuMinBodyRatio&&pC<pO&&prevUpperWickRatio>=fuMinWickRatio&&liqLeftBear&&bearGapLeave;
   bool isBullFU_prev=prevRange>atr*0.5&&prevBodyRatio>=fuMinBodyRatio&&pC>pO&&prevLowerWickRatio>=fuMinWickRatio&&liqLeftBull&&bullGapLeave;
   bool isBullFU=fuRange>atr*0.5&&fuBody/fmax2(fuRange,1e-10)>=fuMinBodyRatio&&cl>op&&fuLowerWick/fmax2(fuRange,1e-10)>=fuMinWickRatio&&((!fuRequireInZone)||(!naf(flipTop)&&!naf(flipBot)&&cl>=flipBot*0.98&&cl<=flipTop*1.02));
   bool isBearFU=fuRange>atr*0.5&&fuBody/fmax2(fuRange,1e-10)>=fuMinBodyRatio&&cl<op&&fuUpperWick/fmax2(fuRange,1e-10)>=fuMinWickRatio&&((!fuRequireInZone)||(!naf(flipTop)&&!naf(flipBot)&&cl>=flipBot*0.98&&cl<=flipTop*1.02));
   if(isBearFU_prev&&showFUBlocks) FuPush(fmax2(pO,pC),pL1,i-1,-1);
   if(isBullFU_prev&&showFUBlocks) FuPush(pH1,fmin2(pO,pC),i-1,1);
   if(isBullFU&&showFUBlocks) FuPush(hi,fmin2(op,cl),i,1);
   if(isBearFU&&showFUBlocks) FuPush(fmax2(op,cl),lo,i,-1);
   bool die_anyBullFUActive=false, die_anyBearFUActive=false; int die_activeFUCount=0;
   for(int fk=ArraySize(g_fu_top)-1;fk>=0;fk--){
      int age=i-g_fu_birthBar[fk];
      if(age>fuMaxBarsActive || g_fu_state[fk]=="Invalidated"){ FuRemove(fk); continue; }
      die_activeFUCount++;
      if(g_fu_dir[fk]==1) die_anyBullFUActive=true; else die_anyBearFUActive=true;
   }

   //==============================================================
   // FU WICK AUTHORITY (1A.8)
   //==============================================================
   double _fuwRange=fmax2(hi-lo,1e-10);
   double _fuwPriorHi=HighestPrior(h,i,fuwLookback), _fuwPriorLo=LowestPrior(l,i,fuwLookback);
   bool _fuwBearCand=!naf(_fuwPriorHi)&&hi>_fuwPriorHi&&cl<_fuwPriorHi&&(hi-fmax2(op,cl))/_fuwRange>=fuwMinWickFrac;
   bool _fuwBullCand=!naf(_fuwPriorLo)&&lo<_fuwPriorLo&&cl>_fuwPriorLo&&(fmin2(op,cl)-lo)/_fuwRange>=fuwMinWickFrac;
   if(_fuwBearCand){ g_fuw_dir=-1; g_fuw_tip=hi; g_fuw_bodyHigh=fmax2(op,cl); g_fuw_bodyLow=fmin2(op,cl); g_fuw_mid=g_fuw_bodyHigh+(g_fuw_tip-g_fuw_bodyHigh)*0.50; g_fuw_mid38=g_fuw_bodyHigh+(g_fuw_tip-g_fuw_bodyHigh)*0.38; g_fuw_mid62=g_fuw_bodyHigh+(g_fuw_tip-g_fuw_bodyHigh)*0.62; g_fuw_leftPool=_fuwPriorHi; g_fuw_bar=i; g_fuw_valid=false; g_fuw_strength=fmin2(100.0,(g_fuw_tip-g_fuw_bodyHigh)/fmax2(atr,1e-10)*40.0+40.0); }
   else if(_fuwBullCand){ g_fuw_dir=1; g_fuw_tip=lo; g_fuw_bodyHigh=fmax2(op,cl); g_fuw_bodyLow=fmin2(op,cl); g_fuw_mid=g_fuw_tip+(g_fuw_bodyLow-g_fuw_tip)*0.50; g_fuw_mid38=g_fuw_tip+(g_fuw_bodyLow-g_fuw_tip)*0.38; g_fuw_mid62=g_fuw_tip+(g_fuw_bodyLow-g_fuw_tip)*0.62; g_fuw_leftPool=_fuwPriorLo; g_fuw_bar=i; g_fuw_valid=false; g_fuw_strength=fmin2(100.0,(g_fuw_bodyLow-g_fuw_tip)/fmax2(atr,1e-10)*40.0+40.0); }
   if(!g_fuw_valid&&g_fuw_dir==-1&&!naf(g_fuw_bodyLow)&&i>g_fuw_bar&&cl<g_fuw_bodyLow) g_fuw_valid=true;
   if(!g_fuw_valid&&g_fuw_dir==1 &&!naf(g_fuw_bodyHigh)&&i>g_fuw_bar&&cl>g_fuw_bodyHigh) g_fuw_valid=true;
   double fuw_bandHi=(naf(g_fuw_mid38)||naf(g_fuw_mid62))?NA:fmax2(g_fuw_mid38,g_fuw_mid62);
   double fuw_bandLo=(naf(g_fuw_mid38)||naf(g_fuw_mid62))?NA:fmin2(g_fuw_mid38,g_fuw_mid62);
   double fuw_futureMagnet=g_fuw_valid?g_fuw_leftPool:NA;

   //==============================================================
   // 1A.9 — MULTI-TF FU POOL MAGNETS
   //==============================================================
   int w_fuValid=MapValI(fpW.t,fpW.valid,fpW.n,ct),   d_fuValid=MapValI(fpD.t,fpD.valid,fpD.n,ct);
   int h4_fuValid=MapValI(fpH4.t,fpH4.valid,fpH4.n,ct),h1_fuValid=MapValI(fpH1.t,fpH1.valid,fpH1.n,ct);
   int m15_fuValid=MapValI(fpM15.t,fpM15.valid,fpM15.n,ct),m5_fuValid=MapValI(fpM5.t,fpM5.valid,fpM5.n,ct);
   double w_fuPool=MapVal(fpW.t,fpW.pool,fpW.n,ct),  w_fuMid=MapVal(fpW.t,fpW.mid,fpW.n,ct),  w_fuTip=MapVal(fpW.t,fpW.tip,fpW.n,ct),  w_fuScore=MapVal(fpW.t,fpW.score,fpW.n,ct);
   double d_fuPool=MapVal(fpD.t,fpD.pool,fpD.n,ct),  d_fuMid=MapVal(fpD.t,fpD.mid,fpD.n,ct),  d_fuTip=MapVal(fpD.t,fpD.tip,fpD.n,ct),  d_fuScore=MapVal(fpD.t,fpD.score,fpD.n,ct);
   double h4_fuPool=MapVal(fpH4.t,fpH4.pool,fpH4.n,ct),h4_fuMid=MapVal(fpH4.t,fpH4.mid,fpH4.n,ct),h4_fuTip=MapVal(fpH4.t,fpH4.tip,fpH4.n,ct),h4_fuScore=MapVal(fpH4.t,fpH4.score,fpH4.n,ct);
   double h1_fuPool=MapVal(fpH1.t,fpH1.pool,fpH1.n,ct),h1_fuMid=MapVal(fpH1.t,fpH1.mid,fpH1.n,ct),h1_fuTip=MapVal(fpH1.t,fpH1.tip,fpH1.n,ct),h1_fuScore=MapVal(fpH1.t,fpH1.score,fpH1.n,ct);
   double m15_fuPool=MapVal(fpM15.t,fpM15.pool,fpM15.n,ct),m15_fuMid=MapVal(fpM15.t,fpM15.mid,fpM15.n,ct),m15_fuTip=MapVal(fpM15.t,fpM15.tip,fpM15.n,ct),m15_fuScore=MapVal(fpM15.t,fpM15.score,fpM15.n,ct);
   double m5_fuTip=MapVal(fpM5.t,fpM5.tip,fpM5.n,ct),m5_fuScore=MapVal(fpM5.t,fpM5.score,fpM5.n,ct);
   int _fuActiveCnt=(w_fuValid==1?1:0)+(d_fuValid==1?1:0)+(h4_fuValid==1?1:0)+(h1_fuValid==1?1:0)+(m15_fuValid==1?1:0)+(m5_fuValid==1?1:0);
   double fu_recursiveAlign=(double)_fuActiveCnt/6.0*100.0;
   double fu_winTarget=NA,fu_winBand=NA; string fu_winSrc="-";
   if(w_fuValid==1&&!naf(w_fuPool)){ fu_winTarget=w_fuPool; fu_winSrc="W FU Left Pool"; fu_winBand=w_fuMid; }
   else if(d_fuValid==1&&!naf(d_fuPool)){ fu_winTarget=d_fuPool; fu_winSrc="D FU Left Pool"; fu_winBand=d_fuMid; }
   else if(h4_fuValid==1&&!naf(h4_fuPool)){ fu_winTarget=h4_fuPool; fu_winSrc="H4 FU Left Pool"; fu_winBand=h4_fuMid; }
   else if(h1_fuValid==1&&!naf(h1_fuPool)){ fu_winTarget=h1_fuPool; fu_winSrc="H1 FU Left Pool"; fu_winBand=h1_fuMid; }
   else if(m15_fuValid==1&&!naf(m15_fuPool)){ fu_winTarget=m15_fuPool; fu_winSrc="M15 FU Left Pool"; fu_winBand=m15_fuMid; }
   else if(g_fuw_valid&&!naf(fuw_futureMagnet)){ fu_winTarget=fuw_futureMagnet; fu_winSrc="FU Left Pool"; fu_winBand=g_fuw_mid; }

   //==============================================================
   // 1A.9B — AFE (Alternating Flip Echo)
   //==============================================================
   if(g_fuw_valid&&(naf(g_afe_origin)||g_fuw_tip!=g_afe_origin)){
      g_afe_origin=g_fuw_tip; g_afe_originDir=g_fuw_dir; g_afe_upperFlip=g_fuw_mid;
      g_afe_lowerFlip=g_fuw_dir==-1?nz(g_prevSwingLow,g_fuw_bodyLow):nz(g_prevSwingHigh,g_fuw_bodyHigh);
      g_afe_step=1; g_afe_upperFlipRole="Destination"; g_afe_activeDest=g_fuw_mid; g_afe_target=NA; g_afe_selfReturnDone=false; g_afe_continuation=false;
   }
   if(g_afe_step>=1&&!naf(g_afe_origin)&&g_afe_originDir!=0){
      bool _afeBear=g_afe_originDir==-1;
      if(g_afe_step==1&&(_afeBear?cl<nz(g_fuw_bodyLow,g_afe_origin):cl>nz(g_fuw_bodyHigh,g_afe_origin))){ g_afe_step=2; g_afe_activeDest=g_afe_upperFlip; }
      if(g_afe_step==2&&!naf(g_afe_upperFlip)&&(_afeBear?hi>=g_afe_upperFlip:lo<=g_afe_upperFlip)){ g_afe_step=3; g_afe_selfReturnDone=true; g_afe_activeDest=g_afe_lowerFlip; }
      if(g_afe_step==3&&!naf(g_afe_lowerFlip)&&(_afeBear?lo<=g_afe_lowerFlip:hi>=g_afe_lowerFlip)){ g_afe_step=4; g_afe_activeDest=g_afe_origin; g_afe_target=g_afe_origin; g_afe_upperFlipRole="Liquidity"; }
      if(g_afe_step==4&&!naf(g_afe_origin)&&(_afeBear?hi>=g_afe_origin:lo<=g_afe_origin)){ g_afe_step=5; g_afe_continuation=true; }
   }

   //==============================================================
   // 1A.10 — FU CONVERSATION (parent FU being sought)
   //==============================================================
   int conv_bias=displayWaveDir_M5!=0?displayWaveDir_M5:fractalStackDir;
   double conv_seekPx=NA,conv_seekSc=0.0; string conv_seekTf="-";
   if(conv_bias!=0){
      if(w_fuValid==1&&!naf(w_fuTip)&&(conv_bias==1?w_fuTip>cl:w_fuTip<cl)){ conv_seekPx=w_fuTip; conv_seekTf="W"; conv_seekSc=nz(w_fuScore); }
      else if(d_fuValid==1&&!naf(d_fuTip)&&(conv_bias==1?d_fuTip>cl:d_fuTip<cl)){ conv_seekPx=d_fuTip; conv_seekTf="D"; conv_seekSc=nz(d_fuScore); }
      else if(h4_fuValid==1&&!naf(h4_fuTip)&&(conv_bias==1?h4_fuTip>cl:h4_fuTip<cl)){ conv_seekPx=h4_fuTip; conv_seekTf="H4"; conv_seekSc=nz(h4_fuScore); }
      else if(h1_fuValid==1&&!naf(h1_fuTip)&&(conv_bias==1?h1_fuTip>cl:h1_fuTip<cl)){ conv_seekPx=h1_fuTip; conv_seekTf="H1"; conv_seekSc=nz(h1_fuScore); }
      else if(m15_fuValid==1&&!naf(m15_fuTip)&&(conv_bias==1?m15_fuTip>cl:m15_fuTip<cl)){ conv_seekPx=m15_fuTip; conv_seekTf="M15"; conv_seekSc=nz(m15_fuScore); }
      else if(m5_fuValid==1&&!naf(m5_fuTip)&&(conv_bias==1?m5_fuTip>cl:m5_fuTip<cl)){ conv_seekPx=m5_fuTip; conv_seekTf="M5"; conv_seekSc=nz(m5_fuScore); }
   }
   double conv_confidence=(conv_bias==0||naf(conv_seekPx))?0.0:fmin2(100.0,conv_seekSc*0.7+fu_recursiveAlign*0.3);

   //==============================================================
   // DIE-3/4 — ENTRY SCORE + CONFLUENCE
   //==============================================================
   double die_entryScore=fmin2((nz(waveModelFit,50.0)*0.20)+(nz(modelConfidence,50.0)*0.20)+(htfAlign==direction&&direction!=0?20.0:htfAlign==0?10.0:0.0)+(nz(liqHeat,0.0)>50?15.0:nz(liqHeat,0.0)*0.30)+((die_anyBullFUActive&&direction==1)||(die_anyBearFUActive&&direction==-1)?15.0:0.0)+(flipzoneStagesComplete>=3?10.0:flipzoneStagesComplete*3.3),100.0);
   bool die_entryFUConfluence=((longSignal&&die_anyBullFUActive)||(shortSignal&&die_anyBearFUActive));
   string die_fuContrib=die_entryFUConfluence?"FU CONFIRMED":(((direction==1&&die_anyBullFUActive&&!longSignal)||(direction==-1&&die_anyBearFUActive&&!shortSignal))?"FU ASSISTED":"FU NOT PRESENT");

   //==============================================================
   // DASHBOARD INTEL — dominance / fusion / cycles / geometry
   //==============================================================
   double _l1_expStrength=expScr_tf1, _l2_expStrength=expScr_tf2;
   string l1_dominantPhase=f_famSimple(f_phaseFamilyCode((int)nz(se15_ph)));
   double l1_modelFit=nz(se15_mf);
   g_l1_confidence=g_l1_confidence+0.4*(nz(se15_mf)-g_l1_confidence); g_l1_confidence=clamp(g_l1_confidence,10,100);
   string l2_dominantPhase=f_famSimple(f_phaseFamilyCode((int)nz(se60_ph)));
   double l2_modelFit=nz(se60_mf);
   g_l2_confidence=g_l2_confidence+0.4*(nz(se60_mf)-g_l2_confidence); g_l2_confidence=clamp(g_l2_confidence,10,100);
   string l3_dominantPhase=f_famMicro(f_phaseFamilyCode((int)nz(se3_ph)));
   double l3_confidence=clamp(nz(se3_mf),10,100);
   string l0_dominantPhase=ie1a_hypFamily; double l0_confidence=ie1a_phaseConfidence;
   int fam_l0=f_phaseFamilyCode((int)nz(se5_ph));
   double l0_dominance=fmin2(nz(se5_wp)*0.45+nz(se5_mf)*0.35+nz(se5_cm)*0.20,100.0);
   double l1_dominance=fmin2(_l1_expStrength*0.35+(expScr_tf1>60?25.0:expScr_tf1*0.40)+liqScr_tf1*0.20+l1_modelFit*0.20,100.0);
   double l2_dominance=fmin2(_l2_expStrength*0.35+(expScr_tf2>60?30.0:expScr_tf2*0.50)+liqScr_tf2*0.15+l2_modelFit*0.20,100.0);
   double l3_dominance=fmin2(nz(se3_mf)*0.60+nz(se3_wp)*0.40,100.0);
   string dominantWaveLevel=(l2_dominance>=l1_dominance&&l2_dominance>=l0_dominance&&l2_dominance>=l3_dominance)?"L2 HTF":(l1_dominance>=l0_dominance&&l1_dominance>=l3_dominance)?"L1 CHILD":(l0_dominance>=l3_dominance)?"L0 PRIMARY":"L3 MICRO";
   bool htfTrendIntact=l2_dominantPhase=="Expansion"&&g_l2_confidence>45.0;
   bool ltfReversalForming=((fam_l0==4||fam_l0==5)||(l3_dominantPhase=="M1 Absorption"||l3_dominantPhase=="M1 Liquidity"))&&!(g_liqg_active&&!(liqg_objArrival&&liqg_trueCHoCH));
   string fusionInterpretation=(htfTrendIntact&&!ltfReversalForming)?"HTF Intact - LTF Expansion Aligned":(htfTrendIntact&&ltfReversalForming)?"HTF Intact - LTF Reversal Forming":(!htfTrendIntact&&ltfReversalForming)?"HTF Weakening - LTF Reversal Confirming":(l2_dominantPhase=="Absorption"&&l1_dominantPhase=="Expansion")?"HTF Absorption - ITF Counter-Bounce":(l2_dominantPhase=="Liquidity"&&(l1_dominantPhase=="Absorption"||fam_l0==5))?"HTF Liq Sweep - Entry Zone Forming":"Mixed - Await Alignment";
   double fusionConfidence=fmin2(g_l2_confidence*0.40+g_l1_confidence*0.30+l0_confidence*0.20+l3_confidence*0.10,100.0);
   double _cycleBaseProg=nz(waveProgress,0.0);
   double cycle1_completion=fmin2((g_entryCycle>=1?60.0:_cycleBaseProg*0.60)+(recursiveComplete&&g_entryCycle>=1?40.0:0.0),100.0);
   double cycle2_completion=fmin2((g_entryCycle>=2?60.0:g_entryCycle>=1?_cycleBaseProg*0.40:0.0)+(recursiveComplete&&g_entryCycle>=2?40.0:0.0),100.0);
   double cycle3_completion=fmin2((g_entryCycle>=3?60.0:g_entryCycle>=2?_cycleBaseProg*0.40:0.0)+(recursiveComplete&&g_entryCycle>=3?40.0:0.0),100.0);
   double cycle4_completion=fmin2((g_entryCycle>=4?60.0:g_entryCycle>=3?_cycleBaseProg*0.40:0.0)+(recursiveComplete&&g_entryCycle>=4?40.0:0.0),100.0);
   string activeCyclePhase=g_entryCycle==0?("Cycle 1 - "+l0_phaseCanon):("Entry Cycle "+IntegerToString(g_entryCycle)+" - "+l0_phaseCanon);
   double geoCapacityScore=fmin2((geoFullConvexityPossible?100.0:geoPartialConvexityPossible?60.0:25.0)*(!naf(flipzoneWidth)?fmax2(0.5,1.0-flipzoneWidth/fmax2(atr*4.0,1e-10)):0.5),100.0);
   string geoCapacityNarrative=geoFullConvexityPossible?"Full Conv - Complete wave expression":geoPartialConvexityPossible?"Partial Conv - Limited but tradeable":"Absorption Only - Expect rapid absorption";


   //==============================================================
   // SECTION 17/19 — FUTURE RETURN ZONE ENGINE
   //==============================================================
   string frz_ownerLayer=dominantWaveLevel;
   bool frz_hasFU_gc=isBullFU_prev||isBearFU_prev;
   bool frz_hasFU_sb=isBullFU||isBearFU;
   bool frz_hasFU=frz_hasFU_gc||frz_hasFU_sb;
   bool frz_fuIsBull=isBullFU_prev||isBullFU;
   bool frz_fuIsBear=isBearFU_prev||isBearFU;
   bool frz_hasImbalance=displacement>dispThresh;
   bool frz_hasLiqClear=liqSweepBull||liqSweepBear||liqVacuum||(obs_LiquidityScore>55.0);
   bool frz_hasDisp=bullImpulse||bearImpulse;
   int frz_rawScore=(frz_hasFU?25:0)+(frz_hasImbalance?25:0)+(frz_hasLiqClear?25:0)+(frz_hasDisp?25:0);
   bool frz_liqResting=liqHeat>60&&!(liqSweepBull||liqSweepBear);
   bool frz_approved=!frz_liqResting;
   string frz_class=frz_rawScore>=76?"Exceptional":frz_rawScore>=51?"Strong":frz_rawScore>=26?"Moderate":"Weak";
   string frz_tier=frz_rawScore>=76?"T1":frz_rawScore>=51?"T2":(frz_rawScore>=26&&frz_hasFU)?"T3":(frz_rawScore>=26&&frz_hasImbalance)?"T4":"-";
   string frz_tierFull=frz_rawScore>=76?"Tier 1 ***":frz_rawScore>=51?"Tier 2 **":(frz_rawScore>=26&&frz_hasFU)?"Tier 3 *":(frz_rawScore>=26&&frz_hasImbalance)?"Tier 4":"-";
   string frz_compStr=(frz_hasFU&&frz_hasImbalance&&frz_hasLiqClear&&frz_hasDisp)?"FU+IMB+LS+DISP":(frz_hasFU&&frz_hasImbalance&&frz_hasLiqClear)?"FU+IMB+LS":(frz_hasFU&&frz_hasImbalance&&frz_hasDisp)?"FU+IMB+DISP":(frz_hasFU&&frz_hasImbalance)?"FU+IMB":(frz_hasFU&&frz_hasLiqClear)?"FU+LS":frz_hasFU?"FU":(frz_hasImbalance&&frz_hasLiqClear)?"IMB+LS":frz_hasImbalance?"IMB":"-";
   int _frz_spawnDir=(direction==1||frz_fuIsBull)&&!(direction==-1||frz_fuIsBear)?1:((direction==-1||frz_fuIsBear)&&!(direction==1||frz_fuIsBull)?-1:(direction!=0?direction:0));
   double _frz_zTop=_frz_spawnDir==1?fmax2(op,cl):hi;
   double _frz_zBot=_frz_spawnDir==1?lo:fmin2(op,cl);
   if(frz_hasFU_gc){ _frz_zTop=_frz_spawnDir==1?pH1:fmax2(pO,pC); _frz_zBot=_frz_spawnDir==1?fmin2(pO,pC):pL1; }
   if(_frz_zTop<=_frz_zBot){ _frz_zTop=fmax2(op,fmax2(cl,hi)); _frz_zBot=fmin2(op,fmin2(cl,lo)); }
   bool _frz_overlaps=false; int _frzExist=ArraySize(g_frz_top);
   for(int oi=0;oi<_frzExist;oi++){
      double ot=g_frz_top[oi],ob=g_frz_bot[oi];
      double ovHi=fmin2(_frz_zTop,ot),ovLo=fmax2(_frz_zBot,ob);
      double ov=fmax2(0.0,ovHi-ovLo); double thisRange=fmax2(_frz_zTop-_frz_zBot,1e-10);
      if(ov/thisRange>0.5){ _frz_overlaps=true; break; }
   }
   bool frz_spawn=showFRZ&&frz_approved&&frz_rawScore>=frz_minScore&&frz_rawScore>0&&(frz_hasFU||frz_hasImbalance)&&_frz_spawnDir!=0&&!_frz_overlaps;
   if(frz_spawn){
      g_frz_totalSpawned++;
      int s=ArraySize(g_frz_top);
      ArrayResize(g_frz_top,s+1);ArrayResize(g_frz_bot,s+1);ArrayResize(g_frz_bar,s+1);ArrayResize(g_frz_dir,s+1);
      ArrayResize(g_frz_score,s+1);ArrayResize(g_frz_class,s+1);ArrayResize(g_frz_tier,s+1);ArrayResize(g_frz_tierF,s+1);
      ArrayResize(g_frz_comp,s+1);ArrayResize(g_frz_owner,s+1);ArrayResize(g_frz_status,s+1);ArrayResize(g_frz_idx,s+1);
      g_frz_top[s]=_frz_zTop; g_frz_bot[s]=_frz_zBot; g_frz_bar[s]=i; g_frz_dir[s]=_frz_spawnDir; g_frz_score[s]=frz_rawScore;
      g_frz_class[s]=frz_class; g_frz_tier[s]=frz_tier; g_frz_tierF[s]=frz_tierFull; g_frz_comp[s]=frz_compStr;
      g_frz_owner[s]=frz_ownerLayer; g_frz_status[s]="Open"; g_frz_idx[s]=g_frz_totalSpawned;
   }
   //--- lifecycle ---
   for(int fi=ArraySize(g_frz_top)-1;fi>=0;fi--){
      double ft=g_frz_top[fi],fb=g_frz_bot[fi]; int fbb=g_frz_bar[fi],fd=g_frz_dir[fi]; string fst=g_frz_status[fi];
      int fage=i-fbb;
      bool terminal=(fst=="Mitigated"||fst=="Invalidated");
      if(!terminal){
         bool wickIn=lo<=ft&&hi>=fb;
         bool closeIn=cl>=fb&&cl<=ft;
         bool invalid=(fd==1&&cl<fb-atr*0.1)||(fd==-1&&cl>ft+atr*0.1);
         string ns=fst;
         if(closeIn) ns="Mitigated"; else if(invalid) ns="Invalidated"; else if(wickIn&&fst=="Open") ns="Partial";
         if(ns!=fst) g_frz_status[fi]=ns;
         fst=ns; terminal=(fst=="Mitigated"||fst=="Invalidated");
      }
      if(terminal||fage>=frz_maxBarsActive){ FrzRemove(fi); }
   }
   //--- ownership tally + best zone ---
   int frz_ownL0=0,frz_ownL1=0,frz_ownL2=0,frz_ownL3=0,frz_activeCount=0,frz_bullCount=0,frz_bearCount=0;
   int frz_bestScore=0; string frz_bestClass="-",frz_bestTier="-",frz_bestComp="-",frz_bestOwner="-",frz_bestStatus="-";
   for(int fk=0;fk<ArraySize(g_frz_score);fk++){
      string own=g_frz_owner[fk],st=g_frz_status[fk]; int sc=g_frz_score[fk],fd2=g_frz_dir[fk];
      bool live=(st=="Open"||st=="Partial");
      if(live){
         frz_activeCount++; if(fd2==1) frz_bullCount++; else frz_bearCount++;
         if(own=="L0 PRIMARY") frz_ownL0++; else if(own=="L1 CHILD") frz_ownL1++; else if(own=="L2 HTF") frz_ownL2++; else frz_ownL3++;
         if(sc>frz_bestScore){ frz_bestScore=sc; frz_bestClass=g_frz_class[fk]; frz_bestTier=g_frz_tierF[fk]; frz_bestComp=g_frz_comp[fk]; frz_bestOwner=own; frz_bestStatus=st; }
      }
   }

   //==============================================================
   // V72 DECISION ARCHITECTURE
   //==============================================================
   int dir3=MapValI(mdir3.t,mdir3.dir,mdir3.n,ct), dir4=MapValI(mdir4.t,mdir4.dir,mdir4.n,ct);
   //--- V72.1 best FRZ zone (open/partial highest) ---
   int v72BestIdx=-1,v72BestSc=-1;
   for(int q=0;q<ArraySize(g_frz_score);q++){ string st=g_frz_status[q]; if(st=="Open"||st=="Partial"){ if(g_frz_score[q]>v72BestSc){ v72BestSc=g_frz_score[q]; v72BestIdx=q; } } }
   double frz_bestZoneTop=v72BestIdx>=0?g_frz_top[v72BestIdx]:NA;
   double frz_bestZoneBot=v72BestIdx>=0?g_frz_bot[v72BestIdx]:NA;
   int    frz_bestZoneDir=v72BestIdx>=0?g_frz_dir[v72BestIdx]:0;
   string frz_bestZoneTier=v72BestIdx>=0?g_frz_tier[v72BestIdx]:"-";
   double frz_bestZoneMid=(!naf(frz_bestZoneTop)&&!naf(frz_bestZoneBot))?(frz_bestZoneTop+frz_bestZoneBot)/2.0:NA;
   double frz_distanceToZone=(frz_activeCount>0&&!naf(frz_bestZoneMid))?MathAbs(cl-frz_bestZoneMid)/fmax2(atr,1e-10):NA;
   bool frz_inProximity=frz_activeCount>0&&!naf(frz_distanceToZone)&&frz_distanceToZone<in_frzProximityATR;
   double frz_resolutionScore=re_resolutionState=="RESOLVED"?90.0:re_resolutionState=="PARTIALLY RESOLVED"?50.0+re_recursiveCompletionScore*0.40:20.0+ede_dissipationProgress*0.30;
   double frz_residualEnergy=fmax2(0.0,100.0-frz_resolutionScore);
   double frz_attractorWeight=frz_activeCount>0?fmin2(frz_residualEnergy*0.50+frz_bestScore*0.30+(frz_bestStatus=="Open"?20.0:frz_bestStatus=="Partial"?10.0:0.0),100.0):0.0;
   bool frz_attractorConvergence=frz_activeCount>0&&!naf(eae_primaryAttractorPrice)&&!naf(frz_bestZoneMid)&&MathAbs(eae_primaryAttractorPrice-frz_bestZoneMid)/fmax2(atr,1e-10)<in_frzConvergenceATR;
   //--- V72.2 RIE ---
   double rot_pressure=fmin2(obs_DecayScore*in_rieW_decay+obs_AbsorptionScore*in_rieW_absorb+(convexityScore>40?convexityScore*in_rieW_convex:0.0)+(obs_LiquidityScore>50?15.0:0.0),100.0);
   double rot_controlStability=fmin2(obs_ExpansionScore*in_rieW_stabExp+(efficiency>effThresh?30.0:efficiency>effThresh*0.7?15.0:0.0)+(ede_state<=2?30.0:ede_state<=3?15.0:0.0),100.0);
   double rot_transferProbability=fmin2(rot_pressure*in_rieW_press+(100.0-rot_controlStability)*in_rieW_stabInv+(re_resolutionState=="UNRESOLVED"?20.0:re_resolutionState=="PARTIALLY RESOLVED"?10.0:0.0),100.0);
   string rot_state=rot_transferProbability>=75?"TRANSFER_IMMINENT":rot_transferProbability>=50?"CONTESTED":rot_transferProbability>=25?"SOFTENING":"STABLE";
   //--- V72.3 MCE ---
   int mce_t1d=l1_dir,mce_t2d=l2_dir,mce_t3d=dir3,mce_t4d=dir4;
   int _mceAll=(mce_t1d==displayWaveDir_M5&&displayWaveDir_M5!=0?1:0)+(mce_t2d==displayWaveDir_M5&&displayWaveDir_M5!=0?1:0)+(mce_t3d==displayWaveDir_M5&&displayWaveDir_M5!=0?1:0)+(mce_t4d==displayWaveDir_M5&&displayWaveDir_M5!=0?1:0);
   int _mceHtf=(mce_t3d==displayWaveDir_M5&&displayWaveDir_M5!=0?1:0)+(mce_t4d==displayWaveDir_M5&&displayWaveDir_M5!=0?1:0);
   int _mceExec=(mce_t1d==displayWaveDir_M5&&displayWaveDir_M5!=0?1:0)+(mce_t2d==displayWaveDir_M5&&displayWaveDir_M5!=0?1:0);
   double mce_alignmentScore=displayWaveDir_M5==0?0.0:(double)_mceAll/4.0*100.0;
   double mce_htfAlignmentScore=displayWaveDir_M5==0?0.0:fmin2(((double)_mceHtf/2.0*100.0)*0.55+fractalCtxScore*0.45,100.0);
   double mce_execAlignmentScore=displayWaveDir_M5==0?0.0:(double)_mceExec/2.0*100.0;
   string mce_htfAlignmentSummary=(mce_htfAlignmentScore>=80&&displayWaveDir_M5==1)?"HTF Bullish Continuation":(mce_htfAlignmentScore>=80&&displayWaveDir_M5==-1)?"HTF Bearish Continuation":(mce_htfAlignmentScore>=60&&rot_transferProbability<40)?"HTF Trend Intact":(mce_htfAlignmentScore>=50&&rot_transferProbability>=60)?"HTF Rotation Developing":mce_htfAlignmentScore<40?"HTF Contested - No Clear Bias":"HTF Developing";
   string mce_execAlignmentSummary=(ie1a_currentPhase=="Demand Return"&&mce_execAlignmentScore>=60)?"Execution Aligned - Long Window":(ie1a_currentPhase=="Supply Return"&&mce_execAlignmentScore>=60)?"Execution Aligned - Short Window":mce_execAlignmentScore<40?"Execution Conflict - Wait":"Execution Developing";
   //--- V72.4 NE ---
   bool _nePhaseExpBull=ie1a_currentPhase=="Expansion"||ie1a_currentPhase=="New High";
   bool _nePhaseExpBear=ie1a_currentPhase=="Expansion"||ie1a_currentPhase=="New Low";
   bool _nePullback=ie1a_currentPhase=="Retracement"||ie1a_currentPhase=="Retracement Pre-Convexity"||ie1a_currentPhase=="Retracement Induction"||ie1a_currentPhase=="Retracement Liquidity";
   string ne_dominantNarrative=displayWaveDir_M5==0?"No Clear Narrative":(displayWaveDir_M5==1&&_nePhaseExpBull&&rot_transferProbability<40)?"Bullish Continuation":(displayWaveDir_M5==-1&&_nePhaseExpBear&&rot_transferProbability<40)?"Bearish Continuation":(displayWaveDir_M5==1&&(_nePullback||ie1a_currentPhase=="Demand Return"))?"Bullish Pullback":(displayWaveDir_M5==-1&&(_nePullback||ie1a_currentPhase=="Supply Return"))?"Bearish Pullback":(displayWaveDir_M5==1&&(rot_transferProbability>=55||ie1a_currentPhase=="Absorption"))?"Bullish Reversal Developing":(displayWaveDir_M5==-1&&(rot_transferProbability>=55||ie1a_currentPhase=="Absorption"))?"Bearish Reversal Developing":(displayWaveDir_M5==1?"Bullish Developing":displayWaveDir_M5==-1?"Bearish Developing":"No Clear Narrative");
   double ne_narrativeStrength=fmin2(mce_alignmentScore*0.40+rot_controlStability*0.30+(re_resolutionState=="RESOLVED"?30.0:re_resolutionState=="PARTIALLY RESOLVED"?15.0:0.0),100.0);
   //--- V72.5 INV ---
   double inv_bullOriginPrice=!naf(point4OriginLow)?point4OriginLow-atr*in_invOriginBuffer:NA;
   double inv_bearOriginPrice=!naf(point4OriginHigh)?point4OriginHigh+atr*in_invOriginBuffer:NA;
   double inv_demandFailPrice=(direction==1&&!naf(flipBot))?flipBot-atr*in_invZoneBuffer:NA;
   double inv_supplyFailPrice=(direction==-1&&!naf(flipTop))?flipTop+atr*in_invZoneBuffer:NA;
   double inv_activeStop=direction==1?nz(inv_demandFailPrice,inv_bullOriginPrice):direction==-1?nz(inv_supplyFailPrice,inv_bearOriginPrice):NA;
   bool inv_invalidated=!naf(inv_activeStop)&&(direction==1?cl<inv_activeStop:direction==-1?cl>inv_activeStop:false);
   double inv_riskInPts=!naf(inv_activeStop)?MathAbs(cl-inv_activeStop):NA;
   //--- V72.6 TE ---
   double eae_tertiaryAttractorPrice=direction==1?fmax2(nz(eae_primaryAttractorPrice,cl),nz(eae_secondaryAttractorPrice,cl))+atr*in_teTertiaryATR:direction==-1?fmin2(nz(eae_primaryAttractorPrice,cl),nz(eae_secondaryAttractorPrice,cl))-atr*in_teTertiaryATR:NA;
   double te_tp1=NA; int _teBestSc=-1;
   if(direction!=0) for(int j2=0;j2<ArraySize(g_frz_score);j2++){ string st2=g_frz_status[j2]; int fd3=g_frz_dir[j2]; if((st2=="Open"||st2=="Partial")&&fd3==direction){ double mid2=(g_frz_top[j2]+g_frz_bot[j2])/2.0; bool beyond=direction==1?mid2>cl:mid2<cl; if(beyond&&g_frz_score[j2]>_teBestSc){ _teBestSc=g_frz_score[j2]; te_tp1=mid2; } } }
   bool te_tp2_valid=!naf(eae_primaryAttractorPrice)&&(direction==1?eae_primaryAttractorPrice>cl:direction==-1?eae_primaryAttractorPrice<cl:false);
   double te_tp2=te_tp2_valid?eae_primaryAttractorPrice:NA;
   bool te_tp3_valid=in_teTertiaryOn&&!naf(eae_tertiaryAttractorPrice)&&(direction==1?eae_tertiaryAttractorPrice>cl:direction==-1?eae_tertiaryAttractorPrice<cl:false);
   double te_tp3=te_tp3_valid?eae_tertiaryAttractorPrice:NA;
   double _teTp1eff=!naf(te_tp1)?te_tp1:te_tp2;   // FRZ-free: fall back to the (network/EAE) attractor target
   double te_rr_tp1=(!naf(_teTp1eff)&&!naf(inv_riskInPts)&&inv_riskInPts>0)?MathAbs(_teTp1eff-cl)/inv_riskInPts:NA;
   bool te_rrGate=!naf(te_rr_tp1)&&te_rr_tp1>=in_rrMinimum;
   string te_expectedPath=(re_resolutionState=="RESOLVED"&&mce_execAlignmentScore>=70)?"Direct":(ie1a_currentPhase=="Demand Return"||ie1a_currentPhase=="Supply Return")?"Direct":rot_transferProbability>50?"Retracement First":re_resolutionState=="UNRESOLVED"?"Range Then Breakout":"Direct";
   //--- V72.7 TQE ---
   double erf_pureConfidence=fmin2(20.0+(re_resolutionState=="RESOLVED"?30.0:re_resolutionState=="PARTIALLY RESOLVED"?20.0:10.0)+eae_primaryAttractorScore*0.30,100.0);
   double frz_entryBonus=(frz_inProximity&&frz_bestZoneDir==direction)?15.0:0.0;
   double tqe_frzQuality=frz_activeCount>0?fmin2(frz_bestScore*0.50+(frz_bestZoneTier=="T1"?40.0:frz_bestZoneTier=="T2"?25.0:frz_bestZoneTier=="T3"?10.0:0.0)+(frz_bestStatus=="Open"?10.0:frz_bestStatus=="Partial"?5.0:0.0)+frz_entryBonus,100.0):0.0;
   double tqe_liqQuality=fmin2(obs_LiquidityScore*0.50+((liqSweepBull||liqSweepBear)?30.0:0.0)+(liqVacuum?20.0:0.0),100.0);
   double tqe_rawScore=ie1a_phaseConfidence*in_tqeW_ie1a+erf_pureConfidence*in_tqeW_erf+tqe_frzQuality*in_tqeW_frz+mce_htfAlignmentScore*in_tqeW_mce+re_recursiveCompletionScore*in_tqeW_re+tqe_liqQuality*in_tqeW_liq;
   string tqe_grade=tqe_rawScore>=in_tqeGradeA1?"A+":tqe_rawScore>=in_tqeGradeA?"A":tqe_rawScore>=in_tqeGradeB?"B":tqe_rawScore>=in_tqeGradeC?"C":"D";
   string tqe_riskLevel=(rot_transferProbability>65||re_resolutionState=="UNRESOLVED")?"HIGH":(rot_transferProbability>35||tqe_rawScore<60)?"MEDIUM":"LOW";
   //--- V72.8 DOE ---
   string doe_bias=(displayWaveDir_M5==1&&mce_htfAlignmentScore>=75&&rot_controlStability>=65)?"Strong Bullish":displayWaveDir_M5==1?"Bullish":(displayWaveDir_M5==-1&&mce_htfAlignmentScore>=75&&rot_controlStability>=65)?"Strong Bearish":displayWaveDir_M5==-1?"Bearish":"Neutral";
   string doe_action=inv_invalidated?"No Trade":(g_liqg_active&&!(liqg_objArrival&&liqg_trueCHoCH))?"Wait":!erf_entryGate?"Wait":!te_rrGate?"Wait":(ie1a_currentPhase=="Demand Return"&&direction==1)?"Long":(ie1a_currentPhase=="Supply Return"&&direction==-1)?"Short":"Wait";
   double doe_confidence=fmin2(modelConfidence*0.50+mce_alignmentScore*0.25+phaseConfidence*0.25,frz_attractorConvergence?in_doeCapConv:in_doeCapBase);
   string doe_tradeType=(ne_dominantNarrative=="Bullish Continuation"||ne_dominantNarrative=="Bearish Continuation")?"Continuation":(ne_dominantNarrative=="Bullish Pullback"||ne_dominantNarrative=="Bearish Pullback")?"Pullback":(ie1a_currentPhase=="New High"||ie1a_currentPhase=="New Low")?"Breakout":"Wait";
   double doe_entryMid=(frz_inProximity&&frz_bestZoneDir==direction&&!naf(frz_bestZoneMid))?frz_bestZoneMid:((ie1a_currentPhase=="Demand Return"||ie1a_currentPhase=="Supply Return")&&!naf(point4OriginHigh)&&!naf(point4OriginLow))?(point4OriginHigh+point4OriginLow)/2.0:cl;
   double doe_entryHigh=!naf(doe_entryMid)?doe_entryMid+atr*0.30:NA;
   double doe_entryLow=!naf(doe_entryMid)?doe_entryMid-atr*0.30:NA;
   string doe_entryTrigger=frz_inProximity?"Limit":(ie1a_currentPhase=="Demand Return"||ie1a_currentPhase=="Supply Return")?"LimitOnRetest":"Market";
   //--- V72.8b OPPORTUNITY ---
   double _opStruct=displayWaveDir_M5==0?0.0:(direction==displayWaveDir_M5?100.0:70.0);
   double _opLifecycle=(ie1a_currentPhase=="Demand Return"||ie1a_currentPhase=="Supply Return")?100.0:(ie1a_currentPhase=="Absorption"||_nePullback)?70.0:(ie1a_currentPhase=="New High"||ie1a_currentPhase=="New Low")?55.0:(ie1a_currentPhase=="Expansion"||ie1a_currentPhase=="Expansion Pre-Convexity"||ie1a_currentPhase=="Expansion Induction"||ie1a_currentPhase=="Expansion Liquidity")?45.0:ie1a_currentPhase=="Point 4 Origin"?25.0:0.0;
   double _opReturn=naf(frz_distanceToZone)?(frz_inProximity?100.0:0.0):fmax2(0.0,100.0-frz_distanceToZone*40.0);
   double _opDisplace=fmax2(re_recursiveCompletionScore,ede_dissipationProgress);
   double _opConfluence=(frz_attractorConvergence?50.0:0.0)+((frz_inProximity&&frz_bestZoneDir==displayWaveDir_M5)?50.0:0.0);
   double oppProgressRaw=_opStruct*0.25+_opLifecycle*0.15+rot_transferProbability*0.15+_opReturn*0.15+mce_htfAlignmentScore*0.10+_opDisplace*0.10+_opConfluence*0.10;
   bool oppVeto=displayWaveDir_M5==0||inv_invalidated;
   double oppProgress=oppVeto?0.0:oppProgressRaw;
   bool _opInZone=frz_inProximity&&frz_bestZoneDir==displayWaveDir_M5;
   string oppState=oppVeto?"STAND DOWN":(oppProgress>=95&&_opInZone)?"TRADE ACTIVE":oppProgress>=85?"PREPARE TO EXECUTE":oppProgress>=60?"OPPORTUNITY CONFIRMING":oppProgress>=20?"OPPORTUNITY FORMING":"STAND DOWN";
   string _cmdDirWord=displayWaveDir_M5==1?"Bullish":displayWaveDir_M5==-1?"Bearish":"Neutral";
   string cmd_narrative=displayWaveDir_M5==0?"No directional thesis":inv_invalidated?_cmdDirWord+" thesis invalidated":(ie1a_currentPhase=="Demand Return"||ie1a_currentPhase=="Supply Return")?_cmdDirWord+" return-to-zone - execution window":(rot_transferProbability>=55||ie1a_currentPhase=="Absorption")?_cmdDirWord+" reversal developing":(_nePullback||ie1a_currentPhase=="Retracement")?_cmdDirWord+" pullback in progress":(ie1a_currentPhase=="Expansion"||ie1a_currentPhase=="New High"||ie1a_currentPhase=="New Low")?_cmdDirWord+" continuation":_cmdDirWord+" developing";
   //--- registries ---
   V72Registries(i,direction,ie1a_currentPhase,re_recursiveCompletionScore,ede_expansionEnergy,ede_state,ede_liquidationBecomingDirectional,re_resolutionState);
   //--- traceability ---
   string trc_decisionSource="IE1A:"+ie1a_currentPhase+" | TQE:"+tqe_grade+" | NE:"+ne_dominantNarrative;
   string trc_confidenceBreakdown="IE1A:"+R0(ie1a_phaseConfidence)+" ERF:"+R0(erf_pureConfidence)+" FRZ:"+R0(tqe_frzQuality)+" MCE:"+R0(mce_htfAlignmentScore)+" RE:"+R0(re_recursiveCompletionScore)+" LIQ:"+R0(tqe_liqQuality);
   string trc_waveChain="Wave#"+IntegerToString(g_wr_activeId)+" (parent #"+IntegerToString(g_wr_activeParent)+", root #"+IntegerToString(g_wr_activeRoot)+")";
   //--- TPL destination ---
   double tpl_mainTarget=NA,tpl_confidence=0.0; string tpl_source="RANGEBOUND",tpl_winnerClass="Weak";
   TPLDestination(cl,atr,displayWaveDir_M5,fractalStackDir,liveHtfAlign,erf_tradeReadiness,
                  fu_winTarget,fu_winSrc,fu_winBand,fu_recursiveAlign,
                  frz_activeCount,frz_bestZoneMid,eae_primaryAttractorPrice,eae_primaryAttractorScore,
                  tpl_mainTarget,tpl_source,tpl_confidence,tpl_winnerClass);

   //==============================================================
   // STORE DISPLAY STATE (last bar drives rendering)
   //==============================================================
   if(isLast){
      cur_ie1aPhase=ie1a_currentPhase; cur_currentDisplayPhase=currentDisplayPhase; cur_hypFamily=ie1a_hypFamily;
      cur_dirM1=m1_dir; cur_dirM3=l3_dir; cur_dirM5=l0_dir; cur_dirM15=l1_dir; cur_dirH1=l2_dir; cur_dirH4=l4_dir;
      cur_l0phase=l0_phaseCanon; cur_l1phase=l1_phaseCanon; cur_l2phase=l2_phaseCanon; cur_l3phase=l3_phaseCanon; cur_l4phase=l4_phaseCanon;
      cur_phaseConfidence=phaseConfidence; cur_phaseIntegrity=phaseIntegrity; cur_phaseProgress=phaseProgress; cur_ie1aPhaseConf=ie1a_phaseConfidence;
      cur_fractalStackScore=fractalStackScore; cur_fractalCtxScore=fractalCtxScore; cur_fractalStackDir=fractalStackDir;
      cur_liveWaveDir=liveWaveDir; cur_liveHtfAlign=liveHtfAlign;
      cur_liqgActive=g_liqg_active; cur_liqgTitle=liqg_title; cur_liqgSub=liqg_subPhase; cur_liqgArr=liqg_arrTx; cur_liqgTarget=g_liqg_target; cur_liqgDistPct=liqg_distPct;
      cur_atr=atr; cur_velocity=velocity; cur_acceleration=acceleration; cur_efficiency=efficiency; cur_displacement=displacement;
      cur_velocityScore=velocityScore; cur_convexityScore=convexityScore; cur_expansionScore=expansionScore;
      cur_obsExp=obs_ExpansionScore; cur_obsDecay=obs_DecayScore; cur_obsCurv=obs_CurvatureScore; cur_obsAbs=obs_AbsorptionScore; cur_obsLiq=obs_LiquidityScore;
      cur_physicsConsensus=physicsConsensus; cur_physicsMax=physicsMax; cur_physicsDiff=physicsDiff; cur_volRegime=volRegime; cur_volRatio=volRatio;
      cur_bExp=d_expansionBelief; cur_bConv=d_convexityBelief; cur_bCreat=d_creationBelief; cur_bAbs=d_absorptionBelief; cur_bRetr=d_retracementBelief; cur_bDR=d_demandReturnBelief;
      cur_pxExp=expansionProximity; cur_pxConv=convexityProximity; cur_pxCreat=creationProximity; cur_pxAbs=absorptionProximity; cur_pxRetr=retracementProximity; cur_pxDR=demandReturnProximity;
      cur_primaryHyp=primaryHypothesis; cur_primaryHypConf=primaryHypothesisConf;
      cur_hypLE=hyp_LateExpansion_N; cur_hypEC=hyp_EarlyConvexity_N; cur_hypCF=hyp_CreationForming_N; cur_hypAA=hyp_AbsorptionActive_N; cur_hypRA=hyp_RetracementActive_N; cur_hypDR2=hyp_DemandReturn_N;
      cur_expectedNextPhase=expectedNextPhase; cur_expectedNextProb=expectedNextProb; cur_predReliability=predReliability; cur_predAcc10=predAcc10; cur_predAcc25=predAcc25;
      cur_modelConfidence=modelConfidence; cur_waveDeviation=waveDeviation; cur_deviationAlert=deviationAlert; cur_m1WarningScore=m1WarningScore; cur_m1Warning=m1Warning;
      cur_htfExpBelief=htf_ExpBelief; cur_htfConvBelief=htf_ConvBelief; cur_htfAbsBelief=htf_AbsBelief; cur_htfLiqBelief=htf_LiqBelief;
      cur_contProb=contProb; cur_finalProb=finalProb; cur_grade=grade; cur_gradeCol=gradeCol;
      cur_structBias=structBias; cur_htfAlign=htfAlign; cur_resonance=resonance;
      cur_liqHeat=liqHeat; cur_liqZone=liqZone; cur_liqVacuum=liqVacuum;
      cur_cycleCapacity=cycleCapacity; cur_geoCapNarr=geoCapacityNarrative; cur_geoCapScore=geoCapacityScore; cur_availableSpace=availableSpace; cur_zonePrecision=zonePrecision;
      cur_edeState=ede_state; cur_edeCleaning=ede_cleaningState; cur_edeDissProg=ede_dissipationProgress; cur_edeExpEnergy=ede_expansionEnergy;
      cur_reResolution=re_resolutionState; cur_reRecursiveCompletion=re_recursiveCompletionScore; cur_reResidual=re_residualEnergyScore; cur_reRevisit=re_revisitProbability;
      cur_eaeEnergyState=eae_energyState; cur_eaePrimaryLabel=eae_primaryAttractorLabel; cur_eaePrimaryPrice=eae_primaryAttractorPrice; cur_eaePrimaryScore=eae_primaryAttractorScore; cur_eaeSecondaryPrice=eae_secondaryAttractorPrice;
      cur_erfTradeReadiness=erf_tradeReadiness; cur_erfConfidence=erf_confidence; cur_erfEntryGate=erf_entryGate; cur_erfSuppressRotation=erf_suppressRotation;
      cur_expansionProbability=expansionProbability; cur_reversalProbability=reversalProbability; cur_tradeReadiness=tradeReadiness;
      cur_directiveStr=directiveStr; cur_directiveCol=directiveCol; cur_liveDirective=liveDirective;
      cur_buyProb=buyProb; cur_sellProb=sellProb; cur_netEdgeAdjusted=netEdgeAdjusted; cur_buyScore=buyScore; cur_sellScore=sellScore;
      cur_dieEntryScore=die_entryScore; cur_dieFuContrib=die_fuContrib; cur_longSignal=longSignal; cur_shortSignal=shortSignal; cur_tradeDir=g_tradeDir;
      cur_entryCycle=g_entryCycle; cur_waveDepth=g_waveDepth; cur_recursiveComplete=recursiveComplete;
      cur_cyc1=cycle1_completion; cur_cyc2=cycle2_completion; cur_cyc3=cycle3_completion; cur_cyc4=cycle4_completion; cur_activeCyclePhase=activeCyclePhase;
      cur_l0domPhase=l0_dominantPhase; cur_l1domPhase=l1_dominantPhase; cur_l2domPhase=l2_dominantPhase; cur_l3domPhase=l3_dominantPhase;
      cur_l0conf=l0_confidence; cur_l1conf=g_l1_confidence; cur_l2conf=g_l2_confidence; cur_l3conf=l3_confidence;
      cur_l0dom=l0_dominance; cur_l1dom=l1_dominance; cur_l2dom=l2_dominance; cur_l3dom=l3_dominance;
      cur_dominantWaveLevel=dominantWaveLevel; cur_fusionInterp=fusionInterpretation; cur_fusionConfidence=fusionConfidence;
      cur_frzActive=frz_activeCount; cur_frzBull=frz_bullCount; cur_frzBear=frz_bearCount; cur_frzBest=frz_bestScore;
      cur_frzL0=frz_ownL0; cur_frzL1=frz_ownL1; cur_frzL2=frz_ownL2; cur_frzL3=frz_ownL3;
      cur_frzBestClass=frz_bestClass; cur_frzBestTier=frz_bestTier; cur_frzBestComp=frz_bestComp; cur_frzBestOwner=frz_bestOwner; cur_frzBestStatus=frz_bestStatus;
      cur_frzBestTop=frz_bestZoneTop; cur_frzBestBot=frz_bestZoneBot; cur_frzBestMid=frz_bestZoneMid; cur_frzBestDir=frz_bestZoneDir;
      cur_anyBullFU=die_anyBullFUActive; cur_anyBearFU=die_anyBearFUActive; cur_fuWinTarget=fu_winTarget; cur_fuWinBand=fu_winBand; cur_fuRecursiveAlign=fu_recursiveAlign; cur_fuWinSrc=fu_winSrc;
      cur_convSeekPx=conv_seekPx; cur_convSeekSc=conv_seekSc; cur_convConfidence=conv_confidence; cur_convSeekTf=conv_seekTf;
      cur_rotState=rot_state; cur_rotTransfer=rot_transferProbability; cur_rotControl=rot_controlStability;
      cur_mceAlign=mce_alignmentScore; cur_mceHtfAlign=mce_htfAlignmentScore; cur_mceExecAlign=mce_execAlignmentScore; cur_mceHtfSummary=mce_htfAlignmentSummary; cur_mceExecSummary=mce_execAlignmentSummary;
      cur_neNarrative=ne_dominantNarrative; cur_neStrength=ne_narrativeStrength;
      cur_invActiveStop=inv_activeStop; cur_invRisk=inv_riskInPts; cur_invInvalidated=inv_invalidated;
      cur_teTp1=te_tp1; cur_teTp2=te_tp2; cur_teTp3=te_tp3; cur_teRR=te_rr_tp1; cur_teExpectedPath=te_expectedPath;
      cur_tqeGrade=tqe_grade; cur_tqeRisk=tqe_riskLevel; cur_tqeRaw=tqe_rawScore;
      cur_doeBias=doe_bias; cur_doeAction=doe_action; cur_doeTradeType=doe_tradeType; cur_doeTrigger=doe_entryTrigger; cur_doeConfidence=doe_confidence; cur_doeEntryMid=doe_entryMid; cur_doeEntryHigh=doe_entryHigh; cur_doeEntryLow=doe_entryLow;
      cur_oppProgress=oppProgress; cur_oppState=oppState; cur_cmdNarrative=cmd_narrative;
      cur_tplMainTarget=tpl_mainTarget; cur_tplConfidence=tpl_confidence; cur_tplSource=tpl_source; cur_tplWinnerClass=tpl_winnerClass;
      cur_trcDecision=trc_decisionSource; cur_trcConf=trc_confidenceBreakdown; cur_trcWaveChain=trc_waveChain;
   }
   g_prevDirection=direction; g_prevEntryCycle=g_entryCycle; g_prev_ede_state=ede_state; g_prev_LBD=ede_liquidationBecomingDirectional;
}


//==================================================================
// HELPER FUNCTIONS referenced by ProcessBar
//==================================================================
double f_idealSim(const double eO,const double dO,const double vO,const double cO,
                  const double eI,const double dI,const double vI,const double cI)
{
   double diff=MathPow(eO-eI,2)+MathPow(dO-dI,2)+MathPow(vO-vI,2)+MathPow(cO-cI,2);
   return(fmax2(0.0,100.0*(1.0-diff/4.0)));
}
double PredAcc(const int n)
{
   int cnt=MathMin(n,g_predTotalIdx); int sum=0; int start=MathMax(0,g_predTotalIdx-cnt);
   if(cnt>0) for(int q=start;q<g_predTotalIdx;q++) sum+=g_predOutcomes[q%100];
   return(cnt>0?(double)sum/(double)cnt*100.0:50.0);
}
double FindInducPrice(const double &h[],const double &l[],const int curIdx,const int anchorRefBar,
                      const double top,const double bot,const int lookback)
{
   if(anchorRefBar<0) return(NA);
   int maxI=MathMin(lookback,curIdx-anchorRefBar); if(maxI<1) return(NA);
   double best=NA,bestDist=NA;
   for(int ii=1;ii<=maxI;ii++){ int idx=curIdx-ii; if(idx<0) break;
      if(h[idx]<top && l[idx]>bot){ double dd=MathAbs((double)((curIdx-ii)-anchorRefBar)); if(naf(bestDist)||dd<bestDist){ bestDist=dd; best=(h[idx]+l[idx])/2.0; } } }
   return(best);
}
void FuPush(const double top,const double bot,const int birthBar,const int dir)
{
   int s=ArraySize(g_fu_top);
   ArrayResize(g_fu_top,s+1);ArrayResize(g_fu_bot,s+1);ArrayResize(g_fu_birthBar,s+1);ArrayResize(g_fu_dir,s+1);ArrayResize(g_fu_state,s+1);
   g_fu_top[s]=top; g_fu_bot[s]=bot; g_fu_birthBar[s]=birthBar; g_fu_dir[s]=dir; g_fu_state[s]="Fresh";
   if(ArraySize(g_fu_top)>300){ ArrayRemove(g_fu_top,0,1);ArrayRemove(g_fu_bot,0,1);ArrayRemove(g_fu_birthBar,0,1);ArrayRemove(g_fu_dir,0,1);ArrayRemove(g_fu_state,0,1); }
}
void FuRemove(const int idx)
{
   ArrayRemove(g_fu_top,idx,1);ArrayRemove(g_fu_bot,idx,1);ArrayRemove(g_fu_birthBar,idx,1);ArrayRemove(g_fu_dir,idx,1);ArrayRemove(g_fu_state,idx,1);
}
void FrzRemove(const int idx)
{
   ArrayRemove(g_frz_top,idx,1);ArrayRemove(g_frz_bot,idx,1);ArrayRemove(g_frz_bar,idx,1);ArrayRemove(g_frz_dir,idx,1);
   ArrayRemove(g_frz_score,idx,1);ArrayRemove(g_frz_class,idx,1);ArrayRemove(g_frz_tier,idx,1);ArrayRemove(g_frz_tierF,idx,1);
   ArrayRemove(g_frz_comp,idx,1);ArrayRemove(g_frz_owner,idx,1);ArrayRemove(g_frz_status,idx,1);ArrayRemove(g_frz_idx,idx,1);
}
int IndexOfInt(const int &arr[],const int v){ for(int q=0;q<ArraySize(arr);q++) if(arr[q]==v) return(q); return(-1); }

void V72Registries(const int i,const int direction,const string phase,const double reCompletion,
                    const double edeExpEnergy,const int edeState,const bool edeLBD,const string reState)
{
   int prevDir=g_prevDirection, prevCycle=g_prevEntryCycle;
   bool died=direction==0 && prevDir!=0;
   bool newRoot=(direction!=0&&prevDir==0)||(direction!=0&&prevDir!=0&&direction!=prevDir);
   bool newChild=direction!=0&&g_entryCycle>prevCycle&&!newRoot;
   if(died&&g_wr_activeId>0){ int di=IndexOfInt(g_wr_id,g_wr_activeId); if(di>=0){ g_wr_death[di]=i; g_wr_deathPh[di]=phase; g_wr_resScore[di]=reCompletion; } g_wr_activeId=0; g_wr_activeParent=0; g_wr_activeRoot=0; }
   if(newRoot||newChild){
      int newId=g_wr_nextId; g_wr_nextId++;
      int parent=newChild?g_wr_activeId:0;
      int root=(newChild&&g_wr_activeRoot>0)?g_wr_activeRoot:newId;
      int depth=newChild?MathMax(0,g_entryCycle):0;
      int s=ArraySize(g_wr_id);
      ArrayResize(g_wr_id,s+1);ArrayResize(g_wr_parent,s+1);ArrayResize(g_wr_root,s+1);ArrayResize(g_wr_birth,s+1);ArrayResize(g_wr_death,s+1);
      ArrayResize(g_wr_spawnPh,s+1);ArrayResize(g_wr_deathPh,s+1);ArrayResize(g_wr_peak,s+1);ArrayResize(g_wr_resScore,s+1);ArrayResize(g_wr_depth,s+1);
      g_wr_id[s]=newId; g_wr_parent[s]=parent; g_wr_root[s]=root; g_wr_birth[s]=i; g_wr_death[s]=-1;
      g_wr_spawnPh[s]=phase; g_wr_deathPh[s]=""; g_wr_peak[s]=edeExpEnergy; g_wr_resScore[s]=0.0; g_wr_depth[s]=depth;
      g_wr_activeId=newId; g_wr_activeParent=parent; g_wr_activeRoot=root;
      if(ArraySize(g_wr_id)>50){ ArrayRemove(g_wr_id,0,1);ArrayRemove(g_wr_parent,0,1);ArrayRemove(g_wr_root,0,1);ArrayRemove(g_wr_birth,0,1);ArrayRemove(g_wr_death,0,1);ArrayRemove(g_wr_spawnPh,0,1);ArrayRemove(g_wr_deathPh,0,1);ArrayRemove(g_wr_peak,0,1);ArrayRemove(g_wr_resScore,0,1);ArrayRemove(g_wr_depth,0,1); }
   }
   if(g_wr_activeId>0){ int ai=IndexOfInt(g_wr_id,g_wr_activeId); if(ai>=0&&edeExpEnergy>g_wr_peak[ai]) g_wr_peak[ai]=edeExpEnergy; }
   //--- delivery registry ---
   bool dwrSpawn=(edeState==4&&g_prev_ede_state!=4)||(edeLBD&&!g_prev_LBD);
   if(dwrSpawn){
      int did=g_dwr_nextId; g_dwr_nextId++;
      int s=ArraySize(g_dwr_id);
      ArrayResize(g_dwr_id,s+1);ArrayResize(g_dwr_root,s+1);ArrayResize(g_dwr_start,s+1);ArrayResize(g_dwr_end,s+1);ArrayResize(g_dwr_energy,s+1);ArrayResize(g_dwr_res,s+1);ArrayResize(g_dwr_cycle,s+1);
      g_dwr_id[s]=did; g_dwr_root[s]=g_wr_activeRoot; g_dwr_start[s]=i; g_dwr_end[s]=-1; g_dwr_energy[s]=edeExpEnergy; g_dwr_res[s]=reState; g_dwr_cycle[s]=g_entryCycle;
      g_dwr_activeId=did;
      if(ArraySize(g_dwr_id)>50){ ArrayRemove(g_dwr_id,0,1);ArrayRemove(g_dwr_root,0,1);ArrayRemove(g_dwr_start,0,1);ArrayRemove(g_dwr_end,0,1);ArrayRemove(g_dwr_energy,0,1);ArrayRemove(g_dwr_res,0,1);ArrayRemove(g_dwr_cycle,0,1); }
   }
   if(g_dwr_activeId>0){ int dwi=IndexOfInt(g_dwr_id,g_dwr_activeId); if(dwi>=0){ g_dwr_res[dwi]=reState; if(reState=="RESOLVED"&&g_dwr_end[dwi]==-1) g_dwr_end[dwi]=i; } }
}

string TplClass(const double s){ return(s>=92?"A+++":s>=85?"A++":s>=78?"A+":s>=68?"A":s>=55?"B":s>=40?"C":"Weak"); }

void TPLDestination(const double cl,const double atr,const int bias,const int fractalStackDir,const int liveHtfAlign,
                    const double erfReady,const double fuWinTarget,const string fuWinSrc,const double fuWinBand,const double fuRecursiveAlign,
                    const int frzActive,const double frzBestMid,const double eaePrice,const double eaeScore,
                    double &mainTarget,string &source,double &confidence,string &winnerClass)
{
   double bestScore=0.0,bestPrice=NA; string bestType="-";
   //--- FU candles ---
   if(bias!=0){
      for(int q=0;q<ArraySize(g_fu_top);q++){
         double fmid=(g_fu_top[q]+g_fu_bot[q])/2.0; int fdir=g_fu_dir[q]; string fst=g_fu_state[q];
         if(fst!="Invalidated"&&(bias==1?fmid>cl:fmid<cl)){
            double ov=(frzActive>0&&!naf(frzBestMid)&&MathAbs(fmid-frzBestMid)/fmax2(atr,1e-10)<1.0)?12.0:0.0;
            double b=(fst=="Fresh"||fst=="Active")?82.0:(fst=="Interacting")?76.0:70.0;
            double dpen=fmin2(MathAbs(cl-fmid)/fmax2(atr,1e-10)*2.0,22.0);
            double al=(fdir==fractalStackDir&&fractalStackDir!=0?8.0:0.0)+(fdir==liveHtfAlign&&liveHtfAlign!=0?6.0:0.0);
            double sc=fmin2(b+ov+al+erfReady*0.06-dpen,100.0);
            if(sc>bestScore){ bestScore=sc; bestPrice=fmid; bestType=ov>0?"FU + imbalance overlap":(fst=="Interacting")?"Residual FU":"FU candle"; }
         }
      }
   }
   //--- FU wick pool magnet + band ---
   if(bias!=0&&!naf(fuWinTarget)&&(bias==1?fuWinTarget>cl:fuWinTarget<cl)){
      double dpen=fmin2(MathAbs(cl-fuWinTarget)/fmax2(atr,1e-10)*1.5,14.0);
      double sc=fmin2(96.0+fuRecursiveAlign*0.04-dpen,100.0);
      if(sc>bestScore){ bestScore=sc; bestPrice=fuWinTarget; bestType=fuWinSrc+" (magnet)"; }
   }
   if(bias!=0&&!naf(fuWinBand)&&(bias==1?fuWinBand>cl:fuWinBand<cl)){
      if(90.0>bestScore){ bestScore=90.0; bestPrice=fuWinBand; bestType="FU induction band"; }
   }
   //--- FRZ zones ---
   if(bias!=0){
      for(int q=0;q<ArraySize(g_frz_top);q++){ string st=g_frz_status[q]; if(st=="Open"||st=="Partial"){
         double zmid=(g_frz_top[q]+g_frz_bot[q])/2.0; int zdir=g_frz_dir[q];
         if(bias==1?zmid>cl:zmid<cl){
            double dpen=fmin2(MathAbs(cl-zmid)/fmax2(atr,1e-10)*2.0,22.0);
            double al=(zdir==fractalStackDir&&fractalStackDir!=0?8.0:0.0)+(zdir==liveHtfAlign&&liveHtfAlign!=0?6.0:0.0);
            double sc=fmin2(g_frz_score[q]*0.85+al+erfReady*0.06-dpen,100.0);
            if(sc>bestScore){ bestScore=sc; bestPrice=zmid; bestType="FRZ "+g_frz_tier[q]; }
         } } }
   }
   //--- EAE attractor ---
   bool attOK=!naf(eaePrice)&&bias!=0&&(bias==1?eaePrice>cl:eaePrice<cl);
   if(attOK){ double sc=fmin2(eaeScore*0.45+(eaeScore>=70?6.0:0.0),100.0); if(sc>bestScore){ bestScore=sc; bestPrice=eaePrice; bestType="Flip / residual"; } }
   //--- resolve ---
   winnerClass=TplClass(bestScore); confidence=bestScore;
   if(bestScore>=55){ mainTarget=bestPrice; source=bestType; } else { mainTarget=NA; source="RANGEBOUND"; }
}


//==================================================================
// STATE RESET + HTF ENGINE BUILDER
//==================================================================
void ResetState()
{
   g_lastPivHigh=NA;g_prevPivHigh=NA;g_lastPivLow=NA;g_prevPivLow=NA;g_structBias=0;
   g_prevSwingHigh=NA;g_prevSwingLow=NA;g_currSwingHigh=NA;g_currSwingLow=NA;
   g_lastPivotPrice=NA;g_prevPivotPrice=NA;g_lastPivotBar=-1;g_prevPivotBar=-1;g_lastPivotDir=0;g_prevPivotDir=0;
   g_direction=0;g_flipTop=NA;g_flipBot=NA;g_obBirthBar=-1;g_barsInZone=0;g_contBar=-1;
   g_point4OriginHigh=NA;g_point4OriginLow=NA;g_point4OriginBar=-1;
   g_flipzoneInducPrice=NA;g_flipzoneInducLow=NA;g_flipzoneInducHigh=NA;
   g_inducExpOriginHigh=NA;g_inducExpExtremeLow=NA;g_inducExpOriginLow=NA;g_inducExpExtremeHigh=NA;
   g_inducRetrOriginHigh=NA;g_inducRetrExtremeLow=NA;g_inducRetrOriginLow=NA;g_inducRetrExtremeHigh=NA;
   g_inducZoneLow=NA;g_inducZoneHigh=NA;g_cycleHigh=NA;g_cycleLow=NA;
   g_waveGeneration=0;g_entryCycle=0;g_isRecursiveWave=false;g_waveDepth=0;g_lastSpawnDir=0;g_recursiveComplete=false;
   for(int k=0;k<4;k++){ g_cycObTop[k]=NA;g_cycObBot[k]=NA;g_cycFlipTop[k]=NA;g_cycFlipBot[k]=NA;g_cycP4High[k]=NA;g_cycP4Low[k]=NA;g_cycStartBar[k]=-1;g_cycDir[k]=0; }
   g_liqHeat=0;g_nearFlipzone=false;g_convexityMaturity=0;g_waveProgress=30;g_waveModelFit=50;
   g_expansionBelief=0;g_convexityBelief=0;g_creationBelief=0;g_absorptionBelief=0;g_retracementBelief=0;g_demandReturnBelief=0;g_modelConfidence=50;
   g_inductionEvidence=false;g_preConvEvidence=false;g_closeInside=false;g_m1AbsorptionEmer=false;g_m1ConvexityEmer=false;g_m1LiquidityEmer=false;
   ArrayInitialize(g_predOutcomes,0);g_predTotalIdx=0;g_lastExpectedPhase="Point 4 Origin";g_lastIE1APhase="Point 4 Origin";
   g_liqg_active=false;g_liqg_isRetr=false;g_liqg_dir=0;g_liqg_target=NA;g_liqg_initDist=NA;g_liqg_absorbUnlocked=false;
   g_recursiveJustFired=false;g_recursiveFiredBar=-1;
   ArrayFree(g_liqLevels);ArrayFree(g_liqWeights);ArrayFree(g_liqAges);ArrayFree(g_liqTypes);
   g_lastSignalBar=-1;g_lastLongBar=-1;g_lastShortBar=-1;g_engineArmed=true;
   g_tradeDir=0;g_exitFiredBar=-1;g_prevEnergy=0;g_prevDirection=0;g_prevEntryCycle=0;g_prev_ede_state=0;g_prev_LBD=false;
   ArrayFree(g_fu_top);ArrayFree(g_fu_bot);ArrayFree(g_fu_birthBar);ArrayFree(g_fu_dir);ArrayFree(g_fu_state);
   g_fuw_tip=NA;g_fuw_bodyHigh=NA;g_fuw_bodyLow=NA;g_fuw_mid=NA;g_fuw_mid38=NA;g_fuw_mid62=NA;g_fuw_dir=0;g_fuw_leftPool=NA;g_fuw_bar=-1;g_fuw_valid=false;g_fuw_strength=NA;
   g_afe_step=0;g_afe_origin=NA;g_afe_originDir=0;g_afe_upperFlip=NA;g_afe_lowerFlip=NA;g_afe_upperFlipRole="-";g_afe_activeDest=NA;g_afe_target=NA;g_afe_selfReturnDone=false;g_afe_continuation=false;
   ArrayFree(g_frz_top);ArrayFree(g_frz_bot);ArrayFree(g_frz_bar);ArrayFree(g_frz_dir);ArrayFree(g_frz_score);
   ArrayFree(g_frz_class);ArrayFree(g_frz_tier);ArrayFree(g_frz_tierF);ArrayFree(g_frz_comp);ArrayFree(g_frz_owner);ArrayFree(g_frz_status);ArrayFree(g_frz_idx);
   g_frz_totalSpawned=0;
   g_die_clusterCount=0;g_die_clusterStartBar=-1;g_die_clusterBestScore=0;g_die_inCluster=false;g_die_objMade=false;g_die_absUnlocked=false;
   g_l1_confidence=50;g_l2_confidence=50;
   ArrayFree(g_wr_id);ArrayFree(g_wr_parent);ArrayFree(g_wr_root);ArrayFree(g_wr_birth);ArrayFree(g_wr_death);ArrayFree(g_wr_depth);ArrayFree(g_wr_spawnPh);ArrayFree(g_wr_deathPh);ArrayFree(g_wr_peak);ArrayFree(g_wr_resScore);
   g_wr_nextId=1;g_wr_activeId=0;g_wr_activeParent=0;g_wr_activeRoot=0;
   ArrayFree(g_dwr_id);ArrayFree(g_dwr_root);ArrayFree(g_dwr_start);ArrayFree(g_dwr_end);ArrayFree(g_dwr_cycle);ArrayFree(g_dwr_energy);ArrayFree(g_dwr_res);
   g_dwr_nextId=1;g_dwr_activeId=0;
   g_htfBias1=0;g_htfBias2=0;
   ArrayFree(g_atrChart);ArrayFree(g_volChart);ArrayFree(g_velHist);
}

void BuildHTFEngines()
{
   ComputeSE(PERIOD_M1, HTF_BARS, pivotLen,structLen,atrLen,effThresh,dispThresh,convMult,impulseAtrMult,chochBufferATR,effLen, se1);
   ComputeSE(PERIOD_M3, HTF_BARS, pivotLen,structLen,atrLen,effThresh,dispThresh,convMult,impulseAtrMult,chochBufferATR,effLen, se3);
   ComputeSE(PERIOD_M5, HTF_BARS, pivotLen,structLen,atrLen,effThresh,dispThresh,convMult,impulseAtrMult,chochBufferATR,effLen, se5);
   ComputeSE(PERIOD_M15,HTF_BARS, pivotLen,structLen,atrLen,effThresh,dispThresh,convMult,impulseAtrMult,chochBufferATR,effLen, se15);
   ComputeSE(PERIOD_H1, HTF_BARS, pivotLen,structLen,atrLen,effThresh,dispThresh,convMult,impulseAtrMult,chochBufferATR,effLen, se60);
   ComputeSE(PERIOD_H4, HTF_BARS, pivotLen,structLen,atrLen,effThresh,dispThresh,convMult,impulseAtrMult,chochBufferATR,effLen, se240);
   ComputePhys(PERIOD_M5,HTF_BARS,atrLen,effLen,effThresh,dispThresh,convMult, phys5);
   ComputeBelief(tf1,HTF_BARS,atrLen,effThresh,dispThresh,convMult,obLookback, bel1);
   ComputeBelief(tf2,HTF_BARS,atrLen,effThresh,dispThresh,convMult,obLookback, bel2);
   ComputeM1(HTF_BARS,atrLen,effLen,effThresh,dispThresh,convMult, m1o);
   ComputeFUPool(PERIOD_W1, HTF_BARS, fuwMinWickFrac, fpW);
   ComputeFUPool(PERIOD_D1, HTF_BARS, fuwMinWickFrac, fpD);
   ComputeFUPool(PERIOD_H4, HTF_BARS, fuwMinWickFrac, fpH4);
   ComputeFUPool(PERIOD_H1, HTF_BARS, fuwMinWickFrac, fpH1);
   ComputeFUPool(PERIOD_M15,HTF_BARS, fuwMinWickFrac, fpM15);
   ComputeFUPool(PERIOD_M5, HTF_BARS, fuwMinWickFrac, fpM5);
   ComputeHtfDir(mce_tf3,HTF_BARS,atrLen,effThresh,dispThresh,obLookback, mdir3);
   ComputeHtfDir(mce_tf4,HTF_BARS,atrLen,effThresh,dispThresh,obLookback, mdir4);
}


//==================================================================
// UNIFIED DRIVER — reprocess a window and set cur_* / gBar* outputs
// Caller should ResetState() first for a clean full recompute.
//==================================================================
void EngineRun(const int n,const datetime &time[],const double &open[],const double &high[],
               const double &low[],const double &close[],const double &volD[],const int startProcess)
{
   if(n<startProcess+3) return;
   BuildHTFEngines();
   int tgt=n-2;
   for(int i=startProcess;i<=tgt;i++)
      ProcessBar(i,open,high,low,close,time,volD,n,(i==tgt));
   g_lastProcessed=tgt;
}


//================================================================================
//  V60 CONTEXT (inlined from Letra37_Context.mqh)
//================================================================================
//+------------------------------------------------------------------+
//| Letra37_Context.mqh                                              |
//| Best-of-v60 ("F16 Raptor") FEATURE / CONTEXT layer for Letra,    |
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
//|   (The Senseei meta-DECISION layer is intentionally NOT ported - |
//|    Letra's own decision stays the authority. This module only    |
//|    supplies FEATURES / CONTEXT consumed by Letra37_EA.)          |
//|   - F72 curve-life score ("is the trade alive?") for management  |
//+------------------------------------------------------------------+

//==================================================================
// SENSEEI INPUTS (distinct names; engine inputs are reused)
//==================================================================
input group "Letra37 - v60 Context (Network)"
input double sIn_wickFrac    = 0.30;   // FU spike: min wick / range
input int    sIn_lookback    = 3;      // FU spike: structure lookback
input int    sIn_authMin     = 45;     // Min node authority
input int    sIn_nodeMax     = 250;    // Max remembered nodes
input int    sIn_dormantBars = 120;    // Bars until dormant
input int    sIn_historyBars = 600;    // Bars until historical

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
// V60 CONTEXT STATE + OUTPUTS
//==================================================================
SEV60     v1,v2,v3,v4,v5,v6;          // ladder rungs 1..6 (rung3 = chart = canonical)
FUPoolOut sfpMN,sfpW,sfpD,sfpH4,sfpH1,sfpM15,sfpM5;

//--- node registry ---
double sn_px[],sn_mid[],sn_sc[]; int sn_dir[],sn_wt[],sn_state[],sn_bar[],sn_rev[];
double sn_pv[7];                       // last pushed tip per TF (MN,W,D,H4,H1,M15,M5)

//--- v60 FEATURE outputs (last closed bar) — NO decision layer ---
int    ctx_waveDir=0, ctx_stackDir=0, ctx_netBias=0, ctx_pdir=0, ctx_timeDir=0;
double ctx_stackPct=0, ctx_pressure=0, ctx_residual=0, ctx_attractorScore=0, ctx_timeAlign=0, ctx_timeConflict=0;
int    ctx_resCode=0, ctx_eligN=0;
string ctx_phase="Point 4 Origin";
double ctx_entry=NA, ctx_stop=NA, ctx_t1=NA, ctx_t2=NA, ctx_t3=NA, ctx_attractorPx=NA, ctx_netTarget=NA, ctx_fezHi=NA, ctx_fezLo=NA;
//--- curve life (management) ---
double ctx_life=50.0, ctx_cpForce=0; string ctx_cpState="NEUTRAL", ctx_alive="WEAKENING";
//--- narrative lineage / ownership migration (context) ---
double ctx_narrative=50.0; string ctx_narrState="HOLDING"; bool ctx_converging=false;
double ctx_chainVitality=50.0, ctx_mig50=NA, ctx_mig618=NA, ctx_retrX=50.0;
//--- TIE detail ---
string ctx_h1Timing="—"; double ctx_wp=0, ctx_atr=0;

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
// SENSEEI DRIVER — full recompute -> sets ctx_* for last closed bar
//==================================================================
void ContextRun(const int bars)
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

   //--- narrative lineage / chain vitality (canonical wave) ---
   double narrDir=0, legX=NA, legPB=0, narrative=50.0; int supV=0, degV=0, seqCnt=0;
   double seqLast=NA, seqPrev=NA; double compHist[]; ArrayResize(compHist,0);
   for(int j=warmup;j<=last;j++){
      datetime ct=d.t[j]; double clj=d.c[j], hj=d.h[j], lj=d.l[j];
      double inv=MapVal(v3.t,v3.inv,v3.n,ct);
      int cdir=f_waveDirByOrigin(inv,clj,(int)nz(MapVal(v3.t,v3.dir,v3.n,ct)));
      double comp=nz(MapVal(v3.t,v3.comp,v3.n,ct));
      int hs=ArraySize(compHist); ArrayResize(compHist,hs+1); compHist[hs]=comp;
      double tighten=(hs>=6)?comp-compHist[hs-6]:0.0;
      if(cdir!=(int)narrDir){ narrDir=cdir; legX=cdir==1?hj:(cdir==-1?lj:NA); legPB=0; narrative=50.0; supV=0; degV=0; seqLast=NA; seqPrev=NA; seqCnt=0; }
      if(cdir!=0 && !naf(inv)){
         bool newX=cdir==1?hj>nz(legX,hj):lj<nz(legX,lj);
         if(newX){
            if(legPB>6.0){
               bool sup=legPB<=50.0 && tighten>=-1.0;
               bool deg=legPB>=62.0 || tighten<-3.0;
               int vote=sup?1:deg?-1:0;
               supV+=vote==1?1:0; degV+=vote==-1?1:0;
               narrative=clamp(narrative+vote*12.0+(tighten>0?3.0:-3.0),0.0,100.0);
               seqPrev=seqLast; seqLast=legPB; seqCnt++;
            }
            legX=cdir==1?hj:lj; legPB=0;
         } else {
            double pbd=MathAbs(nz(legX,clj)-inv)>1e-9?MathAbs(nz(legX,clj)-clj)/MathAbs(nz(legX,clj)-inv)*100.0:0.0;
            legPB=fmax2(legPB,pbd);
         }
      }
   }
   string narrState=narrative>=65.0?"STRENGTHENING":narrative<=35.0?"WEAKENING":"HOLDING";
   bool converging=seqCnt>=2 && !naf(seqLast) && !naf(seqPrev) && seqLast<seqPrev;
   double chainVitality=converging?fmin2(100.0,narrative+10.0):fmax2(0.0,narrative-10.0);

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

   //--- attack / level context (entry zone mid) ---
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
   string aliveTx=(progressing&&life>=45.0)?"ALIVE - ATTACKING":life>=60.0?"ALIVE - HOLD":life<=32.0?"DEAD - FLIP":"WEAKENING - MANAGE";
   //--- ownership migration band (0.5 / 0.618 of the owner leg) ---
   double mig50=(naf(c_inv)||naf(cExtreme)||cExtreme==c_inv)?NA:cExtreme+0.5*(c_inv-cExtreme);
   double mig618=(naf(c_inv)||naf(cExtreme)||cExtreme==c_inv)?NA:cExtreme+0.618*(c_inv-cExtreme);

   //--- publish FEATURE outputs only (NO Senseei decision layer) ---
   ctx_waveDir=waveDir; ctx_stackDir=stackDir; ctx_netBias=netBias; ctx_pdir=pdir; ctx_timeDir=timeDir;
   ctx_stackPct=stackPct; ctx_pressure=pressure; ctx_residual=residual; ctx_attractorScore=attractorScore;
   ctx_timeAlign=timeAlign; ctx_timeConflict=timeConflict; ctx_resCode=resCode; ctx_eligN=eligN; ctx_phase=phaseStr;
   ctx_entry=entry; ctx_stop=c_inv; ctx_t1=nz(c_tgt,attractorPx); ctx_t2=t2; ctx_t3=t3; ctx_attractorPx=attractorPx; ctx_netTarget=netTarget; ctx_fezHi=fezHi; ctx_fezLo=fezLo;
   ctx_life=life; ctx_cpForce=cpForce; ctx_cpState=cpState; ctx_alive=aliveTx; ctx_h1Timing=h1Timing; ctx_wp=c_wp; ctx_atr=atrL;
   ctx_narrative=narrative; ctx_narrState=narrState; ctx_converging=converging; ctx_chainVitality=chainVitality;
   ctx_mig50=mig50; ctx_mig618=mig618; ctx_retrX=retrX;
}


//================================================================================
//  EXPERT ADVISOR (inlined from Letra37_EA.mq5)
//================================================================================

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

input group "Letra37 EA - Take Profit"
input ENUM_TP_MODE  InpTPMode           = TP_NETWORK;   // Take-profit source (FU / Invisible-Network attractor)
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
input bool          InpExitOnPhaseFlip  = false;        // Close on Absorption/Retracement phase (off - was cutting too early)
input int           InpMinHoldBars      = 5;            // Min bars to hold before ANY discretionary exit (SL/TP always active)

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
input bool   InpAggressiveEntry = true;    // AGGRESSIVE: also enter on v60 confluence (network+curve+wave), bypassing strict Return/ERF gate
input bool   InpAggReqNet       = true;    // Aggressive: require network bias to agree
input bool   InpAggReqTime      = false;   // Aggressive: respect TIE-opposed block

input group "Letra37 EA - v60 Curve-Life Management"
input bool   InpUseCurveLifeExit= true;    // Exit when v60 curve-life goes DEAD (in trade direction)
input double InpCurveDeadBelow  = 32.0;    // life <= this => DEAD (close)
input bool   InpUseMigrationTrail= false;  // Keep stop at ownership-migration 0.618 band while force persists
input bool   InpUseNarrativeMgmt= true;    // Manage with narrative lineage / chain vitality
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
   bool aggressive=false;
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
      if(InpReverseOnOpposite){ CloseOwnPositions(0); DeletePendingOrders(); }
      else if(InpExitOnOpposite){ CloseOwnPositions(-dir); }
      else { gEntryBlock="opposite pos open"; return; }
   }
   if(CountOwnPositions()>=InpMaxPositions){ gEntryBlock="max positions"; return; }

   sym.RefreshRates();
   double ask=sym.Ask(), bid=sym.Bid();
   double entry=(dir==1?ask:bid);
   double slBase=ComputeSL(dir,entry);
   double lot=CalcLot(entry,slBase);
   double tp=ComputeTP(dir,entry,slBase);
   bool _arrow=(dir==1?cur_longSignal:cur_shortSignal);
   bool _doe=(dir==1?(cur_doeAction=="Long"):(cur_doeAction=="Short"));
   string _trig=aggressive?"V60AGG":(_arrow&&_doe)?"ARROW+DOE":_arrow?"ARROW":"DOE";
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
      if(InpExitOnInvalid && cur_invInvalidated){ trade.PositionClose(tk); continue; }
      if(InpCloseAtSessEnd && !SessionOK()){ trade.PositionClose(tk); continue; }
      //--- discretionary exits: only after the minimum hold (stops cutting straight away) ---
      if(canSoftExit){
         if(InpExitOnPhaseFlip && (cur_ie1aPhase=="Absorption"||cur_ie1aPhase=="Retracement")){ trade.PositionClose(tk); continue; }
         if(InpExitOnOpposite && ((dir==1&&cur_shortSignal)||(dir==-1&&cur_longSignal))){ trade.PositionClose(tk); continue; }
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
   s+="Narr   : "+cur_cmdNarrative;
   if(InpUseV60Context){
      s+="\n--- v60 context ---";
      s+="\nNet "+(ctx_netBias==1?"BULL":ctx_netBias==-1?"BEAR":"-")+"  Stack "+(ctx_stackDir==1?"BULL":ctx_stackDir==-1?"BEAR":"-")+" "+R0(ctx_stackPct)+"%  press "+R0(ctx_pressure);
      s+="\nCurve "+ctx_alive+"  life "+R0(ctx_life)+"  force "+ctx_cpState;
      s+="\nv60Phase "+ctx_phase+"  Narr "+ctx_narrState+" "+R0(ctx_narrative)+(ctx_converging?" (converging)":"");
      s+="\nTime "+(ctx_timeDir==1?"CLIMB":ctx_timeDir==-1?"DIVE":"LEVEL")+" "+R0(ctx_timeAlign)+"%  H1 "+ctx_h1Timing+"  attr "+PXs(ctx_attractorPx);
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
