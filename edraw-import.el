;;; edraw-import.el --- Convert to Edraw SVG  -*- lexical-binding: t; -*-

;; Copyright (C) 2024  AKIYAMA Kouhei

;; Author: AKIYAMA Kouhei <misohena@gmail.com>
;; Keywords: 

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

(require 'edraw-dom-svg)

;;;; Common

;;;###autoload
(defun edraw-convert-buffer-to-edraw-svg-xml (buffer output)
  (interactive
   (list (current-buffer) (current-buffer)))

  ;; @todo Select the importer that matches the buffer mode or file extension.

  (when (and
         (called-interactively-p 'interactive)
         (not (y-or-n-p
               (edraw-msg "If you import diagrams generated with other software into Edraw, they may not be displayed correctly or the editing operation may become unstable. The original information is lost in the converted data. Do you want to convert to a format for Edraw?"))))
    (keyboard-quit))

  (when-let ((svg (edraw-import-from-svg-buffer buffer)))
    (with-current-buffer output
      (erase-buffer)
      (edraw-svg-print svg nil nil))))

(defun edraw-import-error (string &rest args)
  (apply #'error string args))

(defvar edraw-import-warning-messages nil)
(defvar edraw-import-warning-count 0)
(defvar edraw-import-warning-blocks 0)

(defun edraw-import-warn (string &rest args)
  (let ((msg (apply #'format string args)))
    (unless (member msg edraw-import-warning-messages)
      (push msg edraw-import-warning-messages)
      (cl-incf edraw-import-warning-count)
      (apply #'warn string args))))

(defmacro edraw-import-warning-block (&rest body)
  `(progn
     (when (= edraw-import-warning-blocks 0)
       (setq edraw-import-warning-count 0
             edraw-import-warning-messages nil))
     (unwind-protect
         (let ((edraw-import-warning-blocks (1+ edraw-import-warning-blocks)))
           ,@body)
       (when (= edraw-import-warning-blocks 0)
         (when (> edraw-import-warning-count 0)
           (warn (edraw-msg "edraw-import: %s warnings raised")
                 edraw-import-warning-count))
         (setq edraw-import-warning-count 0
               edraw-import-warning-messages nil)))))

;;;; Import From General SVG

(defconst edraw-import-svg-level 'strict) ;; 'loose
(defconst edraw-import-svg-keep-unsupported-defs t)

(defvar edraw-import-svg-in-defs nil)

;;;###autoload
(defun edraw-import-from-svg-buffer (buffer)
  (edraw-import-warning-block
   (edraw-import-from-svg-dom
    (with-temp-buffer
      (insert-buffer-substring-no-properties buffer)
      (edraw-xml-escape-ns-buffer)
      (libxml-parse-xml-region (point-min) (point-max))))))

;;;###autoload
(defun edraw-import-from-svg-dom (dom)
  (edraw-import-warning-block
   (let* ((svg-comments (edraw-dom-split-top-nodes dom))
          (svg (car svg-comments)))

     (unless (eq (edraw-dom-tag svg) 'svg)
       (edraw-import-error (edraw-msg "Not SVG data")))

     (if (edraw-dom-get-by-id svg "edraw-body")
         (progn
           (edraw-import-warn (edraw-msg "Already an SVG for Edraw"))
           dom)

       ;; `edraw-svg-attr-length' requires ability to get parent from
       ;; child element only.
       (edraw-dom-update-parent-links svg)

       (let* ((edraw-dom-inhibit-parent-links t) ;; Do not create parent links(?)
              (context
               (list
                ;; plist
                (list
                 :namespaces
                 (edraw-xml-collect-ns-decls svg))))
              (converted (edraw-import-svg-convert-children svg context))
              (definitions (plist-get (car context) :definitions)))
         (edraw-dom-element
          'svg
          :attributes
          (edraw-import-svg-convert-element-attributes svg context)
          :xmlns "http://www.w3.org/2000/svg"
          :xmlns:xlink "http://www.w3.org/1999/xlink"
          ;; Children
          (when definitions
            (edraw-dom-element 'g
                               :id "edraw-imported-definitions"
                               :children definitions))
          (edraw-dom-element 'g
                             :id "edraw-body"
                             :children converted)))))))

;;;;; Convert Children

(defun edraw-import-svg-convert-children (parent context)
  (let (new-children)
    (dolist (node (dom-children parent))
      (if (edraw-dom-element-p node)
          (if-let ((new-node (edraw-import-svg-convert-element node context)))
              (if (and (consp new-node)
                       (consp (car new-node)))
                  ;; List of node
                  (dolist (node new-node)
                    (push node new-children))
                ;; Single node (element or text)
                (push new-node new-children))
            ;; Discard element
            nil)
        (push node new-children)))
    (nreverse new-children)))

;;;;; Resolve XML Namespace

(defun edraw-import-svg-normalize-name (name-symbol context)
  "Normalize the NAME of tags and attributes.

SVG names strip the namespace prefix. XLink names begin with
xlink:. In other cases, the namespace URL is appended to the name
in parentheses.

The result value might look like this:
 SVG      :(rect . svg)
 XLink    :(xlink:href . xlink)
 XML      :(xml:space . xml)
 Otherwise:(version\\(http://www.inkscape.org/namespaces/inkscape\\) . unknown)"
  (let* ((ns-name (edraw-xml-unescape-ns-name name-symbol))
         (ns-prefix (car ns-name))
         (name (cdr ns-name))
         (ns-url (alist-get ns-prefix (plist-get (car context) :namespaces)
                            nil nil #'equal)))
    (unless (eq ns-prefix 'xmlns)
      (pcase ns-url
        ('nil (cond
               ;; No xmlns declaration for default. SVG?
               ((null ns-prefix)
                (edraw-import-warn "No xmlns declaration for default")
                (cons name 'svg))
               ;; For eample, xml:space, xml:lang
               ((equal ns-prefix "xml")
                (cons (intern (format "%s:%s" ns-prefix name)) 'xml))
               ;; No xmlns declaration for NS-PREFIX
               (t
                (edraw-import-warn "No xmlns declaration for `%s'" ns-prefix)
                (cons (intern (format "%s:%s" ns-prefix name)) 'unknown))))
        ("http://www.w3.org/2000/svg"
         (cons name 'svg))
        ("http://www.w3.org/1999/xlink"
         (cons (intern (format "xlink:%s" name)) 'xlink))
        (_
         ;; Unknown namespace URL
         (cons (intern (format "%s(%s)" name ns-url)) 'unknown))))))

;;;;; Convert Element

(defvar edraw-import-svg-convert-element-alist
  '((defs . edraw-import-svg-convert-definition)
    (g . edraw-import-svg-convert-group)
    (rect . edraw-import-svg-convert-shape)
    (ellipse . edraw-import-svg-convert-shape)
    (path . edraw-import-svg-convert-shape)
    (image . edraw-import-svg-convert-shape)
    (circle . edraw-import-svg-convert-circle)
    (line . edraw-import-svg-convert-line)
    (polyline . edraw-import-svg-convert-poly-shape)
    (polygon . edraw-import-svg-convert-poly-shape)
    (text . edraw-import-svg-convert-text)
    (tspan . edraw-import-svg-convert-tspan)
    (comment . edraw-import-svg-convert-comment)
    (a . edraw-import-svg-convert-a)
    ;; Not supported:
    ;; animate
    ;; animateMotion
    ;; animateTransform
    ;; clipPath
    ;; desc
    ;; fe*
    ;; filter
    ;; foreignObject
    ;; linearGradient
    ;; marker
    ;; mask
    ;; metadata
    ;; mpath
    ;; pattern
    ;; radialGradient
    ;; script
    ;; set
    ;; stop
    ;; style
    ;; svg
    ;; switch
    ;; symbol
    ;; textPath
    ;; use
    ;; view
    ))

(defun edraw-import-svg-convert-element (elem context)
  ;; Update namespace alist and normalize tag name
  (cl-letf* (((plist-get (car context) :namespaces)
              (nconc
               (edraw-xml-collect-ns-decls elem)
               (plist-get (car context) :namespaces)))
             (tag-ns (edraw-import-svg-normalize-name (edraw-dom-tag elem)
                                                      context))
             (tag (car tag-ns))
             (ns (cdr tag-ns)))
    (unless tag-ns
      (error "Unexpected xmlns decl in tag name"))
    (if-let ((fun (alist-get tag edraw-import-svg-convert-element-alist)))
        (funcall fun elem context)
      (if (or (and edraw-import-svg-in-defs
                   (not (eq ns 'unknown)))
              (eq edraw-import-svg-level 'loose))
          (progn
            (edraw-import-warn (edraw-msg "Keep unsupported element: %s") tag)
            (edraw-import-svg-convert-unsupported-element elem context))
        (edraw-import-warn (edraw-msg "Discard unsupported element: %s") tag)
        nil))))

(defun edraw-import-svg-convert-comment (_elem _context)
  ;; Discard comment
  nil)

(defun edraw-import-svg-convert-a (elem context)
  ;; Expose contents
  ;; @todo check style?
  (edraw-import-svg-convert-children elem context))

(defun edraw-import-svg-convert-definition (elem context)
  (push
   (let ((edraw-import-svg-in-defs edraw-import-svg-keep-unsupported-defs))
     (edraw-dom-element
      (edraw-dom-tag elem)
      :attributes (edraw-import-svg-convert-element-attributes elem context)
      :children (edraw-import-svg-convert-children elem context)))
   (plist-get (car context) :definitions))
  nil)

(defun edraw-import-svg-convert-unsupported-element (elem context)
  (edraw-dom-element
   (edraw-dom-tag elem)
   :attributes (edraw-import-svg-convert-element-attributes elem context)
   :children (edraw-import-svg-convert-children elem context)))

(defun edraw-import-svg-convert-group (elem context)
  (edraw-dom-element
   (edraw-dom-tag elem)
   :attributes (edraw-import-svg-convert-element-attributes elem context)
   :children (edraw-import-svg-convert-children elem context)))

(defun edraw-import-svg-convert-shape (elem context)
  (edraw-dom-element
   (edraw-dom-tag elem)
   :attributes (edraw-import-svg-convert-element-attributes elem context)))

(defun edraw-import-svg-convert-circle (elem context)
  (let ((r (dom-attr elem 'r)))
    (when r
      (edraw-dom-element
       'ellipse
       :rx r
       :ry r
       :attributes (edraw-import-svg-convert-element-attributes
                    elem context '(r))))))

(defun edraw-import-svg-convert-line (elem context)
  (let ((x1 (edraw-svg-attr-length elem 'x1))
        (y1 (edraw-svg-attr-length elem 'y1))
        (x2 (edraw-svg-attr-length elem 'x2))
        (y2 (edraw-svg-attr-length elem 'y2)))
    (when (and x1 y1 x2 y2)
      (edraw-dom-element
       'path
       :d (edraw-path-d-from-command-list `((M ,x1 ,y1 ,x2 ,y2)))
       :attributes (edraw-import-svg-convert-element-attributes
                    elem context '(x1 y1 x2 y2))))))

(defun edraw-import-svg-convert-poly-shape (elem context) ;; polyline or polygon
  (let* ((closepath (eq (edraw-dom-tag elem) 'polygon))
         (points-attr (dom-attr elem 'points))
         (points (edraw-svg-parse-points (or points-attr ""))))
    (cond
     ((null points-attr)
      (edraw-import-warn (edraw-msg "No `points' attribute: %s")
                         (edraw-dom-tag elem))
      nil)
     ((null points)
      (edraw-import-warn (edraw-msg "Empty `points' attribute: %s")
                         (edraw-dom-tag elem))
      nil)
     (t
      (edraw-dom-element
       'path
       :d (edraw-path-d-from-command-list
           (nconc
            (list (cons 'M (cl-loop for (x . y) in points
                                    collect x collect y)))
            (when closepath (list (list 'Z)))))
       :attributes (edraw-import-svg-convert-element-attributes
                    elem context '(points)))))))

(defun edraw-import-svg-convert-text (elem context)
  ;;@todo Extract text attributes from style properties? Should edraw-dom-svg.el parse style?
  (edraw-dom-element
   (edraw-dom-tag elem)
   :attributes (edraw-import-svg-convert-element-attributes elem context)
   :children (edraw-import-svg-convert-children elem context)))

(defun edraw-import-svg-convert-tspan (elem context)
  (edraw-dom-element
   (edraw-dom-tag elem)
   :attributes (edraw-import-svg-convert-element-attributes elem context)
   :children (edraw-import-svg-convert-children elem context)))


;;;;; Convert Attribute

(defun edraw-import-svg-convert-element-attributes (elem context &optional
                                                         exclude-attrs)
  (edraw-import-svg-convert-attributes
   (if exclude-attrs
       (cl-loop for kv in (edraw-dom-attributes elem)
                unless (memq (car kv) exclude-attrs)
                collect kv)
     (edraw-dom-attributes elem))
   elem
   context))

(defun edraw-import-svg-convert-attributes (attributes elem context)
  (cl-loop for (k . v) in attributes
           for new-attr = (edraw-import-svg-convert-attribute k v elem context)
           when new-attr
           collect new-attr))

(defvar edraw-import-svg-convert-attributes-alist
  ;; https://developer.mozilla.org/ja/docs/Web/SVG/Attribute
  '((class . edraw-import-svg-convert-attr-keep)
    (id . edraw-import-svg-convert-attr-keep)
    (opacity . edraw-import-svg-convert-attr-keep)
    (fill . edraw-import-svg-convert-attr-keep)
    (fill-opacity . edraw-import-svg-convert-attr-keep)
    (fill-rule . edraw-import-svg-convert-attr-keep)
    (stroke . edraw-import-svg-convert-attr-keep)
    (stroke-opacity . edraw-import-svg-convert-attr-keep)
    (stroke-width . edraw-import-svg-convert-attr-keep)
    (stroke-dasharray . edraw-import-svg-convert-attr-keep)
    (stroke-dashoffset . edraw-import-svg-convert-attr-keep)
    (stroke-linecap . edraw-import-svg-convert-attr-keep)
    (stroke-linejoin . edraw-import-svg-convert-attr-keep)
    (stroke-miterlimit . edraw-import-svg-convert-attr-keep)

    (style . edraw-import-svg-convert-attr-style)
    (transform . edraw-import-svg-convert-attr-keep)
    ;; geometry
    (x . edraw-import-svg-convert-attr-keep) ;;@todo check text's x
    (y . edraw-import-svg-convert-attr-keep) ;;@todo check text's y
    (cx . edraw-import-svg-convert-attr-keep)
    (cy . edraw-import-svg-convert-attr-keep)
    (width . edraw-import-svg-convert-attr-keep)
    (height . edraw-import-svg-convert-attr-keep)
    (r . edraw-import-svg-convert-attr-keep)
    (rx . edraw-import-svg-convert-attr-keep)
    (ry . edraw-import-svg-convert-attr-keep)
    ;; path
    (d . edraw-import-svg-convert-attr-d)
    (marker-start . edraw-import-svg-convert-attr-keep) ;;@todo check
    (marker-mid . edraw-import-svg-convert-attr-keep) ;;@todo check
    (marker-end . edraw-import-svg-convert-attr-keep) ;;@todo check
    ;; text
    (dx . edraw-import-svg-convert-attr-keep)
    (dy . edraw-import-svg-convert-attr-keep)
    (font-family . edraw-import-svg-convert-attr-keep)
    (font-size . edraw-import-svg-convert-attr-keep)
    (font-weight . edraw-import-svg-convert-attr-keep)
    (font-style . edraw-import-svg-convert-attr-keep)
    (text-decoration . edraw-import-svg-convert-attr-keep)
    (text-anchor . edraw-import-svg-convert-attr-keep)
    (writing-mode . edraw-import-svg-convert-attr-keep)
    ;; image
    (xlink:href . edraw-import-svg-convert-attr-keep)
    (href . edraw-import-svg-convert-attr-keep)
    (preserveAspectRatio . edraw-import-svg-convert-attr-keep) ;; svg or image
    ;; svg
    (viewBox . edraw-import-svg-convert-attr-keep)
    (version . edraw-import-svg-convert-attr-keep)
    (xmlns . edraw-import-svg-convert-attr-keep)
    (xmlns:xlink . edraw-import-svg-convert-attr-keep)
    ;; Inkscape
    (role\(http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd\)
     . edraw-import-svg-convert-attr-inkscape-role)
    ))

(defun edraw-import-svg-convert-attribute (attr-name value elem context)
  (let* ((attr-name-ns (edraw-import-svg-normalize-name attr-name context)))
    ;; Ignore xmlns:<ns>= and xmlns=
    (when attr-name-ns
      (let* ((attr-name (car attr-name-ns))
             (ns (cdr attr-name-ns))
             (fun (alist-get attr-name
                             edraw-import-svg-convert-attributes-alist)))
        (cond
         (fun
          (funcall fun attr-name value elem context))
         ;; Ignore internal attribute
         ((edraw-dom-attr-internal-p attr-name)
          nil)
         ;; Keep data attribute
         ((string-prefix-p "data-" (symbol-name attr-name))
          (cons attr-name value))
         ;; Unsupported attribute
         (t
          (if (or (and edraw-import-svg-in-defs
                       (not (eq ns 'unknown)))
                  (eq edraw-import-svg-level 'loose))
              (progn
                (edraw-import-warn (edraw-msg "Keep unsupported attribute: %s")
                                   attr-name)
                (cons attr-name value))
            (edraw-import-warn (edraw-msg "Discard unsupported attribute: %s")
                               attr-name)
            nil)))))))

(defun edraw-import-svg-convert-attr-keep (attr-name value _elem _context)
  (cons attr-name value))

(defun edraw-import-svg-convert-attr-style (attr-name value _elem _context)
  (edraw-import-warn (edraw-msg "Support for `style' attributes is insufficient and may cause display and operation problems"))
  (cons attr-name value))

(defun edraw-import-svg-convert-attr-d (attr-name value _elem _context)
  ;; Check multiple subpaths and A command
  (let ((cmds (condition-case err
                  (edraw-path-d-parse value)
                (error
                 (edraw-import-warn (edraw-msg "Parsing error: %s") err)
                 (setq value nil) ;;Discard
                 nil))))
    ;; Check empty path data
    (unless cmds
      (setq value nil cmds nil) ;;Discard
      (edraw-import-warn (edraw-msg "Empty path data")))

    ;; Check unsupported path command
    ;;@todo Call `edraw-path-cmdlist-from-d'?
    (when-let ((c (seq-find (lambda (cmd)
                              (not (memq
                                    (car cmd)
                                    '(M m Z z L l H h V v C c S s Q q T t))))
                            cmds)))
      ;; As of 2024-03-11, if there is an unsupported command, an
      ;; error will occur during editing, so discard it.
      (unless (eq edraw-import-svg-level 'loose)
        (setq value nil cmds nil)) ;;Discard
      (edraw-import-warn (edraw-msg "Unsupported path command: `%s'") (car c)))

    ;; Check not start with M
    (when (and cmds (not (memq (caar cmds) '(M m))))
      (setq value nil cmds nil) ;;Discard
      (edraw-import-warn (edraw-msg "Path data does not start with M")))

    ;; Check multiple subpaths (multiple M or command after Z)
    (when (and cmds (cl-loop for x on (cdr cmds)
                             when (or (memq (car x) '(M m))
                                      (and (memq (car x) '(Z z))
                                           (cdr x)))
                             return t))
      (edraw-import-warn (edraw-msg "Multiple subpaths are not supported and may cause display and operation problems"))))

  (when value
    (cons attr-name value)))

(defun edraw-import-svg-convert-attr-inkscape-role (attr-name
                                                    value elem _context)
  (if (and (eq (edraw-dom-tag elem) 'tspan)
           (string= value "line"))
      (cons 'class "edraw-text-line") ;;@todo If elem already has a class?
    ;; Otherwise discard
    (edraw-import-warn (edraw-msg "Discard unsupported attribute: %s")
                       attr-name)
    nil))

;;;; XML

;;@todo Use xmltok.el?

;; https://www.w3.org/TR/xml/#NT-S
(defconst edraw-xml-re-wsp "[ \t\r\n]+")
(defconst edraw-xml-re-wsp-opt "[ \t\r\n]*")
;; https://www.w3.org/TR/xml/#NT-Name
(defconst edraw-xml-re-name "\\(?:[_[:alpha:]][-._[:alnum:]]*\\)")
(defconst edraw-xml-re-name-with-colon
  (concat
   ;; (1)<name>(:(2)<name>)?
   "\\(?:\\(" edraw-xml-re-name "\\)\\(?::\\(" edraw-xml-re-name "\\)\\)?\\)"))
(defconst edraw-xml-re-start
  (concat
   "<\\(?:"
   ;; (1)
   "\\(!--\\)" "\\|"
   ;; (2)
   "\\(!\\[CDATA\\[\\)" "\\|"
   ;; (3)
   "\\(\\?\\)" "\\|"
   ;; (4):(5)
   edraw-xml-re-name-with-colon
   "\\|"
   ;; (6):(7)
   "\\(?:/" edraw-xml-re-name-with-colon "\\)"
   "\\)"))
;; https://www.w3.org/TR/xml/#NT-Attribute
(defconst edraw-xml-re-attr
  (concat
   edraw-xml-re-wsp
   ;; (1):(2)
   edraw-xml-re-name-with-colon
   edraw-xml-re-wsp-opt
   "="
   edraw-xml-re-wsp-opt
   ;; (3)"..." or '...'
   "\\(\\(?:\"[^<&\"]*\"\\)\\|\\(?:'[^<&']*'\\)\\)"))
(defconst edraw-xml-re-tag-close
  (concat "\\(?:" edraw-xml-re-wsp-opt "/>\\|>\\)"))

(defun edraw-xml-escape-ns-buffer ()
  "Replace tag names and attribute names related to namespace.

`libxml-parse-xml-region' removes all elements related to the
namespace, so replace tag and attribute names to avoid this.

Make the following substitutions:

<(ns):(tag)   => <_ns-(ns)--(tag)
</(ns):(tag)  => </_ns-(ns)--(tag)
(ns):(attr)=  => _ns-(ns)--(attr)
xmlns:(ns)=   => _ns-xmlns--(ns)
xmlns=        => _ns-xmlns--

To split an escaped name string on a colon, use `edraw-xml-unescape-ns-name'."
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward edraw-xml-re-start nil t) ;; Skip CharData
      (cond
       ((match-beginning 1)
        (search-forward "-->")) ;; error if not found
       ((match-beginning 2)
        (search-forward "]]>")) ;; error if not found
       ((match-beginning 3)
        (search-forward "?>")) ;; error if not found
       ((match-beginning 6)
        ;; Replace </(6):(7) with </_ns-(6)--(7)
        (when (match-beginning 7)
          (replace-match
           (concat "</" "_ns-" (match-string 6) "--" (match-string 7)) t))
        (search-forward ">")) ;; error if not found
       ((match-beginning 4)
        ;; Replace <(4):(5) with <_ns-(4)--(5)
        (when (match-beginning 5)
          (replace-match
           (concat "<" "_ns-" (match-string 4) "--" (match-string 5)) t))

        ;; Replace attribute names
        (save-match-data
          (while (looking-at edraw-xml-re-attr)
            (goto-char (match-end 0))
            ;; Replace (1):(2)= with _ns-(1)--(2)=
            ;; Replace (1:xmlns)= with _ns-(1:xmlns)--=
            (when (or (match-beginning 2)
                      (equal (match-string 1) "xmlns"))
              (let (;;(ns-url (substring (match-string 3) 1 -1))
                    (name1 (match-string 1))
                    (name2 (match-string 2)))
                (save-excursion
                  (delete-region (match-beginning 1) (or (match-end 2)
                                                         (match-end 1)))
                  (goto-char (match-beginning 1))
                  (insert (concat "_ns-" name1 "--" name2)))))))

        (unless (looking-at edraw-xml-re-tag-close)
          (error "XML syntax error: tag not closed"))
        (goto-char (match-end 0)))))))

(defun edraw-xml-unescape-ns-name (name)
  (let ((name-str (symbol-name name)))
    (if (string-match "\\`_ns-\\(.+\\)--\\(.*\\)\\'" name-str)
        (let ((name1 (match-string 1 name-str))
              (name2 (match-string 2 name-str)))
          (if (string= name1 "xmlns")
              ;; ('xmlns . "name"-or-nil)
              (cons (intern name1)
                    (and (not (string-empty-p name2)) name2))
            ;; ("name" . attr-or-tag)
            (cons name1 (intern name2))))
      ;; (nil . attr-or-tag)
      (cons nil name))))

(defun edraw-xml-collect-ns-decls (elem)
  "Collect namespace declarations from DOM element ELEM.

Return ((prefix-symbol-or-nil . url-string) ...)"
  (when (edraw-dom-element-p elem)
    (cl-loop for (key . value) in (edraw-dom-attributes elem)
             for (name1 . name2) = (edraw-xml-unescape-ns-name key)
             when (eq name1 'xmlns) collect (cons name2 value))))

(provide 'edraw-import)
;;; edraw-import.el ends here
