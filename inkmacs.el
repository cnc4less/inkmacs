;; inkmacs.el -- Inkscape Emacs fusion
;; (c) fsf 2010, 2011
;; author:joakim verona
;; license:gpl


;;; Commentary:
;; 

;;Experimental integration between inkscape and Emacs using dbus.

;;Currently needs bleeding edge versions of a number of components.
;; - trunk version of inkscape with dbus enabled (see note below)
;; - trunk version of Eieio(needs a change which hasnt been merged downstream)
;; - trunk version of Jan Moringen dbus-proxy
;; - Emacs 23(i use Emacs from trunk, but 23 should be ok)

;;If you accept that all this really is bleeding edge for real, and
;;not something i just say, controling inkscape from Emacs is rather
;;fun! If you furthermore use my inkscape branch mentioned below,
;;inkmacs even aproaches usable!

;; the long term goal is to make an Emacs that does things quickly
;;  that currently inhibits creative flow with inkscape.  In
;;  particular I want to make a framework that supports specialized
;;  workflows, such as producing sketches for blog entries and web comics.
;; so, when inspiration hits you: m-x inkscape-blog-sketch,
;;rather than fiddling about in menus etc until you loose inspiration.

;;, for this we want to:
;; - make the xwidget Emacs branch usable, so inkscape can be embedded in Emacs
;; - make inkscape support xembed, so it can be embedded in Emacs
;; - make an inkscape mode that shows just the canvas
;; - make an Emacs inkscape control mode that implements a proper Emacs ui on top of inkscape
;; - somehow implement the Emacs buffer model with inkscape
;; - implement a form of OLE:
;;  - display svg images inline muse-mode org org mode for example(this is already mostly possible)
;;  - edit the svg inside inkscape when desired

;; very important is to support text editing in Emacs.  nodes in an outline-mode
;; document should preferably be bound to nodes in the inkscape document.

;; please note that there is an Inkscape branch where I have some
;; bugfixes for the dbus support:
;; lp:~joakim-verona/inkscape/dbus-fixes
;; In particular the ink-org integration wont work at all without the fixes


;;check alive
;;(dbus-ping :session   "org.inkscape" 100)

;;(dbus-introspect-xml :session   "org.inkscape" "/")

;;(dbus-introspect-get-all-nodes :session   "org.inkscape" "/org/inkscape")

;;(dbus-introspect-get-interface :session   "org.inkscape" "/org/inkscape/application" "org.inkscape.application")
;;(dbus-introspect-get-method-names :session   "org.inkscape" "/org/inkscape/application" "org.inkscape.application")
;;(dbus-introspect-get-method-names  :session "org.inkscape"  "/org/inkscape/desktop_24" "org.inkscape.document")
;; (dbus-introspect-get-method  :session "org.inkscape"  "/org/inkscape/desktop_24" "org.inkscape.document" "rectangle")

;;(dbus-introspect :session "org.inkscape" "/org/inkscape")
;;; Code:

