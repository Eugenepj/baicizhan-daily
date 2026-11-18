# baicizhan-daily

一个 WorkBuddy 技能（Skill）：每天从百词斩账号拉取单词本，按艾宾浩斯遗忘曲线挑出当日该复习的单词，生成一份原创英文短文、含全量释义与例句的词卡，以及一段可直接开练的对话 topic。

## 功能

- 每天产出三份东西：一篇文章（600–650 英文词）、一份词卡、一个对话 topic
- 按艾宾浩斯曲线自动排当日词表（必选新词 / 到期复习 / 预习凑数，固定 12 个）
- 台账记录每个词的复习阶段（stage）与下次复习日

## 安装

把整个仓库目录放到 WorkBuddy 的用户级技能目录：

```
C:\Users\<你的用户名>\.workbuddy\skills\baicizhan-daily\
```

重启 WorkBuddy 后，在对话里说「今日单词」「百词斩」「每日英语」即可触发。

## 依赖

- PowerShell（Windows 自带，无需安装）
- Python 3（仅 `scripts/check_article.py` 文章校验需要）

## 使用

首次使用需要提供百词斩账号 token，获取方式见 `reference.md` 开头。

## 数据

运行数据默认存放在 `scripts/bcz.ps1` 里的 `$DataRoot` 变量指向的目录，按需修改路径。

## 目录结构

```
├── SKILL.md          # 技能说明与完整工作流
├── reference.md      # 接口、数据结构、选词算法、排错
├── templates.md      # 文章 / 词卡 / 对话 topic 模板
└── scripts/
    ├── bcz.ps1             # 主脚本（取词 + 台账 + 排计划）
    ├── check_article.py    # 文章校验（目标词加粗 / 词数）
    ├── apply_answers.py    # 把用户答案写入台账
    ├── import_ledger_xlsx.py  # 从 Excel 导入答案
    └── export_ledger_xlsx.py  # 导出台账为 Excel
```
