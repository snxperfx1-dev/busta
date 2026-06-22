//+------------------------------------------------------------------+
//|                                                  Letra37_EA.mq5   |
//|     Autonomous MT5 port of the "Letra 37" engine, upgraded with  |
//|     the V60 stack:                                               |
//|       - 14-PHASE structure engine (f_se) — Expansion ... Demand/ |
//|         Supply Return, driven by compression / recursion /       |
//|         dominance transfer.                                      |
//|       - F72 "is the trade alive?" curve-life score (ALIVE /      |
//|         WEAKENING / DEAD) for trade management.                  |
//|       - Invisible Network node engine (netBias, pressure,        |
//|         primary attractor, FEZ corridor).                        |
//|       - Adaptive timeframe ladder (climbs above H1).             |
//|     The Letra decision layer (Bayesian / edge / belief entries)  |
//|     is kept as the entry authority — no Senseei meta-layer.      |
//|                                                                  |
//|  AUTHORITY HIERARCHY:                                            |
//|    1. Letra execution/decision layer (buy/sell edge, grade,      |
//|       Bayesian prob, execution lock, belief entries + exitNow)   |
//|       is the PRECISE AUTHORITY for entries and exits.            |
//|    2. The 14-phase structure engine FEEDS that layer (it is the  |
//|       lifecycle input, not a separate decision maker).           |
//|    3. F72 curve-life and the Invisible Network are SUBORDINATE   |
//|       advisory inputs: they may abandon early / tighten / supply |
//|       confluence, but never enter against Letra and never hold a |
//|       position open against a Letra exit.                        |
//|                                                                  |
//|  INSTALL:                                                        |
//|    - Copy  MT5/Include/Letra37 -> <Terminal>/MQL5/Include/        |
//|    - Copy  MT5/Experts/Letra37 -> <Terminal>/MQL5/Experts/        |
//|    - Compile, attach to an M5 chart (works on any TF via ladder).|
//+------------------------------------------------------------------+
#property copyright "Letra 37 MT5 Port"
#property version   "2.00"
#property strict

#include <Letra37/Letra37_Brain.mqh>
#include <Letra37/Letra37_Network.mqh>
#include <Letra37/Letra37_Trade.mqh>

//--- entry source selector -----------------------------------------
enum ENUM_ENTRYMODE
{
   ENTRY_BELIEF = 0,   // belief-gated reversal arrows only (Section 21)
   ENTRY_DOE    = 1,   // synthesized directional command only (net-edge PRESSURE)
   ENTRY_BOTH   = 2    // take either (default)
};

//====================== ENGINE INPUTS (mirror Pine) ================
input string  GRP0           = "===== Core ====="; // ---
input int     InpPivotLen        = 5;       // Pivot Length
input int     InpAtrLen          = 14;      // ATR Length
input int     InpEffLen          = 10;      // Efficiency Lookback
input int     InpResetBars       = 20;      // Min Bars Before Reset

input string  GRP1           = "===== Filters ====="; // ---
input double  InpImpulseAtrMult  = 1.5;     // Impulse ATR Multiple
input double  InpEffThresh        = 0.65;   // Efficiency Threshold
input double  InpDispThresh       = 1.5;    // Displacement ATR Threshold
input double  InpConvMult         = 0.01;   // Convexity ATR Multiplier
input int     InpAcceptBars       = 2;      // Flipzone Acceptance Bars
input int     InpObLookback       = 8;      // Order Block Lookback Bars
input int     InpObMaxBars        = 50;     // OB Max Valid Bars

input string  GRP2           = "===== Structure ====="; // ---
input bool    InpUseStrictStruct  = true;   // Use Strict Structure
input int     InpStructLen        = 10;     // Structure Pivot Length
input bool    InpRequireStruct    = true;   // Require Structure Confirm
input double  InpChochBufferATR   = 0.75;   // Direction CHoCH Buffer (ATR)

