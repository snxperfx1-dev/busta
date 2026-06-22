//+------------------------------------------------------------------+
//|                                            Letra37_Trade.mqh      |
//|   Institutional-grade execution & risk manager for the Letra 37  |
//|   autonomous EA. Handles risk-% sizing, ATR/structure stops &    |
//|   targets, break-even, trailing, daily-loss & drawdown halts,    |
//|   spread & session filters and broker-safe order operations.     |
//+------------------------------------------------------------------+
#property strict
#ifndef LETRA37_TRADE_MQH
#define LETRA37_TRADE_MQH
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

//--- risk / execution configuration --------------------------------
struct RiskConfig
{
   ulong  magic;
   long   deviationPoints;
   // sizing
   bool   useFixedLot;
   double fixedLot;
   double riskPercent;          // % of equity risked per trade
   double maxLot;
   // stops / targets (in ATR multiples unless noted)
   double slAtrMult;            // base SL distance in ATR
   double tpAtrMult;            // base TP distance in ATR (0 = use target/R)
   double minRR;                // minimum reward:risk; if structural TP < this, extend
   bool   useStructuralStop;    // anchor SL beyond flip zone / invalidation
   double structBufferAtr;      // extra ATR buffer beyond structural level
   // management
   bool   useBreakEven;
   double beTriggerR;           // move to BE after this many R of profit
   double beLockAtr;            // lock-in distance (ATR) at BE
   bool   useTrailing;
   double trailAtrMult;         // trailing distance in ATR
   double trailStartR;          // begin trailing after this many R
   bool   closeOnExitSignal;    // close when engine raises exit
   // guards
   double maxSpreadPoints;
   double dailyLossLimitPct;    // halt new trades if daily loss exceeds %
   double maxDrawdownPct;       // halt new trades if equity DD from peak exceeds %
   bool   useSession;
   int    sessionStartHour;     // server time
   int    sessionEndHour;
   bool   oneTradePerBar;
};

//+------------------------------------------------------------------+
class CLetra37Trade
{
private:
   CTrade         m_trade;
   CPositionInfo  m_pos;
   string         m_symbol;
   RiskConfig     m_cfg;
   double         m_point;
   double         m_tick;
   double         m_tickValue;
   int            m_digits;
   double         m_volMin, m_volMax, m_volStep;
   // guards state
   double         m_dayStartEquity;
   int            m_dayStamp;
   double         m_peakEquity;
   datetime       m_lastTradeBar;

public:
   bool           halted;
   string         haltReason;

   CLetra37Trade(){ halted=false; haltReason=""; m_lastTradeBar=0; }

   bool Init(const string sym,const RiskConfig &cfg)
   {
      m_symbol=sym; m_cfg=cfg;
      m_point   = SymbolInfoDouble(sym,SYMBOL_POINT);
      m_tick    = SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
      m_tickValue=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
      m_digits  = (int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
      m_volMin  = SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
      m_volMax  = SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
      m_volStep = SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
      if(m_tick<=0) m_tick=m_point;
      m_trade.SetExpertMagicNumber(cfg.magic);
      m_trade.SetDeviationInPoints(cfg.deviationPoints);
      m_trade.SetTypeFillingBySymbol(sym);
      m_trade.SetAsyncMode(false);
      m_dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      m_peakEquity=m_dayStartEquity;
      m_dayStamp=DayStamp();
      return(true);
   }

   //--- position helpers ------------------------------------------
   bool HasPosition()
   {
      for(int i=PositionsTotal()-1;i>=0;i--)
         if(m_pos.SelectByIndex(i) && m_pos.Symbol()==m_symbol && m_pos.Magic()==m_cfg.magic)
            return(true);
      return(false);
   }
   int PositionDir() // +1 long, -1 short, 0 none
   {
      for(int i=PositionsTotal()-1;i>=0;i--)
         if(m_pos.SelectByIndex(i) && m_pos.Symbol()==m_symbol && m_pos.Magic()==m_cfg.magic)
            return(m_pos.PositionType()==POSITION_TYPE_BUY?1:-1);
      return(0);
   }

   //--- daily / drawdown guards -----------------------------------
   int DayStamp(){ MqlDateTime t; TimeToStruct(TimeCurrent(),t); return(t.year*10000+t.mon*100+t.day); }

   void UpdateGuards()
   {
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq>m_peakEquity) m_peakEquity=eq;
      int d=DayStamp();
      if(d!=m_dayStamp){ m_dayStamp=d; m_dayStartEquity=eq; halted=false; haltReason=""; }

      if(m_cfg.dailyLossLimitPct>0)
      {
         double lossPct=(m_dayStartEquity-eq)/MathMax(m_dayStartEquity,1e-6)*100.0;
         if(lossPct>=m_cfg.dailyLossLimitPct){ halted=true; haltReason="Daily loss limit reached"; }
      }
      if(m_cfg.maxDrawdownPct>0)
      {
         double ddPct=(m_peakEquity-eq)/MathMax(m_peakEquity,1e-6)*100.0;
         if(ddPct>=m_cfg.maxDrawdownPct){ halted=true; haltReason="Max drawdown reached"; }
      }
   }

