export default function AboutPage() {
  return (
    <div className="mx-auto max-w-2xl px-6 py-10 text-sm leading-6">
      <h1 className="mb-4 text-2xl font-semibold">About</h1>
      <p className="mb-4" style={{ color: 'var(--text-secondary)' }}>
        This tool detects <strong>coordinated behavior</strong> on social media using the{' '}
        <a href="https://cran.r-project.org/package=CooRTweet" style={{ color: 'var(--accent)' }}>
          CooRTweet
        </a>{' '}
        R package (Righetti &amp; Balluff, 2025) — the published, validated implementation,
        not a reimplementation. Accounts that repeatedly share the same objects (retweets,
        URLs, hashtags…) within a short time window form a weighted coordination network.
      </p>
      <h2 className="mb-2 mt-6 font-semibold">Method</h2>
      <ol className="mb-4 list-decimal pl-5" style={{ color: 'var(--text-secondary)' }}>
        <li>
          <code>detect_groups</code> — find pairs of accounts sharing the same object within
          the time window
        </li>
        <li>
          <code>generate_coordinated_network</code> — build a weighted network; edges above
          an edge-weight percentile are flagged as coordinated
        </li>
        <li>
          <code>account_stats</code> — per-account participation statistics
        </li>
      </ol>
      <h2 className="mb-2 mt-6 font-semibold">Papers</h2>
      <ul className="mb-4 list-disc pl-5" style={{ color: 'var(--text-secondary)' }}>
        <li>
          Giglietto, Righetti, Rossi &amp; Marino (2020). It takes a village to manipulate
          the media. <em>Information, Communication &amp; Society</em>.
        </li>
        <li>
          Giglietto, Marino, Mincigrucci &amp; Stanziano (2023). A workflow to detect,
          monitor, and update lists of coordinated social media accounts across time.{' '}
          <em>Social Media + Society</em>.
        </li>
        <li>
          Righetti &amp; Balluff (2025). CooRTweet: A Generalized R Software for Coordinated
          Network Detection. <em>Computational Communication Research</em>.
        </li>
      </ul>
      <h2 className="mb-2 mt-6 font-semibold">Data retention</h2>
      <p style={{ color: 'var(--text-secondary)' }}>
        Uploaded datasets and results are automatically deleted after 72 hours. Result URLs
        are unguessable but not password-protected — treat them as private links.
      </p>
    </div>
  )
}
