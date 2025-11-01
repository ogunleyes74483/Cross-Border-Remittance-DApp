(define-constant ERR_UNAUTHORIZED (err u500))
(define-constant ERR_INVALID_AMOUNT (err u501))
(define-constant ERR_INSUFFICIENT_POOL (err u502))
(define-constant ERR_NOT_ELIGIBLE (err u503))
(define-constant ERR_LOCK_ACTIVE (err u504))
(define-constant ERR_LOCK_NOT_EXPIRED (err u505))

(define-constant CONTRACT_OWNER tx-sender)
(define-constant MIN_TRANSFERS_FOR_REFUND u5)
(define-constant BASE_REFUND_RATE u1000)
(define-constant LOCKED_REFUND_BONUS u500)
(define-constant LOCK_PERIOD_BLOCKS u4320)

(define-data-var refund-pool-balance uint u0)
(define-data-var total-refunds-claimed uint u0)
(define-data-var refund-enabled bool true)

(define-map user-stats
  principal
  {
    transfer-count: uint,
    total-fees-paid: uint,
    total-refunds-claimed: uint,
    last-claim-block: uint
  }
)

(define-map locked-eligibility
  principal
  {
    locked-at: uint,
    unlock-at: uint,
    bonus-rate: uint,
    is-active: bool
  }
)

(define-read-only (get-pool-balance)
  (var-get refund-pool-balance)
)

(define-read-only (get-user-stats (user principal))
  (default-to {transfer-count: u0, total-fees-paid: u0, total-refunds-claimed: u0, last-claim-block: u0}
    (map-get? user-stats user))
)

(define-read-only (get-locked-status (user principal))
  (map-get? locked-eligibility user)
)

(define-read-only (calculate-refund-amount (user principal))
  (let (
    (stats (get-user-stats user))
    (fees-paid (get total-fees-paid stats))
    (lock-info (map-get? locked-eligibility user))
    (base-refund (/ (* fees-paid BASE_REFUND_RATE) u10000))
  )
    (match lock-info
      lock-data
        (if (and (get is-active lock-data) (>= stacks-block-height (get unlock-at lock-data)))
          (+ base-refund (/ (* fees-paid (get bonus-rate lock-data)) u10000))
          base-refund)
      base-refund)
  )
)

(define-public (fund-pool (amount uint))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set refund-pool-balance (+ (var-get refund-pool-balance) amount))
    (ok amount)
  )
)

(define-public (record-transfer-fee (user principal) (fee-amount uint))
  (let (
    (current-stats (get-user-stats user))
  )
    (asserts! (> fee-amount u0) ERR_INVALID_AMOUNT)
    (map-set user-stats user {
      transfer-count: (+ (get transfer-count current-stats) u1),
      total-fees-paid: (+ (get total-fees-paid current-stats) fee-amount),
      total-refunds-claimed: (get total-refunds-claimed current-stats),
      last-claim-block: (get last-claim-block current-stats)
    })
    (var-set refund-pool-balance (+ (var-get refund-pool-balance) fee-amount))
    (ok true)
  )
)

(define-public (lock-for-bonus)
  (let (
    (stats (get-user-stats tx-sender))
    (unlock-block (+ stacks-block-height LOCK_PERIOD_BLOCKS))
  )
    (asserts! (>= (get transfer-count stats) MIN_TRANSFERS_FOR_REFUND) ERR_NOT_ELIGIBLE)
    (asserts! (is-none (map-get? locked-eligibility tx-sender)) ERR_LOCK_ACTIVE)
    (map-set locked-eligibility tx-sender {
      locked-at: stacks-block-height,
      unlock-at: unlock-block,
      bonus-rate: LOCKED_REFUND_BONUS,
      is-active: true
    })
    (ok unlock-block)
  )
)

(define-public (claim-refund)
  (let (
    (stats (get-user-stats tx-sender))
    (refund-amount (calculate-refund-amount tx-sender))
  )
    (asserts! (var-get refund-enabled) ERR_UNAUTHORIZED)
    (asserts! (>= (get transfer-count stats) MIN_TRANSFERS_FOR_REFUND) ERR_NOT_ELIGIBLE)
    (asserts! (> refund-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= (var-get refund-pool-balance) refund-amount) ERR_INSUFFICIENT_POOL)
    (map-set user-stats tx-sender (merge stats {
      total-refunds-claimed: (+ (get total-refunds-claimed stats) refund-amount),
      total-fees-paid: u0,
      last-claim-block: stacks-block-height
    }))
    (match (map-get? locked-eligibility tx-sender)
      lock-data
        (map-set locked-eligibility tx-sender (merge lock-data {is-active: false}))
      true)
    (var-set refund-pool-balance (- (var-get refund-pool-balance) refund-amount))
    (var-set total-refunds-claimed (+ (var-get total-refunds-claimed) refund-amount))
    (try! (as-contract (stx-transfer? refund-amount tx-sender tx-sender)))
    (ok refund-amount)
  )
)
