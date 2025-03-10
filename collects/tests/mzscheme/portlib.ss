
(load-relative "loadtest.ss")

(SECTION 'port)

(define SLEEP-TIME 0.1)

(require (lib "port.ss"))

;; ----------------------------------------

;; pipe and pipe-with-specials commmit tests
(define (test-pipe-commit make-pipe)
  (let-values ([(in out) (make-pipe)])
    (display "apple" out)
    (test #"app" peek-bytes 3 0 in)
    (let ([sema (make-semaphore 1)])
      (test #t port-commit-peeked 3 (port-progress-evt in) sema in)
      (test #f semaphore-try-wait? sema))
    (test #"le" read-bytes 2 in)
    (display "banana" out)
    (test #"ban" peek-bytes 3 0 in)
    ;; Set up a commit that fails, because the done-evt never becomes ready:
    (let* ([r '?]
	   [unless-evt (port-progress-evt in)]
	   [th (thread
		(lambda ()
		  (set! r (port-commit-peeked 3 unless-evt never-evt in))))])
      (sleep SLEEP-TIME)
      (test #t thread-running? th)
      (test #\b peek-char in)
      (sleep SLEEP-TIME)
      (test #t thread-running? th)
      (test #f sync/timeout 0 unless-evt)
      (test #\b read-char in)
      (sleep SLEEP-TIME)
      (test th sync th)
      (test #f values r))
    (test "anana" read-string 5 in)
    ;; Set up two commits, pick one to succeed:
    (let ([go (lambda (which peek? suspend/kill)
		(printf "~a ~a ~a~n" which peek? suspend/kill)
		(display "donut" out)
		(test #"don" peek-bytes 3 0 in)
		(let* ([r1 '?]
		       [r2 '?]
		       [s1 (make-semaphore)]
		       [s2 (make-semaphore)]
		       [unless-evt (port-progress-evt in)]
		       [th1 (thread
			     (lambda ()
			       (set! r1 (port-commit-peeked 1 unless-evt s1 in))))]
		       [_ (sleep SLEEP-TIME)]
		       [th2 (thread
			     (lambda ()
			       (set! r2 (port-commit-peeked 2 unless-evt (semaphore-peek-evt s2) in))))])
		  (sleep SLEEP-TIME)
		  (when suspend/kill
		    (case suspend/kill
		      [(suspend) (thread-suspend th1)]
		      [(kill) (kill-thread th1)])
		    (sleep SLEEP-TIME))
		  (test (eq? suspend/kill 'kill) thread-dead? th1)
		  (test #f thread-dead? th2)
		  (when peek?
		    (test #"do" peek-bytes 2 0 in)
		    (sleep SLEEP-TIME))
		  (unless (= which 3)
		    (semaphore-post (if (= which 1) s1 s2)))
		  (when (= which 3)
		    (test #"do" read-bytes 2 in))
		  (sleep SLEEP-TIME)
		  (test unless-evt sync/timeout 0 unless-evt)
		  (test (not (eq? suspend/kill 'suspend)) thread-dead? th1)
		  (sleep SLEEP-TIME)
		  (test #t thread-dead? th2)
		  (test (if (= which 1) #t (if suspend/kill '? #f)) values r1)
		  (test (= which 2) values r2)
		  (test (if (= which 1) #\o #\n) read-char in)
		  (test (if (= which 1) #"nut" #"ut") read-bytes (if (= which 1) 3 2) in)))])
      (go 1 #f #f)
      (go 2 #f #f)
      (go 1 #t #f)
      (go 2 #t #f)
      (go 3 #f #f)
      (go 2 #f 'suspend)
      (go 2 #t 'suspend)
      (go 3 #f 'suspend)
      (go 2 #f 'kill)
      (go 2 #t 'kill)
      (go 3 #f 'kill))))
(test-pipe-commit make-pipe)
(test-pipe-commit (lambda () (make-pipe-with-specials 10000 'special-pipe 'spec-pipe)))

;; pipe-with-specials and limit; also used to test peeked-input-port
(define (test-special-pipe make-pipe-with-specials)
  (let-values ([(in out) (make-pipe-with-specials 10)])
    ;; Check that write events work
    (test 5 sync (write-bytes-avail-evt #"12345" out))
    (test #"12345" read-bytes 5 in)
    (test #f char-ready? in)
    (test #t sync (write-special-evt 'okay out))
    (test 11 write-bytes-avail (make-bytes 11 65) out)
    (test 'okay read-char-or-special in)
    (test (make-bytes 11 65) read-bytes 11 in)

    (let ()
      (define (bg thunk runs? spec? exn?)
	;; Fill the pipe, again:
	(test 10 write-bytes (make-bytes 10 66) out)
	(let* ([ex #f]
	       [th (thread 
		    (lambda ()
		      (with-handlers ([exn:fail? (lambda (x) 
						   (set! ex #t)
						   (raise x))])
			(sync (write-bytes-avail-evt #"x" out)))))])
	  (sleep SLEEP-TIME)
	  (test #t thread-running? th)
	  ;; This thunk (and sometimes read) should go through the manager:
	  (thunk)
	  (sleep SLEEP-TIME)
	  (test (not runs?) thread-running? th)
	  (test (make-bytes 10 66) read-bytes 10 in)
	  (thread-wait th)
	  (test ex values exn?))
	(when spec?
	  (test 'c read-char-or-special in))
	(test (if exn? eof #"x") read-bytes 1 in))
      
      (bg (lambda () (test 0 write-bytes-avail* #"c" out)) #f #f #f)
      (bg (lambda () (test #t write-special 'c out)) #t #t #f)
      (bg (lambda () (test (void) close-output-port out)) #t #f #t))))
(test-special-pipe make-pipe-with-specials)
(test-special-pipe (lambda (limit)
		     (let-values ([(in out) (make-pipe-with-specials limit)])
		       (values (peeking-input-port in) out))))

;; copy-port and make-pipe-with-specials tests
(let ([s (let loop ([n 10000][l null])
	   (if (zero? n)
	       (apply bytes l)
	       (loop (sub1 n) (cons (random 256) l))))])
  (let-values ([(in out) (make-pipe-with-specials)])
    (display s out)
    (test #t 'pipe-same? (bytes=? s (read-bytes (bytes-length s) in)))
    (test out sync/timeout 0 out)
    (test #f sync/timeout 0 in)
    (write-special 'hello? out)
    (test 'hello? read-char-or-special in)
    (display "123" out)
    (write-special 'again! out)
    (display "45" out)
    (let ([s (make-bytes 5)])
      (test 3 read-bytes-avail! s in)
      (test #"123\0\0" values s)
      (let ([p (read-bytes-avail! s in)])
	(test #t procedure? p)
	(test 'again! p 'ok 1 2 3))
      (test 2 read-bytes-avail! s in)
      (test #"453\0\0" values s)))
  (let ([in (open-input-bytes s)]
	[out (open-output-bytes)])
    (copy-port in out)
    (test #t 'copy-same? (bytes=? s (get-output-bytes out))))
  (let* ([a (subbytes s 0 (max 1 (random (bytes-length s))))]
	 [b (subbytes s (bytes-length a) (+ (bytes-length a)
					    (max 1 (random (- (bytes-length s) (bytes-length a))))))]
	 [c (subbytes s (+ (bytes-length a) (bytes-length b)))])
    (define (go-stream close? copy? threads? peek?)
      (printf "Go stream: ~a ~a ~a ~a~n" close? copy? threads? peek?)
      (let*-values ([(in1 out) (make-pipe-with-specials)]
		    [(in out1) (if copy?
				   (make-pipe-with-specials)
				   (values in1 out))])
	(let ([w-th
	       (lambda ()
		 (display a out)
		 (write-special '(first one) out)
		 (display b out)
		 (write-special '(second one) out)
		 (display c out)
		 (when close?
		   (close-output-port out)))]
	      [c-th (lambda ()
		      (when copy?
			(copy-port in1 out1)
			(close-output-port out1)))]
	      [r-th (lambda ()
		      (let ([get-one-str
			     (lambda (a)
			       (let ([dest (make-bytes (bytes-length s))]
				     [target (bytes-length a)])
				 (let loop ([n 0])
				   (let ([v (read-bytes-avail! dest in n)])
				     (if (= target (+ v n))
					 (test #t `(same? ,target) (equal? (subbytes dest 0 target) a))
					 (loop (+ n v)))))))]
			    [get-one-special
			     (lambda (spec)
			       (let ([v (read-bytes-avail! (make-bytes 10) in)])
				 (test #t procedure? v)
				 (test spec v 'ok 5 5 5)))])
			(when peek?
			  (test '(second one) peek-byte-or-special in (+ (bytes-length a) 1 (bytes-length b))))
			(get-one-str a)
			(get-one-special '(first one))
			(get-one-str b)
			(get-one-special '(second one))
			(get-one-str c)
			(if close?
			    (test eof read-byte in)
			    (test #f sync/timeout 0 in))))])
	  (let ([th (if threads?
			thread
			(lambda (f) (f)))])
	    (for-each (lambda (t)
			(and (thread? t) (thread-wait t)))
		      (list
		       (th w-th)
		       (th c-th)
		       (th r-th)))))))
    (go-stream #f #f #f #f)
    (go-stream #t #f #f #f)
    (go-stream #t #t #f #f)
    (go-stream #t #f #t #f)
    (go-stream #t #t #t #f)
    (go-stream #t #f #f #t)
    (go-stream #t #t #f #t)
    (go-stream #t #f #t #t)
    (go-stream #t #t #t #t)))

;; make-input-port/read-to-peek
(define (make-list-port . l)
  (make-input-port/read-to-peek 
   'list-port
   (lambda (bytes)
     (cond
      [(null? l) eof]
      [(byte? (car l))
       (bytes-set! bytes 0 (car l))
       (set! l (cdr l))
       1]
      [(and (char? (car l))
	    (byte? (char->integer (car l))))
       (bytes-set! bytes 0 (char->integer (car l)))
       (set! l (cdr l))
       1]
      [else
       (let ([v (car l)])
	 (set! l (cdr l))
	 (lambda (a b c d) v))]))
   #f
   void))

(let ([p (make-list-port #\h #\e #\l #\l #\o)])
  (test (char->integer #\h) peek-byte p)
  (test (char->integer #\e) peek-byte p 1)
  (test (char->integer #\l) peek-byte p 2)
  (test #"hel" read-bytes 3 p)
  (test (char->integer #\l) peek-byte p)
  (test (char->integer #\o) peek-byte p 1)
  (test #"lo" read-bytes 3 p)
  (test eof peek-byte p)
  (test eof peek-byte p)
  (test eof read-byte p)
  (test eof read-byte p))

(let ([p (make-list-port #\h #\e #\l 'ack #\l #\o)])
  (test (char->integer #\h) read-byte p)
  (test (char->integer #\e) read-byte p)
  (test (char->integer #\l) read-byte p)
  (test 'ack read-byte-or-special p)
  (test (char->integer #\l) read-byte p)
  (test (char->integer #\o) read-byte p))

(let ([p (make-list-port #\h #\e #\l 'ack #\l #\o)])
  (test (char->integer #\h) peek-byte p)
  (test (char->integer #\l) peek-byte p 2)
  (test 'ack peek-byte-or-special p 3)
  (test (char->integer #\l) peek-byte p 4)
  (test #"hel" read-bytes 3 p)
  (test 'ack read-byte-or-special p)
  (test #"lo" read-bytes 4 p))

(test 'hello read (make-list-port #\h #\e #\l #\l #\o))
(let ([p (make-list-port #\h #\e #\l eof #\l #\o)])
  (test 'hel read p)
  (test eof read p)
  (test 'lo read p)
  (test eof read p)
  (test eof read p))
(let ([p (make-list-port #\h #\e #\l #\u7238 #\l #\o)])
  (test 'hel read p)
  (test #\u7238 read p)
  (test 'lo read p))

;; read synchronization events
(define (go mk-hello sync atest btest)
  (test #t list? (list mk-hello sync atest btest))
  (test #"" sync (peek-bytes-evt 0 0 #f (mk-hello)))
  (test #"" sync (read-bytes-evt 0 (mk-hello)))
  (let ([p (mk-hello)])
    (atest #"hello" sync (peek-bytes-evt 5 0 #f p))
    (atest #"llo" sync (peek-bytes-evt 5 2 #f p))
    (atest #"hello" sync (read-bytes-evt 5 p))
    (atest eof sync (peek-bytes-evt 5 0 #f p))
    (atest eof sync (read-bytes-evt 5 p)))
  (test 0 sync (peek-bytes!-evt (make-bytes 0) 0 #f (mk-hello)))
  (test 0 sync (read-bytes!-evt (make-bytes 0) (mk-hello)))
  (let ([s (make-bytes 5)]
	[p (mk-hello)])
    (atest 5 sync (peek-bytes!-evt s 0 #f p))
    (btest #"hello" values s)
    (atest 3 sync (peek-bytes!-evt s 2 #f p))
    (btest #"llolo" values s)
    (bytes-copy! s 0 #"\0\0\0\0\0")
    (atest 5 sync (read-bytes!-evt s p))
    (btest #"hello" values s)
    (atest eof sync (read-bytes!-evt s p)))
  (test 0 sync (read-bytes-avail!-evt (make-bytes 0) (mk-hello)))
  (let ([s (make-bytes 5)]
	[p (mk-hello)])
    (atest 5 sync (peek-bytes-avail!-evt s 0 #f p))
    (btest #"hello" values s)
    (atest 2 sync (peek-bytes-avail!-evt s 3 #f p))
    (btest #"lollo" values s)
    (bytes-copy! s 0 #"\0\0\0\0\0")
    (atest 5 sync (read-bytes-avail!-evt s p))
    (btest #"hello" values s)
    (atest eof sync (read-bytes-avail!-evt s p)))
  (test "" sync (read-string-evt 0 (mk-hello)))
  (let ([p (mk-hello)])
    (atest "hello" sync (peek-string-evt 5 0 #f p))
    (atest "lo" sync (peek-string-evt 5 3 #f p))
    (atest "hello" sync (read-string-evt 5 p))
    (atest eof sync (peek-string-evt 5 0 #f p))
    (atest eof sync (peek-string-evt 5 100 #f p))
    (atest eof sync (read-string-evt 5 p)))
  (test 0 sync (read-string!-evt (make-string 0) (mk-hello)))
  (let ([s (make-string 5)]
	[p (mk-hello)])
    (let ([s2 (make-string 5)])
      (atest 5 sync (peek-string!-evt s2 0 #f p))
      (btest "hello" values s2))
    (atest 5 sync (read-string!-evt s p))
    (btest "hello" values s)
    (atest eof sync (read-string!-evt s p)))
  (let ([p (mk-hello)])
    (atest '(#"hello") sync (regexp-match-evt #rx"....." p)))
  (let ([p (mk-hello)])
    (atest '(#"hello") sync (regexp-match-evt #rx".*" p)))
  (let ([p (mk-hello)])
    (atest '(#"hel") sync (regexp-match-evt #rx"..." p))
    (atest '(#"lo") sync (regexp-match-evt #rx".." p)))
  (let ([p (mk-hello)])
    (atest #"hello" sync (read-bytes-line-evt p))
    (atest eof sync (read-bytes-line-evt p))
    (atest eof sync (eof-evt p)))
  (let ([p (mk-hello)])
    (atest "hello" sync (read-line-evt p))
    (atest eof sync (read-line-evt p))))
(go (lambda () (open-input-bytes #"hello")) sync test test)

(define (sync/poll . args) (apply sync/timeout 0 args))
(go (lambda () (open-input-bytes #"hello")) sync/poll test test)

(define (delay-hello)
  (let-values ([(r w) (make-pipe)])
    (thread (lambda ()
	      (sleep 0.1)
	      (write-string "hello" w)
	      (close-output-port w)))
    r))
(go delay-hello sync test test)

(go (lambda ()
      (let-values ([(r w) (make-pipe)])
	r))
    sync/poll 
    (lambda args
      (apply test #f (cdr args)))
    (lambda args
      (apply test (if (string? (car args))
		      (make-string (string-length (car args)))
		      (make-bytes (bytes-length (car args))))
	     (cdr args))))


;; extra checks for read-line-evt:
(let ([p (open-input-string "ab\nc")])
  (test "ab" sync (read-line-evt p))
  (test "c" sync (read-line-evt p))
  (test eof sync (read-line-evt p)))
(let ([p (open-input-string "ab\nc")])
  (test "ab\nc" sync (read-line-evt p 'return))
  (test eof sync (read-line-evt p 'return)))
(let ([p (open-input-string "ab\r\nc\r")])
  (test "ab" sync (read-line-evt p 'return))
  (test "\nc" sync (read-line-evt p 'return))
  (test eof sync (read-line-evt p 'return)))
(let ([p (open-input-string "ab\r\nc\r")])
  (test "ab" sync (read-line-evt p 'return-linefeed))
  (test "c\r" sync (read-line-evt p 'return-linefeed))
  (test eof sync (read-line-evt p 'return-linefeed)))
(let ([p (open-input-string "ab\r\nc\r")])
  (test "ab" sync (read-line-evt p 'any))
  (test "c" sync (read-line-evt p 'any))
  (test eof sync (read-line-evt p 'any)))
(let ([p (open-input-string "ab\r\nc\r")])
  (test "ab" sync (read-line-evt p 'any-one))
  (test "" sync (read-line-evt p 'any-one))
  (test "c" sync (read-line-evt p 'any-one))
  (test eof sync (read-line-evt p 'any-one)))

;; input-port-append tests
(let* ([do-test
	;; ls is a list of strings for ports
	;;  n, m, q are positive
	;;  n and n+m < total length
	;;  n+m+q can be greater than total length
	(lambda (ls n m q)
	  (let* ([p (apply input-port-append #f (map open-input-string ls))]
		 [s (apply string-append ls)]
		 [l (string-length s)])
	    (test (substring s 0 n) peek-string n 0 p)
	    (test (substring s n (min l (+ n m q))) peek-string (+ m q) n p)
	    (test (substring s (+ n m) (min l (+ n m q))) peek-string q (+ n m) p)

	    (test (substring s 0 n) read-string n p)
	    
	    (test (substring s n (+ n m)) peek-string m 0 p)
	    (test (substring s (+ n m) (min l (+ n m q))) peek-string q m p)

	    (test (substring s n (+ n m)) read-string m p)

	    (test (substring s (+ n m) (min l (+ n m q))) peek-string q 0 p)))]
       [do-tests
	(lambda (ls)
	  (let ([l (apply + (map string-length ls))])
	    (let loop ([n 1])
	      (unless (= n (- l 2))
		(let loop ([m 1])
		  (unless (= (+ m n) (- l 1))
		    (do-test ls n m 1)
		    (do-test ls n m (- l n m))
		    (do-test ls n m (+ (- l n m) 2))
		    (loop (add1 m))))
		(loop (add1 n))))))])
  (do-tests '("apple" "banana"))
  (do-tests '("ax" "b" "cz")))
;; input-port-append and not-ready inputs
(let ([p0 (open-input-bytes #"123")])
  (let-values ([(p1 out) (make-pipe)])
    (let ([p (input-port-append #f p0 p1)])
      (display "4" out)
      (test #"1234" peek-bytes 4 0 p)
      (test #"34" peek-bytes 2 2 p)
      (test #"4" peek-bytes 1 3 p)
      (let* ([v #f]
	     [t (thread (lambda ()
			  (set! v (read-bytes 6 p))))])
	(test #f sync/timeout SLEEP-TIME t)
	(display "56" out)
	(test t sync/timeout SLEEP-TIME t)
	(test #"123456" values v)))))

;; make-limited-input-port tests
(let* ([s (open-input-string "123456789")]
       [s2 (make-limited-input-port s 5)])
  (test #"123" peek-bytes 3 0 s2)
  (test #"12345" peek-bytes 6 0 s2)
  (test #"12" read-bytes 2 s2)
  (test #"345" read-bytes 6 s2)
  (test eof read-bytes 6 s2)
  (test #f port-provides-progress-evts? s2))
(let-values ([(i o) (make-pipe)])
  (let ([s (make-limited-input-port i 5)])
    (test #f char-ready? s)
    (display "123" o)
    (test #t char-ready? s)
    (let ([b (make-bytes 10)])
      (test 3 peek-bytes-avail!* b 0 #f s)
      (test 3 read-bytes-avail!* b s)
      (test 0 peek-bytes-avail!* b 0 #f s)
      (display "456" o)
      (test 2 peek-bytes-avail!* b 0 #f s)
      (test 1 peek-bytes-avail!* b 1 #f s)
      (test 2 read-bytes-avail!* b s))))
	     
;; ----------------------------------------
;; Conversion wrappers

(define (try-eip-seq encoding bytes try-map)
  (let* ([p (open-input-bytes bytes)]
	 [p2 (reencode-input-port p encoding #".!")])
    (for-each (lambda (one-try)
		(let ([p (if (car one-try)
			     p2
			     p)]
		      [len (cadr one-try)]
		      [expect (caddr one-try)])
		  (test expect read-bytes len p)))
	      try-map)))

(try-eip-seq "UTF-8" #"apple" `((#t 3 #"app") (#f 2 #"le") (#t 4 ,eof)))
(try-eip-seq "UTF-8" #"ap\303\251ple" `((#t 3 #"ap\303") (#f 2 #"pl") (#t 4 #"\251e") (#t 5 ,eof)))
(try-eip-seq "ISO-8859-1" #"ap\303\251ple" `((#t 3 #"ap\303") (#f 2 #"\251p") (#t 4 #"\203le") (#t 5 ,eof)))
(try-eip-seq "UTF-8" #"ap\251ple" `((#t 2 #"ap") (#f 2 #"\251p") (#t 4 #"le") (#t 5 ,eof)))
(try-eip-seq "UTF-8" #"ap\251ple" `((#t 3 #"ap.") (#f 1 #"p") (#t 4 #"!le") (#t 5 ,eof)))
(try-eip-seq "UTF-8" #"ap\251ple" `((#t 4 #"ap.!") (#f 1 #"l") (#t 4 #"pe") (#t 5 ,eof)))

(let-values ([(in out) (make-pipe-with-specials)])
  (display "ok" out)
  (write-special 'special! out)
  (display "yz" out)
  (let ([p (reencode-input-port in "UTF-8")])
    (test #"ok" read-bytes 2 p)
    (test 'special! read-byte-or-special p)
    (test #"yz" read-bytes 2 p)
    (close-output-port out)
    (test eof read-bytes 3 p)))

(let*-values ([(r w) (make-pipe 10)]
	      [(w2) (reencode-output-port w "UTF-8" #"!?")])
  (test 4 write-bytes #"abcd" w2)
  (flush-output w2)
  (test #"abcd" read-bytes 4 r)
  
  (test 3 write-bytes #"abc" w2)
  (test 0 read-bytes-avail!* (make-bytes 10) r)
  (test 1 write-bytes-avail #"wx" w2)
  (test #"abcw" read-bytes 4 r)

  ;; Check encoding error
  (test 4 write-bytes #"ab\303x" w2)
  (flush-output w2)
  (test #"ab!?x" read-bytes 5 r)

  ;; Check flushing in middle of encoding:
  (test 3 write-bytes #"ab\303" w2)
  (test 0 read-bytes-avail!* (make-bytes 10) r)
  (test 1 write-bytes-avail #"\251x" w2)
  (test #"ab\303\251" read-bytes 4 r)
  (test 1 write-bytes-avail #"abc" w2)
  (test #"a" read-bytes 1 r)

  ;; Check blocking on full pipe:
  (test 10 write-bytes #"1234567890" w2)
  (flush-output w2)
  (test #f sync/timeout 0.0 w)
  (test #f sync/timeout 0.0 w2)
  (test 0 write-bytes-avail* #"123" w2)
  (test 0 write-bytes-avail* #"123" w2)
  (test 0 write-bytes-avail* #"123" w2)
  (test #"1234567890" read-bytes 10 r)
  (test w2 sync/timeout 0.0 w2)
  (test 1 write-bytes-avail #"123" w2)

  ;; Check specials:
  (let*-values ([(in out) (make-pipe-with-specials)]
		[(out2) (reencode-output-port out "UTF-8" #"!")])
    (test 3 write-bytes #"123" out2)
    (test #t write-special 'spec out2)
    (test 3 write-bytes #"456" out2)
    (flush-output out2)
    (test #"123" read-bytes 3 in)
    (test 'spec read-char-or-special in)
    (test #"456" read-bytes 3 in))

  (void))

;; Check buffer modes:
(let ([i (open-input-string "abc")]
      [o (open-output-string)])
  (test #f file-stream-buffer-mode i)
  (test #f file-stream-buffer-mode o)
  (let ([ei (reencode-input-port i "UTF-8")]
	[eo (reencode-output-port o "UTF-8")])
    (test 'none file-stream-buffer-mode ei)
    (test 'block file-stream-buffer-mode eo)

    (test (void) display 10 eo)
    (test (void) display 12 eo)
    (test (void) newline eo)
    (test #"" get-output-bytes o)
    (test (void) flush-output eo)
    (test #"1012\n" get-output-bytes o)
    
    (test (void) file-stream-buffer-mode eo 'line)
    (test 'line file-stream-buffer-mode eo)
    (test (void) display 13 eo)
    (test #"1012\n" get-output-bytes o)
    (test (void) newline eo)
    (test #"1012\n13\n" get-output-bytes o)
    (test (void) flush-output eo)
    (test #"1012\n13\n" get-output-bytes o)

    (test (void) display 14 eo)
    (test #"1012\n13\n" get-output-bytes o)
    (test (void) file-stream-buffer-mode eo 'none)
    (test #"1012\n13\n14" get-output-bytes o)
    (test 'none file-stream-buffer-mode eo)
    (test (void) display 15 eo)
    (test #"1012\n13\n1415" get-output-bytes o)

    (test #\a read-char ei)
    (test #\b peek-char i)
    (test (void) file-stream-buffer-mode ei 'block)
    (test 'block file-stream-buffer-mode ei)
    (test #\b read-char ei)
    (test eof peek-char i)
    (test #\c read-char ei)
    (test eof read-char ei)))

;; --------------------------------------------------

(report-errs)
