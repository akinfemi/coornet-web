import { useEffect, useMemo, useRef, useState } from 'react'
import Graph from 'graphology'
import FA2Layout from 'graphology-layout-forceatlas2/worker'
import forceAtlas2 from 'graphology-layout-forceatlas2'
import {
  SigmaContainer,
  useLoadGraph,
  useRegisterEvents,
  useSetSettings,
  useSigma,
} from '@react-sigma/core'
import '@react-sigma/core/lib/style.css'
import type { NetworkPayload, NetworkNode } from '../lib/api'
import { communityColors, OTHER_COLOR } from '../lib/palette'

interface Props {
  network: NetworkPayload
}

interface ViewState {
  percentile: number // 0 = show all; else keep edges with weight > q[p]
  focusCommunity: number | null
  search: string
  selected: string | null
}

export default function NetworkView({ network }: Props) {
  const [view, setView] = useState<ViewState>({
    percentile: 0,
    focusCommunity: null,
    search: '',
    selected: null,
  })

  const { graph, colors, communitySizes } = useMemo(() => buildGraph(network), [network])

  const threshold =
    view.percentile > 0 ? network.meta.weight_quantiles.q[view.percentile] : null

  const selectedNode: NetworkNode | undefined = useMemo(
    () => network.nodes.find((n) => n.id === view.selected),
    [network.nodes, view.selected],
  )

  const visibleEdges = useMemo(() => {
    if (threshold === null) return network.meta.n_edges
    return network.edges.filter((e) => e.weight > threshold).length
  }, [network, threshold])

  return (
    <div className="grid h-full grid-cols-[1fr_18rem]">
      <div className="relative min-w-0">
        <SigmaContainer
          style={{ background: 'var(--surface-1)', height: '100%' }}
          settings={{
            renderEdgeLabels: false,
            defaultEdgeType: 'line',
            labelDensity: 0.1,
            labelRenderedSizeThreshold: 9,
            zIndex: true,
          }}
        >
          <GraphController
            graph={graph}
            view={view}
            threshold={threshold}
            weightCol={network.meta.weight_col}
            onSelect={(id) => setView((v) => ({ ...v, selected: id }))}
          />
          <LayoutController graph={graph} />
        </SigmaContainer>

        <div
          className="absolute left-3 top-3 flex flex-col gap-2 rounded-md border p-3 text-xs shadow-sm"
          style={{ background: 'var(--surface-1)', borderColor: 'var(--border)', width: '15rem' }}
        >
          <label className="grid gap-1">
            <span className="flex justify-between">
              <span>Edge-weight percentile</span>
              <span className="tabular font-semibold">
                {view.percentile === 0 ? 'all' : `> p${view.percentile}`}
              </span>
            </span>
            <input
              type="range"
              min={0}
              max={99}
              value={view.percentile}
              data-testid="percentile-slider"
              onChange={(e) =>
                setView((v) => ({ ...v, percentile: Number(e.target.value) }))
              }
            />
            <span style={{ color: 'var(--text-muted)' }}>
              {visibleEdges.toLocaleString()} / {network.meta.n_edges.toLocaleString()} edges
              {threshold !== null && ` (weight > ${threshold})`}
            </span>
          </label>
          <input
            type="search"
            placeholder="Find account…"
            className="rounded border px-2 py-1"
            style={{ borderColor: 'var(--baseline)', background: 'var(--page)' }}
            value={view.search}
            onChange={(e) => setView((v) => ({ ...v, search: e.target.value }))}
          />
        </div>
      </div>

      <aside
        className="min-h-0 overflow-auto border-l p-4 text-sm"
        style={{ borderColor: 'var(--border)', background: 'var(--surface-1)' }}
      >
        {selectedNode ? (
          <NodePanel
            node={selectedNode}
            color={colors.get(selectedNode.community) ?? OTHER_COLOR}
            onClear={() => setView((v) => ({ ...v, selected: null }))}
          />
        ) : (
          <CommunityLegend
            sizes={communitySizes}
            colors={colors}
            focus={view.focusCommunity}
            onFocus={(c) =>
              setView((v) => ({
                ...v,
                focusCommunity: v.focusCommunity === c ? null : c,
              }))
            }
          />
        )}
      </aside>
    </div>
  )
}

