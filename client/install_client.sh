#!/bin/bash

# B-Server 客户端一键安装脚本
# 使用方法: ./install_client.sh <SERVER_IP> [NODE_NAME]
# 例如: ./install_client.sh 192.168.1.100 MyServer

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查参数
if [ $# -lt 1 ]; then
    log_error "使用方法: $0 <SERVER_IP> [NODE_NAME]"
    log_error "例如: $0 192.168.1.100 MyServer"
    exit 1
fi

SERVER_IP="$1"
NODE_NAME="${2:-$(hostname)}"  # 如果没有提供节点名，使用主机名

# 配置变量
CLIENT_DIR="$HOME/b-server-client"
VENV_DIR="$CLIENT_DIR/venv"
CLIENT_FILE="$CLIENT_DIR/client.py"
SUPERVISOR_CONF="$CLIENT_DIR/supervisord.conf"
CLIENT_URL="https://raw.githubusercontent.com/xhhcn/B-server/refs/heads/main/client/client.py"

log_info "开始安装 B-Server 客户端..."
log_info "服务器地址: $SERVER_IP:8008"
log_info "节点名称: $NODE_NAME"
log_info "安装目录: $CLIENT_DIR"

# 检查系统依赖
log_info "检查系统依赖..."

# 检查Python3
if ! command -v python3 &> /dev/null; then
    log_error "Python3 未安装，请先安装 Python3"
    exit 1
fi

# 检查pip3
if ! command -v pip3 &> /dev/null; then
    log_error "pip3 未安装，请先安装 pip3"
    exit 1
fi

# 检查curl或wget
if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
    log_error "curl 或 wget 未安装，请先安装其中之一"
    exit 1
fi

log_success "系统依赖检查完成"

# 创建安装目录
log_info "创建安装目录..."
mkdir -p "$CLIENT_DIR"
cd "$CLIENT_DIR"

# 下载客户端文件
log_info "下载客户端文件..."
if command -v curl &> /dev/null; then
    curl -L -o client.py "$CLIENT_URL"
elif command -v wget &> /dev/null; then
    wget -O client.py "$CLIENT_URL"
fi

if [ ! -f "client.py" ]; then
    log_error "客户端文件下载失败"
    exit 1
fi

log_success "客户端文件下载完成"

# 修改客户端配置
log_info "修改客户端配置..."

# 修改SERVER_URL
sed -i "s|SERVER_URL = 'http://localhost:8008'|SERVER_URL = 'http://$SERVER_IP:8008'|g" client.py

# 修改NODE_NAME（安全处理特殊字符）
# 使用Python来安全地替换，避免shell特殊字符问题
python3 -c "
import re
with open('client.py', 'r') as f:
    content = f.read()
# 安全地替换NODE_NAME，使用repr()来正确转义特殊字符
content = re.sub(r'NODE_NAME = socket\.gethostname\(\)', f'NODE_NAME = {repr(\"$NODE_NAME\")}', content)
with open('client.py', 'w') as f:
    f.write(content)
print('NODE_NAME updated to: $NODE_NAME')
"

# 修改tcping路径为直接使用tcping命令
sed -i "s|os.path.expanduser('~/.local/bin/tcping')|'tcping'|g" client.py

log_success "客户端配置修改完成"

# 创建Python虚拟环境
log_info "创建Python虚拟环境..."
python3 -m venv "$VENV_DIR"

# 激活虚拟环境
source "$VENV_DIR/bin/activate"

log_success "虚拟环境创建完成"

# 升级pip
log_info "升级pip..."
pip install --upgrade pip

# 安装Python依赖
log_info "安装Python依赖..."
pip install psutil python-socketio requests supervisor tcping python-socketio[client]

log_success "Python依赖安装完成"

# 创建supervisor配置文件
log_info "创建supervisor配置文件..."
cat > "$SUPERVISOR_CONF" << EOF
[unix_http_server]
file=$CLIENT_DIR/supervisor.sock

[supervisord]
logfile=$CLIENT_DIR/supervisord.log
logfile_maxbytes=50MB
logfile_backups=10
loglevel=info
pidfile=$CLIENT_DIR/supervisord.pid
nodaemon=false
minfds=1024
minprocs=200

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix://$CLIENT_DIR/supervisor.sock

[program:b-server-client]
command=$VENV_DIR/bin/python $CLIENT_FILE
directory=$CLIENT_DIR
user=$USER
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=$CLIENT_DIR/client.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
environment=PATH="$VENV_DIR/bin:%(ENV_PATH)s"
EOF

log_success "supervisor配置文件创建完成"

# 创建启动脚本
log_info "创建启动脚本..."
cat > "$CLIENT_DIR/start.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
source venv/bin/activate

# 检查supervisor是否已经运行
if [ -f supervisord.pid ]; then
    PID=$(cat supervisord.pid)
    if ps -p $PID > /dev/null 2>&1; then
        echo "B-Server客户端已经在运行中 (PID: $PID)"
        echo "查看状态: ./status.sh"
        echo "查看日志: ./logs.sh"
        exit 0
    else
        echo "清理旧的PID文件..."
        rm -f supervisord.pid supervisor.sock
    fi
fi

# 启动supervisor
echo "启动B-Server客户端..."
supervisord -c supervisord.conf

# 等待启动
sleep 2

# 检查启动状态
if supervisorctl -c supervisord.conf status b-server-client | grep -q "RUNNING"; then
    echo "✅ B-Server客户端启动成功！"
    echo "查看状态: ./status.sh"
    echo "停止服务: ./stop.sh"
    echo "查看日志: ./logs.sh"
else
    echo "❌ B-Server客户端启动失败"
    supervisorctl -c supervisord.conf status
    exit 1
fi
EOF

# 创建状态检查脚本
cat > "$CLIENT_DIR/status.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
source venv/bin/activate

echo "=== B-Server客户端状态 ==="
echo ""

# 检查supervisor是否运行
if [ ! -f supervisord.pid ]; then
    echo "❌ Supervisor未运行"
    echo "   使用 ./start.sh 启动服务"
    exit 1
fi

PID=$(cat supervisord.pid)
if ! ps -p $PID > /dev/null 2>&1; then
    echo "❌ Supervisor PID文件存在但进程未运行"
    echo "   使用 ./start.sh 启动服务"
    exit 1
fi

echo "✅ Supervisor正在运行 (PID: $PID)"
echo ""

# 显示详细状态
echo "=== 服务状态 ==="
supervisorctl -c supervisord.conf status

echo ""
echo "=== 系统信息 ==="
echo "工作目录: $(pwd)"
echo "配置文件: supervisord.conf"
echo "日志文件: client.log"
echo "PID文件: supervisord.pid"

echo ""
echo "=== 管理命令 ==="
echo "查看日志: ./logs.sh"
echo "停止服务: ./stop.sh"
echo "重启服务: ./restart.sh"
echo "更新客户端: ./update.sh"
EOF

# 创建停止脚本
cat > "$CLIENT_DIR/stop.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
source venv/bin/activate

# 检查supervisor是否运行
if [ ! -f supervisord.pid ]; then
    echo "B-Server客户端未在运行"
    exit 0
fi

PID=$(cat supervisord.pid)
if ! ps -p $PID > /dev/null 2>&1; then
    echo "B-Server客户端未在运行，清理PID文件..."
    rm -f supervisord.pid supervisor.sock
    exit 0
fi

echo "停止B-Server客户端..."

# 停止所有程序
supervisorctl -c supervisord.conf stop all

# 关闭supervisor
supervisorctl -c supervisord.conf shutdown

# 等待停止
sleep 2

# 检查是否完全停止
if [ -f supervisord.pid ]; then
    PID=$(cat supervisord.pid)
    if ps -p $PID > /dev/null 2>&1; then
        echo "⚠️  强制终止进程..."
        kill -9 $PID
        rm -f supervisord.pid supervisor.sock
    fi
fi

echo "✅ B-Server客户端已完全停止"
EOF

# 创建重启脚本
cat > "$CLIENT_DIR/restart.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
source venv/bin/activate

echo "重启B-Server客户端..."

# 检查supervisor是否运行
if [ ! -f supervisord.pid ]; then
    echo "Supervisor未运行，使用 ./start.sh 启动服务"
    ./start.sh
    exit $?
fi

PID=$(cat supervisord.pid)
if ! ps -p $PID > /dev/null 2>&1; then
    echo "Supervisor进程未运行，使用 ./start.sh 启动服务"
    ./start.sh
    exit $?
fi

# 重启客户端进程
supervisorctl -c supervisord.conf restart b-server-client

# 等待重启
sleep 2

# 检查重启状态
if supervisorctl -c supervisord.conf status b-server-client | grep -q "RUNNING"; then
    echo "✅ B-Server客户端重启成功！"
    echo "查看状态: ./status.sh"
    echo "查看日志: ./logs.sh"
else
    echo "❌ B-Server客户端重启失败"
    supervisorctl -c supervisord.conf status
    exit 1
fi
EOF

# 创建日志查看脚本
cat > "$CLIENT_DIR/logs.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

# 检查参数
case "$1" in
    "tail"|"t")
        echo "=== 实时日志 (按Ctrl+C退出) ==="
        tail -f client.log
        ;;
    "head"|"h")
        echo "=== 最新100行日志 ==="
        tail -100 client.log
        ;;
    "all"|"a")
        echo "=== 完整日志 ==="
        cat client.log
        ;;
    "supervisor"|"s")
        echo "=== Supervisor日志 ==="
        if [ -f supervisord.log ]; then
            tail -100 supervisord.log
        else
            echo "supervisor日志文件不存在"
        fi
        ;;
    "clear"|"c")
        echo "清空日志文件..."
        > client.log
        if [ -f supervisord.log ]; then
            > supervisord.log
        fi
        echo "✅ 日志文件已清空"
        ;;
    *)
        echo "=== B-Server客户端日志查看工具 ==="
        echo ""
        echo "使用方法: ./logs.sh [选项]"
        echo ""
        echo "选项:"
        echo "  tail, t     - 实时查看日志 (默认)"
        echo "  head, h     - 查看最新100行"
        echo "  all, a      - 查看完整日志"
        echo "  supervisor, s - 查看supervisor日志"
        echo "  clear, c    - 清空日志文件"
        echo ""
        echo "示例:"
        echo "  ./logs.sh          # 实时查看"
        echo "  ./logs.sh head     # 查看最新100行"
        echo "  ./logs.sh all      # 查看完整日志"
        echo ""
        echo "=== 实时日志 (按Ctrl+C退出) ==="
        tail -f client.log
        ;;
