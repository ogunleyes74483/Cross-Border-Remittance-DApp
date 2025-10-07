(define-constant ERR_INVALID_AMOUNT (err u101))
(define-constant ERR_INSUFFICIENT_BALANCE (err u105))

(define-constant POINTS_PER_TRANSFER u10)
(define-constant POINTS_PER_CLAIM u5)
(define-constant POINTS_PER_INSURANCE u15)
(define-constant POINTS_TO_DISCOUNT_RATE u100)
(define-constant MAX_DISCOUNT_PERCENTAGE u50)

(define-map loyalty-points principal uint)
(define-map total-points-earned principal uint)

(define-read-only (get-loyalty-points (user principal))
  (default-to u0 (map-get? loyalty-points user))
)

(define-read-only (get-total-points-earned (user principal))
  (default-to u0 (map-get? total-points-earned user))
)

(define-read-only (calculate-discount-percentage (points uint))
  (let (
    (discount-percent (/ points POINTS_TO_DISCOUNT_RATE))
  )
    (if (> discount-percent MAX_DISCOUNT_PERCENTAGE)
      MAX_DISCOUNT_PERCENTAGE
      discount-percent)
  )
)

(define-read-only (calculate-discounted-fee (original-fee uint) (user principal))
  (let (
    (user-points (get-loyalty-points user))
    (discount-percent (calculate-discount-percentage user-points))
    (discount-amount (/ (* original-fee discount-percent) u100))
  )
    (if (> discount-amount original-fee)
      u0
      (- original-fee discount-amount))
  )
)

(define-private (award-points (user principal) (points uint))
  (let (
    (current-points (get-loyalty-points user))
    (total-earned (get-total-points-earned user))
  )
    (map-set loyalty-points user (+ current-points points))
    (map-set total-points-earned user (+ total-earned points))
    (ok points)
  )
)

(define-public (redeem-points-for-discount (points-to-redeem uint))
  (let (
    (current-points (get-loyalty-points tx-sender))
  )
    (asserts! (> points-to-redeem u0) ERR_INVALID_AMOUNT)
    (asserts! (>= current-points points-to-redeem) ERR_INSUFFICIENT_BALANCE)
    (map-set loyalty-points tx-sender (- current-points points-to-redeem))
    (ok points-to-redeem)
  )
)

(define-public (check-loyalty-status (user principal))
  (let (
    (current-points (get-loyalty-points user))
    (total-earned (get-total-points-earned user))
    (discount-percent (calculate-discount-percentage current-points))
  )
    (ok {
      current-points: current-points,
      total-earned: total-earned,
      discount-percentage: discount-percent
    })
  )
)
