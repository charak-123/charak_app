"""
The prescription PDF, rendered from the structured record.

Laid out on the sample format in the Telemedicine Practice Guidelines 2020:
the doctor's name, qualification and registration; the patient's name, age and
sex; the date; complaints and provisional diagnosis; each medicine with
strength, dose, frequency, duration and instructions; investigations and
advice; follow-up; and the doctor's signature.

The structured record is the source of truth and this is a rendering of it,
made once at submission, stored privately, and kept with its SHA-256. A
correction is a new version and a new PDF; the old one stays as it was.

Font: DejaVu Sans (app/assets/fonts), which covers Latin text and the rupee
sign. Devanagari isn't covered; prescriptions are written in English in
practice. A character outside the font renders as a blank box rather than
failing.
"""
from __future__ import annotations

import hashlib
import io
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    Image, KeepTogether, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle,
)

IST = timezone(timedelta(hours=5, minutes=30))
_FONTS = Path(__file__).resolve().parent.parent / "assets" / "fonts"
_registered = False

# Ink and muted text, and the hairline, from the CHARAK palette (printed on
# white paper, so the light-scheme values).
INK = colors.HexColor("#0E1726")
MUTED = colors.HexColor("#5A6478")
LINE = colors.HexColor("#D9DCE3")


def _fonts() -> None:
    global _registered
    if _registered:
        return
    pdfmetrics.registerFont(TTFont("CharakSans", str(_FONTS / "DejaVuSans.ttf")))
    pdfmetrics.registerFont(TTFont("CharakSans-Bold", str(_FONTS / "DejaVuSans-Bold.ttf")))
    pdfmetrics.registerFontFamily("CharakSans", normal="CharakSans", bold="CharakSans-Bold")
    _registered = True


def _styles() -> dict[str, ParagraphStyle]:
    base = ParagraphStyle("base", fontName="CharakSans", fontSize=9.5, leading=13, textColor=INK)
    return {
        "base": base,
        "muted": ParagraphStyle("muted", parent=base, textColor=MUTED, fontSize=8.5, leading=11.5),
        "doctor": ParagraphStyle("doctor", parent=base, fontName="CharakSans-Bold", fontSize=15, leading=19),
        "label": ParagraphStyle("label", parent=base, fontName="CharakSans-Bold", fontSize=8,
                                leading=11, textColor=MUTED, spaceBefore=8),
        "rx": ParagraphStyle("rx", parent=base, fontName="CharakSans-Bold", fontSize=16, leading=20,
                             spaceBefore=10),
        "cell": ParagraphStyle("cell", parent=base, fontSize=8.8, leading=11.5),
        "cellbold": ParagraphStyle("cellbold", parent=base, fontName="CharakSans-Bold",
                                   fontSize=8.8, leading=11.5),
    }


def _p(text: Optional[str], style: ParagraphStyle) -> Paragraph:
    """Doctor-typed text, escaped (it is never markup) with line breaks kept."""
    safe = escape(text or "").replace("\n", "<br/>")
    return Paragraph(safe, style)


def _when(ts) -> str:
    if not ts:
        return ""
    dt = ts if isinstance(ts, datetime) else datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
    return dt.astimezone(IST).strftime("%d %b %Y, %I:%M %p IST").replace(" 0", " ")


