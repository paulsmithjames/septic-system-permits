;; septic-permit-manager
;; Manages septic system permits with installation tracking and maintenance scheduling

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-installed (err u102))
(define-constant err-not-installed (err u103))
(define-constant err-invalid-status (err u104))
(define-constant err-deadline-passed (err u105))
(define-constant err-unauthorized (err u106))
(define-constant err-invalid-size (err u107))

;; Data variables
(define-data-var next-permit-id uint u1)
(define-data-var next-inspection-id uint u1)
(define-data-var total-permits-issued uint u0)
(define-data-var total-inspections uint u0)
(define-data-var total-maintenance-records uint u0)

;; Data maps
(define-map permits
  { permit-id: uint }
  {
    property-owner: principal,
    property-address: (string-utf8 200),
    system-type: (string-ascii 50),
    system-size: uint,
    contractor: (optional principal),
    issued-at: uint,
    installation-deadline: uint,
    installed: bool,
    installation-date: (optional uint),
    status: (string-ascii 20),
    revoked: bool
  }
)

(define-map inspections
  { inspection-id: uint }
  {
    permit-id: uint,
    inspector: principal,
    inspection-date: uint,
    inspection-type: (string-ascii 50),
    passed: bool,
    notes: (string-utf8 500),
    follow-up-required: bool
  }
)

(define-map maintenance-schedule
  { permit-id: uint }
  {
    last-maintenance: uint,
    next-due: uint,
    maintenance-count: uint,
    overdue: bool,
    maintenance-interval: uint
  }
)

(define-map contractors
  { contractor: principal }
  {
    name: (string-utf8 100),
    license-number: (string-ascii 50),
    active: bool,
    permits-completed: uint
  }
)

(define-map permit-fees
  { permit-id: uint }
  {
    fee-amount: uint,
    paid: bool,
    payment-date: (optional uint)
  }
)

;; Read-only functions
(define-read-only (get-permit (permit-id uint))
  (map-get? permits { permit-id: permit-id })
)

(define-read-only (get-inspection (inspection-id uint))
  (map-get? inspections { inspection-id: inspection-id })
)

(define-read-only (get-maintenance-schedule (permit-id uint))
  (map-get? maintenance-schedule { permit-id: permit-id })
)

(define-read-only (get-contractor (contractor principal))
  (map-get? contractors { contractor: contractor })
)

(define-read-only (get-permit-fee (permit-id uint))
  (map-get? permit-fees { permit-id: permit-id })
)

(define-read-only (is-maintenance-overdue (permit-id uint) (current-height uint))
  (match (map-get? maintenance-schedule { permit-id: permit-id })
    schedule (ok (> current-height (get next-due schedule)))
    err-not-found
  )
)

(define-read-only (get-total-permits)
  (ok (var-get total-permits-issued))
)

(define-read-only (get-total-inspections)
  (ok (var-get total-inspections))
)

(define-read-only (get-total-maintenance-records)
  (ok (var-get total-maintenance-records))
)

;; Public functions
(define-public (issue-permit
    (property-owner principal)
    (property-address (string-utf8 200))
    (system-type (string-ascii 50))
    (system-size uint)
    (fee-amount uint)
  )
  (let ((permit-id (var-get next-permit-id)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> system-size u0) err-invalid-size)
    (map-set permits
      { permit-id: permit-id }
      {
        property-owner: property-owner,
        property-address: property-address,
        system-type: system-type,
        system-size: system-size,
        contractor: none,
        issued-at: block-height,
        installation-deadline: (+ block-height u8640),
        installed: false,
        installation-date: none,
        status: "pending",
        revoked: false
      })
    (map-set permit-fees
      { permit-id: permit-id }
      {
        fee-amount: fee-amount,
        paid: false,
        payment-date: none
      })
    (var-set next-permit-id (+ permit-id u1))
    (var-set total-permits-issued (+ (var-get total-permits-issued) u1))
    (ok permit-id))
)

(define-public (assign-contractor (permit-id uint) (contractor principal))
  (let ((permit (unwrap! (map-get? permits { permit-id: permit-id }) err-not-found)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (get installed permit)) err-already-installed)
    (map-set permits
      { permit-id: permit-id }
      (merge permit { contractor: (some contractor), status: "assigned" }))
    (ok true))
)

