# 壊れたPDFからのプレビュー復旧（2026-10-07）

## 原因

正常PDF → dvipdfmxの画像ページ指定エラーによる不完全PDF → 正常PDF、という順番で同じファイルを再読み込みすると、ちらつき防止のHideViewが残ってプレビューを覆う。

reShowWithPath:は再読み込み前の画面をmyHideView1として重ね、最後にタイマーで除去する。壊れたPDFの読み込みではdocumentがnilになる。その次の正常PDF読み込みはneedsInitialization=YESとなり、setup → initializeDisplayが呼ばれる。

initializeDisplayはmyHideView1とmyHideView2をnilにしていたが、ビュー階層からは除去していなかった。直前に重ねた灰色の画面画像の参照が失われ、removeHideView1:のタイマーからも除去できなくなる。PDFDocumentとページ自体は正常に更新されている。

## 修正

initializeDisplayで参照をnilにする前に、両HideViewにremoveFromSuperviewを送る。PDFの読み込み方式、失敗時の灰色表示、倍率・位置保持のロジックは変更しない。

## 検証

Tests/run-pdf-recovery.pyはリポジトリのreShowWithPath:、prepareSecond、reShowForSecond、initializeDisplay、HideView除去メソッドとHideView.mを使用する独立したPDFKitテスト。ウィンドウ管理・設定UI等の無関係な処理はスタブで置き換える。画面キャッシュは灰色の画像を生成し、画面収録権限やTeXShop本体の起動を必要としない。

- 1ページしかないhoge.pdfに対し、ユーザー指定のtetsujsarticle・tetsuryoku文書でimgの2ページ目を要求。uplatex2pdfを実行し、TeX→DVI成功、dvipdfmx失敗、3490バイトの不完全PDFを確認。
- imgを1ページ目へ修正し、同じスクリプトで正常PDF生成成功。
- 同一パスを正常→不完全→正常へ上書きし、両ペインの読み込み・再初期化・タイマー処理を検証。修正前は正常ページ取得後もHideViewが残ることで失敗。修正後は通過。
- ちらつき防止ON/OFF、4表示モード、NSData/URL読み込みの16条件。PDFの白いページが実際に描画され、灰色画像が残らないことも確認。
- 引数なしでは独立生成したPDFと不完全データを使う。実際のコンパイル結果を使う場合は、正常PDFと不完全PDFの2パスを引数に指定する。

既存のユーザー文書・設定は変更していない。TeXShop本体のGUIで組版する通し操作とは区別する。

社内版・国際版のDebug／Releaseビルド成功。社内版Releaseの署名検証成功。国際版は署名なしでビルド。修正前ソースに同じ回帰テストを適用すると、灰色キャッシュ画像が残る検査で失敗することも確認した。