   bool SpreadOK()
   {
      if(m_cfg.maxSpreadPoints<=0) return(true);
      double sp=(double)SymbolInfoInteger(m_symbol,SYMBOL_SPREAD);
      return(sp<=m_cfg.maxSpreadPoints);
   }
   bool SessionOK()
   {
      if(!m_cfg.useSession) return(true);
      MqlDateTime t; TimeToStruct(TimeCurrent(),t);
      int hr=t.hour;
      if(m_cfg.sessionStartHour<=m_cfg.sessionEndHour)
         return(hr>=m_cfg.sessionStartHour && hr<m_cfg.sessionEndHour);
      // overnight wrap
      return(hr>=m_cfg.sessionStartHour || hr<m_cfg.sessionEndHour);
   }

   //--- lot sizing -------------------------------------------------
   double NormalizeVolume(double v)
   {
      if(m_volStep>0) v=MathFloor(v/m_volStep+0.5)*m_volStep;
      v=MathMax(m_volMin,MathMin(m_volMax,v));
      return(v);
   }
   double LotForRisk(const double slDistancePrice)
   {
      if(m_cfg.useFixedLot) return(NormalizeVolume(m_cfg.fixedLot));
      if(slDistancePrice<=0) return(NormalizeVolume(m_volMin));
      double equity=AccountInfoDouble(ACCOUNT_EQUITY);
      double riskMoney=equity*m_cfg.riskPercent/100.0;
      double ticks=slDistancePrice/m_tick;
      double lossPerLot=ticks*m_tickValue;
      if(lossPerLot<=0) return(NormalizeVolume(m_volMin));
      double lots=riskMoney/lossPerLot;
      lots=MathMin(lots,m_cfg.maxLot);
      return(NormalizeVolume(lots));
   }

   //--- open --------------------------------------------------------
   // dir: +1 long / -1 short. flip/inv/target/attractor from the brain.
   bool OpenTrade(const int dir,const double atr,const double flipTop,const double flipBot,
                  const double target,const double invalidation,const double attractor)
   {
      if(halted || !SpreadOK() || !SessionOK()) return(false);
      if(m_cfg.oneTradePerBar)
      {
         datetime bt=iTime(m_symbol,PERIOD_M5,0);
         if(bt==m_lastTradeBar) return(false);
      }
      double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
      double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
      double entry=(dir==1?ask:bid);

      //--- stop loss -----------------------------------------------
      double slAtr=atr*m_cfg.slAtrMult;
      double sl;
      if(dir==1)
      {
         double atrStop=entry-slAtr;
         double structStop=atrStop;
         if(m_cfg.useStructuralStop)
         {
            double anchor=flipBot;
            if(anchor==DBL_MAX || anchor<=0) anchor=invalidation;
            if(anchor!=DBL_MAX && anchor>0) structStop=anchor-atr*m_cfg.structBufferAtr;
         }
         sl=MathMin(atrStop,structStop);      // farther (safer) of the two for longs
         if(sl>=entry) sl=entry-slAtr;
      }
      else
      {
         double atrStop=entry+slAtr;
         double structStop=atrStop;
         if(m_cfg.useStructuralStop)
         {
            double anchor=flipTop;
            if(anchor==DBL_MAX || anchor<=0) anchor=invalidation;
            if(anchor!=DBL_MAX && anchor>0) structStop=anchor+atr*m_cfg.structBufferAtr;
         }
         sl=MathMax(atrStop,structStop);
         if(sl<=entry) sl=entry+slAtr;
      }

      double risk=MathAbs(entry-sl);
      if(risk<=0) return(false);

      //--- take profit ---------------------------------------------
      double tp=0;
      if(m_cfg.tpAtrMult>0) tp=(dir==1?entry+atr*m_cfg.tpAtrMult:entry-atr*m_cfg.tpAtrMult);
      else
      {
         double t=target;
         bool tValid=(t!=DBL_MAX && t>0 && (dir==1?t>entry:t<entry)); // must be on the correct side
         if(!tValid) t=(dir==1?entry+risk*m_cfg.minRR:entry-risk*m_cfg.minRR);
         tp=t;
      }
      // enforce minimum RR
      double rr=MathAbs(tp-entry)/risk;
      if(rr<m_cfg.minRR) tp=(dir==1?entry+risk*m_cfg.minRR:entry-risk*m_cfg.minRR);

      //--- respect broker min stop distance ------------------------
      double stopLevel=(double)SymbolInfoInteger(m_symbol,SYMBOL_TRADE_STOPS_LEVEL)*m_point;
      if(stopLevel>0)
      {
         if(dir==1)
         {
            if(entry-sl<stopLevel) sl=entry-stopLevel;
            if(tp-entry<stopLevel) tp=entry+stopLevel;
         }
         else
         {
            if(sl-entry<stopLevel) sl=entry+stopLevel;
            if(entry-tp<stopLevel) tp=entry-stopLevel;
         }
         risk=MathAbs(entry-sl);
      }

      double lots=LotForRisk(risk);
      if(lots<m_volMin) return(false);

      sl=NormalizePrice(sl); tp=NormalizePrice(tp);
      bool ok=(dir==1)?
         m_trade.Buy(lots,m_symbol,0.0,sl,tp,"Letra37"):
         m_trade.Sell(lots,m_symbol,0.0,sl,tp,"Letra37");
      if(ok) m_lastTradeBar=iTime(m_symbol,PERIOD_M5,0);
      return(ok);
   }

