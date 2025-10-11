#!/usr/bin/env bash

print_help() {
    cat <<'END'
Usage: httpstat URL [CURL_OPTIONS]
       httpstat -h | --help
       httpstat --version
Arguments:
  URL     url to request, could be with or without `http(s)://` prefix
Options:
  CURL_OPTIONS  any curl supported options, except for -w -D -o -S -s,
                which are already used internally.
  -h --help     show this screen.
  --version     show version.
Environments:
  HTTPSTAT_SHOW_BODY    By default httpstat will write response body
                        in a tempfile, but you can let it print out by setting
                        this variable to `true`.
  HTTPSTAT_SHOW_SPEED   set to `true` to show download and upload speed.
END
}

green="\033[32m"
cyan="\033[36m"
white="\033[37m"
reset="\033[0m"

while (( $# > 0 ))
do
    case "$1" in
        -h | --help)
            print_help
            exit 1
            ;;
        --version)
            echo "httpstat 0.0.1"
            exit 0
            ;;
        '-w' | '--write-out')
            continue
            ;;
        '-D' | '--dump-header')
            continue
            ;;
        '-o' | '--output')
            continue
            ;;
        '-s' | '--silent')
            continue
            ;;
        -* | --*)
            args+=( "$1" )
            ;;
        *)
            url="$1"
            ;;
    esac
    shift
done

if [[ -z $url ]]; then
    echo "too few arguments" >&2
    exit 1
fi

curl_format='{
"time_namelookup": %{time_namelookup},
"time_connect": %{time_connect},
"time_appconnect": %{time_appconnect},
"time_pretransfer": %{time_pretransfer},
"time_redirect": %{time_redirect},
"time_starttransfer": %{time_starttransfer},
"time_total": %{time_total},
"speed_download": %{speed_download},
"speed_upload": %{speed_upload},
"http_version": %{http_version},
"protocol": "%{scheme}"
}'

head="/tmp/httpstat-header.$$$RANDOM$(date +%s)"
body="/tmp/httpstat-body.$$$RANDOM$(date +%s)"

data="$(
LC_ALL=C curl \
    -w "$curl_format" \
    -D "$head" \
    -o "$body" \
    -s -S \
    "${args[@]}" \
    "$url" 2>&1
)"

get() {
    local d
    d="$(
    echo "$data" \
        | grep "$1" \
        | awk '{print $2}' \
        | sed 's/,//g'
    )"
    
    # 对于字符串字段，不进行数值转换
    if [ "$1" = "http_version" ] || [ "$1" = "protocol" ]; then
        echo "$d"
    else
        # 对于时间字段，转换为毫秒
        if type bc &>/dev/null; then
            echo "$d"*1000 | bc -l
        else
            echo "$d" | awk 'END{print $0*1000}'
        fi
    fi
}

calc() {
    if type bc &>/dev/null; then
        echo "$@" | bc -l
    else
        echo "$@" | awk "BEGIN{print $*}"
    fi
}

time_namelookup="$(get time_namelookup)"
time_connect="$(get time_connect)"
time_appconnect="$(get time_appconnect)"
time_pretransfer="$(get time_pretransfer)"
time_redirect="$(get time_redirect)"
time_starttransfer="$(get time_starttransfer)"
time_total="$(get time_total)"
speed_download="$(get speed_download)"
speed_upload="$(get speed_upload)"
http_version="$(get http_version)"
protocol="$(get protocol)"

# 检测协议类型和优化时间计算
range_dns="$time_namelookup"

# 准确检测协议类型
is_http3=false

# 方法1: 检查HTTP版本 (HTTP/3会显示为3或3.0)
if [ "$http_version" = "3" ] || [ "$http_version" = "3.0" ]; then
    is_http3=true
fi

# 方法2: 检查命令行参数中是否指定了HTTP/3
if echo "$*" | grep -q "\-\-http3"; then
    is_http3=true
fi

# 方法3: 通过检查curl的详细输出来确认HTTP/3
# 检查curl输出中是否包含HTTP/3相关信息
if echo "$data" | grep -q "HTTP/3" || echo "$data" | grep -q "QUIC"; then
    is_http3=true
fi

# 方法4: 检查time_appconnect (HTTP/3中通常为0，因为没有单独的TLS握手)
if [ "$(echo "$time_appconnect < 0.001" | bc -l 2>/dev/null || echo "0")" = "1" ] && [ "$http_version" != "1.1" ] && [ "$http_version" != "2.0" ]; then
    is_http3=true
fi

# 调试信息（可以删除）
# echo "DEBUG: http_version='$http_version', is_http3='$is_http3'" >&2

# 计算时间差值，避免负数显示
range_connection="$(calc "$time_connect" - "$time_namelookup")"
range_ssl="$(calc "$time_pretransfer" - "$time_connect")"
range_server="$(calc "$time_starttransfer" - "$time_pretransfer")"
range_transfer="$(calc "$time_total" - "$time_starttransfer")"

