import { useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { QRCodeSVG } from 'qrcode.react'
import { setToken } from '@/lib/auth'
import { api, ApiStepError } from '@/lib/api'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

type Step =
  | { kind: 'credentials' }
  | { kind: 'totp' }                              // already enrolled — just needs the code
  | { kind: 'totp_setup'; provisioningUri: string } // first login — scan, then enter the code

export default function Login() {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [code, setCode] = useState('')
  const [step, setStep] = useState<Step>({ kind: 'credentials' })
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  async function attempt(totpCode?: string) {
    setError('')
    setLoading(true)
    try {
      const body: Record<string, string> = { email: email.trim().toLowerCase(), password }
      if (totpCode) body.totp_code = totpCode
      const { token } = await api.post<{ token: string }>('/admin/login', body)
      setToken(token)
      queryClient.clear()
      navigate('/', { replace: true })
    } catch (err: unknown) {
      if (err instanceof ApiStepError) {
        setStep(
          err.next === 'totp_setup' && err.provisioningUri
            ? { kind: 'totp_setup', provisioningUri: err.provisioningUri }
            : { kind: 'totp' }
        )
      } else {
        setError(err instanceof Error ? err.message : 'Sign-in failed')
      }
    } finally {
      setLoading(false)
    }
  }

  function handleCredentials(e: React.FormEvent) {
    e.preventDefault()
    attempt()
  }

  function handleCode(e: React.FormEvent) {
    e.preventDefault()
    attempt(code)
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-muted/30 px-4">
      <Card className="w-full max-w-[380px]">
        <CardHeader>
          <CardTitle className="flex items-baseline gap-2">
            <span className="text-2xl font-extrabold tracking-wide" style={{ fontStretch: '125%' }}>CHARAK</span>
            <span className="text-2xl font-bold text-chandan" style={{ fontFamily: '"Anek Devanagari"' }}>चरक</span>
            <span className="text-sm font-medium text-muted-foreground">admin</span>
          </CardTitle>
          <p className="text-sm text-muted-foreground">
            {step.kind === 'credentials' && 'Sign in to continue'}
            {step.kind === 'totp' && 'Enter your two-factor code'}
            {step.kind === 'totp_setup' && 'Set up two-factor authentication'}
          </p>
        </CardHeader>
        <CardContent>
          {step.kind === 'credentials' && (
            <form onSubmit={handleCredentials} className="space-y-4">
              <div className="space-y-1.5">
                <label className="text-sm font-medium text-foreground">Email</label>
                <Input
                  type="email"
                  value={email}
                  onChange={e => setEmail(e.target.value)}
                  required
                  autoFocus
                  autoComplete="username"
                />
              </div>
              <div className="space-y-1.5">
                <label className="text-sm font-medium text-foreground">Password</label>
                <Input
                  type="password"
                  value={password}
                  onChange={e => setPassword(e.target.value)}
                  required
                  autoComplete="current-password"
                />
              </div>
              {error && <p className="text-sm text-destructive">{error}</p>}
              <Button type="submit" className="w-full" disabled={loading}>
                {loading ? 'Checking…' : 'Continue'}
              </Button>
            </form>
          )}

          {(step.kind === 'totp' || step.kind === 'totp_setup') && (
            <form onSubmit={handleCode} className="space-y-4">
              {step.kind === 'totp_setup' && (
                <div className="space-y-2">
                  <p className="text-sm text-muted-foreground">
                    Scan this with an authenticator app (Google Authenticator, Authy, 1Password…),
                    then enter the 6-digit code it shows.
                  </p>
                  <div className="flex justify-center rounded-md border bg-white p-4">
                    <QRCodeSVG value={step.provisioningUri} size={180} />
                  </div>
                </div>
              )}
              <div className="space-y-1.5">
                <label className="text-sm font-medium text-foreground">6-digit code</label>
                <Input
                  type="text"
                  inputMode="numeric"
                  pattern="[0-9]*"
                  maxLength={6}
                  value={code}
                  onChange={e => setCode(e.target.value.replace(/\D/g, ''))}
                  required
                  autoFocus
                  autoComplete="one-time-code"
                />
              </div>
              {error && <p className="text-sm text-destructive">{error}</p>}
              <Button type="submit" className="w-full" disabled={loading || code.length !== 6}>
                {loading ? 'Verifying…' : 'Verify'}
              </Button>
              <button
                type="button"
                className="w-full text-xs text-muted-foreground hover:text-foreground"
                onClick={() => { setStep({ kind: 'credentials' }); setCode(''); setError('') }}
              >
                Back
              </button>
            </form>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
