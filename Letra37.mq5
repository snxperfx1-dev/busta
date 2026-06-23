//+------------------------------------------------------------------+
//|                                                      Letra37.mq5  |
//|     Full MQL5 port of the "Letra 37" TradingView Pine v6 study    |
//|                                                                  |
//|  This is a faithful, no-shortcuts port of the multi-engine wave  |
//|  intelligence / market-structure indicator.  Every engine of the |
//|  original (Physics, HTF Belief, fixed-TF Structure Engine, ERF,  |
//|  Liquidity Heatmap, Geometry, Wave Intelligence, Bayesian model, |
//|  Entry Signals, FU Order Blocks, FU Wick Authority, FRZ, and the |
//|  V72 Decision Architecture + MOS narrative) is reimplemented in  |
//|  MQL5.  request.security() multi-timeframe calls are replicated  |
//|  by running each engine over CopyRates() data for the fixed      |
//|  timeframes ("1","3","5","15","60","240","D","W") and mapping    |
//|  the last *closed* HTF bar onto every chart bar (lookahead off).  |
//+------------------------------------------------------------------+
#property copyright "Ported from Pine v6 'Letra 37'"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

//--- plots: entry-signal arrows (computed in the engine, drawn on chart)
#property indicator_label1  "Long Entry"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrAqua
#property indicator_width1  2

#property indicator_label2  "Short Entry"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  2

//--- entry-signal plot buffers ---
double BufLong[];
double BufShort[];

#include "Letra37_Engine.mqh"
//==================================================================
// OnInit
//==================================================================
int OnInit()
{
   SetIndexBuffer(0,BufLong,INDICATOR_DATA);
   SetIndexBuffer(1,BufShort,INDICATOR_DATA);
   PlotIndexSetInteger(0,PLOT_ARROW,233);
   PlotIndexSetInteger(1,PLOT_ARROW,234);
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(1,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetInteger(0,PLOT_ARROW_SHIFT,10);
   PlotIndexSetInteger(1,PLOT_ARROW_SHIFT,-10);
   ArraySetAsSeries(BufLong,false);
   ArraySetAsSeries(BufShort,false);
   showOriginShort=(originMode==OM_SHORT||originMode==OM_BOTH);
   showOriginLong =(originMode==OM_LONG ||originMode==OM_BOTH);
   IndicatorSetString(INDICATOR_SHORTNAME,"Letra 37 (MQL5 port)");
   ResetState();
   g_lastProcessed=-1;
   return(INIT_SUCCEEDED);
}

//==================================================================
// OnCalculate
//==================================================================
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],
                const double &close[],const long &tick_volume[],const long &volume[],const int &spread[])
{
   ArraySetAsSeries(time,false); ArraySetAsSeries(open,false); ArraySetAsSeries(high,false);
   ArraySetAsSeries(low,false); ArraySetAsSeries(close,false); ArraySetAsSeries(tick_volume,false);

   int warmup=MathMax(2*structLen,2*pivotLen)+effLen+10;
   if(rates_total<warmup+5) return(rates_total);

   //--- volume to double array ---
   static double volD[]; ArrayResize(volD,rates_total);
   for(int q=0;q<rates_total;q++) volD[q]=(double)tick_volume[q];

   int target=rates_total-2;             // last fully closed bar
   if(prev_calculated<=0){ ResetState(); ArrayInitialize(BufLong,EMPTY_VALUE); ArrayInitialize(BufShort,EMPTY_VALUE); g_lastProcessed=MathMax(warmup,rates_total-4000)-1; }
   BufLong[rates_total-1]=EMPTY_VALUE; BufShort[rates_total-1]=EMPTY_VALUE;

   if(target>g_lastProcessed){
      BuildHTFEngines();
      for(int i=g_lastProcessed+1;i<=target;i++){
         ProcessBar(i,open,high,low,close,time,volD,rates_total,(i==target));
         BufLong[i]=gBarLong?gBarLongPx:EMPTY_VALUE;
         BufShort[i]=gBarShort?gBarShortPx:EMPTY_VALUE;
      }
      g_lastProcessed=target;
      RenderAll(rates_total,time,high,low);
   }
   return(rates_total);
}


