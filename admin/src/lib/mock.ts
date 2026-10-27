/**
 * Dev-only fixture layer, active when VITE_MOCK=1.
 *
 * It lets the whole admin UI be reviewed without a running backend or a seeded
 * database. Mutations edit the in-memory fixtures so the interactions (approve,
 * reject, change complaint status) behave the way they will against real data.
 * Never bundled behaviour in production: `api` only consults this when the flag
 * is set at build time.
 */

const now = Date.now()
const hoursAgo = (h: number) => new Date(now - h * 3_600_000).toISOString()
const daysAgo = (d: number) => new Date(now - d * 86_400_000).toISOString()
const inHours = (h: number) => new Date(now + h * 3_600_000).toISOString()

const id = (s: string) => s.padEnd(36, '0')

let pendingDoctors = [
  {
    id: id('x5'), name: 'Fatima Sheikh', phone: '+91 99200 76310',
    license_number: 'MMC/2011/20518',
    verification_document_url: 'https://example.com/doc/a1.pdf',
    created_at: hoursAgo(5),
  },
  {
    id: id('x7'), name: 'Devika Rao', phone: '+91 98860 31740',
    license_number: 'KMC/2019/55127',
    verification_document_url: 'https://example.com/doc/b2.pdf',
    created_at: hoursAgo(31),
  },
  {
    id: id('x8'), name: 'Sameer Ahuja', phone: '+91 98180 62094',
    license_number: 'DMC/2021/70933',
    verification_document_url: null,
    created_at: daysAgo(3),
  },
]

const bookings = [
  { id: id('d1'), channel: 'online' as const, scheduled_at: inHours(2), price_confirmed: null, status: 'requested' as const, created_at: hoursAgo(1), users: { name: 'Rohit Sharma', phone: '+91 98200 11002' }, doctors: { name: 'Meera Krishnan' } },
  { id: id('d2'), channel: 'home_visit' as const, scheduled_at: inHours(20), price_confirmed: null, status: 'requested' as const, created_at: hoursAgo(3), users: { name: 'Anjali Desai', phone: '+91 97400 55221' }, doctors: { name: 'Arjun Nair' } },
  { id: id('d3'), channel: 'online' as const, scheduled_at: inHours(6), price_confirmed: null, status: 'accepted' as const, created_at: hoursAgo(8), users: { name: 'Vikram Rao', phone: '+91 99860 33417' }, doctors: { name: 'Sanjay Gupta' } },
  { id: id('d4'), channel: 'home_visit' as const, scheduled_at: inHours(30), price_confirmed: null, status: 'accepted' as const, created_at: hoursAgo(12), users: { name: 'Priya Menon', phone: '+91 98450 90011' }, doctors: { name: 'Meera Krishnan' } },
  { id: id('d5'), channel: 'online' as const, scheduled_at: inHours(1), price_confirmed: 900, status: 'paid' as const, created_at: hoursAgo(26), users: { name: 'Imran Qureshi', phone: '+91 98330 71265' }, doctors: { name: 'Lakshmi Iyer' } },
  { id: id('d6'), channel: 'online' as const, scheduled_at: hoursAgo(4), price_confirmed: 650, status: 'completed' as const, created_at: daysAgo(2), users: { name: 'Sneha Kulkarni', phone: '+91 97020 48813' }, doctors: { name: 'Sanjay Gupta' } },
  { id: id('d7'), channel: 'home_visit' as const, scheduled_at: hoursAgo(28), price_confirmed: 1200, status: 'completed' as const, created_at: daysAgo(3), users: { name: 'Harish Patel', phone: '+91 98795 22106' }, doctors: { name: 'Arjun Nair' } },
  { id: id('d8'), channel: 'online' as const, scheduled_at: hoursAgo(50), price_confirmed: 750, status: 'completed' as const, created_at: daysAgo(4), users: { name: 'Divya Suresh', phone: '+91 94440 60922' }, doctors: { name: 'Lakshmi Iyer' } },
  { id: id('d9'), channel: 'online' as const, scheduled_at: hoursAgo(72), price_confirmed: null, status: 'cancelled' as const, created_at: daysAgo(5), users: { name: 'Nikhil Joshi', phone: '+91 98600 14470' }, doctors: { name: 'Meera Krishnan' } },
  { id: id('da'), channel: 'home_visit' as const, scheduled_at: hoursAgo(96), price_confirmed: null, status: 'declined' as const, created_at: daysAgo(6), users: { name: 'Kavita Balan', phone: '+91 99620 80513' }, doctors: { name: 'Sanjay Gupta' } },
]

