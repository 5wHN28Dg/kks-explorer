"""Pass 2 probes (web): floor filter / photo colouring vs the selected tag, focus ring on tags, toast under a modal,
focus under sticky headers, landscape zoom column, course figure motion under reduced motion, long sheet name.
  KKS_SERVER=... KKS_IMPORTER=... .venv/bin/python web_probe3.py OUTDIR   (same environment as audit_web.py)"""
import os, sys, json
P1 = os.path.dirname(os.path.abspath(__file__))   # audit_web.py lives beside this file
sys.argv = [sys.argv[0], sys.argv[1]]
sys.path.insert(0, P1)
from web_setup import *  # noqa: E402,F401,F403  (starts the server and makes the synthetic data)
OUT = sys.argv[1]; os.makedirs(os.path.join(OUT, 'shots'), exist_ok=True)
R = {}
def login(ctx): assert ctx.request.post(BASE + '/api/login', data={'username': 'boss', 'password': PW}, headers={'Origin': BASE}).ok
def wait_index(page):
    page.wait_for_function("() => typeof TAGS !== 'undefined' && TAGS.length > 0", timeout=30000)
    page.wait_for_function("() => { const i = document.getElementById('sheetimg'); return i && i.complete && i.naturalWidth > 0 }", timeout=30000)
    page.wait_for_timeout(500)
