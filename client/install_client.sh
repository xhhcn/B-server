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
pip install psutil python-socketio requests tcping python-socketio[client]

log_success "Python依赖安装完成"



# 创建启动脚本（保持兼容性）
log_info "创建启动脚本..."
cat > "$CLIENT_DIR/start.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "B-Server客户端启动脚本 - 重定向到新的启动方式"
echo "使用新的启动脚本: ./run_client.sh"
echo ""

# 调用新的启动脚本
./run_client.sh
EOF

# 创建状态检查脚本
cat > "$CLIENT_DIR/status.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "=== B-Server客户端状态检查 ==="
echo ""

# 检查停止标记文件
if [ -f ".stopped" ]; then
    echo "⚠️  发现停止标记文件"
    echo "客户端已被手动停止，不应该自动重启"
    echo ""
    echo "停止标记内容:"
    cat ".stopped"
    echo ""
    echo "如需重新启动:"
    echo "• 删除停止标记并启动: rm -f .stopped && ./run_client.sh"
    echo "• 或直接运行启动脚本: ./run_client.sh"
    echo ""
fi

# 检查客户端是否运行
if [ ! -f client.pid ]; then
    echo "❌ 客户端未运行（无PID文件）"
    if [ -f ".stopped" ]; then
        echo "   客户端处于停止状态"
        echo "   如需启动: ./run_client.sh"
    else
        echo "   使用 ./run_client.sh 启动服务"
    fi
    echo ""
    echo "=== 管理命令 ==="
    echo "启动服务: ./run_client.sh"
    echo "查看日志: ./logs.sh"
    exit 1
fi

PID=$(cat client.pid)
if ! ps -p $PID > /dev/null 2>&1; then
    echo "❌ PID文件存在但进程未运行 (PID: $PID)"
    echo "   清理PID文件并重新启动..."
    rm -f client.pid
    if [ -f ".stopped" ]; then
        echo "   发现停止标记文件，可能是手动停止的"
        echo "   如需启动: ./run_client.sh"
    else
        echo "   使用 ./run_client.sh 启动服务"
    fi
    echo ""
    echo "=== 管理命令 ==="
    echo "启动服务: ./run_client.sh"
    echo "查看日志: ./logs.sh"
    exit 1
fi

echo "✅ B-Server客户端正在运行 (PID: $PID)"
echo ""

# 显示进程信息
echo "=== 进程信息 ==="
ps -p $PID -o pid,ppid,cmd,etime

echo ""
echo "=== 系统信息 ==="
echo "工作目录: $(pwd)"
echo "PID文件: client.pid"
echo "日志文件: client.log"

# 检查自动启动机制
echo ""
echo "=== 自动启动机制 ==="
autostart_found=false

# 检查systemd服务
if command -v systemctl &> /dev/null; then
    if systemctl is-enabled --quiet "b-server-client.service" 2>/dev/null; then
        echo "✅ systemd服务已启用"
        if systemctl is-active --quiet "b-server-client.service" 2>/dev/null; then
            echo "   服务状态: 运行中"
        else
            echo "   服务状态: 已停止"
        fi
        autostart_found=true
    fi
fi

# 检查rc.local
if [ -f "/etc/rc.local" ] && grep -q "$(pwd)" /etc/rc.local; then
    echo "✅ rc.local启动项已设置"
    autostart_found=true
fi

# 检查cron任务
if crontab -l 2>/dev/null | grep -q "$(pwd)"; then
    echo "✅ cron任务已设置"
    autostart_found=true
fi

if [ "$autostart_found" = false ]; then
    echo "⚠️  未找到自动启动机制"
    echo "   客户端不会在重启后自动启动"
    echo "   运行 ./fix_autostart.sh 设置自动启动"
fi

echo ""
echo "=== 管理命令 ==="
echo "查看日志: ./logs.sh"
echo "停止服务: ./stop_simple.sh"
echo "重启服务: ./restart.sh"
echo "更新客户端: ./update.sh"
echo "修复自动启动: ./fix_autostart.sh"
EOF

# 创建重启脚本（使用新的停止脚本）
cat > "$CLIENT_DIR/restart.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "=== 重启B-Server客户端 ==="
echo ""

