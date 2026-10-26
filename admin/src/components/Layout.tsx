import { useEffect, useState } from 'react'
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { clearToken } from '@/lib/auth'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Toaster } from '@/components/ui/sonner'
import {
  LayoutDashboard, ShieldCheck, BookOpen, MessageSquare, Users, ClipboardList, LogOut, UserX, Menu, X, Undo2, Stethoscope, Star, ShieldAlert } from 'lucide-react'

const NAV = [
  { to: '/',              icon: LayoutDashboard, label: 'Overview' },
  { to: '/verification',  icon: ShieldCheck,   label: 'Verification' },
  { to: '/bookings',      icon: BookOpen,      label: 'Bookings' },
  { to: '/complaints',    icon: MessageSquare, label: 'Complaints' },
  { to: '/visits',        icon: Stethoscope,   label: 'Visits' },
  { to: '/incidents',     icon: ShieldAlert,   label: 'Incidents' },
  { to: '/reviews',       icon: Star,          label: 'Reviews' },
  { to: '/refunds',       icon: Undo2,         label: 'Refunds' },
  { to: '/directory',     icon: Users,         label: 'Directory' },
  { to: '/senior-review', icon: ClipboardList, label: 'Senior Review' },
  { to: '/deletion-requests', icon: UserX, label: 'Deletion Requests' },
]

function Wordmark() {
  return (
    <div className="flex items-baseline gap-2">
      {/* Wordmark: CHARAK wide + चरक in Chandan (design-system/README.md § Brand) */}
      <span className="text-lg font-extrabold tracking-wide" style={{ fontStretch: '125%' }}>CHARAK</span>
      <span className="text-lg font-bold text-chandan-300" style={{ fontFamily: '"Anek Devanagari"' }}>चरक</span>
      <span className="text-xs font-medium text-sidebar-foreground/60 ml-1">admin</span>
    </div>
  )
}

/** Nav + logout. The same list renders as the desktop sidebar and the phone drawer. */
function NavPanel({ onNavigate, onLogout }: { onNavigate?: () => void; onLogout: () => void }) {
  return (
    <>
      <nav className="flex-1 overflow-y-auto px-2 py-2 space-y-0.5">
        {NAV.map(({ to, icon: Icon, label }) => (
          <NavLink
            key={to}
            to={to}
            end={to === '/'}
            onClick={onNavigate}
            className={({ isActive }) =>
              cn(
                // 44px rows on phones so every item is a comfortable tap target.
                'flex items-center gap-3 px-3 py-3 md:py-2 text-sm transition-colors',
                isActive
                  ? 'bg-sidebar-primary text-sidebar-primary-foreground rounded-full'
                  : 'text-sidebar-foreground/60 hover:text-sidebar-foreground hover:bg-sidebar-accent rounded-full'
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
          onClick={onLogout}
          className="text-sidebar-foreground/50 hover:text-sidebar-foreground w-full justify-start gap-3"
        >
          <LogOut size={16} /> Logout
        </Button>
      </div>
    </>
  )
}

export default function Layout() {
  const navigate = useNavigate()
  const { pathname } = useLocation()
  const [menuOpen, setMenuOpen] = useState(false)
  function logout() { clearToken(); navigate('/login') }

  // Close the drawer on Escape, and keep the page behind it from scrolling.
  useEffect(() => {
    if (!menuOpen) return
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') setMenuOpen(false) }
    document.addEventListener('keydown', onKey)
    document.body.style.overflow = 'hidden'
    return () => {
      document.removeEventListener('keydown', onKey)
      document.body.style.overflow = ''
    }
  }, [menuOpen])

  const current = NAV.find(n => (n.to === '/' ? pathname === '/' : pathname.startsWith(n.to)))

  return (
    <div className="flex h-dvh flex-col overflow-hidden md:flex-row">
      {/* Desktop: fixed sidebar. */}
      <aside className="hidden w-56 bg-sidebar text-sidebar-foreground md:flex flex-col border-r border-sidebar-border shrink-0">
        <div className="px-5 py-5 border-b border-sidebar-border">
          <Wordmark />
        </div>
        <NavPanel onLogout={logout} />
      </aside>

      {/* Phone: top bar with the current section and a menu button. */}
      <header className="flex h-14 shrink-0 items-center justify-between gap-3 border-b border-sidebar-border bg-sidebar px-4 text-sidebar-foreground md:hidden">
        <Wordmark />
        <div className="flex min-w-0 items-center gap-1">
          {current && <span className="truncate text-sm text-sidebar-foreground/70">{current.label}</span>}
          <Button
            variant="ghost"
            size="icon"
            aria-label="Open menu"
            aria-expanded={menuOpen}
            onClick={() => setMenuOpen(true)}
            className="h-11 w-11 text-sidebar-foreground hover:bg-sidebar-accent"
          >
            <Menu size={20} />
          </Button>
        </div>
      </header>

      {/* Phone: slide-in drawer. */}
      <div
        className={cn('fixed inset-0 z-40 md:hidden', menuOpen ? 'pointer-events-auto' : 'pointer-events-none')}
        aria-hidden={!menuOpen}
      >
        <div
          className={cn('absolute inset-0 bg-black/40 transition-opacity duration-300', menuOpen ? 'opacity-100' : 'opacity-0')}
          onClick={() => setMenuOpen(false)}
        />
        <aside
          role="dialog"
          aria-modal="true"
          aria-label="Navigation"
          className={cn(
            'absolute inset-y-0 left-0 flex w-72 max-w-[85vw] flex-col bg-sidebar text-sidebar-foreground',
            'transition-transform duration-300 ease-out motion-reduce:transition-none',
            menuOpen ? 'translate-x-0' : '-translate-x-full',
          )}
        >
          <div className="flex h-14 items-center justify-between border-b border-sidebar-border px-4">
            <Wordmark />
            <Button
              variant="ghost"
              size="icon"
              aria-label="Close menu"
              onClick={() => setMenuOpen(false)}
              className="h-11 w-11 text-sidebar-foreground hover:bg-sidebar-accent"
            >
              <X size={20} />
            </Button>
          </div>
          <NavPanel onNavigate={() => setMenuOpen(false)} onLogout={logout} />
        </aside>
      </div>

      <main className="min-h-0 flex-1 overflow-auto bg-muted/30">
        <Outlet />
      </main>
      <Toaster />
    </div>
  )
}
