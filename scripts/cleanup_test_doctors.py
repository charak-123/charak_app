#!/usr/bin/env python3
"""
One-time cleanup: removes the 16 seed/test doctor rows and their 2 attached
test bookings from production. See the session where this was agreed —
confirmed clean (no real payments, ratings, complaints or payouts attached).
"""
import os
from dotenv import load_dotenv
from pathlib import Path

load_dotenv(Path(__file__).resolve().parent.parent / "backend" / ".env")

from supabase import create_client

sb = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_ROLE_KEY"])

bids = ["d74ee38c-6efb-43c1-8748-820c79e0fdbe", "c1c9a6c2-1a84-450e-b20d-0b3f5b60085f"]
r1 = sb.table("bookings").delete().in_("id", bids).execute()
print("bookings deleted:", len(r1.data))

doctors = sb.table("doctors").select("id").execute().data
ids = [d["id"] for d in doctors]
r2 = sb.table("doctors").delete().in_("id", ids).execute()
print("doctors deleted:", len(r2.data))
