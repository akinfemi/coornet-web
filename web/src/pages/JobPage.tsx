import { useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { getJob, getNetwork, createJob, exportUrl, type JobParams } from '../lib/api'
import NetworkView from '../components/NetworkView'
import StatsTable from '../components/StatsTable'

const STAGE_LABELS: Record<string, string> = {
  queued: 'Waiting for a worker…',
  detecting: 'Detecting coordinated groups…',
  flagging_speed: 'Flagging fast shares…',
  building_network: 'Building the network…',
  stats: 'Computing account statistics…',
  serializing: 'Preparing results…',
}

type Tab = 'network' | 'accounts' | 'groups' | 'export'

export default function JobPage() {
  const { jobId = '' } = useParams()
  const navigate = useNavigate()
  const [tab, setTab] = useState<Tab>('network')
  const [rerunBusy, setRerunBusy] = useState(false)

  const job = useQuery({
    queryKey: ['job', jobId],
    queryFn: () => getJob(jobId),
    refetchInterval: (q) => {
      const s = q.state.data?.status
      return s === 'queued' || s === 'running' ? 2000 : false
    },
  })

  const network = useQuery({
    queryKey: ['network', jobId],
    queryFn: () => getNetwork(jobId),
    enabled: job.data?.status === 'succeeded',
    staleTime: Infinity,
  })

  const params = (job.data?.params ?? {}) as Partial<JobParams>
  const [draft, setDraft] = useState<Partial<JobParams> | null>(null)
  const effective = { ...params, ...draft }

  const dirty =
    draft !== null &&
    (draft.time_window !== undefined || draft.min_participation !== undefined)

  const onRerun = async () => {
    if (!job.data?.dataset_id) return
    setRerunBusy(true)
    try {
      const { job_id } = await createJob(
        job.data.dataset_id,
        { ...params, ...draft },
        jobId,
      )
      setDraft(null)
      setTab('network')
      navigate(`/jobs/${job_id}`)
    } finally {
      setRerunBusy(false)
    }
  }

  if (job.isLoading) return <Center>Loading job…</Center>
  if (job.error || !job.data)
    return (
      <Center>
        <span style={{ color: 'var(--critical)' }}>
          {job.error instanceof Error ? job.error.message : 'Job not found'}
        </span>
      </Center>
    )

  const st = job.data

  return (
    <div className="grid h-full grid-cols-[16rem_1fr]">
      <aside
        className="flex min-h-0 flex-col gap-4 overflow-auto border-r p-4"
        style={{ borderColor: 'var(--border)' }}
      >
        <div>
          <h2 className="text-sm font-semibold">Parameters</h2>
          {st.derived_from && (
            <Link
              to={`/jobs/${st.derived_from}`}
              className="text-xs"
              style={{ color: 'var(--accent)' }}
            >
              ← derived from earlier run
            </Link>
          )}
        </div>

        <RailSlider
          label="Time window (s)"
          value={effective.time_window ?? 60}
          min={1}
          max={3600}
          onChange={(v) => setDraft((d) => ({ ...d, time_window: v }))}
        />
        <RailSlider
          label="Min participation"
          value={effective.min_participation ?? 2}
          min={1}
          max={20}
          onChange={(v) => setDraft((d) => ({ ...d, min_participation: v }))}
        />

        <button
          disabled={!dirty || rerunBusy || st.status !== 'succeeded'}
          onClick={onRerun}
          data-testid="rerun"
          className="rounded-md px-3 py-2 text-sm font-medium disabled:opacity-40"
          style={{ background: 'var(--accent)', color: '#fff' }}
        >
          {rerunBusy ? 'Submitting…' : 'Re-run with new parameters'}
        </button>
        <p className="text-xs" style={{ color: 'var(--text-muted)' }}>
          Edge-weight filtering is instant on the Network tab — only time window and
          participation changes need a re-run (cached detection makes them fast).
        </p>
      </aside>

      <section className="flex min-h-0 flex-col">
        <div
          className="flex items-center gap-4 border-b px-6 py-2"
          style={{ borderColor: 'var(--border)', background: 'var(--surface-1)' }}
        >
          {(['network', 'accounts', 'groups', 'export'] as Tab[]).map((t) => (
            <button
              key={t}
              onClick={() => setTab(t)}
              className="py-1 text-sm capitalize"
              style={
                tab === t
                  ? {
                      color: 'var(--text-primary)',
                      fontWeight: 600,
                      borderBottom: '2px solid var(--accent)',
                    }
                  : { color: 'var(--text-secondary)' }
              }
            >
              {t === 'groups' ? 'objects' : t}
            </button>
          ))}
          <StatusBadge status={st.status} stage={st.stage ?? undefined} />
        </div>

        <div className="min-h-0 flex-1">
          {st.status === 'failed' && (
            <Center>
              <div className="max-w-lg text-sm">
                <p className="mb-2 font-semibold" style={{ color: 'var(--critical)' }}>
                  Job failed
                </p>
                <p style={{ color: 'var(--text-secondary)' }}>{st.error}</p>
              </div>
            </Center>
          )}
          {(st.status === 'queued' || st.status === 'running') && (
            <Center>
              <div className="text-center text-sm" data-testid="job-progress">
                <div
                  className="mx-auto mb-3 h-6 w-6 animate-spin rounded-full border-2 border-t-transparent"
                  style={{ borderColor: 'var(--accent)', borderTopColor: 'transparent' }}
                />
                {STAGE_LABELS[st.stage ?? 'queued'] ?? st.stage}
              </div>
            </Center>
          )}
          {st.status === 'succeeded' && tab === 'network' && (
            <>
              {network.isLoading && <Center>Loading network…</Center>}
              {network.data && <NetworkView network={network.data} />}
            </>
          )}
          {st.status === 'succeeded' && tab === 'accounts' && (
            <StatsTable jobId={jobId} kind="accounts" />
          )}
          {st.status === 'succeeded' && tab === 'groups' && (
            <StatsTable jobId={jobId} kind="groups" />
          )}
          {st.status === 'succeeded' && tab === 'export' && <ExportTab jobId={jobId} />}
        </div>
      </section>
    </div>
  )
}

function StatusBadge({ status, stage }: { status: string; stage?: string }) {
  const color =
    status === 'succeeded'
      ? 'var(--good)'
      : status === 'failed'
        ? 'var(--critical)'
        : 'var(--accent)'
  return (
    <span className="ml-auto flex items-center gap-1.5 text-xs" style={{ color }}>
      <span
        aria-hidden
        className="inline-block h-2 w-2 rounded-full"
        style={{ background: color }}
      />
      {status}
      {stage && status === 'running' ? ` · ${stage}` : ''}
    </span>
  )
}

function RailSlider({
  label,
  value,
  min,
  max,
  onChange,
}: {
  label: string
  value: number
  min: number
  max: number
  onChange: (v: number) => void
}) {
  return (
    <label className="grid gap-1 text-sm">
      <span className="flex justify-between">
        <span>{label}</span>
        <span className="tabular font-semibold">{value}</span>
      </span>
      <input
        type="range"
        min={min}
        max={max}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
      />
    </label>
  )
}

function ExportTab({ jobId }: { jobId: string }) {
  const items = [
    ['graphml', 'GraphML', 'Gephi, igraph, NetworkX'],
    ['gexf', 'GEXF', 'Gephi, sigma.js'],
    ['accounts_csv', 'Accounts CSV', 'per-account coordination stats'],
    ['groups_csv', 'Objects CSV', 'per-object share stats (needs "objects" enabled)'],
    ['pairs_csv', 'Pairs CSV', 'raw coordinated pair table from detect_groups'],
  ] as const
  return (
    <div className="p-6">
      <ul className="grid max-w-md gap-3">
        {items.map(([fmt, name, desc]) => (
          <li key={fmt}>
            <a
              href={exportUrl(jobId, fmt)}
              className="block rounded-lg border p-4 hover:shadow-sm"
              style={{ borderColor: 'var(--border)', background: 'var(--surface-1)' }}
            >
              <span className="font-medium" style={{ color: 'var(--accent)' }}>
                ↓ {name}
              </span>
              <span className="block text-xs" style={{ color: 'var(--text-muted)' }}>
                {desc}
              </span>
            </a>
          </li>
        ))}
      </ul>
    </div>
  )
}

function Center({ children }: { children: React.ReactNode }) {
  return <div className="flex h-full items-center justify-center">{children}</div>
}
