import { API_URL } from './config'
import type { Action } from './escrowAbi'

export interface PaymentInfo {
  orderId: string
  action: Action
  chainId: number
  contractAddress: string
  sellerWallet: string
  amountWei: string
  amountBnb: string
  amountUsd: number
  delayDays: number
  escrowId: string | null
  buyerWallet?: string | null
  status: string
}

async function call<T>(path: string, token: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${API_URL}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
      ...(init?.headers || {}),
    },
  })
  const body = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(body.error || body.msg || `HTTP ${res.status}`)
  return body as T
}

export const getPaymentInfo = (orderId: string, action: Action, token: string) =>
  call<PaymentInfo>(`/escrow/orders/${orderId}/payment-info?action=${action}`, token)

export const confirmTx = (
  orderId: string,
  action: Action,
  transactionHash: string,
  token: string,
) =>
  call<{ ok: boolean; status: string; escrowId?: string }>(
    `/escrow/orders/${orderId}/tx-confirmed`,
    token,
    { method: 'POST', body: JSON.stringify({ action, transactionHash }) },
  )

/** Best effort: lets the backend link the order to the transaction even if the page is closed. */
export const submitTx = (orderId: string, transactionHash: string, token: string) =>
  call<{ ok: boolean }>(`/escrow/orders/${orderId}/tx-submitted`, token, {
    method: 'POST',
    body: JSON.stringify({ transactionHash }),
  }).catch(() => undefined)
