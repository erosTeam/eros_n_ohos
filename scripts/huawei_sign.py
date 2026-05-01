#!/usr/bin/env python3
"""
huawei_sign.py - 调用 DevEco Studio IDE API 完成证书/Profile 创建，然后签名安装 HAP

用法:
  python3 scripts/huawei_sign.py                # debug 构建+签名+安装（自动选设备/读缓存）
  python3 scripts/huawei_sign.py --no-build     # 跳过构建，直接用已有的 unsigned.hap
  python3 scripts/huawei_sign.py --release      # release 模式
  python3 scripts/huawei_sign.py --profile      # profile 模式
  python3 scripts/huawei_sign.py -d all         # 安装到所有已连接设备
  python3 scripts/huawei_sign.py -d <device>    # 安装到指定设备（不影响缓存）
  python3 scripts/huawei_sign.py --force-profile # 强制重建 Profile
  python3 scripts/huawei_sign.py -h             # 显示帮助

设备缓存:
  首次运行时若检测到多设备会提示选择，选择结果缓存 7 天。
  缓存期内无需 -d 参数，自动使用上次选择的设备并刷新缓存时效。
  -d all 时安装到所有设备，若缓存设备在线则同步刷新其缓存时效。
"""
import sys, os, json, subprocess, shutil, urllib.request, urllib.parse
import urllib.error, threading, webbrowser, random, time, zipfile, tempfile
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

# ── 配置 ──────────────────────────────────────────────────────────────────────
PROJ        = Path(__file__).resolve().parent.parent   # eros_n_ohos root
SIGN_DIR    = PROJ / "ohos/sign"
TOOL_LIB    = Path("/home/gamer/devtool/ohos/command-line-tools/sdk/default/openharmony/toolchains/lib")
HAP_SIGN    = TOOL_LIB / "hap-sign-tool.jar"
HDC         = Path("/home/gamer/devtool/ohos/command-line-tools/sdk/default/openharmony/toolchains/hdc")
UNSIGNED_HAP = PROJ / "build/ohos/hap/entry-default-unsigned.hap"

# 设备选择缓存文件及有效期（7 天）
DEVICE_CACHE_FILE = Path.home() / ".cache" / "eros_n_ohos_device.json"
DEVICE_CACHE_TTL  = 7 * 24 * 3600

def _signed_hap(mode: str) -> Path:
    return PROJ / f"build/ohos/entry-{mode}-signed.hap"

AUTH_FILE   = Path.home() / "Documents/hap_installer/userInfo.json"
CERT_FILE   = SIGN_DIR / "xiaobai-debug.cer"
PROFILE_FILE = SIGN_DIR / "xiaobai-debug.p7b"

KS_FILE     = SIGN_DIR / "xiaobai.p12"
KS_ALIAS    = "key0"
KS_PWD      = "123456Abc"

BUNDLE_NAME = "com.erosteam.erosn"
CERT_NAME   = "xiaobai-debug"

# DevEco IDE 登录 URL
ECO_URL     = "https://cn.devecostudio.huawei.com/console/DevEcoIDE/apply?port={port}&appid=1007&code=20698961dd4f420c8b44f49010c6f0cc"

# ── API 工具函数 ────────────────────────────────────────────────────────────────
def api(url, data=None, method=None, headers=None, auth=None, raw=False):
    if method is None:
        method = "POST" if data is not None else "GET"
    body = json.dumps(data).encode() if data is not None else None
    req_headers = {"content-type": "application/json"}
    if auth:
        req_headers["oauth2Token"] = auth.get("accessToken", "")
        req_headers["teamId"]      = auth.get("teamId") or auth.get("userId", "")
        req_headers["uid"]         = auth.get("userId", "")
    if headers:
        req_headers.update(headers)
    req = urllib.request.Request(url, data=body, headers=req_headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            text = resp.read().decode()
            if raw:
                return text
            try:
                return json.loads(text)
            except json.JSONDecodeError:
                return text  # 部分接口返回纯字符串
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code}: {e.read().decode()[:200]}")

def download(url, dest):
    urllib.request.urlretrieve(url, dest)

