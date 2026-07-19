import { useState } from 'react'
import { useQuery, keepPreviousData } from '@tanstack/react-query'
import { getStats, exportUrl } from '../lib/api'

export default function StatsTable({
  jobId,
  kind,
}: {
  jobId: string
  kind: 'accounts' | 'groups'
}) {
  const [page, setPage] = useState(1)
  const [sort, setSort] = useState<string | undefined>(undefined)
  const perPage = 25

  const { data, isLoading, error } = useQuery({
    queryKey: ['stats', jobId, kind, page, sort],
    queryFn: () => getStats(jobId, kind, page, perPage, sort),
    placeholderData: keepPreviousData,
  })

  if (isLoading) return <p className="p-6 text-sm">Loading…</p>
  if (error)
    return (
      <p className="p-6 text-sm" style={{ color: 'var(--critical)' }}>
        {error instanceof Error ? error.message : 'failed to load'}
      </p>
    )
  if (!data || data.rows.length === 0)
    return (
      <p className="p-6 text-sm" style={{ color: 'var(--text-muted)' }}>
        No rows. {kind === 'groups' && 'Run the job with "objects" enabled to get per-object stats.'}
      </p>
    )

  const cols = Object.keys(data.rows[0])
  const pages = Math.ceil(data.total / perPage)

  const toggleSort = (col: string) => {
    setPage(1)
    setSort((s) => (s === `-${col}` ? col : `-${col}`))
  }

  return (
    <div className="p-6">
      <div className="mb-3 flex items-center justify-between text-sm">
        <span style={{ color: 'var(--text-secondary)' }}>
          {data.total.toLocaleString()} rows
        </span>
        <a
          href={exportUrl(jobId, `${kind}_csv`)}
          className="font-medium"
          style={{ color: 'var(--accent)' }}
        >
          ↓ Download CSV
        </a>
      </div>
      <div
        className="overflow-x-auto rounded-lg border"
        style={{ borderColor: 'var(--border)', background: 'var(--surface-1)' }}
      >
        <table className="w-full text-left text-xs">
          <thead>
            <tr style={{ color: 'var(--text-muted)' }}>
              {cols.map((c) => (
                <th key={c} className="px-3 py-2 font-medium">
                  <button onClick={() => toggleSort(c)} className="hover:underline">
                    {c.replaceAll('_', ' ')}
                    {sort === `-${c}` ? ' ↓' : sort === c ? ' ↑' : ''}
                  </button>
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="tabular">
            {data.rows.map((r, i) => (
              <tr key={i} className="border-t" style={{ borderColor: 'var(--grid)' }}>
                {cols.map((c) => (
                  <td key={c} className="max-w-64 truncate px-3 py-1.5">
                    {fmt(r[c])}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {pages > 1 && (
        <div className="mt-3 flex items-center gap-3 text-sm">
          <button
            disabled={page <= 1}
            onClick={() => setPage((p) => p - 1)}
            className="disabled:opacity-40"
          >
            ← Prev
          </button>
          <span className="tabular" style={{ color: 'var(--text-secondary)' }}>
            {page} / {pages}
          </span>
          <button
            disabled={page >= pages}
            onClick={() => setPage((p) => p + 1)}
            className="disabled:opacity-40"
          >
            Next →
          </button>
        </div>
      )}
    </div>
  )
}

function fmt(v: unknown): string {
  if (typeof v === 'number' && !Number.isInteger(v)) return v.toFixed(3)
  return String(v)
}
