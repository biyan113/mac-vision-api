import axios from 'axios'
import type { AxiosResponse } from 'axios'
import { getCurrentApiUrl } from './api'

// PDF渲染请求接口
export interface PDFRenderRequest {
  pdfFile?: File
  pdfPath?: string
  pdfURL?: string
  pdfBase64?: string
  pageIndex?: number // 页面索引，从0开始
  dpi?: number // 输出DPI，默认150
}

// PDF文本抽取请求接口
export interface PDFTextRequest {
  pdfFile?: File
  pdfPath?: string
  pdfURL?: string
  pdfBase64?: string
  startPage?: number // 起始页面，从0开始
  endPage?: number // 结束页面
  mergePages?: boolean // 是否合并所有页面文本
}

// PDF页面文本
export interface PDFPageText {
  pageNumber: number
  text: string
}

// PDF文本抽取响应
export interface PDFTextResponse {
  totalPages: number
  extractedPages: PDFPageText[]
  allText?: string
}

// PDF渲染为位图
export const renderPDF = async (data: PDFRenderRequest): Promise<Blob> => {
  const formData = new FormData()
  
  if (data.pdfFile) {
    formData.append('pdfFile', data.pdfFile)
  }
  if (data.pdfPath) {
    formData.append('pdfPath', data.pdfPath)
  }
  if (data.pdfURL) {
    formData.append('pdfURL', data.pdfURL)
  }
  if (data.pdfBase64) {
    formData.append('pdfBase64', data.pdfBase64)
  }
  if (data.pageIndex !== undefined) {
    formData.append('pageIndex', data.pageIndex.toString())
  }
  if (data.dpi !== undefined) {
    formData.append('dpi', data.dpi.toString())
  }

  const api = axios.create({
    baseURL: getCurrentApiUrl(),
    timeout: 60000,
  })

  const response: AxiosResponse<Blob> = await api.post(
    '/pdf/render',
    formData,
    {
      headers: {
        'Content-Type': 'multipart/form-data',
      },
      responseType: 'blob',
    }
  )

  return response.data
}

// PDF文本抽取
export const extractPDFText = async (data: PDFTextRequest): Promise<PDFTextResponse> => {
  const formData = new FormData()
  
  if (data.pdfFile) {
    formData.append('pdfFile', data.pdfFile)
  }
  if (data.pdfPath) {
    formData.append('pdfPath', data.pdfPath)
  }
  if (data.pdfURL) {
    formData.append('pdfURL', data.pdfURL)
  }
  if (data.pdfBase64) {
    formData.append('pdfBase64', data.pdfBase64)
  }
  if (data.startPage !== undefined) {
    formData.append('startPage', data.startPage.toString())
  }
  if (data.endPage !== undefined) {
    formData.append('endPage', data.endPage.toString())
  }
  if (data.mergePages !== undefined) {
    formData.append('mergePages', data.mergePages.toString())
  }

  const api = axios.create({
    baseURL: getCurrentApiUrl(),
    timeout: 60000,
  })

  const response: AxiosResponse<PDFTextResponse> = await api.post(
    '/pdf/extract-text',
    formData,
    {
      headers: {
        'Content-Type': 'multipart/form-data',
      },
    }
  )

  return response.data
}
