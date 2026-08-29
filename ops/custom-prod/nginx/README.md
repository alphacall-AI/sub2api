# Nginx and HTTPS

Nginx 是长期运行的入口层，不由应用 GitHub Actions 安装、停止或删除。它只把公网 80/443 请求转发到宿主机的 `127.0.0.1:8080`。

## 启用条件

执行前必须满足：

- 域名的 DNS 已指向生产服务器。
- 公网可以访问服务器 80 和 443 端口。
- Sub2API 已经在 `127.0.0.1:8080` 健康运行。
- 将下文的 `example.com` 替换成正式域名。

## 首次申请证书

1. 安装 Nginx 和 Certbot：

   ```bash
   sudo apt-get update
   sudo apt-get install -y nginx certbot
   sudo install -d -m 0755 /var/www/certbot
   ```

2. 从 `bootstrap.conf.example` 生成临时 HTTP 配置：

   ```bash
   sed 's/__DOMAIN__/example.com/g' \
     ops/custom-prod/nginx/bootstrap.conf.example \
     | sudo tee /etc/nginx/sites-available/sub2api >/dev/null

   sudo ln -sfn /etc/nginx/sites-available/sub2api \
     /etc/nginx/sites-enabled/sub2api
   sudo nginx -t
   sudo systemctl enable --now nginx
   ```

3. 使用 Webroot 模式申请证书：

   ```bash
   sudo certbot certonly \
     --webroot \
     --webroot-path /var/www/certbot \
     --domain example.com
   ```

4. 从 `sub2api.conf.example` 生成正式 HTTPS 配置并重载：

   ```bash
   sed 's/__DOMAIN__/example.com/g' \
     ops/custom-prod/nginx/sub2api.conf.example \
     | sudo tee /etc/nginx/sites-available/sub2api >/dev/null

   sudo nginx -t
   sudo systemctl reload nginx
   ```

## 自动续期

Certbot 的系统定时器负责检查续期。将仓库内的重载脚本安装为 deploy hook，让新证书生效前先验证 Nginx 配置：

```bash
sudo install -D -m 0755 \
  ops/custom-prod/nginx/reload-nginx.sh \
  /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh

sudo systemctl enable --now certbot.timer
sudo certbot renew --dry-run
```

## 验收

```bash
curl --fail --silent --show-error http://127.0.0.1:8080/health
curl --fail --silent --show-error https://example.com/health
sudo nginx -t
systemctl is-active nginx
systemctl is-enabled certbot.timer
```

## 自动部署边界

应用 Action 不得修改以下内容：

- `/etc/nginx/`
- `/etc/letsencrypt/`
- `/var/www/certbot/`
- Nginx 和 Certbot systemd 服务

如果以后需要修改代理规则，先在 `custom/main` 更新本目录文件并测试，再作为独立的运维变更发布；不要把 Nginx 重载混进每次应用镜像更新。

