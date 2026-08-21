/* ============================================================
   CHARAK Patient App — screens, flows, live-sync simulation
   ============================================================ */
const P = {
  user: { name: "Pranav", phone: "+91 98201 44321", firstTime: true },
  cats: [
    { n: "General Physician", ic: "stethoscope" }, { n: "Orthopedic", ic: "bone" },
    { n: "Nurse", ic: "syringe" }, { n: "Cardiology", ic: "heart-pulse" },
    { n: "Dermatology", ic: "droplets" }, { n: "Gynecology", ic: "baby" },
    { n: "Pediatrics", ic: "smile" }, { n: "Physiotherapy", ic: "dumbbell" },
  ],
  docs: [
    { id: 0, name: "Dr. Aarav Mehta", ini: "AM", tone: 1, spec: "General Physician", cred: "MBBS, MD · Internal Medicine", rating: 4.8, reviews: 214, online: 500, home: 800, radius: 3, verified: true, bio: "General physician with 9 years in family practice. Sees everything from routine fevers to chronic-condition follow-ups.", next: "Today, 6:00 PM" },
    { id: 1, name: "Dr. Priya Nair", ini: "PN", tone: 2, spec: "General Physician", cred: "MBBS, DNB · Family Medicine", rating: 4.9, reviews: 301, online: 600, home: 900, radius: 3, verified: true, bio: "Family medicine specialist with a focus on elder care and chronic conditions. Regular home-visit practice across Vashi and Sanpada.", next: "Today, 7:30 PM" },
    { id: 2, name: "Dr. Rohan Kulkarni", ini: "RK", tone: 3, spec: "General Physician", cred: "MBBS", rating: 4.7, reviews: 156, online: 450, home: 750, radius: 2, verified: true, bio: "GP with 6 years of experience. Short-notice consults, same-day slots most days.", next: "Tomorrow, 10:00 AM" },
    { id: 3, name: "Dr. Kavita Desai", ini: "KD", tone: 4, spec: "Dermatology", cred: "MBBS, MD · Dermatology", rating: 4.8, reviews: 189, online: 700, home: 0, radius: 0, verified: true, bio: "Consultant dermatologist. Acne, eczema, hair loss and cosmetic dermatology consultations online.", next: "Today, 5:00 PM" },
    { id: 4, name: "Dr. Sameer Shah", ini: "SS", tone: 5, spec: "Orthopedic", cred: "MBBS, MS · Orthopedics", rating: 4.6, reviews: 98, online: 650, home: 1000, radius: 5, verified: true, bio: "Orthopedic surgeon. Joint pain, sports injuries, post-fracture follow-ups at home.", next: "Today, 6:30 PM" },
    { id: 5, name: "Dr. Neha Gupta", ini: "NG", tone: 6, spec: "Pediatrics", cred: "MBBS, MD · Pediatrics", rating: 4.9, reviews: 240, online: 550, home: 0, radius: 0, verified: true, bio: "Pediatrician. Newborn care, vaccination guidance, and childhood illness consults online.", next: "Today, 4:30 PM" },
    { id: 6, name: "Dr. Farhan Ali", ini: "FA", tone: 4, spec: "Cardiology", cred: "MBBS, DM · Cardiology", rating: 4.8, reviews: 175, online: 800, home: 1200, radius: 5, verified: true, bio: "Cardiologist. BP and cholesterol management, ECG review, and pre-surgery follow-ups.", next: "Tomorrow, 11:30 AM" },
    { id: 7, name: "Dr. Anjali Rao", ini: "AR", tone: 2, spec: "Gynecology", cred: "MBBS, MS · OB-GYN", rating: 4.7, reviews: 132, online: 600, home: 950, radius: 3, verified: true, bio: "Obstetrician & gynecologist. Pregnancy follow-ups, women's health consults, home visits for postnatal care.", next: "Today, 8:00 PM" },
  ],
  slots: ["10:00 AM", "11:30 AM", "2:00 PM", "3:30 PM", "5:00 PM", "6:30 PM", "8:00 PM"],
  dates: ["Today", "Tomorrow", "Fri", "Sat", "Sun", "Mon"],
  sel: { spec: "General Physician", doc: null, date: "Today", time: null, channel: "online" },
  intake: { type: "text", text: "", transcript: "", rec: false },
  bookings: [],
  history: [],
  pending: null,
  actId: null,
  clarify: false,
};

/* ---------- helpers ---------- */
P.docsOf = (spec) => (spec ? P.docs.filter((d) => d.spec === spec) : P.docs);
P.price = (d) => (P.sel.channel === "home" ? d.home : d.online);
P.procCatalog = {
  "General Physician": [["ECG", 250], ["Dressing", 200], ["Injection", 150], ["Nebulization", 300], ["Stitch removal", 350]],
  "Orthopedic": [["Plaster", 800], ["Splint", 600], ["Joint injection", 1000], ["Dressing", 200]],
  "Cardiology": [["ECG", 300], ["BP monitoring", 150]],
  "Gynecology": [["Pregnancy test", 200], ["Ultrasound review", 500], ["Injection", 150]],
  "Pediatrics": [["Vaccination", 400], ["Nebulization", 300], ["Injection", 150]],
  "Dermatology": [["Dressing", 200], ["Cautery", 600]],
  "Physiotherapy": [["Therapy session", 400]],
  "Nurse": [["Dressing", 200], ["Injection", 150], ["Catheter care", 250]],
  "Dentistry": [["Scaling", 800], ["Filling", 1000]],
};
P.procsOf = (d) => (P.procCatalog[d.spec] || []).map(([n, p]) => ({ n, p }));
P.extraRate = (d, ch) => (ch === "home" ? d.homeExtra : d.onlineExtra) || 150;
P.threshOf = (d) => d.procThresh || 500;
P.go = (id, spec) => { if (spec !== undefined) { P.sel.spec = spec; P.dirFilter = "all"; } Charak.go(id); };

P.avatar = (d) => Charak.avatar(d.ini, d.tone);
P.docCard = (d) => `
  <article class="card doc-card pressable" onclick="P.go('dprofile',null);P.sel.doc=${d.id}">
    ${P.avatar(d)}
    <div class="doc-info">
      <h3>${d.name}${d.verified ? '<svg class="verif" data-lucide="shield-check"></svg>' : ""}</h3>
      <p class="doc-spec">${d.cred}</p>
      <div class="doc-row">
        <span class="rate"><svg data-lucide="star"></svg>${d.rating.toFixed(1)} <em>(${d.reviews})</em></span>
        <span class="price tnum">₹${d.online}<span class="per">/15m</span></span>
      </div>
      <div class="doc-badges">
        ${d.online ? '<span class="badge primary">Online</span>' : ""}
        ${d.home ? '<span class="badge">Home Visit</span>' : ""}
      </div>
      <p class="doc-next"><svg data-lucide="clock"></svg>Next: ${d.next}</p>
    </div>
  </article>`;

/* ---------- screens ---------- */
P.screens = {};

P.screens.splash = {
  html: () => `
    <div class="body center-col" style="justify-content:center;padding-bottom:80px">
      <div style="width:64px;height:64px;border-radius:18px;background:var(--color-primary);display:grid;place-items:center;margin-bottom:18px">
        <svg style="width:30px;height:30px;color:#fff" data-lucide="plus"></svg>
      </div>
      <div class="brand-mark">Chara<i>k</i></div>
      <p style="font-size:13.5px;color:var(--color-ink-muted);margin-top:6px">Home visits & online consults</p>
      <div style="margin-top:36px;width:220px">
        <div class="skel" style="height:12px"></div>
        <div class="skel" style="height:12px;margin-top:8px;width:160px;margin-left:auto"></div>
      </div>
    </div>`,
  enter: (el) => { setTimeout(() => Charak.go("phone"), 1100); },
};

