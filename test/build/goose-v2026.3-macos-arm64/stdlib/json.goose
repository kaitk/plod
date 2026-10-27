// JSON (RFC 8259; docs/stdlib.md): a writer that appends values to a byte
// builder, a parser that builds a document tree, and a reader that parses
// straight into the caller's own types, the way a serde derive does.

namespace json;

import std;

// --- writing --------------------------------------------------------------------

// s as a JSON string: quoted, with '"', '\' and the control characters
// escaped. Most strings have none of those, and go out in one piece.
fn format_string(out: u8[>..]&, s: u8[:]) {
    out.push('"');
    if plain(s) { out.append(s); } else { format_escaped(out, s); }
    out.push('"');
}

// An object key and its colon.
fn format_key(out: u8[>..]&, key: u8[:]) {
    out.push('"');
    if plain(key) { out.append(key); } else { format_escaped(out, key); }
    out.append("\":");
}

// Whether s holds nothing a JSON string escapes.
fn plain(s: u8[:]) -> bool {
    for c in s {
        if c < 0x20 || c == '"' || c == '\\' { return false; }
    }
    return true;
}

// s with its quotes, backslashes and control characters escaped.
fn format_escaped(out: u8[>..]&, s: u8[:]) {
    var start = 0;
    for c, i in s {
        if c >= 0x20 && c != '"' && c != '\\' { continue; }
        out.append(s[start..i]);
        start = i + 1;
        if c == '"' || c == '\\' { out.push('\\'); out.push(c); }
        else if c == '\n' { out.append("\\n"); }
        else if c == '\r' { out.append("\\r"); }
        else if c == '\t' { out.append("\\t"); }
        else if c == 8 { out.append("\\b"); }
        else if c == 12 { out.append("\\f"); }
        else {
            out.append("\\u00");
            out.push("0123456789abcdef"[c >> 4]);
            out.push("0123456789abcdef"[c & 15]);
        }
    }
    out.append(s[start..]);
}

fn format_bool(out: u8[>..]&, b: bool) {
    out.append(if b { "true" } else { "false" });
}

fn format_int(out: u8[>..]&, v: i64) {
    format(out, v);
}

// The two digits of each number below 100, so that digits come out of a
// division by 100 two at a time.
let DIGIT_PAIRS = "00010203040506070809101112131415161718192021222324252627282930313233343536373839404142434445464748495051525354555657585960616263646566676869707172737475767778798081828384858687888990919293949596979899";

// 10^0 .. 10^22, each exact in binary64.
let POW10: f64[23] = [1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11,
                      1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22];

// The powers of ten and of five that fit a u64.
let POW10_U64: u64[20] = [1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000,
                          10000000000, 100000000000, 1000000000000, 10000000000000, 100000000000000,
                          1000000000000000, 10000000000000000, 100000000000000000, 1000000000000000000,
                          10000000000000000000];
let POW5: u64[28] = [1, 5, 25, 125, 625, 3125, 15625, 78125, 390625, 1953125, 9765625, 48828125,
                     244140625, 1220703125, 6103515625, 30517578125, 152587890625, 762939453125,
                     3814697265625, 19073486328125, 95367431640625, 476837158203125, 2384185791015625,
                     11920928955078125, 59604644775390625, 298023223876953125, 1490116119384765625,
                     7450580596923828125];

// The bits of a double.
fn bits_of(x: f64) -> u64 {
    let a: f64[1] = [x];
    let b = bytes_of(a);
    return b[0] | (b[1] as u64) << 8 | (b[2] as u64) << 16 | (b[3] as u64) << 24 |
        (b[4] as u64) << 32 | (b[5] as u64) << 40 | (b[6] as u64) << 48 | (b[7] as u64) << 56;
}

// a * b in 128 bits: the high and the low half.
fn mul_wide(a: u64, b: u64) -> u64, u64 {
    let a0 = a & 0xFFFFFFFF;
    let a1 = a >> 32;
    let b0 = b & 0xFFFFFFFF;
    let b1 = b >> 32;
    let p00 = a0 * b0;
    let p01 = a0 * b1;
    let p10 = a1 * b0;
    let mid = (p00 >> 32) + (p01 & 0xFFFFFFFF) + (p10 & 0xFFFFFFFF);
    return a1 * b1 + (p01 >> 32) + (p10 >> 32) + (mid >> 32), (mid << 32) | (p00 & 0xFFFFFFFF);
}

// v as a JSON number: the fewest significant digits that read back as v,
// laid out as serde_json's ryu lays them out: 0.5, 1.0, 123.25, 1e-7,
// 1.5e300, 0.30000000000000004. JSON has no NaN or infinity, so those are
// written as null, as serde_json writes them.
fn format_number(out: u8[>..]&, v: f64) {
    var text: u8[21] = [0; 21];
    let len, point = ryu_digits(v, text[1..]);
    guard len > 0 else { format_other(out, v); return; }
    if v < 0.0 { out.push('-'); }
    lay_out(out, text, len, point);
}

// format_number for v outside ryu_digits' range. It is called from a
// guard's else only, which keeps its fallbacks, big and seldom taken, out
// of line instead of in format_number's fast path.
fn format_other(out: u8[>..]&, v: f64) {
    if v != v || v - v != 0.0 { out.append("null"); return; }
    if v == 0.0 { out.append(if 1.0 / v < 0.0 { "-0.0" } else { "0.0" }); return; }
    var text: u8[21] = [0; 21];
    let len, point = general_digits(abs(v), text[1..18]);
    if v < 0.0 { out.push('-'); }
    lay_out(out, text, len, point);
}

// The number 0.d1 d2 ... dlen * 10^point as format_number writes it, the
// digits in text[1..len + 1]: one place in, so that a point can go in front
// of the fraction by moving the digits before it, nearly always one to
// three, out.
inline fn lay_out(out: u8[>..]&, text: u8[21]&, digits: i64, point: i64) {
    var len = digits;
    while text[len] == '0' { len--; }
    if point > 0 && point < len {
        for i in point { text[i] = text[i + 1]; }
        text[point] = '.';
        out.append(text[..len + 1]);
        return;
    }
    let d = text[1..len + 1];
    if point >= len && point <= 16 {
        out.append(d);
        for i in point - len { out.push('0'); }
        out.append(".0");
    } else if point > -5 && point <= 0 {
        out.append("0.");
        for i in -point { out.push('0'); }
        out.append(d);
    } else {
        out.push(d[0]);
        if len > 1 {
            out.push('.');
            out.append(d[1..]);
        }
        out.push('e');
        format_int(out, point - 1);
    }
}

// The digits of the shortest form of |x| into out, with their count and
// the power of ten they are a fraction of, as format_number takes them; a
// count of 0 for |x| outside about [1e-10, 2^51], NaN and the infinities
// included, which format_number handles otherwise. This is ryu's digit
// loop, run on exact values instead of ryu's tables: with |x| = m * 2^-sh
// and k chosen to give |x| * 10^k 18 or 19 digits, |x| * 10^k and the
// bounds of the interval that reads back as x, half an ulp either side (a
// quarter below a power of two), are 4m * 5^k and 2 * 5^k apart in units of
// 2^(k - sh - 2): 128-bit integers, which shifted right give ryu's vr, vp
// and vm, and the bits shifted out whether each is exact. The range is where
// 5^k fits a u64 and the shift is within one.
inline fn ryu_digits(x: f64, out: u8[:]) -> i64, i64 {
    let b = bits_of(x);
    let be = ((b >> 52) & 0x7FF) as! i64;
    let frac = b & 0xFFFFFFFFFFFFF;
    let k = 17 - (((be - 1023) * 78913) >> 18);     // 17 - floor(log10(2^(be - 1023)))
    let t = 1077 - be - k;                          // sh + 2 - k, sh = 1075 - be
    guard k >= 0 && k <= 27 && t >= 1 && t <= 63 else { return 0, 0; }
    let m = frac | 0x10000000000000;
    let even = (m & 1) == 0;
    let p = POW5[k];
    let nh, nl = mul_wide(m, p);
    // 4x, and the upper and lower bounds.
    let xh = (nh << 2) | (nl >> 62);
    let xl = nl << 2;
    var uh = xh;
    var ul = xl;
    for i in 2 {
        ul += p;
        if ul < p { uh++; }
    }
    var lh = xh;
    var ll = xl;
    for i in (if frac != 0 { 2 } else { 1 }) {
        if ll < p { lh--; }
        ll -= p;
    }
    let low = ((1 as u64) << t) - 1;
    var vr = (xh << (64 - t)) | (xl >> t);
    var vp = (uh << (64 - t)) | (ul >> t);
    var vm = (lh << (64 - t)) | (ll >> t);
    let digits0 = if vr >= 1000000000000000000 { 19 } else { 18 };
    var vr_exact = (xl & low) == 0;
    var vm_exact = even && (ll & low) == 0;
    if !even && (ul & low) == 0 { vp--; }
    var removed = 0;
    var c: u64 = 0;
    if !vr_exact && !vm_exact {
        // Nearly always neither x * 10^k nor an included lower bound is
        // exact, and the digits dropped only round: ryu's common case, two
        // digits a step first, then one.
        var round_up = false;
        let vp100 = vp / 100;
        let vm100 = vm / 100;
        if vp100 > vm100 {
            let vr100 = vr / 100;
            round_up = vr - 100 * vr100 >= 50;
            vr = vr100;
            vp = vp100;
            vm = vm100;
            removed = 2;
        }
        loop {
            let vp10 = vp / 10;
            let vm10 = vm / 10;
            if vp10 <= vm10 { break; }
            let vr10 = vr / 10;
            round_up = vr - 10 * vr10 >= 5;
            vr = vr10;
            vp = vp10;
            vm = vm10;
            removed++;
        }
        c = vr + (if vr == vm || round_up { 1 } else { 0 });
    } else {
        var last: u64 = 0;
        loop {
            let vp10 = vp / 10;
            let vm10 = vm / 10;
            if vp10 <= vm10 { break; }
            let vr10 = vr / 10;
            vm_exact = vm_exact && vm - 10 * vm10 == 0;
            vr_exact = vr_exact && last == 0;
            last = vr - 10 * vr10;
            vr = vr10;
            vp = vp10;
            vm = vm10;
            removed++;
        }
        if vm_exact {
            loop {
                let vm10 = vm / 10;
                if vm - 10 * vm10 != 0 { break; }
                let vr10 = vr / 10;
                vr_exact = vr_exact && last == 0;
                last = vr - 10 * vr10;
                vr = vr10;
                vp /= 10;
                vm = vm10;
                removed++;
            }
        }
        if vr_exact && last == 5 && vr % 2 == 0 { last = 4; }
        c = vr + (if (vr == vm && !vm_exact) || last >= 5 { 1 } else { 0 });
    }
    var len = digits0 - removed;
    if c >= POW10_U64[len] { len++; }
    put_digits(out[..len], c);
    return len, len + removed - k;
}

// The digits of the shortest form of x > 0 outside ryu_digits' range, as
// it gives them. A double whose shortest form has at most 15 significant
// digits, as most have, is x rounded to 15 digits: above the subnormals the
// 15-digit decimals are further apart than x's neighbours, so at most one
// of them reads back as x, the nearest. With x * 10^s scaled into [10^14,
// 10^15) by an exact power of ten, that decimal is the nearest integer n,
// and it reads back as x exactly when n / 10^s, one correctly rounded
// division, is x. shortest_digits handles the rest.
fn general_digits(x: f64, out: u8[:]) -> i64, i64 {
    var s = 15;
    var p = x * 1e15;
    while p < 1e14 && s < 22 { s++; p = x * POW10[s]; }
    while p >= 1e15 && s > -22 { s--; p = if s >= 0 { x * POW10[s] } else { x / POW10[-s] }; }
    if p >= 1e14 && p < 1e15 {
        var n = (p + 0.5) as! u64;
        if n == 1000000000000000 { n = 100000000000000; s--; }
        let back = if s >= 0 { n / POW10[s] } else { n * POW10[-s] };
        if back == x {
            put_digits(out[..15], n);
            return 15, 15 - s;
        }
    }
    return shortest_digits(x, out);
}

// The decimal digits of v, below 10^out.len, zero-padded to fill out: eight
// at a time from the right, and what is left above them two at a time.
inline fn put_digits(out: u8[:], v: u64) {
    var x = v;
    var i = out.len;
    while i >= 8 {
        put8(out, i - 8, x % 100000000);
        x /= 100000000;
        i -= 8;
    }
    while i >= 2 {
        let r = x % 100;
        x /= 100;
        i -= 2;
        out[i] = DIGIT_PAIRS[2 * r];
        out[i + 1] = DIGIT_PAIRS[2 * r + 1];
    }
    if i == 1 { out[0] = ('0' + x) as! u8; }
}

// v, below 10^8, as 8 digits into out[at..at + 8], all at once: four lanes
// of the 64-bit word split their numbers by multiplying by reciprocals until
// each byte holds one digit.
fn put8(out: u8[:], at: i64, v: u64) {
    let merged = (v / 10000) | ((v % 10000) << 32);
    let top = ((merged * 10486) >> 20) & 0x0000007F0000007F;
    let hundreds = ((merged - 100 * top) << 16) + top;
    var tens = ((hundreds * 103) >> 10) & 0x000F000F000F000F;
    tens += (hundreds - 10 * tens) << 8;
    let w = tens | 0x3030303030303030;
    let o = out[at..at + 8];
    for j in 8 { o[j] = (w >> (8 * j)) as! u8; }
}

