

DROP FUNCTION IF EXISTS bm25importwsmap;
CREATE OR REPLACE FUNCTION bm25importwsmap(tablename_bm25wsmap TEXT, csvpath TEXT) RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  sql_statement TEXT := '';
BEGIN
  sql_statement := 'DROP TABLE IF EXISTS ' || tablename_bm25wsmap || ';';
  EXECUTE sql_statement;
  sql_statement := 'CREATE TABLE ' || tablename_bm25wsmap || ' (word TEXT, vl double precision[]);';
  EXECUTE sql_statement;
  sql_statement := 'COPY ' || tablename_bm25wsmap || ' FROM ' || chr(39) || csvpath || chr(39) || ' DELIMITER ' || chr(39) || ';' || chr(39) || ' CSV HEADER;';
  EXECUTE sql_statement;
END;
$$


DROP FUNCTION IF EXISTS bm25scorerows;
CREATE OR REPLACE FUNCTION bm25scorerows(tablename TEXT, tokenizedquery TEXT) RETURNS SETOF double precision[]
LANGUAGE plpgsql
AS $$
DECLARE
  w TEXT := '';
  sql_statement TEXT := '';
  tokenizedqueryjson JSON := tokenizedquery::JSON;
BEGIN
  FOR w IN SELECT * FROM json_array_elements_text(tokenizedqueryjson)
  LOOP
    sql_statement := 'SELECT vl FROM ' || tablename || ' WHERE word = $1';
    RETURN QUERY EXECUTE sql_statement USING w::TEXT;
  END LOOP;
END;
$$


DROP FUNCTION IF EXISTS bm25scoressum;
CREATE OR REPLACE FUNCTION bm25scoressum(tablename TEXT, tokenizedquery TEXT) RETURNS SETOF double precision[]
LANGUAGE plpgsql
AS $$
BEGIN
  DROP TABLE IF EXISTS xdocs;
  CREATE TABLE xdocs AS SELECT bm25scorerows(tablename, tokenizedquery);
  RETURN QUERY SELECT ARRAY_AGG(sum ORDER BY ord) FROM (SELECT ord, SUM(int) FROM xdocs, unnest(bm25scorerows) WITH ORDINALITY u(int, ord) GROUP BY ord);
END;
$$


DROP FUNCTION IF EXISTS bm25scunnest;
CREATE OR REPLACE FUNCTION bm25scunnest(tablename TEXT, tokenizedquery TEXT) RETURNS TABLE(score double precision)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY SELECT unnest(bm25scoressum(tablename,tokenizedquery));
END;
$$


DROP FUNCTION IF EXISTS bm25isc;
CREATE OR REPLACE FUNCTION bm25isc(tablename TEXT, tokenizedquery TEXT) RETURNS TABLE(id BIGINT, score double precision)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY SELECT row_number() OVER () AS id, bm25scunnest FROM bm25scunnest(tablename,tokenizedquery) ;
END;
$$


DROP FUNCTION IF EXISTS bm25topk;
CREATE OR REPLACE FUNCTION bm25topk(tablename TEXT, tablename_bm25wsmap TEXT, tokenizedquery TEXT, k INT) RETURNS TABLE(id INT, score double precision, doc TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
  sql_statement TEXT := '';
BEGIN
  sql_statement := 'SELECT t1.id, t2.score, t1.full_description AS doc FROM (SELECT id, full_description FROM ' || tablename || ') t1 INNER JOIN ( SELECT id, score FROM bm25isc($1,$2) ) t2 ON ( t1.id = t2.id ) ORDER BY t2.score DESC LIMIT $3;';
  RETURN QUERY EXECUTE sql_statement USING tablename_bm25wsmap, tokenizedquery, k;
END;
$$

