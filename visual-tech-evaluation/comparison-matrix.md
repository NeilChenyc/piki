# 方案对比速查表

## 一句话总结

| 方案 | 一句话 | 评分 |
|------|--------|------|
| **AI 内联 SVG + CSS** | 当前方式的直接升级，零依赖，AI 天生擅长 | ⭐⭐⭐⭐ |
| **LottieFiles AI** | AI 生成专业矢量 + 动画，JSON 即用 | ⭐⭐⭐⭐⭐ |
| **GSAP + GSAPify** | 动画天花板，但需要商业许可 | ⭐⭐⭐⭐⭐ |
| **Mermaid** | AI 极擅长生成，适合架构/流程图 | ⭐⭐⭐⭐ |
| **excalidraw-diagram** | 手绘风格，适合非正式图表 | ⭐⭐⭐ |
| **Spline 3D** | 3D 展示的终极方案，性能较重 | ⭐⭐⭐⭐ |
| **unDraw** | 开源插图直接拿来用，零门槛 | ⭐⭐⭐⭐ |
| **frontend-dev** | 完整页面生成，偏 React 技术栈 | ⭐⭐⭐⭐ |

## 快速决策矩阵

```
需要专业矢量动画？
├── 是 → LottieFiles AI（AI 生成 SVG 再手动加动画）
└── 否 → 继续

需要复杂滚动叙事动画？
├── 是，预算充足 → GSAP + ScrollTrigger
├── 是，零成本 → 增强版 AI SVG + CSS scroll-driven
└── 否 → 继续

需要架构图/流程图？
├── 正式风格 → Mermaid
└── 手绘风格 → excalidraw-diagram

需要 3D 展示？
├── 是 → Spline 嵌入
└── 否 → 继续

需要数据图表？
├── 简单 → Mermaid
└── 复杂 → D3.js / Observable Plot

快速填充插图？
└── unDraw 下载开源 SVG
```

## 性能对比

| 方案 | 额外体积 | 运行时开销 | 首次渲染阻塞 |
|------|---------|-----------|-------------|
| AI 内联 SVG + CSS | 0KB JS | 0ms | 否 |
| Lottie | ~30KB | 低 | 否（可延迟加载） |
| GSAP | ~30KB（核心）| 低 | 否 |
| Spline 3D | ~500KB+ | 中-高 | 是 |
| Mermaid | ~100KB | 中 | 是 |
| D3.js | ~80KB | 低 | 否 |
