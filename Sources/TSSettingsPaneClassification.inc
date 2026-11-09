// SPDX-License-Identifier: GPL-2.0-or-later
// The approved catalog describes presentation; original controls own all values/actions.
#include "TSSettingsCatalogLayout.inc"
static id TSCatalogRequired(id value) { if(value==nil) [NSException raise:NSInternalInconsistencyException format:@"Incomplete settings catalog"]; return (id _Nonnull)value; }
@interface TSSettingsProfilePresentation : NSView
@property (strong) NSPopUpButton *popup;
@property (copy) NSArray<NSMenuItem *> *proposals;
- (instancetype)initWithPopup:(NSPopUpButton *)popup title:(NSString *)title;
@end
@implementation TSSettingsProfilePresentation
- (instancetype)initWithPopup:(NSPopUpButton *)popup title:(NSString *)title
{
    self=[super initWithFrame:NSZeroRect]; if(!self)return nil;
    self.translatesAutoresizingMaskIntoConstraints=NO; _popup=popup;
    NSMutableArray *items=[NSMutableArray array];
    for(NSMenuItem *item in popup.itemArray) if(item.tag>0) [items addObject:[item copy]];
    _proposals=[items copy];
    [popup removeAllItems]; popup.pullsDown=NO; popup.autoenablesItems=NO;
    for(NSMenuItem *item in items){[popup addItemWithTitle:item.title];popup.lastItem.tag=item.tag;}
    popup.target=nil;popup.action=NULL;
    NSButton *apply=[NSButton buttonWithTitle:title target:self action:@selector(apply:)];apply.identifier=@"settings.apply-profile";
    [TSPrefPaneLayout attachRows:@[[TSPrefPaneLayout stackWithViews:@[popup,apply] orientation:NSUserInterfaceLayoutOrientationHorizontal]] toView:self];
    return self;
}
- (void)apply:(id)sender
{
    for(NSMenuItem *item in self.proposals) if(item.tag==self.popup.selectedTag){SEL action=item.action;if(action)[NSApp sendAction:action to:item.target from:item];return;}
}
@end
@interface TSSettingsPaneComposer : NSObject
+ (NSDictionary<TSSettingsCategoryID, NSViewController *> *)compose:(NSArray<TSPrefPaneController *> *)panes preferences:(TSPreferences *)preferences;
@end
@implementation TSSettingsPaneComposer
+ (void)collect:(NSView *)view into:(NSMutableDictionary<NSString *, NSView *> *)views
{
    NSString *identifier=view.identifier;if(identifier)views[identifier]=view;
    for(NSView *child in view.subviews)[self collect:child into:views];
}
+ (NSView *)take:(NSString *)identifier from:(NSMutableDictionary<NSString *, NSView *> *)views
{
    NSView *view=views[identifier];
    if(!view)[NSException raise:NSInternalInconsistencyException format:@"Missing catalog control %@",identifier];
    [views removeObjectForKey:identifier];[view removeFromSuperview];[view removeConstraints:view.constraints];
    view.translatesAutoresizingMaskIntoConstraints=NO;view.hidden=NO;
    if([view isKindOfClass:NSControl.class])view.accessibilityElement=YES;
    return view;
}
+ (void)splitMatrix:(NSMatrix *)matrix identifiers:(NSArray<NSString *> *)identifiers into:(NSMutableDictionary<NSString *, NSView *> *)views
{
    NSArray<NSCell *> *cells=[matrix.cells copy];
    if(cells.count!=identifiers.count)[NSException raise:NSInternalInconsistencyException format:@"Unexpected settings matrix cells"];
    while(matrix.numberOfRows)[matrix removeRow:0];[matrix removeFromSuperview];
    for(NSUInteger i=0;i<cells.count;i++){NSButton *button=[NSButton new];button.cell=cells[i];button.identifier=identifiers[i];views[identifiers[i]]=button;}
}
+ (NSTextField *)label:(NSString *)text small:(BOOL)small
{
    TSSettingsLabel *label=[TSSettingsLabel wrappingLabelWithString:text];label.translatesAutoresizingMaskIntoConstraints=NO;
    label.font=[NSFont systemFontOfSize:small?NSFont.smallSystemFontSize:NSFont.systemFontSize];
    label.enabledTextColor=small?NSColor.secondaryLabelColor:NSColor.labelColor;
    [label setContentCompressionResistancePriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];return label;
}
+ (NSView *)horizontal:(NSArray<NSView *> *)views spacing:(CGFloat)spacing
{
    NSStackView *stack=[TSPrefPaneLayout stackWithViews:views orientation:NSUserInterfaceLayoutOrientationHorizontal];stack.spacing=spacing;return stack;
}
+ (void)prepare:(NSView *)view
{
    view.translatesAutoresizingMaskIntoConstraints=NO;
    if([view isKindOfClass:NSPopUpButton.class] || [view isKindOfClass:NSButton.class]) {
        ((NSControl *)view).controlSize=NSControlSizeRegular;
        ((NSControl *)view).font=[NSFont systemFontOfSize:NSFont.systemFontSize];
    }
    if([view isKindOfClass:NSColorWell.class]){
        ((NSColorWell *)view).colorWellStyle=NSColorWellStyleMinimal;
        [view.widthAnchor constraintEqualToConstant:44].active=YES;[view.heightAnchor constraintEqualToConstant:24].active=YES;
    }
    if([view isKindOfClass:NSTextField.class] && ((NSTextField *)view).editable){
        view.accessibilityIdentifier=@"settings.user-data";
        [view setContentHuggingPriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [view setContentCompressionResistancePriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
}
+ (NSGridView *)grid:(NSArray<NSView *> *)cells columns:(NSUInteger)columns spacing:(CGFloat)spacing
{
    NSMutableArray *rows=[NSMutableArray array];
    for(NSUInteger i=0;i<cells.count;i+=columns){NSMutableArray *row=[NSMutableArray array];for(NSUInteger j=0;j<columns;j++)[row addObject:i+j<cells.count?cells[i+j]:NSGridCell.emptyContentView];[rows addObject:row];}
    NSGridView *grid=[NSGridView gridViewWithViews:rows];grid.translatesAutoresizingMaskIntoConstraints=NO;grid.columnSpacing=spacing;grid.rowSpacing=10;grid.rowAlignment=NSGridRowAlignmentFirstBaseline;return grid;
}
+ (NSView *)buildRow:(NSDictionary *)model views:(NSMutableDictionary<NSString *,NSView *> *)views text:(NSString *(^)(NSString *))text
{
    NSString *kind=model[@"kind"],*title=text(model[@"title"]),*note=text(model[@"note"]);
    NSUInteger indent=[model[@"indent"] unsignedIntegerValue];
    NSMutableArray<NSView *> *controls=[NSMutableArray array];
    for(NSString *key in model[@"controls"]){NSView *control=[self take:key from:views];[self prepare:control];[controls addObject:control];}
    NSView *accessory=nil,*row=nil;
    if([kind isEqual:@"switch"] || [kind isEqual:@"switchpopup"]){
        NSButton *source=(NSButton *)controls.firstObject;source.title=title;
        NSView *toggle=[TSPrefPaneLayout switchForButton:source];
        accessory=[kind isEqual:@"switchpopup"]?[self horizontal:@[controls[1],toggle] spacing:12]:toggle;
    }else if([kind isEqual:@"popup"]){
        if([controls.firstObject.identifier isEqual:@"settings.1089"]){
            accessory=[[TSSettingsProfilePresentation alloc]initWithPopup:(NSPopUpButton *)controls.firstObject title:text(model[@"button"])];
        }else{
            BOOL pair=[controls.firstObject.identifier isEqual:@"settings.G6V-Sw-jFT"] || [controls.firstObject.identifier isEqual:@"settings.iRm-g2-CpD"];
            NSView *choice=[TSPrefPaneLayout choiceForControls:pair?controls:@[TSCatalogRequired(controls.firstObject)]];
            choice.accessibilityLabel=title;
            if(!pair && controls.count>1){((NSButton *)controls[1]).title=text(model[@"button"]);accessory=[self horizontal:@[choice,controls[1]] spacing:8];}else accessory=choice;
        }
    }else if([kind isEqual:@"text"] || [kind isEqual:@"path"]){
        NSTextField *field=(NSTextField *)controls.firstObject;field.accessibilityLabel=title;
        if([kind isEqual:@"text"]){field.alignment=NSTextAlignmentRight;[field.widthAnchor constraintEqualToConstant:64].active=YES;}
        else{field.lineBreakMode=NSLineBreakByTruncatingMiddle;[field.widthAnchor constraintGreaterThanOrEqualToConstant:150].active=YES;}
        NSMutableArray *parts=[NSMutableArray arrayWithObject:field];
        if([model[@"unit"] length])[parts addObject:[self label:text(model[@"unit"]) small:YES]];
        if(controls.count>1){((NSButton *)controls[1]).title=text(model[@"button"]);[parts addObject:controls[1]];}
        accessory=parts.count==1?field:[self horizontal:parts spacing:8];
    }else if([kind isEqual:@"font"]){
        controls.firstObject.accessibilityIdentifier=@"settings.user-data";
        ((NSTextField *)controls.firstObject).textColor=NSColor.secondaryLabelColor;
        accessory=[self horizontal:controls spacing:8];
    }else if([kind isEqual:@"button"] || [kind isEqual:@"link"] || [kind isEqual:@"radio"]){
        NSButton *button=(NSButton *)controls.firstObject;button.title=title;
        if([kind isEqual:@"radio"]){
            // A check cell from a nib retains its checkbox bezel when only its
            // type changes. Replace the cell, retaining the typed outlet itself.
            NSButton *radio=[NSButton radioButtonWithTitle:title target:button.target action:button.action];
            radio.state=button.state;radio.tag=button.tag;radio.enabled=button.enabled;
            button.cell=radio.cell;
        }
        if([kind isEqual:@"link"]){button.bordered=NO;button.attributedTitle=[[NSAttributedString alloc]initWithString:title attributes:@{NSForegroundColorAttributeName:NSColor.linkColor,NSFontAttributeName:[NSFont systemFontOfSize:NSFont.systemFontSize]}];}
        NSView *content=button;
        if(note.length || [kind isEqual:@"radio"]){
            NSStackView *stack=[TSPrefPaneLayout stackWithViews:@[button] orientation:NSUserInterfaceLayoutOrientationVertical];
            stack.identifier=@"label.catalog-stack";stack.spacing=2;
            if(note.length)[stack addArrangedSubview:[self label:note small:YES]];
            for(NSView *child in stack.arrangedSubviews)[child.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;
            content=stack;
        }
        row=[TSPrefPaneLayout catalogContent:content trailing:[kind isEqual:@"button"] && !indent indent:indent];
    }else if([kind isEqual:@"description"]){row=[TSPrefPaneLayout catalogContent:[self label:title small:YES] trailing:NO indent:indent];
    }else if([kind isEqual:@"buttons"] || [kind isEqual:@"checks"] || [kind isEqual:@"checkgrid"]){
        for(NSUInteger i=0;i<controls.count;i++)((NSButton *)controls[i]).title=text(model[@"choices"][i]);
        NSView *body=[kind isEqual:@"checkgrid"]?[self grid:controls columns:3 spacing:28]:[self horizontal:controls spacing:[kind isEqual:@"checks"]?14:8];
        if([kind isEqual:@"checks"])accessory=body;else row=[TSPrefPaneLayout catalogContent:body trailing:[kind isEqual:@"buttons"] indent:indent];
    }else if([kind isEqual:@"color"]){accessory=controls.firstObject;
    }else if([kind isEqual:@"colors"] || [kind isEqual:@"colortable"]){
        NSMutableArray *cells=[NSMutableArray array];
        BOOL table=[kind isEqual:@"colortable"];
        if(table){[cells addObject:NSGridCell.emptyContentView];for(NSString *column in model[@"columns"])[cells addObject:[self label:text(column) small:YES]];}
        for(NSDictionary *item in model[@"items"]){
            NSTextField *label=[self label:text(item[@"title"]) small:NO];
            NSMutableArray *wells=[NSMutableArray array];
            for(NSString *key in item[@"controls"]){NSView *well=[self take:key from:views];[self prepare:well];well.accessibilityLabel=label.stringValue;[wells addObject:well];}
            if(table){[cells addObject:label];NSUInteger i=0;for(NSNumber *occupied in item[@"occupied"])[cells addObject:occupied.boolValue?wells[i++]:NSGridCell.emptyContentView];}
            else [cells addObject:[self horizontal:@[TSCatalogRequired(wells.firstObject),label] spacing:8]];
        }
        NSGridView *grid=[self grid:cells columns:table?4:2 spacing:table?28:24];
        if(table){grid.rowSpacing=8;grid.rowAlignment=NSGridRowAlignmentNone;[grid columnAtIndex:0].width=110;for(NSInteger c=1;c<4;c++)[grid columnAtIndex:c].xPlacement=NSGridCellPlacementCenter;for(NSInteger r=0;r<grid.numberOfRows;r++)[grid rowAtIndex:r].yPlacement=NSGridCellPlacementCenter;}
        else { [grid columnAtIndex:0].width=230; [grid columnAtIndex:1].width=230; }
        row=[TSPrefPaneLayout catalogContent:grid trailing:NO indent:indent];
    }
    if(!row && accessory)row=[TSPrefPaneLayout catalogRowWithTitle:title note:note accessory:accessory expands:[kind isEqual:@"path"] indent:indent];
    if(row && controls.count && [controls.firstObject isKindOfClass:NSControl.class]) {
        NSMutableArray<NSView *> *labels=[NSMutableArray arrayWithArray:row.subviews];
        while(labels.count){NSView *candidate=labels.lastObject;[labels removeLastObject];
            if([candidate isKindOfClass:NSTextField.class] && !((NSTextField *)candidate).editable && ([candidate.identifier isEqual:@"label.catalog-row"] || [candidate.identifier isEqual:@"note.catalog-row"]))
                [candidate bind:NSEnabledBinding toObject:TSCatalogRequired(controls.firstObject) withKeyPath:@"enabled" options:nil];
            [labels addObjectsFromArray:candidate.subviews];
        }
    }
    if(row)row.identifier=[@"row." stringByAppendingString:TSCatalogRequired(model[@"id"])];
    return row;
}
+ (NSDictionary<TSSettingsCategoryID,NSViewController *> *)compose:(NSArray<TSPrefPaneController *> *)panes preferences:(TSPreferences *)preferences
{
    NSMutableDictionary *views=[NSMutableDictionary dictionary];NSBundle *bundle=NSBundle.mainBundle;
    for(TSPrefPaneController *pane in panes){[self collect:pane.view into:views];if(pane.nibBundle)bundle=pane.nibBundle;}
    NSString *(^text)(NSString *)=^NSString *(NSString *key){return key.length?[bundle localizedStringForKey:key value:key table:@"SettingsCategories"]:@"";};
    [self splitMatrix:(NSMatrix *)[self take:@"settings.621" from:views] identifiers:@[@"settings.cell.839",@"settings.cell.cgA-o7-Bdw",@"settings.cell.f1k-jx-ley",@"settings.cell.840",@"settings.cell.841",@"settings.cell.842",@"settings.cell.843",@"settings.cell.844",@"settings.cell.845",@"settings.cell.846",@"settings.cell.XoX-gZ-pO3",@"settings.cell.PhR-Vr-jce",@"settings.cell.CPb-hk-Gqb"] into:views];
    [self splitMatrix:(NSMatrix *)[self take:@"settings.cp7-bc-avh" from:views] identifiers:@[@"settings.cell.teg-0p-Q8J",@"settings.cell.3eF-XA-ahc",@"settings.cell.8Wq-gx-FqO"] into:views];
    NSButton *legacy=[NSButton radioButtonWithTitle:@"" target:preferences action:@selector(legacySpellCheckPressed:)];legacy.identifier=@"settings.legacy-spelling";preferences.legacySpellCheckButton=legacy;views[@"settings.legacy-spelling"]=legacy;
    NSArray *newIDs=@[@"settings.edit-bindings",@"settings.edit-completion",@"settings.hidden-settings-help",@"settings.save-theme"];
    SEL actions[]={@selector(editKeyBindings:),@selector(openCommandCompletionList:),@selector(displayCommentLines:),@selector(SaveEditedStyle:)};
    for(NSUInteger i=0;i<newIDs.count;i++){NSButton *b=[NSButton buttonWithTitle:@"" target:i==1?nil:preferences action:actions[i]];b.identifier=newIDs[i];views[newIDs[i]]=b;}
    NSMutableDictionary *result=[NSMutableDictionary dictionary];
    for(NSDictionary *category in TSSettingsCatalogLayout()){
        NSString *cid=category[@"id"];NSMutableArray *groups=[NSMutableArray array];
        for(NSDictionary *model in category[@"groups"]){
            TSSettingsGroupView *group=[TSSettingsGroupView new];group.identifier=model[@"id"];group.title=text(model[@"title"]);group.accessibilityLabel=group.title;
            NSTextField *heading=[self label:group.title small:NO];heading.font=[NSFont boldSystemFontOfSize:NSFont.systemFontSize];heading.identifier=[@"heading." stringByAppendingString:TSCatalogRequired(group.identifier)];
            NSMutableArray *rows=[NSMutableArray arrayWithObject:heading];
            for(NSDictionary *row in model[@"rows"]){NSView *built=[self buildRow:row views:views text:text];if(built)[rows addObject:built];}
            NSView *content=group.contentView;
            [TSPrefPaneLayout attachRows:rows toView:content];
            [NSLayoutConstraint activateConstraints:@[[content.leadingAnchor constraintEqualToAnchor:group.leadingAnchor],[content.trailingAnchor constraintEqualToAnchor:group.trailingAnchor],[content.topAnchor constraintEqualToAnchor:group.topAnchor],[content.bottomAnchor constraintEqualToAnchor:group.bottomAnchor]]];
            [groups addObject:group];
        }
        NSViewController *controller=[[NSViewController alloc]initWithNibName:nil bundle:nil];controller.title=text(cid);
        controller.view=[[NSView alloc]initWithFrame:NSMakeRect(0,0,700,600)];controller.view.identifier=[@"category." stringByAppendingString:cid];
        [TSPrefPaneLayout attachRows:groups toView:controller.view];[TSPrefPaneLayout decorateGroupsInView:controller.view];
        NSStackView *stack=(NSStackView *)controller.view.subviews.firstObject;stack.spacing=18;stack.edgeInsets=NSEdgeInsetsMake(14,24,24,24);
        for(NSLayoutConstraint *c in stack.constraints.copy)if(c.firstAttribute==NSLayoutAttributeWidth && c.secondItem==stack)c.constant=-48;
        TSSettingsCategory *design=[TSSettingsCategory standardCategoryWithIdentifier:cid];
        NSView *header=[TSPrefPaneLayout categoryHeaderWithTitle:TSCatalogRequired(controller.title) summary:text([cid stringByAppendingString:@".summary"]) symbol:design.symbolName color:design.color];
        [stack insertArrangedSubview:header atIndex:0];[stack setCustomSpacing:8 afterView:header];[header.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-48].active=YES;
        result[cid]=controller;
    }
    // The profile selector has moved to General. Keep its typed owner but no footer band.
    ((NSView *)views[@"settings.settings-footer"]).hidden=YES;
    return result;
}
@end
