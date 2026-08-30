#include <metal_stdlib>
using namespace metal;

struct StereogramParams {
    int width;
    int height;
    int vwidth;
    int oversam;
    int vmaxsep;
    int s;
    int poffset;
    int yShift;
    int patWidth;
    int patHeight;
    int sourceWidth;
    int sourceHeight;
    float maxdepthF;
    float depthRange;
    float veyeSepF;
    float obsDistF;
    float adjMin;
    float adjSafeRange;
    float adjStart;
    float adjEnd;
    float tScale;
    float tOffsetX;
    float tOffsetY;
    int invert;
};

inline float3 srgbToLinear(float3 c) {
    return select(c / 12.92, pow((c + 0.055) / 1.055, 2.4), c > 0.04045);
}

inline float3 linearToSrgb(float3 c) {
    c = clamp(c, 0.0f, 1.0f);
    return select(c * 12.92, 1.055 * pow(c, 1.0f / 2.4f) - 0.055, c > 0.0031308);
}

inline float3 srgbBytesToOKLab(uchar3 srgb8) {
    float3 srgb = float3(srgb8) / 255.0f;
    float3 lin = srgbToLinear(srgb);
    float l = 0.4122214708f * lin.r + 0.5363325363f * lin.g + 0.0514459929f * lin.b;
    float m = 0.2119034982f * lin.r + 0.6806995451f * lin.g + 0.1073969566f * lin.b;
    float s = 0.0883024619f * lin.r + 0.2817188376f * lin.g + 0.6299787005f * lin.b;
    float3 lms = pow(max(float3(l, m, s), float3(0.0f)), 1.0f / 3.0f);
    return float3(
        0.2104542553f * lms.x + 0.7936177850f * lms.y - 0.0040720468f * lms.z,
        1.9779984951f * lms.x - 2.4285922050f * lms.y + 0.4505937099f * lms.z,
        0.0259040371f * lms.x + 0.7827717662f * lms.y - 0.8086757660f * lms.z
    );
}

inline uchar3 oklabToSrgbBytes(float3 lab) {
    float lp = lab.x + 0.3963377774f * lab.y + 0.2158037573f * lab.z;
    float mp = lab.x - 0.1055613458f * lab.y - 0.0638541728f * lab.z;
    float sp = lab.x - 0.0894841775f * lab.y - 1.2914855480f * lab.z;
    float l = lp * lp * lp;
    float m = mp * mp * mp;
    float s = sp * sp * sp;
    float3 lin = float3(
         4.0767416621f * l - 3.3077115913f * m + 0.2309699292f * s,
        -1.2684380046f * l + 2.6097574011f * m - 0.3413193965f * s,
        -0.0041960863f * l - 0.7034186147f * m + 1.7076147010f * s
    );
    float3 srgb = linearToSrgb(lin);
    return uchar3(round(clamp(srgb, 0.0f, 1.0f) * 255.0f));
}

