
(module moddep mzscheme
  (require (lib "etc.ss")
           (lib "resolver.ss" "planet"))
  

  (provide moddep-current-open-input-file)
  (define moddep-current-open-input-file
    (make-parameter open-input-file))
  
  (provide with-module-reading-parameterization)
  (define (with-module-reading-parameterization thunk)
    (parameterize ((read-case-sensitive #t)
		   (read-square-bracket-as-paren #t)
		   (read-curly-brace-as-paren #t)
		   (read-accept-box #t)
		   (read-accept-compiled #t)
		   (read-accept-bar-quote #t)
		   (read-accept-graph #t)
		   (read-decimal-as-inexact #t)
		   (read-accept-dot #t)
		   (read-accept-quasiquote #t)
		   (read-accept-reader #t)
		   (current-readtable #f))
      (thunk)))

  (define (raise-wrong-module-name filename expected-name name)
    (raise
     (make-exn:fail
      (string->immutable-string
       (format
	"load-handler: expected a `module' declaration for `~a' in ~s, found: ~a"
	expected-name filename name))
      (current-continuation-marks))))
  
  (define (check-module-form exp expected-module filename)
    (cond
     [(or (eof-object? exp)
	  (eof-object? (syntax-e exp)))
      (and filename
	   (raise
	    (make-exn:fail
	     (string->immutable-string
	      (format
	       "load-handler: expected a `module' declaration for `~a' in ~s, but found end-of-file"
	       expected-module filename))
	     (current-continuation-marks))))]
     [(compiled-module-expression? (syntax-e exp))
      (if (eq? (module-compiled-name (syntax-e exp))
	       expected-module)
	  ;; It's fine:
	  exp
	  ;; Wrong name:
	  (and filename
	       (raise-wrong-module-name filename expected-module 
                                        (module-compiled-name (syntax-e exp)))))]
     [(and (syntax? exp)
	   (syntax-case exp ()
	     [(mod nm . _)
	      (and (eq? (syntax-e (syntax mod)) 'module)
		   (identifier? (syntax nm)))]
	     [_else #f]))
      ;; It's ok; need to install a specific `module' binding:
      (with-syntax ([(mod nm . _) exp])
        (unless (eq? (syntax-e (syntax nm)) expected-module)
          (raise-wrong-module-name filename expected-module (syntax-e (syntax nm))))
	(datum->syntax-object exp
			      (cons (syntax module)
				    (cdr (syntax-e exp)))
			      exp
			      exp))]
     [else
      (and filename
	   (raise
	    (make-exn:fail
	     (string->immutable-string
	      (format
	       "load-handler: expected a `module' declaration for `~a' in ~s, but found something else"
	       expected-module filename))
	     (current-continuation-marks))))]))
  
  (define re:suffix #rx#"\\..*$")
	  
  (define (resolve s)
    (if (complete-path? s)
	s
	(let ([d (current-load-relative-directory)])
	  (if d (path->complete-path s d) s))))
  
  (define (date>=? a bm)
    (and a
	 (let ([am (with-handlers ([exn:fail:filesystem? (lambda (x) #f)])
		     (file-or-directory-modify-seconds a))])
	   (or (and (not bm) am) (and am bm (>= am bm))))))

  (define (read-one path src?)
    (let ([p ((moddep-current-open-input-file) path)])
      (when src? (port-count-lines! p))
      (dynamic-wind
       void
       (lambda ()
	 (let ([v (with-module-reading-parameterization
		   (lambda ()
		     (read-syntax path p)))])
	   (when (eof-object? v)
	     (error 'read-one "empty file; expected a module declaration in: ~a" path))
	   (let ([name (let-values ([(base name dir?) (split-path path)])
			 (string->symbol (bytes->string/utf-8
					  (path->bytes (path-replace-suffix  name #""))
					  #\?)))])
	     (check-module-form v name path))
	   (unless (eof-object? (read p))
	     (error 
	      'read-one
	      "file has more than one expression; expected a module declaration only in: ~a"
	      path))
	   (if (and (syntax? v)
		    (compiled-expression? (syntax-e v)))
	       (syntax-e v)
	       v)))
       (lambda () (close-input-port p)))))
  
  (define-struct (exn:get-module-code exn) (path))

  (define get-module-code
    (opt-lambda (path [sub-path "compiled"] [compiler compile] [extension-handler #f])
      (unless (path-string? path) 
	(raise-type-error 'get-module-code "path or string (sans nul)" path))
      (let*-values ([(path) (resolve path)]
		    [(base file dir?) (split-path path)]
		    [(base) (if (eq? base 'relative) 'same base)]
		    [(mode) (use-compiled-file-paths)])
	(let* ([get-so (lambda (file)
			 (build-path base
				     sub-path
				     "native"
				     (system-library-subpath)
				     (path-replace-suffix
				      file
				      (case (system-type)
					[(windows) #".dll"]
					[else #".so"]))))]
	       [zo (build-path base
			       sub-path
			       (path-replace-suffix file #".zo"))]
	       [so (get-so file)]
	       [_loader-so (get-so (string->path "_loader.ss"))]
	       [path-d (with-handlers ([exn:fail:filesystem? (lambda (x) #f)])
			 (file-or-directory-modify-seconds path))]
	       [with-dir (lambda (t) 
			   (parameterize ([current-load-relative-directory 
					   (if (path? base) 
					       base 
					       (current-directory))])
			     (t)))])
	  (cond
	   ;; Use .zo, if it's new enough
	   [(date>=? zo path-d)
	    (read-one zo #f)]
	   ;; Otherwise, use source if it exists
	   [path-d 
            (with-dir (lambda () (compiler (read-one path #t))))]
	   ;; No source --- maybe there's an .so?
	   [(and (not path-d)
		 (date>=? so path-d))
	    (if extension-handler
		(extension-handler so #f)
		(raise (make-exn:get-module-code 
			(string->immutable-string
			 (format "get-module-code: cannot use extension file; ~e" so))
			(current-continuation-marks)
			so)))]
	   ;; Or maybe even a _loader.so?
	   [(and (not path-d)
		 (date>=? _loader-so path-d)
		 (let ([getter (load-extension _loader-so)])
		   (let-values ([(loader modname) (getter (string->symbol 
							   (bytes->string/latin-1
							    (path->bytes
							     (path-replace-suffix file #"")))))])
		     loader)))
	    => (lambda (loader)
		 (if extension-handler
		     (extension-handler loader #t)
		     (raise (make-exn:get-module-code 
			     (string->immutable-string
			      (format "get-module-code: cannot use _loader file: ~e"
				      _loader-so))
			     (current-continuation-marks)
			     loader))))]
	   ;; Report a not-there error
	   [else
	    (raise (make-exn:get-module-code 
		    (string->immutable-string (format "get-module-code: no such file: ~e" path))
		    (current-continuation-marks)
		    #f))])))))

  (define re:dir #rx#"(.+?)/+(.*)")

  (define (force-relto relto dir?)
    (cond
     [(path-string? relto)
      (if dir?
	  (let-values ([(base n d?) (split-path relto)])
	    (if (eq? base 'relative)
		(or (current-load-relative-directory)
		    (current-directory))
		base))
	  relto)]
     [(pair? relto) relto]
     [(not dir?)
      (error 'resolve-module-path-index "can't resolve \"self\" with just a relative directory ~e" relto)]
     [(procedure? relto) (relto)]
     [else
      (current-directory)]))

  (define resolve-module-path
    ;; relto should be a complete path, #f, or procedure that returns a complete path
    (lambda (s relto)
      (let ([get-dir (lambda () (force-relto relto #t))])
	(cond
	 [(string? s)
	  ;; Parse Unix-style relative path string
	  (let loop ([path (get-dir)][s (if (path? s)
					    (path->bytes s)
					    (string->bytes/utf-8 s))])
	    (let ([prefix (regexp-match re:dir s)])
	      (if prefix
		  (loop (build-path path 
				    (let ([p (cadr prefix)])
				      (cond
				       [(bytes=? p #".") 'same]
				       [(bytes=? p #"..") 'up]
				       [else (bytes->path p)])))
			(caddr prefix))
		  (build-path path (bytes->path s)))))]
	 [(and (or (not (pair? s))
		   (not (list? s)))
	       (not (path? s)))
	  #f]
	 [(or (path? s)
	      (eq? (car s) 'file))
	  (let ([p (if (path? s)
		       s
		       (cadr s))])
	    (path->complete-path p (let ([d (get-dir)])
				     (if (path-string? d)
					 d
					 (or (current-load-relative-directory)
					     (current-directory))))))]
	 [(eq? (car s) 'lib)
	  (let ([cols (let ([len (length s)])
			(if (= len 2)
			    (list "mzlib")
			    (cddr s)))])
	    (let ([p (apply collection-path cols)])
	      (build-path p (cadr s))))]
         [(eq? (car s) 'planet)
          (let ((module-id
                 (cond
                   [(path? relto)
                    (string->symbol (string-append "," (path->string (path->complete-path relto))))]
                   [else #f])))
            (let-values ([(path pkg) (get-planet-module-path/pkg s module-id #f)])
              path))]
	 [else #f]))))

  (define (resolve-module-path-index mpi relto)
    ;; relto must be a complete path
    (let-values ([(path base) (module-path-index-split mpi)])
      (if path
	  (resolve-module-path path (resolve-possible-module-path-index base relto))
	  (force-relto relto #f))))

  (define (resolve-possible-module-path-index base relto)
    (cond
     [(module-path-index? base)
      (resolve-module-path-index base relto)]
     [(symbol? base)
      (let ([s (symbol->string base)])
	(if (and ((string-length s) . > . 0)
		 (char=? #\, (string-ref s 0)))
	    (substring s 1 (string-length s))
	    relto))]
     [relto (if (procedure? relto)
		(relto)
		relto)]
     [else #f]))

  (define re:path-only #rx#"^(.*)/[^/]*$")

  (define collapse-module-path
    ;; relto-mp should be a relative path, '(lib relative-path collection), or '(file path)
    ;;          of a thunk that produces one of those
    (lambda (s relto-mp)
      (let ([combine-relative-elements
	     (lambda (elements)
	       (when (procedure? relto-mp)
		 (set! relto-mp (relto-mp)))
	       (cond
		[(path-string? relto-mp)
		 (bytes->string/locale
		  (apply
		   bytes-append
		   (let ([m (regexp-match re:path-only (if (path? relto-mp)
							   (path->bytes relto-mp)
							   (string->bytes/locale relto-mp)))])
		     (if m
			 (cadr m)
			 #"."))
		   (map (lambda (e)
			  (cond
			   [(eq? e 'same) #"/."]
			   [(eq? e 'up) #"/.."]
			   [else (bytes-append #"/" (if (path? e)
							(path->bytes e)
							e))]))
			elements)))]
		[else (let ([path (path->string
				   (apply build-path
					  (let-values ([(base n d?) (split-path (cadr relto-mp))])
					    (if (eq? base 'relative)
						'same
						base))
					  (map (lambda (i)
						 (cond
						  [(bytes? i) (bytes->path i)]
						  [else i]))
					       elements)))])
			(if (eq? (car relto-mp) 'lib)
			    `(lib ,path ,(caddr relto-mp))
			    `(file ,path)))]))])
	(cond
	 [(string? s)
	  ;; Parse Unix-style relative path string
	  (let loop ([elements null][s (string->bytes/utf-8 s)])
	    (let ([prefix (regexp-match re:dir s)])
	      (if prefix
		  (loop (cons (let ([p (cadr prefix)])
				(cond
				 [(bytes=? p #".") 'same]
				 [(bytes=? p #"..") 'up]
				 [else (bytes->path p)]))
			      elements)
			(caddr prefix))
		  (combine-relative-elements 
		   (reverse (cons s elements))))))]
	 [(and (or (not (pair? s))
		   (not (list? s)))
	       (not (path? s)))
	  #f]
	 [(or (path? s)
	      (eq? (car s) 'file))
	  (let ([p (if (path? s)
		       s
		       (cadr s))])
	    (if (absolute-path? p)
		s
		(let loop ([p p][elements null])
		  (let-values ([(base name dir?) (split-path p)])
		    (cond
		     [(eq? base 'relative)
		      (combine-relative-elements 
		       (cons name elements))]
		     [else (loop base (cons name elements))])))))]
	 [(eq? (car s) 'lib)
	  (let ([cols (let ([len (length s)])
			(if (= len 2)
			    (list "mzlib")
			    (cddr s)))])
	    `(lib ,(path->string
		    (build-path (if (null? (cdr cols))
				    'same
				    (apply build-path 'same (cdr cols)))
				(cadr s)))
		  ,(car cols)))]
	 [else #f]))))

  (define (collapse-module-path-index mpi relto-mp)
    (let-values ([(path base) (module-path-index-split mpi)])
      (if path
	  (collapse-module-path path 
				(cond
				 [(symbol? base)
				  (let ([s (symbol->string base)])
				    (if (and ((string-length s) . > . 0)
					     (char=? #\, (string-ref s 0)))
					`(file ,(substring s 1 (string-length s)))
					relto-mp))]
				 [(module-path-index? base)
				  (collapse-module-path-index base relto-mp)]
				 [else relto-mp]))
	  relto-mp)))

  (define (show-import-tree module-path)
    (let loop ([path (resolve-module-path module-path #f)][indent ""][fs ""])
      (printf "~a~a~a~n" indent path fs)
      (let ([code (get-module-code path)])
	(let-values ([(imports fs-imports ft-imports) (module-compiled-imports code)]
		     [(mk-loop) (lambda (fs)
				  (lambda (i)
				    (unless (symbol? i)
				      (loop (resolve-module-path-index i path)
					    (format " ~a" indent)
					    fs))))])
	  (for-each (mk-loop "") imports)
	  (for-each (mk-loop " [for-syntax]") fs-imports)
	  (for-each (mk-loop " [for-template]") ft-imports)))))

  (provide check-module-form

	   get-module-code
           exn:get-module-code
           exn:get-module-code?
           exn:get-module-code-path
           make-exn:get-module-code
           
	   resolve-module-path
	   resolve-module-path-index

	   collapse-module-path
	   collapse-module-path-index

	   show-import-tree))