esac
EOF

# 创建卸载脚本
cat > "$CLIENT_DIR/uninstall.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "=== B-Server客户端卸载工具 ==="
echo ""

# 确认卸载
read -p "确定要卸载B-Server客户端吗？(y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "取消卸载"
    exit 0
fi

echo "开始卸载..."

# 停止服务
echo "停止客户端服务..."
if [ -f "./stop.sh" ]; then
    ./stop.sh
else
    echo "stop.sh不存在，跳过..."
fi

# 移除cron任务
echo "移除开机自启动..."
CLIENT_DIR="$(pwd)"
if crontab -l 2>/dev/null | grep -q "$CLIENT_DIR/start.sh"; then
    crontab -l | grep -v "$CLIENT_DIR/start.sh" | crontab -
    echo "✅ 开机自启动已移除"
else
    echo "未找到开机自启动任务"
fi

# 移除整个客户端目录
echo "移除客户端文件..."
cd ..
rm -rf "$CLIENT_DIR"

echo "✅ B-Server客户端卸载完成"
EOF

# 创建更新脚本
cat > "$CLIENT_DIR/update.sh" << EOF
#!/bin/bash
cd "\$(dirname "\$0")"
source venv/bin/activate

echo "停止客户端..."
supervisorctl -c supervisord.conf stop b-server-client