(require 'dbus)
(require 'dbus-introspection)
(require 'dbus-proxy)

(defcustom inkscape-path
  "inkscape"
  "Path to dbus-enabled inkscape.")

(defvar inkscape-desktop-name "desktop_0"
  "This is currently hardcoded, since the inkscape dbus api isnt feature complete yet.")

(defvar inkscape-desktop-dummy nil
  "There is one desktop per document. a bit awkward because we need a dummy desktop for proxie creation.
then we have buffer local instances.")

(defvar inkscape-application nil
  "There is only one inkscape application.")

(defvar inkscape-proxies-registered nil
  "The proxies needs creating once.  reset it if the interface changes.")

(defun inkscape-alive ()
  "Check if theres a running inkscape."
  (dbus-ping :session   "org.inkscape" 100))


(defun inkscape-register-proxies ()
  "Register proxys."
  (interactive)
  (message "registering dbus proxies")
  (setq inkscape-application (inkscape-app-dbus-proxy-create)) ;;seems to bring up an inkscape window
  (setq inkscape-desktop-dummy (inkscape-document-dbus-proxy-create inkscape-desktop-name))
  (message "registering inkscape verb proxies")
  (inkscape-make-verb-list) ;;TODO sometimes this simply doesnt execute. wtf?
  (message "emacs-inkscape bridge ready for action!")
  (setq inkscape-proxies-registered t))


;; call-verb support
;; inkscape doesnt export all functionality through proper dbus interfaces atm.
;; there is an older "verb" interface, and a dbus bridge.
;; here is some code that tries to aproximate the dbus-proxy api for the verb api

(defun inkscape-make-verb-list ()
  "Create wrappers for the Verb API."
  (start-process "inkscape-verb-list" "*inkscape-verb-list*" inkscape-path "--verb-list")
  (with-current-buffer  "*inkscape-verb-list*"
    (goto-char (point-min))
    (while (re-search-forward  "^\\([^:]+\\):\\(.*\\)$" nil t)
      (message "[%s][%s]" (match-string 1) (match-string 2))
      (inkscape-make-verb-method (match-string 1)(match-string 2)))))

(defun inkscape-make-verb-method (name doc)
  "Create a Verb wrapper.  NAME is the verb DOC a docstring."
  (eval `(defmethod ,(intern (inkscape-transform-method-name "inkverb" name))
           ((this    org.freedesktop.DBus.Introspectable-org.freedesktop.DBus.Properties-org.inkscape.document
                     ;;                     ,(object-class inkscape-desktop-dummy) ;;inkscape-desktop must be initialized
                     ))
           ,doc
           (inkdoc-call-verb this ,name))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;creating the dbus proxies, using Jan Moringen fantastic
;;dbus-proxy library. The way emacs dbus integration was meant to be


(defun inkscape-transform-method-name (prefix name)
  "Transform NAME. prepend PREFIX.
PREFIX can be inkapp- or inkdoc- for
 example. un-camelcase. switch underscore to dash."
  (concat prefix "-" (replace-regexp-in-string "_" "-" (dbus-proxy-transform-camel-case name))))

(defun inkscape-app-dbus-proxy-create ()
  "Create dbus-proxy to talk to inkscape app."
  (let* ((dbus-proxy-transform-method-name-function (lambda (name) (inkscape-transform-method-name "inkapp" name)))
         (obj (dbus-proxy-make-remote-proxy
               :session "org.inkscape"
               "/org/inkscape/application" t)))
    obj))

(defun inkscape-document-dbus-proxy-create (desktop)
  "Create dbus-proxy to talk to inkscape DESKTOP.
slow the first time, then not so bad."
  (let* ((dbus-proxy-transform-method-name-function (lambda (name) (inkscape-transform-method-name "inkdoc" name)))
         (obj (dbus-proxy-make-remote-proxy
               :session "org.inkscape"
               (concat "/org/inkscape/" desktop) t)))
    obj))

;;TODO
;; should be buffer local
;; seems to create an inkscape instance mysteriously
;;(setq inkscape-desktop (inkscape-document-dbus-proxy-create "desktop_0"))
;;(setq inkscape-desktop-1 (inkscape-document-dbus-proxy-create "desktop_1"))

(defun inkscape-local-instance ()
  "Create a buffer local instance of inkscape."
  ;;TODO this needs more cleverness
  ;;handle closing of ink desktop etc
  (let ((newdesk (car (last (split-string (inkapp-desktop-new inkscape-application ) "/")))))
    (set (make-local-variable 'inkscape-desktop) (inkscape-document-dbus-proxy-create newdesk))))

(defun inkscape-local-instance-close ()
  "Close the local inkscape instance."
  (inkdoc-close inkscape-desktop)
  (setq inkscape-desktop nil))

;;;;;;;;;;;;;;;;;;;;;;;;;,,
;;image mode adapter code
(defun inkscape-open-buffer-file ()
  "Open buffer file un a local inkscape instance."
  (interactive)
  ;;TODO check that the buffer contains a SVG file
  ;;BUG funnily crashes if called twice on the same desktop object(not reproducible)
  ;;inkdoc-load is awkward:
  ;; - 1st open happens inside "virgin" desktop
  ;; - subsequent opens happen in new desktops
  ;; - the resulting desktop name isnt returned
  (inkscape-local-instance)
  (inkdoc-load inkscape-desktop  (buffer-file-name)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;inkscape org integration - the pride of inkmacs
;;

;; strategy:
;;   - tree level 1 represents the file
;;   - tree level 2 is a column heading
;;   - tree level 3 and lower are placed in the column

;; inkscape text is a little bit unintuitive:
;; text objects are realy a set of text span objects with separate prperties
;; but tde api doesnt ouite reflect that because its inconvenient anyway
;; furthermore the spans dont change after you create them

;; for the purpose of inkorg, its nicer if we handle formating and
;; wordwrap inside inkscape. to get that we need a text object and
;; another linked object which determines the shape. they are both handled separately.

;; also note that svg 1.2 isnt finalized so convert to text before publishing:
;; http://wiki.inkscape.org/wiki/index.php/FAQ#What_about_flowed_text.3F

;; tip: create a ospecal txt layer before inkorg-create-text-group

;; these values are used to place new nodes
;; old nodes will retain their placement
(defvar inkorg-x 0)
(defvar inkorg-y 0)

(defun inkorg-create-or-update-text (do-tree)
  "Update the current org node or subtree.
Argument DO-TREE updates the entire subtree."
  (interactive "P")
  (if do-tree
      (inkorg-create-text-group)
    (inkorg-create-or-update-text-node))
  )

;;TODO if a node has been removed from the org doc it should also be
;;removed from the ink doc. this is however a bit tricky.
;; naive method to find orphan nodes:
;; - build a list A of all inkscape objects using select-all
;; - build a list B of all inkorg nodes by iterating the org tree and extracting the id
;; oh wait - I dont know which A:s used to be inkorg nodes. aargh!
;; inkscape groups cant really be used because it changes behaviourp
;; the only reasonable alternative seems to be to use a naming convention:
;; inkmacs-<type>-<orgid>


(defun inkorg-create-text-group()
  "traverse an org tree and create text nodes.
the nodes will be placed on the document canvas according to a simple pattern
the first time. the nodes will retain position later."
  (interactive)
  (setq inkorg-x 0  inkorg-y 0);;todo refactor

  (org-map-entries 'inkorg-create-or-update-text-node nil 'tree 'comment)
  )

;;(defvar inkorg-select 'keep-subtree);;todo should be let bound local
(defvar inkorg-select-start-level 0);;todo should be let bound local

(defun inkorg-select-skip ()
  "Determine node skippage."
  (cond
   ((eq inkorg-select 'keep-siblings)
    (if (= (org-outline-level) inkorg-select-start-level) nil t))
   ((eq inkorg-select 'keep-sibling-subtrees)
    (if (>= (org-outline-level) inkorg-select-start-level) nil t))
   ((eq inkorg-select 'keep-subtree) nil)
   (t nil) )
  )

(defun inkorg-select-tree (inkorg-select)
  "Select the nodes in inkscape corresponding to the org tree.
Argument INKORG-SELECT filters the nodes to select."
  (interactive
   (list (if current-prefix-arg (read (completing-read "keep:" '("keep-sibling-subtrees" "keep-siblings" "keep-subtree") )))))
  (save-excursion
    (org-back-to-heading)
    (setq inkorg-select-start-level (org-outline-level))
    (unless (or (= 1 (org-outline-level)) (equal inkorg-select 'keep-subtree))
      (org-up-heading-all 100))
    (org-map-entries 'inkorg-select-node nil 'tree 'inkorg-select-skip))
  )

(defun inkorg-select-node ()
  "Select the text and flow objects in inkscape corresponding to the org node."
  (let* ((id (org-id-get nil t)))
    (inkdoc-selection-add inkscape-desktop id)
    (inkdoc-selection-add inkscape-desktop (concat id "-flow"))
    ))


(defun org-get-entry-2 ()
  "Get the entry text, after heading, to nex heading, or eof."
  (save-excursion
    (org-back-to-heading t)
    (let ((p1 (point-at-bol 2))
          (p2 (progn (forward-line) (search-forward "*" nil t))))
      (setq p2 (if (null p2) (point-max)
                 (1- p2)))
      (buffer-substring p1  p2))))

(defun inkorg-entry-text ()
  "Extract text from current org node.
Return a format suitable to
create an inkscape text node from.
asterisks and properties are removed."
  (let ((text  (concat (org-get-heading) "\n" (org-get-entry-2))))
    (set-text-properties 0 (length text) nil text )
    
    (concat
     (substring text 0 (string-match org-property-start-re text))
     (if (string-match org-property-end-re text)
         (substring text (progn (string-match org-property-end-re text) (match-end 0)) (length text))))))


(defun inkorg-create-text-node ()
  "Create a corresponding inkscape text node from the current org node."
  (interactive)

  ;;placement ;;TODO refactor, enable different placement algorithms
  (if (= 2 (org-outline-level))
      (progn
        (setq inkorg-x (+ 400 inkorg-x))
        (setq inkorg-y 0)))
  (setq inkorg-y (+ 200 inkorg-y))

  ;;create text node
  (let* ((text (inkorg-entry-text);;TODO enable different text extraction functions
               )
         (id (concat "inkmacs-text-" (org-id-get nil t)))
         (flow-node (inkdoc-rectangle inkscape-desktop inkorg-x inkorg-y 200 200))  ;; create text flow rectangle TODO enable size formatting
         (flow-id (concat "inkmacs-flow-" (org-id-get nil t)))
         (text-node (inkdoc-text inkscape-desktop inkorg-x inkorg-y text)))
    (inkdoc-set-attribute inkscape-desktop text-node "id" id)
    (inkdoc-set-attribute inkscape-desktop flow-node "id" flow-id)
    ;;link text flow frame and text node
    (inkdoc-set-color inkscape-desktop flow-id 255 255 255 t) ;;TODO enable formatting of flow frame
    ;;   select both objects
    (inkdoc-selection-set-list inkscape-desktop (list flow-id id))
    (inkverb-object-flow-text inkscape-desktop) ;;text sshall be flowed in the frame
    ;; were not finished because the text id has changed so change it back
    ;; we rely on the new flow object being selected which seems fragile
    (inkdoc-set-attribute inkscape-desktop     (car (inkdoc-selection-get inkscape-desktop)) "id" id)
    (inkdoc-selection-clear  inkscape-desktop)
    ))

(defun inkorg-create-or-update-text-node ()
  "create a corresponding inkscape text node from the current org
node, or update the node if it already exists."
  (interactive);bind to c-m-x
  (let* ((text (inkorg-entry-text))
         (id (concat "inkmacs-text-" (org-id-get nil t))))
    (if (inkmacs-node-exists inkscape-desktop id)
        (inkdoc-set-text inkscape-desktop id (inkorg-entry-text))
      (inkorg-create-text-node))))

(define-minor-mode inkorg-mode "inkorg" nil " inkorg"
  '(( "\e\C-x" . inkorg-create-or-update-text))
  (if inkorg-mode (inkscape-local-instance)
    (inkscape-local-instance-close))
  
  )

(defun inkmacs-node-exists (desk name)
  "See if an inkscape object exists.
Argument DESK inkscape desktop.
Argument NAME name of object."
  ;;inkscpe throws an error if it doesnt, so we catch it instead
  (condition-case err
      (inkdoc-get-attribute   desk name "id")
    (error nil)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;initialize bridge
(inkscape-register-proxies)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;test code
(defun inkscape-dbus-proxy-test ()
  (inkscape-app-dbus-proxy-create)
  (let*
      ((doc (inkscape-document-dbus-proxy-create "desktop_0")))
    (inkdoc-rectangle doc 100 100 100 100)))

;;get all defined inkscape methods
;;(remove-if-not (lambda (x)(string-match "^ink.*-" (symbol-name x)) ) (eieio-all-generic-functions))



(defun  inkscape-test ()
  "Opens inkscape, draws a black rectangle. a dbus compatible
Inkscape needs to be running 1st. this test doesnt use the dbus-proxy."
  (let*
      ((desktop "/org/inkscape/desktop_0")
       (rect (dbus-call-method
              :session "org.inkscape" desktop
              "org.inkscape.document" "rectangle" :int32 100 :int32  100 :int32  100 :int32  100)))))



(provide 'inkmacs)

;;; inkmacs.el ends here
