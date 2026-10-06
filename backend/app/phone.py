def normalize_e164(v: str) -> str:
    """Strip spaces and check an E.164 number, e.g. "+919876543210"."""
    v = v.strip().replace(" ", "")
    digits = v.lstrip("+")
    if not v.startswith("+") or not digits.isdigit() or not (10 <= len(digits) <= 15):
        raise ValueError("phone must be E.164, e.g. +919876543210")
    return v
