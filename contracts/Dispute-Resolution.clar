(define-constant ERR_UNAUTHORIZED (err u400))
(define-constant ERR_DISPUTE_NOT_FOUND (err u401))
(define-constant ERR_INVALID_STAKE (err u402))
(define-constant ERR_ALREADY_RESOLVED (err u403))
(define-constant ERR_INSUFFICIENT_BALANCE (err u404))
(define-constant ERR_DISPUTE_EXPIRED (err u405))
(define-constant ERR_INVALID_PARTY (err u406))

(define-constant DISPUTE_STAKE_AMOUNT u500000)
(define-constant DISPUTE_RESOLUTION_PERIOD u1008)
(define-constant CONTRACT_OWNER tx-sender)

(define-data-var next-dispute-id uint u1)

(define-map disputes
  uint
  {
    transfer-id: uint,
    initiator: principal,
    respondent: principal,
    stake-amount: uint,
    reason: (string-ascii 200),
    status: (string-ascii 20),
    created-at: uint,
    resolved-at: (optional uint),
    winner: (optional principal),
    resolution-notes: (optional (string-ascii 200))
  }
)

(define-map user-dispute-history principal (list 10 uint))

(define-read-only (get-dispute (dispute-id uint))
  (map-get? disputes dispute-id)
)

(define-read-only (get-user-disputes (user principal))
  (default-to (list) (map-get? user-dispute-history user))
)

(define-read-only (is-dispute-active (dispute-id uint))
  (match (map-get? disputes dispute-id)
    dispute (is-eq (get status dispute) "open")
    false
  )
)

(define-read-only (get-dispute-stake-amount)
  DISPUTE_STAKE_AMOUNT
)

(define-public (open-dispute (transfer-id uint) (respondent principal) (reason (string-ascii 200)))
  (let (
    (dispute-id (var-get next-dispute-id))
    (initiator-disputes (get-user-disputes tx-sender))
  )
    (asserts! (not (is-eq tx-sender respondent)) ERR_INVALID_PARTY)
    (asserts! (> (len reason) u0) ERR_UNAUTHORIZED)
    (try! (stx-transfer? DISPUTE_STAKE_AMOUNT tx-sender (as-contract tx-sender)))
    
    (map-set disputes dispute-id {
      transfer-id: transfer-id,
      initiator: tx-sender,
      respondent: respondent,
      stake-amount: DISPUTE_STAKE_AMOUNT,
      reason: reason,
      status: "open",
      created-at: stacks-block-height,
      resolved-at: none,
      winner: none,
      resolution-notes: none
    })
    
    (map-set user-dispute-history tx-sender
      (unwrap-panic (as-max-len? (append initiator-disputes dispute-id) u10)))
    
    (var-set next-dispute-id (+ dispute-id u1))
    (ok dispute-id)
  )
)

(define-public (resolve-dispute (dispute-id uint) (winner principal) (notes (string-ascii 200)))
  (let (
    (dispute (unwrap! (map-get? disputes dispute-id) ERR_DISPUTE_NOT_FOUND))
  )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status dispute) "open") ERR_ALREADY_RESOLVED)
    (asserts! (or (is-eq winner (get initiator dispute)) (is-eq winner (get respondent dispute))) ERR_INVALID_PARTY)
    
    (map-set disputes dispute-id (merge dispute {
      status: "resolved",
      resolved-at: (some stacks-block-height),
      winner: (some winner),
      resolution-notes: (some notes)
    }))
    
    (try! (as-contract (stx-transfer? (get stake-amount dispute) tx-sender winner)))
    (ok winner)
  )
)
