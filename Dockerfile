# Dockerfile (最终版: Nginx-UI + 3x-ui + 所有服务)

# 使用完整的 Bookworm 镜像确保依赖完整
FROM debian:bookworm

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive

# 安装基础依赖 (重新加回 nginx)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    nginx \
    shellinabox \
    expect \
    curl \
    wget \
    ca-certificates \
    lsb-release \
    debian-archive-keyring  \
    gnupg \
    unzip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# --- 关键改动：从 Nginx 官方源安装 Nginx ---
RUN curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor \
    | tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null && \
    echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
    http://nginx.org/packages/mainline/debian `lsb_release -cs` nginx" \
    | tee /etc/apt/sources.list.d/nginx.list && \
    # 修正：使用 printf 确保跨 shell 兼容性，正确生成带换行的配置文件
    printf "Package: *\\nPin: origin nginx.org\\nPin: release o=nginx\\nPin-Priority: 900\\n" \
    | tee /etc/apt/preferences.d/99nginx && \
    # 安装官方源的 Nginx
    apt-get update && \
    apt-get install -y --no-install-recommends nginx

# --- 手动创建 Nginx 所需的核心目录和空的日志文件 ---
RUN mkdir -p /var/log/nginx && \
    mkdir -p /etc/nginx/conf.d && \
    touch /var/log/nginx/access.log && \
    touch /var/log/nginx/error.log && \
    echo "user nginx;\nworker_processes auto;\npid /run/nginx.pid;\nerror_log /var/log/nginx/error.log;\ninclude /etc/nginx/conf.d/*.conf;" > /etc/nginx/nginx.conf

    
# --- 安装 Cloudflared ---
RUN mkdir -p --mode=0755 /usr/share/keyrings && \
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null && \
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared bookworm main' | tee /etc/apt/sources.list.d/cloudflared.list && \
    apt-get update && \
    apt-get install -y cloudflared

# --- 使用 Docker 的 ARG 来获取目标 CPU 架构 ---
ARG TARGETARCH

# --- 安装 Nezha Agent ---
RUN \
    case "${TARGETARCH}" in \
        amd64) NEZHA_ARCH="amd64" ;; \
        arm64) NEZHA_ARCH="arm64" ;; \
        *) echo "不支持的 Nezha Agent 架构: ${TARGETARCH}"; exit 1 ;; \
    esac && \
    curl -L https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_${NEZHA_ARCH}.zip -o nezha-agent.zip && \
    unzip nezha-agent.zip && \
    mv nezha-agent /usr/local/bin/ && \
    rm nezha-agent.zip

# --- 安装 3x-ui ---
RUN \
    case "${TARGETARCH}" in \
        amd64) XUI_ARCH="amd64" ;; \
        arm64) XUI_ARCH="arm64" ;; \
        arm) XUI_ARCH="armv7" ;; \
        *) echo "不支持的 3x-ui 架构: ${TARGETARCH}"; exit 1 ;; \
    esac && \
    curl -L https://github.com/MHSanaei/3x-ui/releases/latest/download/x-ui-linux-${XUI_ARCH}.tar.gz -o x-ui.tar.gz && \
    tar -zxvf x-ui.tar.gz && \
    mv x-ui /opt/x-ui && \
    chmod +x /opt/x-ui/x-ui /opt/x-ui/bin/xray-linux-* && \
    rm x-ui.tar.gz

# --- 安装 Nginx-UI ---
RUN \
    curl -L https://github.com/0xJacky/nginx-ui/releases/download/v2.1.4-patch.1/nginx-ui-linux-64.tar.gz -o nginx-ui.tar.gz && \
    tar -zxvf nginx-ui.tar.gz && \
    mv nginx-ui /usr/local/bin/ && \
    rm nginx-ui.tar.gz

# --- 创建数据目录并复制脚本 ---
RUN mkdir -p /data
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# --- 暴露端口 ---
EXPOSE 80 443 4200 2053 9000

# --- 设置启动命令 ---
ENTRYPOINT ["/entrypoint.sh"]
