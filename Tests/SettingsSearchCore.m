// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsSearch.h"
#define Check(ok) do { if(!(ok)){fprintf(stderr,"FAIL %d: %s\n",__LINE__,#ok);return 1;} } while(0)
@interface TextBundle:NSBundle @end
@implementation TextBundle
- (NSString *)localizedStringForKey:(NSString *)key value:(NSString *)value table:(NSString *)table {
 if([table isEqual:@"SettingsCategories"]){if([key isEqual:@"general"] || [key isEqual:@"documents"])return @"shared";if([key isEqual:@"editor"])return @"straße";}
 return value ?: key;
}
@end
int main(void){@autoreleasepool{
 TSSettingsSearch *index=[[TSSettingsSearch alloc]initWithBundle:[TextBundle new] categoryOrder:@[@"general",@"documents",@"editor",@"keyboard"] commandNames:@[@"shared",@"ONLYCOMMAND",@"かたかな"]];
 NSArray *hits=[index resultsForQuery:@"shared"];
 Check(hits.count==3);Check([[hits[0] category] isEqual:@"general"]);Check([[hits[1] category] isEqual:@"documents"]);Check([[hits[2] category] isEqual:@"keyboard"]);
 Check([index resultsForQuery:@"shared ONLYCOMMAND"].count==1);
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
 Check([index resultsForQuery:@"ONLYCOMMAND missing"].count==0);
 puts("PASS: normalization, category AND, weighting, ties and function matching");
}return 0;}
