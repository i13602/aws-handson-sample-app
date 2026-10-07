# aws-handson-sample-app

AWSハンズオン研修で使う題材アプリ「構成確認ページ」。

このページを表示しているサーバー、届いたリクエスト、DB の状態を、1ページに表示する。入力欄はない。
Windows Server の IIS で動く。IIS に最初から含まれる機能だけで動き、ビルドも追加のパッケージも要らない。

## 表示するもの

| 区分 | 内容 |
|---|---|
| このサーバー | ホスト名、インスタンスID、インスタンスタイプ、アベイラビリティーゾーン、プライベートIPアドレス |
| 届いたリクエスト | プロトコル（HTTP / HTTPS）、接続元、ロードバランサーを経由しているか |
| DB | 状態（未設定 / 接続できた / 接続できない）、接続先、アクセス回数、前回のアクセス |

アクセス回数は DB に保存する。ページを表示するたびに1つ増える。

## 構成

```
site/
  Default.aspx          構成確認ページ（ASP.NET のページ1枚）
  health.html           ロードバランサーの正常判定用。「OK」とだけ返す。DB には接続しない
  web.config            IIS と ASP.NET の設定
  connection.config     DB の接続情報。最初は空（未設定）。setup-db.ps1 が書き込む
setup.ps1               構成確認ページを IIS に配置する
setup-db.ps1            DB の接続情報を設定する
userdata/
  userdata.ps1          サーバーの起動時に実行する処理（IIS、ASP.NET、Git を入れる）
```

## 使い方

### 1. サーバーを作るとき

`userdata/userdata.ps1` の内容を、EC2 のユーザーデータに貼り付ける。起動時に、IIS、ASP.NET、Git が入る。
実行の記録は、サーバーの `C:\handson-userdata.log` に残る。

### 2. アプリを配置する

サーバーにサインインし、PowerShell を「管理者として実行」で開いて、次を実行する。

```powershell
git clone --branch v1.0.0 https://github.com/i13602/aws-handson-sample-app.git C:\handson-app
C:\handson-app\setup.ps1
```

サーバーのブラウザで `http://localhost/` を開くと、構成確認ページが表示される。
この時点では、DB の状態は「未設定」と表示される。

スクリプトの実行が禁止されている、と表示された場合は、次のように実行する。

```powershell
powershell -ExecutionPolicy Bypass -File C:\handson-app\setup.ps1
```

### 3. DB の接続情報を設定する

Parameter Store に、次の3つを登録しておく。

| 名前 | 種類 | 値 |
|---|---|---|
| /dkt/db/endpoint | String | DB の接続先（RDS のエンドポイント） |
| /dkt/db/username | String | DB のユーザー名 |
| /dkt/db/password | SecureString | DB のパスワード |

サーバーの IAM ロールに、これらを読み取る権限を付けたうえで、次を実行する。

```powershell
C:\handson-app\setup-db.ps1
```

`http://localhost/` を開き直すと、DB の状態が「接続できた」に変わる。

## 研修用として割り切っている点

本番のシステムでは、このままの形では使わないこと。

- **DB の接続情報を、サーバー上のファイルに平文で書き出している。** Parameter Store から読み取るのは、設定のときの1回だけ。ページを表示するたびに読み取る形にはしていない。
- **DB のサーバー証明書を検証していない。** 通信は暗号化しているが、接続先が本物かどうかは確かめていない。
- **DB に接続できないとき、エラーの内容を画面に表示する。** 切り分けの練習のため。公開するシステムでは、内部の情報を画面に出さない。
- **DB の管理者のユーザーで接続している。** 本来は、アプリ用に権限を絞ったユーザーを作る。

## 動作の確認状況

- 確認済み（開発環境で実施）
  - PowerShell のスクリプト3本に、構文の誤りがないこと
  - `setup-db.ps1` の、接続情報をファイルに書き出す処理。記号を含むパスワードでも、正しく書き出して読み戻せること
  - `Default.aspx` の C# のコードが、コンパイルできること。リクエストの情報の判定と、時刻の変換が、意図どおりに動くこと
- 未確認（Windows Server、IIS、SQL Server が必要なため）
  - IIS の上で、ページが表示されること
  - インスタンスの情報が取得できること
  - DB への接続、アクセス回数の保存
  - `setup.ps1`、`setup-db.ps1`、`userdata.ps1` の、Windows 上での動作
  - Git の自動インストール

## 版

研修では、版を指定して取得する（`--branch v1.0.0`）。研修の途中でアプリを直しても、受講者ごとに中身がずれないようにするため。
アプリを直したときは、新しい版の番号で印（タグ）を付ける。`Default.aspx` の `AppVersion` も合わせて書き換える。
