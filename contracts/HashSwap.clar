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
(define-constant ERR_INVALID_AMOUNT (err u110))
(define-constant ERR_SWAP_NOT_OPEN (err u111))
(define-constant ERR_INSUFFICIENT_FUNDS (err u112))
(define-constant ERR_CLAIM_TOO_SMALL (err u113))
(define-constant ERR_MAX_CLAIMS_REACHED (err u114))
(define-constant ERR_EMERGENCY_NOT_ENABLED (err u115))
(define-constant ERR_EMERGENCY_TOO_EARLY (err u116))

(define-data-var admin principal tx-sender)
(define-data-var paused bool false)

;; IMPROVEMENT 3: Emergency recovery settings
(define-data-var emergency-timeout uint u52560) ;; ~1 year in blocks
(define-data-var recovery-enabled bool false)

;; Optional: store pre-approved recipient addresses
(define-map whitelisted-recipients principal bool)

;; IMPROVEMENT 3: Enhanced swap states with partial claim support
(define-map swaps
  (buff 32)
  {
    sender: principal,
    amount: uint,
    timeout: uint,
    status: (string-ascii 12), ;; "open", "claimed", "refunded", "recovered"
    memo: (optional (buff 100)),
    recipient: (optional principal),
    ;; New fields for advanced features
    original-amount: uint,
    remaining-amount: uint,
    min-claim-amount: uint,
    max-claims: uint,
    claim-count: uint,
    created-at: uint,
    last-activity: uint
  }
)

;; IMPROVEMENT 3: Track individual claims for transparency
(define-map claim-history 
  {hash: (buff 32), claim-id: uint}
  {claimer: principal, amount: uint, timestamp: uint}
)

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

;; Admin can resume the contract - FIXED: removed assert-not-paused check
(define-public (unpause)
  (begin
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

;; IMPROVEMENT 1: Fixed lock-funds - now actually transfers STX to contract
(define-public (lock-funds
    (hash-secret (buff 32))
    (timeout-block uint)
    (recipient (optional principal))
    (memo (optional (buff 100)))
    (amount uint)
  )
  (begin
    (try! (assert-not-paused))
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> timeout-block stacks-block-height) ERR_INVALID_TIMEOUT)
    (match (map-get? swaps hash-secret)
      existing
      ERR_ALREADY_EXISTS
      (begin
        ;; CRITICAL FIX: Actually transfer STX to the contract
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        ;; Store swap with enhanced structure (backward compatible)
        (map-insert swaps hash-secret {
          sender: tx-sender,
          amount: amount,
          timeout: timeout-block,
          status: "open",
          memo: memo,
          recipient: recipient,
          ;; New fields for advanced features
          original-amount: amount,
          remaining-amount: amount,
          min-claim-amount: amount, ;; Full amount for basic swaps
          max-claims: u1, ;; Single claim for basic swaps
          claim-count: u0,
          created-at: stacks-block-height,
          last-activity: stacks-block-height
        })
        (print {event: "swap-created", hash: hash-secret, sender: tx-sender, timeout: timeout-block, amount: amount})
        (ok true)
      )
    )
  )
)

;; IMPROVEMENT 3: Advanced lock with partial claim configuration
(define-public (lock-funds-advanced
    (hash-secret (buff 32))
    (timeout-block uint)
    (recipient (optional principal))
    (memo (optional (buff 100)))
    (amount uint)
    (min-claim-amount uint)
    (max-claims uint)
  )
  (begin
    (try! (assert-not-paused))
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> min-claim-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (<= min-claim-amount amount) ERR_INVALID_AMOUNT)
    (asserts! (> max-claims u0) ERR_INVALID_AMOUNT)
    (asserts! (> timeout-block stacks-block-height) ERR_INVALID_TIMEOUT)
    (match (map-get? swaps hash-secret)
      existing
      ERR_ALREADY_EXISTS
      (begin
        ;; Transfer STX to contract
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        (map-insert swaps hash-secret {
          sender: tx-sender,
          amount: amount,
          timeout: timeout-block,
          status: "open",
          memo: memo,
          recipient: recipient,
          original-amount: amount,
          remaining-amount: amount,
          min-claim-amount: min-claim-amount,
          max-claims: max-claims,
          claim-count: u0,
          created-at: stacks-block-height,
          last-activity: stacks-block-height
        })
        
        (print {event: "swap-created-advanced", hash: hash-secret, amount: amount, max-claims: max-claims, min-claim: min-claim-amount})
        (ok true)
      )
    )
  )
)

