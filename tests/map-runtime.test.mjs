import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'
import { createRequire } from 'node:module'
const require = createRequire(new URL('../../oxide-carplayer/web/package.json', import.meta.url))
const Vue = require('vue')
const catalog = JSON.parse(fs.readFileSync(new URL('../web/map/catalog.json', import.meta.url)))
const calibration = JSON.parse(fs.readFileSync(new URL('../data/map-calibration.json', import.meta.url)))
const runtime = fs.readFileSync(new URL('../web/map/runtime.js', import.meta.url), 'utf8')
const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-7, a + ' differs from ' + b)

async function setup(mode = 'combined') {
    let listener
    const config = (value, version = 1) => ({ ready: true, mode: value, catalog, labels: {}, version, assetBase: 'https://cfx-nui-o-link/web/map/tiles/' })
    const context = vm.createContext({
        location: { hostname: 'cfx-nui-oxide-carplayer' },
        addEventListener(name, callback) { if (name === 'message') listener = callback },
        fetch: async url => { assert.match(url, /^https:\/\/oxide-carplayer\/olink:map:getConfig$/); return { ok: true, json: async () => config(mode) } },
        setTimeout() {}, clearTimeout() {},
    })
    vm.runInContext(runtime, context)
    const map = context.OxideMap.use(Vue)
    await new Promise(resolve => setImmediate(resolve))
    return { map, api: context.OxideMap, update(value, version = 2) { listener({ data: { action: 'olink:map:config', data: config(value, version) } }) } }
}

test('shared calibration preserves every source landmark in all applicable views', async () => {
    const { api } = await setup()
    for (const source of calibration.sources) {
        for (const point of source.points) {
            const x = source.transform.x.offset + source.transform.x.scale * point.pixelX
            const y = source.transform.y.offset + source.transform.y.scale * point.pixelY
            const combined = api.project(catalog.maps.combined, x, y)
            near(combined.px, (source.placement.left + point.pixelX / source.width * source.placement.width) / 2)
            near(combined.py, (source.placement.top + point.pixelY / source.height * source.placement.height) / 2)
            const world = api.unproject(catalog.maps.combined, combined.px, combined.py)
            near(world.x, x)
            near(world.y, y)
            const separate = api.project(catalog.maps[source.id], x, y)
            near(separate.px, source.id === 'cayo' ? point.pixelX / 2 : combined.px)
            near(separate.py, source.id === 'cayo' ? point.pixelY / 2 : combined.py)
        }
    }
})

test('separate view selection is local to the view; disabling Cayo hides its markers', async () => {
    const { map, api, update } = await setup('separate')
    const second = api.use(Vue)
    map.selectMapLayer('cayo')
    assert.equal(map.mapLayer.value, 'cayo')
    assert.equal(second.mapLayer.value, 'mainland')
    assert.equal(map.containsPoint(4800, -5000), true)
    assert.equal(map.containsPoint(223, -995), false)
    update('disabled')
    assert.equal(map.mapLayer.value, 'mainland')
    assert.equal(map.containsPoint(4800, -5000), false)
    assert.equal(map.containsPoint(223, -995), true)
    map.selectMapLayer('cayo')
    assert.equal(map.mapLayer.value, 'mainland')
})

test('auto selection follows focus coordinates and stale responses cannot revert a mode change', async () => {
    const { api, update } = await setup('separate')
    const focus = Vue.ref({ x: 223, y: -995 })
    const map = api.use(Vue, { focus })
    focus.value = { x: 4800, y: -5000 }
    await Vue.nextTick()
    assert.equal(map.mapLayer.value, 'cayo')
    update('disabled', 4)
    update('combined', 3)
    assert.equal(map.mapMode.value, 'disabled')
    assert.equal(map.mapLayer.value, 'mainland')
})

test('all tile references resolve to one owner and partial edges have the correct display size', async () => {
    const { map, update } = await setup()
    for (const id of ['combined', 'mainland', 'cayo']) {
        update(id === 'combined' ? 'combined' : 'separate')
        if (id !== 'combined') map.selectMapLayer(id)
        const definition = catalog.maps[id]
        for (const [key, file] of Object.entries(definition.tiles)) {
            assert.ok(fs.existsSync(new URL('../web/map/tiles/' + file, import.meta.url)), file)
            assert.equal(map.tileSrc(key), 'https://cfx-nui-o-link/web/map/tiles/' + file)
            const [col, row] = key.split('_').map(Number)
            const style = map.tileStyle(key)
            near(parseFloat(style.width), Math.min(256, definition.width - col * 256))
            near(parseFloat(style.height), Math.min(256, definition.height - row * 256))
        }
    }
})

test('tile culling and polygon filtering respect the selected island', async () => {
    const { map } = await setup('separate')
    const visible = map.tilesInView(1000, 1200, 1, 600, 400)
    assert.ok(visible.length > 0 && visible.length < Object.keys(catalog.maps.mainland.tiles).length)
    const cayo = [{ x: 4500, y: -4500 }, { x: 5000, y: -4500 }, { x: 5000, y: -5000 }]
    assert.equal(map.containsPolygon(cayo), false)
    map.selectMapLayer('cayo')
    assert.equal(map.containsPolygon(cayo), true)
    assert.equal(map.containsPolygon([{ x: 0, y: 0 }, { x: 100, y: 0 }, { x: 100, y: 100 }]), false)
})
