(module heuristics mzscheme
  (provide (all-defined))
  (define step-weight (make-parameter 0))
  (define wall-threat-value (make-parameter -1))
  (define water-threat-value (make-parameter -10))
  (define blank-threat-value (make-parameter -5))
  (define wall-danger-value (make-parameter -1))
  (define water-danger-value (make-parameter -15))
  (define blank-danger-value (make-parameter -5))
  (define wall-escape-value (make-parameter 5))
  (define water-escape-value (make-parameter 5000))
  (define blank-escape-value (make-parameter 10))
  (define wall-push-value (make-parameter 0))
  (define water-push-value (make-parameter 120))
  (define blank-push-value (make-parameter 10))
  (define blank-value (make-parameter 0))
  (define home-value (make-parameter 1000))
  (define next-water-value (make-parameter -5))
  (define destination-value (make-parameter 1000))
  (define path-value (make-parameter 2))
  (define home-squares (make-parameter 10))
  (define dest-squares (make-parameter 10))
  (define path-squares (make-parameter 5))
  (define home-falloff (make-parameter .9))
  (define dest-falloff (make-parameter .9))
  (define path-falloff (make-parameter .9))
  (define home-geometric (make-parameter #t))
  (define dest-geometric (make-parameter #t))
  (define path-geometric (make-parameter #t))
  (define dvw-value (make-parameter 10))
  (define pickup-value (make-parameter 500))
  (define dropoff-value (make-parameter 1000))
  (define wall-escape-bid (make-parameter 0.5))
  (define water-escape-bid (make-parameter 1.1))
  (define blank-escape-bid (make-parameter 0.7))
  (define wall-push-bid (make-parameter 0.1))
  (define water-push-bid (make-parameter 1))
  (define blank-push-bid (make-parameter 0.3))
  (define max-bid-const (make-parameter 3)))