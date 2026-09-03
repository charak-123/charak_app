/** @type {import('tailwindcss').Config} */
export default {
  darkMode: ['class'],
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        // shadcn CSS-var tokens
        background:  'oklch(var(--background) / <alpha-value>)',
        foreground:  'oklch(var(--foreground) / <alpha-value>)',
        primary: {
          DEFAULT:    'oklch(var(--primary) / <alpha-value>)',
          foreground: 'oklch(var(--primary-foreground) / <alpha-value>)',
          soft:       '#EAF1FE',
          deep:       '#1E4FBF',
        },
        secondary: {
          DEFAULT:    'oklch(var(--secondary) / <alpha-value>)',
          foreground: 'oklch(var(--secondary-foreground) / <alpha-value>)',
        },
        muted: {
          DEFAULT:    'oklch(var(--muted) / <alpha-value>)',
          foreground: 'oklch(var(--muted-foreground) / <alpha-value>)',
        },
        accent: {
          DEFAULT:    'oklch(var(--accent) / <alpha-value>)',
          foreground: 'oklch(var(--accent-foreground) / <alpha-value>)',
        },
        destructive: {
          DEFAULT:    'oklch(var(--destructive) / <alpha-value>)',
          foreground: 'oklch(var(--destructive-foreground) / <alpha-value>)',
        },
        card: {
          DEFAULT:    'oklch(var(--card) / <alpha-value>)',
          foreground: 'oklch(var(--card-foreground) / <alpha-value>)',
        },
        popover: {
          DEFAULT:    'oklch(var(--popover) / <alpha-value>)',
          foreground: 'oklch(var(--popover-foreground) / <alpha-value>)',
        },
        border: 'oklch(var(--border) / <alpha-value>)',
        input:  'oklch(var(--input) / <alpha-value>)',
        ring:   'oklch(var(--ring) / <alpha-value>)',
        sidebar: {
          DEFAULT:            'oklch(var(--sidebar) / <alpha-value>)',
          foreground:         'oklch(var(--sidebar-foreground) / <alpha-value>)',
          primary:            'oklch(var(--sidebar-primary) / <alpha-value>)',
          'primary-foreground':'oklch(var(--sidebar-primary-foreground) / <alpha-value>)',
          accent:             'oklch(var(--sidebar-accent) / <alpha-value>)',
          'accent-foreground':'oklch(var(--sidebar-accent-foreground) / <alpha-value>)',
          border:             'oklch(var(--sidebar-border) / <alpha-value>)',
          ring:               'oklch(var(--sidebar-ring) / <alpha-value>)',
        },
        // Semantic extras
        success: '#1FAA6D',
        warning: '#E0930B',
        danger:  '#E0473E',
        ink: { DEFAULT: '#101828', muted: '#5B6472' },
      },
      fontFamily: { sans: ['Inter', 'system-ui', 'sans-serif'] },
      borderRadius: {
        lg:   'var(--radius)',
        md:   'calc(var(--radius) - 2px)',
        sm:   'calc(var(--radius) - 4px)',
        card: '12px',
        btn:  '10px',
        pill: '100px',
      },
    },
  },
  plugins: [],
}
