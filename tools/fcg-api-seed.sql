CREATE TABLE IF NOT EXISTS "WaitlistEntry" (
  id text PRIMARY KEY
);
INSERT INTO "WaitlistEntry" (id) VALUES ('w1'), ('w2'), ('w3')
ON CONFLICT (id) DO NOTHING;