input string  GRP3           = "===== Inducement ====="; // ---
input int     InpInducLookback    = 80;     // Inducement Lookback Bars
input double  InpInducZoneWidth   = 0.25;   // Inducement Zone Half-Width (ATR)
input bool    InpRequirePreConv   = true;   // Require Pre-Convexity Evidence
input bool    InpRequireInduction = true;   // Require Induction Evidence

input string  GRP4           = "===== Liquidity ====="; // ---
input double  InpLiqRadius        = 0.25;   // Liquidity Radius (x ATR)
input double  InpLiqAgeDecay      = 0.95;   // Age Decay Factor
input bool    InpRequireLiqSweep  = true;   // Require Liquidity Sweep
input int     InpLiqSweepLookback = 10;     // Sweep Lookback Bars

input string  GRP5           = "===== Execution Logic ====="; // ---
input ENUM_ENTRYMODE InpEntryMode = ENTRY_BOTH; // Entry source (belief arrows / DOE command / both)
input double  InpDoeThreshold     = 25.0;   // DOE: net-edge PRESSURE threshold for command entry
input int     InpBaseLockBars     = 10;     // Base Lock Bars After Entry
input bool    InpRequireHTFAlign  = false;  // Require HTF Bias Alignment
input double  InpExecThreshold    = 5.0;    // Net Edge Execution Threshold

input string  GRP6           = "===== Intelligence ====="; // ---
input int     InpBeliefSmooth     = 3;      // Belief EMA Smoothing
input double  InpConfDecayRate    = 0.02;   // Confidence Decay Rate

input string  GRP7           = "===== Energy Resolution Framework ====="; // ---
input double  InpErfResW          = 0.25;   // ERF Recursive Completion Weight
input double  InpErfResidW        = 0.20;   // ERF Delivered Energy Weight
input double  InpErfConfW         = 0.15;   // ERF Confidence Weight
input double  InpErfEntryThresh   = 45.0;   // ERF Entry Gate Threshold
input bool    InpErfGateEnabled   = true;   // ERF Enable Entry Gate
input bool    InpEnableReturnPhase= false;  // Promote return-phase from belief (off: 14-phase engine emits it natively)

input string  GRPH           = "===== History Depth (bars per rung) ====="; // ---
input int     InpBarsM1           = 4000;   // Rung1 history bars
input int     InpBarsM3           = 3000;   // Rung2 history bars
input int     InpBarsM5           = 3000;   // Rung3 (canonical) history bars
input int     InpBarsM15          = 2500;   // Rung4 history bars
input int     InpBarsH1           = 1500;   // Rung5 history bars
input int     InpBarsH4           = 1000;   // Rung6 history bars

//====================== INVISIBLE NETWORK INPUTS ==================
input string  GRPN           = "===== Invisible Network ====="; // ---
input bool    InpUseNetwork       = true;   // Compute the Invisible Network engine
input double  InpNetWickFrac      = 0.30;   // FU spike: min wick / range
input int     InpNetLookback      = 3;      // FU spike: structure lookback
input int     InpNetAuthMin       = 45;     // Min node authority
input int     InpNetNodeMax        = 250;   // Max remembered nodes
input int     InpNetDormantBars   = 120;    // Bars until dormant
input int     InpNetHistoryBars   = 600;    // Bars until historical
input bool    InpNetBiasFilter    = false;  // Require netBias agreement for entries
input bool    InpNetTarget        = false;  // Use network attractor as the take-profit magnet

//====================== F72 CURVE-LIFE MANAGEMENT =================
// AUTHORITY: the Letra execution/decision layer (belief entries + edge/grade/
// Bayesian + execution lock + exitNow) is the precise authority for ENTRIES and
// EXITS. F72 curve-life is a SUBORDINATE management assist: it may abandon early
// (DEAD) or tighten (WEAKENING), but it never enters against Letra and never holds
// a position open against a Letra exit (AliveHold defaults OFF for that reason).
input string  GRPF           = "===== F72 Curve-Life Management (subordinate to Letra) ====="; // ---
input bool    InpUseLifeMgmt      = true;   // Use curve-life as a management assist
input bool    InpLifeDeadExit     = true;   // DEAD: abandon (close) early — protective only
input bool    InpLifeFlip         = false;  // DEAD: also flip (lets F72 enter; off = Letra-only entries)
input bool    InpLifeWeakTighten  = true;   // WEAKENING: tighten the stop
input double  InpLifeTightenAtr   = 1.0;    // WEAKENING tighten distance (ATR)
input bool    InpLifeAliveHold    = false;  // ALIVE: ignore Letra exit (NOT recommended — overrides the authority)

