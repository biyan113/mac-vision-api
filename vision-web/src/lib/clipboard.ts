import { showToast } from '../components/ui/Toast'

/** 复制文本并提示结果 */
export const copyWithToast = async (text: string) => {
  try {
    await navigator.clipboard.writeText(text)
    showToast('success', '已复制到剪贴板')
  } catch {
    showToast('error', '复制失败，请手动复制')
  }
}

export const downloadText = (text: string, filename: string, mime = 'text/plain') => {
  const url = URL.createObjectURL(new Blob([text], { type: `${mime};charset=utf-8` }))
  const link = document.createElement('a')
  link.href = url
  link.download = filename
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(url)
}
