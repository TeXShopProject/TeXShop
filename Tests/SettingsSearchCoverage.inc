// SPDX-License-Identifier: GPL-2.0-or-later
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
 // Independent roles: a boolean's title is a row name (50), while
 // matrix/button choices (e.g. line-number size) remain choices (30).
 for(NSArray *contract in @[@[@"row.catalog.general.0.0",@"catalog.general.0.0.title",@50],@[@"row.catalog.editor.0.2",@"catalog.editor.0.2.title",@50]]){
  NSString *label=[resources localizedStringForKey:contract[1] value:nil table:@"SettingsCategories"];
  BOOL found=NO;for(TSSettingsSearchEntry *entry in index.entries)if([entry.targetIdentifier isEqual:contract[0]] && [entry.text isEqual:label]){Check(entry.weight==[contract[2]integerValue],@"Visible switch row names retain label weight");found=YES;}Check(found,@"Independent visible row is indexed");
 }
 BOOL hasChoices=NO;for(TSSettingsSearchEntry *entry in index.entries)if([entry.targetIdentifier isEqual:@"row.catalog.editor.0.3"] && entry.weight==30)hasChoices=YES;
 Check(hasChoices,@"Radio matrix options have choice weight");
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
 printf("SEARCH PASS %lu queries\n",(unsigned long)searchChecks);
}