# ── 登录 ────────────────────────────────────────────────────────────────────────
class CallbackHandler(BaseHTTPRequestHandler):
    result = None
    def log_message(self, *a): pass
    def do_POST(self):
        if self.path == "/callback":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length).decode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write("登录成功！请返回！".encode("utf-8"))
            CallbackHandler.result = body
        else:
            self.send_response(404); self.end_headers()

def login():
    port = random.randint(3333, 4333)
    server = HTTPServer(("127.0.0.1", port), CallbackHandler)
    server.timeout = 120
    url = ECO_URL.format(port=port)
    print(f"\n请在浏览器中完成华为账号登录:")
    print(f"  {url}\n")
    webbrowser.open(url)

    print("等待登录回调（最长 120 秒）...")
    while CallbackHandler.result is None:
        server.handle_request()

    temp_token_url = CallbackHandler.result
    # 1. 换 jwtToken
    params = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(temp_token_url).query))
    if not params:
        params = dict(x.split("=", 1) for x in temp_token_url.split("&") if "=" in x)
    temp_token = params.get("tempToken", temp_token_url)
    jwt_resp = api(
        f"https://cn.devecostudio.huawei.com/authrouter/auth/api/temptoken/check"
        f"?site=CN&tempToken={urllib.parse.quote(temp_token)}&appid=1007&version=0.0.0",
        method="GET"
    )
    # 返回纯字符串 JWT
    if isinstance(jwt_resp, str):
        jwt_token = jwt_resp
    else:
        jwt_token = jwt_resp.get("ret", {}).get("msg", "") if isinstance(jwt_resp, dict) else str(jwt_resp)

    # 2. 换 accessToken
    user_resp = api(
        "https://cn.devecostudio.huawei.com/authrouter/auth/api/jwToken/check",
        method="GET",
        headers={"refresh": "false", "jwtToken": jwt_token}
    )
    print(f"jwToken/check 响应: {str(user_resp)[:200]}")
    if isinstance(user_resp, dict):
        user_info = user_resp.get("userInfo") or user_resp.get("body", {}).get("userInfo") or user_resp
    else:
        raise RuntimeError(f"jwToken/check 返回异常: {user_resp}")
    auth = {
        "accessToken": user_info.get("accessToken"),
        "userId":      user_info.get("userId") or user_info.get("userID"),
        "teamId":      user_info.get("userId") or user_info.get("userID"),
        "jwtToken":    jwt_token,
        "nickName":    user_info.get("nickName", ""),
    }
    AUTH_FILE.parent.mkdir(parents=True, exist_ok=True)
    AUTH_FILE.write_text(json.dumps(auth, indent=2))
    print(f"登录成功: {auth.get('nickName')} (uid={auth.get('userId')})")
    return auth

def load_or_login():
    if AUTH_FILE.exists():
        auth = json.loads(AUTH_FILE.read_text())
        # 验证 token 是否有效
        try:
            r = api("https://connect-api.cloud.huawei.com/api/ups/user-permission-service/v1/user-team-list",
                    method="GET", auth=auth)
            if r.get("ret", {}).get("code") == 401:
                raise RuntimeError("token expired")
            print(f"使用已缓存账号: {auth.get('nickName', auth.get('userId'))}")
            return auth
        except Exception as e:
            print(f"Token 已过期，重新登录: {e}")
    return login()

