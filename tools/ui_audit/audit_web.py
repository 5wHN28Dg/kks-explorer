"""UI/UX audit evidence for the web client (tools/ui_audit; repository root from $KKS_REPO or this file's place) (docs/UI-UX-POLICY.md §3.3, web row), synthetic data only.
  .venv/bin/python audit_web.py OUTDIR [engines...]
Starts the Nim server ($KKS_SERVER) with the sample sheet ($KKS_IMPORTER), makes synthetic items (20 sign-ups, 20 marked
tags waiting for approval, 20 review-queue tags, an Arabic note), then per engine and layout takes screenshots, the ARIA
snapshot and measure.js's sizes/colours of each screen, plus keyboard, Escape, copy, offline and long-task probes."""
import os, sys, json, time, urllib.parse, traceback
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from web_setup import *  # noqa: E402,F401,F403  (starts the server and makes the synthetic data)

LAYOUTS = {'phone': {'width': 412, 'height': 915}, 'desk': {'width': 1280, 'height': 800},
           'zoom200': {'width': 640, 'height': 400}, 'w320': {'width': 320, 'height': 640}}

def wait_index(page):
    page.wait_for_function("() => typeof TAGS !== 'undefined' && TAGS.length > 0", timeout=30000)
    page.wait_for_function("() => { const i = document.getElementById('sheetimg'); return i && i.complete && i.naturalWidth > 0 }", timeout=30000)
    page.wait_for_timeout(500)

def st_index(p): p.goto(BASE + '/'); wait_index(p)
def st_panel(p): p.goto(BASE + '/?kks=' + KKS); wait_index(p); p.wait_for_selector('#panel.open', timeout=15000); p.wait_for_timeout(400)
def st_review(p): st_index(p); p.click('#revBtn'); p.wait_for_selector('#revDrawer.open'); p.wait_for_timeout(300)
def st_systems(p): st_index(p); p.click('#sysBtn'); p.wait_for_selector('#sysDrawer.open'); p.wait_for_timeout(300)
def st_coverage(p): st_index(p); p.click('#covBtn'); p.wait_for_selector('#covDrawer.open'); p.wait_for_timeout(300)
def st_pick(p): st_index(p); p.click('#zpick'); p.wait_for_selector('#pickbar.open'); p.wait_for_timeout(300)
def admin(tab):
    def f(p): p.goto(BASE + '/admin.html#' + tab); p.wait_for_selector('#main > *', timeout=15000); p.wait_for_timeout(1200)
    return f
def st_learning(p): p.goto(BASE + '/learning.html'); p.wait_for_selector('a.course', timeout=15000); p.wait_for_timeout(300)
def st_course(p): p.goto(BASE + '/course.html?c=inc'); p.wait_for_function("() => !document.querySelector('#main .stat') || document.querySelectorAll('#main *').length > 5", timeout=20000); p.wait_for_timeout(800)
def st_course_q(p):
    st_course(p)
    # a page with a question: the first rail entry that holds one
    p.evaluate("""() => { const a = [...document.querySelectorAll('#rail a, #rail button')]; if (a[2]) a[2].click() }"""); p.wait_for_timeout(800)

STATES = [('index', st_index), ('panel', st_panel), ('review', st_review), ('systems', st_systems), ('coverage', st_coverage),
          ('pick', st_pick), ('a-queue', admin('queue')), ('a-users', admin('users')), ('a-devices', admin('devices')),
          ('a-account', admin('account')), ('a-mine', admin('mine')), ('learning', st_learning), ('course', st_course), ('course2', st_course_q)]

def snapshot(page, eng, lay, scheme, name, full=False):
    base = f'{eng}-{lay}-{scheme}-{name}'
    try: page.screenshot(path=os.path.join(OUT, 'shots', base + '.png'), full_page=full)
    except Exception as e: log('shot fail', base, e)
    rec = {'engine': eng, 'layout': lay, 'scheme': scheme, 'state': name}
    try: rec['m'] = page.evaluate(MEASURE)
    except Exception as e: rec['err'] = str(e)
    try: rec['aria'] = page.locator('body').aria_snapshot()
    except Exception as e: rec['aria_err'] = str(e)
    with open(os.path.join(OUT, 'data', base + '.json'), 'w') as f: json.dump(rec, f)

