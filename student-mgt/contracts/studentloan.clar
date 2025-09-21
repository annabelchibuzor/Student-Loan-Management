;; Student Loan Management Smart Contract

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_LOAN_NOT_FOUND (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_LOAN_ALREADY_EXISTS (err u103))
(define-constant ERR_INSUFFICIENT_BALANCE (err u104))
(define-constant ERR_LOAN_ALREADY_PAID (err u105))
(define-constant ERR_INVALID_INTEREST_RATE (err u106))
(define-constant ERR_PAYMENT_TOO_LARGE (err u107))
(define-constant ERR_INVALID_TERM (err u108))
(define-constant ERR_INVALID_COLLATERAL (err u109))
(define-constant ERR_INVALID_LOAN_ID (err u110))
(define-constant ERR_INVALID_PRINCIPAL (err u111))
(define-constant MIN_LOAN_AMOUNT u1000000) ;; 1 STX minimum
(define-constant MAX_LOAN_AMOUNT u1000000000000) ;; 1M STX maximum
(define-constant MAX_INTEREST_RATE u2000) ;; 20% max (basis points)
(define-constant MIN_TERM_BLOCKS u52560) ;; 1 year minimum
(define-constant MAX_TERM_BLOCKS u1577880) ;; 30 years maximum
(define-constant MAX_COLLATERAL u1000000000000) ;; 1M STX maximum
(define-constant MAX_PAYMENT_AMOUNT u1000000000000) ;; 1M STX maximum
(define-constant BLOCKS_PER_YEAR u52560) ;; Approximate blocks in a year

;; Data Variables
(define-data-var loan-counter uint u0)
(define-data-var total-loans-issued uint u0)
(define-data-var total-amount-repaid uint u0)

;; Data Maps
(define-map loans uint {
    borrower: principal,
    original-amount: uint,
    current-balance: uint,
    interest-rate: uint, ;; in basis points (100 = 1%)
    issue-block: uint,
    term-blocks: uint,
    monthly-payment: uint,
    payments-made: uint,
    total-payments: uint,
    is-active: bool,
    collateral: uint
})

(define-map borrower-loans principal (list 10 uint))
(define-map loan-payments uint (list 50 {block: uint, amount: uint, interest: uint, principal: uint}))
(define-map approved-lenders principal bool)

;; Private Functions
(define-private (min (a uint) (b uint))
    (if (<= a b) a b))

(define-private (max (a uint) (b uint))
    (if (>= a b) a b))

(define-private (calculate-interest (principal uint) (rate uint) (blocks uint))
    (let ((annual-interest (/ (* principal rate) u10000))
          (block-interest (/ annual-interest BLOCKS_PER_YEAR)))
        (* block-interest blocks)))

(define-private (calculate-monthly-payment (principal uint) (rate uint) (term uint))
    (let ((monthly-rate (/ rate u1200)) ;; Convert annual rate to monthly
          (num-payments (/ term u4380))) ;; Approximate blocks per month
        (if (is-eq monthly-rate u0)
            (/ principal num-payments)
            (if (> num-payments u0)
                (/ (* principal monthly-rate) 
                   (- u1 (/ u1 (+ u1 (* monthly-rate num-payments)))))
                u0))))

(define-private (update-borrower-loans (borrower principal) (loan-id uint))
    (let ((current-loans (default-to (list) (map-get? borrower-loans borrower))))
        (if (< (len current-loans) u10)
            (ok (map-set borrower-loans borrower (unwrap! (as-max-len? (append current-loans loan-id) u10) (err u999))))
            (err u998))))

(define-private (validate-loan-inputs (amount uint) (interest-rate uint) (term-blocks uint) (collateral uint))
    (and 
        (>= amount MIN_LOAN_AMOUNT)
        (<= amount MAX_LOAN_AMOUNT)
        (<= interest-rate MAX_INTEREST_RATE)
        (>= term-blocks MIN_TERM_BLOCKS)
        (<= term-blocks MAX_TERM_BLOCKS)
        (<= collateral MAX_COLLATERAL)))

