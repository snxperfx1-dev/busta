//+------------------------------------------------------------------+
//|                                                  Letra37_EA.mq5   |
//|       Autonomous MT5 port of the "Letra 37" Pine v6 engine.      |
//|                                                                  |
//|  A complete reimplementation of the multi-timeframe physics /    |
//|  structure / wave-lifecycle / belief / Bayesian / ERF decision   |
//|  stack, wrapped in an institutional execution & risk layer.      |
//|                                                                  |
//|  INSTALL:                                                        |
//|    - Copy  MT5/Include/Letra37   -> <Terminal>/MQL5/Include/      |
//|    - Copy  MT5/Experts/Letra37   -> <Terminal>/MQL5/Experts/      |
//|    - Compile Letra37_EA.mq5 in MetaEditor, attach to any M5 chart.|
//|                                                                  |
//|  The engine evaluates on each CLOSED M5 bar (execution TF).      |
//+------------------------------------------------------------------+
#property copyright "Letra 37 MT5 Port"
#property version   "1.00"
#property strict

#include <Letra37/Letra37_Brain.mqh>
#include <Letra37/Letra37_Trade.mqh>

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
input bool    InpEnableReturnPhase= true;   // Enable Demand/Supply Return detector (required for entries)

input string  GRPH           = "===== History Depth (bars per TF) ====="; // ---
input int     InpBarsM1           = 4000;   // M1 history bars
input int     InpBarsM3           = 3000;   // M3 history bars
input int     InpBarsM5           = 3000;   // M5 history bars
input int     InpBarsM15          = 2500;   // M15 history bars
input int     InpBarsH1           = 1500;   // H1 history bars
input int     InpBarsH4           = 1000;   // H4 history bars

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
input bool    InpOneTradePerBar   = true;   // Max one entry per M5 bar

input string  GRPD           = "===== Diagnostics ====="; // ---
input bool    InpVerbose          = true;   // Print decisions to log
input bool    InpShowPanel        = true;   // On-chart status panel

//====================== GLOBALS ====================================
CLetra37Brain  g_brain;
CLetra37Trade  g_trade;
BrainParams    g_bp;
RiskConfig     g_rc;
datetime       g_lastBar = 0;
string         g_panel   = "Letra37_Panel";

//+------------------------------------------------------------------+
ENUM_TIMEFRAMES TF1(){ return(PERIOD_M15); }   // Timeframe 1 (HTF bias)
ENUM_TIMEFRAMES TF2(){ return(PERIOD_H1);  }   // Timeframe 2 (HTF bias)

