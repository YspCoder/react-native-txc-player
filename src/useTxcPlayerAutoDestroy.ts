import { useEffect, useRef, type RefObject } from 'react';
import {
  Commands,
  type TxcPlayerViewRef,
} from './TxcPlayerViewNativeComponent';

type Options = {
  /**
   * Whether the current player should be considered active. When false, the hook can destroy
   * the underlying player if `destroyOnDeactivate` is enabled.
   */
  active?: boolean;
  /**
   * Destroy the underlying native player when `active` flips from true to false. Defaults to false.
   */
  destroyOnDeactivate?: boolean;
  /**
   * Ensure only one player is active at a time. When true (default), activating this player will
   * automatically destroy the previously active instance.
   */
  exclusive?: boolean;
};

let currentActive: TxcPlayerViewRef | null = null;

function destroy(ref: TxcPlayerViewRef | null | undefined) {
  if (!ref) {
    return;
  }
  try {
    Commands.destroy(ref);
  } catch (e) {
    // no-op – the native side may already be disposed
  }
}

export function useTxcPlayerAutoDestroy(
  ref: RefObject<TxcPlayerViewRef | null | undefined>,
  options: Options = {}
) {
  const {
    active = true,
    destroyOnDeactivate = false,
    exclusive = true,
  } = options;
  const wasActive = useRef<boolean>(active);
  const lastKnownNode = useRef<TxcPlayerViewRef | null>(null);

  useEffect(() => {
    const node = ref.current as TxcPlayerViewRef | null | undefined;
    if (!node) {
      wasActive.current = active;
      return;
    }

    lastKnownNode.current = node;

    if (active && exclusive) {
      if (currentActive && currentActive !== node) {
        destroy(currentActive);
      }
      currentActive = node;
    }

    if (!active && destroyOnDeactivate && wasActive.current) {
      destroy(node);
      if (currentActive === node) {
        currentActive = null;
      }
    }

    wasActive.current = active;
  }, [active, destroyOnDeactivate, exclusive, ref]);

  useEffect(() => {
    return () => {
      const node = lastKnownNode.current;
      if (node && currentActive === node) {
        currentActive = null;
      }
      destroy(node);
      lastKnownNode.current = null;
    };
  }, [ref]);
}
