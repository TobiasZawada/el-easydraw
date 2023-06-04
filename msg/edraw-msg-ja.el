;;; edraw-msg-ja.el --- Japanese Message Catalog    -*- lexical-binding: t; -*-

;; Copyright (C) 2023 AKIYAMA Kouhei

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

(defvar edraw-msg-hash-table nil)

(setq
 edraw-msg-hash-table
 #s(hash-table
    test equal
    data
    (
     ;; (load-library (expand-file-name "./edraw-msg-tools.el"))
     ;; (edraw-msg-update-catalog-buffer)
     ;; M-x edraw-msg-search at point
     ;; [BEGIN MSG DATA]
     "%s Point" "%sポイント"
     "%s Selected Shapes" "%s個の選択図形"
     "%s shapes" "%s個の図形"
     "<no name>" "<無名>"
     "Anchor Point" "アンカーポイント"
     "Anchor Points" "アンカーポイント"
     "Angle: " "角度: "
     "Apply group's transform property to children?" "グループのtransformプロパティをグループ内に適用しますか?"
     "Apply transform property to anchors" "transformプロパティをアンカーポイントへ適用"
     "Apply" "適用"
     "Arrow" "矢印"
     "Auto" "自動"
     "Background Color: " "背景色: "
     "Bring Forward" "手前へ"
     "Bring to Front" "最前面へ"
     "Cancel Edit" "編集をキャンセル"
     "Child Frame" "子フレーム"
     "Choose" "選択"
     "Circle" "円"
     "Clear..." "クリア..."
     "Close Path" "パスを閉じる"
     "Close" "閉じる"
     "Closed" "閉じました"
     "Color" "色"
     "Connected" "接続しました"
     "Convert To Path" "パスへ変換"
     "Convert To [[edraw:data=]]" "[[edraw:data=]]形式へ変換"
     "Convert To [[edraw:file=]]" "[[edraw:file=]]形式へ変換"
     "Convert To [[file:]]" "[[file:]]形式へ変換"
     "Convert contents back to text format? " "バッファの内容をテキスト形式に戻しますか?"
     "Copied %s entries" "%s項目をコピーしました"
     "Copied %s" "%sをコピーしました"
     "Copy Contents" "内容をコピー"
     "Copy" "コピー"
     "Crop..." "切り抜き..."
     "Custom Shape Tool" "カスタムシェイプツール"
     "Custom shapes have unsaved changes." "カスタムシェイプに未保存の変更があります"
     "Cut %s entries" "%s項目をカットしました"
     "Cut %s" "%sをカットしました"
     "Cut" "カット"
     "Defaults" "デフォルト"
     "Delete Point" "点を削除"
     "Delete" "削除"
     "Delete..." "削除..."
     "Delta X: " "X移動量: "
     "Delta Y: " "Y移動量: "
     "Deselect All" "全選択解除"
     "Discard changes?" "変更を破棄しますか?"
     "Do you want to close the current document?" "現在のドキュメントを閉じますか?"
     "Document Height: " "ドキュメント高さ: "
     "Document Width: " "ドキュメント幅: "
     "Document" "ドキュメント"
     "Drag the cropping range." "切り抜き範囲をドラッグで指定してください。"
     "Duplicate" "複製"
     "Edit" "編集"
     "Edraw editor has unsaved changes. Discard changes ?" "エディタには未保存の変更があります。変更を破棄しますか?"
     "Ellipse Tool" "楕円ツール"
     "Ellipse" "楕円"
     "Empty shapes cannot be registered" "空の図形は登録できません"
     "End Marker" "終点マーカー"
     "Export SVG" "SVGをエクスポート"
     "Export Section" "セクションをエクスポート"
     "Export to Buffer" "バッファへ書き出し"
     "Export to File" "ファイルへ書き出し"
     "Failed to delete entry" "項目の削除に失敗しました"
     "Failed to find insertion point" "挿入場所の特定に失敗しました"
     "Failed to save. %s. Discard changes?" "保存に失敗しました。変更を破棄しますか?"
     "File `%s' exists; overwrite? " "ファイル `%s' はすでに存在します。上書きしますか?"
     "File does not exist" "ファイルが存在しません"
     "Fill" "塗り"
     "Fill..." "塗り..."
     "Find File" "ファイルを開く"
     "Finish Edit" "編集終了"
     "Fold All Sections" "全セクション折りたたみ"
     "Font Size..." "フォントサイズ..."
     "Font Size: " "フォントサイズ: "
     "Frame" "フレーム"
     "Freehand Tool" "手書きツール"
     "Glue to selected or overlapped shape" "選択または重なり図形と接着"
     "Glue" "接着"
     "Glued Text: " "接着テキスト: "
     "Grid Interval: " "グリッド間隔: "
     "Grid" "グリッド"
     "Group" "グループ化"
     "Handle Point" "ハンドルポイント"
     "Href..." "Href..."
     "Image File: " "画像ファイル: "
     "Image Tool" "画像ツール"
     "Import Section Before" "この前にセクションをインポート"
     "Import Section" "セクションをインポート"
     "Input name: " "名前入力: "
     "Insert New Section Before" "この前に新しいセクションを挿入"
     "Insert New Section" "新しいセクションを挿入"
     "Insert New Shape Before" "この前に新しい図形を挿入"
     "Insert New Shape" "新しい図形を投入"
     "Insert Point Before" "この前に点を追加"
     "Link at point does not contain valid data" "この場所のリンクに有効なデータが含まれていません"
     "Main Menu" "メインメニュー"
     "Make Corner" "角にする"
     "Make Smooth" "滑らかにする"
     "Menu" "メニュー"
     "Mode Line" "モードライン表示"
     "Move Backward Same Level" "同じ階層の後ろへ移動"
     "Move Backward" "後ろへ移動"
     "Move Forward Same Level" "同じ階層の前へ移動"
     "Move Forward" "前へ移動"
     "Move by Coordinates..." "座標による移動..."
     "Moving Distance: " "移動距離: "
     "Next" "次"
     "No editor here" "ここにエディタはありません"
     "No entries at point" "この場所に項目がありません"
     "No glue target" "接着先がありません"
     "No link at point" "この場所にリンクがありません"
     "No need to convert" "変換の必要がありません"
     "No need to rotate" "回転の必要がありません"
     "No need to scale" "拡大縮小の必要がありません"
     "No redo data" "やり直しデータがありません"
     "No shape selected" "図形が選択されていません"
     "No shapes" "図形がありません"
     "No target object" "対象オブジェクト無し"
     "No undo data" "取り消しデータがありません"
     "No" "いいえ"
     "None" "なし"
     "Open Path" "パスを開く"
     "Overwrite?" "上書きしますか?"
     "Paste Before" "直前にペースト"
     "Paste" "ペースト"
     "Path Tool" "パスツール"
     "Path" "パス"
     "Please enter a integer or empty." "整数か空を入力してください"
     "Please enter a integer." "整数を入力してください"
     "Please enter a number or empty." "数値か空を入力してください"
     "Please enter a number, %s, or empty." "数値か%s、または空を入力してください"
     "Please enter a number." "数値を入力してください"
     "Prev" "前"
     "Properties of %s" "%sのプロパティ一覧"
     "Properties..." "プロパティ一覧..."
     "Property Editor" "プロパティエディタ"
     "Property: " "プロパティ: "
     "Rect Tool" "矩形ツール"
     "Rect" "矩形"
     "Redo" "やり直し"
     "Rename" "改名"
     "Reset Scroll and Zoom" "スクロールとズームをリセット"
     "Reset View" "表示をリセット"
     "Reset to Default" "デフォルトへリセット"
     "Resize..." "リサイズ..."
     "Reverse Path Direction" "パスの向きを反転"
     "Rotate All..." "全回転..."
     "Rotate..." "回転..."
     "SVG viewBox: " "SVG viewBox: "
     "Save" "保存"
     "Scale All..." "全拡大縮小..."
     "Scale X: " "X拡大率: "
     "Scale Y: " "Y拡大率: "
     "Scale..." "拡大縮小..."
     "Scroll and Zoom" "スクロールとズーム"
     "Search Object" "オブジェクトの検索"
     "Select %s" "%sを選択"
     "Select All" "全選択"
     "Select Next Above" "一つ手前を選択"
     "Select Next Below" "一つ奥を選択"
     "Select Tool" "選択ツール"
     "Select an object" "図形を一つ選択してください"
     "Select" "選択"
     "Selected Object" "選択オブジェクト"
     "Send Backward" "後へ"
     "Send to Back" "最背面へ"
     "Set Background..." "背景設定..."
     "Set Grid Interval..." "グリッド間隔設定..."
     "Set Property" "プロパティ設定"
     "Set View Size..." "表示サイズ設定..."
     "Set as default" "デフォルトとして設定"
     "Set" "設定"
     "Shape name: " "図形名: "
     "Shape's Defaults" "図形のデフォルト"
     "Show SVG" "SVGを表示"
     "Split Path at Point" "この点でパスを分割"
     "Start Marker" "始点マーカー"
     "Stroke" "線"
     "Stroke..." "線..."
     "Text Tool" "テキストツール"
     "Text" "テキスト"
     "Text: " "テキスト: "
     "The buffer has been killed" "バッファが既に削除されています"
     "The crop range is empty." "切り抜き範囲が空です。"
     "The extension is not .edraw.svg" "拡張子が .edraw.svg ではありません"
     "The link at point is not of type `file:'" "ポイントにあるリンクが `file:' タイプではありません"
     "The root entry cannot be deleted" "ルート項目は削除できません"
     "This shape picker is not connected to an editor" "このシェイプピッカーはエディタと接続されていません"
     "To Frame" "フレーム化"
     "To Window" "ウィンドウ化"
     "Top Most" "最前面"
     "Transform Method" "変形方式"
     "Transform" "変形"
     "Translate All..." "全平行移動..."
     "Translate..." "平行移動..."
     "Transparent BG" "透明背景"
     "Unable to cut root entry" "ルート項目はカットできません"
     "Undo" "取り消し"
     "Unglue All" "全接着解除"
     "Unglue" "接着解除"
     "Ungroup" "グループ解除"
     "Unknown type of shape definition" "知らない図形型"
     "Unsupported SVG element: %s" "未対応のSVG要素: %s"
     "View Box..." "viewBox=..."
     "View Height: " "表示高さ: "
     "View Width(or Empty): " "表示幅(空=指定解除): "
     "View" "表示"
     "Write edraw file: " "出力edrawファイル: "
     "X: " "X: "
     "Yes" "はい"
     "Y: " "Y: "
     "Z-Order" "重ね順"
     "Zoom In" "ズームイン"
     "Zoom Out" "ズームアウト"
     "[Custom Shape Tool] Click:Add shape(original size), Drag:Add shape(specified size), S-Drag:Square" "[カスタム図形ツール] クリック:図形追加(元サイズ), ドラッグ:図形追加(指定サイズ), S-ドラッグ:正方形指定"
     "\"transform\" Property" "\"transform\"プロパティ"
     "[Ellipse Tool] Drag:Add ellipse, S-Drag:Square" "[楕円ツール] ドラッグ:楕円追加, S-ドラッグ:正方形指定"
     "all, none, property names separated by spaces, or empty: " "all, none, 空白区切りのプロパティ名列, or 空: "
     "[Freehand Tool] Drag:Add path" "[手書きツール] ドラッグ:パス追加"
     "drag:Scroll, wheel:Zoom, 0:reset, q/r-click:quit" "ドラッグ:スクロール, ホイール:ズーム, 0:リセット, q/右クリック:終了"
     "[Image Tool] Click:Add image(original size), Drag:Add image(specified size), S-Drag:Square" "[画像ツール] クリック:画像追加(元サイズ), ドラッグ:画像追加(指定サイズ), S-ドラッグ:正方形指定"
     "[Path Tool] Click:Add anchor, Drag:Add anchor and handle, S-Click:45-degree, C-Click:Glue, C-u Click:Avoid connection" "[パスツール] クリック:アンカー追加, ドラッグ:アンカーとハンドルの追加, S-クリック:45度単位, C-クリック:接着, C-u クリック:接続の回避"
     "[Rect Tool] Drag:Add rect, S-Drag:Square" "[矩形ツール] ドラッグ:矩形追加, S-ドラッグ:正方形指定"
     "[Select Tool] Click:Select, Drag:Range select or Move, M-Drag:Duplicate and move, S-Click:45-degree, Double Click:Properties" "[選択ツール] クリック:選択, ドラッグ:範囲指定または移動, M-ドラッグ:複製移動, S-クリック:45度単位, ダブルクリック:プロパティエディタ"
     "[Text Tool] Click:Add, C-Click:Glue" "[テキストツール] クリック:テキスト追加, C-クリック:接着"
     ;; [END MSG DATA]
     )))

;;(provide 'edraw-msg-ja)
;;; edraw-msg-ja.el ends here
