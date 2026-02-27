import { useState, useCallback, KeyboardEvent, useMemo } from 'react'

export function usePickerState(): {
    isOpen: boolean,
    open: () => void,
    handleEscapeKey: (e: KeyboardEvent<HTMLInputElement>) => void
} {
  const [openState, setOpenState] = useState(false)

  const handleEscapeKey = useCallback((e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Escape') {
      setOpenState(false)
    }
  }, [setOpenState])

  const isOpen = useMemo(() => {
    return openState
  }, [openState])

  const open = useCallback(() => {
    setOpenState(true)
  }, [setOpenState])

  return {
    isOpen,
    open,
    handleEscapeKey,
  }
}