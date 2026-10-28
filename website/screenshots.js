/* Added by Terada: accessible screenshot slideshow with reduced-motion support. */
for (const gallery of document.querySelectorAll('.screenshot-gallery')) {
  const images = [...gallery.querySelectorAll('.screenshot-frame img')];
  const choices = [...gallery.querySelectorAll('[data-slide]')];
  const toggle = gallery.querySelector('.slideshow-toggle');
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  let current = matchMedia('(prefers-color-scheme: dark)').matches ? images.length - 1 : 0;
  let paused = motion.matches, timer;
  function show(index) {
    current = index;
    images.forEach((image, i) => {
      image.classList.toggle('is-current', i === index);
      image.setAttribute('aria-hidden', String(i !== index));
    });
    choices.forEach((button, i) => button.setAttribute('aria-pressed', String(i === index)));
  }
  function schedule() {
    clearInterval(timer);
    if (!paused && !document.hidden && !gallery.matches(':hover') && !gallery.contains(document.activeElement)) {
      timer = setInterval(() => show((current + 1) % images.length), 5500);
    }
    toggle.setAttribute('aria-label', paused ? 'Play slideshow' : 'Pause slideshow');
    toggle.setAttribute('aria-pressed', String(paused));
    toggle.firstElementChild.textContent = paused ? '▶' : 'Ⅱ';
  }
  choices.forEach((button, i) => button.addEventListener('click', () => show(i)));
  toggle.addEventListener('click', () => { paused = !paused; schedule(); });
  gallery.addEventListener('mouseenter', schedule);
  gallery.addEventListener('mouseleave', schedule);
  gallery.addEventListener('focusin', schedule);
  gallery.addEventListener('focusout', () => requestAnimationFrame(schedule));
  document.addEventListener('visibilitychange', schedule);
  motion.addEventListener('change', () => { paused = motion.matches; schedule(); });
  show(current);
  schedule();
}
