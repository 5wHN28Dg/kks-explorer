package kks.explorer.ui

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.*
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityNodeProvider
import kks.explorer.Jxl
import kks.explorer.core.Core
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors
import kotlin.math.*

/**
 * The drawing viewer (R1; decisions 0015, 0016): the overview pyramid below its own resolution, vector tiles drawn
 * from the path store (views.flat layout from the core) by a software Canvas on background threads above it, tag
 * hotspots on top. Pan, pinch, double-tap zoom, tap a tag. Screen readers get the tags on screen as virtual views.
 */
@SuppressLint("ViewConstructor")
class SheetView(ctx: Context) : View(ctx) {
    data class TagBox(val id: String, val x0: Float, val y0: Float, val x1: Float, val y1: Float, val status: String, val code: String = "",
                      val photos: String = "none")      // both · equipment · plate · none (the photo coverage view)
    /** an off-page connector (C16, D2 …): its code, box in points, and its name for screen readers ("Connector C16,
     *  continues on Sheet B") */
    data class LinkBox(val label: String, val x0: Float, val y0: Float, val x1: Float, val y1: Float, val name: String)

    private class Sheet(b: ByteArray) {
        val buf: ByteBuffer = ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN)
        val width: Int; val height: Int; val nStyles: Int; val nPaths: Int; val nImages: Int; val nOps: Int; val nXY: Int
        val gx: Int; val gy: Int
        val stylesAt: Int; val pathsAt: Int; val opsAt: Int; val xyAt: Int; val cellsAt: Int; val entriesAt: Int
        val images = ArrayList<IntArray>()         // after, x0, y0, x1, y1, dataOffset, length
        init {
            require(String(b, 0, 4) == "KKF1")
            fun u(i: Int) = buf.getInt(4 + i * 4)
            width = u(0); height = u(1); nStyles = u(2); nPaths = u(3); nImages = u(4); nOps = u(5); nXY = u(6); gx = u(7); gy = u(8)
            stylesAt = 40; pathsAt = stylesAt + nStyles * 16; opsAt = pathsAt + nPaths * 32
            xyAt = opsAt + ((nOps + 3) and 3.inv()); cellsAt = xyAt + nXY * 4; entriesAt = cellsAt + (gx * gy + 1) * 4
            var o = entriesAt + buf.getInt(cellsAt + gx * gy * 4) * 4
            repeat(nImages) {
                val len = buf.getInt(o + 20)
                images.add(intArrayOf(buf.getInt(o), buf.getInt(o + 4), buf.getInt(o + 8), buf.getInt(o + 12), buf.getInt(o + 16), o + 24, len))
                o += 24 + ((len + 3) and 3.inv())
            }
        }
        val widthPt get() = width / 64f
        val heightPt get() = height / 64f
        fun cellRange(v0: Int, v1: Int, size: Int, n: Int): IntRange {
            fun cell(v: Int): Int { val x = v.coerceIn(0, max(0, size - 1)); return min(n - 1, ((x.toLong() * n) / max(1, size)).toInt()) }
            return cell(v0)..cell(v1)
        }
        /** paths whose cells touch the quanta rectangle, ascending (paint order), each once */
        fun visible(x0: Int, y0: Int, x1: Int, y1: Int): IntArray {
            val seen = java.util.BitSet(nPaths)
            for (cy in cellRange(y0, y1, height, gy)) for (cx in cellRange(x0, x1, width, gx)) {
                val c = cy * gx + cx
                val a = buf.getInt(cellsAt + c * 4); val e = buf.getInt(cellsAt + (c + 1) * 4)
                for (k in a until e) seen.set(buf.getInt(entriesAt + k * 4))
            }
            return seen.stream().toArray()
        }
    }

    var onTag: ((String) -> Unit)? = null
    var tags: List<TagBox> = emptyList(); set(v) { field = v; invalidate(); a11y.invalidateRoot() }
    var selected = ""; set(v) { field = v; invalidate(); a11y.invalidateRoot() }
    var highlight: Set<String> = emptySet(); set(v) { field = v; invalidate() }
    var dimmed: Set<String>? = null; set(v) { field = v; invalidate() }   // floor filter: tags not in the set are dimmed
    var links: List<LinkBox> = emptyList(); set(v) { field = v; invalidate(); a11y.invalidateRoot() }
    var linkSel = -1; set(v) { field = v; invalidate() }          // the connector just arrived at, drawn bold
    var onLink: ((Int) -> Unit)? = null                             // a connector tapped: its index in `links`
    /** the open panel's valve symbol (x0, y0, x1, y1 in points), outlined; null = none */
    var symbolBox: List<Float>? = null; set(v) { field = v; invalidate() }

    /** the connector under (x, y) in view px, -1 none (a little slack: they are small) */
    private fun hitLink(x: Float, y: Float): Int {
        val px = ox + x / z; val py = oy + y / z; val pad = 8f / z
        return links.indexOfFirst { px >= it.x0 - pad && px <= it.x1 + pad && py >= it.y0 - pad && py <= it.y1 + pad }
    }

    private var sheet: Sheet? = null
    private var scale0 = 2f
    private class Level(val pieces: List<kks.explorer.Jxl.Piece>, val w: Int, val h: Int)
    private var levels = arrayOfNulls<Level>(0)
    private var levelAsked = BooleanArray(0)
    private var sheetId = ""
    private var gen = 0
    private var z = 1f; private var ox = 0f; private var oy = 0f; private var fitted = false
    private val work = Executors.newFixedThreadPool(max(2, Runtime.getRuntime().availableProcessors() - 2))
    private val main = Handler(Looper.getMainLooper())
    private val tiles = object : LruCache<String, Bitmap>(96 * 1024 * 1024) { override fun sizeOf(k: String, v: Bitmap) = v.byteCount }
    private val pending = HashSet<String>()
    private val tile = 512

    fun setSheet(id: String, scale: Float, nLevels: Int) {
        gen++; sheetId = id; scale0 = scale; fitted = false
        supersedeLevels()
        tiles.evictAll(); pending.clear()
        sheet = null; levels = arrayOfNulls(nLevels); levelAsked = BooleanArray(nLevels); stale = arrayOfNulls(0)
        contentDescription = "Drawing $id"
        val g = gen
        work.execute {
            val data = Core.sheet(id)
            val s = data?.let { Sheet(it) }
            main.post { if (g == gen) { sheet = s; invalidate() } }
        }
        askLevel(nLevels - 1)
    }

    private fun askLevel(k: Int) {
        if (k < 0 || k >= levels.size || levelAsked[k]) return
        levelAsked[k] = true
        val g = gen; val id = sheetId; val d = dark; val e = epoch.get()
        // a level 0 is up to 6400 × 4800 px (123 MB of RGBA): a request superseded by another sheet or a dark-drawings
        // switch is cancelled while queued, and stops between its heavy steps if already running (`epoch`)
        val live = { epoch.get() == e }
        levelJobs.add(work.submit {
            if (!live()) return@submit
            // dark drawings: every pixel through DarkColor here, on the worker (a level 0 is up to 30 M pixels)
            val lv = Core.file("sheets/$id.o$k.jxl")?.let { if (live()) Jxl.pieces(it, map = if (d) DarkColor::rgbaBytes else null, keep = live) else null }
                ?.let { (p, dims) -> Level(p, dims[0], dims[1]) }
            main.post {
                if (g == gen && d == dark && lv != null) {
                    levels[k] = lv
                    for (j in k until stale.size) stale[j] = null    // as sharp or sharper in this mode: the old ones go
                    invalidate()
                }
            }
        })
        levelJobs.removeAll { it.isDone }
    }

    /** cancels the queued and running level decodes (a new sheet or a dark-drawings switch) */
    private fun supersedeLevels() {
        epoch.incrementAndGet()
        for (f in levelJobs) f.cancel(false)
        levelJobs.clear()
    }

    /** dark drawings (Drawings → ⋮ → Dark drawings): the sheet light on dark (DarkColor), markers lightened. Switching
     *  drops the tiles and decodes the overview levels again; until they arrive the levels shown before stay (never a
     *  blank sheet, even when switching back before anything arrived). */
    var dark = false
        set(v) {
            if (field == v) return
            field = v
            supersedeLevels()
            tiles.evictAll(); pending.clear()
            // per level: the one this mode had, else the one shown before that (a quick on → off keeps something)
            stale = Array(levels.size) { k -> levels[k] ?: stale.getOrNull(k) }
            levels = arrayOfNulls(levels.size); levelAsked = BooleanArray(levels.size)
            invalidate(); a11y.invalidateRoot()
        }
    private var stale = arrayOfNulls<Level>(0)        // the other mode's levels, shown until this mode's arrive
    private val epoch = java.util.concurrent.atomic.AtomicInteger()
    private val levelJobs = ArrayList<java.util.concurrent.Future<*>>()

    private fun sheetSize(): Pair<Float, Float> = sheet?.let { it.widthPt to it.heightPt }
        ?: levels.firstOrNull { it != null }?.let { b -> val k = levels.indexOf(b); val s = scale0 / (1 shl k); (b.w / s) to (b.h / s) }
        ?: (1f to 1f)

    fun fit() {
        val (w, h) = sheetSize()
        if (width < 2 || height < 2 || w <= 1f) return
        z = min(width / w, height / h) * 0.98f
        ox = -(width / z - w) / 2; oy = -(height / z - h) / 2
        fitted = true; invalidate(); a11y.invalidateRoot()
    }

    /** zoom to a tag; cy = where its centre lands, as a fraction of the height (above the panel when one is open) */
    fun centerOn(x0: Float, y0: Float, x1: Float, y1: Float, cy: Float = 0.5f) {
        val maxZ = 16f * max(1f, scale0)
        z = min(maxZ, max(z, min(width / max(1f, (x1 - x0) * 5), height / max(1f, (y1 - y0) * 8))))
        ox = (x0 + x1) / 2 - width / z / 2; oy = (y0 + y1) / 2 - height * cy / z
        fitted = true; invalidate(); a11y.invalidateRoot()
    }

    private fun zoomAt(f: Float, px: Float, py: Float) {
        val (w, h) = sheetSize()
        val minZ = min(width / w, height / h) * 0.25f
        val nz = (z * f).coerceIn(minZ, 16f * max(1f, scale0))
        val sx = ox + px / z; val sy = oy + py / z
        z = nz; ox = sx - px / z; oy = sy - py / z
        invalidate(); a11y.invalidateRoot()
    }

    private val scaleDetector = ScaleGestureDetector(ctx, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScale(d: ScaleGestureDetector): Boolean { zoomAt(d.scaleFactor, d.focusX, d.focusY); return true }
    })
    private val gestures = GestureDetector(ctx, object : GestureDetector.SimpleOnGestureListener() {
        override fun onScroll(e1: MotionEvent?, e2: MotionEvent, dx: Float, dy: Float): Boolean { ox += dx / z; oy += dy / z; invalidate(); a11y.invalidateRoot(); return true }
        override fun onDoubleTap(e: MotionEvent): Boolean { zoomAt(2f, e.x, e.y); return true }
        override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
            // a connector opens where its line continues; not while selecting (a tap picks tags only)
            val px = ox + e.x / z; val py = oy + e.y / z; val pad = 8f / z
            // (a tap right on a tag stays the tag's: the connectors' slack must not take it)
            if (!selecting && tags.none { it.status != "pending" && px >= it.x0 && px <= it.x1 && py >= it.y0 && py <= it.y1 })
                hitLink(e.x, e.y).takeIf { it >= 0 }?.let { onLink?.invoke(it); return true }
            val hit = tags.filter { it.status != "pending" && px >= it.x0 - pad && px <= it.x1 + pad && py >= it.y0 - pad && py <= it.y1 + pad }
                .minByOrNull { (it.x1 - it.x0) * (it.y1 - it.y0) }
            if (hit != null) { if (selecting) onToggle?.invoke(hit.id) else { selected = hit.id; onTag?.invoke(hit.id) } }
            return true
        }
        override fun onLongPress(e: MotionEvent) {
            if (!selecting) return
            boxFrom = PointF(ox + e.x / z, oy + e.y / z); box = RectF(boxFrom!!.x, boxFrom!!.y, boxFrom!!.x, boxFrom!!.y)
            performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
            invalidate()
        }
    })

    /** marking a missed tag (R6): one finger drags a box (in points); two fingers still pan and zoom */
    var marking = false; set(v) { field = v; mark = null; invalidate() }
    var onMark: ((Float, Float, Float, Float) -> Unit)? = null
    private var mark: RectF? = null
    private var markFrom: PointF? = null

    /** selecting tags (one photo, place or note for several codes): a tap toggles a tag; a long press then a drag
     *  draws a box that adds every tag it touches. One finger still pans and two fingers zoom: a box needs the hold
     *  first, so moving around the drawing between picks stays the plain drag it always was. */
    var selecting = false; set(v) { field = v; box = null; boxFrom = null; invalidate(); a11y.invalidateRoot() }
    var selection: Set<String> = emptySet(); set(v) { field = v; invalidate(); a11y.invalidateRoot() }
    var onToggle: ((String) -> Unit)? = null
    var onBox: ((List<String>) -> Unit)? = null
    private var box: RectF? = null
    private var boxFrom: PointF? = null

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        boxFrom?.let { a ->
            val p = PointF(ox + e.x / z, oy + e.y / z)
            when (e.actionMasked) {
                MotionEvent.ACTION_MOVE -> box = RectF(min(a.x, p.x), min(a.y, p.y), max(a.x, p.x), max(a.y, p.y))
                MotionEvent.ACTION_UP -> {
                    val b = box
                    boxFrom = null; box = null
                    if (b != null && b.width() > 0f && b.height() > 0f)
                        onBox?.invoke(tags.filter { it.status != "pending" && it.x1 >= b.left && it.x0 <= b.right && it.y1 >= b.top && it.y0 <= b.bottom }.map { it.id })
                }
                MotionEvent.ACTION_CANCEL -> { boxFrom = null; box = null }
            }
            gestures.onTouchEvent(e)          // ends its long press
            invalidate()
            return true
        }
        if (marking && e.pointerCount == 1 && !scaleDetector.isInProgress) {
            val p = PointF(ox + e.x / z, oy + e.y / z)
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> { markFrom = p; mark = RectF(p.x, p.y, p.x, p.y) }
                MotionEvent.ACTION_MOVE -> markFrom?.let { a -> mark = RectF(min(a.x, p.x), min(a.y, p.y), max(a.x, p.x), max(a.y, p.y)) }
                MotionEvent.ACTION_UP -> { val m = mark; markFrom = null; if (m != null && m.width() > 0f) onMark?.invoke(m.left, m.top, m.right, m.bottom) }
                MotionEvent.ACTION_CANCEL -> { markFrom = null; mark = null }
            }
            invalidate()
            return true
        }
        scaleDetector.onTouchEvent(e)
        if (!scaleDetector.isInProgress) gestures.onTouchEvent(e)
        return true
    }

    // ---------------------------------------------------------------- accessibility

    /** The tags inside the view, each a virtual view, through the platform's AccessibilityNodeProvider (no library):
     *  TalkBack reads "11LAB70AA501, verified"; double tap selects. Ids are indices into `tags`; the connectors follow
     *  as LINK0 + their index in `links` ("Connector C16, continues on Sheet B"; double tap follows it). */
    private val a11y = Tags()

    private inner class Tags : AccessibilityNodeProvider() {
        private var focused = -1
        private var hovered = -1
        private fun screenRect(t: TagBox) = Rect(((t.x0 - ox) * z).toInt(), ((t.y0 - oy) * z).toInt(), ((t.x1 - ox) * z).toInt(), ((t.y1 - oy) * z).toInt())
        private fun screenRect(l: LinkBox) = Rect(((l.x0 - ox) * z).toInt(), ((l.y0 - oy) * z).toInt(), ((l.x1 - ox) * z).toInt(), ((l.y1 - oy) * z).toInt())
        private fun shown(r: Rect) = r.right > 0 && r.bottom > 0 && r.left < width && r.top < height
        /** in reading order: rows of about one tag height, top to bottom, each left to right; then the connectors */
        private fun onScreen(): List<Int> = tags.indices.filter { i -> shown(screenRect(tags[i])) }
            .sortedWith(compareBy({ (tags[it].y0 / 12f).toInt() }, { tags[it].x0 })).take(200) +
            links.indices.filter { i -> shown(screenRect(links[i])) }.take(50).map { LINK0 + it }

        fun at(x: Float, y: Float): Int {
            val px = ox + x / z; val py = oy + y / z
            // a connector, unless the finger is right on a tag (the tap rule)
            if (!selecting && !marking && tags.none { px in it.x0..it.x1 && py in it.y0..it.y1 })
                hitLink(x, y).takeIf { it >= 0 }?.let { return LINK0 + it }
            return tags.indices.filter { val t = tags[it]; px in t.x0..t.x1 && py in t.y0..t.y1 }
                .minByOrNull { (tags[it].x1 - tags[it].x0) * (tags[it].y1 - tags[it].y0) } ?: -1
        }

        override fun createAccessibilityNodeInfo(id: Int): AccessibilityNodeInfo? {
            if (id == HOST_VIEW_ID) {
                val info = AccessibilityNodeInfo.obtain(this@SheetView)
                onInitializeAccessibilityNodeInfo(info)
                for (i in onScreen()) info.addChild(this@SheetView, i)
                return info
            }
            if (id >= LINK0) return linkInfo(id)
            val t = tags.getOrNull(id) ?: return null
            val info = AccessibilityNodeInfo.obtain(this@SheetView, id)
            info.packageName = context.packageName
            info.className = "android.widget.Button"
            info.setParent(this@SheetView)
            info.contentDescription = t.code.ifEmpty { "Unread tag" } + ", " +
                (if (coverage) coverWords(t.photos) else when (t.status) { "review" -> "needs checking"; "verified" -> "verified"; else -> "read automatically" }) +
                (if (selecting) (if (t.id in selection) ", selected" else if (t.code.isEmpty()) ", no code: can't be selected" else ", not selected")
                 else if (t.id == selected) ", selected" else "")
            val r = screenRect(t); r.intersect(0, 0, width, height)
            info.setBoundsInParent(r)
            val loc = IntArray(2); getLocationOnScreen(loc)
            info.setBoundsInScreen(Rect(r).apply { offset(loc[0], loc[1]) })
            info.isVisibleToUser = !r.isEmpty
            info.isEnabled = true
            info.isClickable = true
            if (selecting) { info.isCheckable = true; info.isChecked = t.id in selection }
            info.isFocusable = true
            info.isAccessibilityFocused = focused == id
            info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_CLICK)
            info.addAction(if (focused == id) AccessibilityNodeInfo.AccessibilityAction.ACTION_CLEAR_ACCESSIBILITY_FOCUS
                           else AccessibilityNodeInfo.AccessibilityAction.ACTION_ACCESSIBILITY_FOCUS)
            return info
        }

        private fun linkInfo(id: Int): AccessibilityNodeInfo? {
            val l = links.getOrNull(id - LINK0) ?: return null
            val info = AccessibilityNodeInfo.obtain(this@SheetView, id)
            info.packageName = context.packageName
            info.className = "android.widget.Button"
            info.setParent(this@SheetView)
            info.contentDescription = l.name
            val r = screenRect(l); r.intersect(0, 0, width, height)
            info.setBoundsInParent(r)
            val loc = IntArray(2); getLocationOnScreen(loc)
            info.setBoundsInScreen(Rect(r).apply { offset(loc[0], loc[1]) })
            info.isVisibleToUser = !r.isEmpty
            info.isEnabled = !selecting && !marking
            info.isClickable = !selecting && !marking
            info.isFocusable = true
            info.isAccessibilityFocused = focused == id
            if (!selecting && !marking) info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_CLICK)
            info.addAction(if (focused == id) AccessibilityNodeInfo.AccessibilityAction.ACTION_CLEAR_ACCESSIBILITY_FOCUS
                           else AccessibilityNodeInfo.AccessibilityAction.ACTION_ACCESSIBILITY_FOCUS)
            return info
        }

        override fun performAction(id: Int, action: Int, args: android.os.Bundle?): Boolean {
            if (id == HOST_VIEW_ID) return performAccessibilityAction(action, args)
            if (id >= LINK0) {
                if (links.getOrNull(id - LINK0) == null) return false
                when (action) {
                    AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS -> {
                        if (focused == id) return false
                        focused = id; invalidate(); send(id, AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUSED); return true
                    }
                    AccessibilityNodeInfo.ACTION_CLEAR_ACCESSIBILITY_FOCUS -> {
                        if (focused != id) return false
                        focused = -1; invalidate(); send(id, AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUS_CLEARED); return true
                    }
                    AccessibilityNodeInfo.ACTION_CLICK -> {
                        if (selecting || marking) return false
                        onLink?.invoke(id - LINK0); send(id, AccessibilityEvent.TYPE_VIEW_CLICKED); return true
                    }
                }
                return false
            }
            val t = tags.getOrNull(id) ?: return false
            when (action) {
                AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS -> {
                    if (focused == id) return false
                    focused = id; invalidate(); send(id, AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUSED); return true
                }
                AccessibilityNodeInfo.ACTION_CLEAR_ACCESSIBILITY_FOCUS -> {
                    if (focused != id) return false
                    focused = -1; invalidate(); send(id, AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUS_CLEARED); return true
                }
                AccessibilityNodeInfo.ACTION_CLICK -> {
                    if (selecting) onToggle?.invoke(t.id) else { selected = t.id; onTag?.invoke(t.id) }
                    send(id, AccessibilityEvent.TYPE_VIEW_CLICKED); return true
                }
            }
            return false
        }

        fun send(id: Int, type: Int) {
            val am = context.getSystemService(AccessibilityManager::class.java)
            if (am == null || !am.isEnabled) return
            val e = AccessibilityEvent.obtain(type)
            e.packageName = context.packageName
            e.className = "android.widget.Button"
            e.setSource(this@SheetView, id)
            if (id >= LINK0) links.getOrNull(id - LINK0)?.let { e.contentDescription = it.name }
            else tags.getOrNull(id)?.let { e.contentDescription = it.code.ifEmpty { "Unread tag" } }
            parent?.requestSendAccessibilityEvent(this@SheetView, e)
        }

        /** touch exploration: announce the tag under the finger */
        fun hover(e: MotionEvent): Boolean {
            val am = context.getSystemService(AccessibilityManager::class.java)
            if (am == null || !am.isEnabled || !am.isTouchExplorationEnabled) return false
            val id = if (e.action == MotionEvent.ACTION_HOVER_EXIT) -1 else at(e.x, e.y)
            if (id != hovered) {
                if (id >= 0) send(id, AccessibilityEvent.TYPE_VIEW_HOVER_ENTER)
                if (hovered >= 0) send(hovered, AccessibilityEvent.TYPE_VIEW_HOVER_EXIT)
                hovered = id
            }
            return id >= 0
        }

        /** the tags on screen changed (pan, zoom, new tags) */
        fun invalidateRoot() {
            val am = context.getSystemService(AccessibilityManager::class.java)
            if (am == null || !am.isEnabled) return
            val e = AccessibilityEvent.obtain(AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED)
            e.contentChangeTypes = AccessibilityEvent.CONTENT_CHANGE_TYPE_SUBTREE
            e.setSource(this@SheetView)
            e.packageName = context.packageName
            parent?.requestSendAccessibilityEvent(this@SheetView, e)
        }
    }

    override fun getAccessibilityNodeProvider(): AccessibilityNodeProvider = a11y

    override fun dispatchHoverEvent(e: MotionEvent): Boolean = a11y.hover(e) || super.dispatchHoverEvent(e)

    // ---------------------------------------------------------------- drawing

    private val bg = Paint()
    private val white = Paint()
    private val bmpPaint = Paint(Paint.FILTER_BITMAP_FLAG)
    /** colour the tags by their photos instead of by how they were read (Drawings → ⋮ → Colour tags by photos) */
    var coverage = false
        set(v) { field = v; invalidate(); a11y.invalidateRoot() }
    private val tagPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }

    private companion object {
        var firstLogged = false
        const val LINK0 = 1_000_000          // the connectors' virtual view ids start here (the tags' are their indices)
        val LINK = Color.rgb(140, 51, 217)    // an off-page connector's violet (GNOME's linkColor)
        val SYMBOL = Color.rgb(176, 23, 158)  // the valve symbol's magenta (GNOME's viewer, the web's .vsym)
    }

    // the drawing and its tags belong in the accessibility tree (explicit rather than "auto"). Open finding,
    override fun onSizeChanged(w: Int, h: Int, ow: Int, oh: Int) { if (!fitted || ow == 0) fit() }

    override fun onDraw(c: Canvas) {
        // around the sheet: grey; on dark drawings lighter than the dark paper (GNOME's colours)
        bg.color = if (dark) Color.rgb(61, 61, 66) else Color.rgb(209, 212, 217)
        white.color = if (dark) PAPER_DARK else Color.WHITE
        c.drawRect(0f, 0f, width.toFloat(), height.toFloat(), bg)
        if (levels.isEmpty()) return        // no sheet set yet
        if (!fitted) fit()
        val (w, h) = sheetSize()
        val dst = RectF(-ox * z, -oy * z, (w - ox) * z, (h - oy) * z)
        // 1. the overview: the smallest level sharp enough (asked once), else the sharpest one decoded
        var want = 0
        for (k in levels.indices.reversed()) if (scale0 / (1 shl k) >= z * 0.9f) { want = k; break }
        askLevel(want)
        // this mode's level, else the level shown before a dark-drawings switch (not a blurrier one of this mode)
        val best = levels[want] ?: stale.getOrNull(want) ?: levels.firstOrNull { it != null } ?: stale.firstOrNull { it != null }
        // the other mode's levels sharper than this zoom wants aren't shown again: they go now, not when this mode's
        // level of that size arrives (a level 0 is up to 123 MB of bitmaps; zoomed out it might never be asked)
        for (j in 0 until minOf(want, stale.size)) if (stale[j] !== best) stale[j] = null
        if (best != null) {
            val f = dst.width() / best.w
            for (p in best.pieces) c.drawBitmap(p.bmp, null, RectF(dst.left + p.x * f, dst.top + p.y * f,
                dst.left + (p.x + p.bmp.width) * f, dst.top + (p.y + p.bmp.height) * f), bmpPaint)
        } else c.drawRect(dst, white)
        if (best != null && !firstLogged) {   // measurements: process start → the first sheet on screen
            firstLogged = true
            android.util.Log.i("KKSTime", "first sheet ${android.os.SystemClock.uptimeMillis() - android.os.Process.getStartUptimeMillis()} ms after process start")
        }
        // 2. vector tiles once the overview isn't sharp enough
        val s = sheet
        if (s != null && z > scale0 * 1.05f) {
            val e = ceil(log2(z.toDouble())).toInt()
            val tz = 2.0.pow(e).toFloat()
            val span = tile / tz
            val x0 = max(0f, ox); val y0 = max(0f, oy)
            val x1 = min(w, ox + width / z); val y1 = min(h, oy + height / z)
            for (iy in floor(y0 / span).toInt()..floor(y1 / span).toInt()) for (ix in floor(x0 / span).toInt()..floor(x1 / span).toInt()) {
                val key = "$dark:$e:$ix:$iy"
                val t = tiles.get(key)
                if (t != null) {
                    c.drawBitmap(t, null, RectF((ix * span - ox) * z, (iy * span - oy) * z, ((ix + 1) * span - ox) * z, ((iy + 1) * span - oy) * z), bmpPaint)
                } else if (pending.add(key)) {
                    val g = gen; val d = dark
                    work.execute {
                        val bmp = renderTile(s, tz, ix * span, iy * span, d)
                        main.post { pending.remove(key); if (g == gen && d == dark) { tiles.put(key, bmp); invalidate() } }
                    }
                }
            }
        }
        // 3. hotspots
        val dens = resources.displayMetrics.density
        for (t in tags) {
            val r = RectF((t.x0 - ox) * z, (t.y0 - oy) * z, (t.x1 - ox) * z, (t.y1 - oy) * z)
            if (r.right < 0 || r.bottom < 0 || r.left > width || r.top > height) continue
            val col = markerColor(t.status, t.photos, coverage, dark)
            val dim = dimmed?.let { t.id !in it } == true
            if (coverage && t.status != "pending" && !dim) { fillPaint.color = Color.argb(70, Color.red(col), Color.green(col), Color.blue(col)); c.drawRect(r, fillPaint) }
            if (t.id in highlight) { fillPaint.color = (if (dark) DarkColor.lighten(Color.rgb(26, 166, 77)) else Color.rgb(26, 166, 77)) and 0xFFFFFF or (77 shl 24); c.drawRect(r, fillPaint) }
            if (t.id == selected) { fillPaint.color = Color.argb(71, Color.red(col), Color.green(col), Color.blue(col)); c.drawRect(r, fillPaint) }
            tagPaint.color = if (dim) Color.argb(46, Color.red(col), Color.green(col), Color.blue(col)) else col
            tagPaint.strokeWidth = (if (t.id == selected) 3f else 1.5f) * dens
            tagPaint.pathEffect = if (t.status == "pending") dash else null     // my proposed marks, until approved
            c.drawRect(r, tagPaint)
        }
        tagPaint.pathEffect = null
        // the open panel's valve symbol: dashed magenta, apart from every tag colour
        symbolBox?.takeIf { it.size == 4 }?.let { b ->
            val col = if (dark) DarkColor.lighten(SYMBOL) else SYMBOL
            val r = RectF((b[0] - ox) * z, (b[1] - oy) * z, (b[2] - ox) * z, (b[3] - oy) * z)
            r.inset(-3f * dens, -3f * dens)
            fillPaint.color = col and 0xFFFFFF or (41 shl 24); c.drawRect(r, fillPaint)
            tagPaint.color = col; tagPaint.strokeWidth = 2.5f * dens; tagPaint.pathEffect = dash
            c.drawRect(r, tagPaint)
            tagPaint.pathEffect = null
        }
        // off-page connectors: violet dashed circles, unlike the tags' rectangles; the one arrived at solid and bold
        if (links.isNotEmpty()) {
            val col = if (dark) DarkColor.lighten(LINK) else LINK
            for ((i, l) in links.withIndex()) {
                val cx = ((l.x0 + l.x1) / 2 - ox) * z; val cy = ((l.y0 + l.y1) / 2 - oy) * z
                val rad = max(6f * dens, max(l.x1 - l.x0, l.y1 - l.y0) / 2 * z + 3f * dens)
                if (cx + rad < 0 || cy + rad < 0 || cx - rad > width || cy - rad > height) continue
                val sel = i == linkSel
                fillPaint.color = col and 0xFFFFFF or ((if (sel) 77 else 31) shl 24); c.drawCircle(cx, cy, rad, fillPaint)
                tagPaint.color = col; tagPaint.strokeWidth = (if (sel) 3.5f else 2f) * dens
                tagPaint.pathEffect = if (sel) null else dash
                c.drawCircle(cx, cy, rad, tagPaint)
            }
            tagPaint.pathEffect = null
        }
        // the selection: a black and yellow ring (GNOME's), visible on any drawing and over any tag colour
        if (selection.isNotEmpty()) for (t in tags) if (t.id in selection) {
            val r = RectF((t.x0 - ox) * z, (t.y0 - oy) * z, (t.x1 - ox) * z, (t.y1 - oy) * z)
            if (r.right < 0 || r.bottom < 0 || r.left > width || r.top > height) continue
            r.inset(-3f * dens, -3f * dens)
            tagPaint.color = Color.BLACK; tagPaint.strokeWidth = 5f * dens; c.drawRect(r, tagPaint)
            tagPaint.color = Color.rgb(255, 214, 0); tagPaint.strokeWidth = 2.5f * dens; c.drawRect(r, tagPaint)
        }
        box?.let { m ->
            tagPaint.color = Color.rgb(255, 214, 0); tagPaint.strokeWidth = 2f * dens; tagPaint.pathEffect = dash
            c.drawRect((m.left - ox) * z, (m.top - oy) * z, (m.right - ox) * z, (m.bottom - oy) * z, tagPaint)
            tagPaint.pathEffect = null
        }
        mark?.let { m ->
            tagPaint.color = markerColor("pending", "", false, dark); tagPaint.strokeWidth = 2f * dens; tagPaint.pathEffect = dash
            c.drawRect((m.left - ox) * z, (m.top - oy) * z, (m.right - ox) * z, (m.bottom - oy) * z, tagPaint)
            tagPaint.pathEffect = null
        }
    }

    private val dash = DashPathEffect(floatArrayOf(12f, 8f), 0f)

    /** the drawing under a box (points) as a bitmap about `maxW` px wide: the crop in the mark dialog */
    fun crop(x0: Float, y0: Float, x1: Float, y1: Float, maxW: Int): Bitmap? {
        val s = sheet ?: return null
        val pad = 6f
        val zz = min(maxW / (x1 - x0 + 2 * pad), 400f / (y1 - y0 + 2 * pad))
        val w = ceil((x1 - x0 + 2 * pad) * zz).toInt(); val h = ceil((y1 - y0 + 2 * pad) * zz).toInt()
        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(out)
        val t = renderTile(s, zz, x0 - pad, y0 - pad, dark)  // tile px square: enough for a tag-sized crop
        c.drawBitmap(t, 0f, 0f, null)
        return out
    }

    /** one tile: the region at (x0, y0) pt, `tile` px square at tz px/pt, on white (PATHSTORE.md style rules); dark:
     *  every stroke, fill and image pixel through DarkColor, on the dark paper */
    private fun renderTile(s: Sheet, tz: Float, x0: Float, y0: Float, dark: Boolean): Bitmap {
        val bmp = Bitmap.createBitmap(tile, tile, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        c.drawColor(if (dark) PAPER_DARK else Color.WHITE)
        fun col(r: Int, g: Int, b: Int) = if (dark) DarkColor.rgb(r, g, b) else Color.rgb(r, g, b)
        val k = tz / 64f                         // px per quantum
        c.scale(k, k); c.translate(-x0 * 64f, -y0 * 64f)
        val qx0 = floor(x0 * 64).toInt(); val qy0 = floor(y0 * 64).toInt()
        val qx1 = ceil((x0 + tile / tz) * 64).toInt(); val qy1 = ceil((y0 + tile / tz) * 64).toInt()
        val px1 = 1f / k
        val b = s.buf
        val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeMiter = 10f }
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
        val path = Path()
        val imgs = s.images.filter { it[3] >= qx0 && it[1] <= qx1 && it[4] >= qy0 && it[2] <= qy1 }.sortedBy { it[0] }
        var ii = 0
        fun drawImage(im: IntArray) {
            val data = ByteArray(im[6]); System.arraycopy(b.array(), im[5], data, 0, im[6])   // absolute: tiles render in parallel
            Jxl.bitmap(data, if (dark) DarkColor::rgbaBytes else null)?.let { c.drawBitmap(it, null, RectF(im[1].toFloat(), im[2].toFloat(), im[3].toFloat(), im[4].toFloat()), bmpPaint) }
        }
        for (i in s.visible(qx0, qy0, qx1, qy1)) {
            while (ii < imgs.size && imgs[ii][0] <= i) drawImage(imgs[ii++])
            val pa = s.pathsAt + i * 32
            if (b.getInt(pa + 12) < qx0 || b.getInt(pa + 4) > qx1 || b.getInt(pa + 16) < qy0 || b.getInt(pa + 8) > qy1) continue
            val st = s.stylesAt + b.getInt(pa) * 16
            val kind = b.get(st).toInt(); val cmdStart = b.getInt(pa + 20); val cmdCount = b.getInt(pa + 24); var pt = b.getInt(pa + 28)
            path.rewind()
            var mx = 0f; var my = 0f
            fun x(n: Int) = b.getInt(s.xyAt + (pt * 2 + n) * 4).toFloat()
            for (j in 0 until cmdCount) {
                when (b.get(s.opsAt + cmdStart + j).toInt()) {
                    0 -> { mx = x(0); my = x(1); path.moveTo(mx, my); pt += 1 }
                    1 -> { path.lineTo(x(0), x(1)); pt += 1 }
                    2 -> { path.cubicTo(x(0), x(1), x(2), x(3), x(4), x(5)); pt += 3 }
                    else -> { path.close(); path.moveTo(mx, my) }
                }
            }
            if (kind and 2 != 0) {
                path.fillType = if (kind and 4 != 0) Path.FillType.EVEN_ODD else Path.FillType.WINDING
                fill.color = col(b.get(st + 11).toInt() and 255, b.get(st + 12).toInt() and 255, b.get(st + 13).toInt() and 255)
                c.drawPath(path, fill)
            }
            if (kind and 1 != 0) {
                val wq = b.getInt(st + 4).toFloat()
                stroke.strokeWidth = if (kind and 8 != 0) px1 else max(wq, px1)
                stroke.strokeCap = when (b.get(st + 1).toInt()) { 1 -> Paint.Cap.ROUND; 2 -> Paint.Cap.SQUARE; else -> Paint.Cap.BUTT }
                stroke.strokeJoin = when (b.get(st + 2).toInt()) { 1 -> Paint.Join.ROUND; 2 -> Paint.Join.BEVEL; else -> Paint.Join.MITER }
                stroke.color = col(b.get(st + 8).toInt() and 255, b.get(st + 9).toInt() and 255, b.get(st + 10).toInt() and 255)
                c.drawPath(path, stroke)
            }
        }
        while (ii < imgs.size) drawImage(imgs[ii++])
        return bmp
    }
}

