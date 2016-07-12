/**
 * @author Petr Boháč
 * @license 2-clause BSD license
 */

CREATE SCHEMA audit;


CREATE TABLE audit.audit_log
(
	id BIGSERIAL NOT NULL,
	"table" REGCLASS NOT NULL,
	pk JSONB NOT NULL,
	diff JSONB NOT NULL,
	action CHARACTER(1) NOT NULL,
	pg_user NAME NOT NULL,
	ip INET NOT NULL,
	xid BIGINT NOT NULL,
	created TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
	CONSTRAINT audit_pk PRIMARY KEY (id)
);


CREATE FUNCTION audit.create_audit_table(table_name REGCLASS)
	RETURNS REGCLASS AS
$$
DECLARE
	log_table TEXT;
BEGIN
	log_table = replace(replace(table_name::TEXT, '.', '__'), '"', '') || '_log';
	EXECUTE 'CREATE TABLE IF NOT EXISTS audit.' || log_table || ' (
		CONSTRAINT "' || replace(log_table, '"', '') || '_pk" PRIMARY KEY (id) WITH (FILLFACTOR=100)
		) INHERITS (audit.audit_log)';

	RETURN ('audit.' || log_table)::REGCLASS;
END;
$$
	LANGUAGE plpgsql
	VOLATILE;



CREATE FUNCTION audit.create_audit_trigger(table_name REGCLASS, target_table REGCLASS, exclude_columns VARCHAR[])
	RETURNS VOID AS
$$
DECLARE
	trigger_args TEXT;
BEGIN
	trigger_args = '''' || target_table::TEXT || '''';
	IF exclude_columns IS NOT NULL THEN
		trigger_args = trigger_args || ', ' || quote_literal(exclude_columns);
	END IF;
	EXECUTE 'DROP TRIGGER IF EXISTS audit ON ' || table_name::TEXT;
	EXECUTE 'CREATE TRIGGER audit '
		|| 'AFTER INSERT OR UPDATE OR DELETE ON '
		|| table_name::TEXT
		|| ' FOR EACH ROW EXECUTE PROCEDURE audit.insert_audit('
		|| trigger_args || ');';
END;
$$
	LANGUAGE plpgsql
	VOLATILE;


CREATE FUNCTION audit.insert_audit()
  RETURNS TRIGGER AS
$$
DECLARE
	diff HSTORE;
	audit_row audit.audit_log;
	pk TEXT[];
	exclude_columns TEXT[];
	audit_table REGCLASS;
	new_hs HSTORE;
	old_hs HSTORE;
	new_json JSONB;
	old_json JSONB;
BEGIN
	audit_row.id := nextval('audit.audit_log_id_seq');
	audit_row.table := TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME;
	audit_row.created := now();
	audit_row.pg_user := SESSION_USER::TEXT;
	audit_row.xid := txid_current();

	SELECT INTO pk array_agg(kcu.column_name::TEXT)
	FROM information_schema.table_constraints tc,
		information_schema.key_column_usage kcu
	WHERE kcu.table_catalog = tc.table_catalog AND tc.table_catalog = current_database()
		AND kcu.table_schema = tc.table_schema AND tc.table_schema = TG_TABLE_SCHEMA
		AND kcu.table_name = tc.table_name and tc.table_name = TG_TABLE_NAME
		AND kcu.constraint_name = tc.constraint_name
		AND tc.constraint_type = 'PRIMARY KEY';

	exclude_columns := ARRAY[]::TEXT[];
	audit_table := 'audit.audit_log'::REGCLASS;

	BEGIN
		IF TG_ARGV[0] IS NOT NULL THEN
			audit_table := TG_ARGV[0]::REGCLASS;
		END IF;

		IF TG_ARGV[1] IS NOT NULL THEN
			exclude_columns := TG_ARGV[1]::TEXT[];
		END IF;
	EXCEPTION WHEN undefined_table THEN
		IF TG_ARGV[0] IS NOT NULL THEN
			exclude_columns := TG_ARGV[0]::TEXT[];
		END IF;
	END;


	IF TG_OP = 'INSERT' THEN
		new_json = to_jsonb(NEW);
		SELECT json_object_agg(key, value) INTO audit_row.pk FROM jsonb_each(new_json) WHERE key = ANY (pk);
		audit_row.diff := new_json;
		audit_row.action := 'I';
	ELSIF TG_OP = 'UPDATE' THEN
		new_hs := hstore(NEW);
		old_hs := hstore(OLD);
		SELECT json_object_agg(key, value) INTO audit_row.pk FROM jsonb_each(to_jsonb(NEW)) WHERE key = ANY (pk);
		audit_row.diff := to_jsonb(old_hs - new_hs);
		audit_row.action := 'U';
	ELSIF TG_OP = 'DELETE' THEN
		old_json := to_jsonb(OLD);
		SELECT json_object_agg(key, value) INTO audit_row.pk FROM jsonb_each(old_json) WHERE key = ANY (pk);
		audit_row.diff := old_json;
		audit_row.action = 'D';
	ELSIF TG_OP = 'TRUNCATE' THEN
		old_json := to_jsonb(OLD);
		SELECT json_object_agg(key, value) INTO audit_row.pk FROM jsonb_each(old_json) WHERE key = ANY (pk);
		audit_row.diff := old_json;
		audit_row.action := 'T';
	END IF;

	audit_row.diff := audit_row.diff #- exclude_columns;
	BEGIN
			audit_row.ip := current_setting('session.ip')::INET;
	EXCEPTION WHEN SQLSTATE '42704' OR SQLSTATE '22P02' THEN
		audit_row.ip := inet_client_addr();

		IF audit_row.ip IS NULL THEN
			audit_row.ip := '0.0.0.0'::INET;
		END IF;
	END;

	IF audit_row.diff != '{}'::JSONB THEN
		EXECUTE 'INSERT INTO ' || audit_table || ' SELECT ($1).*'
		USING audit_row;
	END IF;

	RETURN NULL;
