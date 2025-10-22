;; septic-permit-manager
;; Manages septic system permits with installation tracking and maintenance scheduling

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))

(define-data-var next-permit-id uint u1)
(define-data-var next-inspection-id uint u1)

(define-map permits
  { permit-id: uint }
  {
    property-owner: principal,
    property-address: (string-utf8 200),
    system-type: (string-ascii 50),
    system-size: uint,
    issued-at: uint,
    installation-deadline: uint,
    installed: bool,
    installation-date: (optional uint)
  }
)

(define-map inspections
  { inspection-id: uint }
  {
    permit-id: uint,
    inspector: principal,
    inspection-date: uint,
    passed: bool,
    notes: (string-utf8 500)
  }
)

(define-map maintenance-schedule
  { permit-id: uint }
  {
    last-maintenance: uint,
    next-due: uint,
    maintenance-count: uint
  }
)

(define-read-only (get-permit (permit-id uint))
  (map-get? permits { permit-id: permit-id })
)

(define-read-only (get-inspection (inspection-id uint))
  (map-get? inspections { inspection-id: inspection-id })
)

(define-read-only (get-maintenance-schedule (permit-id uint))
  (map-get? maintenance-schedule { permit-id: permit-id })
)

(define-public (issue-permit
    (property-owner principal)
    (property-address (string-utf8 200))
    (system-type (string-ascii 50))
    (system-size uint)
  )
  (let ((permit-id (var-get next-permit-id)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set permits
      { permit-id: permit-id }
      {
        property-owner: property-owner,
        property-address: property-address,
        system-type: system-type,
        system-size: system-size,
        issued-at: stacks-block-height,
        installation-deadline: (+ stacks-block-height u8640),
        installed: false,
        installation-date: none
      })
    (var-set next-permit-id (+ permit-id u1))
    (ok permit-id))
)

(define-public (record-installation (permit-id uint))
  (let ((permit (unwrap! (map-get? permits { permit-id: permit-id }) err-not-found)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set permits
      { permit-id: permit-id }
      (merge permit { installed: true, installation-date: (some stacks-block-height) }))
    (map-set maintenance-schedule
      { permit-id: permit-id }
      {
        last-maintenance: stacks-block-height,
        next-due: (+ stacks-block-height u52560),
        maintenance-count: u0
      })
    (ok true))
)

(define-public (record-inspection
    (permit-id uint)
    (passed bool)
    (notes (string-utf8 500))
  )
  (let ((inspection-id (var-get next-inspection-id)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set inspections
      { inspection-id: inspection-id }
      {
        permit-id: permit-id,
        inspector: tx-sender,
        inspection-date: stacks-block-height,
        passed: passed,
        notes: notes
      })
    (var-set next-inspection-id (+ inspection-id u1))
    (ok inspection-id))
)

(define-public (record-maintenance (permit-id uint))
  (let 
    (
      (schedule (unwrap! (map-get? maintenance-schedule { permit-id: permit-id }) err-not-found))
      (permit (unwrap! (map-get? permits { permit-id: permit-id }) err-not-found))
    )
    (asserts! (is-eq tx-sender (get property-owner permit)) err-owner-only)
    (map-set maintenance-schedule
      { permit-id: permit-id }
      {
        last-maintenance: stacks-block-height,
        next-due: (+ stacks-block-height u52560),
        maintenance-count: (+ (get maintenance-count schedule) u1)
      })
    (ok true))
)
