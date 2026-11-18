# baicizhan-daily 参考

## token：怎么拿、什么时候要重拿

百词斩助手（Chrome 扩展 `ofdejofffdjcmlbclhhfeaefodgffbnm`）把登录态用 zustand persist 存在
`chrome.storage.local['auth-storage']` 里，值是一个 JSON 字符串，token 在 `.state.token`。

Cursor 的内置浏览器是另一个 Chrome 实例，**没有**这个扩展，所以读不到。token 只能由用户从自己
装了扩展的 Chrome 里取一次，脚本缓存在 `config.json`，过期了再取。

脚本在以下三种情况会打印 `TOKEN_REQUIRED` 并以**退出码 2** 结束：

- `config.json` 里 token 为空
- HTTP 401
- 响应体里 `code == 401`

碰到退出码 2 时，把下面这段完整转给用户（这是给人看的版本）：

> 1. 在装了「百词斩助手」的 Chrome 里打开 `chrome://extensions`
> 2. 打开右上角的「开发者模式」
> 3. 找到「百词斩助手」，点它下方的 **Service Worker**（或「检查视图 service worker」）
> 4. 在弹出的控制台里粘贴这一行并回车：
>
> ```js
> chrome.storage.local.get('auth-storage', r => console.log(JSON.parse(r['auth-storage']).state.token))
> ```
>
> 5. 把打印出来的那串字符贴回给我

拿到后存起来：

```powershell
powershell -ExecutionPolicy Bypass -File "<skill>\scripts\bcz.ps1" token -Token "<粘贴的token>"
```

如果扩展处于休眠状态看不到 Service Worker 链接，让用户先点一下扩展图标把它唤醒。

## 接口

Base `https://www.baicizhan-helper.cn`，鉴权是请求头 `access_token: <token>`（不是 Bearer）。
所有响应都包一层 `{ code, message, data }`，`code` 为 400 / 401 / 403 / 500 时才算失败。

### `GET /books`

`data.user_books[]`：

| 字段 | 说明 |
| --- | --- |
| `user_book_id` | 单词本 id，下一个接口要用 |
| `book_name` | 单词本名，例如「收藏的单词」 |
| `word_num` | 词数 |
| `updated_at` | unix 秒 |

### `GET /book/{bookId}/words`

`data[]`：

| 字段 | 说明 |
| --- | --- |
| `topic_id` | 单词全局 id，台账主键 |
| `word` | 英文词 |
| `mean` | 简短释义，只有一条 |
| `created_at` | **unix 秒，这就是收藏时间** |
| `book_id` | 所属单词本 |
| `audio_us` / `audio_uk` | 发音资源路径 |

`created_at` 必须按本地时区（UTC+8）换算成日期再比较，否则跨零点会错一天。
脚本里是 `ConvertFrom-UnixTime`，顺带兜了毫秒时间戳的情况。

### `GET /word/{topicId}?withDict=true&withMedia=false&withSimilarWords=false`

全量词典数据在 `data.dict`（个别词会落在 `data.dict_wiki.dict`，脚本两处都试）：

| 字段 | 说明 |
| --- | --- |
| `word_basic_info.accent_usa` / `accent_uk` | 美式 / 英式音标 |
| `word_basic_info.etyma` | 词源 |
| `chn_means[]` | **全部**中文释义，按词性分条：`mean_type` + `mean` |
| `en_means[]` | 英文释义 |
| `sentences[]` | **百词斩原生例句**：`sentence` + `sentence_trans`（中文翻译）+ `highlight_phrase` |
| `short_phrases[]` | 常用短语：`short_phrase` + `short_phrase_trans` |
| `synonyms[]` / `antonyms[]` | 近义 / 反义，取 `syn_ant` |
| `exams[]` | 考纲标签 |

词卡要的是**全量**，不要截断。每个词一次请求，当日 6–8 个词就是 6–8 次，没有负担。

### 其他可用接口（当前未使用）

- `GET /search/word/{word}` — 按拼写查词
- `GET /userInfoWithVip` — 用户信息，可用来验活 token
- `PUT /book/{bookId}/word/{topicId}` — 收藏
- `DELETE /book/{bookId}/word/{topicId}` — 取消收藏
- `POST /login/sendSmsVerifyCode/{phoneNum}` 和 `POST /login/{phoneNum}/{smsVerifyCode}` — 短信登录换 token

## 艾宾浩斯间隔

```
stage      0    1    2    3    4    5    6    7
间隔(天)   0    1    2    4    7    15   30   60
```

- 新词入库：`stage = 0`，`due_date = 收藏当天`
- 标 `known`：`stage += 1`（封顶 7），`due_date = 今天 + 该档间隔`
- 标 `unknown`：`stage = 0`，`due_date = 明天`（不退回已经过去的收藏日）

