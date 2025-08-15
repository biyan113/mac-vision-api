import { BrowserRouter as Router, Routes, Route } from 'react-router-dom'
import ErrorBoundary from './components/ErrorBoundary'
import Layout from './components/layout/Layout'
import HomePage from './components/HomePage'
import OCRPage from './components/OCRPage'
import BackgroundRemovalPage from './components/BackgroundRemovalPage'
import PDFPage from './components/PDFPage'
import { ToastContainer } from './components/ui/Toast'

function App() {
  return (
    <ErrorBoundary>
      <Router>
        <Layout>
          <Routes>
            <Route path="/" element={<HomePage />} />
            <Route path="/ocr" element={<OCRPage />} />
            <Route path="/background-removal" element={<BackgroundRemovalPage />} />
            <Route path="/pdf" element={<PDFPage />} />
          </Routes>
        </Layout>
        <ToastContainer />
      </Router>
    </ErrorBoundary>
  )
}

export default App
