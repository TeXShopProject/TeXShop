#!/usr/bin/env python3
"""Check snapshot placement on the PDF's own volume with disposable APFS and HFS+ images.
Pass --mutation=tempdir or --mutation=fullcopy to show the checks fail without the fix."""
from pathlib import Path
import shutil, subprocess, sys, tempfile
root=Path(__file__).resolve().parents[1]
mutation=next((a.split('=',1)[1] for a in sys.argv[1:] if a.startswith('--mutation=')),None)
def run(*args, **kw): return subprocess.run([str(a) for a in args], check=True, **kw)
with tempfile.TemporaryDirectory(prefix='texshop-pdf-volumes-') as td:
    t=Path(td);source=root/'Sources/TSExternalPDFSnapshot.m'
    if mutation:
        text=source.read_text()
        if mutation=='tempdir':
            old='if (stat(candidate.fileSystemRepresentation, &info) || info.st_dev != device) {'
            assert old in text; text=text.replace(old,'if (0) {').replace('if ([url getResourceValue:&clones forKey:NSURLVolumeSupportsFileCloningKey error:NULL] && clones.boolValue)','if (1)')
        elif mutation=='fullcopy':
            assert 'COPYFILE_CLONE_FORCE)' in text; text=text.replace('COPYFILE_CLONE_FORCE)','COPYFILE_DATA | COPYFILE_CLONE)').replace('if ([url getResourceValue:&clones forKey:NSURLVolumeSupportsFileCloningKey error:NULL] && clones.boolValue)','if (1)')
        else: raise SystemExit('unknown mutation')
        shutil.copy(root/'Sources/TSExternalPDFReload.h',t);source=t/'TSExternalPDFSnapshot.m';source.write_text(text)
    run('xcrun','clang','-fobjc-arc','-framework','Cocoa','-framework','PDFKit','-I'+str(root/'Sources'),root/'Tests/PDFSnapshotVolumes.m',source,'-o',t/'probe')
    # A variant that ignores the volume capability exercises a failing clone.
    (t/'forced').mkdir();shutil.copy(root/'Sources/TSExternalPDFReload.h',t/'forced')
    capability='if ([url getResourceValue:&clones forKey:NSURLVolumeSupportsFileCloningKey error:NULL] && clones.boolValue)'
    text=source.read_text();assert capability in text or mutation
    (t/'forced/TSExternalPDFSnapshot.m').write_text(text.replace(capability,'if (1)'))
    run('xcrun','clang','-fobjc-arc','-framework','Cocoa','-framework','PDFKit','-I'+str(root/'Sources'),root/'Tests/PDFSnapshotVolumes.m',t/'forced/TSExternalPDFSnapshot.m','-o',t/'forced-probe')
    dead=subprocess.Popen(['/usr/bin/true']);dead.wait()
    (t/'stale').mkdir();run(t/'probe','stale',t/'stale',dead.pid)
    run(t/'probe','temp',t/'boot/test.pdf',t/'boot')
    mounted=[]
    try:
        for fs,mode in [('APFS','volume'),('HFS+','direct')]:
            image=t/f'{mode}.dmg';mount=t/f'mount-{mode}';mount.mkdir()
            run('hdiutil','create','-quiet','-size','20m','-fs',fs,'-volname','TSSnapshot'+mode,image,stderr=subprocess.DEVNULL)
            run('hdiutil','attach','-quiet','-nobrowse','-noautoopen','-mountpoint',mount,image,stderr=subprocess.DEVNULL);mounted.append(mount)
            run(t/'probe',mode,mount/'dir/test.pdf',mount)
            if mode=='direct': run(t/'forced-probe',mode,mount/'dir/test.pdf',mount)
            left=[p for p in mount.rglob('*') if p.name.startswith(('TeXShop-PDF-','NSIRD'))]
            if left: raise SystemExit(f'FAIL: snapshot directories left on {fs}: {left}')
    finally:
        for mount in mounted: subprocess.run(['hdiutil','detach','-quiet','-force',str(mount)],stderr=subprocess.DEVNULL)
    print('PASS: snapshots cloned on the PDF volume (boot, APFS image); HFS+ image and failed clones read in place; stale cleanup')
