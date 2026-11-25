import { useEffect, useMemo, useState } from 'react'
import { getContract, prepareContractCall, waitForReceipt } from 'thirdweb'
import {
  ConnectButton,
  useActiveAccount,
  useActiveWalletChain,
  useSendTransaction,
  useSwitchActiveWalletChain,
} from 'thirdweb/react'
import { createWallet, walletConnect } from 'thirdweb/wallets'
import { confirmTx, getPaymentInfo, submitTx, type PaymentInfo } from './api'
import {
  APP_URL,
  WC_PROJECT_ID,
  chainFromId,
  client,
  isAllowedReturn,
} from './config'
import { METHODS, type Action } from './escrowAbi'

// Same wallet list on desktop (extension / QR) and mobile (deep link to the app).
const wallets = [
  createWallet('io.metamask'),
  createWallet('com.trustwallet.app'),
  createWallet('com.binance.wallet'),
  createWallet('com.coinbase.wallet'),
  createWallet('me.rainbow'),
  createWallet('com.safepal'),
  createWallet('com.okex.wallet'),
  createWallet('com.crypto.wallet'),
  createWallet('io.rabby'),
  walletConnect(),
]

const TITLES: Record<Action, string> = {
  pay: 'Secure payment',
  confirm: 'Confirm delivery',
  dispute: 'Open a dispute',
  refund: 'Request a refund',
}
const BUTTONS: Record<Action, string> = {
  pay: 'Pay with escrow',
  confirm: 'Release funds to seller',
  dispute: 'Open dispute on-chain',
  refund: 'Refund me',
}

