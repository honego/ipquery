#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
#
# Description:
# Copyright (c) 2026 honeok <i@honeok.com>
#
# References:
# https://github.com/bin456789/reinstall
# https://github.com/fscarmen/sing-box
# https://github.com/xykt/IPQuality

# shellcheck disable=SC2034

set -eE

# MAJOR.MINOR.PATCH
readonly SCRIPT_VERSION='v1.0.0'

## 自定义字体彩色
_red() { printf "\033[31m%b\033[0m\n" "$*"; }
_green() { printf "\033[32m%b\033[0m\n" "$*"; }
_yellow() { printf "\033[33m%b\033[0m\n" "$*"; }
_err_msg() { printf "\033[41m\033[1mError\033[0m %b\n" "$*"; }
_suc_msg() { printf "\033[42m\033[1mSuccess\033[0m %b\n" "$*"; }
_red_bg() { printf "\033[41m\033[37m\033[1m%b\033[0m\n" "$*"; }
_green_bg() { printf "\033[42m\033[37m\033[1m%b\033[0m\n" "$*"; }
_yellow_bg() { printf "\033[43m\033[37m\033[1m%b\033[0m\n" "$*"; }

_bold() { printf "\033[1m%b\033[0m" "$*"; }           # 白色加粗
_bold_cyan() { printf "\033[1;36m%b\033[0m\n" "$*"; } # 青色加粗

_italic() { printf "\033[3m%b\033[23m\n" "$*"; }   # 斜体输出
_underline() { printf "\033[4m%b\033[0m\n" "$*"; } # 下划线

## 各变量默认值
TEMP_DIR="$(mktemp -d 2> /dev/null)"
: "${OUT_LANG:="zh-CN"}" # 默认输出中文

# 终止信号捕获
trap 'rm -rf "${TEMP_DIR:?}" > /dev/null 2>&1' SIGINT SIGTERM EXIT

## 定义数组
declare -a CURL_OPTS=()

# IP查询接口 IPV4 IPV6兼容
# 611611.best 基于 Cloudflare Snippets
declare -a IPAPI_ENDPOINT=(
    "611611.best" "icanhazip.com" "checkip.global.api.aws" "ip.hetzner.com" "ip.sb" "ip.gs" "ip.se" "ip.im" "ip.me" "api.myip.la" "api64.ipify.org"
    "checkip.dedyn.io" "ident.me" "tnedi.me" "ip.wtf" "myip.wtf" "wtfismyip.com" "wgetip.com" "curlmyip.net" "ifconfig.co" "ifconfig.es" "ifconfig.io"
    "ifconfig.is" "ifconfig.me" "ifconfig.cat" "ifconfig.net" "ifconfig.pro" "ifconfig.be" "ip.network" "myip.cam" "ip.zerosla.net" "api.seeip.org"
    "echoip.de" "ping0.cc" "myip.biturl.top" "simpip.com" "i-p.show" "ip.tyk.nu" "ipaddy.net" "ip.5ec.nl" "checkip.spdyn.de" "ip.nnev.de"
)

declare -A SCRIPT_HEAD

declare -A MAXMIND
declare -A IPINFO

SCRIPT_HEAD[title]="IP质量体检报告: "
SCRIPT_HEAD[lenTitle]="16" # 中文环境下标题长度为16个字符
SCRIPT_HEAD[gitRepo]="https://github.com/honeok/ipquery"
SCRIPT_HEAD[bash]="bash <(curl -Ls ${SCRIPT_HEAD[gitRepo]}/raw/master/ipquery.sh)"
SCRIPT_HEAD[timeIndent]="$(printf '%8s' '')" # 时间行缩进
SCRIPT_HEAD[rawTime]="$(TZ="Asia/Shanghai" date +"%Y-%m-%d %H:%M:%S %Z")"
SCRIPT_HEAD[reportTime]="报告时间: ${SCRIPT_HEAD[rawTime]}"
SCRIPT_HEAD[version]="脚本版本: $SCRIPT_VERSION"

declare -A SHOW_TYPE

# ipinfo 属性输出类型映射
SHOW_TYPE[business]="$(_yellow_bg "商业")"
SHOW_TYPE[education]="$(_yellow_bg "教育")"
SHOW_TYPE[hosting]="$(_red_bg "机房")"
SHOW_TYPE[isp]="$(_green_bg "家宽")"
SHOW_TYPE[other]="$(_yellow_bg "其他")"

