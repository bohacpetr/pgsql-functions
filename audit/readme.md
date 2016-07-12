# Audit

Tracks changes on selected tables (INSERT, UPDATE, DELETE) and prints history of changes

## Contents

```sql
audit.print_audit(tb_name REGCLASS, primary_key JSONB)
```

Prints history of audited table for single primary key

* param tb_name audited table name
* param primary_key primary key(s) encoded in JSON. Only single row PK can be passed
* returns table (id BIGINT, table_name REGCLASS, current_value JSONB, new_diff JSONB, old_diff JSONB, action CHAR, pg_user NAME, ip INET, xid XID, created TIMESTAMP)


```sql
audit.start_audit(table_name REGCLASS, exclude_columns VARCHAR[] DEFAULT '{}')
```

Creates audit table and trigger

* param table_table Target table
* param exclude_columns Optional array of exluded columns
* returns void


```sql
audit.stop_audit(table_name REGCLASS)
```

Drops audit trigger, but preservs audit history

* param table_name Target table
* returns void


## Exaples

```sql
SELECT audit.start_audit('public.users', '{created,updated}');

/*
 * ...
 */

SELECT set_config('session.ip', '10.0.0.0'); -- optional
INSERT INTO users (username, first_name, last_name, created, updated)
VALUES ('example@example.com', 'John', 'Doe', now(), now())
RETURNING id;

/*
 *  id
 * ----
 *  1
 * (1 row)
 */

/*
 * ...
 */

SELECT * FROM audit.print_audit('users', '{"id": 1}')
```
