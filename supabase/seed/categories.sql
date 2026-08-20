insert into categories (name) values
  ('General Physician'),
  ('Orthopedic'),
  ('Nurse'),
  ('Cardiology'),
  ('Dermatology'),
  ('Gynecology'),
  ('Pediatrics'),
  ('Dentistry'),
  ('Physiotherapy')
on conflict (name) do nothing;
