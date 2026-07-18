/** GCS base URL for live mart JSON in production builds (trailing slash optional). */
const fromEnv = import.meta.env.VITE_DATA_BASE_URL as string | undefined;

const REMOTE_DATA_BASE = import.meta.env.PROD && fromEnv ? fromEnv.replace(/\/?$/, '/') : undefined;

/** Resolve a mart JSON path against bundled files or live GCS export. */
export function dataUrl(path: string): string {
  const normalized = path.replace(/^\//, '');
  if (REMOTE_DATA_BASE) {
    return `${REMOTE_DATA_BASE}${normalized}`;
  }
  return `${import.meta.env.BASE_URL}${normalized}`;
}
