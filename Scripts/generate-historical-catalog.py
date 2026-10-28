from pathlib import Path
import re,json,html,urllib.parse
from datetime import date
repo=Path(__file__).resolve().parents[1];root=repo/'website';meta=json.loads((repo/'Documentation/HistoricalReleases/manifest.json').read_text())
dates=json.loads((repo/'Documentation/HistoricalReleases/release-dates.json').read_text())
overrides=json.loads((repo/'Documentation/HistoricalReleases/requirements-overrides.json').read_text())
assert all(a['status']=='ok' for r in meta for a in r['assets']), 'archives incomplete'
svg='<svg aria-hidden="true" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="8" y="8" width="12" height="13" rx="2"/><path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3"/></svg><span>SHA-256</span>'
def order(r):
 t=r['tag'];m=re.match(r'v(\d+)\.(\d+)(?:\.(\d+))?',t); nums=tuple(int(n or 0) for n in m.groups()) if m else (0,0,0);return nums, (not bool(re.search(r'(?:beta|d\d)',t,re.I))),t
meta.sort(key=order,reverse=True)
def cell(a,role,tag,ja):
 if not a:return '<span class="not-available">—</span>'
 path='https://github.com/TeXShopProject/TeXShop/releases/download/historical-archive/'+urllib.parse.quote(a['name']);name=f'TeXShop {tag[1:]} {role}';desc=f'{name}のSHA-256をコピー' if ja else f'Copy SHA-256 for {name}';sha=a['sha256']
 return f'<div class="download-actions"><a class="file-button" href="{html.escape(path,quote=True)}" aria-label="{html.escape(name)} ZIP">{role}</a><button class="file-button hash-copy" type="button" data-sha256="{sha}" title="{sha}" aria-label="{html.escape(desc)}" disabled>{svg}</button></div>'
def norm(v):
 if not v:return None
 try:
  nums=tuple(int(n) for n in v.split('.'))
  return '.'.join(str(n) for n in nums[:2] if True)+(('.'+str(nums[2])) if len(nums)>2 and nums[2] else '')
 except Exception:return None

def details(app,ja):
 if not app:return ('不明' if ja else 'Unknown','不明' if ja else 'Unknown')
 arches=app.get('architectures',[]);cpus=[x.get('cpu') for x in arches];cpus.sort(key=lambda c: {'arm64':0,'x86_64':1,'i386':2,'ppc':3,'ppc64':4}.get(c,5));names={'arm64':'Apple Silicon','x86_64':'Intel（64ビット）' if ja else 'Intel (64-bit)','i386':'Intel（32ビット）' if ja else 'Intel (32-bit)','ppc':'PowerPC','ppc64':'PowerPC (64-bit)'}
 cpu='<br>'.join(names.get(c,html.escape(str(c))) for c in cpus) or ('不明' if ja else 'Unknown')
 minimum=norm(app.get('plist_min')); archmins=[norm(a.get('min_os')) for a in arches if norm(a.get('min_os'))]
 if not minimum and archmins:
  minimum=min(archmins,key=lambda x:tuple(map(int,x.split('.'))))
 if not minimum:os='不明' if ja else 'Unknown'
 else:
  parts=tuple(map(int,minimum.split('.'))); family=('Mac OS X' if parts[:1]==(10,) and parts[1]<8 else 'OS X' if parts[:1]==(10,) and parts[1]<12 else 'macOS')
  os=(family+' '+minimum+'以降') if ja else (family+' '+minimum+' or later')
 if 'i386' in cpus and 'x86_64' not in cpus and 'arm64' not in cpus:
  os+=('<small>32ビットIntelはmacOS 10.14まで</small>' if ja else '<small>32-bit Intel: through macOS 10.14</small>')
 if 'ppc' in cpus:os+=('<small>PowerPCはMac OS X 10.6まで</small>' if ja else '<small>PowerPC: through Mac OS X 10.6</small>')
 if 'arm64' in cpus:os+=('<small>Apple SiliconはmacOS 11以降</small>' if ja else '<small>Apple Silicon requires macOS 11 or later</small>')
 return os,cpu
for ja in (False,True):
 filename='downloads-ja.html' if ja else 'downloads.html';text=(root/filename).read_text();pre,rest=text.split('<main class="archive-content downloads">',1); oldmain,post=rest.split('</main>',1)
 title='過去の全バージョン' if ja else 'All Previous Versions';pre=re.sub(r'<title>.*?</title>',f'<title>{title} — TeXShop</title>',pre,count=1)
 if ja:pre=pre.replace('href="downloads.html" lang="en"','href="all-releases.html" lang="en"')
 else:pre=pre.replace('href="downloads-ja.html" lang="ja"','href="all-releases-ja.html" lang="ja"')
 pre=pre.replace('hreflang="en" href="downloads.html"','hreflang="en" href="all-releases.html"').replace('hreflang="ja" href="downloads-ja.html"','hreflang="ja" href="all-releases-ja.html"')
 labels=['バージョン','対応OS','対応CPU','App','Source'] if ja else ['Version','Supported OS','CPU','App','Source']; esc=html.escape
 rows=[]
 for r in meta:
  if not r['assets']:continue
  app=next((a for a in r['assets'] if a['name'].lower().startswith('texshop-')),None);source=next((a for a in r['assets'] if a['name'].lower().startswith('texshopsource-')),None)
  icon=(app or source or {}).get('icon_sha256'); iconpath='assets/release-icons/history/'+icon+'.png' if icon and (root/'assets/release-icons/history'/f'{icon}.png').exists() else None
  img=f'<img src="{iconpath}" width="48" height="48" alt="" loading="lazy">' if iconpath else '<span class="release-icon-placeholder" aria-hidden="true"></span>'
  requirement_app=dict(app) if app else None
  override=overrides.get(r['tag'],{})
  if requirement_app and 'minimum_os' in override: requirement_app['plist_min']=override['minimum_os']
  os,cpu=details(requirement_app,ja);version=esc(r['tag'][1:]); dateinfo=dates.get(r['tag'][1:]); stamp=''
  match=re.fullmatch(r'v5\.(\d+)',r['tag'])
  if app and match and int(match.group(1))<=48:
   os+=('<small>macOS 10.14 Mojaveでは起動不可</small>' if ja else '<small>Does not run on macOS 10.14 Mojave</small>')
  if dateinfo:
   d=date.fromisoformat(dateinfo['date']);label=f'{d.year}年{d.month}月{d.day}日' if ja else d.strftime('%B')+f' {d.day}, {d.year}'
   stamp=f'<small><time datetime="{d.isoformat()}">{label}</time></small>'
  tds=[f'<div class="release-version">{img}<div>TeXShop {version}{stamp}</div></div>',os,cpu,cell(app,'App',r['tag'],ja),cell(source,'Source',r['tag'],ja)]
  rows.append('<tr>'+''.join(f'<td data-label="{labels[i]}">{v}</td>' for i,v in enumerate(tds))+'</tr>')
 note=('過去のバージョンをダウンロードできます。' if ja else 'Download previous versions of TeXShop.')
 heading=''.join('<th scope="col">'+esc(x)+'</th>' for x in labels)
 main=f'<main class="archive-content downloads"><h1>{title}</h1><p>{note}</p><table class="download-table legacy-downloads"><thead><tr>{heading}</tr></thead><tbody>'+''.join(rows)+'</tbody></table></main>'
 (root/('all-releases-ja.html' if ja else 'all-releases.html')).write_text(pre+main+post)
print('Generated',len(rows),'rows per page')
