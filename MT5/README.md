# Letra 37 — MT5 Autonomous Expert Advisor

A complete MQL5 port of the **Letra 37** Pine v6 indicator (`LETRA 37.txt`, 6208 lines),
re-engineered from a chart-only intelligence dashboard into a fully **autonomous,
risk-managed Expert Advisor**.

## What was ported

The Pine script is a multi-timeframe Smart-Money / "wave physics" engine. The
trading-relevant logic was reimplemented faithfully (visual/dashboard code was not
needed for an EA):

| Pine section | MQL5 location |
|---|---|
| `f_se()` fixed-TF structure engine (dir / phase / swings / BOS / CHoCH / point-4 / invalidation / target / FRZ) | `Include/Letra37/Letra37_Structure.mqh` |
| `f_phys()` core physics (velocity / acceleration / convexity / efficiency / displacement / impulse / decay) | `Include/Letra37/Letra37_Brain.mqh` |
| `f_htfBeliefs()` HTF belief engine (tf1 / tf2) | `Include/Letra37/Letra37_HTFBelief.mqh` |
| Sections 3–24: market structure, wave spawn, Engine 1A lifecycle, ERF (Energy Resolution Framework), beliefs, scoring, Bayesian probability, slippage/edge, execution lock, entry & exit signals | `Include/Letra37/Letra37_Brain.mqh` |
| `ta.atr/ema/sma/pivothigh/pivotlow/sum/highest/lowest` | `Include/Letra37/Letra37_Series.mqh` |
| Order execution, risk-% sizing, ATR/structural stops, break-even, trailing, daily-loss & drawdown halts, spread/session filters | `Include/Letra37/Letra37_Trade.mqh` |
| EA orchestration, inputs, panel | `Experts/Letra37/Letra37_EA.mq5` |

### Architecture
- **Execution timeframe:** M5 (mirrors the source's fixed L0 = M5 engine).
- **Context engines:** six independent fixed-TF structure engines (M1, M3, M5, M15, H1, H4)
  plus two HTF belief engines (M15, H1), exactly as the Pine `request.security` calls.
- The decision engine evaluates on each **closed** M5 bar (the still-forming bar is dropped),
  reproducing Pine's confirm-on-close behaviour, then the risk layer manages positions on every tick.
- Each new bar triggers a deterministic full recompute over a rolling window, so there is
  no hidden state drift between runs.

## Install
1. Copy `MT5/Include/Letra37/` → `<MetaTrader>/MQL5/Include/Letra37/`
2. Copy `MT5/Experts/Letra37/` → `<MetaTrader>/MQL5/Experts/Letra37/`
3. Open `Letra37_EA.mq5` in MetaEditor and compile (F7).
4. Attach the EA to an **M5** chart of the instrument you want to trade.

## Important note on entries (deliberate, documented deviation)
In the original Pine, `longSignal`/`shortSignal` gate on
`ie1a_currentPhase == "Demand Return" / "Supply Return"`. However the M5 phase state
machine in `f_se()` can only emit phases up to *Retracement Induction* — it **never
produces** the "Demand/Supply Return" phase. As written, the source's entry signals are
therefore effectively unreachable (it behaves as a visualization/dashboard tool).

To make the EA actually trade, a **canonical terminal Return-phase detector** was added at
decision time: when a directional wave is in its retracement/absorption family and price
returns *into the flip (demand/supply) zone* with the Demand-Return belief dominant
(`demandReturnBelief > 50` and ≥ retracement belief), the phase is promoted to
"Demand/Supply Return". This matches the lifecycle the source documents
(`Retracement → ... → Demand/Supply Return`) and uses only existing engine variables.
It is controlled by the input **`InpEnableReturnPhase`** (default `true`). Set it `false`
to reproduce the literal (non-trading) source behaviour. All other quality gates
(HTF alignment, grade, Bayesian edge, ERF readiness, liquidity sweep, OB freshness,
induction/pre-convexity, structure confirm, execution lock) are preserved unchanged.

## Risk controls (institutional layer)
- Risk-% per trade position sizing (or fixed lot), with a max-lot cap.
- SL from ATR and/or structural invalidation (flip zone) with a configurable buffer; the
  safer of the two is used. TP from the wave target or a minimum reward:risk floor.
- Break-even move, ATR trailing stop, close-on-engine-exit.
- Daily-loss limit and equity max-drawdown halts, spread filter, optional trading session,
  one-entry-per-bar, broker stop-level normalization, magic-number isolation.

## Backtesting note
Each new bar performs a full multi-timeframe recompute (correctness over speed). This is
trivial live (once per 5 minutes) but can be slow in the Strategy Tester over long ranges.
For tester runs, reduce the `History Depth` inputs (e.g. M1=1500, M5=1500) to speed things up.

> Educational/research software. Test thoroughly on a demo account before any live use.
> No warranty; trading involves substantial risk.
