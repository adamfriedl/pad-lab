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

export function formatCompactUsd(d: number): string {
  if (d < 0) return `-${formatCompactUsd(-d)}`;
  if (d >= 1_000_000) return `${(d / 1_000_000).toFixed(1)}M`;
  if (d >= 1000) return `${Math.round(d / 1000)}k`;
  return String(Math.round(d));
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

/** Shared horizontal bar chart for the split panels. */
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
