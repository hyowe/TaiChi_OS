import json
import os
from sys import argv

# 全局基本配置文件
# 构造 config.json 文件的完整路径
config_path = os.path.join(os.path.dirname(argv[0]), 'config.json')



# 定义默认值
default_data = {
    'source_url': 'https://app.kookoo.top',
    'docker_download_url': 'https://download.docker.com/linux/static/stable/x86_64/docker-24.0.7.tgz',
    'docker_service_config': (
        "[Unit]\n"
        "Description=Docker Application Container Engine\n"
        "Documentation=https://docs.docker.com\n"
        "After=network-online.target firewalld.service\n"
        "Wants=network-online.target\n"
        "[Service]\n"
        "Type=notify\n"
        "ExecStart=/usr/bin/dockerd\n"
        "ExecReload=/bin/kill -s HUP $MAINPID\n"
        "LimitNOFILE=infinity\n"
        "LimitNPROC=infinity\n"
        "LimitCORE=infinity\n"
        "TimeoutStartSec=0\n"
        "Delegate=yes\n"
        "KillMode=process\n"
        "Restart=on-failure\n"
        "StartLimitBurst=3\n"
        "StartLimitInterval=60s\n"
        "[Install]\n"
        "WantedBy=multi-user.target\n"
    ),
    'get_docker_shell_command': 'curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh'
}

# 如果存在，尝试打开文件并读取值
if os.path.exists(config_path):
    try:
        with open(config_path, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        # 如果文件内容被破坏，使用默认值
        data = default_data
else:
    # 如果不存在，创建一个新的文件，并设置默认值
    data = default_data
    with open(config_path, 'w') as f:
        json.dump(data, f)

# 检查 data 字典是否包含所有需要的键，如果不包含，使用默认值
for key in default_data:
    if key not in data:
        data[key] = default_data[key]

SOURCE_URL = data['source_url']
DOCKER_DOWNLOAD_URL = data['docker_download_url']
DOCKER_SERVICE_CONFIG = data['docker_service_config']
GET_DOCKER_SHELL_COMMAND = data['get_docker_shell_command']

# @/file 配置文件
HOME_PATH = os.path.abspath('/')  # 将路径转化为标准绝对路径
HOME_NAME = os.path.basename(HOME_PATH)  # 根目录的名字

DEFAULT_LOGO_PATH = 'static/img/favicon.png'
DOCKER_CATEGORY = 'Docker Apps'
SERVICE_CATEGORY = 'Service'

INSTLL_DOCKER_COMMANDS = [
    f'rm -rf /usr/bin/docker* && \
    rm -rf /usr/bin/runc && \
    rm -rf /usr/bin/ctr && \
    rm -rf /usr/bin/containerd* && \
    rm -rf /etc/systemd/system/docker* && \
    rm -rf /var/lib/docker* && \
    rm -rf /var/run/docker.sock && \
    curl -o docker.tgz {DOCKER_DOWNLOAD_URL} && \
    tar xzvf docker.tgz && \
    cp docker/* /usr/bin/ && \
    rm -rf docker && \
    echo "{DOCKER_SERVICE_CONFIG}" > /etc/systemd/system/docker.service && \
    chmod +x /etc/systemd/system/docker.service && \
    systemctl daemon-reload && \
    systemctl enable --now docker.service'
]

UNSUPPORTED_COMMANDS = [
    'top', 'vim', 'ping', 'vi', 'htop', 'nano', 'emacs', 'ssh', 'telnet',
    'ftp', 'sftp', 'scp', 'less', 'more', 'man', 'lynx', 'nc', 'netcat',
    'telnet', 'watch', 'screen', 'tmux', 'w3m', 'links', 'elinks', 'mysql',
    'psql', 'sqlite3'
]

TAICHI_OS_LOGO = """
 ███████████            ███    █████████  █████       ███        ███████     █████████ 
░█░░░███░░░█           ░░░    ███░░░░░███░░███       ░░░       ███░░░░░███  ███░░░░░███
░   ░███  ░   ██████   ████  ███     ░░░  ░███████   ████     ███     ░░███░███    ░░░ 
    ░███     ░░░░░███ ░░███ ░███          ░███░░███ ░░███    ░███      ░███░░█████████ 
    ░███      ███████  ░███ ░███          ░███ ░███  ░███    ░███      ░███ ░░░░░░░░███
    ░███     ███░░███  ░███ ░░███     ███ ░███ ░███  ░███    ░░███     ███  ███    ░███
    █████   ░░████████ █████ ░░█████████  ████ █████ █████    ░░░███████░  ░░█████████ 
   ░░░░░     ░░░░░░░░ ░░░░░   ░░░░░░░░░  ░░░░ ░░░░░ ░░░░░       ░░░░░░░     ░░░░░░░░░                                                                                                                                                             
"""

TAICHI_OS_WELCOME_MESSAGE = ("\n"
                             "版本 : 0.9.9.17-DEV\n"
                             "GITHUB : https://github.com/Xingsandesu\n")
# # @/command 配置文件
# commands = {
#     'docker ps -a': '显示全部容器',
#     'dir': '显示路径',
#     'echo hello word': '测试输出',
# }

# def get_latest_docker_url(base_url: str):
#     # 打开URL并读取内容
#     with urllib.request.urlopen(base_url) as response:
#         html = response.read().decode()
#
#     # 使用正则表达式匹配所有的docker版本链接
#     matches = re.findall(r'docker-(\d+\.\d+\.\d+)\.tgz', html)
#
#     # 对匹配到的版本进行排序，选择最大的版本
#     latest_version = sorted(matches, key=lambda version: list(map(int, version.split('.'))), reverse=True)[0]
#
#     # 拼接完整的URL
#     latest_docker_url = base_url + 'docker-' + latest_version + '.tgz'
#
#     return latest_docker_url
