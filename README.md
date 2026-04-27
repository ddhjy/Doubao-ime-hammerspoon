# Doubao IME Hammerspoon

把豆包输入法留给它最有价值的部分：免费、好用的语音输入。  
把你真正顺手的输入法，继续留作主输入法。

这个项目提供一份 [Hammerspoon](https://www.hammerspoon.org/) 配置和一个一键安装脚本，用来在 macOS 上自动处理：

![按一下 Fn，直接用豆包语音输入](./assets/doubao-fn-voice-message.png)

- 切换到豆包输入法
- 唤起豆包语音输入
- 在操作结束后切回原输入法
- 让日常输入法切换只在你的中文输入法和英文键盘之间进行，不把豆包放进轮换

目标很直接：不把豆包输入法当主输入法用，但把它当成主力语音输入工具来用。

## 为什么做这个项目

豆包输入法的 macOS 版本目前有一个很明显的矛盾：

- 它的常规输入法能力偏弱，不太适合当主输入法。
- 它的语音识别能力却不错，而且免费，单独拿来做语音输入很有价值。
- 但官方的产品形态更偏向“占住输入法入口”，导致日常使用上必须反复切换，体验并不顺。

“点一下 Fn，立刻开始豆包语音输入；说完再点一下 Fn，回到原来的输入法”

## 它做了什么

仓库内有两个核心文件：

- [install-remote.sh](./install-remote.sh)：一行命令安装入口
- [install.sh](./install.sh)：安装脚本
- [init.lua](./init.lua)：Hammerspoon 配置

安装脚本会：

- 使用 `brew install --cask hammerspoon` 安装 Hammerspoon
- 把仓库里的 `init.lua` 复制到 `~/.hammerspoon/init.lua`
- 如果目标位置已有配置：
  - 内容相同则跳过
  - 内容不同则中文询问是否替换
  - 传入 `--force` 时直接覆盖
- 在覆盖前自动备份旧配置

## 一行命令安装

直接复制下面这条命令到终端执行：

```bash
curl -fsSL https://raw.githubusercontent.com/ddhjy/Doubao-ime-hammerspoon/main/install-remote.sh | bash
```

如果你明确要覆盖现有的 `~/.hammerspoon/init.lua`，可以用：

```bash
curl -fsSL https://raw.githubusercontent.com/ddhjy/Doubao-ime-hammerspoon/main/install-remote.sh | bash -s -- --force
```

这条命令会：

- 下载本仓库的安装包到临时目录
- 自动执行安装脚本
- 安装 Hammerspoon
- 复制 `init.lua` 到 `~/.hammerspoon/init.lua`

## 从仓库安装

如果你更希望先把仓库拉到本地，再手动执行安装脚本，也可以这样做：

```bash
git clone https://github.com/ddhjy/Doubao-ime-hammerspoon.git
cd Doubao-ime-hammerspoon
chmod +x ./install.sh
./install.sh
```

如果你明确要覆盖现有的 `~/.hammerspoon/init.lua`，可以用：

```bash
./install.sh --force
```

## 安装后怎么用

1. 打开 Hammerspoon。
2. 第一次运行时，为 Hammerspoon 授予 macOS 的“辅助功能”权限。
3. 在 Hammerspoon 菜单栏图标中点击 `Reload Config`。
4. 轻按一次 `Fn` 键。
5. 脚本会自动切换到豆包输入法，并通过“左 Option 双击”触发豆包语音输入。
6. 说完后再轻按一次 `Fn` 键，脚本会结束豆包语音输入，并恢复你原本的输入法。
7. 日常切换输入法时，按 `Ctrl+Space` 只会在中文输入法和英文键盘之间切换，不会切到豆包。

## 当前默认行为

当前 [init.lua](./init.lua) 的逻辑是：

- 监听单独轻按 `Fn`
- 记录当前输入法
- 切换到豆包输入法
- 等待豆包输入法生效
- 用 `flagsChanged` 事件模拟“双击左侧 Option”，触发豆包语音输入
- 再次轻按 `Fn` 时，再次双击左侧 `Option` 结束语音输入
- 延迟恢复到之前的输入法
- 监听 `Ctrl+Space`，只在 `Squirrel - Simplified` 和 `U.S.` 之间切换；如果当前是豆包，则切回 `U.S.`

这里故意不使用普通的 `keyDown` / `keyUp` 来模拟 `Option`。豆包语音快捷键对纯修饰键事件更敏感，用 `flagsChanged` 更接近真实按键，稳定性更好。

## 适合谁

- 不想把豆包输入法设成主输入法
- 又想高频使用它的免费语音输入
- 希望整个过程尽量像“按一个键就开说”
- 不想每次都手动切换输入法、再切回来

## 注意事项

- 只支持 macOS。
- 需要你已经安装豆包输入法。
- 需要 Hammerspoon 获得“辅助功能”权限，否则无法模拟按键。
- 豆包输入法内的语音快捷键需要保持为 `Option`。
- 如果轻按 `Fn` 时同时触发了 macOS 自带听写，请检查 Hammerspoon 的“辅助功能”权限，或在系统设置里调整 macOS 听写快捷键。
- 默认中文输入法写的是 `Squirrel - Simplified`，英文键盘写的是 `U.S.`；如果你使用别的中文输入法，需要修改 [init.lua](./init.lua) 里的对应配置。
- 安装脚本不会自动合并你原有的 Hammerspoon 配置，只会替换或保留现有 `~/.hammerspoon/init.lua`。
- 如果你已有自己的 Hammerspoon 配置，建议先看清提示；脚本在覆盖前会自动备份。

## 输入法 ID

当前配置里默认使用这个豆包输入法 ID：

```lua
local TARGET_INPUT_SOURCE_ID = "com.bytedance.inputmethod.doubaoime.pinyin"
local TARGET_INPUT_METHOD = "豆包输入法"
local NORMAL_CHINESE_INPUT_METHOD = "Squirrel - Simplified"
local NORMAL_ENGLISH_KEYBOARD_LAYOUT = "U.S."
```

如果你机器上的输入法 ID、显示名称或日常输入法名称不一致，需要手动修改 [init.lua](./init.lua)，然后在 Hammerspoon 中重新加载配置。

## 可以继续自定义的地方

你可以按自己的习惯继续改：

- 触发按键
- `Ctrl+Space` 轮换的中文输入法和英文键盘名称
- 切换到豆包后触发语音的等待时间
- 双击 `Option` 的按下时间和间隔
- 恢复原输入法的延迟
- 与你现有 Hammerspoon 配置的整合方式
