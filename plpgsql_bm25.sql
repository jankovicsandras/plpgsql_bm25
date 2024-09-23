
/* 

  plpgsql_bm25.sql
  BM25 Okapi search implemented in PL/pgSQL
  version 2024-09-22 by András Jankovics  https://github.com/jankovicsandras  andras@jankovics.net

  Example usage:
  SELECT bm25createindex( tablename, columnname );  /* tablename and columnname are TEXT types */
  SELECT * FROM bm25topk( tablename, columnname, question, k ); /* question is TEXT, k is INTEGER */

  Please note: bm25createindex will (re)create new tables <tablename>_bm25i_docs and <tablename>_bm25i_words, 
  document results will come from <tablename>_bm25i_docs, not the original <tablename>. The algorithm can't
  track changes, so if documents change in the original <tablename>, then bm25createindex() must be called again.

  License: The Unlicense / PUBLIC DOMAIN

*/



/* bm25simpletokenize(): split text to words on whitespace, lowercase, remove some punctiation, similar to mytokenize() */
DROP FUNCTION IF EXISTS bm25simpletokenize;
CREATE OR REPLACE FUNCTION bm25simpletokenize(txt TEXT) RETURNS TEXT[]
LANGUAGE plpgsql
AS $$
DECLARE
  w TEXT;
  w2 TEXT;
  words TEXT[];
BEGIN
  FOREACH w IN ARRAY regexp_split_to_array(LOWER(txt), '\s+') LOOP
    w2 = RTRIM( LTRIM( w, '([{<"''' ), '.?!,:;)]}>"''' );
    IF LENGTH(w2) > 0 THEN
      words = array_append( words, w2 );
    END IF;
  END LOOP;
  RETURN words;
END;
$$;


/* count_words_in_array() creates doc->words counts */
DROP FUNCTION IF EXISTS count_words_in_array;
CREATE OR REPLACE FUNCTION count_words_in_array(input_array text[]) RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    word_count jsonb := '{}';
    current_word text;
BEGIN
    FOREACH current_word IN ARRAY input_array LOOP
        IF word_count->>current_word IS NULL THEN
            word_count := jsonb_set( word_count, ARRAY[current_word], '1'::jsonb, true );
        ELSE
            word_count := jsonb_set( word_count, ARRAY[current_word], ((word_count->>current_word)::int + 1)::text::jsonb );
        END IF;
    END LOOP;
    RETURN word_count;
END;
$$;


/* get_word_docs_count() */
DROP FUNCTION IF EXISTS get_word_docs_count;
CREATE OR REPLACE FUNCTION get_word_docs_count( wordstname TEXT, wf JSONB ) RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  mkey TEXT;
BEGIN
  FOR mkey IN SELECT key FROM jsonb_each_text(wf) LOOP
    EXECUTE FORMAT( 'INSERT INTO %s(word, word_docs_count) VALUES (%s, COALESCE((SELECT word_docs_count FROM %s WHERE word = %s) ,1::INTEGER ) ) ON CONFLICT (word) DO UPDATE SET word_docs_count = (%s.word_docs_count + 1)::INTEGER;', wordstname, quote_literal(mkey), wordstname, quote_literal(mkey), wordstname );
  END LOOP;
END;
$$;


/* get_wsmapobj() */
DROP FUNCTION IF EXISTS get_wsmapobj;
CREATE OR REPLACE FUNCTION get_wsmapobj( docstname TEXT, word TEXT, thisidf DOUBLE PRECISION, thisk1 DOUBLE PRECISION ) RETURNS DOUBLE PRECISION[]
LANGUAGE plpgsql
AS $$
DECLARE
  res DOUBLE PRECISION[];
BEGIN
  /* self.wsmap[word][i] = thiswordidf * ( word_freqs[i] * (self.k1 + 1) / ( word_freqs[i] + self.hds[i] ) ) # += replaced with = */
  EXECUTE FORMAT( 'SELECT ARRAY_AGG( %s * COALESCE(word_freqs->>%s,%s)::INTEGER * %s / ( COALESCE(word_freqs->>%s,%s)::INTEGER + hds ) ORDER BY id) FROM %s;', thisidf, quote_literal(word), quote_literal(0), (thisk1+1), quote_literal(word), quote_literal(0), docstname ) INTO res;
  RETURN res;
END;
$$;


/* bm25createindex() */
DROP FUNCTION IF EXISTS bm25createindex;
CREATE OR REPLACE FUNCTION bm25createindex(tablename TEXT, columnname TEXT) RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  docstname TEXT := tablename || '_' ||  columnname || '_bm25i_docs';
  wordstname TEXT := tablename || '_' ||  columnname || '_bm25i_words';
  param_k1 DOUBLE PRECISION := 1.5;
  param_b DOUBLE PRECISION := 0.75;
  param_epsilon DOUBLE PRECISION := 0.25;
  corpus_len INTEGER;
  vocab_len INTEGER;
  total_word_count INTEGER;
  avg_doc_len DOUBLE PRECISION;
  idf_sum DOUBLE PRECISION;
  average_idf DOUBLE PRECISION;
  param_eps DOUBLE PRECISION;
