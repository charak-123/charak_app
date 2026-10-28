def normalize_e164(v: str) -> str:
    """Strip spaces and check an E.164 number, e.g. "+919876543210"."""
    v = v.strip().replace(" ", "")
    digits = v.lstrip("+")
    # isdigit() alone accepts Arabic-Indic and other non-ASCII digits, which are
    # different strings for the same subscriber: they get their own OTP budget
    # and their own account row. Only 0-9, and no leading zero after the plus
    # (no E.164 country code starts with 0).
    if (not v.startswith("+") or not digits.isascii() or not digits.isdigit()
            or not (10 <= len(digits) <= 15) or digits.startswith("0")):
        raise ValueError("phone must be E.164, e.g. +919876543210")
    return v
