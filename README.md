
# 🐳 Docker Compose Template
---
## ✨ Features
- 🚀 **Quick start** - just 5 commands to running stack
- 🔒 **Security** - secrets separate from code, environment variables
- 📁 **Clean structure** - `dev`/`prod` configuration separation
- 🛠️ **Rich Makefile** - 30+ commands for management
- 📊 **Monitoring** - `PgAdmin`, `logs`, `resource` metrics
---
## 📦 Quick Start
```bash
# 1. Clone the project
git clone https://github.com/star-barsuk/docker-compose-template.git
cd docker-compose-template

# 2. Setup environment
cp .env.dev.example .env.dev
cp .env.prod.example .env.prod
# Edit .env files with your values

# 3. Start dev stack
make docker-up-dev
```
---
## 🌐 Access Services
| Service | URL | Description |
|-----------|----------------|-------|
| PgAdmin (`Dev`) | http://localhost:8080 | PostgreSQL admin panel |
| Application | Inside container | Python application |
| Database | Via PgAdmin | PostgreSQL 18.1 |
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
├── 📁 src/             # Application source code
├── ⚡ Makefile         # Command shortcuts
├── 📄 pyproject.toml   # Python dependencies
└── 🧪 .env.*.example   # Environment templates
```
---
## 🚀 Main Commands
🛠️ Development (Dev)
```bash
make docker-up-dev      # 🚀 Start dev stack
make docker-down-dev    # 🛑 Stop dev stack
make docker-logs-dev    # 📜 Show logs (follow mode)
make docker-shell-dev   # 🐚 Enter application container
```
🧹 Cleanup
```bash
make docker-clean-dev           # 🧹 Stop and remove containers+volumes (dev)
make docker-nuke-dev            # 💣 REMOVE EVERYTHING
```
📊 Monitoring
```bash
make docker-ps-dev      # 📋 List containers (dev)
make docker-stats-dev   # 📈 Resource usage
make docker-disk        # 💾 Docker disk usage
make docker-check-ports # 🔍 Check used ports
```
---
## 📋 System Requirements
| Component | Version | Notes |
|-----------|----------------|-------|
| Docker | 29.1.3+ | Client version |
| Docker Compose | v5.0.0+ | Included in Docker |
| openssl | Latest | For secret generation |

## 🖥️ For Local Development (optional)
- `Python` 3.14+
- `uv` 0.9.18+ 
- `Git` 2.51.0+
---
## License
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

© 2025 Star-Barsuk