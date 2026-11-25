import { createThirdwebClient, defineChain } from 'thirdweb'

export const CLIENT_ID = import.meta.env.VITE_THIRDWEB_CLIENT_ID as string
export const API_URL = (import.meta.env.VITE_API_URL as string) || ''
export const APP_URL =
  (import.meta.env.VITE_APP_URL as string) || window.location.origin
export const WC_PROJECT_ID =
  (import.meta.env.VITE_WC_PROJECT_ID as string) || undefined

const allowed = ((import.meta.env.VITE_ALLOWED_RETURN as string) || 'plexus://')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean)

/** Only redirect back to prefixes listed in VITE_ALLOWED_RETURN (no open redirect). */
export function isAllowedReturn(url: string | null): url is string {
  return !!url && allowed.some((p) => url.startsWith(p))
}

export const client = createThirdwebClient({ clientId: CLIENT_ID })

/** Chain comes from the backend (single source of truth). Works for 56, 97, ... */
export const chainFromId = (chainId: number) => defineChain(chainId)
