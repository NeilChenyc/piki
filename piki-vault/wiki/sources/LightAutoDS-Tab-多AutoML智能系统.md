---
title: "LightAutoDS-Tab：面向表格数据的多 AutoML 智能体系统"
type: wiki-source
source_ref: "raw/sources/about-the-dataset-93a85bfa.md"
tags: [AutoML, LLM-Agent, 表格数据, 数据科学自动化]
created: 2026-06-17
---

# LightAutoDS-Tab：面向表格数据的多 AutoML 智能体系统

> 来源：arXiv 2507.13413v1 · Sber AI Lab & ITMO University · 2025-07-17

---

## 核心问题

传统 AutoML 工具（AutoGluon、H2O）依赖预定义搜索空间，配置门槛高；LLM-based Agent 方案虽然灵活，却存在两个致命缺陷：

1. **过度分支**：树搜索式方案（AIDE/SELA）在每个分支都要携带完整历史，计算代价高；
2. **上下文窗口瓶颈**：随对话轮次增加，上下文急剧膨胀，后期 pipeline 阶段的模型组合效果反而下降。

---

## 核心方案：LightAutoDS-Tab

将 **LLM 代码生成能力** 与 **多个成熟 AutoML 工具**（LightAutoML、FEDOT）结合，取长补短。

### 多 Agent 架构

| Agent | 职责 |
|---|---|
| Interactor | 理解用户意图，判断是交互问答还是构建 ML 流水线 |
| Planner | 制定 ML pipeline 方案 |
| Generator | 基于 LLM 生成完整代码（Scikit-learn / CatBoost / TabPFN 等） |
| Validator | 评估代码正确性与指标表现 |
| Improver | 迭代优化不达标的代码 |
| AutoML | 调用 LightAutoML / FEDOT，由 LLM 提取关键参数完成配置 |
| Interpreter | 为每步生成技术/非技术双视角报告 |

### 双路由机制

系统根据任务特征**自动**或按用户指令选择路径：

- **LLM 驱动代码生成**：Planner → Generator → Validator → Improver（迭代直到验证通过）
- **AutoML 工具配置**：LLM 从任务描述中提取参数，直接驱动 LightAutoML 或 FEDOT

---

## 关键设计取舍

- LLM 负责**早期阶段**（EDA、数据预处理、框架配置），不试图替代 AutoML 做模型搜索；
- 代码围绕"骨架（skeleton）"生成，覆盖 ML pipeline 的所有必要步骤，而不是完全自由生成；
- RAG 增强（文档检索）在实验中**尚未成功**，作者将其列为局限性；
- LLM 对代码生成效果**高度敏感**：GigaChat2Max 与 GPT-4o 在相同任务上结果有明显差异。

---

## 实验结果（8 个 Kaggle 数据集）

评价指标：归一化性能分（NPS，越高越好）

| 方案 | 平均 NPS |
|---|---|
| LightAutoDS (LAMA+LLM) | **0.839** |
| LightAutoDS (FEDOT+LLM) | 0.835 |
| LightAutoDS (CodeGen) | 0.835 |
| AutoKaggle | 0.816 |
| AIDE | 0.703 |
| 人类 Q50（中位线） | 0.836 |

LightAutoDS-Tab 的最优配置（LAMA+LLM）达到人类中位水平，显著优于纯 LLM 方案 AIDE。

---

## 局限与未来方向

1. **仅支持表格数据**：时序、序列数据暂不支持；
2. **EDA 智能化不足**：数据泄露等异常检测依赖人工，需要更智能的 EDA 模块；
3. **代码生成不稳定**：即使先进推理模型也无法在多次迭代后保证可执行代码，RAG 改进尚未成功。

---

## 相关概念

- [[concepts/Agent 工作流]] — 与本文的多 Agent 协作模式直接相关
- [[concepts/大模型维基]] — LLM 作为代码生成引擎的背景知识
