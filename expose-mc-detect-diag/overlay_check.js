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
    let layer18Count = 0
    let layer20Count = 0

    for (let i = 0; i < count; i++) {
        const info = ObjC.deepUnwrap(arr.objectAtIndex(i))
        if (!info || info.kCGWindowOwnerName !== 'Dock') continue
        const layer = info.kCGWindowLayer
        if (layer === 18) { layer18Count++; continue }
        if (layer === 20) { layer20Count++ }
    }

    // App Exposé: layer-18 present, at least one layer-20, AND count(layer=20) <= count(layer=18)
    // Mission Control: layer-18 present AND count(layer=20) > count(layer=18)
    const expose = layer18Count > 0 && layer20Count > 0 && layer20Count <= layer18Count
    const mc     = layer18Count > 0 && layer20Count > layer18Count
    return `expose:${expose ? 1 : 0} mc:${mc ? 1 : 0}  (layer18Count:${layer18Count} layer20Count:${layer20Count})`
}