P.screens.phone = {
  html: () => `
    <div class="body" style="padding-top:26px">
      <h1 class="screen-title">Your phone number</h1>
      <p class="screen-sub">We'll send a one-time code to verify it's you.</p>
      <div style="margin-top:26px">
        <div class="field">
          <label>Mobile number</label>
          <div style="display:flex;gap:10px">
            <div class="input" style="width:92px;display:flex;align-items:center;font-weight:500;color:var(--color-ink-muted)">+91</div>
            <input class="input" id="phone-in" style="flex:1" value="98201 44321" maxlength="10" inputmode="numeric">
          </div>
        </div>
        <p class="hint-line">OTP-based signup. No password, ever.</p>
      </div>
    </div>
    <div class="cta-bar"><button class="btn primary" onclick="Charak.go('otp')">Continue</button></div>`,
  enter: (el) => setTimeout(() => { const i = el.querySelector("#phone-in"); i && i.focus(); }, 120),
};

P.screens.otp = {
  html: () => `
    <div class="body" style="padding-top:26px">
      <h1 class="screen-title">Enter the code</h1>
      <p class="screen-sub">Sent to +91 98201 44321 · <a class="link-line" style="font-size:13px" onclick="Charak.go('phone')">Change</a></p>
      <div class="otp-row" id="otp-row">
        ${[0, 1, 2, 3, 4, 5].map((i) => `<input class="otp-cell" id="otp${i}" maxlength="1" inputmode="numeric">`).join("")}
      </div>
      <p class="countdown">Resend code in <b class="tnum">0:28</b></p>
    </div>
    <div class="cta-bar"><button class="btn primary" onclick="P.otpDone()">Verify</button></div>`,
  enter: (el) => {
    const cells = el.querySelectorAll(".otp-cell");
    cells.forEach((c, i) => {
      c.addEventListener("input", () => { if (c.value && i < 5) cells[i + 1].focus(); });
      c.addEventListener("keydown", (e) => { if (e.key === "Backspace" && !c.value && i > 0) cells[i - 1].focus(); });
    });
    setTimeout(() => cells[0].focus(), 120);
  },
};
P.otpDone = () => (P.user.firstTime ? Charak.go("name") : Charak.tab("home"));

P.screens.name = {
  html: () => `
    <div class="body" style="padding-top:26px">
      <h1 class="screen-title">What should we call you?</h1>
      <p class="screen-sub">This is how doctors will see you.</p>
      <div style="margin-top:26px">
        <div class="field">
          <label>Full name</label>
          <input class="input" id="name-in" value="Pranav Deshmukh" placeholder="Your full name">
        </div>
      </div>
    </div>
    <div class="cta-bar"><button class="btn primary" onclick="P.nameDone()">Continue</button></div>`,
  enter: (el) => setTimeout(() => { const i = el.querySelector("#name-in"); i && i.focus(); }, 120),
};
P.nameDone = () => {
  const i = document.getElementById("name-in");
  if (i && i.value.trim()) P.user.name = i.value.trim();
  P.user.firstTime = false;
  Charak.tab("home");
  Charak.toast("Welcome to CHARAK, " + P.user.name.split(" ")[0]);
};

P.screens.home = {
  tabbed: "home",
  html: () => `
    <div class="body" style="padding-top:12px">
      <div class="h-greet">
        <div><p class="hi">Good morning</p><h1>${P.user.name.split(" ")[0]}</h1></div>
        <button class="iconbtn" aria-label="Notifications"><svg data-lucide="bell"></svg><span class="dot"></span></button>
      </div>
      <button class="h-search pressable" onclick="P.go('directory','')"><svg data-lucide="search"></svg>Search doctors or specialties</button>
      <p class="sec-title">Book by specialty</p>
      <div class="spec-grid">
        ${P.cats.map((c) => `
          <button class="spec pressable" onclick="P.go('directory','${c.n}')">
            <span class="spec-ic"><svg data-lucide="${c.ic}"></svg></span>
            <span class="spec-n">${c.n}</span>
          </button>`).join("")}
        <button class="spec-more pressable" onclick="P.go('directory','')"><svg data-lucide="plus"></svg>All specialties</button>
      </div>
    </div>`,
};

P.screens.directory = {
  html: () => `
    <div class="topbar">
      <button class="iconbtn" onclick="Charak.back()"><svg data-lucide="arrow-left"></svg></button>
      <div class="tb-center"><div class="tb-title">${P.sel.spec || "All doctors"}</div></div>
      <button class="iconbtn" onclick="Charak.toast('Filters: radius, price, availability')"><svg data-lucide="sliders-horizontal"></svg></button>
    </div>
    <div class="body" style="padding-top:10px">
      <div class="dir-meta">
        <span class="count tnum">${P.docsOf(P.sel.spec).length} doctors near you</span>
        <span style="font-size:13px;font-weight:500;color:var(--color-ink-muted)">Navi Mumbai</span>
      </div>
      <div class="chip-row" style="margin-bottom:14px">
        <button class="chip ${P.dirFilter === "all" ? "on" : ""}" onclick="P.chip(this,'all')">All</button>
        <button class="chip ${P.dirFilter === "online" ? "on" : ""}" onclick="P.chip(this,'online')">Online</button>
        <button class="chip ${P.dirFilter === "home" ? "on" : ""}" onclick="P.chip(this,'home')">Home Visit</button>
        <button class="chip" style="margin-left:auto" onclick="Charak.toast('Sorted by price · low to high')">Price ▾</button>
      </div>
      ${P.filtered().length ? P.filtered().map(P.docCard).join("") : `
        <div class="empty-state">
          <span class="wait-ic"><svg data-lucide="search-x"></svg></span>
          <h3>No doctors here yet</h3>
          <p>${P.sel.spec} is live but no doctor has opened slots nearby. Try another specialty.</p>
          <button class="btn ghost" style="max-width:200px" onclick="P.go('directory','')">Browse all doctors</button>
        </div>`}
    </div>`,
};
P.chip = (btn, f) => {
  P.dirFilter = f;
  btn.parentElement.querySelectorAll(".chip").forEach((c) => c.classList.toggle("on", c === btn));
  Charak.go("directory");
};
P.filtered = () => {
  let l = P.docsOf(P.sel.spec);
  if (P.dirFilter === "online") l = l.filter((d) => d.online);
  if (P.dirFilter === "home") l = l.filter((d) => d.home);
  return l;
};