//==================================================================
// RENDERING
//==================================================================
int    g_fontPx;
color ScoreCol(const double v){ return(v>=85?(color)0x88FF00:v>=70?clrLime:v>=40?clrYellow:clrRed); }
string DirWord(const int d){ return(d==1?"Bull":d==-1?"Bear":"Neut"); }

void RectObj(const string nm,const datetime t1,const double p1,const datetime t2,const double p2,const color clr,const bool fill,const int width)
{
   if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_RECTANGLE,0,t1,p1,t2,p2);
   ObjectSetInteger(0,nm,OBJPROP_TIME,0,t1); ObjectSetDouble(0,nm,OBJPROP_PRICE,0,p1);
   ObjectSetInteger(0,nm,OBJPROP_TIME,1,t2); ObjectSetDouble(0,nm,OBJPROP_PRICE,1,p2);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,clr); ObjectSetInteger(0,nm,OBJPROP_FILL,fill&&zoneFillOn);
   ObjectSetInteger(0,nm,OBJPROP_WIDTH,width); ObjectSetInteger(0,nm,OBJPROP_BACK,true);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
}
void TextObj(const string nm,const datetime t,const double p,const string txt,const color clr,const int fsz)
{
   if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_TEXT,0,t,p);
   ObjectSetInteger(0,nm,OBJPROP_TIME,0,t); ObjectSetDouble(0,nm,OBJPROP_PRICE,0,p);
   ObjectSetString(0,nm,OBJPROP_TEXT,txt); ObjectSetInteger(0,nm,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,fsz); ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
   ObjectSetString(0,nm,OBJPROP_FONT,"Consolas");
}
void HLineSeg(const string nm,const datetime t1,const datetime t2,const double p,const color clr,const int style)
{
   if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_TREND,0,t1,p,t2,p);
   ObjectSetInteger(0,nm,OBJPROP_TIME,0,t1); ObjectSetDouble(0,nm,OBJPROP_PRICE,0,p);
   ObjectSetInteger(0,nm,OBJPROP_TIME,1,t2); ObjectSetDouble(0,nm,OBJPROP_PRICE,1,p);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,clr); ObjectSetInteger(0,nm,OBJPROP_STYLE,style);
   ObjectSetInteger(0,nm,OBJPROP_RAY_RIGHT,false); ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
}
//--- stacked corner label panel ---
int g_lblSeq=0;
void Lbl(const ENUM_BASE_CORNER corner,const int x,const int y,const string txt,const color clr,const int fsz)
{
   string nm="L37_LBL_"+IntegerToString(g_lblSeq++);
   if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,nm,OBJPROP_CORNER,corner);
   ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,nm,OBJPROP_ANCHOR,(corner==CORNER_RIGHT_UPPER||corner==CORNER_RIGHT_LOWER)?ANCHOR_RIGHT_UPPER:ANCHOR_LEFT_UPPER);
   ObjectSetString(0,nm,OBJPROP_TEXT,txt); ObjectSetInteger(0,nm,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,fsz); ObjectSetString(0,nm,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
}

