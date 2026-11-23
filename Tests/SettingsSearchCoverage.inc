// SPDX-License-Identifier: GPL-2.0-or-later
static NSView *SearchFind(NSView *view,NSString *identifier){if([view.identifier isEqual:identifier])return view;for(NSView *child in view.subviews){NSView *found=SearchFind(child,identifier);if(found)return found;}return nil;}
static NSUInteger searchChecks;
static NSView *searchExcludedView;
static BOOL HasCategory(TSSettingsSearch *index,NSString *query,NSString *category) {
 for(TSSettingsSearchResult *hit in [index resultsForQuery:query]) if([hit.category isEqual:category])return YES;
 return NO;
}
static void CheckSearchText(TSSettingsSearch *index,NSString *text,NSString *category) {
 if(!text.length)return;
 NSMutableString *hiragana=[text mutableCopy];
 for(NSUInteger i=0;i<hiragana.length;i++){unichar c=[hiragana characterAtIndex:i];if(c>=0x30a1 && c<=0x30f6){unichar h=c-0x60;[hiragana replaceCharactersInRange:NSMakeRange(i,1) withString:[NSString stringWithCharacters:&h length:1]];}}
 NSArray *variants=@[text,text.uppercaseString,hiragana,
  [text stringByApplyingTransform:NSStringTransformFullwidthToHalfwidth reverse:YES] ?: text,
  [[text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""],
  [text substringWithRange:NSMakeRange(text.length>2?(text.length-2)/2:0,MIN(2,text.length))]];
 for(NSString *query in variants){if(!TSSettingsQueryTokens(query).count)continue;Check(HasCategory(index,query,category),[NSString stringWithFormat:@"Search coverage %@ %@ / %@",category,text,query]);searchChecks++;}
}
static void SearchViews(NSView *view,NSString *category,TSSettingsSearch *index) {
 if(view==searchExcludedView || [view isKindOfClass:TSSettingsChangeNote.class])return;
 if([view isKindOfClass:NSSearchField.class])CheckSearchText(index,[(NSSearchField *)view placeholderString] ?: @"",category);
 CheckSearchText(index,view.toolTip ?: @"",category);
 BOOL data=[view.accessibilityIdentifier isEqual:@"settings.user-data"];
 if([view isKindOfClass:NSTextField.class] && [(NSTextField *)view isEditable])Check(data,@"Editable values carry user-data marker");

 if(data){
  if([view isKindOfClass:NSTextField.class]) [(NSTextField *)view setStringValue:@"/private/user-only-path-93762"];
  if([view isKindOfClass:NSPopUpButton.class])[(NSPopUpButton *)view addItemWithTitle:@"My Private Theme 93762"];
  return;
 }
 if([view isKindOfClass:NSPopUpButton.class])for(NSString *title in [(NSPopUpButton *)view itemTitles])CheckSearchText(index,title,category);
 else if([view isKindOfClass:NSButton.class] && [(NSButton *)view imagePosition]!=NSImageOnly)CheckSearchText(index,[(NSButton *)view title],category);
 else if([view isKindOfClass:NSMatrix.class])for(NSCell *cell in [(NSMatrix *)view cells])CheckSearchText(index,cell.title,category);
 else if([view isKindOfClass:NSTextField.class])CheckSearchText(index,[(NSTextField *)view stringValue],category);
 if([view isKindOfClass:NSSegmentedControl.class])for(NSInteger i=0;i<[(NSSegmentedControl *)view segmentCount];i++)CheckSearchText(index,[(NSSegmentedControl *)view labelForSegment:i] ?: @"",category);
 if([view isKindOfClass:NSSearchField.class])CheckSearchText(index,[(NSSearchField *)view placeholderString] ?: @"",category);
 if([view isKindOfClass:NSTableView.class]){for(NSTableColumn *column in [(NSTableView *)view tableColumns])CheckSearchText(index,column.title,category);return;}
 for(NSView *child in view.subviews)SearchViews(child,category,index);
}
static void SearchCoverage(NSDictionary<NSString *,NSViewController *> *panes,NSBundle *resources) {
 NSArray *order=@[@"general",@"documents",@"editor",@"spelling",@"appearance",@"preview",@"typesetting",@"console",@"keyboard",@"updates"];
 TSSettingsSearch *index=[[TSSettingsSearch alloc]initWithBundle:resources categoryOrder:order commandNames:@[@"Unique Command 93762"]];
 Check([TSSettingsNormalizedText(@"ＰＤＦ　Éditeur … はんかく ｶﾅ") isEqual:TSSettingsNormalizedText(@"pdf editeur ... ハンカク カナ")],@"Compatibility, kana, accents, whitespace and case");
 Check(![TSSettingsNormalizedText(@"パス") isEqual:TSSettingsNormalizedText(@"ハス")],@"Dakuten distinctions retained");
 for(NSString *year in @[@"2000–2001",@"2001–2013",@"2013–2014",@"2014–2026",@"2026–"]){
  BOOL found=NO;for(TSSettingsSearchResult *hit in [index resultsForQuery:year])if([hit.category isEqual:@"general"] && [hit.targetIdentifier isEqual:@"DockIconChoices"])found=YES;
  Check(found,@"Every visible Dock year finds its choice row");
 }
 // Independent roles: a boolean's title is a row name (50), while
 // matrix/button choices (e.g. line-number size) remain choices (30).
 for(NSArray *contract in @[@[@"row.catalog.general.0.0",@"catalog.general.0.0.title",@50],@[@"row.catalog.editor.0.2",@"catalog.editor.0.2.title",@50]]){
  NSString *label=[resources localizedStringForKey:contract[1] value:nil table:@"SettingsCategories"];
  BOOL found=NO;for(TSSettingsSearchEntry *entry in index.entries)if([entry.targetIdentifier isEqual:contract[0]] && [entry.text isEqual:label] && entry.weight==[contract[2]integerValue]){found=YES;}Check(found,@"Visible switch row names retain label weight");
 }
 // The BibDesk switch moved to Label and Citation Key Completion: its words lead to its new row,
 // and the mark switch of Command Completion is found by its name.
 {
  BOOL moved=NO,old=NO,marks=NO;
  for(TSSettingsSearchResult *hit in [index resultsForQuery:@"BibDesk"]){if([hit.targetIdentifier isEqual:@"row.catalog.keyboard.3.0"])moved=YES;if([hit.targetIdentifier isEqual:@"row.catalog.keyboard.1.1"])old=YES;}
  for(TSSettingsSearchResult *hit in [index resultsForQuery:[resources localizedStringForKey:@"catalog.keyboard.1.3.title" value:nil table:@"SettingsCategories"]])if([hit.targetIdentifier isEqual:@"row.catalog.keyboard.1.3"])marks=YES;
  Check(moved && !old,@"BibDesk finds the switch in Label and Citation Key Completion");
  Check(marks,@"The mark switch is found by its name");
 }
 // The Paste column of key bindings and the note under the list lead to the key binding list
 // itself: the column name as a choice, the note as a description.
 {
  NSString *column=[resources localizedStringForKey:@"Paste" value:nil table:@"Localizable"];
  NSString *note=[resources localizedStringForKey:@"Check “Paste” to also apply the replacement to pasted text." value:nil table:@"Localizable"];
  for(NSArray *pair in @[@[column,@(TSSettingsSearchWeightChoice)],@[note,@(TSSettingsSearchWeightDescription)]]){
   BOOL indexed=NO,reached=NO;
   for(TSSettingsSearchEntry *entry in index.entries)if([entry.category isEqual:@"keyboard"] && [entry.targetIdentifier isEqual:@"row.catalog.keyboard.0.1"] && [entry.text isEqual:pair[0]] && entry.weight==[pair[1] integerValue])indexed=YES;
   for(TSSettingsSearchResult *hit in [index resultsForQuery:pair[0]])if([hit.category isEqual:@"keyboard"] && [hit.targetIdentifier isEqual:@"row.catalog.keyboard.0.1"])reached=YES;
   Check(indexed,[NSString stringWithFormat:@"Key binding list indexes %@ with its role",pair[0]]);
   Check(reached,[NSString stringWithFormat:@"%@ finds the key binding list",pair[0]]);
  }
 }
 BOOL hasChoices=NO;for(TSSettingsSearchEntry *entry in index.entries)if([entry.targetIdentifier isEqual:@"row.catalog.editor.0.3"] && entry.weight==30)hasChoices=YES;
 Check(hasChoices,@"Radio matrix options have choice weight");
 // Every target has a fixed setting name, even when found through its help text.
 for(TSSettingsSearchEntry *entry in index.entries){
  if(!entry.targetIdentifier.length || [entry.targetIdentifier isEqual:@"category.description"])continue;
  BOOL matched=NO;
  for(TSSettingsSearchResult *result in [index resultsForQuery:entry.text]){
   if(![result.category isEqual:entry.category] || ![result.entries containsObject:entry])continue;
   matched=YES;
   Check(result.title.length>0,@"Every result has an explicit setting name");
   if([entry.targetIdentifier hasPrefix:@"row.catalog."]){
    NSView *row=SearchFind(panes[entry.category].view,entry.targetIdentifier);
    NSTextField *name=(NSTextField *)SearchFind(row,@"label.catalog-row");
    if(name.stringValue.length)Check([result.title isEqual:name.stringValue],@"Result name is the visible row name, never its note");
   }
   if([entry.targetIdentifier isEqual:@"DockIconChoices"])Check([result.title isEqual:[resources localizedStringForKey:@"group.general.6.title" value:nil table:@"SettingsCategories"]],@"Dock result uses the visible group name, never removed guidance");
  }
  Check(matched,@"Every indexed target is found by each of its entries");
 }
 // Labels sharing a target must use the name that matches the actual query.
 for(TSSettingsSearchEntry *entry in index.entries)if(entry.weight==TSSettingsSearchWeightLabel && ![entry.targetIdentifier hasPrefix:@"row.catalog."] && ![entry.targetIdentifier isEqual:@"DockIconChoices"]){
  BOOL found=NO;for(TSSettingsSearchResult *result in [index resultsForQuery:entry.text])if([result.entries containsObject:entry] && [result.category isEqual:entry.category]){
   Check([TSSettingsNormalizedText(result.title) isEqual:TSSettingsNormalizedText(entry.text)],[NSString stringWithFormat:@"Matching labels win for %@: expected %@, got %@",entry.targetIdentifier,entry.text,result.title]);found=YES;
  }Check(found,@"Each visible label finds its own target");
 }
 // A category match is one doorway, not a match on every unrelated row.
 TSSettingsSearch *isolated=[[TSSettingsSearch alloc]initWithBundle:resources categoryOrder:@[@"general"] commandNames:@[]];
 NSMutableArray *synthetic=[NSMutableArray array];
 for(NSArray *data in @[@[@"",@"Categoryneedle",@(TSSettingsSearchWeightCategory)],@[@"category.description",@"Summaryneedle",@20],@[@"row.alpha",@"Alpha option",@50],@[@"row.beta",@"Beta option",@50]])
  [synthetic addObject:[[TSSettingsSearchEntry alloc]initWithCategory:@"general" target:data[0] text:data[1] weight:[data[2]integerValue] command:NO]];
 [isolated setValue:synthetic forKey:@"entries"];
 for(NSString *query in @[@"Categoryneedle",@"Summaryneedle"]){
  NSArray<TSSettingsSearchResult *> *hits=[isolated resultsForQuery:query];
  Check(hits.count==1 && !hits.firstObject.targetIdentifier.length && [hits.firstObject.title isEqual:@"Categoryneedle"],@"Category-only matches produce one named category doorway");
 }
 NSArray<TSSettingsSearchResult *> *qualified=[isolated resultsForQuery:@"Categoryneedle Alpha"];
 Check(qualified.count==1 && [qualified.firstObject.targetIdentifier isEqual:@"row.alpha"],@"Category words qualify only the matching item");
 Check([isolated resultsForQuery:@"Alpha Beta"].count==0,@"Unrelated items cannot complete an AND query");
 for(NSArray *targets in @[@[@"settings.L8Q-Ov-EVr",@"settings.0fE-JX-Dl8",@"settings.2U5-cN-QJw"],@[@"settings.Kx3-n3-dsv",@"settings.ooP-O9-ggT",@"settings.c9R-58-ggg"],@[@"settings.FoL-zy-obh",@"settings.GBU-aF-4Dc"],@[@"settings.hCM-4U-XkM",@"settings.cnt-Xt-iQF"]]){
  NSString *label=nil;for(TSSettingsSearchEntry *entry in index.entries)if([entry.targetIdentifier isEqual:targets[0]] && entry.weight==50){label=entry.text;break;}
  NSUInteger matches=0;NSMutableSet *found=[NSMutableSet set];
  for(TSSettingsSearchResult *hit in [index resultsForQuery:label]){
   BOOL row=NO;for(TSSettingsSearchEntry *entry in hit.entries)if([targets containsObject:entry.targetIdentifier]){row=YES;[found addObject:entry.targetIdentifier];}
   if(row)matches++;
  }
  Check(matches==1 && found.count==targets.count,@"A visual theme row has one result retaining all color targets");
 }
 Check([index resultsForQuery:@"unfindable-93762"].count==0,@"Unknown query has no results");
 Check([index resultsForQuery:@"\u3000 \n"].count==0,@"Empty normalized query has no results");
 for(NSString *category in order){
  CheckSearchText(index,panes[category].title ?: @"",category);
  Check([index categoryDescription:category].length>0,@"Category descriptions come from localized group headings");
  CheckSearchText(index,[index categoryDescription:category],category);
  SearchViews(panes[category].view,category,index);
  NSArray *entries=[index.entries filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(TSSettingsSearchEntry *e,NSDictionary *bindings){return [e.category isEqual:category];}]];
  for(TSSettingsSearchEntry *entry in entries)Check(HasCategory(index,[NSString stringWithFormat:@"%@ %@",[index categoryDescription:category],entry.text],category),@"Item queries may include their category");
 }
 Check(HasCategory(index,@"Unique Command 93762",@"keyboard"),@"Command names indexed");
 Check(![index resultsForQuery:@"/private/user-only-path-93762"].count && ![index resultsForQuery:@"My Private Theme 93762"].count,@"No user values in index");
 // The former names of the otf conversion and its group, as each language showed them
 // before they were renamed, still find the setting under its current name.
 NSDictionary<NSString *,NSArray<NSString *> *> *formerOtfNames=@{
  @"Base":@[@"otf Package Support",@"pTeX support (for Japan)",@"otf package support"],
  @"de":@[@"Unterstützung für das otf-Paket",@"pTeX-Unterstützung (für japanische Benutzer)"],
  @"es":@[@"Compatibilidad con el paquete otf",@"Soporte pTeX (japonés)"],
  @"fr":@[@"Prise en charge du paquet otf",@"Support pTeX (Japon)"],
  @"it":@[@"Supporto per il pacchetto otf",@"Supporto pTeX (solo giapponese)"],
  @"ja":@[@"otfパッケージ対応",@"pTeXサポート（日本用）",@"pTeX サポート"],
  @"ko":@[@"otf 패키지 지원",@"일본어 pTeX 지원"],
  @"nl":@[@"Ondersteuning voor het otf-pakket",@"pTeX-ondersteuning (voor Japan)"],
  @"pt":@[@"Suporte ao pacote otf",@"suporte a pTeX (para usuários no Japão)"],
  @"pt-PT":@[@"Suporte para o pacote otf",@"Suporte a pTeX (para o Japão)"],
  @"ro":@[@"Suport pentru pachetul otf",@"Suport pTeX (pentru Japonia)"],
  @"zh_CN":@[@"otf宏包支持",@"pTeX支持 (仅日语用户)"]};
 NSString *otfLanguage=resources.bundlePath.lastPathComponent.stringByDeletingPathExtension;
 NSString *otfTitle=[resources localizedStringForKey:@"catalog.typesetting.9.0.title" value:nil table:@"SettingsCategories"];
 for(NSString *query in [formerOtfNames[otfLanguage] ?: @[] arrayByAddingObject:@"pTeX"]){
  BOOL found=NO;
  for(TSSettingsSearchResult *hit in [index resultsForQuery:query])
   if([hit.category isEqual:@"typesetting"] && [hit.targetIdentifier isEqual:@"row.catalog.typesetting.9.0"] && [hit.title isEqual:otfTitle])found=YES;
  Check(found,[NSString stringWithFormat:@"Former otf name finds the renamed setting: %@ (%@)",query,otfLanguage]);searchChecks++;
 }
 // The former name of the Key Bindings group, where a language renamed it, still finds both rows of the group:
 // the switch and the list of key bindings.
 {
  NSString *former=[resources localizedStringForKey:@"group.bindings.former" value:@"" table:@"SettingsCategories"];
  if(former.length && ![former isEqual:@"group.bindings.former"]){
   BOOL row0=NO,row1=NO;
   for(TSSettingsSearchResult *hit in [index resultsForQuery:former]){
    if([hit.targetIdentifier isEqual:@"row.catalog.keyboard.0.0"])row0=YES;
    if([hit.targetIdentifier isEqual:@"row.catalog.keyboard.0.1"])row1=YES;
   }
   Check(row0&&row1,[NSString stringWithFormat:@"Former Key Bindings name finds the switch and the list: %@ (%@)",former,otfLanguage]);searchChecks++;
  }
 }
 // The system color switches of the cursor and the selection share their title: each has one result, named after
 // its color, that leads to it, whether the title, a part of it or the whole name is searched.
 {
  NSString *title=[resources localizedStringForKey:@"catalog.appearance.3.0.switch" value:nil table:@"SettingsCategories"];
  NSString *cursor=[NSString stringWithFormat:@"%@ — %@",[resources localizedStringForKey:@"catalog.appearance.3.0.item.0" value:nil table:@"SettingsCategories"],title];
  NSString *selection=[NSString stringWithFormat:@"%@ — %@",[resources localizedStringForKey:@"catalog.appearance.3.0.item.3" value:nil table:@"SettingsCategories"],title];
  NSString *part=[title substringToIndex:MAX((NSUInteger)2,title.length/2)];
  for(NSString *query in @[title,part,cursor,selection]){
   NSMutableDictionary<NSString *,NSString *> *names=[NSMutableDictionary dictionary];NSUInteger count=0;
   for(TSSettingsSearchResult *hit in [index resultsForQuery:query])
    if([hit.targetIdentifier isEqual:@"settings.cK4-Ip-S8y"] || [hit.targetIdentifier isEqual:@"settings.sK6-Sl-T1y"]){count++;names[hit.targetIdentifier]=hit.title;}
   // The title finds both; a whole name finds its own switch (the other one too where a word of the name is also
   // in the category's text, as Auswahl is in German), each result under its own name.
   BOOL both=[query isEqual:title] || [query isEqual:part];
   NSString *own=[query isEqual:cursor]?@"settings.cK4-Ip-S8y":[query isEqual:selection]?@"settings.sK6-Sl-T1y":nil;
   Check(count==names.count && (!names[@"settings.cK4-Ip-S8y"] || [names[@"settings.cK4-Ip-S8y"] isEqual:cursor]) && (!names[@"settings.sK6-Sl-T1y"] || [names[@"settings.sK6-Sl-T1y"] isEqual:selection]) && (both?names.count==2:names[own]!=nil),
         [NSString stringWithFormat:@"The system color switches are told apart in the results of %@: %@",query,names]);
   searchChecks++;
  }
 }
 printf("SEARCH PASS %lu queries\n",(unsigned long)searchChecks);
}
