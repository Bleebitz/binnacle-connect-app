import { useState } from 'react'
import Navbar from './components/Navbar.jsx'
import Home from './pages/Home.jsx'
import Dashboard from './pages/Dashboard.jsx'

export default function App() {
  const [page, setPage] = useState('home')
  return (
    <div className="app">
      <Navbar page={page} setPage={setPage} />
      {page === 'home' ? <Home /> : <Dashboard />}
    </div>
  )
}
