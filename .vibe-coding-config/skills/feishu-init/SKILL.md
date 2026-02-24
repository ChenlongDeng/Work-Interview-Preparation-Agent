---
name: feishu-init
description: 飞书多维表格初始化：按路径发现/创建文件夹和 Base
---

# feishu-init

主控 Agent 启动时自动执行。按 `FEISHU_BASE_PATH` 逐级查找/创建文件夹，在末级文件夹中发现或创建多维表格。

## 环境变量

```bash
FEISHU_BASE_PATH="云盘/AI/八股复习"   # 目标路径
FEISHU_BASE_NAME="面试题知识库"       # Base 名称
```

## 流程

1. 拆分路径 → 逐级 `drive_v1_file_list` 查找文件夹，不存在则 `drive_v1_file_createFolder`
2. 在末级文件夹中搜索同名 bitable，存在则复用
3. 不存在则 `bitable_v1_app_create` + 创建两张表

## 表结构

**原始帖子表**：链接(Url) / 状态(SingleSelect: 待处理/处理中/已完成/失败/部分完成/忽略) / 元信息(Text)

**知识库表**：问题(Text) / 答案(Text) / 答案附件(Attachment) / 分类(SingleSelect) / 来源(Text) / 难度(SingleSelect) / 掌握程度(SingleSelect)

分类选项：模型基础、模型架构、训练与优化、强化学习与对齐、Agent与工具调用、RAG与检索、推理与部署、评测与安全、工程系统设计、行为面与项目复盘

## 输出

```json
{"status": "created|found", "app_token": "...", "tables": {"posts": "tblXxx", "knowledge": "tblYyy"}}
```