//====================== EXECUTION / RISK INPUTS ====================
input string  GRPT           = "===== Trade Engine ====="; // ---
input bool    InpEnableTrading    = true;   // Enable live order execution
input long    InpMagic            = 370037; // Magic number
input long    InpDeviation        = 20;     // Max slippage (points)
input bool    InpReverseOnSignal  = true;   // Close & reverse on opposite signal

input string  GRPR           = "===== Position Sizing ====="; // ---
input bool    InpUseFixedLot      = false;  // Use fixed lot (else risk %)
input double  InpFixedLot         = 0.10;   // Fixed lot size
input double  InpRiskPercent      = 0.75;   // Risk % of equity per trade
input double  InpMaxLot           = 25.0;   // Max lot cap

input string  GRPS           = "===== Stops & Targets ====="; // ---
input double  InpSlAtrMult        = 1.5;    // Base SL distance (ATR)
input double  InpTpAtrMult        = 0.0;    // TP distance (ATR); 0 = use wave target/RR
input double  InpMinRR            = 1.8;    // Minimum reward:risk
input bool    InpUseStructStop    = true;   // Anchor SL beyond flip/invalidation
input double  InpStructBufferAtr  = 0.30;   // Extra ATR buffer beyond structure

input string  GRPM           = "===== Trade Management ====="; // ---
input bool    InpUseBreakEven     = true;   // Move to break-even
input double  InpBeTriggerR       = 1.0;    // BE trigger (R multiple)
input double  InpBeLockAtr        = 0.10;   // BE lock distance (ATR)
input bool    InpUseTrailing      = true;   // Trailing stop
input double  InpTrailAtrMult     = 2.0;    // Trail distance (ATR)
input double  InpTrailStartR      = 1.5;    // Start trailing (R multiple)
input bool    InpCloseOnExit      = true;   // Close on engine exit signal

input string  GRPG           = "===== Guards & Filters ====="; // ---
input double  InpMaxSpreadPoints  = 80;     // Max spread (points); 0 = off
input double  InpDailyLossLimit   = 4.0;    // Daily loss limit (%); 0 = off
input double  InpMaxDrawdown      = 15.0;   // Max equity drawdown (%); 0 = off
input bool    InpUseSession       = false;  // Restrict to trading session
input int     InpSessionStart     = 7;      // Session start hour (server)
input int     InpSessionEnd       = 21;     // Session end hour (server)
input bool    InpOneTradePerBar   = true;   // Max one entry per bar

input string  GRPD           = "===== Diagnostics ====="; // ---
input bool    InpVerbose          = true;   // Print decisions to log
input bool    InpShowPanel        = true;   // On-chart status panel

//====================== GLOBALS ====================================
CLetra37Brain   g_brain;
CLetra37Network g_net;
CLetra37Trade   g_trade;
BrainParams     g_bp;
NetParams       g_np;
RiskConfig      g_rc;
datetime        g_lastBar = 0;
ENUM_TIMEFRAMES g_rung[6];
bool            g_netReady = false;