/** the dark paper: white through DarkColor (#121212) */
val PAPER_DARK = DarkColor.rgb(255, 255, 255)

/** how a tag was read: verified green, to review amber, my proposed mark purple, read automatically blue */
fun tagColor(status: String): Int = when (status) {
    "verified" -> Color.rgb(38, 153, 64); "review" -> Color.rgb(242, 140, 0); "pending" -> Color.rgb(140, 51, 191); else -> Color.rgb(26, 102, 230)
}

/** a tag's outline colour: by its photos (coverage view) or by how it was read; on dark drawings the same hues raised
 *  toward white, each ≥ 3:1 against the dark paper (DebugDarkReceiver checks it) */
fun markerColor(status: String, photos: String, coverage: Boolean, dark: Boolean): Int {
    val c = if (coverage && status != "pending") coverColor(photos) else tagColor(status)
    return if (dark) DarkColor.lighten(c) else c
}

/** the photo coverage colours, the same on every client: both green, the equipment only amber, the tag plate only
 *  blue, none red */
fun coverColor(photos: String): Int = when (photos) {
    "both" -> Color.rgb(46, 160, 67); "equipment" -> Color.rgb(230, 150, 0); "plate" -> Color.rgb(30, 120, 230); else -> Color.rgb(220, 40, 40)
}
fun coverWords(photos: String) = when (photos) {
    "both" -> "equipment and tag plate photos"; "equipment" -> "equipment photo only"; "plate" -> "tag plate photo only"; else -> "no photos"
}