(define-private (validate-payment-inputs (loan-id uint) (payment-amount uint))
    (and 
        (> loan-id u0)
        (<= loan-id (var-get loan-counter))
        (> payment-amount u0)
        (<= payment-amount MAX_PAYMENT_AMOUNT)))

;; Read-only Functions
(define-read-only (get-loan (loan-id uint))
    (if (and (> loan-id u0) (<= loan-id (var-get loan-counter)))
        (map-get? loans loan-id)
        none))

(define-read-only (get-borrower-loans (borrower principal))
    (default-to (list) (map-get? borrower-loans borrower)))

(define-read-only (get-loan-payments (loan-id uint))
    (if (and (> loan-id u0) (<= loan-id (var-get loan-counter)))
        (default-to (list) (map-get? loan-payments loan-id))
        (list)))

(define-read-only (get-contract-stats)
    {
        total-loans: (var-get loan-counter),
        total-issued: (var-get total-loans-issued),
        total-repaid: (var-get total-amount-repaid),
        contract-balance: (stx-get-balance (as-contract tx-sender))
    })

(define-read-only (calculate-current-balance (loan-id uint))
    (if (and (> loan-id u0) (<= loan-id (var-get loan-counter)))
        (match (map-get? loans loan-id)
            loan-data
            (let ((blocks-elapsed (- block-height (get issue-block loan-data)))
                  (interest (calculate-interest (get current-balance loan-data) 
                                              (get interest-rate loan-data) 
                                              blocks-elapsed)))
                (ok (+ (get current-balance loan-data) interest)))
            ERR_LOAN_NOT_FOUND)
        ERR_INVALID_LOAN_ID))

(define-read-only (is-loan-overdue (loan-id uint))
    (if (and (> loan-id u0) (<= loan-id (var-get loan-counter)))
        (match (map-get? loans loan-id)
            loan-data
            (let ((expected-payments (/ (- block-height (get issue-block loan-data)) u4380))
                  (actual-payments (get payments-made loan-data)))
                (ok (and (get is-active loan-data) (> expected-payments actual-payments))))
            ERR_LOAN_NOT_FOUND)
        ERR_INVALID_LOAN_ID))

;; Public Functions
(define-public (create-loan (borrower principal) (amount uint) (interest-rate uint) (term-blocks uint) (collateral uint))
    (let ((loan-id (+ (var-get loan-counter) u1)))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (validate-loan-inputs amount interest-rate term-blocks collateral) ERR_INVALID_AMOUNT)
        (asserts! (< (len (get-borrower-loans borrower)) u10) ERR_LOAN_ALREADY_EXISTS)
        
        (let ((validated-amount (min amount MAX_LOAN_AMOUNT))
              (validated-rate (min interest-rate MAX_INTEREST_RATE))
              (validated-term (max (min term-blocks MAX_TERM_BLOCKS) MIN_TERM_BLOCKS))
              (validated-collateral (min collateral MAX_COLLATERAL)))
            
            (let ((monthly-payment (calculate-monthly-payment validated-amount validated-rate validated-term))
                  (total-payments (/ validated-term u4380)))
                
                (try! (stx-transfer? validated-amount (as-contract tx-sender) borrower))
                
                (map-set loans loan-id {
                    borrower: borrower,
                    original-amount: validated-amount,
                    current-balance: validated-amount,
                    interest-rate: validated-rate,
                    issue-block: block-height,
                    term-blocks: validated-term,
                    monthly-payment: monthly-payment,
                    payments-made: u0,
                    total-payments: total-payments,
                    is-active: true,
                    collateral: validated-collateral
                })
                
                (try! (update-borrower-loans borrower loan-id))
                (var-set loan-counter loan-id)
                (var-set total-loans-issued (+ (var-get total-loans-issued) validated-amount))
                (ok loan-id)))))