//+------------------------------------------------------------------+
//| Adaptive timeframe ladder (V60): six distinct rungs that climb   |
//| from the chart timeframe so the multi-TF read stays honest on    |
//| any chart. rung[2] is the canonical / execution rung (chart TF). |
//+------------------------------------------------------------------+
void ResolveLadder(ENUM_TIMEFRAMES &rung[],ENUM_TIMEFRAMES &tf1,ENUM_TIMEFRAMES &tf2)
{
   int csec=PeriodSeconds(Period());
   ENUM_TIMEFRAMES chart=Period();
   if(csec<3600)          { rung[0]=PERIOD_M1; rung[1]=PERIOD_M3; rung[2]=chart;     rung[3]=PERIOD_M15; rung[4]=PERIOD_H1;  rung[5]=PERIOD_H4; }
   else if(csec<14400)    { rung[0]=PERIOD_H1; rung[1]=PERIOD_H2; rung[2]=chart;     rung[3]=PERIOD_H8;  rung[4]=PERIOD_H12; rung[5]=PERIOD_D1; }
   else if(csec<86400)    { rung[0]=PERIOD_H4; rung[1]=PERIOD_H8; rung[2]=chart;     rung[3]=PERIOD_D1;  rung[4]=PERIOD_D1;  rung[5]=PERIOD_W1; }
   else                   { rung[0]=PERIOD_D1; rung[1]=PERIOD_W1; rung[2]=chart;     rung[3]=PERIOD_W1;  rung[4]=PERIOD_MN1; rung[5]=PERIOD_MN1; }
   tf1=rung[3];   // HTF belief engine 1 (M15-equivalent)
   tf2=rung[4];   // HTF belief engine 2 (H1-equivalent)
}

string TFStr(const ENUM_TIMEFRAMES tf){ return(StringSubstr(EnumToString(tf),7)); }

//+------------------------------------------------------------------+
int OnInit()
{
   ENUM_TIMEFRAMES tf1,tf2;
   ResolveLadder(g_rung,tf1,tf2);
   for(int i=0;i<6;i++) g_bp.rung[i]=g_rung[i];

   //--- engine params
   g_bp.pivotLen=InpPivotLen; g_bp.atrLen=InpAtrLen; g_bp.effLen=InpEffLen; g_bp.resetBars=InpResetBars;
   g_bp.impulseAtrMult=InpImpulseAtrMult; g_bp.effThresh=InpEffThresh; g_bp.dispThresh=InpDispThresh;
   g_bp.convMult=InpConvMult; g_bp.acceptBars=InpAcceptBars; g_bp.obLookback=InpObLookback; g_bp.obMaxBars=InpObMaxBars;
   g_bp.useStrictStructure=InpUseStrictStruct; g_bp.structLen=InpStructLen; g_bp.requireStruct=InpRequireStruct;
   g_bp.chochBufferATR=InpChochBufferATR;
   g_bp.inducLookback=InpInducLookback; g_bp.inducZoneWidth=InpInducZoneWidth;
   g_bp.requirePreConv=InpRequirePreConv; g_bp.requireInduction=InpRequireInduction;
   g_bp.liqRadius=InpLiqRadius; g_bp.liqAgDecay=InpLiqAgeDecay; g_bp.requireLiqSweep=InpRequireLiqSweep;
   g_bp.liqSweepLookback=InpLiqSweepLookback;
   g_bp.tf1=tf1; g_bp.tf2=tf2;
   g_bp.baseLockBars=InpBaseLockBars; g_bp.requireHTFAlign=InpRequireHTFAlign; g_bp.execThreshold=InpExecThreshold;
   g_bp.doeThreshold=InpDoeThreshold;
   g_bp.beliefSmooth=InpBeliefSmooth; g_bp.confDecayRate=InpConfDecayRate;
   g_bp.erfReadyResW=InpErfResW; g_bp.erfReadyResidW=InpErfResidW; g_bp.erfReadyConfW=InpErfConfW;
   g_bp.erfEntryThreshold=InpErfEntryThresh; g_bp.erfGateEnabled=InpErfGateEnabled;
   g_bp.enableReturnPhase=InpEnableReturnPhase;
   g_bp.barsM1=InpBarsM1; g_bp.barsM3=InpBarsM3; g_bp.barsM5=InpBarsM5;
   g_bp.barsM15=InpBarsM15; g_bp.barsH1=InpBarsH1; g_bp.barsH4=InpBarsH4;

   //--- network params
   g_np.wickFrac=InpNetWickFrac; g_np.lookback=InpNetLookback; g_np.authMin=InpNetAuthMin;
   g_np.nodeMax=InpNetNodeMax; g_np.dormantBars=InpNetDormantBars; g_np.historyBars=InpNetHistoryBars;
   g_np.baseTF=g_rung[2]; g_np.baseBars=InpBarsM5;

   //--- risk config
   g_rc.magic=(ulong)InpMagic; g_rc.deviationPoints=InpDeviation;
   g_rc.useFixedLot=InpUseFixedLot; g_rc.fixedLot=InpFixedLot; g_rc.riskPercent=InpRiskPercent; g_rc.maxLot=InpMaxLot;
   g_rc.slAtrMult=InpSlAtrMult; g_rc.tpAtrMult=InpTpAtrMult; g_rc.minRR=InpMinRR;
   g_rc.useStructuralStop=InpUseStructStop; g_rc.structBufferAtr=InpStructBufferAtr;
   g_rc.useBreakEven=InpUseBreakEven; g_rc.beTriggerR=InpBeTriggerR; g_rc.beLockAtr=InpBeLockAtr;
   g_rc.useTrailing=InpUseTrailing; g_rc.trailAtrMult=InpTrailAtrMult; g_rc.trailStartR=InpTrailStartR;
   g_rc.closeOnExitSignal=InpCloseOnExit;
   g_rc.maxSpreadPoints=InpMaxSpreadPoints; g_rc.dailyLossLimitPct=InpDailyLossLimit; g_rc.maxDrawdownPct=InpMaxDrawdown;
   g_rc.useSession=InpUseSession; g_rc.sessionStartHour=InpSessionStart; g_rc.sessionEndHour=InpSessionEnd;
   g_rc.oneTradePerBar=InpOneTradePerBar;

   g_trade.Init(_Symbol,g_rc);

   PrintFormat("Letra37 v2 on %s | ladder %s/%s/%s/%s/%s/%s | canon=%s | trading=%s",
      _Symbol,TFStr(g_rung[0]),TFStr(g_rung[1]),TFStr(g_rung[2]),TFStr(g_rung[3]),
      TFStr(g_rung[4]),TFStr(g_rung[5]),TFStr(g_rung[2]),(InpEnableTrading?"ON":"OFF"));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason){ Comment(""); }

