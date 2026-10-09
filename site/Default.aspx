<%@ Page Language="C#" AutoEventWireup="true" ResponseEncoding="utf-8" %>
<%@ Import Namespace="System.Configuration" %>
<%@ Import Namespace="System.Data.SqlClient" %>
<%@ Import Namespace="System.IO" %>
<%@ Import Namespace="System.Net" %>
<script runat="server">
    // 構成確認ページ
    // このサーバー、届いたリクエスト、DB の状態を表示する。入力欄はない。
    // IIS に最初から入っている機能だけで動く（ビルド不要、追加パッケージ不要）。
    // 注意: ASP.NET 4.8 の標準のコンパイラで動くよう、C# 5 までの書き方にしている。

    const string AppVersion = "1.0.1";
    const string ImdsBase = "http://169.254.169.254/latest/";

    protected string HostName = "";
    protected string InstanceId = "";
    protected string InstanceType = "";
    protected string AvailabilityZone = "";
    protected string PrivateIp = "";

    protected string ClientIp = "";
    protected string ForwardedFor = "";
    protected string Protocol = "";
    protected bool ViaLoadBalancer = false;

    // "unset" = 未設定, "ok" = 接続できた, "ng" = 接続できない
    protected string DbState = "unset";
    protected string DbServer = "";
    protected string DbMessage = "";
    protected string DbVersion = "";
    protected string AccessCount = "";
    protected string PreviousAccess = "";

    protected string PageTime = "";

    static string ToJst(DateTime utc)
    {
        TimeZoneInfo jst = TimeZoneInfo.FindSystemTimeZoneById("Tokyo Standard Time");
        DateTime local = TimeZoneInfo.ConvertTimeFromUtc(DateTime.SpecifyKind(utc, DateTimeKind.Utc), jst);
        return local.ToString("yyyy-MM-dd HH:mm:ss") + "（日本時間）";
    }

    // インスタンスの情報を取り出すための、一時的な合言葉（トークン）を取得する。
    static string GetMetadataToken()
    {
        HttpWebRequest req = (HttpWebRequest)WebRequest.Create(ImdsBase + "api/token");
        req.Method = "PUT";
        req.Proxy = null;
        req.Timeout = 2000;
        req.ContentLength = 0;
        req.Headers["X-aws-ec2-metadata-token-ttl-seconds"] = "60";
        using (HttpWebResponse res = (HttpWebResponse)req.GetResponse())
        using (StreamReader reader = new StreamReader(res.GetResponseStream()))
        {
            return reader.ReadToEnd().Trim();
        }
    }

    static string GetMetadata(string path, string token)
    {
        try
        {
            HttpWebRequest req = (HttpWebRequest)WebRequest.Create(ImdsBase + "meta-data/" + path);
            req.Method = "GET";
            req.Proxy = null;
            req.Timeout = 2000;
            req.Headers["X-aws-ec2-metadata-token"] = token;
            using (HttpWebResponse res = (HttpWebResponse)req.GetResponse())
            using (StreamReader reader = new StreamReader(res.GetResponseStream()))
            {
                return reader.ReadToEnd().Trim();
            }
        }
        catch (Exception)
        {
            return "（取得できません）";
        }
    }

    void LoadServerInfo()
    {
        HostName = Environment.MachineName;
        try
        {
            string token = GetMetadataToken();
            InstanceId = GetMetadata("instance-id", token);
            InstanceType = GetMetadata("instance-type", token);
            AvailabilityZone = GetMetadata("placement/availability-zone", token);
            PrivateIp = GetMetadata("local-ipv4", token);
        }
        catch (Exception)
        {
            InstanceId = InstanceType = AvailabilityZone = PrivateIp = "（取得できません）";
        }
    }

    void LoadRequestInfo()
    {
        ClientIp = Request.UserHostAddress ?? "";
        string forwardedFor = Request.Headers["X-Forwarded-For"];
        string forwardedProto = Request.Headers["X-Forwarded-Proto"];
        ViaLoadBalancer = !String.IsNullOrEmpty(forwardedFor);
        ForwardedFor = forwardedFor ?? "";
        if (!String.IsNullOrEmpty(forwardedProto))
        {
            Protocol = forwardedProto.ToUpperInvariant();
        }
        else
        {
            Protocol = Request.IsSecureConnection ? "HTTPS" : "HTTP";
        }
    }

    void LoadDatabaseInfo()
    {
        ConnectionStringSettings setting = ConfigurationManager.ConnectionStrings["handson"];
        if (setting == null || String.IsNullOrEmpty(setting.ConnectionString))
        {
            DbState = "unset";
            return;
        }

        try
        {
            SqlConnectionStringBuilder builder = new SqlConnectionStringBuilder(setting.ConnectionString);
            DbServer = builder.DataSource;

            using (SqlConnection con = new SqlConnection(setting.ConnectionString))
            {
                con.Open();

                // アクセス回数を1つ増やし、増やしたあとの回数と、前回のアクセス時刻を受け取る。
                // 表がなければ、最初に作る。
                using (SqlCommand cmd = con.CreateCommand())
                {
                    cmd.CommandText =
                        "IF OBJECT_ID('dbo.access_counter', 'U') IS NULL " +
                        "BEGIN " +
                        "  CREATE TABLE dbo.access_counter (" +
                        "    id INT NOT NULL PRIMARY KEY, " +
                        "    access_count BIGINT NOT NULL, " +
                        "    last_access DATETIME2 NULL); " +
                        "  INSERT INTO dbo.access_counter (id, access_count, last_access) VALUES (1, 0, NULL); " +
                        "END; " +
                        "UPDATE dbo.access_counter " +
                        "  SET access_count = access_count + 1, last_access = SYSUTCDATETIME() " +
                        "  OUTPUT inserted.access_count, deleted.last_access " +
                        "  WHERE id = 1;";
                    using (SqlDataReader reader = cmd.ExecuteReader())
                    {
                        if (reader.Read())
                        {
                            AccessCount = reader.GetInt64(0).ToString();
                            PreviousAccess = reader.IsDBNull(1) ? "（今回が初めて）" : ToJst(reader.GetDateTime(1));
                        }
                    }
                }

                using (SqlCommand cmd = con.CreateCommand())
                {
                    cmd.CommandText = "SELECT @@VERSION;";
                    string version = Convert.ToString(cmd.ExecuteScalar());
                    int lineEnd = version.IndexOf('\n');
                    DbVersion = (lineEnd > 0 ? version.Substring(0, lineEnd) : version).Trim();
                }
            }
            DbState = "ok";
        }
        catch (Exception ex)
        {
            DbState = "ng";
            DbMessage = ex.Message;
        }
    }

    protected void Page_Load(object sender, EventArgs e)
    {
        Response.Cache.SetCacheability(HttpCacheability.NoCache);
        Response.Cache.SetNoStore();
        PageTime = ToJst(DateTime.UtcNow);
        LoadServerInfo();
        LoadRequestInfo();
        LoadDatabaseInfo();
    }
