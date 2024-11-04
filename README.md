README.md

# plpgsql_bm25
## BM25 search implemented in PL/pgSQL

----
### News
 - all three BM25 algorithms from rank_bm25 are implemented ( BM25Okapi, BM25L, BM25Plus )
 - an optimized Python implementation is available, see [BM25opt](https://github.com/jankovicsandras/bm25opt), which runs 30-40 x faster than rank_bm25

### Roadmap / TODO
 - tokenization options, stopwords
 - bm25scoressum() temp table?

----
### Contributions welcome!
The author is not a Postgres / PL/pgSQL expert, gladly accepts optimizations or constructive criticism.

----
###   Example usage:
1. download and execute [plpgsql_bm25.sql](https://raw.githubusercontent.com/jankovicsandras/plpgsql_bm25/refs/heads/main/plpgsql_bm25.sql) to load the functions, e.g.
   ```bash
   wget https://raw.githubusercontent.com/jankovicsandras/plpgsql_bm25/refs/heads/main/plpgsql_bm25.sql
   psql -f plpgsql_bm25.sql
   ```
3. then
   ```plpgsql
     SELECT bm25createindex( tablename, columnname );  /* tablename and columnname are TEXT types */
     SELECT * FROM bm25topk( tablename, columnname, question, k ); /* question is TEXT, k is INTEGER */
   ```

BM25Okapi is the default algoritm. If you would like to use BM25L or BM25Plus, then the ```algo``` parameter must be specified, ```'l'``` is BM25L and ```'plus'``` is BM25Plus, e.g. :
```plpgsql
  SELECT bm25createindex( tablename, columnname, algo=>'plus' );  /* tablename and columnname are TEXT types */
  SELECT * FROM bm25topk( tablename, columnname, question, k, algo=>'plus' ); /* question is TEXT, k is INTEGER */
```

Calling these from Python with a simple psycopg2 helper:
```Python
# it is assumed that 'mytable' exists in the Postgres DB and has a 'mycolumn' (type TEXT)
tablename = 'mytable'
columnname = 'mycolumn'
p_algo = 'l' # BM25L algoritm
k = 5 # top k results
q = 'this is my question'
msq( 'SELECT bm25createindex( \''+tablename+'\', \''+columnname+'\', algo=>\''+p_algo+'\' );' )
msq( 'SELECT * FROM bm25topk( \''+tablename+'\', \''+columnname+'\', \''+q.replace("'","\'\'")+'\', '+str(k)+', algo=>\''+p_algo+'\' );' )
```
----
### API
```plpgsql
bm25createindex(tablename TEXT, columnname TEXT, algo TEXT DEFAULT '') RETURNS VOID
```
 - This creates the BM25 index by creating these new tables:
   ```plpgsql
     docstname TEXT := tablename || '_' ||  columnname || '_bm25i_docs' || algo;
     wordstname TEXT := tablename || '_' ||  columnname || '_bm25i_words' || algo;
   ```
 - The index creation is a costy operation, but required after every change in the corpus (the original texts in tablename->columnname).
 - ```algo``` values: ```''``` is BM25Okapi (default),  ```'l'``` is BM25L,   ```'plus'``` is BM25Plus. 


```plpgsql
bm25topk(tablename TEXT, columnname TEXT, mquery TEXT, k INT, algo TEXT DEFAULT '') RETURNS TABLE(id INTEGER, score double precision, doc TEXT)
```
 - This is the search function, which returns the top ```k``` documents and their scores that are most similar to ```mquery``` (the question).
 - WARNING: the ```id``` column in the result table must not be used, instead the ```doc``` must be matched with (tablename->columnname) in the original table to get the record / ordering. The ```id``` column and the ordering of ```doc```s in the result table is not guaranteed to be the same as the ordering as the ordering of records in the original table.

```plpgsql
bm25simpletokenize(txt TEXT) RETURNS TEXT[]
```
 - The default tokenizer function. If you need another / custom tokenizer, then you need to overwrite this (DROP FUNCTION... CREATE OR REPLACE FUNCTION...).

----
### What is this?
 - https://en.wikipedia.org/wiki/Okapi_BM25
 - https://en.wikipedia.org/wiki/PL/pgSQL
 - https://github.com/dorianbrown/rank_bm25
 - https://github.com/jankovicsandras/bm25opt
 - TLDR:
    - BM25Okapi is a popular search algorithm.
    - Index building: Initially, there's a list of texts or documents called the corpus. Each document will be split to words (or tokens) with the tokenization function (the simplest is split on whitespace characters). The algorithm then builds a word-score-map ```wsmap```, where every word in the corpus is scored for every document based on their frequencies, ca. how special a word is in the corpus and how frequent in the current document.
    - Search: the question text (or query string) will be tokenized, then the search function looks up the words from ```wsmap``` and sums the scores for each document; the result is a list of scores, one for each document. The highest scoring document is the best match. The search function sorts the scores-documentIDs in descending order.
    - Adding a new document to the corpus or changing one requires rebuilding the whole BM25 index (```wsmap```), because of how the algorithm works.

----
### Repo contents
#### required
 - ```plpgsql_bm25.sql``` : PL/pgSQL functions for BM25 search
#### development and test
 - ```plpgsql_bm25_dev_20241103.ipynb``` : Jupyter notebook where I develop this.
 - ```plpgsql_bm25_comparison_with_paradedb_pg_search.ipynb``` : Jupyter notebook with comparative testing of plpgsql_bm25.sql, ParadeDB pg_search, rank_bm25 and [BM25opt](https://github.com/jankovicsandras/bm25opt)

----
### Why?
Postgres has already Full Text Search and there are several extensions that implement BM25. But Full Text Search is not the same as BM25. The BM25 extensions are written in Rust, which might not be available / practical, especially in hosted environments. See Alternatives section for more info.

----
### Alternatives:

 - Postgres Full Text Search
   - https://www.postgresql.org/docs/current/textsearch.html
   - https://postgresml.org/blog/postgres-full-text-search-is-awesome


 - Rust based BM25
   - https://github.com/paradedb/paradedb/tree/dev/pg_search#overview
   - https://github.com/tensorchord/pg_bestmatch.rs


 - Postgres similarity of text using trigram matching
   - https://www.postgresql.org/docs/current/pgtrgm.html

   - NOTE: this is useful for fuzzy string matching, like spelling correction, but not query->document search solution itself.
The differing document and query text lengths will result very small relative trigram frequencies and incorrect/missing matching.

----
### Special thanks to: dorianbrown, Myon, depesz, sobel, ilmari, xiaomiao and others from #postgresql

----
### LICENSE

The Unlicense / PUBLIC DOMAIN

This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or distribute this software, either in source code form or as a compiled binary, for any purpose, commercial or non-commercial, and by any means.

In jurisdictions that recognize copyright laws, the author or authors of this software dedicate any and all copyright interest in the software to the public domain. We make this dedication for the benefit of the public at large and to the detriment of our heirs and successors. We intend this dedication to be an overt act of relinquishment in perpetuity of all present and future rights to this software under copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to http://unlicense.org