//+------------------------------------------------------------------+
void OnTick()
{
   g_trade.UpdateGuards();

   //--- manage open position every tick (trailing / BE / exit) -----
   if(g_brain.ready && g_trade.HasPosition())
      ManageOpen();

   //--- only run the decision engine on a new CLOSED bar -----------
   datetime bt=iTime(_Symbol,g_rung[2],0);
   if(bt==g_lastBar) return;
   g_lastBar=bt;

   if(!g_brain.Recompute(_Symbol,g_bp))
   {
      if(InpVerbose) Print("Letra37: not enough history yet — waiting.");
      return;
   }
   g_netReady=(InpUseNetwork && g_net.Recompute(_Symbol,g_np));

   if(InpShowPanel) DrawPanel();

   if(InpVerbose)
      PrintFormat("Letra37 | %s | dir=%d phase=%s grade=%s prob=%.0f edge=%.1f life=%.0f(%s) net=%d%s%s%s%s",
                  TimeToString(g_brain.barTime),g_brain.outDir,g_brain.phase,g_brain.grade,
                  g_brain.finalProb,g_brain.netEdgeAdjusted,g_brain.lifeScore,g_brain.aliveVerdict,
                  (g_netReady?g_net.netBias:0),
                  (g_brain.longSignal?" >>>BELIEF-LONG":""),(g_brain.shortSignal?" >>>BELIEF-SHORT":""),
                  (g_brain.doeLong?" >>>DOE-LONG":""),(g_brain.doeShort?" >>>DOE-SHORT":""));

   if(!InpEnableTrading) return;
   if(g_trade.halted){ if(InpVerbose) Print("Letra37: halted — ",g_trade.haltReason); return; }

   int posDir=g_trade.PositionDir();

   //--- LETRA EXIT (authority) — its exit signal always closes -----
   bool aliveHold=(InpUseLifeMgmt && InpLifeAliveHold && g_brain.aliveVerdict=="ALIVE");
   if(posDir!=0 && InpCloseOnExit && g_brain.exitNow && !aliveHold)
   {
      g_trade.CloseAll();
      posDir=0;
   }

   //--- F72 abandon (subordinate assist) — protective early exit ---
   if(posDir!=0 && InpUseLifeMgmt && InpLifeDeadExit && g_brain.aliveVerdict=="DEAD")
   {
      g_trade.CloseAll();
      posDir=0;
      if(InpLifeFlip && g_brain.lifeTradeDir!=0)   // off by default: keeps entries Letra-only
         OpenDir(g_brain.lifeTradeDir);
   }

   //--- LETRA ENTRIES (authority) — belief arrows and/or DOE command --
   bool beliefOK=(InpEntryMode==ENTRY_BELIEF||InpEntryMode==ENTRY_BOTH);
   bool doeOK   =(InpEntryMode==ENTRY_DOE   ||InpEntryMode==ENTRY_BOTH);
   bool wantLong =(beliefOK&&g_brain.longSignal) ||(doeOK&&g_brain.doeLong);
   bool wantShort=(beliefOK&&g_brain.shortSignal)||(doeOK&&g_brain.doeShort);
   if(wantLong && NetAgrees(1))
   {
      if(posDir==-1 && InpReverseOnSignal){ g_trade.CloseAll(); posDir=0; }
      if(posDir==0) OpenDir(1);
   }
   else if(wantShort && NetAgrees(-1))
   {
      if(posDir==1 && InpReverseOnSignal){ g_trade.CloseAll(); posDir=0; }
      if(posDir==0) OpenDir(-1);
   }
}

