
(module graph mzscheme
  (require (lib "class.ss")
           (lib "list.ss")
           (lib "math.ss")
           (lib "mred.ss" "mred")
	   (lib "contract.ss"))
  
  (provide graph-snip<%>
           graph-snip-mixin
           graph-pasteboard-mixin)
  
  (define graph-snip<%>
    (interface ()
      get-children 
      add-child
      remove-child
      
      get-parents
      add-parent
      remove-parent
      
      find-shortest-path))
  
  (define-local-member-name get-parent-links)
  
  (provide/contract (add-links
		     (case->
		      ((is-a?/c graph-snip<%>)
		       (is-a?/c graph-snip<%>)
		       . -> .
		       void?)
		      ((is-a?/c graph-snip<%>)
		       (is-a?/c graph-snip<%>)
		       (union false/c (is-a?/c pen%))
		       (union false/c (is-a?/c pen%))
		       (union false/c (is-a?/c brush%))
		       (union false/c (is-a?/c brush%))
		       . -> .
		       void?)
                      ((is-a?/c graph-snip<%>)
		       (is-a?/c graph-snip<%>)
		       (union false/c (is-a?/c pen%))
		       (union false/c (is-a?/c pen%))
		       (union false/c (is-a?/c brush%))
		       (union false/c (is-a?/c brush%))
		       number?
                       number?
                       . -> .
		       void?))))
  
  (define self-offset 10)
  
  ;; (or-2v arg ...)
  ;; like `or', except each `arg' returns two values. The
  ;; truth value of each arg is #t if both args are #t and
  ;; #f otherwise
  (define-syntax (or-2v stx)
    (syntax-case stx ()
      [(_ arg)
       (syntax arg)]
      [(_ arg args ...)
       (syntax
        (let-values ([(one two) arg])
          (if (and one two)
              (values one two)
              (or-2v args ...))))]))
  
  (define snipclass (make-object snip-class%))
  
  (define default-dark-pen (send the-pen-list find-or-create-pen "blue" 1 'solid))
  (define default-light-pen (send the-pen-list find-or-create-pen "light blue" 1 'solid))
  (define default-dark-brush (send the-brush-list find-or-create-brush "light blue" 'solid))
  (define default-light-brush (send the-brush-list find-or-create-brush "white" 'solid))
  
  (define-struct link (snip dark-pen light-pen dark-brush light-brush dx dy))
  
  ;; add-links : (is-a?/c graph-snip<%>) (is-a?/c graph-snip<%>) -> void
  ;;           : (is-a?/c graph-snip<%>) (is-a?/c graph-snip<%>) pen pen brush brush -> void
  (define add-links 
    (case-lambda
      [(parent child) (add-links parent child #f #f #f #f)]
      [(parent child dark-pen light-pen dark-brush light-brush)
       (add-links parent child dark-pen light-pen dark-brush light-brush 0 0)]
      [(parent child dark-pen light-pen dark-brush light-brush dx dy)
       (send parent add-child child)
       (send child add-parent parent dark-pen light-pen dark-brush light-brush dx dy)]))
  
  (define (graph-snip-mixin %)
    (class* % (graph-snip<%>)
      (field (children null))
      (define/public (get-children) children)
      (define/public (add-child child)
        (unless (memq child children)
          (set! children (cons child children))))
      (define/public (remove-child child)
        (when (memq child children)
          (set! children (remq child children))))
      
      (field (parent-links null))
      (define/public (get-parent-links) parent-links)
      (define/public (get-parents) (map link-snip parent-links))
      (define/public add-parent
        (case-lambda
          [(parent) (add-parent parent #f #f #f #f)]
          [(parent dark-pen light-pen dark-brush light-brush)
           (add-parent parent dark-pen light-pen dark-brush light-brush 0 0)]
          [(parent dark-pen light-pen dark-brush light-brush dx dy)
           (unless (memf (lambda (parent-link) (eq? (link-snip parent-link) parent)) parent-links)
             (set! parent-links 
                   (cons (make-link parent
                                    (or dark-pen default-dark-pen)
                                    (or light-pen default-light-pen)
                                    (or dark-brush default-dark-brush)
                                    (or light-brush default-light-brush)
                                    dx 
                                    dy)
                         parent-links)))]))
      (define/public (remove-parent parent) 
        (when (memf (lambda (parent-link) (eq? (link-snip parent-link) parent)) parent-links)
          (set! parent-links
                (remove
                 parent
                 parent-links
                 (lambda (parent parent-link) (eq? (link-snip parent-link) parent))))))
      
      (define/public (find-shortest-path other)
        (define visited-ht (make-hash-table))
        (define (first-view? n) 
          (hash-table-get visited-ht n (lambda () 
                                         (hash-table-put! visited-ht n #f)
                                         #t)))
        (let loop ((horizon (list (list this))))
          (cond
            [(null? horizon) #f]
            [(assq other horizon) => (lambda (winner) winner)]
            [else
             (let inner-loop ((paths horizon)
                              (acc '()))
               (cond
                 [(null? paths) (loop (apply append acc))]
                 [else
                  (let ((path (car paths)))
                    (inner-loop 
                     (cdr paths)
                     (cons 
                      (map (lambda (child) (cons child path)) (filter first-view? (send (car path) get-children)))
                      acc)))]))])))
      
      (super-instantiate ())
      
      (inherit set-snipclass)
      (set-snipclass snipclass)))
  
  (define graph-pasteboard<%>
    (interface ()
      on-mouse-over-snips
      set-arrowhead-params))
  
  (define-struct rect (left top right bottom))
  
  (define graph-pasteboard-mixin
    (mixin ((class->interface pasteboard%)) (graph-pasteboard<%>)
      (inherit find-first-snip find-next-selected-snip)
    
      (define arrowhead-angle-width (* 1/4 pi))
      (define arrowhead-short-side 8)
      (define arrowhead-long-side 12)
      
      (define/public (set-arrowhead-params angle-width long-side short-side)
        (set! arrowhead-angle-width angle-width)
        (set! arrowhead-short-side short-side)
        (set! arrowhead-long-side long-side))
      (define/public (get-arrowhead-params)
        (values arrowhead-angle-width
                arrowhead-long-side
                arrowhead-short-side))
    
      (inherit dc-location-to-editor-location get-canvas)
      (field (currently-overs null))
      (define/override (on-event evt)
        (cond
          [(send evt leaving?)
           (change-currently-overs null)
           (super on-event evt)]
          [(or (send evt entering?)
               (send evt moving?))
           (let ([ex (send evt get-x)]
                 [ey (send evt get-y)])
             (let-values ([(x y) (dc-location-to-editor-location ex ey)])
               (change-currently-overs (find-snips-under-mouse x y))))
           (super on-event evt)]
          [else 
           (super on-event evt)]))
      
      (define/augment (on-interactive-move evt)
        (invalidate-selected-snips)
        #;(super on-interactive-move evt)
        )
      
      (define/augment (after-interactive-move evt)
        (invalidate-selected-snips)
        #;(super on-interactive-move evt))
      
      (define/override (interactive-adjust-move snip x y)
        (invalidate-to-children/parents snip)
        (super interactive-adjust-move snip x y))
      
      (define/augment (after-insert snip before x y)
        (invalidate-to-children/parents snip)
        #;(super after-insert snip before x y))
      
      ;; invalidate-selected-snips : -> void
      ;; invalidates the region around the selected
      ;; snips and their parents and children
      (define/private (invalidate-selected-snips)
        (let loop ([snip (find-next-selected-snip #f)])
          (when snip
            (invalidate-to-children/parents snip)
            (loop (find-next-selected-snip snip)))))
      
      (define/private (add-to-rect from to rect)
        (let-values ([(xf yf wf hf) (get-position from)]
                     [(xt yt wt ht) (get-position to)])
          (make-rect
           (if rect 
               (min xf xt (rect-left rect))
               (min xf xt))
           (if rect
               (min yf yt (rect-top rect))
               (min yf yt))
           (if rect
               (max (+ xf wf) (+ xt wt) (rect-right rect))
               (max (+ xf wf) (+ xt wt)))
           (if rect
               (max (+ yf hf) (+ yt ht) (rect-bottom rect))
               (max (+ yf hf) (+ yt ht))))))
      
      
      ;; find-snips-under-mouse : num num -> (listof graph-snip<%>)
      (define/private (find-snips-under-mouse x y)
        (let loop ([snip (find-first-snip)])
          (cond
            [snip
             (let-values ([(sx sy sw sh) (get-position snip)])
               (if (and (<= sx x (+ sx sw))
                        (<= sy y (+ sy sh))
                        (is-a? snip graph-snip<%>))
                   (cons snip (loop (send snip next)))
                   (loop (send snip next))))]
            [else null])))
      
      ;; change-currently-overs : (listof snip) -> void
      (define/private (change-currently-overs new-currently-overs)
        (unless (set-equal new-currently-overs currently-overs)
          (let ([old-currently-overs currently-overs])
            (set! currently-overs new-currently-overs)
            
	    (on-mouse-over-snips currently-overs)
            (for-each 
             (lambda (old-currently-over)
               (invalidate-to-children/parents old-currently-over))
             old-currently-overs)
            (for-each
             (lambda (new-currently-over)
               (invalidate-to-children/parents new-currently-over))
             new-currently-overs))))

      (define/public (on-mouse-over-snips snips)
	(void))
        
      ;; set-equal : (listof snip) (listof snip) -> boolean
      ;; typically lists will be small (length 1),
      ;; so use andmap/memq rather than hash-tables
      (define/private (set-equal los1 los2)
        (and (andmap (lambda (s1) (memq s1 los2)) los1)
             (andmap (lambda (s2) (memq s2 los1)) los2)
             #t))
      
      ;; invalidate-to-children/parents : snip -> void
      ;; invalidates the region containing this snip and
      ;; all of its children and parents.
      (inherit invalidate-bitmap-cache)
      (define/private (invalidate-to-children/parents snip)
        (when (is-a? snip graph-snip<%>)
          (let* ([parents-and-children (append (get-all-parents snip)
                                               (get-all-children snip))]
                 [rects (eliminate-redundancies (get-rectangles snip parents-and-children))]
                 [union (union-rects rects)]
                 [invalidate-rect
                  (lambda (rect)
                    (invalidate-bitmap-cache (rect-left rect)
                                             (rect-top rect)
                                             (- (rect-right rect)
                                                (rect-left rect))
                                             (- (rect-bottom rect)
                                                (rect-top rect))))])
            (cond
              [(< (rect-area union)
                  (apply + (map (lambda (x) (rect-area x)) rects)))
               (invalidate-rect union)]
              [else
               (for-each invalidate-rect rects)]))))
      
      ;; (listof rect) -> (listof rect)
      (define/private (eliminate-redundancies rects)
        (let loop ([rects rects]
                   [acc null])
          (cond
            [(null? rects) acc]
            [else (let ([r (car rects)])
                    (cond
                      [(or (ormap (lambda (other-rect) (rect-included-in? r other-rect))
                                  (cdr rects))
                           (ormap (lambda (other-rect) (rect-included-in? r other-rect))
                                  acc))
                       (loop (cdr rects)
                             acc)]
                      [else 
                       (loop (cdr rects) 
                             (cons r acc))]))])))
      
      ;; rect-included-in? : rect rect -> boolean
      (define/private (rect-included-in? r1 r2)
        (and ((rect-left r1) . >= . (rect-left r2))
             ((rect-top r1) . >= . (rect-top r2))
             ((rect-right r1) . <= . (rect-right r2))
             ((rect-bottom r1) . <= . (rect-bottom r2))))

      ;; get-rectangles : snip (listof snip) -> rect
      ;; computes the rectangles that need to be invalidated for connecting 
      (define/private (get-rectangles main-snip c/p-snips)
        (let ([main-snip-rect (snip->rect main-snip)])
          (let loop ([c/p-snips c/p-snips])
            (cond
              [(null? c/p-snips) null]
              [else 
               (let* ([c/p (car c/p-snips)]
                      [rect
                       (if (eq? c/p main-snip)
                           (let-values ([(sx sy sw sh) (get-position c/p)])
                             (make-rect (- sx self-offset)
                                        sy
                                        (+ (+ sx sw) self-offset)
                                        (+ (+ sy sh) self-offset)))
                           (union-rects (list main-snip-rect
                                              (snip->rect c/p))))])
                 (cons rect (loop (cdr c/p-snips))))]))))

      (define/private (snip->rect snip)
        (let-values ([(sx sy sw sh) (get-position snip)])
          (make-rect sx sy (+ sx sw) (+ sy sh))))

      
      (define/private (rect-area rect)
        (* (- (rect-right rect)
              (rect-left rect))
           (- (rect-bottom rect)
              (rect-top rect))))
      
      (define/private (union-rects rects)
        (cond
          [(null? rects) (make-rect 0 0 0 0)]
          [else
           (let loop ([rects (cdr rects)]
                      [l (rect-left (car rects))]
                      [t (rect-top (car rects))]
                      [r (rect-right (car rects))]
                      [b (rect-bottom (car rects))])
             (cond
               [(null? rects) (make-rect l t r b)]
               [else
                (let ([rect (car rects)])
                  (loop (cdr rects)
                        (min l (rect-left rect))
                        (min t (rect-top rect))
                        (max r (rect-right rect))
                        (max b (rect-bottom rect))))]))]))
            
      ;; on-paint : ... -> void
      ;; see docs, same as super
      ;; draws all of the lines and then draws all of the arrow heads
      (define/private (old-on-paint before? dc left top right bottom dx dy draw-caret)
        (let ()
          ;; draw-connection : link snip boolean boolean -> void
          ;; sets the drawing context (pen and brush)
          ;; determines if the connection is between a snip and itself or two different snips
          ;;  and calls draw-self-connection or draw-non-self-connection
          (define (draw-connection from-link to dark-lines?)
            (let ([from (link-snip from-link)])
              (when (send from get-admin)
                (let ([dx (+ dx (link-dx from-link))]
                      [dy (+ dy (link-dy from-link))])
                  (cond
                    [(eq? from to)
                     (set-pen/brush from-link dark-lines?)
                     (draw-self-connection dx dy (link-snip from-link))]
                    [else
                     (draw-non-self-connection dx dy from-link dark-lines? to)])))))
          
          (define (draw-self-connection dx dy snip)
            (let*-values ([(sx sy sw sh) (get-position snip)]
                          [(s1x s1y) (values (+ sx sw) (+ sy (* sh 1/2)))]
                          [(s2x s2y) (values (+ sx sw self-offset) (+ sy (* 3/4 sh) (* 1/2 self-offset)))]
                          [(s3x s3y) (values (+ sx sw) (+ sy sh self-offset))]
                          [(b12x b12y) (values s2x s1y)]
                          [(b23x b23y) (values s2x s3y)]
                          
                          [(s4x s4y) (values (- sx arrowhead-short-side)
                                             (+ sy (* sh 1/2)))]
                          [(s5x s5y) (values (- sx arrowhead-short-side self-offset)
                                             (+ sy (* 3/4 sh) (* 1/2 self-offset)))]
                          [(s6x s6y) (values (- sx arrowhead-short-side)
                                             (+ sy sh self-offset))]
                          [(b45x b45y) (values s5x s4y)]
                          [(b56x b56y) (values s5x s6y)])
              
              (update-polygon s4x s4y sx s4y)
              (send dc draw-spline (+ dx s1x) (+ dy s1y) (+ dx b12x) (+ dy b12y) (+ dx s2x) (+ dy s2y))
              (send dc draw-spline (+ dx s2x) (+ dy s2y) (+ dx b23x) (+ dy b23y) (+ dx s3x) (+ dy s3y))
              (send dc draw-line (+ dx s3x) (+ dy s3y) (+ dx s6x) (+ dy s6y))
              (send dc draw-spline (+ dx s4x) (+ dy s4y) (+ dx b45x) (+ dy b45y) (+ dx s5x) (+ dy s5y))
              (send dc draw-spline (+ dx s5x) (+ dy s5y) (+ dx b56x) (+ dy b56y) (+ dx s6x) (+ dy s6y))
              (send dc draw-polygon points dx dy)))
          
          (define (draw-non-self-connection dx dy from-link dark-lines? to)
            (let ([from (link-snip from-link)])
              (let*-values ([(xf yf wf hf) (get-position from)]
                            [(xt yt wt ht) (get-position to)]
                            [(lf tf rf bf) (values xf yf (+ xf wf) (+ yf hf))]
                            [(lt tt rt bt) (values xt yt (+ xt wt) (+ yt ht))])
                (let ([x1 (+ xf (/ wf 2))]
                      [y1 (+ yf (/ hf 2))]
                      [x2 (+ xt (/ wt 2))]
                      [y2 (+ yt (/ ht 2))])
                  
                  (unless (or (and (x1 . <= . left)
                                   (x2 . <= . left))
                              (and (x1 . >= . right)
                                   (x2 . >= . right))
                              (and (y1 . <= . top)
                                   (y2 . <= . top))
                              (and (y1 . >= . bottom)
                                   (y2 . >= . bottom)))
                    (set-pen/brush from-link dark-lines?)
                    (let-values ([(from-x from-y)
                                  (or-2v (find-intersection x1 y1 x2 y2 
                                                            lf tf rf tf)
                                         (find-intersection x1 y1 x2 y2 
                                                            lf bf rf bf)
                                         (find-intersection x1 y1 x2 y2 
                                                            lf tf lf bf)
                                         (find-intersection x1 y1 x2 y2 
                                                            rf tf rf bf))]
                                 [(to-x to-y)
                                  (or-2v (find-intersection x1 y1 x2 y2 
                                                            lt tt rt tt)
                                         (find-intersection x1 y1 x2 y2 
                                                            lt bt rt bt)
                                         (find-intersection x1 y1 x2 y2 
                                                            lt tt lt bt)
                                         (find-intersection x1 y1 x2 y2 
                                                            rt tt rt bt))])
                      (when (and from-x from-y to-x to-y)
                        (let ()
                          (define (arrow-point-ok? point-x point-y)
                            (and (in-rectangle? point-x point-y
                                                (min lt rt lf rf) (min tt bt tf bf)
                                                (max lt rt lf rf) (max tt bt tf bf))
                                 (not (strict-in-rectangle? point-x point-y 
                                                            (min lt rt) (min tt bt) 
                                                            (max lt rt) (max tt bt)))
                                 (not (strict-in-rectangle? point-x point-y
                                                            (min lf rf) (min tf bf)
                                                            (max lf rf) (max tf bf)))))
                          (cond
                            [(or (in-rectangle? from-x from-y lt tt rt bt)
                                 (in-rectangle? to-x to-y lf tf rf bf))
                             ;; the snips overlap, draw nothing
                             (void)]
                            [else
                             (send dc draw-line
                                   (+ dx from-x) (+ dy from-y) 
                                   (+ dx to-x) (+ dy to-y))
                             (update-polygon from-x from-y to-x to-y)
                             (when (and (arrow-point-ok? (send point1 get-x) (send point1 get-y))
                                        (arrow-point-ok? (send point2 get-x) (send point2 get-y))
                                        (arrow-point-ok? (send point3 get-x) (send point3 get-y))
                                        (arrow-point-ok? (send point4 get-x) (send point4 get-y)))
                               ;; the arrowhead is not overlapping the snips, so draw it
                               ;; (this is only an approximate test, but probably good enough)
                               (send dc draw-polygon points dx dy))])))))))))
          
          (define (set-pen/brush from-link dark-lines?)
            (send dc set-brush 
                  (if dark-lines?
                      (link-dark-brush from-link)
                      (link-light-brush from-link)))
            (send dc set-pen
                  (if dark-lines?
                      (link-dark-pen from-link)
                      (link-light-pen from-link))))
          
          ;;; body of on-paint
          (when before?
            (let ([old-pen (send dc get-pen)]
                  [old-brush (send dc get-brush)]
                  [os (send dc get-smoothing)])
              (send dc set-smoothing 'aligned)
              
              (let loop ([snip (find-first-snip)])
                (when snip
                  (when (and (send snip get-admin)
                             (is-a? snip graph-snip<%>))
                    (for-each (lambda (parent-link)
                                (draw-connection parent-link snip #f))
                              (send snip get-parent-links)))
                  (loop (send snip next))))
              
              (for-each
               (lambda (currently-over)
                 (for-each
                  (lambda (child)
                    (let ([parent-link-f
                           (memf (lambda (parent-link) (eq? currently-over (link-snip parent-link)))
                                 (send child get-parent-links))])
                      (when parent-link-f
                        (draw-connection (car parent-link-f) child #t))))
                  (send currently-over get-children))
                 (for-each
                  (lambda (parent-link)
                    (draw-connection parent-link currently-over #t))
                  (send currently-over get-parent-links)))
               currently-overs)
              
              (send dc set-smoothing os)
              (send dc set-pen old-pen)
              (send dc set-brush old-brush)))
          
          (super on-paint before? dc left top right bottom dx dy draw-caret)))
      
      (define/override (on-paint before? dc left top right bottom dx dy draw-caret)
        (let ()
          ;; draw-connection : link snip boolean boolean -> void
          ;; sets the drawing context (pen and brush)
          ;; determines if the connection is between a snip and itself or two different snips
          ;;  and calls draw-self-connection or draw-non-self-connection
          (define (draw-connection from-link to dark-lines?)
            (let ([from (link-snip from-link)])
              (when (send from get-admin)
                (let ([dx (+ dx (link-dx from-link))]
                      [dy (+ dy (link-dy from-link))])
                  (cond
                    [(eq? from to)
                     (set-pen/brush from-link dark-lines?)
                     (draw-self-connection dx dy (link-snip from-link))]
                    [else
                     (draw-non-self-connection dx dy from-link dark-lines? to)])))))
          
          (define (draw-self-connection dx dy snip)
            (let*-values ([(sx sy sw sh) (get-position snip)]
                          [(s1x s1y) (values (+ sx sw) (+ sy (* sh 1/2)))]
                          [(s2x s2y) (values (+ sx sw self-offset) (+ sy (* 3/4 sh) (* 1/2 self-offset)))]
                          [(s3x s3y) (values (+ sx sw) (+ sy sh self-offset))]
                          [(b12x b12y) (values s2x s1y)]
                          [(b23x b23y) (values s2x s3y)]
                          
                          [(s4x s4y) (values (- sx arrowhead-short-side)
                                             (+ sy (* sh 1/2)))]
                          [(s5x s5y) (values (- sx arrowhead-short-side self-offset)
                                             (+ sy (* 3/4 sh) (* 1/2 self-offset)))]
                          [(s6x s6y) (values (- sx arrowhead-short-side)
                                             (+ sy sh self-offset))]
                          [(b45x b45y) (values s5x s4y)]
                          [(b56x b56y) (values s5x s6y)])
              
              (update-polygon s4x s4y sx s4y)
              (send dc draw-spline (+ dx s1x) (+ dy s1y) (+ dx b12x) (+ dy b12y) (+ dx s2x) (+ dy s2y))
              (send dc draw-spline (+ dx s2x) (+ dy s2y) (+ dx b23x) (+ dy b23y) (+ dx s3x) (+ dy s3y))
              (send dc draw-line (+ dx s3x) (+ dy s3y) (+ dx s6x) (+ dy s6y))
              (send dc draw-spline (+ dx s4x) (+ dy s4y) (+ dx b45x) (+ dy b45y) (+ dx s5x) (+ dy s5y))
              (send dc draw-spline (+ dx s5x) (+ dy s5y) (+ dx b56x) (+ dy b56y) (+ dx s6x) (+ dy s6y))
              (send dc draw-polygon points dx dy)))
          
          (define (draw-non-self-connection dx dy from-link dark-lines? to)
            (let ([from (link-snip from-link)])
              (let*-values ([(xf yf wf hf) (get-position from)]
                            [(xt yt wt ht) (get-position to)]
                            [(lf tf rf bf) (values xf yf (+ xf wf) (+ yf hf))]
                            [(lt tt rt bt) (values xt yt (+ xt wt) (+ yt ht))])
                (let ([x1 (+ xf (/ wf 2))]
                      [y1 (+ yf (/ hf 2))]
                      [x2 (+ xt (/ wt 2))]
                      [y2 (+ yt (/ ht 2))])
                  
                  (set-pen/brush from-link dark-lines?)
                  (let-values ([(from-x from-y)
                                (or-2v (find-intersection x1 y1 x2 y2 
                                                          lf tf rf tf)
                                       (find-intersection x1 y1 x2 y2 
                                                          lf bf rf bf)
                                       (find-intersection x1 y1 x2 y2 
                                                          lf tf lf bf)
                                       (find-intersection x1 y1 x2 y2 
                                                          rf tf rf bf))]
                               [(to-x to-y)
                                (or-2v (find-intersection x1 y1 x2 y2 
                                                          lt tt rt tt)
                                       (find-intersection x1 y1 x2 y2 
                                                          lt bt rt bt)
                                       (find-intersection x1 y1 x2 y2 
                                                          lt tt lt bt)
                                       (find-intersection x1 y1 x2 y2 
                                                          rt tt rt bt))])
                    (when (and from-x from-y to-x to-y)
                      (let ()
                        (define (arrow-point-ok? point-x point-y)
                          (and (in-rectangle? point-x point-y
                                              (min lt rt lf rf) (min tt bt tf bf)
                                              (max lt rt lf rf) (max tt bt tf bf))
                               (not (strict-in-rectangle? point-x point-y 
                                                          (min lt rt) (min tt bt) 
                                                          (max lt rt) (max tt bt)))
                               (not (strict-in-rectangle? point-x point-y
                                                          (min lf rf) (min tf bf)
                                                          (max lf rf) (max tf bf)))))
                        (cond
                          [(or (in-rectangle? from-x from-y lt tt rt bt)
                               (in-rectangle? to-x to-y lf tf rf bf))
                           ;; the snips overlap, draw nothing
                           (void)]
                          [else
                           (send dc draw-line
                                 (+ dx from-x) (+ dy from-y) 
                                 (+ dx to-x) (+ dy to-y))
                           (update-polygon from-x from-y to-x to-y)
                           (when (and (arrow-point-ok? (send point1 get-x) (send point1 get-y))
                                      (arrow-point-ok? (send point2 get-x) (send point2 get-y))
                                      (arrow-point-ok? (send point3 get-x) (send point3 get-y))
                                      (arrow-point-ok? (send point4 get-x) (send point4 get-y)))
                             ;; the arrowhead is not overlapping the snips, so draw it
                             ;; (this is only an approximate test, but probably good enough)
                             (send dc draw-polygon points dx dy))]))))))))
          
          (define (set-pen/brush from-link dark-lines?)
            (send dc set-brush 
                  (if dark-lines?
                      (link-dark-brush from-link)
                      (link-light-brush from-link)))
            (send dc set-pen
                  (if dark-lines?
                      (link-dark-pen from-link)
                      (link-light-pen from-link))))
          
          ;;; body of on-paint
          (when before?
            (let ([old-pen (send dc get-pen)]
                  [old-brush (send dc get-brush)]
                  [os (send dc get-smoothing)])
              (send dc set-smoothing 'aligned)
              
              (let ([pairs '()])
                (for-each-to-redraw 
                 left top right bottom 
                 (lambda (from-link to)
                   (let ([from (link-snip from-link)])
                     (cond
                       [(or (memq from currently-overs)
                            (memq to currently-overs))
                        (set! pairs (cons (cons from-link to) pairs))]
                       [else
                        (draw-connection from-link to #f)]))))
                (for-each (lambda (pr)
                            (draw-connection (car pr) (cdr pr) #t))
                          pairs))
              
              (send dc set-smoothing os)
              (send dc set-pen old-pen)
              (send dc set-brush old-brush)))
          
          (super on-paint before? dc left top right bottom dx dy draw-caret)))
      
        ;; for-each-to-redraw : number number number number (link snip -> void)
      (define/private (for-each-to-redraw left top right bottom f)
        (let ()
          ;; draw-connection : link snip boolean boolean -> void
          ;; sets the drawing context (pen and brush)
          ;; determines if the connection is between a snip and itself or two different snips
          ;;  and calls draw-self-connection or draw-non-self-connection
          (define (maybe-call-f from-link to)
            (let ([from (link-snip from-link)])
              (when (send from get-admin)
                (cond
                  [(eq? from to)
                   (f from-link to)]
                  [else
                   (let*-values ([(xf yf wf hf) (get-position from)]
                                 [(xt yt wt ht) (get-position to)]
                                 [(lf tf rf bf) (values xf yf (+ xf wf) (+ yf hf))]
                                 [(lt tt rt bt) (values xt yt (+ xt wt) (+ yt ht))])
                     (let ([x1 (+ xf (/ wf 2))]
                           [y1 (+ yf (/ hf 2))]
                           [x2 (+ xt (/ wt 2))]
                           [y2 (+ yt (/ ht 2))])
                       
                       (unless (or (and (x1 . <= . left)
                                        (x2 . <= . left))
                                   (and (x1 . >= . right)
                                        (x2 . >= . right))
                                   (and (y1 . <= . top)
                                        (y2 . <= . top))
                                   (and (y1 . >= . bottom)
                                        (y2 . >= . bottom)))
                         (f from-link to))))]))))
          
          (let loop ([snip (find-first-snip)])
            (when snip
              (when (and (send snip get-admin)
                         (is-a? snip graph-snip<%>))
                (for-each (lambda (parent-link) (maybe-call-f parent-link snip))
                          (send snip get-parent-links)))
              (loop (send snip next))))))
      
      
      (field 
       [point1 (make-object point% 0 0)]
       [point2 (make-object point% 0 0)]
       [point3 (make-object point% 0 0)]
       [point4 (make-object point% 0 0)]
       [points (list point1 point2 point3 point4)])
      
      ;; update-polygon : number^4 -> void
      ;; updates points1, 2, and 3 with the arrow head's
      ;; points. Use a turtle-like movement to find the points.
      ;; point3 is the point where the line should end.
      (define/private (update-polygon from-x from-y to-x to-y)
        (define (move tx ty ta d) (values (+ tx (* d (cos ta)))
                                          (+ ty (* d (sin ta)))
                                          ta))
        (define (turn tx ty ta a) (values tx
                                          ty
                                          (+ ta a)))
        (define init-angle 
          (cond
            [(and (from-x . = . to-x)
                  (from-y . < . to-y))
             (* pi 3/2)]
            [(from-x . = . to-x)
             (* pi 1/2)]
            [(from-x . < . to-x)
             (+ pi (atan (/ (- from-y to-y) (- from-x to-x))))]
            [else
             (atan (/ (- from-y to-y) (- from-x to-x)))]))
        (let*-values ([(t1x t1y t1a) (values to-x to-y init-angle)]
                      [(t2x t2y t2a) (turn t1x t1y t1a (/ arrowhead-angle-width 2))]
                      [(t3x t3y t3a) (move t2x t2y t2a arrowhead-long-side)]
                      [(t4x t4y t4a) (turn t1x t1y t1a (- (/ arrowhead-angle-width 2)))]
                      [(t5x t5y t5a) (move t4x t4y t4a arrowhead-long-side)]
                      [(t6x t6y t6a) (move t1x t1y t1a arrowhead-short-side)])
          (send point1 set-x t1x)
          (send point1 set-y t1y)
          (send point2 set-x t3x)
          (send point2 set-y t3y)
          (send point3 set-x t6x)
          (send point3 set-y t6y)
          (send point4 set-x t5x)
          (send point4 set-y t5y)))
      
      (define/private (should-hilite? snip)
        (let ([check-one-way
               (lambda (way)
                 (let loop ([snip snip])
                   (or (memq snip currently-overs)
                       (and (is-a? snip graph-snip<%>)
                            (loop (car (way snip)))))))])
          (or (check-one-way (lambda (snip) (send snip get-children)))
              (check-one-way (lambda (snip) (send snip get-parents))))))
      
      (inherit get-snip-location)
      (field [lb (box 0)]
             [tb (box 0)]
             [rb (box 0)]
             [bb (box 0)])
      (define/private (get-position snip)
        (get-snip-location snip lb tb #f)
        (get-snip-location snip rb bb #t)
        (values (unbox lb)
                (unbox tb)
                (- (unbox rb) (unbox lb))
                (- (unbox bb) (unbox tb))))
      
      (super-new)))
  
  ;; in-rectangle? : number^2 number^2 number^2 -> boolean
  ;; determines if (x,y) is in the rectangle described
  ;; by (p1x,p1y) and (p2x,p2y).
  (define (in-rectangle? x y p1x p1y p2x p2y)
    (and (<= (min p1x p2x) x (max p1x p2x))
         (<= (min p1y p2y) y (max p1y p2y))))
  
  ;; strict-in-rectangle? : number^2 number^2 number^2 -> boolean
  ;; determines if (x,y) is in the rectangle described
  ;; by (p1x,p1y) and (p2x,p2y), but not on the border
  (define (strict-in-rectangle? x y p1x p1y p2x p2y)
    (and (< (min p1x p2x) x (max p1x p2x))
         (< (min p1y p2y) y (max p1y p2y))))
  
  ;; find-intersection : number^8 -> (values (union #f number) (union #f number))
  ;; calculates the intersection between two line segments, 
  ;; described as pairs of points. Returns #f if they do not intersect
  (define (find-intersection x1 y1 x2 y2 x3 y3 x4 y4)
    (let-values ([(m1 b1) (find-mb x1 y1 x2 y2)]
                 [(m2 b2) (find-mb x3 y3 x4 y4)])
      (let-values ([(int-x int-y)
                    (cond
                      [(and m1 m2 b1 b2
                            (= m1 0)
                            (= m2 0))
                       (values #f #f)]
                      [(and m1 m2 b1 b2
                            (= m1 0))
                       (let* ([y y1]
                              [x (/ (- y b2) m2)])
                         (values x y))]
                      [(and m1 m2 b1 b2
                            (= m2 0))
                       (let* ([y y3]
                              [x (/ (- y b1) m1)])
                         (values x y))]
                      [(and m1 m2 b1 b2
                            (not (= m1 m2)))
                       (let* ([y (/ (- b2 b1) (- m1 m2))]
                              [x (/ (- y b1) m1)])
                         (values x y))]
                      [(and m1 b1)
                       (let* ([x x3]
                              [y (+ (* m1 x) b1)])
                         (values x y))]
                      [(and m2 b2)
                       (let* ([x x1]
                              [y (+ (* m2 x) b2)])
                         (values x y))]
                      [else 
                       (values #f #f)])])
        
        (if (and int-x
                 int-y
                 (<= (min x1 x2) int-x (max x1 x2))
                 (<= (min y1 y2) int-y (max y1 y2))
                 (<= (min x3 x4) int-x (max x3 x4))
                 (<= (min y3 y4) int-y (max y3 y4)))
            (values int-x int-y)
            (values #f #f)))))
  
  ;; find-mb : number number number number -> (values (union #f number) (union #f number))
  ;; finds the "m" and "b" constants that describe the
  ;; lines from (x1, y1) to (x2, y2)
  (define (find-mb x1 y1 x2 y2)
    (if (= x1 x2)
        (values #f #f)
        (let-values ([(xl yl xr yr)
                      (if (x1 . <= . x2)
                          (values x1 y1 x2 y2)
                          (values x2 y2 x1 y1))])
          (let* ([m (/ (- yr yl) (- xr xl))]
                 [b (- y1 (* m x1))])
            (values m b)))))
  
  ;; get-all-relatives : (snip -> (listof snip)) snip -> (listof snip)
  ;; returns all editor-snip relatives (of a particular sort), including
  ;; any regular snip relatives along the way.
  (define (get-all-relatives get-relatives snip)
    (let loop ([flat-relatives (get-relatives snip)]
               [relatives null])
      (cond
        [(null? flat-relatives) relatives]
        [else
         (let i-loop ([dummy (car flat-relatives)]
                      [acc relatives])
           (cond
             [(is-a? dummy graph-snip<%>)
              (loop (cdr flat-relatives) (cons dummy acc))]
             [else
              (i-loop (car (get-relatives dummy))
                      (cons dummy acc))]))])))
  
  ;; get-all-children : snip -> (listof snip)
  (define (get-all-children snip)
    (get-all-relatives (lambda (snip) (send snip get-children)) snip))
  
  ;; get-all-parents : snip -> (listof snip)
  (define (get-all-parents snip)
    (get-all-relatives (lambda (snip) (send snip get-parents)) snip)))
  
