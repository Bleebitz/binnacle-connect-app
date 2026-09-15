export default function Navbar({ page, setPage }) {
  return (
    <div className="navbar">
      <div className="brand">CONNECT</div>
      <div className="nav-links">
        <button className={page === 'home' ? 'active' : ''} onClick={() => setPage('home')}>
          Home
        </button>
        <button className={page === 'dashboard' ? 'active' : ''} onClick={() => setPage('dashboard')}>
          Fleet Dashboard
        </button>
      </div>
    </div>
  )
}