</script>
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>構成確認ページ</title>
<style>
  body { font-family: "Yu Gothic UI", "Meiryo", sans-serif; margin: 0; background: #f3f6f8; color: #1f2933; }
  header { background: #0f5d6b; color: #fff; padding: 16px 24px; }
  header h1 { margin: 0; font-size: 20px; }
  header p { margin: 4px 0 0; font-size: 13px; opacity: 0.9; }
  main { max-width: 860px; margin: 24px auto; padding: 0 16px; }
  section { background: #fff; border: 1px solid #d5dde2; border-radius: 6px; margin-bottom: 20px; }
  section h2 { margin: 0; padding: 12px 16px; font-size: 16px; border-bottom: 1px solid #d5dde2; color: #0f3f48; }
  table { width: 100%; border-collapse: collapse; }
  th, td { text-align: left; padding: 10px 16px; border-bottom: 1px solid #eef2f4; font-size: 14px; vertical-align: top; }
  tr:last-child th, tr:last-child td { border-bottom: none; }
  th { width: 34%; color: #52606d; font-weight: normal; }
  td { font-family: Consolas, "Yu Gothic UI", monospace; word-break: break-all; }
  .badge { display: inline-block; padding: 2px 10px; border-radius: 10px; font-size: 13px; color: #fff; font-family: "Yu Gothic UI", "Meiryo", sans-serif; }
  .ok { background: #2f7d32; }
  .ng { background: #c62828; }
  .unset { background: #64748b; }
  .note { padding: 0 16px 12px; font-size: 13px; color: #52606d; }
  footer { text-align: center; font-size: 12px; color: #52606d; padding-bottom: 24px; }
</style>
</head>
<body>
<header>
  <h1>構成確認ページ</h1>
  <p>このページを表示しているサーバー、届いたリクエスト、DB の状態を表示します。</p>
</header>
<main>

  <section>
    <h2>このサーバー</h2>
    <table>
      <tr><th>ホスト名</th><td><%: HostName %></td></tr>
      <tr><th>インスタンスID</th><td><%: InstanceId %></td></tr>
      <tr><th>インスタンスタイプ</th><td><%: InstanceType %></td></tr>
      <tr><th>アベイラビリティーゾーン</th><td><%: AvailabilityZone %></td></tr>
      <tr><th>プライベートIPアドレス</th><td><%: PrivateIp %></td></tr>
    </table>
  </section>

  <section>
    <h2>届いたリクエスト</h2>
    <table>
      <tr><th>プロトコル</th><td><%: Protocol %></td></tr>
      <tr><th>このサーバーから見た接続元</th><td><%: ClientIp %></td></tr>
      <tr>
        <th>ロードバランサー</th>
        <td>
          <% if (ViaLoadBalancer) { %>
            経由している（もとの接続元：<%: ForwardedFor %>）
          <% } else { %>
            経由していない
          <% } %>
        </td>
      </tr>
    </table>
  </section>

  <section>
    <h2>DB</h2>
    <table>
      <tr>
        <th>状態</th>
        <td>
          <% if (DbState == "ok") { %>
            <span class="badge ok">接続できた</span>
          <% } else if (DbState == "ng") { %>
            <span class="badge ng">接続できない</span>
          <% } else { %>
            <span class="badge unset">未設定</span>
          <% } %>
        </td>
      </tr>
      <% if (DbState == "unset") { %>
        <tr><th>説明</th><td>DB の接続情報が、まだ設定されていません。第2週で設定します。</td></tr>
      <% } %>
      <% if (DbState != "unset") { %>
        <tr><th>接続先</th><td><%: DbServer %></td></tr>
      <% } %>
      <% if (DbState == "ok") { %>
        <tr><th>アクセス回数</th><td><%: AccessCount %></td></tr>
        <tr><th>前回のアクセス</th><td><%: PreviousAccess %></td></tr>
        <tr><th>DB の種類</th><td><%: DbVersion %></td></tr>
      <% } %>
      <% if (DbState == "ng") { %>
        <tr><th>エラーの内容</th><td><%: DbMessage %></td></tr>
      <% } %>
    </table>
    <% if (DbState == "ok") { %>
      <p class="note">アクセス回数は DB に保存しています。このページを表示するたびに、1つ増えます。</p>
    <% } %>
  </section>

</main>
<footer>
  表示した時刻：<%: PageTime %>　／　構成確認ページ v<%: AppVersion %>
</footer>
</body>
</html>
