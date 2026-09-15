import { useEffect, useState } from 'react'

// MOCK DATA — a real build wires this to the Core's cloud API. Connect never
// talks to sensors or Switch directly (Connectivity Architecture §2); this
// dashboard would consume aggregated status the Core reports, not raw
// telemetry. Nothing here should be read as a live fleet.
const MOCK_FLEET = [
  { id: 'vision-0001', label: "Levi's boat", status: 'simulated', temp: '31°C', lastSeen: 'now' },
  { id: 'vision-0002', label: 'Demo unit', status: 'offline', temp: '—', lastSeen: '3d ago' },
]

function Pill({ status }) {
  const cls = status === 'simulated' ? 'sim' : status === 'offline' ? 'warn' : 'ok'
  return <span className={`pill ${cls}`}>{status.toUpperCase()}</span>
}

export default function Dashboard() {
  const [fleet, setFleet] = useState(MOCK_FLEET)

  useEffect(() => {
    // TODO(backend): replace with a real fetch to the Core's fleet-status
    // endpoint once one exists. Left as a no-op interval so the loading
    // pattern is in place without fabricating a fake live connection.
  }, [])

  return (
    <div className="dashboard">
      <h2>Fleet status</h2>
      <p style={{ color: 'var(--slate)', fontSize: 13.5 }}>
        Mock data — no Core backend exists yet to source this from.
      </p>
      <table className="status-table">
        <thead>
          <tr>
            <th>Device</th>
            <th>Status</th>
            <th>Temp</th>
            <th>Last seen</th>
          </tr>
        </thead>
        <tbody>
          {fleet.map((f) => (
            <tr key={f.id}>
              <td>{f.label}</td>
              <td><Pill status={f.status} /></td>
              <td>{f.temp}</td>
              <td>{f.lastSeen}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
