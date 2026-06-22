//+------------------------------------------------------------------+
//|                                          Letra37_Network.mqh      |
//|   The Invisible Network node engine (V60 Part A) port.           |
//|   Detects rejection-wick "FU" levels across every timeframe      |
//|   (MN -> M5), scores each by authority (timeframe weight +       |
//|   revisits + strength) and produces: netBias, pressure, the      |
//|   primary attractor (the magnet price is pulled toward) and the  |
//|   FEZ corridor (nearest high-authority node above & below).      |
//+------------------------------------------------------------------+
#property strict
#ifndef LETRA37_NETWORK_MQH
#define LETRA37_NETWORK_MQH
#include "Letra37_Series.mqh"

struct FuBar
{
   datetime time;
   double   tip;     // LNA when no FU formed on this bar
   double   mid;
   int      dir;
   int      valid;   // 1 when an FU level is currently held
   double   score;
};

struct NetParams
{
   double wickFrac;
   int    lookback;
   int    authMin;
   int    nodeMax;
   int    dormantBars;
   int    historyBars;
   ENUM_TIMEFRAMES baseTF;   // chart / canonical rung
   int    baseBars;
};

//+------------------------------------------------------------------+
//| FU rejection-wick pool for one timeframe (V60 f_fuPool).         |
//+------------------------------------------------------------------+
int ComputeFuPool(const string symbol,const ENUM_TIMEFRAMES tf,const int count,
                  const double wf,const int lb,FuBar &out[])
{
   MqlRates r[]; ArraySetAsSeries(r,false);
   int n=CopyRates(symbol,tf,0,count,r);
   if(n>2) n--;
   if(n<lb+16) return(0);
   double o[],h[],l[],c[]; ArrayResize(o,n);ArrayResize(h,n);ArrayResize(l,n);ArrayResize(c,n);
   for(int i=0;i<n;i++){ o[i]=r[i].open;h[i]=r[i].high;l[i]=r[i].low;c[i]=r[i].close; }
   double atr[]; ATR_RMA(h,l,c,14,atr);
   ArrayResize(out,n);

   double tip=LNA,bH=LNA,bL=LNA,mid=LNA; int dir=0; bool have=false,conf=false;
   for(int i=0;i<n;i++)
   {
      double rng=MathMax(h[i]-l[i],1e-10);
      double pHi=(i>=1?HighestAt(h,i-1,lb):LNA);
      double pLo=(i>=1?LowestAt(l,i-1,lb):LNA);
      double uw=(h[i]-MathMax(o[i],c[i]))/rng;
      double lw=(MathMin(o[i],c[i])-l[i])/rng;
      bool localTop=(h[i]>=HighestAt(h,i,lb));
      bool localBot=(l[i]<=LowestAt(l,i,lb));
      bool bear=(uw>=wf && ((!IsNAv(pHi)&&h[i]>=pHi&&c[i]<pHi)||(localTop&&c[i]<o[i])));
      bool bull=(lw>=wf && ((!IsNAv(pLo)&&l[i]<=pLo&&c[i]>pLo)||(localBot&&c[i]>o[i])));
      if(bear){ dir=-1; tip=h[i]; bH=MathMax(o[i],c[i]); bL=MathMin(o[i],c[i]); mid=bH+(tip-bH)*0.5; have=true; conf=false; }
      else if(bull){ dir=1; tip=l[i]; bH=MathMax(o[i],c[i]); bL=MathMin(o[i],c[i]); mid=tip+(bL-tip)*0.5; have=true; conf=false; }
      if(have&&dir==-1&&!conf&&c[i]<bL) conf=true;
      if(have&&dir==1 &&!conf&&c[i]>bH) conf=true;
      double wk=((dir==-1&&have)?(tip-bH)/MathMax(atr[i],1e-10):(dir==1&&have)?(bL-tip)/MathMax(atr[i],1e-10):0.0);
      double score=20.0+MathMin(25.0,wk*15.0)+(conf?30.0:0.0)+(wk>1.0?15.0:0.0)+(wk>1.5?10.0:0.0);
      out[i].time=r[i].time;
      out[i].tip=(have?tip:LNA); out[i].mid=mid; out[i].dir=dir; out[i].valid=(have?1:0); out[i].score=score;
   }
   return(n);
}

//+------------------------------------------------------------------+
//| Align an FU series to the base timeline.                         |
//+------------------------------------------------------------------+
void AlignFu(const FuBar &src[],const datetime &bt[],int &idxOut[])
{
   int nm=ArraySize(bt), ns=ArraySize(src);
   ArrayResize(idxOut,nm);
   int j=0;
   for(int i=0;i<nm;i++)
   {
      while(j+1<ns && src[j+1].time<=bt[i]) j++;
      idxOut[i]=(ns>0 && src[0].time<=bt[i])?j:-1;
   }
}

