//+------------------------------------------------------------------+
//|                                            Letra37_Brain.mqh      |
//|   Faithful port of the Letra 37 decision engine (Sections 2-24). |
//|   Operates on the M5 execution timeframe (chart context = M5),   |
//|   consuming six fixed-TF structure engines (M1/M3/M5/M15/H1/H4)  |
//|   and two HTF belief engines (tf1/tf2). Produces the final       |
//|   long/short/exit signals plus all supporting trade context.     |
//+------------------------------------------------------------------+
#property strict
#ifndef LETRA37_BRAIN_MQH
#define LETRA37_BRAIN_MQH
#include "Letra37_Series.mqh"
#include "Letra37_Structure.mqh"
#include "Letra37_HTFBelief.mqh"

//--- forward declaration (defined at end of file) ------------------
double IdealSim(const double eObs,const double dObs,const double vObs,const double cObs,
                const double eId,const double dId,const double vId,const double cId);

//--- All tunables consumed by the engine ---------------------------
struct BrainParams
{
   // Core
   int    pivotLen;
   int    atrLen;
   int    effLen;
   int    resetBars;
   // Filters
   double impulseAtrMult;
   double effThresh;
   double dispThresh;
   double convMult;
   int    acceptBars;
   int    obLookback;
   int    obMaxBars;
   // Structure
   bool   useStrictStructure;
   int    structLen;
   bool   requireStruct;
   double chochBufferATR;
   // Inducement
   int    inducLookback;
   double inducZoneWidth;
   bool   requirePreConv;
   bool   requireInduction;
   // Liquidity
   double liqRadius;
   double liqAgDecay;
   bool   requireLiqSweep;
   int    liqSweepLookback;
   // MTF
   ENUM_TIMEFRAMES tf1;
   ENUM_TIMEFRAMES tf2;
   // Execution
   int    baseLockBars;
   bool   requireHTFAlign;
   double execThreshold;
   // Intelligence
   int    beliefSmooth;
   double confDecayRate;
   // ERF
   double erfReadyResW;
   double erfReadyResidW;
   double erfReadyConfW;
   double erfEntryThreshold;
   bool   erfGateEnabled;
   // Return-phase detector. The V60 14-phase engine emits Demand/Supply Return
   // natively, so this is OFF by default. When ON it additionally promotes the
   // entry phase from belief/zone state (legacy behaviour / extra entries).
   bool   enableReturnPhase;
   // Adaptive timeframe ladder (V60). rung[0..5] = the six wave engines, climbing
   // from the chart timeframe so they stay distinct on any chart. rung[2] is the
   // canonical / execution rung (chart TF) used for physics + base series.
   ENUM_TIMEFRAMES rung[6];
   // History depth (per rung position 1..6)
   int    barsM1;
   int    barsM3;
   int    barsM5;
   int    barsM15;
   int    barsH1;
   int    barsH4;
};

//+------------------------------------------------------------------+
class CLetra37Brain
{
public:
   //--- outputs (state of the most recent closed M5 bar) -----------
   bool     ready;
   datetime barTime;
   bool     longSignal;
   bool     shortSignal;
   bool     exitNow;
   bool     exitLatchActive;
   int      outDir;           // active wave direction (gated)
   int      tradeDir;
   double   atr;
   double   outFlipTop, outFlipBot;
   double   target;           // l0_target (se5 tgt)
   double   invalidation;     // l0 invalidation (se5 inv)
   double   attractorPrice;   // eae primary attractor
   string   phase;            // ie1a_currentPhase
   string   grade;
   double   finalProb;        // bayesian
   double   netEdgeAdjusted;
   double   buyProb, sellProb;
   string   directive;        // liveDirective
   int      fractalStackDir;
   double   fractalCtxScore;
   int      htfAlign;
   double   liqHeatOut;
   double   erfReadinessOut;
   double   demandReturnBeliefOut;
   //--- V60 14-phase + F72 curve-life outputs ----------------------
   int      phaseCode;        // se5 canonical phase code 0..14
   double   compIdx;          // se5 compression index
   int      recCount;         // se5 recursive-transition count
   double   domTransfer;      // se5 dominance transfer %
   double   lifeScore;        // F72 "is the trade alive?" 0..100
   string   aliveVerdict;     // ALIVE / WEAKENING / DEAD
   int      lifeTradeDir;     // curve-resolved trade dir (+1/-1/0; may flip vs wave)
   string   cpState;          // compression persistence: PERSISTING / LEAKING / NEUTRAL
   string   narrState;        // narrative lineage: STRENGTHENING / HOLDING / WEAKENING
   string   chainScope;       // chain vitality scope
   string   htfThreat;        // HTF parent threat: CLEAR / APPROACHING / AT ZONE
   double   ownerOrigin;      // owner curve origin (migration/stop reference)
   double   ownerExtreme;     // owner curve extreme

   CLetra37Brain(){ ready=false; }

   bool Recompute(const string symbol,const BrainParams &P);

private:
   SeParams SeP(const BrainParams &P)
   {
      SeParams s;
      s.pivotLen=P.pivotLen; s.structLen=P.structLen; s.atrLen=P.atrLen;
      s.effThresh=P.effThresh; s.dispThresh=P.dispThresh; s.convMult=P.convMult;
      s.impulseAtrMult=P.impulseAtrMult; s.chochBuffer=P.chochBufferATR; s.effLen=P.effLen;
      return(s);
   }
};


//+------------------------------------------------------------------+
//| Inducement price finder (Pine f_findInducPrice).                 |
//+------------------------------------------------------------------+
double FindInducPrice(const double &h[],const double &l[],const int bi,
                      const int anchorRefBar,const double anchorTop,const double anchorBot,
                      const int lookback)
{
   double best=LNA, bestDist=LNA;
   int maxI=MathMin(lookback,bi-anchorRefBar);
   for(int i=1;i<=maxI;i++)
   {
      int k=bi-i; if(k<0) break;
      if(h[k]<anchorTop && l[k]>anchorBot)
      {
         double d=MathAbs((double)((bi-i)-anchorRefBar));
         if(IsNAv(bestDist) || d<bestDist){ bestDist=d; best=(h[k]+l[k])/2.0; }
      }
   }
   return(best);
}

//+------------------------------------------------------------------+
//| Build alignment: for each M5 bar, latest src index with time<=.  |
//+------------------------------------------------------------------+
void AlignSe(const SeBar &src[],const datetime &m5time[],int &idxOut[])
{
   int nm=ArraySize(m5time), ns=ArraySize(src);
   ArrayResize(idxOut,nm);
   int j=0;
   for(int i=0;i<nm;i++)
   {
      while(j+1<ns && src[j+1].time<=m5time[i]) j++;
      idxOut[i]=(ns>0 && src[0].time<=m5time[i])?j:-1;
   }
}
void AlignHtf(const HtfBel &src[],const datetime &m5time[],int &idxOut[])
{
   int nm=ArraySize(m5time), ns=ArraySize(src);
   ArrayResize(idxOut,nm);
   int j=0;
   for(int i=0;i<nm;i++)
   {
      while(j+1<ns && src[j+1].time<=m5time[i]) j++;
      idxOut[i]=(ns>0 && src[0].time<=m5time[i])?j:-1;
   }
}