//+------------------------------------------------------------------+
int OnInit()
{
   if(Period()!=PERIOD_M5)
      Print("Letra37: WARNING — engine is designed for the M5 execution timeframe. Attach to an M5 chart for intended behaviour.");

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
   g_bp.tf1=TF1(); g_bp.tf2=TF2();
   g_bp.baseLockBars=InpBaseLockBars; g_bp.requireHTFAlign=InpRequireHTFAlign; g_bp.execThreshold=InpExecThreshold;
   g_bp.beliefSmooth=InpBeliefSmooth; g_bp.confDecayRate=InpConfDecayRate;
   g_bp.erfReadyResW=InpErfResW; g_bp.erfReadyResidW=InpErfResidW; g_bp.erfReadyConfW=InpErfConfW;
   g_bp.erfEntryThreshold=InpErfEntryThresh; g_bp.erfGateEnabled=InpErfGateEnabled;
   g_bp.enableReturnPhase=InpEnableReturnPhase;
   g_bp.barsM1=InpBarsM1; g_bp.barsM3=InpBarsM3; g_bp.barsM5=InpBarsM5;
   g_bp.barsM15=InpBarsM15; g_bp.barsH1=InpBarsH1; g_bp.barsH4=InpBarsH4;

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

   Print("Letra37 EA initialised on ",_Symbol," | execution TF=M5 | HTF bias=M15/H1 | trading=",
         (InpEnableTrading?"ON":"OFF"));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectDelete(0,g_panel);
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   g_trade.UpdateGuards();

   //--- manage open position every tick (trailing / BE / exit) -----
   if(g_brain.ready && g_trade.HasPosition())
      g_trade.ManagePosition(g_brain.atr>0?g_brain.atr:CurrentAtr(),g_brain.exitNow);

   //--- only run the decision engine on a new CLOSED M5 bar --------
   datetime bt=iTime(_Symbol,PERIOD_M5,0);
   if(bt==g_lastBar) return;
   g_lastBar=bt;

   if(!g_brain.Recompute(_Symbol,g_bp))
   {
      if(InpVerbose) Print("Letra37: not enough history yet — waiting.");
      return;
   }

   if(InpShowPanel) DrawPanel();

   if(InpVerbose)
      PrintFormat("Letra37 | %s | dir=%d phase=%s grade=%s prob=%.0f%% edge=%.1f buy=%.0f sell=%.0f ERF=%.0f %s%s",
                  TimeToString(g_brain.barTime),g_brain.outDir,g_brain.phase,g_brain.grade,
                  g_brain.finalProb,g_brain.netEdgeAdjusted,g_brain.buyProb,g_brain.sellProb,
                  g_brain.erfReadinessOut,
                  (g_brain.longSignal?" >>> LONG SIGNAL":""),(g_brain.shortSignal?" >>> SHORT SIGNAL":""));

   if(!InpEnableTrading) return;
   if(g_trade.halted)
   {
      if(InpVerbose) Print("Letra37: trading halted — ",g_trade.haltReason);
      return;
   }

   int posDir=g_trade.PositionDir();

   //--- exit handling ---------------------------------------------
   if(posDir!=0 && InpCloseOnExit && g_brain.exitNow)
   {
      g_trade.CloseAll();
      posDir=0;
   }

   //--- entry / reversal ------------------------------------------
   if(g_brain.longSignal)
   {
      if(posDir==-1 && InpReverseOnSignal){ g_trade.CloseAll(); posDir=0; }
      if(posDir==0)
         g_trade.OpenTrade(1,g_brain.atr,g_brain.outFlipTop,g_brain.outFlipBot,
                           g_brain.target,g_brain.invalidation,g_brain.attractorPrice);
   }
   else if(g_brain.shortSignal)
   {
      if(posDir==1 && InpReverseOnSignal){ g_trade.CloseAll(); posDir=0; }
      if(posDir==0)
         g_trade.OpenTrade(-1,g_brain.atr,g_brain.outFlipTop,g_brain.outFlipBot,
                           g_brain.target,g_brain.invalidation,g_brain.attractorPrice);
   }
}

//+------------------------------------------------------------------+
double CurrentAtr()
{
   double buf[];
   int hAtr=iATR(_Symbol,PERIOD_M5,InpAtrLen);
   if(hAtr==INVALID_HANDLE) return(0);
   if(CopyBuffer(hAtr,0,1,1,buf)>0){ IndicatorRelease(hAtr); return(buf[0]); }
   IndicatorRelease(hAtr);
   return(0);
}

//+------------------------------------------------------------------+
void DrawPanel()
{
   string s="";
   s+="LETRA 37  —  "+_Symbol+"  (M5 engine)\n";
   s+="Bar: "+TimeToString(g_brain.barTime)+"\n";
   s+="Phase: "+g_brain.phase+"\n";
   s+="Wave Dir: "+(g_brain.outDir==1?"BULLISH":g_brain.outDir==-1?"BEARISH":"NEUTRAL")+"\n";
   s+="Directive: "+g_brain.directive+"\n";
   s+="Grade: "+g_brain.grade+"   Prob: "+DoubleToString(g_brain.finalProb,0)+"%\n";
   s+="Net Edge: "+DoubleToString(g_brain.netEdgeAdjusted,1)+"   (Buy "+DoubleToString(g_brain.buyProb,0)+
      "% / Sell "+DoubleToString(g_brain.sellProb,0)+"%)\n";
   s+="HTF Align: "+(g_brain.htfAlign==1?"BULL":g_brain.htfAlign==-1?"BEAR":"-")+
      "   Stack: "+(g_brain.fractalStackDir==1?"BULL":g_brain.fractalStackDir==-1?"BEAR":"-")+
      " ("+DoubleToString(g_brain.fractalCtxScore,0)+")\n";
   s+="LiqHeat: "+DoubleToString(g_brain.liqHeatOut,0)+"   ERF Ready: "+DoubleToString(g_brain.erfReadinessOut,0)+"\n";
   s+="DemandReturn Belief: "+DoubleToString(g_brain.demandReturnBeliefOut,0)+"\n";
   s+="Signal: "+(g_brain.longSignal?"LONG":g_brain.shortSignal?"SHORT":g_brain.exitNow?"EXIT":"—")+"\n";
   s+="Position: "+(g_trade.PositionDir()==1?"LONG":g_trade.PositionDir()==-1?"SHORT":"flat")+
      (g_trade.halted?("  [HALTED: "+g_trade.haltReason+"]"):"")+"\n";
   Comment(s);
}
//+------------------------------------------------------------------+