// The rest of general_digits: the digits of the shortest form of x > 0, into
// `out`, with their count and the power of ten they are a fraction of. The
// builtin text of a double has 15 significant digits if those read back,
// which above the subnormals makes it the shortest form once its trailing
// zeros are dropped, and the correctly rounded 17 otherwise. Here 17 digits
// are tried at 16, and a subnormal's at every length below its own, since
// its neighbours lie further apart: at each length the two decimals around
// the digits held, the nearer first, through the exact parser.
fn shortest_digits(x: f64, out: u8[:]) -> i64, i64 {
    var text: u8[..32] = [];
    format(text, x);
    var len = 0;
    var point = 0;
    var frac = false;           // past the point
    var lead = true;            // before the first digit other than 0
    var i = 0;
    while i < text.len && text[i] != 'e' {
        let c = text[i];
        i++;
        if c == '.' { frac = true; continue; }
        if lead && c == '0' {
            if frac { point--; }
            continue;
        }
        lead = false;
        if len < out.len {
            out[len] = c;
            len++;
        }
        if !frac { point++; }
    }
    if i < text.len {
        let e, end = scan_exponent(text, i + 1);
        point += e;
    }
    while len > 1 && out[len - 1] == '0' { len--; }
    let subnormal = x < 2.2250738585072014e-308;
    guard len == 17 || subnormal else { return len, point; }
    var try: u8[17] = [0; 17];
    for k in (if subnormal { 1 } else { len - 1 })..len {
        // The decimal of k digits below the digits held, and the one above.
        copy_into(try[..k], out[..k]);
        let up = out[k] >= '5';
        for side in 2 {
            var n = k;
            var p = point;
            if (side == 0) == up {
                // one more in the last place, carried
                var j = k;
                while j > 0 && try[j - 1] == '9' { j--; }
                if j == 0 {
                    try[0] = '1';
                    n = 1;
                    p++;
                } else {
                    try[j - 1]++;
                    n = j;
                }
            }
            if reads_back(try[..n], p, x) {
                copy_into(out[..n], try[..n]);
                return n, p;
            }
            copy_into(try[..k], out[..k]);
        }
    }
    return len, point;
}

// Whether 0.d1 d2 ... dn * 10^point reads back as x.
fn reads_back(digits: u8[:], point: i64, x: f64) -> bool {
    var text: u8[..40] = [];
    text.append(digits);
    text.push('e');
    format(text, point - digits.len);
    return scan_number_general(text, 0).value == x;
}

// --- scanning -------------------------------------------------------------------

// JSON's white space, all of it at or below ' ', so that the first compare
// settles nearly every byte.
fn is_space(c: u8) -> bool { c <= ' ' && (c == ' ' || c == '\n' || c == '\r' || c == '\t') }

// The first position at or after pos that is not white space.
fn skip_space(text: u8[:], pos: i64) -> i64 {
    var p = pos;
    while p < text.len && is_space(text[p]) { p++; }
    return p;
}

// The string whose opening quote is at text[at - 1], from its first byte:
// the position of its closing quote, and whether it holds an escape. -1 if
// it is unterminated or holds a raw control character. Escapes are passed
// over unchecked: decode_string or valid_escapes checks them.
fn scan_string(text: u8[:], at: i64) -> i64, bool {
    guard at >= 0 else { return -1, false; }
    var pos = at;
    var escaped = false;
    while pos < text.len {
        let c = text[pos];
        if c == '"' { return pos, escaped; }
        if c == '\\' { escaped = true; pos += 2; continue; }
        if c < 0x20 { return -1, false; }
        pos++;
    }
    return -1, false;
}

// Whether every escape in text[from..to], the body of a string, is one of
// \" \\ \/ \b \f \n \r \t \uXXXX.
fn valid_escapes(text: u8[:], from: i64, to: i64) -> bool {
    var pos = from;
    while pos < to {
        if text[pos] != '\\' { pos++; continue; }
        guard pos + 1 < to else { return false; }
        let e = text[pos + 1];
        if e == 'u' {
            guard pos + 6 <= to else { return false; }
            for i in 4 {
                if hex_digit(text[pos + 2 + i]) < 0 { return false; }
            }
            pos += 6;
        } else if e == '"' || e == '\\' || e == '/' || e == 'b' || e == 'f' || e == 'n' || e == 'r' || e == 't' {
            pos += 2;
        } else {
            return false;
        }
    }
    return true;
}

fn hex_digit(c: u8) -> i64 {
    if c >= '0' && c <= '9' { return c - '0'; }
    if c >= 'a' && c <= 'f' { return c - 'a' + 10; }
    if c >= 'A' && c <= 'F' { return c - 'A' + 10; }
    return -1;
}

// The escaped string text[at..end] decoded onto the end of out, and false
// if an escape is malformed.
fn decode_string(text: u8[:], at: i64, end: i64, out: u8[>..]&) -> const u8[:], bool {
    let first = out.len;
    var pos = at;
    while pos < end {
        let c = text[pos];
        pos++;
        if c != '\\' { out.push(c); continue; }
        let e = text[pos];
        pos++;
        if e == '"' || e == '\\' || e == '/' { out.push(e); }
        else if e == 'n' { out.push('\n'); }
        else if e == 't' { out.push('\t'); }
        else if e == 'r' { out.push('\r'); }
        else if e == 'b' { out.push(8); }
        else if e == 'f' { out.push(12); }
        else if e == 'u' {
            guard pos + 4 <= end else { return out[first..], false; }
            var cp = 0;
            for i in 4 {
                let d = hex_digit(text[pos + i]);
                guard d >= 0 else { return out[first..], false; }
                cp = cp * 16 + d;
            }
            pos += 4;
            // A surrogate pair is two escapes that make one code point; a
            // lone half is kept as the three bytes of its own code.
            if cp >= 0xD800 && cp < 0xDC00 && pos + 6 <= end && text[pos] == '\\' && text[pos + 1] == 'u' {
                var lo = 0;
                for i in 4 {
                    let d = hex_digit(text[pos + 2 + i]);
                    guard d >= 0 else { return out[first..], false; }
                    lo = lo * 16 + d;
                }
                if lo >= 0xDC00 && lo < 0xE000 {
                    cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                    pos += 6;
                }
            }
            push_utf8(out, cp);
        }
        else { return out[first..], false; }
    }
    return out[first..], true;
}

// A JSON number, -?(0|[1-9][0-9]*)(.[0-9]+)?([eE][+-]?[0-9]+)?, and where
// it ends; `is_int` when it has neither a fraction nor an exponent and fits
// an i64.
struct Number { value: f64, int: i64, is_int: bool, end: i64 }

// The number starting at text[at], or one with end == at when there is none.
// A number of at most 19 digits, as nearly every number is, is read here.
// Where its digits make an integer of at most 2^53 and its exponent is at
// most 22 either way, that integer and the power of ten that scales it are
// both exact, so the one multiply or divide is correctly rounded. Where they
// make more, as 17 significant digits do, a plain decimal whose whole part w
// and fraction's digits f make at most 2^53 each is w + f / 10^k: f / 10^k
// is rounded once, and adding w rounds again, which gives the correctly
// rounded sum unless the sum lies within an ulp of f / 10^k of a point
// halfway between two doubles. Rounding is monotonic, so if the sums with
// f / 10^k nudged an ulp down and up round alike, that is the answer. Any
// other number goes to eisel_lemire, and what neither settles is read by
// scan_number_general.
fn scan_number(text: u8[:], at: i64) -> Number {
    guard at >= 0 else { return Number { value: 0.0, int: 0, is_int: false, end: at }; }
    var pos = at;
    var neg = false;
    if pos < text.len && text[pos] == '-' { neg = true; pos++; }
    let int_start = pos;
    var mant: u64 = 0;
    while pos < text.len && text[pos] >= '0' && text[pos] <= '9' {
        mant = mant * 10 + (text[pos] - '0');
        pos++;
    }
    let int_end = pos;
    let whole = mant;
    var frac_digits = 0;
    if pos < text.len && text[pos] == '.' {
        pos++;
        let frac_start = pos;
        while pos < text.len && text[pos] >= '0' && text[pos] <= '9' {
            mant = mant * 10 + (text[pos] - '0');
            pos++;
        }
        frac_digits = pos - frac_start;
        guard frac_digits > 0 else { return scan_number_general(text, at); }
    }
    let int_digits = int_end - int_start;
    guard int_digits > 0 && (int_digits == 1 || text[int_start] != '0')
          && int_digits + frac_digits <= 19 else {
        return scan_number_general(text, at);
    }
    var exp10 = -frac_digits;
    var end = pos;
    if pos < text.len && (text[pos] == 'e' || text[pos] == 'E') {
        let e, exp_end = scan_exponent(text, pos + 1);
        guard exp_end > pos + 1 else { return scan_number_general(text, at); }
        exp10 += e;
        end = exp_end;
    }
    let frac = mant - whole * POW10_U64[frac_digits];
    var v: f64 = mant;
    if mant <= MAX_EXACT && exp10 >= -22 && exp10 <= 22 {
        if exp10 > 0 { v *= POW10[exp10]; } else if exp10 < 0 { v /= POW10[-exp10]; }
    } else if end == pos && frac_digits > 0 && whole <= MAX_EXACT && frac <= MAX_EXACT {
        let w: f64 = whole;
        let f: f64 = frac;
        let q = f / POW10[frac_digits];
        v = w + q * 0.9999999999999998;
        guard v == w + q * 1.0000000000000002 else { return scan_number_general(text, at); }
    } else {
        let w, ok = eisel_lemire(mant, exp10);
        guard ok else { return scan_number_general(text, at); }
        v = w;
    }
    if neg { v = -v; }
    let is_int = frac_digits == 0 && end == pos && (mant <= MAX_I64 || (neg && mant == MAX_I64 + 1));
    let i = if neg { (0 - mant) as! i64 } else { mant as! i64 };
    return Number { value: v, int: i, is_int: is_int, end: end };
}

// 2^53: the integers up to it are exact in binary64.
let MAX_EXACT: u64 = 9007199254740992;

// Any number, correctly rounded. Its first 19 significant digits accumulate
// in a u64, and where that integer and the power of ten that scales it are
// both exact, one multiply or divide is correctly rounded. Otherwise the
// value they give in steps is within a few ulps, and round_near, for a
// number all of whose digits are in the u64 and a power of ten up to 10^27
// either way, eisel_lemire for one of those beyond that, or round_exact
// settles it.
fn scan_number_general(text: u8[:], at: i64) -> Number {
    let none = Number { value: 0.0, int: 0, is_int: false, end: at };
    guard at >= 0 else { return none; }
    var pos = at;
    var neg = false;
    if pos < text.len && text[pos] == '-' { neg = true; pos++; }
    let int_start = pos;
    while pos < text.len && text[pos] >= '0' && text[pos] <= '9' { pos++; }
    let int_digits = pos - int_start;
    guard int_digits > 0 && (int_digits == 1 || text[int_start] != '0') else { return none; }
    var frac_digits = 0;
    if pos < text.len && text[pos] == '.' {
        pos++;
        let frac_start = pos;
        while pos < text.len && text[pos] >= '0' && text[pos] <= '9' { pos++; }
        frac_digits = pos - frac_start;
        guard frac_digits > 0 else { return none; }
    }
    var end = pos;
    var exp10 = -frac_digits;
    if pos < text.len && (text[pos] == 'e' || text[pos] == 'E') {
        let e, exp_end = scan_exponent(text, pos + 1);
        guard exp_end > pos + 1 else { return none; }
        exp10 += e;
        end = exp_end;
    }
    // The first 19 significant digits, and how many follow them.
    var mant: u64 = 0;
    var taken = 0;
    var dropped = 0;
    for c in text[int_start..pos] {
        if c == '.' || (taken == 0 && c == '0') { continue; }
        if taken < 19 { mant = mant * 10 + (c - '0'); taken++; } else { dropped++; }
    }
    // A value other than zero is below 10^(digits + exp10) and at least a
    // tenth of that.
    let digits = taken + dropped;
    var v: f64 = mant;
    if digits == 0 || digits + exp10 < -324 {
        v = 0.0;
    } else if digits + exp10 > 310 {
        v = 1.0 / 0.0;
    } else if dropped == 0 && mant <= MAX_EXACT && exp10 >= -22 && exp10 <= 22 {
        v = scale(v, exp10);
    } else if dropped == 0 && exp10 >= -27 && exp10 <= 27 {
        v = round_near(mant, exp10, scale(v, exp10));
    } else {
        var settled = false;
        if dropped == 0 {
            let w, ok = eisel_lemire(mant, exp10);
            if ok {
                v = w;
                settled = true;
            }
        }
        if !settled { v = round_exact(text, int_start, pos, exp10, scale(v, exp10 + dropped)); }
    }
    if neg { v = -v; }
    // An integer when every digit was taken and it fits: at most 2^63 - 1,
    // or 2^63 below zero, whose negation wraps to itself.
    let is_int = frac_digits == 0 && end == pos && dropped == 0
                 && (mant <= MAX_I64 || (neg && mant == MAX_I64 + 1));
    let i = if neg { (0 - mant) as! i64 } else { mant as! i64 };
    return Number { value: v, int: i, is_int: is_int, end: end };
}

let MAX_I64: u64 = 9223372036854775807;

// The exponent that follows the 'e' at text[at - 1], and where it ends;
// end == at when it has no digits.
fn scan_exponent(text: u8[:], at: i64) -> i64, i64 {
    var pos = at;
    var neg = false;
    if pos < text.len && (text[pos] == '-' || text[pos] == '+') {
        neg = text[pos] == '-';
        pos++;
    }
    let start = pos;
    var e = 0;
    while pos < text.len && text[pos] >= '0' && text[pos] <= '9' {
        if e < 100000 { e = e * 10 + (text[pos] - '0'); }
        pos++;
    }
    if pos == start { return 0, at; }
    if neg { e = -e; }
    return e, pos;
}

// v * 10^e, in steps of an exact power of ten.
fn scale(v: f64, e: i64) -> f64 {
    var x = v;
    var k = e;
    while k > 22 { x *= 1e22; k -= 22; }
    while k < -22 { x /= 1e22; k += 22; }
    if k > 0 { x *= POW10[k]; } else if k < 0 { x /= POW10[-k]; }
    return x;
}

// --- fast rounding --------------------------------------------------------------

