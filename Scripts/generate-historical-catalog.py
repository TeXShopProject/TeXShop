from pathlib import Path
import re,json,html,urllib.parse
from datetime import date
repo=Path(__file__).resolve().parents[1];root=repo/'website';meta=json.loads((repo/'Documentation/HistoricalReleases/manifest.json').read_text())
dates=json.loads((repo/'Documentation/HistoricalReleases/release-dates.json').read_text())
year_inferences=json.loads((repo/'Documentation/HistoricalReleases/year-inferences.json').read_text())
overrides=json.loads((repo/'Documentation/HistoricalReleases/requirements-overrides.json').read_text())
projects={x['tag']:x for x in json.loads((repo/'Documentation/HistoricalReleases/project-settings-audit.json').read_text())}
statuses=json.loads((repo/'Documentation/HistoricalReleases/release-status.json').read_text())
changelogs=json.loads((repo/'Documentation/HistoricalReleases/changelog-links.json').read_text())
first_release=json.loads((repo/'Documentation/HistoricalReleases/first-release.json').read_text())
icon_notes=json.loads((repo/'Documentation/HistoricalReleases/icon-transition-notes.json').read_text())
cpu_notes=json.loads((repo/'Documentation/HistoricalReleases/cpu-transition-notes.json').read_text())
requirements=json.loads((repo/'Documentation/HistoricalReleases/requirements-inferences.json').read_text())
assert all(a['status']=='ok' for r in meta for a in r['assets']), 'archives incomplete'
svg='<svg aria-hidden="true" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="8" y="8" width="12" height="13" rx="2"/><path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3"/></svg><span>SHA-256</span>'
def order(r):
 t=r['tag'];m=re.match(r'v(\d+)\.(\d+)(?:\.(\d+))?',t); nums=tuple(int(n or 0) for n in m.groups()) if m else (0,0,0)
 chronological=dates.get(t[1:],{}).get('date','') if nums==(1,0,0) else ''
 return nums, (not bool(re.search(r'(?:beta|d\d)',t,re.I))),chronological,t
meta.sort(key=order,reverse=True)
def date_label(value, ja):
 parts=value.split('-')
 if not re.fullmatch(r'\d{4}(?:-\d{2}){0,2}',value):
  raise ValueError(f'Invalid historical date: {value}')
 year=int(parts[0]);month=int(parts[1]) if len(parts)>1 else 1;day=int(parts[2]) if len(parts)>2 else 1
 d=date(year,month,day)
 if len(parts)==1:return f'{year}年' if ja else str(year)
 if len(parts)==2:return f'{year}年{month}月' if ja else d.strftime('%B')+f' {year}'
 return f'{year}年{month}月{day}日' if ja else d.strftime('%B')+f' {day}, {year}'

def date_stamp(info, ja):
 value=info['date'];label=date_label(value,ja)
 stamp=f'<time datetime="{value}">{label}</time>'
 if info.get('end_date'):
  end=info['end_date'];end_label=date_label(end,ja)
  if len(end)!=len(value) or end<=value:raise ValueError('Historical date range must increase at equal precision')
  stamp+=f'–<time datetime="{end}">{end_label}</time>'
 return '<small>'+stamp+'</small>'

def cell(a,role,tag,ja):
 if not a:return '<span class="not-available">—</span>'
 path=a.get('download_url') or 'https://github.com/TeXShopProject/TeXShop/releases/download/historical-archive/'+urllib.parse.quote(a['name']);name=f'TeXShop {tag[1:]} {role}';desc=f'{name}のSHA-256をコピー' if ja else f'Copy SHA-256 for {name}';sha=a['sha256']
 return f'<div class="download-actions"><a class="file-button" href="{html.escape(path,quote=True)}" aria-label="{html.escape(name)} ZIP">{role}</a><button class="file-button hash-copy" type="button" data-sha256="{sha}" title="{sha}" aria-label="{html.escape(desc)}" disabled>{svg}</button></div>'
def norm(v):
 if not v:return None
 try:
  nums=tuple(int(n) for n in v.split('.'))
  return '.'.join(str(n) for n in nums[:2] if True)+(('.'+str(nums[2])) if len(nums)>2 and nums[2] else '')
 except Exception:return None

