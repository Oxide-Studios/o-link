/* Shared NUI map runtime. Consumers supply their own Vue instance and overlays. */
(function (global) {
    const stores = new WeakMap()
    function inside(bounds, x, y) {
        return bounds && Number.isFinite(x) && Number.isFinite(y)
            && x >= bounds.minX && x <= bounds.maxX && y >= bounds.minY && y <= bounds.maxY
    }
    function project(map, x, y) {
        const b = map.bounds
        return { px: (x - b.minX) / (b.maxX - b.minX) * map.width,
            py: (b.maxY - y) / (b.maxY - b.minY) * map.height }
    }
    function unproject(map, px, py) {
        const b = map.bounds
        return { x: b.minX + px / map.width * (b.maxX - b.minX),
            y: b.maxY - py / map.height * (b.maxY - b.minY) }
    }
    function getResourceName(fallback) {
        const host = global.location?.hostname || ''
        if (host.startsWith('cfx-nui-')) return host.slice(8)
        return typeof GetParentResourceName === 'function' ? GetParentResourceName() : fallback
    }
    function store(Vue, resource) {
        if (stores.has(Vue)) return stores.get(Vue)
        const state = Vue.reactive({ ready: false, mode: 'combined', labels: {}, catalog: null, assetBase: '', error: false, version: -1 })
        let retry, loading = false
        function apply(data) {
            if (!data || !data.catalog?.maps) return
            if (Number.isFinite(data.version) && data.version < state.version) return
            Object.assign(state, data, { ready: data.ready === true, error: false })
            if (state.ready) clearTimeout(retry)
        }
        async function load() {
            if (loading) return
            loading = true
            try {
                const response = await fetch('https://' + getResourceName(resource) + '/olink:map:getConfig', {
                    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}',
                })
                if (!response.ok) throw new Error('Map configuration unavailable')
                apply(await response.json())
            } catch { state.error = true }
            finally {
                loading = false
                if (!state.ready) retry = setTimeout(load, 1000)
            }
        }
        global.addEventListener('message', event => {
            if (event.data?.action === 'olink:map:config') apply(event.data.data)
        })
        stores.set(Vue, state)
        load()
        return state
    }
    function use(Vue, options = {}) {
        const { ref, computed, watch, unref } = Vue
        const state = store(Vue, options.resource)
        const selected = ref('mainland')
        const mapId = computed(() => state.mode === 'combined' ? 'combined' : state.mode === 'disabled' ? 'mainland' : selected.value)
        const definition = computed(() => state.catalog?.maps[mapId.value])
        const field = (key, fallback) => computed(() => definition.value?.[key] ?? fallback)
        const isCayo = (x, y) => inside(state.catalog?.regions.cayo, x, y)
        function selectMapLayer(id) {
            if (state.mode === 'separate' && (id === 'mainland' || id === 'cayo')) selected.value = id
        }
        function focusMap(x, y) {
            if (state.mode === 'separate') selected.value = isCayo(x, y) ? 'cayo' : 'mainland'
        }
        if (options.focus) watch(() => {
            const point = typeof options.focus === 'function' ? options.focus() : unref(options.focus)
            return [state.mode, state.ready, point?.x, point?.y]
        }, ([mode, ready, x, y], previous = []) => {
            if (ready && Number.isFinite(x) && Number.isFinite(y)
                && (mode !== previous[0] || ready !== previous[1] || x !== previous[2] || y !== previous[3])) focusMap(x, y)
        }, { immediate: true })
        const containsPoint = (x, y) => {
            if (!state.ready || !inside(definition.value?.bounds, x, y)) return false
            if (mapId.value === 'mainland') return !isCayo(x, y)
            return mapId.value !== 'cayo' || isCayo(x, y)
        }
        function containsPolygon(points) {
            if (!state.ready || !Array.isArray(points) || !points.length) return false
            const x = points.reduce((sum, point) => sum + point.x, 0) / points.length
            const y = points.reduce((sum, point) => sum + point.y, 0) / points.length
            if (mapId.value === 'mainland' && isCayo(x, y)) return false
            const b = definition.value.bounds
            return Math.max(...points.map(point => point.x)) >= b.minX && Math.min(...points.map(point => point.x)) <= b.maxX
                && Math.max(...points.map(point => point.y)) >= b.minY && Math.min(...points.map(point => point.y)) <= b.maxY
        }
        const worldToPlanePx = (x, y) => definition.value ? project(definition.value, x, y) : { px: 0, py: 0 }
        const planePxToWorld = (x, y) => definition.value ? unproject(definition.value, x, y) : null
        const worldToPercent = (x, y) => {
            const point = worldToPlanePx(x, y)
            return { x: point.px / (definition.value?.width || 1) * 100, y: point.py / (definition.value?.height || 1) * 100 }
        }
        const tileSrc = key => {
            const file = definition.value?.tiles[key]
            return file ? state.assetBase + file : ''
        }
        const tileStyle = (key, zoom = 1) => {
            const map = definition.value
            if (!map) return { display: 'none' }
            const [col, row] = String(key).split('_').map(Number)
            return { position: 'absolute', left: col * map.tileSize * zoom + 'px', top: row * map.tileSize * zoom + 'px',
                width: Math.min(map.tileSize, map.width - col * map.tileSize) * zoom + 'px',
                height: Math.min(map.tileSize, map.height - row * map.tileSize) * zoom + 'px' }
        }
        const allTiles = computed(() => !state.ready || !definition.value ? [] : Object.keys(definition.value.tiles).map(key => ({
            key: mapId.value + ':' + key, src: tileSrc(key), style: tileStyle(key),
        })))
        function tilesInView(cx, cy, zoom, width, height) {
            const map = definition.value
            if (!state.ready || !map || zoom <= 0 || width <= 0 || height <= 0) return []
            const left = Math.max(0, Math.floor((cx - width / zoom / 2) / map.tileSize) - 1)
            const right = Math.min(map.cols - 1, Math.floor((cx + width / zoom / 2) / map.tileSize) + 1)
            const top = Math.max(0, Math.floor((cy - height / zoom / 2) / map.tileSize) - 1)
            const bottom = Math.min(map.rows - 1, Math.floor((cy + height / zoom / 2) / map.tileSize) + 1)
            const result = []
            for (let row = top; row <= bottom; row++) for (let col = left; col <= right; col++) {
                const key = col + '_' + row
                result.push({ key: mapId.value + ':' + key, src: tileSrc(key), style: tileStyle(key) })
            }
            return result
        }
        return {
            MAP_BOUNDS: field('bounds', { minX: 0, maxX: 1, minY: 0, maxY: 1 }),
            MAP_W: field('width', 1), MAP_H: field('height', 1), TILE_SIZE: field('tileSize', 256),
            TILE_COLS: computed(() => state.ready ? definition.value?.cols || 0 : 0),
            TILE_ROWS: computed(() => state.ready ? definition.value?.rows || 0 : 0),
            mapReady: computed(() => state.ready), mapError: computed(() => state.error),
            mapMode: computed(() => state.mode), mapLayer: mapId,
            mapLabels: computed(() => state.labels), mapOptions: computed(() => ['mainland', 'cayo'].map(id => ({ id, label: state.labels[id] || id }))),
            mapViewKey: computed(() => (state.ready ? state.catalog.revision : '') + ':' + mapId.value + ':' + state.mode),
            selectMapLayer, focusMap, containsPoint, containsPolygon, isCayo, worldToPlanePx, planePxToWorld, worldToPercent,
            tileSrc, tileStyle, allTiles, tilesInView,
        }
    }
    global.OxideMap = { use, project, unproject, inside }
})(globalThis)
