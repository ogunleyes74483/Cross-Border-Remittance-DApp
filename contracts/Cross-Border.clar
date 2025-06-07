
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_AMOUNT (err u101))
(define-constant ERR_TRANSFER_NOT_FOUND (err u102))
(define-constant ERR_TRANSFER_ALREADY_CLAIMED (err u103))
(define-constant ERR_TRANSFER_NOT_READY (err u104))
(define-constant ERR_INSUFFICIENT_BALANCE (err u105))
(define-constant ERR_INVALID_BENEFICIARY (err u106))

(define-data-var next-transfer-id uint u1)
(define-data-var platform-fee-rate uint u250)
(define-data-var min-transfer-amount uint u1000000)
(define-data-var max-transfer-amount uint u100000000)

(define-map transfers
  uint
  {
    sender: principal,
    beneficiary: principal,
    amount: uint,
    fee: uint,
    status: (string-ascii 20),
    created-at: uint,
    delivery-time: uint,
    claimed-at: (optional uint)
  }
)

(define-map user-balances principal uint)

(define-map sender-transfers principal (list 50 uint))

(define-map beneficiary-transfers principal (list 50 uint))

(define-read-only (get-transfer (transfer-id uint))
  (map-get? transfers transfer-id)
)

(define-read-only (get-user-balance (user principal))
  (default-to u0 (map-get? user-balances user))
)

(define-read-only (get-platform-fee-rate)
  (var-get platform-fee-rate)
)

(define-read-only (get-transfer-limits)
  {
    min-amount: (var-get min-transfer-amount),
    max-amount: (var-get max-transfer-amount)
  }
)

(define-read-only (calculate-fee (amount uint))
  (/ (* amount (var-get platform-fee-rate)) u10000)
)

(define-read-only (get-sender-transfers (sender principal))
  (default-to (list) (map-get? sender-transfers sender))
)

(define-read-only (get-beneficiary-transfers (beneficiary principal))
  (default-to (list) (map-get? beneficiary-transfers beneficiary))
)

(define-read-only (is-transfer-ready (transfer-id uint))
  (match (map-get? transfers transfer-id)
    transfer (>= stacks-block-height (get delivery-time transfer))
    false
  )
)

(define-public (deposit (amount uint))
  (let (
    (current-balance (get-user-balance tx-sender))
  )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set user-balances tx-sender (+ current-balance amount))
    (ok amount)
  )
)

(define-public (withdraw (amount uint))
  (let (
    (current-balance (get-user-balance tx-sender))
  )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= current-balance amount) ERR_INSUFFICIENT_BALANCE)
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    (map-set user-balances tx-sender (- current-balance amount))
    (ok amount)
  )
)

(define-public (create-transfer (beneficiary principal) (amount uint) (delivery-blocks uint))
  (let (
    (transfer-id (var-get next-transfer-id))
    (fee (calculate-fee amount))
    (total-cost (+ amount fee))
    (sender-balance (get-user-balance tx-sender))
    (current-sender-transfers (get-sender-transfers tx-sender))
    (current-beneficiary-transfers (get-beneficiary-transfers beneficiary))
  )
    (asserts! (>= amount (var-get min-transfer-amount)) ERR_INVALID_AMOUNT)
    (asserts! (<= amount (var-get max-transfer-amount)) ERR_INVALID_AMOUNT)
    (asserts! (not (is-eq tx-sender beneficiary)) ERR_INVALID_BENEFICIARY)
    (asserts! (>= sender-balance total-cost) ERR_INSUFFICIENT_BALANCE)
    
    (map-set user-balances tx-sender (- sender-balance total-cost))
    
    (map-set transfers transfer-id {
      sender: tx-sender,
      beneficiary: beneficiary,
      amount: amount,
      fee: fee,
      status: "pending",
      created-at: stacks-block-height,
      delivery-time: (+ stacks-block-height delivery-blocks),
      claimed-at: none
    })
    
    (map-set sender-transfers tx-sender 
      (unwrap-panic (as-max-len? (append current-sender-transfers transfer-id) u50)))
    
    (map-set beneficiary-transfers beneficiary
      (unwrap-panic (as-max-len? (append current-beneficiary-transfers transfer-id) u50)))
    
    (var-set next-transfer-id (+ transfer-id u1))
    (ok transfer-id)
  )
)

(define-public (claim-transfer (transfer-id uint))
  (let (
    (transfer-data (unwrap! (map-get? transfers transfer-id) ERR_TRANSFER_NOT_FOUND))
    (beneficiary-balance (get-user-balance tx-sender))
  )
    (asserts! (is-eq tx-sender (get beneficiary transfer-data)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status transfer-data) "pending") ERR_TRANSFER_ALREADY_CLAIMED)
    (asserts! (>= stacks-block-height (get delivery-time transfer-data)) ERR_TRANSFER_NOT_READY)
    
    (map-set user-balances tx-sender (+ beneficiary-balance (get amount transfer-data)))
    
    (map-set transfers transfer-id (merge transfer-data {
      status: "claimed",
      claimed-at: (some stacks-block-height)
    }))
    
    (ok (get amount transfer-data))
  )
)

(define-public (cancel-transfer (transfer-id uint))
  (let (
    (transfer-data (unwrap! (map-get? transfers transfer-id) ERR_TRANSFER_NOT_FOUND))
    (sender-balance (get-user-balance tx-sender))
    (refund-amount (+ (get amount transfer-data) (get fee transfer-data)))
  )
    (asserts! (is-eq tx-sender (get sender transfer-data)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status transfer-data) "pending") ERR_TRANSFER_ALREADY_CLAIMED)
    (asserts! (< stacks-block-height (get delivery-time transfer-data)) ERR_TRANSFER_NOT_READY)
    
    (map-set user-balances tx-sender (+ sender-balance refund-amount))
    
    (map-set transfers transfer-id (merge transfer-data {
      status: "cancelled"
    }))
    
    (ok refund-amount)
  )
)

(define-public (update-platform-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= new-rate u1000) ERR_INVALID_AMOUNT)
    (var-set platform-fee-rate new-rate)
    (ok new-rate)
  )
)

(define-public (update-transfer-limits (min-amount uint) (max-amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (< min-amount max-amount) ERR_INVALID_AMOUNT)
    (var-set min-transfer-amount min-amount)
    (var-set max-transfer-amount max-amount)
    (ok {min: min-amount, max: max-amount})
  )
)

(define-public (collect-platform-fees)
  (let (
    (contract-balance (stx-get-balance (as-contract tx-sender)))
  )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> contract-balance u0) ERR_INSUFFICIENT_BALANCE)
    (try! (as-contract (stx-transfer? contract-balance tx-sender CONTRACT_OWNER)))
    (ok contract-balance)
  )
)
