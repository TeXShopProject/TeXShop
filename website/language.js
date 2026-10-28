// Select the stored language at the automatic entry page, or use the browser preference.
(() => {
    let language;
    try { language = localStorage.getItem('texshop-language'); } catch (_) { /* Use the browser preference. */ }
    if (language !== 'ja' && language !== 'en') {
        const languages = navigator.languages?.length ? navigator.languages : [navigator.language || 'en'];
        language = languages.map(value => value.toLowerCase().split('-')[0])
            .find(value => value === 'ja' || value === 'en') || 'en';
    }
    if (language === 'ja') location.replace('ja.html' + location.search + location.hash);
})();
