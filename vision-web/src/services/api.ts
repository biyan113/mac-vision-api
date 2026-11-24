import axios from 'axios'
import type { AxiosResponse } from 'axios'

// API基础配置
// 可在构建时用 VITE_API_BASE_URL 覆盖：
// - nginx 镜像中为 /api（由 nginx 反向代理到后端）
// - 随后端一起发布时为 /（前端与 API 同源）
export const DEFAULT_API_BASE_URL: string =
  import.meta.env.VITE_API_BASE_URL ||
  (import.meta.env.PROD ? '/api' : 'http://localhost:8080')

let API_BASE_URL: string = DEFAULT_API_BASE_URL

// 从localStorage获取用户配置的API地址
const getApiBaseUrl = (): string => {
  const savedUrl = localStorage.getItem('vision-api-base-url')
  return savedUrl || API_BASE_URL
}

// 设置API基础地址
export const setApiBaseUrl = (url: string): void => {
  localStorage.setItem('vision-api-base-url', url)
  API_BASE_URL = url
  // 更新axios实例的baseURL
  api.defaults.baseURL = url
}

const api = axios.create({
  baseURL: getApiBaseUrl(),
  timeout: 60000, // 60秒超时
})

// API Key（后端设置了 VISION_API_KEY 时需要）
export const getApiKey = (): string => localStorage.getItem('vision-api-key') || ''

export const setApiKey = (key: string): void => {
  if (key) {
    localStorage.setItem('vision-api-key', key)
  } else {
    localStorage.removeItem('vision-api-key')
  }
}

// 请求拦截器
api.interceptors.request.use(
  (config) => {
    const key = getApiKey()
    if (key) {
      config.headers.set('X-API-Key', key)
    }
    return config
  },
  (error) => {
    return Promise.reject(error)
  }
)

// 响应拦截器
api.interceptors.response.use(
  (response) => {
    return response
  },
  (error) => {
    console.error('API Error:', error)
    return Promise.reject(error)
  }
)

// OCR文本识别接口
export interface OCRRequest {
  imageFile?: File
  imagePath?: string
  imageURL?: string
  imageBase64?: string
  recognitionLanguages?: string // 逗号分隔的语言代码，如 "zh-Hans,en-US"
  recognitionLevel?: number // 0=精确模式，1=快速模式
  includeLines?: boolean // 是否返回每行的位置与置信度
}

export interface OCRLine {
  text: string
  confidence: number
  // 归一化坐标，原点在左下角
  boundingBox: { x: number; y: number; width: number; height: number }
}

export interface OCRResponse {
  text: string
  lines?: OCRLine[]
}

export const recognizeText = async (data: OCRRequest): Promise<OCRResponse> => {
  const formData = new FormData()
  
  if (data.imageFile) {
    formData.append('imageFile', data.imageFile)
  }
  if (data.imagePath) {
    formData.append('imagePath', data.imagePath)
  }
  if (data.imageURL) {
    formData.append('imageURL', data.imageURL)
  }
  if (data.imageBase64) {
    formData.append('imageBase64', data.imageBase64)
  }
  if (data.recognitionLanguages) {
    formData.append('recognitionLanguages', data.recognitionLanguages)
  }
  if (data.recognitionLevel !== undefined) {
    formData.append('recognitionLevel', data.recognitionLevel.toString())
  }
  if (data.includeLines) {
    formData.append('includeLines', 'true')
  }

  const response: AxiosResponse<OCRResponse> = await api.post(
    '/text-detection/recognize-text',
    formData,
    {
      headers: {
        'Content-Type': 'multipart/form-data',
      },
    }
  )

  return response.data
}

// 背景移除接口
export interface BackgroundRemovalRequest {
  imageFile: File
}

export const removeBackground = async (data: BackgroundRemovalRequest): Promise<Blob> => {
  const formData = new FormData()
  formData.append('imageFile', data.imageFile)

  const response: AxiosResponse<Blob> = await api.post(
    '/image-feature/background-removal',
    formData,
    {
      headers: {
        'Content-Type': 'multipart/form-data',
      },
      responseType: 'blob', // 重要：指定响应类型为blob
    }
  )

  return response.data
}

