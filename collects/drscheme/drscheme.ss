(module drscheme mzscheme
  (require "private/key.ss")
  
  (define debugging? (getenv "PLTDRDEBUG"))
  
  (define install-cm? (and (not debugging?)
                           (getenv "PLTDRCM")))
  
  (define cm-trace? (or (equal? (getenv "PLTDRCM") "trace")
                        (equal? (getenv "PLTDRDEBUG") "trace")))
  
  (when debugging?
    (printf "PLTDRDEBUG: installing CM to load/create errortrace zos\n")
    (let-values ([(zo-compile
                   make-compilation-manager-load/use-compiled-handler
                   manager-trace-handler)
                  (parameterize ([current-namespace (make-namespace)])
                    (values
                     (dynamic-require '(lib "zo-compile.ss" "errortrace") 'zo-compile)
                     (dynamic-require '(lib "cm.ss") 'make-compilation-manager-load/use-compiled-handler)
                     (dynamic-require '(lib "cm.ss") 'manager-trace-handler)))])
      (current-compile zo-compile)
      (use-compiled-file-paths (list (build-path "compiled" "errortrace")))
      (current-load/use-compiled (make-compilation-manager-load/use-compiled-handler))
      (error-display-handler (dynamic-require '(lib "errortrace-lib.ss" "errortrace")
                                              'errortrace-error-display-handler))
      (when cm-trace?
        (printf "PLTDRDEBUG: enabling CM tracing\n")
        (manager-trace-handler
         (λ (x) (display "1: ") (display x) (newline))))))
  
  (when install-cm?
    (printf "PLTDRCM: installing compilation manager\n")
    (let-values ([(make-compilation-manager-load/use-compiled-handler
                   manager-trace-handler)
                  (parameterize ([current-namespace (make-namespace)])
                    (values
                     (dynamic-require '(lib "cm.ss") 'make-compilation-manager-load/use-compiled-handler)
                     (dynamic-require '(lib "cm.ss") 'manager-trace-handler)))])
      (current-load/use-compiled (make-compilation-manager-load/use-compiled-handler))
      (when cm-trace?
        (printf "PLTDRCM: enabling CM tracing\n")
        (manager-trace-handler
         (λ (x) (display "1: ") (display x) (newline))))))

  (dynamic-require '(lib "drscheme-normal.ss" "drscheme" "private") #f))
