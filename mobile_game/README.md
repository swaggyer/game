# 星灯岛与回家的小龙 · v1.3.0

v1.3.0 为七个区域、标题、战斗与首领加入十首配乐，并为全部剧情提供可暂停、重听和跳过的中文旁白。详见 [音乐与剧情朗读说明](docs/V1.3音乐与剧情朗读.md)。

基于《星灯岛》故事设定与既有角色模型制作的横屏单机冒险。v1.2 加入妖怪有效命中最低四分之一最大生命、三位伙伴八方向步态、每区三个真实挑战，并重做全部主线目标，移除站位摇铃解锁。左上角双角色头像根据用户照片保真绘制，背景适配森林冒险风格。自然卡通场景、七个开放区域和双主角战斗继续保留。

v1.2.1 修复左上角血条撑高、遮挡生命值与星晶文字的问题；等级、血条、数值采用自动纵向排布，文字加大并提高对比度。新版玩法、头像与存档迁移见 [V1.2更新说明](docs/V1.2更新说明.md)。

## 立即游玩

双击 **`E:\game\StarLanternIsland\mobile_game\builds\试玩星灯岛.cmd`**。同目录的 `StarLanternIsland.exe` 与 `StarLanternIsland.pck` 必须一起保留；Windows 便携版无需安装 Godot 编辑器。启动器把存档放在 `builds\userdata`，换位置游玩时可连同该目录一起复制。

完整版压缩包：`E:\game\StarLanternIsland\星灯岛-实战闯关版-v1.2.1.zip`。解压后打开 `mobile_game\builds\试玩星灯岛.cmd`，不要直接在压缩软件中运行。旧版压缩包继续保留。

需要编辑源码时，双击 `E:\game\StarLanternIsland\mobile_game\打开手游工程.cmd`，或在 Godot 4.7.2 中导入 `E:\game\StarLanternIsland\mobile_game\project.godot`。首次打开源码请等待编辑器完成资源导入；此后本机可直接运行：

```powershell
& 'E:\Godot\Godot_v4.7.2-stable_win64.exe' --path 'E:\game\StarLanternIsland\mobile_game'
```

## 操作与通关

| 操作 | 触屏/鼠标 | 键盘 |
| --- | --- | --- |
| 移动 | 左下浮动摇杆 | WASD / 方向键 |
| 连续攻击 | 右下攻击键连续轻点 | J 连续轻按 |
| 龙术/互动 | 攻击键左上方情境键 | K |
| 切换旺仔、小馒头 | 点击左上未选中头像 | Tab |
| 区域地图 | 点击小地图或区域地图按钮 | M |
| 暂停/返回 | 右上暂停键 | Esc |

进入区域后可自由选择路线。金色标记为三个主线目标，蓝色旗标为三个区域挑战。主线包含限时穿门、攻击移动封印、短途护送、两波战斗和机关；首领目标需要先完成另外两个目标，水闸按荷叶、月牙、星星的顺序调节。全部主线目标完成后，前往区域星灯互动，继续下一组。

战斗中情境键固定为所选龙术，其他龙术在暂停菜单切换；脱战并靠近、面向目标后，按钮显示启动闯关、护送出发、推箱、转镜、开箱或关闭陷阱等具体动作。按下至松开期间锁定动作与目标。挑战倒计时内按指示完成操作，站在原地不会自动完成；失败后可重试，营地休息可以取消当前试炼。

## v1.4 安卓性能修复

首图草叶花朵改为分块网格绘制，移动端采用720逻辑高度的线性缩放与60帧目标；动作贴图与常用音乐预热，攻击/龙术在按下时起手，重复HUD更新、寻路和自动存档开销降低。沿用原签名覆盖升级，可保留存档。[修复说明与验证边界](docs/V1.4性能修复.md)。

## 已实现的系统

