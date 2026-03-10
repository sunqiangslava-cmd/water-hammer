# 水锤计算示例程序

这是一个轻量级的 Python 水锤（Water Hammer）模拟脚本，适合用于教学、参数敏感性分析和快速估算。

## 模型说明

- 一维管道瞬变模型（简化特征线更新）
- 上游为恒定水头水库边界
- 下游阀门按线性规律关闭
- 默认仅在初始工况中考虑沿程损失（Darcy 摩阻）

> 说明：该程序用于工程前期估算，不替代高精度商业瞬态软件。

## 运行方式

```bash
python3 water_hammer.py
```

可选参数示例：

```bash
python3 water_hammer.py \
  --length 1500 \
  --diameter 0.6 \
  --wave-speed 1100 \
  --initial-discharge 0.25 \
  --valve-close-time 1.5 \
  --total-time 8 \
  --segments 60 \
  --output-csv result.csv
```

## 输出

- 终端输出：峰值水头、最小水头、Joukowsky 估算值
- CSV 文件字段：
  - `time_s`
  - `downstream_head_m`
  - `downstream_discharge_m3s`
  - `min_head_m`
  - `max_head_m`

## 下一步可扩展

- 加入准稳态/非稳态摩阻项
- 增加阀门特性曲线（非线性开度-流量）
- 加入气穴判别与蒸汽压限制
- 增加 matplotlib 绘图功能
