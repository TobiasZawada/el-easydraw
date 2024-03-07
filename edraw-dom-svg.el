;;; edraw-dom-svg.el --- DOM/SVG Utility             -*- lexical-binding: t; -*-

;; Copyright (C) 2021 AKIYAMA Kouhei

;; Author: AKIYAMA Kouhei <misohena@gmail.com>
;; Keywords: Graphics,Drawing,SVG

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; 

;;; Code:
(require 'dom)
(require 'seq)
(require 'subr-x)
(require 'edraw-math)
(require 'edraw-path)
(require 'edraw-util)

(defvar edraw-svg-version "1.1")

;;;; DOM Element Creation

(defun edraw-dom-element (tag &rest attr-plist-and-children)
  "Return a new DOM element with TAG and ATTR-PLIST-AND-CHILDREN.

ATTR-PLIST-AND-CHILDREN specifies the attributes and children of
the new element. For example:

  (edraw-dom-element
    \\='div
    :class \"some-div\"
    (edraw-dom-element \\='p \"Paragraph 1.\")
    (edraw-dom-element \\='p \"Paragraph 2.\"))

Attributes are specified in a property list starting at the
beginning of ATTR-PLIST-AND-CHILDREN. A property list key must be
a symbol. If the symbol is a keyword, the leading colon is
ignored (i.e. :x and \\='x are the same).

If a non-symbol appears at the position where the key symbol of
the property list should appear, the subsequent elements are
treated as children.

The following special properties can be specified.

:parent      Parent DOM element.
:children    A list of child DOM nodes.
:attributes  An plist or alist of additional attributes.

Commonly used SVG elements have their own creation functions:

- `edraw-svg-create'
- `edraw-svg-rect'
- `edraw-svg-circle'
- `edraw-svg-ellipse'
- `edraw-svg-line'
- `edraw-svg-path'
- `edraw-svg-polygon'
- `edraw-svg-polyline'
- `edraw-svg-group'

These functions can specify the same arguments as this function
in the rest argument."
  (let ((children attr-plist-and-children)
        attr-alist)
    ;; Split ATTR-PLIST-AND-CHILDREN into ATTR-ALIST and CHILDREN.
    (while (and children (symbolp (car children)))
      (let* ((key (car children))
             (value (cadr children))
             (key-symbol
              (cond
               ((keywordp key) (intern (substring (symbol-name key) 1)))
               ((symbolp key) key))))
        (pcase key-symbol
          ;; Ignore :parent and :children
          ((or 'nil 'parent 'children))
          ;; Support :attributes (key value ...) notation
          ('attributes
           (when (consp value)
             (cond
              ((consp (car value)) ;; alist
               (setcdr (cdr children) (nconc
                                       (cl-loop for (k . v) in value
                                                collect k collect v)
                                       (cddr children))))
              ((plistp value) ;; plist
               (setcdr (cdr children) (nconc
                                       value
                                       (cddr children)))))))
          (_
           (push (cons key-symbol value) attr-alist)))
        (setq children (cddr children))))
    (setq attr-alist (nreverse attr-alist))

    ;; Support :children (list ...) notation.
    (when-let ((attr-children (plist-get attr-plist-and-children :children)))
      (setq children (nconc children attr-children)))

    ;; Create an element
    (let ((element (apply 'dom-node tag attr-alist children)))
      ;; Set ELEMENT as parent for children
      (dolist (child children)
        (edraw-dom-set-parent child element))
      ;; Append the element to parent
      (when-let ((parent (plist-get attr-plist-and-children :parent)))
        (edraw-dom-append-child parent element))
      element)))

(defun edraw-dom-copy-tree (node)
  "Duplicate the DOM tree NODE.

Attribute keys and values, and text node strings are shared
before and after copying.

Each element in the cloned tree has no link to its parent
element. Call `edraw-dom-update-parents' explicitly if necessary.

Attributes for internal use are not duplicated.
Whether it is for internal use is determined by `edraw-dom-attr-internal-p'."
  (if (and (consp node)
           (symbolp (car node)))
      (let* ((tag (dom-tag node))
             (attributes (cl-loop for (key . value) in (dom-attributes node)
                                  unless (edraw-dom-attr-internal-p key)
                                  collect (cons key value)))
             (children (cl-loop for child in (dom-children node)
                                collect (edraw-dom-copy-tree child))))
        (apply #'dom-node tag attributes children)
        ;; Do not call `edraw-dom-set-parent' and
        ;; (edraw-dom-element tag :attributes attributes :children children)
        )
    node))

;;;; DOM Element Accessors

(defun edraw-dom-element-p (node)
  (and node
       (listp node)
       (not (null (car node)))
       (symbolp (car node))))

(defmacro edraw-dom-tag (node)
  "Return the NODE tag.
Unlike `dom-tag', this function doesn't consider NODE if is's a
list of nodes.
Since this is a macro, setf can be used."
  ;; depends on dom.el node structure
  `(car-safe ,node))

(defmacro edraw-dom-attributes (node)
  "Return the NODE attribute list.
Unlike `dom-attributes', this function doesn't consider NODE if
is's a list of nodes.
Since this is a macro, setf can be used."
  ;; depends on dom.el node structure
  `(cadr ,node))

(defmacro edraw-dom-children (node)
  "Return the NODE child list.
Unlike `dom-children', this function doesn't consider NODE if
is's a list of nodes.
Since this is a macro, setf can be used."
  ;; depends on dom.el node structure
  `(cddr ,node))

(defun edraw-dom-tag-eq (node tag)
  (eq (edraw-dom-tag node) tag))

;;;; DOM Search

(defun edraw-dom-get-by-id (parent id)
  (car (dom-by-id parent (concat "\\`" (regexp-quote id) "\\'"))))

(defun edraw-dom-get-or-create (parent tag id)
  (or
   (edraw-dom-get-by-id parent id)
   (edraw-dom-element tag :id id :parent parent)))

;;;; DOM Parent Tracking

(defun edraw-dom-set-parent (node parent)
  (when (edraw-dom-element-p node)
    ;; :-edraw-dom-parent is an attribute for internal use.
    ;; (See: `edraw-dom-attr-internal-p')
    (dom-set-attribute node :-edraw-dom-parent parent)))

(defun edraw-dom-get-parent (node)
  (when (edraw-dom-element-p node)
    (dom-attr node :-edraw-dom-parent)))

(defun edraw-dom-reset-parent (node)
  (when (edraw-dom-element-p node)
    (edraw-dom-remove-attr node :-edraw-dom-parent)))

(defun edraw-dom-update-parents (tree)
  "Make it possible to retrieve parents of all elements in TREE."
  (when (edraw-dom-element-p tree)
    (dolist (child (dom-children tree))
      (edraw-dom-set-parent child tree)
      (edraw-dom-update-parents child))))

(defun edraw-dom-get-root (node)
  (let (parent)
    (while (setq parent (edraw-dom-get-parent node))
      (setq node parent))
    node))

(defun edraw-dom-get-ancestor-by-tag (node tag)
  (let (parent)
    (while (and (setq parent (edraw-dom-get-parent node))
                (not (eq (dom-tag parent) tag)))
      (setq node parent))
    parent))

(defun edraw-dom-parent (dom node)
  "Return the parent of NODE in DOM.

Same as `dom-parent', but if NODE has the parent node information
set by `dom-set-parent', this function will skip searching from
the DOM and quickly identify the parent."
  (let ((parent (edraw-dom-get-parent node)))
    (if (and parent (memq node (edraw-dom-children parent)))
        parent
      (dom-parent dom node))))

;;;; DOM Removing

(defun edraw-dom-remove-node (dom node)
  (prog1 (dom-remove-node dom node)
    ;; @todo Should check to see if it has really been removed.
    (edraw-dom-reset-parent node)))

(defun edraw-dom-remove-all-children (node)
  (when (consp node)
    (dolist (child (dom-children node))
      (edraw-dom-reset-parent child))
    (setf (edraw-dom-children node) nil))
  node)

(defun edraw-dom-remove-by-id (dom id)
  (when-let ((node (edraw-dom-get-by-id dom id)))
    (edraw-dom-remove-node dom node)))

(defun edraw-dom-remove-attr (node attr)
  (dom-set-attributes node (assq-delete-all attr (dom-attributes node))))

(defun edraw-dom-remove-attr-if (node pred)
  (dom-set-attributes node (cl-delete-if pred (dom-attributes node))))

;;;; DOM Insertion

(defun edraw-dom-add-child-before (node child &optional before)
  (prog1 (dom-add-child-before node child before)
    (edraw-dom-set-parent child node)))

(defun edraw-dom-append-child (node child)
  (prog1 (dom-append-child node child)
    (edraw-dom-set-parent child node)))

(defun edraw-dom-insert-first (node child)
  (prog1 (dom-add-child-before node child)
    (edraw-dom-set-parent child node)))

(defun edraw-dom-insert-nth (node child index)
  (setq node (dom-ensure-node node))
  ;; depends on dom.el node structure
  (if (<= index 0)
      (setcdr (cdr node) (cons child (cddr node)))
    (let ((cell (or (nthcdr (1- index) (cddr node))
                    (last (cddr node)))))
      (setcdr cell (cons child (cdr cell)))))
  (edraw-dom-set-parent child node)
  child)

;;;; DOM Retrieve Siblings

(defun edraw-dom-first-child (node)
  (car (dom-children node)))

(defun edraw-dom-last-child (node)
  (car (last (dom-children node))))

(defun edraw-dom-next-sibling (dom node)
  (when-let ((parent (edraw-dom-parent dom node)))
    (let ((siblings (dom-children parent)))
      (while (and siblings
                  (not (eq (car siblings) node)))
        (setq siblings (cdr siblings)))
      (cadr siblings))))

(defun edraw-dom-previous-sibling (dom node)
  (when-let ((parent (edraw-dom-parent dom node)))
    (let ((siblings (dom-children parent)))
      (if (eq (car siblings) node)
          nil
        (while (and (cadr siblings)
                    (not (eq (cadr siblings) node)))
          (setq siblings (cdr siblings)))
        (car siblings)))))

;;;; DOM Ordering

(defun edraw-dom-first-node-p (dom node)
  (if-let ((parent (edraw-dom-parent dom node)))
      (eq (car (dom-children parent)) node)
    t))

(defun edraw-dom-last-node-p (dom node)
  (if-let ((parent (edraw-dom-parent dom node)))
      (eq (car (last (dom-children parent))) node)
    t))

(defun edraw-dom-reorder-prev (dom node)
  (when-let ((parent (edraw-dom-parent dom node)))
    (let ((index (seq-position (dom-children parent) node #'eq)))
      (when (> index 0)
        (let* ((prev-cell (nthcdr (1- index) (dom-children parent)))
               (prev-node (car prev-cell)))
          ;; depends on dom.el node structure
          (setcar prev-cell node)
          (setcar (cdr prev-cell) prev-node))
        t))))

(defun edraw-dom-reorder-next (dom node)
  (when-let ((parent (edraw-dom-parent dom node)))
    (let* ((index (seq-position (dom-children parent) node #'eq))
           (curr-cell (nthcdr index (dom-children parent)))
           (next-cell (cdr curr-cell))
           (next-node (car next-cell)))
      (when next-cell
        ;; depends on dom.el node structure
        (setcar next-cell node)
        (setcar curr-cell next-node)
        t))))

(defun edraw-dom-reorder-first (dom node)
  (when-let ((parent (edraw-dom-parent dom node)))
    (when (not (eq (car (dom-children parent)) node))
      ;; The parent of NODE does not change.
      (dom-remove-node parent node)
      (dom-add-child-before parent node (car (dom-children parent)))
      t)))

(defun edraw-dom-reorder-last (dom node)
  (when-let ((parent (edraw-dom-parent dom node)))
    (when (not (eq (car (last (dom-children parent))) node))
      ;; The parent of NODE does not change.
      (dom-remove-node parent node)
      (dom-append-child parent node)
      t)))

;;;; DOM Attributes

(defun edraw-dom-attr-internal-p (attr-name)
  "Return non-nil if the attribute's name ATTR-NAME is for internal use.

ATTR-NAME is a symbol or string.

Attribute names starting with a colon are for internal use."
  (cond
   ((symbolp attr-name) (keywordp attr-name))
   ((stringp attr-name) (and (not (string-empty-p attr-name))
                             (eq (aref attr-name 0) ?:)))))

(defun edraw-dom-remove-internal-attributes (node)
  (when (edraw-dom-element-p node)
    (edraw-dom-remove-attr-if node #'edraw-dom-attr-internal-p))
  node)

(defun edraw-dom-remove-internal-attributes-from-tree (node)
  (edraw-dom-do
   node
   (lambda (node _ancestors)
     (edraw-dom-remove-internal-attributes node))))

(defun edraw-dom-set-attribute-name (node old-name new-name)
  "Rename OLD-NAME attribute in NODE to NEW-NAME if it exists.
If the attribute named OLD-NAME does not exist, do nothing.
Attribute value is preserved."
  (setq node (dom-ensure-node node))
  (let* ((attributes (cadr node))
         (old-cell (assoc old-name attributes)))
    (when old-cell
      (setcar old-cell new-name))))

;;;; DOM Mapping

(defun edraw-dom-do (node function &optional ancestors)
  (funcall function node ancestors)
  (when (edraw-dom-element-p node)
    (let ((ancestors (cons node ancestors))
          (children (dom-children node)))
      (cond
       ((listp children)
        (dolist (child-node children)
          (edraw-dom-do child-node function ancestors)))
       ;; Comment Node (comment nil "comment text")
       ((stringp children)
        (funcall function children ancestors))))))

;;;; DOM Top Level Handling

(defun edraw-dom-split-top-nodes (dom)
  "Split DOM into pre comment nodes, top-level element, and post
comment nodes.

Return (ROOT-ELEMENT . (PRE-COMMENTS . POST-COMMENTS)).

`libxml-parse-xml-region' returns an element with the tag top if
there are comments before or after root element. This function
splits the DOM into pre comment nodes, root element, and post
comment nodes."
  (if (edraw-dom-tag-eq dom 'top)
      ;; DOM contains comments directly below
      (let* ((top-nodes (dom-children dom))
             (p top-nodes)
             (pre-comments nil))
        (while (and p (edraw-dom-tag-eq (car p) 'comment))
          (push (car p) pre-comments)
          (setq p (cdr p)))

        (if p
            ;; (ROOT-ELEMENT . (PRE-COMMENTS . POST-COMMENTS))
            (cons (car p) (cons (nreverse pre-comments) (cdr p)))
          ;; No elements!
          (cons nil (cons top-nodes nil))))
    (cons dom nil)))

(defun edraw-dom-merge-top-nodes (root-element pre-comments post-comments)
  "Reverse operation of `edraw-dom-split-top-nodes'."
  ;;@todo If (edraw-dom-tag-eq root-element 'top)?
  (if (or pre-comments post-comments)
      (apply #'dom-node 'top nil
             (append pre-comments (list root-element) post-comments))
    root-element))


;;;; SVG Print


(defun edraw-svg-to-image (svg &rest props)
  (apply
   #'create-image
   (edraw-svg-to-string svg nil #'edraw-svg-print-attr-filter)
   'svg t
   props))

(defun edraw-svg-to-string (dom node-filter attr-filter &optional indent no-indent)
  (with-temp-buffer
    (edraw-svg-print dom node-filter attr-filter indent no-indent)
    (buffer-string)))

(defun edraw-svg-print (dom node-filter attr-filter &optional indent no-indent)
  ;; Derived from svg-print in svg.el
  (when (or (null node-filter) (funcall node-filter dom))
    (cond
     ;; Text Node
     ((stringp dom)
      (edraw-svg-print--text-node dom))
     ;; Comment
     ((eq (car-safe dom) 'comment)
      (edraw-svg-print--comment dom))
     ;; Top-Level Comments
     ;;@todo `top' should only be processed if dom is expected to be the root element.
     ((eq (car-safe dom) 'top)
      (edraw-svg-print--top-level dom node-filter attr-filter indent no-indent))
     ;; Element
     (t
      (edraw-svg-print--element dom node-filter attr-filter indent no-indent))
     )))

(defun edraw-svg-print--text-node (dom)
  (insert (edraw-svg-escape-chars dom)))

(defun edraw-svg-print--comment (dom)
  (insert "<!--" (caddr dom) "-->"))

(defun edraw-svg-print--top-level (dom node-filter attr-filter indent no-indent)
  (let ((children (cddr dom)))
    (dolist (node children)
      (if (edraw-dom-tag-eq node 'comment)
          (progn
            ;; Insert a line break after root element for footer comments.
            (unless (bolp)
              (insert "\n"))
            (edraw-svg-print--comment node)
            ;; Insert a line break after each top-level comment.
            ;; It expects to put a line like
            ;; <!-- -*- mode: edraw -*- --> at the top of the file.
            (insert "\n"))
        (edraw-svg-print node node-filter attr-filter indent no-indent)))))

(defun edraw-svg-print--element (dom node-filter attr-filter indent no-indent)
  (let ((tag (car dom))
        (attrs (cadr dom))
        (children (cddr dom)))
    (when (and (integerp indent) (not no-indent))
      (insert (make-string indent ? )))
    (insert (format "<%s" tag))
    (dolist (attr attrs)
      (when (or (null attr-filter) (funcall attr-filter attr))
        (insert (format " %s=\"%s\""
                        (car attr)
                        ;;@todo add true attribute filter and add number format option on export
                        (edraw-svg-escape-chars
                         (edraw-svg-ensure-string-attr (cdr attr)))))))
    (if (null children)
        ;;children is empty
        (insert " />")
      ;; output children
      (insert ">")
      (edraw-svg-print--children-and-end-tag
       tag children node-filter attr-filter indent no-indent))))

(defun edraw-svg-print--children-and-end-tag (tag
                                              children node-filter attr-filter
                                              indent no-indent)
  (let ((no-indent (or no-indent
                       (not (integerp indent))
                       (memq tag '(text tspan))
                       (seq-find 'stringp children))))
    (dolist (elem children)
      (unless no-indent (insert "\n"))
      (edraw-svg-print elem node-filter attr-filter (unless no-indent (+ indent 2)) no-indent))
    (unless no-indent (insert "\n" (make-string indent ? )))
    (insert (format "</%s>" tag))))

(defun edraw-svg-print-attr-filter (attr)
  (/= (aref (edraw-svg-symbol-name (car attr)) 0) ?:))

(defun edraw-svg-symbol-name (symbol-or-str)
  (format "%s" symbol-or-str))

(defun edraw-svg-escape-chars (str)
  (replace-regexp-in-string
   "\\([\"&<]\\)"
   (lambda (str)
     (pcase (elt str 0)
       (?\" "&quot;")
       (?& "&amp;")
       (?< "&lt;")))
   str
   t t))


;;;; SVG Encode / Decode


(defun edraw-svg-decode (data base64-p)
  (with-temp-buffer
    (insert data)
    (edraw-decode-buffer base64-p)
    (let ((dom (libxml-parse-xml-region (point-min) (point-max))))
      ;; libxml-parse-xml-region drops the xmlns= attribute and
      ;; replaces xlink:href= with href=.
      ;; Fix xmlns:xlink and xlink:href
      (edraw-svg-compatibility-fix dom)
      dom)))

(defun edraw-svg-decode-svg (data base64-p
                                  &optional accepts-top-level-comments-p)
  (let* ((dom (edraw-svg-decode data base64-p))
         (root-svg (car (edraw-dom-split-top-nodes dom))))
    ;; Recover missing xmlns on root-svg.
    ;; libxml-parse-xml-region drops the xmlns attribute.
    (when (edraw-dom-tag-eq root-svg 'svg)
      (unless (dom-attr root-svg 'xmlns)
        (dom-set-attribute root-svg 'xmlns "http://www.w3.org/2000/svg")))

    ;; Strip `top' root element generated by libxml-parse-xml-region.
    (if accepts-top-level-comments-p
        dom
      root-svg)))

(defun edraw-svg-encode (svg base64-p gzip-p)
  (with-temp-buffer
    (edraw-svg-print
     svg
     nil
     'edraw-svg-print-attr-filter)
    (edraw-encode-buffer base64-p gzip-p)
    (buffer-string)))


;;;; SVG File I/O


(defun edraw-svg-make-file-writer (path gzip-p)
  (lambda (svg)
    (edraw-svg-write-to-file svg path gzip-p)))

(defun edraw-svg-write-to-file (svg path gzip-p)
  (with-temp-file path
    (insert (edraw-svg-encode svg nil gzip-p))
    (set-buffer-file-coding-system 'utf-8)))

(defun edraw-svg-read-from-file (path &optional accepts-top-level-comments-p)
  (edraw-svg-decode-svg
   (with-temp-buffer
     (insert-file-contents path)
     (buffer-substring-no-properties (point-min) (point-max)))
   nil
   accepts-top-level-comments-p))


;;;; SVG Attributes

;;;;; Regexp

;; https://www.w3.org/TR/SVG11/types.html#DataTypeNumber
(defconst edraw-svg-number-re
  ;; Valid: 12  12.34  .34
  ;; Invalid: 12.
  "\\([+-]?\\(?:[0-9]+\\|[0-9]*\\.[0-9]+\\)\\(?:[Ee][+-]?[0-9]+\\)?\\)")

;; https://www.w3.org/TR/SVG11/types.html#DataTypeLength
(defconst edraw-svg-unit-re
  "\\(em\\|ex\\|px\\|in\\|cm\\|mm\\|pt\\|pc\\|\\%\\)?")

(defconst edraw-svg-length-re
  (concat edraw-svg-number-re edraw-svg-unit-re))

(defconst edraw-svg-attr-length-re
  (concat "\\`[ \t\n\r]*" edraw-svg-length-re "[ \t\n\r]*\\'"))

(defun edraw-svg-attr-length-match (value)
  (when (string-match edraw-svg-attr-length-re value)
    (cons (string-to-number (match-string 1 value))
          (match-string 2 value))))

;;;;; Length

;;@todo default values
(defconst edraw-svg-attr-default-font-size 16)
(defconst edraw-svg-attr-default-dpi 96)

(defun edraw-svg-attr-length-dpi ()
  edraw-svg-attr-default-dpi)

(defun edraw-svg-attr-length-em (element)
  ;; @todo Is there a way to get the exact em?
  ;; @todo Style should be considered.
  (or (edraw-svg-attr-length-or-inherited element 'font-size)
      edraw-svg-attr-default-font-size))

(defun edraw-svg-attr-length-ex (element)
  ;; @todo Is there a way to get the exact ex?
  ;; @todo Style should be considered.
  (/ (edraw-svg-attr-length-em element) 2))

(defun edraw-svg-attr-length-viewport-size (element)
  (if-let ((svg (if (eq (dom-tag element) 'svg)
                    element
                  (edraw-dom-get-ancestor-by-tag element 'svg))))
      (if-let ((vbox (dom-attr svg 'viewBox)))
          ;; viewBox="<min-x> <min-y> <width> <height>"
          (let* ((vbox-vals
                  (save-match-data
                    (split-string vbox
                                  "\\([ \t\n\r]*,[ \t\n\r]*\\|[ \t\n\r]+\\)")))
                 (width (string-to-number (or (nth 2 vbox-vals) "")))
                 (height (string-to-number (or (nth 3 vbox-vals) ""))))
            (cons
             (max 0 width)
             (max 0 height)))
        ;; width= height=
        (cons
         (or (edraw-svg-attr-length element 'width) 0)
         (or (edraw-svg-attr-length element 'height) 0)))
    (cons 0 0)))

(defun edraw-svg-attr-length-percentage (element attr)
  (pcase attr
    ('font-size
     (or (edraw-svg-attr-length-or-inherited (edraw-dom-get-parent element)
                                             'font-size)
         edraw-svg-attr-default-font-size))
    ((or 'x 'rx 'cx 'width)
     (car (edraw-svg-attr-length-viewport-size element)))
    ((or 'y 'ry 'cy 'height)
     (cdr (edraw-svg-attr-length-viewport-size element)))
    (_
     ;; https://www.w3.org/TR/SVG11/coords.html#Units_viewport_percentage
     (let* ((vsize (edraw-svg-attr-length-viewport-size element))
            (vw (car vsize))
            (vh (cdr vsize)))
       (/ (sqrt (+ (* vw vw) (* vh vh))) (sqrt 2))))))

(defun edraw-svg-attr-length-match-to-number (num-unit element attr)
  ;; <length> ::=  number ("em"|"ex"|"px"|"in"|"cm"|"mm"|"pt"|"pc"|"%")?
  (if num-unit
      (let ((num (car num-unit))
            (unit (cdr num-unit)))
        (pcase unit
          ('nil num)
          ("" num)
          ("px" num)
          ("in" (* num (edraw-svg-attr-length-dpi)))
          ("cm" (/ (* num (edraw-svg-attr-length-dpi)) 2.54))
          ("mm" (/ (* num (edraw-svg-attr-length-dpi)) 25.4))
          ("pt" (/ (* num (edraw-svg-attr-length-dpi)) 72.0))
          ("pc" (/ (* num (edraw-svg-attr-length-dpi)) 6.0))
          ("em" (* (edraw-svg-attr-length-em element) num))
          ("ex" (* (edraw-svg-attr-length-ex element) num))
          ("%" (/ (* (edraw-svg-attr-length-percentage element attr) num)
                  100.0))
          (_ 0)))
    0))

;;;;; Conversion

(defun edraw-svg-attr-length-to-number (value &optional element attr)
  "Convert length attribute value to number."
  (cond
   ((null value)
    value)
   ((stringp value)
    (edraw-svg-attr-length-match-to-number (edraw-svg-attr-length-match value)
                                           element
                                           attr))
   ((numberp value)
    value)
   ;; symbol?
   (t
    value)))

(defun edraw-svg-attr-number-to-number (value)
  "Convert number attribute value to number."
  (cond
   ((null value)
    value)
   ((stringp value)
    (string-to-number value)) ;;@todo invalid format
   ((numberp value)
    value)
   ;; symbol?
   (t
    value)))

(defun edraw-svg-ensure-string-attr (value)
  "Convert attribute value to string."
  (cond
   ((null value) "")
   ((numberp value) (edraw-to-string value))
   (t (format "%s" value))))

;;;;; Get Attribute

(defun edraw-svg-attr-number (element attr)
  "Return the number attribute ATTR from ELEMENT."
  (edraw-svg-attr-number-to-number (dom-attr element attr)))

(defun edraw-svg-attr-coord (element attr)
  "Return the coordinate attribute ATTR from ELEMENT."
  ;; <coordinate> ::= <length>
  (edraw-svg-attr-length element attr))

(defun edraw-svg-attr-length (element attr)
  "Return the length attribute ATTR from ELEMENT."
  (edraw-svg-attr-length-to-number (dom-attr element attr)
                                   element
                                   attr))

(defun edraw-svg-attr-length-or-inherited (element attr)
  (when element
    (if (dom-attr element attr)
        (edraw-svg-attr-length element attr)
      (edraw-svg-attr-length-or-inherited (edraw-dom-get-parent element)
                                          attr))))

;;;;; Set Attribute

(defun edraw-svg-set-attr-string (element attribute value)
  "Set ATTRIBUTE in ELEMENT to string VALUE.
VALUE is converted to a string for sure."
  (dom-set-attribute element attribute (edraw-svg-ensure-string-attr value)))

(defun edraw-svg-set-attr-number (element attribute value)
  "Set ATTRIBUTE in ELEMENT to number VALUE.
To avoid numerical errors, VALUE is not converted to
anything. Numeric values are set as numeric values and strings
are set as strings."
  (dom-set-attribute element attribute value))


;;;; SVG Transform Attribute

(defconst edraw-svg-transform-number
  "\\(?:[-+]?\\(?:[0-9]+\\(?:\\.[0-9]*\\)?\\|\\.[0-9]+\\)\\(?:[eE][-+]?[0-9]+\\)?\\)")
(defconst edraw-svg-transform-unit "\\(?:[a-z]+\\|%\\)")
(defconst edraw-svg-transform-number-unit
  (concat edraw-svg-transform-number edraw-svg-transform-unit "?"))
(defconst edraw-svg-transform-wsp "\\(?:[ \t\n\f\r]+\\)")
(defconst edraw-svg-transform-wsp-opt "[ \t\n\f\r]*")
(defconst edraw-svg-transform-comma-wsp "\\(?:[ \t\n\f\r]+,?[ \t\n\f\r]*\\|,[ \t\n\f\r]*\\)")
(defconst edraw-svg-transform-function
  (concat
   edraw-svg-transform-wsp-opt
   ;; (1) function name
   "\\([A-Za-z0-9_]+\\)"
   edraw-svg-transform-wsp-opt
   "("
   edraw-svg-transform-wsp-opt
   ;;(2) command arguments
   "\\(" edraw-svg-transform-number-unit
   "\\(?:" edraw-svg-transform-comma-wsp edraw-svg-transform-number-unit "\\)*\\)?"
   edraw-svg-transform-wsp-opt ")" edraw-svg-transform-wsp-opt))

(defun edraw-svg-transform-parse-numbers (numbers-str)
  (when numbers-str
    (mapcar
     (lambda (ns)
       (when (string-match
              (concat "\\(" edraw-svg-transform-number "\\)"
                      "\\(" edraw-svg-transform-unit "\\)?")
              ns)
         (let ((num (string-to-number (match-string 1 ns)))
               (unit (match-string 2 ns)))
           (pcase unit
             ((or 'nil "") num)
             ;; angle to degrees
             ("deg" num)
             ("rad" (radians-to-degrees num))
             ("grad" (/ (* num 180) 200.0))
             ("turn" (* 360 num))
             ;; length to px
             ;;@todo relative
             ("cm" (/ (* num 96) 2.54))
             ("mm" (/ (* num 96) 25.4))
             ("Q" (/ (* num 96) 2.54 40))
             ("in" (* num 96))
             ("pc" (/ (* num 96) 6))
             ("pt" (/ (* num 96) 72))
             ("px" num)
             (_ (cons num unit))))))
     (split-string numbers-str
                   edraw-svg-transform-comma-wsp))))

(defun edraw-svg-transform-parse (str)
  (let ((pos 0)
        functions)
    (while (and (string-match edraw-svg-transform-function str pos)
                (= (match-beginning 0) pos))
      (setq pos (match-end 0))
      (let* ((fname (match-string 1 str))
             (numbers-str (match-string 2 str))
             (numbers (edraw-svg-transform-parse-numbers numbers-str)))
        (push (cons fname numbers) functions)))
    (when (/= pos (length str))
      (error "transform value parsing error at %s" (substring str pos)))
    (nreverse functions)))

;;TEST: (edraw-svg-transform-parse "") => nil
;;TEST: (edraw-svg-transform-parse "translate(10 20)") => (("translate" 10 20))
;;TEST: (edraw-svg-transform-parse "rotate(180deg)") => (("rotate" 180))
;;TEST: (edraw-svg-transform-parse "scale(2) rotate(0.125turn)") => (("scale" 2) ("rotate" 45.0))

(defun edraw-svg-transform-apply (fname-args)
  (let ((fname (car fname-args))
        (args (cdr fname-args)))
    (apply (intern (concat "edraw-svg-transform--" fname)) args)))

(defun edraw-svg-transform--matrix (a b c d e f)
  (edraw-matrix (vector a b c d e f)))

(defun edraw-svg-transform--translate (tx &optional ty)
  (edraw-matrix-translate tx (or ty 0) 0))

(defun edraw-svg-transform--translateX (tx)
  (edraw-matrix-translate tx 0 0))

(defun edraw-svg-transform--translateY (ty)
  (edraw-matrix-translate 0 ty 0))

(defun edraw-svg-transform--scale (sx &optional sy)
  (edraw-matrix-scale sx (or sy sx) 1))

(defun edraw-svg-transform--scaleX (sx)
  (edraw-matrix-scale sx 1 1))

(defun edraw-svg-transform--scaleY (sy)
  (edraw-matrix-scale 1 sy 1))

(defun edraw-svg-transform--rotate (angle-deg &optional cx cy)
  (if (or cx cy)
      (edraw-matrix-mul-mat-mat
       (edraw-matrix-translate (or cx 0) (or cy 0) 0)
       (edraw-matrix-mul-mat-mat
        (edraw-matrix-rotate angle-deg)
        (edraw-matrix-translate (- (or cx 0)) (- (or cy 0)) 0)))
    (edraw-matrix-rotate angle-deg)))

(defun edraw-svg-transform--skew (ax-deg &optional ay-deg)
  (edraw-matrix-skew ax-deg (or ay-deg 0)))

(defun edraw-svg-transform--skewX (ax-deg)
  (edraw-matrix-skew ax-deg 0))

(defun edraw-svg-transform--skewY (ay-deg)
  (edraw-matrix-skew 0 ay-deg))

(defun edraw-svg-transform-to-matrix (str)
  (seq-reduce #'edraw-matrix-mul-mat-mat
              (mapcar #'edraw-svg-transform-apply
                      (edraw-svg-transform-parse str))
              (edraw-matrix)))

;;TEST: (edraw-svg-transform-to-matrix "translate(10 20)") => [1 0 0 0 0 1 0 0 0 0 1 0 10 20 0 1]
;;TEST: (edraw-svg-transform-to-matrix "scale(2) translate(10 20)") => [2 0 0 0 0 2 0 0 0 0 1 0 20 40 0 1]
;;TEST: (edraw-svg-transform-to-matrix "rotate(45deg)") => [0.7071067811865476 0.7071067811865475 0.0 0.0 -0.7071067811865475 0.7071067811865476 0.0 0.0 0 0 1 0 0 0 0 1]
;;TEST: (edraw-svg-transform-to-matrix "rotate(45deg 10 10)") => [0.7071067811865476 0.7071067811865475 0.0 0.0 -0.7071067811865475 0.7071067811865476 0.0 0.0 0.0 0.0 1.0 0.0 10.0 -4.142135623730951 0.0 1.0]

(defun edraw-svg-transform-from-matrix (mat)
  (when mat
    (format "matrix(%s,%s,%s,%s,%s,%s)"
            (edraw-to-string (edraw-matrix-at mat 0))
            (edraw-to-string (edraw-matrix-at mat 1))
            (edraw-to-string (edraw-matrix-at mat 4))
            (edraw-to-string (edraw-matrix-at mat 5))
            (edraw-to-string (edraw-matrix-at mat 12))
            (edraw-to-string (edraw-matrix-at mat 13)))))

(defun edraw-svg-element-transform-get (element &optional matrix)
  (edraw-matrix-mul-mat-mat
   ;;nil means identity matrix
   matrix
   (when-let ((transform-str (dom-attr element 'transform)))
     (ignore-errors
       (edraw-svg-transform-to-matrix transform-str)))))

(defun edraw-svg-element-transform-set (element mat)
  (if (edraw-matrix-identity-p mat)
      (edraw-dom-remove-attr element 'transform)
    (edraw-svg-set-attr-string element 'transform (edraw-svg-transform-from-matrix mat))))

(defun edraw-svg-element-transform-multiply (element mat)
  (unless (edraw-matrix-identity-p mat)
    (edraw-svg-element-transform-set
     element
     (edraw-svg-element-transform-get element mat))))

(defun edraw-svg-element-transform-translate (element xy)
  (when (and xy (not (edraw-xy-zero-p xy)))
    (let ((transform (or
                      (edraw-svg-element-transform-get element)
                      (edraw-matrix))))
      (edraw-matrix-translate-add transform (car xy) (cdr xy))
      (edraw-svg-element-transform-set element transform))))


;;;; SVG Compatibility

(defun edraw-svg-compatibility-fix (svg)
  (let ((ver.1.1-p (version<= edraw-svg-version "1.1")))
    (edraw-dom-do
     svg
     (lambda (node _ancestors)
       (when (edraw-dom-element-p node)
         ;; xmlns:xlink= and version=
         (when (edraw-dom-tag-eq node 'svg)
           (if ver.1.1-p
               (progn
                 (dom-set-attribute node 'xmlns:xlink "http://www.w3.org/1999/xlink")
                 (dom-set-attribute node 'version edraw-svg-version))
             (edraw-dom-remove-attr node 'xmlns:xlink)
             (edraw-dom-remove-attr node 'version)))

         ;; xlink:href
         (if ver.1.1-p
             ;; Use xlink:href
             (edraw-dom-set-attribute-name node 'href 'xlink:href)

           ;; Use href
           (edraw-dom-set-attribute-name node 'xlink:href 'href)))))))

(defun edraw-svg-href-symbol ()
  (if (version<= edraw-svg-version "1.1")
      'xlink:href
    'href))

;;;; SVG Element Creation

(defun edraw-svg-create (width height &rest attr-plist-and-children)
  (apply #'edraw-dom-element
         'svg
         `(width
           ,width
           height ,height
           xmlns "http://www.w3.org/2000/svg"
           ,@(when (version<= edraw-svg-version "1.1")
               (list
                'version edraw-svg-version
                'xmlns:xlink "http://www.w3.org/1999/xlink"))
           ,@attr-plist-and-children)))

(defun edraw-svg-rect (x y width height &rest attr-plist-and-children)
  "Create a `rect' element.
Attributes are specified by X, Y, WIDTH, HEIGHT, and ATTR-PLIST-AND-CHILDREN.

See `edraw-dom-element' for more information about ATTR-PLIST-AND-CHILDREN."
  (apply #'edraw-dom-element
         'rect
         `(x ,x y ,y width ,width height ,height ,@attr-plist-and-children)))

(defun edraw-svg-circle (cx cy r &rest attr-plist-and-children)
  "Create a `circle' element.
Attributes are specified by CX, CY, R, and ATTR-PLIST-AND-CHILDREN.

See `edraw-dom-element' for more information about ATTR-PLIST-AND-CHILDREN."
  (apply #'edraw-dom-element
         'circle
         `(cx ,cx cy ,cy r ,r ,@attr-plist-and-children)))

(defun edraw-svg-ellipse (cx cy rx ry &rest attr-plist-and-children)
  "Create an `ellipse' element.
Attributes are specified by CX, CY, RX, RY, and ATTR-PLIST-AND-CHILDREN.

See `edraw-dom-element' for more information about ATTR-PLIST-AND-CHILDREN."
  (apply #'edraw-dom-element
         'ellipse
         `(cx ,cx cy ,cy rx ,rx ry ,ry ,@attr-plist-and-children)))

(defun edraw-svg-line (x1 y1 x2 y2 &rest attr-plist-and-children)
  "Create a `line' element.
Attributes are specified by X1, Y1, X2, Y2, and ATTR-PLIST-AND-CHILDREN.

See `edraw-dom-element' for more information about ATTR-PLIST-AND-CHILDREN."
  (apply #'edraw-dom-element
         'line
         `(x1 ,x1 y1 ,y1 x2 ,x2 y2 ,y2 ,@attr-plist-and-children)))

(defun edraw-svg-path (d &rest attr-plist-and-children)
  "Create a `path' element.
Attributes are specified by D, and ATTR-PLIST-AND-CHILDREN.

See `edraw-dom-element' for more information about ATTR-PLIST-AND-CHILDREN."
  (apply #'edraw-dom-element
         'path
         `(d ,d ,@attr-plist-and-children)))

(defun edraw-svg-polygon (points &rest attr-plist-and-children)
  "Create a `polygon' element.
Attributes are specified by POINTS, and ATTR-PLIST-AND-CHILDREN.

POINTS is a string or a list of cons cell representing coordinates.

See `edraw-dom-element' for more information about ATTR-PLIST-AND-CHILDREN."
  (apply #'edraw-dom-element
         'polygon
         `(points
           ,(if (stringp points)
                points
              (mapconcat (lambda (xy) (format "%s %s" (car xy) (cdr xy)))
                         points " "))
           ,@attr-plist-and-children)))

(defun edraw-svg-polyline (points &rest attr-plist-and-children)
  "Create a `polyline' element.
Attributes are specified by POINTS, and ATTR-PLIST-AND-CHILDREN.

POINTS is a string or a list of cons cell representing coordinates.

See `edraw-dom-element' for more information about ATTR-PLIST-AND-CHILDREN."
  (apply #'edraw-dom-element
         'polyline
         `(points
           ,(if (stringp points)
                points
              (mapconcat (lambda (xy) (format "%s %s" (car xy) (cdr xy)))
                         points " "))
           ,@attr-plist-and-children)))

(defun edraw-svg-group (&rest attr-plist-and-children)
  "Create a `g' element.
Attributes and children are specified by ATTR-PLIST-AND-CHILDREN.

For example:
  (edraw-svg-group
  :class \"red-cross\"
  :stroke \"red\"
  :stroke-width 10
  (edraw-svg-line 0 -100 0 100)
  (edraw-svg-line -100 0 100 0))

See `edraw-dom-element' for more information about ATTR-PLIST-AND-CHILDREN."
  (apply #'edraw-dom-element 'g attr-plist-and-children))


;;;; SVG Shape Rectangular Range Setting


(defun edraw-svg-rect-set-range (element xy0 xy1)
  (edraw-svg-set-attr-number element 'x (min (car xy0) (car xy1)))
  (edraw-svg-set-attr-number element 'y (min (cdr xy0) (cdr xy1)))
  (edraw-svg-set-attr-number element 'width (abs (- (car xy0) (car xy1))))
  (edraw-svg-set-attr-number element 'height (abs (- (cdr xy0) (cdr xy1)))))

(defun edraw-svg-ellipse-set-range (element xy0 xy1)
  (edraw-svg-set-attr-number element 'cx (* 0.5 (+ (car xy0) (car xy1))))
  (edraw-svg-set-attr-number element 'cy (* 0.5 (+ (cdr xy0) (cdr xy1))))
  (edraw-svg-set-attr-number element 'rx (* 0.5 (abs (- (car xy0) (car xy1)))))
  (edraw-svg-set-attr-number element 'ry (* 0.5 (abs (- (cdr xy0) (cdr xy1))))))

(defun edraw-svg-image-set-range (element xy0 xy1)
  (edraw-svg-set-attr-number element 'x (min (car xy0) (car xy1)))
  (edraw-svg-set-attr-number element 'y (min (cdr xy0) (cdr xy1)))
  (edraw-svg-set-attr-number element 'width (abs (- (car xy0) (car xy1))))
  (edraw-svg-set-attr-number element 'height (abs (- (cdr xy0) (cdr xy1)))))


;;;; SVG Shape Summary


(defun edraw-svg-element-summary (element)
  (pcase (dom-tag element)
    ('path (edraw-svg-path-summary element))
    ('rect (edraw-svg-rect-summary element))
    ('ellipse (edraw-svg-ellipse-summary element))
    ('circle (edraw-svg-circle-summary element))
    ('text (edraw-svg-text-summary element))
    ('image (edraw-svg-image-summary element))
    ('g (edraw-svg-group-summary element))))

(defun edraw-svg-path-summary (element)
  (format "path (%s)"
          (truncate-string-to-width
           (or (dom-attr element 'd) "") 20 nil nil "...")))

(defun edraw-svg-rect-summary (element)
  (format "rect (%s,%s,%s,%s)"
          (dom-attr element 'x)
          (dom-attr element 'y)
          (dom-attr element 'width)
          (dom-attr element 'height)))

(defun edraw-svg-ellipse-summary (element)
  (format "ellipse (%s,%s,%s,%s)"
          (dom-attr element 'cx)
          (dom-attr element 'cy)
          (dom-attr element 'rx)
          (dom-attr element 'ry)))

(defun edraw-svg-circle-summary (element)
  (format "circle (%s,%s,%s)"
          (dom-attr element 'cx)
          (dom-attr element 'cy)
          (dom-attr element 'r)))

(defun edraw-svg-text-summary (element)
  (format "text (%s)"
          (truncate-string-to-width (dom-text element) 20 nil nil "...")))

(defun edraw-svg-image-summary (element)
  (format "image (%s,%s,%s,%s,%s)"
          (dom-attr element 'x)
          (dom-attr element 'y)
          (dom-attr element 'width)
          (dom-attr element 'height)
          (truncate-string-to-width
           (or (dom-attr element (edraw-svg-href-symbol)) "")
           20 nil nil "...")))

(defun edraw-svg-group-summary (element)
  (format "group (%s children)" ;;@todo edraw-msg (require 'edraw-util)
          (length (dom-children element))))


;;;; SVG Shape Properties

(defconst edraw-svg-elem-prop-number-types
  '(number opacity length coordinate))

(defconst edraw-svg-element-properties-common
  ;;name source type flags attrs...
  '((opacity attr opacity nil)
    (fill attr-fill-stroke paint nil)
    (fill-opacity attr opacity nil)
    (stroke attr-fill-stroke paint nil)
    (stroke-opacity attr opacity nil)
    (stroke-width attr length nil)
    (stroke-dasharray attr string nil)
    (stroke-dashoffset attr length nil)
    (style attr string nil)
    (transform attr string (geometry))))
(defconst edraw-svg-element-properties-path-common
  '((fill-rule attr (or "nonzero" "evenodd") nil)
    (stroke-linecap attr (or "butt" "round" "square") nil)
    (stroke-linejoin attr (or "miter" "round" "bevel") nil)
    (stroke-miterlimit attr number nil)))
(defconst edraw-svg-element-properties
  `((rect
     (x attr coordinate (required geometry))
     (y attr coordinate (required geometry))
     (width attr length (required geometry))
     (height attr length (required geometry))
     (rx attr length (geometry))
     (ry attr length (geometry))
     ,@edraw-svg-element-properties-common)
    (circle
     (cx attr coordinate (required geometry))
     (cy attr coordinate (required geometry))
     (r attr length (required geometry))
     ,@edraw-svg-element-properties-common)
    (ellipse
     (cx attr coordinate (required geometry))
     (cy attr coordinate (required geometry))
     (rx attr length (required geometry))
     (ry attr length (required geometry))
     ,@edraw-svg-element-properties-common)
    (path
     (d attr string (required geometry) :internal t)
     ,@edraw-svg-element-properties-common
     ,@edraw-svg-element-properties-path-common
     (marker-start attr-marker marker nil)
     (marker-mid attr-marker marker nil)
     (marker-end attr-marker marker nil))
    (text
     (text inner-text text (required geometry))
     ;; librsvg does not support list-of-coordinates
     ;; https://gitlab.gnome.org/GNOME/librsvg/-/issues/183
     (x attr coordinate (required geometry))
     (y attr coordinate (required geometry))
     (dx attr coordinate (geometry))
     (dy attr coordinate (geometry))
     ;; librsvg does not support?
     ;;(rotate attr string nil)
     ;; librsvg does not support textLength
     ;; https://gitlab.gnome.org/GNOME/librsvg/-/issues/88
     ;;(textLength attr number nil)
     ;;(lengthAdjust attr (or "spacing" "spacingAndGlyphs") nil)
     (font-family attr font-family nil)
     (font-size attr number (geometry))
     (font-weight attr (or "normal" "bold" "bolder" "lighter") nil)
     (font-style attr (or "normal" "italic" "oblique") nil)
     (text-decoration attr (or "underline" "overline" "line-through") nil)
     (text-anchor attr (or "start" "middle" "end") (geometry))
     (writing-mode attr-update-text
                   (or "horizontal-tb" "vertical-rl" "vertical-lr") (geometry))
     ;; https://gitlab.gnome.org/GNOME/librsvg/-/issues/129
     ;;(baseline-shift attr number nil)
     (data-edraw-text-leading attr-update-text number (geometry))
     ,@edraw-svg-element-properties-common)
    (image
     (x attr coordinate (required geometry))
     (y attr coordinate (required geometry))
     (width attr length (required geometry))
     (height attr length (required geometry))
     ;;@todo should change dynamically depending on edraw-svg-version
     (xlink:href attr string ,(when (eq (edraw-svg-href-symbol) 'xlink:href) '(required)))
     (href attr string  ,(when (eq (edraw-svg-href-symbol) 'href) '(required)))
     (preserveAspectRatio attr string nil)
     (opacity attr opacity nil)
     (style attr string nil)
     (transform attr string (geometry)))
    (g
     ,@edraw-svg-element-properties-common
     ,@edraw-svg-element-properties-path-common)))
(defun edraw-svg-elem-prop-name (prop-def) (nth 0 prop-def))
(defun edraw-svg-elem-prop-source (prop-def) (nth 1 prop-def))
(defun edraw-svg-elem-prop-type (prop-def) (nth 2 prop-def))
(defun edraw-svg-elem-prop-flags (prop-def) (nth 3 prop-def))
(defun edraw-svg-elem-prop-attrs (prop-def) (nthcdr 4 prop-def))
(defun edraw-svg-elem-prop-required (prop-def)
  (when (memq 'required (edraw-svg-elem-prop-flags prop-def)) t))

(defun edraw-svg-elem-prop-number-p (prop-def)
  (memq (edraw-svg-elem-prop-type prop-def) edraw-svg-elem-prop-number-types))

(defun edraw-svg-element-get-property-info-list (element)
  (edraw-svg-element-get-property-info-list-by-tag (dom-tag element)))

(defun edraw-svg-element-get-property-info-list-by-tag (tag)
  (when-let ((prop-def-list (alist-get tag edraw-svg-element-properties)))
    (cl-loop for prop-def in prop-def-list
             for prop-type = (edraw-svg-elem-prop-type prop-def)
             collect
             (append
              (list :name (edraw-svg-elem-prop-name prop-def)
                    :type prop-type
                    :required (edraw-svg-elem-prop-required prop-def)
                    :flags (edraw-svg-elem-prop-flags prop-def)
                    :to-string #'edraw-svg-ensure-string-attr
                    :from-string #'identity
                    :number-p (edraw-svg-elem-prop-number-p prop-def)
                    :to-number (pcase prop-type
                                 ('coordinate #'edraw-svg-attr-length-to-number)
                                 ('length #'edraw-svg-attr-length-to-number)
                                 ('number #'edraw-svg-attr-number-to-number)
                                 ('opacity #'edraw-svg-attr-number-to-number)
                                 (_ nil))
                    )
              (edraw-svg-elem-prop-attrs prop-def)))))
;; TEST: (edraw-svg-element-get-property-info-list-by-tag 'rect)

(defun edraw-svg-element-can-have-property-p (element prop-name)
  (edraw-svg-tag-can-have-property-p (dom-tag element) prop-name))

(defun edraw-svg-tag-can-have-property-p (tag prop-name)
  (when-let ((prop-def-list (alist-get tag edraw-svg-element-properties)))
    (seq-some (lambda (prop-def) (eq (edraw-svg-elem-prop-name prop-def)
                                     prop-name))
              prop-def-list)))

(defun edraw-svg-element-get-property (element prop-name defrefs)
  (when-let ((prop-def-list (alist-get (dom-tag element) edraw-svg-element-properties))
             (prop-def (assq prop-name prop-def-list)))
    (let* ((source (edraw-svg-elem-prop-source prop-def))
           (getter (intern
                    (concat "edraw-svg-element-get-" (symbol-name source)))))
      (funcall getter element prop-name defrefs))))

(defun edraw-svg-element-set-property (element prop-name value defrefs)
  (when-let ((prop-def-list (alist-get (dom-tag element) edraw-svg-element-properties))
             (prop-def (assq prop-name prop-def-list)))
    (let* ((source (edraw-svg-elem-prop-source prop-def))
           (setter (intern
                    (concat "edraw-svg-element-set-" (symbol-name source)))))
      (funcall setter element prop-name value defrefs))))

(defun edraw-svg-element-has-property-p (element prop-name defrefs)
  (not (null (edraw-svg-element-get-property element prop-name defrefs))))

;; Property Source

(defun edraw-svg-element-get-attr (element prop-name _defrefs)
  ;; nil means no property.
  ;; Return nil, string, or other stored types like a number.
  (dom-attr element prop-name))

(defun edraw-svg-element-set-attr (element prop-name value _defrefs)
  (cond
   ;; nil means no property.
   ((null value)
    (edraw-dom-remove-attr element prop-name))
   ;; x of text must by changed along with inner tspans.
   ((and (eq (dom-tag element) 'text)
         (eq prop-name 'x))
    (edraw-svg-text-set-x element value))
   ;; y of text must by changed along with inner tspans if vertical writing.
   ((and (eq (dom-tag element) 'text)
         (eq prop-name 'y))
    (edraw-svg-text-set-y element value))
   ;; Store as is. Avoid numerical errors.
   ((numberp value)
    (edraw-svg-set-attr-number element prop-name value))
   ((stringp value)
    (edraw-svg-set-attr-string element prop-name value))
   (t
    (dom-set-attribute element prop-name value))))

(defun edraw-svg-element-get-inner-text (element _prop-name _defrefs)
  (edraw-svg-text-get-text element))

(defun edraw-svg-element-set-inner-text (element _prop-name value _defrefs)
  (edraw-svg-text-set-text element value))

(defun edraw-svg-element-get-attr-update-text (element prop-name defrefs)
  (edraw-svg-element-get-attr element prop-name defrefs))

(defun edraw-svg-element-set-attr-update-text (element prop-name value defrefs)
  (edraw-svg-element-set-attr element prop-name value defrefs)
  (edraw-svg-text-update-text element))

(defun edraw-svg-element-get-attr-marker (element prop-name defrefs)
  (edraw-svg-get-marker-property element prop-name defrefs))

(defun edraw-svg-element-set-attr-marker (element prop-name value defrefs)
  (edraw-svg-set-marker-property element prop-name value defrefs))

(defun edraw-svg-element-get-attr-fill-stroke (element prop-name defrefs)
  (edraw-svg-element-get-attr element prop-name defrefs))

(defun edraw-svg-element-set-attr-fill-stroke (element prop-name value defrefs)
  (edraw-svg-element-set-attr element prop-name value defrefs)
  (edraw-svg-update-marker-properties element defrefs))


;;;; SVG Text Layout

(defun edraw-svg-text-update-text (element)
  (edraw-svg-text-set-text element (edraw-svg-text-get-text element)))

(defun edraw-svg-text-set-text (element text)
  (edraw-dom-remove-all-children element)

  (when (stringp text)
    (let ((lines (split-string text "\n")))
      (if (null (cdr lines))
          ;; single line
          (edraw-dom-append-child element (car lines)) ;; string
        ;; multi-line
        (edraw-svg-text--set-text-multiline element lines)))))

(defun edraw-svg-text--set-text-multiline (element lines)
  (let* ((vertical-p (edraw-svg-text-vertical-writing-p element))
         (negative-dir-p (eq (edraw-svg-text-writing-mode element)
                             'vertical-rl))
         (attr-col (if vertical-p 'y 'x))
         (col (or (edraw-svg-attr-coord element attr-col) 0))
         (attr-line-delta (if vertical-p 'dx 'dy))
         (leading (edraw-svg-attr-length element 'data-edraw-text-leading))
         (line-delta-unit (if leading "" "em"))
         (line-delta-step-abs (or leading 1))
         (line-delta-step (if negative-dir-p
                              (- line-delta-step-abs)
                            line-delta-step-abs))
         (line-delta 0))
    (dolist (line lines)
      (edraw-dom-element 'tspan
                         :parent element
                         :class "text-line"
                         attr-col col
                         :attributes
                         (when (and (/= line-delta 0)
                                    (not (string-empty-p line)))
                           (list attr-line-delta
                                 (format "%s%s"
                                         line-delta
                                         line-delta-unit)))
                         ;; string
                         line)
      (unless (string-empty-p line)
        (setq line-delta 0))
      (cl-incf line-delta line-delta-step))))

(defun edraw-svg-text-get-text (element)
  (if (stringp (car (dom-children element)))
      (car (dom-children element))
    (let ((tspans (dom-by-class element "\\`text-line\\'")))
      (mapconcat (lambda (tspan) (dom-text tspan)) tspans "\n"))))

(defun edraw-svg-text-set-x (element x)
  (edraw-svg-set-attr-number element 'x x)
  (unless (edraw-svg-text-vertical-writing-p element)
    (let ((tspans (dom-by-class element "\\`text-line\\'")))
      (dolist (tspan tspans)
        (edraw-svg-set-attr-number tspan 'x x)))))

(defun edraw-svg-text-set-y (element y)
  (edraw-svg-set-attr-number element 'y y)
  (when (edraw-svg-text-vertical-writing-p element)
    (let ((tspans (dom-by-class element "\\`text-line\\'")))
      (dolist (tspan tspans)
        (edraw-svg-set-attr-number tspan 'y y)))))

(defun edraw-svg-text-set-xy (element xy)
  (edraw-svg-text-set-x element (car xy))
  (edraw-svg-text-set-y element (cdr xy)))


;;;; SVG Defs


(defun edraw-svg-defs-as-defrefs (id)
  (edraw-svg-defrefs
   (edraw-dom-element 'defs :id id)))


;;;;; Definition and Referrers Pair


(defun edraw-svg-defref (def-element idnum)
  "Create a definition-referrers pair.

DEF-ELEMENT is an element under the defs element. For example,
one of the elements that is reused from others, such as <marker>
or <linearGradient>.

IDNUM is the identification number of DEF-ELEMENT."
  (list def-element idnum))

(defun edraw-svg-defref-def-element (defref) (car defref))
(defun edraw-svg-defref-idnum (defref) (cadr defref))
(defun edraw-svg-defref-referrers (defref) (cddr defref))
(defun edraw-svg-defref-referrers--head (defref) (cdr defref))

(defun edraw-svg-defref-add-referrer (defref referrer-element)
  "Add REFERRER-ELEMENT that references the definition element of DEFREF."
  (setcdr (edraw-svg-defref-referrers--head defref)
          (cons referrer-element (edraw-svg-defref-referrers defref))))

(defun edraw-svg-defref-remove-referrer (defref referrer-element)
  "Remove REFERRER-ELEMENT that references the definition element of DEFREF.

The same ELEMENT may exist multiple times in the list, in which
case only the first one is removed."
  (let ((cell (edraw-svg-defref-referrers--head defref)))
    (while (and (cdr cell)
                (not (eq (cadr cell) referrer-element)))
      (setq cell (cdr cell)))
    (when (cdr cell)
      (setcdr cell (cddr cell)))))

(defun edraw-svg-defref-empty-p (defref)
  (null (edraw-svg-defref-referrers defref)))

(defun edraw-svg-def-element-equal-p (a b)
  ;; equal except id
  (and
   (eq (dom-tag a) (dom-tag b))
   (seq-set-equal-p
    (seq-remove (lambda (atr) (eq (car atr) 'id)) (dom-attributes a))
    (seq-remove (lambda (atr) (eq (car atr) 'id)) (dom-attributes b)))
   (equal (dom-children a) (dom-children b))))


;;;;; Definition and Referrers Table


(defun edraw-svg-defrefs (defs-element)
  "Create a definition-referrers table.

DEFS-ELEMENT is a <defs> element for storing definitions."
  (list defs-element))

(defun edraw-svg-defrefs-defs-element (defrefs) (car defrefs))
(defun edraw-svg-defrefs-defrefs (defrefs) (cdr defrefs))
(defun edraw-svg-defrefs-defrefs--head (defrefs) defrefs)

(defun edraw-svg-defrefs-insert-with-unused-idnum (defrefs def-element)
  (let ((idnum 0)
        (cell (edraw-svg-defrefs-defrefs--head defrefs)))
    (while (and (cdr cell)
                (= idnum (edraw-svg-defref-idnum (cadr cell))))
      (setq cell (cdr cell))
      (setq idnum (1+ idnum)))
    (let ((defref (edraw-svg-defref def-element idnum)))
      (setcdr cell (cons defref (cdr cell)))
      defref)))

(defun edraw-svg-defrefs-add-ref (defrefs def-element referrer-element
                                   prop-value)
  (if-let ((defref (assoc def-element (edraw-svg-defrefs-defrefs defrefs)
                          'edraw-svg-def-element-equal-p)))
      (progn
        (edraw-svg-defref-add-referrer defref referrer-element)
        (format "url(#edraw-def-%s-%s)"
                (edraw-svg-defref-idnum defref)
                prop-value))
    (let* ((defref (edraw-svg-defrefs-insert-with-unused-idnum defrefs
                                                               def-element))
           (idnum (edraw-svg-defref-idnum defref)))
      ;; add a new definition element
      (edraw-svg-defref-add-referrer defref referrer-element)
      (edraw-svg-set-attr-string def-element 'id
                                 (format "edraw-def-%s-%s" idnum prop-value))
      (edraw-dom-append-child (edraw-svg-defrefs-defs-element defrefs)
                              def-element)
      (format "url(#edraw-def-%s-%s)" idnum prop-value))))

(defun edraw-svg-defrefs-remove-ref-by-idnum (defrefs idnum element)
  (let ((cell (edraw-svg-defrefs-defrefs--head defrefs)))
    (while (and (cdr cell)
                (not (= (edraw-svg-defref-idnum (cadr cell)) idnum)))
      (setq cell (cdr cell)))
    (when (cdr cell)
      (let ((defref (cadr cell)))
        (edraw-svg-defref-remove-referrer defref element)
        ;; when no referrer
        (when (edraw-svg-defref-empty-p defref)
          ;; remove definition element
          (edraw-dom-remove-node
           (edraw-svg-defrefs-defs-element defrefs)
           (edraw-svg-defref-def-element defref))
          ;; remove defref pair
          (setcdr cell (cddr cell)))))))

(defun edraw-svg-defrefs-get-by-idnum (defrefs idnum)
  (seq-find (lambda (defref) (= (edraw-svg-defref-idnum defref) idnum))
            (edraw-svg-defrefs-defrefs defrefs)))

(defun edraw-svg-defrefs-add-ref-by-idnum (defrefs idnum referrer-element)
  (when-let ((defref (edraw-svg-defrefs-get-by-idnum defrefs idnum)))
    (edraw-svg-defref-add-referrer defref referrer-element)))

(defun edraw-svg-defref-id-attr-to-idnum (id-attr)
  (and (stringp id-attr)
       (string-match "\\`edraw-def-\\([0-9]+\\)-\\([^)]+\\)\\'" id-attr)
       (string-to-number (match-string 1 id-attr))))

(defun edraw-svg-defref-url-to-idnum (url)
  (and (stringp url)
       (string-match "\\`url(#edraw-def-\\([0-9]+\\)-\\([^)]+\\))\\'" url)
       (string-to-number (match-string 1 url))))

(defun edraw-svg-defref-url-to-prop-value (url)
  (and (stringp url)
       (string-match "\\`url(#edraw-def-\\([0-9]+\\)-\\([^)]+\\))\\'" url)
       (match-string-no-properties 2 url)))

(defun edraw-svg-defrefs-remove-ref-by-url (defrefs url element)
  (when-let ((idnum (edraw-svg-defref-url-to-idnum url)))
    (edraw-svg-defrefs-remove-ref-by-idnum defrefs idnum element)))

(defun edraw-svg-defrefs-get-defref-by-url (defrefs url)
  (when-let ((idnum (edraw-svg-defref-url-to-idnum url)))
    (edraw-svg-defrefs-get-by-idnum defrefs idnum)))

(defun edraw-svg-defrefs-from-dom (defs-node body-node &optional recursive-p)
  (let ((defrefs (edraw-svg-defrefs defs-node))
        defref-list)
    ;; Collect definitions
    (dolist (def (dom-children defs-node))
      (when-let ((idnum (edraw-svg-defref-id-attr-to-idnum (dom-attr def 'id))))
        (push (edraw-svg-defref def idnum) defref-list)))
    ;; Sort and assign
    (setcdr (edraw-svg-defrefs-defrefs--head defrefs)
            (sort defref-list (lambda (defref1 defref2)
                                (< (edraw-svg-defref-idnum defref1)
                                   (edraw-svg-defref-idnum defref2)))))
    ;; Collect references
    (edraw-svg-defrefs-from-dom--collect-references defrefs body-node
                                                    recursive-p)
    ;; Remove unreferenced definitions
    (dolist (defref (edraw-svg-defrefs-defrefs defrefs))
      (when (edraw-svg-defref-empty-p defref)
        (edraw-dom-remove-node defs-node
                               (edraw-svg-defref-def-element defref))))
    (setcdr (edraw-svg-defrefs-defrefs--head defrefs)
            (seq-remove 'edraw-svg-defref-empty-p
                        (edraw-svg-defrefs-defrefs defrefs)))

    defrefs))

(defun edraw-svg-defrefs-from-dom--collect-references (defrefs
                                                       body-node
                                                       recursive-p)
  (when body-node
    (dolist (node (dom-children body-node))
      (when (edraw-dom-element-p node) ;;exclude text nodes
        (dolist (attr (dom-attributes node))
          (when (member (car attr) '(marker-start marker-mid marker-end))
            (when-let ((idnum (edraw-svg-defref-url-to-idnum (cdr attr))))
              (edraw-svg-defrefs-add-ref-by-idnum defrefs idnum node))))
        (when recursive-p
          (edraw-svg-defrefs-from-dom--collect-references defrefs node t))))))


;;;; SVG Marker

(defconst edraw-svg-marker-arrow-overhang
  (/ (*
      6 ;;markerWidth
      4) ;;arrow tip position
     20.0)) ;;viewBox width

(defun edraw-svg-marker-arrow-overhang (marker stroke-width)
  (/ (*
      stroke-width
      (edraw-svg-marker-prop-number marker 'markerWidth 6)
      4) ;;arrow tip position
     20.0)) ;;viewBox width

(defun edraw-svg-marker-arrow-props (marker-attrs)
  (list
   (cons 'markerWidth (alist-get 'markerWidth marker-attrs "6"))
   (cons 'markerHeight (alist-get 'markerHeight marker-attrs "6"))
   (cons 'refX (alist-get 'refX marker-attrs "0"))))

(defun edraw-svg-marker-arrow-create (prop-name element marker)
  (edraw-dom-element
   'marker
   :markerWidth (edraw-svg-marker-prop-str marker 'markerWidth "6")
   :markerHeight (edraw-svg-marker-prop-str marker 'markerHeight "6")
   :preserveAspectRatio "none"
   :viewBox "-10 -10 20 20"
   :refX (edraw-svg-marker-prop-str marker 'refX "0")
   :refY "0"
   :orient "auto"
   :stroke "none"
   :fill
   ;; @todo I want to use context-stroke and remove edraw-svg-update-marker-properties
   ;; https://gitlab.gnome.org/GNOME/librsvg/-/issues/618
   (let ((stroke (dom-attr element 'stroke)))
     (if (or (null stroke) (equal stroke "none"))
         "none" ;;stroke may change later
       stroke))
   ;; Children
   (edraw-svg-path
    ;; @todo I want to use auto-start-reverse
    ;; https://gitlab.gnome.org/GNOME/librsvg/-/issues/484
    (if (eq prop-name 'marker-start)
        "M10,-7 10,7 -4,0Z" ;; <|
      "M-10,-7 -10,7 4,0Z")))) ;; |>

(defun edraw-svg-marker-circle-props (marker-attrs)
  (list
   (cons 'markerWidth (alist-get 'markerWidth marker-attrs "4"))
   (cons 'markerHeight (alist-get 'markerHeight marker-attrs "4"))
   (cons 'refX (alist-get 'refX marker-attrs "0"))))

(defun edraw-svg-marker-circle-create (_prop-name element marker)
  (edraw-dom-element
   'marker
   :markerWidth (edraw-svg-marker-prop-str marker 'markerWidth "4")
   :markerHeight (edraw-svg-marker-prop-str marker 'markerHeight "4")
   :preserveAspectRatio "none"
   :viewBox "-5 -5 10 10"
   :refX (edraw-svg-marker-prop-str marker 'refX "0")
   :refY "0"
   :orient "auto"
   :stroke "none"
   :fill
   ;; @todo I want to use context-stroke
   ;; https://gitlab.gnome.org/GNOME/librsvg/-/issues/618
   (let ((stroke (dom-attr element 'stroke)))
     (if (or (null stroke) (equal stroke "none"))
         "none" ;;stroke may change later
       stroke))
   ;; Children
   (edraw-svg-circle "0" "0" "4")))

(defconst edraw-svg-marker-types
  `(("arrow"
     :overhang edraw-svg-marker-arrow-overhang
     :creator edraw-svg-marker-arrow-create
     :get-props edraw-svg-marker-arrow-props
     :prop-info-list
     ((:name markerWidth :type number :required nil :flags nil :to-string edraw-svg-ensure-string-attr :from-string identity :number-p t :to-number edraw-svg-attr-number-to-number)
      (:name markerHeight :type number :required nil :flags nil :to-string edraw-svg-ensure-string-attr :from-string identity :number-p t :to-number edraw-svg-attr-number-to-number)
      (:name refX :type number :required nil :flags nil :to-string edraw-svg-ensure-string-attr :from-string identity :number-p t :to-number edraw-svg-attr-number-to-number)))
    ("circle"
     :creator edraw-svg-marker-circle-create
     :get-props edraw-svg-marker-circle-props
     :prop-info-list
     ((:name markerWidth :type number :required nil :flags nil :to-string edraw-svg-ensure-string-attr :from-string identity :number-p t :to-number edraw-svg-attr-number-to-number)
      (:name markerHeight :type number :required nil :flags nil :to-string edraw-svg-ensure-string-attr :from-string identity :number-p t :to-number edraw-svg-attr-number-to-number)
      (:name refX :type number :required nil :flags nil :to-string edraw-svg-ensure-string-attr :from-string identity :number-p t :to-number edraw-svg-attr-number-to-number)))
    ;; Ignore "" or "none"
    ))

(defun edraw-svg-marker-type-all ()
  (mapcar #'car edraw-svg-marker-types))

(defun edraw-svg-marker-type-next (type)
  (if (null type)
      (caar edraw-svg-marker-types)
    (cl-loop for x on edraw-svg-marker-types
             when (equal (caar x) type)
             return (caadr x))))
;; TEST: (edraw-svg-marker-type-next nil) => "arrow"
;; TEST: (edraw-svg-marker-type-next "arrow") => "circle"
;; TEST: (edraw-svg-marker-type-next "circle") => nil

(defun edraw-svg-marker-prop-info-list (type)
  (when-let ((props (alist-get type edraw-svg-marker-types nil nil #'equal)))
    (plist-get props :prop-info-list)))

(defun edraw-svg-marker-type-funcall (type key &rest args)
  (when-let ((props (alist-get type edraw-svg-marker-types nil nil #'equal)))
    (when-let ((fun (plist-get props key)))
      (apply fun args))))

(defun edraw-svg-marker-create-element (marker prop-name referrer-element)
  (edraw-svg-marker-type-funcall (edraw-svg-marker-type marker) :creator
                                 prop-name referrer-element
                                 marker))

(defun edraw-svg-marker-from-element (element prop-name defrefs)
  "Create a marker descriptor from the attribute PROP-NAME of the ELEMENT."
  (let ((value (dom-attr element prop-name)))
    (when (and value
               (stringp value)
               (not (string= value "none"))
               (not (string= value "")))
      (let ((marker-type (edraw-svg-defref-url-to-prop-value value))
            (marker-element
             (edraw-svg-defref-def-element
              (edraw-svg-defrefs-get-defref-by-url defrefs value))))
        (when marker-type
          (edraw-svg-marker
           marker-type
           (when marker-element
             (edraw-svg-marker-type-funcall
              marker-type :get-props (dom-attributes marker-element)))))))))

(defun edraw-svg-marker-overhang (element prop-name defrefs)
  (when-let ((marker (edraw-svg-marker-from-element element prop-name defrefs)))
    (edraw-svg-marker-type-funcall (edraw-svg-marker-type marker) :overhang
                                   marker
                                   ;;@todo support group stroke-width
                                   (or (edraw-svg-attr-length element 'stroke-width) 1)
                                   )))


(defun edraw-svg-marker (marker-type props)
  "Create a marker descriptor.

MARKER-TYPE is a type name in `edraw-svg-marker-types'.

PROPS is an alist of properties defined by the MARKER-TYPE."
  (nconc (list 'marker marker-type) props))

(defun edraw-svg-marker-p (object)
  (eq (car-safe object) 'marker))

(defun edraw-svg-marker-type (marker)
  "Return marker type."
  (when (edraw-svg-marker-p marker)
    (cadr marker)))

(defun edraw-svg-marker-props (marker)
  "Return alist of marker property."
  (when (edraw-svg-marker-p marker)
    (cddr marker)))

(defun edraw-svg-marker-props-head (marker)
  (when (edraw-svg-marker-p marker)
    (cdr marker)))

(defun edraw-svg-marker-prop-str (marker key default)
  (edraw-svg-ensure-string-attr
   (alist-get key (edraw-svg-marker-props marker) default)))

(defun edraw-svg-marker-prop-number (marker key default)
  (let ((value (alist-get key (edraw-svg-marker-props marker))))
    (if (and (stringp value)
             (string-match-p "\\`-?\\([0-9]\\|\\.[0-9]\\)" value))
        (string-to-number value)
      default)))

(defun edraw-svg-set-marker-property (element prop-name marker defrefs)
  "Set the property PROP-NAME of the SVG ELEMENT to MARKER."
  ;; String to marker descriptor
  (when (stringp marker)
    (setq marker (edraw-svg-marker marker nil))) ;; Including "" or "none"

  ;; Remove reference to current marker
  (edraw-svg-defrefs-remove-ref-by-url
   defrefs
   (dom-attr element prop-name) ;;url(#...) or "none" or nil
   element)
  ;; Add reference to marker
  (let ((marker-element
         (edraw-svg-marker-create-element marker prop-name element)))
    (if marker-element
        (edraw-svg-set-attr-string element
                                   prop-name
                                   (edraw-svg-defrefs-add-ref
                                    defrefs marker-element element
                                    (edraw-svg-marker-type marker)))
      (edraw-dom-remove-attr element
                             prop-name))))

(defun edraw-svg-get-marker-property (element prop-name defrefs)
  "Return marker descriptor set in the property PROP-NAME of the SVG ELEMENT"
  ;; Return marker descriptor
  (edraw-svg-marker-from-element element prop-name defrefs)
  ;; Return only marker type (old behavior)
  ;;(edraw-svg-defref-url-to-prop-value (dom-attr element prop-name))
  )

(defun edraw-svg-update-marker-properties (element defrefs)
  (edraw-svg-update-marker-property element 'marker-start defrefs)
  (edraw-svg-update-marker-property element 'marker-mid defrefs)
  (edraw-svg-update-marker-property element 'marker-end defrefs))

(defun edraw-svg-update-marker-property (element prop-name defrefs)
  (when-let ((marker (edraw-svg-marker-from-element element prop-name defrefs)))
    (edraw-svg-set-marker-property element prop-name marker defrefs)))



;;;; SVG Shape Bounding Box

;; (Depends on edraw-math.el)

(defun edraw-svg-shape-aabb (element &optional matrix local-p)
  (let ((edraw-path-cmdlist-to-seglist--include-empty-p t)) ;;Enumerate zero-length segments
    (edraw-path-seglist-aabb
     (edraw-svg-element-to-seglist element matrix local-p))))

(defvar edraw-svg-text-contents-aabb--remove-last-descent nil)

(defun edraw-svg-text-contents-aabb (element)
  "Return the axis-aligned bounding box of the text ELEMENT.

This function does not consider the effect of the transform attribute."
  ;; https://www.w3.org/TR/SVG11/text.html#TextElement
  ;; @todo support inherit attribute from ancestor
  (let* ((x (or (dom-attr element 'x) ""))
         (y (or (dom-attr element 'y) ""))
         (separator ;;comma-wsp
          "\\(?:[ \t\n\f\r]+,?[ \t\n\f\r]*\\|,[ \t\n\f\r]*\\)")
         (xs
          (if (stringp x)
              (or (mapcar
                   (lambda (n) (edraw-svg-attr-length-to-number n element 'x))
                   (split-string x separator t))
                  (list 0))
            (list x)))
         (ys
          (if (stringp y)
              (or (mapcar
                   (lambda (n) (edraw-svg-attr-length-to-number n element 'y))
                   (split-string y separator t))
                  (list 0))
            (list y)))
         (anchor-x (car xs))
         (anchor-y (car ys))
         ;;@todo support dx, dy
         (text (edraw-svg-text-get-text element));;@todo analyze decendant nodes
         (lines (split-string text "\n"))
         (max-width (cl-loop for line in lines
                             maximize (string-width line)))
         (text-anchor (or (dom-attr element 'text-anchor) "start"))
         (font-size (or (edraw-svg-attr-length element 'font-size)
                        edraw-svg-attr-default-font-size)) ;;@todo default font size
         (font-ascent (/ (* font-size 80) 100)) ;;@todo default font ascent
         (writing-mode (edraw-svg-text-writing-mode element))
         (vertical-p (edraw-svg-text-vertical-writing-p element))
         (vertical-rl-p (eq writing-mode 'vertical-rl)))
    ;;@todo direction=rtl
    ;;@todo support style
    ;;@todo support baseline spec. (but librsvg does not support baseline spec https://gitlab.gnome.org/GNOME/librsvg/-/issues/414 )
    ;;@todo support list-of-coordinates x=, y=, dx=, dy= (librsvg does not support https://gitlab.gnome.org/GNOME/librsvg/-/issues/183 )
    ;;@todo support rotate (librsvg does not suppor ?)
    ;;@todo support textLength (librsvg does not support https://gitlab.gnome.org/GNOME/librsvg/-/issues/88 )

    (let* ((anchor-col (if vertical-p anchor-y anchor-x))
           (anchor-line (if vertical-p anchor-x anchor-y))
           (num-lines (length lines))
           (leading (or (edraw-svg-attr-length element 'data-edraw-text-leading)
                        font-size)) ;; NOTE: Can be negative
           (leading-total (if (= num-lines 0) 0 (* (1- num-lines) leading)))
           (leading-total-abs (abs leading-total))
           (leading-total-neg (- (min leading-total 0)))
           (text-w (* 0.5 font-size max-width))
           (text-h
            (if (= num-lines 0)
                0
              (max 0
                   (+ font-size
                      leading-total-abs
                      (if edraw-svg-text-contents-aabb--remove-last-descent
                          (- (- font-size font-ascent)) 0)))))
           (text-col (- anchor-col
                        (* text-w (pcase text-anchor
                                    ("middle" 0.5) ("end" 1) (_ 0)))))
           (text-line (if vertical-p
                          (if vertical-rl-p
                              (+ (- anchor-line text-h) (* 0.5 font-size)
                                 leading-total-neg)
                            ;; vertical-lr
                            (- anchor-line (* 0.5 font-size) leading-total-neg))
                        (- anchor-line font-ascent leading-total-neg))))
      (if vertical-p
          (edraw-rect-xywh text-line text-col text-h text-w)
        (edraw-rect-xywh text-col text-line text-w text-h)))))

(defun edraw-svg-text-writing-mode (element)
  ;;@todo support style attribute
  ;;@todo support inherit
  ;; https://www.w3.org/TR/css-writing-modes-3/#svg-writing-mode
  (pcase (dom-attr element 'writing-mode)
    ((or "horizontal-tb" "lr" "lr-tb" "rl" "rl-tb") 'horizontal-tb)
    ((or "vertical-rl" "tb-rl" "tb") 'vertical-rl)
    ("vertical-lr" 'vertical-lr)
    (_ 'horizontal-tb)))

(defun edraw-svg-text-vertical-writing-p (element)
  (memq (edraw-svg-text-writing-mode element) '(vertical-rl vertical-lr)))


;;;; SVG Shape Translation

;;
;;

(defun edraw-svg-element-translate (element xy)
  (let ((transform (edraw-svg-element-transform-get element)))
    (pcase (dom-tag element)
      ((or 'path 'rect 'ellipse 'circle 'text 'image)
       (if transform ;;(not (edraw-matrix-translation-only-p transform)) ?
           (progn
             (edraw-matrix-translate-add transform (car xy) (cdr xy))
             (edraw-svg-element-transform-set element transform))
         (edraw-svg-shape-translate-contents element xy)))
      ('g
       (if transform
           (progn
             (edraw-matrix-translate-add transform (car xy) (cdr xy))
             (edraw-svg-element-transform-set element transform))
         (edraw-svg-element-transform-set
          element
          (edraw-matrix-translate (car xy) (cdr xy) 0)))))))

(defun edraw-svg-shape-translate-contents (element xy)
  (pcase (dom-tag element)
    ('rect (edraw-svg-rect-translate-contents element xy))
    ('ellipse (edraw-svg-ellipse-translate-contents element xy))
    ('circle (edraw-svg-circle-translate-contents element xy))
    ('text (edraw-svg-text-translate-contents element xy))
    ('image (edraw-svg-image-translate-contents element xy))
    ('path (edraw-svg-path-translate-contents element xy))
    ('g (edraw-svg-group-translate-contents element xy)))
  element)

(defun edraw-svg-rect-translate-contents (element xy)
  (edraw-svg-set-attr-number element 'x
                             (+ (or (edraw-svg-attr-coord element 'x) 0)
                                (car xy)))
  (edraw-svg-set-attr-number element 'y
                             (+ (or (edraw-svg-attr-coord element 'y) 0)
                                (cdr xy))))

(defun edraw-svg-ellipse-translate-contents (element xy)
  (edraw-svg-set-attr-number element 'cx
                             (+ (or (edraw-svg-attr-coord element 'cx) 0)
                                (car xy)))
  (edraw-svg-set-attr-number element 'cy
                             (+ (or (edraw-svg-attr-coord element 'cy) 0)
                                (cdr xy))))

(defun edraw-svg-circle-translate-contents (element xy)
  (edraw-svg-set-attr-number element 'cx
                             (+ (or (edraw-svg-attr-coord element 'cx) 0)
                                (car xy)))
  (edraw-svg-set-attr-number element 'cy
                             (+ (or (edraw-svg-attr-coord element 'cy) 0)
                                (cdr xy))))

(defun edraw-svg-text-translate-contents (element xy)
  ;;@todo support list-of-coordinates
  (edraw-svg-text-set-x element (+ (or (edraw-svg-attr-coord element 'x) 0)
                                   (car xy)))
  (edraw-svg-set-attr-number element 'y
                             (+ (or (edraw-svg-attr-coord element 'y) 0)
                                (cdr xy))))

(defun edraw-svg-image-translate-contents (element xy)
  (edraw-svg-set-attr-number element 'x
                             (+ (or (edraw-svg-attr-coord element 'x) 0)
                                (car xy)))
  (edraw-svg-set-attr-number element 'y
                             (+ (or (edraw-svg-attr-coord element 'y) 0)
                                (cdr xy))))

(defun edraw-svg-path-translate-contents (element xy)
  (when-let ((d (dom-attr element 'd)))
    (edraw-svg-set-attr-string element 'd (edraw-path-d-translate d xy))))

(defun edraw-svg-group-translate-contents (element xy)
  ;;@todo Should I change the transform attribute instead?
  ;; Transformation of children is inefficient and causes numerical error.
  ;; But easy to ungroup.
  (dolist (child (dom-children element))
    (when (edraw-dom-element-p child)
      (edraw-svg-element-translate child xy))))



;;;; SVG Shapes to edraw-path-cmdlist

(defconst edraw-bezier-circle-point 0.552284749831) ;;https://stackoverflow.com/questions/1734745/how-to-create-circle-with-b%C3%A9zier-curves

;; (Depends on edraw-path.el)

(defun edraw-svg-element-to-path-cmdlist (element &optional matrix transformed)
  (edraw-svg-element-contents-to-path-cmdlist
   element
   (when transformed
     (edraw-svg-element-transform-get element matrix))))

(defun edraw-svg-element-contents-to-path-cmdlist (element &optional matrix)
  (when (edraw-dom-element-p element)
    (pcase (dom-tag element)
      ((or 'path 'rect 'ellipse 'circle 'text 'image)
       (let ((cmdlist (edraw-svg-shape-contents-to-path-cmdlist element)))
         (unless (edraw-matrix-identity-p matrix)
           (edraw-path-cmdlist-transform cmdlist matrix))
         cmdlist))
      ('g
       (edraw-svg-group-contents-to-path-cmdlist element matrix)))))

(defun edraw-svg-shape-contents-to-path-cmdlist (element)
  (when (edraw-dom-element-p element)
    (pcase (dom-tag element)
      ('path (edraw-svg-path-contents-to-path-cmdlist element))
      ('rect (edraw-svg-rect-contents-to-path-cmdlist element))
      ('ellipse (edraw-svg-ellipse-contents-to-path-cmdlist element))
      ('circle (edraw-svg-circle-contents-to-path-cmdlist element))
      ('text (edraw-svg-text-contents-to-path-cmdlist element))
      ('image (edraw-svg-image-contents-to-path-cmdlist element)))))

(defun edraw-svg-path-contents-to-path-cmdlist (element)
  (let ((fill (dom-attr element 'fill))
        (d (dom-attr element 'd)))
    (when d
      (let ((cmdlist (edraw-path-cmdlist-from-d d))
            (needs-closed-p (not (equal fill "none"))))
        (when needs-closed-p
          (edraw-path-cmdlist-close-path cmdlist t))
        cmdlist))))

(defun edraw-svg-rect-contents-to-path-cmdlist (element)
  ;; https://www.w3.org/TR/SVG11/shapes.html#RectElement
  (let* ((x0 (or (edraw-svg-attr-coord element 'x) 0))
         (y0 (or (edraw-svg-attr-coord element 'y) 0))
         (width (or (edraw-svg-attr-coord element 'width) 0))
         (height (or (edraw-svg-attr-coord element 'height) 0))
         (x3 (+ x0 width))
         (y3 (+ y0 height))
         (rx-spec (edraw-svg-attr-length element 'rx))
         (ry-spec (edraw-svg-attr-length element 'ry))
         (rx (edraw-clamp (if (numberp rx-spec) rx-spec
                            (if (numberp ry-spec) ry-spec 0))
                          0 (/ width 2.0)))
         (ry (edraw-clamp (if (numberp ry-spec) ry-spec
                            (if (numberp rx-spec) rx-spec 0))
                          0 (/ height 2.0)))
         (c edraw-bezier-circle-point)
         (crx (* c rx))
         (cry (* c ry))
         (x1 (+ x0 rx))
         (y1 (+ y0 ry))
         (x2 (max x1 (- x3 rx)))
         (y2 (max y1 (- y3 ry)))
         (cmdlist (edraw-path-cmdlist)))

    (cond
     ((or (= rx 0) (= ry 0))
      (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd
                                             'M (cons x0 y0)))
      (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd
                                             'L (cons x3 y0)))
      (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd
                                             'L (cons x3 y3)))
      (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd
                                             'L (cons x0 y3)))
      (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd
                                             'L (cons x0 y0)))
      (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd 'Z)))

     (t
      (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd
                                             'M (cons x1 y0)))
      (unless (= x1 x2)
        (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd
                                               'L (cons x2 y0))))
      (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd
                                             'C
                                             (cons (+ x2 crx) y0)
                                             (cons x3 (- y1 cry))
                                             (cons x3 y1)))
      (unless (= y1 y2)
        (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd
                                               'L (cons x3 y2))))
      (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd
                                             'C
                                             (cons x3 (+ y2 cry))
                                             (cons (+ x2 crx) y3)
                                             (cons x2 y3)))
      (unless (= x1 x2)
        (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd
                                               'L (cons x1 y3))))
      (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd
                                             'C
                                             (cons (- x1 crx) y3)
                                             (cons x0 (+ y2 cry))
                                             (cons x0 y2)))
      (unless (= y1 y2)
        (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd
                                               'L (cons x0 y1))))
      (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd
                                             'C
                                             (cons x0 (- y1 cry))
                                             (cons (- x1 crx) y0)
                                             (cons x1 y0)))
      (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd 'Z))))
    cmdlist))

(defun edraw-svg-ellipse-contents-to-path-cmdlist (element)
  ;; https://www.w3.org/TR/SVG11/shapes.html#EllipseElement
  (let* ((cx (or (edraw-svg-attr-coord element 'cx) 0))
         (cy (or (edraw-svg-attr-coord element 'cy) 0))
         (rx (or (edraw-svg-attr-coord element 'rx) 0))
         (ry (or (edraw-svg-attr-coord element 'ry) 0))
         (left   (- cx rx))
         (top    (- cy ry))
         (right  (+ cx rx))
         (bottom (+ cy ry))
         (c edraw-bezier-circle-point)
         (crx (* c rx))
         (cry (* c ry))
         (cmdlist (edraw-path-cmdlist)))
    (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd
                                           'M (cons right cy)))
    (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd
                                           'C
                                           (cons right (+ cy cry))
                                           (cons (+ cx crx) bottom)
                                           (cons cx bottom)))
    (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd
                                           'C
                                           (cons (- cx crx) bottom)
                                           (cons left (+ cy cry))
                                           (cons left cy)))
    (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd
                                           'C
                                           (cons left (- cy cry))
                                           (cons (- cx crx) top)
                                           (cons cx top)))
    (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd
                                           'C
                                           (cons (+ cx crx) top)
                                           (cons right (- cy cry))
                                           (cons right cy)))
    (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd 'Z))
    cmdlist))

(defun edraw-svg-circle-contents-to-path-cmdlist (element)
  ;; https://www.w3.org/TR/SVG11/shapes.html#CircleElement
  (let* ((cx (or (edraw-svg-attr-coord element 'cx) 0))
         (cy (or (edraw-svg-attr-coord element 'cy) 0))
         (r (or (edraw-svg-attr-coord element 'r) 0))
         (left   (- cx r))
         (top    (- cy r))
         (right  (+ cx r))
         (bottom (+ cy r))
         (c edraw-bezier-circle-point)
         (cr (* c r))
         (cmdlist (edraw-path-cmdlist)))
    (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd
                                           'M (cons right cy)))
    (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd
                                           'C
                                           (cons right (+ cy cr))
                                           (cons (+ cx cr) bottom)
                                           (cons cx bottom)))
    (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd
                                           'C
                                           (cons (- cx cr) bottom)
                                           (cons left (+ cy cr))
                                           (cons left cy)))
    (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd
                                           'C
                                           (cons left (- cy cr))
                                           (cons (- cx cr) top)
                                           (cons cx top)))
    (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd
                                           'C
                                           (cons (+ cx cr) top)
                                           (cons right (- cy cr))
                                           (cons right cy)))
    (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd 'Z))
    cmdlist))

(defun edraw-svg-text-contents-to-path-cmdlist (element)
  ;; Exact calculation is difficult, so use AABB instead
  (let* ((rect (edraw-svg-text-contents-aabb element))
         (left   (caar rect))
         (top    (cdar rect))
         (right  (cadr rect))
         (bottom (cddr rect))
         (cmdlist (edraw-path-cmdlist)))
    (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd 'M (cons left top)))
    (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd 'L (cons right top)))
    (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd 'L (cons right bottom)))
    (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd 'L (cons left bottom)))
    (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd 'L (cons left top)))
    (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd 'Z))
    cmdlist))

(defun edraw-svg-image-contents-to-path-cmdlist (element)
  ;; https://www.w3.org/TR/SVG11/struct.html#ImageElement
  (let* ((left   (or (edraw-svg-attr-coord element 'x) 0))
         (top    (or (edraw-svg-attr-coord element 'y) 0))
         (width  (or (edraw-svg-attr-coord element 'width) 0))
         (height (or (edraw-svg-attr-coord element 'height) 0))
         (right  (+ left width))
         (bottom (+ top height))
         (cmdlist (edraw-path-cmdlist)))
    ;;@todo support overflow? clip?
    (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd 'M (cons left top)))
    (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd 'L (cons right top)))
    (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd 'L (cons right bottom)))
    (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd 'L (cons left bottom)))
    (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd 'L (cons left top)))
    (edraw-path-cmdlist-push-back cmdlist (edraw-path-cmd 'Z))
    cmdlist))

(defun edraw-svg-group-contents-to-path-cmdlist (element &optional matrix)
  (let (cmdlist)
    (dolist (child (dom-children element))
      (when (edraw-dom-element-p child)
        (let ((child-cmdlist (edraw-svg-element-to-path-cmdlist element matrix)))
          (when (and child-cmdlist
                     (not (edraw-path-cmdlist-empty-p child-cmdlist)))
            (when cmdlist
              (edraw-path-cmdlist-insert-cmdlist-front child-cmdlist cmdlist))
            (setq cmdlist child-cmdlist)))))
    cmdlist))



;;;; SVG Shapes to Segment List

;; (Depends on edraw-path.el)

(defun edraw-svg-element-to-seglist (element &optional matrix local-p)
  (edraw-svg-element-contents-to-seglist
   element
   (if local-p
       matrix
     ;; Apply the transform= attribute if not local-p
     (edraw-svg-element-transform-get element matrix))))

(defun edraw-svg-element-contents-to-seglist (element &optional matrix)
  (when (edraw-dom-element-p element)
    (pcase (dom-tag element)
      ((or 'path 'rect 'ellipse 'circle 'text 'image)
       (let ((segments (edraw-svg-shape-contents-to-seglist element)))
         (unless (edraw-matrix-identity-p matrix)
           (edraw-path-seglist-transform segments matrix))
         segments))
      ('g
       (edraw-svg-group-contents-to-seglist element matrix)))))

(defun edraw-svg-shape-contents-to-seglist (element)
  (when (edraw-dom-element-p element)
    (pcase (dom-tag element)
      ('path (edraw-svg-path-contents-to-seglist element))
      ('rect (edraw-svg-rect-contents-to-seglist element))
      ('ellipse (edraw-svg-ellipse-contents-to-seglist element))
      ('circle (edraw-svg-circle-contents-to-seglist element))
      ('text (edraw-svg-text-contents-to-seglist element))
      ('image (edraw-svg-image-contents-to-seglist element)))))

(defun edraw-svg-path-contents-to-seglist (element)
  (let ((fill (dom-attr element 'fill))
        (d (dom-attr element 'd)))
    (when d
      (edraw-path-cmdlist-to-seglist
       (edraw-path-cmdlist-from-d d)
       (not (equal fill "none"))))))

(defun edraw-svg-rect-contents-to-seglist (element)
  ;; https://www.w3.org/TR/SVG11/shapes.html#RectElement
  (let* ((x0 (or (edraw-svg-attr-coord element 'x) 0))
         (y0 (or (edraw-svg-attr-coord element 'y) 0))
         (width (or (edraw-svg-attr-coord element 'width) 0))
         (height (or (edraw-svg-attr-coord element 'height) 0))
         (x3 (+ x0 width))
         (y3 (+ y0 height))
         (rx-spec (edraw-svg-attr-length element 'rx))
         (ry-spec (edraw-svg-attr-length element 'ry))
         (rx (edraw-clamp (if (numberp rx-spec) rx-spec
                            (if (numberp ry-spec) ry-spec 0))
                          0 (/ width 2.0)))
         (ry (edraw-clamp (if (numberp ry-spec) ry-spec
                            (if (numberp rx-spec) rx-spec 0))
                          0 (/ height 2.0)))
         (c edraw-bezier-circle-point)
         (crx (* c rx))
         (cry (* c ry))
         (x1 (+ x0 rx))
         (y1 (+ y0 ry))
         (x2 (max x1 (- x3 rx)))
         (y2 (max y1 (- y3 ry)))
         (segments
          (cond
           ((or (= rx 0) (= ry 0))
            (list (vector (cons x0 y0) (cons x3 y0))
                  (vector (cons x3 y0) (cons x3 y3))
                  (vector (cons x3 y3) (cons x0 y3))
                  (vector (cons x0 y3) (cons x0 y0))))
           (t
            (delq
             nil
             (list
              (unless (= x1 x2)
                (vector (cons x1 y0) (cons x2 y0)))
              (vector (cons x2 y0) (cons (+ x2 crx) y0)
                      (cons x3 (- y1 cry)) (cons x3 y1))
              (unless (= y1 y2)
                (vector (cons x3 y1) (cons x3 y2)))
              (vector (cons x3 y2) (cons x3 (+ y2 cry))
                      (cons (+ x2 crx) y3) (cons x2 y3))
              (unless (= x1 x2)
                (vector (cons x2 y3) (cons x1 y3)))
              (vector (cons x1 y3) (cons (- x1 crx) y3)
                      (cons x0 (+ y2 cry)) (cons x0 y2))
              (unless (= y1 y2)
                (vector (cons x0 y2) (cons x0 y1)))

              (vector (cons x0 y1) (cons x0 (- y1 cry))
                      (cons (- x1 crx) y0) (cons x1 y0))))))))
    segments))

(defun edraw-svg-ellipse-contents-to-seglist (element)
  ;; https://www.w3.org/TR/SVG11/shapes.html#EllipseElement
  (let* ((cx (or (edraw-svg-attr-coord element 'cx) 0))
         (cy (or (edraw-svg-attr-coord element 'cy) 0))
         (rx (or (edraw-svg-attr-coord element 'rx) 0))
         (ry (or (edraw-svg-attr-coord element 'ry) 0))
         (left   (- cx rx))
         (top    (- cy ry))
         (right  (+ cx rx))
         (bottom (+ cy ry))
         (c edraw-bezier-circle-point)
         (crx (* c rx))
         (cry (* c ry))
         (segments
          (list
           (vector (cons right cy) (cons right (+ cy cry))
                   (cons (+ cx crx) bottom) (cons cx bottom))
           (vector (cons cx bottom) (cons (- cx crx) bottom)
                   (cons left (+ cy cry)) (cons left cy))
           (vector (cons left cy) (cons left (- cy cry))
                   (cons (- cx crx) top) (cons cx top))
           (vector (cons cx top) (cons (+ cx crx) top)
                   (cons right (- cy cry)) (cons right cy)))))
    segments))

(defun edraw-svg-circle-contents-to-seglist (element)
  ;; https://www.w3.org/TR/SVG11/shapes.html#CircleElement
  (let* ((cx (or (edraw-svg-attr-coord element 'cx) 0))
         (cy (or (edraw-svg-attr-coord element 'cy) 0))
         (r (or (edraw-svg-attr-coord element 'r) 0))
         (left   (- cx r))
         (top    (- cy r))
         (right  (+ cx r))
         (bottom (+ cy r))
         (c edraw-bezier-circle-point)
         (cr (* c r))
         (segments
          (list
           (vector (cons right cy) (cons right (+ cy cr))
                   (cons (+ cx cr) bottom) (cons cx bottom))
           (vector (cons cx bottom) (cons (- cx cr) bottom)
                   (cons left (+ cy cr)) (cons left cy))
           (vector (cons left cy) (cons left (- cy cr))
                   (cons (- cx cr) top) (cons cx top))
           (vector (cons cx top) (cons (+ cx cr) top)
                   (cons right (- cy cr)) (cons right cy)))))
    segments))

(defun edraw-svg-text-contents-to-seglist (element)
  ;; Exact calculation is difficult, so use AABB instead
  (let* ((rect (edraw-svg-text-contents-aabb element))
         (left   (caar rect))
         (top    (cdar rect))
         (right  (cadr rect))
         (bottom (cddr rect))
         (segments (list (vector (cons left  top   ) (cons right top   ))
                         (vector (cons right top   ) (cons right bottom))
                         (vector (cons right bottom) (cons left  bottom))
                         (vector (cons left  bottom) (cons left  top)))))
    segments))

(defun edraw-svg-image-contents-to-seglist (element)
  ;; https://www.w3.org/TR/SVG11/struct.html#ImageElement
  (let* ((left   (or (edraw-svg-attr-coord element 'x) 0))
         (top    (or (edraw-svg-attr-coord element 'y) 0))
         (width  (or (edraw-svg-attr-coord element 'width) 0))
         (height (or (edraw-svg-attr-coord element 'height) 0))
         (right  (+ left width))
         (bottom (+ top height))
         ;;@todo support overflow? clip?
         (segments (list (vector (cons left  top   ) (cons right top   ))
                         (vector (cons right top   ) (cons right bottom))
                         (vector (cons right bottom) (cons left  bottom))
                         (vector (cons left  bottom) (cons left  top)))))
    segments))

(defun edraw-svg-group-contents-to-seglist (element &optional matrix)
  (let (segments)
    (dolist (child (dom-children element))
      (when (edraw-dom-element-p child)
        (let ((child-segments (edraw-svg-element-to-seglist child matrix)))
          (setq segments (nconc segments child-segments)))))
    segments))



;;;; Point in SVG Shapes Test

;; (Depends on edraw-path.el)

(defconst edraw-pick-point-radius 2)

(defun edraw-svg-element-contains-point-p (element xy)
  (let ((transform (edraw-svg-element-transform-get element)))
    (unless (edraw-matrix-identity-p transform)
      (when-let ((inv (edraw-matrix-inverse transform)))
        (setq xy (edraw-matrix-mul-mat-xy inv xy)))))

  (when (edraw-dom-element-p element)
    (pcase (dom-tag element)
      ((or 'path 'rect 'ellipse 'circle 'text 'image)
       (edraw-svg-shape-contains-point-p element xy))
      ('g
       (edraw-svg-group-contains-point-p element xy)))))

(defun edraw-svg-shape-contains-point-p (element xy)
  (let* ((fill (dom-attr element 'fill))
         (fill-p (not (equal fill "none"))) ;;default black
         (fill-rule (dom-attr element 'fill-rule))
         (stroke (dom-attr element 'stroke))
         (stroke-p (and stroke ;;default none
                        (not (equal stroke ""))
                        (not (equal stroke "none"))))
         (stroke-width (if stroke-p
                           (or (edraw-svg-attr-length element 'stroke-width) 1)
                         0))
         (stroke-square-r (/ stroke-width (* 2 (sqrt 2))))
         (segments (edraw-svg-shape-contents-to-seglist element)
                   ;;or (edraw-svg-element-contents-to-seglist element)
                   )
         (text-bb-p (eq (dom-tag element) 'text)))

    (when segments
      (or (and stroke-p
               (not text-bb-p)
               (edraw-path-seglist-intersects-rect-p
                segments
                (edraw-square xy (+ edraw-pick-point-radius stroke-square-r))))
          (and (or fill-p
                   text-bb-p)
               (edraw-path-seglist-contains-point-p
                segments
                xy
                (equal fill-rule "evenodd")))))))

(defun edraw-svg-group-contains-point-p (element xy)
  (seq-some
   (lambda (child)
     (and (edraw-dom-element-p child)
          (edraw-svg-element-contains-point-p child xy)))
   (dom-children element)))


;;;; SVG Shapes and Rectangle Intersection Test

(defun edraw-svg-element-intersects-rect-p (element rect &optional matrix)
  (when (edraw-dom-element-p element)
    (pcase (dom-tag element)
      ((or 'path 'rect 'ellipse 'circle 'text 'image)
       (edraw-svg-shape-intersects-rect-p element rect matrix))
      ('g
       (edraw-svg-group-intersects-rect-p element rect matrix)))))

(defun edraw-svg-shape-intersects-rect-p (element rect &optional matrix)
  (when (and element
             rect
             (not (edraw-rect-empty-p rect)))
    (let* ((fill (dom-attr element 'fill))
           (fill-p (not (equal fill "none"))) ;;default black
           (fill-rule (dom-attr element 'fill-rule))
           (stroke (dom-attr element 'stroke))
           (stroke-width (if (and stroke
                                  (not (equal stroke ""))
                                  (not (equal stroke "none")))
                             (or (edraw-svg-attr-length element 'stroke-width) 1)
                           0))
           (stroke-r (/ stroke-width (* 2 (sqrt 2))))
           (enlarged-rect (edraw-rect
                           (- (caar rect) stroke-r)
                           (- (cdar rect) stroke-r)
                           (+ (cadr rect) stroke-r)
                           (+ (cddr rect) stroke-r)))
           (segments (edraw-svg-element-to-seglist element matrix))
           (text-aabb-p (eq (dom-tag element) 'text)))
      (when segments
        (or (edraw-path-seglist-intersects-rect-p segments enlarged-rect)
            ;; Case where rect is completely inside the shape
            (and (or fill-p
                     text-aabb-p)
                 (edraw-path-seglist-contains-point-p
                  segments
                  (edraw-xy (caar enlarged-rect) (cdar enlarged-rect))
                  (equal fill-rule "evenodd"))))))))

(defun edraw-svg-group-intersects-rect-p (element rect &optional matrix)
  (let ((sub-matrix (edraw-svg-element-transform-get element matrix)))
    (seq-some
     (lambda (child)
       (and (edraw-dom-element-p child)
            (edraw-svg-element-intersects-rect-p child rect sub-matrix)))
     (dom-children element))))

;;;; Intersection Coordinates of SVG Shape and Line

(defun edraw-svg-element-and-line-intersections (element pt dir &optional matrix local-p)
  (setq dir (edraw-xy-normalize dir))
  (let* ((segments (edraw-svg-element-to-seglist element matrix local-p))
         (invdir (edraw-xy (edraw-x dir) (- (edraw-y dir))))
         (invdir90 (edraw-xy-rot90 invdir))
         (invpt-y (+ (* (edraw-x pt) (edraw-y invdir))
                     (* (edraw-y pt) (edraw-y invdir90))))
         (invpt-y-dir90 (edraw-xy-nmul invpt-y (edraw-xy-rot90 dir))))
    (edraw-path-seglist-transform-mat22
     segments
     (cons invdir invdir90))

    (mapcar
     (lambda (x) (edraw-xy-add (edraw-xy-nmul x dir) invpt-y-dir90))
     (sort
      (edraw-path-seglist-and-horizontal-line-intersections
       segments invpt-y)
      #'<))))
;; (edraw-svg-element-and-line-intersections (dom-node 'rect '((x . "100") (y . "50") (width . 300) (height . 200))) (edraw-xy 100 100) (edraw-xy 10 10))

;;;; SVG Shape Thumbnail

(defun edraw-svg-shape-thumbnail-cover (svg svg-width svg-height spec
                                            pl pt cw ch id)
  (let ((bl 0)
        (bt 0)
        (bw svg-width)
        (bh svg-height)
        (attrs '((fill . "#ffffff"))))
    ;; '(content (symbol . value)...)
    ;; '(full (symbol . value)...)
    (pcase spec
      (`(content . ,alist)
       (setq bl pl bt pt bw cw bh ch attrs alist))
      (`(full . ,alist)
       (setq attrs alist)))
    (edraw-svg-rect bl bt bw bh
                    :parent svg
                    :id id
                    :attributes attrs)))

(defun edraw-svg-shape-thumbnail (shape svg-width svg-height
                                        &optional
                                        padding background foreground
                                        svg-max-width svg-max-height)
  (let ((aabb (edraw-svg-shape-aabb shape)))
    (unless (edraw-rect-empty-p aabb)
      (setq padding
            (pcase padding
              (`(,pl ,pt ,pr ,pb) (list pl pt pr pb))
              (`(,plr ,ptb) (list plr ptb plr ptb))
              ('nil (list 0 0 0 0))
              (n (list n n n n))))
      (unless (seq-every-p #'numberp padding)
        (error "Wrong padding spec %s" padding))

      (let* (;;bounding box
             (bl (edraw-rect-left aabb))
             (bt (edraw-rect-top aabb))
             (bw (edraw-rect-width aabb))
             (bh (edraw-rect-height aabb))
             ;;padding
             (pl (nth 0 padding))
             (pt (nth 1 padding))
             (pr (nth 2 padding))
             (pb (nth 3 padding))
             ;;content (without padding)
             (cw (max 0
                      (- svg-width pl pr)
                      (if svg-max-width (min (- svg-max-width pl pr) bw) 0)))
             (ch (max 0
                      (- svg-height pt pb)
                      (if svg-max-height (min (- svg-max-height pt pb) bh) 0)))
             ;;scale
             (sx (/ (float cw) bw))
             (sy (/ (float ch) bh))
             (scale (min sx sy 1.0)))

        (setq svg-width (+ pl cw pr)
              svg-height (+ pt ch pb))

        (let ((svg (edraw-svg-create svg-width svg-height)))
          (when background
            (edraw-svg-shape-thumbnail-cover
             svg svg-width svg-height
             background pl pt cw ch "background"))

          ;; Body
          (edraw-svg-group :parent svg
                           :id "body"
                           :transform
                           (concat
                            (format "translate(%s %s)"
                                    (+ pl (/ (- cw (* bw scale)) 2))
                                    (+ pt (/ (- ch (* bh scale)) 2)))
                            " "
                            (format "scale(%s)" scale)
                            " "
                            (format "translate(%s %s)" (- bl) (- bt)))
                           ;; Children
                           shape)

          (when foreground
            (edraw-svg-shape-thumbnail-cover
             svg svg-width svg-height
             foreground pl pt cw ch "foreground"))

          svg)))))



(provide 'edraw-dom-svg)
;;; edraw-dom-svg.el ends here