P.screens.dprofile = {
  html: () => {
    const d = P.sel.doc !== null ? P.docs[P.sel.doc] : P.docs[0];
    return `
    <div class="topbar">
      <button class="iconbtn" onclick="Charak.back()"><svg data-lucide="arrow-left"></svg></button>
      <div class="tb-center"><div class="tb-title">Doctor</div></div>
      <button class="iconbtn" onclick="Charak.toast('Saved to your doctors')"><svg data-lucide="bookmark"></svg></button>
    </div>
    <div class="body" style="padding-top:4px;padding-bottom:110px">
      <div class="dp-hero">
        ${P.avatar(d)}
        <h1>${d.name}${d.verified ? '<svg class="verif" data-lucide="shield-check"></svg>' : ""}</h1>
        <p class="spec">${d.cred}</p>
      </div>
      <div class="dp-stats">
        <div class="dp-stat"><div class="v tnum"><svg data-lucide="star"></svg>${d.rating.toFixed(1)}</div><div class="l">${d.reviews} ratings</div></div>
        <div class="dp-stat"><div class="v">Verified</div><div class="l">License checked</div></div>
        <div class="dp-stat"><div class="v tnum">₹${d.online}<span class="per">/15m</span></div><div class="l">Online consult</div></div>
        ${d.home ? `<div class="dp-stat"><div class="v tnum">₹${d.home}<span class="per">/15m</span></div><div class="l">Home visit</div></div>` : ""}
      </div>
      <div class="dp-sec">
        <p class="sec-title">About</p>
        <p class="dp-bio">${d.bio}</p>
      </div>
      <div class="dp-sec">
        <p class="sec-title">Consultation fee</p>
        <div class="fee-line">
          <div class="fee-row"><span>Online consult</span><span class="tnum">₹${d.online}</span></div>
          <div class="fee-row"><span>Home visit</span><span class="tnum">₹${d.home}</span></div>
          <div class="fee-row muted"><span>Extra time (per 15 min)</span><span class="tnum">₹${d.onlineExtra || 150}</span></div>
        </div>
        <p class="hint-line">Price covers a <b>15-minute</b> consult. Each extra 15 min is charged at the doctor's extra-time rate.</p>
      </div>
      <div class="dp-sec">
        <p class="sec-title">Services</p>
        <div class="chip-rows" style="margin-top:8px">
          ${d.online ? '<span class="badge primary">Online · ₹' + d.online + "/15m</span>" : ""}
          ${d.home ? '<span class="badge">Home Visit · ₹' + d.home + `/15m</span><span class="badge">Within ${d.radius} km</span>` : ""}
          <span class="badge">Next: ${d.next}</span>
        </div>
      </div>
      <div class="dp-sec">
        <p class="sec-title">Procedure prices · fixed</p>
        <p class="dp-bio" style="margin-bottom:10px">Flat rates for procedures done during a <b>home visit</b> — billed after the visit, only for what's actually done.</p>
        <div class="fee-line">
          ${P.procsOf(d).map((p) => `<div class="fee-row"><span>${p.n}</span><span class="tnum">₹${p.p}</span></div>`).join("")}
        </div>
        <p class="hint-line">Charged after a home visit. Bills above ₹${P.threshOf(d)} are reviewed by a senior doctor before you pay.</p>
      </div>
      <div class="dp-sec">
        <p class="sec-title">What patients say</p>
        <p class="dp-bio" style="font-style:italic">"Explained everything clearly, didn't rush us. Came home on time."</p>
      </div>
    </div>
    <div class="cta-bar"><button class="btn primary" onclick="P.beginBooking()">Book a slot</button></div>`;
  },
};
P.beginBooking = () => { P.sel.time = null; P.sel.date = "Today"; Charak.go("slots"); };

P.screens.slots = {
  html: () => {
    const d = P.docs[P.sel.doc];
    const offIdx = (d.id * 2) % P.slots.length; // deterministic greyed slots
    return `
    <div class="topbar">
      <button class="iconbtn" onclick="Charak.back()"><svg data-lucide="arrow-left"></svg></button>
      <div class="tb-center"><div class="tb-title">Pick a slot</div></div>
      <div style="width:44px"></div>
    </div>
    <div class="body" style="padding-top:10px">
      <p class="screen-sub" style="margin-bottom:14px">${d.name} · ${d.spec}</p>
      <div class="date-strip">
        ${P.dates.map((dt, i) => `
          <button class="date-chip ${P.sel.date === dt ? "on" : ""}" onclick="P.sel.date='${dt}';Charak.go('slots')">
            <span class="d">${i === 0 ? "Wed" : i === 1 ? "Thu" : dt}</span><span class="n tnum">${["13", "14", "15", "16", "17", "18"][i]}</span>
          </button>`).join("")}
      </div>
      <div class="time-grid">
        ${P.slots.map((t, i) => `
          <button class="time-slot ${i === offIdx || (i + d.id) % 5 === 4 ? "off" : ""} ${P.sel.time === t ? "on" : ""}"
            ${(i === offIdx || (i + d.id) % 5 === 4) ? "" : `onclick="P.sel.time='${t}';Charak.go('slots')"`}>${t}</button>`).join("")}
      </div>
      <p class="slot-hint"><svg data-lucide="info"></svg>${P.sel.time ? "Selected: " + P.sel.date + ", " + P.sel.time : "Greyed slots are already booked"}</p>
    </div>
    <div class="cta-bar">
      <button class="btn primary" ${P.sel.time ? "" : "disabled"} onclick="P.slotNext()">Continue</button>
    </div>`;
  },
};
P.slotNext = () => {
  const d = P.docs[P.sel.doc];
  if (d.online && d.home) Charak.go("channel");
  else { P.sel.channel = d.home ? "home" : "online"; Charak.go("intake"); }
};

P.screens.channel = {
  html: () => {
    const d = P.docs[P.sel.doc];
    return `
    <div class="topbar">
      <button class="iconbtn" onclick="Charak.back()"><svg data-lucide="arrow-left"></svg></button>
      <div class="tb-center"><div class="tb-title">How should the visit happen?</div></div>
      <div style="width:44px"></div>
    </div>
    <div class="body" style="padding-top:12px">
      <p class="screen-sub" style="margin-bottom:16px">${P.sel.date}, ${P.sel.time} · ${d.name}</p>
      <button class="card chan-card pressable ${P.sel.channel === "online" ? "sel" : ""}" onclick="P.sel.channel='online';Charak.go('channel')">
        <span class="chan-ic"><svg data-lucide="video"></svg></span>
        <div><h3>Online Consult</h3><p>Video call on CHARAK. Price covers a 15-min consult, paid before the call.</p><p class="chan-note">+ ₹${d.onlineExtra || 150} per extra 15 min</p></div>
        <span class="price tnum">₹${d.online}<span class="per">/15m</span></span>
      </button>
      <button class="card chan-card pressable ${P.sel.channel === "home" ? "sel" : ""}" onclick="P.sel.channel='home';Charak.go('channel')">
        <span class="chan-ic" style="background:rgba(31,170,109,0.12);color:var(--color-success)"><svg data-lucide="home"></svg></span>
        <div><h3>Home Visit</h3><p>Doctor comes to you. Consult fee paid upfront; procedures (if any) billed after at fixed rates.</p><p class="chan-note">+ ₹${d.homeExtra || 200} per extra 15 min · within ${d.radius} km</p></div>
        <span class="price tnum">₹${d.home}<span class="per">/15m</span></span>
      </button>
      <div class="act-timer" style="margin-top:18px;justify-content:flex-start;gap:10px">
        <svg data-lucide="map-pin" style="width:16px;height:16px;color:var(--color-primary-deep)"></svg>
        <span class="t">Sector 9, Nerul — in range for Home Visit</span>
      </div>
    </div>
    <div class="cta-bar"><button class="btn primary" onclick="Charak.go('intake')">Continue · ₹${P.price(P.docs[P.sel.doc])}${P.sel.channel === "home" ? " + procedures" : ""}</button></div>`;
  },
};

