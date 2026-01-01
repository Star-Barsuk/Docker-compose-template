
# 🐳 Docker Compose Template
---
## ✨ Features
- 🚀 **Quick start** - just 3 steps to running stack
- 🔒 **Security** - secrets separate from code, environment variables
- 📁 **Clean structure** - `dev`/`prod`/`...` configuration separation
- 🛠️ **Rich Makefile** - simple commands for management
- 📊 **Monitoring** - `status`, `logs`, `resource` metrics
---
## 📦 Quick Start
```bash
# 1. Clone the project
git clone https://github.com/star-barsuk/docker-compose-template.git
cd docker-compose-template

# 2. Setup environment
cp envs/.env.dev.example envs/.env.dev
# Edit .env files with your values

# 3. Start dev stack
make up
```
---
## 🌐 Access Services
### Example for `dev` stack
| Service | URL | Description |
|-----------|----------------|-------|
| PgAdmin | http://localhost:8080 | PostgreSQL admin panel |
| Application | Inside container | Python application |
| Database | Via PgAdmin or Application container| PostgreSQL 18.1 |
---
## 🗂️ Project Structure
```
.
├── 📁 docker/                     # Docker configuration
│   ├── 🔐 secrets/                # Password files
│   ├── 🐳 docker-compose.yml      # Base configuration
│   ├── 🛠️ docker-compose.dev.yml  # Development overrides
│   ├── 🚀 docker-compose.prod.yml # Production overrides
│   └── 📦 Dockerfile              # App container definition
├── 📁 envs/                       # Environment configurations
│   ├── .env.dev                   # Development environment
│   └── .env.prod                  # Production environment
├── 📁 src/                        # Application source code
│   └── main.py                    # Main application file
├── ⚡ Makefile                    # Command shortcuts
├── 📄 .active-env                # Current active environment
└── 📄 README.md                  # This file
```
---
## 🚀 Main Commands
🛠️ Development (Dev)
```bash
make env-dev          # 🔄 Switch to dev environment
make up              # 🚀 Start stack
make logs            # 📜 Show logs
make stop            # 🛑 Stop stack
make shell           # 🐚 Enter application container
```
🧹 Cleanup
```bash
make clean           # 🧹 Stop and remove containers
make clean-all       # 🧹 Remove all resources (except containers)
make nuke            # 💣 COMPLETE DESTRUCTION
```
📊 Monitoring
```bash
make ps              # 📋 List containers
make stats           # 📈 Resource usage
make disk            # 💾 Docker disk usage
make ports           # 🔍 Check used ports
make check-ports     # 🔍 Check busy ports
```
---
## 📋 System Requirements
| Component | Version | Notes |
|-----------|----------------|-------|
| Docker | 29.1.3+ | Client version |
| Docker Compose | v5.0.0+ | Included in Docker |
| GNU Make | 4.4.1+ | For command shortcuts |
| openssl | Latest | For secret generation |

## 🖥️ For Local Development (optional)
- `Python` 3.14+
- `uv` 0.9.18+
- `Git` 2.51.0+
---
## License
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

© 2026 Star-Barsuk