// Refunds as services/refunds.py records them: one stuck, two in flight, one done.
const ago = (minutes: number) => new Date(Date.now() - minutes * 60_000).toISOString()
const soon = (hours: number) => new Date(Date.now() + hours * 3_600_000).toISOString()
let refunds = [
  {
    id: 'rf-1', amount_paise: 80000, status: 'failed', reason: 'booking_cancelled', attempts: 5,
    failure_reason: 'Razorpay reported the refund as failed.', razorpay_refund_id: 'rfnd_Nq2Lx9',
    requested_by_role: 'patient', created_at: ago(190), processed_at: null,
    bookings: { id: 'bk-a1c4e2f9', channel: 'home_visit', scheduled_start: soon(20), cancelled_by: 'patient',
      doctors: { name: 'Dr. Sameer Deshpande' }, users: { name: 'Aarav Kulkarni' } },
  },
  {
    id: 'rf-2', amount_paise: 55000, status: 'processing', reason: 'booking_cancelled', attempts: 1,
    failure_reason: null, razorpay_refund_id: 'rfnd_Nq7Pa2', requested_by_role: 'doctor',
    created_at: ago(42), processed_at: null,
    bookings: { id: 'bk-77d0b3e1', channel: 'online_consult', scheduled_start: soon(4), cancelled_by: 'doctor',
      doctors: { name: 'Dr. Anjali Patil' }, users: { name: 'Riya Shah' } },
  },
  {
    id: 'rf-3', amount_paise: 65000, status: 'pending', reason: 'late_capture', attempts: 1,
    failure_reason: 'read timed out', razorpay_refund_id: null, requested_by_role: 'system',
    created_at: ago(6), processed_at: null,
    bookings: { id: 'bk-0e5f19aa', channel: 'online_consult', scheduled_start: soon(30), cancelled_by: 'system',
      doctors: { name: 'Dr. Meera Kulkarni' }, users: { name: 'Kabir Mehta' } },
  },
  {
    id: 'rf-4', amount_paise: 90000, status: 'processed', reason: 'booking_cancelled', attempts: 1,
    failure_reason: null, razorpay_refund_id: 'rfnd_Nm3Qt8', requested_by_role: 'patient',
    created_at: ago(60 * 26), processed_at: ago(60 * 2),
    bookings: { id: 'bk-5c2e8d41', channel: 'home_visit', scheduled_start: soon(-24), cancelled_by: 'patient',
      doctors: { name: 'Dr. Rahul Joshi' }, users: { name: 'Neha Iyer' } },
  },
]

let complaints = [
  { id: id('e1'), description: 'Doctor joined the video consult 25 minutes late and ended the call after four minutes. Asking for a refund of the consult fee.', status: 'open' as string, created_at: hoursAgo(4), bookings: { id: id('d6'), patient_id: id('p1'), doctor_id: id('x1') } },
  { id: id('e2'), description: 'Home visit doctor charged ₹800 over the quoted price for dressing material and would not itemise it.', status: 'open' as string, created_at: hoursAgo(19), bookings: { id: id('d7'), patient_id: id('p2'), doctor_id: id('x2') } },
  { id: id('e3'), description: 'Call quality was unusable — audio dropped throughout. Prescription was still issued but I could not discuss my symptoms.', status: 'in_review' as string, created_at: daysAgo(2), bookings: { id: id('d8'), patient_id: id('p3'), doctor_id: id('x3') } },
  { id: id('e4'), description: 'Patient did not answer the door for a scheduled home visit; marking for no-show fee review.', status: 'resolved' as string, created_at: daysAgo(6), bookings: { id: id('da'), patient_id: id('p4'), doctor_id: id('x1') } },
  { id: id('e5'), description: 'Duplicate charge on UPI for a single booking.', status: 'closed' as string, created_at: daysAgo(9), bookings: { id: id('d9'), patient_id: id('p5'), doctor_id: id('x2') } },
]

