# Work-Interview-Preparation-Agent

小红书面试题自动采集与整理 Agent 框架。

## 核心角色

```
┌─────────────────────────────────────────────────────────────┐
│                      主 Agent（调度器）                      │
│  • 拉取帖子表（非"已完成"状态）                               │
│  • 并行调度 Collector 采集帖子                                │
│  • 按需获取问题快照（最近N条）                                │
│  • 串行调度 QA Processor 处理题目                             │
│  • 写回飞书，更新帖子状态                                     │
└─────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┴───────────────────┐
          ▼                                       ▼
┌─────────────────────┐                 ┌─────────────────────┐
│  worker_collector   │                 │ worker_qa_processor │
│  （并行，每帖一个）   │                 │ （串行，逐题处理）   │
│                     │                 │                     │
│ 输入: 帖子URL        │                 │ 输入: 单题 + 问题快照 │
│ 输出: 问答列表       │                 │ 输出: 标准化问题     │
│ 工具: Chrome DevTools│                │ 工具: 飞书 API       │
└─────────────────────┘                 └─────────────────────┘
```

## 完整流程

```
Step 1: 拉取任务
  └─ 获取帖子表中「状态≠已完成」的帖子（待处理/处理中/失败/部分完成）
  
Step 2: 并行采集（每帖一个 Worker）
  ├─ Worker 1: 帖子A → [{question, answer_ref}, ...]
  ├─ Worker 2: 帖子B → [{question, answer_ref}, ...]
  └─ Worker N: 帖子C → error（记录失败，熔断检查）
  
Step 3: 按需获取问题快照
  └─ 只拉取最近 N 条问题（而非全量），用于去重判断
  
Step 4: 构建处理队列
  └─ 合并所有成功帖子的 qa_items
  
Step 5: 串行处理（每题一个 Worker）
  ├─ 题目1: 标准化 → 去重判断 → 写回飞书 → 更新快照
  ├─ 题目2: 标准化 → 去重判断 → 写回飞书 → 更新快照
  └─ 题目3: ...
  
Step 6: 收尾
  └─ 更新帖子状态（已完成/部分完成/失败）
```

## Worker 详细职责

### worker_collector（采集 Agent）

**做什么**：打开小红书帖子，提取面试题和参考答案。

**输入**：`https://www.xiaohongshu.com/explore/xxxxx`

**输出**：
```json
{
  "source_url": "https://www.xiaohongshu.com/explore/xxxxx",
  "qa_items": [
    {"question": "什么是RLHF？", "answer_ref": "RLHF是..."},
    {"question": "Transformer原理？", "answer_ref": "自注意力机制..."}
  ]
}
```

**失败时**：
```json
{"source_url": "...", "error": {"code": "EXTRACT_FAILED", "detail": "无有效内容"}}
```

**怎么做**：
1. 用 Chrome DevTools 打开帖子链接
2. 截图识别文字（支持滚动加载多图）
3. 提取显式问题（带问号或面试官语气）
4. 记录参考答案原文（不做扩写）

---

### worker_qa_processor（处理 Agent）

**做什么**：把一道原始题目转化为标准化问题，并决定是新建还是更新。

**输入**：
```json
{
  "source_url": "https://www.xiaohongshu.com/explore/xxxxx",
  "item": {"question": "RLHF是啥？", "answer_ref": "RLHF是..."},
  "questions_snapshot": [
    {"record_id": "rec_abc", "standard_question": "什么是RLHF？", "category_l1": "强化学习", "category_l2": "RLHF流程"}
  ]
}
```

**输出**：
```json
{
  "result": "success",
  "action": "update_existing",
  "target_question_id": "rec_abc",
  "record": {
    "standard_question": "什么是RLHF？",
    "category_l1": "强化学习与对齐",
    "category_l2": "RLHF流程",
    "answer": "RLHF（Reinforcement Learning from Human Feedback）是..."
  }
}
```

**怎么做**：
1. **标准化问题**：优化措辞（如"RLHF是啥"→"什么是RLHF"）
2. **分类**：确定大类（如"强化学习与对齐"）和小类（如"RLHF流程"）
3. **去重判断**：对比 `questions_snapshot`，语义判断是否已存在相同题目
   - 存在 → `update_existing`，追加来源关联
   - 不存在 → `create_new`，创建新问题
4. **撰写答案**：基于 `answer_ref` 扩写为面试级完整答案
5. **写回飞书**：调用 API 创建/更新记录

---

## 数据表结构

只需**两个表**，简化设计：

