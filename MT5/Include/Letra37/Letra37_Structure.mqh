//+------------------------------------------------------------------+
//|                                         Letra37_Structure.mqh    |
//|   Fixed-timeframe structure engine  ==  V60 `f_se()` port.       |
//|   The upgraded 14-PHASE lifecycle authority:                     |
//|     Expansion -> Pre-Convexity -> Induction -> Liquidity ->      |
//|     New High/Low -> Transition -> Retracement -> HTF Flip Zone ->|
//|     Induction -> Liquidation -> Terminal Curve -> Demand/Supply  |
//|     Return.                                                       |
//|   Driven by a compression index, recursive-transition counting   |
//|   and dominance transfer (recursive wave's share of control).    |
//|   DIR-FIX spawn: the order block is ordered by ACTUAL price and   |
//|   invalidation is pinned to the protective extreme.              |
//+------------------------------------------------------------------+
#property strict
#ifndef LETRA37_STRUCTURE_MQH
#define LETRA37_STRUCTURE_MQH
#include "Letra37_Series.mqh"

//--- One bar of structure-engine output ----------------------------
struct SeBar
{
   datetime time;
   int      dir;     // origin-based wave dir (_dirLabel) using this TF close
   int      phase;   // canonical phase code 0..14 (V60 14-phase lifecycle)
   double   swH, swL, pswH, pswL;
   int      bos, choch;
   double   p4h, p4l, inv, tgt, ft, fb;
   double   frzS, wp, cm, mf;
   double   comp;    // compression index 0..100 (high = tight curves)
   int      rec;     // recursive-transition count (Phase-2 CHoCHs after extreme)
   double   dom;     // dominance transfer 0..100 (recursive wave share; 50 = handoff)
};

//--- Engine parameters (mirror the Pine inputs passed to f_se) -----
struct SeParams
{
   int    pivotLen;
   int    structLen;
   int    atrLen;
   double effThresh;
   double dispThresh;
   double convMult;
   double impulseAtrMult;
   double chochBuffer;
   int    effLen;
};

//+------------------------------------------------------------------+
//| Phase code -> canonical lifecycle string (V60 f_phaseStr).       |
//+------------------------------------------------------------------+
string SePhaseStr(const int c)
{
   switch(c)
   {
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
      default: return("Point 4 Origin");
   }
}

//+------------------------------------------------------------------+
//| Short phase-family label (V60 f_famS) for multi-TF panels.       |
//+------------------------------------------------------------------+
string SeFamShort(const int ph)
{
   string p=SePhaseStr(ph);
   if(StringFind(p,"Transition")>=0)      return("Transition");
   if(StringFind(p,"Terminal")>=0)        return("Terminal");
   if(StringFind(p,"Liquidation")>=0)     return("Liquidation");
   if(StringFind(p,"HTF Flip")>=0)        return("Flip Zone");
   if(StringFind(p,"Induction")>=0 && StringFind(p,"Expansion")<0) return("Induction");
   if(StringFind(p,"Pre-Convexity")>=0)   return("Pre-Conv");
   if(StringFind(p,"Liquidity")>=0)       return("Liquidity");
   if(StringFind(p,"New High")>=0 || StringFind(p,"New Low")>=0) return("Creation");
   if(StringFind(p,"Return")>=0)          return("Return");
   if(StringFind(p,"Retracement")>=0)     return("Retracement");
   return("Expansion");
}

