;; Automated Contract Lifecycle Management
;; A smart contract for managing contract lifecycles with compliance tracking and renewal alerts

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-invalid-contract-id (err u102))
(define-constant err-contract-not-found (err u103))
(define-constant err-invalid-data (err u104))
(define-constant err-contract-expired (err u105))


;; Contract status constants
(define-constant status-active u1)
(define-constant status-pending-renewal u2)
(define-constant status-expired u3)
(define-constant status-compliant u4)
(define-constant status-non-compliant u5)

;; Data structures
(define-map contracts 
  uint 
  {
    title: (string-ascii 100),
    parties: (list 2 principal),
    start-date: uint,
    end-date: uint,
    renewal-alert-days: uint,
    status: uint,
    compliance-status: uint,
    created-by: principal,
    last-updated: uint
  })

;; Contract counter
(define-data-var contract-counter uint u0)

;; Compliance tracking map
(define-map compliance-records 
  uint 
  {
    last-check-date: uint,
    compliance-score: uint,
    violations: uint,
    notes: (string-ascii 200)
  })

;; Function 1: Create and store a new contract with lifecycle details
(define-public (create-contract 
  (title (string-ascii 100))
  (party-a principal)
  (party-b principal)
  (start-date uint)
  (end-date uint)
  (renewal-alert-days uint))
  (let 
    (
      (contract-id (+ (var-get contract-counter) u1))
      (current-block stacks-block-height)
    )
    (begin
      ;; Validation checks
      (asserts! (> (len title) u0) err-invalid-data)
      (asserts! (> end-date start-date) err-invalid-data)
      (asserts! (> renewal-alert-days u0) err-invalid-data)
      (asserts! (not (is-eq party-a party-b)) err-invalid-data)
      
      ;; Store contract details
      (map-set contracts contract-id
        {
          title: title,
          parties: (list party-a party-b),
          start-date: start-date,
          end-date: end-date,
          renewal-alert-days: renewal-alert-days,
          status: status-active,
          compliance-status: status-compliant,
          created-by: tx-sender,
          last-updated: current-block
        })
      
      ;; Initialize compliance record
      (map-set compliance-records contract-id
        {
          last-check-date: current-block,
          compliance-score: u100,
          violations: u0,
          notes: "Contract created - initial compliance check passed"
        })
      
      ;; Update counter
      (var-set contract-counter contract-id)
      
      ;; Print event for off-chain monitoring
      (print {
        event: "contract-created",
        contract-id: contract-id,
        title: title,
        parties: (list party-a party-b),
        end-date: end-date,
        created-by: tx-sender
      })
      
      (ok contract-id))))

;; Function 2: Check contract status and update compliance with renewal alerts
(define-public (check-contract-status-and-compliance 
  (contract-id uint)
  (compliance-score uint)
  (violation-count uint)
  (notes (string-ascii 200)))
  (let 
    (
      (contract-data (unwrap! (map-get? contracts contract-id) err-contract-not-found))
      (current-block stacks-block-height)
      (end-date (get end-date contract-data))
      (renewal-alert-days (get renewal-alert-days contract-data))
      (alert-threshold (- end-date renewal-alert-days))
    )
    (begin
      ;; Authorization check - only contract parties or owner can update
      (asserts! (or 
                  (is-eq tx-sender contract-owner)
                  (is-some (index-of (get parties contract-data) tx-sender)))
                err-not-authorized)
      
      ;; Validation checks
      (asserts! (<= compliance-score u100) err-invalid-data)
      (asserts! (> (len notes) u0) err-invalid-data)
      
      ;; Determine contract status based on dates
      (let 
        (
          (new-status 
            (if (>= current-block end-date)
              status-expired
              (if (>= current-block alert-threshold)
                status-pending-renewal
                status-active)))
          (new-compliance-status
            (if (>= compliance-score u70)
              status-compliant
              status-non-compliant))
        )
        
        ;; Update contract status
        (map-set contracts contract-id
          (merge contract-data {
            status: new-status,
            compliance-status: new-compliance-status,
            last-updated: current-block
          }))
        
        ;; Update compliance record
        (map-set compliance-records contract-id
          {
            last-check-date: current-block,
            compliance-score: compliance-score,
            violations: violation-count,
            notes: notes
          })
        
        ;; Generate alerts based on status
        (if (is-eq new-status status-pending-renewal)
          (begin
            (print {
              event: "renewal-alert",
              contract-id: contract-id,
              title: (get title contract-data),
              end-date: end-date,
              days-remaining: (- end-date current-block),
              parties: (get parties contract-data)
            })
            true)
          true)

  
        
        ;; Return comprehensive status
        (ok {
          contract-id: contract-id,
          status: new-status,
          compliance-status: new-compliance-status,
          compliance-score: compliance-score,
          violations: violation-count,
          days-to-expiry: (if (> end-date current-block) (- end-date current-block) u0),
          renewal-alert-active: (is-eq new-status status-pending-renewal)
        })))))

;; Read-only functions for querying contract data
(define-read-only (get-contract (contract-id uint))
  (map-get? contracts contract-id))

(define-read-only (get-compliance-record (contract-id uint))
  (map-get? compliance-records contract-id))

(define-read-only (get-contract-counter)
  (var-get contract-counter))

;; Helper function to check if contract needs renewal alert
(define-read-only (needs-renewal-alert (contract-id uint))
  (match (map-get? contracts contract-id)
    contract-data 
      (let 
        (
          (end-date (get end-date contract-data))
          (renewal-alert-days (get renewal-alert-days contract-data))
          (alert-threshold (- end-date renewal-alert-days))
        )
        (and 
          (>= stacks-block-height alert-threshold)
          (< stacks-block-height end-date)))
    false))

;; Function to get all active contracts (returns contract IDs that are active)
(define-read-only (is-contract-active (contract-id uint))
  (match (map-get? contracts contract-id)
    contract-data (is-eq (get status contract-data) status-active)
    false))