def details(app,ja):
 if app is None:return ('不明' if ja else 'Unknown','不明' if ja else 'Unknown')
 arches=app.get('architectures',[]);cpus=[x.get('cpu') for x in arches];cpus.sort(key=lambda c: {'arm64':0,'x86_64':1,'i386':2,'ppc':3,'ppc64':4}.get(c,5));names={'arm64':'Apple Silicon','x86_64':'Intel（64ビット）' if ja else 'Intel (64-bit)','i386':'Intel（32ビット）' if ja else 'Intel (32-bit)','ppc':'PowerPC（32ビット）' if ja else 'PowerPC (32-bit)','ppc64':'PowerPC（64ビット）' if ja else 'PowerPC (64-bit)'}
 cpu='<span class="cpu-tags">'+''.join(f'<span class="cpu-tag cpu-tag--{html.escape(c,quote=True)}">{html.escape(names.get(c,str(c)))}</span>' for c in cpus)+'</span>' if cpus else ('不明' if ja else 'Unknown')
 minimum=norm(app.get('plist_min')); archmins=[norm(a.get('min_os')) for a in arches if norm(a.get('min_os'))]
 if archmins:
  archminimum=min(archmins,key=lambda x:tuple(map(int,x.split('.'))))
  if not minimum or tuple(map(int,archminimum.split('.'))) > tuple(map(int,minimum.split('.'))): minimum=archminimum
 if not minimum:os='不明' if ja else 'Unknown'
 else:
  parts=tuple(map(int,minimum.split('.'))); family=('Mac OS X' if parts[:1]==(10,) and parts[1]<8 else 'OS X' if parts[:1]==(10,) and parts[1]<12 else 'macOS')
  os=(family+' '+minimum+'以降') if ja else (family+' '+minimum+' or later')
 if 'i386' in cpus and 'x86_64' not in cpus and 'arm64' not in cpus:
  os+=('<small>32ビットIntelはmacOS 10.14まで</small>' if ja else '<small>32-bit Intel: through macOS 10.14</small>')
 if 'ppc' in cpus:os+=('<small>PowerPCはMac OS X 10.6まで</small>' if ja else '<small>PowerPC: through Mac OS X 10.6</small>')
 if 'arm64' in cpus and (not minimum or tuple(map(int,minimum.split('.'))) < (11,0)):os+=('<small>Apple SiliconはmacOS 11以降</small>' if ja else '<small>Apple Silicon requires macOS 11 or later</small>')
 return os,cpu
