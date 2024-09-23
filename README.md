README.md

# plpgsql_bm25
## BM25 search implemented in PL/pgSQL

----
### News
 - PL/pgSQL BM25 search functions work in Postgres without any extensions / Rust

### Roadmap / TODO
 - implement other algorithms from rank_bm25, not just Okapi
 - tokenization options, stopwords
 - test performance vs. Rust extension solutions (pg_search, pg_bestmatch.rs)
 - bm25scoressum() temp table?

----
### Contributions welcome!
The author is not a Postgres / PL/pgSQL expert, gladly accepts optimizations or constructive criticism.

----
###   Example usage:

```plpgsql
  SELECT bm25createindex( tablename, columnname );  /* tablename and columnname are TEXT types */
  SELECT * FROM bm25topk( tablename, columnname, question, k ); /* question is TEXT, k is INTEGER */
```

----
### What is this?
 - https://en.wikipedia.org/wiki/Okapi_BM25
 - https://en.wikipedia.org/wiki/PL/pgSQL
 - https://github.com/dorianbrown/rank_bm25
 - TLDR:
    - BM25Okapi is a popular search algorithm.
    - Index building: Initially, there's a list of texts or documents called the corpus. Each document will be split to words (or tokens) with the tokenization function (the simplest is split on whitespace characters). The algorithm then builds a word-score-map ```wsmap```, where every word in the corpus is scored for every document based on their frequencies, ca. how special a word is in the corpus and how frequent in the current document.
    - Search: the question text (or query string) will be tokenized, then the search function looks up the words from ```wsmap``` and sums the scores for each document; the result is a list of scores, one for each document. The highest scoring document is the best match. The search function sorts the scores-documentIDs in descending order.
    - Adding a new document to the corpus or changing one requires rebuilding the whole BM25 index (```wsmap```), because of how the algorithm works.

----
### Repo contents
 - ```plpgsql_bm25.sql``` : PL/pgSQL functions for BM25 search
 - ```plpgsql_bm25_test.ipynb``` : Latest Jupyter notebook with comparative testing of plpgsql_bm25.sql, rank_bm25 and mybm25okapi.py.
 - ```plpgsql_bm25_dev.ipynb``` : Jupyter notebook where I develop this.
 - ```plpgsql_bm25_old_dev.ipynb``` : old
 - ```mybm25okapi.py``` : Python BM25 index builder, see also https://github.com/dorianbrown/rank_bm25

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

As https://github.com/dorianbrown/rank_bm25 has Apache-2.0 license, the derived mybm25okapi class should probably have Apache-2.0 license. The test datasets and other external code might have different licenses, please check them.

My code:

The Unlicense / PUBLIC DOMAIN

This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or distribute this software, either in source code form or as a compiled binary, for any purpose, commercial or non-commercial, and by any means.

In jurisdictions that recognize copyright laws, the author or authors of this software dedicate any and all copyright interest in the software to the public domain. We make this dedication for the benefit of the public at large and to the detriment of our heirs and successors. We intend this dedication to be an overt act of relinquishment in perpetuity of all present and future rights to this software under copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to http://unlicense.org
