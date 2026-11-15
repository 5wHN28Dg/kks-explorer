"""Extra probes for the web audit (focus ring, Arabic note, forced colours, T4, D3, G2, G3, photo delete dialog).
  .venv/bin/python web_probe2.py OUTDIR [engines...]   (same environment as audit_web.py; reuses its server setup)"""
import os, sys, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from web_setup import *  # noqa: E402,F401,F403  (starts the server and makes the synthetic data)
OUT = sys.argv[1]; ENGINES = sys.argv[2:] or ['chromium', 'webkit', 'firefox']
os.makedirs(os.path.join(OUT, 'shots'), exist_ok=True); os.makedirs(os.path.join(OUT, 'data'), exist_ok=True)

def login(ctx): assert ctx.request.post(BASE + '/api/login', data={'username': 'boss', 'password': PW}, headers={'Origin': BASE}).ok
def wait_index(page):
    page.wait_for_function("() => typeof TAGS !== 'undefined' && TAGS.length > 0", timeout=30000)
    page.wait_for_function("() => { const i = document.getElementById('sheetimg'); return i && i.complete && i.naturalWidth > 0 }", timeout=30000)
    page.wait_for_timeout(500)
def shot(page, name, **kw): page.screenshot(path=os.path.join(OUT, 'shots', name + '.png'), **kw)

