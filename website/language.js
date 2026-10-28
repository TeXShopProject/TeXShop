// added by Terada: Detect language only at the automatic entry page.
(() => {
    const languages = navigator.languages?.length ? navigator.languages : [navigator.language || 'en'];
    const language = languages.map(value => value.toLowerCase().split('-')[0])
        .find(value => value === 'ja' || value === 'en') || 'en';
    if (language === 'ja') {
        location.replace('ja.html' + location.search + location.hash);
    }
})();
