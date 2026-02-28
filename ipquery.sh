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

# shellcheck disable=all

set -eE

# MAJOR.MINOR.PATCH
# shellcheck disable=SC2034
readonly SCRIPT_VERSION='v1.0.0'

_red() {
    printf "\033[31m%b\033[0m\n" "$*"
}

_green() {
    printf "\033[32m%b\033[0m\n" "$*"
}

_yellow() {
    printf "\033[33m%b\033[0m\n" "$*"
}

_cyan() {
    printf "\033[36m%b\033[0m\n" "$*"
}

_err_msg() {
    printf "\033[41m\033[1mError\033[0m %b\n" "$*"
}

_suc_msg() {
    printf "\033[42m\033[1mSuccess\033[0m %b\n" "$*"
}

_warn_msg() {
    printf "\033[43m\033[1mWarning\033[0m %b\n" "$*"
}

# 斜体输出
_italic() {
    printf "\033[3m%b\033[23m\n" "$*"
}

## 定义关联数组

declare -A MAXMIND
declare -A IPINFO

declare -A SHOW_TYPE

SHOW_TYPE[business]="$Back_Yellow$Font_White$Font_B 商业 $Font_Suffix"
SHOW_TYPE[education]="$Back_Yellow$Font_White$Font_B 教育 $Font_Suffix"
SHOW_TYPE[hosting]="$Back_Red$Font_White$Font_B 机房 $Font_Suffix"
SHOW_TYPE[isp]="$Back_Green$Font_White$Font_B 家宽 $Font_Suffix"
SHOW_TYPE[other]="$Back_Yellow$Font_White$Font_B 其他 $Font_Suffix"

# 各变量默认值
TEMP_DIR="$(mktemp -d 2> /dev/null)"

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
        if command curl --insecure --connect-timeout 10 -f "$@"; then
            return
        else
            RET="$?"
            # 403 404 错误 或达到重试次数
            if [ $RET -eq 22 ] || [ $i -eq 5 ]; then
                return $RET
            fi
            sleep 1
        fi
    done
}

is_in_china() {
    if [ -z "$COUNTRY" ]; then
        # www.cloudflare.com / dash.cloudflare.com 国内访问的是美国服务器，而且部分地区被墙
        # 没有ipv6 www.visa.cn
        # 没有ipv6 www.bose.cn
        # 没有ipv6 www.garmin.com.cn
        # 备用 www.prologis.cn
        # 备用 www.autodesk.com.cn
        # 备用 www.keysight.com.cn

        if ! COUNTRY="$(curl -Ls http://www.qualcomm.cn/cdn-cgi/trace | grep '^loc=' | cut -d= -f2 | grep .)"; then
            die "Can not get location."
        fi
        echo >&2 "Location: $COUNTRY"
    fi
    [ "$COUNTRY" = CN ]
}

# 准备程序运行基础命令
check_cmd() {
    curl -LsS https://github.com/jqlang/jq/releases/download/jq-1.8.1/jq-linux-amd64 -o "$TEMP_DIR/jq" > /dev/null 2>&1 && chmod +x "$TEMP_DIR/jq" > /dev/null 2>&1
}

# 小写转换
to_lower() {
    tr '[:upper:]' '[:lower:]'
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
gen_googlemap() {
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
    local RESPONSE

    RESPONSE="$(curl -Ls "https://maxmind.haiok.de/$(curl -Ls ip.haiok.de)?lang=cn" 2> /dev/null || true)"
    [ -n "$RESPONSE" ] || RESPONSE=""

    MAXMIND[asn]="$("$TEMP_DIR/jq" -r '.asn' <<< "$RESPONSE")"
    MAXMIND[org]="$("$TEMP_DIR/jq" -r '.org' <<< "$RESPONSE")"
}

ipinfo_db() {
    local RESPONSE ISO3166

    RESPONSE="$(curl -Ls "https://ipinfo.io/widget/demo/$(curl -Ls ip.haiok.de)" 2> /dev/null || true)"
    # https://github.com/lukes/ISO-3166-Countries-with-Regional-Codes
    ISO3166="$(curl -Ls https://fastly.jsdelivr.net/gh/lukes/ISO-3166-Countries-with-Regional-Codes@master/all/all.json)"

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
    IPINFO[abuseCountry]="$("$TEMP_DIR/jq" --arg code "${IPINFO[abuseCountryCode]}" -r '.[] | select(.["alpha-2"] == $code) | .name' <<< "$ISO3166")"
}

# https://www.nodeseek.com/post-627595-1
# curl -L -4 https://abiding-cistern-488411-j3.uc.r.appspot.com
# curl -L -6 https://abiding-cistern-488411-j3.uc.r.appspot.com