let bills = [
  {
    id: id('f1'), booking_id: id('d7'), total_amount: 4350, status: 'under_review',
    items: [
      { name: 'Home visit consult', qty: 1, price: 1200 },
      { name: 'Wound debridement', qty: 1, price: 2500 },
      { name: 'Dressing kit', qty: 2, price: 325 },
    ],
    bookings: { id: id('d7'), doctor_id: id('x2'), doctors: { name: 'Arjun Nair' } },
  },
  {
    id: id('f2'), booking_id: id('d4'), total_amount: 9800, status: 'under_review',
    items: [
      { name: 'Home visit consult', qty: 1, price: 1500 },
      { name: 'IV fluid administration', qty: 4, price: 950 },
      { name: 'Nebulisation', qty: 2, price: 2250 },
    ],
    bookings: { id: id('d4'), doctor_id: id('x1'), doctors: { name: 'Meera Krishnan' } },
  },
]

const directory = [
  { id: id('x1'), name: 'Meera Krishnan', phone: '+91 98450 11234', category_id: 'c1', category_name: 'General Physician', verification_status: 'verified' as const, rating_avg: 4.8, offers_online_consult: true,  offers_home_visit: true,  created_at: daysAgo(210) },
  { id: id('x2'), name: 'Arjun Nair', phone: '+91 98110 44872', category_id: 'c2', category_name: 'Orthopaedics', verification_status: 'verified' as const, rating_avg: 4.4, offers_online_consult: true,  offers_home_visit: true,  created_at: daysAgo(165) },
  { id: id('x3'), name: 'Sanjay Gupta', phone: '+91 98730 90184', category_id: 'c3', category_name: 'Paediatrics', verification_status: 'verified' as const, rating_avg: 4.9, offers_online_consult: true,  offers_home_visit: false, created_at: daysAgo(142) },
  { id: id('x4'), name: 'Lakshmi Iyer', phone: '+91 94440 22087', category_id: 'c4', category_name: 'Dermatology', verification_status: 'verified' as const, rating_avg: 4.6, offers_online_consult: true,  offers_home_visit: false, created_at: daysAgo(98) },
  { id: id('x5'), name: 'Fatima Sheikh', phone: '+91 99200 76310', category_id: 'c1', category_name: 'General Physician', verification_status: 'pending' as const, rating_avg: null, offers_online_consult: true,  offers_home_visit: true,  created_at: daysAgo(3) },
  { id: id('x7'), name: 'Devika Rao', phone: '+91 98860 31740', category_id: 'c2', category_name: 'Orthopaedics', verification_status: 'pending' as const, rating_avg: null, offers_online_consult: true,  offers_home_visit: false, created_at: daysAgo(2) },
  { id: id('x8'), name: 'Sameer Ahuja', phone: '+91 98180 62094', category_id: 'c3', category_name: 'Paediatrics', verification_status: 'pending' as const, rating_avg: null, offers_online_consult: true,  offers_home_visit: true,  created_at: daysAgo(1) },
  { id: id('x6'), name: 'Rakesh Menon', phone: '+91 97390 51120', category_id: 'c5', category_name: 'Cardiology', verification_status: 'rejected' as const, rating_avg: 3.1, offers_online_consult: false, offers_home_visit: false, created_at: daysAgo(64) },
]

