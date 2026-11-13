// Test data on a shared database must be findable and removable by whoever finds it later.
// Every record a test creates carries this prefix plus a timestamp.
export const PROBE_PREFIX = 'Probe'

export function probeName(label: string): string {
  return `${PROBE_PREFIX} ${label} ${Date.now()}`
}