def context(browser, lay, scheme, login=True, reduced=False, **kw):
    ctx = browser.new_context(viewport=LAYOUTS[lay], color_scheme=scheme, reduced_motion='reduce' if reduced else 'no-preference', **kw)
    if login:
        r = ctx.request.post(BASE + '/api/login', data={'username': 'boss', 'password': PW}, headers={'Origin': BASE}); assert r.ok, r.text()
    return ctx

PR = {}
def probes(browser, eng):
    """keyboard walk, Escape, copy, long tasks, errors: desk layout, dark"""
    R = PR[eng] = {}
    perms = {'permissions': ['clipboard-read', 'clipboard-write']} if eng == 'chromium' else {}
    ctx = context(browser, 'desk', 'dark', **perms); page = ctx.new_page()
    page.on('dialog', lambda dl: (R.setdefault('dialogs', []).append([dl.type, dl.message[:120]]), dl.dismiss()))
    # long tasks during load and opening the panel (Chromium only exposes them)
    if eng == 'chromium':
        page.add_init_script("window.__lt=[];try{new PerformanceObserver(l=>l.getEntries().forEach(e=>__lt.push([Math.round(e.startTime),Math.round(e.duration)]))).observe({type:'longtask',buffered:true})}catch(e){}")
    st_index(page)
    # keyboard walk from the top
    page.evaluate("document.activeElement && document.activeElement.blur()"); page.mouse.click(5, 300) if False else None
    walk = []
    for i in range(70):
        page.keyboard.press('Tab')
        info = page.evaluate("""() => { const e = document.activeElement; if (!e || e === document.body) return null;
          const r = e.getBoundingClientRect(), s = getComputedStyle(e);
          const cx = r.left + r.width / 2, cy = r.top + r.height / 2, top = document.elementFromPoint(Math.min(Math.max(cx,0),innerWidth-1), Math.min(Math.max(cy,0),innerHeight-1));
          return {tag: e.localName, id: e.id, name: (e.getAttribute('aria-label') || e.title || e.textContent || e.placeholder || '').trim().slice(0, 40),
            x: Math.round(r.left), y: Math.round(r.top), w: Math.round(r.width), h: Math.round(r.height),
            outline: s.outlineStyle + ' ' + s.outlineWidth + ' ' + s.outlineColor, shadow: s.boxShadow,
            covered: !!top && top !== e && !e.contains(top) && !top.contains(e), inView: r.bottom > 0 && r.top < innerHeight && r.right > 0 && r.left < innerWidth} }""")
        walk.append(info)
    R['walk_index'] = walk
    # Enter on the search: the panel; then Escape
    box = page.locator('#q'); box.focus(); page.keyboard.type('LAB70AA500'); page.wait_for_selector('#results [role=option]'); page.keyboard.press('Enter')
    page.wait_for_selector('#panel.open'); page.wait_for_timeout(300)
    R['panel_focus'] = page.evaluate("document.activeElement && document.activeElement.textContent.slice(0,40)")
    if eng == 'chromium':
        R['longtasks'] = page.evaluate("window.__lt")
    # R1: close button before/after scrolling to the end of the panel
    cb = lambda: page.evaluate("(() => { const b = document.querySelector('#panel [aria-label=\"Close the panel\"]'); const r = b.getBoundingClientRect(); return [Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height)] })()")
    R['close_before'] = cb(); page.evaluate("document.getElementById('panel').scrollTop = 1e6"); page.wait_for_timeout(200); R['close_after'] = cb()
    R['panel_scroll'] = page.evaluate("[document.getElementById('panel').scrollHeight, document.getElementById('panel').clientHeight]")
    page.screenshot(path=os.path.join(OUT, 'shots', f'{eng}-desk-dark-panel-scrolled.png'))
    # C1/C2: select the code heading's text and copy it
    if eng == 'chromium':
        page.evaluate("document.getElementById('panel').scrollTop = 0")
        page.evaluate("""() => { const e = document.querySelector('#panel .kks'); const r = document.createRange(); r.selectNodeContents(e); const s = getSelection(); s.removeAllRanges(); s.addRange(r) }""")
        page.keyboard.press('Control+c'); page.wait_for_timeout(200)
        try: R['copied'] = page.evaluate("navigator.clipboard.readText()")
        except Exception as e: R['copied'] = 'ERR ' + str(e)
        R['copy_toast'] = page.evaluate("getComputedStyle(document.getElementById('toast')).display + ' ' + document.getElementById('toast').textContent")
    # the search's handling of case and spaces (G1)
    for q in ('11lab70aa500', '11 LAB70 AA500', '11 lab70 aa500'):
        box.fill(''); box.fill(q); page.wait_for_timeout(400)
        R['search ' + q] = page.evaluate("[...document.querySelectorAll('#results [role=option]')].map(e => e.textContent.slice(0, 30)).slice(0, 3)")
    page.keyboard.press('Escape')
    # Escape on the panel (focus inside it)
    page.evaluate("document.querySelector('#panel .kks') && document.querySelector('#panel .kks').focus()")
    page.keyboard.press('Escape'); page.wait_for_timeout(200)
    R['esc_panel_open_after'] = page.evaluate("document.getElementById('panel').classList.contains('open')")
    for btn, drw in (('#sysBtn', '#sysDrawer'), ('#revBtn', '#revDrawer'), ('#procBtn', '#procDrawer'), ('#covBtn', '#covDrawer')):
        st_index(page); page.click(btn); page.wait_for_timeout(300); page.keyboard.press('Escape'); page.wait_for_timeout(200)
        R['esc ' + drw + ' open after'] = page.evaluate(f"document.querySelector('{drw}').classList.contains('open')")
        R['focus after open ' + drw] = page.evaluate("document.activeElement && (document.activeElement.id || document.activeElement.localName)")
    # the confirmation of deleting the hand-added tag / a photo: what kind of dialog
    st_panel(page)
    rm = page.get_by_role('button', name='Remove this tag')
    if rm.count():
        rm.first.click(); page.wait_for_timeout(300)
    R['dialogs_after_remove'] = list(R.get('dialogs', []))
    # errors: a wrong password on the sign-in screen; the server's 4xx text shown raw?
    c2 = context(browser, 'desk', 'dark', login=False); p2 = c2.new_page(); p2.goto(BASE + '/'); p2.wait_for_selector('#kov input[name=username]', timeout=15000)
    p2.screenshot(path=os.path.join(OUT, 'shots', f'{eng}-desk-dark-signin.png'))
    snapshot(p2, eng, 'desk', 'dark', 'signin')
    p2.fill('#kov input[name=username]', 'boss'); p2.fill('#kov input[name=password]', 'wrong password'); p2.keyboard.press('Enter'); p2.wait_for_timeout(800)
    R['err_wrong_pw'] = p2.text_content('#kov .err')
    R['err_wrong_pw_kept'] = p2.input_value('#kov input[name=username]')
    p2.set_viewport_size(LAYOUTS['phone']); p2.wait_for_timeout(200); snapshot(p2, eng, 'phone', 'dark', 'signin-err')
    c2.close()
    # an add-user form error (username taken) in admin: what does it say
    page.goto(BASE + '/admin.html#users'); page.wait_for_selector('#main form', timeout=15000); page.wait_for_timeout(500)
    f = page.locator('#main form.inline').last
    try:
        page.fill('input[name=full_name]', 'Tom Again'); page.fill('input[name=position]', 'Tech'); page.fill('input[name=username]', 'tom')
        page.get_by_role('button', name='Create and get link').click(); page.wait_for_timeout(800)
        R['err_user_taken_toast'] = page.text_content('#toast'); R['err_user_taken_kept'] = page.input_value('input[name=username]')
    except Exception as e: R['err_user_taken'] = 'ERR ' + str(e)
    # admin keyboard walk
    page.goto(BASE + '/admin.html#queue'); page.wait_for_selector('#main .card', timeout=15000); page.wait_for_timeout(500)
    aw = []
    for i in range(40):
        page.keyboard.press('Tab')
        aw.append(page.evaluate("""() => { const e = document.activeElement; if (!e || e === document.body) return null; const s = getComputedStyle(e), r = e.getBoundingClientRect();
          return {tag: e.localName, name: (e.getAttribute('aria-label') || e.textContent || e.placeholder || '').trim().slice(0, 30), outline: s.outlineStyle + ' ' + s.outlineWidth + ' ' + s.outlineColor, shadow: s.boxShadow, y: Math.round(r.top)} }"""))
    R['walk_admin'] = aw
    R['queue_buttons'] = page.evaluate("[...document.querySelectorAll('#main button')].map(b => b.textContent.trim()).reduce((m, t) => (m[t] = (m[t] || 0) + 1, m), {})")
    R['queue_checkboxes'] = page.locator('#main input[type=checkbox]').count()
    page.goto(BASE + '/admin.html#users'); page.wait_for_selector('#signups', timeout=15000)
    R['signup_buttons'] = page.evaluate("[...document.querySelectorAll('#signups button')].map(b => b.textContent.trim()).reduce((m, t) => (m[t] = (m[t] || 0) + 1, m), {})")
    R['signup_checkboxes'] = page.locator('#signups input[type=checkbox]').count()
    # D2: what Reject on a sign-up does (dialog type)
    n0 = len(R.get('dialogs', []))
    page.locator('#signups').get_by_role('button', name='Reject').first.click(); page.wait_for_timeout(300)
    R['reject_signup_dialog'] = R.get('dialogs', [])[n0:]
    # review drawer on the drawings page: bulk?
    st_review(page)
    R['review_items'] = page.locator('#revBody .revitem').count()
    R['review_buttons'] = page.evaluate("[...document.querySelectorAll('#revBody button, #revBody input')].map(b => b.textContent.trim() || b.type).reduce((m, t) => (m[t] = (m[t] || 0) + 1, m), {})")
    # reduced motion: any running CSS transition or animation on the drawings page
    R['animations'] = page.evaluate("document.getAnimations ? document.getAnimations().length : -1")
    # offline (not WebKit: its offline emulation fails navigations)
    if eng != 'webkit':
        st_panel(page); ctx.set_offline(True); page.wait_for_timeout(500)
        try:
            page.get_by_role('button', name='Edit Notes').click(); page.fill('#f_notes', 'offline synthetic note'); page.get_by_role('button', name='Save').click()
            page.wait_for_timeout(2500)
        except Exception as e: R['offline_edit'] = 'ERR ' + str(e)
        R['offline_sync'] = page.text_content('#syncStatus'); R['offline_toast'] = page.text_content('#toast')
        page.screenshot(path=os.path.join(OUT, 'shots', f'{eng}-desk-dark-offline-panel.png'))
        snapshot(page, eng, 'desk', 'dark', 'offline-panel')
        try:
            page.goto(BASE + '/admin.html#queue', timeout=8000); page.wait_for_timeout(1500)
            R['offline_admin'] = page.text_content('body')[:300]
        except Exception as e: R['offline_admin'] = 'ERR ' + str(e)[:200]
        page.screenshot(path=os.path.join(OUT, 'shots', f'{eng}-desk-dark-offline-admin.png'))
        ctx.set_offline(False)
    ctx.close()
    with open(os.path.join(OUT, 'data', f'{eng}-probes.json'), 'w') as f: json.dump(R, f, indent=1, ensure_ascii=False)

