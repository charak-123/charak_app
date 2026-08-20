import os
from dotenv import load_dotenv

load_dotenv()

SUPABASE_URL             = os.environ["SUPABASE_URL"]
SUPABASE_ANON_KEY        = os.environ["SUPABASE_ANON_KEY"]
SUPABASE_SERVICE_ROLE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
JWT_SECRET               = os.environ["JWT_SECRET"]

MSG91_API_KEY    = os.getenv("MSG91_API_KEY", "")
MSG91_SENDER_ID  = os.getenv("MSG91_SENDER_ID", "CHARAK")
MSG91_TEMPLATE_ID = os.getenv("MSG91_TEMPLATE_ID", "")

RAZORPAY_KEY_ID     = os.getenv("RAZORPAY_KEY_ID", "")
RAZORPAY_KEY_SECRET = os.getenv("RAZORPAY_KEY_SECRET", "")

AGORA_APP_ID          = os.getenv("AGORA_APP_ID", "")
AGORA_APP_CERTIFICATE = os.getenv("AGORA_APP_CERTIFICATE", "")

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
