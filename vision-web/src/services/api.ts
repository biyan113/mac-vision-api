import axios from 'axios'
import type { AxiosResponse } from 'axios'

// API基础配置
let API_BASE_URL = process.env.NODE_ENV === 'production' ? '/api' : 'http://localhost:8080'

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

// 请求拦截器
api.interceptors.request.use(
  (config) => {
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
  recognitionLanguages?: string // 逗号分隔的语言代码，如 "zh,en"
  recognitionLevel?: number // 0=精确模式，1=快速模式
}

export interface OCRResponse {
  text: string
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

export default api