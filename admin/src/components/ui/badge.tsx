import { cn } from '@/lib/utils'

type Variant = 'default' | 'success' | 'warning' | 'danger' | 'muted'
const styles: Record<Variant, string> = {
  default: 'bg-primary-soft text-primary',
  success: 'bg-green-50 text-success',
  warning: 'bg-yellow-50 text-warning',
  danger:  'bg-red-50 text-danger',
  muted:   'bg-bg-subtle text-ink-muted',
}
export function Badge({ label, variant = 'default' }: { label: string; variant?: Variant }) {
  return (
    <span className={cn('inline-flex items-center px-2 py-0.5 rounded-pill text-xs font-medium', styles[variant])}>
      {label}
    </span>
  )
}
