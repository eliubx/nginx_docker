#!/bin/sh

# entrypoint.sh - 最终版：Nginx-UI 作为主服务

# --- 1. 启动所有后台服务 ---

# A. WebSSH
if [ "$ENABLE_WEBSSH" = "true" ]; then
    echo "✅ 正在启动 WebSSH 服务..."
    if [ -z "${ROOT_PASSWORD}" ]; then echo "致命错误: WebSSH 已启用，但 .env 文件中未设置 ROOT_PASSWORD" >&2; exit 1; fi
    expect << EOF
spawn passwd root
expect "New password:"
send "${ROOT_PASSWORD}\r"
expect "Retype new password:"
send "${ROOT_PASSWORD}\r"
expect eof
EOF
    shellinaboxd -b -t
else
    echo "❌ WebSSH 服务已被禁用。"
fi

# B. Nezha Agent
if [ "$ENABLE_NEZHA_AGENT" = "true" ]; then
    echo "✅ 正在配置并启动 Nezha Agent..."
    if [ -z "${NEZHA_SERVER}" ] || [ -z "${NEZHA_PORT}" ] || [ -z "${NEZHA_KEY}" ]; then echo "致命错误: Nezha 已启用，但 .env 文件中未完整设置 NEZHA_SERVER, NEZHA_PORT, 或 NEZHA_KEY" >&2; exit 1; fi
    mkdir -p /etc/nezha-agent
    cat > /etc/nezha-agent/config.yaml << EOF
client_secret: "${NEZHA_KEY}"
debug: ${NEZHA_DEBUG}
server: "${NEZHA_SERVER}:${NEZHA_PORT}"
tls: ${NEZHA_TLS}
EOF
    if [ "$NEZHA_DEBUG" = "true" ]; then nezha-agent -c /etc/nezha-agent/config.yaml & else nezha-agent -c /etc/nezha-agent/config.yaml >/dev/null 2>&1 & fi
else
    echo "❌ Nezha Agent 已被禁用。"
fi

# C. Cloudflared Tunnel
if [ "$ENABLE_CLOUDFLARED" = "true" ]; then
    echo "✅ 正在启动 Cloudflared 服务 (Token 模式)..."
    if [ -z "${CLOUDFLARED_TOKEN}" ]; then echo "致命错误: Cloudflared 已启用，但 .env 文件中未设置 CLOUDFLARED_TOKEN" >&2; exit 1; fi
    cloudflared tunnel run --token ${CLOUDFLARED_TOKEN} &
else
    echo "❌ Cloudflared 已被禁用。"
fi

# D. 3x-ui Panel (添加符号链接修复)
if [ "$ENABLE_3X_UI" = "true" ]; then
    echo "✅ 正在启动 3x-ui 面板 (后台模式)..."
    DATA_DIR="/data/3x-ui"
    APP_DIR="/opt/x-ui"
    
    # 确保数据目录存在
    mkdir -p ${DATA_DIR}

    # 关键一步：在数据目录中，创建指向程序 bin 目录的符号链接
    # 这让 3x-ui 在当前目录能找到 bin，从而写入 xray 配置
    # -s: 创建符号链接, -f: 强制覆盖已存在的链接, -n: 处理目标是目录时的兼容性
    ln -sfn ${APP_DIR}/bin ${DATA_DIR}/bin
    
    # 导出环境变量，供 3x-ui 首次启动时读取
    export XRAY_PANEL_PORT=${PANEL_PORT}
    export XRAY_PANEL_USERNAME=${PANEL_USERNAME}
    export XRAY_PANEL_PASSWORD=${PANEL_PASSWORD}
    
    # 切换到数据目录再执行程序，确保数据库在此创建
    (cd ${DATA_DIR} && ${APP_DIR}/x-ui) &
else
    echo "❌ 3x-ui 面板已被禁用。"
fi

# --- 2. 启动主服务 ---

if [ "$ENABLE_NGINX_UI" = "true" ]; then
    echo "🚀 正在启动 Nginx-UI 作为主进程..."
    DATA_DIR="/etc/nginx-ui"
    
    mkdir -p ${DATA_DIR}
    
    export NGINX_UI_PORT=${NGINX_UI_PORT}
    export NGINX_UI_USERNAME=${NGINX_UI_USERNAME}
    export NGINX_UI_PASSWORD=${NGINX_UI_PASSWORD}
    
    # --- 关键修复：明确告知 Nginx-UI 配置文件和 PID 文件的位置 ---
    # 这样它就不会再去依赖 `nginx -V` 的输出了
    export NGINX_CONF_PATH="/etc/nginx/nginx.conf"
    export NGINX_PID_PATH="/run/nginx.pid"

    # 修正：先进入目录，再用 exec 启动程序，这是正确的语法
    cd ${DATA_DIR}
    exec /usr/local/bin/nginx-ui
else
    echo "❌ Nginx-UI 未启用。容器将进入休眠状态以保持后台服务运行。"
    tail -f /dev/null
fi
