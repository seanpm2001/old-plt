(module exit mzscheme
  (require (lib "unitsig.ss")
           (lib "string-constant.ss" "string-constants")
	   (lib "class.ss")
	   "sig.ss"
	   "../gui-utils.ss"
	   (lib "mred-sig.ss" "mred")
	   (lib "file.ss")
           (lib "etc.ss"))

  (provide exit@)

  (define exit@
    (unit/sig framework:exit^
      (import mred^
	      [preferences : framework:preferences^])
      (rename (-exit exit))
      
      (define can?-callbacks '())
      (define on-callbacks '())
      
      (define insert-can?-callback
	(λ (cb)
	  (set! can?-callbacks (cons cb can?-callbacks))
	  (λ ()
	    (set! can?-callbacks
		  (let loop ([cb-list can?-callbacks])
		    (cond
		     [(null? cb-list) ()]
		     [(eq? cb (car cb-list)) (cdr cb-list)]
		     [else (cons (car cb-list) (loop (cdr cb-list)))]))))))

      (define insert-on-callback
	(λ (cb)
	  (set! on-callbacks (cons cb on-callbacks))
	  (λ ()
	    (set! on-callbacks
		  (let loop ([cb-list on-callbacks])
		    (cond
		     [(null? cb-list) ()]
		     [(eq? cb (car cb-list)) (cdr cb-list)]
		     [else (cons (car cb-list) (loop (cdr cb-list)))]))))))
      
      (define is-exiting? #f)
      (define (set-exiting b) (set! is-exiting? b))
      (define (exiting?) is-exiting?)
      
      (define (can-exit?) (andmap (λ (cb) (cb)) can?-callbacks))
      (define (on-exit) (for-each (λ (cb) (cb)) on-callbacks))

      (define (user-oks-exit)
	(if (preferences:get 'framework:verify-exit)
	    (gui-utils:get-choice
	     (if (eq? (system-type) 'windows)
		 (string-constant are-you-sure-exit)
		 (string-constant are-you-sure-quit))
	     (if (eq? (system-type) 'windows)
		 (string-constant exit)
		 (string-constant quit))
	     (string-constant cancel)
	     (string-constant warning)
	     #f)
	    #t))

      (define (-exit)
        (set! is-exiting? #t)
        (cond
          [(can-exit?)
           (on-exit)
           (queue-callback 
            (λ () 
              (exit)
              (set! is-exiting? #f)))]
          [else
           (set! is-exiting? #f)])))))
