from fastapi import APIRouter, Response
from ..db import supabase

router = APIRouter()


@router.get("/")
def list_categories(response: Response):
    # Categories change rarely; let clients and any CDN cache them briefly to
    # keep this off the hot path for every app launch.
    response.headers["Cache-Control"] = "public, max-age=300"
    return supabase.table("categories").select("*").order("name").execute().data
