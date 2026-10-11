import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  // Served at charak.care/admin (a rewrite on the main site's Vercel project
  // proxies that path to this app's own deployment — see
  // ../../charak site/vercel.json). Without this, the built HTML references
  // /assets/... absolutely, which the browser would request from the main
  // site's deployment instead of this one.
  base: '/admin/',
  plugins: [react()],
  resolve: { alias: { '@': path.resolve(__dirname, './src') } },
})