(define-public (make-payment (loan-id uint) (payment-amount uint))
    (begin
        (asserts! (validate-payment-inputs loan-id payment-amount) ERR_INVALID_AMOUNT)
        (let ((validated-loan-id (max u1 (min loan-id (var-get loan-counter))))
              (validated-payment (min payment-amount MAX_PAYMENT_AMOUNT)))
            
            (match (map-get? loans validated-loan-id)
                loan-data
                (let ((borrower (get borrower loan-data))
                      (current-balance (get current-balance loan-data))
                      (blocks-since-issue (- block-height (get issue-block loan-data)))
                      (interest-accrued (calculate-interest current-balance 
                                                         (get interest-rate loan-data)
                                                         blocks-since-issue))
                      (total-owed (+ current-balance interest-accrued))
                      (safe-payment (min validated-payment total-owed))
                      (interest-payment (min safe-payment interest-accrued))
                      (principal-payment (if (> safe-payment interest-accrued) 
                                           (- safe-payment interest-accrued) 
                                           u0))
                      (new-balance (if (> current-balance principal-payment) 
                                     (- current-balance principal-payment) 
                                     u0))
                      (current-payments (default-to (list) (map-get? loan-payments validated-loan-id))))
                    
                    (asserts! (is-eq tx-sender borrower) ERR_NOT_AUTHORIZED)
                    (asserts! (> safe-payment u0) ERR_INVALID_AMOUNT)
                    (asserts! (get is-active loan-data) ERR_LOAN_ALREADY_PAID)
                    
                    (try! (stx-transfer? safe-payment tx-sender (as-contract tx-sender)))
                    
                    (let ((new-payment {block: block-height, amount: safe-payment, 
                                       interest: interest-payment, principal: principal-payment})
                          (updated-payments (unwrap! (as-max-len? (append current-payments new-payment) u50) 
                                                   ERR_LOAN_NOT_FOUND)))
                        
                        (map-set loan-payments validated-loan-id updated-payments)
                        (map-set loans validated-loan-id (merge loan-data {
                            current-balance: new-balance,
                            payments-made: (+ (get payments-made loan-data) u1),
                            is-active: (> new-balance u0)
                        }))
                        
                        (var-set total-amount-repaid (+ (var-get total-amount-repaid) safe-payment))
                        (ok {payment-id: (len updated-payments), remaining-balance: new-balance})))
                ERR_LOAN_NOT_FOUND))))

(define-public (approve-lender (lender principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (not (is-eq lender 'SP000000000000000000002Q6VF78)) ERR_INVALID_PRINCIPAL)
        (map-set approved-lenders lender true)
        (ok true)))

(define-public (fund-contract (amount uint))
    (begin
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (<= amount MAX_LOAN_AMOUNT) ERR_INVALID_AMOUNT)
        (let ((validated-amount (min amount MAX_LOAN_AMOUNT)))
            (try! (stx-transfer? validated-amount tx-sender (as-contract tx-sender)))
            (ok validated-amount))))

(define-public (liquidate-loan (loan-id uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (and (> loan-id u0) (<= loan-id (var-get loan-counter))) ERR_INVALID_LOAN_ID)
        (let ((validated-loan-id (max u1 (min loan-id (var-get loan-counter)))))
            (match (map-get? loans validated-loan-id)
                loan-data
                (begin
                    (asserts! (get is-active loan-data) ERR_LOAN_ALREADY_PAID)
                    (asserts! (unwrap! (is-loan-overdue validated-loan-id) ERR_LOAN_NOT_FOUND) ERR_NOT_AUTHORIZED)
                    
                    (map-set loans validated-loan-id (merge loan-data {is-active: false}))
                    (ok (get collateral loan-data)))
                ERR_LOAN_NOT_FOUND))))

(define-public (emergency-withdraw (amount uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (<= amount MAX_LOAN_AMOUNT) ERR_INVALID_AMOUNT)
        (let ((contract-balance (stx-get-balance (as-contract tx-sender)))
              (validated-amount (min amount (min MAX_LOAN_AMOUNT contract-balance))))
            (asserts! (> validated-amount u0) ERR_INSUFFICIENT_BALANCE)
            (try! (as-contract (stx-transfer? validated-amount tx-sender CONTRACT_OWNER)))
            (ok validated-amount))))