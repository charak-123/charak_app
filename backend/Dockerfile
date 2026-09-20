FROM python:3.13-slim

# Fail fast and log straight through — buffered stdout hides startup errors in
# Fly's log stream.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/

# Run unprivileged. Nothing in the image needs to write to disk, so the
# application user owns nothing it could be tricked into modifying.
RUN useradd --create-home --shell /usr/sbin/nologin charak
USER charak

EXPOSE 8000

# Two workers is now safe: OTP state moved from a per-process dict into the
# otp_codes table in migration 0007, so a code issued by one worker verifies on
# the other.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
