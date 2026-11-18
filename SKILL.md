---
name: baicizhan-daily
description: 从百词斩助手（baicizhan-helper）拉取账号下全部单词本，按艾宾浩斯遗忘曲线挑出当日该复习的单词，生成 500 英文词以内的原创文章、含全量释义与百词斩原生例句的词卡、以及一段可直接开练的对话 topic。Use when the user asks for 今日单词、每日英语、百词斩、单词文章、背单词复习、daily English lesson, or wants to generate today's vocabulary article and chat topic.
---

# baicizhan-daily

每天一次，产出三份东西：一篇文章、一份词卡、一个对话 topic。

- 脚本：`scripts/bcz.ps1`（本机没有 Python 和 Node，全部走 PowerShell）
- 接口与数据结构：见 [reference.md](reference.md)
- 文章体裁池与三份产物的模板：见 [templates.md](templates.md)
- 运行数据：`%USERPROFILE%\baicizhan-daily\`
- 当日产物：`%USERPROFILE%\baicizhan-daily\<YYYY-MM-DD>\`

## 工作流

复制这份 checklist 并逐项推进：

```
- [ ] 1. 确认    列出今天的 12 个词（上次词表），请用户逐词明确回复「认识 / 不认识」，不设默认值
- [ ] 2. 写入    把用户确认后的结果写入台账（认识 → mark known；不认识 → mark unknown）
- [ ] 3. sync    拉取全部单词本，更新台账
- [ ] 4. plan    算出当日词表（固定 12 个词，写入 plan.json）
- [ ] 5. detail  取全量释义和百词斩原生例句
- [ ] 6. 选体裁  挑一个近期没用过的「体裁 + 主题」组合
- [ ] 7. 写文章  article.md，600–650 英文词，目标词加粗，过 check_article 校验
- [ ] 8. 写词卡  vocab.md，并把完整词卡原样贴进对话
- [ ] 9. 写topic topic.md，角色扮演 prompt + 备用问题
- [ ] 10. 收尾   回写 style-history.json，报告词表与文件路径，提醒用户收新词（如需要）
```

**硬性规则**：
- 台账只在用户**明确回复**熟悉度之后才改变。不设默认值，用户未回复的词不写入。
- 写入前必须先把改动清单（词、选择、将执行的 mark）发给用户，用户确认后才执行。
- 顺序不能颠倒：必须先完成第 1、2 步（写入台账），再执行第 4 步 plan 固定当日词表，最后生成内容。
- 生成过程中不得直接调用 `mark`，除第 2 步外不改动台账。
- 不使用 Excel。`台账.xlsx`、`import_ledger_xlsx.py`、`export_ledger_xlsx.py` 不再被本流程调用。

### 1. 确认熟悉度（每次生成前先做）

列出上次词表中的 12 个词（来自 `<上次日期目录>\plan.json` 的 `markable_topic_ids` 对应词），请用户按编号逐词回复「认识 / 不认识」。

展示表格的固定格式（列顺序不能改）：

| 编号 | 单词 | 例句 | 释义 | 状态 |
|---|---|---|---|---|

- **例句**：每个词必须有一条例句，取自 `<上次日期目录>\words.json` 的 `sentences`（百词斩原生例句），例句英文在前，中文翻译紧随其后
- **释义**：放在例句的**后面**，即 `chn_means` 的中文释义，不放在例句前面
- **状态**：初始为空，等用户回复后再填「认识 / 不认识」

示例（单行）：

| 编号 | 单词 | 例句 | 释义 | 状态 |
|---|---|---|---|---|
| 1 | overhead compartment | Do you have any space left in the overhead compartment? 行李架上还有剩余的空间吗？ | phr. 行李架 | |

- 用户必须对每个词给出明确回答；未回答的词不写入台账
- 用户可以用简短的编号形式回复，例如「1 认识、2 不认识、3 认识……」
- 把用户回答整理成改动清单发给用户确认，例如：

  | 编号 | 单词 | 选择 | 将执行 |
  |---|---|---|---|
  | 1 | overhead compartment | 认识 | mark known |
  | 2 | budget airline | 不认识 | mark unknown |

- 用户确认后进入第 2 步；用户要求修改则重新整理清单

若第一次运行、没有上次词表，则跳过本步，直接进入第 3 步。

### 2. 写入台账

用户确认后，按改动清单执行（`$S` 是本 skill 目录）：

```powershell
powershell -ExecutionPolicy Bypass -Command "& '$S\scripts\bcz.ps1' mark -Date <上次日期> -Result known -TopicIds @(<认识的 topic_id 列表>)"
powershell -ExecutionPolicy Bypass -Command "& '$S\scripts\bcz.ps1' mark -Date <上次日期> -Result unknown -TopicIds @(<不认识的 topic_id 列表>)"
```

- `认识` → stage +1，按曲线推后；`不认识` → stage 归 0，明天再来
- `-TopicIds` 必须是数组字面量 `@(...)`，不能用逗号拼接字符串
- 只改用户确认过的词，其余词不动
- 执行前先告知将要执行的命令，用户确认后再正式执行

脚本调用一律用这个形式（`$S` 是本 skill 目录）：

```powershell
powershell -ExecutionPolicy Bypass -File "$S\scripts\bcz.ps1" <command> [参数]
```

脚本调用一律用这个形式（`$S` 是本 skill 目录）：

```powershell
powershell -ExecutionPolicy Bypass -File "$S\scripts\bcz.ps1" <command> [参数]
```

### 1. sync

```powershell
powershell -ExecutionPolicy Bypass -File "$S\scripts\bcz.ps1" sync
```

拉取全部单词本（不只「收藏的单词」），把新词写进台账并初始化为 stage 0。

**如果退出码是 2 或输出以 `TOKEN_REQUIRED` 开头**，说明没有 token 或 token 已过期。此时立刻停下来，把脚本打印的那段控制台取数命令原样转给用户，等他回贴 token，然后执行：

```powershell
powershell -ExecutionPolicy Bypass -File "$S\scripts\bcz.ps1" token -Token "<用户贴来的token>"
```

存好之后从第 1 步重来。不要自己去猜 token，也不要跳过取词直接编单词。

### 2. plan

```powershell
powershell -ExecutionPolicy Bypass -File "$S\scripts\bcz.ps1" plan
```

写出 `<日期>\plan.json` 并打印路径。用 Read 工具读这个文件，拿到当日词表。

选词规则由脚本实现，你不需要重算。当日固定 12 个词（昨天收得特别多时会更多），**全部**要进文章。
每个词带一个 `source`，决定它在第 2 步写入台账时怎么处理（预习词不写入）：

- `source: "new"` — 昨天新收藏的词，必选，不受名额限制
- `source: "curve"` — 曲线上今天到期的词，按欠得最久的优先补进来
- `source: "preview"` — 到期词不够 12 个时提前拉来凑数的预习词，**不计入复习记录**，不写入台账

不用自己判断哪些能 mark，`plan.json` 里的 `markable_topic_ids` 已经算好了，不带 `-TopicIds` 的
`mark` 也只会动这批词。

另外注意 `silence_days`：超过 5 天没收藏新词时，第 10 步要在报告末尾提醒用户去收点新词。

### 3. detail

```powershell
powershell -ExecutionPolicy Bypass -File "$S\scripts\bcz.ps1" detail
```

不带参数就取当日词表里的所有词；也可以 `detail -TopicIds 1,2,3` 指定。结果写进 `<日期>\words.json`，用 Read 读。

里面是**全量**的释义和例句：`chn_means` 是分词性的所有中文释义，`sentences` 是百词斩里该词自带的所有例句，每条都带 `sentence_trans` 中文翻译。不要截断，词卡里有几条给几条。

### 4. 选体裁

读 `%USERPROFILE%\baicizhan-daily\style-history.json`，看最近 14 天用过哪些「体裁 + 主题」组合，挑一个没撞上的。体裁池和主题池在 [templates.md](templates.md)。

当日这 12 个词来自不同收藏日、不同领域，语义上多半不成群。**先扫一遍词表，找出能自然容纳最大
子集的那个主题**，以它定场景，别先挑主题再硬塞词。剩下三两个拽不进来的离群词，宁可在同一场景里
显得突兀，也不要为它们另开一个场景。

约束：**双主持人对话占一半左右**。翻一下历史记录，如果最近几天都是双主持人就换别的，如果最近都没出现过就用双主持人。

### 5. 写文章

按 [templates.md](templates.md) 的文章规格写 `<日期>\article.md`。硬性要求：

- 正文 **600–650 个英文单词**，上限 650，写完自己数一遍，把实际词数写在文末
- `plan.json` 里的词**全部**要在正文里自然出现（不是罗列，是用进句子）
- **只用一个场景，往深里挖。** 一个地点、一段时间、一组人物。不要"先在厨房再去机场"地换地方，
  装不下的离群词用场景内部的支线（一通电话、一句回忆、一个旁白）拽进来
- 每个目标词先在语境里出现，紧接着用简单英语解释一次
- **每个目标词在正文里必须加粗**（`**word**`），每个词至少加粗一次。除目标词外不加粗任何其他内容。
  这一条是硬性的，写完必须运行校验，不通过就修改后重跑，直到 PASS：
  ```powershell
  python "$S\scripts\check_article.py" "<日期目录>"
  ```
  校验会检查：12 个目标词都出现且都加粗、没有多余加粗、正文词数不超过 650。
- 纯英文正文，贴近真实生活使用场景
- 不用 BBC 品牌、固定开场白和它的主持人名字，系列名自取

12 个词装进 650 词全靠单场景摊薄开销：场景在开场段建一次，后面所有词共用这套上下文，
每个词只付"语境句 + 解释 + 推进剧情"约 37 词。一换场景就要重新交代人物处境，预算立刻超。

### 6. 写词卡

按 [templates.md](templates.md) 的词卡模板写 `<日期>\vocab.md`。

写完之后，**把 vocab.md 的完整内容原样贴进对话回复里**。不要只说"已生成，见文件"，不要摘要，不要只贴前两个词。用户要的就是在对话里直接看到释义和例句。

### 7. 写 topic

按 [templates.md](templates.md) 的模板写 `<日期>\topic.md`：一段可整段复制的角色扮演 prompt，后面跟 3–5 个备用讨论问题。

场景要和文章里的**换一个**，不要复述文章内容——同一批词换个情境才是迁移。

### 8. 收尾

1. 把本次用掉的「体裁 + 主题」追加进 `style-history.json`
2. 报告：今天用了哪几个词、各自的 stage 和下次复习日、文章实际词数、三份文件的路径
3. `silence_days > 5` 时提醒用户去收新词

### 9. 回填

已取消。熟悉度完全通过第 1、2 步的对话确认完成，不再使用 Excel。

## 选词规则速查

```
stage      0    1    2    4    7    15   30   60
新词入库 → stage 0，due_date = 收藏当天
标 known → stage +1，due_date = 今天 + 该档间隔
标 unknown → stage 归 0，due_date = 明天

当日词表凑满 12 个，分三段：
  1. new     昨天收藏的词，全要，不排序不截断
  2. curve   剩下的到期词按 due_date 升序补，补到 12 个为止，其余顺延
  3. preview 还不够 12 就把最接近到期的词提前拉来凑，排除 7 天内出现过的
```

昨天收了 14 个就是 14 个词、曲线让位；收了 0 个就全走曲线。**必选是一道独立的通道，不靠曲线
自动满足**——到期词按欠得最久优先排，昨天的词到期日最晚、排在队尾，没有这道通道就会被长期
积压的旧词挤掉。