- **v1.2 实战挑战**：妖怪伤害在被动减免后仍至少为最大生命的 25%（向上取整）；水盾和受击保护保留。七区共新增 21 个独立关卡，涵盖限时障碍、三波战斗、踏板光栅、移动靶场和粮车护送，记录勋章与最佳时间，首次奖励经验 24、星晶 10。
- **v1.2 角色表现**：旺仔、小馒头、小龙新增 192 张八方向行走帧和 24 张静止帧，按实际移动距离播放；两位孩子有膝弯、摆臂、脚跟落地与前掌离地，小龙以四肢交替行走。左上角头像采用用户照片保真二维重绘与森林背景。
- **v1.1自然卡通渲染**：高分辨率Blender环境素材、草地与泥土材质、柔和日照和云影、动态水面与岸边泡沫；区域地图采用平滑矢量轮廓与柔化迷雾。六类机关增加石材、铁、铜、链条、火焰和水流质感。
- **v1.1挑战调整**：妖怪基础攻击提高，新游戏默认星灯探险家；旧存档的难度选择保留。完整数值对照在新版更新说明。
- **七个开放区域**：村庄广场与果园、森林环湖、原野断崖与麦田、水乡五岛、遗迹庭院、裂隙三桥、星灯岛环庭。每区可玩范围为 3400×2400，有多条环路和交叉通道；水域、房屋、岩石和墙体参与碰撞，桥梁可真实通行。小地图记录探索迷雾、目标、已发现宝箱、营地和附近妖怪。
- **可操作机关与探索**：木箱按人物站位被实际推动，需要压上金色踏板；镜台可逐次转向，光束需对准目标；水闸有明确顺序。每组主线配置四处探索宝箱和两处营地，已领取宝箱、完成目标和关闭机关会保存。营地可重置尚未解开的木箱。
- **两位不同的主角**：旺仔使用三段近战剑盾连击，第三段盾击可推退、打断普通妖怪并显露首领核心；小馒头发射有飞行时间和碰撞的星矢弹，第三段附带近身星爆打断。两人共享生命、等级和装备，未操控的孩子与小龙会寻路跟随。
- **真正的动作阶段**：两位主角共 96 张由原 Blender 模型骨骼摆姿渲染的战斗帧，覆盖四方向、三段攻击、起手/接触/跟随/收招四阶段。命中在接触阶段结算；攻击有移动限制、连段输入缓冲和收招时间。
- **八类妖怪的不同攻击**：跃击、侧向冲刺、风弹、泡影与扩散水环、根刺与挥枝、风道、直冲与旋转甲刃、移影星弹与安全扇区。巡逻、追击、绕墙寻路、攻击预警、实际命中几何和收招反击均已实现；五场首领记录阶段进度。
- **六类陷阱**：星刺地板、间歇喷焰、摆锤、三发星矢、漩涡、踩踏坍塌石板都有实际危险判定。观察范围标记与节奏，寻找旁侧拉杆可永久关闭当前关卡的机关；关闭状态存档。序章初始教学和星岛尾声保持安全。
- **成长与续玩**：三种难度、1—20 级成长、装备与五槽强化、强化全额返还、龙术解锁、红星果补给、暂停菜单和本地存档。受击后有 1 秒保护；倒下回营地恢复，保留目标、宝箱、首领阶段和装备。

当前完整变化见 [V1.2更新说明](docs/V1.2更新说明.md)。[V1实现说明](docs/V1实现说明.md) 和 [V1.1更新说明](docs/V1.1更新说明.md) 为历史版本记录；旧版站位协作与伤害断言已由当前玩法替代。

## 难度与存档

| 难度 | 生命倍率 | 敌方/陷阱伤害倍率 | 敌人起手提示 | 陷阱时钟速度 |
| --- | --- | --- | --- | --- |
| 小小守护者 | 1.3 | 0.65 | 额外延长 0.3 秒 | 0.84 倍 |
| 星灯探险家 | 1.0 | 0.85 | 基础时长 | 1.00 倍 |
| 勇敢冒险家 | 1.0 | 1.00 | 基础时长 | 1.12 倍 |

表中伤害倍率仍用于普通结算与陷阱；妖怪最终伤害另设四分之一最大生命下限。存档包含 `campaign.json`（等级、装备、主线、首领阶段）及 v3 的 `campaign.json.world.json`（区域目标、封印血量、木箱、镜台、宝箱、迷雾、营地、已关闭陷阱、区域挑战勋章和最佳时间）。写入使用临时文件替换并保留 `.bak`；每 12 秒以及关键互动、暂停等时机保存。v2 世界存档读取时保留探索内容，重置已更换玩法的当前组局部主线目标，等级与已解锁章节不变。

通过便携启动器运行时，文件在 `E:\game\StarLanternIsland\mobile_game\builds\userdata\Godot\app_userdata\星灯岛与回家的小龙`。直接运行源码时使用 Windows 默认 `%APPDATA%\Godot\app_userdata\星灯岛与回家的小龙`。

