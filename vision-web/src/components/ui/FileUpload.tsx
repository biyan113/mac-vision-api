import React, { useCallback } from 'react'
import { useDropzone } from 'react-dropzone'
import { Upload, Image, X } from 'lucide-react'
import { cn } from '../../lib/utils'

interface FileUploadProps {
  onFileSelect: (file: File) => void
  selectedFile: File | null
  onClear: () => void
  accept?: Record<string, string[]>
  maxSize?: number
  className?: string
  disabled?: boolean
}

const FileUpload: React.FC<FileUploadProps> = ({
  onFileSelect,
  selectedFile,
  onClear,
  accept = {
    'image/*': ['.png', '.jpg', '.jpeg', '.webp', '.heic']
  },
  maxSize = 20 * 1024 * 1024, // 20MB
  className,
  disabled = false
}) => {
  const onDrop = useCallback((acceptedFiles: File[]) => {
    if (acceptedFiles.length > 0) {
      onFileSelect(acceptedFiles[0])
    }
  }, [onFileSelect])

  const { getRootProps, getInputProps, isDragActive, fileRejections } = useDropzone({
    onDrop,
    accept,
    maxSize,
    multiple: false,
    disabled
  })

  const formatFileSize = (bytes: number) => {
    if (bytes === 0) return '0 B'
    const k = 1024
    const sizes = ['B', 'KB', 'MB', 'GB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
  }

  return (
    <div className={cn('w-full', className)}>
      {/* 文件上传区域 */}
      {!selectedFile && (
        <div
          {...getRootProps()}
          className={cn(
            'border-2 border-dashed rounded-notion p-8 text-center cursor-pointer notion-transition',
            'hover:border-notion-blue hover:bg-notion-blue-light/20',
            isDragActive && 'border-notion-blue bg-notion-blue-light/20',
            disabled && 'cursor-not-allowed opacity-50',
            'border-notion-border bg-notion-bg-secondary/50'
          )}
        >
          <input {...getInputProps()} />
          <Upload className="w-12 h-12 mx-auto mb-4 text-notion-text-light" />
          <div className="space-y-2">
            <p className="text-notion-text font-medium">
              {isDragActive ? '拖放图片到这里' : '点击上传或拖拽图片'}
            </p>
            <p className="text-notion-text-secondary text-sm">
              支持 PNG、JPG、JPEG、WebP、HEIC 格式，最大 {formatFileSize(maxSize)}
            </p>
          </div>
        </div>
      )}

      {/* 已选择文件预览 */}
      {selectedFile && (
        <div className="bg-notion-bg-secondary rounded-notion p-4">
          <div className="flex items-center justify-between mb-3">
            <h3 className="font-medium text-notion-text">已选择文件</h3>
            <button
              onClick={onClear}
              className="p-1 hover:bg-notion-bg-hover rounded-notion-sm notion-transition"
            >
              <X className="w-4 h-4 text-notion-text-secondary" />
            </button>
          </div>
          
          <div className="flex items-center space-x-3">
            <div className="flex-shrink-0 w-12 h-12 bg-notion-blue-light rounded-notion-sm flex items-center justify-center">
              <Image className="w-6 h-6 text-notion-blue" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-notion-text font-medium truncate">
                {selectedFile.name}
              </p>
              <p className="text-notion-text-secondary text-sm">
                {formatFileSize(selectedFile.size)}
              </p>
            </div>
          </div>

          {/* 图片预览 */}
          {selectedFile.type.startsWith('image/') && (
            <div className="mt-3">
              <img
                src={URL.createObjectURL(selectedFile)}
                alt="Preview"
                className="max-w-full max-h-64 rounded-notion-sm border border-notion-border"
              />
            </div>
          )}
        </div>
      )}

      {/* 错误提示 */}
      {fileRejections.length > 0 && (
        <div className="mt-3 p-3 bg-red-50 border border-red-200 rounded-notion">
          {fileRejections.map(({ file, errors }) => (
            <div key={file.name} className="text-red-800 text-sm">
              <p className="font-medium">{file.name}:</p>
              <ul className="list-disc list-inside">
                {errors.map((error) => (
                  <li key={error.code}>{error.message}</li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

export default FileUpload