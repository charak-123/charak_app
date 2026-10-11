#!/usr/bin/env python3
"""
Create (or reset) an admin dashboard account.

There is deliberately no HTTP endpoint that does this — anyone who could reach
the API would otherwise be able to mint themselves ops access. This talks to
Supabase directly with the service-role key, the same credential the backend
itself uses, so it must be run somewhere that already has backend/.env (or
the equivalent production secrets) available.

Usage:
    cd backend && ../scripts/create_admin.py ops@charak.care
    cd backend && ../scripts/create_admin.py ops@charak.care --reset-password

You'll be prompted for a password (not echoed). The account starts with TOTP
not yet enrolled — the first time this person logs in at /admin/login with
just the password, the API hands back a QR code to scan in their
authenticator app; scanning it and entering the 6-digit code finishes setup
and logs them in. --reset-password keeps the existing TOTP secret in place
(so their authenticator entry keeps working) and only changes the password.
"""
from __future__ import annotations

import argparse
import getpass
import os
import sys
from pathlib import Path

import bcrypt
import pyotp
from dotenv import load_dotenv

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "backend"))

load_dotenv(Path(__file__).resolve().parent.parent / "backend" / ".env")

from supabase import create_client  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("email")
    parser.add_argument("--reset-password", action="store_true",
                         help="Change the password on an existing account; keep its TOTP secret.")
    args = parser.parse_args()
    email = args.email.strip().lower()

    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        sys.exit("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not set (check backend/.env).")
    supabase = create_client(url, key)

    password = getpass.getpass(f"Password for {email}: ")
    confirm = getpass.getpass("Confirm: ")
    if password != confirm:
        sys.exit("Passwords did not match.")
    if len(password) < 12:
        sys.exit("Use at least 12 characters — this account can verify doctors and issue payouts.")

    password_hash = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()

    existing = (
        supabase.table("admin_users").select("id").eq("email", email).execute().data
    )

    if existing:
        if not args.reset_password:
            sys.exit(f"{email} already has an account. Pass --reset-password to change it.")
        supabase.table("admin_users").update({"password_hash": password_hash}) \
            .eq("id", existing[0]["id"]).execute()
        print(f"Password updated for {email}. Existing TOTP enrollment is unchanged.")
        return

    totp_secret = pyotp.random_base32()
    supabase.table("admin_users").insert({
        "email": email,
        "password_hash": password_hash,
        "totp_secret": totp_secret,
        "totp_enabled": False,
    }).execute()
    print(f"Created {email}.")
    print("Sign in once at the admin dashboard with just the password — it will show a QR")
    print("code to scan in an authenticator app (Google Authenticator, Authy, 1Password, …).")
    print("Entering the 6-digit code it generates finishes setup and logs you in.")


if __name__ == "__main__":
    main()