;; CRITICAL FIX: Fixed claim function - now properly transfers from contract to claimer
(define-public (claim (preimage (buff 32)))
  (let (
    (hash (sha256 preimage))
    (claimer tx-sender) ;; Capture the claimer's address before as-contract
  )
    (match (map-get? swaps hash)
      swap-data
      (begin
        (try! (assert-not-paused))
        (asserts! (is-eq (get status swap-data) "open") ERR_SWAP_NOT_OPEN)
        
        ;; Recipient match check if specified
        (let ((recipient-opt (get recipient swap-data)))
          (if (is-some recipient-opt)
            (asserts! (is-eq claimer (unwrap! recipient-opt ERR_NOT_RECIPIENT)) ERR_NOT_RECIPIENT)
            true
          )
        )
        
        ;; For backward compatibility, claim the full remaining amount
        (let ((claim-amount (get remaining-amount swap-data)))
          ;; CRITICAL FIX: Transfer from contract to claimer using captured address
          (try! (as-contract (stx-transfer? claim-amount tx-sender claimer)))
          
          ;; Update swap status
          (map-set swaps hash (merge swap-data { 
            status: "claimed",
            remaining-amount: u0,
            claim-count: u1,
            last-activity: stacks-block-height
          }))
          
          ;; Record claim history
          (map-insert claim-history 
            {hash: hash, claim-id: u1}
            {claimer: claimer, amount: claim-amount, timestamp: stacks-block-height}
          )
          
          (print {event: "swap-claimed", hash: hash, recipient: claimer, amount: claim-amount})
          (ok true)
        )
      )
      ERR_INVALID_PREIMAGE
    )
  )
)

;; CRITICAL FIX: Fixed partial-claim function - now properly transfers from contract to claimer
(define-public (partial-claim (preimage (buff 32)) (claim-amount uint))
  (let (
    (hash (sha256 preimage))
    (claimer tx-sender) ;; Capture the claimer's address before as-contract
  )
    (match (map-get? swaps hash)
      swap-data
      (begin
        (try! (assert-not-paused))
        (asserts! (is-eq (get status swap-data) "open") ERR_SWAP_NOT_OPEN)
        (asserts! (>= (get remaining-amount swap-data) claim-amount) ERR_INSUFFICIENT_FUNDS)
        (asserts! (>= claim-amount (get min-claim-amount swap-data)) ERR_CLAIM_TOO_SMALL)
        (asserts! (< (get claim-count swap-data) (get max-claims swap-data)) ERR_MAX_CLAIMS_REACHED)
        
        ;; Recipient validation
        (match (get recipient swap-data)
          some-recipient (asserts! (is-eq claimer some-recipient) ERR_NOT_RECIPIENT)
          true
        )
        
        ;; CRITICAL FIX: Transfer claimed amount from contract to claimer using captured address
        (try! (as-contract (stx-transfer? claim-amount tx-sender claimer)))
        
        ;; Update swap data
        (let (
          (new-remaining (- (get remaining-amount swap-data) claim-amount))
          (new-claim-count (+ (get claim-count swap-data) u1))
          (new-status (if (is-eq new-remaining u0) "claimed" "open"))
        )
          (map-set swaps hash (merge swap-data {
            remaining-amount: new-remaining,
            claim-count: new-claim-count,
            status: new-status,
            last-activity: stacks-block-height
          }))
          
          ;; Record claim history
          (map-insert claim-history 
            {hash: hash, claim-id: new-claim-count}
            {claimer: claimer, amount: claim-amount, timestamp: stacks-block-height}
          )
          
          (print {event: "partial-claim", hash: hash, amount: claim-amount, remaining: new-remaining, claimer: claimer})
          (ok true)
        )
      )
      ERR_INVALID_PREIMAGE
    )
  )
)

;; CRITICAL FIX: Fixed refund function - now properly transfers from contract to sender
(define-public (refund (hash-secret (buff 32)))
  (let ((refunder tx-sender)) ;; Capture the refunder's address before as-contract
    (match (map-get? swaps hash-secret)
      swap-data
      (begin
        (try! (assert-not-paused))
        (asserts! (is-eq (get status swap-data) "open") ERR_SWAP_NOT_OPEN)
        (asserts! (>= stacks-block-height (get timeout swap-data)) ERR_TOO_EARLY)
        (asserts! (is-eq refunder (get sender swap-data)) ERR_NOT_SENDER)
        
        ;; CRITICAL FIX: Transfer remaining amount from contract back to sender
        (let ((refund-amount (get remaining-amount swap-data)))
          (try! (as-contract (stx-transfer? refund-amount tx-sender (get sender swap-data))))
          
          (map-set swaps hash-secret (merge swap-data { 
            status: "refunded",
            remaining-amount: u0,
            last-activity: stacks-block-height
          }))
          
          (print {event: "swap-refunded", hash: hash-secret, sender: refunder, amount: refund-amount})
          (ok true)
        )
      )
      ERR_SWAP_NOT_FOUND
    )
  )
)