//+------------------------------------------------------------------+
//| Per-tick management: trailing/BE/exit + F72 WEAKENING tighten.   |
//+------------------------------------------------------------------+
void ManageOpen()
{
   double atr=(g_brain.atr>0?g_brain.atr:CurrentAtr());
   bool aliveHold=(InpUseLifeMgmt && InpLifeAliveHold && g_brain.aliveVerdict=="ALIVE");
   g_trade.ManagePosition(atr,g_brain.exitNow && !aliveHold);
   if(InpUseLifeMgmt && InpLifeWeakTighten && g_brain.aliveVerdict=="WEAKENING")
      g_trade.TightenStop(atr,InpLifeTightenAtr);
}

//+------------------------------------------------------------------+
//| Network bias confluence (optional).                             |
//+------------------------------------------------------------------+
bool NetAgrees(const int dir)
{
   if(!InpUseNetwork || !InpNetBiasFilter || !g_netReady) return(true);
   return(g_net.netBias==0 || g_net.netBias==dir);
}

//+------------------------------------------------------------------+
//| Open a trade in dir, choosing the take-profit magnet.            |
//+------------------------------------------------------------------+
void OpenDir(const int dir)
{
   double tgt=g_brain.target;
   if(InpNetTarget && g_netReady && g_net.attractorPrice!=DBL_MAX)
   {
      double a=g_net.attractorPrice;
      if(dir==1 ? a>SymbolInfoDouble(_Symbol,SYMBOL_ASK) : a<SymbolInfoDouble(_Symbol,SYMBOL_BID))
         tgt=a;
   }
   g_trade.OpenTrade(dir,g_brain.atr,g_brain.outFlipTop,g_brain.outFlipBot,
                     tgt,g_brain.invalidation,g_brain.attractorPrice);
}

//+------------------------------------------------------------------+
double CurrentAtr()
{
   double buf[];
   int hAtr=iATR(_Symbol,g_rung[2],InpAtrLen);
   if(hAtr==INVALID_HANDLE) return(0);
   double v=0;
   if(CopyBuffer(hAtr,0,1,1,buf)>0) v=buf[0];
   IndicatorRelease(hAtr);
   return(v);
}