### 表1：原始帖子表（采集任务队列）
| 字段 | 类型 | 说明 |
|------|------|------|
| 链接 | URL | 小红书帖子URL |
| 状态 | SingleSelect | 待处理/处理中/已完成/失败/部分完成/忽略 |
| 元信息 | Text | JSON：`{更新时间, 题目总数, 成功数, 失败原因}` |

**状态流转**：
```
待处理 → 处理中 → 已完成
               ↘ 部分完成
               ↘ 失败
```

### 表2：知识库表（核心，支持手动添加）
| 字段 | 类型 | 说明 |
|------|------|------|
| 问题 | Text | 标准问题文本（必填，可手动添加） |
| 答案 | Text | 答案文本，支持 Markdown |
| 答案附件 | Attachment | 图片/代码截图等多模态内容 |
| 分类 | SingleSelect | 自定义分类 |
| 标签 | MultiSelect | 关键词标签 |
| 来源 | Text | 来源记录（格式：`链接 | 原始表述`） |
| 难度 | SingleSelect | 简单/中等/困难 |
| 掌握程度 | SingleSelect | 未学习/学习中/已掌握/需复习 |
| 复习次数 | Number | 复习计数 |
| 下次复习日期 | DateTime | 间隔重复提醒 |
| 创建时间 | CreatedTime | 自动记录 |
| 最后修改 | ModifiedTime | 自动记录 |

**特点**：
- ✅ **支持手动添加**：不依赖小红书采集，自由添加自己的题目
- ✅ **多模态答案**：文字（Markdown）+ 图片附件
- ✅ **复习管理**：掌握程度追踪 + 间隔重复

---

## 分类体系

| 大类 | 小类 |
|------|------|
| 模型基础 | 参数与容量、损失函数、优化器、泛化与过拟合 |
| 模型架构 | Transformer细节、注意力机制、位置编码、MoE |
| 训练与优化 | 预训练、微调、蒸馏与量化、分布式训练 |
| 强化学习与对齐 | RL基础、RLHF流程、奖励建模、偏好优化 |
| Agent与工具调用 | Agent规划、函数调用、工具选择、多Agent协作 |
| RAG与检索 | 索引构建、召回排序、Chunk策略、检索评估 |
| 推理与部署 | 推理优化、服务架构、观测与告警、成本治理 |
| 评测与安全 | 离线评测、在线评测、越狱与注入、数据安全 |
| 工程系统设计 | 系统拆分、可靠性、幂等与重试、数据建模 |
| 行为面与项目复盘 | 项目亮点、取舍与权衡、故障复盘、跨团队协作 |

---

## 快速开始

### 配置（自动初始化）

只需配置路径，主控 Agent 启动时会**自动创建**表格：

```bash
# .env.mcp.local
export FEISHU_BASE_PATH="云盘/AI/八股复习"    # 目标路径（支持多级）
export FEISHU_BASE_NAME="面试题知识库"        # Base 名称
```

然后启动主 Agent：

```bash
./.vibe-coding-config/scripts/sync-configs.sh all-core
# 主 Agent 会自动：
# 1. 查找/创建路径中的各级文件夹
# 2. 在目标文件夹创建多维表格
# 3. 创建帖子表和知识库表
```

### 手动指定 Table ID（已有表格）

```bash
export FEISHU_APP_TOKEN="bascn_xxxxx"
export FEISHU_POSTS_TABLE_ID="tbl_xxxxx"
export FEISHU_KNOWLEDGE_TABLE_ID="tbl_yyyyy"
```

---

## 关键设计

### 为什么先拉取帖子而非问题表？

**传统做法（低效）**：
1. 先全量拉取问题表（可能几千条）
2. 再拉取帖子表
3. 问题：大部分时间花在拉取无关问题上

**本方案（高效）**：
1. 先拉取帖子表（通常 <20 条/轮）
2. 并行采集，知道实际需要处理哪些问题
3. 按需获取问题快照（最近 N 条，通常 200 条足够）
4. 问题：新问题通常和近期问题重复，老问题很少被重复提问

### 问题快照策略

| 问题表大小 | 策略 |
|-----------|------|
| < 1000 条 | 全量拉取 |
| >= 1000 条 | 只拉最近 200 条（按更新时间倒序）|

### 断点续传

帖子状态支持断点续传：
- `处理中`：上次被中断，重新采集处理
- `失败`：上次失败，可重试
- `部分完成`：部分题目成功，下次只处理未成功的

---

## 防御规则

| 规则 | 触发条件 | 行为 |
|------|----------|------|
| 熔断 | 连续3帖采集失败 | 立即停止，输出告警 |
| 限流 | 单轮超过20帖 | 分页处理 |
| 重试 | API 429/5xx | 指数退避，最多3次 |
