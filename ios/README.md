# 译镜（LensTranslate）

一个 iPhone 应用：把镜头对准外文，译文实时贴在原文的位置上；也可以两个人对着说话互相翻译，或者在看英文时顺手收集生词。所有识别和翻译都在手机本地完成。

## 功能

| 模式 | 做什么 |
|---|---|
| 翻译 | 相机实时识别文字并翻译，译文覆盖在原文位置；可定格画面、切换看原文、朗读译文 |
| 学词 | 保留英文原文，只标出所选词书里的单词，显示音标和释义，一键加入生词本 |
| 对话 | 两人各按各的麦克风说话，显示原文和译文并朗读 |

生词本可以导出为 Anki 能直接导入的制表符分隔文本。

## 构建

需要 Xcode 26 和一台 iOS 18 或更高版本的 iPhone。相机和麦克风在模拟器里无法使用，要装到真机上测试。

```bash
brew install xcodegen
cd ios
xcodegen generate
open LensTranslate.xcodeproj
```

在 Xcode 里选择自己的开发团队（Signing & Capabilities），连接手机后运行。

## 词库

学词模式需要一个词库文件，仓库里不包含数据（见下方许可说明）。生成方法：

```bash
pip install openpyxl
git clone --depth 1 https://github.com/lilinji/English
python3 tools/vocab/build_vocab.py English vocab.sqlite
```

把生成的 `vocab.sqlite`（约 50 MB）用隔空投送或“文件”App 传到手机，然后在 App 的“设置 → 学词模式 → 导入词库文件”里选择它。也可以在构建前把它放进 `ios/LensTranslate/` 目录，随 App 一起打包。

词库数据来自 [English Vocabulary Vault](https://github.com/lilinji/English)，采用 CC BY-NC-SA 4.0 许可：仅限非商业使用，需署名，衍生数据须以相同许可分发。

## 语言

翻译使用系统的 Translation 框架，支持的语言由系统决定。在 macOS 26 上实测为 21 种：中文、英语、日语、韩语、印尼语、泰语、越南语、法语、德语、西班牙语、意大利语、葡萄牙语、俄语、阿拉伯语、印地语、荷兰语、波兰语、土耳其语、乌克兰语等，**不包含马来语**。首次使用某个语言对时，系统会提示下载语言包。

## 结构

- `LensCore/`：与界面无关的核心逻辑（坐标换算、词形还原、词库查询、生词本），可以在 Mac 上用 `swift test` 运行测试。
- `LensTranslate/App/`：应用状态、语言列表、主题。
- `LensTranslate/Camera/`：相机会话和预览。
- `LensTranslate/Services/`：文字识别、翻译桥接、语音识别、朗读。
- `LensTranslate/Views/`：界面。

## 已知限制

- 代码在 CI 上为 iOS 模拟器编译通过，核心逻辑有单元测试；相机、语音和翻译的实际运行效果只能在真机上验证。
- 译文按每次识别的结果整体替换，镜头移动时标签会跟着跳动，没有做逐帧的平滑跟踪。
- 对话模式使用系统的语音识别，设备支持时只在本机识别；某些语言在某些设备上可能需要联网。
