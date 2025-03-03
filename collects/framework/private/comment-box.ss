
(module comment-box mzscheme
  (require (lib "class.ss")
           (lib "etc.ss")
	   (lib "mred.ss" "mred")
           (lib "unitsig.ss")
           "sig.ss"
           "../decorated-editor-snip.ss"
           (lib "include-bitmap.ss" "mrlib")
           (lib "string-constant.ss" "string-constants"))
  
  (provide comment-box@)
  
  (define comment-box@
    (unit/sig framework:comment-box^
      (import [text : framework:text^]
              [scheme : framework:scheme^]
              [keymap : framework:keymap^])
      
      (rename [-snip% snip%]
	      [-text% text%])

      (define snipclass%
        (class decorated-editor-snipclass%
          (define/override (make-snip stream-in) (instantiate -snip% ()))
          (super-instantiate ())))
      
      (define snipclass (make-object snipclass%))
      (send snipclass set-version 1)
      (send snipclass set-classname (format "~s" '(lib "comment-snip.ss" "framework")))
      (send (get-the-snip-class-list) add snipclass)
      
      (define bm (include-bitmap (lib "semicolon.gif" "icons")))
      
      (define (editor-keymap-mixin %)
        (class %
          (define/override (get-keymaps)
            (cons (keymap:get-file) (super get-keymaps)))
          (super-instantiate ())))
      
      (define scheme+copy-self% #f)
      (define (get-scheme+copy-self%)
        (unless scheme+copy-self%
          (set! scheme+copy-self%
                (class scheme:text%
                  (inherit copy-self-to)
                  (define/override (copy-self)
                    (let ([ed (new scheme+copy-self%)])
                      (copy-self-to ed)
                      ed))
                  (super-new))))
        scheme+copy-self%)
      
      (define -snip%
        (class* decorated-editor-snip% (readable-snip<%>)
          (inherit get-editor get-style)
          
          (define/override (make-editor) (new (get-scheme+copy-self%)))
          (define/override (make-snip) (make-object -snip%))
          (define/override (get-corner-bitmap) bm)
          (define/override (get-position) 'left-top)
          
          (define/override get-text
	    (opt-lambda (offset num [flattened? #t])
	      (let* ([super-res (super get-text offset num flattened?)]
		     [replaced (string-append "; " (regexp-replace* "\n" super-res "\n; "))])
		(if (char=? #\newline (string-ref replaced (- (string-length replaced) 1)))
		    replaced
		    (string-append replaced "\n")))))
                              
          
          (define/override (get-menu)
            (let ([menu (make-object popup-menu%)])
              (make-object menu-item% 
                (string-constant convert-to-semicolon-comment)
                menu
                (λ (x y)
                  (let ([to-ed (find-containing-editor)])
                    (when to-ed
                      (let ([this-pos (find-this-position)])
                        (when this-pos
                          (let ([from-ed (get-editor)])
                            (send to-ed begin-edit-sequence)
                            (send from-ed begin-edit-sequence)
                            (copy-contents-with-semicolons-to-position to-ed from-ed (+ this-pos 1))
                            (send to-ed delete this-pos (+ this-pos 1))
                            (send to-ed end-edit-sequence)
                            (send from-ed end-edit-sequence))))))))
              menu))
          
          (inherit get-admin)
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
          
          ;; copy-contents-with-semicolons-to-position : (is-a? text%) number -> void
          (define/private (copy-contents-with-semicolons-to-position to-ed from-ed pos)
            (let loop ([snip (find-last-snip from-ed)])
              (cond
                [snip 
                 (when (or (memq 'hard-newline (send snip get-flags))
                           (memq 'newline (send snip get-flags)))
                   (send to-ed insert "; " pos))
                 (send to-ed insert (send snip copy) pos)
                 (loop (send snip previous))]
                [else 
                 (send to-ed insert "; " pos)])))
          
          ;; find-last-snip : editor -> snip
          ;; returns the last snip in the editor
          (define/private (find-last-snip ed)
            (let loop ([snip (send ed find-first-snip)]
                       [acc (send ed find-first-snip)])
              (cond
                [snip (loop (send snip next) snip)]
                [else acc])))
          
          (define/public (read-special source line column position)
            (raise (make-special-comment "comment")))
          (super-instantiate ())
          (inherit set-snipclass)
          (set-snipclass snipclass))))))