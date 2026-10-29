#!/usr/bin/env python3
"""
Create (or reset) an admin dashboard account.

There is deliberately no HTTP endpoint that does this — anyone who could reach
the API would otherwise be able to mint themselves ops access. This talks to
Supabase directly with the service-role key, the same credential the backend
itself uses, so it must be run somewhere that already has backend/.env (or
the equivalent production secrets) available.

Usage:
    cd backend && ../scripts/create_admin.py ops@charak.care --role ops_lead
    cd backend && ../scripts/create_admin.py ops@charak.care --reset-password

--role is one of support (the default: bookings, cases, queues), ops_lead
(also decides incidents, reviews, refunds, verification), finance (refunds and
payouts) or admin (everything, including approving policies and managing
admins). See backend/app/services/admin_roles.py. An admin can change a role
later from the console.

You'll be prompted for a password (not echoed). Creating the account prints the
two-factor secret ONCE, here in your terminal, as a setup link and a key: add it
to the new admin's authenticator app (Google Authenticator, Authy, 1Password)
yourself, or give it to them over a channel you trust. The login page never shows
it, so knowing the password alone is not enough to sign in. The first 6-digit
code they enter switches two-factor on.

--reset-password keeps the existing secret (their authenticator entry keeps
working) and only changes the password. --reset-totp issues a NEW secret for an
admin who lost their authenticator, and prints it once the same way.
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
    parser.add_argument("--reset-totp", action="store_true",
                         help="Issue a new two-factor secret for an existing account (lost phone).")
    parser.add_argument("--role", choices=("support", "ops_lead", "finance", "admin"), default="support",
                        help="What the account may do (default: support, the least).")
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

    if existing and args.reset_totp:
        secret = pyotp.random_base32()
        supabase.table("admin_users").update({"totp_secret": secret, "totp_enabled": False}) \
            .eq("id", existing[0]["id"]).execute()
        print(f"New two-factor secret issued for {email}.")
        _show_secret(email, secret)
        return

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
        "role": args.role,
    }).execute()
    print(f"Created {email} as {args.role}.")
    _show_secret(email, totp_secret)


def _show_secret(email: str, secret: str) -> None:
    """Shown once, here. The login page never reveals it."""
    uri = pyotp.TOTP(secret).provisioning_uri(name=email, issuer_name="Charak Admin")
    print()
    print("Add this to the admin's authenticator app NOW. It is not shown again:")
    print(f"  key:   {secret}")
    print(f"  link:  {uri}")
    print("They then sign in with the password plus the 6-digit code it shows.")


if __name__ == "__main__":
    main()
