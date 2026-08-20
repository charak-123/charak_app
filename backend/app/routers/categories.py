from fastapi import APIRouter
from ..db import supabase

router = APIRouter()


@router.get("/")
def list_categories():
    return supabase.table("categories").select("*").order("name").execute().data