for ja in (False,True):
 filename='downloads-ja.html' if ja else 'downloads.html';text=(root/filename).read_text();pre,rest=text.split('<main class="archive-content downloads">',1); oldmain,post=rest.split('</main>',1)
 title='リリース履歴' if ja else 'Release History';pre=re.sub(r'<title>.*?</title>',f'<title>{title} — TeXShop</title>',pre,count=1)
 if ja:pre=pre.replace('href="downloads.html" lang="en"','href="all-releases.html" lang="en"')
 else:pre=pre.replace('href="downloads-ja.html" lang="ja"','href="all-releases-ja.html" lang="ja"')
 pre=pre.replace('hreflang="en" href="downloads.html"','hreflang="en" href="all-releases.html"').replace('hreflang="ja" href="downloads-ja.html"','hreflang="ja" href="all-releases-ja.html"')
 labels=['バージョン','対応OS','対応CPU','App','Source'] if ja else ['Version','Supported OS','CPU','App','Source']; esc=html.escape
 # Use the current Downloads row as the single source of truth for the latest version.
 latest_table=re.search(r'<table\b[^>]*>.*?</table>',oldmain,re.S).group(0)
 latest_row=re.search(r'<tbody>\s*(<tr>.*?</tr>)',latest_table,re.S).group(1)
 latest_cells=re.findall(r'<td\b[^>]*>.*?</td>',latest_row,re.S)
 assert len(latest_cells)==6, 'Expected the current Downloads row with release notes'
 latest_version=re.search(r'<strong>TeXShop ([^<]+)</strong>',latest_cells[0]).group(1)
 notes_path=('release-notes-ja.html' if ja else 'release-notes.html')+'#v'+latest_version
 latest_cells[0]=latest_cells[0].replace('<strong>TeXShop '+latest_version+'</strong>',f'<a href="{html.escape(notes_path,quote=True)}">TeXShop {html.escape(latest_version)}</a>')
 rows=[('latest','', '<tr>'+''.join(latest_cells[:5])+'</tr>')]
 for r in meta:
  if r['tag'] in ('v'+latest_version,'v.'+latest_version):continue
  if not r['assets']:continue
  app=next((a for a in r['assets'] if a.get('kind') == 'app' or (not a.get('kind') and a['name'].lower().startswith('texshop-'))),None);source=next((a for a in r['assets'] if a.get('kind') == 'source' or (not a.get('kind') and a['name'].lower().startswith('texshopsource-'))),None)
  iconasset=app or source or {}; icon=iconasset.get('icon_png_sha256') or (None if iconasset.get('icon_inferred_from') else iconasset.get('icon_sha256')); iconpath='assets/release-icons/history/'+icon+'.png' if icon and (root/'assets/release-icons/history'/f'{icon}.png').exists() else None
  img=f'<img src="{iconpath}" width="48" height="48" alt="" loading="lazy">' if iconpath else '<span class="release-icon-placeholder" aria-hidden="true"></span>'
  requirement_app=dict(app) if app else None
  project=projects.get(r['tag'],{})
  release_settings=[c['settings'] for c in project.get('configs',[]) if c.get('name')=='Release']
  if not release_settings: release_settings=[c['settings'] for c in project.get('configs',[]) if c.get('name')=='Legacy']
  if not app and source:
   embedded=source.get('embedded_application')
   requirement_app=dict(embedded) if embedded else {}
  if requirement_app is not None:
   for config in release_settings:
    minimum=config.get('MACOSX_DEPLOYMENT_TARGET')
    current=requirement_app.get('plist_min')
    if minimum and (not current or (not app and tuple(map(int,str(minimum).split('.'))) > tuple(map(int,str(current).split('.'))))):
     requirement_app['plist_min']=str(minimum)
   if not requirement_app.get('architectures') and release_settings:
    arch=next((c['ARCHS'] for c in reversed(release_settings) if c.get('ARCHS')),None)
    if arch == '$(ARCHS_STANDARD_32_64_BIT)': arch=['i386','x86_64']
    if isinstance(arch,list) and all(x in ('i386','x86_64','ppc','ppc64','arm64') for x in arch):
     requirement_app['architectures']=[{'cpu':x} for x in arch]
  override=overrides.get(r['tag'],{})
  if requirement_app and 'minimum_os' in override: requirement_app['plist_min']=override['minimum_os']
  inferred=requirements.get(r['tag'],{})
  if requirement_app is not None:
   if not requirement_app.get('architectures') and inferred.get('architectures'):
    requirement_app['architectures']=[{'cpu':x} for x in inferred['architectures']]
   if not requirement_app.get('plist_min') and inferred.get('minimum_os'):
    requirement_app['plist_min']=inferred['minimum_os']
  os,cpu=details(requirement_app,ja)
  if r.get('os_note'): os += '<small>'+html.escape(r['os_note']['ja' if ja else 'en'])+'</small>'
  version=esc(r.get('display_version',r['tag'][1:])); dateinfo=dates.get(r['tag'][1:]); stamp=''
  match=re.fullmatch(r'v5\.(\d+)',r['tag'])
  if app and match and int(match.group(1))<=48:
   os+=('<small>macOS 10.14 Mojaveでは起動不可</small>' if ja else '<small>Does not run on macOS 10.14 Mojave</small>')
  if dateinfo:
   stamp=date_stamp(dateinfo,ja)
  status=statuses.get(r['tag'],{}); state=status.get('status'); label={'beta':('ベータ版','beta'),'unreleased':('未公開','unreleased'),'experimental':('実験版','experimental'),'development':('開発版','development'),'first_official':('初公式リリース','first official release')}.get(state); badge=''
  if label:
   label_text=(label[0] if ja else label[1]) if state=='first_official' else (f'（{label[0]}）' if ja else f'({label[1]})'); badge=f' <span class="release-status{" first-official" if state=="first_official" else ""}">{label_text}</span>'
  changelog=html.escape(changelogs[r['tag']].get('path_ja' if ja else 'path',changelogs[r['tag']]['path']),quote=True); version_link=f'<a href="{changelog}">TeXShop {version}</a>'
  if state=='first_official':
   badge=f'<small class="release-status first-official">{label_text}</small>'; version_contents=version_link+stamp+badge; version_class='release-version first-release-version'
  else:
   version_contents=version_link+badge+stamp; version_class='release-version'
  if r.get('variant'): version_contents += '<small class="release-variant">'+html.escape(r['variant']['ja' if ja else 'en'])+'</small>'
  icon_note=icon_notes.get(r['tag'])
  if icon_note:
   version_contents += f'<small class="icon-transition-note">{html.escape(icon_note["ja" if ja else "en"])}</small>'; version_class='release-version first-release-version'
  cpu_note=cpu_notes.get(r['tag'])
  if cpu_note:
   version_contents += f'<small class="release-milestone-note">{html.escape(cpu_note["ja" if ja else "en"])}</small>'; version_class='release-version first-release-version'
  tds=[f'<div class="{version_class}">{img}<div>{version_contents}</div></div>',os,cpu,cell(app,'App',r['tag'],ja),cell(source,'Source',r['tag'],ja)]
  year=dateinfo['date'][:4] if dateinfo else year_inferences[r['tag']]['year']
  if dateinfo and dateinfo.get('end_date',dateinfo['date'])[:4]!=year:
   year+='–'+dateinfo['end_date'][:4]
  rows.append((year,dateinfo['date'] if dateinfo else '', '<tr>'+''.join(f'<td data-label="{labels[i]}">{v}</td>' for i,v in enumerate(tds))+'</tr>'))
 first=first_release; first_os,first_cpu=details(first['app'],ja)
 first_stamp='2000年7月23日' if ja else 'July 23, 2000'
 first_variant='2024年再コンパイル版' if ja else 'Recompiled in 2024'
 first_name=f'<a href="{html.escape(first["history"],quote=True)}">TeXShop 1.0d1</a> <span class="release-status">（開発版）</span>' if ja else f'<a href="{html.escape(first["history"],quote=True)}">TeXShop 1.0d1</a> <span class="release-status">(development)</span>'
 first_version=f'<div class="release-version first-release-version"><img src="{html.escape(first["icon"],quote=True)}" width="48" height="48" alt="" loading="lazy"><div>{first_name}<small><time datetime="{first["release_date"]}">{first_stamp}</time></small><small class="recompiled-note">{first_variant}</small></div></div>'
 first_cells=[first_version,first_os,first_cpu,cell(first['app'],'App',first['tag'],ja),cell(first['source'],'Source',first['tag'],ja)]
 rows.append((first['release_date'][:4],first['release_date'], '<tr>'+''.join(f'<td data-label="{labels[i]}">{v}</td>' for i,v in enumerate(first_cells))+'</tr>'))
 heading=''.join('<th scope="col">'+esc(x)+'</th>' for x in labels)
 back='<a href="downloads-ja.html">‹ ダウンロード</a>' if ja else '<a href="downloads.html">‹ Downloads</a>'
 groups={}
 for year,release_date,row in rows:
  groups.setdefault(year,[]).append((release_date,row))
 def group_order(year):
  if year=='latest':return (9999,9999)
  bounds=year.split('–')
  return (int(bounds[-1]),int(bounds[0]))
 sections=[];year_links=[]
 for year in sorted(groups,key=group_order,reverse=True):
  section_id='releases-'+year.replace('–','-')
  if year=='latest':label='最新バージョン' if ja else 'Latest Version'
  else:label=year+('年' if ja else '')
  year_links.append(f'<a href="#{section_id}">{label}</a>')
  # Preserve version order within each year, including dates known only to the year.
  content=''.join(row for _,row in groups[year])
  sections.append(f'<section class="release-year" aria-labelledby="{section_id}"><h2 id="{section_id}">{label}</h2><table class="download-table legacy-downloads"><thead><tr>{heading}</tr></thead><tbody>{content}</tbody></table></section>')
 navigation=f'<nav class="release-years" aria-label="{"年別のリリース履歴" if ja else "Release history by year"}">'+''.join(year_links)+'</nav>'
 main=f'<main class="archive-content downloads release-history"><nav class="release-back" aria-label="{title}">{back}</nav><h1>{title}</h1>'+navigation+''.join(sections)+'</main>'
 (root/('all-releases-ja.html' if ja else 'all-releases.html')).write_text(pre+main+post)
print('Generated',len(rows),'rows per page')