echo "[1] 停止现有进程..."
./stop_simple.sh

echo ""
echo "[2] 等待完全停止..."
sleep 3

echo ""
echo "[3] 启动新进程..."
./run_client.sh
EOF

# 创建启动脚本（兼容性重定向）
cat > "$CLIENT_DIR/start.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "B-Server客户端启动脚本 - 重定向到新的启动方式"
echo "使用新的启动脚本: ./run_client.sh"
echo ""

# 调用新的启动脚本
./run_client.sh
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
    "startup"|"s")
        echo "=== 启动日志 ==="
        if [ -f startup.log ]; then
            tail -100 startup.log
        else
            echo "启动日志文件不存在"
        fi
        ;;
    "clear"|"c")
        echo "清空日志文件..."
        > client.log
        if [ -f startup.log ]; then
            > startup.log
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
        echo "  startup, s  - 查看启动日志"
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
if [ -f "./stop_simple.sh" ]; then
    ./stop_simple.sh
elif [ -f "./stop.sh" ]; then
    ./stop.sh
else
    echo "停止脚本不存在，尝试手动停止..."
    # 手动停止进程
    if [ -f "client.pid" ]; then
        PID=$(cat client.pid)
        if ps -p $PID > /dev/null 2>&1; then
            kill $PID && echo "已停止进程 PID: $PID"
        fi
        rm -f client.pid
    fi
    pkill -f "python3.*client.py" || true
fi

# 移除systemd服务
echo "检查并移除systemd服务..."
if command -v systemctl &> /dev/null; then
    SERVICE_NAME="b-server-client.service"
    SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
    
    # 检查服务是否存在
    if systemctl list-unit-files | grep -q "$SERVICE_NAME"; then
        echo "发现systemd服务，正在移除..."
        
        # 停止并禁用服务
        sudo systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        sudo systemctl disable "$SERVICE_NAME" 2>/dev/null || true
        
        # 删除服务文件
        if [ -f "$SERVICE_FILE" ]; then
            sudo rm -f "$SERVICE_FILE"
            echo "✅ systemd服务文件已删除"
        fi
        
        # 重新加载systemd
        sudo systemctl daemon-reload 2>/dev/null || true
        echo "✅ systemd服务已完全移除"
    else
        echo "未找到systemd服务"
    fi
else
    echo "系统不支持systemd，跳过服务移除"
fi

# 移除rc.local启动项
echo "检查并移除rc.local启动项..."
CLIENT_DIR="$(pwd)"
if [ -f "/etc/rc.local" ] && grep -q "$CLIENT_DIR" /etc/rc.local; then
    echo "发现rc.local启动项，正在移除..."
    # 备份rc.local
    sudo cp /etc/rc.local /etc/rc.local.backup.uninstall.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
    
    # 移除B-Server相关的启动项
    sudo sed -i '/# B-Server Client Auto Start/,+1d' /etc/rc.local 2>/dev/null || true
    sudo sed -i "\\|$CLIENT_DIR|d" /etc/rc.local 2>/dev/null || true
    echo "✅ rc.local启动项已移除"
else
    echo "未找到rc.local启动项"
fi

# 移除cron任务
echo "检查并移除cron任务..."
if crontab -l 2>/dev/null | grep -q "$CLIENT_DIR"; then
    echo "发现cron任务，正在移除..."
    # 创建临时cron文件
    TEMP_CRON=$(mktemp)
    
    # 获取现有cron任务并过滤掉B-Server相关的任务
    crontab -l 2>/dev/null | grep -v "$CLIENT_DIR" > "$TEMP_CRON"
    
    # 安装新的crontab
    if crontab "$TEMP_CRON"; then
        echo "✅ cron任务已移除"
    else
        echo "❌ 移除cron任务失败，请手动执行: crontab -e"
    fi
    
    # 清理临时文件
    rm -f "$TEMP_CRON"
else
    echo "未找到cron任务"
fi

