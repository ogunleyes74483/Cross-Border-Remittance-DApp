
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_AMOUNT (err u101))
(define-constant ERR_TRANSFER_NOT_FOUND (err u102))
(define-constant ERR_TRANSFER_ALREADY_CLAIMED (err u103))
(define-constant ERR_TRANSFER_NOT_READY (err u104))
(define-constant ERR_INSUFFICIENT_BALANCE (err u105))
(define-constant ERR_INVALID_BENEFICIARY (err u106))
(define-constant ERR_POLICY_NOT_FOUND (err u302))
(define-constant ERR_ALREADY_INSURED (err u303))
(define-constant ERR_POLICY_EXPIRED (err u304))
(define-constant ERR_CLAIM_ALREADY_PROCESSED (err u305))
(define-constant ERR_INSUFFICIENT_FUNDS (err u306))
(define-constant ERR_INVALID_TRANSFER (err u307))

(define-data-var next-policy-id uint u1)
(define-data-var base-premium-rate uint u50)
(define-data-var insurance-pool uint u0)
(define-data-var max-coverage-amount uint u50000000)
(define-data-var claim-period-blocks uint u1008)

(define-constant ERR_INVALID_CURRENCY (err u201))
(define-constant ERR_INVALID_RATE (err u202))
(define-constant ERR_CURRENCY_NOT_FOUND (err u203))

(define-data-var oracle-fee uint u100)

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



(define-map exchange-rates 
  (string-ascii 10)
  {
    rate: uint,
    decimals: uint,
    last-updated: uint,
    is-active: bool
  }
)

(define-map supported-currencies (string-ascii 10) bool)

(define-read-only (get-exchange-rate (currency (string-ascii 10)))
  (map-get? exchange-rates currency)
)

(define-read-only (get-oracle-fee)
  (var-get oracle-fee)
)

(define-read-only (is-currency-supported (currency (string-ascii 10)))
  (default-to false (map-get? supported-currencies currency))
)

(define-read-only (convert-stx-to-currency (stx-amount uint) (currency (string-ascii 10)))
  (match (map-get? exchange-rates currency)
    rate-data 
      (if (get is-active rate-data)
        (ok (/ (* stx-amount (get rate rate-data)) (pow u10 (get decimals rate-data))))
        ERR_CURRENCY_NOT_FOUND)
    ERR_CURRENCY_NOT_FOUND
  )
)

(define-read-only (convert-currency-to-stx (currency-amount uint) (currency (string-ascii 10)))
  (match (map-get? exchange-rates currency)
    rate-data
      (if (get is-active rate-data)
        (ok (/ (* currency-amount (pow u10 (get decimals rate-data))) (get rate rate-data)))
        ERR_CURRENCY_NOT_FOUND)
    ERR_CURRENCY_NOT_FOUND
  )
)

(define-read-only (get-all-rates)
  {
    usd: (map-get? exchange-rates "USD"),
    eur: (map-get? exchange-rates "EUR"),
    gbp: (map-get? exchange-rates "GBP"),
    jpy: (map-get? exchange-rates "JPY"),
    cad: (map-get? exchange-rates "CAD")
  }
)

(define-public (add-currency (currency (string-ascii 10)) (rate uint) (decimals uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> rate u0) ERR_INVALID_RATE)
    (asserts! (<= decimals u8) ERR_INVALID_RATE)
    (asserts! (> (len currency) u0) ERR_INVALID_CURRENCY)
    
    (map-set exchange-rates currency {
      rate: rate,
      decimals: decimals,
      last-updated: stacks-block-height,
      is-active: true
    })
    
    (map-set supported-currencies currency true)
    (ok currency)
  )
)

(define-public (update-exchange-rate (currency (string-ascii 10)) (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> new-rate u0) ERR_INVALID_RATE)
    (asserts! (is-currency-supported currency) ERR_CURRENCY_NOT_FOUND)
    
    (match (map-get? exchange-rates currency)
      rate-data 
        (begin
          (map-set exchange-rates currency (merge rate-data {
            rate: new-rate,
            last-updated: stacks-block-height
          }))
          (ok new-rate))
      ERR_CURRENCY_NOT_FOUND
    )
  )
)

(define-public (toggle-currency-status (currency (string-ascii 10)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-currency-supported currency) ERR_CURRENCY_NOT_FOUND)
    
    (match (map-get? exchange-rates currency)
      rate-data
        (begin
          (map-set exchange-rates currency (merge rate-data {
            is-active: (not (get is-active rate-data)),
            last-updated: stacks-block-height
          }))
          (ok (not (get is-active rate-data))))
      ERR_CURRENCY_NOT_FOUND
    )
  )
)

(define-public (set-oracle-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= new-fee u1000) ERR_INVALID_RATE)
    (var-set oracle-fee new-fee)
    (ok new-fee)
  )
)

(define-public (batch-update-rates (usd-rate uint) (eur-rate uint) (gbp-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (and (> usd-rate u0) (> eur-rate u0) (> gbp-rate u0)) ERR_INVALID_RATE)
    
    (try! (update-exchange-rate "USD" usd-rate))
    (try! (update-exchange-rate "EUR" eur-rate))
    (try! (update-exchange-rate "GBP" gbp-rate))
    
    (ok {usd: usd-rate, eur: eur-rate, gbp: gbp-rate})
  )
)



