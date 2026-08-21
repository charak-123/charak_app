/* ============================================================
   CHARAK Doctor App — screens, flows, live-sync simulation
   ============================================================ */
const D = {
  verified: false,
  me: { name: "Dr. Aarav Mehta", spec: "General Physician", ini: "AM", tone: 1, phone: "+91 98200 11223" },
  setup: {
    online: true, home: true, radius: 3,
    onlineMin: 15, onlinePrice: 500, onlineExtra: 150,
    homeMin: 15, homePrice: 800, homeExtra: 200,
    procThresh: 500,
    procs: [
      { n: "ECG", p: 250 }, { n: "Dressing", p: 200 }, { n: "Injection", p: 150 },
      { n: "Nebulization", p: 300 }, { n: "Stitch removal", p: 350 },
    ],
  },
  sched: { Mon: ["9:00–12:00", "5:00–8:00"], Tue: ["9:00–12:00", "5:00–8:00"], Wed: ["9:00–12:00", "5:00–8:00"], Thu: ["9:00–12:00", "5:00–8:00"], Fri: ["9:00–12:00", "5:00–8:00"], Sat: ["10:00–1:00"], Sun: [] },
  blocked: [{ date: "Today", t: "4:00 PM–5:00 PM", reason: "Personal" }],
  requests: [
    { id: "RQ-3897", name: "Anita Sharma", ini: "AS", tone: 4, cat: "General Physician", channel: "home", slot: "Today, 6:00 PM", price: 800, dist: "2.4 km", addr: "Sector 17, Vashi", status: "new", text: "My mother has had pain in both knees for about a week. It is worse in the morning. She is 62 and diabetic.", voice: true, voiceTxt: "Also, she finished her BP medicine yesterday — please check if she needs a refill.", photos: 1 },
    { id: "RQ-3895", name: "Rakesh Iyer", ini: "RI", tone: 5, cat: "Cardiology", channel: "online", slot: "Today, 7:30 PM", price: 600, dist: "", addr: "", status: "pending", text: "Mild chest tightness after climbing stairs, twice this week. On Metoprolol 25. Attaching my ECG report.", voice: false, photos: 1 },
    { id: "RQ-3893", name: "Meera Joshi", ini: "MJ", tone: 6, cat: "Physiotherapy", channel: "home", slot: "Tomorrow, 10:00 AM", price: 750, dist: "3.1 km", addr: "Sector 21, Nerul", status: "pending", text: "Recovering from ACL surgery in May. Would like a home physio session for range-of-motion work.", voice: false, photos: 0 },
  ],
  actId: null,
  active: null,
  paidFlag: false,
  earnings: [
    { when: "Mon", cat: "General", channel: "Home Visit", amt: 800 },
    { when: "Tue", cat: "General", channel: "Online", amt: 500 },
    { when: "Wed", cat: "Pediatrics", channel: "Online", amt: 550 },
  ],
  callMode: "clarify",
};

/* ---------- helpers ---------- */
D.req = (id) => D.requests.find((r) => r.id === id) || D.requests[0];
D.go = (id) => Charak.go(id);
D.avatar = (r) => Charak.avatar(r.ini, r.tone);

D.reqCard = (r) => `
  <article class="card req-card ${r.status === "new" ? "new" : ""} ${r.status === "new" ? "arrive" : ""}" id="req-${r.id}">
    ${r.status === "new" ? '<span class="req-tag">New</span>' : ""}
    <div class="req-top">
      ${D.avatar(r)}
      <div class="who"><h3>${r.name}</h3><p class="sub">${r.cat} · ${r.channel === "home" ? "Home Visit" : "Online Consult"}</p></div>
    </div>
    <div class="req-mid"><svg data-lucide="clock"></svg>${r.slot}<span class="price tnum">₹${r.price}<span class="per">/15m</span></span></div>
    ${r.dist ? `<p style="display:flex;align-items:center;gap:6px;font-size:12.5px;color:var(--color-ink-muted);margin-top:6px"><svg style="width:13px;height:13px" data-lucide="map-pin"></svg>${r.dist} · ${r.addr}</p>` : ""}
    <div class="req-actions">
      <button class="btn ghost" onclick="D.decline('${r.id}')">Decline</button>
      <button class="btn primary" onclick="D.actId='${r.id}';Charak.go('detail')">Review</button>
    </div>
  </article>`;

/* ---------- screens ---------- */
D.screens = {};

D.screens.splash = {
  html: () => `
    <div class="body center-col" style="justify-content:center;padding-bottom:80px">
      <div style="width:64px;height:64px;border-radius:18px;background:var(--color-ink);display:grid;place-items:center;margin-bottom:18px">
        <svg style="width:30px;height:30px;color:#fff" data-lucide="plus"></svg>
      </div>
      <div class="brand-mark">Chara<i>k</i> <span style="font-size:14px;font-weight:500;color:var(--color-ink-muted)">Partner</span></div>
      <p style="font-size:13.5px;color:var(--color-ink-muted);margin-top:6px">Your practice, your schedule, your price</p>
      <div style="margin-top:36px;width:220px">
        <div class="skel" style="height:12px"></div>
        <div class="skel" style="height:12px;margin-top:8px;width:160px;margin-left:auto"></div>
      </div>
    </div>`,
  enter: (el) => setTimeout(() => Charak.go("phone"), 1100),
};