## 函数库
usage_and_exit() {
    :
}

clear() {
    [ -t 1 ] && tput clear 2> /dev/null || printf "\033[2J\033[H" || command clear
}

die() {
    _err_msg >&2 "$(_red "$@")"
    exit 1
}

curl() {
    local RET

    # 添加 -f --fail 不然 404 退出码也为 0
    # 32位 cygwin 已停止更新 证书可能有问题 添加 --insecure
    # centos7 curl 不支持 --retry-connrefused --retry-all-errors 因此手动 retry

    for ((i = 1; i <= 5; i++)); do
        if command curl --connect-timeout 10 --fail --insecure "$@"; then
            return
        else
            RET="$?"
            # 403 404 错误 或达到重试次数
            if [ "$RET" -eq 22 ] || [ "$i" -eq 5 ]; then
                return "$RET"
            fi
            sleep 1
        fi
    done
}

is_in_china() {
    if [ -z "$COUNTRY" ]; then
        # www.cloudflare.com / dash.cloudflare.com 国内访问的是美国服务器 而且部分地区被墙
        # 没有ipv6 www.visa.cn
        # 没有ipv6 www.bose.cn
        # 没有ipv6 www.garmin.com.cn
        # 备用 www.prologis.cn
        # 备用 www.autodesk.com.cn
        # 备用 www.keysight.com.cn
        if ! COUNTRY="$(curl "${CURL_OPTS[@]}" -L http://www.qualcomm.cn/cdn-cgi/trace | grep '^loc=' | cut -d= -f2 | grep .)"; then
            die "Can not get location."
        fi
        echo >&2 "Location: $COUNTRY"
    fi
    [ "$COUNTRY" = CN ]
}

# 合法 IPV4 地址校验
is_legal_ipv4() {
    local IP IFS
    local -a OCTETS

    IP="$1"
    IFS=.

    # 基本格式校验
    [[ $IP =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

    read -r -a OCTETS <<< "$IP"

    # 每一段必须是 0–255
    for o in "${OCTETS[@]}"; do
        ((o >= 0 && o <= 255)) || return 1
    done

    return 0
}

# 合法 IPv6 地址校验
is_legal_ipv6() {
    local IP

    IP="$1"

    # 使用内核解析 iproute2
    ip -6 address show to "$IP" > /dev/null 2>&1 && return 0

    return 1
}

# 判断是否为公网 IPV4 排除内网 / 保留地址
is_valid_ipv4() {
    local IP IFS
    local -a OCTETS

    IP="$1"
    IFS=.

    read -r -a OCTETS <<< "$IP"

    # RFC1918 私网
    [ "${OCTETS[0]}" -eq 10 ] && return 1
    [ "${OCTETS[0]}" -eq 172 ] && [ "${OCTETS[1]}" -ge 16 ] && [ "${OCTETS[1]}" -le 31 ] && return 1
    [ "${OCTETS[0]}" -eq 192 ] && [ "${OCTETS[1]}" -eq 168 ] && return 1

    # 回环地址 127.0.0.0/8
    [ "${OCTETS[0]}" -eq 127 ] && return 1

    # 链路本地 169.254.0.0/16
    [ "${OCTETS[0]}" -eq 169 ] && [ "${OCTETS[1]}" -eq 254 ] && return 1

    # 0.0.0.0/8
    [ "${OCTETS[0]}" -eq 0 ] && return 1

    # 广播地址
    [ "$IP" = "255.255.255.255" ] && return 1

    # 文档测试地址
    [ "${OCTETS[0]}" -eq 192 ] && [ "${OCTETS[1]}" -eq 0 ] && [ "${OCTETS[2]}" -eq 2 ] && return 1
    [ "${OCTETS[0]}" -eq 198 ] && [ "${OCTETS[1]}" -eq 51 ] && [ "${OCTETS[2]}" -eq 100 ] && return 1
    [ "${OCTETS[0]}" -eq 203 ] && [ "${OCTETS[1]}" -eq 0 ] && [ "${OCTETS[2]}" -eq 113 ] && return 1

    # 多播 / 保留地址 224.0.0.0/4
    [ "${OCTETS[0]}" -ge 224 ] && return 1

    return 0
}

# 判断是否为公网 IPv6 (排除 ULA / 本地 / 保留)
is_valid_ipv6() {
    local IP

    IP="$1"

    # 回环 ::1/128
    [ "$IP" = "::1" ] && return 1

    # 未指定地址 ::/128
    [ "$IP" = "::" ] && return 1

    # Link local fe80::/10
    case "$IP" in
    fe8*:* | fe9*:* | fea*:* | feb*:*)
        return 1
        ;;
    esac

    # ULA fc00::/7
    case "$IP" in
    fc*:* | fd*:*)
        return 1
        ;;
    esac

    # 文档地址 2001:db8::/32
    case "$IP" in
    2001:db8:*)
        return 1
        ;;
    esac

    # 多播 ff00::/8
    case "$IP" in
    ff*:*)
        return 1
        ;;
    esac

    return 0
}