try:
    with sync_playwright() as pw:
        # a photo on the tag (JPEG XL made by the page, as test_admin_web does)
        b = pw.chromium.launch(); c = b.new_context(); login(c); pg = c.new_page(); pg.goto(BASE + '/learning.html')
        pg.wait_for_function("() => typeof K !== 'undefined' && K.me")
        jxl = pg.evaluate("""() => { const c = document.createElement('canvas'); c.width = 64; c.height = 48;
            const g = c.getContext('2d'); g.fillStyle = '#3c5a96'; g.fillRect(0, 0, 64, 48); return K.jxlEncode(c, 1.9, 3) }""")
        b.close()
        log('photo', boss.req('POST', '/api/submit', {'kind': 'photo', 'payload': {'kks': KKS, 'caption': 'Synthetic photo', 'dataUrl': jxl}}).get('status'))
        for eng in ENGINES:
            R = {}; browser = getattr(pw, eng).launch()
            try:
                # --- focus ring on the header buttons and a ghost button (K3, A1)
                ctx = browser.new_context(viewport={'width': 1280, 'height': 800}, color_scheme='dark'); login(ctx); page = ctx.new_page()
                page.goto(BASE + '/'); wait_index(page)
                page.locator('#q').focus(); page.keyboard.press('Tab')
                shot(page, f'{eng}-focus-header', clip={'x': 380, 'y': 0, 'width': 300, 'height': 60})
                page.keyboard.press('Shift+Tab'); page.keyboard.press('Shift+Tab')
                R['focus_from_search_back'] = page.evaluate("document.activeElement.localName + '#' + document.activeElement.id")
                # --- the panel: Arabic note, direction, photo delete
                page.goto(BASE + '/?kks=' + KKS); wait_index(page); page.wait_for_selector('#panel.open')
                R['notes_dir'] = page.evaluate("(() => { const e = document.getElementById('f_notes'); return [e.getAttribute('dir'), getComputedStyle(e).direction, e.value] })()")
                page.locator('#f_notes').scroll_into_view_if_needed(); page.wait_for_timeout(200)
                bb = page.locator('#f_notes').bounding_box()
                shot(page, f'{eng}-arabic-note', clip={'x': bb['x'] - 10, 'y': bb['y'] - 30, 'width': bb['width'] + 70, 'height': bb['height'] + 40})
                # photo delete button vs the photo (T2), and the dialog it opens (D2, A2)
                dl = page.locator('#panel .photos button').first
                if dl.count():
                    dl.scroll_into_view_if_needed(); page.wait_for_timeout(200)
                    R['photo_del_box'] = dl.bounding_box(); R['photo_img_box'] = page.locator('#panel .photos img').first.bounding_box()
                    shot(page, f'{eng}-photo-delete', clip={'x': R['photo_img_box']['x'] - 6, 'y': R['photo_img_box']['y'] - 6, 'width': R['photo_img_box']['width'] + 12, 'height': R['photo_img_box']['height'] + 40})
                    dl.click(); page.wait_for_timeout(300)
                    R['ask'] = page.evaluate("""(() => { const a = document.activeElement; const o = [...document.body.children].pop();
                        return {focus: a.localName + ' ' + (a.textContent || a.placeholder || '').slice(0, 20), role: o.getAttribute('role'), modal: o.getAttribute('aria-modal'),
                                buttons: [...o.querySelectorAll('button')].map(b => b.textContent + ' bg=' + getComputedStyle(b).backgroundColor)} })()""")
                    shot(page, f'{eng}-delete-ask')
                    page.keyboard.press('Escape'); page.wait_for_timeout(200)
                    R['ask_after_escape_open'] = page.locator('text=Delete this photo?').count()
                    page.keyboard.press('Enter'); page.wait_for_timeout(300)
                    R['ask_after_enter_open'] = page.locator('text=Delete this photo?').count()
                    R['after_enter_toast'] = page.text_content('#toast')
                # --- D3: type into Notes, close the panel, open it again
                page.goto(BASE + '/?kks=' + KKS); wait_index(page); page.wait_for_selector('#panel.open')
                page.get_by_role('button', name='Edit Notes').click(); page.fill('#f_notes', 'typed but not saved')
                n0 = []; page.on('dialog', lambda d: (n0.append(d.message), d.dismiss()))
                page.get_by_role('button', name='Close the panel').click(); page.wait_for_timeout(300)
                page.locator('#q').fill('LAB70AA501'); page.wait_for_selector('#results [role=option]'); page.keyboard.press('Enter'); page.wait_for_selector('#panel.open')
                R['d3_after_close'] = {'asked': n0[:], 'notes': page.input_value('#f_notes')}
                page.get_by_role('button', name='Edit Notes').click(); page.fill('#f_notes', 'typed again')
                try:
                    page.goto(BASE + '/learning.html', timeout=5000)
                except Exception as e: R['d3_nav_err'] = str(e)[:100]
                R['d3_after_navigate'] = {'asked': n0[:], 'url': page.url}
                # --- G2: the open tag in the URL (a reload brings it back)
                page.goto(BASE + '/'); wait_index(page)
                page.locator('#q').fill('LAB70AA501'); page.wait_for_selector('#results [role=option]'); page.keyboard.press('Enter'); page.wait_for_selector('#panel.open')
                R['g2_url'] = page.url; page.reload(); wait_index(page); page.wait_for_timeout(500)
                R['g2_panel_after_reload'] = page.evaluate("document.getElementById('panel').classList.contains('open') && document.querySelector('#panel .kks').textContent")
                ctx.close()
                # --- T4: a tap 12 px beside the tag at the phone layout
                ctx = browser.new_context(viewport={'width': 412, 'height': 915}, color_scheme='dark', has_touch=eng != 'firefox'); login(ctx); page = ctx.new_page()
                page.goto(BASE + '/?kks=' + KKS); wait_index(page); page.wait_for_selector('#panel.open')
                page.get_by_role('button', name='Close the panel').click(); page.wait_for_timeout(300)
                box = page.evaluate("""(() => { const t = [...document.querySelectorAll('#layer .hs')].find(e => (e.getAttribute('aria-label') || e.title || '').includes('11LAB70AA501'));
                    if (!t) return null; const r = t.getBoundingClientRect(); return [r.left, r.top, r.width, r.height] })()""")
                R['t4_tag_box'] = box
                if box:
                    page.mouse.click(box[0] + box[2] + 12, box[1] + box[3] / 2); page.wait_for_timeout(400)
                    R['t4_beside_opens'] = page.evaluate("document.getElementById('panel').classList.contains('open')")
                # landscape phone (G3)
                page.set_viewport_size({'width': 915, 'height': 412}); page.goto(BASE + '/?kks=' + KKS); wait_index(page); page.wait_for_selector('#panel.open'); page.wait_for_timeout(300)
                shot(page, f'{eng}-landscape-panel')
                page.goto(BASE + '/admin.html#users'); page.wait_for_selector('#signups', timeout=15000); page.wait_for_timeout(500); shot(page, f'{eng}-landscape-admin')
                ctx.close()
                # --- forced colours (Chromium only emulates it)
                if eng == 'chromium':
                    ctx = browser.new_context(viewport={'width': 1280, 'height': 800}, forced_colors='active'); login(ctx); page = ctx.new_page()
                    page.goto(BASE + '/?kks=' + KKS); wait_index(page); page.wait_for_selector('#panel.open'); page.wait_for_timeout(300)
                    shot(page, f'{eng}-forced-colors-panel')
                    page.click('#zcover'); page.get_by_role('button', name='Close the panel').click(); page.wait_for_timeout(300); shot(page, f'{eng}-forced-colors-cover')
                    page.goto(BASE + '/admin.html#queue'); page.wait_for_selector('#main .card'); page.wait_for_timeout(400); shot(page, f'{eng}-forced-colors-admin')
                    ctx.close()
                # --- the course page, reduced motion, and a wrong answer (K4)
                ctx = browser.new_context(viewport={'width': 412, 'height': 915}, color_scheme='light', reduced_motion='reduce'); login(ctx); page = ctx.new_page()
                page.goto(BASE + '/course.html?c=inc'); page.wait_for_timeout(1500)
                opt = page.locator('#main button.opt').first
                if opt.count():
                    opt.scroll_into_view_if_needed(); opt.click(); page.wait_for_timeout(300)
                    fb = page.locator('#main .fb').first
                    R['course_feedback'] = fb.text_content()[:120] if fb.count() else None
                    R['course_feedback_role'] = fb.get_attribute('role') if fb.count() else None
                    if fb.count(): fb.scroll_into_view_if_needed(); shot(page, f'{eng}-course-answer')
                R['course_transitions'] = page.evaluate("getComputedStyle(document.querySelector('#main button') || document.body).transitionDuration")
                ctx.close()
            except Exception:
                R['error'] = traceback.format_exc()[-1200:]; log('probe2 fail', eng, R['error'])
            with open(os.path.join(OUT, 'data', f'{eng}-probe2.json'), 'w') as f: json.dump(R, f, indent=1, ensure_ascii=False)
            browser.close(); log('probe2 done', eng)
finally:
    server.terminate(); server.wait(10); shutil.rmtree(d, ignore_errors=True); log('server stopped')