function buildGraph(network: NetworkPayload) {
  const graph = new Graph({ type: 'undirected', multi: false })
  const communitySizes = new Map<number, number>()
  for (const n of network.nodes) {
    communitySizes.set(n.community, (communitySizes.get(n.community) ?? 0) + 1)
  }
  const colors = communityColors(communitySizes)

  const maxStrength = Math.max(...network.nodes.map((n) => n.strength), 1)
  network.nodes.forEach((n, i) => {
    const angle = (2 * Math.PI * i) / network.nodes.length
    graph.addNode(n.id, {
      label: n.id,
      community: n.community,
      size: 3 + 9 * Math.sqrt(n.strength / maxStrength),
      color: colors.get(n.community) ?? OTHER_COLOR,
      x: Math.cos(angle) + 0.01 * ((i % 7) - 3),
      y: Math.sin(angle) + 0.01 * ((i % 5) - 2),
    })
  })
  for (const e of network.edges) {
    if (!graph.hasEdge(e.source, e.target)) {
      graph.addEdge(e.source, e.target, {
        weight: e.weight,
        size: Math.min(1 + Math.log2(e.weight), 6),
        threshold_pass: (e.weight_threshold ?? 1) === 1,
      })
    }
  }
  return { graph, colors, communitySizes }
}

function GraphController({
  graph,
  view,
  threshold,
  onSelect,
}: {
  graph: Graph
  view: ViewState
  threshold: number | null
  weightCol: string
  onSelect: (id: string | null) => void
}) {
  const loadGraph = useLoadGraph()
  const registerEvents = useRegisterEvents()
  const setSettings = useSetSettings()
  const sigma = useSigma()

  useEffect(() => {
    loadGraph(graph)
  }, [graph, loadGraph])

  useEffect(() => {
    registerEvents({
      clickNode: ({ node }) => onSelect(node),
      clickStage: () => onSelect(null),
    })
  }, [registerEvents, onSelect])

  useEffect(() => {
    const search = view.search.trim().toLowerCase()
    setSettings({
      nodeReducer: (node, data) => {
        const res = { ...data }
        const matchesSearch = search !== '' && node.toLowerCase().includes(search)
        if (search !== '' && !matchesSearch) {
          res.color = 'var(--grid)'
          res.label = ''
        }
        if (matchesSearch) {
          res.highlighted = true
        }
        if (
          view.focusCommunity !== null &&
          (data.community as number) !== view.focusCommunity
        ) {
          res.color = 'rgba(137,135,129,0.25)'
          res.label = ''
        }
        if (view.selected === node) res.highlighted = true
        return res
      },
      edgeReducer: (edge, data) => {
        const res = { ...data }
        if (threshold !== null && (data.weight as number) <= threshold) {
          res.hidden = true
        }
        if (view.focusCommunity !== null) {
          const [s, t] = sigma.getGraph().extremities(edge)
          const cs = sigma.getGraph().getNodeAttribute(s, 'community')
          const ct = sigma.getGraph().getNodeAttribute(t, 'community')
          if (cs !== view.focusCommunity && ct !== view.focusCommunity) res.hidden = true
        }
        return res
      },
    })
  }, [setSettings, sigma, view, threshold])

  return null
}

