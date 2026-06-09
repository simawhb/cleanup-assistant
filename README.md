# 驷马C盘清理助手

智能C盘清理工具，支持 Web 界面操作、Token 鉴权、定时清理。

## 功能

- 一键扫描C盘可清理文件
- 支持分类清理：临时文件、开发缓存、浏览器缓存、系统日志等
- 内存清理（普通/强力模式）
- 大文件扫描
- Web UI 界面，支持远程访问
- Token 鉴权保护
- PowerShell 脚本驱动，安全可控

## 快速开始

\\ash
# 安装依赖
pip install -r requirements.txt

# 启动服务
set CLEAN_HOST=127.0.0.1
set CLEAN_PORT=8000
set CLEAN_TOKEN=你的密码
set CLEAN_OPEN_FOLDER=0
python server.py
\
浏览器打开 http://127.0.0.1:8000

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| CLEAN_HOST | 0.0.0.0 | 监听地址 |
| CLEAN_PORT | 5050 | 监听端口 |
| CLEAN_TOKEN | (空) | 访问密码，为空则不鉴权 |
| CLEAN_OPEN_FOLDER | 0 | 是否启用远程打开文件夹 |

## API 接口

| 接口 | 方法 | 说明 |
|------|------|------|
| /api/health | GET | 健康检查 |
| /api/disk | GET | 磁盘信息 |
| /api/scan | GET | 扫描可清理文件 |
| /api/clean | POST | 执行清理 |
| /api/largefiles | GET | 大文件扫描 |
| /api/memory | GET | 内存使用情况 |
| /api/memory-clean | POST | 内存清理 |

## 项目结构

\cleanup-assistant/
├── server.py              # Web 服务主文件
├── template.html          # 前端页面
├── cleanup-cache.ps1      # 清理脚本
├── scan-largefiles.ps1    # 大文件扫描
├── clean-memory.ps1       # 内存清理
├── requirements.txt       # Python 依赖
├── 启动.bat               # Windows 启动脚本
└── README.md
\
## 安全特性

- Token 鉴权：所有 API 接口需要 Bearer Token
- open-folder 默认禁用
- 路径白名单限制
- PowerShell 执行策略保护

## 许可证

MIT License
