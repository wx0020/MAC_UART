# MAC UART 1.0（Build 2）提审填写单

对应 macOS 版、Apple ID `6837191388`，Bundle ID 为 `com.itron.mac.uart.MAC-UART`。已核对本机归档的版本、构建号、macOS 14.0 部署目标和 Developer Tools 类别。当前资料按英语（澳大利亚）和简体中文准备。

## 1. 填写商店页面

| App Store Connect 位置 | 填写内容 |
| --- | --- |
| App 信息 → 名称 | MAC UART |
| App 信息 → 副标题 | 按语言复制对应文案中的副标题。 |
| App 信息 → 主要类别 | Developer Tools（开发者工具），与归档一致。 |
| macOS 版本 1.0 → 本地化 | 英语（澳大利亚）使用 [listing-en-AU.md](listing-en-AU.md)，添加简体中文后使用 [listing-zh-Hans.md](listing-zh-Hans.md)。逐字段复制正文。 |
| 版本 → 截图 | 使用同语言目录内的两张 JPG。建议顺序为 serial、tcp。每张 1280 × 800，分别展示文本收发和 TCP 服务端 HEX 视图。 |
| 版本 → 构建版本 | 在后台确认处理状态，选择拟送审的构建。当前上传为 1.0（2）；若补齐下述包内项目后重传，则选择新构建。 |
| 版本 → 版权 | 待填写：2026 加实际版权持有人完整名称。 |
| 定价与销售范围 | 由账号持有人确定定价、地区及发布方式。 |

截图由本版本的原生 SwiftUI 界面使用示例串口、回环地址和模拟收发记录渲染。数据仅用于展示功能，不代表实际客户设备或测试结果。

## 2. 准备两个公开网址

已确认公开支持邮箱为 **xiangw@itron.com.cn**。将 [support.html](public/support.html) 和 [privacy.html](public/privacy.html) 作为同一目录下的网页部署至你管理的网站。两页都有中文和英文内容，支持页已填写该邮箱。发布前由运营主体确认隐私说明与实际客服数据处理方式一致。

用未登录浏览器分别打开两页，验证互链及邮箱后，将各自的 HTTPS 地址填入「支持 URL」和「隐私政策 URL」。目前交付的是网页文件，线上地址待填写。营销 URL 可在有正式产品页时填写。

## 3. 审核信息

- 登录要求：本应用无需登录，不需要提供测试账号。
- 审核备注：粘贴 [review-notes.txt](review-notes.txt)。步骤使用同一台 Mac 的 Terminal 和 TCP 回环连接，可收发 PING/PONG、运行三轮定时发送并检查录制文件。
- 审核联系人姓名、电话（含国家或地区代码）、审核邮箱：待填写。公开支持邮箱已填在支持页，审核专用联系方式另行确认。
- 在准备提交的实际构建上运行一次上述步骤。已有虚拟串口测试；本资料中的 TCP 步骤是审核操作说明，尚未在本次提交的签名构建上做端到端验证。

## 4. App 隐私、年龄分级和加密

- **App 隐私**：已查看本版源码，偏好与快捷指令存于本机，收发数据发给用户选择的设备或 TCP 对端，导出和录制写入用户选择的位置。未发现开发者自有数据上报、账号、广告或分析 SDK。若实际发行构建和第三方合作方也符合这些情况，后台可按“开发者及第三方合作方不通过本 App 收集数据”作答。用户主动联系支持时提供的资料另见隐私政策。
- **年龄分级**：这是设备调试工具。根据实际功能完成问卷，由后台生成分级。应用没有内置社交信息流、浏览器或付费抽奖。
- **加密出口合规**：源码中的设备通信使用串口和普通 TCP，未发现应用实现的 TLS 会话、自有加密算法或独立加密 SDK。提交人按最终构建实际情况回答后台问卷。

## 5. 上传成功后仍须复核的包内项目

1. **隐私清单**：本机 00:10 的 1.0（2）归档未包含 `PrivacyInfo.xcprivacy`。项目使用 `UserDefaults.standard` 和 `@AppStorage` 保存本应用偏好。已附 [隐私清单草案](build-review/PrivacyInfo.xcprivacy)，其中声明本应用自身偏好所用的 UserDefaults 类别和理由 CA92.1。请复核最终构建的全部受管 API 和依赖，把清单加入主应用 target 的资源，在新归档内确认文件实际存在。单独填写后台问卷不会改变已上传的二进制包。
2. **应用内隐私政策入口**：目前源码中未找到可访问隐私政策的入口。公开网址确定后，在「帮助」或「关于」中提供链接，并验证从应用内能打开。苹果审核指南 5.1.1(i) 同时要求商店元数据和应用内提供入口。
3. 如为以上项目更新应用，市场版本可保留 1.0，使用新的构建号归档并上传；在商店版本页选择补齐后的构建。资料生成过程未改变 Build 2。

## Apple 官方参考

- [版本字段和支持网址](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)
- [截图尺寸](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [App 隐私信息](https://developer.apple.com/app-store/app-privacy-details/)
- [App 审核指南](https://developer.apple.com/app-store/review/guidelines/)
- [受管 API 使用理由](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [年龄分级问卷](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating)
- [加密出口合规](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)