// The double nearest to mant * 10^exp10, by the Eisel-Lemire algorithm
// (Lemire, "Number Parsing at a Gigabyte per Second", 2021), as Go's strconv
// has it: mant, shifted to fill 64 bits, times the leading 64 bits of 10^exp10
// gives the double's 54 leading bits, unless the product's low bits are so
// near a carry that the 64 bits of 10^exp10 after those could change them;
// then those take part too. False, rarely, where even that leaves the
// rounding open, or the result would be subnormal or infinite: the exact
// path decides those.
fn eisel_lemire(mant: u64, exp10: i64) -> f64, bool {
    if mant == 0 { return 0.0, true; }
    guard exp10 >= POW10_128_MIN && exp10 < POW10_128_MIN + POW10_128.len / 2 else { return 0.0, false; }
    let lz = clz(mant);
    let m = mant << lz;
    // 217706 / 2^16 is log2(10) closely enough for every exp10 here.
    var exp2 = ((217706 * exp10) >> 16) + 64 + 1023 - lz;
    let row = 2 * (exp10 - POW10_128_MIN);
    var hi, lo = mul_wide(m, POW10_128[row]);
    if hi & 0x1FF == 0x1FF && lo + m < m {
        let yhi, ylo = mul_wide(m, POW10_128[row + 1]);
        var mhi = hi;
        let mlo = lo + yhi;
        if mlo < lo { mhi++; }
        if mhi & 0x1FF == 0x1FF && mlo + 1 == 0 && ylo + m < m { return 0.0, false; }
        hi = mhi;
        lo = mlo;
    }
    // 54 bits, the top one of hi or the one below it first, then rounded to
    // 53, half to even. A product exactly halfway is not settled here.
    let top = hi >> 63;
    var r = hi >> (top + 9);
    if top == 0 { exp2--; }
    if lo == 0 && hi & 0x1FF == 0 && r & 3 == 1 { return 0.0, false; }
    r += r & 1;
    r >>= 1;
    if r >> 53 > 0 {
        r >>= 1;
        exp2++;
    }
    guard exp2 >= 1 && exp2 < 0x7FF else { return 0.0, false; }
    return ldexp(r, (exp2 - 1075) as! i32), true;
}

// --- exact rounding -------------------------------------------------------------

// The C library's split of a double into a fraction in [0.5, 1) and a power
// of two, and its inverse.
extern fn frexp(x: f64, e: i32&) -> f64;
extern fn ldexp(x: f64, e: i32) -> f64;

// The double nearest to D * 10^e10, D the decimal digits text[from..to]
// (a point among them is passed over), given an estimate v within a few
// ulps of it. With v = m * 2^k, v steps an ulp at a time until the exact
// value lies within the halfway points to its neighbours, ties going to the
// even m. Each comparison is exact, in big integers.
fn round_exact(text: u8[:], from: i64, to: i64, e10: i64, v: f64) -> f64 {
    var digits: u32[>..] = [];
    for c in text[from..to] {
        if c != '.' { big_mul_add(digits, 10, c - '0'); }
    }
    // m below 2^53, k from -1074, the subnormals' exponent, to 971, the
    // largest finite double's.
    var m: u64 = 0;
    var k = -1074;
    if v - v != 0.0 {
        m = MAX_EXACT - 1;
        k = 971;
    } else if v > 0.0 {
        var e: i32 = 0;
        let f = frexp(v, e);
        m = (f * 9007199254740992.0) as! u64;
        k = e - 53;
        if k < -1074 {
            m >>= -1074 - k;
            k = -1074;
        }
    }
    loop {
        let up = compare_exact(digits, e10, 2 * m + 1, k - 1);
        if up > 0 || (up == 0 && m % 2 == 1) {
            m++;
            if m == MAX_EXACT { m = MAX_EXACT / 2; k++; }
            if k > 971 { return 1.0 / 0.0; }
            continue;
        }
        if m == 0 { break; }
        // Below a power of two the neighbour is half as far.
        let down = if m == MAX_EXACT / 2 && k > -1074 { compare_exact(digits, e10, 4 * m - 1, k - 2) }
                   else { compare_exact(digits, e10, 2 * m - 1, k - 1) };
        if down < 0 || (down == 0 && m % 2 == 1) {
            m--;
            if m < MAX_EXACT / 2 && k > -1074 { m = 2 * m + 1; k--; }
            continue;
        }
        break;
    }
    return ldexp(m, k as! i32);
}

// round_exact for w * 10^e10, |e10| <= 27, where the numbers it compares
// fit 128 bits: 5^27 is below 2^63.
fn round_near(w: u64, e10: i64, v: f64) -> f64 {
    let b = bits_of(v);
    let m0 = (b & 0xFFFFFFFFFFFFF) | 0x10000000000000;
    let be = ((b >> 52) & 0x7FF) as! i64;
    let k0 = be - 1075;
    var m = m0;
    var k = k0;
    loop {
        let up = compare_near(w, e10, 2 * m + 1, k - 1);
        if up > 0 || (up == 0 && m % 2 == 1) {
            m++;
            if m == MAX_EXACT { m = MAX_EXACT / 2; k++; }
            continue;
        }
        let down = if m == MAX_EXACT / 2 { compare_near(w, e10, 4 * m - 1, k - 2) }
                   else { compare_near(w, e10, 2 * m - 1, k - 1) };
        if down < 0 || (down == 0 && m % 2 == 1) {
            m--;
            if m < MAX_EXACT / 2 { m = 2 * m + 1; k--; }
            continue;
        }
        break;
    }
    return if m == m0 && k == k0 { v } else { ldexp(m, k as! i32) };
}

// w * 10^e10 against h * 2^p, as compare_exact. That is w * 5^e10 against
// h * 2^(p - e10), the power of five on whichever side keeps it whole; the
// two are within a few ulps of each other, so the one shifted left to line
// them up stays within 128 bits.
fn compare_near(w: u64, e10: i64, h: u64, p: i64) -> i64 {
    var ah: u64 = 0;
    var al = w;
    var bh: u64 = 0;
    var bl = h;
    if e10 >= 0 { ah, al = mul_wide(w, POW5[e10]); } else { bh, bl = mul_wide(h, POW5[-e10]); }
    let d = e10 - p;
    if d > 0 { ah, al = shl_wide(ah, al, d); } else if d < 0 { bh, bl = shl_wide(bh, bl, -d); }
    if ah != bh { return if ah < bh { -1 } else { 1 }; }
    if al != bl { return if al < bl { -1 } else { 1 }; }
    return 0;
}

// The 128-bit h * 2^64 + l shifted left by s, 0 < s < 128.
fn shl_wide(h: u64, l: u64, s: i64) -> u64, u64 {
    if s >= 64 { return l << (s - 64), 0; }
    return (h << s) | (l >> (64 - s)), l << s;
}

// D * 10^e10 against h * 2^p: -1, 0 or 1 as it is below, equal to or above.
fn compare_exact(digits: u32[:], e10: i64, h: u64, p: i64) -> i64 {
    var a: u32[>..] = [];
    a.append(digits);
    var b: u32[>..] = [];
    b.push(h as! u32);
    if h >> 32 > 0 { b.push((h >> 32) as! u32); }
    if e10 >= 0 { big_mul_pow5(a, e10); } else { big_mul_pow5(b, -e10); }
    if e10 >= p { big_shl(a, e10 - p); } else { big_shl(b, p - e10); }
    return big_cmp(a, b);
}

// Big integers are their base-2^32 limbs, least significant first, with no
// zero limbs on top: zero has none.

// x = x * m + a.
fn big_mul_add(x: u32[>..]&, m: u32, a: u32) {
    var carry: u64 = a;
    for &limb in x {
        let t = limb as u64 * m + carry;
        limb = t as! u32;
        carry = t >> 32;
    }
    if carry > 0 { x.push(carry as! u32); }
}

// x = x * 5^e.
fn big_mul_pow5(x: u32[>..]&, e: i64) {
    var k = e;
    while k >= 13 { big_mul_add(x, 1220703125, 0); k -= 13; }
    var m: u32 = 1;
    for i in k { m *= 5; }
    big_mul_add(x, m, 0);
}

// x = x * 2^e.
fn big_shl(x: u32[>..]&, e: i64) {
    var k = e;
    while k >= 31 { big_mul_add(x, 0x80000000, 0); k -= 31; }
    big_mul_add(x, (1 as u32) << k, 0);
}

fn big_cmp(a: u32[:], b: u32[:]) -> i64 {
    if a.len != b.len { return if a.len < b.len { -1 } else { 1 }; }
    var i = a.len;
    while i > 0 {
        i--;
        if a[i] != b[i] { return if a[i] < b[i] { -1 } else { 1 }; }
    }
    return 0;
}

// --- the document tree ----------------------------------------------------------

// A document is one grow-only pool of fixed-size nodes in text order. A
// node is a link to its next sibling, a link to its first child (null but
// in a container), its key (empty in an array) and its value. Keys and
// strings are views of the text they were parsed from, or of the caller's
// buffer for those that held escapes, so nodes are all one size and nothing
// is copied into them. Links are 4-byte self-relative offsets.
struct Node { next: Node&<u32>?, first: Node&<u32>?, key: const u8[:], val: Value }

enum Value {
    Null,
    Bool { v: bool },
    Int { v: i64 },
    Num { v: f64 },
    Str { s: const u8[:] },
    Arr { count: i64 },
    Obj { count: i64 },
}

// A container the parser is inside of: its node, its last child so far and
// how many it has, and whether it is an object.
struct Open { node: Node?, last: Node?, count: i64, is_obj: bool }

// parse's result for text that stops being JSON at byte pos.
fn parse_error(what: const u8[:], pos: i64) -> Node?, u8[>..] { return null, str("json: ", what, " at byte ", pos); }

// Parses text into doc and returns the root, or null and a message naming
// the byte where the text stops being JSON. Strings with escapes are
// decoded onto `decoded`. The parse is one loop over the values in text
// order, with the innermost container in locals and the ones around it on
// a stack. Each node is linked from its previous sibling, or its parent,
// as it is pushed.
fn parse(text: u8[:], doc: Node[>..]&, decoded: u8[>..]&) -> Node?, u8[>..] {
    var pos = 0;
    var root: Node? = null;
    var parent: Node? = null;       // the innermost container,
    var last: Node? = null;         // its last child so far,
    var count = 0;                  // how many it has,
    var is_obj = false;             // and whether it is an object
    var outer: Open[>..<] = [];     // the containers around it, innermost last
    var member = false;             // whether the value at the cursor has a key

    // The string whose opening quote is at pos: a slice of the text, or of
    // `decoded` when it holds escapes.
    fn string() -> const u8[:] {
        let start = pos + 1;
        let end, escaped = scan_string(text, start);
        if end >= 0 {
            pos = end + 1;
            if !escaped { return text[start..end]; }
            let s, ok = decode_string(text, start, end, decoded);
            if ok { return s; }
        }
        return parse_error("bad string", pos) from parse;
    }

    // An object member's key and its colon.
    fn member_key() -> const u8[:] {
        pos = skip_space(text, pos);
        guard pos < text.len && text[pos] == '"' else { return parse_error("expected a key", pos) from parse; }
        let k = string();
        pos = skip_space(text, pos);
        guard pos < text.len && text[pos] == ':' else { return parse_error("expected ':'", pos) from parse; }
        pos++;
        return k;
    }

    fn word(w: u8[:]) {
        guard pos + w.len <= text.len && text[pos..pos + w.len] == w else { return parse_error("expected a value", pos) from parse; }
        pos += w.len;
    }

    // The value at pos, c its first byte; a container's count is filled in
    // when it closes.
    fn value(c: u8) -> Value {
        if c == '{' { return Value.Obj { count: 0 }; }
        if c == '[' { return Value.Arr { count: 0 }; }
        if c == '"' { return Value.Str { s: string() }; }
        if c == 't' { word("true"); return Value.Bool { v: true }; }
        if c == 'f' { word("false"); return Value.Bool { v: false }; }
        if c == 'n' { word("null"); return Value.Null; }
        let n = scan_number(text, pos);
        guard n.end > pos else {
            let what = if c == '-' || (c >= '0' && c <= '9') { "bad number" } else { "expected a value" };
            return parse_error(what, pos) from parse;
        }
        pos = n.end;
        if n.is_int { return Value.Int { v: n.int }; }
        return Value.Num { v: n.value };
    }

    loop {
        let key = if member { member_key() } else { "" };
        pos = skip_space(text, pos);
        guard pos < text.len else { return parse_error("unexpected end of input", pos); }
        let c = text[pos];
        let val = value(c);
        let node .= doc.push(Node { next: null, first: null, key: key, val: val });
        if last { last.next .= node; } else if parent { parent.first .= node; } else { root .= node; }
        last .= node;
        count++;
        if c == '{' || c == '[' {
            outer.push(Open { node: parent, last: last, count: count, is_obj: is_obj });
            parent .= node;
            last .= null;
            count = 0;
            is_obj = c == '{';
            pos = skip_space(text, pos + 1);
            if pos >= text.len || text[pos] != (if is_obj { '}' } else { ']' }) {
                member = is_obj;
                continue;
            }
        } else {
            pos = skip_space(text, pos);
        }
        // Past a value: each close bracket completes the innermost container,
        // and a comma starts the next value.
        var more = false;
        while outer.len > 0 && pos < text.len {
            let d = text[pos];
            if d == ',' { pos++; more = true; break; }
            guard d == (if is_obj { '}' } else { ']' }) else {
                return parse_error(if is_obj { "expected ',' or '}'" } else { "expected ',' or ']'" }, pos);
            }
            pos++;
            if parent { parent.val = if is_obj { Value.Obj { count: count } } else { Value.Arr { count: count } }; }
            let o = outer[outer.len - 1];
            outer.pop();
            parent .= o.node;
            last .= o.last;
            count = o.count;
            is_obj = o.is_obj;
            pos = skip_space(text, pos);
        }
        if more { member = is_obj; continue; }
        guard outer.len == 0 else { return parse_error(if is_obj { "unclosed object" } else { "unclosed array" }, pos); }
        guard pos == text.len else { return parse_error("trailing input", pos); }
        return root, str("");
    }
}

// The first member of object n named key; null if there is none, or if n
// is no object or null itself, so that lookups chain.
fn member(n: Node?, key: u8[:]) -> Node? {
    guard n else { return null; }
    match n.val {
        Obj => {},
        _ => { return null; },
    }
    var c = n.first;
    while c {
        if c.key == key { return c; }
        c .= c.next;
    }
    return null;
}

// F(child) for each element of an array or member of an object, in order.
fn each<F>(n: Node&) {
    var c = n.first;
    while c {
        F(c);
        c .= c.next;
    }
}

