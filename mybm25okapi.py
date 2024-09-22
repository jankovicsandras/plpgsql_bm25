"""
This is a refactored variant of rank_bm25 Okapi. https://github.com/dorianbrown/rank_bm25
This is not required for plpgsql_bm25, just here for comparison / testing.

Usage:
  - corpus and query must be tokenized already, e.g. corpus = [ ['one','two','three'], ['bla','two','two'] ]  ; query = [ 'Is', 'this', 'a', 'question?' ] ; see also mytokenize()
  - __init__(corpus) will initialize the bm25Okapi components, where self.wsmap is the most important
  - No update is possible, so if the documents change in the corpus, then __init__(corpus) must be called again (recreating all the components).
  - search with topk() or get_scores()
"""
import math


class mybm25okapi:
  def __init__(self, corpus):
    # constants
    self.debugmode = False
    self.k1 = 1.5
    self.b = 0.75
    self.epsilon = 0.25

    self.corpus_len = len(corpus)
    self.avg_doc_len = 0
    self.word_freqs = []
    self.idf = {}
    self.doc_lens = []
    word_docs_count = {}  # word -> number of documents with word
    total_word_count = 0

    for document in corpus:
      # doc lengths and total word count
      self.doc_lens.append(len(document))
      total_word_count += len(document)

      # word frequencies in this document
      frequencies = {}
      for word in document:
        if word not in frequencies:
          frequencies[word] = 0
        frequencies[word] += 1
      self.word_freqs.append(frequencies)

      # number of documents with word count
      for word, freq in frequencies.items():
        try:
          word_docs_count[word] += 1
        except KeyError:
          word_docs_count[word] = 1

    # average document length
    self.avg_doc_len = total_word_count / self.corpus_len

    if self.debugmode : print('self.corpus_len',self.corpus_len,'\nself.doc_lens',self.doc_lens,'\ntotal_word_count',total_word_count,'\nself.word_freqs',self.word_freqs,'\nself.avg_doc_len',self.avg_doc_len,'\nword_docs_count',word_docs_count)

    # precalc "half of divisor" + self.k1 * (1 - self.b + self.b * doc_lens / self.avg_doc_len)
    self.hds = [ self.k1 * ( 1-self.b + self.b*doc_len/self.avg_doc_len) for doc_len in self.doc_lens ]
    if self.debugmode : print('self.hds',self.hds)

    """
    Calculates frequencies of terms in documents and in corpus.
    This algorithm sets a floor on the idf values to eps * average_idf
    """
    # collect idf sum to calculate an average idf for epsilon value
    # collect words with negative idf to set them a special epsilon value.
    # idf can be negative if word is contained in more than half of documents
    idf_sum = 0
    negative_idfs = []
    for word, freq in word_docs_count.items():
      idf = math.log(self.corpus_len - freq + 0.5) - math.log(freq + 0.5)
      self.idf[word] = idf
      idf_sum += idf
      if idf < 0:
        negative_idfs.append(word)
      if self.debugmode : print('word',word,'self.idf[word]',self.idf[word])
    self.average_idf = idf_sum / len(self.idf)
    if self.debugmode : print('idf_sum',idf_sum,'len(self.idf)',len(self.idf),'self.average_idf',self.average_idf)
    # assign epsilon
    eps = self.epsilon * self.average_idf
    if self.debugmode : print('eps',eps)
    for word in negative_idfs:
      self.idf[word] = eps
      if self.debugmode : print('word',word,'got eps',eps)
    if self.debugmode : print('self.idf',self.idf)


    # words * documents score map
    self.wsmap = {}
    for word in self.idf :
      self.wsmap[word] = [0] * self.corpus_len
      word_freqs = [ (word_freq.get(word) or 0) for word_freq in self.word_freqs ]
      thiswordidf = (self.idf.get(word) or 0)
      if self.debugmode : print('word in self.idf',word,'thiswordidf',thiswordidf,'word_freqs',word_freqs)
      for i in range(0,self.corpus_len) :
        self.wsmap[word][i] = thiswordidf * ( word_freqs[i] * (self.k1 + 1) / ( word_freqs[i] + self.hds[i] ) ) # += replaced with =
    if self.debugmode : print('self.wsmap',self.wsmap)


  # get a list of scores for every document
  def get_scores(self, tokenizedquery):
    # zeroes list of scores
    scores = [0] * self.corpus_len
    # for each word in tokenizedquery, if word is in wsmap, lookup and add word score for every documents' scores
    for word in tokenizedquery:
      if word in self.wsmap :
        for i in range(0,self.corpus_len) :
          scores[i] += self.wsmap[word][i]
    # return scores list (not sorted)
    return scores


  def topk(self,tokenizedquery,k=None):
    docscores = self.get_scores( tokenizedquery )
    sisc = [ [i,s] for i,s in enumerate(docscores) ]
    sisc.sort(key=lambda x:x[1],reverse=True)
    if k :
      sisc = sisc[:k]
    return sisc


  # save the words*documents score map as csv for import to Postgres: COPY tablename_bm25wsmap FROM '/path-to/tablename_bm25wsmap.csv' DELIMITER ';' CSV HEADER;
  def exportwsmap(self, csvfilename) :
    with open(csvfilename,'w+') as f:
      f.write('word;vl\n')
      for word in self.wsmap :
        f.write('"'+word.replace('"','\'')+'";{'+str(self.wsmap[word]).strip()[1:-1]+'}\n')




# tokenization function
def mytokenize(s) :
  ltrimchars = ['(','[','{','<','\'','"']
  rtrimchars = ['.', '?', '!', ',', ':', ';', ')', ']', '}', '>','\'','"']
  if type(s) != str : return []
  wl = s.lower().split()
  for i,w in enumerate(wl) :
    if len(w) < 1 : continue
    si = 0
    ei = len(w)
    try :
      while si < ei and w[si] in ltrimchars : si += 1
      while ei > si and w[ei-1] in rtrimchars : ei -= 1
      wl[i] = wl[i][si:ei]
    except Exception as ex:
      print('|',w,'|',ex,'|',wl)
  wl = [ w for w in wl if len(w) > 0 ]
  return wl

