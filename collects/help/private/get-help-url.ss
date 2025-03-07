(module get-help-url mzscheme
  
  #| Library responsible for turning a path on disk into a URL the help desk can use |#
  (require (lib "file.ss")
           "internal-hp.ss"
           (lib "contract.ss")
           (lib "etc.ss"))
  
  (provide/contract (get-help-url
                     (((lambda (x)
                        (or (path? x)
                            (path-string? x))))
                      (string?)
                      . opt-> . string?)))
  
  ; given a manual path, convert to absolute Web path
  ; manual path is an anchored path to a collects/doc manual, never a servlet
  (define get-help-url
    (opt-lambda (manual-path [anchor #f])
      (let ([segments (explode-path (normalize-path manual-path))])
        (let loop ([candidates manual-path-candidates])
          (cond
            ;; shouldn't happen, unless documentation is found outside the user's addon dir
            ;; and also outside the PLT tree.
            [(null? candidates) "/cannot-find-docs.html"]
            [else
             (let ([candidate (car candidates)])
               (cond
                 [(subpath/tail (car candidate) segments)
                  =>
                  (λ (l-o-path)
                     ((cadr candidate) l-o-path anchor))]
                 [else (loop (cdr candidates))]))])))))
  
  (define manual-path-candidates '())
  (define (maybe-add-candidate candidate host)
    (with-handlers ([exn:fail? void])
      (set! manual-path-candidates
            (cons (list (explode-path (normalize-path candidate))
                        (λ (segments anchor)
                           (format "http://~a:~a~a~a"
                                   host
                                   internal-port
                                   (apply string-append (map (λ (x) (format "/~a" (path->string x))) 
                                                             segments))
                                   (if anchor
                                       (string-append "#" anchor)
                                       ""))))
                  manual-path-candidates))))
  (define stupid-internal-define-syntax1
    (maybe-add-candidate (build-path (collection-path "doc") 'up) internal-host))
  (define stupid-internal-define-syntax2
    (maybe-add-candidate (build-path (find-system-path 'addon-dir)) addon-host))
  
  (define (subpath/tail short long)
    (let loop ([short short]
               [long long])
      (cond
        [(null? short) long]
        [(null? long) #f]
        [(equal? (car short) (car long))
         (loop (cdr short) (cdr long))]
        [else #f]))))