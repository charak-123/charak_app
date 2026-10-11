import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

/**
 * Up to two initials for an avatar fallback. A doctor row can have `name:
 * null` — a Google sign-in creates the account before the profile-setup step
 * that collects a name, and that row shows up in admin (pending verification,
 * the directory) before it's ever completed. Falls back to "?" rather than
 * throwing on .split() of null, which crashed both VerificationQueue and
 * DirectoryOversight (they each had their own unguarded copy of this).
 */
export function getInitials(name: string | null | undefined): string {
  if (!name) return '?'
  const initials = name.trim().split(/\s+/).map(w => w[0]).slice(0, 2).join('')
  return initials ? initials.toUpperCase() : '?'
}