# ── 证书 ────────────────────────────────────────────────────────────────────────
def ensure_cert(auth):
    cert_list = api("https://connect-api.cloud.huawei.com/api/cps/harmony-cert-manage/v1/cert/list",
                    method="GET", auth=auth).get("certList", [])
    debug_certs = [c for c in cert_list if c.get("certType") == 1]
    existing = next((c for c in debug_certs if c.get("certName") == CERT_NAME), None)

    # 固定用 xiaobai.csr（与 xiaobai.p12 配对）
    csr_path = SIGN_DIR / "xiaobai.csr"
    csr = csr_path.read_text()

    need_create = existing is None
    # 若本地证书文件不存在，说明之前是用别的 CSR 创建的（密钥不匹配），删掉重建
    if existing is not None and not CERT_FILE.exists():
        print(f"本地证书缺失，删除 AGC 旧证书并用 xiaobai.csr 重建...")
        api("https://connect-api.cloud.huawei.com/api/cps/harmony-cert-manage/v1/cert/delete",
            data={"certIds": [existing["id"]]}, method="DELETE", auth=auth)
        existing = None
        need_create = True

    if need_create:
        if len(cert_list) >= 3:
            debug_certs.sort(key=lambda c: c.get("expireTime", 0))
            api("https://connect-api.cloud.huawei.com/api/cps/harmony-cert-manage/v1/cert/delete",
                data={"certIds": [debug_certs[0]["id"]]}, method="DELETE", auth=auth)
        print(f"创建调试证书 '{CERT_NAME}'...")
        result = api("https://connect-api.cloud.huawei.com/api/cps/harmony-cert-manage/v1/cert/add",
                     data={"csr": csr, "certName": CERT_NAME, "certType": 1}, auth=auth)
        existing = result.get("harmonyCert", {})
        if not existing:
            raise RuntimeError(f"证书创建失败: {result}")

    cert_id = existing["id"]
    obj_id  = existing.get("certObjectId")
    if not CERT_FILE.exists():
        urls = api("https://connect-api.cloud.huawei.com/api/amis/app-manage/v1/objects/url/reapply",
                   data={"sourceUrls": obj_id}, auth=auth)
        url = urls.get("urlsInfo", [{}])[0].get("newUrl")
        print(f"下载证书...")
        download(url, CERT_FILE)
    print(f"证书 ID: {cert_id}, 文件: {CERT_FILE.name}")
    return cert_id

# ── 设备 ─────────────────────────────────────────────────────────────────────────
def ensure_device(auth, udid):
    device_list = api("https://connect-api.cloud.huawei.com/api/cps/device-manage/v1/device/list?start=1&pageSize=100&encodeFlag=0",
                      method="GET", auth=auth).get("list", [])
    if not any(d.get("udid") == udid for d in device_list):
        print(f"注册设备 {udid[:16]}...")
        api("https://connect-api.cloud.huawei.com/api/cps/device-manage/v1/device/add",
            data={"deviceName": f"xiaobai-device-{udid[:10]}", "udid": udid, "deviceType": 4},
            auth=auth)
        device_list = api("https://connect-api.cloud.huawei.com/api/cps/device-manage/v1/device/list?start=1&pageSize=100&encodeFlag=0",
                          method="GET", auth=auth).get("list", [])
    device_ids = [d["id"] for d in device_list]
    print(f"设备数: {len(device_list)}")
    return device_ids

# ── Profile ───────────────────────────────────────────────────────────────────
def ensure_profile(auth, cert_id, device_ids):
    profile_name = f"xiaobai-debug_{BUNDLE_NAME.replace('.', '_')}"
    print(f"创建 Profile '{profile_name}'...")
    result = api("https://connect-api.cloud.huawei.com/api/cps/provision-manage/v1/ide/test/provision/add",
                 data={
                     "provisionName":     profile_name,
                     "aclPermissionList": [],
                     "deviceList":        device_ids,
                     "certList":          [cert_id],
                     "packageName":       BUNDLE_NAME,
                 }, auth=auth)
    url = result.get("provisionFileUrl")
    if not url:
        raise RuntimeError(f"Profile 创建失败: {result}")
    print("下载 Profile...")
    download(url, PROFILE_FILE)
    print(f"Profile: {PROFILE_FILE.name}")

# ── 签名 & 安装 ───────────────────────────────────────────────────────────────
def _fix_so_compression(hap_path: Path):
    """Ensure .so files are STORED (not deflated) in the HAP.
    HarmonyOS requires uncompressed .so for code signature verification."""
    needs_fix = False
    with zipfile.ZipFile(hap_path, 'r') as zf:
        for info in zf.infolist():
            if info.filename.endswith('.so') and info.compress_type != zipfile.ZIP_STORED:
                needs_fix = True
                break
    if not needs_fix:
        return
    print("修正 HAP 中 .so 压缩方式为 STORED...")
    tmp = tempfile.mkdtemp()
    try:
        with zipfile.ZipFile(hap_path, 'r') as zf:
            zf.extractall(tmp)
            entries = zf.infolist()
        with zipfile.ZipFile(hap_path, 'w') as zf_out:
            for info in entries:
                if info.is_dir():
                    continue
                fpath = os.path.join(tmp, info.filename)
                data = open(fpath, 'rb').read()
                if info.filename.endswith('.so'):
                    info.compress_type = zipfile.ZIP_STORED
                else:
                    info.compress_type = zipfile.ZIP_DEFLATED
                zf_out.writestr(info, data)
    finally:
        shutil.rmtree(tmp)

