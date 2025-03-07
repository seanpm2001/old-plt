
(module frame mzscheme
  (require (lib "name-message.ss" "mrlib")
           (lib "string-constant.ss" "string-constants")
           (lib "unitsig.ss")
           (lib "class.ss")
           (lib "string.ss")
           (lib "list.ss")
           "drsig.ss"
           (lib "check-gui.ss" "version")
           (lib "mred.ss" "mred")
           (lib "framework.ss" "framework")
           (lib "url.ss" "net")
           (lib "head.ss" "net")
           (lib "plt-installer.ss" "setup")
           (lib "bug-report.ss" "help")
           (prefix mzlib:file: (lib "file.ss")) (lib "file.ss")
           (prefix mzlib:list: (lib "list.ss")))
  
  (provide frame@)
  (define frame@
    (unit/sig drscheme:frame^
      (import [drscheme:unit : drscheme:unit^]
              [drscheme:app : drscheme:app^]
              [help : drscheme:help-desk^]
              [drscheme:multi-file-search : drscheme:multi-file-search^]
              [drscheme:init : drscheme:init^])
      
      (rename [-mixin mixin])
      
      (define basics<%> (interface (frame:standard-menus<%>)))
      
      (define basics-mixin
        (mixin (frame:standard-menus<%>) (basics<%>)
          (inherit get-edit-target-window get-edit-target-object get-menu-bar)
          [define/private get-menu-bindings
            (λ ()
              (let ([name-ht (make-hash-table)])
                (let loop ([menu-container (get-menu-bar)])
                  (for-each
                   (λ (item)
                     (when (is-a? item selectable-menu-item<%>)
                       (let ([short-cut (send item get-shortcut)])
                         (when short-cut
                           (let ([keyname
                                  (string->symbol
                                   (keymap:canonicalize-keybinding-string
                                    (string-append
                                     (case (system-type)
                                       [(windows) "c:"]
                                       [(macosx macos) "d:"]
                                       [(unix)
                                        (case (send item get-x-shortcut-prefix)
                                          [(meta) "m:"]
                                          [(alt) "a:"]
                                          [(ctl) "c:"]
                                          [(ctl-m) "c:m;"])]
                                       [else ""])
                                     (case short-cut
                                       [(#\;) "semicolon"]
                                       [(#\:) "colon"]
                                       [(#\space) "space"]
                                       [else (string short-cut)]))))])
                             (hash-table-put! name-ht keyname (send item get-plain-label))))))
                     (when (is-a? item menu-item-container<%>)
                       (loop item)))
                   (send menu-container get-items)))
                name-ht))]
          
          [define/private copy-hash-table
            (λ (ht)
              (let ([res (make-hash-table)])
                (hash-table-for-each
                 ht
                 (λ (x y) (hash-table-put! res x y)))
                res))]
          [define/private can-show-keybindings?
            (λ ()
              (let ([edit-object (get-edit-target-object)])
                (and edit-object
                     (is-a? edit-object editor<%>)
                     (let ([keymap (send edit-object get-keymap)])
                       (is-a? keymap keymap:aug-keymap<%>)))))]
          
          [define/private show-keybindings
            (λ ()
              (if (can-show-keybindings?)
                  (let ([edit-object (get-edit-target-object)])
                    (let ([keymap (send edit-object get-keymap)])
                      (let*-values ([(menu-names) (get-menu-bindings)])
                        (let* ([table (send keymap get-map-function-table)]
                               [bindings (hash-table-map table list)]
                               [w/menus 
                                (append (hash-table-map menu-names list)
                                        (filter (λ (binding) (not (bound-by-menu? binding menu-names)))
                                                bindings))]
                               [structured-list
                                (mzlib:list:quicksort
                                 w/menus
                                 (λ (x y) (string-ci<=? (cadr x) (cadr y))))])
                          (show-keybindings-to-user structured-list this)))))
                  (bell)))]
          
          (define/private (bound-by-menu? binding menu-table)
            (ormap (λ (constituent)
                     (hash-table-get menu-table (string->symbol constituent) (λ () #f)))
                   (regexp-split #rx";" (symbol->string (car binding)))))
          
          (define/override (help-menu:before-about help-menu)
            (make-help-desk-menu-item help-menu)
            '(make-object menu-item%
               (format (string-constant welcome-to-something)
                       (string-constant drscheme))
               help-menu
               (λ (item evt)
                 (drscheme:app:invite-tour))))
          
          (define/override (help-menu:about-callback item evt) (drscheme:app:about-drscheme))
          (define/override (help-menu:about-string) (string-constant about-drscheme))
          (define/override (help-menu:create-about?) #t)
          
          (define/public (get-additional-important-urls) '())
          (define/override (help-menu:after-about menu)
            (instantiate menu-item% ()
              (label (string-constant help-menu-check-for-updates))
              (parent menu)
              (callback (λ (item evt) (check-version this))))
            (drscheme:app:add-important-urls-to-help-menu
             menu 
             (get-additional-important-urls))
            (new menu-item%
                 (label (string-constant bug-report-submit-menu-item))
                 (parent menu)
                 (callback
                  (λ (x y)
                    (help-desk:report-bug))))
            
            (drscheme:app:add-language-items-to-help-menu menu))
          
          (define/override (file-menu:open-callback item evt) (handler:open-file))
          (define/override (file-menu:new-string) (string-constant new-menu-item))
          (define/override (file-menu:open-string) (string-constant open-menu-item))

          (define/override (file-menu:between-open-and-revert file-menu) 
            (make-object menu-item% 
              (string-constant install-plt-file-menu-item...)
              file-menu
              (λ (item evt)
                (install-plt-file this)))
            (super file-menu:between-open-and-revert file-menu))
          
          (define/override (file-menu:between-print-and-close menu)
            (super file-menu:between-print-and-close menu)
            (instantiate menu-item% ()
              (label (string-constant mfs-multi-file-search-menu-item))
              (parent menu)
              (callback
               (λ (_1 _2)
                 (drscheme:multi-file-search:multi-file-search))))
            (new separator-menu-item% (parent menu)))
          
          (define/override (edit-menu:between-find-and-preferences menu)
            (make-object separator-menu-item% menu)
            (let ([keybindings-on-demand
                   (λ (menu-item)
                     (let ([last-edit-object (get-edit-target-window)])
                       (send menu-item enable (can-show-keybindings?))))])
              (instantiate menu% ()
                (label (string-constant keybindings-menu-item))
                (parent menu)
                (demand-callback
                 (λ (keybindings-menu)
                   (for-each (λ (old) (send old delete)) 
                             (send keybindings-menu get-items))
                   (new menu-item%
                        (parent keybindings-menu)
                        (label (string-constant keybindings-show-active))
                        (callback (λ (x y) (show-keybindings)))
                        (help-string (string-constant keybindings-info))
                        (demand-callback keybindings-on-demand))
                   (new menu-item%
                        (parent keybindings-menu)
                        (label (string-constant keybindings-add-user-defined-keybindings))
                        (callback
                         (λ (x y) 
                           (let ([filename (finder:get-file #f
                                                            (string-constant keybindings-choose-user-defined-file)
                                                            #f "" this)])
                             (when filename
                               (add-keybindings-file filename))))))
                   (let ([ud (preferences:get 'drscheme:user-defined-keybindings)])
                     (unless (null? ud)
                       (new separator-menu-item% (parent keybindings-menu))
                       (for-each (λ (path)
                                   (new menu-item%
                                        (label (format (string-constant keybindings-menu-remove)
                                                       (path->string path)))
                                        (parent keybindings-menu)
                                        (callback
                                         (λ (x y) (remove-keybindings-file path)))))
                                 ud)))))))
            (unless (current-eventspace-has-standard-menus?)
              (make-object separator-menu-item% menu)))
          
          (super-new)))

      (define (add-keybindings-file path)
        (with-handlers ([exn? (λ (x)
                                (message-box (string-constant drscheme)
                                             (exn-message x)))])
          (keymap:add-user-keybindings-file path)
          (preferences:set 'drscheme:user-defined-keybindings
                           (cons path
                                 (preferences:get 'drscheme:user-defined-keybindings)))))
      (define (remove-keybindings-file path)
        (keymap:remove-user-keybindings-file path)
        (preferences:set
         'drscheme:user-defined-keybindings
         (remq path
               (preferences:get 'drscheme:user-defined-keybindings))))
      
      ;; install-plt-file : (union #f dialog% frame%) -> void
      ;; asks the user for a .plt file, either from the web or from
      ;; a file on the disk and installs it.
      (define (install-plt-file parent)
        (define dialog
          (instantiate dialog% ()
            (parent parent)
            (alignment '(left center))
            (label (string-constant install-plt-file-dialog-title))))
        (define tab-panel
          (instantiate tab-panel% ()
            (parent dialog)
            (callback (λ (x y) (update-panels)))
            (choices (list (string-constant install-plt-web-tab)
                           (string-constant install-plt-file-tab)))))
        (define outer-swapping-panel (instantiate horizontal-panel% ()
                                       (parent tab-panel)
                                       (stretchable-height #f)))
        (define spacing-panel (instantiate horizontal-panel% ()
                                (stretchable-width #f)
                                (parent outer-swapping-panel)
                                (min-width 20)))
        (define swapping-panel (instantiate panel:single% ()
                                 (parent outer-swapping-panel)
                                 (alignment '(left center))
                                 (stretchable-width #t)
                                 (stretchable-height #f)))
        (define file-panel (instantiate horizontal-panel% ()
                             (parent swapping-panel)
                             (stretchable-width #t)
                             (stretchable-height #f)))
        (define url-panel (instantiate horizontal-panel% ()
                            (parent swapping-panel)
                            (stretchable-height #f)))
        (define button-panel (instantiate horizontal-panel% ()
                               (parent dialog)
                               (stretchable-height #f)
                               (alignment '(right center))))
        (define file-text-field (instantiate text-field% ()
                                  (parent file-panel)
                                  (callback void)
                                  (min-width 300)
                                  (stretchable-width #t)
                                  (label (string-constant install-plt-filename))))
        (define file-button (instantiate button% ()
                              (parent file-panel)
                              (label (string-constant browse...))
                              (callback (λ (x y) (browse)))))
        (define url-text-field (instantiate text-field% ()
                                 (parent url-panel)
                                 (label (string-constant install-plt-url))
                                 (min-width 300)
                                 (stretchable-width #t)
                                 (callback void)))
        
        (define-values (ok-button cancel-button)
          (gui-utils:ok/cancel-buttons
           button-panel
           (λ (x y)
             (set! cancel? #f)
             (send dialog show #f))
           (λ (x y)
             (send dialog show #f))))
        
        ;; browse : -> void
        ;; gets the name of a file from the user and
        ;; updates file-text-field
        (define (browse)
          (let ([filename (get-file #f dialog)])
            (when filename
              (send file-text-field set-value (path->string filename)))))
        
        ;; from-web? : -> boolean
        ;; returns #t if the user has selected a web address
        (define (from-web?)
          (zero? (send tab-panel get-selection)))
        
        (define cancel? #t)
        
        (define (update-panels)
          (send swapping-panel active-child
                (if (from-web?)
                    url-panel
                    file-panel)))
        
        (update-panels)
        (send dialog show #t)
        
        (cond
          [cancel? (void)]
          [(from-web?)
           (install-plt-from-url (send url-text-field get-value) parent)]
          [else 
           (parameterize ([error-display-handler drscheme:init:original-error-display-handler])
             (run-installer (string->path (send file-text-field get-value))))]))

      ;; install-plt-from-url : string (union #f dialog%) -> void
      ;; downloads and installs a .plt file from the given url
      (define (install-plt-from-url s-url parent)
        (with-handlers ([(λ (x) #f)
                         (λ (exn)
                           (message-box (string-constant drscheme)
                                        (if (exn? exn)
                                            (format "~a" (exn-message exn))
                                            (format "~s" exn))))])
          (let* ([url (string->url s-url)]
                 [tmp-filename (make-temporary-file "tmp~a.plt")]
                 [port (get-impure-port url)]
                 [header (purify-port port)]
                 [size (let* ([content-header (extract-field "content-length" header)]
                              [m (and content-header
                                      (regexp-match "[0-9]+" content-header))])
                         (and m (string->number (car m))))]
                 [d (make-object dialog% (string-constant downloading) parent)] 
                 [message (make-object message% (string-constant downloading-file...) d)] 
                 [gauge (if size 
                            (make-object gauge% #f 100 d) 
                            #f)] 
                 [exn #f] 
                 ; Semaphores to avoid race conditions: 
                 [wait-to-start (make-semaphore 0)] 
                 [wait-to-break (make-semaphore 0)] 
                 ; Thread to perform the download: 
                 [t (thread 
                     (λ () 
                       (semaphore-wait wait-to-start) 
                       (with-handlers ([exn:fail?
                                        (λ (x) 
                                          (set! exn x))] 
                                       [exn:break? ; throw away break exceptions 
                                        void])
                         (semaphore-post wait-to-break) 
                         (with-output-to-file tmp-filename 
                           (λ () 
                             (let loop ([total 0]) 
                               (when gauge 
                                 (send gauge set-value  
                                       (inexact->exact 
                                        (floor (* 100 (/ total size)))))) 
                               (let ([s (read-string 1024 port)]) 
                                 (unless (eof-object? s) 
                                   (unless (eof-object? s) 
                                     (display s) 
                                     (loop (+ total (string-length s))))))))
                           'binary 'truncate))
                       (send d show #f)))]) 
            (send d center) 
            (make-object button% (string-constant &stop)
			 d
			 (λ (b e) 
			   (semaphore-wait wait-to-break) 
			   (set! tmp-filename #f) 
			   (send d show #f) 
			   (break-thread t))) 
            ; Let thread run only after the dialog is shown 
            (queue-callback (λ () (semaphore-post wait-to-start))) 
            (send d show #t) 
            (when exn (raise exn))
            (parameterize ([error-display-handler drscheme:init:original-error-display-handler])
              (run-installer tmp-filename
                             (λ ()
                               (delete-file tmp-filename)))))))
      
      
      (define keybindings-dialog%
        (class dialog%
          (override on-size)
          [define on-size
            (lambda (w h)
              (preferences:set 'drscheme:keybindings-window-size (cons w h))
              (super on-size w h))]
          (super-instantiate ())))
      
      (define (show-keybindings-to-user bindings frame)
        (letrec ([f (instantiate keybindings-dialog% ()
                      (label (string-constant keybindings-frame-title))
                      (parent frame)
                      (width (car (preferences:get 'drscheme:keybindings-window-size)))
                      (height (cdr (preferences:get 'drscheme:keybindings-window-size)))
                      (style '(resize-border)))]
                 [bp (make-object horizontal-panel% f)]
                 [b-name (make-object button% (string-constant keybindings-sort-by-name)
                           bp (λ x (update-bindings #f)))]
                 [b-key (make-object button% (string-constant keybindings-sort-by-key)
                          bp (λ x (update-bindings #t)))]
                 [lb
                  (make-object list-box% #f null f void)]
                 [bp2 (make-object horizontal-panel% f)]
                 [cancel (make-object button% (string-constant close)
                           bp2 (λ x (send f show #f)))]
                 [space (make-object grow-box-spacer-pane% bp2)]
                 [update-bindings
                  (λ (by-key?)
                    (let ([format-binding/name
                           (λ (b) (format "~a (~a)" (cadr b) (car b)))]
                          [format-binding/key
                           (λ (b) (format "~a (~a)" (car b) (cadr b)))]
                          [predicate/key
                           (λ (a b) (string-ci<=? (format "~a" (car a))
                                                       (format "~a" (car b))))]
                          [predicate/name
                           (λ (a b) (string-ci<=? (cadr a) (cadr b)))])
                      (send lb set
                            (if by-key?
                                (map format-binding/key (mzlib:list:quicksort bindings predicate/key))
                                (map format-binding/name (mzlib:list:quicksort bindings predicate/name))))))])
          (send bp stretchable-height #f)
          (send bp set-alignment 'center 'center)
          (send bp2 stretchable-height #f)
          (send bp2 set-alignment 'right 'center)
          (update-bindings #f)
          (send f show #t)))
      
      (define <%>
        (interface (frame:editor<%> basics<%> frame:text-info<%>)
          get-show-menu
          update-shown
          add-show-menu-items))
      
      (define -mixin
        (mixin (frame:editor<%> frame:text-info<%> basics<%>) (<%>)
          (inherit get-editor get-menu% get-menu-bar)
          (define show-menu #f)
          (define/public get-show-menu (λ () show-menu))
          (define/public update-shown (λ () (void)))
          (define/public (add-show-menu-items show-menu) (void))
          (super-new)
          (set! show-menu (make-object (get-menu%) (string-constant view-menu-label)
                            (get-menu-bar)))
          (add-show-menu-items show-menu)))
      
      
      (define (create-root-menubar)
        (let* ([mb (new menu-bar% (parent 'root))]
               [file-menu (new menu% 
                               (label (string-constant file-menu))
                               (parent mb))]
               [help-menu (new menu% 
                               (label (string-constant help-menu))
                               (parent mb))])
          (new menu-item%
               (label (string-constant new-menu-item))
               (parent file-menu)
               (shortcut #\n)
               (callback
                (λ (x y)
                  (handler:edit-file #f)
                  #t)))
	  (new menu-item%
               (label (string-constant open-menu-item))
               (parent file-menu)
               (shortcut #\o)
               (callback
                (λ (x y)
                  (handler:open-file)
                  #t)))
          (new menu%
               (label (string-constant open-recent-menu-item))
               (parent file-menu)
               (demand-callback
                (λ (menu)
                  (handler:install-recent-items menu))))
	  (instantiate menu-item% ()
            (label (string-constant mfs-multi-file-search-menu-item))
            (parent file-menu)
            (callback
             (λ (_1 _2)
               (drscheme:multi-file-search:multi-file-search))))
          (unless (current-eventspace-has-standard-menus?)
	    (new separator-menu-item% (parent file-menu))
	    (new menu-item%
                 (label (string-constant quit-menu-item-others))
                 (parent file-menu)
                 (shortcut #\q)
                 (callback
                  (λ (x y)
                    (when (exit:user-oks-exit)
                      (exit:exit))
                    #t))))
          (make-help-desk-menu-item help-menu)))
      
      (define (make-help-desk-menu-item help-menu)
        (make-object menu-item%
          (string-constant help-desk)
          help-menu
          (λ (item evt)
            (help:help-desk)
            #t)))
      
      
      )))