# 显示清理摘要
echo ""
echo "=== 卸载摘要 ==="
echo "已尝试移除："
echo "  ✓ 客户端进程"
echo "  ✓ systemd服务 (如果存在)"
echo "  ✓ rc.local启动项 (如果存在)"
echo "  ✓ cron任务 (如果存在)"
echo ""

# 移除整个客户端目录
echo "移除客户端文件..."
PARENT_DIR="$(dirname "$CLIENT_DIR")"
cd "$PARENT_DIR"
rm -rf "$CLIENT_DIR"

echo "✅ B-Server客户端卸载完成"
echo ""
echo "如需重新安装，请重新运行安装脚本："
echo "curl -fsSL https://raw.githubusercontent.com/xhhcn/B-server/refs/heads/main/client/install_client.sh | bash -s <SERVER_IP> [NODE_NAME]"
EOF

# 创建更新脚本
cat > "$CLIENT_DIR/update.sh" << EOF
#!/bin/bash
cd "\$(dirname "\$0")"

echo "停止客户端..."
./stop_simple.sh

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
    if ./run_client.sh; then
        sleep 2
        if [ -f "client.pid" ] && ps -p \$(cat client.pid) > /dev/null 2>&1; then
            echo "✅ 客户端更新完成 (PID: \$(cat client.pid))"
        else
            echo "⚠️  客户端更新完成但启动可能失败，请检查日志"
        fi
    else
        echo "❌ 启动失败，请检查配置"
    fi
else
    echo "❌ 下载失败"
fi
EOF

# 创建开机自启动修复脚本
cat > "$CLIENT_DIR/fix_autostart.sh" << 'AUTOSTART_EOF'
#!/bin/bash

# B-Server 客户端开机自启动修复脚本
# 使用方法: ./fix_autostart.sh

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

# 获取脚本所在目录（客户端安装目录）
CLIENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "B-Server 客户端开机自启动修复工具"
echo "========================================"
echo ""
log_info "客户端目录: $CLIENT_DIR"
echo ""

# 检查客户端文件是否存在
if [ ! -f "$CLIENT_DIR/run_client.sh" ]; then
    log_error "run_client.sh 文件不存在，请确保在正确的客户端目录中运行此脚本"
    exit 1
fi

if [ ! -f "$CLIENT_DIR/client.py" ]; then
    log_error "client.py 文件不存在，请确保客户端已正确安装"
    exit 1
fi

# 检查当前开机自启动状态
log_info "检查当前开机自启动状态..."

CURRENT_METHOD=""
if command -v systemctl &> /dev/null && systemctl is-enabled b-server-client.service &>/dev/null; then
    CURRENT_METHOD="systemd"
    log_info "发现systemd服务: b-server-client.service"
elif [ -f "/etc/rc.local" ] && grep -q "$CLIENT_DIR/run_client.sh" /etc/rc.local; then
    CURRENT_METHOD="rc.local"
    log_info "发现rc.local启动项"
elif crontab -l 2>/dev/null | grep -q "$CLIENT_DIR"; then
    CURRENT_METHOD="cron"
    log_info "发现cron启动项（旧版本）"
else
    log_warn "未找到现有的开机自启动设置"
fi

# 提供选项让用户选择
echo ""
echo "请选择开机自启动方式:"
echo "1) systemd服务 (推荐，现代Linux发行版)"
echo "2) rc.local (传统方式，简单直接)"
echo "3) crontab (兼容性最好，但可能有延迟)"
echo "0) 移除所有开机自启动"

while true; do
    read -p "请选择 (1/2/3/0): " choice
    case $choice in
        1)
            # 使用systemd
            if ! command -v systemctl &> /dev/null; then
                log_error "系统不支持systemd"
                continue
            fi
            
            log_info "设置systemd开机自启动..."
            
            # 移除其他方式的自启动
            [ "$CURRENT_METHOD" = "rc.local" ] && sudo sed -i '/B-Server Client Auto Start/,+1d' /etc/rc.local
            [ "$CURRENT_METHOD" = "cron" ] && (crontab -l 2>/dev/null | grep -v "$CLIENT_DIR" | crontab -)
            
            # 创建systemd服务
            SERVICE_FILE="/etc/systemd/system/b-server-client.service"
            if sudo tee "$SERVICE_FILE" > /dev/null << SYSTEMD_EOF
