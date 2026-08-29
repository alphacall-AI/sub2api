# Docker Nginx and HTTPS

Nginx 和 Certbot 都通过 `compose.edge.yml` 运行。它们是长期入口层，不由应用 GitHub Actions 停止或删除。

```text
Internet :80/:443
        │
        ▼
sub2api-nginx
        │  Docker network: sub2api-backend
        ▼
sub2api-prod:8080
```

证书和 ACME 文件保存在 `/srv/sub2api/certbot`，不在容器层或 Runner 工作目录中。

## 启用条件

执行前必须满足：

- 域名 DNS 已指向生产服务器。
- 公网可以访问服务器 80 和 443 端口。
- `compose.infra.yml` 已启动并创建 `sub2api-backend` 网络。
- 将下文的 `example.com` 替换成正式域名。

## 首次申请证书

1. 创建持久化目录：

   ```bash
   sudo install -d -m 0750 \
     /srv/sub2api/config \
     /srv/sub2api/certbot/www \
     /srv/sub2api/certbot/letsencrypt
   sudo chown -R "$USER":"$USER" /srv/sub2api
   ```

2. 在 `/srv/sub2api/config/prod.env` 设置：

   ```text
   SUB2API_DOMAIN=example.com
   NGINX_IMAGE=nginx:alpine
   CERTBOT_IMAGE=certbot/certbot:latest
   ```

   Nginx/Certbot 镜像不会被应用 Action 自动更新。正式运行稳定后可以将它们固定到测试过的版本或 digest。

3. 从 `bootstrap.conf.example` 生成临时 HTTP 配置：

   ```bash
   sed 's/__DOMAIN__/example.com/g' \
     ops/custom-prod/nginx/bootstrap.conf.example \
     > /srv/sub2api/config/nginx.conf
   chmod 640 /srv/sub2api/config/nginx.conf
   ```

4. 只启动 Nginx：

   ```bash
   docker compose \
     --env-file /srv/sub2api/config/prod.env \
     -f ops/custom-prod/compose.edge.yml \
     up -d nginx
   ```

5. 使用一次性 Certbot 容器申请证书：

   ```bash
   docker compose \
     --env-file /srv/sub2api/config/prod.env \
     -f ops/custom-prod/compose.edge.yml \
     run --rm --entrypoint /bin/sh certbot -ec '
       certbot certonly \
         --webroot \
         --webroot-path /var/www/certbot \
         --domain "$SUB2API_DOMAIN" \
         --agree-tos \
         --register-unsafely-without-email
     '
   ```

6. 从 `sub2api.conf.example` 生成正式 HTTPS 配置：

   ```bash
   sed 's/__DOMAIN__/example.com/g' \
     ops/custom-prod/nginx/sub2api.conf.example \
     > /srv/sub2api/config/nginx.conf

   docker exec sub2api-nginx nginx -t
   docker exec sub2api-nginx nginx -s reload
   ```

7. 启动自动续期容器：

   ```bash
   docker compose \
     --env-file /srv/sub2api/config/prod.env \
     -f ops/custom-prod/compose.edge.yml \
     up -d
   ```

Certbot 使用无邮箱 ACME 账户注册。它每 12 小时检查一次续期；Nginx 每 6 小时验证配置并平滑重载，因此续期后的证书会自动生效。

## 验收

```bash
docker compose \
  --env-file /srv/sub2api/config/prod.env \
  -f ops/custom-prod/compose.edge.yml \
  ps

curl --fail --silent --show-error https://example.com/health
docker exec sub2api-nginx nginx -t
```

## 自动部署边界

应用 Action 不得管理或删除：

- `compose.edge.yml`
- `sub2api-nginx`
- `sub2api-certbot`
- `/srv/sub2api/config/nginx.conf`
- `/srv/sub2api/certbot`

代理规则变更应先在 `custom/main` 测试，再作为独立运维变更发布；不要把 Nginx 重启混进每次应用镜像更新。
