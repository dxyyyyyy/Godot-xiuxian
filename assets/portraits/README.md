# 捏脸部件库（CharaGraphicMaker → 纸娃娃分层叠绘）

本目录的部件 PNG 与 `catalog.json` 由 **`import_chara_parts.py`** 从
`E:\Game\CharaGraphicMaker\角色图形合成器\Graphics\` 的 **脸C(青年男)/脸D(青年女)** 套件生成，
**不要手工往槽位目录里塞图**——重跑脚本会清空重建（黑名单/清洗规则改脚本顶部）。

```
python import_chara_parts.py            # 全量重导(部件 + catalog.json)
python import_chara_parts.py --preview  # 只重出校验图(E:\Game\CharaGraphicMaker\_import_preview\)
```

## 数据流

- `catalog.json`：`{"male"/"female": {槽位: [{id,name,n,back,back_only,color,skin,base?,src}]}}`。
  `id`=原文件名(唯一键，appearance 字典里存它)，`name`=清洗后中文显示名，`n`=文件序号(1 基)，
  `back`=有同名 `$` 背面件，`back_only`=仅背面件，`color`=发色标签(前后发同色配对用)，
  `skin`=肤色标签(耳朵随脸型肤色自动换同形件)，`base`=耳朵同形归组键。
- 运行时单一数据源：`sim/NpcGenerator.gd` 的目录 API(`options/entry/default_id/resolve_look/random_look/layer_paths`)，
  `scripts/portrait.gd` 叠绘、`scripts/apps/app_face.gd` 捏脸工坊都走它。
- appearance 字典：`{gender, face, brows, eyes, mouth, ears, hair_front, hair_back, cloth, aura}`；
  存档只存参数不存图。旧版值(鹅蛋脸/高马尾…)与缺槽自动落该性别默认件；当前无可空槽。

## 槽位与文件命名

`<slot>/<序号>m.png`(男·脸C) / `<序号>f.png`(女·脸D)，背面件加 `_back` 后缀：

| 槽位 | 素材分类 | 叠绘深度(底→顶) | 背面层深度 |
|---|---|---|---|
| face | 基础层 | 1 | — |
| cloth | 服装 | 3 | — |
| hair_back | 后发 | 6 | 0(垫脸后) |
| ears | 耳朵(固定默认人耳, 不作选择; 肤色随脸型自动配对) | 7 | — |
| eyes | 眼睛 | 9 | 8 |
| brows | 眉毛 | 10 | — |
| mouth | 嘴巴 | 10 | — |
| hair_front | 前发 | 12 | 0 |

> 「底层装饰」(decor) 与「饰品」(acc) 槽、以及精灵/兽/龙/狗等幻想耳已按需求移除;
> 老存档残留的 `decor/acc` 键会被忽略。耳朵固定为默认人耳(肤色随脸型自动配对),不作选择。

深度与素材 `Setting.txt` 的图层/第三参数实测一致(`$` 同名图按第三参数垫层)。
`aura` 不出图，作头像背景色底(五色见 portrait.gd)。

## 发色/瞳色调色(recolor.gdshader)

- appearance 另有 4 个调色键:`hair_hue`(0-359°)/`hair_sat`(0-200%)/`eye_hue`/`eye_sat`,
  缺省 identity(0/100) = 素材原色,老存档天然兼容。
- 运行时 canvas_item shader 做 HSV 色相旋转+彩度缩放(亮度不动),数学等价原版 GraphicMaker 的
  色相·彩度调整;黑描边/白高光饱和度≈0 不受影响。
- 挂材质范围:发色联动 `hair_front/hair_back/brows`(素材 `連動パーツ:前发,后发,眉毛` 组,含背面件),
  瞳色作用于 `eyes`;identity 时不挂材质,零开销。材质按 (色相,彩度) 静态缓存共享。
- 捏脸工坊的滑杆在 `app_face.gd`;NPC 随机与「随机」按钮按权重掷色(五成原色、彩度收敛)。

## 加新套件/新部件

1. 往脚本 `KIT_M/KIT_F` 或 `SLOT_MAP` 加映射(如接入脸E~H 做中老年 NPC)；
2. 黑名单 `BLACKLIST` 排除跑题件(骷髅/宇航服/电动装甲等)；
3. 仙侠古风清洗 `STYLE_BLACKLIST`(现仅作用于 cloth 槽)：两轮严选已删现代/西式/科幻服饰与
   欧式甲胄(板甲/锁子甲/骑士盔)、蒙面紧身衣、和西式立领裙装等;和服类因交领/广袖长袍剪影
   **保留但经 `NAME_OVERRIDES` 改显示名**(和服→交领袍/广袖袍、打底衫→中衣),id 不变;
4. 重跑脚本 → catalog 与部件目录自动重建；序号会重排，appearance 存的是 `id` 不受影响
   (但 npcs.json 定妆引用的是 id, 删件时需同步换件)。

> 没有放任何零件时，游戏自动回退成占位圆头像，不会报错或空白。
