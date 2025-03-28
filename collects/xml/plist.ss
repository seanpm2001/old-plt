(module plist mzscheme

  (require "xml.ss"
           (lib "contract.ss"))

  (provide read-plist)
  (provide/contract [write-plist (xexpr? output-port? . -> . void?)])
  
   ; a dict is (list 'dict assoc-pair ...)
   ; an assoc-pair is (list 'assoc-pair key value)
   ; a key is a string
   ; a value is either: 
   ;  a string,
   ;  a boolean, 
   ;  an integer : (list 'integer number)
   ;  a real : (list 'real number)
   ;  a dict, or
   ;  an array : (list 'array value ...)
   ; (we're ignoring data & date)


   ; raise-plist-exn : string mark-set xexpr symbol -> ???
   (define (raise-plist-exn tag mark-set xexpr type)
     (raise (make-exn:fail:contract (string-append "badly formed '" tag "'")
				    mark-set)))

   ; expand-dict : xexpr -> xexpr
   (define (expand-dict x)
     (cond [(and (eq? (car x) 'dict)
		 (map expand-assoc-pair (cdr x)))
	    =>
	    (lambda (x) `(dict ,@(apply append x)))]
	   [else
	    (raise-plist-exn "dict" (current-continuation-marks) x 'plist:dict)]))

   ; expand-assoc-pair : xexpr -> (list xexpr xexpr)
   (define (expand-assoc-pair x)
     (cond [(and (eq? (car x) 'assoc-pair)
		 (string? (cadr x))
		 (expand-value (caddr x)))
	    =>
	    (lambda (z) `((key ,(cadr x))
			  ,z))]
	   [else
	    (raise-plist-exn "assoc-pair" (current-continuation-marks) x 'plist:assoc-pair)]))

   ; expand-value : xexpr -> xexpr
   (define (expand-value x)
     (cond [(string? x)
	    `(string ,x)]
	   [(or (equal? x '(true))
		(equal? x '(false)))
	    x]
	   [(and (eq? (car x) 'integer)
		 (expand-integer x))
	    => 
	    (lambda (x) x)]
	   [(and (eq? (car x) 'real)
		 (expand-real x))
	    =>
	    (lambda (x) x)]
	   [(and (eq? (car x) 'dict)
		 (expand-dict x))
	    =>
	    (lambda (x) x)]
	   [(and (eq? (car x) 'array)
		 (expand-array x))
	    =>
	    (lambda (x) x)]
	   [else
	    (raise-plist-exn "value" (current-continuation-marks) x 'plist:value)]))

   ; expand-real : xexpr -> xexpr
   (define (expand-real x)
     (cond [(and (eq? (car x) 'real)
		 (real? (cadr x)))
	    `(real ,(number->string (cadr x)))]
	   [else
	    (raise-plist-exn "real" (current-continuation-marks) x 'plist:real)]))

   ; expand-integer : xexpr -> xexpr
   (define (expand-integer x)
     (cond [(and (eq? (car x) 'integer)
		 (integer? (cadr x)))
	    `(integer ,(number->string (cadr x)))]
	   [else
	    (raise-plist-exn "integer" (current-continuation-marks) x 'plist:integer)]))

   ; expand-array : xexpr -> xexpr
   (define (expand-array x)
     (cond [(and (eq? (car x) 'array)
		 (map expand-value (cdr x)))
	    =>
	    (lambda (x)
	      `(array ,@x))]
	   [else
	    (raise-plist-exn "array" (current-continuation-marks) x 'plist:array)]))

   ; dict? tst -> boolean
   (define (dict? x)
     (with-handlers [(exn:fail:contract? (lambda (exn) #f))]
       (expand-dict x)
       #t))

   ; write-plist : xexpr port -> (void)
   (define (write-plist xexpr port)
     (let ([plist-xexpr `(plist ,(expand-dict xexpr))])
       (write-xml 
	(make-document (make-prolog (list (make-pi #f #f 'xml "version=\"1.0\" encoding=\"UTF-8\"")) 
				    (make-document-type 'plist
							(if (eq? (system-type) 'macosx)
							    (make-external-dtd/system 
							     "file://localhost/System/Library/DTDs/PropertyList.dtd")
							    #f)
							#f))
		       (xexpr->xml `(plist ((version "0.9"))
					   ,(expand-dict xexpr)))
		       null)
	port)))


   ; collapse-dict : xexpr -> dict
   (define (collapse-dict x)
     `(dict ,@(collapse-assoc-pairs (cdr x))))

   ; collapse-assoc-pairs : (listof xexpr) -> (listof assoc-pairs)
   (define (collapse-assoc-pairs args)
     (if (null? args)
	 null
	 (let ([key (car args)]
	       [value (cadr args)]
	       [rest (cddr args)])
	   (cons `(assoc-pair ,(cadr key) ,(collapse-value value))
		 (collapse-assoc-pairs rest)))))

   ; collapse-value : xexpr -> value
   (define (collapse-value value)
     (case (car value)
       [(string) (cadr value)]
       [(true false) value]
       [(integer real) (list (car value) (string->number (cadr value)))]
       [(dict) (collapse-dict value)]
       [(array) (collapse-array value)]))

   ; collapse-array : xexpr -> array
   (define (collapse-array xexpr)
     `(array ,@(map collapse-value (cdr xexpr))))

   (define tags-without-whitespace
     '(plist dict array))

   ; read-plist : port -> dict
   (define (read-plist port)
     (let* ([xml-doc (read-xml port)]
	    [content (parameterize ([xexpr-drop-empty-attributes #t])
		       (xml->xexpr
			((eliminate-whitespace tags-without-whitespace (lambda (x) x))
			 (document-element xml-doc))))])
       (unless (eq? (car content) 'plist)
	       (error 'read-plist "xml expression is not a plist: ~a" content))
       (collapse-dict (caddr content))))

   ;; TEST

   '(define my-dict
     `(dict (assoc-pair "first-key"
			"just a string
                         with some whitespace in it")
	    (assoc-pair "second-key"
			(false))
	    (assoc-pair "third-key"
			(dict ))
	    (assoc-pair "fourth-key"
			(dict (assoc-pair "inner-key"
					  (real 3.432))))
	    (assoc-pair "fifth-key"
			(array (integer 14)
			       "another string"
			       (true)))
	    (assoc-pair "sixth-key"
			(array))))

   '(call-with-output-file "/Users/clements/tmp.plist"
     (lambda (port)
       (write-plist my-dict port))
     'truncate)

   '(define new-dict
     (call-with-input-file "/Users/clements/tmp.plist"
       (lambda (port)
	 (read-plist port))))

   '(equal? new-dict my-dict)

   ;; END OF TEST
	 
)		 
		 
	    
		   
