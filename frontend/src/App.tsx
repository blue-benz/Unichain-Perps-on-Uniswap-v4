import { useMemo, useState } from "react";
import type { Hex } from "viem";

import perpsEngineAbi from "../../shared/abi/PerpsEngine.json";

type PositionSide = "LONG" | "SHORT";

type Position = {
  id: string;
  side: PositionSide;
  sizeUsd: number;
  marginUsd: number;
  entry: number;
  mark: number;
};

const seedPositions: Position[] = [
  { id: "ALICE", side: "LONG", sizeUsd: 2000, marginUsd: 500, entry: 1, mark: 0.94 },
  { id: "BOB", side: "SHORT", sizeUsd: 1500, marginUsd: 500, entry: 1, mark: 0.94 }
];

export default function App() {
  const [positions, setPositions] = useState(seedPositions);
  const [side, setSide] = useState<PositionSide>("LONG");
  const [size, setSize] = useState(1000);
  const [margin, setMargin] = useState(250);

  const fundingRate = 0.00048;
  const marketId = "0x0000000000000000000000000000000000000000000000000000000000000000" as Hex;

  const hedgePanel = useMemo(() => {
    const unhedgedPnl = -620;
    const hedgedPnl = -165;
    return {
      drawdownReductionPct: Math.round(((Math.abs(unhedgedPnl) - Math.abs(hedgedPnl)) / Math.abs(unhedgedPnl)) * 100),
      unhedgedPnl,
      hedgedPnl
    };
  }, []);

  const onOpen = () => {
    const next: Position = {
      id: `TRADER-${positions.length + 1}`,
      side,
      sizeUsd: size,
      marginUsd: margin,
      entry: 1,
      mark: 1
    };
    setPositions((prev) => [next, ...prev]);
  };

  return (
    <main className="shell">
      <section className="hero">
        <p className="eyebrow">Unichain Prize Demo</p>
        <h1>Hook-Integrated Perps Terminal</h1>
        <p className="lede">
          Isolated-margin perpetuals on Unichain, anchored to Uniswap v4 mark pricing and deterministic funding windows.
        </p>
        <div className="meta">
          <span>Market ID: {marketId}</span>
          <span>ABI methods: {perpsEngineAbi.length}</span>
          <span>Funding / window: {(fundingRate * 100).toFixed(4)}%</span>
        </div>
      </section>

      <section className="grid">
        <article className="card trade-card">
          <h2>Open / Modify Position</h2>
          <label>
            Side
            <select value={side} onChange={(e) => setSide(e.target.value as PositionSide)}>
              <option value="LONG">Long</option>
              <option value="SHORT">Short</option>
            </select>
          </label>
          <label>
            Size (USD)
            <input type="number" value={size} onChange={(e) => setSize(Number(e.target.value))} />
          </label>
          <label>
            Margin (USD)
            <input type="number" value={margin} onChange={(e) => setMargin(Number(e.target.value))} />
          </label>
          <button onClick={onOpen}>Queue Trade (Demo)</button>
        </article>

        <article className="card">
          <h2>Liquidation Monitor</h2>
          <ul className="risk-list">
            {positions.map((p) => {
              const pnl = p.side === "LONG" ? p.sizeUsd * (p.mark - p.entry) : p.sizeUsd * (p.entry - p.mark);
              const equity = p.marginUsd + pnl;
              const mmr = p.sizeUsd * 0.05;
              const unhealthy = equity < mmr;
              return (
                <li key={p.id} className={unhealthy ? "danger" : "healthy"}>
                  <span>{p.id}</span>
                  <span>{p.side}</span>
                  <span>Eq ${equity.toFixed(2)}</span>
                  <span>MMR ${mmr.toFixed(2)}</span>
                </li>
              );
            })}
          </ul>
        </article>

        <article className="card hedge-card">
          <h2>LP Hedge Narrative</h2>
          <p>LP adds concentrated liquidity, market sells off, LP opens short perp, drawdown compresses.</p>
          <div className="hedge-stats">
            <div>
              <p className="label">Unhedged LP PnL</p>
              <p className="value negative">${hedgePanel.unhedgedPnl}</p>
            </div>
            <div>
              <p className="label">Hedged LP PnL</p>
              <p className="value less-negative">${hedgePanel.hedgedPnl}</p>
            </div>
            <div>
              <p className="label">Drawdown Reduction</p>
              <p className="value positive">{hedgePanel.drawdownReductionPct}%</p>
            </div>
          </div>
        </article>
      </section>
    </main>
  );
}
