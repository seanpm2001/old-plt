(module utils mzscheme
  (require "ast.ss")
  (require (lib "list.ss" "srfi" "1"))

  (provide fold-with-rest)
  (define (fold-with-rest f init l)
    (if (null? l)
        init
        (fold-with-rest f (f (car l) (cdr l) init) (cdr l))))
  
  (provide unique?)
  (define (unique? cs)
    (fold-with-rest (lambda (c cs acc)
                      (and acc
                           (not (member c cs))))
                    #t cs))
  
  (define (get-names ds p f)
    (filter-map (lambda (defn)
                  (and (p defn)
                       (f defn)))
                ds))    
  
  (provide map-and-fold)
  (define (map-and-fold f i l)
    (let loop ((l l)
               (mapped '())
               (folded i))
      (if (null? l)
          (values (reverse mapped) folded)
          (let-values ([(res folded) (f (car l) folded)])
            (loop (cdr l)
                  (cons res mapped)
                  folded)))))
  
  (provide map-two-values)
  (define (map-two-values f . lists)
    (let loop ((lists lists)
               (map1  '())
               (map2  '()))
      (if (any null? lists)
          (values (reverse map1) (reverse map2))
          (let-values ([(m1 m2) (apply f (map car lists))])
            (loop (map cdr lists)
                  (cons m1 map1)
                  (cons m2 map2))))))
    )
