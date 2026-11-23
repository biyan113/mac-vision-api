import React, { useState } from 'react'
import { Copy, Download, Table } from 'lucide-react'
import FileUpload from './ui/FileUpload'
import { showToast } from './ui/Toast'
import {
  CapabilityNotice, EmptyState, ErrorBox, LoadingState, PageHeader, RunButton,
} from './ui/Common'
import { copyWithToast, downloadText } from '../lib/clipboard'
import { errorMessage, recognizeDocument } from '../services/api'
import type { DocumentResponse } from '../services/api'
import { useCapabilities } from '../hooks/useCapabilities'

const toCSV = (rows: string[][]): string =>
  rows
    .map((row) => row.map((cell) => `"${cell.replace(/"/g, '""')}"`).join(','))
    .join('\n')

const DocumentPage: React.FC = () => {
  const capabilities = useCapabilities()
  const [selectedFile, setSelectedFile] = useState<File | null>(null)
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState('')
  const [result, setResult] = useState<DocumentResponse | null>(null)

  const reset = () => {
    setError('')
    setResult(null)
  }

  const handleRun = async () => {
    if (!selectedFile) return
    setIsLoading(true)
    reset()
    try {
      setResult(await recognizeDocument(selectedFile))
      showToast('success', '文档识别完成')
    } catch (err) {
      const message = errorMessage(err, '识别失败，请稍后重试')
      setError(message)
      showToast('error', message)
    } finally {
      setIsLoading(false)
    }
  }

  return (
    <div className="max-w-6xl mx-auto px-4 py-8 sm:px-6 lg:px-8">
      <PageHeader
        icon={Table}
        title="文档结构识别"
        description="识别文档图片中的段落和表格，并提取邮箱、电话。适合票据、合同、表单等有版面结构的图片。"
      />

      <CapabilityNotice capabilities={capabilities} need="documentRecognition" requirement="macOS 26 或更高版本" />

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="space-y-4">
          <FileUpload
            onFileSelect={(file) => {
              setSelectedFile(file)
              reset()
            }}
            selectedFile={selectedFile}
            onClear={() => {
              setSelectedFile(null)
              reset()
            }}
            disabled={isLoading}
          />
          <RunButton
            onClick={handleRun}
            disabled={!selectedFile}
            loading={isLoading}
            label="开始识别"
            loadingLabel="识别中..."
          />
        </div>

        <div className="bg-notion-bg-secondary rounded-notion p-4 min-h-[400px]">
          <h3 className="font-medium text-notion-text mb-4">识别结果</h3>

          {error && <ErrorBox title="识别失败" message={error} />}
          {isLoading && <LoadingState text="正在识别文档结构..." />}
          {!result && !error && !isLoading && <EmptyState icon={Table} text="上传文档图片并点击开始识别" />}

          {result && (
            <div className="space-y-4">
              {result.tables.map((table, index) => (
                <div key={index} className="bg-white border border-notion-border rounded-notion p-4">
                  <div className="flex items-center justify-between mb-3">
                    <h4 className="font-medium text-notion-text">表格 {index + 1}</h4>
                    <button
                      onClick={() => downloadText(toCSV(table.rows), `table-${index + 1}.csv`, 'text/csv')}
                      className="flex items-center space-x-1 text-sm text-notion-blue hover:underline"
                    >
                      <Download className="w-4 h-4" />
                      <span>导出 CSV</span>
                    </button>
                  </div>
                  <div className="overflow-x-auto">
                    <table className="min-w-full text-sm border-collapse">
                      <tbody>
                        {table.rows.map((row, r) => (
                          <tr key={r}>
                            {row.map((cell, c) => (
                              <td key={c} className="border border-notion-border px-2 py-1 text-notion-text align-top">
                                {cell}
                              </td>
                            ))}
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </div>
              ))}

              {(result.emails.length > 0 || result.phoneNumbers.length > 0) && (
                <div className="bg-white border border-notion-border rounded-notion p-4 text-sm text-notion-text space-y-1">
                  <h4 className="font-medium mb-2">提取到的信息</h4>
                  {result.emails.map((email) => (
                    <p key={email}>邮箱：{email}</p>
                  ))}
                  {result.phoneNumbers.map((phone) => (
                    <p key={phone}>电话：{phone}</p>
                  ))}
                </div>
              )}

              <div className="bg-white border border-notion-border rounded-notion p-4">
                <div className="flex items-center justify-between mb-3">
                  <h4 className="font-medium text-notion-text">段落（{result.paragraphs.length}）</h4>
                  <button
                    onClick={() => copyWithToast(result.text)}
                    className="flex items-center space-x-1 text-sm text-notion-blue hover:underline"
                  >
                    <Copy className="w-4 h-4" />
                    <span>复制全文</span>
                  </button>
                </div>
                {result.paragraphs.length > 0 ? (
                  <div className="space-y-3 text-sm text-notion-text leading-relaxed">
                    {result.paragraphs.map((paragraph, i) => (
                      <p key={i} className="whitespace-pre-wrap">{paragraph}</p>
                    ))}
                  </div>
                ) : (
                  <pre className="whitespace-pre-wrap text-sm text-notion-text">{result.text || '没有识别到文字'}</pre>
                )}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

export default DocumentPage
