# B-Server 客户端 Windows 安装脚本
# 使用方法: 
# 方法1(推荐): powershell -ExecutionPolicy Bypass -Command "iwr -Uri 'https://raw.githubusercontent.com/xhhcn/B-server/refs/heads/main/client/install_client.ps1' -UseBasicParsing | iex; Install-BServerClient -ServerIP '192.168.1.100' -NodeName 'MyServer'"
# 方法2: .\install_client.ps1 -ServerIP "192.168.1.100" -NodeName "MyServer"
#
# 特殊字符处理:
# 如果NodeName包含特殊符号（如美元符号），请使用以下方式之一：
# 1. 转义符号：powershell -ExecutionPolicy Bypass -Command "iwr -Uri 'https://raw.githubusercontent.com/xhhcn/B-server/refs/heads/main/client/install_client.ps1' -UseBasicParsing | iex; Install-BServerClient -ServerIP '51.81.222.49' -NodeName 'Layer(`$29.9/Y)'"
# 2. 使用Base64编码：powershell -ExecutionPolicy Bypass -Command "iwr -Uri 'https://raw.githubusercontent.com/xhhcn/B-server/refs/heads/main/client/install_client.ps1' -UseBasicParsing | iex; Install-BServerClient -ServerIP '51.81.222.49' -NodeNameBase64 'TGF5ZXIoJDI5LjkvWSk='"
# 3. 下载脚本后本地运行：iwr -Uri 'https://raw.githubusercontent.com/xhhcn/B-server/refs/heads/main/client/install_client.ps1' -OutFile install_client.ps1; .\install_client.ps1 -ServerIP "51.81.222.49" -NodeName "Layer(`$29.9/Y)"
# 4. 生成Base64编码：[System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('Your-Node-Name'))
#
# SSL证书问题处理:
# 如果遇到SSL证书验证失败错误，脚本会自动尝试以下解决方案：
# 1. 使用可信主机参数绕过SSL验证：--trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org
# 2. 增加重试次数和超时时间
# 3. 如果自动修复失败，请手动运行以下命令：
#    cd %USERPROFILE%\b-server-client
#    .\venv\Scripts\python.exe -m pip install --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org psutil python-socketio requests tcping

param(
    [Parameter(Mandatory=$false)]
    [string]$ServerIP,
    
    [Parameter(Mandatory=$false)]
    [string]$NodeName = $env:COMPUTERNAME,
    
    [Parameter(Mandatory=$false)]
    [string]$NodeNameBase64
)

# 设置控制台编码为UTF-8
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    # 忽略编码设置错误
}

# 颜色输出函数
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    
    switch ($Color) {
        "Red" { Write-Host $Message -ForegroundColor Red }
        "Green" { Write-Host $Message -ForegroundColor Green }
        "Yellow" { Write-Host $Message -ForegroundColor Yellow }
        "Blue" { Write-Host $Message -ForegroundColor Blue }
        default { Write-Host $Message }
    }
}

