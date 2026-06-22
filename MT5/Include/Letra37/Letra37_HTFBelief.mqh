//+------------------------------------------------------------------+
//|                                         Letra37_HTFBelief.mqh     |
//|   HTF belief engine  ==  Pine `f_htfBeliefs()` port.             |
//+------------------------------------------------------------------+
#property strict
#ifndef LETRA37_HTFBELIEF_MQH
#define LETRA37_HTFBELIEF_MQH
#include "Letra37_Series.mqh"

struct HtfBel
{
   datetime time;
   int      dir;
   double   expScr, decScr, curvScr, abScr, liqScr;
};

//+------------------------------------------------------------------+
//| Compute HTF belief series for a timeframe.                       |
//+------------------------------------------------------------------+
int ComputeHtfBeliefs(const string symbol,const ENUM_TIMEFRAMES tf,const int count,
                      const int atrLen,const double effThresh,const double dispThresh,
                      const double convMult,const int obLookback,HtfBel &out[])
{
   MqlRates r[];
   ArraySetAsSeries(r,false);
   int n=CopyRates(symbol,tf,0,count,r);
   if(n>2) n--;                                  // drop the still-forming bar
   if(n<=atrLen+obLookback+5) return(0);

   double h[],l[],c[];
   ArrayResize(h,n); ArrayResize(l,n); ArrayResize(c,n);
   for(int i=0;i<n;i++){ h[i]=r[i].high; l[i]=r[i].low; c[i]=r[i].close; }

   double atr[],dClose[],vel[],accArr[],convArr[],convSm[],absStep[],pathSum[];
   ArrayResize(dClose,n);
   for(int i=0;i<n;i++) dClose[i]=(i==0?0.0:c[i]-c[i-1]);
   ATR_RMA(h,l,c,atrLen,atr);
   EMAv(dClose,3,vel);
   ArrayResize(accArr,n); ArrayResize(convArr,n);
   for(int i=0;i<n;i++) accArr[i]=(i==0?0.0:vel[i]-vel[i-1]);
   for(int i=0;i<n;i++) convArr[i]=(i==0?0.0:accArr[i]-accArr[i-1]);
   EMAv(convArr,3,convSm);
   ArrayResize(absStep,n);
   for(int i=0;i<n;i++) absStep[i]=MathAbs(dClose[i]);
   RollSum(absStep,obLookback,pathSum);

   ArrayResize(out,n);
   for(int i=0;i<n;i++)
   {
      double _atr=atr[i];
      double _vel=vel[i], _velP=(i>0?vel[i-1]:0.0);
      double _acc=accArr[i], _accP=(i>0?accArr[i-1]:0.0);
      double _conv=convArr[i];
      double _convSm=convSm[i];
      double _convTh=_atr*convMult;
      double _move=(i>=obLookback?MathAbs(c[i]-c[i-obLookback]):MathAbs(c[i]-c[0]));
      double _ps=pathSum[i];
      double _eff=(_ps>0.0?_move/_ps:0.0);
      double _disp=(h[i]-l[i])/MathMax(_atr,1e-10);

      double _expScore=MinD(_eff/MathMax(effThresh,1e-10)*50.0+_disp/MathMax(dispThresh,1e-10)*50.0,100.0);
      double _decayScr=(MathAbs(_acc)<MathAbs(_accP)*0.8?MinD(MathAbs(_conv)/MathMax(_convTh,1e-10)*50.0,100.0):0.0);
      double _curvScr=MinD(MathAbs(_convSm)/MathMax(_convTh,1e-10)*50.0,100.0);
      double _abScr=((_eff<effThresh*0.7 && MathAbs(_vel)<MathAbs(_velP)*0.6)?60.0+_curvScr*0.4:_curvScr*0.3);
      double _liqScr=((MathAbs(_convSm)>_convTh*1.5 && _disp>dispThresh)?MinD(_curvScr*1.2,100.0):_curvScr*0.5);

      bool _bullImp=(_eff>effThresh && _vel>_velP && _acc>0 && c[i]>r[i].open && _disp>dispThresh);
      bool _bearImp=(_eff>effThresh && _vel<_velP && _acc<0 && c[i]<r[i].open && _disp>dispThresh);
      int _dir=(_bullImp?1:_bearImp?-1:0);

      out[i].time=r[i].time;
      out[i].dir=_dir;
      out[i].expScr=_expScore; out[i].decScr=_decayScr; out[i].curvScr=_curvScr;
      out[i].abScr=_abScr; out[i].liqScr=_liqScr;
   }
   return(n);
}

int HtfIndexAtTime(const HtfBel &arr[],const datetime target)
{
   int n=ArraySize(arr); int idx=-1;
   for(int i=0;i<n;i++){ if(arr[i].time<=target) idx=i; else break; }
   return(idx);
}
//+------------------------------------------------------------------+


#endif // LETRA37_HTFBELIEF_MQH
