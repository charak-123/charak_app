/* ============================================================
   CHARAK shared core — router, sheets, toasts, sim bridge, helpers
   ============================================================ */
(function () {
  const C = {
    app: document.body.dataset.app || "patient",
    state: {},
    screens: {},       // id -> { html: () => string, enter: () => void, leave: () => void }
    stack: [],
    tabRoot: null,     // current tab screen id (no history)
  };

  /* ---------- dom helpers ---------- */
  C.esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  C.ic = (name, cls) => `<svg class="icon ${cls || ""}" data-lucide="${name}"></svg>`;

  /* ---------- router ---------- */
  const stage = () => document.getElementById("stage");

  function mount(id) {
    const def = C.screens[id];
    const el = document.createElement("section");
    el.className = "scr";
    el.id = "scr-" + id;
    el.innerHTML = def.html();
    stage().appendChild(el);
    refreshIcons(el);
    if (def.enter) def.enter(el);
    return el;
  }

  C.go = function (id) {
    const current = stage().querySelector(".scr:not(.leaving)");
    const entering = mount(id);
    entering.classList.add("entering");
    if (current) {
      current.classList.add("leaving");
      const prevDef = C.screens[C.stack[C.stack.length - 1]];
      if (prevDef && prevDef.leave) prevDef.leave();
    }
    C.stack.push(id);
    C.tabRoot = null;
    setTimeout(() => current && current.remove(), 300);
    C.afterRoute();
  };

  C.back = function () {
    const current = stage().querySelector(".scr:not(.leaving)");
    C.stack.pop();
    const prevId = C.stack[C.stack.length - 1];
    if (!prevId || !C.screens[prevId]) { C.go(Object.keys(C.screens)[0]); return; }
    if (current) {
      const curDef = C.screens[curIdOf(current)] || null;
      if (curDef && curDef.leave) curDef.leave();
    }
    const prev = mount(prevId);
    prev.classList.add("back-in");
    if (current) current.classList.add("back-out");
    setTimeout(() => current && current.remove(), 300);
    C.afterRoute();
  };

  C.tab = function (id) {
    const current = stage().querySelector(".scr");
    if (current) {
      const curDef = C.screens[curIdOf(current)] || null;
      if (curDef && curDef.leave) curDef.leave();
      current.remove();
    }
    mount(id).classList.add("tab-in");
    C.tabRoot = id;
    C.stack = [id];
    C.afterRoute();
  };
  function curIdOf(el) { return el.id.replace("scr-", ""); }

  C.afterRoute = function () {
    const s = C.stack[C.stack.length - 1];
    const tabs = document.getElementById("tabbar");
    if (!tabs) return;
    const tabbed = C.screens[s] && C.screens[s].tabbed;
    tabs.style.display = tabbed ? "grid" : "none";
    if (tabbed) {
      tabs.querySelectorAll(".tab-item").forEach((b) => b.classList.toggle("on", b.dataset.tab === tabbed));
    }
  };

  /* ---------- sheets ---------- */
  let backdropEl = null;
  C.openSheet = function (id, html) {
    C.closeSheet();
    backdropEl = document.createElement("div");
    backdropEl.className = "sheet-backdrop";
    backdropEl.onclick = C.closeSheet;
    const sheet = document.createElement("div");
    sheet.className = "sheet";
    sheet.id = "sheet-" + id;
    sheet.innerHTML = `<div class="grab"></div>${html}`;
    stage().appendChild(backdropEl, sheet);
    stage().appendChild(sheet);
    refreshIcons(sheet);
    if (C.sheets && C.sheets[id]) C.sheets[id].open && C.sheets[id].open(sheet);
  };
  C.closeSheet = function () {
    if (backdropEl) { backdropEl.remove(); backdropEl = null; }
    stage().querySelectorAll(".sheet").forEach((s) => s.remove());
  };

  /* ---------- toast ---------- */
  let toastEl = null;
  C.toast = function (msg, ms) {
    if (!toastEl) { toastEl = document.createElement("div"); toastEl.className = "toast"; document.getElementById("stage").appendChild(toastEl); }
    toastEl.textContent = msg;
    requestAnimationFrame(() => toastEl.classList.add("show"));
    clearTimeout(C.toast._t);
    C.toast._t = setTimeout(() => toastEl.classList.remove("show"), ms || 2400);
  };

  /* ---------- sim bridge (cross-app live sync) ---------- */
  const bc = window.BroadcastChannel ? new BroadcastChannel("charak-sim") : { postMessage() {}, onmessage: null };
  const listeners = [];
  bc.onmessage = (e) => { C.onSim && C.onSim(e.data); listeners.forEach((fn) => fn(e.data)); };
  C.simPost = (msg) => {
    if (window.BroadcastChannel) { try { bc.postMessage(msg); } catch (e) {} } // not delivered to self
    listeners.forEach((fn) => fn(msg)); // mirror locally
    C.onSim && C.onSim(msg);
  };
  C.simOn = (fn) => listeners.push(fn);

  /* ---------- checkmark / status helpers ---------- */
  C.checkSvg = (size) => `
    <svg class="check-circle" width="${size}" height="${size}" viewBox="0 0 64 64" fill="none">
      <circle cx="32" cy="32" r="29"/>
      <path d="M20 33.5 L28.5 42 L44.5 24.5"/>
    </svg>`;

  /* ---------- icons ---------- */
  function refreshIcons(root) {
    if (window.lucide) lucide.createIcons({ attrs: { class: ["lucide"] } }, root);
  }
  window.addEventListener("load", () => refreshIcons(document));
  C.refreshIcons = refreshIcons;

  /* ---------- fake avatars ---------- */
  C.avatar = (initials, tone) => `<div class="avatar av-${tone || 1}">${C.esc(initials)}</div>`;

  /* ---------- shared status pill ---------- */
  C.statusPill = (status) => {
    const map = {
      requested: ["warning", "Pending review"],
      accepted: ["primary", "Accepted"],
      paid: ["success", "Paid & confirmed"],
      completed: ["success", "Completed"],
      declined: ["danger", "Declined"],
      cancelled: ["danger", "Cancelled"],
    };
    const [cls, label] = map[status] || ["primary", status];
    return `<span class="status-pill ${cls}">${label}</span>`;
  };

  window.Charak = C;
})();
