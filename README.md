# CycloneTracker — 全球热带气旋地图

一个基于 **SwiftUI + iOS 26 MapKit** 的全球热带气旋追踪 App,可在地图上查看当前活跃的全球热带气旋与历史热带气旋,展示中心气压、最大风速、等级与位置。

## 数据来源

| 数据 | 来源 | 接口 |
| --- | --- | --- |
| 大西洋/东北太平洋活跃气旋 | NHC (National Hurricane Center) | `https://www.nhc.noaa.gov/CurrentStorms.json` |
| NHC 气旋路径与预报 | NHC ATCF A-deck | `https://ftp.nhc.noaa.gov/atcf/aid_public/` (gzip) |
| 西北太平洋/印度洋/南半球气旋 | JTWC (Joint Typhoon Warning Center) | NHC 托管的 JTWC A-deck + IBTrACS 实时合并的 USA(JTWC) 列 |
| 历史最佳路径 (1851 至今) | IBTrACS v04r01 (NOAA NCEI) | `ibtracs.ACTIVE` / `ibtracs.last3years` / 分海盆 `ibtracs.{BASIN}.list` CSV |

## 功能

- **实时模式**: 全球活跃气旋(含 NHC 5 日预报路径虚线、JTWC 各海盆气旋)
- **历史模式**: 按年份(1851–今)与海盆查询 IBTrACS 最佳路径,按巅峰强度着色
- **气旋详情**: 中心气压(hPa)、最大风速(kt / km/h / m/s)、等级(Saffir-Simpson / JTWC)、经纬度位置与反向地理编码地点
- iOS 26 MapKit:新 `MapFeature` 选择 API(`MapSelectable`)、路径线、指南针/比例尺/定位控件

## 构建

项目使用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 管理,无需提交 `.xcodeproj`:

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project CycloneTracker.xcodeproj -scheme CycloneTracker \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

要求: Xcode 26 / iOS 26 SDK。GitHub Actions(`.github/workflows/ios.yml`)在 `macos-15` runner 上自动编译验证。

## 免责声明

本 App 仅用于信息展示与学习,不作为防灾决策依据。请以各国官方气象机构发布为准。

- NHC: <https://www.nhc.noaa.gov>
- JTWC: <https://www.metoc.navy.mil/jtwc/jtwc.html>
- IBTrACS: <https://www.ncei.noaa.gov/products/international-best-track-archive>
