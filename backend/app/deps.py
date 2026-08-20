from fastapi import Depends, Header, HTTPException
from jose import jwt, JWTError
from .config import JWT_SECRET


def get_current_user(authorization: str = Header(...)) -> dict:
    try:
        token = authorization.removeprefix("Bearer ")
        payload = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
        return payload  # {"sub": id, "role": "patient"|"doctor"|"ops"}
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid or expired token")


def require_doctor(user: dict = Depends(get_current_user)) -> dict:
    if user.get("role") != "doctor":
        raise HTTPException(status_code=403, detail="Doctor access required")
    return user


def require_patient(user: dict = Depends(get_current_user)) -> dict:
    if user.get("role") != "patient":
        raise HTTPException(status_code=403, detail="Patient access required")
    return user


def require_ops(user: dict = Depends(get_current_user)) -> dict:
    if user.get("role") != "ops":
        raise HTTPException(status_code=403, detail="Ops access required")
    return user
