(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_THRESHOLD (err u108))
(define-constant ERR_WALLET_NOT_FOUND (err u109))
(define-constant ERR_ALREADY_SIGNED (err u110))
(define-constant ERR_INSUFFICIENT_SIGNATURES (err u111))
(define-constant ERR_TRANSFER_EXECUTED (err u112))

(define-data-var next-wallet-id uint u1)
(define-data-var next-pending-id uint u1)

(define-map multi-sig-wallets
  uint
  {
    signers: (list 10 principal),
    threshold: uint,
    owner: principal,
    is-active: bool
  }
)

(define-map pending-transfers
  uint
  {
    wallet-id: uint,
    beneficiary: principal,
    amount: uint,
    signatures: (list 10 principal),
    created-at: uint,
    executed: bool
  }
)

(define-map user-wallets principal (list 5 uint))

(define-read-only (get-wallet (wallet-id uint))
  (map-get? multi-sig-wallets wallet-id)
)

(define-read-only (get-pending-transfer (transfer-id uint))
  (map-get? pending-transfers transfer-id)
)

(define-read-only (get-user-wallets (user principal))
  (default-to (list) (map-get? user-wallets user))
)

(define-public (create-wallet (signers (list 10 principal)) (threshold uint))
  (let (
    (wallet-id (var-get next-wallet-id))
    (signer-count (len signers))
    (current-wallets (get-user-wallets tx-sender))
  )
    (asserts! (> threshold u0) ERR_INVALID_THRESHOLD)
    (asserts! (<= threshold signer-count) ERR_INVALID_THRESHOLD)
    (asserts! (> signer-count u0) ERR_INVALID_THRESHOLD)
    
    (map-set multi-sig-wallets wallet-id {
      signers: signers,
      threshold: threshold,
      owner: tx-sender,
      is-active: true
    })
    
    (map-set user-wallets tx-sender
      (unwrap-panic (as-max-len? (append current-wallets wallet-id) u5)))
    
    (var-set next-wallet-id (+ wallet-id u1))
    (ok wallet-id)
  )
)

(define-public (propose-transfer (wallet-id uint) (beneficiary principal) (amount uint))
  (let (
    (wallet (unwrap! (map-get? multi-sig-wallets wallet-id) ERR_WALLET_NOT_FOUND))
    (transfer-id (var-get next-pending-id))
  )
    (asserts! (get is-active wallet) ERR_WALLET_NOT_FOUND)
    (asserts! (is-some (index-of (get signers wallet) tx-sender)) ERR_UNAUTHORIZED)
    
    (map-set pending-transfers transfer-id {
      wallet-id: wallet-id,
      beneficiary: beneficiary,
      amount: amount,
      signatures: (list tx-sender),
      created-at: stacks-block-height,
      executed: false
    })
    
    (var-set next-pending-id (+ transfer-id u1))
    (ok transfer-id)
  )
)

(define-public (sign-transfer (transfer-id uint))
  (let (
    (transfer (unwrap! (map-get? pending-transfers transfer-id) ERR_TRANSFER_EXECUTED))
    (wallet (unwrap! (map-get? multi-sig-wallets (get wallet-id transfer)) ERR_WALLET_NOT_FOUND))
    (current-signatures (get signatures transfer))
  )
    (asserts! (not (get executed transfer)) ERR_TRANSFER_EXECUTED)
    (asserts! (is-some (index-of (get signers wallet) tx-sender)) ERR_UNAUTHORIZED)
    (asserts! (is-none (index-of current-signatures tx-sender)) ERR_ALREADY_SIGNED)
    
    (map-set pending-transfers transfer-id (merge transfer {
      signatures: (unwrap-panic (as-max-len? (append current-signatures tx-sender) u10))
    }))
    
    (ok true)
  )
)

(define-public (execute-transfer (transfer-id uint))
  (let (
    (transfer (unwrap! (map-get? pending-transfers transfer-id) ERR_TRANSFER_EXECUTED))
    (wallet (unwrap! (map-get? multi-sig-wallets (get wallet-id transfer)) ERR_WALLET_NOT_FOUND))
    (signature-count (len (get signatures transfer)))
  )
    (asserts! (not (get executed transfer)) ERR_TRANSFER_EXECUTED)
    (asserts! (>= signature-count (get threshold wallet)) ERR_INSUFFICIENT_SIGNATURES)
    
    (map-set pending-transfers transfer-id (merge transfer {executed: true}))
    (ok (get amount transfer))
  )
)
