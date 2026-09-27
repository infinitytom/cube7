# 立方-7 Cube-7（原型）

体素箱庭解谜冒险。当前版本包含区域 1「翠绿温室」的完整关卡（方块体素版），以及一个机制测试房间。
下一阶段会把体素底层迁移到 Voxel Tools 的平滑地形（雾锁王国式的破坏）。

## 运行

1. 用 Godot 4.6（官方版或 Voxel Tools 定制版都可以）打开本文件夹里的 `project.godot`。
2. 按 F5 运行。

## 操作（PS5 手柄优先，Xbox / 键鼠同样支持，界面会自动切换按键图标）

| 功能 | PS5 | Xbox | 键鼠 |
| --- | --- | --- | --- |
| 移动 | 左摇杆 | 左摇杆 | WASD |
| 镜头 | 右摇杆 | 右摇杆 | 鼠标 |
| 跳跃（仅测试房间） | ✕ | A | 空格 |
| 形态能力 | □ | X | 左键 / F |
| 抓取 / 投掷 | ○ | B | E / 右键 |
| 加速 | R2 | RT | Shift |
| 切换形态 | L1 / R1 | LB / RB | 滚轮 / Z C |
| 直选形态 | 十字键 | 十字键 | 1–5 |
| 俯视模式 | △ | Y | V |
| 回到检查点 | Create | View | R |
| 暂停 | Options | Menu | Esc |

## 形态

| 形态 | 重量 | 能力 |
| --- | --- | --- |
| 滚球 | 1.0 | 冲刺（可撞碎玻璃） |
| 钻头 | 2.5 | 按住向前钻；静止时向下钻 |
| 立方 | 3.0 | 空中重压；够重能压动压力板 |
| 磁铁 | 1.4 | 按住吸附金属墙，推向墙面往上爬 |
| 气泡 | 0.3 | 喷气上浮；能被上升气流吹起 |

## 代码结构

```
scripts/
  voxel/blocks.gd        方块类型表（颜色、谁能破坏、掉落）——调数值改这里
  voxel/voxel_world.gd   体素世界：分块网格、碰撞、破坏、砂块下落
  voxel/pickup.gd        金币/能源：自动飞入球体
  player/morph_ball.gd   主角：五种形态的物理参数与能力
  player/camera_rig.gd   第三人称镜头
  puzzles/               插槽、能量回路、压力板、气流、检查点、变形站、NOVA 对话触发
  levels/test_room.gd    测试关卡（代码搭建）
  ui/hud.gd              界面
  debug/autotest.gd      自动测试
```

## 关卡与测试

- 默认进入区域 1「翠绿温室」；加参数 `-- --level=test` 进入机制测试房间。
- 设计原则：主角默认不能跳（致敬平衡球），高低差靠坡道、弹跳垫和形态能力；往下钻只对松土有效，避免把自己困住。

```
godot --headless --path . -- --autotest              # 机制测试房间，22 项
godot --headless --path . -- --autotest=greenhouse   # 区域 1 整关测试，按设计路线走到终点
```

## 音频

`audio/` 下的音乐和音效由 `tools/synth_audio.py` 程序合成（numpy + ffmpeg）。
区域音乐分三层（底层 / 旋律 / 明亮）同步循环，由 `scripts/game/music.gd` 按游戏状态自动混音。
