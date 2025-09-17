#!/usr/bin/env bash

{ # 确保整个脚本被完整下载 #

nvm_has() {
  type "$1" > /dev/null 2>&1
}

nvm_echo() {
  command printf %s\\n "$*" 2>/dev/null
}

# 仅支持bash，不支持zsh直接运行
if [ -z "${BASH_VERSION}" ] || [ -n "${ZSH_VERSION}" ]; then
  nvm_echo >&2 '错误：安装说明明确要求将安装脚本通过bash执行，请遵循说明操作'
  exit 1
fi

nvm_grep() {
  GREP_OPTIONS='' command grep "$@"
}

# 默认安装目录
nvm_default_install_dir() {
  [ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm"
}

# 获取安装目录
nvm_install_dir() {
  if [ -n "$NVM_DIR" ]; then
    printf %s "${NVM_DIR}"
  else
    nvm_default_install_dir
  fi
}

# NVM最新版本
nvm_latest_version() {
  nvm_echo "v0.40.3"
}

# 检查配置文件是否为bash或zsh的
nvm_profile_is_bash_or_zsh() {
  local TEST_PROFILE
  TEST_PROFILE="${1-}"
  case "${TEST_PROFILE-}" in
    *"/.bashrc" | *"/.bash_profile" | *"/.zshrc" | *"/.zprofile")
      return
    ;;
    *)
      return 1
    ;;
  esac
}

# 获取NVM源地址 - 使用国内镜像
nvm_source() {
  # 使用国内Gitee镜像
  local NVM_GITHUB_REPO
  NVM_GITHUB_REPO="${NVM_INSTALL_GITHUB_REPO:-mirrors/nvm}"
  
  local NVM_VERSION
  NVM_VERSION="${NVM_INSTALL_VERSION:-$(nvm_latest_version)}"
  local NVM_METHOD
  NVM_METHOD="$1"
  local NVM_SOURCE_URL
  NVM_SOURCE_URL="$NVM_SOURCE"
  
  # 国内镜像源
  local BASE_URL="https://gitee.com/${NVM_GITHUB_REPO}"
  
  if [ "_$NVM_METHOD" = "_script-nvm-exec" ]; then
    NVM_SOURCE_URL="${BASE_URL}/raw/${NVM_VERSION}/nvm-exec"
  elif [ "_$NVM_METHOD" = "_script-nvm-bash-completion" ]; then
    NVM_SOURCE_URL="${BASE_URL}/raw/${NVM_VERSION}/bash_completion"
  elif [ -z "$NVM_SOURCE_URL" ]; then
    if [ "_$NVM_METHOD" = "_script" ]; then
      NVM_SOURCE_URL="${BASE_URL}/raw/${NVM_VERSION}/nvm.sh"
    elif [ "_$NVM_METHOD" = "_git" ] || [ -z "$NVM_METHOD" ]; then
      NVM_SOURCE_URL="${BASE_URL}.git"
    else
      nvm_echo >&2 "意外的\$NVM_METHOD值 \"$NVM_METHOD\""
      return 1
    fi
  fi
  nvm_echo "$NVM_SOURCE_URL"
}

# Node.js版本
nvm_node_version() {
  nvm_echo "$NODE_VERSION"
}

# 下载函数
nvm_download() {
  if nvm_has "curl"; then
    # 添加代理选项，国内用户可根据需要取消注释
    # curl --proxy http://127.0.0.1:7890 --fail --compressed -q "$@"
    curl --fail --compressed -q "$@"
  elif nvm_has "wget"; then
    # 模拟curl参数
    ARGS=$(nvm_echo "$@" | command sed -e 's/--progress-bar /--progress=bar /' \
                            -e 's/--compressed //' \
                            -e 's/--fail //' \
                            -e 's/-L //' \
                            -e 's/-I /--server-response /' \
                            -e 's/-s /-q /' \
                            -e 's/-sS /-nv /' \
                            -e 's/-o /-O /' \
                            -e 's/-C - /-c /')
    # shellcheck disable=SC2086
    eval wget $ARGS
  fi
}

