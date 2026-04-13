#!/usr/bin/osascript -l JavaScript
// overlay_check.js - query Dock window layers to detect App Exposé / Mission Control.
// No build step, no Xcode required. Runs on any Mac (macOS 10.10+).
//
// Usage: osascript -l JavaScript expose-mc-detect-diag/overlay_check.js

'use strict'
ObjC.import('ApplicationServices')
ObjC.import('Foundation')

function run() {
    const raw = $.CGWindowListCopyWindowInfo(
        $.kCGWindowListOptionOnScreenOnly,
        $.kCGNullWindowID
    )
    if (!raw) return 'expose:0 mc:0  (CGWindowListCopyWindowInfo failed)'

    const arr   = ObjC.castRefToObject(raw)
    const count = arr.count
    let hasOverlay   = false
    let layer20Count = 0

    for (let i = 0; i < count; i++) {
        const info = ObjC.deepUnwrap(arr.objectAtIndex(i))
        if (!info || info.kCGWindowOwnerName !== 'Dock') continue
        const layer = info.kCGWindowLayer
        if (layer === 18) { hasOverlay = true; continue }
        if (layer === 20) { layer20Count++ }
    }

    // App Exposé: layer-18 + 1-2 layer-20 windows
    // Mission Control: layer-18 + 3+ layer-20 windows (3 on single-monitor, 4 on dual)
    const expose = hasOverlay && (layer20Count === 1 || layer20Count === 2)
    const mc     = hasOverlay && layer20Count >= 3
    return `expose:${expose ? 1 : 0} mc:${mc ? 1 : 0}  (overlay:${hasOverlay ? 1 : 0} layer20Count:${layer20Count})`
}