//+------------------------------------------------------------------+
//| Compute the full f_se output series for a timeframe.             |
//| Returns number of bars produced (0 on failure).                  |
//+------------------------------------------------------------------+
int ComputeStructureEngine(const string symbol,const ENUM_TIMEFRAMES tf,
                           const int count,const SeParams &p,SeBar &out[])
{
   MqlRates r[];
   ArraySetAsSeries(r,false);
   int n=CopyRates(symbol,tf,0,count,r);
   if(n>2) n--;                                  // drop the still-forming bar (act on closed bars only)
   if(n<=p.pivotLen*3+p.atrLen+5) return(0);

   double o[],h[],l[],c[];
   ArrayResize(o,n); ArrayResize(h,n); ArrayResize(l,n); ArrayResize(c,n);
   for(int i=0;i<n;i++){ o[i]=r[i].open; h[i]=r[i].high; l[i]=r[i].low; c[i]=r[i].close; }

   //--- physics series -------------------------------------------------
   double atr[],dClose[],vel[],csmIn[],csm[],pathSum[];
   ArrayResize(dClose,n);
   for(int i=0;i<n;i++) dClose[i]=(i==0?0.0:c[i]-c[i-1]);
   ATR_RMA(h,l,c,p.atrLen,atr);
   EMAv(dClose,3,vel);
   double acc[],conv[];
   ArrayResize(acc,n); ArrayResize(conv,n); ArrayResize(csmIn,n);
   for(int i=0;i<n;i++) acc[i]=(i==0?0.0:vel[i]-vel[i-1]);
   for(int i=0;i<n;i++) conv[i]=(i==0?0.0:acc[i]-acc[i-1]);
   for(int i=0;i<n;i++) csmIn[i]=conv[i];
   EMAv(csmIn,3,csm);
   double absStep[]; ArrayResize(absStep,n);
   for(int i=0;i<n;i++) absStep[i]=MathAbs(dClose[i]);
   RollSum(absStep,p.effLen,pathSum);

   //--- pivots ---------------------------------------------------------
   double pH[],pL[];
   PivotHigh(h,p.pivotLen,p.pivotLen,pH);
   PivotLow(l,p.pivotLen,p.pivotLen,pL);

   ArrayResize(out,n);

   //--- persistent (var) state ----------------------------------------
   double curSH=LNA,curSL=LNA,prSH=LNA,prSL=LNA;
   double lastP=LNA,prevP=LNA; int lastD=0,prevD=0;
   int    dir=0; double ft=LNA,fb=LNA,p4h=LNA,p4l=LNA,inv=LNA,tgt=LNA,cycH=LNA,cycL=LNA;
   bool   bos1=false,bos2=false; double protSw=LNA,protSw2=LNA,indOrig=LNA,indExt=LNA;
   bool   indBrk=false; int lastDirSeen=0;
   int    recBrk=0; bool recArm=true;             // recursive-transition counter
   int    pst=0;                                  // 14-state phase machine

   for(int i=0;i<n;i++)
   {
      double _atr=atr[i];
      double _vel=vel[i];
      double _velP=(i>0?vel[i-1]:0.0);
      double _acc=acc[i];
      double _accP=(i>0?acc[i-1]:0.0);
      double _csm=csm[i];
      double _mv=(i>=p.effLen ? MathAbs(c[i]-c[i-p.effLen]) : MathAbs(c[i]-c[0]));
      double _ps=pathSum[i];
      double _eff=(_ps>0.0 ? _mv/_ps : 0.0);
      double _disp=(h[i]-l[i])/MathMax(_atr,1e-10);
      bool _bullImp=(_eff>p.effThresh && _vel>_velP && _acc>0 && c[i]>o[i] && _disp>p.dispThresh);
      bool _bearImp=(_eff>p.effThresh && _vel<_velP && _acc<0 && c[i]<o[i] && _disp>p.dispThresh);
      bool _bullDec=(MathAbs(_acc)<MathAbs(_accP)*0.8 && _vel>0);
      bool _bearDec=(MathAbs(_acc)<MathAbs(_accP)*0.8 && _vel<0);

      double _pH=pH[i];
      double _pL=pL[i];

      //--- swings
      if(!IsNAv(_pH)){ prSH=(IsNAv(curSH)?_pH:curSH); curSH=_pH; }
      if(!IsNAv(_pL)){ prSL=(IsNAv(curSL)?_pL:curSL); curSL=_pL; }

      //--- pivot memory (impulse + OB origin)
      double _eP=LNA; int _eD=0;
      if(!IsNAv(_pH)){ _eP=_pH; _eD=1; }
      else if(!IsNAv(_pL)){ _eP=_pL; _eD=-1; }
      if(_eD!=0){ prevP=lastP; prevD=lastD; lastP=_eP; lastD=_eD; }

      //--- BOS / CHoCH
      bool _bullBOS=(!IsNAv(prSH) && c[i]>prSH);
      bool _bearBOS=(!IsNAv(prSL) && c[i]<prSL);
      bool _bullCH =(!IsNAv(prSH) && c[i]>prSH+_atr*p.chochBuffer);
      bool _bearCH =(!IsNAv(prSL) && c[i]<prSL-_atr*p.chochBuffer);

      //--- impulse
      bool _eLong =(!IsNAv(_pH) && prevD==-1 && (_pH-prevP)>_atr*p.impulseAtrMult);
      bool _eShort=(!IsNAv(_pL) && prevD==1  && (prevP-_pL)>_atr*p.impulseAtrMult);

      //--- direction / point4 / invalidation / target spawn (DIR-FIX) -----
      bool _hasCtx=(dir!=0 && !IsNAv(ft));
      bool _flipDn=(dir==1  && _bearCH);
      bool _flipUp=(dir==-1 && _bullCH);
      bool _isRev =((_eLong && dir==-1) || (_eShort && dir==1) || _flipUp || _flipDn);
      bool _spawn =((_eLong || _eShort || _flipUp || _flipDn) && (!_hasCtx || _isRev));
      if(_spawn)
      {
         int _nd=(_eLong?1:_eShort?-1:_flipUp?1:-1);
         double _hi=MathMax(lastP,prevP);          // order the OB by ACTUAL price
         double _lo=MathMin(lastP,prevP);
         double _obT=_hi, _obB=_lo;
         dir=_nd; ft=_obT; fb=_obB; p4h=_obT; p4l=_obB;
         cycH=h[i]; cycL=l[i];
         inv=(_nd==1?_lo:_hi);                      // pin invalidation to protective extreme
         double _rng=((!IsNAv(prSH) && !IsNAv(prSL))?MathAbs(prSH-prSL):_atr*5.0);
         tgt=(_nd==1?NZv(_obT,c[i])+_rng:NZv(_obB,c[i])-_rng);
      }
      if(dir==1)  cycH=(IsNAv(cycH)?h[i]:MathMax(cycH,h[i]));
      if(dir==-1) cycL=(IsNAv(cycL)?l[i]:MathMin(cycL,l[i]));

      int _bosOut=(_bullBOS?1:_bearBOS?-1:0);
      int _chOut =(_bullCH?1:_bearCH?-1:0);

      //--- opposing-BOS / inducement-break tracking -----------------------
      bool _reset=(dir!=lastDirSeen);
      lastDirSeen=dir;
      if(_reset){ bos1=false; bos2=false; protSw=LNA; protSw2=LNA; indOrig=LNA; indExt=LNA; indBrk=false; }
      if(dir==1  && !IsNAv(_pL)){ protSw2=protSw; protSw=_pL; }
      if(dir==-1 && !IsNAv(_pH)){ protSw2=protSw; protSw=_pH; }
      bool _oppBOS=((dir==1 && !IsNAv(protSw) && c[i]<protSw) || (dir==-1 && !IsNAv(protSw) && c[i]>protSw));
      if(!bos1 && _oppBOS){ bos1=true; indOrig=(dir==1?NZv(cycH,h[i]):NZv(cycL,l[i])); }
      if(bos1 && !bos2 && _oppBOS && !IsNAv(protSw2) && (dir==1?c[i]<protSw2:c[i]>protSw2)) bos2=true;
      if(bos1 && dir==1)  indExt=(IsNAv(indExt)?c[i]:MathMin(indExt,c[i]));
      if(bos1 && dir==-1) indExt=(IsNAv(indExt)?c[i]:MathMax(indExt,c[i]));
      if(bos2 && !IsNAv(indOrig))
      {
         if(dir==1  && c[i]>indOrig) indBrk=true;
         if(dir==-1 && c[i]<indOrig) indBrk=true;
      }

      //--- scores ---------------------------------------------------------
      double _convScore=MinD(MathAbs(_csm)/MathMax(_atr*p.convMult,1e-10)*50.0,100.0);
      double _expScore =MinD(_eff/MathMax(p.effThresh,1e-10)*50.0 + _disp/MathMax(p.dispThresh,1e-10)*50.0,100.0);
      double _velPabs=MathAbs(_velP);
      double _absScore=((_eff<p.effThresh*0.7 && MathAbs(_vel)<_velPabs*0.6)?60.0+_convScore*0.4:_convScore*0.3);
      bool _momExpStrong=(_eff>p.effThresh*0.75 && (dir==1?_vel>0:_vel<0));
      bool _momDecaying =(dir==1?_bullDec:_bearDec);
      bool _momCounter  =(dir==1?_bearImp:_bullImp);
      bool _momExhaust  =(_eff<p.effThresh*0.65 && _absScore>40.0);
      bool _physConvexDevel=(_convScore>35.0);
      bool _physTransfer   =(_convScore>48.0 || _absScore>40.0);
      bool _physCapacityLow=(_absScore>45.0 || _eff<p.effThresh*0.6);

      //--- direction (origin-based) + geometry ----------------------------
      int   _wdir   =(!IsNAv(inv)?(c[i]>inv?1:c[i]<inv?-1:dir):dir);
      bool  _atFlip =(!IsNAv(ft) && !IsNAv(fb) && c[i]<=ft && c[i]>=fb);
      bool  _expanding=(_momExpStrong || _eLong || _eShort || (_wdir==1?_bullImp:_bearImp));
      bool  _atExtreme=(_wdir==1 ? h[i]>=NZv(cycH,h[i]) : _wdir==-1 ? l[i]<=NZv(cycL,l[i]) : false);
      double _extr  =(_wdir==1 ? NZv(cycH,c[i]) : NZv(cycL,c[i]));
      bool  _extended=(!IsNAv(inv) && MathAbs(_extr-inv)>_atr*1.5);
      double _fzMid =((!IsNAv(ft) && !IsNAv(fb))?(ft+fb)/2.0:LNA);
      double _retrFrac=((!IsNAv(_fzMid) && MathAbs(_extr-_fzMid)>1e-10)?MathAbs(_extr-c[i])/MathAbs(_extr-_fzMid):0.0);
      double _compIdx=MinD(100.0,MaxD(0.0,(1.0-MinD(_disp/MathMax(p.dispThresh,1e-10),1.0))*60.0+(1.0-MinD(_eff/MathMax(p.effThresh,1e-10),1.0))*40.0));

      //--- recursive transition counting ----------------------------------
      bool _phase2CH=((dir==1 && _bearCH) || (dir==-1 && _bullCH));
      if(_reset || (_atExtreme && _extended)){ recBrk=0; recArm=true; }
      if((dir==1 && !IsNAv(_pH)) || (dir==-1 && !IsNAv(_pL))) recArm=true;
      if((_phase2CH || _oppBOS) && recArm && !_atExtreme){ recBrk=recBrk+1; recArm=false; }

      //--- dominance transfer ---------------------------------------------
      double _recDom=MinD(100.0,MaxD(recBrk*(30.0-_compIdx*0.15),_retrFrac*80.0));
      bool   _transferDone=(_recDom>=50.0);

      //--- single-latch 14-phase state machine (0 -> 13) ------------------
      if(_reset) pst=0;
      if(dir!=0 && !_reset)
      {
         if(pst==0 && _expanding) pst=1;
         if(pst==1 && !_atExtreme && _momDecaying && _physConvexDevel) pst=2;
         if(pst==2 && !_atExtreme && _momCounter && _physTransfer) pst=3;
         if(pst==3 && !_atExtreme && (bos1 || bos2 || indBrk) && _physTransfer) pst=4;
         if(pst>=1 && pst<=7 && _atExtreme && _extended) pst=5;
         if(pst==5 && !_atExtreme && (recBrk>=1 || _momExhaust)) pst=7;
         if(pst==7 && _transferDone) pst=8;
         if(pst==8 && _atFlip) pst=9;
         if(pst==9 && ((dir==1 && _bullImp) || (dir==-1 && _bearImp))) pst=10;
         if(pst==10 && (_oppBOS || _physCapacityLow)) pst=11;
         if(pst==11 && ((dir==1 && l[i]<fb) || (dir==-1 && h[i]>ft))) pst=12;
         if(pst==12 && ((dir==1 && _bullCH) || (dir==-1 && _bearCH))) pst=13;
      }
      int _phase=pst;
      if(_phase==5  && dir==-1) _phase=6;
      if(_phase==13 && dir==-1) _phase=14;

      double _wp=(pst==0?5.0:pst==1?15.0:pst==2?25.0:pst==3?33.0:pst==4?42.0:pst==5?55.0:
                  pst==7?65.0:pst==8?75.0:pst==9?85.0:pst==10?90.0:pst==11?94.0:pst==12?97.0:100.0);
      double _cm=MinD(_convScore,100.0);
      double _mf=MinD(MathMax(_expScore,MathMax(_absScore,_convScore))*0.70+(dir!=0?30.0:0.0),100.0);
      double _frzS=MinD((_eLong||_eShort?50.0:0.0)+_expScore*0.30+_convScore*0.20,100.0);
      int _dirLabel=_wdir;

      out[i].time=r[i].time;
      out[i].dir=_dirLabel;
      out[i].phase=_phase;
      out[i].swH=curSH; out[i].swL=curSL; out[i].pswH=prSH; out[i].pswL=prSL;
      out[i].bos=_bosOut; out[i].choch=_chOut;
      out[i].p4h=p4h; out[i].p4l=p4l; out[i].inv=inv; out[i].tgt=tgt; out[i].ft=ft; out[i].fb=fb;
      out[i].frzS=_frzS; out[i].wp=_wp; out[i].cm=_cm; out[i].mf=_mf;
      out[i].comp=_compIdx; out[i].rec=recBrk; out[i].dom=_recDom;
   }
   return(n);
}

//+------------------------------------------------------------------+
//| Return index of latest SeBar with time <= target (or -1).        |
//+------------------------------------------------------------------+
int SeIndexAtTime(const SeBar &arr[],const datetime target)
{
   int n=ArraySize(arr);
   int idx=-1;
   for(int i=0;i<n;i++)
   {
      if(arr[i].time<=target) idx=i; else break;
   }
   return(idx);
}
//+------------------------------------------------------------------+
#endif // LETRA37_STRUCTURE_MQH