// One thread per output row. Each thread owns its slice of the per-row buffers
// (lookL_buf, lookR_buf, colour_buf, empty_buf), so there is no cross-thread aliasing.
kernel void stereogram_row(
    device const float*  depths       [[ buffer(0) ]],
    device const uchar4* pattern      [[ buffer(1) ]],
    device int*          lookL_buf    [[ buffer(2) ]],
    device int*          lookR_buf    [[ buffer(3) ]],
    device uchar4*       colour_buf   [[ buffer(4) ]],
    device uchar*        empty_buf    [[ buffer(5) ]],
    device uchar4*       outImage     [[ buffer(6) ]],
    constant StereogramParams& params [[ buffer(7) ]],
    uint y                             [[ thread_position_in_grid ]]
) {
    if ((int)y >= params.height) { return; }

    const int width    = params.width;
    const int vwidth   = params.vwidth;
    const int oversam  = params.oversam;
    const int s        = params.s;
    const int vmaxsep  = params.vmaxsep;
    const int poffset  = params.poffset;
    const int yShift   = params.yShift;
    const int patW     = params.patWidth;
    const int patH     = params.patHeight;
    const int srcW     = params.sourceWidth;
    const int srcH     = params.sourceHeight;
    const int invert   = params.invert;

    device int*    L = lookL_buf  + (uint)y * vwidth;
    device int*    R = lookR_buf  + (uint)y * vwidth;
    device uchar4* C = colour_buf + (uint)y * vwidth;
    device uchar*  E = empty_buf  + (uint)y * vwidth;
    device uchar4* out = outImage + (uint)y * width;

    for (int x = 0; x < vwidth; ++x) {
        L[x] = x;
        R[x] = x;
    }

    // Source row index, computed once per row. The live framing (pan / zoom of
    // the depth map itself) folds into the resample; `DepthTransform.sourceU/V`
    // runs the same two lines on the CPU path — keep them aligned.
    const float invScale = 1.0f / max(1.0f, params.tScale);
    const float spanX    = (float)max(0, srcW - 1);
    const float spanY    = (float)max(0, srcH - 1);
    const float denomX   = (float)max(1, width - 1);
    const float denomY   = (float)max(1, params.height - 1);

    float v0 = (float)y / denomY;
    float sv = clamp(0.5f + (v0 - 0.5f) * invScale - params.tOffsetY, 0.0f, 1.0f);
    int srcY = clamp((int)(sv * spanY), 0, srcH - 1);
    int srcRowBase = srcY * srcW;

    int sep = 0;
    for (int x = 0; x < vwidth; ++x) {
        if (x % oversam == 0) {
            int xr = x / oversam;
            float u0 = (float)xr / denomX;
            float su = clamp(0.5f + (u0 - 0.5f) * invScale - params.tOffsetX, 0.0f, 1.0f);
            int srcX = clamp((int)(su * spanX), 0, srcW - 1);
            float v = depths[srcRowBase + srcX];
            float clamped = clamp((v - params.adjMin) / params.adjSafeRange, 0.0f, 1.0f);
            float h = params.adjStart + clamped * (params.adjEnd - params.adjStart);
            h = clamp(h, 0.0f, 1.0f);
            if (invert) { h = 1.0f - h; }
            float featureZ = params.maxdepthF - h * params.depthRange;
            sep = (int)round(params.veyeSepF * featureZ / (featureZ + params.obsDistF));
        }
        int left = x - sep / 2;
        int right = left + sep;
        if (left < 0 || right >= vwidth) { continue; }

        bool vis = true;
        int lr = L[right];
        if (lr != right) {
            if (lr < left) {
                R[lr] = lr;
                L[right] = right;
            } else {
                vis = false;
            }
        }
        int rl = R[left];
        if (rl != left) {
            if (rl > right) {
                L[rl] = rl;
                R[left] = left;
            } else {
                vis = false;
            }
        }
        if (vis) {
            L[right] = left;
            R[left]  = right;
        }
    }

    int lastlinked = -10;
    for (int x = s; x < vwidth; ++x) {
        int Lx = L[x];
        if (Lx == x || Lx < s) {
            if (lastlinked == x - 1) {
                E[x] = 1;
            } else {
                int px = (((x + poffset) % vmaxsep) / oversam) % patW;
                int row = ((int)y + ((x - s) / vmaxsep) * yShift) % patH;
                E[x] = 0;
                uchar4 p = pattern[row * patW + px];
                C[x] = uchar4(p.r, p.g, p.b, 255);
            }
        } else {
            E[x] = E[Lx];
            uchar4 c = C[Lx];
            C[x] = uchar4(c.r, c.g, c.b, 255);
            lastlinked = x;
        }
    }

    lastlinked = -10;
    for (int x = s - 1; x >= 0; --x) {
        int Rx = R[x];
        if (Rx == x) {
            if (lastlinked == x + 1) {
                E[x] = 1;
            } else {
                int px = (((x + poffset) % vmaxsep) / oversam) % patW;
                int row = ((int)y + ((s - x) / vmaxsep + 1) * yShift) % patH;
                E[x] = 0;
                uchar4 p = pattern[row * patW + px];
                C[x] = uchar4(p.r, p.g, p.b, 255);
            }
        } else {
            E[x] = E[Rx];
            uchar4 c = C[Rx];
            C[x] = uchar4(c.r, c.g, c.b, 255);
            lastlinked = x;
        }
    }

    int x = 0;
    while (x < vwidth) {
        if (E[x] == 0) { x++; continue; }
        int end = x;
        while (end + 1 < vwidth && E[end + 1] == 1) { end++; }
        int runLen = end - x + 1;
        bool hasLeft  = x > 0;
        bool hasRight = end + 1 < vwidth;

        if (hasLeft && hasRight) {
            uchar4 lpx = C[x - 1];
            uchar4 rpx = C[end + 1];
            float3 lLab = srgbBytesToOKLab(uchar3(lpx.r, lpx.g, lpx.b));
            float3 rLab = srgbBytesToOKLab(uchar3(rpx.r, rpx.g, rpx.b));
            float denom = float(runLen + 1);
            for (int i = 0; i < runLen; ++i) {
                float t = float(i + 1) / denom;
                float3 lab = mix(lLab, rLab, t);
                uchar3 rgb = oklabToSrgbBytes(lab);
                C[x + i] = uchar4(rgb, 255);
            }
        } else if (hasLeft || hasRight) {
            uchar4 sp = hasLeft ? C[x - 1] : C[end + 1];
            uchar4 v = uchar4(sp.r, sp.g, sp.b, 255);
            for (int i = 0; i < runLen; ++i) { C[x + i] = v; }
        }
        x = end + 1;
    }

    float invOver = 1.0f / float(oversam);
    for (int xr = 0; xr < width; ++xr) {
        int baseV = xr * oversam;
        uchar4 outPx;
        if (oversam == 1) {
            uchar4 c = C[baseV];
            outPx = uchar4(c.r, c.g, c.b, 255);
        } else {
            float3 sum = float3(0.0f);
            for (int i = 0; i < oversam; ++i) {
                uchar4 c = C[baseV + i];
                sum += srgbBytesToOKLab(uchar3(c.r, c.g, c.b));
            }
            sum *= invOver;
            uchar3 rgb = oklabToSrgbBytes(sum);
            outPx = uchar4(rgb, 255);
        }
        out[xr] = outPx;
    }
}