D.screens.phone = {
  html: () => `
    <div class="body" style="padding-top:26px">
      <h1 class="screen-title">Your phone number</h1>
      <p class="screen-sub">Same OTP flow as patients — one identity per doctor.</p>
      <div style="margin-top:26px">
        <div class="field">
          <label>Mobile number</label>
          <div style="display:flex;gap:10px">
            <div class="input" style="width:92px;display:flex;align-items:center;font-weight:500;color:var(--color-ink-muted)">+91</div>
            <input class="input" id="doc-phone" style="flex:1" value="98200 11223" maxlength="10" inputmode="numeric">
          </div>
        </div>
      </div>
    </div>
    <div class="cta-bar"><button class="btn primary" onclick="Charak.go('otp')">Continue</button></div>`,
  enter: (el) => setTimeout(() => { const i = el.querySelector("#doc-phone"); i && i.focus(); }, 120),
};

D.screens.otp = {
  html: () => `
    <div class="body" style="padding-top:26px">
      <h1 class="screen-title">Enter the code</h1>
      <p class="screen-sub">Sent to +91 98200 11223</p>
      <div class="otp-row">
        ${[0, 1, 2, 3, 4, 5].map((i) => `<input class="otp-cell" id="d-otp${i}" maxlength="1" inputmode="numeric">`).join("")}
      </div>
      <p class="countdown">Resend code in <b class="tnum">0:26</b></p>
    </div>
    <div class="cta-bar"><button class="btn primary" onclick="Charak.go('setup')">Verify</button></div>`,
  enter: (el) => {
    const cells = el.querySelectorAll(".otp-cell");
    cells.forEach((c, i) => {
      c.addEventListener("input", () => { if (c.value && i < 5) cells[i + 1].focus(); });
      c.addEventListener("keydown", (e) => { if (e.key === "Backspace" && !c.value && i > 0) cells[i - 1].focus(); });
    });
    setTimeout(() => cells[0].focus(), 120);
  },
};

D.screens.setup = {
  html: () => `
    <div class="body" style="padding-top:16px">
      <div class="step-dots"><i class="on"></i><i></i><i></i></div>
      <h1 class="screen-title" style="margin-top:10px">Set up your profile</h1>
      <p class="screen-sub" style="margin-bottom:18px">One screen, fill it once — this is what patients see in the directory.</p>
      <div class="field" style="margin-bottom:12px"><label>Full name</label><input class="input" value="Dr. Aarav Mehta"></div>
      <div class="field" style="margin-bottom:12px"><label>Specialty</label>
        <select class="input" style="appearance:auto">
          <option>General Physician</option><option>Orthopedic</option><option>Nurse</option><option>Cardiology</option>
          <option>Dermatology</option><option>Gynecology</option><option>Pediatrics</option><option>Dentistry</option><option>Physiotherapy</option>
        </select>
      </div>
      <div class="field" style="margin-bottom:12px"><label>Profile photo</label>
        <button class="upload-tile" onclick="this.classList.add('has');this.innerHTML='<svg data-lucide=\\'check\\'></svg>Photo added — patients see this in the directory'">
          <svg data-lucide="camera"></svg>Upload a clear, professional photo
        </button>
      </div>
      <div class="field"><label>Bio (1–2 lines)</label>
        <textarea class="input" style="min-height:80px">General physician with 9 years in family practice. Sees everything from routine fevers to chronic-condition follow-ups.</textarea>
      </div>
    </div>
    <div class="cta-bar"><button class="btn primary" onclick="Charak.go('verify')">Continue</button></div>`,
};

D.screens.verify = {
  html: () => `
    <div class="body" style="padding-top:16px">
      <div class="step-dots"><i class="on"></i><i class="on"></i><i></i></div>
      <h1 class="screen-title" style="margin-top:10px">Verify your license</h1>
      <p class="screen-sub" style="margin-bottom:18px">Manual check by our team — usually within 1 working day. You can explore the app meanwhile.</p>
      <div class="field" style="margin-bottom:12px"><label>Medical council registration no.</label><input class="input tnum" value="MCI-118342"></div>
      <div class="field" style="margin-bottom:12px"><label>Degree certificate / council ID</label>
        <button class="upload-tile" onclick="this.classList.add('has');this.innerHTML='<svg data-lucide=\\'file-check\\'></svg>certificate.pdf attached'">
          <svg data-lucide="upload"></svg>Upload photo or PDF
        </button>
      </div>
      <p class="exp-line"><svg data-lucide="shield-check"></svg><span>Your registration number, degree and ID are checked by a human on our team. Nothing is automated.</span></p>
    </div>
    <div class="cta-bar"><button class="btn primary" onclick="Charak.go('pending')">Submit for verification</button></div>`,
};

D.screens.pending = {
  html: () => `
    <div class="body" style="padding-top:40px">
      <div class="ok-state">
        <div class="wait-ic"><svg data-lucide="clipboard-check"></svg></div>
        <h1 class="title" style="font-size:21px">Under review</h1>
        <p class="sub">Our team is verifying your license. You can set up your practice now — you'll appear in the directory the moment you're approved.</p>
        <span class="status-pill warning" style="margin-top:18px"><span class="wait-dot"></span>Under review</span>
        <button class="btn ghost" style="max-width:220px;margin-top:22px" onclick="Charak.toast('Explore the app — nothing goes live until approved')">Explore the app</button>
        <p class="hint-line" style="text-align:center">Demo: use the dock to simulate ops approving you.</p>
      </div>
    </div>`,
};