has_v4_v6() {
    local IP_FAMILY

    IP_FAMILY="$1"

    # 参数校验
    [ "$IP_FAMILY" != "4" ] && [ "$IP_FAMILY" != "6" ] && return 1

    ip -"$IP_FAMILY" addr show scope global 2> /dev/null | grep -q inet || return 1 # 是否存在 global 地址
    ip -"$IP_FAMILY" route show default 2> /dev/null | grep -q default || return 1  # 是否存在默认路由
    return 0
}

get_ipv4() {
    local RESPONSE

    if has_v4_v6 4; then
        IPV4_ONLINE="true"
    else
        IPV4_ONLINE="false"
        return
    fi

    for i in "${IPAPI_ENDPOINT[@]}"; do
        RESPONSE="$(curl "${CURL_OPTS[@]}" -L -4 "$i" 2> /dev/null || true)"
        if [ -n "$RESPONSE" ] && is_legal_ipv4 "$RESPONSE" && is_valid_ipv4 "$RESPONSE"; then
            IPV4_ADDRESS="$RESPONSE"
            IPV4_MASKED="$(awk -F'.' 'NF==4{print $1"."$2".*.*"} NF!=4{print ""}' <<< "$IPV4_ADDRESS")" # IPV4 模糊处理
            break
        fi
    done
}

get_ipv6() {
    local RESPONSE

    if has_v4_v6 6; then
        IPV6_ONLINE="true"
    else
        IPV6_ONLINE="false"
        return
    fi

    for i in "${IPAPI_ENDPOINT[@]}"; do
        RESPONSE="$(curl "${CURL_OPTS[@]}" -L -6 "$i" 2> /dev/null || true)"
        if [ -n "$RESPONSE" ] && is_legal_ipv6 "$RESPONSE" && is_valid_ipv6 "$RESPONSE"; then
            IPV6_ADDRESS="$RESPONSE"
            IPV6_MASKED="$(printf '%s\n' "$IPV6_ADDRESS" | sed 's/^\([^:]*:[^:]*:[^:]*\).*/\1:*:*:*:*:*/')" # IPV6 模糊处理
            break
        fi
    done
}

# 准备程序运行基础命令
install_runCmd() {
    curl "${CURL_OPTS[@]}" -L https://github.com/jqlang/jq/releases/download/jq-1.8.1/jq-linux-amd64 -o "$TEMP_DIR/jq" > /dev/null 2>&1 && chmod +x "$TEMP_DIR/jq" > /dev/null 2>&1
}

bootstrap_deps() {
    # https://github.com/ip2location/ip2location-iata-icao
    IATAICAO_DB="$(curl "${CURL_OPTS[@]}" -Ls https://fastly.jsdelivr.net/gh/ip2location/ip2location-iata-icao@master/iata-icao.csv 2> /dev/null || true)"
    # https://github.com/lmc999/RegionRestrictionCheck
    MEDIA_COOKIE="$(curl "${CURL_OPTS[@]}" -Ls https://fastly.jsdelivr.net/gh/lmc999/RegionRestrictionCheck@main/cookies 2> /dev/null || true)"
}

# 大写转换
to_upper() {
    tr '[:lower:]' '[:upper:]'
}

# 小写转换
to_lower() {
    tr '[:upper:]' '[:lower:]'
}

