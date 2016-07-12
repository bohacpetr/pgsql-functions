# EAN13

## Requirements


* [isn](https://www.postgresql.org/docs/current/static/isn.html) extension


## Contents


```sql
get_ean13(IN code BIGINT)
get_ean13(IN code VARCHAR(12))
get_ean13(IN code_prefix VARCHAR(12), IN code BIGINT)
get_ean13(IN code_prefix VARCHAR(12), IN code VARCHAR(12))
```
* param `code` Will be padded to 12 digits by 0
* param `code_prefix` If length of code_prefix and code is greater than 12, code will be truncated!
* returns `ean13`


```sql
get_ean13_check_digit(IN code CHAR(12))
```
Calculates EAN13 checksum digit
* param `code`
* returns `CHAR(1)`


## Exaples

```sql
SELECT get_ean13('020', nextval('ean13_020_seq'));
```

```sql
SELECT
	get_ean13(x),
	get_ean13(x::TEXT),
	get_ean13('020', x),
	get_ean13('020', x::TEXT)
FROM generate_series(0, 999999999, 1234567) x;
```