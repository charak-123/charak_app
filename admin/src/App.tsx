import { Suspense, lazy } from 'react'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { isAuthed } from '@/lib/auth'
import Layout from '@/components/Layout'
import Login from '@/pages/Login'

// Route components are code-split: each page ships as its own chunk and loads on
// navigation, so the initial bundle is the shell + login rather than every screen.
const Overview          = lazy(() => import('@/pages/Overview'))
const VerificationQueue = lazy(() => import('@/pages/VerificationQueue'))
const BookingsMonitor   = lazy(() => import('@/pages/BookingsMonitor'))
const ComplaintInbox    = lazy(() => import('@/pages/ComplaintInbox'))
const DirectoryOversight = lazy(() => import('@/pages/DirectoryOversight'))
const SeniorReviewQueue = lazy(() => import('@/pages/SeniorReviewQueue'))
const DeletionRequests  = lazy(() => import('@/pages/DeletionRequests'))
const Refunds           = lazy(() => import('@/pages/Refunds'))
const Visits            = lazy(() => import('@/pages/Visits'))

function Guard({ children }: { children: React.ReactNode }) {
  return isAuthed() ? <>{children}</> : <Navigate to="/login" replace />
}

export default function App() {
  return (
    // Served at charak.care/admin — see vite.config.ts's `base` for why.
    <BrowserRouter basename="/admin">
      <Suspense fallback={<div className="p-8 text-sm text-muted-foreground">Loading…</div>}>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route element={<Guard><Layout /></Guard>}>
            <Route index element={<Overview />} />
            <Route path="verification" element={<VerificationQueue />} />
            <Route path="bookings"      element={<BookingsMonitor />} />
            <Route path="complaints"    element={<ComplaintInbox />} />
            <Route path="visits"        element={<Visits />} />
            <Route path="refunds"       element={<Refunds />} />
            <Route path="directory"     element={<DirectoryOversight />} />
            <Route path="senior-review" element={<SeniorReviewQueue />} />
            <Route path="deletion-requests" element={<DeletionRequests />} />
          </Route>
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </Suspense>
    </BrowserRouter>
  )
}