//+------------------------------------------------------------------+
//| Main recompute.                                                  |
//+------------------------------------------------------------------+
bool CLetra37Brain::Recompute(const string symbol,const BrainParams &P)
{
   ready=false;
   SeParams sp=SeP(P);

   //--- fixed-TF structure engines ---------------------------------
   SeBar se1[],se3[],se5[],se15[],se60[],se240[];
   if(ComputeStructureEngine(symbol,P.rung[0], P.barsM1, sp,se1)  ==0) return(false);
   if(ComputeStructureEngine(symbol,P.rung[1], P.barsM3, sp,se3)  ==0) return(false);
   if(ComputeStructureEngine(symbol,P.rung[2], P.barsM5, sp,se5)  ==0) return(false);
   if(ComputeStructureEngine(symbol,P.rung[3], P.barsM15,sp,se15) ==0) return(false);
   if(ComputeStructureEngine(symbol,P.rung[4], P.barsH1, sp,se60) ==0) return(false);
   if(ComputeStructureEngine(symbol,P.rung[5], P.barsH4, sp,se240)==0) return(false);

   //--- HTF belief engines -----------------------------------------
   HtfBel hb1[],hb2[];
   ComputeHtfBeliefs(symbol,P.tf1,P.barsM15,P.atrLen,P.effThresh,P.dispThresh,P.convMult,P.obLookback,hb1);
   ComputeHtfBeliefs(symbol,P.tf2,P.barsH1, P.atrLen,P.effThresh,P.dispThresh,P.convMult,P.obLookback,hb2);

   //--- base series (canonical rung = chart TF) --------------------
   MqlRates r[]; ArraySetAsSeries(r,false);
   int n=CopyRates(symbol,P.rung[2],0,P.barsM5,r);
   if(n>2) n--;                                  // drop the still-forming bar (decide on closed bars)
   if(n<P.atrLen+P.structLen*3+10) return(false);

   double o[],h[],l[],c[],vol[]; datetime tm[];
   ArrayResize(o,n);ArrayResize(h,n);ArrayResize(l,n);ArrayResize(c,n);ArrayResize(vol,n);ArrayResize(tm,n);
   for(int i=0;i<n;i++){ o[i]=r[i].open;h[i]=r[i].high;l[i]=r[i].low;c[i]=r[i].close;vol[i]=(double)r[i].tick_volume;tm[i]=r[i].time; }

   //--- M5 physics (f_phys) ----------------------------------------
   double atrA[],dC[],velA[],accA[],convA[],csmA[],absStep[],pathSum[],atrSmaA[],volAvgA[];
   ArrayResize(dC,n); for(int i=0;i<n;i++) dC[i]=(i==0?0.0:c[i]-c[i-1]);
   ATR_RMA(h,l,c,P.atrLen,atrA);
   EMAv(dC,3,velA);
   ArrayResize(accA,n); for(int i=0;i<n;i++) accA[i]=(i==0?0.0:velA[i]-velA[i-1]);
   ArrayResize(convA,n); for(int i=0;i<n;i++) convA[i]=(i==0?0.0:accA[i]-accA[i-1]);
   EMAv(convA,3,csmA);
   ArrayResize(absStep,n); for(int i=0;i<n;i++) absStep[i]=MathAbs(dC[i]);
   RollSum(absStep,P.effLen,pathSum);
   SMAv(atrA,20,atrSmaA);
   SMAv(vol,20,volAvgA);

   //--- M5 pivots (pivotLen + structLen) ---------------------------
   double pHc[],pLc[],spH[],spL[];
   PivotHigh(h,P.pivotLen,P.pivotLen,pHc);
   PivotLow (l,P.pivotLen,P.pivotLen,pLc);
   PivotHigh(h,P.structLen,P.structLen,spH);
   PivotLow (l,P.structLen,P.structLen,spL);

   //--- time alignment ---------------------------------------------
   int ia1[],ia3[],ia5[],ia15[],ia60[],ia240[],ib1[],ib2[];
   AlignSe(se1,tm,ia1); AlignSe(se3,tm,ia3); AlignSe(se5,tm,ia5);
   AlignSe(se15,tm,ia15); AlignSe(se60,tm,ia60); AlignSe(se240,tm,ia240);
   AlignHtf(hb1,tm,ib1); AlignHtf(hb2,tm,ib2);

   //=================================================================
   //  PERSISTENT (var) STATE
   //=================================================================
   // Section 3 HTF bias
   int htfBias1=0, htfBias2=0;
   // Section 4 structure
   double lastPivHigh=LNA,prevPivHigh=LNA,lastPivLow=LNA,prevPivLow=LNA; int structBias=0;
   double prevSwingHigh=LNA,prevSwingLow=LNA,currSwingHigh=LNA,currSwingLow=LNA;
   // Section 5 pivot memory
   double lastPivotPrice=LNA,prevPivotPrice=LNA; int lastPivotBar=-1,prevPivotBar=-1,lastPivotDir=0,prevPivotDir=0;
   // Section 8 wave context
   int direction=0; double flipTop=LNA,flipBot=LNA; int obBirthBar=-1,barsInZone=0,contBar=-1;
   double point4OriginHigh=LNA,point4OriginLow=LNA; int point4OriginBar=-1;
   double flipzoneInducPrice=LNA,flipzoneInducLow=LNA,flipzoneInducHigh=LNA;
   double inducExpOriginHigh=LNA,inducExpExtremeLow=LNA,inducExpOriginLow=LNA,inducExpExtremeHigh=LNA;
   double inducRetrOriginHigh=LNA,inducRetrExtremeLow=LNA,inducRetrOriginLow=LNA,inducRetrExtremeHigh=LNA;
   double inducZoneLow=LNA,inducZoneHigh=LNA,cycleHigh=LNA,cycleLow=LNA;
   int waveGeneration=0,entryCycle=0,waveDepth=0,lastSpawnDir=0; bool isRecursiveWave=false,recursiveComplete=false;
   double retestHigh=LNA,retestLow=LNA;
   // forward declarations (Section 8)
   bool inductionEvidence=false,preConvEvidence=false,closeInside=false;
   // Section 9/12 forward vars
   double liqHeat=0.0,convexityMaturity=0.0; bool nearFlipzone=false;
   // Section 12 belief EMAs
   double expansionBelief=0.0,convexityBelief=0.0,creationBelief=0.0,absorptionBelief=0.0,retracementBelief=0.0,demandReturnBelief=0.0;
   double waveProgress=30.0,waveModelFit=50.0,modelConfidence=50.0;
   string lastExpectedPhase="Point 4 Origin",lastIE1APhase="Point 4 Origin";
   // Section 13 recursive
   bool recursiveJustFired=false; int recursiveFiredBar=-1;
   // Section 20 exec lock
   int lastSignalBar=-1,lastLongBar=-1,lastShortBar=-1; bool engineArmed=true;
   // Section 24 trade state
   int tradeDirV=0,exitFiredBar=-1;
   double energyPrev=0.0;
   // liquidity heatmap arrays
   double liqLvl[],liqWt[]; int liqAge[],liqTyp[];
   ArrayResize(liqLvl,0);ArrayResize(liqWt,0);ArrayResize(liqAge,0);ArrayResize(liqTyp,0);

   //--- F72 curve-life persistent state ----------------------------
   double f72comp[]; ArrayResize(f72comp,n); for(int i=0;i<n;i++) f72comp[i]=0.0;
   int    narrDir=0; double legX=LNA,legPBdepth=0.0,narrative=50.0; int supVotes=0,degVotes=0;
   double wholeChainLife=50.0;
   double seqRetr[]; ArrayResize(seqRetr,0);
   double lifeSeq[]; ArrayResize(lifeSeq,0);

   // outputs for the final bar
   bool fLong=false,fShort=false,fExit=false,fExitLatch=false;
   string fPhase="",fGrade="",fDirective="";
   double fFinalProb=0,fNetEdge=0,fBuyProb=0,fSellProb=0,fTarget=LNA,fInv=LNA,fFlipTop=LNA,fFlipBot=LNA,fAttr=LNA,fAtr=0;
   int fDir=0,fTradeDir=0,fStackDir=0,fHtfAlign=0; double fCtx=0,fLiq=0,fErf=0,fDRB=0;
   // F72 final-bar temporaries
   int fPhaseCode=0,fRec=0,fLifeDir=0; double fComp=0,fDom=0,fLife=50.0,fOwnOrig=LNA,fOwnExt=LNA;
   string fAlive="—",fCp="NEUTRAL",fNarr="HOLDING",fChain="healthy",fHtf="—";

   int warmStart = MathMax(P.structLen*2+2, P.atrLen+5);


   //=================================================================
   //  CHRONOLOGICAL PASS
   //=================================================================
   for(int i=warmStart;i<n;i++)
   {
      // skip until all engines have an aligned value
      if(ia1[i]<0||ia3[i]<0||ia5[i]<0||ia15[i]<0||ia60[i]<0||ia240[i]<0||ib1[i]<0||ib2[i]<0) continue;
      if(i<P.effLen+1 || i<3) continue;

      double close=c[i], open=o[i], high=h[i], low=l[i];

      //--- PHYSICS (Section 2) ------------------------------------
      double atr=atrA[i];
      double vel=velA[i], velP=velA[i-1], velP2=velA[i-2], velP3=velA[i-3];
      double acc=accA[i], accP=accA[i-1];
      double csm=csmA[i], csmP=csmA[i-1];
      double eff=(pathSum[i]>0.0 ? MathAbs(close-c[i-P.effLen])/pathSum[i] : 0.0);
      double disp=(high-low)/MathMax(atr,1e-10);
      double cth=atr*P.convMult;
      bool bullConvShift=(csm>cth && csmP<=cth);
      bool bearConvShift=(csm<-cth && csmP>=-cth);
      bool bullImpulse=(eff>P.effThresh && vel>velP && acc>0 && close>open && disp>P.dispThresh);
      bool bearImpulse=(eff>P.effThresh && vel<velP && acc<0 && close<open && disp>P.dispThresh);
      bool bullMomDecay=(MathAbs(acc)<MathAbs(accP)*0.8 && vel>0);
      bool bearMomDecay=(MathAbs(acc)<MathAbs(accP)*0.8 && vel<0);
      bool bullMicroImpulse=(eff>P.effThresh*0.8 && vel>velP && acc>0 && close>open && disp>P.dispThresh*0.5);
      bool bearMicroImpulse=(eff>P.effThresh*0.8 && vel<velP && acc<0 && close<open && disp>P.dispThresh*0.5);
      bool phys_vd70=(MathAbs(vel)<MathAbs(velP)*0.7);
      bool phys_vd50=(MathAbs(vel)<MathAbs(velP)*0.5);
      double phys_mom=vel-velP;
      double volRatio=atr/MathMax(atrSmaA[i],1e-10);
      double volMult=MathMax(0.5,MathMin(volRatio,2.5));

      //--- MARKET STRUCTURE (Section 4) ---------------------------
      double structPivH=spH[i], structPivL=spL[i];
      if(!IsNAv(structPivH)){ prevPivHigh=lastPivHigh; lastPivHigh=structPivH; }
      if(!IsNAv(structPivL)){ prevPivLow=lastPivLow; lastPivLow=structPivL; }
      bool isHH=(!IsNAv(lastPivHigh)&&!IsNAv(prevPivHigh)&&lastPivHigh>prevPivHigh);
      bool isLH=(!IsNAv(lastPivHigh)&&!IsNAv(prevPivHigh)&&lastPivHigh<prevPivHigh);
      bool isHL=(!IsNAv(lastPivLow)&&!IsNAv(prevPivLow)&&lastPivLow>prevPivLow);
      bool isLL=(!IsNAv(lastPivLow)&&!IsNAv(prevPivLow)&&lastPivLow<prevPivLow);
      double swPivH=pHc[i], swPivL=pLc[i];
      if(!IsNAv(swPivH)){ prevSwingHigh=(IsNAv(currSwingHigh)?swPivH:currSwingHigh); currSwingHigh=swPivH; }
      if(!IsNAv(swPivL)){ prevSwingLow=(IsNAv(currSwingLow)?swPivL:currSwingLow); currSwingLow=swPivL; }
      bool bullBOS=(!IsNAv(prevSwingHigh)&&close>prevSwingHigh);
      bool bearBOS=(!IsNAv(prevSwingLow)&&close<prevSwingLow);
      if(P.useStrictStructure){ if(isHH&&isHL) structBias=1; if(isLH&&isLL) structBias=-1; }
      else { if(bullBOS) structBias=1; if(bearBOS) structBias=-1; }

      //--- PIVOT MEMORY (Section 5) -------------------------------
      double pivH=pHc[i], pivL=pLc[i];
      double pivotEventPrice=LNA; int pivotEventBar=-1,pivotEventDir=0;
      if(!IsNAv(pivH)){ pivotEventPrice=pivH; pivotEventBar=i-P.pivotLen; pivotEventDir=1; }
      else if(!IsNAv(pivL)){ pivotEventPrice=pivL; pivotEventBar=i-P.pivotLen; pivotEventDir=-1; }
      if(pivotEventDir!=0)
      {
         prevPivotPrice=lastPivotPrice; prevPivotBar=lastPivotBar; prevPivotDir=lastPivotDir;
         lastPivotPrice=pivotEventPrice; lastPivotBar=pivotEventBar; lastPivotDir=pivotEventDir;
      }

      //--- ALIGNED STRUCTURE ENGINES ------------------------------
      int j1=ia1[i],j3=ia3[i],j5=ia5[i],j15=ia15[i],j60=ia60[i],j240=ia240[i];
      double se5_inv=se5[j5].inv, se5_tgt=se5[j5].tgt, l0_p4High=se5[j5].p4h, l0_p4Low=se5[j5].p4l;
      double se5_mf=se5[j5].mf, se5_wp=se5[j5].wp;
      string l0_phaseCanon=SePhaseStr(se5[j5].phase);
      int m1_dir=(!IsNAv(se1[j1].inv)?(close>se1[j1].inv?1:close<se1[j1].inv?-1:se1[j1].dir):se1[j1].dir);
      int l3_dir=(!IsNAv(se3[j3].inv)?(close>se3[j3].inv?1:close<se3[j3].inv?-1:se3[j3].dir):se3[j3].dir);
      int l0_dir=(!IsNAv(se5_inv)?(close>se5_inv?1:close<se5_inv?-1:se5[j5].dir):se5[j5].dir);
      int l1_dir=(!IsNAv(se15[j15].inv)?(close>se15[j15].inv?1:close<se15[j15].inv?-1:se15[j15].dir):se15[j15].dir);
      int l2_dir=(!IsNAv(se60[j60].inv)?(close>se60[j60].inv?1:close<se60[j60].inv?-1:se60[j60].dir):se60[j60].dir);
      int l4_dir=(!IsNAv(se240[j240].inv)?(close>se240[j240].inv?1:close<se240[j240].inv?-1:se240[j240].dir):se240[j240].dir);
      int sBull=(m1_dir==1?1:0)+(l3_dir==1?1:0)+(l0_dir==1?1:0)+(l1_dir==1?1:0)+(l2_dir==1?1:0)+(l4_dir==1?1:0);
      int sBear=(m1_dir==-1?1:0)+(l3_dir==-1?1:0)+(l0_dir==-1?1:0)+(l1_dir==-1?1:0)+(l2_dir==-1?1:0)+(l4_dir==-1?1:0);
      int fractalStackDir=(sBull>sBear?1:sBear>sBull?-1:0);
      double fractalCtxScore=MinD(
         (l4_dir==fractalStackDir&&fractalStackDir!=0?30.0:0.0)+
         (l2_dir==fractalStackDir&&fractalStackDir!=0?26.0:0.0)+
         (l1_dir==fractalStackDir&&fractalStackDir!=0?20.0:0.0)+
         (l0_dir==fractalStackDir&&fractalStackDir!=0?14.0:0.0)+
         (l3_dir==fractalStackDir&&fractalStackDir!=0?6.0:0.0)+
         (m1_dir==fractalStackDir&&fractalStackDir!=0?4.0:0.0),100.0);
      int liveWaveDir=l0_dir;
      int liveHtfAlign=((l2_dir!=0&&l2_dir==l4_dir)?l2_dir:0);

      //--- HTF BELIEFS (Section 3) --------------------------------
      int    dir_tf1=hb1[ib1[i]].dir,    dir_tf2=hb2[ib2[i]].dir;
      double expScr_tf1=hb1[ib1[i]].expScr, expScr_tf2=hb2[ib2[i]].expScr;
      double decScr_tf1=hb1[ib1[i]].decScr, decScr_tf2=hb2[ib2[i]].decScr;
      if(expScr_tf1>60&&dir_tf1!=0) htfBias1=dir_tf1;
      if(expScr_tf2>60&&dir_tf2!=0) htfBias2=dir_tf2;
      if(decScr_tf1>70&&dir_tf1==htfBias1) htfBias1=0;
      if(decScr_tf2>70&&dir_tf2==htfBias2) htfBias2=0;
      int htfAlign=((htfBias1==1&&htfBias2==1)?1:(htfBias1==-1&&htfBias2==-1)?-1:0);

      //--- PHYSICS OBSERVATION LAYER (Section 9) ------------------
      double velocityScore=MinD(MathAbs(vel)/MathMax(atr*0.1,1e-10)*50.0,100.0);
      double convexityScore=MinD(MathAbs(csm)/MathMax(atr*P.convMult,1e-10)*25.0,100.0);
      double obs_ExpansionScore=MinD(
         (eff>P.effThresh?eff*60.0:eff*30.0)+
         (disp>P.dispThresh?(disp/MathMax(P.dispThresh,1e-10)-1.0)*20.0:0.0)+
         (((vel>0&&acc>0)||(vel<0&&acc<0))?velocityScore*0.2:0.0),100.0);
      double obs_DecayScore=MinD((bullMomDecay||bearMomDecay?40.0:0.0)+(convexityScore>30?convexityScore*0.5:0.0)+(phys_vd70?30.0:0.0),100.0);
      double obs_CurvatureScore=convexityScore;
      double obs_AbsorptionScore=MinD((eff<P.effThresh*0.7?(1.0-eff/MathMax(P.effThresh,1e-10))*50.0:0.0)+(phys_vd50?30.0:0.0)+(disp<P.dispThresh*0.5?20.0:0.0),100.0);
      double obs_LiquidityScore=MinD(obs_DecayScore*0.4+obs_CurvatureScore*0.4+(disp>P.dispThresh*1.2&&(bullMomDecay||bearMomDecay)?20.0:0.0),100.0);
      double physicsMax=MathMax(obs_ExpansionScore,MathMax(obs_DecayScore,MathMax(obs_AbsorptionScore,obs_LiquidityScore)));
      double physicsMin=MathMin(obs_ExpansionScore,MathMin(obs_DecayScore,MathMin(obs_AbsorptionScore,obs_LiquidityScore)));
      double physicsDiff=physicsMax-physicsMin;
      double physicsConsensus=MathMax(0.0,100.0-physicsDiff);

      //--- ENGINE 1A ----------------------------------------------
      string ie1a_currentPhase=l0_phaseCanon;
      double ie1a_phaseConfidence=MathMax(20.0,MathMin(100.0,fractalCtxScore*0.50+NZv(se5_mf)*0.30+NZv(se5_wp)*0.20));

      //--- ENERGY RESOLUTION FRAMEWORK (uses prev-bar liqHeat / convexityMaturity / direction) ---
      int ede_state=(l0_phaseCanon=="Point 4 Origin"?1:l0_phaseCanon=="Expansion"?1:
                     l0_phaseCanon=="Expansion Pre-Convexity"?2:l0_phaseCanon=="Expansion Induction"?3:
                     l0_phaseCanon=="Expansion Liquidity"?4:l0_phaseCanon=="New High"?5:l0_phaseCanon=="New Low"?5:6);
      double ede_expansionEnergy=MinD(obs_ExpansionScore*0.5+(bullImpulse||bearImpulse?30.0:0.0)+(eff*20.0),100.0);
      double ede_dissipatedEnergy=MinD((ede_state>=2?obs_DecayScore*0.4:0.0)+(ede_state>=3?obs_CurvatureScore*0.3:0.0)+(ede_state>=4?obs_LiquidityScore*0.3:0.0),100.0);
      double ede_dissipationProgress=MinD((ede_state>=2?25.0:0.0)+(ede_state>=3?25.0:0.0)+(ede_state>=4?25.0:0.0)+(ede_state>=5?25.0:0.0),100.0);
      bool ede_messyPriceIsDissipation=((ede_state>=2&&ede_state<=4)&&obs_DecayScore>30.0&&eff<P.effThresh*0.9&&!(bullImpulse||bearImpulse));
      int re_expectedCycles=MathMax(1,MathMin(waveDepth+2,4));
      int re_completedCycles=MathMax(0,MathMin(entryCycle,re_expectedCycles));
      double re_recursiveCompletionScore=(re_expectedCycles>0?MinD((double)re_completedCycles/(double)re_expectedCycles*100.0,100.0):0.0);
      double re_residualEnergy=MathMax(0.0,ede_expansionEnergy-ede_dissipatedEnergy);
      bool re_objectiveReached=(ede_state>=5);
      bool re_fullDissipation=(ede_dissipationProgress>=75.0);
      bool re_absorbedAndReturned=((ie1a_currentPhase=="Demand Return"||ie1a_currentPhase=="Supply Return")&&recursiveComplete);
      int re_state; // 0 UNRES,1 PARTIAL,2 RESOLVED
      if(re_absorbedAndReturned&&re_fullDissipation&&re_recursiveCompletionScore>=75.0) re_state=2;
      else if(re_objectiveReached&&ede_dissipationProgress>=50.0) re_state=1;
      else re_state=0;
      double re_residualEnergyScore=MinD(re_residualEnergy,100.0);
      double eae_primaryAttractorPrice=LNA;
      if(direction!=0)
      {
         if(re_state==0) eae_primaryAttractorPrice=(direction==1?NZv(flipBot,close-atr*2.0):NZv(flipTop,close+atr*2.0));
         else if(re_state==1) eae_primaryAttractorPrice=(direction==1?NZv(point4OriginLow,close-atr):NZv(point4OriginHigh,close+atr));
      }
      double eae_primaryAttractorScore=MinD(
         re_residualEnergyScore*0.4+(re_state==0?30.0:re_state==1?20.0:5.0)+
         (!IsNAv(eae_primaryAttractorPrice)?MathMax(0.0,30.0-MathAbs(close-eae_primaryAttractorPrice)/MathMax(atr,1e-10)*5.0):0.0),100.0);
      string eae_energyState=(ede_state==1?"Accumulating":(ede_state>=2&&ede_state<=4)?"Cleaning":ede_state==5?"Delivering":re_state==2?"Exhausted":"Resolving");
      bool erf_activeDissipation=ede_messyPriceIsDissipation;
      bool erf_suppressRotation=(erf_activeDissipation&&ede_state>=2&&ede_state<=4);
      double erf_confidence=MinD((eae_energyState!="Accumulating"?ie1a_phaseConfidence*0.4:20.0)+(re_state==2?30.0:re_state==1?20.0:10.0)+(eae_primaryAttractorScore*0.3),100.0);
      double erf_tradeReadiness=MinD((re_state==2?40.0:re_state==1?25.0:10.0)+re_recursiveCompletionScore*P.erfReadyResW+(100.0-re_residualEnergyScore)*P.erfReadyResidW+erf_confidence*P.erfReadyConfW,100.0);
      bool erf_entryGate=(!P.erfGateEnabled||erf_tradeReadiness>=P.erfEntryThreshold);


      //--- LIQUIDITY HEATMAP (Section 10) -------------------------
      double _swH=HighestAt(h,i,P.liqSweepLookback);
      double _swL=LowestAt(l,i,P.liqSweepLookback);
      bool liqSweepBull=(!IsNAv(flipTop)&&_swH>flipTop);
      bool liqSweepBear=(!IsNAv(flipBot)&&_swL<flipBot);
      double volAvg=volAvgA[i];
      double normVol=(volAvg>0&&i>=P.pivotLen?vol[i-P.pivotLen]/volAvg:1.0);
      if((!IsNAv(pivH)||!IsNAv(pivL))&&i>=P.pivotLen)
      {
         double lvl=(!IsNAv(pivH)?pivH:pivL);
         int lType=(!IsNAv(pivH)?1:-1);
         double swRng=(h[i-P.pivotLen]-l[i-P.pivotLen])/MathMax(atr,1e-10);
         double wt=normVol*swRng;
         int sz=ArraySize(liqLvl);
         ArrayResize(liqLvl,sz+1);ArrayResize(liqWt,sz+1);ArrayResize(liqAge,sz+1);ArrayResize(liqTyp,sz+1);
         liqLvl[sz]=lvl; liqWt[sz]=wt; liqAge[sz]=i-P.pivotLen; liqTyp[sz]=lType;
      }
      if(ArraySize(liqLvl)>150)
      {
         int sz=ArraySize(liqLvl);
         for(int k=1;k<sz;k++){ liqLvl[k-1]=liqLvl[k];liqWt[k-1]=liqWt[k];liqAge[k-1]=liqAge[k];liqTyp[k-1]=liqTyp[k]; }
         ArrayResize(liqLvl,sz-1);ArrayResize(liqWt,sz-1);ArrayResize(liqAge,sz-1);ArrayResize(liqTyp,sz-1);
      }
      double wDensity=0.0,wDensityAbove=0.0,wDensityBelow=0.0;
      double liqRadiusP=atr*P.liqRadius, liqRadiusWide=atr*P.liqRadius*3.0;
      int lsz=ArraySize(liqLvl);
      for(int k=0;k<lsz;k++)
      {
         double lvl=liqLvl[k], wt=liqWt[k];
         int age=i-liqAge[k];
         double dcy=MathPow(P.liqAgDecay,age);
         double dist=MathAbs(close-lvl);
         if(dist<liqRadiusP) wDensity+=wt*dcy;
         if(dist<liqRadiusWide)
         {
            if(lvl>close) wDensityAbove+=wt*dcy*(1.0-dist/liqRadiusWide);
            else          wDensityBelow+=wt*dcy*(1.0-dist/liqRadiusWide);
         }
      }
      double liqHeatRaw=MinD((wDensityAbove+wDensityBelow)/2.0,5.0)/5.0*100.0;
      liqHeat=MathMax(0.0,MathMin(liqHeatRaw,100.0));
      bool liqVacuum=(wDensity<0.5);
      bool liqSweepOK=(!P.requireLiqSweep)||
         (direction==1&&(liqSweepBull||liqVacuum))||
         (direction==-1&&(liqSweepBear||liqVacuum));

      //--- GEOMETRY (Section 11) ----------------------------------
      int obAge=(obBirthBar>=0?i-obBirthBar:0);
      bool obFresh=(obAge<=P.obMaxBars);
      double obFreshness=(obBirthBar>=0?MathMax(0.0,1.0-(double)obAge/(double)P.obMaxBars):0.0);
      double originToExtreme=LNA;
      if(!IsNAv(point4OriginHigh)&&!IsNAv(point4OriginLow))
      {
         double orig=(direction==1?point4OriginLow:point4OriginHigh);
         double extr=(direction==1?NZv(cycleHigh,orig):NZv(cycleLow,orig));
         originToExtreme=MathAbs(extr-orig);
      }
      double flipzoneWidth=((!IsNAv(flipTop)&&!IsNAv(flipBot))?flipTop-flipBot:LNA);

      //--- WAVE INTELLIGENCE (Section 12) -------------------------
      double ref_effNorm=MinD(eff,1.0);
      double ref_dispNorm=MinD(disp/MathMax(P.dispThresh*2.0,1e-10),1.0);
      double ref_velNorm=MinD(MathAbs(vel)/MathMax(atr*0.15,1e-10),1.0);
      double ref_curvNorm=MinD(MathAbs(csm)/MathMax(atr*P.convMult*2.0,1e-10),1.0);
      double sim_Expansion  =IdealSim(ref_effNorm,ref_dispNorm,ref_velNorm,ref_curvNorm,0.85,0.80,0.80,0.10);
      double sim_PreConv    =IdealSim(ref_effNorm,ref_dispNorm,ref_velNorm,ref_curvNorm,0.60,0.55,0.40,0.50);
      double sim_Induction  =IdealSim(ref_effNorm,ref_dispNorm,ref_velNorm,ref_curvNorm,0.65,0.60,0.30,0.60);
      double sim_Liquidity  =IdealSim(ref_effNorm,ref_dispNorm,ref_velNorm,ref_curvNorm,0.45,0.85,0.15,0.80);
      double sim_Creation   =IdealSim(ref_effNorm,ref_dispNorm,ref_velNorm,ref_curvNorm,0.30,0.70,0.05,0.90);
      double sim_Absorption =IdealSim(ref_effNorm,ref_dispNorm,ref_velNorm,ref_curvNorm,0.20,0.25,0.10,0.40);
      double sim_Retracement=IdealSim(ref_effNorm,ref_dispNorm,ref_velNorm,ref_curvNorm,0.70,0.65,0.65,0.25);
      double sim_DemandReturn=IdealSim(ref_effNorm,ref_dispNorm,ref_velNorm,ref_curvNorm,0.50,0.40,0.35,0.20);

      double waveTotalRange=(!IsNAv(originToExtreme)?originToExtreme:atr*5.0);
      double currentToFlipMid=((!IsNAv(flipTop)&&!IsNAv(flipBot))?MathAbs(close-(flipTop+flipBot)/2.0):atr*4.0);
      double currentToExtreme=(direction==1?MathAbs(NZv(cycleHigh,close+atr)-close):MathAbs(close-NZv(cycleLow,close-atr)));
      double posNormDen=MathMax(waveTotalRange,atr*0.5);
      double posDistToCreation=MinD(currentToExtreme/posNormDen*100.0,100.0);
      double posDistToDemand=MinD(currentToFlipMid/posNormDen*100.0,100.0);

      // convexity maturity (uses prev-bar inductionEvidence/preConvEvidence)
      double expWeaknessScore=MinD(((eff<P.effThresh?(1.0-eff/MathMax(P.effThresh,1e-10))*40.0:0.0)+(obs_DecayScore*0.30)+(MathAbs(vel)<MathAbs(velP2)*0.6?20.0:0.0))*(100.0/90.0),100.0);
      double inductionMatScore=MinD((inductionEvidence?35.0:0.0)+(obs_CurvatureScore*0.35)+(preConvEvidence?20.0:0.0)+(disp>P.dispThresh*1.2&&(bullMomDecay||bearMomDecay)?10.0:0.0),100.0);
      double liqMatScore=MinD((obs_LiquidityScore*0.50)+(liqSweepBull||liqSweepBear?30.0:0.0)+(liqHeat>60?20.0:liqHeat>30?10.0:0.0),100.0);
      double rawConvexityMaturity=MinD(expWeaknessScore*0.35+inductionMatScore*0.35+liqMatScore*0.30,100.0);
      double bAlpha=2.0/(P.beliefSmooth+1.0);
      convexityMaturity=convexityMaturity+bAlpha*(rawConvexityMaturity-convexityMaturity);

      // wave progress
      double _progressFromGeom=LNA;
      if(!IsNAv(point4OriginHigh)&&!IsNAv(flipTop)&&!IsNAv(flipBot))
      {
         double _origin=(direction==1?point4OriginLow:point4OriginHigh);
         double _extreme=(direction==1?NZv(cycleHigh,close+atr):NZv(cycleLow,close-atr));
         double _fzMid=(flipTop+flipBot)/2.0;
         double _totalMove=MathAbs(_extreme-_origin);
         double _toFzMid=MathAbs(_extreme-_fzMid);
         double _traveled=MathAbs(close-_origin);
         double _expProg=(_totalMove>1e-10?MinD(_traveled/_totalMove*60.0,60.0):30.0);
         double _retrMove=MathAbs(close-_extreme);
         double _retrProg=(_toFzMid>1e-10?MinD(_retrMove/MathMax(_toFzMid,1e-10)*40.0,40.0):0.0);
         double _retrWeight=MinD(obs_AbsorptionScore/40.0,1.0);
         _progressFromGeom=_expProg+_retrProg*_retrWeight;
      }
      double _geomProgress=NZv(_progressFromGeom,30.0);
      double _simAnchor=
         (sim_DemandReturn>=sim_Retracement&&sim_DemandReturn>=sim_Absorption&&sim_DemandReturn>=sim_Creation&&sim_DemandReturn>=sim_Expansion)?95.0:
         (sim_Retracement>=sim_Absorption&&sim_Retracement>=sim_Creation&&sim_Retracement>=sim_Expansion)?87.0:
         (sim_Absorption>=sim_Creation&&sim_Absorption>=sim_Expansion)?75.0:
         (sim_Creation>=sim_Liquidity&&sim_Creation>=sim_Expansion)?62.0:
         (sim_Liquidity>=sim_Induction&&sim_Liquidity>=sim_Expansion)?52.0:
         (sim_Induction>=sim_PreConv&&sim_Induction>=sim_Expansion)?43.0:
         (sim_PreConv>=sim_Expansion)?33.0:22.0;
      double _convWeight=MathMax(0.0,1.0-MathAbs(_simAnchor-47.5)/14.5);
      double _convAdjust=(convexityMaturity/100.0)*(_simAnchor-33.0)*0.50*_convWeight;
      double _physProgress=_simAnchor+_convAdjust;
      double rawWaveProgress=_geomProgress*0.60+_physProgress*0.40;
      waveProgress=waveProgress+bAlpha*(rawWaveProgress-waveProgress);
      waveProgress=MathMax(0.0,MathMin(100.0,waveProgress));

      double _bestSim=MathMax(sim_Expansion,MathMax(sim_PreConv,MathMax(sim_Induction,MathMax(sim_Liquidity,MathMax(sim_Creation,MathMax(sim_Absorption,MathMax(sim_Retracement,sim_DemandReturn)))))));
      double _geomConsistency=MinD(
         (!IsNAv(originToExtreme)&&originToExtreme>atr*2.0?30.0:0.0)+
         (!IsNAv(flipzoneWidth)&&flipzoneWidth<atr*4.0?25.0:0.0)+
         ((!IsNAv(cycleHigh)||!IsNAv(cycleLow))?20.0:0.0)+
         (direction!=0?25.0:0.0),100.0);
      double rawWaveModelFit=_bestSim*0.55+_geomConsistency*0.45;
      waveModelFit=waveModelFit+bAlpha*(rawWaveModelFit-waveModelFit);
      waveModelFit=MathMax(0.0,MathMin(100.0,waveModelFit));

      // belief engine (12A) — updates inductionEvidence/preConvEvidence for next bar
      preConvEvidence=(bullMomDecay||bearMomDecay);
      inductionEvidence=((direction==1&&bearImpulse&&structBias==1)||(direction==-1&&bullImpulse&&structBias==-1));
      bool liquidityEvidence=(obs_LiquidityScore>50.0&&obs_DecayScore>40.0);
      double _expPosMult=(waveProgress<40.0?1.20:waveProgress<60.0?0.80:0.50);
      double rawExpansionBelief=MinD((obs_ExpansionScore*0.45+(bullImpulse||bearImpulse?30.0:0.0)+(eff>P.effThresh*1.1?15.0:0.0)+sim_Expansion*0.10)*_expPosMult,100.0);
      double _convPosMult=((waveProgress>=30.0&&waveProgress<=65.0)?1.30:0.70);
      double rawConvexityBelief=MinD((obs_DecayScore*0.30+obs_CurvatureScore*0.25+(preConvEvidence?15.0:0.0)+(inductionEvidence?10.0:0.0)+(liquidityEvidence?5.0:0.0)+convexityMaturity*0.08)*_convPosMult,100.0);
      double _creatPosMult=((waveProgress>=45.0&&waveProgress<=68.0)?1.40:0.60);
      double rawCreationBelief=MinD(((convexityMaturity>50?convexityMaturity*0.12:0.0)+(obs_DecayScore>60?obs_DecayScore*0.20:0.0)+(obs_LiquidityScore>50?obs_LiquidityScore*0.20:0.0)+(obs_AbsorptionScore>20?obs_AbsorptionScore*0.15:0.0)+(!IsNAv(cycleHigh)&&!IsNAv(cycleLow)&&((direction==1&&high>=NZv(cycleHigh,high)*0.998)||(direction==-1&&low<=NZv(cycleLow,low)*1.002))?20.0:0.0)+sim_Creation*0.10+(posDistToCreation<15.0?(15.0-posDistToCreation)*1.0:0.0))*_creatPosMult,100.0);
      double rawAbsorptionBelief=MinD(obs_AbsorptionScore*0.50+(eff<P.effThresh*0.6?25.0:0.0)+(disp<P.dispThresh*0.5?15.0:0.0)+sim_Absorption*0.10,100.0);
      double rawRetracementBelief=MinD(((direction==1&&bearImpulse)||(direction==-1&&bullImpulse)?45.0:0.0)+(rawAbsorptionBelief>50?rawAbsorptionBelief*0.30:0.0)+(obs_CurvatureScore>40?15.0:0.0)+sim_Retracement*0.10,100.0);
      double rawDemandReturnBelief=MinD((!IsNAv(flipTop)&&!IsNAv(flipBot)&&close<=flipTop&&close>=flipBot?35.0:0.0)+(rawRetracementBelief>60?rawRetracementBelief*0.30:0.0)+(liqHeat>50?liqHeat*0.15:0.0)+(liqSweepBull||liqSweepBear?20.0:0.0)+sim_DemandReturn*0.10,100.0);
      expansionBelief=expansionBelief+bAlpha*(NZv(rawExpansionBelief)-expansionBelief);
      convexityBelief=convexityBelief+bAlpha*(NZv(rawConvexityBelief)-convexityBelief);
      creationBelief=creationBelief+bAlpha*(NZv(rawCreationBelief)-creationBelief);
      absorptionBelief=absorptionBelief+bAlpha*(NZv(rawAbsorptionBelief)-absorptionBelief);
      retracementBelief=retracementBelief+bAlpha*(NZv(rawRetracementBelief)-retracementBelief);
      demandReturnBelief=demandReturnBelief+bAlpha*(NZv(rawDemandReturnBelief)-demandReturnBelief);

      // prediction (12E) -> expectedNextPhase
      double predScore_Expansion=(waveProgress<35.0?(35.0-waveProgress)*1.0:0.0)+(expansionBelief>55?expansionBelief*0.30:0.0)+(convexityMaturity<25?20.0:0.0)+(posDistToCreation>30?15.0:0.0)+(htfAlign==direction&&direction!=0?15.0:0.0);
      double predScore_Convexity=(waveProgress>=25.0&&waveProgress<=60.0?30.0:0.0)+(convexityMaturity>20?convexityMaturity*0.30:0.0)+(obs_DecayScore>40?20.0:0.0)+(preConvEvidence?15.0:0.0);
      double predScore_Creation=(convexityMaturity>55?(convexityMaturity-55.0)*1.20:0.0)+(posDistToCreation<20.0?(20.0-posDistToCreation)*2.0:0.0)+(obs_LiquidityScore>55?20.0:0.0)+(liqSweepBull||liqSweepBear?15.0:0.0);
      double predScore_Absorption=(predScore_Creation>50?predScore_Creation*0.40:0.0)+(obs_AbsorptionScore>35?obs_AbsorptionScore*0.30:0.0)+(waveProgress>=60.0&&waveProgress<=78.0?15.0:0.0);
      double predScore_Retracement=(absorptionBelief>45?absorptionBelief*0.35:0.0)+(((direction==1&&bearMicroImpulse)||(direction==-1&&bullMicroImpulse))?25.0:0.0)+(waveProgress>=72.0&&waveProgress<=90.0?20.0:0.0)+(physicsConsensus<40?10.0:0.0);
      double predScore_DemandReturn=(retracementBelief>45?retracementBelief*0.35:0.0)+(posDistToDemand<20.0?(20.0-posDistToDemand)*1.50:0.0)+(liqSweepBull||liqSweepBear?20.0:0.0)+(waveProgress>=88.0?(waveProgress-88.0)*1.20:0.0);
      string expectedNextPhase=
         (predScore_DemandReturn>=predScore_Retracement&&predScore_DemandReturn>=predScore_Absorption&&predScore_DemandReturn>=predScore_Creation&&predScore_DemandReturn>=predScore_Convexity&&predScore_DemandReturn>=predScore_Expansion)?(direction==-1?"Supply Return":"Demand Return"):
         (predScore_Retracement>=predScore_Absorption&&predScore_Retracement>=predScore_Creation&&predScore_Retracement>=predScore_Convexity&&predScore_Retracement>=predScore_Expansion)?"Retracement":
         (predScore_Absorption>=predScore_Creation&&predScore_Absorption>=predScore_Convexity&&predScore_Absorption>=predScore_Expansion)?"Absorption":
         (predScore_Creation>=predScore_Convexity&&predScore_Creation>=predScore_Expansion)?(direction==-1?"New Low":"New High"):
         (predScore_Convexity>=predScore_Expansion)?"Expansion Pre-Convexity":"Expansion";
      bool predTransition=(ie1a_currentPhase!=lastIE1APhase);
      bool predSucceeded=(predTransition&&ie1a_currentPhase==lastExpectedPhase);
      lastExpectedPhase=expectedNextPhase; lastIE1APhase=ie1a_currentPhase;

      // adaptive confidence (12G)
      double confIncrease=(predSucceeded?3.0:0.0)+(physicsConsensus>70?2.0:0.0)+(htfAlign==direction&&direction!=0?1.5:0.0)+(dir_tf1==dir_tf2&&dir_tf1!=0?1.0:0.0);
      double confDecrease=(predTransition&&!predSucceeded?2.0:0.0)+(physicsDiff>60?2.0:0.0)+(htfAlign!=direction&&direction!=0?1.5:0.0)+(dir_tf1!=dir_tf2&&dir_tf1!=0&&dir_tf2!=0?1.0:0.0);
      modelConfidence=MathMax(10.0,MathMin(100.0,modelConfidence+confIncrease-confDecrease-P.confDecayRate*(modelConfidence-50.0)));


      //--- WAVE SPAWN ENGINE (Section 13) -------------------------
      bool _allowSpawn=(l0_dir!=0&&l0_dir!=direction);
      if(_allowSpawn)
      {
         int _newDir=l0_dir;
         double _obTop=(_newDir==1?lastPivotPrice:prevPivotPrice);
         double _obBot=(_newDir==1?prevPivotPrice:lastPivotPrice);
         int _anchBar=prevPivotBar;
         double _fzIP=(_anchBar>=0?FindInducPrice(h,l,i,_anchBar,_obTop,_obBot,P.inducLookback):LNA);
         _obTop=NZv(l0_p4High,_obTop); _obBot=NZv(l0_p4Low,_obBot);
         lastSpawnDir=_newDir; direction=_newDir; flipTop=_obTop; flipBot=_obBot; barsInZone=0; obBirthBar=i; contBar=-1;
         point4OriginHigh=_obTop; point4OriginLow=_obBot; point4OriginBar=i;
         flipzoneInducPrice=_fzIP;
         flipzoneInducLow=(!IsNAv(_fzIP)?_fzIP-atr*P.inducZoneWidth:LNA);
         flipzoneInducHigh=(!IsNAv(_fzIP)?_fzIP+atr*P.inducZoneWidth:LNA);
         inducExpOriginHigh=LNA;inducExpExtremeLow=LNA;inducExpOriginLow=LNA;inducExpExtremeHigh=LNA;
         inducRetrOriginHigh=LNA;inducRetrExtremeLow=LNA;inducRetrOriginLow=LNA;inducRetrExtremeHigh=LNA;
         inducZoneLow=LNA;inducZoneHigh=LNA;cycleHigh=high;cycleLow=low;isRecursiveWave=false;entryCycle=0;waveDepth=0;
      }
      if(direction==1&&high>NZv(cycleHigh,high)) cycleHigh=high;
      if(direction==-1&&low<NZv(cycleLow,low))   cycleLow=low;

      bool expInducBuyEv=(direction==1&&bearImpulse&&structBias==1);
      bool expInducSellEv=(direction==-1&&bullImpulse&&structBias==-1);
      if(expInducBuyEv&&IsNAv(inducExpOriginHigh)){ inducExpOriginHigh=NZv(point4OriginHigh,NZv(cycleHigh,high)); inducExpExtremeLow=low; inducZoneLow=NZv(point4OriginHigh,low)-atr*P.inducZoneWidth; inducZoneHigh=NZv(point4OriginHigh,low)+atr*P.inducZoneWidth; }
      if(expInducSellEv&&IsNAv(inducExpOriginLow)){ inducExpOriginLow=NZv(point4OriginLow,NZv(cycleLow,low)); inducExpExtremeHigh=high; inducZoneLow=NZv(point4OriginLow,high)-atr*P.inducZoneWidth; inducZoneHigh=NZv(point4OriginLow,high)+atr*P.inducZoneWidth; }
      if(!IsNAv(inducExpExtremeLow)&&direction==1&&low<inducExpExtremeLow){ inducExpExtremeLow=low; inducZoneLow=low-atr*P.inducZoneWidth; inducZoneHigh=low+atr*P.inducZoneWidth; }
      if(!IsNAv(inducExpExtremeHigh)&&direction==-1&&high>inducExpExtremeHigh){ inducExpExtremeHigh=high; inducZoneLow=high-atr*P.inducZoneWidth; inducZoneHigh=high+atr*P.inducZoneWidth; }

      nearFlipzone=(!IsNAv(flipTop)&&!IsNAv(flipBot)&&close<=flipTop*1.02&&close>=flipBot*0.98);
      bool retrInducBuyEv=(direction==1&&bullImpulse&&structBias==-1&&nearFlipzone);
      bool retrInducSellEv=(direction==-1&&bearImpulse&&structBias==1&&nearFlipzone);
      if(retrInducBuyEv&&IsNAv(inducRetrOriginLow)){ inducRetrOriginLow=NZv(cycleLow,low); inducRetrExtremeHigh=high; inducZoneLow=high-atr*P.inducZoneWidth; inducZoneHigh=high+atr*P.inducZoneWidth; }
      if(retrInducSellEv&&IsNAv(inducRetrOriginHigh)){ inducRetrOriginHigh=NZv(cycleHigh,high); inducRetrExtremeLow=low; inducZoneLow=low-atr*P.inducZoneWidth; inducZoneHigh=low+atr*P.inducZoneWidth; }
      if(!IsNAv(inducRetrExtremeHigh)&&direction==1&&high>inducRetrExtremeHigh){ inducRetrExtremeHigh=high; inducZoneLow=high-atr*P.inducZoneWidth; inducZoneHigh=high+atr*P.inducZoneWidth; }
      if(!IsNAv(inducRetrExtremeLow)&&direction==-1&&low<inducRetrExtremeLow){ inducRetrExtremeLow=low; inducZoneLow=low-atr*P.inducZoneWidth; inducZoneHigh=low+atr*P.inducZoneWidth; }

      closeInside=(!IsNAv(flipTop)&&!IsNAv(flipBot)&&close<=flipTop&&close>=flipBot);
      bool priceInDemand=(!IsNAv(flipBot)&&low<flipBot&&(!IsNAv(point4OriginHigh)&&low<=point4OriginHigh));
      bool priceInSupply=(!IsNAv(flipTop)&&high>flipTop&&(!IsNAv(point4OriginLow)&&high>=point4OriginLow));
      bool trueCHoCH_bull=(direction==1&&priceInDemand&&bullImpulse&&liqSweepOK);
      bool trueCHoCH_bear=(direction==-1&&priceInSupply&&bearImpulse&&liqSweepOK);
      bool structFlipBull=(direction==1&&bullConvShift&&structBias==-1);
      bool structFlipBear=(direction==-1&&bearConvShift&&structBias==1);
      bool recursiveTrigger=((trueCHoCH_bull||trueCHoCH_bear||structFlipBull||structFlipBear)&&(ie1a_currentPhase=="Demand Return"||ie1a_currentPhase=="Supply Return")&&demandReturnBelief>40&&direction!=0&&!IsNAv(flipTop));
      if(recursiveTrigger&&(recursiveFiredBar<0||(i-recursiveFiredBar)>P.resetBars)){ recursiveJustFired=true; recursiveFiredBar=i; recursiveComplete=true; }
      else recursiveJustFired=false;
      if(recursiveJustFired)
      {
         waveGeneration=waveGeneration+1; entryCycle=MathMin(entryCycle+1,4); isRecursiveWave=true; waveDepth=entryCycle;
         int _nextDir=(l0_dir!=0?l0_dir:((bullImpulse||bullConvShift)?1:-1));
         double _obTop2=(_nextDir==1?lastPivotPrice:prevPivotPrice);
         double _obBot2=(_nextDir==1?prevPivotPrice:lastPivotPrice);
         int _anchBar2=prevPivotBar;
         double _fzIP2=(_anchBar2>=0?FindInducPrice(h,l,i,_anchBar2,_obTop2,_obBot2,P.inducLookback):LNA);
         lastSpawnDir=_nextDir; direction=(l0_dir!=0?l0_dir:_nextDir); flipTop=_obTop2; flipBot=_obBot2; barsInZone=0; obBirthBar=i;
         point4OriginHigh=_obTop2; point4OriginLow=_obBot2; point4OriginBar=i;
         flipzoneInducPrice=_fzIP2; flipzoneInducLow=(!IsNAv(_fzIP2)?_fzIP2-atr*P.inducZoneWidth:LNA); flipzoneInducHigh=(!IsNAv(_fzIP2)?_fzIP2+atr*P.inducZoneWidth:LNA);
         inducExpOriginHigh=LNA;inducExpExtremeLow=LNA;inducExpOriginLow=LNA;inducExpExtremeHigh=LNA;
         inducRetrOriginHigh=LNA;inducRetrExtremeLow=LNA;inducRetrOriginLow=LNA;inducRetrExtremeHigh=LNA;
         inducZoneLow=LNA;inducZoneHigh=LNA;cycleHigh=high;cycleLow=low;contBar=i;
      }

      int barsSinceCont=(contBar>=0?i-contBar:(obBirthBar>=0?i-obBirthBar:0));
      bool bullInvalid=(direction==1&&!IsNAv(flipBot)&&close<flipBot-atr*0.5);
      bool bearInvalid=(direction==-1&&!IsNAv(flipTop)&&close>flipTop+atr*0.5);
      bool opposingMove=((direction==1&&bearImpulse)||(direction==-1&&bullImpulse));
      bool hardInvalid=(bullInvalid||bearInvalid);
      bool softReset=(barsSinceCont>P.resetBars&&opposingMove&&(ie1a_currentPhase!="Demand Return"&&ie1a_currentPhase!="Supply Return")&&demandReturnBelief<30&&expansionBelief<30&&!erf_suppressRotation);
      bool safeToReset=(hardInvalid||softReset);
      if(direction!=l0_dir&&safeToReset)
      {
         direction=0;lastSpawnDir=0;flipTop=LNA;flipBot=LNA;contBar=-1;obBirthBar=-1;barsInZone=0;isRecursiveWave=false;entryCycle=0;waveDepth=0;recursiveComplete=false;
      }

      //--- INDUCTION CLASSIFICATION (Section 14) ------------------
      bool inRetracementInducZone=(!IsNAv(pivL)&&!IsNAv(inducZoneLow)&&!IsNAv(inducZoneHigh)&&direction==1&&pivL>=inducZoneLow&&pivL<=inducZoneHigh&&retrInducBuyEv);
      bool inShortRetrInducZone=(!IsNAv(pivH)&&!IsNAv(inducZoneLow)&&!IsNAv(inducZoneHigh)&&direction==-1&&pivH>=inducZoneLow&&pivH<=inducZoneHigh&&retrInducSellEv);
      double inducConfidence=0.0;
      if(direction==1&&inRetracementInducZone) inducConfidence=1.0;
      else if(direction==1&&!IsNAv(pivL)&&!IsNAv(flipTop)&&!IsNAv(flipBot)&&pivL<flipTop&&pivL>flipBot&&!inRetracementInducZone) inducConfidence=-0.5;
      else if(direction==-1&&inShortRetrInducZone) inducConfidence=1.0;
      else if(direction==-1&&!IsNAv(pivH)&&!IsNAv(flipTop)&&!IsNAv(flipBot)&&pivH>flipBot&&pivH<flipTop&&!inShortRetrInducZone) inducConfidence=-0.5;
      bool retracementPreConvSeen=(nearFlipzone&&(bullMomDecay||bearMomDecay));
      bool retracementInductionConf=(inRetracementInducZone||inShortRetrInducZone);
      bool convexityComplete=(creationBelief>50||absorptionBelief>40);
      int flipzoneStagesComplete=(demandReturnBelief>75&&recursiveComplete?5:demandReturnBelief>60?4:retracementBelief>55?3:retracementInductionConf?2:retracementPreConvSeen?1:0);
      double flipzoneScore=(double)flipzoneStagesComplete/5.0*100.0;

      //--- CANONICAL TERMINAL RETURN PHASE (decision-level) -------
      // The M5 structure engine never emits Demand/Supply Return; derive it here
      // from the canonical lifecycle state so the entry gate is reachable.
      bool _retrFamily=(ie1a_currentPhase=="Absorption"||ie1a_currentPhase=="Retracement"||ie1a_currentPhase=="Retracement Pre-Convexity"||ie1a_currentPhase=="Retracement Induction"||ie1a_currentPhase=="Retracement Liquidity");
      bool inDemandReturn=(P.enableReturnPhase&&direction==1&&closeInside&&demandReturnBelief>50.0&&demandReturnBelief>=retracementBelief&&_retrFamily);
      bool inSupplyReturn=(P.enableReturnPhase&&direction==-1&&closeInside&&demandReturnBelief>50.0&&demandReturnBelief>=retracementBelief&&_retrFamily);
      string entryPhase=(inDemandReturn?"Demand Return":inSupplyReturn?"Supply Return":ie1a_currentPhase);

      //--- SCORING (Section 15) -----------------------------------
      double poiMid=((!IsNAv(flipTop)&&!IsNAv(flipBot))?(flipTop+flipBot)/2.0:LNA);
      double energy=(!IsNAv(poiMid)?MathAbs(close-poiMid)/MathMax(atr,1e-10):0.0);
      double sStruct=flipzoneScore*0.30;
      double sConv=MinD(MathAbs(csm)/MathMax(atr*P.convMult,1e-10)*25.0,25.0);
      double sEnergy=MinD(energy*10.0,20.0);
      double sEff=eff*15.0;
      double sVol=MinD((atr/MathMax(close,1e-10))*1000.0,10.0);
      double contProb=MinD(sStruct+sConv+sEnergy+sEff+sVol,100.0);
      string grade=(contProb>90?"A+":contProb>80?"A":contProb>70?"B":contProb>60?"C":"D");

      //--- BAYESIAN (Section 16) ----------------------------------
      double bayesStruct=(structBias==liveWaveDir?0.90:structBias==0?0.50:0.15);
      double bayesMomentum=((liveWaveDir==1&&vel>0&&acc>0)?0.85:(liveWaveDir==-1&&vel<0&&acc<0)?0.85:((liveWaveDir==1&&vel>0)||(liveWaveDir==-1&&vel<0))?0.60:0.30);
      double bayesLiq=(liqHeat>70?0.80:liqHeat>30?0.55:0.35);
      double bayesHTF=((liveHtfAlign==liveWaveDir&&liveHtfAlign!=0)?0.90:liveHtfAlign==0?0.55:0.20);
      double bayesDisp=(disp>P.dispThresh*1.5?0.85:disp>P.dispThresh?0.65:0.35);
      double bayesOB=(obFreshness>0.7?0.80:obFreshness>0.4?0.60:0.35);
      double bayesInduc=(inducConfidence>0?0.90:inducConfidence<0?0.20:0.50);
      double bayesFlipzone=(flipzoneStagesComplete>=4?0.92:flipzoneStagesComplete>=3?0.75:flipzoneStagesComplete>=2?0.58:flipzoneStagesComplete>=1?0.42:0.25);
      double logOdds=
         0.15*MathLog(MathMax(bayesStruct,1e-10)/MathMax(1.0-bayesStruct,1e-10))+
         0.14*MathLog(MathMax(bayesMomentum,1e-10)/MathMax(1.0-bayesMomentum,1e-10))+
         0.10*MathLog(MathMax(bayesLiq,1e-10)/MathMax(1.0-bayesLiq,1e-10))+
         0.14*MathLog(MathMax(bayesHTF,1e-10)/MathMax(1.0-bayesHTF,1e-10))+
         0.11*MathLog(MathMax(bayesDisp,1e-10)/MathMax(1.0-bayesDisp,1e-10))+
         0.07*MathLog(MathMax(bayesOB,1e-10)/MathMax(1.0-bayesOB,1e-10))+
         0.12*MathLog(MathMax(bayesInduc,1e-10)/MathMax(1.0-bayesInduc,1e-10))+
         0.17*MathLog(MathMax(bayesFlipzone,1e-10)/MathMax(1.0-bayesFlipzone,1e-10));
      double finalProb=1.0/(1.0+MathExp(-logOdds))*100.0;

      //--- SLIPPAGE & OPPORTUNITY (Section 18) --------------------
      double spreadEstimate=atr*0.05;
      double volatilityFactor=volRatio*0.10;
      double slippageCost=atr*volatilityFactor+spreadEstimate;
      double liqDepthPenalty=(liqHeat>70?atr*0.05:0.0);
      double totalSlippage=slippageCost+liqDepthPenalty;
      double baseTrend=eff*30.0;
      double impulseScore=(disp>P.dispThresh?20.0:0.0);
      double momentumScore=(phys_mom>0?10.0:-10.0);
      double accelScore=(acc>0?10.0:-10.0);
      double structScore=(structBias==1?20.0:structBias==-1?-20.0:0.0);
      double htfScore=(htfAlign==1?20.0:htfAlign==-1?-20.0:0.0);
      double liqScore=(wDensity<0.5?10.0:-5.0);
      double zoneScore=(closeInside?15.0:0.0);
      double inducScore=(inducConfidence>0?10.0:inducConfidence<0?-10.0:0.0);
      double fzStageScore=flipzoneStagesComplete*6.0;
      double beliefBonus=((direction==1&&demandReturnBelief>60)?demandReturnBelief*0.10:(direction==-1&&demandReturnBelief>60)?demandReturnBelief*0.10:0.0);
      double confMult=MathMax(0.7,MathMin(modelConfidence/100.0*1.3,1.3));
      double buyScore=(baseTrend+impulseScore+MathMax(momentumScore,0.0)+MathMax(accelScore,0.0)+MathMax(structScore,0.0)+MathMax(htfScore,0.0)+liqScore+zoneScore+MathMax(inducScore,0.0)+fzStageScore+beliefBonus+(fractalStackDir==1?fractalCtxScore*0.30:0.0))*confMult;
      double sellScore=(baseTrend+impulseScore+MathMax(-momentumScore,0.0)+MathMax(-accelScore,0.0)+MathMax(-structScore,0.0)+MathMax(-htfScore,0.0)+liqScore+zoneScore+MathMax(-inducScore,0.0)+fzStageScore+beliefBonus+(fractalStackDir==-1?fractalCtxScore*0.30:0.0))*confMult;
      double netEdge=buyScore-sellScore;
      double netEdgeAdjusted=netEdge-(totalSlippage/MathMax(atr,1e-10)*10.0);
      bool edgePassesFilter=(MathAbs(netEdgeAdjusted)>P.execThreshold);
      double buyProb=MathMin(MathMax(buyScore/279.5*100.0,0.0),100.0);
      double sellProb=MathMin(MathMax(sellScore/279.5*100.0,0.0),100.0);
      string liveDirective=(netEdgeAdjusted>25?"BUY PRESSURE":netEdgeAdjusted>10?"BULLISH BIAS":netEdgeAdjusted<-25?"SELL PRESSURE":netEdgeAdjusted<-10?"BEARISH BIAS":"NEUTRAL / WAIT");

      //--- HTF GATE (Section 19) ----------------------------------
      bool htfAligned=(direction!=0&&(htfAlign==direction||htfAlign==0));

      //--- EXECUTION LOCK (Section 20) ----------------------------
      int dynamicLockBars=(int)MathRound(P.baseLockBars*volMult);
      bool inducRearmLong=(direction==1&&inRetracementInducZone);
      bool inducRearmShort=(direction==-1&&inShortRetrInducZone);
      if(recursiveJustFired) engineArmed=true;
      if(inducRearmLong||inducRearmShort) engineArmed=true;
      bool withinGlobalLock=(lastSignalBar>=0&&(i-lastSignalBar)<dynamicLockBars);
      bool withinLongLock=(lastLongBar>=0&&(i-lastLongBar)<dynamicLockBars);
      bool withinShortLock=(lastShortBar>=0&&(i-lastShortBar)<dynamicLockBars);
      bool signalLocked=(withinGlobalLock&&!engineArmed);
      bool htfLongOK=(!P.requireHTFAlign||(htfBias1>=0&&htfBias2>=0));
      bool htfShortOK=(!P.requireHTFAlign||(htfBias1<=0&&htfBias2<=0));
      bool preConvOK_long=(!P.requirePreConv||retracementPreConvSeen);
      bool preConvOK_short=(!P.requirePreConv||retracementPreConvSeen);
      bool inducOK_long=(!P.requireInduction||retracementInductionConf);
      bool inducOK_short=(!P.requireInduction||retracementInductionConf);

      //--- STRUCTURE GATES (Section 4 tail) -----------------------
      bool structLongOK=(!P.requireStruct||(P.useStrictStructure&&structBias==1&&isHH)||(!P.useStrictStructure&&structBias==1));
      bool structShortOK=(!P.requireStruct||(P.useStrictStructure&&structBias==-1&&isLL)||(!P.useStrictStructure&&structBias==-1));

      //--- ENTRY SIGNALS (Section 21) -----------------------------
      bool gradeOK=(P.useStrictStructure?(grade=="A+"||grade=="A"||grade=="B"):(grade=="A+"||grade=="A"||grade=="B"||grade=="C"));
      bool beliefEntryLong=(direction==1&&entryPhase=="Demand Return"&&demandReturnBelief>50&&expansionBelief<60&&absorptionBelief>25);
      bool beliefEntryShort=(direction==-1&&entryPhase=="Supply Return"&&demandReturnBelief>50&&expansionBelief<60&&absorptionBelief>25);
      bool longSignal=(beliefEntryLong&&htfAligned&&gradeOK&&!signalLocked&&!withinLongLock&&edgePassesFilter&&preConvOK_long&&inducOK_long&&structLongOK&&liqSweepOK&&obFresh&&htfLongOK&&erf_entryGate);
      bool shortSignal=(beliefEntryShort&&htfAligned&&gradeOK&&!signalLocked&&!withinShortLock&&edgePassesFilter&&preConvOK_short&&inducOK_short&&structShortOK&&liqSweepOK&&obFresh&&htfShortOK&&erf_entryGate);
      if(longSignal){ lastSignalBar=i; lastLongBar=i; engineArmed=false; }
      if(shortSignal){ lastSignalBar=i; lastShortBar=i; engineArmed=false; }

      //--- F72 CURVE-LIFE ("is the trade alive?") -----------------
      double se5_comp=se5[j5].comp; int se5_recN=se5[j5].rec; double se5_dom=se5[j5].dom;
      f72comp[i]=se5_comp;
      double cmpNow=se5_comp;
      double cmpTighten=(i>=5? cmpNow-f72comp[i-5] : 0.0);
      int treeDepth=se5_recN;
      int curveBudgetDepth=MathMax(1,MathMin(4,1+(int)MathRound(se5_comp/33.0)));
      double eRes=re_residualEnergyScore;
      double cpForce=MaxD(0.0,MinD(100.0, cmpNow*0.50 + eRes*0.20 - treeDepth*12.0 + MaxD(0.0,cmpTighten)*0.8 + 8.0));
      string cpStateL=(cpForce>=60.0?"PERSISTING":cpForce<=35.0?"LEAKING":"NEUTRAL");
      int ownDir=direction;
      double ownOrig=(direction==1?NZv(point4OriginLow,se5_inv):direction==-1?NZv(point4OriginHigh,se5_inv):se5_inv);
      double ownExt=(direction==1?NZv(cycleHigh,close):direction==-1?NZv(cycleLow,close):close);
      bool attacking=(ownDir==1? high>=NZv(ownExt,high): ownDir==-1? low<=NZv(ownExt,low): false);
      bool trendImp=((ownDir==1&&bullImpulse)||(ownDir==-1&&bearImpulse));
      bool progressing=(attacking||trendImp);
      double retrX=((IsNAv(ownExt)||IsNAv(ownOrig)||ownExt==ownOrig)?50.0:MinD(100.0,MathAbs(ownExt-close)/MathMax(MathAbs(ownExt-ownOrig),1e-10)*100.0));
      bool recursionComplete=(curveBudgetDepth>0 && treeDepth>=curveBudgetDepth);
      double pFt=se240[j240].ft, pFb=se240[j240].fb, pSh=se240[j240].swH, pSl=se240[j240].swL;
      double parentThreat=(ownDir==1?((!IsNAv(pFt)&&pFt>close)?pFt:pSh):ownDir==-1?((!IsNAv(pFb)&&pFb<close)?pFb:pSl):LNA);
      double htfRoomAtr=(IsNAv(parentThreat)?LNA:MathAbs(parentThreat-close)/MathMax(atr,1e-10));
      string htfThreatL=(IsNAv(htfRoomAtr)?"—":htfRoomAtr>3.0?"CLEAR":htfRoomAtr>1.0?"APPROACHING":"AT ZONE");
      double life=MaxD(0.0,MinD(100.0, cpForce*0.45 + eRes*0.30 + (cmpTighten>0.0?12.0:0.0)
         - (recursionComplete&&!progressing?25.0:0.0) - (cpStateL=="LEAKING"&&!progressing?20.0:0.0)
         + (progressing?28.0:0.0) + (retrX<25.0?16.0:retrX<45.0?6.0:retrX>75.0?-12.0:0.0) + 10.0));
      // narrative lineage
      if(ownDir!=narrDir){ narrDir=ownDir; legX=(ownDir==1?high:ownDir==-1?low:LNA); legPBdepth=0.0; narrative=50.0; supVotes=0; degVotes=0; ArrayResize(seqRetr,0); ArrayResize(lifeSeq,0); }
      if(ownDir!=0 && !IsNAv(ownOrig))
      {
         bool newLegX=(ownDir==1? high>NZv(legX,high): low<NZv(legX,low));
         if(newLegX)
         {
            if(legPBdepth>6.0)
            {
               bool sup=(legPBdepth<=50.0 && cmpTighten>=-1.0);
               bool deg=(legPBdepth>=62.0 || cmpTighten<-3.0);
               int vote=(sup?1:deg?-1:0);
               supVotes+=(vote==1?1:0); degVotes+=(vote==-1?1:0);
               narrative=MaxD(0.0,MinD(100.0,narrative+vote*12.0+(cmpTighten>0.0?3.0:-3.0)));
               int sz=ArraySize(seqRetr); ArrayResize(seqRetr,sz+1); seqRetr[sz]=legPBdepth;
               if(ArraySize(seqRetr)>5){ for(int k=1;k<ArraySize(seqRetr);k++) seqRetr[k-1]=seqRetr[k]; ArrayResize(seqRetr,ArraySize(seqRetr)-1); }
               int sz2=ArraySize(lifeSeq); ArrayResize(lifeSeq,sz2+1); lifeSeq[sz2]=life;
               if(ArraySize(lifeSeq)>5){ for(int k=1;k<ArraySize(lifeSeq);k++) lifeSeq[k-1]=lifeSeq[k]; ArrayResize(lifeSeq,ArraySize(lifeSeq)-1); }
            }
            legX=(ownDir==1?high:low); legPBdepth=0.0;
         }
         else
         {
            double pbd=(MathAbs(NZv(legX,close)-ownOrig)>1e-9?MathAbs(NZv(legX,close)-close)/MathAbs(NZv(legX,close)-ownOrig)*100.0:0.0);
            legPBdepth=MaxD(legPBdepth,pbd);
         }
      }
      string narrStateL=(narrative>=65.0?"STRENGTHENING":narrative<=35.0?"WEAKENING":"HOLDING");
      wholeChainLife=wholeChainLife+0.02*(life-wholeChainLife);
      double chainVitality=(ArraySize(lifeSeq)>=2?MaxD(0.0,MinD(100.0,50.0+(lifeSeq[ArraySize(lifeSeq)-1]-lifeSeq[0]))):wholeChainLife);
      string chainScopeL=(life>=50.0?"healthy":chainVitality>=50.0?"CURVE only - chain intact":wholeChainLife>=45.0?"CHAIN weakening":"WHOLE CHAIN decaying");
      string aliveL=(life<=32.0?"DEAD":(life>=60.0||(progressing&&life>=45.0)||(htfThreatL=="AT ZONE"&&life>=45.0))?"ALIVE":"WEAKENING");
      int lifeDirL=((ownDir==0||(life>32.0&&life<45.0))?0:life<=32.0?-ownDir:ownDir);

      //--- TRADE STATE (Section 24) -------------------------------
      bool exitCondition=
         (tradeDirV==1&&bearBOS)||(tradeDirV==-1&&bullBOS)||
         (tradeDirV==1&&bearConvShift&&energy<energyPrev)||(tradeDirV==-1&&bullConvShift&&energy<energyPrev)||
         (tradeDirV==1&&htfAlign==-1)||(tradeDirV==-1&&htfAlign==1)||
         (tradeDirV!=0&&!obFresh)||(tradeDirV!=0&&safeToReset)||
         (tradeDirV==1&&bullInvalid)||(tradeDirV==-1&&bearInvalid)||
         (tradeDirV!=0&&(entryPhase=="Absorption"||entryPhase=="Retracement"));
      if(longSignal){ tradeDirV=1; exitFiredBar=-1; }
      else if(shortSignal){ tradeDirV=-1; exitFiredBar=-1; }
      else if(exitCondition&&tradeDirV!=0){ exitFiredBar=i; tradeDirV=0; }
      bool exitLatchActive=(exitFiredBar>=0&&(i-exitFiredBar)<3);

      energyPrev=energy;

      //--- capture final-bar outputs ------------------------------
      if(i==n-1)
      {
         fLong=longSignal; fShort=shortSignal; fExit=(exitCondition&&true); fExitLatch=exitLatchActive;
         fPhase=entryPhase; fGrade=grade; fDirective=liveDirective;
         fFinalProb=finalProb; fNetEdge=netEdgeAdjusted; fBuyProb=buyProb; fSellProb=sellProb;
         fTarget=se5_tgt; fInv=se5_inv; fFlipTop=flipTop; fFlipBot=flipBot; fAttr=eae_primaryAttractorPrice; fAtr=atr;
         fDir=direction; fTradeDir=tradeDirV; fStackDir=fractalStackDir; fHtfAlign=htfAlign;
         fCtx=fractalCtxScore; fLiq=liqHeat; fErf=erf_tradeReadiness; fDRB=demandReturnBelief;
         fPhaseCode=se5[j5].phase; fComp=se5_comp; fRec=se5_recN; fDom=se5_dom;
         fLife=life; fAlive=aliveL; fLifeDir=lifeDirL; fCp=cpStateL; fNarr=narrStateL; fChain=chainScopeL; fHtf=htfThreatL;
         fOwnOrig=ownOrig; fOwnExt=ownExt;
         barTime=tm[i];
      }
   } // end for

   //--- publish ----------------------------------------------------
   longSignal=fLong; shortSignal=fShort; exitNow=fExit; exitLatchActive=fExitLatch;
   outDir=fDir; tradeDir=fTradeDir; atr=fAtr;
   outFlipTop=fFlipTop; outFlipBot=fFlipBot; target=fTarget; invalidation=fInv; attractorPrice=fAttr;
   phase=fPhase; grade=fGrade; finalProb=fFinalProb; netEdgeAdjusted=fNetEdge;
   buyProb=fBuyProb; sellProb=fSellProb; directive=fDirective;
   fractalStackDir=fStackDir; fractalCtxScore=fCtx; htfAlign=fHtfAlign;
   liqHeatOut=fLiq; erfReadinessOut=fErf; demandReturnBeliefOut=fDRB;
   phaseCode=fPhaseCode; compIdx=fComp; recCount=fRec; domTransfer=fDom;
   lifeScore=fLife; aliveVerdict=fAlive; lifeTradeDir=fLifeDir; cpState=fCp;
   narrState=fNarr; chainScope=fChain; htfThreat=fHtf; ownerOrigin=fOwnOrig; ownerExtreme=fOwnExt;
   ready=true;
   return(true);
}

//+------------------------------------------------------------------+
//| Ideal-state similarity (Pine f_idealSim).                        |
//+------------------------------------------------------------------+
double IdealSim(const double eObs,const double dObs,const double vObs,const double cObs,
                const double eId,const double dId,const double vId,const double cId)
{
   double diff=MathPow(eObs-eId,2)+MathPow(dObs-dId,2)+MathPow(vObs-vId,2)+MathPow(cObs-cId,2);
   return(MathMax(0.0,100.0*(1.0-diff/4.0)));
}
//+------------------------------------------------------------------+


#endif // LETRA37_BRAIN_MQH
