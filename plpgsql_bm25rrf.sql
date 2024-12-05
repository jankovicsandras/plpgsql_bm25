/*

  plpgsql_bm25rrf.sql
  Hybrid search with Reciprocal Rank Fusion
  
  Requirements: 
    - https://github.com/jankovicsandras/plpgsql_bm25
    - https://github.com/pgvector/pgvector
    - The documents and their vector embeddings are stored in the same table
    - The BM25 index is already created with bm25createindex()

  Example:
    SELECT * FROM bm25rrf( querytext, queryembedding, tablename, idcolumnname, doccolumnname, embeddingcolumnname, resultlimit, algo );

*/


DROP FUNCTION IF EXISTS bm25rrf;
CREATE OR REPLACE FUNCTION bm25rrf(querytext TEXT, queryembedding vector, tablename TEXT, idcolumnname TEXT, doccolumnname TEXT, embeddingcolumnname TEXT, slimit INT DEFAULT 20, algo TEXT DEFAULT '') RETURNS TABLE(id INTEGER, score NUMERIC, doc TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY EXECUTE FORMAT( 'WITH vector_search AS (
            SELECT %s AS id, RANK () OVER (ORDER BY %s <=> %s) AS rank, %s AS doc FROM %s ORDER BY %s <=> %s LIMIT %s
        ),
        bm25_search AS (
            SELECT %s AS id, RANK () OVER (ORDER BY score DESC) AS rank, doc FROM bm25topk( %s, %s, %s, %s, %s )
        )
        SELECT
            COALESCE(vector_search.id, bm25_search.id) AS id,
            COALESCE(1.0 / (60 + vector_search.rank), 0.0) + COALESCE(1.0 / (60 + bm25_search.rank), 0.0) AS score,
            COALESCE(vector_search.doc, bm25_search.doc) AS doc
        FROM vector_search
        FULL OUTER JOIN bm25_search ON vector_search.doc = bm25_search.doc
        ORDER BY score DESC LIMIT %s ;', idcolumnname, embeddingcolumnname, quote_literal(queryembedding), doccolumnname, tablename, embeddingcolumnname, quote_literal(queryembedding), slimit, idcolumnname, quote_literal(tablename), quote_literal(doccolumnname), quote_literal(querytext), slimit, quote_literal(algo), slimit );
END;
$$;

