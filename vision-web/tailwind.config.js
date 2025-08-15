/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        notion: {
          bg: '#ffffff',
          'bg-secondary': '#f7f6f3',
          'bg-hover': '#f1f1ef',
          text: '#37352f',
          'text-secondary': '#6b6b6b',
          'text-light': '#9b9b9b',
          border: '#e5e5e5',
          blue: '#0084ff',
          'blue-light': '#e7f3ff',
          gray: '#787774',
          'sidebar-bg': '#fbfbfa',
        }
      },
      fontFamily: {
        sans: ['-apple-system', 'BlinkMacSystemFont', 'Segoe UI', 'Roboto', 'sans-serif'],
      },
      boxShadow: {
        'notion': '0 1px 3px rgba(0, 0, 0, 0.1)',
        'notion-hover': '0 2px 8px rgba(0, 0, 0, 0.15)',
        'notion-modal': '0 16px 70px rgba(0, 0, 0, 0.2)',
      },
      borderRadius: {
        'notion': '8px',
        'notion-sm': '4px',
      }
    },
  },
  plugins: [],
}