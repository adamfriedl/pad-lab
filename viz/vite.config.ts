import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Project Pages: https://adamfriedl.github.io/pad-lab
export default defineConfig({
  plugins: [react()],
  base: '/pad-lab/',
});