END;
$$
	LANGUAGE plpgsql
	VOLATILE;


CREATE FUNCTION audit.start_audit(table_name REGCLASS, exclude_columns VARCHAR[] DEFAULT '{}')
  RETURNS VOID AS
$$
DECLARE
	trigger_args TEXT;
	log_table REGCLASS;
BEGIN
	log_table = audit.create_audit_table(table_name);
	PERFORM audit.create_audit_trigger(table_name, log_table, exclude_columns);
END;
$$
  LANGUAGE plpgsql
	VOLATILE;


CREATE FUNCTION audit.stop_audit(table_name REGCLASS)
  RETURNS VOID AS
$BODY$
BEGIN
	EXECUTE 'DROP TRIGGER IF EXISTS audit ON ' || table_name::TEXT;
END;
$BODY$
  LANGUAGE plpgsql
	VOLATILE;


CREATE FUNCTION audit.print_audit(tb_name REGCLASS, primary_key JSONB)
RETURNS TABLE (id BIGINT, table_name REGCLASS, current_value JSONB,
	new_diff JSONB, old_diff JSONB, action CHAR, pg_user NAME, ip INET, xid XID,
	created TIMESTAMP) AS
$$
DECLARE
	where_sql TEXT;
	r audit.audit_log;
	p RECORD;
	json_row JSONB;
BEGIN

	SELECT string_agg(cond, ' AND ') INTO where_sql
	FROM (
			SELECT quote_ident(k) || ' = ' || quote_literal(v) cond
			FROM (
					SELECT array_agg(key) AS keys, array_agg(value) AS values
					FROM jsonb_each_text(primary_key)
				) t2
				JOIN unnest(t2.keys) WITH ORDINALITY k ON (true)
				JOIN unnest(t2.values) WITH ORDINALITY v ON (k.ordinality = v.ordinality)
		) t1;

	IF where_sql IS NULL THEN
		RAISE EXCEPTION 'Empty primary key';
	END IF;

	EXECUTE 'SELECT to_json(t) FROM ' || tb_name || ' t WHERE ' || where_sql
	INTO json_row;

	FOR r IN
		EXECUTE format('SELECT *
			FROM audit.%s_log
			WHERE pk @> $1
			ORDER BY id DESC', REPLACE(tb_name::TEXT, '.', '__'))
		USING primary_key
	LOOP
		current_value := json_row;

		SELECT jsonb_object_agg(d.key, d.value) INTO new_diff
		FROM jsonb_each_text(json_row) d
			JOIN (SELECT jsonb_object_keys(r.diff) AS key) k ON (d.key = k.key);

		json_row := COALESCE(json_row, r.diff) || r.diff;
		id := r.id;
		table_name := r.table;
		action := r.action;
		pg_user := r.pg_user;
		ip := r.ip;
		xid := r.xid;
		created := r.created;

		IF r.action != 'I' THEN
			old_diff := r.diff;
		ELSE
			old_diff := NULL;
		END IF;

		RETURN NEXT;
	END LOOP;

	RETURN;
END
$$
LANGUAGE plpgsql;
