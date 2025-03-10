(module tool mzscheme
  (require (lib "tool.ss" "drscheme")
           (lib "mred.ss" "mred") (lib "framework.ss" "framework") (lib "unitsig.ss") 
           (lib "include-bitmap.ss" "mrlib") (lib "etc.ss")
           (lib "class.ss")
	   (lib "string-constant.ss" "string-constants")
           (lib "Object.ss" "profj" "libs" "java" "lang") (lib "array.ss" "profj" "libs" "java" "lang")
           (lib "String.ss" "profj" "libs" "java" "lang"))
  (require "compile.ss" "parameters.ss" "parsers/lexer.ss" "parser.ss" "ast.ss")

  (require-for-syntax "compile.ss")
  
  (provide tool@)

  ;Set the default classpath
  (preferences:set-default 'profj:classpath null (lambda (v) (and (list? v) (andmap string? v))))
  
  (define tool@
    (unit/sig drscheme:tool-exports^
      (import drscheme:tool^)

      ;Set the Java editing colors
      (define color-prefs-table
        `((keyword ,(make-object color% "black") ,(string-constant profj-java-mode-color-keyword))
          (string ,(make-object color% "forestgreen") ,(string-constant profj-java-mode-color-string))
          (literal ,(make-object color% "forestgreen") ,(string-constant profj-java-mode-color-literal))
          (comment ,(make-object color% 194 116 31) ,(string-constant profj-java-mode-color-comment))
          (error ,(make-object color% "red") ,(string-constant profj-java-mode-color-error))
          (identifier ,(make-object color% 38 38 128) ,(string-constant profj-java-mode-color-identifier))
          (default ,(make-object color% "black") ,(string-constant profj-java-mode-color-default))))
      
      ;; short-sym->pref-name : symbol -> symbol
      ;; returns the preference name for the color prefs
      (define (short-sym->pref-name sym) (string->symbol (short-sym->style-name sym)))
      
      ;; short-sym->style-name : symbol->string
      ;; converts the short name (from the table above) into a name in the editor list
      ;; (they are added in by `color-prefs:register-color-pref', called below)
      (define (short-sym->style-name sym) (format "profj:syntax-coloring:scheme:~a" sym))
      
      ;; extend-preferences-panel : vertical-panel -> void
      ;; adds in the configuration for the Java colors to the prefs panel
      (define (extend-preferences-panel parent)
        (for-each
         (lambda (line)
           (let ([sym (car line)])
             (color-prefs:build-color-selection-panel 
              parent
              (short-sym->pref-name sym)
              (short-sym->style-name sym)
              (format "~a" sym))))
         color-prefs-table))
      
      ;Create the Java editing mode
      (define mode-surrogate
        (new color:text-mode%
             (matches (list (list '|{| '|}|)
                            (list '|(| '|)|)
                            (list '|[| '|]|)))
             (get-token get-syntax-token)
             (token-sym->style short-sym->style-name)))
            
      ;repl-submit: text int -> bool
      ;Determines if the reple should submit or not
      (define (repl-submit text prompt-position)
        (let ((is-if? #f)
              (is-string? #f)
              (open-parens 0)
              (open-braces 0)
              (open-curlies 0))
          (let loop ((index 1) (char (send text get-character prompt-position)))
            (unless (eq? char #\nul)
              (cond 
                ;beginning of if statement
                ((and (= index 1) 
                      (eq? char #\i) 
                      (eq? (send text get-character (add1 prompt-position)) #\f)
                      (eq? (send text get-character (+ 2 prompt-position)) #\space))
                 (set! is-if? #t)
                 (loop 3 (send text get-character (+ 3 prompt-position))))
                ((eq? char #\()
                 (unless is-string? (set! open-parens (add1 open-parens)))
                 (loop (add1 index) (send text get-character (+ index prompt-position))))
                ((eq? char #\))
                 (unless is-string? (set! open-parens (sub1 open-parens)))
                 (loop (add1 index) (send text get-character (+ index prompt-position))))
                ((eq? char #\{)
                 (unless is-string? (set! open-curlies (add1 open-curlies)))
                 (loop (add1 index) (send text get-character (+ index prompt-position))))
                ((eq? char #\})
                 (unless is-string? (set! open-curlies (sub1 open-curlies)))
                 (loop (add1 index) (send text get-character (+ index prompt-position))))
                ((eq? char #\[)
                 (unless is-string? (set! open-braces (add1 open-braces)))
                 (loop (add1 index) (send text get-character (+ index prompt-position))))
                ((eq? char #\])
                 (unless is-string? (set! open-braces (sub1 open-braces)))
                 (loop (add1 index) (send text get-character (+ index prompt-position))))
                ;beginning of string
                ((eq? char #\")
                 (set! is-string? (not is-string?))
                 (loop (add1 index) (send text get-character (+ index prompt-position))))
                (else
                 (loop (add1 index) (send text get-character (+ index prompt-position)))))))
          (not (or (not (= open-parens 0))
                   (not (= open-braces 0))
                   (not (= open-curlies 0))
                   is-if?))))
      
      ;; matches-language : (union #f (listof string)) -> boolean
      (define (matches-language l)
        (and l (pair? l) (pair? (cdr l)) (equal? (cadr l) "ProfessorJ")))
      
      (define (phase1) void)
      ;Add all the ProfessorJ languages into DrScheme
      (define (phase2) 
        (drscheme:language-configuration:add-language
         (make-object ((drscheme:language:get-default-mixin) dynamic-lang%)))
        (drscheme:language-configuration:add-language
         (make-object ((drscheme:language:get-default-mixin) full-lang%)))
        (drscheme:language-configuration:add-language
         (make-object ((drscheme:language:get-default-mixin) advanced-lang%)))
        (drscheme:language-configuration:add-language
         (make-object ((drscheme:language:get-default-mixin) intermediate-lang%)))
        (drscheme:language-configuration:add-language
         (make-object ((drscheme:language:get-default-mixin) beginner-lang%))))                 
      
      ;(make-profj-settings symbol boolean (list string))
      (define-struct profj-settings (print-style print-full? classpath) (make-inspector))
      
      ;ProfJ general language mixin
      (define (java-lang-mixin level name number one-line dyn?)
        (when dyn? (dynamic? #t))
        (class* object% (drscheme:language:language<%>)
          
          (define/public (order-manuals x)
            (let* ((beg-list '(#"profj-beginner" #"tour" #"drscheme" #"help"))
                   (int-list (cons #"profj-intermediate" beg-list)))
              (values (case level
                        ((beginner) beg-list)
                        ((intermediate) int-list)
                        ((advanced full) (cons #"profj-advanced" int-list)))
                      #f)))
          
          ;default-settings: -> profj-settings
          (define/public (default-settings) 
            (if (memq level `(beginner intermediate advanced))
                (make-profj-settings 'field #f null)
                (make-profj-settings 'type #f null)))
          ;default-settings? any -> bool
          (define/public (default-settings? s) (equal? s (default-settings)))

          ;marshall-settings: profj-settings -> (list (list symbol) (list bool) (list string))
          (define/public (marshall-settings s)
            (list (list (profj-settings-print-style s))
                  (list (profj-settings-print-full? s))))
          
          ;unmarshall-settings: any -> (U profj-settings #f)
          (define/public (unmarshall-settings s)
            (if (and (pair? s) (= (length s) 2)
                     (pair? (car s)) (= (length (car s)) 1)
                     (pair? (cadr s)) (= (length (cadr s)) 1))
                (make-profj-settings (caar s) (caadr s) null)
                #f))

          ;Create the ProfessorJ settings selection panel
          ;Note: Should add strings to string constants
          (define/public (config-panel _parent)
            (letrec ([parent (instantiate vertical-panel% ()
                               (parent _parent)
                               (alignment '(center center))
                               (stretchable-height #f)
                               (stretchable-width #f))]
                     
                     [output-panel (instantiate group-box-panel% ()
                                     (label "Display Preferences")
                                     (parent parent)
                                     (alignment '(left center)))]
                     [print-full (when (memq level '(advanced full))
                                   (make-object check-box% "Print entire contents of arrays?" output-panel 
                                     (lambda (x y) update-pf)))]
                     [print-style (make-object radio-box%
                                    "Display style"
                                    (list "Class" "Class+Fields" );"Graphical")
                                    output-panel
                                    (lambda (x y) (update-ps)))]
                     
                     [update-pf (lambda () (void))]
                     [update-ps (lambda () (void))]
                     
                     [cp-panel (instantiate group-box-panel% ()
                                            (parent parent)
                                            (alignment '(left center))
                                            (label "Class path"))]
                     [tp-panel (instantiate horizontal-panel% ()
                                 (parent cp-panel)
                                 (alignment '(center center))
                                 (stretchable-height #f))]
                     [lb (instantiate list-box% ()
                                     (parent cp-panel)
                                     (choices `("a" "b" "c"))
                                     (label #f)
                                     (callback (lambda (x y) (update-buttons))))]
                     [top-button-panel (instantiate horizontal-panel% ()
                                         (parent cp-panel)
                                         (alignment '(center center))
                                         (stretchable-height #f))]
                     [bottom-button-panel (instantiate horizontal-panel% ()
                                            (parent cp-panel)
                                            (alignment '(center center))
                                            (stretchable-height #f))]
                     [list-button (make-object button% "Display Current" tp-panel (lambda (x y) (list-callback)))]                     
                     [add-button (make-object button% "Add" bottom-button-panel (lambda (x y) (add-callback)))]
                     [remove-button (make-object button% "Remove" bottom-button-panel (lambda (x y) (remove-callback)))]
                     [raise-button (make-object button% "Raise" top-button-panel (lambda (x y) (raise-callback)))]
                     [lower-button (make-object button% "Lower" top-button-panel (lambda (x y) (lower-callback)))]
                     [enable? #f]
                     
                     [update-buttons 
                      (lambda ()
                        (let ([lb-selection (send lb get-selection)]
                              [lb-tot (send lb get-number)])
                          (send remove-button enable (and lb-selection enable?))
                          (send raise-button enable (and lb-selection enable? (not (= lb-selection 0))))
                          (send lower-button enable (and lb-selection enable? (not (= lb-selection (- lb-tot 1)))))))]
                     [add-callback
                      (lambda ()
                        (let ([dir (get-directory "Choose the directory to add to class path" 
                                                  (send parent get-top-level-window))])
                          (when dir
                            (send lb append dir #f)
                            (preferences:set 'profj:classpath (cons dir (preferences:get 'profj:classpath)))
                            (update-buttons))))]
                     [list-callback
                      (lambda ()
                        (send lb clear)
                        (let ((cpath (preferences:get 'profj:classpath)))
                          (let loop ((n 0) (l cpath))
                            (cond
                              ((> n (sub1 (length cpath))) (void))
                              (else (send lb append (car l))
                                    (send lb set-data n (car l))
                                    (loop (+ n 1) (cdr l)))))
                          (unless (null? cpath)
                            (send lb set-selection 0))
                          (set! enable? #t)
                          (update-buttons)))]
                     [remove-callback
                      (lambda ()
                        (let ([to-delete (send lb get-selection)])
                           (send lb delete to-delete)
                          (unless (zero? (send lb get-number))
                            (send lb set-selection (min to-delete (- (send lb get-number) 1))))
                          (preferences:set 'profj:classpath (get-classpath))
                          (update-buttons)))]
                     [lower-callback
                      (lambda ()
                        (let* ([sel (send lb get-selection)]
                               [vec (get-lb-vector)]
                               [below (vector-ref vec (+ sel 1))])
                          (vector-set! vec (+ sel 1) (vector-ref vec sel))
                          (vector-set! vec sel below)
                          (set-lb-vector vec)
                          (send lb set-selection (+ sel 1))
                          (preferences:set 'profj:classpath (get-classpath))
                          (update-buttons)))]
                     [raise-callback
                      (lambda ()
                        (let* ([sel (send lb get-selection)]
                               [vec (get-lb-vector)]
                               [above (vector-ref vec (- sel 1))])
                          (vector-set! vec (- sel 1) (vector-ref vec sel))
                          (vector-set! vec sel above)
                          (set-lb-vector vec)
                          (send lb set-selection (- sel 1))
                          (preferences:set 'profj:classpath (get-classpath))
                          (update-buttons)))]
                     [get-lb-vector
                      (lambda ()
                        (list->vector
                         (let loop ([n 0])
                           (cond
                             [(= n (send lb get-number)) null]
                             [else (cons (cons (send lb get-string n)
                                               (send lb get-data n))
                                         (loop (+ n 1)))]))))]
                     [set-lb-vector
                      (lambda (vec)
                        (send lb clear)
                        (let loop ([n 0])
                          (cond
                            [(= n (vector-length vec)) (void)]
                            [else (send lb append (car (vector-ref vec n)))
                                  (send lb set-data n (cdr (vector-ref vec n)))
                                  (loop (+ n 1))])))]
                     [get-classpath
                      (lambda ()
                        (let loop ([n 0])
                          (cond
                            [(= n (send lb get-number)) null]
                            [else
                             (let ([data (send lb get-data n)])
                               (cons (if data
                                         'default
                                         (send lb get-string n))
                                     (loop (+ n 1))))])))]
                     [install-classpath
                      (lambda (paths)
                        (send lb clear)
                        (for-each (lambda (cp)
                                    (if (symbol? cp)
                                        (send lb append "Default" #t)
                                        (send lb append cp #f)))
                                  paths))])
              (send lb set '())
              (update-buttons)
              
              (case-lambda
                [()
                 (make-profj-settings (case (send print-style get-selection)
                                        [(0) 'type]
                                        [(1) 'field]
                                        [(2) 'graphical])
                                      (if (memq level '(advanced full))
                                          (send print-full get-value)
                                          #f)
                                      (get-classpath))]
                [(settings)
                 (send print-style set-selection
                       (case (profj-settings-print-style settings)
                         ((type default) 0)
                         ((field) 1)
                         ((graphical) 2)))
                 (when (memq level '(advanced full))
                   (send print-full set-value (profj-settings-print-full? settings)))
                 (install-classpath (profj-settings-classpath settings))])))
                     
          ;;Stores the types that can be used in the interactions window
          ;;execute-types: type-record 
          (define execute-types (create-type-record))
          
          (define/public (front-end/complete-program port settings teachpack-cache)
            (set! execute-types (create-type-record))
            (let ([name (object-name port)])
              (lambda ()
                (syntax-as-top
                 (let ((end? (eof-object? (peek-char-or-special port))))
                   (if end? 
                       eof 
                       (datum->syntax-object #f `(parse-java-full-program ,(parse port name level)) #f)))))))
          (define/public (front-end/interaction port settings teachpack-cache)
            (let ([name (object-name port)])
              (lambda ()
                (if (eof-object? (peek-char-or-special port))
                    eof
		    (syntax-as-top
                     (datum->syntax-object 
                      #f
                      #;`(compile-interactions-helper ,(lambda (ast) (compile-interactions-ast ast name level execute-types))
                                                    ,(parse-interactions port name level))
                      `(parse-java-interactions ,(parse-interactions port name level) ,name)
                      #f))))))

          ;process-extras: (list struct) type-record -> (list syntax)
          (define/private (process-extras extras type-recs)
            (cond
              ((null? extras) null)
              ((example-box? (car extras)) 
               (let ((contents (eval (example-box-contents (car extras)))))
                 (append 
                  (map (lambda (example)
                         (let* ((type-editor (car example))
                                (type (parse-type (open-input-text-editor type-editor) type-editor level))
                                (name-editor (cadr example))
                                (name (parse-name (open-input-text-editor name-editor) name-editor))
                                (val-editor (caddr example))
                                (val (parse-expression (open-input-text-editor val-editor) val-editor level)))
                           (compile-interactions-ast
                            (make-var-init (make-var-decl name null type #f) val #f #f)
                            val-editor level type-recs)))
                       contents)
                  (process-extras (cdr extras) type-recs))))
              ((test-case? (car extras))
               (cons 
                (let ((new-test-case
                       (lambda (to-test-stx exp-stx record set-actuals)
                         (let ([to-test-values (call-with-values (lambda () to-test-stx) list)]
                               [exp-values (call-with-values (lambda () exp-stx) list)])
                           (record (and (= (length to-test-values) (length exp-values))
                                        (andmap (dynamic-require '(lib "profj-testing.ss" "profj") 'java-values-equal?)
                                                to-test-values exp-values)))
                           (set-actuals to-test-values)))))
                  (let-values (((syn t t2) (send (test-case-test (car extras)) read-special #f #f #f #f)))
                    (syntax-case syn ()
                      ((test-case equal? exp1 exp2 exp3 exp4) 
                       (syntax-case (syntax exp1) (begin require)
                         ((begin (require req ...) exp)
                          (syntax-case (syntax exp2) (begin require)
                            ((begin (require req2 ...) new-exp2) 
                             (datum->syntax-object #f 
                                                   `(begin ,(syntax (require req ... req2 ...))
                                                           (,new-test-case ,(syntax exp) ,(syntax new-exp2)
                                                             ,(syntax exp3) ,(syntax exp4)))
                                                   #f))
                            (else 
                             (datum->syntax-object #f
                                                   `(begin ,(syntax (require req ...))
                                                           (,new-test-case ,(syntax exp) ,(syntax exp2)  ,(syntax exp3) ,(syntax exp4)))
                                                   #f))))                         
                         (else 
                          (syntax-case (syntax exp2) (begin require)
                            ((begin (require req2 ...) new-exp2)
                             (datum->syntax-object #f
                                                   `(begin ,(syntax (require req2 ...))
                                                           (,new-test-case ,(syntax exp1) ,(syntax new-exp2) ,(syntax exp3) ,(syntax exp4)))
                                                   #f))
                          (else 
                           (datum->syntax-object #f `(,new-test-case ,(syntax exp1) ,(syntax exp2) ,(syntax exp3) ,(syntax exp4)) #f))))))
                      (else syn))))
                (process-extras (cdr extras) type-recs)))
              ((interact-case? (car extras))
               (let ((interact-box (interact-case-box (car extras))))
                 (send interact-box set-level level)
                 (send interact-box set-records execute-types)
                 (send interact-box set-ret-kind #t)
                 (append 
                  (with-handlers ((exn? 
                                   (lambda (e)
                                     (send execute-types clear-interactions)
                                     (raise e))))
                    (let-values (((syn-list t t2) 
                                  (send interact-box read-special #f #f #f #f))) syn-list))
                  (process-extras (cdr extras) type-recs))))))
          
          ;find-main-module: (list compilation-unit) -> (U syntax #f)
          (define/private (find-main-module mod-lists)
            (if (null? mod-lists)
                #f
                (let ((names (compilation-unit-contains (car mod-lists)))
                      (syntaxes (compilation-unit-code (car mod-lists))))
                  (if (member (cadr (main)) names)
                      (if (= (length syntaxes) 1)
                          (list-ref syntaxes 0)
                          (list-ref syntaxes (find-position names 1)))
                      (find-main-module (cdr mod-lists))))))
        
          ;find-position: (list string) number-> number
          (define/private (find-position l p)
            (when (null? l)
              (error 'find-position "Internal Error: member incorrectly chose an element as a member"))
            (if (equal? (cadr (main)) (car l))
                p
                (find-position (cdr l) (add1 p))))
          
          ;order: (list compilation-unit) -> (list syntax)
          (define/private (order mod-lists)
            (if (null? mod-lists)
                null
                (append (compilation-unit-code (car mod-lists))
                        (order (cdr mod-lists)))))
              
          (define/public (get-comment-character) (values "//" "*"))
          (define/public (get-style-delta) #f)
          (define/public (get-language-position) 
            (cons (string-constant experimental-languages) (list "ProfessorJ" name) ))
          (define/public (get-language-numbers) (list 1000 10 number))
          (define/public (get-language-name) (string-append "ProfessorJ: " name))
          (define/public (get-language-url) #f)
          (define/public (get-teachpack-names) null)

          (define/private (syntax-as-top s)
	    (if (syntax? s) (namespace-syntax-introduce s) s))
          
          (define/public (on-execute settings run-in-user-thread)
            (dynamic-require '(lib "Object.ss" "profj" "libs" "java" "lang") #f)
            (let ([obj-path ((current-module-name-resolver) '(lib "Object.ss" "profj" "libs" "java" "lang") #f #f)]
                  [class-path ((current-module-name-resolver) '(lib "class.ss") #f #f)]
                  [tool-path ((current-module-name-resolver) '(lib "tool.ss" "profj") #f #f)]
                  [n (current-namespace)])
              (read-case-sensitive #t)
              (run-in-user-thread
               (lambda ()
                 (error-display-handler 
                  (drscheme:debug:make-debug-error-display-handler (error-display-handler)))
                 (let ((old-current-eval (drscheme:debug:make-debug-eval-handler (current-eval))))
                   (current-eval 
                    (lambda (exp)
                      (syntax-case exp (parse-java-full-program parse-java-interactions)
                        ((parse-java-full-program ex)
                         (let ((exp (old-current-eval (syntax ex))))
                           (execution? #t)
                           (let ((name-to-require #f))
                             (let loop ((mods (order (compile-ast exp level execute-types)))
                                        (extras (process-extras 
                                                 (send execute-types get-interactions-boxes) execute-types))
                                        (require? #f))
                               (cond
                                 ((and (not require?) (null? mods) (null? extras)) (void))
                                 ((and (not require?) (null? mods))
                                  (old-current-eval (syntax-as-top (car extras)))
                                  (loop mods (cdr extras) require?))
                                 (require? 
                                  (old-current-eval 
                                   (syntax-as-top (with-syntax ([name name-to-require])
                                                    (syntax (require name)))))
                                  (loop mods extras #f))
                                 (else 
                                  (let-values (((name syn) (get-module-name (expand (car mods)))))
                                    (set! name-to-require name)
                                    (syntax-as-top (old-current-eval syn))
                                    (loop (cdr mods) extras #t))))))))
                        ((parse-java-interactions ex loc)
                         (let ((exp (syntax-object->datum (syntax ex))))
                           (old-current-eval 
                            (syntax-as-top (compile-interactions-ast exp (syntax loc) level execute-types)))))
                        (_ (old-current-eval exp))))))
                 (with-handlers ([void (lambda (x)  (printf "~a~n" (exn-message x)))])
                   (namespace-require 'mzscheme)
                   (namespace-attach-module n obj-path)
                   (namespace-attach-module n class-path)
                   (namespace-require obj-path)
                   #;(namespace-require '(lib "tool.ss" "profj"))
                   (namespace-require class-path)
                   (namespace-require '(prefix javaRuntime: (lib "runtime.scm" "profj" "libs" "java")))
                   (namespace-require '(prefix c: (lib "contract.ss"))))))))
          
          (define/public (render-value value settings port); port-write)
            (let ((print-full? (profj-settings-print-full? settings))
                  (style (profj-settings-print-style settings)))
              (if (is-a? value String)
                  (write-special (send value get-mzscheme-string) port)
                  (let ((out (format-java value print-full? style null #f 0)))
                    (if (< 25 (string-length out))
                        (display (format-java value print-full? style null #t 0) port)
                        (display out port))))))
          (define/public (render-value/format value settings port width) 
            (render-value value settings port)(newline port))
          
          (define/public (create-executable fn parent . args)
	    (message-box "Unsupported"
			 "Sorry - executables are not supported for Java at this time"
			 parent))
	  (define/public (get-one-line-summary) one-line)
          
          (super-instantiate ())))
      
      ;Create the ProfessorJ languages
      (define full-lang% (java-lang-mixin 'full "Full" 4 "Like Java 1.0 (some 1.1)" #f))
      (define advanced-lang% (java-lang-mixin 'advanced "Advanced" 3 "Java-like Advanced teaching language" #f))
      (define intermediate-lang% 
        (java-lang-mixin 'intermediate "Intermediate" 2 "Java-like Intermediate teaching language" #f))
      (define beginner-lang% (java-lang-mixin 'beginner "Beginner" 1 "Java-like Beginner teaching language" #f))
      (define dynamic-lang% (java-lang-mixin 'full "Java+dynamic" 5 "Java with dynamic typing capabilities" #t))
      
      ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
      ;;
      ;;  Wire up to DrScheme
      ;;
      
      (drscheme:modes:add-mode (string-constant profj-java-mode) mode-surrogate repl-submit matches-language)
      (color-prefs:add-to-preferences-panel (string-constant profj-java) extend-preferences-panel)
      
      (for-each (lambda (line)
                  (let ([sym (car line)]
                        [color (cadr line)])
                    (color-prefs:register-color-pref (short-sym->pref-name sym)
                                                     (short-sym->style-name sym)
                                                     color)))
                color-prefs-table)
      
      ;;Java Boxes
      (define java-box%
        (class* decorated-editor-snip% ()
          (inherit get-admin get-editor)
          (define/public (get-comment) "// ")
          (define/public (get-mesg) "Convert to text comment")

          (define/override get-text
            (opt-lambda (offset num [flattened? #t])
              (let* ([super-res (super get-text offset num flattened?)]
                     [replaced (string-append (send this get-comment) 
                                              (regexp-replace* "\n" super-res 
                                                               (string-append "\n" (send this get-comment))))])
                (if (char=? #\newline (string-ref replaced (- (string-length replaced) 1)))
                    replaced
		    (string-append replaced "\n")))))
          (define/override (get-menu)
            (let ([menu (make-object popup-menu%)])
              (make-object menu-item% 
                (send this get-mesg)
                menu
                (lambda (x y)
                  (let ([to-ed (find-containing-editor)])
                    (when to-ed
                      (let ([this-pos (find-this-position)])
                        (when this-pos
                          (let ([from-ed (get-editor)])
                            (send to-ed begin-edit-sequence)
                            (send from-ed begin-edit-sequence)
                            (copy-contents-with-comment-char-to-position to-ed from-ed (+ this-pos 1))
                            (send to-ed delete this-pos (+ this-pos 1))
                            (send to-ed end-edit-sequence)
                            (send from-ed end-edit-sequence))))))))
              menu))
          ;; find-containing-editor : -> (union #f editor)
          (define/private (find-containing-editor)
            (let ([admin (get-admin)])
              (and admin
                   (send admin get-editor))))
          
          ;; find-this-position : -> (union #f number)
          (define/private (find-this-position)
            (let ([ed (find-containing-editor)])
              (and ed
                   (send ed get-snip-position this))))
          
          ;; copy-contents-with-comment-char-to-position : (is-a? text%) number -> void
          (define/private (copy-contents-with-comment-char-to-position to-ed from-ed pos)
            (let loop ([snip (find-last-snip from-ed)])
              (cond
                [snip 
                 (when (or (memq 'hard-newline (send snip get-flags))
                           (memq 'newline (send snip get-flags)))
                   (send to-ed insert (send this get-comment) pos))
                 (send to-ed insert (send snip copy) pos)
                 (loop (send snip previous))]
                [else 
                 (send to-ed insert (send this get-comment) pos)])))
          
          ;; find-last-snip : editor -> snip
          ;; returns the last snip in the editor
          (define/private (find-last-snip ed)
            (let loop ([snip (send ed find-first-snip)]
                       [acc (send ed find-first-snip)])
              (cond
                [snip (loop (send snip next) snip)]
                [else acc])))
          
          (super-instantiate ())
          ))
      
      ;Comment box
      ;;Comment icon
      (define comment-gif (include-bitmap (lib "slash-slash.gif" "icons")))
      
      ;;The following code has been taken with small modifications from framework/private/comment-box.ss
      (define snipclass-java-comment%
        (class decorated-editor-snipclass%
          (define/override (make-snip stream-in) (instantiate java-comment-box% ()))
          (super-instantiate ())))
      
      (define snipclass-comment (make-object snipclass-java-comment%))
      (send snipclass-comment set-version 1)
      (send snipclass-comment set-classname "java-comment-box%")
      (send (get-the-snip-class-list) add snipclass-comment)
      
      (define java-comment-box%
        (class* java-box% (readable-snip<%>)
          (define/override (make-editor) (new text:keymap%))
          (define/override (make-snip) (make-object java-comment-box%))
          (define/override (get-corner-bitmap) comment-gif)
          (define/override (get-position) 'left-top)

          (define/public (read-special source line column position)
            (make-special-comment 1))
          
          (super-instantiate ())
          (inherit set-snipclass get-editor)
          (set-snipclass snipclass-comment)))
          
      (define (java-comment-box-mixin %)
        (class %
          (inherit get-special-menu get-edit-target-object)
          
          (super-new)
          (new menu-item%
            (label  (string-constant profj-insert-java-comment-box))
            (parent (get-special-menu))
            (callback
             (lambda (menu event)
               (let ([c-box (new java-comment-box%)]
                     [text (get-edit-target-object)])
                 (send text insert c-box)
                 (send text set-caret-owner c-box 'global)))))))
      
      (drscheme:get/extend:extend-unit-frame java-comment-box-mixin)
      
      ;;Java interactions box
      #;(define ji-gif (include-bitmap (lib "java-interactions-box.gif" "icons")))
      (define ji-gif (include-bitmap (lib "j.gif" "icons")))
      
      (define snipclass-java-interactions%
        (class decorated-editor-snipclass%
          (define/override (make-snip stream-in) (instantiate java-interactions-box% ()))
          (super-instantiate ())))
      
      (define snipclass-interactions (make-object snipclass-java-interactions%))
      (send snipclass-interactions set-version 1)
      (send snipclass-interactions set-classname "java-interactions-box%")
      (send (get-the-snip-class-list) add snipclass-interactions)
      
      (define java-interactions-box%
        (class* java-box% (readable-snip<%>)
          (define/override (make-editor) (new ((drscheme:unit:get-program-editor-mixin) color:text%)))
          (define/override (make-snip) (make-object java-interactions-box%))
          (define/override (get-corner-bitmap) ji-gif)
          (define/override (get-mesg) "Convert to comment")
          (define level 'full)
          (define type-recs (create-type-record))
          (define ret-list? #f)
          (define/public (set-level l) (set! level l))
          (define/public (set-records tr) (set! type-recs tr))
          (define/public (set-ret-kind k) (set! ret-list? k)) 
          (define-struct input-length (start-pos end-pos))

          (define/private (newline? char) (memq char '(#\015 #\012)))
          
          (define/public (read-special source line column position)
            (let* ((ed (get-editor))
                   (port (open-input-text-editor ed 0 'end (editor-filter #t)))
                   (inputs-list null))
              (let outer-loop ((c (read-char-or-special port)) (start 0))
                (unless (eof-object? c)
                  (let inner-loop ((put c) (offset start))
                    (cond
                      ((eof-object? put)
                       (set! inputs-list (cons (make-input-length start offset) inputs-list))
                       (outer-loop (read-char-or-special port) (add1 offset)))
                      ((newline? put) 
                       (let ((new-put (read-char-or-special port))) 
                         (if (or (eof-object? new-put) (newline? new-put))
                             (begin
                               (set! inputs-list (cons (make-input-length start (add1 offset)) inputs-list))
                               (outer-loop (read-char-or-special port) (+ 2 offset)))
                             (inner-loop new-put (add1 offset)))))
                      #;((or (eq? put #\015) (eq? put #\012) (eof-object? put))
                         (set! inputs-list (cons (make-input-length start offset) inputs-list))
                         (outer-loop (read-char-or-special port) (add1 offset)))
                      (else (inner-loop (read-char-or-special port) (add1 offset)))))))
              (let ((syntax-list (map 
                                  (lambda (input-len)
                                    (interactions-offset (input-length-start-pos input-len))
                                    
                                    (compile-interactions (open-input-text-editor ed 
                                                                                  (input-length-start-pos input-len)
                                                                                  (input-length-end-pos input-len)
                                                                                  (editor-filter #t))
                                                          ed type-recs level))
                                  (reverse inputs-list))))
;                (printf "~a~n~a~n" syntax-list (map remove-requires syntax-list))
                (if ret-list?
                    syntax-list
                    (datum->syntax-object #f `(begin ,@(map remove-requires syntax-list)) #f)))))
          (define (remove-requires syn)
            (syntax-case* syn (begin require) (lambda (r1 r2) (eq? (syntax-e r1) (syntax-e r2)))
              ((begin (require x ...) exp1 exp ...) (syntax (begin exp1 exp ...)))
              (else syn)))
          
          (super-instantiate ())
          (inherit set-snipclass get-editor)
          (set-snipclass snipclass-interactions)
          (send (get-editor) start-colorer
                short-sym->style-name get-syntax-token 
                (list (list '|{| '|}|)
                      (list '|(| '|)|)
                      (list '|[| '|]|)))
          ))
      
      (define (java-interactions-box-mixin %)
        (class %
          (inherit get-special-menu get-edit-target-object)
          
          (super-new)
          (new menu-item%
               (label (string-constant profj-insert-java-interactions-box))
               (parent (get-special-menu))
               (callback
                (lambda (menu event)
                  (let ([i-box (new java-interactions-box%)]
                        [text (get-edit-target-object)])
                    (send text insert i-box)
                    (send text set-caret-owner i-box 'global)))))))
      
      (drscheme:get/extend:extend-unit-frame java-interactions-box-mixin)
      

  ))
  (define (editor-filter delay?)
    (lambda (s)
      (let ((name (send (send s get-snipclass) get-classname)))
        (cond
          ((equal? "test-case-box%" name) (values (make-test-case s) 1))
          ((equal? "java-interactions-box%" name) (values (make-interact-case s) 1))
          ((equal? "java-class-box%" name) (values (make-class-case s) 1))
          (delay? (values (lambda () (send s read-one-special 0 #f #f #f #f)) 1))
          (else (values s 1))))))
    
  (provide compile-interactions-helper)
  (define-syntax (compile-interactions-helper syn)
    (syntax-case syn ()
      ((_ comp ast)
        (namespace-syntax-introduce ((syntax-object->datum (syntax comp))
                                     (syntax-object->datum (syntax ast)))))))
  
    
  (provide format-java)
  ;formats a java value (number, character or Object) into a string
  ;format-java: java-value bool symbol (list value) -> string
  (define (format-java value full-print? style already-printed newline? num-tabs)
    (cond
      ((null? value) "null")
      ((number? value) (format "~a" value))
      ((char? value) (format "'~a'" value))
      ((boolean? value) (if value "true" "false"))
      ((is-java-array? value) 
       (if full-print?
           (array->string value (send value length) -1 #t style already-printed newline? num-tabs)
           (array->string value 3 (- (send value length) 3) #f style already-printed newline? num-tabs)))
      ((is-a? value String) (format "~s" (send value get-mzscheme-string)))
      ((is-a? value ObjectI)
       (case style
         ((type) (send value my-name))
         ((field)
          (let* ((retrieve-fields (send value fields-for-display))
                 (st (format "~a(" (send value my-name)))
                 (new-tabs (+ num-tabs 3));(string-length st)))
                 (fields ""))
            (let loop ((current (retrieve-fields)))
              (let ((next (retrieve-fields)))
                (when current
                  (set! fields 
                        (string-append fields 
                                       (format "~a~a = ~a~a~a" 
                                               (if newline? (if (equal? fields "") 
                                                                (format "~n~a" (get-n-spaces new-tabs)); "" 
                                                                (get-n-spaces new-tabs)) "")
                                               (car current)
                                               (if (memq (cadr current) already-printed)
                                                   (format-java (cadr current) full-print? 'type already-printed #f 0)
                                                   (format-java (cadr current) full-print? style 
                                                                (cons value already-printed) newline?
                                                                (if newline? 
                                                                    (+ new-tabs (string-length (car current)) 3)
                                                                    num-tabs)))
                                               (if next "," "")
                                               (if newline? (format "~n") " "))))
                  (loop next))))
            (string-append st 
                           (if (> (string-length fields) 1) 
                               (substring fields 0 (sub1 (string-length fields))) "") ")")))
         (else (send value my-name))))
      (else (format "~a" value))))
  
  ;array->string: java-value int int bool symbol (list value) -> string
  (define (array->string value stop restart full-print? style already-printed nl? nt)
    (letrec ((len (send value length))
             (make-partial-string
              (lambda (idx first-test second-test)
                (cond
                  ((first-test idx) "")
                  ((second-test idx)
                   (string-append (format-java (send value access idx) full-print? style already-printed nl? nt)
                                  (make-partial-string (add1 idx) first-test second-test)))
                  (else
                   (string-append (format-java (send value access idx) full-print? style already-printed nl? nt)
                                  " "
                                  (make-partial-string (add1 idx) first-test second-test)))))))
      (if (or full-print? (< restart stop))
          (format "[~a]" (make-partial-string 0 (lambda (i) (>= i len)) (lambda (i) (= i (sub1 len)))))
          (format "[~a~a~a]"                      
                  (make-partial-string 0 (lambda (i) (or (>= i stop) (>= i len))) (lambda (i) (= i (sub1 stop))))
                  " ... "
                  (make-partial-string restart (lambda (i) (>= i len)) (lambda (i) (= i (sub1 len))))))))
  
  (define (get-n-spaces n)
    (cond
      ((= n 0) "")
      (else (string-append " " (get-n-spaces (sub1 n))))))
  
  (define (get-module-name stx)
    (syntax-case stx (module #%plain-module-begin)
      [(module name lang (#%plain-module-begin bodies ...))
       (values (syntax name)
               (syntax (module name lang
                         (#%plain-module-begin bodies ...))))]
      [else 
       (raise-syntax-error 'Java 
                           "Internal Syntax error in getting module name"
                           stx)]))
  
  (define (add-main-call stx)
    (syntax-case stx (module #%plain-module-begin)
      [(module name lang (#%plain-module-begin bodies ...))
       (let ([execute-body (if (car (main))
                               `(lambda (x) 
                                  (display "executing main - ")
                                  (display (,(string->symbol (string-append (cadr (main)) "-main_java.lang.String1")) x)))
                               'void)])
         (with-syntax ([main (datum->syntax-object #f execute-body #f)]) 
           (values (syntax name)
                   (syntax (module name lang 
                             (#%plain-module-begin 
                              (begin bodies ...)
                              (main "temporary")))))))]
      [else
       (raise-syntax-error 'Java
                           "Internal Syntax error in compiling Java Program"
                           stx)])))
