(module default-lexer mzscheme
  (require (lib "lex.ss" "parser-tools")
           (prefix : (lib "lex-sre.ss" "parser-tools")))
  
  (provide default-lexer)
  
  (define-lex-abbrevs 
   (parens (:or #\( #\) #\[ #\] #\{ #\})))
                     
  
  (define default-lexer
    (lexer
     ((:+ (:~ parens whitespace))
      (values lexeme 'no-color #f (position-offset start-pos) (position-offset end-pos)))
     ((:+ whitespace)
      (values lexeme 'white-space #f (position-offset start-pos) (position-offset end-pos)))
     (parens
      (values lexeme 'no-color (string->symbol lexeme) (position-offset start-pos) (position-offset end-pos)))
     ((special)
      (values "" 'no-color #f (position-offset start-pos) (position-offset end-pos)))
     ((special-comment)
      (values "" 'comment #f (position-offset start-pos) (position-offset end-pos)))
     ((eof)
      (values lexeme 'eof #f #f #f)))))
     
             
             