v0.1 的等级、装备和已解锁主线沿用原 `campaign.json`；旧单路线的关卡检查点不套用到新地图，新区域探索记录从对应入口建立。旧工程备份在 `E:\game\backups\StarLanternIsland-v0.1-20261104`，原 `E:\game\StarLanternIsland\星灯岛-手游开发原型-v0.1.zip` 保留。

## 源码与美术

| 路径（相对本工程） | 作用 |
| --- | --- |
| `scripts/game_main.gd` | 开放区域主流程、机关交互、技能、营地与区域存档 |
| `scripts/open_world.gd` | 七区固定布局、场景美术、真实水域/障碍、AStar 导航 |
| `scripts/hero_actions.gd` | 双角色攻击阶段、连段、星矢弹与支援动作 |
| `scripts/damage_rules.gd` | 妖怪伤害下限与独立环境伤害结算 |
| `scripts/main_trials.gd` / `scripts/challenge_director.gd` | 主线试炼、21 个区域挑战与奖励存档 |
| `scripts/locomotion.gd` / `assets/locomotion_v12` | 实际位移驱动的八方向步态与运行时清单 |
| `assets/portraits_v12` | 图一小馒头、图二旺仔的保真二维头像 |
| `scripts/enemy_director.gd` | 八类妖怪、首领阶段、预警与攻击碰撞 |
| `scripts/trap_director.gd` | 六类陷阱、计时、飞矢、关闭拉杆 |
| `scripts/area_map_v11.gd` / `scripts/map_fog.gdshader` | 矢量区域地图与柔化探索云层 |
| `scripts/landscape_renderer.gd` / `shaders` | 自然草地、泥土、水面、日照与柔影 |
| `scripts/trap_visuals.gd` | 六类机关材质与动态绘制 |
| `scripts/campaign.gd` / `scripts/mobile_ui.gd` | 成长存档与横屏触控菜单 |
| `assets/actions` / `tools/render_combat_poses.py` | 战斗帧与 Blender 重渲染脚本 |
| `data` / `tests` / `docs` | 原设定副本、验证用例、截图与日志 |

新版环境可编辑源文件位于 `assets/environment_v11/source/environment_library.blend`，生成脚本为 `tools/render_environment_v11.py`，此source目录通过 `.gdignore` 避免运行时导入。

模型源文件继续保存在 `E:\game\StarLanternIsland\source_models\characters`、`source_models\creatures` 和 `source_models\world`；设定数据来自 `E:\game\StarLanternIsland\design_web\content`。运行时使用模型渲染图，无需启动 Blender。战斗姿势重渲染命令：

```powershell
& 'E:\blender\blender.exe' --background --python 'E:\game\StarLanternIsland\mobile_game\tools\render_combat_poses.py'
```

## 已完成的验证

当前验证覆盖成长与存档、七区导航、妖怪战斗、陷阱、伤害下限、步态、全部 21 个区域挑战、主线试炼与完整 63 目标流程；具体检查数、构建哈希和截图记录见 `docs/validation.json`。另外运行主角动作与机关材质绘制专项。完整流程用例为 `tests/test_full_game_v12.gd`。

如需复查，在新开的 PowerShell 终端使用独立数据目录，避免影响试玩存档：

```powershell
$env:APPDATA = 'E:\game\StarLanternIsland\mobile_game\tests\manual-v1-data'
& 'E:\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'E:\game\StarLanternIsland\mobile_game' --script 'tests/test_full_game_v12.gd'
```

## 手机导出

已生成独立签名的 Android arm64 release APK：`builds/android/StarLanternIsland-v1.3.0-arm64.apk`，最低 Android 7.0，已校验签名、16KB 对齐、完整游戏资源与包信息。构建方法见 [Android发布说明](docs/ANDROID发布说明.md)。

iOS 采用用户选择的 Xcode 工程与未签名构建方案；完整 Xcode 工程已导出，GitHub macOS 工作流负责原生编译未签名设备 IPA，并将产物附加到仓库 Release。未签名 IPA 需要后续签名，不能直接安装到普通 iPhone；构建状态与操作见 [iOS发布说明](docs/IOS发布说明.md)。当前未进行 Android 或 iPhone 真机试玩。

参考：[Godot 触摸事件](https://docs.godotengine.org/en/stable/classes/class_inputeventscreentouch.html)、[Godot 命令行说明](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)。