[Unit]
Description=B-Server Monitoring Client
After=network.target
Wants=network.target

[Service]
Type=forking
User=$USER
WorkingDirectory=$CLIENT_DIR
ExecStart=$CLIENT_DIR/run_client.sh
ExecStop=$CLIENT_DIR/stop_simple.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF
            then
                if sudo systemctl daemon-reload && sudo systemctl enable b-server-client.service; then
                    log_success "systemd开机自启动设置成功"
                    log_info "管理命令:"
                    log_info "  启动: sudo systemctl start b-server-client"
                    log_info "  停止: sudo systemctl stop b-server-client"
                    log_info "  状态: sudo systemctl status b-server-client"
                    log_info "  日志: journalctl -u b-server-client -f"
                else
                    log_error "systemd服务启用失败"
                fi
            else
                log_error "创建systemd服务文件失败"
            fi
            break
            ;;
        2)
            # 使用rc.local
            log_info "设置rc.local开机自启动..."
            
            # 移除其他方式的自启动
            [ "$CURRENT_METHOD" = "systemd" ] && sudo systemctl disable b-server-client.service 2>/dev/null
            [ "$CURRENT_METHOD" = "cron" ] && (crontab -l 2>/dev/null | grep -v "$CLIENT_DIR" | crontab -)
            
            # 创建或修改rc.local
            if [ ! -f "/etc/rc.local" ]; then
                sudo tee /etc/rc.local > /dev/null << RC_EOF
#!/bin/bash
# rc.local - executed at the end of each multiuser runlevel

exit 0
RC_EOF
                sudo chmod +x /etc/rc.local
            fi
            
            # 添加启动命令
            if ! grep -q "$CLIENT_DIR/run_client.sh" /etc/rc.local; then
                sudo sed -i '/^exit 0/i\# B-Server Client Auto Start\nsleep 10 && su - '$USER' -c "cd '$CLIENT_DIR' && ./run_client.sh" &\n' /etc/rc.local
                log_success "rc.local开机自启动设置成功"
            else
                log_info "rc.local中已存在启动命令"
            fi
            break
            ;;
        3)
            # 使用crontab
            log_info "设置crontab开机自启动..."
            
            # 移除其他方式的自启动
            [ "$CURRENT_METHOD" = "systemd" ] && sudo systemctl disable b-server-client.service 2>/dev/null
            [ "$CURRENT_METHOD" = "rc.local" ] && sudo sed -i '/B-Server Client Auto Start/,+1d' /etc/rc.local
            
            # 设置cron
            TEMP_CRON=$(mktemp)
            crontab -l 2>/dev/null | grep -v "$CLIENT_DIR" > "$TEMP_CRON"
            echo "@reboot sleep 30 && cd $CLIENT_DIR && ./run_client.sh" >> "$TEMP_CRON"
            
            if crontab "$TEMP_CRON"; then
                log_success "crontab开机自启动设置成功"
                log_info "查看任务: crontab -l"
            else
                log_error "crontab设置失败"
            fi
            rm -f "$TEMP_CRON"
            break
            ;;
        0)
            # 移除所有自启动
            log_info "移除所有开机自启动..."
            
            # 移除systemd
            if command -v systemctl &> /dev/null && systemctl is-enabled b-server-client.service &>/dev/null; then
                sudo systemctl disable b-server-client.service
                sudo rm -f /etc/systemd/system/b-server-client.service
                sudo systemctl daemon-reload
                log_info "已移除systemd服务"
            fi
            
            # 移除rc.local
            if [ -f "/etc/rc.local" ] && grep -q "$CLIENT_DIR" /etc/rc.local; then
                sudo sed -i '/B-Server Client Auto Start/,+1d' /etc/rc.local
                log_info "已移除rc.local启动项"
            fi
            
            # 移除cron
            if crontab -l 2>/dev/null | grep -q "$CLIENT_DIR"; then
                crontab -l 2>/dev/null | grep -v "$CLIENT_DIR" | crontab -
                log_info "已移除cron启动项"
            fi
            
            log_success "所有开机自启动已移除"
            break
            ;;
        *)
            log_error "无效选择，请重新输入"
            ;;
    esac
