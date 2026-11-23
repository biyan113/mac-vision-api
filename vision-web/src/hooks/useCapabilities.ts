import { useEffect, useState } from 'react'
import { getCapabilities } from '../services/api'
import type { Capabilities } from '../services/api'

/** 读取后端当前可用的能力；读取失败（后端未启动或版本较旧）时返回 null */
export const useCapabilities = (): Capabilities | null => {
  const [capabilities, setCapabilities] = useState<Capabilities | null>(null)

  useEffect(() => {
    let cancelled = false
    getCapabilities()
      .then((caps) => {
        if (!cancelled) setCapabilities(caps)
      })
      .catch(() => {
        // 忽略：页面仍可使用，只是不显示可用性提示
      })
    return () => {
      cancelled = true
    }
  }, [])

  return capabilities
}