D.screens.channels = {
  html: () => `
    <div class="body" style="padding-top:16px">
      <div class="step-dots"><i></i><i></i><i class="on"></i></div>
      <h1 class="screen-title" style="margin-top:10px">How do you practice?</h1>
      <p class="screen-sub" style="margin-bottom:18px">Pick one or both. A cardiologist can simply skip Home Visit.</p>
      <button class="tog-card ${D.setup.online ? "on" : ""}" onclick="D.setup.online=!D.setup.online;Charak.go('channels')">
        <span class="tog-ic"><svg data-lucide="video"></svg></span>
        <div><h3>Online Consult</h3><p>Video consults on your scheduled hours.</p></div>
        <span class="tog-sw"></span>
      </button>
      <button class="tog-card ${D.setup.home ? "on" : ""}" onclick="D.setup.home=!D.setup.home;Charak.go('channels')">
        <span class="tog-ic"><svg data-lucide="home"></svg></span>
        <div><h3>Home Visit</h3><p>You travel to the patient, within your radius.</p></div>
        <span class="tog-sw"></span>
      </button>
    </div>
    <div class="cta-bar"><button class="btn primary" onclick="D.channelsNext()">Continue</button></div>`,
};
D.channelsNext = () => {
  if (!D.setup.online && !D.setup.home) { Charak.toast("Pick at least one channel"); return; }
  if (D.setup.online && D.setup.home) Charak.go("online");
  else if (D.setup.online) Charak.go("online");
  else Charak.go("homevisit");
};

D.screens.online = {
  html: () => `
    <div class="body" style="padding-top:16px">
      <h1 class="screen-title">Online consult hours</h1>
      <p class="screen-sub" style="margin-bottom:10px">Weekly template — patients book into these slots.</p>
      <div style="margin-top:8px">
        ${Object.entries(D.sched).map(([day, blocks]) => `
          <div class="day-row">
            <span class="day ${blocks.length ? "" : "off"}">${day}</span>
            <div class="block-chips">
              ${blocks.map((b) => `<span class="block-chip">${b}<svg data-lucide="x" onclick="D.delBlock('${day}','${b}')"></svg></span>`).join("") || '<span style="font-size:12.5px;color:var(--color-ink-muted)">No hours</span>'}
            </div>
            <button class="block-add" onclick="D.addBlock('${day}')"><svg data-lucide="plus"></svg></button>
          </div>`).join("")}
      </div>
    </div>
    <div class="cta-bar"><button class="btn primary" onclick="D.setup.home ? Charak.go('homevisit') : Charak.go('pricing')">Continue</button></div>`,
};
D.addBlock = (day) => { D.sched[day].push("5:00–8:00 PM"); Charak.go("online"); };
D.delBlock = (day, b) => { D.sched[day] = D.sched[day].filter((x) => x !== b); Charak.go("online"); };

D.screens.homevisit = {
  html: () => `
    <div class="body" style="padding-top:16px">
      <h1 class="screen-title">Home visits</h1>
      <p class="screen-sub" style="margin-bottom:16px">Schedule, radius and base location.</p>
      <p class="sec-title" style="margin-bottom:9px">Service radius</p>
      <div class="rad-chips" style="margin-bottom:18px">
        ${[2, 3, 5].map((r) => `<button class="rad-chip ${D.setup.radius === r ? "on" : ""}" onclick="D.setup.radius=${r};Charak.go('homevisit')">${r} km</button>`).join("")}
      </div>
      <p class="sec-title" style="margin-bottom:9px">Base location</p>
      <button class="card" style="display:flex;align-items:center;gap:11px;padding:13px 14px;margin-bottom:20px;width:100%;text-align:left" onclick="Charak.toast('Set via map or address search')">
        <span class="lr-ic" style="width:36px;height:36px;border-radius:10px;background:var(--color-primary-soft);display:grid;place-items:center;color:var(--color-primary-deep);flex:none"><svg style="width:16px;height:16px" data-lucide="map-pin"></svg></span>
        <span style="flex:1"><span style="display:block;font-size:14px;font-weight:600">Clinic · Sector 12, Vashi</span><span style="font-size:12px;color:var(--color-ink-muted)">19.0663° N, 72.9982° E</span></span>
        <svg style="width:16px;height:16px;color:var(--color-ink-muted)" data-lucide="chevron-right"></svg>
      </button>
      <p class="sec-title" style="margin-bottom:9px">Visit hours</p>
      <div class="card" style="padding:4px 14px">
        ${Object.entries(D.sched).map(([day, blocks]) => `
          <div class="day-row">
            <span class="day ${blocks.length ? "" : "off"}">${day}</span>
            <div class="block-chips">
              ${blocks.map((b) => `<span class="block-chip">${b}</span>`).join("") || '<span style="font-size:12.5px;color:var(--color-ink-muted)">No hours</span>'}
            </div>
            <button class="block-add" onclick="D.addBlock('${day}')"><svg data-lucide="plus"></svg></button>
          </div>`).join("")}
      </div>
    </div>
    <div class="cta-bar"><button class="btn primary" onclick="Charak.go('pricing')">Continue</button></div>`,
};

