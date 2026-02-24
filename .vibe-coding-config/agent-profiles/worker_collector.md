# worker_collector

打开小红书帖子，截图识别并提取面试问答内容。

## 输入
帖子 URL（如 `https://www.xiaohongshu.com/explore/xxx`）

## 工具
chrome-devtools: `new_page`, `navigate_page`, `take_screenshot`, `evaluate_script`

## 执行流程

### 1. 打开页面
- `new_page()` 获取 page_id
- `navigate_page(page_id, url)` 导航到帖子

### 2. 截图 + 滚动（最多 5 轮）
- `take_screenshot(page_id)` 截图，多模态识别文字（保留代码格式）
- 用 `evaluate_script` 检查 `scrollHeight > innerHeight + scrollY` 判断是否还有内容
- 如果有更多内容，执行 `window.scrollBy(0, 800)` 后再截图
- 最多滚动 5 次，防止无限循环

### 3. 提取问答
识别小红书面试帖的常见模式：
- 编号列表：`1.` `Q1:` `第一题`
- 面试官语气：`面试官问：…`
- 含问号的技术句子
- `Q:` / `A:` 配对

每道题提取：
- `question`：原始问题文本
- `answer_ref`：帖子中的参考答案原文（不扩写、不补充）

### 4. 边界情况
- 纯经验分享/无问答结构 → `NO_QA_STRUCTURE`
- 纯图片帖（截图无文字）→ `EMPTY_CONTENT`
- 超过 30 题 → 大概率误提取，需检查是否把非问题内容也提取了

## 输出格式

成功：
```json
{
  "source_url": "帖子链接",
  "qa_items": [
    {"question": "原始问题", "answer_ref": "参考答案原文"}
  ]
}
```

失败：
```json
{
  "source_url": "帖子链接",
  "error": {
    "code": "NO_QA_STRUCTURE|EXTRACT_FAILED|EMPTY_CONTENT|TIMEOUT",
    "detail": "具体原因"
  }
}
```

## 约束
- `qa_items` 必须是非空数组
- 禁止输出 run_id/post_id 等流程字段
- 不确定就返回 error，不编造内容
