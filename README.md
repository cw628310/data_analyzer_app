# 数据分析仪

`数据分析仪` 是一个离线 Flutter APK 项目，用于分析购买情况号码文件，并根据用户输入的参考号码生成相似风格组合。

## 已实现功能

- 支持导入一个或多个 `.txt` 购买情况文件作为分析文件 A
- 支持输入参考号码，格式为 `01.02.03.04.05.06+09`
- 支持统计参考号码在文件 A 中的出现次数、概率、共现关系、相似组合和搭配数字
- 支持设置生成数量、最少保留参考红球、蓝球处理方式、相似度强度
- 支持导入一个或多个 `.txt` 文件作为组合文件 B
- 支持结合文件 A 分析结果和文件 B 数据生成相似组合
- 每组生成结果都会说明原因
- 支持复制全部结果和导出 TXT
- 全程本地运行，不需要联网

## 文件格式

软件识别类似下面的文本：

```text
双色球号码第一组红球：03,05,14,21,24,32蓝球：10
第二组红球：02,13,16,17,22,30蓝球：07
第三组红球：11,14,23,25,30,32蓝球：10
```

即使文件没有标准换行，只要包含 `红球：` 和 `蓝球：`，软件也会尝试连续解析。

## CircleCI 在线打包

项目已经包含 `.circleci/config.yml`。提交到 GitHub 或 Gitee 后，在 CircleCI 绑定仓库即可自动打包。

打包流程：

```text
提交代码
↓
CircleCI 安装 Flutter
↓
生成 Android 工程
↓
获取依赖
↓
运行 flutter analyze
↓
打包 Debug APK
↓
在 Artifacts 下载 数据分析仪-debug.apk
```

第一版默认打包 Debug APK，方便测试安装，不需要配置正式签名。

## 本地运行

如果本地已经安装 Flutter，可以运行：

```bash
flutter create --platforms=android --project-name=data_analyzer_app .
flutter pub get
flutter run
```

本地打包：

```bash
flutter build apk --debug
```
