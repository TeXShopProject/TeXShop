 // Regression cases: context-menu transitions, end-of-document position and reparsing.
 {
  int auditFail=0;
  #define AUDIT(ok,msg) do{ if(ok) printf("AUDIT-OK   %s\n",[msg UTF8String]); else {auditFail++; printf("AUDIT-FAIL %s\n",[msg UTF8String]);} }while(0)
  MyPDFKitView *v=d.myPDFKitView; d.pdfKitWindow.activeView=v;
  [d changePreviewArrangement:Choice(@selector(changePreviewArrangement:),4)];
  // (A) arrangement chosen while in a single-page layout, then two-up selected by PDFKit's own context menu (setDisplayMode: only)
  v.document=PDF(); [d changePreviewLayout:Choice(@selector(changePreviewLayout:),1)];
  BOOL wantRTL=!d.previewDisplaysRTL; [d changePreviewArrangement:Choice(@selector(changePreviewArrangement:),wantRTL?2:1)];
  [d changePreviewArrangement:Choice(@selector(changePreviewArrangement:),3)];
  [v setDisplayMode:kPDFDisplayTwoUp];
  AUDIT(v.pageStyle==2,@"(A) context-menu Two Pages updates pageStyle");
  AUDIT(v.displaysRTL==d.previewDisplaysRTL && v.displaysAsBook==d.previewDisplaysAsBook,
        ([NSString stringWithFormat:@"(A) context-menu Two Pages shows resolved arrangement (view rtl=%d book=%d, resolved rtl=%d book=%d)",v.displaysRTL,v.displaysAsBook,d.previewDisplaysRTL,d.previewDisplaysAsBook]));
  [d changePreviewArrangement:Choice(@selector(changePreviewArrangement:),4)];
  // (B) position kept across layout x direction x cover for 1/odd/even page counts and rotated pages
  int bad=0,total=0;
  for(int pages=1;pages<=8;pages+=(pages==1?4:3)) for(int rot=0;rot<2;rot++){
   NSMutableData *data=[NSMutableData data];CGDataConsumerRef cons=CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
   CGRect box=CGRectMake(0,0,400,600);CGContextRef c=CGPDFContextCreate(cons,&box,NULL);
   for(int i=0;i<pages;i++){CGPDFContextBeginPage(c,NULL);CGContextFillRect(c,CGRectMake(40,150,320,280));CGPDFContextEndPage(c);}
   CGPDFContextClose(c);CGContextRelease(c);CGDataConsumerRelease(cons);
   PDFDocument *pd=[[PDFDocument alloc]initWithData:data]; if(rot) for(int i=0;i<pages;i+=2)[pd pageAtIndex:i].rotation=90;
   v.document=pd; v->resizeOption=2; v.scaleFactor=.6;
   for(int from=1;from<=4;from++) for(int to=1;to<=4;to++) for(int rtl=0;rtl<2;rtl++) for(int book=0;book<2;book++){
    if(from==to) continue;
    [d changePreviewLayout:Choice(@selector(changePreviewLayout:),from)];
    [d changePreviewArrangement:Choice(@selector(changePreviewArrangement:),rtl?2:1)];
    if(d.previewDisplaysAsBook!=book)[d changePreviewArrangement:Choice(@selector(changePreviewArrangement:),3)];
    PDFPage *target=[pd pageAtIndex:pages-1]; [v goToPage:target]; Pump();
    CGFloat s=v.scaleFactor;
    [d changePreviewLayout:Choice(@selector(changePreviewLayout:),to)]; Pump();
    total++;
    BOOL ok=[v.visiblePages containsObject:target] && fabs(v.scaleFactor-s)<.01 && v.pageStyle==to;
    if((to==2||to==4)) ok = ok && v.displaysRTL==rtl && v.displaysAsBook==book;
    if(!ok){bad++; printf("   case pages=%d rot=%d %d->%d rtl=%d book=%d visible=%d scale %.2f->%.2f nowpage=%lu\n",pages,rot,from,to,rtl,book,[v.visiblePages containsObject:target],s,v.scaleFactor,(unsigned long)[pd indexForPage:v.currentPage]+1);}
    // cover toggle keeps the page visible too
    [v goToPage:target]; Pump(); [d changePreviewArrangement:Choice(@selector(changePreviewArrangement:),3)]; Pump();
    total++; if(![v.visiblePages containsObject:target]){bad++; printf("   cover-toggle lost page pages=%d rot=%d style=%d rtl=%d\n",pages,rot,to,rtl);}
   }
  }
  AUDIT(bad==0,([NSString stringWithFormat:@"(B) last page stays visible, manual scale kept, arrangement applied: %d/%d failures",bad,total]));
  [d changePreviewArrangement:Choice(@selector(changePreviewArrangement:),4)];
  // (C) source reparse while open: view not refreshed until next layout/setDocument
  v.document=PDF(); [d changePreviewLayout:Choice(@selector(changePreviewLayout:),2)];
  [d comments:@""]; [v setupPageStyle];
  BOOL before=v.displaysAsBook; [d comments:@"% !TEX bookDisplay"];
  AUDIT(v.displaysAsBook==d.previewDisplaysAsBook,([NSString stringWithFormat:@"(C) reparsed bookDisplay reaches the view without another action (view=%d resolved=%d, before=%d)",v.displaysAsBook,d.previewDisplaysAsBook,before]));
  v.document=PDF();
  AUDIT(v.displaysAsBook==d.previewDisplaysAsBook,([NSString stringWithFormat:@"(C') after PDF reload (setDocument:) view book=%d resolved=%d",v.displaysAsBook,d.previewDisplaysAsBook]));
  [d comments:@""]; [v setupPageStyle];
  // (D) auto-fit recomputed for the new layout
  v->resizeOption=3; [v setupMagnificationStyle]; [d changePreviewLayout:Choice(@selector(changePreviewLayout:),1)]; Pump(); CGFloat s1=v.scaleFactor;
  [d changePreviewLayout:Choice(@selector(changePreviewLayout:),2)]; Pump(); CGFloat s2=v.scaleFactor;
  AUDIT(v.autoScales && s2<s1,([NSString stringWithFormat:@"(D) auto-fit recomputed single %.3f -> two-up %.3f",s1,s2]));
  // (E/F) Source reload is a no-op; real changes retain the point on the current page.
  int unchangedCases=0, pointCases=0, directionCases=0;
  NSArray *reloadSources=@[@"",@"% !TEX bookDisplay\n% !TEX PageDirectionR2L",@"% !TEX PageDirectionR2L",@"% !TEX bookDisplay",@"",@""];
  for(int source=0;source<6;source++) for(int style=1;style<=4;style++) for(int k=0;k<3;k++) for(int where=0;where<2;where++) {
   [d changePreviewArrangement:Choice(@selector(changePreviewArrangement:),4)]; [d comments:reloadSources[source]];
   v.document=source==4 ? DirectedPDF(@"/ViewerPreferences << /Direction /R2L >>") : PDF();
   if(source==5){[d changePreviewArrangement:Choice(@selector(changePreviewArrangement:),2)];[d changePreviewArrangement:Choice(@selector(changePreviewArrangement:),3)];}
   [d changePreviewLayout:Choice(@selector(changePreviewLayout:),style)];
   v->resizeOption=2; v.scaleFactor=(k==0?.6:(k==1?1.5:2.5)); Pump();
   PDFPage *p=[v.document pageAtIndex:MIN(3,v.document.pageCount-1)];
   [v goToDestination:[[PDFDestination alloc]initWithPage:p atPoint:NSMakePoint(120,where?40:330)]]; Pump();
   NSClipView *clip=v.documentView.enclosingScrollView.contentView;
   NSRect before=clip.bounds; PDFPage *current=v.currentPage;
   [d comments:reloadSources[source]]; Pump();
   Check(NSEqualRects(before,clip.bounds) && v.currentPage==current,@"Unchanged source reload preserves exact viewport and page");
   Check(v.displaysRTL==d.previewDisplaysRTL && v.displaysAsBook==d.previewDisplaysAsBook,@"Reload preserves resolved arrangement"); unchangedCases++;
  }
  // (G) Check a direction-only action before a cover or layout action can mask it.
  for(int style=1;style<=4;style++) for(int book=0;book<2;book++) for(int rtl=0;rtl<2;rtl++) {
   [d changePreviewArrangement:Choice(@selector(changePreviewArrangement:),4)];
   [d comments:book?@"% !TEX bookDisplay":@""];
   v.document=PDF(); [d changePreviewLayout:Choice(@selector(changePreviewLayout:),style)];
   [d changePreviewArrangement:Choice(@selector(changePreviewArrangement:),rtl?2:1)]; Pump();
   Check(v.displaysRTL==rtl && d.previewDisplaysRTL==rtl && v.displaysAsBook==book,@"Direction-only toolbar action reaches the view and preserves cover"); directionCases++;
  }
  for(int style=1;style<=4;style++) for(int op=0;op<2;op++) {
   [d changePreviewArrangement:Choice(@selector(changePreviewArrangement:),4)]; [d comments:@""];
   v.document=PDF(); [d changePreviewLayout:Choice(@selector(changePreviewLayout:),style)];
   v->resizeOption=2; v.scaleFactor=2.5; Pump();
   [v goToDestination:[[PDFDestination alloc]initWithPage:[v.document pageAtIndex:3] atPoint:NSMakePoint(120,200)]]; Pump();
   PDFDestination *before=v.currentDestination; PDFPage *current=v.currentPage;
   Check(before.page==current,@"High-zoom fixture is on the current page");
   [d changePreviewArrangement:Choice(@selector(changePreviewArrangement:),op?3:2)]; Pump();
   PDFDestination *after=v.currentDestination;
   Check(after.page==before.page && v.currentPage==current && fabs(after.point.x-before.point.x)<1 && fabs(after.point.y-before.point.y)<1,@"Arrangement preserves within-page position"); pointCases++;
  }
  printf("PASS: unchanged reload %d cases; high-zoom arrangement %d cases; direction-only %d cases\n",unchangedCases,pointCases,directionCases);
  Check(auditFail==0,@"Arrangement and last-page regression cases");
  #undef AUDIT
 }
