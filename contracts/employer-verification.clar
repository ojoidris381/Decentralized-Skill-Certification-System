;; Employer Verification Contract
;; Validates worker qualifications for hiring

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-INVALID-INPUT (err u301))
(define-constant ERR-REQUEST-NOT-FOUND (err u302))
(define-constant ERR-ALREADY-VERIFIED (err u303))
(define-constant ERR-PERMISSION-DENIED (err u304))

;; Data Variables
(define-data-var next-request-id uint u1)
(define-data-var next-verification-id uint u1)

;; Data Maps
(define-map verification-requests
  { request-id: uint }
  {
    employer: principal,
    candidate: principal,
    skill-categories: (list 10 (string-ascii 50)),
    request-date: uint,
    status: (string-ascii 20),
    urgency: (string-ascii 10)
  }
)

(define-map verification-results
  { verification-id: uint }
  {
    request-id: uint,
    skill-category: (string-ascii 50),
    certified: bool,
    certification-level: uint,
    valid-until: uint,
    issuing-authority: principal,
    verification-date: uint
  }
)

(define-map registered-employers
  { employer: principal }
  {
    company-name: (string-ascii 100),
    industry: (string-ascii 50),
    verified: bool,
    registration-date: uint
  }
)

(define-map candidate-permissions
  { candidate: principal, employer: principal }
  {
    permission-granted: bool,
    granted-date: uint,
    expiry-date: uint,
    scope: (list 10 (string-ascii 50))
  }
)

(define-map verification-history
  { candidate: principal, employer: principal }
  {
    total-requests: uint,
    last-verification: uint,
    trust-score: uint
  }
)

;; Employer Registration Functions
(define-public (register-employer
  (company-name (string-ascii 100))
  (industry (string-ascii 50)))
  (begin
    (asserts! (> (len company-name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len industry) u0) ERR-INVALID-INPUT)

    (map-set registered-employers
      { employer: tx-sender }
      {
        company-name: company-name,
        industry: industry,
        verified: false,
        registration-date: block-height
      }
    )
    (ok true)
  )
)

(define-public (verify-employer (employer principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? registered-employers { employer: employer })) ERR-INVALID-INPUT)

    (map-set registered-employers
      { employer: employer }
      (merge
        (unwrap-panic (map-get? registered-employers { employer: employer }))
        { verified: true }
      )
    )
    (ok true)
  )
)

;; Permission Management Functions
(define-public (grant-verification-permission
  (employer principal)
  (expiry-blocks uint)
  (scope (list 10 (string-ascii 50))))
  (begin
    (asserts! (is-registered-employer employer) ERR-INVALID-INPUT)
    (asserts! (> expiry-blocks u0) ERR-INVALID-INPUT)
    (asserts! (> (len scope) u0) ERR-INVALID-INPUT)

    (map-set candidate-permissions
      { candidate: tx-sender, employer: employer }
      {
        permission-granted: true,
        granted-date: block-height,
        expiry-date: (+ block-height expiry-blocks),
        scope: scope
      }
    )
    (ok true)
  )
)

(define-public (revoke-verification-permission (employer principal))
  (begin
    (map-set candidate-permissions
      { candidate: tx-sender, employer: employer }
      {
        permission-granted: false,
        granted-date: u0,
        expiry-date: u0,
        scope: (list)
      }
    )
    (ok true)
  )
)

;; Verification Request Functions
(define-public (create-verification-request
  (candidate principal)
  (skill-categories (list 10 (string-ascii 50)))
  (urgency (string-ascii 10)))
  (let ((request-id (var-get next-request-id)))
    (begin
      (asserts! (is-verified-employer tx-sender) ERR-NOT-AUTHORIZED)
      (asserts! (has-verification-permission candidate tx-sender skill-categories) ERR-PERMISSION-DENIED)
      (asserts! (> (len skill-categories) u0) ERR-INVALID-INPUT)

      (map-set verification-requests
        { request-id: request-id }
        {
          employer: tx-sender,
          candidate: candidate,
          skill-categories: skill-categories,
          request-date: block-height,
          status: "pending",
          urgency: urgency
        }
      )

      (var-set next-request-id (+ request-id u1))
      (ok request-id)
    )
  )
)

(define-public (process-verification-request
  (request-id uint)
  (skill-category (string-ascii 50))
  (certified bool)
  (certification-level uint)
  (valid-until uint)
  (issuing-authority principal))
  (let ((verification-id (var-get next-verification-id)))
    (begin
      (asserts! (is-some (map-get? verification-requests { request-id: request-id })) ERR-REQUEST-NOT-FOUND)
      (asserts! (> (len skill-category) u0) ERR-INVALID-INPUT)
      (asserts! (> valid-until block-height) ERR-INVALID-INPUT)

      (map-set verification-results
        { verification-id: verification-id }
        {
          request-id: request-id,
          skill-category: skill-category,
          certified: certified,
          certification-level: certification-level,
          valid-until: valid-until,
          issuing-authority: issuing-authority,
          verification-date: block-height
        }
      )

      (var-set next-verification-id (+ verification-id u1))
      (ok verification-id)
    )
  )
)

;; Query Functions
(define-read-only (get-verification-request (request-id uint))
  (map-get? verification-requests { request-id: request-id })
)

(define-read-only (get-verification-result (verification-id uint))
  (map-get? verification-results { verification-id: verification-id })
)

(define-read-only (is-registered-employer (employer principal))
  (is-some (map-get? registered-employers { employer: employer }))
)

(define-read-only (is-verified-employer (employer principal))
  (match (map-get? registered-employers { employer: employer })
    employer-info (get verified employer-info)
    false
  )
)

(define-read-only (has-verification-permission
  (candidate principal)
  (employer principal)
  (requested-scope (list 10 (string-ascii 50))))
  (match (map-get? candidate-permissions { candidate: candidate, employer: employer })
    permission-info
      (and
        (get permission-granted permission-info)
        (> (get expiry-date permission-info) block-height)
      )
    false
  )
)

(define-read-only (get-employer-info (employer principal))
  (map-get? registered-employers { employer: employer })
)