P.screens.intake = {
  html: () => {
    const seg = (id, ic, label) => `<button class="${P.intake.type === id ? "on" : ""}" onclick="P.intake.type='${id}';Charak.go('intake')"><svg data-lucide="${ic}"></svg>${label}</button>`;
    const rec = P.intake.rec;
    return `
    <div class="topbar">
      <button class="iconbtn" onclick="Charak.back()"><svg data-lucide="arrow-left"></svg></button>
      <div class="tb-center"><div class="tb-title">Describe the issue</div></div>
      <div style="width:44px"></div>
    </div>
    <div class="body" style="padding-top:12px">
      <p class="screen-sub" style="margin-bottom:14px">Share as much as you like — the doctor reads it directly.</p>
      <div class="seg">${seg("text", "type", "Text")}${seg("voice", "mic", "Voice")}${seg("photo", "camera", "Photo")}${seg("video", "video", "Video")}</div>

      ${P.intake.type === "text" ? `
        <div class="intake-box">
          <textarea class="input" id="intake-text" placeholder="e.g. Fever since yesterday evening, mild body ache, taking Crocin…">${P.intake.text}</textarea>
          <p class="hint-line">Doctors prefer specifics: how long, how severe, anything you've tried.</p>
        </div>` : ""}

      ${P.intake.type === "voice" ? `
        <div class="mic-box">
          ${rec ? `<div class="wave"><i></i><i></i><i></i><i></i><i></i><i></i><i></i></div>
            <button class="mic-btn stop" onclick="P.stopRec()"><svg data-lucide="square"></svg></button>
            <span class="mic-txt tnum">Recording… 0:12 · tap to stop</span>`
            : `<button class="mic-btn" onclick="P.startRec()"><svg data-lucide="mic"></svg></button>
            <span class="mic-txt">Tap to describe your issue by voice</span>`}
        </div>
        ${P.intake.transcript ? `<div class="transcript"><b>Transcribed · editable</b><div contenteditable="true" id="transcript-edit">${P.intake.transcript}</div></div>` : ""}` : ""}

      ${P.intake.type === "photo" ? `
        <div class="attach-row">
          <button class="attach-tile has" onclick="Charak.toast('Photo attached')"><svg data-lucide="image"></svg></button>
          <button class="attach-tile has" onclick="Charak.toast('Photo attached')"><svg data-lucide="image"></svg></button>
          <button class="attach-tile" onclick="Charak.toast('Add photo')"><svg data-lucide="plus"></svg></button>
        </div>
        <p class="hint-line">Rashes, wounds, reports — anything visual helps.</p>` : ""}

      ${P.intake.type === "video" ? `
        <div class="attach-row">
          <button class="attach-tile has" onclick="Charak.toast('Video attached')"><svg data-lucide="video"></svg></button>
          <button class="attach-tile" onclick="Charak.toast('Record video')"><svg data-lucide="plus"></svg></button>
        </div>
        <p class="hint-line">Show how you move or the affected area. Max 2 minutes.</p>` : ""}

      <p class="reassure"><svg data-lucide="shield-check"></svg><span>Reviewed by your doctor directly — never analyzed by AI.</span></p>
    </div>
    <div class="cta-bar"><button class="btn primary" onclick="P.intakeNext()">Continue</button></div>`;
  },
  enter: (el) => {
    const t = el.querySelector("#intake-text");
    if (t) t.addEventListener("input", () => (P.intake.text = t.value));
    const tr = el.querySelector("#transcript-edit");
    if (tr) tr.addEventListener("input", () => (P.intake.transcript = tr.textContent));
  },
};
P.startRec = () => { P.intake.rec = true; Charak.go("intake"); };
P.stopRec = () => {
  P.intake.rec = false;
  P.intake.transcript = "Fever since yesterday evening, mild body ache. Taking Crocin twice but not helping much. Requesting a home visit for my mother, she is 62.";
  Charak.go("intake");
};
P.intakeNext = () => {
  if (P.intake.type === "text") P.intake.text = (document.getElementById("intake-text") || {}).value || P.intake.text;
  Charak.go("review");
};

P.screens.declined = {
  html: () => {
    const b = P.pending;
    return `
    <div class="body" style="padding-top:34px">
      <div class="ok-state">
        <div class="wait-ic"><svg data-lucide="info"></svg></div>
        <h1 class="title">Request declined</h1>
        <p class="sub">${b ? b.doc.name + " couldn't take this request" : "The doctor couldn't take this request"} — it happens for all sorts of reasons, none of them about you. Plenty of other doctors in ${P.sel.spec || "your area"} are available.</p>
        <div class="card bsum">
          <div class="rev-row"><span class="k">When</span><span class="v">${b ? b.date + ", " + b.time : "—"}</span></div>
          <div class="rev-row"><span class="k">Channel</span><span class="v">${b ? (b.channel === "home" ? "Home Visit" : "Online Consult") : "—"}</span></div>
          <div class="rev-div"></div>
          <div class="rev-row"><span class="k">Status</span><span class="v"><span class="status-pill danger">Declined</span></span></div>
        </div>
      </div>
    </div>
    <div class="cta-bar"><button class="btn primary" onclick="P.findAnother()">Find another doctor</button></div>`;
  },
};
P.findAnother = () => {
  P.go("directory", P.sel.spec || "");
};

P.screens.review = {
  html: () => {
    const d = P.docs[P.sel.doc];
    const sum = P.intake.type === "text" ? P.intake.text : P.intake.type === "voice" ? P.intake.transcript : P.intake.type + " attached";
    return `
    <div class="topbar">
      <button class="iconbtn" onclick="Charak.back()"><svg data-lucide="arrow-left"></svg></button>
      <div class="tb-center"><div class="tb-title">Review & confirm</div></div>
      <div style="width:44px"></div>
    </div>
    <div class="body" style="padding-top:12px">
      <div class="card rev-sum">
        <div class="rev-row"><span class="k">Doctor</span><span class="v">${d.name}</span></div>
        <div class="rev-row"><span class="k">When</span><span class="v">${P.sel.date}, ${P.sel.time}</span></div>
        <div class="rev-row"><span class="k">Channel</span><span class="v">${P.sel.channel === "home" ? "Home Visit" : "Online Consult"}</span></div>
        <div class="rev-div"></div>
        <div class="rev-row"><span class="k">Consult fee · 15 min</span><span class="v tnum">₹${P.price(d)}</span></div>
        <div class="rev-row"><span class="k">Extra 15 min</span><span class="v muted">₹${P.sel.channel === "home" ? d.homeExtra || 200 : d.onlineExtra || 150}</span></div>
        <div class="rev-div"></div>
        <div class="rev-row"><span class="k">Payment</span><span class="v muted">${P.sel.channel === "online" ? "Paid before the call" : "Consult fee now · procedures billed after visit"}</span></div>
      </div>
      ${P.sel.channel === "home" ? `
      <div class="clarify-banner" style="align-items:flex-start"><svg data-lucide="receipt"></svg>
        <span><b>Procedures billed after the visit</b> — if any procedure is done, it's charged at the doctor's fixed rates on this profile. Bills above ₹${P.threshOf(d)} are reviewed by a senior doctor first.</span>
      </div>` : ""}
      <div class="intake-prev">
        <div class="meta"><span class="badge primary">${P.intake.type === "text" ? "Text" : P.intake.type === "voice" ? "Voice · transcribed" : P.intake.type + " · 2 files"}</span></div>
        ${sum ? sum : "<span style='color:var(--color-ink-muted)'>No description added</span>"}
      </div>
      <p class="hint-line">The doctor reviews your request before accepting — booking a slot does not confirm it automatically.</p>
    </div>
    <div class="cta-bar"><button class="btn primary" onclick="P.sendRequest()">Send request · ₹${P.price(P.docs[P.sel.doc])}</button></div>`;
  },
};
P.sendRequest = () => {
  const d = P.docs[P.sel.doc];
  P.pending = { id: "BK-2846", doc: d, channel: P.sel.channel, price: P.price(d), date: P.sel.date, time: P.sel.time, status: "requested" };
  P.bookings.unshift(P.pending);
  Charak.simPost({ t: "request", id: P.pending.id });
  Charak.go("sent");
};

