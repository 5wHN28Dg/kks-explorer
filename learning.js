// The Learning page (learning.html). A file of its own, not an inline script, so the Content-Security-Policy can
// allow scripts from this site only (#8).
// The courses (docs/COURSES.md, drawn by course.html) as the server lists them. Progress = the course's own "solved"
// key, from this device's log (private, M4) where there is one, else from this browser.
(async () => {
  await K.start();
  let courses = [];
  try { courses = (await K.api('/api/courses')).courses.map(c => ({...c, href: '/course.html?c=' + encodeURIComponent(c.id)})) } catch (e) {}
  let saved = null;
  try { saved = (await K.api('/api/progress')).courses } catch (e) {}
  const solvedOf = c => {
    let s = saved ? saved[c.id]?.solved : localStorage.getItem(c.id + '.solved');
    try { s = JSON.parse(s || '{}') } catch (e) { s = {} }
    return c.questions.filter(q => s[q]).length;
  };
  const h = K.h;
  document.getElementById('main').replaceChildren(...courses.map(c => {
    const n = solvedOf(c), t = c.questions.length;
    const a = h('a', {class: 'course'}, h('h2', null, c.title), c.short ? h('div', {class: 'sub'}, c.short) : null,
      h('div', {class: 'sub'}, `${n} of ${t} questions answered correctly`), h('div', {class: 'bar'}, h('i', {style: `width:${t ? Math.round(100 * n / t) : 0}%`})));
    a.href = K.safeUrl(c.href);
    return a;
  }), h('p', {class: 'sub'}, saved ? 'Your progress is private: only your own devices can read it, and it follows you between them.'
                                   : 'On the plant server, progress stays in this browser. The app on your own phone or computer keeps it with you across devices.'));
})();
