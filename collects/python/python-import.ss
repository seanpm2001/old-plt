(module python-import mzscheme
  (require (lib "list.ss")
           (lib "file.ss")
           (lib "etc.ss")
           (lib "string.ss")
           ;"compile-python.ss"
           )
  (provide python-import-from-module
           python-load-module
           python-load-module-path
           copy-namespace-bindings
           make-python-namespace ; note that make-python-namespace already calls init-...
           init-python-namespace
           ;;
           eval-python-ns
           eval-python-inner-ns
           ;;
           eval-python&copy
           eval-python
           build-module-path
           module-path->string
           toggle-python-use-cache-namespace!
           set-python-cache-namespace!
           set-python-namespace-name!
           )

  (define eval-python-ns #f)
  (define eval-python-inner-ns #f)
  
  (define (python-load-module-path path-str)
    (python-load-module (map string->symbol (regexp-split #rx"\\." path-str))))

  (define (dynamic-python-to-scheme)
;    (dynamic-require '(lib "compile-python.ss" "python") 'python-to-scheme))
    ;(my-dynamic-require (current-namespace) '(lib "compile-python.ss" "python"))
    (namespace-variable-value 'python-to-scheme))

  ; python-import-from-module: (listof (list symbol (U symbol false))) symbol ... ->
  ; import a subset of a python module's definitions into the current namespace
  (define (python-import-from-module bindings id . rest)
    (eval-python&copy (parse-module (module-path->string (build-module-path (cons id rest))))
                      (make-python-namespace)
                      bindings)
    (void))



  ; python-load-module: (listof symbol) [(listof symbol)] -> (values namespace symbol string)
  (define python-load-module
    (opt-lambda (id-list [parent-id-list null])
      (let* ([path (build-module-path (list (car id-list)))]
             [module (or (*lookup-loaded-module* path)
                         (let* ([absolute-id-list (reverse (cons (car id-list)
                                                                 (reverse parent-id-list)))]
                                [name #cs(string->symbol
                                          (symbol-list->dotted-string absolute-id-list))]
                                [ns (make-python-namespace name)]
                                [module (make-loaded-module ns name path)])
                           (set-python-namespace-name! ns (loaded-module-name module))
                           (*add-loaded-module* module)
                           (eval-python (parse-module (module-path->string path)) ns)
                           ;;;; now that we loaded the "a" part of "a.b.c.d", load "b" inside "a", and so on
                           (unless (null? (cdr id-list))
                             (parameterize ([current-namespace ns]
                                            [current-directory (module-path-dir-string path)])
                               (let ([primitives-module-name ((current-module-name-resolver) '(lib "primitives.ss"
                                                                                                   "python")
                                                                                             #f
                                                                                             #f)])
                                 (dynamic-require primitives-module-name #f)
                                 (namespace-require primitives-module-name)
                                 (print "loading more modules in python-load-module")
                                 (namespace-set-variable-value! (cadr id-list)
                                                                (call-with-values
                                                                 (lambda ()
                                                                   (python-load-module (cdr id-list) absolute-id-list))
                                                                 (namespace-variable-value 'namespace->py-module%))))))
                           module))])
      (values (loaded-module-namespace module)
              (loaded-module-name module)
              (module-path->string (loaded-module-path module))))))

  
  (define (symbol-list->dotted-string sl)
    (foldr (lambda (a b)
             (if (string=? b "")
                 a
                 (string-append a "." b)))
           ""
           (map symbol->string
                sl)))
  
  
  (define (set-python-namespace-name! ns name)
  #|  (parameterize ([current-namespace ns])
       (eval (datum->syntax-object (eval '(current-toplevel-context))
                                   `(namespace-set-variable-value! '__name__
                                                                   (make-py-string
                                                                     (symbol->string name)))))))
;                                                                   ,((eval 'symbol->py-string%) name))))))
  |#
    #f)


;  (require (lib "date.ss"))
  ; parse-module: string -> (listof ast-node%)
  (define (parse-module path)
    ((dynamic-python-to-scheme) path))
 ;   (print (date->string (seconds->date (current-seconds)) #t))
  ;  (let ([compiler-module-name ((current-module-name-resolver) '(lib "python.ss" "python") #f #f)])
  ;  (print (date->string (seconds->date (current-seconds)) #t))
  ;    (dynamic-require compiler-module-name #f)
  ;  (print (date->string (seconds->date (current-seconds)) #t))
  ;    (namespace-require compiler-module-name)
  ;  (print (date->string (seconds->date (current-seconds)) #t))
  ;    (begin0 ((namespace-variable-value 'python-to-scheme) path)
  ;  (print (date->string (seconds->date (current-seconds)) #t)))))

  ; build-module-path: (U string (listof symbol)) -> module-path
  ; creates a module-path object from a list of symbols or a path to a file
  (define (build-module-path spec)
;    (printf "build-module-path: spec is ~a~n" spec)
    (let ([relative-path
           (cond
             [(string? spec) spec]
             [(list? spec) (foldr (lambda (a b)
                                    (if (string=? b "")
                                        a
                                        (build-path a b)))
                                  ""
                                  (map symbol->string spec))])])
      (let ([file-path
             (if (directory-exists? relative-path)
                 (module-path->string (build-module-path (build-path relative-path "__init__.py")))
                 (let ([fn (if (string? spec) spec (string-append relative-path ".py"))])
;                   (printf "build-module-path: fn is ~a~n" fn)
                   (if (file-exists? fn)
                       fn
                       (ormap (lambda (library-path)
                                (let ([path (build-path library-path relative-path)])
                                  (or (and (directory-exists? path)
                                           (module-path->string (build-module-path (build-path path "__init__.py"))))
                                      (let ([path (if (string? spec) path (string-append path ".py"))])
                                        (and (file-exists? path)
                                             path)))))
                              (current-python-library-paths)))))])
        (unless file-path
          (error (format "Python module ~a does not exist." relative-path)))
        (make-module-path (string->symbol (normalize-path file-path))))))

  (define copy-namespace-bindings
    (opt-lambda (from to [bindings #f] [prefix #f])
;      (printf "namespace bindings: ~a~n" bindings)
      (parameterize ([current-namespace to])
        (for-each (lambda (symbol)
;                    (printf "namespace symbol: ~a~n" symbol)
;                    (unless (namespace-variable-value symbol #t
;                                                      (lambda () #f))
                      (with-handlers ([exn:syntax? (lambda (exn) #f)]) ;ignore defined macros
                        (namespace-set-variable-value! (let ([symbol (or (and bindings
                                                                              (cadr (assq symbol
                                                                                          bindings)))
                                                                         symbol)])
;                                                         (printf "renamed symbol: ~a~n" symbol)
                                                         (if prefix
                                                             (string->symbol
                                                              (string-append (symbol->string prefix)
                                                                             (symbol->string symbol)))
                                                             symbol))
                                                       (parameterize ([current-namespace from])
                                                         (namespace-variable-value symbol)))))
                  (let ([symbols (parameterize ([current-namespace from])
                                   (namespace-mapped-symbols))])
                    (if bindings
                        (filter (lambda (sym)
                                  (assq sym bindings))
                                symbols)
                        symbols))))))

  ; eval-python: (listof syntax-object) namespace -> (listof python-node)
  (define (eval-python s-obj-list namespace)
    (filter (lambda (result)
              (not (void? result)))
            (parameterize ([current-namespace namespace])
              (map eval
                   s-obj-list))))

   ; make-python-namespace: [bool] -> namespace
  ; returns an initialized python namespace (empty namespace + python base)
  (define make-python-namespace
    (opt-lambda ([new-cache? #f])
    (let ([p-n ;(null-environment 5)])
               (make-namespace ;'initial)])
                               'empty)])
;      (when new-cache?
;        (set-python-cache-namespace! p-n))
      (init-python-namespace p-n)
      p-n)))


  (define init-python-namespace
    (let ()
    (dynamic-require '(lib "base.ss" "python") #f)
    (let ([base-path ((current-module-name-resolver) '(lib "base.ss" "python") #f #f)]
          [outer-namespace (current-namespace)])
      (lambda (py-ns)
        (with-handlers ([void (lambda (e)
                                (printf (exn-message e)))])
          (parameterize ([current-namespace py-ns])
            (namespace-attach-module outer-namespace base-path)
            (namespace-require base-path)
            ;(eval `(require (file ,(build-path (this-expression-source-directory)
            ;                                   "base.ss"))))
            ))))))
    

  (define outside (current-namespace))

  (define (my-dynamic-require dest-namespace spec)
    (dynamic-require spec #f)
    (let (;[cache (get-cache-namespace)]
          ;[path (lookup-cached-mzscheme-module spec)]
          [path2 ((current-module-name-resolver) spec #f #f)]
          [caller-namespace (current-namespace)])
      (parameterize ([current-namespace dest-namespace])
        (with-handlers ([exn:application:mismatch?
                         (lambda (e)
                           (printf "FAILURE. spec: ~a path: ~a exn: ~a~n" spec path2 e))])
;          (namespace-attach-module cache path)
         ; (printf "SUCCESS. spec: ~a  path: ~a~n" spec path)
          (namespace-attach-module caller-namespace path2)
          ;(namespace-attach-module outside 'mzscheme)
          ;(namespace-require 'mzscheme)
      ;(dynamic-require spec #f)
       ; (namespace-transformer-require spec)
        (namespace-require spec)
          )
        )))

    (define (my-dynamic-require/syntax dest-namespace spec)
    (let ([cache (get-cache-namespace)]
          [path (lookup-cached-mzscheme-module spec)]
          [caller-namespace (current-namespace)])
      (parameterize ([current-namespace dest-namespace])
        (with-handlers ([exn:application:mismatch? (lambda (e)
                                                     (printf "FAILURE. spec: ~a path: ~a exn: ~a~n" spec path e))])
          (namespace-attach-module cache path)
        (namespace-transformer-require spec)
        (namespace-require spec)
          )
        (namespace-transformer-require spec)
        (namespace-require spec)
        )))


  (define cache-namespace #f)
  (define use-cache-namespace? #t)

  (define (get-cache-namespace)
    (unless cache-namespace
      (set-python-cache-namespace! (current-namespace)))
    (if use-cache-namespace?
        cache-namespace
        (current-namespace)))

  (define (set-python-cache-namespace! ns)
    (set! cache-namespace ns))

  (define (toggle-python-use-cache-namespace! use?)
    (set! use-cache-namespace? use?))

  (define (lookup-cached-mzscheme-module spec)
    (parameterize ([current-namespace (get-cache-namespace)])
      (namespace-require spec)
      (let ([path ((current-module-name-resolver) spec #f #f)])
;        (dynamic-require path #f)
        path)))

  ; eval-python&copy: (listof syntax-object) namespace [(listof (list symbol symbol))] [symbol]-> (listof python-node)
  ; SIDE-EFFECT: adds the results to the current namespace, optionally with a prefix
  (define eval-python&copy
    (opt-lambda (s-obj-list python-namespace [bindings #f] [prefix #f])
      (begin0 (eval-python s-obj-list python-namespace)
              (copy-namespace-bindings python-namespace (current-namespace) bindings prefix))))


  ; a loaded-module is:
  ;  (make-loaded-module namespace symbol module-path)

  (define-struct loaded-module (namespace name path))

  ; a module-path is:
  ;  (make-module-path sym-path)
  ; where sym-path is a complete path symbol

  (define-struct module-path (value))

  (define (module-path->string mp)
    (symbol->string (module-path-value mp)))

  (define (module-path-dir-string mp)
    (let-values ([(base name dir?) (split-path (module-path->string mp))])
      (cond
        [(eq? 'relative base) (current-directory)]
        [(not base) "/"]
        [else base])))

  (define *loaded-modules* (make-parameter null))

  ; *add-loaded-module*: loaded-module -> void
  ; add a module to the internal list of pre-loaded modules
  (define (*add-loaded-module* module)
    (*loaded-modules* (cons module (*loaded-modules*))))

  ; *lookup-loaded-module*: module-path -> (U false loaded-module)
  ; retrieves the module specified by a module path, or signals failure by returning false
  (define (*lookup-loaded-module* path)
    (ormap (lambda (module)
             (and (eq? (module-path-value path) (module-path-value (loaded-module-path module)))
                  module))
           (*loaded-modules*)))

  (define current-python-library-paths (make-parameter (list (build-path (collection-path "python")
                                                                         "libs"))))

  (define (list-head list items)
    (reverse (list-tail (reverse list)
                        (- (length list) items))))
  )