def shot(page, name, **kw): page.screenshot(path=os.path.join(OUT, 'shots', name + '.png'), **kw)
SELQ = "(() => { const e = document.querySelector('#layer .hs.sel'); if (!e) return null; const s = getComputedStyle(e); return {cls: e.className, outline: s.outlineColor + ' ' + s.outlineStyle + ' ' + s.outlineWidth, bg: s.backgroundColor} })()"
OTHER = "(() => { const e = [...document.querySelectorAll('#layer .hs.floor:not(.sel)')][0]; if (!e) return null; const s = getComputedStyle(e); return {cls: e.className, outline: s.outlineColor + ' ' + s.outlineStyle + ' ' + s.outlineWidth, bg: s.backgroundColor} })()"
try:
    # a second sheet with a long (80-character) name
    with open(os.path.join(REPO, 'importer', 'tests', 'vectors', 'kkp-sample.pdf'), 'rb') as f: pdf = f.read()
    import urllib.parse, time
    LONG = 'Synthetic feed water and condensate piping, second section, revision B (sheet 3)'[:80]
    r = boss.req('POST', '/api/sheets/import?id=longname&name=' + urllib.parse.quote(LONG), raw=pdf, ctype='application/pdf')
    for _ in range(600):
        job = boss.req('GET', '/api/sheets/job')['job']
        if job['state'] != 'running': break
        time.sleep(0.2)
    R['long_import'] = job['state']
    # another tag on floor 2 so the floor filter has two
    with sync_playwright() as pw:
        for eng in ['chromium', 'webkit', 'firefox']:
            E = R[eng] = {}
            b = getattr(pw, eng).launch()
            try:
                ctx = b.new_context(viewport={'width': 1280, 'height': 800}, color_scheme='dark'); login(ctx); page = ctx.new_page()
                page.goto(BASE + '/?kks=' + KKS); wait_index(page); page.wait_for_selector('#panel.open'); page.wait_for_timeout(400)
                E['sel_plain'] = page.evaluate(SELQ)
                page.select_option('#floorSel', '2'); page.wait_for_timeout(500)
                E['sel_floor'] = page.evaluate(SELQ); E['floor_other'] = page.evaluate(OTHER)
                E['floor_classes'] = page.evaluate("[...document.querySelectorAll('#layer .hs')].map(e=>e.className).filter(c=>/floor|sel/.test(c))")
                bb = page.locator('#layer .hs.sel').bounding_box()
                if eng == 'chromium' and bb: shot(page, 'p3-floor-sel', clip={'x': max(0, bb['x'] - 60), 'y': max(0, bb['y'] - 60), 'width': bb['width'] + 120, 'height': bb['height'] + 120})
                page.select_option('#floorSel', ''); page.wait_for_timeout(300)
                page.evaluate("setCover(true)"); page.wait_for_timeout(400)
                E['sel_cover'] = page.evaluate(SELQ)
                E['cover_other'] = page.evaluate("(() => { const e = [...document.querySelectorAll('#layer .hs:not(.sel):not(.review):not(.pendmark)')][0]; if (!e) return null; const s = getComputedStyle(e); return {cls: e.className, outline: s.outlineColor + ' ' + s.outlineStyle + ' ' + s.outlineWidth} })()")
                E['review_cover'] = page.evaluate("(() => { const e = document.querySelector('#layer .hs.review'); if (!e) return null; const s = getComputedStyle(e); return {cls: e.className, outline: s.outlineColor + ' ' + s.outlineStyle + ' ' + s.outlineWidth} })()")
                bb = page.locator('#layer .hs.sel').bounding_box()
                if eng == 'chromium' and bb: shot(page, 'p3-cover-sel', clip={'x': max(0, bb['x'] - 60), 'y': max(0, bb['y'] - 60), 'width': bb['width'] + 120, 'height': bb['height'] + 120})
                page.evaluate("setCover(false)"); page.wait_for_timeout(300)
                # --- focus ring on a tag in select mode (keyboard)
                page.get_by_role('button', name='Close the panel').click(); page.wait_for_timeout(300)
                page.click('#zpick'); page.wait_for_selector('#pickbar.open'); page.wait_for_timeout(300)
                page.locator('#layer .hs[aria-label="%s"]' % KKS).focus(); page.keyboard.press('Shift+Tab'); page.keyboard.press('Tab'); page.wait_for_timeout(200)
                E['tag_focus'] = page.evaluate("(() => { const a = document.activeElement; const s = getComputedStyle(a); return {lab: a.getAttribute('aria-label'), cls: a.className, outline: s.outlineColor + ' ' + s.outlineStyle + ' ' + s.outlineWidth + ' off ' + s.outlineOffset, darkdwg: document.body.classList.contains('darkdwg')} })()")
                bb = page.evaluate("(() => { const r = document.activeElement.getBoundingClientRect(); return {x: r.x, y: r.y, width: r.width, height: r.height} })()")
                shot(page, f'p3-{eng}-tag-focus', clip={'x': max(0, bb['x'] - 30), 'y': max(0, bb['y'] - 30), 'width': bb['width'] + 60, 'height': bb['height'] + 60})
                # --- a validation message from a modal dialog
                page.keyboard.press('Space'); page.wait_for_timeout(200)
                page.click('#pickPlace'); page.wait_for_selector('dialog[open]')
                page.locator('dialog[open] [data-send]').click(); page.wait_for_timeout(250)
                E['modal_toast'] = page.evaluate("(() => { const t = document.getElementById('toast'); const d = document.querySelector('dialog[open]'); const r = t.getBoundingClientRect(); const x = r.x + r.width / 2, y = r.y + r.height / 2; const top = document.elementFromPoint(x, y); return {text: t.textContent, shown: t.style.display, top_is_toast: !!top && (top === t || t.contains(top)), top: top && (top.localName + '.' + top.className), focus: document.activeElement.localName + ' ' + (document.activeElement.id || document.activeElement.textContent.slice(0, 20))} })()")
                shot(page, f'p3-{eng}-modal-toast')
                page.wait_for_timeout(2300)
                E['modal_toast_after_2_5s'] = page.evaluate("document.getElementById('toast').style.display")
                page.keyboard.press('Escape'); ctx.close()
                # --- focus under the panel's sticky heading (Shift+Tab back up the panel), desktop and phone
                for lay, vp in [('desk', {'width': 1280, 'height': 800}), ('phone', {'width': 412, 'height': 915})]:
                    ctx = b.new_context(viewport=vp, color_scheme='dark'); login(ctx); page = ctx.new_page()
                    page.goto(BASE + '/?kks=' + KKS); wait_index(page); page.wait_for_selector('#panel.open'); page.wait_for_timeout(400)
                    page.evaluate("(() => { const p = document.getElementById('panel'); p.scrollTop = p.scrollHeight; const f = [...p.querySelectorAll('button,input,textarea,select,a[href],[tabindex]:not([tabindex=\"-1\"])')].filter(e => e.offsetParent); f[f.length - 1].focus() })()")
                    hidden = []
                    for i in range(60):
                        page.keyboard.press('Shift+Tab'); page.wait_for_timeout(40)
                        st = page.evaluate("""(() => { const a = document.activeElement, p = document.getElementById('panel'); if (!p.contains(a)) return {out: true};
                          const h = p.querySelector('.phead').getBoundingClientRect(), r = a.getBoundingClientRect(), pr = p.getBoundingClientRect();
                          const visTop = Math.max(r.top, h.bottom, pr.top), visBot = Math.min(r.bottom, pr.bottom);
                          return {name: (a.getAttribute('aria-label') || a.id || a.textContent || '').slice(0, 30), top: r.top, bottom: r.bottom, head_bottom: h.bottom, under_head: a.closest('.phead') ? false : visBot - visTop < 1, partly: !a.closest('.phead') && r.top < h.bottom - 1} })()""")
                        if st.get('out'): break
                        if st['under_head'] or st['partly']: hidden.append(st)
                    E[f'focus_under_phead_{lay}'] = {'count': len(hidden), 'fully': sum(1 for x in hidden if x['under_head']), 'examples': hidden[:4]}
                    if hidden and eng == 'chromium' and lay == 'desk':
                        # reproduce the first hidden one for a screenshot
                        pass
                    ctx.close()
                # --- admin: Shift+Tab under the sticky header (Approvals, phone)
                ctx = b.new_context(viewport={'width': 412, 'height': 915}, color_scheme='dark'); login(ctx); page = ctx.new_page()
                page.goto(BASE + '/admin.html#queue'); page.wait_for_selector('#main .card', timeout=15000); page.wait_for_timeout(1200)
                page.evaluate("(() => { window.scrollTo(0, document.body.scrollHeight); const f = [...document.querySelectorAll('#main button,#main input,#main a[href]')].filter(e => e.offsetParent); f[f.length - 1].focus() })()")
                hid = 0; tot = 0; ex = []
                for i in range(80):
                    page.keyboard.press('Shift+Tab'); page.wait_for_timeout(30)
                    st = page.evaluate("""(() => { const a = document.activeElement; if (a.closest('header') || a === document.body) return {out: true};
                       const h = document.querySelector('header').getBoundingClientRect(), r = a.getBoundingClientRect();
                       return {name: (a.textContent || a.placeholder || '').slice(0, 25), top: r.top, bottom: r.bottom, head_bottom: h.bottom, fully: r.bottom <= h.bottom + 1, partly: r.top < h.bottom - 1} })()""")
                    if st.get('out'): break
                    tot += 1
                    if st['partly']: hid += 1; ex.append(st)
                E['admin_focus_under_header'] = {'steps': tot, 'hidden_or_partly': hid, 'fully': sum(1 for x in ex if x['fully']), 'examples': ex[:3]}
                if ex and eng == 'chromium':
                    shot(page, 'p3-admin-focus-under-header', clip={'x': 0, 'y': 0, 'width': 412, 'height': 260})
                ctx.close()
                # --- landscape phone: the zoom column vs the header and the panel
                ctx = b.new_context(viewport={'width': 915, 'height': 412}, color_scheme='dark', has_touch=eng != 'firefox'); login(ctx); page = ctx.new_page()
                page.goto(BASE + '/'); wait_index(page)
                E['landscape'] = page.evaluate("""(() => { const h = document.querySelector('header').getBoundingClientRect();
                   return {header_bottom: h.bottom, zoom: [...document.querySelectorAll('.zoom button')].map(b => { const r = b.getBoundingClientRect(); const t = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
                     return [b.title, Math.round(r.top), Math.round(r.bottom), t === b || b.contains(t)] })} })()""")
                ctx.close()
                # --- long sheet name at 412 px and at 320 px
                for w in (412, 320):
                    ctx = b.new_context(viewport={'width': w, 'height': 800}, color_scheme='dark'); login(ctx); page = ctx.new_page()
                    page.goto(BASE + '/'); wait_index(page)
                    page.select_option('#sheetSel', 'longname'); page.wait_for_timeout(800)
                    E[f'longname_{w}'] = page.evaluate("""(() => { const s = document.getElementById('sheetSel'), r = s.getBoundingClientRect();
                      return {sel_w: r.width, sel_right: r.right, vw: innerWidth, doc_sw: document.documentElement.scrollWidth, header_sw: document.querySelector('header').scrollWidth, text: s.selectedOptions[0]?.textContent} })()""")
                    if eng == 'chromium': shot(page, f'p3-longname-{w}', clip={'x': 0, 'y': 0, 'width': w, 'height': 260})
                    ctx.close()
                # --- course figure under reduced motion: does a toggle start a loop?
                ctx = b.new_context(viewport={'width': 1280, 'height': 800}, color_scheme='light', reduced_motion='reduce'); login(ctx); page = ctx.new_page()
                found = None
                for c in ('fnd', 'hrsg', 'ppt'):
                    page.goto(BASE + '/course.html?c=' + c); page.wait_for_timeout(1500)
                    n = page.evaluate("document.querySelectorAll('#rail a, #rail button').length")
                    for i in range(n):
                        page.evaluate("i => { const a = [...document.querySelectorAll('#rail a, #rail button')]; a[i] && a[i].click() }", i); page.wait_for_timeout(400)
                        if page.locator('figure.vis input[type=checkbox], figure.vis input[type=radio]').count():
                            found = (c, i); break
                    if found: break
                E['course_toggle_page'] = found
                if found:
                    fig = page.locator('figure.vis:has(input[type=checkbox]), figure.vis:has(input[type=radio])').first
                    fig.scroll_into_view_if_needed(); page.wait_for_timeout(300)
                    cv = "(f => f.querySelector('canvas').toDataURL())"
                    a0 = fig.evaluate(cv); page.wait_for_timeout(800); a1 = fig.evaluate(cv)
                    E['course_before_toggle'] = {'canvas_changes': a0 != a1, 'play_btn': fig.locator('.vis-btn').first.text_content() if fig.locator('.vis-btn').count() else None}
                    inp = fig.locator('input[type=checkbox], input[type=radio]')
                    (inp.nth(1) if inp.count() > 1 and fig.locator('input[type=radio]').count() else inp.first).click(); page.wait_for_timeout(3000)
                    b0 = fig.evaluate(cv); page.wait_for_timeout(1000); b1 = fig.evaluate(cv); page.wait_for_timeout(1000); b2 = fig.evaluate(cv)
                    E['course_after_toggle'] = {'changes_3to4s': b0 != b1, 'changes_4to5s': b1 != b2, 'play_btn': fig.locator('.vis-btn').first.text_content() if fig.locator('.vis-btn').count() else None}
                ctx.close()
            except Exception as e:
                import traceback; E['error'] = traceback.format_exc()[-1500:]
            finally:
                b.close()
            print(eng, json.dumps(E)[:3000], flush=True)
finally:
    json.dump(R, open(os.path.join(OUT, 'probe3.json'), 'w'), indent=1, ensure_ascii=False)
    server.terminate()
    try: server.wait(10)
    except Exception: server.kill()
    print('server stopped', server.pid)