//+------------------------------------------------------------------+
void DrawPanel()
{
   string s="";
   s+="LETRA 37 v2  —  "+_Symbol+"  ["+TFStr(g_rung[2])+" canon]\n";
   s+="Bar: "+TimeToString(g_brain.barTime)+"\n";
   s+="Phase: "+g_brain.phase+"  (#"+IntegerToString(g_brain.phaseCode)+")\n";
   s+="Wave Dir: "+(g_brain.outDir==1?"BULLISH":g_brain.outDir==-1?"BEARISH":"NEUTRAL")+
      "   Stack: "+(g_brain.fractalStackDir==1?"BULL":g_brain.fractalStackDir==-1?"BEAR":"-")+
      " ("+DoubleToString(g_brain.fractalCtxScore,0)+")\n";
   s+="Directive: "+g_brain.directive+"   Grade: "+g_brain.grade+"  Prob "+DoubleToString(g_brain.finalProb,0)+"%\n";
   s+="Net Edge: "+DoubleToString(g_brain.netEdgeAdjusted,1)+"  (Buy "+DoubleToString(g_brain.buyProb,0)+
      "% / Sell "+DoubleToString(g_brain.sellProb,0)+"%)\n";
   s+="Compression: "+DoubleToString(g_brain.compIdx,0)+"%   Recursion: "+IntegerToString(g_brain.recCount)+
      "   Dominance: "+DoubleToString(g_brain.domTransfer,0)+"%\n";
   s+="── F72 CURVE LIFE (advisory · subordinate) ──\n";
   s+="Trade Alive?  "+g_brain.aliveVerdict+"   (life "+DoubleToString(g_brain.lifeScore,0)+")\n";
   s+="Force: "+g_brain.cpState+"   Narrative: "+g_brain.narrState+"\n";
   s+="Chain: "+g_brain.chainScope+"   HTF Threat: "+g_brain.htfThreat+"\n";
   s+="Curve trade dir: "+(g_brain.lifeTradeDir==1?"LONG":g_brain.lifeTradeDir==-1?"SHORT":"wait")+"\n";
   if(InpUseNetwork && g_netReady)
   {
      s+="── INVISIBLE NETWORK (advisory) ──\n";
      s+="netBias: "+(g_net.netBias==1?"BULL":g_net.netBias==-1?"BEAR":"-")+
         "   Pressure: "+DoubleToString(g_net.pressure,0)+"  ("+IntegerToString(g_net.liveNodes)+" live)\n";
      s+="Attractor: "+(g_net.attractorPrice==DBL_MAX?"-":DoubleToString(g_net.attractorPrice,_Digits))+"\n";
      s+="FEZ: "+(g_net.fezLo==DBL_MAX?"-":DoubleToString(g_net.fezLo,_Digits))+" .. "+
         (g_net.fezHi==DBL_MAX?"-":DoubleToString(g_net.fezHi,_Digits))+"\n";
   }
   s+="── LETRA EXECUTION (AUTHORITY) ──\n";
   s+="Belief arrow: "+(g_brain.longSignal?"LONG":g_brain.shortSignal?"SHORT":"—")+
      "   DOE command: "+(g_brain.doeLong?"LONG":g_brain.doeShort?"SHORT":"—")+"\n";
   s+="Exit: "+(g_brain.exitNow?"YES":"-")+"   Mode: "+
      (InpEntryMode==ENTRY_BELIEF?"belief":InpEntryMode==ENTRY_DOE?"DOE":"both")+"\n";
   s+="Position: "+(g_trade.PositionDir()==1?"LONG":g_trade.PositionDir()==-1?"SHORT":"flat")+
      (g_trade.halted?("  [HALTED: "+g_trade.haltReason+"]"):"")+"\n";
   Comment(s);
}
//+------------------------------------------------------------------+