// 工具函数：将文件转换为base64
export const fileToBase64 = (file: File): Promise<string> => {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.readAsDataURL(file)
    reader.onload = () => {
      const result = reader.result as string
      resolve(result)
    }
    reader.onerror = (error) => {
      reject(error)
    }
  })
}

// 工具函数：检查服务器状态
export const checkServerHealth = async (customUrl?: string): Promise<{ isHealthy: boolean; message: string; url: string }> => {
  const testUrl = customUrl || getApiBaseUrl()
  try {
    const testApi = axios.create({
      baseURL: testUrl,
      timeout: 5000,
    })
    const response = await testApi.get('/health')
    return {
      isHealthy: response.status === 200,
      message: response.data?.status || 'Connected',
      url: testUrl
    }
  } catch (error) {
    console.error('Server health check failed:', error)
    return {
      isHealthy: false,
      message: error instanceof Error ? error.message : 'Connection failed',
      url: testUrl
    }
  }
}

// 获取当前API基础地址
export const getCurrentApiUrl = (): string => {
  return getApiBaseUrl()
}

// 从错误对象中取出后端返回的原因
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const errorMessage = (err: any, fallback = '请求失败，请稍后重试'): string => {
  const data = err?.response?.data
  if (data instanceof Blob) return err?.message || fallback
  return data?.reason || data?.message || err?.message || fallback
}

// 当前系统上可用的能力
export interface Capabilities {
  textRecognition: boolean
  pdf: boolean
  imageAnalysis: boolean
  backgroundRemoval: boolean
  aesthetics: boolean
  documentRecognition: boolean
  lensSmudge: boolean
  speechTranscription: boolean
  translation: boolean
}

export const getCapabilities = async (): Promise<Capabilities> => {
  const response = await api.get<Capabilities>('/capabilities', { timeout: 5000 })
  return response.data
}

// 通用：上传一张图片到指定接口，返回 JSON
export const postImage = async <T,>(
  path: string,
  imageFile: File,
  params: Record<string, string | number | boolean | undefined> = {}
): Promise<T> => {
  const formData = new FormData()
  formData.append('imageFile', imageFile)
  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== '') formData.append(key, String(value))
  })
  const response = await api.post<T>(path, formData)
  return response.data
}

// 文档结构识别
export interface DocumentResponse {
  text: string
  paragraphs: string[]
  tables: { rows: string[][] }[]
  emails: string[]
  phoneNumbers: string[]
}

export const recognizeDocument = (imageFile: File) =>
  postImage<DocumentResponse>('/text-detection/recognize-document', imageFile)

// 语音转写
export interface TranscriptSegment {
  text: string
  start: number
  duration: number
}

export interface TranscribeResponse {
  locale: string
  text: string
  segments: TranscriptSegment[]
}

export interface SpeechLocales {
  supported: string[]
  installed: string[]
}

export const getSpeechLocales = async (): Promise<SpeechLocales> => {
  const response = await api.get<SpeechLocales>('/speech/supported-locales', { timeout: 10000 })
  return response.data
}

export const transcribeAudio = async (audioFile: File, locale: string): Promise<TranscribeResponse> => {
  const formData = new FormData()
  formData.append('audioFile', audioFile)
  formData.append('locale', locale)
  // 长音频和首次下载语音模型都可能很慢
  const response = await api.post<TranscribeResponse>('/speech/transcribe', formData, { timeout: 30 * 60 * 1000 })
  return response.data
}

// 翻译
export interface TranslateResponse {
  sourceLanguage: string
  targetLanguage: string
  translations: string[]
}

export const getTranslationLanguages = async (): Promise<string[]> => {
  const response = await api.get<{ languages: string[] }>('/translation/supported-languages', { timeout: 10000 })
  return response.data.languages
}

export const translateText = async (
  text: string,
  targetLanguage: string,
  sourceLanguage?: string
): Promise<TranslateResponse> => {
  const response = await api.post<TranslateResponse>('/translation/translate', {
    text,
    targetLanguage,
    sourceLanguage: sourceLanguage || undefined,
  })
  return response.data
}

export default api