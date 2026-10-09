// ThinkPad Sunset Backlight: sun math, no Quickshell imports.

var RAD = Math.PI / 180

// Sunrise and sunset for the day containing `date`, at lat/lon in degrees.
// Standard sunrise equation; good to a minute or two, plenty for a light.
// Returns { rise, set } in epoch ms, or null near the poles.
function sunTimes(date, lat, lon) {
  var noon = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 12)
  var jd = noon.getTime() / 86400000 + 2440587.5
  var n = Math.round(jd - 2451545.0 + 0.0008)
  var jStar = n - lon / 360
  var m = (357.5291 + 0.98560028 * jStar) % 360
  var c = 1.9148 * Math.sin(m * RAD) + 0.02 * Math.sin(2 * m * RAD) + 0.0003 * Math.sin(3 * m * RAD)
  var lambda = (m + c + 180 + 102.9372) % 360
  var transit = 2451545.0 + jStar + 0.0053 * Math.sin(m * RAD) - 0.0069 * Math.sin(2 * lambda * RAD)
  var sinDec = Math.sin(lambda * RAD) * Math.sin(23.4397 * RAD)
  var cosDec = Math.cos(Math.asin(sinDec))
  var cosW = (Math.sin(-0.833 * RAD) - Math.sin(lat * RAD) * sinDec) / (Math.cos(lat * RAD) * cosDec)
  if (cosW < -1 || cosW > 1) return null
  var w = Math.acos(cosW) / RAD
  function toMs(j) { return (j - 2440587.5) * 86400000 }
  return { rise: toMs(transit - w / 360), set: toMs(transit + w / 360) }
}

// True between (sunset - leadMinutes) and sunrise.
function isDark(now, lat, lon, leadMinutes) {
  var t = sunTimes(now, lat, lon)
  if (!t) return false
  var ms = now.getTime()
  return ms < t.rise || ms >= t.set - leadMinutes * 60000
}

// "+340308-1181434" (±DDMM[SS]±DDDMM[SS], zone.tab format) → { lat, lon }.
function parseIso6709(s) {
  var m = String(s || "").trim().match(/^([+-])(\d{2})(\d{2})(\d{2})?([+-])(\d{3})(\d{2})(\d{2})?$/)
  if (!m) return null
  function deg(sign, d, mm, ss) {
    var v = parseInt(d, 10) + parseInt(mm, 10) / 60 + (ss ? parseInt(ss, 10) / 3600 : 0)
    return sign === "-" ? -v : v
  }
  return { lat: deg(m[1], m[2], m[3], m[4]), lon: deg(m[5], m[6], m[7], m[8]) }
}

// "19:05", "7:05 PM", "7pm" → minutes after midnight, or -1.
function parseClock(s) {
  var m = String(s || "").trim().toLowerCase().match(/^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$/)
  if (!m) return -1
  var h = parseInt(m[1], 10), mi = m[2] ? parseInt(m[2], 10) : 0
  if (mi > 59) return -1
  if (m[3]) {
    if (h < 1 || h > 12) return -1
    h = h % 12 + (m[3] === "pm" ? 12 : 0)
  } else if (h > 23 || !m[2]) return -1
  return h * 60 + mi
}

// epoch ms → "6:38 PM"
function clock12(ms) {
  var d = new Date(ms)
  var h = d.getHours(), mi = d.getMinutes()
  return (h % 12 || 12) + ":" + (mi < 10 ? "0" : "") + mi + (h < 12 ? " AM" : " PM")
}

function atMinutes(day, minutes) {
  return new Date(day.getFullYear(), day.getMonth(), day.getDate(), 0, minutes).getTime()
}

// Where the light should be now and what happens next.
// opts: { onMin, offMin, lat, lon, leadMinutes }. A time of -1 means
// "follow the sun" for that side: on before sunset, off at sunrise.
// Returns { dark, nextOn, nextOff } or null.
function schedule(now, opts) {
  var ms = now.getTime()
  var needSun = opts.onMin < 0 || opts.offMin < 0
  if (needSun && (isNaN(opts.lat) || isNaN(opts.lon))) return null
  function sun(d) { return sunTimes(d, opts.lat, opts.lon) }
  var onAt = opts.onMin >= 0
    ? function(d) { return atMinutes(d, opts.onMin) }
    : function(d) { var t = sun(d); return t ? t.set - opts.leadMinutes * 60000 : NaN }
  var offAt = opts.offMin >= 0
    ? function(d) { return atMinutes(d, opts.offMin) }
    : function(d) { var t = sun(d); return t ? t.rise : NaN }
  var tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 12)
  var on = onAt(now), off = offAt(now)
  if (isNaN(on) || isNaN(off)) return null
  var events = [
    { kind: "on", at: on }, { kind: "off", at: off },
    { kind: "on", at: onAt(tomorrow) }, { kind: "off", at: offAt(tomorrow) }
  ].sort(function(a, b) { return a.at - b.at })
  var next = null, nextOn = NaN, nextOff = NaN
  for (var i = 0; i < events.length; i++) {
    var e = events[i]
    if (e.at <= ms) continue
    if (!next) next = e
    if (e.kind === "on" && isNaN(nextOn)) nextOn = e.at
    if (e.kind === "off" && isNaN(nextOff)) nextOff = e.at
  }
  if (!next) return null
  // Dark now exactly when the next thing to happen is the light going off.
  return { dark: next.kind === "off", nextOn: nextOn, nextOff: nextOff }
}
