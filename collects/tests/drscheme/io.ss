#|

add this test:

(let ()
  (display "x")
  (write-special (make-object string-snip% " in: "))
  (display "y")
  (flush-output))

|#

(module io mzscheme
  (require "drscheme-test-util.ss"
           (lib "gui.ss" "tests" "utils")
           (lib "class.ss")
           (lib "list.ss")
           (lib "pretty.ss")
           (lib "mred.ss" "mred")
           (lib "framework.ss" "framework")
           (lib "text-string-style-desc.ss" "mrlib")
           (prefix fw: (lib "framework.ss" "framework")))
  
  (provide run-test)
  
  (define (output-err-port-checking)
    (define (check-output expression expected)
      (begin
        (clear-definitions drs-frame)
        (type-in-definitions drs-frame expression)
        (do-execute drs-frame)
        (let* ([text (send drs-frame get-interactions-text)]
               [got (get-string/style-desc text (send text paragraph-start-position 2))])
          (unless (andmap (λ (exp got)
                            (and (string=? (car exp) (car got))
                                 (or (equal? (cadr exp) (cadr got))
                                     (and (procedure? (cadr exp))
                                          ((cadr exp) (cadr got))))))
                          expected 
                          got)
            (error 'io.ss "expected ~s, got ~s for ~s" expected got expression)))))
    
    (define (output-style x) (equal? (list-ref x 9) '(150 0 150)))
    (define (error-style x) (equal? (list-ref x 9) '(255 0 0)))
    
    (define prompt '("\n> " default-color))
    
    (check-output "(display 1)" (list (list "1" output-style) prompt))
    (check-output "(display 1 (current-output-port))" (list (list "1" output-style) prompt))
    
    (check-output "(display 1 (current-error-port))" (list (list "1" error-style) prompt))
    (check-output "(display 1) (display 1 (current-error-port))" 
                  (list (list "1" output-style)
                        (list "1" error-style)
                        prompt))
    (check-output "(display 1 (current-error-port)) (display 1)" 
                  (list (list "1" error-style)
                        (list "1" output-style)
                        prompt))
    (check-output "(display 1) (display 1 (current-error-port)) (display 1)" 
                  (list (list "1" output-style)
                        (list "1" error-style)
                        (list "1" output-style)
                        prompt))
    (check-output "(display 1 (current-error-port)) (display 1) (display 1 (current-error-port))"
                  (list (list "1" error-style)
                        (list "1" output-style)
                        (list "1" error-style)
                        prompt))
    (check-output "(let ([s (make-semaphore)]) (thread (lambda () (display 1) (semaphore-post s))) (semaphore-wait s))"
                  (list (list "1" output-style)
                        prompt))
    (check-output
     "(let ([s (make-semaphore)]) (thread (lambda () (display 1 (current-output-port)) (semaphore-post s))) (semaphore-wait s))" 
     (list (list "1" output-style)
           prompt))
    (check-output
     "(let ([s (make-semaphore)]) (thread (lambda () (display 1 (current-error-port)) (semaphore-post s))) (semaphore-wait s))"
     (list (list "1" error-style)
           prompt)))
  
  (define (long-io/execute-test)
    (let ([string-port (open-output-string)])
      (pretty-print
       (let f ([n 7] [p null]) (if (= n 0) p (list (f (- n 1) (cons 'l p)) (f (- n 1)  (cons 'r p)))))
       string-port)
      (clear-definitions drs-frame)
      (type-in-definitions
       drs-frame
       "(let f ([n 7] [p null]) (if (= n 0) p (list (f (- n 1) (cons 'l p)) (f (- n 1)  (cons 'r p)))))")
      (do-execute drs-frame)
      (let ([got-output (fetch-output drs-frame)])
        (clear-definitions drs-frame)
        (do-execute drs-frame)
        (unless (equal? "" (fetch-output drs-frame))
          (error 'io.ss "failed long io / execute test (extra io)"))
        (unless (whitespace-string=?
                 (get-output-string string-port)
                 got-output)
          (error 'io.ss "failed long io / execute test (output doesn't match)")))))
  
  
  (define (reading-test)
    (define (do-input-test program input expected-transcript)
      (do-execute drs-frame)
      (type-in-interactions drs-frame program)
      (let ([before-newline-pos (send interactions-text last-position)])
        (type-in-interactions drs-frame (string #\newline))
        (wait (λ ()
                ;; the focus moves to the input box, so wait for that.
                (send interactions-text get-focus-snip))
              "input box didn't appear")
        
        (type-string input)
        (wait-for-computation drs-frame)
        (let ([got-value
               (fetch-output drs-frame 
                             (send interactions-text paragraph-start-position 3) ;; start after test expression
                             (send interactions-text paragraph-end-position
                                   (- (send interactions-text last-paragraph) 1)))])
          (unless (equal? got-value expected-transcript)
            (printf "FAILED: expected: ~s~n             got: ~s~n         program: ~s~n           input: ~s~n"
                    expected-transcript got-value program input)))))
    
    (clear-definitions drs-frame)
    (do-input-test "(read-char)" "a\n" "a\n#\\a")
    (do-input-test "(read-char)" "λ\n" "λ\n#\\λ")
    (do-input-test "(read-line)" "abcdef\n" "abcdef\n\"abcdef\"") 
    (do-input-test "(list (read-char) (read-line))" "abcdef\n" "abcdef\n(#\\a \"bcdef\")")

    (do-input-test "(read)" "a\n" "a\na")
    (do-input-test "(list (read) (read))" "a a\n" "a a\n(a a)")
    (do-input-test "(list (read-char) (read))" "aa\n" "aa\n(#\\a a)")
    
    (do-input-test "(begin (read-char) (sleep 1) (read-char))" "ab\ncd\n" "ab\ncd\n#\\b")
    (do-input-test "(list (read) (sleep 1) (read) (read))" "a b\nc d\n" "a b\nc d\n(a #<void> b c)")
    
    (do-input-test "(begin (display 1) (read))" "2\n" "12\n2\n") ;; why an extra newline?!
    
    (do-input-test "(read-line)" "\n" "\n\"\"")
    (do-input-test "(read-char)" "\n" "\n#\\newline")

    (do-input-test "(list (read) (printf \"1~n\") (read) (printf \"3~n\"))"
                   "0 2\n"
                   "0 2\n1\n3\n(0 #<void> 2 #<void>)")
    
    (do-input-test "(write (read))"
                   "()\n"
                   "()\n()")
    
    (do-input-test "(begin (write (read)) (write (read)))"
                   "(1)\n(2)\n"
                   "(1)\n(1)(2)\n(2)")
    
    (do-input-test 
     (string-append "(let ([b (read-byte)][bs0 (bytes 0)][bs1 (bytes 1)][bs2 (bytes 2)])"
                    "(read-bytes-avail!* bs0)"
                    "(read-bytes-avail!* bs1)"
                    "(read-bytes-avail!* bs2)"
                    "(list b bs0 bs1 bs2))\n")
     "ab\n"
     "ab\n(97 #\"b\" #\"\\n\" #\"\\2\")"))
  
  (define drs-frame (wait-for-drscheme-frame))
  (define interactions-text (send drs-frame get-interactions-text))
  (set-language-level! (list "PLT" (regexp "Textual")))
  
  (define (run-test)
    ;(long-io/execute-test)
    ;(output-err-port-checking)
    (reading-test)
    ))
