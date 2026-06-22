//+------------------------------------------------------------------+
//|                                            Letra37_Series.mqh     |
//|   Streaming TA helpers used by the Letra 37 MT5 port.            |
//|   All functions operate on chronological arrays (index 0 = oldest|
//|   ... index n-1 = newest), matching Pine Script bar order.       |
//+------------------------------------------------------------------+
#property copyright "Letra 37 MT5 Port"
#property strict
#ifndef LETRA37_SERIES_MQH
#define LETRA37_SERIES_MQH

//--- NA sentinel (mirrors Pine `na` for float series) --------------
#define LNA  DBL_MAX

bool   IsNAv(const double x){ return(x==LNA || !MathIsValidNumber(x)); }
double NZv(const double x, const double d=0.0){ return(IsNAv(x) ? d : x); }
double MinD(const double a,const double b){ return(a<b?a:b); }
double MaxD(const double a,const double b){ return(a>b?a:b); }

//+------------------------------------------------------------------+
//| True Range -> Wilder RMA (Pine ta.atr)                           |
//+------------------------------------------------------------------+
void ATR_RMA(const double &h[],const double &l[],const double &c[],const int n,double &out[])
{
   int sz=ArraySize(h);
   ArrayResize(out,sz);
   if(sz==0) return;
   double tr[]; ArrayResize(tr,sz);
   for(int i=0;i<sz;i++)
   {
      double hl=h[i]-l[i];
      if(i==0){ tr[i]=hl; continue; }
      double hc=MathAbs(h[i]-c[i-1]);
      double lc=MathAbs(l[i]-c[i-1]);
      tr[i]=MathMax(hl,MathMax(hc,lc));
   }
   // seed with SMA of first n TR values
   double seed=0.0; int seedCnt=MathMin(n,sz);
   for(int i=0;i<seedCnt;i++) seed+=tr[i];
   seed/= (seedCnt>0?seedCnt:1);
   for(int i=0;i<sz;i++)
   {
      if(i<n-1) out[i]=seed;                          // warmup region
      else if(i==n-1) out[i]=seed;
      else out[i]=(out[i-1]*(n-1)+tr[i])/n;           // Wilder smoothing
   }
}

//+------------------------------------------------------------------+
//| EMA (Pine ta.ema). Seeds with first source value.                |
//+------------------------------------------------------------------+
void EMAv(const double &src[],const int n,double &out[])
{
   int sz=ArraySize(src);
   ArrayResize(out,sz);
   if(sz==0) return;
   double a=2.0/(n+1.0);
   out[0]=src[0];
   for(int i=1;i<sz;i++) out[i]=out[i-1]+a*(src[i]-out[i-1]);
}

//+------------------------------------------------------------------+
//| SMA (Pine ta.sma).                                               |
//+------------------------------------------------------------------+
void SMAv(const double &src[],const int n,double &out[])
{
   int sz=ArraySize(src);
   ArrayResize(out,sz);
   double run=0.0;
   for(int i=0;i<sz;i++)
   {
      run+=src[i];
      if(i>=n) run-=src[i-n];
      int cnt=MathMin(i+1,n);
      out[i]=run/cnt;
   }
}

//+------------------------------------------------------------------+
//| Rolling sum over n bars (Pine math.sum).                         |
//+------------------------------------------------------------------+
void RollSum(const double &src[],const int n,double &out[])
{
   int sz=ArraySize(src);
   ArrayResize(out,sz);
   double run=0.0;
   for(int i=0;i<sz;i++)
   {
      run+=src[i];
      if(i>=n) run-=src[i-n];
      out[i]=run;
   }
}

//+------------------------------------------------------------------+
//| Pivot high (Pine ta.pivothigh src,left,right).                   |
//| out[i] = pivot price (high at i-right) when confirmed at bar i,  |
//| else LNA. Strict-greater on both sides.                          |
//+------------------------------------------------------------------+
void PivotHigh(const double &h[],const int left,const int right,double &out[])
{
   int sz=ArraySize(h);
   ArrayResize(out,sz);
   for(int i=0;i<sz;i++) out[i]=LNA;
   for(int i=left+right;i<sz;i++)
   {
      int p=i-right;                       // candidate bar
      double v=h[p];
      bool isPivot=true;
      for(int k=p-left;k<=p+right && isPivot;k++)
      {
         if(k==p) continue;
         if(h[k]>=v) isPivot=false;
      }
      if(isPivot) out[i]=v;
   }
}

//+------------------------------------------------------------------+
//| Pivot low (Pine ta.pivotlow).                                    |
//+------------------------------------------------------------------+
void PivotLow(const double &l[],const int left,const int right,double &out[])
{
   int sz=ArraySize(l);
   ArrayResize(out,sz);
   for(int i=0;i<sz;i++) out[i]=LNA;
   for(int i=left+right;i<sz;i++)
   {
      int p=i-right;
      double v=l[p];
      bool isPivot=true;
      for(int k=p-left;k<=p+right && isPivot;k++)
      {
         if(k==p) continue;
         if(l[k]<=v) isPivot=false;
      }
      if(isPivot) out[i]=v;
   }
}

//+------------------------------------------------------------------+
//| Highest / lowest over the last n bars at index i.                |
//+------------------------------------------------------------------+
double HighestAt(const double &h[],const int i,const int n)
{
   int start=MathMax(0,i-n+1);
   double m=h[start];
   for(int k=start+1;k<=i;k++) if(h[k]>m) m=h[k];
   return m;
}
double LowestAt(const double &l[],const int i,const int n)
{
   int start=MathMax(0,i-n+1);
   double m=l[start];
   for(int k=start+1;k<=i;k++) if(l[k]<m) m=l[k];
   return m;
}
//+------------------------------------------------------------------+


#endif // LETRA37_SERIES_MQH