function LayoutController({ graph }: { graph: Graph }) {
  const [running, setRunning] = useState(true)
  const layoutRef = useRef<FA2Layout | null>(null)

  useEffect(() => {
    const settings = forceAtlas2.inferSettings(graph)
    const layout = new FA2Layout(graph, { settings: { ...settings, slowDown: 5 } })
    layoutRef.current = layout
    layout.start()
    setRunning(true)
    const stopTimer = window.setTimeout(() => {
      layout.stop()
      setRunning(false)
    }, 6000)
    return () => {
      window.clearTimeout(stopTimer)
      layout.kill()
    }
  }, [graph])

  return (
    <button
      className="absolute bottom-3 left-3 rounded-md border px-3 py-1.5 text-xs font-medium"
      style={{ background: 'var(--surface-1)', borderColor: 'var(--baseline)' }}
      onClick={() => {
        const layout = layoutRef.current
        if (!layout) return
        if (layout.isRunning()) {
          layout.stop()
          setRunning(false)
        } else {
          layout.start()
          setRunning(true)
        }
      }}
    >
      {running ? '⏸ Pause layout' : '▶ Resume layout'}
    </button>
  )
}

function NodePanel({
  node,
  color,
  onClear,
}: {
  node: NetworkNode
  color: string
  onClear: () => void
}) {
  const statKeys = Object.keys(node).filter(
    (k) => !['id', 'community', 'x', 'y'].includes(k) && node[k] !== null,
  )
  return (
    <div data-testid="node-panel">
      <div className="mb-3 flex items-center justify-between">
        <h3 className="font-semibold">Account</h3>
        <button className="text-xs" style={{ color: 'var(--text-muted)' }} onClick={onClear}>
          ✕ close
        </button>
      </div>
      <div className="mb-3 flex items-center gap-2">
        <span
          aria-hidden
          className="inline-block h-3 w-3 rounded-full"
          style={{ background: color }}
        />
        <code className="break-all text-xs">{node.id}</code>
      </div>
      <dl className="grid gap-2">
        {statKeys.map((k) => (
          <div key={k} className="flex justify-between gap-3 text-xs">
            <dt style={{ color: 'var(--text-secondary)' }}>{k.replaceAll('_', ' ')}</dt>
            <dd className="tabular font-medium">{formatStat(node[k])}</dd>
          </div>
        ))}
      </dl>
      <p className="mt-4 text-xs" style={{ color: 'var(--text-muted)' }}>
        Community {node.community}
      </p>
    </div>
  )
}

function formatStat(v: unknown): string {
  if (typeof v === 'number') {
    return Number.isInteger(v) ? v.toLocaleString() : v.toFixed(3)
  }
  return String(v)
}

function CommunityLegend({
  sizes,
  colors,
  focus,
  onFocus,
}: {
  sizes: Map<number, number>
  colors: Map<number, string>
  focus: number | null
  onFocus: (c: number) => void
}) {
  const ranked = [...sizes.entries()].sort((a, b) => b[1] - a[1])
  const top = ranked.slice(0, 8)
  const rest = ranked.slice(8)
  return (
    <div>
      <h3 className="mb-1 font-semibold">Communities</h3>
      <p className="mb-3 text-xs" style={{ color: 'var(--text-muted)' }}>
        Louvain clusters, sized by member count. Click to isolate; click a node for
        account stats.
      </p>
      <ul className="grid gap-1.5">
        {top.map(([c, n]) => (
          <li key={c}>
            <button
              className="flex w-full items-center gap-2 rounded px-2 py-1 text-left text-xs"
              style={focus === c ? { background: 'var(--grid)' } : {}}
              onClick={() => onFocus(c)}
            >
              <span
                aria-hidden
                className="inline-block h-3 w-3 rounded-full"
                style={{ background: colors.get(c) }}
              />
              <span className="flex-1">Community {c}</span>
              <span className="tabular" style={{ color: 'var(--text-secondary)' }}>
                {n}
              </span>
            </button>
          </li>
        ))}
        {rest.length > 0 && (
          <li className="flex items-center gap-2 px-2 py-1 text-xs">
            <span
              aria-hidden
              className="inline-block h-3 w-3 rounded-full"
              style={{ background: OTHER_COLOR }}
            />
            <span className="flex-1" style={{ color: 'var(--text-secondary)' }}>
              {rest.length} smaller communities
            </span>
            <span className="tabular" style={{ color: 'var(--text-secondary)' }}>
              {rest.reduce((a, [, n]) => a + n, 0)}
            </span>
          </li>
        )}
      </ul>
    </div>
  )
}
