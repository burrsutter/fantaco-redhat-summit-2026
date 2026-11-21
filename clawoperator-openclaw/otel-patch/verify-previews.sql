-- Read-only. MLflow preview health, by root span.
--
--   oc exec -i -n mlflow <postgres-pod> -- bash -lc \
--     'psql -U "$POSTGRESQL_USER" -d "$POSTGRESQL_DATABASE" -f - -P pager=off' \
--     < verify-previews.sql
--
-- A trace shows "null" in the Traces list when trace_info.request_preview is
-- SQL NULL. Healthy = the only rows left are conversation roots at ~100%.

\echo '===== 1. preview coverage by root span ====='
WITH roots AS (SELECT trace_id, name FROM spans WHERE parent_span_id IS NULL)
SELECT r.name AS root_span,
       count(*) AS traces,
       count(ti.request_preview) AS with_preview,
       round(100.0 * count(ti.request_preview) / count(*), 1) AS pct_ok
FROM trace_info ti
JOIN roots r ON r.trace_id = ti.request_id
GROUP BY 1
ORDER BY 2 DESC;

\echo ''
\echo '===== 2. headline: what fraction of the Traces list reads "null" ====='
SELECT count(*) AS traces,
       count(*) FILTER (WHERE request_preview IS NULL) AS null_rows,
       round(100.0 * count(*) FILTER (WHERE request_preview IS NULL) / count(*), 1) AS pct_null
FROM trace_info;

\echo ''
\echo '===== 3. PROBE: did openclaw.model.usage re-parent? ====='
\echo '-- preview4: as_root = total, as_child = 0 (the bug)'
\echo '-- preview5 "reparent" working: as_child > 0'
\echo '-- if as_child stays 0, the widened lookup did not help -> consider'
\echo '   __MLFLOW_MODEL_USAGE_MODE = "reparent-or-drop"'
SELECT count(*) AS model_usage_spans,
       count(*) FILTER (WHERE parent_span_id IS NULL) AS as_root,
       count(*) FILTER (WHERE parent_span_id IS NOT NULL) AS as_child
FROM spans
WHERE name = 'openclaw.model.usage';

\echo ''
\echo '===== 4. REGRESSION GUARD: token accounting must not disappear ====='
\echo '-- expect one row per key, n tracking the number of model calls'
SELECT 'metadata:' || key AS item, count(*) AS n
FROM trace_request_metadata WHERE key = 'mlflow.trace.tokenUsage' GROUP BY 1
UNION ALL
SELECT 'metric:' || key, count(*)
FROM trace_metrics WHERE key IN ('input_tokens', 'output_tokens', 'total_tokens')
GROUP BY 1
ORDER BY 1;

\echo ''
\echo '===== 5. suppressed span types must be absent for new traces ====='
SELECT name, count(*) AS still_present,
       to_timestamp(max(start_time_unix_nano) / 1e9) AS newest
FROM spans
WHERE name IN ('openclaw.exec', 'openclaw.liveness.warning',
               'openclaw.memory.pressure', 'openclaw.diagnostic.phase')
GROUP BY 1 ORDER BY 2 DESC;