def sign_and_install(mode: str, devices: list[str]):
    signed_hap = _signed_hap(mode)
    xiaobai_p12 = SIGN_DIR / "xiaobai.p12"
    ks, alias, pwd = str(xiaobai_p12), "xiaobai", "xiaobai123"

    _fix_so_compression(UNSIGNED_HAP)

    print("签名 HAP...")
    cmd = [
        "java", "-jar", str(HAP_SIGN),
        "sign-app",
        "-mode",        "localSign",
        "-keyAlias",    alias,
        "-keyPwd",      pwd,
        "-appCertFile", str(CERT_FILE),
        "-profileFile", str(PROFILE_FILE),
        "-inFile",      str(UNSIGNED_HAP),
        "-signAlg",     "SHA256withECDSA",
        "-keystoreFile",ks,
        "-keystorePwd", pwd,
        "-compatibleVersion", "8",
        "-outFile",     str(signed_hap),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    output = result.stdout + result.stderr
    print(output)
    if "sign-app success" not in output:
        raise RuntimeError("签名失败")

    print("安装 HAP...")
    for dev in devices:
        print(f"  安装到 {dev}...")
        result = subprocess.run([str(HDC), "-t", dev, "install", str(signed_hap)], capture_output=True, text=True)
        print(f"  {(result.stdout + result.stderr).strip()}")

# ── 设备缓存 ──────────────────────────────────────────────────────────────────
def load_cached_device() -> str | None:
    """返回缓存的设备地址（若未过期），否则返回 None。"""
    if not DEVICE_CACHE_FILE.exists():
        return None
    try:
        data = json.loads(DEVICE_CACHE_FILE.read_text())
        if time.time() < data.get("expires", 0):
            return data.get("device")
    except Exception:
        pass
    return None

def save_cached_device(device: str):
    """将设备写入缓存并刷新 TTL。"""
    DEVICE_CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
    DEVICE_CACHE_FILE.write_text(json.dumps({
        "device":  device,
        "expires": time.time() + DEVICE_CACHE_TTL,
    }))

def pick_device(devices: list[str]) -> str:
    """若只有一台设备直接返回；否则展示编号列表让用户选择。"""
    if len(devices) == 1:
        print(f"使用唯一已连接设备: {devices[0]}")
        return devices[0]
    print("\n检测到多个已连接设备，请选择安装目标:")
    for i, dev in enumerate(devices):
        print(f"  [{i + 1}] {dev}")
    while True:
        choice = input(f"输入序号 (1-{len(devices)}): ").strip()
        if choice.isdigit() and 1 <= int(choice) <= len(devices):
            return devices[int(choice) - 1]
        print("无效输入，请重试")

def resolve_install_targets(target_device_arg: str | None) -> list[str]:
    """构建前确定安装目标列表。
    - target_device_arg == "all"：安装到所有已连接设备
    - target_device_arg 为具体地址：仅安装到该设备，并更新缓存为该设备
    - None：读取缓存设备（若在线则复用并刷新 TTL），否则交互选择并写入缓存
    """
    targets_result = subprocess.run([str(HDC), "list", "targets"], capture_output=True, text=True)
    connected = [d.strip() for d in targets_result.stdout.splitlines()
                 if d.strip() and d.strip() != "[Empty]"]
    if not connected:
        raise RuntimeError("无已连接设备，请检查 hdc 连接")

    if target_device_arg == "all":
        devices = connected
        cached = load_cached_device()
        if cached and cached in connected:
            save_cached_device(cached)   # 刷新缓存时效
    elif target_device_arg:
        # 明确指定设备，视为切换默认设备，写入缓存
        devices = [target_device_arg]
        save_cached_device(target_device_arg)
    else:
        cached = load_cached_device()
        if cached and cached in connected:
            print(f"使用缓存设备: {cached}")
            save_cached_device(cached)   # 刷新缓存时效
            devices = [cached]
        else:
            if cached and cached not in connected:
                print(f"缓存设备 {cached} 当前未连接，重新选择...")
            selected = pick_device(connected)
            save_cached_device(selected)
            devices = [selected]

    return devices

# ── 获取设备 UDID ───────────────────────────────────────────────────────────────
def get_udid():
    targets_result = subprocess.run([str(HDC), "list", "targets"],
                                     capture_output=True, text=True)
    devices = [d.strip() for d in targets_result.stdout.splitlines() if d.strip() and d.strip() != "[Empty]"]
    udids = []
    for dev in devices:
        result = subprocess.run([str(HDC), "-t", dev, "shell", "bm", "get", "--udid"],
                                capture_output=True, text=True)
        lines = result.stdout.strip().splitlines()
        for line in lines:
            line = line.strip()
            if line and "udid of" not in line.lower() and len(line) >= 32:
                udids.append(line)
                print(f"  设备 {dev} UDID: {line}")
                break
    if not udids:
        raise RuntimeError("无法获取设备 UDID，请确保设备已连接")
    return udids

# ── main ──────────────────────────────────────────────────────────────────────
def main():
    args = sys.argv[1:]

    if "-h" in args or "--help" in args:
        print(__doc__)
        sys.exit(0)

    no_build      = "--no-build"       in args
    force_profile = "--force-profile"  in args

    # 解析 -d 参数：可以是 "all" 或具体设备地址
    target_device = None
    for i, arg in enumerate(args):
        if arg == "-d" and i + 1 < len(args):
            target_device = args[i + 1]
            break

    if "--release" in args:
        mode = "release"
    elif "--profile" in args:
        mode = "profile"
    else:
        mode = "debug"

    # 构建前先确定安装目标，避免构建完成后才询问设备
    print("==> 检查已连接设备...")
    devices = resolve_install_targets(target_device)

    # 唤醒目标设备屏幕并延长息屏时间，忽略错误
    for dev in devices:
        subprocess.run([str(HDC), "-t", dev, "shell", "power-shell", "wakeup"],
                       capture_output=True)
        subprocess.run([str(HDC), "-t", dev, "shell", "power-shell", "timeout", "-o", "3600000"],
                       capture_output=True)

    if not no_build:
        print(f"==> 构建 HAP（{mode}, no codesign）...")
        result = subprocess.run(
            ["fvm", "flutter", "build", "hap", f"--{mode}",
             "--target-platform", "ohos-arm64", "--no-codesign"],
            cwd=PROJ
        )
        if result.returncode != 0:
            sys.exit(1)

    if not UNSIGNED_HAP.exists():
        print(f"ERROR: 未找到 {UNSIGNED_HAP}")
        sys.exit(1)

    # 如果 profile 已存在且不强制刷新，直接签名安装
    if CERT_FILE.exists() and PROFILE_FILE.exists() and not force_profile:
        print("证书和 Profile 已存在，跳过 API 调用")
        sign_and_install(mode, devices)
        return

    auth = load_or_login()

    print("\n==> 确认调试证书...")
    cert_id = ensure_cert(auth)

    print("\n==> 确认设备...")
    udids = get_udid()
    device_ids = set()
    for udid in udids:
        ids = ensure_device(auth, udid)
        device_ids.update(ids)
    device_ids = list(device_ids)

    print("\n==> 创建 Profile...")
    if force_profile or not PROFILE_FILE.exists():
        ensure_profile(auth, cert_id, device_ids)

    print("\n==> 签名 & 安装...")
    sign_and_install(mode, devices)

    if mode != "release":
        print("\n==> 完成！在设备上打开 App，然后运行:")
        print(f"    cd {PROJ} && fvm flutter attach")
    else:
        print("\n==> 完成！")

if __name__ == "__main__":
    main()
