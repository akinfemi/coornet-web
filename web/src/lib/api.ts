import { z } from 'zod'

const BASE = '/api/v1'

export const UploadResponse = z.object({
  dataset_id: z.string(),
  columns: z.array(z.string()),
  n_rows: z.number(),
  sample_rows: z.array(z.record(z.string(), z.unknown())),
})
export type UploadResponse = z.infer<typeof UploadResponse>

export const MappingReport = z.object({
  dataset_id: z.string(),
  report: z.object({
    n_rows: z.number(),
    n_rows_dropped_na: z.number(),
    n_accounts: z.number(),
    n_objects: z.number(),
    timestamp_range: z.array(z.string()),
    oversize_objects: z.unknown().nullish(),
  }),
})
export type MappingReport = z.infer<typeof MappingReport>

export interface JobParams {
  time_window: number
  min_participation: number
  remove_loops: boolean
  edge_weight: number
  subgraph: number
  objects: boolean
  fast_net?: { time_window: number }
}

export const JobStatus = z.object({
  job_id: z.string(),
  status: z.enum(['queued', 'running', 'succeeded', 'failed']),
  stage: z.string().nullish(),
  error: z.string().nullish(),
  dataset_id: z.string().nullish(),
  derived_from: z.string().nullish(),
  params: z.record(z.string(), z.unknown()).nullish(),
})
export type JobStatus = z.infer<typeof JobStatus>

export interface NetworkNode {
  id: string
  community: number
  degree: number
  strength: number
  [k: string]: unknown
}

export interface NetworkEdge {
  source: string
  target: string
  weight: number
  avg_time_delta: number
  edge_symmetry_score: number
  weight_threshold?: number
  [k: string]: unknown
}

export interface NetworkPayload {
  meta: {
    n_nodes: number
    n_edges: number
    params: Record<string, unknown>
    fast_net: boolean
    weight_col: string
    weight_quantiles: { p: number[]; q: number[] }
  }
  nodes: NetworkNode[]
  edges: NetworkEdge[]
}

export interface StatsPage {
  total: number
  page: number
  per_page: number
  rows: Record<string, unknown>[]
}

async function jsonOrThrow(res: Response) {
  const body = await res.json().catch(() => ({}))
  if (!res.ok) {
    throw new Error(
      typeof body?.error === 'string' ? body.error : `request failed (${res.status})`,
    )
  }
  return body
}

export async function uploadDataset(file: File): Promise<UploadResponse> {
  const fd = new FormData()
  fd.append('file', file)
  const res = await fetch(`${BASE}/datasets`, { method: 'POST', body: fd })
  return UploadResponse.parse(await jsonOrThrow(res))
}

export async function mapDataset(
  datasetId: string,
  mapping: Record<'object_id' | 'account_id' | 'content_id' | 'timestamp_share', string>,
): Promise<MappingReport> {
  const res = await fetch(`${BASE}/datasets/${datasetId}/mapping`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(mapping),
  })
  return MappingReport.parse(await jsonOrThrow(res))
}

export async function createJob(
  datasetId: string,
  params: Partial<JobParams>,
  derivedFrom?: string,
): Promise<{ job_id: string }> {
  const res = await fetch(`${BASE}/jobs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ dataset_id: datasetId, params, derived_from: derivedFrom }),
  })
  return (await jsonOrThrow(res)) as { job_id: string }
}

export async function getJob(jobId: string): Promise<JobStatus> {
  const res = await fetch(`${BASE}/jobs/${jobId}`)
  return JobStatus.parse(await jsonOrThrow(res))
}

export async function getNetwork(jobId: string): Promise<NetworkPayload> {
  const res = await fetch(`${BASE}/jobs/${jobId}/network`)
  if (!res.ok) throw new Error(`network not available (${res.status})`)
  return (await res.json()) as NetworkPayload
}

export async function getStats(
  jobId: string,
  kind: 'accounts' | 'groups',
  page: number,
  perPage: number,
  sort?: string,
): Promise<StatsPage> {
  const params = new URLSearchParams({ page: String(page), per_page: String(perPage) })
  if (sort) params.set('sort', sort)
  const res = await fetch(`${BASE}/jobs/${jobId}/${kind}?${params}`)
  return (await jsonOrThrow(res)) as StatsPage
}

export function exportUrl(jobId: string, format: string): string {
  return `${BASE}/jobs/${jobId}/export?format=${format}`
}