# 从git安装nvm
install_nvm_from_git() {
  local INSTALL_DIR
  INSTALL_DIR="$(nvm_install_dir)"
  local NVM_VERSION
  NVM_VERSION="${NVM_INSTALL_VERSION:-$(nvm_latest_version)}"
  
  local fetch_error
  if [ -d "$INSTALL_DIR/.git" ]; then
    # 更新现有安装
    nvm_echo "=> nvm已安装在$INSTALL_DIR，尝试使用git更新"
    command printf '\r=> '
    fetch_error="使用$NVM_VERSION更新nvm失败，请在$INSTALL_DIR中手动运行'git fetch'"
  else
    fetch_error="使用$NVM_VERSION获取源失败，请反馈此问题！"
    nvm_echo "=> 从git下载nvm到'$INSTALL_DIR'"
    command printf '\r=> '
    mkdir -p "${INSTALL_DIR}"
    if [ "$(ls -A "${INSTALL_DIR}")" ]; then
      # 初始化仓库
      command git init "${INSTALL_DIR}" || {
        nvm_echo >&2 '初始化nvm仓库失败，请反馈此问题！'
        exit 2
      }
      command git --git-dir="${INSTALL_DIR}/.git" remote add origin "$(nvm_source)" 2> /dev/null \
        || command git --git-dir="${INSTALL_DIR}/.git" remote set-url origin "$(nvm_source)" || {
        nvm_echo >&2 '添加远程仓库"origin"失败，请反馈此问题！'
        exit 2
      }
    else
      # 克隆仓库
      command git clone "$(nvm_source)" --depth=1 "${INSTALL_DIR}" || {
        nvm_echo >&2 '克隆nvm仓库失败，请反馈此问题！'
        exit 2
      }
    fi
  fi
  
  # 尝试获取标签
  if command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" fetch origin tag "$NVM_VERSION" --depth=1 2>/dev/null; then
    :
  # 获取指定版本
  elif ! command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" fetch origin "$NVM_VERSION" --depth=1; then
    nvm_echo >&2 "$fetch_error"
    exit 1
  fi
  command git -c advice.detachedHead=false --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" checkout -f --quiet FETCH_HEAD || {
    nvm_echo >&2 "切换到指定版本$NVM_VERSION失败，请反馈此问题！"
    exit 2
  }
  
  nvm_echo "=> 压缩并清理git仓库"
  if ! command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" reflog expire --expire=now --all; then
    nvm_echo >&2 "您的git版本过旧，请更新！"
  fi
  if ! command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" gc --auto --aggressive --prune=now ; then
    nvm_echo >&2 "您的git版本过旧，请更新！"
  fi
  return
}

# 安装Node.js
nvm_install_node() {
  local NODE_VERSION_LOCAL
  NODE_VERSION_LOCAL="$(nvm_node_version)"

  if [ -z "$NODE_VERSION_LOCAL" ]; then
    return 0
  fi

  # 使用国内npm镜像
  nvm_echo "=> 设置npm国内镜像"
  npm config set registry https://registry.npmmirror.com
  
  nvm_echo "=> 安装Node.js版本$NODE_VERSION_LOCAL"
  nvm install "$NODE_VERSION_LOCAL"
  local CURRENT_NVM_NODE

  CURRENT_NVM_NODE="$(nvm_version current)"
  if [ "$(nvm_version "$NODE_VERSION_LOCAL")" == "$CURRENT_NVM_NODE" ]; then
    nvm_echo "=> Node.js版本$NODE_VERSION_LOCAL已成功安装"
  else
    nvm_echo >&2 "安装Node.js $NODE_VERSION_LOCAL失败"
  fi
}

# 作为脚本安装nvm
install_nvm_as_script() {
  local INSTALL_DIR
  INSTALL_DIR="$(nvm_install_dir)"
  local NVM_SOURCE_LOCAL
  NVM_SOURCE_LOCAL="$(nvm_source script)"
  local NVM_EXEC_SOURCE
  NVM_EXEC_SOURCE="$(nvm_source script-nvm-exec)"
  local NVM_BASH_COMPLETION_SOURCE
  NVM_BASH_COMPLETION_SOURCE="$(nvm_source script-nvm-bash-completion)"

  # 下载到$INSTALL_DIR
  mkdir -p "$INSTALL_DIR"
  if [ -f "$INSTALL_DIR/nvm.sh" ]; then
    nvm_echo "=> nvm已安装在$INSTALL_DIR，尝试更新脚本"
  else
    nvm_echo "=> 下载nvm脚本到'$INSTALL_DIR'"
  fi
  nvm_download -s "$NVM_SOURCE_LOCAL" -o "$INSTALL_DIR/nvm.sh" || {
    nvm_echo >&2 "下载'$NVM_SOURCE_LOCAL'失败"
    return 1
  } &
  nvm_download -s "$NVM_EXEC_SOURCE" -o "$INSTALL_DIR/nvm-exec" || {
    nvm_echo >&2 "下载'$NVM_EXEC_SOURCE'失败"
    return 2
  } &
  nvm_download -s "$NVM_BASH_COMPLETION_SOURCE" -o "$INSTALL_DIR/bash_completion" || {
    nvm_echo >&2 "下载'$NVM_BASH_COMPLETION_SOURCE'失败"
    return 2
  } &
  for job in $(jobs -p | command sort)
  do
    wait "$job" || return $?
  done
  chmod a+x "$INSTALL_DIR/nvm-exec" || {
    nvm_echo >&2 "无法将'$INSTALL_DIR/nvm-exec'标记为可执行"
    return 3
  }
}

