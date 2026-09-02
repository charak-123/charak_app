import { cn } from '@/lib/utils'
import { InputHTMLAttributes } from 'react'
export function Input({ className, ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      {...props}
      className={cn('w-full rounded-btn border border-border bg-bg-subtle px-3 py-2 text-sm text-ink placeholder:text-ink-muted focus:outline-none focus:ring-2 focus:ring-primary focus:border-primary', className)}
    />
  )
}
