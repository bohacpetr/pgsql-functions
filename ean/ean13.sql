/**
 * @author Petr Boháč
 * @license 2-clause BSD license
 */

CREATE FUNCTION get_ean13_check_digit(IN code CHAR(12))
	RETURNS CHAR AS
$$
	SELECT ((10 - (chk_sum % 10)) % 10)::CHAR
	FROM (
		SELECT sum(digit * weight) AS chk_sum
		FROM (
			SELECT digit,
				CASE
					WHEN (row_number() OVER ()) % 2 = 0 THEN 3
					ELSE 1
				END AS weight
			FROM (
				SELECT unnest((regexp_split_to_array(code, '')))::INT AS digit
			) t1
		) t2
	) t3;
$$
	LANGUAGE sql
	IMMUTABLE
	LEAKPROOF
	RETURNS NULL ON NULL INPUT;


CREATE FUNCTION get_ean13 (IN code BIGINT)
	RETURNS ean13 AS
$$
	SELECT ean13(padded_code || get_ean13_check_digit(padded_code))
	FROM (
		SELECT lpad(code::TEXT, 12, '0') AS padded_code
	) t1;
$$
	LANGUAGE sql
	IMMUTABLE
	LEAKPROOF
	RETURNS NULL ON NULL INPUT;


CREATE FUNCTION get_ean13 (IN code VARCHAR(12))
	RETURNS ean13 AS
$$
	SELECT ean13(padded_code || get_ean13_check_digit(padded_code))
	FROM (
		SELECT lpad(btrim(code, ' '), 12, '0') AS padded_code
	) t1;
$$
	LANGUAGE sql
	IMMUTABLE
	LEAKPROOF
	RETURNS NULL ON NULL INPUT;


CREATE FUNCTION get_ean13 (IN code_prefix VARCHAR(12), IN code BIGINT)
	RETURNS ean13 AS
$$
	SELECT ean13(padded_code || get_ean13_check_digit(padded_code))
	FROM (
		SELECT code_prefix || lpad(code::TEXT, 12 - length(code_prefix), '0') AS padded_code
	) t1;
$$
	LANGUAGE sql
	IMMUTABLE
	LEAKPROOF
	RETURNS NULL ON NULL INPUT;


CREATE FUNCTION get_ean13 (IN code_prefix VARCHAR(12), IN code VARCHAR(12))
	RETURNS ean13 AS
$$
	SELECT ean13(padded_code || get_ean13_check_digit(padded_code))
	FROM (
		SELECT code_prefix || lpad(btrim(code, ' '), 12 - length(code_prefix), '0') AS padded_code
	) t1;
$$
	LANGUAGE sql
	IMMUTABLE
	LEAKPROOF
	RETURNS NULL ON NULL INPUT;