nvm_try_profile() {
  if [ -z "${1-}" ] || [ ! -f "${1}" ]; then
    return 1
  fi
  nvm_echo "${1}"
}

# 检测配置文件
nvm_detect_profile() {
  if [ "${PROFILE-}" = '/dev/null' ]; then
    # 用户明确要求不修改配置文件
    return
  fi

  if [ -n "${PROFILE}" ] && [ -f "${PROFILE}" ]; then
    nvm_echo "${PROFILE}"
    return
  fi

  local DETECTED_PROFILE
  DETECTED_PROFILE=''

  if [ "${SHELL#*bash}" != "$SHELL" ]; then
    if [ -f "$HOME/.bashrc" ]; then
      DETECTED_PROFILE="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
      DETECTED_PROFILE="$HOME/.bash_profile"
    fi
  elif [ "${SHELL#*zsh}" != "$SHELL" ]; then
    if [ -f "${ZDOTDIR:-${HOME}}/.zshrc" ]; then
      DETECTED_PROFILE="${ZDOTDIR:-${HOME}}/.zshrc"
    elif [ -f "${ZDOTDIR:-${HOME}}/.zprofile" ]; then
      DETECTED_PROFILE="${ZDOTDIR:-${HOME}}/.zprofile"
    fi
  fi

  if [ -z "$DETECTED_PROFILE" ]; then
    for EACH_PROFILE in ".profile" ".bashrc" ".bash_profile" ".zprofile" ".zshrc"
    do
      if DETECTED_PROFILE="$(nvm_try_profile "${ZDOTDIR:-${HOME}}/${EACH_PROFILE}")"; then
        break
      fi
    done
  fi

  if [ -n "$DETECTED_PROFILE" ]; then
    nvm_echo "$DETECTED_PROFILE"
  fi
}

# 检查全局npm模块
nvm_check_global_modules() {
  local NPM_COMMAND
  NPM_COMMAND="$(command -v npm 2>/dev/null)" || return 0
  [ -n "${NVM_DIR}" ] && [ -z "${NPM_COMMAND%%"$NVM_DIR"/*}" ] && return 0

  local NPM_VERSION
  NPM_VERSION="$(npm --version)"
  NPM_VERSION="${NPM_VERSION:--1}"
  [ "${NPM_VERSION%%[!-0-9]*}" -gt 0 ] || return 0

  local NPM_GLOBAL_MODULES
  NPM_GLOBAL_MODULES="$(
    npm list -g --depth=0 |
    command sed -e '/ npm@/d' -e '/ (empty)$/d'
  )"

  local MODULE_COUNT
  MODULE_COUNT="$(
    command printf %s\\n "$NPM_GLOBAL_MODULES" |
    command sed -ne '1!p' |                     # 移除第一行
    wc -l | command tr -d ' '                   # 计数
  )"

  if [ "${MODULE_COUNT}" != '0' ]; then
    nvm_echo '=> 您当前有通过`npm`全局安装的模块，这些模块'
    nvm_echo '=> 在使用`nvm`安装新的Node版本后将不再链接到当前活动版本，'
    nvm_echo '=> 并且可能会覆盖`nvm`安装的模块的二进制文件：'
    nvm_echo

    command printf %s\\n "$NPM_GLOBAL_MODULES"
    nvm_echo '=> 如果您希望稍后卸载它们（或在`nvm`管理的Node版本下重新安装），'
    nvm_echo '=> 可以通过以下方式从系统Node中移除它们：'
    nvm_echo
    nvm_echo '     $ nvm use system'
    nvm_echo '     $ npm uninstall -g 模块名'
    nvm_echo
  fi
}

