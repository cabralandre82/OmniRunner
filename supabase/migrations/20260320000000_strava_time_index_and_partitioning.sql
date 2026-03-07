-- Index temporal para strava_activity_history (necessário para queries por período e cleanup)
CREATE INDEX IF NOT EXISTS idx_strava_history_imported_at
  ON strava_activity_history (imported_at DESC);

CREATE INDEX IF NOT EXISTS idx_strava_history_start_date
  ON strava_activity_history (start_date DESC);

-- Particionamento: preparar sessions para particionamento por range temporal
-- Nota: PostgreSQL não suporta ALTER TABLE para converter tabela existente em particionada.
-- A estratégia é criar tabelas particionadas paralelas e migrar dados incrementalmente.

-- Tabela de arquivamento para sessions antigas (> 6 meses)
-- sessions usa start_time_ms (BIGINT epoch ms) e status (SMALLINT)
CREATE TABLE IF NOT EXISTS sessions_archive (
  LIKE sessions INCLUDING ALL
);

COMMENT ON TABLE sessions_archive IS 'Archive for sessions older than 6 months. Data is moved here by the archival cron job.';

-- Tabela de arquivamento para coin_ledger antigo (> 12 meses)
CREATE TABLE IF NOT EXISTS coin_ledger_archive (
  LIKE coin_ledger INCLUDING ALL
);

COMMENT ON TABLE coin_ledger_archive IS 'Archive for coin_ledger entries older than 12 months. Data is moved here by the archival cron job.';

-- Função de arquivamento automático para sessions
-- status SMALLINT: 0=active, 1=paused, 2=completed, 3=cancelled
CREATE OR REPLACE FUNCTION fn_archive_old_sessions()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  moved integer;
  cutoff_ms bigint;
BEGIN
  cutoff_ms := (EXTRACT(EPOCH FROM (NOW() - INTERVAL '6 months')) * 1000)::bigint;

  WITH to_archive AS (
    DELETE FROM sessions
    WHERE start_time_ms < cutoff_ms
      AND status IN (2, 3)
    RETURNING *
  )
  INSERT INTO sessions_archive
  SELECT * FROM to_archive;

  GET DIAGNOSTICS moved = ROW_COUNT;
  RETURN moved;
END;
$$;

-- Função de arquivamento automático para coin_ledger
CREATE OR REPLACE FUNCTION fn_archive_old_ledger()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  moved integer;
BEGIN
  WITH to_archive AS (
    DELETE FROM coin_ledger
    WHERE created_at < NOW() - INTERVAL '12 months'
    RETURNING *
  )
  INSERT INTO coin_ledger_archive
  SELECT * FROM to_archive;

  GET DIAGNOSTICS moved = ROW_COUNT;
  RETURN moved;
END;
$$;

-- Indexes otimizados para as tabelas de arquivo
CREATE INDEX IF NOT EXISTS idx_sessions_archive_user ON sessions_archive (user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_archive_start ON sessions_archive (start_time_ms DESC);
CREATE INDEX IF NOT EXISTS idx_ledger_archive_user ON coin_ledger_archive (user_id);
CREATE INDEX IF NOT EXISTS idx_ledger_archive_created ON coin_ledger_archive (created_at DESC);

-- Cron job para arquivamento (executa todo domingo às 3h)
SELECT cron.schedule(
  'archive-old-sessions',
  '0 3 * * 0',
  $$SELECT fn_archive_old_sessions()$$
);

SELECT cron.schedule(
  'archive-old-ledger',
  '0 4 * * 0',
  $$SELECT fn_archive_old_ledger()$$
);

GRANT EXECUTE ON FUNCTION fn_archive_old_sessions() TO service_role;
GRANT EXECUTE ON FUNCTION fn_archive_old_ledger() TO service_role;
