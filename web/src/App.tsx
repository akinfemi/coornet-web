import { Link, NavLink, Outlet } from 'react-router-dom'

export default function App() {
  return (
    <div className="flex h-full flex-col">
      <header
        className="flex items-center gap-6 border-b px-6 py-3"
        style={{ borderColor: 'var(--border)', background: 'var(--surface-1)' }}
      >
        <Link to="/" className="text-lg font-semibold tracking-tight">
          CooRTweet <span style={{ color: 'var(--accent)' }}>Web</span>
        </Link>
        <nav className="flex gap-4 text-sm" style={{ color: 'var(--text-secondary)' }}>
          <NavLink
            to="/"
            className={({ isActive }) => (isActive ? 'font-semibold' : '')}
            style={({ isActive }) => (isActive ? { color: 'var(--text-primary)' } : {})}
          >
            New analysis
          </NavLink>
          <NavLink
            to="/walkthrough"
            className={({ isActive }) => (isActive ? 'font-semibold' : '')}
            style={({ isActive }) => (isActive ? { color: 'var(--text-primary)' } : {})}
          >
            Walkthrough
          </NavLink>
          <NavLink
            to="/about"
            className={({ isActive }) => (isActive ? 'font-semibold' : '')}
            style={({ isActive }) => (isActive ? { color: 'var(--text-primary)' } : {})}
          >
            About
          </NavLink>
        </nav>
        <div className="ml-auto text-xs" style={{ color: 'var(--text-muted)' }}>
          Coordinated behavior detection · uploads auto-delete after 72h
        </div>
      </header>
      <main className="min-h-0 flex-1 overflow-auto">
        <Outlet />
      </main>
    </div>
  )
}