void RenderAll(const int rates_total,const datetime &time[],const double &high[],const double &low[])
{
   ObjectsDeleteAll(0,"L37_");
   g_lblSeq=0;
   g_fontPx=(dashTextSize==TS_TINY?7:dashTextSize==TS_NORMAL?10:8);
   datetime tNow=time[rates_total-1];
   int psec=PeriodSeconds(_Period);
   datetime rT=tNow+(datetime)(40*psec);
   double atr=cur_atr;

   //--- PHASE REGION LABEL ---
   if(showNarrative && cur_currentDisplayPhase!="" && cur_dirM5!=0){
      double y=cur_dirM5==1?high[rates_total-1]+atr*1.2:low[rates_total-1]-atr*1.2;
      color rc=StringFind(cur_currentDisplayPhase,"Liquidation Wave")>=0?clrOrange:
               StringFind(cur_currentDisplayPhase,"Induction")>=0?clrYellow:
               StringFind(cur_currentDisplayPhase,"Pre-Convexity")>=0?(color)0xC084FC:
               StringFind(cur_currentDisplayPhase,"Liquidity")>=0?clrOrange:
               StringFind(cur_currentDisplayPhase,"Absorption")>=0?clrAqua:
               (StringFind(cur_currentDisplayPhase,"New High")>=0||StringFind(cur_currentDisplayPhase,"New Low")>=0)?(color)0x88FF00:
               StringFind(cur_currentDisplayPhase,"Retracement")>=0?clrSilver:
               StringFind(cur_currentDisplayPhase,"Return")>=0?clrTeal:
               StringFind(cur_currentDisplayPhase,"Expansion")>=0?clrLime:clrGray;
      TextObj("L37_REGION",tNow,y,(DirWord(cur_dirM5)=="Bull"?"Bullish":DirWord(cur_dirM5)=="Bear"?"Bearish":"Neutral")+" - "+cur_currentDisplayPhase,rc,g_fontPx+1);
   }

   //--- ENTRY ZONE (primary attractor) ---
   if(showEntryZone && cur_dirM5!=0 && !naf(cur_eaePrimaryPrice)){
      double mid=cur_eaePrimaryPrice, hi=mid+atr*entryZoneWidthA, lo=mid-atr*entryZoneWidthA;
      color ec=cur_dirM5==1?(color)0x00FFCC:(color)0x4422FF;
      RectObj("L37_EZ",tNow-(datetime)(2*psec),hi,rT,lo,ec,true,1);
      TextObj("L37_EZL",rT,mid,"ENTRY ZONE "+R0(cur_eaePrimaryScore)+"% "+cur_eaePrimaryLabel,ec,g_fontPx);
   }

   //--- FU WICK AUTHORITY band + magnet ---
   if(showFUWick && g_fuw_valid && !naf(g_fuw_tip)){
      double bH=(naf(g_fuw_mid38)||naf(g_fuw_mid62))?NA:fmax2(g_fuw_mid38,g_fuw_mid62);
      double bL=(naf(g_fuw_mid38)||naf(g_fuw_mid62))?NA:fmin2(g_fuw_mid38,g_fuw_mid62);
      datetime fT=(g_fuw_bar>=0&&g_fuw_bar<rates_total)?time[g_fuw_bar]:tNow;
      if(!naf(bH)){ RectObj("L37_FUWB",fT,bH,rT,bL,clrYellow,true,1); TextObj("L37_FUWBL",rT,(bH+bL)/2.0,"INDUCTION BAND",clrYellow,g_fontPx); }
      TextObj("L37_FUWT",fT,g_fuw_tip,"FU",g_fuw_dir==1?(color)0x00FFAA:(color)0x0066FF,g_fontPx);
      if(g_fuw_valid && !naf(g_fuw_leftPool)) TextObj("L37_FUWM",rT,g_fuw_leftPool,"MAGNET",(color)0xFF00FF,g_fontPx);
   }

   //--- P4 ORIGIN BOX ---
   if(showP4Box && !naf(g_point4OriginHigh) && !naf(g_point4OriginLow) && g_point4OriginBar>=0 && g_point4OriginBar<rates_total){
      RectObj("L37_P4",time[g_point4OriginBar],g_point4OriginHigh,rT,g_point4OriginLow,clrOrange,true,1);
   }

   //--- FRZ ZONES ---
   if(showFRZ){
      for(int q=0;q<ArraySize(g_frz_top);q++){
         if(g_frz_bar[q]<0||g_frz_bar[q]>=rates_total) continue;
         color zc=g_frz_dir[q]==1?clrTeal:clrRed; if(g_frz_score[q]>=76) zc=g_frz_dir[q]==1?(color)0x00FFCC:(color)0x4422FF;
         if(g_frz_status[q]=="Partial") zc=clrYellow; else if(g_frz_status[q]=="Mitigated") zc=clrGray;
         string nm="L37_FRZ"+IntegerToString(g_frz_idx[q]);
         datetime r2=tNow+(datetime)(10*psec);
         RectObj(nm,time[g_frz_bar[q]],g_frz_top[q],r2,g_frz_bot[q],zc,true,g_frz_score[q]>=76?2:1);
         if(showFRZ_Labels){
            double yy=g_frz_dir[q]==1?g_frz_bot[q]-atr*0.4:g_frz_top[q]+atr*0.4;
            TextObj(nm+"L",time[g_frz_bar[q]],yy,"FRZ#"+IntegerToString(g_frz_idx[q])+" "+IntegerToString(g_frz_score[q])+"% "+g_frz_tier[q]+" ["+g_frz_status[q]+"]",zc,g_fontPx);
         }
      }
   }

   //--- FU BLOCKS ---
   if(showFUBlocks){
      for(int q=0;q<ArraySize(g_fu_top);q++){
         if(g_fu_birthBar[q]<0||g_fu_birthBar[q]>=rates_total) continue;
         color fc=g_fu_dir[q]==1?(color)0x00FFAA:(color)0x0066FF;
         datetime r2=time[g_fu_birthBar[q]]+(datetime)(fuMaxBarsActive*psec);
         RectObj("L37_FU"+IntegerToString(q),time[g_fu_birthBar[q]],g_fu_top[q],r2,g_fu_bot[q],fc,true,1);
      }
   }

   //--- TARGET / DESTINATION line ---
   if(showV72Destination && !naf(cur_tplMainTarget)){
      HLineSeg("L37_TGT",tNow-(datetime)(20*psec),rT,cur_tplMainTarget,(color)0xFFD700,STYLE_DASH);
      TextObj("L37_TGTL",rT,cur_tplMainTarget,"TARGET "+cur_tplWinnerClass+" "+R0(cur_tplConfidence)+"% ("+cur_tplSource+")",(color)0xFFD700,g_fontPx);
   }

   if(showTable) DrawDashboards();
}