// A number's value as an f64; false for anything else.
fn as_f64(n: Node?) -> f64, bool {
    guard n else { return 0.0, false; }
    match n.val {
        Num x => { return x.v, true; },
        Int i => { return i.v, true; },
        _ => { return 0.0, false; },
    }
}

// An integer's value; false for anything else, a number with a fraction or
// an exponent included.
fn as_i64(n: Node?) -> i64, bool {
    guard n else { return 0, false; }
    match n.val {
        Int i => { return i.v, true; },
        _ => { return 0, false; },
    }
}

fn as_bool(n: Node?) -> bool, bool {
    guard n else { return false, false; }
    match n.val {
        Bool b => { return b.v, true; },
        _ => { return false, false; },
    }
}

// A string's text, a view of the parsed text or of `decoded`; false for
// anything else.
fn as_string(n: Node?) -> const u8[:], bool {
    guard n else { return "", false; }
    match n.val {
        Str t => { return t.s, true; },
        _ => { return "", false; },
    }
}

// --- reading into the caller's types --------------------------------------------

// A cursor over JSON text for parsers that map it straight onto their own
// types: `each_member` and `each_element` walk a container and hand each
// member or element to a block, which reads it with `read_number`,
// `read_string` and the rest, or passes it over with `skip`. A read that
// meets malformed text records what it expected and where, and moves the
// cursor to the end of the text, so that every read after it fails too and
// every loop ends: the parser checks once, with `finish`, when it is done.
struct Reader { text: const u8[:], pos: i64 = 0, error: const u8[:] = "", error_at: i64 = 0 }

fn reader(text: const u8[:]) -> Reader { Reader { text: text, .. } }

fn fail(r: Reader&, what: const u8[:]) {
    if r.error.len == 0 {
        r.error = what;
        r.error_at = r.pos;
    }
    r.pos = r.text.len;
}

// Whether the text was read without an error and holds nothing but white
// space after what was read; records "trailing input" if it holds more.
fn finish(r: Reader&) -> bool {
    if r.error.len > 0 { return false; }
    peek(r);
    if r.pos < r.text.len { fail(r, "trailing input"); return false; }
    return true;
}

// The error as a message: "json: <what> at byte <n>".
fn message(r: Reader&) -> u8[>..] { str("json: ", r.error, " at byte ", r.error_at) }

// The next byte that is not white space, not consumed; 0 at the end.
fn peek(r: Reader&) -> u8 {
    r.pos = skip_space(r.text, r.pos);
    return if r.pos < r.text.len { r.text[r.pos] } else { 0 };
}

fn read_number(r: Reader&) -> f64 {
    let at = skip_space(r.text, r.pos);
    let n = scan_number(r.text, at);
    r.pos = at;
    if n.end == at { fail(r, "expected a number"); return 0.0; }
    r.pos = n.end;
    return n.value;
}

// A number with neither a fraction nor an exponent that fits an i64.
fn read_int(r: Reader&) -> i64 {
    let at = skip_space(r.text, r.pos);
    let n = scan_number(r.text, at);
    r.pos = at;
    if n.end == at || !n.is_int { fail(r, "expected an integer"); return 0; }
    r.pos = n.end;
    return n.int;
}

fn read_bool(r: Reader&) -> bool {
    let c = peek(r);
    if c == 't' { word(r, "true"); return r.error.len == 0; }
    if c == 'f' { word(r, "false"); return false; }
    fail(r, "expected true or false");
    return false;
}

// A string without escapes as a slice of the text; one with escapes is
// decoded onto `scratch` and returned as a slice of that.
fn read_string(r: Reader&, scratch: u8[>..]&) -> const u8[:] {
    if peek(r) != '"' { fail(r, "expected a string"); return ""; }
    let start = r.pos + 1;
    let end, escaped = scan_string(r.text, start);
    if end < 0 { fail(r, "bad string"); return ""; }
    r.pos = end + 1;
    if !escaped { return r.text[start..end]; }
    let s, ok = decode_string(r.text, start, end, scratch);
    if !ok {
        r.pos = start - 1;
        fail(r, "bad escape");
    }
    return s;
}

// F(key) for each member of the object at the cursor; F reads the value.
// Keys are handed over as written, so one with escapes in it never equals
// a plain one.
fn each_member<F>(r: Reader&) {
    if peek(r) != '{' { fail(r, "expected '{'"); return; }
    r.pos++;
    if peek(r) == '}' { r.pos++; return; }
    loop {
        if peek(r) != '"' { fail(r, "expected a key"); return; }
        let start = r.pos + 1;
        let end, escaped = scan_string(r.text, start);
        if end < 0 || (escaped && !valid_escapes(r.text, start, end)) { fail(r, "bad string"); return; }
        r.pos = end + 1;
        if peek(r) != ':' { fail(r, "expected ':'"); return; }
        r.pos++;
        F(r.text[start..end]);
        let c = peek(r);
        if c == ',' { r.pos++; continue; }
        if c == '}' { r.pos++; } else { fail(r, "expected ',' or '}'"); }
        return;
    }
}

// F() for each element of the array at the cursor; F reads the element.
fn each_element<F>(r: Reader&) {
    if peek(r) != '[' { fail(r, "expected '['"); return; }
    r.pos++;
    if peek(r) == ']' { r.pos++; return; }
    loop {
        F();
        let c = peek(r);
        if c == ',' { r.pos++; continue; }
        if c == ']' { r.pos++; } else { fail(r, "expected ',' or ']'"); }
        return;
    }
}

fn word(r: Reader&, w: u8[:]) {
    if r.pos + w.len <= r.text.len && r.text[r.pos..r.pos + w.len] == w { r.pos += w.len; }
    else { fail(r, "expected a value"); }
}

// Passes over the value at the cursor, checking that it is well formed.
// A string, the value most often passed over, is scanned here; anything
// else goes through skip_value's loop.
fn skip(r: Reader&) {
    if peek(r) != '"' { skip_value(r); return; }
    let end, escaped = scan_string(r.text, r.pos + 1);
    if end < 0 || (escaped && !valid_escapes(r.text, r.pos + 1, end)) { fail(r, "bad string"); return; }
    r.pos = end + 1;
}

// skip for any value: one loop over the values in it, with the containers
// around the cursor on a stack.
fn skip_value(r: Reader&) {
    var open: bool[>..<] = [];      // the containers around the cursor, true for an object
    var member = false;             // whether the value at the cursor has a key
    loop {
        if member {
            if peek(r) != '"' { fail(r, "expected a key"); return; }
            let end, escaped = scan_string(r.text, r.pos + 1);
            if end < 0 || (escaped && !valid_escapes(r.text, r.pos + 1, end)) { fail(r, "bad string"); return; }
            r.pos = end + 1;
            if peek(r) != ':' { fail(r, "expected ':'"); return; }
            r.pos++;
        }
        let c = peek(r);
        if c == '{' || c == '[' {
            r.pos++;
            open.push(c == '{');
            if peek(r) != (if c == '{' { '}' } else { ']' }) {
                member = c == '{';
                continue;
            }
            r.pos++;
            open.pop();
        } else if c == '"' {
            let end, escaped = scan_string(r.text, r.pos + 1);
            if end < 0 || (escaped && !valid_escapes(r.text, r.pos + 1, end)) { fail(r, "bad string"); return; }
            r.pos = end + 1;
        } else if c == 't' {
            word(r, "true");
        } else if c == 'f' {
            word(r, "false");
        } else if c == 'n' {
            word(r, "null");
        } else if c == '-' || (c >= '0' && c <= '9') {
            read_number(r);
        } else {
            fail(r, "expected a value");
            return;
        }
        // Past a value: each close bracket ends the innermost container,
        // and a comma starts the next value.
        member = false;
        loop {
            if open.len == 0 { return; }
            let in_obj = open[open.len - 1];
            let d = peek(r);
            if d == ',' {
                r.pos++;
                member = in_obj;
                break;
            }
            if d != (if in_obj { '}' } else { ']' }) {
                fail(r, if in_obj { "expected ',' or '}'" } else { "expected ',' or ']'" });
                return;
            }
            r.pos++;
            open.pop();
        }
    }
}

// --- powers of ten -------------------------------------------------------------

// 10^q for q from POW10_128_MIN on, each as its leading 128 bits, rounded down:
// two u64s, the high half first, the top bit set. 10^q is that times 2^(e - 127)
// for the e with 2^e <= 10^q < 2^(e + 1). Printed by scripts/json_pow10_table.py
// (Go's strconv and Wuffs hold the same table).
let POW10_128_MIN = -348;

