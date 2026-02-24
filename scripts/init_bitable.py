#!/usr/bin/env python3
"""
飞书多维表格配置检查工具

功能：
1. 检查环境变量配置是否完整
2. 显示当前配置的目标路径
3. 说明自动初始化流程

注意：实际初始化由主控 Agent 调用 MCP API 完成
"""

import os
import sys


def check_config():
    """检查配置并显示信息"""
    
    print("=" * 60)
    print("飞书多维表格配置检查")
    print("=" * 60)
    
    base_path = os.getenv("FEISHU_BASE_PATH", "云盘/AI/八股复习")
    base_name = os.getenv("FEISHU_BASE_NAME", "面试题知识库")
    app_token = os.getenv("FEISHU_APP_TOKEN")
    
    print(f"\n📁 目标路径: {base_path}")
    print(f"📊 Base 名称: {base_name}")
    
    if app_token:
        print(f"✅ 已指定现有表格: {app_token[:15]}...")
        print("   主控 Agent 将直接使用此表格")
    else:
        print(f"\n📝 自动初始化流程：")
        print(f"   1. 逐级查找/创建文件夹: {' > '.join(base_path.split('/'))}")
        print(f"   2. 在目标文件夹创建/发现: {base_name}")
        print(f"   3. 创建表结构:")
        print(f"      - 原始帖子表")
        print(f"      - 知识库表（支持多模态答案）")
        print(f"\n   无需手动配置，启动主 Agent 即可自动完成！")
    
    print("\n" + "=" * 60)
    print("启动命令：")
    print("=" * 60)
    print("./.vibe-coding-config/scripts/sync-configs.sh all-core")
    print("\n或直接启动主 Agent（会读取 AGENTS.md 指令）")
    
    return True


if __name__ == "__main__":
    check_config()
