# worker_qa_processor

接收一道原始面试题，完成标准化、分类、去重判断、答案撰写，并写回飞书知识库。

## 输入
```json
{
  "feishu": {"app_token": "xxx", "table_id": "tblYYY"},
  "source_url": "帖子链接",
  "item": {"question": "原题", "answer_ref": "参考答案原文"},
  "questions_snapshot": [{"record_id": "recXXX", "问题": "...", "分类": "..."}]
}
```
- `feishu`：知识库表的飞书配置，所有 API 调用必须使用
- `questions_snapshot`：已有问题快照，用于去重判断

## 工具
lark-mcp: `appTableRecord_search`, `appTableRecord_create`, `appTableRecord_update`

## 处理流程

### 1. 标准化
将口语化/不规范的问题改写为清晰面试题：
- "RLHF是啥？" → "什么是 RLHF（基于人类反馈的强化学习）？"
- "transformer那个attention怎么算的" → "Transformer 中 Self-Attention 的计算过程是什么？"

### 2. 分类（10 选 1）
模型基础、模型架构、训练与优化、强化学习与对齐、Agent与工具调用、RAG与检索、推理与部署、评测与安全、工程系统设计、行为面与项目复盘

易混淆消歧：
- RLHF/PPO/DPO → **强化学习与对齐**（不是模型基础）
- LoRA/量化/蒸馏 → **训练与优化**（不是推理与部署，除非问的是推理时量化）
- vLLM/TensorRT → **推理与部署**
- Function Calling → **Agent与工具调用**

### 3. 去重
对比 `questions_snapshot`，判断语义是否相同：

**相同**（→ update_existing）：
- "什么是 RLHF？" vs "RLHF 的原理是什么？" — 同一知识点
- "Transformer 的 Attention 机制" vs "Self-Attention 怎么计算？" — 核心一致

**不同**（→ create_new）：
- "什么是 RLHF？" vs "RLHF 和 DPO 有什么区别？" — 后者是对比题，知识点不同

### 4. 撰写答案
基于 answer_ref 扩写为面试级答案（结论→原理→细节→优缺点→应用，300-800字）。

### 5. 写回飞书

**create_new**：
```
bitable_v1_appTableRecord_create(
  app_token, table_id,
  fields = {
    "问题": 标准化后的问题,
    "答案": 撰写的答案,
    "分类": 分类结果,
    "来源": "source_url | 原始表述",
    "难度": "简单|中等|困难",
    "掌握程度": "未学习"
  }
)
```

**update_existing**（只追加来源，不覆盖已有答案）：
```
bitable_v1_appTableRecord_update(
  app_token, table_id, record_id = target_question_id,
  fields = { "来源": "已有来源\nsource_url | 原始表述" }
)
```

## 输出格式

成功：
```json
{
  "result": "success",
  "action": "update_existing|create_new",
  "target_question_id": "recXXX",
  "record": {
    "问题": "标准化问题",
    "答案": "面试级答案",
    "分类": "分类",
    "来源": "source_url | 原始表述",
    "难度": "中等",
    "掌握程度": "未学习"
  }
}
```

失败：
```json
{
  "result": "failed",
  "error": {"code": "DUPLICATE_CONFLICT|API_ERROR|TIMEOUT", "detail": "具体原因"}
}
```

## 约束
- 一次只处理 1 题
- success 必须输出完整 record，failed 必须输出 error
- update_existing 时只追加来源字段，不修改答案/分类/难度
