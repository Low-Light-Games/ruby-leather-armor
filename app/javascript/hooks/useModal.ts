import { useState, useCallback } from 'react';
import type { Dispatch, SetStateAction } from 'react';

export interface UseModalResult<T> {
  isOpen: boolean;
  data: T | null;
  open: Dispatch<SetStateAction<T | null>>;
  close: () => void;
}

/**
 * Generic open/close modal (or drawer) state with optional typed payload.
 */
export function useModal<T>(initialState: T | null = null): UseModalResult<T> {
  const [modalData, setModalData] = useState<T | null>(initialState);

  const close = useCallback(() => {
    setModalData(null);
  }, []);

  return {
    isOpen: modalData !== null,
    data: modalData,
    open: setModalData,
    close,
  };
}