os.makedirs(os.path.join(OUT, 'shots'), exist_ok=True); os.makedirs(os.path.join(OUT, 'data'), exist_ok=True)
try:
    with sync_playwright() as pw:
        for eng in ENGINES:
            browser = getattr(pw, eng).launch()
            for lay, scheme in (() if os.environ.get('PROBES_ONLY') else (('phone', 'dark'), ('phone', 'light'), ('desk', 'dark'), ('desk', 'light'), ('zoom200', 'dark'), ('w320', 'dark'))):
                ctx = context(browser, lay, scheme); page = ctx.new_page()
                page.on('dialog', lambda dl: dl.dismiss())
                for name, fn in STATES:
                    if lay in ('zoom200', 'w320') and name in ('pick', 'coverage', 'a-mine'): continue
                    if scheme == 'light' and name not in ('index', 'panel', 'a-queue', 'learning', 'course', 'course2'): continue
                    try:
                        fn(page); snapshot(page, eng, lay, scheme, name)
                        if name == 'panel' and lay in ('phone', 'w320'):
                            page.evaluate("document.getElementById('panel').scrollTop = 1e6"); page.wait_for_timeout(200)
                            snapshot(page, eng, lay, scheme, 'panel-end')
                    except Exception as e:
                        log('state fail', eng, lay, scheme, name, str(e)[:300])
                ctx.close(); log('done', eng, lay, scheme)
            try: probes(browser, eng)
            except Exception:
                log('probes fail', eng, traceback.format_exc()[-1500:])
                with open(os.path.join(OUT, 'data', f'{eng}-probes.json'), 'w') as f: json.dump(PR.get(eng, {}), f, indent=1, ensure_ascii=False)
            browser.close()
finally:
    server.terminate(); server.wait(10); shutil.rmtree(d, ignore_errors=True); log('server stopped')