**stage 0 的间隔是 0 天**，所以新词收藏当天就到期、标记后次日再到期，天然有资格进当日词表。
但"有资格"不等于"选得上"：到期词按 `due_date` 升序排，昨天的词到期日最晚、天然排在队尾，
一旦台账里堆着一批长期没 mark 的旧词，新词会被持续挤到名额之外。所以必选是
[选词算法](#选词算法)里一道**独立的通道**，不依赖曲线。

## 选词算法

目标是每天凑满 `daily_target`(12) 个词，分三段取，每个词在 `plan.json` 里带 `source` 标明出处。

```
today    = 本机日期
active   = 台账里 removed = false 的词

1. mustHave  source = "new"
   active 中 collected_date == today - 1 的全部词，按 created_at 升序
   不看 due_date，不设上限，不截断
   昨天收了 14 个，当日就是 14 个词，曲线和预习全部让位

2. curveTake  source = "curve"
   dueAll  = active 中 due_date <= today，按 due_date / stage / created_at 升序
   dueRest = dueAll 去掉 mustHave
   取前 max(0, daily_target - mustHave.Count) 个
   deferred_count = dueRest 剩下的个数，自然顺延到次日

3. previewFill  source = "preview"
   仅当前两段凑不满 daily_target 时触发（台账小，或大部分词都在高 stage）
   从未选中的词里按 due_date 升序取 shortfall 个，排除 dedup_window_days(7) 天内曝光过的
   去重后仍不够就放宽窗口补齐
   预习不写 stage，也不改 due_date，不计入复习
```

`mode` 只是个摘要：全是预习为 `preview`，掺了预习为 `mixed`，否则 `due`。真正决定能不能 mark 的是
`markable_topic_ids`，里面是 `source != "preview"` 的那些 id。台账词数实在不够 `daily_target` 时
plan 会打印 `UNDERFILLED`。

`silence_days = today - 最近一次收藏日`，超过 `silence_alert_days`(5) 时 plan 会打印
`SILENCE_ALERT`，收尾报告要提醒用户去收新词。

## 数据文件

都在 `%USERPROFILE%\baicizhan-daily\`，统一 UTF-8 无 BOM。脚本写 JSON 时会把 PowerShell
产生的 `\uXXXX` 还原成真字符，所以可以直接用 Read 工具读。

### `config.json`

```json
{
  "token": "",
  "series_name": "English in Six",
  "daily_target": 12,
  "article_max_words": 650,
  "dedup_window_days": 7,
  "silence_alert_days": 5
}
```

`Get-Config` 会把缺的键补上默认值并回写，也会删掉早期版本遗留的 `max_daily_words` 和
`preview_count`。

### `ledger.json`

```json
{
  "version": 1,
  "updated_at": "2026-10-18 00:52:11",
  "word_count": 68,
  "words": [
    {
      "topic_id": 101,
      "word": "commute",
      "mean": "通勤",
      "book_id": 1,
      "book_name": "收藏的单词",
      "created_at": 1792285200,
      "collected_date": "2026-10-18",
      "audio_us": "",
      "audio_uk": "",
      "stage": 1,
      "last_reviewed": "2026-10-18",
      "due_date": "2026-10-19",
      "removed": false,
      "history": [
        { "date": "2026-10-18", "result": "known", "stage": 1 }
      ]
    }
  ]
}
```

`sync` 只刷新来自接口的字段（`word` / `mean` / `book_*` / `audio_*`），复习状态一律保留。
从单词本里删掉的词不会被物理删除，只标 `removed = true`，退出选词但保留历史。

### `exposure.json`

哪天给出过哪些词，预习去重靠它。

```json
{ "days": [ { "date": "2026-10-18", "topic_ids": [101, 102, 103] } ] }
```

`plan` 每次运行都会覆盖当天那条，所以同一天重跑不会把窗口撑大。

### `style-history.json`

由 agent 维护，不归脚本管。

```json
{
  "days": [
    { "date": "2026-10-18", "format": "two-host dialogue", "theme": "租房与押金", "title": "..." }
  ]
}
```

### `<yyyy-MM-dd>/`

`plan.json`（当日词表）、`words.json`（全量释义与例句）、`article.md`、`vocab.md`、`topic.md`。

## 退出码

| 码 | 含义 |
| --- | --- |
| 0 | 成功 |
| 1 | 普通错误（台账为空、参数不对、预习日拒绝 mark 等） |
| 2 | **需要用户提供新 token** |

## 排错

- **脚本报语法错**：`bcz.ps1` 必须保持纯 ASCII。Windows PowerShell 5.1 会把无 BOM 的
  UTF-8 脚本按 GBK 读，一旦混入中文注释就会解析失败。
- **读出来的中文是乱码**：别用 `Get-Content`，它按 ANSI 代码页解码。用
  `[System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)`，或者直接用 Read 工具。
- **台账里的释义本身就是乱码**（`备件` 存成 `å¤ä»¶`）：接口响应的 `Content-Type` 不带 charset，
  PowerShell 5.1 的 `Invoke-RestMethod` 这时会按 ISO-8859-1 解码，中文在取数阶段就毁了。
  `Invoke-Bcz` 改用 `Invoke-WebRequest -UseBasicParsing` 再手动
  `[Text.Encoding]::UTF8.GetString($web.RawContentStream.ToArray())` 解决。
  已经存坏的台账跑一次 `sync` 就会被覆盖修好。
- **台账看起来空了**：`Read-JsonFile` 对空文件返回 `$null`，plan 会报 "Ledger is empty"。
  跑一次 `sync` 重建即可，复习历史在 `ledger.json` 被覆盖前都还在。
