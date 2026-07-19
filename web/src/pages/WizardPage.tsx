import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  uploadDataset,
  mapDataset,
  createJob,
  twitterImport,
  waitForJob,
  type UploadResponse,
  type MappingReport,
  type JobParams,
  type TwitterImportSpec,
} from '../lib/api'
import TwitterImportForm from '../components/TwitterImportForm'

const SCHEMA_FIELDS = ['object_id', 'account_id', 'content_id', 'timestamp_share'] as const
type SchemaField = (typeof SCHEMA_FIELDS)[number]

const FIELD_HELP: Record<SchemaField, string> = {
  object_id: 'What is being shared (retweeted tweet id, URL, hashtag…)',
  account_id: 'Who shares it (author / account id)',
  content_id: 'The share itself (tweet/post id)',
  timestamp_share: 'When it was shared (UNIX seconds or "YYYY-MM-DD HH:MM:SS")',
}

export default function WizardPage() {
  const navigate = useNavigate()
  const [step, setStep] = useState(0)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const [upload, setUpload] = useState<UploadResponse | null>(null)
  const [mapping, setMapping] = useState<Partial<Record<SchemaField, string>>>({})
  const [report, setReport] = useState<MappingReport | null>(null)
  const [params, setParams] = useState<Partial<JobParams>>({
    time_window: 60,
    min_participation: 2,
    edge_weight: 0.5,
    subgraph: 1,
  })

  const guessMapping = (columns: string[]) => {
    const guess: Partial<Record<SchemaField, string>> = {}
    for (const f of SCHEMA_FIELDS) {
      if (columns.includes(f)) guess[f] = f
    }
    return guess
  }

  const onFile = async (file: File) => {
    setBusy(true)
    setError(null)
    try {
      const up = await uploadDataset(file)
      setUpload(up)
      setMapping(guessMapping(up.columns))
      setStep(1)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  const mappingComplete = useMemo(
    () => SCHEMA_FIELDS.every((f) => mapping[f]),
    [mapping],
  )

  const onMap = async () => {
    if (!upload || !mappingComplete) return
    setBusy(true)
    setError(null)
    try {
      const rep = await mapDataset(
        upload.dataset_id,
        mapping as Record<SchemaField, string>,
      )
      setReport(rep)
      setStep(2)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  const onRun = async () => {
    const datasetId = upload?.dataset_id ?? importedDatasetId
    if (!datasetId) return
    setBusy(true)
    setError(null)
    try {
      const { job_id } = await createJob(datasetId, params)
      navigate(`/jobs/${job_id}`)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
      setBusy(false)
    }
  }

  const [source, setSource] = useState<'upload' | 'twitter'>('upload')
  const [importedDatasetId, setImportedDatasetId] = useState<string | null>(null)
  const [importProgress, setImportProgress] = useState<string | null>(null)

  const onTwitterImport = async (spec: TwitterImportSpec) => {
    setBusy(true)
    setError(null)
    setImportProgress('Contacting the X API…')
    try {
      const { job_id, dataset_id } = await twitterImport(spec)
      setImportProgress('Fetching tweets (this can take a while for large queries)…')
      const st = await waitForJob(job_id)
      if (st.status === 'failed') {
        throw new Error(st.error ?? 'import failed')
      }
      setImportedDatasetId(dataset_id)
      // The import replaces any earlier upload as the active dataset.
      setUpload(null)
      setReport({
        dataset_id,
        report: {
          n_rows: st.result?.n_rows ?? 0,
          n_rows_dropped_na: 0,
          n_accounts: 0,
          n_objects: 0,
          timestamp_range: ['', ''],
          oversize_objects: null,
        },
      })
      setStep(2)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setImportProgress(null)
      setBusy(false)
    }
  }

  return (
    <div className="mx-auto max-w-3xl px-6 py-10">
      <h1 className="mb-1 text-2xl font-semibold">New analysis</h1>
      <p className="mb-8 text-sm" style={{ color: 'var(--text-secondary)' }}>
        Upload a CSV, map it to the CooRTweet schema, tune detection parameters, run.
      </p>

      <Stepper step={step} labels={['Data', 'Map columns', 'Parameters']} />

      {error && (
        <div
          className="mb-6 rounded-md border px-4 py-3 text-sm"
          style={{ borderColor: 'var(--critical)', color: 'var(--critical)' }}
        >
          {error}
        </div>
      )}

      {step === 0 && (
        <Card>
          <div className="mb-5 flex gap-2">
            {(
              [
                ['upload', 'Upload CSV'],
                ['twitter', 'Import from X/Twitter'],
              ] as const
            ).map(([key, label]) => (
              <button
                key={key}
                onClick={() => setSource(key)}
                className="rounded-md px-3 py-1.5 text-sm font-medium"
                style={
                  source === key
                    ? { background: 'var(--accent)', color: '#fff' }
                    : { border: '1px solid var(--baseline)', color: 'var(--text-secondary)' }
                }
              >
                {label}
              </button>
            ))}
          </div>

          {source === 'upload' && (
            <>
              <h2 className="mb-2 font-medium">Upload a CSV</h2>
              <p className="mb-4 text-sm" style={{ color: 'var(--text-secondary)' }}>
                Any dataset works if each row is one “share” event: something shared, by
                someone, at some time. Gzip-compressed CSVs are accepted. Max 100&nbsp;MB /
                2M rows.
              </p>
              <input
                type="file"
                accept=".csv,.gz,text/csv"
                disabled={busy}
                data-testid="file-input"
                onChange={(e) => {
                  const f = e.target.files?.[0]
                  if (f) void onFile(f)
                }}
              />
              {busy && <Busy label="Uploading and parsing…" />}
            </>
          )}

          {source === 'twitter' && (
            <TwitterImportForm
              busy={busy}
              progress={importProgress}
              onSubmit={(spec) => void onTwitterImport(spec)}
            />
          )}
        </Card>
      )}

      {step === 1 && upload && (
        <Card>
          <h2 className="mb-2 font-medium">Map columns to the schema</h2>
          <p className="mb-4 text-sm" style={{ color: 'var(--text-secondary)' }}>
            {upload.n_rows.toLocaleString()} rows · {upload.columns.length} columns
          </p>
          <div className="mb-6 grid gap-4">
            {SCHEMA_FIELDS.map((f) => (
              <label key={f} className="grid grid-cols-[10rem_1fr] items-center gap-3 text-sm">
                <span>
                  <code className="font-semibold">{f}</code>
                  <span className="block text-xs" style={{ color: 'var(--text-muted)' }}>
                    {FIELD_HELP[f]}
                  </span>
                </span>
                <select
                  className="rounded-md border px-2 py-1.5"
                  style={{ borderColor: 'var(--baseline)', background: 'var(--surface-1)' }}
                  value={mapping[f] ?? ''}
                  data-testid={`map-${f}`}
                  onChange={(e) => setMapping((m) => ({ ...m, [f]: e.target.value || undefined }))}
                >
                  <option value="">— select column —</option>
                  {upload.columns.map((c) => (
                    <option key={c} value={c}>
                      {c}
                    </option>
                  ))}
                </select>
              </label>
            ))}
          </div>
          <SampleTable rows={upload.sample_rows.slice(0, 5)} />
          <div className="mt-6 flex gap-3">
            <Button onClick={onMap} disabled={!mappingComplete || busy} primary>
              {busy ? 'Validating…' : 'Validate mapping'}
            </Button>
            <Button onClick={() => setStep(0)} disabled={busy}>
              Back
            </Button>
          </div>
        </Card>
      )}

      {step === 2 && report && (
        <Card>
          <h2 className="mb-4 font-medium">Detection parameters</h2>
          <div
            className="mb-6 rounded-md border px-4 py-3 text-sm"
            style={{ borderColor: 'var(--grid)', color: 'var(--text-secondary)' }}
            data-testid="validation-report"
          >
            <span style={{ color: 'var(--good)' }}>✓ Valid.</span>{' '}
            {report.report.n_rows.toLocaleString()} rows
            {report.report.n_accounts > 0 && (
              <>
                {' '}
                · {report.report.n_accounts.toLocaleString()} accounts ·{' '}
                {report.report.n_objects.toLocaleString()} shared objects ·{' '}
                {report.report.timestamp_range[0]} → {report.report.timestamp_range[1]}
              </>
            )}
            {report.report.n_rows_dropped_na > 0 &&
              ` · ${report.report.n_rows_dropped_na} rows dropped (missing values)`}
          </div>

          <div className="grid gap-5">
            <ParamSlider
              label="Time window (seconds)"
              help="Shares of the same object within this window count as coordinated"
              value={params.time_window ?? 60}
              min={1}
              max={3600}
              onChange={(v) => setParams((p) => ({ ...p, time_window: v }))}
            />
            <ParamSlider
              label="Minimum participation"
              help="Accounts need at least this many shares to be considered"
              value={params.min_participation ?? 2}
              min={1}
              max={20}
              onChange={(v) => setParams((p) => ({ ...p, min_participation: v }))}
            />
            <ParamSlider
              label="Edge weight percentile"
              help="Edges above this percentile of repeated co-sharing are flagged as coordinated"
              value={params.edge_weight ?? 0.5}
              min={0}
              max={0.99}
              step={0.01}
              onChange={(v) => setParams((p) => ({ ...p, edge_weight: v }))}
            />
            <label className="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                checked={(params.subgraph ?? 1) === 1}
                onChange={(e) =>
                  setParams((p) => ({ ...p, subgraph: e.target.checked ? 1 : 0 }))
                }
              />
              Keep only edges above the threshold (recommended for large datasets)
            </label>
          </div>

          <div className="mt-8 flex gap-3">
            <Button onClick={onRun} disabled={busy} primary data-testid="run-analysis">
              {busy ? 'Submitting…' : 'Run analysis'}
            </Button>
            <Button onClick={() => setStep(1)} disabled={busy}>
              Back
            </Button>
          </div>
        </Card>
      )}
    </div>
  )
}

function Stepper({ step, labels }: { step: number; labels: string[] }) {
  return (
    <ol className="mb-8 flex gap-2 text-sm">
      {labels.map((l, i) => (
        <li key={l} className="flex items-center gap-2">
          <span
            className="flex h-6 w-6 items-center justify-center rounded-full text-xs font-semibold"
            style={
              i <= step
                ? { background: 'var(--accent)', color: '#fff' }
                : { background: 'var(--grid)', color: 'var(--text-muted)' }
            }
          >
            {i + 1}
          </span>
          <span style={{ color: i <= step ? 'var(--text-primary)' : 'var(--text-muted)' }}>
            {l}
          </span>
          {i < labels.length - 1 && (
            <span aria-hidden style={{ color: 'var(--text-muted)' }}>
              →
            </span>
          )}
        </li>
      ))}
    </ol>
  )
}

function Card({ children }: { children: React.ReactNode }) {
  return (
    <section
      className="rounded-lg border p-6"
      style={{ borderColor: 'var(--border)', background: 'var(--surface-1)' }}
    >
      {children}
    </section>
  )
}

function Button({
  children,
  onClick,
  disabled,
  primary,
  ...rest
}: {
  children: React.ReactNode
  onClick: () => void
  disabled?: boolean
  primary?: boolean
} & Record<string, unknown>) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className="rounded-md px-4 py-2 text-sm font-medium disabled:opacity-50"
      style={
        primary
          ? { background: 'var(--accent)', color: '#fff' }
          : { border: '1px solid var(--baseline)', color: 'var(--text-primary)' }
      }
      {...rest}
    >
      {children}
    </button>
  )
}

function Busy({ label }: { label: string }) {
  return (
    <p className="mt-3 text-sm" style={{ color: 'var(--text-muted)' }}>
      {label}
    </p>
  )
}

function SampleTable({ rows }: { rows: Record<string, unknown>[] }) {
  if (rows.length === 0) return null
  const cols = Object.keys(rows[0])
  return (
    <div className="overflow-x-auto rounded-md border" style={{ borderColor: 'var(--grid)' }}>
      <table className="w-full text-left text-xs">
        <thead>
          <tr style={{ color: 'var(--text-muted)' }}>
            {cols.map((c) => (
              <th key={c} className="px-3 py-2 font-medium">
                {c}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="tabular">
          {rows.map((r, i) => (
            <tr key={i} className="border-t" style={{ borderColor: 'var(--grid)' }}>
              {cols.map((c) => (
                <td key={c} className="max-w-48 truncate px-3 py-1.5">
                  {String(r[c])}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function ParamSlider({
  label,
  help,
  value,
  min,
  max,
  step = 1,
  onChange,
}: {
  label: string
  help: string
  value: number
  min: number
  max: number
  step?: number
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
        step={step}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
      />
      <span className="text-xs" style={{ color: 'var(--text-muted)' }}>
        {help}
      </span>
    </label>
  )
}
