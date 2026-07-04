# AI 生成官网视觉实操指南

## 原则

不改变 Astro 零依赖的核心理念，所有增强都在 **纯 SVG + CSS** 框架内完成。

---

## 技巧 1：让 AI 生成带渐变和滤镜的丰富 SVG

### 当前 Hero SVG 的问题
- 平面白色卡片 + 细灰描边
- 绿色是唯一强调色
- 没有深度感

### 升级 Prompt 模板

```
为产品官网的 Hero section 生成一个内联 SVG 图解：
- 主题：[产品核心概念，如"碎片知识汇聚为 Wiki"]
- 风格：现代 SaaS 产品风格，磨砂玻璃质感
- 配色：主色 #4CAF50，辅助色梯度从浅绿到深绿
- 特效：使用 SVG <filter> 添加投影和发光效果
- 动画：使用 CSS @keyframes，滚动触发入场
- viewBox: "0 0 480 300"
- 要求：代码整洁，CSS 类名语义化
```

### SVG 增强技巧清单

| 技巧 | SVG 代码 | 效果 |
|------|---------|------|
| 渐变背景 | `<linearGradient>` | 卡片渐变填充 |
| 投影 | `<filter><feDropShadow>` | 卡片浮起感 |
| 发光 | `<filter><feGaussianBlur>` | 节点发光脉冲 |
| 纹理 | `<feTurbulence>` + `<feColorMatrix>` | 噪点纹理背景 |
| 路径动画 | `stroke-dasharray` + `stroke-dashoffset` | 连线描绘 |
| 形变 | `<animateTransform>` | 节点旋转/缩放 |
| 裁剪 | `<clipPath>` | 内容裁切显示 |

---

## 技巧 2：CSS 动画升级

### 当前方式
```css
.fade-in {
  opacity: 0;
  transform: translateY(20px);
  transition: opacity 0.6s ease, transform 0.6s ease;
}
.fade-in.visible {
  opacity: 1;
  transform: translateY(0);
}
```

### 升级为 Scroll-Driven Animations（原生）

```css
/* Chrome 115+ 原生支持，零 JS */
.hero-illustration {
  animation: hero-reveal linear;
  animation-timeline: view();
  animation-range: entry 0% entry 80%;
}

@keyframes hero-reveal {
  from { opacity: 0; transform: translateY(40px) scale(0.95); }
  to   { opacity: 1; transform: translateY(0) scale(1); }
}
```

### 交错入场增强

```css
/* 每个元素独立动画，用 animation-range 控制时序 */
.card-1 { animation-range: entry 0% entry 30%; }
.card-2 { animation-range: entry 10% entry 40%; }
.card-3 { animation-range: entry 20% entry 50%; }
```

---

## 技巧 3：引入 Lottie 动画（最小入侵）

```html
<!-- Astro 组件中 -->
<script type="module">
  import { DotLottie } from 'https://esm.sh/@lottiefiles/dotlottie-web';

  customElements.define('hero-animation', class extends HTMLElement {
    connectedCallback() {
      new DotLottie({
        canvas: this.querySelector('canvas'),
        src: '/animations/hero.lottie',
        autoplay: true,
        loop: false,
      });
      // IntersectionObserver 触发播放
      const obs = new IntersectionObserver(([e]) => {
        if (e.isIntersecting) this._lottie?.play();
      });
      obs.observe(this);
    }
  });
</script>

<hero-animation>
  <canvas width="480" height="300"></canvas>
</hero-animation>
```

---

## 技巧 4：Mermaid 嵌入产品架构图

```astro
<!-- MermaidDiagram.astro -->
<script type="module">
  import mermaid from 'https://esm.sh/mermaid';
  mermaid.initialize({ startOnLoad: true, theme: 'neutral' });
</script>
<pre class="mermaid">
graph LR
    A[📥 文件输入] --> B[🤖 Agent 处理]
    B --> C[📝 Wiki 写入]
    B --> D[📋 Journal 记录]
    C --> E[⏪ Rollback 回退]
</pre>
```

---

## 技巧 5：unDraw + AI 颜色定制

```bash
# 从 undraw 下载 SVG，修改主色
# unDraw 所有插图都可以一键改色
# https://undraw.co/illustrations?primaryColor=4CAF50
```

AI 可以帮你：
1. 挑选与产品概念匹配的插图
2. 修改 SVG 中的颜色变量匹配品牌色
3. 组合多个插图元素创建定制场景

---

## 真实 Prompt 示例

### 生成 Hero 图解

```
为 Piki 产品官网生成一个 inline SVG 的 Hero 图解：

Piki 是一个本地优先的个人知识管理系统。
用户把碎片笔记、聊天记录、截图等"丢"给 AI Agent，
Agent 自动整理成结构化的 Wiki 知识库。

视觉概念：
- 左侧：散落的碎片（便签、气泡、截图）→ 表示"输入"
- 中间：一个发光的 AI Agent 核心（齿轮/星形）→ 表示"处理"
- 右侧：整齐的 Wiki 知识树（分支节点）→ 表示"输出"
- 连接：从左到右的渐变箭头/光线

设计要求：
- viewBox="0 0 600 350"
- 磨砂玻璃卡片风格（白色半透明 + backdrop-filter）
- 配色：绿 #4CAF50 为主色，辅以蓝色 #2196F3 表示 AI
- 使用 SVG filter 做投影和发光
- 使用 CSS animation 做入场动效
- 包含 dotted grid 背景增加科技感
- 代码嵌入 Astro 组件的 <style> 中
```

### 生成 Feature 对比图

```
为 Piki 官网生成一个"传统笔记 vs Piki"的对比图解 SVG：

左侧：传统方式
- 散乱的文件夹、手动整理、格式不统一 → 红色/灰色调
- 标签：手动维护、碎片化、容易遗忘

右侧：Piki 方式
- 自动分类、结构化 Wiki、Agent 持续维护 → 绿色调
- 标签：AI 自动化、结构化、维基线持续对齐

设计要求：
- viewBox="0 0 600 300"
- 左右分区，中间分割线
- 左侧偏灰/红，右侧绿色渐变
- 卡片投影、图标用简单几何形状
- CSS 入场动画
```

---

## 文件大小控制

| 方案 | 合理上限 | 说明 |
|------|---------|------|
| 内联 SVG | < 5KB 每个 | 超过则用 `<img src>` 外链 |
| CSS 动画 | < 2KB 每个 section | 复用 keyframes |
| Lottie JSON | < 50KB 每个 | 复杂动画才用 |
| 总页面 CSS | < 15KB | 合并压缩后 |