D.screens.pricing = {
  html: () => `
    <div class="body" style="padding-top:16px">
      <div class="step-dots"><i></i><i></i><i class="on"></i></div>
      <h1 class="screen-title" style="margin-top:10px">Set your prices</h1>
      <p class="screen-sub" style="margin-bottom:18px">Consult fee covers a base time (min 15 min). Extra time is charged per additional 15 min — your call.</p>
      ${D.setup.online ? `
        <div class="field" style="margin-bottom:12px"><label>Online Consult</label>
          <div style="display:flex;gap:10px;align-items:center;margin-bottom:8px">
            <span style="font-size:18px;font-weight:600" class="tnum">₹</span>
            <input class="input tnum" id="p-online" value="${D.setup.onlinePrice}" inputmode="numeric">
            <span class="price-suffix">per 15 min</span>
          </div>
          <div style="display:flex;gap:10px;align-items:center">
            <input class="input tnum" id="p-online-x" value="${D.setup.onlineExtra}" inputmode="numeric" style="width:86px" title="extra per 15 min">
            <span class="price-suffix">extra per 15 min</span>
          </div>
        </div>` : ""}
      ${D.setup.home ? `
        <div class="field" style="margin-bottom:14px"><label>Home Visit</label>
          <div style="display:flex;gap:10px;align-items:center;margin-bottom:8px">
            <span style="font-size:18px;font-weight:600" class="tnum">₹</span>
            <input class="input tnum" id="p-home" value="${D.setup.homePrice}" inputmode="numeric">
            <span class="price-suffix">per 15 min</span>
          </div>
          <div style="display:flex;gap:10px;align-items:center">
            <input class="input tnum" id="p-home-x" value="${D.setup.homeExtra}" inputmode="numeric" style="width:86px" title="extra per 15 min">
            <span class="price-suffix">extra per 15 min</span>
          </div>
        </div>` : ""}
      <p class="sec-title" style="margin-bottom:9px">Procedure prices · fixed</p>
      <p class="screen-sub" style="font-size:13px;margin-bottom:12px">Shown to patients on your profile. Charged only after a home visit, for what's actually done.</p>
      ${D.setup.procs.map((p, i) => `
        <div class="proc-price-row">
          <span>${p.n}</span>
          <div style="display:flex;align-items:center;gap:8px"><span style="font-weight:600" class="tnum">₹</span>
            <input class="input tnum proc-in" id="proc-${i}" value="${p.p}" inputmode="numeric"></div>
        </div>`).join("")}
      <p class="sec-title" style="margin:16px 0 9px">Senior review threshold</p>
      <div class="field"><label>Review procedure bills above</label>
        <div style="display:flex;gap:10px;align-items:center">
          <span style="font-size:18px;font-weight:600" class="tnum">₹</span>
          <input class="input tnum" id="p-thresh" value="${D.setup.procThresh}" inputmode="numeric" style="width:120px">
        </div>
      </div>
      <div class="price-preview">Patients see <b>₹${D.setup.onlinePrice}</b> online${D.setup.home ? ` and <b>₹${D.setup.homePrice}</b> for home visits` : ""} for a 15-min consult — plus your fixed procedure rates and the senior-review note.</div>
    </div>
    <div class="cta-bar"><button class="btn primary" onclick="D.pricingDone()">Finish — go live</button></div>`,
  enter: (el) => {
    const po = el.querySelector("#p-online"); po && po.addEventListener("input", () => (D.setup.onlinePrice = +po.value || 0));
    const pox = el.querySelector("#p-online-x"); pox && pox.addEventListener("input", () => (D.setup.onlineExtra = +pox.value || 0));
    const ph = el.querySelector("#p-home"); ph && ph.addEventListener("input", () => (D.setup.homePrice = +ph.value || 0));
    const phx = el.querySelector("#p-home-x"); phx && phx.addEventListener("input", () => (D.setup.homeExtra = +phx.value || 0));
    const pt = el.querySelector("#p-thresh"); pt && pt.addEventListener("input", () => (D.setup.procThresh = +pt.value || 0));
    D.setup.procs.forEach((p, i) => {
      const inp = el.querySelector("#proc-" + i); inp && inp.addEventListener("input", () => (D.setup.procs[i].p = +inp.value || 0));
    });
  },
};
D.pricingDone = () => {
  Charak.tab("requests");
  Charak.toast("You're live in the directory");
};

D.screens.requests = {
  tabbed: "requests",
  html: () => `
    <div class="body" style="padding-top:14px">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:4px">
        <h1 class="screen-title">Requests</h1>
        <span class="badge primary">${D.requests.filter((r) => r.status === "new").length} new</span>
      </div>
      <p class="screen-sub" style="margin-bottom:14px">Decide on each — new requests arrive live.</p>
      ${D.requests.length ? D.requests.map(D.reqCard).join("") : `
        <div class="empty-state">
          <span class="wait-ic"><svg data-lucide="inbox"></svg></span>
          <h3>All caught up</h3>
          <p>New booking requests will appear here the moment a patient sends one.</p>
          <button class="btn ghost" style="max-width:200px" onclick="D.simNewRequest()">Simulate a new request</button>
        </div>`}
    </div>`,
};