P.screens.sent = {
  html: () => `
    <div class="body" style="padding-top:16px">
      <div class="wait-state">
        <div class="wait-ic" style="margin-bottom:22px"><svg data-lucide="send"></svg></div>
        <span class="status-pill warning"><span class="wait-dot"></span>Pending doctor review</span>
        <h1 class="screen-title" style="margin-top:18px">Request sent</h1>
        <p class="screen-sub">${P.pending.doc.name} will review your request. You'll be notified the moment they decide — usually within minutes.</p>
        <div class="card bsum">
          <div class="rev-row"><span class="k">When</span><span class="v">${P.pending.date}, ${P.pending.time}</span></div>
          <div class="rev-row"><span class="k">Channel</span><span class="v">${P.pending.channel === "home" ? "Home Visit" : "Online Consult"}</span></div>
          <div class="rev-div"></div>
          <div class="rev-row"><span class="k">Price</span><span class="v tnum">₹${P.pending.price}</span></div>
        </div>
        <p class="hint-line">This is not a confirmed appointment yet. Use the dock to simulate the doctor accepting or declining.</p>
      </div>
    </div>`,
};

P.screens.accepted = {
  html: () => {
    const b = P.pending;
    return `
    <div class="body" style="padding-top:34px">
      <div class="ok-state">
        <div class="ok-ic">${Charak.checkSvg(88)}</div>
        <h1 class="title">Booking accepted!</h1>
        <p class="sub">${b.doc.name} accepted your request. Pay to confirm the slot — the price stays exactly as shown.</p>
        <div class="card bsum">
          <div class="rev-row"><span class="k">Doctor</span><span class="v">${b.doc.name}</span></div>
          <div class="rev-row"><span class="k">When</span><span class="v">${b.date}, ${b.time}</span></div>
          <div class="rev-row"><span class="k">Channel</span><span class="v">${b.channel === "home" ? "Home Visit" : "Online Consult"}</span></div>
          <div class="rev-div"></div>
          <div class="rev-row"><span class="k">To pay</span><span class="v tnum">₹${b.price}</span></div>
        </div>
        <p class="hint-line">Payment via UPI or card · Razorpay secure checkout</p>
      </div>
    </div>
    <div class="cta-bar"><button class="btn primary" onclick="P.paySheet()">Pay ₹${b.price} now</button></div>`;
  },
};
P.paySheet = () => {
  const b = P.pending;
  Charak.openSheet("pay", `
    <div style="display:flex;justify-content:space-between;align-items:center">
      <h2 class="sheet-title">Pay ₹${b.price}</h2>
      <span class="badge">Secure</span>
    </div>
    <p style="font-size:13px;color:var(--color-ink-muted);margin-bottom:14px">${b.doc.name} · ${b.date}, ${b.time}</p>
    <div class="seg" style="margin-bottom:14px">
      <button class="on" id="pay-upi-tab" onclick="P.payTab('upi')">UPI</button>
      <button id="pay-card-tab" onclick="P.payTab('card')">Card</button>
    </div>
    <div id="pay-upi">
      <div class="field"><label>UPI ID</label><input class="input" value="pranav@okhdfc" placeholder="yourname@bank"></div>
      <p class="hint-line" style="margin-bottom:12px">or pay with</p>
      <div class="two-col">
        <button class="btn ghost" style="height:46px" onclick="Charak.toast('Opening GPay…')">GPay</button>
        <button class="btn ghost" style="height:46px" onclick="Charak.toast('Opening PhonePe…')">PhonePe</button>
      </div>
    </div>
    <div id="pay-card" style="display:none">
      <div class="field" style="margin-bottom:10px"><label>Card number</label><input class="input tnum" placeholder="4242 4242 4242 4242"></div>
      <div class="two-col">
        <div class="field"><label>Expiry</label><input class="input tnum" placeholder="08/28"></div>
        <div class="field"><label>CVV</label><input class="input tnum" placeholder="123" type="password"></div>
      </div>
    </div>
    <button class="btn primary" style="margin-top:16px" id="pay-btn" onclick="P.payNow()">Pay ₹${b.price}</button>`);
};
P.payTab = (t) => {
  document.getElementById("pay-upi").style.display = t === "upi" ? "block" : "none";
  document.getElementById("pay-card").style.display = t === "card" ? "block" : "none";
  document.getElementById("pay-upi-tab").classList.toggle("on", t === "upi");
  document.getElementById("pay-card-tab").classList.toggle("on", t === "card");
};
P.payNow = () => {
  const btn = document.getElementById("pay-btn");
  btn.disabled = true;
  btn.textContent = "Processing…";
  setTimeout(() => {
    btn.innerHTML = "Payment successful ✓";
    btn.classList.add("success");
    setTimeout(() => {
      Charak.closeSheet();
      P.pending.status = "paid";
      Charak.simPost({ t: "paid" });
      Charak.go("confirmed");
    }, 700);
  }, 1100);
};

P.screens.confirmed = {
  html: () => {
    const b = P.pending;
    return `
    <div class="body" style="padding-top:34px">
      <div class="ok-state">
        <div class="ok-ic">${Charak.checkSvg(88)}</div>
        <h1 class="title">Booking confirmed</h1>
        <p class="sub">You're set with ${b.doc.name} on ${b.date} at ${b.time} (${b.channel === "home" ? "Home Visit" : "Online Consult"}).</p>
        <div class="card bsum">
          <div class="rev-row"><span class="k">Receipt</span><span class="v muted">RZP-204188 · paid via UPI</span></div>
          <div class="rev-row"><span class="k">Amount</span><span class="v tnum">₹${b.price}</span></div>
          <div class="rev-row"><span class="k">Status</span><span class="v"><span class="status-pill success">Confirmed</span></span></div>
        </div>
        <button class="btn ghost" style="max-width:240px;margin-top:18px" onclick="Charak.toast('Added to calendar')"><svg class="icon" data-lucide="calendar-plus"></svg>Add to calendar</button>
      </div>
    </div>
    <div class="cta-bar"><button class="btn primary" onclick="Charak.tab('bookings')">View my bookings</button></div>`;
  },
};