# 使用awk确保非负数显示
range_connection="$(echo "$range_connection" | awk '{print ($1 < 0) ? 0 : $1}')"
range_ssl="$(echo "$range_ssl" | awk '{print ($1 < 0) ? 0 : $1}')"
range_server="$(echo "$range_server" | awk '{print ($1 < 0) ? 0 : $1}')"
range_transfer="$(echo "$range_transfer" | awk '{print ($1 < 0) ? 0 : $1}')"

# 调试信息：显示时间计算结果
# echo "DEBUG: range_connection='$range_connection', range_ssl='$range_ssl'" >&2

fmta() {
    echo "$1" \
        | awk '{printf("%5dms\n", $1 + 0.5)}'
}

fmtb() {
    local d
    d="$(
    echo "$1" \
        | awk '{printf("%d\n", $1 + 0.5)}'
    )"
    printf "%-7s\n" "${d}ms"
}

a000="$cyan$(fmta "$range_dns")$reset"
a001="$cyan$(fmta "$range_connection")$reset"
a002="$cyan$(fmta "$range_ssl")$reset"
a003="$cyan$(fmta "$range_server")$reset"
a004="$cyan$(fmta "$range_transfer")$reset"
b000="$cyan$(fmtb "$time_namelookup")$reset"
b001="$cyan$(fmtb "$time_connect")$reset"
b002="$cyan$(fmtb "$time_pretransfer")$reset"
b003="$cyan$(fmtb "$time_starttransfer")$reset"
b004="$cyan$(fmtb "$time_total")$reset"

# 根据协议类型选择模板
if [ "$is_http3" = true ]; then
    # HTTP/3 模板
    https_template="$white
  DNS Lookup   QUIC Connection   Server Processing   Content Transfer$reset
[   ${a000}  |     ${a001}    |      ${a003}      |      ${a004}     ]
             |                |                   |                  |
    namelookup:${b000}        |                   |                  |
                        connect:${b001}           |                  |
                                      starttransfer:${b003}          |
                                                                 total:${b004}
"
    http_template="$white
  DNS Lookup   QUIC Connection   Server Processing   Content Transfer$reset
[   ${a000}  |     ${a001}    |      ${a003}      |      ${a004}     ]
             |                |                   |                  |
    namelookup:${b000}        |                   |                  |
                        connect:${b001}           |                  |
                                      starttransfer:${b003}          |
                                                                 total:${b004}
"
else
    # 传统HTTP模板
    https_template="$white
  DNS Lookup   TCP Connection   SSL Handshake   Server Processing   Content Transfer$reset
[   ${a000}  |     ${a001}    |    ${a002}    |      ${a003}      |      ${a004}     ]
             |                |               |                   |                  |
    namelookup:${b000}        |               |                   |                  |
                        connect:${b001}       |                   |                  |
                                    pretransfer:${b002}           |                  |
                                                      starttransfer:${b003}          |
                                                                                 total:${b004}
"

    http_template="$white
  DNS Lookup   TCP Connection   Server Processing   Content Transfer$reset
[   ${a000}  |     ${a001}    |      ${a003}      |      ${a004}     ]
             |                |                   |                  |
    namelookup:${b000}        |                   |                  |
                        connect:${b001}           |                  |
                                      starttransfer:${b003}          |
                                                                 total:${b004}
"
fi

# output, need to print escape sequences raw (disable those checks for shellcheck)
# shellcheck disable=SC2059,SC2002
{
    # Print header
    cat "$head" \
        | perl -pe 's/^(HTTP)(.*)$/'"$green"'$1'"$reset""$cyan"'$2'"$reset"'/g' \
        | perl -pe 's/^(.*?): (.*)$/'"$white"'$1: '"$cyan"'$2/g'
    printf "$reset"
    
    # 显示协议类型
    if [ "$is_http3" = true ]; then
        printf "${yellow}Protocol: HTTP/3 (QUIC)${reset}\n"
    else
        case "$http_version" in
            "1.1")
                printf "${yellow}Protocol: HTTP/1.1 (TCP)${reset}\n"
                ;;
            "2.0")
                printf "${yellow}Protocol: HTTP/2 (TCP)${reset}\n"
                ;;
            "3"|"3.0")
                printf "${yellow}Protocol: HTTP/3 (QUIC)${reset}\n"
                ;;
            *)
                printf "${yellow}Protocol: HTTP/$http_version (TCP)${reset}\n"
                ;;
        esac
    fi

    # Print body
    if [[ "$HTTPSTAT_SHOW_BODY" == true ]]; then
        cat "$body"; printf '\n'
    else
        printf "${green}Body${reset} stored in: $body\n"
    fi

    if [[ "$url" =~ https:// ]]; then
        printf "$https_template\n"
    else
        printf "$http_template\n"
    fi

    # speed, originally bytes per second
    if [[ "$HTTPSTAT_SHOW_SPEED" == true ]]; then
        printf "speed_download %.1f KiB, speed_upload %.1f KiB\n" \
            "$(calc "$speed_download" / 1024)" \
            "$(calc "$speed_upload" / 1024)"
    fi
}