   double NormalizePrice(const double p){ return(NormalizeDouble(p,m_digits)); }

   //--- manage open position (BE / trailing / exit) ----------------
   void ManagePosition(const double atr,const bool exitSignal)
   {
      if(!m_pos.Select(m_symbol)) return;
      if(m_pos.Magic()!=m_cfg.magic) return;

      int dir=(m_pos.PositionType()==POSITION_TYPE_BUY?1:-1);
      double entry=m_pos.PriceOpen();
      double curSL=m_pos.StopLoss();
      double curTP=m_pos.TakeProfit();
      double price=(dir==1?SymbolInfoDouble(m_symbol,SYMBOL_BID):SymbolInfoDouble(m_symbol,SYMBOL_ASK));

      if(m_cfg.closeOnExitSignal && exitSignal)
      {
         m_trade.PositionClose(m_symbol);
         return;
      }

      double initRisk=MathAbs(entry-curSL);
      if(initRisk<=0) initRisk=atr*m_cfg.slAtrMult;
      double profit=(dir==1?price-entry:entry-price);
      double rNow=profit/MathMax(initRisk,1e-9);

      double newSL=curSL;

      //--- break-even ----------------------------------------------
      if(m_cfg.useBreakEven && rNow>=m_cfg.beTriggerR)
      {
         double be=(dir==1?entry+atr*m_cfg.beLockAtr:entry-atr*m_cfg.beLockAtr);
         if(dir==1 && (curSL==0 || be>curSL)) newSL=be;
         if(dir==-1&& (curSL==0 || be<curSL)) newSL=be;
      }

      //--- trailing ------------------------------------------------
      if(m_cfg.useTrailing && rNow>=m_cfg.trailStartR)
      {
         double trail=(dir==1?price-atr*m_cfg.trailAtrMult:price+atr*m_cfg.trailAtrMult);
         if(dir==1 && trail>newSL) newSL=trail;
         if(dir==-1&& (newSL==0 || trail<newSL)) newSL=trail;
      }

      if(newSL!=curSL && newSL!=0)
      {
         double stopLevel=(double)SymbolInfoInteger(m_symbol,SYMBOL_TRADE_STOPS_LEVEL)*m_point;
         bool valid=(dir==1?(price-newSL>=stopLevel && newSL>curSL):(newSL-price>=stopLevel && (curSL==0||newSL<curSL)));
         if(valid) m_trade.PositionModify(m_symbol,NormalizePrice(newSL),curTP);
      }
   }

   void CloseAll()
   {
      if(m_pos.Select(m_symbol) && m_pos.Magic()==m_cfg.magic)
         m_trade.PositionClose(m_symbol);
   }
};
//+------------------------------------------------------------------+


#endif // LETRA37_TRADE_MQH