def render(rx: dict, items: list[dict], doctor: dict, patient: dict, booking: dict,
           follow_up: Optional[dict] = None, signature: Optional[bytes] = None,
           supersedes_version: Optional[int] = None) -> tuple[bytes, str]:
    """
    Render one prescription version. Returns (pdf bytes, sha256 hex).

    ``rx`` is the prescriptions row (with ``submitted_at`` set), ``items`` its
    medicines in order, ``doctor`` and ``patient`` the people, ``booking`` the
    consultation it belongs to.
    """
    _fonts()
    st = _styles()
    out = io.BytesIO()
    doc = SimpleDocTemplate(
        out, pagesize=A4, leftMargin=18 * mm, rightMargin=18 * mm,
        topMargin=16 * mm, bottomMargin=16 * mm,
        title=f"Prescription — {patient.get('name') or 'Patient'}",
        author=doctor.get("name") or "CHARAK",
        creator="CHARAK",
    )
    flow: list = []
    # The frame pads its content 6 pt each side; tables sized to doc.width would
    # stick out past the paragraphs by that much.
    width = doc.width - 12

    def cols(*fractions: float) -> list[float]:
        return [width * f for f in fractions]

    # ── Doctor ──────────────────────────────────────────────────────────────
    details = doctor.get("application_details") or {}
    qualification = details.get("qualification") or details.get("degree")
    council = details.get("council") or details.get("registrationCouncil")
    specialty = (doctor.get("categories") or {}).get("name") or details.get("specialty")
    flow.append(_p(_doctor_name(doctor.get("name")), st["doctor"]))
    line = " · ".join(x for x in (qualification, specialty) if x)
    if line:
        flow.append(_p(line, st["base"]))
    reg = doctor.get("license_number")
    if reg:
        flow.append(_p(f"Registration No. {reg}" + (f" ({council})" if council else ""), st["base"]))
    flow.append(Spacer(1, 6))
    flow.append(_rule(width))

    # ── Patient and consultation ────────────────────────────────────────────
    age_sex = ", ".join(x for x in (
        f"{rx['patient_age']} y" if rx.get("patient_age") is not None else None,
        (rx.get("patient_sex") or "").capitalize() or None,
    ) if x)
    mode = "Home visit" if booking.get("channel") == "home_visit" else "Online consultation (video)"
    meta = Table([
        [_p("Patient", st["muted"]), _p("Date", st["muted"]), _p("Consultation", st["muted"])],
        [_p(f"{patient.get('name') or 'Patient'}" + (f" · {age_sex}" if age_sex else ""), st["base"]),
         _p(_when(rx.get("submitted_at")), st["base"]),
         _p(mode, st["base"])],
    ], colWidths=cols(0.40, 0.29, 0.31))
    meta.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"),
                              ("LEFTPADDING", (0, 0), (-1, -1), 0),
                              ("BOTTOMPADDING", (0, 0), (-1, -1), 1)]))
    flow.append(Spacer(1, 4))
    flow.append(meta)

    if rx.get("complaints"):
        flow += [_p("CHIEF COMPLAINTS", st["label"]), _p(rx["complaints"], st["base"])]
    if rx.get("diagnosis"):
        flow += [_p("PROVISIONAL DIAGNOSIS", st["label"]), _p(rx["diagnosis"], st["base"])]

    # ── Medicines ───────────────────────────────────────────────────────────
    if rx.get("kind") == "notes":
        flow.append(_p("CONSULTATION NOTES", st["label"]))
        flow.append(_p("No medicines prescribed.", st["muted"]))
    elif items:
        flow.append(_p("℞", st["rx"]))
        rows = [[_p(h, st["muted"]) for h in ("#", "Medicine", "Dose", "Frequency", "Duration", "Instructions")]]
        for i, item in enumerate(items, start=1):
            name = " ".join(x for x in (item.get("medicine"), item.get("strength")) if x)
            form_route = " · ".join(x for x in (item.get("form"), item.get("route")) if x)
            rows.append([
                _p(str(i), st["cell"]),
                [_p(name, st["cellbold"])] + ([_p(form_route, st["muted"])] if form_route else []),
                _p(item.get("dose"), st["cell"]),
                _p(item.get("frequency"), st["cell"]),
                _p(item.get("duration"), st["cell"]),
                _p(item.get("instructions"), st["cell"]),
            ])
        table = Table(rows, colWidths=cols(0.04, 0.30, 0.13, 0.15, 0.12, 0.26), repeatRows=1)
        table.setStyle(TableStyle([
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("LINEBELOW", (0, 0), (-1, 0), 0.6, LINE),
            ("LINEBELOW", (0, 1), (-1, -1), 0.3, LINE),
            ("LEFTPADDING", (0, 0), (-1, -1), 0),
            ("RIGHTPADDING", (0, 0), (-1, -1), 6),
            ("TOPPADDING", (0, 0), (-1, -1), 4),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ]))
        flow.append(table)
    if rx.get("upload_path"):
        flow += [_p("HANDWRITTEN PRESCRIPTION", st["label"]),
                 _p("The doctor's handwritten prescription is attached in the CHARAK app.", st["base"])]

    if rx.get("investigations"):
        flow += [_p("INVESTIGATIONS", st["label"]), _p(rx["investigations"], st["base"])]
    if rx.get("advice"):
        flow += [_p("ADVICE", st["label"]), _p(rx["advice"], st["base"])]
    if follow_up:
        channel = {"online_consult": "online consultation", "home_visit": "home visit",
                   "either": "online consultation or home visit"}.get(follow_up.get("channel"), "")
        text = f"Around {_date(follow_up.get('recommended_date'))}" + (f", by {channel}" if channel else "")
        if follow_up.get("note"):
            text += f". {follow_up['note']}"
        flow += [_p("FOLLOW-UP", st["label"]), _p(text, st["base"])]

    # ── Signature ───────────────────────────────────────────────────────────
    block: list = [Spacer(1, 14)]
    if signature:
        try:
            img = Image(io.BytesIO(signature))
            ratio = img.imageHeight / float(img.imageWidth or 1)
            img.drawWidth, img.drawHeight = 38 * mm, min(38 * mm * ratio, 16 * mm)
            img.hAlign = "RIGHT"
            block.append(img)
        except Exception:                          # noqa: BLE001 — a bad image never blocks the PDF
            pass
    block.append(_p(_doctor_name(doctor.get("name")), ParagraphStyle(
        "sign", parent=st["base"], fontName="CharakSans-Bold", alignment=2)))
    block.append(_p(f"Issued electronically through CHARAK on {_when(rx.get('submitted_at'))}",
                    ParagraphStyle("signnote", parent=st["muted"], alignment=2)))
    flow.append(KeepTogether(block))

    # ── Footer facts ────────────────────────────────────────────────────────
    flow.append(Spacer(1, 12))
    flow.append(_rule(width))
    notes = [f"Prescription {rx['id']} · version {rx.get('version', 1)}"]
    if supersedes_version:
        notes.append(f"This corrected prescription replaces version {supersedes_version}.")
    if booking.get("channel") == "online_consult":
        notes.append("Issued after a video consultation under the Telemedicine Practice Guidelines 2020.")
    notes.append("Not valid for medicines in the prohibited list of the Telemedicine Practice Guidelines.")
    for n in notes:
        flow.append(_p(n, st["muted"]))

    doc.build(flow)
    pdf = out.getvalue()
    return pdf, hashlib.sha256(pdf).hexdigest()


def _rule(width: float) -> Table:
    t = Table([[""]], colWidths=[width], rowHeights=[1])
    t.setStyle(TableStyle([("LINEBELOW", (0, 0), (-1, -1), 0.6, LINE)]))
    return t


def _doctor_name(name: Optional[str]) -> str:
    bare = (name or "").strip()
    for prefix in ("Dr. ", "Dr ", "dr. ", "dr "):
        if bare.startswith(prefix):
            bare = bare[len(prefix):]
    return f"Dr. {bare}" if bare else "Doctor"


def _date(value) -> str:
    if not value:
        return ""
    try:
        return datetime.fromisoformat(str(value)).strftime("%d %b %Y").lstrip("0")
    except ValueError:
        return str(value)
