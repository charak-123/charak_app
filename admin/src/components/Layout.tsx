import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import { clearToken } from '@/lib/auth'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Toaster } from '@/components/ui/sonner'
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
    <div className="flex h-screen overflow-hidden">
      <aside className="w-56 bg-sidebar text-sidebar-foreground flex flex-col border-r border-sidebar-border shrink-0">
        <div className="px-5 py-5 text-lg font-semibold border-b border-sidebar-border">
          charak <span className="text-primary text-sm font-normal">admin</span>
        </div>
        <nav className="flex-1 px-2 py-2 space-y-0.5">
          {NAV.map(({ to, icon: Icon, label }) => (
            <NavLink
              key={to}
              to={to}
              end={to === '/'}
              className={({ isActive }) =>
                cn(
                  'flex items-center gap-3 px-3 py-2 text-sm transition-colors',
                  isActive
                    ? 'bg-sidebar-primary text-sidebar-primary-foreground rounded-md'
                    : 'text-sidebar-foreground/60 hover:text-sidebar-foreground hover:bg-sidebar-accent rounded-md'
                )
              }
            >
              <Icon size={16} />
              {label}
            </NavLink>
          ))}
        </nav>
        <div className="px-2 py-2 border-t border-sidebar-border">
          <Button
            variant="ghost"
            onClick={logout}
            className="text-sidebar-foreground/50 hover:text-sidebar-foreground w-full justify-start gap-3"
          >
            <LogOut size={16} /> Logout
          </Button>
        </div>
      </aside>
      <main className="flex-1 overflow-auto bg-muted/30">
        <Outlet />
      </main>
      <Toaster />
    </div>
  )
}