P.screens.bookings = {
  tabbed: "bookings",
  html: () => `
    <div class="body" style="padding-top:14px">
      <h1 class="screen-title">Bookings</h1>
      <p class="screen-sub" style="margin-bottom:16px">${P.bookings.length} active booking${P.bookings.length === 1 ? "" : "s"}</p>
      ${P.bookings.length ? P.bookings.map((b) => `
        <button class="card bk-card pressable" onclick="P.actId='${b.id}';Charak.go('active')">
          <div class="bk-top">
            ${P.avatar(b.doc)}
            <div style="flex:1;min-width:0"><h3>${b.doc.name}</h3><p class="sub">${b.doc.spec} · ${b.channel === "home" ? "Home Visit" : "Online Consult"}</p></div>
            ${Charak.statusPill(b.status)}
          </div>
          <div class="bk-mid"><svg data-lucide="clock"></svg>${b.date}, ${b.time}<span class="price tnum">₹${b.price}</span></div>
        </button>`).join("") : `
        <div class="empty-state">
          <span class="wait-ic"><svg data-lucide="calendar-x"></svg></span>
          <h3>No active bookings</h3>
          <p>Book a doctor from the Home tab and your appointments will show up here.</p>
          <button class="btn primary" style="max-width:200px" onclick="Charak.tab('home')">Browse doctors</button>
        </div>`}
    </div>`,
};

P.screens.active = {
  html: () => {
    const b = P.bookings.find((x) => x.id === P.actId) || P.pending || P.bookings[0];
    const online = b.channel === "online";
    return `
    <div class="topbar">
      <button class="iconbtn" onclick="Charak.back()"><svg data-lucide="arrow-left"></svg></button>
      <div class="tb-center"><div class="tb-title">${b.doc.name}</div></div>
      <div style="width:44px"></div>
    </div>
    <div class="body" style="padding-top:10px;padding-bottom:110px">
      ${P.clarify ? `
        <div class="clarify-banner"><svg data-lucide="phone-call"></svg>
          <span><b>Clarification call scheduled</b> — ${b.doc.name} will call you 15 min before the slot to confirm a few details.</span>
        </div>` : ""}
      <div class="card act-card">
        <div class="act-doctor">
          ${P.avatar(b.doc)}
          <div><h3>${b.doc.name}</h3><p class="sub">${b.channel === "home" ? "Home Visit" : "Online Consult"} · ${b.date}, ${b.time}</p></div>
        </div>
        ${online ? `
          <div class="act-timer">
            <span class="t">Consult starts in</span>
            <span class="v tnum">12:46</span>
          </div>` : `
          <div class="act-timer">
            <span class="t">Doctor's ETA</span>
            <span class="v">~ 5:45 PM</span>
          </div>`}
      </div>
      ${online ? `
        <div class="card act-card">
          <div class="act-row"><svg data-lucide="video"></svg><span>Video call</span><span class="v muted">Join from this screen</span></div>
          <div class="act-row"><svg data-lucide="message-circle"></svg><span>Contact through app</span><span class="v muted">Tap to chat</span></div>
          <div class="act-row"><svg data-lucide="receipt"></svg><span>Paid via UPI</span><span class="v tnum">₹${b.price}</span></div>
        </div>
        <button class="btn primary" style="margin-top:6px" onclick="Charak.go('call')"><svg class="icon" data-lucide="video"></svg>Join call</button>
        <p class="hint-line" style="text-align:center">Join button enables 5 min before the slot (simulated here)</p>` : `
        <div class="card act-card">
          <div class="act-row"><svg data-lucide="map-pin"></svg><span>Address</span><span class="v">Sector 9, Nerul</span></div>
          <div class="act-row"><svg data-lucide="navigation"></svg><span>Doctor en route</span><span class="v muted">Live in demo</span></div>
          <div class="act-row"><svg data-lucide="message-circle"></svg><span>Contact through app</span><span class="v muted">Tap to chat</span></div>
          <div class="act-row"><svg data-lucide="receipt"></svg><span>Paid via UPI</span><span class="v tnum">₹${b.price}</span></div>
        </div>`}
    </div>
    <div class="cta-bar"><button class="btn ghost" onclick="Charak.toast('Doctor notified')">I'm running late</button><button class="btn primary" onclick="Charak.toast('Cancellation under review')">Cancel</button></div>`;
  },
};

P.screens.call = {
  html: () => `
    <div class="call-grid">
      <div class="call-top"><span class="rec"></span><span id="call-timer" class="tnum">00:00</span></div>
      <div class="call-peer">
        ${P.avatar(P.docs[P.sel.doc] || P.pending.doc)}
        <h3>${(P.docs[P.sel.doc] || P.pending.doc).name}</h3>
        <p>Video consult · connected</p>
      </div>
      <div class="call-self"><svg data-lucide="user"></svg></div>
      <div class="call-controls">
        <button class="call-btn" onclick="this.classList.toggle('muted')"><svg data-lucide="mic"></svg></button>
        <button class="call-btn" onclick="this.classList.toggle('muted')"><svg data-lucide="video-off"></svg></button>
        <button class="call-btn end" onclick="P.endCall()"><svg data-lucide="phone-off"></svg></button>
      </div>
    </div>`,
  enter: () => {
    P.callT = 0;
    P.callInt = setInterval(() => {
      P.callT++;
      const el = document.getElementById("call-timer");
      if (el) el.textContent = "0" + Math.floor(P.callT / 60) + ":" + String(P.callT % 60).padStart(2, "0");
    }, 1000);
  },
  leave: () => clearInterval(P.callInt),
};
P.endCall = () => {
  clearInterval(P.callInt);
  P.completeBooking();
  Charak.go("visitdone");
};
P.completeBooking = (m) => {
  const b = P.pending || P.bookings[0];
  if (!b || b.status === "completed") return;
  if (b.channel === "home" && m && m.procs && m.procs.length) {
    b.procBill = {
      procs: m.procs,
      procTotal: m.procTotal !== undefined ? m.procTotal : m.procs.reduce((s, p) => s + p.p, 0),
      needsReview: !!m.needsReview,
      status: m.needsReview ? "review" : "approved",
    };
    Charak.go("procbill");
    return;
  }
  b.status = "completed";
  P.history.unshift(b);
  P.bookings = P.bookings.filter((x) => x.id !== b.id);
  Charak.simPost({ t: "complete" });
};

P.screens.visitdone = {
  html: () => `
    <div class="body" style="padding-top:44px">
      <div class="ok-state">
        <div class="wait-ic"><svg data-lucide="flag"></svg></div>
        <h1 class="title">Visit complete</h1>
        <p class="sub">Hope it went well. A quick rating helps other patients choose well.</p>
      </div>
    </div>
    <div class="cta-bar"><button class="btn primary" onclick="Charak.go('rate')">Rate your visit</button><button class="btn ghost" onclick="Charak.tab('history')">Skip</button></div>`,
};

P.screens.rate = {
  html: () => `
    <div class="body" style="padding-top:26px">
      <h1 class="screen-title" style="text-align:center">How was your visit?</h1>
      <p class="screen-sub" style="text-align:center">${(P.pending || P.bookings[0]).doc.name} · ${(P.pending || P.bookings[0]).channel === "home" ? "Home Visit" : "Online Consult"}</p>
      <div class="stars" id="stars">
        ${[1, 2, 3, 4, 5].map((i) => `<button class="${i <= (P.rateStars || 0) ? "on" : ""}" onclick="P.rateStars=${i};Charak.go('rate')"><svg data-lucide="star"></svg></button>`).join("")}
      </div>
      <p class="rate-hint" id="rate-hint">${["", "Poor", "Fair", "Good", "Very good", "Excellent"][P.rateStars || 0] || "Tap a star"}</p>
      <div class="field"><label>Add a comment (optional)</label><textarea class="input" style="min-height:90px" placeholder="What should other patients know?"></textarea></div>
    </div>
    <div class="cta-bar">
      <button class="btn primary" onclick="P.submitRate()">Submit rating</button>
    </div>`,
};
P.submitRate = () => {
  const b = P.pending || P.bookings[0];
  if (b && b.status === "completed") b.rated = P.rateStars || 5;
  Charak.tab("history");
  Charak.toast("Thanks for rating!");
};