function Install-BServerClient {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ServerIP,
        
        [Parameter(Mandatory=$false)]
        [string]$NodeName = $env:COMPUTERNAME,
        
        [Parameter(Mandatory=$false)]
        [string]$NodeNameBase64
    )

    # 处理Base64编码的节点名称
    if (-not [string]::IsNullOrWhiteSpace($NodeNameBase64)) {
        try {
            $NodeName = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($NodeNameBase64))
            Write-ColorOutput "[INFO] Decoded NodeName from Base64: '$NodeName'" "Blue"
        }
        catch {
            Write-ColorOutput "[ERROR] Failed to decode NodeNameBase64: $($_.Exception.Message)" "Red"
            exit 1
        }
    }
    
    # 验证参数
    if ([string]::IsNullOrWhiteSpace($ServerIP)) {
        Write-ColorOutput "[ERROR] ServerIP parameter is null or empty" "Red"
        exit 1
    }
    
    if ([string]::IsNullOrWhiteSpace($NodeName)) {
        $NodeName = $env:COMPUTERNAME
    }

    Write-ColorOutput "[INFO] Starting B-Server client installation..." "Blue"
    Write-ColorOutput ("[INFO] Server address: " + $ServerIP + ":8008") "Blue"
    Write-ColorOutput ("[INFO] Node name: " + $NodeName) "Blue"
    Write-ColorOutput ("[DEBUG] Raw ServerIP: '" + $ServerIP + "'") "Yellow"
    Write-ColorOutput ("[DEBUG] Raw NodeName: '" + $NodeName + "'") "Yellow"
    
    # 检查节点名称是否包含特殊字符并提供建议
    $dollarSign = '$'
    $hasSpecialChars = $NodeName.Contains($dollarSign) -or $NodeName.Contains('(') -or $NodeName.Contains(')') -or $NodeName.Contains('[') -or $NodeName.Contains(']') -or $NodeName.Contains('&') -or $NodeName.Contains('|')
    if ($hasSpecialChars) {
        Write-ColorOutput "[WARNING] Node name contains special characters that may cause issues!" "Yellow"
        $base64NodeName = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($NodeName))
        Write-ColorOutput ("[SUGGESTION] For better compatibility, use Base64 encoding: -NodeNameBase64 '" + $base64NodeName + "'") "Yellow"
        Write-ColorOutput "[SUGGESTION] Complete command:" "Yellow"
        $suggestedCommand = 'powershell -ExecutionPolicy Bypass -Command "iwr -Uri ''https://raw.githubusercontent.com/xhhcn/B-server/refs/heads/main/client/install_client.ps1'' -UseBasicParsing | iex; Install-BServerClient -ServerIP ''' + $ServerIP + ''' -NodeNameBase64 ''' + $base64NodeName + '''"'
        Write-ColorOutput $suggestedCommand "Cyan"
        Write-Host ""
    }

    # Configuration variables
    $ClientDir = Join-Path $env:USERPROFILE "b-server-client"
    $ClientFile = Join-Path $ClientDir "client.py"
    $ClientURL = "https://raw.githubusercontent.com/xhhcn/B-server/refs/heads/main/client/client.py"

    Write-ColorOutput ("[INFO] Installation directory: " + $ClientDir) "Blue"

    # Check system dependencies
    Write-ColorOutput "[INFO] Checking system dependencies..." "Blue"

    # Check Python
    try {
        $pythonVersion = python --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Python not found"
        }
        Write-ColorOutput "[SUCCESS] Python installed: $pythonVersion" "Green"
    }
    catch {
        Write-ColorOutput "[ERROR] Python not installed, please install Python 3.7+" "Red"
        Write-ColorOutput "[INFO] Download from: https://www.python.org/downloads/" "Yellow"
        exit 1
    }

    # Check pip
    try {
        $pipVersion = pip --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "pip not found"
        }
        Write-ColorOutput "[SUCCESS] pip installed: $pipVersion" "Green"
    }
    catch {
        Write-ColorOutput "[ERROR] pip not installed, please ensure Python is correctly installed" "Red"
        exit 1
    }

    # Create installation directory
    Write-ColorOutput "[INFO] Creating installation directory..." "Blue"
    if (!(Test-Path -Path $ClientDir)) {
        New-Item -ItemType Directory -Path $ClientDir -Force | Out-Null
    }
    Set-Location -Path $ClientDir

    # Download client file
    Write-ColorOutput "[INFO] Downloading client file..." "Blue"
    try {
        Invoke-WebRequest -Uri $ClientURL -OutFile "client.py" -UseBasicParsing
        if (!(Test-Path -Path "client.py")) {
            throw "Download failed"
        }
        Write-ColorOutput "[SUCCESS] Client file downloaded successfully" "Green"
    }
    catch {
        Write-ColorOutput "[ERROR] Client file download failed: $($_.Exception.Message)" "Red"
        exit 1
    }

    # Modify client configuration
    Write-ColorOutput "[INFO] Modifying client configuration..." "Blue"
    
    try {
        $content = Get-Content -Path "client.py" -Raw -Encoding UTF8
        
        # 修改SERVER_URL - 使用单引号避免变量展开
        $newServerUrl = 'SERVER_URL = ''http://' + $ServerIP + ':8008'''
        $content = $content -replace "SERVER_URL = 'http://localhost:8008'", $newServerUrl
        
        # 修改NODE_NAME - 安全处理特殊字符，避免PowerShell变量展开
        # 使用单引号字符串拼接，避免$符号被解释为变量
        $newNodeName = 'NODE_NAME = ''' + $NodeName + ''''
        $content = $content -replace "NODE_NAME = socket\.gethostname\(\)", $newNodeName
        
        Set-Content -Path "client.py" -Value $content -Encoding UTF8
        
        # 验证修改是否成功
        $verifyContent = Get-Content -Path "client.py" -Raw -Encoding UTF8
        
        # 检查SERVER_URL是否修改成功 - 使用单引号避免变量展开
        $expectedServerUrl = 'SERVER_URL = ''http://' + $ServerIP + ':8008'''
        $serverUrlFound = $verifyContent.Contains($expectedServerUrl)
        
        # 检查NODE_NAME是否修改成功 - 使用单引号避免变量展开
        $expectedNodeName = 'NODE_NAME = ''' + $NodeName + ''''
        $nodeNameFound = $verifyContent.Contains($expectedNodeName)
        
        Write-ColorOutput ("[DEBUG] Expected Server URL: " + $expectedServerUrl) "Yellow"
        Write-ColorOutput ("[DEBUG] Server URL found: " + $serverUrlFound) "Yellow"
        Write-ColorOutput ("[DEBUG] Expected Node Name: " + $expectedNodeName) "Yellow"
        Write-ColorOutput ("[DEBUG] Node Name found: " + $nodeNameFound) "Yellow"
        
        # 额外验证：显示实际的节点名称长度和内容
        Write-ColorOutput ("[DEBUG] Node Name length: " + $NodeName.Length) "Yellow"
        Write-ColorOutput ("[DEBUG] Node Name bytes: " + [System.Text.Encoding]::UTF8.GetBytes($NodeName).Length) "Yellow"
        $dollarSign = '$'
        Write-ColorOutput ("[DEBUG] Node Name contains dollar sign: " + $NodeName.Contains($dollarSign)) "Yellow"
        
        if ($serverUrlFound -and $nodeNameFound) {
            Write-ColorOutput "[SUCCESS] Client configuration modified successfully" "Green"
            Write-ColorOutput ("[INFO] Server URL: http://" + $ServerIP + ":8008") "Blue"
            Write-ColorOutput ("[INFO] Node Name: " + $NodeName) "Blue"
        } else {
            # 显示实际的配置内容用于调试
            $relevantLines = $verifyContent -split "`n" | Where-Object { $_ -match "SERVER_URL|NODE_NAME" } | Select-Object -First 10
            Write-ColorOutput "[DEBUG] Actual configuration lines:" "Yellow"
            foreach ($line in $relevantLines) {
                Write-ColorOutput "[DEBUG] $line" "Yellow"
            }
            throw "Configuration verification failed - Expected patterns not found"
        }
    }
    catch {
        Write-ColorOutput "[ERROR] Configuration file modification failed: $($_.Exception.Message)" "Red"
        Write-ColorOutput ("[DEBUG] ServerIP: '" + $ServerIP + "'") "Yellow"
        Write-ColorOutput ("[DEBUG] NodeName: '" + $NodeName + "'") "Yellow"
        
        # 显示文件的前几行用于调试
        try {
            $filePreview = Get-Content -Path "client.py" -TotalCount 20 -Encoding UTF8
            Write-ColorOutput "[DEBUG] First 20 lines of client.py:" "Yellow"
            for ($i = 0; $i -lt $filePreview.Length; $i++) {
                Write-ColorOutput "[DEBUG] $($i+1): $($filePreview[$i])" "Yellow"
            }
        } catch {
            Write-ColorOutput "[DEBUG] Could not read client.py for debugging" "Yellow"
        }
        exit 1
    }

    # Create Python virtual environment
    Write-ColorOutput "[INFO] Creating Python virtual environment..." "Blue"
    try {
        python -m venv venv
        if ($LASTEXITCODE -ne 0) {
            throw "Virtual environment creation failed"
        }
        Write-ColorOutput "[SUCCESS] Virtual environment created successfully" "Green"
    }
    catch {
        Write-ColorOutput "[ERROR] Virtual environment creation failed: $($_.Exception.Message)" "Red"
        exit 1
    }

    # Activate virtual environment and install dependencies
    Write-ColorOutput "[INFO] Installing Python dependencies..." "Blue"
    
    # 定义要安装的包
    $packages = @("psutil", "python-socketio", "requests", "tcping", "python-socketio[client]")
    $installSuccess = $false
    
    try {
        # 首先尝试标准安装
        Write-ColorOutput "[INFO] Attempting standard installation..." "Blue"
        & ".\venv\Scripts\python.exe" -m pip install --upgrade pip
        & ".\venv\Scripts\python.exe" -m pip install $packages
        
        if ($LASTEXITCODE -eq 0) {
            $installSuccess = $true
            Write-ColorOutput "[SUCCESS] Standard installation completed successfully" "Green"
        }
    }
    catch {
        Write-ColorOutput "[WARNING] Standard installation failed, trying alternatives..." "Yellow"
    }
    
    # 如果标准安装失败，尝试使用可信主机
    if (-not $installSuccess) {
        try {
            Write-ColorOutput "[INFO] Attempting installation with trusted hosts (SSL bypass)..." "Blue"
            Write-ColorOutput "[INFO] This may be needed due to corporate firewall or SSL certificate issues" "Yellow"
            
            # 升级pip（使用可信主机）
            & ".\venv\Scripts\python.exe" -m pip install --upgrade pip --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org
            
            # 安装依赖包（使用可信主机）
            & ".\venv\Scripts\python.exe" -m pip install $packages --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org
            
            if ($LASTEXITCODE -eq 0) {
                $installSuccess = $true
                Write-ColorOutput "[SUCCESS] Installation with trusted hosts completed successfully" "Green"
            }
        }
        catch {
            Write-ColorOutput "[WARNING] Trusted hosts installation failed, trying offline cache..." "Yellow"
        }
    }
    
    # 如果仍然失败，尝试使用pip缓存
    if (-not $installSuccess) {
        try {
            Write-ColorOutput "[INFO] Attempting installation with pip cache and retries..." "Blue"
            
            # 使用重试和缓存
            & ".\venv\Scripts\python.exe" -m pip install --upgrade pip --retries 5 --timeout 60 --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org
            & ".\venv\Scripts\python.exe" -m pip install $packages --retries 5 --timeout 60 --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org
            
            if ($LASTEXITCODE -eq 0) {
                $installSuccess = $true
                Write-ColorOutput "[SUCCESS] Installation with retries completed successfully" "Green"
            }
        }
        catch {
            Write-ColorOutput "[ERROR] All installation methods failed" "Red"
        }
    }
    
    # 验证安装结果
    if ($installSuccess) {
        Write-ColorOutput "[SUCCESS] Python dependencies installed successfully" "Green"
        
        # 验证关键模块是否可以导入
        Write-ColorOutput "[INFO] Verifying installed packages..." "Blue"
        $verifyResult = & ".\venv\Scripts\python.exe" -c "import psutil, socketio, requests; print('All packages verified successfully')" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput "[SUCCESS] Package verification completed" "Green"
        } else {
            Write-ColorOutput "[WARNING] Some packages may not be properly installed: $verifyResult" "Yellow"
        }
    } else {
        Write-ColorOutput "[ERROR] Dependencies installation failed after trying all methods" "Red"
        Write-ColorOutput "" "White"
        Write-ColorOutput "Possible solutions:" "Yellow"
        Write-ColorOutput "1. Check your internet connection" "Yellow"
        Write-ColorOutput "2. Configure corporate proxy settings if behind firewall" "Yellow"
        Write-ColorOutput "3. Update Windows certificates: certlm.msc" "Yellow"
        Write-ColorOutput "4. Run the SSL fix script after installation completes: fix_ssl.bat" "Yellow"
        Write-ColorOutput "5. Run the following commands manually:" "Yellow"
        Write-ColorOutput "   cd `"$((Get-Location).Path)`"" "White"
        Write-ColorOutput "   .\venv\Scripts\python.exe -m pip install --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org psutil python-socketio requests tcping" "White"
        Write-ColorOutput "" "White"
        Write-ColorOutput "[INFO] Continuing with installation despite package installation issues..." "Yellow"
        Write-ColorOutput "[INFO] You can run fix_ssl.bat later to resolve SSL certificate problems" "Yellow"
        Write-ColorOutput "" "White"
        # Don't exit here - continue with creating scripts so user can run fix_ssl.bat later
    }

    # Create startup scripts
    Write-ColorOutput "[INFO] Creating management scripts..." "Blue"
    
    # 启动脚本 - 使用占位符避免变量展开问题
    $startScript = (@'
@echo off
cd /d "%~dp0"
echo Starting B-Server Client...
echo Server: {0}:8008
echo Node: {1}
echo.
venv\Scripts\python.exe client.py
if errorlevel 1 (
    echo.
    echo [ERROR] Client failed to start. Error code: %errorlevel%
    echo Check the following:
    echo 1. Server {0}:8008 is accessible
    echo 2. Node '{1}' is added in admin panel
    echo 3. Firewall allows outbound connections to port 8008
    echo.
)
pause
'@) -f $ServerIP, $NodeName
    Set-Content -Path "start.bat" -Value $startScript -Encoding UTF8

    # 后台启动脚本 - 使用占位符避免变量展开问题
    $startBackgroundScript = (@'
@echo off
cd /d "%~dp0"
echo Starting B-Server Client in background...
echo Server: {0}:8008
echo Node: {1}
echo.

REM 先停止现有进程
taskkill /f /im python.exe 2>nul
taskkill /f /im pythonw.exe 2>nul

REM 启动新进程
start /min cmd /c "venv\Scripts\pythonw.exe client.py"

REM 等待进程启动
timeout /t 2 /nobreak >nul

REM 检查是否启动成功
tasklist /fi "IMAGENAME eq pythonw.exe" 2>nul | find "pythonw.exe" >nul
if %errorlevel%==0 (
    echo B-Server Client started successfully in background
) else (
    echo [ERROR] Failed to start client in background
    echo Try running start.bat to see detailed error messages
)
echo.
'@) -f $ServerIP, $NodeName
    Set-Content -Path "start_background.bat" -Value $startBackgroundScript -Encoding UTF8

    # 停止脚本 - 修复版本，使用标准ASCII字符确保兼容性
    $stopScript = @"
@echo off
echo ==========================================
echo        B-Server Client Stop Script
echo ==========================================
echo.

echo [1] Stopping B-Server Client processes...

echo    - Attempting to stop python.exe processes...
taskkill /f /im python.exe >nul 2>&1
if %errorlevel%==0 (
    echo      [OK] python.exe processes stopped
) else (
    echo      [INFO] No python.exe processes found
)

echo    - Attempting to stop pythonw.exe processes...
taskkill /f /im pythonw.exe >nul 2>&1
if %errorlevel%==0 (
    echo      [OK] pythonw.exe processes stopped
) else (
    echo      [INFO] No pythonw.exe processes found
)

echo.
echo [2] Verifying processes are stopped...

tasklist /fi "IMAGENAME eq python.exe" 2>nul | find "python.exe" >nul
if %errorlevel%==0 (
    echo    [WARNING] Some python.exe processes are still running
    echo    Active python.exe processes:
    tasklist /fi "IMAGENAME eq python.exe" 2>nul
) else (
    echo    [OK] No python.exe processes found
)

tasklist /fi "IMAGENAME eq pythonw.exe" 2>nul | find "pythonw.exe" >nul
if %errorlevel%==0 (
    echo    [WARNING] Some pythonw.exe processes are still running
    echo    Active pythonw.exe processes:
    tasklist /fi "IMAGENAME eq pythonw.exe" 2>nul
) else (
    echo    [OK] No pythonw.exe processes found
)

echo.
echo [3] Additional stop methods:
echo    If processes are still running, try these commands manually:
echo    - taskkill /f /im python.exe
echo    - taskkill /f /im pythonw.exe
echo    - Use Task Manager to end processes manually

echo.
echo ==========================================
echo Stop script completed!
echo ==========================================
pause
"@
    Set-Content -Path "stop.bat" -Value $stopScript -Encoding UTF8

    # 状态检查脚本 - 使用占位符避免变量展开问题
    $statusScript = (@'
@echo off
echo ========================================
echo B-Server Client Status Check
echo ========================================
echo Server: {0}:8008
echo Node: {1}
echo Installation: %~dp0
echo.
echo Checking processes...
tasklist /fi "IMAGENAME eq python.exe" 2>nul | find "python.exe" >nul
if %errorlevel%==0 (
    echo [STATUS] B-Server Client is running (foreground)
    tasklist /fi "IMAGENAME eq python.exe" 2>nul
) else (
    tasklist /fi "IMAGENAME eq pythonw.exe" 2>nul | find "pythonw.exe" >nul
    if %errorlevel%==0 (
        echo [STATUS] B-Server Client is running (background)
        tasklist /fi "IMAGENAME eq pythonw.exe" 2>nul
    ) else (
        echo [STATUS] B-Server Client is not running
        echo.
        echo To start the client:
        echo   Foreground: start.bat
        echo   Background: start_background.bat
        echo.
        echo To troubleshoot:
        echo   1. Run start.bat to see error messages
        echo   2. Check if server {0}:8008 is accessible
        echo   3. Ensure node '{1}' exists in admin panel
    )
)
echo.
pause
'@) -f $ServerIP, $NodeName
    Set-Content -Path "status.bat" -Value $statusScript -Encoding UTF8

    # 调试脚本 - 使用占位符避免变量展开问题
    $debugScript = (@'
@echo off
cd /d "%~dp0"
echo ========================================
echo B-Server Client Debug Information
echo ========================================
echo Server: {0}:8008
echo Node: {1}
echo Installation: %~dp0
echo Time: %date% %time%
echo.

echo [1] Testing Python environment...
venv\Scripts\python.exe --version
if errorlevel 1 (
    echo [ERROR] Python environment not working
    goto :end
)

echo [2] Testing Python modules...
venv\Scripts\python.exe -c "import sys, psutil, socketio, requests; print('All modules imported successfully')"
if errorlevel 1 (
    echo [ERROR] Python modules missing or broken
    echo.
    echo [SSL FIX] If you see SSL certificate errors, try:
    echo   venv\Scripts\python.exe -m pip install --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org psutil python-socketio requests tcping
    echo.
    echo [CORPORATE NETWORK] If behind corporate firewall:
    echo   1. Contact IT for proxy settings
    echo   2. Or use: venv\Scripts\python.exe -m pip install --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org --proxy http://proxy:port packages
    echo.
    goto :end
)

echo [3] Testing SSL/TLS connectivity...
venv\Scripts\python.exe -c "import ssl, socket; print('SSL version: ' + ssl.ssl_version); print('SSL connectivity test passed')"
if errorlevel 1 (
    echo [WARNING] SSL/TLS connectivity issues detected
    echo This may cause problems with pip and network requests
    echo.
    echo [SSL TROUBLESHOOTING]
    echo 1. Check system date and time
    echo 2. Run: certlm.msc to manage certificates
    echo 3. Contact IT if on corporate network
    echo.
) else (
    echo [SUCCESS] SSL/TLS connectivity OK
)

echo [4] Testing network connectivity...
ping -n 1 {0} >nul
if errorlevel 1 (
    echo [ERROR] Cannot reach server {0}
    echo Check network connection and firewall
    goto :end
) else (
    echo Server {0} is reachable
)

echo [5] Testing client configuration...
echo Checking configuration file...
findstr /C:"SERVER_URL" client.py
findstr /C:"NODE_NAME" client.py
echo Configuration check completed

echo [6] Starting client with verbose output...
echo Press Ctrl+C to stop
venv\Scripts\python.exe client.py

:end
pause
'@) -f $ServerIP, $NodeName
    Set-Content -Path "debug.bat" -Value $debugScript -Encoding UTF8

    # 更新脚本 - 使用占位符避免变量展开问题
    $updateScript = (@'
@echo off
cd /d "%~dp0"
echo ========================================
echo B-Server Client Update Script
echo ========================================
echo.

echo [1] Stopping client...
taskkill /f /im python.exe 2>nul
taskkill /f /im pythonw.exe 2>nul

echo [2] Downloading latest client...
powershell -Command "Invoke-WebRequest -Uri '{0}' -OutFile 'client.py.new' -UseBasicParsing"

if exist client.py.new (
    echo [3] Updating configuration...
    powershell -Command "(Get-Content 'client.py.new') -replace \"SERVER_URL = 'http://localhost:8008'\", \"SERVER_URL = 'http://{1}:8008'\" -replace \"NODE_NAME = socket\.gethostname\(\)\", \"NODE_NAME = '{2}'\" | Set-Content 'client.py.new'"
    
    move client.py client.py.backup
    move client.py.new client.py
    echo [4] Client updated successfully
    echo.
    echo [5] Updating Python packages...
    echo First trying standard installation...
    venv\Scripts\python.exe -m pip install --upgrade psutil python-socketio requests tcping
    if errorlevel 1 (
        echo Standard installation failed, trying with SSL bypass...
        venv\Scripts\python.exe -m pip install --upgrade --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org psutil python-socketio requests tcping
        if errorlevel 1 (
            echo [WARNING] Package update failed
            echo [SSL FIX] If you see SSL certificate errors, the client may still work
            echo [SSL FIX] For manual fix: venv\Scripts\python.exe -m pip install --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org --upgrade psutil python-socketio requests tcping
        ) else (
            echo [SUCCESS] Packages updated with SSL bypass
        )
    ) else (
        echo [SUCCESS] Packages updated successfully
    )
    echo.
    echo Update completed! You can now start the client.
) else (
    echo [ERROR] Download failed
    echo [TROUBLESHOOTING]
    echo 1. Check internet connection
    echo 2. Check firewall settings
    echo 3. Try running as administrator
)
pause
'@) -f $ClientURL, $ServerIP, $NodeName
    Set-Content -Path "update.bat" -Value $updateScript -Encoding UTF8

    # SSL修复脚本 - 专门处理SSL证书问题
    $sslFixScript = @'
@echo off
cd /d "%~dp0"
echo ========================================
echo B-Server Client SSL Certificate Fix
echo ========================================
echo.
echo This script will attempt to fix SSL certificate issues
echo that may prevent Python packages from installing.
echo.

echo [1] Checking current SSL configuration...
venv\Scripts\python.exe -c "import ssl; print('SSL version: ' + ssl.ssl_version); print('Current SSL configuration OK')"
if errorlevel 1 (
    echo [WARNING] SSL configuration issues detected
)

echo.
echo [2] Attempting to reinstall packages with SSL bypass...
echo This uses --trusted-host to bypass SSL certificate verification
echo.

echo Upgrading pip...
venv\Scripts\python.exe -m pip install --upgrade pip --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org --retries 5 --timeout 60

echo.
echo Installing core packages...
venv\Scripts\python.exe -m pip install --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org --retries 5 --timeout 60 psutil python-socketio requests tcping "python-socketio[client]"

if errorlevel 1 (
    echo.
    echo [ERROR] Package installation still failed
    echo.
    echo [MANUAL SOLUTIONS]
    echo 1. Check system date and time (wrong time causes SSL errors)
    echo 2. Run 'certlm.msc' to manage certificates
    echo 3. Contact IT administrator if on corporate network
    echo 4. Try using a different network (mobile hotspot)
    echo 5. Download packages manually from PyPI
    echo.
    echo [CORPORATE NETWORK USERS]
    echo If behind corporate firewall/proxy, ask IT for:
    echo - Proxy server address and port
    echo - SSL certificate bundle
    echo - Firewall rules for Python package installation
    echo.
    echo [MANUAL PROXY CONFIGURATION]
    echo If you know your proxy settings, try:
    echo   venv\Scripts\python.exe -m pip install --proxy http://proxy:port --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org psutil python-socketio requests tcping
    echo.
) else (
    echo.
    echo [SUCCESS] SSL certificate fix completed!
    echo Python packages have been installed successfully.
    echo.
    echo [VERIFICATION]
    echo Testing module imports...
    venv\Scripts\python.exe -c "import psutil, socketio, requests; print('All modules imported successfully')"
    if errorlevel 1 (
        echo [WARNING] Some modules may not work properly
    ) else (
        echo [SUCCESS] All modules verified successfully
    )
)

echo.
echo ========================================
echo SSL Fix Script Completed
echo ========================================
pause
'@
    Set-Content -Path "fix_ssl.bat" -Value $sslFixScript -Encoding UTF8

    Write-ColorOutput "[SUCCESS] Management scripts created successfully" "Green"

    # 创建Windows服务脚本（可选）
    $serviceScript = @"
# Windows Service Installation Script
# Run as Administrator

`$serviceName = "BServerClient"
`$serviceDisplayName = "B-Server Monitoring Client"
`$servicePath = Join-Path (Get-Location) "venv\Scripts\pythonw.exe"
`$serviceArgs = Join-Path (Get-Location) "client.py"

# Install service using NSSM (Non-Sucking Service Manager)
# Download NSSM from: https://nssm.cc/download

Write-Host "To install as Windows Service:"
Write-Host "1. Download NSSM from https://nssm.cc/download"
Write-Host "2. Extract nssm.exe to this directory"
Write-Host "3. Run as Administrator: .\nssm.exe install `$serviceName `$servicePath `$serviceArgs"
Write-Host "4. Run: .\nssm.exe start `$serviceName"
"@
    Set-Content -Path "install_service.ps1" -Value $serviceScript -Encoding UTF8

    Write-ColorOutput "[SUCCESS] Management scripts created successfully" "Green"

    # Test client configuration
    Write-ColorOutput "[INFO] Testing client configuration..." "Blue"
    try {
        # Test 1: Check if Python modules can be imported
        $moduleTest = & ".\venv\Scripts\python.exe" -c "import socket, psutil, socketio, requests; print('All modules imported successfully')" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput "[SUCCESS] All dependency modules imported successfully" "Green"
        } else {
            Write-ColorOutput "[ERROR] Dependency module import failed: $moduleTest" "Red"
            throw "Module import test failed"
        }

        # Test 2: Check if client.py file exists and has correct configuration
        if (Test-Path "client.py") {
            $clientContent = Get-Content "client.py" -Raw -Encoding UTF8
            
            # Check server URL configuration
            $expectedServerUrl = "SERVER_URL = 'http://$ServerIP`:8008'"
            if ($clientContent -match [regex]::Escape($expectedServerUrl)) {
                Write-ColorOutput "[SUCCESS] Server address configured correctly" "Green"
            } else {
                Write-ColorOutput "[ERROR] Server address configuration error" "Red"
                Write-ColorOutput "[DEBUG] Expected: $expectedServerUrl" "Yellow"
                throw "Server URL configuration test failed"
            }
            
            # Check node name configuration
            $expectedNodeName = "NODE_NAME = '$NodeName'"
            if ($clientContent -match [regex]::Escape($expectedNodeName)) {
                Write-ColorOutput "[SUCCESS] Node name configured correctly" "Green"
            } else {
                Write-ColorOutput "[ERROR] Node name configuration error" "Red"
                Write-ColorOutput "[DEBUG] Expected: $expectedNodeName" "Yellow"
                throw "Node name configuration test failed"
            }
            
            Write-ColorOutput "[SUCCESS] Client configuration test passed" "Green"
        } else {
            Write-ColorOutput "[ERROR] client.py file not found" "Red"
            throw "Client file test failed"
        }
    }
    catch {
        Write-ColorOutput "[ERROR] Client configuration test failed: $($_.Exception.Message)" "Red"
        Write-ColorOutput "[INFO] Continuing with installation..." "Yellow"
        # Don't exit due to test failure, continue installation process
        
        # Provide debugging information
        Write-ColorOutput "[DEBUG] Configuration file verification:" "Yellow"
        if (Test-Path "client.py") {
            $debugContent = Get-Content "client.py" -TotalCount 30 -Encoding UTF8
            Write-ColorOutput "[DEBUG] First 30 lines of client.py:" "Yellow"
            for ($i = 0; $i -lt $debugContent.Length; $i++) {
                if ($debugContent[$i] -match "SERVER_URL|NODE_NAME") {
                    Write-ColorOutput "[DEBUG] Line $($i+1): $($debugContent[$i])" "Cyan"
                }
            }
        } else {
            Write-ColorOutput "[DEBUG] client.py file does not exist" "Yellow"
        }
    }

    # Display installation completion information
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-ColorOutput "[SUCCESS] B-Server Client installation completed successfully!" "Green"
    Write-ColorOutput "" "White"
    Write-ColorOutput "Installation Information:" "Blue"
    Write-Host ("  Installation Directory: " + $ClientDir)
    Write-Host ("  Server Address: " + $ServerIP + ":8008")
    Write-Host ("  Node Name: " + $NodeName)
    Write-Host ""
    Write-ColorOutput "Management Commands:" "Blue"
    Write-Host "  Start (foreground):  start.bat"
    Write-Host "  Start (background):  start_background.bat"
    Write-Host "  Stop client:         stop.bat"
    Write-Host "  Check status:        status.bat"
    Write-Host "  Debug issues:        debug.bat"
    Write-Host "  Update client:       update.bat"
    Write-Host "  Fix SSL issues:      fix_ssl.bat"
    Write-Host ""
    Write-ColorOutput "Important Notes:" "Yellow"
    Write-Host "  - On Windows, TCPing uses Python implementation to avoid CMD popups"
    Write-Host "  - Client will run silently in background when using start_background.bat"
    Write-Host ("  - Ensure the node '" + $NodeName + "' is added in the admin panel")
    Write-Host "  - Check firewall allows outbound connections to port 8008"
    Write-Host "  - If you encountered SSL certificate errors during installation, run fix_ssl.bat"
    Write-Host ""
    
    # Ask whether to start immediately
    if ($installSuccess) {
        $choice = Read-Host "Start client immediately? (Y/N)"
        if ($choice -eq 'Y' -or $choice -eq 'y') {
            Write-ColorOutput "[INFO] Starting B-Server client..." "Blue"
            Write-Host "Starting client in background..."
            & ".\start_background.bat"
            Start-Sleep -Seconds 3
            Write-Host ""
            Write-ColorOutput "[INFO] Checking status..." "Blue"
            & ".\status.bat"
        } else {
            Write-ColorOutput "[INFO] To start later, run: .\start_background.bat" "Blue"
            Write-ColorOutput "[INFO] For troubleshooting, run: .\debug.bat" "Blue"
        }
    } else {
        Write-ColorOutput "[WARNING] Package installation failed - client may not work properly" "Yellow"
        Write-ColorOutput "[INFO] Before starting the client, run: .\fix_ssl.bat" "Yellow"
        Write-ColorOutput "[INFO] After fixing SSL issues, you can start with: .\start_background.bat" "Blue"
        Write-ColorOutput "[INFO] For troubleshooting, run: .\debug.bat" "Blue"
    }
    
    Write-ColorOutput "[INFO] Installation completed!" "Green"
}

# 主逻辑：处理直接运行脚本的情况
# 只有在直接运行脚本文件（而不是通过iex执行）时才检查参数
if ($MyInvocation.InvocationName -match '\.ps1$') {
    # 这是直接运行脚本文件的情况
    if (-not $ServerIP -or (-not $NodeName -and -not $NodeNameBase64)) {
        Write-ColorOutput "[ERROR] Missing required parameters" "Red"
        Write-ColorOutput "[INFO] Usage:" "Blue"
        Write-Host "  Local run: .\install_client.ps1 -ServerIP '<ServerIP>' -NodeName '<NodeName>'"
        Write-Host "  Local run (Base64): .\install_client.ps1 -ServerIP '<ServerIP>' -NodeNameBase64 '<Base64EncodedNodeName>'"
        Write-Host "  One-click: powershell -ExecutionPolicy Bypass -Command `"iwr -Uri 'https://raw.githubusercontent.com/xhhcn/B-server/refs/heads/main/client/install_client.ps1' -UseBasicParsing | iex; Install-BServerClient -ServerIP '<ServerIP>' -NodeName '<NodeName>'`""
        Write-Host ""
        Write-ColorOutput "[INFO] Examples:" "Blue"
        Write-Host "  .\install_client.ps1 -ServerIP '192.168.1.100' -NodeName 'MyServer'"
        Write-Host "  .\install_client.ps1 -ServerIP '192.168.1.100' -NodeName 'Layer(`$29.9/Y)'"
        Write-Host "  .\install_client.ps1 -ServerIP '192.168.1.100' -NodeNameBase64 'TGF5ZXIoJDI5LjkvWSk='"
        Write-Host ""
        Write-ColorOutput "[INFO] For special characters in NodeName, use one of these methods:" "Yellow"
        Write-Host "  1. Escape dollar sign with backtick: 'Layer(`$29.9/Y)'"
        Write-Host "  2. Use Base64 encoding: -NodeNameBase64 'TGF5ZXIoJDI5LjkvWSk='"
        Write-Host "  3. Download script first, then run locally"
        exit 1
    } else {
        # 直接运行脚本且参数正确，调用安装函数
        if ($NodeNameBase64) {
            Install-BServerClient -ServerIP $ServerIP -NodeNameBase64 $NodeNameBase64
        } else {
            Install-BServerClient -ServerIP $ServerIP -NodeName $NodeName
        }
    }
}

# 注意：一键命令通过iex执行脚本内容，然后直接调用 Install-BServerClient 函数
# 这种情况下不会进入上面的条件分支 