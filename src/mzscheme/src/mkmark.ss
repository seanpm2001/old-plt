
(define re:start "^START ([a-z]+);")
(define re:end "^END ([a-z]+);")

(define re:form "^([a-zA-Z0-9_]+) {")

(define re:mark "^ mark:")
(define re:size "^ size:")
(define re:close "^}")

(define re:const-size (regexp "^[ \t]*gcBYTES_TO_WORDS[(]sizeof[(][A-Za-z0-9_]*[)][)];[ \t]*$"))

(define (upcase s)
  (list->string (map char-upcase (string->list s))))

(define (do-form name)
  (let ([read-lines
	 (lambda (re:done)
	   (let loop ()
	     (let ([l (read-line)])
	       (if (eof-object? l)
		   (error 'mkmark.ss "unexpected EOF")
		   (cond
		    [(regexp-match re:done l)
		     null]
		    [(or (regexp-match re:mark l)
			 (regexp-match re:size l))
		     (error 'mkmark.ss "unexpected label: ~a at ~a" l
			    (file-position (current-input-port)))]
		    [(regexp-match re:close l)
		     (error 'mkmark.ss "unexpected close")]
		    [else (cons l (loop))])))))]
	[print-lines (lambda (l)
		       (for-each
			(lambda (s)
			  (printf "~a~n" s))
			l))])
    (let ([prefix (read-lines re:mark)]
	  [mark (read-lines re:size)]
	  [size (read-lines re:close)])
      (printf "int ~a_SIZE(void *p) {~n" name)
      (print-lines prefix)
      (printf "  return~n")
      (print-lines size)
      (printf "}~n~n")

      (printf "int ~a_MARK(void *p) {~n" name)
      (print-lines prefix)
      (print-lines (map (lambda (s)
			  (regexp-replace* 
			   "FIXUP_ONLY[(]([^;]*;)[)]" 
			   (regexp-replace* 
			    "FIXUP_TYPED_NOW[(][^,]*," 
			    s 
			    "MARK(")
			   ""))
			mark))
      (printf "  return~n")
      (print-lines size)
      (printf "}~n~n")

      (printf "int ~a_FIXUP(void *p) {~n" name)
      (print-lines prefix)
      (print-lines (map (lambda (s)
			  (regexp-replace* 
			   "FIXUP_ONLY[(]([^;]*;)[)]" 
			   (regexp-replace* 
			    "MARK" 
			    s 
			    "FIXUP")
			   "\\1"))
			mark))
      (printf "  return~n")
      (print-lines size)
      (printf "}~n~n")

      (printf "#define ~a_IS_ATOMIC ~a~n" 
	      name
	      (if (null? mark)
		  "1" 
		  "0"))

      (printf "#define ~a_IS_CONST_SIZE ~a~n~n" 
	      name
	      (if (and (= 1 (length size))
		       (regexp-match re:const-size (car size)))
		  "1" 
		  "0")))))

(printf "/* >>>> Generated by mkmark.ss from mzmarksrc.c <<<< */~n")

(let loop ()
  (let ([l (read-line)])
    (unless (eof-object? l)
      (cond
       [(regexp-match re:start l)
	=> (lambda (m)
	     (let ([who (upcase (cadr m))])
	       (printf "#ifdef MARKS_FOR_~a_C~n" who)
	       
	       (let file-loop ()
		 (let ([l (read-line)])
		   (if (eof-object? l)
		       (error 'mkmark.ss "unexpected EOF")
		       (cond
			[(regexp-match re:end l)
			 => (lambda (m)
			      (printf "#endif  /* ~a */~n" (upcase (cadr m)))
			      (loop))]
			[(regexp-match re:form l)
			 => (lambda (m)
			      (do-form (cadr m))
			      (file-loop))]
			[else (printf "~a~n" l)
			      (file-loop)]))))))]
       [else (printf "~a~n" l)
	     (loop)]))))
