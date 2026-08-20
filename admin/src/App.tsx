import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import VerificationQueue from './pages/VerificationQueue'
import BookingsMonitor from './pages/BookingsMonitor'
import ComplaintInbox from './pages/ComplaintInbox'
import DirectoryOversight from './pages/DirectoryOversight'
import SeniorReviewQueue from './pages/SeniorReviewQueue'

export default function App() {
  return (
    <BrowserRouter>
      <div style={{ display: 'flex', minHeight: '100vh', fontFamily: 'system-ui, sans-serif' }}>
        <nav style={{ width: 220, background: '#101828', color: '#fff', padding: '24px 0' }}>
          <div style={{ padding: '0 20px 24px', fontSize: 18, fontWeight: 600 }}>charak admin</div>
          {[
            ['/', 'Verification Queue'],
            ['/bookings', 'Bookings Monitor'],
            ['/complaints', 'Complaints'],
            ['/directory', 'Directory'],
            ['/senior-review', 'Senior Review'],
          ].map(([path, label]) => (
            <a key={path} href={path} style={{
              display: 'block', padding: '10px 20px', color: '#9CA3AF',
              textDecoration: 'none', fontSize: 14,
            }}>{label}</a>
          ))}
        </nav>
        <main style={{ flex: 1, padding: 32 }}>
          <Routes>
            <Route path="/"              element={<VerificationQueue />} />
            <Route path="/bookings"      element={<BookingsMonitor />} />
            <Route path="/complaints"    element={<ComplaintInbox />} />
            <Route path="/directory"     element={<DirectoryOversight />} />
            <Route path="/senior-review" element={<SeniorReviewQueue />} />
            <Route path="*"              element={<Navigate to="/" />} />
          </Routes>
        </main>
      </div>
    </BrowserRouter>
  )
}
