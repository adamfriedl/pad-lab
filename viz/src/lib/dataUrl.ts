/** GCS bucket for live mart JSON — matches infra `viz_data_base_url` (pad-lab-{project}-viz). */
const REMOTE_DATA_BASE = import.meta.env.PROD
  ? 'https://storage.googleapis.com/pad-lab-gcp-lab-497423-viz/'
  : undefined;

/** Resolve a mart JSON path against bundled files or live GCS export. */
export function dataUrl(path: string): string {
  const normalized = path.replace(/^\//, '');
  if (REMOTE_DATA_BASE) {
    return `${REMOTE_DATA_BASE}${normalized}`;
  }
  return `${import.meta.env.BASE_URL}${normalized}`;
}
