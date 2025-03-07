#|

Check Syntax separates two classes of identifiers,
those bound in this file and those bound by require,
and uses identifier-binding and identifier-transformer-binding
to distinguish them. 

Variables come from 'origin, 'disappeared-use, and 'disappeared-binding 
syntax properties, as well as from variable references and binding (letrec-values,
let-values, define-values) in the fully expanded text.

Variables inside #%top (not inside a module) are treated specially. 
If the namespace has a binding for them, they are colored bound color.
If the namespace does not, they are colored the unbound color.

|#

(module syncheck mzscheme
  (require (lib "string-constant.ss" "string-constants")
           (lib "unitsig.ss")
           (lib "tool.ss" "drscheme")
           (lib "class.ss")
           (lib "list.ss")
           (lib "toplevel.ss" "syntax")
           (lib "boundmap.ss" "syntax")
           (lib "bitmap-label.ss" "mrlib")
           (prefix drscheme:arrow: (lib "arrow.ss" "drscheme"))
           (prefix fw: (lib "framework.ss" "framework"))
           (lib "mred.ss" "mred"))
  (provide tool@)

  (define o (current-output-port))
  
  (define status-init (string-constant cs-status-init))
  (define status-coloring-program (string-constant cs-status-coloring-program))
  (define status-eval-compile-time (string-constant cs-status-eval-compile-time))
  (define status-expanding-expression (string-constant cs-status-expanding-expression))
    
  (define jump-to-next-bound-occurrence (string-constant cs-jump-to-next-bound-occurrence))
  (define jump-to-binding (string-constant cs-jump-to-binding))
  (define jump-to-definition (string-constant cs-jump-to-definition))
  
  (define-local-member-name
    syncheck:init-arrows
    syncheck:clear-arrows
    syncheck:add-menu
    syncheck:add-arrow
    syncheck:add-tail-arrow
    syncheck:add-mouse-over-status
    syncheck:add-jump-to-definition
    syncheck:sort-bindings-table
    syncheck:get-bindings-table
    syncheck:jump-to-next-bound-occurrence
    syncheck:jump-to-binding-occurrence
    syncheck:jump-to-definition
    
    syncheck:clear-highlighting
    syncheck:button-callback
    syncheck:add-to-cleanup-texts
    syncheck:error-report-visible?
    syncheck:clear-error-message
    
    hide-error-report
    get-error-report-text
    get-error-report-visible?)
  
  (define tool@
    (unit/sig drscheme:tool-exports^
      (import drscheme:tool^)

      (define (phase1) 
        (drscheme:unit:add-to-program-editor-mixin clearing-text-mixin))
      (define (phase2) (void))

      (define (printf . args) (apply fprintf o args))


                     
                     
                      ;;;  ;;; ;;; ;;;;; 
                     ;   ;  ;   ;    ;   
                     ;   ;  ;   ;    ;   
                     ;      ;   ;    ;   
                     ;  ;;  ;   ;    ;   
                     ;   ;  ;   ;    ;   
                     ;   ;  ;; ;;    ;   
                      ;;;    ;;;   ;;;;; 
                     
            
      ;; used for quicker debugging of the preference panel
      '(define test-preference-panel
         (λ (name f)
           (let ([frame (make-object frame% name)])
             (f frame)
             (send frame show #t))))
      
      (define-struct graphic (pos* locs->thunks draw-fn click-fn))
      
      (define-struct arrow (start-x start-y end-x end-y))
      (define-struct (var-arrow arrow)
                     (start-text start-pos-left start-pos-right
                      end-text end-pos-left end-pos-right))
      (define-struct (tail-arrow arrow) (from-text from-pos to-text to-pos))
      
      ;; id : symbol  --  the nominal-source-id from identifier-binding
      ;; filename : path
      (define-struct def-link (id filename) (make-inspector))
      
      (define tacked-var-brush (send the-brush-list find-or-create-brush "BLUE" 'solid))
      (define var-pen (send the-pen-list find-or-create-pen "BLUE" 1 'solid))
      (define tail-pen (send the-pen-list find-or-create-pen "orchid" 1 'solid))
      (define tacked-tail-brush (send the-brush-list find-or-create-brush "orchid" 'solid))
      (define untacked-brush (send the-brush-list find-or-create-brush "WHITE" 'solid))
      
      (define syncheck-text<%>
        (interface ()
          syncheck:init-arrows
          syncheck:clear-arrows
          syncheck:add-menu
          syncheck:add-arrow
          syncheck:add-tail-arrow
          syncheck:add-mouse-over-status
          syncheck:add-jump-to-definition
          syncheck:sort-bindings-table
          syncheck:get-bindings-table
          syncheck:jump-to-next-bound-occurrence
          syncheck:jump-to-binding-occurrence
          syncheck:jump-to-definition))
      
      ;; clearing-text-mixin : (mixin text%)
      ;; overrides methods that make sure the arrows go away appropriately.
      ;; adds a begin/end-edit-sequence to the insertion and deletion
      ;;  to ensure that the on-change method isn't called until after
      ;;  the arrows are cleared.
      (define clearing-text-mixin
        (mixin ((class->interface text%)) ()
          
          (inherit begin-edit-sequence end-edit-sequence)
          (define/augment (on-delete start len)
            (begin-edit-sequence)
            (inner (void) on-delete start len))
          (define/augment (after-delete start len)
            (inner (void) after-delete start len)
            (clean-up)
            (end-edit-sequence))
          
          (define/augment (on-insert start len)
            (begin-edit-sequence)
            (inner (void) on-insert start len))
          (define/augment (after-insert start len)
            (inner (void) after-insert start len)
            (clean-up)
            (end-edit-sequence))

          (define/private (clean-up)
            (let ([st (find-syncheck-text this)])
              (when (and st
                         (is-a? st drscheme:unit:definitions-text<%>))
                (let ([tab (send st get-tab)])
                  (send tab syncheck:clear-error-message)
                  (send tab syncheck:clear-highlighting)))))
          
	  (super-new)))
      
      (define make-graphics-text%
        (λ (super%)
          (let* ([cursor-arrow (make-object cursor% 'arrow)])
            (class* super% (syncheck-text<%>)
              (inherit set-cursor get-admin invalidate-bitmap-cache set-position
                       position-location
                       get-canvas last-position dc-location-to-editor-location
                       find-position begin-edit-sequence end-edit-sequence)
              
              
              ;; arrow-vectors : 
              ;; (union 
              ;;  #f
              ;;  (hash-table
              ;;    (text%
              ;;     . -o> .
              ;;    (vector (listof (union (cons (union #f sym) (menu -> void))
              ;;                           def-link
              ;;                           tail-link
              ;;                           arrow
              ;;                           string))))))
              (define arrow-vectors #f)
              
              
              ;; bindings-table : hash-table[(list text number number) -o> (listof (list text number number))]
              ;; this is a private field
              (define bindings-table (make-hash-table 'equal))
              
              ;; add-to-bindings-table : text number number text number number -> boolean
              ;; results indicates if the binding was added to the table. It is added, unless
              ;;  1) it is already there, or
              ;;  2) it is a link to itself
              (define/private (add-to-bindings-table start-text start-left start-right
                                                    end-text end-left end-right)
                (cond
                  [(and (object=? start-text end-text)
                        (= start-left end-left)
                        (= start-right end-right))
                   #f]
                  [else
                   (let* ([key (list start-text start-left start-right)]
                          [priors (hash-table-get bindings-table key (λ () '()))]
                          [new (list end-text end-left end-right)])
                     (cond
                       [(member new priors)
                        #f]
                       [else
                        (hash-table-put! bindings-table key (cons new priors))
                        #t]))]))
              
              ;; for use in the automatic test suite
              (define/public (syncheck:get-bindings-table) bindings-table)
              
              (define/public (syncheck:sort-bindings-table)
                
                ;; compare-bindings : (list text number number) (list text number number) -> boolean
                (define (compare-bindings l1 l2)
                  (let ([start-text (first l1)]
                        [start-left (second l1)]
                        [end-text (first l2)]
                        [end-left (second l2)])
                    (let-values ([(sx sy) (find-dc-location start-text start-left)]
                                 [(ex ey) (find-dc-location end-text end-left)])
                      (cond
                        [(= sy ey) (< sx ex)]
                        [else (< sy ey)]))))
                
                ;; find-dc-location : text number -> (values number number)
                (define (find-dc-location text pos)
                  (let ([bx (box 0)]
                        [by (box 0)])
                    (send text position-location pos bx by)
                    (send text editor-location-to-dc-location (unbox bx) (unbox by))))
                
                (hash-table-for-each
                 bindings-table
                 (λ (k v)
                   (hash-table-put! bindings-table k (quicksort v compare-bindings)))))
                    
              (define tacked-hash-table (make-hash-table))
              (define cursor-location #f)
              (define cursor-text #f)
              (define/private (find-poss text left-pos right-pos)
                (let ([xlb (box 0)]
                      [ylb (box 0)]
                      [xrb (box 0)]
                      [yrb (box 0)])
                  (send text position-location left-pos xlb ylb #t)
                  (send text position-location right-pos xrb yrb #f)
                  (let*-values ([(xl-off yl-off) (send text editor-location-to-dc-location (unbox xlb) (unbox ylb))]
                                [(xl yl) (dc-location-to-editor-location xl-off yl-off)]
                                [(xr-off yr-off) (send text editor-location-to-dc-location (unbox xrb) (unbox yrb))]
                                [(xr yr) (dc-location-to-editor-location xr-off yr-off)])
                    (values (/ (+ xl xr) 2)
                            (/ (+ yl yr) 2)))))
              
              ;; find-char-box : text number number -> (values number number number number)
              ;; returns the bounding box (left, top, right, bottom) for the text range.
              ;; only works right if the text is on a single line.
              (define/private (find-char-box text left-pos right-pos)
                (let ([xlb (box 0)]
                      [ylb (box 0)]
                      [xrb (box 0)]
                      [yrb (box 0)])
                  (send text position-location left-pos xlb ylb #t)
                  (send text position-location right-pos xrb yrb #f)
                  (let*-values ([(xl-off yl-off) (send text editor-location-to-dc-location (unbox xlb) (unbox ylb))]
                                [(xl yl) (dc-location-to-editor-location xl-off yl-off)]
                                [(xr-off yr-off) (send text editor-location-to-dc-location (unbox xrb) (unbox yrb))]
                                [(xr yr) (dc-location-to-editor-location xr-off yr-off)])
                    (values 
                     xl
                     yl
                     xr 
                     yr))))
              
              (define/private (update-arrow-poss arrow)
                (cond
                  [(var-arrow? arrow) (update-var-arrow-poss arrow)]
                  [(tail-arrow? arrow) (update-tail-arrow-poss arrow)]))
              
              (define/private (update-var-arrow-poss arrow)
                (let-values ([(start-x start-y) (find-poss 
                                                 (var-arrow-start-text arrow)
                                                 (var-arrow-start-pos-left arrow)
                                                 (var-arrow-start-pos-right arrow))]
                             [(end-x end-y) (find-poss 
                                             (var-arrow-end-text arrow)
                                             (var-arrow-end-pos-left arrow)
                                             (var-arrow-end-pos-right arrow))])
                  (set-arrow-start-x! arrow start-x)
                  (set-arrow-start-y! arrow start-y)
                  (set-arrow-end-x! arrow end-x)
                  (set-arrow-end-y! arrow end-y)))
              
              (define/private (update-tail-arrow-poss arrow)
                (let-values ([(start-x start-y) (find-poss 
                                                 (tail-arrow-from-text arrow)
                                                 (tail-arrow-from-pos arrow)
                                                 (+ (tail-arrow-from-pos arrow) 1))]
                             [(end-x end-y) (find-poss 
                                             (tail-arrow-to-text arrow)
                                             (tail-arrow-to-pos arrow)
                                             (+ (tail-arrow-to-pos arrow) 1))])
                  (set-arrow-start-x! arrow start-x)
                  (set-arrow-start-y! arrow start-y)
                  (set-arrow-end-x! arrow end-x)
                  (set-arrow-end-y! arrow end-y)))
              
              ;; syncheck:init-arrows : -> void
              (define/public (syncheck:init-arrows)
                (set! tacked-hash-table (make-hash-table))
                (set! arrow-vectors (make-hash-table))
                (set! bindings-table (make-hash-table 'equal))
                (let ([f (get-top-level-window)])
                  (when f
                    (send f open-status-line 'drscheme:check-syntax:mouse-over))))
              
              ;; syncheck:clear-arrows : -> void
              (define/public (syncheck:clear-arrows)
                (when (or arrow-vectors cursor-location cursor-text)
                  (let ([any-tacked? #f])
                    (when tacked-hash-table
                      (let/ec k
                        (hash-table-for-each
                         tacked-hash-table
                         (λ (key val)
                           (set! any-tacked? #t)
                           (k (void))))))
                    (set! tacked-hash-table #f)
                    (set! arrow-vectors #f)
                    (set! cursor-location #f)
                    (set! cursor-text #f)
                    (when any-tacked?
                      (invalidate-bitmap-cache))
                    (let ([f (get-top-level-window)])
                      (when f
                        (send f close-status-line 'drscheme:check-syntax:mouse-over))))))
              (define/public (syncheck:add-menu text start-pos end-pos key make-menu)
                (when (and (<= 0 start-pos end-pos (last-position)))
                  (add-to-range/key text start-pos end-pos make-menu key #t)))
              
              ;; syncheck:add-arrow : symbol text number number text number number -> void
              ;; pre: start-editor, end-editor are embedded in `this' (or are `this')
              (define/public (syncheck:add-arrow start-text start-pos-left start-pos-right
                                                 end-text end-pos-left end-pos-right)
                (let* ([arrow (make-var-arrow #f #f #f #f
                                              start-text start-pos-left start-pos-right
                                              end-text end-pos-left end-pos-right)])
                  (when (add-to-bindings-table
                         start-text start-pos-left start-pos-right
                         end-text end-pos-left end-pos-right)
                    (add-to-range/key start-text start-pos-left start-pos-right arrow #f #f)
                    (add-to-range/key end-text end-pos-left end-pos-right arrow #f #f))))
              
              ;; syncheck:add-tail-arrow : text number text number -> void
              (define/public (syncheck:add-tail-arrow from-text from-pos to-text to-pos)
                (let ([tail-arrow (make-tail-arrow #f #f #f #f to-text to-pos from-text from-pos)])
                  (add-to-range/key from-text from-pos (+ from-pos 1) tail-arrow #f #f)
                  (add-to-range/key from-text to-pos (+ to-pos 1) tail-arrow #f #f)))
              
              ;; syncheck:add-jump-to-definition : text start end id filename -> void
              (define/public (syncheck:add-jump-to-definition text start end id filename)
                (add-to-range/key text start end (make-def-link id filename) #f #f))
              
              ;; syncheck:add-mouse-over-status : text pos-left pos-right string -> void
              (define/public (syncheck:add-mouse-over-status text pos-left pos-right str)
                (add-to-range/key text pos-left pos-right str #f #f))

              ;; add-to-range/key : text number number any any boolean -> void
              ;; adds `key' to the range `start' - `end' in the editor
              ;; If use-key? is #t, it adds `to-add' with the key, and does not
              ;; replace a value with that key already there.
              ;; If use-key? is #f, it adds `to-add' without a key.
              ;; pre: arrow-vectors is not #f
              (define/private (add-to-range/key text start end to-add key use-key?)
                (let ([arrow-vector (hash-table-get 
                                     arrow-vectors
                                     text 
                                     (λ ()
                                       (let ([new-vec 
                                              (make-vector
                                               (add1 (send text last-position))
                                               null)])
                                         (hash-table-put! 
                                          arrow-vectors 
                                          text
                                          new-vec)
                                         new-vec)))])
                  (let loop ([p start])
                    (when (<= p end)
                      (let ([r (vector-ref arrow-vector p)])
                        (cond
                          [use-key?
                           (unless (ormap (λ (x) 
                                            (and (pair? x) 
                                                 (car x)
                                                 (eq? (car x) key)))
                                          r)
                             (vector-set! arrow-vector p (cons (cons key to-add) r)))]
                          [else
                           (vector-set! arrow-vector p (cons to-add r))]))
                      (loop (add1 p))))))

              (inherit get-top-level-window)

              (define/augment (on-change)
                (inner (void) on-change)
                (when arrow-vectors
                  (flush-arrow-coordinates-cache)
                  (let ([any-tacked? #f])
                    (when tacked-hash-table
                      (let/ec k
                        (hash-table-for-each
                         tacked-hash-table
                         (λ (key val)
                           (set! any-tacked? #t)
                           (k (void))))))
                    (when any-tacked?
                      (invalidate-bitmap-cache)))))
              
              ;; flush-arrow-coordinates-cache : -> void
              ;; pre-condition: arrow-vector is not #f.
              (define/private (flush-arrow-coordinates-cache)
                (hash-table-for-each
                 arrow-vectors
                 (λ (text arrow-vector)
                   (let loop ([n (vector-length arrow-vector)])
                     (unless (zero? n)
                       (let ([eles (vector-ref arrow-vector (- n 1))])
                         (for-each (λ (ele)
                                     (cond
                                       [(arrow? ele)
                                        (set-arrow-start-x! ele #f)
                                        (set-arrow-start-y! ele #f)
                                        (set-arrow-end-x! ele #f)
                                        (set-arrow-end-y! ele #f)]))
                                   eles))
                       (loop (- n 1)))))))
              
              (define/override (on-paint before dc left top right bottom dx dy draw-caret)
                (super on-paint before dc left top right bottom dx dy draw-caret)
                (when (and arrow-vectors (not before))
                  (let ([draw-arrow2
                         (λ (arrow)
                           (unless (arrow-start-x arrow)
                             (update-arrow-poss arrow))
                           (let ([start-x (arrow-start-x arrow)]
                                 [start-y (arrow-start-y arrow)]
                                 [end-x   (arrow-end-x arrow)]
                                 [end-y   (arrow-end-y arrow)])
                             (unless (and (= start-x end-x)
                                          (= start-y end-y))
                               (drscheme:arrow:draw-arrow dc start-x start-y end-x end-y dx dy))))]
                        [old-brush (send dc get-brush)]
                        [old-pen   (send dc get-pen)])
                    (hash-table-for-each tacked-hash-table
                                         (λ (arrow v) 
                                           (when v 
                                             (cond
                                               [(var-arrow? arrow)
                                                (send dc set-pen var-pen)
                                                (send dc set-brush tacked-var-brush)]
                                               [(tail-arrow? arrow)
                                                (send dc set-pen tail-pen)
                                                (send dc set-brush tacked-tail-brush)])
                                             (draw-arrow2 arrow))))
                    (when (and cursor-location
                               cursor-text)
                      (let* ([arrow-vector (hash-table-get arrow-vectors cursor-text (λ () #f))])
                        (when arrow-vector
                          (let ([eles (vector-ref arrow-vector cursor-location)])
                            (for-each (λ (ele) 
                                        (cond
                                          [(var-arrow? ele)
                                           (send dc set-pen var-pen)
                                           (send dc set-brush untacked-brush)
                                           (draw-arrow2 ele)]
                                          [(tail-arrow? ele)
                                           (send dc set-pen tail-pen)
                                           (send dc set-brush untacked-brush)
                                           (for-each-tail-arrows draw-arrow2 ele)]))
                                      eles)))))
                    (send dc set-brush old-brush)
                    (send dc set-pen old-pen))))
              
              ;; for-each-tail-arrows : (tail-arrow -> void) tail-arrow -> void
              (define/private (for-each-tail-arrows f tail-arrow)
                ;; call-f-ht ensures that `f' is only called once per arrow
                (define call-f-ht (make-hash-table))

                (define (for-each-tail-arrows/to/from tail-arrow-pos tail-arrow-text
                                                      tail-arrow-other-pos tail-arrow-other-text)

                  ;; traversal-ht ensures that we don't loop in the arrow traversal.
                  (let ([traversal-ht (make-hash-table)])
                    (let loop ([tail-arrow tail-arrow])
                      (unless (hash-table-get traversal-ht tail-arrow (λ () #f))
                        (hash-table-put! traversal-ht tail-arrow #t)
                        (unless (hash-table-get call-f-ht tail-arrow (λ () #f))
                          (hash-table-put! call-f-ht tail-arrow #t)
                          (f tail-arrow))
                        (let* ([next-pos (tail-arrow-pos tail-arrow)]
                               [next-text (tail-arrow-text tail-arrow)]
                               [arrow-vector (hash-table-get arrow-vectors next-text (λ () #f))])
                          (when arrow-vector
                            (let ([eles (vector-ref arrow-vector next-pos)])
                              (for-each (λ (ele) 
                                          (cond
                                            [(tail-arrow? ele)
                                             (let ([other-pos (tail-arrow-other-pos ele)]
                                                   [other-text (tail-arrow-other-text ele)])
                                               (when (and (= other-pos next-pos)
                                                          (eq? other-text next-text))
                                                 (loop ele)))]))
                                        eles))))))))
                
                (for-each-tail-arrows/to/from tail-arrow-to-pos tail-arrow-to-text
                                              tail-arrow-from-pos tail-arrow-from-text)
                (for-each-tail-arrows/to/from tail-arrow-from-pos tail-arrow-from-text
                                              tail-arrow-to-pos tail-arrow-to-text))
              
              ;; get-pos/text : event -> (values (union #f text%) (union number #f))
              ;; returns two #fs to indicate the event doesn't correspond to
              ;; a position in an editor, or returns the innermost text
              ;; and position in that text where the event is.
              (define/private (get-pos/text event)
                (let ([event-x (send event get-x)]
                      [event-y (send event get-y)]
                      [on-it? (box #f)])
                  (let loop ([editor this])
                    (let-values ([(x y) (send editor dc-location-to-editor-location event-x event-y)])
                      (cond
                        [(is-a? editor text%)
                         (let ([pos (send editor find-position x y #f on-it?)])
                           (cond
                             [(not (unbox on-it?)) (values #f #f)]
                             [else
                              (let ([snip (send editor find-snip pos 'after-or-none)])
                                (if (and snip
                                         (is-a? snip editor-snip%))
                                    (loop (send snip get-editor))
                                    (values pos editor)))]))]
                        [(is-a? editor pasteboard%)
                         (let ([snip (send editor find-snip x y)])
                           (if (and snip
                                    (is-a? snip editor-snip%))
                               (loop (send snip get-editor))
                               (values #f #f)))]
                        [else (values #f #f)])))))
              
            (define/override (on-event event)
              (if arrow-vectors
                  (cond
                    [(send event leaving?)
                     (when (and cursor-location cursor-text)
                       (set! cursor-location #f)
                       (set! cursor-text #f)
                       (let ([f (get-top-level-window)])
                         (when f
                           (send f update-status-line 'drscheme:check-syntax:mouse-over #f)))
                       (invalidate-bitmap-cache))
                     (super on-event event)]
                    [(or (send event moving?)
                         (send event entering?))
                     (let-values ([(pos text) (get-pos/text event)])
                       (cond
                         [(and pos text)
                          (unless (and (equal? pos cursor-location)
                                       (eq? cursor-text text))
                            (set! cursor-location pos)
                            (set! cursor-text text)
                            
                            (let* ([arrow-vector (hash-table-get arrow-vectors cursor-text (λ () #f))]
                                   [eles (and arrow-vector (vector-ref arrow-vector cursor-location))])
                              (when eles
                                (let ([has-txt? #f])
                                  (for-each (λ (ele)
                                              (cond
                                                [(string? ele)
                                                 (set! has-txt? #t)
                                                 (let ([f (get-top-level-window)])
                                                   (when f
                                                     (send f update-status-line 
                                                           'drscheme:check-syntax:mouse-over 
                                                           ele)))]))
                                            eles)
                                  (unless has-txt?
                                    (let ([f (get-top-level-window)])
                                      (when f
                                        (send f update-status-line 'drscheme:check-syntax:mouse-over #f))))))
                              
                              (when eles
                                (for-each (λ (ele)
                                            (cond
                                              [(arrow? ele)
                                               (update-arrow-poss ele)]))
                                          eles)
                                (invalidate-bitmap-cache))))]
                         [else
                          (let ([f (get-top-level-window)])
                            (when f
                              (send f update-status-line 'drscheme:check-syntax:mouse-over #f)))
                          (when (or cursor-location cursor-text)
                            (set! cursor-location #f)
                            (set! cursor-text #f)
                            (invalidate-bitmap-cache))]))
                     (super on-event event)]
                    [(send event button-down? 'right)
                     (let-values ([(pos text) (get-pos/text event)])
                       (if (and pos text)
                           (let ([arrow-vector (hash-table-get arrow-vectors text (λ () #f))])
                             (when arrow-vector
                               (let ([vec-ents (vector-ref arrow-vector pos)])
                                 (cond
                                   [(null? vec-ents)
                                    (super on-event event)]
                                   [else
                                    (let* ([menu (make-object popup-menu% #f)]
                                           [arrows (filter arrow? vec-ents)]
                                           [def-links (filter def-link? vec-ents)]
                                           [var-arrows (filter var-arrow? arrows)]
                                           [add-menus (map cdr (filter cons? vec-ents))])
                                      (unless (null? arrows)
                                        (make-object menu-item%
                                          (string-constant cs-tack/untack-arrow)
                                          menu
                                          (λ (item evt) (tack/untack-callback arrows))))
                                      (unless (null? def-links)
                                        (let ([def-link (car def-links)])
                                          (make-object menu-item%
                                            jump-to-definition
                                            menu
                                            (λ (item evt)
                                              (jump-to-definition-callback def-link)))))
                                      (unless (null? var-arrows)
                                        (make-object menu-item%
                                          jump-to-next-bound-occurrence
                                          menu
                                          (λ (item evt) (jump-to-next-callback pos text arrows)))
                                        (make-object menu-item%
                                          jump-to-binding
                                          menu
                                          (λ (item evt) (jump-to-binding-callback arrows))))
                                      (for-each (λ (f) (f menu)) add-menus)
                                      (send (get-canvas) popup-menu menu
                                            (+ 1 (inexact->exact (floor (send event get-x))))
                                            (+ 1 (inexact->exact (floor (send event get-y))))))]))))
                           (super on-event event)))]
                    [else (super on-event event)])
                  (super on-event event)))

              ;; tack/untack-callback : (listof arrow) -> void
              ;; callback for the tack/untack menu item
              (define/private (tack/untack-callback arrows)
                (let ([arrow-tacked?
                       (λ (arrow)
                         (hash-table-get
                          tacked-hash-table
                          arrow
                          (λ () #f)))]
                      [untack-arrows? #f])
                  (for-each 
                   (λ (arrow)
                     (cond
                       [(var-arrow? arrow)
                        (set! untack-arrows? (or untack-arrows? (arrow-tacked? arrow)))]
                       [(tail-arrow? arrow)
                        (for-each-tail-arrows
                         (λ (arrow) (set! untack-arrows? (or untack-arrows? (arrow-tacked? arrow))))
                         arrow)]))
                   arrows)
                  (for-each 
                   (λ (arrow)
                     (cond
                       [(var-arrow? arrow)
                        (hash-table-put! tacked-hash-table arrow (not untack-arrows?))]
                       [(tail-arrow? arrow)
                        (for-each-tail-arrows
                         (λ (arrow) 
                           (hash-table-put! tacked-hash-table arrow (not untack-arrows?)))
                         arrow)]))
                   arrows))
                (invalidate-bitmap-cache))
              
              ;; syncheck:jump-to-binding-occurrence : text -> void
              ;; jumps to the next occurrence, based on the insertion point
              (define/public (syncheck:jump-to-next-bound-occurrence text)
                (jump-to-binding/bound-helper 
                 text 
                 (λ (pos text vec-ents)
                   (jump-to-next-callback pos text vec-ents))))
              
              ;; syncheck:jump-to-binding-occurrence : text -> void
              (define/public (syncheck:jump-to-binding-occurrence text)
                (jump-to-binding/bound-helper 
                 text 
                 (λ (pos text vec-ents)
                   (jump-to-binding-callback vec-ents))))
              
              (define/private (jump-to-binding/bound-helper text do-jump)
                (let ([pos (send text get-start-position)])
                  (when arrow-vectors
                    (let ([arrow-vector (hash-table-get arrow-vectors text (λ () #f))])
                      (when arrow-vector
                        (let ([vec-ents (filter var-arrow? (vector-ref arrow-vector pos))])
                          (unless (null? vec-ents)
                            (do-jump pos text vec-ents))))))))
              
              ;; jump-to-next-callback : (listof arrow) -> void
              ;; callback for the jump popup menu item
              (define/private (jump-to-next-callback pos txt input-arrows)
                (unless (null? input-arrows)
                  (let* ([arrow-key (car input-arrows)]
                         [orig-arrows (hash-table-get bindings-table
                                                      (list (var-arrow-start-text arrow-key)
                                                            (var-arrow-start-pos-left arrow-key)
                                                            (var-arrow-start-pos-right arrow-key))
                                                      (λ () '()))])
                    (cond
                      [(null? orig-arrows) (void)]
                      [(null? (cdr orig-arrows)) (jump-to (car orig-arrows))]
                      [else
                       (let loop ([arrows orig-arrows])
                         (cond
                           [(null? arrows) (jump-to (car orig-arrows))]
                           [else (let ([arrow (car arrows)])
                                   (cond
                                     [(and (object=? txt (first arrow))
                                           (<= (second arrow) pos (third arrow)))
                                      (jump-to (if (null? (cdr arrows))
                                                   (car orig-arrows)
                                                   (cadr arrows)))]
                                     [else (loop (cdr arrows))]))]))]))))
              
              ;; jump-to : (list text number number) -> void
              (define/private (jump-to to-arrow)
                (let ([end-text (first to-arrow)]
                      [end-pos-left (second to-arrow)]
                      [end-pos-right (third to-arrow)])
                  (send end-text set-position end-pos-left end-pos-right)
                  (send end-text set-caret-owner #f 'global)))
              
              ;; jump-to-binding-callback : (listof arrow) -> void
              ;; callback for the jump popup menu item
              (define/private (jump-to-binding-callback arrows)
                (unless (null? arrows)
                  (let* ([arrow (car arrows)]
                         [start-text (var-arrow-start-text arrow)]
                         [start-pos-left (var-arrow-start-pos-left arrow)]
                         [start-pos-right (var-arrow-start-pos-right arrow)])
                    (send start-text set-position start-pos-left start-pos-right)
                    (send start-text set-caret-owner #f 'global))))

              ;; syncheck:jump-to-definition : text -> void
              (define/public (syncheck:jump-to-definition text)
                (let ([pos (send text get-start-position)])
                  (when arrow-vectors
                    (let ([arrow-vector (hash-table-get arrow-vectors text (λ () #f))])
                      (when arrow-vector
                        (let ([vec-ents (filter def-link? (vector-ref arrow-vector pos))])
                          (unless (null? vec-ents)
                            (jump-to-definition-callback (car vec-ents)))))))))
              
              (define/private (jump-to-definition-callback def-link)
                (let* ([filename (def-link-filename def-link)]
                       [id-from-def (def-link-id def-link)]
                       [frame (fw:handler:edit-file filename)])
                  (when (is-a? frame syncheck-frame<%>)
                    (send frame syncheck:button-callback id-from-def))))
              
              (super-new)))))
      
      (define syncheck-bitmap
        (bitmap-label-maker
         (string-constant check-syntax)
         (build-path (collection-path "icons") "syncheck.png")))
      
      (define syncheck-frame<%>
        (interface ()
          syncheck:button-callback
          syncheck:error-report-visible?))
      
      (define tab-mixin

        (mixin (drscheme:unit:tab<%>) ()
          (inherit is-current-tab? get-defs get-frame)
          
          (define report-error-text (new (fw:text:ports-mixin fw:scheme:text%)))
          (define error-report-visible? #f)
          (send report-error-text auto-wrap #t)
          (send report-error-text set-autowrap-bitmap #f)
          (send report-error-text lock #t)
          
          (define/public (get-error-report-text) report-error-text)
          (define/public (get-error-report-visible?) error-report-visible?)
          (define/public (turn-on-error-report) (set! error-report-visible? #t))
          (define/augment (clear-annotations)
            (inner (void) clear-annotations)
            (syncheck:clear-error-message)
            (syncheck:clear-highlighting))
          
          (define/public (syncheck:clear-error-message)
            (set! error-report-visible? #f)
            (send report-error-text clear-output-ports)
            (send report-error-text lock #f)
            (send report-error-text delete/io 0 (send report-error-text last-position))
            (send report-error-text lock #t)
            (when (is-current-tab?)
              (send (get-frame) hide-error-report)))
          
          (define cleanup-texts '())
          (define/public (syncheck:clear-highlighting)
            (let* ([definitions (get-defs)]
                   [locked? (send definitions is-locked?)])
              (send definitions begin-edit-sequence #f)
              (send definitions lock #f)
              (send definitions syncheck:clear-arrows)
              (for-each (λ (text) 
                          (send text thaw-colorer))
                        cleanup-texts)
              (set! cleanup-texts '())
              (send definitions lock locked?)
              (send definitions end-edit-sequence)))
        
          (define/augment (can-close?)
	    (and (send report-error-text can-close?)
                 (inner #t can-close?)))
          
          (define/augment (on-close)
	    (send report-error-text on-close)
	    (inner (void) on-close))
          
          ;; syncheck:add-to-cleanup-texts : (is-a?/c text%) -> void
          (define/public (syncheck:add-to-cleanup-texts txt)
            (unless (memq txt cleanup-texts)
              (send txt freeze-colorer)
              (set! cleanup-texts (cons txt cleanup-texts))))
          
          (super-new)))
      
      (define unit-frame-mixin
        (mixin (drscheme:unit:frame<%>) (syncheck-frame<%>)
          
          (inherit get-button-panel 
                   get-definitions-canvas 
                   get-definitions-text
                   get-interactions-text
                   get-current-tab)
          
          (define/augment (on-tab-change old-tab new-tab)
            (inner (void) on-tab-change old-tab new-tab)
            (if (send new-tab get-error-report-visible?)
                (show-error-report)
                (hide-error-report))
            (send report-error-canvas set-editor (send new-tab get-error-report-text)))
          
          (define/augment (enable-evaluation)
            (send check-syntax-button enable #t)
            (inner (void) enable-evaluation))
          
          (define/augment (disable-evaluation)
            (send check-syntax-button enable #f)
            (inner (void) disable-evaluation))
          
          (define report-error-parent-panel 'uninitialized-report-error-parent-panel)
          (define report-error-panel 'uninitialized-report-error-panel)
          (define report-error-canvas 'uninitialized-report-error-editor-canvas)
          (define/override (get-definitions/interactions-panel-parent)
            (set! report-error-parent-panel
                  (make-object vertical-panel%
                    (super get-definitions/interactions-panel-parent)))
            (set! report-error-panel (instantiate horizontal-panel% ()
                                       (parent report-error-parent-panel)
                                       (stretchable-height #f)
                                       (alignment '(center center))
                                       (style '(border))))
            (send report-error-parent-panel change-children (λ (l) null))
            (let ([message-panel (instantiate vertical-panel% ()
                                   (parent report-error-panel)
                                   (stretchable-width #f)
                                   (stretchable-height #f)
                                   (alignment '(left center)))])
              (make-object message% (string-constant check-syntax) message-panel)
              (make-object message% (string-constant cs-error-message) message-panel))
            (set! report-error-canvas (new editor-canvas% 
                                           (parent report-error-panel)
                                           (editor (send (get-current-tab) get-error-report-text))
                                           (line-count 3)
                                           (style '(no-hscroll))))
            (instantiate button% () 
              (label (string-constant hide))
              (parent report-error-panel)
              (callback (λ (x y) (hide-error-report)))
              (stretchable-height #t))
            (make-object vertical-panel% report-error-parent-panel))
          
          (define/public-final (syncheck:error-report-visible?)
            (and (is-a? report-error-parent-panel area-container<%>)
                 (member report-error-panel (send report-error-parent-panel get-children))))
          
          (define/public (hide-error-report) 
            (when (syncheck:error-report-visible?)
              (send report-error-parent-panel change-children
                    (λ (l) (remq report-error-panel l)))))
          
          (define/private (show-error-report)
            (unless (syncheck:error-report-visible?)
              (send report-error-parent-panel change-children
                    (λ (l) (cons report-error-panel l)))))
          
          (define rest-panel 'uninitialized-root)
          (define super-root 'uninitialized-super-root)
          (define/override (make-root-area-container % parent)
            (let* ([s-root (super make-root-area-container
                            vertical-panel%
                            parent)]
                   [r-root (make-object % s-root)])
              (set! super-root s-root)
              (set! rest-panel r-root)
              r-root))

          (inherit open-status-line close-status-line update-status-line)
          ;; syncheck:button-callback : (case-> (-> void) ((union #f syntax) -> void)
          ;; this is the only function that has any code running on the user's thread
          (define/public syncheck:button-callback
            (case-lambda
              [() (syncheck:button-callback #f)]
              [(jump-to-id)
               (when (send check-syntax-button is-enabled?)
                 (open-status-line 'drscheme:check-syntax)
                 (update-status-line 'drscheme:check-syntax status-init)
                 (let-values ([(expanded-expression expansion-completed) (make-traversal)])
                   (let* ([definitions-text (get-definitions-text)]
                          [drs-eventspace (current-eventspace)]
                          [the-tab (get-current-tab)])
                     (let-values ([(old-break-thread old-custodian) (send the-tab get-breakables)])
                       (let* ([user-namespace #f]
                              [user-directory #f]
                              [user-custodian #f]
                              [normal-termination? #f]
                              [cleanup
                               (λ () ; =drs=
                                 (send the-tab set-breakables old-break-thread old-custodian)
                                 (send the-tab enable-evaluation)
                                 (send definitions-text end-edit-sequence)
                                 (close-status-line 'drscheme:check-syntax))]
                              [kill-termination
                               (λ ()
                                 (unless normal-termination?
                                   (parameterize ([current-eventspace drs-eventspace])
                                     (queue-callback
                                      (λ ()
                                        (send the-tab syncheck:clear-highlighting)
                                        (cleanup)
                                        (custodian-shutdown-all user-custodian))))))]
                              [error-display-semaphore (make-semaphore 0)]
                              [uncaught-exception-raised
                               (λ () ;; =user=
                                 (set! normal-termination? #t)
                                 (parameterize ([current-eventspace drs-eventspace])
                                   (queue-callback
                                    (λ () ;;  =drs=
                                      (yield error-display-semaphore) ;; let error display go first
                                      (send the-tab syncheck:clear-highlighting)
                                      (cleanup)
                                      (custodian-shutdown-all user-custodian)))))]
                              [error-port (send (send the-tab get-error-report-text) get-err-port)]
                              [init-proc
                               (λ () ; =user=
                                 (send the-tab set-breakables (current-thread) (current-custodian))
                                 (set-directory definitions-text)
                                 (error-display-handler 
                                  (λ (msg exn) ;; =user=
                                    (parameterize ([current-eventspace drs-eventspace])
                                      (queue-callback
                                       (λ () ;; =drs=
                                         (send the-tab turn-on-error-report)
                                         (when (eq? (get-current-tab) the-tab)
                                           (show-error-report)))))
                                    
                                    (parameterize ([current-error-port error-port])
                                      (drscheme:debug:show-error-and-highlight 
                                       msg exn 
                                       (λ (src-to-display cms) ;; =user=
                                         (parameterize ([current-eventspace drs-eventspace])
                                           (queue-callback
                                            (λ () ;; =drs=
                                              (send (send the-tab get-ints) highlight-errors src-to-display cms)))))))
                                    
                                    (semaphore-post error-display-semaphore)))
                                 
                                 (error-print-source-location #f) ; need to build code to render error first
                                 (current-exception-handler
                                  (let ([oh (current-exception-handler)])
                                    (λ (exn)
                                      (uncaught-exception-raised)
                                      (oh exn))))
                                 (update-status-line 'drscheme:check-syntax status-expanding-expression)
                                 (set! user-custodian (current-custodian))
                                 (set! user-directory (current-directory)) ;; set by set-directory above
                                 (set! user-namespace (current-namespace)))])
                         (send the-tab disable-evaluation) ;; this locks the editor, so must be outside.
                         (send definitions-text begin-edit-sequence #f)
                         (with-lock/edit-sequence
                          definitions-text
                          (λ ()
                            (send the-tab clear-annotations)
                            (send the-tab reset-offer-kill)
                            (send (send the-tab get-defs) syncheck:init-arrows)
                            
                            (drscheme:eval:expand-program
                             (drscheme:language:make-text/pos definitions-text
                                                              0
                                                              (send definitions-text last-position))
                             (send definitions-text get-next-settings)
                             #t
                             init-proc
                             kill-termination
                             (λ (sexp loop) ; =user=
                               (cond
                                 [(eof-object? sexp)
                                  (set! normal-termination? #t)
                                  (parameterize ([current-eventspace drs-eventspace])
                                    (queue-callback
                                     (λ () ; =drs=
                                       (with-lock/edit-sequence
                                        definitions-text
                                        (λ ()
                                          (expansion-completed user-namespace user-directory)
                                          (send definitions-text syncheck:sort-bindings-table)))
                                       (cleanup)
                                       (custodian-shutdown-all user-custodian))))]
                                 [else
                                  (update-status-line 'drscheme:check-syntax status-eval-compile-time)
                                  (eval-compile-time-part-of-top-level sexp)
                                  (parameterize ([current-eventspace drs-eventspace])
                                    (queue-callback
                                     (λ () ; =drs=
                                       (with-lock/edit-sequence
                                        definitions-text
                                        (λ ()
                                          (open-status-line 'drscheme:check-syntax)
                                          (update-status-line 'drscheme:check-syntax status-coloring-program)
                                          (expanded-expression user-namespace user-directory sexp jump-to-id)
                                          (close-status-line 'drscheme:check-syntax))))))
                                  (update-status-line 'drscheme:check-syntax status-expanding-expression)
                                  (loop)]))))))))))]))

          ;; set-directory : text -> void
          ;; sets the current-directory and current-load-relative-directory
          ;; based on the file saved in the definitions-text
          (define/private (set-directory definitions-text)
            (let* ([tmp-b (box #f)]
                   [fn (send definitions-text get-filename tmp-b)])
              (unless (unbox tmp-b)
                (when fn
                  (let-values ([(base name dir?) (split-path fn)])
                    (current-directory base)
                    (current-load-relative-directory base))))))
          
          ;; with-lock/edit-sequence : text (-> void) -> void
          ;; sets and restores some state of the definitions text
          ;; so that edits to the definitions text work out.
          (define/private (with-lock/edit-sequence definitions-text thnk)
            (let* ([locked? (send definitions-text is-locked?)])
              (send definitions-text begin-edit-sequence)
              (send definitions-text lock #f)
              (thnk)
              (send definitions-text end-edit-sequence)
              (send definitions-text lock locked?)))
          
          (super-new)
          
          (define check-syntax-button
            (new button%
                 (label (syncheck-bitmap this))
                 (parent (get-button-panel))
                 (callback (λ (button evt) (syncheck:button-callback)))))
          (define/public (syncheck:get-button) check-syntax-button)
          (send (get-button-panel) change-children
                (λ (l)
                  (cons check-syntax-button
                        (remove check-syntax-button l))))))
      
      (define report-error-style (make-object style-delta% 'change-style 'slant))
      (send report-error-style set-delta-foreground "red")
      
      (define (add-check-syntax-key-bindings keymap)
        (send keymap add-function
              "check syntax"
              (λ (obj evt)
                (when (is-a? obj editor<%>)
                  (let ([canvas (send obj get-canvas)])
                    (when canvas
                      (let ([frame (send canvas get-top-level-window)])
                        (when (is-a? frame syncheck-frame<%>)
                          (send frame syncheck:button-callback))))))))
        
        (let ([jump-callback
               (λ (send-msg)
                 (λ (obj evt)
                   (when (is-a? obj text%)
                     (let ([canvas (send obj get-canvas)])
                       (when canvas
                         (let ([frame (send canvas get-top-level-window)])
                           (when (is-a? frame syncheck-frame<%>)
                             (let ([defs (send frame get-definitions-text)])
                               (when (is-a? defs syncheck-text<%>)
                                 (send-msg defs obj))))))))))])
          (send keymap add-function
                "jump to binding occurrence"
                (jump-callback (λ (defs obj) (send defs syncheck:jump-to-binding-occurrence obj))))
          (send keymap add-function
                "jump to next bound occurrence"
                (jump-callback (λ (defs obj) (send defs syncheck:jump-to-next-bound-occurrence obj))))
          (send keymap add-function
                "jump to definition (in other file)"
                (jump-callback (λ (defs obj) (send defs syncheck:jump-to-definition obj)))))
        
        (send keymap map-function "f6" "check syntax")
        (send keymap map-function "c:c;c:c" "check syntax")
        (send keymap map-function "c:x;b" "jump to binding occurrence")
        (send keymap map-function "c:x;n" "jump to next bound occurrence")
        (send keymap map-function "c:x;d" "jump to definition (in other file)"))

      (define lexically-bound-variable-style-pref 'drscheme:check-syntax:lexically-bound-identifier)
      (define imported-variable-style-pref 'drscheme:check-syntax:imported-identifier)
      
      (define lexically-bound-variable-style-name (symbol->string lexically-bound-variable-style-pref))
      (define imported-variable-style-name (symbol->string imported-variable-style-pref))

      (define error-style-name (fw:scheme:short-sym->style-name 'error))
      ;(define constant-style-name (fw:scheme:short-sym->style-name 'constant))
      
      (define (syncheck-add-to-preferences-panel parent)
        (fw:color-prefs:build-color-selection-panel parent
                                                    lexically-bound-variable-style-pref
                                                    lexically-bound-variable-style-name
                                                    (string-constant cs-lexical-variable))
        (fw:color-prefs:build-color-selection-panel parent
                                                    imported-variable-style-pref
                                                    imported-variable-style-name
                                                    (string-constant cs-imported-variable)))
      
      (fw:color-prefs:register-color-pref lexically-bound-variable-style-pref
                                          lexically-bound-variable-style-name
                                          (make-object color% 81 112 203))
      (fw:color-prefs:register-color-pref imported-variable-style-pref
                                          imported-variable-style-name
                                          (make-object color% 68 0 203))


                                          
                                          

;                                                                                                             
;                                                                                                             
;                                                                                                             
;                                                                                                   ;         
;                                                                                                   ;         
;                         ;                       ;                                                 ;         
;    ;;;  ;     ; ; ;;   ;;;;  ;;;   ;     ;     ;;;;  ; ;  ;;;   ;     ;  ;;;   ; ;   ;;;   ;;;    ;    ;;;  
;   ;     ;     ; ;;  ;   ;   ;   ;   ;   ;       ;    ;;  ;   ;   ;   ;  ;   ;  ;;   ;     ;   ;   ;   ;     
;   ;;     ;   ;  ;   ;   ;       ;    ; ;        ;    ;       ;   ;   ; ;    ;  ;    ;;        ;   ;   ;;    
;    ;;    ;   ;  ;   ;   ;    ;;;;     ;         ;    ;    ;;;;    ; ;  ;;;;;;  ;     ;;    ;;;;   ;    ;;   
;      ;    ; ;   ;   ;   ;   ;   ;    ; ;        ;    ;   ;   ;    ; ;  ;       ;       ;  ;   ;   ;      ;  
;      ;    ; ;   ;   ;   ;   ;   ;   ;   ;       ;    ;   ;   ;     ;    ;      ;       ;  ;   ;   ;      ;  
;   ;;;      ;    ;   ;    ;;  ;;;;; ;     ;       ;;  ;    ;;;;;    ;     ;;;;  ;    ;;;    ;;;;;  ;   ;;;   
;            ;                                                                                                
;            ;                                                                                                
;           ;                                                                                                 
                                                       
                                                                      

      ;; make-traversal : -> (values (namespace syntax (union #f syntax) -> void)
      ;;                             (namespace string[directory] -> void))
      ;; returns a pair of functions that close over some state that
      ;; represents the top-level of a single program. The first value
      ;; is called once for each top-level expression and the second
      ;; value is called once, after all expansion is complete.
      (define (make-traversal)
        (let* ([tl-binders (make-id-set)]
               [tl-varrefs (make-id-set)]
               [tl-high-varrefs (make-id-set)]
               [tl-tops (make-id-set)]
               [tl-requires (make-hash-table 'equal)]
               [tl-require-for-syntaxes (make-hash-table 'equal)]
               [expanded-expression
                (λ (user-namespace user-directory sexp jump-to-id)
                  (parameterize ([current-load-relative-directory user-directory])
                    (let ([is-module? (syntax-case sexp (module)
                                        [(module . rest) #t]
                                        [else #f])])
                      (cond
                        [is-module?
                         (let ([binders (make-id-set)]
                               [varrefs (make-id-set)]
                               [high-varrefs (make-id-set)]
                               [tops (make-id-set)]
                               [requires (make-hash-table 'equal)]
                               [require-for-syntaxes (make-hash-table 'equal)])
                           (annotate-basic sexp user-namespace user-directory jump-to-id
                                           binders varrefs high-varrefs tops
                                           requires require-for-syntaxes) 
                           (annotate-variables user-namespace
                                               user-directory
                                               binders
                                               varrefs
                                               high-varrefs
                                               tops
                                               requires
                                               require-for-syntaxes))]
                        [else
                         (annotate-basic sexp user-namespace user-directory jump-to-id
                                         tl-binders tl-varrefs tl-high-varrefs tl-tops 
                                         tl-requires tl-require-for-syntaxes)]))))]
               [expansion-completed
                (λ (user-namespace user-directory)
                  (parameterize ([current-load-relative-directory user-directory])
                    (annotate-variables user-namespace
                                        user-directory
                                        tl-binders
                                        tl-varrefs
                                        tl-high-varrefs
                                        tl-tops
                                        tl-requires
                                        tl-require-for-syntaxes)))])
          (values expanded-expression expansion-completed)))
      
      
      ;; type req/tag = (make-req/tag syntax sexp boolean)
      (define-struct req/tag (req-stx req-sexp used?))
      
      ;; annotate-basic : syntax 
      ;;                  namespace
      ;;                  string[directory]
      ;;                  syntax[id]
      ;;                  id-set (four of them)
      ;;                  hash-table[require-spec -> syntax] (two of them)
      ;;               -> void
      (define (annotate-basic sexp user-namespace user-directory jump-to-id
                              binders low-varrefs high-varrefs tops
                              requires require-for-syntaxes)
        (let ([tail-ht (make-hash-table)]
              [maybe-jump
               (λ (vars)
                 (when jump-to-id
                   (for-each (λ (id)
                               (let ([binding (identifier-binding id)])
                                 (when (pair? binding)
                                   (let ([nominal-source-id (list-ref binding 3)])
                                     (when (eq? nominal-source-id jump-to-id)
                                       (jump-to id))))))
                             (syntax->list vars))))])
                 
          (let level-loop ([sexp sexp]
                           [high-level? #f])
            (let* ([loop (λ (sexp) (level-loop sexp high-level?))]
                   [varrefs (if high-level? high-varrefs low-varrefs)]
                   [collect-general-info
                    (λ (stx)
                      (add-origins stx varrefs)
                      (add-disappeared-bindings stx binders varrefs)
                      (add-disappeared-uses stx varrefs))])
              (collect-general-info sexp)
              (syntax-case* sexp (lambda case-lambda if begin begin0 let-values letrec-values set!
                                   quote quote-syntax with-continuation-mark 
                                   #%app #%datum #%top #%plain-module-begin
                                   define-values define-syntaxes module
                                   require require-for-syntax provide)
                (if high-level? module-transformer-identifier=? module-identifier=?)
                [(lambda args bodies ...)
                 (begin
                   (annotate-raw-keyword sexp varrefs)
                   (annotate-tail-position/last sexp (syntax->list (syntax (bodies ...))) tail-ht)
                   (add-binders (syntax args) binders)
                   (for-each loop (syntax->list (syntax (bodies ...)))))]
                [(case-lambda [argss bodiess ...]...)
                 (begin
                   (annotate-raw-keyword sexp varrefs)
                   (for-each (λ (bodies/stx) (annotate-tail-position/last sexp 
                                                                               (syntax->list bodies/stx)
                                                                               tail-ht))
                             (syntax->list (syntax ((bodiess ...) ...))))
                   (for-each
                    (λ (args bodies)
                      (add-binders args binders)
                      (for-each loop (syntax->list bodies)))
                    (syntax->list (syntax (argss ...)))
                    (syntax->list (syntax ((bodiess ...) ...)))))]
                [(if test then else)
                 (begin
                   (annotate-raw-keyword sexp varrefs)
                   (annotate-tail-position sexp (syntax then) tail-ht)
                   (annotate-tail-position sexp (syntax else) tail-ht)
                   (loop (syntax test))
                   (loop (syntax else))
                   (loop (syntax then)))]
                [(if test then)
                 (begin
                   (annotate-raw-keyword sexp varrefs)
                   (annotate-tail-position sexp (syntax then) tail-ht)
                   (loop (syntax test))
                   (loop (syntax then)))]
                [(begin bodies ...)
                 (begin
                   (annotate-raw-keyword sexp varrefs)
                   (annotate-tail-position/last sexp (syntax->list (syntax (bodies ...))) tail-ht)
                   (for-each loop (syntax->list (syntax (bodies ...)))))]
                
                ;; treat a single body expression specially, since this has
                ;; different tail behavior.
                [(begin0 body)
                 (begin
                   (annotate-raw-keyword sexp varrefs)
                   (annotate-tail-position sexp (syntax body) tail-ht)
                   (loop (syntax body)))]
                
                [(begin0 bodies ...)
                 (begin
                   (annotate-raw-keyword sexp varrefs)
                   (for-each loop (syntax->list (syntax (bodies ...)))))]
                
                [(let-values (bindings ...) bs ...)
                 (begin
                   (annotate-raw-keyword sexp varrefs)
                   (for-each collect-general-info (syntax->list (syntax (bindings ...))))
                   (annotate-tail-position/last sexp (syntax->list (syntax (bs ...))) tail-ht)
                   (with-syntax ([(((xss ...) es) ...) (syntax (bindings ...))])
                     (for-each (λ (x) (add-binders x binders))
                               (syntax->list (syntax ((xss ...) ...))))
                     (for-each loop (syntax->list (syntax (es ...))))
                     (for-each loop (syntax->list (syntax (bs ...))))))]
                [(letrec-values (bindings ...) bs ...)
                 (begin
                   (annotate-raw-keyword sexp varrefs)
                   (for-each collect-general-info (syntax->list (syntax (bindings ...))))
                   (annotate-tail-position/last sexp (syntax->list (syntax (bs ...))) tail-ht)
                   (with-syntax ([(((xss ...) es) ...) (syntax (bindings ...))])
                     (for-each (λ (x) (add-binders x binders))
                               (syntax->list (syntax ((xss ...) ...))))
                     (for-each loop (syntax->list (syntax (es ...))))
                     (for-each loop (syntax->list (syntax (bs ...))))))]
                [(set! var e)
                 (begin
                   (annotate-raw-keyword sexp varrefs)
                   
                   ;; tops are used here because a binding free use of a set!'d variable
                   ;; is treated just the same as (#%top . x).
                   (if (identifier-binding (syntax var))
                       (add-id (if high-level? high-varrefs varrefs) (syntax var))
                       (add-id tops (syntax var)))
                   
                   (loop (syntax e)))]
                [(quote datum)
                 ;(color-internal-structure (syntax datum) constant-style-name)
                 (annotate-raw-keyword sexp varrefs)]
                [(quote-syntax datum)
                 ;(color-internal-structure (syntax datum) constant-style-name)
                 (annotate-raw-keyword sexp varrefs)]
                [(with-continuation-mark a b c)
                 (begin
                   (annotate-raw-keyword sexp varrefs)
                   (annotate-tail-position sexp (syntax c) tail-ht)
                   (loop (syntax a))
                   (loop (syntax b))
                   (loop (syntax c)))]
                [(#%app pieces ...)
                 (begin
                   (annotate-raw-keyword sexp varrefs)
                   (for-each loop (syntax->list (syntax (pieces ...)))))]
                [(#%datum . datum)
                   ;(color-internal-structure (syntax datum) constant-style-name)
                   (annotate-raw-keyword sexp varrefs)]
                [(#%top . var)
                 (begin
                   (annotate-raw-keyword sexp varrefs)
                   (when (syntax-original? (syntax var))
                     (add-id tops (syntax var))))]
                [(define-values vars b)
                 (begin
                   (annotate-raw-keyword sexp varrefs)
                   (add-binders (syntax vars) binders)
                   (maybe-jump (syntax vars))
                   (loop (syntax b)))]
                [(define-syntaxes names exp)
                 (begin
                   (annotate-raw-keyword sexp varrefs)
                   (add-binders (syntax names) binders)
                   (maybe-jump (syntax names))
                   (level-loop (syntax exp) #t))]
                [(module m-name lang (#%plain-module-begin bodies ...))
                 (begin
                   (annotate-raw-keyword sexp varrefs)
                   ((annotate-require-open user-namespace user-directory) (syntax lang))
                   (hash-table-put! requires 
                                    (syntax-object->datum (syntax lang))
                                    (cons (syntax lang)
                                          (hash-table-get requires 
                                                          (syntax-object->datum (syntax lang))
                                                          (λ () '()))))
                   (for-each loop (syntax->list (syntax (bodies ...)))))]
                
                ; top level or module top level only:
                [(require require-specs ...)
                 (let ([new-specs (map trim-require-prefix
                                       (syntax->list (syntax (require-specs ...))))])
                   (annotate-raw-keyword sexp varrefs)
                   (for-each (annotate-require-open user-namespace user-directory) new-specs)
                   (for-each (add-require-spec requires)
                             new-specs
                             (syntax->list (syntax (require-specs ...)))))]
                [(require-for-syntax require-specs ...)
                 (let ([new-specs (map trim-require-prefix (syntax->list (syntax (require-specs ...))))])
                   (annotate-raw-keyword sexp varrefs)
                   (for-each (annotate-require-open user-namespace user-directory) new-specs)
                   (for-each (add-require-spec require-for-syntaxes)
                             new-specs
                             (syntax->list (syntax (require-specs ...)))))]
                
                ; module top level only:
                [(provide provide-specs ...)
                 (let ([provided-varss (map extract-provided-vars
                                            (syntax->list (syntax (provide-specs ...))))])
                   (annotate-raw-keyword sexp varrefs)
                   (for-each (λ (provided-vars)
                               (for-each
                                (λ (provided-var)
                                  (add-id varrefs provided-var))
                                provided-vars))
                             provided-varss))]
                [id
                 (identifier? (syntax id))
                 (when (syntax-original? sexp)
                   (add-id varrefs sexp))]
                [_
                 (begin
                   '(printf "unknown stx: ~e (datum: ~e) (source: ~e)~n"
                            sexp
                            (and (syntax? sexp)
                                 (syntax-object->datum sexp))
                            (and (syntax? sexp)
                                 (syntax-source sexp)))
                   (void))])))
          (add-tail-ht-links tail-ht)))

      ;; add-disappeared-bindings : syntax id-set -> void
      (define (add-disappeared-bindings stx binders disappaeared-uses)
        (let ([prop (syntax-property stx 'disappeared-binding)])
          (when prop
            (let loop ([prop prop])
              (cond
                [(pair? prop)
                 (loop (car prop))
                 (loop (cdr prop))]
                [(identifier? prop)
                 (add-origins prop disappaeared-uses)
                 (add-id binders prop)])))))
      
      ;; add-disappeared-uses : syntax id-set -> void
      (define (add-disappeared-uses stx id-set)
        (let ([prop (syntax-property stx 'disappeared-use)])
          (when prop
            (let loop ([prop prop])
              (cond
                [(pair? prop)
                 (loop (car prop))
                 (loop (cdr prop))]
                [(identifier? prop)
                 (add-id id-set prop)])))))
      
      ;; add-require-spec : hash-table[sexp[require-spec] -o> (listof syntax)]
      ;;                 -> sexp[require-spec]
      ;;                    syntax
      ;;                 -> void
      (define (add-require-spec require-ht)
        (λ (raw-spec syntax)
          (when (syntax-original? syntax)
            (hash-table-put! require-ht
                             (syntax-object->datum raw-spec)
                             (cons syntax
                                   (hash-table-get require-ht
                                                   (syntax-object->datum raw-spec)
                                                   (λ () '())))))))
      
      ;; annotate-unused-require : syntax -> void
      (define (annotate-unused-require req/tag)
        (unless (req/tag-used? req/tag)
          (color (req/tag-req-stx req/tag) error-style-name)))

      ;; annotate-variables : namespace directory string id-set[four of them] (listof syntax) (listof syntax) -> void
      ;; colors in and draws arrows for variables, according to their classifications
      ;; in the various id-sets
      (define (annotate-variables user-namespace
                                  user-directory
                                  binders
                                  varrefs
                                  high-varrefs
                                  tops
                                  requires
                                  require-for-syntaxes)
        
        (let ([unused-requires (make-hash-table 'equal)]
              [unused-require-for-syntaxes (make-hash-table 'equal)]
              [id-sets (list binders varrefs high-varrefs tops)])
          (hash-table-for-each requires (λ (k v) (hash-table-put! unused-requires k #t)))
          (hash-table-for-each require-for-syntaxes (λ (k v) (hash-table-put! unused-require-for-syntaxes k #t)))
          
          (for-each (λ (vars) 
                      (for-each (λ (var)
                                  (when (syntax-original? var)
                                    (color-variable var identifier-binding)
                                    (make-rename-menu var id-sets)))
                                vars))
                    (get-idss binders))
          
          (for-each (λ (vars) (for-each 
                                    (λ (var)
                                      (color-variable var identifier-binding)
                                      (connect-identifier var
                                                          binders
                                                          unused-requires
                                                          requires
                                                          identifier-binding
                                                          id-sets
                                                          user-namespace 
                                                          user-directory))
                                    vars))
                    (get-idss varrefs))
          
          (for-each (λ (vars) (for-each 
                                    (λ (var)
                                      (color-variable var identifier-transformer-binding)
                                      (connect-identifier var
                                                          binders 
                                                          unused-require-for-syntaxes
                                                          require-for-syntaxes
                                                          identifier-transformer-binding
                                                          id-sets
                                                          user-namespace 
                                                          user-directory))
                                    vars))
                    (get-idss high-varrefs))
          
          (for-each 
           (λ (vars) 
             (for-each
              (λ (var) 
                (color/connect-top user-namespace user-directory binders var id-sets))
              vars))
           (get-idss tops))
          
          (color-unused require-for-syntaxes unused-require-for-syntaxes)
          (color-unused requires unused-requires)))
      
      ;; color-unused : hash-table[sexp -o> syntax] hash-table[sexp -o> #f] -> void
      (define (color-unused requires unused)
        (hash-table-for-each
         unused
         (λ (k v)
           (for-each (λ (stx) (color stx error-style-name))
                     (hash-table-get requires k)))))
      
      ;; connect-identifier : syntax
      ;;                      id-set 
      ;;                      (union #f hash-table)
      ;;                      (union #f hash-table)
      ;;                      (union identifier-binding identifier-transformer-binding)
      ;;                      (listof id-set)
      ;;                      namespace
      ;;                      directory
      ;;                   -> void
      ;; adds arrows and rename menus for binders/bindings
      (define (connect-identifier var all-binders unused requires get-binding id-sets user-namespace user-directory)
        (connect-identifier/arrow var all-binders unused requires get-binding user-namespace user-directory)
        (when (get-ids all-binders var)
          (make-rename-menu var id-sets)))
      
      ;; connect-identifier/arrow : syntax
      ;;                            id-set 
      ;;                            (union #f hash-table)
      ;;                            (union #f hash-table)
      ;;                            (union identifier-binding identifier-transformer-binding)
      ;;                         -> void
      ;; adds the arrows that correspond to binders/bindings
      (define (connect-identifier/arrow var all-binders unused requires get-binding user-namespace user-directory)
        (let ([binders (get-ids all-binders var)])
          (when binders
            (for-each (λ (x)
                        (when (syntax-original? x)
                          (connect-syntaxes x var)))
                      binders))
          
          (when (and unused requires)
            (let ([req-path/pr (get-module-req-path (get-binding var))])
              (when req-path/pr
                (let* ([req-path (car req-path/pr)]
                       [id (cdr req-path/pr)]
                       [req-stxes (hash-table-get requires req-path (λ () #f))])
                  (when req-stxes
                    (hash-table-remove! unused req-path)
                    (for-each (λ (req-stx) 
                                (when id
                                  (add-jump-to-definition
                                   var
                                   id
                                   (get-require-filename req-path user-namespace user-directory)))
                                (add-mouse-over var (format (string-constant cs-mouse-over-import)
                                                            (syntax-e var)
                                                            req-path))
                                (connect-syntaxes req-stx var))
                              req-stxes))))))))
          
      ;; get-module-req-path : binding -> (union #f (cons require-sexp sym))
      ;; argument is the result of identifier-binding or identifier-transformer-binding
      (define (get-module-req-path binding)
        (and (pair? binding)
             (let ([mod-path (list-ref binding 2)])
               (cond
                 [(module-path-index? mod-path)
                  (let-values ([(base offset) (module-path-index-split mod-path)])
                    (cons base (list-ref binding 3)))]
                 [(symbol? mod-path)
                  (cons mod-path #f)]))))
      
      ;; color/connect-top : namespace directory id-set syntax -> void
      (define (color/connect-top user-namespace user-directory binders var id-sets)
        (let ([top-bound?
               (or (get-ids binders var)
                   (parameterize ([current-namespace user-namespace])
                     (namespace-variable-value (syntax-e var) #t (λ () #f))))])
          (if top-bound?
              (color var lexically-bound-variable-style-name)
              (color var error-style-name))
          (connect-identifier var binders #f #f identifier-binding id-sets user-namespace user-directory)))
      
      ;; color-variable : syntax (union identifier-binding identifier-transformer-binding) -> void
      (define (color-variable var get-binding)
        (let* ([b (get-binding var)]
               [lexical? 
                (or (not b)
                    (eq? b 'lexical)
                    (and (pair? b)
                         (let ([path (caddr b)])
                           (and (module-path-index? path)
                                (let-values ([(a b) (module-path-index-split path)])
                                  (and (not a)
                                       (not b)))))))])
          (cond
            [lexical? (color var lexically-bound-variable-style-name)]
            [(pair? b) (color var imported-variable-style-name)])))
      
      ;; add-var : hash-table -> syntax -> void
      ;; adds the variable to the hash table.
      (define (add-var ht)
        (λ (var)
          (let* ([key (syntax-e var)]
                 [prev (hash-table-get ht key (λ () null))])
            (hash-table-put! ht key (cons var prev)))))

      ;; connect-syntaxes : syntax[original] syntax[original] -> void
      ;; adds an arrow from `from' to `to', unless they have the same source loc. 
      (define (connect-syntaxes from to)
        (let* ([from-source (syntax-source from)]
	       [to-source (syntax-source to)])
          (when (and (is-a? from-source text%)
                     (is-a? to-source text%))
            (let ([to-syncheck-text (find-syncheck-text to-source)]
                  [from-syncheck-text (find-syncheck-text from-source)])
              (when (and to-syncheck-text
                         from-syncheck-text
                         (eq? to-syncheck-text from-syncheck-text))
                (let ([pos-from (syntax-position from)]
                      [span-from (syntax-span from)]
                      [pos-to (syntax-position to)]
                      [span-to (syntax-span to)])
                  (when (and pos-from span-from pos-to span-to)
                        (let* ([from-pos-left (- (syntax-position from) 1)]
                               [from-pos-right (+ from-pos-left (syntax-span from))]
                               [to-pos-left (- (syntax-position to) 1)]
                               [to-pos-right (+ to-pos-left (syntax-span to))])
                          (unless (= from-pos-left to-pos-left)
                            (send from-syncheck-text syncheck:add-arrow
                                  from-source from-pos-left from-pos-right
                                  to-source to-pos-left to-pos-right))))))))))
      
      ;; add-mouse-over : syntax[original] string -> void
      ;; registers the range in the editor so that a mouse over
      ;; this area shows up in the status line.
      (define (add-mouse-over stx str)
        (let* ([source (syntax-source stx)])
	  (when (is-a? source text%)
            (let ([syncheck-text (find-syncheck-text source)])
              (when (and syncheck-text
                         (syntax-position stx)
                         (syntax-span stx))
                (let* ([pos-left (- (syntax-position stx) 1)]
                       [pos-right (+ pos-left (syntax-span stx))])
                  (send syncheck-text syncheck:add-mouse-over-status
                        source pos-left pos-right str)))))))
      
      ;; add-jump-to-definition : syntax symbol path -> void
      ;; registers the range in the editor so that a mouse over
      ;; this area shows up in the status line.
      (define (add-jump-to-definition stx id filename)
        (let ([source (syntax-source stx)])
          (when (is-a? source text%)
            (let ([syncheck-text (find-syncheck-text source)])
              (when (and syncheck-text
                         (syntax-position stx)
                         (syntax-span stx))
                (let* ([pos-left (- (syntax-position stx) 1)]
                       [pos-right (+ pos-left (syntax-span stx))])
                  (send syncheck-text syncheck:add-jump-to-definition
                        source
                        pos-left
                        pos-right
                        id
                        filename)))))))
      
      ;; find-syncheck-text : text% -> (union #f (is-a?/c syncheck-text<%>))
      (define (find-syncheck-text text)
        (let loop ([text text])
          (cond
            [(is-a? text syncheck-text<%>) text]
            [else 
             (let ([admin (send text get-admin)])
               (and (is-a? admin editor-snip-editor-admin<%>)
                    (let* ([enclosing-editor-snip (send admin get-snip)]
                           [editor-snip-admin (send enclosing-editor-snip get-admin)]
                           [enclosing-editor (send editor-snip-admin get-editor)])
                      (loop enclosing-editor))))])))
 
      ;; annotate-tail-position/last : (listof syntax) -> void
      (define (annotate-tail-position/last orig-stx stxs tail-ht)
        (unless (null? stxs)
          (annotate-tail-position orig-stx (car (last-pair stxs)) tail-ht)))
      
      ;; annotate-tail-position : syntax -> void
      ;; colors the parens (if any) around the argument
      ;; to indicate this is a tail call.
      (define (annotate-tail-position orig-stx tail-stx tail-ht)
        (hash-table-put!
         tail-ht 
         orig-stx 
         (cons
          tail-stx
          (hash-table-get 
           tail-ht
           orig-stx
           (λ () null)))))

      ;; annotate-require-open : namespace string -> (stx -> void)
      ;; relies on current-module-name-resolver, which in turn depends on
      ;; current-directory and current-namespace
      (define (annotate-require-open user-namespace user-directory)
	(λ (require-spec)
	  (when (syntax-original? require-spec)
	    (let ([source (syntax-source require-spec)])
	      (when (and (is-a? source text%)
			 (syntax-position require-spec)
			 (syntax-span require-spec))
                (let ([syncheck-text (find-syncheck-text source)])
                  (when syncheck-text
                    (let* ([start (- (syntax-position require-spec) 1)]
                           [end (+ start (syntax-span require-spec))]
                           [file (get-require-filename (syntax-object->datum require-spec)
                                                       user-namespace
                                                       user-directory)])
                      (when file
                        (send syncheck-text syncheck:add-menu
                              source
                              start end 
                              #f
                              (make-require-open-menu file)))))))))))
      
      ;; get-require-filename : sexp namespace string[directory] -> filename
      ;; finds the filename corresponding to the require in stx
      (define (get-require-filename datum user-namespace user-directory)
        (let* ([sym 
                (and (not (symbol? datum))
                     (parameterize ([current-namespace user-namespace]
                                    [current-directory user-directory]
                                    [current-load-relative-directory user-directory])
                       ((current-module-name-resolver) datum #f #f)))])
          (and (symbol? sym)
               (module-name-sym->filename sym))))
      
      ;; make-require-open-menu : path -> menu -> void
      (define (make-require-open-menu file)
        (λ (menu)
          (let-values ([(base name dir?) (split-path file)])
            (instantiate menu-item% ()
              (label (format (string-constant cs-open-file) (path->string name)))
              (parent menu)
              (callback (λ (x y) (fw:handler:edit-file file))))
            (void))))
      
      ;; possible-suffixes : (listof string)
      ;; these are the suffixes that are checked for the reverse 
      ;; module-path mapping.
      (define possible-suffixes '(".ss" ".scm" ""))
      
      ;; module-name-sym->filename : symbol -> (union #f string)
      (define (module-name-sym->filename sym)
        (let ([str (symbol->string sym)])
          (and ((string-length str) . > . 1)
               (char=? (string-ref str 0) #\,)
               (let ([fn (substring str 1 (string-length str))])
                 (ormap (λ (x)
                          (let ([test (string->path (string-append fn x))])
                            (and (file-exists? test)
                                 test)))
                        possible-suffixes)))))

      ;; add-origins : sexp id-set -> void
      (define (add-origins sexp id-set)
        (let ([origin (syntax-property sexp 'origin)])
          (when origin
            (let loop ([ct origin])
              (cond
                [(pair? ct) 
                 (loop (car ct))
                 (loop (cdr ct))]
                [(syntax? ct) 
                 (when (syntax-original? ct)
                   (add-id id-set ct))]
                [else (void)])))))
      
      ;; extract-provided-vars : syntax -> (listof syntax[identifier])
      (define (extract-provided-vars stx)
        (syntax-case stx (rename struct all-from all-from-except)
          [identifier
           (identifier? (syntax identifier))
           (list (syntax identifier))]
          
          [(rename local-identifier export-identifier) 
           (list (syntax local-identifier))]
          
          ;; why do I even see this?!?
          [(struct struct-identifier (field-identifier ...))
           null]
          
          [(all-from module-name) null] 
          [(all-from-except module-name identifer ...)
           null]
          [_ 
           null]))
          
      
       ;; trim-require-prefix : syntax -> syntax
      (define (trim-require-prefix require-spec)
        (let loop ([stx require-spec])
          (syntax-case stx (prefix all-except rename)
            [(prefix identifier module-name) (loop (syntax module-name))]
            [(all-except module-name identifer ...)
             (loop (syntax module-name))]
            [(rename module-name local-identifer exported-identifer)
             (loop (syntax module-name))]
            [_ stx])))
      
      ;; add-binders : syntax id-set -> void
      ;; transforms an argument list into a bunch of symbols/symbols
      ;; and puts them into the id-set
      ;; effect: colors the identifiers
      (define (add-binders stx id-set)
        (let loop ([stx stx])
          (let ([e (if (syntax? stx) (syntax-e stx) stx)])
            (cond
              [(cons? e)
               (let ([fst (car e)]
                     [rst (cdr e)])
                 (if (syntax? fst)
                     (begin
                       (add-id id-set fst)
                       (loop rst))
                     (loop rst)))]
              [(null? e) (void)]
              [else 
               (when (syntax-original? stx)
                 (add-id id-set stx))]))))
      
      ;; annotate-raw-keyword : syntax id-map -> void
      ;; annotates keywords when they were never expanded. eg.
      ;; if someone just types `(λ (x) x)' it has no 'origin
      ;; field, but there still are keywords.
      (define (annotate-raw-keyword stx id-map)
        (unless (syntax-property stx 'origin)
          (let ([lst (syntax-e stx)])
            (when (pair? lst)
              (let ([f-stx (car lst)])
                (when (and (syntax-original? f-stx)
                           (identifier? f-stx))
                  (add-id id-map f-stx)))))))
            
      ;; color-internal-structure : syntax str -> void
      (define (color-internal-structure stx style-name)
        (let ([ht (make-hash-table)]) 
          ;; ht : stx -o> true
          ;; indicates if we've seen this syntax object before
          
          (let loop ([stx stx]
                     [datum (syntax-object->datum stx)])
	    (unless (hash-table-get ht datum (λ () #f))
	      (hash-table-put! ht datum #t)
              (cond
	       [(pair? stx) 
		(loop (car stx) (car datum))
		(loop (cdr stx) (cdr datum))]
	       [(syntax? stx)
                (when (syntax-original? stx)
                  (color stx style-name))
                (let ([stx-e (syntax-e stx)]) 
                  (cond
		   [(cons? stx-e)
		    (loop (car stx-e) (car datum))
		    (loop (cdr stx-e) (cdr datum))]
		   [(null? stx-e)
		    (void)]
		   [(vector? stx-e)
		    (for-each loop
			      (vector->list stx-e)
			      (vector->list datum))]
		   [(box? stx-e)
		    (loop (unbox stx-e) (unbox datum))]
		   [else (void)]))])))))

      ;; jump-to : syntax -> void
      (define (jump-to stx)
        (let ([src (syntax-source stx)]
              [pos (syntax-position stx)]
              [span (syntax-span stx)])
          (when (and (is-a? src text%)
                     pos
                     span)
            (send src set-position (- pos 1) (+ pos span -1)))))
      
      ;; color : syntax[original] str -> void
      ;; colors the syntax with style-name's style
      (define (color stx style-name)
        (let ([source (syntax-source stx)])
          (when (is-a? source text%)
            (let ([pos (- (syntax-position stx) 1)]
                  [span (syntax-span stx)])
              (color-range source pos (+ pos span) style-name)))))
      
      ;; color-range : text start finish style-name 
      ;; colors a range in the text based on `style-name'
      (define (color-range source start finish style-name)
        (let ([style (send (send source get-style-list)
                           find-named-style
                           style-name)])
          (add-to-cleanup-texts source)
          (send source change-style style start finish #f)))

      ;; hash-table[syntax -o> (listof syntax)] -> void
      (define (add-tail-ht-links tail-ht)
        (hash-table-for-each
         tail-ht
         (λ (stx-from stx-tos)
           (for-each (λ (stx-to) (add-tail-ht-link stx-from stx-to))
                     stx-tos))))
      
      ;; add-tail-ht-link : syntax syntax -> void
      (define (add-tail-ht-link from-stx to-stx)
        (let* ([to-src (syntax-source to-stx)]
               [from-src (syntax-source from-stx)]
               [to-outermost-src (and (is-a? to-src editor<%>)
                                      (find-outermost-editor to-src))]
               [from-outermost-src (and (is-a? from-src editor<%>)
                                        (find-outermost-editor from-src))])
          (when (and (is-a? to-outermost-src syncheck-text<%>)
                     (eq? from-outermost-src to-outermost-src))
            (let ([from-pos (syntax-position from-stx)]
                  [to-pos (syntax-position to-stx)])
              (when (and from-pos to-pos)
                (send to-outermost-src syncheck:add-tail-arrow
                      from-src (- from-pos 1)
                      to-src (- to-pos 1)))))))
      
      ;; add-to-cleanup-texts : (is-a?/c editor<%>) -> void
      (define (add-to-cleanup-texts ed)
        (let ([ed (find-outermost-editor ed)])
          (when (is-a? ed drscheme:unit:definitions-text<%>)
            (let ([tab (send ed get-tab)])
              (send tab syncheck:add-to-cleanup-texts ed)))))
      
      (define (find-outermost-editor ed)
        (let loop ([ed ed])
          (let ([admin (send ed get-admin)])
            (if (is-a? admin editor-snip-editor-admin<%>)
                (let* ([enclosing-snip (send admin get-snip)]
                       [enclosing-snip-admin (send enclosing-snip get-admin)])
                  (loop (send enclosing-snip-admin get-editor)))
                ed))))
      
      ;; make-rename-menu : stx[original] (listof id-set) -> void
      (define (make-rename-menu stx id-sets)
        (let ([source (syntax-source stx)])
          (when (is-a? source text%)
            (let ([syncheck-text (find-syncheck-text source)])
              (when syncheck-text
                (let* ([name-to-offer (format "~a" (syntax-object->datum stx))]
                       [start (- (syntax-position stx) 1)]
                       [fin (+ start (syntax-span stx))])
                  (send syncheck-text syncheck:add-menu
                        source start fin (syntax-e stx)
                        (λ (menu)
                          (instantiate menu-item% ()
                            (parent menu)
                            (label (format (string-constant cs-rename-var) name-to-offer))
                            (callback
                             (λ (x y)
                               (let ([frame-parent (find-menu-parent menu)])
                                 (rename-callback name-to-offer
                                                  stx
                                                  id-sets
                                                  frame-parent)))))))))))))
      
      ;; find-parent : menu-item-container<%> -> (union #f (is-a?/c top-level-window<%>)
      (define (find-menu-parent menu)
        (let loop ([menu menu])
          (cond
            [(is-a? menu menu-bar%) (send menu get-frame)]
            [(is-a? menu popup-menu%)
             (let ([target (send menu get-popup-target)])
               (cond
                 [(is-a? target editor<%>) 
                  (let ([canvas (send target get-canvas)])
                    (and canvas
                         (send canvas get-top-level-window)))]
                 [(is-a? target window<%>) 
                  (send target get-top-level-window)]
                 [else #f]))]
            [(is-a? menu menu-item<%>) (loop (send menu get-parent))]
            [else #f])))

      ;; rename-callback : string syntax[original] (listof id-set) (union #f (is-a?/c top-level-window<%>)) -> void
      ;; callback for the rename popup menu item
      (define (rename-callback name-to-offer stx id-sets parent)
        (let ([new-sym 
               (fw:keymap:call/text-keymap-initializer
                (λ ()
                  (get-text-from-user
                   (string-constant cs-rename-id)
                   (format (string-constant cs-rename-var-to) name-to-offer)
                   parent
                   name-to-offer)))])
          (when new-sym
            (let* ([to-be-renamed 
                    (remove-duplicates
                     (quicksort 
                      (apply 
                       append
                       (map (λ (id-set) (or (get-ids id-set stx) '()))
                            id-sets))
                      (λ (x y) 
                        ((syntax-position x) . >= . (syntax-position y)))))]
                   [do-renaming?
                    (or (not (name-duplication? to-be-renamed id-sets new-sym))
                        (equal?
                         (message-box/custom
                          (string-constant check-syntax)
                          (format (string-constant cs-name-duplication-error) 
                                  new-sym)
                          (string-constant cs-rename-anyway)
                          (string-constant cancel)
                          #f
                          parent
                          '(stop default=2))
                         1))])
              (when do-renaming?
                (unless (null? to-be-renamed)
                  (let ([first-one-source (syntax-source (car to-be-renamed))])
                    (when (is-a? first-one-source text%)
                      (send first-one-source begin-edit-sequence)
                      (for-each (λ (stx) 
                                  (let ([source (syntax-source stx)])
                                    (when (is-a? source text%)
                                      (let* ([start (- (syntax-position stx) 1)]
                                             [end (+ start (syntax-span stx))])
                                        (send source delete start end #f)
                                        (send source insert new-sym start start #f)))))
                                to-be-renamed)
                      (send first-one-source invalidate-bitmap-cache)
                      (send first-one-source end-edit-sequence)))))))))
      
      ;; name-duplication? : (listof syntax) (listof id-set) symbol -> boolean
      ;; returns #t if the name chosen would be the same as another name in this scope.
      (define (name-duplication? to-be-renamed id-sets new-str)
        (let ([new-ids (map (λ (id) (datum->syntax-object id (string->symbol new-str)))
                            to-be-renamed)])
          (ormap (λ (id-set)
                   (ormap (λ (new-id) (get-ids id-set new-id)) 
                          new-ids))
                 id-sets)))
               
      ;; remove-duplicates : (listof syntax[original]) -> (listof syntax[original])
      ;; removes duplicates, based on the source locations of the identifiers
      (define (remove-duplicates ids)
        (cond
          [(null? ids) null]
          [else (let loop ([fst (car ids)]
                           [rst (cdr ids)])
                  (cond
                    [(null? rst) (list fst)]
                    [else (if (and (eq? (syntax-source fst)
                                        (syntax-source (car rst)))
                                   (= (syntax-position fst)
                                      (syntax-position (car rst))))
                              (loop fst (cdr rst))
                              (cons fst (loop (car rst) (cdr rst))))]))]))
      
      
;                                            
;                                            
;                                            
;   ;       ;                                
;           ;                                
;           ;                     ;          
;   ;    ;; ;        ;;;    ;;;  ;;;;   ;;;  
;   ;   ;  ;;       ;      ;   ;  ;    ;     
;   ;  ;    ;       ;;    ;    ;  ;    ;;    
;   ;  ;    ;        ;;   ;;;;;;  ;     ;;   
;   ;  ;    ;          ;  ;       ;       ;  
;   ;   ;  ;;          ;   ;      ;       ;  
;   ;    ;; ;       ;;;     ;;;;   ;;  ;;;   
;                                            
;                                            
;                                            

      ;; make-id-set : -> id-set
      (define (make-id-set) (make-module-identifier-mapping))
      
      ;; add-id : id-set identifier -> void
      (define (add-id mapping id)
        (let ([old (module-identifier-mapping-get mapping id (λ () '()))])
          (module-identifier-mapping-put! mapping id (cons id old))))
      
      ;; get-idss : id-set -> (listof (listof identifier))
      (define (get-idss mapping)
        (module-identifier-mapping-map mapping (λ (x y) y)))
      
      ;; get-ids : id-set identifier -> (union (listof identifier) #f)
      (define (get-ids mapping var)
        (module-identifier-mapping-get mapping var (λ () #f)))
      
      ;; for-each-ids : id-set ((listof identifier) -> void) -> void
      (define (for-each-ids mapping f)
        (module-identifier-mapping-for-each mapping (λ (x y) (f y))))

      
      ;                                                 
      ;                                                 
      ;                                                 
      ;  ;    ;    ; ;                                  
      ;  ;    ;    ;                                    
      ;  ;   ; ;   ;                                    
      ;   ;  ; ;  ;  ;   ; ;   ;;;       ;   ;   ; ;;   
      ;   ;  ; ;  ;  ;   ;;   ;   ;      ;   ;   ;;  ;  
      ;   ; ;   ; ;  ;   ;   ;    ;      ;   ;   ;    ; 
      ;   ; ;   ; ;  ;   ;   ;;;;;;      ;   ;   ;    ; 
      ;   ; ;   ; ;  ;   ;   ;           ;   ;   ;    ; 
      ;    ;     ;   ;   ;    ;          ;  ;;   ;;  ;  
      ;    ;     ;   ;   ;     ;;;;       ;; ;   ; ;;   
      ;                                          ;      
      ;                                          ;      
      ;                                          ;      

      
      (add-check-syntax-key-bindings (drscheme:rep:get-drs-bindings-keymap))
      (fw:color-prefs:add-to-preferences-panel (string-constant check-syntax)
                                               syncheck-add-to-preferences-panel)
      (drscheme:get/extend:extend-definitions-text make-graphics-text%)
      (drscheme:get/extend:extend-unit-frame unit-frame-mixin #f)
      (drscheme:get/extend:extend-tab tab-mixin))))
