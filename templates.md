# 三份产物的模板

## 文章

### 硬性约束

- 正文 **600–650 个英文单词**，上限 650。写完自己数一遍，把实际词数写进文末。不要靠感觉，不要超。
- `plan.json` 里的词**全部**要在正文里用进句子，不是罗列。通常是 12 个。
- **单场景。** 一个地点、一段时间、一组人物，从头到尾不换。
- 每个目标词先在语境里自然出现，紧接着用简单英语解释一次，不要先定义后造句。
- 纯英文正文。中文只允许出现在文末的目标词清单里。
- 难度 CEFR B1–B2。短句和中句为主，少用连续从句。
- 不用 BBC 品牌、它的固定开场白和主持人名字。系列名用 `config.json` 里的 `series_name`。

### 650 词的四段结构

1. **场景开场**（约 120 词）——直接进场景，把人物、地点、处境一次交代清楚。不要寒暄，不要"今天我们来聊"。
   这 120 词是全篇唯一一次建场景的开销，后面所有词都靠它吃饭，值得写足。
2. **冲突或反直觉点**（约 150 词）——出现一个问题、误会、意外或者和直觉相反的事实。前三四个目标词在这里自然登场。
3. **展开与解决**（约 300 词）——把事情说清楚，剩下的目标词在这里登场。每个词出现后紧跟一句简单英语解释。
4. **收束与提问**（约 80 词）——一句话落地，然后抛一个问题给读者。

### 为什么必须是单场景

目标词预算只有第 2、3 段的 450 词，摊到 12 个词是每词 37 词：语境句约 16 + 简明解释约 11 +
推进剧情约 10，正好用完。这个预算是建立在"场景只建一次、12 个词共用同一套上下文"之上的。
每换一个场景就要重新交代人物和处境，一次约 40 词，换两次就超纲，最后只能砍掉解释或者把
语境句压成干巴巴的例句——那就退回成词表了。

当日 12 个词来自不同收藏日、不同领域，不成群是常态。做法是**先扫词表，找出能自然容纳最大
子集的那个主题**，以它定场景；剩下的离群词用场景内部的支线拽进来——场景里的一通电话、一条
短信、一句回忆、一个旁白吐槽，都还在同一个地点和时间里。宁可让一两个词显得突兀，也不要
为它们另开场景。

### 体裁池

**双主持人对话占一半左右。** 写之前翻 `style-history.json`：最近几天连着用双主持人就换别的，
最近都没出现过就用双主持人。

| 体裁 | 说明 |
| --- | --- |
| two-host dialogue | 两个主持人聊一个话题，语气轻松，互相追问 |
| workplace dialogue | 同事之间的具体一件事，比如交接、返工、报销 |
| friends chat | 朋友闲聊，口语最松，缩略和口头语多一些 |
| service encounter | 客服、前台、店员、房东、医生这类一问一答 |
| interview | 面试或采访，一方主导提问 |
| podcast monologue | 单人口播，有明确的"你"作为听众 |
| short story | 三幕微型故事，有具体人物和一个转折 |
| slice-of-life essay | 第一人称生活观察随笔 |
| message thread | 短信或群聊记录，极短句，适合口语搭配 |

### 主题池

贴近真实使用场景，不写学术论文：

通勤与迟到、租房与押金、点餐与结账、看病与配药、同事协作与返工、网购退换与客服、旅行与改签、
健身与受伤、搬家与打包、面试与跳槽、手机套餐与账单、修东西与报价、带娃与请假、
室友与家务分工、快递与丢件、办证与排队、二手交易与砍价、听演唱会与抢票

选法是反过来的：不是先挑主题再塞词，而是扫一遍当日词表，看哪个主题能自然容纳最大的那个
子集，就定它。12 个词里能覆盖七八个就够了，剩下的靠场景内支线拽进来。

### 文件模板

```markdown
# [Title]

**Series:** [series_name]　**Level:** B1–B2　**Format:** [体裁]　**Date:** [yyyy-MM-dd]

[正文。按上面四段结构写，不要把段落标题写进去。]

---

## Today's words

1. **[word]** — [一句简明英文释义]
2. ...

**Word count:** [正文实际英文词数] / 650
```

## 词卡

`words.json` 里有什么就给什么，**不要截断**：`chn_means` 是分词性的全部中文释义，
`sentences` 是百词斩里该词自带的全部例句，每条都带中文翻译。

写完 `vocab.md` 之后，**把它的完整内容原样贴进对话回复里**。不要只说"已生成，见文件"，
不要摘要，不要只贴前两个词。用户要的就是在对话里直接看到释义和例句。

```markdown
# 今日词卡 · [yyyy-MM-dd]

共 [N] 个词　new [必选] / curve [到期] / preview [预习]

---

## 1. [word]

美 [accent_usa]　英 [accent_uk]
收藏于 [collected_date]　stage [stage]　下次复习 [due_date]　来源 [source]

**释义**

- [mean_type] [mean]
- [mean_type] [mean]

**百词斩例句**

1. [sentence]
   [sentence_trans]
2. [sentence]
   [sentence_trans]

**短语**

- [short_phrase] [short_phrase_trans]

**近义** [synonyms]　**反义** [antonyms]

---

## 2. [word]

...
```

没有的小节（比如某个词没有短语、没有近反义）就整节省略，不要留空占位。

## 对话 topic

```markdown
# 今日对话 topic · [yyyy-MM-dd]

## 角色扮演 prompt（整段复制到新对话）

\`\`\`text
You are my English conversation partner. Stay in character for the whole chat.

SCENE: [一个具体情境，和今天文章里的换一个]
YOUR ROLE: [一个会自然用到这些词的角色]
MY ROLE: [我的角色]
LEVEL: CEFR B1-B2. Short, natural, spoken sentences.

TARGET WORDS - you must steer the conversation so that I need to use all of them:
- [word] : [一行简明英文释义]
- [word] : [一行简明英文释义]

RULES
1. Speak only English. Open with one line that sets the scene, then ask me something.
2. One or two sentences per turn. Never lecture.
3. Each turn, use at least one target word yourself so I hear it in context.
4. When I misuse grammar or a target word, correct it inline like this:
   (-> better: "...") then continue the scene immediately.
5. Do not list the target words to me and do not explain the task.
6. After about 15 of my turns, break character once and give me:
   - which target words I used correctly
   - which ones I never used
   - my three most useful corrections
\`\`\`

## 备用问题

1. [问题]
2. [问题]
3. [问题]
```

### 几条设计纪律

- **场景必须和文章换一个。** 同一批词换个情境才是迁移，场景一样就只是在背文章。
- **释义跟着词一起塞进 prompt。** 只给孤立单词，对话很容易飘到用不上这些词的方向。
- **第 5 条不能删。** 不写这条，对方开场就会说"今天我们来练这 6 个词"，对话立刻退化成背单词。
- **第 6 条的收尾报告别省。** 这是你判断哪些词真用出来了的唯一出口，也正好对应
  `mark -Result known|unknown` 要填的东西。
- 备用问题写 3–5 个，给"不想沉浸、只想随便聊两句"的用法。

## style-history.json

收尾时追加一条，格式见 [reference.md](reference.md)：

```json
{ "date": "2026-10-18", "format": "two-host dialogue", "theme": "租房与押金", "title": "..." }
```

只保留最近 30 条就够了，太老的删掉。
