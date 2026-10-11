import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import './index.css'
import App from './App.tsx'

// Ops needs to see a new verification request, booking, or complaint land
// without manually reloading the tab. 15s matches the cadence the doctor
// apps already poll at (CharakPoller) — frequent enough to feel live, not so
// frequent it's a meaningful load on the backend for a handful of ops users.
// Pauses automatically while the tab isn't focused (react-query's default),
// so it doesn't poll a backgrounded browser tab forever.
const qc = new QueryClient({
  defaultOptions: {
    queries: {
      refetchInterval: 15_000,
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
