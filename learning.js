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
  }), h('p', {class: 'sub', id: 'progressNote'}, saved
    ? 'Your progress is private: only you can read it, on your own devices that you paired in the app. Not the manager, not the server.'
    // decision 0062 (the user, 2026-10-22): a browser holds no key, so its progress never leaves it
    : 'Your progress stays in this browser only: it is not sent to the server, and it does not follow you to other ' +
      'devices or browsers. The Walkdown app on your phone or computer keeps it private and shares it with your own ' +
      'paired devices.'));
})();
