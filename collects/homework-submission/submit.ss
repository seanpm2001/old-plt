;; The servlet. Start things off and catch any last exceptions that got raised.

(module submit mzscheme
  (require (lib "pages-transitions.ss" "homework-submission" "src")
           (lib "scheduler.ss" "homework-submission" "src")
           )

  (provide timeout interface-version start)

  (define timeout 120)
  (define interface-version 'v1)

  (define start transition-login)

  )
