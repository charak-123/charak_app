/** @type {import('tailwindcss').Config} */
export default {
  darkMode: ['class'],
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        // shadcn CSS-var tokens
        background:  'rgb(var(--background) / <alpha-value>)',
        foreground:  'rgb(var(--foreground) / <alpha-value>)',
        primary: {
          DEFAULT:    'rgb(var(--primary) / <alpha-value>)',
          foreground: 'rgb(var(--primary-foreground) / <alpha-value>)',
          soft:       'rgb(var(--rgb-primary-soft) / <alpha-value>)',
          deep:       'rgb(var(--rgb-on-primary-soft) / <alpha-value>)',
        },
        secondary: {
          DEFAULT:    'rgb(var(--secondary) / <alpha-value>)',
          foreground: 'rgb(var(--secondary-foreground) / <alpha-value>)',
        },
        muted: {
          DEFAULT:    'rgb(var(--muted) / <alpha-value>)',
          foreground: 'rgb(var(--muted-foreground) / <alpha-value>)',
        },
        accent: {
          DEFAULT:    'rgb(var(--accent) / <alpha-value>)',
          foreground: 'rgb(var(--accent-foreground) / <alpha-value>)',
        },
        destructive: {
          DEFAULT:    'rgb(var(--destructive) / <alpha-value>)',
          foreground: 'rgb(var(--destructive-foreground) / <alpha-value>)',
        },
        card: {
          DEFAULT:    'rgb(var(--card) / <alpha-value>)',
          foreground: 'rgb(var(--card-foreground) / <alpha-value>)',
        },
        popover: {
          DEFAULT:    'rgb(var(--popover) / <alpha-value>)',
          foreground: 'rgb(var(--popover-foreground) / <alpha-value>)',
        },
        border: 'rgb(var(--border) / <alpha-value>)',
        input:  'rgb(var(--input) / <alpha-value>)',
        ring:   'rgb(var(--ring) / <alpha-value>)',
        sidebar: {
          DEFAULT:            'rgb(var(--sidebar) / <alpha-value>)',
          foreground:         'rgb(var(--sidebar-foreground) / <alpha-value>)',
          primary:            'rgb(var(--sidebar-primary) / <alpha-value>)',
          'primary-foreground':'rgb(var(--sidebar-primary-foreground) / <alpha-value>)',
          accent:             'rgb(var(--sidebar-accent) / <alpha-value>)',
          'accent-foreground':'rgb(var(--sidebar-accent-foreground) / <alpha-value>)',
          border:             'rgb(var(--sidebar-border) / <alpha-value>)',
          ring:               'rgb(var(--sidebar-ring) / <alpha-value>)',
        },
        // CHARAK V2 semantic extras (values: src/styles/charak-tokens.css,
        // generated from design-system/tokens.json)
        success: 'rgb(var(--rgb-success) / <alpha-value>)',
        warning: 'rgb(var(--rgb-warning) / <alpha-value>)',
        danger:  'rgb(var(--rgb-danger) / <alpha-value>)',
        ground:  'rgb(var(--rgb-ground) / <alpha-value>)',
        chandan: {
          DEFAULT: 'rgb(var(--rgb-accent-warm) / <alpha-value>)',
          50: 'rgb(var(--rgb-chandan-50) / <alpha-value>)', 100: 'rgb(var(--rgb-chandan-100) / <alpha-value>)', 200: 'rgb(var(--rgb-chandan-200) / <alpha-value>)', 300: 'rgb(var(--rgb-chandan-300) / <alpha-value>)', 400: 'rgb(var(--rgb-chandan-400) / <alpha-value>)', 500: 'rgb(var(--rgb-chandan-500) / <alpha-value>)', 600: 'rgb(var(--rgb-chandan-600) / <alpha-value>)', 700: 'rgb(var(--rgb-chandan-700) / <alpha-value>)', 800: 'rgb(var(--rgb-chandan-800) / <alpha-value>)', 900: 'rgb(var(--rgb-chandan-900) / <alpha-value>)',
        },
        sage: { 50: 'rgb(var(--rgb-sage-50) / <alpha-value>)', 100: 'rgb(var(--rgb-sage-100) / <alpha-value>)', 500: 'rgb(var(--rgb-sage-500) / <alpha-value>)', 700: 'rgb(var(--rgb-sage-700) / <alpha-value>)' },
        blue: { 50: 'rgb(var(--rgb-blue-50) / <alpha-value>)', 100: 'rgb(var(--rgb-blue-100) / <alpha-value>)', 500: 'rgb(var(--rgb-blue-500) / <alpha-value>)', 700: 'rgb(var(--rgb-blue-700) / <alpha-value>)' },
        ink: {
          DEFAULT: 'rgb(var(--rgb-ink-900) / <alpha-value>)',
          muted:   'rgb(var(--rgb-ink-500) / <alpha-value>)',
          50: 'rgb(var(--rgb-ink-50) / <alpha-value>)', 100: 'rgb(var(--rgb-ink-100) / <alpha-value>)', 200: 'rgb(var(--rgb-ink-200) / <alpha-value>)', 300: 'rgb(var(--rgb-ink-300) / <alpha-value>)', 500: 'rgb(var(--rgb-ink-500) / <alpha-value>)', 700: 'rgb(var(--rgb-ink-700) / <alpha-value>)', 800: 'rgb(var(--rgb-ink-800) / <alpha-value>)', 900: 'rgb(var(--rgb-ink-900) / <alpha-value>)',
        },
      },
      fontFamily: { sans: ['"Anek Latin"', '"Anek Devanagari"', 'system-ui', 'sans-serif'] },
      boxShadow: { DEFAULT: 'none', sm: 'none', md: 'none', lg: 'none', xl: 'none' }, // V2 is flat
      borderRadius: {
        lg:   'var(--radius)',
        md:   'calc(var(--radius) - 2px)',
        sm:   'calc(var(--radius) - 4px)',
        card: 'var(--radius-card)',   // 26
        tile: 'var(--radius-tile)',   // 20
        btn:  'var(--radius-pill)',   // buttons are pills
        pill: 'var(--radius-pill)',
      },
    },
  },
  plugins: [],
}
