import * as Plot from '@observablehq/plot';
import { formatUsd } from './format';

const BODY_FONT = '12px "Public Sans", system-ui, sans-serif';

let measureCtx: CanvasRenderingContext2D | null = null;

function measureFont(): string {
  if (typeof document === 'undefined') return BODY_FONT;
  const root = getComputedStyle(document.documentElement);
  const family = root.getPropertyValue('--font-body').trim() || 'system-ui, sans-serif';
  return `12px ${family}`;
}

function textWidth(text: string, font = measureFont()): number {
  if (typeof document === 'undefined') return text.length * 7;
  measureCtx ??= document.createElement('canvas').getContext('2d');
  if (!measureCtx) return text.length * 7;
  measureCtx.font = font;
  return measureCtx.measureText(text).width;
}

function marginLeftForLabels(yLabels: string[]): number {
  const maxLabel = yLabels.reduce((m, s) => Math.max(m, textWidth(s)), 0);
  return Math.ceil(Math.max(72, maxLabel + 18));
}

function marginRightForValues(values: number[]): number {
  const maxValue = values.reduce((m, v) => Math.max(m, textWidth(formatUsd(v))), 0);
  return Math.ceil(Math.max(20, maxValue + 12));
}

export type DailyScale = {
  domain: [number, number];
  inScale: Array<{ date: string; total_amount: number }>;
  outliers: Array<{ date: string; total_amount: number }>;
  /** In-scale days whose net total is below zero (refunds/adjustments). */
  negativeDays: Array<{ date: string; total_amount: number }>;
};

export function formatCompactUsd(d: number): string {
  if (d < 0) return `-${formatCompactUsd(-d)}`;
  if (d >= 1_000_000) return `${(d / 1_000_000).toFixed(1)}M`;
  if (d >= 1000) return `${Math.round(d / 1000)}k`;
  return String(Math.round(d));
}

/** Left margin for y ticks plus the vertical axis label. */
export function marginLeftForTimeSeriesY(domain: [number, number]): number {
  const [, hi] = domain;
  const samples = [0, hi * 0.25, hi * 0.5, hi * 0.75, hi].map(formatCompactUsd);
  return marginLeftForLabels(samples) + 36;
}

const MAX_SPIKE_OUTLIERS = 2;
const SPIKE_RATIO = 4;

/**
 * Clip at most two days that dominate the scale (4× next-largest) so smaller days stay visible.
 * Y-axis is floored at $0; net-negative days are kept in the series but plotted at zero.
 */
export function dailyYScale(points: Array<{ date: string; total_amount: number }>): DailyScale {
  const outliers: Array<{ date: string; total_amount: number }> = [];
  let inScale = [...points];

  while (inScale.length > 1 && outliers.length < MAX_SPIKE_OUTLIERS) {
    const positives = inScale.map((p) => p.total_amount).filter((v) => v > 0);
    if (positives.length <= 1) break;

    const sorted = [...positives].sort((a, b) => a - b);
    const max = sorted[sorted.length - 1]!;
    const secondMax = sorted[sorted.length - 2]!;
    if (max <= secondMax * SPIKE_RATIO) break;

    const peak = inScale.reduce((a, b) => (a.total_amount >= b.total_amount ? a : b));
    outliers.push(peak);
    inScale = inScale.filter((p) => p.date !== peak.date);
  }

  if (inScale.length === 0) {
    return { domain: [0, 1], inScale: [], outliers, negativeDays: [] };
  }

  const plotAmounts = inScale.map((p) => Math.max(0, p.total_amount));
  const yMax = Math.max(...plotAmounts, 0);
  const pad = yMax > 0 ? Math.max(yMax * 0.08, 50) : 1;
  const negativeDays = inScale.filter((p) => p.total_amount < 0);

  return {
    domain: [0, yMax > 0 ? yMax + pad : 1],
    inScale,
    outliers,
    negativeDays,
  };
}

export function chartWidth(containerWidth: number, max = 920): number {
  return Math.max(280, Math.min(max, containerWidth || 640));
}

export async function whenFontsReady(): Promise<void> {
  if (typeof document === 'undefined' || !document.fonts) return;
  await document.fonts.ready;
}

export type HorizBarRow = { y: string; x: number; fill: string };

type HorizBarChartOpts = {
  rows: HorizBarRow[];
  width: number;
  rowHeight?: number;
  minHeight?: number;
  tipX?: (value: number) => string;
};

/** Shared horizontal bar chart used by the split panels below the time series. */
export function createHorizBarChart({
  rows,
  width,
  rowHeight = 28,
  minHeight = 200,
  tipX,
}: HorizBarChartOpts): ReturnType<typeof Plot.plot> {
  const marginLeft = marginLeftForLabels(rows.map((r) => r.y));
  const marginRight = marginRightForValues(rows.map((r) => r.x));
  const marginBottom = 36;

  return Plot.plot({
    width,
    height: Math.max(minHeight, rows.length * rowHeight + marginBottom + 12),
    marginLeft,
    marginRight,
    marginTop: 8,
    marginBottom,
    style: {
      background: 'transparent',
      color: 'var(--ink-muted)',
      fontFamily: 'var(--font-body)',
      fontSize: '12px',
    },
    x: {
      label: 'Total raised',
      labelAnchor: 'center',
      labelArrow: false,
      grid: true,
      tickFormat: (d: number) =>
        d >= 1_000_000 ? `${(d / 1_000_000).toFixed(1)}M` : `${Math.round(d / 1000)}k`,
    },
    y: { label: null },
    marks: [
      Plot.barX(rows, {
        y: 'y',
        x: 'x',
        fill: 'fill',
        sort: { y: '-x' },
        tip: tipX
          ? {
              format: {
                x: tipX,
              },
            }
          : true,
      }),
      Plot.text(rows, {
        y: 'y',
        x: 'x',
        text: (d: HorizBarRow) => formatUsd(d.x),
        dx: 6,
        textAnchor: 'start',
        fill: 'var(--ink-muted)',
        fontSize: 11,
      }),
    ],
  });
}