D.screens.detail = {
  html: () => {
    const r = D.req(D.actId);
    return `
    <div class="topbar">
      <button class="iconbtn" onclick="Charak.back()"><svg data-lucide="arrow-left"></svg></button>
      <div class="tb-center"><div class="tb-title">Request</div></div>
      <div style="width:44px"></div>
    </div>
    <div class="body" style="padding-top:10px">
      <div class="card pat-strip">
        ${D.avatar(r)}
        <div class="pat-info">
          <h3>${r.name}</h3>
          <p class="sub">${r.cat} · ${r.channel === "home" ? "Home Visit" : "Online Consult"}</p>
        </div>
        <div class="pat-right">
          <div class="price tnum">₹${r.price}<span class="per">/15m</span></div>
          ${r.status === "new" ? '<span class="badge warning" style="margin-top:4px">New</span>' : ""}
        </div>
      </div>
      <p class="sec-title" style="margin-bottom:9px">What the patient said</p>
      <div class="intake-blk">
        <div class="bhead"><svg data-lucide="type"></svg>Typed note</div>
        <p>${r.text}</p>
      </div>
      ${r.voice ? `
        <div class="intake-blk">
          <div class="bhead"><svg data-lucide="mic"></svg>Voice note · 0:42<span class="vtag">Transcribed</span></div>
          <p>${r.voiceTxt}</p>
        </div>` : ""}
      ${r.photos ? `
        <div class="intake-blk">
          <div class="bhead"><svg data-lucide="image"></svg>Attachments</div>
          <button class="file-chip" onclick="Charak.toast('Opens full-screen in the app')"><svg data-lucide="image"></svg>${r.photos} photo${r.photos > 1 ? "s" : ""}</button>
          ${r.cat === "Cardiology" ? '<button class="file-chip" onclick="Charak.toast(\'Opens full-screen in the app\')"><svg data-lucide="file-text"></svg>ECG report.pdf</button>' : ""}
        </div>` : ""}
      <p class="sec-title" style="margin:16px 0 6px">Visit details</p>
      <div class="card" style="padding:6px 14px">
        <div class="visit-line"><svg data-lucide="clock"></svg><b>${r.slot}</b></div>
        ${r.channel === "home" ? `<div class="visit-line"><svg data-lucide="map-pin"></svg><b>${r.addr}</b> · ${r.dist}</div>` : `<div class="visit-line"><svg data-lucide="video"></svg><b>Video call</b> · join from active visit</div>`}
      </div>
      ${r.note ? `
        <div class="intake-blk" style="border:1px dashed var(--color-border);background:transparent;margin-top:12px">
          <div class="bhead"><svg data-lucide="sticky-note"></svg>Clarification call note</div>
          <p>${r.note}</p>
        </div>` : ""}
      <button class="btn ghost" style="margin-top:14px" onclick="D.callMode='clarify';Charak.go('call')"><svg class="icon" data-lucide="phone"></svg>Request clarification call</button>
    </div>
    <div class="cta-bar">
      <button class="btn ghost" onclick="D.decline('${r.id}')">Decline</button>
      <button class="btn primary" onclick="D.accept('${r.id}')">Accept</button>
    </div>`;
  },
};

D.decline = (id) => {
  const r = D.req(id);
  const el = document.getElementById("req-" + id);
  if (el) { el.classList.add("leaving"); setTimeout(() => { D.requests = D.requests.filter((x) => x.id !== id); Charak.go("requests"); }, 240); }
  else { D.requests = D.requests.filter((x) => x.id !== id); Charak.go("requests"); }
  Charak.toast("Request declined — patient notified");
  Charak.simPost({ t: "decline" });
};
D.accept = (id) => {
  const r = D.req(id);
  r.status = "accepted";
  r.procs = [];
  D.active = r;
  D.paidFlag = false;
  Charak.simPost({ t: "accept" });
  Charak.go("active");
};

D.screens.call = {
  html: () => `
    <div class="call-grid">
      <div class="call-top"><span class="rec"></span><span>${D.callMode === "clarify" ? "Clarification call" : "Consult in progress"}</span></div>
      <div class="call-peer">
        ${D.avatar(D.req(D.actId))}
        <h3>${D.req(D.actId).name}</h3>
        <p>${D.callMode === "clarify" ? "Clarification call · before you decide" : "Video consult"}</p>
      </div>
      <div class="call-self"><svg data-lucide="user"></svg></div>
      ${D.callMode === "clarify" ? `
        <div class="call-notes">
          <input id="call-note" placeholder="Equipment needed, prep notes… (kept for this booking)">
        </div>` : ""}
      <div class="call-controls">
        <button class="call-btn" onclick="this.classList.toggle('muted')"><svg data-lucide="mic"></svg></button>
        <button class="call-btn" onclick="this.classList.toggle('muted')"><svg data-lucide="video-off"></svg></button>
        <button class="call-btn end" onclick="D.endCall()"><svg data-lucide="phone-off"></svg></button>
      </div>
    </div>`,
  enter: () => {
    D.callT = 0;
    D.callInt = setInterval(() => {
      D.callT++;
      const el = document.querySelector(".call-top .tnum, .call-top span:last-child");
    }, 1000);
  },
  leave: () => clearInterval(D.callInt),
};
D.endCall = () => {
  clearInterval(D.callInt);
  const note = document.getElementById("call-note");
  if (D.callMode === "clarify") {
    const r = D.req(D.actId);
    if (note && note.value.trim()) r.note = note.value.trim();
    Charak.toast(r.note ? "Call note saved" : "Clarification call ended");
    Charak.back();
  } else {
    Charak.toast("Call ended");
    Charak.go("active");
  }
};

