# 纸娃娃零件出图清单（mode=generic）

## 对齐铁律（决定能不能拼上）
1. **先单独生成 `face/…` 底脸并定稿**，它定义了头位与构图；
2. 其余 hair/eyes/cloth 一律**以该底脸为图生图/垫图（锁同一 seed、同尺寸、同构图）**，只用提示词或局部重绘换对应部位；
3. 全部 **512×512、头居中、透明背景 PNG**，画布尺寸一致。
4. Midjourney 用 `--cref <底脸图> --seed <固定>`；SD 用 ControlNet(lineart/openpose) 锁构图 + inpaint 换部位。
5. 未放的性别版会自动回退通用版，可先做通用 20 张再逐件补。

## 通用风格后缀（每条末尾都接）
```
Chinese xianxia cultivation game character portrait, front-facing centered bust, soft cel-shaded illustration, clean thick outlines, gentle rim light, isolated on transparent background PNG, same head position and scale across the whole set, high detail, no text, no watermark
```
## 负向词
```
photorealistic, 3d, text, watermark, blurry, extra limbs, gore, horror, different head size, off-center
```

## 逐件提示词
### face/1.png
- 中文：正面居中胸像，一张鹅蛋脸的底脸，中性平静表情，五官清晰，肤色自然，含颈部与少量肩
- EN:
```
base front-facing bust portrait head: oval soft face, neutral calm expression, clear features, natural skin, neck and a bit of shoulder. Chinese xianxia cultivation game character portrait, front-facing centered bust, soft cel-shaded illustration, clean thick outlines, gentle rim light, isolated on transparent background PNG, same head position and scale across the whole set, high detail, no text, no watermark
```

### face/2.png
- 中文：正面居中胸像，一张剑客脸的底脸，中性平静表情，五官清晰，肤色自然，含颈部与少量肩
- EN:
```
base front-facing bust portrait head: sharp angular swordsman face, keen brows, neutral calm expression, clear features, natural skin, neck and a bit of shoulder. Chinese xianxia cultivation game character portrait, front-facing centered bust, soft cel-shaded illustration, clean thick outlines, gentle rim light, isolated on transparent background PNG, same head position and scale across the whole set, high detail, no text, no watermark
```

### face/3.png
- 中文：正面居中胸像，一张圆脸的底脸，中性平静表情，五官清晰，肤色自然，含颈部与少量肩
- EN:
```
base front-facing bust portrait head: round friendly face, neutral calm expression, clear features, natural skin, neck and a bit of shoulder. Chinese xianxia cultivation game character portrait, front-facing centered bust, soft cel-shaded illustration, clean thick outlines, gentle rim light, isolated on transparent background PNG, same head position and scale across the whole set, high detail, no text, no watermark
```

### face/4.png
- 中文：正面居中胸像，一张清瘦面的底脸，中性平静表情，五官清晰，肤色自然，含颈部与少量肩
- EN:
```
base front-facing bust portrait head: lean long face, neutral calm expression, clear features, natural skin, neck and a bit of shoulder. Chinese xianxia cultivation game character portrait, front-facing centered bust, soft cel-shaded illustration, clean thick outlines, gentle rim light, isolated on transparent background PNG, same head position and scale across the whole set, high detail, no text, no watermark
```

### face/5.png
- 中文：正面居中胸像，一张丰润面的底脸，中性平静表情，五官清晰，肤色自然，含颈部与少量肩
- EN:
```
base front-facing bust portrait head: full plump face, neutral calm expression, clear features, natural skin, neck and a bit of shoulder. Chinese xianxia cultivation game character portrait, front-facing centered bust, soft cel-shaded illustration, clean thick outlines, gentle rim light, isolated on transparent background PNG, same head position and scale across the whole set, high detail, no text, no watermark
```

### hair/1.png
- 中文：以标准正脸底图为准，只绘制【高马尾】发型，头顶与两侧，脸部位置与大小完全不变，其余全透明
- EN:
```
hair layer only: high ponytail, sitting on the SAME standard head template, face untouched, everything else transparent. Chinese xianxia cultivation game character portrait, front-facing centered bust, soft cel-shaded illustration, clean thick outlines, gentle rim light, isolated on transparent background PNG, same head position and scale across the whole set, high detail, no text, no watermark
```

### hair/2.png
- 中文：以标准正脸底图为准，只绘制【垂鬓】发型，头顶与两侧，脸部位置与大小完全不变，其余全透明
- EN:
```
hair layer only: loose side-locks, sitting on the SAME standard head template, face untouched, everything else transparent. Chinese xianxia cultivation game character portrait, front-facing centered bust, soft cel-shaded illustration, clean thick outlines, gentle rim light, isolated on transparent background PNG, same head position and scale across the whole set, high detail, no text, no watermark
```

### hair/3.png
- 中文：以标准正脸底图为准，只绘制【束发】发型，头顶与两侧，脸部位置与大小完全不变，其余全透明
- EN:
```
hair layer only: tied-up topknot, sitting on the SAME standard head template, face untouched, everything else transparent. Chinese xianxia cultivation game character portrait, front-facing centered bust, soft cel-shaded illustration, clean thick outlines, gentle rim light, isolated on transparent background PNG, same head position and scale across the whole set, high detail, no text, no watermark
```

### hair/4.png
- 中文：以标准正脸底图为准，只绘制【披发】发型，头顶与两侧，脸部位置与大小完全不变，其余全透明
- EN:
```
hair layer only: long flowing loose hair, sitting on the SAME standard head template, face untouched, everything else transparent. Chinese xianxia cultivation game character portrait, front-facing centered bust, soft cel-shaded illustration, clean thick outlines, gentle rim light, isolated on transparent background PNG, same head position and scale across the whole set, high detail, no text, no watermark
```

