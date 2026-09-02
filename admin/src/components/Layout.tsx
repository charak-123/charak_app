import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import { clearToken } from '@/lib/auth'
import { cn } from '@/lib/utils'
import {
  ShieldCheck, BookOpen, MessageSquare, Users, ClipboardList, LogOut
} from 'lucide-react'

const NAV = [
  { to: '/',              icon: ShieldCheck,   label: 'Verification' },
  { to: '/bookings',      icon: BookOpen,      label: 'Bookings' },
  { to: '/complaints',    icon: MessageSquare, label: 'Complaints' },
  { to: '/directory',     icon: Users,         label: 'Directory' },
  { to: '/senior-review', icon: ClipboardList, label: 'Senior Review' },
]

export default function Layout() {
  const navigate = useNavigate()
  function logout() { clearToken(); navigate('/login') }

  return (
    <div className="flex min-h-screen">
      <aside className="w-56 bg-ink text-white flex flex-col shrink-0">
        <div className="px-5 py-6 text-lg font-semibold tracking-tight">
          charak <span className="text-primary text-sm font-normal">admin</span>
        </div>
        <nav className="flex-1 px-2 space-y-0.5">
          {NAV.map(({ to, icon: Icon, label }) => (
            <NavLink
              key={to}
              to={to}
              end={to === '/'}
              className={({ isActive }) =>
                cn('flex items-center gap-3 px-3 py-2 rounded-btn text-sm transition-colors',
                  isActive ? 'bg-primary text-white' : 'text-white/60 hover:text-white hover:bg-white/10')
              }
            >
              <Icon size={16} />
              {label}
            </NavLink>
          ))}
        </nav>
        <button
          onClick={logout}
          className="flex items-center gap-3 px-5 py-4 text-sm text-white/50 hover:text-white transition-colors"
        >
          <LogOut size={16} /> Logout
        </button>
      </aside>
      <main className="flex-1 overflow-auto">
        <Outlet />
      </main>
    </div>
  )
}