D.screens.active = {
  html: () => {
    const r = D.active || D.req(D.actId);
    const online = r.channel === "online";
    return `
    <div class="topbar">
      <button class="iconbtn" onclick="Charak.back()"><svg data-lucide="arrow-left"></svg></button>
      <div class="tb-center"><div class="tb-title">Active visit</div></div>
      <div style="width:44px"></div>
    </div>
    <div class="body" style="padding-top:10px">
      <div class="card act-doctor-card" style="padding:15px;display:flex;align-items:center;gap:12px;margin-bottom:12px">
        ${D.avatar(r)}
        <div style="flex:1;min-width:0"><h3 style="font-size:16px;font-weight:600">${r.name}</h3><p style="font-size:12.5px;color:var(--color-ink-muted);margin-top:1px">${r.cat} · ${r.slot}</p></div>
        <span class="status-pill success">Accepted</span>
      </div>
      ${D.paidFlag ? `
        <div class="clarify-banner" style="display:flex;align-items:center"><svg data-lucide="banknote"></svg>
          <span><b>Payment received</b> — ₹${r.price} confirmed. Visit proceeds.</span>
        </div>` : ""}
      <div class="card" style="padding:6px 14px;margin-bottom:14px">
        <div class="visit-line"><svg data-lucide="clock"></svg><b>${r.slot}</b></div>
        ${online ? `<div class="visit-line"><svg data-lucide="video"></svg><b>Video consult</b> — start the call at slot time</div>`
                  : `<div class="visit-line"><svg data-lucide="map-pin"></svg><b>${r.addr}</b> · ${r.dist}</div>`}
      </div>
      ${!online ? `
        <div class="card" style="padding:14px;margin-bottom:14px">
          <p class="sec-title" style="margin-bottom:2px">Procedures performed</p>
          <p style="font-size:12.5px;color:var(--color-ink-muted);margin:2px 0 10px">Tap the procedures done this visit — fixed rates apply. Patient is billed after the visit.</p>
          ${D.setup.procs.map((p) => `
            <label class="proc-check ${r.procs && r.procs.includes(p.n) ? "on" : ""}">
              <span>${p.n}</span><span class="tnum" style="color:var(--color-ink-muted)">₹${p.p}</span>
              <input type="checkbox" ${r.procs && r.procs.includes(p.n) ? "checked" : ""} onchange="D.toggleProc('${r.id}','${p.n}',this.checked)">
            </label>`).join("")}
          <div class="proc-total">Procedures total <b class="tnum">₹${D.procTotal(r)}</b></div>
          ${D.procTotal(r) >= D.setup.procThresh ? `
            <div class="clarify-banner" style="align-items:flex-start;margin-top:10px"><svg data-lucide="shield-alert"></svg>
              <span><b>Senior review needed</b> — this bill is above ₹${D.setup.procThresh}. A senior doctor verifies it before the patient pays.</span>
            </div>` : `
            <p class="hint-line" style="margin-top:8px">Bills above ₹${D.setup.procThresh} are auto-sent for senior review.</p>`}
        </div>` : ""}
      ${online ? `
        <button class="btn primary" style="margin-bottom:10px" onclick="D.callMode='consult';Charak.go('call')"><svg class="icon" data-lucide="video"></svg>Start call</button>
        <button class="btn ghost" onclick="Charak.toast('Opens native maps')"><svg class="icon" data-lucide="navigation"></svg>Directions to patient</button>`
        : `
        <button class="btn primary" style="margin-bottom:10px" onclick="Charak.toast('Opens native maps')"><svg class="icon" data-lucide="navigation"></svg>Navigate to patient</button>
        <button class="btn ghost" onclick="Charak.toast('Contact through app — no raw number')"><svg class="icon" data-lucide="message-circle"></svg>Contact patient</button>`}
      <p class="hint-line" style="text-align:center;margin-top:8px">Consult fee ₹${r.price} is confirmed from the request. Procedures are billed separately after the visit.</p>
    </div>
    <div class="cta-bar"><button class="btn primary" onclick="D.complete()"><svg class="icon" data-lucide="flag"></svg>Mark as complete</button></div>`;
  },
};
D.toggleProc = (id, name, on) => {
  const r = D.req(id);
  r.procs = r.procs || [];
  r.procs = on ? r.procs.concat(name) : r.procs.filter((x) => x !== name);
  Charak.go("active");
};
D.procTotal = (r) => {
  if (!r.procs) return 0;
  return D.setup.procs.filter((p) => r.procs.includes(p.n)).reduce((s, p) => s + p.p, 0);
};
D.complete = () => {
  const r = D.active;
  if (!r) { Charak.tab("requests"); return; }
  const procs = (r.procs || []).map((n) => D.setup.procs.find((p) => p.n === n)).filter(Boolean);
  const procTotal = procs.reduce((s, p) => s + p.p, 0);
  const needsReview = procTotal >= D.setup.procThresh;
  r.procsDone = procs;
  r.procTotal = procTotal;
  r.needsReview = needsReview;
  D.earnings.unshift({ when: r.slot.split(",")[0], cat: r.cat, channel: r.channel === "home" ? "Home Visit" : "Online", amt: r.price, procs: procs, procTotal: procTotal, needsReview: needsReview });
  D.requests = D.requests.filter((x) => x.id !== r.id);
  D.active = null;
  Charak.simPost({ t: "complete", procs: procs, procTotal: procTotal, needsReview: needsReview });
  Charak.tab("requests");
  Charak.toast(needsReview ? "Visit completed — procedures sent for senior review" : "Visit completed — patient can now pay");
};