//+------------------------------------------------------------------+
class CLetra37Network
{
public:
   bool   ready;
   int    netBias;          // +1/-1/0
   int    pressureDir;      // +1/-1/0
   double pressure;         // -100..100
   double attractorPrice;   // primary magnet on the bias side
   int    attractorWt;      // timeframe weight of the attractor node
   double fezHi, fezLo;     // FEZ corridor bounds
   int    nodeCount, liveNodes;

   CLetra37Network(){ ready=false; }
   bool Recompute(const string symbol,const NetParams &P);
};

//+------------------------------------------------------------------+
bool CLetra37Network::Recompute(const string symbol,const NetParams &P)
{
   ready=false;
   //--- base series ------------------------------------------------
   MqlRates r[]; ArraySetAsSeries(r,false);
   int n=CopyRates(symbol,P.baseTF,0,P.baseBars,r);
   if(n>2) n--;
   if(n<60) return(false);
   double c[],h[],l[]; datetime bt[];
   ArrayResize(c,n);ArrayResize(h,n);ArrayResize(l,n);ArrayResize(bt,n);
   for(int i=0;i<n;i++){ c[i]=r[i].close;h[i]=r[i].high;l[i]=r[i].low;bt[i]=r[i].time; }
   double atrA[]; ATR_RMA(h,l,c,14,atrA);
   double ema50[]; EMAv(c,50,ema50);

   //--- FU pools per TF (MN..M5) + weights -------------------------
   ENUM_TIMEFRAMES tfs[7]={PERIOD_MN1,PERIOD_W1,PERIOD_D1,PERIOD_H4,PERIOD_H1,PERIOD_M15,PERIOD_M5};
   int wts[7]={9,8,7,6,5,4,3};
   FuBar fu0[],fu1[],fu2[],fu3[],fu4[],fu5[],fu6[];
   ComputeFuPool(symbol,tfs[0],300, P.wickFrac,P.lookback,fu0);
   ComputeFuPool(symbol,tfs[1],400, P.wickFrac,P.lookback,fu1);
   ComputeFuPool(symbol,tfs[2],600, P.wickFrac,P.lookback,fu2);
   ComputeFuPool(symbol,tfs[3],800, P.wickFrac,P.lookback,fu3);
   ComputeFuPool(symbol,tfs[4],1200,P.wickFrac,P.lookback,fu4);
   ComputeFuPool(symbol,tfs[5],2000,P.wickFrac,P.lookback,fu5);
   ComputeFuPool(symbol,tfs[6],P.baseBars,P.wickFrac,P.lookback,fu6);

   int ix0[],ix1[],ix2[],ix3[],ix4[],ix5[],ix6[];
   AlignFu(fu0,bt,ix0); AlignFu(fu1,bt,ix1); AlignFu(fu2,bt,ix2); AlignFu(fu3,bt,ix3);
   AlignFu(fu4,bt,ix4); AlignFu(fu5,bt,ix5); AlignFu(fu6,bt,ix6);

   //--- registry ---------------------------------------------------
   double nPx[],nMid[],nSc[]; int nDir[],nWt[],nState[],nBar[],nRev[];
   ArrayResize(nPx,0);ArrayResize(nMid,0);ArrayResize(nSc,0);ArrayResize(nDir,0);
   ArrayResize(nWt,0);ArrayResize(nState,0);ArrayResize(nBar,0);ArrayResize(nRev,0);
   double prevTip[7]; for(int k=0;k<7;k++) prevTip[k]=LNA;
   int curBias=0;

   for(int i=0;i<n;i++)
   {
      // current aligned FU values per TF
      int idxs[7];
      idxs[0]=ix0[i]; idxs[1]=ix1[i]; idxs[2]=ix2[i]; idxs[3]=ix3[i];
      idxs[4]=ix4[i]; idxs[5]=ix5[i]; idxs[6]=ix6[i];
      // resolve netBias for this bar (highest TF valid wins, else ema50)
      curBias=0;
      for(int k=0;k<7;k++)
      {
         int ix=idxs[k]; if(ix<0) continue;
         FuBar fb; // fetch
         if(k==0) fb=fu0[ix]; else if(k==1) fb=fu1[ix]; else if(k==2) fb=fu2[ix];
         else if(k==3) fb=fu3[ix]; else if(k==4) fb=fu4[ix]; else if(k==5) fb=fu5[ix]; else fb=fu6[ix];
         if(fb.valid==1){ curBias=fb.dir; break; }
      }
      if(curBias==0) curBias=(c[i]>ema50[i]?1:c[i]<ema50[i]?-1:0);

      // add new nodes (only when a TF prints a NEW tip)
      for(int k=0;k<7;k++)
      {
         int ix=idxs[k]; if(ix<0) continue;
         FuBar fb;
         if(k==0) fb=fu0[ix]; else if(k==1) fb=fu1[ix]; else if(k==2) fb=fu2[ix];
         else if(k==3) fb=fu3[ix]; else if(k==4) fb=fu4[ix]; else if(k==5) fb=fu5[ix]; else fb=fu6[ix];
         if(fb.valid==1 && !IsNAv(fb.tip) && (IsNAv(prevTip[k])||fb.tip!=prevTip[k]))
         {
            int sz=ArraySize(nPx);
            ArrayResize(nPx,sz+1);ArrayResize(nMid,sz+1);ArrayResize(nSc,sz+1);ArrayResize(nDir,sz+1);
            ArrayResize(nWt,sz+1);ArrayResize(nState,sz+1);ArrayResize(nBar,sz+1);ArrayResize(nRev,sz+1);
            nPx[sz]=fb.tip; nMid[sz]=fb.mid; nDir[sz]=fb.dir; nSc[sz]=fb.score;
            nWt[sz]=wts[k]; nState[sz]=0; nBar[sz]=i; nRev[sz]=0;
            prevTip[k]=fb.tip;
            if(ArraySize(nPx)>P.nodeMax)
            {
               for(int q=1;q<ArraySize(nPx);q++){ nPx[q-1]=nPx[q];nMid[q-1]=nMid[q];nSc[q-1]=nSc[q];nDir[q-1]=nDir[q];nWt[q-1]=nWt[q];nState[q-1]=nState[q];nBar[q-1]=nBar[q];nRev[q-1]=nRev[q]; }
               int ns2=ArraySize(nPx)-1;
               ArrayResize(nPx,ns2);ArrayResize(nMid,ns2);ArrayResize(nSc,ns2);ArrayResize(nDir,ns2);
               ArrayResize(nWt,ns2);ArrayResize(nState,ns2);ArrayResize(nBar,ns2);ArrayResize(nRev,ns2);
            }
         }
      }

      // age / consume nodes
      double natr=atrA[i];
      for(int q=0;q<ArraySize(nPx);q++)
      {
         if(nState[q]==2) continue;
         double np=nPx[q]; int nd=nDir[q]; int age=i-nBar[q];
         if(nd==-1 ? c[i]>np : c[i]<np){ nState[q]=2; continue; }
         if(MathAbs(c[i]-np)<natr*0.25) nRev[q]=nRev[q]+1;
         int wtn=nWt[q];
         nState[q]=(age>P.historyBars*wtn?3:age>P.dormantBars*wtn?1:0);
      }
   }

   //--- final-bar metrics ------------------------------------------
   netBias=curBias;
   double closeF=c[n-1];
   double bullAuth=0.0,bearAuth=0.0; int elig=0;
   double attrRank=-1.0; int attrIdx=-1;
   double fezHiA=0.0,fezLoA=0.0; fezHi=LNA; fezLo=LNA;
   for(int q=0;q<ArraySize(nPx);q++)
   {
      if(nState[q]==2) continue;
      double a=nSc[q]+nWt[q]*4.0+nRev[q]*3.0;
      if(a<P.authMin) continue;
      elig++;
      double np=nPx[q]; int nd=nDir[q]; int wt=nWt[q];
      if(nd==1) bullAuth+=a; else if(nd==-1) bearAuth+=a;
      bool onBias=(netBias==-1?np<closeF:np>closeF);
      if(onBias){ double rk=wt*1000.0+a; if(rk>attrRank){ attrRank=rk; attrIdx=q; } }
      if(np>closeF && a>fezHiA){ fezHi=np; fezHiA=a; }
      if(np<closeF && a>fezLoA){ fezLo=np; fezLoA=a; }
   }
   pressure=((bullAuth+bearAuth)>0?(bullAuth-bearAuth)/(bullAuth+bearAuth)*100.0:0.0);
   pressureDir=(pressure>12?1:pressure<-12?-1:0);
   attractorPrice=(attrIdx>=0?nPx[attrIdx]:LNA);
   attractorWt=(attrIdx>=0?nWt[attrIdx]:0);
   nodeCount=ArraySize(nPx); liveNodes=elig;
   ready=true;
   return(true);
}
//+------------------------------------------------------------------+
#endif // LETRA37_NETWORK_MQH
