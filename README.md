#twitcui

twitcuiは、キャラクターベースのtwitterクライアントと見せかけたPerlによる対話型インタフェース作例です。
実際に使っているものです。

* PerlによるCUIの構築（Term::ReadLine）
* CUIでの色づけ（Term::ANSIColor）

##起動

コマンドラインで

    $ chmod 755 twitcui.pl
    $ ./twitcui.pl

##files

設置者が自分で準備し書き換える必要があるファイルは以下の通りです。

* /twitter_keys.yaml : Twitter APIで使うconsumer_keyのペア
* ~/.pit/default.yaml: Config::Pitが参照するファイルで、使うユーザのaccess_tokenのペアを書いておきます（取得する時のkey指定は103行目で指定しています）。

##設置例

![設置例](http://mamesibori.net/twitcui/images/twitcui-image.png)

##changes

* ver 0.0.1 first import
* ver 0.0.2 favoriteに対応／UTF-8 Macで書き込まれたツイートをなるべく読めるように