D.screens.schedule = {
  tabbed: "schedule",
  html: () => `
    <div class="body" style="padding-top:14px">
      <div class="sched-head">
        <h1>Schedule</h1>
        <button class="btn ghost" onclick="D.blockSheet()">Block time</button>
      </div>
      <div class="week-strip">
        ${[["Mo", 12], ["Tu", 14], ["We", 8], ["Th", 10], ["Fr", 12], ["Sa", 6], ["Su", "–"]].map(([d, n], i) => `
          <button class="wday ${i === 2 ? "on" : ""}" onclick="Charak.toast('Week view — swipe to change day')"><span class="d">${d}</span><span class="n">${n}</span></button>`).join("")}
      </div>
      <p class="sec-title" style="margin-bottom:9px">Today, Wednesday</p>
      <div class="slot-row booked"><span class="t">10:00</span><div><p class="tt">Online Consult</p><p class="ts">General · ₹500</p></div><span class="st">Booked</span></div>
      <div class="slot-row open"><span class="t">11:00</span><div><p class="tt">Open slot</p><p class="ts">Bookable by patients</p></div><span class="st">Open</span></div>
      <div class="slot-row home"><span class="t">12:00</span><div><p class="tt">Home Visit</p><p class="ts">Anita Sharma · ₹800</p></div><span class="st">Booked</span></div>
      ${D.blocked.map((b) => `
        <div class="slot-row blocked"><span class="t">${b.t.split("–")[0]}</span><div><p class="tt">Blocked</p><p class="ts">${b.reason || "Personal"} · ${b.date}</p></div><span class="st">Blocked</span></div>`).join("")}
      <div class="slot-row booked"><span class="t">5:30</span><div><p class="tt">Online Consult</p><p class="ts">Cardiology · ₹600</p></div><span class="st">Booked</span></div>
    </div>`,
};
D.blockSheet = () => {
  Charak.openSheet("block", `
    <h2 class="sheet-title">Block a time slot</h2>
    <p style="font-size:13px;color:var(--color-ink-muted);margin-bottom:14px">One-off unavailability — your weekly template stays untouched.</p>
    <div class="comp-picker" style="margin-bottom:14px">
      <button class="comp-pick on" onclick="D.blockDate='Today';D.pick(this)">Today</button>
      <button class="comp-pick" onclick="D.blockDate='Tomorrow';D.pick(this)">Tomorrow</button>
      <button class="comp-pick" onclick="D.blockDate='Fri';D.pick(this)">Fri</button>
    </div>
    <div class="two-col" style="margin-bottom:16px">
      <div class="field"><label>From</label><select class="input"><option>4:00 PM</option><option>5:00 PM</option><option>6:00 PM</option></select></div>
      <div class="field"><label>To</label><select class="input"><option>5:00 PM</option><option>6:00 PM</option><option>7:00 PM</option></select></div>
    </div>
    <button class="btn primary" onclick="D.doBlock()">Block slot</button>`);
  D.blockDate = "Today";
  D.pick = (el) => { el.parentElement.querySelectorAll(".comp-pick").forEach((x) => x.classList.remove("on")); el.classList.add("on"); };
};
D.doBlock = () => {
  D.blocked.push({ date: D.blockDate || "Today", t: "4:00 PM–5:00 PM", reason: "Personal" });
  Charak.closeSheet();
  Charak.go("schedule");
  Charak.toast("Slot blocked for " + (D.blockDate || "Today"));
};

D.screens.earnings = {
  tabbed: "earnings",
  html: () => {
    const total = D.earnings.reduce((s, e) => s + e.amt, 0);
    return `
    <div class="body" style="padding-top:14px">
      <h1 class="screen-title">Earnings</h1>
      <p class="screen-sub" style="margin-bottom:14px">This month · V1 keeps it simple</p>
      <div class="earn-total">
        <div class="l">Total · August 2026</div>
        <div class="v tnum">₹${total.toLocaleString("en-IN")}</div>
      </div>
      <p class="sec-title" style="margin-bottom:4px">Completed bookings</p>
      ${D.earnings.map((e) => `
        <div class="earn-row">
          <span class="when">${e.when}</span>
          <div class="what">
            <div class="tt">${e.cat}</div>
            <div class="ts">${e.channel}${e.procs && e.procs.length ? " · " + e.procs.map((p) => p.n).join(", ") : ""}</div>
            ${e.needsReview ? '<div class="rev-line"><svg data-lucide="shield-alert"></svg>Awaiting senior review</div>' : ""}
          </div>
          <span class="amt tnum">₹${e.amt + (e.procTotal || 0)}</span>
        </div>`).join("")}
      <p class="hint-line" style="margin-top:14px">Full dashboard — charts, payout history, filters — is planned for V2.</p>
    </div>`;
  },
};