done

echo ""
echo "========================================"
log_success "开机自启动修复完成！"
echo "========================================"
echo ""

# 询问是否测试启动
if [ "$choice" != "0" ]; then
    read -p "是否现在测试启动客户端？(Y/n): " test_choice
    if [[ ! "$test_choice" =~ ^[Nn]$ ]]; then
        log_info "测试启动客户端..."
        cd "$CLIENT_DIR"
        
        if ./run_client.sh; then
            sleep 2
            if [ -f "client.pid" ] && ps -p $(cat client.pid) > /dev/null 2>&1; then
                log_success "客户端启动测试成功 (PID: $(cat client.pid))"
            else
                log_error "客户端启动测试失败"
            fi
        else
            log_error "客户端启动脚本执行失败"
        fi
    fi
fi

echo ""
log_info "修复完成！"
AUTOSTART_EOF

# 设置脚本执行权限
chmod +x "$CLIENT_DIR"/*.sh

log_success "管理脚本创建完成"

# 设置开机自启动（优先使用systemd，备选rc.local）
log_info "设置开机自启动..."

# 创建智能启动脚本（检查停止标记文件）
cat > "$CLIENT_DIR/run_client.sh" << 'RUN_EOF'
#!/bin/bash

# B-Server 客户端智能启动脚本
CLIENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$CLIENT_DIR"

echo "=== B-Server客户端启动脚本 ==="
echo ""

# 检查停止标记文件
if [ -f "$CLIENT_DIR/.stopped" ]; then
    echo "⚠️  发现停止标记文件"
    echo "客户端之前已被手动停止，可能不应该自动重启"
    echo ""
    echo "停止标记内容:"
    cat "$CLIENT_DIR/.stopped"
    echo ""
    echo "如果您确实想要启动客户端，请选择："
    echo "1. 删除停止标记并启动 (推荐)"
    echo "2. 忽略停止标记并强制启动"
    echo "3. 取消启动"
    echo ""
    
    # 如果是自动启动（非交互环境），则直接退出
    if [ ! -t 0 ]; then
        echo "🔍 检测到非交互环境（自动启动），遵循停止标记，不启动客户端"
        echo "如需启动，请手动运行: rm -f .stopped && ./run_client.sh"
        exit 0
    fi
    
    read -p "请选择 (1/2/3): " choice
    case $choice in
        1)
            rm -f "$CLIENT_DIR/.stopped"
            echo "✅ 已删除停止标记，继续启动..."
            ;;
        2)
            echo "⚠️  强制启动，保留停止标记..."
            ;;
        3)
            echo "❌ 取消启动"
            exit 0
            ;;
        *)
            echo "❌ 无效选择，取消启动"
            exit 0
            ;;
    esac
    echo ""
fi

# 检查是否已经在运行
if [ -f "client.pid" ]; then
    PID=$(cat client.pid)
    if ps -p $PID > /dev/null 2>&1; then
        echo "⚠️  客户端已经在运行 (PID: $PID)"
        echo "如需重启，请先运行: ./stop_simple.sh"
        exit 1
    else
        echo "🔍 发现僵尸PID文件，清理中..."
        rm -f client.pid
    fi
fi

echo "[1] 准备启动环境..."

# 激活虚拟环境
if [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
    echo "✅ 虚拟环境已激活"
else
    echo "⚠️  未找到虚拟环境，使用系统Python"
fi

# 设置日志文件
LOG_FILE="$CLIENT_DIR/client.log"
echo "✅ 日志文件: $LOG_FILE"

echo ""
echo "[2] 启动客户端进程..."

# 记录启动时间
echo "$(date): Starting B-Server Client..." >> "$LOG_FILE"

# 直接运行客户端，输出到日志文件
nohup python3 client.py >> "$LOG_FILE" 2>&1 &

# 获取进程ID
CLIENT_PID=$!
echo $CLIENT_PID > "$CLIENT_DIR/client.pid"

echo "$(date): B-Server Client started with PID: $CLIENT_PID" >> "$LOG_FILE"

# 验证进程是否成功启动
sleep 2
if ps -p $CLIENT_PID > /dev/null 2>&1; then
    echo "✅ B-Server客户端启动成功 (PID: $CLIENT_PID)"
    echo ""
    echo "管理命令:"
    echo "• 查看状态: ./status.sh"
    echo "• 查看日志: tail -f client.log"
    echo "• 停止客户端: ./stop_simple.sh"
    echo "• 重启客户端: ./restart.sh"
else
    echo "❌ 客户端启动失败"
    echo "请检查日志文件: $LOG_FILE"
    rm -f client.pid
    exit 1
fi
RUN_EOF

chmod +x "$CLIENT_DIR/run_client.sh"

# 创建统一的停止脚本（彻底停止所有自动启动）
cat > "$CLIENT_DIR/stop_simple.sh" << 'STOP_EOF'
#!/bin/bash

CLIENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$CLIENT_DIR"

echo "=== 彻底停止B-Server客户端 ==="
echo ""

# 1. 停止当前运行的进程
echo "[1] 停止当前运行的进程..."
if [ -f "client.pid" ]; then
    PID=$(cat client.pid)
    if ps -p $PID > /dev/null 2>&1; then
        kill $PID
        echo "✅ 已停止进程 PID: $PID"
        rm -f client.pid
    else
        echo "🔍 PID文件存在但进程未运行，清理PID文件"
        rm -f client.pid
    fi
else
    echo "🔍 未找到PID文件"
fi

# 强制停止所有相关进程
pkill -f "python3.*client.py" 2>/dev/null && echo "✅ 已强制停止所有client.py进程" || echo "🔍 未找到其他client.py进程"

# 2. 临时禁用systemd服务（如果存在）
echo ""
echo "[2] 检查并临时停止systemd服务..."
if command -v systemctl &> /dev/null; then
    SERVICE_NAME="b-server-client.service"
    
    # 检查服务是否存在且正在运行
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        echo "🔍 发现运行中的systemd服务，正在停止..."
        if sudo systemctl stop "$SERVICE_NAME" 2>/dev/null; then
            echo "✅ systemd服务已停止"
        else
            echo "❌ 停止systemd服务失败"
        fi
    elif systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        echo "🔍 发现已启用的systemd服务（未运行）"
        echo "ℹ️  服务已停止，但仍会在重启后自动启动"
        echo "ℹ️  如需永久禁用，请运行: sudo systemctl disable $SERVICE_NAME"
    else
        echo "🔍 未找到systemd服务"
    fi
else
    echo "🔍 系统不支持systemd"
fi

# 3. 创建临时标记文件，防止其他启动机制重启
echo ""
echo "[3] 创建停止标记文件..."
echo "$(date): 客户端已手动停止" > "$CLIENT_DIR/.stopped"
echo "✅ 已创建停止标记文件"

# 4. 检查其他可能的启动机制
echo ""
echo "[4] 检查其他自动启动机制..."

# 检查rc.local
if [ -f "/etc/rc.local" ] && grep -q "$CLIENT_DIR" /etc/rc.local; then
    echo "⚠️  发现rc.local启动项，仍会在重启后自动启动"
    echo "ℹ️  如需永久移除，请运行: sudo sed -i '\\|$CLIENT_DIR|d' /etc/rc.local"
fi

# 检查cron任务
if crontab -l 2>/dev/null | grep -q "$CLIENT_DIR"; then
    echo "⚠️  发现cron任务，仍会在重启后自动启动"
    echo "ℹ️  如需永久移除，请运行: crontab -e 并删除相关行"
fi

# 5. 显示最终状态
echo ""
echo "=== 停止完成 ==="
echo "✅ 当前进程已停止"
echo "✅ 已创建停止标记文件"
echo ""
echo "重要提示:"
echo "• 客户端当前已完全停止"
echo "• 停止标记文件可防止意外重启"
echo "• 如需重新启动: rm -f .stopped && ./run_client.sh"
echo "• 如需永久禁用自动启动，请运行: ./uninstall.sh"
echo ""
echo "启动相关命令:"
echo "• 重新启动客户端: ./run_client.sh"
echo "• 查看当前状态: ./status.sh"
echo "• 永久禁用自动启动: ./uninstall.sh"
STOP_EOF

chmod +x "$CLIENT_DIR/stop_simple.sh"

# 尝试使用systemd设置开机自启动
AUTOSTART_SUCCESS=false

if command -v systemctl &> /dev/null && [ -d "/etc/systemd/system" ]; then
    log_info "检测到systemd，创建systemd服务..."
    
    # 创建systemd服务文件
    SERVICE_FILE="/etc/systemd/system/b-server-client.service"
    
    if sudo tee "$SERVICE_FILE" > /dev/null << SYSTEMD_EOF
[Unit]
Description=B-Server Monitoring Client
After=network.target
Wants=network.target

[Service]
Type=forking
User=$USER
WorkingDirectory=$CLIENT_DIR
ExecStart=$CLIENT_DIR/run_client.sh
ExecStop=$CLIENT_DIR/stop_simple.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF
    then
        log_info "systemd服务文件已创建"
        
        # 重新加载systemd并启用服务
        if sudo systemctl daemon-reload && sudo systemctl enable b-server-client.service; then
            log_success "systemd开机自启动设置成功"
            AUTOSTART_SUCCESS=true
            
            # 显示服务状态
            log_info "服务管理命令:"
            log_info "  启动服务: sudo systemctl start b-server-client"
            log_info "  停止服务: sudo systemctl stop b-server-client"
            log_info "  查看状态: sudo systemctl status b-server-client"
            log_info "  查看日志: journalctl -u b-server-client -f"
        else
            log_warn "systemd服务启用失败，尝试其他方法"
        fi
    else
        log_warn "无法创建systemd服务文件，可能权限不足"
    fi
fi

# 如果systemd失败，使用rc.local方式
if [ "$AUTOSTART_SUCCESS" = false ]; then
    log_info "使用rc.local设置开机自启动..."
    
    # 检查rc.local是否存在
    if [ -f "/etc/rc.local" ]; then
        # 检查是否已经添加了我们的启动命令
        if ! grep -q "$CLIENT_DIR/run_client.sh" /etc/rc.local; then
            log_info "添加启动命令到rc.local..."
            
            # 备份原文件
            sudo cp /etc/rc.local /etc/rc.local.backup.$(date +%Y%m%d_%H%M%S)
            
            # 在exit 0之前添加我们的命令
            if sudo sed -i '/^exit 0/i\# B-Server Client Auto Start\nsleep 10 && su - '$USER' -c "cd '$CLIENT_DIR' && ./run_client.sh" &\n' /etc/rc.local; then
                log_success "rc.local开机自启动设置成功"
                AUTOSTART_SUCCESS=true
            else
                log_error "修改rc.local失败"
            fi
        else
            log_info "rc.local中已存在启动命令"
            AUTOSTART_SUCCESS=true
        fi
    else
        log_info "创建rc.local文件..."
        if sudo tee /etc/rc.local > /dev/null << RC_EOF
#!/bin/bash
# rc.local - executed at the end of each multiuser runlevel

# B-Server Client Auto Start
sleep 10 && su - $USER -c "cd $CLIENT_DIR && ./run_client.sh" &

exit 0
RC_EOF
        then
            sudo chmod +x /etc/rc.local
            log_success "rc.local开机自启动设置成功"
            AUTOSTART_SUCCESS=true
        else
            log_error "创建rc.local失败"
        fi
    fi
fi

# 如果都失败了，提供手动设置指导
if [ "$AUTOSTART_SUCCESS" = false ]; then
    log_error "自动设置开机自启动失败，请手动设置："
    log_error "方法1 - 添加到用户的.bashrc:"
    log_error "  echo 'cd $CLIENT_DIR && ./run_client.sh &' >> ~/.bashrc"
    log_error ""
    log_error "方法2 - 手动编辑rc.local:"
    log_error "  sudo nano /etc/rc.local"
    log_error "  在exit 0之前添加: sleep 10 && su - $USER -c 'cd $CLIENT_DIR && ./run_client.sh' &"
    log_error ""
    log_error "方法3 - 使用crontab:"
    log_error "  crontab -e"
    log_error "  添加: @reboot sleep 30 && cd $CLIENT_DIR && ./run_client.sh"
else
    log_success "开机自启动设置完成"
fi

log_info "开机自启动配置完成"
    log_info "可以使用以下命令管理服务:"
log_info "  启动: cd $CLIENT_DIR && ./run_client.sh"
log_info "  停止: cd $CLIENT_DIR && ./stop_simple.sh"
log_info "  重启: cd $CLIENT_DIR && ./restart.sh"
log_info "  查看状态: cd $CLIENT_DIR && ./status.sh"
log_info "  查看日志: cd $CLIENT_DIR && ./logs.sh"

# 测试客户端配置
log_info "测试客户端配置..."
cd "$CLIENT_DIR"
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

# 启动客户端（使用简单方式）
log_info "启动B-Server客户端..."
cd "$CLIENT_DIR"

# 使用新的简单启动脚本
if ./run_client.sh; then
    # 等待启动
    sleep 3
    
    # 检查启动状态
    if [ -f "client.pid" ] && ps -p $(cat client.pid) > /dev/null 2>&1; then
        PID=$(cat client.pid)
        log_success "B-Server客户端启动成功！(PID: $PID)"
    else
        log_error "B-Server客户端启动失败，请检查日志: $CLIENT_DIR/client.log"
        exit 1
    fi
else
    log_error "B-Server客户端启动脚本执行失败"
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
echo "  启动客户端: cd $CLIENT_DIR && ./run_client.sh"
echo "  停止客户端: cd $CLIENT_DIR && ./stop_simple.sh"
echo "  查看状态: cd $CLIENT_DIR && ./status.sh"
echo "  查看日志: cd $CLIENT_DIR && ./logs.sh"
echo "  重启服务: cd $CLIENT_DIR && ./restart.sh"
echo "  更新客户端: cd $CLIENT_DIR && ./update.sh"
echo "  修复开机自启动: cd $CLIENT_DIR && ./fix_autostart.sh"
echo "  卸载客户端: cd $CLIENT_DIR && ./uninstall.sh"
echo ""
echo "开机自启动："
if [ "$AUTOSTART_SUCCESS" = true ]; then
    if command -v systemctl &> /dev/null && systemctl is-enabled b-server-client.service &>/dev/null; then
        echo "  ✅ 已通过systemd设置开机自启动"
        echo "  管理服务: sudo systemctl start/stop/restart b-server-client"
        echo "  查看状态: sudo systemctl status b-server-client"
        echo "  查看日志: journalctl -u b-server-client -f"
        echo "  禁用自启动: sudo systemctl disable b-server-client.service"
    elif grep -q "$CLIENT_DIR/run_client.sh" /etc/rc.local 2>/dev/null; then
        echo "  ✅ 已通过rc.local设置开机自启动"
        echo "  管理方式: 编辑 /etc/rc.local 文件"
        echo "  移除自启动: sudo sed -i '/B-Server Client Auto Start/,+1d' /etc/rc.local"
    else
        echo "  ✅ 开机自启动已设置"
    fi
else
    echo "  ⚠️  开机自启动设置失败"
    echo "  请运行修复脚本: cd $CLIENT_DIR && ./fix_autostart.sh"
    echo "  或手动设置: 编辑 /etc/rc.local 添加启动命令"
fi
    echo ""
echo "重要提示:"
echo "  1. 请确保在服务器管理面板中添加了节点 '$NODE_NAME'"
echo "  2. 请确保服务器防火墙允许8008端口访问"
echo "  3. 客户端日志位置: $CLIENT_DIR/client.log"
echo "  4. 新版本使用简单的PID管理，不再依赖supervisor"
echo "  5. 使用 ./run_client.sh 和 ./stop_simple.sh 来控制服务"
echo "  6. 停止客户端时会创建停止标记文件，防止自动重启"
echo "  7. 如需重新启动已停止的客户端，运行 ./run_client.sh 即可"
echo ""
log_info "安装完成！客户端正在运行中..." 