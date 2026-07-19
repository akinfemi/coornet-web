import { useState } from 'react'
import type { TwitterImportSpec } from '../lib/api'

const INTENTS = [
  ['retweets', 'Retweets — who amplifies the same tweets together'],
  ['hashtags', 'Hashtags — who pushes the same hashtags together'],
  ['urls', 'URLs — who shares the same links together'],
  ['urls_domains', 'Domains — who shares the same sites together'],
] as const

export default function TwitterImportForm({
  busy,
  progress,
  onSubmit,
}: {
  busy: boolean
  progress: string | null
  onSubmit: (spec: TwitterImportSpec) => void
}) {
  const [token, setToken] = useState('')
  const [mode, setMode] = useState<TwitterImportSpec['mode']>('search_recent')
  const [query, setQuery] = useState('')
  const [userId, setUserId] = useState('')
  const [intent, setIntent] = useState<TwitterImportSpec['intent']>('retweets')
  const [maxResults, setMaxResults] = useState(1000)

  const valid =
    token.trim() !== '' &&
    (mode === 'user_tweets' ? /^\d+$/.test(userId) : query.trim() !== '')

  return (
    <div className="grid gap-4 text-sm">
      <h2 className="font-medium">Import from the X API v2</h2>
      <p style={{ color: 'var(--text-secondary)' }}>
        Bring your own API key. Reading tweets requires the paid <strong>Basic</strong>{' '}
        tier or higher; <code>search_all</code> (full archive) requires <strong>Pro</strong>.
        Your bearer token is used for this import only and is never stored.
      </p>

      <label className="grid gap-1">
        <span>Bearer token</span>
        <input
          type="password"
          className="rounded-md border px-2 py-1.5 font-mono"
          style={{ borderColor: 'var(--baseline)', background: 'var(--page)' }}
          value={token}
          autoComplete="off"
          onChange={(e) => setToken(e.target.value)}
          placeholder="AAAA…"
        />
      </label>

      <div className="grid grid-cols-2 gap-3">
        <label className="grid gap-1">
          <span>Source</span>
          <select
            className="rounded-md border px-2 py-1.5"
            style={{ borderColor: 'var(--baseline)', background: 'var(--surface-1)' }}
            value={mode}
            onChange={(e) => setMode(e.target.value as TwitterImportSpec['mode'])}
          >
            <option value="search_recent">Search — last 7 days (Basic tier)</option>
            <option value="search_all">Search — full archive (Pro tier)</option>
            <option value="user_tweets">A user's tweets</option>
          </select>
        </label>
        <label className="grid gap-1">
          <span>Max posts</span>
          <input
            type="number"
            min={10}
            max={50000}
            className="rounded-md border px-2 py-1.5"
            style={{ borderColor: 'var(--baseline)', background: 'var(--page)' }}
            value={maxResults}
            onChange={(e) => setMaxResults(Number(e.target.value))}
          />
        </label>
      </div>

      {mode === 'user_tweets' ? (
        <label className="grid gap-1">
          <span>Numeric user ID</span>
          <input
            className="rounded-md border px-2 py-1.5 font-mono"
            style={{ borderColor: 'var(--baseline)', background: 'var(--page)' }}
            value={userId}
            onChange={(e) => setUserId(e.target.value)}
            placeholder="e.g. 2244994945"
          />
        </label>
      ) : (
        <label className="grid gap-1">
          <span>Search query</span>
          <input
            className="rounded-md border px-2 py-1.5"
            style={{ borderColor: 'var(--baseline)', background: 'var(--page)' }}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder='e.g. #election2026 lang:en -is:reply'
          />
          <span className="text-xs" style={{ color: 'var(--text-muted)' }}>
            Standard X search operators work (hashtags, from:, lang:, -is:retweet…)
          </span>
        </label>
      )}

      <label className="grid gap-1">
        <span>Coordination signal</span>
        <select
          className="rounded-md border px-2 py-1.5"
          style={{ borderColor: 'var(--baseline)', background: 'var(--surface-1)' }}
          value={intent}
          onChange={(e) => setIntent(e.target.value as TwitterImportSpec['intent'])}
        >
          {INTENTS.map(([v, label]) => (
            <option key={v} value={v}>
              {label}
            </option>
          ))}
        </select>
      </label>

      <div>
        <button
          disabled={!valid || busy}
          onClick={() =>
            onSubmit({
              bearer_token: token.trim(),
              mode,
              query: mode === 'user_tweets' ? undefined : query.trim(),
              user_id: mode === 'user_tweets' ? userId : undefined,
              intent,
              max_results: maxResults,
            })
          }
          className="rounded-md px-4 py-2 text-sm font-medium disabled:opacity-50"
          style={{ background: 'var(--accent)', color: '#fff' }}
        >
          {busy ? 'Importing…' : 'Fetch and map'}
        </button>
        {progress && (
          <p className="mt-2 text-xs" style={{ color: 'var(--text-muted)' }}>
            {progress}
          </p>
        )}
      </div>
    </div>
  )
}
