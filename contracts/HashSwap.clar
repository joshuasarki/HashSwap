(define-constant ERR_ALREADY_EXISTS (err u100))
(define-constant ERR_INVALID_PREIMAGE (err u101))
(define-constant ERR_TOO_EARLY (err u102))
(define-constant ERR_NOT_SENDER (err u103))
(define-constant ERR_NOT_RECIPIENT (err u104))
(define-constant ERR_SWAP_NOT_FOUND (err u105))
(define-constant ERR_CONTRACT_PAUSED (err u106))
(define-constant ERR_INVALID_TIMEOUT (err u107))
(define-constant ERR_UNAUTHORIZED (err u108))
(define-constant ERR_INVALID_ADDRESS (err u109))

(define-data-var admin principal tx-sender)
(define-data-var paused bool false)

;; Optional: store pre-approved recipient addresses
(define-map whitelisted-recipients principal bool)

;; Swap states
(define-map swaps
  (buff 32)
  {
    sender: principal,
    amount: uint,
    timeout: uint,
    status: (string-ascii 12), ;; "open", "claimed", "refunded"
    memo: (optional (buff 100)),
    recipient: (optional principal)
  }
)

;; Events (Clarity does not support custom event definitions; use print for event emission)
;; Example: (print {event: "swap-created", hash: hash, sender: sender, timeout: timeout, amount: amount})
;; Example: (print {event: "swap-claimed", hash: hash, recipient: recipient})
;; Example: (print {event: "swap-refunded", hash: hash, sender: sender})
;; Example: (print {event: "swap-paused"})
;; Example: (print {event: "swap-unpaused"})

;; Helper to check if contract is paused
(define-private (assert-not-paused)
  (begin
    (asserts! (not (var-get paused)) ERR_CONTRACT_PAUSED)
    (ok true)
  )
)

;; Only admin
(define-private (assert-admin)
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) ERR_UNAUTHORIZED)
    (ok true)
  )
)

;; Admin can pause the contract
(define-public (pause)
  (begin
    (try! (assert-not-paused))
    (try! (assert-admin))
    (var-set paused true)
    (print {event: "swap-paused"})
    (ok true)
  )
)

;; Admin can resume the contract
(define-public (unpause)
  (begin
    (try! (assert-not-paused))
    (try! (assert-admin))
    (var-set paused false)
    (print {event: "swap-unpaused"})
    (ok true)
  )
)

;; Admin can set whitelisted addresses (optional feature)
(define-public (add-recipient (addr principal))
  (begin
    (try! (assert-not-paused))
    (try! (assert-admin))
    (map-insert whitelisted-recipients addr true)
    (ok true)
  )
)

;; Lock STX into swap contract
(define-public (lock-funds
    (hash-secret (buff 32))
    (timeout-block uint)
    (recipient (optional principal))
    (memo (optional (buff 100)))
    (amount uint)
  )
  (begin
    (try! (assert-not-paused))
    (asserts! (> timeout-block stacks-block-height) ERR_INVALID_TIMEOUT)
    (match (map-get? swaps hash-secret)
      existing
      ERR_ALREADY_EXISTS
      (begin
        (map-insert swaps hash-secret {
          sender: tx-sender,
          amount: amount,
          timeout: timeout-block,
          status: "open",
          memo: memo,
          recipient: recipient
        })
        (print {event: "swap-created", hash: hash-secret, sender: tx-sender, timeout: timeout-block, amount: amount})
        (ok true)
      )
    )
  )
)

;; Claim STX with preimage and optional recipient check
(define-public (claim (preimage (buff 32)))
  (let (
    (hash (sha256 preimage))
  )
    (match (map-get? swaps hash)
      swap-data
      (begin
        (try! (assert-not-paused))
        ;; Recipient match check if specified
        (let ((recipient-opt (get recipient swap-data)))
          (if (is-some recipient-opt)
            (asserts! (is-eq tx-sender (unwrap! recipient-opt ERR_NOT_RECIPIENT)) ERR_NOT_RECIPIENT)
            (asserts! true ERR_NOT_RECIPIENT)
          )
        )
        ;; Optional whitelist check
        (let ((whitelist-check true)) ;; Default to true if not enforcing
          whitelist-check
        )
        (try! (stx-transfer? (get amount swap-data) (get sender swap-data) tx-sender))
        (map-insert swaps hash (merge swap-data { status: "claimed" }))
        (print {event: "swap-claimed", hash: hash, recipient: tx-sender})
        (ok true)
      )
      ERR_INVALID_PREIMAGE
    )
  )
)

;; Refund STX after timeout
(define-public (refund (hash-secret (buff 32)))
  (match (map-get? swaps hash-secret)
    swap-data
    (begin
      (try! (assert-not-paused))
      (asserts! (>= stacks-block-height (get timeout swap-data)) ERR_TOO_EARLY)
      (asserts! (is-eq tx-sender (get sender swap-data)) ERR_NOT_SENDER)
      (try! (stx-transfer? (get amount swap-data) tx-sender tx-sender))
      (map-insert swaps hash-secret (merge swap-data { status: "refunded" }))
      (print {event: "swap-refunded", hash: hash-secret, sender: tx-sender})
      (ok true)
    )
    ERR_SWAP_NOT_FOUND
  )
)

;; View function: get swap details (minus preimage!)
(define-read-only (get-swap (hash-secret (buff 32)))
  (match (map-get? swaps hash-secret)
    swap
    (ok swap)
    ERR_SWAP_NOT_FOUND
  )
)

;; Read contract status
(define-read-only (is-paused) (ok (var-get paused)))

;; Get admin address
(define-read-only (get-admin) (ok (var-get admin)))

;; Read recipient whitelist status
(define-read-only (is-whitelisted (addr principal))
  (ok (map-get? whitelisted-recipients addr))
)