BEGIN

  /* create bm25_params_debug table, this is only required for debugging. */
  /*
  DROP TABLE IF EXISTS bm25_params_debug;
  CREATE TABLE bm25_params_debug ( paramname TEXT PRIMARY KEY, value DOUBLE PRECISION );
  INSERT INTO bm25_params_debug(paramname,value) VALUES('param_k1',param_k1);
  INSERT INTO bm25_params_debug(paramname,value) VALUES('param_b',param_b);
  INSERT INTO bm25_params_debug(paramname,value) VALUES('param_epsilon',param_epsilon);
  */

  /* create docs table */
  EXECUTE FORMAT( 'DROP TABLE IF EXISTS %s;', docstname );
  EXECUTE FORMAT( 'CREATE TABLE %s (id SERIAL PRIMARY KEY, doc TEXT, tokenized_doc TEXT[]);', docstname );
  EXECUTE FORMAT( 'INSERT INTO %s (doc, tokenized_doc) SELECT %s AS doc, bm25simpletokenize(%s) AS tokenized_doc FROM %s ;', docstname, columnname, columnname, tablename );

  /* add doc_lens */
  EXECUTE FORMAT( 'ALTER TABLE %s ADD COLUMN doc_lens INTEGER;', docstname );
  EXECUTE FORMAT( 'UPDATE %s SET doc_lens=subquery.doc_lens FROM (SELECT tokenized_doc AS td, CARDINALITY(tokenized_doc) AS doc_lens FROM %s) AS subquery WHERE tokenized_doc = subquery.td;', docstname, docstname );

  /* add word_freqs (JSONB word:count object) */
  EXECUTE FORMAT( 'ALTER TABLE %s ADD COLUMN word_freqs JSONB;', docstname );
  EXECUTE FORMAT( 'UPDATE %s SET word_freqs=count_words_in_array(tokenized_doc);', docstname );

  /* total word count */
  EXECUTE FORMAT( 'SELECT SUM(doc_lens) FROM %s;', docstname ) INTO total_word_count;

  /* this debug statement is not required */
  /*INSERT INTO bm25_params_debug(paramname,value) VALUES('total_word_count',total_word_count);*/

  /* create words table */
  EXECUTE FORMAT( 'DROP TABLE IF EXISTS %s;', wordstname );
  EXECUTE FORMAT( 'CREATE TABLE %s ( word TEXT PRIMARY KEY, word_docs_count INTEGER, idf DOUBLE PRECISION );', wordstname );

  /* count docs with each word */
  EXECUTE FORMAT('SELECT get_word_docs_count( %s, word_freqs ) FROM %s;', quote_literal(wordstname), docstname );

  /* self.avg_doc_len = total_word_count / self.corpus_len */
  EXECUTE FORMAT( 'SELECT COUNT(doc_lens) FROM %s WHERE doc_lens > 0;', docstname ) INTO corpus_len;
  avg_doc_len := total_word_count::DOUBLE PRECISION / corpus_len::DOUBLE PRECISION;

  /* these debug statements are not required */
  /*INSERT INTO bm25_params_debug(paramname,value) VALUES('corpus_len',corpus_len);
  INSERT INTO bm25_params_debug(paramname,value) VALUES('avg_doc_len',avg_doc_len);*/

  /*  # precalc "half of divisor" + self.k1 * (1 - self.b + self.b * doc_lens / self.avg_doc_len)  */
  EXECUTE FORMAT( 'ALTER TABLE %s ADD COLUMN hds DOUBLE PRECISION;', docstname );
  EXECUTE FORMAT( 'UPDATE %s SET hds = %s * ( 1.0::DOUBLE PRECISION - %s + %s * doc_lens / %s ) ;', docstname, param_k1, param_b, param_b, avg_doc_len );


  /* idf = math.log(self.corpus_len - freq + 0.5) - math.log(freq + 0.5) ; self.idf[word] = idf ; idf_sum += idf */
  EXECUTE FORMAT( 'UPDATE %s SET idf = LN( %s - word_docs_count::DOUBLE PRECISION + 0.5::DOUBLE PRECISION) - LN( word_docs_count::DOUBLE PRECISION + 0.5::DOUBLE PRECISION);', wordstname, corpus_len::DOUBLE PRECISION );
  EXECUTE FORMAT( 'SELECT SUM(idf) FROM %s;', wordstname ) INTO idf_sum;
  EXECUTE FORMAT( 'SELECT COUNT(word) FROM %s;', wordstname ) INTO vocab_len;
  average_idf = idf_sum / vocab_len::DOUBLE PRECISION;
  param_eps = param_epsilon * average_idf;
  EXECUTE FORMAT( 'UPDATE %s SET idf = %s WHERE idf < 0;', wordstname, param_eps );

  /* these debug statements are not required */
  /*INSERT INTO bm25_params_debug(paramname,value) VALUES('idf_sum',idf_sum);
  INSERT INTO bm25_params_debug(paramname,value) VALUES('vocab_len',vocab_len);
  INSERT INTO bm25_params_debug(paramname,value) VALUES('average_idf',average_idf);
  INSERT INTO bm25_params_debug(paramname,value) VALUES('param_eps',param_eps);*/

  /*  words * documents score map  */
  EXECUTE FORMAT( 'ALTER TABLE %s ADD COLUMN wsmap DOUBLE PRECISION[];', wordstname );
  EXECUTE FORMAT( 'UPDATE %s SET wsmap = get_wsmapobj( %s, word, idf, %s );', wordstname, quote_literal(docstname), param_k1 );