D.screens.profile = {
  tabbed: "profile",
  html: () => `
    <div class="body" style="padding-top:14px">
      <div class="card" style="padding:18px;display:flex;align-items:center;gap:14px">
        ${Charak.avatar(D.me.ini, D.me.tone)}
        <div style="flex:1"><h3 style="font-size:17px;font-weight:600">${D.me.name}</h3><p style="font-size:13px;color:var(--color-ink-muted);margin-top:2px">${D.me.spec} · ${D.me.phone}</p></div>
      </div>
      <div class="card verif-card" style="margin-top:10px">
        <span class="v-ic" style="background:${D.verified ? "rgba(31,170,109,0.12);color:var(--color-success)" : "rgba(224,147,11,0.13);color:var(--color-warning)"}"><svg data-lucide="${D.verified ? "shield-check" : "shield"}" style="width:20px;height:20px"></svg></span>
        <div><h3>${D.verified ? "Verified doctor" : "Verification pending"}</h3><p>${D.verified ? "License checked · listed in directory" : "You'll be listed the moment ops approves"}</p></div>
      </div>
      <div style="margin-top:14px">
        <button class="listrow" onclick="Charak.go('channels')"><span class="lr-ic"><svg data-lucide="radio"></svg></span><span class="lr-txt">Channels & modes</span><span class="lr-sub">${D.setup.online ? "Online" : ""}${D.setup.home ? " · Home Visit" : ""}</span><span class="lr-end"><svg data-lucide="chevron-right"></svg></span></button>
        <button class="listrow" onclick="Charak.go('pricing')"><span class="lr-ic"><svg data-lucide="indian-rupee"></svg></span><span class="lr-txt">Pricing & procedures</span><span class="lr-sub tnum">₹${D.setup.onlinePrice}/15m · +₹${D.setup.onlineExtra}/15m</span><span class="lr-end"><svg data-lucide="chevron-right"></svg></span></button>
        <button class="listrow" onclick="Charak.go('homevisit')"><span class="lr-ic"><svg data-lucide="map-pin"></svg></span><span class="lr-txt">Schedule & radius</span><span class="lr-sub">${D.setup.radius} km</span><span class="lr-end"><svg data-lucide="chevron-right"></svg></span></button>
        <button class="listrow" onclick="Charak.tab('schedule')"><span class="lr-ic"><svg data-lucide="calendar-days"></svg></span><span class="lr-txt">Slot blocking</span><span class="lr-end"><svg data-lucide="chevron-right"></svg></span></button>
        <button class="listrow" onclick="Charak.toast('Help centre — coming in full build')"><span class="lr-ic"><svg data-lucide="life-buoy"></svg></span><span class="lr-txt">Help</span><span class="lr-end"><svg data-lucide="chevron-right"></svg></span></button>
        <button class="listrow" onclick="D.reset()"><span class="lr-ic" style="color:var(--color-danger)"><svg data-lucide="log-out"></svg></span><span class="lr-txt" style="color:var(--color-danger)">Logout</span></button>
      </div>
    </div>`,
};

/* ---------- live-sync simulation ---------- */
D.onSim = (m) => {
  if (m.t === "request") {
    const r = { id: "RQ-" + (3899 + D.requests.length), name: "Sunita Verma", ini: "SV", tone: 6, cat: "Nurse", channel: "home", slot: "Today, 8:00 PM", price: 700, dist: "1.8 km", addr: "Sector 15, Nerul", status: "new", text: "Post-surgery dressing change needed for my father. He is 70 and cannot travel.", voice: true, voiceTxt: "The clinic said the dressing should be changed every alternate day.", photos: 1 };
    D.requests.unshift(r);
    const cur = Charak.stack[Charak.stack.length - 1];
    if (cur === "requests") { Charak.go("requests"); Charak.toast("New request from Sunita Verma"); }
    else Charak.toast("New request received");
  }
  if (m.t === "paid") {
    D.paidFlag = true;
    if (Charak.stack[Charak.stack.length - 1] === "active") Charak.go("active");
    Charak.toast("Payment received — price confirmed");
  }
  if (m.t === "seniorApproved") {
    const e = D.earnings.find((x) => x.needsReview);
    if (e) { e.needsReview = false; Charak.toast("Senior doctor approved the procedure bill"); }
  }
  if (m.t === "seniorFlagged") {
    const e = D.earnings.find((x) => x.needsReview);
    if (e) {
      e.procs = e.procs.filter((p) => p.n !== m.n);
      e.procTotal = e.procs.reduce((s, p) => s + p.p, 0);
      e.needsReview = false;
      Charak.toast("Senior doctor flagged " + m.n + " — removed from bill");
    }
  }
};
D.simNewRequest = () => Charak.simPost({ t: "request" });
D.simPaid = () => Charak.simPost({ t: "paid" });
D.simApproved = () => {
  D.verified = true;
  if (Charak.stack[Charak.stack.length - 1] === "pending") Charak.go("channels");
  Charak.toast("Verification approved — you're live");
};
D.reset = () => {
  clearInterval(D.callInt);
  D.verified = false;
  D.requests = D.requests.filter((r) => ["RQ-3897", "RQ-3895", "RQ-3893"].includes(r.id)).map((r) => (r.id === "RQ-3897" ? { ...r, status: "new", procs: [] } : { ...r, status: "pending", procs: [] }));
  D.active = null; D.paidFlag = false; D.actId = null; D.blocked = [{ date: "Today", t: "4:00 PM–5:00 PM", reason: "Personal" }];
  Charak.toast("Demo reset");
  Charak.go("splash");
};

/* ---------- boot ---------- */
Object.assign(Charak.screens, D.screens);
Charak.onSim = D.onSim;
Charak.toggleDock = () => {
  const d = document.getElementById("dock");
  d.classList.toggle("collapsed");
  d.querySelector(".dock-head button").textContent = d.classList.contains("collapsed") ? "+" : "−";
};
document.querySelectorAll(".tab-item").forEach((b) => (b.onclick = () => Charak.tab(b.dataset.tab)));
Charak.go("splash");
