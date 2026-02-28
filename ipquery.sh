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

# 生成 Google 地图链接
gen_googlemap() {
    local LATITUDE LONGITUDE RADIUS ZOOM_LEVEL

    LATITUDE="$1"  # 纬度
    LONGITUDE="$2" # 经度
    RADIUS="$3"    # 半径

    if [ -z "$LATITUDE" ] || [ "$LATITUDE" = "null" ] || [ -z "$LONGITUDE" ] || [ "$LONGITUDE" = "null" ] || [ -z "$RADIUS" ] || [ "$RADIUS" = "null" ]; then
        return
    fi

    # 根据半径大小动态调整地图缩放
    if [ "$RADIUS" -gt 1000 ]; then
        ZOOM_LEVEL="12" # 半径 > 1km 缩放12
    elif [ "$RADIUS" -gt 500 ]; then
        ZOOM_LEVEL="13" # 半径 > 500m 缩放13
    elif [ "$RADIUS" -gt 250 ]; then
        ZOOM_LEVEL="14" # 半径 > 250m 缩放14
    else
        ZOOM_LEVEL="15" # ≤250m 就保持默认的15
    fi

    echo "https://www.google.com/maps/@$LATITUDE,$LONGITUDE,$ZOOM_LEVEL,cn"
}

# https://www.nodeseek.com/post-627595-1
curl -L -4 https://abiding-cistern-488411-j3.uc.r.appspot.com
curl -L -6 https://abiding-cistern-488411-j3.uc.r.appspot.com