(define-public (record-installation (permit-id uint))
  (let ((permit (unwrap! (map-get? permits { permit-id: permit-id }) err-not-found)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (get installed permit)) err-already-installed)
    (asserts! (<= block-height (get installation-deadline permit)) err-deadline-passed)
    (map-set permits
      { permit-id: permit-id }
      (merge permit { 
        installed: true, 
        installation-date: (some block-height),
        status: "installed"
      }))
    (map-set maintenance-schedule
      { permit-id: permit-id }
      {
        last-maintenance: block-height,
        next-due: (+ block-height u52560),
        maintenance-count: u0,
        overdue: false,
        maintenance-interval: u52560
      })
    (ok true))
)

(define-public (record-inspection
    (permit-id uint)
    (inspection-type (string-ascii 50))
    (passed bool)
    (notes (string-utf8 500))
    (follow-up-required bool)
  )
  (let 
    (
      (inspection-id (var-get next-inspection-id))
      (permit (unwrap! (map-get? permits { permit-id: permit-id }) err-not-found))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set inspections
      { inspection-id: inspection-id }
      {
        permit-id: permit-id,
        inspector: tx-sender,
        inspection-date: block-height,
        inspection-type: inspection-type,
        passed: passed,
        notes: notes,
        follow-up-required: follow-up-required
      })
    (if passed
      (map-set permits
        { permit-id: permit-id }
        (merge permit { status: "approved" }))
      (map-set permits
        { permit-id: permit-id }
        (merge permit { status: "failed-inspection" })))
    (var-set next-inspection-id (+ inspection-id u1))
    (var-set total-inspections (+ (var-get total-inspections) u1))
    (ok inspection-id))
)

(define-public (record-maintenance (permit-id uint))
  (let 
    (
      (schedule (unwrap! (map-get? maintenance-schedule { permit-id: permit-id }) err-not-found))
      (permit (unwrap! (map-get? permits { permit-id: permit-id }) err-not-found))
    )
    (asserts! (is-eq tx-sender (get property-owner permit)) err-unauthorized)
    (asserts! (get installed permit) err-not-installed)
    (map-set maintenance-schedule
      { permit-id: permit-id }
      {
        last-maintenance: block-height,
        next-due: (+ block-height (get maintenance-interval schedule)),
        maintenance-count: (+ (get maintenance-count schedule) u1),
        overdue: false,
        maintenance-interval: (get maintenance-interval schedule)
      })
    (var-set total-maintenance-records (+ (var-get total-maintenance-records) u1))
    (ok true))
)

(define-public (pay-permit-fee (permit-id uint))
  (let 
    (
      (fee-info (unwrap! (map-get? permit-fees { permit-id: permit-id }) err-not-found))
      (permit (unwrap! (map-get? permits { permit-id: permit-id }) err-not-found))
    )
    (asserts! (is-eq tx-sender (get property-owner permit)) err-unauthorized)
    (asserts! (not (get paid fee-info)) err-invalid-status)
    (map-set permit-fees
      { permit-id: permit-id }
      {
        fee-amount: (get fee-amount fee-info),
        paid: true,
        payment-date: (some block-height)
      })
    (ok true))
)

(define-public (register-contractor 
    (contractor principal)
    (name (string-utf8 100))
    (license-number (string-ascii 50))
  )
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set contractors
      { contractor: contractor }
      {
        name: name,
        license-number: license-number,
        active: true,
        permits-completed: u0
      })
    (ok true))
)

(define-public (revoke-permit (permit-id uint))
  (let ((permit (unwrap! (map-get? permits { permit-id: permit-id }) err-not-found)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set permits
      { permit-id: permit-id }
      (merge permit { revoked: true, status: "revoked" }))
    (ok true))
)

(define-public (update-maintenance-interval (permit-id uint) (new-interval uint))
  (let ((schedule (unwrap! (map-get? maintenance-schedule { permit-id: permit-id }) err-not-found)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set maintenance-schedule
      { permit-id: permit-id }
      (merge schedule { maintenance-interval: new-interval }))
    (ok true))
)
