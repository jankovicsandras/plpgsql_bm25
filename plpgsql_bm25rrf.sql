/*

  plpgsql_bm25rrf.sql
  Hybrid search with Reciprocal Rank Fusion
  version 1.1.0 by András Jankovics  https://github.com/jankovicsandras  andras@jankovics.net
  
  Requirements: 
    - https://github.com/jankovicsandras/plpgsql_bm25
    - https://github.com/pgvector/pgvector
    - The documents and their vector embeddings are stored in the same table
    - The BM25 index is already created with bm25createindex()

  Example:
    SELECT * FROM bm25rrf( querytext, queryembedding, tablename, idcolumnname, doccolumnname, embeddingcolumnname, resultlimit, algo, stopwordslanguage );

*/


DROP FUNCTION IF EXISTS bm25rrf;

CREATE OR REPLACE FUNCTION bm25rrf(
    querytext TEXT,
    queryembedding vector,
    tablename TEXT,
    idcolumnname TEXT,
    doccolumnname TEXT,
    embeddingcolumnname TEXT,
    slimit INT DEFAULT 20,
    algo TEXT DEFAULT '',
    stopwordslanguage TEXT DEFAULT ''
) RETURNS TABLE(id INTEGER, score NUMERIC, doc TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY EXECUTE FORMAT(
        $f$
        WITH vector_search AS (
            SELECT 
                %1$I AS id,
                RANK() OVER (ORDER BY %2$I <=> %3$L) AS rank,
                %4$I AS doc
            FROM %5$I
            ORDER BY %2$I <=> %3$L
            LIMIT %8$L
        ),
        bm25_search AS (
            SELECT 
                %1$I AS id,
                RANK() OVER (ORDER BY score DESC) AS rank,
                doc
            FROM bm25topk(
                %3$L, %9$L, %4$L, %10$L, %11$L, %8$L
            )
        )
        SELECT
            COALESCE(vector_search.id, bm25_search.id) AS id,
            COALESCE(1.0 / (60 + vector_search.rank), 0.0) + 
            COALESCE(1.0 / (60 + bm25_search.rank), 0.0) AS score,
            COALESCE(vector_search.doc, bm25_search.doc) AS doc
        FROM vector_search
        FULL OUTER JOIN bm25_search 
            ON vector_search.doc = bm25_search.doc
        ORDER BY score DESC
        LIMIT %8$L;
        $f$,
        -- FORMAT parameters
        idcolumnname,       
        embeddingcolumnname,
        queryembedding,     
        doccolumnname,      
        tablename,          
        embeddingcolumnname,
        doccolumnname,     
        slimit,             
        tablename,          
        doccolumnname,    
        querytext          
    );
END;
$$;
