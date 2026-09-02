/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        primary: { DEFAULT: '#2F6FED', soft: '#EAF1FE', deep: '#1E4FBF' },
        ink: { DEFAULT: '#101828', muted: '#5B6472' },
        border: '#E4E8EE',
        bg: { DEFAULT: '#FFFFFF', subtle: '#F5F8FA' },
        success: '#1FAA6D',
        warning: '#E0930B',
        danger: '#E0473E',
      },
      fontFamily: { sans: ['Inter', 'system-ui', 'sans-serif'] },
      borderRadius: { card: '12px', btn: '10px', pill: '100px' },
    },
  },
  plugins: [],
}