(define-map insurance-policies
  uint
  {
    transfer-id: uint,
    policyholder: principal,
    coverage-amount: uint,
    premium-paid: uint,
    created-at: uint,
    expires-at: uint,
    status: (string-ascii 20),
    claim-amount: (optional uint)
  }
)

(define-map transfer-insurance uint uint)

(define-map user-policies principal (list 20 uint))

(define-read-only (get-policy (policy-id uint))
  (map-get? insurance-policies policy-id)
)

(define-read-only (get-transfer-insurance (transfer-id uint))
  (map-get? transfer-insurance transfer-id)
)

(define-read-only (calculate-premium (coverage-amount uint))
  (/ (* coverage-amount (var-get base-premium-rate)) u10000)
)

(define-read-only (get-insurance-pool-balance)
  (var-get insurance-pool)
)

(define-read-only (get-base-premium-rate)
  (var-get base-premium-rate)
)

(define-read-only (get-user-policies (user principal))
  (default-to (list) (map-get? user-policies user))
)

(define-read-only (is-transfer-insured (transfer-id uint))
  (is-some (map-get? transfer-insurance transfer-id))
)

(define-read-only (get-max-coverage)
  (var-get max-coverage-amount)
)

(define-public (purchase-insurance (transfer-id uint) (coverage-amount uint))
  (let (
    (policy-id (var-get next-policy-id))
    (premium (calculate-premium coverage-amount))
    (current-policies (get-user-policies tx-sender))
    (expires-at (+ stacks-block-height (var-get claim-period-blocks)))
  )
    (asserts! (> coverage-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (<= coverage-amount (var-get max-coverage-amount)) ERR_INVALID_AMOUNT)
    (asserts! (is-none (map-get? transfer-insurance transfer-id)) ERR_ALREADY_INSURED)
    (asserts! (> premium u0) ERR_INVALID_AMOUNT)
    
    (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
    
    (var-set insurance-pool (+ (var-get insurance-pool) premium))
    
    (map-set insurance-policies policy-id {
      transfer-id: transfer-id,
      policyholder: tx-sender,
      coverage-amount: coverage-amount,
      premium-paid: premium,
      created-at: stacks-block-height,
      expires-at: expires-at,
      status: "active",
      claim-amount: none
    })
    
    (map-set transfer-insurance transfer-id policy-id)
    
    (map-set user-policies tx-sender
      (unwrap-panic (as-max-len? (append current-policies policy-id) u20)))
    
    (var-set next-policy-id (+ policy-id u1))
    (ok policy-id)
  )
)

(define-public (file-insurance-claim (policy-id uint) (claim-amount uint))
  (let (
    (policy (unwrap! (map-get? insurance-policies policy-id) ERR_POLICY_NOT_FOUND))
  )
    (asserts! (is-eq tx-sender (get policyholder policy)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status policy) "active") ERR_CLAIM_ALREADY_PROCESSED)
    (asserts! (>= stacks-block-height (get created-at policy)) ERR_INVALID_TRANSFER)
    (asserts! (<= stacks-block-height (get expires-at policy)) ERR_POLICY_EXPIRED)
    (asserts! (<= claim-amount (get coverage-amount policy)) ERR_INVALID_AMOUNT)
    (asserts! (>= (var-get insurance-pool) claim-amount) ERR_INSUFFICIENT_FUNDS)
    
    (map-set insurance-policies policy-id (merge policy {
      status: "claimed",
      claim-amount: (some claim-amount)
    }))
    
    (var-set insurance-pool (- (var-get insurance-pool) claim-amount))
    
    (try! (as-contract (stx-transfer? claim-amount tx-sender (get policyholder policy))))
    (ok claim-amount)
  )
)

(define-public (cancel-policy (policy-id uint))
  (let (
    (policy (unwrap! (map-get? insurance-policies policy-id) ERR_POLICY_NOT_FOUND))
    (refund-amount (/ (get premium-paid policy) u2))
  )
    (asserts! (is-eq tx-sender (get policyholder policy)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status policy) "active") ERR_CLAIM_ALREADY_PROCESSED)
    (asserts! (< stacks-block-height (get expires-at policy)) ERR_POLICY_EXPIRED)
    
    (map-set insurance-policies policy-id (merge policy {
      status: "cancelled"
    }))
    
    (map-delete transfer-insurance (get transfer-id policy))
    
    (try! (as-contract (stx-transfer? refund-amount tx-sender (get policyholder policy))))
    (ok refund-amount)
  )
)

(define-public (update-premium-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= new-rate u500) ERR_INVALID_AMOUNT)
    (var-set base-premium-rate new-rate)
    (ok new-rate)
  )
)

(define-public (update-max-coverage (new-max uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> new-max u0) ERR_INVALID_AMOUNT)
    (var-set max-coverage-amount new-max)
    (ok new-max)
  )
)

(define-public (fund-insurance-pool (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set insurance-pool (+ (var-get insurance-pool) amount))
    (ok amount)
  )
)

(define-public (withdraw-from-pool (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= (var-get insurance-pool) amount) ERR_INSUFFICIENT_FUNDS)
    (var-set insurance-pool (- (var-get insurance-pool) amount))
    (try! (as-contract (stx-transfer? amount tx-sender CONTRACT_OWNER)))
    (ok amount)
  )
)