echo "下载最新客户端..."
if command -v curl &> /dev/null; then
    curl -L -o client.py.new "$CLIENT_URL"
elif command -v wget &> /dev/null; then
    wget -O client.py.new "$CLIENT_URL"
fi

if [ -f "client.py.new" ]; then
    # 修改配置
    sed -i "s|SERVER_URL = 'http://localhost:8008'|SERVER_URL = 'http://$SERVER_IP:8008'|g" client.py.new
    # 安全地修改NODE_NAME
    python3 -c "
import re
with open('client.py.new', 'r') as f:
    content = f.read()
content = re.sub(r'NODE_NAME = socket\.gethostname\(\)', f'NODE_NAME = {repr(\"$NODE_NAME\")}', content)
with open('client.py.new', 'w') as f:
    f.write(content)
"
    sed -i "s|os.path.expanduser('~/.local/bin/tcping')|'tcping'|g" client.py.new
    
    # 备份旧文件
    mv client.py client.py.backup
    mv client.py.new client.py
    
    echo "启动客户端..."
    supervisorctl -c supervisord.conf start b-server-client
    echo "✅ 客户端更新完成"
else
    echo "❌ 下载失败，启动旧版本客户端..."
    supervisorctl -c supervisord.conf start b-server-client
fi
EOF