# 获取文本视觉宽度
visual_width() {
    local STRING CHARSET LC_ALL NON_ASCII

    STRING="$1"
    CHARSET="$(locale charmap 2> /dev/null || echo "UTF-8")" # 获取当前终端 / 系统的字符集编码

    if [[ "${CHARSET^^}" == *"GB"* ]]; then
        LC_ALL=C
        echo "${#STRING}"
    else
        NON_ASCII="${STRING//[ -~$'\t']/}"
        echo $((${#STRING} + ${#NON_ASCII}))
    fi
}

# 生成居中空格
center_padding() {
    local INPUT_TEXT SCREEN_WIDTH CONTENT_WIDTH OFFSET

    INPUT_TEXT="$1"
    SCREEN_WIDTH="${2:-80}"
    # 重新计算以确保其为正确的视觉宽度
    CONTENT_WIDTH="$(visual_width "$INPUT_TEXT")"
    OFFSET=$(((SCREEN_WIDTH - CONTENT_WIDTH) / 2))

    # 计算出偏移量直接注入变量 PADDING
    if ((OFFSET > 0)); then
        printf -v PADDING "%*s" "$OFFSET" ""
    else
        PADDING=""
    fi
}

# 生成随机 UA
gen_userAgent() {
    local TMP_RANDOM UA_VERSION

    TMP_RANDOM="$(shuf -i 0-32767 -n 1 2> /dev/null || od -vAn -N2 -tu2 < /dev/urandom | tr -d ' ')" # 模拟 RANDOM 变量用于生成 0 到 32767 之间的任一随机数

    if [ $((TMP_RANDOM % 2)) -ne 0 ]; then
        # 随机生成 Chrome 140-145
        UA_VERSION=$((140 + TMP_RANDOM % 6))
        UA_BROWSER="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$UA_VERSION.0.0.0 Safari/537.36"
    else
        # 随机生成 Firefox 140-147
        UA_VERSION=$((140 + TMP_RANDOM % 8))
        UA_BROWSER="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:$UA_VERSION.0) Gecko/20100101 Firefox/$UA_VERSION.0"
    fi
}

# 生成 DMS 格式坐标
gen_dms() {
    local LATITUDE LONGITUDE

    LATITUDE="$1"  # 纬度
    LONGITUDE="$2" # 经度

    if [ -z "$LATITUDE" ] || [ "$LATITUDE" = "null" ] || [ -z "$LONGITUDE" ] || [ "$LONGITUDE" = "null" ]; then
        return
    fi

    awk -v lat="$LATITUDE" -v lon="$LONGITUDE" '
    function to_dms(coord, pos_dir, neg_dir) {
        dir = (coord < 0) ? neg_dir : pos_dir
        if (coord < 0) coord = -coord

        deg = int(coord)
        min_raw = (coord - deg) * 60
        min = int(min_raw)
        sec = (min_raw - min) * 60

        return sprintf("%d°%d′%.0f″%s", deg, min, sec, dir)
    }
    BEGIN {
        lat_dms = to_dms(lat, "N", "S")
        lon_dms = to_dms(lon, "E", "W")
        printf "%s, %s\n", lon_dms, lat_dms
    }'
}

# 生成 Google 地图链接
# https://developers.google.com/maps/documentation/urls/get-started?hl=zh-cn#map-action
gen_googleMap() {
    local LATITUDE LONGITUDE RADIUS ZOOM_LEVEL

    LATITUDE="$1"  # 纬度
    LONGITUDE="$2" # 经度
    RADIUS="$3"    # 半径

    if [ -z "$LATITUDE" ] || [ "$LATITUDE" = "null" ] || [ -z "$LONGITUDE" ] || [ "$LONGITUDE" = "null" ] || [ -z "$RADIUS" ] || [ "$RADIUS" = "null" ]; then
        return
    fi

    # 根据半径大小动态调整地图缩放 取值范围 1-21 数值越大缩放越近
    if [ "$RADIUS" -gt 1000 ]; then
        ZOOM_LEVEL="12" # 半径 > 1km 缩放12
    elif [ "$RADIUS" -gt 500 ]; then
        ZOOM_LEVEL="13" # 半径 > 500m 缩放13
    elif [ "$RADIUS" -gt 250 ]; then
        ZOOM_LEVEL="14" # 半径 > 250m 缩放14
    else
        ZOOM_LEVEL="15" # ≤250m 就保持默认的15
    fi

    echo "https://www.google.com/maps/place/$LATITUDE,$LONGITUDE/@$LATITUDE,$LONGITUDE,${ZOOM_LEVEL}z" # 2D 纯净地图
    echo "https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=$LATITUDE,$LONGITUDE"          # 3D 街景地图
}

maxmind_db() {
    local CHECK_IP RESPONSE

    CHECK_IP="$1"
    RESPONSE="$(curl "${CURL_OPTS[@]}" -Ls "https://maxmind.iplen.de/$CHECK_IP?lang=$OUT_LANG" 2> /dev/null || true)"
    [ -n "$RESPONSE" ] || RESPONSE=""

    MAXMIND[asn]="$("$TEMP_DIR/jq" -r '.asn' <<< "$RESPONSE")"
    MAXMIND[org]="$("$TEMP_DIR/jq" -r '.org' <<< "$RESPONSE")"
    MAXMIND[city]="$("$TEMP_DIR/jq" -r '.city' <<< "$RESPONSE")"
    MAXMIND[postal]="$("$TEMP_DIR/jq" -r '.postal_code' <<< "$RESPONSE")"
    MAXMIND[latitude]="$("$TEMP_DIR/jq" -r '.latitude' <<< "$RESPONSE")"
    MAXMIND[longitude]="$("$TEMP_DIR/jq" -r '.longitude' <<< "$RESPONSE")"
    MAXMIND[radius]="$("$TEMP_DIR/jq" -r '.accuracy_radius' <<< "$RESPONSE")"
    MAXMIND[continentCode]="$("$TEMP_DIR/jq" -r '.continent_code' <<< "$RESPONSE")"
    MAXMIND[continent]="$("$TEMP_DIR/jq" -r '.continent' <<< "$RESPONSE")"
    MAXMIND[countryCode]="$("$TEMP_DIR/jq" -r '.country_code' <<< "$RESPONSE")"
    MAXMIND[country]="$("$TEMP_DIR/jq" -r '.country' <<< "$RESPONSE")"
    MAXMIND[timezone]="$("$TEMP_DIR/jq" -r '.time_zone' <<< "$RESPONSE")"
    MAXMIND[regionCode]="$("$TEMP_DIR/jq" -r 'if .region_code != null and .region_code != "" then .region_code else "N/A" end' <<< "$RESPONSE")"
    MAXMIND[region]="$("$TEMP_DIR/jq" -r 'if .region != null and .region != "" then .region else "N/A" end' <<< "$RESPONSE")"
    MAXMIND[rgsCountryCode]="$("$TEMP_DIR/jq" -r '.registered_country_code' <<< "$RESPONSE")" # 注册地国家代码
    MAXMIND[rgsCountry]="$("$TEMP_DIR/jq" -r '.registered_country' <<< "$RESPONSE")"          # 注册地国家名称

    if [ "${MAXMIND[latitude]}" != "null" ] && [ "${MAXMIND[longitude]}" != "null" ]; then
        MAXMIND[dms]="$(gen_dms "${MAXMIND[latitude]}" "${MAXMIND[longitude]}")"
        MAXMIND[map]="$(gen_googleMap "${MAXMIND[latitude]}" "${MAXMIND[longitude]}" "${MAXMIND[radius]}")"
    else
        MAXMIND[dms]="null"
        MAXMIND[map]="null"
    fi
}

ipinfo_db() {
    local CHECK_IP RESPONSE ISO3166

    CHECK_IP="$1"
    RESPONSE="$(curl "${CURL_OPTS[@]}" -Ls "https://ipinfo.io/widget/demo/$CHECK_IP" 2> /dev/null || true)"
    # https://github.com/lukes/ISO-3166-Countries-with-Regional-Codes
    ISO3166="$(curl "${CURL_OPTS[@]}" -Ls https://fastly.jsdelivr.net/gh/lukes/ISO-3166-Countries-with-Regional-Codes@master/all/all.json 2> /dev/null || true)"

    [ -n "$RESPONSE" ] || RESPONSE=""
    IPINFO[asnType]="$("$TEMP_DIR/jq" -r '.data.asn.type' <<< "$RESPONSE")"
    IPINFO[companyType]="$("$TEMP_DIR/jq" -r '.data.company.type' <<< "$RESPONSE")"

    # https://ipinfo.io/developers/asn
    # The type of the Autonomous System (AS) organization, such as hosting, ISP, education, government, or business.
    # ASN使用类型
    case "$(to_lower <<< "${IPINFO[asnType]}")" in
    business) IPINFO[showAsnType]="${SHOW_TYPE[business]}" ;;
    education) IPINFO[showAsnType]="${SHOW_TYPE[education]}" ;;
    hosting) IPINFO[showAsnType]="${SHOW_TYPE[hosting]}" ;;
    isp) IPINFO[showAsnType]="${SHOW_TYPE[isp]}" ;;
    *) IPINFO[showAsnType]="${SHOW_TYPE[other]}" ;;
    esac

    # 公司类型
    case "$(to_lower <<< "${IPINFO[companyType]}")" in
    business) IPINFO[showCompanyType]="${SHOW_TYPE[business]}" ;;
    education) IPINFO[showCompanyType]="${SHOW_TYPE[education]}" ;;
    hosting) IPINFO[showCompanyType]="${SHOW_TYPE[hosting]}" ;;
    isp) IPINFO[showCompanyType]="${SHOW_TYPE[isp]}" ;;
    *) IPINFO[showCompanyType]="${SHOW_TYPE[other]}" ;;
    esac

    # 风险因子
    IPINFO[countryCode]="$("$TEMP_DIR/jq" -r '.data.country' <<< "$RESPONSE")"
    IPINFO[proxy]="$("$TEMP_DIR/jq" -r '.data.privacy.proxy' <<< "$RESPONSE")"
    IPINFO[tor]="$("$TEMP_DIR/jq" -r '.data.privacy.tor' <<< "$RESPONSE")"
    IPINFO[vpn]="$("$TEMP_DIR/jq" -r '.data.privacy.vpn' <<< "$RESPONSE")"
    IPINFO[server]="$("$TEMP_DIR/jq" -r '.data.privacy.hosting' <<< "$RESPONSE")"
    IPINFO[postal]="$("$TEMP_DIR/jq" -r '.data.postal' <<< "$RESPONSE")"
    IPINFO[abuseCountryCode]="$("$TEMP_DIR/jq" -r '.data.abuse.country' <<< "$RESPONSE")"
    IPINFO[abuseCountry]="$("$TEMP_DIR/jq" --arg code "${IPINFO[abuseCountryCode]}" -r ".[] | select(.[\"alpha-2\"] == \$code) | .name" <<< "$ISO3166")"
}

