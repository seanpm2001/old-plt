;; I believe this file is dead now.
;; should require response.ss instead
(require (lib "list.ss")
         (lib "xml.ss" "xml")
         (lib "port.ss")
         (lib "contract.ss"))



; more here - these should really have a common super type, but I don't want to break
; the existing interface.
(define-struct response/full (code message seconds mime extras body) (make-inspector))
(define-struct (response/incremental response/full) ())

; response = (cons str (listof str)), where the first str is a mime-type
;          | x-expression
;          | (make-response/full nat str nat str (listof (cons sym str)) (listof str))
;          | (make-response/incremental nat str nat str (listof (cons sym str))
;              ((str -> void) -> void))

; TST -> bool
(define (response? page)
  (or (response/full? page)
      ; this could fail for dotted lists - rewrite andmap
      (and (pair? page) (pair? (cdr page)) (andmap string? page))
      ; insist the xexpr has a root element
      (and (pair? page) (xexpr? page))))


;; ********************************************************************************
(define-struct response (o-port close? code message seconds mime headers))
(define-struct (response/full response) (body))
(define-struct (response/incremental response) (generator))

;; output-response/file
;; default the headers, code = 200, message = "Okay"
;; compute the seconds based on the file
;; compute the mime-type based on the file

;; output-response/x-expression
;; default the headers, code = 200, message = "Okay"


;; **************************************************
;; what do you need in order to respond to a request?
;;
;; 1. You need to have an output port
;; 2. You need to know the protocol version
;; 3. You need to know the method
;; 4. You need some header gunk
;; 5. You need a procedure to generate the body of the response




(provide/contract
 [output-headers (connection? number? string? list? number? string? . -> . void)]
 [output-file (path? number? symbol? connection? . -> . void)]
 [output-page/port (connection? response? . -> . void)]
 )

;; **************************************************
;; output-headers:

; output-headers : connection Nat String (listof (listof String)) Nat String -> Void
(define output-headers
  (case-lambda
    [(conn code message extras seconds mime)
     (let ([out (connection-o-port conn)])
       (for-each (lambda (line)
                   (for-each (lambda (word) (display word out)) line)
                   (display #\return out)
                   (newline out))
                 (list* `("HTTP/1.1 " ,code " " ,message)
                        `("Date: " ,(seconds->gmt-string (current-seconds)))
                        `("Last-Modified: " ,(seconds->gmt-string seconds))
                        `("Server: PLT Scheme")
                        `("Content-type: " ,mime)
                        ; more here - consider removing Connection fields
                        ; from extras or raising an error
                        (if (connection-close? conn)
                            (cons `("Connection: close") extras)
                            extras)))
       (display #\return out)
       (newline out))]
    [(conn code message extras)
     (output-headers conn code message extras (current-seconds) TEXT/HTML-MIME-TYPE)]
    [(conn code message)
     (output-headers conn code message '() (current-seconds) TEXT/HTML-MIME-TYPE)]))

(define TEXT/HTML-MIME-TYPE "text/html")

; seconds->gmt-string : Nat -> String
; format is rfc1123 compliant according to rfc2068 (http/1.1)
(define (seconds->gmt-string s)
  (let* ([local-date (seconds->date s)]
         [date (seconds->date (- s
                                 (date-time-zone-offset local-date)
                                 (if (date-dst? local-date) 3600 0)))])
    (format "~a, ~a ~a ~a ~a:~a:~a GMT"
            (vector-ref DAYS (date-week-day date))
            (two-digits (date-day date))
            (vector-ref MONTHS (sub1 (date-month date)))
            (date-year date)
            (two-digits (date-hour date))
            (two-digits (date-minute date))
            (two-digits (date-second date)))))

; two-digits : num -> str
(define (two-digits n)
  (let ([str (number->string n)])
    (if (< n 10) (string-append "0" str) str)))

(define MONTHS
  #("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))

(define DAYS
  #("Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat"))

;; output-headers/response/full: connection response/full extras ->
;; see def of output-headers for datadef of extras
;; unpack response/full and call output-headers
(define (output-headers/response/full conn r/full extras)
  (output-headers conn
                  (response/full-code r/full)
                  (response/full-message r/full)
                  extras
                  (response/full-seconds r/full)
                  (response/full-mime r/full)))


;; **************************************************
;; output-page/port




; output-page/port : connection response -> void
(define (output-page/port conn page)
  (let ([out (connection-o-port conn)]
        [close (connection-close? conn)])
    ; double check what happens on erronious servlet output
    ; it should output an error for this response
    (cond
      [(response/full? page)
       (cond
         [(response/incremental? page)
          (output-headers/response/full
           conn page
           (if close
               null
               `(("Transfer-Encoding: chunked")
                 . ,(map (lambda (x) (list (symbol->string (car x)) ": " (cdr x)))
                         (response/full-extras page)))))
          (if close
              ; WARNING: This is unreliable because the client can not distinguish between
              ; a dropped connection and the end of the file.  This is an inherit limitation
              ; of HTTP/1.0.  Other cases where we close the connection correspond to work arounds
              ; for buggy IE versions, at least some of which don't support chunked either.
              ((response/full-body page)
               (lambda chunks
                 (for-each (lambda (chunk) (display chunk out)) chunks)))
              (begin
                ((response/full-body page)
                 (lambda chunks
                   (fprintf out "~x\r\n" (foldl (lambda (c acc) (+ (string-length c) acc)) 0 chunks))
                   (for-each (lambda (chunk) (display chunk out)) chunks)
                   (fprintf out "\r\n")))
                ; one \r\n ends the last (empty) chunk and the second \r\n ends the (non-existant) trailers
                (fprintf out "0\r\n\r\n")))]
         [else
          (output-headers/response/full
           conn page
           `(("Content-length: " ,(apply + (map string-length (response/full-body page))))
             . ,(map (lambda (x) (list (symbol->string (car x)) ": " (cdr x)))
                     (response/full-extras page))))
          (for-each (lambda (str) (display str out))
                    (response/full-body page))])]
      [(and (pair? page) (string? (car page)))
       (output-headers conn 200 "Okay"
                       `(("Content-length: " ,(apply + (map string-length (cdr page)))))
                       (current-seconds) (car page))
       (for-each (lambda (str) (display str out))
                 (cdr page))]
      [else
       ;; TODO: make a real exception for this.
       (with-handlers
           ([exn? (lambda (exn)
                    (raise exn))])
         (let ([str (xexpr->string page)])
           (output-headers conn 200 "Okay"
                           `(("Content-length: " ,(add1 (string-length str)))))
           (display str out) ; the newline is for an IE 5.5 bug workaround
           (newline out)))])))

;; **************************************************
;; output-file

; output-file : path number symbol string connection -> void
; to serve out the file
(define (output-file path size method mime-type conn)
  (output-headers conn 200 "Okay"
                  `(("Content-length: " ,size))
                  (file-or-directory-modify-seconds path)
                  mime-type)
  (when (eq? method 'get)
    (call-with-input-file path (lambda (in) (copy-port in (connection-o-port conn))))))