# 设置脚本执行权限
chmod +x "$CLIENT_DIR"/*.sh

log_success "管理脚本创建完成"

# 设置开机自启动（使用cron而不是systemd）
log_info "设置开机自启动..."

# 检查是否已经存在cron任务
if crontab -l 2>/dev/null | grep -q "$CLIENT_DIR/start.sh"; then
    log_info "开机自启动已存在，跳过..."
else
    # 添加开机自启动到cron
    (crontab -l 2>/dev/null; echo "@reboot sleep 30 && cd $CLIENT_DIR && ./start.sh") | crontab -
    log_success "开机自启动已添加到cron"
fi

log_info "开机自启动配置完成"
log_info "可以使用以下命令管理服务:"
log_info "  启动: cd $CLIENT_DIR && ./start.sh"
log_info "  停止: cd $CLIENT_DIR && ./stop.sh"
log_info "  重启: cd $CLIENT_DIR && ./restart.sh"
log_info "  查看状态: cd $CLIENT_DIR && ./status.sh"
log_info "  查看日志: cd $CLIENT_DIR && ./logs.sh"

# 测试客户端配置
log_info "测试客户端配置..."
source "$VENV_DIR/bin/activate"
python3 -c "
import sys
sys.path.insert(0, '$CLIENT_DIR')
try:
    import socket, psutil, socketio, requests
    print('✓ 所有依赖模块导入成功')
except ImportError as e:
    print(f'✗ 依赖模块导入失败: {e}')
    sys.exit(1)

# 检查配置
with open('$CLIENT_FILE', 'r') as f:
    content = f.read()
    if 'http://$SERVER_IP:8008' in content:
        print('✓ 服务器地址配置正确')
    else:
        print('✗ 服务器地址配置错误')
        sys.exit(1)
    
    # 检查NODE_NAME是否已经不是默认的socket.gethostname()形式
    if 'NODE_NAME = socket.gethostname()' not in content:
        print('✓ 节点名称配置正确')
    else:
        print('✗ 节点名称配置错误')
        sys.exit(1)
        
    if \"'tcping'\" in content:
        print('✓ tcping路径配置正确')
    else:
        print('✗ tcping路径配置错误')
        sys.exit(1)

print('✓ 客户端配置测试通过')
"

if [ $? -eq 0 ]; then
    log_success "客户端配置测试通过"
else
    log_error "客户端配置测试失败"
    exit 1
fi

# 启动客户端
log_info "启动B-Server客户端..."
source "$VENV_DIR/bin/activate"
supervisord -c "$SUPERVISOR_CONF"

# 等待启动
sleep 3

# 检查启动状态
if supervisorctl -c "$SUPERVISOR_CONF" status b-server-client | grep -q "RUNNING"; then
    log_success "B-Server客户端启动成功！"
else
    log_error "B-Server客户端启动失败，请检查日志"
    supervisorctl -c "$SUPERVISOR_CONF" status
    exit 1
fi

# 显示安装完成信息
echo ""
echo "========================================"
log_success "B-Server客户端安装完成！"
echo "========================================"
echo ""
echo "安装信息:"
echo "  安装目录: $CLIENT_DIR"
echo "  服务器地址: $SERVER_IP:8008"
echo "  节点名称: $NODE_NAME"
echo ""
echo "管理命令:"
echo "  查看状态: cd $CLIENT_DIR && ./status.sh"
echo "  查看日志: cd $CLIENT_DIR && ./logs.sh"
echo "  停止服务: cd $CLIENT_DIR && ./stop.sh"
echo "  重启服务: cd $CLIENT_DIR && ./restart.sh"
echo "  更新客户端: cd $CLIENT_DIR && ./update.sh"
echo "  卸载客户端: cd $CLIENT_DIR && ./uninstall.sh"
echo ""
echo "开机自启动："
echo "  ✅ 已通过cron设置开机自启动"
echo "  查看cron任务: crontab -l"
echo "  移除自启动: crontab -e (删除包含 $CLIENT_DIR/start.sh 的行)"
echo ""
echo "重要提示:"
echo "  1. 请确保在服务器管理面板中添加了节点 '$NODE_NAME'"
echo "  2. 请确保服务器防火墙允许8008端口访问"
echo "  3. 客户端日志位置: $CLIENT_DIR/client.log"
echo "  4. 使用 ./start.sh 和 ./stop.sh 来控制服务"
echo ""
log_info "安装完成！客户端正在运行中..." 