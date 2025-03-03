
(module teachprims mzscheme

  (require "../imageeq.ss" 
           (lib "list.ss"))
  
  (define-syntax (define-teach stx)
    (syntax-case stx ()
      [(_ level id expr)
       (with-syntax ([level-id (datum->syntax-object
				(syntax id)
				(string->symbol
				 (format "~a-~a"
					 (syntax-object->datum (syntax level))
					 (syntax-object->datum (syntax id))))
				(syntax id))])
	 (syntax (define level-id
		   (let ([id expr])
		     id))))]))

  (define-teach beginner list?
    (lambda (x)
      (or (null? x) (pair? x))))
		    
  ;; Don't need this anymore, since we just check for pairs:
  #;
  (define cyclic-list?
    (lambda (l)
       (or (list? l)
	   (and (pair? l)
		(let loop ([hare (cdr l)][turtle l])
		  (cond
		   [(eq? hare turtle) #t]
		   [(not (pair? hare)) #f]
		   [(eq? (cdr hare) turtle) #t]
		   [(not (pair? (cdr hare))) #f]
		   [else (loop (cddr hare) (cdr turtle))]))))))

  (define cyclic-list? beginner-list?)

  (define (build-arg-list args)
    (let loop ([args args][n 0])
      (cond
       [(null? args) ""]
       [(= n 5) " ..."]
       [else
	(format " ~e~a" (car args) (loop (cdr args) (add1 n)))])))

  (define (mk-check-second ok? type)
    (lambda (prim-name a b)
      (unless (ok? b)
	(raise
	 (make-exn:fail:contract
	  (string->immutable-string
	   (format "~a: second argument must be of type <~a>, given ~e and ~e"
		   prim-name type
		   a b))
	  (current-continuation-marks))))))

  (define check-second 
    (mk-check-second beginner-list? "list"))

  (define check-second/cycle
    (mk-check-second cyclic-list? "list or cyclic list"))

  (define (mk-check-last ok? type)
    (lambda (prim-name args)
      (let loop ([l args])
	(cond
	 [(null? l) (void)]
	 [(null? (cdr l))
	  (let ([last (car l)])
	    (unless (ok? last)
	      (raise
	       (make-exn:fail:contract
		(string->immutable-string
		 (format "~a: last argument must be of type <~a>, given ~e; other args:~a"
			 prim-name type
			 last
			 (build-arg-list
			  (let loop ([args args])
			    (cond
			     [(null? (cdr args)) null]
			     [else (cons (car args) (loop (cdr args)))])))))
		(current-continuation-marks)))))]
	 [else (loop (cdr l))]))))

  (define check-last 
    (mk-check-last beginner-list? "list"))

  (define check-last/cycle
    (mk-check-last cyclic-list? "list or cyclic list"))

  (define (check-three a b c prim-name ok1? 1type ok2? 2type ok3? 3type)
    (let ([bad
	   (lambda (v which type)
	     (raise
	      (make-exn:fail:contract
	       (string->immutable-string
		(format "~a: ~a argument must be of type <~a>, given ~e, ~e, and ~e"
			prim-name which type
			a b c))
	       (current-continuation-marks))))])
      (unless (ok1? a)
	(bad a "first" 1type))
      (unless (ok2? b)
	(bad b "second" 2type))
      (unless (ok3? c)
	(bad c "second" 3type))))

  (define (positive-real? v)
    (and (real? v) (>= v 0)))

  (define-teach beginner not
    (lambda (a)
      (unless (boolean? a)
	(raise
	 (make-exn:fail:contract
	  (string->immutable-string
	   (format "not: expected either true or false; given ~e"
		   a))
	  (current-continuation-marks))))
      (not a)))

  (define-teach beginner +
    (lambda (a b . args)
      (apply + a b args)))

  (define-teach beginner /
    (lambda (a b . args)
      (apply / a b args)))
  
  (define-teach beginner *
    (lambda (a b . args)
      (apply * a b args)))
  
  (define-teach beginner member 
    (lambda (a b)
      (check-second 'member a b)
      (not (boolean? (member a b)))))

  (define-teach beginner cons 
    (lambda (a b)
      (check-second 'cons a b)
      (cons a b)))
  
  (define-teach beginner list*
    (lambda x
      (check-last 'list* x)
      (apply list* x)))
  
  (define-teach beginner append
    (lambda x
      (check-last 'append x)
      (apply append x)))
  
  (define-teach beginner error
    (lambda (sym str)
      (unless (and (symbol? sym)
		   (string? str))
	(raise
	 (make-exn:fail:contract
	  (string->immutable-string
	   (format "error: expected a symbol and a string, got ~e and ~e"
		   sym str))
	  (current-continuation-marks))))
      (error sym "~a" str)))

  (define-teach beginner struct?
    (lambda (x)
      (not (or (number? x)
	       (boolean? x)
	       (pair? x)
	       (symbol? x)
	       (string? x)
	       (procedure? x)
	       (vector? x)
	       (char? x)
	       (port? x)
	       (eof-object? x)
	       (void? x)))))

  (define-teach beginner exit
    (lambda () (exit)))
  
  ;; This equality predicate doesn't handle hash tables.
  ;; (It could, but there are no hash tables in the teaching
  ;;  languages.)
  (define (tequal? a b epsilon)
    (let ? ([a a][b b])
      (or (equal? a b)
	  (cond
	   [(box? a)
	    (and (box? b)
		 (? (unbox a) (unbox b)))]
	   [(pair? a)
	    (and (pair? b)
		 (? (car a) (car b))
		 (? (cdr a) (cdr b)))]
	   [(vector? a)
	    (and (vector? b)
		 (= (vector-length a) (vector-length b))
		 (andmap ?
			 (vector->list a)
			 (vector->list b)))]
	   [(image? a)
	    (and (image? b)
		 (image=? a b))]
	   [(real? a)
	    (and epsilon
		 (real? b)
		 (beginner-=~ a b epsilon))]
	   [(struct? a)
	    (and (struct? b)
		 (let-values ([(ta sa?) (struct-info a)]
			      [(tb sb?) (struct-info b)])
		   (and (not sa?)
			(not sb?)
			(eq? ta tb)
			(? (struct->vector a)
			   (struct->vector b)))))]
	   [(hash-table? a)
	    (and (hash-table? b)
		 (eq? (immutable? a) (immutable? b))
		 (eq? (hash-table? a 'weak) (hash-table? b 'weak))
		 (eq? (hash-table? a 'equal) (hash-table? b 'equal))
		 (let ([al (hash-table-map a cons)]
		       [bl (hash-table-map b cons)])
		   (and (= (length al) (length bl))
			(for-each 
			 (lambda (ai)
			   (? (hash-table-get b (car ai) (lambda () (not (cdr ai))))
			      (cdr ai)))
			 al))))]
	   [else #f]))))

  (define-teach beginner equal?
    (lambda (a b)
      (tequal? a b #f)))

  (define-teach beginner =~
    (lambda (a b c)
      (check-three a b c '=~ real? 'real real? 'real positive-real? 'non-negative-real)
      (<= (- a c) b (+ a c))))

  (define-teach beginner equal~?
    (lambda (a b c)
      (check-three a b c 'equal~? values 'any values 'any positive-real? 'non-negative-real)
      (tequal? a b c)))

  (define (qcheck fmt-str x)
    (raise
     (make-exn:fail:contract
      (string->immutable-string
       (string-append "quicksort: " (format fmt-str x)))
      (current-continuation-marks))))
    
  (define-teach intermediate quicksort
    (lambda (l cmp?)
      (unless (beginner-list? l) 
        (qcheck "first argument must be of type <list>, given ~e" l))
      (unless (and (procedure? cmp?) (procedure-arity-includes? cmp? 2))
        (qcheck "second argument must be a <procedure> that accepts two arguments, given ~e" cmp?))
      (quicksort l (lambda (x y) 
                     (define r (cmp? x y))
                     (unless (boolean? r)
                       (qcheck "the results of the procedure argument must be of type <boolean>, produced ~e" r))
                     r))))
  
  (define-teach advanced cons 
    (lambda (a b)
      (check-second/cycle 'cons a b)
      (cons a b)))
  
  (define-teach advanced set-cdr!
    (lambda (a b)
      (check-second/cycle 'set-cdr! a b)
      (set-cdr! a b)))
  
  (define-teach advanced set-rest!
    (lambda (a b)
      (check-second/cycle 'set-rest! a b)
      (set-cdr! a b)))
  
  (define-teach advanced list*
    (lambda x
      (check-last/cycle 'list* x)
      (apply list* x)))
  
  (define-teach advanced append
    (lambda x
      (check-last/cycle 'append x)
      (apply append x)))
  
  (define-teach advanced append!
    (lambda x
      (check-last/cycle 'append! x)
      (apply append! x)))

  (provide beginner-not
	   beginner-+
	   beginner-/
	   beginner-*
	   beginner-list?
           beginner-member
	   beginner-cons
	   beginner-list*
	   beginner-append
	   beginner-error
	   beginner-struct?
	   beginner-exit
	   beginner-equal?
	   beginner-equal~?
	   beginner-=~
           intermediate-quicksort
	   advanced-cons
	   advanced-set-cdr!
	   advanced-set-rest!
	   advanced-list*
	   advanced-append
	   advanced-append!
	   cyclic-list?))
