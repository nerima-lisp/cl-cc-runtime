;;;; Tests for the dependency-free regex and persistent data structure modules.
(in-package :cl-cc-runtime/test)

(describe "regular expressions"
  (it "matches literals and concatenation"
    (expect (rt-regex-match-p "ab" "ab") :to-be-truthy)
    (expect (rt-regex-match-p "ab" "ac") :to-be-null))
  (it "supports alternation and repetition"
    (expect (rt-regex-match-p "(cat|dog)s?" "dogs") :to-be-truthy)
    (expect (rt-regex-match-p "a+b*" "aaabbb") :to-be-truthy)
    (expect (rt-regex-match-p "a+b*" "bbb") :to-be-null))
  (it "supports classes, escapes, anchors, and search"
    (expect (rt-regex-match-p "^[a-z]+@[a-z]+\\.com$" "a@b.com") :to-be-truthy)
    (expect (rt-regex-match-p "^[^0-9]+$" "abc") :to-be-truthy)
    (expect (rt-regex-search "cat" "a cat nap") :to-equal '(2 . 5))))

(describe "persistent data structures"
  (it "keeps vector versions independent"
    (let* ((old (rt-persistent-vector 1 2))
           (new (rt-persistent-vector-assoc old 0 9))
           (grown (rt-persistent-vector-conj new 3)))
      (expect (rt-persistent-vector-ref old 0) :to-be 1)
      (expect (rt-persistent-vector-ref new 0) :to-be 9)
      (expect (rt-persistent-vector-length grown) :to-be 3)
      (expect (rt-persistent-vector-ref grown 2) :to-be 3)))
  (it "shares map versions without mutation"
    (let* ((empty (rt-persistent-map))
           (one (rt-persistent-map-assoc empty :a 1))
           (two (rt-persistent-map-assoc one :b 2)))
      (expect (rt-persistent-map-get empty :a :missing) :to-be :missing)
      (expect (rt-persistent-map-get one :a) :to-be 1)
      (expect (rt-persistent-map-get one :b :missing) :to-be :missing)
      (expect (rt-persistent-map-get two :b) :to-be 2))))
