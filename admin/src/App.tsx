import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { isAuthed } from '@/lib/auth'
import Layout from '@/components/Layout'
import Login from '@/pages/Login'
import VerificationQueue from '@/pages/VerificationQueue'
import BookingsMonitor from '@/pages/BookingsMonitor'
import ComplaintInbox from '@/pages/ComplaintInbox'
import DirectoryOversight from '@/pages/DirectoryOversight'
import SeniorReviewQueue from '@/pages/SeniorReviewQueue'

function Guard({ children }: { children: React.ReactNode }) {
  return isAuthed() ? <>{children}</> : <Navigate to="/login" replace />
}

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route element={<Guard><Layout /></Guard>}>
          <Route index element={<VerificationQueue />} />
          <Route path="bookings"      element={<BookingsMonitor />} />
          <Route path="complaints"    element={<ComplaintInbox />} />
          <Route path="directory"     element={<DirectoryOversight />} />
          <Route path="senior-review" element={<SeniorReviewQueue />} />
        </Route>
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  )
}