P.screens.history = {
  tabbed: "history",
  html: () => {
    const months = { "August 2026": P.history.filter((x) => x.date.includes("Aug")) };
    const rows = P.history.length ? P.history.map((b) => `
      <button class="card hist-card pressable" onclick="P.actId='${b.id}';Charak.go('hdetail')">
        ${P.avatar(b.doc)}
        <div class="hist-info"><h3>${b.doc.name}</h3><p class="sub">${b.channel === "home" ? "Home Visit" : "Online"} · ${b.date}, ${b.time}</p></div>
        <div class="hist-right"><div class="amt tnum">₹${b.price}</div>
          <div class="st">${b.status === "completed" ? '<span class="badge success">Completed</span>' : '<span class="badge danger">Cancelled</span>'}</div>
        </div>
      </button>`).join("") : "";
    return `
    <div class="body" style="padding-top:14px">
      <h1 class="screen-title">History</h1>
      <p class="screen-sub" style="margin-bottom:6px">Past visits, receipts and ratings</p>
      ${P.history.length ? `<p class="month">August 2026</p>` + rows : `
        <div class="empty-state">
          <span class="wait-ic"><svg data-lucide="archive"></svg></span>
          <h3>Nothing here yet</h3>
          <p>Completed visits will appear here with receipts and your ratings.</p>
        </div>`}
    </div>`;
  },
};

P.screens.hdetail = {
  html: () => {
    const b = P.history.find((x) => x.id === P.actId) || P.history[0];
    return `
    <div class="topbar">
      <button class="iconbtn" onclick="Charak.back()"><svg data-lucide="arrow-left"></svg></button>
      <div class="tb-center"><div class="tb-title">Visit details</div></div>
      <div style="width:44px"></div>
    </div>
    <div class="body" style="padding-top:12px">
      <div class="card rev-sum">
        <div class="rev-row"><span class="k">Doctor</span><span class="v">${b.doc.name}</span></div>
        <div class="rev-row"><span class="k">When</span><span class="v">${b.date}, ${b.time}</span></div>
        <div class="rev-row"><span class="k">Channel</span><span class="v">${b.channel === "home" ? "Home Visit" : "Online Consult"}</span></div>
        <div class="rev-div"></div>
        <div class="rev-row"><span class="k">Consult fee · 15 min</span><span class="v tnum">₹${b.price}</span></div>
        ${b.procBill && b.procBill.procs ? b.procBill.procs.map((p) => `<div class="rev-row"><span class="k">${p.n}</span><span class="v tnum">₹${p.p}</span></div>`).join("") : ""}
        ${b.procBill && b.procBill.procTotal ? `<div class="rev-row"><span class="k">Procedures</span><span class="v tnum">₹${b.procBill.procTotal}</span></div>` : ""}
        <div class="rev-row"><span class="k">Amount</span><span class="v tnum">₹${b.price + (b.procBill ? b.procBill.procTotal : 0)}</span></div>
        <div class="rev-row"><span class="k">Paid via</span><span class="v muted">UPI · RZP-204188</span></div>
        <div class="rev-row"><span class="k">Status</span><span class="v">${Charak.statusPill(b.status)}</span></div>
      </div>
      ${b.rated ? `
        <div class="card rev-sum" style="margin-top:12px">
          <p class="sec-title" style="margin-bottom:8px">Your rating</p>
          <div style="display:flex;gap:4px;color:var(--color-warning)">
            ${[1, 2, 3, 4, 5].map((i) => `<svg style="width:18px;height:18px;fill:currentColor;${i <= b.rated ? "" : "color:var(--color-border)"}" data-lucide="star"></svg>`).join("")}
          </div>
        </div>` : ""}
      <button class="btn text" style="margin-top:8px" onclick="P.go('complaint')">Submit a complaint about this visit</button>
    </div>`;
  },
};

P.screens.profile = {
  tabbed: "profile",
  html: () => `
    <div class="body" style="padding-top:14px">
      <div class="card" style="padding:18px;display:flex;align-items:center;gap:14px">
        <div class="avatar av-1">${P.user.name.split(" ").map((w) => w[0]).join("")}</div>
        <div><h3 style="font-size:17px;font-weight:600">${P.user.name}</h3><p style="font-size:13px;color:var(--color-ink-muted);margin-top:2px" class="tnum">${P.user.phone}</p></div>
      </div>
      <div style="margin-top:18px">
        <button class="listrow" onclick="Charak.toast('Edit profile — coming in full build')"><span class="lr-ic"><svg data-lucide="user"></svg></span><span class="lr-txt">Edit Profile</span><span class="lr-end"><svg data-lucide="chevron-right"></svg></span></button>
        <button class="listrow" onclick="Charak.toast('UPI + card on file')"><span class="lr-ic"><svg data-lucide="credit-card"></svg></span><span class="lr-txt">Payment Methods</span><span class="lr-sub">UPI · HDFC •• 4821</span><span class="lr-end"><svg data-lucide="chevron-right"></svg></span></button>
        <button class="listrow" onclick="P.go('complaint')"><span class="lr-ic"><svg data-lucide="message-square-warning"></svg></span><span class="lr-txt">Submit a Complaint</span><span class="lr-end"><svg data-lucide="chevron-right"></svg></span></button>
        <button class="listrow" onclick="Charak.toast('Help centre — coming in full build')"><span class="lr-ic"><svg data-lucide="life-buoy"></svg></span><span class="lr-txt">Help</span><span class="lr-end"><svg data-lucide="chevron-right"></svg></span></button>
        <button class="listrow" onclick="P.reset()"><span class="lr-ic" style="color:var(--color-danger)"><svg data-lucide="log-out"></svg></span><span class="lr-txt" style="color:var(--color-danger)">Logout</span></button>
      </div>
    </div>`,
};

P.screens.complaint = {
  html: () => `
    <div class="topbar">
      <button class="iconbtn" onclick="Charak.back()"><svg data-lucide="arrow-left"></svg></button>
      <div class="tb-center"><div class="tb-title">Submit a complaint</div></div>
      <div style="width:44px"></div>
    </div>
    <div class="body" style="padding-top:12px">
      <p class="screen-sub" style="margin-bottom:14px">Tied to a booking — handled by our team, not the doctor.</p>
      <p class="sec-title" style="margin-bottom:8px">Which booking?</p>
      <div class="comp-picker">
        ${P.history.slice(0, 3).map((b, i) => `
          <button class="comp-pick ${i === 0 ? "on" : ""}" onclick="this.parentElement.querySelectorAll('.comp-pick').forEach(x=>x.classList.remove('on'));this.classList.add('on')">
            ${b.doc.name.split(" ")[1]} · ${b.date}</button>`).join("")}
      </div>
      <div class="field" style="margin-top:18px"><label>Describe the issue</label>
        <textarea class="input" style="min-height:110px" placeholder="What went wrong? Be specific — dates, times, anything the team should know."></textarea>
      </div>
      <p class="exp-line"><svg data-lucide="shield-check"></svg><span>A member of our team will review this within 1–2 working days and get back to you here.</span></p>
    </div>
    <div class="cta-bar"><button class="btn primary" onclick="P.submitComplaint()">Submit complaint</button></div>`,
};
P.submitComplaint = () => {
  Charak.go("complaint");
  document.querySelector(".cta-bar .btn").disabled = true;
  const body = document.querySelector(".scr .body");
  body.innerHTML = `
    <div class="ok-state">
      <div class="ok-ic">${Charak.checkSvg(88)}</div>
      <h1 class="title">Complaint received</h1>
      <p class="sub">Ref <span class="ref-no">CMP-2081</span> — we'll review it within 1–2 working days.</p>
      <button class="btn ghost" style="max-width:220px;margin-top:20px" onclick="Charak.tab('profile')">Back to profile</button>
    </div>`;
  Charak.refreshIcons && Charak.refreshIcons(document);
  Charak.simPost({ t: "complaint" });
};