# 主安装函数
nvm_do_install() {
  if [ -n "${NVM_DIR-}" ] && ! [ -d "${NVM_DIR}" ]; then
    if [ -e "${NVM_DIR}" ]; then
      nvm_echo >&2 "文件\"${NVM_DIR}\"与安装目录同名。"
      exit 1
    fi

    if [ "${NVM_DIR}" = "$(nvm_default_install_dir)" ]; then
      mkdir "${NVM_DIR}"
    else
      nvm_echo >&2 "您设置了\$NVM_DIR为\"${NVM_DIR}\"，但该目录不存在。请检查您的配置文件和环境。"
      exit 1
    fi
  fi
  
  # 检查依赖
  if nvm_has xcode-select && [ "$(xcode-select -p >/dev/null 2>/dev/null ; echo $?)" = '2' ] && [ "$(which git)" = '/usr/bin/git' ] && [ "$(which curl)" = '/usr/bin/curl' ]; then
    nvm_echo >&2 '您可能在Mac上，需要安装Xcode命令行开发工具。'
    nvm_echo >&2 '如果是这样，请运行`xcode-select --install`然后重试。否则，请反馈此问题！'
    exit 1
  fi
  if [ -z "${METHOD}" ]; then
    # 自动检测安装方法
    if nvm_has git; then
      install_nvm_from_git
    elif nvm_has curl || nvm_has wget; then
      install_nvm_as_script
    else
      nvm_echo >&2 '安装nvm需要git、curl或wget'
      exit 1
    fi
  elif [ "${METHOD}" = 'git' ]; then
    if ! nvm_has git; then
      nvm_echo >&2 "安装nvm需要git"
      exit 1
    fi
    install_nvm_from_git
  elif [ "${METHOD}" = 'script' ]; then
    if ! nvm_has curl && ! nvm_has wget; then
      nvm_echo >&2 "安装nvm需要curl或wget"
      exit 1
    fi
    install_nvm_as_script
  else
    nvm_echo >&2 "环境变量\$METHOD设置为\"${METHOD}\"，这不是有效的安装方法。"
    exit 1
  fi

  nvm_echo

  local NVM_PROFILE
  NVM_PROFILE="$(nvm_detect_profile)"
  local PROFILE_INSTALL_DIR
  PROFILE_INSTALL_DIR="$(nvm_install_dir | command sed "s:^$HOME:\$HOME:")"

  SOURCE_STR="\\nexport NVM_DIR=\"${PROFILE_INSTALL_DIR}\"\\n[ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\"  # 加载nvm\\n"

  COMPLETION_STR='[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # 加载nvm bash补全\n'
  BASH_OR_ZSH=false

  if [ -z "${NVM_PROFILE-}" ] ; then
    local TRIED_PROFILE
    if [ -n "${PROFILE}" ]; then
      TRIED_PROFILE="${NVM_PROFILE}（如\$PROFILE中定义），"
    fi
    nvm_echo "=> 未找到配置文件。已尝试${TRIED_PROFILE-}~/.bashrc, ~/.bash_profile, ~/.zprofile, ~/.zshrc, 和 ~/.profile。"
    nvm_echo "=> 创建其中一个文件并重新运行此脚本"
    nvm_echo "   或者"
    nvm_echo "=> 手动将以下行添加到正确的文件中："
    command printf "${SOURCE_STR}"
    nvm_echo
  else
    if nvm_profile_is_bash_or_zsh "${NVM_PROFILE-}"; then
      BASH_OR_ZSH=true
    fi
    if ! command grep -qc '/nvm.sh' "$NVM_PROFILE"; then
      nvm_echo "=> 将nvm源字符串添加到$NVM_PROFILE"
      command printf "${SOURCE_STR}" >> "$NVM_PROFILE"
    else
      nvm_echo "=> nvm源字符串已在${NVM_PROFILE}中"
    fi
    if ${BASH_OR_ZSH} && ! command grep -qc '$NVM_DIR/bash_completion' "$NVM_PROFILE"; then
      nvm_echo "=> 将bash_completion源字符串添加到$NVM_PROFILE"
      command printf "$COMPLETION_STR" >> "$NVM_PROFILE"
    else
      nvm_echo "=> bash_completion源字符串已在${NVM_PROFILE}中"
    fi
  fi
  if ${BASH_OR_ZSH} && [ -z "${NVM_PROFILE-}" ] ; then
    nvm_echo "=> 如果您使用bash/zsh shell，请同时将以下行添加到配置文件："
    command printf "${COMPLETION_STR}"
  fi

  # 加载nvm
  # shellcheck source=/dev/null
  \. "$(nvm_install_dir)/nvm.sh"

  nvm_check_global_modules

  # 配置nvm使用国内镜像加速
  nvm_echo "=> 配置nvm使用国内镜像加速"
  echo 'export NVM_NODEJS_ORG_MIRROR=https://npmmirror.com/mirrors/node' >> "$(nvm_install_dir)/nvm.sh"
  echo 'export NVM_NPM_MIRROR=https://npmmirror.com/mirrors/npm' >> "$(nvm_install_dir)/nvm.sh"

  nvm_install_node

  nvm_reset

  nvm_echo "=> 关闭并重新打开终端以开始使用nvm，或运行以下命令立即使用："
  command printf "${SOURCE_STR}"
  if ${BASH_OR_ZSH} ; then
    command printf "${COMPLETION_STR}"
  fi
}

# 清理函数
nvm_reset() {
  unset -f nvm_has nvm_install_dir nvm_latest_version nvm_profile_is_bash_or_zsh \
    nvm_source nvm_node_version nvm_download install_nvm_from_git nvm_install_node \
    install_nvm_as_script nvm_try_profile nvm_detect_profile nvm_check_global_modules \
    nvm_do_install nvm_reset nvm_default_install_dir nvm_grep
}

[ "_$NVM_ENV" = "_testing" ] || nvm_do_install

} # 确保整个脚本被完整下载 #
    