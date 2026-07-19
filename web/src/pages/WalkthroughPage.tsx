import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import NetworkView from '../components/NetworkView'
import type { NetworkPayload } from '../lib/api'

interface Step {
  title: string
  body: string
  code: string
  network: string | null // filename under /walkthrough, or null for text-only
}

const STEPS: Step[] = [
  {
    title: 'The data: 35,125 retweets from Russian political Twitter',
    body:
      'The bundled dataset (Kulichkina, Righetti & Waldherr 2024) contains anonymized ' +
      'pro-government retweets. Every row is one share event in the CooRTweet schema: ' +
      'object_id (the retweeted tweet), account_id (who retweeted), content_id (the ' +
      'retweet itself), and timestamp_share. This is exactly the shape your own CSV ' +
      'needs — nothing platform-specific survives the mapping.',
    code:
      'library(CooRTweet)\ndata(russian_coord_tweets)\nstr(russian_coord_tweets)\n' +
      '# object_id, account_id, content_id, timestamp_share',
    network: null,
  },
  {
    title: 'Detect accounts sharing the same content within 60 seconds',
    body:
      'detect_groups() finds every pair of accounts that shared the same object within ' +
      'the time window. A 60-second window with minimum participation of 2 yields ' +
      'thousands of coordinated pairs — but a pair appearing once can be coincidence. ' +
      'The network step separates signal from noise.',
    code:
      'result <- detect_groups(\n  russian_coord_tweets,\n  time_window = 60,\n' +
      '  min_participation = 2\n)',
    network: null,
  },
  {
    title: 'The full coordination network',
    body:
      'Every co-sharing pair becomes an edge; edge weight counts how often the pair ' +
      'repeated. Most of this network is incidental — accounts that happened to retweet ' +
      'the same viral post once. The edge-weight threshold (here the 0.5 percentile of ' +
      'weights, strict >) marks the repeated, systematic pairs. Drag the percentile ' +
      'slider to watch the incidental periphery fall away.',
    code:
      'graph <- generate_coordinated_network(\n  result,\n  edge_weight = 0.5,\n' +
      '  subgraph = 0\n)',
    network: 'russian-full.json',
  },
  {
    title: 'The coordinated core',
    body:
      'With subgraph = 1, only edges above the threshold remain: a tight cluster of ' +
      'accounts that repeatedly amplified the same tweets within a minute of each ' +
      'other — the structural signature of coordinated amplification described in the ' +
      'papers. Click nodes for per-account statistics (account_stats).',
    code:
      'core <- generate_coordinated_network(\n  result,\n  edge_weight = 0.5,\n' +
      '  subgraph = 1\n)\naccount_stats(core, result, weight_threshold = "full")',
    network: 'russian-core.json',
  },
  {
    title: 'Multi-platform: the 2021 German federal election',
    body:
      'The method generalizes beyond retweets. Here, 218,971 Facebook and Twitter posts ' +
      'are reshaped four ways — same URL, same domain, same hashtag, same image ' +
      '(perceptual hash) — each intent detected separately (30s window) and combined ' +
      'into a single cross-platform, cross-signal coordination network.',
    code:
      '# per intent: prep_data(...) |> detect_groups(time_window = 30)\n' +
      'combined <- rbindlist(list(urls, domains, hashtags, images))\n' +
      'net <- generate_coordinated_network(combined, edge_weight = 0.5, subgraph = 1)',
    network: 'german-combined.json',
  },
  {
    title: 'The fastest actors: re-flagging at 10 seconds',
    body:
      'flag_speed_share() re-tests each coordinated share against a much narrower ' +
      'window. Accounts that repeatedly share the same URLs within 10 seconds are ' +
      'very unlikely to be humans hitting retweet at the same moment — this "fast" ' +
      'subgraph is where automation and tight orchestration concentrate.',
    code:
      'flagged <- flag_speed_share(urls, result,\n  min_participation = 2, time_window = 10)\n' +
      'fast <- generate_coordinated_network(flagged,\n  fast_net = TRUE, edge_weight = 0.5, subgraph = 2)',
    network: 'german-fast.json',
  },
]

export default function WalkthroughPage() {
  const [step, setStep] = useState(0)
  const s = STEPS[step]

  const network = useQuery({
    queryKey: ['walkthrough', s.network],
    queryFn: async () => {
      const res = await fetch(`/walkthrough/${s.network}`)
      if (!res.ok) throw new Error('walkthrough data missing — run build_walkthrough.R')
      return (await res.json()) as NetworkPayload
    },
    enabled: s.network !== null,
    staleTime: Infinity,
  })

  return (
    <div className="grid h-full grid-cols-[24rem_1fr]">
      <aside
        className="flex min-h-0 flex-col overflow-auto border-r"
        style={{ borderColor: 'var(--border)' }}
      >
        <div className="p-5">
          <h1 className="mb-1 text-lg font-semibold">How coordination detection works</h1>
          <p className="mb-4 text-xs" style={{ color: 'var(--text-muted)' }}>
            Reproducing the published analyses on the packages' bundled datasets —
            precomputed, nothing to run.
          </p>
          <ol className="grid gap-1">
            {STEPS.map((st, i) => (
              <li key={i}>
                <button
                  onClick={() => setStep(i)}
                  className="w-full rounded-md px-3 py-2 text-left text-sm"
                  style={
                    i === step
                      ? { background: 'var(--grid)', fontWeight: 600 }
                      : { color: 'var(--text-secondary)' }
                  }
                >
                  {i + 1}. {st.title}
                </button>
              </li>
            ))}
          </ol>
        </div>
        <div className="mt-auto border-t p-5" style={{ borderColor: 'var(--border)' }}>
          <h2 className="mb-1 text-sm font-semibold">{s.title}</h2>
          <p className="mb-3 text-sm leading-6" style={{ color: 'var(--text-secondary)' }}>
            {s.body}
          </p>
          <pre
            className="overflow-x-auto rounded-md p-3 text-xs leading-5"
            style={{ background: 'var(--surface-1)', border: '1px solid var(--grid)' }}
          >
            <code>{s.code}</code>
          </pre>
          <div className="mt-4 flex justify-between">
            <button
              disabled={step === 0}
              onClick={() => setStep((v) => v - 1)}
              className="text-sm disabled:opacity-40"
            >
              ← Back
            </button>
            <button
              disabled={step === STEPS.length - 1}
              onClick={() => setStep((v) => v + 1)}
              data-testid="walkthrough-next"
              className="rounded-md px-3 py-1.5 text-sm font-medium disabled:opacity-40"
              style={{ background: 'var(--accent)', color: '#fff' }}
            >
              Next →
            </button>
          </div>
        </div>
      </aside>

      <section className="min-h-0">
        {s.network === null ? (
          <div className="flex h-full items-center justify-center p-10">
            <div className="max-w-md text-center text-sm" style={{ color: 'var(--text-muted)' }}>
              <p className="mb-2 text-4xl" aria-hidden>
                ⿻
              </p>
              The network appears at step 3 — first the data and the detection step.
            </div>
          </div>
        ) : network.isLoading ? (
          <div className="flex h-full items-center justify-center text-sm">Loading network…</div>
        ) : network.data ? (
          <NetworkView key={s.network} network={network.data} />
        ) : (
          <div className="flex h-full items-center justify-center text-sm" style={{ color: 'var(--critical)' }}>
            {network.error instanceof Error ? network.error.message : 'failed to load'}
          </div>
        )}
      </section>
    </div>
  )
}
