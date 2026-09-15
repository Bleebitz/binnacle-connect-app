const FEATURES = [
  {
    title: 'Live view, no operator',
    desc: 'Track frames the rider automatically — nobody holds a camera.',
  },
  {
    title: 'Signed clips',
    desc: 'Every highlight is signed on Vision at capture, with GPS attached.',
  },
  {
    title: 'King of Wake',
    desc: 'Speed-classed wake and ramp leaderboards, verified vs. unverified.',
  },
  {
    title: 'Fall & MOB alerting',
    desc: 'Always on. Assistive, not a substitute for a lookout.',
  },
  {
    title: 'Crew, not friends',
    desc: 'Sessions and clips organize around who actually rode together.',
  },
  {
    title: 'Consent-first sharing',
    desc: 'Public uploads require an explicit consent step before they post.',
  },
]

export default function FeatureGrid() {
  return (
    <div className="feature-grid">
      {FEATURES.map((f) => (
        <div className="feature-card" key={f.title}>
          <h3>{f.title}</h3>
          <p>{f.desc}</p>
        </div>
      ))}
    </div>
  )
}