const auditLog = [
  { id: id('g1'), actor_role: 'ops',    entity: 'doctor',         entity_id: id('x4'), action: 'verify.approve',      at: hoursAgo(2) },
  { id: id('g2'), actor_role: 'ops',    entity: 'complaint',      entity_id: id('e3'), action: 'status.in_review',    at: hoursAgo(5) },
  { id: id('g3'), actor_role: 'senior', entity: 'procedure_bill', entity_id: id('f1'), action: 'bill.flag',           at: hoursAgo(9) },
  { id: id('g4'), actor_role: 'ops',    entity: 'doctor',         entity_id: id('x6'), action: 'verify.reject',       at: hoursAgo(22) },
  { id: id('g5'), actor_role: 'system', entity: 'booking',        entity_id: id('d9'), action: 'refund.initiated',    at: hoursAgo(27) },
  { id: id('g6'), actor_role: 'senior', entity: 'procedure_bill', entity_id: id('f2'), action: 'bill.approve',        at: daysAgo(2) },
  { id: id('g7'), actor_role: 'ops',    entity: 'doctor',         entity_id: id('x3'), action: 'suspend.lift',        at: daysAgo(2) },
  { id: id('g8'), actor_role: 'ops',    entity: 'complaint',      entity_id: id('e4'), action: 'status.resolved',     at: daysAgo(3) },
  { id: id('g9'), actor_role: 'system', entity: 'booking',        entity_id: id('da'), action: 'no_show.flag',        at: daysAgo(4) },
  { id: id('ga'), actor_role: 'ops',    entity: 'doctor',         entity_id: id('x2'), action: 'verify.approve',      at: daysAgo(5) },
]

/**
 * A 30-day series with a weekly rhythm and mild growth, so the trend charts get
 * exercised with a realistic shape rather than noise.
 */
function timeseries(days: number) {
  const out = []
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(now - i * 86_400_000)
    const dow = d.getDay()
    const weekend = dow === 0 || dow === 6
    const growth = 1 + (days - i) / (days * 2.5)
    const wobble = 0.75 + ((Math.sin(i * 1.7) + 1) / 2) * 0.5
    const count = Math.max(0, Math.round((weekend ? 4 : 9) * growth * wobble))
    const completed = Math.round(count * 0.62)
    out.push({
      date: d.toISOString().slice(0, 10),
      bookings: count,
      completed,
      revenue: completed * 620,
    })
  }
  return out
}

function metrics() {
  const count = (s: string) => bookings.filter(b => b.status === s).length
  return {
    doctors: {
      total: directory.length,
      pending: directory.filter(d => d.verification_status === 'pending').length,
      verified: directory.filter(d => d.verification_status === 'verified').length,
      rejected: directory.filter(d => d.verification_status === 'rejected').length,
      suspended: 1,
    },
    bookings: {
      total: bookings.length,
      requested: count('requested'), accepted: count('accepted'), paid: count('paid'),
      completed: count('completed'), cancelled: count('cancelled'),
      declined: count('declined'), no_show: 0,
    },
    revenue: {
      consult_gross: 186_400,
      procedure_gross: 92_750,
      commission_earned: 41_872,
      owed_to_doctors: 63_205,
    },
    queues: {
      bills_under_review: bills.filter(b => b.status === 'under_review').length,
      complaints_open: complaints.filter(c => c.status === 'open').length,
      complaints_in_review: complaints.filter(c => c.status === 'in_review').length,
      refunds_failed: refunds.filter(r => r.status === 'failed').length,
      refunds_in_flight: refunds.filter(r => r.status === 'pending' || r.status === 'processing').length,
    },
  }
}

function match(path: string, pattern: RegExp) {
  return pattern.exec(path.split('?')[0])
}

function query(path: string, key: string) {
  return new URLSearchParams(path.split('?')[1] ?? '').get(key)
}

