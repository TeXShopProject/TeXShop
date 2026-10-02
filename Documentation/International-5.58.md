# 国際版 TeXShop 5.58 の作業記録（2026-10-02）

## 基点

`$HOME/Downloads/TexShop-5.58-GG-Source` の原本を独立したリポジトリにコピーした。
初期コミットは `a1c197b`。生成済み build、.DS_Store、Xcode個人設定は追跡対象外。
社内版の独自リソース、ブランド、印刷変更、Sparkle除去は適用していない。版番号は国際版5.58のまま。

## 変更

- メールで提出した6項目を個別コミットにした。ピンチ倍率同期、リロード倍率保持、初回ページ位置、PDF描画座標、ツールバーサイズ指定、PDF外観選択。
- `7716549` で提出した最終ZIPのファイルに一致させた。Terada注釈、旧外観設定キーの整理、外観処理のコンパイルガードを含む。
- `6450d0e` でHTMLビューを実行時に生成する方式へ変更。全12言語のTSDocument.nibにNSViewコンテナを保存し、TSDocumentが実行中のOSのWKWebViewを生成する。HTML表示機能は維持する。
- 全12言語のPreferences.nibのタブを上揃えとし、テーマの内側のタブも含めて内容領域を拡張。固定フォント名をシステムフォントへ変更。括弧チェック欄の幅と高さを調整。
- ルーマニア語・中国語に残った、所有者からのアウトレット接続がない旧欄を非表示にした。旧欄のオブジェクト自体や接続は残し、現在の設定欄は維持した。

## 検証

- DebugとReleaseをXcodeでビルド。署名は無効化し、ビルド時の最低OSを14.6に指定した。プロジェクトの配布設定は変更していない。
- Release実行ファイルはx86_64とarm64を含む。
- `Tests/verify-interfaces.py`：全12言語のPreferencesとTSDocumentのアクション・アウトレットを原本と照合。HTMLコンテナのアウトレット名変更以外は一致。
- タブ内容の上余白12ptと子ビューの領域内配置を検証。
- 生成済みReleaseバンドルも含め、TSDocument.nibにWKWebViewおよびWKColorExtensionViewがないこと、htmlViewContainer接続があることを検証。
- 実アプリの設定初期化を呼ばない独立ハーネスで全12言語のPreferencesを読み込み、全9タブを切り替えた。テーマ内の2タブも確認した。
- 最後のルーマニア語・中国語の旧欄非表示と見出し位置の微調整については、再コンパイルと接続チェックで確認。再撮影時にホストがロックされたため、その最終差分の画面再確認は未実施。
- HTML生成方式は社内版でSequoiaとGolden Gateの検証を済ませた修正の移植。今回作成した国際版アプリ本体について、両OSでのGUI一式の再試験は実施していない。
- この作業ではTeXShop本体をホストで起動せず、ユーザーのTeXShop設定・Libraryを変更していない。

ビルド出力と検証ログは `$HOME/Library/Developer/TeXShop-international-5.58-build` に保存。
署名・公証・公開・pushは行っていない。

## 再検証

リポジトリ直下から実行する。Pythonは利用環境のpython3を使う。

```
python3 Tests/verify-interfaces.py /path/to/TeXShop.app
clang -fobjc-arc -framework Cocoa Tests/PreferencesPreview.m -o /tmp/PreferencesPreview
/tmp/PreferencesPreview Resources/Interfaces/*/Preferences.nib
```

ハーネスの値はnibに保存された仮の値であり、実設定を読み書きしない。
「Next language」で次の言語へ進む。実アプリ用の保存・取消ボタンは使わない。
`normalize-preferences.py` はタブの配置補正用、`compile-interface.py Preferences TSDocument` は編集元XMLからコンパイル済みnibを更新する補助スクリプト。