;; CRITICAL FIX: Fixed emergency recovery function - now properly transfers from contract to sender
(define-public (emergency-recover (hash-secret (buff 32)))
  (let ((recoverer tx-sender)) ;; Capture the recoverer's address before as-contract
    (match (map-get? swaps hash-secret)
      swap-data
      (begin
        (asserts! (var-get recovery-enabled) ERR_EMERGENCY_NOT_ENABLED)
        (asserts! (is-eq (get status swap-data) "open") ERR_SWAP_NOT_OPEN)
        (asserts! (> (- stacks-block-height (get created-at swap-data)) (var-get emergency-timeout)) ERR_EMERGENCY_TOO_EARLY)
        
        ;; Only admin or original sender can recover
        (asserts! (or (is-eq recoverer (var-get admin)) 
                      (is-eq recoverer (get sender swap-data))) ERR_UNAUTHORIZED)
        
        ;; Transfer remaining funds to sender
        (let ((recovery-amount (get remaining-amount swap-data)))
          (try! (as-contract (stx-transfer? recovery-amount tx-sender (get sender swap-data))))
          
          (map-set swaps hash-secret (merge swap-data { 
            status: "recovered",
            remaining-amount: u0,
            last-activity: stacks-block-height
          }))
          
          (print {event: "emergency-recovery", hash: hash-secret, recovered-amount: recovery-amount, recoverer: recoverer})
          (ok true)
        )
      )
      ERR_SWAP_NOT_FOUND
    )
  )
)

;; IMPROVEMENT 3: Admin functions for emergency settings
(define-public (toggle-recovery (enabled bool))
  (begin
    (try! (assert-admin))
    (var-set recovery-enabled enabled)
    (print {event: "recovery-toggled", enabled: enabled})
    (ok true)
  )
)

(define-public (set-emergency-timeout (blocks uint))
  (begin
    (try! (assert-admin))
    (asserts! (> blocks u1000) ERR_INVALID_TIMEOUT) ;; Minimum ~1 week
    (var-set emergency-timeout blocks)
    (print {event: "emergency-timeout-updated", blocks: blocks})
    (ok true)
  )
)

;; View function: get swap details (backward compatible)
(define-read-only (get-swap (hash-secret (buff 32)))
  (match (map-get? swaps hash-secret)
    swap
    (ok swap)
    ERR_SWAP_NOT_FOUND
  )
)

;; IMPROVEMENT 3: New view functions for advanced features
(define-read-only (get-claim-history (hash-secret (buff 32)) (claim-id uint))
  (ok (map-get? claim-history {hash: hash-secret, claim-id: claim-id}))
)

(define-read-only (get-swap-stats (hash-secret (buff 32)))
  (match (map-get? swaps hash-secret)
    swap-data
    (ok {
      progress: (if (> (get original-amount swap-data) u0)
                   (/ (* (- (get original-amount swap-data) (get remaining-amount swap-data)) u100) (get original-amount swap-data))
                   u0),
      claims-used: (get claim-count swap-data),
      claims-remaining: (- (get max-claims swap-data) (get claim-count swap-data)),
      age-blocks: (- stacks-block-height (get created-at swap-data))
    })
    ERR_SWAP_NOT_FOUND
  )
)

(define-read-only (get-contract-balance)
  (ok (stx-get-balance (as-contract tx-sender)))
)

;; Read contract status
(define-read-only (is-paused) (ok (var-get paused)))

;; Get admin address
(define-read-only (get-admin) (ok (var-get admin)))

;; Read recipient whitelist status
(define-read-only (is-whitelisted (addr principal))
  (ok (map-get? whitelisted-recipients addr))
)

;; IMPROVEMENT 3: Read emergency settings
(define-read-only (get-emergency-settings)
  (ok {
    recovery-enabled: (var-get recovery-enabled),
    emergency-timeout: (var-get emergency-timeout)
  })
)