show_head() {
    local IP_MASKED

    IP_MASKED="$1"

    echo -en "\r$(printf '%72s' "" | tr ' ' '#')\n"
    center_padding "$(printf '%*s' "${SCRIPT_HEAD[lenTitle]}" '')$IP_MASKED" 72
    echo -en "\r$PADDING$(_bold "${SCRIPT_HEAD[title]} $(_bold_cyan "$IP_MASKED")")\n" # 打印 IP 质量体检报告
    center_padding "${SCRIPT_HEAD[gitRepo]}" 72
    echo -en "\r$PADDING$(_underline "${SCRIPT_HEAD[gitRepo]}")\n" # 打印 Github 地址
    center_padding "${SCRIPT_HEAD[bash]}" 72
    echo -en "\r$PADDING${SCRIPT_HEAD[bash]}\n"                                                    # 打印执行命令
    echo -en "\r${SCRIPT_HEAD[timeIndent]}${SCRIPT_HEAD[reportTime]}    ${SCRIPT_HEAD[version]}\n" # 打印报告时间 脚本版本
    echo -en "\r$(printf '%72s' "" | tr ' ' '#')\n"
}

run_check() {
    local CHECK_IP IP_FAMILY DISPLAY_IP

    # 数据库检测
    maxmind_db "$1"
    ipinfo_db "$1"

    # 结果打印
    case "$2" in
    4)
        DISPLAY_IP="$IPV4_MASKED"
        show_head "$DISPLAY_IP"
        ;;
    6)
        DISPLAY_IP="$IPV6_MASKED"
        show_head "$DISPLAY_IP"
        ;;
    esac
}

## 解析命令行参数
while [ "$#" -gt 0 ]; do
    case "$1" in
    -h | --help)
        usage_and_exit
        ;;
    -4 | --ipv4)
        CHECK_IPV4=1
        shift
        ;;
    -6 | --ipv6)
        CHECK_IPV6=1
        shift
        ;;
    -i | --interface)
        [ -z "$2" ] || [ "${2#-}" != "$2" ] && usage_and_exit
        CURL_OPTS+=(--interface "$2")
        shift 2
        ;;
    -l | --language)
        [ -z "$2" ] || [ "${2#-}" != "$2" ] && usage_and_exit
        OUT_LANG="$(to_lower <<< "$2")"
        shift 2
        ;;
    *)
        die "Illegal option: $1"
        ;;
    esac
done

## 主程序运行 1/3
clear
get_ipv4
get_ipv6
install_runCmd
bootstrap_deps
