# Custom production deployment

这个目录是我们自己的生产部署层，独立于原作者的 `deploy/` 目录，目的是降低同步上游代码时的冲突。

## 分支规则

- `main`：只同步原作者上游，不放自定义修改。
- `custom/main`：自定义开发与部署配置。
- `custom/prod`：生产分支，只接收确认可上线的 `custom/main` 变更。
- GitHub Actions 只允许由 `custom/prod` 触发生产部署。

自定义分支中的 `backend-ci.yml` 和 `security-scan.yml` 也只响应 `custom/prod` 的 push，或目标为 `custom/prod` 的 pull request。推送 `custom/main` 不运行这些工作流。

上游 `main` 保留原作者文件，因此直接推送它时仍可能遵循原作者的 Action 规则。若某次只是在 GitHub 上同步上游且明确不需要检查，可让该次同步提交信息包含 `[skip ci]`。包含应用变更的 `custom/prod` 最新提交不得带 `[skip ci]`，否则生产部署也会被跳过；仅修改 CI 配置时可以有意使用。

## 文件职责

- `compose.infra.yml`：PostgreSQL、Redis 和私有 Docker 网络。长期运行，不由自动部署停止或删除。
- `compose.app.yml`：Sub2API 应用。GitHub Actions 只能管理这一层。
- `compose.edge.yml`：Docker Nginx 和 Certbot。长期运行，不由应用 Action 管理。
- `compose.runner.yml`：专用生产 GitHub Actions Runner，以 Docker 容器运行。
- `nginx/`：Nginx HTTP/HTTPS 模板和证书申请说明。
- `runner/`：Runner 镜像、首次注册和日常启动脚本。
- `env.example`：服务器环境变量模板，不包含真实密钥。

所有持久化数据默认位于 `/srv/sub2api`，不放在 Runner 工作目录：

```text
/srv/sub2api/
├── app/          Sub2API 运行数据和日志
├── postgres/     PostgreSQL 数据
├── redis/        Redis AOF/RDB 数据
├── backups/      数据库备份
├── certbot/      Let's Encrypt 证书和 ACME 文件
├── runner/       Runner 注册状态和工作目录
└── config/
    ├── prod.env  生产密钥，权限 600，不进入 Git
    └── nginx.conf  当前生效的 Nginx 配置
```

## 首次部署顺序

1. 在服务器创建持久化目录：

   ```bash
   sudo install -d -m 0750 /srv/sub2api/{app,postgres,redis,backups,config}
   sudo chown -R "$USER":"$USER" /srv/sub2api
   ```

2. 创建生产配置：

   ```bash
   cp ops/custom-prod/env.example /srv/sub2api/config/prod.env
   chmod 600 /srv/sub2api/config/prod.env
   nano /srv/sub2api/config/prod.env
   ```

   密钥可以这样生成：

   ```bash
   openssl rand -hex 32
   ```

   PostgreSQL、Redis、管理员、JWT 和 TOTP 必须使用不同的固定密钥。部署更新时不得重新生成。

3. 启动长期基础设施：

   ```bash
   docker compose \
     --env-file /srv/sub2api/config/prod.env \
     -f ops/custom-prod/compose.infra.yml \
     up -d
   ```

4. PostgreSQL 和 Redis 都健康后，首次启动应用：

   ```bash
   docker compose \
     --env-file /srv/sub2api/config/prod.env \
     -f ops/custom-prod/compose.app.yml \
     up -d
   ```

5. 应用同时加入 `sub2api-backend` 私有网络，并只在宿主机监听 `127.0.0.1:8080`。按照 `nginx/README.md` 启动 Docker Nginx 和 HTTPS；PostgreSQL 和 Redis 不映射宿主机端口。

## Docker Runner 首次注册

Runner 使用 GitHub 官方发布的 Linux x64 压缩包构建，构建时强制校验 SHA-256。宿主机不安装 Runner、Git、Node 或 Compose；仅保留 Docker 与 `/srv/sub2api/runner` 持久化状态。

1. 在 GitHub 仓库进入 **Settings → Actions → Runners → New self-hosted runner**，选择 Linux x64，页面保持打开。
2. 在服务器构建镜像：

   ```bash
   cd /opt/sub2api/repo
   bash ops/custom-prod/runner/start.sh
   ```

   尚未注册时该脚本只构建镜像，不会启动反复退出的容器。

3. 执行安全注册脚本，并在隐藏提示中只粘贴 GitHub 页面 `--token` 后面的值：

   ```bash
   cd /opt/sub2api/repo
   bash ops/custom-prod/runner/register.sh
   ```

Token 只进入一次性的注册容器环境，注册完成后容器立即删除；它不会写入 Git、`prod.env` 或 Runner 配置。之后 Runner 使用 `/srv/sub2api/runner` 中的长期凭据连接 GitHub。

Runner 挂载了宿主机 Docker Socket，因此其权限接近宿主机 root。生产工作流只能由受保护的 `custom/prod` push 触发，不得让 fork PR 或任意分支在该 Runner 上执行。

## 自动部署边界

`.github/workflows/custom-prod-deploy.yml` 只响应本仓库 `custom/prod`。流程分为两台机器：

- GitHub 托管 Runner：构建 `linux/amd64` 镜像，并推送 `prod` 与提交 SHA 两个标签到 GHCR。
- `sub2api-prod` 自托管 Runner：确认 PostgreSQL、Redis 健康，创建数据库备份，然后按不可变镜像 digest 更新应用并检查 HTTPS 健康端点。

生产 Runner 不处理 pull request，也不负责编译来自其他分支的代码。相同时间只允许一个生产部署运行，后来的部署会排队而不是中断正在执行的部署。

生产 Action 只能对 `compose.app.yml` 执行以下类型的操作：

```bash
docker compose --env-file /srv/sub2api/config/prod.env \
  -f ops/custom-prod/compose.app.yml pull sub2api

docker compose --env-file /srv/sub2api/config/prod.env \
  -f ops/custom-prod/compose.app.yml up -d --no-deps sub2api
```

自动部署禁止执行：

- `docker compose down`（针对基础设施文件）
- `docker compose down -v`
- `docker volume prune`
- `docker system prune --volumes`
- 删除 `/srv/sub2api/postgres` 或 `/srv/sub2api/redis`
- 修改或停止 Docker Nginx、Certbot

应用启动时会自动执行向前数据库迁移。生产更新前必须先创建 PostgreSQL 备份；应用镜像回滚不代表数据库结构会自动回滚。

## PostgreSQL 手动备份

```bash
mkdir -p /srv/sub2api/backups
docker exec sub2api-postgres pg_dump \
  -U sub2api -d sub2api -Fc \
  > "/srv/sub2api/backups/sub2api-$(date +%Y%m%d-%H%M%S).dump"
```

备份文件应定期复制到另一台机器或对象存储，避免服务器磁盘故障时同时丢失数据库和备份。