//==================================================================
// DASHBOARD PANELS (stacked corner labels)
//==================================================================
void DrawDashboards()
{
   int fs=g_fontPx, dy=fs+5, x=6, y=16;
   color hdr=clrWhite, dim=clrSilver;

   //--- Dashboard A : Command Center (top-left) ---
   if(showDA_Header){ Lbl(CORNER_LEFT_UPPER,x,y,"== LETRA 37 - COMMAND CENTER ==",hdr,fs); y+=dy; }
   if(showDA_Directive){ Lbl(CORNER_LEFT_UPPER,x,y,"Directive : "+cur_directiveStr,cur_directiveCol,fs); y+=dy;
      Lbl(CORNER_LEFT_UPPER,x,y,"Live      : "+cur_liveDirective+"  (edge "+R0(cur_netEdgeAdjusted)+")",dim,fs); y+=dy; }
   if(showDA_WaveCtx){ Lbl(CORNER_LEFT_UPPER,x,y,"Phase     : "+cur_currentDisplayPhase,ScoreCol(cur_phaseConfidence),fs); y+=dy;
      Lbl(CORNER_LEFT_UPPER,x,y,"Wave M5   : "+f_waveDirLabel(cur_dirM5)+"  Conf "+R0(cur_phaseConfidence)+"%  Integ "+R0(cur_phaseIntegrity)+"%  Prog "+PCTs(cur_phaseProgress),dim,fs); y+=dy;
      Lbl(CORNER_LEFT_UPPER,x,y,"Grade "+cur_grade+"  Cont "+R0(cur_contProb)+"%  Bayes "+R0(cur_finalProb)+"%",cur_gradeCol,fs); y+=dy; }
   if(showDA_MarketState){ Lbl(CORNER_LEFT_UPPER,x,y,"Struct "+DirWord(cur_structBias)+"  HTF "+DirWord(cur_htfAlign)+"  Liq "+cur_liqZone+" ("+R0(cur_liqHeat)+")  Vol "+cur_volRegime,dim,fs); y+=dy; }
   if(showDA_HTFStack){ Lbl(CORNER_LEFT_UPPER,x,y,"Stack M1:"+DirWord(cur_dirM1)+" M3:"+DirWord(cur_dirM3)+" M5:"+DirWord(cur_dirM5)+" M15:"+DirWord(cur_dirM15)+" H1:"+DirWord(cur_dirH1)+" H4:"+DirWord(cur_dirH4),dim,fs); y+=dy;
      Lbl(CORNER_LEFT_UPPER,x,y,"Fractal "+R0(cur_fractalStackScore)+"%  Ctx "+R0(cur_fractalCtxScore)+"%  Dominant "+cur_dominantWaveLevel,dim,fs); y+=dy; }
   if(showDA_Physics){ Lbl(CORNER_LEFT_UPPER,x,y,"Eff "+DoubleToString(cur_efficiency,2)+"  Disp "+DoubleToString(cur_displacement,2)+"  PhysCons "+R0(cur_physicsConsensus)+"%",dim,fs); y+=dy; }

   //--- Dashboard B : Beliefs ---
   if(showDB_Header){ y+=4; Lbl(CORNER_LEFT_UPPER,x,y,"-- BELIEF DISTRIBUTION --",hdr,fs); y+=dy; }
   if(showDB_Beliefs){
      Lbl(CORNER_LEFT_UPPER,x,y,"Expansion  "+R0(cur_bExp)+"%   Convexity "+R0(cur_bConv)+"%",ScoreCol(cur_bExp),fs); y+=dy;
      Lbl(CORNER_LEFT_UPPER,x,y,"Creation   "+R0(cur_bCreat)+"%   Absorption "+R0(cur_bAbs)+"%",ScoreCol(cur_bCreat),fs); y+=dy;
      Lbl(CORNER_LEFT_UPPER,x,y,"Retrace    "+R0(cur_bRetr)+"%   DemandRet  "+R0(cur_bDR)+"%",ScoreCol(cur_bDR),fs); y+=dy; }
   if(showDB_PhysObs){ Lbl(CORNER_LEFT_UPPER,x,y,"Obs Exp "+R0(cur_obsExp)+" Dec "+R0(cur_obsDecay)+" Curv "+R0(cur_obsCurv)+" Abs "+R0(cur_obsAbs)+" Liq "+R0(cur_obsLiq),dim,fs); y+=dy; }
   if(showDB_Geometry){ Lbl(CORNER_LEFT_UPPER,x,y,"Geo "+cur_geoCapNarr+"  Cap "+R0(cur_geoCapScore)+"%  "+cur_cycleCapacity,dim,fs); y+=dy; }

   //--- Dashboard C : Intelligence ---
   if(showDC_Header){ y+=4; Lbl(CORNER_LEFT_UPPER,x,y,"-- INTELLIGENCE ENGINE --",hdr,fs); y+=dy; }
   if(showDC_Hypothesis){ Lbl(CORNER_LEFT_UPPER,x,y,"Hypothesis "+cur_primaryHyp+"  ("+R0(cur_primaryHypConf)+"%)",ScoreCol(cur_primaryHypConf),fs); y+=dy; }
   if(showDC_Prediction){ Lbl(CORNER_LEFT_UPPER,x,y,"Next "+cur_expectedNextPhase+"  ("+R0(cur_expectedNextProb)+"%)",dim,fs); y+=dy; }
   if(showDC_Validation){ Lbl(CORNER_LEFT_UPPER,x,y,"PredRel "+R0(cur_predReliability)+"%  Acc10 "+R0(cur_predAcc10)+"%  Dev "+R0(cur_waveDeviation),dim,fs); y+=dy; }
   if(showDC_AdapConf){ Lbl(CORNER_LEFT_UPPER,x,y,"ModelConf "+R0(cur_modelConfidence)+"%  M1Warn "+cur_m1Warning,dim,fs); y+=dy; }
   if(showDC_Quality){ Lbl(CORNER_LEFT_UPPER,x,y,"SetupQ "+R0(cur_dieEntryScore)+"%  "+cur_dieFuContrib,ScoreCol(cur_dieEntryScore),fs); y+=dy; }
   if(showDC_DirProb){ Lbl(CORNER_LEFT_UPPER,x,y,"Buy "+R0(cur_buyProb)+"%  Sell "+R0(cur_sellProb)+"%  Exp "+R0(cur_expansionProbability)+"%  Rev "+R0(cur_reversalProbability)+"%",dim,fs); y+=dy; }

   //--- Dashboard P3 : Recursive Wave Intel ---
   if(showDP3_Header){ y+=4; Lbl(CORNER_LEFT_UPPER,x,y,"-- RECURSIVE WAVE INTEL --",hdr,fs); y+=dy; }
   if(showDP3_Dominance){ Lbl(CORNER_LEFT_UPPER,x,y,"L0 "+cur_l0domPhase+"("+R0(cur_l0dom)+") L1 "+cur_l1domPhase+"("+R0(cur_l1dom)+") L2 "+cur_l2domPhase+"("+R0(cur_l2dom)+")",dim,fs); y+=dy; }
   if(showDP3_Fusion){ Lbl(CORNER_LEFT_UPPER,x,y,"Fusion "+cur_fusionInterp+"  ("+R0(cur_fusionConfidence)+"%)",dim,fs); y+=dy; }
   if(showDP3_Cycles){ Lbl(CORNER_LEFT_UPPER,x,y,"Cycle "+cur_activeCyclePhase+"  Depth "+IntegerToString(cur_waveDepth),dim,fs); y+=dy; }

   //--- Dashboard FU ---
   if(showDFU_Panel && showDFU_Header){ y+=4; Lbl(CORNER_LEFT_UPPER,x,y,"-- FU ORDER BLOCKS --",hdr,fs); y+=dy;
      Lbl(CORNER_LEFT_UPPER,x,y,"BullFU "+(cur_anyBullFU?"Y":"N")+"  BearFU "+(cur_anyBearFU?"Y":"N")+"  Recurse "+R0(cur_fuRecursiveAlign)+"%",dim,fs); y+=dy;
      if(!naf(cur_fuWinTarget)) Lbl(CORNER_LEFT_UPPER,x,y,"Magnet "+cur_fuWinSrc+" @ "+PXs(cur_fuWinTarget),dim,fs); y+=dy; }

   //--- ERF ---
   if(showERF_Dashboard){ y+=4; Lbl(CORNER_LEFT_UPPER,x,y,"-- ENERGY RESOLUTION --",hdr,fs); y+=dy;
      Lbl(CORNER_LEFT_UPPER,x,y,cur_edeCleaning+"  Diss "+R0(cur_edeDissProg)+"%  "+cur_reResolution,dim,fs); y+=dy;
      Lbl(CORNER_LEFT_UPPER,x,y,"Energy "+cur_eaeEnergyState+"  Readiness "+R0(cur_erfTradeReadiness)+"%  Gate "+(cur_erfEntryGate?"OPEN":"SHUT"),ScoreCol(cur_erfTradeReadiness),fs); y+=dy; }

   //--- V72 COMMAND CENTER (right side) ---
   if(in_showV72Command){
      int yr=18, xr=8, dyr=fs+5;
      ENUM_BASE_CORNER cor=(commandPanelYOffset==PP_TOP?CORNER_RIGHT_UPPER:CORNER_RIGHT_LOWER);
      if(cor==CORNER_RIGHT_LOWER) yr=18+dyr*16;
      color ac=cur_doeAction=="Long"?(color)0x88FF00:cur_doeAction=="Short"?clrRed:cur_doeAction=="No Trade"?clrMaroon:clrGray;
      color gc=cur_tqeGrade=="A+"?(color)0x00FFCC:cur_tqeGrade=="A"?clrLime:cur_tqeGrade=="B"?clrYellow:cur_tqeGrade=="C"?clrOrange:clrRed;
      Lbl(cor,xr,yr,"=== V72 COMMAND ===",clrWhite,fs); yr-=dyr;
      Lbl(cor,xr,yr,"ACTION "+cur_doeAction+"  ("+R0(cur_doeConfidence)+"%)",ac,fs); yr-=dyr;
      Lbl(cor,xr,yr,"Bias "+cur_doeBias+"  Type "+cur_doeTradeType,clrSilver,fs); yr-=dyr;
      Lbl(cor,xr,yr,"Grade "+cur_tqeGrade+" ("+R0(cur_tqeRaw)+")  Risk "+cur_tqeRisk,gc,fs); yr-=dyr;
      Lbl(cor,xr,yr,"Opportunity "+cur_oppState+"  "+R0(cur_oppProgress)+"%",ScoreCol(cur_oppProgress),fs); yr-=dyr;
      Lbl(cor,xr,yr,"Narrative "+cur_neNarrative+" ("+R0(cur_neStrength)+"%)",clrSilver,fs); yr-=dyr;
      Lbl(cor,xr,yr,"Rotation "+cur_rotState+"  "+R0(cur_rotTransfer)+"%",clrSilver,fs); yr-=dyr;
      Lbl(cor,xr,yr,"MCE Align "+R0(cur_mceAlign)+"%  HTF "+R0(cur_mceHtfAlign)+"%  Exec "+R0(cur_mceExecAlign)+"%",clrSilver,fs); yr-=dyr;
      Lbl(cor,xr,yr,"HTF: "+cur_mceHtfSummary,clrSilver,fs); yr-=dyr;
      Lbl(cor,xr,yr,cur_cmdNarrative,clrAqua,fs); yr-=dyr;
      Lbl(cor,xr,yr,"Entry "+PXs(cur_doeEntryMid)+" ("+cur_doeTrigger+")",clrSilver,fs); yr-=dyr;
      Lbl(cor,xr,yr,"Stop "+PXs(cur_invActiveStop)+(cur_invInvalidated?" [INVALIDATED]":""),cur_invInvalidated?clrRed:clrSilver,fs); yr-=dyr;
      Lbl(cor,xr,yr,"TP1 "+PXs(cur_teTp1)+"  TP2 "+PXs(cur_teTp2)+"  RR "+(naf(cur_teRR)?"-":DoubleToString(cur_teRR,2)),clrSilver,fs); yr-=dyr;
      Lbl(cor,xr,yr,"Path "+cur_teExpectedPath,clrSilver,fs); yr-=dyr;
      if(showV72Destination) Lbl(cor,xr,yr,"DEST "+cur_tplWinnerClass+" "+PXs(cur_tplMainTarget)+" ("+cur_tplSource+")",(color)0xFFD700,fs); yr-=dyr;
      Lbl(cor,xr,yr,"FRZ active "+IntegerToString(cur_frzActive)+" (B"+IntegerToString(cur_frzBull)+"/S"+IntegerToString(cur_frzBear)+") best "+IntegerToString(cur_frzBest)+"%",clrSilver,fs); yr-=dyr;
   }
}

//==================================================================
// OnDeinit
//==================================================================
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0,"L37_");
   Comment("");
}
//+------------------------------------------------------------------+
