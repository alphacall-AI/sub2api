# Custom production deployment

这个目录是我们自己的生产部署层，独立于原作者的 `deploy/` 目录，目的是降低同步上游代码时的冲突。

## 分支规则

- `main`：只同步原作者上游，不放自定义修改。
- `custom/main`：自定义开发与部署配置。
- `custom/prod`：生产分支，只接收确认可上线的 `custom/main` 变更。
- GitHub Actions 只允许由 `custom/prod` 触发生产部署。

## 文件职责

- `compose.infra.yml`：PostgreSQL、Redis 和私有 Docker 网络。长期运行，不由自动部署停止或删除。
- `compose.app.yml`：Sub2API 应用。GitHub Actions 只能管理这一层。
- `compose.edge.yml`：Docker Nginx 和 Certbot。长期运行，不由应用 Action 管理。
- `nginx/`：Nginx HTTP/HTTPS 模板和证书申请说明。
- `env.example`：服务器环境变量模板，不包含真实密钥。

所有持久化数据默认位于 `/srv/sub2api`，不放在 Runner 工作目录：

```text
/srv/sub2api/
├── app/          Sub2API 运行数据和日志
├── postgres/     PostgreSQL 数据
├── redis/        Redis AOF/RDB 数据
├── backups/      数据库备份
├── certbot/      Let's Encrypt 证书和 ACME 文件
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

## 自动部署边界

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
