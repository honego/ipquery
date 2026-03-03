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

    // 拦截图标请求
    if (path === "/favicon.ico") {
      return new Response(null, { status: 204 });
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