/* ---------- live-sync simulation ---------- */
P.onSim = (m) => {
  if (m.t === "accept") {
    if (P.pending) P.pending.status = "accepted";
    if (Charak.stack[Charak.stack.length - 1] === "sent") { Charak.go("accepted"); Charak.toast("Doctor accepted your request"); }
    else Charak.toast("Your request was accepted");
  }
  if (m.t === "decline") {
    if (P.pending) P.pending.status = "declined";
    if (Charak.stack[Charak.stack.length - 1] === "sent") { Charak.go("declined"); Charak.toast("Doctor declined the request"); }
  }
  if (m.t === "complete") {
    const cur = Charak.stack[Charak.stack.length - 1];
    if (["active", "call"].includes(cur)) { P.completeBooking(m); if (!P.pending.procBill) Charak.go("visitdone"); }
  }
  if (m.t === "clarify") {
    P.clarify = true;
    Charak.toast("Clarification call scheduled");
  }
};
P.simAccept = () => Charak.simPost({ t: "accept" });
P.simDecline = () => Charak.simPost({ t: "decline" });
P.simClarify = () => Charak.simPost({ t: "clarify" });
P.screens.procbill = {
  html: () => {
    const b = P.pending || P.bookings[0];
    const bill = b.procBill;
    const d = b.doc;
    const waiting = bill.status === "review";
    return `
    <div class="topbar">
      <button class="iconbtn" onclick="Charak.back()"><svg data-lucide="arrow-left"></svg></button>
      <div class="tb-center"><div class="tb-title">Visit complete</div></div>
      <div style="width:44px"></div>
    </div>
    <div class="body" style="padding-top:12px">
      <div class="ok-state" style="padding:16px 0 0">
        <div class="wait-ic"><svg data-lucide="receipt"></svg></div>
        <h1 class="title" style="font-size:22px">Procedures from your visit</h1>
        <p class="sub">${d.name} did the following during your home visit. Charged at the fixed rates on their profile.</p>
      </div>
      <div class="card rev-sum" style="margin-top:22px">
        <div class="rev-row"><span class="k">Consult fee · 15 min</span><span class="v tnum">₹${b.price} <span class="paid-tag">Paid</span></span></div>
        <div class="rev-div"></div>
        ${bill.procs.map((p) => `<div class="rev-row"><span class="k">${p.n}</span><span class="v tnum">₹${p.p}</span></div>`).join("")}
        <div class="rev-div"></div>
        <div class="rev-row"><span class="k">Procedures total</span><span class="v tnum">₹${bill.procTotal}</span></div>
      </div>
      ${waiting ? `
        <div class="clarify-banner" style="align-items:flex-start"><svg data-lucide="shield-alert"></svg>
          <span><b>Under senior review</b> — procedure bills above ₹${P.threshOf(d)} are checked by a senior doctor to make sure everything was necessary. You'll be asked to pay once approved.</span>
        </div>
        <p class="hint-line" style="text-align:center">Use the dock to simulate the senior doctor approving or flagging this bill.</p>` : `
        <div class="act-timer" style="background:rgba(31,170,109,0.1);justify-content:flex-start;gap:10px">
          <svg data-lucide="shield-check" style="width:16px;height:16px;color:var(--color-success)"></svg>
          <span class="t" style="color:var(--color-success)">${bill.needsReview ? "Reviewed & approved by a senior doctor" : "Bill confirmed"} — pay to finish</span>
        </div>`}
    </div>
    <div class="cta-bar">
      ${waiting ? `<button class="btn primary" disabled>Awaiting senior review</button>`
                 : `<button class="btn primary" onclick="P.payProcs()">Pay ₹${bill.procTotal}</button>`}
    </div>`;
  },
};
P.payProcs = () => {
  const b = P.pending || P.bookings[0];
  if (!b || b.status === "completed") return;
  b.procBill.paid = true;
  b.status = "completed";
  P.history.unshift(b);
  P.bookings = P.bookings.filter((x) => x.id !== b.id);
  Charak.simPost({ t: "procPaid" });
  Charak.go("visitdone");
};
P.simSeniorApprove = () => {
  const b = P.pending || P.bookings[0];
  if (b && b.procBill && b.procBill.status === "review") {
    b.procBill.status = "approved";
    Charak.simPost({ t: "seniorApproved" });
    if (Charak.stack[Charak.stack.length - 1] === "procbill") Charak.go("procbill");
    Charak.toast("Senior doctor approved the procedure bill");
  } else Charak.toast("No procedure bill awaiting review");
};
P.simSeniorFlag = () => {
  const b = P.pending || P.bookings[0];
  if (b && b.procBill && b.procBill.status === "review") {
    const flagged = b.procBill.procs.pop();
    b.procBill.procTotal = b.procBill.procs.reduce((s, p) => s + p.p, 0);
    b.procBill.status = "approved";
    Charak.simPost({ t: "seniorFlagged", n: flagged.n });
    if (Charak.stack[Charak.stack.length - 1] === "procbill") Charak.go("procbill");
    Charak.toast("Senior doctor flagged " + flagged.n + " — removed from bill");
  } else Charak.toast("No procedure bill awaiting review");
};
P.simComplete = () => {
  const b = P.pending || P.bookings[0];
  if (b && b.channel === "home") {
    const list = P.procsOf(b.doc).slice(0, 3);
    const procTotal = list.reduce((s, p) => s + p.p, 0);
    Charak.simPost({ t: "complete", procs: list, procTotal, needsReview: procTotal >= P.threshOf(b.doc) });
  } else Charak.simPost({ t: "complete" });
};
P.reset = () => {
  clearInterval(P.callInt);
  P.sel = { spec: "General Physician", doc: null, date: "Today", time: null, channel: "online" };
  P.intake = { type: "text", text: "", transcript: "", rec: false };
  P.bookings = []; P.history = []; P.pending = null; P.clarify = false; P.rateStars = 0;
  P.user.firstTime = true;
  Charak.toast("Demo reset");
  Charak.go("splash");
};

/* ---------- boot ---------- */
Object.assign(Charak.screens, P.screens);
Charak.onSim = P.onSim;
Charak.toggleDock = () => {
  const d = document.getElementById("dock");
  d.classList.toggle("collapsed");
  d.querySelector(".dock-head button").textContent = d.classList.contains("collapsed") ? "+" : "−";
};
document.querySelectorAll(".tab-item").forEach((b) => (b.onclick = () => Charak.tab(b.dataset.tab)));
Charak.go("splash");