### hair/5.png
- 中文：以标准正脸底图为准，只绘制【双丫髻】发型，头顶与两侧，脸部位置与大小完全不变，其余全透明
- EN:
```
hair layer only: twin buns, sitting on the SAME standard head template, face untouched, everything else transparent. Chinese xianxia cultivation game character portrait, front-facing centered bust, soft cel-shaded illustration, clean thick outlines, gentle rim light, isolated on transparent background PNG, same head position and scale across the whole set, high detail, no text, no watermark
```

### eyes/1.png
- 中文：透明底，仅绘制一双【琥珀瞳】，双眼居中落在标准眼位线上，位置严格统一
- EN:
```
eyes layer only, transparent bg: amber eyes, positioned on the fixed standard eye line. Chinese xianxia cultivation game character portrait, front-facing centered bust, soft cel-shaded illustration, clean thick outlines, gentle rim light, isolated on transparent background PNG, same head position and scale across the whole set, high detail, no text, no watermark
```

### eyes/2.png
- 中文：透明底，仅绘制一双【墨瞳】，双眼居中落在标准眼位线上，位置严格统一
- EN:
```
eyes layer only, transparent bg: ink-black eyes, positioned on the fixed standard eye line. Chinese xianxia cultivation game character portrait, front-facing centered bust, soft cel-shaded illustration, clean thick outlines, gentle rim light, isolated on transparent background PNG, same head position and scale across the whole set, high detail, no text, no watermark
```

### eyes/3.png
- 中文：透明底，仅绘制一双【浅褐瞳】，双眼居中落在标准眼位线上，位置严格统一
- EN:
```
eyes layer only, transparent bg: light-brown eyes, positioned on the fixed standard eye line. Chinese xianxia cultivation game character portrait, front-facing centered bust, soft cel-shaded illustration, clean thick outlines, gentle rim light, isolated on transparent background PNG, same head position and scale across the whole set, high detail, no text, no watermark
```

### eyes/4.png
- 中文：透明底，仅绘制一双【灰蓝瞳】，双眼居中落在标准眼位线上，位置严格统一
- EN:
```
eyes layer only, transparent bg: grey-blue eyes, positioned on the fixed standard eye line. Chinese xianxia cultivation game character portrait, front-facing centered bust, soft cel-shaded illustration, clean thick outlines, gentle rim light, isolated on transparent background PNG, same head position and scale across the whole set, high detail, no text, no watermark
```

### eyes/5.png
- 中文：透明底，仅绘制一双【绯瞳】，双眼居中落在标准眼位线上，位置严格统一
- EN:
```
eyes layer only, transparent bg: crimson eyes, positioned on the fixed standard eye line. Chinese xianxia cultivation game character portrait, front-facing centered bust, soft cel-shaded illustration, clean thick outlines, gentle rim light, isolated on transparent background PNG, same head position and scale across the whole set, high detail, no text, no watermark
```

### cloth/1.png
- 中文：透明底，仅绘制【靛青布衣】的肩颈与领口，向上衔接下巴，其余全透明
- EN:
```
clothing/shoulders layer only, transparent bg: indigo coarse cloth robe, collar under the chin, rest transparent. Chinese xianxia cultivation game character portrait, front-facing centered bust, soft cel-shaded illustration, clean thick outlines, gentle rim light, isolated on transparent background PNG, same head position and scale across the whole set, high detail, no text, no watermark
```

### cloth/2.png
- 中文：透明底，仅绘制【月白衫】的肩颈与领口，向上衔接下巴，其余全透明
- EN:
```
clothing/shoulders layer only, transparent bg: pale moon-white robe, collar under the chin, rest transparent. Chinese xianxia cultivation game character portrait, front-facing centered bust, soft cel-shaded illustration, clean thick outlines, gentle rim light, isolated on transparent background PNG, same head position and scale across the whole set, high detail, no text, no watermark
```

### cloth/3.png
- 中文：透明底，仅绘制【玄色劲装】的肩颈与领口，向上衔接下巴，其余全透明
- EN:
```
clothing/shoulders layer only, transparent bg: black fitted martial garb, collar under the chin, rest transparent. Chinese xianxia cultivation game character portrait, front-facing centered bust, soft cel-shaded illustration, clean thick outlines, gentle rim light, isolated on transparent background PNG, same head position and scale across the whole set, high detail, no text, no watermark
```

### cloth/4.png
- 中文：透明底，仅绘制【藕荷襦裙】的肩颈与领口，向上衔接下巴，其余全透明
- EN:
```
clothing/shoulders layer only, transparent bg: lotus-root pink ruqun dress, collar under the chin, rest transparent. Chinese xianxia cultivation game character portrait, front-facing centered bust, soft cel-shaded illustration, clean thick outlines, gentle rim light, isolated on transparent background PNG, same head position and scale across the whole set, high detail, no text, no watermark
```

### cloth/5.png
- 中文：透明底，仅绘制【灰褐短打】的肩颈与领口，向上衔接下巴，其余全透明
- EN:
```
clothing/shoulders layer only, transparent bg: grey-brown short working jacket, collar under the chin, rest transparent. Chinese xianxia cultivation game character portrait, front-facing centered bust, soft cel-shaded illustration, clean thick outlines, gentle rim light, isolated on transparent background PNG, same head position and scale across the whole set, high detail, no text, no watermark
```