/** Returns the fixture for a request, or throws for an unmapped route. */
export async function mockRequest(path: string, method: string, body: unknown): Promise<unknown> {
  await new Promise(r => setTimeout(r, 280))   // let the skeletons actually show
  const bare = path.split('?')[0]

  if (method === 'POST' && bare === '/admin/login') return { token: 'mock-token' }

  if (method === 'POST') {
    if (match(bare, /^\/admin\/reviews\/([^/]+)\/moderate$/)) return { ok: true }
    if (match(bare, /^\/admin\/incidents\/([^/]+)\/(decide|appeal-decision|refund)$/)) return { ok: true }
    if (match(bare, /^\/admin\/prescriptions\/([^/]+)\/access$/)) {
      return { id: 'rx-1', version: 1, kind: 'prescription', complaints: 'Fever for 3 days',
               diagnosis: 'Viral fever', investigations: null, advice: 'Rest and fluids',
               items: [{ position: 1, medicine: 'Paracetamol', strength: '500 mg', dose: '1 tablet',
                         frequency: '1-0-1', duration: '3 days', instructions: 'After food' }],
               pdf_url: null, upload_url: null }
    }
    const retry = match(bare, /^\/admin\/refunds\/([^/]+)\/retry$/)
    if (retry) {
      refunds = refunds.map(r => (r.id === retry[1]
        ? { ...r, status: 'processing', attempts: r.attempts + 1, razorpay_refund_id: 'rfnd_Nr0Ks4', failure_reason: null }
        : r))
      return refunds.find(r => r.id === retry[1])
    }
  }

  if (method === 'GET') {
    if (bare === '/admin/metrics') return metrics()
    if (bare === '/admin/metrics/timeseries') {
      return timeseries(Number(query(path, 'days') ?? 30))
    }
    if (bare === '/admin/audit-log') {
      const limit = Number(query(path, 'limit') ?? 100)
      return auditLog.slice(0, limit)
    }
    if (bare === '/admin/doctors/pending') return pendingDoctors
    if (bare === '/admin/doctors') return directory
    // The real /doctors/search pages its results.
    if (bare === '/doctors/search') return { items: directory, total: directory.length, has_more: false }
    if (bare === '/admin/bookings') {
      const status = query(path, 'status')
      return status ? bookings.filter(b => b.status === status) : bookings
    }
    if (bare === '/admin/complaints') {
      const status = query(path, 'status')
      return status ? complaints.filter(c => c.status === status) : complaints
    }
    const timeline = match(bare, /^\/admin\/bookings\/([^/]+)\/timeline$/)
    if (timeline) {
      const at = (h: number) => new Date(Date.now() - h * 3_600_000).toISOString()
      return [
        { id: 1, event: 'created', from_status: null, to_status: 'requested', actor_role: 'patient', actor_id: 'p', occurred_at: at(30), metadata: {} },
        { id: 2, event: 'accept', from_status: 'requested', to_status: 'accepted', actor_role: 'doctor', actor_id: 'd', occurred_at: at(29), metadata: {} },
        { id: 3, event: 'pay', from_status: 'accepted', to_status: 'paid', actor_role: 'system', actor_id: null, occurred_at: at(28.9), metadata: { method: 'upi' } },
        { id: 4, event: 'cancel', from_status: 'paid', to_status: 'cancelled', actor_role: 'patient', actor_id: 'p', occurred_at: at(1), metadata: { refund_pct: 50, refund_paise: 40000, policy_version: '2026-10-26', reason_code: 'schedule_conflict' } },
      ]
    }
    if (match(bare, /^\/admin\/pricing\/([^/]+)\/history$/)) {
      const at = (d: number) => new Date(Date.now() - d * 86_400_000).toISOString()
      return {
        follow_up_validity_days: 7,
        rules: [
          { id: 'r5', channel: 'online_consult', visit_category: 'initial', duration_min: 15, price_paise: 70000, effective_from: at(2), effective_until: null },
          { id: 'r4', channel: 'online_consult', visit_category: 'initial', duration_min: 30, price_paise: 100000, effective_from: at(20), effective_until: null },
          { id: 'r3', channel: 'online_consult', visit_category: 'follow_up', duration_min: 10, price_paise: 0, effective_from: at(20), effective_until: null },
          { id: 'r1', channel: 'online_consult', visit_category: 'initial', duration_min: 15, price_paise: 60000, effective_from: at(20), effective_until: at(2) },
        ],
      }
    }
    if (bare === '/admin/me') {
      return { email: 'ops@charak.care', role: 'admin', permissions: [
        'admins.manage', 'audit.read', 'bookings.override', 'bookings.read', 'complaints.read', 'complaints.update',
        'deletions.fulfil', 'doctors.read', 'doctors.suspend', 'doctors.verify', 'incidents.decide', 'incidents.read',
        'metrics.read', 'patient_phone.reveal', 'payouts.manage', 'payouts.read', 'policies.approve', 'prescriptions.break_glass',
        'pricing.read', 'procedure_bills.review', 'refunds.manage', 'reviews.moderate', 'reviews.read', 'sessions.revoke',
        'storage.manage', 'system.read', 'system.retry', 'visits.read'] }
    }
    if (bare === '/admin/health') {
      return {
        window_days: 30,
        bookings: { requested: 142, confirmed: 118, patient_cancelled_free: 9, patient_cancelled_late: 3, doctor_cancelled: 2, requests_expired: 6, patient_no_shows: 1 },
        attendance: { visits_held: 96, home_visits_held: 41, home_visits_with_journey: 37, doctor_no_shows_confirmed: 1, call_problems_reported: 4, reschedules: { doctor_device: 2, mutual: 1 } },
        incidents: { reported: 7, unresolved: 2, appeals_open: 1, appeals_reversed: 0, remedies: { refund: 2, replacement: 1 }, replacements_paid: 1 },
        refunds: { count: 15, processed: 13, failed: 0, open: 2, median_minutes_to_processed: 42.5, by_reason: { booking_cancelled: 12, doctor_no_show: 2, replacement_difference: 1 } },
        prescriptions: { sent: 88, median_minutes_after_start: 26, opened_within_48h: 71, awaiting_view: 9, completed_by_fallback: 6, follow_ups_recommended: 22, follow_ups_booked: 9 },
        reviews: { count: 54, completed_visits: 79, distribution: { 5: 38, 4: 11, 3: 3, 2: 1, 1: 1 }, avg_professionalism: 4.7, avg_communication: 4.5, avg_punctuality: 4.2, reported_open: 1, hidden: 0 },
        money: { payouts: { paid: 12, processing: 1 }, ledger_reversals: 11 },
        system: { dead_jobs: 0, failed_webhooks: 0, failed_notifications: 3 },
      }
    }
    if (bare === '/admin/policies') {
      const at = (d: number) => new Date(Date.now() - d * 86_400_000).toISOString()
      return {
        policies: [
          { id: 'p3', channel: 'online_consult', version: '2026-11-01', summary: 'Free until 15 minutes before; no refund after.', decision_ref: 'D3', effective_from: at(-4), created_at: at(0), policy_approvals: null },
          { id: 'p2', channel: 'home_visit', version: '2026-10-26', summary: 'Free cancellation up to 2 hours before your visit.', decision_ref: 'LD-005', effective_from: at(1), created_at: at(1), policy_approvals: { approved_by: 'In force before the review gate (migration 0029)', note: null, approved_at: at(1) } },
        ],
        documents: [
          { id: 'd1', type: 'tos', version: '2026-10-01', title: 'Terms of Use', url: 'https://www.charak.care/terms', material: true, published_at: at(26), legal_document_approvals: { approved_by: 'In force before the review gate (migration 0029)', note: null, approved_at: at(26) } },
        ],
      }
    }
    if (bare === '/admin/system/dead-letters') {
      return { jobs: [], webhooks: [], notifications: [
        { id: 'n1', event: 'prescription.ready', recipient_role: 'patient', delivery_error: 'FCM: UNREGISTERED', created_at: new Date(Date.now() - 7_200_000).toISOString() },
      ] }
    }
    if (bare === '/admin/admins') {
      return [
        { id: 'a1', email: 'ops@charak.care', role: 'admin', totp_enabled: true, last_login_at: new Date().toISOString() },
        { id: 'a2', email: 'support@charak.care', role: 'support', totp_enabled: false, last_login_at: null },
      ]
    }
    if (bare === '/admin/incidents') {
      const at = (h: number) => new Date(Date.now() - h * 3_600_000).toISOString()
      return query(path, 'view') === 'appealed' ? [] : [{
        id: 'inc-1', case_ref: 'CHK-7F3K2', booking_id: 'bk-1', type: 'doctor_no_show',
        reported_as: 'doctor_not_arrived', reported_by_role: 'patient', cause: 'undetermined', status: 'under_review',
        evidence: { scheduled_start: at(2), journey_started_at: at(2.5), channel: 'home_visit' },
        patient_note: 'Waited 45 minutes, phone switched off.', doctor_response: 'Stuck in traffic at Vashi, called twice.',
        decision_reason: null, appeal_status: 'none', appeal_note: null, remedy_eligible: false, remedy: 'none',
        auto_confirm_at: null, created_at: at(1),
        bookings: { channel: 'home_visit', scheduled_start: at(2), status: 'paid' },
        doctors: { name: 'Dr. Arjun Nair' }, users: { name: 'Riya Shah' },
        events: [{ event: 'reported', actor_role: 'patient', note: null, occurred_at: at(1) },
                 { event: 'doctor_responded', actor_role: 'doctor', note: null, occurred_at: at(0.5) }],
      }]
    }
    if (bare === '/admin/reviews') {
      const at = (d: number) => new Date(Date.now() - d * 86_400_000).toISOString()
      return query(path, 'status') === 'hidden' ? [] : [{
        id: 'rev-1', overall: 1, professionalism: 1, communication: null, punctuality: null,
        comment: 'Rude and kept me waiting. Call him on 98xxxxxx12 and see.', status: 'published',
        hidden_reason: null, hidden_at: null, created_at: at(2), doctors: { name: 'Dr. Arjun Nair' },
        reports: [{ id: 'rep-1', reason: 'privacy', note: 'Contains my personal number', reporter_role: 'doctor', created_at: at(1) }],
      }]
    }
    if (bare === '/admin/visits/queues') {
      const at = (h: number) => new Date(Date.now() + h * 3_600_000).toISOString()
      return {
        journey_not_started: [
          { id: 'b7f3c2a1-0000-4000-8000-000000000001', channel: 'home_visit', status: 'paid', scheduled_start: at(0.3),
            journey_started_at: null, prescription_sent_at: null, patient_name: 'Riya Shah', doctor_name: 'Dr. Meera Kulkarni' },
        ],
        prescription_overdue: [],
        prescription_unviewed: [
          { id: 'b7f3c2a1-0000-4000-8000-000000000002', channel: 'online_consult', status: 'consulted', scheduled_start: at(-30),
            journey_started_at: null, prescription_sent_at: at(-29), patient_name: 'Aarav Joshi', doctor_name: 'Dr. Sameer Deshpande' },
        ],
      }
    }
    if (match(bare, /^\/admin\/bookings\/([^/]+)\/prescriptions$/)) {
      const at = (h: number) => new Date(Date.now() - h * 3_600_000).toISOString()
      return [{ id: 'rx-1', version: 1, kind: 'prescription', status: 'submitted', submitted_at: at(29),
                first_viewed_at: null, superseded_at: null }]
    }
    if (bare === '/admin/refunds') {
      const status = query(path, 'status')
      return status
        ? refunds.filter(r => r.status === status)
        : refunds.filter(r => r.status !== 'processed')
    }
    if (bare === '/admin/procedure-bills/review') {
      return bills.filter(b => b.status === 'under_review')
    }
  }

  if (method === 'PATCH') {
    const verify = match(bare, /^\/admin\/doctors\/([^/]+)\/verify$/)
    if (verify) {
      pendingDoctors = pendingDoctors.filter(d => d.id !== verify[1])
      return { ok: true }
    }
    const suspend = match(bare, /^\/admin\/doctors\/([^/]+)\/suspend$/)
    if (suspend) return { ok: true }

    const complaint = match(bare, /^\/admin\/complaints\/([^/]+)$/)
    if (complaint) {
      const next = (body as { status?: string })?.status
      complaints = complaints.map(c => (c.id === complaint[1] && next ? { ...c, status: next } : c))
      return { ok: true }
    }
    const bill = match(bare, /^\/bookings\/([^/]+)\/procedure-bill\/(approve|flag)$/)
    if (bill) {
      bills = bills.map(b =>
        b.booking_id === bill[1] ? { ...b, status: bill[2] === 'approve' ? 'paid' : 'flagged' } : b
      )
      return { ok: true }
    }
  }

  throw new Error(`No fixture for ${method} ${bare}`)
}
