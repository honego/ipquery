const EMOJI_FLAG_UNICODE_STARTING_POSITION = 127397;

// 国旗转换
function getFlag(countryCode) {
  const regex = new RegExp("^[A-Z]{2}$").test(countryCode);
  if (!countryCode || !regex) return undefined;
  try {
    return String.fromCodePoint(
      ...countryCode.split("").map((char) => EMOJI_FLAG_UNICODE_STARTING_POSITION + char.charCodeAt(0)),
    );
  } catch (error) {
    return undefined;
  }
}

// 获取 Emoji 的 Unicode 字符串
function getFlagUnicode(countryCode) {
  const regex = new RegExp("^[A-Z]{2}$").test(countryCode);
  if (!countryCode || !regex) return undefined;
  try {
    return countryCode
      .split("")
      .map((char) => "U+" + (EMOJI_FLAG_UNICODE_STARTING_POSITION + char.charCodeAt(0)).toString(16).toUpperCase())
      .join(" ");
  } catch (error) {
    return undefined;
  }
}

// 获取 WARP 状态
function getWarp(asn) {
  if (!asn) return "off";
  const warpASNs = [13335, 209242];
  return warpASNs.includes(Number(asn)) ? "on" : "off";
}

// 获取时区偏移量
function getOffset(timeZone) {
  if (!timeZone) return undefined;
  try {
    const now = new Date();
    const utcDate = new Date(now.toLocaleString("en-US", { timeZone: "UTC", hour12: false }));
    const tzDate = new Date(now.toLocaleString("en-US", { timeZone: timeZone, hour12: false }));
    return Math.round((tzDate.getTime() - utcDate.getTime()) / 1000);
  } catch (error) {
    return undefined;
  }
}

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;

    // 获取请求头中的 UA
    const ua = request.headers.get("User-Agent");

    // 处理 favicon 请求
    if (path === "/favicon.ico") {
      if (!ua) {
        return new Response(null, { status: 204 });
      } else {
        const svgIcon =
          '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="icon icon-tabler icons-tabler-outline icon-tabler-live-view"><path stroke="none" d="M0 0h24v24H0z" fill="none"/><path d="M4 8v-2a2 2 0 0 1 2 -2h2" /><path d="M4 16v2a2 2 0 0 0 2 2h2" /><path d="M16 4h2a2 2 0 0 1 2 2v2" /><path d="M16 20h2a2 2 0 0 0 2 -2v-2" /><path d="M12 11l0 .01" /><path d="M12 18l-3.5 -5a4 4 0 1 1 7 0l-3.5 5" /></svg>';

        return new Response(svgIcon, {
          headers: {
            "Content-Type": "image/svg+xml",
            "Cache-Control": "public, max-age=86400",
          },
        });
      }
    }

    // 提取通用变量
    const clientIP = request.headers.get("CF-Connecting-IP") || "127.0.0.1";
    const cf = request.cf || {};

    // 全局 CORS 头 确保前端直接 Fetch 不被拦截
    const corsHeaders = {
      "Access-Control-Allow-Origin": "*",
    };

    // 根路径仅返回IP
    if (path === "/") {
      return new Response(clientIP + "\n", {
        headers: {
          ...corsHeaders,
          "Content-Type": "text/plain; charset=utf-8",
        },
      });
    }

    // JSON 返回详细信息
    if (path === "/json") {
      const data = {
        ip: clientIP,
        asn: cf.asn,
        org: cf.asOrganization,
        colo: cf.colo,
        continent: cf.continent,
        country: cf.country,
        emoji: getFlag(cf.country),
        emoji_unicode: getFlagUnicode(cf.country),
        region: cf.region,
        regionCode: cf.regionCode,
        city: cf.city,
        postalCode: cf.postalCode,
        metroCode: cf.metroCode,
        latitude: cf.latitude,
        longitude: cf.longitude,
        warp: getWarp(cf.asn),
        offset: getOffset(cf.timezone),
        timezone: cf.timezone,
      };

      const dataJson = JSON.stringify(data, null, 2);
      return new Response(dataJson, {
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json; charset=utf-8",
        },
      });
    }

    // 避免异常路径穿透
    return new Response("Not Found", { status: 404 });
  },
};
