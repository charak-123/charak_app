import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import './index.css'
import App from './App.tsx'

// No polling by default. Every query used to re-fetch every 15 seconds, so
// each open tab kept a stream of requests going (plus their preflights) for
// data nobody was looking at changing, and that competed with the requests
// someone was waiting on. Now data is fresh for 30 seconds (moving between
// pages doesn't re-fetch) and refreshes when the tab regains focus. The
// queues where new work lands (verification, incidents, complaints,
// bookings, the overview) poll once a minute on their own.
const qc = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      refetchOnWindowFocus: true,
      retry: 1,
    },
  },
})
createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={qc}>
      <App />
    </QueryClientProvider>
  </StrictMode>
)
