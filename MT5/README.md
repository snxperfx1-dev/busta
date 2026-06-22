# Letra 37 — MT5 Autonomous Expert Advisor (V60 engine)

A complete MQL5 port of the **Letra 37** Pine engine, upgraded with the **V60
"F16 Raptor"** stack while keeping the **Letra decision layer** as the entry
authority (no Senseei meta-layer).

## V60 upgrades in this build
- **14-phase structure engine (`f_se`)** — the lifecycle now models how a move
  actually dies and hands off: Expansion -> Pre-Convexity -> Induction ->
  Liquidity -> New High/Low -> Transition -> Retracement -> HTF Flip Zone ->
  Induction -> Liquidation -> Terminal Curve -> Demand/Supply Return. Driven by a
  compression index, recursive-transition counting and dominance transfer. The
  DIR-FIX spawn orders the order block by actual price and pins invalidation to
  the protective extreme. This also makes the Demand/Supply Return entry phase
  emit natively, so entries are reachable without any workaround.
- **F72 "is the trade alive?" curve-life score** — scores the live trade
  **ALIVE / WEAKENING / DEAD** from compression persistence (can the other side
  even build a move here?), residual energy, retrace depth, progress and the HTF
  parent threat, plus narrative lineage (are pullbacks getting shallower or
  deeper?) and chain vitality. Used for trade management.
- **Invisible Network node engine** — detects rejection-wick "FU" levels across
  MN -> M5, scores each by authority (timeframe weight + revisits + strength), and
  produces `netBias`, `pressure`, the **primary attractor** (the magnet price is
  pulled toward) and the **FEZ corridor**.
- **Adaptive timeframe ladder** — six distinct rungs that climb from the chart
  timeframe instead of collapsing to the chart above H1 (fixes the pinned
  fractal-score bug); the multi-timeframe read stays honest on any chart.

## How the pieces are wired (authority hierarchy)
- The **Letra execution/decision layer** (physics, beliefs, scoring, Bayesian
  probability, edge/slippage, execution lock, belief entries, ERF gate, and its
  `exitNow`) is the **precise authority for entries AND exits**. The 14-phase
  engine feeds this layer as its lifecycle input.
- **Two complementary Letra entry types** (`InpEntryMode`, default **both**):
  1. **Belief arrows** — the precise Section-21 reversal trigger that fires at the
     Demand/Supply Return (belief-gated, with liquidity-sweep / pre-convexity /
     induction confirmation).
  2. **DOE command** — the synthesized directional opportunity (net-edge
     "PRESSURE") entry: a continuation/pressure entry from the same Letra edge
     engine, gated by structure / HTF / grade / lock / OB / ERF but not the
     reversal-zone belief. Threshold = `InpDoeThreshold`.
- **F72 curve-life** is a **subordinate management assist**: `DEAD` abandons early
  (protective), `WEAKENING` tightens the stop. It never enters against Letra, and
  by default it does **not** hold a position open against a Letra exit
  (`InpLifeAliveHold` is off).
- The **Network** is optional confluence: `netBias` can gate entries and the
  attractor can be used as the take-profit magnet (both off by default to keep the
  Letra layer precise).

| Component | File |
|---|---|
| 14-phase structure engine (`f_se`) | `Include/Letra37/Letra37_Structure.mqh` |
| Streaming TA helpers | `Include/Letra37/Letra37_Series.mqh` |
| HTF belief engine | `Include/Letra37/Letra37_HTFBelief.mqh` |
| Decision layer + F72 curve-life | `Include/Letra37/Letra37_Brain.mqh` |
| Invisible Network node engine | `Include/Letra37/Letra37_Network.mqh` |
| Execution & risk manager | `Include/Letra37/Letra37_Trade.mqh` |
| EA orchestration, inputs, panel | `Experts/Letra37/Letra37_EA.mq5` |

## Install
1. Copy `MT5/Include/Letra37/` -> `<MetaTrader>/MQL5/Include/Letra37/`
2. Copy `MT5/Experts/Letra37/` -> `<MetaTrader>/MQL5/Experts/Letra37/`
3. Compile `Letra37_EA.mq5` in MetaEditor (F7).
4. Attach to a chart (designed for M5; the adaptive ladder keeps it valid on any TF).

## Decision flow
- Execution / canonical timeframe = the chart timeframe (rung 3 of the ladder).
- Six structure engines run on the six ladder rungs; two HTF belief engines run on
  the M15/H1-equivalent rungs.
- The engine evaluates on each **closed** bar (the still-forming bar is dropped),
  reproducing Pine confirm-on-close; the risk layer manages positions every tick.

## Risk controls
Risk-% sizing (or fixed lot), ATR + structural stops with a min reward:risk floor,
break-even, ATR trailing, F72 curve-life management, daily-loss & equity-drawdown
halts, spread filter, optional session window, one-entry-per-bar and broker
stop-level normalization.

## Backtesting note
Each new bar performs a full multi-timeframe recompute (correctness over speed) —
trivial live, but reduce the History Depth inputs for long Strategy Tester runs.

> Educational/research software. Test thoroughly on a demo account before any live
> use. No warranty; trading involves substantial risk.
