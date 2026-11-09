// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsSearch.h"
#define Check(ok) do { if(!(ok)){fprintf(stderr,"FAIL %d: %s\n",__LINE__,#ok);return 1;} } while(0)
@interface TextBundle:NSBundle @end
@implementation TextBundle
- (NSString *)localizedStringForKey:(NSString *)key value:(NSString *)value table:(NSString *)table {
 if([table isEqual:@"SettingsCategories"]){
  NSDictionary *labels=@{@"general":@"General",@"documents":@"Documents",@"editor":@"Editor",@"keyboard":@"Keyboard",@"catalog.general.0.0.title":@"shared",@"catalog.general.0.0.note":@"extra",@"catalog.general.0.1.title":@"unrelated",@"catalog.documents.0.0.title":@"shared",@"catalog.editor.0.0.title":@"straße"};
  return labels[key] ?: @"";
 }
 return @"";
}
@end
int main(void){@autoreleasepool{
 TSSettingsSearch *index=[[TSSettingsSearch alloc]initWithBundle:[TextBundle new] categoryOrder:@[@"general",@"documents",@"editor",@"keyboard"] commandNames:@[@"shared",@"ONLYCOMMAND",@"かたかな"]];
 TSSettingsSearchEntry *note=[[TSSettingsSearchEntry alloc]initWithCategory:@"general" target:@"fixture" text:@"Description is not a name" weight:TSSettingsSearchWeightDescription command:NO];
 TSSettingsSearchEntry *label=[[TSSettingsSearchEntry alloc]initWithCategory:@"general" target:@"fixture" text:@"Setting name" weight:TSSettingsSearchWeightLabel command:NO];
 Check([[[TSSettingsSearchResult alloc]initWithCategory:@"general" entries:@[note] score:0]title].length==0);
 TSSettingsSearchResult *named=[[TSSettingsSearchResult alloc]initWithCategory:@"general" entries:@[note,label] score:0];
 Check([named.title isEqual:@"Setting name"]);
 NSArray *hits=[index resultsForQuery:@"shared"];
 Check([[hits objectAtIndex:0] score]==70);
 Check([[[index resultsForQuery:@"shar"] objectAtIndex:0] score]==60);
 Check([[[index resultsForQuery:@"hare"] objectAtIndex:0] score]==50);
 Check(hits.count==3);Check([[hits[0] category] isEqual:@"general"]);Check([[hits[1] category] isEqual:@"documents"]);Check([[hits[2] category] isEqual:@"keyboard"]);
 Check([index resultsForQuery:@"Keyboard ONLYCOMMAND"].count==1);
 Check([index resultsForQuery:@"straße ONLYCOMMAND"].count==0);
 Check([index resultsForQuery:@"ＳＴＲＡＳＳＥ"].count==1);
 Check([index resultsForQuery:@"カタカナ"].count==1);
 Check([TSSettingsNormalizedText(@"école") isEqual:@"ecole"]);
 Check([TSSettingsNormalizedText(@"ＡＢＣ ﾊﾟｽ …") isEqual:@"abcパス..."]);
 Check([TSSettingsNormalizedText(@"a b\nc") isEqual:@"abc"]);
 Check(TSSettingsTextMatches(@"Café — Print PDF",TSSettingsQueryTokens(@"cafe—printpdf")));
 Check(![TSSettingsNormalizedText(@"パス") isEqual:TSSettingsNormalizedText(@"ハス")]);
 Check([TSSettingsNormalizedText(@"ソース") isEqual:@"ソース"]);
 Check(TSSettingsTextMatches(@"Café — Print PDF",TSSettingsQueryTokens(@"ＰＤＦ cafe")));
 Check(!TSSettingsTextMatches(@"Café — Print PDF",TSSettingsQueryTokens(@"PDF missing")));
 Check(TSSettingsQueryTokens(@" ").count==0);
 Check(TSSettingsTextMatches(@"保存する文字（か＋゛）",TSSettingsQueryTokens(@"保存する文字（か＋゛）")));
 Check(TSSettingsQueryTokens(@"か＋゛").count==1);
 Check(TSSettingsTextMatches(@"such as か + ゛) into が",TSSettingsQueryTokens(@"such as か + ゛) into が")));
 Check([index resultsForQuery:@"ONLYCOMMAND missing"].count==0);
 Check([index resultsForQuery:@"shared unrelated"].count==0);
 Check([index resultsForQuery:@"General shared"].count==1);
 NSArray *general=[index resultsForQuery:@"General"];
 Check(general.count==1);
 Check([general[0] targetIdentifier].length==0 && [[general[0] title]isEqual:@"General"]);
 Check([index resultsForQuery:@"General unrelated"].count==1);
 Check([[[index resultsForQuery:@"shared"] firstObject].targetIdentifier isEqual:@"row.catalog.general.0.0"]);
 Check([[[index resultsForQuery:@"shared"] firstObject].title isEqual:@"shared"]);
 NSArray *labels=@[@"コマンド",@"ショートカット",@"機能で検索",@"キーで検索",@"Search by Function",@"Search by Key"];
 NSMutableArray *sameTarget=[NSMutableArray array];for(NSString *text in labels)[sameTarget addObject:[[TSSettingsSearchEntry alloc]initWithCategory:@"keyboard" target:@"shared-target" text:text weight:TSSettingsSearchWeightLabel command:NO]];
 [index setValue:sameTarget forKey:@"entries"];
 for(NSString *text in labels)Check([[[index resultsForQuery:text]firstObject].title isEqual:text]);
 puts("PASS: normalization, item AND, category qualification, weighting, ties and command matching");
}return 0;}