END;
$$;


/* bm25scorerows() get the documentscores row for each word */
DROP FUNCTION IF EXISTS bm25scorerows;
CREATE OR REPLACE FUNCTION bm25scorerows(tablename TEXT, mquery TEXT) RETURNS SETOF double precision[]
LANGUAGE plpgsql
AS $$
DECLARE
  w TEXT := '';
BEGIN
  FOR w IN SELECT unnest(bm25simpletokenize(mquery))
  LOOP
    RETURN QUERY EXECUTE FORMAT( 'SELECT wsmap FROM %s WHERE word = %s;', tablename, quote_literal(w) );
  END LOOP;
END;
$$;


/* bm25scoressum(): sums the score rows to one array with the document scores ; TODO: instead of xdocstname maybe with temp table, race condition here? */
DROP FUNCTION IF EXISTS bm25scoressum;
CREATE OR REPLACE FUNCTION bm25scoressum(tablename TEXT, tokenizedquery TEXT) RETURNS SETOF double precision[]
LANGUAGE plpgsql
AS $$
DECLARE
  xdocstname TEXT := tablename || '_bm25i_temp';
BEGIN
  EXECUTE FORMAT( 'DROP TABLE IF EXISTS %s;', xdocstname );
  EXECUTE FORMAT( 'CREATE TABLE %s AS SELECT bm25scorerows(%s, %s);', xdocstname, quote_literal(tablename), quote_literal(tokenizedquery) );
  RETURN QUERY EXECUTE FORMAT( 'SELECT ARRAY_AGG(sum ORDER BY ord) FROM (SELECT ord, SUM(int) FROM %s, unnest(bm25scorerows) WITH ORDINALITY u(int, ord) GROUP BY ord);', xdocstname );
END;
$$;


/* bm25scunnest(): unnests the score array */
DROP FUNCTION IF EXISTS bm25scunnest;
CREATE OR REPLACE FUNCTION bm25scunnest(tablename TEXT, tokenizedquery TEXT) RETURNS TABLE(score double precision)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY SELECT unnest(bm25scoressum(tablename,tokenizedquery));
END;
$$;


/* bm25isc(): returns the index and score of the documents; index starts with 1 */
DROP FUNCTION IF EXISTS bm25isc;
CREATE OR REPLACE FUNCTION bm25isc(tablename TEXT, tokenizedquery TEXT) RETURNS TABLE(id BIGINT, score double precision)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY SELECT row_number() OVER () AS id, bm25scunnest FROM bm25scunnest(tablename,tokenizedquery) ;
END;
$$;


/* bm25topk(): returns the index, score and document sorted and limited |  TABLE(id INT, id2 BIGINT, score double precision, doc TEXT) */
DROP FUNCTION IF EXISTS bm25topk;
CREATE OR REPLACE FUNCTION bm25topk(tablename TEXT, columnname TEXT, tokenizedquery TEXT, k INT) RETURNS TABLE(id INTEGER, score double precision, doc TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
  docstname TEXT := tablename || '_' ||  columnname || '_bm25i_docs';
  wordstname TEXT := tablename || '_' ||  columnname || '_bm25i_words';
BEGIN
  RETURN QUERY EXECUTE FORMAT( 'SELECT t1.id, t2.score, t1.%s AS doc FROM (SELECT id, doc AS %s FROM %s) t1 INNER JOIN ( SELECT id, score FROM bm25isc(%s,%s) ) t2 ON ( t1.id = t2.id ) ORDER BY t2.score DESC LIMIT %s;', columnname, columnname, docstname, quote_literal(wordstname), quote_literal(tokenizedquery), k );
END;
$$;