let POW10_128: u64[1392] = [
    0xFA8FD5A0081C0288, 0x1732C869CD60E453, 0x9C99E58405118195, 0x0E7FBD42205C8EB4,   // 1e-348, 1e-347
    0xC3C05EE50655E1FA, 0x521FAC92A873B261, 0xF4B0769E47EB5A78, 0xE6A797B752909EF9,   // 1e-346, 1e-345
    0x98EE4A22ECF3188B, 0x9028BED2939A635C, 0xBF29DCABA82FDEAE, 0x7432EE873880FC33,   // 1e-344, 1e-343
    0xEEF453D6923BD65A, 0x113FAA2906A13B3F, 0x9558B4661B6565F8, 0x4AC7CA59A424C507,   // 1e-342, 1e-341
    0xBAAEE17FA23EBF76, 0x5D79BCF00D2DF649, 0xE95A99DF8ACE6F53, 0xF4D82C2C107973DC,   // 1e-340, 1e-339
    0x91D8A02BB6C10594, 0x79071B9B8A4BE869, 0xB64EC836A47146F9, 0x9748E2826CDEE284,   // 1e-338, 1e-337
    0xE3E27A444D8D98B7, 0xFD1B1B2308169B25, 0x8E6D8C6AB0787F72, 0xFE30F0F5E50E20F7,   // 1e-336, 1e-335
    0xB208EF855C969F4F, 0xBDBD2D335E51A935, 0xDE8B2B66B3BC4723, 0xAD2C788035E61382,   // 1e-334, 1e-333
    0x8B16FB203055AC76, 0x4C3BCB5021AFCC31, 0xADDCB9E83C6B1793, 0xDF4ABE242A1BBF3D,   // 1e-332, 1e-331
    0xD953E8624B85DD78, 0xD71D6DAD34A2AF0D, 0x87D4713D6F33AA6B, 0x8672648C40E5AD68,   // 1e-330, 1e-329
    0xA9C98D8CCB009506, 0x680EFDAF511F18C2, 0xD43BF0EFFDC0BA48, 0x0212BD1B2566DEF2,   // 1e-328, 1e-327
    0x84A57695FE98746D, 0x014BB630F7604B57, 0xA5CED43B7E3E9188, 0x419EA3BD35385E2D,   // 1e-326, 1e-325
    0xCF42894A5DCE35EA, 0x52064CAC828675B9, 0x818995CE7AA0E1B2, 0x7343EFEBD1940993,   // 1e-324, 1e-323
    0xA1EBFB4219491A1F, 0x1014EBE6C5F90BF8, 0xCA66FA129F9B60A6, 0xD41A26E077774EF6,   // 1e-322, 1e-321
    0xFD00B897478238D0, 0x8920B098955522B4, 0x9E20735E8CB16382, 0x55B46E5F5D5535B0,   // 1e-320, 1e-319
    0xC5A890362FDDBC62, 0xEB2189F734AA831D, 0xF712B443BBD52B7B, 0xA5E9EC7501D523E4,   // 1e-318, 1e-317
    0x9A6BB0AA55653B2D, 0x47B233C92125366E, 0xC1069CD4EABE89F8, 0x999EC0BB696E840A,   // 1e-316, 1e-315
    0xF148440A256E2C76, 0xC00670EA43CA250D, 0x96CD2A865764DBCA, 0x380406926A5E5728,   // 1e-314, 1e-313
    0xBC807527ED3E12BC, 0xC605083704F5ECF2, 0xEBA09271E88D976B, 0xF7864A44C633682E,   // 1e-312, 1e-311
    0x93445B8731587EA3, 0x7AB3EE6AFBE0211D, 0xB8157268FDAE9E4C, 0x5960EA05BAD82964,   // 1e-310, 1e-309
    0xE61ACF033D1A45DF, 0x6FB92487298E33BD, 0x8FD0C16206306BAB, 0xA5D3B6D479F8E056,   // 1e-308, 1e-307
    0xB3C4F1BA87BC8696, 0x8F48A4899877186C, 0xE0B62E2929ABA83C, 0x331ACDABFE94DE87,   // 1e-306, 1e-305
    0x8C71DCD9BA0B4925, 0x9FF0C08B7F1D0B14, 0xAF8E5410288E1B6F, 0x07ECF0AE5EE44DD9,   // 1e-304, 1e-303
    0xDB71E91432B1A24A, 0xC9E82CD9F69D6150, 0x892731AC9FAF056E, 0xBE311C083A225CD2,   // 1e-302, 1e-301
    0xAB70FE17C79AC6CA, 0x6DBD630A48AAF406, 0xD64D3D9DB981787D, 0x092CBBCCDAD5B108,   // 1e-300, 1e-299
    0x85F0468293F0EB4E, 0x25BBF56008C58EA5, 0xA76C582338ED2621, 0xAF2AF2B80AF6F24E,   // 1e-298, 1e-297
    0xD1476E2C07286FAA, 0x1AF5AF660DB4AEE1, 0x82CCA4DB847945CA, 0x50D98D9FC890ED4D,   // 1e-296, 1e-295
    0xA37FCE126597973C, 0xE50FF107BAB528A0, 0xCC5FC196FEFD7D0C, 0x1E53ED49A96272C8,   // 1e-294, 1e-293
    0xFF77B1FCBEBCDC4F, 0x25E8E89C13BB0F7A, 0x9FAACF3DF73609B1, 0x77B191618C54E9AC,   // 1e-292, 1e-291
    0xC795830D75038C1D, 0xD59DF5B9EF6A2417, 0xF97AE3D0D2446F25, 0x4B0573286B44AD1D,   // 1e-290, 1e-289
    0x9BECCE62836AC577, 0x4EE367F9430AEC32, 0xC2E801FB244576D5, 0x229C41F793CDA73F,   // 1e-288, 1e-287
    0xF3A20279ED56D48A, 0x6B43527578C1110F, 0x9845418C345644D6, 0x830A13896B78AAA9,   // 1e-286, 1e-285
    0xBE5691EF416BD60C, 0x23CC986BC656D553, 0xEDEC366B11C6CB8F, 0x2CBFBE86B7EC8AA8,   // 1e-284, 1e-283
    0x94B3A202EB1C3F39, 0x7BF7D71432F3D6A9, 0xB9E08A83A5E34F07, 0xDAF5CCD93FB0CC53,   // 1e-282, 1e-281
    0xE858AD248F5C22C9, 0xD1B3400F8F9CFF68, 0x91376C36D99995BE, 0x23100809B9C21FA1,   // 1e-280, 1e-279
    0xB58547448FFFFB2D, 0xABD40A0C2832A78A, 0xE2E69915B3FFF9F9, 0x16C90C8F323F516C,   // 1e-278, 1e-277
    0x8DD01FAD907FFC3B, 0xAE3DA7D97F6792E3, 0xB1442798F49FFB4A, 0x99CD11CFDF41779C,   // 1e-276, 1e-275
    0xDD95317F31C7FA1D, 0x40405643D711D583, 0x8A7D3EEF7F1CFC52, 0x482835EA666B2572,   // 1e-274, 1e-273
    0xAD1C8EAB5EE43B66, 0xDA3243650005EECF, 0xD863B256369D4A40, 0x90BED43E40076A82,   // 1e-272, 1e-271
    0x873E4F75E2224E68, 0x5A7744A6E804A291, 0xA90DE3535AAAE202, 0x711515D0A205CB36,   // 1e-270, 1e-269
    0xD3515C2831559A83, 0x0D5A5B44CA873E03, 0x8412D9991ED58091, 0xE858790AFE9486C2,   // 1e-268, 1e-267
    0xA5178FFF668AE0B6, 0x626E974DBE39A872, 0xCE5D73FF402D98E3, 0xFB0A3D212DC8128F,   // 1e-266, 1e-265
    0x80FA687F881C7F8E, 0x7CE66634BC9D0B99, 0xA139029F6A239F72, 0x1C1FFFC1EBC44E80,   // 1e-264, 1e-263
    0xC987434744AC874E, 0xA327FFB266B56220, 0xFBE9141915D7A922, 0x4BF1FF9F0062BAA8,   // 1e-262, 1e-261
    0x9D71AC8FADA6C9B5, 0x6F773FC3603DB4A9, 0xC4CE17B399107C22, 0xCB550FB4384D21D3,   // 1e-260, 1e-259
    0xF6019DA07F549B2B, 0x7E2A53A146606A48, 0x99C102844F94E0FB, 0x2EDA7444CBFC426D,   // 1e-258, 1e-257
    0xC0314325637A1939, 0xFA911155FEFB5308, 0xF03D93EEBC589F88, 0x793555AB7EBA27CA,   // 1e-256, 1e-255
    0x96267C7535B763B5, 0x4BC1558B2F3458DE, 0xBBB01B9283253CA2, 0x9EB1AAEDFB016F16,   // 1e-254, 1e-253
    0xEA9C227723EE8BCB, 0x465E15A979C1CADC, 0x92A1958A7675175F, 0x0BFACD89EC191EC9,   // 1e-252, 1e-251
    0xB749FAED14125D36, 0xCEF980EC671F667B, 0xE51C79A85916F484, 0x82B7E12780E7401A,   // 1e-250, 1e-249
    0x8F31CC0937AE58D2, 0xD1B2ECB8B0908810, 0xB2FE3F0B8599EF07, 0x861FA7E6DCB4AA15,   // 1e-248, 1e-247
    0xDFBDCECE67006AC9, 0x67A791E093E1D49A, 0x8BD6A141006042BD, 0xE0C8BB2C5C6D24E0,   // 1e-246, 1e-245
    0xAECC49914078536D, 0x58FAE9F773886E18, 0xDA7F5BF590966848, 0xAF39A475506A899E,   // 1e-244, 1e-243
    0x888F99797A5E012D, 0x6D8406C952429603, 0xAAB37FD7D8F58178, 0xC8E5087BA6D33B83,   // 1e-242, 1e-241
    0xD5605FCDCF32E1D6, 0xFB1E4A9A90880A64, 0x855C3BE0A17FCD26, 0x5CF2EEA09A55067F,   // 1e-240, 1e-239
    0xA6B34AD8C9DFC06F, 0xF42FAA48C0EA481E, 0xD0601D8EFC57B08B, 0xF13B94DAF124DA26,   // 1e-238, 1e-237
    0x823C12795DB6CE57, 0x76C53D08D6B70858, 0xA2CB1717B52481ED, 0x54768C4B0C64CA6E,   // 1e-236, 1e-235
    0xCB7DDCDDA26DA268, 0xA9942F5DCF7DFD09, 0xFE5D54150B090B02, 0xD3F93B35435D7C4C,   // 1e-234, 1e-233
    0x9EFA548D26E5A6E1, 0xC47BC5014A1A6DAF, 0xC6B8E9B0709F109A, 0x359AB6419CA1091B,   // 1e-232, 1e-231
    0xF867241C8CC6D4C0, 0xC30163D203C94B62, 0x9B407691D7FC44F8, 0x79E0DE63425DCF1D,   // 1e-230, 1e-229
    0xC21094364DFB5636, 0x985915FC12F542E4, 0xF294B943E17A2BC4, 0x3E6F5B7B17B2939D,   // 1e-228, 1e-227
    0x979CF3CA6CEC5B5A, 0xA705992CEECF9C42, 0xBD8430BD08277231, 0x50C6FF782A838353,   // 1e-226, 1e-225
    0xECE53CEC4A314EBD, 0xA4F8BF5635246428, 0x940F4613AE5ED136, 0x871B7795E136BE99,   // 1e-224, 1e-223
    0xB913179899F68584, 0x28E2557B59846E3F, 0xE757DD7EC07426E5, 0x331AEADA2FE589CF,   // 1e-222, 1e-221
    0x9096EA6F3848984F, 0x3FF0D2C85DEF7621, 0xB4BCA50B065ABE63, 0x0FED077A756B53A9,   // 1e-220, 1e-219
    0xE1EBCE4DC7F16DFB, 0xD3E8495912C62894, 0x8D3360F09CF6E4BD, 0x64712DD7ABBBD95C,   // 1e-218, 1e-217
    0xB080392CC4349DEC, 0xBD8D794D96AACFB3, 0xDCA04777F541C567, 0xECF0D7A0FC5583A0,   // 1e-216, 1e-215
    0x89E42CAAF9491B60, 0xF41686C49DB57244, 0xAC5D37D5B79B6239, 0x311C2875C522CED5,   // 1e-214, 1e-213
    0xD77485CB25823AC7, 0x7D633293366B828B, 0x86A8D39EF77164BC, 0xAE5DFF9C02033197,   // 1e-212, 1e-211
    0xA8530886B54DBDEB, 0xD9F57F830283FDFC, 0xD267CAA862A12D66, 0xD072DF63C324FD7B,   // 1e-210, 1e-209
    0x8380DEA93DA4BC60, 0x4247CB9E59F71E6D, 0xA46116538D0DEB78, 0x52D9BE85F074E608,   // 1e-208, 1e-207
    0xCD795BE870516656, 0x67902E276C921F8B, 0x806BD9714632DFF6, 0x00BA1CD8A3DB53B6,   // 1e-206, 1e-205
    0xA086CFCD97BF97F3, 0x80E8A40ECCD228A4, 0xC8A883C0FDAF7DF0, 0x6122CD128006B2CD,   // 1e-204, 1e-203
    0xFAD2A4B13D1B5D6C, 0x796B805720085F81, 0x9CC3A6EEC6311A63, 0xCBE3303674053BB0,   // 1e-202, 1e-201
    0xC3F490AA77BD60FC, 0xBEDBFC4411068A9C, 0xF4F1B4D515ACB93B, 0xEE92FB5515482D44,   // 1e-200, 1e-199
    0x991711052D8BF3C5, 0x751BDD152D4D1C4A, 0xBF5CD54678EEF0B6, 0xD262D45A78A0635D,   // 1e-198, 1e-197
    0xEF340A98172AACE4, 0x86FB897116C87C34, 0x9580869F0E7AAC0E, 0xD45D35E6AE3D4DA0,   // 1e-196, 1e-195
    0xBAE0A846D2195712, 0x8974836059CCA109, 0xE998D258869FACD7, 0x2BD1A438703FC94B,   // 1e-194, 1e-193
    0x91FF83775423CC06, 0x7B6306A34627DDCF, 0xB67F6455292CBF08, 0x1A3BC84C17B1D542,   // 1e-192, 1e-191
    0xE41F3D6A7377EECA, 0x20CABA5F1D9E4A93, 0x8E938662882AF53E, 0x547EB47B7282EE9C,   // 1e-190, 1e-189
    0xB23867FB2A35B28D, 0xE99E619A4F23AA43, 0xDEC681F9F4C31F31, 0x6405FA00E2EC94D4,   // 1e-188, 1e-187
    0x8B3C113C38F9F37E, 0xDE83BC408DD3DD04, 0xAE0B158B4738705E, 0x9624AB50B148D445,   // 1e-186, 1e-185
    0xD98DDAEE19068C76, 0x3BADD624DD9B0957, 0x87F8A8D4CFA417C9, 0xE54CA5D70A80E5D6,   // 1e-184, 1e-183
    0xA9F6D30A038D1DBC, 0x5E9FCF4CCD211F4C, 0xD47487CC8470652B, 0x7647C3200069671F,   // 1e-182, 1e-181
    0x84C8D4DFD2C63F3B, 0x29ECD9F40041E073, 0xA5FB0A17C777CF09, 0xF468107100525890,   // 1e-180, 1e-179
    0xCF79CC9DB955C2CC, 0x7182148D4066EEB4, 0x81AC1FE293D599BF, 0xC6F14CD848405530,   // 1e-178, 1e-177
    0xA21727DB38CB002F, 0xB8ADA00E5A506A7C, 0xCA9CF1D206FDC03B, 0xA6D90811F0E4851C,   // 1e-176, 1e-175
    0xFD442E4688BD304A, 0x908F4A166D1DA663, 0x9E4A9CEC15763E2E, 0x9A598E4E043287FE,   // 1e-174, 1e-173
    0xC5DD44271AD3CDBA, 0x40EFF1E1853F29FD, 0xF7549530E188C128, 0xD12BEE59E68EF47C,   // 1e-172, 1e-171
    0x9A94DD3E8CF578B9, 0x82BB74F8301958CE, 0xC13A148E3032D6E7, 0xE36A52363C1FAF01,   // 1e-170, 1e-169
    0xF18899B1BC3F8CA1, 0xDC44E6C3CB279AC1, 0x96F5600F15A7B7E5, 0x29AB103A5EF8C0B9,   // 1e-168, 1e-167
    0xBCB2B812DB11A5DE, 0x7415D448F6B6F0E7, 0xEBDF661791D60F56, 0x111B495B3464AD21,   // 1e-166, 1e-165
    0x936B9FCEBB25C995, 0xCAB10DD900BEEC34, 0xB84687C269EF3BFB, 0x3D5D514F40EEA742,   // 1e-164, 1e-163
    0xE65829B3046B0AFA, 0x0CB4A5A3112A5112, 0x8FF71A0FE2C2E6DC, 0x47F0E785EABA72AB,   // 1e-162, 1e-161
    0xB3F4E093DB73A093, 0x59ED216765690F56, 0xE0F218B8D25088B8, 0x306869C13EC3532C,   // 1e-160, 1e-159
    0x8C974F7383725573, 0x1E414218C73A13FB, 0xAFBD2350644EEACF, 0xE5D1929EF90898FA,   // 1e-158, 1e-157
    0xDBAC6C247D62A583, 0xDF45F746B74ABF39, 0x894BC396CE5DA772, 0x6B8BBA8C328EB783,   // 1e-156, 1e-155
    0xAB9EB47C81F5114F, 0x066EA92F3F326564, 0xD686619BA27255A2, 0xC80A537B0EFEFEBD,   // 1e-154, 1e-153
    0x8613FD0145877585, 0xBD06742CE95F5F36, 0xA798FC4196E952E7, 0x2C48113823B73704,   // 1e-152, 1e-151
    0xD17F3B51FCA3A7A0, 0xF75A15862CA504C5, 0x82EF85133DE648C4, 0x9A984D73DBE722FB,   // 1e-150, 1e-149
    0xA3AB66580D5FDAF5, 0xC13E60D0D2E0EBBA, 0xCC963FEE10B7D1B3, 0x318DF905079926A8,   // 1e-148, 1e-147
    0xFFBBCFE994E5C61F, 0xFDF17746497F7052, 0x9FD561F1FD0F9BD3, 0xFEB6EA8BEDEFA633,   // 1e-146, 1e-145
    0xC7CABA6E7C5382C8, 0xFE64A52EE96B8FC0, 0xF9BD690A1B68637B, 0x3DFDCE7AA3C673B0,   // 1e-144, 1e-143
    0x9C1661A651213E2D, 0x06BEA10CA65C084E, 0xC31BFA0FE5698DB8, 0x486E494FCFF30A62,   // 1e-142, 1e-141
    0xF3E2F893DEC3F126, 0x5A89DBA3C3EFCCFA, 0x986DDB5C6B3A76B7, 0xF89629465A75E01C,   // 1e-140, 1e-139
    0xBE89523386091465, 0xF6BBB397F1135823, 0xEE2BA6C0678B597F, 0x746AA07DED582E2C,   // 1e-138, 1e-137
    0x94DB483840B717EF, 0xA8C2A44EB4571CDC, 0xBA121A4650E4DDEB, 0x92F34D62616CE413,   // 1e-136, 1e-135
    0xE896A0D7E51E1566, 0x77B020BAF9C81D17, 0x915E2486EF32CD60, 0x0ACE1474DC1D122E,   // 1e-134, 1e-133
    0xB5B5ADA8AAFF80B8, 0x0D819992132456BA, 0xE3231912D5BF60E6, 0x10E1FFF697ED6C69,   // 1e-132, 1e-131
    0x8DF5EFABC5979C8F, 0xCA8D3FFA1EF463C1, 0xB1736B96B6FD83B3, 0xBD308FF8A6B17CB2,   // 1e-130, 1e-129
    0xDDD0467C64BCE4A0, 0xAC7CB3F6D05DDBDE, 0x8AA22C0DBEF60EE4, 0x6BCDF07A423AA96B,   // 1e-128, 1e-127
    0xAD4AB7112EB3929D, 0x86C16C98D2C953C6, 0xD89D64D57A607744, 0xE871C7BF077BA8B7,   // 1e-126, 1e-125
    0x87625F056C7C4A8B, 0x11471CD764AD4972, 0xA93AF6C6C79B5D2D, 0xD598E40D3DD89BCF,   // 1e-124, 1e-123
    0xD389B47879823479, 0x4AFF1D108D4EC2C3, 0x843610CB4BF160CB, 0xCEDF722A585139BA,   // 1e-122, 1e-121
    0xA54394FE1EEDB8FE, 0xC2974EB4EE658828, 0xCE947A3DA6A9273E, 0x733D226229FEEA32,   // 1e-120, 1e-119
    0x811CCC668829B887, 0x0806357D5A3F525F, 0xA163FF802A3426A8, 0xCA07C2DCB0CF26F7,   // 1e-118, 1e-117
    0xC9BCFF6034C13052, 0xFC89B393DD02F0B5, 0xFC2C3F3841F17C67, 0xBBAC2078D443ACE2,   // 1e-116, 1e-115
    0x9D9BA7832936EDC0, 0xD54B944B84AA4C0D, 0xC5029163F384A931, 0x0A9E795E65D4DF11,   // 1e-114, 1e-113
    0xF64335BCF065D37D, 0x4D4617B5FF4A16D5, 0x99EA0196163FA42E, 0x504BCED1BF8E4E45,   // 1e-112, 1e-111
    0xC06481FB9BCF8D39, 0xE45EC2862F71E1D6, 0xF07DA27A82C37088, 0x5D767327BB4E5A4C,   // 1e-110, 1e-109
    0x964E858C91BA2655, 0x3A6A07F8D510F86F, 0xBBE226EFB628AFEA, 0x890489F70A55368B,   // 1e-108, 1e-107
    0xEADAB0ABA3B2DBE5, 0x2B45AC74CCEA842E, 0x92C8AE6B464FC96F, 0x3B0B8BC90012929D,   // 1e-106, 1e-105
    0xB77ADA0617E3BBCB, 0x09CE6EBB40173744, 0xE55990879DDCAABD, 0xCC420A6A101D0515,   // 1e-104, 1e-103
    0x8F57FA54C2A9EAB6, 0x9FA946824A12232D, 0xB32DF8E9F3546564, 0x47939822DC96ABF9,   // 1e-102, 1e-101
    0xDFF9772470297EBD, 0x59787E2B93BC56F7, 0x8BFBEA76C619EF36, 0x57EB4EDB3C55B65A,   // 1e-100, 1e-99
    0xAEFAE51477A06B03, 0xEDE622920B6B23F1, 0xDAB99E59958885C4, 0xE95FAB368E45ECED,   // 1e-98, 1e-97
    0x88B402F7FD75539B, 0x11DBCB0218EBB414, 0xAAE103B5FCD2A881, 0xD652BDC29F26A119,   // 1e-96, 1e-95
    0xD59944A37C0752A2, 0x4BE76D3346F0495F, 0x857FCAE62D8493A5, 0x6F70A4400C562DDB,   // 1e-94, 1e-93
    0xA6DFBD9FB8E5B88E, 0xCB4CCD500F6BB952, 0xD097AD07A71F26B2, 0x7E2000A41346A7A7,   // 1e-92, 1e-91
    0x825ECC24C873782F, 0x8ED400668C0C28C8, 0xA2F67F2DFA90563B, 0x728900802F0F32FA,   // 1e-90, 1e-89
    0xCBB41EF979346BCA, 0x4F2B40A03AD2FFB9, 0xFEA126B7D78186BC, 0xE2F610C84987BFA8,   // 1e-88, 1e-87
    0x9F24B832E6B0F436, 0x0DD9CA7D2DF4D7C9, 0xC6EDE63FA05D3143, 0x91503D1C79720DBB,   // 1e-86, 1e-85
    0xF8A95FCF88747D94, 0x75A44C6397CE912A, 0x9B69DBE1B548CE7C, 0xC986AFBE3EE11ABA,   // 1e-84, 1e-83
    0xC24452DA229B021B, 0xFBE85BADCE996168, 0xF2D56790AB41C2A2, 0xFAE27299423FB9C3,   // 1e-82, 1e-81
    0x97C560BA6B0919A5, 0xDCCD879FC967D41A, 0xBDB6B8E905CB600F, 0x5400E987BBC1C920,   // 1e-80, 1e-79
    0xED246723473E3813, 0x290123E9AAB23B68, 0x9436C0760C86E30B, 0xF9A0B6720AAF6521,   // 1e-78, 1e-77
    0xB94470938FA89BCE, 0xF808E40E8D5B3E69, 0xE7958CB87392C2C2, 0xB60B1D1230B20E04,   // 1e-76, 1e-75
    0x90BD77F3483BB9B9, 0xB1C6F22B5E6F48C2, 0xB4ECD5F01A4AA828, 0x1E38AEB6360B1AF3,   // 1e-74, 1e-73
    0xE2280B6C20DD5232, 0x25C6DA63C38DE1B0, 0x8D590723948A535F, 0x579C487E5A38AD0E,   // 1e-72, 1e-71
    0xB0AF48EC79ACE837, 0x2D835A9DF0C6D851, 0xDCDB1B2798182244, 0xF8E431456CF88E65,   // 1e-70, 1e-69
    0x8A08F0F8BF0F156B, 0x1B8E9ECB641B58FF, 0xAC8B2D36EED2DAC5, 0xE272467E3D222F3F,   // 1e-68, 1e-67
    0xD7ADF884AA879177, 0x5B0ED81DCC6ABB0F, 0x86CCBB52EA94BAEA, 0x98E947129FC2B4E9,   // 1e-66, 1e-65
    0xA87FEA27A539E9A5, 0x3F2398D747B36224, 0xD29FE4B18E88640E, 0x8EEC7F0D19A03AAD,   // 1e-64, 1e-63
    0x83A3EEEEF9153E89, 0x1953CF68300424AC, 0xA48CEAAAB75A8E2B, 0x5FA8C3423C052DD7,   // 1e-62, 1e-61
    0xCDB02555653131B6, 0x3792F412CB06794D, 0x808E17555F3EBF11, 0xE2BBD88BBEE40BD0,   // 1e-60, 1e-59
    0xA0B19D2AB70E6ED6, 0x5B6ACEAEAE9D0EC4, 0xC8DE047564D20A8B, 0xF245825A5A445275,   // 1e-58, 1e-57
    0xFB158592BE068D2E, 0xEED6E2F0F0D56712, 0x9CED737BB6C4183D, 0x55464DD69685606B,   // 1e-56, 1e-55
    0xC428D05AA4751E4C, 0xAA97E14C3C26B886, 0xF53304714D9265DF, 0xD53DD99F4B3066A8,   // 1e-54, 1e-53
    0x993FE2C6D07B7FAB, 0xE546A8038EFE4029, 0xBF8FDB78849A5F96, 0xDE98520472BDD033,   // 1e-52, 1e-51
    0xEF73D256A5C0F77C, 0x963E66858F6D4440, 0x95A8637627989AAD, 0xDDE7001379A44AA8,   // 1e-50, 1e-49
    0xBB127C53B17EC159, 0x5560C018580D5D52, 0xE9D71B689DDE71AF, 0xAAB8F01E6E10B4A6,   // 1e-48, 1e-47
    0x9226712162AB070D, 0xCAB3961304CA70E8, 0xB6B00D69BB55C8D1, 0x3D607B97C5FD0D22,   // 1e-46, 1e-45
    0xE45C10C42A2B3B05, 0x8CB89A7DB77C506A, 0x8EB98A7A9A5B04E3, 0x77F3608E92ADB242,   // 1e-44, 1e-43
    0xB267ED1940F1C61C, 0x55F038B237591ED3, 0xDF01E85F912E37A3, 0x6B6C46DEC52F6688,   // 1e-42, 1e-41
    0x8B61313BBABCE2C6, 0x2323AC4B3B3DA015, 0xAE397D8AA96C1B77, 0xABEC975E0A0D081A,   // 1e-40, 1e-39
    0xD9C7DCED53C72255, 0x96E7BD358C904A21, 0x881CEA14545C7575, 0x7E50D64177DA2E54,   // 1e-38, 1e-37
    0xAA242499697392D2, 0xDDE50BD1D5D0B9E9, 0xD4AD2DBFC3D07787, 0x955E4EC64B44E864,   // 1e-36, 1e-35
    0x84EC3C97DA624AB4, 0xBD5AF13BEF0B113E, 0xA6274BBDD0FADD61, 0xECB1AD8AEACDD58E,   // 1e-34, 1e-33
    0xCFB11EAD453994BA, 0x67DE18EDA5814AF2, 0x81CEB32C4B43FCF4, 0x80EACF948770CED7,   // 1e-32, 1e-31
    0xA2425FF75E14FC31, 0xA1258379A94D028D, 0xCAD2F7F5359A3B3E, 0x096EE45813A04330,   // 1e-30, 1e-29
    0xFD87B5F28300CA0D, 0x8BCA9D6E188853FC, 0x9E74D1B791E07E48, 0x775EA264CF55347D,   // 1e-28, 1e-27
    0xC612062576589DDA, 0x95364AFE032A819D, 0xF79687AED3EEC551, 0x3A83DDBD83F52204,   // 1e-26, 1e-25
    0x9ABE14CD44753B52, 0xC4926A9672793542, 0xC16D9A0095928A27, 0x75B7053C0F178293,   // 1e-24, 1e-23
    0xF1C90080BAF72CB1, 0x5324C68B12DD6338, 0x971DA05074DA7BEE, 0xD3F6FC16EBCA5E03,   // 1e-22, 1e-21
    0xBCE5086492111AEA, 0x88F4BB1CA6BCF584, 0xEC1E4A7DB69561A5, 0x2B31E9E3D06C32E5,   // 1e-20, 1e-19
    0x9392EE8E921D5D07, 0x3AFF322E62439FCF, 0xB877AA3236A4B449, 0x09BEFEB9FAD487C2,   // 1e-18, 1e-17
    0xE69594BEC44DE15B, 0x4C2EBE687989A9B3, 0x901D7CF73AB0ACD9, 0x0F9D37014BF60A10,   // 1e-16, 1e-15
    0xB424DC35095CD80F, 0x538484C19EF38C94, 0xE12E13424BB40E13, 0x2865A5F206B06FB9,   // 1e-14, 1e-13
    0x8CBCCC096F5088CB, 0xF93F87B7442E45D3, 0xAFEBFF0BCB24AAFE, 0xF78F69A51539D748,   // 1e-12, 1e-11
    0xDBE6FECEBDEDD5BE, 0xB573440E5A884D1B, 0x89705F4136B4A597, 0x31680A88F8953030,   // 1e-10, 1e-9
    0xABCC77118461CEFC, 0xFDC20D2B36BA7C3D, 0xD6BF94D5E57A42BC, 0x3D32907604691B4C,   // 1e-8, 1e-7
    0x8637BD05AF6C69B5, 0xA63F9A49C2C1B10F, 0xA7C5AC471B478423, 0x0FCF80DC33721D53,   // 1e-6, 1e-5
    0xD1B71758E219652B, 0xD3C36113404EA4A8, 0x83126E978D4FDF3B, 0x645A1CAC083126E9,   // 1e-4, 1e-3
    0xA3D70A3D70A3D70A, 0x3D70A3D70A3D70A3, 0xCCCCCCCCCCCCCCCC, 0xCCCCCCCCCCCCCCCC,   // 1e-2, 1e-1
    0x8000000000000000, 0x0000000000000000, 0xA000000000000000, 0x0000000000000000,   // 1e0, 1e1
    0xC800000000000000, 0x0000000000000000, 0xFA00000000000000, 0x0000000000000000,   // 1e2, 1e3
    0x9C40000000000000, 0x0000000000000000, 0xC350000000000000, 0x0000000000000000,   // 1e4, 1e5
    0xF424000000000000, 0x0000000000000000, 0x9896800000000000, 0x0000000000000000,   // 1e6, 1e7
    0xBEBC200000000000, 0x0000000000000000, 0xEE6B280000000000, 0x0000000000000000,   // 1e8, 1e9
    0x9502F90000000000, 0x0000000000000000, 0xBA43B74000000000, 0x0000000000000000,   // 1e10, 1e11
    0xE8D4A51000000000, 0x0000000000000000, 0x9184E72A00000000, 0x0000000000000000,   // 1e12, 1e13
    0xB5E620F480000000, 0x0000000000000000, 0xE35FA931A0000000, 0x0000000000000000,   // 1e14, 1e15
    0x8E1BC9BF04000000, 0x0000000000000000, 0xB1A2BC2EC5000000, 0x0000000000000000,   // 1e16, 1e17
    0xDE0B6B3A76400000, 0x0000000000000000, 0x8AC7230489E80000, 0x0000000000000000,   // 1e18, 1e19
    0xAD78EBC5AC620000, 0x0000000000000000, 0xD8D726B7177A8000, 0x0000000000000000,   // 1e20, 1e21
    0x878678326EAC9000, 0x0000000000000000, 0xA968163F0A57B400, 0x0000000000000000,   // 1e22, 1e23
    0xD3C21BCECCEDA100, 0x0000000000000000, 0x84595161401484A0, 0x0000000000000000,   // 1e24, 1e25
    0xA56FA5B99019A5C8, 0x0000000000000000, 0xCECB8F27F4200F3A, 0x0000000000000000,   // 1e26, 1e27
    0x813F3978F8940984, 0x4000000000000000, 0xA18F07D736B90BE5, 0x5000000000000000,   // 1e28, 1e29
    0xC9F2C9CD04674EDE, 0xA400000000000000, 0xFC6F7C4045812296, 0x4D00000000000000,   // 1e30, 1e31
    0x9DC5ADA82B70B59D, 0xF020000000000000, 0xC5371912364CE305, 0x6C28000000000000,   // 1e32, 1e33
    0xF684DF56C3E01BC6, 0xC732000000000000, 0x9A130B963A6C115C, 0x3C7F400000000000,   // 1e34, 1e35
    0xC097CE7BC90715B3, 0x4B9F100000000000, 0xF0BDC21ABB48DB20, 0x1E86D40000000000,   // 1e36, 1e37
    0x96769950B50D88F4, 0x1314448000000000, 0xBC143FA4E250EB31, 0x17D955A000000000,   // 1e38, 1e39
    0xEB194F8E1AE525FD, 0x5DCFAB0800000000, 0x92EFD1B8D0CF37BE, 0x5AA1CAE500000000,   // 1e40, 1e41
    0xB7ABC627050305AD, 0xF14A3D9E40000000, 0xE596B7B0C643C719, 0x6D9CCD05D0000000,   // 1e42, 1e43
    0x8F7E32CE7BEA5C6F, 0xE4820023A2000000, 0xB35DBF821AE4F38B, 0xDDA2802C8A800000,   // 1e44, 1e45
    0xE0352F62A19E306E, 0xD50B2037AD200000, 0x8C213D9DA502DE45, 0x4526F422CC340000,   // 1e46, 1e47
    0xAF298D050E4395D6, 0x9670B12B7F410000, 0xDAF3F04651D47B4C, 0x3C0CDD765F114000,   // 1e48, 1e49
    0x88D8762BF324CD0F, 0xA5880A69FB6AC800, 0xAB0E93B6EFEE0053, 0x8EEA0D047A457A00,   // 1e50, 1e51
    0xD5D238A4ABE98068, 0x72A4904598D6D880, 0x85A36366EB71F041, 0x47A6DA2B7F864750,   // 1e52, 1e53
    0xA70C3C40A64E6C51, 0x999090B65F67D924, 0xD0CF4B50CFE20765, 0xFFF4B4E3F741CF6D,   // 1e54, 1e55
    0x82818F1281ED449F, 0xBFF8F10E7A8921A4, 0xA321F2D7226895C7, 0xAFF72D52192B6A0D,   // 1e56, 1e57
    0xCBEA6F8CEB02BB39, 0x9BF4F8A69F764490, 0xFEE50B7025C36A08, 0x02F236D04753D5B4,   // 1e58, 1e59
    0x9F4F2726179A2245, 0x01D762422C946590, 0xC722F0EF9D80AAD6, 0x424D3AD2B7B97EF5,   // 1e60, 1e61
    0xF8EBAD2B84E0D58B, 0xD2E0898765A7DEB2, 0x9B934C3B330C8577, 0x63CC55F49F88EB2F,   // 1e62, 1e63
    0xC2781F49FFCFA6D5, 0x3CBF6B71C76B25FB, 0xF316271C7FC3908A, 0x8BEF464E3945EF7A,   // 1e64, 1e65
    0x97EDD871CFDA3A56, 0x97758BF0E3CBB5AC, 0xBDE94E8E43D0C8EC, 0x3D52EEED1CBEA317,   // 1e66, 1e67
    0xED63A231D4C4FB27, 0x4CA7AAA863EE4BDD, 0x945E455F24FB1CF8, 0x8FE8CAA93E74EF6A,   // 1e68, 1e69
    0xB975D6B6EE39E436, 0xB3E2FD538E122B44, 0xE7D34C64A9C85D44, 0x60DBBCA87196B616,   // 1e70, 1e71
    0x90E40FBEEA1D3A4A, 0xBC8955E946FE31CD, 0xB51D13AEA4A488DD, 0x6BABAB6398BDBE41,   // 1e72, 1e73
    0xE264589A4DCDAB14, 0xC696963C7EED2DD1, 0x8D7EB76070A08AEC, 0xFC1E1DE5CF543CA2,   // 1e74, 1e75
    0xB0DE65388CC8ADA8, 0x3B25A55F43294BCB, 0xDD15FE86AFFAD912, 0x49EF0EB713F39EBE,   // 1e76, 1e77
    0x8A2DBF142DFCC7AB, 0x6E3569326C784337, 0xACB92ED9397BF996, 0x49C2C37F07965404,   // 1e78, 1e79
    0xD7E77A8F87DAF7FB, 0xDC33745EC97BE906, 0x86F0AC99B4E8DAFD, 0x69A028BB3DED71A3,   // 1e80, 1e81
    0xA8ACD7C0222311BC, 0xC40832EA0D68CE0C, 0xD2D80DB02AABD62B, 0xF50A3FA490C30190,   // 1e82, 1e83
    0x83C7088E1AAB65DB, 0x792667C6DA79E0FA, 0xA4B8CAB1A1563F52, 0x577001B891185938,   // 1e84, 1e85
    0xCDE6FD5E09ABCF26, 0xED4C0226B55E6F86, 0x80B05E5AC60B6178, 0x544F8158315B05B4,   // 1e86, 1e87
    0xA0DC75F1778E39D6, 0x696361AE3DB1C721, 0xC913936DD571C84C, 0x03BC3A19CD1E38E9,   // 1e88, 1e89
    0xFB5878494ACE3A5F, 0x04AB48A04065C723, 0x9D174B2DCEC0E47B, 0x62EB0D64283F9C76,   // 1e90, 1e91
    0xC45D1DF942711D9A, 0x3BA5D0BD324F8394, 0xF5746577930D6500, 0xCA8F44EC7EE36479,   // 1e92, 1e93
    0x9968BF6ABBE85F20, 0x7E998B13CF4E1ECB, 0xBFC2EF456AE276E8, 0x9E3FEDD8C321A67E,   // 1e94, 1e95
    0xEFB3AB16C59B14A2, 0xC5CFE94EF3EA101E, 0x95D04AEE3B80ECE5, 0xBBA1F1D158724A12,   // 1e96, 1e97
    0xBB445DA9CA61281F, 0x2A8A6E45AE8EDC97, 0xEA1575143CF97226, 0xF52D09D71A3293BD,   // 1e98, 1e99
    0x924D692CA61BE758, 0x593C2626705F9C56, 0xB6E0C377CFA2E12E, 0x6F8B2FB00C77836C,   // 1e100, 1e101
    0xE498F455C38B997A, 0x0B6DFB9C0F956447, 0x8EDF98B59A373FEC, 0x4724BD4189BD5EAC,   // 1e102, 1e103
    0xB2977EE300C50FE7, 0x58EDEC91EC2CB657, 0xDF3D5E9BC0F653E1, 0x2F2967B66737E3ED,   // 1e104, 1e105
    0x8B865B215899F46C, 0xBD79E0D20082EE74, 0xAE67F1E9AEC07187, 0xECD8590680A3AA11,   // 1e106, 1e107
    0xDA01EE641A708DE9, 0xE80E6F4820CC9495, 0x884134FE908658B2, 0x3109058D147FDCDD,   // 1e108, 1e109
    0xAA51823E34A7EEDE, 0xBD4B46F0599FD415, 0xD4E5E2CDC1D1EA96, 0x6C9E18AC7007C91A,   // 1e110, 1e111
    0x850FADC09923329E, 0x03E2CF6BC604DDB0, 0xA6539930BF6BFF45, 0x84DB8346B786151C,   // 1e112, 1e113
    0xCFE87F7CEF46FF16, 0xE612641865679A63, 0x81F14FAE158C5F6E, 0x4FCB7E8F3F60C07E,   // 1e114, 1e115
    0xA26DA3999AEF7749, 0xE3BE5E330F38F09D, 0xCB090C8001AB551C, 0x5CADF5BFD3072CC5,   // 1e116, 1e117
    0xFDCB4FA002162A63, 0x73D9732FC7C8F7F6, 0x9E9F11C4014DDA7E, 0x2867E7FDDCDD9AFA,   // 1e118, 1e119
    0xC646D63501A1511D, 0xB281E1FD541501B8, 0xF7D88BC24209A565, 0x1F225A7CA91A4226,   // 1e120, 1e121
    0x9AE757596946075F, 0x3375788DE9B06958, 0xC1A12D2FC3978937, 0x0052D6B1641C83AE,   // 1e122, 1e123
    0xF209787BB47D6B84, 0xC0678C5DBD23A49A, 0x9745EB4D50CE6332, 0xF840B7BA963646E0,   // 1e124, 1e125
    0xBD176620A501FBFF, 0xB650E5A93BC3D898, 0xEC5D3FA8CE427AFF, 0xA3E51F138AB4CEBE,   // 1e126, 1e127
    0x93BA47C980E98CDF, 0xC66F336C36B10137, 0xB8A8D9BBE123F017, 0xB80B0047445D4184,   // 1e128, 1e129
    0xE6D3102AD96CEC1D, 0xA60DC059157491E5, 0x9043EA1AC7E41392, 0x87C89837AD68DB2F,   // 1e130, 1e131
    0xB454E4A179DD1877, 0x29BABE4598C311FB, 0xE16A1DC9D8545E94, 0xF4296DD6FEF3D67A,   // 1e132, 1e133
    0x8CE2529E2734BB1D, 0x1899E4A65F58660C, 0xB01AE745B101E9E4, 0x5EC05DCFF72E7F8F,   // 1e134, 1e135
    0xDC21A1171D42645D, 0x76707543F4FA1F73, 0x899504AE72497EBA, 0x6A06494A791C53A8,   // 1e136, 1e137
    0xABFA45DA0EDBDE69, 0x0487DB9D17636892, 0xD6F8D7509292D603, 0x45A9D2845D3C42B6,   // 1e138, 1e139
    0x865B86925B9BC5C2, 0x0B8A2392BA45A9B2, 0xA7F26836F282B732, 0x8E6CAC7768D7141E,   // 1e140, 1e141
    0xD1EF0244AF2364FF, 0x3207D795430CD926, 0x8335616AED761F1F, 0x7F44E6BD49E807B8,   // 1e142, 1e143
    0xA402B9C5A8D3A6E7, 0x5F16206C9C6209A6, 0xCD036837130890A1, 0x36DBA887C37A8C0F,   // 1e144, 1e145
    0x802221226BE55A64, 0xC2494954DA2C9789, 0xA02AA96B06DEB0FD, 0xF2DB9BAA10B7BD6C,   // 1e146, 1e147
    0xC83553C5C8965D3D, 0x6F92829494E5ACC7, 0xFA42A8B73ABBF48C, 0xCB772339BA1F17F9,   // 1e148, 1e149
    0x9C69A97284B578D7, 0xFF2A760414536EFB, 0xC38413CF25E2D70D, 0xFEF5138519684ABA,   // 1e150, 1e151
    0xF46518C2EF5B8CD1, 0x7EB258665FC25D69, 0x98BF2F79D5993802, 0xEF2F773FFBD97A61,   // 1e152, 1e153
    0xBEEEFB584AFF8603, 0xAAFB550FFACFD8FA, 0xEEAABA2E5DBF6784, 0x95BA2A53F983CF38,   // 1e154, 1e155
    0x952AB45CFA97A0B2, 0xDD945A747BF26183, 0xBA756174393D88DF, 0x94F971119AEEF9E4,   // 1e156, 1e157
    0xE912B9D1478CEB17, 0x7A37CD5601AAB85D, 0x91ABB422CCB812EE, 0xAC62E055C10AB33A,   // 1e158, 1e159
    0xB616A12B7FE617AA, 0x577B986B314D6009, 0xE39C49765FDF9D94, 0xED5A7E85FDA0B80B,   // 1e160, 1e161
    0x8E41ADE9FBEBC27D, 0x14588F13BE847307, 0xB1D219647AE6B31C, 0x596EB2D8AE258FC8,   // 1e162, 1e163
    0xDE469FBD99A05FE3, 0x6FCA5F8ED9AEF3BB, 0x8AEC23D680043BEE, 0x25DE7BB9480D5854,   // 1e164, 1e165
    0xADA72CCC20054AE9, 0xAF561AA79A10AE6A, 0xD910F7FF28069DA4, 0x1B2BA1518094DA04,   // 1e166, 1e167
    0x87AA9AFF79042286, 0x90FB44D2F05D0842, 0xA99541BF57452B28, 0x353A1607AC744A53,   // 1e168, 1e169
    0xD3FA922F2D1675F2, 0x42889B8997915CE8, 0x847C9B5D7C2E09B7, 0x69956135FEBADA11,   // 1e170, 1e171
    0xA59BC234DB398C25, 0x43FAB9837E699095, 0xCF02B2C21207EF2E, 0x94F967E45E03F4BB,   // 1e172, 1e173
    0x8161AFB94B44F57D, 0x1D1BE0EEBAC278F5, 0xA1BA1BA79E1632DC, 0x6462D92A69731732,   // 1e174, 1e175
    0xCA28A291859BBF93, 0x7D7B8F7503CFDCFE, 0xFCB2CB35E702AF78, 0x5CDA735244C3D43E,   // 1e176, 1e177
    0x9DEFBF01B061ADAB, 0x3A0888136AFA64A7, 0xC56BAEC21C7A1916, 0x088AAA1845B8FDD0,   // 1e178, 1e179
    0xF6C69A72A3989F5B, 0x8AAD549E57273D45, 0x9A3C2087A63F6399, 0x36AC54E2F678864B,   // 1e180, 1e181
    0xC0CB28A98FCF3C7F, 0x84576A1BB416A7DD, 0xF0FDF2D3F3C30B9F, 0x656D44A2A11C51D5,   // 1e182, 1e183
    0x969EB7C47859E743, 0x9F644AE5A4B1B325, 0xBC4665B596706114, 0x873D5D9F0DDE1FEE,   // 1e184, 1e185
    0xEB57FF22FC0C7959, 0xA90CB506D155A7EA, 0x9316FF75DD87CBD8, 0x09A7F12442D588F2,   // 1e186, 1e187
    0xB7DCBF5354E9BECE, 0x0C11ED6D538AEB2F, 0xE5D3EF282A242E81, 0x8F1668C8A86DA5FA,   // 1e188, 1e189
    0x8FA475791A569D10, 0xF96E017D694487BC, 0xB38D92D760EC4455, 0x37C981DCC395A9AC,   // 1e190, 1e191
    0xE070F78D3927556A, 0x85BBE253F47B1417, 0x8C469AB843B89562, 0x93956D7478CCEC8E,   // 1e192, 1e193
    0xAF58416654A6BABB, 0x387AC8D1970027B2, 0xDB2E51BFE9D0696A, 0x06997B05FCC0319E,   // 1e194, 1e195
    0x88FCF317F22241E2, 0x441FECE3BDF81F03, 0xAB3C2FDDEEAAD25A, 0xD527E81CAD7626C3,   // 1e196, 1e197
    0xD60B3BD56A5586F1, 0x8A71E223D8D3B074, 0x85C7056562757456, 0xF6872D5667844E49,   // 1e198, 1e199
    0xA738C6BEBB12D16C, 0xB428F8AC016561DB, 0xD106F86E69D785C7, 0xE13336D701BEBA52,   // 1e200, 1e201
    0x82A45B450226B39C, 0xECC0024661173473, 0xA34D721642B06084, 0x27F002D7F95D0190,   // 1e202, 1e203
    0xCC20CE9BD35C78A5, 0x31EC038DF7B441F4, 0xFF290242C83396CE, 0x7E67047175A15271,   // 1e204, 1e205
    0x9F79A169BD203E41, 0x0F0062C6E984D386, 0xC75809C42C684DD1, 0x52C07B78A3E60868,   // 1e206, 1e207
    0xF92E0C3537826145, 0xA7709A56CCDF8A82, 0x9BBCC7A142B17CCB, 0x88A66076400BB691,   // 1e208, 1e209
    0xC2ABF989935DDBFE, 0x6ACFF893D00EA435, 0xF356F7EBF83552FE, 0x0583F6B8C4124D43,   // 1e210, 1e211
    0x98165AF37B2153DE, 0xC3727A337A8B704A, 0xBE1BF1B059E9A8D6, 0x744F18C0592E4C5C,   // 1e212, 1e213
    0xEDA2EE1C7064130C, 0x1162DEF06F79DF73, 0x9485D4D1C63E8BE7, 0x8ADDCB5645AC2BA8,   // 1e214, 1e215
    0xB9A74A0637CE2EE1, 0x6D953E2BD7173692, 0xE8111C87C5C1BA99, 0xC8FA8DB6CCDD0437,   // 1e216, 1e217
    0x910AB1D4DB9914A0, 0x1D9C9892400A22A2, 0xB54D5E4A127F59C8, 0x2503BEB6D00CAB4B,   // 1e218, 1e219
    0xE2A0B5DC971F303A, 0x2E44AE64840FD61D, 0x8DA471A9DE737E24, 0x5CEAECFED289E5D2,   // 1e220, 1e221
    0xB10D8E1456105DAD, 0x7425A83E872C5F47, 0xDD50F1996B947518, 0xD12F124E28F77719,   // 1e222, 1e223
    0x8A5296FFE33CC92F, 0x82BD6B70D99AAA6F, 0xACE73CBFDC0BFB7B, 0x636CC64D1001550B,   // 1e224, 1e225
    0xD8210BEFD30EFA5A, 0x3C47F7E05401AA4E, 0x8714A775E3E95C78, 0x65ACFAEC34810A71,   // 1e226, 1e227
    0xA8D9D1535CE3B396, 0x7F1839A741A14D0D, 0xD31045A8341CA07C, 0x1EDE48111209A050,   // 1e228, 1e229
    0x83EA2B892091E44D, 0x934AED0AAB460432, 0xA4E4B66B68B65D60, 0xF81DA84D5617853F,   // 1e230, 1e231
    0xCE1DE40642E3F4B9, 0x36251260AB9D668E, 0x80D2AE83E9CE78F3, 0xC1D72B7C6B426019,   // 1e232, 1e233
    0xA1075A24E4421730, 0xB24CF65B8612F81F, 0xC94930AE1D529CFC, 0xDEE033F26797B627,   // 1e234, 1e235
    0xFB9B7CD9A4A7443C, 0x169840EF017DA3B1, 0x9D412E0806E88AA5, 0x8E1F289560EE864E,   // 1e236, 1e237
    0xC491798A08A2AD4E, 0xF1A6F2BAB92A27E2, 0xF5B5D7EC8ACB58A2, 0xAE10AF696774B1DB,   // 1e238, 1e239
    0x9991A6F3D6BF1765, 0xACCA6DA1E0A8EF29, 0xBFF610B0CC6EDD3F, 0x17FD090A58D32AF3,   // 1e240, 1e241
    0xEFF394DCFF8A948E, 0xDDFC4B4CEF07F5B0, 0x95F83D0A1FB69CD9, 0x4ABDAF101564F98E,   // 1e242, 1e243
    0xBB764C4CA7A4440F, 0x9D6D1AD41ABE37F1, 0xEA53DF5FD18D5513, 0x84C86189216DC5ED,   // 1e244, 1e245
    0x92746B9BE2F8552C, 0x32FD3CF5B4E49BB4, 0xB7118682DBB66A77, 0x3FBC8C33221DC2A1,   // 1e246, 1e247
    0xE4D5E82392A40515, 0x0FABAF3FEAA5334A, 0x8F05B1163BA6832D, 0x29CB4D87F2A7400E,   // 1e248, 1e249
    0xB2C71D5BCA9023F8, 0x743E20E9EF511012, 0xDF78E4B2BD342CF6, 0x914DA9246B255416,   // 1e250, 1e251
    0x8BAB8EEFB6409C1A, 0x1AD089B6C2F7548E, 0xAE9672ABA3D0C320, 0xA184AC2473B529B1,   // 1e252, 1e253
    0xDA3C0F568CC4F3E8, 0xC9E5D72D90A2741E, 0x8865899617FB1871, 0x7E2FA67C7A658892,   // 1e254, 1e255
    0xAA7EEBFB9DF9DE8D, 0xDDBB901B98FEEAB7, 0xD51EA6FA85785631, 0x552A74227F3EA565,   // 1e256, 1e257
    0x8533285C936B35DE, 0xD53A88958F87275F, 0xA67FF273B8460356, 0x8A892ABAF368F137,   // 1e258, 1e259
    0xD01FEF10A657842C, 0x2D2B7569B0432D85, 0x8213F56A67F6B29B, 0x9C3B29620E29FC73,   // 1e260, 1e261
    0xA298F2C501F45F42, 0x8349F3BA91B47B8F, 0xCB3F2F7642717713, 0x241C70A936219A73,   // 1e262, 1e263
    0xFE0EFB53D30DD4D7, 0xED238CD383AA0110, 0x9EC95D1463E8A506, 0xF4363804324A40AA,   // 1e264, 1e265
    0xC67BB4597CE2CE48, 0xB143C6053EDCD0D5, 0xF81AA16FDC1B81DA, 0xDD94B7868E94050A,   // 1e266, 1e267
    0x9B10A4E5E9913128, 0xCA7CF2B4191C8326, 0xC1D4CE1F63F57D72, 0xFD1C2F611F63A3F0,   // 1e268, 1e269
    0xF24A01A73CF2DCCF, 0xBC633B39673C8CEC, 0x976E41088617CA01, 0xD5BE0503E085D813,   // 1e270, 1e271
    0xBD49D14AA79DBC82, 0x4B2D8644D8A74E18, 0xEC9C459D51852BA2, 0xDDF8E7D60ED1219E,   // 1e272, 1e273
    0x93E1AB8252F33B45, 0xCABB90E5C942B503, 0xB8DA1662E7B00A17, 0x3D6A751F3B936243,   // 1e274, 1e275
    0xE7109BFBA19C0C9D, 0x0CC512670A783AD4, 0x906A617D450187E2, 0x27FB2B80668B24C5,   // 1e276, 1e277
    0xB484F9DC9641E9DA, 0xB1F9F660802DEDF6, 0xE1A63853BBD26451, 0x5E7873F8A0396973,   // 1e278, 1e279
    0x8D07E33455637EB2, 0xDB0B487B6423E1E8, 0xB049DC016ABC5E5F, 0x91CE1A9A3D2CDA62,   // 1e280, 1e281
    0xDC5C5301C56B75F7, 0x7641A140CC7810FB, 0x89B9B3E11B6329BA, 0xA9E904C87FCB0A9D,   // 1e282, 1e283
    0xAC2820D9623BF429, 0x546345FA9FBDCD44, 0xD732290FBACAF133, 0xA97C177947AD4095,   // 1e284, 1e285
    0x867F59A9D4BED6C0, 0x49ED8EABCCCC485D, 0xA81F301449EE8C70, 0x5C68F256BFFF5A74,   // 1e286, 1e287
    0xD226FC195C6A2F8C, 0x73832EEC6FFF3111, 0x83585D8FD9C25DB7, 0xC831FD53C5FF7EAB,   // 1e288, 1e289
    0xA42E74F3D032F525, 0xBA3E7CA8B77F5E55, 0xCD3A1230C43FB26F, 0x28CE1BD2E55F35EB,   // 1e290, 1e291
    0x80444B5E7AA7CF85, 0x7980D163CF5B81B3, 0xA0555E361951C366, 0xD7E105BCC332621F,   // 1e292, 1e293
    0xC86AB5C39FA63440, 0x8DD9472BF3FEFAA7, 0xFA856334878FC150, 0xB14F98F6F0FEB951,   // 1e294, 1e295
    0x9C935E00D4B9D8D2, 0x6ED1BF9A569F33D3, 0xC3B8358109E84F07, 0x0A862F80EC4700C8,   // 1e296, 1e297
    0xF4A642E14C6262C8, 0xCD27BB612758C0FA, 0x98E7E9CCCFBD7DBD, 0x8038D51CB897789C,   // 1e298, 1e299
    0xBF21E44003ACDD2C, 0xE0470A63E6BD56C3, 0xEEEA5D5004981478, 0x1858CCFCE06CAC74,   // 1e300, 1e301
    0x95527A5202DF0CCB, 0x0F37801E0C43EBC8, 0xBAA718E68396CFFD, 0xD30560258F54E6BA,   // 1e302, 1e303
    0xE950DF20247C83FD, 0x47C6B82EF32A2069, 0x91D28B7416CDD27E, 0x4CDC331D57FA5441,   // 1e304, 1e305
    0xB6472E511C81471D, 0xE0133FE4ADF8E952, 0xE3D8F9E563A198E5, 0x58180FDDD97723A6,   // 1e306, 1e307
    0x8E679C2F5E44FF8F, 0x570F09EAA7EA7648, 0xB201833B35D63F73, 0x2CD2CC6551E513DA,   // 1e308, 1e309
    0xDE81E40A034BCF4F, 0xF8077F7EA65E58D1, 0x8B112E86420F6191, 0xFB04AFAF27FAF782,   // 1e310, 1e311
    0xADD57A27D29339F6, 0x79C5DB9AF1F9B563, 0xD94AD8B1C7380874, 0x18375281AE7822BC,   // 1e312, 1e313
    0x87CEC76F1C830548, 0x8F2293910D0B15B5, 0xA9C2794AE3A3C69A, 0xB2EB3875504DDB22,   // 1e314, 1e315
    0xD433179D9C8CB841, 0x5FA60692A46151EB, 0x849FEEC281D7F328, 0xDBC7C41BA6BCD333,   // 1e316, 1e317
    0xA5C7EA73224DEFF3, 0x12B9B522906C0800, 0xCF39E50FEAE16BEF, 0xD768226B34870A00,   // 1e318, 1e319
    0x81842F29F2CCE375, 0xE6A1158300D46640, 0xA1E53AF46F801C53, 0x60495AE3C1097FD0,   // 1e320, 1e321
    0xCA5E89B18B602368, 0x385BB19CB14BDFC4, 0xFCF62C1DEE382C42, 0x46729E03DD9ED7B5,   // 1e322, 1e323
    0x9E19DB92B4E31BA9, 0x6C07A2C26A8346D1, 0xC5A05277621BE293, 0xC7098B7305241885,   // 1e324, 1e325
    0xF70867153AA2DB38, 0xB8CBEE4FC66D1EA7, 0x9A65406D44A5C903, 0x737F74F1DC043328,   // 1e326, 1e327
    0xC0FE908895CF3B44, 0x505F522E53053FF2, 0xF13E34AABB430A15, 0x647726B9E7C68FEF,   // 1e328, 1e329
    0x96C6E0EAB509E64D, 0x5ECA783430DC19F5, 0xBC789925624C5FE0, 0xB67D16413D132072,   // 1e330, 1e331
    0xEB96BF6EBADF77D8, 0xE41C5BD18C57E88F, 0x933E37A534CBAAE7, 0x8E91B962F7B6F159,   // 1e332, 1e333
    0xB80DC58E81FE95A1, 0x723627BBB5A4ADB0, 0xE61136F2227E3B09, 0xCEC3B1AAA30DD91C,   // 1e334, 1e335
    0x8FCAC257558EE4E6, 0x213A4F0AA5E8A7B1, 0xB3BD72ED2AF29E1F, 0xA988E2CD4F62D19D,   // 1e336, 1e337
    0xE0ACCFA875AF45A7, 0x93EB1B80A33B8605, 0x8C6C01C9498D8B88, 0xBC72F130660533C3,   // 1e338, 1e339
    0xAF87023B9BF0EE6A, 0xEB8FAD7C7F8680B4, 0xDB68C2CA82ED2A05, 0xA67398DB9F6820E1,   // 1e340, 1e341
    0x892179BE91D43A43, 0x88083F8943A1148C, 0xAB69D82E364948D4, 0x6A0A4F6B948959B0,   // 1e342, 1e343
    0xD6444E39C3DB9B09, 0x848CE34679ABB01C, 0x85EAB0E41A6940E5, 0xF2D80E0C0C0B4E11,   // 1e344, 1e345
    0xA7655D1D2103911F, 0x6F8E118F0F0E2195, 0xD13EB46469447567, 0x4B7195F2D2D1A9FB,   // 1e346, 1e347
];
