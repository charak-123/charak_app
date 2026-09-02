import { cn } from '@/lib/utils'
import { ButtonHTMLAttributes } from 'react'

type Variant = 'default' | 'outline' | 'ghost' | 'danger'
const base = 'inline-flex items-center justify-center gap-2 rounded-btn px-4 py-2 text-sm font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed'
const variants: Record<Variant, string> = {
  default: 'bg-primary text-white hover:bg-primary-deep',
  outline: 'border border-primary text-primary hover:bg-primary-soft',
  ghost:   'text-ink-muted hover:bg-bg-subtle',
  danger:  'bg-danger text-white hover:opacity-90',
}
export function Button({ variant = 'default', className, ...props }: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant }) {
  return <button {...props} className={cn(base, variants[variant], className)} />
}
