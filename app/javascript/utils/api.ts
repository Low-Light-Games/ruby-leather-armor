/**
 * Read the Rails CSRF token from the meta tag.
 * Safe to call repeatedly — always reads the current DOM value.
 */
export function csrfToken(): string {
  return (
    document
      .querySelector('meta[name="csrf-token"]')
      ?.getAttribute('content') || ''
  );
}

/**
 * Thin wrapper around `fetch` that:
 * - Injects CSRF token and JSON headers automatically
 * - Throws on non-2xx responses with a parsed error message
 * - Returns parsed JSON (or null for 204 No Content)
 *
 * Use for any JSON API call to the Rails backend.
 */
export async function apiFetch<T = any>(
  url: string,
  options: RequestInit = {},
): Promise<T> {
  const res = await fetch(url, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      'X-CSRF-Token': csrfToken(),
      ...(options.headers || {}),
    },
  });

  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(
      body.errors?.join(', ') || body.error || `HTTP ${res.status}`,
    );
  }

  if (res.status === 204) return null as T;
  return res.json();
}