function readParams() {
  const url = new URL(window.location.href)
  const hash = new URLSearchParams(window.location.hash.replace(/^#/, ''))
  const token = hash.get('t') || ''
  // The token must not stay in the address bar / history.
  if (window.location.hash) {
    window.history.replaceState(null, '', url.pathname + url.search)
  }
  const a = (url.searchParams.get('a') || 'pay') as Action
  return {
    orderId: url.searchParams.get('orderId') || '',
    action: (['pay', 'confirm', 'dispute', 'refund'].includes(a) ? a : 'pay') as Action,
    returnUrl: url.searchParams.get('r'),
    token,
  }
}

const short = (v?: string | null) => (v ? `${v.slice(0, 8)}…${v.slice(-6)}` : '-')

export default function App() {
  const params = useMemo(readParams, [])
  const { orderId, action, token, returnUrl } = params

  const account = useActiveAccount()
  const activeChain = useActiveWalletChain()
  const switchChain = useSwitchActiveWalletChain()
  const { mutateAsync: sendTx } = useSendTransaction()

  const [info, setInfo] = useState<PaymentInfo | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [step, setStep] = useState<string>('')
  const [done, setDone] = useState<string | null>(null)

  useEffect(() => {
    if (!orderId || !token) {
      setError('Invalid or expired link. Please go back to the PLEXUS app and try again.')
      return
    }
    getPaymentInfo(orderId, action, token)
      .then(setInfo)
      .catch((e) => setError(e.message))
  }, [orderId, token, action])

  const chain = info ? chainFromId(info.chainId) : null

  async function run() {
    if (!info || !chain || !account) return
    setError(null)
    setBusy(true)
    try {
      if (activeChain?.id !== info.chainId) {
        setStep('Switching network…')
        await switchChain(chain)
      }

      const contract = getContract({
        client,
        chain,
        address: info.contractAddress,
      })

      setStep('Confirm the transaction in your wallet…')
      let tx
      if (action === 'pay') {
        tx = prepareContractCall({
          contract,
          method: METHODS.creerCommande,
          params: [info.sellerWallet, BigInt(info.delayDays)],
          value: BigInt(info.amountWei),
        })
      } else {
        if (!info.escrowId) throw new Error('This order has no escrow id yet.')
        const method =
          action === 'confirm'
            ? METHODS.confirmerLivraison
            : action === 'dispute'
              ? METHODS.ouvrirLitige
              : METHODS.demanderRemboursement
        tx = prepareContractCall({ contract, method, params: [BigInt(info.escrowId)] })
      }

      const sent = await sendTx(tx)
      void submitTx(orderId, sent.transactionHash, token)

      setStep('Waiting for blockchain confirmation…')
      const receipt = await waitForReceipt({
        client,
        chain,
        transactionHash: sent.transactionHash,
      })
      if (receipt.status !== 'success') throw new Error('Transaction failed on-chain.')

      // The server acts only after enough blocks sit on top of the payment, so this can take a minute or two.
      setStep('Waiting for confirmations…')
      let last: Error | null = null
      for (let i = 0; i < 45; i++) {
        try {
          const r = await confirmTx(orderId, action, sent.transactionHash, token)
          setDone(r.status)
          last = null
          break
        } catch (e) {
          last = e as Error
          if (/confirmations|not confirmed yet/i.test(last.message)) setStep(last.message)
          else if (i > 5) break // a real refusal (wrong amount, wrong seller...): stop waiting
          await new Promise((r) => setTimeout(r, 3000))
        }
      }
      if (last) throw last
    } catch (e) {
      const m = (e as Error).message || String(e)
      setError(/reject|denied|cancel/i.test(m) ? 'Transaction cancelled in the wallet.' : m)
    } finally {
      setBusy(false)
      setStep('')
    }
  }

  const back = isAllowedReturn(returnUrl) ? returnUrl : 'plexus://orders'

  return (
    <div className="page">
      <div className="card">
        <h1 className="brand">PLEXUS</h1>
        <p className="sub">{TITLES[action]}</p>

        {info && (
          <>
            {action === 'pay' && (
              <div className="amount">
                <div className="big">{info.amountBnb} BNB</div>
                <div className="small">≈ ${info.amountUsd.toFixed(2)} · locked in escrow</div>
              </div>
            )}
            <div className="row"><span>Order</span><span>{short(info.orderId)}</span></div>
            {action === 'pay' && (
              <div className="row"><span>Seller wallet</span><span>{short(info.sellerWallet)}</span></div>
            )}
            {info.escrowId && (
              <div className="row"><span>Escrow #</span><span>{info.escrowId}</span></div>
            )}
            <div className="row"><span>Network</span><span>BNB Smart Chain ({info.chainId})</span></div>

            {!done && (
              <>
                <div className="center">
                  <ConnectButton
                    client={client}
                    wallets={wallets}
                    chain={chain ?? undefined}
                    connectModal={{ size: 'compact', title: 'Connect your wallet' }}
                    appMetadata={{
                      name: 'PLEXUS',
                      url: APP_URL,
                      description: 'PLEXUS marketplace escrow payments',
                      logoUrl: `${APP_URL}/logo.png`,
                    }}
                    walletConnect={WC_PROJECT_ID ? { projectId: WC_PROJECT_ID } : undefined}
                    theme="light"
                  />
                </div>
                {account && (
                  <button className="btn" disabled={busy} onClick={run}>
                    {busy ? step || 'Please wait…' : BUTTONS[action]}
                  </button>
                )}
                {account &&
                  info.buyerWallet &&
                  action !== 'pay' &&
                  account.address.toLowerCase() !== info.buyerWallet.toLowerCase() && (
                    <div className="msg info">
                      Connect the same wallet you used to pay ({short(info.buyerWallet)}).
                    </div>
                  )}
              </>
            )}
          </>
        )}

        {done && (
          <>
            <div className="msg ok">Done. Your order is now: {done}.</div>
            <div style={{ marginTop: 14 }}>
              <a href={back}>
                <button className="btn secondary">Return to PLEXUS</button>
              </a>
            </div>
          </>
        )}
        {error && <div className="msg err">{error}</div>}
        {!info && !error && <div className="msg info">Loading order…</div>}
        <p className="hint">Funds are locked and released by the PlexusEscrow smart contract. PLEXUS never holds your funds.</p>
      </div>
    </div>
  )
}
