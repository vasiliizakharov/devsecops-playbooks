-- zabbix-httptest-auth-gate.sql
--
-- When a Web Scenario monitors a site that is later locked behind nginx
-- Basic-Auth or an IP allowlist, the default Zabbix HTTP test reports DOWN
-- because the response code is 401/403 instead of 200.
--
-- Two fixes — pick the one that matches your situation.
--
-- Fix A: pass Basic-Auth credentials to the test (recommended for /wp-admin).
-- Fix B: accept 401/403 as valid response codes (recommended for hosts where
--        the public path is intentionally protected and you just want to know
--        the daemon is alive).
--
-- Run from the Zabbix DB host:
--   psql -U zabbix -d zabbix -f zabbix-httptest-auth-gate.sql
--
-- Replace placeholders before running.

\set HOSTNAME              '<HOSTNAME>'
\set HTTPTEST_NAME          '<HTTPTEST_NAME>'
\set BASIC_AUTH_USER        '<USERNAME>'
\set BASIC_AUTH_PASS        '<PASSWORD>'
\set ACCEPTED_CODES_PIPED   '200|301|302|401|403'

-- Lookup the httptest_id
\set httptest_id (
  SELECT ht.httptestid
  FROM httptest ht
  JOIN hosts h ON h.hostid = ht.hostid
  WHERE h.host = :'HOSTNAME'
    AND ht.name = :'HTTPTEST_NAME'
  LIMIT 1
)

-- =================== Fix A: Basic-Auth credentials ============================

UPDATE httptest
SET authentication = 1,                         -- 1 = HTTP Basic
    http_user = :'BASIC_AUTH_USER',
    http_password = :'BASIC_AUTH_PASS'
WHERE httptestid = :httptest_id;

-- =================== Fix B: accept 401/403 as valid ===========================
-- Each "step" in the scenario has a status_codes field.
-- Set it to a pipe-list of acceptable codes.

UPDATE httpstep
SET status_codes = :'ACCEPTED_CODES_PIPED'
WHERE httptestid = :httptest_id;

-- =================== Reload server to pick up changes =========================
-- After running, restart zabbix-server or wait for cache refresh
-- (default CacheUpdateFrequency=60s).
