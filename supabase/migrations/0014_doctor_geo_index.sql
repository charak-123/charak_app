-- Supports the bounding-box pre-filter in GET /doctors/search: a distance-
-- constrained search now filters base_lat/base_lng in SQL instead of pulling
-- every verified doctor into Python.
create index if not exists idx_doctors_base_latlng
  on doctors (base_lat, base_lng)
  where verification_status = 'verified' and suspended = false;
